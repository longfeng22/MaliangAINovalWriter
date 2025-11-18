package com.ainovel.server.service.impl;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

import org.apache.commons.lang3.StringUtils;
import com.ainovel.server.service.ai.tools.fallback.ToolFallbackRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIRequest.Message.MessageBuilder;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.domain.model.ModelListingCapability;
import com.ainovel.server.service.AIProviderRegistryService;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.service.ai.capability.ToolCallCapable;
import com.ainovel.server.service.ai.tools.ToolExecutionService;
import com.ainovel.server.service.ai.factory.AIModelProviderFactory;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.ai.observability.TraceContextManager;
import org.springframework.context.ApplicationEventPublisher;
import org.jasypt.encryption.StringEncryptor;
import com.ainovel.server.service.ai.capability.ProviderCapabilityService;
import com.ainovel.server.service.ai.capability.ProviderCapabilityDetector;


import dev.langchain4j.agent.tool.ToolSpecification;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.ToolExecutionResultMessage;
import dev.langchain4j.model.chat.ChatLanguageModel;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.response.ChatResponse;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 基础AI服务实现 负责AI模型的基础功能和系统级信息，不包含用户特定配置。
 */
@Slf4j
@Service
public class AIServiceImpl implements AIService {

    // 是否使用LangChain4j实现（保留配置入口）
    @SuppressWarnings("unused")
    private boolean useLangChain4j = true;
    @Autowired
    @SuppressWarnings("unused")
    private ProxyConfig proxyConfig;

    // 模型分组信息
    private final Map<String, List<String>> modelGroups = new HashMap<>();
    @SuppressWarnings("unused")
    private final NovelService novelService;
    private final AIProviderRegistryService providerRegistryService;

    private final AIModelProviderFactory providerFactory;
    // 直接注入所需 Bean，避免在运行时从 ApplicationContext 动态查找
    @Autowired(required = false)
    private ApplicationEventPublisher eventPublisher;
    @Autowired(required = false)
    private TraceContextManager traceContextManager;
    @Autowired
    private UserAIModelConfigService userAIModelConfigService;
    @Autowired
    private PublicModelConfigService publicModelConfigService;
    @Autowired
    private CreditService creditService;
    @Autowired
    private StringEncryptor encryptor;
    private final ProviderCapabilityService capabilityService;
    private final ToolExecutionService toolExecutionService;
    private final ToolFallbackRegistry toolFallbackRegistry;
    private final ObjectMapper objectMapper;
    private final List<ProviderCapabilityDetector> capabilityDetectors;

    @Autowired
    public AIServiceImpl(
            NovelService novelService,
            AIProviderRegistryService providerRegistryService,
            AIModelProviderFactory providerFactory,
            ProviderCapabilityService capabilityService,
            ToolExecutionService toolExecutionService,
            ToolFallbackRegistry toolFallbackRegistry,
            ObjectMapper objectMapper,
            List<ProviderCapabilityDetector> capabilityDetectors) {
        this.novelService = novelService;
        this.providerRegistryService = providerRegistryService;
        this.providerFactory = providerFactory;
        this.capabilityService = capabilityService;
        this.toolExecutionService = toolExecutionService;
        this.toolFallbackRegistry = toolFallbackRegistry;
        this.objectMapper = objectMapper;
        this.capabilityDetectors = capabilityDetectors;
        initializeModelGroups();
    }

    /**
     * 动态初始化模型分组信息 - 从CapabilityDetector获取最新模型列表
     */
    private void initializeModelGroups() {
        log.info("开始动态初始化模型分组，共找到 {} 个CapabilityDetector", capabilityDetectors.size());
        
        for (ProviderCapabilityDetector detector : capabilityDetectors) {
            String providerName = detector.getProviderName();
            try {
                List<String> modelIds = detector.getDefaultModels()
                        .map(ModelInfo::getId)
                        .collectList()
                        .block(); // 由于是启动时初始化，可以使用阻塞调用
                
                if (modelIds != null && !modelIds.isEmpty()) {
                    modelGroups.put(providerName, modelIds);
                    log.info("为提供商 '{}' 加载了 {} 个模型: {}", providerName, modelIds.size(), 
                            modelIds.size() > 5 ? modelIds.subList(0, 5) + "..." : modelIds);
                } else {
                    log.warn("提供商 '{}' 没有返回任何默认模型", providerName);
                }
            } catch (Exception e) {
                log.error("无法从CapabilityDetector获取提供商 '{}' 的模型列表: {}", providerName, e.getMessage(), e);
                // 添加基本的后备模型，避免完全失败
                addFallbackModels(providerName);
            }
        }
        
        log.info("模型分组初始化完成，共支持 {} 个提供商: {}", modelGroups.size(), modelGroups.keySet());
    }
    
    /**
     * 为特定提供商添加后备模型
     */
    private void addFallbackModels(String providerName) {
        switch (providerName.toLowerCase()) {
            case "openai" -> modelGroups.put(providerName, List.of("gpt-3.5-turbo", "gpt-4", "gpt-4o"));
            case "anthropic" -> modelGroups.put(providerName, List.of("claude-3-opus", "claude-3-sonnet", "claude-3-haiku"));
            case "gemini" -> modelGroups.put(providerName, List.of("gemini-2.5-flash", "gemini-2.5-pro"));
            case "zhipu" -> modelGroups.put(providerName, List.of("glm-4", "glm-4-flash"));
            case "doubao" -> modelGroups.put(providerName, List.of("ep-2025-01-ark"));
            case "qwen" -> modelGroups.put(providerName, List.of("qwen-plus", "qwen-turbo"));
            case "siliconflow" -> modelGroups.put(providerName, List.of("deepseek-ai/DeepSeek-V3"));
            case "x-ai", "grok" -> modelGroups.put(providerName, List.of("x-ai/grok-3"));
            case "togetherai" -> modelGroups.put(providerName, List.of("meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"));
            case "openrouter" -> modelGroups.put(providerName, List.of("openai/gpt-4o"));
            default -> {
                log.warn("未知提供商 '{}' 没有后备模型配置", providerName);
                modelGroups.put(providerName, List.of("default-model"));
            }
        }
        log.info("为提供商 '{}' 使用后备模型配置", providerName);
    }

    @Override
    public Mono<AIResponse> generateContent(AIRequest request, String apiKey, String apiEndpoint) {
        if (!StringUtils.isNotBlank(apiKey)) {
            return Mono.error(new IllegalArgumentException("API密钥不能为空"));
        }
        String providerName = getProviderForModel(request.getModel());
        AIModelProvider provider = providerFactory.createProvider(providerName, request.getModel(), apiKey, apiEndpoint);
        provider = wrapWithBilling(provider);

        if (provider == null) {
            return Mono.error(new IllegalArgumentException("无法为模型创建提供商: " + request.getModel()));
        }

        return provider.generateContent(request);
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request, String apiKey, String apiEndpoint) {
        if (!StringUtils.isNotBlank(apiKey)) {
            return Flux.error(new IllegalArgumentException("API密钥不能为空"));
        }
        String providerName = getProviderForModel(request.getModel());

        // 将Provider创建与底层调用延迟到订阅时执行，避免装配阶段的副作用
        return reactor.core.publisher.Flux.defer(() -> {
            AIModelProvider provider = providerFactory.createProvider(providerName, request.getModel(), apiKey, apiEndpoint);
            provider = wrapWithBilling(provider);

            if (provider == null) {
                return Flux.error(new IllegalArgumentException("无法为模型创建提供商: " + request.getModel()));
            }

            return provider.generateContentStream(request)
                    // 统一过滤掉内部 keep-alive 消息，后续由各控制器自行发送 SSE 心跳
                    .filter(chunk -> chunk != null && !"heartbeat".equalsIgnoreCase(chunk));
        });
    }

    @Override
    public Flux<String> getAvailableModels() {
        return Flux.fromIterable(modelGroups.values())
                .flatMap(Flux::fromIterable);
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request, String apiKey, String apiEndpoint) {
        if (!StringUtils.isNotBlank(apiKey)) {
            return Mono.error(new IllegalArgumentException("API密钥不能为空"));
        }
        String providerName = getProviderForModel(request.getModel());
        AIModelProvider provider = providerFactory.createProvider(providerName, request.getModel(), apiKey, apiEndpoint);
        provider = wrapWithBilling(provider);

        if (provider == null) {
            return Mono.error(new IllegalArgumentException("无法为模型创建提供商: " + request.getModel()));
        }

        return provider.estimateCost(request);
    }



    @Override
    public void setUseLangChain4j(boolean useLangChain4j) {
        log.info("设置 useLangChain4j = {}", useLangChain4j);
        this.useLangChain4j = useLangChain4j;
    }

    @Override
    @Deprecated
    public String getProviderForModel(String modelName) {
        if (!StringUtils.isNotBlank(modelName)) {
            throw new IllegalArgumentException("模型名称不能为空");
        }
        for (Map.Entry<String, List<String>> entry : modelGroups.entrySet()) {
            if (entry.getValue().stream().anyMatch(model -> model.equalsIgnoreCase(modelName))) {
                return entry.getKey();
            }
        }
        log.warn("未找到模型 '{}' 对应的提供商", modelName);
        throw new IllegalArgumentException("未知的或系统不支持的模型: " + modelName);
    }

    @Override
    public Flux<String> getModelsForProvider(String provider) {
        if (!StringUtils.isNotBlank(provider)) {
            return Flux.error(new IllegalArgumentException("提供商名称不能为空"));
        }
        List<String> models = modelGroups.get(provider.toLowerCase());
        if (models == null) {
            log.warn("请求未知的提供商 '{}' 的模型名称列表", provider);
            // 即使未知，也返回空列表，避免前端报错
            return Flux.empty();
            // return Flux.error(new IllegalArgumentException("未知的提供商: " + provider));
        }
        return Flux.fromIterable(models);
    }

    @Override
    public Flux<String> getAvailableProviders() {
        return Flux.fromIterable(modelGroups.keySet());
    }

    @Override
    public Map<String, List<String>> getModelGroups() {
        return new HashMap<>(modelGroups);
    }

    @Override
    public Flux<ModelInfo> getModelInfosForProvider(String provider) {
        if (!StringUtils.isNotBlank(provider)) {
            return Flux.error(new IllegalArgumentException("提供商名称不能为空"));
        }
        String lowerCaseProvider = provider.toLowerCase();

        // 1. 获取提供商能力
        return providerRegistryService.getProviderListingCapability(lowerCaseProvider)
                .flatMapMany(capability -> {
                    log.info("提供商 '{}' 的能力是: {}", lowerCaseProvider, capability);
                    // 2. 根据能力决定行为
                    if (capability == ModelListingCapability.LISTING_WITHOUT_KEY /* || capability == ModelListingCapability.LISTING_WITH_OR_WITHOUT_KEY */ ) {
                        log.info("提供商 '{}' 支持无密钥列出模型，尝试调用实际 provider", lowerCaseProvider);
                        // 尝试获取实际的 Provider 实例并调用 listModels()
                        // 注意：createAIModelProvider 可能需要 modelName 和 apiKey，这里需要调整
                        // 简化处理：假设 createAIModelProvider 能处理 dummy key，或者有其他方式获取实例
                        try {
                            // 获取默认端点（当前未直接使用，保留便于后续扩展）
                            @SuppressWarnings("unused")
                            String defaultEndpoint = capabilityService.getDefaultApiEndpoint(lowerCaseProvider);
                            
                            // 获取默认模型ID用于创建临时提供商实例
                            return capabilityService.getDefaultModels(lowerCaseProvider)
                                .switchIfEmpty(Mono.error(new RuntimeException("未找到提供商 " + lowerCaseProvider + " 的默认模型")))
                                .take(1)  // 只取第一个模型，用于创建临时实例
                                .flatMap(firstModel -> {
                                    // 创建临时提供商实例用于获取模型列表
                                    AIModelProvider providerInstance = providerFactory.createProvider(
                                            lowerCaseProvider,
                                            firstModel.getId(),
                                            "dummy-key-for-listing",
                                            null // 使用默认端点
                                    );
                                    
                                    if (providerInstance != null) {
                                        return providerInstance.listModels()
                                                .doOnError(e -> log.error("调用提供商 '{}' 的 listModels 失败，将回退到默认列表", lowerCaseProvider, e))
                                                .onErrorResume(e -> getDefaultModelInfos(lowerCaseProvider)); // 出错时回退
                                    } else {
                                        log.warn("无法创建提供商 '{}' 的实例，将回退到默认列表", lowerCaseProvider);
                                        return getDefaultModelInfos(lowerCaseProvider);
                                    }
                                });
                        } catch (Exception e) {
                            log.error("尝试为提供商 '{}' 获取实际模型列表时出错，将回退到默认列表", lowerCaseProvider, e);
                            return getDefaultModelInfos(lowerCaseProvider);
                        }
                    } else {
                        // 能力为 NO_LISTING 或 LISTING_WITH_KEY，返回默认模型信息
                        log.info("提供商 '{}' 能力为 {}，返回默认模型列表", lowerCaseProvider, capability);
                        return getDefaultModelInfos(lowerCaseProvider);
                    }
                })
                .switchIfEmpty(Flux.defer(() -> {
                    // 如果获取能力失败或提供商未知，也返回默认列表
                    log.warn("无法获取提供商 '{}' 的能力或提供商未知，返回默认模型列表", lowerCaseProvider);
                    return getDefaultModelInfos(lowerCaseProvider);
                }));
    }

    // 辅助方法：获取默认模型信息
    private Flux<ModelInfo> getDefaultModelInfos(String lowerCaseProvider) {
        List<String> modelNames = modelGroups.get(lowerCaseProvider);
        if (modelNames == null || modelNames.isEmpty()) {
            log.warn("无法找到提供商 '{}' 的默认模型名称列表", lowerCaseProvider);
            return Flux.empty(); // 如果连默认的都没有，返回空
        }

        List<ModelInfo> models = new ArrayList<>();
        for (String modelName : modelNames) {
            // 创建基础的 ModelInfo 对象
            models.add(ModelInfo.basic(modelName, modelName, lowerCaseProvider)
                    .withDescription(lowerCaseProvider + "的" + modelName + "模型")
                    .withMaxTokens(8192) // 使用合理的默认值
                    .withUnifiedPrice(0.001)); // 使用合理的默认值
        }
        log.info("为提供商 '{}' 返回了 {} 个默认模型信息", lowerCaseProvider, models.size());
        return Flux.fromIterable(models);
    }

    @Override
    public Flux<ModelInfo> getModelInfosForProviderWithApiKey(String provider, String apiKey, String apiEndpoint) {
        if (!StringUtils.isNotBlank(provider)) {
            return Flux.error(new IllegalArgumentException("提供商名称不能为空"));
        }

        if (!StringUtils.isNotBlank(apiKey)) {
            return Flux.error(new IllegalArgumentException("API密钥不能为空"));
        }

        String lowerCaseProvider = provider.toLowerCase();
        
        // 检查提供商是否已知 (通过modelGroups)
        if (!modelGroups.containsKey(lowerCaseProvider)) {
            log.warn("请求未知的提供商 '{}'", provider);
            return Flux.error(new IllegalArgumentException("未知的提供商: " + provider));
        }

        // 尝试获取该提供商的默认模型ID，用于创建Provider实例
        return capabilityService.getDefaultModels(lowerCaseProvider)
            .take(1) // 只取第一个默认模型
            .switchIfEmpty(Flux.<ModelInfo>defer(() -> {
                // 如果capabilityService没有默认模型，尝试从modelGroups获取第一个作为后备
                List<String> modelsFromGroup = modelGroups.get(lowerCaseProvider);
                if (modelsFromGroup != null && !modelsFromGroup.isEmpty()) {
                    log.info("使用modelGroups中的第一个模型: {} 作为默认模型", modelsFromGroup.get(0));
                    return Flux.just(ModelInfo.basic(modelsFromGroup.get(0), modelsFromGroup.get(0), lowerCaseProvider));
                } else {
                    log.error("无法为提供商 '{}' 找到任何模型", lowerCaseProvider);
                    return Flux.error(new RuntimeException("无法为提供商 " + lowerCaseProvider + " 找到任何模型"));
                }
            }))
            .flatMap(defaultModel -> {
                try {
                    log.info("为提供商 '{}' 创建Provider实例，使用模型 '{}'", lowerCaseProvider, defaultModel.getId());
                    
                    // 创建Provider实例
                    AIModelProvider providerInstance = providerFactory.createProvider(
                        lowerCaseProvider,
                        defaultModel.getId(),
                        apiKey,
                        apiEndpoint
                    );
                    
                    if (providerInstance != null) {
                        log.info("成功创建Provider实例，调用listModelsWithApiKey获取模型列表");
                        // 调用实例的listModelsWithApiKey方法
                        return providerInstance.listModelsWithApiKey(apiKey, apiEndpoint)
                            .collectList()
                            .flatMapMany(models -> {
                                log.info("使用API密钥获取提供商 '{}' 的模型信息列表成功: count={}", lowerCaseProvider, models.size());
                                return Flux.fromIterable(models);
                            })
                            .onErrorResume(e -> {
                                log.error("调用提供商 '{}' 的listModelsWithApiKey失败: {}", lowerCaseProvider, e.getMessage(), e);
                                return Flux.error(new RuntimeException("获取模型列表失败: " + e.getMessage()));
                            });
                    } else {
                        log.error("无法创建提供商 '{}' 的Provider实例", lowerCaseProvider);
                        return Mono.error(new RuntimeException("无法创建提供商实例: " + lowerCaseProvider));
                    }
                } catch (Exception e) {
                    log.error("为提供商 '{}' 创建Provider实例或获取模型时出错: {}", lowerCaseProvider, e.getMessage(), e);
                    return Mono.error(new RuntimeException("获取模型列表时发生内部错误: " + e.getMessage()));
                }
            });
    }

    // 已删除旧直连入口，请使用 createProviderByConfigId

    @Override
    public AIModelProvider createProviderByConfigId(String userId, String configId) {
        try {
            // 优先用户私有配置
            com.ainovel.server.domain.model.UserAIModelConfig userCfg = userAIModelConfigService
                    .getConfigurationById(userId, configId)
                    .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic())
                    .blockOptional()
                    .orElse(null);
            if (userCfg != null && Boolean.TRUE.equals(userCfg.getIsValidated())) {
                String apiKey = null;
                try {
                    apiKey = encryptor.decrypt(userCfg.getApiKey());
                } catch (Exception ignore) {}
                AIModelProvider provider = providerFactory.createProvider(userCfg.getProvider(), userCfg.getModelName(), apiKey, userCfg.getApiEndpoint());
                return wrapWithBilling(provider);
            }
            log.info("尝试使用公共模型解析 :{} ", configId);

            // 回退公共配置
            com.ainovel.server.domain.model.PublicModelConfig pub = publicModelConfigService
                    .findById(configId)
                    .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic())
                    .blockOptional()
                    .orElse(null);
            if (pub != null && Boolean.TRUE.equals(pub.getEnabled())) {
                String apiKey = publicModelConfigService
                        .getActiveDecryptedApiKey(pub.getProvider(), pub.getModelId())
                        .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic())
                        .block();
                AIModelProvider provider = providerFactory.createProvider(pub.getProvider(), pub.getModelId(), apiKey, pub.getApiEndpoint());
                return wrapWithBilling(provider);
            }
        } catch (Exception e) {
            log.error("createProviderByConfigId failed: userId={}, configId={}, err={}", userId, configId, e.getMessage());
        }
        throw new IllegalArgumentException("无法根据配置ID创建Provider: " + configId);
    }

    private AIModelProvider wrapWithBilling(AIModelProvider base) {
        try {
            // 优先构建内层（Tracing），再由外层（Billing）包裹，确保：先预扣费 -> 再创建/发布 Trace
            AIModelProvider inner = base;
            if (eventPublisher != null && traceContextManager != null) {
                boolean isLangChain4j = base.getClass().getName().toLowerCase().contains("langchain4j");
                inner = new com.ainovel.server.service.ai.TracingAIModelProviderDecorator(base, eventPublisher, traceContextManager, isLangChain4j);
            } else {
                if (eventPublisher == null) {
                    log.warn("Tracing disabled: ApplicationEventPublisher not injected.");
                }
                if (traceContextManager == null) {
                    log.warn("Tracing disabled: TraceContextManager not injected.");
                }
            }
            return new com.ainovel.server.service.ai.BillingAIModelProviderDecorator(inner, creditService, publicModelConfigService);
        } catch (Throwable e) {
            log.warn("wrapWithBilling failed, fallback to base provider: {}", e.getMessage(), e);
            return base;
        }
    }


    // ==================== LangChain4j 格式转换适配器 ====================
    
    /**
     * LangChain4j到AIRequest的适配器
     * 遵循适配器模式，将LangChain4j格式转换为统一的AIRequest格式
     */
    @Value("${ai.model.max-tokens:8192}")
    private int defaultMaxTokens;

    private AIRequest convertLangChain4jToAIRequest(
            List<ChatMessage> messages,
            List<ToolSpecification> toolSpecifications,
            String modelName,
            Map<String, String> config) {
        
        AIRequest.AIRequestBuilder builder = AIRequest.builder()
                .model(modelName)
                .maxTokens(defaultMaxTokens) // Use configured default value
                .temperature(0.7); // Default value, can be overridden by config

        // 转换消息列表
        List<AIRequest.Message> aiMessages = new ArrayList<>();
        for (ChatMessage message : messages) {
            AIRequest.Message aiMessage = convertLangChain4jMessageToAIRequestMessage(message);
            if (aiMessage != null) {
                aiMessages.add(aiMessage);
            }
        }
        builder.messages(aiMessages);

        // 🚀 直接设置工具规范到专门字段，避免在metadata中传递
        if (toolSpecifications != null && !toolSpecifications.isEmpty()) {
            builder.toolSpecifications(new ArrayList<>(toolSpecifications));
            log.debug("设置工具规范到AIRequest专门字段，工具数量: {}", toolSpecifications.size());
        }
        
        // 添加配置信息同时到元数据与parameters，便于Trace监听读取
        Map<String, Object> extra = new HashMap<>();
        if (config != null) {
            extra.putAll(config);
        }
        builder.metadata(extra);
        builder.parameters(extra);

        // 从配置推断 featureType 与 traceId（若存在）
        try {
            String reqType = config != null ? config.get("requestType") : null;
            if (reqType != null && !reqType.isBlank()) {
                try {
                    builder.featureType(com.ainovel.server.domain.model.AIFeatureType.valueOf(reqType));
                } catch (Exception ignore) {}
            }
            String idemKey = null;
            if (config != null) {
                idemKey = config.get(com.ainovel.server.service.billing.BillingKeys.REQUEST_IDEMPOTENCY_KEY);
            }
            if (idemKey != null && !idemKey.isBlank()) {
                builder.traceId(idemKey);
            }
        } catch (Exception ignore) {}
        // 关键：从配置中透传 userId / sessionId 到 AIRequest，供 LLMTrace 正确记录
        if (config != null) {
            String uid = config.get("userId");
            if (uid != null && !uid.isEmpty()) {
                builder.userId(uid);
            }
            String sid = config.get("sessionId");
            if (sid != null && !sid.isEmpty()) {
                builder.sessionId(sid);
            }
        }
        
        AIRequest built = builder.build();
        // 统一公共模型计费标记注入（工具编排路径会走到这里）
        try {
            com.ainovel.server.service.billing.PublicModelBillingNormalizer.normalize(built, config);
        } catch (Exception ignore) {}
        return built;
    }

    /**
     * 转换单个LangChain4j消息到AIRequest.Message
     * 遵循单一职责原则
     */
    private AIRequest.Message convertLangChain4jMessageToAIRequestMessage(ChatMessage message) {
        if (message == null) {
            return null;
        }

        MessageBuilder builder = AIRequest.Message.builder();

        // 根据消息类型进行转换
        if (message instanceof SystemMessage systemMessage) {
            builder.role("system").content(systemMessage.text());
        } else if (message instanceof dev.langchain4j.data.message.UserMessage userMessage) {
            builder.role("user").content(userMessage.singleText());
        } else if (message instanceof dev.langchain4j.data.message.AiMessage aiMessage) {
            builder.role("assistant").content(aiMessage.text());
            
            // 转换工具调用请求
            if (aiMessage.hasToolExecutionRequests()) {
                List<AIRequest.ToolExecutionRequest> toolRequests = 
                    aiMessage.toolExecutionRequests().stream()
                        .map(this::convertLangChain4jToolRequestToAIRequest)
                        .filter(Objects::nonNull)
                        .collect(Collectors.toList());
                builder.toolExecutionRequests(toolRequests);
            }
        } else if (message instanceof ToolExecutionResultMessage toolResult) {
            builder.role("tool")
                .toolExecutionResult(AIRequest.ToolExecutionResult.builder()
                    .toolExecutionId(toolResult.id())
                    .toolName(toolResult.toolName())
                    .result(toolResult.text())
                    .build());
        } else {
            // 未知消息类型，记录警告并作为用户消息处理
            log.warn("未知的LangChain4j消息类型: {}", message.getClass().getSimpleName());
            builder.role("user").content(message.toString());
        }

        return builder.build();
    }

    /**
     * 转换LangChain4j工具请求到AIRequest格式
     */
    private AIRequest.ToolExecutionRequest convertLangChain4jToolRequestToAIRequest(
            dev.langchain4j.agent.tool.ToolExecutionRequest request) {
        if (request == null) {
            return null;
        }
        
        return AIRequest.ToolExecutionRequest.builder()
            .id(request.id())
            .name(request.name())
            .arguments(request.arguments())
            .build();
    }

    /**
     * AIResponse到LangChain4j格式的适配器
     * 将统一的AIResponse转换回LangChain4j需要的格式
     */
    private List<ChatMessage> convertAIResponseToLangChain4jMessages(AIResponse response) {
        List<ChatMessage> messages = new ArrayList<>();
        
        if (response == null) {
            log.warn("AIResponse为空，返回空消息列表");
            return messages;
        }

        // 创建AI消息
        dev.langchain4j.data.message.AiMessage.Builder aiMessageBuilder = 
            dev.langchain4j.data.message.AiMessage.builder();
        
        // 设置文本内容
        if (response.getContent() != null) {
            aiMessageBuilder.text(response.getContent());
        }
        
        // 转换工具调用
        if (response.getToolCalls() != null && !response.getToolCalls().isEmpty()) {
            List<dev.langchain4j.agent.tool.ToolExecutionRequest> toolRequests = 
                response.getToolCalls().stream()
                    .map(this::convertAIResponseToolCallToLangChain4j)
                    .filter(Objects::nonNull)
                    .collect(Collectors.toList());
            aiMessageBuilder.toolExecutionRequests(toolRequests);
        }
        
        messages.add(aiMessageBuilder.build());
        return messages;
    }

    /**
     * 转换AIResponse工具调用到LangChain4j格式
     */
    private dev.langchain4j.agent.tool.ToolExecutionRequest convertAIResponseToolCallToLangChain4j(
            AIResponse.ToolCall toolCall) {
        if (toolCall == null || toolCall.getFunction() == null) {
            return null;
        }
        
        return dev.langchain4j.agent.tool.ToolExecutionRequest.builder()
            .id(toolCall.getId())
            .name(toolCall.getFunction().getName())
            .arguments(toolCall.getFunction().getArguments())
            .build();
    }
    
    @Override
    public Mono<ChatResponse> chatWithTools(
            List<ChatMessage> messages,
            List<ToolSpecification> toolSpecifications,
            String modelName,
            String apiKey,
            String apiEndpoint,
            Map<String, String> config) {
        
        return Mono.fromCallable(() -> {
            // 直接从config获取提供商信息
            String provider = config != null ? config.get("provider") : null;
            if (provider == null || provider.isEmpty()) {
                throw new IllegalArgumentException("Provider must be specified in config");
            }
            
            // 创建AI提供者（工具调用分支使用可调用工具的Provider）
            AIModelProvider aiProvider = providerFactory.createToolCallProvider(provider, modelName, apiKey, apiEndpoint);
            
            // 尝试获取工具可调用能力（对非LangChain4j实现，如GenAI REST，允许走适配器路径）
            // 标识能力（此方法中chatModel暂未直接使用，保留以兼容后续分支或上游变更）
            ChatLanguageModel chatModel = null;
            ToolCallCapable toolCallCapable = null;
            if (aiProvider instanceof ToolCallCapable tcc) {
                toolCallCapable = tcc;
                if (toolCallCapable.supportsToolCalling()) {
                    chatModel = toolCallCapable.getToolCallableChatModel();
                }
            }
            
            if (chatModel != null) {
                // 构建聊天请求并执行（LangChain4j直连路径）
                ChatRequest chatRequest = ChatRequest.builder()
                    .messages(messages)
                    .toolSpecifications(toolSpecifications)
                    .build();
                return chatModel.chat(chatRequest);
            }

            // 非LangChain4j路径：通过统一AIRequest + Provider调用（允许REST实现例如GenAI）
            AIRequest aiRequest = convertLangChain4jToAIRequest(
                messages,
                toolSpecifications,
                modelName,
                config
            );
            AIResponse aiResponse = aiProvider.generateContent(aiRequest).block();
            if (aiResponse == null) {
                throw new IllegalStateException("Received null AIResponse from provider");
            }
            // 适配为一个包含单条AiMessage的ChatResponse
            List<ChatMessage> adapted = convertAIResponseToLangChain4jMessages(aiResponse);
            dev.langchain4j.data.message.AiMessage adaptedAi = null;
            for (ChatMessage m : adapted) {
                if (m instanceof dev.langchain4j.data.message.AiMessage) {
                    adaptedAi = (dev.langchain4j.data.message.AiMessage) m;
                    break;
                }
            }
            if (adaptedAi == null) {
                throw new IllegalStateException("Failed to adapt AIResponse to AiMessage");
            }
            return ChatResponse.builder().aiMessage(adaptedAi).build();
        });
    }
    
    @Override
    public Mono<List<ChatMessage>> executeToolCallLoop(
            List<ChatMessage> messages,
            List<ToolSpecification> toolSpecifications,
            String modelName,
            String apiKey,
            String apiEndpoint,
            Map<String, String> config,
            int maxIterations) {
        
        return Mono.fromCallable(() -> {
            log.info("启动工具调用循环: 模型={} 最大轮数={} 工具数={}", 
                modelName, maxIterations, toolSpecifications.size());
            
            // 复制消息列表，避免修改原始列表
            List<ChatMessage> conversationHistory = new ArrayList<>(messages);
            
            // 直接从config获取提供商信息
            String provider = config != null ? config.get("provider") : null;
            if (provider == null || provider.isEmpty()) {
                throw new IllegalArgumentException("Provider must be specified in config");
            }
            log.debug("使用提供商: {} 模型={}", provider, modelName);
            
            // 创建AI提供者（工具调用分支使用可调用工具的Provider）
            // 优化：使用缓存键避免重复创建相同配置的提供者
            String cacheKey = String.format("%s:%s:%s", provider, modelName, 
                apiEndpoint != null ? apiEndpoint.hashCode() : "default");
            
            AIModelProvider aiProvider = providerFactory.createToolCallProvider(provider, modelName, apiKey, apiEndpoint);
            if (aiProvider == null) {
                log.error("Failed to create AI provider for model: {}, provider: {}", modelName, provider);
                throw new IllegalArgumentException("Failed to create AI provider for model: " + modelName);
            }
            log.debug("使用AI提供者: {} (缓存键={})", aiProvider.getClass().getSimpleName(), cacheKey);
            
            // 非强依赖LangChain4j能力：统一走AIRequest路径，适配REST实现
            // 执行工具调用循环
            int iteration = 0;
            // 可选：延迟基于 complete:true 的提前结束，用于与外层文本阶段门控配合
            boolean deferComplete = false;
            if (config != null) {
                String v1 = config.get("deferCompleteUntilTextEnd");
                String v2 = config.get("toolLoop.deferComplete");
                deferComplete = (v1 != null && v1.equalsIgnoreCase("true")) || (v2 != null && v2.equalsIgnoreCase("true"));
            }

            while (iteration < maxIterations) {
                log.debug("开始工具调用迭代: {}/{}", iteration + 1, maxIterations);
                
                try {
                // *** 使用适配器模式调用AIModelProvider，经过TracingAIModelProviderDecorator ***
                log.debug("使用AIModelProvider适配器调用（工具调用）- 第{}轮", iteration + 1);
                    
                // 1. 转换LangChain4j格式到AIRequest（并强制函数调用）
                AIRequest aiRequest = convertLangChain4jToAIRequest(
                    conversationHistory, 
                    toolSpecifications, 
                    modelName, 
                    config
                );
                // 明确要求函数调用：为 REST/SDK Provider 提供统一的 functionCalling 配置
                Map<String, Object> params = aiRequest.getParameters();
                if (params != null) {
                    Map<String, Object> fc = new HashMap<>();
                    fc.put("mode", "REQUIRED");
                    // 允许的函数名基于工具规范收集
                    List<String> allowed = toolSpecifications.stream().map(ToolSpecification::name).toList();
                    fc.put("allowedFunctionNames", allowed);
                    params.put("functionCalling", fc);
                    params.put("function_calling", fc); // 兼容另一命名
                }
                
                log.debug("已转换为AIRequest: 消息数={} 工具规范数={}", 
                    aiRequest.getMessages().size(), 
                    aiRequest.getToolSpecifications() != null ? aiRequest.getToolSpecifications().size() : 0);
                
                // 2. 通过TracingAIModelProviderDecorator调用AI服务 ⭐ 关键修复点
                AIResponse aiResponse = aiProvider.generateContent(aiRequest).block();
                if (aiResponse == null) {
                    log.error("Received null AIResponse from provider");
                    throw new RuntimeException("Received null AIResponse from provider");
                }
                
                log.debug("收到AI响应: 文本长度={} 工具调用数={}", 
                    aiResponse.getContent() != null ? aiResponse.getContent().length() : 0,
                    aiResponse.getToolCalls() != null ? aiResponse.getToolCalls().size() : 0);
                
                // 3. 转换AIResponse回LangChain4j格式以保持现有逻辑兼容
                List<ChatMessage> responseMessages = convertAIResponseToLangChain4jMessages(aiResponse);
                if (responseMessages.isEmpty()) {
                    log.error("Failed to convert AIResponse to LangChain4j messages");
                    throw new RuntimeException("Failed to convert AIResponse to LangChain4j messages");
                }
                
                // 4. 提取AI消息（保持与原有逻辑一致）
                AiMessage aiMessage = null;
                for (ChatMessage message : responseMessages) {
                    if (message instanceof AiMessage) {
                        aiMessage = (AiMessage) message;
                        break;
                    }
                }
                
                if (aiMessage == null) {
                    log.error("No AiMessage found in converted response");
                    throw new RuntimeException("No AiMessage found in converted response");
                }
                    
                    log.debug("收到AI消息: 工具请求数={}", 
                        aiMessage.hasToolExecutionRequests() ? aiMessage.toolExecutionRequests().size() : 0);
                    
                conversationHistory.add(aiMessage);
                
                // 检查是否有工具调用请求
                if (!aiMessage.hasToolExecutionRequests()) {
                        log.debug("AI消息未包含工具请求，尝试首轮兜底解析");
                    boolean appliedFallback = false;
                    if (iteration == 0) {
                        try {
                            String text = aiMessage.text();
                            if (text != null && !text.isBlank()) {
                                java.util.List<String> allowedToolNames = toolSpecifications.stream().map(ToolSpecification::name).toList();
                                String toolContextId = config != null ? config.get("toolContextId") : null;
                                for (String toolNameAllowed : allowedToolNames) {
                                    java.util.List<com.ainovel.server.service.ai.tools.fallback.ToolFallbackParser> parsers = toolFallbackRegistry.getParsers(toolNameAllowed);
                                    if (parsers == null || parsers.isEmpty()) continue;
                                    for (var parser : parsers) {
                                        try {
                                            if (parser.canParse(text)) {
                                                java.util.Map<String, Object> parsedParams = parser.parseToToolParams(text);
                                                if (parsedParams != null) {
                                                    String argsJson = objectMapper.writeValueAsString(parsedParams);
                                                    String resultJson = toolExecutionService.invokeTool(toolContextId, toolNameAllowed, argsJson);
                                                    String fakeId = "fallback-" + java.util.UUID.randomUUID();
                                                    conversationHistory.add(new ToolExecutionResultMessage(fakeId, toolNameAllowed, resultJson));
                                                    appliedFallback = true;
                                                    log.info("首轮无工具调用，已通过兜底解析并模拟执行工具: {}", toolNameAllowed);
                                                    break;
                                                }
                                            }
                                        } catch (Exception parseOrExecEx) {
                                            log.warn("兜底解析或执行工具失败: 工具={} 错误={}", toolNameAllowed, parseOrExecEx.getMessage());
                                        }
                                    }
                                    if (appliedFallback) break;
                                }
                            }
                        } catch (Exception ignore) {}
                    }
                    if (!appliedFallback) {
                        log.debug("AI消息未包含工具请求，结束工具调用循环");
                    }
                    break;
                }
                // 新增：首轮若模型未产生任何工具调用，视为错误
                if (iteration == 0 && aiMessage.toolExecutionRequests().isEmpty()) {
                    throw new RuntimeException("MODEL_NO_TOOL_CALL_ON_FIRST_ITERATION");
                }

                // 新增：如果是生成流程中的“markGenerationComplete”，直接结束循环，避免额外一次模型调用
                if (aiMessage.toolExecutionRequests().stream()
                        .anyMatch(req -> "markGenerationComplete".equals(req.name()))) {
                    log.info("检测到 markGenerationComplete 工具，请求结束工具调用循环（不再触发额外模型调用）");
                    break;
                }

                // 检查是否调用了修改完成工具
                if (aiMessage.toolExecutionRequests().stream()
                        .anyMatch(req -> "markModificationComplete".equals(req.name()))) {
                    log.info("检测到 markModificationComplete 工具，结束工具调用循环");
                    // 执行一次该工具（上下文感知），以记录日志或触发事件，然后退出循环
                    String toolContextIdForComplete = config != null ? config.get("toolContextId") : null;
                    toolExecutionService.executeToolCalls(aiMessage, toolContextIdForComplete); 
                    break;
                }
                
                // 执行工具调用（上下文感知）
                    try {
                String toolContextId = config != null ? config.get("toolContextId") : null;

                boolean shouldEndAfterTools = false;
                if (!deferComplete) {
                    // 任意场景：只要本轮任意工具参数包含 complete=true，执行完工具后即结束循环
                    if (aiMessage.hasToolExecutionRequests()) {
                        for (var req : aiMessage.toolExecutionRequests()) {
                            String args = req.arguments();
                            if (args != null && args.replaceAll("\\s+", "").contains("\"complete\":true")) {
                                shouldEndAfterTools = true;
                                break;
                            }
                        }
                    }
                }

                List<ChatMessage> toolResults = toolExecutionService.executeToolCalls(aiMessage, toolContextId);
                if (toolResults == null || toolResults.isEmpty()) {
                    log.warn("工具执行结果为空或null");
                } else {
                    log.debug("工具执行返回结果数={}", toolResults.size());
                    conversationHistory.addAll(toolResults);
                }

                // 若首轮工具执行结果整体为空（例如 text_to_settings 返回 nodes:[]），直接抛错
                boolean allEmpty = (toolResults == null || toolResults.isEmpty()) || toolResults.stream().allMatch(m -> {
                    if (m instanceof ToolExecutionResultMessage ter) {
                        String c = ter.text();
                        return c == null || c.trim().isEmpty() || c.contains("\"nodes\":[]");
                    }
                    return false;
                });
                if (iteration == 0 && allEmpty) {
                    throw new RuntimeException("TOOL_STAGE_EMPTY_RESULT_ON_FIRST_ITERATION");
                }

                if (shouldEndAfterTools) {
                    log.info("检测到工具参数中包含 complete=true，执行完工具后结束循环以节省Token");
                    break;
                }
                    } catch (Exception e) {
                        log.error("工具执行异常: 迭代={} 错误={}", iteration + 1, e.getMessage(), e);
                        // 首轮失败直接抛错，避免错误信息进入下一轮
                        if (iteration == 0) {
                            throw new RuntimeException("TOOL_EXECUTION_FAILED_ON_FIRST_ITERATION: " + e.getMessage(), e);
                        }
                        // 非首轮：停止工具循环，保留已有结果，不把错误文本注入会话
                        break;
                    }
                
                iteration++;
                log.debug("工具调用迭代完成: {}", iteration);
                    
                } catch (Exception e) {
                    log.error("聊天模型调用异常: 迭代={} 错误={}", iteration + 1, e.getMessage(), e);
                    // 优雅处理：Gemini/JDK HttpClient 中断类错误（网络抖动/连接中断）
                    boolean isInterrupted =
                        (e.getMessage() != null && e.getMessage().contains("Sending the request was interrupted"))
                        || (e.getCause() instanceof InterruptedException);
                    if (isInterrupted) {
                        log.info("检测到传输中断类错误，优雅结束当前迭代且不标记完成");
                        // 轻量休眠一次，避免紧接着再次拉起造成风暴
                        try { Thread.sleep(300L); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
                        break; // 退出循环，保留已得到的工具结果，不抛错
                    }
                    
                    // 检查是否为OpenRouter API返回的choices字段为null的错误
                    if (e instanceof NullPointerException && e.getMessage() != null && 
                        e.getMessage().contains("choices()") && e.getMessage().contains("null")) {
                        log.error("Detected OpenRouter API null choices response, possibly due to API rate limit or service error");
                        
                        // 添加重试逻辑
                        int maxRetries = 3;
                        int retryDelay = 2000; // 2秒延迟
                        boolean retrySucceeded = false;
                        
                        for (int retryCount = 1; retryCount <= maxRetries; retryCount++) {
                            log.info("OpenRouter API错误，开始重试 {}/{}...", retryCount, maxRetries);
                            
                            try {
                                // 等待一段时间再重试，避免立即重试触发更多限制
                                Thread.sleep(retryDelay * retryCount); // 递增延迟：2s, 4s, 6s
                                
                                // *** 重试时也使用适配器模式 ***
                                log.debug("重试: 使用AIModelProvider适配器调用 - 第{}次", retryCount);
                                
                                // 转换为AIRequest格式并通过TracingAIModelProviderDecorator调用
                                AIRequest retryAIRequest = convertLangChain4jToAIRequest(
                                    conversationHistory, 
                                    toolSpecifications, 
                                    modelName, 
                                    config
                                );
                                Map<String, Object> retryParams = retryAIRequest.getParameters();
                                if (retryParams != null) {
                                    Map<String, Object> fc = new HashMap<>();
                                    fc.put("mode", "REQUIRED");
                                    List<String> allowed = toolSpecifications.stream().map(ToolSpecification::name).toList();
                                    fc.put("allowedFunctionNames", allowed);
                                    retryParams.put("functionCalling", fc);
                                    retryParams.put("function_calling", fc);
                                }
                                
                                AIResponse retryAIResponse = aiProvider.generateContent(retryAIRequest).block();
                                if (retryAIResponse != null) {
                                    // 转换AIResponse回LangChain4j格式
                                    List<ChatMessage> retryMessages = convertAIResponseToLangChain4jMessages(retryAIResponse);
                                    AiMessage retryAiMessage = null;
                                    for (ChatMessage message : retryMessages) {
                                        if (message instanceof AiMessage) {
                                            retryAiMessage = (AiMessage) message;
                                            break;
                                        }
                                    }
                                    
                                    if (retryAiMessage != null) {
                                        log.info("重试 {} 成功，继续工具调用循环", retryCount);
                                        conversationHistory.add(retryAiMessage);
                                        
                                        // 检查是否有工具调用请求
                                        if (!retryAiMessage.hasToolExecutionRequests()) {
                                            log.debug("No tool execution requests in retry response, ending tool call loop");
                                            retrySucceeded = true;
                                            // 直接跳出所有循环
                                            iteration = maxIterations;
                                            break;
                                        }
                                        
                                        // 执行工具调用（上下文感知）
                                        try {
                                            String toolContextIdRetry = config != null ? config.get("toolContextId") : null;
                                            List<ChatMessage> retryToolResults = toolExecutionService.executeToolCalls(retryAiMessage, toolContextIdRetry);
                                            if (retryToolResults != null && !retryToolResults.isEmpty()) {
                                                log.debug("重试工具执行返回结果数={}", retryToolResults.size());
                                                conversationHistory.addAll(retryToolResults);
                                            }
                                        } catch (Exception toolException) {
                                            log.error("重试期间工具执行异常: {}", toolException.getMessage(), toolException);
                                            conversationHistory.add(new dev.langchain4j.data.message.ToolExecutionResultMessage(
                                                "error", "tool_execution_error", 
                                                "Tool execution failed during retry: " + toolException.getMessage()
                                            ));
                                        }
                                        
                                        // 成功重试，跳出重试循环，继续外层循环
                                        retrySucceeded = true;
                                        break;
                                    }
                                }
                            } catch (InterruptedException ie) {
                                Thread.currentThread().interrupt();
                                log.error("Retry interrupted: {}", ie.getMessage());
                                break;
                            } catch (Exception retryException) {
                                log.warn("重试 {} 失败: {}", retryCount, retryException.getMessage());
                                if (retryCount == maxRetries) {
                                    log.error("全部 {} 次重试失败，放弃重试", maxRetries);
                                }
                            }
                        }
                        
                        // 如果重试成功，继续外层循环
                        if (retrySucceeded) {
                            continue; // 继续下一次迭代
                        }
                        
                        // 如果所有重试都失败了
                        // 添加错误信息到对话历史
                        conversationHistory.add(new dev.langchain4j.data.message.SystemMessage(
                            "Error: OpenRouter API returned null response after " + maxRetries + " retries. This might be due to persistent rate limiting or service issues."
                        ));
                        
                        // 如果是第一次迭代就失败，直接抛出异常
                        if (iteration == 0) {
                            throw new RuntimeException("OpenRouter API returned null response on first iteration after " + maxRetries + " retries, possibly due to rate limiting or service issues", e);
                        }
                        
                        // 否则停止循环但不抛出异常，让已有的工具调用结果生效
                        log.warn("因OpenRouter API空响应，在迭代{}经历{}次重试后停止工具调用循环", iteration + 1, maxRetries);
                        break;
                    }
                    
                    // 检查是否为LangChain4j相关的错误
                    if (e.getMessage() != null && e.getMessage().contains("parts") && e.getMessage().contains("null")) {
                        log.error("检测到LangChain4j解析错误，可能是提供商返回空响应");
                        throw new RuntimeException("AI provider returned invalid response format", e);
                    }
                    
                    // 如果是第一次迭代就失败，直接抛出异常
                    if (iteration == 0) {
                        throw new RuntimeException("初始聊天请求执行失败: " + e.getMessage(), e);
                    }
                    
                    // 否则记录错误但继续执行
                    log.warn("因错误停止工具调用循环: 迭代={} 错误={}", iteration + 1, e.getMessage());
                    break;
                }
            }
            
            if (iteration >= maxIterations) {
                log.warn("已达到工具调用最大迭代次数 ({})", maxIterations);
            }
            
            log.info("工具调用循环完成: 迭代次数={} 最终对话长度={}", 
                iteration, conversationHistory.size());
            
            return conversationHistory;
        })
        .doOnError(error -> log.error("工具调用循环失败: {}", error.getMessage(), error))
        .onErrorMap(throwable -> {
            // 包装异常以提供更好的错误信息
            if (throwable instanceof RuntimeException) {
                return throwable;
            }
            return new RuntimeException("工具调用循环执行失败: " + throwable.getMessage(), throwable);
        });
    }

}
