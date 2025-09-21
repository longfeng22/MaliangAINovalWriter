package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;

import reactor.core.publisher.Mono;

@Component
public class QwenTokenPricingCalculator extends AbstractTokenPricingCalculator {

    private static final String PROVIDER_NAME = "qwen";

    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }

    /**
     * 通义千问（文本）阶梯/固定定价计算（人民币）。
     * 约定：未区分“思考模式”，默认按“非思考模式”单价计费；
     * 若需思考模式计费，可在后续扩展中区分模型ID或传入请求标志。
     */
    @Override
    public reactor.core.publisher.Mono<java.math.BigDecimal> calculateTotalCost(String modelId, int inputTokens, int outputTokens) {
        if (modelId == null) {
            return super.calculateTotalCost(modelId, inputTokens, outputTokens);
        }
        String id = modelId.toLowerCase();

        // qwen3-max-preview：按输入Token阶梯计价（0-32K / 32-128K / 128-252K）
        if ("qwen3-max-preview".equals(id)) {
            return Mono.just(computeTieredCost(
                inputTokens,
                outputTokens,
                new int[] { 32_000, 128_000, 252_000 },
                new double[] { 0.006, 0.010, 0.015 },   // input RMB per 1K
                new double[] { 0.024, 0.040, 0.060 }    // output RMB per 1K
            ));
        }

        // qwen-plus 最新/快照（1M 上下文）：按输入Token阶梯计价（0-128K / 128-256K / 256K-1M），默认非思考输出单价
        if ("qwen-plus-latest".equals(id) || "qwen-plus-2025-09-11".equals(id) || "qwen-plus-2025-07-28".equals(id)) {
            return Mono.just(computeTieredCost(
                inputTokens,
                outputTokens,
                new int[] { 128_000, 256_000, 1_000_000 },
                new double[] { 0.0008, 0.0024, 0.0048 }, // input RMB per 1K
                new double[] { 0.0020, 0.0200, 0.0480 }  // output RMB per 1K（非思考）
            ));
        }

        // qwen-plus 稳定版（非思考固定价）
        if ("qwen-plus".equals(id) || "qwen-plus-2025-07-14".equals(id) || "qwen-plus-2025-04-28".equals(id)) {
            return Mono.just(computeFixedCost(inputTokens, outputTokens, 0.0008, 0.0020));
        }

        // qwen-flash（0-128K / 128-256K / 256K-1M 阶梯定价）
        if ("qwen-flash".equals(id) || "qwen-flash-2025-07-28".equals(id)) {
            return Mono.just(computeTieredCost(
                inputTokens,
                outputTokens,
                new int[] { 128_000, 256_000, 1_000_000 },
                new double[] { 0.00015, 0.00060, 0.00120 },
                new double[] { 0.00150, 0.00600, 0.01200 }
            ));
        }

        // qwen-turbo（已不建议，保留兼容：默认按“非思考”近似价处理）
        if ("qwen-turbo".equals(id) || "qwen-turbo-latest".equals(id) || "qwen-turbo-2025-07-15".equals(id)
                || "qwen-turbo-2025-04-28".equals(id)) {
            return Mono.just(computeFixedCost(inputTokens, outputTokens, 0.0006, 0.0030));
        }

        // QwQ 推理（固定价）
        if ("qwq-plus".equals(id) || "qwq-plus-latest".equals(id)) {
            return Mono.just(computeFixedCost(inputTokens, outputTokens, 0.0016, 0.0040));
        }

        // Qwen-Long 1M（固定价）
        if ("qwen-long".equals(id) || "qwen-long-latest".equals(id)) {
            return Mono.just(computeFixedCost(inputTokens, outputTokens, 0.0005, 0.0020));
        }

        return super.calculateTotalCost(modelId, inputTokens, outputTokens);
    }

    private java.math.BigDecimal computeFixedCost(int inputTokens, int outputTokens, double inputPerK, double outputPerK) {
        double cost = (inputTokens / 1000.0) * inputPerK + (outputTokens / 1000.0) * outputPerK;
        return java.math.BigDecimal.valueOf(cost).setScale(PRECISION, ROUNDING_MODE);
    }

    /**
     * 根据输入token所在区间确定价档（包含上界）。
     */
    private java.math.BigDecimal computeTieredCost(int inputTokens, int outputTokens, int[] inputThresholdsInclusive,
            double[] inputPricesPerK, double[] outputPricesPerK) {
        // 阶梯数组长度应一致
        int idx = 0;
        for (int i = 0; i < inputThresholdsInclusive.length; i++) {
            if (inputTokens <= inputThresholdsInclusive[i]) {
                idx = i;
                break;
            }
            // 若超出最后一档，则使用最后一档
            if (i == inputThresholdsInclusive.length - 1) {
                idx = i;
            }
        }
        double inputPerK = inputPricesPerK[Math.min(idx, inputPricesPerK.length - 1)];
        double outputPerK = outputPricesPerK[Math.min(idx, outputPricesPerK.length - 1)];
        double cost = (inputTokens / 1000.0) * inputPerK + (outputTokens / 1000.0) * outputPerK;
        return java.math.BigDecimal.valueOf(cost).setScale(PRECISION, ROUNDING_MODE);
    }

    public Mono<List<ModelPricing>> getDefaultQwenPricing() {
        // 文本模型默认价（人民币/每千Token）；思考模式价以 additionalPricing 记录（默认计算走非思考）。
        List<ModelPricing> defaults = List.of(
            // Max（预览，阶梯定价）
            create("qwen3-max-preview", "Qwen3-Max-Preview", null, null, 262144, "Qwen3 Max 预览，按输入阶梯计价",
                Map.of(
                    "tier1_input_perK", 0.006,
                    "tier1_output_perK", 0.024,
                    "tier2_input_perK", 0.010,
                    "tier2_output_perK", 0.040,
                    "tier3_input_perK", 0.015,
                    "tier3_output_perK", 0.060
                )
            ),

            // Plus（稳定/最新版/快照）
            create("qwen-plus", "Qwen-Plus", 0.0008, 0.0020, 131072, "Qwen-Plus 稳定版（非思考默认）",
                Map.of(
                    "thinking_output_perK", 0.008
                )
            ),
            create("qwen-plus-latest", "Qwen-Plus-Latest", null, null, 1_000_000, "Qwen-Plus 最新版 1M，上下文阶梯定价",
                Map.of(
                    "tier1_input_perK", 0.0008,
                    "tier1_output_perK", 0.0020,
                    "tier1_output_thinking_perK", 0.0080,
                    "tier2_input_perK", 0.0024,
                    "tier2_output_perK", 0.0200,
                    "tier2_output_thinking_perK", 0.0240,
                    "tier3_input_perK", 0.0048,
                    "tier3_output_perK", 0.0480,
                    "tier3_output_thinking_perK", 0.0640
                )
            ),
            create("qwen-plus-2025-09-11", "Qwen-Plus-2025-09-11", null, null, 1_000_000, "Qwen-Plus 快照 2025-09-11（阶梯定价）",
                Map.of(
                    "tier1_input_perK", 0.0008,
                    "tier1_output_perK", 0.0020,
                    "tier2_input_perK", 0.0024,
                    "tier2_output_perK", 0.0200,
                    "tier3_input_perK", 0.0048,
                    "tier3_output_perK", 0.0480
                )
            ),
            create("qwen-plus-2025-07-28", "Qwen-Plus-2025-07-28", null, null, 1_000_000, "Qwen-Plus 快照 2025-07-28（阶梯定价）",
                Map.of(
                    "tier1_input_perK", 0.0008,
                    "tier1_output_perK", 0.0020,
                    "tier2_input_perK", 0.0024,
                    "tier2_output_perK", 0.0200,
                    "tier3_input_perK", 0.0048,
                    "tier3_output_perK", 0.0480
                )
            ),
            create("qwen-plus-2025-07-14", "Qwen-Plus-2025-07-14", 0.0008, 0.0020, 131072, "Qwen-Plus 快照 2025-07-14（非思考默认）",
                Map.of("thinking_output_perK", 0.0080)
            ),
            create("qwen-plus-2025-04-28", "Qwen-Plus-2025-04-28", 0.0008, 0.0020, 98304, "Qwen-Plus 快照 2025-04-28（非思考默认）",
                Map.of("thinking_output_perK", 0.0080)
            ),

            // Flash（阶梯定价）
            create("qwen-flash", "Qwen-Flash", null, null, 1_000_000, "Qwen-Flash 稳定版（阶梯定价）",
                Map.of(
                    "tier1_input_perK", 0.00015,
                    "tier1_output_perK", 0.00150,
                    "tier2_input_perK", 0.00060,
                    "tier2_output_perK", 0.00600,
                    "tier3_input_perK", 0.00120,
                    "tier3_output_perK", 0.01200
                )
            ),
            create("qwen-flash-2025-07-28", "Qwen-Flash-2025-07-28", null, null, 1_000_000, "Qwen-Flash 快照 2025-07-28（阶梯定价）",
                Map.of(
                    "tier1_input_perK", 0.00015,
                    "tier1_output_perK", 0.00150,
                    "tier2_input_perK", 0.00060,
                    "tier2_output_perK", 0.00600,
                    "tier3_input_perK", 0.00120,
                    "tier3_output_perK", 0.01200
                )
            ),

            // Turbo（兼容保留）
            create("qwen-turbo", "Qwen-Turbo", 0.0006, 0.0030, 1_000_000, "Qwen-Turbo（建议改用 Flash）"),
            create("qwen-turbo-latest", "Qwen-Turbo-Latest", 0.0006, 0.0030, 1_000_000, "Qwen-Turbo-Latest（建议改用 Flash）"),
            create("qwen-turbo-2025-07-15", "Qwen-Turbo-2025-07-15", 0.0006, 0.0030, 131072, "Qwen-Turbo 快照 2025-07-15"),
            create("qwen-turbo-2025-04-28", "Qwen-Turbo-2025-04-28", 0.0006, 0.0030, 131072, "Qwen-Turbo 快照 2025-04-28"),

            // QwQ 推理
            create("qwq-plus", "QwQ-Plus", 0.0016, 0.0040, 131072, "QwQ 推理（固定价）"),
            create("qwq-plus-latest", "QwQ-Plus-Latest", 0.0016, 0.0040, 131072, "QwQ 推理（固定价）"),

            // Long 1M 上下文
            create("qwen-long", "Qwen-Long", 0.0005, 0.0020, 10_000_000, "Qwen-Long 1M 上下文（固定价）"),
            create("qwen-long-latest", "Qwen-Long-Latest", 0.0005, 0.0020, 10_000_000, "Qwen-Long 1M 上下文（固定价）")
        );
        return Mono.just(defaults);
    }

    private ModelPricing create(String modelId, String name, Double inPrice, Double outPrice, int maxTokens, String desc) {
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

    private ModelPricing create(String modelId, String name, Double inPrice, Double outPrice, int maxTokens, String desc,
                                Map<String, Double> additional) {
        ModelPricing p = create(modelId, name, inPrice, outPrice, maxTokens, desc);
        if (additional != null && !additional.isEmpty()) {
            p.setAdditionalPricing(additional);
        }
        return p;
    }

    @Override
    protected Mono<ModelPricing> getDefaultPricing(String modelId) {
        return getDefaultQwenPricing()
            .flatMapMany(reactor.core.publisher.Flux::fromIterable)
            .filter(p -> p.getModelId().equals(modelId))
            .next();
    }
}


