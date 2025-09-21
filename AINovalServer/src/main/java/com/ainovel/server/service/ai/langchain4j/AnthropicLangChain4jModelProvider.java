package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.model.anthropic.AnthropicChatModel;
import dev.langchain4j.model.anthropic.AnthropicStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Anthropic的LangChain4j实现
 */
@Slf4j
public class AnthropicLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private static final String DEFAULT_API_ENDPOINT = "https://api.anthropic.com";

    /**
     * 构造函数
     *
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点
     * @param listenerManager 监听器管理器
     */
    public AnthropicLangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint, 
                                           ChatModelListenerManager listenerManager) {
        super("anthropic", modelName, apiKey, apiEndpoint, null, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            // 获取API端点
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);

            // 配置系统代理
            configureSystemProxy();

            // 获取所有注册的监听器
            List<dev.langchain4j.model.chat.listener.ChatModelListener> listeners = getListeners();

            // 创建非流式模型
            var chatBuilder = AnthropicChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300));
            
            if (!listeners.isEmpty()) {
                chatBuilder.listeners(listeners);
            }
            this.chatModel = chatBuilder.build();

            // 创建流式模型
            var streamingBuilder = AnthropicStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300));
            
            if (!listeners.isEmpty()) {
                streamingBuilder.listeners(listeners);
            }
            this.streamingChatModel = streamingBuilder.build();

            log.info("Anthropic模型初始化成功: {}", modelName);
        } catch (Exception e) {
            log.error("初始化Anthropic模型时出错", e);
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
        
        double defaultPrice = 0.003;
        int totalTokens = inputTokens + outputTokens;
        double costInUSD = (totalTokens / 1000.0) * defaultPrice;
        return Mono.just(costInUSD * 7.2);
    }
    
    private com.ainovel.server.service.ai.pricing.TokenPricingCalculator getPricingCalculator() {
        try {
            return applicationContext.getBeansOfType(
                com.ainovel.server.service.ai.pricing.TokenPricingCalculator.class)
                .values().stream()
                .filter(calc -> "anthropic".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        log.info("获取Anthropic模型列表");

        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ?
                apiEndpoint : DEFAULT_API_ENDPOINT;

        WebClient webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .build();

        return webClient.get()
                .uri("/v1/models")
                .header("x-api-key", apiKey)
                .header("anthropic-version", "2023-06-01")
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .flatMapMany(response -> {
                    try {
                        log.debug("Anthropic模型列表响应: {}", response);
                        // 简化起见，返回空让基类使用统一的默认列表
                        return Flux.<ModelInfo>empty();
                    } catch (Exception e) {
                        log.error("解析Anthropic模型列表时出错", e);
                        return Flux.<ModelInfo>empty();
                    }
                })
                .onErrorResume(e -> Flux.<ModelInfo>empty());
    }

}
