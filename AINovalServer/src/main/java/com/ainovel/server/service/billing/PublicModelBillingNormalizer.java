package com.ainovel.server.service.billing;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;

import java.util.Map;

/**
 * 统一规范化公共模型请求的计费标记。
 *
 * 用途：当上游经过工具编排（Tool Orchestration）等路径构建 AIRequest 时，
 * 仅把公共模型相关标记放在 config/metadata 中，监听器无法在 providerSpecific 读取到，
 * 导致后扣费判定失效。该工具在请求发出前，将必要的标记规范化写入 parameters.providerSpecific。
 */
public final class PublicModelBillingNormalizer {

    private PublicModelBillingNormalizer() {}

    public static void normalize(AIRequest request, Map<String, String> config) {
        if (request == null || config == null) return;

        // 工具编排链路跳过计费
        if ("true".equalsIgnoreCase(config.get(BillingKeys.SKIP_BILLING_FOR_TOOL_ORCHESTRATION))) {
            return;
        }

        // 识别公共模型标记
        boolean usedPublic = parseBool(config.get(BillingKeys.USED_PUBLIC_MODEL))
                || parseBool(config.get("isPublicModel")); // 兼容老字段

        String publicCfgId = firstNonEmpty(
                config.get(BillingKeys.PUBLIC_MODEL_CONFIG_ID),
                config.get("publicModelConfigId")
        );

        // 仅在需要后扣费的文本流场景才注入标记；工具编排阶段不做注入
        boolean requiresPostStream = parseBool(config.get(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION));
        String featureType = firstNonEmpty(config.get(BillingKeys.STREAM_FEATURE_TYPE), config.get("streamFeatureType"));
        if (!(usedPublic || !isEmpty(publicCfgId))) {
            return; // 非公共模型
        }
        if (!requiresPostStream || isEmpty(featureType)) {
            return; // 非文本流后扣费场景（如工具编排），不注入
        }
        String provider = firstNonEmpty(config.get(BillingKeys.PROVIDER), config.get("provider"));
        String modelId = firstNonEmpty(config.get(BillingKeys.MODEL_ID), request.getModel());
        String correlationId = config.get(BillingKeys.CORRELATION_ID);
        String idempotencyKey = config.get(BillingKeys.REQUEST_IDEMPOTENCY_KEY);

        PublicModelBillingContext ctx = PublicModelBillingContext.builder()
                .usedPublicModel(true)
                .requiresPostStreamDeduction(requiresPostStream)
                .streamFeatureType(featureType)
                .publicModelConfigId(publicCfgId)
                .provider(provider)
                .modelId(modelId)
                .correlationId(correlationId)
                .idempotencyKey(idempotencyKey)
                .build();

        // 统一注入到 providerSpecific（并可选双写到 metadata）
        BillingMarkerEnricher.applyTo(request, ctx);
    }

    /**
     * 便捷重载：直接传入关键字段，由本方法组装配置并复用 normalize(req, config)。
     */
    public static void normalize(
            AIRequest request,
            boolean usedPublicModel,
            boolean requiresPostStreamDeduction,
            String streamFeatureType,
            String publicModelConfigId,
            String provider,
            String modelId,
            String correlationId,
            String idempotencyKey) {
        java.util.Map<String, String> cfg = new java.util.HashMap<>();
        if (usedPublicModel) cfg.put(BillingKeys.USED_PUBLIC_MODEL, "true");
        if (requiresPostStreamDeduction) cfg.put(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION, "true");
        if (streamFeatureType != null) cfg.put(BillingKeys.STREAM_FEATURE_TYPE, streamFeatureType);
        if (publicModelConfigId != null) cfg.put(BillingKeys.PUBLIC_MODEL_CONFIG_ID, publicModelConfigId);
        if (provider != null) cfg.put(BillingKeys.PROVIDER, provider);
        if (modelId != null) cfg.put(BillingKeys.MODEL_ID, modelId);
        if (correlationId != null) cfg.put(BillingKeys.CORRELATION_ID, correlationId);
        if (idempotencyKey != null) cfg.put(BillingKeys.REQUEST_IDEMPOTENCY_KEY, idempotencyKey);
        normalize(request, cfg);
    }

    /**
     * DTO 便捷重载：在 DTO 层补全 metadata 与 parameters.providerSpecific，
     * 并保持键名与 AIRequest 层一致，底层构建 AIRequest 时仍会再次标准化（双保险）。
     */
    public static void normalize(
            UniversalAIRequestDto dto,
            boolean usedPublicModel,
            boolean requiresPostStreamDeduction,
            String streamFeatureType,
            String publicModelConfigId,
            String provider,
            String modelId,
            String correlationId,
            String idempotencyKey) {
        if (dto == null) return;
        // 工具编排链路跳过计费（若上层已设定）
        Object skip = dto.getParameters() != null ? dto.getParameters().get(BillingKeys.SKIP_BILLING_FOR_TOOL_ORCHESTRATION) : null;
        if (skip != null && "true".equalsIgnoreCase(String.valueOf(skip))) {
            return;
        }
        // 写 metadata
        if (dto.getMetadata() == null) dto.setMetadata(new java.util.HashMap<>());
        if (usedPublicModel) dto.getMetadata().put(BillingKeys.USED_PUBLIC_MODEL, true);
        if (requiresPostStreamDeduction) dto.getMetadata().put(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION, true);
        if (streamFeatureType != null) dto.getMetadata().put(BillingKeys.STREAM_FEATURE_TYPE, streamFeatureType);
        if (publicModelConfigId != null) dto.getMetadata().put(BillingKeys.PUBLIC_MODEL_CONFIG_ID, publicModelConfigId);
        if (provider != null) dto.getMetadata().put(BillingKeys.PROVIDER, provider);
        if (modelId != null) dto.getMetadata().put(BillingKeys.MODEL_ID, modelId);
        if (correlationId != null) dto.getMetadata().put(BillingKeys.CORRELATION_ID, correlationId);
        if (idempotencyKey != null) dto.getMetadata().put(BillingKeys.REQUEST_IDEMPOTENCY_KEY, idempotencyKey);
        // 兼容旧字段
        if (usedPublicModel) dto.getMetadata().put("isPublicModel", true);
        if (publicModelConfigId != null) dto.getMetadata().put("publicModelConfigId", publicModelConfigId);

        // 写 parameters.providerSpecific
        if (dto.getParameters() == null) dto.setParameters(new java.util.HashMap<>());
        @SuppressWarnings("unchecked")
        java.util.Map<String, Object> ps = (java.util.Map<String, Object>) dto.getParameters().computeIfAbsent("providerSpecific", k -> new java.util.HashMap<>());
        if (usedPublicModel) ps.put(BillingKeys.USED_PUBLIC_MODEL, true);
        if (requiresPostStreamDeduction) ps.put(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION, true);
        if (streamFeatureType != null) ps.put(BillingKeys.STREAM_FEATURE_TYPE, streamFeatureType);
        if (publicModelConfigId != null) ps.put(BillingKeys.PUBLIC_MODEL_CONFIG_ID, publicModelConfigId);
        if (provider != null) ps.put(BillingKeys.PROVIDER, provider);
        if (modelId != null) ps.put(BillingKeys.MODEL_ID, modelId);
        if (correlationId != null) ps.put(BillingKeys.CORRELATION_ID, correlationId);
        if (idempotencyKey != null) ps.put(BillingKeys.REQUEST_IDEMPOTENCY_KEY, idempotencyKey);
    }

    private static boolean parseBool(String v) {
        if (v == null) return false;
        return "true".equalsIgnoreCase(v) || "1".equals(v) || "yes".equalsIgnoreCase(v);
    }

    private static boolean isEmpty(String s) { return s == null || s.isBlank(); }

    private static String firstNonEmpty(String a, String b) {
        if (!isEmpty(a)) return a;
        if (!isEmpty(b)) return b;
        return null;
    }
}


