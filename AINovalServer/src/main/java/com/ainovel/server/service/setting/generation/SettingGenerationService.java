package com.ainovel.server.service.setting.generation;

import com.ainovel.server.domain.model.setting.generation.*;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.domain.model.NovelSettingGenerationHistory;
import com.ainovel.server.domain.model.SettingType;
import com.ainovel.server.service.AIService;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.NovelAIService;
import com.ainovel.server.service.NovelSettingService;

import com.ainovel.server.service.ai.tools.ToolExecutionService;
import com.ainovel.server.service.ai.tools.ToolRegistry;
import com.ainovel.server.service.setting.generation.tools.BatchCreateNodesTool;
import com.ainovel.server.service.setting.generation.tools.CreateSettingNodeTool;
import com.ainovel.server.service.setting.generation.tools.MarkModificationCompleteTool;
import com.ainovel.server.service.setting.SettingConversionService;
import com.ainovel.server.service.setting.NovelSettingHistoryService;
import dev.langchain4j.agent.tool.ToolSpecification;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.UserMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import reactor.core.publisher.Sinks;
import reactor.core.scheduler.Schedulers;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * 设定生成服务
 * 使用解耦的工具架构和内存会话管理
 */
@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"unused"})
public class SettingGenerationService implements ISettingGenerationService {
    
    private final InMemorySessionManager sessionManager;
    private final SettingValidationService validationService;
    private final StructuredSettingOutputValidator structuredOutputValidator;
    private final SettingGenerationStrategyFactory strategyFactory;
    private final ToolRegistry toolRegistry;
    private final AIService aiService;
    private final ToolExecutionService toolExecutionService;
    private final NovelAIService novelAIService;
    private final SettingConversionService conversionService;
    private final NovelSettingHistoryService historyService;
    private final NovelSettingService novelSettingService;
    private final com.ainovel.server.repository.EnhancedUserPromptTemplateRepository promptTemplateRepository;
    private final com.ainovel.server.service.prompt.providers.SettingTreeGenerationPromptProvider promptProvider;
    private final com.ainovel.server.service.ai.orchestration.ToolStreamingOrchestrator toolStreamingOrchestrator;
    private final com.ainovel.server.service.PublicModelConfigService publicModelConfigService;
    private final com.ainovel.server.service.CreditService creditService;
    private final com.ainovel.server.service.ai.observability.TraceContextManager traceContextManager;
    private final com.ainovel.server.service.UserAIModelConfigService userAIModelConfigService;
    // 移除公共AI应用服务依赖（统一由Provider装饰器负责）
    private final com.fasterxml.jackson.databind.ObjectMapper objectMapper;
    @SuppressWarnings("unused")
    private final com.ainovel.server.service.CostEstimationService costEstimationService;
    private final com.ainovel.server.service.ai.tools.fallback.ToolFallbackRegistry toolFallbackRegistry;
    // 📚 知识库Repository
    private final com.ainovel.server.repository.NovelKnowledgeBaseRepository knowledgeBaseRepository;
    // 计费常量
    @SuppressWarnings("unused") private static final String USED_PUBLIC_MODEL_KEY = com.ainovel.server.service.billing.BillingKeys.USED_PUBLIC_MODEL;
    @SuppressWarnings("unused") private static final String REQUIRES_POST_STREAM_DEDUCTION_KEY = com.ainovel.server.service.billing.BillingKeys.REQUIRES_POST_STREAM_DEDUCTION;
    @SuppressWarnings("unused") private static final String STREAM_FEATURE_TYPE_KEY = com.ainovel.server.service.billing.BillingKeys.STREAM_FEATURE_TYPE;
    @SuppressWarnings("unused") private static final String PUBLIC_MODEL_CONFIG_ID_KEY = com.ainovel.server.service.billing.BillingKeys.PUBLIC_MODEL_CONFIG_ID;
    
    // 文本阶段循环轮数（默认3，可通过配置覆盖）
    @Value("${setting.generation.text-phase.iterations:3}")
    private int textPhaseIterations;
    
    // 存储每个会话的事件发射器
    private final Map<String, Sinks.Many<SettingGenerationEvent>> eventSinks = new ConcurrentHashMap<>();

    // 增加会话锁，防止并发修改
    private final Map<String, Object> sessionLocks = new ConcurrentHashMap<>();
    // 生成完成过程的并发防抖标记
    private final java.util.Set<String> completingSessions = java.util.Collections.newSetFromMap(new java.util.concurrent.ConcurrentHashMap<>());
    private final java.util.Set<String> completedSessions = java.util.Collections.newSetFromMap(new java.util.concurrent.ConcurrentHashMap<>());

    // 在途工具编排任务：按会话跟踪 taskId -> 启动时间戳
    private final Map<String, java.util.concurrent.ConcurrentHashMap<String, Long>> inFlightTasks = new ConcurrentHashMap<>();
    // 在途任务超时时间：3 分钟
    private static final long INFLIGHT_TIMEOUT_MS = java.util.concurrent.TimeUnit.MINUTES.toMillis(3);
    
    // 防重复工具调用机制 - 跟踪正在进行的工具调用
    private final java.util.concurrent.ConcurrentHashMap<String, Boolean> activeToolCalls = new java.util.concurrent.ConcurrentHashMap<>();

    // 移除业务层公共模型占位Provider，公共路径逻辑统一由底层装饰器处理
    
    @Override
    public Mono<SettingGenerationSession> startGeneration(
            String userId, String novelId, String initialPrompt,
            String promptTemplateId, String modelConfigId) {
        
        log.debug("Starting setting generation with template: {}", promptTemplateId);
        
        // 获取提示词模板
        return promptTemplateRepository.findById(promptTemplateId)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
            .flatMap(template -> {
                // 验证模板类型
                if (!template.isSettingGenerationTemplate()) {
                    return Mono.error(new IllegalArgumentException("Template is not for setting generation: " + promptTemplateId));
                }
                
                // 获取或创建策略适配器
                return strategyFactory.createConfigurableStrategy(template)
                    .map(Mono::just)
                    .orElse(Mono.error(new IllegalArgumentException("Cannot create strategy from template: " + promptTemplateId)))
                    .flatMap(strategyAdapter -> {
                        String strategyId = strategyAdapter.getStrategyId();
                        
                        // 创建会话
                        return sessionManager.createSession(userId, novelId, initialPrompt, strategyId, promptTemplateId)
                            .flatMap(session -> {
                                // 存储相关信息到会话元数据
                                session.getMetadata().put("modelConfigId", modelConfigId);
                                session.getMetadata().put("strategyAdapter", strategyAdapter);
                                
                                // 创建事件流（缓存所有事件，支持大量节点）
                                Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                                eventSinks.put(session.getSessionId(), sink);
                                
                                // 发送开始事件
                                emitEvent(session.getSessionId(), new SettingGenerationEvent.SessionStartedEvent(
                                    initialPrompt, strategyId
                                ));
                                
                                // 更新状态
                                return sessionManager.updateSessionStatus(
                                    session.getSessionId(),
                                    SettingGenerationSession.SessionStatus.GENERATING
                                ).thenReturn(session);
                            })
                            .flatMap(session -> {
                                // 异步启动生成
                                generateSettingsAsync(session, template, strategyAdapter)
                                    .subscribe(
                                        result -> log.info("Generation completed for session: {}", session.getSessionId()),
                                        error -> {
                                            if (isInterrupted(error)) {
                                                log.warn("Request interrupted, treat as CANCELLED: {}", session.getSessionId());
                                                cancelSession(session.getSessionId()).subscribe();
                                                return;
                                            }
                                            log.error("Generation failed for session: {}", session.getSessionId(), error);
                                            emitErrorEvent(session.getSessionId(), "GENERATION_FAILED",
                                                error.getMessage(), null, false);
                                            sessionManager.setSessionError(session.getSessionId(), error.getMessage())
                                                .subscribe();
                                        }
                                    );
                                
                                return Mono.just(session);
                            });
                    });
            });
    }

    @Override
    public Mono<SettingGenerationSession> startGenerationHybrid(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            String textEndSentinel,
            Boolean usePublicTextModel) {

        // 统一由服务端管理文本阶段结束标记，避免前端参数导致不一致
        final String endSentinel = "<<END_OF_SETTINGS>>";
        log.debug("Using server-managed textEndSentinel: {}", endSentinel);

        return promptTemplateRepository.findById(promptTemplateId)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
            .flatMap(template -> {
                if (!template.isSettingGenerationTemplate()) {
                    return Mono.error(new IllegalArgumentException("Template is not for setting generation: " + promptTemplateId));
                }
                return strategyFactory.createConfigurableStrategy(template)
                    .map(Mono::just)
                    .orElse(Mono.error(new IllegalArgumentException("Cannot create strategy from template: " + promptTemplateId)))
                    .flatMap(strategyAdapter -> sessionManager.createSession(userId, novelId, initialPrompt, strategyAdapter.getStrategyId(), promptTemplateId)
                        .flatMap(session -> {
                            // 事件流（缓存所有事件，支持大量节点）
                            Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                            eventSinks.put(session.getSessionId(), sink);
                            emitEvent(session.getSessionId(), new SettingGenerationEvent.SessionStartedEvent(initialPrompt, strategyAdapter.getStrategyId()));

                            // 设定生成遵循"前端先独立预估→用户确认→开始生成"，后端不再内嵌预估事件
                            // 记录调试信息：将结束标记写入会话元数据
                            try {
                                session.getMetadata().put("textEndSentinel", endSentinel);
                                session.getMetadata().put("modelConfigId", modelConfigId);
                                if (usePublicTextModel != null && usePublicTextModel.booleanValue()) {
                                    // 仅记录开关；公共配置ID不再直接沿用传入的 modelConfigId，待启动流前校验再写入
                                    session.getMetadata().put("usePublicTextModel", Boolean.TRUE);
                                }
                                sessionManager.saveSession(session).subscribe();
                            } catch (Exception ignore) {
                                log.warn("Failed to persist textEndSentinel for session {}", session.getSessionId());
                            }
                            return sessionManager.updateSessionStatus(session.getSessionId(), SettingGenerationSession.SessionStatus.GENERATING)
                                .thenReturn(new Object[]{session, template, strategyAdapter});
                        })
                        .flatMap(arr -> {
                            SettingGenerationSession session = (SettingGenerationSession) arr[0];
                            com.ainovel.server.domain.model.EnhancedUserPromptTemplate templateObj = (com.ainovel.server.domain.model.EnhancedUserPromptTemplate) arr[1];
                            ConfigurableStrategyAdapter strategyAdapterObj = (ConfigurableStrategyAdapter) arr[2];

                            // 统一：不再在业务层区分公共/私有模型，直接启动文本流
                                startStreamingTextToSettings(session, templateObj, strategyAdapterObj, modelConfigId, endSentinel)
                                    .onErrorResume(err -> {
                                        if (isInterrupted(err)) {
                                            log.warn("Text streaming interrupted for session {}, suppressing error and continuing", session.getSessionId());
                                            return Mono.just(0);
                                        }
                                        emitErrorEvent(session.getSessionId(), "HYBRID_FLOW_FAILED", err.getMessage(), null, true);
                                        return Mono.just(0);
                                    })
                                    .subscribe();
                            
                            // 立即返回会话，允许控制器尽快建立SSE订阅
                            return Mono.just(session);
                        }));
            });
    }



    /**
     * 流式文本阶段 + 增量工具解析：
     * - 使用用户模型配置进行流式文本生成
     * - 累计到一定长度或时间片后，将增量文本片段送入 text_to_settings 工具进行结构化
     * - 去重与父子映射由现有校验与 crossBatchTempIdMap 保障
     */
    private Mono<Integer> startStreamingTextToSettings(SettingGenerationSession session,
                                                       com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
                                                       ConfigurableStrategyAdapter strategyAdapter,
                                                       String userModelConfigId,
                                                       String endSentinel) {
        // 1) 构造 system/user（强调仅输出设定纯文本，尽量分段输出）
        Map<String, Object> ctx = buildPromptContext(session, template, strategyAdapter);
        return promptProvider.getSystemPrompt(session.getUserId(), ctx)
            .zipWith(promptProvider.getUserPrompt(session.getUserId(), template.getId(), ctx))
            .flatMap(prompts -> {
                String baseSys = prompts.getT1() +
                        "\n\n只输出设定纯文本，不要JSON/代码/工具调用。务必按如下严格格式输出，三行一组，每组代表一个设定节点，组与组之间以一个空行分隔：" +
                        "\n1) 当前节点<tempId> 标题：<名称>" +
                        "\n2) 父节点是：<parentTempId 或 null> [父节点标题：<父名称>]" +
                        "\n3) 内容：<该节点的描述>" +
                        "\n\n格式要求（必须遵守）：" +
                        "\n- 每个节点严格使用上述三行，并在节点与节点之间留一个空行。" +
                        "\n- 先创建用户期待深度的根节点，再创建其子节点。而不是先创建完所有父节点才创建相关子节点，比如用户期待创建深度为三，则创建一个根节点，三个第二层子节点，9个第三层子节点，而不是先创建完所有父节点才创建相关子节点。子节点数量可多可少，但必须满足用户期待深度。" +
                        "\n- <tempId> 使用如 R1、R1-1、R2-3 的形式；同一节点在多轮文本中必须保持 tempId 不变。" +
                        "\n- 根节点父节点写为 null；子节点父节点必须写其父节点的 tempId，并可在方括号中给出父节点标题。" +
                        "\n- 名称中不要包含 '/' 字符；如需斜杠请使用全角 '／'。" +
                        "\n- 严禁在同一行混写多个节点，严禁输出列表、表格、编号或Markdown标记。" +
                        "\n\n示例：" +
                        "\n当前节点R1 标题：魔法系统" +
                        "\n父节点是：null" +
                        "\n内容：本世界的超自然能力来源与运行规则的总称……" +
                        "\n\n当前节点R1-1 标题：法师" +
                        "\n父节点是：R1 [父节点标题：魔法系统]" +
                        "\n内容：能感知与操控魔力的人群，通常需要通过学派训练以掌握法术……";
                String baseUsr = prompts.getT2();

                // 2) 选择文本阶段模型：统一走用户配置（公共模型逻辑下沉至 Provider 装饰器）
                Mono<com.ainovel.server.service.ai.AIModelProvider> providerMonoEffective =
                    novelAIService.getAIModelProviderByConfigId(session.getUserId(), userModelConfigId);

                return providerMonoEffective
                    .flatMap(provider -> {
                        log.debug("[TextPhase] Provider resolved. providerIsNull={}", (provider == null));
                        // 2.2) 选择工具阶段模型（优先用户"工具调用默认"→公共→回退用户默认）
                        Mono<String[]> toolConfigMono = userAIModelConfigService.getValidatedToolDefaultConfiguration(session.getUserId())
                            .flatMap(cfg -> userAIModelConfigService.getDecryptedApiKey(session.getUserId(), cfg.getId())
                                .map(apiKey -> new String[] { cfg.getProvider(), cfg.getModelName(), apiKey, cfg.getApiEndpoint() }))
                            .onErrorResume(err -> {
                                log.warn("[Tool][Orchestrator] 读取用户工具默认模型失败，将尝试公共模型: {}", err != null ? err.getMessage() : "");
                                return Mono.empty();
                            })
                            .switchIfEmpty(
                                publicModelConfigService.findByFeatureType(com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                                    .doOnSubscribe(s -> log.debug("[Tool][Orchestrator] Fetching orchestrator model for feature: SETTING_TREE_GENERATION"))
                                    .collectList()
                                    .flatMap(list -> {
                                        java.util.Set<String> lcProviders = new java.util.HashSet<>(
                                            java.util.Arrays.asList(
                                                "openai", "anthropic", "gemini", "siliconflow", "togetherai",
                                                "doubao", "ark", "volcengine", "bytedance", "zhipu", "glm",
                                                "qwen", "dashscope", "tongyi", "alibaba"
                                            )
                                        );
                                        com.ainovel.server.domain.model.PublicModelConfig chosen = null;
                                        for (com.ainovel.server.domain.model.PublicModelConfig c : list) {
                                            String p = c.getProvider();
                                            if (p != null && lcProviders.contains(p.toLowerCase())) { chosen = c; break; }
                                        }
                                        if (chosen == null) {
                                            for (com.ainovel.server.domain.model.PublicModelConfig c : list) {
                                                String p = c.getProvider();
                                                if (p != null && lcProviders.contains(p.toLowerCase()) && c.getTags() != null && c.getTags().contains("jsonify")) { chosen = c; break; }
                                            }
                                        }
                                        if (chosen == null) {
                                            for (com.ainovel.server.domain.model.PublicModelConfig c : list) {
                                                if (c.getTags() != null && c.getTags().contains("jsonify")) { chosen = c; break; }
                                            }
                                        }
                                        if (chosen == null && !list.isEmpty()) { chosen = list.get(0); }
                                        if (chosen != null) {
                                            String providerName = chosen.getProvider();
                                            String modelId = chosen.getModelId();
                                            String apiEndpoint = chosen.getApiEndpoint();
                                            log.info("[Tool][Orchestrator] chosen provider={}, modelId={}, endpoint={}", providerName, modelId, apiEndpoint);
                                            return publicModelConfigService.getActiveDecryptedApiKey(providerName, modelId)
                                                .map(apiKey -> new String[] { providerName, modelId, apiKey, apiEndpoint });
                                        }
                                        return Mono.empty();
                                    })
                                    .timeout(java.time.Duration.ofSeconds(12))
                                    .onErrorResume(err -> {
                                        log.warn("[Tool][Orchestrator] 获取编排器模型配置失败或超时，将回退到用户默认模型: {}", err != null ? err.getMessage() : "");
                                        return novelAIService.getAIModelProvider(session.getUserId(), null)
                                            .map(p -> new String[] { p.getProviderName(), p.getModelName(), p.getApiKey(), p.getApiEndpoint() });
                                    })
                                    .switchIfEmpty(Mono.defer(() ->
                                        novelAIService.getAIModelProvider(session.getUserId(), null)
                                            .map(p -> new String[] { p.getProviderName(), p.getModelName(), p.getApiKey(), p.getApiEndpoint() })
                                    ))
                            );

                        final java.util.concurrent.atomic.AtomicReference<String> accumulatedText = new java.util.concurrent.atomic.AtomicReference<>("");
                        final int iterations = Math.max(1, textPhaseIterations);

                        java.util.function.Function<Integer, Mono<Integer>> runRound = new java.util.function.Function<Integer, Mono<Integer>>() {
                            @Override
                            public Mono<Integer> apply(Integer roundIndex) {
                                int r = (roundIndex == null) ? 0 : roundIndex.intValue();
                                boolean isFinalRound = r >= (iterations - 1);
                                log.debug("[文本阶段] 进入回合: {}/{}", r + 1, iterations);

                                // 文本阶段结束标记快速短路（等价于后续轮的break）
                                if (Boolean.TRUE.equals(session.getMetadata().get("textStreamEnded"))) {
                                    log.debug("[TextPhase] textStreamEnded=true, short-circuit round {}", r + 1);
                                    return Mono.just(1);
                                }

                                // 2.1) 构建请求（带上前轮上下文，避免重复并提升完整性）
                                java.util.List<com.ainovel.server.domain.model.AIRequest.Message> msgs = new java.util.ArrayList<>();
                                msgs.add(com.ainovel.server.domain.model.AIRequest.Message.builder().role("system").content(baseSys).build());
                                String prev = accumulatedText.get();
                                if (prev != null && !prev.isBlank()) {
                                    msgs.add(com.ainovel.server.domain.model.AIRequest.Message.builder()
                                        .role("assistant")
                                        .content("以下是此前轮的设定文本（供参考，避免重复）：\n" + prev)
                                        .build());
                                }
                                msgs.add(com.ainovel.server.domain.model.AIRequest.Message.builder().role("user").content(baseUsr).build());
                                // 公共模型逻辑已下沉至装饰器
                                final String modelForText = provider != null ? provider.getModelName() : null;

                                java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
                                meta.put("userId", session.getUserId() != null ? session.getUserId() : "system");
                                meta.put("sessionId", session.getSessionId());
                                meta.put("requestType", com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION.name());
                                Object mc = session.getMetadata() != null ? session.getMetadata().get("modelConfigId") : null;
                                if (mc != null) meta.put("modelConfigId", mc);

                                com.ainovel.server.domain.model.AIRequest req = com.ainovel.server.domain.model.AIRequest.builder()
                                    .model(modelForText)
                                    .messages(msgs)
                                    .userId(session.getUserId())
                                    .sessionId(session.getSessionId())
                                    .traceId(getOrCreateTraceId())
                                    .featureType(com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                                    .metadata(meta)
                                    .build();
                                log.debug("[文本阶段] 构建AI请求: 回合={}/{} 文本模型={} 消息数={} ", r + 1, iterations, modelForText, msgs.size());
                                // 直接走用户/当前provider流
                                com.ainovel.server.service.ai.AIModelProvider nonNullProvider = java.util.Objects.requireNonNull(provider, "模型提供商为空，无法启动文本流");
                                log.info("[文本阶段] 启动流式文本生成: provider={} model={} ", nonNullProvider.getProviderName(), nonNullProvider.getModelName());
                                reactor.core.publisher.Flux<String> textStream = nonNullProvider.generateContentStream(req);

                                // 私有模型：直接进入流式（与编排器配置并行预取，避免阻塞文本流启动）
                                final reactor.core.publisher.Mono<String[]> orchestratorCfgMono = toolConfigMono
                                    .doOnNext(cfg2 -> log.debug("[Tool][Orchestrator] Using provider={}, model={}, endpoint={} for incremental parsing", cfg2[0], cfg2[1], cfg2[3]))
                                    .cache();

                                // 每轮的累积与消费指针
                                final StringBuilder accumulator = new StringBuilder();
                                final java.util.concurrent.atomic.AtomicInteger consumed = new java.util.concurrent.atomic.AtomicInteger(0);
                                final int minBatch = 800;     // 提高批量阈值，减少过早触发
                                final int overlap = 120;      // 边界重叠，降低句子截断影响
                                final java.util.concurrent.atomic.AtomicLong lastFlushMs = new java.util.concurrent.atomic.AtomicLong(System.currentTimeMillis());

                                emitEvent(session.getSessionId(), new SettingGenerationEvent.GenerationProgressEvent(
                                    "开始流式文本生成并增量解析… (第" + (r + 1) + "/" + iterations + ")", null, null, null
                                ));

                                // 统一构建文本流（公共/私有逻辑已下沉至装饰器）
                                // 已在上方定义 nonNullProvider 与 textStream，这里直接复用
                                // com.ainovel.server.service.ai.AIModelProvider nonNullProvider = java.util.Objects.requireNonNull(provider, "模型提供商为空，无法启动文本流");
                                log.info("[文本阶段] 启动流式文本生成: provider={} model={} ", nonNullProvider.getProviderName(), nonNullProvider.getModelName());
                                // reactor.core.publisher.Flux<String> textStream = nonNullProvider.generateContentStream(req);

                                return textStream
                                    // 仅对中断类错误进行有限次退避重试，避免与底层Provider的重试叠加
                                    .retryWhen(reactor.util.retry.Retry
                                        .backoff(2, java.time.Duration.ofSeconds(1))
                                        .jitter(0.3)
                                        .filter(SettingGenerationService.this::isInterrupted))
                                    .filter(chunk -> chunk != null && !chunk.isBlank() && !"heartbeat".equalsIgnoreCase(chunk))
                                    .bufferTimeout(32, java.time.Duration.ofSeconds(4))
                                    .flatMap(parts -> {
                                        String part = String.join("", parts);
                                        if (part.isBlank()) return Mono.empty();
                                        accumulator.append(part);
                                        int total = accumulator.length();
                                        int start = consumed.get();
                                        int deltaLen = total - start;
                                        if (deltaLen < minBatch) {
                                            long now = System.currentTimeMillis();
                                            if (now - lastFlushMs.get() < 10000L) {
                                                return Mono.empty();
                                            }
                                        }
                                        String delta = accumulator.substring(start, total);
                                        // 若已在之前的工具结果中声明完成，则不再发起新的增量编排
                                        Object finalizedFlag = session.getMetadata().get("streamFinalized");
                                        if (Boolean.TRUE.equals(finalizedFlag)) {
                                            return Mono.<Void>empty();
                                        }
                                        // 异步触发工具解析，不阻塞文本流与回合结束
                                        // 优化：添加并发限制和去重，避免同时发起过多工具调用
                                        String orchestrationKey = session.getSessionId() + ":" + total;
                                        
                                        // 防重复调用检查
                                        if (activeToolCalls.putIfAbsent(orchestrationKey, true) != null) {
                                            log.debug("跳过重复的工具调用: 批次标识={}", orchestrationKey);
                                            return Mono.<Void>empty();
                                        }
                                        
                                        orchestratorCfgMono
                                            .flatMap(cfg2 -> {
                                                log.debug("触发增量工具解析: sessionId={} 文本长度={} 批次标识={}", 
                                                    session.getSessionId(), delta.length(), orchestrationKey);
                                                return orchestrateIncrementalTextToSettings(session, strategyAdapter, cfg2[0], cfg2[1], cfg2[2], cfg2[3], delta, isFinalRound);
                                            })
                                            .timeout(java.time.Duration.ofMinutes(3))
                                            .onErrorResume(err -> {
                                                emitErrorEvent(session.getSessionId(), "TOOL_STAGE_INC_ERROR", err.getMessage(), null, true);
                                                return Mono.<Void>empty();
                                            })
                                            .doFinally(signalType -> {
                                                // 完成后清理防重复调用标记
                                                activeToolCalls.remove(orchestrationKey);
                                                log.debug("清理工具调用标记: 批次标识={}", orchestrationKey);
                                            })
                                            .subscribe();

                                        // 单调更新消费指针与时间戳
                                        int newConsumed = Math.max(0, accumulator.length() - overlap);
                                        consumed.updateAndGet(prevVal -> Math.max(prevVal, newConsumed));
                                        lastFlushMs.set(System.currentTimeMillis());
                                        return Mono.empty();
                                    }, 1)
                                    // 将流错误改为可恢复/兜底，不向前端发送致命错误
                                    .onErrorResume(err -> {
                                        if (isInterrupted(err)) {
                                            log.warn("文本流被中断 (回合 {}), 继续下一轮。session={}", r + 1, session.getSessionId());
                                            try {
                                                // 仅在最后一轮时记录文本阶段结束
                                                if (isFinalRound) {
                                                    session.getMetadata().put("textStreamEnded", Boolean.TRUE);
                                                    sessionManager.saveSession(session).subscribe();
                                                }
                                            } catch (Exception ignore) {}
                                            try {
                                                if (!Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                                                    int start2 = consumed.get();
                                                    int total2 = accumulator.length();
                                                    if (total2 > start2) {
                                                        String tail = accumulator.substring(start2, total2);
                                                        orchestratorCfgMono
                                                            .flatMap(cfg2 -> orchestrateIncrementalTextToSettings(session, strategyAdapter, cfg2[0], cfg2[1], cfg2[2], cfg2[3], tail, isFinalRound)
                                                                .timeout(java.time.Duration.ofMinutes(2))
                                                                .onErrorResume(e2 -> Mono.empty())
                                                            )
                                                            .subscribe();
                                                    }
                                                }
                                            } catch (Exception ignore2) {}
                                            // 不中断后续链路
                                            return Mono.<Void>empty();
                                        }
                                        // 非中断错误：可恢复，尝试对已积累文本进行兜底解析；仅在最后一轮时考虑结束
                                        emitErrorEvent(session.getSessionId(), "TEXT_STREAM_ERROR", err.getMessage(), null, true);
                                        try {
                                            if (isFinalRound) {
                                                session.getMetadata().put("textStreamEnded", Boolean.TRUE);
                                                session.getMetadata().put("textEndedAt", System.currentTimeMillis());
                                                sessionManager.saveSession(session).subscribe();
                                            }
                                        } catch (Exception ignore) {}
                                        try {
                                            String snapshot = accumulator.toString();
                                            if (snapshot != null && !snapshot.isBlank() && !Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                                                attemptTextToSettingsJsonFallback(session, snapshot, strategyAdapter)
                                                    .doFinally(sig2 -> {
                                                        try {
                                                            if (isFinalRound && !Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                                                                attemptFinalizeWithInFlightGate(session, "Hybrid streaming error (with fallback)");
                                                            }
                                                        } catch (Exception ignore2) {}
                                                    })
                                                    .subscribe();
                                            } else {
                                                if (isFinalRound && !Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                                                    attemptFinalizeWithInFlightGate(session, "Hybrid streaming error (no content)");
                                                }
                                            }
                                        } catch (Exception ignore3) {}
                                        return Mono.empty();
                                    })
                                    .doOnComplete(() -> {
                                        try {
                                            // 保存本轮输出以作为后续上下文
                                            String roundOut = accumulator.toString();
                                            if (roundOut != null && !roundOut.isBlank()) {
                                                String prevOut = accumulatedText.get();
                                                String merged = (prevOut == null || prevOut.isBlank()) ? roundOut : (prevOut + "\n" + roundOut);
                                                accumulatedText.set(merged);
                                                try { session.getMetadata().put("accumulatedText", merged); } catch (Exception ignore) {}
                                            }

                                            if (isFinalRound) {
                                                // 仅在最后一轮记录文本阶段结束，尾段交给工具解析（不触发 finalize）
                                                session.getMetadata().put("textStreamEnded", Boolean.TRUE);
                                                session.getMetadata().put("textEndedAt", System.currentTimeMillis());
                                                sessionManager.saveSession(session).subscribe();
                                            }

                                            if (!Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                                                int start2 = consumed.get();
                                                int total2 = accumulator.length();
                                                if (total2 > start2) {
                                                    String tail = accumulator.substring(start2, total2);
                                                    orchestratorCfgMono
                                                        .flatMap(cfg2 -> orchestrateIncrementalTextToSettings(session, strategyAdapter, cfg2[0], cfg2[1], cfg2[2], cfg2[3], tail, isFinalRound)
                                                            .timeout(java.time.Duration.ofMinutes(2))
                                                            .onErrorResume(err -> {
                                                                emitErrorEvent(session.getSessionId(), "TOOL_STAGE_INC_ERROR", err.getMessage(), null, true);
                                                                return Mono.empty();
                                                            })
                                                        )
                                                        .subscribe();
                                                } else {
                                                    // 再次兜底：尝试对全量文本进行解析（不结束会话）；
                                                    // 是否能解析由解析器自行判断（canParse），并由验证服务去重/过滤。
                                                    attemptTextToSettingsJsonFallback(session, accumulator.toString(), strategyAdapter).subscribe();
                                                }
                                            }
                                        } catch (Exception e) {
                                            emitErrorEvent(session.getSessionId(), "STREAM_FINALIZE_ERROR", e.getMessage(), null, false);
                                        }
                                    })
                                    .then(Mono.just(1));
                            }
                        };

                        // 顺序执行多轮文本阶段
                        Mono<Integer> chain = Mono.just(0);
                        for (int i = 0; i < iterations; i++) {
                            final int idx = i;
                            chain = chain.then(Mono.defer(() -> runRound.apply(idx)));
                        }
                        return chain;
                    });
            });
    }

    /**
     * 单次增量文本 → text_to_settings 工具编排与处理（不标记整体完成）。
     */
    private Mono<Void> orchestrateIncrementalTextToSettings(SettingGenerationSession session,
                                                            ConfigurableStrategyAdapter strategyAdapter,
                                                            String provider,
                                                            String modelName,
                                                            String apiKey,
                                                            String apiEndpoint,
                                                            String textDelta,
                                                            boolean isFinalRoundSource) {
        // 记录在途任务开始
        String taskId = "tool-inc-" + java.util.UUID.randomUUID();
        java.util.concurrent.ConcurrentHashMap<String, Long> taskMap = inFlightTasks.computeIfAbsent(session.getSessionId(), k -> new java.util.concurrent.ConcurrentHashMap<String, Long>());
        taskMap.put(taskId, System.currentTimeMillis());
        log.debug("[InFlight] start task: sessionId={} taskId={} totalInFlight={}", session.getSessionId(), taskId, taskMap.size());
        String systemPrompt = "你是设定结构化助手。\n"
                + "- 仅在有可解析的新节点，或需要结束时，才调用工具；不要输出任何自然语言。\n"
                + "- 仅调用 text_to_settings 一个工具，不允许调用其他工具。\n"
                + "- 严禁改写/杜撰/删除原文内容，只能结构化组织并标注来源区间。\n"
                + "- nodes 的每项字段：name,type,description,parentId,tempId,attributes(可选)。\n"
                + "- 根节点 parentId=null；子节点 parentId=父节点的 tempId（不要使用真实UUID）。\n"
                + "- 可能成为父节点的条目必须提供唯一 tempId（如 R1、R1-1），供子节点引用。\n"
                + "- name 中禁止包含 '/' 字符，如需斜杠请使用全角 '／'。\n"
                + "- 不要为新建节点生成 id；仅在更新已存在节点时填写 id。引用父节点时，parentId 只能使用 tempId。\n"
                + "- 将提供已存在节点的 临时ID 列表（tempId|name|type）；若匹配到同名同类型节点，请避免重复创建；挂接父子关系时必须使用这些 tempId 作为 parentId。\n"
                + "- 若本批没有可解析的新节点且文本阶段未结束，请不要调用工具；当确认文本阶段结束时，调用并传 {complete:true}，nodes 可为空。";

        String existingTemps;
        try {
            @SuppressWarnings("unchecked")
            java.util.Map<String, String> tempIdMap = (java.util.Map<String, String>) session.getMetadata().get("tempIdMap");
            if (tempIdMap == null || tempIdMap.isEmpty()) {
                existingTemps = "(无)";
            } else {
                java.util.List<java.util.Map.Entry<String,String>> entries = new java.util.ArrayList<>(tempIdMap.entrySet());
                entries.sort(java.util.Map.Entry.comparingByKey());
                StringBuilder idx = new StringBuilder();
                int maxLines = 200;
                int written = 0;
                for (java.util.Map.Entry<String,String> e : entries) {
                    String tid = e.getKey();
                    String rid = e.getValue();
                    if (tid == null || tid.isBlank() || rid == null || rid.isBlank()) continue;
                    SettingNode n = session.getGeneratedNodes().get(rid);
                    if (n == null) continue;
                    String name = sanitizeNodeName(n.getName());
                    String type = n.getType() != null ? n.getType().toString() : "";
                    idx.append(tid).append(" | ").append(name != null ? name : "").append(" | ").append(type).append("\n");
                    written++;
                    if (written >= maxLines) break;
                    if (idx.length() >= 8000) break;
                }
                existingTemps = idx.length() > 0 ? idx.toString() : "(无)";
            }
        } catch (Exception e) {
            existingTemps = "(无)";
        }
        String userPrompt =
                "【文本格式说明】\n" +
                "每个节点以三行描述，并在节点之间留一个空行：\n" +
                "1) 当前节点<tempId> 标题：<名称>\n" +
                "2) 父节点是：<parentTempId 或 null> [父节点标题：<父名称>]\n" +
                "3) 内容：<描述>\n" +
                "【新增设定文本片段】\n" + textDelta + "\n\n" +
                "已存在节点（临时ID）列表（避免重复创建；挂接父子关系时必须使用下列 tempId 作为 parentId）：\n" + existingTemps + "\n" +
                "执行要求：\n" +
                "1) 只能调用 text_to_settings；\n" +
                "2) 若挂接到已有父节点，请使用该父节点的真实UUID作为 parentId；否则为新父节点提供 tempId 并在同批内引用；\n" +
                "3) 同父同名同类型去重；\n" +
                "4) 若文本较少，可先提取主干，再细化子项；\n" +
                "5) 即使无法解析，也必须调用 text_to_settings，传入 settings: []。";

        java.util.Map<String, String> cfg = new java.util.HashMap<>(java.util.Collections.unmodifiableMap(new java.util.HashMap<String, String>() {{
            put("correlationId", session.getSessionId());
            put("userId", session.getUserId() != null ? session.getUserId() : "system");
            put("sessionId", session.getSessionId());
            put("requestType", "SETTING_TOOL_STAGE_INC");
            put("provider", provider);
        }}));

        com.ainovel.server.service.ai.orchestration.ToolStreamingOrchestrator.StartOptions options = new com.ainovel.server.service.ai.orchestration.ToolStreamingOrchestrator.StartOptions(
            "orchestrate-" + session.getSessionId() + "-inc-" + java.util.UUID.randomUUID(),
            provider,
            modelName,
            apiKey,
            apiEndpoint,
            cfg,
            java.util.Arrays.asList(
                new com.ainovel.server.service.setting.generation.tools.TextToSettingsDataTool()
            ),
            systemPrompt,
            userPrompt,
            12,
            true
        );

        return toolStreamingOrchestrator.startStreaming(options)
            .timeout(java.time.Duration.ofMinutes(3))
            .doOnNext(evt -> {
                String eventType = evt.getEventType();
                if ("CALL_RECEIVED".equals(eventType)) {
                    emitEvent(session.getSessionId(), new SettingGenerationEvent.GenerationProgressEvent(
                        "Tool call: " + evt.getToolName(), null, null, null
                    ));
                } else if ("CALL_RESULT".equals(eventType)) {
                    try {
                        if (evt.getResultJson() != null && "text_to_settings".equalsIgnoreCase(evt.getToolName())) {
                            @SuppressWarnings("unchecked")
                            java.util.Map<String, Object> result = objectMapper.readValue(evt.getResultJson(), java.util.Map.class);

                            // 读取 nodes 或兼容 settings
                            Object nodesObj = result.get("nodes");
                            java.util.List<java.util.Map<String, Object>> nodes = null;
                            if (nodesObj instanceof java.util.List) {
                                java.util.List<?> raw = (java.util.List<?>) nodesObj;
                                if (!raw.isEmpty()) {
                                    nodes = new java.util.ArrayList<java.util.Map<String, Object>>();
                                    for (Object item : raw) {
                                        if (item instanceof java.util.Map) {
                                            java.util.Map<?, ?> m = (java.util.Map<?, ?>) item;
                                            java.util.Map<String, Object> node = new java.util.HashMap<String, Object>();
                                            Object name = m.get("name");
                                            Object type = m.get("type");
                                            Object description = m.get("description");
                                            Object parentId = m.get("parentId");
                                            Object tempId = m.get("tempId");
                                            Object attributes = m.get("attributes");
                                            Object id = m.get("id");
                                            if (name != null && type != null && description != null) {
                                                if (id != null) node.put("id", id.toString());
                                                node.put("name", name.toString());
                                                node.put("type", type.toString());
                                                node.put("description", description.toString());
                                                node.put("parentId", parentId != null ? parentId.toString() : null);
                                                if (tempId != null) node.put("tempId", tempId.toString());
                                                if (attributes instanceof java.util.Map) node.put("attributes", attributes);
                                                nodes.add(node);
                                            }
                                        }
                                    }
                                }
                            }
                            if (nodes == null || nodes.isEmpty()) {
                                Object settingsObj = result.get("settings");
                                if (settingsObj instanceof java.util.List) {
                                    java.util.List<?> list2 = (java.util.List<?>) settingsObj;
                                    if (!list2.isEmpty()) {
                                        nodes = new java.util.ArrayList<java.util.Map<String, Object>>();
                                        for (Object item : list2) {
                                            if (item instanceof java.util.Map) {
                                                java.util.Map<?, ?> m = (java.util.Map<?, ?>) item;
                                                java.util.Map<String, Object> node = new java.util.HashMap<String, Object>();
                                                Object name = m.get("name");
                                                Object type = m.get("type");
                                                Object description = m.get("description");
                                                Object parentId = m.get("parentId");
                                                Object tempId = m.get("tempId");
                                                Object attributes = m.get("attributes");
                                                if (name != null && type != null && description != null) {
                                                    node.put("name", name.toString());
                                                    node.put("type", type.toString());
                                                    node.put("description", description.toString());
                                                    node.put("parentId", parentId != null ? parentId.toString() : null);
                                                    if (tempId != null) node.put("tempId", tempId.toString());
                                                    if (attributes instanceof java.util.Map) node.put("attributes", attributes);
                                                    nodes.add(node);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if (nodes != null && !nodes.isEmpty()) {
                                int created = applyNodesDirect(session, nodes, strategyAdapter);
                                emitEvent(session.getSessionId(), new SettingGenerationEvent.GenerationProgressEvent(
                                    "已创建节点:" + created, null, null, null
                                ));
                                // 若工具结果声明 complete=true，则记录请求；仅当文本阶段已结束时才真正完成
                                Object completeFlag = result.get("complete");
                                if (Boolean.TRUE.equals(completeFlag)) {
                                    try {
                                        session.getMetadata().put("toolPendingComplete", Boolean.TRUE);
                                        sessionManager.saveSession(session).subscribe();
                                    } catch (Exception ignore) {}
                                    try {
                                        Object textEnded = session.getMetadata().get("textStreamEnded");
                                        if (isFinalRoundSource && Boolean.TRUE.equals(textEnded)) {
                                            String aggregated;
                                            try {
                                                Object acc = session.getMetadata().get("accumulatedText");
                                                aggregated = acc != null ? acc.toString() : null;
                                            } catch (Exception e) {
                                                aggregated = null;
                                            }
                                            attemptFinalizeWithInFlightGate(session, "Tool stage completed");
                                        }
                                    } catch (Exception ignore) {}
                                }
                            }
                        }
                    } catch (Exception parseEx) {
                        emitErrorEvent(session.getSessionId(), "PARSE_ERROR", parseEx.getMessage(), null, true);
                    }
                } else if ("CALL_ERROR".equals(eventType)) {
                    String msg = evt.getErrorMessage() != null ? evt.getErrorMessage() : "";
                    if (isTransientLLMRetryMessage(msg)) {
                        emitEvent(session.getSessionId(), new SettingGenerationEvent.GenerationProgressEvent(
                            "模型繁忙/限流，自动重试中… " + safeErrorMessage(msg, 200), null, null, null
                        ));
                    } else {
                        emitErrorEvent(session.getSessionId(), "TOOL_ERROR", msg, null, true);
                    }
                } else if ("COMPLETE".equals(eventType)) {
                    // 工具编排结束：若文本阶段已结束且尚未完成，统一在此结束
                    try {
                        if (isFinalRoundSource && !Boolean.TRUE.equals(session.getMetadata().get("streamFinalized"))) {
                            Object textEnded = session.getMetadata().get("textStreamEnded");
                            if (Boolean.TRUE.equals(textEnded)) {
                                // 若之前已收到工具层 complete 请求，也在此统一完成（受在途门控）
                                attemptFinalizeWithInFlightGate(session, "Hybrid streaming tool stage completed");
                            }
                        }
                    } catch (Exception ignore) {}
                }
            })
            .doOnError(err -> {
                if (isTransientLLMRetry(err)) {
                    emitEvent(session.getSessionId(), new SettingGenerationEvent.GenerationProgressEvent(
                        "模型繁忙/限流，自动重试中… " + safeErrorMessage(err, 200), null, null, null
                    ));
                }
            })
            .doFinally(sig -> {
                // 记录在途任务结束
                try {
                    java.util.concurrent.ConcurrentHashMap<String, Long> map = inFlightTasks.get(session.getSessionId());
                    if (map != null) {
                        map.remove(taskId);
                        log.debug("[InFlight] end task: sessionId={} taskId={} remainInFlight={}", session.getSessionId(), taskId, map.size());
                        // 文本已结束时尝试完成（仅最后一轮来源）
                        Object textEnded = session.getMetadata().get("textStreamEnded");
                        if (isFinalRoundSource && Boolean.TRUE.equals(textEnded)) {
                            attemptFinalizeWithInFlightGate(session, "Task ended");
                        }
                    }
                } catch (Exception ignore) {}
            })
            .then();
    }

    private boolean isTransientLLMRetry(Throwable err) {
        if (err == null) return false;
        String cls = err.getClass().getName().toLowerCase();
        String msg = err.getMessage() != null ? err.getMessage().toLowerCase() : "";
        return msg.contains("429")
            || msg.contains("quota")
            || msg.contains("rate limit")
            || msg.contains("retry")
            || msg.contains("sending the request was interrupted")
            || cls.contains("ioexception")
            || cls.contains("reactor.core.Exceptions.retry")
            || msg.contains("resource_exhausted");
    }

    private boolean isTransientLLMRetryMessage(String msg) {
        if (msg == null) return false;
        String m = msg.toLowerCase();
        return m.contains("429")
            || m.contains("quota")
            || m.contains("rate limit")
            || m.contains("retry")
            || m.contains("resource_exhausted");
    }

    private String safeErrorMessage(Throwable err, int maxLen) {
        return safeErrorMessage(err != null ? err.getMessage() : null, maxLen);
    }
    private String safeErrorMessage(String msg, int maxLen) {
        if (msg == null) return "";
        String s = msg.replaceAll("\n|\r", " ").trim();
        if (s.length() <= maxLen) return s;
        return s.substring(0, Math.max(0, maxLen - 1)) + "…";
    }

    /**
     * 直接在服务端将解析出来的 nodes 落地到会话：
     * - 处理 tempId → 真实ID 的映射（批内 + 跨批）
     * - 父子关系解析（优先批内，再回退跨批）
     * - 校验（策略 + 基础）
     * - addNodeToSession 后立刻 emit NodeCreatedEvent
     * 返回成功创建的节点数量
     */
    private int applyNodesDirect(SettingGenerationSession session,
                                 java.util.List<java.util.Map<String, Object>> nodes,
                                 ConfigurableStrategyAdapter strategyAdapter) {
        if (nodes == null || nodes.isEmpty()) return 0;

        @SuppressWarnings("unchecked")
        java.util.Map<String, String> crossBatchTempIdMapInit = (java.util.Map<String, String>) session.getMetadata().get("tempIdMap");
        if (crossBatchTempIdMapInit == null) {
            crossBatchTempIdMapInit = new java.util.concurrent.ConcurrentHashMap<String, String>();
            session.getMetadata().put("tempIdMap", crossBatchTempIdMapInit);
        }
        final java.util.Map<String, String> crossBatchTempIdMap = crossBatchTempIdMapInit;

        java.util.Map<String, String> inBatchTempIdToRealId = new java.util.HashMap<String, String>();
        final java.util.concurrent.atomic.AtomicInteger createdCount = new java.util.concurrent.atomic.AtomicInteger(0);

        for (java.util.Map<String, Object> m : nodes) {
            try {
                Object idObj = m.get("id");
                Object nameObj = m.get("name");
                Object typeObj = m.get("type");
                Object descObj = m.get("description");
                Object parentObj = m.get("parentId");
                Object tempIdObj = m.get("tempId");
                @SuppressWarnings("unchecked")
                java.util.Map<String, Object> attrs = m.get("attributes") instanceof java.util.Map ? (java.util.Map<String, Object>) m.get("attributes") : new java.util.HashMap<String, Object>();

                String name = nameObj != null ? nameObj.toString() : null;
                String typeStr = typeObj != null ? typeObj.toString() : null;
                String description = descObj != null ? descObj.toString() : null;
                String parentId = parentObj != null ? parentObj.toString() : null;
                String tempId = tempIdObj != null ? tempIdObj.toString() : null;

                // 解析父ID：批内优先，其次跨批
                if (parentId != null) {
                    if (inBatchTempIdToRealId.containsKey(parentId)) {
                        parentId = inBatchTempIdToRealId.get(parentId);
                    } else if (crossBatchTempIdMap.containsKey(parentId)) {
                        parentId = crossBatchTempIdMap.get(parentId);
                    }
                }

                // 生成或使用提供的ID
                String nodeId = (idObj != null && !idObj.toString().isBlank())
                        ? idObj.toString()
                        : java.util.UUID.randomUUID().toString();

                // 统一清理名称中的分隔符，避免前端按'/'分割路径导致父节点匹配失败
                String sanitizedName = sanitizeNodeName(name);

                SettingNode node = SettingNode.builder()
                    .id(nodeId)
                    .parentId(parentId)
                    .name(sanitizedName)
                    .type(com.ainovel.server.domain.model.SettingType.fromValue(typeStr))
                    .description(description)
                    .attributes(attrs)
                    .generationStatus(SettingNode.GenerationStatus.COMPLETED)
                    .build();

                // 策略校验
                SettingGenerationStrategy.ValidationResult sv = strategyAdapter.validateNode(node, strategyAdapter.getCustomConfig(), session);
                if (!sv.valid()) {
                    emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", sv.errorMessage(), node.getId(), true);
                    continue;
                }
                // 基础校验
                SettingValidationService.ValidationResult v = validationService.validateNode(node, session);
                if (!v.isValid()) {
                    emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", java.lang.String.join(", ", v.errors()), node.getId(), true);
                    continue;
                }

                sessionManager.addNodeToSession(session.getSessionId(), node)
                    .subscribe(s -> emitNodeCreatedEvent(session.getSessionId(), node, session));
                createdCount.incrementAndGet();

                if (tempId != null && !tempId.isBlank()) {
                    inBatchTempIdToRealId.put(tempId, nodeId);
                    crossBatchTempIdMap.put(tempId, nodeId);
                }
            } catch (Exception e) {
                emitErrorEvent(session.getSessionId(), "CREATE_NODE_ERROR", e.getMessage(), null, true);
            }
        }

        return createdCount.get();
    }

    /**
     * Reactive 版本：确保在下游订阅完成后，节点已添加且事件已发出。
     */
    @SuppressWarnings("unused")
    private Mono<Integer> applyNodesDirectReactive(SettingGenerationSession session,
                                                   java.util.List<java.util.Map<String, Object>> nodes,
                                                   ConfigurableStrategyAdapter strategyAdapter) {
        if (nodes == null || nodes.isEmpty()) return Mono.just(0);

        @SuppressWarnings("unchecked")
        java.util.Map<String, String> crossBatchTempIdMapInit = (java.util.Map<String, String>) session.getMetadata().get("tempIdMap");
        if (crossBatchTempIdMapInit == null) {
            crossBatchTempIdMapInit = new java.util.concurrent.ConcurrentHashMap<String, String>();
            session.getMetadata().put("tempIdMap", crossBatchTempIdMapInit);
        }
        final java.util.Map<String, String> crossBatchTempIdMap = crossBatchTempIdMapInit;

        java.util.Map<String, String> inBatchTempIdToRealId = new java.util.HashMap<String, String>();
        final java.util.concurrent.atomic.AtomicInteger createdCount = new java.util.concurrent.atomic.AtomicInteger(0);

        return reactor.core.publisher.Flux.fromIterable(nodes)
            .concatMap(m -> {
                try {
                    Object idObj = m.get("id");
                    Object nameObj = m.get("name");
                    Object typeObj = m.get("type");
                    Object descObj = m.get("description");
                    Object parentObj = m.get("parentId");
                    Object tempIdObj = m.get("tempId");
                    @SuppressWarnings("unchecked")
                    java.util.Map<String, Object> attrs = m.get("attributes") instanceof java.util.Map ? (java.util.Map<String, Object>) m.get("attributes") : new java.util.HashMap<String, Object>();

                    String name = nameObj != null ? nameObj.toString() : null;
                    String typeStr = typeObj != null ? typeObj.toString() : null;
                    String description = descObj != null ? descObj.toString() : null;
                    String parentIdRaw = parentObj != null ? parentObj.toString() : null;
                    String tempId = tempIdObj != null ? tempIdObj.toString() : null;

                    String parentId = parentIdRaw;
                    if (parentId != null) {
                        if (inBatchTempIdToRealId.containsKey(parentId)) {
                            parentId = inBatchTempIdToRealId.get(parentId);
                        } else if (                     crossBatchTempIdMap.containsKey(parentId)) {
                            parentId = crossBatchTempIdMap.get(parentId);
                        }
                    }

                    String nodeId = (idObj != null && !idObj.toString().isBlank())
                            ? idObj.toString()
                            : java.util.UUID.randomUUID().toString();

                    // 统一清理名称中的分隔符，避免前端按'/'分割路径导致父节点匹配失败
                    String sanitizedName = sanitizeNodeName(name);

                    SettingNode node = SettingNode.builder()
                        .id(nodeId)
                        .parentId(parentId)
                        .name(sanitizedName)
                        .type(com.ainovel.server.domain.model.SettingType.fromValue(typeStr))
                        .description(description)
                        .attributes(attrs)
                        .generationStatus(SettingNode.GenerationStatus.COMPLETED)
                        .build();

                    // 策略校验
                    SettingGenerationStrategy.ValidationResult sv = strategyAdapter.validateNode(node, strategyAdapter.getCustomConfig(), session);
                    if (!sv.valid()) {
                        emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", sv.errorMessage(), node.getId(), true);
                        return Mono.empty();
                    }
                    // 基础校验
                    SettingValidationService.ValidationResult v = validationService.validateNode(node, session);
                    if (!v.isValid()) {
                        emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", java.lang.String.join(", ", v.errors()), node.getId(), true);
                        return Mono.empty();
                    }

                    return sessionManager.addNodeToSession(session.getSessionId(), node)
                        .doOnNext(s -> emitNodeCreatedEvent(session.getSessionId(), node, session))
                        .doOnNext(s -> {
                            createdCount.incrementAndGet();
                            if (tempId != null && !tempId.isBlank()) {
                                inBatchTempIdToRealId.put(tempId, nodeId);
                                crossBatchTempIdMap.put(tempId, nodeId);
                            }
                        })
                        .then();
                } catch (Exception e) {
                    emitErrorEvent(session.getSessionId(), "CREATE_NODE_ERROR", e.getMessage(), null, true);
                    return Mono.empty();
                }
            })
            .then(Mono.fromCallable(createdCount::get));
    }

    @Override
    public Mono<Void> adjustSession(String sessionId, String adjustmentPrompt, String modelConfigId, String promptTemplateId) {
        log.info("Adjusting session: {} with template: {}", sessionId, promptTemplateId);

        // 1) 取会话，若不在内存则基于历史记录恢复
        return sessionManager.getSession(sessionId)
            .switchIfEmpty(Mono.defer(() -> {
                log.info("Session not found in memory for adjustSession. Creating from history: {}", sessionId);
                return createSessionFromHistory(sessionId);
            }))
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Session not found and could not be created from history: " + sessionId)))
            .flatMap(session -> {
                // 2) 更新模型配置ID（可覆盖）
                if (modelConfigId != null && !modelConfigId.isBlank()) {
                    session.getMetadata().put("modelConfigId", modelConfigId);
                }

                // 3) 取得模板并生成策略适配器
                return promptTemplateRepository.findById(promptTemplateId)
                    .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
                    .flatMap(template -> {
                        if (!template.isSettingGenerationTemplate()) {
                            return Mono.error(new IllegalArgumentException("Template is not for setting generation: " + promptTemplateId));
                        }

                        return strategyFactory.createConfigurableStrategy(template)
                            .map(Mono::just)
                            .orElse(Mono.error(new IllegalArgumentException("Cannot create strategy from template: " + promptTemplateId)))
                            .flatMap(strategyAdapter -> {
                                // 将策略适配器入会话元数据，后续提示与验证使用
                                session.getMetadata().put("strategyAdapter", strategyAdapter);

                                // 标记状态为生成中
                                return sessionManager.updateSessionStatus(session.getSessionId(), SettingGenerationSession.SessionStatus.GENERATING)
                                    .then(Mono.defer(() -> adjustSessionAsync(session, template, strategyAdapter, adjustmentPrompt)));
                            });
                    });
            });
    }

    private Mono<Void> adjustSessionAsync(SettingGenerationSession session,
                                          com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
                                          ConfigurableStrategyAdapter strategyAdapter,
                                          String adjustmentPrompt) {
        String contextId = "adjust-" + session.getSessionId();
        String modelConfigId = (String) session.getMetadata().get("modelConfigId");

        return novelAIService.getAIModelProviderByConfigId(session.getUserId(), modelConfigId)
            .flatMap(provider -> {
                String modelName = provider.getModelName();
                Map<String, String> aiConfig = new HashMap<>();
                aiConfig.put("apiKey", provider.getApiKey());
                aiConfig.put("apiEndpoint", provider.getApiEndpoint());
                aiConfig.put("provider", provider.getProviderName());
                aiConfig.put("requestType", AIFeatureType.SETTING_TREE_GENERATION.name());
                aiConfig.put("correlationId", session.getSessionId());
                // 透传身份信息，供AIRequest写入并被LLMTrace记录
                if (session.getUserId() != null && !session.getUserId().isBlank()) {
                    aiConfig.put("userId", session.getUserId());
                }
                if (session.getSessionId() != null && !session.getSessionId().isBlank()) {
                    aiConfig.put("sessionId", session.getSessionId());
                }

                // 创建工具上下文（整体调整依然走生成工具，补齐/改写结构）
                ToolExecutionService.ToolCallContext context = createToolContext(contextId);
                registerGenerationTools(context, session, strategyAdapter);
                List<ToolSpecification> toolSpecs = toolRegistry.getSpecificationsForContext(contextId);

                // 构建 Prompt 上下文
                Map<String, Object> promptContext = buildPromptContext(session, template, strategyAdapter);
                // 合并调整说明
                promptContext.put("adjustmentPrompt", adjustmentPrompt);
                // 新增：会话设定树（仅名称/路径/类型/简述，不包含任何UUID）
                String sessionTreeReadable = buildReadableSessionTree(session);
                promptContext.put("sessionTree", sessionTreeReadable);

                return promptProvider.getSystemPrompt(session.getUserId(), promptContext)
                    .zipWith(promptProvider.getUserPrompt(session.getUserId(), template.getId(), promptContext))
                    .flatMap(prompts -> {
                        String systemPrompt = prompts.getT1();
                        String userPrompt = prompts.getT2();

                        // 按你的要求：调整生成相当于重新生成，不添加额外规则，只追加上下文
                        String adjustedSystem = systemPrompt + "\n\n" +
                                "工具使用指引（重要，减少无效请求）：\n" +
                                "不能回复任何普通文本，仅发起工具调用。\n" +
                                "- 使用 create_setting_nodes 或 create_setting_node 完成最后一批创建时，请在参数中加入 complete=true。\n" +
                                "- 这样服务端将在工具执行后直接结束本轮生成循环，不会再发起额外一次模型调用，从而节省 token。\n" +
                                "- 非最后一批创建请不要带 complete。\n" +
                                "- 严禁调用 create_setting_nodes 时 nodes 为空（不得只发送 {\"complete\": true}）。\n" +
                                "- 若携带 complete=true，则本批必须包含\"足量\"节点：建议不少于 15 个，且≥60% 为子节点；\n" +
                                "  并优先为所有尚无子节点的父节点各补齐至少 2~3 个直接子节点。\n\n" +
                                "父子关系与 ID 规则（必须遵守）：\n" +
                                "- 根节点的 parentId 必须为 null。\n" +
                                "- 绝对禁止使用 '1'、'0'、'root' 等硬编码值作为 parentId。\n" +
                                "- 本批次内：为每个可能成为父节点的条目提供 tempId（如 R1、R2、R1-1）。随后子节点一律用该 tempId 作为 parentId；\n" +
                                "  服务端会把 tempId 映射为真实 UUID，无需你记忆真实ID。\n" +
                                "- 跨批次：可继续用先前批次定义的 tempId 作为 parentId；服务端维护全局 tempId→UUID 映射。\n" +
                                "- 仅当你明确知道真实 UUID 时才使用真实 UUID；否则一律使用 tempId。\n" +
                                "- 注意：单个创建（create_setting_node）不支持 tempId 映射；涉及父子引用时优先使用 create_setting_nodes。\n\n" +
                                "字段规范：\n" +
                                "- id：仅在\"更新已存在节点\"时提供；新建时不要提供。\n" +
                                "- name, type, description：必填。\n" +
                                "- parentId：根为 null；子节点使用父节点的 tempId 或真实 UUID。\n" +
                                "- tempId：可选字符串；用于被其他条目作为 parentId 引用。\n\n" +
                                "类型枚举（必须使用其一）：\n" +
                                "CHARACTER、LOCATION、ITEM、LORE、FACTION、EVENT、CONCEPT、CREATURE、MAGIC_SYSTEM、TECHNOLOGY、CULTURE、HISTORY、ORGANIZATION、WORLDVIEW、PLEASURE_POINT、ANTICIPATION_HOOK、THEME、TONE、STYLE、TROPE、PLOT_DEVICE、POWER_SYSTEM、GOLDEN_FINGER、TIMELINE、RELIGION、POLITICS、ECONOMY、GEOGRAPHY、OTHER\n\n" +
                                "类型选择建议：若想表达剧情，请优先用 EVENT 或 PLOT_DEVICE；不要使用 PLOT。\n\n" +
                                "常见错误（请避免）：\n" +
                                "- 把所有节点的 parentId 设置为 1（无效）。\n" +
                                "- 为根节点设置非 null 的 parentId。\n" +
                                "- 在同一批次引用尚未赋予 tempId 的父节点。";

                        String adjustedUser = userPrompt +
                                "\n\n[当前会话设定树]\n" + sessionTreeReadable +
                                "\n\n[调整说明]\n" + adjustmentPrompt;

                        List<ChatMessage> messages = new ArrayList<>();
                        messages.add(new SystemMessage(adjustedSystem));
                        messages.add(new UserMessage(adjustedUser));

                        aiConfig.put("toolContextId", contextId);
                        // 工具阶段：显式限制最大轮数，并增加整体超时，防止死循环
                        return aiService.executeToolCallLoop(
                                messages,
                                toolSpecs,
                                modelName,
                                aiConfig.get("apiKey"),
                                aiConfig.get("apiEndpoint"),
                                aiConfig,
                                30
                        ).timeout(java.time.Duration.ofMinutes(5))
                         .onErrorResume(timeout -> {
                             if (timeout instanceof java.util.concurrent.TimeoutException || (timeout.getMessage() != null && timeout.getMessage().contains("Timeout"))) {
                                 log.error("Tool loop timed out for session {}", session.getSessionId());
                                 emitErrorEvent(session.getSessionId(), "TOOL_STAGE_TIMEOUT", "工具编排阶段超时", null, false);
                             }
                             return Mono.error(timeout);
                         });
                    })
                    .flatMap(history -> {
                        // 完成后标记完成
                        markGenerationComplete(session.getSessionId(), "Adjustment completed");
                        return Mono.empty();
                    })
                    .onErrorResume(error -> {
                        log.error("Error in adjust tool loop for session: {}", session.getSessionId(), error);
                        emitErrorEvent(session.getSessionId(), "ADJUST_FAILED", "整体调整失败: " + error.getMessage(), null, true);
                        return sessionManager.updateSessionStatus(session.getSessionId(), SettingGenerationSession.SessionStatus.ERROR)
                                .then(Mono.error(error));
                    })
                    .doFinally(signal -> {
                        try { context.close(); } catch (Exception ignore) {}
                    })
                    .subscribeOn(Schedulers.boundedElastic())
                    .then();
            });
    }

    /**
     * 生成仅包含名称/路径/类型/简述的会话设定树文本文本，避免UUID泄漏到提示词中
     */
    private String buildReadableSessionTree(SettingGenerationSession session) {
        StringBuilder sb = new StringBuilder();
        // 根节点：parentId == null
        session.getGeneratedNodes().values().stream()
            .filter(n -> n.getParentId() == null)
            .forEach(root -> appendReadableNodeLine(session, root, sb, 0));
        return sb.toString();
    }

    private void appendReadableNodeLine(SettingGenerationSession session, SettingNode node, StringBuilder sb, int depth) {
        for (int i = 0; i < depth; i++) sb.append("  ");
        String path = buildParentPath(node.getId(), session);
        String oneLineDesc = safeOneLine(node.getDescription(), 140);
        sb.append("- ").append(path).append("/").append(node.getName())
          .append(" [").append(node.getType()).append("]");
        if (!oneLineDesc.isBlank()) {
            sb.append(": ").append(oneLineDesc);
        }
        sb.append("\n");
        // 遍历子节点
        List<String> childIds = session.getChildrenIds(node.getId());
        if (childIds != null) {
            for (String cid : childIds) {
                SettingNode child = session.getGeneratedNodes().get(cid);
                if (child != null) {
                    appendReadableNodeLine(session, child, sb, depth + 1);
                }
            }
        }
    }

    private String safeOneLine(String text, int maxLen) {
        if (text == null) return "";
        String t = text.replaceAll("\n|\r", " ").trim();
        if (t.length() <= maxLen) return t;
        return t.substring(0, Math.max(0, maxLen - 1)) + "…";
    }
    
    /**
     * 兼容保留：构建已有节点索引（id|name|type）。若调用处仍引用该方法，避免编译错误。
     */
    @SuppressWarnings("unused")
    private String buildExistingNodeIndex(SettingGenerationSession session) {
        if (session == null || session.getGeneratedNodes() == null || session.getGeneratedNodes().isEmpty()) {
            return "(无)";
        }
        StringBuilder sb = new StringBuilder();
        java.util.List<SettingNode> list = new java.util.ArrayList<>(session.getGeneratedNodes().values());
        list.sort((a, b) -> {
            boolean ra = a.getParentId() == null;
            boolean rb = b.getParentId() == null;
            if (ra != rb) return ra ? -1 : 1;
            String na = a.getName() != null ? a.getName() : "";
            String nb = b.getName() != null ? b.getName() : "";
            return na.compareTo(nb);
        });
        int maxLines = 200;
        int written = 0;
        for (SettingNode n : list) {
            if (n == null) continue;
            String id = n.getId();
            String name = sanitizeNodeName(n.getName());
            String type = n.getType() != null ? n.getType().toString() : "";
            if (id == null || id.isBlank()) continue;
            sb.append(id).append(" | ").append(name != null ? name : "").append(" | ").append(type).append("\n");
            written++;
            if (written >= maxLines) break;
            if (sb.length() >= 8000) break;
        }
        if (written < list.size()) {
            sb.append("…(其余 ").append(list.size() - written).append(" 条已省略)");
        }
        return sb.toString();
    }
    
    // 已存在节点索引方法改为内联调用，避免未使用警告
    
    @Override
    public Flux<SettingGenerationEvent> getGenerationEventStream(String sessionId) {
        Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
        if (sink == null) {
            // 为修改操作或其他情况创建新的事件流
            log.info("Creating new event stream for session: {}", sessionId);
            sink = Sinks.many().replay().all();
            eventSinks.put(sessionId, sink);
        }
        
        // 核心事件流：来自会话sink
        reactor.core.publisher.Flux<SettingGenerationEvent> core = sink.asFlux()
            // 订阅即推送一条就绪事件（补全必要字段）
            .startWith(buildProgressEvent(sessionId, "STREAM_READY"));

        // 心跳：在核心流完成时一并结束，避免上游看到 cancel
        reactor.core.publisher.Flux<SettingGenerationEvent> heartbeat = reactor.core.publisher.Flux
            .interval(java.time.Duration.ofSeconds(15))
            .map(i -> (SettingGenerationEvent) buildProgressEvent(sessionId, "HEARTBEAT"))
            .takeUntilOther(core.ignoreElements().then(reactor.core.publisher.Mono.just(Boolean.TRUE)));

        return reactor.core.publisher.Flux.merge(core, heartbeat)
            .doFinally(signal -> {
                log.info("Event stream closed for session: {}, signal={}", sessionId, signal);
                cleanupSession(sessionId);
            });
    }

    private SettingGenerationEvent.GenerationProgressEvent buildProgressEvent(String sessionId, String message) {
        SettingGenerationEvent.GenerationProgressEvent evt =
            new SettingGenerationEvent.GenerationProgressEvent(message, null, null, null);
        try {
            evt.setSessionId(sessionId);
            evt.setTimestamp(LocalDateTime.now());
        } catch (Exception ignore) {}
        return evt;
    }

    /**
 * 获取修改操作事件流（不销毁session）
 * 专门用于节点修改、添加等需要保持session连续性的操作
 */
@Override
public Flux<SettingGenerationEvent> getModificationEventStream(String sessionId) {
    Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
    if (sink == null) {
        // 为修改操作创建新的事件流
        log.info("Creating new modification event stream for session: {}", sessionId);
        sink = Sinks.many().replay().all();
        eventSinks.put(sessionId, sink);
    }
    
    return sink.asFlux()
        .doOnCancel(() -> {
            log.info("Modification event stream cancelled for session: {}", sessionId);
            // 只清理事件流，不删除session
            eventSinks.remove(sessionId);
        })
        .doOnTerminate(() -> {
            log.info("Modification event stream terminated for session: {}", sessionId);
            // 只清理事件流，不删除session，保持session用于后续操作
            eventSinks.remove(sessionId);
        });
}
    
    @Override
    public Mono<Void> modifyNode(String sessionId, String nodeId, String modificationPrompt,
                                String modelConfigId, String scope, Boolean isPublicModel, String publicModelConfigId) {

    // 获取或创建会话锁
    Object lock = sessionLocks.computeIfAbsent(sessionId, k -> new Object());
    
    return Mono.defer(() -> {
        synchronized (lock) {
            log.info("Starting node modification for session: {}", sessionId);
            
            // 确保事件流提前创建，以便在任何阶段都能发送错误事件
            if (!eventSinks.containsKey(sessionId)) {
                log.info("Creating new event stream for modification on session: {}", sessionId);
                Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                eventSinks.put(sessionId, sink);
            }
            
            // 步骤 1: 优先从内存中获取会话
            return sessionManager.getSession(sessionId)
                // 步骤 2: 如果内存中没有，则从历史记录创建
                .switchIfEmpty(Mono.defer(() -> {
                    log.info("Session not found in memory for modifyNode. Creating from history: {}", sessionId);
                    return createSessionFromHistory(sessionId);
                }))
                // 步骤 2.5: 如果历史记录也不存在，发送错误事件并抛出异常
                .onErrorResume(error -> {
                    log.error("Failed to get or create session for modification: {}", sessionId, error);
                    // 发送错误事件到事件流
                    SettingGenerationEvent.GenerationErrorEvent errorEvent = 
                        new SettingGenerationEvent.GenerationErrorEvent();
                    errorEvent.setSessionId(sessionId);
                    errorEvent.setNodeId(nodeId);
                    errorEvent.setErrorCode("SESSION_NOT_FOUND");
                    errorEvent.setErrorMessage("会话已过期或不存在，无法进行AI修改。请刷新页面重新生成设定。");
                    errorEvent.setRecoverable(false);
                    errorEvent.setTimestamp(LocalDateTime.now());
                    emitEvent(sessionId, errorEvent);
                    
                    // 完成事件流
                    Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
                    if (sink != null) {
                        sink.tryEmitComplete();
                    }
                    
                    return Mono.error(new IllegalArgumentException("会话已过期或不存在: " + sessionId + " - 原因: " + error.getMessage()));
                })
                .switchIfEmpty(Mono.error(new IllegalArgumentException("Session not found and could not be created from history: " + sessionId)))
                .flatMap(session -> {
                    // 步骤 3: 查找要修改的节点
                    SettingNode nodeToModify = session.getGeneratedNodes().get(nodeId);
                    if (nodeToModify == null) {
                        log.error("Node not found in session '{}'. Available nodes: {}", sessionId, session.getGeneratedNodes().keySet());
                        
                        // 发送错误事件
                        SettingGenerationEvent.GenerationErrorEvent errorEvent = 
                            new SettingGenerationEvent.GenerationErrorEvent();
                        errorEvent.setSessionId(sessionId);
                        errorEvent.setNodeId(nodeId);
                        errorEvent.setErrorCode("NODE_NOT_FOUND");
                        errorEvent.setErrorMessage("节点不存在: " + nodeId);
                        errorEvent.setRecoverable(false);
                        errorEvent.setTimestamp(LocalDateTime.now());
                        emitEvent(sessionId, errorEvent);
                        
                        // 完成事件流
                        Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
                        if (sink != null) {
                            sink.tryEmitComplete();
                        }
                        
                        return Mono.error(new IllegalArgumentException("Node not found: " + nodeId));
                    }

                    // 步骤 4: 记录scope到元数据，供下游提示词与校验使用
                    if (scope != null && !scope.isBlank()) {
                        session.getMetadata().put("modificationScope", scope);
                    } else {
                        session.getMetadata().put("modificationScope", "self");
                    }

                    // 步骤 5: 统一走常规修改逻辑（公共模型逻辑下沉至装饰器）
                    return modifyNodeAsync(session, nodeToModify, modificationPrompt, modelConfigId);
                });
        }
    }).doFinally(signalType -> {
        log.info("Finished modifyNode process for session: {} with signal: {}", sessionId, signalType);
        // 注意：这里不再清理session，只是记录日志
    });
}
    
    @Override
    public Mono<Void> updateNodeContent(String sessionId, String nodeId, String newContent) {
        log.info("Updating content for node {} in session {}", nodeId, sessionId);
        
        return sessionManager.getSession(sessionId)
            .flatMap(session -> {
                // 会话存在，在会话中查找并更新节点
                SettingNode node = session.getGeneratedNodes().get(nodeId);
                
                if (node == null) {
                    return Mono.error(new IllegalArgumentException("Node not found in session: " + nodeId));
                }
                
                // 保存旧内容作为previousVersion（可选）
                SettingNode previousVersion = SettingNode.builder()
                    .id(node.getId())
                    .parentId(node.getParentId())
                    .name(node.getName())
                    .type(node.getType())
                    .description(node.getDescription())
                    .attributes(new HashMap<>(node.getAttributes()))
                    .strategyMetadata(new HashMap<>(node.getStrategyMetadata()))
                    .generationStatus(node.getGenerationStatus())
                    .errorMessage(node.getErrorMessage())
                    .generationPrompt(node.getGenerationPrompt())
                    .build();
                
                // 更新节点内容
                node.setDescription(newContent);
                node.setGenerationStatus(SettingNode.GenerationStatus.MODIFIED);
                
                // 保存更新后的会话
                return sessionManager.saveSession(session)
                    .then(Mono.fromRunnable(() -> {
                        // 发送更新事件
                        SettingGenerationEvent.NodeUpdatedEvent updateEvent = 
                            new SettingGenerationEvent.NodeUpdatedEvent(node, previousVersion);
                        emitEvent(sessionId, updateEvent);
                        
                        log.info("Node content updated successfully in session: {}", nodeId);
                    }))
                    // 关键：发出一个非空信号，避免触发 switchIfEmpty 回退
                    .thenReturn(Boolean.TRUE);
            })
            .switchIfEmpty(Mono.defer(() -> {
                // 会话不存在，尝试直接更新数据库中的设定条目
                return updateSettingItemDirectly(nodeId, newContent)
                    .doOnSuccess(v -> log.info("Node content updated directly in database: {}", nodeId))
                    .doOnError(e -> log.warn("Failed to update node {} directly in database: {}", nodeId, e.getMessage()))
                    .thenReturn(Boolean.FALSE);
            }))
            .then();
    }
    
    /**
     * 直接更新数据库中的设定条目
     * 当会话不存在时的回退方案
     */
    private Mono<Void> updateSettingItemDirectly(String nodeId, String newContent) {
        log.info("Attempting to update setting item directly in database: {}", nodeId);
        
        return novelSettingService.getSettingItemById(nodeId)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Setting item not found: " + nodeId)))
            .flatMap(settingItem -> {
                // 更新设定条目的描述内容
                settingItem.setDescription(newContent);
                settingItem.setUpdatedAt(LocalDateTime.now());
                
                // 在metadata中标记这是一个直接更新
                if (settingItem.getMetadata() == null) {
                    settingItem.setMetadata(new HashMap<>());
                }
                settingItem.getMetadata().put("lastDirectUpdate", LocalDateTime.now().toString());
                settingItem.getMetadata().put("updateSource", "direct_node_update");
                
                return novelSettingService.updateSettingItem(nodeId, settingItem);
            })
            .then();
    }
    
    @Override
    public Mono<List<String>> deleteNode(String sessionId, String nodeId) {
        log.info("Deleting node {} from session {}", nodeId, sessionId);
        
        return sessionManager.getSession(sessionId)
            .flatMap(session -> {
                // 查找要删除的节点
                SettingNode nodeToDelete = session.getGeneratedNodes().get(nodeId);
                
                if (nodeToDelete == null) {
                    return Mono.error(new IllegalArgumentException("Node not found in session: " + nodeId));
                }
                
                // 收集所有要删除的节点ID（包括子节点）
                List<String> deletedNodeIds = new ArrayList<>();
                collectNodeAndDescendants(nodeToDelete, session.getGeneratedNodes(), deletedNodeIds);
                
                // 从会话中删除节点及其子节点
                return sessionManager.removeNodeFromSession(sessionId, nodeId)
                    .flatMap(updatedSession -> {
                        // 发送删除事件
                        SettingGenerationEvent.NodeDeletedEvent deleteEvent = 
                            new SettingGenerationEvent.NodeDeletedEvent(deletedNodeIds, "User requested node deletion");
                        emitEvent(sessionId, deleteEvent);
                        
                        log.info("Successfully deleted node {} and {} descendants from session {}", 
                            nodeId, deletedNodeIds.size() - 1, sessionId);
                        
                        return Mono.just(deletedNodeIds);
                    });
            })
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Session not found: " + sessionId)));
    }
    
    /**
     * 递归收集节点及其所有子节点的ID
     */
    private void collectNodeAndDescendants(SettingNode node, Map<String, SettingNode> allNodes, List<String> result) {
        result.add(node.getId());
        
        // 查找并递归处理子节点
        for (SettingNode potentialChild : allNodes.values()) {
            if (node.getId().equals(potentialChild.getParentId())) {
                collectNodeAndDescendants(potentialChild, allNodes, result);
            }
        }
    }

    @Override
    public Mono<SaveResult> saveGeneratedSettings(String sessionId, String novelId) {
        // 委托给带完整参数的方法，默认创建新历史记录
        return saveGeneratedSettings(sessionId, novelId, false, null);
    }
    
    @Override
    public Mono<SaveResult> saveGeneratedSettings(String sessionId, String novelId, boolean updateExisting, String targetHistoryId) {
        return sessionManager.getSession(sessionId)
            .switchIfEmpty(Mono.defer(() -> {
                // 当请求为更新现有历史且内存中找不到会话时，尝试基于历史记录恢复会话
                if (updateExisting) {
                    String historyId = (targetHistoryId != null && !targetHistoryId.isBlank()) ? targetHistoryId : sessionId;
                    log.info("Session not found in memory. Attempting to restore from history for update: {}", historyId);
                    return createSessionFromHistory(historyId)
                        .onErrorResume(err -> Mono.error(new IllegalArgumentException("Session not found and history restore failed: " + historyId, err)));
                }
                return Mono.error(new IllegalArgumentException("Session not found: " + sessionId));
            }))
            .flatMap(session -> {
                // 幂等处理：若已在生成完成时自动创建过历史记录，且此次不是要求更新现有历史，则直接返回该历史
                if (!updateExisting) {
                    Object autoSavedIdObj = session.getMetadata().get("autoSavedHistoryId");
                    if (autoSavedIdObj instanceof String autoSavedHistoryId && !autoSavedHistoryId.isBlank()) {
                        log.info("Detected autoSavedHistoryId {} for session {}, returning existing result", autoSavedHistoryId, sessionId);
                        return historyService.getHistoryById(autoSavedHistoryId)
                            .map(history -> new SaveResult(history.getRootSettingIds(), history.getHistoryId()));
                    }
                }

                // 检查会话是否有可保存的内容，而不是严格要求COMPLETED状态
                // 允许保存GENERATING、ERROR、CANCELLED状态的会话，只要有生成的节点
                SettingGenerationSession.SessionStatus status = session.getStatus();
                //List<SettingNode> generatedNodes = session.getGeneratedNodes();

                if (status == SettingGenerationSession.SessionStatus.INITIALIZING) {
                    return Mono.error(new IllegalStateException("Session is still initializing: " + sessionId));
                }
                
//                if (generatedNodes == null || generatedNodes.isEmpty()) {
//                    return Mono.error(new IllegalStateException("No generated content to save in session: " + sessionId));
//                }
                
//                // 记录保存未完成会话的情况
//                if (status != SettingGenerationSession.SessionStatus.COMPLETED) {
//                    log.info("Saving session {} with status {} - has {} generated nodes",
//                        sessionId, status, generatedNodes.size());
//                }
                
                log.info("Saving settings for session {} to novel {}", sessionId, novelId);
                
                // 1. 转换 SettingNode 为 NovelSettingItem
                List<NovelSettingItem> settingItems = conversionService.convertSessionToSettingItems(session, novelId);
                
                // 2. 先保存所有设定条目到数据库
                List<Mono<NovelSettingItem>> saveOperations = settingItems.stream()
                    .map(item -> novelSettingService.createSettingItem(item))
                    .collect(Collectors.toList());
                
                return Flux.fromIterable(saveOperations)
                    .flatMap(mono -> mono)
                    .collectList()
                    .flatMap(savedItems -> {
                        // 3. 获取保存后的设定条目ID列表
                        List<String> settingItemIds = savedItems.stream()
                            .map(NovelSettingItem::getId)
                            .collect(Collectors.toList());
                        
                        // 4. 根据参数决定创建新历史记录还是更新现有历史记录
                        Mono<NovelSettingGenerationHistory> historyMono;
                        if (updateExisting && targetHistoryId != null) {
                            log.info("更新现有历史记录: {}", targetHistoryId);
                            historyMono = historyService.updateHistoryFromSession(session, settingItemIds, targetHistoryId);
                        } else {
                            log.info("创建新历史记录");
                            historyMono = historyService.createHistoryFromSession(session, settingItemIds);
                        }
                        
                        return historyMono.flatMap(history -> {
                            // 5. 标记会话为已保存，但保持session活跃以便后续操作
                            return sessionManager.updateSessionStatus(sessionId, SettingGenerationSession.SessionStatus.SAVED)
                                .thenReturn(new SaveResult(history.getRootSettingIds(), history.getHistoryId()));
                        });
                    });
            });
    }
    
    @Override
    public Mono<List<StrategyTemplateInfo>> getAvailableStrategyTemplates() {
        // 公开接口：仅返回系统公共策略模板
        return promptTemplateRepository.findByUserId("system")
            .filter(template -> template.getFeatureType() == com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
            .filter(template -> {
                com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig cfg = template.getSettingGenerationConfig();
                return cfg != null && java.lang.Boolean.TRUE.equals(cfg.getIsSystemStrategy());
            })
            .map(this::mapToStrategyTemplateInfo)
            .collectList()
            .doOnNext(templates -> log.info("返回 {} 个系统策略模板", templates.size()));
    }

    /**
     * 已登录用户：返回系统公共策略 + 用户自定义策略
     */
    public Mono<List<StrategyTemplateInfo>> getAvailableStrategyTemplatesForUser(String userId) {
        Mono<List<StrategyTemplateInfo>> system = promptTemplateRepository.findByUserId("system")
            .filter(t -> t.getFeatureType() == com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
            .filter(t -> {
                com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig cfg = t.getSettingGenerationConfig();
                return cfg != null && java.lang.Boolean.TRUE.equals(cfg.getIsSystemStrategy());
            })
            .map(this::mapToStrategyTemplateInfo)
            .collectList();

        Mono<List<StrategyTemplateInfo>> user = promptTemplateRepository.findByUserId(userId)
            .filter(t -> t.getFeatureType() == com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
            .map(this::mapToStrategyTemplateInfo)
            .collectList();

        return Mono.zip(system, user)
            .map(tuple -> {
                List<StrategyTemplateInfo> all = new ArrayList<>();
                all.addAll(tuple.getT1());
                all.addAll(tuple.getT2());
                return all;
            })
            .doOnNext(list -> log.info("用户 {} 返回策略模板 {} 个(系统{} + 用户{})", userId, list.size(), list.size() - 0, 0));
    }

    /**
     * 保留兼容性的旧方法
     */
    @Deprecated
    public List<StrategyInfo> getAvailableStrategies() {
        return strategyFactory.getAllStrategies().values().stream()
            .map(strategy -> {
                com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig config = strategy.createDefaultConfig();
                return new StrategyInfo(
                    strategy.getStrategyName(),
                    strategy.getDescription(),
                    config.getExpectedRootNodes(),
                    config.getMaxDepth()
                );
            })
            .toList();
    }
    
    @Override
    public Mono<SettingGenerationSession> startSessionFromHistory(String historyId, String newPrompt, String modelConfigId) {
        log.info("Starting session from history: {}", historyId);
        
        return historyService.createSessionFromHistory(historyId, newPrompt)
            .flatMap(session -> {
                // 更新模型配置ID
                if (modelConfigId != null) {
                    session.getMetadata().put("modelConfigId", modelConfigId);
                }
                
                // 标记为基于现有历史记录创建
                session.setFromExistingHistory(true);
                session.setSourceHistoryId(historyId);
                
                // 创建事件流（缓存所有事件，支持大量节点）
                Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                eventSinks.put(session.getSessionId(), sink);
                
                // 发送会话创建事件
                emitEvent(session.getSessionId(), new SettingGenerationEvent.SessionStartedEvent(
                    session.getInitialPrompt(), session.getStrategy()
                ));
                
                return sessionManager.saveSession(session);
            });
    }

    @Override
    public Mono<SettingGenerationSession> startSessionFromNovel(String novelId, String userId, String editReason, String modelConfigId, boolean createNewSnapshot) {
        log.info("Starting session from novel {} for user {} with editReason: {}, createNewSnapshot: {}", novelId, userId, editReason, createNewSnapshot);
        
        if (createNewSnapshot) {
            // 用户选择创建新快照
            log.info("用户选择创建新快照，基于小说 {} 的当前设定状态", novelId);
            return createSettingSnapshotFromNovel(novelId, userId, editReason != null ? editReason : "创建新设定快照")
                .flatMap(snapshot -> {
                    String prompt = editReason != null ? editReason : "基于新快照编辑设定";
                    return startSessionFromHistory(snapshot.getHistoryId(), prompt, modelConfigId)
                        .map(session -> {
                            // 标记为基于新创建的快照（非现有历史记录）
                            session.setFromExistingHistory(false);
                            session.getMetadata().put("snapshotMode", "new");
                            return session;
                        });
                });
        } else {
            // 用户选择编辑上次设定
            log.info("用户选择编辑上次设定，查找小说 {} 的最新历史记录", novelId);
            return historyService.getUserHistories(userId, novelId, null)
                .take(1) // 获取最新的一个历史记录
                .next()
                .hasElement()
                .flatMap(hasHistory -> {
                    if (hasHistory) {
                        // 如果有历史记录，从最新的历史记录创建会话
                        log.info("找到历史记录，基于最新历史记录创建编辑会话");
                        return historyService.getUserHistories(userId, novelId, null)
                            .take(1)
                            .next()
                            .flatMap(latestHistory -> {
                                String prompt = editReason != null ? editReason : "编辑上次设定";
                                return startSessionFromHistory(latestHistory.getHistoryId(), prompt, modelConfigId)
                                    .map(session -> {
                                        // 标记为基于现有历史记录
                                        session.setFromExistingHistory(true);
                                        session.getMetadata().put("snapshotMode", "existing");
                                        return session;
                                    });
                            });
                    } else {
                        // 如果没有历史记录，自动创建新快照
                        log.info("未找到历史记录，自动创建新快照");
                        return createSettingSnapshotFromNovel(novelId, userId, "自动创建首次设定快照")
                            .flatMap(snapshot -> {
                                String prompt = editReason != null ? editReason : "基于首次快照编辑设定";
                                return startSessionFromHistory(snapshot.getHistoryId(), prompt, modelConfigId)
                                    .map(session -> {
                                        // 标记为非基于现有历史记录（因为是新创建的快照）
                                        session.setFromExistingHistory(false);
                                        session.getMetadata().put("snapshotMode", "auto_new");
                                        return session;
                                    });
                            });
                    }
                });
        }
    }

    @Override
    public Mono<SessionStatus> getSessionStatus(String sessionId) {
        log.debug("Getting session status for: {}", sessionId);
        
        return sessionManager.getSession(sessionId)
            .map(session -> new SessionStatus(
                session.getStatus().name(),
                calculateProgress(session),
                getCurrentStep(session),
                getTotalSteps(session),
                session.getErrorMessage()
            ))
            .switchIfEmpty(Mono.error(new RuntimeException("会话不存在: " + sessionId)));
    }

    @Override
    public Mono<Void> cancelSession(String sessionId) {
        log.info("Cancelling session: {}", sessionId);
        
        return sessionManager.updateSessionStatus(sessionId, SettingGenerationSession.SessionStatus.CANCELLED)
            .flatMap(session -> {
                // 发送取消事件
                emitEvent(sessionId, new SettingGenerationEvent.GenerationCompletedEvent(
                    session.getGeneratedNodes().size(),
                    calculateDuration(session),
                    "CANCELLED"
                ));
                
                // 清理事件流
                cleanupSession(sessionId);
                
                return Mono.empty();
            });
    }

    /**
     * 从历史记录创建会话
     */
    private Mono<SettingGenerationSession> createSessionFromHistory(String historyId) {
        log.info("Attempting to create session from history: {}", historyId);
        
        return historyService.getHistoryWithSettings(historyId)
            .flatMap(historyWithSettings -> {
                // 构建节点映射
                Map<String, SettingNode> nodeMap = buildNodeMap(historyWithSettings.rootNodes());
                
                log.info("Successfully fetched history {}. Creating session with {} nodes.", historyId, nodeMap.size());
                
                // 使用sessionManager创建会话
                return sessionManager.createSessionFromHistoryData(
                    historyId,
                    historyWithSettings.history().getUserId(),
                    null, // 切换历史创建会话时不继承历史的 novelId
                    historyWithSettings.history().getInitialPrompt(),
                    historyWithSettings.history().getStrategy(),
                    nodeMap,
                    historyWithSettings.history().getRootSettingIds(),
                    historyWithSettings.history().getPromptTemplateId()
                ).flatMap(session -> {
                    // 再次确保 novelId 已被清空
                    session.setNovelId(null);
                    // 兼容新流程：基于历史记录的 promptTemplateId 恢复并写入策略适配器
                    String templateId = historyWithSettings.history().getPromptTemplateId();
                    if (templateId == null || templateId.isBlank()) {
                        return sessionManager.saveSession(session);
                    }
                    return promptTemplateRepository.findById(templateId)
                        .flatMap(template -> {
                            return strategyFactory.createConfigurableStrategy(template)
                                .map(adapter -> {
                                    session.getMetadata().put("strategyAdapter", adapter);
                                    return sessionManager.saveSession(session);
                                })
                                .orElseGet(() -> {
                                    log.warn("Cannot create strategy adapter from template: {} while restoring session {}", templateId, historyId);
                                    return sessionManager.saveSession(session);
                                });
                        })
                        .switchIfEmpty(sessionManager.saveSession(session));
                });
            })
            .doOnError(error -> log.error("Failed to fetch or process history with settings for ID: {}", historyId, error));
    }

    /**
     * 递归构建节点映射
     */
    private Map<String, SettingNode> buildNodeMap(List<SettingNode> nodes) {
        Map<String, SettingNode> nodeMap = new ConcurrentHashMap<>();
        
        for (SettingNode node : nodes) {
            nodeMap.put(node.getId(), node);
            
            // 递归处理子节点
            if (node.getChildren() != null && !node.getChildren().isEmpty()) {
                nodeMap.putAll(buildNodeMap(node.getChildren()));
            }
        }
        
        return nodeMap;
    }

    /**
     * 异步生成设定（新架构）
     */
    private Mono<Void> generateSettingsAsync(SettingGenerationSession session, 
                                            com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
                                            ConfigurableStrategyAdapter strategyAdapter) {
        String contextId = "generation-" + session.getSessionId();
        String modelConfigId = (String) session.getMetadata().get("modelConfigId");

        return novelAIService.getAIModelProviderByConfigId(session.getUserId(), modelConfigId)
            .flatMap(provider -> {
                String modelName = provider.getModelName();
                Map<String, String> aiConfig = new HashMap<>();
                aiConfig.put("apiKey", provider.getApiKey());
                aiConfig.put("apiEndpoint", provider.getApiEndpoint());
                aiConfig.put("provider", provider.getProviderName());
                aiConfig.put("requestType", AIFeatureType.SETTING_TREE_GENERATION.name());
                aiConfig.put("correlationId", session.getSessionId());
                // 透传身份信息，供AIRequest写入并被LLMTrace记录
                if (session.getUserId() != null && !session.getUserId().isBlank()) {
                    aiConfig.put("userId", session.getUserId());
                }
                if (session.getSessionId() != null && !session.getSessionId().isBlank()) {
                    aiConfig.put("sessionId", session.getSessionId());
                }

                // 创建工具上下文
                ToolExecutionService.ToolCallContext context = createToolContext(contextId);
                
                // 注册工具处理器（使用策略适配器）
                registerGenerationTools(context, session, strategyAdapter);

                // 获取工具规范
                List<ToolSpecification> toolSpecs = toolRegistry.getSpecificationsForContext(contextId);

                // 改为仅使用后端配置的工具阶段提示词（不再使用 Provider 提示词）
                List<ChatMessage> messages = new ArrayList<>();
                String backendToolSystemPrompt = "你是设定生成助手。\n"
                    + "- 只能进行工具调用，不得输出任何自然语言。\n"
                    + "- 可用工具：create_setting_nodes（批量）、create_setting_node（单个）。\n"
                    + "- 完成最后一批创建时，参数中加入 complete=true；否则不要携带 complete。\n\n"
                    + "父子关系与 ID 规则：\n"
                    + "- 根节点 parentId=null；\n"
                    + "- 本批次内：为可能成为父节点的条目提供 tempId（如 R1、R2、R1-1），子节点用该 tempId 作为 parentId；\n"
                    + "- 跨批次：可继续引用先前批次定义的 tempId；\n"
                    + "- 仅在更新已存在节点时提供 id；新建时不要提供 id。\n\n"
                    + "字段规范：name,type,description 必填；parentId 见上；tempId 可选用于被引用。\n\n"
                    + "类型枚举（二选其一示例）：CHARACTER、LOCATION、ITEM、LORE、FACTION、EVENT、CONCEPT、WORLDVIEW、PLEASURE_POINT、ANTICIPATION_HOOK、POWER_SYSTEM、GOLDEN_FINGER、OTHER。\n\n"
                    + "常见错误：\n"
                    + "- 把所有节点的 parentId 设为 1；\n"
                    + "- 为根节点设置非 null 的 parentId；\n"
                    + "- 在同一批次引用未赋予 tempId 的父节点。\n\n"
                    + "完整性与停止条件：\n"
                    + "- 每批优先为尚无子节点的父节点补齐；\n"
                    + "- 建议每批创建 15-25 个节点，≥60% 为子节点；\n"
                    + "- 仅当根节点与父节点子项均达标时，才允许携带 complete=true 结束。";

                String backendToolUserPrompt = "【创意】\n" + session.getInitialPrompt() + "\n\n"
                    + "请按通用设定结构先创建必要的根节点及关键子节点，并持续分批补齐。";

                messages.add(new SystemMessage(backendToolSystemPrompt));
                messages.add(new UserMessage(backendToolUserPrompt));

                // 执行工具调用循环（传入上下文ID，供工具执行时识别）
                // 关键：将 toolContextId 透传到 AIServiceImpl 的 config 中
                aiConfig.put("toolContextId", contextId);
                aiConfig.put("requestType", com.ainovel.server.domain.model.AIFeatureType.SETTING_GENERATION_TOOL.name());
                if (modelConfigId != null) {
                    aiConfig.put("modelConfigId", modelConfigId);
                }
                return aiService.executeToolCallLoop(
                            messages,
                            toolSpecs,
                            modelName,
                            aiConfig.get("apiKey"),
                            aiConfig.get("apiEndpoint"),
                            aiConfig,
                            30
                        )
                    .flatMap(conversationHistory -> {
                        if (session.getStatus() != SettingGenerationSession.SessionStatus.COMPLETED) {
                            markGenerationComplete(session.getSessionId(), "Generation completed");
                        }
                        return Mono.empty();
                    })
                    .onErrorResume(error -> {
                        // 错误处理逻辑保持不变
                        log.error("Error in tool call loop for session: {}", session.getSessionId(), error);
                        
                        // 将中断视为取消，避免向前端发送致命错误事件
                        if (isInterrupted(error)) {
                            log.warn("Request interrupted, treat as CANCELLED in tool call loop: {}", session.getSessionId());
                            return cancelSession(session.getSessionId());
                        }

                        if (error.getMessage() != null && 
                            (error.getMessage().contains("OpenRouter API returned null response") ||
                             error.getMessage().contains("rate limit") ||
                             error.getMessage().contains("choices()") ||
                             error.getMessage().contains("API rate limit"))) {
                            
                            emitErrorEvent(session.getSessionId(), "API_ERROR", 
                                "API调用失败，可能是由于速率限制或服务异常。如果已经生成了一些设定，它们已经被保存。", 
                                null, true);
                            
                            if (!session.getGeneratedNodes().isEmpty()) {
                                log.info("Partial generation completed for session {} with {} nodes", 
                                    session.getSessionId(), session.getGeneratedNodes().size());
                                markGenerationComplete(session.getSessionId(), 
                                    "部分生成完成 - API错误导致提前结束，但已生成的设定已保存");
                                return Mono.empty();
                            }
                        }
                        
                        emitErrorEvent(session.getSessionId(), "GENERATION_FAILED", 
                            "设定生成失败: " + error.getMessage(), null, false);
                        
                        return sessionManager.updateSessionStatus(
                            session.getSessionId(), 
                            SettingGenerationSession.SessionStatus.ERROR
                        ).then(Mono.error(error));
                    })
                    .doFinally(signalType -> {
                        log.debug("Cleaning up tool context for session: {}, signal: {}", 
                            session.getSessionId(), signalType);
                        try {
                            context.close();
                        } catch (Exception e) {
                            log.warn("Failed to close tool context for session: {}", session.getSessionId(), e);
                        }
                    })
                    .subscribeOn(Schedulers.boundedElastic())
                    .then();
            });
    }

    /**
     * 判断异常是否属于中断/取消语义
     */
    private boolean isInterrupted(Throwable t) {
        for (Throwable e = t; e != null; e = e.getCause()) {
            if (e instanceof InterruptedException) {
                return true;
            }
            String msg = e.getMessage();
            if (msg != null) {
                String lower = msg.toLowerCase();
                if (lower.contains("interrupted") || msg.contains("Sending the request was interrupted")) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 🚀 获取当前请求的traceId，确保预扣费和费用调整使用同一个traceId
     */
    private String getOrCreateTraceId() {
        try {
            com.ainovel.server.domain.model.observability.LLMTrace currentTrace = traceContextManager.getTrace();
            if (currentTrace != null && currentTrace.getTraceId() != null) {
                String traceId = currentTrace.getTraceId();
                log.debug("使用系统traceId: {}", traceId);
                return traceId;
            } else {
                // 回退：如果无法获取系统traceId，生成新的
                String traceId = java.util.UUID.randomUUID().toString();
                log.warn("无法获取系统traceId，生成新的traceId: {}", traceId);
                return traceId;
            }
        } catch (Exception e) {
            // 回退：如果获取过程出错，生成新的
            String traceId = java.util.UUID.randomUUID().toString();
            log.warn("获取系统traceId时出错，生成新的traceId: {}, 错误: {}", traceId, e.getMessage());
            return traceId;
        }
    }

    /**
     * 🚀 执行带预扣费的AI请求
     * 直接使用preDeductCredits方法（已包含余额校验）
     */
    private reactor.core.publisher.Flux<String> executeAIRequestWithPrededuction(
            com.ainovel.server.domain.model.AIRequest aiRequest,
            com.ainovel.server.domain.model.PublicModelConfig publicModelConfig,
            String apiKey,
            String endpoint) {
        // 已废弃：公共模型预扣费逻辑已下沉至 Billing 装饰器与 Trace 事件监听器
        return reactor.core.publisher.Flux.error(new UnsupportedOperationException("executeAIRequestWithPrededuction is deprecated"));
    }



    /**
     * 异步修改节点（新版本 - 不删除原节点）
     */
    private Mono<Void> modifyNodeAsync(SettingGenerationSession session, SettingNode node,
                                      String modificationPrompt, String modelConfigId) {
        
        String contextId = "modification-" + session.getSessionId() + "-" + node.getId();

        // 🔧 新版本：不删除原节点，支持"以此设定为父节点"的语义
        log.info("🔄 开始修改节点（保留原节点）: {} in session: {}", node.getName(), session.getSessionId());

        return novelAIService.getAIModelProviderByConfigId(session.getUserId(), modelConfigId)
                .onErrorResume(error -> {
                    // 🔧 修复：捕获AI模型配置获取失败的错误，发送错误事件给前端
                    log.error("Failed to get AI model provider for session: {}, modelConfigId: {}, error: {}", 
                        session.getSessionId(), modelConfigId, error.getMessage());
                    
                    // 发送错误事件给前端
                    emitErrorEvent(
                        session.getSessionId(),
                        "MODEL_CONFIG_ERROR",
                        "AI模型配置获取失败: " + error.getMessage(),
                        node.getId(),
                        false // 基于错误码强制不可恢复，确保控制器不过滤并终止SSE流
                    );
                    
                    // 返回错误以终止流程
                    return Mono.error(error);
                })
                .flatMap(provider -> {
                    String modelName = provider.getModelName();
                    Map<String, String> aiConfig = new HashMap<>();
                    aiConfig.put("apiKey", provider.getApiKey());
                    aiConfig.put("apiEndpoint", provider.getApiEndpoint());
                    aiConfig.put("provider", provider.getProviderName());
                    // 透传身份信息，供AIRequest写入并被LLMTrace记录
                    if (session.getUserId() != null && !session.getUserId().isBlank()) {
                        aiConfig.put("userId", session.getUserId());
                    }
                    if (session.getSessionId() != null && !session.getSessionId().isBlank()) {
                        aiConfig.put("sessionId", session.getSessionId());
                    }
                    
                    // 创建工具上下文
                    ToolExecutionService.ToolCallContext context = createToolContext(contextId);
                            // 为修改操作注册专用工具集（不包含markGenerationComplete）
                            registerModificationTools(context, session);

                            // 获取策略适配器
                            ConfigurableStrategyAdapter strategyAdapter = (ConfigurableStrategyAdapter) session.getMetadata().get("strategyAdapter");
                            if (strategyAdapter == null) {
                                log.warn("Strategy adapter not found in session {}. Proceeding without adapter for modification.", session.getSessionId());
                            }
                            
                            List<ToolSpecification> toolSpecs = toolRegistry.getSpecificationsForContext(contextId);

                            // 构建更丰富的上下文
                            String parentPath = buildParentPath(node.getParentId(), session);

                            // 构建修改提示词的上下文
                            Map<String, Object> promptContext = new HashMap<>();
                            promptContext.put("nodeId", node.getId());
                            promptContext.put("nodeName", node.getName());
                            promptContext.put("nodeType", node.getType().toString());
                            promptContext.put("nodeDescription", node.getDescription());
                            promptContext.put("modificationPrompt", modificationPrompt);
                            promptContext.put("originalNode", node.getName() + ": " + node.getDescription());
                            promptContext.put("targetChanges", modificationPrompt);
                            promptContext.put("parentNode", parentPath);
                            // 🔧 关键修复：明确提供父节点ID给AI
                            promptContext.put("originalParentId", node.getParentId());
                            
                            // 🔧 优化：构建包含描述的节点列表，帮助AI理解上下文
                            StringBuilder availableNodes = new StringBuilder();
                            session.getGeneratedNodes().values().forEach(n -> {
                                String nodePath = buildParentPath(n.getId(), session);
                                String description = n.getDescription();
                                // 限制描述长度，避免提示词过长
                                if (description != null && description.length() > 100) {
                                    description = description.substring(0, 97) + "...";
                                }
                                availableNodes.append(String.format("- %s (ID: %s, 路径: %s)\n  描述: %s\n", 
                                    n.getName(), n.getId(), nodePath, description != null ? description : "无"));
                            });
                            promptContext.put("availableNodes", availableNodes.toString());
                            
                            // 🔧 新增：当前节点的信息（支持修改当前节点或创建子节点）
                            promptContext.put("currentNodeId", node.getId());
                            // 写入到会话元数据，供 scope 校验使用
                            session.getMetadata().put("currentNodeIdForModification", node.getId());
                            // 🔧 新增：提供scope（self|children_only|self_and_children）给AI
                            String scopeValue = (String) session.getMetadata().getOrDefault("modificationScope", "self");
                            promptContext.put("scope", scopeValue);

                            List<ChatMessage> messages = new ArrayList<>();
                            // 在系统提示中加入基于 scope 的强约束，优先级高于用户内容
                            String systemPromptWithScope = promptProvider.getDefaultSystemPrompt()
                                    + "\n\n" + getModificationToolUsageInstructions()
                                    + "\n\n" + buildScopeConstraintSystemBlock(scopeValue, node.getId(), node.getParentId());
                            messages.add(new SystemMessage(systemPromptWithScope));
                            
                            // 使用提示词提供器渲染用户消息
                            String userPromptTemplate = """
                                ## 修改任务
                                **当前节点**: {{nodeName}}
                                **节点ID**: {{currentNodeId}}
                                **当前描述**: {{nodeDescription}}
                                **修改要求**: {{modificationPrompt}}
                                **节点路径**: {{parentNode}} -> {{nodeName}}
                                
                                ## 🚨 重要：修改规则
                                根据用户的修改要求，你可以进行以下两种操作：
                                
                                ### 1. 修改当前节点本身
                                - **如果**用户要求修改当前节点的内容、描述等
                                - **必须**使用相同的节点ID: `{{currentNodeId}}`
                                - **必须**保持相同的 parentId: `{{originalParentId}}`
                                - 工具调用示例：`create_setting_node(id="{{currentNodeId}}", parentId="{{originalParentId}}", ...)`
                                
                                ### 2. 为当前节点创建子节点
                                - **如果**用户要求"以此设定为父节点"、"完善设定"、"创建子设定"等
                                - **必须**将新子节点的 parentId 设置为: `{{currentNodeId}}`
                                - 工具调用示例：`create_setting_node(parentId="{{currentNodeId}}", ...)`
                                
                                ## 🔒 修改范围(scope) 约束（必须严格遵守）
                                - scope=`self`：仅允许修改当前节点本身；禁止创建或修改任何其他节点
                                - scope=`children_only`：仅允许为当前节点创建或修改子节点；禁止修改当前节点本身
                                - scope=`self_and_children`：可同时修改当前节点并创建/修改其子节点
                                - 任何超出scope的操作都视为无效，必须忽略
                                
                                ## 可用的节点列表（供参考）
                                {{availableNodes}}
                                
                                ## 执行步骤
                                1. **仔细分析**用户的修改要求：
                                   - 是要修改当前节点？→ 使用相同ID `{{currentNodeId}}`
                                   - 是要为当前节点创建子节点？→ 设置 parentId=`{{currentNodeId}}`
                                
                                2. **使用工具创建**：
                                   - 使用 `create_setting_node` 或 `create_setting_nodes` 工具
                                   - **严格按照上述规则设置 ID 和 parentId**
                                
                                3. **完成后** 将自动结束本次修改，无需额外调用完成标记
                                
                                ## ⚠️ 关键提醒
                                - **修改当前节点**: id=`{{currentNodeId}}`, parentId=`{{originalParentId}}`
                                - **创建子节点**: parentId=`{{currentNodeId}}`（id自动生成新的UUID）
                                - **绝不能**随意更改节点的层级关系！
                                """;
                            
                            messages.add(new UserMessage(
                                promptProvider.renderPrompt(userPromptTemplate, promptContext).block()
                            ));

                    // 将工具上下文ID透传
                    aiConfig.put("toolContextId", contextId);
                    return aiService.executeToolCallLoop(
                                messages,
                                toolSpecs,
                                modelName,
                                aiConfig.get("apiKey"),
                                aiConfig.get("apiEndpoint"),
                                aiConfig,
                                1
                    ).onErrorResume(toolError -> {
                        // 🔧 修复：捕获工具执行失败的错误，发送错误事件给前端
                        log.error("Failed to execute tool loop for session: {}, node: {}, error: {}", 
                            session.getSessionId(), node.getId(), toolError.getMessage());
                        
                        // 发送错误事件给前端
                        emitErrorEvent(
                            session.getSessionId(), 
                            "MODIFICATION_FAILED", 
                            "节点修改失败: " + toolError.getMessage(), 
                            node.getId(), 
                            true
                        );
                        
                        // 返回错误以终止流程
                        return Mono.error(toolError);
                    })
                    // ✅ 成功路径自动发送完成事件并结束事件流
                    .then(Mono.fromRunnable(() -> {
                        log.info("Auto-completing modification for session {}", session.getSessionId());
                        SettingGenerationEvent.GenerationCompletedEvent event = 
                            new SettingGenerationEvent.GenerationCompletedEvent(
                                session.getGeneratedNodes().size(),
                                java.time.Duration.between(session.getCreatedAt(), LocalDateTime.now()).toMillis(),
                                "MODIFICATION_SUCCESS"
                            );
                        emitEvent(session.getSessionId(), event);
                        Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(session.getSessionId());
                        if (sink != null) {
                            sink.tryEmitComplete();
                        }
                    }))
                    .doFinally(signalType -> {
                        // 确保在所有情况下都清理工具上下文
                        log.debug("Cleaning up modification tool context for session: {}, node: {}, signal: {}", 
                            session.getSessionId(), node.getId(), signalType);
                        try {
                            context.close();
                        } catch (Exception e) {
                            log.warn("Failed to close modification tool context for session: {}, node: {}", 
                                session.getSessionId(), node.getId(), e);
                        }
                    }).subscribeOn(Schedulers.boundedElastic()).then();
                });
    }

    // 已移除公共模型分支：modifyNodeAsyncPublic
    
    /**
     * 创建工具调用上下文
     */
    private ToolExecutionService.ToolCallContext createToolContext(String contextId) {
        return toolExecutionService.createContext(contextId);
    }
    
    /**
     * 构建基于 scope 的系统级约束提示块（优先级高于用户内容）
     */
    private String buildScopeConstraintSystemBlock(String scope, String currentNodeId, String originalParentId) {
        String normalized = (scope != null && !scope.isBlank()) ? scope : "self";
        switch (normalized) {
            case "self":
                return """
## 系统范围约束（必须严格遵守）
- 仅允许修改当前节点本身；
- 工具调用必须使用固定的 id 与父关系：id = "%s"，parentId = "%s"；
- 禁止创建或修改任何其他节点。
""".formatted(currentNodeId, originalParentId);
            case "children_only":
                return """
## 系统范围约束（必须严格遵守）
- 仅允许为当前节点创建或修改子节点；
- 所有新建或修改的子节点必须使用 parentId = "%s"；
- 禁止修改当前节点本身。
""".formatted(currentNodeId);
            case "self_and_children":
                return """
## 系统范围约束（必须严格遵守）
- 可修改当前节点并创建/修改其子节点；
- 修改当前节点时：id = "%s" 且 parentId = "%s"；
- 创建/修改子节点时：parentId = "%s"。
""".formatted(currentNodeId, originalParentId, currentNodeId);
            default:
                // 默认为 self 约束
                return """
## 系统范围约束（必须严格遵守）
- 仅允许修改当前节点本身；
- 工具调用必须使用固定的 id 与父关系：id = "%s"，parentId = "%s"；
- 禁止创建或修改任何其他节点。
""".formatted(currentNodeId, originalParentId);
        }
    }

    /**
     * 构建提示词上下文
     */
    private Map<String, Object> buildPromptContext(SettingGenerationSession session, 
                                                 com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
                                                 ConfigurableStrategyAdapter strategyAdapter) {
        Map<String, Object> context = new HashMap<>();
        
        // 基础信息
        context.put("input", session.getInitialPrompt());
        context.put("novelId", session.getNovelId());
        context.put("userId", session.getUserId());
        
        // 策略配置信息
        com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig config = strategyAdapter.getCustomConfig();
        context.put("strategyName", config.getStrategyName());
        context.put("strategyDescription", config.getDescription());
        context.put("expectedRootNodes", config.getExpectedRootNodes());
        context.put("maxDepth", config.getMaxDepth());
        
        // 节点模板信息
        StringBuilder nodeTemplatesInfo = new StringBuilder();
        config.getNodeTemplates().forEach(nodeTemplate -> {
            nodeTemplatesInfo.append("**").append(nodeTemplate.getName()).append("**: ")
                           .append(nodeTemplate.getDescription()).append("\n");
        });
        context.put("nodeTemplatesInfo", nodeTemplatesInfo.toString());
        
        // 生成规则信息
        com.ainovel.server.domain.model.settinggeneration.GenerationRules rules = config.getRules();
        StringBuilder rulesInfo = new StringBuilder();
        rulesInfo.append("- 批量创建首选数量: ").append(rules.getPreferredBatchSize()).append("\n");
        rulesInfo.append("- 最大批量数量: ").append(rules.getMaxBatchSize()).append("\n");
        rulesInfo.append("- 描述长度范围: ").append(rules.getMinDescriptionLength())
                 .append("-").append(rules.getMaxDescriptionLength()).append("字\n");
        rulesInfo.append("- 要求节点关联: ").append(rules.getRequireInterConnections() ? "是" : "否").append("\n");
        context.put("generationRulesInfo", rulesInfo.toString());
        
        return context;
    }
    
    /**
     * 注册生成工具（更新版本）
     */
    private void registerGenerationTools(ToolExecutionService.ToolCallContext context, 
                                       SettingGenerationSession session, 
                                       ConfigurableStrategyAdapter strategyAdapter) {
        // 上下文级临时ID映射（跨批次）
        @SuppressWarnings("unchecked")
        java.util.Map<String, String> crossBatchTempIdMap = (java.util.Map<String, String>) context.getData("tempIdMap");
        if (crossBatchTempIdMap == null) {
            crossBatchTempIdMap = new java.util.concurrent.ConcurrentHashMap<>();
            context.setData("tempIdMap", crossBatchTempIdMap);
        }
        
        // 创建节点处理器
        CreateSettingNodeTool.SettingNodeHandler nodeHandler = node -> {
            // 使用策略验证节点
            SettingGenerationStrategy.ValidationResult strategyValidation = 
                strategyAdapter.validateNode(node, strategyAdapter.getCustomConfig(), session);
            
            if (!strategyValidation.valid()) {
                log.warn("Strategy validation failed: {}", strategyValidation.errorMessage());
                emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", 
                    strategyValidation.errorMessage(), node.getId(), true);
                return false;
            }
            
            // 基础验证
            SettingValidationService.ValidationResult validation = 
                validationService.validateNode(node, session);
            
            if (!validation.isValid()) {
                log.warn("Node validation failed: {}", validation.errors());
                emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", 
                    String.join(", ", validation.errors()), node.getId(), true);
                return false;
            }
            
            // 添加到会话
            sessionManager.addNodeToSession(session.getSessionId(), node)
                .subscribe(s -> {
                    // 发送创建事件
                    emitNodeCreatedEvent(session.getSessionId(), node, session);
                });
            
            return true;
        };
        
        // 注册工具（不再注册"生成完成"工具，避免触发额外一次模型调用）
        context.registerTool(new CreateSettingNodeTool(nodeHandler));
        context.registerTool(new BatchCreateNodesTool(nodeHandler, crossBatchTempIdMap));
    }
    
    /**
     * 注册修改工具（专用于节点修改，不包含markGenerationComplete）
     */
    private void registerModificationTools(ToolExecutionService.ToolCallContext context, 
                                         SettingGenerationSession session) {
        // 上下文级临时ID映射（用于修改过程中批量新增的父子关系）
        @SuppressWarnings("unchecked")
        java.util.Map<String, String> crossBatchTempIdMap = (java.util.Map<String, String>) context.getData("tempIdMap");
        if (crossBatchTempIdMap == null) {
            crossBatchTempIdMap = new java.util.concurrent.ConcurrentHashMap<>();
            context.setData("tempIdMap", crossBatchTempIdMap);
        }
        
        // 创建节点处理器
        CreateSettingNodeTool.SettingNodeHandler nodeHandler = node -> {
            // 验证节点
            SettingValidationService.ValidationResult validation = 
                validationService.validateNode(node, session);
            // 🔒 追加scope范围校验：仅允许在scope规定范围内创建/修改
            String scopeValue = (String) session.getMetadata().getOrDefault("modificationScope", "self");
            if (scopeValue != null) {
                boolean violatesScope = false;
                if ("self".equals(scopeValue)) {
                    // 仅允许修改当前节点：若创建了与当前节点无关的新节点则拒绝
                    // 规则：允许 id == currentNodeId 的更新；不允许 parentId == currentNodeId 的新增
                    Object currentId = session.getMetadata().get("currentNodeIdForModification");
                    if (currentId instanceof String) {
                        String currentNodeId = (String) currentId;
                        boolean isUpdateSelf = node.getId() != null && node.getId().equals(currentNodeId);
                        boolean isChildOfCurrent = node.getParentId() != null && node.getParentId().equals(currentNodeId);
                        if (!isUpdateSelf || isChildOfCurrent) {
                            violatesScope = true;
                        }
                    }
                } else if ("children_only".equals(scopeValue)) {
                    // 仅允许为当前节点创建/修改子节点，禁止直接修改当前节点本身
                    Object currentId = session.getMetadata().get("currentNodeIdForModification");
                    if (currentId instanceof String) {
                        String currentNodeId = (String) currentId;
                        boolean isUpdateSelf = node.getId() != null && node.getId().equals(currentNodeId);
                        boolean isChildOfCurrent = node.getParentId() != null && node.getParentId().equals(currentNodeId);
                        if (isUpdateSelf || !isChildOfCurrent) {
                            violatesScope = true;
                        }
                    }
                } else if ("self_and_children".equals(scopeValue)) {
                    // 同时允许修改当前节点与其子节点
                    Object currentId = session.getMetadata().get("currentNodeIdForModification");
                    if (currentId instanceof String) {
                        String currentNodeId = (String) currentId;
                        boolean isUpdateSelf = node.getId() != null && node.getId().equals(currentNodeId);
                        boolean isChildOfCurrent = node.getParentId() != null && node.getParentId().equals(currentNodeId);
                        if (!(isUpdateSelf || isChildOfCurrent)) {
                            violatesScope = true;
                        }
                    }
                }
                if (violatesScope) {
                    emitErrorEvent(session.getSessionId(), "SCOPE_VIOLATION", 
                        "操作超出允许范围(scope=" + scopeValue + ")，已忽略。", node.getId(), true);
                    return false;
                }
            }
            
            if (!validation.isValid()) {
                log.warn("Node validation failed: {}", validation.errors());
                emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", 
                    String.join(", ", validation.errors()), node.getId(), true);
                return false;
            }
            
            // 添加到会话
            sessionManager.addNodeToSession(session.getSessionId(), node)
                .subscribe(s -> {
                    // 发送创建事件
                    emitNodeCreatedEvent(session.getSessionId(), node, session);
                });
            
            return true;
        };
        
        // // 创建修改完成处理器
        // MarkModificationCompleteTool.CompletionHandler completionHandler = message -> {
        //     log.info("Modification for session {} marked as complete with message: {}", session.getSessionId(), message);
            
        //     // 发送修改完成事件
        //     SettingGenerationEvent.GenerationCompletedEvent event = 
        //         new SettingGenerationEvent.GenerationCompletedEvent(
        //             session.getGeneratedNodes().size(),
        //             java.time.Duration.between(session.getCreatedAt(), LocalDateTime.now()).toMillis(),
        //             "MODIFICATION_SUCCESS"
        //         );
        //     emitEvent(session.getSessionId(), event);
            
        //     // 完成事件流
        //     Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(session.getSessionId());
        //     if (sink != null) {
        //         sink.tryEmitComplete();
        //     }
            
        //     return true; 
        // };

        // 注册工具
        context.registerTool(new CreateSettingNodeTool(nodeHandler));
        context.registerTool(new BatchCreateNodesTool(nodeHandler, crossBatchTempIdMap));
        // 不再注册 MarkModificationCompleteTool，改为自动完成
    }
    
    /**
     * 获取修改工具使用说明
     */
    private String getModificationToolUsageInstructions() {
        return """
            
            节点修改工具使用说明（重要！）：
            
            **【可用工具】**
            - create_setting_node：创建单个新设定节点
            - create_setting_nodes：批量创建多个新设定节点（推荐使用）

            
            **【修改操作指南】**
            根据用户的修改要求，可以进行两种操作：
            
            **1. 修改当前节点本身**
            - 如果用户要求修改当前节点的内容、描述等
            - 必须使用提示词中的 `{{currentNodeId}}` 作为节点ID
            - 必须保持相同的 parentId（从提示词中的 `{{originalParentId}}` 获取）
            - 这样会更新/替换原节点的内容
            
            **2. 为当前节点创建子节点**
            - 如果用户要求"以此设定为父节点"、"完善设定"、"创建子设定"等
            - 新子节点的 parentId 必须设置为 `{{currentNodeId}}`
            - 这样新节点会成为当前节点的子节点
            
            - 推荐使用批量创建工具(createSettingNodes)一次性完成所有相关设定
            - 保持与其他现有设定的一致性和关联关系
            
            **【节点ID和parentId设置规则 - 极其重要！】**
            - **修改当前节点**：
              - id = `{{currentNodeId}}`（保持相同ID）
              - parentId = `{{originalParentId}}`（保持原父节点）
            - **为当前节点创建子节点**：
              - id = 自动生成新UUID（不设置）
              - parentId = `{{currentNodeId}}`（当前节点成为父节点）
            - **绝对禁止**：随意更改节点的层级关系或ID规则
            

            
            **【描述质量要求】**
            - **根节点描述：必须50-80字**，清晰概括该线的核心内容
            - **叶子节点描述：必须100-200字**，包含具体的背景、特征、作用、关联关系等详细信息
            - 描述必须具体生动，包含具体的人物、地点、时间、冲突等要素
            - 避免空洞的概念性文字和模糊的占位符文本
            
            **【修改策略】**
            - 优先使用批量创建，可以同时创建多个相关设定
            - 使用tempId建立同批次内的父子关系
            - 确保新设定与用户修改要求完全一致

""";
    }
    
    

    
    /**
     * 发送事件
     */
    private void emitEvent(String sessionId, SettingGenerationEvent event) {
        event.setSessionId(sessionId);
        event.setTimestamp(LocalDateTime.now());
        
        Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
        if (sink != null) {
            sink.tryEmitNext(event);
        }
    }
    
    /**
     * 发送节点创建事件
     */
    private void emitNodeCreatedEvent(String sessionId, SettingNode node, 
                                    SettingGenerationSession session) {
        String parentPath = buildParentPath(node.getParentId(), session);
        SettingGenerationEvent.NodeCreatedEvent event = new SettingGenerationEvent.NodeCreatedEvent(
            node, parentPath
        );
        emitEvent(sessionId, event);
    }
    
    /**
     * 发送错误事件
     */
    private void emitErrorEvent(String sessionId, String errorCode, String errorMessage, 
                              String nodeId, boolean recoverable) {
        SettingGenerationEvent.GenerationErrorEvent event = new SettingGenerationEvent.GenerationErrorEvent(
            errorCode, errorMessage, nodeId, recoverable
        );
        emitEvent(sessionId, event);
    }
    
    /**
     * 标记生成完成
     */
    private void markGenerationComplete(String sessionId, String message) {
        // 并发防抖：已完成直接返回；正在完成中的请求也直接返回
        if (completedSessions.contains(sessionId) || !completingSessions.add(sessionId)) {
            log.info("markGenerationComplete skipped (already completing/completed): {}", sessionId);
            return;
        }
        // ⚠️ 必须订阅，否则Mono链不会执行，导致complete事件永远不会发送
        sessionManager.updateSessionStatus(sessionId, SettingGenerationSession.SessionStatus.COMPLETED)
            .flatMap(session -> {
                try {
                    // 打上流式阶段完成标记，防止后续再触发增量编排
                    session.getMetadata().put("streamFinalized", Boolean.TRUE);
                    sessionManager.saveSession(session).subscribe();
                } catch (Exception ignore) {}
                
                SettingGenerationEvent.GenerationCompletedEvent event =
                    new SettingGenerationEvent.GenerationCompletedEvent(
                        session.getGeneratedNodes().size(),
                        java.time.Duration.between(session.getCreatedAt(), LocalDateTime.now()).toMillis(),
                        "SUCCESS"
                    );
                emitEvent(sessionId, event);

                // 完成事件流
                Sinks.Many<SettingGenerationEvent> sink = eventSinks.get(sessionId);
                if (sink != null) {
                    sink.tryEmitComplete();
                }

                // 生成完成后自动创建历史记录（兼容旧行为）
                // 防御：若没有生成任何节点则跳过自动保存，避免生成空历史
                if (session.getGeneratedNodes() == null || session.getGeneratedNodes().isEmpty()) {
                    log.info("Skip auto-save history for session {}: no generated nodes", sessionId);
                    completedSessions.add(sessionId);
                    completingSessions.remove(sessionId);
                    return Mono.just(session);
                }

                // 若前端后续再次调用保存接口，将进行幂等处理，直接返回已创建的历史记录信息
                Object exists = session.getMetadata().get("autoSavedHistoryId");
                Mono<SaveResult> saveMono = (exists instanceof String s && !s.isBlank())
                        ? historyService.getHistoryById(s).map(h -> new SaveResult(h.getRootSettingIds(), h.getHistoryId()))
                        : saveGeneratedSettings(sessionId, session.getNovelId());
                return saveMono
                    .doOnSuccess(result -> {
                        try {
                            // 记录自动保存的历史ID，便于幂等返回/后续更新
                            session.getMetadata().put("autoSavedHistoryId", result.getHistoryId());
                            sessionManager.saveSession(session).subscribe();
                            log.info("Auto-created history {} for session {} on generation complete", result.getHistoryId(), sessionId);
                            
                            // 🎁 生成成功完成后，给策略作者奖励积分
                            handleStrategyUsageReward(session.getPromptTemplateId(), session.getUserId()).subscribe();
                        } catch (Exception e) {
                            log.warn("Failed to record autoSavedHistoryId for session {}: {}", sessionId, e.getMessage());
                        }
                        completedSessions.add(sessionId);
                        completingSessions.remove(sessionId);
                    })
                    .onErrorResume(e -> {
                        log.error("Auto-create history failed for session {}: {}", sessionId, e.getMessage());
                        completedSessions.add(sessionId);
                        completingSessions.remove(sessionId);
                        return Mono.empty();
                    })
                    .thenReturn(session);
            })
            .subscribe();
    }

    /**
     * 在途任务门控：仅当文本阶段结束且无在途任务（或均超时≥3分钟）时，才触发完成。
     * - 会打印调试日志
     * - 当检测到全部在途任务超时，将清空在途任务后再完成
     */
    private void attemptFinalizeWithInFlightGate(SettingGenerationSession session, String message) {
        try {
            Object finalized = session.getMetadata().get("streamFinalized");
            if (Boolean.TRUE.equals(finalized)) {
                log.debug("[InFlight] finalize skipped (already finalized): sessionId={}", session.getSessionId());
                return;
            }
            boolean textEnded = Boolean.TRUE.equals(session.getMetadata().get("textStreamEnded"));
            long now = System.currentTimeMillis();
            long textEndedAt = 0L;
            try {
                Object tea = session.getMetadata().get("textEndedAt");
                if (tea instanceof Number) {
                    textEndedAt = ((Number) tea).longValue();
                } else if (tea instanceof String) {
                    textEndedAt = Long.parseLong((String) tea);
                }
            } catch (Exception ignore) {}
            // 轻量缓冲：文本结束至少 350ms 后才允许 finalize 判定
            if (textEnded && textEndedAt > 0 && (now - textEndedAt) < 350L) {
                log.debug("[InFlight] finalize delayed by buffer ({}ms): sessionId={} remain={} message={}", (350L - (now - textEndedAt)), session.getSessionId(), inFlightTasks.getOrDefault(session.getSessionId(), new java.util.concurrent.ConcurrentHashMap<>()).size(), message);
                return;
            }
            java.util.concurrent.ConcurrentHashMap<String, Long> map = inFlightTasks.computeIfAbsent(session.getSessionId(), k -> new java.util.concurrent.ConcurrentHashMap<String, Long>());
            int before = map.size();
            if (before > 0) {
                boolean allTimedOut = true;
                for (java.util.Map.Entry<String, Long> e : map.entrySet()) {
                    Long start = e.getValue();
                    if (start == null) { continue; }
                    long age = now - start;
                    if (age < INFLIGHT_TIMEOUT_MS) {
                        allTimedOut = false;
                        break;
                    }
                }
                if (allTimedOut) {
                    map.clear();
                    log.debug("[InFlight] all tasks timed out >=3m, cleared: sessionId={} clearedCount={}", session.getSessionId(), before);
                }
            }
            int remain = map.size();
            log.debug("[InFlight] finalize check: sessionId={} textEnded={} inFlight={} message={}", session.getSessionId(), textEnded, remain, message);
            if (textEnded && remain == 0) {
                markGenerationComplete(session.getSessionId(), message);
            }
        } catch (Exception e) {
            log.warn("[InFlight] finalize gate error: sessionId={} err={}", session.getSessionId(), e.getMessage());
            // 保守降级：不直接完成，等待下一次触发
        }
    }
    
    /**
     * 构建父节点路径
     */
    private String buildParentPath(String parentId, SettingGenerationSession session) {
        if (parentId == null) {
            return "/";
        }
        
        List<String> path = new ArrayList<>();
        String currentId = parentId;
        
        while (currentId != null) {
            SettingNode node = session.getGeneratedNodes().get(currentId);
            if (node != null) {
                path.add(0, node.getName());
                currentId = node.getParentId();
            } else {
                break;
            }
        }
        
        return "/" + String.join("/", path);
    }

    /**
     * 统一清理节点名称中可能影响前端路径解析的分隔符。
     * 将'/'替换为全角'／'，防止被视为路径分隔符。
     */
    private String sanitizeNodeName(String name) {
        if (name == null) return null;
        return name.replace("/", "／");
    }
    
    /**
     * 收集子孙节点ID
     */
    @SuppressWarnings("unused")
    private void collectDescendantIds(String nodeId, SettingGenerationSession session, 
                                    List<String> result) {
        List<String> children = session.getChildrenIds(nodeId);
        for (String childId : children) {
            result.add(childId);
            collectDescendantIds(childId, session, result);
        }
    }
    
    /**
     * 清理会话资源
     */
    private void cleanupSession(String sessionId) {
        eventSinks.remove(sessionId);
        sessionLocks.remove(sessionId);
        log.debug("Cleaned up session: {}", sessionId);
    }

    /**
     * 将EnhancedUserPromptTemplate映射为StrategyTemplateInfo
     */
    private StrategyTemplateInfo mapToStrategyTemplateInfo(com.ainovel.server.domain.model.EnhancedUserPromptTemplate template) {
        com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig config = template.getSettingGenerationConfig();
        
        if (config == null) {
            // 如果没有配置，返回默认值
            return new StrategyTemplateInfo(
                template.getId(),
                template.getName(),
                template.getDescription() != null ? template.getDescription() : "",
                0,
                5,
                true,
                java.util.List.of("系统策略"),
                java.util.List.of("系统预设")
            );
        }
        
        // 从配置中提取信息
        java.util.List<String> categories = java.util.List.of("系统策略");
        java.util.List<String> tags = java.util.List.of("系统预设");
        
        if (config.getMetadata() != null) {
            if (config.getMetadata().getCategories() != null) {
                categories = config.getMetadata().getCategories();
            }
            if (config.getMetadata().getTags() != null) {
                tags = config.getMetadata().getTags();
            }
        }
        
        return new StrategyTemplateInfo(
            template.getId(),
            config.getStrategyName() != null ? config.getStrategyName() : template.getName(),
            config.getDescription() != null ? config.getDescription() : template.getDescription(),
            config.getExpectedRootNodes() != null ? config.getExpectedRootNodes() : 0,
            config.getMaxDepth() != null ? config.getMaxDepth() : 5,
            true, // 系统策略
            categories,
            tags
        );
    }



    /**
     * 从小说创建设定快照
     */
    private Mono<NovelSettingGenerationHistory> createSettingSnapshotFromNovel(String novelId, String userId, String reason) {
        log.info("Creating setting snapshot from novel {} for user {}", novelId, userId);
        
        // 获取小说的所有设定条目
        return novelSettingService.getNovelSettingItems(novelId, null, null, null, null, null, null)
            .collectList()
            .flatMap(settings -> {
                if (settings.isEmpty()) {
                    // 如果小说没有设定，创建一个空的会话
                    return sessionManager.createSession(userId, novelId, "创建空设定快照", "default")
                        .flatMap(session -> {
                            session.setStatus(SettingGenerationSession.SessionStatus.COMPLETED);
                            return sessionManager.saveSession(session)
                                .flatMap(savedSession -> historyService.createHistoryFromSession(savedSession, new ArrayList<>()));
                        });
                } else {
                    // 创建基于现有设定的会话
                    return sessionManager.createSession(userId, novelId, "从小说设定创建快照", "snapshot")
                        .flatMap(session -> {
                            // 将设定条目转换为设定节点并添加到会话中
                            List<SettingNode> nodes = conversionService.convertSettingItemsToNodes(settings);
                            nodes.forEach(node -> session.addNode(node));
                            
                            session.setStatus(SettingGenerationSession.SessionStatus.COMPLETED);
                            return sessionManager.saveSession(session)
                                .flatMap(savedSession -> {
                                    List<String> settingIds = settings.stream()
                                        .map(NovelSettingItem::getId)
                                        .collect(Collectors.toList());
                                    return historyService.createHistoryFromSession(savedSession, settingIds);
                                });
                        });
                }
            });
    }

    /**
     * 计算会话进度
     */
    private Integer calculateProgress(SettingGenerationSession session) {
        if (session.getStatus() == SettingGenerationSession.SessionStatus.COMPLETED ||
            session.getStatus() == SettingGenerationSession.SessionStatus.SAVED) {
            return 100;
        }
        if (session.getStatus() == SettingGenerationSession.SessionStatus.GENERATING) {
            return Math.min(90, session.getGeneratedNodes().size() * 10); // 估算进度
        }
        return 0;
    }

    /**
     * 获取当前步骤描述
     */
    private String getCurrentStep(SettingGenerationSession session) {
        switch (session.getStatus()) {
            case INITIALIZING:
                return "初始化中";
            case GENERATING:
                return "生成设定中";
            case COMPLETED:
                return "生成完成";
            case SAVED:
                return "已保存";
            case ERROR:
                return "发生错误";
            case CANCELLED:
                return "已取消";
            default:
                return "未知状态";
        }
    }

    /**
     * 获取总步骤数
     */
    private Integer getTotalSteps(SettingGenerationSession session) {
        // 从策略适配器获取配置信息
        ConfigurableStrategyAdapter strategyAdapter = (ConfigurableStrategyAdapter) session.getMetadata().get("strategyAdapter");
        if (strategyAdapter != null) {
            com.ainovel.server.domain.model.settinggeneration.SettingGenerationConfig config = strategyAdapter.getCustomConfig();
            if (config != null && config.getExpectedRootNodes() != null) {
                return config.getExpectedRootNodes() * 2; // 估算：每个根节点需要2个步骤
            }
        }
        return 10; // 默认值
    }

    /**
     * 计算会话持续时间
     */
    private Long calculateDuration(SettingGenerationSession session) {
        if (session.getCreatedAt() != null && session.getUpdatedAt() != null) {
            return java.time.Duration.between(session.getCreatedAt(), session.getUpdatedAt()).toMillis();
        }
        return 0L;
    }

    /**
     * 兜底：向模型发起一次"只输出JSON"的请求，然后用解析器将其转为工具参数并落地。
     */
    @SuppressWarnings("unused")
    private Mono<Integer> attemptModelJsonifyFallback(SettingGenerationSession session,
                                                      String systemPrompt,
                                                      String userPrompt,
                                                      ConfigurableStrategyAdapter strategyAdapter) {
        return Mono.defer(() -> {
            // 统一走公共模型进行 JSON 化兜底；不依赖用户私有模型配置
            String jsonOnlySystem = systemPrompt + "\n你必须只输出 JSON，不得输出任何自然语言。" +
                    "输出对象必须是 text_to_settings 的参数对象：{\"nodes\":[...],\"complete\"?:true/false }。";

            java.util.List<com.ainovel.server.domain.model.AIRequest.Message> msgs = new java.util.ArrayList<>();
            msgs.add(com.ainovel.server.domain.model.AIRequest.Message.builder().role("system").content(jsonOnlySystem).build());
            msgs.add(com.ainovel.server.domain.model.AIRequest.Message.builder().role("user").content(userPrompt).build());

            java.util.Set<String> preferredProviders = new java.util.HashSet<>(
                java.util.Arrays.asList(
                    "openai", "anthropic", "gemini", "siliconflow", "togetherai",
                    "doubao", "ark", "volcengine", "bytedance", "zhipu", "glm",
                    "qwen", "dashscope", "tongyi", "alibaba"
                )
            );

            return publicModelConfigService.findByFeatureType(com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                .collectList()
                .flatMap(list -> {
                    com.ainovel.server.domain.model.PublicModelConfig chosen = null;
                    // 优先选择带有 "jsonify" 标签的公共模型
                    for (com.ainovel.server.domain.model.PublicModelConfig c : list) {
                        if (c.getTags() != null && c.getTags().contains("jsonify")) { chosen = c; break; }
                    }
                    // 其次选择受支持提供商的任意一个
                    if (chosen == null) {
                        for (com.ainovel.server.domain.model.PublicModelConfig c : list) {
                            String p = c.getProvider();
                            if (p != null && preferredProviders.contains(p.toLowerCase())) { chosen = c; break; }
                        }
                    }
                    // 兜底：取第一个可用配置
                    if (chosen == null && !list.isEmpty()) {
                        chosen = list.get(0);
                    }
                    if (chosen == null) {
                        return Mono.error(new IllegalStateException("No public model config available for JSONIFY fallback"));
                    }
                    final com.ainovel.server.domain.model.PublicModelConfig finalChosen = chosen;
                    log.info("[Tool][JSONifyFallback] chosen public provider={}, modelId={}, endpoint={}",
                        finalChosen.getProvider(), finalChosen.getModelId(), finalChosen.getApiEndpoint());
                    return publicModelConfigService.getActiveDecryptedApiKey(finalChosen.getProvider(), finalChosen.getModelId())
                        .flatMap(apiKey -> {
                            com.ainovel.server.domain.model.AIRequest req = com.ainovel.server.domain.model.AIRequest.builder()
                                .model(finalChosen.getModelId())
                                .messages(msgs)
                                .userId(session.getUserId())
                                .sessionId(session.getSessionId())
                                .metadata(new java.util.HashMap<>(java.util.Map.of(
                                    "userId", session.getUserId() != null ? session.getUserId() : "system",
                                    "sessionId", session.getSessionId(),
                                    "requestType", "SETTING_TOOL_JSON_FALLBACK",
                                    "usedPublicModel", Boolean.TRUE.toString(),
                                    "publicProvider", finalChosen.getProvider(),
                                    "publicModelId", finalChosen.getModelId()
                                )))
                                .build();
                            return aiService.createProviderByConfigId(session.getUserId(), finalChosen.getId())
                                .generateContent(req)
                                .map(resp -> resp != null ? resp.getContent() : null);
                        });
                })
                .flatMap(raw -> attemptTextToSettingsJsonFallback(session, raw, strategyAdapter))
                .onErrorResume(e -> {
                    log.error("JSON fallback attempt failed for session {}: {}", session.getSessionId(), e.getMessage());
                    return Mono.just(0);
                });
        });
    }

    /**
     * 兜底：直接对文本（可能含```json代码块）进行 text_to_settings 参数解析并批量创建。
     */
    private Mono<Integer> attemptTextToSettingsJsonFallback(SettingGenerationSession session,
                                                            String rawText,
                                                            ConfigurableStrategyAdapter strategyAdapter) {
        return Mono.fromCallable(() -> {
            if (rawText == null || rawText.isBlank()) return 0;
            java.util.List<com.ainovel.server.service.ai.tools.fallback.ToolFallbackParser> parsers =
                toolFallbackRegistry.getParsers("text_to_settings");
            if (parsers == null || parsers.isEmpty()) return 0;
            java.util.Map<String, Object> params = null;
            for (com.ainovel.server.service.ai.tools.fallback.ToolFallbackParser p : parsers) {
                try {
                    if (p.canParse(rawText)) {
                        params = p.parseToToolParams(rawText);
                        if (params != null) break;
                    }
                } catch (Exception ignore) {}
            }
            if (params == null) return 0;
            @SuppressWarnings("unchecked")
            java.util.List<java.util.Map<String, Object>> nodes = (java.util.List<java.util.Map<String, Object>>) params.get("nodes");
            if (nodes == null || nodes.isEmpty()) return 0;
            return applyParsedNodes(session, nodes, strategyAdapter);
        });
    }

    /**
     * 将解析出的节点参数批量落地到会话（复用 BatchCreateNodesTool 以支持 tempId 映射）。
     * 返回成功创建的节点条数（按输入nodes长度估算）。
     */
    private int applyParsedNodes(SettingGenerationSession session,
                                 java.util.List<java.util.Map<String, Object>> nodes,
                                 ConfigurableStrategyAdapter strategyAdapter) {
        if (nodes == null || nodes.isEmpty()) return 0;

        CreateSettingNodeTool.SettingNodeHandler handler = new CreateSettingNodeTool.SettingNodeHandler() {
            @Override
            public boolean handleNodeCreation(SettingNode n) {
                SettingGenerationStrategy.ValidationResult sv = strategyAdapter.validateNode(n, strategyAdapter.getCustomConfig(), session);
                if (!sv.valid()) {
                    emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", sv.errorMessage(), n.getId(), true);
                    return false;
                }
                SettingValidationService.ValidationResult v = validationService.validateNode(n, session);
                if (!v.isValid()) {
                    emitErrorEvent(session.getSessionId(), "VALIDATION_ERROR", java.lang.String.join(", ", v.errors()), n.getId(), true);
                    return false;
                }
                sessionManager.addNodeToSession(session.getSessionId(), n).subscribe(s -> emitNodeCreatedEvent(session.getSessionId(), n, session));
                return true;
            }
        };

        @SuppressWarnings("unchecked")
        java.util.Map<String, String> crossBatchTempIdMap = (java.util.Map<String, String>) session.getMetadata().get("tempIdMap");
        if (crossBatchTempIdMap == null) {
            crossBatchTempIdMap = new java.util.concurrent.ConcurrentHashMap<String, String>();
            session.getMetadata().put("tempIdMap", crossBatchTempIdMap);
        }

        com.ainovel.server.service.setting.generation.tools.BatchCreateNodesTool batch = new com.ainovel.server.service.setting.generation.tools.BatchCreateNodesTool(handler, crossBatchTempIdMap);
        java.util.Map<String, Object> params = new java.util.HashMap<String, Object>();
        params.put("nodes", nodes);
        try {
            Object resultObj = batch.execute(params);
            if (resultObj instanceof java.util.Map) {
                @SuppressWarnings("unchecked")
                java.util.Map<String, Object> resultMap = (java.util.Map<String, Object>) resultObj;
                Object created = resultMap.get("createdNodeIds");
                if (created instanceof java.util.List) {
                    return ((java.util.List<?>) created).size();
                }
                Object totalCreated = resultMap.get("totalCreated");
                if (totalCreated instanceof Number) {
                    return ((Number) totalCreated).intValue();
                }
            }
        } catch (Exception e) {
            emitErrorEvent(session.getSessionId(), "BATCH_CREATE_ERROR", e.getMessage(), null, true);
            return 0;
        }
        // 回退：若无法解析结果，则返回输入节点数作为估算
        return nodes.size();
    }
    
    // ==================== 📚 知识库集成功能 ====================
    
    /**
     * 启动支持知识库集成的设定生成
     * 
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param initialPrompt 用户提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param usePublicTextModel 是否使用公共文本模型
     * @param knowledgeBaseMode 知识库模式 (NONE/REUSE/IMITATION/HYBRID)
     * @param knowledgeBaseIds 知识库ID列表
     * @param knowledgeBaseCategories 知识库分类映射
     * @return 会话Mono
     */
    public Mono<SettingGenerationSession> startGenerationWithKnowledgeBase(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Boolean usePublicTextModel,
            String knowledgeBaseMode,
            List<String> knowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        // 如果没有指定知识库模式或为NONE，使用默认流程
        if (knowledgeBaseMode == null || "NONE".equalsIgnoreCase(knowledgeBaseMode) || 
            knowledgeBaseIds == null || knowledgeBaseIds.isEmpty()) {
            log.info("[KB-Integration] No knowledge base mode specified, using default flow");
            return startGenerationHybrid(userId, novelId, initialPrompt, promptTemplateId, 
                                       modelConfigId, null, usePublicTextModel);
        }
        
        log.info("[KB-Integration] Starting generation with mode: {}, KBs: {}", 
                knowledgeBaseMode, knowledgeBaseIds);
        
        // 根据模式分发处理
        switch (knowledgeBaseMode.toUpperCase()) {
            case "REUSE":
                return handleReuseMode(userId, novelId, initialPrompt, promptTemplateId, 
                                     modelConfigId, knowledgeBaseIds, knowledgeBaseCategories);
            case "IMITATION":
                return handleImitationMode(userId, novelId, initialPrompt, promptTemplateId, 
                                          modelConfigId, usePublicTextModel, knowledgeBaseIds, 
                                          knowledgeBaseCategories);
            case "HYBRID":
                return handleHybridMode(userId, novelId, initialPrompt, promptTemplateId, 
                                      modelConfigId, usePublicTextModel, knowledgeBaseIds, 
                                      knowledgeBaseCategories);
            default:
                log.warn("[KB-Integration] Unknown mode: {}, falling back to default", knowledgeBaseMode);
                return startGenerationHybrid(userId, novelId, initialPrompt, promptTemplateId, 
                                           modelConfigId, null, usePublicTextModel);
        }
    }
    
    /**
     * 模式1：复用知识库设定
     * 直接从知识库复制设定，不调用LLM
     */
    private Mono<SettingGenerationSession> handleReuseMode(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            List<String> knowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        log.info("[KB-Reuse] Starting reuse mode for KBs: {}", knowledgeBaseIds);
        
        // 获取第一个知识库（复用模式通常只选一个）
        String kbId = knowledgeBaseIds.get(0);
        
        return knowledgeBaseRepository.findById(kbId)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Knowledge base not found: " + kbId)))
            .flatMap(kb -> {
                // 根据用户选择的分类过滤设定
                List<NovelSettingItem> filteredSettings = filterSettingsByCategories(kb, knowledgeBaseCategories);
                
                if (filteredSettings.isEmpty()) {
                    return Mono.error(new IllegalArgumentException("No settings found in selected categories"));
                }
                
                log.info("[KB-Reuse] Filtered {} settings from KB: {}", filteredSettings.size(), kb.getTitle());
                
                // 获取提示词模板（需要策略适配器）
                return promptTemplateRepository.findById(promptTemplateId)
                    .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
                    .flatMap(template -> {
                        return strategyFactory.createConfigurableStrategy(template)
                            .map(Mono::just)
                            .orElse(Mono.error(new IllegalArgumentException("Cannot create strategy from template")))
                            .flatMap(strategyAdapter -> {
                                // 创建会话
                                return sessionManager.createSession(userId, novelId, initialPrompt, 
                                                                   strategyAdapter.getStrategyId(), promptTemplateId)
                                    .flatMap(session -> {
                                        // 创建事件流（缓存所有事件，支持大量节点）
                                        Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                                        eventSinks.put(session.getSessionId(), sink);
                                        
                                        // 发送开始事件
                                        emitEvent(session.getSessionId(), new SettingGenerationEvent.SessionStartedEvent(
                                            initialPrompt, strategyAdapter.getStrategyId()
                                        ));
                                        
                                        // 存储知识库信息到元数据
                                        session.getMetadata().put("knowledgeBaseMode", "REUSE");
                                        session.getMetadata().put("sourceKnowledgeBaseId", kbId);
                                        session.getMetadata().put("sourceKnowledgeBaseTitle", kb.getTitle());
                                        session.getMetadata().put("modelConfigId", modelConfigId);
                                        
                                        // 将知识库设定转换为节点并添加到会话
                                        List<SettingNode> nodes = convertSettingsToNodes(filteredSettings);
                                        
                                        return Flux.fromIterable(nodes)
                                            .flatMap(node -> sessionManager.addNodeToSession(session.getSessionId(), node)
                                                .doOnSuccess(s -> emitNodeCreatedEvent(session.getSessionId(), node, session)))
                                            .then(sessionManager.updateSessionStatus(session.getSessionId(), 
                                                                                   SettingGenerationSession.SessionStatus.COMPLETED))
                                            .then(Mono.fromRunnable(() -> {
                                                // 发送完成事件
                                                SettingGenerationEvent.GenerationCompletedEvent completedEvent = 
                                                    new SettingGenerationEvent.GenerationCompletedEvent();
                                                completedEvent.setSessionId(session.getSessionId());
                                                completedEvent.setStatus("已成功复用知识库设定：" + kb.getTitle() + 
                                                                        "，共 " + nodes.size() + " 个设定项");
                                                completedEvent.setTimestamp(LocalDateTime.now());
                                                completedEvent.setTotalNodesGenerated(nodes.size());
                                                emitEvent(session.getSessionId(), completedEvent);
                                            }))
                                            .thenReturn(session);
                                    });
                            });
                    });
            });
    }
    
    /**
     * 模式2：设定仿写
     * 使用知识库设定作为参考，拼接到提示词中让AI仿写
     */
    private Mono<SettingGenerationSession> handleImitationMode(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Boolean usePublicTextModel,
            List<String> knowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        log.info("[KB-Imitation] Starting imitation mode for KBs: {}", knowledgeBaseIds);
        
        // 获取所有选中的知识库设定作为参考
        return fetchKnowledgeBaseSettings(knowledgeBaseIds, knowledgeBaseCategories)
            .flatMap(referenceSettings -> {
                if (referenceSettings.isEmpty()) {
                    log.warn("[KB-Imitation] No reference settings found, proceeding with original prompt");
                    return startGenerationHybrid(userId, novelId, initialPrompt, promptTemplateId, 
                                               modelConfigId, null, usePublicTextModel);
                }
                
                // 构建增强的提示词（在用户输入前添加参考设定）
                String enhancedPrompt = buildEnhancedPromptWithReferences(initialPrompt, referenceSettings);
                
                log.info("[KB-Imitation] Enhanced prompt with {} reference settings", referenceSettings.size());
                
                // 使用增强后的提示词调用正常生成流程
                return startGenerationHybrid(userId, novelId, enhancedPrompt, promptTemplateId, 
                                           modelConfigId, null, usePublicTextModel)
                    .doOnSuccess(session -> {
                        // 在会话元数据中标记知识库信息
                        session.getMetadata().put("knowledgeBaseMode", "IMITATION");
                        session.getMetadata().put("referenceKnowledgeBaseIds", knowledgeBaseIds);
                        sessionManager.saveSession(session).subscribe();
                    });
            });
    }
    
    /**
     * 模式3：混合模式
     * 复用部分设定，同时让AI生成新设定
     */
    /**
     * 混合模式知识库集成（明确区分复用和参考）
     */
    @Override
    public Mono<SettingGenerationSession> startGenerationWithKnowledgeBaseHybrid(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Boolean usePublicTextModel,
            List<String> reuseKnowledgeBaseIds,
            List<String> referenceKnowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        log.info("[KB-Hybrid] 混合模式: 复用={}, 参考={}", reuseKnowledgeBaseIds, referenceKnowledgeBaseIds);
        
        return handleHybridModeWithSeparateLists(
                userId, novelId, initialPrompt, promptTemplateId, modelConfigId,
                usePublicTextModel, reuseKnowledgeBaseIds, referenceKnowledgeBaseIds,
                knowledgeBaseCategories);
    }
    
    private Mono<SettingGenerationSession> handleHybridMode(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Boolean usePublicTextModel,
            List<String> knowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        log.info("[KB-Hybrid] Starting hybrid mode for KBs: {}", knowledgeBaseIds);
        
        // 第一个知识库用于复用，其余用于参考
        List<String> reuseKbIds = List.of(knowledgeBaseIds.get(0));
        List<String> referenceKbIds = knowledgeBaseIds.size() > 1 
            ? knowledgeBaseIds.subList(1, knowledgeBaseIds.size()) 
            : new ArrayList<>();
        
        return handleHybridModeWithSeparateLists(
                userId, novelId, initialPrompt, promptTemplateId, modelConfigId,
                usePublicTextModel, reuseKbIds, referenceKbIds, knowledgeBaseCategories);
    }
    
    /**
     * 混合模式核心逻辑（接收明确分离的复用和参考列表）
     */
    private Mono<SettingGenerationSession> handleHybridModeWithSeparateLists(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Boolean usePublicTextModel,
            List<String> reuseKbIds,
            List<String> referenceKbIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        log.info("[KB-Hybrid-Core] 复用: {}, 参考: {}", reuseKbIds, referenceKbIds);
        
        // 获取要复用的设定（支持多个知识库）
        Mono<List<NovelSettingItem>> reuseSettingsMono = reuseKbIds.isEmpty()
            ? Mono.just(new ArrayList<>())
            : fetchKnowledgeBaseSettings(reuseKbIds, knowledgeBaseCategories);
        
        // 获取参考设定（如果有）
        Mono<List<NovelSettingItem>> referenceSettingsMono = (referenceKbIds == null || referenceKbIds.isEmpty())
            ? Mono.just(new ArrayList<>())
            : fetchKnowledgeBaseSettings(referenceKbIds, knowledgeBaseCategories);
        
        return Mono.zip(reuseSettingsMono, referenceSettingsMono)
            .flatMap(tuple -> {
                List<NovelSettingItem> reuseSettings = tuple.getT1();
                List<NovelSettingItem> referenceSettings = tuple.getT2();
                
                log.info("[KB-Hybrid] 复用: {} 个设定, 参考: {} 个设定", 
                        reuseSettings.size(), referenceSettings.size());
                
                // 构建增强的提示词（如果有参考设定）
                String enhancedPrompt = referenceSettings.isEmpty()
                    ? initialPrompt
                    : buildEnhancedPromptWithReferences(initialPrompt, referenceSettings);
                
                // 先调用LLM生成新设定
                return startGenerationHybrid(userId, novelId, enhancedPrompt, promptTemplateId, 
                                           modelConfigId, null, usePublicTextModel)
                    .flatMap(session -> {
                        // 标记会话为混合模式
                        session.getMetadata().put("knowledgeBaseMode", "HYBRID");
                        session.getMetadata().put("reuseKnowledgeBaseIds", reuseKbIds);
                        if (referenceKbIds != null && !referenceKbIds.isEmpty()) {
                            session.getMetadata().put("referenceKnowledgeBaseIds", referenceKbIds);
                        }
                        
                        // 如果有复用设定，等待LLM生成完成后添加
                        if (!reuseSettings.isEmpty()) {
                            return waitForGenerationComplete(session.getSessionId())
                                .then(addReuseSettingsAsParentNodes(session, reuseSettings))
                                .thenReturn(session);
                        }
                        
                        return Mono.just(session);
                    });
            });
    }
    
    /**
     * 等待生成完成
     */
    private Mono<Void> waitForGenerationComplete(String sessionId) {
        return Mono.delay(java.time.Duration.ofSeconds(1))
            .flatMap(tick -> sessionManager.getSession(sessionId))
            .flatMap(session -> {
                if (session.getStatus() == SettingGenerationSession.SessionStatus.COMPLETED ||
                    session.getStatus() == SettingGenerationSession.SessionStatus.ERROR) {
                    return Mono.empty();
                }
                // 递归等待
                return waitForGenerationComplete(sessionId);
            })
            .timeout(java.time.Duration.ofMinutes(5))
            .onErrorResume(e -> {
                log.warn("[KB-Hybrid] Wait timeout or error: {}", e.getMessage());
                return Mono.empty();
            });
    }
    
    /**
     * 将复用的设定添加为父节点
     */
    private Mono<Void> addReuseSettingsAsParentNodes(
            SettingGenerationSession session,
            List<NovelSettingItem> reuseSettings) {
        
        return Mono.fromRunnable(() -> {
            log.info("[KB-Hybrid] Adding {} reused settings as parent nodes", reuseSettings.size());
            
            // 将复用的设定转换为节点
            List<SettingNode> reuseNodes = convertSettingsToNodes(reuseSettings);
            
            // 将复用节点添加到会话的开头
            for (SettingNode node : reuseNodes) {
                // 使用addNode方法添加节点，会自动处理到generatedNodes和rootNodeIds
                session.addNode(node);
            }
            
            // 保存会话并发送事件
            sessionManager.saveSession(session)
                .doOnSuccess(s -> {
                    for (SettingNode node : reuseNodes) {
                        emitNodeCreatedEvent(session.getSessionId(), node, session);
                    }
                    
                    // 发送特殊事件通知前端已添加复用设定
                    SettingGenerationEvent.GenerationCompletedEvent event = 
                        new SettingGenerationEvent.GenerationCompletedEvent();
                    event.setSessionId(session.getSessionId());
                    event.setStatus("已添加 " + reuseNodes.size() + " 个复用设定作为基础设定");
                    event.setTimestamp(LocalDateTime.now());
                    event.setTotalNodesGenerated(reuseNodes.size());
                    emitEvent(session.getSessionId(), event);
                })
                .subscribe();
        });
    }
    
    /**
     * 从多个知识库获取设定
     */
    private Mono<List<NovelSettingItem>> fetchKnowledgeBaseSettings(
            List<String> knowledgeBaseIds,
            Map<String, List<String>> categoriesMap) {
        
        return Flux.fromIterable(knowledgeBaseIds)
            .flatMap(kbId -> knowledgeBaseRepository.findById(kbId)
                .map(kb -> filterSettingsByCategories(kb, categoriesMap))
                .onErrorResume(e -> {
                    log.warn("[KB-Integration] Failed to fetch KB {}: {}", kbId, e.getMessage());
                    return Mono.just(new ArrayList<NovelSettingItem>());
                }))
            .collectList()
            .map(listOfLists -> listOfLists.stream()
                .flatMap(List::stream)
                .collect(Collectors.toList()));
    }
    
    /**
     * 根据分类过滤知识库设定
     */
    private List<NovelSettingItem> filterSettingsByCategories(
            com.ainovel.server.domain.model.NovelKnowledgeBase kb,
            Map<String, List<String>> categoriesMap) {
        
        List<String> selectedCategories = categoriesMap != null 
            ? categoriesMap.get(kb.getId()) 
            : null;
        
        // 如果没有指定分类，返回所有设定
        if (selectedCategories == null || selectedCategories.isEmpty()) {
            List<NovelSettingItem> allSettings = new ArrayList<>();
            if (kb.getNarrativeStyleSettings() != null) allSettings.addAll(kb.getNarrativeStyleSettings());
            if (kb.getCharacterPlotSettings() != null) allSettings.addAll(kb.getCharacterPlotSettings());
            if (kb.getNovelFeatureSettings() != null) allSettings.addAll(kb.getNovelFeatureSettings());
            if (kb.getHotMemesSettings() != null) allSettings.addAll(kb.getHotMemesSettings());
            if (kb.getCustomSettings() != null) allSettings.addAll(kb.getCustomSettings());
            if (kb.getReaderEmotionSettings() != null) allSettings.addAll(kb.getReaderEmotionSettings());
            return allSettings;
        }
        
        List<NovelSettingItem> filtered = new ArrayList<>();
        
        for (String category : selectedCategories) {
            switch (category.toUpperCase()) {
                case "NARRATIVE_STYLE":
                case "WRITING_STYLE":
                case "WORD_USAGE":
                    if (kb.getNarrativeStyleSettings() != null) {
                        filtered.addAll(kb.getNarrativeStyleSettings());
                    }
                    break;
                case "CORE_CONFLICT":
                case "SUSPENSE_DESIGN":
                case "STORY_PACING":
                case "CHARACTER_BUILDING":
                    if (kb.getCharacterPlotSettings() != null) {
                        filtered.addAll(kb.getCharacterPlotSettings());
                    }
                    break;
                case "WORLDVIEW":
                case "GOLDEN_FINGER":
                    if (kb.getNovelFeatureSettings() != null) {
                        filtered.addAll(kb.getNovelFeatureSettings());
                    }
                    break;
                case "HOT_MEMES":
                case "FUNNY_POINTS":
                    if (kb.getHotMemesSettings() != null) {
                        filtered.addAll(kb.getHotMemesSettings());
                    }
                    break;
                case "RESONANCE":
                case "PLEASURE_POINT":
                case "EXCITEMENT_POINT":
                    if (kb.getReaderEmotionSettings() != null) {
                        filtered.addAll(kb.getReaderEmotionSettings());
                    }
                    break;
                case "CUSTOM":
                    if (kb.getCustomSettings() != null) {
                        filtered.addAll(kb.getCustomSettings());
                    }
                    break;
            }
        }
        
        return filtered;
    }
    
    /**
     * 构建带参考的增强提示词
     */
    private String buildEnhancedPromptWithReferences(
            String userPrompt,
            List<NovelSettingItem> referenceSettings) {
        
        if (referenceSettings == null || referenceSettings.isEmpty()) {
            return userPrompt;
        }
        
        StringBuilder enhanced = new StringBuilder();
        enhanced.append("===== 参考设定（请参考以下设定的风格和结构进行创作） =====\n\n");
        
        // 按类型分组显示参考设定
        Map<String, List<NovelSettingItem>> groupedByType = referenceSettings.stream()
            .collect(Collectors.groupingBy(setting -> 
                setting.getType() != null ? setting.getType() : "OTHER"));
        
        for (Map.Entry<String, List<NovelSettingItem>> entry : groupedByType.entrySet()) {
            enhanced.append("【").append(entry.getKey()).append("】\n");
            for (NovelSettingItem setting : entry.getValue()) {
                enhanced.append("  • ").append(setting.getName()).append("\n");
                if (setting.getDescription() != null && !setting.getDescription().isBlank()) {
                    String content = setting.getDescription();
                    // 限制每个设定的长度，避免提示词过长
                    if (content.length() > 200) {
                        content = content.substring(0, 200) + "...";
                    }
                    enhanced.append("    ").append(content.replace("\n", "\n    ")).append("\n");
                }
                enhanced.append("\n");
            }
        }
        
        enhanced.append("===== 用户生成需求 =====\n\n");
        enhanced.append(userPrompt);
        enhanced.append("\n\n");
        enhanced.append("注意：请参考以上设定的风格、深度和结构，生成符合用户需求的新设定。");
        enhanced.append("不要直接复制参考设定，而是要创造性地结合参考风格和用户需求。");
        
        return enhanced.toString();
    }
    
    /**
     * 将设定列表转换为节点结构
     */
    private List<SettingNode> convertSettingsToNodes(List<NovelSettingItem> settings) {
        if (settings == null || settings.isEmpty()) {
            return new ArrayList<>();
        }
        
        return settings.stream()
            .map(setting -> {
                SettingNode node = SettingNode.builder()
                    .id(java.util.UUID.randomUUID().toString())
                    .name(setting.getName())
                    .type(SettingType.fromValue(setting.getType()))
                    .description(setting.getDescription())
                    .attributes(setting.getAttributes() != null 
                        ? new HashMap<>(setting.getAttributes()) 
                        : new HashMap<>())
                    .children(new ArrayList<>())
                    .generationStatus(SettingNode.GenerationStatus.COMPLETED)
                    .build();
                // 标记为来自知识库
                node.getAttributes().put("fromKnowledgeBase", "true");
                return node;
            })
            .collect(Collectors.toList());
    }
    
    // ==================== 结构化输出循环模式 ====================
    
    /**
     * 启动设定生成（结构化输出循环模式）
     * 不使用工具调用，直接输出JSON，循环最多N次直到满足质量要求
     * 
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param initialPrompt 用户提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param maxIterations 最大迭代次数
     * @return 会话Mono
     */
    @Override
    public Mono<SettingGenerationSession> startGenerationStructured(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Integer maxIterations) {
        
        return startGenerationStructuredWithKnowledgeBase(
            userId, novelId, initialPrompt, promptTemplateId, modelConfigId, maxIterations,
            null, null, null, null, null
        );
    }
    
    /**
     * 启动设定生成（结构化输出循环模式 + 知识库集成）
     */
    @Override
    public Mono<SettingGenerationSession> startGenerationStructuredWithKnowledgeBase(
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Integer maxIterations,
            String knowledgeBaseMode,
            List<String> knowledgeBaseIds,
            List<String> reuseKnowledgeBaseIds,
            List<String> referenceKnowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        return startGenerationStructuredWithKnowledgeBase(null, userId, novelId, initialPrompt,
                promptTemplateId, modelConfigId, maxIterations, knowledgeBaseMode, knowledgeBaseIds,
                reuseKnowledgeBaseIds, referenceKnowledgeBaseIds, knowledgeBaseCategories);
    }
    
    /**
     * 🔧 新增：支持前端传入sessionId的重载方法
     */
    public Mono<SettingGenerationSession> startGenerationStructuredWithKnowledgeBase(
            String sessionId,
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            Integer maxIterations,
            String knowledgeBaseMode,
            List<String> knowledgeBaseIds,
            List<String> reuseKnowledgeBaseIds,
            List<String> referenceKnowledgeBaseIds,
            Map<String, List<String>> knowledgeBaseCategories) {
        
        int iterations = (maxIterations != null && maxIterations > 0) ? maxIterations : 3;
        log.info("[StructuredOutput] 启动结构化输出循环生成: sessionId={}, userId={}, iterations={}, KB模式={}", 
            sessionId, userId, iterations, knowledgeBaseMode);
        log.info("[StructuredOutput] 知识库参数: knowledgeBaseIds={}, reuseKbIds={}, referenceKbIds={}, categories={}", 
            knowledgeBaseIds != null ? knowledgeBaseIds.size() + "个" : "null",
            reuseKnowledgeBaseIds != null ? reuseKnowledgeBaseIds.size() + "个" : "null",
            referenceKnowledgeBaseIds != null ? referenceKnowledgeBaseIds.size() + "个" : "null",
            knowledgeBaseCategories != null ? "已提供" : "null");
        
        // 如果没有知识库参数，直接使用原始提示词
        if (knowledgeBaseMode == null || "NONE".equalsIgnoreCase(knowledgeBaseMode)) {
            log.info("[StructuredOutput] 知识库模式为NONE，使用默认流程");
            return startGenerationStructuredInternal(sessionId, userId, novelId, initialPrompt, 
                promptTemplateId, modelConfigId, iterations);
        }
        
        // REUSE模式：直接将知识库设定转换为设定树，不调用LLM
        if ("REUSE".equalsIgnoreCase(knowledgeBaseMode)) {
            log.info("[StructuredOutput-Reuse] 直接复用知识库设定，不调用LLM");
            
            return fetchKnowledgeBaseSettings(knowledgeBaseIds, knowledgeBaseCategories)
                .flatMap(reuseSettings -> {
                    if (reuseSettings.isEmpty()) {
                        return Mono.error(new IllegalArgumentException("No settings found in selected categories"));
                    }
                    
                    log.info("[StructuredOutput-Reuse] 复用 {} 个设定", reuseSettings.size());
                    
                    // 获取提示词模板（需要策略信息）
                    return promptTemplateRepository.findById(promptTemplateId)
                        .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
                        .flatMap(template -> {
                            String strategyName = (template.getSettingGenerationConfig() != null && 
                                                  template.getSettingGenerationConfig().getStrategyName() != null) 
                                                  ? template.getSettingGenerationConfig().getStrategyName() 
                                                  : template.getName();
                            
                            // 创建会话
                            return sessionManager.createSession(userId, novelId, initialPrompt, 
                                                              strategyName, promptTemplateId)
                                .flatMap(session -> {
                                    // 标记会话元数据
                                    session.setStatus(SettingGenerationSession.SessionStatus.GENERATING);
                                    if (session.getMetadata() == null) {
                                        session.setMetadata(new java.util.concurrent.ConcurrentHashMap<>());
                                    }
                                    session.getMetadata().put("knowledgeBaseMode", "REUSE");
                                    session.getMetadata().put("knowledgeBaseIds", knowledgeBaseIds);
                                    session.getMetadata().put("mode", "STRUCTURED_OUTPUT");
                                    
                                    // 将知识库设定转换为节点并添加到会话
                                    List<SettingNode> reuseNodes = convertSettingsToNodes(reuseSettings);
                                    
                                    for (SettingNode node : reuseNodes) {
                                        session.addNode(node);
                                    }
                                    
                                    // 标记会话完成
                                    session.setStatus(SettingGenerationSession.SessionStatus.COMPLETED);
                                    
                                    log.info("[StructuredOutput-Reuse] 成功复用 {} 个设定节点", reuseNodes.size());
                                    
                                    // 创建事件流sink并发送事件（缓存所有事件，支持大量节点）
                                    Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                                    eventSinks.put(session.getSessionId(), sink);
                                    
                                    // 发送节点创建事件
                                    for (SettingNode node : reuseNodes) {
                                        emitNodeCreatedEvent(session.getSessionId(), node, session);
                                    }
                                    
                                    // 保存会话
                                    return sessionManager.saveSession(session)
                                        .doOnSuccess(s -> {
                                            // 发送完成事件并创建历史记录
                                            markGenerationComplete(session.getSessionId(), 
                                                "已复用 " + reuseNodes.size() + " 个知识库设定");
                                        })
                                        .thenReturn(session);
                                });
                        });
                });
        }
        
        // IMITATION模式：获取参考设定并增强提示词
        if ("IMITATION".equalsIgnoreCase(knowledgeBaseMode)) {
            log.info("[StructuredOutput-Imitation] 获取知识库参考设定");
            
            return fetchKnowledgeBaseSettings(knowledgeBaseIds, knowledgeBaseCategories)
                .flatMap(referenceSettings -> {
                    if (referenceSettings.isEmpty()) {
                        log.warn("[StructuredOutput-Imitation] No reference settings found, proceeding with original prompt");
                        return startGenerationStructuredInternal(sessionId, userId, novelId, initialPrompt, 
                            promptTemplateId, modelConfigId, iterations);
                    }
                    
                    // 构建增强的提示词
                    String enhancedPrompt = buildEnhancedPromptWithReferences(initialPrompt, referenceSettings);
                    
                    log.info("[StructuredOutput-Imitation] Enhanced prompt with {} reference settings", referenceSettings.size());
                    
                    // 使用增强后的提示词调用结构化输出流程
                    return startGenerationStructuredInternal(sessionId, userId, novelId, enhancedPrompt, 
                        promptTemplateId, modelConfigId, iterations)
                        .doOnSuccess(session -> {
                            session.getMetadata().put("knowledgeBaseMode", "IMITATION");
                            session.getMetadata().put("knowledgeBaseIds", knowledgeBaseIds);
                            sessionManager.saveSession(session).subscribe();
                        });
                });
        }
        
        // HYBRID模式：先添加复用设定（并发送事件），再生成新设定
        if ("HYBRID".equalsIgnoreCase(knowledgeBaseMode)) {
            log.info("[StructuredOutput-Hybrid] 混合模式：先推送复用节点，再启动AI生成");
            
            // ✅ 使用显式传递的分组参数
            if (reuseKnowledgeBaseIds == null || reuseKnowledgeBaseIds.isEmpty()) {
                return Mono.error(new IllegalArgumentException("HYBRID模式必须提供reuseKnowledgeBaseIds"));
            }
            
            log.info("[StructuredOutput-Hybrid] 复用知识库: {}, 参考知识库: {}", 
                reuseKnowledgeBaseIds, referenceKnowledgeBaseIds);
            
            // 获取要复用的设定
            Mono<List<NovelSettingItem>> reuseSettingsMono = fetchKnowledgeBaseSettings(
                reuseKnowledgeBaseIds, knowledgeBaseCategories);
            
            // 获取参考设定（如果有）
            Mono<List<NovelSettingItem>> referenceSettingsMono = 
                (referenceKnowledgeBaseIds == null || referenceKnowledgeBaseIds.isEmpty())
                ? Mono.just(new ArrayList<>())
                : fetchKnowledgeBaseSettings(referenceKnowledgeBaseIds, knowledgeBaseCategories);
            
            return Mono.zip(reuseSettingsMono, referenceSettingsMono, 
                          promptTemplateRepository.findById(promptTemplateId))
                .flatMap(tuple -> {
                    List<NovelSettingItem> reuseSettings = tuple.getT1();
                    List<NovelSettingItem> referenceSettings = tuple.getT2();
                    com.ainovel.server.domain.model.EnhancedUserPromptTemplate template = tuple.getT3();
                    
                    log.info("[StructuredOutput-Hybrid] 复用: {} 个设定, 参考: {} 个设定", 
                            reuseSettings.size(), referenceSettings.size());
                    
                    // 构建增强的提示词（如果有参考设定）
                    String enhancedPrompt = referenceSettings.isEmpty()
                        ? initialPrompt
                        : buildEnhancedPromptWithReferences(initialPrompt, referenceSettings);
                    
                    // 获取策略名称
                    String strategyName = (template.getSettingGenerationConfig() != null && 
                                          template.getSettingGenerationConfig().getStrategyName() != null) 
                                          ? template.getSettingGenerationConfig().getStrategyName() 
                                          : template.getName();
                    
                    // 1️⃣ 先创建session
                    return sessionManager.createSession(userId, novelId, enhancedPrompt, 
                                                      strategyName, promptTemplateId)
                        .flatMap(session -> {
                            // 设置会话元数据
                            session.setStatus(SettingGenerationSession.SessionStatus.GENERATING);
                            if (session.getMetadata() == null) {
                                session.setMetadata(new java.util.concurrent.ConcurrentHashMap<>());
                            }
                            session.getMetadata().put("knowledgeBaseMode", "HYBRID");
                            session.getMetadata().put("reuseKnowledgeBaseIds", reuseKnowledgeBaseIds);
                            if (referenceKnowledgeBaseIds != null && !referenceKnowledgeBaseIds.isEmpty()) {
                                session.getMetadata().put("referenceKnowledgeBaseIds", referenceKnowledgeBaseIds);
                            }
                            session.getMetadata().put("modelConfigId", modelConfigId);
                            session.getMetadata().put("mode", "STRUCTURED_OUTPUT");
                            session.getMetadata().put("maxIterations", iterations);
                            
                            // 2️⃣ 创建事件流sink（缓存所有事件）
                            Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                            eventSinks.put(session.getSessionId(), sink);
                            
                            // 3️⃣ 添加复用节点并发送事件
                            if (!reuseSettings.isEmpty()) {
                                log.info("[StructuredOutput-Hybrid] ✅ 添加 {} 个复用设定并推送到前端", 
                                    reuseSettings.size());
                                
                                List<SettingNode> reuseNodes = convertSettingsToNodes(reuseSettings);
                                for (SettingNode node : reuseNodes) {
                                    session.addNode(node);
                                    // 🎯 关键：发送NodeCreatedEvent到前端
                                    emitNodeCreatedEvent(session.getSessionId(), node, session);
                                }
                                
                                log.info("[StructuredOutput-Hybrid] ✅ 复用节点事件已推送，现在启动AI生成");
                            }
                            
                            // 4️⃣ 启动AI生成（异步）
                            return Mono.justOrEmpty(strategyFactory.createConfigurableStrategy(template))
                                .switchIfEmpty(Mono.error(new IllegalArgumentException("Cannot create strategy")))
                                .flatMap(strategyAdapter -> 
                                    novelAIService.getAIModelProviderByConfigId(userId, modelConfigId)
                                        .flatMap(provider -> {
                                            // 在后台异步执行生成
                                            executeStructuredOutputLoop(
                                                session, template, strategyAdapter, provider, iterations
                                            )
                                            .doOnError(error -> {
                                                log.error("[StructuredOutput-Hybrid] 生成失败: {}", error.getMessage(), error);
                                                emitErrorEvent(session.getSessionId(), "GENERATION_ERROR", 
                                                    error.getMessage(), null, false);
                                            })
                                            .subscribe();  // 后台异步执行
                                            
                                            // 5️⃣ 立即返回session，让Controller订阅事件流
                                            return Mono.just(session);
                                        })
                                );
                        });
                });
        }
        
        // 未知模式，降级为无知识库
        log.warn("[StructuredOutput] Unknown KB mode: {}, falling back to no KB", knowledgeBaseMode);
        return startGenerationStructuredInternal(sessionId, userId, novelId, initialPrompt, 
            promptTemplateId, modelConfigId, iterations);
    }
    
    /**
     * 内部方法：实际执行结构化输出生成
     */
    private Mono<SettingGenerationSession> startGenerationStructuredInternal(
            String sessionId,
            String userId,
            String novelId,
            String initialPrompt,
            String promptTemplateId,
            String modelConfigId,
            int iterations) {
        
        log.info("[StructuredOutput] 开始执行结构化输出生成: sessionId={}, userId={}, iterations={}", sessionId, userId, iterations);
        
        // 1. 获取模板和策略
        return promptTemplateRepository.findById(promptTemplateId)
            .switchIfEmpty(Mono.error(new IllegalArgumentException("Prompt template not found: " + promptTemplateId)))
            .flatMap(template -> {
                // 2. 创建策略适配器
                return Mono.justOrEmpty(strategyFactory.createConfigurableStrategy(template))
                    .switchIfEmpty(Mono.error(new IllegalArgumentException("Cannot create strategy from template: " + promptTemplateId)))
                    .flatMap(strategyAdapter -> {
                        // 3. 创建会话（使用前端提供的sessionId，如果有的话）
                        // 从settingGenerationConfig中获取策略名称，如果没有则使用模板名称
                        String strategyName = (template.getSettingGenerationConfig() != null && 
                                              template.getSettingGenerationConfig().getStrategyName() != null) 
                                              ? template.getSettingGenerationConfig().getStrategyName() 
                                              : template.getName();
                        return sessionManager.createSession(sessionId, userId, novelId, initialPrompt, 
                                                          strategyName, promptTemplateId)
                            .flatMap(session -> {
                                // 设置会话元数据
                                session.setStatus(SettingGenerationSession.SessionStatus.GENERATING);
                                if (session.getMetadata() == null) {
                                    session.setMetadata(new java.util.concurrent.ConcurrentHashMap<>());
                                }
                                session.getMetadata().put("modelConfigId", modelConfigId);
                                session.getMetadata().put("mode", "STRUCTURED_OUTPUT");
                                session.getMetadata().put("maxIterations", iterations);
                                
                                // 4. 创建事件流sink（必须在生成开始前创建，缓存所有事件）
                                Sinks.Many<SettingGenerationEvent> sink = Sinks.many().replay().all();
                                eventSinks.put(session.getSessionId(), sink);
                                
                                // 5. 获取AI模型提供商并在后台异步执行生成
                                novelAIService.getAIModelProviderByConfigId(userId, modelConfigId)
                                    .flatMap(provider -> {
                                        // 启动结构化输出循环（异步执行）
                                        return executeStructuredOutputLoop(
                                            session, 
                                            template, 
                                            strategyAdapter, 
                                            provider, 
                                            iterations
                                        );
                                    })
                                    .doOnError(error -> {
                                        log.error("[StructuredOutput] 生成失败: {}", error.getMessage(), error);
                                        emitErrorEvent(session.getSessionId(), "GENERATION_ERROR", 
                                            error.getMessage(), null, false);
                                    })
                                    .subscribe();  // 后台异步执行，不阻塞返回
                                
                                // 6. 立即返回session，让Controller订阅事件流
                                return Mono.just(session);
                            });
                    });
            });
    }
    
    /**
     * 执行结构化输出循环逻辑（多轮增量生成）
     * 每轮都基于前面轮次生成的节点继续扩展
     */
    private Mono<Void> executeStructuredOutputLoop(
            SettingGenerationSession session,
            com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
            ConfigurableStrategyAdapter strategyAdapter,
            com.ainovel.server.service.ai.AIModelProvider provider,
            int maxIterations) {
        
        log.info("[StructuredOutput] 开始多轮增量生成，共{}轮", maxIterations);
        
        return executeStructuredRound(
            session, template, strategyAdapter, provider, 
            1, maxIterations
        );
    }
    
    /**
     * 执行单轮结构化输出生成（增量模式）
     */
    private Mono<Void> executeStructuredRound(
            SettingGenerationSession session,
            com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
            ConfigurableStrategyAdapter strategyAdapter,
            com.ainovel.server.service.ai.AIModelProvider provider,
            int currentRound,
            int totalRounds) {
        
        log.info("[StructuredOutput] 📝 开始第 {}/{} 轮生成", currentRound, totalRounds);
        
        // 获取当前已生成的节点列表（用于下一轮参考）
        Map<String, SettingNode> existingNodes = session.getGeneratedNodes();
        int existingCount = existingNodes != null ? existingNodes.size() : 0;
        
        SettingGenerationEvent.GenerationProgressEvent progressEvent = new SettingGenerationEvent.GenerationProgressEvent();
        progressEvent.setMessage("第" + currentRound + "轮生成中（已有" + existingCount + "个节点）...");
        progressEvent.setTotalNodes(totalRounds);
        progressEvent.setCompletedNodes(currentRound - 1);
        progressEvent.setProgress((double)(currentRound - 1) / totalRounds);
        emitEvent(session.getSessionId(), progressEvent);
        
        // 1. 构建结构化输出请求（包含已有节点信息）
        return buildStructuredOutputRequest(session, template, strategyAdapter, currentRound, existingNodes)
            .flatMap(request -> {
                // 2. 调用AI生成JSON
                log.info("[StructuredOutput] 发起第{}轮AI请求: provider={}, model={}", 
                    currentRound, provider.getProviderName(), provider.getModelName());
                
                return provider.generateContent(request)
                    .flatMap(response -> {
                        String jsonContent = response.getContent();
                        log.debug("[StructuredOutput] 第{}轮收到响应，长度: {}", currentRound, jsonContent.length());
                        
                        try {
                            // 3. 解析JSON为节点列表
                            List<SettingNode> newNodes = parseJsonToNodes(jsonContent);
                            log.info("[StructuredOutput] ✅ 第{}轮解析出 {} 个新节点", currentRound, newNodes.size());
                            
                            // 4. 应用新节点到会话（不标记完成，因为可能还有后续轮次）
                            return applyNodesIncremental(session, newNodes, strategyAdapter)
                                .then(Mono.defer(() -> {
                                    // 5. 判断是否继续下一轮
                                    if (currentRound < totalRounds) {
                                        log.info("[StructuredOutput] 第{}轮完成，继续第{}轮", currentRound, currentRound + 1);
                                        // 递归执行下一轮
                                        return executeStructuredRound(
                                            session, template, strategyAdapter, provider,
                                            currentRound + 1, totalRounds
                                        );
                                    } else {
                                        // 所有轮次完成，标记会话完成
                                        log.info("[StructuredOutput] ✅ 所有{}轮生成完成", totalRounds);
                                        markGenerationComplete(session.getSessionId(), "Structured output completed");
                                        return Mono.empty();
                                    }
                                }));
                            
                        } catch (Exception e) {
                            // 解析JSON失败 - 跳过这一轮，尝试下一轮
                            log.error("[StructuredOutput] ❌ 第{}轮解析JSON失败: {}", currentRound, e.getMessage());
                            
                            if (currentRound < totalRounds) {
                                log.warn("[StructuredOutput] 跳过第{}轮，继续第{}轮", currentRound, currentRound + 1);
                                return executeStructuredRound(
                                    session, template, strategyAdapter, provider,
                                    currentRound + 1, totalRounds
                                );
                            } else {
                                // 最后一轮也失败了，但如果已有节点就标记完成
                                if (existingCount > 0) {
                                    log.warn("[StructuredOutput] 最后一轮失败，但已有{}个节点，标记完成", existingCount);
                                    markGenerationComplete(session.getSessionId(), "Partial structured output completed");
                                    return Mono.empty();
                                } else {
                                    String errorMsg = "结构化输出生成失败：所有轮次都解析失败 - " + e.getMessage();
                                    log.error("[StructuredOutput] {}", errorMsg);
                                    emitErrorEvent(session.getSessionId(), "PARSE_ERROR", errorMsg, null, false);
                                    return Mono.error(new RuntimeException(errorMsg));
                                }
                            }
                        }
                    });
            })
            .onErrorResume(error -> {
                log.error("[StructuredOutput] 第 {} 轮出错: {}", currentRound, error.getMessage());
                
                // 如果不是最后一轮，尝试继续
                if (currentRound < totalRounds && existingCount > 0) {
                    log.warn("[StructuredOutput] 第{}轮出错，但继续下一轮", currentRound);
                    return executeStructuredRound(
                        session, template, strategyAdapter, provider,
                        currentRound + 1, totalRounds
                    );
                }
                
                emitErrorEvent(session.getSessionId(), "GENERATION_ERROR", 
                    "第" + currentRound + "轮生成出错: " + error.getMessage(), null, false);
                return Mono.error(error);
            });
    }
    
    /**
     * 构建结构化输出请求（包含已有节点信息）
     */
    private Mono<com.ainovel.server.domain.model.AIRequest> buildStructuredOutputRequest(
            SettingGenerationSession session,
            com.ainovel.server.domain.model.EnhancedUserPromptTemplate template,
            ConfigurableStrategyAdapter strategyAdapter,
            int roundNumber,
            Map<String, SettingNode> existingNodes) {
        
        // 构建提示词上下文（复用现有逻辑）
        Map<String, Object> ctx = buildPromptContext(session, template, strategyAdapter);
        
        return promptProvider.getSystemPrompt(session.getUserId(), ctx)
            .zipWith(promptProvider.getUserPrompt(session.getUserId(), template.getId(), ctx))
            .map(prompts -> {
                String baseSystemPrompt = prompts.getT1();
                String baseUserPrompt = prompts.getT2();
                
                // 增强系统提示词：要求输出JSON而不是文本
                String structuredSystemPrompt = baseSystemPrompt + "\n\n" + buildStructuredOutputInstructions(roundNumber, existingNodes);
                
                // 构建消息列表
                java.util.List<com.ainovel.server.domain.model.AIRequest.Message> messages = new java.util.ArrayList<>();
                messages.add(com.ainovel.server.domain.model.AIRequest.Message.builder()
                    .role("system")
                    .content(structuredSystemPrompt)
                    .build());
                
                messages.add(com.ainovel.server.domain.model.AIRequest.Message.builder()
                    .role("user")
                    .content(baseUserPrompt)
                    .build());
                
                // 构建AI请求
                String modelConfigId = (String) session.getMetadata().get("modelConfigId");
                java.util.Map<String, Object> metadata = new java.util.HashMap<>();
                metadata.put("userId", session.getUserId());
                metadata.put("sessionId", session.getSessionId());
                metadata.put("requestType", com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION.name());
                metadata.put("modelConfigId", modelConfigId);
                metadata.put("roundNumber", roundNumber);
                
                // 🔧 为每一轮生成新的traceId，避免预扣费冲突
                String traceId = java.util.UUID.randomUUID().toString();
                log.debug("[StructuredOutput] 第{}轮生成新的traceId: {}", roundNumber, traceId);
                
                return com.ainovel.server.domain.model.AIRequest.builder()
                    .messages(messages)
                    .userId(session.getUserId())
                    .sessionId(session.getSessionId())
                    .traceId(traceId)
                    .featureType(com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                    .metadata(metadata)
                    .build();
            });
    }
    
    /**
     * 构建结构化输出指令（包含已有节点信息）
     * 
     * 🔧 过滤掉知识库复用的节点（fromKnowledgeBase=true），只展示AI生成的节点
     */
    private String buildStructuredOutputInstructions(int roundNumber, Map<String, SettingNode> existingNodes) {
        StringBuilder instructions = new StringBuilder();
        
        instructions.append("## 🔧 结构化输出模式 (第").append(roundNumber).append("轮)\n\n");
        instructions.append("**重要**：你必须直接输出一个**完整的JSON数组**，不要输出任何其他文字、解释或代码块标记。\n\n");
        
        // 如果有已生成的节点，提供完整信息作为参考
        if (existingNodes != null && !existingNodes.isEmpty()) {
            // 🎯 过滤掉知识库复用的节点，只保留AI生成的节点
            Map<String, SettingNode> aiGeneratedNodes = existingNodes.entrySet().stream()
                .filter(entry -> {
                    SettingNode node = entry.getValue();
                    // 检查是否为知识库复用节点
                    if (node.getAttributes() != null) {
                        Object fromKb = node.getAttributes().get("fromKnowledgeBase");
                        return !(fromKb != null && (Boolean.TRUE.equals(fromKb) || "true".equals(String.valueOf(fromKb))));
                    }
                    return true; // 没有标记的节点视为AI生成
                })
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
            
            // 如果过滤后没有AI生成的节点，说明这是第1轮，视为"首次AI生成"
            if (aiGeneratedNodes.isEmpty()) {
                log.info("[StructuredOutput] 第{}轮：所有{}个节点均为知识库复用，视为首次AI生成", 
                    roundNumber, existingNodes.size());
                instructions.append("## 本轮任务\n\n");
                instructions.append("这是第一轮AI生成，请生成基础的设定节点框架，包括若干根节点及其子节点。\n\n");
            } else {
                // 有AI生成的节点，展示它们作为参考
                instructions.append("## 📚 已有节点（完整信息）\n\n");
                instructions.append("当前已有 ").append(aiGeneratedNodes.size()).append(" 个AI生成的节点，请仔细阅读这些节点的内容，在本轮生成中继续扩展和深化：\n\n");
                
                // 按照根节点->子节点的层级顺序展示
                List<SettingNode> rootNodes = aiGeneratedNodes.values().stream()
                    .filter(n -> n.getParentId() == null || n.getParentId().isBlank())
                    .collect(Collectors.toList());
                
                List<SettingNode> childNodes = aiGeneratedNodes.values().stream()
                    .filter(n -> n.getParentId() != null && !n.getParentId().isBlank())
                    .collect(Collectors.toList());
                
                // 展示根节点
                instructions.append("### 根节点（").append(rootNodes.size()).append("个）\n\n");
                for (SettingNode node : rootNodes) {
                    appendNodeFullInfo(instructions, node, aiGeneratedNodes);
                }
                
                // 展示子节点
                if (!childNodes.isEmpty()) {
                    instructions.append("\n### 子节点（").append(childNodes.size()).append("个）\n\n");
                    for (SettingNode node : childNodes) {
                        appendNodeFullInfo(instructions, node, aiGeneratedNodes);
                    }
                }
                
                instructions.append("\n---\n\n");
                
                // 增量生成任务
                instructions.append("**本轮任务**：\n");
                instructions.append("1. 为现有节点添加更多子节点（特别是那些还没有子节点的）\n");
                instructions.append("2. 为现有子节点添加孙节点，增加层级深度\n");
                instructions.append("3. 扩展现有节点的横向内容（同级的新节点）\n");
                instructions.append("4. 确保新生成的内容与已有节点保持一致性和连贯性\n");
                instructions.append("5. 新节点的tempId要在已有节点的tempId基础上编号（如已有R1-1，新增R1-2、R1-3等）\n\n");
            }
        } else {
            // 没有任何节点（包括复用的），这是真正的第一轮
            instructions.append("## 本轮任务\n\n");
            instructions.append("这是第一轮生成，请生成基础的设定节点框架，包括若干根节点及其子节点。\n\n");
        }
        
        instructions.append("\n");
        
        instructions.append("## JSON格式要求\n\n");
        instructions.append("```json\n");
        instructions.append("[\n");
        instructions.append("  {\n");
        instructions.append("    \"tempId\": \"R1\",\n");
        instructions.append("    \"name\": \"节点名称\",\n");
        instructions.append("    \"type\": \"CHARACTER\",\n");
        instructions.append("    \"description\": \"详细描述（至少50字，包含具体细节）\",\n");
        instructions.append("    \"parentId\": null,\n");
        instructions.append("    \"attributes\": {}\n");
        instructions.append("  },\n");
        instructions.append("  {\n");
        instructions.append("    \"tempId\": \"R1-1\",\n");
        instructions.append("    \"name\": \"子节点名称\",\n");
        instructions.append("    \"type\": \"CONCEPT\",\n");
        instructions.append("    \"description\": \"子节点详细描述...\",\n");
        instructions.append("    \"parentId\": \"R1\",\n");
        instructions.append("    \"attributes\": {}\n");
        instructions.append("  }\n");
        instructions.append("]\n");
        instructions.append("```\n\n");
        
        instructions.append("## ⚠️ 字段说明（必须严格遵守）\n\n");
        instructions.append("- **tempId**: 【必填】临时ID，用于父子引用（如 R1, R1-1, R1-2, R2, R2-1）\n");
        instructions.append("  - ⚠️ **每个节点都必须有tempId，包括根节点！**\n");
        instructions.append("  - 格式：根节点用R1、R2、R3...，子节点用R1-1、R1-2、R2-1...，孙节点用R1-1-1...\n");
        instructions.append("- **name**: 节点名称（不能包含'/'字符，如需斜杠请使用全角'／'）\n");
        instructions.append("- **type**: 节点类型，必须从以下枚举中选择：\n");
        instructions.append("  CHARACTER, LOCATION, ITEM, LORE, FACTION, EVENT, CONCEPT, WORLDVIEW, \n");
        instructions.append("  POWER_SYSTEM, GOLDEN_FINGER, TIMELINE, CREATURE, MAGIC_SYSTEM, TECHNOLOGY,\n");
        instructions.append("  CULTURE, HISTORY, ORGANIZATION, PLEASURE_POINT, ANTICIPATION_HOOK, \n");
        instructions.append("  THEME, TONE, STYLE, TROPE, PLOT_DEVICE, RELIGION, POLITICS, ECONOMY, GEOGRAPHY, OTHER\n");
        instructions.append("- **description**: 节点详细描述（至少100字，包含具体细节和特色）\n");
        instructions.append("- **parentId**: 父节点的tempId，根节点必须为null\n");
        instructions.append("- **attributes**: 附加属性（可选，如 {\"age\": \"25\", \"power\": \"high\"}）\n\n");
        
        instructions.append("## 质量要求（必须满足）\n\n");
        instructions.append("1. **节点数量**：至少生成15个节点\n");
        instructions.append("2. **层级深度**：至少3层（根节点→二级节点→三级节点）\n");
        instructions.append("3. **根节点数量**：2-5个根节点\n");
        instructions.append("4. **父子完整性**：所有非根节点的parentId必须指向已存在的节点tempId\n");
        instructions.append("5. **描述质量**：每个节点描述至少50字，包含具体细节和特色\n");
        instructions.append("6. **类型多样性**：尽量使用多种不同的节点类型\n");
        instructions.append("7. **层级设计**：先创建用户期待深度的根节点，再创建其子节点，而不是先创建完所有父节点才创建相关子节点。\n");
        instructions.append("   例如：用户期待深度为3，则应创建1个根节点→3个二级子节点→9个三级子节点，而不是先创建所有根节点\n\n");
        
        instructions.append("## 输出要求（必须100%遵守）\n\n");
        instructions.append("- **只输出纯JSON数组**，不要任何解释文字\n");
        instructions.append("- 确保JSON格式完全正确，可被直接解析\n");
        instructions.append("- ⚠️ **每个节点必须包含tempId字段，一个都不能少！**\n");
        instructions.append("- ⚠️ **所有节点的parentId必须指向已存在节点的tempId**\n");
        instructions.append("- 先创建根节点，再创建子节点，保持父子关系清晰\n");
        instructions.append("- 描述要具体生动，避免空洞套话\n");
        instructions.append("- 节点名称要简洁明了，描述要详细充实\n");
        
        return instructions.toString();
    }
    
    /**
     * 格式化节点完整信息（用于提示词）
     */
    private void appendNodeFullInfo(StringBuilder sb, SettingNode node, Map<String, SettingNode> allNodes) {
        // 获取tempId
        String tempId = "未知";
        if (node.getAttributes() != null && node.getAttributes().containsKey("tempId")) {
            tempId = String.valueOf(node.getAttributes().get("tempId"));
        }
        
        // 获取父节点信息
        String parentInfo = "null";
        if (node.getParentId() != null && !node.getParentId().isBlank()) {
            SettingNode parent = allNodes.get(node.getParentId());
            if (parent != null) {
                String parentTempId = parent.getAttributes() != null ? 
                    String.valueOf(parent.getAttributes().getOrDefault("tempId", node.getParentId())) : 
                    node.getParentId();
                parentInfo = parentTempId + " [" + parent.getName() + "]";
            } else {
                parentInfo = node.getParentId();
            }
        }
        
        // 格式化输出
        sb.append("**节点 ").append(tempId).append("：").append(node.getName()).append("**\n");
        sb.append("- 类型：").append(node.getType()).append("\n");
        sb.append("- 父节点：").append(parentInfo).append("\n");
        sb.append("- 描述：").append(node.getDescription() != null ? node.getDescription() : "无").append("\n");
        
        // 如果有attributes中的额外信息，也显示出来
        if (node.getAttributes() != null && !node.getAttributes().isEmpty()) {
            StringBuilder attrs = new StringBuilder();
            for (Map.Entry<String, Object> entry : node.getAttributes().entrySet()) {
                if (!"tempId".equals(entry.getKey()) && entry.getValue() != null) {
                    attrs.append(entry.getKey()).append("=").append(entry.getValue()).append("; ");
                }
            }
            if (attrs.length() > 0) {
                sb.append("- 额外属性：").append(attrs.toString().trim()).append("\n");
            }
        }
        
        sb.append("\n");
    }
    
    /**
     * 解析JSON字符串为节点列表
     */
    private List<SettingNode> parseJsonToNodes(String jsonContent) throws Exception {
        // 提取JSON（可能包含在代码块中）
        String extractedJson = extractJsonFromResponse(jsonContent);
        
        // 解析为Map列表
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> nodeDataList = objectMapper.readValue(
            extractedJson, 
            objectMapper.getTypeFactory().constructCollectionType(List.class, Map.class)
        );
        
        // 🔍 调试：打印解析出的节点数据
        log.debug("[StructuredOutput] 解析出的节点原始数据：");
        for (int i = 0; i < nodeDataList.size(); i++) {
            Map<String, Object> data = nodeDataList.get(i);
            log.debug("  [{}] tempId={}, name={}, parentId={}", 
                i, data.get("tempId"), data.get("name"), data.get("parentId"));
        }
        
        // 转换为SettingNode对象
        List<SettingNode> nodes = new ArrayList<>();
        for (Map<String, Object> nodeData : nodeDataList) {
            SettingNode node = convertMapToSettingNode(nodeData);
            nodes.add(node);
        }
        
        return nodes;
    }
    
    /**
     * 从响应中提取JSON
     */
    private String extractJsonFromResponse(String response) {
        if (response == null || response.trim().isEmpty()) {
            throw new IllegalArgumentException("响应内容为空");
        }
        
        String trimmed = response.trim();
        
        // 移除可能的代码块标记
        if (trimmed.startsWith("```json")) {
            trimmed = trimmed.substring(7);
        } else if (trimmed.startsWith("```")) {
            trimmed = trimmed.substring(3);
        }
        
        if (trimmed.endsWith("```")) {
            trimmed = trimmed.substring(0, trimmed.length() - 3);
        }
        
        trimmed = trimmed.trim();
        
        // 查找JSON数组的开始和结束
        int start = trimmed.indexOf('[');
        int end = trimmed.lastIndexOf(']');
        
        if (start == -1 || end == -1 || start >= end) {
            throw new IllegalArgumentException("未找到有效的JSON数组");
        }
        
        return trimmed.substring(start, end + 1);
    }
    
    /**
     * 将Map转换为SettingNode对象
     */
    private SettingNode convertMapToSettingNode(Map<String, Object> data) {
        SettingNode node = new SettingNode();
        node.setId(java.util.UUID.randomUUID().toString());
        
        // 初始化attributes
        Map<String, Object> attrs = new HashMap<>();
        if (data.containsKey("attributes") && data.get("attributes") instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> existingAttrs = (Map<String, Object>) data.get("attributes");
            attrs.putAll(existingAttrs);
        }
        
        // 将tempId存储在attributes中
        if (data.containsKey("tempId")) {
            attrs.put("tempId", String.valueOf(data.get("tempId")));
        }
        
        node.setAttributes(attrs);
        
        if (data.containsKey("name")) {
            node.setName(String.valueOf(data.get("name")));
        }
        
        if (data.containsKey("type")) {
            String typeStr = String.valueOf(data.get("type"));
            try {
                node.setType(SettingType.valueOf(typeStr));
            } catch (IllegalArgumentException e) {
                log.warn("未知的节点类型: {}, 使用OTHER", typeStr);
                node.setType(SettingType.OTHER);
            }
        }
        
        if (data.containsKey("description")) {
            node.setDescription(String.valueOf(data.get("description")));
        }
        
        if (data.containsKey("parentId") && data.get("parentId") != null) {
            String parentId = String.valueOf(data.get("parentId"));
            if (!"null".equals(parentId)) {
                node.setParentId(parentId);
            }
        }
        
        node.setChildren(new ArrayList<>());
        node.setGenerationStatus(SettingNode.GenerationStatus.COMPLETED);
        
        return node;
    }
    
    /**
     * 增量应用节点（不标记完成，用于多轮生成）
     */
    private Mono<Void> applyNodesIncremental(
            SettingGenerationSession session,
            List<SettingNode> nodes,
            ConfigurableStrategyAdapter strategyAdapter) {
        
        log.info("[StructuredOutput] 增量应用 {} 个节点到会话", nodes.size());
        
        return applyNodesToSession(session, nodes, strategyAdapter);
    }
    
    /**
     * 应用节点并标记完成（用于单轮生成或最后一轮）
     */
    private Mono<Void> applyNodesAndComplete(
            SettingGenerationSession session,
            List<SettingNode> nodes,
            ConfigurableStrategyAdapter strategyAdapter) {
        
        log.info("[StructuredOutput] 应用 {} 个节点到会话并标记完成", nodes.size());
        
        return applyNodesToSession(session, nodes, strategyAdapter)
            .then(Mono.fromRunnable(() -> {
                // 标记会话完成
                markGenerationComplete(session.getSessionId(), "Structured output completed");
                log.info("[StructuredOutput] ✅ 结构化输出生成完成");
            }));
    }
    
    /**
     * 核心方法：应用节点到会话
     */
    private Mono<Void> applyNodesToSession(
            SettingGenerationSession session,
            List<SettingNode> nodes,
            ConfigurableStrategyAdapter strategyAdapter) {
        
        log.info("[StructuredOutput] 开始应用 {} 个节点", nodes.size());
        
        // 获取或创建跨轮次的tempId映射表（累积所有轮次的映射）
        @SuppressWarnings("unchecked")
        Map<String, String> globalTempIdMap = (Map<String, String>) session.getMetadata().get("tempIdMap");
        if (globalTempIdMap == null) {
            globalTempIdMap = new java.util.concurrent.ConcurrentHashMap<>();
            session.getMetadata().put("tempIdMap", globalTempIdMap);
        }
        
        // 将当前批次的新节点tempId添加到全局映射表
        for (SettingNode node : nodes) {
            Object tempIdObj = node.getAttributes() != null ? node.getAttributes().get("tempId") : null;
            if (tempIdObj != null) {
                String tempId = String.valueOf(tempIdObj);
                if (!tempId.isBlank()) {
                    globalTempIdMap.put(tempId, node.getId());
                    log.debug("[StructuredOutput] 注册tempId映射: {} -> {}", tempId, node.getId());
                }
            }
        }
        
        log.info("[StructuredOutput] 当前全局tempId映射表大小: {}", globalTempIdMap.size());
        
        // 解析parentId（支持跨轮次的tempId引用）
        for (SettingNode node : nodes) {
            if (node.getParentId() != null && !node.getParentId().isBlank()) {
                String originalParentId = node.getParentId();
                // 如果parentId是tempId，转换为真实ID
                String realParentId = globalTempIdMap.get(originalParentId);
                if (realParentId != null) {
                    log.debug("[StructuredOutput] 转换parentId: {} -> {}", originalParentId, realParentId);
                    node.setParentId(realParentId);
                } else {
                    log.warn("[StructuredOutput] ⚠️ 找不到tempId映射: {}，可用映射: {}", 
                        originalParentId, globalTempIdMap.keySet());
                }
            }
        }
        
        // 添加所有节点到会话
        return Flux.fromIterable(nodes)
            .flatMap(node -> sessionManager.addNodeToSession(session.getSessionId(), node)
                .doOnNext(s -> {
                    // 发送节点创建事件
                    emitNodeCreatedEvent(session.getSessionId(), node, session);
                    log.debug("[StructuredOutput] 节点已添加: {}", node.getName());
                })
            )
            .then();
    }
    
    // ==================== 积分奖励辅助方法 ====================
    
    /**
     * 处理策略使用时的积分奖励
     * 1. 增加模板的usageCount
     * 2. 给模板作者增加1积分（自己使用自己的策略不获得积分）
     * 
     * @param promptTemplateId 策略模板ID
     * @param currentUserId 当前使用策略的用户ID
     * @return 处理结果的Mono
     */
    private Mono<Void> handleStrategyUsageReward(String promptTemplateId, String currentUserId) {
        if (promptTemplateId == null || currentUserId == null) {
            return Mono.empty();
        }
        
        return promptTemplateRepository.findById(promptTemplateId)
            .flatMap(template -> {
                // 增加使用次数
                template.incrementUsageCount();
                
                // 保存模板更新
                return promptTemplateRepository.save(template)
                    .flatMap(savedTemplate -> {
                        // 检查作者是否是当前用户
                        String authorId = savedTemplate.getAuthorId();
                        if (authorId == null || authorId.equals(currentUserId)) {
                            // 自己使用自己的策略不获得积分
                            log.debug("策略使用：自己使用自己的策略，不增加积分。模板ID: {}, 用户ID: {}", 
                                    promptTemplateId, currentUserId);
                            return Mono.empty();
                        }
                        
                        // 给作者增加积分
                        return creditService.addCredits(authorId, 1L, "策略被使用奖励 - 模板: " + savedTemplate.getName())
                            .doOnSuccess(success -> {
                                if (Boolean.TRUE.equals(success)) {
                                    log.info("✅ 策略使用积分奖励成功：作者ID: {}, 模板ID: {}, 模板名称: {}, 当前使用次数: {}", 
                                            authorId, promptTemplateId, savedTemplate.getName(), savedTemplate.getUsageCount());
                                } else {
                                    log.warn("⚠️ 策略使用积分奖励失败：作者ID: {}, 模板ID: {}", authorId, promptTemplateId);
                                }
                            })
                            .then();
                    });
            })
            .onErrorResume(error -> {
                // 即使积分奖励失败，也不影响主流程
                log.error("❌ 处理策略使用积分奖励时发生错误: templateId={}, userId={}, error={}", 
                        promptTemplateId, currentUserId, error.getMessage(), error);
                return Mono.empty();
            });
    }
}