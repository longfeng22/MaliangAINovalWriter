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
 * 豆包（火山引擎 Ark）能力检测器 - OpenAI兼容
 */
@Slf4j
@Component
public class DoubaoCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://ark.cn-beijing.volces.com/api/v3";

    @Override
    public String getProviderName() {
        return "doubao";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        List<ModelInfo> models = new ArrayList<>();

        // Ark Endpoint 占位
        models.add(ModelInfo.builder()
            .id("ep-2025-01-ark")
            .name("Ark Endpoint")
            .description("方舟 Endpoint ID 作为模型占位，具体模型由端点决定")
            .maxTokens(128000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("endpoint","ark")));

        // seed 1.6 分段计费系列（按输入/输出长度分档）- 使用正确的带版本号的模型ID
        models.add(ModelInfo.builder()
            .id("doubao-seed-1-6-vision-250815")
            .name("doubao-seed-1.6-vision")
            .description("seed 1.6 视觉模型（推荐250815版本），支持深度思考、图片理解、视频理解、GUI任务处理")
            .maxTokens(256000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("seed-1.6","vision","tiered-pricing","thinking","recommended")));

        models.add(ModelInfo.builder()
            .id("doubao-seed-1-6-250615")
            .name("doubao-seed-1.6")
            .description("seed 1.6 标准模型（推荐250615版本），支持深度思考、文本生成、图片理解、视频理解")
            .maxTokens(256000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("seed-1.6","tiered-pricing","thinking","recommended")));

        models.add(ModelInfo.builder()
            .id("doubao-seed-1-6-thinking-250715")
            .name("doubao-seed-1.6-thinking")
            .description("seed 1.6 思维链模型（250715版本），专注深度思考、图片理解、视频理解")
            .maxTokens(256000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("seed-1.6","thinking","tiered-pricing")));

        models.add(ModelInfo.builder()
            .id("doubao-seed-1-6-flash-250828")
            .name("doubao-seed-1.6-flash")
            .description("seed 1.6 Flash模型（推荐250828版本），高速低价，支持深度思考、视觉定位")
            .maxTokens(256000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("seed-1.6","flash","tiered-pricing","thinking","recommended")));

        // 添加250715版本的flash模型作为备选
        models.add(ModelInfo.builder()
            .id("doubao-seed-1-6-flash-250715")
            .name("doubao-seed-1.6-flash-250715")
            .description("seed 1.6 Flash模型（250715版本），支持深度思考、视觉定位")
            .maxTokens(256000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("seed-1.6","flash","tiered-pricing","thinking")));

        // LLM 在线推理固价（示例）
        models.add(ModelInfo.builder()
            .id("doubao-seed-translation")
            .name("doubao-seed-translation")
            .description("翻译专用模型")
            .maxTokens(128000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("translation")));

        models.add(ModelInfo.builder()
            .id("doubao-1.5-pro-32k")
            .name("doubao-1.5-pro-32k")
            .description("1.5 Pro 32K")
            .maxTokens(32000)
            .provider("doubao")
            .build());

        models.add(ModelInfo.builder()
            .id("doubao-1.5-pro-256k")
            .name("doubao-1.5-pro-256k")
            .description("1.5 Pro 256K")
            .maxTokens(256000)
            .provider("doubao")
            .build());

        models.add(ModelInfo.builder()
            .id("doubao-1.5-lite-32k")
            .name("doubao-1.5-lite-32k")
            .description("1.5 Lite 32K")
            .maxTokens(32000)
            .provider("doubao")
            .build());

        models.add(ModelInfo.builder()
            .id("doubao-pro-32k")
            .name("doubao-pro-32k")
            .description("Pro 32K")
            .maxTokens(32000)
            .provider("doubao")
            .build());

        models.add(ModelInfo.builder()
            .id("doubao-lite-32k")
            .name("doubao-lite-32k")
            .description("Lite 32K")
            .maxTokens(32000)
            .provider("doubao")
            .build());

        // 第三方在 Doubao 平台的主流模型 - 使用正确的带版本号的模型ID
        models.add(ModelInfo.builder()
            .id("deepseek-v3-1-terminus")
            .name("deepseek-v3.1")
            .description("DeepSeek V3.1模型（推荐版本），支持深度思考、文本生成、工具调用")
            .maxTokens(128000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("third-party","thinking","recommended")));

        models.add(ModelInfo.builder()
            .id("deepseek-r1-250528")
            .name("deepseek-r1")
            .description("DeepSeek R1模型（250528版本），支持深度思考、工具调用")
            .maxTokens(96000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("third-party","thinking")));

        models.add(ModelInfo.builder()
            .id("deepseek-v3-250324")
            .name("deepseek-v3")
            .description("DeepSeek V3模型（250324版本），支持文本生成、工具调用")
            .maxTokens(128000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("third-party")));

        models.add(ModelInfo.builder()
            .id("kimi-k2-250905")
            .name("kimi-k2")
            .description("Kimi K2模型（推荐250905版本），支持文本生成、工具调用")
            .maxTokens(128000)
            .provider("doubao")
            .build()
            .withProperty("tags", java.util.List.of("third-party","recommended")));

        return Flux.fromIterable(models);
    }

    @Override
    public Mono<Boolean> testApiKey(String apiKey, String apiEndpoint) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            return Mono.just(false);
        }
        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ? apiEndpoint : DEFAULT_API_ENDPOINT;
        WebClient webClient = WebClient.builder().baseUrl(baseUrl).build();

        // 优先尝试 OpenAI 兼容的 /models 列表
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




