package com.ainovel.server.web.controller;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.service.NextOutlineService;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionParameters;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionResult;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.web.dto.NextOutlineDTO;
import com.ainovel.server.web.dto.OutlineGenerationChunk;
import com.ainovel.server.web.dto.request.RefineStoryPredictionRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 剧情推演控制器
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/v1/novels/{novelId}/next-outlines")
public class NextOutlineController {

    private final NextOutlineService nextOutlineService;
    private final TaskSubmissionService taskSubmissionService;
    private final TaskStateService taskStateService;
    
    private static final String SSE_EVENT_NAME = "outline-chunk";

    /**
     * 生成剧情大纲
     *
     * @param novelId 小说ID
     * @param request 生成请求
     * @return 生成的剧情大纲列表
     */
    @PostMapping("/generate")
    public Mono<ResponseEntity<NextOutlineDTO.GenerateResponse>> generateNextOutlines(
            @PathVariable String novelId,
            @Valid @RequestBody NextOutlineDTO.GenerateRequest request) {

        log.info("生成剧情大纲: novelId={}, startChapter={}, endChapter={}, numOptions={}",
                novelId, request.getStartChapterId(), request.getEndChapterId(), request.getNumOptions());

        long startTime = System.currentTimeMillis();

        return nextOutlineService.generateNextOutlines(novelId, request)
                .map(response -> {
                    long endTime = System.currentTimeMillis();
                    response.setGenerationTimeMs(endTime - startTime);
                    return ResponseEntity.ok(response);
                });
    }

    /**
     * 流式生成剧情大纲
     *
     * @param novelId 小说ID
     * @param request 生成请求
     * @return 流式生成的剧情大纲块 (OutlineGenerationChunk)
     */
    @PostMapping(value = "/generate-stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<OutlineGenerationChunk>> generateNextOutlinesStream(
            @PathVariable String novelId,
            @Valid @RequestBody NextOutlineDTO.GenerateRequest request) {

        log.info("请求流式生成剧情大纲: novelId={}, startChapter={}, endChapter={}, numOptions={}",
                novelId, request.getStartChapterId(), request.getEndChapterId(), request.getNumOptions());

        return nextOutlineService.generateNextOutlinesStream(novelId, request)
                .map(chunk -> ServerSentEvent.<OutlineGenerationChunk>builder()
                        .id(chunk.getOptionId() + "-" + UUID.randomUUID().toString())
                        .event(SSE_EVENT_NAME)
                        .data(chunk)
                        .retry(Duration.ofSeconds(10))
                        .build())
                .doOnSubscribe(subscription -> log.info("SSE 连接建立 for generate-stream, novelId: {}", novelId))
                .doOnCancel(() -> log.info("SSE 连接关闭 for generate-stream, novelId: {}", novelId))
                .doOnError(error -> log.error("SSE 流错误 for generate-stream, novelId: {}: {}", novelId, error.getMessage(), error));
    }
    
    /**
     * 重新生成单个剧情大纲选项 (流式)
     *
     * @param novelId 小说ID
     * @param request 重新生成请求
     * @return 流式生成的剧情大纲块 (OutlineGenerationChunk)
     */
    @PostMapping(value = "/regenerate-option", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<OutlineGenerationChunk>> regenerateOutlineOption(
            @PathVariable String novelId,
            @Valid @RequestBody NextOutlineDTO.RegenerateOptionRequest request) {

        log.info("请求流式重新生成单个剧情大纲: novelId={}, optionId={}, configId={}",
                novelId, request.getOptionId(), request.getSelectedConfigId());

        return nextOutlineService.regenerateOutlineOption(novelId, request)
                .map(chunk -> ServerSentEvent.<OutlineGenerationChunk>builder()
                        .id(chunk.getOptionId() + "-" + UUID.randomUUID().toString())
                        .event(SSE_EVENT_NAME)
                        .data(chunk)
                        .retry(Duration.ofSeconds(10))
                        .build())
                 .doOnSubscribe(subscription -> log.info("SSE 连接建立 for regenerate-option, novelId: {}, optionId: {}", novelId, request.getOptionId()))
                .doOnCancel(() -> log.info("SSE 连接关闭 for regenerate-option, novelId: {}, optionId: {}", novelId, request.getOptionId()))
                .doOnError(error -> log.error("SSE 流错误 for regenerate-option, novelId: {}, optionId: {}: {}", novelId, request.getOptionId(), error.getMessage(), error));
    }

    /**
     * 保存选中的剧情大纲
     *
     * @param novelId 小说ID
     * @param request 保存请求
     * @return 保存结果
     */
    @PostMapping("/save")
    public Mono<ResponseEntity<NextOutlineDTO.SaveResponse>> saveNextOutline(
            @PathVariable String novelId,
            @Valid @RequestBody NextOutlineDTO.SaveRequest request) {

        log.info("保存剧情大纲: novelId={}, outlineId={}", novelId, request.getOutlineId());

        return nextOutlineService.saveNextOutline(novelId, request)
                .map(ResponseEntity::ok);
    }
    
    // ==================== 基于任务系统的新端点 ====================
    
    /**
     * 使用任务系统创建剧情推演任务
     * 
     * @param novelId 小说ID
     * @param request 剧情推演请求
     * @return 任务创建响应
     */
    @PostMapping("/v2/story-prediction")
    public Mono<ResponseEntity<StoryPredictionResponse>> createStoryPredictionTask(
            @PathVariable String novelId,
            @Valid @RequestBody StoryPredictionRequest request) {
        
        log.info("创建剧情推演任务: novelId={}, chapterId={}, modelCount={}, generationCount={}", 
                novelId, request.getChapterId(), 
                request.getModelConfigs() != null ? request.getModelConfigs().size() : 0,
                request.getGenerationCount());
        
        return ReactiveSecurityContextHolder.getContext()
                .cast(org.springframework.security.core.context.SecurityContext.class)
                .map(org.springframework.security.core.context.SecurityContext::getAuthentication)
                .cast(Authentication.class)
                .map(Authentication::getPrincipal)
                .cast(com.ainovel.server.domain.model.User.class)
                .map(user -> user.getId())
                .flatMap(userId -> {
                    // 构建任务参数
                    StoryPredictionParameters parameters = StoryPredictionParameters.builder()
                            .novelId(novelId)
                            .chapterId(request.getChapterId())
                            .modelConfigs(convertModelConfigs(request.getModelConfigs()))
                            .generationCount(request.getGenerationCount())
                            .styleInstructions(request.getStyleInstructions())
                            .contextSelection(convertContextSelection(request.getContextSelection()))
                            .additionalInstructions(request.getAdditionalInstructions())
                            .summaryPromptTemplateId(request.getSummaryPromptTemplateId())
                            .scenePromptTemplateId(request.getScenePromptTemplateId())
                            .generateSceneContent(request.getGenerateSceneContent())
                            .build();
                    
                    // 提交任务
                    return taskSubmissionService.submitTask(userId, "STORY_PREDICTION", parameters);
                })
                .map(taskId -> {
                    StoryPredictionResponse response = new StoryPredictionResponse();
                    response.setTaskId(taskId);
                    response.setStatus("SUBMITTED");
                    response.setMessage("剧情推演任务已创建");
                    
                    log.info("剧情推演任务创建成功: taskId={}", taskId);
                    return ResponseEntity.ok(response);
                })
                .doOnError(error -> log.error("创建剧情推演任务失败: novelId={}, error={}", 
                        novelId, error.getMessage(), error));
    }
    
    /**
     * 迭代优化剧情推演
     * 
     * 功能说明：
     * 用户在生成多个推演结果后，可以选择一个最满意的结果，
     * 提出修改意见，基于选定的结果继续推演，支持切换模型。
     * 
     * @param novelId 小说ID
     * @param request 迭代优化请求
     * @return 新任务创建响应
     */
    @PostMapping("/v2/story-prediction/refine")
    public Mono<ResponseEntity<StoryPredictionResponse>> refineStoryPrediction(
            @PathVariable String novelId,
            @Valid @RequestBody com.ainovel.server.web.dto.request.RefineStoryPredictionRequest request) {
        
        log.info("迭代优化剧情推演: novelId={}, originalTaskId={}, basePredictionId={}", 
                novelId, request.getOriginalTaskId(), request.getBasePredictionId());
        
        return ReactiveSecurityContextHolder.getContext()
                .cast(org.springframework.security.core.context.SecurityContext.class)
                .map(org.springframework.security.core.context.SecurityContext::getAuthentication)
                .cast(Authentication.class)
                .map(Authentication::getPrincipal)
                .cast(com.ainovel.server.domain.model.User.class)
                .map(user -> user.getId())
                .flatMap(userId -> {
                    // 1. 🔥 直接获取 originalTaskId 对应的任务（每次迭代独立、解耦）
                    return taskStateService.getTask(request.getOriginalTaskId())
                            .switchIfEmpty(Mono.error(new IllegalArgumentException("原始任务不存在: " + request.getOriginalTaskId())))
                            .flatMap(originalTask -> {
                                log.info("📋 获取到原始任务: taskId={}, status={}, resultType={}", 
                                        originalTask.getId(), 
                                        originalTask.getStatus(),
                                        originalTask.getResult() != null ? originalTask.getResult().getClass().getName() : "null");
                                
                                // 2. 🔥 从任务结果中查找指定的预测项
                                Object resultObj = originalTask.getResult();
                                
                                // 如果result为空，尝试从progress中获取已完成的预测
                                if (resultObj == null) {
                                    log.info("⚠️ 任务result为空，尝试从progress中获取已完成的预测");
                                    return extractPredictionFromProgress(originalTask, request.getBasePredictionId())
                                            .flatMap(selectedPrediction -> processRefinement(originalTask, request, novelId, selectedPrediction));
                                }
                                
                                log.info("✅ 任务状态={}，结果已存在，可以进行迭代", originalTask.getStatus());
                                log.info("🔍 任务结果: {}", resultObj.toString().length());
                                
                                // 3. 🔥 查找用户选择的预测结果
                                return findSelectedPrediction(resultObj, request.getBasePredictionId())
                                        .switchIfEmpty(Mono.error(new IllegalArgumentException("未找到指定的预测结果: " + request.getBasePredictionId())))
                                        .flatMap(selectedPrediction -> processRefinement(originalTask, request, novelId, selectedPrediction));
                            });
                })
                .map(taskId -> {
                    StoryPredictionResponse response = new StoryPredictionResponse();
                    response.setTaskId(taskId);
                    response.setStatus("SUBMITTED");
                    response.setMessage("迭代优化任务已创建");
                    
                    log.info("迭代优化任务创建成功: taskId={}", taskId);
                    return ResponseEntity.ok(response);
                })
                .doOnError(error -> log.error("创建迭代优化任务失败: novelId={}, error={}", 
                        novelId, error.getMessage(), error));
    }
    
    /**
     * 从任务结果中查找指定的预测项
     */
    private Mono<StoryPredictionResult.PredictionItem> findSelectedPrediction(Object resultObj, String predictionId) {
        try {
            log.debug("🔍 开始查找预测结果: predictionId={}, resultObj类型={}", 
                    predictionId, resultObj != null ? resultObj.getClass().getName() : "null");
            
            if (resultObj == null) {
                log.warn("⚠️ 任务结果为null");
                return Mono.empty();
            }
            
            // 如果resultObj已经是StoryPredictionResult对象
            if (resultObj instanceof StoryPredictionResult) {
                StoryPredictionResult result = (StoryPredictionResult) resultObj;
                log.debug("✅ 结果是StoryPredictionResult对象，predictions数量={}", 
                        result.getPredictions() != null ? result.getPredictions().size() : 0);
                
                if (result.getPredictions() != null) {
                    for (StoryPredictionResult.PredictionItem item : result.getPredictions()) {
                        log.debug("   - 检查预测项: id={}, modelName={}", item.getId(), item.getModelName());
                        if (predictionId.equals(item.getId())) {
                            log.info("✅ 找到匹配的预测项: id={}", predictionId);
                            return Mono.just(item);
                        }
                    }
                }
                log.warn("⚠️ 在StoryPredictionResult中未找到ID={}的预测项", predictionId);
                return Mono.empty();
            }
            
            // 如果是Map类型
            if (resultObj instanceof Map) {
                Map<?, ?> resultMap = (Map<?, ?>) resultObj;
                log.debug("✅ 结果是Map对象，keys={}", resultMap.keySet());
                
                Object predictionsObj = resultMap.get("predictions");
                log.debug("   - predictions字段类型={}", 
                        predictionsObj != null ? predictionsObj.getClass().getName() : "null");
                
                if (predictionsObj instanceof List) {
                    List<?> predictions = (List<?>) predictionsObj;
                    log.debug("   - predictions列表大小={}", predictions.size());
                    
                    for (int i = 0; i < predictions.size(); i++) {
                        Object predObj = predictions.get(i);
                        log.debug("   - [{}] 预测项类型={}", i, 
                                predObj != null ? predObj.getClass().getName() : "null");
                        
                        if (predObj instanceof Map) {
                            Map<?, ?> predMap = (Map<?, ?>) predObj;
                            Object idObj = predMap.get("id");
                            log.debug("      id={}, 期望={}, 相等={}", 
                                    idObj, predictionId, predictionId.equals(idObj));
                            
                            if (predictionId.equals(idObj)) {
                                log.info("✅ 在Map中找到匹配的预测项: id={}", predictionId);
                                // 构建PredictionItem
                                StoryPredictionResult.PredictionItem item = StoryPredictionResult.PredictionItem.builder()
                                        .id((String) predMap.get("id"))
                                        .modelName((String) predMap.get("modelName"))
                                        .summary((String) predMap.get("summary"))
                                        .sceneContent((String) predMap.get("sceneContent"))
                                        .status((String) predMap.get("status"))
                                        .build();
                                return Mono.just(item);
                            }
                        }
                    }
                }
            }
            
            log.warn("⚠️ 未找到预测项: predictionId={}", predictionId);
        } catch (Exception e) {
            log.error("❌ 解析预测结果失败: predictionId={}, error={}", predictionId, e.getMessage(), e);
        }
        return Mono.empty();
    }
    
    /**
     * 获取迭代轮次
     */
    private int getIterationRound(com.ainovel.server.task.model.BackgroundTask task) {
        try {
            Object paramsObj = task.getParameters();
            if (paramsObj instanceof Map) {
                Map<?, ?> paramsMap = (Map<?, ?>) paramsObj;
                Object refinementCtxObj = paramsMap.get("refinementContext");
                if (refinementCtxObj instanceof Map) {
                    Map<?, ?> refinementCtxMap = (Map<?, ?>) refinementCtxObj;
                    Object roundObj = refinementCtxMap.get("iterationRound");
                    if (roundObj instanceof Number) {
                        return ((Number) roundObj).intValue();
                    }
                }
            }
        } catch (Exception e) {
            log.warn("获取迭代轮次失败: {}", e.getMessage());
        }
        return 0;
    }
    
    /**
     * 从原始任务中获取章节ID
     */
    private String getChapterId(com.ainovel.server.task.model.BackgroundTask task) {
        try {
            Object paramsObj = task.getParameters();
            if (paramsObj instanceof Map) {
                Map<?, ?> paramsMap = (Map<?, ?>) paramsObj;
                return (String) paramsMap.get("chapterId");
            }
        } catch (Exception e) {
            log.warn("获取章节ID失败: {}", e.getMessage());
        }
        return null;
    }
    /**
     * 从原始任务中获取上下文选择配置
     */
    private StoryPredictionParameters.ContextSelection getOriginalContextSelection(
            com.ainovel.server.task.model.BackgroundTask task) {
        try {
            Object paramsObj = task.getParameters();
            if (paramsObj instanceof Map) {
                Map<?, ?> paramsMap = (Map<?, ?>) paramsObj;
                Object ctxSelObj = paramsMap.get("contextSelection");
                if (ctxSelObj instanceof Map) {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> ctxSelMap = (Map<String, Object>) ctxSelObj;
                    @SuppressWarnings("unchecked")
                    List<String> types = (List<String>) ctxSelMap.get("types");
                    @SuppressWarnings("unchecked")
                    List<String> customContextIds = (List<String>) ctxSelMap.get("customContextIds");
                    return StoryPredictionParameters.ContextSelection.builder()
                            .types(types)
                            .customContextIds(customContextIds)
                            .maxTokens((Integer) ctxSelMap.get("maxTokens"))
                            .build();
                }
            }
        } catch (Exception e) {
            log.warn("获取上下文选择配置失败: {}", e.getMessage());
        }
        return null;
    }
    
    /**
     * 获取剧情推演任务状态
     * 
     * @param novelId 小说ID
     * @param taskId 任务ID
     * @return 任务状态响应
     */
    @GetMapping("/v2/story-prediction/{taskId}")
    public Mono<ResponseEntity<TaskStatusResponse>> getStoryPredictionTaskStatus(
            @PathVariable String novelId,
            @PathVariable String taskId) {
        
        log.debug("查询剧情推演任务状态: taskId={}", taskId);
        
        return taskStateService.getTask(taskId)
                .map(task -> {
                    TaskStatusResponse response = new TaskStatusResponse();
                    response.setTaskId(taskId);
                    response.setStatus(task.getStatus().name());
                    response.setProgress(task.getProgress());
                    response.setResult(task.getResult());
                    response.setError(convertErrorToString(task.getErrorInfo()));
                    response.setCreatedAt(convertToLocalDateTime(task.getTimestamps().getCreatedAt()));
                    response.setUpdatedAt(convertToLocalDateTime(task.getTimestamps().getUpdatedAt()));
                    
                    return ResponseEntity.ok(response);
                })
                .switchIfEmpty(Mono.just(ResponseEntity.notFound().build()))
                .doOnError(error -> log.error("查询任务状态失败: taskId={}, error={}", 
                        taskId, error.getMessage(), error));
    }
    
    /**
     * 流式获取剧情推演任务进度
     * 
     * @param novelId 小说ID
     * @param taskId 任务ID
     * @return 流式任务进度
     */
    @GetMapping(value = "/v2/story-prediction/{taskId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<Object>> streamStoryPredictionProgress(
            @PathVariable String novelId,
            @PathVariable String taskId) {
        
        log.info("开始流式获取剧情推演进度: taskId={}", taskId);
        
        // 简化实现：定期轮询任务状态
        return Flux.interval(Duration.ofSeconds(1))
                .flatMap(tick -> taskStateService.getTask(taskId))
                .takeUntil(task -> task.getStatus().isTerminal())
                .map(task -> {
                    TaskProgressEvent event = new TaskProgressEvent();
                    event.setType(determineEventType(task));
                    event.setTaskId(taskId);
                    event.setStatus(task.getStatus().name());
                    event.setProgress(task.getProgress());
                    event.setResult(task.getResult());
                    event.setError(convertErrorToString(task.getErrorInfo()));
                    
                    return ServerSentEvent.builder()
                            .id(taskId + "-" + System.currentTimeMillis())
                            .event(event.getType())
                            .data(event)
                            .retry(Duration.ofSeconds(5))
                            .build();
                })
                .doOnSubscribe(subscription -> log.info("SSE连接建立: taskId={}", taskId))
                .doOnCancel(() -> log.info("SSE连接关闭: taskId={}", taskId))
                .doOnError(error -> log.error("SSE流错误: taskId={}, error={}", taskId, error.getMessage()));
    }
    
    /**
     * 取消剧情推演任务
     * 
     * @param novelId 小说ID
     * @param taskId 任务ID
     * @return 取消结果
     */
    @PostMapping("/v2/story-prediction/{taskId}/cancel")
    public Mono<ResponseEntity<CancelTaskResponse>> cancelStoryPredictionTask(
            @PathVariable String novelId,
            @PathVariable String taskId) {
        
        log.info("取消剧情推演任务: taskId={}", taskId);
        
        return ReactiveSecurityContextHolder.getContext()
                .cast(org.springframework.security.core.context.SecurityContext.class)
                .map(org.springframework.security.core.context.SecurityContext::getAuthentication)
                .cast(Authentication.class)
                .map(Authentication::getPrincipal)
                .cast(com.ainovel.server.domain.model.User.class)
                .map(user -> user.getId())
                .flatMap(userId -> taskStateService.cancelTask(taskId, userId))
                .map(cancelled -> {
                    CancelTaskResponse response = new CancelTaskResponse();
                    response.setTaskId(taskId);
                    response.setCancelled(cancelled);
                    response.setMessage(cancelled ? "任务已取消" : "任务无法取消");
                    
                    return ResponseEntity.ok(response);
                })
                .doOnError(error -> log.error("取消任务失败: taskId={}, error={}", 
                        taskId, error.getMessage(), error));
    }
    
    // ==================== 辅助方法 ====================
    
    /**
     * 转换模型配置
     */
    private List<StoryPredictionParameters.ModelConfig> convertModelConfigs(
            List<StoryPredictionRequest.ModelConfig> requestConfigs) {
        
        if (requestConfigs == null) {
            return List.of();
        }
        
        return requestConfigs.stream()
                .map(config -> StoryPredictionParameters.ModelConfig.builder()
                        .type(config.getType())
                        .configId(config.getConfigId())
                        .build())
                .toList();
    }
    
    /**
     * 转换上下文选择配置
     */
    private StoryPredictionParameters.ContextSelection convertContextSelection(
            StoryPredictionRequest.ContextSelection requestContext) {
        
        if (requestContext == null) {
            return null;
        }
        
        return StoryPredictionParameters.ContextSelection.builder()
                .types(requestContext.getTypes())
                .customContextIds(requestContext.getCustomContextIds())
                .maxTokens(requestContext.getMaxTokens())
                .build();
    }
    
    /**
     * 确定事件类型
     */
    private String determineEventType(BackgroundTask task) {
        switch (task.getStatus()) {
            case QUEUED:
                return "task_queued";
            case RUNNING:
                return "task_progress";
            case COMPLETED:
                return "task_completed";
            case FAILED:
                return "task_failed";
            case CANCELLED:
                return "task_cancelled";
            case RETRYING:
                return "task_retrying";
            case DEAD_LETTER:
                return "task_dead_letter";
            case COMPLETED_WITH_ERRORS:
                return "task_completed_with_errors";
            default:
                return "task_update";
        }
    }
    
    /**
     * 将Instant转换为LocalDateTime
     */
    private LocalDateTime convertToLocalDateTime(java.time.Instant instant) {
        if (instant == null) {
            return null;
        }
        return LocalDateTime.ofInstant(instant, java.time.ZoneId.systemDefault());
    }
    
    /**
     * 将错误信息Map转换为字符串
     */
    private String convertErrorToString(java.util.Map<String, Object> errorInfo) {
        if (errorInfo == null || errorInfo.isEmpty()) {
            return null;
        }
        try {
            // 如果有 message 字段，直接返回
            if (errorInfo.containsKey("message")) {
                return errorInfo.get("message").toString();
            }
            // 否则返回JSON字符串
            return errorInfo.toString();
        } catch (Exception e) {
            return "Error converting error info: " + e.getMessage();
        }
    }
    
    // ==================== 内部DTO类 ====================
    
    /**
     * 剧情推演请求DTO
     */
    public static class StoryPredictionRequest {
        private String chapterId;
        private List<ModelConfig> modelConfigs;
        private Integer generationCount;
        private String styleInstructions;
        private ContextSelection contextSelection;
        private String additionalInstructions;
        private String summaryPromptTemplateId;
        private String scenePromptTemplateId;
        private Boolean generateSceneContent;
        
        // Getters and Setters
        public String getChapterId() { return chapterId; }
        public void setChapterId(String chapterId) { this.chapterId = chapterId; }
        
        public List<ModelConfig> getModelConfigs() { return modelConfigs; }
        public void setModelConfigs(List<ModelConfig> modelConfigs) { this.modelConfigs = modelConfigs; }
        
        public Integer getGenerationCount() { return generationCount; }
        public void setGenerationCount(Integer generationCount) { this.generationCount = generationCount; }
        
        public String getStyleInstructions() { return styleInstructions; }
        public void setStyleInstructions(String styleInstructions) { this.styleInstructions = styleInstructions; }
        
        public ContextSelection getContextSelection() { return contextSelection; }
        public void setContextSelection(ContextSelection contextSelection) { this.contextSelection = contextSelection; }
        
        public String getAdditionalInstructions() { return additionalInstructions; }
        public void setAdditionalInstructions(String additionalInstructions) { this.additionalInstructions = additionalInstructions; }
        
        public String getSummaryPromptTemplateId() { return summaryPromptTemplateId; }
        public void setSummaryPromptTemplateId(String summaryPromptTemplateId) { this.summaryPromptTemplateId = summaryPromptTemplateId; }
        
        public String getScenePromptTemplateId() { return scenePromptTemplateId; }
        public void setScenePromptTemplateId(String scenePromptTemplateId) { this.scenePromptTemplateId = scenePromptTemplateId; }
        
        public Boolean getGenerateSceneContent() { return generateSceneContent; }
        public void setGenerateSceneContent(Boolean generateSceneContent) { this.generateSceneContent = generateSceneContent; }
        
        public static class ModelConfig {
            private String type;
            private String configId;
            
            public String getType() { return type; }
            public void setType(String type) { this.type = type; }
            
            public String getConfigId() { return configId; }
            public void setConfigId(String configId) { this.configId = configId; }
        }
        
        public static class ContextSelection {
            private List<String> types;
            private List<String> customContextIds;
            private Integer maxTokens;
            
            public List<String> getTypes() { return types; }
            public void setTypes(List<String> types) { this.types = types; }
            
            public List<String> getCustomContextIds() { return customContextIds; }
            public void setCustomContextIds(List<String> customContextIds) { this.customContextIds = customContextIds; }
            
            public Integer getMaxTokens() { return maxTokens; }
            public void setMaxTokens(Integer maxTokens) { this.maxTokens = maxTokens; }
        }
    }
    
    /**
     * 剧情推演响应DTO
     */
    public static class StoryPredictionResponse {
        private String taskId;
        private String status;
        private String message;
        
        public String getTaskId() { return taskId; }
        public void setTaskId(String taskId) { this.taskId = taskId; }
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        
        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }
    }
    
    /**
     * 任务状态响应DTO
     */
    public static class TaskStatusResponse {
        private String taskId;
        private String status;
        private Object progress;
        private Object result;
        private String error;
        private java.time.LocalDateTime createdAt;
        private java.time.LocalDateTime updatedAt;
        
        public String getTaskId() { return taskId; }
        public void setTaskId(String taskId) { this.taskId = taskId; }
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        
        public Object getProgress() { return progress; }
        public void setProgress(Object progress) { this.progress = progress; }
        
        public Object getResult() { return result; }
        public void setResult(Object result) { this.result = result; }
        
        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
        
        public java.time.LocalDateTime getCreatedAt() { return createdAt; }
        public void setCreatedAt(java.time.LocalDateTime createdAt) { this.createdAt = createdAt; }
        
        public java.time.LocalDateTime getUpdatedAt() { return updatedAt; }
        public void setUpdatedAt(java.time.LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
    }
    
    /**
     * 任务进度事件DTO
     */
    public static class TaskProgressEvent {
        private String type;
        private String taskId;
        private String status;
        private Object progress;
        private Object result;
        private String error;
        
        public String getType() { return type; }
        public void setType(String type) { this.type = type; }
        
        public String getTaskId() { return taskId; }
        public void setTaskId(String taskId) { this.taskId = taskId; }
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        
        public Object getProgress() { return progress; }
        public void setProgress(Object progress) { this.progress = progress; }
        
        public Object getResult() { return result; }
        public void setResult(Object result) { this.result = result; }
        
        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
    }
    
    /**
     * 取消任务响应DTO
     */
    public static class CancelTaskResponse {
        private String taskId;
        private Boolean cancelled;
        private String message;
        
        public String getTaskId() { return taskId; }
        public void setTaskId(String taskId) { this.taskId = taskId; }
        
        public Boolean getCancelled() { return cancelled; }
        public void setCancelled(Boolean cancelled) { this.cancelled = cancelled; }
        
        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }
    }
    
    /**
     * 🔥 处理迭代优化逻辑（从selectedPrediction构建新任务）
     */
    private Mono<String> processRefinement(
            com.ainovel.server.task.model.BackgroundTask originalTask,
            RefineStoryPredictionRequest request,
            String novelId,
            StoryPredictionResult.PredictionItem selectedPrediction) {
        
        String userId = originalTask.getUserId();
        
        // 2. 🔥 直接使用 selectedPrediction 中的 aiRequest（必须存在）
        AIRequest savedAIRequest = selectedPrediction.getAiRequest();
        if (savedAIRequest == null) {
            return Mono.error(new IllegalStateException("预测结果中缺少AIRequest，无法进行迭代优化"));
        }
        
        log.info("✅ 从 selectedPrediction 获取 AIRequest: messages={}", savedAIRequest.getMessages().size());
        
        return Mono.just(savedAIRequest)
                .flatMap(aiRequest -> {
                    // 🔥 不在这里添加消息，让 TaskExecutor 负责添加
                    // 这里只负责构建 RefinementContext
                    
                    log.info("✅ 原始 AIRequest 消息数量：{}条", savedAIRequest.getMessages().size());
                    
                    // 构建迭代优化上下文
                    StoryPredictionParameters.RefinementContext refinementContext = 
                            StoryPredictionParameters.RefinementContext.builder()
                            .previousSummary(selectedPrediction.getSummary())
                            .previousSceneContent(selectedPrediction.getSceneContent())
                            .previousModelName(selectedPrediction.getModelName())
                            .iterationRound(getIterationRound(originalTask) + 1)
                            .originalTaskId(request.getOriginalTaskId())  // 🔥 使用前端传递的originalTaskId（前端已修复）
                            .savedAIRequest(savedAIRequest)  // 🔥 保存摘要 AIRequest
                            .sceneAIRequest(selectedPrediction.getSceneAIRequest())  // 🔥 保存场景 AIRequest
                            .build();
                    
                    // 3. 构建新的任务参数
                    StoryPredictionParameters parameters = StoryPredictionParameters.builder()
                            .novelId(novelId)
                            .chapterId(getChapterId(originalTask))
                            .modelConfigs(request.getModelConfigs())
                            .generationCount(request.getGenerationCount())
                            .basePredictionId(request.getBasePredictionId())
                            .refinementInstructions(request.getRefinementInstructions())
                            .refinementContext(refinementContext)
                            // 继承或使用新的配置
                            .contextSelection(request.getContextSelection() != null 
                                    ? request.getContextSelection()
                                    : getOriginalContextSelection(originalTask))
                            .generateSceneContent(request.getGenerateSceneContent())
                            .styleInstructions(request.getStyleInstructions())
                            .additionalInstructions(request.getAdditionalInstructions())
                            .summaryPromptTemplateId(request.getSummaryPromptTemplateId())
                            .scenePromptTemplateId(request.getScenePromptTemplateId())
                            .build();
                    
                    log.info("✅ 迭代优化参数构建完成: 轮次={}, 上一次摘要长度={}, 修改意见长度={}", 
                            refinementContext.getIterationRound(),
                            selectedPrediction.getSummary() != null ? selectedPrediction.getSummary().length() : 0,
                            request.getRefinementInstructions().length());
                    
                    // 4. 提交新任务
                    return taskSubmissionService.submitTask(userId, "STORY_PREDICTION", parameters);
                });
    }
    

    

    /**
     * 🔥 从任务progress中提取已完成的预测
     * 支持在任务RUNNING状态下，只要某个预测卡片完成就能用于迭代
     */
    private Mono<StoryPredictionResult.PredictionItem> extractPredictionFromProgress(
            com.ainovel.server.task.model.BackgroundTask task,
            String predictionId) {
        
        try {
            Object progressObj = task.getProgress();
            if (progressObj == null) {
                return Mono.error(new IllegalArgumentException("任务暂无进度数据"));
            }
            
            log.debug("尝试从progress中提取预测: predictionId={}", predictionId);
            
            if (progressObj instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<String, Object> progressMap = (Map<String, Object>) progressObj;
                
                // 正确字段名是 "predictionProgress"，且是一个List而不是Map
                Object predictionsObj = progressMap.get("predictionProgress");
                
                if (predictionsObj instanceof List) {
                    @SuppressWarnings("unchecked")
                    List<Map<String, Object>> predictionsList = (List<Map<String, Object>>) predictionsObj;
                    
                    // 遍历List查找指定的predictionId
                    for (Map<String, Object> predMap : predictionsList) {
                        String currentId = (String) predMap.get("predictionId");
                        
                        if (predictionId.equals(currentId)) {
                            // 找到了目标预测
                            String status = (String) predMap.get("status");
                            
                            // 检查状态是否完成
                            if (!"COMPLETED".equals(status)) {
                                log.warn("预测未完成: predictionId={}, status={}", predictionId, status);
                                return Mono.error(new IllegalArgumentException("指定的预测尚未完成（当前状态：" + status + "），请等待"));
                            }
                            
                            // 🔥 提取 aiRequest
                            AIRequest aiRequest = extractAIRequestFromMap(predMap.get("aiRequest"));
                            if (aiRequest == null) {
                                log.warn("⚠️ 预测中未找到 aiRequest，将在迭代时重新构建");
                            } else {
                                log.info("✅ 从progress中提取到 aiRequest: messages={}", aiRequest.getMessages().size());
                            }
                            
                            // 构建PredictionItem
                            StoryPredictionResult.PredictionItem item = StoryPredictionResult.PredictionItem.builder()
                                    .id(predictionId)
                                    .modelId((String) predMap.get("modelId"))
                                    .modelName((String) predMap.get("modelName"))
                                    .summary((String) predMap.get("summary"))
                                    .sceneContent((String) predMap.get("sceneContent"))
                                    .status(status)
                                    .aiRequest(aiRequest)  // 🔥 包含 AIRequest
                                    .build();
                            
                            log.info("✅ 从progress中成功提取预测: predictionId={}, modelName={}, summary长度={}, 含AIRequest={}", 
                                    predictionId, 
                                    item.getModelName(),
                                    item.getSummary() != null ? item.getSummary().length() : 0,
                                    aiRequest != null);
                            
                            return Mono.just(item);
                        }
                    }
                }
            }
            
            log.warn("progress中未找到指定预测: predictionId={}", predictionId);
            return Mono.error(new IllegalArgumentException("未找到指定的预测: " + predictionId));
            
        } catch (Exception e) {
            log.error("从progress提取预测失败: predictionId={}, error={}", predictionId, e.getMessage(), e);
            return Mono.error(new IllegalArgumentException("无法从进度数据中提取预测: " + e.getMessage()));
        }
    }
    
    /**
     * 从Map中提取AIRequest对象
     * MongoDB反序列化后可能是AIRequest对象，也可能是Map
     */
    private AIRequest extractAIRequestFromMap(Object aiRequestObj) {
        if (aiRequestObj == null) {
            return null;
        }
        
        // 已经是AIRequest对象
        if (aiRequestObj instanceof AIRequest) {
            return (AIRequest) aiRequestObj;
        }
        
        // 是Map，需要手动转换
        if (aiRequestObj instanceof Map) {
            return convertMapToAIRequest((Map<?, ?>) aiRequestObj);
        }
        
        log.warn("未知的aiRequest类型: {}", aiRequestObj.getClass().getName());
        return null;
    }
    
    /**
     * 从 Map 转换为 AIRequest（用于 MongoDB 反序列化）
     */
    private AIRequest convertMapToAIRequest(Map<?, ?> map) {
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> messagesMap = (List<Map<String, Object>>) map.get("messages");
        
        List<AIRequest.Message> messages = new ArrayList<>();
        if (messagesMap != null) {
            for (Map<String, Object> msgMap : messagesMap) {
                messages.add(AIRequest.Message.builder()
                        .role((String) msgMap.get("role"))
                        .content((String) msgMap.get("content"))
                        .build());
            }
        }
        
        @SuppressWarnings("unchecked")
        Map<String, Object> parameters = (Map<String, Object>) map.get("parameters");
        @SuppressWarnings("unchecked")
        Map<String, Object> metadata = (Map<String, Object>) map.get("metadata");
        
        String featureTypeStr = (String) map.get("featureType");
        AIFeatureType featureType = featureTypeStr != null ? AIFeatureType.valueOf(featureTypeStr) : null;
        
        return AIRequest.builder()
                .userId((String) map.get("userId"))
                .novelId((String) map.get("novelId"))
                .sceneId((String) map.get("sceneId"))
                .model((String) map.get("model"))
                .featureType(featureType)
                .maxTokens(map.get("maxTokens") != null ? ((Number) map.get("maxTokens")).intValue() : null)
                .temperature(map.get("temperature") != null ? ((Number) map.get("temperature")).doubleValue() : null)
                .parameters(parameters != null ? parameters : new HashMap<>())
                .metadata(metadata != null ? metadata : new HashMap<>())
                .messages(messages)
                .build();
    }
}
