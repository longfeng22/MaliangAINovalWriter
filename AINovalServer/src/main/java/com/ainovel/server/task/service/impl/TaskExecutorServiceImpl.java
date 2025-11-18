package com.ainovel.server.task.service.impl;

import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.TaskContextImpl;
import com.ainovel.server.task.service.TaskExecutorService;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.ExecutionResult;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeoutException;
import java.util.stream.Collectors;

/**
 * 任务执行器服务响应式实现类
 */
@Service
public class TaskExecutorServiceImpl implements TaskExecutorService {

    private static final Logger logger = LoggerFactory.getLogger(TaskExecutorServiceImpl.class);
    
    private final Map<String, BackgroundTaskExecutable<?, ?>> executors = new HashMap<>();
    private final TaskStateService taskStateService;
    
    /**
     * 构造函数，注入所有BackgroundTaskExecutable实现
     * 
     * @param executables 任务执行器列表
     * @param taskStateService 任务状态服务
     */
    @Autowired
    public TaskExecutorServiceImpl(List<BackgroundTaskExecutable<?, ?>> executables, TaskStateService taskStateService) {
        this.taskStateService = taskStateService;
        for (BackgroundTaskExecutable<?, ?> executable : executables) {
            // ✅ 使用 getSupportedTaskTypes() 支持多任务类型执行器
            List<String> supportedTypes = executable.getSupportedTaskTypes();
            for (String taskType : supportedTypes) {
                executors.put(taskType, executable);
                logger.info("已注册任务执行器: {} (执行器类: {})", 
                    taskType, executable.getClass().getSimpleName());
            }
        }
    }
    
    @Override
    @SuppressWarnings("unchecked")
    public <P, R> Mono<BackgroundTaskExecutable<P, R>> findExecutor(String taskType) {
        BackgroundTaskExecutable<?, ?> executor = executors.get(taskType);
        if (executor == null) {
            logger.warn("找不到任务类型'{}'的执行器", taskType);
            return Mono.empty();
        }
        // 使用不安全的转换，由调用者确保类型安全
        BackgroundTaskExecutable<P, R> typedExecutor = (BackgroundTaskExecutable<P, R>) executor;
        return Mono.just(typedExecutor);
    }
    
    @Override
    public <P, R> Mono<ExecutionResult<R>> executeTask(BackgroundTaskExecutable<P, R> executable, TaskContext<P> context) {
        logger.debug("开始执行任务类型: {}, 任务ID: {}", executable.getTaskType(), context.getTaskId());
        
        long startTime = System.currentTimeMillis();
        
        return executable.execute(context)
            .map(result -> {
                long executionTime = System.currentTimeMillis() - startTime;
                logger.debug("任务执行成功: {}, 任务ID: {}, 耗时: {}ms", executable.getTaskType(), context.getTaskId(), executionTime);
                return ExecutionResult.success(result);
            })
            .onErrorResume(e -> {
                long executionTime = System.currentTimeMillis() - startTime;
                logger.error("任务执行失败: {}, 任务ID: {}, 错误: {}", executable.getTaskType(), context.getTaskId(), e.getMessage(), e);
                
                if (isRetryableException(e)) {
                    logger.warn("任务失败可重试: taskId={}, error={}", context.getTaskId(), e.getMessage());
                    return Mono.just(ExecutionResult.retryableFailure(e));
                } else {
                    logger.error("任务失败不可重试: taskId={}, error={}", context.getTaskId(), e.getMessage());
                    return Mono.just(ExecutionResult.nonRetryableFailure(e));
                }
            });
    }
    
    @Override
    public Mono<Void> cancelTask(String taskId) {
        return taskStateService.getTask(taskId)
            .flatMap(task -> {
                String taskType = task.getTaskType();
                return findExecutor(taskType)
                    .flatMap(executable -> {
                        if (!executable.isCancellable()) {
                            logger.info("任务类型{}不支持取消", taskType);
                            return Mono.empty();
                        }
                        
                        // 创建一个最小上下文
                        TaskContext<?> context = TaskContextImpl.builder()
                            .taskId(taskId)
                            .taskType(taskType)
                            .userId(task.getUserId())
                            .parameters(task.getParameters())
                            .build();
                        
                        return executable.cancel(context)
                            .then(taskStateService.recordCancellation(taskId));
                    })
                    .switchIfEmpty(Mono.error(new IllegalStateException("无法找到或无法取消任务执行器: " + taskType)));
            })
            .switchIfEmpty(Mono.error(new IllegalStateException("无法找到任务: " + taskId)));
    }
    
    @Override
    public <P> Mono<Integer> getEstimatedExecutionTime(String taskType, TaskContext<P> context) {
        return this.<P, Object>findExecutor(taskType)
            .map(executable -> executable.getEstimatedExecutionTimeSeconds(context))
            .defaultIfEmpty(60); // 默认1分钟
    }
    
    /**
     * 判断异常是否可重试
     * 
     * @param throwable 异常
     * @return 如果可重试返回true，否则返回false
     */
    private boolean isRetryableException(Throwable throwable) {
        if (throwable instanceof java.net.SocketTimeoutException || 
            throwable instanceof TimeoutException ||
            throwable instanceof java.io.IOException) {
             return true;
        }
        
        String message = throwable.getMessage();
        if (message != null) {
            message = message.toLowerCase();
            return message.contains("timeout") ||
                   message.contains("connection reset") ||
                   message.contains("connection refused") ||
                   message.contains("temporary unavailable") ||
                   message.contains("overloaded") ||
                   message.contains("rate limit") ||
                   message.contains("throttled") ||
                   message.contains("please retry");
        }

        return false;
    }
    
    /**
     * 获取已注册的任务类型列表
     * 
     * @return 任务类型列表
     */
    public List<String> getRegisteredTaskTypes() {
        return executors.keySet().stream().collect(Collectors.toList());
    }
} 