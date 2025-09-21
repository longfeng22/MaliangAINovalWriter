package com.ainovel.server.controller;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.common.security.CurrentUser;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.domain.model.setting.generation.SettingGenerationEvent;
import com.ainovel.server.domain.model.settinggeneration.NodeTemplateConfig;
import com.ainovel.server.service.setting.generation.ISettingGenerationService;
import com.ainovel.server.service.setting.generation.StrategyManagementService;
import com.ainovel.server.service.setting.NovelSettingHistoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

// import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 设定生成控制器
 * 提供AI驱动的结构化小说设定生成API
 * 
 * 设定生成与历史记录关系说明：
 * 1. 设定历史记录与小说无关，与用户有关 - 历史记录是按用户维度管理的
 * 2. 小说与历史记录的关系：
 *    a) 当用户进入小说设定生成页面时，如果没有历史记录，会创建一个历史记录，收集当前小说的设定作为快照
 *    b) 用户从小说列表页面发起提示词生成设定请求，生成完后会自动生成一个历史记录
 * 3. 历史记录相当于小说设定的快照，供用户修改和版本管理
 * 4. 设定生成流程：
 *    - 用户输入提示词 -> AI生成设定结构 -> 用户可修改节点 -> 保存到小说设定 -> 自动创建历史记录
 * 5. 编辑现有设定流程：
 *    - 从历史记录创建编辑会话 -> 修改设定节点 -> 保存修改 -> 更新历史记录或创建新历史记录
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/setting-generation")
@RequiredArgsConstructor
@Tag(name = "设定生成", description = "AI驱动的结构化小说设定生成")
public class SettingGenerationController {
    
    private final ISettingGenerationService settingGenerationService;
    private final NovelSettingHistoryService historyService;
    private final StrategyManagementService strategyManagementService;
    private final com.ainovel.server.service.setting.generation.SystemStrategyInitializationService systemStrategyInitializationService;
    private final com.ainovel.server.service.NovelService novelService;
    private final com.ainovel.server.service.setting.generation.InMemorySessionManager sessionManager;
    private final com.ainovel.server.service.setting.SettingComposeService settingComposeService;
    
    /**
     * 获取可用的生成策略模板
     */
    @GetMapping("/strategies")
    @Operation(summary = "获取可用的生成策略模板", description = "返回所有支持的设定生成策略模板列表")
    public Mono<ApiResponse<List<ISettingGenerationService.StrategyTemplateInfo>>> getAvailableStrategyTemplates(
            @CurrentUser com.ainovel.server.domain.model.User user) {
        Mono<List<ISettingGenerationService.StrategyTemplateInfo>> mono =
            (user != null && user.getId() != null)
                ? ((com.ainovel.server.service.setting.generation.SettingGenerationService)settingGenerationService).getAvailableStrategyTemplatesForUser(user.getId())
                : settingGenerationService.getAvailableStrategyTemplates();
        return mono.map(ApiResponse::success)
            .onErrorResume(error -> {
                log.error("Failed to get available strategy templates", error);
                return Mono.just(ApiResponse.error("GET_STRATEGIES_FAILED", error.getMessage()));
            });
    }
    
    /**
     * 启动设定生成
     * 用户从小说列表页面发起提示词生成设定请求时调用
     */
    @PostMapping(value = "/start", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @Operation(summary = "启动设定生成", 
        description = "根据用户提示词和选定策略开始生成设定，返回SSE事件流。生成完成后会自动创建历史记录")
    public Flux<ServerSentEvent<SettingGenerationEvent>> startGeneration(
            @Valid @RequestBody StartGenerationRequest request) {
        
        // 使用请求中的userId，如果没有提供则使用默认值
        String userId = request.getUserId() != null ? request.getUserId() : "67d67d6833335f5166782e6f";
        
        // 兼容性处理：如果提供了strategy而没有promptTemplateId，则转换
        Mono<String> promptTemplateIdMono;
        if (request.getPromptTemplateId() != null && !request.getPromptTemplateId().trim().isEmpty()) {
            promptTemplateIdMono = Mono.just(request.getPromptTemplateId());
        } else if (request.getStrategy() != null && !request.getStrategy().trim().isEmpty()) {
            log.warn("使用已废弃的strategy参数: {}, 建议使用promptTemplateId", request.getStrategy());
            // 通过SystemStrategyInitializationService查找对应的模板ID
            promptTemplateIdMono = systemStrategyInitializationService.getTemplateIdByStrategyId(request.getStrategy())
                .doOnNext(templateId -> log.info("策略 {} 转换为模板ID: {}", request.getStrategy(), templateId));
        } else {
            return Flux.just(ServerSentEvent.<SettingGenerationEvent>builder()
                .event("GenerationErrorEvent")
                .data(new SettingGenerationEvent.GenerationErrorEvent() {{
                    setErrorCode("INVALID_REQUEST");
                    setErrorMessage("必须提供promptTemplateId或strategy参数");
                    setRecoverable(false);
                }})
                .build());
        }
        
        // 创建会话并获取事件流（切换到“新流程：Hybrid”）
        return promptTemplateIdMono.flatMapMany(promptTemplateId -> {
            log.info("[新流程][HYBRID] 启动设定生成: 用户={}, 模板ID={}, 模型配置ID={}, 小说ID={}",
                userId, promptTemplateId, request.getModelConfigId(), request.getNovelId());

            // 使用混合流程：文本阶段 + 工具直通（服务端自行管理 textEndSentinel）
            return settingGenerationService.startGenerationHybrid(
                    userId,
                    request.getNovelId(),
                    request.getInitialPrompt(),
                    promptTemplateId,
                    request.getModelConfigId(),
                    null,
                    request.getUsePublicTextModel()
                )
                .flatMapMany(session -> {
                    // 返回事件流（在完成/不可恢复错误时自动结束SSE）
                    return settingGenerationService.getGenerationEventStream(session.getSessionId())
                        // 过滤掉可恢复错误，不让前端看到 GENERATION_ERROR（recoverable=true）
                        .filter(event -> {
                            if (event instanceof com.ainovel.server.domain.model.setting.generation.SettingGenerationEvent.GenerationErrorEvent err) {
                                Boolean recoverable = err.getRecoverable();
                                return recoverable == null || !recoverable;
                            }
                            return true;
                        })
                        .doOnSubscribe(s -> log.info("客户端已订阅设定生成事件: {}", session.getSessionId()))
                        .doOnError(error -> log.error("设定生成事件流出错: sessionId={}", session.getSessionId(), error))
                        .doFinally(signal -> log.info("SSE连接关闭: sessionId={}, signal={}", session.getSessionId(), signal))
                        .map(event -> ServerSentEvent.<SettingGenerationEvent>builder()
                            .id(String.valueOf(System.currentTimeMillis()))
                            .event(event.getClass().getSimpleName())
                            .data(event)
                            .build()
                        );
                });
        })
        .onErrorResume(error -> {
            log.error("启动设定生成失败", error);
            // 发送错误事件
            SettingGenerationEvent.GenerationErrorEvent errorEvent = 
                new SettingGenerationEvent.GenerationErrorEvent();
            errorEvent.setErrorCode("START_FAILED");
            errorEvent.setErrorMessage(error.getMessage());
            errorEvent.setRecoverable(false);
            // 补全必要字段，避免前端解析失败
            try {
                errorEvent.setSessionId("session-error-" + System.currentTimeMillis());
                errorEvent.setTimestamp(java.time.LocalDateTime.now());
            } catch (Exception ignore) {}
            
            // 显式发送complete事件（标准负载），确保前端SSE客户端立即关闭连接
            @SuppressWarnings({"rawtypes","unchecked"})
            ServerSentEvent<SettingGenerationEvent> completeSse = (ServerSentEvent<SettingGenerationEvent>)(ServerSentEvent) ServerSentEvent.builder()
                .event("complete")
                .data(java.util.Map.of("data", "[DONE]"))
                .build();

            return Flux.just(
                ServerSentEvent.<SettingGenerationEvent>builder()
                    .event("GenerationErrorEvent")
                    .data(errorEvent)
                    .build(),
                completeSse
            );
        });
    }
    
    /**
     * 从小说设定创建编辑会话
     * 当用户进入小说设定生成页面时调用，支持用户选择编辑模式
     */
    @PostMapping("/novel/{novelId}/edit-session")
    @Operation(summary = "从小说设定创建编辑会话", 
        description = "基于小说现有设定创建编辑会话，支持用户选择创建新快照或编辑上次设定")
    public Mono<ApiResponse<EditSessionResponse>> createEditSessionFromNovel(
            @CurrentUser User user,
            @Parameter(description = "小说ID") @PathVariable String novelId,
            @Valid @RequestBody CreateNovelEditSessionRequest request) {
        
        log.info("Creating edit session from novel {} for user {} with editReason: {} createNewSnapshot: {}", 
            novelId, user.getId(), request.getEditReason(), request.isCreateNewSnapshot());
        
        return settingGenerationService.startSessionFromNovel(
                novelId, 
                user.getId(),
                request.getEditReason(), 
                request.getModelConfigId(),
                request.isCreateNewSnapshot()
            )
            .map(session -> {
                EditSessionResponse response = new EditSessionResponse();
                response.setSessionId(session.getSessionId());
                response.setMessage("编辑会话创建成功");
                response.setHasExistingHistory(session.isFromExistingHistory());
                response.setSnapshotMode((String) session.getMetadata().get("snapshotMode"));
                return ApiResponse.<EditSessionResponse>success(response);
            })
            .onErrorResume(error -> {
                log.error("Failed to create edit session from novel", error);
                return Mono.just(ApiResponse.<EditSessionResponse>error("SESSION_CREATE_FAILED", error.getMessage()));
            });
    }
    
    /**
     * AI修改设定节点
     */
    @PostMapping(value = "/{sessionId}/update-node", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @Operation(summary = "修改设定节点", 
        description = "修改指定的设定节点及其子节点，返回SSE事件流显示修改过程")
    public Flux<ServerSentEvent<SettingGenerationEvent>> updateNode(
            @CurrentUser User user,
            @Parameter(description = "会话ID") @PathVariable String sessionId,
            @Valid @RequestBody UpdateNodeRequest request) {
        
        log.info("Updating node {} in session {} for user {} with modelConfigId {}, isPublicModel={}, publicModelConfigId={}", 
            request.getNodeId(), sessionId, user.getId(), request.getModelConfigId(), request.getPublicModel(), request.getPublicModelConfigId());
        
        // 周期性心跳，避免长时间无事件导致 HTTP/2 中间层（如 CDN/浏览器）断开连接
        @SuppressWarnings({"rawtypes","unchecked"})
        ServerSentEvent<SettingGenerationEvent> keepAliveSse = (ServerSentEvent<SettingGenerationEvent>)(ServerSentEvent) ServerSentEvent.builder()
            .comment("keepalive")
            .build();
        // 标准 complete 事件，供前端及时收尾（事件名=complete，数据负载与OpenAI风格一致）
        @SuppressWarnings({"rawtypes","unchecked"})
        ServerSentEvent<SettingGenerationEvent> completeSse = (ServerSentEvent<SettingGenerationEvent>)(ServerSentEvent) ServerSentEvent.builder()
            .event("complete")
            .data(java.util.Map.of("data", "[DONE]"))
            .build();

        // 先获取事件流，然后启动修改操作（仅启动一次），并对流进行共享，避免多处订阅导致重复启动
        final AtomicBoolean started = new AtomicBoolean(false);
        Flux<ServerSentEvent<SettingGenerationEvent>> eventSseFlux = settingGenerationService.getModificationEventStream(sessionId)
            // 与 start 接口对齐：屏蔽可恢复错误（recoverable=true）的 GENERATION_ERROR 事件
            .filter(event -> {
                if (event instanceof SettingGenerationEvent.GenerationErrorEvent err) {
                    Boolean recoverable = err.getRecoverable();
                    return recoverable == null || !recoverable;
                }
                return true;
            })
            .doOnSubscribe(subscription -> {
                if (started.compareAndSet(false, true)) {
                    settingGenerationService.modifyNode(
                        sessionId,
                        request.getNodeId(),
                        request.getModificationPrompt(),
                        request.getModelConfigId(),
                        request.getScope() == null ? "self" : request.getScope(),
                        request.getPublicModel(),
                        request.getPublicModelConfigId()
                    ).subscribe(
                        result -> log.info("Node modification completed for session: {}", sessionId),
                        error -> log.error("Node modification failed for session: {}", sessionId, error)
                    );
                } else {
                    log.debug("update-node stream already started for session: {}", sessionId);
                }
            })
            .takeUntil(event -> {
                if (event instanceof SettingGenerationEvent.GenerationCompletedEvent) {
                    return true; // 修改流程完成，结束流
                }
                if (event instanceof SettingGenerationEvent.GenerationErrorEvent err) {
                    return err.getRecoverable() != null && !err.getRecoverable(); // 不可恢复错误，结束流
                }
                return false;
            })
            .map(event -> ServerSentEvent.<SettingGenerationEvent>builder()
                .id(String.valueOf(System.currentTimeMillis()))
                .event(event.getClass().getSimpleName())
                .data(event)
                .build()
            )
            // 共享上游订阅，避免 heartbeat 与主流各自订阅导致重复启动
            .publish()
            .refCount(1)
            .onErrorResume(error -> {
                log.error("Failed to update node", error);
                SettingGenerationEvent.GenerationErrorEvent errorEvent = 
                    new SettingGenerationEvent.GenerationErrorEvent();
                errorEvent.setSessionId(sessionId);
                errorEvent.setErrorCode("UPDATE_FAILED");
                errorEvent.setErrorMessage(error.getMessage());
                errorEvent.setNodeId(request.getNodeId());
                errorEvent.setRecoverable(false);
                ServerSentEvent<SettingGenerationEvent> errorSse = ServerSentEvent.<SettingGenerationEvent>builder()
                    .event("GenerationErrorEvent")
                    .data(errorEvent)
                    .build();
                // 错误时也返回 complete，确保前端及时收尾
                return Flux.just(errorSse, completeSse);
            });

        // 15s 心跳流（仅注释行，不携带数据），跟随事件流完成
        Flux<ServerSentEvent<SettingGenerationEvent>> heartbeatFlux = Flux
            .interval(java.time.Duration.ofSeconds(15))
            .map(tick -> keepAliveSse)
            // 事件流完成（正常完成或错误）时，心跳自动结束
            .takeUntilOther(eventSseFlux.ignoreElements().then(Mono.just("stop")));

        // 合并实际事件与心跳，并在业务完成后显式拼接 complete
        return Flux.merge(eventSseFlux, heartbeatFlux)
            .concatWith(Mono.just(completeSse));
    }
    
    /**
     * 直接更新节点内容
     */
    @PostMapping("/{sessionId}/update-content")
    @Operation(summary = "直接更新节点内容", 
        description = "直接更新指定节点的内容，不通过AI重新生成")
    public Mono<ApiResponse<String>> updateNodeContent(
            @CurrentUser User user,
            @Parameter(description = "会话ID") @PathVariable String sessionId,
            @Valid @RequestBody UpdateNodeContentRequest request) {
        
        log.info("Updating node content {} in session {} for user {}", 
            request.getNodeId(), sessionId, user.getId());
        
        return settingGenerationService.updateNodeContent(
                sessionId, 
                request.getNodeId(), 
                request.getNewContent()
            )
            .then(Mono.just(ApiResponse.success("节点内容已更新")))
            .onErrorResume(error -> {
                log.error("Failed to update node content", error);
                return Mono.just(ApiResponse.error("UPDATE_CONTENT_FAILED", "更新节点内容失败: " + error.getMessage()));
            });
    }
    
    /**
     * 保存生成的设定
     * 保存完成后会自动创建历史记录
     */
    @PostMapping("/{sessionId}/save")
    @Operation(summary = "保存生成的设定", 
        description = "将会话中的设定保存到数据库，并自动创建历史记录快照")
    public Mono<ApiResponse<SaveSettingResponse>> saveGeneratedSettings(
            @RequestHeader(value = "X-User-Id", required = false) String userId,
            @Parameter(description = "会话ID") @PathVariable String sessionId,
            @Valid @RequestBody SaveSettingsRequest request) {

        // 🔧 修复：为开发环境提供默认用户ID
        final String finalUserId = (userId == null || userId.trim().isEmpty()) 
            ? "67d67d6833335f5166782e6f" // 默认测试用户ID
            : userId;
        
        if (userId == null || userId.trim().isEmpty()) {
            log.warn("使用默认用户ID进行保存操作: {}", finalUserId);
        }

        log.info("Saving generated settings for session {} to novel {} by user {}, updateExisting: {}, targetHistoryId: {}", 
                sessionId, request.getNovelId(), finalUserId, request.getUpdateExisting(), request.getTargetHistoryId());

        // 根据请求参数调用相应的保存方法
        boolean updateExisting = Boolean.TRUE.equals(request.getUpdateExisting());
        String targetHistoryId = updateExisting ? request.getTargetHistoryId() : null;
        
        // 如果是更新现有历史记录但没有提供targetHistoryId，则使用sessionId作为默认值
        if (updateExisting && (targetHistoryId == null || targetHistoryId.trim().isEmpty())) {
            targetHistoryId = sessionId;
            log.info("使用sessionId作为默认的targetHistoryId: {}", targetHistoryId);
        }

        return settingGenerationService.saveGeneratedSettings(sessionId, request.getNovelId(), updateExisting, targetHistoryId)
            .map(saveRes -> {
                // Service 已自动创建历史记录，这里仅构造响应
                SaveSettingResponse response = new SaveSettingResponse();
                response.setSuccess(true);
                response.setMessage("设定已成功保存，并已创建历史记录");
                response.setRootSettingIds(saveRes.getRootSettingIds());
                response.setHistoryId(saveRes.getHistoryId());
                return ApiResponse.success(response);
            })
            .onErrorResume(error -> {
                log.error("Failed to save settings", error);
                SaveSettingResponse response = new SaveSettingResponse();
                response.setSuccess(false);
                response.setMessage("保存失败: " + error.getMessage());
                return Mono.just(ApiResponse.error("SAVE_FAILED", error.getMessage()));
            });
    }

    /**
     * 基于会话整体调整生成
     * 使用已存在会话中的设定树与初始提示词进行整体调整，返回生成过程的SSE事件流
     */
    @PostMapping(value = "/{sessionId}/adjust", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @Operation(summary = "整体调整生成",
        description = "在不破坏现有层级与关联关系的前提下，基于当前会话进行整体调整生成，返回SSE事件流")
    public Flux<ServerSentEvent<SettingGenerationEvent>> adjustSession(
            @CurrentUser User user,
            @Parameter(description = "会话ID") @PathVariable String sessionId,
            @Valid @RequestBody AdjustSessionRequest request) {

        log.info("Adjusting session {} for user {} with modelConfigId {}", sessionId, user.getId(), request.getModelConfigId());

        // 提示词增强：明确保持层级/关联结构，避免UUID等无意义ID
        final String enhancedPrompt =
                "请在不破坏现有层级结构与父子关联关系的前提下，对设定进行整体调整。" +
                "保留节点的层级与引用关系（使用名称/路径表达），避免包含任何UUID或无意义的内部ID。" +
                "\n调整说明：\n" + request.getAdjustmentPrompt();

        // 显式追加完成事件，确保前端能立即关闭SSE连接
        @SuppressWarnings({"rawtypes","unchecked"})
        ServerSentEvent<SettingGenerationEvent> completeSse = (ServerSentEvent<SettingGenerationEvent>)(ServerSentEvent) ServerSentEvent.builder()
                .event("complete")
                .data(java.util.Map.of("data", "[DONE]"))
                .build();

        // 先返回事件流，再在订阅后触发调整操作，避免竞态
        return settingGenerationService.getGenerationEventStream(sessionId)
                .doOnSubscribe(subscription -> {
                    settingGenerationService.adjustSession(
                            sessionId,
                            enhancedPrompt,
                            request.getModelConfigId(),
                            request.getPromptTemplateId()
                    ).subscribe(
                            result -> log.info("Session adjustment completed for session: {}", sessionId),
                            error -> log.error("Session adjustment failed for session: {}", sessionId, error)
                    );
                })
                .takeUntil(event -> {
                    if (event instanceof SettingGenerationEvent.GenerationCompletedEvent) {
                        return true; // 调整完成，结束流
                    }
                    if (event instanceof SettingGenerationEvent.GenerationErrorEvent err) {
                        return err.getRecoverable() != null && !err.getRecoverable(); // 不可恢复错误，结束流
                    }
                    return false;
                })
                .map(event -> ServerSentEvent.<SettingGenerationEvent>builder()
                        .id(String.valueOf(System.currentTimeMillis()))
                        .event(event.getClass().getSimpleName())
                        .data(event)
                        .build()
                )
                // 正常完成时，追加一个标准complete事件
                .concatWith(Mono.just(completeSse))
                .onErrorResume(error -> {
                    log.error("Failed to adjust session", error);
                    SettingGenerationEvent.GenerationErrorEvent errorEvent = new SettingGenerationEvent.GenerationErrorEvent();
                    errorEvent.setSessionId(sessionId);
                    errorEvent.setErrorCode("ADJUST_FAILED");
                    errorEvent.setErrorMessage(error.getMessage());
                    errorEvent.setRecoverable(true);
                    ServerSentEvent<SettingGenerationEvent> errorSse = ServerSentEvent.<SettingGenerationEvent>builder()
                            .event("GenerationErrorEvent")
                            .data(errorEvent)
                            .build();
                    // 错误时也追加complete，确保前端及时关闭SSE
                    return Flux.just(errorSse, completeSse);
                });
    }

    /**
     * 开始写作：确保novelId存在，保存当前session的设定到小说，并将小说标记为未就绪→就绪，返回小说ID
     *
     * 语义调整：彻底忽略历史记录的 novelId。历史仅作为设定树来源，不参与 novelId 的确定。
     *
     * 新增参数：
     * - fork: Boolean，默认 true（表示创建新小说，不复用会话里的 novelId）
     * - reuseNovel: Boolean（保留解析，不再使用历史记录 novelId）
     * 说明：当 fork 与 reuseNovel 同时传入时，以 fork 为准（fork=true 则强制新建）。
     */
    @PostMapping("/start-writing")
    @Operation(summary = "开始写作", description = "确保novelId存在，保存当前会话设定并关联到小说，然后返回小说ID")
    public Mono<ApiResponse<Map<String, String>>> startWriting(
            @CurrentUser User user,
            @RequestHeader(value = "X-User-Id", required = false) String headerUserId,
            @RequestBody Map<String, String> body
    ) {
        String sessionId = body.get("sessionId");
        String novelId = body.get("novelId");
        String historyId = body.get("historyId");

        // 解析 fork / reuseNovel 标志（默认创建新小说：fork=true）
        boolean fork = parseBoolean(body.get("fork")).orElse(true);
        parseBoolean(body.get("reuseNovel")).orElse(false); // 保留解析，逻辑已并入优先级顺序

        // 日志：入口参数与语义声明
        try {
            log.info("[开始写作] 忽略历史记录的 novelId，仅用于设定树：sessionId={}, body.novelId={}, historyId={}, fork={}",
                    sessionId, novelId, historyId, fork);
        } catch (Exception ignore) {}

        // 1) novelId / session 优先；其后 fork；否则新建（忽略历史记录 novelId）
        Mono<String> ensureNovel = Mono.defer(() -> {
            // 显式 novelId 优先
            if (novelId != null && !novelId.isBlank()) {
                try { log.info("[开始写作] 使用请求体提供的 novelId: {}", novelId); } catch (Exception ignore) {}
                return Mono.just(novelId);
            }
            // 会话中的 novelId 次之
            if (sessionId != null && !sessionId.isBlank()) {
                Mono<String> fromSession = sessionManager.getSession(sessionId)
                        .flatMap(sess -> {
                            String id = sess.getNovelId();
                            if (id != null && !id.isBlank()) {
                                try { log.info("[开始写作] 使用会话中的 novelId: {} (sessionId={})", id, sessionId); } catch (Exception ignore) {}
                            }
                            return (id == null || id.isBlank()) ? reactor.core.publisher.Mono.empty() : reactor.core.publisher.Mono.just(id);
                        });
                return fromSession.switchIfEmpty(Mono.defer(() -> {
                    // 若会话没有 novelId，则根据 fork 判断；不再从历史记录派生 novelId
                    if (fork) {
                        try { log.info("[开始写作] 会话无 novelId，fork=true → 创建草稿小说"); } catch (Exception ignore) {}
                        return novelService.createNovel(Novel.builder()
                                .title("未命名小说")
                                .description("自动创建的草稿，用于写作编排")
                                .author(Novel.Author.builder().id(user.getId()).username(user.getUsername()).build())
                                .isReady(true)
                                .build()).map(Novel::getId);
                    }
                    // fork=false 也不再使用历史记录 novelId，直接新建
                    try { log.info("[开始写作] 会话无 novelId，fork=false → 仍然创建草稿小说"); } catch (Exception ignore) {}
                    return novelService.createNovel(Novel.builder()
                            .title("未命名小说")
                            .description("自动创建的草稿，用于写作编排")
                            .author(Novel.Author.builder().id(user.getId()).username(user.getUsername()).build())
                            .isReady(true)
                            .build()).map(Novel::getId);
                }));
            }
            // 无 sessionId：按 fork 决定
            if (fork) {
                try { log.info("[开始写作] 无 sessionId，fork=true → 创建草稿小说"); } catch (Exception ignore) {}
                return novelService.createNovel(Novel.builder()
                        .title("未命名小说")
                        .description("自动创建的草稿，用于写作编排")
                        .author(Novel.Author.builder().id(user.getId()).username(user.getUsername()).build())
                        .isReady(true)
                        .build()).map(Novel::getId);
            }
            // fork=false 且未提供 novelId / session.novelId：直接新建（不再参考历史记录 novelId）
            try { log.info("[开始写作] 无 sessionId，fork=false → 创建草稿小说"); } catch (Exception ignore) {}
            return novelService.createNovel(Novel.builder()
                    .title("未命名小说")
                    .description("自动创建的草稿，用于写作编排")
                    .author(Novel.Author.builder().id(user.getId()).username(user.getUsername()).build())
                    .isReady(true)
                    .build()).map(Novel::getId);
        });

        String effectiveUserId = (user != null && user.getId() != null && !user.getId().isBlank())
                ? user.getId() : (headerUserId != null ? headerUserId : null);
        String effectiveUsername = (user != null && user.getUsername() != null && !user.getUsername().isBlank())
                ? user.getUsername() : effectiveUserId;
        if (effectiveUserId == null || effectiveUserId.isBlank()) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "START_WRITING_FAILED"));
        }
        // 统一使用 ensureNovel 的结果作为本次写作流程的 novelId，避免出现前后不一致
        return ensureNovel
                .flatMap(ensuredNovelId -> settingComposeService
                        .orchestrateStartWriting(effectiveUserId, effectiveUsername, sessionId, ensuredNovelId, historyId)
                        .map(nid -> ApiResponse.success(Map.of("novelId", nid)))
                        .onErrorResume(e -> {
                            String msg = e.getMessage() != null ? e.getMessage() : "发生未知错误";
                            if (e instanceof IllegalStateException && msg.startsWith("Session not completed")) {
                                return Mono.just(ApiResponse.error("会话未完成，请等待生成完成后再开始写作，或传入historyId", "SESSION_NOT_COMPLETED"));
                            }
                            // 容错：若误将 sessionId 当作 historyId 导致“历史记录不存在”，
                            // 依然返回成功并带上已确保的 novelId，避免前端因格式化错误文本而判失败
                            if (msg.startsWith("历史记录不存在")) {
                                return Mono.just(ApiResponse.success(Map.of("novelId", ensuredNovelId)));
                            }
                            return Mono.just(ApiResponse.error(msg, "START_WRITING_FAILED"));
                        })
                );
    }

    private java.util.Optional<Boolean> parseBoolean(Object val) {
        if (val == null) return java.util.Optional.empty();
        if (val instanceof Boolean b) return java.util.Optional.of(b);
        if (val instanceof String s) {
            String t = s.trim().toLowerCase();
            if ("true".equals(t) || "1".equals(t) || "yes".equals(t) || "y".equals(t)) return java.util.Optional.of(Boolean.TRUE);
            if ("false".equals(t) || "0".equals(t) || "no".equals(t) || "n".equals(t)) return java.util.Optional.of(Boolean.FALSE);
        }
        return java.util.Optional.empty();
    }

    /**
     * 轻量状态查询：仅报告是否存在该会话或历史记录
     */
    @GetMapping("/status-lite/{id}")
    @Operation(summary = "轻量状态查询", description = "返回ID是否为有效的会话或历史记录")
    public Mono<ApiResponse<Map<String, Object>>> getStatusLite(
            @CurrentUser User user,
            @Parameter(description = "会话ID或历史记录ID") @PathVariable String id) {
        return settingComposeService.getStatusLite(id).map(ApiResponse::success);
    }

    /**
     * 获取会话状态
     */
        @GetMapping("/{sessionId}/status")
        @Operation(summary = "获取会话状态", description = "获取指定会话的当前状态信息")
        public Mono<ApiResponse<SessionStatusResponse>> getSessionStatus(
                @CurrentUser User user,
                @Parameter(description = "会话ID") @PathVariable String sessionId) {
            
            log.info("Getting session status {} for user {}", sessionId, user.getId());
            
            return settingGenerationService.getSessionStatus(sessionId)
                .map(status -> {
                    SessionStatusResponse response = new SessionStatusResponse();
                    response.setSessionId(sessionId);
                    response.setStatus(status.status());
                    response.setProgress(status.progress());
                    response.setCurrentStep(status.currentStep());
                    response.setTotalSteps(status.totalSteps());
                    response.setErrorMessage(status.errorMessage());
                    return ApiResponse.<SessionStatusResponse>success(response);
                })
                .onErrorResume(error -> {
                    log.error("Failed to get session status", error);
                    return Mono.just(ApiResponse.<SessionStatusResponse>error("STATUS_GET_FAILED", error.getMessage()));
                });
        }

    /**
     * 取消生成会话
     */
    @PostMapping("/{sessionId}/cancel")
    @Operation(summary = "取消生成会话", description = "取消正在进行的设定生成会话")
    public Mono<ApiResponse<String>> cancelSession(
            @CurrentUser User user,
            @Parameter(description = "会话ID") @PathVariable String sessionId) {
        
        log.info("Cancelling session {} for user {}", sessionId, user.getId());
        
        return settingGenerationService.cancelSession(sessionId)
            .then(Mono.just(ApiResponse.success("会话已取消")))
            .onErrorResume(error -> {
                log.error("Failed to cancel session", error);
                return Mono.just(ApiResponse.error("CANCEL_FAILED", "取消会话失败: " + error.getMessage()));
            });
    }
    
    // ==================== 策略管理接口 ====================
    
    /**
     * 创建用户自定义策略
     */
    @PostMapping("/strategies/custom")
    @Operation(summary = "创建用户自定义策略", description = "用户创建完全自定义的设定生成策略")
    public Mono<ApiResponse<StrategyResponse>> createCustomStrategy(
            @CurrentUser User user,
            @Valid @RequestBody CreateCustomStrategyRequest request) {
        
        log.info("Creating custom strategy for user: {}, name: {}", user.getId(), request.getName());
        
        // TODO: 实现创建自定义策略的完整逻辑
        return Mono.just(new EnhancedUserPromptTemplate())
            .map(template -> {
                StrategyResponse response = mapToStrategyResponse(template);
                return ApiResponse.<StrategyResponse>success(response);
            })
            .onErrorResume(error -> {
                log.error("Failed to create custom strategy", error);
                return Mono.just(ApiResponse.<StrategyResponse>error("STRATEGY_CREATE_FAILED", error.getMessage()));
            });
    }
    
    /**
     * 基于现有策略创建新策略
     */
    @PostMapping("/strategies/from-base/{baseTemplateId}")
    @Operation(summary = "基于现有策略创建新策略", description = "基于系统预设或其他用户的策略创建个性化策略")
    public Mono<ApiResponse<StrategyResponse>> createStrategyFromBase(
            @CurrentUser User user,
            @Parameter(description = "基础策略模板ID") @PathVariable String baseTemplateId,
            @Valid @RequestBody CreateFromBaseStrategyRequest request) {
        
        log.info("Creating strategy from base {} for user: {}, name: {}", baseTemplateId, user.getId(), request.getName());
        
        // TODO: 实现基于现有策略创建的完整逻辑
        return Mono.just(new EnhancedUserPromptTemplate())
            .map(template -> {
                StrategyResponse response = mapToStrategyResponse(template);
                return ApiResponse.<StrategyResponse>success(response);
            })
            .onErrorResume(error -> {
                log.error("Failed to create strategy from base", error);
                return Mono.just(ApiResponse.<StrategyResponse>error("STRATEGY_CREATE_FROM_BASE_FAILED", error.getMessage()));
            });
    }
    
    /**
     * 获取用户的策略列表
     */
    @GetMapping("/strategies/my")
    @Operation(summary = "获取用户的策略列表", description = "获取当前用户创建的所有策略")
    public Flux<StrategyResponse> getUserStrategies(
            @CurrentUser User user,
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页大小") @RequestParam(defaultValue = "20") int size) {
        
        log.info("Getting strategies for user: {}, page: {}, size: {}", user.getId(), page, size);
        
        return strategyManagementService.getUserStrategies(user.getId(), 
                org.springframework.data.domain.PageRequest.of(page, size))
            .map(this::mapToStrategyResponse)
            .onErrorResume(error -> {
                log.error("Failed to get user strategies", error);
                return Flux.empty();
            });
    }
    
    /**
     * 获取公开策略列表
     */
    @GetMapping("/strategies/public")
    @Operation(summary = "获取公开策略列表", description = "获取所有审核通过的公开策略")
    public Flux<StrategyResponse> getPublicStrategies(
            @Parameter(description = "分类筛选") @RequestParam(required = false) String category,
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页大小") @RequestParam(defaultValue = "20") int size) {
        
        log.info("Getting public strategies, category: {}, page: {}, size: {}", category, page, size);
        
        return strategyManagementService.getPublicStrategies(category, 
                org.springframework.data.domain.PageRequest.of(page, size))
            .map(this::mapToStrategyResponse)
            .onErrorResume(error -> {
                log.error("Failed to get public strategies", error);
                return Flux.empty();
            });
    }
    
    /**
     * 获取策略详情
     */
    @GetMapping("/strategies/{strategyId}")
    @Operation(summary = "获取策略详情", description = "获取指定策略的详细信息")
    public Mono<ApiResponse<StrategyDetailResponse>> getStrategyDetail(
            @CurrentUser User user,
            @Parameter(description = "策略ID") @PathVariable String strategyId) {
        
        log.info("Getting strategy detail: {} for user: {}", strategyId, user.getId());
        
        // 这里需要从 templateRepository 获取详情，暂时使用简化实现
        return Mono.just(ApiResponse.<StrategyDetailResponse>success(new StrategyDetailResponse()))
            .doOnError(error -> log.error("Failed to get strategy detail", error));
    }
    
    /**
     * 更新策略
     */
    @PutMapping("/strategies/{strategyId}")
    @Operation(summary = "更新策略", description = "更新用户自己创建的策略")
    public Mono<ApiResponse<StrategyResponse>> updateStrategy(
            @CurrentUser User user,
            @Parameter(description = "策略ID") @PathVariable String strategyId,
            @Valid @RequestBody UpdateStrategyRequest request) {
        
        log.info("Updating strategy: {} for user: {}", strategyId, user.getId());
        
        // 这里需要实现策略更新逻辑，暂时返回成功响应
        return Mono.just(ApiResponse.<StrategyResponse>success(new StrategyResponse()))
            .doOnError(error -> log.error("Failed to update strategy", error));
    }
    
    /**
     * 删除策略
     */
    @DeleteMapping("/strategies/{strategyId}")
    @Operation(summary = "删除策略", description = "删除用户自己创建的策略")
    public Mono<ApiResponse<String>> deleteStrategy(
            @CurrentUser User user,
            @Parameter(description = "策略ID") @PathVariable String strategyId) {
        
        log.info("Deleting strategy: {} for user: {}", strategyId, user.getId());
        
        // 这里需要实现策略删除逻辑，暂时返回成功响应
        return Mono.just(ApiResponse.success("策略已删除"))
            .doOnError(error -> log.error("Failed to delete strategy", error));
    }
    
    /**
     * 提交策略审核
     */
    @PostMapping("/strategies/{strategyId}/submit-review")
    @Operation(summary = "提交策略审核", description = "将策略提交审核以便公开分享")
    public Mono<ApiResponse<String>> submitStrategyForReview(
            @CurrentUser User user,
            @Parameter(description = "策略ID") @PathVariable String strategyId) {
        
        log.info("Submitting strategy for review: {} by user: {}", strategyId, user.getId());
        
        return strategyManagementService.submitForReview(strategyId, user.getId())
            .then(Mono.just(ApiResponse.success("策略已提交审核")))
            .onErrorResume(error -> {
                log.error("Failed to submit strategy for review", error);
                return Mono.just(ApiResponse.error("SUBMIT_REVIEW_FAILED", error.getMessage()));
            });
    }
    
    // ==================== 管理员审核接口 ====================
    
    /**
     * 获取待审核策略列表（管理员接口）
     */
    @GetMapping("/admin/strategies/pending")
    @Operation(summary = "获取待审核策略列表", description = "管理员获取所有待审核的策略")
    public Flux<StrategyResponse> getPendingStrategies(
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页大小") @RequestParam(defaultValue = "20") int size) {
        
        log.info("Getting pending strategies for review, page: {}, size: {}", page, size);
        
        return strategyManagementService.getPendingReviews(
                org.springframework.data.domain.PageRequest.of(page, size))
            .map(this::mapToStrategyResponse)
            .onErrorResume(error -> {
                log.error("Failed to get pending strategies", error);
                return Flux.empty();
            });
    }
    
    /**
     * 审核策略（管理员接口）
     */
    @PostMapping("/admin/strategies/{strategyId}/review")
    @Operation(summary = "审核策略", description = "管理员审核策略，决定是否通过")
    public Mono<ApiResponse<String>> reviewStrategy(
            @CurrentUser User reviewer,
            @Parameter(description = "策略ID") @PathVariable String strategyId,
            @Valid @RequestBody ReviewStrategyRequest request) {
        
        log.info("Reviewing strategy: {} by reviewer: {}, decision: {}", 
            strategyId, reviewer.getId(), request.getDecision());
        
        // TODO: 实现策略审核的完整逻辑
        return Mono.just(new EnhancedUserPromptTemplate())
            .then(Mono.just(ApiResponse.success("审核完成")))
            .onErrorResume(error -> {
                log.error("Failed to review strategy", error);
                return Mono.just(ApiResponse.error("REVIEW_FAILED", error.getMessage()));
            });
    }
    
    // ==================== 辅助方法 ====================
    
    // 暂时使用简化的映射，后续需要实现完整的服务层方法
    // 这些方法需要根据实际的服务层接口来完善
    
    private StrategyResponse mapToStrategyResponse(EnhancedUserPromptTemplate template) {
        StrategyResponse response = new StrategyResponse();
        
        // 安全地获取各个字段，避免空指针异常
        response.setId(template.getId() != null ? template.getId() : "");
        response.setName(template.getName() != null ? template.getName() : "");
        response.setDescription(template.getDescription() != null ? template.getDescription() : "");
        response.setAuthorId(template.getAuthorId() != null ? template.getAuthorId() : "");
        response.setIsPublic(template.getIsPublic() != null ? template.getIsPublic() : false);
        response.setCreatedAt(template.getCreatedAt());
        response.setUpdatedAt(template.getUpdatedAt());
        response.setUsageCount(0L); // 默认值
        
        if (template.getSettingGenerationConfig() != null) {
            response.setExpectedRootNodes(template.getSettingGenerationConfig().getExpectedRootNodes());
            response.setMaxDepth(template.getSettingGenerationConfig().getMaxDepth());
            
            if (template.getSettingGenerationConfig().getReviewStatus() != null &&
                template.getSettingGenerationConfig().getReviewStatus().getStatus() != null) {
                response.setReviewStatus(template.getSettingGenerationConfig().getReviewStatus().getStatus().name());
            } else {
                response.setReviewStatus("DRAFT");
            }
            
            if (template.getSettingGenerationConfig().getMetadata() != null) {
                response.setCategories(template.getSettingGenerationConfig().getMetadata().getCategories());
                response.setTags(template.getSettingGenerationConfig().getMetadata().getTags());
                response.setDifficultyLevel(template.getSettingGenerationConfig().getMetadata().getDifficultyLevel());
            }
        } else {
            // 设置默认值
            response.setExpectedRootNodes(0);
            response.setMaxDepth(5);
            response.setReviewStatus("DRAFT");
        }
        
        return response;
    }
    
    // ==================== DTO 类 ====================
    
    /**
     * 启动生成请求
     */
    @Data
    public static class StartGenerationRequest {
        @NotBlank(message = "初始提示词不能为空")
        private String initialPrompt;
        
        // 新的字段，与strategy二选一
        private String promptTemplateId;
        
        private String novelId; // 改为可选
        
        @NotBlank(message = "模型配置ID不能为空")
        private String modelConfigId;
        
        // 当没有JWT认证时使用的用户ID
        private String userId;
        
        // 保留兼容性，与promptTemplateId二选一
        @Deprecated
        private String strategy;

        // 文本阶段是否改用公共模型
        private Boolean usePublicTextModel;
        
        // 自定义验证：promptTemplateId和strategy必须提供其中一个
        public boolean isValid() {
            return (promptTemplateId != null && !promptTemplateId.trim().isEmpty()) ||
                   (strategy != null && !strategy.trim().isEmpty());
        }
    }

    /**
     * 创建自定义策略请求
     */
    @Data
    public static class CreateCustomStrategyRequest {
        @NotBlank(message = "策略名称不能为空")
        private String name;
        
        @NotBlank(message = "策略描述不能为空")
        private String description;
        
        @NotBlank(message = "系统提示词不能为空")
        private String systemPrompt;
        
        @NotBlank(message = "用户提示词不能为空")
        private String userPrompt;
        
        private List<NodeTemplateConfig> nodeTemplates;
        
        private Integer expectedRootNodes;
        
        private Integer maxDepth;
        
        private String baseStrategyId; // 可选，如果指定则基于该策略
    }
    
    /**
     * 基于现有策略创建请求
     */
    @Data
    public static class CreateFromBaseStrategyRequest {
        @NotBlank(message = "策略名称不能为空")
        private String name;
        
        @NotBlank(message = "策略描述不能为空")
        private String description;
        
        private String systemPrompt; // 可选，不提供则使用基础策略的
        
        private String userPrompt; // 可选，不提供则使用基础策略的
        
        private Map<String, Object> modifications; // 对基础策略的修改
    }
    
    /**
     * 更新策略请求
     */
    @Data
    public static class UpdateStrategyRequest {
        @NotBlank(message = "策略名称不能为空")
        private String name;
        
        @NotBlank(message = "策略描述不能为空")
        private String description;
        
        private String systemPrompt;
        
        private String userPrompt;
        
        private List<NodeTemplateConfig> nodeTemplates;
        
        private Integer expectedRootNodes;
        
        private Integer maxDepth;
    }
    
    /**
     * 审核策略请求
     */
    @Data
    public static class ReviewStrategyRequest {
        @NotBlank(message = "审核决定不能为空")
        private String decision; // APPROVED, REJECTED
        
        private String comment; // 审核评论
        
        private List<String> rejectionReasons; // 拒绝理由
        
        private List<String> improvementSuggestions; // 改进建议
    }
    
    /**
     * 策略响应
     */
    @Data
    public static class StrategyResponse {
        private String id;
        private String name;
        private String description;
        private String authorId;
        private Boolean isPublic;
        private java.time.LocalDateTime createdAt;
        private java.time.LocalDateTime updatedAt;
        private Long usageCount;
        private Integer expectedRootNodes;
        private Integer maxDepth;
        private String reviewStatus;
        private List<String> categories;
        private List<String> tags;
        private Integer difficultyLevel;
    }
    
    /**
     * 策略详情响应
     */
    @Data
    public static class StrategyDetailResponse {
        private String id;
        private String name;
        private String description;
        private String authorId;
        private String authorName;
        private Boolean isPublic;
        private java.time.LocalDateTime createdAt;
        private java.time.LocalDateTime updatedAt;
        private Long usageCount;
        private Integer expectedRootNodes;
        private Integer maxDepth;
        private String reviewStatus;
        private List<String> categories;
        private List<String> tags;
        private Integer difficultyLevel;
        private String systemPrompt;
        private String userPrompt;
        private List<NodeTemplateConfig> nodeTemplates;
    }

    /**
     * 从小说创建编辑会话请求
     */
    @Data
    public static class CreateNovelEditSessionRequest {
        /**
         * 编辑原因/说明
         */
        private String editReason;
        
        /**
         * 模型配置ID
         */
        @NotBlank(message = "模型配置ID不能为空")
        private String modelConfigId;

        /**
         * 是否创建新的快照
         */
        private boolean createNewSnapshot = false;
    }
    
    /**
     * 更新节点请求
     */
    @Data
    public static class UpdateNodeRequest {
        @NotBlank(message = "节点ID不能为空")
        private String nodeId;
        
        @NotBlank(message = "修改提示词不能为空")
        private String modificationPrompt;
        
        @NotBlank(message = "模型配置ID不能为空")
        private String modelConfigId;

        /**
         * 修改范围：self | children_only | self_and_children
         */
        private String scope;

        /**
         * 是否使用公共模型（可选）。若为true，优先使用 publicModelConfigId 分支。
         * 命名为 publicModel 以适配标准布尔JavaBean访问器（getPublicModel）。
         */
        private Boolean publicModel;

        /**
         * 公共模型配置ID（可选）。仅当 isPublicModel=true 时生效。
         */
        private String publicModelConfigId;
    }

    /**
     * 更新节点内容请求
     */
    @Data
    public static class UpdateNodeContentRequest {
        @NotBlank(message = "节点ID不能为空")
        private String nodeId;
        
        @NotBlank(message = "新内容不能为空")
        private String newContent;
    }

    /**
     * 整体调整生成请求
     */
    @Data
    public static class AdjustSessionRequest {
        @NotBlank(message = "调整提示词不能为空")
        private String adjustmentPrompt;

        @NotBlank(message = "模型配置ID不能为空")
        private String modelConfigId;

        /**
         * 提示词模板ID：用于指定策略/提示风格
         */
        @NotBlank(message = "提示词模板ID不能为空")
        private String promptTemplateId;
    }

    /**
     * 保存设定请求
     */
    @Data
    public static class SaveSettingsRequest {
        /**
         * 小说ID
         * 如果为 null 或空字符串，表示保存为独立快照（不关联任何小说）
         */
        private String novelId;
        
        /**
         * 是否更新现有历史记录
         * true: 更新当前历史记录（一般使用sessionId作为historyId）
         * false: 创建新的历史记录（默认行为）
         */
        private Boolean updateExisting = false;
        
        /**
         * 目标历史记录ID
         * 当updateExisting=true时使用，一般情况下就是sessionId
         */
        private String targetHistoryId;
    }
    
    /**
     * 编辑会话响应
     */
    @Data
    public static class EditSessionResponse {
        private String sessionId;
        private String message;
        private boolean hasExistingHistory;
        private String snapshotMode;
    }
    
    /**
     * 保存设定响应
     */
    @Data
    public static class SaveSettingResponse {
        private boolean success;
        private String message;
        private List<String> rootSettingIds;
        private String historyId; // 新增：自动创建的历史记录ID
    }

    /**
     * 会话状态响应
     */
    @Data
    public static class SessionStatusResponse {
        private String sessionId;
        private String status;
        private Integer progress;
        private String currentStep;
        private Integer totalSteps;
        private String errorMessage;
    }
}