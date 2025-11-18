package com.ainovel.server.task.executor;

import com.ainovel.server.domain.model.Novel.Act; // Import Act
import com.ainovel.server.domain.model.Scene; // Import Scene
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.NovelAIService; // Import NovelAIService
// import com.ainovel.server.service.SceneService; // Import SceneService
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.continuecontent.GenerateSingleChapterParameters;
import com.ainovel.server.task.dto.continuecontent.GenerateSingleChapterResult;
import com.ainovel.server.web.dto.CreatedChapterInfo;
import com.ainovel.server.web.dto.GenerateSceneFromSummaryRequest; // Import the request DTO
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
// 引入 DTO
import java.util.concurrent.atomic.AtomicReference; // 用于在lambda中传递sceneId
import reactor.util.function.Tuple2;
import reactor.util.function.Tuples;
import java.util.HashMap;
import java.util.Map;

/**
 * 生成单章摘要和内容的任务执行器 (REQ-TASK-002 子任务)
 * 负责生成一章的摘要和内容，并在完成后触发下一个章节的生成（如果需要）。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class GenerateSingleChapterTaskExecutable implements BackgroundTaskExecutable<GenerateSingleChapterParameters, GenerateSingleChapterResult> {

    private final NovelService novelService;
    private final NovelAIService novelAIService; // Inject NovelAIService
    // private final SceneService sceneService; // Inject SceneService (暂未使用)
    // private final ChapterPersistenceService chapterPersistenceService; // Assume a service to handle chapter creation/updates

    @Override
    public Mono<GenerateSingleChapterResult> execute(TaskContext<GenerateSingleChapterParameters> context) {
        GenerateSingleChapterParameters params = context.getParameters();
        String taskId = context.getTaskId();
        String userId = context.getUserId();
        
        // 增强日志，显示完整索引信息
        log.info("执行 GenerateSingleChapterTask: {}, User: {}, 章节索引: {}/{}, 父任务: {}, 持久化: {}",
                 taskId, userId, params.getChapterIndex(), params.getTotalChapters(), 
                 params.getParentTaskId(), params.isPersistChanges());

        if (userId == null) {
             log.error("Task {} cannot proceed without a userId.", taskId);
             return Mono.error(new IllegalStateException("User ID not available in TaskContext"));
        }

        // 用于在 flatMap 链中传递生成的 chapterId, sceneId 和生成的内容
        AtomicReference<String> generatedChapterIdRef = new AtomicReference<>();
        AtomicReference<String> generatedSceneIdRef = new AtomicReference<>(); 
        AtomicReference<String> generatedSummaryRef = new AtomicReference<>();
        AtomicReference<String> generatedContentRef = new AtomicReference<>(); // 新增：用于存储生成的内容

        // --- 步骤 1: 生成本章摘要并创建章节和初始场景 ---
        return generateSummaryAndInitialChapter(userId, params, context)
            .flatMap((CreatedChapterInfo chapterInfo) -> {
                generatedChapterIdRef.set(chapterInfo.getChapterId());
                generatedSceneIdRef.set(chapterInfo.getSceneId());
                generatedSummaryRef.set(chapterInfo.getGeneratedSummary());
                context.updateProgress("SUMMARY_GENERATED_AND_CHAPTER_CREATED").subscribe();

                String chapterId = chapterInfo.getChapterId();
                String generatedSummary = chapterInfo.getGeneratedSummary();
                
                log.info("任务 {} 第 {} 章摘要生成并创建章节完成，章节ID: {}, 场景ID: {}, 摘要长度: {} 字符",
                        taskId, params.getChapterIndex(), chapterId, chapterInfo.getSceneId(), 
                        generatedSummary != null ? generatedSummary.length() : 0);

                // --- 步骤 2: (可选) 评审环节 ---
                if (params.isRequiresReview()) {
                    log.info("任务 {} 第 {} 章摘要生成完毕，等待评审。章节ID: {}", taskId, params.getChapterIndex(), chapterId);
                    
                    return Mono.just(GenerateSingleChapterResult.builder()
                            .novelId(params.getNovelId())
                            .generatedChapterId(chapterId)
                            .generatedInitialSceneId(chapterInfo.getSceneId())
                            .generatedSummary(generatedSummary)
                            .generatedContent(null)
                            .chapterIndex(params.getChapterIndex())
                            .contentGenerated(false)
                            .contentPersisted(false)
                            .build());
                }

                // --- 步骤 3: 生成本章内容并更新场景 ---
                return generateContentAndUpdateScene(userId, params, chapterId, generatedSceneIdRef.get(), generatedSummary, context)
                    // 修改：直接捕获生成的内容
                    .flatMap(tuple -> {
                        GenerateSingleChapterResult contentResult = tuple.getT1();
                        String generatedContent = tuple.getT2();
                        
                        // 存储生成的内容用于后续传递
                        generatedContentRef.set(generatedContent);
                        
                        log.info("任务 {} 第 {} 章内容生成完成，内容长度: {} 字符", 
                                taskId, params.getChapterIndex(), 
                                generatedContent != null ? generatedContent.length() : 0);
                        
                        context.updateProgress("CONTENT_GENERATED").subscribe();

                        // --- 步骤 4: 准备并提交下一个子任务 (如果需要) ---
                        if (params.getChapterIndex() < params.getTotalChapters()) {
                            // 直接使用内存中的内容，无需再次查询数据库
                            return prepareAndSubmitNextTask(params, generatedSummaryRef.get(), generatedContent, context)
                                   .thenReturn(contentResult);
                        } else {
                            log.info("任务 {} 已完成最后一章 ({}/{}) 的内容生成。章节ID: {}", 
                                    taskId, params.getChapterIndex(), params.getTotalChapters(), chapterId);
                            return Mono.just(contentResult);
                        }
                    });
            })
            .doOnError(e -> log.error("GenerateSingleChapterTask {} 执行失败: {}", taskId, e.getMessage(), e));
    }

    // 修改 generateSummary 以调用新服务方法并返回 ChapterCreationInfo
    private Mono<CreatedChapterInfo> generateSummaryAndInitialChapter(String userId, GenerateSingleChapterParameters params, TaskContext<?> context) {
        log.info("任务 {}: 正在为第 {} 章生成摘要...", context.getTaskId(), params.getChapterIndex());

        Mono<String> summaryMono = novelAIService.generateNextSingleSummaryStream(
                userId,
                params.getNovelId(),
                params.getCurrentContext(),
                params.getAiConfigIdSummary(),
                params.getWritingStyle(),
                params.getSummaryPromptTemplateId(),
                params.getSummaryPublicModelConfigId()
            )
            .filter(chunk -> chunk != null && !chunk.equals("[DONE]") && !chunk.equalsIgnoreCase("heartbeat"))
            .collect(StringBuilder::new, StringBuilder::append)
            .map(StringBuilder::toString)
            .doOnError(e -> log.error("为章节 {} 生成摘要(流式)时出错: {}", params.getChapterIndex(), e.getMessage(), e));

        return summaryMono
            .flatMap((String summary) -> {
                log.info("任务 {}: 摘要生成成功，长度: {} 字符", context.getTaskId(), summary.length());
                
                if (params.isPersistChanges()) {
                    log.info("任务 {}: 持久化摘要并创建章节和初始场景 (章节索引 {})", context.getTaskId(), params.getChapterIndex());
                    
                    // 先获取小说，以确定已有章节数量
                    return novelService.findNovelById(params.getNovelId())
                        .flatMap(novel -> {
                            // 计算当前小说已有的总章节数
                            int existingChaptersCount = 0;
                            if (novel.getStructure() != null && novel.getStructure().getActs() != null) {
                                for (Act act : novel.getStructure().getActs()) {
                                    if (act.getChapters() != null) {
                                        existingChaptersCount += act.getChapters().size();
                                    }
                                }
                            }
                            
                            // 新章节的编号 = 已有章节数 + 当前任务的章节索引
                            int newChapterNumber = existingChaptersCount + params.getChapterIndex();
                            String chapterTitle = "第 " + newChapterNumber + " 章";
                            String sceneTitle = chapterTitle + " - 场景 1";
                            
                            log.info("任务 {}: 创建第 {} 章 (当前小说已有 {} 章)", 
                                    context.getTaskId(), newChapterNumber, existingChaptersCount);
                            
                            // 在调用 addChapterWithInitialScene 之前，添加自动生成标记
                            Map<String, Object> metadata = new HashMap<>();
                            metadata.put("isAutoGenerated", true);
                            metadata.put("generatedTimestamp", System.currentTimeMillis());
                            metadata.put("generatedByTask", context.getTaskId());
                            metadata.put("generatedByUserId", userId);
                            
                            // 修改 service 方法调用
                            return novelService.addChapterWithInitialScene(
                                params.getNovelId(), 
                                chapterTitle, 
                                summary, 
                                sceneTitle,
                                metadata // 添加元数据参数
                            );
                        });
                } else {
                    log.info("任务 {}: 跳过持久化 (章节索引 {})", context.getTaskId(), params.getChapterIndex());
                    // 如果不持久化，需要生成临时的 chapterId 和 sceneId
                    String tempChapterId = "temp-chapter-" + params.getNovelId() + "-" + params.getChapterIndex() + "-" + System.currentTimeMillis();
                    String tempSceneId = "temp-scene-" + tempChapterId + "-1";
                    return Mono.just(new CreatedChapterInfo(tempChapterId, tempSceneId, summary));
                }
            })
            .onErrorResume(e -> {
                log.error("任务 {}: 摘要生成及章节创建处理失败: {}", context.getTaskId(), e.getMessage(), e);
                return Mono.error(new RuntimeException("生成章节摘要或创建章节失败: " + e.getMessage(), e));
            });
    }

    // 修改 generateContent 以调用新服务方法并返回 GenerateSingleChapterResult
    private Mono<Tuple2<GenerateSingleChapterResult, String>> generateContentAndUpdateScene(
            String userId, GenerateSingleChapterParameters params, String chapterId, 
            String sceneId, String summary, TaskContext<?> context) {
        
        boolean canPersist = params.isPersistChanges() && !chapterId.startsWith("temp-chapter-");
        log.info("任务 {}: 正在为章节 {} (场景 {}, 索引 {}) 生成内容... Persist={}", 
                context.getTaskId(), chapterId, sceneId, params.getChapterIndex(), canPersist);
        
        // 当前将上下文拼接作为AI输入由 NovelAIService 内部处理，无需在此变量中复用

        GenerateSceneFromSummaryRequest aiRequestDto = new GenerateSceneFromSummaryRequest();
        aiRequestDto.setChapterId(chapterId);
        aiRequestDto.setSceneId(sceneId);
        aiRequestDto.setSummary(summary);
        aiRequestDto.setAdditionalInstructions(params.getWritingStyle());
        // 指定内容阶段的模型配置
        aiRequestDto.setAiConfigId(params.getAiConfigIdContent());
        // 指定内容阶段的提示词模板ID（可选）
        if (params.getContentPromptTemplateId() != null && !params.getContentPromptTemplateId().isBlank()) {
            aiRequestDto.setPromptTemplateId(params.getContentPromptTemplateId());
        }
        // 设置内容阶段的公共模型配置ID（如果有）
        if (params.getContentPublicModelConfigId() != null && !params.getContentPublicModelConfigId().isBlank()) {
            aiRequestDto.setPublicModelConfigId(params.getContentPublicModelConfigId());
        }

        Mono<String> contentMono = novelAIService.generateSceneFromSummaryStream(userId, params.getNovelId(), aiRequestDto)
            .filter(chunk -> !"[DONE]".equals(chunk) && !"heartbeat".equals(chunk))
            .collect(StringBuilder::new, StringBuilder::append)
            .map(StringBuilder::toString)
            .doOnNext(content -> {
                // 仅打印长度，避免正文泄露
                if (content != null && !content.isEmpty()) {
                    log.info("任务 {}: AI成功生成内容，总长度: {} 字符", context.getTaskId(), content.length());
                } else {
                    log.warn("任务 {}: AI生成的内容为空或null", context.getTaskId());
                }
            })
            .doOnError(e -> log.error("AI内容生成失败: {}", e.getMessage()));

        return contentMono
            .flatMap(content -> {
                log.info("任务 {}: 内容生成成功，长度: {} 字符", context.getTaskId(), content.length());
                Mono<Scene> scenePersistenceMono;

                if (canPersist) {
                    log.info("任务 {}: 持久化场景 {} 的内容 (长度: {} 字符)。", 
                            context.getTaskId(), sceneId, content.length());
                    // 调用Service方法更新场景内容
                    scenePersistenceMono = novelService.updateSceneContent(params.getNovelId(), chapterId, sceneId, content)
                        .doOnSuccess(savedScene -> {
                            log.info("任务 {}: 场景 {} 内容成功保存到数据库", context.getTaskId(), sceneId);
                        })
                        .doOnError(e -> {
                            log.error("任务 {}: 保存场景 {} 内容失败: {}", 
                                    context.getTaskId(), sceneId, e.getMessage(), e);
                        });
                } else {
                    log.info("任务 {}: 跳过内容持久化 (场景 {})", context.getTaskId(), sceneId);
                    scenePersistenceMono = Mono.empty();
                }

                return scenePersistenceMono
                    .map(savedScene -> true)
                    .defaultIfEmpty(false)
                    .map(contentWasPersisted -> {
                        try {
                            log.info("[BUILD RESULT] taskId={} chapterId={} sceneId={} persisted={} contentLen={}",
                                    context.getTaskId(), chapterId, sceneId, contentWasPersisted, content != null ? content.length() : -1);
                        } catch (Throwable ignore) {}
                        // 构建结果DTO + 生成的内容作为元组返回
                        GenerateSingleChapterResult result = GenerateSingleChapterResult.builder()
                            .novelId(params.getNovelId())
                            .generatedChapterId(chapterId)
                            .generatedInitialSceneId(sceneId)
                            .generatedSummary(summary)
                            .generatedContent(content)
                            .contentGenerated(true)
                            .contentPersisted(contentWasPersisted)
                            .chapterIndex(params.getChapterIndex())
                            .build();
                            
                        return Tuples.of(result, content); // 返回元组包含结果和内容
                    });
            })
            .onErrorResume(e -> {
                log.error("任务 {}: 内容生成或更新处理失败: {}", context.getTaskId(), e.getMessage(), e);
                return Mono.error(new RuntimeException("生成或更新场景内容失败: " + e.getMessage(), e));
            });
    }

    // 调整 prepareAndSubmitNextTask 以接收实际生成的内容
     private Mono<String> prepareAndSubmitNextTask(
             GenerateSingleChapterParameters currentParams, 
             String generatedSummary, 
             String actualGeneratedContent, 
             TaskContext<?> context) {
        
        int nextChapterIndex = currentParams.getChapterIndex() + 1;
        log.info("任务 {}: 准备提交下一个章节任务 (索引 {}/{}) 上下文长度: 摘要={}, 内容={}",
                context.getTaskId(), nextChapterIndex, currentParams.getTotalChapters(),
                generatedSummary != null ? generatedSummary.length() : 0,
                actualGeneratedContent != null ? actualGeneratedContent.length() : 0);

        String nextContext = manageContextWindow(
            currentParams.getCurrentContext(),
            currentParams.getChapterIndex(),
            generatedSummary,
            actualGeneratedContent // 使用内存中的实际内容
        );

        GenerateSingleChapterParameters nextParams = GenerateSingleChapterParameters.builder()
                .novelId(currentParams.getNovelId())
                .chapterIndex(nextChapterIndex)
                .totalChapters(currentParams.getTotalChapters())
                .aiConfigIdSummary(currentParams.getAiConfigIdSummary())
                .aiConfigIdContent(currentParams.getAiConfigIdContent())
                .summaryPublicModelConfigId(currentParams.getSummaryPublicModelConfigId())
                .contentPublicModelConfigId(currentParams.getContentPublicModelConfigId())
                .currentContext(nextContext)
                .writingStyle(currentParams.getWritingStyle())
                .requiresReview(currentParams.isRequiresReview())
                .persistChanges(currentParams.isPersistChanges())
                .parentTaskId(currentParams.getParentTaskId())
                .build();
        
        log.info("任务 {}: 准备提交的下一任务参数: novelId={}, 章节索引={}/{}, 上下文长度={}, 父任务={}",
                context.getTaskId(), nextParams.getNovelId(), nextParams.getChapterIndex(), 
                nextParams.getTotalChapters(), nextParams.getCurrentContext().length(),
                nextParams.getParentTaskId());

        return context.submitSubTask("GENERATE_SINGLE_CHAPTER", nextParams)
                .doOnNext(nextTaskId -> log.info("任务 {} 已提交下一个子任务: {} (章节索引 {}/{})", 
                        context.getTaskId(), nextTaskId, nextChapterIndex, currentParams.getTotalChapters()));
    }
    
    /**
     * 智能管理上下文窗口，避免上下文过长超出LLM处理能力
     * 策略: 保留前文摘要+最后N章详细内容
     * @param currentContext 当前上下文
     * @param chapterIndex 当前章节索引
     * @param summary 当前章节摘要
     * @param content 当前章节内容
     * @return 优化后的下一章上下文
     */
    private String manageContextWindow(String currentContext, int chapterIndex, String summary, String content) {
        final int MAX_CONTEXT_LENGTH = 16000; // 设置合理的上下文最大长度
        final int KEEP_LAST_CHAPTERS = 2; // 保留最近几章的详细内容
        
        // 为本章内容添加标记，方便日后识别和截取
        String currentChapterSection = "\n\n==== 上一章 ====\n摘要:\n" + summary + "\n\n内容:\n" + content;
        
        // 如果加入当前章节后仍然在上下文长度限制内，直接返回
        String fullContext = currentContext + currentChapterSection;
        if (fullContext.length() <= MAX_CONTEXT_LENGTH) {
            return fullContext;
        }
        
        log.info("上下文长度超出限制 ({} > {}), 启用智能窗口管理", fullContext.length(), MAX_CONTEXT_LENGTH);
        
        // 查找章节分隔标记，提取各章节内容
        String[] sections = fullContext.split("==== 第\\d+章 ====");
        if (sections.length <= KEEP_LAST_CHAPTERS + 1) {
            // 章节数量不多，但总长度超限，需要压缩前文
            String header = sections[0]; // 保留小说基本信息
            
            // 如果header太长，需要截断
            if (header.length() > MAX_CONTEXT_LENGTH / 3) {
                header = header.substring(0, MAX_CONTEXT_LENGTH / 3) + "\n...(部分内容省略)...\n";
            }
            
            // 重建上下文，只保留头部信息和最后N章
            StringBuilder optimizedContext = new StringBuilder(header);
            for (int i = Math.max(1, sections.length - KEEP_LAST_CHAPTERS); i < sections.length; i++) {
                optimizedContext.append("==== 第").append(chapterIndex - (sections.length - i)).append("章 ====");
                optimizedContext.append(sections[i]);
            }
            
            return optimizedContext.toString();
        } else {
            // 章节数量超过保留限制，只保留前文概要和最近N章
            String header = sections[0]; // 小说基本信息
            
            // 压缩前面章节为摘要形式
            StringBuilder summaryBuilder = new StringBuilder(header);
            summaryBuilder.append("\n\n==== 前文摘要 ====\n");
            
            // 对早期章节进行摘要，只提取摘要部分(不包含详细内容)
            for (int i = 1; i < sections.length - KEEP_LAST_CHAPTERS; i++) {
                String section = sections[i];
                int summaryEndPos = section.indexOf("\n\n内容:");
                if (summaryEndPos > 0) {
                    // 只保留摘要部分
                    summaryBuilder.append("- 第").append(chapterIndex - (sections.length - i)).append("章: ");
                    summaryBuilder.append(section.substring(section.indexOf("摘要:") + 4, summaryEndPos).trim());
                    summaryBuilder.append("\n");
                }
            }
            
            // 添加最近几章的完整内容
            for (int i = sections.length - KEEP_LAST_CHAPTERS; i < sections.length; i++) {
                summaryBuilder.append("==== 第").append(chapterIndex - (sections.length - i)).append("章 ====");
                summaryBuilder.append(sections[i]);
            }
            
            String result = summaryBuilder.toString();
            
            // 最后检查优化后的长度，如果仍然超限，进行强制截断
            if (result.length() > MAX_CONTEXT_LENGTH) {
                log.warn("优化后上下文仍超过长度限制 ({}), 执行强制截断", result.length());
                // 保留前1/3和后2/3的内容，中间部分省略
                int firstPartLength = MAX_CONTEXT_LENGTH / 3;
                int lastPartLength = (MAX_CONTEXT_LENGTH * 2) / 3;
                result = result.substring(0, firstPartLength) + 
                         "\n\n... (内容过长，中间部分已省略) ...\n\n" + 
                         result.substring(result.length() - lastPartLength);
            }
            
            return result;
        }
    }

    @Override
    public String getTaskType() {
        return "GENERATE_SINGLE_CHAPTER";
    }
} 