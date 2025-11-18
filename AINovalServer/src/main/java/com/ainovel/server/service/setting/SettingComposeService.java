package com.ainovel.server.service.setting;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.UniversalAIService;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.NovelAIService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.NovelSettingService;
// import com.ainovel.server.service.setting.generation.SettingGenerationService;
import com.ainovel.server.service.setting.generation.InMemorySessionManager;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.domain.model.setting.generation.SettingGenerationSession;
import com.ainovel.server.domain.model.setting.generation.SettingNode;
import com.ainovel.server.service.setting.NovelSettingHistoryService.HistoryWithSettings;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.web.dto.response.UniversalAIResponseDto;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
// import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.agent.tool.ToolSpecification;

/**
 * 写作编排服务（基于一个 AIFeatureType 实现大纲/章节/组合）
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SettingComposeService {

    private final UniversalAIService universalAIService;
    private final NovelService novelService;
    // private final com.ainovel.server.service.SceneService sceneService;
    private final InMemorySessionManager inMemorySessionManager;
    private final SettingConversionService settingConversionService;
    private final NovelSettingService novelSettingService;
    private final com.ainovel.server.service.setting.NovelSettingHistoryService historyService;
    // private final SettingGenerationService settingGenerationService;
    private final ObjectMapper objectMapper;
    private final NovelAIService novelAIService;
    private final AIService aiService;
    private final com.ainovel.server.service.ai.tools.ToolExecutionService toolExecutionService;
    private final com.ainovel.server.service.ai.tools.ToolRegistry toolRegistry;
    private final com.ainovel.server.service.prompt.providers.NovelComposePromptProvider composePromptProvider;
    private final PublicModelConfigService publicModelConfigService;
    // private final com.ainovel.server.service.ai.tools.fallback.ToolFallbackRegistry toolFallbackRegistry;

    public Flux<UniversalAIResponseDto> streamCompose(UniversalAIRequestDto request) {
        // 归一化 requestType
        request.setRequestType(AIFeatureType.NOVEL_COMPOSE.name());

        // 先确保 novelId（若无则创建草稿），再尝试把设定会话落库
        Mono<UniversalAIRequestDto> prepared = ensureNovelIdIfNeeded(request)
                .flatMap(req -> tryConvertSettingsFromSession(req).thenReturn(req));

        // 🚀 修复：提前发送初始绑定信号（ready=false），告诉前端已绑定但还在生成中
        return prepared.flatMapMany(preq -> {
            log.info("[Compose] prepared: userId={}, settingSessionId={}, sessionId={}, novelId={}",
                    preq.getUserId(), preq.getSettingSessionId(), preq.getSessionId(), preq.getNovelId());
            Flux<UniversalAIResponseDto> preBind = bindNovelToSessionAndSignalInitial(preq.getNovelId(), preq.getSettingSessionId())
                    .doOnNext(chunk -> {
                        try {
                            Map<String, Object> m = chunk.getMetadata();
                            Object bind = m != null ? m.get("composeBind") : null;
                            Object status = m != null ? m.get("composeBindStatus") : null;
                            Object ready = m != null ? m.get("composeReady") : null;
                            log.info("[Compose] preBind emitted: bind={}, status={}, ready={}", bind, status, ready);
                        } catch (Exception ignore) {}
                    })
                    .flux();
            return Flux.concat(preBind, streamWithPrepared(preq));
        });
    }

    // ==================== 开始写作编排（无会话可直接从历史恢复） ====================
    public Mono<String> orchestrateStartWriting(String userId, String username, String sessionId, String novelId, String historyId) {
        return ensureNovelIdForStart(userId, username, novelId, sessionId, historyId)
            .flatMap(nid -> performSaveOrRestore(userId, sessionId, historyId, nid)
                .then(markNovelReady(nid))
                .thenReturn(nid)
            );
    }

    private Mono<String> ensureNovelIdForStart(String userId, String username, String providedNovelId, String sessionId, String historyId) {
        if (providedNovelId != null && !providedNovelId.isEmpty()) {
            try { log.info("[开始写作/服务] 使用传入 novelId: {}", providedNovelId); } catch (Exception ignore) {}
            return Mono.just(providedNovelId);
        }
        Mono<String> fromSession = Mono.defer(() -> {
            if (sessionId == null || sessionId.isEmpty()) return Mono.empty();
            return inMemorySessionManager.getSession(sessionId)
                .flatMap(s -> Mono.justOrEmpty(s.getNovelId()))
                .filter(id -> !id.isEmpty());
        });
        Mono<String> createDraft = Mono.defer(() -> {
            try { log.info("[开始写作/服务] 未提供 novelId，准备创建草稿小说"); } catch (Exception ignore) {}
            Novel draft = new Novel();
            draft.setTitle("未命名小说");
            draft.setDescription("自动创建的草稿，用于写作编排");
            Novel.Author author = Novel.Author.builder().id(userId).username(username != null ? username : userId).build();
            draft.setAuthor(author);
            return novelService.createNovel(draft).map(Novel::getId);
        });
        // 历史记录仅提供设定树信息，不再参与 novelId 的确定
        return fromSession.switchIfEmpty(createDraft);
    }

    private Mono<Void> performSaveOrRestore(String userId, String sessionId, String historyId, String novelId) {
        // 优先保存当前会话节点；仅当会话不存在或无节点且显式传入 historyId 时，从历史恢复设定树
        if (sessionId != null && !sessionId.isEmpty()) {
            return inMemorySessionManager.getSession(sessionId)
                    .flatMap(sess -> {
                        boolean hasNodes = false;
                        try {
                            hasNodes = sess.getGeneratedNodes() != null && !sess.getGeneratedNodes().isEmpty();
                        } catch (Exception ignore) {}

                        Mono<Void> opMono;
                        if (hasNodes) {
                            try { log.info("[开始写作/服务] 会话存在且有生成节点，直接保存为小说设定: sessionId={}, novelId={}", sessionId, novelId); } catch (Exception ignore) {}
                            // 直接将会话的生成节点转换并保存到当前 novelId（不依赖会话完成状态）
                            java.util.List<NovelSettingItem> items = settingConversionService.convertSessionToSettingItems(sess, novelId);
                            try { log.info("[开始写作/服务] 将保存设定条目数量: {}", (items != null ? items.size() : 0)); } catch (Exception ignore) {}
                            opMono = novelSettingService.saveAll(items).then();
                        } else if (historyId != null && !historyId.isEmpty()) {
                            try { log.info("[开始写作/服务] 会话无节点，使用显式 historyId 进行历史拷贝: {}", historyId); } catch (Exception ignore) {}
                            opMono = restoreFromHistoryStrict(userId, historyId, novelId);
                        } else {
                            try { log.info("[开始写作/服务] 会话无节点且未提供 historyId，跳过保存/恢复"); } catch (Exception ignore) {}
                            // 无可保存/恢复的数据，直接跳过
                            opMono = Mono.empty();
                        }

                        return opMono.then(
                                inMemorySessionManager.getSession(sessionId)
                                        .flatMap(s -> {
                                            s.setNovelId(novelId);
                                            return inMemorySessionManager.saveSession(s);
                                        })
                                        .onErrorResume(e -> {
                                            log.warn("[Compose] 绑定 novelId 到会话失败: sessionId={}, novelId={}, err={}", sessionId, novelId, e.getMessage());
                                            return Mono.empty();
                                        })
                                        .then()
                        );
                    })
                    .switchIfEmpty(Mono.defer(() -> {
                        // 会话不存在：显式提供 historyId 则恢复；否则尝试将 sessionId 视为 historyId 恢复
                        if (historyId != null && !historyId.isEmpty()) {
                            try { log.info("[开始写作/服务] 无会话，使用显式 historyId 进行历史拷贝: {}", historyId); } catch (Exception ignore) {}
                            return restoreFromHistoryStrict(userId, historyId, novelId);
                        }
                        if (sessionId != null && !sessionId.isEmpty()) {
                            try { log.info("[开始写作/服务] 无会话，尝试将 sessionId 当作 historyId 进行历史拷贝: {}", sessionId); } catch (Exception ignore) {}
                            return restoreFromHistoryStrict(userId, sessionId, novelId);
                        }
                        return Mono.empty();
                    }));
        }
        // 无 sessionId：仅在显式提供 historyId 时进行恢复
        if (historyId != null && !historyId.isEmpty()) {
            try { log.info("[开始写作/服务] 无 sessionId，使用显式 historyId 进行历史拷贝: {}", historyId); } catch (Exception ignore) {}
            return restoreFromHistoryStrict(userId, historyId, novelId);
        }
        return Mono.empty();
    }

    private Mono<Void> restoreFromHistoryStrict(String userId, String historyId, String novelId) {
        if (userId == null || userId.isEmpty()) {
            return Mono.error(new RuntimeException("UNAUTHORIZED"));
        }
        return historyService.getHistoryById(historyId)
            .flatMap(h -> {
                if (!userId.equals(h.getUserId())) {
                    return Mono.error(new RuntimeException("无权限恢复此历史记录"));
                }
                // 使用直接拷贝实现，避免无谓的 SettingNode 往返转换
                try { log.info("[开始写作/服务] 历史拷贝：historyId={} -> novelId={}", historyId, novelId); } catch (Exception ignore) {}
                return historyService.copyHistoryItemsToNovel(historyId, novelId, userId).then();
            });
    }

    private Mono<Void> markNovelReady(String novelId) {
        // 仅更新就绪标记，显式避免携带结构字段，防止触发结构合并
        Novel patch = new Novel();
        patch.setId(novelId);
        patch.setIsReady(true);
        // 显式置空结构，确保不会因为默认builder值而传入空结构
        patch.setStructure(null);
        return novelService.updateNovel(novelId, patch).then();
    }

    public Mono<Map<String, Object>> getStatusLite(String id) {
        return inMemorySessionManager.getSession(id)
            .map(sess -> {
                Map<String, Object> body = new java.util.HashMap<>();
                body.put("type", "session");
                body.put("exists", true);
                body.put("status", sess.getStatus().name());
                return body;
            })
            .switchIfEmpty(
                historyService.getHistoryById(id)
                    .map(h -> {
                        Map<String, Object> body = new java.util.HashMap<>();
                        body.put("type", "history");
                        body.put("exists", true);
                        return body;
                    })
                    .onErrorResume(err -> Mono.fromSupplier(() -> {
                        Map<String, Object> body = new java.util.HashMap<>();
                        body.put("type", "none");
                        body.put("exists", false);
                        return body;
                    }))
            );
    }

    private Flux<UniversalAIResponseDto> streamWithPrepared(UniversalAIRequestDto request) {
        String mode = getParam(request, "mode", "outline");

        if ("outline".equalsIgnoreCase(mode)) {
            // 公共/私有统一走工具化大纲路径
            Mono<List<String>> blocksMono = generateOutlinesWithTools(request).map(items -> {
                List<String> blocks = new ArrayList<>();
                for (int i = 0; i < items.size(); i++) {
                    var it = items.get(i);
                    String title = it.getTitle() != null ? it.getTitle() : defaultChapterTitle(i + 1);
                    String summary = it.getSummary() != null ? it.getSummary() : "";
                    blocks.add(title + "\n" + summary);
                }
                return blocks;
            }).cache();

            Mono<UniversalAIResponseDto> afterMono = blocksMono.flatMap(blocks -> {
                String novelId = request.getNovelId();
                List<Mono<Void>> saves = new ArrayList<>();
                for (int i = 0; i < blocks.size(); i++) {
                    String block = blocks.get(i);
                    String title = defaultChapterTitle(i + 1);
                    String outlineSummary = block.contains("\n") ? block.substring(block.indexOf("\n") + 1) : block;
                    if (novelId != null && !novelId.isEmpty()) {
                        saves.add(saveChapter(novelId, title, outlineSummary, ""));
                    }
                }
                Mono<Void> all = saves.isEmpty() ? Mono.empty() : reactor.core.publisher.Flux.fromIterable(saves).concatMap(m -> m).then();
                Mono<UniversalAIResponseDto> bindChunk = bindNovelToSessionAndSignal(novelId, request.getSettingSessionId());
                // 在保存完成后同步刷新字数统计，再发送绑定信号
                Mono<UniversalAIResponseDto> tail = (novelId != null && !novelId.isEmpty())
                        ? novelService.updateNovelWordCount(novelId).then(bindChunk)
                        : bindChunk;
                return all.then(tail);
            });

            Flux<UniversalAIResponseDto> outlinesJsonFlux = blocksMono
                    .map(blocks -> buildOutlinesMetadata(blocks))
                    .map(meta -> buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta))
                    .flux();

            return Flux.concat(outlinesJsonFlux, afterMono.flux());
        }
        if ("chapters".equalsIgnoreCase(mode)) {
            AtomicReference<StringBuilder> buffer = new AtomicReference<>(new StringBuilder());
            Mono<String> wholeTreeContextMono = maybeBuildWholeSettingTreeContext(request);
            Flux<UniversalAIResponseDto> stream = wholeTreeContextMono.flatMapMany(ctx -> {
                try { log.info("[Compose][Context] Chapters mode ctx.length={}", (ctx != null ? ctx.length() : -1)); } catch (Exception ignore) {}
                UniversalAIRequestDto reqWithCtx = (ctx != null && !ctx.isBlank())
                        ? cloneWithParam(request, Map.of("context", ctx))
                        : request;
                return universalAIService.processStreamRequest(reqWithCtx)
                        .doOnNext(evt -> {
                            if (evt != null && evt.getContent() != null) {
                                buffer.get().append(evt.getContent());
                            }
                        });
            });

            Mono<UniversalAIResponseDto> postMono = Mono.defer(() -> {
                try {
                    String novelId = request.getNovelId();
                    int expected = getIntParam(request, "chapterCount", 3);
                    List<ChapterPiece> pieces = parseChapters(buffer.get().toString(), expected);
                    List<Mono<Void>> saves = new ArrayList<>();
                    for (int i = 0; i < pieces.size(); i++) {
                        ChapterPiece piece = pieces.get(i);
                        String outlineText = piece.outline != null ? piece.outline : "";
                        String title = piece.title != null && !piece.title.isEmpty() ? piece.title : defaultChapterTitle(i + 1);
                        String content = piece.content != null ? piece.content : "";
                        if (novelId != null && !novelId.isEmpty()) {
                            saves.add(saveChapter(novelId, title, outlineText, content));
                        }
                    }
                    Mono<Void> all = saves.isEmpty() ? Mono.empty() : reactor.core.publisher.Flux.fromIterable(saves).concatMap(m -> m).then();
                    Mono<UniversalAIResponseDto> bindChunk = bindNovelToSessionAndSignal(novelId, request.getSettingSessionId());
                    // 在保存完成后同步刷新字数统计，再发送绑定信号
                    Mono<UniversalAIResponseDto> tail = (novelId != null && !novelId.isEmpty())
                            ? novelService.updateNovelWordCount(novelId).then(bindChunk)
                            : bindChunk;
                    return all.then(tail);
                } catch (Exception e) {
                    log.warn("[Compose] 仅章节模式后处理失败: {}", e.getMessage());
                    return Mono.empty();
                }
            });

            return Flux.concat(stream, postMono.flux());
        }

        if ("outline_plus_chapters".equalsIgnoreCase(mode)) {
            // 1) 先大纲：统一走工具化大纲路径（公共逻辑由装饰器处理）
            UniversalAIRequestDto outlineReq = cloneWithParam(request, Map.of("mode", "outline"));

            // 转换为字符串块供后续章节生成使用："标题\n摘要"（缓存，防止多订阅）
            Mono<List<String>> outlinesMono = generateOutlinesWithTools(outlineReq).map(items -> {
                List<String> blocks = new ArrayList<>();
                for (int i = 0; i < items.size(); i++) {
                    var it = items.get(i);
                    String title = it.getTitle() != null ? it.getTitle() : defaultChapterTitle(i + 1);
                    String summary = it.getSummary() != null ? it.getSummary() : "";
                    blocks.add(title + "\n" + summary);
                }
                return blocks;
            }).cache();

            // 将大纲块作为结构化元数据发给前端
            Flux<UniversalAIResponseDto> outlinesJsonFlux = outlinesMono
                    .map(outlines -> buildOutlinesMetadata(outlines))
                    .map(meta -> buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta))
                    .flux();

            Mono<String> wholeTreeContextMono = maybeBuildWholeSettingTreeContext(request);
            Flux<UniversalAIResponseDto> chaptersFlux = outlinesMono.flatMapMany(outlines -> {
                // 🚀 新的串行生成逻辑：改为逐章串行生成，确保章节间依赖关系正确
                log.info("[Compose][Serial] 开始串行生成 {} 章节", outlines.size());
                
                return wholeTreeContextMono.flatMapMany(settingTreeContext -> {
                    try { 
                        log.info("[Compose][Context] Outline+Chapters mode settingTreeContext.length={}", 
                                (settingTreeContext != null ? settingTreeContext.length() : -1)); 
                    } catch (Exception ignore) {}
                    
                    // 🚀 使用递归方式串行生成章节
                    return generateChaptersSequentially(request, outlines, settingTreeContext, 0, new ArrayList<>(), new StringBuilder());
                });
            });

            return Flux.concat(outlinesJsonFlux, chaptersFlux);
        }

        // 兜底：按普通流式处理（装饰器统一处理公共路径）
        return universalAIService.processStreamRequest(request);
    }

    /**
     * 🚀 新增：串行生成章节，确保章节间依赖关系正确
     * @param request 原始请求
     * @param outlines 所有章节的大纲列表
     * @param settingTreeContext 设定树上下文
     * @param currentIndex 当前生成章节的索引
     * @param chapterBuffers 已生成章节内容的缓存
     * @param previousContext 前面章节的累积上下文
     * @return 流式响应
     */
    private Flux<UniversalAIResponseDto> generateChaptersSequentially(
            UniversalAIRequestDto request, 
            List<String> outlines, 
            String settingTreeContext,
            int currentIndex, 
            List<StringBuilder> chapterBuffers,
            StringBuilder previousContext) {
        
        // 递归终止条件：所有章节生成完毕
        if (currentIndex >= outlines.size()) {
            log.info("[Compose][Serial] 所有章节生成完毕，开始保存到数据库");
            
            // 在最后统一保存所有章节并绑定小说
            Mono<UniversalAIResponseDto> saveMono = Mono.defer(() -> {
                String novelId = request.getNovelId();
                if (novelId != null && !novelId.isEmpty()) {
                    List<Mono<Void>> saves = new ArrayList<>();
                    for (int i = 0; i < outlines.size(); i++) {
                        String outlineText = outlines.get(i);
                        String content = chapterBuffers.get(i).toString();
                        String chapterTitle = defaultChapterTitle(i + 1);
                        saves.add(saveChapter(novelId, chapterTitle, outlineText, content));
                    }
                    Mono<Void> all = saves.isEmpty() ? Mono.empty() : 
                            reactor.core.publisher.Flux.fromIterable(saves).concatMap(m -> m).then();
                    
                    return all
                            .then(novelService.updateNovelWordCount(novelId))
                            .then(bindNovelToSessionAndSignal(novelId, request.getSettingSessionId()));
                }
                return bindNovelToSessionAndSignal(null, request.getSettingSessionId());
            });
            
            return saveMono.flux();
        }
        
        // 生成当前章节
        String outlineText = outlines.get(currentIndex);
        int chapterIndex = currentIndex + 1;
        chapterBuffers.add(new StringBuilder());
        
        log.info("[Compose][Serial] 开始生成第 {} 章，前文上下文长度: {}", 
                chapterIndex, previousContext.length());
        
        // 构建当前章节的生成请求
        UniversalAIRequestDto s2sReq = cloneWithParam(request, Map.of(
                "chapterIndex", chapterIndex,
                "outlineText", outlineText,
                "previousChaptersContent", previousContext.toString(), // 🚀 传递前面章节的完整内容
                "totalChapters", outlines.size()
        ));
        
        // 切换功能类型为 SUMMARY_TO_SCENE，并将大纲作为 prompt 传入
        s2sReq.setRequestType(AIFeatureType.SUMMARY_TO_SCENE.name());
        s2sReq.setPrompt(outlineText);
        
        // 🚀 上游仅传入设定树给 context，由占位符解析器统一合并previousChaptersContent，避免重复
        if (settingTreeContext != null && !settingTreeContext.isBlank()) {
            s2sReq.getParameters().put("context", settingTreeContext);
        }
        if (previousContext.length() > 0) {
            s2sReq.getParameters().put("previousChaptersContent", previousContext.toString());
        }
        
        // 🚀 透传前端模型/提示词相关参数：instructions、length、topP、topK（若提供）
        try {
            if (request.getInstructions() != null && !request.getInstructions().isEmpty()) {
                s2sReq.setInstructions(request.getInstructions());
                s2sReq.getParameters().put("instructions", request.getInstructions());
            }
            if (request.getParameters() != null) {
                Object len = request.getParameters().get("length");
                if (len != null) {
                    s2sReq.getParameters().put("length", len);
                }
                Object topP = request.getParameters().get("topP");
                if (topP != null) {
                    s2sReq.getParameters().put("topP", topP);
                }
                Object topK = request.getParameters().get("topK");
                if (topK != null) {
                    s2sReq.getParameters().put("topK", topK);
                }
            }
        } catch (Exception ignore) {}
        
        // 若前端传入 s2sTemplateId，则映射为本次 S2S 请求的 promptTemplateId
        if (request.getParameters() != null && request.getParameters().get("s2sTemplateId") instanceof String) {
            String s2sTemplateId = (String) request.getParameters().get("s2sTemplateId");
            if (s2sTemplateId != null && !s2sTemplateId.isEmpty()) {
                s2sReq.getParameters().put("promptTemplateId", s2sTemplateId);
            }
        }
        
        // 输出章节大纲和正文开始标记
        Flux<UniversalAIResponseDto> preOutline = Flux.just(
                buildSystemChunk(AIFeatureType.SUMMARY_TO_SCENE.name(),
                        "[CHAPTER_" + chapterIndex + "_OUTLINE]\n" + outlineText + "\n"));
        Flux<UniversalAIResponseDto> preContentStart = Flux.just(
                buildSystemChunk(AIFeatureType.SUMMARY_TO_SCENE.name(),
                        "[CHAPTER_" + chapterIndex + "_CONTENT]"));
        
        // 计费归一化处理
        try {
            com.ainovel.server.service.billing.PublicModelBillingNormalizer.normalize(
                s2sReq,
                true,
                true,
                AIFeatureType.SUMMARY_TO_SCENE.name(),
                resolveModelConfigId(s2sReq),
                null,
                null,
                s2sReq.getSettingSessionId() != null ? s2sReq.getSettingSessionId() : s2sReq.getSessionId(),
                null
            );
        } catch (Exception ignore) {}
        
        // 🚀 生成当前章节内容，并在完成后递归生成下一章
        Flux<UniversalAIResponseDto> currentChapterFlux = universalAIService.processStreamRequest(s2sReq)
                .doOnNext(evt -> {
                    if (evt != null && evt.getContent() != null) {
                        chapterBuffers.get(currentIndex).append(evt.getContent());
                        log.debug("🔧 [DEBUG] 章节 {} 收到内容块: length={}, 累积长度={}", 
                                chapterIndex, evt.getContent().length(), chapterBuffers.get(currentIndex).length());
                    }
                })
                .doOnComplete(() -> {
                    String generatedContent = chapterBuffers.get(currentIndex).toString();
                    log.info("[Compose][Serial] 第 {} 章生成完成，内容长度: {} 字符", 
                            chapterIndex, generatedContent.length());
                    log.info("🔧 [DEBUG] 章节 {} 内容预览: '{}'", chapterIndex, 
                            generatedContent.length() > 100 ? generatedContent.substring(0, 100) + "..." : generatedContent);
                    
                    // 🚀 将当前章节的摘要和内容添加到上下文中，供下一章使用
                    previousContext.append("\n\n==== 第").append(chapterIndex).append("章 ====\n");
                    previousContext.append("摘要: ").append(outlineText).append("\n");
                    previousContext.append("内容: ").append(generatedContent);
                    
                    // 🚀 智能管理上下文窗口，避免过长
                    manageContextWindow(previousContext);
                });

        // 返回：大纲标记 → 正文开始标记 → 当前章节内容 →（当前完成后）下一章节内容...
        return Flux.concat(preOutline, preContentStart, currentChapterFlux)
                .concatWith(reactor.core.publisher.Flux.defer(() ->
                        generateChaptersSequentially(request, outlines, settingTreeContext,
                                currentIndex + 1, chapterBuffers, previousContext)
                ));
    }
    
    /**
     * 🚀 新增：智能管理上下文窗口，避免上下文过长
     * @param context 当前累积的上下文
     */
    private void manageContextWindow(StringBuilder context) {
        final int MAX_CONTEXT_LENGTH = 160000; // 设置合理的上下文最大长度
        final int KEEP_LAST_CHAPTERS = 5; // 保留最近几章的详细内容
        
        if (context.length() <= MAX_CONTEXT_LENGTH) {
            return; // 未超过限制，无需处理
        }
        
        log.info("[Compose][Serial] 上下文长度超出限制 ({} > {}), 启用智能窗口管理", 
                context.length(), MAX_CONTEXT_LENGTH);
        
        // 查找章节分隔标记，提取各章节内容
        String contextStr = context.toString();
        String[] sections = contextStr.split("==== 第\\d+章 ====");
        
        if (sections.length <= KEEP_LAST_CHAPTERS + 1) {
            // 章节数量不多，但总长度超限，需要压缩内容
            String header = sections[0]; // 保留小说基本信息
            
            // 如果header太长，需要截断
            if (header.length() > MAX_CONTEXT_LENGTH / 3) {
                header = header.substring(0, MAX_CONTEXT_LENGTH / 3) + "\n...(部分内容省略)...\n";
            }
            
            // 重建上下文，只保留头部信息和最后N章
            context.setLength(0);
            context.append(header);
            for (int i = Math.max(1, sections.length - KEEP_LAST_CHAPTERS); i < sections.length; i++) {
                context.append("==== 第").append(i).append("章 ====");
                context.append(sections[i]);
            }
        } else {
            // 章节数量超过保留限制，只保留前文概要和最近N章
            String header = sections[0]; // 小说基本信息
            
            // 创建前文概要
            StringBuilder summary = new StringBuilder(header);
            summary.append("\n\n==== 前文概要 ====\n");
            for (int i = 1; i <= sections.length - KEEP_LAST_CHAPTERS - 1; i++) {
                // 只保留每章的摘要部分
                String section = sections[i];
                String[] lines = section.split("\n");
                for (String line : lines) {
                    if (line.startsWith("摘要:")) {
                        summary.append("第").append(i).append("章").append(line).append("\n");
                        break;
                    }
                }
            }
            
            // 重建上下文：头部 + 前文概要 + 最近N章完整内容
            context.setLength(0);
            context.append(summary.toString());
            for (int i = Math.max(1, sections.length - KEEP_LAST_CHAPTERS); i < sections.length; i++) {
                context.append("==== 第").append(i).append("章 ====");
                context.append(sections[i]);
            }
        }
        
        log.info("[Compose][Serial] 上下文窗口管理完成，新长度: {}", context.length());
    }

    /**
     * 异步保存章节：创建章节并创建一个初始场景，摘要写入summary，正文写入content
     */
    // private void saveChapterAsync(String novelId, String chapterTitle, String outlineSummary, String chapterContent) {
    //     saveChapter(novelId, chapterTitle, outlineSummary, chapterContent).subscribe();
    // }

    private Mono<Void> saveChapter(String novelId, String chapterTitle, String outlineSummary, String chapterContent) {
        try {
            return novelService.addChapterWithInitialScene(novelId, chapterTitle, outlineSummary, "场景 1")
                    .flatMap(info -> novelService.updateSceneContent(novelId, info.getChapterId(), info.getSceneId(), chapterContent))
                    .then();
        } catch (Exception e) {
            log.warn("保存章节失败: {}", e.getMessage());
            return Mono.empty();
        }
    }

    private String defaultChapterTitle(int index) { return "第" + index + "章"; }

    private static class ChapterPiece {
        String title;
        String outline;
        String content;
    }

    // 用于在工具化链路中统一承载提供商信息（公共/私有均可）
    private static class ProviderInfo {
        final String provider;
        final String modelName;
        final String apiKey;
        final String apiEndpoint;
        ProviderInfo(String provider, String modelName, String apiKey, String apiEndpoint) {
            this.provider = provider;
            this.modelName = modelName;
            this.apiKey = apiKey;
            this.apiEndpoint = apiEndpoint;
        }
    }

    /**
     * 尝试从带有 [CHAPTER_i_OUTLINE] / [CHAPTER_i_CONTENT] 标签的文本中解析章节块；
     * 若无标签，则按空行分段作为回退。
     */
    private List<ChapterPiece> parseChapters(String text, int expected) {
        List<ChapterPiece> result = new ArrayList<>();
        if (text == null || text.isEmpty()) return result;

        try {
            // 基于标签的解析
            for (int i = 1; i <= expected; i++) {
                String outlineTag = "[CHAPTER_" + i + "_OUTLINE]";
                String contentTag = "[CHAPTER_" + i + "_CONTENT]";
                int outlinePos = text.indexOf(outlineTag);
                int contentPos = text.indexOf(contentTag);
                int nextOutlinePos = text.indexOf("[CHAPTER_" + (i + 1) + "_OUTLINE]");

                if (outlinePos >= 0 && contentPos >= 0) {
                    int outlineStart = outlinePos + outlineTag.length();
                    int outlineEnd = contentPos;
                    int contentStart = contentPos + contentTag.length();
                    int contentEnd = nextOutlinePos > 0 ? nextOutlinePos : text.length();

                    String outlineText = safeTrim(text.substring(outlineStart, Math.max(outlineStart, outlineEnd)));
                    String contentText = safeTrim(text.substring(contentStart, Math.max(contentStart, contentEnd)));

                    ChapterPiece cp = new ChapterPiece();
                    cp.outline = outlineText;
                    cp.content = contentText;
                    cp.title = defaultChapterTitle(i);
                    result.add(cp);
                }
            }
        } catch (Exception ignore) {
        }

        // 回退：按空行拆成 expected 段，每段第一行做标题，余下作为正文
        if (result.isEmpty()) {
            String[] blocks = text.split("\n\n+");
            List<String> clean = new ArrayList<>();
            for (String b : blocks) {
                String t = b.trim();
                if (!t.isEmpty()) clean.add(t);
                if (clean.size() >= expected) break;
            }
            for (int i = 0; i < clean.size() && i < expected; i++) {
                String block = clean.get(i);
                String[] lines = block.split("\n", 2);
                ChapterPiece cp = new ChapterPiece();
                cp.title = safeTrim(lines[0]);
                cp.content = lines.length > 1 ? safeTrim(lines[1]) : "";
                cp.outline = "";
                result.add(cp);
            }
        }

        if (result.size() > expected) return result.subList(0, expected);
        return result;
    }

    private String safeTrim(String s) { return s == null ? "" : s.trim(); }

    private Mono<UniversalAIRequestDto> ensureNovelIdIfNeeded(UniversalAIRequestDto req) {
        boolean isCompose;
        try { isCompose = AIFeatureType.valueOf(req.getRequestType()) == AIFeatureType.NOVEL_COMPOSE; }
        catch (Exception ignore) { isCompose = false; }
        if (!isCompose) {
            return Mono.just(req);
        }

        // 识别 fork / reuseNovel 标志（默认 fork=true：强制新建小说）
        boolean fork = false;
        // boolean reuseNovel = false;
        try {
            Object f = req.getParameters() != null ? req.getParameters().get("fork") : null;
            // Object r = req.getParameters() != null ? req.getParameters().get("reuseNovel") : null;
            fork = parseBooleanFlag(f).orElse(false); // compose 默认不主动fork，除非前端传入
        } catch (Exception ignore) {}

        Mono<UniversalAIRequestDto> ensureNovelMono;
        if (!fork && req.getNovelId() != null && !req.getNovelId().isEmpty()) {
            ensureNovelMono = Mono.just(req);
        } else {
            // 当 fork=true 或本次未携带 novelId 时，创建草稿
            Novel draft = new Novel();
            draft.setTitle("未命名小说");
            draft.setDescription("自动创建的草稿，用于写作编排");
            Novel.Author author = Novel.Author.builder().id(req.getUserId()).username(req.getUserId()).build();
            draft.setAuthor(author);
            ensureNovelMono = novelService.createNovel(draft)
                    .map(created -> { req.setNovelId(created.getId()); return req; })
                    .onErrorResume(e -> {
                        log.warn("创建草稿小说失败，继续无novelId流程: {}", e.getMessage());
                        return Mono.just(req);
                    });
        }

        // 在编排开始时，将 novelId 绑定到设定会话（优先 settingSessionId，回退使用 sessionId）
        return ensureNovelMono.flatMap(updated -> {
            String settingSessionId = updated.getSettingSessionId();
            String novelId = updated.getNovelId();
            if (novelId == null || novelId.isEmpty()) {
                return Mono.just(updated);
            }
            String sessionIdForBind = (settingSessionId != null && !settingSessionId.isEmpty())
                    ? settingSessionId
                    : updated.getSessionId();
            if (sessionIdForBind == null || sessionIdForBind.isEmpty()) {
                return Mono.just(updated);
            }
            return inMemorySessionManager.getSession(sessionIdForBind)
                    .flatMap(session -> {
                        session.setNovelId(novelId);
                        return inMemorySessionManager.saveSession(session);
                    })
                    .onErrorResume(e -> {
                        log.warn("绑定 novelId 到会话失败: sessionId={}, novelId={}, err={}", sessionIdForBind, novelId, e.getMessage());
                        return Mono.empty();
                    })
                    .thenReturn(updated);
        });
    }

    private java.util.Optional<Boolean> parseBooleanFlag(Object val) {
        if (val == null) return java.util.Optional.empty();
        if (val instanceof Boolean b) return java.util.Optional.of(b);
        if (val instanceof String s) {
            String t = s.trim().toLowerCase();
            if ("true".equals(t) || "1".equals(t) || "yes".equals(t) || "y".equals(t)) return java.util.Optional.of(Boolean.TRUE);
            if ("false".equals(t) || "0".equals(t) || "no".equals(t) || "n".equals(t)) return java.util.Optional.of(Boolean.FALSE);
        }
        return java.util.Optional.empty();
    }

    private Mono<Void> tryConvertSettingsFromSession(UniversalAIRequestDto req) {
        boolean isCompose;
        try { isCompose = AIFeatureType.valueOf(req.getRequestType()) == AIFeatureType.NOVEL_COMPOSE; }
        catch (Exception ignore) { isCompose = false; }
        if (!isCompose) return Mono.empty();
        String novelId = req.getNovelId();
        String sessionId = req.getSettingSessionId();
        if (novelId == null || novelId.isEmpty() || sessionId == null || sessionId.isEmpty()) {
            return Mono.empty();
        }
        return inMemorySessionManager.getSession(sessionId)
                .flatMapMany(session -> {
                    java.util.List<NovelSettingItem> items = settingConversionService.convertSessionToSettingItems(session, novelId);
                    return novelSettingService.saveAll(items);
                })
                .then();
    }

    private String getParam(UniversalAIRequestDto req, String key, String def) {
        if (req.getParameters() != null) {
            Object val = req.getParameters().get(key);
            if (val instanceof String) return (String) val;
        }
        return def;
    }

    private int getIntParam(UniversalAIRequestDto req, String key, int def) {
        if (req.getParameters() != null) {
            Object val = req.getParameters().get(key);
            if (val instanceof Number) return ((Number) val).intValue();
        }
        return def;
    }

    private UniversalAIRequestDto cloneWithParam(UniversalAIRequestDto origin, Map<String, Object> patch) {
        UniversalAIRequestDto clone = UniversalAIRequestDto.builder()
                .requestType(origin.getRequestType())
                .userId(origin.getUserId())
                .sessionId(origin.getSessionId())
                .settingSessionId(origin.getSettingSessionId())
                .novelId(origin.getNovelId())
                .sceneId(origin.getSceneId())
                .chapterId(origin.getChapterId())
                .modelConfigId(origin.getModelConfigId())
                .prompt(origin.getPrompt())
                .instructions(origin.getInstructions())
                .selectedText(origin.getSelectedText())
                .contextSelections(origin.getContextSelections())
                .parameters(origin.getParameters() != null ? new java.util.HashMap<>(origin.getParameters()) : new java.util.HashMap<>())
                .metadata(origin.getMetadata() != null ? new java.util.HashMap<>(origin.getMetadata()) : new java.util.HashMap<>())
                .build();
        clone.getParameters().putAll(patch);
        return clone;
    }

    // 公共模型辅助逻辑已下沉至装饰器层，删除上层判定

    

    // 旧的公共模型文本生成大纲路径已移除（统一走 generateOutlinesWithTools）

    private String resolveModelConfigId(UniversalAIRequestDto req) {
        String modelConfigId = req.getModelConfigId();
        if ((modelConfigId == null || modelConfigId.isEmpty()) && req.getMetadata() != null) {
            Object mid = req.getMetadata().get("modelConfigId");
            if (mid instanceof String s && !s.isEmpty()) {
                modelConfigId = s;
            }
        }
        return modelConfigId;
    }

    // private List<String> parseOutlines(String outlineText, int expected) { /* unused */ return java.util.Collections.emptyList(); }

    /**
     * 构造一个简易的系统片段，插入到合并流中（例如章节大纲/正文的标记）。
     * 仅用于前端消费展示，不影响计费与追踪。
     */
    private UniversalAIResponseDto buildSystemChunk(String requestType, String content) {
        return UniversalAIResponseDto.builder()
                .id(java.util.UUID.randomUUID().toString())
                .requestType(requestType)
                .content(content)
                .finishReason(null)
                .tokenUsage(null)
                .model(null)
                .createdAt(java.time.LocalDateTime.now())
                .metadata(new java.util.HashMap<>())
                .build();
    }

    // 新增：仅通过 metadata 发送结构化数据的系统片段
    private UniversalAIResponseDto buildSystemChunkWithMetadata(String requestType, java.util.Map<String, Object> metadata) {
        java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
        if (metadata != null) meta.putAll(metadata);
        return UniversalAIResponseDto.builder()
                .id(java.util.UUID.randomUUID().toString())
                .requestType(requestType)
                .content("")
                .finishReason(null)
                .tokenUsage(null)
                .model(null)
                .createdAt(java.time.LocalDateTime.now())
                .metadata(meta)
                .build();
    }



    // 新增：将大纲转换为 metadata Map（避免大文本放入content，便于前端通过metadata消费）
    private java.util.Map<String, Object> buildOutlinesMetadata(java.util.List<String> outlines) {
        java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
        java.util.ArrayList<java.util.Map<String, Object>> arr = new java.util.ArrayList<>();
        for (int i = 0; i < outlines.size(); i++) {
            String block = outlines.get(i);
            String title = defaultChapterTitle(i + 1);
            String summary = block;
            java.util.HashMap<String, Object> item = new java.util.HashMap<>();
            item.put("index", i + 1);
            item.put("title", title);
            item.put("summary", summary);
            arr.add(item);
        }
        meta.put("composeOutlines", arr);
        meta.put("composeOutlinesFormat", "json");
        meta.put("composeOutlinesCount", arr.size());
        return meta;
    }

    // 🚀 新增：初始绑定信号（ready=false，告诉前端已绑定但还在生成中）
    private Mono<UniversalAIResponseDto> bindNovelToSessionAndSignalInitial(String novelId, String settingSessionId) {
        if (novelId == null || novelId.isEmpty()) {
            log.info("[Compose] initial bind: no novelId, settingSessionId={}", settingSessionId);
            java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
            meta.put("composeBind", java.util.Map.of("novelId", "", "sessionId", settingSessionId != null ? settingSessionId : ""));
            meta.put("composeBindStatus", "no_novelId");
            meta.put("composeReady", Boolean.FALSE);
            meta.put("composeReadyReason", "no_novelId");
            return Mono.just(buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta));
        }
        if (settingSessionId == null || settingSessionId.isEmpty()) {
            log.info("[Compose] initial bind: no settingSessionId, novelId={}", novelId);
            java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
            meta.put("composeBind", java.util.Map.of("novelId", novelId, "sessionId", ""));
            meta.put("composeBindStatus", "no_session");
            meta.put("composeReady", Boolean.FALSE);
            meta.put("composeReadyReason", "no_session");
            return Mono.just(buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta));
        }
        // 🚀 关键修复：初始绑定只发送 ready=false，表示"已绑定但还在生成中"
        java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
        meta.put("composeBind", java.util.Map.of("novelId", novelId, "sessionId", settingSessionId));
        meta.put("composeBindStatus", "binding");
        meta.put("composeReady", Boolean.FALSE);  // ✅ 关键：告诉前端还在生成中
        meta.put("composeReadyReason", "generating");
        UniversalAIResponseDto chunk = buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta);
        log.info("[Compose] initial bind: emitted initial signal bind={}, status=binding, ready=false", novelId);
        return Mono.just(chunk);
    }

    // 保存完成后，若有settingSessionId则把novelId绑定到会话，并发给前端最终完成信号
    private Mono<UniversalAIResponseDto> bindNovelToSessionAndSignal(String novelId, String settingSessionId) {
        if (novelId == null || novelId.isEmpty()) {
            log.info("[Compose] final bind: no novelId, settingSessionId={}", settingSessionId);
            java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
            meta.put("composeBind", java.util.Map.of("novelId", "", "sessionId", settingSessionId != null ? settingSessionId : ""));
            meta.put("composeBindStatus", "no_novelId");
            meta.put("composeReady", Boolean.FALSE);
            meta.put("composeReadyReason", "no_novelId");
            return Mono.just(buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta));
        }
        if (settingSessionId == null || settingSessionId.isEmpty()) {
            log.info("[Compose] final bind: no settingSessionId, novelId={}", novelId);
            java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
            meta.put("composeBind", java.util.Map.of("novelId", novelId, "sessionId", ""));
            meta.put("composeBindStatus", "no_session");
            meta.put("composeReady", Boolean.FALSE);
            meta.put("composeReadyReason", "no_session");
            return Mono.just(buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta));
        }
        return inMemorySessionManager.getSession(settingSessionId)
                .flatMap(session -> {
                    session.setNovelId(novelId);
                    return inMemorySessionManager.saveSession(session);
                })
                .onErrorResume(e -> {
                    log.warn("[Compose] final bind: failed to save session mapping: sessionId={}, novelId={}, err={}", settingSessionId, novelId, e.getMessage());
                    return Mono.empty();
                })
                .then(Mono.fromSupplier(() -> {
                    java.util.HashMap<String, Object> meta = new java.util.HashMap<>();
                    meta.put("composeBind", java.util.Map.of("novelId", novelId, "sessionId", settingSessionId));
                    meta.put("composeBindStatus", "bound");
                    meta.put("composeReady", Boolean.TRUE);  // ✅ 只有最终信号才设置 ready=true
                    meta.put("composeReadyReason", "ok");
                    UniversalAIResponseDto chunk = buildSystemChunkWithMetadata(AIFeatureType.NOVEL_COMPOSE.name(), meta);
                    try {
                        Map<String, Object> m = chunk.getMetadata();
                        log.info("[Compose] final bind: emitted final signal bind={}, status=bound, ready=true", (m != null ? m.get("composeBind") : null));
                    } catch (Exception ignore) {}
                    return chunk;
                }));
    }

    // ==================== 工具化大纲生成 ====================
    private Mono<List<com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool.OutlineItem>> generateOutlinesWithTools(UniversalAIRequestDto request) {
        // 统一：只依据用户模型配置或默认模型，公共模型/计费由底层装饰器处理
        String modelConfigId = request.getModelConfigId();
        if ((modelConfigId == null || modelConfigId.isEmpty()) && request.getMetadata() != null) {
            Object mid = request.getMetadata().get("modelConfigId");
            if (mid instanceof String s && !s.isEmpty()) modelConfigId = s;
        }
        int chapterCount = getIntParam(request, "chapterCount", 3);
        String contextId = "compose-outline-" + (request.getSessionId() != null ? request.getSessionId() : java.util.UUID.randomUUID());

        Mono<ProviderInfo> providerInfoMono = (modelConfigId != null && !modelConfigId.isEmpty())
                ? novelAIService.getAIModelProviderByConfigId(request.getUserId(), modelConfigId)
                    .map(p -> new ProviderInfo(p.getProviderName(), p.getModelName(), p.getApiKey(), p.getApiEndpoint()))
                    .onErrorResume(err -> {
                        log.warn("[Compose] 用户配置ID无效: {}，回退到用户默认模型", err.getMessage());
                        return novelAIService.getAIModelProvider(request.getUserId(), null)
                                .map(p -> new ProviderInfo(p.getProviderName(), p.getModelName(), p.getApiKey(), p.getApiEndpoint()));
                    })
                : novelAIService.getAIModelProvider(request.getUserId(), null)
                    .map(p -> new ProviderInfo(p.getProviderName(), p.getModelName(), p.getApiKey(), p.getApiEndpoint()));

        return providerInfoMono.flatMap(providerInfo -> {
            String modelName = providerInfo.modelName;
            java.util.Map<String, String> aiConfig = new java.util.HashMap<>();
            aiConfig.put("apiKey", providerInfo.apiKey);
            aiConfig.put("apiEndpoint", providerInfo.apiEndpoint);
            aiConfig.put("provider", providerInfo.provider);
            aiConfig.put("requestType", AIFeatureType.NOVEL_COMPOSE.name());
            aiConfig.put("correlationId", contextId);
            // 不再在业务层打公共计费标记
            // 透传身份信息，供AIRequest写入并被LLMTrace记录
            if (request.getUserId() != null && !request.getUserId().isEmpty()) {
                aiConfig.put("userId", request.getUserId());
            }
            if (request.getSessionId() != null && !request.getSessionId().isEmpty()) {
                aiConfig.put("sessionId", request.getSessionId());
            }

            com.ainovel.server.service.ai.tools.ToolExecutionService.ToolCallContext toolContext = toolExecutionService.createContext(contextId);

            java.util.List<com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool.OutlineItem> captured = new java.util.ArrayList<>();
            com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool.OutlineHandler handler = outlines -> {
                if (outlines == null || outlines.isEmpty()) return false;
                // 截断到期望数量
                java.util.List<com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool.OutlineItem> toAdd = outlines;
                if (toAdd.size() > chapterCount) {
                    toAdd = toAdd.subList(0, chapterCount);
                }
                captured.clear();
                captured.addAll(toAdd);
                return true;
            };
            toolContext.registerTool(new com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool(objectMapper, handler));

            java.util.List<ToolSpecification> toolSpecs = toolRegistry.getSpecificationsForContext(contextId);

            // 构建提示词上下文（支持整棵设定树注入）与历史初始提示（仅当无会话时）
            Mono<String> wholeTreeContextMono = maybeBuildWholeSettingTreeContext(request);
            Mono<String> historyInitPromptMono = maybeGetHistoryInitPromptWhenNoSession(request);
            return reactor.core.publisher.Mono.zip(wholeTreeContextMono, historyInitPromptMono).flatMap(tuple2 -> {
                String ctx = tuple2.getT1();
                String historyInitPrompt = tuple2.getT2();
                try {
                    log.info("[Compose][Context] Outline mode ctx.length={}, historyInitPrompt.length={}",
                            (ctx != null ? ctx.length() : -1), (historyInitPrompt != null ? historyInitPrompt.length() : -1));
                } catch (Exception ignore) {}
                java.util.Map<String, Object> promptParams = new java.util.HashMap<>();
                if (request.getParameters() != null) promptParams.putAll(request.getParameters());
                promptParams.put("mode", "outline");
                promptParams.put("chapterCount", chapterCount);
                promptParams.put("novelId", request.getNovelId());
                promptParams.put("userId", request.getUserId());
                
                // 🚀 确保传递用户输入内容
                String inputContent = "";
                if (request.getSelectedText() != null && !request.getSelectedText().isEmpty()) {
                    inputContent = request.getSelectedText();
                } else if (request.getPrompt() != null && !request.getPrompt().isEmpty()) {
                    inputContent = request.getPrompt();
                }
                promptParams.put("input", inputContent);
                
                // 🚀 确保传递用户指令
                if (request.getInstructions() != null && !request.getInstructions().isEmpty()) {
                    promptParams.put("instructions", request.getInstructions());
                }
                
                // 🚀 传递设定树上下文
                if (ctx != null && !ctx.isBlank()) {
                    promptParams.put("context", ctx);
                }
                
                // 🚀 传递历史初始提示词
                if (historyInitPrompt != null && !historyInitPrompt.isBlank()) {
                    promptParams.put("historyInitPrompt", historyInitPrompt);
                }

                String templateId = null;
                try {
                    templateId = getParam(request, "promptTemplateId", "");
                    if (templateId != null && templateId.startsWith("public_")) {
                        templateId = templateId.substring("public_".length());
                    }
                } catch (Exception ignore) {}

                return composePromptProvider.getSystemPrompt(request.getUserId(), promptParams)
                        .zipWith(composePromptProvider.getUserPrompt(request.getUserId(), templateId, promptParams))
                        .flatMap(tuple -> {
                            String systemPrompt = tuple.getT1();
                            String userPrompt = tuple.getT2();
                            java.util.List<ChatMessage> messages = new java.util.ArrayList<>();
                            messages.add(new SystemMessage(systemPrompt));
                            messages.add(new UserMessage(userPrompt));

                            aiConfig.put("toolContextId", contextId);
                            return aiService.executeToolCallLoop(
                                    messages,
                                    toolSpecs,
                                    modelName,
                                    aiConfig.get("apiKey"),
                                    aiConfig.get("apiEndpoint"),
                                    aiConfig,
                                    1
                            ).then(Mono.defer(() -> {
                                if (captured.isEmpty()) {
                                    // 兜底：返回空列表（显式类型）
                                    return Mono.just(
                                        java.util.Collections.<com.ainovel.server.service.compose.tools.BatchCreateOutlinesTool.OutlineItem>emptyList()
                                    );
                                }
                                return Mono.just(captured);
                            }));
                        })
                        .doFinally(signal -> {
                            try { toolContext.close(); } catch (Exception ignore) {}
                        });
            });
        });
    }

    /**
     * 当 includeWholeSettingTree=true 时，构建整棵设定树的可读上下文字符串。
     * 优先从内存会话获取；若不存在，则将 settingSessionId 或 sessionId 当作历史ID从历史记录构建。
     */
    private Mono<String> maybeBuildWholeSettingTreeContext(UniversalAIRequestDto request) {
        boolean includeWholeTree = false;
        try {
            Object flag = request.getParameters() != null ? request.getParameters().get("includeWholeSettingTree") : null;
            includeWholeTree = parseBooleanFlag(flag).orElse(false);
        } catch (Exception ignore) {}
        try { log.info("[Compose][Context] includeWholeSettingTree={} (requestType={})", includeWholeTree, request.getRequestType()); } catch (Exception ignore) {}
        if (!includeWholeTree) {
            return Mono.just("");
        }

        String sid = request.getSettingSessionId() != null && !request.getSettingSessionId().isEmpty()
                ? request.getSettingSessionId()
                : request.getSessionId();
        try { log.info("[Compose][Context] resolve sid for whole-tree: settingSessionId={}, sessionId={}, sid={}", request.getSettingSessionId(), request.getSessionId(), sid); } catch (Exception ignore) {}
        if (sid == null || sid.isEmpty()) {
            return Mono.just("");
        }

        // 优先使用内存会话；失败则回退到历史记录；若会话存在但渲染为空，也回退历史
        return inMemorySessionManager.getSession(sid)
                .flatMap(session -> {
                    try {
                        int nodeCount = session.getGeneratedNodes() != null ? session.getGeneratedNodes().size() : 0;
                        long rootCount = 0;
                        try {
                            rootCount = session.getGeneratedNodes().values().stream()
                                    .filter(n -> n.getParentId() == null)
                                    .count();
                        } catch (Exception ignore) {}
                        log.info("[Compose][Context] Session found for sid={}, nodes={}, roots={}", sid, nodeCount, rootCount);
                    } catch (Exception ignore) {}
                    String ctx = buildReadableSessionTree(session);
                    try { log.info("[Compose][Context] SessionTree length={}", (ctx != null ? ctx.length() : -1)); } catch (Exception ignore) {}
                    if (ctx == null || ctx.isBlank()) {
                        return historyService.getHistoryWithSettings(sid)
                                .map(this::buildReadableHistoryTree)
                                .doOnNext(hctx -> { try { log.info("[Compose][Context] HistoryTree length={}", (hctx != null ? hctx.length() : -1)); } catch (Exception ignore) {} })
                                .defaultIfEmpty("");
                    }
                    return Mono.just(ctx);
                })
                .switchIfEmpty(Mono.defer(() -> {
                    try { log.info("[Compose][Context] Session not found, fallback to history: {}", sid); } catch (Exception ignore) {}
                    return historyService.getHistoryWithSettings(sid)
                            .map(this::buildReadableHistoryTree)
                            .doOnNext(hctx -> { try { log.info("[Compose][Context] HistoryTree length={}", (hctx != null ? hctx.length() : -1)); } catch (Exception ignore) {} })
                            .defaultIfEmpty("");
                }))
                .onErrorResume(err -> { try { log.warn("[Compose][Context] Build whole-tree context failed: {}", err.getMessage(), err); } catch (Exception ignore) {} return Mono.just(""); });
    }

    private String buildReadableSessionTree(SettingGenerationSession session) {
        StringBuilder sb = new StringBuilder();
        // 根节点：parentId == null
        session.getGeneratedNodes().values().stream()
                .filter(n -> n.getParentId() == null)
                .forEach(root -> appendSessionNodeLine(session, root, sb, 0, new java.util.ArrayList<>()))
        ;
        return sb.toString();
    }

    private void appendSessionNodeLine(SettingGenerationSession session, SettingNode node, StringBuilder sb,
                                       int depth, java.util.List<String> ancestors) {
        for (int i = 0; i < depth; i++) sb.append("  ");
        String path = String.join("/", ancestors);
        // 🔧 修复：不再截断描述，保留完整内容
        String oneLineDesc = safeOneLine(node.getDescription(), 99999);
        String typeStr = node.getType() != null ? node.getType().name() : "UNKNOWN";
        if (!path.isEmpty()) {
            sb.append("- ").append(path).append("/").append(node.getName())
              .append(" [").append(typeStr).append("]");
        } else {
            sb.append("- ").append(node.getName()).append(" [").append(typeStr).append("]");
        }
        if (!oneLineDesc.isBlank()) {
            sb.append(": ").append(oneLineDesc);
        }
        sb.append("\n");
        // 子节点
        java.util.List<String> childIds = session.getChildrenIds(node.getId());
        if (childIds != null) {
            ancestors.add(node.getName());
            for (String cid : childIds) {
                SettingNode child = session.getGeneratedNodes().get(cid);
                if (child != null) {
                    appendSessionNodeLine(session, child, sb, depth + 1, ancestors);
                }
            }
            ancestors.remove(ancestors.size() - 1);
        }
    }

    private String buildReadableHistoryTree(HistoryWithSettings history) {
        StringBuilder sb = new StringBuilder();
        java.util.List<SettingNode> roots = history.rootNodes();
        for (SettingNode root : roots) {
            appendHistoryNodeLine(root, sb, 0, new java.util.ArrayList<>());
        }
        return sb.toString();
    }

    private void appendHistoryNodeLine(SettingNode node, StringBuilder sb, int depth, java.util.List<String> ancestors) {
        for (int i = 0; i < depth; i++) sb.append("  ");
        String path = String.join("/", ancestors);
        // 🔧 修复：不再截断描述，保留完整内容
        String oneLineDesc = safeOneLine(node.getDescription(), 99999);
        String typeStr = node.getType() != null ? node.getType().name() : "UNKNOWN";
        if (!path.isEmpty()) {
            sb.append("- ").append(path).append("/").append(node.getName())
              .append(" [").append(typeStr).append("]");
        } else {
            sb.append("- ").append(node.getName()).append(" [").append(typeStr).append("]");
        }
        if (!oneLineDesc.isBlank()) {
            sb.append(": ").append(oneLineDesc);
        }
        sb.append("\n");
        // 历史的 SettingNode 包含 children 列表
        if (node.getChildren() != null && !node.getChildren().isEmpty()) {
            ancestors.add(node.getName());
            for (SettingNode child : node.getChildren()) {
                appendHistoryNodeLine(child, sb, depth + 1, ancestors);
            }
            ancestors.remove(ancestors.size() - 1);
        }
    }

    private String safeOneLine(String text, int maxLen) {
        if (text == null) return "";
        String t = text.replaceAll("\n|\r", " ").trim();
        if (t.length() <= maxLen) return t;
        return t.substring(0, Math.max(0, maxLen - 1)) + "…";
    }

    /**
     * 当无法解析到有效会话（或会话树渲染为空）时，尝试获取历史记录的 initialPrompt 作为补充提示信息。
     * 仅在 outline 阶段读取，并以参数 historyInitPrompt 注入。
     */
    private Mono<String> maybeGetHistoryInitPromptWhenNoSession(UniversalAIRequestDto request) {
        try {
            // 如果显式有 settingSessionId，优先使用会话；仅当会话不存在或不可用时才考虑历史
            String sid = request.getSettingSessionId();
            if (sid != null && !sid.isEmpty()) {
                return inMemorySessionManager.getSession(sid)
                        .map(sess -> {
                            // 有会话则不需要历史初始提示
                            return "";
                        })
                        .switchIfEmpty(Mono.defer(() -> {
                            try { log.info("[Compose][InitPrompt] sessionId={} 不存在，尝试作为historyId读取initialPrompt", sid); } catch (Exception ignore) {}
                            return historyService.getHistoryById(sid)
                                    .map(h -> {
                                        String ip = h.getInitialPrompt();
                                        try { log.info("[Compose][InitPrompt] 从historyId={} 读取initialPrompt.length={}", sid, (ip != null ? ip.length() : -1)); } catch (Exception ignore) {}
                                        return ip != null ? ip : "";
                                    })
                                    .onErrorResume(err -> Mono.just(""));
                        }))
                        .onErrorResume(err -> Mono.just(""));
            }
        } catch (Exception ignore) {}
        return Mono.just("");
    }
}


