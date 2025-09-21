package com.ainovel.server.service.billing;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.observability.LLMTrace;
import com.ainovel.server.repository.CreditTransactionRepository;
import com.ainovel.server.service.ai.observability.LLMTraceService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Service
@RequiredArgsConstructor
@Slf4j
public class BillingReconciliationJob {

    private final LLMTraceService traceService;
    private final CreditTransactionRepository txRepo;
    private final com.ainovel.server.service.SystemConfigService systemConfigService;

    // 每15分钟对账：确保所有需要后扣费的trace都有对应交易
    @Scheduled(fixedDelay = 900000L)
    public void reconcile() {
        // 读取时间窗口配置
        Mono<java.time.LocalDateTime> sinceMono = systemConfigService.getStringValue(com.ainovel.server.domain.model.SystemConfig.Keys.BILLING_PROCESS_SINCE_TIME, null)
            .map(v -> {
                try { return v != null && !v.isBlank() ? java.time.LocalDateTime.parse(v) : null; } catch (Exception e) { return null; }
            })
            .flatMap(v -> v != null ? Mono.just(v) : systemConfigService.getIntegerValue(com.ainovel.server.domain.model.SystemConfig.Keys.BILLING_PROCESS_SINCE_HOURS, null)
                .map(hours -> hours != null ? java.time.LocalDateTime.now().minusHours(Math.max(1, hours)) : null))
            .switchIfEmpty(Mono.empty());

        Flux<LLMTrace> traces = sinceMono.flatMapMany(since -> {
            if (since != null) {
                log.info("[Reconcile] 使用时间窗口 since={}", since);
                return traceService.findTracesByTimeRange(since, java.time.LocalDateTime.now(), org.springframework.data.domain.Pageable.unpaged());
            }
            // 回退策略：仅取最近500条，避免全量
            return traceService.findRecent(500);
        });
        traces.flatMap(t -> {
            if (t.getRequest() == null || t.getRequest().getParameters() == null
                    || t.getRequest().getParameters().getProviderSpecific() == null) {
                return reactor.core.publisher.Mono.empty();
            }
            var ps = t.getRequest().getParameters().getProviderSpecific();
            Object flag = ps.get(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION);
            Object used = ps.get(BillingKeys.USED_PUBLIC_MODEL);
            if (!Boolean.TRUE.equals(flag) || !Boolean.TRUE.equals(used)) {
                return reactor.core.publisher.Mono.empty();
            }
            // 进一步校验：补建前必须具备 userId 与 featureType
            if (t.getUserId() == null || String.valueOf(ps.get(BillingKeys.STREAM_FEATURE_TYPE)) == null) {
                log.warn("对账跳过缺字段trace: traceId={} userId={} featureType={}", t.getTraceId(), t.getUserId(), String.valueOf(ps.get(BillingKeys.STREAM_FEATURE_TYPE)));
                return reactor.core.publisher.Mono.empty();
            }
            return txRepo.existsByTraceId(t.getTraceId())
                .flatMap(exists -> {
                    if (Boolean.TRUE.equals(exists)) return reactor.core.publisher.Mono.empty();
                    log.warn("对账发现缺失交易，触发补建: traceId={}", t.getTraceId());
                    // 直接创建PENDING交易，交由补偿服务处理
                    com.ainovel.server.domain.model.billing.CreditTransaction pending = com.ainovel.server.domain.model.billing.CreditTransaction.builder()
                        .traceId(t.getTraceId())
                        .userId(t.getUserId())
                        .provider(t.getProvider())
                        .modelId(t.getModel())
                        .featureType(String.valueOf(ps.get(BillingKeys.STREAM_FEATURE_TYPE)))
                        .inputTokens(t.getResponse() != null && t.getResponse().getMetadata() != null && t.getResponse().getMetadata().getTokenUsage() != null ? t.getResponse().getMetadata().getTokenUsage().getInputTokenCount() : 0)
                        .outputTokens(t.getResponse() != null && t.getResponse().getMetadata() != null && t.getResponse().getMetadata().getTokenUsage() != null ? t.getResponse().getMetadata().getTokenUsage().getOutputTokenCount() : 0)
                        .status("PENDING")
                        .billingMode("ACTUAL") // 若为0，补偿时会改为ESTIMATED
                        .estimated(Boolean.FALSE)
                        .build();
                    return txRepo.save(pending).then();
                });
        }).subscribe();
    }
}


