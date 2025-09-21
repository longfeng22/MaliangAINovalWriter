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
 * OpenAI提供商能力检测器
 */
@Slf4j
@Component
public class OpenAICapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://api.openai.com/v1";

    @Override
    public String getProviderName() {
        return "openai";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        // OpenAI需要API密钥才能获取模型列表
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        // 直接返回静态模型列表（与OpenAITokenPricingCalculator保持一致）
        List<ModelInfo> models = new ArrayList<>();

        // GPT-5 family
        models.add(ModelInfo.builder()
            .id("gpt-5")
            .name("GPT-5")
            .description("OpenAI GPT-5 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00125)
            .withOutputPrice(0.01000));

        models.add(ModelInfo.builder()
            .id("gpt-5-mini")
            .name("GPT-5 Mini")
            .description("OpenAI GPT-5 Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00025)
            .withOutputPrice(0.00200));

        models.add(ModelInfo.builder()
            .id("gpt-5-nano")
            .name("GPT-5 Nano")
            .description("OpenAI GPT-5 Nano 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00005)
            .withOutputPrice(0.00040));

        models.add(ModelInfo.builder()
            .id("gpt-5-chat-latest")
            .name("GPT-5 Chat Latest")
            .description("OpenAI GPT-5 Chat Latest 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00125)
            .withOutputPrice(0.01000));

        // GPT-4.1 family
        models.add(ModelInfo.builder()
            .id("gpt-4.1")
            .name("GPT-4.1")
            .description("OpenAI GPT-4.1 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00200)
            .withOutputPrice(0.00800));

        models.add(ModelInfo.builder()
            .id("gpt-4.1-mini")
            .name("GPT-4.1 Mini")
            .description("OpenAI GPT-4.1 Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00040)
            .withOutputPrice(0.00160));

        models.add(ModelInfo.builder()
            .id("gpt-4.1-nano")
            .name("GPT-4.1 Nano")
            .description("OpenAI GPT-4.1 Nano 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00010)
            .withOutputPrice(0.00040));

        // GPT-4o family
        models.add(ModelInfo.builder()
            .id("gpt-4o")
            .name("GPT-4o")
            .description("OpenAI GPT-4o 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00250)
            .withOutputPrice(0.01000));

        models.add(ModelInfo.builder()
            .id("gpt-4o-2024-05-13")
            .name("GPT-4o 2024-05-13")
            .description("OpenAI GPT-4o 2024-05-13 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00500)
            .withOutputPrice(0.01500));

        models.add(ModelInfo.builder()
            .id("gpt-4o-mini")
            .name("GPT-4o Mini")
            .description("OpenAI GPT-4o Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00015)
            .withOutputPrice(0.00060));

        // Realtime / Audio
        models.add(ModelInfo.builder()
            .id("gpt-realtime")
            .name("GPT Realtime")
            .description("OpenAI GPT Realtime 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00400)
            .withOutputPrice(0.01600));

        models.add(ModelInfo.builder()
            .id("gpt-4o-realtime-preview")
            .name("GPT-4o Realtime Preview")
            .description("OpenAI GPT-4o Realtime Preview 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00500)
            .withOutputPrice(0.02000));

        models.add(ModelInfo.builder()
            .id("gpt-4o-mini-realtime-preview")
            .name("GPT-4o Mini Realtime Preview")
            .description("OpenAI GPT-4o Mini Realtime Preview 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00060)
            .withOutputPrice(0.00240));

        models.add(ModelInfo.builder()
            .id("gpt-audio")
            .name("GPT Audio")
            .description("OpenAI GPT Audio 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00250)
            .withOutputPrice(0.01000));

        models.add(ModelInfo.builder()
            .id("gpt-4o-audio-preview")
            .name("GPT-4o Audio Preview")
            .description("OpenAI GPT-4o Audio Preview 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00250)
            .withOutputPrice(0.01000));

        models.add(ModelInfo.builder()
            .id("gpt-4o-mini-audio-preview")
            .name("GPT-4o Mini Audio Preview")
            .description("OpenAI GPT-4o Mini Audio Preview 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00015)
            .withOutputPrice(0.00060));

        // o family
        models.add(ModelInfo.builder()
            .id("o1")
            .name("o1")
            .description("OpenAI o1 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.01500)
            .withOutputPrice(0.06000));

        models.add(ModelInfo.builder()
            .id("o1-pro")
            .name("o1 Pro")
            .description("OpenAI o1 Pro 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.15000)
            .withOutputPrice(0.60000));

        models.add(ModelInfo.builder()
            .id("o3-pro")
            .name("o3 Pro")
            .description("OpenAI o3 Pro 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.02000)
            .withOutputPrice(0.08000));

        models.add(ModelInfo.builder()
            .id("o3")
            .name("o3")
            .description("OpenAI o3 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00200)
            .withOutputPrice(0.00800));

        models.add(ModelInfo.builder()
            .id("o3-deep-research")
            .name("o3 Deep Research")
            .description("OpenAI o3 Deep Research 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.01000)
            .withOutputPrice(0.04000));

        models.add(ModelInfo.builder()
            .id("o4-mini")
            .name("o4 Mini")
            .description("OpenAI o4 Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00110)
            .withOutputPrice(0.00440));

        models.add(ModelInfo.builder()
            .id("o4-mini-deep-research")
            .name("o4 Mini Deep Research")
            .description("OpenAI o4 Mini Deep Research 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00200)
            .withOutputPrice(0.00800));

        models.add(ModelInfo.builder()
            .id("o3-mini")
            .name("o3 Mini")
            .description("OpenAI o3 Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00110)
            .withOutputPrice(0.00440));

        models.add(ModelInfo.builder()
            .id("o1-mini")
            .name("o1 Mini")
            .description("OpenAI o1 Mini 模型")
            .maxTokens(128000)
            .provider("openai")
            .build()
            .withInputPrice(0.00110)
            .withOutputPrice(0.00440));

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