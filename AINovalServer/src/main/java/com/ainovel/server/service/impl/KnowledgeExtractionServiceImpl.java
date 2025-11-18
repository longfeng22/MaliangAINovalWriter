package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.FanqieNovelImportRecord;
import com.ainovel.server.domain.model.KnowledgeExtractionType;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.service.FanqieNovelImportRecordService;
import com.ainovel.server.service.KnowledgeExtractionService;
import com.ainovel.server.service.PublicModelConfigService;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.web.dto.request.FanqieKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.request.TextKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.response.KnowledgeExtractionTaskResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 知识提取服务实现
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class KnowledgeExtractionServiceImpl implements KnowledgeExtractionService {
    
    private final TaskStateService taskStateService;
    private final TaskSubmissionService taskSubmissionService;
    private final FanqieNovelImportRecordService importRecordService;
    private final PublicModelConfigService publicModelConfigService;
    
    @Override
    public Mono<KnowledgeExtractionTaskResponse> extractFromFanqieNovel(
            FanqieKnowledgeExtractionRequest request, 
            String userId) {
        
        log.info("从番茄小说提取知识库: fanqieNovelId={}, userId={}", 
                request.getFanqieNovelId(), userId);
        
        // 解析提取类型（如果为空，使用全部默认类型）
        List<KnowledgeExtractionType> extractionTypes = parseExtractionTypes(request.getExtractionTypes());
        
        // 自动选择带有"chaishu"标签的公共模型
        return selectChaishuModel()
                .flatMap(modelConfig -> {
                    log.info("使用拆书专用模型: modelId={}", modelConfig.getId());
                    
                    // 创建导入记录
                    FanqieNovelImportRecord importRecord = FanqieNovelImportRecord.builder()
                            .fanqieNovelId(request.getFanqieNovelId())
                            .userId(userId)
                            .status(FanqieNovelImportRecord.ImportStatus.PENDING)
                            .extractionTypes(extractionTypes)
                            .llmRequests(new ArrayList<>())
                            .totalTokensUsed(0L)
                            .modelConfigId(modelConfig.getId())
                            .modelType("public")
                            .build();
        
                    return importRecordService.create(importRecord)
                            .flatMap(record -> {
                                // 提交后台任务
                                Map<String, Object> taskParams = new HashMap<>();
                                taskParams.put("importRecordId", record.getId());
                                taskParams.put("fanqieNovelId", request.getFanqieNovelId());
                                taskParams.put("modelConfigId", modelConfig.getId());
                                taskParams.put("modelType", "public");
                                taskParams.put("extractionTypes", extractionTypes.stream()
                                        .map(KnowledgeExtractionType::getValue)
                                        .collect(Collectors.toList()));
                                taskParams.put("userId", userId);
                                
                                return taskSubmissionService.submitTask(
                                        userId,
                                        "KNOWLEDGE_EXTRACTION_FANQIE",
                                        taskParams,
                                        null
                                ).flatMap(taskId -> {
                                    // 更新导入记录的任务ID
                                    record.setTaskId(taskId);
                                    return importRecordService.update(record)
                                            .then(buildTaskResponse(taskId, record.getId()));
                                });
                            });
                });
    }
    
    /**
     * 选择带有"chaishu"标签的公共模型
     */
    private Mono<PublicModelConfig> selectChaishuModel() {
        return publicModelConfigService.findAllEnabled()
                .filter(model -> {
                    if (model.getTags() == null) {
                        return false;
                    }
                    // 检查标签列表是否包含"chaishu"
                    return model.getTags().stream()
                            .anyMatch(tag -> "chaishu".equalsIgnoreCase(tag.trim()));
                })
                .next()
                .switchIfEmpty(Mono.error(new IllegalStateException(
                        "未找到带有'chaishu'标签的公共模型，请在系统中配置拆书专用模型")));
    }
    
    @Override
    public Mono<KnowledgeExtractionTaskResponse> extractFromUserText(
            TextKnowledgeExtractionRequest request,
            String userId) {
        
        log.info("从用户文本提取知识库: title={}, userId={}", request.getTitle(), userId);
        
        // 解析提取类型
        List<KnowledgeExtractionType> extractionTypes = parseExtractionTypes(request.getExtractionTypes());
        
        // 创建导入记录
        FanqieNovelImportRecord importRecord = FanqieNovelImportRecord.builder()
                .userId(userId)
                .status(FanqieNovelImportRecord.ImportStatus.PENDING)
                .extractionTypes(extractionTypes)
                .llmRequests(new ArrayList<>())
                .totalTokensUsed(0L)
                .novelTitle(request.getTitle())
                .modelConfigId(request.getModelConfigId())
                .modelType(request.getModelType())
                .build();
        
        return importRecordService.create(importRecord)
                .flatMap(record -> {
                    // 提交后台任务
                    Map<String, Object> taskParams = new HashMap<>();
                    taskParams.put("importRecordId", record.getId());
                    taskParams.put("title", request.getTitle());
                    taskParams.put("content", request.getContent());
                    taskParams.put("description", request.getDescription());
                    taskParams.put("modelConfigId", request.getModelConfigId());
                    taskParams.put("modelType", request.getModelType());
                    taskParams.put("extractionTypes", extractionTypes.stream()
                            .map(KnowledgeExtractionType::getValue)
                            .collect(Collectors.toList()));
                    taskParams.put("userId", userId);
                    
                    // ✅ 传递章节数量（如果有）
                    if (request.getChapterCount() != null) {
                        taskParams.put("chapterCount", request.getChapterCount());
                        log.info("用户文本提取: 传递章节数量={}", request.getChapterCount());
                    }
                    
                    // ✅ 传递预览会话ID（用于获取章节详情）
                    if (request.getPreviewSessionId() != null && !request.getPreviewSessionId().isEmpty()) {
                        taskParams.put("previewSessionId", request.getPreviewSessionId());
                        log.info("用户文本提取: 传递预览会话ID={}", request.getPreviewSessionId());
                    }
                    
                    return taskSubmissionService.submitTask(
                            userId,
                            "KNOWLEDGE_EXTRACTION_TEXT",
                            taskParams,
                            null
                    ).flatMap(taskId -> {
                        // 更新导入记录的任务ID
                        record.setTaskId(taskId);
                        return importRecordService.update(record)
                                .then(buildTaskResponse(taskId, record.getId()));
                    });
                });
    }
    
    @Override
    public Mono<KnowledgeExtractionTaskResponse> getExtractionTaskStatus(String taskId) {
        log.info("获取拆书任务状态: {}", taskId);
        
        return taskStateService.getTask(taskId)
                .map(task -> {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> progressData = task.getProgress() instanceof Map ? 
                            (Map<String, Object>) task.getProgress() : new HashMap<>();
                    
                    Instant createdAt = task.getTimestamps().getCreatedAt();
                    LocalDateTime startTime = createdAt != null ? 
                            LocalDateTime.ofInstant(createdAt, ZoneId.systemDefault()) : null;
                    
                    KnowledgeExtractionTaskResponse response = KnowledgeExtractionTaskResponse.builder()
                            .taskId(taskId)
                            .status(task.getStatus().name())
                            .progress(calculateProgress(progressData))
                            .message(task.getErrorInfo() != null ? 
                                    task.getErrorInfo().getOrDefault("message", "").toString() : "处理中")
                            .startTime(startTime)
                            .build();
                    
                    // 如果任务完成，获取知识库ID
                    if (progressData != null) {
                        Object kbId = progressData.get("knowledgeBaseId");
                        if (kbId != null) {
                            response.setKnowledgeBaseId(kbId.toString());
                        }
                    }
                    
                    return response;
                });
    }
    
    /**
     * 解析提取类型
     */
    private List<KnowledgeExtractionType> parseExtractionTypes(List<String> typeStrings) {
        if (typeStrings == null || typeStrings.isEmpty()) {
            // 返回所有默认类型
            return Arrays.stream(KnowledgeExtractionType.values())
                    .collect(Collectors.toList());
        }
        
        return typeStrings.stream()
                .map(typeStr -> {
                    try {
                        return KnowledgeExtractionType.fromValue(typeStr);
                    } catch (IllegalArgumentException e) {
                        log.warn("未知的提取类型: {}", typeStr);
                        return null;
                    }
                })
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }
    
    /**
     * 构建任务响应
     */
    private Mono<KnowledgeExtractionTaskResponse> buildTaskResponse(String taskId, String importRecordId) {
        return Mono.just(KnowledgeExtractionTaskResponse.builder()
                .taskId(taskId)
                .status("PENDING")
                .progress(0)
                .message("任务已创建，等待执行")
                .startTime(LocalDateTime.now())
                .build());
    }
    
    /**
     * 计算进度百分比
     */
    private Integer calculateProgress(Map<String, Object> progressData) {
        if (progressData == null) {
            return 0;
        }
        
        Object progressObj = progressData.get("progress");
        if (progressObj instanceof Number) {
            return ((Number) progressObj).intValue();
        }
        
        Object completedObj = progressData.get("completedSubTasks");
        Object totalObj = progressData.get("totalSubTasks");
        
        if (completedObj instanceof Number && totalObj instanceof Number) {
            int completed = ((Number) completedObj).intValue();
            int total = ((Number) totalObj).intValue();
            if (total > 0) {
                return (int) ((completed * 100.0) / total);
            }
        }
        
        return 0;
    }
}

