package com.ainovel.server.task.dto.storyprediction;

import com.ainovel.server.domain.model.AIRequest;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 剧情推演任务结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StoryPredictionResult {
    
    /**
     * 任务ID
     */
    private String taskId;
    
    /**
     * 小说ID
     */
    private String novelId;
    
    /**
     * 章节ID
     */
    private String chapterId;
    
    /**
     * 总预测数量
     */
    private Integer totalPredictions;
    
    /**
     * 成功数量
     */
    private Integer successCount;
    
    /**
     * 失败数量
     */
    private Integer failureCount;
    
    /**
     * 预测结果列表
     */
    private List<PredictionItem> predictions;
    
    /**
     * 任务状态
     */
    private String status;
    
    /**
     * 开始时间
     */
    private LocalDateTime startTime;
    
    /**
     * 完成时间
     */
    private LocalDateTime completionTime;
    
    /**
     * 总耗时（毫秒）
     */
    private Long executionTimeMs;
    
    /**
     * 错误信息
     */
    private String error;
    
    /**
     * 单个预测结果项
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class PredictionItem {
        /**
         * 预测ID
         */
        private String id;
        
        /**
         * 模型ID
         */
        private String modelId;
        
        /**
         * 模型名称
         */
        private String modelName;
        
        /**
         * 摘要内容
         */
        private String summary;
        
        /**
         * 场景内容
         */
        private String sceneContent;
        
        /**
         * 预测状态
         */
        private String status;
        
        /**
         * 场景状态
         */
        private String sceneStatus;
        
        /**
         * 错误信息
         */
        private String error;
        
        /**
         * 生成时间
         */
        private LocalDateTime createdAt;
        
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
        
        /**
         * 是否包含场景内容
         */
        public boolean hasSceneContent() {
            return sceneContent != null && !sceneContent.trim().isEmpty();
        }
    }
}
