package com.ainovel.server.task.event.internal;

import java.util.Map;

/**
 * 任务失败事件
 */
public class TaskFailedEvent extends TaskApplicationEvent {
    
    private final Map<String, Object> errorInfo;
    private final boolean isDeadLetter;
    private final String parentTaskId;
    
    /**
     * 创建任务失败事件
     * 
     * @param source 事件源
     * @param taskId 任务ID
     * @param taskType 任务类型
     * @param userId 用户ID
     * @param errorInfo 错误信息
     * @param isDeadLetter 是否死信
     */
    public TaskFailedEvent(Object source, String taskId, String taskType, String userId, 
                          Map<String, Object> errorInfo, boolean isDeadLetter) {
        this(source, taskId, taskType, userId, null, errorInfo, isDeadLetter);
    }
    
    public TaskFailedEvent(Object source, String taskId, String taskType, String userId, 
                          String parentTaskId, Map<String, Object> errorInfo, boolean isDeadLetter) {
        super(source, taskId, taskType, userId);
        this.errorInfo = errorInfo;
        this.isDeadLetter = isDeadLetter;
        this.parentTaskId = parentTaskId;
    }
    
    /**
     * 获取错误信息
     * 
     * @return 错误信息
     */
    public Map<String, Object> getErrorInfo() {
        return errorInfo;
    }
    
    /**
     * 是否为死信
     * 
     * @return 如果是死信返回true，否则返回false
     */
    public boolean isDeadLetter() {
        return isDeadLetter;
    }
    
    public String getParentTaskId() {
        return parentTaskId;
    }
} 