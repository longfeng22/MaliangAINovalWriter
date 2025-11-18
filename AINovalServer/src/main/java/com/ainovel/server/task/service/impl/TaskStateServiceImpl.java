package com.ainovel.server.task.service.impl;

import java.time.Instant;
import java.time.Duration;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Service;
import com.ainovel.server.task.events.TaskEventPublisher;

import com.ainovel.server.repository.BackgroundTaskRepository;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;
import com.ainovel.server.task.service.TaskStateService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * TaskStateService接口的响应式实现
 */
@Slf4j
@Service
public class TaskStateServiceImpl implements TaskStateService {
    
    private final BackgroundTaskRepository taskRepository;
    private final ReactiveMongoTemplate mongoTemplate;
    private final ObjectMapper objectMapper;
    
    private final TaskEventPublisher taskEventPublisher;

    // 内部缓存：用户任务列表（父任务分页 + 子任务扁平化后的序列）
    // key 结构：userId:statusOrStar:page:size
    private final Cache<String, java.util.List<BackgroundTask>> userTasksCache = Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofSeconds(60))
            .maximumSize(1000)
            .build();

    @Autowired
    public TaskStateServiceImpl(BackgroundTaskRepository taskRepository, 
                             ReactiveMongoTemplate mongoTemplate,
                             ObjectMapper objectMapper,
                             TaskEventPublisher taskEventPublisher) {
        this.taskRepository = taskRepository;
        this.mongoTemplate = mongoTemplate;
        this.objectMapper = objectMapper;
        this.taskEventPublisher = taskEventPublisher;
    }

    @Override
    public Mono<String> createTask(String userId, String taskType, Object parameters, String parentTaskId) {
        return createSubTask(userId, taskType, parameters, parentTaskId)
                .map(BackgroundTask::getId);
    }
    
    /**
     * 创建无父任务的后台任务
     * 此方法是一个便捷方法，内部调用createSubTask，简单封装了一下
     * 
     * @param userId 用户ID
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @return 创建的任务实体
     */
    public Mono<BackgroundTask> createTask(String userId, String taskType, Object parameters) {
        return createSubTask(userId, taskType, parameters, null);
    }
    
    @Override
    public Mono<BackgroundTask> createSubTask(String userId, String taskType, Object parameters, String parentTaskId) {
        BackgroundTask task = new BackgroundTask();
        task.setId(UUID.randomUUID().toString());
        task.setUserId(userId);
        task.setTaskType(taskType);
        task.setStatus(TaskStatus.QUEUED);
        task.setParameters(parameters);
        task.setParentTaskId(parentTaskId);
        task.setRetryCount(0);
        
        // 设置时间戳
        BackgroundTask.TaskTimestamps timestamps = new BackgroundTask.TaskTimestamps();
        Instant now = Instant.now();
        timestamps.setCreatedAt(now);
        timestamps.setUpdatedAt(now);
        task.setTimestamps(timestamps);
        
        return taskRepository.save(task);
    }
    
    /**
     * 通过ID查找任务
     * 
     * @param taskId 任务ID
     * @return 包含任务的Mono，如果找不到则返回empty
     */
    public Mono<BackgroundTask> findById(String taskId) {
        return taskRepository.findById(taskId);
    }
    
    @Override
    public Mono<Boolean> trySetRunning(String taskId) {
        return trySetRunning(taskId, "default-node");
    }
    
    @Override
    public Mono<Boolean> trySetRunning(String taskId, String executionNodeId) {
        Instant now = Instant.now();
        
        // 使用原子性查询和更新操作
        Query query = new Query(Criteria.where("_id").is(taskId)
                                   .and("status").in(TaskStatus.QUEUED, TaskStatus.RETRYING));
        
        Update update = new Update()
                .set("status", TaskStatus.RUNNING)
                .set("executionNodeId", executionNodeId)
                .set("lastAttemptTimestamp", now)
                .set("timestamps.startedAt", now)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.findAndModify(query, update, BackgroundTask.class)
                .map(task -> true)
                .defaultIfEmpty(false)
                .onErrorResume(e -> {
                    log.error("Error when trying to set task {} to running state: {}", taskId, e.getMessage());
                    return Mono.just(false);
                });
    }
    
    @Override
    public Mono<Void> recordProgress(String taskId, Object progressData) {
        Query query = new Query(Criteria.where("_id").is(taskId)
                                   .and("status").is(TaskStatus.RUNNING));
        
        Update update = new Update()
                .set("progress", progressData)
                .set("timestamps.updatedAt", Instant.now());
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then();
    }
    
    @Override
    public Mono<Void> recordCompletion(String taskId, Object result) {
        Instant now = Instant.now();
        
        Query query = new Query(Criteria.where("_id").is(taskId)
                                   .and("status").is(TaskStatus.RUNNING));
        
        Update update = new Update()
                .set("status", TaskStatus.COMPLETED)
                .set("result", result)
                .set("timestamps.completedAt", now)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then(taskRepository.findById(taskId)
                        .doOnNext(task -> {
                            try {
                                java.util.Map<String, Object> ev = new java.util.HashMap<>();
                                ev.put("type", "TASK_COMPLETED");
                                ev.put("taskId", taskId);
                                ev.put("taskType", task.getTaskType());
                                ev.put("userId", task.getUserId());
                                ev.put("result", result);
                                if (task.getParentTaskId() != null) ev.put("parentTaskId", task.getParentTaskId());
                                taskEventPublisher.publish(ev);
                            } catch (Throwable ignore) {}
                        })
                        .then());
    }
    
    @Override
    public Mono<Void> updateTaskResult(String taskId, Object result) {
        Instant now = Instant.now();
        
        // 无论任务当前状态如何，都更新result和updatedAt时间戳
        Query query = new Query(Criteria.where("_id").is(taskId));
        
        Update update = new Update()
                .set("result", result)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .flatMap(updateResult -> {
                    if (updateResult.getModifiedCount() == 0) {
                        log.warn("更新任务result失败，任务不存在或未修改: taskId={}", taskId);
                        return Mono.empty();
                    }
                    
                    log.info("成功更新任务result: taskId={}, resultType={}", 
                            taskId, result != null ? result.getClass().getSimpleName() : "null");
                    
                    // 查询任务并发布更新事件
                    return taskRepository.findById(taskId)
                            .doOnNext(task -> {
                                try {
                                    // 发布TASK_COMPLETED事件，包含更新后的result
                                    java.util.Map<String, Object> ev = new java.util.HashMap<>();
                                    ev.put("type", "TASK_COMPLETED");
                                    ev.put("taskId", taskId);
                                    ev.put("taskType", task.getTaskType());
                                    ev.put("userId", task.getUserId());
                                    ev.put("result", result);
                                    if (task.getParentTaskId() != null) {
                                        ev.put("parentTaskId", task.getParentTaskId());
                                    }
                                    
                                    log.debug("发布任务result更新事件: taskId={}", taskId);
                                    taskEventPublisher.publish(ev);
                                } catch (Throwable ex) {
                                    log.error("发布任务result更新事件失败: taskId={}, error={}", 
                                            taskId, ex.getMessage(), ex);
                                }
                            })
                            .then();
                })
                .then();
    }
    
    @Override
    public Mono<Void> recordFailure(String taskId, Map<String, Object> errorInfo, boolean isDeadLetter) {
        Instant now = Instant.now();
        TaskStatus newStatus = isDeadLetter ? TaskStatus.DEAD_LETTER : TaskStatus.FAILED;
        
        Query query = new Query(Criteria.where("_id").is(taskId));
        
        Update update = new Update()
                .set("status", newStatus)
                .set("errorInfo", errorInfo)
                .set("timestamps.updatedAt", now);
        
        if (isDeadLetter) {
            update.set("timestamps.completedAt", now); // 死信也视为一种"完成"
        }
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then(taskRepository.findById(taskId)
                        .doOnNext(task -> {
                            try {
                                java.util.Map<String, Object> ev = new java.util.HashMap<>();
                                ev.put("type", "TASK_FAILED");
                                ev.put("taskId", taskId);
                                ev.put("taskType", task.getTaskType());
                                ev.put("userId", task.getUserId());
                                ev.put("error", errorInfo);
                                ev.put("deadLetter", isDeadLetter);
                                if (task.getParentTaskId() != null) ev.put("parentTaskId", task.getParentTaskId());
                                taskEventPublisher.publish(ev);
                            } catch (Throwable ignore) {}
                        })
                        .then());
    }
    
    @Override
    public Mono<Void> recordFailure(String taskId, Throwable error, boolean isDeadLetter) {
        Map<String, Object> errorInfo = new HashMap<>();
        errorInfo.put("message", error.getMessage());
        errorInfo.put("type", error.getClass().getName());
        
        // 如果有堆栈信息，最多收集10层
        StackTraceElement[] stackTrace = error.getStackTrace();
        if (stackTrace != null && stackTrace.length > 0) {
            List<String> stackTraceList = Arrays.stream(stackTrace)
                    .limit(10)
                    .map(StackTraceElement::toString)
                    .collect(Collectors.toList());
            errorInfo.put("stackTrace", stackTraceList);
        }
        
        return recordFailure(taskId, errorInfo, isDeadLetter);
    }
    
    @Override
    public Mono<Void> recordRetrying(String taskId, int retryCount, Throwable error, Instant nextAttemptTime) {
        Map<String, Object> errorInfo = new HashMap<>();
        errorInfo.put("message", error.getMessage());
        errorInfo.put("type", error.getClass().getName());
        
        // 如果有堆栈信息，最多收集10层
        StackTraceElement[] stackTrace = error.getStackTrace();
        if (stackTrace != null && stackTrace.length > 0) {
            List<String> stackTraceList = Arrays.stream(stackTrace)
                    .limit(10)
                    .map(StackTraceElement::toString)
                    .collect(Collectors.toList());
            errorInfo.put("stackTrace", stackTraceList);
        }
        
        Instant now = Instant.now();
        
        Query query = new Query(Criteria.where("_id").is(taskId));
        
        Update update = new Update()
                .set("status", TaskStatus.RETRYING)
                .set("errorInfo", errorInfo)
                .set("retryCount", retryCount)
                .set("nextAttemptTimestamp", nextAttemptTime)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then();
    }
    
    @Override
    public Mono<Void> recordRetry(String taskId, Map<String, Object> errorInfo, Instant nextAttemptAt) {
        Instant now = Instant.now();
        
        Query query = new Query(Criteria.where("_id").is(taskId));
        
        Update update = new Update()
                .set("status", TaskStatus.RETRYING)
                .set("errorInfo", errorInfo)
                .set("nextAttemptTimestamp", nextAttemptAt)
                .inc("retryCount", 1)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then();
    }
    
    @Override
    public Mono<Void> recordCancellation(String taskId) {
        Instant now = Instant.now();
        
        Query query = new Query(Criteria.where("_id").is(taskId));
        
        Update update = new Update()
                .set("status", TaskStatus.CANCELLED)
                .set("timestamps.completedAt", now)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then(taskRepository.findById(taskId)
                        .doOnNext(task -> {
                            try {
                                java.util.Map<String, Object> ev = new java.util.HashMap<>();
                                ev.put("type", "TASK_CANCELLED");
                                ev.put("taskId", taskId);
                                ev.put("taskType", task.getTaskType());
                                ev.put("userId", task.getUserId());
                                if (task.getParentTaskId() != null) ev.put("parentTaskId", task.getParentTaskId());
                                taskEventPublisher.publish(ev);
                            } catch (Throwable ignore) {}
                        })
                        .then());
    }
    
    @Override
    public Mono<BackgroundTask> getTask(String taskId) {
        return taskRepository.findById(taskId);
    }
    
    @Override
    public Flux<BackgroundTask> getUserTasks(String userId, TaskStatus status, int page, int size) {
        // 尝试缓存命中
        final String cacheKey = buildUserTasksCacheKey(userId, status, page, size);
        java.util.List<BackgroundTask> cached = userTasksCache.getIfPresent(cacheKey);
        if (cached != null) {
            log.debug("[cache hit] getUserTasks key={} size={}", cacheKey, cached.size());
            return Flux.fromIterable(cached);
        }

        // 排除摘要相关任务类型和拆书任务类型
        List<String> excludeTypes = Arrays.asList(
            "GENERATE_SUMMARY", 
            "BATCH_GENERATE_SUMMARY",
            "KNOWLEDGE_EXTRACTION_FANQIE",
            "KNOWLEDGE_EXTRACTION_TEXT",
            "KNOWLEDGE_EXTRACTION_GROUP"
        );
        
        // 按创建时间倒序排列
        PageRequest pageRequest = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "timestamps.createdAt"));
        
        Flux<BackgroundTask> parentTasksFlux;
        if (status != null) {
            parentTasksFlux = taskRepository.findParentTasksByUserIdAndStatusExcludingTypes(userId, status, excludeTypes, pageRequest);
        } else {
            parentTasksFlux = taskRepository.findParentTasksByUserIdExcludingTypes(userId, excludeTypes, pageRequest);
        }
        
        // 为每个父任务查询并附加其子任务，最终收集列表后写入缓存
        return parentTasksFlux
            .concatMap(parentTask -> {
                // 首先返回父任务
                Flux<BackgroundTask> parentFlux = Flux.just(parentTask);
                
                // 然后查询并返回该父任务的所有子任务
                Flux<BackgroundTask> childrenFlux = taskRepository.findByParentTaskId(parentTask.getId())
                    .sort((a, b) -> {
                        Instant aTime = a.getTimestamps().getCreatedAt();
                        Instant bTime = b.getTimestamps().getCreatedAt();
                        if (aTime == null && bTime == null) return 0;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;
                        return bTime.compareTo(aTime); // 倒序
                    });
                
                // 合并父任务和子任务
                return parentFlux.concatWith(childrenFlux);
            })
            .collectList()
            .doOnNext(list -> {
                try {
                    userTasksCache.put(cacheKey, list);
                    log.debug("[cache put] getUserTasks key={} size={}", cacheKey, list.size());
                } catch (Throwable ignore) {}
            })
            .flatMapMany(Flux::fromIterable);
    }

    private String buildUserTasksCacheKey(String userId, TaskStatus status, int page, int size) {
        String st = (status == null) ? "*" : status.name();
        return userId + ":" + st + ":" + page + ":" + size;
    }
    
    @Override
    public Flux<BackgroundTask> getSubTasks(String parentTaskId) {
        return taskRepository.findByParentTaskId(parentTaskId);
    }

    @Override
    public Mono<Void> updateSubTaskStatusSummary(String parentTaskId, String childTaskId, 
                                               TaskStatus oldStatus, TaskStatus newStatus) {
        if (parentTaskId == null) {
            return Mono.empty();
        }
            
        return Mono.zip(
                // 减少旧状态计数
                decrementStatusCount(parentTaskId, oldStatus),
                // 增加新状态计数
                incrementStatusCount(parentTaskId, newStatus)
            ).then();
    }
    
    private Mono<Void> decrementStatusCount(String parentTaskId, TaskStatus status) {
        if (status == null) {
            return Mono.empty(); // 如果是初始状态变更（无旧状态），不需要减少
        }
        
        String statusKey = "subTaskStatusSummary." + status.name();
        Query query = new Query(Criteria.where("_id").is(parentTaskId));
        Update update = new Update().inc(statusKey, -1);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then();
    }
    
    private Mono<Void> incrementStatusCount(String parentTaskId, TaskStatus status) {
        String statusKey = "subTaskStatusSummary." + status.name();
        Query query = new Query(Criteria.where("_id").is(parentTaskId));
        Update update = new Update().inc(statusKey, 1);
        
        return mongoTemplate.updateFirst(query, update, BackgroundTask.class)
                .then();
    }

    @Override
    public Mono<Boolean> cancelTask(String taskId, String userId) {
        Instant now = Instant.now();
        
        Query query = new Query(Criteria.where("_id").is(taskId)
                                   .and("userId").is(userId)
                                   .and("status").in(TaskStatus.QUEUED, TaskStatus.RUNNING, TaskStatus.RETRYING));
        
        Update update = new Update()
                .set("status", TaskStatus.CANCELLED)
                .set("timestamps.completedAt", now)
                .set("timestamps.updatedAt", now);
        
        return mongoTemplate.findAndModify(query, update, BackgroundTask.class)
                .map(task -> true)
                .defaultIfEmpty(false);
    }
} 