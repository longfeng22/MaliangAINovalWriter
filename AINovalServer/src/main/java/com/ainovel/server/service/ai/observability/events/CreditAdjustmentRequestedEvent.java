package com.ainovel.server.service.ai.observability.events;

import com.ainovel.server.domain.model.observability.LLMTrace;
import lombok.Getter;
import org.springframework.context.ApplicationEvent;

/**
 * 费用调整请求事件
 * 当AI调用完成后，基于真实token使用量调整预扣费
 */
@Getter
public class CreditAdjustmentRequestedEvent extends ApplicationEvent {
    
    private final LLMTrace trace;
    
    public CreditAdjustmentRequestedEvent(Object source, LLMTrace trace) {
        super(source);
        this.trace = trace;
    }
}
