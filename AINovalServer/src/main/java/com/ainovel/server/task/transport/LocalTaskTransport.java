package com.ainovel.server.task.transport;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.service.TaskExecutorService;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.TaskContextImpl;
import com.ainovel.server.task.ExecutionResult;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;
import lombok.extern.slf4j.Slf4j;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.config.TaskConversionConfig;
import com.ainovel.server.task.event.internal.TaskStartedEvent;
import com.ainovel.server.task.event.internal.TaskCompletedEvent;
import com.ainovel.server.task.event.internal.TaskFailedEvent;
import com.ainovel.server.task.event.internal.TaskRetryingEvent;
import com.ainovel.server.task.event.internal.TaskCancelledEvent;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.core.publisher.Sinks;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 本地内存传输实现：使用 Reactor Sinks.Many 作为本地任务队列，多个并发消费者执行。
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "task.transport", havingValue = "local")
public class LocalTaskTransport implements TaskTransport {

    private final TaskStateService taskStateService;
    private final TaskExecutorService taskExecutorService;
    private final ApplicationEventPublisher eventPublisher;
    private final TaskSubmissionService taskSubmissionService;
    private final TaskConversionConfig taskConversionConfig;

    // 无界多播 sink（背压策略：buffer），用于本地队列
    private final Sinks.Many<String> taskSink;
    private final int concurrency;
    private final AtomicBoolean started = new AtomicBoolean(false);
    private Disposable consumerSubscription;
    private final String executionNodeId = "local-node";
    private final long[] retryDelays;

    @Autowired
    public LocalTaskTransport(TaskStateService taskStateService,
                              TaskExecutorService taskExecutorService,
                              ApplicationEventPublisher eventPublisher,
                              TaskSubmissionService taskSubmissionService,
                              TaskConversionConfig taskConversionConfig,
                              @org.springframework.beans.factory.annotation.Value("${task.local.concurrency:4}") int concurrency,
                              @org.springframework.beans.factory.annotation.Value("${task.retry.delays:15000,60000,300000}") String retryDelaysStr) {
        this.taskStateService = taskStateService;
        this.taskExecutorService = taskExecutorService;
        this.eventPublisher = eventPublisher;
        this.taskSubmissionService = taskSubmissionService;
        this.taskConversionConfig = taskConversionConfig;
        // ✅ 修复：使用 multicast() 替代 unicast()，支持并发提交任务
        // unicast() 只支持单订阅者且不支持并发写入，会导致 FAIL_NON_SERIALIZED 错误
        this.taskSink = Sinks.many().multicast().onBackpressureBuffer();
        this.concurrency = Math.max(1, concurrency);
        this.retryDelays = parseRetryDelays(retryDelaysStr);
        startConsumersIfNeeded();
    }

    @Override
    public Mono<Void> dispatchTask(String taskId, String userId, String taskType, Object parameters) {
        return Mono.fromRunnable(() -> {
            // ✅ 并发写入重试机制：在 FAIL_NON_SERIALIZED 时自动重试
            // multicast() Sink 在高并发下可能出现序列化冲突，需要重试
            int maxRetries = 100; // 最多重试100次
            int retryCount = 0;
            
            while (retryCount < maxRetries) {
                Sinks.EmitResult result = taskSink.tryEmitNext(taskId);
                
                if (result.isSuccess()) {
                    if (retryCount > 0) {
                        log.debug("任务入队成功（重试{}次）: taskId={}", retryCount, taskId);
                    }
                    return; // 成功，退出
                }
                
                if (result == Sinks.EmitResult.FAIL_NON_SERIALIZED) {
                    // 并发冲突，短暂等待后重试
                    retryCount++;
                    try {
                        Thread.sleep(1); // 等待1毫秒
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new IllegalStateException("Task dispatch interrupted: " + taskId, e);
                    }
                } else {
                    // 其他错误，直接失败（不打印堆栈，因为是业务异常）
                    log.error("本地队列入队失败: taskId={}, result={}, retries={}", taskId, result, retryCount);
                    throw new IllegalStateException("Local task queue emit failed: " + result);
                }
            }
            
            // 超过最大重试次数（不打印堆栈，因为是业务异常）
            log.error("本地队列入队失败（超过最大重试次数）: taskId={}, maxRetries={}", taskId, maxRetries);
            throw new IllegalStateException("Local task queue emit failed after " + maxRetries + " retries");
        });
    }

    @Override
    public Mono<Void> dispatchDelayedRetryTask(String taskId, String userId, String taskType, Object parameters, int retryCount, long delayMillis) {
        return Mono.delay(Duration.ofMillis(Math.max(0, delayMillis)))
                .then(dispatchTask(taskId, userId, taskType, parameters));
    }

    private void startConsumersIfNeeded() {
        if (started.compareAndSet(false, true)) {
            consumerSubscription = taskSink.asFlux()
                .publishOn(Schedulers.boundedElastic())
                .flatMap(this::processTaskIdSafely, concurrency)
                .onErrorContinue((e, v) -> log.error("本地队列消费异常: {}, value={}", e.toString(), v, e))
                .subscribe();
            log.info("LocalTaskTransport 启动并发消费者: {}", concurrency);
        }
    }

    private Mono<Void> processTaskIdSafely(String taskId) {
        return processTask(taskId)
            .onErrorResume(e -> {
                log.error("处理本地任务失败: taskId={}, error={}", taskId, e.getMessage(), e);
                return Mono.empty();
            });
    }

    private Mono<Void> processTask(String taskId) {
        // 与 TaskConsumer.processMessageReactively 类似的执行管道（简化版）
        return taskStateService.getTask(taskId)
            .switchIfEmpty(Mono.error(new IllegalStateException("任务不存在: " + taskId)))
            .flatMap(task -> {
                if (task.getStatus() == null) {
                    return Mono.error(new IllegalStateException("任务状态为null: " + taskId));
                }
                if (task.getStatus() == TaskStatus.RUNNING) {
                    return Mono.empty();
                }
                if (task.getStatus() != TaskStatus.QUEUED && task.getStatus() != TaskStatus.RETRYING) {
                    return Mono.empty();
                }
                return taskStateService.trySetRunning(taskId, executionNodeId)
                    .flatMap(updated -> {
                        if (!updated) return Mono.empty();
                        eventPublisher.publishEvent(new TaskStartedEvent(this, taskId, task.getTaskType(), task.getUserId(), executionNodeId, task.getParentTaskId()));
                        return executeTask(task);
                    });
            });
    }

    private Mono<Void> executeTask(BackgroundTask task) {
        final String taskId = task.getId();
        final String taskType = task.getTaskType();

        return taskExecutorService.findExecutor(taskType)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("找不到任务类型为 " + taskType + " 的执行器")))
            .flatMap(executable ->
                taskConversionConfig.convertParametersToType(taskType, task.getParameters())
                    .flatMap(typedParams -> {
                        TaskContext<?> context = TaskContextImpl.builder()
                            .taskId(taskId)
                            .taskType(taskType)
                            .userId(task.getUserId())
                            .parameters(typedParams)
                            .executionNodeId(executionNodeId)
                            .parentTaskId(task.getParentTaskId())
                            .taskStateService(taskStateService)
                            .taskSubmissionService(taskSubmissionService)
                            .eventPublisher(eventPublisher)
                            .build();
                        return taskExecutorService.executeTask((BackgroundTaskExecutable<Object, Object>) executable, (TaskContext<Object>) context)
                            .flatMap(result -> handleResult(task, result));
                    })
            );
    }

    @SuppressWarnings("unchecked")
    private Mono<Void> handleResult(BackgroundTask task, ExecutionResult<?> result) {
        if (result.isSuccess()) {
            try {
                // 父任务 CONTINUE_WRITING_CONTENT 的初始结果通常为 RUNNING，不应立即标记完成
                if ("CONTINUE_WRITING_CONTENT".equals(task.getTaskType()) && result.getResult() instanceof com.ainovel.server.task.dto.continuecontent.ContinueWritingContentResult cResult) {
                    if (cResult.getStatus() == TaskStatus.RUNNING) {
                        log.info("父任务初始结果为 RUNNING，记录进度，不发布 Completed: taskId={}", task.getId());
                        return taskStateService.recordProgress(task.getId(), cResult);
                    }
                }
            } catch (Throwable ignore) {}

            // 其他任务：先持久化，再发布 Completed 事件（与 Rabbit 流程保持一致）
            return taskStateService.recordCompletion(task.getId(), result.getResult())
                    .doOnSuccess(v -> eventPublisher.publishEvent(new TaskCompletedEvent(this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId(), result.getResult())));
        } else if (result.isRetryable()) {
            long delay = getRetryDelay(task.getRetryCount());
            int nextRetry = task.getRetryCount() + 1;
            Instant nextAt = Instant.now().plusMillis(delay);
            eventPublisher.publishEvent(new TaskRetryingEvent(this, task.getId(), task.getTaskType(), task.getUserId(), nextRetry, nextRetry, delay, createErrorInfoMap(result.getError())));
            return taskStateService.recordRetrying(task.getId(), nextRetry, result.getError(), nextAt)
                .then(dispatchDelayedRetryTask(task.getId(), task.getUserId(), task.getTaskType(), task.getParameters(), nextRetry, delay));
        } else if (result.isNonRetryable()) {
            Map<String, Object> errorInfo = Map.of(
                "message", result.getError() != null ? result.getError().getMessage() : "non-retryable",
                "exceptionClass", result.getError() != null ? result.getError().getClass().getName() : ""
            );
            eventPublisher.publishEvent(new TaskFailedEvent(this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId(), errorInfo, false));
            return taskStateService.recordFailure(task.getId(), errorInfo, false);
        } else if (result.isCancelled()) {
            eventPublisher.publishEvent(new TaskCancelledEvent(this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId()));
            return taskStateService.recordCancellation(task.getId());
        }
        return Mono.error(new IllegalStateException("未知的任务结果状态"));
    }

    private long[] parseRetryDelays(String str) {
        String[] parts = str.split(",");
        long[] arr = new long[parts.length];
        for (int i = 0; i < parts.length; i++) {
            try {
                arr[i] = Long.parseLong(parts[i].trim());
            } catch (Exception e) {
                arr[i] = 15000L;
            }
        }
        return arr.length > 0 ? arr : new long[]{15000L, 60000L, 300000L};
    }

    private long getRetryDelay(int retryCount) {
        if (retryCount >= 0 && retryCount < retryDelays.length) return retryDelays[retryCount];
        return retryDelays[retryDelays.length - 1];
    }

    private Map<String, Object> createErrorInfoMap(Throwable error) {
        Map<String, Object> errorInfo = new java.util.HashMap<>();
        if (error != null) {
            errorInfo.put("message", error.getMessage());
            errorInfo.put("exceptionClass", error.getClass().getName());
            StackTraceElement[] st = error.getStackTrace();
            if (st != null && st.length > 0) {
                String[] tops = new String[Math.min(st.length, 10)];
                for (int i = 0; i < tops.length; i++) tops[i] = st[i].toString();
                errorInfo.put("stackTrace", tops);
            }
            Throwable cause = error.getCause();
            if (cause != null && cause != error) {
                Map<String, String> causeInfo = new java.util.HashMap<>();
                causeInfo.put("message", cause.getMessage());
                causeInfo.put("exceptionClass", cause.getClass().getName());
                errorInfo.put("cause", causeInfo);
            }
        }
        errorInfo.putIfAbsent("timestamp", Instant.now().toString());
        return errorInfo;
    }
}


