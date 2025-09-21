package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;

import reactor.core.publisher.Mono;

@Component
public class GrokTokenPricingCalculator extends AbstractTokenPricingCalculator {

    private static final String PROVIDER_NAME = "x-ai";

    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }

    public Mono<List<ModelPricing>> getDefaultGrokPricing() {
        List<ModelPricing> defaults = List.of(
            create("x-ai/grok-3-beta", "Grok 3 Beta", 0.003, 0.006, 131072, "Grok 3 Beta 通用模型"),
            create("x-ai/grok-3", "Grok 3", 0.003, 0.006, 131072, "Grok 3 通用模型"),
            create("x-ai/grok-3-fast", "Grok 3 Fast", 0.0015, 0.003, 131072, "Grok 3 Fast 高速版"),
            create("x-ai/grok-3-mini", "Grok 3 Mini", 0.0006, 0.0012, 131072, "Grok 3 Mini 轻量版"),
            create("x-ai/grok-3-mini-fast", "Grok 3 Mini Fast", 0.0003, 0.0006, 131072, "Grok 3 Mini Fast 更高速版本"),
            create("x-ai/grok-2-vision-1212", "Grok 2 Vision", 0.003, 0.006, 131072, "Grok 2 视觉模型")
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
        return getDefaultGrokPricing()
            .flatMapMany(reactor.core.publisher.Flux::fromIterable)
            .filter(p -> p.getModelId().equals(modelId))
            .next();
    }
}
