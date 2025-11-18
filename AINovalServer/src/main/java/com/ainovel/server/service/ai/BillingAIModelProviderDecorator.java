package com.ainovel.server.service.ai;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.service.ai.capability.ToolCallCapable;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.billing.BillingMarkerEnricher;
import com.ainovel.server.service.billing.PublicModelBillingContext;
import com.ainovel.server.service.billing.BillingKeys;
import dev.langchain4j.model.chat.ChatLanguageModel;
import dev.langchain4j.model.chat.StreamingChatLanguageModel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 计费装饰器（外层）
 *
 * 目标：将公共模型识别、预扣费与后续结算从业务层下沉到 Provider 装饰器层。
 * 当前提交为骨架版：仅做透明透传，不改变现有行为，为后续逐步迁移提供挂载点。
 *
 * 建议装饰器链顺序：Billing -> Tracing -> RealProvider
 */
@Slf4j
@RequiredArgsConstructor
public class BillingAIModelProviderDecorator implements AIModelProvider, ToolCallCapable {

    private final AIModelProvider decoratedProvider;
    private final CreditService creditService;
    private final PublicModelConfigService publicModelConfigService;
    // 若由 Provider 创建链路明确识别为公共模型，可在此强制注入，避免依赖请求体标记
    private com.ainovel.server.domain.model.PublicModelConfig forcedPublicModel;

    @Override
    public Mono<AIResponse> generateContent(AIRequest request) {
        if (shouldSkipBilling(request)) {
            return decoratedProvider.generateContent(request);
        }
        Mono<PublicCtx> ctxMono = (forcedPublicModel != null)
                ? Mono.just(new PublicCtx(getOrCreateTraceId(request, forcedPublicModel), forcedPublicModel, extractFeatureType(request)))
                : resolvePublicCtx(request);
        return ctxMono
                .switchIfEmpty(Mono.defer(() -> Mono.empty()))
                .flatMap(ctx -> creditService.estimateCreditsForAIRequest(request, ctx.publicModel(), ctx.featureType())
                        .flatMap(cost -> creditService.preDeductCredits(ctx.traceId(), request.getUserId(), Math.max(1L, cost),
                                ctx.publicModel().getProvider(), ctx.publicModel().getModelId(), ctx.featureType()))
                        .onErrorResume(err -> Mono.just(com.ainovel.server.service.impl.CreditServiceImpl.PreDeductionResult.failure(ctx.traceId(), err.getMessage())))
                        .flatMap(pr -> {
                            if (!pr.isSuccess()) {
                                // 余额不足或其他失败，向上抛错，阻止后续生成
                                return Mono.error(new IllegalStateException("预扣费失败: " + pr.getMessage()));
                            }
                            return decoratedProvider.generateContent(request)
                                    .doOnError(e -> creditService.refundPreDeduction(ctx.traceId()).subscribe());
                        })
                )
                .switchIfEmpty(decoratedProvider.generateContent(request));
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        if (shouldSkipBilling(request)) {
            return decoratedProvider.generateContentStream(request);
        }
        Mono<PublicCtx> ctxMono = (forcedPublicModel != null)
                ? Mono.just(new PublicCtx(getOrCreateTraceId(request, forcedPublicModel), forcedPublicModel, extractFeatureType(request)))
                : resolvePublicCtx(request);
        return ctxMono
                .flatMapMany(ctx -> creditService.estimateCreditsForAIRequest(request, ctx.publicModel(), ctx.featureType())
                        .flatMap(cost -> {
                            long estimated = Math.max(1L, cost);
                            log.info("[Billing] 预扣费开始: traceId={}, userId={}, provider={}, modelId={}, featureType={}, estimatedCredits={}",
                                    ctx.traceId(), request.getUserId(), ctx.publicModel().getProvider(), ctx.publicModel().getModelId(), ctx.featureType(), estimated);
                            return creditService.preDeductCredits(ctx.traceId(), request.getUserId(), estimated,
                                ctx.publicModel().getProvider(), ctx.publicModel().getModelId(), ctx.featureType());
                        })
                        .doOnError(err -> log.error("[Billing] 预扣费异常: traceId={}, err={}", ctx.traceId(), err.getMessage()))
                        .onErrorResume(err -> Mono.just(com.ainovel.server.service.impl.CreditServiceImpl.PreDeductionResult.failure(ctx.traceId(), err.getMessage())))
                        .flatMapMany(pr -> {
                            if (!pr.isSuccess()) {
                                return Flux.error(new IllegalStateException("预扣费失败: " + pr.getMessage()));
                            }
                            return decoratedProvider.generateContentStream(request)
                                    .doOnError(e -> creditService.refundPreDeduction(ctx.traceId()).subscribe());
                        })
                )
                .switchIfEmpty(decoratedProvider.generateContentStream(request));
    }

    /**
     * 由 Provider 构造链路注入公共模型来源，避免依赖请求体标记被篡改。
     */
    public BillingAIModelProviderDecorator forcePublicModel(com.ainovel.server.domain.model.PublicModelConfig publicModel) {
        this.forcedPublicModel = publicModel;
        return this;
    }

    private static class PublicCtx {
        private final String traceId;
        private final PublicModelConfig publicModel;
        private final AIFeatureType featureType;
        private PublicCtx(String traceId, PublicModelConfig publicModel, AIFeatureType featureType) {
            this.traceId = traceId;
            this.publicModel = publicModel;
            this.featureType = featureType;
        }
        public String traceId() { return traceId; }
        public PublicModelConfig publicModel() { return publicModel; }
        public AIFeatureType featureType() { return featureType; }
    }

    // 保留：旧入口，兼容外部可能的调用（内部改用 resolvePublicCtx）
    @SuppressWarnings("unused")
    private Mono<PublicCtx> prepareForPublicBilling(AIRequest request) {
        String publicCfgId = extractPublicConfigId(request);
        if (publicCfgId == null || publicCfgId.isBlank()) {
            return Mono.error(new IllegalArgumentException("缺少publicModelConfigId"));
        }
        return publicModelConfigService.findById(publicCfgId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("公共模型配置不存在: " + publicCfgId)))
                .map(pub -> new PublicCtx(getOrCreateTraceId(request, pub), pub, extractFeatureType(request)));
    }

    /**
     * 统一基于 modelConfigId 或 publicModelConfigId 解析是否为公共模型请求。
     * 若无法解析则返回 empty。
     */
    private Mono<PublicCtx> resolvePublicCtx(AIRequest request) {
        // 1) 明确的 publicModelConfigId
        String publicCfgId = extractPublicConfigId(request);
        if (publicCfgId != null && !publicCfgId.isBlank() && !"null".equalsIgnoreCase(publicCfgId)) {
            return publicModelConfigService.findById(publicCfgId)
                    .map(pub -> new PublicCtx(getOrCreateTraceId(request, pub), pub, extractFeatureType(request)))
                    .switchIfEmpty(Mono.empty());
        }
        // 2) 统一：从 modelConfigId 判断是否是公共配置
        String modelCfgId = extractModelConfigId(request);
        if (modelCfgId != null && !modelCfgId.isBlank() && !"null".equalsIgnoreCase(modelCfgId)) {
            return publicModelConfigService.findById(modelCfgId)
                    .map(pub -> new PublicCtx(getOrCreateTraceId(request, pub), pub, extractFeatureType(request)))
                    .switchIfEmpty(Mono.empty());
        }
        return Mono.empty();
    }

    /**
     * 规则：若明确标记为设定生成的工具阶段，则跳过预扣费/后扣费
     */
    private boolean shouldSkipBilling(AIRequest request) {
        try {
            if (request.getFeatureType() != null) {
                if (request.getFeatureType() == com.ainovel.server.domain.model.AIFeatureType.SETTING_GENERATION_TOOL) {
                    log.debug("[Billing] Skip for tool stage feature: {}", request.getFeatureType());
                    return true;
                }
            }
            // 兼容旧路径：从metadata.requestType判断
            if (request.getMetadata() != null) {
                Object rt = request.getMetadata().get("requestType");
                if (rt != null && com.ainovel.server.domain.model.AIFeatureType.SETTING_GENERATION_TOOL.name().equals(rt.toString())) {
                    log.debug("[Billing] Skip for tool stage via metadata.requestType={}", rt);
                    return true;
                }
            }
        } catch (Exception ignore) {}
        return false;
    }

    // 保留：兼容旧判断逻辑（内部改用 resolvePublicCtx）
    @SuppressWarnings("unused")
    private boolean isPublicRequest(AIRequest request) {
        try {
            if (request.getParameters() != null) {
                Object ps = request.getParameters().get("providerSpecific");
                if (ps instanceof java.util.Map<?, ?> m) {
                    Object used = m.get(BillingKeys.USED_PUBLIC_MODEL);
                    if (used != null && Boolean.parseBoolean(String.valueOf(used))) return true;
                }
            }
            if (request.getMetadata() != null) {
                Object id = request.getMetadata().get("publicModelConfigId");
                if (id instanceof String s && !s.isBlank()) return true;
            }
        } catch (Exception ignore) {}
        return false;
    }

    private String extractPublicConfigId(AIRequest request) {
        try {
            if (request.getParameters() != null) {
                Object ps = request.getParameters().get("providerSpecific");
                if (ps instanceof java.util.Map<?, ?> m) {
                    Object id = m.get(BillingKeys.PUBLIC_MODEL_CONFIG_ID);
                    if (id instanceof String s && !s.isBlank()) return s;
                }
            }
            if (request.getMetadata() != null) {
                Object id = request.getMetadata().get("publicModelConfigId");
                if (id instanceof String s && !s.isBlank()) return s;
            }
        } catch (Exception ignore) {}
        return null;
    }

    private String extractModelConfigId(AIRequest request) {
        try {
            if (request.getParameters() != null) {
                Object raw = request.getParameters().get("modelConfigId");
                if (raw != null) return String.valueOf(raw);
                Object ps = request.getParameters().get("providerSpecific");
                if (ps instanceof java.util.Map<?, ?> m) {
                    Object id = m.get("modelConfigId");
                    if (id != null) return String.valueOf(id);
                }
            }
            if (request.getMetadata() != null) {
                Object id = request.getMetadata().get("modelConfigId");
                if (id != null) return String.valueOf(id);
            }
        } catch (Exception ignore) {}
        return null;
    }

    private String getOrCreateTraceId(AIRequest request, PublicModelConfig pub) {
        // 1) 优先使用显式字段 traceId
        try {
            if (request.getTraceId() != null && !request.getTraceId().isBlank()) {
                String tid = request.getTraceId();
                // 确保写入 providerSpecific/metadata，供下游追踪/监听统一读取
                try {
                    PublicModelBillingContext ctx = PublicModelBillingContext.builder()
                            .usedPublicModel(true)
                            .requiresPostStreamDeduction(true)
                            .streamFeatureType(extractFeatureType(request).toString())
                            .publicModelConfigId(extractPublicConfigId(request))
                            .provider(pub.getProvider())
                            .modelId(pub.getModelId())
                            .idempotencyKey(tid)
                            .build();
                    BillingMarkerEnricher.applyTo(request, ctx);
                } catch (Exception ignore) {}
                return tid;
            }
        } catch (Exception ignore) {}

        // 2) 其次使用 providerSpecific / metadata 中的幂等键
        String existed = null;
        try {
            if (request.getParameters() != null) {
                Object ps = request.getParameters().get("providerSpecific");
                if (ps instanceof java.util.Map<?, ?> m) {
                    Object k = m.get(BillingKeys.REQUEST_IDEMPOTENCY_KEY);
                    if (k != null) existed = String.valueOf(k);
                }
            }
            if (existed == null && request.getMetadata() != null) {
                Object k = request.getMetadata().get(BillingKeys.REQUEST_IDEMPOTENCY_KEY);
                if (k != null) existed = String.valueOf(k);
            }
        } catch (Exception ignore) {}
        if (existed != null && !existed.isBlank()) {
            // 同步到显式字段，避免后续装饰器优先读取到空
            try { if (request.getTraceId() == null || request.getTraceId().isBlank()) request.setTraceId(existed); } catch (Exception ignore) {}
            return existed;
        }

        // 3) 都没有时生成新的，并写回三处
        String traceId = java.util.UUID.randomUUID().toString();
        try {
            request.setTraceId(traceId);
        } catch (Exception ignore) {}
        try {
            PublicModelBillingContext ctx = PublicModelBillingContext.builder()
                    .usedPublicModel(true)
                    .requiresPostStreamDeduction(true)
                    .streamFeatureType(extractFeatureType(request).toString())
                    .publicModelConfigId(extractPublicConfigId(request))
                    .provider(pub.getProvider())
                    .modelId(pub.getModelId())
                    .idempotencyKey(traceId)
                    .build();
            BillingMarkerEnricher.applyTo(request, ctx);
        } catch (Exception ignore) {}
        return traceId;
    }

    private AIFeatureType extractFeatureType(AIRequest request) {
        try {
            if (request.getParameters() != null) {
                Object ps = request.getParameters().get("providerSpecific");
                if (ps instanceof java.util.Map<?, ?> m) {
                    Object ft = m.get(BillingKeys.STREAM_FEATURE_TYPE);
                    if (ft instanceof String s && !s.isBlank()) return AIFeatureType.valueOf(s);
                }
            }
            if (request.getMetadata() != null) {
                Object ft = request.getMetadata().get("streamFeatureType");
                if (ft instanceof String s && !s.isBlank()) return AIFeatureType.valueOf(s);
                Object reqType = request.getMetadata().get("requestType");
                if (reqType instanceof String rs && !rs.isBlank()) {
                    try {
                        return AIFeatureType.valueOf(rs);
                    } catch (Exception ignore) {}
                }
            }
        } catch (Exception ignore) {}
        return AIFeatureType.AI_CHAT;
    }

    // --- 其余接口方法直接委托 ---

    @Override
    public String getProviderName() {
        return decoratedProvider.getProviderName();
    }

    @Override
    public String getModelName() {
        return decoratedProvider.getModelName();
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request) {
        return decoratedProvider.estimateCost(request);
    }

    @Override
    public Mono<Boolean> validateApiKey() {
        return decoratedProvider.validateApiKey();
    }

    @Override
    public void setProxy(String host, int port) {
        decoratedProvider.setProxy(host, port);
    }

    @Override
    public void disableProxy() {
        decoratedProvider.disableProxy();
    }

    @Override
    public boolean isProxyEnabled() {
        return decoratedProvider.isProxyEnabled();
    }

    @Override
    public Flux<ModelInfo> listModels() {
        return decoratedProvider.listModels();
    }

    @Override
    public Flux<ModelInfo> listModelsWithApiKey(String apiKey, String apiEndpoint) {
        return decoratedProvider.listModelsWithApiKey(apiKey, apiEndpoint);
    }

    @Override
    public String getApiKey() {
        return decoratedProvider.getApiKey();
    }

    @Override
    public String getApiEndpoint() {
        return decoratedProvider.getApiEndpoint();
    }

    // ====== ToolCallCapable 条件实现 ======
    @Override
    public boolean supportsToolCalling() {
        if (decoratedProvider instanceof ToolCallCapable capable) {
            return capable.supportsToolCalling();
        }
        return false;
    }

    @Override
    public ChatLanguageModel getToolCallableChatModel() {
        if (decoratedProvider instanceof ToolCallCapable capable) {
            return capable.getToolCallableChatModel();
        }
        throw new UnsupportedOperationException("被装饰的提供者不支持工具调用: " + decoratedProvider.getClass().getSimpleName());
    }

    @Override
    public StreamingChatLanguageModel getToolCallableStreamingChatModel() {
        if (decoratedProvider instanceof ToolCallCapable capable) {
            return capable.getToolCallableStreamingChatModel();
        }
        return null;
    }
}


