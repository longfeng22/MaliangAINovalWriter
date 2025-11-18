package com.ainovel.server.task.service;

import java.util.Map;
import java.time.Instant;

import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 任务状态管理服务接口，提供对后台任务状态的响应式操作
 */
public interface TaskStateService {
    
    /**
     * 创建新任务
     * @param userId 用户ID
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @param parentTaskId 父任务ID（可选）
     * @return 创建的任务的Mono
     */
    Mono<String> createTask(String userId, String taskType, Object parameters, String parentTaskId);
    
    /**
     * 创建子任务
     * @param userId 用户ID
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @param parentTaskId 父任务ID
     * @return 创建的子任务的Mono
     */
    Mono<BackgroundTask> createSubTask(String userId, String taskType, Object parameters, String parentTaskId);
    
    /**
     * 尝试将任务状态设置为运行中（原子操作）
     * @param taskId 任务ID
     * @return 如果设置成功返回true，否则返回false的Mono
     */
    Mono<Boolean> trySetRunning(String taskId);
    
    /**
     * 尝试将任务状态设置为运行中，并设置执行节点（原子操作）
     * @param taskId 任务ID
     * @param executionNodeId 执行节点ID
     * @return 如果设置成功返回true，否则返回false的Mono
     */
    Mono<Boolean> trySetRunning(String taskId, String executionNodeId);
    
    /**
     * 记录任务进度
     * @param taskId 任务ID
     * @param progressData 进度数据
     * @return 完成信号
     */
    Mono<Void> recordProgress(String taskId, Object progressData);
    
    /**
     * 记录任务完成
     * @param taskId 任务ID
     * @param result 任务结果
     * @return 完成信号
     */
    Mono<Void> recordCompletion(String taskId, Object result);
    
    /**
     * 更新任务结果（无论任务当前状态如何）
     * 用于父任务需要更新已完成子任务的result的场景
     * 
     * @param taskId 任务ID
     * @param result 结果对象
     * @return 完成信号
     */
    Mono<Void> updateTaskResult(String taskId, Object result);
    
    /**
     * 记录任务重试状态
     * @param taskId 任务ID
     * @param retryCount 重试次数
     * @param error 错误对象
     * @param nextAttemptTime 下次尝试时间
     * @return 完成信号
     */
    Mono<Void> recordRetrying(String taskId, int retryCount, Throwable error, Instant nextAttemptTime);
    
    /**
     * 记录任务失败
     * @param taskId 任务ID
     * @param error 错误对象
     * @param isDeadLetter 是否为死信
     * @return 完成信号
     */
    Mono<Void> recordFailure(String taskId, Throwable error, boolean isDeadLetter);
    
    /**
     * 记录任务失败（使用Map格式的错误信息）
     * @param taskId 任务ID
     * @param errorInfo 错误信息
     * @param isDeadLetter 是否为死信
     * @return 完成信号
     */
    Mono<Void> recordFailure(String taskId, Map<String, Object> errorInfo, boolean isDeadLetter);
    
    /**
     * 记录任务重试
     * @param taskId 任务ID
     * @param errorInfo 错误信息
     * @param nextAttemptAt 下次尝试时间
     * @return 完成信号
     */
    Mono<Void> recordRetry(String taskId, Map<String, Object> errorInfo, java.time.Instant nextAttemptAt);
    
    /**
     * 取消任务
     * @param taskId 任务ID
     * @param userId 用户ID（用于权限检查）
     * @return 如果取消成功返回true，否则返回false的Mono
     */
    Mono<Boolean> cancelTask(String taskId, String userId);
    
    /**
     * 获取任务
     * @param taskId 任务ID
     * @return 任务的Mono
     */
    Mono<BackgroundTask> getTask(String taskId);
    
    /**
     * 获取用户的任务列表
     * @param userId 用户ID
     * @param status 可选的状态过滤
     * @param page 页码
     * @param size 每页大小
     * @return 任务列表的Flux
     */
    Flux<BackgroundTask> getUserTasks(String userId, TaskStatus status, int page, int size);
    
    /**
     * 获取父任务的子任务列表
     * @param parentTaskId 父任务ID
     * @return 子任务列表的Flux
     */
    Flux<BackgroundTask> getSubTasks(String parentTaskId);
    
    /**
     * 更新子任务状态摘要
     * @param parentTaskId 父任务ID
     * @param childTaskId 子任务ID
     * @param oldStatus 旧状态
     * @param newStatus 新状态
     * @return 完成信号
     */
    Mono<Void> updateSubTaskStatusSummary(String parentTaskId, String childTaskId, 
                                        TaskStatus oldStatus, TaskStatus newStatus);
    
    /**
     * 记录任务取消
     * @param taskId 任务ID
     * @return 完成信号
     */
    Mono<Void> recordCancellation(String taskId);
} 