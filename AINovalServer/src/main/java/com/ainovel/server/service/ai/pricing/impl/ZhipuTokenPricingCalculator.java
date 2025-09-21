package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;

import reactor.core.publisher.Mono;

@Component
public class ZhipuTokenPricingCalculator extends AbstractTokenPricingCalculator {

    private static final String PROVIDER_NAME = "zhipu";

    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }

    public Mono<List<ModelPricing>> getDefaultZhipuPricing() {
        // 价格为示例占位，建议按官方价目更新
        List<ModelPricing> defaults = List.of(
            create("glm-4.5", "GLM-4.5", 2.0, 8.0, 128000, "GLM-4.5 高智能旗舰（示例价，元/百万Tok）"),
            create("glm-4.5-x", "GLM-4.5-X", 8.0, 16.0, 128000, "GLM-4.5-X 极速（示例价）"),
            create("glm-4.5-air", "GLM-4.5-Air", 0.8, 2.0, 128000, "GLM-4.5-Air 高性价比（示例价）"),
            create("glm-4.5-airx", "GLM-4.5-AirX", 4.0, 12.0, 128000, "GLM-4.5-AirX 极速性价比（示例价）"),
            create("glm-4.5-flash", "GLM-4.5-Flash", 0.0, 0.0, 128000, "GLM-4.5-Flash 免费（示例价）"),
            create("glm-4-plus", "GLM-4-Plus", 4.0, 16.0, 128000, "GLM-4-Plus（示例价）"),
            create("glm-4-air-250414", "GLM-4-Air-250414", 1.2, 8.0, 128000, "GLM-4-Air-250414（示例价）"),
            create("glm-4-long", "GLM-4-Long", 4.0, 16.0, 1000000, "GLM-4-Long 1M上下文（示例价）"),
            create("glm-4-airx", "GLM-4-AirX", 4.0, 16.0, 8000, "GLM-4-AirX（示例价）"),
            create("glm-4-flashx-250414", "GLM-4-FlashX-250414", 0.4, 1.6, 128000, "GLM-4-FlashX-250414（示例价）"),
            create("glm-z1-air", "GLM-Z1-Air", 0.8, 2.0, 128000, "GLM-Z1-Air（示例价）"),
            create("glm-z1-airx", "GLM-Z1-AirX", 4.0, 12.0, 32000, "GLM-Z1-AirX（示例价）"),
            create("glm-z1-flashx", "GLM-Z1-FlashX", 0.4, 1.6, 128000, "GLM-Z1-FlashX（示例价）")
        );
        return Mono.just(defaults);
    }

    private ModelPricing create(String modelId, String name, double inPrice, double outPrice, int maxTokens, String desc) {
        return ModelPricing.builder()
            .provider(PROVIDER_NAME)
            .modelId(modelId)
            .modelName(name)
            .inputPricePerThousandTokens(inPrice)
            .outputPricePerThousandTokens(outPrice)
            .maxContextTokens(maxTokens)
            .supportsStreaming(true)
            .description(desc)
            .source(ModelPricing.PricingSource.DEFAULT)
            .createdAt(LocalDateTime.now())
            .updatedAt(LocalDateTime.now())
            .version(1)
            .active(true)
            .build();
    }

    @Override
    protected Mono<ModelPricing> getDefaultPricing(String modelId) {
        return getDefaultZhipuPricing()
            .flatMapMany(reactor.core.publisher.Flux::fromIterable)
            .filter(p -> p.getModelId().equals(modelId))
            .next();
    }
}


