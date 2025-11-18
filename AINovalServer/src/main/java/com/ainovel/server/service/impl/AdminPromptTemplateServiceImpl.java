package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.domain.model.ReviewStatusConstants;
import com.ainovel.server.repository.EnhancedUserPromptTemplateRepository;
import com.ainovel.server.service.AdminPromptTemplateService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 管理员提示词模板管理服务实现
 * 基于 EnhancedUserPromptTemplate 的统一管理
 */
@Slf4j
@Service
public class AdminPromptTemplateServiceImpl implements AdminPromptTemplateService {
    
    @Autowired
    private EnhancedUserPromptTemplateRepository templateRepository;
    
    // ==================== 公共模板管理 ====================
    
    @Override
    public Flux<EnhancedUserPromptTemplate> findAllPublicTemplates() {
        log.debug("获取所有公共模板");
        return templateRepository.findByIsPublicTrue()
                .doOnNext(template -> log.debug("找到公共模板: {} (ID: {})", template.getName(), template.getId()));
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> findPublicTemplatesByFeatureType(AIFeatureType featureType) {
        log.debug("获取功能类型 {} 的公共模板", featureType);
        return templateRepository.findPublicTemplatesByFeatureType(featureType)
                .doOnNext(template -> log.debug("找到功能类型 {} 的公共模板: {}", featureType, template.getName()));
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> findPendingTemplates() {
        log.debug("获取所有待审核的模板");
        // 🔧 修复：使用统一的 reviewStatus 字段，而不是旧的 isVerified 逻辑
        return templateRepository.findAll()
                .filter(template -> ReviewStatusConstants.PENDING.equals(template.getReviewStatus()))
                .doOnNext(template -> log.debug("找到待审核模板: {} (作者: {}, 类型: {}, 状态: {})", 
                        template.getName(), template.getAuthorId(), template.getFeatureType(), template.getReviewStatus()));
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> findVerifiedTemplates() {
        log.debug("获取已验证的官方模板");
        return templateRepository.findByIsPublicTrue()
                .filter(template -> template.getIsVerified())
                .doOnNext(template -> log.debug("找到已验证模板: {}", template.getName()));
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> findAllUserTemplates(int page, int size, String search) {
        log.info("获取所有用户模板: page={}, size={}, search={}", page, size, search);
        
        Flux<EnhancedUserPromptTemplate> templateFlux;
        
        if (search != null && !search.trim().isEmpty()) {
            // 带搜索条件
            templateFlux = templateRepository.findByNameContainingIgnoreCaseOrDescriptionContainingIgnoreCase(search, search);
        } else {
            // 无搜索条件，获取所有
            templateFlux = templateRepository.findAll();
        }
        
        return templateFlux
                .skip((long) page * size)
                .take(size)
                .sort((t1, t2) -> t2.getUpdatedAt().compareTo(t1.getUpdatedAt()))
                .doOnNext(template -> log.debug("找到用户模板: {} (用户: {}, 公共: {})", 
                        template.getName(), template.getUserId(), template.getIsPublic()));
    }
    
    // ==================== 模板创建与更新 ====================
    
    @Override
    public Mono<EnhancedUserPromptTemplate> createOfficialTemplate(EnhancedUserPromptTemplate template, String adminId) {
        log.info("管理员 {} 创建官方模板: {}", adminId, template.getName());
        // 兜底：当adminId为空时，使用system作为所有者，避免下游空指针
        final String ownerId = (adminId == null || adminId.isBlank()) ? "system" : adminId;

        template.setId(null); // 确保创建新模板
        // 若前端传入了userId/authorId，则尊重前端；否则使用ownerId兜底，避免为null
        if (template.getUserId() == null || template.getUserId().isBlank()) {
            template.setUserId(ownerId);
        }
        if (template.getAuthorId() == null || template.getAuthorId().isBlank()) {
            template.setAuthorId(template.getUserId());
        }
        template.setIsPublic(true);
        template.setIsVerified(true);
        template.setCreatedAt(LocalDateTime.now());
        template.setUpdatedAt(LocalDateTime.now());
        template.setUsageCount(0L);
        template.setFavoriteCount(0L);
        template.setVersion(1);
        // 防御性处理：关键字段为空时提供默认值
        if (template.getName() == null || template.getName().isBlank()) {
            template.setName("OFFICIAL_TEMPLATE");
        }
        if (template.getFeatureType() == null) {
            template.setFeatureType(AIFeatureType.TEXT_EXPANSION);
        }
        if (template.getSystemPrompt() == null) {
            template.setSystemPrompt("");
        }
        if (template.getUserPrompt() == null) {
            template.setUserPrompt("");
        }
        
        return templateRepository.save(template)
                .doOnSuccess(savedTemplate -> log.info("官方模板创建成功: {} (ID: {})", 
                    savedTemplate.getName(), savedTemplate.getId()))
                .doOnError(error -> log.error("创建官方模板失败: {}", template.getName(), error));
    }
    
    @Override
    public Mono<EnhancedUserPromptTemplate> updatePublicTemplate(String templateId, EnhancedUserPromptTemplate template, String adminId) {
        log.info("管理员 {} 更新公共模板: {}", adminId, templateId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .filter(existing -> existing.getIsPublic())
                .switchIfEmpty(Mono.error(new RuntimeException("只能更新公共模板")))
                .flatMap(existing -> {
                    // 保留原有的关键信息
                    template.setId(existing.getId());
                    // 兜底：确保userId/authorId不为null
                    template.setUserId(existing.getUserId() != null && !existing.getUserId().isBlank()
                            ? existing.getUserId()
                            : ((adminId == null || adminId.isBlank()) ? "system" : adminId));
                    template.setAuthorId(existing.getAuthorId() != null && !existing.getAuthorId().isBlank()
                            ? existing.getAuthorId()
                            : template.getUserId());
                    template.setCreatedAt(existing.getCreatedAt());
                    template.setUsageCount(existing.getUsageCount());
                    template.setFavoriteCount(existing.getFavoriteCount());
                    template.setRatingStatistics(existing.getRatingStatistics());
                    template.setVersion(existing.getVersion() + 1);
                    
                    // 更新时间和状态
                    template.setUpdatedAt(LocalDateTime.now());
                    template.setIsPublic(true); // 确保保持公共状态

                    // 兼容前端仅部分字段更新：避免关键字段被置空
                    // 若未传入则沿用原值
                    if (template.getFeatureType() == null) {
                        template.setFeatureType(existing.getFeatureType());
                    }
                    if (template.getSystemPrompt() == null) {
                        template.setSystemPrompt(existing.getSystemPrompt());
                    }
                    if (template.getUserPrompt() == null) {
                        template.setUserPrompt(existing.getUserPrompt());
                    }
                    if (template.getTags() == null || template.getTags().isEmpty()) {
                        template.setTags(existing.getTags());
                    }
                    if (template.getCategories() == null || template.getCategories().isEmpty()) {
                        template.setCategories(existing.getCategories());
                    }

                    // 设定生成模板的策略配置不可丢失
                    // 如果是设定生成模板且未提交配置，则沿用原配置
                    if ((template.getFeatureType() != null && template.getFeatureType() == AIFeatureType.SETTING_TREE_GENERATION)
                            || (existing.getFeatureType() == AIFeatureType.SETTING_TREE_GENERATION)) {
                        if (template.getSettingGenerationConfig() == null && existing.getSettingGenerationConfig() != null) {
                            template.setSettingGenerationConfig(existing.getSettingGenerationConfig());
                        }
                    }
                    
                    return templateRepository.save(template);
                })
                .doOnSuccess(savedTemplate -> log.info("公共模板更新成功: {}", savedTemplate.getName()))
                .doOnError(error -> log.error("更新公共模板失败: {}", templateId, error));
    }
    
    @Override
    public Mono<Void> deletePublicTemplate(String templateId, String adminId) {
        log.info("管理员 {} 删除公共模板: {}", adminId, templateId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .filter(template -> template.getIsPublic())
                .switchIfEmpty(Mono.error(new RuntimeException("只能删除公共模板")))
                .flatMap(template -> {
                    log.info("删除公共模板: {} (作者: {})", template.getName(), template.getAuthorId());
                    return templateRepository.delete(template);
                })
                .doOnSuccess(v -> log.info("公共模板删除成功: {}", templateId))
                .doOnError(error -> log.error("删除公共模板失败: {}", templateId, error));
    }
    
    // ==================== 审核与发布管理 ====================
    
    @Override
    public Mono<EnhancedUserPromptTemplate> reviewUserTemplate(String templateId, boolean approved, String adminId, String reviewComment) {
        log.info("管理员 {} 审核模板 {}: {}", adminId, templateId, approved ? "通过" : "拒绝");
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    if (approved) {
                        template.setIsPublic(true);
                        template.setIsVerified(true);
                        template.setSharedAt(LocalDateTime.now());
                        template.setReviewStatus(ReviewStatusConstants.APPROVED);
                        log.info("模板审核通过，设置为公开验证模板: {}", template.getName());
                    } else {
                        template.setIsPublic(false);
                        template.setIsVerified(false);
                        template.setReviewStatus(ReviewStatusConstants.REJECTED);
                        log.info("模板审核拒绝，设置为私有模板: {}", template.getName());
                    }
                    
                    template.setReviewerId(adminId);
                    template.setReviewComment(reviewComment);
                    template.setReviewedAt(LocalDateTime.now());
                    template.setUpdatedAt(LocalDateTime.now());
                    
                    return templateRepository.save(template);
                })
                .doOnSuccess(template -> log.info("模板审核完成: {} -> {}", 
                    templateId, approved ? "已通过" : "已拒绝"))
                .doOnError(error -> log.error("审核模板失败: {}", templateId, error));
    }
    
    @Override
    public Mono<EnhancedUserPromptTemplate> publishTemplate(String templateId, String adminId) {
        log.info("管理员 {} 发布模板: {}", adminId, templateId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    template.setIsPublic(true);
                    template.setSharedAt(LocalDateTime.now());
                    template.setUpdatedAt(LocalDateTime.now());
                    return templateRepository.save(template);
                })
                .doOnSuccess(template -> log.info("模板发布成功: {}", template.getName()))
                .doOnError(error -> log.error("发布模板失败: {}", templateId, error));
    }
    
    @Override
    public Mono<EnhancedUserPromptTemplate> unpublishTemplate(String templateId, String adminId) {
        log.info("管理员 {} 取消发布模板: {}", adminId, templateId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    template.setIsPublic(false);
                    template.setUpdatedAt(LocalDateTime.now());
                    return templateRepository.save(template);
                })
                .doOnSuccess(template -> log.info("模板取消发布成功: {}", template.getName()))
                .doOnError(error -> log.error("取消发布模板失败: {}", templateId, error));
    }
    
    @Override
    public Mono<EnhancedUserPromptTemplate> setVerified(String templateId, boolean verified, String adminId) {
        log.info("管理员 {} 设置模板 {} 验证状态: {}", adminId, templateId, verified);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    template.setIsVerified(verified);
                    template.setUpdatedAt(LocalDateTime.now());
                    return templateRepository.save(template);
                })
                .doOnSuccess(template -> log.info("模板验证状态更新成功: {} -> {}", 
                    template.getName(), verified))
                .doOnError(error -> log.error("设置模板验证状态失败: {}", templateId, error));
    }
    
    // ==================== 批量操作 ====================
    
    @Override
    public Mono<Map<String, Object>> batchReviewTemplates(List<String> templateIds, boolean approved, String adminId) {
        log.info("管理员 {} 批量审核 {} 个模板: {}", adminId, templateIds.size(), approved ? "通过" : "拒绝");
        
        return Flux.fromIterable(templateIds)
                .flatMap(templateId -> reviewUserTemplate(templateId, approved, adminId, "批量操作")
                        .onErrorReturn(null)) // 忽略单个失败
                .filter(Objects::nonNull)
                .collectList()
                .map(results -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("totalRequested", templateIds.size());
                    result.put("successCount", results.size());
                    result.put("failureCount", templateIds.size() - results.size());
                    result.put("operation", approved ? "批量审核通过" : "批量审核拒绝");
                    result.put("adminId", adminId);
                    result.put("timestamp", LocalDateTime.now());
                    return result;
                })
                .doOnSuccess(result -> log.info("批量审核完成: {}", result));
    }
    
    @Override
    public Mono<Map<String, Object>> batchSetVerified(List<String> templateIds, boolean verified, String adminId) {
        log.info("管理员 {} 批量设置 {} 个模板验证状态: {}", adminId, templateIds.size(), verified);
        
        return Flux.fromIterable(templateIds)
                .flatMap(templateId -> setVerified(templateId, verified, adminId)
                        .onErrorReturn(null))
                .filter(Objects::nonNull)
                .collectList()
                .map(results -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("totalRequested", templateIds.size());
                    result.put("successCount", results.size());
                    result.put("failureCount", templateIds.size() - results.size());
                    result.put("operation", verified ? "批量设置验证" : "批量取消验证");
                    result.put("adminId", adminId);
                    result.put("timestamp", LocalDateTime.now());
                    return result;
                })
                .doOnSuccess(result -> log.info("批量设置验证状态完成: {}", result));
    }
    
    @Override
    public Mono<Map<String, Object>> batchPublishTemplates(List<String> templateIds, boolean publish, String adminId) {
        log.info("管理员 {} 批量{}发布 {} 个模板", adminId, publish ? "" : "取消", templateIds.size());
        
        return Flux.fromIterable(templateIds)
                .flatMap(templateId -> publish 
                        ? publishTemplate(templateId, adminId)
                        : unpublishTemplate(templateId, adminId))
                .onErrorReturn(null)
                .filter(Objects::nonNull)
                .collectList()
                .map(results -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("totalRequested", templateIds.size());
                    result.put("successCount", results.size());
                    result.put("failureCount", templateIds.size() - results.size());
                    result.put("operation", publish ? "批量发布" : "批量取消发布");
                    result.put("adminId", adminId);
                    result.put("timestamp", LocalDateTime.now());
                    return result;
                })
                .doOnSuccess(result -> log.info("批量发布操作完成: {}", result));
    }
    
    // ==================== 统计与分析 ====================
    
    @Override
    public Mono<Map<String, Object>> getTemplateUsageStatistics(String templateId) {
        log.debug("获取模板 {} 的使用统计", templateId);
        
        return templateRepository.findById(templateId)
                .switchIfEmpty(Mono.error(new RuntimeException("模板不存在: " + templateId)))
                .map(template -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("templateId", template.getId());
                    stats.put("templateName", template.getName());
                    stats.put("featureType", template.getFeatureType());
                    stats.put("isPublic", template.getIsPublic());
                    stats.put("isVerified", template.getIsVerified());
                    stats.put("authorId", template.getAuthorId());
                    stats.put("usageCount", template.getUsageCount());
                    stats.put("favoriteCount", template.getFavoriteCount());
                    stats.put("rating", template.getRating());
                    stats.put("ratingStatistics", template.getRatingStatistics());
                    stats.put("createdAt", template.getCreatedAt());
                    stats.put("updatedAt", template.getUpdatedAt());
                    stats.put("lastUsedAt", template.getLastUsedAt());
                    return stats;
                })
                .doOnSuccess(stats -> log.debug("模板统计信息: {}", stats.get("templateName")));
    }
    
    @Override
    public Mono<Map<String, Object>> getPublicTemplatesStatistics() {
        log.debug("获取公共模板统计信息");
        
        return templateRepository.findByIsPublicTrue()
                .collectList()
                .map(templates -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("totalPublicTemplates", templates.size());
                    
                    // 按功能类型分组统计
                    Map<String, Long> byFeatureType = templates.stream()
                            .collect(Collectors.groupingBy(
                                template -> template.getFeatureType() != null ? template.getFeatureType().name() : "UNKNOWN",
                                Collectors.counting()));
                    stats.put("byFeatureType", byFeatureType);
                    
                    // 验证模板统计
                    long verifiedCount = templates.stream()
                            .mapToLong(template -> template.getIsVerified() ? 1 : 0)
                            .sum();
                    stats.put("verifiedCount", verifiedCount);
                    stats.put("unverifiedCount", templates.size() - verifiedCount);
                    
                    // 使用统计
                    long totalUsage = templates.stream()
                            .mapToLong(template -> template.getUsageCount() != null ? template.getUsageCount() : 0)
                            .sum();
                    stats.put("totalUsage", totalUsage);
                    
                    // 收藏统计
                    long totalFavorites = templates.stream()
                            .mapToLong(template -> template.getFavoriteCount() != null ? template.getFavoriteCount() : 0)
                            .sum();
                    stats.put("totalFavorites", totalFavorites);
                    
                    // 平均评分
                    OptionalDouble avgRating = templates.stream()
                            .filter(template -> template.getRating() != null && template.getRating() > 0)
                            .mapToDouble(EnhancedUserPromptTemplate::getRating)
                            .average();
                    stats.put("averageRating", avgRating.isPresent() ? avgRating.getAsDouble() : 0.0);
                    
                    return stats;
                })
                .doOnSuccess(stats -> log.debug("公共模板统计完成: {} 个模板", stats.get("totalPublicTemplates")));
    }
    
    @Override
    public Mono<Map<String, Object>> getUserTemplatesStatistics(String userId) {
        log.debug("获取用户 {} 的模板统计信息", userId);
        
        return templateRepository.findByUserId(userId)
                .collectList()
                .map(templates -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("userId", userId);
                    stats.put("totalTemplates", templates.size());
                    
                    // 公共/私有统计
                    long publicCount = templates.stream().mapToLong(t -> t.getIsPublic() ? 1 : 0).sum();
                    stats.put("publicTemplates", publicCount);
                    stats.put("privateTemplates", templates.size() - publicCount);
                    
                    // 验证统计
                    long verifiedCount = templates.stream().mapToLong(t -> t.getIsVerified() ? 1 : 0).sum();
                    stats.put("verifiedTemplates", verifiedCount);
                    
                    // 功能类型分布
                    Map<String, Long> byFeatureType = templates.stream()
                            .collect(Collectors.groupingBy(
                                t -> t.getFeatureType() != null ? t.getFeatureType().name() : "UNKNOWN",
                                Collectors.counting()));
                    stats.put("byFeatureType", byFeatureType);
                    
                    return stats;
                });
    }
    
    @Override
    public Mono<Map<String, Object>> getSystemTemplatesStatistics() {
        log.debug("获取系统模板统计信息");
        
        return templateRepository.findAll()
                .collectList()
                .map(templates -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("totalTemplates", templates.size());
                    
                    // 按公共性分类
                    long publicCount = templates.stream().mapToLong(t -> t.getIsPublic() ? 1 : 0).sum();
                    stats.put("publicTemplates", publicCount);
                    stats.put("privateTemplates", templates.size() - publicCount);
                    
                    // 按验证状态分类
                    long verifiedCount = templates.stream().mapToLong(t -> t.getIsVerified() ? 1 : 0).sum();
                    stats.put("verifiedTemplates", verifiedCount);
                    
                    // 用户分布（前10名）
                    Map<String, Long> topUsers = templates.stream()
                            .filter(t -> t.getUserId() != null)
                            .collect(Collectors.groupingBy(EnhancedUserPromptTemplate::getUserId, Collectors.counting()))
                            .entrySet().stream()
                            .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                            .limit(10)
                            .collect(Collectors.toMap(
                                Map.Entry::getKey,
                                Map.Entry::getValue,
                                (e1, e2) -> e1,
                                LinkedHashMap::new));
                    stats.put("topUsers", topUsers);
                    
                    return stats;
                });
    }
    
    // ==================== 导入导出 ====================
    
    @Override
    public Mono<List<EnhancedUserPromptTemplate>> exportPublicTemplates(List<String> templateIds, String adminId) {
        log.info("管理员 {} 导出模板，数量: {}", adminId, templateIds.size());
        
        Flux<EnhancedUserPromptTemplate> templatesFlux = templateIds.isEmpty() 
                ? templateRepository.findByIsPublicTrue()
                : templateRepository.findAllById(templateIds).filter(EnhancedUserPromptTemplate::getIsPublic);
                
        return templatesFlux.collectList()
                .doOnSuccess(templates -> log.info("成功导出 {} 个公共模板", templates.size()));
    }
    
    @Override
    public Mono<List<EnhancedUserPromptTemplate>> importPublicTemplates(List<EnhancedUserPromptTemplate> templates, String adminId) {
        log.info("管理员 {} 导入 {} 个公共模板", adminId, templates.size());
        
        return Flux.fromIterable(templates)
                .map(template -> {
                    // 重置关键字段
                    template.setId(null);
                    template.setUserId(adminId);
                    template.setAuthorId(adminId);
                    template.setIsPublic(true);
                    template.setIsVerified(true);
                    template.setCreatedAt(LocalDateTime.now());
                    template.setUpdatedAt(LocalDateTime.now());
                    template.setUsageCount(0L);
                    template.setFavoriteCount(0L);
                    template.setVersion(1);
                    return template;
                })
                .flatMap(template -> templateRepository.save(template))
                .collectList()
                .doOnSuccess(savedTemplates -> log.info("成功导入 {} 个公共模板", savedTemplates.size()));
    }
    
    // ==================== 搜索与查询 ====================
    
    @Override
    public Flux<EnhancedUserPromptTemplate> searchPublicTemplates(String keyword, AIFeatureType featureType, Boolean verified, int page, int size) {
        log.debug("搜索公共模板: 关键词={}, 功能类型={}, 验证状态={}, 页码={}, 大小={}", keyword, featureType, verified, page, size);
        
        return templateRepository.findByIsPublicTrue()
                .filter(template -> featureType == null || featureType.equals(template.getFeatureType()))
                .filter(template -> verified == null || verified.equals(template.getIsVerified()))
                .filter(template -> keyword == null || keyword.trim().isEmpty() ||
                        (template.getName() != null && template.getName().toLowerCase().contains(keyword.toLowerCase())) ||
                        (template.getDescription() != null && template.getDescription().toLowerCase().contains(keyword.toLowerCase())))
                .skip((long) page * size)
                .take(size);
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> getPopularPublicTemplates(AIFeatureType featureType, int limit) {
        log.debug("获取热门公共模板: 功能类型={}, 限制={}", featureType, limit);
        
        return templateRepository.findByIsPublicTrue()
                .filter(template -> featureType == null || featureType.equals(template.getFeatureType()))
                .sort((t1, t2) -> {
                    // 按使用次数和收藏数排序
                    long score1 = (t1.getUsageCount() != null ? t1.getUsageCount() : 0) + 
                                 (t1.getFavoriteCount() != null ? t1.getFavoriteCount() * 2 : 0);
                    long score2 = (t2.getUsageCount() != null ? t2.getUsageCount() : 0) + 
                                 (t2.getFavoriteCount() != null ? t2.getFavoriteCount() * 2 : 0);
                    return Long.compare(score2, score1); // 降序
                })
                .take(limit);
    }
    
    @Override
    public Flux<EnhancedUserPromptTemplate> getLatestPublicTemplates(AIFeatureType featureType, int limit) {
        log.debug("获取最新公共模板: 功能类型={}, 限制={}", featureType, limit);
        
        return templateRepository.findByIsPublicTrue()
                .filter(template -> featureType == null || featureType.equals(template.getFeatureType()))
                .filter(template -> template.getCreatedAt() != null)
                .sort((t1, t2) -> t2.getCreatedAt().compareTo(t1.getCreatedAt())) // 按创建时间降序
                .take(limit);
    }
}