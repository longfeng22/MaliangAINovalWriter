package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;

import reactor.core.publisher.Mono;

@Component
public class DoubaoTokenPricingCalculator extends AbstractTokenPricingCalculator {

    private static final String PROVIDER_NAME = "doubao";

    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }

    @Override
    public reactor.core.publisher.Mono<java.math.BigDecimal> calculateTotalCost(String modelId, int inputTokens, int outputTokens) {
        String id = modelId != null ? modelId.toLowerCase() : "";
        // 更新seed 1.6系列的匹配逻辑，支持带版本号的模型ID格式 doubao-seed-1-6-xxx-xxxxxx
        if (id.startsWith("doubao-seed-1-6")) {
            return reactor.core.publisher.Mono.just(computeSeed16Cost(id, inputTokens, outputTokens));
        }
        // 1.5 与通用 LLM 列表按固定价目，更新为带版本号的模型ID匹配
        if (id.startsWith("doubao-1.5") || id.startsWith("doubao-pro") || id.startsWith("doubao-lite")
                || id.startsWith("deepseek-v3-1-") || id.startsWith("deepseek-r1-") || id.startsWith("deepseek-v3-") || id.startsWith("kimi-k2-")
                || id.equals("doubao-seed-translation")) {
            return super.calculateTotalCost(modelId, inputTokens, outputTokens);
        }
        return super.calculateTotalCost(modelId, inputTokens, outputTokens);
    }

    /**
     * 计算 doubao-seed-1.6 系列按区间的费用。
     * 价格单位：元/百万 token。
     * @return 返回USD成本
     */
    private java.math.BigDecimal computeSeed16Cost(String modelId, int inputTokens, int outputTokens) {
        double inK = inputTokens / 1000.0;     // 千token
        double outK = outputTokens / 1000.0;   // 千token

        // 默认单价（兜底）
        double inPricePerMillion = 0.8;  // 元/百万token
        double outPricePerMillion = 8.0; // 元/百万token

        boolean isVision = modelId.contains("vision");
        boolean isThinking = modelId.contains("thinking");
        boolean isFlash = modelId.contains("flash");

        if (isVision) {
            // doubao-seed-1.6-vision
            if (inK <= 32) { inPricePerMillion = 0.8; outPricePerMillion = 8.0; }
            else if (inK <= 128) { inPricePerMillion = 1.2; outPricePerMillion = 16.0; }
            else { inPricePerMillion = 2.4; outPricePerMillion = 24.0; }
        } else if (isFlash) {
            // doubao-seed-1.6-flash
            if (inK <= 32) { inPricePerMillion = 0.15; outPricePerMillion = 1.5; }
            else if (inK <= 128) { inPricePerMillion = 0.30; outPricePerMillion = 3.0; }
            else { inPricePerMillion = 0.60; outPricePerMillion = 6.0; }
        } else if (isThinking) {
            // doubao-seed-1.6-thinking
            if (inK <= 32) { inPricePerMillion = 0.8; outPricePerMillion = 8.0; }
            else if (inK <= 128) { inPricePerMillion = 1.2; outPricePerMillion = 16.0; }
            else { inPricePerMillion = 2.4; outPricePerMillion = 24.0; }
        } else {
            // doubao-seed-1.6 标准款，输入[0,32]时按输出长度分段
            if (inK <= 32) {
                if (outK <= 0.2) { // 输出<=0.2千token（<=200 token）
                    inPricePerMillion = 0.8; outPricePerMillion = 2.0;
                } else {
                    inPricePerMillion = 0.8; outPricePerMillion = 8.0;
                }
            } else if (inK <= 128) {
                inPricePerMillion = 1.2; outPricePerMillion = 16.0;
            } else {
                inPricePerMillion = 2.4; outPricePerMillion = 24.0;
            }
        }

        // 计算人民币成本
        double costInCNY = (inputTokens / 1_000_000.0) * inPricePerMillion
                + (outputTokens / 1_000_000.0) * outPricePerMillion;
        
        // 转换为USD（1 USD = 7.0 CNY）
        final double CNY_TO_USD_RATE = 7.0;
        double costInUSD = costInCNY / CNY_TO_USD_RATE;
        
        return java.math.BigDecimal.valueOf(costInUSD).setScale(PRECISION, ROUNDING_MODE);
    }

    public Mono<List<ModelPricing>> getDefaultDoubaoPricing() {
        // 价格为示例占位，建议后续以官方价目更新（或接入实时拉取）
        // 更新为带版本号的正确模型ID
        List<ModelPricing> defaults = List.of(
            // seed 1.6 分段价（以基准段落为主，详细分段逻辑通过重载计算实现）
            create("doubao-seed-1-6-vision-250815", "doubao-seed-1.6-vision", 0.8, 8.0, 256000, "分段计费（0-32K/32-128K/128-256K）"),
            create("doubao-seed-1-6-250615", "doubao-seed-1.6", 0.8, 8.0, 256000, "分段计费（含输出<=0.2K差异）"),
            create("doubao-seed-1-6-thinking-250715", "doubao-seed-1.6-thinking", 0.8, 8.0, 256000, "分段计费（0-32K/32-128K/128-256K）"),
            create("doubao-seed-1-6-flash-250828", "doubao-seed-1.6-flash", 0.15, 1.5, 256000, "分段计费（0-32K/32-128K/128-256K）"),
            create("doubao-seed-1-6-flash-250715", "doubao-seed-1.6-flash-250715", 0.15, 1.5, 256000, "分段计费（0-32K/32-128K/128-256K）"),

            // LLM 在线推理固价（示例）
            create("doubao-seed-translation", "doubao-seed-translation", 1.2, 3.6, 128000, "翻译专用"),
            create("doubao-1.5-pro-32k", "doubao-1.5-pro-32k", 0.8, 2.0, 32000, "1.5 Pro 32K"),
            create("doubao-1.5-pro-256k", "doubao-1.5-pro-256k", 5.0, 9.0, 256000, "1.5 Pro 256K"),
            create("doubao-1.5-lite-32k", "doubao-1.5-lite-32k", 0.3, 0.6, 32000, "1.5 Lite 32K"),
            create("doubao-pro-32k", "doubao-pro-32k", 0.8, 2.0, 32000, "Pro 32K"),
            create("doubao-lite-32k", "doubao-lite-32k", 0.3, 0.6, 32000, "Lite 32K"),

            // 第三方在Doubao平台售卖（示例） - 更新为带版本号的模型ID
            create("kimi-k2-250905", "kimi-k2", 4.0, 16.0, 128000, "Kimi K2 on Doubao"),
            create("deepseek-v3-250324", "deepseek-v3", 2.0, 8.0, 128000, "DeepSeek V3 on Doubao"),
            create("deepseek-v3-1-terminus", "deepseek-v3.1", 4.0, 12.0, 128000, "DeepSeek V3.1 on Doubao"),
            create("deepseek-r1-250528", "deepseek-r1", 4.0, 16.0, 128000, "DeepSeek R1 on Doubao")
        );
        return Mono.just(defaults);
    }

    /**
     * 创建定价信息
     * @param inPrice 输入价格（元/百万tokens）
     * @param outPrice 输出价格（元/百万tokens）
     * @return 转换后的ModelPricing（USD/1K tokens）
     */
    private ModelPricing create(String modelId, String name, double inPrice, double outPrice, int maxTokens, String desc) {
        // 转换单位：元/百万tokens → USD/1K tokens
        // 公式：(CNY per million) / 1000 / exchange_rate = USD per 1K
        // 假设汇率：1 USD = 7.0 CNY
        final double CNY_TO_USD_RATE = 7.0;
        final double MILLION_TO_THOUSAND = 1000.0;
        
        double inputPriceUsdPerThousand = inPrice / MILLION_TO_THOUSAND / CNY_TO_USD_RATE;
        double outputPriceUsdPerThousand = outPrice / MILLION_TO_THOUSAND / CNY_TO_USD_RATE;
        
        return ModelPricing.builder()
            .provider(PROVIDER_NAME)
            .modelId(modelId)
            .modelName(name)
            .inputPricePerThousandTokens(inputPriceUsdPerThousand)
            .outputPricePerThousandTokens(outputPriceUsdPerThousand)
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
        return getDefaultDoubaoPricing()
            .flatMapMany(reactor.core.publisher.Flux::fromIterable)
            .filter(p -> p.getModelId().equals(modelId))
            .next();
    }
}
