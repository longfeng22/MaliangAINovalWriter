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
 * Gemini提供商能力检测器
 */
@Slf4j
@Component
public class GeminiCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://generativelanguage.googleapis.com";

    @Override
    public String getProviderName() {
        return "gemini";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        // Gemini不支持直接列出所有模型，需要使用默认模型列表
        return Mono.just(ModelListingCapability.NO_LISTING);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        // 返回默认的Gemini模型列表（以最新API产品线为准）
        List<ModelInfo> models = new ArrayList<>();

        // 2.5 Pro（文本/多模态）
        models.add(ModelInfo.builder()
            .id("gemini-2.5-pro")
            .name("Gemini 2.5 Pro")
            .description("2.5 Pro：高级通用多模态，强推理；分段价：≤200K/＞200K")
            .maxTokens(2_000_000)
            .provider("gemini")
            .build());
        
                    // 2.5 Pro（文本/多模态）
        models.add(ModelInfo.builder()
            .id("gemini-2.5-pro-preview-06-05")
            .name("Gemini-2.5-pro-preview-06-05")
            .description("2.5 Pro：高级通用多模态，强推理；分段价：≤200K/＞200K")
            .maxTokens(2_000_000)
            .provider("gemini")
            .build());
        
                    // 2.5 Pro（文本/多模态）
        models.add(ModelInfo.builder()
        .id("gemini-2.5-pro-preview-03-25")
        .name("gemini-2.5-pro-preview-03-25")
        .description("2.5 Pro：高级通用多模态，强推理；分段价：≤200K/＞200K")
        .maxTokens(2_000_000)
        .provider("gemini")
        .build());

        // 2.5 Flash / Flash-Lite（文本/图像/视频/音频）
        models.add(ModelInfo.builder()
            .id("gemini-2.5-flash")
            .name("Gemini 2.5 Flash")
            .description("2.5 Flash：100万上下文，混合推理，思考预算")
            .maxTokens(1_000_000)
            .provider("gemini")
            .build());
        models.add(ModelInfo.builder()
            .id("gemini-2.5-flash-lite")
            .name("Gemini 2.5 Flash-Lite")
            .description("2.5 Flash-Lite：成本最低，适合大规模调用")
            .maxTokens(1_000_000)
            .provider("gemini")
            .build());

        // 2.0 Flash / Flash-Lite
        models.add(ModelInfo.builder()
            .id("gemini-2.0-flash")
            .name("Gemini 2.0 Flash")
            .description("2.0 Flash：均衡多模态，1M 上下文")
            .maxTokens(1_000_000)
            .provider("gemini")
            .build());
        models.add(ModelInfo.builder()
            .id("gemini-2.0-flash-lite")
            .name("Gemini 2.0 Flash-Lite")
            .description("2.0 Flash-Lite：小巧高性价比")
            .maxTokens(1_000_000)
            .provider("gemini")
            .build());

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
                .uri("/v1/models?key=" + apiKey)
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