package com.ainovel.server.task.executor;

import com.ainovel.server.domain.model.KnowledgeExtractionType;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.ai.strategy.KnowledgeExtractionStrategy;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionGroupParameters;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionGroupProgress;
import com.ainovel.server.task.dto.knowledge.KnowledgeExtractionGroupResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

/**
 * 知识提取组任务执行器（子任务）
 * 负责执行单个提取组（如"文风叙事"、"人物情节"等）的知识提取
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class KnowledgeExtractionGroupTaskExecutor 
        implements BackgroundTaskExecutable<KnowledgeExtractionGroupParameters, KnowledgeExtractionGroupResult> {
    
    private final AIService aiService;
    private final ObjectMapper objectMapper;
    private final com.ainovel.server.service.KnowledgeExtractionTaskService taskRecordService;
    
    @Override
    public String getTaskType() {
        return "KNOWLEDGE_EXTRACTION_GROUP";
    }
    
    @Override
    public Mono<KnowledgeExtractionGroupResult> execute(TaskContext<KnowledgeExtractionGroupParameters> context) {
        KnowledgeExtractionGroupParameters parameters = context.getParameters();
        String taskId = context.getTaskId();
        String groupName = parameters.getGroupName();
        
        log.info("开始执行知识提取组任务: taskId={}, groupName={}, types={}", 
                taskId, groupName, parameters.getExtractionTypes());
        
        // 初始化进度
        KnowledgeExtractionGroupProgress progress = KnowledgeExtractionGroupProgress.builder()
                .groupName(groupName)
                .currentStep("INITIALIZING")
                .progress(0)
                .extractedCount(0)
                .lastUpdated(LocalDateTime.now())
                .build();
        
        AtomicLong totalTokens = new AtomicLong(0);
        
        return context.updateProgress(progress)
                .then(Mono.defer(() -> {
                    // 解析提取类型
                    List<KnowledgeExtractionType> types = parameters.getExtractionTypes().stream()
                            .map(KnowledgeExtractionType::fromValue)
                            .collect(Collectors.toList());
                    
                    log.info("🚀 一次性提取整个组: groupName={}, types={}", 
                            groupName, types.stream().map(KnowledgeExtractionType::getValue).collect(Collectors.toList()));
                    
                    progress.setCurrentStep("EXTRACTING");
                    progress.setProgress(20);
                    
                    // 创建子任务记录
                    String parentTaskId = parameters.getParentTaskId();
                    com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo subTaskInfo = 
                            com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo.builder()
                                    .subTaskId(taskId)
                                    .groupName(groupName)
                                    .extractionTypes(parameters.getExtractionTypes())
                                    .status(com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.RUNNING)
                                    .progress(20)
                                    .extractedCount(0)
                                    .startTime(LocalDateTime.now())
                                    .build();
                    
                    // ✅ 一次性提取整个组的所有类型
                    return context.updateProgress(progress)
                            .then(updateSubTaskRecord(parentTaskId, subTaskInfo))
                            .then(extractGroupTypes(context, types, parameters))
                            .flatMap(settings -> {
                                progress.setCurrentStep("COMPLETED");
                                progress.setProgress(100);
                                progress.setExtractedCount(settings.size());
                                
                                log.info("✅ 组提取完成: groupName={}, 设定数量: {}", groupName, settings.size());
                                
                                // 更新子任务为完成状态
                                subTaskInfo.setStatus(com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.COMPLETED);
                                subTaskInfo.setProgress(100);
                                subTaskInfo.setExtractedCount(settings.size());
                                subTaskInfo.setTokensUsed(totalTokens.get());
                                subTaskInfo.setEndTime(LocalDateTime.now());
                                
                                return context.updateProgress(progress)
                                        .then(updateSubTaskRecord(parentTaskId, subTaskInfo))
                                        .then(Mono.just(KnowledgeExtractionGroupResult.builder()
                                                .groupName(groupName)
                                                .settings(settings)
                                                .success(true)
                                                .tokensUsed(totalTokens.get())
                                                .build()));
                            })
                            .onErrorResume(error -> {
                                log.error("❌ 组提取失败: groupName={}, error={}", groupName, error.getMessage());
                                
                                // 更新子任务为失败状态
                                subTaskInfo.setStatus(com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.FAILED);
                                subTaskInfo.setErrorMessage(error.getMessage());
                                subTaskInfo.setEndTime(LocalDateTime.now());
                                
                                return updateSubTaskRecord(parentTaskId, subTaskInfo)
                                        .then(Mono.just(KnowledgeExtractionGroupResult.builder()
                                                .groupName(groupName)
                                                .settings(new ArrayList<>())
                                                .success(false)
                                                .errorMessage(error.getMessage())
                                                .tokensUsed(totalTokens.get())
                                                .build()));
                            });
                }))
                .doOnSuccess(result -> {
                    log.info("✅ 知识提取组任务完成: taskId={}, groupName={}, 设定数量: {}", 
                            taskId, groupName, result.getSettings().size());
                })
                .doOnError(error -> {
                    log.error("❌ 知识提取组任务失败: taskId={}, groupName={}, error={}", 
                            taskId, groupName, error.getMessage(), error);
                })
                .onErrorResume(error -> {
                    // 任务失败时返回失败结果
                    return Mono.just(KnowledgeExtractionGroupResult.builder()
                            .groupName(groupName)
                            .settings(new ArrayList<>())
                            .success(false)
                            .errorMessage(error.getMessage())
                            .tokensUsed(totalTokens.get())
                            .build());
                });
    }
    
    /**
     * 一次性提取组内所有类型的设定
     */
    private Mono<List<NovelSettingItem>> extractGroupTypes(
            TaskContext<KnowledgeExtractionGroupParameters> context,
            List<KnowledgeExtractionType> types,
            KnowledgeExtractionGroupParameters parameters) {
        
        log.info("🎯 开始一次性提取组: types={}, contentLength={}", 
                types.stream().map(KnowledgeExtractionType::getValue).collect(Collectors.toList()),
                parameters.getContent().length());
        
        return Mono.fromCallable(() -> {
                    // ✅ 根据模型类型决定是否传递userId
                    // - user: 需要userId查找用户私有配置
                    // - public: 不需要userId，直接查找公共配置
                    String userId = "user".equals(parameters.getModelType()) ? context.getUserId() : null;
                    log.info("创建AI Provider: modelType={}, userId={}, configId={}", 
                            parameters.getModelType(), userId, parameters.getModelConfigId());
                    return aiService.createProviderByConfigId(userId, parameters.getModelConfigId());
                })
                .flatMap(provider -> {
                    // 创建知识提取策略
                    KnowledgeExtractionStrategy strategy = new KnowledgeExtractionStrategy(provider, objectMapper);
                    
                    // ✅ 一次性为整个组的所有类型调用LLM（传递章节数量、模型配置信息）
                    return strategy.extractKnowledgeForGroup(
                            types,
                            parameters.getContent(),
                            null, // novelId
                            context.getUserId(), // ✅ 传递userId用于计费
                            parameters.getChapterCount(),  // ✅ 传递章节数量
                            parameters.getModelConfigId(),  // ✅ 传递模型配置ID用于计费识别
                            parameters.getModelType()  // ✅ 传递模型类型用于计费识别
                    )
                    .doOnNext(settings -> {
                        log.info("✅ 组AI响应解析成功: types={}, 设定数量={}", 
                                types.stream().map(KnowledgeExtractionType::getValue).collect(Collectors.toList()),
                                settings.size());
                    });
                })
                .onErrorResume(error -> {
                    log.error("❌ 组AI调用失败: types={}, error={}", 
                            types.stream().map(KnowledgeExtractionType::getValue).collect(Collectors.toList()),
                            error.getMessage(), error);
                    // ✅ 不要吞掉错误，让调用者知道失败原因
                    return Mono.error(new RuntimeException(
                            "AI调用失败: " + error.getMessage(), error));
                });
    }
    
    /**
     * 更新子任务记录
     */
    private Mono<Void> updateSubTaskRecord(
            String parentTaskId,
            com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord.SubTaskInfo subTaskInfo) {
        
        if (parentTaskId == null) {
            return Mono.empty();
        }
        
        return taskRecordService.updateSubTaskInfo(parentTaskId, subTaskInfo)
                .then()
                .onErrorResume(error -> {
                    log.warn("更新子任务记录失败: parentTaskId={}, subTaskId={}, error={}", 
                            parentTaskId, subTaskInfo.getSubTaskId(), error.getMessage());
                    return Mono.empty();  // 不影响主流程
                });
    }
}

