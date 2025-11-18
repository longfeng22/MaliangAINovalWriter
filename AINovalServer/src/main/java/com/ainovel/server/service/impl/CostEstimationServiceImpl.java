package com.ainovel.server.service.impl;

import com.ainovel.server.service.CostEstimationService;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.service.TokenEstimationService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.service.NovelSettingService;
import com.ainovel.server.service.impl.content.ContentProviderFactory;
import com.ainovel.server.service.impl.content.ContentProvider;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.domain.model.UserAIModelConfig;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;
import lombok.extern.slf4j.Slf4j;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 积分成本预估服务实现
 * 通过快速获取内容长度来预估AI请求的积分成本
 */
@Slf4j
@Service
public class CostEstimationServiceImpl implements CostEstimationService {

    @Autowired
    private CreditService creditService;

    @Autowired
    private PublicModelConfigService publicModelConfigService;

    @Autowired
    private UserAIModelConfigService userAIModelConfigService;

    @Autowired
    private TokenEstimationService tokenEstimationService;

    @Autowired
    private ContentProviderFactory contentProviderFactory;

    @Autowired
    private NovelService novelService;

    @Autowired
    private SceneService sceneService;

    @Autowired
    private NovelSettingService novelSettingService;

    @Override
    public Mono<CostEstimationResponse> estimateCost(UniversalAIRequestDto request) {
        log.info("开始预估积分成本 - 用户ID: {}, 请求类型: {}", request.getUserId(), request.getRequestType());

        // 从请求的 metadata 中获取模型信息
        String provider = extractProvider(request);
        String modelId = extractModelId(request);
        String modelConfigId = extractModelConfigId(request);
        Boolean isPublicModel = extractIsPublicModel(request);

        log.info("模型信息 - provider: {}, modelId: {}, configId: {}, isPublic: {}", 
                provider, modelId, modelConfigId, isPublicModel);

        // 公共模型：若缺 provider/modelId，则根据 configId 回填
        if ((provider == null || provider.isBlank()) || (modelId == null || modelId.isBlank())) {
            if (Boolean.TRUE.equals(isPublicModel) && modelConfigId != null && !modelConfigId.isBlank()) {
                return publicModelConfigService.findById(modelConfigId)
                        .flatMap(pub -> {
                            String p = pub.getProvider();
                            String m = pub.getModelId();
                            log.info("预估回填公共模型信息: provider={}, modelId={} (configId={})", p, m, modelConfigId);
                            return estimateForPublicModel(request, p, m);
                        })
                        .switchIfEmpty(Mono.just(new CostEstimationResponse(0L, false, "公共模型配置不存在: " + modelConfigId)));
            }
            log.warn("预估失败: 请求中缺少有效的模型信息");
            return Mono.just(new CostEstimationResponse(0L, false, "请求中必须包含有效的模型信息 (provider 和 modelId)"));
        }

        // 检查是否为公共模型
        if (isPublicModel != null && isPublicModel) {
            return estimateForPublicModel(request, provider, modelId);
        } else {
            return estimateForPrivateModel(request, provider, modelId, modelConfigId);
        }
    }

    @Override
    public Mono<CostEstimationResponse> estimateCostForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType) {
        log.info("基于AIRequest预估积分成本 - 用户: {}, 模型: {}:{}, 功能: {}", 
                aiRequest.getUserId(), publicModel.getProvider(), publicModel.getModelId(), featureType);

        // 检查模型是否启用
        if (!publicModel.getEnabled()) {
            return Mono.just(new CostEstimationResponse(0L, false, "该公共模型当前不可用"));
        }

        // 检查模型是否支持该功能
        if (!publicModel.isEnabledForFeature(featureType)) {
            return Mono.just(new CostEstimationResponse(0L, false, "该公共模型不支持当前功能: " + featureType));
        }

        // 直接基于AIRequest估算内容长度
        return estimateContentLengthFromAIRequest(aiRequest)
                .flatMap(totalLength -> {
                    log.info("估算的总内容长度: {} 字符", totalLength);

                    // 估算token数量
                    return tokenEstimationService.estimateTokensByWordCount(totalLength, publicModel.getModelId())
                            .flatMap(inputTokens -> {
                                // 估算输出token
                                int outputTokens = estimateOutputTokens(inputTokens.intValue(), featureType);
                                
                                log.info("估算tokens - 输入: {}, 输出: {}", inputTokens, outputTokens);

                                // 计算积分成本
                                return creditService.calculateCreditCost(publicModel.getProvider(), publicModel.getModelId(), 
                                        featureType, inputTokens.intValue(), outputTokens)
                                        .map(cost -> {
                                            log.info("公共模型 {}:{} 预估积分成本: {}", 
                                                    publicModel.getProvider(), publicModel.getModelId(), cost);
                                            
                                            CostEstimationResponse response = new CostEstimationResponse(cost, true);
                                            response.setEstimatedInputTokens(inputTokens.intValue());
                                            response.setEstimatedOutputTokens(outputTokens);
                                            response.setModelProvider(publicModel.getProvider());
                                            response.setModelId(publicModel.getModelId());
                                            response.setCreditMultiplier(publicModel.getCreditRateMultiplier());
                                            
                                            return response;
                                        })
                                        .onErrorResume(error -> {
                                            log.warn("积分计算失败: {}，使用默认值", error.getMessage());
                                            return Mono.just(new CostEstimationResponse(1L, true));
                                        });
                            })
                            .onErrorResume(error -> {
                                log.warn("Token估算失败: {}，使用默认值", error.getMessage());
                                return Mono.just(new CostEstimationResponse(1L, true));
                            });
                })
                .onErrorResume(error -> {
                    log.warn("内容长度估算失败: {}，返回失败结果", error.getMessage());
                    return Mono.just(new CostEstimationResponse(0L, false, error.getMessage()));
                });
    }

    /**
     * 基于AIRequest估算内容长度
     */
    private Mono<Integer> estimateContentLengthFromAIRequest(AIRequest aiRequest) {
        int baseLength = 0;
        
        // 计算提示词长度
        if (aiRequest.getPrompt() != null) {
            baseLength += aiRequest.getPrompt().length();
        }
        
        // 计算消息历史长度
        if (aiRequest.getMessages() != null) {
            for (AIRequest.Message message : aiRequest.getMessages()) {
                if (message.getContent() != null) {
                    baseLength += message.getContent().length();
                }
            }
        }
        
        // 如果有上下文相关的ID，估算额外的上下文长度
        String novelId = aiRequest.getNovelId();
        
        // 基础内容已有的长度
        int finalBaseLength = baseLength;
        
        // 如果启用了上下文，则需要估算上下文内容
        if (Boolean.TRUE.equals(aiRequest.getEnableContext()) && novelId != null) {
            // 估算小说相关上下文长度（简化估算）
            return Mono.just(finalBaseLength + 2000); // 假设平均上下文长度为2000字符
        }
        
        return Mono.just(Math.max(finalBaseLength, 100)); // 最小100字符
    }

    /**
     * 为公共模型预估积分成本
     */
    private Mono<CostEstimationResponse> estimateForPublicModel(UniversalAIRequestDto request, String provider, String modelId) {
        log.info("为公共模型预估积分成本: {}:{}", provider, modelId);

        // 验证公共模型是否存在
        return publicModelConfigService.findByProviderAndModelId(provider, modelId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("指定的公共模型不存在: " + provider + ":" + modelId)))
                .flatMap(publicModel -> {
                    log.info("找到公共模型配置: {}, 积分倍率: {}", publicModel.getDisplayName(), publicModel.getCreditRateMultiplier());

                    // 检查模型是否启用
                    if (!publicModel.getEnabled()) {
                        return Mono.just(new CostEstimationResponse(0L, false, "该公共模型当前不可用"));
                    }

                    // 映射AI功能类型
                    AIFeatureType featureType = mapRequestTypeToFeatureType(request.getRequestType());

                    // ✅ 优先使用前端传递的token预估值
                    Integer providedInputTokens = extractEstimatedInputTokens(request);
                    Integer providedOutputTokens = extractEstimatedOutputTokens(request);
                    
                    if (providedInputTokens != null && providedInputTokens > 0) {
                        // 使用前端提供的token值
                        int inputTokens = providedInputTokens;
                        int outputTokens = providedOutputTokens != null && providedOutputTokens > 0 
                                ? providedOutputTokens 
                                : estimateOutputTokens(inputTokens, featureType);
                        
                        log.info("使用前端提供的tokens - 输入: {}, 输出: {}", inputTokens, outputTokens);

                        // 计算积分成本
                        return creditService.calculateCreditCost(provider, modelId, featureType, inputTokens, outputTokens)
                                .map(cost -> {
                                    log.info("公共模型 {}:{} 预估积分成本: {}", provider, modelId, cost);
                                    
                                    CostEstimationResponse response = new CostEstimationResponse(cost, true);
                                    response.setEstimatedInputTokens(inputTokens);
                                    response.setEstimatedOutputTokens(outputTokens);
                                    response.setModelProvider(provider);
                                    response.setModelId(modelId);
                                    response.setCreditMultiplier(publicModel.getCreditRateMultiplier());
                                    
                                    return response;
                                })
                                // 🚀 如果没有定价信息，检查是否为免费模型
                                .onErrorResume(error -> {
                                    log.warn("公共模型 {}:{} 积分计算失败: {}，检查是否为免费模型", provider, modelId, error.getMessage());
                                    
                                    // 检查模型标签是否包含"免费"
                                    if (isFreeTierModel(publicModel)) {
                                        log.info("公共模型 {}:{} 标记为免费，使用默认1积分", provider, modelId);
                                        
                                        CostEstimationResponse response = new CostEstimationResponse(1L, true);
                                        response.setEstimatedInputTokens(inputTokens);
                                        response.setEstimatedOutputTokens(outputTokens);
                                        response.setModelProvider(provider);
                                        response.setModelId(modelId);
                                        response.setCreditMultiplier(1.0);
                                        
                                        return Mono.just(response);
                                    } else {
                                        // 不是免费模型，返回原错误
                                        return Mono.error(error);
                                    }
                                });
                    }

                    // ✅ 后端自己估算token
                    // 快速估算内容长度
                    return estimateContentLength(request)
                            .flatMap(totalLength -> {
                                log.info("估算的总内容长度: {} 字符", totalLength);

                                // 估算token数量
                                return tokenEstimationService.estimateTokensByWordCount(totalLength, modelId)
                                        .flatMap(inputTokens -> {
                                            // 估算输出token
                                            int outputTokens = estimateOutputTokens(inputTokens.intValue(), featureType);
                                            
                                            log.info("估算tokens - 输入: {}, 输出: {}", inputTokens, outputTokens);

                                            // 计算积分成本
                                            return creditService.calculateCreditCost(provider, modelId, featureType, inputTokens.intValue(), outputTokens)
                                                    .map(cost -> {
                                                        log.info("公共模型 {}:{} 预估积分成本: {}", provider, modelId, cost);
                                                        
                                                        CostEstimationResponse response = new CostEstimationResponse(cost, true);
                                                        response.setEstimatedInputTokens(inputTokens.intValue());
                                                        response.setEstimatedOutputTokens(outputTokens);
                                                        response.setModelProvider(provider);
                                                        response.setModelId(modelId);
                                                        response.setCreditMultiplier(publicModel.getCreditRateMultiplier());
                                                        
                                                        return response;
                                                    })
                                                    // 🚀 如果没有定价信息，检查是否为免费模型
                                                    .onErrorResume(error -> {
                                                        log.warn("公共模型 {}:{} 积分计算失败: {}，检查是否为免费模型", provider, modelId, error.getMessage());
                                                        
                                                        // 检查模型标签是否包含"免费"
                                                        if (isFreeTierModel(publicModel)) {
                                                            log.info("公共模型 {}:{} 标记为免费，使用默认1积分", provider, modelId);
                                                            
                                                            CostEstimationResponse response = new CostEstimationResponse(1L, true);
                                                            response.setEstimatedInputTokens(inputTokens.intValue());
                                                            response.setEstimatedOutputTokens(outputTokens);
                                                            response.setModelProvider(provider);
                                                            response.setModelId(modelId);
                                                            response.setCreditMultiplier(1.0);
                                                            
                                                            return Mono.just(response);
                                                        } else {
                                                            // 不是免费模型，返回原错误
                                                            return Mono.error(error);
                                                        }
                                                    });
                                        });
                            });
                })
                .onErrorResume(error -> {
                    log.error("公共模型积分预估失败: {}:{}, 错误: {}", provider, modelId, error.getMessage());
                    return Mono.just(new CostEstimationResponse(0L, false, "公共模型预估失败: " + error.getMessage()));
                });
    }

    /**
     * 为私有模型预估积分成本
     */
    private Mono<CostEstimationResponse> estimateForPrivateModel(UniversalAIRequestDto request, String provider, String modelId, String modelConfigId) {
        log.info("为私有模型预估积分成本: {}:{}, configId: {}", provider, modelId, modelConfigId);

        // 私有模型不需要积分，返回0成本
        return estimateContentLength(request)
                .flatMap(totalLength -> {
                    log.info("私有模型估算的总内容长度: {} 字符", totalLength);

                    // 仍然估算token数量用于显示
                    return tokenEstimationService.estimateTokensByWordCount(totalLength, modelId)
                            .map(inputTokens -> {
                                AIFeatureType featureType = mapRequestTypeToFeatureType(request.getRequestType());
                                int outputTokens = estimateOutputTokens(inputTokens.intValue(), featureType);
                                
                                log.info("私有模型估算tokens - 输入: {}, 输出: {} (无积分成本)", inputTokens, outputTokens);

                                CostEstimationResponse response = new CostEstimationResponse(0L, true);
                                response.setEstimatedInputTokens(inputTokens.intValue());
                                response.setEstimatedOutputTokens(outputTokens);
                                response.setModelProvider(provider);
                                response.setModelId(modelId);
                                response.setCreditMultiplier(1.0); // 私有模型无倍率
                                
                                return response;
                            });
                })
                .onErrorResume(error -> {
                    log.error("私有模型积分预估失败: {}:{}, 错误: {}", provider, modelId, error.getMessage());
                    return Mono.just(new CostEstimationResponse(0L, false, "私有模型预估失败: " + error.getMessage()));
                });
    }

    /**
     * 快速估算内容总长度
     */
    private Mono<Integer> estimateContentLength(UniversalAIRequestDto request) {
        List<Mono<Integer>> lengthSources = new ArrayList<>();

        // 添加用户直接输入的内容长度
        int directInputLength = 0;
        if (request.getPrompt() != null && !request.getPrompt().trim().isEmpty()) {
            directInputLength += request.getPrompt().length();
        }
        if (request.getSelectedText() != null && !request.getSelectedText().trim().isEmpty()) {
            directInputLength += request.getSelectedText().length();
        }
        if (request.getInstructions() != null && !request.getInstructions().trim().isEmpty()) {
            directInputLength += request.getInstructions().length();
        }

        final int finalDirectInputLength = directInputLength;
        log.debug("直接输入内容长度: {} 字符", finalDirectInputLength);

        // 处理上下文选择
        if (request.getContextSelections() != null && !request.getContextSelections().isEmpty()) {
            log.info("处理上下文选择内容长度估算，数量: {}", request.getContextSelections().size());
            
            for (UniversalAIRequestDto.ContextSelectionDto selection : request.getContextSelections()) {
                String type = selection.getType();
                String id = selection.getId();
                
                if (type != null && id != null) {
                    lengthSources.add(getEstimatedLengthFromProvider(type.toLowerCase(), id, request));
                }
            }
        }

        // 添加智能检索内容的估算长度
        Boolean enableSmartContext = (Boolean) request.getMetadata().get("enableSmartContext");
        if (enableSmartContext != null && enableSmartContext && request.getNovelId() != null) {
            lengthSources.add(estimateSmartContextLength(request));
        }

        // 合并所有长度
        if (lengthSources.isEmpty()) {
            return Mono.just(finalDirectInputLength);
        }

        return Flux.merge(lengthSources)
                .collectList()
                .map(lengths -> {
                    int totalLength = finalDirectInputLength;
                    for (Integer length : lengths) {
                        totalLength += length != null ? length : 0;
                    }
                    log.info("总估算内容长度: {} 字符 (直接输入: {}, 上下文: {})", 
                             totalLength, finalDirectInputLength, totalLength - finalDirectInputLength);
                    return totalLength;
                });
    }

    /**
     * 通过ContentProvider快速获取内容长度估算
     */
    private Mono<Integer> getEstimatedLengthFromProvider(String type, String id, UniversalAIRequestDto request) {
        Optional<ContentProvider> providerOptional = contentProviderFactory.getProvider(type);
        
        if (providerOptional.isPresent()) {
            ContentProvider provider = providerOptional.get();
            
            // 构建上下文参数
            Map<String, Object> contextParameters = new HashMap<>();
            contextParameters.put("userId", request.getUserId());
            contextParameters.put("novelId", request.getNovelId());
            
            // 根据类型添加特定参数
            if ("scene".equals(type)) {
                contextParameters.put("sceneId", extractIdFromContextId(id));
            } else if ("chapter".equals(type)) {
                contextParameters.put("chapterId", extractIdFromContextId(id));
            } else if (Arrays.asList("character", "location", "item", "lore").contains(type)) {
                contextParameters.put("settingId", extractIdFromContextId(id));
            } else if ("snippet".equals(type)) {
                contextParameters.put("snippetId", extractIdFromContextId(id));
            }
            
            // 调用快速长度估算方法
            return provider.getEstimatedContentLength(contextParameters)
                    .doOnSuccess(length -> log.debug("Provider {} 返回长度估算: {} 字符", type, length))
                    .onErrorReturn(0);
        } else {
            log.warn("未找到类型为 {} 的ContentProvider", type);
            return Mono.just(0);
        }
    }

    /**
     * 估算智能上下文内容长度
     */
    private Mono<Integer> estimateSmartContextLength(UniversalAIRequestDto request) {
        // 简单估算：智能上下文通常包含少量相关设定和场景信息
        // 这里可以根据实际RAG检索的平均长度来调整
        return Mono.just(500); // 估算500字符的智能上下文内容
    }

    /**
     * 估算输出token数量
     * 改为基于实际输出长度的固定估算，而非输入token的倍数
     */
    private int estimateOutputTokens(int inputTokens, AIFeatureType featureType) {
        return switch (featureType) {
            case TEXT_EXPANSION, TEXT_REFACTOR ->
                // 重构输出长度通常与输入相近，但略有增加
                    Math.min(inputTokens + 1000, 5000);
            case TEXT_SUMMARY, SCENE_TO_SUMMARY->
                // 总结通常输出200-800字，按500字估算 ≈ 650 tokens
                    650;
            case NOVEL_GENERATION, SUMMARY_TO_SCENE->
                // 小说生成通常输出2000-4000字，按3000字估算 ≈ 3900 tokens
                    3900;
            case AI_CHAT ->
                // 聊天通常输出100-1000字，按500字估算 ≈ 650 tokens
                    650;
            default ->
                // 默认估算1000字 ≈ 1300 tokens
                    1300;
        };
    }

    /**
     * 映射请求类型到AI功能类型
     */
    private AIFeatureType mapRequestTypeToFeatureType(String requestType) {
        if (requestType == null) {
            return AIFeatureType.AI_CHAT;
        }
        return AIFeatureType.valueOf(requestType);

    }

    /**
     * 从请求中提取Provider
     */
    private String extractProvider(UniversalAIRequestDto request) {
        // ✅ 优先从DTO顶层字段读取
        if (request.getModelProvider() != null && !request.getModelProvider().isBlank()) {
            return request.getModelProvider();
        }
        // 兼容：从metadata中读取
        if (request.getMetadata() != null) {
            Object provider = request.getMetadata().get("modelProvider");
            if (provider instanceof String) {
                return (String) provider;
            }
        }
        return null;
    }

    /**
     * 从请求中提取ModelId
     */
    private String extractModelId(UniversalAIRequestDto request) {
        // ✅ 优先从DTO顶层字段读取
        if (request.getModelName() != null && !request.getModelName().isBlank()) {
            return request.getModelName();
        }
        // 兼容：从metadata中读取
        if (request.getMetadata() != null) {
            Object modelId = request.getMetadata().get("modelName");
            if (modelId instanceof String) {
                return (String) modelId;
            }
        }
        return null;
    }

    /**
     * 从请求中提取前端预估的输入token数
     */
    private Integer extractEstimatedInputTokens(UniversalAIRequestDto request) {
        if (request.getParameters() != null) {
            Object value = request.getParameters().get("estimatedInputTokens");
            if (value instanceof Integer) {
                return (Integer) value;
            } else if (value instanceof Number) {
                return ((Number) value).intValue();
            }
        }
        return null;
    }

    /**
     * 从请求中提取前端预估的输出token数
     */
    private Integer extractEstimatedOutputTokens(UniversalAIRequestDto request) {
        if (request.getParameters() != null) {
            Object value = request.getParameters().get("estimatedOutputTokens");
            if (value instanceof Integer) {
                return (Integer) value;
            } else if (value instanceof Number) {
                return ((Number) value).intValue();
            }
        }
        return null;
    }

    /**
     * 从请求中提取ModelConfigId
     */
    private String extractModelConfigId(UniversalAIRequestDto request) {
        if (request.getMetadata() != null) {
            Object configId = request.getMetadata().get("modelConfigId");
            if (configId instanceof String) {
                return (String) configId;
            }
        }
        return request.getModelConfigId();
    }

    /**
     * 从请求中提取是否为公共模型标识
     */
    private Boolean extractIsPublicModel(UniversalAIRequestDto request) {
        if (request.getMetadata() != null) {
            Object isPublic = request.getMetadata().get("isPublicModel");
            if (isPublic instanceof Boolean) {
                return (Boolean) isPublic;
            }
        }
        return null;
    }

    /**
     * 从上下文ID中提取实际ID
     */
    private String extractIdFromContextId(String contextId) {
        if (contextId == null || contextId.isEmpty()) {
            return null;
        }
        
        // 处理格式如：scene_xxx, chapter_xxx等
        int underscoreIndex = contextId.indexOf("_");
        if (underscoreIndex >= 0 && underscoreIndex + 1 < contextId.length()) {
            return contextId.substring(underscoreIndex + 1);
        }
        
        return contextId;
    }

    /**
     * 🚀 新增：检查公共模型是否为免费层级
     * 通过检查模型标签判断是否为免费模型
     */
    private boolean isFreeTierModel(PublicModelConfig publicModel) {
        if (publicModel.getTags() == null || publicModel.getTags().isEmpty()) {
            return false;
        }
        
        List<String> tags = publicModel.getTags();
        
        // 检查标签列表中是否包含免费相关的标签
        for (String tag : tags) {
            if (tag != null) {
                String lowercaseTag = tag.toLowerCase().trim();
                if (lowercaseTag.equals("免费") || 
                    lowercaseTag.equals("free") || 
                    lowercaseTag.equals("免费层级") || 
                    lowercaseTag.equals("free tier") ||
                    lowercaseTag.equals("无费用") ||
                    lowercaseTag.equals("no cost")) {
                    log.info("发现免费标签: {}", tag);
                    return true;
                }
            }
        }
        
        return false;
    }
} 