package com.ainovel.server.service.ai.observability;

import com.ainovel.server.domain.model.observability.LLMTrace;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.billing.BillingKeys;
import com.ainovel.server.service.ai.observability.events.LLMTraceEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

/**
 * 计费追踪事件监听器（骨架）：
 * 监听 LLMTraceEvent，并在后续版本中基于 tokenUsage 进行实际结算/补扣/退款。
 * 当前提交仅作占位与日志，避免打断现有流程。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class BillingTraceEventListener {

    private final CreditService creditService;

    @Async("llmTraceExecutor")
    @EventListener
    public void handleLLMTraceEvent(LLMTraceEvent event) {
        try {
            LLMTrace trace = event.getTrace();
            if (trace == null) return;
            String traceId = trace.getTraceId();
            // 通过 businessType 判断是否为工具阶段，若是则跳过
            try {
                String bt = trace.getBusinessType();
                if (bt != null && bt.equalsIgnoreCase(com.ainovel.server.domain.model.AIFeatureType.SETTING_GENERATION_TOOL.name())) {
                    return;
                }
                // 仅公共模型请求才进行后结算（标记由装饰器基于modelConfigId自动写入）
                var ps = trace.getRequest() != null && trace.getRequest().getParameters() != null
                        ? trace.getRequest().getParameters().getProviderSpecific() : null;
                if (ps == null || !Boolean.TRUE.equals(ps.get(BillingKeys.USED_PUBLIC_MODEL))) {
                    return;
                }
                // 若为公共模型的流式后扣费链路，改由 RichTraceChatModelListener 发布 CreditAdjustmentRequestedEvent
                // 并通过 BillingOrchestrator 串行、幂等处理，避免重复结算
                Object requiresPost = ps.get(BillingKeys.REQUIRES_POST_STREAM_DEDUCTION);
                if (Boolean.TRUE.equals(requiresPost)) {
                    // 明确跳过，防止与 BillingOrchestrator 重复
                    log.debug("[BillingTrace] 跳过流式后扣费链路的直接调整: traceId={}", traceId);
                    return;
                }
            } catch (Exception ignore) {}
            Integer inTok = trace.getResponse() != null && trace.getResponse().getMetadata() != null && trace.getResponse().getMetadata().getTokenUsage() != null
                    ? trace.getResponse().getMetadata().getTokenUsage().getInputTokenCount() : null;
            Integer outTok = trace.getResponse() != null && trace.getResponse().getMetadata() != null && trace.getResponse().getMetadata().getTokenUsage() != null
                    ? trace.getResponse().getMetadata().getTokenUsage().getOutputTokenCount() : null;
            if (inTok != null && outTok != null) {
                // 非流式/非后扣费链路若需要，可在此扩展；当前先不直接结算，避免重复
                log.debug("[BillingTrace] 非后扣费链路，当前不直接调整: traceId={}, in={}, out={}", traceId, inTok, outTok);
            }
        } catch (Exception e) {
            log.warn("[BillingTrace] 处理LLMTraceEvent失败: {}", e.getMessage());
        }
    }
}


