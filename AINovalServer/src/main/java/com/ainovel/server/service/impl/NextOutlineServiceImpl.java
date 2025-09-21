package com.ainovel.server.service.impl;

import com.ainovel.server.common.util.PromptUtil;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.NextOutline;
import com.ainovel.server.domain.model.UserAIModelConfig;
import com.ainovel.server.repository.NextOutlineRepository;
import com.ainovel.server.repository.NovelRepository;
import com.ainovel.server.service.NextOutlineService;
import com.ainovel.server.service.NovelAIService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.UserService;
import com.ainovel.server.service.EnhancedUserPromptService;
import com.ainovel.server.web.dto.NextOutlineDTO;
import com.ainovel.server.web.dto.OutlineGenerationChunk;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Collectors;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 剧情推演服务实现
 */
@Slf4j
@Service
public class NextOutlineServiceImpl implements NextOutlineService {

    private final NovelAIService novelAIService;
    private final NextOutlineRepository nextOutlineRepository;
    private final ObjectMapper objectMapper;
    private final EnhancedUserPromptService promptService;

    // 添加用于缓存原始上下文的Map，提高单项刷新的一致性
    private final Map<String, Map<String, Object>> optionContextCache = new ConcurrentHashMap<>();
    
    // 设置上下文最大长度限制
    private static final int MAX_CONTEXT_LENGTH = 10000;

    @Autowired
    private NovelService novelService;

    @Autowired
    private SceneService sceneService;

    @Autowired
    private UserAIModelConfigService userAIModelConfigService;

    /**
     * 设置NovelService（用于测试）
     *
     * @param novelService NovelService
     */
    public void setNovelService(NovelService novelService) {
        this.novelService = novelService;
    }

    /**
     * 设置SceneService（用于测试）
     *
     * @param sceneService SceneService
     */
    public void setSceneService(SceneService sceneService) {
        this.sceneService = sceneService;
    }

    @Autowired
    public NextOutlineServiceImpl(NovelAIService novelAIService, NextOutlineRepository nextOutlineRepository, ObjectMapper objectMapper, EnhancedUserPromptService promptService) {
        this.novelAIService = novelAIService;
        this.nextOutlineRepository = nextOutlineRepository;
        this.objectMapper = objectMapper;
        this.promptService = promptService;
    }

    @Override
    public Mono<NextOutlineDTO.GenerateResponse> generateNextOutlines(String novelId, NextOutlineDTO.GenerateRequest request) {
        log.info("非流式生成剧情大纲: novelId={}, targetChapter={}, numOptions={}, startChapter={}, endChapter={}",
                novelId, request.getTargetChapter(), request.getNumOptions(), request.getStartChapterId(), request.getEndChapterId());

        return getCurrentUserId()
                .flatMap(userId -> {
                    return userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                            .defaultIfEmpty(UserAIModelConfig.builder().build())
                            .flatMap(userConfig -> {
                                Mono<AIResponse> aiResponseMono;
                                if (request.getStartChapterId() != null || request.getEndChapterId() != null) {
                                    log.warn("非流式生成暂不支持章节范围，将尝试使用 targetChapter 作为上下文");
                                    aiResponseMono = novelAIService.generateNextOutlines(
                                            novelId,
                                            request.getTargetChapter(),
                                            request.getNumOptions(),
                                            request.getAuthorGuidance()
                                    );
                                } else {
                                    aiResponseMono = novelAIService.generateNextOutlines(
                                            novelId,
                                            request.getTargetChapter(),
                                            request.getNumOptions(),
                                            request.getAuthorGuidance()
                                    );
                                }

                                return aiResponseMono.flatMap(aiResponse -> {
                                    log.info("AI生成剧情大纲成功: {}", aiResponse.getContent());
                                    return parseAIResponseToOutlines(aiResponse, novelId, userId, request.getStartChapterId(), request.getEndChapterId(), request.getAuthorGuidance())
                                            .flatMap(outlines -> {
                                                return saveOutlines(outlines)
                                                        .thenReturn(outlines);
                                            })
                                            .map(outlines -> {
                                                List<NextOutlineDTO.OutlineItem> outlineItems = outlines.stream()
                                                        .map(this::convertToOutlineItem)
                                                        .collect(Collectors.toList());
                                                return NextOutlineDTO.GenerateResponse.builder()
                                                        .outlines(outlineItems)
                                                        .build();
                                            });
                                });
                            });
                });
    }

    @Override
    public Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, NextOutlineDTO.GenerateRequest request) {
        log.info("流式生成剧情大纲: novelId={}, numOptions={}, startChapterId={}, endChapterId={}, targetChapter={}",
                novelId, request.getNumOptions(), request.getStartChapterId(), request.getEndChapterId(), request.getTargetChapter());

        Integer numOptions = request.getNumOptions();
        String authorGuidanceInput = request.getAuthorGuidance() != null ? request.getAuthorGuidance() : "";
        String startChapterId = request.getStartChapterId();
        String endChapterId = request.getEndChapterId();
        List<String> selectedConfigIds = request.getSelectedConfigIds();


        // 1. 获取基础提示词模板
        Mono<String> promptTemplateMono = promptService.getNextChapterOutlineGenerationPrompt();

        // 2. 获取上下文摘要 (contextSummary)
        // 首先确定用于摘要的实际起止章节ID
        String actualSummaryStart = startChapterId;
        String actualSummaryEnd = endChapterId;

        if (actualSummaryStart == null) {
            // 仅提供了结束章节ID，将其同时用作摘要的开始和结束，以获取单个章节的摘要
            log.debug("流式生成剧情大纲: 仅提供 endChapterId ({}) 用于摘要，将用其作为摘要范围的起止点", actualSummaryEnd);
            actualSummaryStart = actualSummaryEnd;
        }
        // 其他情况: 
        // - 如果 actualSummaryStart 和 actualSummaryEnd 都被提供，则直接使用它们定义的范围。
        // - 如果提供了 actualSummaryStart 但 actualSummaryEnd 为 null, novelService.getChapterRangeSummaries 应该能处理（例如，摘要到小说末尾）。
        // - 如果所有相关ID都为null (startChapterId, endChapterId, targetChapterForSummary), 
        //   那么 actualSummaryStart 和 actualSummaryEnd 将为null, novelService.getChapterRangeSummaries 应该能处理（例如，返回空摘要或整个小说的摘要）。

        final String finalActualSummaryStart = actualSummaryStart;
        final String finalActualSummaryEnd = actualSummaryEnd;
        
        Mono<String> contextSummaryMono = novelService.getChapterRangeSummaries(novelId, finalActualSummaryStart, finalActualSummaryEnd)
            .defaultIfEmpty("") // 如果没有摘要，提供空字符串
            .doOnNext(summary -> {
                if (summary.length() > MAX_CONTEXT_LENGTH / 2) { // 假设摘要占提示词一半长度
                    log.warn("章节摘要可能过长 ({})，考虑截断或优化摘要逻辑: novelId={}, start={}, end={}",
                        summary.length(), novelId, finalActualSummaryStart, finalActualSummaryEnd); // 使用 final 变量
                }
            });

        // 3. 获取上一章节完整内容 (previousChapterContent)
        // 我们将 endChapterId 视为"上一章"的ID。如果未提供，则这部分内容可能为空。
        final Mono<String> finalPreviousChapterContentMono;
        final String effectivePreviousChapterId = endChapterId; // 使用 endChapterId 作为上一章的ID

        if (effectivePreviousChapterId != null && !effectivePreviousChapterId.isEmpty()) {
            finalPreviousChapterContentMono = novelService.getChapterRangeContext(novelId, effectivePreviousChapterId, effectivePreviousChapterId)
                .defaultIfEmpty("") // 如果没有内容，提供空字符串
                .doOnNext(content -> {
                     if (content.length() > MAX_CONTEXT_LENGTH * 2) { // 允许上一章内容更长一些
                        log.warn("上一章节内容非常长 ({})，可能影响AI处理时间和token消耗: novelId={}, chapterId={}",
                            content.length(), novelId, effectivePreviousChapterId);
                    }
                });
        } else {
             log.warn("未提供 endChapterId (上一章ID)，'previousChapterContent' 将为空。AI可能缺乏足够的文风参考。 novelId={}", novelId);
             finalPreviousChapterContentMono = Mono.just(""); // 默认空字符串
        }

        return getCurrentUserId().flatMapMany(userId ->
            Mono.zip(promptTemplateMono, contextSummaryMono, finalPreviousChapterContentMono) // 使用 final 版本
                .flatMapMany(tuple -> {
                    String template = tuple.getT1();
                    String contextSummary = tuple.getT2();
                    String previousChapterContent = tuple.getT3();

                    String finalAuthorGuidance = template
                        .replace("{{numberOfOptions}}", String.valueOf(numOptions))
                        .replace("{{contextSummary}}", contextSummary)
                        .replace("{{previousChapterContent}}", PromptUtil.extractPlainTextFromRichText(previousChapterContent))
                        .replace("{{authorGuidance}}", authorGuidanceInput);
                    
                    log.debug("构建的剧情推演提示词 (部分内容已省略): " + 
                             "Template used: next_chapter_outline_generation, " +
                             "ContextSummary length: {}, PreviousChapterContent length: {}, AuthorGuidanceInput length: {}", 
                             contextSummary.length(), previousChapterContent.length(), authorGuidanceInput.length());
                    if (finalAuthorGuidance.length() > 20000) {
                        log.warn("最终构建的提示词非常长 ({})，可能超出模型限制或导致性能问题。", finalAuthorGuidance.length());
                    }

                    Flux<OutlineGenerationChunk> generationStream;
                    generationStream = novelAIService.generateNextOutlinesStream(
                            novelId,
                            startChapterId,
                            endChapterId,
                            numOptions,
                            finalAuthorGuidance,
                            selectedConfigIds
                    );

                    Map<String, NextOutline> pendingOutlines = new ConcurrentHashMap<>();

                    return generationStream
                        .doOnNext(chunk -> {
                            if (!pendingOutlines.containsKey(chunk.getOptionId())) {
                                NextOutline outline = NextOutline.builder()
                                    .id(chunk.getOptionId())
                                    .novelId(novelId)
                                    .title(chunk.getOptionTitle())
                                    .content("")
                                    .createdAt(LocalDateTime.now())
                                    .selected(false)
                                    .originalStartChapterId(startChapterId)
                                    .originalEndChapterId(endChapterId)
                                    .originalAuthorGuidance(authorGuidanceInput)
                                    .build();
                                pendingOutlines.put(chunk.getOptionId(), outline);
                                
                                Map<String, Object> contextMap = new ConcurrentHashMap<>();
                                contextMap.put("novelId", novelId);
                                contextMap.put("userId", userId);
                                contextMap.put("originalStartChapterId", startChapterId);
                                contextMap.put("originalEndChapterId", endChapterId);
                                contextMap.put("originalAuthorGuidance", authorGuidanceInput);
                                contextMap.put("selectedConfigIds", selectedConfigIds != null ? new ArrayList<>(selectedConfigIds) : null);
                                contextMap.put("numOptions", numOptions);
                                contextMap.put("timestamp", System.currentTimeMillis());
                                optionContextCache.put(chunk.getOptionId(), contextMap);
                                
                                scheduleContextCacheCleaning(chunk.getOptionId());
                            } else {
                                NextOutline existing = pendingOutlines.get(chunk.getOptionId());
                                if (chunk.getOptionTitle() != null && !chunk.getOptionTitle().equals(existing.getTitle())) {
                                    existing.setTitle(chunk.getOptionTitle());
                                }
                                existing.setContent(existing.getContent() + chunk.getTextChunk());
                            }

                            if (chunk.isFinalChunk() && chunk.getError() == null) {
                                NextOutline finalOutline = pendingOutlines.remove(chunk.getOptionId());
                                if (finalOutline != null) {
                                    nextOutlineRepository.save(finalOutline)
                                        .subscribe(
                                            saved -> log.debug("流式生成的大纲选项 {} 已保存", saved.getId()),
                                            error -> log.error("保存流式生成的大纲选项 {} 失败: {}", finalOutline.getId(), error.getMessage())
                                        );
                                }
                            }
                        })
                        .doOnError(error -> {
                            log.error("流式生成剧情大纲时出错: {}", error.getMessage(), error);
                            pendingOutlines.clear();
                            optionContextCache.keySet().removeIf(key -> pendingOutlines.containsKey(key));
                        })
                        .doOnComplete(() -> {
                            if (!pendingOutlines.isEmpty()) {
                                log.warn("流处理完成时仍有 {} 个未保存的暂存大纲，将尝试保存...", pendingOutlines.size());
                                Flux.fromIterable(pendingOutlines.values())
                                    .flatMap(nextOutlineRepository::save)
                                    .subscribe(
                                        saved -> log.debug("清理保存暂存大纲 {} 成功", saved.getId()),
                                        error -> log.error("清理保存暂存大纲失败: {}", error.getMessage())
                                    );
                                pendingOutlines.clear();
                            }
                        });
                })
        );
    }

    @Override
    public Mono<NextOutlineDTO.SaveResponse> saveNextOutline(String novelId, NextOutlineDTO.SaveRequest request) {
        log.info("保存剧情大纲: novelId={}, outlineId={}, insertType={}",
                novelId, request.getOutlineId(), request.getInsertType());

        return getCurrentUserId()
                .flatMap(userId -> {
                    return nextOutlineRepository.findById(request.getOutlineId())
                            .switchIfEmpty(Mono.error(new RuntimeException("大纲不存在")))
                            .flatMap(outline -> {
                                outline.setSelected(true);
                                return nextOutlineRepository.save(outline)
                                        .flatMap(savedOutline -> {
                                            String insertType = request.getInsertType();
                                            if (insertType == null) insertType = "NEW_CHAPTER";
                                            switch (insertType) {
                                                case "CHAPTER_END":
                                                    return addSceneToChapterEnd(novelId, savedOutline, request);
                                                case "BEFORE_SCENE":
                                                    return addSceneBeforeTarget(novelId, savedOutline, request);
                                                case "AFTER_SCENE":
                                                    return addSceneAfterTarget(novelId, savedOutline, request);
                                                case "NEW_CHAPTER":
                                                default:
                                                    return createNewChapterAndScene(novelId, savedOutline, request);
                                            }
                                        });
                            });
                });
    }

    @Override
    public Flux<OutlineGenerationChunk> regenerateOutlineOption(String novelId, NextOutlineDTO.RegenerateOptionRequest request) {
        log.info("流式重新生成单个剧情大纲: novelId={}, optionId={}, selectedConfigId={}, hint={}",
                novelId, request.getOptionId(), request.getSelectedConfigId(), request.getRegenerateHint());

        String optionId = request.getOptionId();
        String selectedConfigId = request.getSelectedConfigId();
        String regenerateHint = request.getRegenerateHint() != null ? request.getRegenerateHint() : ""; // 用户提供的额外提示

        return getCurrentUserId()
            .flatMapMany(userId -> {
                // 1. 获取模型配置 (这一步保持不变)
                return userAIModelConfigService.getConfigurationById(userId, selectedConfigId)
                    .switchIfEmpty(Mono.error(new RuntimeException("未找到指定的模型配置: " + selectedConfigId)))
                    .flatMapMany(config -> {
                        // 2. 获取重新生成所需的上下文信息
                        Mono<Map<String, Object>> contextInfoMono;
                        Map<String, Object> cachedContext = optionContextCache.get(optionId);

                        if (cachedContext != null) {
                            log.info("使用缓存的上下文信息重新生成大纲选项 {}", optionId);
                            contextInfoMono = Mono.just(cachedContext);
                        } else {
                            log.warn("选项 {} 的上下文未在缓存中找到，将从数据库回退获取原始参数。", optionId);
                            contextInfoMono = nextOutlineRepository.findById(optionId)
                                .switchIfEmpty(Mono.error(new RuntimeException("未找到指定的大纲选项: " + optionId)))
                                .map(outline -> {
                                    Map<String, Object> dbContext = new ConcurrentHashMap<>();
                                    dbContext.put("novelId", outline.getNovelId()); // 应该与传入的novelId一致
                                    dbContext.put("userId", userId); // 当前用户
                                    dbContext.put("originalStartChapterId", outline.getOriginalStartChapterId());
                                    dbContext.put("originalEndChapterId", outline.getOriginalEndChapterId());
                                    dbContext.put("originalAuthorGuidance", outline.getOriginalAuthorGuidance());
                                    // 从DB加载时，我们没有numOptions和selectedConfigIds，这些来自当前请求
                                    // targetChapter 也可以从outline中获取（如果之前保存了）
                                    // 为了与缓存结构对齐，这里可以不填充 numOptions, selectedConfigIds, targetChapter
                                    // 因为它们主要在首次生成时使用，或由当前regenerateRequest提供
                                    return dbContext;
                                });
                        }

                        return contextInfoMono.flatMapMany(contextInfo -> {
                            String originalStartChapterId = (String) contextInfo.get("originalStartChapterId");
                            String originalEndChapterId = (String) contextInfo.get("originalEndChapterId"); // 这是"上一章"的ID
                            String originalAuthorGuidance = (String) contextInfo.get("originalAuthorGuidance");
                            // numOptions for single regeneration is always 1
                            final int numOptionsForRegen = 1;

                            // 3. 获取提示词模板
                            Mono<String> promptTemplateMono = promptService.getNextChapterOutlineGenerationPrompt();

                            // 4. 获取上下文摘要 (contextSummary)
                            // 与 generateNextOutlinesStream 逻辑类似，但使用 originalStart/EndChapterId
                            final String finalSummaryContextChapterStart;
                            final String finalSummaryContextChapterEnd = originalEndChapterId;

                            if (originalStartChapterId == null && originalEndChapterId != null) {
                                finalSummaryContextChapterStart = originalEndChapterId;
                            } else {
                                finalSummaryContextChapterStart = originalStartChapterId;
                            }
                            // 如果两者都为null，则摘要可能为空或依赖 targetChapter (如果从contextInfo中获取并处理)
                            // 但对于重新生成，我们应该已经有了原始的章节ID。

                            Mono<String> contextSummaryMono = novelService.getChapterRangeSummaries(novelId, finalSummaryContextChapterStart, finalSummaryContextChapterEnd)
                                .defaultIfEmpty("")
                                .doOnNext(summary -> {
                                    if (summary.length() > MAX_CONTEXT_LENGTH / 2) {
                                        log.warn("重新生成：章节摘要可能过长 ({}) novelId={}, start={}, end={}",
                                            summary.length(), novelId, finalSummaryContextChapterStart, finalSummaryContextChapterEnd);
                                    }
                                });

                            // 5. 获取上一章节完整内容 (previousChapterContent)
                            Mono<String> previousChapterContentMono = Mono.just("");
                            if (originalEndChapterId != null && !originalEndChapterId.isEmpty()) {
                                previousChapterContentMono = novelService.getChapterRangeContext(novelId, originalEndChapterId, originalEndChapterId)
                                    .defaultIfEmpty("")
                                    .doOnNext(content -> {
                                        if (content.length() > MAX_CONTEXT_LENGTH * 2) {
                                            log.warn("重新生成：上一章节内容非常长 ({}) novelId={}, chapterId={}",
                                                content.length(), novelId, originalEndChapterId);
                                        }
                                    });
                            } else {
                                log.warn("重新生成：未找到 originalEndChapterId (上一章ID)，'previousChapterContent' 将为空。novelId={}, optionId={}", novelId, optionId);
                            }

                            return Mono.zip(promptTemplateMono, contextSummaryMono, previousChapterContentMono)
                                .flatMapMany(tuple -> {
                                    String template = tuple.getT1();
                                    String contextSummary = tuple.getT2();
                                    String previousChapterContent = tuple.getT3();

                                    // 原始作者引导 + 当前的重新生成提示
                                    String combinedAuthorGuidance = originalAuthorGuidance != null ? originalAuthorGuidance : "";
                                    if (!regenerateHint.isEmpty()) {
                                        combinedAuthorGuidance += "\n\n重新生成指示：" + regenerateHint;
                                    }

                                    String finalPrompt = template
                                        .replace("{{numberOfOptions}}", String.valueOf(numOptionsForRegen)) // 重新生成通常是针对一个选项
                                        .replace("{{contextSummary}}", contextSummary)
                                        .replace("{{previousChapterContent}}", previousChapterContent)
                                        .replace("{{authorGuidance}}", combinedAuthorGuidance);

                                    log.debug("重新构建的剧情推演提示词 (部分内容已省略): optionId={}, Template used: next_chapter_outline_generation, " +
                                            "ContextSummary length: {}, PreviousChapterContent length: {}, CombinedAuthorGuidance length: {}", 
                                            optionId, contextSummary.length(), previousChapterContent.length(), combinedAuthorGuidance.length());
                                     if (finalPrompt.length() > 20000) {
                                        log.warn("重新生成：最终构建的提示词非常长 ({})，可能超出模型限制或导致性能问题。optionId={}", finalPrompt.length(), optionId);
                                    }
                                    
                                    // 调用 NovelAIService 进行重新生成
                                    // 假设 regenerateSingleOutlineStream 的第5个参数 (regenerateHint) 可以接收完整的提示词
                                    // 并且其内部逻辑能够处理好这种情况。或者需要一个新的方法。
                                    // 为了最小化对 NovelAIService 接口的改动，我们在这里将 finalPrompt 放入 regenerateHint 参数。
                                    // originalStartChapterId, originalEndChapterId 仍然传递，供AI服务内部可能需要的精确定位。
                                    return novelAIService.regenerateSingleOutlineStream(
                                        novelId,
                                        optionId,
                                        userId, // 这个userId是当前操作的用户，不一定是原始生成者
                                        selectedConfigId, // 当前请求中选择的configId
                                        finalPrompt, // <--- 放入构建好的完整提示词
                                        originalStartChapterId,
                                        originalEndChapterId,
                                        null // 最后一个参数 originalAuthorGuidance 对于此方法可能不再直接使用，因为已包含在 finalPrompt 中
                                               // 或者 NovelAIService regenerateSingleOutlineStream 的签名需要调整
                                               // 这里暂时传null，并假设 finalPrompt 是主导
                                    )
                                    .doOnNext(chunk -> handleRegenerationChunk(chunk, optionId, request)); // handleRegenerationChunk 保持不变
                                });
                        });
                    })
                    .onErrorResume(e -> {
                        log.error("重新生成大纲选项 {} 时出错: {}", optionId, e.getMessage(), e);
                        return Flux.just(
                            new OutlineGenerationChunk(
                                optionId,
                                "错误",
                                "重新生成失败: " + e.getMessage(),
                                true,
                                e.getMessage()
                            )
                        );
                    });
            });
    }
    
    /**
     * 处理重新生成的chunk
     */
    private void handleRegenerationChunk(OutlineGenerationChunk chunk, String optionId, NextOutlineDTO.RegenerateOptionRequest request) {
        if (chunk.isFinalChunk() && chunk.getError() == null) {
            nextOutlineRepository.findById(optionId)
                .flatMap(outline -> {
                    outline.setConfigId(request.getSelectedConfigId());
                    if (chunk.getOptionTitle() != null) {
                        outline.setTitle(chunk.getOptionTitle());
                    }
                    return nextOutlineRepository.save(outline);
                })
                .subscribe(
                    saved -> log.debug("重新生成后的大纲选项 {} 已更新并保存", optionId),
                    error -> log.error("更新重新生成的大纲选项 {} 失败: {}", optionId, error.getMessage())
                );
        }
    }
    
    /**
     * 设置上下文缓存的超时清理 (30分钟)
     */
    private void scheduleContextCacheCleaning(String optionId) {
        Mono.delay(Duration.ofMinutes(30))
            .subscribe(v -> {
                optionContextCache.remove(optionId);
                log.debug("已清理过期的上下文缓存: optionId={}", optionId);
            });
    }

    /**
     * 解析AI响应，生成大纲列表
     *
     * @param aiResponse AI响应
     * @param novelId 小说ID
     * @param userId 用户ID
     * @param originalStartChapterId 原始起始章节ID
     * @param originalEndChapterId 原始结束章节ID
     * @param originalAuthorGuidance 原始作者引导
     * @return 大纲列表
     */
    private Mono<List<NextOutline>> parseAIResponseToOutlines(AIResponse aiResponse, String novelId, String userId,
                                                            String originalStartChapterId, String originalEndChapterId, String originalAuthorGuidance) {
        try {
            List<NextOutline> outlines = parseJsonResponse(aiResponse.getContent(), novelId, originalStartChapterId, originalEndChapterId, originalAuthorGuidance);
            if (!outlines.isEmpty()) {
                 log.debug("成功解析JSON格式的AI大纲响应");
                 return Mono.just(outlines);
            }
        } catch (Exception e) {
            log.warn("解析JSON格式大纲失败，尝试解析文本格式: {}", e.getMessage());
        }
        List<NextOutline> outlines = parseTextResponse(aiResponse.getContent(), novelId, originalStartChapterId, originalEndChapterId, originalAuthorGuidance);
         log.debug("解析文本格式的AI大纲响应，共 {} 个选项", outlines.size());
        return Mono.just(outlines);
    }

    /**
     * 解析JSON格式的AI响应
     *
     * @param content AI响应内容
     * @param novelId 小说ID
     * @param originalStartChapterId 原始起始章节ID
     * @param originalEndChapterId 原始结束章节ID
     * @param originalAuthorGuidance 原始作者引导
     * @return 大纲列表
     */
    private List<NextOutline> parseJsonResponse(String content, String novelId,
                                                String originalStartChapterId, String originalEndChapterId, String originalAuthorGuidance) throws JsonProcessingException {
        List<NextOutline> outlines = new ArrayList<>();
        /*
        for (Map<String, String> rawOutline : rawOutlines) {
            NextOutline outline = NextOutline.builder()
                    .id(UUID.randomUUID().toString())
                    .novelId(novelId)
                    .title(rawOutline.getOrDefault("title", "剧情选项"))
                    .content(rawOutline.getOrDefault("content", ""))
                    .createdAt(LocalDateTime.now())
                    .selected(false)
                    .originalStartChapterId(originalStartChapterId)
                    .originalEndChapterId(originalEndChapterId)
                    .originalAuthorGuidance(originalAuthorGuidance)
                    .build();
            outlines.add(outline);
        }
        */
        if (outlines.isEmpty() && !content.trim().startsWith("[")) {
             throw new JsonProcessingException("Content does not appear to be a JSON array") {};
        }
        return outlines;
    }

    /**
     * 解析文本格式的AI响应
     *
     * @param content AI响应内容
     * @param novelId 小说ID
     * @param originalStartChapterId 原始起始章节ID
     * @param originalEndChapterId 原始结束章节ID
     * @param originalAuthorGuidance 原始作者引导
     * @return 大纲列表
     */
    private List<NextOutline> parseTextResponse(String content, String novelId,
                                                String originalStartChapterId, String originalEndChapterId, String originalAuthorGuidance) {
        List<NextOutline> outlines = new ArrayList<>();
        String[] sections = content.split("(?im)^\\s*(选项|大纲|剧情选项)\\s*\\d+\\s*[:\\：]\\s*");

        Pattern titlePattern = Pattern.compile("^(选项|大纲|剧情选项)\\s*\\d+\\s*[:\\：]\\s*(.*?)$", Pattern.MULTILINE);
        Matcher titleMatcher = titlePattern.matcher(content);
        List<String> titles = new ArrayList<>();
        while (titleMatcher.find()) {
             titles.add(titleMatcher.group(2).trim());
        }
        
        Pattern titleContentPattern = Pattern.compile("(?im)^\\s*(标题|TITLE|Title)\\s*[:\\：]\\s*(.*?)\\s*(?:\\n|$)\\s*(内容|CONTENT|Content)\\s*[:\\：]\\s*(.+)", Pattern.DOTALL);
        Matcher titleContentMatcher = titleContentPattern.matcher(content);
        
        if (titleContentMatcher.find()) {
            NextOutline outline = NextOutline.builder()
                .id(UUID.randomUUID().toString())
                .novelId(novelId)
                .title(titleContentMatcher.group(2).trim())
                .content(titleContentMatcher.group(4).trim())
                .createdAt(LocalDateTime.now())
                .selected(false)
                .originalStartChapterId(originalStartChapterId)
                .originalEndChapterId(originalEndChapterId)
                .originalAuthorGuidance(originalAuthorGuidance)
                .build();
            outlines.add(outline);
            
            titleContentMatcher.reset();
            int matchCount = 0;
            while (titleContentMatcher.find()) {
                matchCount++;
                if (matchCount > 1) {
                    outline = NextOutline.builder()
                        .id(UUID.randomUUID().toString())
                        .novelId(novelId)
                        .title(titleContentMatcher.group(2).trim())
                        .content(titleContentMatcher.group(4).trim())
                        .createdAt(LocalDateTime.now())
                        .selected(false)
                        .originalStartChapterId(originalStartChapterId)
                        .originalEndChapterId(originalEndChapterId)
                        .originalAuthorGuidance(originalAuthorGuidance)
                        .build();
                    outlines.add(outline);
                }
            }
            
            if (!outlines.isEmpty()) {
                log.info("使用标题-内容格式成功解析 {} 个大纲选项", outlines.size());
                return outlines;
            }
        }
        
        int titleIndex = 0;
        for (int i = 0; i < sections.length; i++) {
            String section = sections[i].trim();
            if (section.isEmpty() || section.matches("^(选项|大纲|剧情选项)\\s*\\d+\\s*[:\\：]")) {
                 continue;
            }

            String title;
            if (titleIndex < titles.size()) {
                 title = titles.get(titleIndex++);
            } else {
                 title = "剧情选项 " + (outlines.size() + 1);
                 log.warn("无法为第 {} 个文本大纲选项提取标题，使用默认标题: {}", outlines.size() + 1, title);
            }
            String outlineContent = section;

            NextOutline outline = NextOutline.builder()
                    .id(UUID.randomUUID().toString())
                    .novelId(novelId)
                    .title(title)
                    .content(outlineContent)
                    .createdAt(LocalDateTime.now())
                    .selected(false)
                    .originalStartChapterId(originalStartChapterId)
                    .originalEndChapterId(originalEndChapterId)
                    .originalAuthorGuidance(originalAuthorGuidance)
                    .build();
            outlines.add(outline);
        }

        if (outlines.isEmpty() && content != null && !content.isBlank()) {
             log.warn("无法按预期分割文本大纲响应，将整个内容视为单个选项");
            
            String title = "剧情选项";
            String contentText = content.trim();
            
            Pattern extractTitlePattern = Pattern.compile("(?im)^\\s*(.*?)\\s*(?:\\n|$)");
            Matcher extractTitleMatcher = extractTitlePattern.matcher(contentText);
            if (extractTitleMatcher.find()) {
                String possibleTitle = extractTitleMatcher.group(1).trim();
                if (possibleTitle.length() <= 50) {
                    title = possibleTitle;
                    contentText = contentText.substring(extractTitleMatcher.end()).trim();
                }
            }
            
            NextOutline outline = NextOutline.builder()
                    .id(UUID.randomUUID().toString())
                    .novelId(novelId)
                    .title(title)
                    .content(contentText)
                    .createdAt(LocalDateTime.now())
                    .selected(false)
                    .originalStartChapterId(originalStartChapterId)
                    .originalEndChapterId(originalEndChapterId)
                    .originalAuthorGuidance(originalAuthorGuidance)
                    .build();
            outlines.add(outline);
        }
        return outlines;
    }

    /**
     * 保存大纲列表
     *
     * @param outlines 大纲列表
     * @return 完成信号
     */
    private Mono<Void> saveOutlines(List<NextOutline> outlines) {
        return Mono.when(
                outlines.stream()
                        .map(nextOutlineRepository::save)
                        .collect(Collectors.toList())
        );
    }

    /**
     * 将大纲转换为DTO
     *
     * @param outline 大纲
     * @return 大纲DTO
     */
    private NextOutlineDTO.OutlineItem convertToOutlineItem(NextOutline outline) {
        return NextOutlineDTO.OutlineItem.builder()
                .id(outline.getId())
                .title(outline.getTitle())
                .content(outline.getContent())
                .isSelected(outline.isSelected())
                .configId(outline.getConfigId())
                .build();
    }

    /**
     * 获取当前用户ID
     *
     * @return 当前用户ID
     */
    private Mono<String> getCurrentUserId() {
        return ReactiveSecurityContextHolder.getContext()
                .map(SecurityContext::getAuthentication)
                .filter(Authentication::isAuthenticated)
                .map(Authentication::getPrincipal)
                .cast(com.ainovel.server.domain.model.User.class)
                .map(com.ainovel.server.domain.model.User::getId)
                .switchIfEmpty(Mono.error(new RuntimeException("用户未登录")));
    }

    /**
     * 创建新章节和场景
     *
     * @param novelId 小说ID
     * @param outline 大纲
     * @param request 保存请求
     * @return 保存响应
     */
    private Mono<NextOutlineDTO.SaveResponse> createNewChapterAndScene(String novelId, NextOutline outline, NextOutlineDTO.SaveRequest request) {
        return novelService.findNovelById(novelId)
                .flatMap(novel -> {
                    String actId;
                    if (novel.getStructure() == null || novel.getStructure().getActs() == null || novel.getStructure().getActs().isEmpty()) {
                        return novelService.addAct(novelId, "第一卷", null)
                                .flatMap(updatedNovel -> {
                                    String newActId = updatedNovel.getStructure().getActs().get(0).getId();
                                    return novelService.addChapter(novelId, newActId, outline.getTitle(), null);
                                })
                                .flatMap(updatedNovel -> {
                                    String newChapterId = updatedNovel.getStructure().getActs().get(0).getChapters().get(0).getId();
                                    if (request.isCreateNewScene()) {
                                        return sceneService.addScene(novelId, newChapterId, outline.getTitle(), outline.getContent(), null, null)
                                                .map(scene -> {
                                                    return NextOutlineDTO.SaveResponse.builder()
                                                            .success(true)
                                                            .outlineId(outline.getId())
                                                            .newChapterId(newChapterId)
                                                            .newSceneId(scene.getId())
                                                            .insertType("NEW_CHAPTER")
                                                            .outlineTitle(outline.getTitle())
                                                            .build();
                                                });
                                    } else {
                                        return Mono.just(NextOutlineDTO.SaveResponse.builder()
                                                .success(true)
                                                .outlineId(outline.getId())
                                                .newChapterId(newChapterId)
                                                .insertType("NEW_CHAPTER")
                                                .outlineTitle(outline.getTitle())
                                                .build());
                                    }
                                });
                    } else {
                        actId = novel.getStructure().getActs().get(0).getId();
                        return novelService.addChapter(novelId, actId, outline.getTitle(), null)
                                .flatMap(updatedNovel -> {
                                    String newChapterId = null;
                                    for (var act : updatedNovel.getStructure().getActs()) {
                                        if (act.getId().equals(actId)) {
                                            int lastIndex = act.getChapters().size() - 1;
                                            newChapterId = act.getChapters().get(lastIndex).getId();
                                            break;
                                        }
                                    }
                                    if (newChapterId == null) {
                                        return Mono.error(new RuntimeException("新章节创建失败"));
                                    }
                                    final String chapterId = newChapterId;
                                    if (request.isCreateNewScene()) {
                                        return sceneService.addScene(novelId, chapterId, outline.getTitle(), outline.getContent(), null, null)
                                                .map(scene -> {
                                                    return NextOutlineDTO.SaveResponse.builder()
                                                            .success(true)
                                                            .outlineId(outline.getId())
                                                            .newChapterId(chapterId)
                                                            .newSceneId(scene.getId())
                                                            .insertType("NEW_CHAPTER")
                                                            .outlineTitle(outline.getTitle())
                                                            .build();
                                                });
                                    } else {
                                        return Mono.just(NextOutlineDTO.SaveResponse.builder()
                                                .success(true)
                                                .outlineId(outline.getId())
                                                .newChapterId(newChapterId)
                                                .insertType("NEW_CHAPTER")
                                                .outlineTitle(outline.getTitle())
                                                .build());
                                    }
                                });
                    }
                });
    }

    /**
     * 在现有章节末尾添加场景
     *
     * @param novelId 小说ID
     * @param outline 大纲
     * @param request 保存请求
     * @return 保存响应
     */
    private Mono<NextOutlineDTO.SaveResponse> addSceneToChapterEnd(String novelId, NextOutline outline, NextOutlineDTO.SaveRequest request) {
        if (request.getTargetChapterId() == null || request.getTargetChapterId().isEmpty()) {
            return Mono.error(new RuntimeException("目标章节ID不能为空"));
        }
        return sceneService.addScene(novelId, request.getTargetChapterId(), outline.getTitle(), outline.getContent(), null, null)
                .map(scene -> {
                    return NextOutlineDTO.SaveResponse.builder()
                            .success(true)
                            .outlineId(outline.getId())
                            .targetChapterId(request.getTargetChapterId())
                            .newSceneId(scene.getId())
                            .insertType("CHAPTER_END")
                            .outlineTitle(outline.getTitle())
                            .build();
                });
    }

    /**
     * 在指定场景之前添加场景
     *
     * @param novelId 小说ID
     * @param outline 大纲
     * @param request 保存请求
     * @return 保存响应
     */
    private Mono<NextOutlineDTO.SaveResponse> addSceneBeforeTarget(String novelId, NextOutline outline, NextOutlineDTO.SaveRequest request) {
        if (request.getTargetSceneId() == null || request.getTargetSceneId().isEmpty()) {
            return Mono.error(new RuntimeException("目标场景ID不能为空"));
        }
        return sceneService.findSceneById(request.getTargetSceneId())
                .flatMap(targetScene -> {
                    int targetPosition = targetScene.getSequence();
                    return sceneService.addScene(novelId, targetScene.getChapterId(), outline.getTitle(), outline.getContent(), null, targetPosition)
                            .map(scene -> {
                                return NextOutlineDTO.SaveResponse.builder()
                                        .success(true)
                                        .outlineId(outline.getId())
                                        .targetChapterId(targetScene.getChapterId())
                                        .targetSceneId(request.getTargetSceneId())
                                        .newSceneId(scene.getId())
                                        .insertType("BEFORE_SCENE")
                                        .outlineTitle(outline.getTitle())
                                        .build();
                            });
                });
    }

    /**
     * 在指定场景之后添加场景
     *
     * @param novelId 小说ID
     * @param outline 大纲
     * @param request 保存请求
     * @return 保存响应
     */
    private Mono<NextOutlineDTO.SaveResponse> addSceneAfterTarget(String novelId, NextOutline outline, NextOutlineDTO.SaveRequest request) {
        if (request.getTargetSceneId() == null || request.getTargetSceneId().isEmpty()) {
            return Mono.error(new RuntimeException("目标场景ID不能为空"));
        }
        return sceneService.findSceneById(request.getTargetSceneId())
                .flatMap(targetScene -> {
                    int targetPosition = targetScene.getSequence() + 1;
                    return sceneService.addScene(novelId, targetScene.getChapterId(), outline.getTitle(), outline.getContent(), null, targetPosition)
                            .map(scene -> {
                                return NextOutlineDTO.SaveResponse.builder()
                                        .success(true)
                                        .outlineId(outline.getId())
                                        .targetChapterId(targetScene.getChapterId())
                                        .targetSceneId(request.getTargetSceneId())
                                        .newSceneId(scene.getId())
                                        .insertType("AFTER_SCENE")
                                        .outlineTitle(outline.getTitle())
                                        .build();
                            });
                });
    }
}
