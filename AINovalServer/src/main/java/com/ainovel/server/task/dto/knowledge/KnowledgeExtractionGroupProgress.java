package com.ainovel.server.task.dto.knowledge;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 知识提取组任务进度
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class KnowledgeExtractionGroupProgress {
    
    /**
     * 组名称
     */
    private String groupName;
    
    /**
     * 当前步骤（INITIALIZING, EXTRACTING, COMPLETED）
     */
    private String currentStep;
    
    /**
     * 当前处理的类型
     */
    private String currentType;
    
    /**
     * 进度百分比（0-100）
     */
    private Integer progress;
    
    /**
     * 已提取的设定数量
     */
    private Integer extractedCount;
    
    /**
     * 最后更新时间
     */
    private LocalDateTime lastUpdated;
}


