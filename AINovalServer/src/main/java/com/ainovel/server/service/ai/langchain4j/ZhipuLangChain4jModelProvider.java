package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.community.model.zhipu.ZhipuAiChatModel;
import dev.langchain4j.community.model.zhipu.ZhipuAiStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * 智谱AI（GLM） - OpenAI 兼容端点接入
 * 参考：智谱 OpenAI 兼容网关
 */
@Slf4j
public class ZhipuLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private static final String DEFAULT_API_ENDPOINT = "https://open.bigmodel.cn/";


    public ZhipuLangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint, ProxyConfig proxyConfig,
                                         ChatModelListenerManager listenerManager) {
        super("zhipu", modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);
            if (baseUrl == null || baseUrl.trim().isEmpty()) {
                baseUrl = DEFAULT_API_ENDPOINT;
            }
            // 国内平台：不配置系统代理

            var listeners = getListeners();

            var chatBuilder = ZhipuAiChatModel.builder()
                    .apiKey(apiKey)
                    .model(modelName)
                    .baseUrl(baseUrl)
                    .callTimeout(Duration.ofSeconds(300))
                    .connectTimeout(Duration.ofSeconds(60))
                    .writeTimeout(Duration.ofSeconds(60))
                    .readTimeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            if (!listeners.isEmpty()) chatBuilder.listeners(listeners);
            this.chatModel = chatBuilder.build();

            var streamingBuilder = ZhipuAiStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .model(modelName)
                    .baseUrl(baseUrl)
                    .callTimeout(Duration.ofSeconds(300))
                    .connectTimeout(Duration.ofSeconds(60))
                    .writeTimeout(Duration.ofSeconds(60))
                    .readTimeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            if (!listeners.isEmpty()) streamingBuilder.listeners(listeners);
            this.streamingChatModel = new com.ainovel.server.service.ai.langchain4j.wrapper.SafeStreamingChatModel(
                    streamingBuilder.build()
            );

            log.info("Zhipu(GLM) 专用客户端初始化成功: {} @ {}", modelName, baseUrl);
        } catch (Exception e) {
            log.error("初始化 Zhipu(GLM) 模型时出错", e);
            this.chatModel = null;
            this.streamingChatModel = null;
        }
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request) {
        int inputTokens = estimateInputTokens(request);
        int outputTokens = request.getMaxTokens() != null ? request.getMaxTokens() : 1000;
        
        // 尝试使用PricingCalculator
        try {
            var pricingCalculator = getPricingCalculator();
            if (pricingCalculator != null) {
                return pricingCalculator.calculateTotalCost(modelName, inputTokens, outputTokens)
                        .map(cost -> cost.doubleValue() * 7.2);
            }
        } catch (Exception e) {
            log.debug("使用PricingCalculator失败，使用默认估算: {}", e.getMessage());
        }
        
        // 默认估算
        double defaultPrice = 0.002;
        int totalTokens = inputTokens + outputTokens;
        double costInUSD = (totalTokens / 1000.0) * defaultPrice;
        return Mono.just(costInUSD * 7.2);
    }
    
    private com.ainovel.server.service.ai.pricing.TokenPricingCalculator getPricingCalculator() {
        try {
            return applicationContext.getBeansOfType(
                com.ainovel.server.service.ai.pricing.TokenPricingCalculator.class)
                .values().stream()
                .filter(calc -> "zhipu".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty()
                ? apiEndpoint
                : DEFAULT_API_ENDPOINT;

        WebClient webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .build();

        return webClient.get()
                .uri("/models")
                .header("Authorization", "Bearer " + apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .flatMapMany(response -> {
                    try {
                        ObjectMapper mapper = new ObjectMapper();
                        JsonNode root = mapper.readTree(response);
                        List<ModelInfo> models = new ArrayList<>();

                        JsonNode data = root.path("data");
                        if (!data.isArray() || data.isEmpty()) {
                            data = root.path("models");
                        }

                        if (data.isArray()) {
                            for (JsonNode n : data) {
                                String id = n.path("id").asText();
                                if (id == null || id.isEmpty()) continue;

                                int maxTokens = 128000;
                                if (n.has("context_length")) {
                                    try {
                                        maxTokens = n.path("context_length").asInt(128000);
                                    } catch (Exception ignore) {
                                    }
                                }

                                ModelInfo mi = ModelInfo.basic(id, id, "zhipu")
                                        .withDescription("Zhipu GLM 模型: " + id)
                                        .withMaxTokens(maxTokens);
                                models.add(mi);
                            }
                        }
                        return Flux.fromIterable(models);
                    } catch (Exception e) {
                        log.error("解析Zhipu模型列表失败: {}", e.getMessage(), e);
                        return Flux.empty();
                    }
                })
                .onErrorResume(e -> Flux.empty());
    }
 
}




