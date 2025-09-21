package com.ainovel.server.task.executor;

import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Novel.Act;
import com.ainovel.server.domain.model.Novel.Chapter;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentParameters;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentProgress;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentResult;
import com.ainovel.server.task.dto.continuecontent.GenerateSingleChapterParameters;
import com.ainovel.server.task.model.TaskStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * 自动续写小说章节内容的任务执行器 (REQ-TASK-002 父任务)
 * 负责启动第一个 "生成单章" 子任务 (GenerateSingleChapterTaskExecutable)。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ContinueWritingContentTaskExecutable implements BackgroundTaskExecutable<ContinueWritingContentParameters, ContinueWritingContentResult> {

    private final NovelService novelService;

    @Override
    public Mono<ContinueWritingContentResult> execute(TaskContext<ContinueWritingContentParameters> context) {
        ContinueWritingContentParameters parameters = context.getParameters();
        String novelId = parameters.getNovelId();
        int numberOfChapters = parameters.getNumberOfChapters();
        String parentTaskId = context.getTaskId();

        log.info("启动自动续写内容任务 (父任务): {}, 小说ID: {}, 章节数: {}, 持久化: {}",
                 parentTaskId, novelId, numberOfChapters, parameters.isPersistChanges()); // Log new param

        ContinueWritingContentProgress progress = new ContinueWritingContentProgress();
        progress.setTotalChapters(numberOfChapters);
        progress.setChaptersCompleted(0);
        progress.setFailedChapters(0);
        progress.setCurrentStep("STARTING");

        return context.updateProgress(progress)
            .then(novelService.findNovelById(novelId))
            .switchIfEmpty(Mono.error(new IllegalArgumentException("找不到小说: " + novelId)))
            .flatMap(novel -> {
                String initialContext = determineInitialContext(novel, parameters);

                GenerateSingleChapterParameters firstChapterParams = GenerateSingleChapterParameters.builder()
                        .novelId(novelId)
                        .chapterIndex(1)
                        .currentContext(initialContext)
                        .aiConfigIdSummary(parameters.getAiConfigIdSummary())
                        .aiConfigIdContent(parameters.getAiConfigIdContent())
                        .writingStyle(parameters.getWritingStyle())
                        .summaryPromptTemplateId(parameters.getSummaryPromptTemplateId())
                        .contentPromptTemplateId(parameters.getContentPromptTemplateId())
                        .summaryPublicModelConfigId(parameters.getSummaryPublicModelConfigId())
                        .contentPublicModelConfigId(parameters.getContentPublicModelConfigId())
                        .totalChapters(numberOfChapters)
                        .requiresReview(parameters.isRequiresReview())
                        .parentTaskId(parentTaskId)
                        .persistChanges(parameters.isPersistChanges()) // Pass the new parameter
                        .build();

                return context.submitSubTask("GENERATE_SINGLE_CHAPTER", firstChapterParams)
                    .doOnNext(subTaskId ->
                        log.info("父任务 {} 已提交第一个 GENERATE_SINGLE_CHAPTER 子任务: {}", parentTaskId, subTaskId))
                    .flatMap(subTaskId ->
                        context.updateProgress(updateProgressStep(progress, 1))
                               .thenReturn(subTaskId)
                    );
            })
            .thenReturn(buildInitialRunningResult(numberOfChapters));
    }

    // Helper method to determine initial context based on parameters
    private String determineInitialContext(Novel novel, ContinueWritingContentParameters parameters) {
        StringBuilder contextBuilder = new StringBuilder();
        
        // 添加小说基本信息
        if (novel.getTitle() != null && !novel.getTitle().isEmpty()) {
            contextBuilder.append("小说标题: ").append(novel.getTitle()).append("\n\n");
        }
        
        if (novel.getDescription() != null && !novel.getDescription().isEmpty()) {
            contextBuilder.append("小说简介:\n").append(novel.getDescription()).append("\n\n");
        }
        
        // 根据startContextMode确定如何获取章节上下文
        String startContextMode = parameters.getStartContextMode();
        if (startContextMode == null) {
            startContextMode = "AUTO"; // 默认使用自动模式
        }
        
        if ("CUSTOM".equals(startContextMode) && parameters.getCustomContext() != null) {
            // 使用自定义上下文
            log.info("使用自定义上下文，长度: {}", parameters.getCustomContext().length());
            contextBuilder.append("自定义上下文:\n").append(parameters.getCustomContext());
        } 
        else if ("LAST_N_CHAPTERS".equals(startContextMode) && parameters.getContextChapterCount() != null) {
            // 使用最后N章的内容
            int chaptersToInclude = parameters.getContextChapterCount();
            log.info("将使用最后 {} 章的内容作为上下文", chaptersToInclude);
            
            // 异步获取章节摘要并等待结果
            try {
                // 找到最后N章的起始章节ID
                String startChapterId = findStartChapterIdForLastN(novel, chaptersToInclude);
                if (startChapterId != null) {
                    // 从startChapterId到最后一章的摘要
                    String summaries = novelService.getChapterRangeSummaries(novel.getId(), startChapterId, null)
                        .block(Duration.ofSeconds(10)); // 使用阻塞方式等待结果，仅用于简化实现
                    
                    if (summaries != null && !summaries.isEmpty()) {
                        contextBuilder.append("前序章节摘要:\n").append(summaries);
                    } else {
                        log.warn("无法获取章节摘要，将只使用小说基本信息作为上下文");
                    }
                }
            } catch (Exception e) {
                log.error("获取章节摘要时出错: {}", e.getMessage(), e);
            }
        }
        else { // AUTO模式
            // 自动模式: 获取最后3章或全部章节(如果少于3章)的摘要
            try {
                String startChapterId = findStartChapterIdForLastN(novel, 3);
                if (startChapterId != null) {
                    String summaries = novelService.getChapterRangeSummaries(novel.getId(), startChapterId, null)
                        .block(Duration.ofSeconds(10));
                    
                    if (summaries != null && !summaries.isEmpty()) {
                        contextBuilder.append("前序章节摘要:\n").append(summaries);
                    }
                }
            } catch (Exception e) {
                log.error("自动获取章节摘要时出错: {}", e.getMessage(), e);
            }
        }
        
        return contextBuilder.toString();
    }

    /**
     * 查找最后N章的起始章节ID
     */
    private String findStartChapterIdForLastN(Novel novel, int n) {
        if (novel.getStructure() == null || novel.getStructure().getActs() == null) {
            return null;
        }
        
        // 收集所有章节并按顺序排序
        List<Novel.Chapter> allChapters = novel.getStructure().getActs().stream()
            .flatMap(act -> {
                if (act.getChapters() == null) return Stream.empty();
                return act.getChapters().stream();
            })
            .sorted(Comparator.comparingInt(ch -> {
                // 尝试从章节标题解析序号
                try {
                    String title = ch.getTitle();
                    if (title.startsWith("第") && title.endsWith("章")) {
                        String numPart = title.substring(1, title.length() - 1);
                        return Integer.parseInt(numPart);
                    }
                } catch (Exception ignored) {}
                // 如果解析失败，使用默认顺序
                return ch.getOrder(); // Integer类型自动拆箱
            }))
            .collect(Collectors.toList());
        
        int totalChapters = allChapters.size();
        if (totalChapters == 0) {
            return null;
        }
        
        // 获取倒数第N章或第一章(如果总章节数小于N)
        int startIndex = Math.max(0, totalChapters - n);
        return allChapters.get(startIndex).getId();
    }
    
    // Helper method to update progress step
    private ContinueWritingContentProgress updateProgressStep(ContinueWritingContentProgress progress, int chapterIndex) {
        progress.setCurrentStep("GENERATING_SUMMARY_" + chapterIndex);
        return progress;
    }

    // Helper method to build the initial "running" result for the parent task
    private ContinueWritingContentResult buildInitialRunningResult(int totalChapters) {
        return ContinueWritingContentResult.builder()
                .newChapterIds(new ArrayList<>())
                .summariesGeneratedCount(0)
                .contentGeneratedCount(0)
                .failedChaptersCount(0)
                .status(TaskStatus.RUNNING) // Indicate the parent task is now running (driven by subtasks)
                .build();
    }

    @Override
    public String getTaskType() {
        return "CONTINUE_WRITING_CONTENT";
    }
} 