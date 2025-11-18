package com.ainovel.server.task.executor;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.NovelAIService;
import com.ainovel.server.service.UniversalAIService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionParameters;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionProgress;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionResult;

import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * 剧情推演任务执行器
 * 
 * 功能：
 * 1. 根据配置创建多个子任务并发执行
 * 2. 每个模型配置生成指定数量的剧情推演
 * 3. 支持两阶段生成：摘要 -> 场景内容（可选）
 * 4. 实时报告进度
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StoryPredictionTaskExecutor implements BackgroundTaskExecutable<StoryPredictionParameters, StoryPredictionResult> {
    
    private final NovelService novelService;
    private final NovelAIService novelAIService;
    private final UniversalAIService universalAIService;
    private final UserAIModelConfigService userAIModelConfigService;
    private final PublicModelConfigService publicModelConfigService;
    private final TaskStateService taskStateService;
    
    // 注意：不得在单例上共享预测进度缓存，避免不同任务/用户间串数据
    
    @Override
    public String getTaskType() {
        return "STORY_PREDICTION";
    }
    
    @Override
    public Mono<StoryPredictionResult> execute(TaskContext<StoryPredictionParameters> context) {
        StoryPredictionParameters parameters = context.getParameters();
        String taskId = context.getTaskId();
        
        log.info("开始执行剧情推演任务: taskId={}, novelId={}, chapterId={}", 
                taskId, parameters.getNovelId(), parameters.getChapterId());
        
        // 计算总预测数量
        int totalPredictions = parameters.getGenerationCount();
        
        // 初始化进度
        StoryPredictionProgress progress = StoryPredictionProgress.builder()
                .totalPredictions(totalPredictions)
                .completedPredictions(0)
                .failedPredictions(0)
                .currentStep("INITIALIZING")
                .lastUpdated(LocalDateTime.now())
                .build();
        
        LocalDateTime startTime = LocalDateTime.now();
        
        return context.updateProgress(progress)
                .then(novelService.findNovelById(parameters.getNovelId()))
                .switchIfEmpty(Mono.error(new IllegalArgumentException("找不到小说: " + parameters.getNovelId())))
                .flatMap(novel -> {
                    // 构建上下文
                    String contextContent = buildContext(novel, parameters);
                    
                    // 更新进度：开始生成
                    progress.setCurrentStep("GENERATING");
                    return context.updateProgress(progress)
                            .then(generatePredictions(context, parameters, novel, contextContent, startTime));
                })
                .doOnError(error -> {
                    log.error("剧情推演任务执行失败: taskId={}, error={}", taskId, error.getMessage(), error);
                });
    }
    
    /**
     * 生成所有预测
     */
    private Mono<StoryPredictionResult> generatePredictions(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            Novel novel,
            String contextContent,
            LocalDateTime startTime) {
        
        String taskId = context.getTaskId();
        // 为当前任务构建独立的预测进度缓存，避免跨任务共享导致串台
        ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache = new ConcurrentHashMap<>();
        
        // 创建所有预测任务
        List<Mono<StoryPredictionResult.PredictionItem>> predictionTasks = new ArrayList<>();
        List<StoryPredictionParameters.ModelConfig> modelConfigs = parameters.getModelConfigs();
        int totalPredictions = parameters.getGenerationCount();
        
        // 为每个预测创建子任务
        for (int i = 0; i < totalPredictions; i++) {
            final int predictionIndex = i;
            // 轮询选择模型
            StoryPredictionParameters.ModelConfig modelConfig = modelConfigs.get(i % modelConfigs.size());
            String predictionId = UUID.randomUUID().toString();
            
            // 创建子任务参数
            Map<String, Object> subTaskParams = new HashMap<>();
            subTaskParams.put("novelId", parameters.getNovelId());
            subTaskParams.put("chapterId", parameters.getChapterId());
            subTaskParams.put("predictionIndex", predictionIndex + 1);
            subTaskParams.put("modelConfigId", modelConfig.getConfigId());
            subTaskParams.put("modelType", modelConfig.getType());
            subTaskParams.put("generateSceneContent", parameters.getGenerateSceneContent());
            subTaskParams.put("styleInstructions", parameters.getStyleInstructions());
            
            // 提交子任务并执行预测
            Mono<StoryPredictionResult.PredictionItem> predictionTask = context.submitSubTask(
                "STORY_PREDICTION_SINGLE", 
                subTaskParams
            ).flatMap(subTaskId -> {
                log.info("剧情推演子任务已提交: {} (预测 {}/{})", subTaskId, predictionIndex + 1, totalPredictions);
                // 子任务置为运行中并记录初始进度（包含模型名）
                String modelName = getActualModelName(modelConfig, context.getUserId());
                return taskStateService.trySetRunning(subTaskId)
                        .then(taskStateService.recordProgress(subTaskId, Map.of(
                                "status", "STARTING",
                                "modelName", modelName,
                                "predictionIndex", predictionIndex + 1
                        )))
                        // 执行实际的预测生成，并在过程中同步子任务进度
                        .then(generateSinglePrediction(context, parameters, modelConfig, contextContent, predictionId, predictionIndex + 1, subTaskId, predictionCache));
            });
            
            predictionTasks.add(predictionTask);
        }
        
        // 并发执行所有预测任务
        return Flux.merge(predictionTasks)
                .collectList()
                .map(completedPredictions -> {
                    // 统计结果
                    long successCount = completedPredictions.stream()
                            .filter(p -> "COMPLETED".equals(p.getStatus()))
                            .count();
                    long failureCount = completedPredictions.size() - successCount;
                    
                    LocalDateTime endTime = LocalDateTime.now();
                    long executionTimeMs = java.time.Duration.between(startTime, endTime).toMillis();
                    
                    log.info("剧情推演任务完成: taskId={}, 成功={}, 失败={}, 耗时={}ms", 
                            taskId, successCount, failureCount, executionTimeMs);
                    
                    StoryPredictionResult result = StoryPredictionResult.builder()
                            .taskId(taskId)
                            .novelId(parameters.getNovelId())
                            .chapterId(parameters.getChapterId())
                            .totalPredictions(completedPredictions.size())
                            .successCount((int) successCount)
                            .failureCount((int) failureCount)
                            .predictions(completedPredictions)
                            .status("COMPLETED")
                            .startTime(startTime)
                            .completionTime(endTime)
                            .executionTimeMs(executionTimeMs)
                            .build();
                    
                    // 不保存到聊天历史，遵循产品：任务系统自身展示结果
                    
                    return result;
                })
                .doFinally(signal -> {
                    // 发送最终进度，包含所有预测结果
                    if (!predictionCache.isEmpty()) {
                        StoryPredictionProgress finalProgress = StoryPredictionProgress.builder()
                                .totalPredictions(predictionCache.size())
                                .completedPredictions(predictionCache.size())
                                .currentStep("COMPLETED")
                                .lastUpdated(LocalDateTime.now())
                                .predictionProgress(new ArrayList<>(predictionCache.values()))
                                .build();
                        context.updateProgress(finalProgress).subscribe();
                    }
                    // 清理缓存
                    predictionCache.clear();
                });
    }
    
    /**
     * 生成单个预测
     */
    private Mono<StoryPredictionResult.PredictionItem> generateSinglePrediction(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String contextContent,
            String predictionId,
            int index,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        log.debug("开始生成单个预测: predictionId={}, modelConfig={}, index={}", 
                predictionId, modelConfig.getConfigId(), index);
        
        // 创建预测进度对象
        StoryPredictionProgress.PredictionProgress predictionProgress = StoryPredictionProgress.PredictionProgress.builder()
                .predictionId(predictionId)
                .modelId(modelConfig.getConfigId())
                .modelName(getActualModelName(modelConfig, context.getUserId())) // 获取实际模型名称
                .status("STARTING")
                .startTime(LocalDateTime.now())
                .build();
        
        predictionCache.put(predictionId, predictionProgress);
        // 立即向父任务推送一次起始进度，避免前端无感知
        updateTaskProgress(context, predictionId, predictionCache);
        
        // 第一阶段：生成摘要
        return generateSummary(context, parameters, modelConfig, contextContent, predictionId, childTaskId, predictionCache)
                .flatMap(summary -> {
                    // 更新摘要状态
                    predictionProgress.setSummary(summary);
                    predictionProgress.setStatus("SUMMARY_COMPLETED");
                    
                    // 如果需要生成场景内容，则进入第二阶段
                    if (Boolean.TRUE.equals(parameters.getGenerateSceneContent())) {
                        return generateSceneContent(context, parameters, modelConfig, summary, predictionId, childTaskId, predictionCache, contextContent)
                                .map(sceneContent -> {
                                    predictionProgress.setSceneContent(sceneContent);
                                    predictionProgress.setSceneStatus("COMPLETED");
                                    predictionProgress.setStatus("COMPLETED");
                                    predictionProgress.setCompletionTime(LocalDateTime.now());
                                    
                                    // 子任务完成 - 使用updateTaskResult而不是recordCompletion
                                    // 因为占位执行器已经将子任务标记为COMPLETED，需要更新已完成任务的result
                                    try {
                                        java.util.Map<String, Object> payload = new java.util.HashMap<>();
                                        payload.put("status", "COMPLETED");
                                        payload.put("modelName", predictionProgress.getModelName());
                                        payload.put("summary", predictionProgress.getSummary());
                                        payload.put("sceneContent", predictionProgress.getSceneContent());
                                        // 兼容预览对话框字段
                                        payload.put("generatedSummary", predictionProgress.getSummary());
                                        payload.put("generatedContent", predictionProgress.getSceneContent());
                                        // 传递上下文
                                        payload.put("novelId", parameters.getNovelId());
                                        payload.put("chapterId", parameters.getChapterId());
                                        payload.put("predictionId", predictionId);
                                        
                                        log.info("更新剧情推演子任务result: childTaskId={}, contentLength={}", 
                                                childTaskId, 
                                                predictionProgress.getSceneContent() != null ? predictionProgress.getSceneContent().length() : 0);
                                        
                                        taskStateService.updateTaskResult(childTaskId, payload).subscribe();
                                    } catch (Throwable ignore) {
                                        log.error("更新剧情推演子任务result失败: childTaskId={}", childTaskId, ignore);
                                    }
                                    return buildPredictionResult(predictionProgress);
                                })
                                .onErrorResume(err -> {
                                    // 记录子任务失败
                                    try {
                                        java.util.Map<String, Object> payload = new java.util.HashMap<>();
                                        payload.put("status", "FAILED");
                                        payload.put("error", err.getMessage());
                                        payload.put("novelId", parameters.getNovelId());
                                        payload.put("chapterId", parameters.getChapterId());
                                        payload.put("predictionId", predictionId);
                                        
                                        log.warn("剧情推演子任务场景生成失败: childTaskId={}, error={}", 
                                                childTaskId, err.getMessage());
                                        
                                        taskStateService.recordFailure(childTaskId, payload, false).subscribe();
                                    } catch (Throwable ignore) {
                                        log.error("记录剧情推演子任务失败状态时出错: childTaskId={}", childTaskId, ignore);
                                    }
                                    return Mono.just(buildFailedPredictionResult(predictionProgress, "场景生成失败"));
                                });
                    } else {
                        predictionProgress.setStatus("COMPLETED");
                        predictionProgress.setSceneStatus("SKIPPED");
                        predictionProgress.setCompletionTime(LocalDateTime.now());
                        
                        try {
                            java.util.Map<String, Object> payload = new java.util.HashMap<>();
                            payload.put("status", "COMPLETED");
                            payload.put("modelName", predictionProgress.getModelName());
                            payload.put("summary", predictionProgress.getSummary());
                            payload.put("generatedSummary", predictionProgress.getSummary());
                            payload.put("novelId", parameters.getNovelId());
                            payload.put("chapterId", parameters.getChapterId());
                            payload.put("predictionId", predictionId);
                            
                            log.info("更新剧情推演子任务result(仅摘要): childTaskId={}, summaryLength={}", 
                                    childTaskId, 
                                    predictionProgress.getSummary() != null ? predictionProgress.getSummary().length() : 0);
                            
                            taskStateService.updateTaskResult(childTaskId, payload).subscribe();
                        } catch (Throwable ignore) {
                            log.error("更新剧情推演子任务result(仅摘要)失败: childTaskId={}", childTaskId, ignore);
                        }
                        return Mono.just(buildPredictionResult(predictionProgress));
                    }
                })
                .onErrorResume(err -> {
                    try {
                        java.util.Map<String, Object> payload = new java.util.HashMap<>();
                        payload.put("status", "FAILED");
                        payload.put("error", err.getMessage());
                        payload.put("novelId", parameters.getNovelId());
                        payload.put("chapterId", parameters.getChapterId());
                        payload.put("predictionId", predictionId);
                        
                        log.warn("剧情推演子任务摘要生成失败: childTaskId={}, error={}", 
                                childTaskId, err.getMessage());
                        
                        taskStateService.recordFailure(childTaskId, payload, false).subscribe();
                    } catch (Throwable ignore) {
                        log.error("记录剧情推演子任务失败状态时出错: childTaskId={}", childTaskId, ignore);
                    }
                    return Mono.just(buildFailedPredictionResult(predictionProgress, "摘要生成失败"));
                })
                .doOnNext(result -> updateTaskProgress(context, predictionId, predictionCache));
                // 注意：不在这里清理缓存，等所有预测完成后统一清理
    }
    
    /**
     * 生成摘要
     */
    private Mono<String> generateSummary(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String contextContent,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        // 🔥 检查是否为迭代优化模式
        boolean isRefinement = parameters.getRefinementContext() != null 
                && parameters.getRefinementInstructions() != null;
        
        if (isRefinement) {
            // 🔥 迭代优化模式：从保存的 AIRequest 恢复并追加消息
            log.info("迭代优化模式：基于预测结果 {} 继续推演，轮次={}", 
                    parameters.getBasePredictionId(), 
                    parameters.getRefinementContext().getIterationRound());
            
            return generateSummaryWithSavedAIRequest(context, parameters, modelConfig, predictionId, childTaskId, predictionCache);
        } else {
            // 🔥 普通模式：先 buildAIRequest，保存AIRequest，然后直接调用AI服务
            return generateSummaryFirstTime(context, parameters, modelConfig, contextContent, predictionId, childTaskId, predictionCache);
        }
    }
    
    /**
     * 🔥 第一次生成摘要（普通模式）
     * 1. 调用 buildAIRequest 获取 AIRequest
     * 2. 保存 AIRequest 到任务上下文（用于后续迭代）
     * 3. 直接调用 AI 服务
     */
    private Mono<String> generateSummaryFirstTime(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String contextContent,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        // 第一步：构建 UniversalAIRequestDto
        UniversalAIRequestDto dtoRequest = UniversalAIRequestDto.builder()
                    .requestType(AIFeatureType.STORY_PLOT_CONTINUATION.name())
                    .prompt(contextContent)
                    .instructions(buildMergedInstructions(parameters))
                    .userId(context.getUserId())
                    .novelId(parameters.getNovelId())
                    .chapterId(parameters.getChapterId())
                    .contextSelections(convertContextSelections(parameters))
                .modelConfigId(modelConfig.getConfigId())
                    .build();
        
        log.info("🔥 第一次生成摘要：先调用 buildAIRequest");
        
        // 第二步：调用 buildAIRequest 获取 AIRequest
        return universalAIService.buildAIRequest(dtoRequest)
                .flatMap(aiRequest -> {
                    log.info("✅ 获取到 AIRequest：messages={}, model={}", 
                            aiRequest.getMessages().size(), aiRequest.getModel());
                    
                    // 第三步：🔥 保存 AIRequest 到 predictionCache（用于后续迭代）
                    StoryPredictionProgress.PredictionProgress progress = predictionCache.get(predictionId);
                    if (progress != null) {
                        progress.setAiRequest(aiRequest);
                        log.info("✅ AIRequest 已保存到 predictionCache: predictionId={}", predictionId);
                    }
                    
                    // 第四步：设置 parameters 和 metadata
                    // 确保 modelConfigId 在 parameters 中（用于计费）
                    Map<String, Object> params = aiRequest.getParameters() != null ? 
                            aiRequest.getParameters() : new HashMap<>();
                    params.put("modelConfigId", modelConfig.getConfigId());
                    aiRequest.setParameters(params);
                    
                    Map<String, Object> metadata = aiRequest.getMetadata() != null ? 
                            aiRequest.getMetadata() : new HashMap<>();
                    if ("PUBLIC".equals(modelConfig.getType())) {
                        metadata.put("isPublicModel", true);
                        metadata.put("publicModelConfigId", modelConfig.getConfigId());
                    }
                    metadata.put("requestedModelConfigId", modelConfig.getConfigId());
                    aiRequest.setMetadata(metadata);
                    
                    // 第五步：直接调用 AI 服务
                    log.info("🔥 直接调用 AI 服务生成摘要");
                    return callAIServiceForStream(aiRequest, predictionId, childTaskId, predictionCache, "summary");
                });
    }
    
    /**
     * 🔥 使用保存的 AIRequest 生成摘要（迭代模式）
     * 1. 从 RefinementContext 获取 AIRequest
     * 2. 追加助手+用户消息
     * 3. 修改 modelConfigId
     * 4. 直接调用 AI 服务
     */
    private Mono<String> generateSummaryWithSavedAIRequest(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        StoryPredictionParameters.RefinementContext refinementCtx = parameters.getRefinementContext();
        AIRequest savedAIRequest = refinementCtx.getSavedAIRequest();
        
        if (savedAIRequest == null) {
            return Mono.error(new IllegalStateException("迭代模式下未找到保存的 AIRequest"));
        }
        
        log.info("🔥 迭代模式：从 RefinementContext 获取 AIRequest");
        
        // 第一步：获取实际的模型名称（如果savedAIRequest中为null）
        String modelName = savedAIRequest.getModel();
        if (modelName == null || modelName.isEmpty()) {
            // 如果savedAIRequest中没有model，从modelConfig获取
            modelName = getActualModelName(modelConfig, context.getUserId());
            log.warn("⚠️ savedAIRequest中model为空，使用modelConfig获取: {}", modelName);
        }
        
        // 第二步：复制 AIRequest（避免修改原对象）
        Map<String, Object> aiParams = new HashMap<>(savedAIRequest.getParameters());
        aiParams.put("modelConfigId", modelConfig.getConfigId());  // 🔥 设置新的 modelConfigId
        
        // 🔥 清理 providerSpecific 中的旧计费信息（避免使用错误的模型配置）
        Object providerSpecific = aiParams.get("providerSpecific");
        if (providerSpecific instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> psMap = (Map<String, Object>) providerSpecific;
            psMap.remove("PUBLIC_MODEL_CONFIG_ID");
            psMap.remove("modelConfigId");
            psMap.remove("usedPublicModel");
            psMap.remove("requiresPostStreamDeduction");
            psMap.remove("streamFeatureType");
            psMap.remove("provider");
            psMap.remove("modelId");
            psMap.remove("idempotencyKey");
            log.info("✅ 已清理 providerSpecific 中的旧计费信息");
        }
        
        // 🔥 创建新的metadata，不复用旧的（避免traceId重复和模型信息错误）
        Map<String, Object> newMetadata = new HashMap<>();
        newMetadata.put("requestedModelConfigId", modelConfig.getConfigId());
        newMetadata.put("isRefinement", true);
        if ("PUBLIC".equals(modelConfig.getType())) {
            newMetadata.put("isPublicModel", true);
            newMetadata.put("publicModelConfigId", modelConfig.getConfigId());
        }
        
        AIRequest aiRequest = AIRequest.builder()
                .userId(savedAIRequest.getUserId())
                .novelId(savedAIRequest.getNovelId())
                .sceneId(savedAIRequest.getSceneId())
                .model(modelName)  // 使用获取到的模型名称
                .featureType(savedAIRequest.getFeatureType())
                .maxTokens(savedAIRequest.getMaxTokens())
                .temperature(savedAIRequest.getTemperature())
                .prompt(savedAIRequest.getPrompt())  // 🔥 复制系统提示词（重要！）
                .parameters(aiParams)  // 🔥 包含 modelConfigId
                .metadata(newMetadata)  // 🔥 使用新的metadata（不包含旧traceId）
                .build();
        
        // 第三步：复制原有的所有消息
        List<AIRequest.Message> messages = new ArrayList<>();
        for (AIRequest.Message msg : savedAIRequest.getMessages()) {
            messages.add(AIRequest.Message.builder()
                    .role(msg.getRole())
                    .content(msg.getContent())
                    .build());
        }
        
        // 第四步：追加助手消息（上一轮的结果）
        StringBuilder previousResult = new StringBuilder();
        
        // 🔥 根据任务类型构建assistant消息
        if (refinementCtx.getPreviousSceneContent() != null 
                && !refinementCtx.getPreviousSceneContent().trim().isEmpty()) {
            // 如果有场景内容，说明是完整的剧情推演结果
            previousResult.append("【剧情推演结果】\n\n");
            previousResult.append(refinementCtx.getPreviousSummary());  // 不添加"## 剧情大纲"标题
            previousResult.append("\n\n").append(refinementCtx.getPreviousSceneContent());  // 不添加"## 具体场景内容"标题
        } else {
            // 只有大纲
            previousResult.append("【剧情大纲】\n\n");
            previousResult.append(refinementCtx.getPreviousSummary());
        }
            
        messages.add(AIRequest.Message.builder()
                    .role("assistant")
                    .content(previousResult.toString())
                    .build());
            
        // 第五步：追加用户消息（修改意见）
        StringBuilder userRefinement = new StringBuilder();
        userRefinement.append("请根据以下修改意见进行优化，结合之前生成的原大纲和原内容：\n\n");
        userRefinement.append(parameters.getRefinementInstructions());
        userRefinement.append("\n\n请保持与原有剧情的连贯性，只输出大纲内容。同时体现修改建议的要求。");
        
        messages.add(AIRequest.Message.builder()
                    .role("user")
                    .content(userRefinement.toString())
                    .build());
            
        aiRequest.setMessages(messages);
        
        log.info("✅ AIRequest 准备完成：messages={}, model={}", messages.size(), aiRequest.getModel());
        
        // 第六步：🔥 保存新的 AIRequest 到 predictionCache（用于后续迭代）
        StoryPredictionProgress.PredictionProgress progress = predictionCache.get(predictionId);
        if (progress != null) {
            progress.setAiRequest(aiRequest);
            log.info("✅ 迭代后的 AIRequest 已保存到 predictionCache: predictionId={}", predictionId);
        }
        
        // 第七步：添加迭代轮次到metadata
        Map<String, Object> metadata = aiRequest.getMetadata();
        metadata.put("iterationRound", refinementCtx.getIterationRound());
        aiRequest.setMetadata(metadata);
        
        // 第八步：直接调用 AI 服务
        log.info("🔥 直接调用 AI 服务生成摘要（迭代）");
        return callAIServiceForStream(aiRequest, predictionId, childTaskId, predictionCache, "summary");
    }
    
    /**
     * 🔥 直接调用 AI 服务（流式）
     */
    private Mono<String> callAIServiceForStream(
            AIRequest aiRequest,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache,
            String contentType) {
        
        // 从 parameters 中读取 modelConfigId
        String modelConfigId = null;
        if (aiRequest.getParameters() != null) {
            Object modelConfigIdObj = aiRequest.getParameters().get("modelConfigId");
            if (modelConfigIdObj instanceof String) {
                modelConfigId = (String) modelConfigIdObj;
            }
        }
        
        // 如果没有 modelConfigId，尝试从 metadata 读取
        if (modelConfigId == null && aiRequest.getMetadata() != null) {
            Object modelConfigIdObj = aiRequest.getMetadata().get("requestedModelConfigId");
            if (modelConfigIdObj instanceof String) {
                modelConfigId = (String) modelConfigIdObj;
            }
        }
        
        if (modelConfigId == null) {
            return Mono.error(new IllegalStateException("AIRequest 中未找到 modelConfigId"));
        }
        
        final String finalModelConfigId = modelConfigId;
        log.info("🔥 使用模型配置ID: {}", finalModelConfigId);
        
        // 获取 AIModelProvider 并调用
        return novelAIService.getAIModelProviderByConfigId(aiRequest.getUserId(), finalModelConfigId)
                .flatMapMany(provider -> provider.generateContentStream(aiRequest))
                .collectList()
                .map(chunks -> {
                    // 合并所有流式内容
                    StringBuilder content = new StringBuilder();
                    for (String chunk : chunks) {
                        if (chunk != null) {
                            content.append(chunk);
                            
                            // 实时更新进度
                            if ("summary".equals(contentType)) {
                                updatePredictionProgress(predictionId, content.toString(), null, predictionCache);
                            } else {
                                updatePredictionProgress(predictionId, null, content.toString(), predictionCache);
                            }
                            
                            try {
                                taskStateService.recordProgress(childTaskId, Map.of(
                                        "status", "GENERATING",
                                        contentType, content.toString()
                                )).subscribe();
                            } catch (Throwable ignore) {}
                        }
                    }
                    return content.toString().trim();
                })
                .filter(content -> !content.isEmpty())
                .switchIfEmpty(Mono.error(new RuntimeException("生成的" + contentType + "为空")));
    }
    
    /**
     * 生成场景内容
     * 
     * @param contextContent 上下文内容（用于迭代模式）
     */
    private Mono<String> generateSceneContent(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String summary,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache,
            String contextContent) {
        
        // 🔥 检查是否为迭代优化模式
        boolean isRefinement = parameters.getRefinementContext() != null 
                && parameters.getRefinementInstructions() != null;
        
        if (isRefinement) {
            // 🔥 迭代优化模式：从保存的 AIRequest 恢复并追加场景请求
            return generateSceneContentWithSavedAIRequest(context, parameters, modelConfig, summary, predictionId, childTaskId, predictionCache);
        } else {
            // 🔥 普通模式：先 buildAIRequest，然后直接调用AI服务
            return generateSceneContentFirstTime(context, parameters, modelConfig, summary, predictionId, childTaskId, predictionCache);
        }
    }
    
    /**
     * 🔥 第一次生成场景（普通模式）
     */
    private Mono<String> generateSceneContentFirstTime(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String summary,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        // 第一步：构建 UniversalAIRequestDto
        UniversalAIRequestDto dtoRequest = UniversalAIRequestDto.builder()
                .requestType(AIFeatureType.SUMMARY_TO_SCENE.name())
                .prompt(summary)
                .instructions(buildMergedInstructions(parameters))
                .userId(context.getUserId())
                .novelId(parameters.getNovelId())
                .chapterId(parameters.getChapterId())
                .contextSelections(convertContextSelections(parameters))
                .modelConfigId(modelConfig.getConfigId())
                .build();
        
        log.info("🔥 第一次生成场景：先调用 buildAIRequest");
        
        // 第二步：调用 buildAIRequest 获取 AIRequest
        return universalAIService.buildAIRequest(dtoRequest)
                .flatMap(aiRequest -> {
                    log.info("✅ 获取到场景生成 AIRequest：messages={}, model={}", 
                            aiRequest.getMessages().size(), aiRequest.getModel());
                    
                    // 第三步：🔥 保存场景 AIRequest 到 predictionCache（用于后续迭代）
                    StoryPredictionProgress.PredictionProgress progress = predictionCache.get(predictionId);
                    if (progress != null) {
                        progress.setSceneAIRequest(aiRequest);
                        log.info("✅ 场景 AIRequest 已保存到 predictionCache: predictionId={}", predictionId);
                    }
                    
                    // 第四步：设置 parameters 和 metadata
                    // 确保 modelConfigId 在 parameters 中（用于计费）
                    Map<String, Object> params = aiRequest.getParameters() != null ? 
                            aiRequest.getParameters() : new HashMap<>();
                    params.put("modelConfigId", modelConfig.getConfigId());
                    aiRequest.setParameters(params);
                    
                    Map<String, Object> metadata = aiRequest.getMetadata() != null ? 
                            aiRequest.getMetadata() : new HashMap<>();
                    if ("PUBLIC".equals(modelConfig.getType())) {
                        metadata.put("isPublicModel", true);
                        metadata.put("publicModelConfigId", modelConfig.getConfigId());
                    }
                    metadata.put("requestedModelConfigId", modelConfig.getConfigId());
                    aiRequest.setMetadata(metadata);
                    
                    // 第五步：直接调用 AI 服务
                    log.info("🔥 直接调用 AI 服务生成场景");
                    return callAIServiceForStream(aiRequest, predictionId, childTaskId, predictionCache, "sceneContent");
                });
    }
    
    /**
     * 🔥 使用保存的 AIRequest 生成场景（迭代模式）
     * 优先使用场景的 AIRequest，如果没有则使用摘要的 AIRequest
     */
    private Mono<String> generateSceneContentWithSavedAIRequest(
            TaskContext<StoryPredictionParameters> context,
            StoryPredictionParameters parameters,
            StoryPredictionParameters.ModelConfig modelConfig,
            String summary,
            String predictionId,
            String childTaskId,
            ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        
        StoryPredictionParameters.RefinementContext refinementCtx = parameters.getRefinementContext();
        
        // 🔥 优先使用场景的 AIRequest（包含正确的 SUMMARY_TO_SCENE 系统提示词）
        AIRequest savedAIRequest = refinementCtx.getSceneAIRequest();
        boolean useSceneAIRequest = savedAIRequest != null;
        
        // 如果没有场景 AIRequest，回退到摘要 AIRequest
        if (savedAIRequest == null) {
            savedAIRequest = refinementCtx.getSavedAIRequest();
            log.warn("⚠️ 未找到场景 AIRequest，回退使用摘要 AIRequest（系统提示词可能不正确）");
        }
        
        if (savedAIRequest == null) {
            return Mono.error(new IllegalStateException("迭代模式下未找到保存的 AIRequest"));
        }
        
        log.info("🔥 迭代模式：生成场景内容，使用{}AIRequest", useSceneAIRequest ? "场景" : "摘要");
        
        // 第一步：获取实际的模型名称（如果savedAIRequest中为null）
        String modelName = savedAIRequest.getModel();
        if (modelName == null || modelName.isEmpty()) {
            modelName = getActualModelName(modelConfig, context.getUserId());
            log.warn("⚠️ savedAIRequest中model为空，使用modelConfig获取: {}", modelName);
        }
        
        // 第二步：复制 AIRequest（避免修改原对象）
        Map<String, Object> aiParams = new HashMap<>(savedAIRequest.getParameters());
        aiParams.put("modelConfigId", modelConfig.getConfigId());
        
        // 🔥 清理 providerSpecific 中的旧计费信息（避免使用错误的模型配置）
        Object providerSpecific = aiParams.get("providerSpecific");
        if (providerSpecific instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> psMap = (Map<String, Object>) providerSpecific;
            psMap.remove("PUBLIC_MODEL_CONFIG_ID");
            psMap.remove("modelConfigId");
            psMap.remove("usedPublicModel");
            psMap.remove("requiresPostStreamDeduction");
            psMap.remove("streamFeatureType");
            psMap.remove("provider");
            psMap.remove("modelId");
            psMap.remove("idempotencyKey");
            log.info("✅ 已清理 providerSpecific 中的旧计费信息（场景生成）");
        }
        
        // 🔥 创建新的metadata，不复用旧的（避免traceId重复和模型信息错误）
        Map<String, Object> newMetadata = new HashMap<>();
        newMetadata.put("requestedModelConfigId", modelConfig.getConfigId());
        newMetadata.put("isRefinement", true);
        newMetadata.put("iterationRound", refinementCtx.getIterationRound());
        if ("PUBLIC".equals(modelConfig.getType())) {
            newMetadata.put("isPublicModel", true);
            newMetadata.put("publicModelConfigId", modelConfig.getConfigId());
        }
        
        AIRequest aiRequest = AIRequest.builder()
                .userId(savedAIRequest.getUserId())
                .novelId(savedAIRequest.getNovelId())
                .sceneId(savedAIRequest.getSceneId())
                .model(modelName)
                .featureType(savedAIRequest.getFeatureType())
                .maxTokens(savedAIRequest.getMaxTokens())
                .temperature(savedAIRequest.getTemperature())
                .prompt(savedAIRequest.getPrompt())  // 🔥 复制系统提示词（重要！）
                .parameters(aiParams)
                .metadata(newMetadata)
                .build();
        
        // 第三步：复制原有的所有消息
        List<AIRequest.Message> messages = new ArrayList<>();
        for (AIRequest.Message msg : savedAIRequest.getMessages()) {
            messages.add(AIRequest.Message.builder()
                    .role(msg.getRole())
                    .content(msg.getContent())
                    .build());
        }
        
        // 第四步：追加助手消息（上一轮的场景内容）
        if (refinementCtx.getPreviousSceneContent() != null 
                && !refinementCtx.getPreviousSceneContent().trim().isEmpty()) {
            StringBuilder previousResult = new StringBuilder();
            previousResult.append("【场景内容】\n\n");
            previousResult.append(refinementCtx.getPreviousSceneContent());
            
            messages.add(AIRequest.Message.builder()
                    .role("assistant")
                    .content(previousResult.toString())
                    .build());
        }
        
        // 第五步：追加用户消息（场景生成请求 + 新大纲）
        StringBuilder userSceneRequest = new StringBuilder();
        userSceneRequest.append("请根据以下调整要求和新的剧情大纲，生成场景内容：\n\n");
        userSceneRequest.append("调整要求：\n");
        userSceneRequest.append(parameters.getRefinementInstructions());
        userSceneRequest.append("\n\n新的剧情大纲：\n");
        userSceneRequest.append(summary);
        userSceneRequest.append("\n\n请生成详细的场景内容，结合之前生成的大纲和场景内容，体现新大纲的要点和调整要求。");
        
        messages.add(AIRequest.Message.builder()
                .role("user")
                .content(userSceneRequest.toString())
                .build());
        
        aiRequest.setMessages(messages);
        
        log.info("✅ 场景 AIRequest 准备完成：messages={}, model={}", messages.size(), aiRequest.getModel());
        
        // 第六步：🔥 保存新的场景 AIRequest 到 predictionCache（用于后续迭代）
        StoryPredictionProgress.PredictionProgress progress = predictionCache.get(predictionId);
        if (progress != null) {
            progress.setSceneAIRequest(aiRequest);
            log.info("✅ 迭代后的场景 AIRequest 已保存到 predictionCache: predictionId={}", predictionId);
        }
        
        // 第七步：直接调用 AI 服务
        log.info("🔥 直接调用 AI 服务生成场景（迭代）");
        return callAIServiceForStream(aiRequest, predictionId, childTaskId, predictionCache, "sceneContent");
    }
    

    
    /**
     * 构建上下文内容
     */
    private String buildContext(Novel novel, StoryPredictionParameters parameters) {
        StringBuilder context = new StringBuilder();
        
        // 添加小说基本信息
        if (novel.getTitle() != null && !novel.getTitle().isEmpty()) {
            context.append("小说标题: ").append(novel.getTitle()).append("\n\n");
        }
        
        if (novel.getDescription() != null && !novel.getDescription().isEmpty()) {
            context.append("小说简介:\n").append(novel.getDescription()).append("\n\n");
        }
        
        // TODO: 根据contextSelection构建更详细的上下文
        // 包括：最近章节摘要、内容、设定等
        
        return context.toString();
    }
    
    /**
     * 构建摘要生成指令
     */
    // 移除独立的摘要/场景指令构建逻辑，统一通过合并后的 instructions 占位符传入

    /**
     * 合并 styleInstructions 与 additionalInstructions，直接作为 {{instructions}} 的值传入模板
     * 不再手动添加前缀文本或格式，避免与模板重复。
     */
    private String buildMergedInstructions(StoryPredictionParameters parameters) {
        String style = parameters.getStyleInstructions() == null ? "" : parameters.getStyleInstructions().trim();
        String additional = parameters.getAdditionalInstructions() == null ? "" : parameters.getAdditionalInstructions().trim();

        boolean hasStyle = !style.isEmpty();
        boolean hasAdditional = !additional.isEmpty();

        if (hasStyle && hasAdditional) {
            return style + "\n\n" + additional;
        } else if (hasStyle) {
            return style;
        } else if (hasAdditional) {
            return additional;
        } else {
            return "";
        }
    }
    
    /**
     * 更新预测进度
     */
    private void updatePredictionProgress(String predictionId, String summary, String sceneContent,
                                          ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        StoryPredictionProgress.PredictionProgress progress = predictionCache.get(predictionId);
        if (progress != null) {
            if (summary != null) {
                progress.setSummary(summary);
            }
            if (sceneContent != null) {
                progress.setSceneContent(sceneContent);
            }
        }
    }
    
    /**
     * 更新任务总体进度
     */
    private void updateTaskProgress(TaskContext<StoryPredictionParameters> context, String completedPredictionId,
                                    ConcurrentMap<String, StoryPredictionProgress.PredictionProgress> predictionCache) {
        // 统计完成数量
        long completedCount = predictionCache.values().stream()
                .filter(p -> "COMPLETED".equals(p.getStatus()))
                .count();
        
        StoryPredictionProgress progress = StoryPredictionProgress.builder()
                .totalPredictions(predictionCache.size())
                .completedPredictions((int) completedCount)
                .currentStep("GENERATING")
                .lastUpdated(LocalDateTime.now())
                .predictionProgress(new ArrayList<>(predictionCache.values()))
                .build();
        
        context.updateProgress(progress).subscribe();
    }
    
    /**
     * 构建预测结果
     */
    private StoryPredictionResult.PredictionItem buildPredictionResult(
            StoryPredictionProgress.PredictionProgress progress) {
        
        return StoryPredictionResult.PredictionItem.builder()
                .id(progress.getPredictionId())
                .modelId(progress.getModelId())
                .modelName(progress.getModelName())
                .summary(progress.getSummary())
                .sceneContent(progress.getSceneContent())
                .status(progress.getStatus())
                .sceneStatus(progress.getSceneStatus())
                .createdAt(progress.getStartTime())
                .aiRequest(progress.getAiRequest())  // 🔥 保存摘要AIRequest
                .sceneAIRequest(progress.getSceneAIRequest())  // 🔥 保存场景AIRequest
                .build();
    }
    
    /**
     * 构建失败的预测结果
     */
    private StoryPredictionResult.PredictionItem buildFailedPredictionResult(
            StoryPredictionProgress.PredictionProgress progress, String error) {
        
        progress.setStatus("FAILED");
        progress.setError(error);
        progress.setCompletionTime(LocalDateTime.now());
        
        return StoryPredictionResult.PredictionItem.builder()
                .id(progress.getPredictionId())
                .modelId(progress.getModelId())
                .modelName(progress.getModelName())
                .summary(progress.getSummary())
                .sceneContent(progress.getSceneContent())
                .status("FAILED")
                .error(error)
                .createdAt(progress.getStartTime())
                .build();
    }
    
    @Override
    public int getEstimatedExecutionTimeSeconds(TaskContext<StoryPredictionParameters> context) {
        StoryPredictionParameters parameters = context.getParameters();
        // 估算时间：每个预测大约30秒
        int totalPredictions = parameters.getGenerationCount();
        return totalPredictions * 30;
    }
    
    @Override
    public boolean isCancellable() {
        return true;
    }
    
    /**
     * 获取实际的模型名称
     */
    private String getActualModelName(StoryPredictionParameters.ModelConfig modelConfig, String userId) {
        try {
            if ("PUBLIC".equals(modelConfig.getType())) {
                // 公共模型
                return publicModelConfigService.findById(modelConfig.getConfigId())
                        .map(config -> config.getDisplayName() != null ? config.getDisplayName() : config.getModelId())
                        .block(); // 注意：这里使用block()可能会阻塞，在生产环境中可能需要优化
            } else {
                // 用户私有模型
                return userAIModelConfigService.getConfigurationById(userId, modelConfig.getConfigId())
                        .map(config -> config.getAlias() != null ? config.getAlias() : config.getModelName())
                        .block(); // 注意：这里使用block()可能会阻塞，在生产环境中可能需要优化
            }
        } catch (Exception e) {
            log.warn("获取模型名称失败: configId={}, type={}, error={}", 
                    modelConfig.getConfigId(), modelConfig.getType(), e.getMessage());
            return modelConfig.getConfigId(); // 回退到使用配置ID
        }
    }
    
    private java.util.List<UniversalAIRequestDto.ContextSelectionDto> convertContextSelections(StoryPredictionParameters parameters) {
        StoryPredictionParameters.ContextSelection ctx = parameters.getContextSelection();
        if (ctx == null || (ctx.getTypes() == null && ctx.getCustomContextIds() == null)) {
            return java.util.List.of();
        }

        java.util.List<UniversalAIRequestDto.ContextSelectionDto> result = new java.util.ArrayList<>();
        java.util.List<String> types = ctx.getTypes() != null ? ctx.getTypes() : java.util.List.of();
        java.util.List<String> ids = ctx.getCustomContextIds() != null ? ctx.getCustomContextIds() : java.util.List.of();

        // 没有ID的通用类型
        for (String type : types) {
            String t = type != null ? type.toLowerCase() : "";
            if (t.isEmpty()) continue;
            if (t.equals("act") || t.equals("chapter") || t.equals("scene") || t.equals("snippet")
                    || t.equals("setting_group") || t.equals("settings_by_type") || t.equals("settings")) {
                continue;
            }
            result.add(UniversalAIRequestDto.ContextSelectionDto.builder()
                    .id(t)
                    .title(t)
                    .type(t)
                    .build());
        }

        // 需要ID的类型
        for (String id : ids) {
            if (id == null || id.isBlank()) continue;
            String lower = id.toLowerCase();
            String type;
            if (lower.startsWith("chapter_")) type = "chapter";
            else if (lower.startsWith("scene_")) type = "scene";
            else if (lower.startsWith("snippet_")) type = "snippet";
            else if (lower.startsWith("type_")) type = "settings_by_type";
            else if (lower.startsWith("setting_group_")) type = "setting_group";
            else type = "settings";

            result.add(UniversalAIRequestDto.ContextSelectionDto.builder()
                    .id(id)
                    .title(id)
                    .type(type)
                    .build());
        }

        return result;
    }

}
