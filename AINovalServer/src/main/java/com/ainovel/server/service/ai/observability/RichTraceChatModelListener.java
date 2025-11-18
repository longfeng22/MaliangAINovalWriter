package com.ainovel.server.service.ai.observability;

import com.ainovel.server.domain.model.observability.LLMTrace;
import com.ainovel.server.service.ai.observability.events.LLMTraceEvent;
import dev.langchain4j.model.chat.listener.ChatModelListener;
import dev.langchain4j.model.chat.listener.ChatModelRequestContext;
import dev.langchain4j.model.chat.listener.ChatModelResponseContext;
import dev.langchain4j.model.chat.listener.ChatModelErrorContext;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.request.ChatRequestParameters;
import dev.langchain4j.model.chat.response.ChatResponse;
import dev.langchain4j.model.chat.response.ChatResponseMetadata;
import dev.langchain4j.model.openai.OpenAiChatRequestParameters;
import dev.langchain4j.model.openai.OpenAiChatResponseMetadata;
import dev.langchain4j.model.openai.OpenAiTokenUsage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

import org.springframework.context.ApplicationEventPublisher;

import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.List;

/**
 * LangChain4j富化追踪监听器
 * 从LangChain4j的详细上下文中提取更多信息来增强追踪数据
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class RichTraceChatModelListener implements ChatModelListener {

    private final ApplicationEventPublisher eventPublisher;
    private final TraceContextManager traceContextManager;
    private final org.springframework.context.ApplicationEventPublisher billingEventPublisher;
    private final ObservabilityConfig observabilityConfig;
    private static final String TRACE_ATTR_KEY = "llm.trace";

    @Override
    public void onRequest(ChatModelRequestContext context) {
        log.info("🚀 RichTraceChatModelListener.onRequest 被调用");
        try {
            // 从Reactor Context获取AOP创建的Trace对象并存储到attributes中
            enrichTraceWithRequestDetails(context);
        } catch (Exception e) {
            log.error("增强追踪请求信息时出错", e);
        }
    }

    @Override
    public void onResponse(ChatModelResponseContext context) {
        log.info("🚀 RichTraceChatModelListener.onResponse 被调用");
        try {
            // 从attributes中获取Trace对象并增强响应信息（支持跨线程）
            enrichTraceWithResponseDetails(context);
        } catch (Exception e) {
            log.error("增强追踪响应信息时出错", e);
        }
    }

    @Override
    public void onError(ChatModelErrorContext context) {
        try {
            // 增强错误信息
            enrichTraceWithErrorDetails(context);
        } catch (Exception e) {
            log.debug("增强追踪错误信息时出错", e);
        }
    }

    /**
     * 增强请求详细信息，并将trace存储到attributes以支持跨线程访问
     */
    private void enrichTraceWithRequestDetails(ChatModelRequestContext context) {
        //log.info("🔍 开始增强请求详细信息，检查各种trace来源...");
        
        // 🚀 优先从TraceContextManager获取trace（新的主要方式）
        LLMTrace trace = traceContextManager.getTrace();
        if (trace != null) {
            log.info("✅ 从TraceContextManager中找到trace: traceId={}", trace.getTraceId());
            // 🚀 关键：将trace存储到attributes中，以便在不同线程的onResponse中访问
            context.attributes().put(TRACE_ATTR_KEY, trace);
            enhanceRequestDetails(trace, context);
            return;
        }
        
        // 🚀 其次检查attributes中是否已经有trace（兼容性）
        Object existingTrace = context.attributes().get(TRACE_ATTR_KEY);
        if (existingTrace instanceof LLMTrace attributeTrace) {
            //log.info("✅ 从attributes中找到现有trace: traceId={}", attributeTrace.getTraceId());
            enhanceRequestDetails(attributeTrace, context);
            return;
        }
        
        // 🚀 最后尝试从Reactor Context获取（兼容性，很可能不会成功）
        try {
            Mono.deferContextual(ctx -> {
                if (ctx.hasKey(LLMTrace.class)) {
                    LLMTrace reactorTrace = ctx.get(LLMTrace.class);
                    //log.info("✅ 从Reactor Context中找到trace: traceId={}", reactorTrace.getTraceId());
                    
                    // 🚀 关键：将trace存储到attributes中，以便在不同线程的onResponse中访问
                    context.attributes().put(TRACE_ATTR_KEY, reactorTrace);
                    enhanceRequestDetails(reactorTrace, context);
                } else {
                    log.warn("❌ 未在任何地方找到LLMTrace对象");
                    log.warn("🔍 TraceContextManager: {}, attributes: {}, Reactor Context: 无trace", 
                            trace, context.attributes().get(TRACE_ATTR_KEY));
                }
                return Mono.empty();
            }).block(); // 🚀 使用block()确保同步执行
        } catch (Exception e) {
            log.error("从Reactor Context获取trace时出错", e);
        }
    }
    
    /**
     * 增强请求详细信息的具体实现
     */
    private void enhanceRequestDetails(LLMTrace trace, ChatModelRequestContext context) {
        try {
            ChatRequest chatRequest = context.chatRequest();
            ChatRequestParameters params = chatRequest.parameters();

            // 增强通用参数
            if (params.topP() != null) {
                trace.getRequest().getParameters().setTopP(params.topP());
            }
            if (params.topK() != null) {
                trace.getRequest().getParameters().setTopK(params.topK());
            }
            if (params.stopSequences() != null) {
                trace.getRequest().getParameters().setStopSequences(params.stopSequences());
            }
            if (params.responseFormat() != null) {
                trace.getRequest().getParameters().setResponseFormat(params.responseFormat().toString());
            }

            // 增强工具规范
            if (observabilityConfig.isIncludeToolSpecifications()
                    && params.toolSpecifications() != null && !params.toolSpecifications().isEmpty()) {
                params.toolSpecifications().forEach(toolSpec -> {
                    LLMTrace.ToolSpecification traceToolSpec = LLMTrace.ToolSpecification.builder()
                            .name(toolSpec.name())
                            .description(toolSpec.description())
                            .parameters(toolSpec.parameters() != null ? 
                                      convertToMap(toolSpec.parameters()) : new HashMap<>())
                            .build();
                    trace.getRequest().getParameters().getToolSpecifications().add(traceToolSpec);
                });
            }

            if (params.toolChoice() != null) {
                trace.getRequest().getParameters().setToolChoice(params.toolChoice().toString());
            }

            // 增强提供商特定参数（与业务标记“合并”而非覆盖）
            Map<String, Object> providerSpecific = trace.getRequest().getParameters().getProviderSpecific();
            if (providerSpecific == null) {
                providerSpecific = new HashMap<>();
            } else {
                providerSpecific = new HashMap<>(providerSpecific); // 拷贝一份，避免副作用
            }
            if (params instanceof OpenAiChatRequestParameters openAiParams) {
                if (openAiParams.seed() != null) {
                    providerSpecific.put("seed", openAiParams.seed());
                }
                if (openAiParams.logitBias() != null) {
                    providerSpecific.put("logitBias", openAiParams.logitBias());
                }
                if (openAiParams.user() != null) {
                    providerSpecific.put("user", openAiParams.user());
                }
                if (openAiParams.parallelToolCalls() != null) {
                    providerSpecific.put("parallelToolCalls", openAiParams.parallelToolCalls());
                }
            }
            trace.getRequest().getParameters().setProviderSpecific(providerSpecific);
            // 记录关键计费标记，帮助定位注入是否到位
            try {
                Object f1 = providerSpecific.get("requiresPostStreamDeduction");
                Object f2 = providerSpecific.get("streamFeatureType");
                Object f3 = providerSpecific.get("usedPublicModel");
                log.info("🔎 providerSpecific关键标记: requiresPostStreamDeduction={}, streamFeatureType={}, usedPublicModel={}", f1, f2, f3);
            } catch (Exception ignore) {}
            log.info("✅ 已合并providerSpecific参数, keys={}", providerSpecific.keySet());

            log.info("✅ 已增强追踪请求信息: traceId={}", trace.getTraceId());
        } catch (Exception e) {
            log.error("增强请求详细信息时出错: traceId={}", trace.getTraceId(), e);
        }
    }

    /**
     * 增强响应详细信息（从attributes中获取trace，支持跨线程访问）
     */
    private void enrichTraceWithResponseDetails(ChatModelResponseContext context) {
        log.info("🔍 开始增强响应详细信息，检查attributes...");
        
        // 🚀 从attributes中获取trace（跨线程安全）
        Object traceObj = context.attributes().get(TRACE_ATTR_KEY);
        log.info("📋 attributes中的trace对象: {}", traceObj != null ? traceObj.getClass().getSimpleName() : "null");
        
        if (traceObj instanceof LLMTrace trace) {
            log.info("✅ 从attributes中找到LLMTrace: traceId={}", trace.getTraceId());
            try {
                // 确保trace有响应对象，如果没有则创建一个基本的
                if (trace.getResponse() == null) {
                    trace.setResponse(LLMTrace.Response.builder()
                            .metadata(LLMTrace.Metadata.builder().build())
                            .build());
                }
                
                ChatResponse chatResponse = context.chatResponse();
                ChatResponseMetadata metadata = chatResponse.metadata();

                // 增强基本元数据
                if (metadata.id() != null) {
                    trace.getResponse().getMetadata().setId(metadata.id());
                }
                if (metadata.finishReason() != null) {
                    trace.getResponse().getMetadata().setFinishReason(metadata.finishReason().toString());
                }

                // 🎯 关键：增强Token使用信息（这是修复的核心）
                if (metadata.tokenUsage() != null) {
                    LLMTrace.TokenUsageInfo tokenUsage = LLMTrace.TokenUsageInfo.builder()
                            .inputTokenCount(metadata.tokenUsage().inputTokenCount())
                            .outputTokenCount(metadata.tokenUsage().outputTokenCount())
                            .totalTokenCount(metadata.tokenUsage().totalTokenCount())
                            .build();

                    // OpenAI特定的Token信息
                    if (metadata.tokenUsage() instanceof OpenAiTokenUsage openAiUsage) {
                        Map<String, Object> tokenSpecific = new HashMap<>();
                        if (openAiUsage.inputTokensDetails() != null) {
                            tokenSpecific.put("inputTokensDetails", Map.of(
                                "cachedTokens", openAiUsage.inputTokensDetails().cachedTokens()
                            ));
                        }
                        if (openAiUsage.outputTokensDetails() != null) {
                            tokenSpecific.put("outputTokensDetails", Map.of(
                                "reasoningTokens", openAiUsage.outputTokensDetails().reasoningTokens()
                            ));
                        }
                        tokenUsage.setProviderSpecific(tokenSpecific);
                    }

                    trace.getResponse().getMetadata().setTokenUsage(tokenUsage);
                    log.debug("已设置Token使用信息: input={}, output={}, total={}", 
                             tokenUsage.getInputTokenCount(), 
                             tokenUsage.getOutputTokenCount(), 
                             tokenUsage.getTotalTokenCount());
                }

                // 额外：从请求参数的providerSpecific中读取业务标识，补充businessType与关联信息
                try {
                    if (trace.getRequest() != null && trace.getRequest().getParameters() != null
                        && trace.getRequest().getParameters().getProviderSpecific() != null) {
                        Object reqType = trace.getRequest().getParameters().getProviderSpecific().get("requestType");
                        if (reqType != null && (trace.getBusinessType() == null || trace.getBusinessType().isBlank())) {
                            trace.setBusinessType(reqType.toString());
                        }
                        Object correlationId = trace.getRequest().getParameters().getProviderSpecific().get("correlationId");
                        if (correlationId != null && (trace.getCorrelationId() == null || trace.getCorrelationId().isBlank())) {
                            trace.setCorrelationId(correlationId.toString());
                        }
                    }
                } catch (Exception ignore) {}

                // 增强提供商特定元数据
                Map<String, Object> responseProviderSpecific = new HashMap<>();
                if (metadata instanceof OpenAiChatResponseMetadata openAiMetadata) {
                    if (openAiMetadata.systemFingerprint() != null) {
                        responseProviderSpecific.put("systemFingerprint", openAiMetadata.systemFingerprint());
                    }
                    if (openAiMetadata.created() != null) {
                        responseProviderSpecific.put("created", openAiMetadata.created());
                    }
                    if (openAiMetadata.serviceTier() != null) {
                        responseProviderSpecific.put("serviceTier", openAiMetadata.serviceTier());
                    }
                }
                trace.getResponse().getMetadata().setProviderSpecific(responseProviderSpecific);

                // 🎯 补充响应中的工具调用（在发布事件前写入，避免竞态导致丢失）
                try {
                    dev.langchain4j.data.message.AiMessage aiMsg = chatResponse.aiMessage();
                    if (aiMsg != null && aiMsg.hasToolExecutionRequests()
                            && aiMsg.toolExecutionRequests() != null
                            && !aiMsg.toolExecutionRequests().isEmpty()) {

                        // 确保存在响应消息对象，但不要覆盖已有内容
                        if (trace.getResponse().getMessage() == null) {
                            com.ainovel.server.domain.model.observability.LLMTrace.MessageInfo msg =
                                    com.ainovel.server.domain.model.observability.LLMTrace.MessageInfo.builder()
                                            .role("assistant")
                                            .content(aiMsg.text())
                                            .build();
                            trace.getResponse().setMessage(msg);
                        }

                        List<com.ainovel.server.domain.model.observability.LLMTrace.ToolCallInfo> extracted = new ArrayList<>();
                        for (var req : aiMsg.toolExecutionRequests()) {
                            extracted.add(
                                com.ainovel.server.domain.model.observability.LLMTrace.ToolCallInfo.builder()
                                    .id(req.id())
                                    .type("function")
                                    .functionName(req.name())
                                    .arguments(req.arguments())
                                    .build()
                            );
                        }

                        List<com.ainovel.server.domain.model.observability.LLMTrace.ToolCallInfo> existing =
                                trace.getResponse().getMessage().getToolCalls();
                        if (existing == null || existing.isEmpty()) {
                            trace.getResponse().getMessage().setToolCalls(extracted);
                        } else {
                            // 合并去重（按 id 优先，其次按 name+args）
                            Map<String, com.ainovel.server.domain.model.observability.LLMTrace.ToolCallInfo> merged = new LinkedHashMap<>();
                            for (var tc : existing) {
                                if (tc == null) continue;
                                String key = (tc.getId() != null && !tc.getId().isBlank())
                                        ? tc.getId()
                                        : (tc.getFunctionName() + ":" + (tc.getArguments() != null ? tc.getArguments() : ""));
                                merged.putIfAbsent(key, tc);
                            }
                            for (var tc : extracted) {
                                if (tc == null) continue;
                                String key = (tc.getId() != null && !tc.getId().isBlank())
                                        ? tc.getId()
                                        : (tc.getFunctionName() + ":" + (tc.getArguments() != null ? tc.getArguments() : ""));
                                merged.putIfAbsent(key, tc);
                            }
                            trace.getResponse().getMessage().setToolCalls(new ArrayList<>(merged.values()));
                        }
                    }
                } catch (Exception e) {
                    log.debug("附加工具调用到trace失败: {}", e.getMessage());
                }

                log.debug("已增强追踪响应信息（跨线程）: traceId={}", trace.getTraceId());
                
                // 🚀 关键：在增强完成后发布事件，确保tokenUsage已写入
                try {
                    // 🚀 新增：处理公共模型流式请求的后扣费
                    handlePublicModelPostStreamDeduction(trace);

                    // 流式场景：仅增强，不在监听器中发布事件，留给装饰器在流结束时发布（保证聚合内容存在）
                    if (trace.getType() == com.ainovel.server.domain.model.observability.LLMTrace.CallType.STREAMING_CHAT) {
                        log.info("🔄 Streaming 请求：在监听器中仅增强，不发布事件: traceId={}, type={}", trace.getTraceId(), trace.getType());
                    } else {
                        log.info("📤 非流式请求：监听器发布事件: traceId={}, type={}", trace.getTraceId(), trace.getType());
                        eventPublisher.publishEvent(new LLMTraceEvent(this, trace));
                        log.info("✅ LLM追踪事件已发布（含完整tokenUsage）: traceId={}", trace.getTraceId());
                        // 非流式：发布后清理
                        traceContextManager.clearTrace();
                        log.debug("已清理trace上下文: traceId={}", trace.getTraceId());
                    }
                } catch (Exception publishError) {
                    log.error("发布LLM追踪事件失败: traceId={}", trace.getTraceId(), publishError);
                }
            } catch (Exception e) {
                log.warn("增强追踪响应信息时出错: traceId={}", trace.getTraceId(), e);
                // 🔧 修复：避免重复发布事件，只在非流式或增强失败时发布一次
                try {
                    if (trace.getType() != com.ainovel.server.domain.model.observability.LLMTrace.CallType.STREAMING_CHAT) {
                        // 非流式：增强失败时仍需发布事件（但不重复）
                        log.info("📤 增强失败-非流式请求：监听器发布事件: traceId={}, type={}", trace.getTraceId(), trace.getType());
                        eventPublisher.publishEvent(new LLMTraceEvent(this, trace));
                        log.info("⚠️ 增强失败但已发布LLM追踪事件: traceId={}", trace.getTraceId());
                    } else {
                        log.info("🔄 增强失败-流式请求：不在监听器中发布事件，等待装饰器处理: traceId={}, type={}", trace.getTraceId(), trace.getType());
                    }
                } catch (Exception publishError) {
                    log.error("发布LLM追踪事件失败: traceId={}", trace.getTraceId(), publishError);
                } finally {
                    // 🚀 清理trace上下文，防止内存泄漏
                    traceContextManager.clearTrace();
                    log.debug("异常情况下已清理trace上下文: traceId={}", trace.getTraceId());
                }
            }
        } else {
            log.warn("❌ 未在attributes中找到LLMTrace对象！");
            log.warn("📋 当前attributes内容: {}", context.attributes());
            log.warn("🔍 可能原因: 1) onRequest没有被调用 2) trace没有被正确存储到attributes 3) 不同的attributes实例");
        }
    }

    /**
     * 增强错误详细信息（从attributes中获取trace，支持跨线程访问）
     */
    private void enrichTraceWithErrorDetails(ChatModelErrorContext context) {
        // 🚀 从attributes中获取trace（跨线程安全）
        Object traceObj = context.attributes().get(TRACE_ATTR_KEY);
        if (traceObj instanceof LLMTrace trace) {
            try {
                if (trace.getError() != null) {
                    // 可以根据具体错误类型增强错误信息
                    log.debug("已增强追踪错误信息（跨线程）: traceId={}", trace.getTraceId());
                }
                
                // 🚀 发布错误事件
                try {
                    if (trace.getType() == com.ainovel.server.domain.model.observability.LLMTrace.CallType.STREAMING_CHAT) {
                        log.debug("Streaming 请求错误：在监听器中仅增强错误，不发布事件，留待装饰器处理: traceId={}", trace.getTraceId());
                    } else {
                        eventPublisher.publishEvent(new LLMTraceEvent(this, trace));
                        log.debug("LLM追踪错误事件已发布: traceId={}", trace.getTraceId());
                        traceContextManager.clearTrace();
                        log.debug("错误处理完成，已清理trace上下文: traceId={}", trace.getTraceId());
                    }
                } catch (Exception publishError) {
                    log.error("发布LLM追踪错误事件失败: traceId={}", trace.getTraceId(), publishError);
                }
            } catch (Exception e) {
                log.warn("增强追踪错误信息时出错: traceId={}", trace.getTraceId(), e);
                // 即使增强失败，也要尝试发布事件
                try {
                    eventPublisher.publishEvent(new LLMTraceEvent(this, trace));
                } catch (Exception publishError) {
                    log.error("发布LLM追踪错误事件失败: traceId={}", trace.getTraceId(), publishError);
                } finally {
                    // 🚀 清理trace上下文，防止内存泄漏
                    traceContextManager.clearTrace();
                    log.debug("异常错误处理完成，已清理trace上下文: traceId={}", trace.getTraceId());
                }
            }
        } else {
            log.debug("未在attributes中找到LLMTrace对象，无法增强错误信息");
        }
    }

    /**
     * 🚀 新增：处理公共模型流式请求的后扣费
     */
    private void handlePublicModelPostStreamDeduction(LLMTrace trace) {
        try {
            // 检查是否是需要后扣费的公共模型流式请求
            if (trace.getRequest() == null || trace.getRequest().getParameters() == null || 
                trace.getRequest().getParameters().getProviderSpecific() == null) {
                return;
            }
            
            Map<String, Object> providerSpecific = trace.getRequest().getParameters().getProviderSpecific();
            Object requiresPostDeduction = providerSpecific.get(com.ainovel.server.service.billing.BillingKeys.REQUIRES_POST_STREAM_DEDUCTION);
            Object streamFeatureType = providerSpecific.get(com.ainovel.server.service.billing.BillingKeys.STREAM_FEATURE_TYPE);
            Object isPublicModel = providerSpecific.get(com.ainovel.server.service.billing.BillingKeys.USED_PUBLIC_MODEL);

            log.info("🔎 后扣费判定检查: requiresPostStreamDeduction={}, streamFeatureType={}, usedPublicModel={}, providerSpecificKeys={}",
                    requiresPostDeduction, streamFeatureType, isPublicModel,
                    providerSpecific != null ? providerSpecific.keySet() : java.util.Collections.emptySet());
            
            // 设定生成的工具编排：若打了跳过计费标记，则跳过发布调整事件
            Object skipBilling = providerSpecific.get(com.ainovel.server.service.billing.BillingKeys.SKIP_BILLING_FOR_TOOL_ORCHESTRATION);
            if (Boolean.TRUE.equals(skipBilling)) {
                log.info("计费跳过：工具编排链路，traceId={}", trace.getTraceId());
                return;
            }

            if (Boolean.TRUE.equals(requiresPostDeduction) && streamFeatureType != null && Boolean.TRUE.equals(isPublicModel)) {
                // 获取真实的token使用量
                if (trace.getResponse() != null && trace.getResponse().getMetadata() != null 
                    && trace.getResponse().getMetadata().getTokenUsage() != null) {
                    
                    LLMTrace.TokenUsageInfo tokenUsage = trace.getResponse().getMetadata().getTokenUsage();
                    String userId = trace.getUserId();
                    
                    if (tokenUsage.getInputTokenCount() != null && tokenUsage.getOutputTokenCount() != null && userId != null) {
                        // 🚀 重构：发布费用调整事件，而不是直接扣费事件
                        try {
                            billingEventPublisher.publishEvent(new com.ainovel.server.service.ai.observability.events.CreditAdjustmentRequestedEvent(this, trace));
                            log.info("🧾 已发布CreditAdjustmentRequestedEvent: traceId={}", trace.getTraceId());
                        } catch (Exception e) {
                            log.error("发布CreditAdjustmentRequestedEvent失败: traceId={}", trace.getTraceId(), e);
                        }
                    } else {
                        log.warn("公共模型流式请求缺少必要的扣费信息: userId={}, inputTokens={}, outputTokens={}", 
                                userId, tokenUsage.getInputTokenCount(), tokenUsage.getOutputTokenCount());
                    }
                } else {
                    log.warn("公共模型流式请求缺少token使用量信息，无法进行后扣费");
                }
            } else {
                log.info("后扣费未触发，原因: requiresPostStreamDeduction={}, streamFeatureType={}, usedPublicModel={}",
                        requiresPostDeduction, streamFeatureType, isPublicModel);
            }
        } catch (Exception e) {
            log.error("处理公共模型流式请求后扣费时出错", e);
        }
    }

    /**
     * 转换工具参数对象为Map
     */
    private Map<String, Object> convertToMap(Object parameters) {
        // 这里可以使用Jackson ObjectMapper进行转换
        // 为简化示例，返回空Map
        return new HashMap<>();
    }
} 