package com.ainovel.server.task.service;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;

/**
 * 响应式任务提交服务接口
 */
public interface TaskSubmissionService {
    
    /**
     * 提交任务
     * 
     * @param userId 用户ID
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @param parentTaskId 父任务ID (可选)
     * @return 创建的任务ID的Mono
     */
    Mono<String> submitTask(String userId, String taskType, Object parameters, String parentTaskId);
    
    /**
     * 提交任务（无父任务）
     * 
     * @param userId 用户ID
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @return 创建的任务ID的Mono
     */
    default Mono<String> submitTask(String userId, String taskType, Object parameters) {
        return submitTask(userId, taskType, parameters, null);
    }
    
    /**
     * 获取任务状态
     * 
     * @param taskId 任务ID
     * @return 任务状态的JSON表示的Mono
     */
    Mono<Object> getTaskStatus(String taskId);
    
    /**
     * 获取任务状态，包含验证用户权限
     * 
     * @param taskId 任务ID
     * @param userId 用户ID
     * @return 任务状态的JSON表示的Mono
     */
    Mono<Object> getTaskStatus(String taskId, String userId);
    
    /**
     * 获取用户的历史任务列表
     * 
     * @param userId 用户ID
     * @param status 任务状态过滤条件（可选）
     * @param page 页码
     * @param size 每页大小
     * @return 任务列表的Flux
     */
    Flux<BackgroundTask> getUserTasks(String userId, TaskStatus status, int page, int size);
    
    /**
     * 取消任务
     * 
     * @param taskId 任务ID
     * @return 是否成功取消的Mono
     */
    Mono<Boolean> cancelTask(String taskId);
    
    /**
     * 取消任务，包含验证用户权限
     * 
     * @param taskId 任务ID
     * @param userId 用户ID
     * @return 是否成功取消的Mono
     */
    Mono<Boolean> cancelTask(String taskId, String userId);
} 