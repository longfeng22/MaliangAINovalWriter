package com.ainovel.server.service.ai.capability;

import java.util.ArrayList;
import java.util.List;

import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.domain.model.ModelListingCapability;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * X.AI提供商能力检测器
 */
@Slf4j
@Component
public class GrokCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://api.x.ai/v1";

    @Override
    public String getProviderName() {
        return "x-ai";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        // X.AI需要API密钥获取模型列表
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        // 返回默认的X.AI模型列表（与GrokTokenPricingCalculator保持一致）
        List<ModelInfo> models = new ArrayList<>();

        // Grok 3 Beta
        models.add(ModelInfo.builder()
            .id("x-ai/grok-3-beta")
            .name("Grok 3 Beta")
            .description("Grok 3 Beta 通用模型")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.003)
            .withOutputPrice(0.006));

        // Grok 3
        models.add(ModelInfo.builder()
            .id("x-ai/grok-3")
            .name("Grok 3")
            .description("Grok 3 通用模型")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.003)
            .withOutputPrice(0.006));

        // Grok 3 Fast
        models.add(ModelInfo.builder()
            .id("x-ai/grok-3-fast")
            .name("Grok 3 Fast")
            .description("Grok 3 Fast 高速版")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.0015)
            .withOutputPrice(0.003));

        // Grok 3 Mini
        models.add(ModelInfo.builder()
            .id("x-ai/grok-3-mini")
            .name("Grok 3 Mini")
            .description("Grok 3 Mini 轻量版")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.0006)
            .withOutputPrice(0.0012));

        // Grok 3 Mini Fast
        models.add(ModelInfo.builder()
            .id("x-ai/grok-3-mini-fast")
            .name("Grok 3 Mini Fast")
            .description("Grok 3 Mini Fast 更高速版本")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.0003)
            .withOutputPrice(0.0006));

        // Grok 2 Vision
        models.add(ModelInfo.builder()
            .id("x-ai/grok-2-vision-1212")
            .name("Grok 2 Vision")
            .description("Grok 2 视觉模型")
            .maxTokens(131072)
            .provider("x-ai")
            .build()
            .withInputPrice(0.003)
            .withOutputPrice(0.006));

        return Flux.fromIterable(models);
    }

    @Override
    public Mono<Boolean> testApiKey(String apiKey, String apiEndpoint) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            return Mono.just(false);
        }

        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ?
                apiEndpoint : DEFAULT_API_ENDPOINT;

        WebClient webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .build();

        return webClient.get()
                .uri("/models")
                .header("Authorization", "Bearer " + apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> true)
                .onErrorReturn(false);
    }

    @Override
    public String getDefaultApiEndpoint() {
        return DEFAULT_API_ENDPOINT;
    }
} 