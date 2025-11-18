package com.ainovel.server.task.dto.storyprediction;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 剧情推演任务参数
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StoryPredictionParameters {
    
    /**
     * 小说ID
     */
    @NotBlank(message = "小说ID不能为空")
    private String novelId;
    
    /**
     * 当前章节ID
     */
    @NotBlank(message = "章节ID不能为空")
    private String chapterId;
    
    /**
     * 模型配置列表
     */
    @NotNull(message = "模型配置不能为空")
    private List<ModelConfig> modelConfigs;
    
    /**
     * 每个模型生成的数量
     */
    @NotNull(message = "生成数量不能为空")
    @Min(value = 1, message = "生成数量必须大于0")
    private Integer generationCount;
    
    /**
     * 风格指令
     */
    private String styleInstructions;
    
    /**
     * 上下文选择配置
     */
    private ContextSelection contextSelection;
    
    /**
     * 额外指令
     */
    private String additionalInstructions;
    
    /**
     * 摘要生成提示词模板ID
     */
    private String summaryPromptTemplateId;
    
    /**
     * 场景生成提示词模板ID
     */
    private String scenePromptTemplateId;
    
    /**
     * 是否生成场景内容
     */
    @Builder.Default
    private Boolean generateSceneContent = true;
    
    /**
     * 【迭代优化】基于的预测结果ID
     */
    private String basePredictionId;
    
    /**
     * 【迭代优化】用户的修改意见
     */
    private String refinementInstructions;
    
    /**
     * 【迭代优化】迭代上下文（记录上一次的结果）
     */
    private RefinementContext refinementContext;
    
    /**
     * 模型配置类
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ModelConfig {
        /**
         * 模型类型：PUBLIC 或 PRIVATE
         */
        @NotBlank(message = "模型类型不能为空")
        private String type;
        
        /**
         * 配置ID
         */
        @NotBlank(message = "配置ID不能为空")
        private String configId;
    }
    
    /**
     * 上下文选择配置
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ContextSelection {
        /**
         * 上下文类型列表
         */
        private List<String> types;
        
        /**
         * 自定义上下文ID列表
         */
        private List<String> customContextIds;
        
        /**
         * 最大token数
         */
        @Builder.Default
        private Integer maxTokens = 4000;
    }
    
    /**
     * 迭代优化上下文
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RefinementContext {
        /**
         * 上一次生成的摘要
         */
        private String previousSummary;
        
        /**
         * 上一次生成的场景内容
         */
        private String previousSceneContent;
        
        /**
         * 上一次使用的模型名称
         */
        private String previousModelName;
        
        /**
         * 迭代轮次（从1开始）
         */
        @Builder.Default
        private Integer iterationRound = 0;
        
        /**
         * 原始任务ID
         */
        private String originalTaskId;
        
        /**
         * 🔥 摘要生成的 AIRequest（用于大纲迭代时复用）
         * 包含 STORY_PLOT_CONTINUATION 的系统提示词
         */
        private com.ainovel.server.domain.model.AIRequest savedAIRequest;
        
        /**
         * 🔥 场景生成的 AIRequest（用于场景迭代时复用）
         * 包含 SUMMARY_TO_SCENE 的系统提示词
         */
        private com.ainovel.server.domain.model.AIRequest sceneAIRequest;
    }
    
    /**
     * 对话消息（用于累积历史）
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ConversationMessage {
        /**
         * 消息角色：assistant 或 user
         */
        private String role;
        
        /**
         * 消息内容
         */
        private String content;
    }
}
