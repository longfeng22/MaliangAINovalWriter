package com.ainovel.server.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * AI拆书任务记录
 * 用于追踪每个拆书任务的完整生命周期和进度
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "knowledge_extraction_task_records")
public class KnowledgeExtractionTaskRecord {
    
    @Id
    private String id;  // 等同于 BackgroundTask 的 taskId
    
    // ===== 基础信息 =====
    @Indexed
    private String userId;  // 用户ID
    
    @Indexed
    private String importRecordId;  // 导入记录ID
    
    private String fanqieNovelId;  // 番茄小说ID（如果是番茄小说）
    
    private String novelTitle;  // 小说标题
    
    private String novelAuthor;  // 小说作者
    
    private String coverImageUrl;  // 封面图片
    
    private SourceType sourceType;  // 来源类型
    
    // ===== 任务状态 =====
    @Indexed
    private TaskStatus status;  // 任务状态
    
    private Integer progress;  // 总进度（0-100）
    
    private String currentStep;  // 当前步骤
    
    @Indexed
    private LocalDateTime startTime;  // 开始时间
    
    private LocalDateTime endTime;  // 结束时间
    
    private Long durationMs;  // 执行耗时（毫秒）
    
    // ===== 子任务信息 =====
    private Integer totalSubTasks;  // 总子任务数
    
    private Integer completedSubTasks;  // 已完成子任务数
    
    private Integer failedSubTasks;  // 失败子任务数
    
    private List<SubTaskInfo> subTasks;  // 子任务详情列表
    
    // ===== 执行结果 =====
    private String knowledgeBaseId;  // 生成的知识库ID
    
    private Integer totalSettings;  // 生成的设定总数
    
    private Long totalTokens;  // 消耗的总token数
    
    // ===== 错误信息 =====
    private String errorMessage;  // 错误信息
    
    private String errorStack;  // 错误堆栈
    
    private FailureReason failureReason;  // 失败原因分类
    
    // ===== 重试信息 =====
    private Integer retryCount;  // 重试次数
    
    private String originalTaskId;  // 原始任务ID（重试时记录）
    
    private LocalDateTime lastRetryTime;  // 最后重试时间
    
    // ===== 配置信息 =====
    private String modelConfigId;  // 使用的模型配置ID
    
    private String modelType;  // 模型类型
    
    private List<String> extractionTypes;  // 提取类型列表
    
    // ===== 元数据 =====
    private Map<String, Object> metadata;  // 其他元数据
    
    @Indexed
    private LocalDateTime createdAt;  // 创建时间
    
    private LocalDateTime updatedAt;  // 更新时间
    
    // ===== 枚举定义 =====
    
    /**
     * 任务状态
     */
    public enum TaskStatus {
        QUEUED,         // 已排队
        INITIALIZING,   // 初始化中
        DOWNLOADING,    // 下载小说中
        EXTRACTING,     // 提取知识中
        AGGREGATING,    // 聚合结果中
        COMPLETED,      // 已完成
        FAILED,         // 失败
        CANCELLED       // 已取消
    }
    
    /**
     * 来源类型
     */
    public enum SourceType {
        FANQIE_NOVEL,   // 番茄小说
        USER_TEXT       // 用户文本
    }
    
    /**
     * 失败原因分类
     */
    public enum FailureReason {
        DOWNLOAD_FAILED,        // 下载失败
        AI_CALL_FAILED,         // AI调用失败
        PARSE_FAILED,           // 解析失败
        TIMEOUT,                // 超时
        RATE_LIMIT,             // 速率限制
        SUBTASK_FAILED,         // 子任务失败
        AGGREGATION_FAILED,     // 聚合失败
        DATABASE_ERROR,         // 数据库错误
        UNKNOWN                 // 未知错误
    }
    
    /**
     * 子任务信息
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class SubTaskInfo {
        private String subTaskId;           // 子任务ID
        private String groupName;           // 组名称
        private List<String> extractionTypes;  // 提取类型
        private SubTaskStatus status;       // 状态
        private Integer progress;           // 进度
        private Integer extractedCount;     // 已提取数量
        private Long tokensUsed;           // 消耗token数
        private String errorMessage;        // 错误信息
        private LocalDateTime startTime;    // 开始时间
        private LocalDateTime endTime;      // 结束时间
        
        public enum SubTaskStatus {
            PENDING,        // 待执行
            RUNNING,        // 执行中
            COMPLETED,      // 已完成
            FAILED          // 失败
        }
    }
    
    // ===== 工具方法 =====
    
    /**
     * 计算任务执行时长
     */
    public void calculateDuration() {
        if (startTime != null && endTime != null) {
            this.durationMs = java.time.Duration.between(startTime, endTime).toMillis();
        }
    }
    
    /**
     * 更新进度
     */
    public void updateProgress() {
        if (totalSubTasks != null && totalSubTasks > 0 && completedSubTasks != null) {
            this.progress = (int) ((completedSubTasks * 100.0) / totalSubTasks);
        }
    }
    
    /**
     * 判断是否可以重试
     */
    public boolean canRetry() {
        return status == TaskStatus.FAILED && 
               (retryCount == null || retryCount < 3);
    }
    
    /**
     * 判断是否完成
     */
    public boolean isCompleted() {
        return status == TaskStatus.COMPLETED;
    }
    
    /**
     * 判断是否失败
     */
    public boolean isFailed() {
        return status == TaskStatus.FAILED;
    }
}


