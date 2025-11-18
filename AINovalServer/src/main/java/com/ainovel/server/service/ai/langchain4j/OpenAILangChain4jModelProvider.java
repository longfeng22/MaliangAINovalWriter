package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.ExchangeStrategies;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.model.openai.OpenAiStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * OpenAI的LangChain4j实现
 */
@Slf4j
public class OpenAILangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private static final String DEFAULT_API_ENDPOINT = "https://api.openai.com/v1";

    /**
     * 构造函数
     *
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点
     * @param proxyConfig 代理配置
     * @param listenerManager 监听器管理器
     */
    public OpenAILangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint,
                                          ProxyConfig proxyConfig, ChatModelListenerManager listenerManager) {
        super("openai", modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            // 获取最终 API 端点：
            // 1. 如果用户配置的 apiEndpoint 非空白，则优先使用
            // 2. 否则降级为默认端点（https://api.openai.com/v1）
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);

            // 若 apiEndpoint 存在但为纯空白字符串，getApiEndpoint 会返回空白，此处需要额外处理，
            // 以避免将空白 baseUrl 传递给 DefaultOpenAiClient，导致 IllegalArgumentException。
            if (baseUrl == null || baseUrl.trim().isEmpty()) {
                baseUrl = DEFAULT_API_ENDPOINT;
            }

            // OpenAI Provider 特殊处理：去除用户端点中的重复路径，避免 LangChain4j 自动拼接导致路径重复
            baseUrl = normalizeOpenAIEndpoint(baseUrl);

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

            log.info("OpenAI模型初始化成功: {}", modelName);
        } catch (Exception e) {
            log.error("初始化OpenAI模型时出错", e);
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
                .filter(calc -> "openai".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        log.info("开始OpenAI流式生成，模型: {}", modelName);

        // 记录连接开始时间
        final long connectionStartTime = System.currentTimeMillis();
        final AtomicLong firstResponseTime = new AtomicLong(0);

        return super.generateContentStream(request)
                .doOnSubscribe(__ -> {
                    log.info("OpenAI流式生成已订阅，等待首次响应...");
                })
                .doOnNext(content -> {
                    // 记录首次响应时间
                    if (firstResponseTime.get() == 0 && !"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        firstResponseTime.set(System.currentTimeMillis());
                        log.info("OpenAI首次响应耗时: {}ms, 模型: {}",
                                (firstResponseTime.get() - connectionStartTime), modelName);
                    }

                    if (!"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        //log.debug("OpenAI生成内容: {}", content);
                    }
                })
                .doOnComplete(() -> {
                    if (firstResponseTime.get() > 0) {
                        log.info("OpenAI流式生成完成，总耗时: {}ms, 模型: {}",
                                (System.currentTimeMillis() - connectionStartTime), modelName);
                    } else {
                        log.warn("OpenAI流式生成完成，但未收到任何内容，可能是连接问题，总耗时: {}ms, 模型: {}",
                                (System.currentTimeMillis() - connectionStartTime), modelName);
                    }
                })
                .doOnError(e -> {
                    log.error("OpenAI流式生成出错: {}, 模型: {}", e.getMessage(), modelName, e);
                })
                .doOnCancel(() -> {
                    if (firstResponseTime.get() > 0) {
                        log.info("OpenAI流式生成被取消，已生成内容 {}ms，总耗时: {}ms, 模型: {}",
                                (firstResponseTime.get() - connectionStartTime),
                                (System.currentTimeMillis() - connectionStartTime),
                                modelName);
                    } else {
                        log.warn("OpenAI流式生成被取消，未收到任何内容，可能是连接超时，总耗时: {}ms, 模型: {}",
                                (System.currentTimeMillis() - connectionStartTime), modelName);
                    }
                });
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        log.info("获取OpenAI模型列表");

        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ?
                apiEndpoint : DEFAULT_API_ENDPOINT;

        ExchangeStrategies strategies = ExchangeStrategies.builder()
                .codecs(cfg -> cfg.defaultCodecs().maxInMemorySize(5 * 1024 * 1024)) // 5MB
                .build();

        WebClient webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .exchangeStrategies(strategies)
                .build();

        return webClient.get()
                .uri("/models")
                .header("Authorization", "Bearer " + apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .flatMapMany(response -> {
                    try {
                        log.debug("OpenAI模型列表响应: {}", response);
                        // 简化起见，返回空让基类使用统一的默认列表
                        return Flux.<ModelInfo>empty();
                    } catch (Exception e) {
                        log.error("解析OpenAI模型列表时出错", e);
                        return Flux.<ModelInfo>empty();
                    }
                })
                .onErrorResume(e -> Flux.<ModelInfo>empty());
    }

    /**
     * 规范化 OpenAI 端点 URL，避免 LangChain4j 自动拼接导致路径重复
     * 
     * @param endpoint 原始端点
     * @return 规范化后的端点
     */
    private String normalizeOpenAIEndpoint(String endpoint) {
        if (endpoint == null || endpoint.trim().isEmpty()) {
            return endpoint;
        }
        
        String normalized = endpoint.trim();
        
        // 移除末尾的斜杠
        if (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        
        // 检查并移除常见的 OpenAI API 路径，因为 LangChain4j 会自动拼接
        String[] pathsToRemove = {
            "/chat/completions",
            "/v1/chat/completions",
            "/completions"
        };
        
        for (String path : pathsToRemove) {
            if (normalized.endsWith(path)) {
                normalized = normalized.substring(0, normalized.length() - path.length());
                log.info("OpenAI端点规范化: 移除了重复路径 '{}', 原URL: {}, 规范化后: {}", 
                        path, endpoint, normalized);
                break;
            }
        }
        
        return normalized;
    }

}
