package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIPromptPreset;
import com.ainovel.server.repository.AIPromptPresetRepository;
import com.ainovel.server.repository.EnhancedUserPromptTemplateRepository;
import com.ainovel.server.service.AIPresetService;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * AI预设服务实现类
 * 专门处理预设的CRUD操作和管理功能
 */
@Slf4j
@Service
public class AIPresetServiceImpl implements AIPresetService {

    @Autowired
    private AIPromptPresetRepository presetRepository;

    @Autowired
    private EnhancedUserPromptTemplateRepository templateRepository;

    @Autowired
    private ObjectMapper objectMapper;

    @Override
    public Mono<AIPromptPreset> createPreset(UniversalAIRequestDto request, String presetName, 
                                           String presetDescription, List<String> presetTags) {
        log.info("创建AI预设 - userId: {}, presetName: {}", request.getUserId(), presetName);
        
        // 🚀 修复：移除预设名称唯一性检查，允许用户创建同名预设
        // 直接创建预设，存储原始请求数据
        return createPresetFromRequest(request, presetName, presetDescription, presetTags);
    }

    /**
     * 🚀 新方法：从请求直接创建预设（不拼接提示词）
     */
    private Mono<AIPromptPreset> createPresetFromRequest(UniversalAIRequestDto request, String presetName,
                                                        String presetDescription, List<String> presetTags) {
        try {
            String presetId = UUID.randomUUID().toString();
            
            // 将请求数据序列化为JSON
            String requestDataJson = objectMapper.writeValueAsString(request);
            
            // 生成预设哈希
            String presetHash = generatePresetHash(requestDataJson);
            
            // 获取AI功能类型
            String aiFeatureType = determineAIFeatureType(request.getRequestType());
            
            // 🚀 关键：直接存储原始数据，不生成拼接的提示词
            AIPromptPreset preset = AIPromptPreset.builder()
                    .presetId(presetId)
                    .userId(request.getUserId())
                    .novelId(request.getNovelId())
                    .presetName(presetName)
                    .presetDescription(presetDescription)
                    .presetTags(presetTags != null ? presetTags : new ArrayList<>())
                    .isFavorite(false)
                    .isPublic(false)
                    .useCount(0)
                    .presetHash(presetHash)
                    .requestData(requestDataJson) // 🚀 存储原始请求JSON
                    .systemPrompt(getDefaultSystemPrompt(aiFeatureType)) // 使用默认系统提示词
                    .userPrompt(request.getInstructions() != null ? request.getInstructions() : "") // 存储用户指令
                    .aiFeatureType(aiFeatureType)
                    .templateId(null) // 预设创建时不关联模板
                    .customSystemPrompt(null)
                    .customUserPrompt(null)
                    .promptCustomized(false)
                    .isSystem(false)
                    .showInQuickAccess(false)
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build();
            
            log.info("创建预设对象完成 - presetId: {}, aiFeatureType: {}", presetId, aiFeatureType);
            
            return presetRepository.save(preset);
            
        } catch (Exception e) {
            log.error("创建预设失败", e);
            return Mono.error(new RuntimeException("创建预设失败: " + e.getMessage(), e));
        }
    }

    /**
     * 生成预设哈希值
     */
    private String generatePresetHash(String requestDataJson) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(requestDataJson.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) {
                    hexString.append('0');
                }
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (NoSuchAlgorithmException e) {
            log.error("生成预设哈希失败", e);
            return UUID.randomUUID().toString().replace("-", "");
        }
    }

    /**
     * 根据请求类型确定AI功能类型
     */
    private String determineAIFeatureType(String requestType) {
        if (requestType == null) {
            return AIFeatureType.TEXT_EXPANSION.name();
        }
        return requestType;
        
//        switch (requestType.toUpperCase()) {
//            case "EXPANSION":
//                return AIFeatureType.TEXT_EXPANSION.name();
//            case "SUMMARY":
//                return AIFeatureType.TEXT_SUMMARY.name();
//            case "REFACTOR":
//                return AIFeatureType.TEXT_REFACTOR.name();
//            case "CHAT":
//                return AIFeatureType.AI_CHAT.name();
//            case "GENERATION":
//                return AIFeatureType.NOVEL_GENERATION.name();
//            case "SCENE_SUMMARY":
//                return AIFeatureType.SCENE_TO_SUMMARY.name();
//            default:
//                log.warn("未知的请求类型: {}, 使用默认类型", requestType);
//                return AIFeatureType.TEXT_EXPANSION.name();
//        }
    }

    /**
     * 获取默认系统提示词
     */
    private String getDefaultSystemPrompt(String aiFeatureType) {
        try {
            AIFeatureType featureType = AIFeatureType.valueOf(aiFeatureType);
            switch (featureType) {
                case TEXT_EXPANSION:
                    return "你是一位专业的文本扩写助手，擅长为用户的内容添加更多细节、描述和深度。";
                case TEXT_SUMMARY:
                    return "你是一位专业的文本摘要助手，擅长提取关键信息并生成简洁准确的摘要。";
                case TEXT_REFACTOR:
                    return "你是一位专业的文本重构助手，擅长改善文本的结构、风格和表达方式。";
                case AI_CHAT:
                    return "你是一位智能助手，可以与用户进行自然、有用的对话。";
                case NOVEL_GENERATION:
                    return "你是一位专业的小说创作助手，擅长生成引人入胜的故事内容。";
                case SCENE_TO_SUMMARY:
                    return "你是一位专业的场景摘要助手，擅长分析场景内容并生成准确的摘要。";
                case SUMMARY_TO_SCENE:
                    return "你是一位专业的场景创作助手，擅长根据摘要生成详细的场景内容。";
                default:
                    return "你是一位专业的AI助手，可以帮助用户完成各种文本处理任务。";
            }
        } catch (Exception e) {
            log.warn("获取默认系统提示词失败，使用通用提示词", e);
            return "你是一位专业的AI助手，可以帮助用户完成各种文本处理任务。";
        }
    }

    @Override
    public Mono<AIPromptPreset> overwritePreset(String presetId, AIPromptPreset newPreset) {
        log.info("覆盖更新预设 - presetId: {}, presetName: {}", presetId, newPreset.getPresetName());
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(oldPreset -> {
                    // 检查权限：只有用户自己的预设才能修改
                    if (oldPreset.getIsSystem()) {
                        return Mono.error(new IllegalArgumentException("无法修改系统预设"));
                    }
                    
                    // 保险起见，保留系统关键字段不被前端篡改
                    newPreset.setId(oldPreset.getId());
                    newPreset.setPresetId(oldPreset.getPresetId());
                    newPreset.setUserId(oldPreset.getUserId());
                    newPreset.setIsSystem(oldPreset.getIsSystem());
                    newPreset.setCreatedAt(oldPreset.getCreatedAt());
                    newPreset.setUpdatedAt(LocalDateTime.now());
                    
                    // 如果前端没有传递预设哈希，保持原有哈希
                    if (newPreset.getPresetHash() == null || newPreset.getPresetHash().isEmpty()) {
                        newPreset.setPresetHash(oldPreset.getPresetHash());
                    }
                    
                    log.info("覆盖更新预设完成 - presetId: {}, 新名称: {}", presetId, newPreset.getPresetName());
                    
                    return presetRepository.save(newPreset);
                });
    }

    @Override
    public Mono<AIPromptPreset> updatePresetInfo(String presetId, String presetName, 
                                               String presetDescription, List<String> presetTags) {
        log.info("更新预设信息 - presetId: {}, presetName: {}", presetId, presetName);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> {
                    // 检查权限：只有用户自己的预设才能修改
                    if (preset.getIsSystem()) {
                        return Mono.error(new IllegalArgumentException("无法修改系统预设"));
                    }
                    
                    // 更新字段
                    preset.setPresetName(presetName);
                    preset.setPresetDescription(presetDescription);
                    preset.setPresetTags(presetTags);
                    preset.setUpdatedAt(LocalDateTime.now());
                    
                    return presetRepository.save(preset);
                });
    }

    @Override
    public Mono<AIPromptPreset> updatePresetPrompts(String presetId, String customSystemPrompt, String customUserPrompt) {
        log.info("更新预设提示词 - presetId: {}", presetId);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> {
                    if (preset.getIsSystem()) {
                        return Mono.error(new IllegalArgumentException("无法修改系统预设"));
                    }
                    
                    preset.setCustomSystemPrompt(customSystemPrompt);
                    preset.setCustomUserPrompt(customUserPrompt);
                    preset.setPromptCustomized(true);
                    preset.setUpdatedAt(LocalDateTime.now());
                    
                    return presetRepository.save(preset);
                });
    }

    @Override
    public Mono<AIPromptPreset> updatePresetTemplate(String presetId, String templateId) {
        log.info("更新预设模板关联 - presetId: {}, templateId: {}", presetId, templateId);

        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> templateRepository.findById(templateId)
                        .switchIfEmpty(Mono.error(new IllegalArgumentException("模板不存在: " + templateId)))
                        .flatMap(template -> {
                            // 1) 功能类型必须一致
                            try {
                                AIFeatureType presetFeatureType = AIFeatureType.valueOf(
                                        preset.getAiFeatureType() != null ? preset.getAiFeatureType() : "TEXT_EXPANSION");
                                if (template.getFeatureType() != null && !template.getFeatureType().equals(presetFeatureType)) {
                                    return Mono.error(new IllegalArgumentException("模板功能类型与预设不一致"));
                                }
                            } catch (IllegalArgumentException ex) {
                                return Mono.error(new IllegalArgumentException("预设功能类型无效: " + preset.getAiFeatureType()));
                            }

                            // 2) 不同预设类型的关联约束
                            if (Boolean.TRUE.equals(preset.getIsSystem())) {
                                // 系统预设：禁止关联公共模板；仅允许关联同一管理员创建的私有模板
                                if (Boolean.TRUE.equals(template.getIsPublic())) {
                                    return Mono.error(new IllegalArgumentException("系统预设不能关联公共模板"));
                                }
                                if (template.getUserId() == null || !template.getUserId().equals(preset.getUserId())) {
                                    return Mono.error(new IllegalArgumentException("系统预设只能关联由同管理员创建的私有模板"));
                                }
                            } else if (Boolean.TRUE.equals(preset.getIsPublic())) {
                                // 公共预设：仅允许关联已验证的系统模板（公共且已验证）
                                if (!(Boolean.TRUE.equals(template.getIsPublic()) && Boolean.TRUE.equals(template.getIsVerified()))) {
                                    return Mono.error(new IllegalArgumentException("公共预设只能关联已验证的系统模板"));
                                }
                            } else {
                                // 用户预设：允许关联自己的私有模板或任何公共模板
                                boolean isOwnPrivate = !Boolean.TRUE.equals(template.getIsPublic())
                                        && template.getUserId() != null
                                        && template.getUserId().equals(preset.getUserId());
                                boolean isPublicTpl = Boolean.TRUE.equals(template.getIsPublic());
                                if (!isOwnPrivate && !isPublicTpl) {
                                    return Mono.error(new IllegalArgumentException("只能关联自己的私有模板或公开模板"));
                                }
                            }

                            // 通过校验，保存关联
                            preset.setTemplateId(template.getId());
                            preset.setUpdatedAt(LocalDateTime.now());
                            return presetRepository.save(preset);
                        }));
    }

    @Override
    public Mono<Void> deletePreset(String presetId) {
        log.info("删除预设 - presetId: {}", presetId);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> {
                    if (preset.getIsSystem()) {
                        return Mono.error(new IllegalArgumentException("无法删除系统预设"));
                    }
                    
                    return presetRepository.deleteByPresetId(presetId);
                });
    }

    @Override
    public Mono<AIPromptPreset> duplicatePreset(String presetId, String newPresetName) {
        log.info("复制预设 - sourcePresetId: {}, newPresetName: {}", presetId, newPresetName);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("源预设不存在: " + presetId)))
                .flatMap(sourcePreset -> {
                    // 创建复制的预设
                    String newPresetId = UUID.randomUUID().toString();
                    
                    AIPromptPreset duplicatedPreset = AIPromptPreset.builder()
                            .presetId(newPresetId)
                            .userId(sourcePreset.getUserId())
                            .novelId(sourcePreset.getNovelId())
                            .presetName(newPresetName)
                            .presetDescription(sourcePreset.getPresetDescription())
                            .presetTags(new ArrayList<>(sourcePreset.getPresetTags() != null ? sourcePreset.getPresetTags() : new ArrayList<>()))
                            .isFavorite(false)
                            .isPublic(false)
                            .useCount(0)
                            .presetHash(sourcePreset.getPresetHash())
                            .requestData(sourcePreset.getRequestData())
                            .systemPrompt(sourcePreset.getSystemPrompt())
                            .userPrompt(sourcePreset.getUserPrompt())
                            .aiFeatureType(sourcePreset.getAiFeatureType())
                            .templateId(sourcePreset.getTemplateId())
                            .customSystemPrompt(sourcePreset.getCustomSystemPrompt())
                            .customUserPrompt(sourcePreset.getCustomUserPrompt())
                            .promptCustomized(sourcePreset.getPromptCustomized())
                            .isSystem(false) // 复制的预设永远不是系统预设
                            .showInQuickAccess(false) // 默认不显示在快捷访问中
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .build();
                    
                    return presetRepository.save(duplicatedPreset);
                });
    }

    @Override
    public Mono<AIPromptPreset> toggleQuickAccess(String presetId) {
        log.info("切换快捷访问状态 - presetId: {}", presetId);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> {
                    preset.setShowInQuickAccess(!preset.getShowInQuickAccess());
                    preset.setUpdatedAt(LocalDateTime.now());
                    
                    return presetRepository.save(preset);
                });
    }

    @Override
    public Mono<AIPromptPreset> toggleFavorite(String presetId) {
        log.info("切换收藏状态 - presetId: {}", presetId);
        
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)))
                .flatMap(preset -> {
                    preset.setIsFavorite(!preset.getIsFavorite());
                    preset.setUpdatedAt(LocalDateTime.now());
                    
                    return presetRepository.save(preset);
                });
    }

    @Override
    public Mono<Void> recordUsage(String presetId) {
        log.debug("记录预设使用 - presetId: {}", presetId);
        
        return presetRepository.findByPresetId(presetId)
                .flatMap(preset -> {
                    preset.setUseCount(preset.getUseCount() + 1);
                    preset.setLastUsedAt(LocalDateTime.now());
                    preset.setUpdatedAt(LocalDateTime.now());
                    
                    return presetRepository.save(preset);
                })
                .then();
    }

    @Override
    public Mono<AIPromptPreset> getPresetById(String presetId) {
        return presetRepository.findByPresetId(presetId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("预设不存在: " + presetId)));
    }

    @Override
    public Flux<AIPromptPreset> getUserPresets(String userId) {
        return presetRepository.findByUserIdOrderByCreatedAtDesc(userId);
    }

    @Override
    public Flux<AIPromptPreset> getUserPresetsByNovelId(String userId, String novelId) {
        // 获取特定小说的预设 + 全局预设（novelId为null）
        return presetRepository.findByUserIdAndNovelIdOrderByLastUsedAtDesc(userId, novelId);
    }

    @Override
    public Flux<AIPromptPreset> getUserPresetsByFeatureType(String userId, String featureType) {
        return presetRepository.findByUserIdAndAiFeatureType(userId, featureType);
    }

    @Override
    public Flux<AIPromptPreset> getUserPresetsByFeatureTypeAndNovelId(String userId, String featureType, String novelId) {
        return presetRepository.findByUserIdAndAiFeatureTypeAndNovelId(userId, featureType, novelId);
    }

    @Override
    public Flux<AIPromptPreset> getSystemPresets(String featureType) {
        if (featureType != null) {
            return presetRepository.findByIsSystemTrueAndAiFeatureType(featureType);
        } else {
            return presetRepository.findByIsSystemTrue();
        }
    }

    @Override
    public Flux<AIPromptPreset> getQuickAccessPresets(String userId, String featureType) {
        if (featureType != null) {
            return presetRepository.findQuickAccessPresetsByUserAndFeatureType(userId, featureType);
        } else {
            return presetRepository.findByUserIdAndShowInQuickAccessTrue(userId)
                    .concatWith(presetRepository.findByIsSystemTrueAndShowInQuickAccessTrue())
                    .distinct();
        }
    }

    @Override
    public Flux<AIPromptPreset> getFavoritePresets(String userId, String featureType, String novelId) {
        if (novelId != null) {
            return presetRepository.findByUserIdAndIsFavoriteTrueAndNovelId(userId, novelId)
                    .filter(preset -> featureType == null || featureType.equals(preset.getAiFeatureType()));
        } else {
            return presetRepository.findByUserIdAndIsFavoriteTrue(userId)
                    .filter(preset -> featureType == null || featureType.equals(preset.getAiFeatureType()));
        }
    }

    @Override
    public Flux<AIPromptPreset> getRecentPresets(String userId, int limit, String featureType, String novelId) {
        // 获取最近30天的预设
        LocalDateTime since = LocalDateTime.now().minusDays(30);
        return presetRepository.findRecentlyUsedPresets(userId, since)
                .filter(preset -> featureType == null || featureType.equals(preset.getAiFeatureType()))
                .filter(preset -> novelId == null || novelId.equals(preset.getNovelId()) || preset.getNovelId() == null)
                .sort((a, b) -> b.getLastUsedAt().compareTo(a.getLastUsedAt()))
                .take(limit);
    }

    @Override
    public Mono<Map<String, List<AIPromptPreset>>> getUserPresetsGrouped(String userId) {
        return getUserPresets(userId)
                .collectList()
                .map(presets -> presets.stream()
                        .collect(Collectors.groupingBy(AIPromptPreset::getAiFeatureType)));
    }

    @Override
    public Flux<AIPromptPreset> getPresetsBatch(List<String> presetIds) {
        // 批量查询：通过多个findByPresetId调用实现
        return Flux.fromIterable(presetIds)
                .flatMap(presetRepository::findByPresetId)
                .onErrorContinue((error, presetId) -> {
                    log.warn("获取预设失败，跳过: presetId={}, error={}", presetId, error.getMessage());
                });
    }

    @Override
    public Mono<com.ainovel.server.dto.response.PresetListResponse> getFeaturePresetList(String userId, String featureType, String novelId) {
        log.info("获取功能预设列表: userId={}, featureType={}, novelId={}", userId, featureType, novelId);


        
        // 并行获取三类预设
        Mono<List<AIPromptPreset>> favoritesMono = getFavoritePresets(userId, featureType, novelId)
                .take(5)
                .collectList();
                
        Mono<List<AIPromptPreset>> recentUsedMono = getRecentPresets(userId, 5, featureType, novelId)
                .collectList();
                
        // 获取最近创建的预设（用于推荐）
        Mono<List<AIPromptPreset>> recommendedMono = getUserPresetsByFeatureTypeAndNovelId(userId, featureType, novelId)
                .sort((a, b) -> b.getCreatedAt().compareTo(a.getCreatedAt()))
                .take(10)
                .collectList();

        return Mono.zip(favoritesMono, recentUsedMono, recommendedMono)
                .map(tuple -> {
                    List<AIPromptPreset> favorites = tuple.getT1();
                    List<AIPromptPreset> recentUsed = tuple.getT2();
                    List<AIPromptPreset> allRecommended = tuple.getT3();
                    
                    // 创建已使用预设的ID集合，避免重复
                    Set<String> usedPresetIds = new HashSet<>();
                    favorites.forEach(p -> usedPresetIds.add(p.getPresetId()));
                    recentUsed.forEach(p -> usedPresetIds.add(p.getPresetId()));
                    
                    // 计算需要补充的推荐预设数量
                    int totalNeeded = 10;
                    int currentCount = favorites.size() + recentUsed.size();
                    int recommendedNeeded = Math.max(0, totalNeeded - currentCount);
                    
                    // 过滤出未重复的推荐预设
                    List<AIPromptPreset> recommended = allRecommended.stream()
                            .filter(p -> !usedPresetIds.contains(p.getPresetId()))
                            .limit(recommendedNeeded)
                            .collect(Collectors.toList());

                    // 构建响应数据
                    List<com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag> favoriteItems = 
                            favorites.stream()
                                    .map(preset -> com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag.builder()
                                            .preset(preset)
                                            .isFavorite(true)
                                            .isRecentUsed(false)
                                            .isRecommended(false)
                                            .build())
                                    .collect(Collectors.toList());

                    List<com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag> recentUsedItems = 
                            recentUsed.stream()
                                    .map(preset -> com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag.builder()
                                            .preset(preset)
                                            .isFavorite(preset.getIsFavorite())
                                            .isRecentUsed(true)
                                            .isRecommended(false)
                                            .build())
                                    .collect(Collectors.toList());

                    List<com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag> recommendedItems = 
                            recommended.stream()
                                    .map(preset -> com.ainovel.server.dto.response.PresetListResponse.PresetItemWithTag.builder()
                                            .preset(preset)
                                            .isFavorite(preset.getIsFavorite())
                                            .isRecentUsed(false)
                                            .isRecommended(true)
                                            .build())
                                    .collect(Collectors.toList());

                    log.info("功能预设列表获取完成: 收藏{}个, 最近使用{}个, 推荐{}个", 
                            favoriteItems.size(), recentUsedItems.size(), recommendedItems.size());

                    return com.ainovel.server.dto.response.PresetListResponse.builder()
                            .favorites(favoriteItems)
                            .recentUsed(recentUsedItems)
                            .recommended(recommendedItems)
                            .build();
                })
                .onErrorMap(error -> {
                    log.error("获取功能预设列表失败: userId={}, featureType={}, error={}", userId, featureType, error.getMessage());
                    return new RuntimeException("获取功能预设列表失败: " + error.getMessage());
                });
    }

    @Override
    public Flux<AIPromptPreset> searchUserPresets(String userId, String keyword, List<String> tags, String featureType) {
        String kw = (keyword == null || keyword.isEmpty()) ? ".*" : keyword;
        return presetRepository.searchPresets(userId, kw, tags, featureType);
    }

    @Override
    public Flux<AIPromptPreset> searchUserPresetsByNovelId(String userId, String keyword, List<String> tags, String featureType, String novelId) {
        String kw = (keyword == null || keyword.isEmpty()) ? ".*" : keyword;
        return presetRepository.searchPresetsByNovelId(userId, kw, tags, featureType, novelId);
    }
} 