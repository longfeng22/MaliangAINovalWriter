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
 * 小说知识库领域实体
 * 存储番茄小说或用户导入文本的拆书结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "novel_knowledge_bases")
@CompoundIndexes({
    @CompoundIndex(name = "fanqie_novel_idx", def = "{'fanqieNovelId': 1}", unique = true, sparse = true),
    @CompoundIndex(name = "public_status_idx", def = "{'isPublic': 1, 'status': 1}"),
    @CompoundIndex(name = "user_status_idx", def = "{'firstImportUserId': 1, 'status': 1}"),
    @CompoundIndex(name = "reference_count_idx", def = "{'referenceCount': -1}"),
    @CompoundIndex(name = "like_count_idx", def = "{'likeCount': -1}"),
    @CompoundIndex(name = "import_time_idx", def = "{'firstImportTime': -1}")
})
public class NovelKnowledgeBase {
    
    @Id
    private String id;
    
    // ==================== 基本信息 ====================
    
    /**
     * 番茄小说ID（如果是番茄小说来源）
     */
    @Indexed(unique = true, sparse = true)
    private String fanqieNovelId;
    
    /**
     * 小说标题
     */
    private String title;
    
    /**
     * 小说简介
     */
    private String description;
    
    /**
     * 小说封面URL
     */
    private String coverImageUrl;
    
    /**
     * 小说作者
     */
    private String author;
    
    /**
     * 是否是用户导入的小说
     */
    @Builder.Default
    private Boolean isUserImported = false;
    
    /**
     * 小说完结状态
     */
    private NovelCompletionStatus completionStatus;
    
    /**
     * 小说标签
     */
    @Builder.Default
    private List<String> tags = new ArrayList<>();
    
    // ==================== 知识库内容 ====================
    
    /**
     * 文风叙事类设定列表
     */
    @Builder.Default
    private List<NovelSettingItem> narrativeStyleSettings = new ArrayList<>();
    
    /**
     * 人物情节类设定列表
     */
    @Builder.Default
    private List<NovelSettingItem> characterPlotSettings = new ArrayList<>();
    
    /**
     * 小说特点类设定列表（世界观、金手指等）
     */
    @Builder.Default
    private List<NovelSettingItem> novelFeatureSettings = new ArrayList<>();
    
    /**
     * 热梗搞笑点设定列表
     */
    @Builder.Default
    private List<NovelSettingItem> hotMemesSettings = new ArrayList<>();
    
    /**
     * 用户自定义设定列表
     */
    @Builder.Default
    private List<NovelSettingItem> customSettings = new ArrayList<>();
    
    /**
     * 读者情绪设定列表（共鸣、爽点、嗨点）
     */
    @Builder.Default
    private List<NovelSettingItem> readerEmotionSettings = new ArrayList<>();
    
    /**
     * 章节大纲外键引用（novelId）
     * 关联到 Novel 实体的章节结构
     */
    private String outlineNovelId;
    
    // ==================== 统计和状态 ====================
    
    /**
     * 缓存状态
     */
    @Builder.Default
    private CacheStatus status = CacheStatus.PENDING;
    
    /**
     * 是否成功缓存
     */
    @Builder.Default
    private Boolean cacheSuccess = false;
    
    /**
     * 缓存失败原因
     */
    private String cacheFailureReason;
    
    /**
     * 缓存时间
     */
    private LocalDateTime cacheTime;
    
    /**
     * 被引用次数
     */
    @Builder.Default
    private Integer referenceCount = 0;
    
    /**
     * 被查看次数
     */
    @Builder.Default
    private Integer viewCount = 0;
    
    /**
     * 点赞次数
     */
    @Builder.Default
    private Integer likeCount = 0;
    
    /**
     * 点赞用户ID列表
     */
    @Builder.Default
    private List<String> likedUserIds = new ArrayList<>();
    
    /**
     * 是否公开
     */
    @Builder.Default
    private Boolean isPublic = false;
    
    /**
     * 第一次导入用户ID
     */
    private String firstImportUserId;
    
    /**
     * 第一次导入时间
     */
    private LocalDateTime firstImportTime;
    
    /**
     * 拆书任务ID（关联后台任务）
     */
    private String extractionTaskId;
    
    /**
     * 拆书使用的模型配置ID
     */
    private String modelConfigId;
    
    /**
     * 拆书使用的模型类型（public/user）
     */
    private String modelType;
    
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
     * 小说完结状态枚举
     */
    public enum NovelCompletionStatus {
        ONGOING("连载中"),
        COMPLETED("已完结"),
        PAUSED("暂停中"),
        UNKNOWN("未知");
        
        private final String displayName;
        
        NovelCompletionStatus(String displayName) {
            this.displayName = displayName;
        }
        
        public String getDisplayName() {
            return displayName;
        }
    }
    
    /**
     * 缓存状态枚举
     */
    public enum CacheStatus {
        PENDING("待处理"),
        PROCESSING("处理中"),
        COMPLETED("已完成"),
        FAILED("失败"),
        PARTIAL("部分完成");
        
        private final String displayName;
        
        CacheStatus(String displayName) {
            this.displayName = displayName;
        }
        
        public String getDisplayName() {
            return displayName;
        }
    }
}


