package com.ainovel.server.task.dto.continuecontent;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 自动续写小说章节内容任务参数
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ContinueWritingContentParameters {
    
    /**
     * 小说ID
     */
    @NotBlank(message = "小说ID不能为空")
    private String novelId;
    
    /**
     * 要生成的章节数量
     */
    @NotNull(message = "续写章节数不能为空")
    @Min(value = 1, message = "续写章节数必须大于0")
    private Integer numberOfChapters;
    
    /**
     * 摘要生成用的AI配置ID（当使用公共模型时可为空）
     */
    private String aiConfigIdSummary;
    
    /**
     * 内容生成用的AI配置ID（当使用公共模型时可为空）
     */
    private String aiConfigIdContent;
    
    /**
     * 上下文获取模式
     * AUTO: 由后端决定（如最后3章内容+全局设定）
     * LAST_N_CHAPTERS: 需配合contextChapterCount
     * CUSTOM: 需配合customContext
     */
    @Builder.Default
    private String startContextMode = "AUTO";
    
    /**
     * 当startContextMode为LAST_N_CHAPTERS时使用
     */
    private Integer contextChapterCount;
    
    /**
     * 当startContextMode为CUSTOM时使用
     */
    private String customContext;
    
    /**
     * 写作风格提示
     */
    private String writingStyle;
    
    /**
     * 是否需要在生成摘要后暂停，等待用户评审
     */
    @Builder.Default
    private boolean requiresReview = false;

    @Builder.Default
    private boolean persistChanges = true;

    /**
     * （可选）用于摘要生成阶段的提示词模板ID
     */
    private String summaryPromptTemplateId;

    /**
     * （可选）用于场景生成阶段（SUMMARY_TO_SCENE）的提示词模板ID
     */
    private String contentPromptTemplateId;

    /**
     * （可选）公共模型配置ID：摘要阶段
     */
    private String summaryPublicModelConfigId;

    /**
     * （可选）公共模型配置ID：内容阶段
     */
    private String contentPublicModelConfigId;

    /**
     * 验证模型配置的有效性
     * 规则：对于摘要和内容阶段，要么有私人模型配置ID，要么有公共模型配置ID，不能两者都为空
     */
    public void validate() {
        if ((aiConfigIdSummary == null || aiConfigIdSummary.isBlank()) && 
            (summaryPublicModelConfigId == null || summaryPublicModelConfigId.isBlank())) {
            throw new IllegalArgumentException("摘要阶段必须选择私人模型或公共模型");
        }
        
        if ((aiConfigIdContent == null || aiConfigIdContent.isBlank()) && 
            (contentPublicModelConfigId == null || contentPublicModelConfigId.isBlank())) {
            throw new IllegalArgumentException("内容阶段必须选择私人模型或公共模型");
        }
    }
} 