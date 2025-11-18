package com.ainovel.server.service.billing;

import org.springframework.context.event.EventListener;
import org.springframework.data.mongodb.ReactiveMongoTransactionManager;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.billing.CreditTransaction;
import com.ainovel.server.domain.model.observability.LLMTrace;
import com.ainovel.server.repository.CreditTransactionRepository;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.ai.observability.events.BillingRequestedEvent;
import com.ainovel.server.service.ai.observability.events.CreditAdjustmentRequestedEvent;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import jakarta.annotation.PostConstruct;

@Service
@RequiredArgsConstructor
@Slf4j
public class BillingOrchestrator {

    private final CreditService creditService;
    private final CreditTransactionRepository txRepo;
    private final ReactiveMongoTransactionManager tm; // 仍用于其他路径，但本方法已移除事务
    private final Sinks.Many<CreditAdjustmentRequestedEvent> creditAdjustmentSink = Sinks.many().unicast().onBackpressureBuffer();
    // 去重：防止同一个traceId的调整被重复入队/消费（例如多次发布同一事件或多实例竞态）
    private final java.util.concurrent.ConcurrentHashMap<String, Boolean> processingTraces = new java.util.concurrent.ConcurrentHashMap<>();

    @PostConstruct
    public void initCreditAdjustmentPipeline() {
        creditAdjustmentSink.asFlux()
                .groupBy(evt -> {
                    LLMTrace t = evt.getTrace();
                    return t != null ? t.getUserId() : "unknown";
                })
                .flatMap(group -> group
                        .doOnSubscribe(sub -> log.info("🧵 启动用户分组队列消费: userId={}", group.key()))
                        .concatMap(evt -> {
                            LLMTrace t = evt.getTrace();
                            String traceId = t != null ? t.getTraceId() : null;
                            String userId = t != null ? t.getUserId() : null;
                            log.info("📥 [队列消费开始] CreditAdjustmentRequestedEvent: userId={}, traceId={}", userId, traceId);
                            return processCreditAdjustment(evt)
                                    .doOnSuccess(v -> log.info("📤 [队列消费完成] CreditAdjustmentRequestedEvent: userId={}, traceId={}", userId, traceId))
                                    .doOnError(e -> log.error("❌ [队列消费失败] CreditAdjustmentRequestedEvent: userId={}, traceId={}, err={}", userId, traceId, e.getMessage()));
                        })
                )
                .onErrorContinue((error, obj) -> log.error("费用调整流水线错误: {}", error.getMessage(), error))
                .subscribe();
    }

    @EventListener
    public void onBillingRequested(BillingRequestedEvent evt) {
        LLMTrace t = evt.getTrace();
        if (t == null || t.getRequest() == null || t.getRequest().getParameters() == null
                || t.getRequest().getParameters().getProviderSpecific() == null) {
            return;
        }

        String traceId = t.getTraceId();
        String userId = t.getUserId();
        String provider = t.getProvider();
        String modelId = t.getModel();

        var ps = t.getRequest().getParameters().getProviderSpecific();
        Object flag = ps.get(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION);
        Object used = ps.get(BillingKeys.USED_PUBLIC_MODEL);
        Object ft = ps.get(BillingKeys.STREAM_FEATURE_TYPE);
        if (!Boolean.TRUE.equals(flag) || !Boolean.TRUE.equals(used) || ft == null) {
            return;
        }

        var token = t.getResponse() != null && t.getResponse().getMetadata() != null ? t.getResponse().getMetadata().getTokenUsage() : null;
        int in = token != null && token.getInputTokenCount() != null ? token.getInputTokenCount() : 0;
        int out = token != null && token.getOutputTokenCount() != null ? token.getOutputTokenCount() : 0;
        AIFeatureType featureType = AIFeatureType.valueOf(ft.toString());

        log.info("🧾 BillingOrchestrator 收到扣费请求: traceId={}, userId={}, provider={}, modelId={}, featureType={}, inTokens={}, outTokens={}",
                traceId, userId, provider, modelId, featureType, in, out);

        // 先查现有交易：若存在并为ESTIMATED，则做ADJUSTMENT；否则走正常扣费流
        txRepo.findByTraceId(traceId)
            .flatMap(existing -> {
                if (existing != null && Boolean.TRUE.equals(existing.getEstimated())) {
                    // 已做过估算扣费，基于实际用量做差额调整
                    return creditService.calculateCreditCost(provider, modelId, featureType, in, out)
                        .flatMap(actualCredits -> {
                            long prev = existing.getCreditsDeducted() != null ? existing.getCreditsDeducted() : 0L;
                            long diff = actualCredits - prev;
                            if (diff == 0L) {
                                log.info("估算与实际一致，无需调整: traceId={} actual={} prev={}", traceId, actualCredits, prev);
                                return Mono.empty();
                            }
                            Mono<Boolean> op = diff > 0
                                ? creditService.deductCredits(userId, diff)
                                : creditService.addCredits(userId, -diff, "ADJUSTMENT for " + traceId);
                            return op.flatMap(ok -> {
                                if (!ok) return Mono.error(new RuntimeException("调整扣减失败"));
                                CreditTransaction adjust = CreditTransaction.builder()
                                        .traceId(traceId + ":adjust")
                                        .userId(userId)
                                        .provider(provider)
                                        .modelId(modelId)
                                        .featureType(featureType.name())
                                        .inputTokens(in)
                                        .outputTokens(out)
                                        .creditsDeducted(diff)
                                        .status("ADJUSTED")
                                        .billingMode("ADJUSTMENT")
                                        .estimated(Boolean.FALSE)
                                        .reversalOfTraceId(traceId)
                                        .updatedAt(java.time.Instant.now())
                                        .build();
                                return txRepo.save(adjust).then();
                            });
                        })
                        .onErrorResume(e -> { log.error("调整失败: traceId={}, err={}", traceId, e.getMessage()); return Mono.empty(); });
                }
                // 不是估算交易，跳过（避免重复）；若需要可扩展为幂等等
                log.info("已存在交易且非估算，跳过新扣费: traceId={}", traceId);
                return Mono.empty();
            })
            .switchIfEmpty(Mono.defer(() -> {
                // 创建PENDING事务并按实际扣费
                CreditTransaction pending = CreditTransaction.builder()
                        .traceId(traceId)
                        .userId(userId)
                        .provider(provider)
                        .modelId(modelId)
                        .featureType(featureType.name())
                        .inputTokens(in)
                        .outputTokens(out)
                        .status("PENDING")
                        .billingMode("ACTUAL")
                        .estimated(Boolean.FALSE)
                        .build();

                return txRepo.save(pending)
                    .then(
                        creditService.deductCreditsForAI(userId, provider, modelId, featureType, in, out)
                            .flatMap(res -> {
                                if (res.isSuccess()) {
                                    return txRepo.findByTraceId(traceId)
                                            .flatMap(tx -> {
                                                tx.setStatus("DEDUCTED");
                                                tx.setCreditsDeducted(res.getCreditsDeducted());
                                                tx.setBillingMode("ACTUAL");
                                                tx.setEstimated(Boolean.FALSE);
                                                tx.setUpdatedAt(java.time.Instant.now());
                                                return txRepo.save(tx);
                                            })
                                            .then();
                                } else {
                                    return txRepo.findByTraceId(traceId)
                                            .flatMap(tx -> {
                                                tx.setStatus("FAILED");
                                                tx.setErrorMessage(res.getMessage());
                                                tx.setUpdatedAt(java.time.Instant.now());
                                                return txRepo.save(tx);
                                            })
                                            .then(Mono.error(new RuntimeException("扣费失败: " + res.getMessage())));
                                }
                            })
                    )
                    .onErrorResume(e -> {
                        log.error("BillingOrchestrator 扣费失败(无事务): traceId={}, err={}", traceId, e.getMessage());
                        return txRepo.findByTraceId(traceId)
                                .flatMap(tx -> { tx.setStatus("FAILED"); tx.setErrorMessage(e.getMessage()); tx.setUpdatedAt(java.time.Instant.now()); return txRepo.save(tx); })
                                .then();
                    });
            }))
            .subscribe();
    }

    /**
     * 🚀 新增：处理费用调整请求事件
     * 基于真实token使用量调整预扣费
     */
    @EventListener
    public void onCreditAdjustmentRequested(CreditAdjustmentRequestedEvent evt) {
        LLMTrace t = evt.getTrace();
        String traceId = t != null ? t.getTraceId() : null;
        String userId = t != null ? t.getUserId() : null;
        if (userId == null) {
            log.warn("跳过费用调整事件，缺少userId: traceId={}", traceId);
            return;
        }
        // 事件入队前做幂等去重：相同traceId若已在处理，则忽略本次事件
        if (traceId != null) {
            Boolean existed = processingTraces.putIfAbsent(traceId, Boolean.TRUE);
            if (existed != null) {
                log.warn("🔁 重复的费用调整事件，已忽略: traceId={}, userId={}", traceId, userId);
                return;
            }
        }
        Sinks.EmitResult result = creditAdjustmentSink.tryEmitNext(evt);
        if (result.isFailure()) {
            log.warn("入队失败，降级为即时处理: traceId={}, emitResult={}", traceId, result);
            processCreditAdjustment(evt)
                    .doFinally(sig -> { if (traceId != null) processingTraces.remove(traceId); })
                    .doOnError(e -> log.error("即时处理费用调整失败: traceId={}, 错误={}", traceId, e.getMessage()))
                    .subscribe();
        } else {
            log.info("📥 费用调整事件已入队: traceId={}, userId={}", traceId, userId);
        }
    }

    private Mono<Void> processCreditAdjustment(CreditAdjustmentRequestedEvent evt) {
        LLMTrace t = evt.getTrace();
        if (t == null || t.getRequest() == null || t.getRequest().getParameters() == null
                || t.getRequest().getParameters().getProviderSpecific() == null) {
            return Mono.empty();
        }

        String traceId = t.getTraceId();
        log.info("🔧 开始处理费用调整请求(串行): traceId={}", traceId);

        var ps = t.getRequest().getParameters().getProviderSpecific();
        Object skipBilling = ps.get(BillingKeys.SKIP_BILLING_FOR_TOOL_ORCHESTRATION);
        if (Boolean.TRUE.equals(skipBilling)) {
            log.info("计费跳过：工具编排链路，traceId={}", traceId);
            return Mono.empty();
        }
        Object flag = ps.get(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION);
        Object used = ps.get(BillingKeys.USED_PUBLIC_MODEL);
        if (!Boolean.TRUE.equals(flag) || !Boolean.TRUE.equals(used)) {
            log.info("跳过费用调整，不符合条件: traceId={}, requiresPostDeduction={}, usedPublicModel={}", 
                    traceId, flag, used);
            return Mono.empty();
        }

        var token = t.getResponse() != null && t.getResponse().getMetadata() != null ? t.getResponse().getMetadata().getTokenUsage() : null;
        int inputTokens = token != null && token.getInputTokenCount() != null ? token.getInputTokenCount() : 0;
        int outputTokens = token != null && token.getOutputTokenCount() != null ? token.getOutputTokenCount() : 0;

        if (inputTokens <= 0 && outputTokens <= 0) {
            log.warn("费用调整跳过，无有效token信息: traceId={}, inputTokens={}, outputTokens={}", 
                    traceId, inputTokens, outputTokens);
            return Mono.empty();
        }

        return creditService.adjustCreditsBasedOnActualUsage(traceId, inputTokens, outputTokens)
                .flatMap(adjustmentResult -> {
                    if (!adjustmentResult.isSuccess()) {
                        log.error("费用调整失败: traceId={}, 错误: {}", traceId, adjustmentResult.getMessage());
                        return Mono.empty();
                    }

                    log.info("费用调整成功: traceId={}, 调整类型: {}, 调整金额: {}, 实际费用: {}, 原预扣费: {}", 
                            traceId, adjustmentResult.getAdjustmentType(), adjustmentResult.getAdjustmentAmount(),
                            adjustmentResult.getActualCost(), adjustmentResult.getOriginalPreDeduction());

                    return txRepo.findByTraceId(traceId)
                            .flatMap(existingTx -> {
                                existingTx.setActualInputTokens(inputTokens);
                                existingTx.setActualOutputTokens(outputTokens);
                                existingTx.setActualCost(adjustmentResult.getActualCost());
                                existingTx.setAdjustmentAmount(adjustmentResult.getAdjustmentAmount());
                                existingTx.setAdjustmentType(adjustmentResult.getAdjustmentType());
                                existingTx.setStatus("COMPLETED");
                                existingTx.setUpdatedAt(java.time.Instant.now());
                                return txRepo.save(existingTx);
                            })
                            .switchIfEmpty(Mono.defer(() -> {
                                CreditTransaction newTx = CreditTransaction.builder()
                                        .traceId(traceId)
                                        .userId(t.getUserId())
                                        .provider(t.getProvider())
                                        .modelId(t.getModel())
                                        .featureType(String.valueOf(ps.get(BillingKeys.STREAM_FEATURE_TYPE)))
                                        .actualInputTokens(inputTokens)
                                        .actualOutputTokens(outputTokens)
                                        .actualCost(adjustmentResult.getActualCost())
                                        .adjustmentAmount(adjustmentResult.getAdjustmentAmount())
                                        .adjustmentType(adjustmentResult.getAdjustmentType())
                                        .status("COMPLETED")
                                        .createdAt(java.time.Instant.now())
                                        .updatedAt(java.time.Instant.now())
                                        .build();
                                return txRepo.save(newTx);
                            }))
                            .then();
                })
                .doOnSuccess(v -> log.info("费用调整事务处理完成(串行): traceId={}", traceId))
                .doOnError(error -> log.error("费用调整事务处理失败(串行): traceId={}, 错误: {}", traceId, error.getMessage()))
                .onErrorResume(e -> Mono.empty())
                .doFinally(sig -> {
                    // 清理去重标记
                    if (traceId != null) processingTraces.remove(traceId);
                });
    }
}


