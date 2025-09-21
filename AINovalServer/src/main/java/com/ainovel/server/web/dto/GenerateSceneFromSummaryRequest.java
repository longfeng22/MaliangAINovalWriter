package com.ainovel.server.web.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 根据摘要生成场景请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class GenerateSceneFromSummaryRequest {
    
    /**
     * 要生成或更新的场景ID
     */
    private String sceneId;
    
    /**
     * 摘要或大纲
     */
    @NotBlank(message = "摘要不能为空")
    private String summary;
    
    /**
     * 场景计划归属的章节ID（可选）
     */
    private String chapterId;
    
    /**
     * 场景在章节或小说中的大致位置（可选，用于RAG参考）
     */
    private Integer position;
    
    /**
     * 生成风格 (正常, 简洁, 详细, 戏剧化等)
     */
    private String style;
    
    /**
     * 生成的内容长度 (短, 中, 长)
     */
    private String length;
    
    /**
     * 生成的语调 (正式, 随意, 幽默, 严肃等)
     */
    private String tone;
    
    /**
     * 用户附加的风格指令（可选）
     */
    private String additionalInstructions;
    
    /**
     * AI配置ID（可选）
     */
    private String aiConfigId;

    /**
     * 提示词模板ID（可选，用于SUMMARY_TO_SCENE）
     */
    private String promptTemplateId;

    /**
     * 公共模型配置ID（可选，使用公共模型时填写）
     */
    private String publicModelConfigId;
} 