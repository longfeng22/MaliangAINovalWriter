package com.ainovel.server.task.events;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

import java.util.HashMap;
import java.util.Map;

import com.ainovel.server.task.event.internal.*;

/**
 * 任务事件发布实现（基础设施层）。
 * 负责承载事件 Sinks，供 SSE 与服务层使用。
 */
@Slf4j
@Component
public class TaskEventPublisherImpl implements TaskEventPublisher {

    // 🔧 修复：使用multicast代替replay，避免历史事件重放导致SSE连接风暴
    // replay会缓存历史事件并在新连接时重放，导致服务重启后前端收到大量重复事件
    private final Sinks.Many<Map<String, Object>> sink = Sinks.many().multicast().onBackpressureBuffer();
    
    // 事件去重：记录最近发送的事件，防止短时间内重复发送
    private final Map<String, Long> recentEventHashes = new java.util.concurrent.ConcurrentHashMap<>();
    private static final long DEDUP_WINDOW_MS = 1000; // 1秒内相同事件视为重复

    @Override
    public Flux<Map<String, Object>> events() {
        return sink.asFlux();
    }

    @Override
    public void publish(Map<String, Object> event) {
        if (event == null) return;
        String type = String.valueOf(event.getOrDefault("type", "TASK_UNKNOWN"));
        String taskId = event.containsKey("taskId") && event.get("taskId") != null ? String.valueOf(event.get("taskId")) : null;
        String taskType = event.containsKey("taskType") && event.get("taskType") != null ? String.valueOf(event.get("taskType")) : null;
        String userId = event.containsKey("userId") && event.get("userId") != null ? String.valueOf(event.get("userId")) : null;

        Map<String, Object> more = new HashMap<>(event);
        more.remove("type");
        more.remove("taskId");
        more.remove("taskType");
        more.remove("userId");
        emit(type, taskId, taskType, userId, more);
    }

    @Override
    public void publish(String type, String taskId, String taskType, String userId, Map<String, Object> more) {
        emit(type, taskId, taskType, userId, more);
    }

    private void emit(String type, String taskId, String taskType, String userId, Map<String, Object> more) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", type);
        m.put("taskId", taskId);
        m.put("taskType", taskType);
        // 回填 userId：事件未带 userId 时，从任务状态服务查询
        if (userId != null) m.put("userId", userId);
        if (more != null) m.putAll(more);
        
        // 🔧 事件去重：生成事件指纹，防止短时间内重复发送
        String eventHash = generateEventHash(type, taskId, userId);
        long now = System.currentTimeMillis();
        Long lastEmitTime = recentEventHashes.get(eventHash);
        
        if (lastEmitTime != null && (now - lastEmitTime) < DEDUP_WINDOW_MS) {
            log.debug("[TASK EVENTS DEDUP] 跳过重复事件: type={} taskId={} timeSinceLastEmit={}ms",
                    type, taskId, now - lastEmitTime);
            return;
        }
        
        try {
            sink.emitNext(m, (signalType, emitResult) -> emitResult == Sinks.EmitResult.FAIL_NON_SERIALIZED);
            recentEventHashes.put(eventHash, now);
            
            // 清理过期的去重记录（保持Map大小可控）
            if (recentEventHashes.size() > 1000) {
                cleanupExpiredDedup(now);
            }
            
            log.info("[TASK EVENTS EMIT] type={} taskId={} taskType={} hasResult={} parentTaskId={}",
                    type, taskId, taskType, m.containsKey("result"), m.get("parentTaskId"));
        } catch (Exception ex) {
            log.warn("[TASK EVENTS EMIT FAIL] type={} taskId={} taskType={} keys={} error={}",
                    type, taskId, taskType, m.keySet(), ex.toString());
        }
    }
    
    private String generateEventHash(String type, String taskId, String userId) {
        return String.format("%s:%s:%s", type, taskId, userId);
    }
    
    private void cleanupExpiredDedup(long now) {
        recentEventHashes.entrySet().removeIf(entry -> 
            (now - entry.getValue()) > DEDUP_WINDOW_MS * 10 // 保留10倍窗口期
        );
    }

    // 监听内部事件并转发到统一 Publisher
    @EventListener
    public void onSubmitted(TaskSubmittedEvent e) {
        // 拆书任务不发送SUBMITTED事件，只发送完成/失败事件
        if (isBookExtractionTask(e.getTaskType())) {
            log.debug("[TASK EVENTS] 拆书任务不发送SUBMITTED事件: taskType={} taskId={}", e.getTaskType(), e.getTaskId());
            return;
        }
        
        Map<String, Object> more = new HashMap<>();
        if (e.getParentTaskId() != null) {
            more.put("parentTaskId", e.getParentTaskId());
        }
        String novelId = tryExtractNovelId(e.getParameters());
        if (novelId != null) {
            more.put("novelId", novelId);
        }
        publish("TASK_SUBMITTED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
    }

    @EventListener
    public void onStarted(TaskStartedEvent e) {
        // 拆书任务不发送STARTED事件，只发送完成/失败事件
        if (isBookExtractionTask(e.getTaskType())) {
            log.debug("[TASK EVENTS] 拆书任务不发送STARTED事件: taskType={} taskId={}", e.getTaskType(), e.getTaskId());
            return;
        }
        
        Map<String, Object> more = new HashMap<>();
        more.put("executionNodeId", e.getExecutionNodeId());
        publish("TASK_STARTED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
    }

    @EventListener
    public void onProgress(TaskProgressEvent e) {
        // 拆书任务不发送PROGRESS事件，只发送完成/失败事件
        if (isBookExtractionTask(e.getTaskType())) {
            log.debug("[TASK EVENTS] 拆书任务不发送PROGRESS事件: taskType={} taskId={}", e.getTaskType(), e.getTaskId());
            return;
        }
        
        Map<String, Object> more = new HashMap<>();
        more.put("progress", e.getProgressData());
        publish("TASK_PROGRESS", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
    }

    @EventListener
    public void onCompleted(TaskCompletedEvent e) {
        // 拆书任务始终发送COMPLETED事件（用于通知前端）
        Map<String, Object> more = new HashMap<>();
        if (e.getResult() != null) more.put("result", e.getResult());
        String novelId = tryExtractNovelId(e.getResult());
        if (novelId != null) {
            more.put("novelId", novelId);
        }
        
        if (isBookExtractionTask(e.getTaskType())) {
            log.info("[TASK EVENTS] 拆书任务完成，发送COMPLETED事件: taskType={} taskId={}", e.getTaskType(), e.getTaskId());
        }
        
        publish("TASK_COMPLETED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
    }

    @EventListener
    public void onFailed(TaskFailedEvent e) {
        // 拆书任务始终发送FAILED事件（用于通知前端）
        Map<String, Object> more = new HashMap<>();
        if (e.getErrorInfo() != null) more.put("error", e.getErrorInfo());
        more.put("deadLetter", e.isDeadLetter());
        
        if (isBookExtractionTask(e.getTaskType())) {
            log.info("[TASK EVENTS] 拆书任务失败，发送FAILED事件: taskType={} taskId={}", e.getTaskType(), e.getTaskId());
        }
        
        publish("TASK_FAILED", e.getTaskId(), e.getTaskType(), e.getUserId(), more);
    }

    @EventListener
    public void onCancelled(TaskCancelledEvent e) {
        publish("TASK_CANCELLED", e.getTaskId(), e.getTaskType(), e.getUserId(), new HashMap<>());
    }

    private String tryExtractNovelId(Object obj) {
        if (obj == null) return null;
        try {
            // 1) 反射读取 getNovelId()
            var method = obj.getClass().getMethod("getNovelId");
            Object val = method.invoke(obj);
            if (val != null) return String.valueOf(val);
        } catch (Throwable ignore) {}
        try {
            // 2) Map 结构读取 key="novelId"
            if (obj instanceof Map<?, ?> map) {
                Object val = map.get("novelId");
                if (val != null) return String.valueOf(val);
            }
        } catch (Throwable ignore) {}
        return null;
    }
    
    /**
     * 判断是否为拆书任务类型
     * 拆书任务不需要在AI任务中心显示，只需要通知完成/失败状态
     */
    private boolean isBookExtractionTask(String taskType) {
        if (taskType == null) return false;
        return taskType.equals("KNOWLEDGE_EXTRACTION_FANQIE") || 
               taskType.equals("KNOWLEDGE_EXTRACTION_TEXT") || 
               taskType.equals("KNOWLEDGE_EXTRACTION_GROUP");
    }
}



