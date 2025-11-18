package com.ainovel.server.web.dto.request;

import com.ainovel.server.task.dto.storyprediction.StoryPredictionParameters;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 剧情推演迭代优化请求
 * 
 * 功能说明：
 * 用户在生成多个推演结果后，可以选择一个最满意的结果，
 * 提出修改意见，基于选定的结果继续推演，支持切换模型。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RefineStoryPredictionRequest {
    
    /**
     * 原始任务ID
     */
    @NotBlank(message = "原始任务ID不能为空")
    private String originalTaskId;
    
    /**
     * 基于的预测结果ID（用户选择的那个）
     */
    @NotBlank(message = "预测结果ID不能为空")
    private String basePredictionId;
    
    /**
     * 用户的修改意见
     */
    @NotBlank(message = "修改意见不能为空")
    private String refinementInstructions;
    
    /**
     * 新的模型配置（支持切换模型）
     */
    @NotNull(message = "模型配置不能为空")
    private List<StoryPredictionParameters.ModelConfig> modelConfigs;
    
    /**
     * 每个模型生成的数量（默认1个）
     */
    @Min(value = 1, message = "生成数量必须大于0")
    @Builder.Default
    private Integer generationCount = 1;
    
    /**
     * 继承的上下文配置（可选，如果不提供则继承原任务）
     */
    private StoryPredictionParameters.ContextSelection contextSelection;
    
    /**
     * 是否生成场景内容
     */
    @Builder.Default
    private Boolean generateSceneContent = true;
    
    /**
     * 风格指令（可选）
     */
    private String styleInstructions;
    
    /**
     * 额外指令（可选）
     */
    private String additionalInstructions;
    
    /**
     * 摘要生成提示词模板ID（可选）
     */
    private String summaryPromptTemplateId;
    
    /**
     * 场景生成提示词模板ID（可选）
     */
    private String scenePromptTemplateId;
}



