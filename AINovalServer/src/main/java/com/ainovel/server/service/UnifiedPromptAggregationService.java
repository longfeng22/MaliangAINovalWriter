package com.ainovel.server.service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;

import reactor.core.publisher.Mono;

/**
 * 统一提示词聚合服务接口
 * 为前端提供一站式的提示词获取和缓存接口
 */
public interface UnifiedPromptAggregationService {

    /**
     * 获取功能的完整提示词包（包括系统默认、用户自定义、公开模板等）
     * 
     * @param featureType 功能类型
     * @param userId 用户ID
     * @param includePublic 是否包含公开模板
     * @return 完整的提示词包
     */
    Mono<PromptPackage> getCompletePromptPackage(AIFeatureType featureType, String userId, boolean includePublic);

    /**
     * 获取用户的所有提示词概览（跨功能）
     * 
     * @param userId 用户ID
     * @return 用户提示词概览
     */
    Mono<UserPromptOverview> getUserPromptOverview(String userId);

    /**
     * 预热缓存（用于系统启动时）
     * 
     * @param userId 用户ID
     * @return 预热结果
     */
    Mono<CacheWarmupResult> warmupCache(String userId);

    /**
     * 获取聚合服务的缓存统计
     * 
     * @return 缓存统计信息
     */
    Mono<AggregationCacheStats> getCacheStats();

    /**
     * 清除所有提示词包缓存
     * 
     * @return 清除结果
     */
    Mono<String> clearAllCaches();

    /**
     * 清除指定用户的缓存
     * 
     * @param userId 用户ID
     * @return 清除结果
     */
    Mono<String> clearUserCache(String userId);

    // ==================== 数据传输对象 ====================

    /**
     * 完整的提示词包
     */
    class PromptPackage {
        private final AIFeatureType featureType;
        private final SystemPromptInfo systemPrompt;
        private final List<UserPromptInfo> userPrompts;
        private final List<PublicPromptInfo> publicPrompts;
        private final List<RecentPromptInfo> recentlyUsed;
        private final Set<String> supportedPlaceholders;
        private final Map<String, String> placeholderDescriptions;
        private final LocalDateTime lastUpdated;

        public PromptPackage(AIFeatureType featureType, SystemPromptInfo systemPrompt,
                           List<UserPromptInfo> userPrompts, List<PublicPromptInfo> publicPrompts,
                           List<RecentPromptInfo> recentlyUsed, Set<String> supportedPlaceholders,
                           Map<String, String> placeholderDescriptions, LocalDateTime lastUpdated) {
            this.featureType = featureType;
            this.systemPrompt = systemPrompt;
            this.userPrompts = userPrompts;
            this.publicPrompts = publicPrompts;
            this.recentlyUsed = recentlyUsed;
            this.supportedPlaceholders = supportedPlaceholders;
            this.placeholderDescriptions = placeholderDescriptions;
            this.lastUpdated = lastUpdated;
        }

        // Getters
        public AIFeatureType getFeatureType() { return featureType; }
        public SystemPromptInfo getSystemPrompt() { return systemPrompt; }
        public List<UserPromptInfo> getUserPrompts() { return userPrompts; }
        public List<PublicPromptInfo> getPublicPrompts() { return publicPrompts; }
        public List<RecentPromptInfo> getRecentlyUsed() { return recentlyUsed; }
        public Set<String> getSupportedPlaceholders() { return supportedPlaceholders; }
        public Map<String, String> getPlaceholderDescriptions() { return placeholderDescriptions; }
        public LocalDateTime getLastUpdated() { return lastUpdated; }
    }

    /**
     * 系统提示词信息
     */
    class SystemPromptInfo {
        private final String defaultSystemPrompt;
        private final String defaultUserPrompt;
        private final String userCustomSystemPrompt;
        private final boolean hasUserCustom;

        public SystemPromptInfo(String defaultSystemPrompt, String defaultUserPrompt, String userCustomSystemPrompt, boolean hasUserCustom) {
            this.defaultSystemPrompt = defaultSystemPrompt;
            this.defaultUserPrompt = defaultUserPrompt;
            this.userCustomSystemPrompt = userCustomSystemPrompt;
            this.hasUserCustom = hasUserCustom;
        }

        public String getDefaultSystemPrompt() { return defaultSystemPrompt; }
        public String getDefaultUserPrompt() { return defaultUserPrompt; }
        public String getUserCustomSystemPrompt() { return userCustomSystemPrompt; }
        public boolean isHasUserCustom() { return hasUserCustom; }
    }

    /**
     * 用户提示词信息
     */
    class UserPromptInfo {
        private final String id;
        private final String name;
        private final String description;
        private final AIFeatureType featureType;
        private final String systemPrompt;
        private final String userPrompt;
        private final List<String> tags;
        private final List<String> categories;
        private final boolean isFavorite;
        private final boolean isDefault;
        private final boolean isPublic;
        private final String shareCode;
        private final boolean isVerified;
        private final Long usageCount;
        private final Long favoriteCount;
        private final Double rating;
        private final String authorId;
        private final Integer version;
        private final String language;
        private final LocalDateTime createdAt;
        private final LocalDateTime lastUsedAt;
        private final LocalDateTime updatedAt;
        private final String reviewStatus; // 🆕 审核状态: DRAFT, PENDING, APPROVED, REJECTED
        private final boolean hidePrompts; // 🆕 是否隐藏提示词
        private final com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig settingGenerationConfig; // 🆕 设定生成配置

        public UserPromptInfo(String id, String name, String description, AIFeatureType featureType,
                            String systemPrompt, String userPrompt, List<String> tags, List<String> categories,
                            boolean isFavorite, boolean isDefault, boolean isPublic, String shareCode,
                            boolean isVerified, Long usageCount, Long favoriteCount, Double rating,
                            String authorId, Integer version, String language, LocalDateTime createdAt,
                            LocalDateTime lastUsedAt, LocalDateTime updatedAt, String reviewStatus, boolean hidePrompts,
                            com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig settingGenerationConfig) {
            this.id = id;
            this.name = name;
            this.description = description;
            this.featureType = featureType;
            this.systemPrompt = systemPrompt;
            this.userPrompt = userPrompt;
            this.tags = tags;
            this.categories = categories;
            this.isFavorite = isFavorite;
            this.isDefault = isDefault;
            this.isPublic = isPublic;
            this.shareCode = shareCode;
            this.isVerified = isVerified;
            this.usageCount = usageCount;
            this.favoriteCount = favoriteCount;
            this.rating = rating;
            this.authorId = authorId;
            this.version = version;
            this.language = language;
            this.createdAt = createdAt;
            this.lastUsedAt = lastUsedAt;
            this.updatedAt = updatedAt;
            this.reviewStatus = reviewStatus; // 🆕 审核状态
            this.hidePrompts = hidePrompts; // 🆕 是否隐藏提示词
            this.settingGenerationConfig = settingGenerationConfig; // 🆕 设定生成配置
        }

        // Getters
        public String getId() { return id; }
        public String getName() { return name; }
        public String getDescription() { return description; }
        public AIFeatureType getFeatureType() { return featureType; }
        public String getSystemPrompt() { return systemPrompt; }
        public String getUserPrompt() { return userPrompt; }
        public List<String> getTags() { return tags; }
        public List<String> getCategories() { return categories; }
        public boolean isFavorite() { return isFavorite; }
        public boolean isDefault() { return isDefault; }
        public boolean isPublic() { return isPublic; }
        public String getShareCode() { return shareCode; }
        public boolean isVerified() { return isVerified; }
        public Long getUsageCount() { return usageCount; }
        public Long getFavoriteCount() { return favoriteCount; }
        public Double getRating() { return rating; }
        public String getAuthorId() { return authorId; }
        public Integer getVersion() { return version; }
        public String getLanguage() { return language; }
        public LocalDateTime getCreatedAt() { return createdAt; }
        public LocalDateTime getLastUsedAt() { return lastUsedAt; }
        public LocalDateTime getUpdatedAt() { return updatedAt; }
        public String getReviewStatus() { return reviewStatus; } // 🆕 审核状态getter
        public boolean isHidePrompts() { return hidePrompts; } // 🆕 是否隐藏提示词getter
        public com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig getSettingGenerationConfig() { return settingGenerationConfig; } // 🆕 设定生成配置getter
    }

    /**
     * 公开提示词信息
     */
    class PublicPromptInfo {
        private final String id;
        private final String name;
        private final String description;
        private final String authorName;
        private final AIFeatureType featureType;
        private final String systemPrompt;
        private final String userPrompt;
        private final List<String> tags;
        private final List<String> categories;
        private final Double rating;
        private final Long usageCount;
        private final Long favoriteCount;
        private final String shareCode;
        private final boolean isVerified;
        private final String language;
        private final Integer version;
        private final LocalDateTime createdAt;
        private final LocalDateTime updatedAt;
        private final LocalDateTime lastUsedAt;

        public PublicPromptInfo(String id, String name, String description, String authorName,
                              AIFeatureType featureType, String systemPrompt, String userPrompt,
                              List<String> tags, List<String> categories, Double rating, Long usageCount, 
                              Long favoriteCount, String shareCode, boolean isVerified, String language,
                              Integer version, LocalDateTime createdAt, LocalDateTime updatedAt, 
                              LocalDateTime lastUsedAt) {
            this.id = id;
            this.name = name;
            this.description = description;
            this.authorName = authorName;
            this.featureType = featureType;
            this.systemPrompt = systemPrompt;
            this.userPrompt = userPrompt;
            this.tags = tags;
            this.categories = categories;
            this.rating = rating;
            this.usageCount = usageCount;
            this.favoriteCount = favoriteCount;
            this.shareCode = shareCode;
            this.isVerified = isVerified;
            this.language = language;
            this.version = version;
            this.createdAt = createdAt;
            this.updatedAt = updatedAt;
            this.lastUsedAt = lastUsedAt;
        }

        // Getters
        public String getId() { return id; }
        public String getName() { return name; }
        public String getDescription() { return description; }
        public String getAuthorName() { return authorName; }
        public AIFeatureType getFeatureType() { return featureType; }
        public String getSystemPrompt() { return systemPrompt; }
        public String getUserPrompt() { return userPrompt; }
        public List<String> getTags() { return tags; }
        public List<String> getCategories() { return categories; }
        public Double getRating() { return rating; }
        public Long getUsageCount() { return usageCount; }
        public Long getFavoriteCount() { return favoriteCount; }
        public String getShareCode() { return shareCode; }
        public boolean isVerified() { return isVerified; }
        public String getLanguage() { return language; }
        public Integer getVersion() { return version; }
        public LocalDateTime getCreatedAt() { return createdAt; }
        public LocalDateTime getUpdatedAt() { return updatedAt; }
        public LocalDateTime getLastUsedAt() { return lastUsedAt; }
    }

    /**
     * 最近使用的提示词信息
     */
    class RecentPromptInfo {
        private final String id;
        private final String name;
        private final String description;
        private final AIFeatureType featureType;
        private final List<String> tags;
        private final boolean isDefault;
        private final boolean isFavorite;
        private final Double rating;
        private final LocalDateTime lastUsedAt;
        private final Long usageCount;

        public RecentPromptInfo(String id, String name, String description, AIFeatureType featureType,
                              List<String> tags, boolean isDefault, boolean isFavorite, Double rating,
                              LocalDateTime lastUsedAt, Long usageCount) {
            this.id = id;
            this.name = name;
            this.description = description;
            this.featureType = featureType;
            this.tags = tags;
            this.isDefault = isDefault;
            this.isFavorite = isFavorite;
            this.rating = rating;
            this.lastUsedAt = lastUsedAt;
            this.usageCount = usageCount;
        }

        public String getId() { return id; }
        public String getName() { return name; }
        public String getDescription() { return description; }
        public AIFeatureType getFeatureType() { return featureType; }
        public List<String> getTags() { return tags; }
        public boolean isDefault() { return isDefault; }
        public boolean isFavorite() { return isFavorite; }
        public Double getRating() { return rating; }
        public LocalDateTime getLastUsedAt() { return lastUsedAt; }
        public Long getUsageCount() { return usageCount; }
    }

    /**
     * 用户提示词概览
     */
    class UserPromptOverview {
        private final String userId;
        private final Map<AIFeatureType, Integer> promptCountsByFeature;
        private final List<RecentPromptInfo> globalRecentlyUsed;
        private final List<UserPromptInfo> favoritePrompts;
        private final Set<String> allTags;
        private final Long totalUsageCount;
        private final LocalDateTime lastActiveAt;

        public UserPromptOverview(String userId, Map<AIFeatureType, Integer> promptCountsByFeature,
                                List<RecentPromptInfo> globalRecentlyUsed, List<UserPromptInfo> favoritePrompts,
                                Set<String> allTags, Long totalUsageCount, LocalDateTime lastActiveAt) {
            this.userId = userId;
            this.promptCountsByFeature = promptCountsByFeature;
            this.globalRecentlyUsed = globalRecentlyUsed;
            this.favoritePrompts = favoritePrompts;
            this.allTags = allTags;
            this.totalUsageCount = totalUsageCount;
            this.lastActiveAt = lastActiveAt;
        }

        // Getters
        public String getUserId() { return userId; }
        public Map<AIFeatureType, Integer> getPromptCountsByFeature() { return promptCountsByFeature; }
        public List<RecentPromptInfo> getGlobalRecentlyUsed() { return globalRecentlyUsed; }
        public List<UserPromptInfo> getFavoritePrompts() { return favoritePrompts; }
        public Set<String> getAllTags() { return allTags; }
        public Long getTotalUsageCount() { return totalUsageCount; }
        public LocalDateTime getLastActiveAt() { return lastActiveAt; }
    }

    /**
     * 缓存预热结果
     */
    class CacheWarmupResult {
        private final boolean success;
        private final long duration;
        private final int warmedFeatures;
        private final int warmedPrompts;
        private final String errorMessage;

        public CacheWarmupResult(boolean success, long duration, int warmedFeatures, 
                               int warmedPrompts, String errorMessage) {
            this.success = success;
            this.duration = duration;
            this.warmedFeatures = warmedFeatures;
            this.warmedPrompts = warmedPrompts;
            this.errorMessage = errorMessage;
        }

        public boolean isSuccess() { return success; }
        public long getDuration() { return duration; }
        public int getWarmedFeatures() { return warmedFeatures; }
        public int getWarmedPrompts() { return warmedPrompts; }
        public String getErrorMessage() { return errorMessage; }
    }

    /**
     * 聚合缓存统计
     */
    class AggregationCacheStats {
        private final Map<String, Long> cacheHitCounts;
        private final Map<String, Long> cacheMissCounts;
        private final Map<String, Double> cacheHitRates;
        private final long totalCacheSize;
        private final LocalDateTime lastClearTime;

        public AggregationCacheStats(Map<String, Long> cacheHitCounts, Map<String, Long> cacheMissCounts,
                                   Map<String, Double> cacheHitRates, long totalCacheSize, 
                                   LocalDateTime lastClearTime) {
            this.cacheHitCounts = cacheHitCounts;
            this.cacheMissCounts = cacheMissCounts;
            this.cacheHitRates = cacheHitRates;
            this.totalCacheSize = totalCacheSize;
            this.lastClearTime = lastClearTime;
        }

        // Getters
        public Map<String, Long> getCacheHitCounts() { return cacheHitCounts; }
        public Map<String, Long> getCacheMissCounts() { return cacheMissCounts; }
        public Map<String, Double> getCacheHitRates() { return cacheHitRates; }
        public long getTotalCacheSize() { return totalCacheSize; }
        public LocalDateTime getLastClearTime() { return lastClearTime; }
    }
} 