package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * Anthropic Token定价计算器
 * 目前使用静态定价数据，因为Anthropic没有公开的定价API
 */
@Slf4j
@Component
public class AnthropicTokenPricingCalculator extends AbstractTokenPricingCalculator {
    
    private static final String PROVIDER_NAME = "anthropic";
    
    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }
    
    /**
     * 获取Anthropic模型的默认定价信息
     * 基于2025年1月最新官方价格
     * 
     * @return 默认定价信息列表
     */
    public Mono<List<ModelPricing>> getDefaultAnthropicPricing() {
        List<ModelPricing> defaultPricing = List.of(
                // Latest Models
                createDefaultPricingWithCaching("claude-4.1-opus", "Opus 4.1", 
                        15.0, 75.0, 200000, "最智能的模型，适合复杂任务",
                        18.75, 1.50), // Prompt caching prices
                
                createDefaultPricingWithTieredCaching("claude-4-sonnet", "Sonnet 4", 
                        3.0, 15.0, 6.0, 22.50, 200000, "智能、成本和速度的最优平衡",
                        3.75, 0.30, 7.50, 0.60), // Tiered prompt caching
                
                createDefaultPricingWithCaching("claude-3.5-haiku", "Haiku 3.5", 
                        0.80, 4.0, 200000, "最快、最经济高效的模型",
                        1.0, 0.08), // Prompt caching prices
                
                // Legacy Models
                createDefaultPricingWithCaching("claude-3-opus-20240229", "Opus 3", 
                        15.0, 75.0, 200000, "Claude 3 Opus遗留模型",
                        18.75, 1.50),
                
                createDefaultPricingWithCaching("claude-3.7-sonnet", "Sonnet 3.7", 
                        3.0, 15.0, 200000, "Claude 3.7 Sonnet遗留模型",
                        3.75, 0.30),
                
                createDefaultPricingWithCaching("claude-3-haiku-20240307", "Haiku 3", 
                        0.25, 1.25, 200000, "Claude 3 Haiku遗留模型",
                        0.30, 0.03)
        );
        
        return Mono.just(defaultPricing);
    }
    
    /**
     * 创建默认定价信息
     */
    private ModelPricing createDefaultPricing(String modelId, String modelName, 
                                            double inputPrice, double outputPrice, 
                                            int maxTokens, String description) {
        return ModelPricing.builder()
                .provider(PROVIDER_NAME)
                .modelId(modelId)
                .modelName(modelName)
                .inputPricePerThousandTokens(inputPrice)
                .outputPricePerThousandTokens(outputPrice)
                .maxContextTokens(maxTokens)
                .supportsStreaming(true)
                .description(description)
                .source(ModelPricing.PricingSource.DEFAULT)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .version(1)
                .active(true)
                .build();
    }
    
    /**
     * 创建带Prompt Caching的定价信息
     */
    private ModelPricing createDefaultPricingWithCaching(String modelId, String modelName, 
                                                       double inputPrice, double outputPrice, 
                                                       int maxTokens, String description,
                                                       double cacheWritePrice, double cacheReadPrice) {
        ModelPricing pricing = createDefaultPricing(modelId, modelName, inputPrice, outputPrice, maxTokens, description);
        
        // 添加Prompt Caching价格信息（确保map非空）
        if (pricing.getAdditionalPricing() == null) {
            pricing.setAdditionalPricing(new java.util.HashMap<>());
        }
        pricing.getAdditionalPricing().put("prompt_cache_write", cacheWritePrice);
        pricing.getAdditionalPricing().put("prompt_cache_read", cacheReadPrice);
        pricing.getAdditionalPricing().put("supports_prompt_caching", 1.0); // Use 1.0 for true
        
        return pricing;
    }
    
    /**
     * 创建分层定价信息（Sonnet 4）
     */
    private ModelPricing createDefaultPricingWithTieredCaching(String modelId, String modelName,
                                                             double inputPriceSmall, double outputPriceSmall,
                                                             double inputPriceLarge, double outputPriceLarge,
                                                             int maxTokens, String description,
                                                             double cacheWriteSmall, double cacheReadSmall,
                                                             double cacheWriteLarge, double cacheReadLarge) {
        ModelPricing pricing = createDefaultPricing(modelId, modelName, inputPriceSmall, outputPriceSmall, maxTokens, description);
        
        // 添加分层定价信息（确保map非空）
        if (pricing.getAdditionalPricing() == null) {
            pricing.setAdditionalPricing(new java.util.HashMap<>());
        }
        pricing.getAdditionalPricing().put("tiered_pricing", 1.0); // Use 1.0 for true
        pricing.getAdditionalPricing().put("input_price_large", inputPriceLarge);
        pricing.getAdditionalPricing().put("output_price_large", outputPriceLarge);
        pricing.getAdditionalPricing().put("tier_threshold", 200000.0); // 200K tokens as double
        
        // Prompt Caching价格
        pricing.getAdditionalPricing().put("cache_write_small", cacheWriteSmall);
        pricing.getAdditionalPricing().put("cache_read_small", cacheReadSmall);
        pricing.getAdditionalPricing().put("cache_write_large", cacheWriteLarge);
        pricing.getAdditionalPricing().put("cache_read_large", cacheReadLarge);
        pricing.getAdditionalPricing().put("supports_prompt_caching", 1.0); // Use 1.0 for true
        
        return pricing;
    }
    
    /**
     * 根据模型ID获取特定的定价信息
     * 
     * @param modelId 模型ID
     * @return 定价信息
     */
    @Override
    protected Mono<ModelPricing> getDefaultPricing(String modelId) {
        return getDefaultAnthropicPricing()
                .flatMapMany(reactor.core.publisher.Flux::fromIterable)
                .filter(pricing -> pricing.getModelId().equals(modelId))
                .next();
    }
    
    /**
     * 批量更新Anthropic定价信息
     * 
     * @return 更新结果
     */
    public Mono<Void> updateAllPricing() {
        log.info("Updating Anthropic pricing information...");
        
        return getDefaultAnthropicPricing()
                .flatMap(super::batchSavePricing)
                .doOnSuccess(unused -> log.info("Successfully updated Anthropic pricing"))
                .doOnError(error -> log.error("Failed to update Anthropic pricing", error));
    }
    
    /**
     * 检查模型是否为Claude模型
     * 
     * @param modelId 模型ID
     * @return 是否为Claude模型
     */
    public boolean isClaudeModel(String modelId) {
        return modelId != null && 
               (modelId.startsWith("claude-") || 
                modelId.contains("claude") || 
                modelId.startsWith("anthropic"));
    }
    
    /**
     * 获取模型类型（Haiku, Sonnet, Opus等）
     */
    public String getModelType(String modelId) {
        if (modelId.contains("haiku")) {
            return "haiku";
        } else if (modelId.contains("sonnet")) {
            return "sonnet";
        } else if (modelId.contains("opus")) {
            return "opus";
        } else if (modelId.contains("instant")) {
            return "instant";
        } else if (modelId.contains("claude-2")) {
            return "claude-2";
        } else {
            return "unknown";
        }
    }
    
    /**
     * 检查模型是否支持Prompt Caching
     */
    public boolean supportsPromptCaching(String modelId) {
        // 所有新模型都支持Prompt Caching
        return !modelId.contains("claude-2") && !modelId.contains("instant");
    }
    
    /**
     * 检查模型是否使用分层定价
     */
    public boolean usesTieredPricing(String modelId) {
        return modelId.contains("claude-4-sonnet");
    }
    
    /**
     * 获取模型的建议用途
     */
    public String getModelRecommendation(String modelId) {
        String type = getModelType(modelId);
        return switch (type) {
            case "haiku" -> "适合快速响应和大批量处理任务";
            case "sonnet" -> "适合平衡性能和成本的日常工作";
            case "opus" -> "适合需要最高质量输出的复杂任务";
            case "instant" -> "适合需要快速响应的简单任务";
            case "claude-2" -> "通用型模型，适合各种文本任务";
            default -> "通用AI助手模型";
        };
    }
    
    /**
     * 计算Prompt Caching成本
     */
    public Mono<Double> calculatePromptCachingCost(String modelId, int cacheWriteTokens, int cacheReadTokens) {
        return getDefaultAnthropicPricing()
                .flatMapMany(reactor.core.publisher.Flux::fromIterable)
                .filter(pricing -> pricing.getModelId().equals(modelId))
                .next()
                .map(pricing -> {
                    Double writePrice = (Double) pricing.getAdditionalPricing().get("prompt_cache_write");
                    Double readPrice = (Double) pricing.getAdditionalPricing().get("prompt_cache_read");
                    
                    if (writePrice == null || readPrice == null) {
                        return 0.0;
                    }
                    
                    double writeCost = (cacheWriteTokens / 1000.0) * writePrice;
                    double readCost = (cacheReadTokens / 1000.0) * readPrice;
                    
                    return writeCost + readCost;
                })
                .defaultIfEmpty(0.0);
    }
}