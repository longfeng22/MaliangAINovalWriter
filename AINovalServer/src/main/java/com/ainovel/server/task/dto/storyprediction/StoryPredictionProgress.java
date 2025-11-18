package com.ainovel.server.task.dto.storyprediction;

import com.ainovel.server.domain.model.AIRequest;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 剧情推演任务进度
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StoryPredictionProgress {
    
    /**
     * 总预测数量
     */
    private Integer totalPredictions;
    
    /**
     * 已完成的预测数量
     */
    @Builder.Default
    private Integer completedPredictions = 0;
    
    /**
     * 失败的预测数量
     */
    @Builder.Default
    private Integer failedPredictions = 0;
    
    /**
     * 当前阶段
     */
    private String currentStep;
    
    /**
     * 进度详情
     */
    @Builder.Default
    private List<PredictionProgress> predictionProgress = new ArrayList<>();
    
    /**
     * 最后更新时间
     */
    private LocalDateTime lastUpdated;
    
    /**
     * 单个预测进度
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class PredictionProgress {
        /**
         * 预测ID
         */
        private String predictionId;
        
        /**
         * 模型ID
         */
        private String modelId;
        
        /**
         * 模型名称
         */
        private String modelName;
        
        /**
         * 预测状态
         */
        private String status;
        
        /**
         * 摘要内容
         */
        private String summary;
        
        /**
         * 场景内容
         */
        private String sceneContent;
        
        /**
         * 场景状态
         */
        private String sceneStatus;
        
        /**
         * 错误信息
         */
        private String error;
        
        /**
         * 开始时间
         */
        private LocalDateTime startTime;
        
        /**
         * 完成时间
         */
        private LocalDateTime completionTime;
        
        /**
         * 🔥 摘要生成的 AIRequest（用于大纲迭代优化）
         * 包含完整的对话历史和上下文信息
         */
        private AIRequest aiRequest;
        
        /**
         * 🔥 场景生成的 AIRequest（用于场景迭代优化）
         * 使用 SUMMARY_TO_SCENE 的系统提示词
         */
        private AIRequest sceneAIRequest;
    }
}
