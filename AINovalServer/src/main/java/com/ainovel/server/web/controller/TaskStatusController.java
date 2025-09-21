package com.ainovel.server.web.controller;

import com.ainovel.server.security.CurrentUser;
import com.ainovel.server.task.event.internal.*;
import com.ainovel.server.task.model.TaskStatus;
import com.ainovel.server.task.service.TaskSubmissionService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 任务状态与事件（SSE）控制器
 * 路由前缀：/api/v1/api/tasks
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/api/tasks")
@RequiredArgsConstructor
public class TaskStatusController {

    private final TaskSubmissionService taskSubmissionService;
    private final TaskSseBroker taskSseBroker;

    /**
     * 查询任务状态
     */
    @GetMapping("/{taskId}/status")
    public Mono<ResponseEntity<Object>> getTaskStatus(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable("taskId") String taskId) {
        final String userId = currentUser != null ? currentUser.getId() : null;
        return taskSubmissionService.getTaskStatus(taskId, userId)
                .map(body -> {
                    try {
                        Object status = (body instanceof Map<?,?>) ? ((Map<?,?>) body).get("status") : null;
                        boolean hasResult = (body instanceof Map<?,?>) && ((Map<?,?>) body).containsKey("result");
                        log.info("[GET STATUS] taskId={} status={} hasResult={}", taskId, status, hasResult);
                    } catch (Throwable ignore) {}
                    return ResponseEntity.ok(body);
                })
                .onErrorResume(e -> {
                    log.error("获取任务状态失败: taskId={} error={}", taskId, e.getMessage(), e);
                    return Mono.just(ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                            "taskId", taskId,
                            "error", e.getMessage()
                    )));
                });
    }

    /**
     * 获取用户历史任务列表（支持分页和状态过滤）
     */
    @GetMapping("/list")
    public Mono<ResponseEntity<List<Map<String, Object>>>> getUserTasks(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(value = "status", required = false) String statusParam,
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "50") int size) {
        
        final String userId = currentUser != null ? currentUser.getId() : null;
        if (userId == null) {
            return Mono.just(ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(List.of()));
        }
        
        TaskStatus status = null;
        if (statusParam != null && !statusParam.isBlank()) {
            try {
                status = TaskStatus.valueOf(statusParam.toUpperCase());
            } catch (IllegalArgumentException e) {
                log.warn("无效的任务状态参数: {}", statusParam);
                return Mono.just(ResponseEntity.badRequest().body(List.of()));
            }
        }
        
        log.info("获取用户历史任务: userId={}, status={}, page={}, size={}", 
                userId, status, page, size);
        
        return taskSubmissionService.getUserTasks(userId, status, page, size)
                .map(task -> {
                    // 将BackgroundTask转换为前端友好的格式
                    Map<String, Object> taskData = new HashMap<>();
                    taskData.put("taskId", task.getId());
                    taskData.put("taskType", task.getTaskType());
                    taskData.put("type", mapTaskStatusToEventType(task.getStatus()));
                    taskData.put("status", task.getStatus());
                    taskData.put("userId", task.getUserId());
                    taskData.put("parentTaskId", task.getParentTaskId());
                    taskData.put("parameters", task.getParameters());
                    taskData.put("progress", task.getProgress());
                    taskData.put("result", task.getResult());
                    taskData.put("errorInfo", task.getErrorInfo());
                    taskData.put("ts", task.getTimestamps().getUpdatedAt() != null 
                            ? task.getTimestamps().getUpdatedAt().toEpochMilli() 
                            : task.getTimestamps().getCreatedAt().toEpochMilli());
                    
                    return taskData;
                })
                .collectList()
                .map(taskList -> {
                    log.info("成功获取用户历史任务: userId={}, count={}", userId, taskList.size());
                    return ResponseEntity.ok(taskList);
                })
                .onErrorResume(e -> {
                    log.error("获取用户历史任务失败: userId={}, error={}", userId, e.getMessage(), e);
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(List.of()));
                });
    }
    
    /**
     * 将任务状态映射为SSE事件类型
     */
    private String mapTaskStatusToEventType(TaskStatus status) {
        return switch (status) {
            case QUEUED -> "TASK_SUBMITTED";
            case RUNNING -> "TASK_STARTED";
            case COMPLETED -> "TASK_COMPLETED";
            case FAILED, DEAD_LETTER -> "TASK_FAILED";
            case CANCELLED -> "TASK_CANCELLED";
            default -> "TASK_UNKNOWN";
        };
    }

    /**
     * 用户任务事件 SSE 流
     * 使用 GET + text/event-stream（标准范式）。
     */
    @GetMapping(path = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<Map<String, Object>> streamTaskEvents(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(value = "userId", required = false) String userIdParam) {
        final String userId = (userIdParam != null && !userIdParam.isBlank())
                ? userIdParam
                : (currentUser != null ? currentUser.getId() : null);

        log.info("SSE 订阅任务事件: userId={}", userId);
        // 过滤到当前用户的事件，并设置心跳，防止中间层断开
        return taskSseBroker.events()
                .filter(ev -> {
                    Object uid = ev.get("userId");
                    boolean pass = (userId == null) || (uid != null && userId.equals(String.valueOf(uid)));
                    if (!pass) {
                        log.debug("[SSE FILTER MISS] expectUserId={} actualUserId={}", userId, uid);
                    }
                    return pass;
                })
                .map(ev -> {
                    try {
                        Object type = ev.get("type");
                        Object taskId = ev.get("taskId");
                        Object parent = ev.get("parentTaskId");
                        Object uid = ev.get("userId");
                        boolean hasResult = ev.containsKey("result");
                        Object result = ev.get("result");
                        log.info("[SSE OUT] type={} taskId={} parentTaskId={} userId={} hasResult={} result ={}", type, taskId, parent, uid, hasResult,result.toString());
                    } catch (Throwable ignore) {}
                    return ev;
                })
                .mergeWith(Flux.interval(Duration.ofSeconds(20))
                        .map(tick -> Map.of("type", "HEARTBEAT", "ts", System.currentTimeMillis())))
                .onErrorResume(e -> {
                    log.error("SSE 任务事件流错误: {}", e.getMessage(), e);
                    return Flux.empty();
                });
    }

    /**
     * 简单的应用内 SSE broker：监听内部任务事件并广播成 Map。
     */
    @Component
    @Slf4j
    public static class TaskSseBroker {
        // 使用可回放的 Sinks，避免在无订阅者或订阅尚未建立时丢事件
        private final Sinks.Many<Map<String, Object>> sink = Sinks.many().replay().limit(256);
        private final com.ainovel.server.task.service.TaskStateService taskStateService;

        public TaskSseBroker(com.ainovel.server.task.service.TaskStateService taskStateService) {
            this.taskStateService = taskStateService;
        }

        public Flux<Map<String, Object>> events() {
            return sink.asFlux();
        }

        /**
         * 对外发布统一任务事件（供跨进程桥接使用，如 RabbitMQ 转发）。
         * 将复用内部 emit 逻辑，自动补全 userId 与 parentTaskId 等信息。
         */
        public void publish(String type, String taskId, String taskType, String userId, Map<String, Object> more) {
            emit(type, taskId, taskType, userId, more);
        }

        /**
         * 对外发布统一任务事件（Map 版本）。
         * 识别常用字段并复用 emit 逻辑；其余字段放入 more。
         */
        public void publish(Map<String, Object> event) {
            if (event == null) return;
            String type = String.valueOf(event.getOrDefault("type", "TASK_UNKNOWN"));
            String taskId = event.get("taskId") != null ? String.valueOf(event.get("taskId")) : null;
            String taskType = event.get("taskType") != null ? String.valueOf(event.get("taskType")) : null;
            String userId = event.get("userId") != null ? String.valueOf(event.get("userId")) : null;

            Map<String, Object> more = new HashMap<>(event);
            more.remove("type");
            more.remove("taskId");
            more.remove("taskType");
            more.remove("userId");
            emit(type, taskId, taskType, userId, more);
        }

        private void emit(String type, String taskId, String taskType, String userId, Map<String, Object> more) {
            Map<String, Object> m = new HashMap<>();
            m.put("type", type);
            m.put("taskId", taskId);
            m.put("taskType", taskType);
            // 回填 userId：事件未带 userId 时，从任务状态服务查询
            String effectiveUserId = userId != null ? userId : tryGetUserId(taskId);
            if (effectiveUserId != null) m.put("userId", effectiveUserId);
            if (more != null) m.putAll(more);
            try {
                sink.emitNext(m, (signalType, emitResult) -> {
                    // 对并发导致的 FAIL_NON_SERIALIZED 进行忙等重试
                    if (emitResult == Sinks.EmitResult.FAIL_NON_SERIALIZED) {
                        return true; // 重试
                    }
                    // 其他错误不重试，交由外层记录
                    return false;
                });
                log.info("[SSE EMIT OK] type={} taskId={} taskType={} hasResult={} parentTaskId={}", type, taskId, taskType, m.containsKey("result"), m.get("parentTaskId"));
            } catch (Exception ex) {
                // 兜底：记录精确失败原因
                log.warn("[SSE EMIT FAIL] type={} taskId={} taskType={} payloadKeys={} error={}", type, taskId, taskType, m.keySet(), ex.toString());
            }
        }

        private String tryExtractNovelId(Object obj) {
            if (obj == null) return null;
            try {
                var method = obj.getClass().getMethod("getNovelId");
                Object val = method.invoke(obj);
                return val != null ? val.toString() : null;
            } catch (Throwable ignore) {
                return null;
            }
        }

        private String tryGetParentTaskId(String taskId) {
            try {
                var taskMono = taskStateService.getTask(taskId);
                var task = taskMono.block();
                if (task != null && task.getParentTaskId() != null) {
                    return task.getParentTaskId();
                }
            } catch (Throwable ignore) {}
            return null;
        }

        private String tryGetUserId(String taskId) {
            try {
                var taskMono = taskStateService.getTask(taskId);
                var task = taskMono.block();
                if (task != null && task.getUserId() != null) {
                    return task.getUserId();
                }
            } catch (Throwable ignore) {}
            return null;
        }

        @EventListener
        public void onSubmitted(TaskSubmittedEvent e) {
            String novelId = tryExtractNovelId(e.getParameters());
            Map<String, Object> more = new HashMap<>();
            if (novelId != null) {
                more.put("novelId", novelId);
            }
            String parentId = tryGetParentTaskId(e.getTaskId());
            if (parentId != null) more.put("parentTaskId", parentId);
            emit("TASK_SUBMITTED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
        }

        @EventListener
        public void onStarted(TaskStartedEvent e) {
            Map<String, Object> more = new HashMap<>();
            more.put("executionNodeId", e.getExecutionNodeId());
            String parentId = tryGetParentTaskId(e.getTaskId());
            if (parentId != null) more.put("parentTaskId", parentId);
            emit("TASK_STARTED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
        }

        @EventListener
        public void onProgress(TaskProgressEvent e) {
            Map<String, Object> more = new HashMap<>();
            more.put("progress", e.getProgressData());
            String parentId = tryGetParentTaskId(e.getTaskId());
            if (parentId != null) more.put("parentTaskId", parentId);
            emit("TASK_PROGRESS", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
        }

        @EventListener
        public void onCompleted(TaskCompletedEvent e) {
            Map<String, Object> more = new HashMap<>();
            if (e.getResult() != null) more.put("result", e.getResult());
            // 尝试从result中提取 novelId（若有）
            String novelId = tryExtractNovelId(e.getResult());
            if (novelId != null) {
                more.put("novelId", novelId);
            }
            String parentId = tryGetParentTaskId(e.getTaskId());
            if (parentId != null) more.put("parentTaskId", parentId);
            try {
                Object result = e.getResult();
                String keys = result == null ? "-" : String.join(",", ((Map<?,?>) result).keySet().stream().map(Object::toString).toList());
                log.info("[TASK COMPLETED] taskId={} taskType={} userId={} parentTaskId={} novelId={} resultKeys={}",
                        e.getTaskId(), e.getTaskType(), e.getUserId(), parentId, novelId, keys);
            } catch (Throwable t) {
                log.info("[TASK COMPLETED] taskId={} taskType={} userId={} parentTaskId={} novelId={}",
                        e.getTaskId(), e.getTaskType(), e.getUserId(), parentId, novelId);
            }
            emit("TASK_COMPLETED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
        }

        @EventListener
        public void onFailed(TaskFailedEvent e) {
            Map<String, Object> more = new HashMap<>();
            if (e.getErrorInfo() != null) more.put("error", e.getErrorInfo());
            more.put("deadLetter", e.isDeadLetter());
            emit("TASK_FAILED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
        }

        @EventListener
        public void onCancelled(TaskCancelledEvent e) {
            emit("TASK_CANCELLED", e.getTaskId(), e.getTaskType(), e.getUserId(), Map.of());
        }
    }
}


