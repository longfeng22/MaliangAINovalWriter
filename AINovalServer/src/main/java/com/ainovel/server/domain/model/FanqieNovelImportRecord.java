package com.ainovel.server.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 番茄小说导入记录
 * 记录番茄小说的导入历史，包括LLM请求记录和处理状态
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "fanqie_novel_import_records")
@CompoundIndexes({
    @CompoundIndex(name = "fanqie_user_idx", def = "{'fanqieNovelId': 1, 'userId': 1}"),
    @CompoundIndex(name = "user_time_idx", def = "{'userId': 1, 'startTime': -1}"),
    @CompoundIndex(name = "status_idx", def = "{'status': 1}")
})
public class FanqieNovelImportRecord {
    
    @Id
    private String id;
    
    // ==================== 基本信息 ====================
    
    /**
     * 番茄小说ID
     */
    @Indexed
    private String fanqieNovelId;
    
    /**
     * 番茄小说标题
     */
    private String novelTitle;
    
    /**
     * 发起导入的用户ID
     */
    @Indexed
    private String userId;
    
    /**
     * 关联的知识库ID
     */
    private String knowledgeBaseId;
    
    /**
     * 拆书任务ID（关联后台任务系统）
     */
    private String taskId;
    
    // ==================== 拆书配置 ====================
    
    /**
     * 需要拆书的类型列表
     */
    @Builder.Default
    private List<KnowledgeExtractionType> extractionTypes = new ArrayList<>();
    
    /**
     * 使用的模型配置ID
     */
    private String modelConfigId;
    
    /**
     * 模型类型（public/user）
     */
    private String modelType;
    
    // ==================== 处理状态 ====================
    
    /**
     * 导入状态
     */
    @Builder.Default
    private ImportStatus status = ImportStatus.PENDING;
    
    /**
     * 是否成功
     */
    @Builder.Default
    private Boolean success = false;
    
    /**
     * 失败原因
     */
    private String failureReason;
    
    /**
     * 开始时间
     */
    private LocalDateTime startTime;
    
    /**
     * 完成时间
     */
    private LocalDateTime completionTime;
    
    /**
     * 处理耗时（毫秒）
     */
    private Long processingTimeMs;
    
    // ==================== LLM请求记录 ====================
    
    /**
     * LLM请求记录列表
     */
    @Builder.Default
    private List<LLMRequestRecord> llmRequests = new ArrayList<>();
    
    /**
     * 总LLM请求次数
     */
    @Builder.Default
    private Integer totalLLMRequests = 0;
    
    /**
     * 成功的LLM请求次数
     */
    @Builder.Default
    private Integer successfulLLMRequests = 0;
    
    /**
     * 失败的LLM请求次数
     */
    @Builder.Default
    private Integer failedLLMRequests = 0;
    
    /**
     * 总消耗Token数
     */
    @Builder.Default
    private Long totalTokensUsed = 0L;
    
    // ==================== 章节信息 ====================
    
    /**
     * 处理的章节数量
     */
    private Integer processedChapterCount;
    
    /**
     * 处理的章节ID列表
     */
    @Builder.Default
    private List<String> processedChapterIds = new ArrayList<>();
    
    // ==================== 元数据 ====================
    
    /**
     * 创建时间
     */
    private LocalDateTime createdAt;
    
    /**
     * 更新时间
     */
    private LocalDateTime updatedAt;
    
    /**
     * 额外元数据
     */
    private Map<String, Object> metadata;
    
    /**
     * 导入状态枚举
     */
    public enum ImportStatus {
        PENDING("待处理"),
        FETCHING_CHAPTERS("获取章节中"),
        EXTRACTING("拆书中"),
        COMPLETED("已完成"),
        FAILED("失败"),
        CANCELLED("已取消");
        
        private final String displayName;
        
        ImportStatus(String displayName) {
            this.displayName = displayName;
        }
        
        public String getDisplayName() {
            return displayName;
        }
    }
    
    /**
     * LLM请求记录内嵌对象
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class LLMRequestRecord {
        
        /**
         * 请求ID
         */
        private String requestId;
        
        /**
         * 子任务ID
         */
        private String subTaskId;
        
        /**
         * 提取类型组
         */
        private String extractionGroup;
        
        /**
         * AI功能类型
         */
        private String featureType;
        
        /**
         * 请求开始时间
         */
        private LocalDateTime requestTime;
        
        /**
         * 请求完成时间
         */
        private LocalDateTime responseTime;
        
        /**
         * 是否成功
         */
        private Boolean success;
        
        /**
         * 错误信息
         */
        private String errorMessage;
        
        /**
         * 使用的Token数
         */
        private Long tokensUsed;
        
        /**
         * 生成的设定数量
         */
        private Integer generatedSettingsCount;
        
        /**
         * 生成的设定ID列表
         */
        @Builder.Default
        private List<String> generatedSettingIds = new ArrayList<>();
    }
}


