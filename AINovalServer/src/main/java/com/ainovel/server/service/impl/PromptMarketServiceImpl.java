package com.ainovel.server.service.impl;

import com.ainovel.server.config.PromptMarketRewardConfig;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.domain.model.ReviewStatusConstants;
import com.ainovel.server.repository.EnhancedUserPromptTemplateRepository;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.PromptMarketService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * 提示词市场服务实现
 */
@Slf4j
@Service
public class PromptMarketServiceImpl implements PromptMarketService {
    
    @Autowired
    private EnhancedUserPromptTemplateRepository templateRepository;
    
    @Autowired
    private ReactiveMongoTemplate mongoTemplate;
    
    @Autowired
    private CreditService creditService;
    
    @Autowired
    private PromptMarketRewardConfig rewardConfig;
    
    @Autowired
    private com.ainovel.server.service.UserService userService;
    
    @Override
    public Flux<EnhancedUserPromptTemplate> getPublicTemplates(
            AIFeatureType featureType, 
            String userId, 
            int page, 
            int size, 
            String sortBy) {
        
        log.info("📋 获取公开提示词模板: featureType={}, userId={}, page={}, size={}, sortBy={}", 
                featureType, userId, page, size, sortBy);
        
        Query query = new Query();
        
        // 过滤条件：必须是公开的
        query.addCriteria(Criteria.where("isPublic").is(true));
        
        // 过滤条件：指定功能类型
        if (featureType != null) {
            query.addCriteria(Criteria.where("featureType").is(featureType));
        }
        
        // 排序
        Sort sort = getSortByType(sortBy);
        query.with(sort);
        
        // 分页
        query.skip((long) page * size).limit(size);
        
        return mongoTemplate.find(query, EnhancedUserPromptTemplate.class)
                .flatMap(this::enrichWithAuthorInfo)  // 填充作者信息
                .map(t -> sanitizeForPublicResponse(t, userId)) // 🔒 隐私保护：隐藏提示词不返回内容
                .doOnNext(template -> log.debug("  - 模板: id={}, name={}, author={}, likes={}, usageCount={}", 
                        template.getId(), template.getName(), template.getAuthorName(), 
                        template.getLikeCount(), template.getUsageCount()))
                .doOnComplete(() -> log.info("✅ 公开模板获取完成"));
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> getAllPublicTemplates(
            String userId, 
            int page, 
            int size, 
            String sortBy) {
        
        log.info("📋 获取所有公开提示词模板: userId={}, page={}, size={}, sortBy={}", 
                userId, page, size, sortBy);
        
        Query query = new Query();
        query.addCriteria(Criteria.where("isPublic").is(true));
        
        Sort sort = getSortByType(sortBy);
        query.with(sort);
        query.skip((long) page * size).limit(size);
        
        return mongoTemplate.find(query, EnhancedUserPromptTemplate.class)
                .flatMap(this::enrichWithAuthorInfo)
                .map(t -> sanitizeForPublicResponse(t, userId));  // 填充作者信息并脱敏
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> searchPublicTemplates(
            AIFeatureType featureType,
            String keyword,
            String userId,
            int page,
            int size) {
        
        log.info("🔍 搜索公开提示词模板: featureType={}, keyword={}, userId={}", 
                featureType, keyword, userId);
        
        Query query = new Query();
        query.addCriteria(Criteria.where("isPublic").is(true));
        
        if (featureType != null) {
            query.addCriteria(Criteria.where("featureType").is(featureType));
        }
        
        if (keyword != null && !keyword.trim().isEmpty()) {
            // 模糊搜索：名称、描述、标签
            Pattern pattern = Pattern.compile(keyword, Pattern.CASE_INSENSITIVE);
            Criteria searchCriteria = new Criteria().orOperator(
                    Criteria.where("name").regex(pattern),
                    Criteria.where("description").regex(pattern),
                    Criteria.where("tags").in(keyword)
            );
            query.addCriteria(searchCriteria);
        }
        
        query.with(Sort.by(Sort.Direction.DESC, "usageCount", "likeCount"));
        query.skip((long) page * size).limit(size);
        
        return mongoTemplate.find(query, EnhancedUserPromptTemplate.class)
                .flatMap(this::enrichWithAuthorInfo)
                .map(t -> sanitizeForPublicResponse(t, userId));  // 填充作者信息并脱敏
    }
    
    @Override
    public Mono<Map<String, Object>> toggleLike(String templateId, String userId) {
        log.info("👍 切换点赞状态: templateId={}, userId={}", templateId, userId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    // 注意：这里的isLiked是针对当前用户的，实际应该通过用户-模板关系表来管理
                    // 为了简化，暂时使用模板上的字段（需要后续改进）
                    boolean wasLiked = Boolean.TRUE.equals(template.getIsLiked());
                    
                    if (wasLiked) {
                        template.decrementLikeCount();
                        template.setIsLiked(false);
                        log.info("  ➖ 取消点赞: templateId={}, newCount={}", templateId, template.getLikeCount());
                    } else {
                        template.incrementLikeCount();
                        template.setIsLiked(true);
                        log.info("  ➕ 添加点赞: templateId={}, newCount={}", templateId, template.getLikeCount());
                    }
                    
                    return templateRepository.save(template);
                })
                .map(template -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("isLiked", template.getIsLiked());
                    result.put("likeCount", template.getLikeCount());
                    return result;
                })
                .doOnSuccess(result -> log.info("✅ 点赞状态切换成功: templateId={}, isLiked={}, likeCount={}", 
                        templateId, result.get("isLiked"), result.get("likeCount")));
    }
    
    @Override
    public Mono<Map<String, Object>> toggleFavorite(String templateId, String userId) {
        log.info("⭐ 切换收藏状态: templateId={}, userId={}", templateId, userId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    boolean wasFavorite = Boolean.TRUE.equals(template.getIsFavorite());
                    
                    if (wasFavorite) {
                        template.decrementFavoriteCount();
                        template.setIsFavorite(false);
                        log.info("  ➖ 取消收藏: templateId={}, newCount={}", templateId, template.getFavoriteCount());
                    } else {
                        template.incrementFavoriteCount();
                        template.setIsFavorite(true);
                        log.info("  ➕ 添加收藏: templateId={}, newCount={}", templateId, template.getFavoriteCount());
                    }
                    
                    return templateRepository.save(template);
                })
                .map(template -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("isFavorite", template.getIsFavorite());
                    result.put("favoriteCount", template.getFavoriteCount());
                    return result;
                })
                .doOnSuccess(result -> log.info("✅ 收藏状态切换成功: templateId={}, isFavorite={}, favoriteCount={}", 
                        templateId, result.get("isFavorite"), result.get("favoriteCount")));
    }
    
    @Override
    public Mono<Void> shareTemplate(String templateId, String userId, Boolean hidePrompts) {
        log.info("🔗 分享模板（提交审核）: templateId={}, userId={}, hidePrompts={}", templateId, userId, hidePrompts);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    // 检查权限：只有作者可以分享
                    if (!userId.equals(template.getUserId()) && !userId.equals(template.getAuthorId())) {
                        return Mono.error(new IllegalArgumentException("只有模板作者可以分享模板"));
                    }
                    
                    // 可选：在提交审核前设置隐藏提示词
                    if (hidePrompts != null) {
                        log.info("  🔒 设置隐藏提示词: templateId={}, hidePrompts={}", templateId, hidePrompts);
                        template.setHidePrompts(hidePrompts);
                    } else {
                        log.warn("  ⚠️ hidePrompts参数为null，将使用模板当前值: templateId={}, currentValue={}", 
                                templateId, template.getHidePrompts());
                    }
                    
                    // 检查是否已经提交审核
                    if (ReviewStatusConstants.PENDING.equals(template.getReviewStatus())) {
                        return Mono.error(new IllegalStateException("模板已提交审核，请等待审核结果"));
                    }
                    if (ReviewStatusConstants.APPROVED.equals(template.getReviewStatus())) {
                        return Mono.error(new IllegalStateException("模板已审核通过，无需重复提交"));
                    }
                    
                    // 提交审核：设置审核状态为 PENDING
                    template.setReviewStatus(ReviewStatusConstants.PENDING);
                    template.setSubmittedAt(LocalDateTime.now());
                    template.setUpdatedAt(LocalDateTime.now());
                    
                    log.info("  ✅ 模板提交审核: templateId={}, reviewStatus={}, hidePrompts={}", 
                            templateId, ReviewStatusConstants.PENDING, template.getHidePrompts());
                    
                    return templateRepository.save(template).then();
                })
                .doOnSuccess(v -> log.info("✅ 模板提交审核成功: templateId={}", templateId));
    }

    /**
     * 隐私保护：对公开返回进行脱敏
     * - 若作者设置 hidePrompts=true，且当前用户不是作者，则清空 systemPrompt/userPrompt
     */
    private EnhancedUserPromptTemplate sanitizeForPublicResponse(EnhancedUserPromptTemplate template, String userId) {
        try {
            boolean hidden = Boolean.TRUE.equals(template.getHidePrompts());
            String owner = template.getAuthorId() != null ? template.getAuthorId() : template.getUserId();
            boolean isOwner = userId != null && userId.equals(owner);
            if (hidden && !isOwner) {
                template.setSystemPrompt("");
                template.setUserPrompt("");
            }
            return template;
        } catch (Exception e) {
            // 兜底不影响主流程
            return template;
        }
    }
    
    @Override
    public Mono<EnhancedUserPromptTemplate> toggleHidePrompts(String templateId, String userId, boolean hide) {
        log.info("🔒 切换提示词隐藏状态: templateId={}, userId={}, hide={}", templateId, userId, hide);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    // 检查权限：只有作者可以设置
                    if (!userId.equals(template.getUserId()) && !userId.equals(template.getAuthorId())) {
                        return Mono.error(new IllegalArgumentException("只有模板作者可以设置隐藏状态"));
                    }
                    
                    template.setHidePrompts(hide);
                    template.setUpdatedAt(LocalDateTime.now());
                    
                    log.info("  ✅ 提示词隐藏状态已设置: templateId={}, hide={}", templateId, hide);
                    
                    return templateRepository.save(template);
                })
                .doOnSuccess(template -> log.info("✅ 提示词隐藏状态切换成功: templateId={}, hidePrompts={}", 
                        templateId, template.getHidePrompts()));
    }
    
    @Override
    public Mono<Void> recordUsageAndReward(String templateId, String userId) {
        log.info("📊 记录模板使用并奖励积分: templateId={}, userId={}", templateId, userId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    // 增加使用次数
                    template.incrementUsageCount();
                    log.info("  ➕ 增加使用次数: templateId={}, newCount={}", templateId, template.getUsageCount());
                    
                    return templateRepository.save(template)
                            .flatMap(savedTemplate -> {
                                // 获取作者ID
                                String authorId = savedTemplate.getAuthorId() != null 
                                        ? savedTemplate.getAuthorId() 
                                        : savedTemplate.getUserId();
                                
                                // 自己使用自己的模板不奖励积分
                                if (authorId == null || authorId.equals(userId)) {
                                    log.info("  ℹ️  自己使用自己的模板，不奖励积分");
                                    return Mono.empty();
                                }
                                
                                // 获取该功能类型的积分奖励
                                long rewardPoints = rewardConfig.getReferencePoints(savedTemplate.getFeatureType());
                                
                                if (rewardPoints <= 0) {
                                    log.info("  ℹ️  该功能类型不奖励积分: featureType={}", savedTemplate.getFeatureType());
                                    return Mono.empty();
                                }
                                
                                // 给作者增加积分
                                String reason = String.format("模板被引用: %s", savedTemplate.getName());
                                return creditService.addCredits(authorId, rewardPoints, reason)
                                        .doOnSuccess(success -> {
                                            if (Boolean.TRUE.equals(success)) {
                                                log.info("  🎉 积分奖励成功: authorId={}, points={}, templateId={}, templateName={}", 
                                                        authorId, rewardPoints, templateId, savedTemplate.getName());
                                            } else {
                                                log.warn("  ⚠️  积分奖励失败: authorId={}, templateId={}", 
                                                        authorId, templateId);
                                            }
                                        })
                                        .then();
                            });
                })
                .onErrorResume(error -> {
                    log.error("❌ 记录使用和奖励积分失败: templateId={}, userId={}, error={}", 
                            templateId, userId, error.getMessage(), error);
                    return Mono.empty(); // 不影响主流程
                })
                .doFinally(signalType -> log.info("✅ 使用记录和积分奖励处理完成: templateId={}", templateId));
    }
    
    @Override
    public Mono<Map<String, Object>> getTemplateRewardInfo(String templateId) {
        return templateRepository.findById(templateId)
                .map(template -> {
                    long points = rewardConfig.getReferencePoints(template.getFeatureType());
                    String description = rewardConfig.getReferencePointsDescription(template.getFeatureType());
                    
                    Map<String, Object> result = new HashMap<>();
                    result.put("points", points);
                    result.put("description", description);
                    result.put("featureType", template.getFeatureType().name());
                    
                    return result;
                })
                .defaultIfEmpty(new HashMap<>());
    }
    
    @Override
    public Mono<Map<AIFeatureType, Long>> getAllRewardPoints() {
        return Mono.fromCallable(() -> rewardConfig.getAllReferencePoints());
    }
    
    @Override
    public Mono<MarketStatistics> getMarketStatistics() {
        log.info("📊 获取市场统计信息");
        
        Query publicQuery = new Query(Criteria.where("isPublic").is(true));
        
        return mongoTemplate.count(publicQuery, EnhancedUserPromptTemplate.class)
                .flatMap(totalTemplates -> {
                    MarketStatistics stats = new MarketStatistics();
                    stats.setTotalTemplates(totalTemplates);
                    
                    // 获取更多统计信息
                    return mongoTemplate.find(publicQuery, EnhancedUserPromptTemplate.class)
                            .collectList()
                            .map(templates -> {
                                // 统计作者数量
                                long totalAuthors = templates.stream()
                                        .map(t -> t.getAuthorId() != null ? t.getAuthorId() : t.getUserId())
                                        .distinct()
                                        .count();
                                stats.setTotalAuthors(totalAuthors);
                                
                                // 统计总使用次数
                                long totalUsages = templates.stream()
                                        .mapToLong(t -> t.getUsageCount() != null ? t.getUsageCount() : 0L)
                                        .sum();
                                stats.setTotalUsages(totalUsages);
                                
                                // 统计总点赞数
                                long totalLikes = templates.stream()
                                        .mapToLong(t -> t.getLikeCount() != null ? t.getLikeCount() : 0L)
                                        .sum();
                                stats.setTotalLikes(totalLikes);
                                
                                // 统计总收藏数
                                long totalFavorites = templates.stream()
                                        .mapToLong(t -> t.getFavoriteCount() != null ? t.getFavoriteCount() : 0L)
                                        .sum();
                                stats.setTotalFavorites(totalFavorites);
                                
                                // 按功能类型统计
                                Map<AIFeatureType, Long> countByFeature = new HashMap<>();
                                for (AIFeatureType type : AIFeatureType.values()) {
                                    long count = templates.stream()
                                            .filter(t -> type.equals(t.getFeatureType()))
                                            .count();
                                    if (count > 0) {
                                        countByFeature.put(type, count);
                                    }
                                }
                                stats.setTemplateCountByFeature(countByFeature);
                                
                                return stats;
                            });
                })
                .doOnSuccess(stats -> log.info("✅ 市场统计信息获取成功: totalTemplates={}, totalAuthors={}", 
                        stats.getTotalTemplates(), stats.getTotalAuthors()));
    }
    
    // ==================== 私有辅助方法 ====================
    
    /**
     * 填充作者信息
     */
    private Mono<EnhancedUserPromptTemplate> enrichWithAuthorInfo(EnhancedUserPromptTemplate template) {
        String authorId = template.getAuthorId() != null ? template.getAuthorId() : template.getUserId();
        
        if (authorId == null) {
            // 如果没有作者ID，直接返回原模板
            return Mono.just(template);
        }
        
        // 从 UserService 获取作者信息
        return userService.findUserById(authorId)
                .map(user -> {
                    // 填充作者姓名
                    template.setAuthorName(user.getUsername() != null ? user.getUsername() : "未知用户");
                    return template;
                })
                .switchIfEmpty(Mono.fromCallable(() -> {
                    // 如果找不到用户，设置默认值
                    template.setAuthorName("未知用户");
                    return template;
                }))
                .onErrorResume(error -> {
                    // 如果获取用户信息失败，记录日志但不中断流程
                    log.warn("⚠️ 获取作者信息失败: authorId={}, error={}", authorId, error.getMessage());
                    template.setAuthorName("未知用户");
                    return Mono.just(template);
                });
    }
    
    /**
     * 根据排序类型获取Sort对象
     */
    private Sort getSortByType(String sortBy) {
        if (sortBy == null) {
            sortBy = "latest";
        }
        
        return switch (sortBy.toLowerCase()) {
            case "popular" -> Sort.by(Sort.Direction.DESC, "likeCount", "favoriteCount", "usageCount");
            case "mostused" -> Sort.by(Sort.Direction.DESC, "usageCount", "likeCount");
            case "rating" -> Sort.by(Sort.Direction.DESC, "rating", "likeCount");
            default -> Sort.by(Sort.Direction.DESC, "createdAt"); // latest
        };
    }
}


