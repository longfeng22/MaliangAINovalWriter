package com.ainovel.server.repository;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;

import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 后台任务的响应式MongoDB存储库
 */
@Repository
public interface BackgroundTaskRepository extends ReactiveMongoRepository<BackgroundTask, String> {
    
    /**
     * 根据用户ID查找任务，支持分页
     * @param userId 用户ID
     * @param pageable 分页参数
     * @return 该用户的任务流
     */
    Flux<BackgroundTask> findByUserId(String userId, Pageable pageable);
    
    /**
     * 根据ID和用户ID查找任务（用于权限验证）
     * @param id 任务ID
     * @param userId 用户ID
     * @return 任务的Mono
     */
    Mono<BackgroundTask> findByIdAndUserId(String id, String userId);
    
    /**
     * 根据父任务ID查找子任务
     * @param parentTaskId 父任务ID
     * @return 子任务流
     */
    Flux<BackgroundTask> findByParentTaskId(String parentTaskId);
    
    /**
     * 查找指定用户的指定状态的任务，支持分页
     * @param userId 用户ID
     * @param status 任务状态
     * @param pageable 分页参数
     * @return 符合条件的任务流
     */
    Flux<BackgroundTask> findByUserIdAndStatus(String userId, TaskStatus status, Pageable pageable);
    
    /**
     * 查找指定类型的任务，支持分页
     * @param taskType 任务类型
     * @param pageable 分页参数
     * @return 符合条件的任务流
     */
    Flux<BackgroundTask> findByTaskType(String taskType, Pageable pageable);
    
    /**
     * 计算指定用户的待处理任务数量
     * @param userId 用户ID
     * @return 待处理任务数量的Mono
     */
    Mono<Long> countByUserIdAndStatusIn(String userId, TaskStatus... statuses);
    
    /**
     * 根据状态和执行节点查找任务
     * @param status 任务状态
     * @param executionNodeId 执行节点ID
     * @return 符合条件的任务流
     */
    Flux<BackgroundTask> findByStatusAndExecutionNodeId(TaskStatus status, String executionNodeId);
    
    /**
     * 查找用户的父任务（排除摘要相关任务），按创建时间倒序
     * @param userId 用户ID
     * @param excludeTypes 排除的任务类型列表
     * @param pageable 分页参数
     * @return 符合条件的父任务流
     */
    @org.springframework.data.mongodb.repository.Query("{ 'userId': ?0, 'parentTaskId': null, 'taskType': { $nin: ?1 } }")
    Flux<BackgroundTask> findParentTasksByUserIdExcludingTypes(String userId, java.util.List<String> excludeTypes, Pageable pageable);
    
    /**
     * 查找用户指定状态的父任务（排除摘要相关任务），按创建时间倒序
     * @param userId 用户ID
     * @param status 任务状态
     * @param excludeTypes 排除的任务类型列表
     * @param pageable 分页参数
     * @return 符合条件的父任务流
     */
    @org.springframework.data.mongodb.repository.Query("{ 'userId': ?0, 'status': ?1, 'parentTaskId': null, 'taskType': { $nin: ?2 } }")
    Flux<BackgroundTask> findParentTasksByUserIdAndStatusExcludingTypes(String userId, TaskStatus status, java.util.List<String> excludeTypes, Pageable pageable);
} 