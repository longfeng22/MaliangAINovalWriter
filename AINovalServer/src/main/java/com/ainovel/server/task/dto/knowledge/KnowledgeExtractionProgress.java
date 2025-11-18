package com.ainovel.server.task.dto.knowledge;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 知识提取进度信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeExtractionProgress {
    
    /**
     * 当前步骤
     */
    private String currentStep;
    
    /**
     * 总子任务数
     */
    private Integer totalSubTasks;
    
    /**
     * 已完成子任务数
     */
    private Integer completedSubTasks;
    
    /**
     * 失败子任务数
     */
    private Integer failedSubTasks;
    
    /**
     * 进度百分比
     */
    private Integer progress;
    
    /**
     * 当前处理的类型
     */
    private String currentType;
    
    /**
     * 最后更新时间
     */
    private LocalDateTime lastUpdated;
}


