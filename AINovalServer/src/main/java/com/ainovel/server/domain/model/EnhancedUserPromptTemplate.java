package com.ainovel.server.domain.model;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 增强的用户提示词模板
 * 支持系统提示词、用户提示词、标签、评分、分享等功能
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "enhanced_user_prompt_templates")
public class EnhancedUserPromptTemplate {

    @Id
    private String id;

    /**
     * 用户ID
     */
    private String userId;

    /**
     * 功能类型
     */
    private AIFeatureType featureType;

    /**
     * 模板名称
     */
    private String name;

    /**
     * 模板描述
     */
    private String description;

    /**
     * 系统提示词
     */
    private String systemPrompt;

    /**
     * 用户提示词
     */
    private String userPrompt;

    /**
     * 标签列表
     */
    @Builder.Default
    private List<String> tags = new ArrayList<>();

    /**
     * 分类列表
     */
    @Builder.Default
    private List<String> categories = new ArrayList<>();

    /**
     * 是否公开（可分享）
     */
    @Builder.Default
    private Boolean isPublic = false;
    
    /**
     * 是否隐藏提示词（隐私保护）
     * true: 只显示描述和效果，不显示具体的 system/user prompt
     */
    @Builder.Default
    private Boolean hidePrompts = false;

    /**
     * 分享码（用于快速分享）
     */
    private String shareCode;
    
    /**
     * 点赞次数
     */
    @Builder.Default
    private Long likeCount = 0L;
    
    /**
     * 是否被当前用户点赞
     */
    @Builder.Default
    private Boolean isLiked = false;

    /**
     * 评分（1-5星）
     */
    private Double rating;

    /**
     * 评分统计
     */
    @Builder.Default
    private RatingStatistics ratingStatistics = new RatingStatistics();

    /**
     * 使用次数
     */
    @Builder.Default
    private Long usageCount = 0L;

    /**
     * 收藏次数（被其他用户收藏）
     */
    @Builder.Default
    private Long favoriteCount = 0L;

    /**
     * 是否被当前用户收藏
     */
    @Builder.Default
    private Boolean isFavorite = false;

    /**
     * 是否为默认模板（每个用户每个功能类型只能有一个默认模板）
     */
    @Builder.Default
    private Boolean isDefault = false;

    /**
     * 是否通过验证（官方认证）
     */
    @Builder.Default
    private Boolean isVerified = false;

    /**
     * 作者ID（原创作者）
     */
    private String authorId;

    /**
     * 作者名称（运行时填充，不存储）
     */
    @org.springframework.data.annotation.Transient
    private String authorName;

    /**
     * 作者头像（运行时填充，不存储）
     */
    @org.springframework.data.annotation.Transient
    private String authorAvatar;

    /**
     * 源模板ID（如果是复制的）
     */
    private String sourceTemplateId;

    /**
     * 版本号
     */
    @Builder.Default
    private Integer version = 1;

    /**
     * 语言
     */
    @Builder.Default
    private String language = "zh";

    /**
     * 创建时间
     */
    private LocalDateTime createdAt;

    /**
     * 更新时间
     */
    private LocalDateTime updatedAt;

    /**
     * 分享时间
     */
    private LocalDateTime sharedAt;

    /**
     * 最后使用时间
     */
    private LocalDateTime lastUsedAt;

    /**
     * 扩展属性（JSON格式）
     */
    private String extendedProperties;
    
    /**
     * 审核状态（用于模板分享审核）
     * DRAFT - 草稿（未提交审核）
     * PENDING - 待审核
     * APPROVED - 已通过
     * REJECTED - 已拒绝
     */
    private String reviewStatus;
    
    /**
     * 审核员ID
     */
    private String reviewerId;
    
    /**
     * 审核意见
     */
    private String reviewComment;
    
    /**
     * 审核时间
     */
    private LocalDateTime reviewedAt;
    
    /**
     * 提交审核时间
     */
    private LocalDateTime submittedAt;
    
    /**
     * 拒绝原因列表（用于详细审核反馈）
     */
    @Builder.Default
    private List<String> rejectionReasons = new ArrayList<>();
    
    /**
     * 改进建议列表（用于审核指导）
     */
    @Builder.Default
    private List<String> improvementSuggestions = new ArrayList<>();
    
    /**
     * 审核优先级：LOW, NORMAL, HIGH, URGENT
     */
    private String reviewPriority;
    
    /**
     * 设定生成配置
     * 当功能类型为 SETTING_TREE_GENERATION 时使用
     */
    private SettingGenerationConfig settingGenerationConfig;

    /**
     * 评分统计内部类
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RatingStatistics {
        @Builder.Default
        private Long totalRatings = 0L;
        @Builder.Default
        private Double averageRating = 0.0;
        @Builder.Default
        private Long fiveStarCount = 0L;
        @Builder.Default
        private Long fourStarCount = 0L;
        @Builder.Default
        private Long threeStarCount = 0L;
        @Builder.Default
        private Long twoStarCount = 0L;
        @Builder.Default
        private Long oneStarCount = 0L;
    }

    /**
     * 增加使用次数
     */
    public void incrementUsageCount() {
        this.usageCount = (this.usageCount == null ? 0L : this.usageCount) + 1;
        this.lastUsedAt = LocalDateTime.now();
    }

    /**
     * 增加收藏次数
     */
    public void incrementFavoriteCount() {
        this.favoriteCount = (this.favoriteCount == null ? 0L : this.favoriteCount) + 1;
    }

    /**
     * 减少收藏次数
     */
    public void decrementFavoriteCount() {
        this.favoriteCount = Math.max(0L, (this.favoriteCount == null ? 0L : this.favoriteCount) - 1);
    }
    
    /**
     * 增加点赞次数
     */
    public void incrementLikeCount() {
        this.likeCount = (this.likeCount == null ? 0L : this.likeCount) + 1;
    }
    
    /**
     * 减少点赞次数
     */
    public void decrementLikeCount() {
        this.likeCount = Math.max(0L, (this.likeCount == null ? 0L : this.likeCount) - 1);
    }

    /**
     * 更新评分统计
     */
    public void updateRatingStatistics(int newRating) {
        if (ratingStatistics == null) {
            ratingStatistics = new RatingStatistics();
        }

        // 增加对应星级的计数
        switch (newRating) {
            case 5: ratingStatistics.fiveStarCount++; break;
            case 4: ratingStatistics.fourStarCount++; break;
            case 3: ratingStatistics.threeStarCount++; break;
            case 2: ratingStatistics.twoStarCount++; break;
            case 1: ratingStatistics.oneStarCount++; break;
        }

        // 更新总数和平均分
        ratingStatistics.totalRatings++;
        long total = ratingStatistics.fiveStarCount * 5 + ratingStatistics.fourStarCount * 4 +
                    ratingStatistics.threeStarCount * 3 + ratingStatistics.twoStarCount * 2 +
                    ratingStatistics.oneStarCount * 1;
        ratingStatistics.averageRating = (double) total / ratingStatistics.totalRatings;
        
        // 更新主评分字段
        this.rating = ratingStatistics.averageRating;
    }
    
    /**
     * 检查是否为设定生成模板
     */
    public boolean isSettingGenerationTemplate() {
        return AIFeatureType.SETTING_TREE_GENERATION.equals(this.featureType);
    }
    
    /**
     * 获取或创建设定生成配置
     */
    public SettingGenerationConfig getOrCreateSettingGenerationConfig() {
        if (this.settingGenerationConfig == null) {
            this.settingGenerationConfig = SettingGenerationConfig.builder().build();
        }
        return this.settingGenerationConfig;
    }
} 