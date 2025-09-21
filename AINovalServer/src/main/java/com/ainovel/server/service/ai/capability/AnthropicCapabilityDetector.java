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
 * Anthropic提供商能力检测器
 */
@Slf4j
@Component
public class AnthropicCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://api.anthropic.com";

    @Override
    public String getProviderName() {
        return "anthropic";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        // Anthropic需要API密钥才能获取模型列表
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        // 返回默认的Anthropic模型列表（基于2025年1月最新价格）
        List<ModelInfo> models = new ArrayList<>();

        // Latest Models
        models.add(ModelInfo.builder()
            .id("claude-4.1-opus")
            .name("Opus 4.1")
            .description("最智能的模型，适合复杂任务")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tags", List.of("最新", "智能", "复杂任务"))
            .withInputPrice(15.0)
            .withOutputPrice(75.0));

        models.add(ModelInfo.builder()
            .id("claude-4-sonnet")
            .name("Sonnet 4")
            .description("智能、成本和速度的最优平衡")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tiered_pricing", true)
            .withProperty("tier_threshold", 200000)
            .withProperty("tags", List.of("最新", "平衡", "分层定价"))
            .withInputPrice(3.0)
            .withOutputPrice(15.0));

        models.add(ModelInfo.builder()
            .id("claude-3.5-haiku")
            .name("Haiku 3.5")
            .description("最快、最经济高效的模型")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tags", List.of("最新", "快速", "经济"))
            .withInputPrice(0.80)
            .withOutputPrice(4.0));

        // Legacy Models
        models.add(ModelInfo.builder()
            .id("claude-3-opus-20240229")
            .name("Opus 3")
            .description("Claude 3 Opus遗留模型")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tags", List.of("遗留", "智能"))
            .withInputPrice(15.0)
            .withOutputPrice(75.0));

        models.add(ModelInfo.builder()
            .id("claude-3.7-sonnet")
            .name("Sonnet 3.7")
            .description("Claude 3.7 Sonnet遗留模型")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tags", List.of("遗留", "平衡"))
            .withInputPrice(3.0)
            .withOutputPrice(15.0));

        models.add(ModelInfo.builder()
            .id("claude-3-haiku-20240307")
            .name("Haiku 3")
            .description("Claude 3 Haiku遗留模型")
            .maxTokens(200000)
            .provider("anthropic")
            .build()
            .withProperty("supports_prompt_caching", true)
            .withProperty("tags", List.of("遗留", "快速"))
            .withInputPrice(0.25)
            .withOutputPrice(1.25));

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
                .uri("/v1/models")
                .header("x-api-key", apiKey)
                .header("anthropic-version", "2023-06-01")
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