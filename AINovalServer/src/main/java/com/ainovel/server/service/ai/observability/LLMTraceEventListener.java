package com.ainovel.server.service.ai.observability;

import com.ainovel.server.service.ai.observability.events.LLMTraceEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import reactor.core.scheduler.Schedulers;

/**
 * LLM追踪事件监听器
 * 异步处理追踪事件，避免影响主业务流程
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class LLMTraceEventListener {

    private final LLMTraceService traceService;

    /**
     * 异步处理LLM追踪事件
     * 使用虚拟线程进行非阻塞IO操作
     */
    @Async("llmTraceExecutor")
    @EventListener
    public void handleLLMTraceEvent(LLMTraceEvent event) {
        log.info("📥 接收到LLMTraceEvent: traceId={}, source={}, type={}", 
                event.getTrace().getTraceId(), 
                event.getSource().getClass().getSimpleName(),
                event.getTrace().getType());
        traceService.save(event.getTrace())
                .subscribeOn(Schedulers.boundedElastic()) // 使用弹性调度器处理IO
                .subscribe(
                        saved -> log.info("💾 LLM追踪记录保存成功: traceId={}, provider={}, model={}", 
                                saved.getTraceId(), saved.getProvider(), saved.getModel()),
                        error -> log.error("❌ LLM追踪记录保存失败: traceId={}", 
                                event.getTrace().getTraceId(), error)
                );
    }
}