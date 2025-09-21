package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.model.openai.OpenAiStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * OpenRouter的LangChain4j实现
 * 使用OpenAI兼容模式，因为OpenRouter API与OpenAI兼容
 */
@Slf4j
public class OpenRouterLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private static final String DEFAULT_API_ENDPOINT = "https://openrouter.ai/api/v1";
    

    
    // 模型列表缓存 - 静态缓存，所有实例共享
    private static final Map<String, List<ModelInfo>> MODEL_CACHE = new ConcurrentHashMap<>();
    
    // 缓存过期时间 - 1小时
    private static final long CACHE_EXPIRY_MS = 3600 * 1000;
    
    // 最后一次缓存更新时间
    private static final AtomicLong lastCacheUpdateTime = new AtomicLong(0);
    
    // 最大返回的模型数量
    private static final int MAX_MODELS_TO_RETURN = 20;


    /**
     * 构造函数
     *
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点
     * @param proxyConfig 代理配置
     * @param listenerManager 监听器管理器
     */
    public OpenRouterLangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint,
                                          ProxyConfig proxyConfig, ChatModelListenerManager listenerManager) {
        super("openrouter", modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            // 获取API端点
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);
            
            // 额外的安全检查
            if (baseUrl == null || baseUrl.trim().isEmpty()) {
                baseUrl = DEFAULT_API_ENDPOINT;
                log.warn("OpenRouter baseUrl为空，使用默认值: {}", DEFAULT_API_ENDPOINT);
            }
            
            log.info("OpenRouter初始化 - baseUrl: {}, apiEndpoint: {}, DEFAULT_API_ENDPOINT: {}", 
                     baseUrl, this.apiEndpoint, DEFAULT_API_ENDPOINT);

            // 配置系统代理
            configureSystemProxy();

            // 获取所有注册的监听器
            List<dev.langchain4j.model.chat.listener.ChatModelListener> listeners = getListeners();

            // 创建非流式模型
            var chatBuilder = OpenAiChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            
            if (!listeners.isEmpty()) {
                chatBuilder.listeners(listeners);
            }
            this.chatModel = chatBuilder.build();

            // 创建流式模型
            var streamingBuilder = OpenAiStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            
            if (!listeners.isEmpty()) {
                streamingBuilder.listeners(listeners);
            }
            this.streamingChatModel = streamingBuilder.build();

            log.info("OpenRouter模型初始化成功: {}", modelName);
        } catch (Exception e) {
            log.error("初始化OpenRouter模型时出错", e);
            this.chatModel = null;
            this.streamingChatModel = null;
        }
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request) {
        int inputTokens = estimateInputTokens(request);
        int outputTokens = request.getMaxTokens() != null ? request.getMaxTokens() : 1000;
        
        try {
            var pricingCalculator = getPricingCalculator();
            if (pricingCalculator != null) {
                return pricingCalculator.calculateTotalCost(modelName, inputTokens, outputTokens)
                        .map(cost -> cost.doubleValue() * 7.2);
            }
        } catch (Exception e) {
            log.debug("使用PricingCalculator失败: {}", e.getMessage());
        }
        
        double defaultPrice = 0.01;
        int totalTokens = inputTokens + outputTokens;
        double costInUSD = (totalTokens / 1000.0) * defaultPrice;
        return Mono.just(costInUSD * 7.2);
    }
    
    private com.ainovel.server.service.ai.pricing.TokenPricingCalculator getPricingCalculator() {
        try {
            return applicationContext.getBeansOfType(
                com.ainovel.server.service.ai.pricing.TokenPricingCalculator.class)
                .values().stream()
                .filter(calc -> "openrouter".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        log.info("开始OpenRouter流式生成，模型: {}", modelName);

        // 记录连接开始时间
        final long connectionStartTime = System.currentTimeMillis();
        final AtomicLong firstResponseTime = new AtomicLong(0);

        return super.generateContentStream(request)
                .doOnSubscribe(__ -> {
                    log.info("OpenRouter流式生成已订阅，等待首次响应...");
                })
                .doOnNext(content -> {
                    // 记录首次响应时间
                    if (firstResponseTime.get() == 0 && !"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        firstResponseTime.set(System.currentTimeMillis());
                        log.info("OpenRouter首次响应耗时: {}ms, 模型: {}",
                                (firstResponseTime.get() - connectionStartTime), modelName);
                    }

                    if (!"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        //log.debug("OpenRouter生成内容: {}", content);
                    }
                })
                .doOnComplete(() -> {
                    if (firstResponseTime.get() > 0) {
                        log.info("OpenRouter流式生成完成，总耗时: {}ms, 模型: {}",
                                (System.currentTimeMillis() - connectionStartTime), modelName);
                    } else {
                        log.warn("OpenRouter流式生成完成，但未收到有效响应，总耗时: {}ms, 模型: {}",
                                (System.currentTimeMillis() - connectionStartTime), modelName);
                    }
                })
                .doOnError(e -> {
                    log.error("OpenRouter流式生成出错: {}, 模型: {}", e.getMessage(), modelName, e);
                });
    }

    /**
     * OpenRouter不需要API密钥就能获取模型列表
     * 覆盖基类的listModels方法，但保持缓存机制
     */
    @Override
    public Flux<ModelInfo> listModels() {
        log.info("获取OpenRouter模型列表");
        
        // 检查缓存是否有效
        if (!isCacheExpired() && !MODEL_CACHE.isEmpty()) {
            log.info("从缓存返回OpenRouter模型列表，共{}个模型", MODEL_CACHE.size());
            List<ModelInfo> cachedModels = MODEL_CACHE.getOrDefault("models", getUnifiedDefaultModels());
            return Flux.fromIterable(cachedModels);
        }

        // 尝试从 API 获取，失败时使用统一默认数据
        return callOpenRouterApi()
                .switchIfEmpty(Flux.fromIterable(getUnifiedDefaultModels()))
                .collectList()
                .flatMapMany(models -> {
                    if (!models.isEmpty()) {
                        updateCache(models);
                    }
                    return Flux.fromIterable(models);
                })
                .onErrorResume(e -> {
                    log.error("获取OpenRouter模型列表时出错", e);
                    List<ModelInfo> defaultModels = getUnifiedDefaultModels();
                    updateCache(defaultModels);
                    return Flux.fromIterable(defaultModels);
                });
    }
    
    /**
     * 调用OpenRouter API获取模型列表
     */
    private Flux<ModelInfo> callOpenRouterApi() {
        ExchangeStrategies strategies = ExchangeStrategies.builder()
                .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(5 * 1024 * 1024)) // 5MB
                .build();
        
        WebClient webClient = WebClient.builder()
                .baseUrl("https://openrouter.ai/api")
                .exchangeStrategies(strategies)
                .build();

        return webClient.get()
                .uri("/v1/models")
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .flatMapMany(response -> {
                    try {
                        ObjectMapper mapper = new ObjectMapper();
                        JsonNode root = mapper.readTree(response);
                        JsonNode data = root.path("data");
                        
                        List<ModelInfo> models = new ArrayList<>();
                        
                        if (data.isArray()) {
                            for (JsonNode modelNode : data) {
                                String id = modelNode.path("id").asText();
                                String context = modelNode.path("context_length").asText("0");
                                int contextLength = Integer.parseInt(context.replaceAll("[^0-9]", ""));
                                
                                double inputPrice = 0.0;
                                double outputPrice = 0.0;
                                
                                if (modelNode.has("pricing")) {
                                    JsonNode pricing = modelNode.path("pricing");
                                    inputPrice = pricing.path("prompt").asDouble(0.0);
                                    outputPrice = pricing.path("completion").asDouble(0.0);
                                }
                                
                                double unifiedPrice = (inputPrice + outputPrice) / 2;
                                if (unifiedPrice <= 0) {
                                    unifiedPrice = 0.001; // 默认价格
                                }
                                
                                ModelInfo modelInfo = ModelInfo.basic(id, id, "openrouter")
                                        .withDescription("OpenRouter提供的" + id + "模型")
                                        .withMaxTokens(contextLength > 0 ? contextLength : 8192)
                                        .withUnifiedPrice(unifiedPrice);
                                        
                                models.add(modelInfo);
                            }
                        }
                        
                        // 按价格排序并限制数量
                        models.sort(Comparator.<ModelInfo, Double>comparing(model -> 
                            model.getPricing().getOrDefault("unified", 0.0)).reversed());
                        
                        List<ModelInfo> finalModels = models.size() > MAX_MODELS_TO_RETURN ? 
                                models.subList(0, MAX_MODELS_TO_RETURN) : models;
                        
                        return Flux.fromIterable(finalModels);
                    } catch (Exception e) {
                        log.error("解析OpenRouter模型列表时出错", e);
                        return Flux.<ModelInfo>empty();
                    }
                });
    }
    
    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        // OpenRouter不需要API密钥，直接调用API
        return callOpenRouterApi();
    }
    
    /**
     * 检查缓存是否过期
     * @return 是否过期
     */
    private boolean isCacheExpired() {
        long now = System.currentTimeMillis();
        long lastUpdate = lastCacheUpdateTime.get();
        return (now - lastUpdate) > CACHE_EXPIRY_MS;
    }
    
    /**
     * 更新缓存
     * @param models 模型列表
     */
    private synchronized void updateCache(List<ModelInfo> models) {
        MODEL_CACHE.put("models", models);
        lastCacheUpdateTime.set(System.currentTimeMillis());
        log.info("更新OpenRouter模型缓存，共{}个模型", models.size());
    }

}
