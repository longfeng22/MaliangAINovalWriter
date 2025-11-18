package com.ainovel.server.task.dto.knowledge;

import com.ainovel.server.domain.model.KnowledgeExtractionType;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 知识提取任务参数
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeExtractionParameters {
    
    /**
     * 导入记录ID
     */
    private String importRecordId;
    
    /**
     * 番茄小说ID（如果是番茄小说）
     */
    private String fanqieNovelId;
    
    /**
     * 小说标题（如果是用户文本）
     */
    private String title;
    
    /**
     * 小说内容（如果是用户文本）
     */
    private String content;
    
    /**
     * 小说简介
     */
    private String description;
    
    /**
     * 模型配置ID
     */
    private String modelConfigId;
    
    /**
     * 模型类型（public/user）
     */
    private String modelType;
    
    /**
     * 提取类型列表
     */
    private List<KnowledgeExtractionType> extractionTypes;
    
    /**
     * 用户ID
     */
    private String userId;
    
    /**
     * 章节数量（用于章节大纲提取）
     */
    private Integer chapterCount;
    
    /**
     * 预览会话ID（用户导入文本时使用，用于获取章节详情）
     */
    private String previewSessionId;
}


