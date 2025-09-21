package com.ainovel.server.task.service.impl;

import com.ainovel.server.repository.BackgroundTaskRepository;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;
import com.ainovel.server.task.event.internal.TaskSubmittedEvent;
import com.ainovel.server.task.producer.TaskMessageProducer;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.reactive.TransactionalOperator;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * 响应式任务提交服务实现类
 */
@Slf4j
@Service
public class TaskSubmissionServiceImpl implements TaskSubmissionService {

    private final BackgroundTaskRepository taskRepository;
    private final TaskStateService taskStateService;
    private final TaskMessageProducer taskMessageProducer;
    private final ApplicationEventPublisher eventPublisher;
    private final ObjectMapper objectMapper;
    private final TransactionalOperator transactionalOperator;

    @Autowired
    public TaskSubmissionServiceImpl(
            BackgroundTaskRepository taskRepository,
            TaskStateService taskStateService,
            TaskMessageProducer taskMessageProducer,
            ApplicationEventPublisher eventPublisher,
            ObjectMapper objectMapper,
            TransactionalOperator transactionalOperator) {
        this.taskRepository = taskRepository;
        this.taskStateService = taskStateService;
        this.taskMessageProducer = taskMessageProducer;
        this.eventPublisher = eventPublisher;
        this.objectMapper = objectMapper;
        this.transactionalOperator = transactionalOperator;
    }

    @Override
    public Mono<String> submitTask(String userId, String taskType, Object parameters, String parentTaskId) {
        // 确保参数有效
        if (userId == null || userId.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("用户ID不能为空"));
        }
        
        if (taskType == null || taskType.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("任务类型不能为空"));
        }
        
        if (parameters == null) {
            return Mono.error(new IllegalArgumentException("任务参数不能为空"));
        }
        
        log.info("准备提交任务，用户ID: {}, 任务类型: {}, 父任务ID: {}", userId, taskType, parentTaskId);
        
        // 先在事务中创建任务，提交后再发布事件，避免本地传输读取不到任务（提交竞态）
        Mono<String> createMono = transactionalOperator.execute(status -> {
            Mono<String> taskIdMono;
            if (parentTaskId != null && !parentTaskId.trim().isEmpty()) {
                log.debug("创建子任务，父任务ID: {}", parentTaskId);
                taskIdMono = taskStateService.createSubTask(userId, taskType, parameters, parentTaskId)
                    .map(task -> task.getId());
            } else {
                log.debug("创建普通任务");
                taskIdMono = taskStateService.createTask(userId, taskType, parameters, null);
            }
            return taskIdMono;
        }).single();

        return createMono.flatMap(taskId -> {
            try {
                String eventId = UUID.randomUUID().toString();
                TaskSubmittedEvent event = new TaskSubmittedEvent(
                        this,
                        taskId,
                        taskType,
                        userId,
                        parameters);
                event.setEventId(eventId);
                log.info("发布任务提交事件: taskId={}, eventId={}, taskType={}", taskId, eventId, taskType);
                eventPublisher.publishEvent(event);
                log.debug("任务提交事件已发布（提交后），将由TaskSubmissionListener处理分发");
            } catch (Exception e) {
                log.error("发布任务提交事件失败: {} [类型: {}, 用户: {}]", taskId, taskType, userId, e);
                return Mono.error(e);
            }
            return Mono.just(taskId);
        });
    }
    
    @Override
    public Mono<Object> getTaskStatus(String taskId) {
        return getTaskStatus(taskId, null);
    }
    
    @Override
    public Mono<Object> getTaskStatus(String taskId, String userId) {
        if (taskId == null || taskId.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("任务ID不能为空"));
        }
        
        return taskStateService.getTask(taskId)
            .flatMap(task -> {
                // 如果提供了用户ID，检查用户是否有权限
                if (userId != null && !userId.equals(task.getUserId())) {
                    return Mono.error(new SecurityException("无权访问此任务"));
                }
                
                // 构建任务状态响应
                return Mono.fromCallable(() -> {
                    ObjectNode statusNode = objectMapper.createObjectNode();
                    statusNode.put("id", task.getId());
                    statusNode.put("type", task.getTaskType());
                    statusNode.put("status", task.getStatus().name());
                    
                    if (task.getProgress() != null) {
                        statusNode.set("progress", objectMapper.valueToTree(task.getProgress()));
                    }
                    
                    if (task.getResult() != null) {
                        statusNode.set("result", objectMapper.valueToTree(task.getResult()));
                    }
                    
                    if (task.getErrorInfo() != null) {
                        statusNode.set("errorInfo", objectMapper.valueToTree(task.getErrorInfo()));
                    }
                    
                    if (task.getTimestamps() != null) {
                        statusNode.set("timestamps", objectMapper.valueToTree(task.getTimestamps()));
                    }
                    
                    statusNode.put("retryCount", task.getRetryCount());
                    
                    // Cast ObjectNode to Object before returning
                    return (Object) statusNode;
                }).subscribeOn(Schedulers.boundedElastic());
            })
            .switchIfEmpty(Mono.error(new IllegalArgumentException("找不到任务: " + taskId)));
    }
    
    @Override
    public Mono<Boolean> cancelTask(String taskId) {
        return cancelTask(taskId, null);
    }
    
    @Override
    public Mono<Boolean> cancelTask(String taskId, String userId) {
        if (taskId == null || taskId.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("任务ID不能为空"));
        }
        
        Mono<Boolean> cancelMono;
        
        if (userId != null && !userId.trim().isEmpty()) {
            // 带用户权限检查的取消
            cancelMono = taskStateService.cancelTask(taskId, userId);
        } else {
            // 不检查用户权限的取消（通常是系统或管理员操作）
            cancelMono = taskStateService.getTask(taskId)
                .flatMap(task -> taskStateService.cancelTask(task.getId(), task.getUserId()));
        }
        
        return cancelMono.flatMap(cancelled -> {
            if (cancelled) {
                // 如果成功取消，发送取消事件消息
                return taskStateService.getTask(taskId)
                    .flatMap(task -> {
                        try {
                            Map<String, Object> eventData = new HashMap<>();
                            eventData.put("taskId", taskId);
                            eventData.put("userId", task.getUserId());
                            eventData.put("taskType", task.getTaskType());
                            eventData.put("status", TaskStatus.CANCELLED.name());
                            eventData.put("timestamp", Instant.now().toString());
                            
                            return taskMessageProducer.sendTaskEvent("TASK_CANCELLED", eventData)
                                .thenReturn(true);
                        } catch (Exception e) {
                            log.error("发送任务取消事件消息失败: taskId={}, error={}", 
                                     taskId, e.getMessage(), e);
                            return Mono.just(true); // 即使事件发送失败，任务取消成功
                        }
                    });
            } else {
                return Mono.just(false);
            }
        });
    }
    
    @Override
    public Flux<BackgroundTask> getUserTasks(String userId, TaskStatus status, int page, int size) {
        if (userId == null || userId.trim().isEmpty()) {
            return Flux.error(new IllegalArgumentException("用户ID不能为空"));
        }
        
        log.debug("获取用户任务列表: userId={}, status={}, page={}, size={}", userId, status, page, size);
        
        return taskStateService.getUserTasks(userId, status, page, size)
                .doOnNext(task -> log.debug("找到任务: taskId={}, type={}, status={}", 
                        task.getId(), task.getTaskType(), task.getStatus()))
                .onErrorResume(e -> {
                    log.error("获取用户任务列表失败: userId={}, error={}", userId, e.getMessage(), e);
                    return Flux.error(new RuntimeException("获取任务列表失败: " + e.getMessage(), e));
                });
    }
} 