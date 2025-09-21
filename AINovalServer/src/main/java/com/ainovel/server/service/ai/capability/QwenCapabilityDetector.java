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
 * 通义千问能力检测器（DashScope OpenAI兼容端点）
 */
@Slf4j
@Component
public class QwenCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1";

    @Override
    public String getProviderName() {
        return "qwen";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        List<ModelInfo> models = new ArrayList<>();

        // Max（预览，阶梯计费）
        models.add(ModelInfo.builder()
            .id("qwen3-max-preview")
            .name("Qwen3-Max-Preview")
            .description("Qwen3 Max 预览版，输入/输出阶梯计费")
            .maxTokens(262144)
            .provider("qwen")
            .build()
            .withProperty("tags", java.util.List.of("max","preview","tiered-pricing")));

        // Plus（稳定/最新版/快照，思考与非思考双模式，阶梯计费）
        models.add(ModelInfo.builder()
            .id("qwen-plus")
            .name("Qwen-Plus")
            .description("Qwen-Plus 稳定版，支持思考/非思考，阶梯计费")
            .maxTokens(131072)
            .provider("qwen")
            .build()
            .withProperty("tags", java.util.List.of("plus","stable","thinking","tiered-pricing")));
        models.add(ModelInfo.builder()
            .id("qwen-plus-latest")
            .name("Qwen-Plus-Latest")
            .description("Qwen-Plus 最新版，1M上下文，阶梯计费")
            .maxTokens(1000000)
            .provider("qwen")
            .build()
            .withProperty("tags", java.util.List.of("plus","latest","thinking","1M","tiered-pricing")));
        models.add(ModelInfo.builder()
            .id("qwen-plus-2025-09-11")
            .name("Qwen-Plus-2025-09-11")
            .description("Qwen-Plus 快照版 2025-09-11")
            .maxTokens(1000000)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-plus-2025-07-28")
            .name("Qwen-Plus-2025-07-28")
            .description("Qwen-Plus 快照版 2025-07-28")
            .maxTokens(1000000)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-plus-2025-07-14")
            .name("Qwen-Plus-2025-07-14")
            .description("Qwen-Plus 快照版 2025-07-14")
            .maxTokens(131072)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-plus-2025-04-28")
            .name("Qwen-Plus-2025-04-28")
            .description("Qwen-Plus 快照版 2025-04-28")
            .maxTokens(98304)
            .provider("qwen")
            .build());

        // Flash（替代 Turbo，阶梯计费）
        models.add(ModelInfo.builder()
            .id("qwen-flash")
            .name("Qwen-Flash")
            .description("Qwen-Flash 稳定版，0-1M阶梯计费")
            .maxTokens(1000000)
            .provider("qwen")
            .build()
            .withProperty("tags", java.util.List.of("flash","tiered-pricing")));
        models.add(ModelInfo.builder()
            .id("qwen-flash-2025-07-28")
            .name("Qwen-Flash-2025-07-28")
            .description("Qwen-Flash 快照版 2025-07-28")
            .maxTokens(1000000)
            .provider("qwen")
            .build());

        // Turbo（保留兼容）
        models.add(ModelInfo.builder()
            .id("qwen-turbo")
            .name("Qwen-Turbo")
            .description("Qwen-Turbo 稳定版（建议迁移至 Flash）")
            .maxTokens(1000000)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-turbo-latest")
            .name("Qwen-Turbo-Latest")
            .description("Qwen-Turbo 最新版（建议迁移至 Flash）")
            .maxTokens(1000000)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-turbo-2025-07-15")
            .name("Qwen-Turbo-2025-07-15")
            .description("Qwen-Turbo 快照版 2025-07-15")
            .maxTokens(131072)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-turbo-2025-04-28")
            .name("Qwen-Turbo-2025-04-28")
            .description("Qwen-Turbo 快照版 2025-04-28")
            .maxTokens(131072)
            .provider("qwen")
            .build());

        // Reasoning & Long
        models.add(ModelInfo.builder()
            .id("qwq-plus")
            .name("QwQ-Plus")
            .description("QwQ 推理模型稳定版")
            .maxTokens(131072)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwq-plus-latest")
            .name("QwQ-Plus-Latest")
            .description("QwQ 推理模型最新版")
            .maxTokens(131072)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-long")
            .name("Qwen-Long")
            .description("Qwen-Long 1M 上下文模型")
            .maxTokens(10000000)
            .provider("qwen")
            .build());
        models.add(ModelInfo.builder()
            .id("qwen-long-latest")
            .name("Qwen-Long-Latest")
            .description("Qwen-Long 1M 上下文最新版")
            .maxTokens(10000000)
            .provider("qwen")
            .build());

        return Flux.fromIterable(models);
    }

    @Override
    public Mono<Boolean> testApiKey(String apiKey, String apiEndpoint) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            return Mono.just(false);
        }
        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ? apiEndpoint : DEFAULT_API_ENDPOINT;
        WebClient webClient = WebClient.builder().baseUrl(baseUrl).build();
        return webClient.get()
            .uri("/models")
            .header("Authorization", "Bearer " + apiKey)
            .accept(MediaType.APPLICATION_JSON)
            .retrieve()
            .bodyToMono(String.class)
            .map(r -> true)
            .onErrorReturn(false);
    }

    @Override
    public String getDefaultApiEndpoint() {
        return DEFAULT_API_ENDPOINT;
    }
}




