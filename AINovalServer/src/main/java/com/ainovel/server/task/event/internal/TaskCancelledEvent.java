package com.ainovel.server.task.event.internal;

/**
 * 任务取消事件
 */
public class TaskCancelledEvent extends TaskApplicationEvent {

    private final String parentTaskId;

    /**
     * 创建任务取消事件
     */
    public TaskCancelledEvent(Object source, String taskId, String taskType, String userId) {
        this(source, taskId, taskType, userId, null);
    }

    public TaskCancelledEvent(Object source, String taskId, String taskType, String userId, String parentTaskId) {
        super(source, taskId, taskType, userId);
        this.parentTaskId = parentTaskId;
    }

    public String getParentTaskId() {
        return parentTaskId;
    }
}