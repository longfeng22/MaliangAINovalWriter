package com.ainovel.server.task.executor;

import com.ainovel.server.domain.model.*;
import com.ainovel.server.repository.NovelKnowledgeBaseRepository;
import com.ainovel.server.repository.UserKnowledgeBaseRelationRepository;
import com.ainovel.server.service.FanqieNovelImportRecordService;
import com.ainovel.server.service.fanqie.FanqieNovelService;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionParameters;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionProgress;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionResult;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionGroupResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 知识提取任务执行器
 * 
 * 功能：
 * 1. 从番茄小说或用户文本提取知识
 * 2. 创建多个子任务组并发执行
 * 3. 聚合结果生成知识库
 * 4. 实时报告进度
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class KnowledgeExtractionTaskExecutor implements BackgroundTaskExecutable<KnowledgeExtractionParameters, KnowledgeExtractionResult> {
    
    private final FanqieNovelService fanqieNovelService;
    private final FanqieNovelImportRecordService importRecordService;
    private final NovelKnowledgeBaseRepository knowledgeBaseRepository;
    private final UserKnowledgeBaseRelationRepository relationRepository;
    private final ObjectMapper objectMapper;
    private final com.ainovel.server.task.service.TaskStateService taskStateService;
    private final com.ainovel.server.service.NovelService novelService;
    private final com.ainovel.server.service.KnowledgeExtractionTaskService taskRecordService;
    private final com.ainovel.server.repository.SceneRepository sceneRepository;
    private final com.ainovel.server.repository.NovelRepository novelRepository;
    private final com.ainovel.server.service.ImportService importService;
    
    // 前端访问的公开URL（用于生成图片链接）
    @org.springframework.beans.factory.annotation.Value("${fanqie.api.public-url}")
    private String fanqiePublicUrl;
    
    @Override
    public String getTaskType() {
        // 返回主要任务类型
        return "KNOWLEDGE_EXTRACTION_FANQIE";
    }
    
    @Override
    public List<String> getSupportedTaskTypes() {
        // ✅ 支持两种任务类型（番茄小说和用户文本）
        return Arrays.asList(
            "KNOWLEDGE_EXTRACTION_FANQIE",
            "KNOWLEDGE_EXTRACTION_TEXT"
        );
    }
    
    @Override
    public Mono<KnowledgeExtractionResult> execute(TaskContext<KnowledgeExtractionParameters> context) {
        KnowledgeExtractionParameters parameters = context.getParameters();
        String taskId = context.getTaskId();
        
        log.info("开始执行知识提取任务: taskId={}, importRecordId={}", 
                taskId, parameters.getImportRecordId());
        
        // 初始化进度
        KnowledgeExtractionProgress progress = KnowledgeExtractionProgress.builder()
                .currentStep("INITIALIZING")
                .totalSubTasks(0)
                .completedSubTasks(0)
                .failedSubTasks(0)
                .progress(0)
                .lastUpdated(LocalDateTime.now())
                .build();
        
        // ✅ 立即创建任务记录（使用占位符数据）
        return createInitialTaskRecord(taskId, parameters)
                .then(context.updateProgress(progress))
                .then(getNovelContent(parameters))
                .flatMap(contentData -> {
                    // ✅ 更新任务记录的详细信息（标题、作者、封面）
                    return updateTaskRecordDetails(taskId, contentData)
                            .then(Mono.defer(() -> {
                                // 更新进度：开始提取
                                progress.setCurrentStep("EXTRACTING");
                                return context.updateProgress(progress)
                                        .then(taskRecordService.updateTaskStatus(taskId, 
                                                com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.TaskStatus.EXTRACTING, 
                                                "EXTRACTING"))
                                        .then(extractKnowledge(context, parameters, contentData))
                                        .map(result -> {
                                            log.info("所有子任务已提交，任务ID: {}", taskId);
                                            return result;
                                        });
                            }));
                })
                .doOnSuccess(result -> {
                    log.info("知识提取任务（父任务）完成: taskId={}, success={}", 
                            taskId, result.getSuccess());
                    
                    // 记录任务成功
                    if (result.getSuccess()) {
                        taskRecordService.recordTaskSuccess(
                                taskId, 
                                result.getKnowledgeBaseId(), 
                                result.getTotalSettings(), 
                                result.getTotalTokens())
                                .subscribe();
                    }
                })
                .doOnError(error -> {
                    log.error("知识提取任务失败: taskId={}, error={}", taskId, error.getMessage(), error);
                    
                    // 记录任务失败
                    com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason reason = 
                            classifyFailureReason(error);
                    taskRecordService.recordTaskFailure(
                            taskId, 
                            error.getMessage(), 
                            getStackTrace(error), 
                            reason)
                            .subscribe();
                    
                    // 更新导入记录状态
                    updateImportRecordStatus(parameters.getImportRecordId(), 
                            FanqieNovelImportRecord.ImportStatus.FAILED, 
                            null)
                            .subscribe();
                });
    }
    
    /**
     * ✅ 立即创建任务记录（使用占位符数据）
     */
    private Mono<com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord> createInitialTaskRecord(
            String taskId,
            KnowledgeExtractionParameters parameters) {
        
        com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SourceType sourceType = 
                parameters.getFanqieNovelId() != null ? 
                com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SourceType.FANQIE_NOVEL :
                com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SourceType.USER_TEXT;
        
        // 使用占位符数据
        String placeholderTitle = parameters.getFanqieNovelId() != null ? 
                "等待下载小说..." : "用户文本";
        
        log.info("创建初始任务记录: taskId={}, userId={}, title={}", 
                taskId, parameters.getUserId(), placeholderTitle);
        
        return taskRecordService.createTaskRecord(
                taskId,
                parameters.getUserId(),
                parameters.getImportRecordId(),
                parameters.getFanqieNovelId(),
                placeholderTitle,
                null,  // author 暂时为空
                null,  // coverImageUrl 暂时为空
                sourceType,
                parameters.getModelConfigId(),
                parameters.getModelType(),
                parameters.getExtractionTypes().stream()
                        .map(KnowledgeExtractionType::getValue)
                        .collect(java.util.stream.Collectors.toList())
        );
    }
    
    /**
     * ✅ 更新任务记录的详细信息（标题、作者、封面）
     */
    private Mono<Void> updateTaskRecordDetails(
            String taskId,
            Map<String, Object> contentData) {
        
        String title = (String) contentData.get("title");
        String author = (String) contentData.get("author");
        String coverImageUrl = (String) contentData.get("coverImageUrl");
        
        log.info("更新任务记录详细信息: taskId={}, title={}, author={}", 
                taskId, title, author);
        
        return taskRecordService.updateTaskDetails(taskId, title, author, coverImageUrl);
    }
    
    /**
     * 分类失败原因
     */
    private com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason classifyFailureReason(Throwable error) {
        String message = error.getMessage();
        if (message == null) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.UNKNOWN;
        }
        
        message = message.toLowerCase();
        if (message.contains("download") || message.contains("下载")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.DOWNLOAD_FAILED;
        } else if (message.contains("timeout") || message.contains("超时")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.TIMEOUT;
        } else if (message.contains("rate limit") || message.contains("限流") || message.contains("429")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.RATE_LIMIT;
        } else if (message.contains("parse") || message.contains("解析")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.PARSE_FAILED;
        } else if (message.contains("subtask") || message.contains("子任务")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.SUBTASK_FAILED;
        } else if (message.contains("aggregate") || message.contains("聚合")) {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.AGGREGATION_FAILED;
        } else {
            return com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.FailureReason.UNKNOWN;
        }
    }
    
    /**
     * 获取错误堆栈
     */
    private String getStackTrace(Throwable error) {
        if (error == null) return null;
        
        java.io.StringWriter sw = new java.io.StringWriter();
        error.printStackTrace(new java.io.PrintWriter(sw));
        String stackTrace = sw.toString();
        
        // 限制长度，避免存储过大
        if (stackTrace.length() > 2000) {
            return stackTrace.substring(0, 2000) + "...";
        }
        return stackTrace;
    }
    
    /**
     * 获取小说内容
     */
    private Mono<Map<String, Object>> getNovelContent(KnowledgeExtractionParameters parameters) {
        if (parameters.getFanqieNovelId() != null) {
            // 从番茄小说获取
            String novelId = parameters.getFanqieNovelId();
            log.info("开始获取番茄小说内容: novelId={}", novelId);
            
            // 先尝试直接获取小说详情，如果失败则创建下载任务
            return fanqieNovelService.getNovelDetail(novelId)
                    .onErrorResume(error -> {
                        log.warn("小说详情获取失败，可能还未下载，开始创建下载任务: novelId={}, error={}", 
                                novelId, error.getMessage());
                        
                        // 创建下载任务（前10章）
                        return fanqieNovelService.addNovelDownloadTask(novelId, 10)
                                .flatMap(task -> {
                                    log.info("下载任务创建成功: taskId={}, celeryTaskId={}, status={}", 
                                            task.getId(), task.getCeleryTaskId(), task.getStatus());
                                    
                                    // 等待下载任务完成（轮询检查状态）
                                    return waitForDownloadTask(task.getCeleryTaskId())
                                            .then(fanqieNovelService.getNovelDetail(novelId));
                                });
                    })
                    .flatMap(detail -> {
                        // 获取前10章内容
                        return fanqieNovelService.getChapterList(novelId, 1, 10, "asc")
                                .flatMap(chapterList -> {
                                    if (chapterList.getChapters() == null || chapterList.getChapters().isEmpty()) {
                                        log.warn("未找到章节列表，使用简介作为内容: novelId={}", novelId);
                                        Map<String, Object> data = new HashMap<>();
                                        data.put("title", detail.getTitle());
                                        data.put("author", detail.getAuthor());
                                        data.put("description", detail.getDescription());
                                        // ✅ 将相对路径转换为完整URL
                                        data.put("coverImageUrl", buildFullCoverUrl(detail.getCoverImageUrl()));
                                        data.put("content", detail.getDescription());
                                        data.put("fanqieNovelId", novelId);
                                        data.put("isUserImported", false);
                                        return Mono.just(data);
                                    }
                                    
                                    // 批量获取章节内容
                                    return Flux.fromIterable(chapterList.getChapters())
                                            .take(10) // 确保只取前10章
                                            .flatMap(chapterInfo -> {
                                                log.info("获取章节内容: novelId={}, chapterId={}, title={}", 
                                                        novelId, chapterInfo.getId(), chapterInfo.getTitle());
                                                
                                                return fanqieNovelService.getChapterContent(novelId, chapterInfo.getId())
                                                        .map(chapter -> {
                                                            // HTML转纯文本
                                                            String cleanContent = htmlToPlainText(chapter.getContent());
                                                            return String.format("【第%d章 %s】\n%s", 
                                                                    chapter.getIndex(), 
                                                                    chapter.getTitle(), 
                                                                    cleanContent);
                                                        })
                                                        .onErrorResume(error -> {
                                                            log.error("获取章节内容失败: chapterId={}, error={}", 
                                                                    chapterInfo.getId(), error.getMessage());
                                                            return Mono.just(""); // 失败时返回空字符串
                                                        });
                                            }, 2) // 并发2个请求
                                            .collectList()
                                            .map(chapters -> {
                                                String content = String.join("\n\n", chapters);
                                                
                                                Map<String, Object> data = new HashMap<>();
                                                data.put("title", detail.getTitle());
                                                data.put("author", detail.getAuthor());
                                                data.put("description", detail.getDescription());
                                                // ✅ 将相对路径转换为完整URL
                                                data.put("coverImageUrl", buildFullCoverUrl(detail.getCoverImageUrl()));
                                                data.put("content", content);
                                                data.put("fanqieNovelId", novelId);
                                                data.put("isUserImported", false);
                                                data.put("chapterCount", chapters.size());  // ✅ 添加章节数量
                                                
                                                log.info("成功获取小说内容: novelId={}, contentLength={}, chapterCount={}", 
                                                        novelId, content.length(), chapters.size());
                                                
                                                return data;
                                            });
                                });
                    })
                    .onErrorResume(error -> {
                        log.error("获取番茄小说内容失败: novelId={}, error={}", 
                                novelId, error.getMessage(), error);
                        return Mono.error(error);
                    });
        } else {
            // ✅ 使用用户提供的文本：尝试从previewSession获取章节详情
            if (parameters.getPreviewSessionId() != null && !parameters.getPreviewSessionId().isEmpty()) {
                log.info("用户导入文本: 从预览会话获取章节详情, sessionId={}", parameters.getPreviewSessionId());
                
                final String sessionId = parameters.getPreviewSessionId();
                
                // 从previewSession获取章节详情
                return importService.getChapterDetailsFromPreviewSession(sessionId, parameters.getChapterCount())
                .map(chapterDetails -> {
                    // 转换为标准格式（与番茄小说相同）
                    List<Map<String, Object>> chapterDetailsList = chapterDetails.stream()
                            .map(detail -> {
                                Map<String, Object> map = new HashMap<>();
                                map.put("index", detail.getIndex());
                                map.put("chapterId", detail.getChapterId());
                                map.put("title", detail.getTitle());
                                map.put("content", detail.getContent());
                                map.put("wordCount", detail.getWordCount());
                                map.put("formattedContent", 
                                        String.format("【第%d章 %s】\n%s", 
                                                detail.getIndex(), 
                                                detail.getTitle(), 
                                                detail.getContent()));
                                return map;
                            })
                            .collect(Collectors.toList());
                    
                    // 合并所有章节内容用于AI分析
                    String mergedContent = chapterDetailsList.stream()
                            .map(ch -> (String) ch.get("formattedContent"))
                            .collect(Collectors.joining("\n\n"));
                    
                    Map<String, Object> data = new HashMap<>();
                    data.put("title", parameters.getTitle());
                    data.put("description", parameters.getDescription());
                    data.put("content", mergedContent); // 合并后的内容用于AI分析
                    data.put("chapterDetails", chapterDetailsList); // ✅ 章节详情列表
                    data.put("isUserImported", true);
                    data.put("chapterCount", chapterDetailsList.size());
                    
                    log.info("用户导入文本: 成功获取章节详情, chapters={}", chapterDetailsList.size());
                    
                    return data;
                })
                .doOnSuccess(data -> {
                    // ✅ 获取完章节详情后立即清理预览会话
                    log.info("清理预览会话: sessionId={}", sessionId);
                    importService.cleanupPreviewSession(sessionId)
                            .subscribe(
                                null,
                                error -> log.warn("清理预览会话失败: sessionId={}, error={}", 
                                        sessionId, error.getMessage())
                            );
                })
                .doOnError(error -> {
                    // ⚠️ 即使失败也清理会话（避免内存泄漏）
                    log.warn("获取章节详情失败，仍然清理预览会话: sessionId={}", sessionId);
                    importService.cleanupPreviewSession(sessionId).subscribe();
                });
            } else {
                // 降级方案：直接使用原始内容（没有previewSessionId时）
                log.warn("用户导入文本: 未提供previewSessionId，使用原始内容");
                Map<String, Object> data = new HashMap<>();
                data.put("title", parameters.getTitle());
                data.put("description", parameters.getDescription());
                data.put("content", parameters.getContent());
                data.put("isUserImported", true);
                
                // ✅ 传递章节数量（用于章节大纲提取）
                if (parameters.getChapterCount() != null && parameters.getChapterCount() > 0) {
                    data.put("chapterCount", parameters.getChapterCount());
                    log.info("用户导入文本: 传递章节数量={}", parameters.getChapterCount());
                }
                
                return Mono.just(data);
            }
        }
    }
    
    /**
     * 等待番茄小说下载任务完成
     * 
     * @param celeryTaskId Celery任务ID
     * @return 完成信号
     */
    private Mono<Void> waitForDownloadTask(String celeryTaskId) {
        log.info("开始等待下载任务完成: celeryTaskId={}", celeryTaskId);
        
        return Mono.defer(() -> checkDownloadTaskStatus(celeryTaskId, 0))
                .then();
    }
    
    /**
     * 递归检查下载任务状态
     * 
     * @param celeryTaskId Celery任务ID
     * @param attemptCount 尝试次数
     * @return 任务状态
     */
    private Mono<String> checkDownloadTaskStatus(String celeryTaskId, int attemptCount) {
        final int MAX_ATTEMPTS = 180; // 最多等待60次（约15分钟）
        final int POLL_INTERVAL_SECONDS = 10; // 每5秒检查一次
        
        if (attemptCount >= MAX_ATTEMPTS) {
            return Mono.error(new RuntimeException(
                    "下载任务超时: 等待时间超过" + (MAX_ATTEMPTS * POLL_INTERVAL_SECONDS) + "秒"));
        }
        
        return fanqieNovelService.getTaskStatus(celeryTaskId)
                .flatMap(task -> {
                    String status = task.getStatus();
                    Integer progress = task.getProgress();
                    
                    log.info("下载任务状态检查 [尝试 {}/{}]: status={}, progress={}%", 
                            attemptCount + 1, MAX_ATTEMPTS, status, progress);
                    
                    // 支持多种完成状态：SUCCESS, COMPLETED
                    if ("completed".equalsIgnoreCase(status) || "success".equalsIgnoreCase(status)) {
                        log.info("✅ 下载任务完成: celeryTaskId={}, status={}", celeryTaskId, status);
                        return Mono.just(status);
                    } else if ("failed".equalsIgnoreCase(status)) {
                        String errorMsg = task.getMessage() != null ? task.getMessage() : "未知错误";
                        log.error("❌ 下载任务失败: celeryTaskId={}, error={}", celeryTaskId, errorMsg);
                        return Mono.error(new RuntimeException("下载任务失败: " + errorMsg));
                    } else if ("terminated".equalsIgnoreCase(status)) {
                        log.error("❌ 下载任务被终止: celeryTaskId={}", celeryTaskId);
                        return Mono.error(new RuntimeException("下载任务被终止"));
                    } else {
                        // 任务仍在进行中，等待后重试
                        return Mono.delay(java.time.Duration.ofSeconds(POLL_INTERVAL_SECONDS))
                                .flatMap(tick -> checkDownloadTaskStatus(celeryTaskId, attemptCount + 1));
                    }
                })
                .onErrorResume(error -> {
                    if (error.getMessage() != null && 
                        (error.getMessage().contains("下载任务失败") || 
                         error.getMessage().contains("下载任务被终止") ||
                         error.getMessage().contains("下载任务超时"))) {
                        // 这些是业务错误，直接传播
                        return Mono.error(error);
                    }
                    
                    // 其他错误（如网络错误），重试
                    if (attemptCount < MAX_ATTEMPTS) {
                        log.warn("检查任务状态失败，将在{}秒后重试: error={}", 
                                POLL_INTERVAL_SECONDS, error.getMessage());
                        return Mono.delay(java.time.Duration.ofSeconds(POLL_INTERVAL_SECONDS))
                                .flatMap(tick -> checkDownloadTaskStatus(celeryTaskId, attemptCount + 1));
                    } else {
                        return Mono.error(new RuntimeException("无法获取下载任务状态，已达到最大重试次数", error));
                    }
                });
    }
    
    /**
     * HTML转纯文本
     * 移除HTML标签，保留文本内容
     */
    private String htmlToPlainText(String html) {
        if (html == null || html.isEmpty()) {
            return "";
        }
        
        // 简单的HTML标签移除
        String text = html
                // 保留段落换行
                .replaceAll("</p>", "\n")
                .replaceAll("<br\\s*/?>", "\n")
                // 移除所有HTML标签
                .replaceAll("<[^>]+>", "")
                // 转换HTML实体
                .replaceAll("&nbsp;", " ")
                .replaceAll("&lt;", "<")
                .replaceAll("&gt;", ">")
                .replaceAll("&amp;", "&")
                .replaceAll("&quot;", "\"")
                .replaceAll("&#39;", "'")
                // 移除多余空白
                .replaceAll("[ \\t]+", " ")
                .replaceAll("\\n{3,}", "\n\n")
                .trim();
        
        return text;
    }
    
    /**
     * 提取知识（子任务模式）
     */
    private Mono<KnowledgeExtractionResult> extractKnowledge(
            TaskContext<KnowledgeExtractionParameters> context,
            KnowledgeExtractionParameters parameters,
            Map<String, Object> contentData) {
        
        String content = (String) contentData.get("content");
        List<KnowledgeExtractionType> extractionTypes = parameters.getExtractionTypes();
        
        // 按组创建子任务
        List<ExtractionGroup> groups = createExtractionGroups(extractionTypes);
        
        // 更新总子任务数
        KnowledgeExtractionProgress progress = KnowledgeExtractionProgress.builder()
                .currentStep("EXTRACTING")
                .totalSubTasks(groups.size())
                .completedSubTasks(0)
                .failedSubTasks(0)
                .progress(10)
                .lastUpdated(LocalDateTime.now())
                .build();
        
        return context.updateProgress(progress)
                .thenMany(Flux.fromIterable(groups))
                .flatMap(group -> {
                    // 为每个组创建子任务
                    Map<String, Object> subTaskParams = new HashMap<>();
                    subTaskParams.put("groupName", group.getName());
                    subTaskParams.put("extractionTypes", group.getTypes().stream()
                            .map(KnowledgeExtractionType::getValue)
                            .collect(Collectors.toList()));
                    subTaskParams.put("content", content);
                    subTaskParams.put("modelConfigId", parameters.getModelConfigId());
                    subTaskParams.put("modelType", parameters.getModelType());
                    subTaskParams.put("parentTaskId", context.getTaskId());
                    
                    // ✅ 如果是章节大纲组，传递章节数量
                    if ("章节大纲".equals(group.getName())) {
                        Integer chapterCount = (Integer) contentData.get("chapterCount");
                        if (chapterCount != null && chapterCount > 0) {
                            subTaskParams.put("chapterCount", chapterCount);
                            log.info("章节大纲组: 传递章节数量={}", chapterCount);
                        }
                    }
                    
                    log.info("提交知识提取组子任务: groupName={}, types={}", 
                            group.getName(), group.getTypes().size());
                    
                    return context.submitSubTask("KNOWLEDGE_EXTRACTION_GROUP", subTaskParams)
                            .doOnNext(subTaskId -> {
                                log.info("✅ 子任务已提交: taskId={}, groupName={}", subTaskId, group.getName());
                                        })
                                        .doOnError(error -> {
                                log.error("❌ 子任务提交失败: groupName={}, error={}", 
                                        group.getName(), error.getMessage());
                            });
                }, 3) // 最多3个并发提交
                .collectList()
                .flatMap(subTaskIds -> {
                    log.info("所有子任务已提交，共{}个，开始等待全部完成", subTaskIds.size());
                    
                    // 等待所有子任务完成
                    return waitForAllSubTasksComplete(context.getTaskId(), subTaskIds)
                            .flatMap(results -> {
                                // 所有子任务完成，聚合结果并创建知识库
                                log.info("所有子任务已完成，开始聚合结果并创建知识库");
                                return aggregateResultsAndCreateKnowledgeBase(contentData, results, parameters);
                            });
                });
    }
    
    /**
     * 等待所有子任务完成
     */
    private Mono<List<KnowledgeExtractionGroupResult>> waitForAllSubTasksComplete(
            String parentTaskId, 
            List<String> subTaskIds) {
        
        log.info("开始等待{}个子任务完成", subTaskIds.size());
        
        return Mono.defer(() -> checkAllSubTasksStatus(subTaskIds, 0));
    }
    
    /**
     * 递归检查所有子任务状态
     */
    private Mono<List<KnowledgeExtractionGroupResult>> checkAllSubTasksStatus(
            List<String> subTaskIds, 
            int attemptCount) {
        
        final int MAX_ATTEMPTS = 360; // 最多等待120次（10分钟，每5秒一次）
        final int POLL_INTERVAL_SECONDS = 5;
        
        if (attemptCount >= MAX_ATTEMPTS) {
            return Mono.error(new RuntimeException(
                    "子任务执行超时: 等待时间超过" + (MAX_ATTEMPTS * POLL_INTERVAL_SECONDS / 60) + "分钟"));
        }
        
        // 获取所有子任务的状态
        return Flux.fromIterable(subTaskIds)
                .flatMap(taskId -> 
                    taskStateService.getTask(taskId)
                            .map(task -> {
                                Map<String, Object> taskInfo = new HashMap<>();
                                taskInfo.put("taskId", taskId);
                                taskInfo.put("status", task.getStatus().name());
                                taskInfo.put("result", task.getResult());
                                return taskInfo;
                            })
                            .switchIfEmpty(Mono.defer(() -> {
                                Map<String, Object> taskInfo = new HashMap<>();
                                taskInfo.put("taskId", taskId);
                                taskInfo.put("status", "UNKNOWN");
                                return Mono.just(taskInfo);
                            }))
                )
                .collectList()
                .flatMap(taskInfos -> {
                    long completedCount = taskInfos.stream()
                            .filter(info -> "COMPLETED".equals(info.get("status")))
                            .count();
                    long failedCount = taskInfos.stream()
                            .filter(info -> "FAILED".equals(info.get("status")))
                            .count();
                    long runningCount = taskInfos.size() - completedCount - failedCount;
                    
                    log.info("子任务状态检查 [尝试 {}/{}]: 完成={}, 失败={}, 进行中={}", 
                            attemptCount + 1, MAX_ATTEMPTS, completedCount, failedCount, runningCount);
                    
                    // 检查是否全部完成
                    if (completedCount + failedCount == taskInfos.size()) {
                        if (failedCount > 0) {
                            log.warn("⚠️  部分子任务失败: 完成={}, 失败={}", completedCount, failedCount);
                        } else {
                            log.info("✅ 所有子任务已完成: 共{}个", completedCount);
                        }
                        
                        // 收集所有子任务的结果
                        return collectSubTaskResults(taskInfos);
                    } else {
                        // 仍有任务在运行，继续等待
                        return Mono.delay(java.time.Duration.ofSeconds(POLL_INTERVAL_SECONDS))
                                .flatMap(tick -> checkAllSubTasksStatus(subTaskIds, attemptCount + 1));
                    }
                })
                .onErrorResume(error -> {
                    log.error("检查子任务状态失败: error={}", error.getMessage());
                    if (attemptCount < MAX_ATTEMPTS) {
                        return Mono.delay(java.time.Duration.ofSeconds(POLL_INTERVAL_SECONDS))
                                .flatMap(tick -> checkAllSubTasksStatus(subTaskIds, attemptCount + 1));
                    } else {
                        return Mono.error(error);
                    }
                });
    }
    
    /**
     * 收集所有子任务的结果
     */
    private Mono<List<KnowledgeExtractionGroupResult>> collectSubTaskResults(List<Map<String, Object>> taskInfos) {
        List<KnowledgeExtractionGroupResult> results = new ArrayList<>();
        
        for (Map<String, Object> taskInfo : taskInfos) {
            if ("COMPLETED".equals(taskInfo.get("status")) && taskInfo.get("result") != null) {
                try {
                    // 尝试将result转换为KnowledgeExtractionGroupResult
                    Object resultObj = taskInfo.get("result");
                    KnowledgeExtractionGroupResult result = objectMapper.convertValue(
                            resultObj, 
                            KnowledgeExtractionGroupResult.class);
                    results.add(result);
                    log.info("收集到子任务结果: groupName={}, 设定数量={}", 
                            result.getGroupName(), 
                            result.getSettings() != null ? result.getSettings().size() : 0);
                } catch (Exception e) {
                    log.error("解析子任务结果失败: taskId={}, error={}", 
                            taskInfo.get("taskId"), e.getMessage());
                }
            }
        }
        
        log.info("共收集到{}个子任务结果", results.size());
        return Mono.just(results);
    }
    
    /**
     * 聚合结果并创建知识库
     */
    private Mono<KnowledgeExtractionResult> aggregateResultsAndCreateKnowledgeBase(
            Map<String, Object> contentData,
            List<KnowledgeExtractionGroupResult> groupResults,
            KnowledgeExtractionParameters parameters) {
        
        log.info("开始聚合{}个组的提取结果", groupResults.size());
        
        // 收集所有设定
        Map<String, List<NovelSettingItem>> allSettings = new HashMap<>();
        long totalTokens = 0L;
        
        for (KnowledgeExtractionGroupResult result : groupResults) {
            if (result.isSuccess() && result.getSettings() != null) {
                allSettings.put(result.getGroupName(), result.getSettings());
                totalTokens += result.getTokensUsed() != null ? result.getTokensUsed() : 0L;
            }
        }
        
        int totalSettingsCount = allSettings.values().stream().mapToInt(List::size).sum();
        
        log.info("聚合完成: 共{}组, {}个设定, {}tokens", 
                allSettings.size(), 
                totalSettingsCount,
                totalTokens);
        
        // ✅ 如果没有提取到任何设定，返回错误
        if (totalSettingsCount == 0) {
            log.error("❌ 所有子任务都未提取到设定数据，可能原因：1.模型配置无效 2.API Key失效 3.内容为空");
            return Mono.error(new RuntimeException(
                    "知识提取失败：所有子任务都未能提取到设定数据。" +
                    "请检查：1.模型配置是否有效 2.API Key是否正确 3.小说内容是否完整"));
        }
        
        // 检查是否有章节大纲需要创建Novel
        List<NovelSettingItem> chapterOutlineSettings = allSettings.getOrDefault("章节大纲", new ArrayList<>());
        
        final long finalTotalTokens = totalTokens;
        
        // 如果有章节大纲，先创建Novel
        Mono<String> novelCreationMono;
        if (!chapterOutlineSettings.isEmpty()) {
            log.info("检测到章节大纲，开始创建大纲小说: {} 个章节", chapterOutlineSettings.size());
            // ✅ 传递章节详细信息（包含完整内容）
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> chapterDetails = 
                    (List<Map<String, Object>>) contentData.get("chapterDetails");
            novelCreationMono = createOutlineNovel(contentData, chapterOutlineSettings, chapterDetails, parameters);
        } else {
            log.info("未检测到章节大纲，跳过小说创建");
            // ✅ 使用明确类型的 Mono.empty().defaultIfEmpty(null) 安全处理 null
            novelCreationMono = Mono.<String>empty().defaultIfEmpty(null);
        }
        
        // 创建知识库并关联Novel
        return novelCreationMono
                .flatMap(outlineNovelId -> {
                    log.info("开始创建知识库, outlineNovelId={}", outlineNovelId);
                    return buildKnowledgeBase(contentData, allSettings, parameters, outlineNovelId);
                })
                .flatMap(knowledgeBase -> 
                    knowledgeBaseRepository.save(knowledgeBase)
                            .flatMap(savedKb -> {
                                // ✅ 自动创建用户知识库关系
                                UserKnowledgeBaseRelation relation = UserKnowledgeBaseRelation.builder()
                                        .userId(parameters.getUserId())
                                        .knowledgeBaseId(savedKb.getId())
                                        .addType(UserKnowledgeBaseRelation.AddType.AUTO_EXTRACT)
                                        .addedAt(LocalDateTime.now())
                                        .lastUsedAt(LocalDateTime.now())
                                        .build();
                                
                                return relationRepository.save(relation)
                                        .doOnSuccess(r -> log.info("✅ 用户知识库关系已创建: userId={}, knowledgeBaseId={}", 
                                                parameters.getUserId(), savedKb.getId()))
                                        .thenReturn(savedKb);
                            })
                            .map(savedKb -> KnowledgeExtractionResult.builder()
                                    .knowledgeBaseId(savedKb.getId())
                                    .success(true)
                                    .totalSettings(countTotalSettings(savedKb))
                                    .totalTokens(finalTotalTokens)
                                    .build())
                )
                .doOnSuccess(result -> {
                    log.info("✅ 知识库创建成功: knowledgeBaseId={}", result.getKnowledgeBaseId());
                    // 更新导入记录状态
                    updateImportRecordStatus(parameters.getImportRecordId(), 
                            FanqieNovelImportRecord.ImportStatus.COMPLETED, 
                            result.getKnowledgeBaseId())
                            .subscribe();
                })
                .onErrorResume(error -> {
                    log.error("❌ 知识库创建失败: error={}", error.getMessage(), error);
                    return Mono.just(KnowledgeExtractionResult.builder()
                            .success(false)
                            .failureReason(error.getMessage())
                            .build());
                });
    }
    
    /**
     * 创建提取分组
     */
    private List<ExtractionGroup> createExtractionGroups(List<KnowledgeExtractionType> types) {
        Map<String, List<KnowledgeExtractionType>> groupMap = new HashMap<>();
        
        for (KnowledgeExtractionType type : types) {
            String groupName = getGroupName(type);
            groupMap.computeIfAbsent(groupName, k -> new ArrayList<>()).add(type);
        }
        
        return groupMap.entrySet().stream()
                .map(entry -> new ExtractionGroup(entry.getKey(), entry.getValue()))
                .collect(Collectors.toList());
    }
    
    /**
     * 获取分组名称
     */
    private String getGroupName(KnowledgeExtractionType type) {
        return switch (type) {
            case NARRATIVE_STYLE, WRITING_STYLE, WORD_USAGE -> "文风叙事";
            case CORE_CONFLICT, SUSPENSE_DESIGN, STORY_PACING -> "情节设计";  // ✅ 情节设计独立组
            case CHARACTER_BUILDING -> "人物塑造";  // ✅ 人物塑造独立组
            case WORLDVIEW, GOLDEN_FINGER -> "小说特点";
            case RESONANCE, PLEASURE_POINT, EXCITEMENT_POINT -> "读者情绪";
            case HOT_MEMES, FUNNY_POINTS -> "热梗搞笑点";
            case CUSTOM -> "用户自定义";
            case CHAPTER_OUTLINE -> "章节大纲";
        };
    }
    
    /**
     * 构建知识库对象
     */
    private Mono<NovelKnowledgeBase> buildKnowledgeBase(
            Map<String, Object> contentData,
            Map<String, List<NovelSettingItem>> allSettings,
            KnowledgeExtractionParameters parameters,
            String outlineNovelId) {
        
        NovelKnowledgeBase.NovelKnowledgeBaseBuilder builder = NovelKnowledgeBase.builder()
                .title((String) contentData.get("title"))
                .author((String) contentData.get("author"))
                .description((String) contentData.get("description"))
                .coverImageUrl((String) contentData.get("coverImageUrl"))
                .fanqieNovelId((String) contentData.get("fanqieNovelId"))
                .isUserImported((Boolean) contentData.getOrDefault("isUserImported", false))
                .firstImportUserId(parameters.getUserId())
                .firstImportTime(LocalDateTime.now())
                .status(NovelKnowledgeBase.CacheStatus.COMPLETED)
                .cacheSuccess(true)
                .cacheTime(LocalDateTime.now())
                .isPublic(contentData.get("fanqieNovelId") != null) // 番茄小说默认公开
                .likeCount(0)
                .referenceCount(0)
                .viewCount(0)
                .likedUserIds(new ArrayList<>())
                .outlineNovelId(outlineNovelId) // 设置大纲小说ID
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now());
        
        // 设置各类型设定
        builder.narrativeStyleSettings(allSettings.getOrDefault("文风叙事", new ArrayList<>()));
        
        // ✅ 合并情节设计和人物塑造到characterPlotSettings字段
        List<NovelSettingItem> characterPlotSettings = new ArrayList<>();
        characterPlotSettings.addAll(allSettings.getOrDefault("情节设计", new ArrayList<>()));
        characterPlotSettings.addAll(allSettings.getOrDefault("人物塑造", new ArrayList<>()));
        builder.characterPlotSettings(characterPlotSettings);
        
        builder.novelFeatureSettings(allSettings.getOrDefault("小说特点", new ArrayList<>()));
        builder.hotMemesSettings(allSettings.getOrDefault("热梗搞笑点", new ArrayList<>()));
        builder.customSettings(allSettings.getOrDefault("用户自定义", new ArrayList<>()));
        builder.readerEmotionSettings(allSettings.getOrDefault("读者情绪", new ArrayList<>()));
        
        return Mono.just(builder.build());
    }
    
    /**
     * 从章节大纲创建Novel对象
     */
    /**
     * 从章节大纲创建Novel对象（包含Scene内容保存）
     */
    private Mono<String> createOutlineNovel(
            Map<String, Object> contentData,
            List<NovelSettingItem> chapterOutlineSettings,
            List<Map<String, Object>> chapterDetails,
            KnowledgeExtractionParameters parameters) {
        
        log.info("开始从章节大纲创建Novel: {} 个章节", chapterOutlineSettings.size());
        
        // 从章节大纲创建Acts和Chapters
        List<Novel.Act> acts = convertOutlineToActsAndChapters(chapterOutlineSettings);
        
        // 设置作者信息
        String authorName = (String) contentData.get("author");
        Novel.Author author = null;
        if (authorName != null && !authorName.isEmpty()) {
            author = Novel.Author.builder()
                    .id(UUID.randomUUID().toString())
                    .username(authorName)
                    .build();
        }
        
        // 创建Structure并设置acts
        Novel.Structure structure = Novel.Structure.builder()
                .acts(acts)
                .build();
        
        // 创建Novel对象
        Novel novel = Novel.builder()
                .title((String) contentData.get("title"))
                .description((String) contentData.get("description"))
                .coverImage((String) contentData.get("coverImageUrl"))
                .author(author)
                .structure(structure)
                .isReady(true) // 标记为已就绪
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
        
        // 保存Novel并创建Scene
        return novelService.createNovel(novel)
                .flatMap(savedNovel -> {
                    log.info("✅ 大纲小说创建成功: novelId={}, title={}, chapters={}",
                            savedNovel.getId(), savedNovel.getTitle(), 
                            acts.stream().mapToInt(act -> act.getChapters().size()).sum());
                    
                    // ✅ 创建并保存Scene内容
                    if (chapterDetails != null && !chapterDetails.isEmpty()) {
                        return createScenesForChapters(savedNovel, chapterOutlineSettings, chapterDetails)
                                .thenReturn(savedNovel.getId());
                    } else {
                        log.warn("⚠️ 未找到章节详细内容，跳过Scene创建");
                        return Mono.just(savedNovel.getId());
                    }
                })
                .onErrorResume(error -> {
                    log.error("❌ 大纲小说创建失败: error={}", error.getMessage(), error);
                    return Mono.just(null); // 失败时返回null，不阻断整个流程
                });
    }
    
    /**
     * 为章节创建Scene并保存内容
     */
    private Mono<Void> createScenesForChapters(
            Novel savedNovel,
            List<NovelSettingItem> chapterOutlineSettings,
            List<Map<String, Object>> chapterDetails) {
        
        String novelId = savedNovel.getId();
        List<Novel.Chapter> allChapters = savedNovel.getStructure().getActs().stream()
                .flatMap(act -> act.getChapters().stream())
                .collect(Collectors.toList());
        
        log.info("开始为 {} 个章节创建Scene", allChapters.size());
        
        // ✅ 为每个章节创建Scene
        return Flux.fromIterable(allChapters)
                .index()
                .flatMap(tuple -> {
                    long index = tuple.getT1();
                    Novel.Chapter chapter = tuple.getT2();
                    
                    // 获取对应的章节详细内容
                    Map<String, Object> chapterDetail = null;
                    if (chapterDetails != null && index < chapterDetails.size()) {
                        chapterDetail = chapterDetails.get((int) index);
                    }
                    
                    // 获取对应的章节大纲设定
                    NovelSettingItem outlineSetting = null;
                    if (index < chapterOutlineSettings.size()) {
                        outlineSetting = chapterOutlineSettings.get((int) index);
                    }
                    
                    if (chapterDetail == null || outlineSetting == null) {
                        log.warn("⚠️ 章节 {} 缺少详细内容或大纲，跳过Scene创建", chapter.getTitle());
                        return Mono.empty();
                    }
                    
                    String content = (String) chapterDetail.get("content");
                    String summaryContent = outlineSetting.getDescription(); // ✅ 章节大纲作为摘要
                    
                    if (content == null || content.isEmpty()) {
                        log.warn("⚠️ 章节 {} 内容为空，跳过Scene创建", chapter.getTitle());
                        return Mono.empty();
                    }
                    
                    // 创建Scene内容
                    String sceneId = UUID.randomUUID().toString();
                    Scene scene = Scene.builder()
                            .id(sceneId)
                            .novelId(novelId)
                            .chapterId(chapter.getId())
                            .title(chapter.getTitle())
                            .content(content)
                            .summary(summaryContent) // ✅ 保存AI生成的章节大纲作为摘要
                            .wordCount(content.length())
                            .sequence(1) // 每个章节只有一个scene，序号为1
                            .version(1)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .lastEdited(LocalDateTime.now())
                            .build();
                    
                    log.info("创建Scene: chapterTitle={}, sceneId={}, contentLength={}, summaryLength={}", 
                            chapter.getTitle(), sceneId, content.length(), 
                            summaryContent != null ? summaryContent.length() : 0);
                    
                    // 保存Scene内容，并更新Chapter的sceneIds
                    return sceneRepository.save(scene)
                            .flatMap(savedScene -> {
                                // 更新Chapter的sceneIds
                                List<String> sceneIds = new ArrayList<>();
                                sceneIds.add(savedScene.getId());
                                return updateChapterSceneIds(novelId, chapter.getId(), sceneIds)
                                        .thenReturn(savedScene)
                                        .doOnSuccess(v -> log.info("✅ Scene创建成功: {}", chapter.getTitle()))
                                        .doOnError(e -> log.error("❌ 更新Chapter的sceneIds失败: {}", e.getMessage()));
                            })
                            .onErrorResume(error -> {
                                log.error("❌ Scene创建失败: chapterTitle={}, error={}", 
                                        chapter.getTitle(), error.getMessage());
                                return Mono.empty(); // 单个Scene失败不影响其他
                            });
                }, 2) // 并发2个创建
                .then()
                .doOnSuccess(v -> log.info("✅ 所有Scene创建完成"))
                .doOnError(e -> log.error("❌ Scene创建过程出错: {}", e.getMessage()));
    }
    
    /**
     * 更新Chapter的sceneIds
     */
    private Mono<Void> updateChapterSceneIds(String novelId, String chapterId, List<String> sceneIds) {
        return novelRepository.findById(novelId)
                .flatMap(novel -> {
                    // 查找并更新Chapter
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            if (chapter.getId().equals(chapterId)) {
                                chapter.setSceneIds(sceneIds);
                                return novelRepository.save(novel).then();
                            }
                        }
                    }
                    return Mono.error(new RuntimeException("未找到章节: " + chapterId));
                });
    }
    
    /**
     * 将章节大纲转换为Acts和Chapters结构
     */
    private List<Novel.Act> convertOutlineToActsAndChapters(List<NovelSettingItem> chapterOutlineSettings) {
        // 按order排序（如果有的话）
        chapterOutlineSettings.sort((a, b) -> {
            // 尝试从tags或description中提取order
            int orderA = extractOrder(a);
            int orderB = extractOrder(b);
            return Integer.compare(orderA, orderB);
        });
        
        // 创建默认的Act（将所有章节放在一个Act中）
        List<Novel.Chapter> chapters = new ArrayList<>();
        for (int i = 0; i < chapterOutlineSettings.size(); i++) {
            NovelSettingItem item = chapterOutlineSettings.get(i);
            
            Novel.Chapter chapter = Novel.Chapter.builder()
                    .id(UUID.randomUUID().toString())
                    .title(item.getName() != null ? item.getName() : "第" + (i + 1) + "章")
                    .description(item.getDescription())
                    .order(i + 1)
                    .sceneIds(new ArrayList<>())
                    .metadata(new HashMap<>())
                    .build();
            
            chapters.add(chapter);
        }
        
        // 创建Act
        Novel.Act act = Novel.Act.builder()
                .id(UUID.randomUUID().toString())
                .title("正文")
                .order(1)
                .chapters(chapters)
                .metadata(new HashMap<>())
                .build();
        
        return List.of(act);
    }
    
    /**
     * 从NovelSettingItem中提取order信息
     */
    private int extractOrder(NovelSettingItem item) {
        // 尝试从tags中提取
        if (item.getTags() != null) {
            for (String tag : item.getTags()) {
                if (tag.startsWith("order:")) {
                    try {
                        return Integer.parseInt(tag.substring(6));
                    } catch (NumberFormatException e) {
                        // 忽略解析错误
                    }
                }
            }
        }
        return 0;
    }
    
    /**
     * 更新导入记录状态
     */
    private Mono<FanqieNovelImportRecord> updateImportRecordStatus(
            String importRecordId,
            FanqieNovelImportRecord.ImportStatus status,
            String knowledgeBaseId) {
        
        return importRecordService.getById(importRecordId)
                .flatMap(record -> {
                    record.setStatus(status);
                    if (knowledgeBaseId != null) {
                        record.setKnowledgeBaseId(knowledgeBaseId);
                    }
                    return importRecordService.update(record);
                });
    }
    
    /**
     * 统计总设定数
     */
    private Integer countTotalSettings(NovelKnowledgeBase kb) {
        int count = 0;
        if (kb.getNarrativeStyleSettings() != null) count += kb.getNarrativeStyleSettings().size();
        if (kb.getCharacterPlotSettings() != null) count += kb.getCharacterPlotSettings().size();
        if (kb.getNovelFeatureSettings() != null) count += kb.getNovelFeatureSettings().size();
        if (kb.getHotMemesSettings() != null) count += kb.getHotMemesSettings().size();
        if (kb.getCustomSettings() != null) count += kb.getCustomSettings().size();
        if (kb.getReaderEmotionSettings() != null) count += kb.getReaderEmotionSettings().size();
        return count;
    }
    
    /**
     * 提取分组
     */
    private static class ExtractionGroup {
        private final String name;
        private final List<KnowledgeExtractionType> types;
        
        public ExtractionGroup(String name, List<KnowledgeExtractionType> types) {
            this.name = name;
            this.types = types;
        }
        
        public String getName() {
            return name;
        }
        
        public List<KnowledgeExtractionType> getTypes() {
            return types;
        }
    }
    
    /**
     * 将番茄服务的相对路径转换为前端可访问的完整URL
     * 
     * 开发环境：/api/novels/123/cover -> http://localhost:5000/api/novels/123/cover
     * 生产环境：/api/novels/123/cover -> https://maliangwriter.com/api/fanqie/novels/123/cover
     * 
     * @param relativePath 相对路径，例如：/api/novels/123/cover
     * @return 前端可访问的完整URL
     */
    private String buildFullCoverUrl(String relativePath) {
        if (relativePath == null || relativePath.isEmpty()) {
            return null;
        }
        
        // 如果已经是完整URL，直接返回
        if (relativePath.startsWith("http://") || relativePath.startsWith("https://")) {
            return relativePath;
        }
        
        // 判断是否是生产环境（通过 public-url 包含 https 来判断）
        if (fanqiePublicUrl.startsWith("https://")) {
            // 生产环境：转换为 Nginx 代理路径
            // /api/novels/123/cover -> https://maliangwriter.com/api/fanqie/novels/123/cover
            String path = relativePath.replace("/api/", "/");
            return fanqiePublicUrl + path;
        } else {
            // 开发环境：直接拼接
            // /api/novels/123/cover -> http://localhost:5000/api/novels/123/cover
            return fanqiePublicUrl + relativePath;
        }
    }
}

