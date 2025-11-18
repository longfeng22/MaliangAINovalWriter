package com.ainovel.server.task.event.internal;

/**
 * 任务进度更新事件
 */
public class TaskProgressEvent extends TaskApplicationEvent {
    
    private final Object progressData;
    private final String parentTaskId;
    
    /**
     * 创建任务进度事件（简化版本，兼容旧用法，不包含用户与任务类型信息）
     */
    public TaskProgressEvent(Object source, String taskId, Object progressData) {
        super(source, taskId);
        this.progressData = progressData;
        this.parentTaskId = null;
    }

    /**
     * 创建任务进度事件（完整信息）
     * 
     * @param source 事件源
     * @param taskId 任务ID
     * @param taskType 任务类型
     * @param userId 用户ID
     * @param parentTaskId 父任务ID（顶层任务可为null）
     * @param progressData 进度数据
     */
    public TaskProgressEvent(Object source, String taskId, String taskType, String userId, String parentTaskId, Object progressData) {
        super(source, taskId, taskType, userId);
        this.progressData = progressData;
        this.parentTaskId = parentTaskId;
    }
    
    /**
     * 获取进度数据
     */
    public Object getProgressData() {
        return progressData;
    }

    /**
     * 获取父任务ID（如果存在）
     */
    public String getParentTaskId() {
        return parentTaskId;
    }
}