package com.ainovel.server.service.impl;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.MalformedInputException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.dto.ParsedNovelData;
import com.ainovel.server.domain.dto.ParsedSceneData;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.repository.NovelRepository;
import com.ainovel.server.repository.SceneRepository;
import com.ainovel.server.service.ImportService;
import com.ainovel.server.service.IndexingService;
import com.ainovel.server.service.MetadataService;
import com.ainovel.server.service.NovelParser;
import com.ainovel.server.service.TokenEstimationService;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.task.dto.batchsummary.BatchGenerateSummaryParameters;
import com.ainovel.server.web.dto.ImportStatus;
import com.ainovel.server.web.dto.ImportPreviewRequest;
import com.ainovel.server.web.dto.ImportPreviewResponse;
import com.ainovel.server.web.dto.ImportConfirmRequest;
import com.ainovel.server.web.dto.ImportSessionInfo;
import com.ainovel.server.web.dto.ChapterPreview;
import com.ainovel.server.web.dto.ChapterDetailDto;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.common.util.PromptUtil;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.core.scheduler.Schedulers;

/**
 * 小说导入服务实现类
 */
@Slf4j
@Service
public class ImportServiceImpl implements ImportService {

    private final NovelRepository novelRepository;
    private final SceneRepository sceneRepository;
    private final IndexingService indexingService;
    private final MetadataService metadataService;
    private final List<NovelParser> parsers;
    private final TaskSubmissionService taskSubmissionService;
    private final UserAIModelConfigService userAIModelConfigService;
    private final TokenEstimationService tokenEstimationService;

    // 使用ConcurrentHashMap存储活跃的导入任务Sink
    private final Map<String, Sinks.Many<ServerSentEvent<ImportStatus>>> activeJobSinks = new ConcurrentHashMap<>();

    // 用于跟踪任务是否被取消的标记
    private final Map<String, Boolean> cancelledJobs = new ConcurrentHashMap<>();

    // 用于跟踪处理任务的临时文件路径
    private final Map<String, Path> jobTempFiles = new ConcurrentHashMap<>();

    // 用于存储jobId到novelId的映射关系
    private final Map<String, String> jobToNovelIdMap = new ConcurrentHashMap<>();

    // 用于存储进度更新订阅
    private final Map<String, reactor.core.Disposable> progressUpdateSubscriptions = new ConcurrentHashMap<>();

    // 用于存储预览会话信息
    private final Map<String, ImportSessionInfo> previewSessions = new ConcurrentHashMap<>();

    // 用于存储解析后的数据（按会话ID）
    private final Map<String, ParsedNovelData> parsedDataCache = new ConcurrentHashMap<>();

    @Autowired
    public ImportServiceImpl(
            NovelRepository novelRepository,
            SceneRepository sceneRepository,
            IndexingService indexingService,
            MetadataService metadataService,
            List<NovelParser> parsers,
            TaskSubmissionService taskSubmissionService,
            UserAIModelConfigService userAIModelConfigService,
            TokenEstimationService tokenEstimationService) {
        this.novelRepository = novelRepository;
        this.sceneRepository = sceneRepository;
        this.indexingService = indexingService;
        this.metadataService = metadataService;
        this.parsers = parsers;
        this.taskSubmissionService = taskSubmissionService;
        this.userAIModelConfigService = userAIModelConfigService;
        this.tokenEstimationService = tokenEstimationService;
    }

    @Override
    public Mono<String> startImport(FilePart filePart, String userId) {
        String jobId = UUID.randomUUID().toString();
        Path tempFilePath = null; // 用于后续清理
        try {
            // 1. 创建 Sink 并存储
            Sinks.Many<ServerSentEvent<ImportStatus>> sink = Sinks.many().multicast().onBackpressureBuffer();
            activeJobSinks.put(jobId, sink);
            log.info("创建 Sink 并存储 {}", jobId);

            // 2. 创建临时文件路径 (不立即创建文件)
            tempFilePath = Files.createTempFile("import-", "-" + filePart.filename());
            jobTempFiles.put(jobId, tempFilePath);
            final Path finalTempFilePath = tempFilePath; // For use in lambda

            // 3. 定义文件传输和处理的响应式管道
            Mono<Void> processingPipeline = filePart.transferTo(finalTempFilePath) // transferTo 是响应式的
                    .then(Mono.<Void>defer(() -> processAndSaveNovel(jobId, finalTempFilePath, filePart.filename(), userId, sink) // 核心处理逻辑
                            .subscribeOn(Schedulers.boundedElastic()) // 在弹性线程池执行核心逻辑
                    ))
                    .doOnError(e -> { // 处理管道中的错误
                        log.error("Import pipeline error for job {}", jobId, e);
                        sink.tryEmitNext(createStatusEvent(jobId, "FAILED", "导入失败: " + e.getMessage()));
                        sink.tryEmitComplete();
                        activeJobSinks.remove(jobId); // 清理 Sink
                        cancelledJobs.remove(jobId); // 清理取消标记
                        cleanupTempFile(jobId); // 清理临时文件
                    })
                    .doFinally(signalType -> { // 清理临时文件
                        cleanupTempFile(jobId); // 清理临时文件

                        // 确保 Sink 被移除，即使没有错误但正常完成
                        if (activeJobSinks.containsKey(jobId)) {
                            activeJobSinks.remove(jobId);
                        }

                        // 移除取消标记
                        cancelledJobs.remove(jobId);
                    });

            // 4. 异步订阅并启动管道 (Fire-and-forget)
            processingPipeline.subscribe(
                    null, // onNext - not needed for Mono<Void>
                    error -> log.error("Error subscribing to processing pipeline for job {}", jobId, error) // Log subscription errors
            );

            // 5. 立即返回 Job ID
            return Mono.just(jobId);

        } catch (IOException e) {
            log.error("Failed to create temporary file for import", e);
            // 如果创建临时文件失败，也需要处理
            cleanupTempFile(jobId);

            // 移除可能已添加的Sink和取消标记
            activeJobSinks.remove(jobId);
            cancelledJobs.remove(jobId);

            return Mono.error(new RuntimeException("无法启动导入任务：无法创建临时文件", e));
        }
    }

    /**
     * 清理临时文件
     */
    private void cleanupTempFile(String jobId) {
        Path tempPath = jobTempFiles.remove(jobId);
        if (tempPath != null && Files.exists(tempPath)) {
            try {
                Files.delete(tempPath);
                log.info("Deleted temporary file for job {}: {}", jobId, tempPath);
            } catch (IOException e) {
                log.error("Failed to delete temporary file for job {}: {}", jobId, tempPath, e);
            }
        }
    }

    @Override
    public Flux<ServerSentEvent<ImportStatus>> getImportStatusStream(String jobId) {
        log.info(">>> getImportStatusStream started for jobID: {}", jobId);
        Sinks.Many<ServerSentEvent<ImportStatus>> sink = activeJobSinks.get(jobId);
        log.info(">>> Sink found for job {}: {}", jobId, (sink != null));

        if (sink != null) {
            // 添加心跳机制，每30秒发送一次注释行作为心跳
            log.info(">>> Returning sink.asFlux() for job {}", jobId);
            return sink.asFlux().log("sse-stream-" + jobId); // Return the business event stream directly

        } else {
            log.warn(">>> Sink not found for job {}, returning ERROR event.", jobId);
            return Flux.just(
                    ServerSentEvent.<ImportStatus>builder()
                            .id(jobId)
                            .event("import-status")
                            .data(new ImportStatus("ERROR", "任务不存在或已完成"))
                            .build()
            );
        }
    }

    /**
     * 处理并保存小说（运行在boundedElastic调度器上）
     */
    private Mono<Void> processAndSaveNovel(
            String jobId,
            Path tempFilePath,
            String originalFilename,
            String userId,
            Sinks.Many<ServerSentEvent<ImportStatus>> sink) {

        return Mono.fromCallable(() -> {
            // 检查是否已取消
            if (isCancelled(jobId)) {
                throw new InterruptedException("导入任务已被用户取消");
            }

            sink.tryEmitNext(createStatusEvent(jobId, "PROCESSING", "开始解析文件..."));
            log.info("Job {}: Processing file {}", jobId, originalFilename);

            NovelParser parser = getParserForFile(originalFilename);

            // 尝试使用多种常见编码读取，避免因未知编码导致 UTF-8 解析失败
            List<String> fileLines;
            try {
                fileLines = readFileLinesWithAutoCharset(tempFilePath);
            } catch (IOException e) {
                log.error("Job {}: 读取文件失败", jobId, e);
                throw new RuntimeException("读取文件失败: " + e.getMessage(), e);
            }

            // 预处理：去除噪声与站点广告行，避免影响章节分割
            fileLines = preprocessLines(fileLines);

            ParsedNovelData parsedData = parser.parseStream(fileLines.stream());

            // 检查是否已取消
            if (isCancelled(jobId)) {
                throw new InterruptedException("导入任务已被用户取消");
            }

            // 始终使用文件名作为小说标题
            String title = extractTitleFromFilename(originalFilename);
            parsedData.setNovelTitle(title);
            log.info("Job {}: 使用文件名 '{}' 作为小说标题。", jobId, title);

            log.info("Job {}: Parsed data obtained. Scene count: {}", jobId, parsedData.getScenes().size());
            sink.tryEmitNext(createStatusEvent(jobId, "SAVING", "解析完成，发现 " + parsedData.getScenes().size() + " 个场景，正在保存小说结构..."));

            log.info("Job {}: About to call saveNovelAndScenesReactive...", jobId);
            // 现在调用 saveNovelAndScenesReactive
            return saveNovelAndScenesReactive(parsedData, userId)
                    .flatMap(savedNovel -> {
                        // 检查是否已取消
                        if (isCancelled(jobId)) {
                            return Mono.error(new InterruptedException("导入任务已被用户取消"));
                        }

                        log.info("Job {}: Novel and scenes saved successfully. Novel ID: {}", jobId, savedNovel.getId());
                        sink.tryEmitNext(createStatusEvent(jobId, "INDEXING", "小说结构保存完成，正在为 RAG 创建索引..."));

                        // 创建一个定时发送进度更新的流
                        Flux<Long> progressUpdates = Flux.interval(java.time.Duration.ofSeconds(10))
                                .doOnNext(tick -> {
                                    // 检查是否被取消
                                    if (isCancelled(jobId)) {
                                        log.warn("Job {}: 检测到任务已取消，停止进度更新", jobId);
                                        throw new RuntimeException("任务已取消");
                                    }

                                    String message = String.format("正在为 RAG 创建索引，已处理 %d 秒，请耐心等待...", (tick + 1) * 10);
                                    log.info("Job {}: Sending progress update: {}", jobId, message);
                                    sink.tryEmitNext(createStatusEvent(jobId, "INDEXING", message));
                                });

                        // 触发 RAG 索引，同时发送进度更新
                        return Mono.defer(() -> {
                            // 开始发送进度更新，使用线程安全的方式存储 Disposable
                            final java.util.concurrent.atomic.AtomicReference<reactor.core.Disposable> progressRef
                                    = new java.util.concurrent.atomic.AtomicReference<>();

                            log.info("Job {}: Starting progress updates", jobId);
                            var subscription = progressUpdates
                                    .doOnSubscribe(s -> log.info("Job {}: Progress updates subscribed", jobId))
                                    .doOnCancel(() -> log.info("Job {}: Progress updates cancelled", jobId))
                                    .onErrorResume(error -> {
                                        // 如果是因为取消而产生的错误，记录日志但不继续传播错误
                                        if (error.getMessage() != null && error.getMessage().contains("任务已取消")) {
                                            log.info("Job {}: Progress updates stopped due to task cancellation", jobId);
                                            return Flux.empty();
                                        }
                                        log.warn("Job {}: Progress updates error: {}", jobId, error.getMessage());
                                        return Flux.error(error);
                                    })
                                    .subscribe();

                            progressRef.set(subscription);
                            // 存储订阅以便可以在取消时使用
                            progressUpdateSubscriptions.put(jobId, subscription);

                            // 保存jobId和novelId的映射关系，以便后续取消操作
                            jobToNovelIdMap.put(jobId, savedNovel.getId());
                            log.info("Job {}: 已建立与Novel ID: {}的映射关系", jobId, savedNovel.getId());

                            // 执行实际的索引操作
                            return indexingService.indexNovel(savedNovel.getId())
                                    .doOnSuccess(result -> {
                                        // 检查是否被取消
                                        if (isCancelled(jobId)) {
                                            return;
                                        }

                                        log.info("Job {}: RAG indexing successfully completed for Novel ID: {}", jobId, savedNovel.getId());
                                        
                                        // 确保取消进度更新
                                        try {
                                            var disposable = progressRef.getAndSet(null);
                                            if (disposable != null) {
                                                disposable.dispose();
                                                log.info("Job {}: Progress updates disposed after success", jobId);
                                            }

                                            // 清理进度更新订阅
                                            progressUpdateSubscriptions.remove(jobId);
                                        } catch (Exception e) {
                                            log.error("Job {}: Error disposing progress updates", jobId, e);
                                        }
                                        
                                        // 发送RAG索引完成通知
                                        sink.tryEmitNext(createStatusEvent(jobId, "RAG_INDEXED", "RAG索引成功完成"));
                                    })
                                    .doOnError(error -> {
                                        log.error("Job {}: RAG indexing failed for Novel ID: {}", jobId, savedNovel.getId(), error);
                                        // 确保取消进度更新
                                        try {
                                            var disposable = progressRef.getAndSet(null);
                                            if (disposable != null) {
                                                disposable.dispose();
                                                log.info("Job {}: Progress updates disposed after error", jobId);
                                            }

                                            // 清理进度更新订阅
                                            progressUpdateSubscriptions.remove(jobId);
                                        } catch (Exception e) {
                                            log.error("Job {}: Error disposing progress updates", jobId, e);
                                        }
                                        // 发送失败通知
                                        sink.tryEmitNext(createStatusEvent(jobId, "FAILED", "RAG 索引失败: " + error.getMessage()));
                                        sink.tryEmitComplete();
                                    })
                                    // 索引完成后，提交批量生成摘要任务
                                    .then(Mono.defer(() -> {
                                        // 检查是否被取消
                                        if (isCancelled(jobId)) {
                                            return Mono.empty();
                                        }
                                        
                                        // 提交批量生成摘要的任务
                                        return submitBatchSummaryTask(savedNovel.getId(), userId, null)
                                            .doOnSuccess(taskId -> {
                                                if (taskId != null) {
                                                    log.info("Job {}: 为小说 {} 提交了批量生成摘要任务，任务ID: {}", 
                                                             jobId, savedNovel.getId(), taskId);
                                                    sink.tryEmitNext(createStatusEvent(jobId, "SUMMARY_TASK_SUBMITTED", 
                                                                    "已在后台启动摘要生成任务，将自动为所有章节生成摘要"));
                                                } else {
                                                    log.warn("Job {}: 批量生成摘要任务未能成功提交", jobId);
                                                }
                                            })
                                            .doOnError(error -> {
                                                log.error("Job {}: 提交批量生成摘要任务失败", jobId, error);
                                            })
                                            .onErrorResume(e -> Mono.empty()) // 如果提交摘要任务失败，继续流程
                                            .then(Mono.defer(() -> {
                                                // 清理相关映射 
                                                jobToNovelIdMap.remove(jobId);
                                                // 发送最终完成通知
                                                sink.tryEmitNext(createStatusEvent(jobId, "COMPLETED", "导入和索引成功完成！"));
                                                sink.tryEmitComplete();
                                                return Mono.empty();
                                            }));
                                    }));
                        });
                });
        }).flatMap(Function.identity()) // 展平 Mono<Mono<Void>>
                .doOnError(e -> { // 捕获 processAndSaveNovel 内部的同步异常或响应式链中的错误
                    // 检查是否是取消导致的错误
                    if (e instanceof InterruptedException) {
                        log.info("Job {}: Import was cancelled by user", jobId);
                        sink.tryEmitNext(createStatusEvent(jobId, "CANCELLED", "导入任务已被用户取消"));
                    } else {
                        log.error("Job {}: Processing failed.", jobId, e);
                        sink.tryEmitNext(createStatusEvent(jobId, "FAILED", "导入处理失败: " + e.getMessage()));
                    }
                    sink.tryEmitComplete();
                }).then(); // 转换为 Mono<Void>
    }

    /**
     * 检查任务是否已被取消
     */
    private boolean isCancelled(String jobId) {
        boolean cancelled = cancelledJobs.getOrDefault(jobId, false);
        if (cancelled) {
            log.debug("任务已被标记为取消状态: {}", jobId);
        }
        return cancelled;
    }

    /**
     * 保存小说和场景（响应式方式）
     */
    private Mono<Novel> saveNovelAndScenesReactive(ParsedNovelData parsedData, String userId) {
        log.info(">>> saveNovelAndScenesReactive started for novel: {} userId: {} ", parsedData.getNovelTitle(), userId);
        LocalDateTime novelNow = LocalDateTime.now(); // 时间戳用于 Novel

        // 创建Novel对象
        Novel novel = Novel.builder()
                .title(parsedData.getNovelTitle())
                .author(Novel.Author.builder().id(userId).build())
                .status("draft")
                .createdAt(novelNow) // 使用 Novel 的时间戳
                .updatedAt(novelNow) // 使用 Novel 的时间戳
                .build();

        // 先保存小说
        log.info(">>> Attempting to save novel: {}", novel.getTitle());
        return novelRepository.save(novel)
                .flatMap(savedNovel -> {
                    log.info(">>> Novel saved successfully with ID: {}", savedNovel.getId()); // 保存成功日志
                    List<Scene> scenes = new ArrayList<>();

                    // 创建场景列表 - 每个解析出的章节单独一个章节，每个章节默认创建一个场景
                    for (int i = 0; i < parsedData.getScenes().size(); i++) {
                        ParsedSceneData parsedScene = parsedData.getScenes().get(i);
                        LocalDateTime sceneNow = LocalDateTime.now(); // 为每个 Scene 获取独立的时间戳

                        // 使用UUID生成场景ID，与前端保持一致
                        String sceneId = UUID.randomUUID().toString();

                        // 将普通文本转换为富文本格式 - 调用 PromptUtil
                        String richTextContent = PromptUtil.convertPlainTextToQuillDelta(parsedScene.getSceneContent());

                        Scene scene = Scene.builder()
                                .id(sceneId)
                                .novelId(savedNovel.getId())
                                .title(parsedScene.getSceneTitle())
                                .content(richTextContent)
                                .summary("")
                                .sequence(parsedScene.getOrder())
                                .sceneType("NORMAL")
                                .characterIds(new ArrayList<>())
                                .locations(new ArrayList<>())
                                .version(0)
                                .history(new ArrayList<>())
                                .createdAt(sceneNow) // 使用 Scene 的时间戳
                                .updatedAt(sceneNow) // 使用 Scene 的时间戳
                                .build();

                        // 使用元数据服务计算并设置场景字数
                        metadataService.updateSceneMetadata(scene);

                        scenes.add(scene);
                    }

                    // 批量保存场景
                    return sceneRepository.saveAll(scenes)
                            .collectList()
                            .flatMap(savedScenes -> {
                                // 使用元数据服务更新小说元数据
                                return metadataService.updateNovelMetadata(savedNovel.getId())
                                        .flatMap(updatedNovel -> {
                                            // 创建基本结构 - 一个卷，每个场景一个章节
                                            Novel.Act act = Novel.Act.builder()
                                                    .id(UUID.randomUUID().toString())
                                                    .title("第一卷")
                                                    .description("")
                                                    .order(0)
                                                    .chapters(new ArrayList<>())
                                                    .build();

                                            // 创建章节并更新场景的chapterId
                                            List<Scene> updatedScenes = new ArrayList<>();

                                            for (int i = 0; i < savedScenes.size(); i++) {
                                                Scene scene = savedScenes.get(i);
                                                // 生成章节ID，格式为"chapter_" + UUID
                                                String chapterId = UUID.randomUUID().toString();

                                                Novel.Chapter chapter = Novel.Chapter.builder()
                                                        .id(chapterId)
                                                        .title(scene.getTitle())
                                                        .description("")
                                                        .order(i)
                                                        .sceneIds(List.of(scene.getId()))
                                                        .build();

                                                // 更新场景的chapterId
                                                scene.setChapterId(chapterId);
                                                updatedScenes.add(scene);

                                                // 添加章节到卷中
                                                act.getChapters().add(chapter);
                                                if (i == 0) {
                                                    updatedNovel.setLastEditedChapterId(chapterId);
                                                }
                                            }

                                            updatedNovel.getStructure().getActs().add(act);

                                            // 保存更新后的场景和小说
                                            return sceneRepository.saveAll(updatedScenes)
                                                    .collectList()
                                                    .then(novelRepository.save(updatedNovel));
                                        });
                            });
                });
    }

    /**
     * 根据文件名获取对应的解析器
     */
    private NovelParser getParserForFile(String filename) {
        String extension = getFileExtension(filename).toLowerCase();

        // 查找支持该扩展名的解析器
        return parsers.stream()
                .filter(parser -> parser.getSupportedExtension().equalsIgnoreCase(extension))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("不支持的文件类型: " + extension));
    }

    /**
     * 从文件名中提取文件扩展名
     */
    private String getFileExtension(String filename) {
        int lastDotPosition = filename.lastIndexOf('.');
        if (lastDotPosition > 0) {
            return filename.substring(lastDotPosition + 1);
        }
        return "";
    }

    /**
     * 从文件名中提取小说标题
     */
    private String extractTitleFromFilename(String filename) {
        int lastDotPosition = filename.lastIndexOf('.');
        if (lastDotPosition > 0) {
            String nameWithoutExtension = filename.substring(0, lastDotPosition);
            return nameWithoutExtension.replaceAll("[-_]", " ").trim();
        }
        return filename;
    }

    /**
     * 创建SSE状态事件
     */
    private ServerSentEvent<ImportStatus> createStatusEvent(String jobId, String status, String message) {
        return ServerSentEvent.<ImportStatus>builder()
                .id(jobId)
                .event("import-status")
                .data(new ImportStatus(status, message))
                .build();
    }

    /**
     * 取消导入任务
     */
    @Override
    public Mono<Boolean> cancelImport(String jobId) {
        log.info("接收到取消导入任务请求: {}", jobId);

        // 获取任务的Sink
        Sinks.Many<ServerSentEvent<ImportStatus>> sink = activeJobSinks.get(jobId);

        if (sink == null) {
            log.warn("取消导入任务失败: 任务 {} 不存在或已完成", jobId);
            return Mono.just(false);
        }

        try {
            // 先取消进度更新订阅，避免继续发送进度消息
            reactor.core.Disposable subscription = progressUpdateSubscriptions.remove(jobId);
            if (subscription != null && !subscription.isDisposed()) {
                subscription.dispose();
                log.info("Job {}: 已取消进度更新订阅", jobId);
            }

            // 标记任务为已取消
            cancelledJobs.put(jobId, true);

            // 发送取消状态到客户端
            sink.tryEmitNext(createStatusEvent(jobId, "CANCELLED", "导入任务已取消"));

            // 完成Sink
            sink.tryEmitComplete();

            // 从活跃任务中移除
            activeJobSinks.remove(jobId);

            // 清理临时文件
            cleanupTempFile(jobId);

            // 尝试取消索引任务
            try {
                // 首先，尝试使用jobId直接取消（可能正在执行的是前置任务）
                boolean cancelled = indexingService.cancelIndexingTask(jobId);

                // 其次，检查是否有关联的novelId，如果有，也尝试取消它
                String novelId = jobToNovelIdMap.get(jobId);
                if (novelId != null) {
                    // 使用关联的novelId取消索引任务
                    boolean novelCancelled = indexingService.cancelIndexingTask(novelId);
                    log.info("使用novelId({})取消索引任务: {}", novelId, novelCancelled ? "成功" : "失败或不需要");
                    cancelled = cancelled || novelCancelled;
                }

                // 清理映射关系
                jobToNovelIdMap.remove(jobId);

                log.info("已经发送取消信号到索引任务: {} (结果: {})", jobId, cancelled ? "成功" : "失败或不需要");
            } catch (Exception e) {
                log.warn("尝试取消索引任务时出错，但不影响导入取消操作: {}", e.getMessage());
            }

            log.info("成功取消导入任务: {}", jobId);
            return Mono.just(true);
        } catch (Exception e) {
            log.error("取消导入任务异常: {}", jobId, e);
            return Mono.just(false);
        }
    }

    /**
     * 提交批量生成摘要的后台任务
     * 
     * @param novelId 小说ID
     * @param userId 用户ID 
     * @return 任务ID的Mono
     */
    private Mono<String> submitBatchSummaryTask(String novelId, String userId, String requestedAiConfigId) {
        return novelRepository.findById(novelId)
            .flatMap(novel -> {
                // 获取小说的第一个和最后一个章节ID
                final String[] chapterIds = new String[2]; // [0]:firstChapterId, [1]:lastChapterId
                
                if (novel.getStructure() != null && 
                    novel.getStructure().getActs() != null && 
                    !novel.getStructure().getActs().isEmpty()) {
                    
                    // 找到第一个章节
                    outer1: for (var act : novel.getStructure().getActs()) {
                        if (act.getChapters() != null && !act.getChapters().isEmpty()) {
                            chapterIds[0] = act.getChapters().get(0).getId();
                            break outer1;
                        }
                    }
                    
                    // 找到最后一个章节
                    outer2: for (int i = novel.getStructure().getActs().size() - 1; i >= 0; i--) {
                        var act = novel.getStructure().getActs().get(i);
                        if (act.getChapters() != null && !act.getChapters().isEmpty()) {
                            chapterIds[1] = act.getChapters().get(act.getChapters().size() - 1).getId();
                            break outer2;
                        }
                    }
                }
                
                if (chapterIds[0] == null || chapterIds[1] == null) {
                    log.warn("小说 {} 没有章节，无法启动批量生成摘要任务", novelId);
                    return Mono.empty();
                }
                
                Mono<String> aiConfigIdMono;
                if (requestedAiConfigId != null && !requestedAiConfigId.isBlank()) {
                    aiConfigIdMono = Mono.just(requestedAiConfigId);
                } else {
                    // 获取用户的默认AI配置ID
                    aiConfigIdMono = userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                        .map(config -> config.getId())
                        .defaultIfEmpty("default");
                }

                return aiConfigIdMono.flatMap(aiConfigId -> {
                    // 构建任务参数
                    BatchGenerateSummaryParameters parameters = BatchGenerateSummaryParameters.builder()
                        .novelId(novelId)
                        .startChapterId(chapterIds[0])
                        .endChapterId(chapterIds[1])
                        .aiConfigId(aiConfigId)
                        .overwriteExisting(true)
                        .build();
                    
                    log.info("为小说 {} 提交批量生成摘要任务, 用户: {}, AI配置: {}", novelId, userId, aiConfigId);
                    
                    // 提交任务
                    return taskSubmissionService.submitTask(userId, "BATCH_GENERATE_SUMMARY", parameters);
                });
            });
    }

    @Override
    public Mono<String> uploadFileForPreview(FilePart filePart, String userId) {
        String sessionId = UUID.randomUUID().toString();
        
        log.info("开始上传文件用于预览: sessionId={}, userId={}, fileName={}", 
                sessionId, userId, filePart.filename());

        return Mono.fromCallable(() -> {
            try {
                // 创建临时文件
                Path tempFilePath = Files.createTempFile("preview-import-", "-" + filePart.filename());
                
                // 创建会话信息
                ImportSessionInfo sessionInfo = ImportSessionInfo.builder()
                        .sessionId(sessionId)
                        .userId(userId)
                        .originalFileName(filePart.filename())
                        .tempFilePath(tempFilePath.toString())
                        .fileSize(filePart.headers().getContentLength())
                        .createdAt(LocalDateTime.now())
                        .expiresAt(LocalDateTime.now().plusHours(2)) // 2小时后过期
                        .parseStatus("UPLOADED")
                        .cleaned(false)
                        .build();

                previewSessions.put(sessionId, sessionInfo);
                
                return tempFilePath;
            } catch (IOException e) {
                throw new RuntimeException("创建临时文件失败", e);
            }
        })
        .flatMap(tempFilePath -> filePart.transferTo(tempFilePath).thenReturn(sessionId))
        .doOnSuccess(result -> log.info("文件上传成功: sessionId={}, userId={}", sessionId, userId))
        .onErrorResume(e -> {
            log.error("文件上传失败: sessionId={}, userId={}", sessionId, userId, e);
            cleanupPreviewSession(sessionId).subscribe(); // 清理失败的会话
            return Mono.error(new RuntimeException("文件上传失败: " + e.getMessage()));
        });
    }

    @Override
    public Mono<ImportPreviewResponse> getImportPreview(ImportPreviewRequest request) {
        String sessionId = request.getFileSessionId();
        
        log.info("获取导入预览: sessionId={}, 章节限制={}, AI摘要={}", 
                sessionId, request.getChapterLimit(), request.getEnableAISummary());

        ImportSessionInfo sessionInfo = previewSessions.get(sessionId);
        if (sessionInfo == null || sessionInfo.getCleaned()) {
            return Mono.error(new RuntimeException("预览会话不存在或已过期"));
        }

        return Mono.fromCallable(() -> {
            try {
                Path tempFilePath = Paths.get(sessionInfo.getTempFilePath());
                if (!Files.exists(tempFilePath)) {
                    throw new RuntimeException("临时文件不存在");
                }

                // 解析文件
                NovelParser parser = getParserForFile(sessionInfo.getOriginalFileName());
                List<String> fileLines = readFileLinesWithAutoCharset(tempFilePath);

                // 预处理：去除噪声与站点广告行，避免影响章节分割
                fileLines = preprocessLines(fileLines);

                ParsedNovelData parsedData = parser.parseStream(fileLines.stream());

                // 设置标题
                String title = request.getCustomTitle();
                if (title == null || title.trim().isEmpty()) {
                    title = extractTitleFromFilename(sessionInfo.getOriginalFileName());
                }
                parsedData.setNovelTitle(title);

                // 缓存解析数据
                parsedDataCache.put(sessionId, parsedData);

                // 创建章节预览列表
                List<ChapterPreview> chapterPreviews = new ArrayList<>();
                List<ParsedSceneData> scenes = parsedData.getScenes();
                int previewCount = Math.min(
                        request.getPreviewChapterCount() != null ? request.getPreviewChapterCount() : 10,
                        scenes.size()
                );

                // ✅ 计算全本字数（所有章节）
                int totalWordCount = 0;
                for (ParsedSceneData scene : scenes) {
                    totalWordCount += scene.getSceneContent().length();
                }
                
                // 创建章节预览（只预览前N章）
                for (int i = 0; i < previewCount; i++) {
                    ParsedSceneData scene = scenes.get(i);
                    String content = scene.getSceneContent();
                    
                    int wordCount = content.length(); // 简单字数统计
                    
                    ChapterPreview preview = new ChapterPreview();
                    preview.setChapterIndex(i);
                    preview.setTitle(scene.getSceneTitle());
                    preview.setContentPreview(content.length() > 200 ? content.substring(0, 200) + "..." : content);
                    preview.setFullContentLength(content.length());
                    preview.setWordCount(wordCount);
                    preview.setSelected(request.getChapterLimit() == null || 
                                      request.getChapterLimit() == -1 || 
                                      i < request.getChapterLimit());
                    
                    chapterPreviews.add(preview);
                }

                // 构建响应
                ImportPreviewResponse.ImportPreviewResponseBuilder responseBuilder = ImportPreviewResponse.builder()
                        .previewSessionId(sessionId)
                        .detectedTitle(parsedData.getNovelTitle())
                        .totalChapterCount(scenes.size())
                        .chapterPreviews(chapterPreviews)
                        .totalWordCount(totalWordCount)
                        .warnings(new ArrayList<>());

                // 如果启用AI功能，进行估算
                if (Boolean.TRUE.equals(request.getEnableAISummary()) && 
                    request.getAiConfigId() != null && !request.getAiConfigId().isEmpty()) {
                    
                    // 简单的AI估算
                    responseBuilder.aiEstimation(ImportPreviewResponse.AIEstimation.builder()
                            .supported(true)
                            .estimatedTokens((long)(totalWordCount * 1.3)) // 简单估算
                            .estimatedCost(totalWordCount * 1.3 * 0.01 / 1000) // 简单成本估算
                            .estimatedTimeMinutes(Math.max(1, scenes.size() / 10)) // 估算时间
                            .selectedModel("默认模型")
                            .limitations("这是简化估算，实际可能有差异")
                            .build());
                } else {
                    responseBuilder.aiEstimation(ImportPreviewResponse.AIEstimation.builder()
                            .supported(false)
                            .limitations("未启用AI功能或未配置AI模型")
                            .build());
                }

                return responseBuilder.build();

            } catch (Exception e) {
                log.error("解析预览文件失败: sessionId={}", sessionId, e);
                throw new RuntimeException("解析文件失败: " + e.getMessage());
            }
        })
        .subscribeOn(Schedulers.boundedElastic())
        .onErrorResume(e -> {
            log.error("获取导入预览失败: sessionId={}", sessionId, e);
            return Mono.error(e);
        });
    }

    @Override
    public Mono<String> confirmAndStartImport(ImportConfirmRequest request) {
        String sessionId = request.getPreviewSessionId();
        String jobId = UUID.randomUUID().toString();
        
        log.info("确认并开始导入: sessionId={}, jobId={}, 标题={}, aiConfigId={}, enableAISummary={}, enableSmartContext={}, userId={}", 
                sessionId, jobId, request.getFinalTitle(), request.getAiConfigId(), request.getEnableAISummary(), request.getEnableSmartContext(), request.getUserId());

        ImportSessionInfo sessionInfo = previewSessions.get(sessionId);
        if (sessionInfo == null || sessionInfo.getCleaned()) {
            return Mono.error(new RuntimeException("预览会话不存在或已过期"));
        }

        // 补充用户ID，如果前端未传递则使用上传预览阶段记录的用户ID
        if (request.getUserId() == null || request.getUserId().isBlank()) {
            request.setUserId(sessionInfo.getUserId());
        }

        ParsedNovelData parsedData = parsedDataCache.get(sessionId);
        if (parsedData == null) {
            return Mono.error(new RuntimeException("预览数据不存在，请重新获取预览"));
        }

        return Mono.fromCallable(() -> {
            try {
                // 创建Sink并存储
                Sinks.Many<ServerSentEvent<ImportStatus>> sink = Sinks.many().multicast().onBackpressureBuffer();
                activeJobSinks.put(jobId, sink);

                // 更新解析数据
                parsedData.setNovelTitle(request.getFinalTitle());
                
                // 如果选择了特定章节，过滤数据
                if (request.getSelectedChapterIndexes() != null && !request.getSelectedChapterIndexes().isEmpty()) {
                    List<ParsedSceneData> allScenes = parsedData.getScenes();
                    List<ParsedSceneData> selectedScenes = new ArrayList<>();
                    
                    for (Integer index : request.getSelectedChapterIndexes()) {
                        if (index >= 0 && index < allScenes.size()) {
                            selectedScenes.add(allScenes.get(index));
                        }
                    }
                    
                    parsedData.setScenes(selectedScenes);
                }

                // 异步处理导入
                Mono<Void> processingPipeline = saveNovelAndScenesReactive(parsedData, request.getUserId())
                        .flatMap(novel -> {
                            jobToNovelIdMap.put(jobId, novel.getId());
                            sink.tryEmitNext(createStatusEvent(jobId, "SAVING", "小说保存完成"));

                            // 如果启用AI摘要生成，提交后台任务
                            if (Boolean.TRUE.equals(request.getEnableAISummary()) && 
                                request.getAiConfigId() != null && !request.getAiConfigId().isEmpty()) {
                                
                                sink.tryEmitNext(createStatusEvent(jobId, "INDEXING", "开始生成AI摘要..."));
                                return submitBatchSummaryTask(novel.getId(), request.getUserId(), request.getAiConfigId())
                                        .doOnSuccess(taskId -> {
                                            sink.tryEmitNext(createStatusEvent(jobId, "COMPLETED", 
                                                    "导入完成，AI摘要生成任务已提交: " + taskId));
                                            sink.tryEmitComplete();
                                        });
                            } else {
                                sink.tryEmitNext(createStatusEvent(jobId, "COMPLETED", "导入完成"));
                                sink.tryEmitComplete();
                                return Mono.just("completed");
                            }
                        })
                        .doOnError(e -> {
                            log.error("确认导入处理失败: jobId={}", jobId, e);
                            sink.tryEmitNext(createStatusEvent(jobId, "FAILED", "导入失败: " + e.getMessage()));
                            sink.tryEmitComplete();
                        })
                        .doFinally(signalType -> {
                            activeJobSinks.remove(jobId);
                            jobToNovelIdMap.remove(jobId);
                            // 清理预览会话
                            cleanupPreviewSession(sessionId).subscribe();
                        })
                        .then();

                // 异步启动处理
                processingPipeline
                        .subscribeOn(Schedulers.boundedElastic())
                        .subscribe(
                                null,
                                error -> log.error("确认导入处理管道错误: jobId={}", jobId, error)
                        );

                return jobId;

            } catch (Exception e) {
                log.error("确认导入启动失败: sessionId={}", sessionId, e);
                throw new RuntimeException("启动导入失败: " + e.getMessage());
            }
        })
        .subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Void> cleanupPreviewSession(String previewSessionId) {
        log.info("清理预览会话: sessionId={}", previewSessionId);
        
        return Mono.fromRunnable(() -> {
            ImportSessionInfo sessionInfo = previewSessions.remove(previewSessionId);
            if (sessionInfo != null && !sessionInfo.getCleaned()) {
                // 删除临时文件
                try {
                    Path tempPath = Paths.get(sessionInfo.getTempFilePath());
                    if (Files.exists(tempPath)) {
                        Files.delete(tempPath);
                        log.info("删除临时文件: {}", tempPath);
                    }
                } catch (IOException e) {
                    log.error("删除预览临时文件失败: {}", sessionInfo.getTempFilePath(), e);
                }
                
                // 标记为已清理
                sessionInfo.setCleaned(true);
            }
            
            // 清理解析数据缓存
            parsedDataCache.remove(previewSessionId);
        })
        .subscribeOn(Schedulers.boundedElastic())
        .then();
    }
    
    @Override
    public Mono<String> getFullContentFromPreviewSession(String previewSessionId, Integer chapterLimit) {
        return Mono.fromCallable(() -> {
            log.info("从预览会话获取完整内容: sessionId={}, chapterLimit={}", previewSessionId, chapterLimit);
            
            ImportSessionInfo sessionInfo = previewSessions.get(previewSessionId);
            if (sessionInfo == null || sessionInfo.getCleaned()) {
                throw new RuntimeException("预览会话不存在或已过期");
            }
            
            // 先尝试从缓存获取
            ParsedNovelData parsedData = parsedDataCache.get(previewSessionId);
            
            if (parsedData == null) {
                // 如果缓存中没有，重新解析文件
                Path tempFilePath = Paths.get(sessionInfo.getTempFilePath());
                if (!Files.exists(tempFilePath)) {
                    throw new RuntimeException("临时文件不存在");
                }
                
                NovelParser parser = getParserForFile(sessionInfo.getOriginalFileName());
                List<String> fileLines = readFileLinesWithAutoCharset(tempFilePath);
                fileLines = preprocessLines(fileLines);
                
                parsedData = parser.parseStream(fileLines.stream());
                
                // 设置标题
                String title = extractTitleFromFilename(sessionInfo.getOriginalFileName());
                parsedData.setNovelTitle(title);
                
                // 缓存起来
                parsedDataCache.put(previewSessionId, parsedData);
            }
            
            // 拼接章节内容
            StringBuilder fullContent = new StringBuilder();
            List<ParsedSceneData> scenes = parsedData.getScenes();
            
            // 确定实际使用的章节数
            int totalChapters = scenes.size();
            int effectiveChapters = (chapterLimit != null && chapterLimit > 0) 
                    ? Math.min(chapterLimit, totalChapters) 
                    : totalChapters;
            
            for (int i = 0; i < effectiveChapters; i++) {
                ParsedSceneData scene = scenes.get(i);
                if (i > 0) {
                    fullContent.append("\n\n");
                }
                fullContent.append("【第").append(i + 1).append("章 ").append(scene.getSceneTitle()).append("】\n");
                fullContent.append(scene.getSceneContent());
            }
            
            String content = fullContent.toString();
            log.info("获取完整内容成功: sessionId={}, 总章节数={}, 使用章节数={}, 总字数={}", 
                    previewSessionId, totalChapters, effectiveChapters, content.length());
            
            return content;
        }).subscribeOn(Schedulers.boundedElastic());
    }
    
    @Override
    public Mono<Integer> getTotalChapterCountFromPreviewSession(String previewSessionId) {
        return Mono.fromCallable(() -> {
            log.info("从预览会话获取章节数量: sessionId={}", previewSessionId);
            
            ImportSessionInfo sessionInfo = previewSessions.get(previewSessionId);
            if (sessionInfo == null || sessionInfo.getCleaned()) {
                throw new RuntimeException("预览会话不存在或已过期");
            }
            
            // 先尝试从缓存获取
            ParsedNovelData parsedData = parsedDataCache.get(previewSessionId);
            
            if (parsedData == null) {
                // 如果缓存中没有，重新解析文件
                Path tempFilePath = Paths.get(sessionInfo.getTempFilePath());
                if (!Files.exists(tempFilePath)) {
                    throw new RuntimeException("临时文件不存在");
                }
                
                NovelParser parser = getParserForFile(sessionInfo.getOriginalFileName());
                List<String> fileLines = readFileLinesWithAutoCharset(tempFilePath);
                fileLines = preprocessLines(fileLines);
                
                parsedData = parser.parseStream(fileLines.stream());
                
                // 设置标题
                String title = extractTitleFromFilename(sessionInfo.getOriginalFileName());
                parsedData.setNovelTitle(title);
                
                // 缓存起来
                parsedDataCache.put(previewSessionId, parsedData);
            }
            
            int totalChapters = parsedData.getScenes().size();
            log.info("获取章节数量成功: sessionId={}, totalChapters={}", previewSessionId, totalChapters);
            
            return totalChapters;
        }).subscribeOn(Schedulers.boundedElastic());
    }
    
    @Override
    public Mono<List<ChapterDetailDto>> getChapterDetailsFromPreviewSession(
            String previewSessionId, Integer chapterLimit) {
        return Mono.fromCallable(() -> {
            log.info("从预览会话获取章节详情: sessionId={}, chapterLimit={}", previewSessionId, chapterLimit);
            
            ImportSessionInfo sessionInfo = previewSessions.get(previewSessionId);
            if (sessionInfo == null || sessionInfo.getCleaned()) {
                throw new RuntimeException("预览会话不存在或已过期");
            }
            
            // 先尝试从缓存获取
            ParsedNovelData parsedData = parsedDataCache.get(previewSessionId);
            
            if (parsedData == null) {
                // 如果缓存中没有，重新解析文件
                Path tempFilePath = Paths.get(sessionInfo.getTempFilePath());
                if (!Files.exists(tempFilePath)) {
                    throw new RuntimeException("临时文件不存在");
                }
                
                NovelParser parser = getParserForFile(sessionInfo.getOriginalFileName());
                List<String> fileLines = readFileLinesWithAutoCharset(tempFilePath);
                fileLines = preprocessLines(fileLines);
                
                parsedData = parser.parseStream(fileLines.stream());
                
                // 设置标题
                String title = extractTitleFromFilename(sessionInfo.getOriginalFileName());
                parsedData.setNovelTitle(title);
                
                // 缓存起来
                parsedDataCache.put(previewSessionId, parsedData);
            }
            
            // 获取章节列表
            List<ParsedSceneData> scenes = parsedData.getScenes();
            int totalChapters = scenes.size();
            int effectiveChapters = (chapterLimit != null && chapterLimit > 0) 
                    ? Math.min(chapterLimit, totalChapters) 
                    : totalChapters;
            
            // 转换为ChapterDetailDto
            List<ChapterDetailDto> chapterDetails = new ArrayList<>();
            for (int i = 0; i < effectiveChapters; i++) {
                ParsedSceneData scene = scenes.get(i);
                ChapterDetailDto detail = ChapterDetailDto.builder()
                        .index(i + 1)
                        .chapterId("user_imported_ch_" + (i + 1)) // 虚拟ID，标记为用户导入
                        .title(scene.getSceneTitle())
                        .content(scene.getSceneContent())
                        .wordCount(scene.getSceneContent().length())
                        .build();
                chapterDetails.add(detail);
            }
            
            log.info("获取章节详情成功: sessionId={}, 总章节数={}, 使用章节数={}", 
                    previewSessionId, totalChapters, chapterDetails.size());
            
            return chapterDetails;
        }).subscribeOn(Schedulers.boundedElastic());
    }

    /**
     * 尝试使用多种常见编码读取文本文件，优先 UTF-8，其次 GBK/GB18030，最后 ISO-8859-1。
     * 如果所有编码均失败，则抛出最后一次异常。
     */
    private List<String> readFileLinesWithAutoCharset(Path filePath) throws IOException {
        List<Charset> charsetCandidates = List.of(
                StandardCharsets.UTF_8,
                Charset.forName("GBK"),
                Charset.forName("GB18030"),
                StandardCharsets.ISO_8859_1
        );

        IOException lastException = null;
        for (Charset charset : charsetCandidates) {
            try {
                return Files.readAllLines(filePath, charset);
            } catch (MalformedInputException e) {
                // 记录并尝试下一个编码
                lastException = e;
                log.debug("读取文件使用编码 {} 失败，尝试下一个...", charset);
            }
        }

        // 如果全部失败，抛出最后一次异常
        throw lastException != null ? lastException : new IOException("无法解析文件编码");
    }

    /**
     * 预处理文本行，去除噪声与站点广告行，避免影响章节分割
     */
    private List<String> preprocessLines(List<String> lines) {
        List<String> processedLines = new ArrayList<>();
        for (String line : lines) {
            // 去除噪声与站点广告行，避免影响章节分割
            if (!line.trim().isEmpty() && !line.contains("广告") && !line.contains("站点")) {
                processedLines.add(line);
            }
        }
        return processedLines;
    }
}
