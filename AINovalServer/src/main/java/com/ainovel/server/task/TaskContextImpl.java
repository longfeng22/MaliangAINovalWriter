package com.ainovel.server.task;

import com.ainovel.server.task.event.internal.TaskProgressEvent;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.service.TaskSubmissionService;
import lombok.Getter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * TaskContext接口的实现类，提供任务执行的上下文环境
 * @param <P> 任务参数类型
 */
public class TaskContextImpl<P> implements TaskContext<P> {
    
    private static final Logger logger = LoggerFactory.getLogger(TaskContextImpl.class);
    
    @Getter
    private final String taskId;
    
    @Getter
    private final String taskType;
    
    @Getter
    private final String userId;
    
    @Getter
    private final P parameters;
    
    @Getter
    private final String executionNodeId;
    
    @Getter
    private final String parentTaskId;
    
    private final TaskStateService taskStateService;
    private final TaskSubmissionService taskSubmissionService;
    private final ApplicationEventPublisher eventPublisher;
    
    /**
     * 构造函数
     * 
     * @param taskId 任务ID
     * @param taskType 任务类型
     * @param userId 用户ID
     * @param parameters 任务参数
     * @param executionNodeId 执行节点ID
     * @param parentTaskId 父任务ID
     * @param taskStateService 任务状态服务
     * @param taskSubmissionService 任务提交服务
     * @param eventPublisher 事件发布器
     */
    public TaskContextImpl(
            String taskId,
            String taskType,
            String userId,
            P parameters,
            String executionNodeId,
            String parentTaskId,
            TaskStateService taskStateService,
            TaskSubmissionService taskSubmissionService,
            ApplicationEventPublisher eventPublisher) {
        this.taskId = taskId;
        this.taskType = taskType;
        this.userId = userId;
        this.parameters = parameters;
        this.executionNodeId = executionNodeId;
        this.parentTaskId = parentTaskId;
        this.taskStateService = taskStateService;
        this.taskSubmissionService = taskSubmissionService;
        this.eventPublisher = eventPublisher;
    }
    
    @Override
    public Mono<Void> updateProgress(Object progressData) {
        if (progressData == null) {
            return Mono.empty();
        }
        
        // 发布进度更新事件（包含更多上下文）
        eventPublisher.publishEvent(new TaskProgressEvent(this, taskId, taskType, userId, parentTaskId, progressData));
        
        // 更新数据库中的进度
        return taskStateService.recordProgress(taskId, progressData);
    }
    
    @Override
    public Mono<Void> logInfo(String message) {
        logger.info("[任务:{}] {}", taskId, message);
        return Mono.empty();
    }
    
    @Override
    public Mono<Void> logError(String message, Throwable error) {
        if (error != null) {
            logger.error("[任务:{}] {}", taskId, message, error);
        } else {
            logger.error("[任务:{}] {}", taskId, message);
        }
        return Mono.empty();
    }
    
    @Override
    public Mono<String> submitSubTask(String taskType, Object parameters) {
        // 修复子任务父子关系：
        // - 若当前上下文已有 parentTaskId（说明自己已经是子任务），则继续将新子任务挂到这个“顶层父任务”之下；
        // - 否则（当前为顶层任务），将新子任务挂到当前 taskId 之下。
        final String effectiveParentId = (parentTaskId != null && !parentTaskId.isBlank()) ? parentTaskId : taskId;
        return taskSubmissionService.submitTask(userId, taskType, parameters, effectiveParentId);
    }
    
    /**
     * 创建TaskContext的构建器
     * 
     * @param <P> 任务参数类型
     * @return TaskContext构建器
     */
    public static <P> Builder<P> builder() {
        return new Builder<>();
    }
    
    /**
     * TaskContext构建器
     * @param <P> 任务参数类型
     */
    public static class Builder<P> {
        private String taskId;
        private String taskType;
        private String userId;
        private P parameters;
        private String executionNodeId;
        private String parentTaskId;
        private TaskStateService taskStateService;
        private TaskSubmissionService taskSubmissionService;
        private ApplicationEventPublisher eventPublisher;
        
        private Builder() {
            // 默认生成一个UUID作为任务ID
            this.taskId = UUID.randomUUID().toString();
        }
        
        public Builder<P> taskId(String taskId) {
            this.taskId = taskId;
            return this;
        }
        
        public Builder<P> taskType(String taskType) {
            this.taskType = taskType;
            return this;
        }
        
        public Builder<P> userId(String userId) {
            this.userId = userId;
            return this;
        }
        
        public Builder<P> parameters(P parameters) {
            this.parameters = parameters;
            return this;
        }
        
        public Builder<P> executionNodeId(String executionNodeId) {
            this.executionNodeId = executionNodeId;
            return this;
        }
        
        public Builder<P> parentTaskId(String parentTaskId) {
            this.parentTaskId = parentTaskId;
            return this;
        }
        
        public Builder<P> taskStateService(TaskStateService taskStateService) {
            this.taskStateService = taskStateService;
            return this;
        }
        
        public Builder<P> taskSubmissionService(TaskSubmissionService taskSubmissionService) {
            this.taskSubmissionService = taskSubmissionService;
            return this;
        }
        
        public Builder<P> eventPublisher(ApplicationEventPublisher eventPublisher) {
            this.eventPublisher = eventPublisher;
            return this;
        }
        
        /**
         * 构建TaskContext实例
         * 
         * @return TaskContext实例
         */
        public TaskContext<P> build() {
            if (taskId == null) {
                taskId = UUID.randomUUID().toString();
            }
            
            if (taskType == null || userId == null || parameters == null || 
                taskStateService == null || taskSubmissionService == null || eventPublisher == null) {
                throw new IllegalStateException("缺少必要的TaskContext参数");
            }
            
            return new TaskContextImpl<>(
                    taskId, taskType, userId, parameters, executionNodeId, parentTaskId,
                    taskStateService, taskSubmissionService, eventPublisher);
        }
    }
} 