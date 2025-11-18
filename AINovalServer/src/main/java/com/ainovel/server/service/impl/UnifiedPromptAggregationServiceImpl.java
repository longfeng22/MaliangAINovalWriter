package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.service.EnhancedUserPromptService;
import com.ainovel.server.service.UnifiedPromptAggregationService;
import com.ainovel.server.service.UnifiedPromptService;
import com.ainovel.server.service.prompt.AIFeaturePromptProvider;
import com.ainovel.server.service.prompt.PromptProviderFactory;
import com.ainovel.server.service.prompt.impl.VirtualThreadPlaceholderResolver;
import com.ainovel.server.service.prompt.PlaceholderDescriptionService;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 统一提示词聚合服务实现
 * 集成虚拟线程优化、缓存机制和前端友好的数据聚合
 */
@Slf4j
@Service
public class UnifiedPromptAggregationServiceImpl implements UnifiedPromptAggregationService {

    @Autowired
    private PromptProviderFactory promptProviderFactory;
    
    @Autowired
    private EnhancedUserPromptService enhancedUserPromptService;
    
    @Autowired
    private UnifiedPromptService unifiedPromptService;
    
    @Autowired
    private VirtualThreadPlaceholderResolver virtualThreadResolver;
    
    @Autowired
    private PlaceholderDescriptionService placeholderDescriptionService;

    // 缓存统计
    private final Map<String, Long> cacheHitCounts = new ConcurrentHashMap<>();
    private final Map<String, Long> cacheMissCounts = new ConcurrentHashMap<>();
    private LocalDateTime lastCacheCleanTime = LocalDateTime.now();

    @Override
    @Cacheable(value = "promptPackages", key = "#featureType + ':' + #userId + ':' + #includePublic")
    public Mono<PromptPackage> getCompletePromptPackage(AIFeatureType featureType, String userId, boolean includePublic) {
        long startTime = System.currentTimeMillis();
        log.info("开始获取完整提示词包: featureType={}, userId={}, includePublic={}", 
                featureType, userId, includePublic);

        return Mono.fromCallable(() -> {
            // 更新缓存统计
            String cacheKey = featureType + ":" + userId + ":" + includePublic;
            cacheHitCounts.merge(cacheKey, 1L, Long::sum);
            
            return featureType;
        })
        .flatMap(ft -> buildPromptPackage(ft, userId, includePublic))
        .doOnSuccess(pkg -> {
            long duration = System.currentTimeMillis() - startTime;
            log.info("提示词包构建完成: featureType={}, 耗时={}ms, 用户模板数={}, 公开模板数={}", 
                    featureType, duration, pkg.getUserPrompts().size(), pkg.getPublicPrompts().size());
        })
        .doOnError(error -> {
            log.error("提示词包构建失败: featureType={}, error={}", featureType, error.getMessage());
            // 记录缓存未命中
            String cacheKey = featureType + ":" + userId + ":" + includePublic;
            cacheMissCounts.merge(cacheKey, 1L, Long::sum);
        });
    }

    @Override
    @Cacheable(value = "userPromptOverviews", key = "#userId")
    public Mono<UserPromptOverview> getUserPromptOverview(String userId) {
        log.info("获取用户提示词概览: userId={}", userId);
        
        // 并行获取各种统计信息
        Mono<Map<AIFeatureType, Integer>> countsByFeature = getPromptCountsByFeature(userId);
        Mono<List<RecentPromptInfo>> recentlyUsed = getGlobalRecentlyUsed(userId);
        Mono<List<UserPromptInfo>> favoritePrompts = getFavoritePrompts(userId);
        Mono<Set<String>> allTags = getAllUserTags(userId);
        Mono<Long> totalUsage = getTotalUsageCount(userId);
        
        return Mono.zip(countsByFeature, recentlyUsed, favoritePrompts, allTags, totalUsage)
                .map(tuple -> new UserPromptOverview(
                        userId,
                        tuple.getT1(), // countsByFeature
                        tuple.getT2(), // recentlyUsed
                        tuple.getT3(), // favoritePrompts
                        tuple.getT4(), // allTags
                        tuple.getT5(), // totalUsage
                        LocalDateTime.now() // lastActiveAt
                ));
    }

    @Override
    public Mono<CacheWarmupResult> warmupCache(String userId) {
        long startTime = System.currentTimeMillis();
        log.info("开始缓存预热: userId={}", userId);
        
        return Flux.fromArray(AIFeatureType.values())
                .flatMap(featureType -> 
                    getCompletePromptPackage(featureType, userId, true)
                        .onErrorResume(error -> {
                            log.warn("功能预热失败: featureType={}, error={}", featureType, error.getMessage());
                            return Mono.empty();
                        })
                )
                .count()
                .zipWith(getUserPromptOverview(userId).onErrorReturn(new UserPromptOverview(
                        userId, Collections.emptyMap(), Collections.emptyList(),
                        Collections.emptyList(), Collections.emptySet(), 0L, LocalDateTime.now()
                )))
                .map(tuple -> {
                    long duration = System.currentTimeMillis() - startTime;
                    int warmedFeatures = tuple.getT1().intValue();
                    
                    log.info("缓存预热完成: userId={}, 耗时={}ms, 预热功能数={}", userId, duration, warmedFeatures);
                    
                    return new CacheWarmupResult(
                            true, duration, warmedFeatures, 0, null
                    );
                })
                .onErrorReturn(new CacheWarmupResult(
                        false, System.currentTimeMillis() - startTime, 0, 0, "预热过程中发生错误"
                ));
    }

    @Override
    public Mono<AggregationCacheStats> getCacheStats() {
        return Mono.fromCallable(() -> {
            Map<String, Double> hitRates = new HashMap<>();
            
            for (String key : cacheHitCounts.keySet()) {
                long hits = cacheHitCounts.getOrDefault(key, 0L);
                long misses = cacheMissCounts.getOrDefault(key, 0L);
                double hitRate = hits + misses > 0 ? (double) hits / (hits + misses) : 0.0;
                hitRates.put(key, hitRate);
            }
            
            return new AggregationCacheStats(
                    new HashMap<>(cacheHitCounts),
                    new HashMap<>(cacheMissCounts),
                    hitRates,
                    cacheHitCounts.size() + cacheMissCounts.size(),
                    lastCacheCleanTime
            );
        });
    }

    /**
     * 清除所有提示词包缓存
     */
    @CacheEvict(value = {"promptPackages", "userPromptOverviews"}, allEntries = true)
    public Mono<String> clearAllCaches() {
        log.info("清除所有提示词聚合缓存");
        return Mono.just("缓存已清除");
    }

    /**
     * 清除指定用户的缓存
     */
    @CacheEvict(value = {"promptPackages", "userPromptOverviews"}, allEntries = true)
    public Mono<String> clearUserCache(String userId) {
        log.info("清除用户缓存: userId={}", userId);
        return Mono.just("用户缓存已清除");
    }

    // ==================== 私有辅助方法 ====================

    /**
     * 构建完整的提示词包
     */
    private Mono<PromptPackage> buildPromptPackage(AIFeatureType featureType, String userId, boolean includePublic) {
        // 获取功能提供器
        AIFeaturePromptProvider provider = promptProviderFactory.getProvider(featureType);
        if (provider == null) {
            return Mono.error(new IllegalArgumentException("不支持的功能类型: " + featureType));
        }

        // 并行获取各种数据
        Mono<SystemPromptInfo> systemPrompt = buildSystemPromptInfo(provider, userId);
        Mono<List<UserPromptInfo>> userPrompts = buildUserPromptInfos(featureType, userId);
        Mono<List<PublicPromptInfo>> publicPrompts = includePublic ? 
                buildPublicPromptInfos(featureType) : Mono.just(Collections.emptyList());
        Mono<List<RecentPromptInfo>> recentlyUsed = buildRecentPromptInfos(featureType, userId);

        return Mono.zip(systemPrompt, userPrompts, publicPrompts, recentlyUsed)
                .map(tuple -> {
                    // 使用统一提示词服务获取过滤后的占位符
                    Set<String> filteredPlaceholders = unifiedPromptService.getSupportedPlaceholders(featureType);
                    
                    // 同样过滤占位符描述，只保留可用的占位符描述
                    Map<String, String> allDescriptions = provider.getPlaceholderDescriptions();
                    Map<String, String> filteredDescriptions = allDescriptions.entrySet().stream()
                            .filter(entry -> filteredPlaceholders.contains(entry.getKey()))
                            .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
                    
                    log.debug("占位符过滤结果: 功能={}, 原始占位符数={}, 过滤后占位符数={}", 
                             featureType, provider.getSupportedPlaceholders().size(), filteredPlaceholders.size());
                    
                    return new PromptPackage(
                            featureType,
                            tuple.getT1(), // systemPrompt
                            tuple.getT2(), // userPrompts
                            tuple.getT3(), // publicPrompts
                            tuple.getT4(), // recentlyUsed
                            filteredPlaceholders,
                            filteredDescriptions,
                            LocalDateTime.now()
                    );
                });
    }

    /**
     * 构建系统提示词信息
     */
    private Mono<SystemPromptInfo> buildSystemPromptInfo(AIFeaturePromptProvider provider, String userId) {
        return Mono.fromCallable(() -> {
            String defaultSystem = provider.getDefaultSystemPrompt();
            String defaultUser = provider.getDefaultUserPrompt();
            // TODO: 获取用户自定义系统提示词
            String userCustomSystem = null;
            boolean hasUserCustom = userCustomSystem != null && !userCustomSystem.trim().isEmpty();
            
            return new SystemPromptInfo(defaultSystem, defaultUser, userCustomSystem, hasUserCustom);
        });
    }

    /**
     * 构建用户提示词信息列表
     */
    private Mono<List<UserPromptInfo>> buildUserPromptInfos(AIFeatureType featureType, String userId) {
        log.info("🔍 开始构建用户提示词信息: featureType={}, userId={}", featureType, userId);
        
        return enhancedUserPromptService.getUserPromptTemplatesByFeatureType(userId, featureType)
                .doOnNext(template -> {
                    log.info("📋 查询到用户模板: id={}, name={}, isDefault={}, isFavorite={}", 
                            template.getId(), template.getName(), template.getIsDefault(), template.getIsFavorite());
                })
                .collectList()
                .map(templates -> {
                    log.info("📊 查询完成: featureType={}, userId={}, 模板总数={}", featureType, userId, templates.size());
                    
                    // 统计默认模板数量
                    long defaultCount = templates.stream()
                            .filter(t -> t.getIsDefault() != null && t.getIsDefault())
                            .count();
                    log.info("🌟 默认模板统计: featureType={}, 默认模板数量={}", featureType, defaultCount);
                    
                    List<UserPromptInfo> result = templates.stream()
                            .map(this::convertToUserPromptInfo)
                            .collect(Collectors.toList());
                    
                    log.info("✅ 用户提示词信息构建完成: featureType={}, 转换后数量={}", featureType, result.size());
                    return result;
                });
    }

    /**
     * 构建公开提示词信息列表
     */
    private Mono<List<PublicPromptInfo>> buildPublicPromptInfos(AIFeatureType featureType) {
        return enhancedUserPromptService.getPublicTemplates(featureType, 0, 100)
                .collectList()
                .map(templates -> templates.stream()
                        .map(this::convertToPublicPromptInfo)
                        .collect(Collectors.toList())
                );
    }

    /**
     * 构建最近使用提示词信息列表
     */
    private Mono<List<RecentPromptInfo>> buildRecentPromptInfos(AIFeatureType featureType, String userId) {
        return enhancedUserPromptService.getRecentlyUsedTemplates(userId, 10)
                .filter(template -> template.getFeatureType() == featureType)
                .collectList()
                .map(templates -> templates.stream()
                        .map(this::convertToRecentPromptInfo)
                        .collect(Collectors.toList())
                );
    }

    /**
     * 获取各功能的提示词数量统计
     */
    private Mono<Map<AIFeatureType, Integer>> getPromptCountsByFeature(String userId) {
        return Flux.fromArray(AIFeatureType.values())
                .flatMap(featureType ->
                    enhancedUserPromptService.getUserPromptTemplatesByFeatureType(userId, featureType)
                            .count()
                            .map(count -> Map.entry(featureType, count.intValue()))
                )
                .collectMap(Map.Entry::getKey, Map.Entry::getValue);
    }

    /**
     * 获取全局最近使用的提示词
     */
    private Mono<List<RecentPromptInfo>> getGlobalRecentlyUsed(String userId) {
        return enhancedUserPromptService.getRecentlyUsedTemplates(userId, 20)
                .collectList()
                .map(templates -> templates.stream()
                        .map(this::convertToRecentPromptInfo)
                        .collect(Collectors.toList())
                );
    }

    /**
     * 获取收藏的提示词
     */
    private Mono<List<UserPromptInfo>> getFavoritePrompts(String userId) {
        return enhancedUserPromptService.getUserFavoriteTemplates(userId)
                .collectList()
                .map(templates -> templates.stream()
                        .map(this::convertToUserPromptInfo)
                        .collect(Collectors.toList())
                );
    }

    /**
     * 获取用户的所有标签
     */
    private Mono<Set<String>> getAllUserTags(String userId) {
        return enhancedUserPromptService.getUserPromptTemplates(userId)
                .flatMap(template -> Flux.fromIterable(template.getTags()))
                .collect(Collectors.toSet());
    }

    /**
     * 获取总使用次数
     */
    private Mono<Long> getTotalUsageCount(String userId) {
        return enhancedUserPromptService.getUserPromptTemplates(userId)
                .map(EnhancedUserPromptTemplate::getUsageCount)
                .reduce(0L, Long::sum);
    }

    // ==================== 转换方法 ====================

    private UserPromptInfo convertToUserPromptInfo(EnhancedUserPromptTemplate template) {
        log.info("🔄 转换用户提示词模板: id={}, name={}, isDefault={}, isFavorite={}", 
                template.getId(), template.getName(), template.getIsDefault(), template.getIsFavorite());
        
        // 为null的DateTime字段提供默认值
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime createdAt = template.getCreatedAt() != null ? template.getCreatedAt() : now;
        LocalDateTime updatedAt = template.getUpdatedAt() != null ? template.getUpdatedAt() : now;
        LocalDateTime lastUsedAt = template.getLastUsedAt(); // 可以为null，前端会处理
        
        UserPromptInfo result = new UserPromptInfo(
                template.getId(),
                template.getName(),
                template.getDescription(),
                template.getFeatureType(),
                template.getSystemPrompt(),
                template.getUserPrompt(),
                template.getTags() != null ? template.getTags() : List.of(),
                template.getCategories() != null ? template.getCategories() : List.of(),
                template.getIsFavorite() != null ? template.getIsFavorite() : false,
                template.getIsDefault() != null ? template.getIsDefault() : false,
                template.getIsPublic() != null ? template.getIsPublic() : false,
                template.getShareCode(),
                template.getIsVerified() != null ? template.getIsVerified() : false,
                template.getUsageCount() != null ? template.getUsageCount() : 0L,
                template.getFavoriteCount() != null ? template.getFavoriteCount() : 0L,
                template.getRatingStatistics() != null ? template.getRatingStatistics().getAverageRating() : 0.0,
                template.getAuthorId(),
                template.getVersion(),
                template.getLanguage(),
                createdAt,
                lastUsedAt,
                updatedAt,
                template.getReviewStatus(), // 🆕 添加审核状态
                template.getHidePrompts() != null ? template.getHidePrompts() : false, // 🆕 添加隐藏提示词
                template.getSettingGenerationConfig() // 🆕 添加设定生成配置
        );
        
        log.info("✅ 转换完成: id={}, name={}, result.isDefault={}", 
                template.getId(), template.getName(), result.isDefault());
        
        return result;
    }

    private PublicPromptInfo convertToPublicPromptInfo(EnhancedUserPromptTemplate template) {
        // 为null的DateTime字段提供默认值
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime createdAt = template.getCreatedAt() != null ? template.getCreatedAt() : now;
        LocalDateTime updatedAt = template.getUpdatedAt() != null ? template.getUpdatedAt() : now;
        LocalDateTime lastUsedAt = template.getLastUsedAt(); // 可以为null，前端会处理
        
        return new PublicPromptInfo(
                template.getId(),
                template.getName(),
                template.getDescription(),
                template.getAuthorId(),
                template.getFeatureType(),
                template.getSystemPrompt(),
                template.getUserPrompt(),
                template.getTags() != null ? template.getTags() : List.of(),
                template.getCategories() != null ? template.getCategories() : List.of(),
                template.getRatingStatistics() != null ? template.getRatingStatistics().getAverageRating() : 0.0,
                template.getUsageCount() != null ? template.getUsageCount() : 0L,
                template.getFavoriteCount() != null ? template.getFavoriteCount() : 0L,
                template.getShareCode(),
                template.getIsVerified() != null ? template.getIsVerified() : false,
                template.getLanguage(),
                template.getVersion(),
                createdAt,
                updatedAt,
                lastUsedAt
        );
    }

    private RecentPromptInfo convertToRecentPromptInfo(EnhancedUserPromptTemplate template) {
        // 为null的DateTime字段提供默认值
        LocalDateTime lastUsedAt = template.getLastUsedAt() != null ? template.getLastUsedAt() : LocalDateTime.now();
        
        return new RecentPromptInfo(
                template.getId(),
                template.getName(),
                template.getDescription(),
                template.getFeatureType(),
                template.getTags() != null ? template.getTags() : List.of(),
                template.getIsDefault() != null ? template.getIsDefault() : false,
                template.getIsFavorite() != null ? template.getIsFavorite() : false,
                template.getRatingStatistics() != null ? template.getRatingStatistics().getAverageRating() : 0.0,
                lastUsedAt,
                template.getUsageCount() != null ? template.getUsageCount() : 0L
        );
    }
} 