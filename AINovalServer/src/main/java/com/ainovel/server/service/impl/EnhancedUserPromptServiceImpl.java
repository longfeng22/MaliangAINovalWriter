package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.repository.EnhancedUserPromptTemplateRepository;
import com.ainovel.server.service.EnhancedUserPromptService;
import com.ainovel.server.service.prompt.AIFeaturePromptProvider;
import com.ainovel.server.service.prompt.PromptProviderFactory;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 增强用户提示词服务实现类
 */
@Slf4j
@Service
public class EnhancedUserPromptServiceImpl implements EnhancedUserPromptService {

    @Autowired
    private EnhancedUserPromptTemplateRepository repository;
    
    @Autowired
    private PromptProviderFactory promptProviderFactory;

    @Override
    @CacheEvict(value = "promptPackages", allEntries = true)
    public Mono<EnhancedUserPromptTemplate> createPromptTemplate(String userId, String name, String description,
            AIFeatureType featureType, String systemPrompt, String userPrompt, 
            List<String> tags, List<String> categories) {
        
        log.info("创建用户提示词模板: userId={}, name={}, featureType={}", userId, name, featureType);

        LocalDateTime now = LocalDateTime.now();
        
        // 检查是否是用户该功能类型的第一个模板，如果是则设为默认
        return repository.countByUserIdAndFeatureType(userId, featureType)
                .flatMap(count -> {
                    boolean isFirstTemplate = count == 0;
                    
                    EnhancedUserPromptTemplate template = EnhancedUserPromptTemplate.builder()
                            .id(UUID.randomUUID().toString())
                            .userId(userId)
                            .name(name)
                            .description(description)
                            .featureType(featureType)
                            .systemPrompt(systemPrompt)
                            .userPrompt(userPrompt)
                            .tags(tags != null ? tags : List.of())
                            .categories(categories != null ? categories : List.of())
                            .isPublic(false)
                            .isFavorite(false)
                            .isDefault(isFirstTemplate) // 第一个模板设为默认
                            .isVerified(false)
                            .usageCount(0L)
                            .favoriteCount(0L)
                            .rating(0.0)
                            .authorId(userId)
                            .version(1)
                            .language("zh")
                            .createdAt(now)
                            .updatedAt(now)
                            .build();

                    return repository.save(template);
                })
                .doOnSuccess(saved -> log.info("成功创建用户提示词模板: id={}, name={}, isDefault={}", saved.getId(), saved.getName(), saved.getIsDefault()))
                .doOnError(error -> log.error("创建用户提示词模板失败: userId={}, error={}", userId, error.getMessage(), error));
    }

    @Override
    @CacheEvict(value = "promptPackages", allEntries = true)
    public Mono<EnhancedUserPromptTemplate> updatePromptTemplate(String userId, String templateId, String name,
            String description, String systemPrompt, String userPrompt, 
            List<String> tags, List<String> categories) {
        
        log.info("更新用户提示词模板: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    // 验证权限
                    if (!userId.equals(template.getUserId())) {
                        return Mono.error(new IllegalArgumentException("无权修改此模板"));
                    }

                    // 更新字段
                    if (name != null && !name.trim().isEmpty()) {
                        template.setName(name.trim());
                    }
                    if (description != null) {
                        template.setDescription(description.trim());
                    }
                    if (systemPrompt != null) {
                        template.setSystemPrompt(systemPrompt);
                    }
                    if (userPrompt != null) {
                        template.setUserPrompt(userPrompt);
                    }
                    if (tags != null) {
                        template.setTags(tags);
                    }
                    if (categories != null) {
                        template.setCategories(categories);
                    }

                    template.setUpdatedAt(LocalDateTime.now());
                    template.setVersion(template.getVersion() + 1);

                    return repository.save(template);
                })
                .doOnSuccess(updated -> log.info("成功更新用户提示词模板: id={}", updated.getId()))
                .doOnError(error -> log.error("更新用户提示词模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    @CacheEvict(value = "promptPackages", allEntries = true)
    public Mono<Void> deletePromptTemplate(String userId, String templateId) {
        log.info("删除用户提示词模板: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    // 验证权限
                    if (!userId.equals(template.getUserId())) {
                        return Mono.error(new IllegalArgumentException("无权删除此模板"));
                    }
                    return repository.delete(template);
                })
                .doOnSuccess(v -> log.info("成功删除用户提示词模板: templateId={}", templateId))
                .doOnError(error -> log.error("删除用户提示词模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Mono<EnhancedUserPromptTemplate> getPromptTemplateById(String userId, String templateId) {
        return repository.findById(templateId)
                .flatMap(template -> {
                    // 检查权限：用户自己的模板或公开模板
                    if (userId.equals(template.getUserId()) || template.getIsPublic()) {
                        return Mono.just(template);
                    }
                    return Mono.error(new IllegalArgumentException("无权访问此模板"));
                })
                .doOnError(error -> log.error("获取用户提示词模板失败: templateId={}, error={}", templateId, error.getMessage()));
    }

    @Override
    public Flux<EnhancedUserPromptTemplate> getUserPromptTemplates(String userId) {
        log.debug("获取用户所有提示词模板: userId={}", userId);
        return repository.findByUserId(userId)
                .sort((t1, t2) -> t2.getUpdatedAt().compareTo(t1.getUpdatedAt()));
    }

    @Override
    public Flux<EnhancedUserPromptTemplate> getUserPromptTemplatesByFeatureType(String userId, AIFeatureType featureType) {
        log.info("🔍 查询用户指定功能类型的提示词模板: userId={}, featureType={}", userId, featureType);
        
        return repository.findByUserIdAndFeatureType(userId, featureType)
                .doOnNext(template -> {
                    log.info("📋 找到用户模板: id={}, name={}, isDefault={}, isFavorite={}, usageCount={}", 
                            template.getId(), template.getName(), template.getIsDefault(), 
                            template.getIsFavorite(), template.getUsageCount());
                })
                .doOnComplete(() -> {
                    log.info("✅ 用户模板查询完成: userId={}, featureType={}", userId, featureType);
                })
                .doOnError(error -> {
                    log.error("❌ 用户模板查询失败: userId={}, featureType={}, error={}", 
                            userId, featureType, error.getMessage(), error);
                });
    }

    @Override
    public Flux<EnhancedUserPromptTemplate> getUserFavoriteTemplates(String userId) {
        log.debug("获取用户收藏的提示词模板: userId={}", userId);
        return repository.findByUserIdAndIsFavoriteTrue(userId)
                .sort((t1, t2) -> t2.getUpdatedAt().compareTo(t1.getUpdatedAt()));
    }

    @Override
    public Flux<EnhancedUserPromptTemplate> getRecentlyUsedTemplates(String userId, int limit) {
        log.debug("获取用户最近使用的提示词模板: userId={}, limit={}", userId, limit);
        return repository.findByUserIdOrderByLastUsedAtDesc(userId)
                .take(limit);
    }

    @Override
    public Mono<EnhancedUserPromptTemplate> publishTemplate(String userId, String templateId, String shareCode) {
        log.info("发布用户提示词模板: userId={}, templateId={}, shareCode={}", userId, templateId, shareCode);

        return repository.findById(templateId)
                .flatMap(template -> {
                    // 验证权限
                    if (!userId.equals(template.getUserId())) {
                        return Mono.error(new IllegalArgumentException("无权发布此模板"));
                    }

                    template.setIsPublic(true);
                    template.setShareCode(shareCode);
                    template.setSharedAt(LocalDateTime.now());
                    template.setUpdatedAt(LocalDateTime.now());

                    return repository.save(template);
                })
                .doOnSuccess(published -> log.info("成功发布用户提示词模板: id={}, shareCode={}", published.getId(), published.getShareCode()))
                .doOnError(error -> log.error("发布用户提示词模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Mono<EnhancedUserPromptTemplate> getTemplateByShareCode(String shareCode) {
        log.debug("通过分享码获取模板: shareCode={}", shareCode);
        return repository.findByShareCode(shareCode)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("分享码无效或模板不存在")));
    }

    @Override
    @CacheEvict(value = "promptPackages", allEntries = true)
    public Mono<EnhancedUserPromptTemplate> copyPublicTemplate(String userId, String templateId) {
        log.info("复制公开模板: userId={}, templateId={}", userId, templateId);

        // 检查是否是虚拟ID
        if (templateId.startsWith("system_default_")) {
            return handleSystemDefaultTemplateCopy(userId, templateId);
        }
        if (templateId.startsWith("public_")) {
            return handlePublicTemplateCopy(userId, templateId);
        }

        return repository.findById(templateId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                .flatMap(template -> {
                    // 🔒 若作者开启了隐藏提示词，禁止他人复制
                    String owner = template.getAuthorId() != null ? template.getAuthorId() : template.getUserId();
                    boolean isOwner = userId != null && userId.equals(owner);
                    if (Boolean.TRUE.equals(template.getHidePrompts()) && !isOwner) {
                        return Mono.error(new IllegalStateException("作者隐藏了提示词，禁止复制"));
                    }
                    // 允许复制任何模板，包括其他用户的私有模板
                    log.info("复制模板: templateId={}, isPublic={}, owner={}", templateId, template.getIsPublic(), template.getUserId());

                    // 检查是否是用户该功能类型的第一个模板
                    return repository.countByUserIdAndFeatureType(userId, template.getFeatureType())
                            .flatMap(count -> {
                                boolean isFirstTemplate = count == 0;
                                
                                LocalDateTime now = LocalDateTime.now();
                                String newName = template.getName() + " (复制)";

                                EnhancedUserPromptTemplate copied = EnhancedUserPromptTemplate.builder()
                                        .id(UUID.randomUUID().toString())
                                        .userId(userId)
                                        .name(newName)
                                        .description(template.getDescription())
                                        .featureType(template.getFeatureType())
                                        .systemPrompt(template.getSystemPrompt())
                                        .userPrompt(template.getUserPrompt())
                                        .tags(template.getTags() != null ? List.copyOf(template.getTags()) : List.of())
                                        .categories(template.getCategories() != null ? List.copyOf(template.getCategories()) : List.of())
                                        .isPublic(false)
                                        .isFavorite(false)
                                        .isDefault(isFirstTemplate) // 第一个模板设为默认
                                        .isVerified(false)
                                        .usageCount(0L)
                                        .favoriteCount(0L)
                                        .rating(0.0)
                                        .authorId(userId)
                                        .sourceTemplateId(templateId)
                                        .version(1)
                                        .language(template.getLanguage() != null ? template.getLanguage() : "zh")
                                        .settingGenerationConfig(template.getSettingGenerationConfig()) // 🆕 复制设定生成配置
                                        .createdAt(now)
                                        .updatedAt(now)
                                        .build();

                                return repository.save(copied);
                            });
                })
                .doOnSuccess(copied -> log.info("成功复制公开模板: newId={}, sourceId={}, isDefault={}", copied.getId(), templateId, copied.getIsDefault()))
                .doOnError(error -> log.error("复制公开模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Flux<EnhancedUserPromptTemplate> getPublicTemplates(AIFeatureType featureType, int page, int size) {
        log.debug("获取公开模板列表: featureType={}, page={}, size={}", featureType, page, size);
        return repository.findPublicTemplatesByFeatureType(featureType)
                .sort((t1, t2) -> {
                    // 按评分和使用次数排序
                    int ratingCompare = Double.compare(t2.getRating() != null ? t2.getRating() : 0.0, 
                                                      t1.getRating() != null ? t1.getRating() : 0.0);
                    if (ratingCompare != 0) return ratingCompare;
                    return Long.compare(t2.getUsageCount() != null ? t2.getUsageCount() : 0L,
                                       t1.getUsageCount() != null ? t1.getUsageCount() : 0L);
                })
                .skip((long) page * size)
                .take(size);
    }

    @Override
    public Mono<Void> favoriteTemplate(String userId, String templateId) {
        log.info("收藏模板: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    if (userId.equals(template.getUserId())) {
                        // 用户收藏自己的模板
                        template.setIsFavorite(true);
                        template.setUpdatedAt(LocalDateTime.now());
                        return repository.save(template).then();
                    } else if (template.getIsPublic()) {
                        // 用户收藏公开模板 - 这里可以扩展为创建收藏关系记录
                        template.incrementFavoriteCount();
                        template.setUpdatedAt(LocalDateTime.now());
                        return repository.save(template).then();
                    } else {
                        return Mono.error(new IllegalArgumentException("无法收藏此模板"));
                    }
                })
                .doOnSuccess(v -> log.info("成功收藏模板: templateId={}", templateId))
                .doOnError(error -> log.error("收藏模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Mono<Void> unfavoriteTemplate(String userId, String templateId) {
        log.info("取消收藏模板: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    if (userId.equals(template.getUserId())) {
                        // 用户取消收藏自己的模板
                        template.setIsFavorite(false);
                        template.setUpdatedAt(LocalDateTime.now());
                        return repository.save(template).then();
                    } else if (template.getIsPublic()) {
                        // 用户取消收藏公开模板
                        template.decrementFavoriteCount();
                        template.setUpdatedAt(LocalDateTime.now());
                        return repository.save(template).then();
                    } else {
                        return Mono.error(new IllegalArgumentException("无法取消收藏此模板"));
                    }
                })
                .doOnSuccess(v -> log.info("成功取消收藏模板: templateId={}", templateId))
                .doOnError(error -> log.error("取消收藏模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Mono<EnhancedUserPromptTemplate> rateTemplate(String userId, String templateId, int rating) {
        if (rating < 1 || rating > 5) {
            return Mono.error(new IllegalArgumentException("评分必须在1-5之间"));
        }

        log.info("评分模板: userId={}, templateId={}, rating={}", userId, templateId, rating);

        return repository.findById(templateId)
                .flatMap(template -> {
                    // 只能对公开模板评分，且不能对自己的模板评分
                    if (!template.getIsPublic()) {
                        return Mono.error(new IllegalArgumentException("只能对公开模板评分"));
                    }
                    if (userId.equals(template.getUserId())) {
                        return Mono.error(new IllegalArgumentException("不能对自己的模板评分"));
                    }

                    // 更新评分统计（这里简化处理，实际应该记录用户评分历史）
                    template.updateRatingStatistics(rating);
                    template.setUpdatedAt(LocalDateTime.now());

                    return repository.save(template);
                })
                .doOnSuccess(rated -> log.info("成功评分模板: templateId={}, newRating={}", templateId, rated.getRating()))
                .doOnError(error -> log.error("评分模板失败: templateId={}, error={}", templateId, error.getMessage(), error));
    }

    @Override
    public Mono<Void> recordTemplateUsage(String userId, String templateId) {
        log.debug("记录模板使用: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    template.incrementUsageCount();
                    return repository.save(template).then();
                })
                .doOnError(error -> log.error("记录模板使用失败: templateId={}, error={}", templateId, error.getMessage()));
    }

    @Override
    public Flux<String> getUserTags(String userId) {
        log.debug("获取用户所有标签: userId={}", userId);
        return repository.findTagsByUserId(userId)
                .flatMapIterable(template -> template.getTags() != null ? template.getTags() : List.of())
                .distinct()
                .sort();
    }
    
    /**
     * 处理系统默认模板的复制
     * 从虚拟ID解析功能类型，使用提示词提供器获取默认内容
     */
    private Mono<EnhancedUserPromptTemplate> handleSystemDefaultTemplateCopy(String userId, String templateId) {
        log.info("复制系统默认模板: userId={}, templateId={}", userId, templateId);
        
        try {
            // 解析功能类型 from "system_default_AIFeatureType.textExpansion"
            String featureTypePart = templateId.replace("system_default_", "");
            if (featureTypePart.startsWith("AIFeatureType.")) {
                featureTypePart = featureTypePart.replace("AIFeatureType.", "");
            }
            
            AIFeatureType featureType;
            try {
                // 处理前端的camelCase到后端的UPPER_CASE映射
                String upperCaseFeatureType = convertCamelCaseToUpperCase(featureTypePart);
                featureType = AIFeatureType.valueOf(upperCaseFeatureType);
            } catch (IllegalArgumentException e) {
                log.error("无法解析功能类型: {}", featureTypePart);
                return Mono.error(new IllegalArgumentException("无效的系统模板ID: " + templateId));
            }
            
            // 获取对应的提示词提供器
            AIFeaturePromptProvider provider = promptProviderFactory.getProvider(featureType);
            if (provider == null) {
                return Mono.error(new IllegalArgumentException("不支持的功能类型: " + featureType));
            }
            
            // 检查是否是用户该功能类型的第一个模板
            return repository.countByUserIdAndFeatureType(userId, featureType)
                    .flatMap(count -> {
                        boolean isFirstTemplate = count == 0;
                        
                        // 创建基于系统默认内容的用户模板
                        LocalDateTime now = LocalDateTime.now();
                        String systemPrompt = provider.getDefaultSystemPrompt();
                        String userPrompt = provider.getDefaultUserPrompt();
                        
                        EnhancedUserPromptTemplate copied = EnhancedUserPromptTemplate.builder()
                                .id(UUID.randomUUID().toString())
                                .userId(userId)
                                .name("系统默认模板 (复制)")
                                .description("基于系统默认模板创建的用户自定义模板")
                                .featureType(featureType)
                                .systemPrompt(systemPrompt)
                                .userPrompt(userPrompt)
                                .tags(List.of("系统默认", "复制"))
                                .categories(List.of())
                                .isPublic(false)
                                .isFavorite(false)
                                .isDefault(isFirstTemplate) // 第一个模板设为默认
                                .isVerified(false)
                                .usageCount(0L)
                                .favoriteCount(0L)
                                .rating(0.0)
                                .authorId(userId)
                                .sourceTemplateId(templateId)
                                .version(1)
                                .language("zh")
                                .createdAt(now)
                                .updatedAt(now)
                                .build();
                        
                        return repository.save(copied);
                    })
                    .doOnSuccess(result -> log.info("成功复制系统默认模板: newId={}, sourceId={}, isDefault={}", 
                            result.getId(), templateId, result.getIsDefault()));
                    
        } catch (Exception e) {
            log.error("复制系统默认模板失败: templateId={}, error={}", templateId, e.getMessage(), e);
            return Mono.error(new IllegalArgumentException("复制系统默认模板失败: " + e.getMessage()));
        }
    }
    
    /**
     * 处理公开模板的复制
     * 从虚拟ID解析真实的模板ID，然后复制
     */
    private Mono<EnhancedUserPromptTemplate> handlePublicTemplateCopy(String userId, String templateId) {
        log.info("复制公开模板虚拟ID: userId={}, templateId={}", userId, templateId);
        
        try {
            // 解析真实的模板ID from "public_realTemplateId"
            String realTemplateId = templateId.replace("public_", "");
            
            if (realTemplateId.isEmpty()) {
                return Mono.error(new IllegalArgumentException("无效的公开模板ID: " + templateId));
            }
            
            // 递归调用原方法处理真实的模板ID
            return copyPublicTemplate(userId, realTemplateId);
            
        } catch (Exception e) {
            log.error("复制公开模板虚拟ID失败: templateId={}, error={}", templateId, e.getMessage(), e);
            return Mono.error(new IllegalArgumentException("复制公开模板失败: " + e.getMessage()));
        }
    }
    
    /**
     * 将camelCase转换为UPPER_CASE
     * 例如：textExpansion -> TEXT_EXPANSION
     */
    private String convertCamelCaseToUpperCase(String camelCase) {
        if (camelCase == null || camelCase.isEmpty()) {
            return camelCase;
        }
        
        // 处理特殊映射
        switch (camelCase) {
            case "textExpansion":
                return "TEXT_EXPANSION";
            case "textRefactor":
                return "TEXT_REFACTOR";
            case "textSummary":
                return "TEXT_SUMMARY";
            case "aiChat":
                return "AI_CHAT";
            case "novelGeneration":
                return "NOVEL_GENERATION";
            case "professionalFictionContinuation":
                return "PROFESSIONAL_FICTION_CONTINUATION";
            case "sceneToSummary":
                return "SCENE_TO_SUMMARY";
            case "summaryToScene":
                return "SUMMARY_TO_SCENE";
            default:
                // 通用的camelCase转UPPER_CASE逻辑
                return camelCase.replaceAll("([a-z])([A-Z])", "$1_$2").toUpperCase();
        }
    }

    // ==================== 默认模板功能实现 ====================

    @Override
    @CacheEvict(value = "promptPackages", allEntries = true)
    public Mono<EnhancedUserPromptTemplate> setDefaultTemplate(String userId, String templateId) {
        log.info("设置默认模板: userId={}, templateId={}", userId, templateId);

        return repository.findById(templateId)
                .flatMap(template -> {
                    // 验证权限
                    if (!userId.equals(template.getUserId())) {
                        return Mono.error(new IllegalArgumentException("无权设置此模板为默认"));
                    }

                    AIFeatureType featureType = template.getFeatureType();
                    
                    // 先清除该功能类型下所有模板的默认状态
                    return repository.findAllByUserIdAndFeatureTypeAndIsDefaultTrue(userId, featureType)
                            .flatMap(existingDefault -> {
                                existingDefault.setIsDefault(false);
                                existingDefault.setUpdatedAt(LocalDateTime.now());
                                return repository.save(existingDefault);
                            })
                            .then(Mono.defer(() -> {
                                // 设置新的默认模板
                                template.setIsDefault(true);
                                template.setUpdatedAt(LocalDateTime.now());
                                return repository.save(template);
                            }));
                })
                .doOnSuccess(updated -> log.info("成功设置默认模板: templateId={}, featureType={}", 
                        updated.getId(), updated.getFeatureType()))
                .doOnError(error -> log.error("设置默认模板失败: templateId={}, error={}", 
                        templateId, error.getMessage(), error));
    }

    @Override
    public Mono<EnhancedUserPromptTemplate> getDefaultTemplate(String userId, AIFeatureType featureType) {
        log.debug("获取默认模板: userId={}, featureType={}", userId, featureType);
        
        return repository.findByUserIdAndFeatureTypeAndIsDefaultTrue(userId, featureType)
                .switchIfEmpty(
                    // 如果没有默认模板，返回该功能类型的第一个模板
                    repository.findByUserIdAndFeatureType(userId, featureType)
                            .sort((t1, t2) -> t1.getCreatedAt().compareTo(t2.getCreatedAt()))
                            .next()
                            .doOnNext(firstTemplate -> log.debug("未找到默认模板，返回第一个模板: templateId={}", 
                                    firstTemplate.getId()))
                )
                .doOnNext(template -> log.debug("找到模板: templateId={}, isDefault={}", 
                        template.getId(), template.getIsDefault()));
    }
    
    // ==================== 提示词模板功能实现 ====================
    
    @Override
    public Mono<String> getSuggestionPrompt(String suggestionType) {
        log.info("获取建议提示词，类型: {}", suggestionType);
        
        String defaultTemplate = DEFAULT_TEMPLATES.getOrDefault(suggestionType,
                "请为我的小说提供" + suggestionType + "方面的建议。");
        return Mono.just(defaultTemplate);
    }
    
    @Override
    public Mono<String> getRevisionPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("revision"));
    }
    
    @Override
    public Mono<String> getCharacterGenerationPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("character_generation"));
    }
    
    @Override
    public Mono<String> getPlotGenerationPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("plot_generation"));
    }
    
    @Override
    public Mono<String> getSettingGenerationPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("setting_generation"));
    }
    
    @Override
    public Mono<String> getNextOutlinesGenerationPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("next_outlines_generation"));
    }
    
    @Override
    public Mono<String> getNextChapterOutlineGenerationPrompt() {
        return Mono.just(DEFAULT_TEMPLATES.get("next_chapter_outline_generation"));
    }
    
    @Override
    public Mono<String> getSingleOutlineGenerationPrompt() {
        String prompt = "基于以下上下文信息，为小说生成一个有趣而合理的后续剧情大纲选项。"
                + "请确保生成的剧情与已有内容保持连贯，符合角色性格，推动情节发展。\n\n"
                + "当前上下文：\n{{context}}\n\n"
                + "{{authorGuidance}}\n\n"
                + "请严格按照以下格式返回你的剧情大纲，先输出标题，再输出内容：\n"
                + "TITLE: [简洁有力的标题，概括这个剧情走向的核心]\n"
                + "CONTENT: [详细描述这个剧情大纲，包括关键人物动向、重要事件、情节转折等]";
        
        return Mono.just(prompt);
    }
    
    @Override
    public Mono<Map<String, String>> getStructuredSettingPrompt(String settingTypes, int maxSettingsPerType, String additionalInstructions) {
        Map<String, String> prompts = new HashMap<>();
        
        // 系统提示词 - 增强JSON生成指导
        prompts.put("system", "你是一个专业的小说设定分析专家。你的任务是从提供的文本中提取并生成小说设定项。\n\n" +
            "**关键要求：**\n" +
            "1. 输出必须是完整且有效的JSON数组格式\n" +
            "2. 每个对象必须包含：\n" +
            "   - 'name' (字符串): 设定项名称\n" +
            "   - 'type' (字符串): 设定类型，必须是请求的有效类型之一\n" +
            "   - 'description' (字符串): 详细描述\n" +
            "3. 可选字段：\n" +
            "   - 'attributes' (对象): 属性键值对\n" +
            "   - 'tags' (数组): 标签列表\n" +
            "   - 'parentId' (字符串): 父设定ID，用于建立层级关系\n\n" +
            "**设定关联规则：**\n" +
            "- 如果新生成的设定与已有设定存在关联关系或父子关系，请填充 'parentId' 字段\n" +
            "- parentId 应该是已有设定的ID（在已有设定列表中查找）\n" +
            "- 例如：某个物品属于某个角色，该物品的parentId应该是该角色的ID\n" +
            "- 例如：某个地点的子区域，子区域的parentId应该是父区域的ID\n\n" +
            "**JSON格式要求：**\n" +
            "- 必须以 [ 开始，以 ] 结束\n" +
            "- 每个对象必须完整闭合 { }\n" +
            "- 所有字符串必须用双引号包围\n" +
            "- 对象间用逗号分隔\n" +
            "- 不要添加任何解释文字或代码块标记\n" +
            "- 确保JSON语法完全正确\n\n" +
            "**示例输出格式：**\n" +
            "[{\"name\":\"示例名称\",\"type\":\"角色\",\"description\":\"示例描述\"},{\"name\":\"相关物品\",\"type\":\"道具\",\"description\":\"示例描述\",\"parentId\":\"已有设定ID\"}]\n\n" +
            "如果找不到某种类型的设定，请不要包含它。专注于生成完整、有效的JSON数组。");
        
        // 用户提示词模板 - 增强指导
        String userPromptTemplate = "**小说上下文：**\n{{contextText}}\n\n" +
            "**请求的设定类型：** {{settingTypes}}\n" +
            "**生成数量：** 为每种类型生成大约 {{maxSettingsPerType}} 个项目\n" +
            "**附加说明：** {{additionalInstructions}}\n\n" +
            "请严格按照以下要求输出：\n" +
            "1. 只输出JSON数组，不要任何其他文字\n" +
            "2. 确保JSON格式完整且有效\n" +
            "3. 每个对象都必须完整闭合\n" +
            "4. 所有必需字段都必须包含\n" +
            "5. 字符串值不能为空\n\n" +
            "现在请输出完整的JSON数组：";
        
        // 填充用户提示词模板
        String userPrompt = userPromptTemplate
            .replace("{{settingTypes}}", settingTypes)
            .replace("{{maxSettingsPerType}}", String.valueOf(maxSettingsPerType))
            .replace("{{additionalInstructions}}", additionalInstructions == null ? "无特殊要求" : additionalInstructions);
        
        prompts.put("user", userPrompt);
        
        return Mono.just(prompts);
    }
    
    @Override
    public Mono<String> getGeneralSettingPrompt(String contextText, String settingTypes, int maxSettingsPerType, String additionalInstructions) {
        StringBuilder promptBuilder = new StringBuilder();
        promptBuilder.append("你是一个专业的小说设定分析专家。请从以下小说内容中提取并生成小说设定项。\n\n");
        promptBuilder.append("小说内容:\n").append(contextText).append("\n\n");
        promptBuilder.append("请求的设定类型: ").append(settingTypes).append("\n");
        promptBuilder.append("为每种请求的类型生成大约 ").append(maxSettingsPerType).append(" 个项目。\n");
        
        if (additionalInstructions != null && !additionalInstructions.isEmpty()) {
            promptBuilder.append("附加说明: ").append(additionalInstructions).append("\n\n");
        }
        
        promptBuilder.append("请以JSON数组格式返回结果。每个对象必须包含以下字段:\n");
        promptBuilder.append("- name: 设定项名称 (字符串)\n");
        promptBuilder.append("- type: 设定类型 (字符串，必须是请求的类型之一)\n");
        promptBuilder.append("- description: 详细描述 (字符串)\n");
        promptBuilder.append("可选字段:\n");
        promptBuilder.append("- attributes: 属性映射 (键值对)\n");
        promptBuilder.append("- tags: 标签列表 (字符串数组)\n\n");
        promptBuilder.append("示例输出格式:\n");
        promptBuilder.append("[{\"name\": \"魔法剑\", \"type\": \"ITEM\", \"description\": \"一把会发光的剑\", \"attributes\": {\"color\": \"blue\"}, \"tags\": [\"magic\", \"weapon\"]}]\n\n");
        promptBuilder.append("确保输出是有效的JSON数组。你的输出必须是纯JSON格式，不需要任何额外的说明文字。");
        
        return Mono.just(promptBuilder.toString());
    }
    
    @Override
    public Mono<String> getSystemMessageForFeature(AIFeatureType featureType) {
        String key = featureType.name() + "_SYSTEM";
        log.info("获取特性 {} 的系统提示词，键: {}", featureType, key);
        return Mono.justOrEmpty(DEFAULT_TEMPLATES.get(key))
                .switchIfEmpty(Mono.defer(() -> {
                    log.warn("特性 {} 没有找到特定的系统提示词 (键: {})，可能需要定义默认模板。", featureType, key);
                    return Mono.empty();
                }));
    }
    
    @Override
    public Mono<List<String>> getAllPromptTypes() {
        log.info("获取所有提示词类型");
        return Mono.just(List.copyOf(DEFAULT_TEMPLATES.keySet()));
    }
        // 默认提示词模板
    private static final Map<String, String> DEFAULT_TEMPLATES = new HashMap<>();

    static {
        // 初始化默认提示词模板
        DEFAULT_TEMPLATES.put("plot", "请为我的小说提供情节建议。我正在写一个场景，需要有创意的情节发展。");
        DEFAULT_TEMPLATES.put("character", "请为我的小说提供角色互动建议。我需要让角色之间的对话和互动更加生动。");
        DEFAULT_TEMPLATES.put("dialogue", "请为我的小说提供对话建议。我需要让角色的对话更加自然和有特点。");
        DEFAULT_TEMPLATES.put("description", "请为我的小说提供场景描述建议。我需要让环境描写更加生动和有氛围感。");
        DEFAULT_TEMPLATES.put("revision", "请帮我修改以下内容，按照指示进行调整：\n\n{{content}}\n\n修改指示：{{instruction}}\n\n请提供修改后的完整内容。");
        DEFAULT_TEMPLATES.put("character_generation", "请根据以下描述，为我的小说创建一个详细的角色：\n\n{{description}}\n\n请提供角色的姓名、外貌、性格、背景故事、动机和特点等信息。");
        DEFAULT_TEMPLATES.put("plot_generation", "请根据以下描述，为我的小说创建一个详细的情节：\n\n{{description}}\n\n请提供情节的起因、发展、高潮和结局，以及可能的转折点和悬念。");
        DEFAULT_TEMPLATES.put("setting_generation", "请根据以下描述，为我的小说创建一个详细的世界设定：\n\n{{description}}\n\n请提供这个世界的地理、历史、文化、社会结构、规则和特殊元素等信息。");
        DEFAULT_TEMPLATES.put("next_outlines_generation", "你是一位专业的小说创作顾问，擅长为作者提供多样化的剧情发展选项。请根据以下信息，为作者生成 {{numberOfOptions}} 个不同的剧情大纲选项，每个选项应该是对当前故事的合理延续。\n\n小说当前进展：{{context}}\n\n{{authorGuidance}}\n\n请为每个选项提供以下内容：\n1. 一个简短但吸引人的标题\n2. 剧情概要（200-300字）\n3. 主要事件（3-5个关键点）\n4. 涉及的角色\n5. 冲突或悬念\n\n格式要求：\n选项1：[标题]\n[剧情概要]\n主要事件：\n- [事件1]\n- [事件2]\n- [事件3]\n涉及角色：[角色列表]\n冲突/悬念：[冲突或悬念描述]\n\n选项2：[标题]\n...\n\n注意事项：\n- 每个选项应该有明显的差异，提供真正不同的故事发展方向\n- 保持与已有故事的连贯性和一致性\n- 考虑角色动机和故事内在逻辑\n- 提供有创意但合理的发展方向\n- 确保每个选项都有足够的戏剧冲突和情感张力");
        
        // 新增设定生成相关提示词模板
        DEFAULT_TEMPLATES.put("setting_item_generation", "你是一个专业的小说设定分析专家。你的任务是从提供的文本中提取并生成小说设定项。" +
            "每个对象必须代表一个不同的设定项，并且必须包含\'name\'（字符串）、\'type\'（字符串，必须是提供的有效类型之一）和\'description\'（字符串）。" +
            "可选字段是\'attributes\'（Map<String, String>）和\'tags\'（List<String>）。" +
            "确保输出是有效的JSON对象列表。如果找不到某种类型的设定，请不要包含它。");

        // 新增：下一章剧情大纲生成提示词模板
        DEFAULT_TEMPLATES.put("next_chapter_outline_generation", "你是一位专业的小说创作顾问，擅长为作者的下一章内容提供一个详细的剧情发展构思。" +
            "你的目标是基于提供的小说背景信息、最近章节的完整内容以及作者的特定指导，创作出一个详细的、仅覆盖一章内容的剧情大纲。" +
            "请仔细研读\"上一章节完整内容\"，以确保你的建议在文风、文笔和情节发展上与原文保持一致性和连贯性。" +
            "剧情大纲应该足够详细，能够支撑起一个完整章节的写作，并明确指出故事将如何在本章内发展和可能的小高潮。" +
            "不要生成超出单章范围的剧情。" +
            "\n\n小说当前进展摘要：\n{{contextSummary}}" +
            "\n\n上一章节完整内容：\n{{previousChapterContent}}" +
            "\n\n作者的创作方向引导：\n{{authorGuidance}}" +
            "\n\n请严格按照以下格式返回你的剧情大纲，确保是纯文本，不包含任何列表符号 (如 '*' 或 '-') 或其他 Markdown 格式：" +
            "\n标题：[此处填写简洁且引人入胜的标题，点明本章核心内容]" +
            "\n剧情概要：[此处填写详细的本章剧情概要，描述主要情节脉络、发展和转折，预计300-500字]" +
            "\n\n请确保你的构思独特且合理，同时忠于已有的故事设定和角色塑造。");

        // 新增: "根据摘要生成场景" 的系统提示词
        DEFAULT_TEMPLATES.put(AIFeatureType.SUMMARY_TO_SCENE.name() + "_SYSTEM",
                "你是一位富有创意的小说家。请根据用户提供的摘要、上下文信息和风格要求，生成详细的小说场景内容。" +
                "你的任务是只输出生成的场景内容本身，不包含任何标题、小标题、格式标记（如Markdown）、或其他解释性文字。" );

        // 新增: "专业续写小说" 的系统提示词
        DEFAULT_TEMPLATES.put(AIFeatureType.PROFESSIONAL_FICTION_CONTINUATION.name() + "_SYSTEM",
                "你是一位专业的小说续写专家。你的专长是根据已有内容进行高质量的小说续写。\n\n" +
                "请始终遵循以下续写规则：\n" +
                "- 使用过去时态，采用中文写作规范和表达习惯\n" +
                "- 使用主动语态\n" +
                "- 始终遵循\"展现，而非叙述\"的原则\n" +
                "- 避免使用副词、陈词滥调和过度使用的常见短语。力求新颖独特的描述\n" +
                "- 通过对话来传达事件和故事发展\n" +
                "- 混合使用短句和长句，短句富有冲击力，长句细致描述。省略冗余词汇增加变化\n" +
                "- 省略\"他/她说\"这样的对话标签，通过角色的动作或面部表情来传达说话状态\n" +
                "- 避免过于煽情的对话和描述，对话应始终推进情节，绝不拖沓或添加不必要的冗余。变化描述以避免重复\n" +
                "- 将对话单独成段，与场景和动作分离\n" +
                "- 减少不确定性的表达，如\"试图\"或\"也许\"\n\n" +
                "续写时请特别注意：\n" +
                "- 必须与前文保持高度连贯性，包括人物性格、情节逻辑、写作风格\n" +
                "- 仔细分析前文的语言风格、节奏感和叙述特点，在续写中保持一致\n" +
                "- 绝不要自己结束场景，严格按照续写指示进行\n" +
                "- 绝不要以预示结尾\n" +
                "- 绝不要写超出所提示的内容范围\n" +
                "- 避免想象可能的结局，绝不要偏离续写指示\n" +
                "- 如果续写内容已包含指示中要求的情节点，请适时停止。你不需要填满所有可能的字数");

        // 新增: "专业续写小说" 的用户提示词模板
        DEFAULT_TEMPLATES.put(AIFeatureType.PROFESSIONAL_FICTION_CONTINUATION.name(),
                "前文内容：{{previousContent}}\n\n" +
                "续写要求：{{continuationRequirements}}\n\n" +
                "情节指导：{{plotGuidance}}\n\n" +
                "风格要求：{{styleRequirements}}\n\n" +
                "请根据以上信息，按照专业小说续写标准，自然流畅地续写下去。");

        // 新增: "根据摘要生成场景" 的基础用户提示词模板
        // UserPromptService 会优先查找用户自定义版本，如果找不到，则回退到这个基础版本
        DEFAULT_TEMPLATES.put(AIFeatureType.SUMMARY_TO_SCENE.name(),
                "摘要:\n{{summary}}\n\n相关上下文:\n{{context}}\n\n风格要求:\n{{styleInstructions}}\n\n" +
                "请根据以上摘要和上下文信息，创作一个完整的场景。确保场景内容与摘要和上下文保持一致，" +
                "同时符合风格要求。你需要将摘要中简要描述的内容具体化，加入细节、对话、情感和环境描写。");
    }
} 