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
 * 智谱AI 能力检测器 - OpenAI兼容端点
 */
@Slf4j
@Component
public class ZhipuCapabilityDetector implements ProviderCapabilityDetector {

    private static final String DEFAULT_API_ENDPOINT = "https://open.bigmodel.cn/api/paas/v4";

    @Override
    public String getProviderName() {
        return "zhipu";
    }

    @Override
    public Mono<ModelListingCapability> detectModelListingCapability() {
        return Mono.just(ModelListingCapability.LISTING_WITH_KEY);
    }

    @Override
    public Flux<ModelInfo> getDefaultModels() {
        List<ModelInfo> models = new ArrayList<>();

        // 4.5 旗舰系列
        models.add(ModelInfo.builder()
            .id("glm-4.5")
            .name("GLM-4.5")
            .description("高智能旗舰，性能最优，强推理/代码/工具调用")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 96000)
            .withProperty("tags", java.util.List.of("旗舰","推理","代码","工具调用")));

        models.add(ModelInfo.builder()
            .id("glm-4.5-x")
            .name("GLM-4.5-X")
            .description("高智能旗舰-极速版，更快推理，适合实时问答/助手/翻译")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 96000)
            .withProperty("tags", java.util.List.of("旗舰","极速","助手","翻译")));

        // 4.5 高性价比系列
        models.add(ModelInfo.builder()
            .id("glm-4.5-air")
            .name("GLM-4.5-Air")
            .description("高性价比，同参数规模性能佳，推理/编码/智能体表现强")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 96000)
            .withProperty("tags", java.util.List.of("性价比","推理","编码","智能体")));

        models.add(ModelInfo.builder()
            .id("glm-4.5-airx")
            .name("GLM-4.5-AirX")
            .description("高性价比-极速版，速度快且价格适中，适合时效性场景")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 96000)
            .withProperty("tags", java.util.List.of("性价比","极速","时效性")));

        // 4.5 免费/Flash 系列
        models.add(ModelInfo.builder()
            .id("glm-4.5-flash")
            .name("GLM-4.5-Flash")
            .description("免费模型，4.5基座普惠版，极速推理")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 96000)
            .withProperty("tags", java.util.List.of("免费","极速","普惠")));

        // 4.x 现役产品线（保留）
        models.add(ModelInfo.builder()
            .id("glm-4-plus")
            .name("GLM-4-Plus")
            .description("性能优秀，理解/推理/指令/长文本处理强")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 4000)
            .withProperty("tags", java.util.List.of("性能","长文本")));

        models.add(ModelInfo.builder()
            .id("glm-4-air-250414")
            .name("GLM-4-Air-250414")
            .description("高性价比，善工具/联网/代码，快速执行")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 16000)
            .withProperty("tags", java.util.List.of("性价比","工具","联网","代码")));

        models.add(ModelInfo.builder()
            .id("glm-4-long")
            .name("GLM-4-Long")
            .description("超长输入，1M上下文，适合长文与记忆任务")
            .maxTokens(1000000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 4000)
            .withProperty("tags", java.util.List.of("长上下文","1M")));

        models.add(ModelInfo.builder()
            .id("glm-4-airx")
            .name("GLM-4-AirX")
            .description("极速推理，推理速度极快，效果强")
            .maxTokens(8000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 4000)
            .withProperty("tags", java.util.List.of("极速","推理")));

        models.add(ModelInfo.builder()
            .id("glm-4-flashx-250414")
            .name("GLM-4-FlashX-250414")
            .description("高速低价，Flash增强版，更强并发保障")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 16000)
            .withProperty("tags", java.util.List.of("高速","低价","并发")));

        // Z1 系列
        models.add(ModelInfo.builder()
            .id("glm-z1-air")
            .name("GLM-Z1-Air")
            .description("高性价比，具备深度思考，数理推理增强")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 32000)
            .withProperty("tags", java.util.List.of("性价比","深度思考","数理")));

        models.add(ModelInfo.builder()
            .id("glm-z1-airx")
            .name("GLM-Z1-AirX")
            .description("极速推理，国内最快，支持8倍推理速度")
            .maxTokens(32000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 30000)
            .withProperty("tags", java.util.List.of("极速","8x")));

        models.add(ModelInfo.builder()
            .id("glm-z1-flashx")
            .name("GLM-Z1-FlashX")
            .description("高速低价，超快推理，更强并发保障")
            .maxTokens(128000)
            .provider("zhipu")
            .build()
            .withProperty("max_output", 32000)
            .withProperty("tags", java.util.List.of("高速","低价","并发")));

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




