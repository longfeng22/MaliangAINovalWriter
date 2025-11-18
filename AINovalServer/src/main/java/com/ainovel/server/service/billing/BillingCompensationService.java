package com.ainovel.server.service.billing;

import org.springframework.data.mongodb.ReactiveMongoTransactionManager;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.billing.CreditTransaction;
import com.ainovel.server.repository.CreditTransactionRepository;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.ai.observability.LLMTraceService;
import com.ainovel.server.domain.model.observability.LLMTrace;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.transaction.reactive.TransactionalOperator;

@Service
@RequiredArgsConstructor
@Slf4j
public class BillingCompensationService {

    private final CreditService creditService;
    private final CreditTransactionRepository txRepo;
    private final ReactiveMongoTransactionManager tm;
    private final LLMTraceService traceService;
    private final com.ainovel.server.service.SystemConfigService systemConfigService;

    // 每5分钟扫一次失败或挂起的交易进行补偿
    @Scheduled(fixedDelay = 300000L)
    public void compensate() {
        // 读取时间窗口配置
        Mono<java.time.Instant> sinceInstantMono = systemConfigService.getStringValue(com.ainovel.server.domain.model.SystemConfig.Keys.BILLING_PROCESS_SINCE_TIME, null)
            .map(v -> {
                try { return v != null && !v.isBlank() ? java.time.LocalDateTime.parse(v) : null; } catch (Exception e) { return null; }
            })
            .flatMap(v -> v != null ? reactor.core.publisher.Mono.just(v.atZone(java.time.ZoneId.systemDefault()).toInstant())
                : systemConfigService.getIntegerValue(com.ainovel.server.domain.model.SystemConfig.Keys.BILLING_PROCESS_SINCE_HOURS, null)
                    .map(hours -> hours != null ? java.time.LocalDateTime.now().minusHours(Math.max(1, hours)).atZone(java.time.ZoneId.systemDefault()).toInstant() : null))
            .switchIfEmpty(reactor.core.publisher.Mono.empty());

        Flux<CreditTransaction> candidates = sinceInstantMono.flatMapMany(since -> txRepo.findAll()
            .filter(tx -> "FAILED".equals(tx.getStatus()) || "PENDING".equals(tx.getStatus()))
            .filter(tx -> {
                if (since == null) return true;
                try {
                    java.time.Instant created = tx.getCreatedAt();
                    return created == null || !created.isBefore(since);
                } catch (Exception e) { return true; }
            }));

        candidates
            .flatMap(tx -> {
                // 🔧 修复：验证交易记录的基本字段完整性
                if (tx.getUserId() == null || tx.getUserId().isBlank() || 
                    tx.getFeatureType() == null || tx.getFeatureType().isBlank()) {
                    log.warn("跳过补偿：交易记录缺少必要字段 - txId={}, userId={}, featureType={}", 
                            tx.getId(), tx.getUserId(), tx.getFeatureType());
                    // 将交易标记为 INVALID，避免被定时补偿反复扫描
                    try {
                        tx.setStatus("INVALID");
                        tx.setErrorMessage("交易缺少必要字段(userId/featureType)");
                        tx.setUpdatedAt(java.time.Instant.now());
                    } catch (Exception ignore) {}
                    return txRepo.save(tx).then(reactor.core.publisher.Mono.empty());
                }
                
                return TransactionalOperator.create(tm)
                    .execute(status -> {
                        AIFeatureType featureType;
                        try {
                            featureType = AIFeatureType.valueOf(tx.getFeatureType());
                        } catch (IllegalArgumentException e) {
                            log.error("跳过补偿：无效的featureType - txId={}, featureType={}, error={}", 
                                    tx.getId(), tx.getFeatureType(), e.getMessage());
                            // 标记为FAILED避免重复处理
                            tx.setStatus("FAILED");
                            tx.setErrorMessage("无效的featureType: " + tx.getFeatureType());
                            tx.setUpdatedAt(java.time.Instant.now());
                            return txRepo.save(tx).then(reactor.core.publisher.Mono.empty());
                        }

                    return traceService.findTraceById(tx.getTraceId())
                        .map(trace -> java.util.Optional.of(trace))
                        .onErrorResume(org.springframework.dao.IncorrectResultSizeDataAccessException.class, ex -> {
                            // 🔧 修复：处理重复traceId的情况，取第一个记录
                            log.warn("发现重复的traceId，将使用第一个匹配记录: traceId={}, error={}", 
                                    tx.getTraceId(), ex.getMessage());
                            return traceService.findFirstByTraceId(tx.getTraceId())
                                    .map(java.util.Optional::of)
                                    .switchIfEmpty(reactor.core.publisher.Mono.just(java.util.Optional.<LLMTrace>empty()));
                        })
                        .switchIfEmpty(reactor.core.publisher.Mono.just(java.util.Optional.<LLMTrace>empty()))
                        .flatMap(optionalTrace -> {
                            LLMTrace trace = optionalTrace.orElse(null);
                            int in = tx.getInputTokens() != null ? tx.getInputTokens() : 0;
                            int out = tx.getOutputTokens() != null ? tx.getOutputTokens() : 0;
                            String billingMode = "ACTUAL";

                            // 若缺少 provider/modelId，则尝试从 trace 补全
                            if ((tx.getProvider() == null || tx.getProvider().isBlank()) ||
                                (tx.getModelId() == null || tx.getModelId().isBlank())) {
                                try {
                                    String provider = null;
                                    String modelId = null;
                                    if (trace != null) {
                                        // 优先使用顶层trace中的provider/model
                                        if (trace.getProvider() != null && !trace.getProvider().isBlank()) provider = trace.getProvider();
                                        if (trace.getModel() != null && !trace.getModel().isBlank()) modelId = trace.getModel();

                                        // 其次从请求参数的providerSpecific中补全
                                        java.util.Map<String, Object> ps = (trace.getRequest() != null && trace.getRequest().getParameters() != null)
                                                ? trace.getRequest().getParameters().getProviderSpecific() : null;
                                        if (ps != null) {
                                            Object p2 = ps.get(com.ainovel.server.service.billing.BillingKeys.PROVIDER);
                                            Object m3 = ps.get(com.ainovel.server.service.billing.BillingKeys.MODEL_ID);
                                            if (provider == null && p2 instanceof String s3 && !s3.isBlank()) provider = s3;
                                            if (modelId == null && m3 instanceof String s4 && !s4.isBlank()) modelId = s4;
                                        }

                                        // 最后从响应元数据的providerSpecific中尝试
                                        java.util.Map<String, Object> rps = (trace.getResponse() != null && trace.getResponse().getMetadata() != null)
                                                ? trace.getResponse().getMetadata().getProviderSpecific() : null;
                                        if (rps != null) {
                                            Object p4 = rps.get(com.ainovel.server.service.billing.BillingKeys.PROVIDER);
                                            Object m5 = rps.get(com.ainovel.server.service.billing.BillingKeys.MODEL_ID);
                                            if (provider == null && p4 instanceof String s7 && !s7.isBlank()) provider = s7;
                                            if (modelId == null && m5 instanceof String s8 && !s8.isBlank()) modelId = s8;
                                        }
                                    }
                                    if (provider != null && !provider.isBlank()) tx.setProvider(provider);
                                    if (modelId != null && !modelId.isBlank()) tx.setModelId(modelId);
                                } catch (Exception ignore) {}
                            }

                            if (in <= 0 && out <= 0) {
                                // 尝试用trace中的真实用量
                                if (trace != null && trace.getResponse() != null &&
                                        trace.getResponse().getMetadata() != null &&
                                        trace.getResponse().getMetadata().getTokenUsage() != null) {
                                    var u = trace.getResponse().getMetadata().getTokenUsage();
                                    in = u.getInputTokenCount() != null ? u.getInputTokenCount() : 0;
                                    out = u.getOutputTokenCount() != null ? u.getOutputTokenCount() : 0;
                                    billingMode = "ACTUAL";
                                } else {
                                    // 估算：根据trace内容粗估token
                                    billingMode = "ESTIMATED";
                                    in = estimateInputTokensFromTrace(trace);
                                    out = estimateOutputTokensFromTrace(trace, in, featureType);
                                    
                                    // 🔧 修复：如果仍然无法获取token数量，跳过此次补偿
                                    if (in <= 0 && out <= 0) {
                                        log.warn("跳过补偿：无法获取token使用量 - traceId={}, userId={}, provider={}, modelId={}, featureType={}", 
                                                tx.getTraceId(), tx.getUserId(), tx.getProvider(), tx.getModelId(), tx.getFeatureType());
                                        // 将状态标记为FAILED，避免重复处理
                                        tx.setStatus("FAILED");
                                        tx.setErrorMessage("无法获取token使用量，trace不存在或无效");
                                        tx.setUpdatedAt(java.time.Instant.now());
                                        return txRepo.save(tx).then(reactor.core.publisher.Mono.empty());
                                    }
                                }
                            }

                            final int finalIn = in;
                            final int finalOut = out;
                            final String finalBillingMode = billingMode;

                            return creditService
                                .deductCreditsForAI(tx.getUserId(), tx.getProvider(), tx.getModelId(), featureType, finalIn, finalOut)
                                .flatMap(res -> {
                                    if (res.isSuccess()) {
                                        tx.setStatus("COMPENSATED");
                                        tx.setCreditsDeducted(res.getCreditsDeducted());
                                        tx.setBillingMode(finalBillingMode);
                                        tx.setEstimated("ESTIMATED".equals(finalBillingMode));
                                        tx.setInputTokens(finalIn);
                                        tx.setOutputTokens(finalOut);
                                        tx.setUpdatedAt(java.time.Instant.now());
                                        return txRepo.save(tx);
                                    } else {
                                        String message = res.getMessage();
                                        boolean insufficient = message != null && (message.contains("积分余额不足") || message.toLowerCase().contains("insufficient"));
                                        if (insufficient) {
                                            tx.setStatus("NO_FUNDS");
                                            tx.setErrorMessage(message);
                                            tx.setUpdatedAt(java.time.Instant.now());
                                            log.warn("补偿跳过：积分不足 - traceId={}, userId={}, provider={}, modelId={}, featureType={}, err={}",
                                                    tx.getTraceId(), tx.getUserId(), tx.getProvider(), tx.getModelId(), tx.getFeatureType(), message);
                                            return txRepo.save(tx).then(reactor.core.publisher.Mono.empty());
                                        } else {
                                            tx.setStatus("FAILED");
                                            tx.setErrorMessage(message);
                                            tx.setUpdatedAt(java.time.Instant.now());
                                            return txRepo.save(tx)
                                                .then(reactor.core.publisher.Mono.error(new RuntimeException(message)));
                                        }
                                    }
                                });
                        });
                    })
                    .onErrorResume(e -> {
                        String msg = e != null && e.getMessage() != null ? e.getMessage() : "";
                        boolean insufficient = msg.contains("积分余额不足") || msg.toLowerCase().contains("insufficient");
                        if (e instanceof com.ainovel.server.common.exception.InsufficientCreditsException || insufficient) {
                            log.warn("补偿事务失败（可预期，跳过重试）: err={}, traceId={}, userId={}, provider={}, modelId={}, featureType={}",
                                    msg,
                                    tx.getTraceId(),
                                    tx.getUserId(),
                                    tx.getProvider(),
                                    tx.getModelId(),
                                    tx.getFeatureType());
                        } else {
                            log.error("补偿事务失败: err={}, traceId={}, userId={}, provider={}, modelId={}, featureType={}",
                                    msg,
                                    tx.getTraceId(),
                                    tx.getUserId(),
                                    tx.getProvider(),
                                    tx.getModelId(),
                                    tx.getFeatureType(),
                                    e);
                        }
                        return reactor.core.publisher.Mono.empty();
                    });
            })
            .retryWhen(reactor.util.retry.Retry.backoff(3, java.time.Duration.ofSeconds(2)).jitter(0.3))
            .doOnError(e -> log.error("补偿失败: err={}", e.getMessage()))
            .onErrorResume(e -> reactor.core.publisher.Mono.empty())
            .subscribe();
    }

    private int estimateOutputTokensForFeature(int inputTokens, AIFeatureType featureType) {
        switch (featureType) {
            case TEXT_EXPANSION:
                return (int) (inputTokens * 1.5);
            case TEXT_SUMMARY:
            case SCENE_TO_SUMMARY:
                return (int) (inputTokens * 0.3);
            case TEXT_REFACTOR:
                return (int) (inputTokens * 1.1);
            case NOVEL_GENERATION:
            case SUMMARY_TO_SCENE:
                return (int) (inputTokens * 2.0);
            case AI_CHAT:
                return (int) (inputTokens * 0.8);
            default:
                return inputTokens;
        }
    }

    private int estimateInputTokensFromTrace(LLMTrace trace) {
        try {
            int sum = 0;
            if (trace != null && trace.getRequest() != null && trace.getRequest().getMessages() != null) {
                for (var m : trace.getRequest().getMessages()) {
                    if (m.getContent() != null) {
                        sum += roughTokenEstimate(m.getContent());
                    }
                }
            }
            return Math.max(1, sum);
        } catch (Exception e) {
            return 1;
        }
    }

    private int estimateOutputTokensFromTrace(LLMTrace trace, int fallbackIn, AIFeatureType featureType) {
        try {
            if (trace != null && trace.getResponse() != null && trace.getResponse().getMessage() != null &&
                trace.getResponse().getMessage().getContent() != null) {
                return roughTokenEstimate(trace.getResponse().getMessage().getContent());
            }
        } catch (Exception ignore) {}
        return estimateOutputTokensForFeature(fallbackIn, featureType);
    }

    private int roughTokenEstimate(String text) {
        if (text == null || text.isBlank()) return 0;
        int len = text.length();
        // 简化估算：中文每字≈1token，英文≈4字符1token，取折中
        return Math.max(1, (int) Math.ceil(len / 2.5));
    }
}


