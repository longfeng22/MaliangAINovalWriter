package com.ainovel.server.task.dto.knowledge;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 知识提取任务结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeExtractionResult {
    
    /**
     * 知识库ID
     */
    private String knowledgeBaseId;
    
    /**
     * 是否成功
     */
    private Boolean success;
    
    /**
     * 失败原因
     */
    private String failureReason;
    
    /**
     * 提取的设定总数
     */
    private Integer totalSettings;
    
    /**
     * 消耗的Token数
     */
    private Long totalTokens;
}


