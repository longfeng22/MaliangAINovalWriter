package com.ainovel.server.service;

import com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord;
import com.ainovel.server.repository.KnowledgeExtractionTaskRecordRepository;
import com.ainovel.server.task.service.TaskSubmissionService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * AI拆书任务管理服务
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class KnowledgeExtractionTaskService {
    
    private final KnowledgeExtractionTaskRecordRepository taskRecordRepository;
    private final TaskSubmissionService taskSubmissionService;
    
    /**
     * 创建任务记录
     */
    public Mono<KnowledgeExtractionTaskRecord> createTaskRecord(
            String taskId,
            String userId,
            String importRecordId,
            String fanqieNovelId,
            String novelTitle,
            String novelAuthor,
            String coverImageUrl,
            KnowledgeExtractionTaskRecord.SourceType sourceType,
            String modelConfigId,
            String modelType,
            List<String> extractionTypes) {
        
        KnowledgeExtractionTaskRecord record = KnowledgeExtractionTaskRecord.builder()
                .id(taskId)
                .userId(userId)
                .importRecordId(importRecordId)
                .fanqieNovelId(fanqieNovelId)
                .novelTitle(novelTitle)
                .novelAuthor(novelAuthor)
                .coverImageUrl(coverImageUrl)
                .sourceType(sourceType)
                .status(KnowledgeExtractionTaskRecord.TaskStatus.QUEUED)
                .progress(0)
                .currentStep("QUEUED")
                .startTime(LocalDateTime.now())
                .totalSubTasks(0)
                .completedSubTasks(0)
                .failedSubTasks(0)
                .retryCount(0)
                .modelConfigId(modelConfigId)
                .modelType(modelType)
                .extractionTypes(extractionTypes)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
        
        return taskRecordRepository.save(record)
                .doOnSuccess(r -> log.info("创建任务记录成功: taskId={}, title={}", taskId, novelTitle))
                .doOnError(e -> log.error("创建任务记录失败: taskId={}, error={}", taskId, e.getMessage()));
    }
    
    /**
     * 更新任务详细信息（标题、作者、封面）
     */
    public Mono<Void> updateTaskDetails(
            String taskId,
            String novelTitle,
            String novelAuthor,
            String coverImageUrl) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    record.setNovelTitle(novelTitle);
                    record.setNovelAuthor(novelAuthor);
                    record.setCoverImageUrl(coverImageUrl);
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    return taskRecordRepository.save(record);
                })
                .doOnSuccess(r -> log.info("更新任务详细信息: taskId={}, title={}, author={}", 
                        taskId, novelTitle, novelAuthor))
                .doOnError(e -> log.error("更新任务详细信息失败: taskId={}, error={}", taskId, e.getMessage()))
                .then();
    }
    
    /**
     * 更新任务状态
     */
    public Mono<KnowledgeExtractionTaskRecord> updateTaskStatus(
            String taskId,
            KnowledgeExtractionTaskRecord.TaskStatus status,
            String currentStep) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    record.setStatus(status);
                    record.setCurrentStep(currentStep);
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    if (status == KnowledgeExtractionTaskRecord.TaskStatus.COMPLETED ||
                        status == KnowledgeExtractionTaskRecord.TaskStatus.FAILED) {
                        record.setEndTime(LocalDateTime.now());
                        record.calculateDuration();
                    }
                    
                    return taskRecordRepository.save(record);
                })
                .doOnSuccess(r -> log.debug("更新任务状态: taskId={}, status={}", taskId, status));
    }
    
    /**
     * 更新任务进度
     */
    public Mono<KnowledgeExtractionTaskRecord> updateTaskProgress(
            String taskId,
            Integer progress,
            String currentStep,
            Integer totalSubTasks,
            Integer completedSubTasks,
            Integer failedSubTasks) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    if (progress != null) record.setProgress(progress);
                    if (currentStep != null) record.setCurrentStep(currentStep);
                    if (totalSubTasks != null) record.setTotalSubTasks(totalSubTasks);
                    if (completedSubTasks != null) record.setCompletedSubTasks(completedSubTasks);
                    if (failedSubTasks != null) record.setFailedSubTasks(failedSubTasks);
                    
                    record.updateProgress();
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    return taskRecordRepository.save(record);
                });
    }
    
    /**
     * 添加或更新子任务信息
     */
    public Mono<KnowledgeExtractionTaskRecord> updateSubTaskInfo(
            String taskId,
            KnowledgeExtractionTaskRecord.SubTaskInfo subTaskInfo) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    List<KnowledgeExtractionTaskRecord.SubTaskInfo> subTasks = record.getSubTasks();
                    if (subTasks == null) {
                        subTasks = new java.util.ArrayList<>();
                        record.setSubTasks(subTasks);
                    }
                    
                    // 查找是否已存在该子任务
                    boolean found = false;
                    for (int i = 0; i < subTasks.size(); i++) {
                        if (subTasks.get(i).getSubTaskId().equals(subTaskInfo.getSubTaskId())) {
                            subTasks.set(i, subTaskInfo);
                            found = true;
                            break;
                        }
                    }
                    
                    if (!found) {
                        subTasks.add(subTaskInfo);
                    }
                    
                    // 更新统计
                    long completed = subTasks.stream()
                            .filter(st -> st.getStatus() == KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.COMPLETED)
                            .count();
                    long failed = subTasks.stream()
                            .filter(st -> st.getStatus() == KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.FAILED)
                            .count();
                    
                    record.setTotalSubTasks(subTasks.size());
                    record.setCompletedSubTasks((int) completed);
                    record.setFailedSubTasks((int) failed);
                    record.updateProgress();
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    return taskRecordRepository.save(record);
                })
                .doOnSuccess(r -> log.debug("更新子任务信息: taskId={}, subTaskId={}", 
                        taskId, subTaskInfo.getSubTaskId()));
    }
    
    /**
     * 记录任务成功
     */
    public Mono<KnowledgeExtractionTaskRecord> recordTaskSuccess(
            String taskId,
            String knowledgeBaseId,
            Integer totalSettings,
            Long totalTokens) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    record.setStatus(KnowledgeExtractionTaskRecord.TaskStatus.COMPLETED);
                    record.setKnowledgeBaseId(knowledgeBaseId);
                    record.setTotalSettings(totalSettings);
                    record.setTotalTokens(totalTokens);
                    record.setProgress(100);
                    record.setEndTime(LocalDateTime.now());
                    record.calculateDuration();
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    return taskRecordRepository.save(record);
                })
                .switchIfEmpty(Mono.defer(() -> {
                    // ⚠️ 警告：任务记录不存在，这不应该发生！
                    log.error("❌ 任务记录不存在，无法记录成功: taskId={}", taskId);
                    return Mono.empty();
                }))
                .doOnSuccess(r -> {
                    if (r != null) {
                        log.info("任务成功完成: taskId={}, knowledgeBaseId={}", taskId, knowledgeBaseId);
                    }
                })
                .doOnError(e -> log.error("记录任务成功时出错: taskId={}, error={}", taskId, e.getMessage()));
    }
    
    /**
     * 记录任务失败
     */
    public Mono<KnowledgeExtractionTaskRecord> recordTaskFailure(
            String taskId,
            String errorMessage,
            String errorStack,
            KnowledgeExtractionTaskRecord.FailureReason failureReason) {
        
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    record.setStatus(KnowledgeExtractionTaskRecord.TaskStatus.FAILED);
                    record.setErrorMessage(errorMessage);
                    record.setErrorStack(errorStack);
                    record.setFailureReason(failureReason);
                    record.setEndTime(LocalDateTime.now());
                    record.calculateDuration();
                    record.setUpdatedAt(LocalDateTime.now());
                    
                    return taskRecordRepository.save(record);
                })
                .doOnError(e -> log.error("记录任务失败时出错: taskId={}, error={}", taskId, e.getMessage()));
    }
    
    /**
     * 查询所有任务列表（管理员）
     */
    public Flux<KnowledgeExtractionTaskRecord> getAllTasks(
            KnowledgeExtractionTaskRecord.TaskStatus status,
            int page,
            int size) {
        
        PageRequest pageRequest = PageRequest.of(page, size);
        
        if (status != null) {
            return taskRecordRepository.findByStatusOrderByCreatedAtDesc(status, pageRequest);
        } else {
            return taskRecordRepository.findAllByOrderByCreatedAtDesc(pageRequest);
        }
    }
    
    /**
     * 统计所有任务数量（管理员）
     */
    public Mono<Long> countAllTasks(KnowledgeExtractionTaskRecord.TaskStatus status) {
        if (status != null) {
            return taskRecordRepository.countByStatus(status);
        } else {
            return taskRecordRepository.count();
        }
    }
    
    /**
     * 查询用户的任务列表
     */
    public Flux<KnowledgeExtractionTaskRecord> getUserTasks(
            String userId,
            KnowledgeExtractionTaskRecord.TaskStatus status,
            int page,
            int size) {
        
        PageRequest pageRequest = PageRequest.of(page, size);
        
        if (status != null) {
            return taskRecordRepository.findByUserIdAndStatusOrderByCreatedAtDesc(userId, status, pageRequest);
        } else {
            return taskRecordRepository.findByUserIdOrderByCreatedAtDesc(userId, pageRequest);
        }
    }
    
    /**
     * 统计用户任务数量
     */
    public Mono<Long> countUserTasks(String userId, KnowledgeExtractionTaskRecord.TaskStatus status) {
        if (status != null) {
            return taskRecordRepository.countByUserIdAndStatus(userId, status);
        } else {
            return taskRecordRepository.countByUserId(userId);
        }
    }
    
    /**
     * 获取任务详情
     */
    public Mono<KnowledgeExtractionTaskRecord> getTaskDetail(String taskId) {
        return taskRecordRepository.findById(taskId);
    }
    
    /**
     * 重试失败的任务
     * 
     * @param taskId 任务ID
     * @param userId 当前用户ID
     * @param isAdmin 是否为管理员
     */
    public Mono<String> retryFailedTask(String taskId, String userId, boolean isAdmin) {
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    // ✅ 管理员可以重试所有任务，普通用户只能重试自己的任务
                    if (!isAdmin && !record.getUserId().equals(userId)) {
                        log.warn("用户 {} 尝试重试其他用户的任务: taskId={}, taskUserId={}", 
                                userId, taskId, record.getUserId());
                        return Mono.error(new IllegalArgumentException("无权限重试此任务"));
                    }
                    
                    // 验证状态
                    if (!record.canRetry()) {
                        return Mono.error(new IllegalStateException(
                                "任务不可重试: status=" + record.getStatus() + ", retryCount=" + record.getRetryCount()));
                    }
                    
                    log.info("开始重试任务: taskId={}, userId={}, isAdmin={}, taskUserId={}", 
                            taskId, userId, isAdmin, record.getUserId());
                    
                    // 构建任务参数
                    Map<String, Object> parameters = new HashMap<>();
                    parameters.put("importRecordId", record.getImportRecordId());
                    parameters.put("modelConfigId", record.getModelConfigId());
                    parameters.put("modelType", record.getModelType());
                    parameters.put("extractionTypes", record.getExtractionTypes());
                    parameters.put("userId", userId);
                    
                    if (record.getFanqieNovelId() != null) {
                        parameters.put("fanqieNovelId", record.getFanqieNovelId());
                    }
                    
                    // 提交新任务
                    String taskType = record.getSourceType() == KnowledgeExtractionTaskRecord.SourceType.FANQIE_NOVEL
                            ? "KNOWLEDGE_EXTRACTION_FANQIE"
                            : "KNOWLEDGE_EXTRACTION_TEXT";
                    
                    return taskSubmissionService.submitTask(userId, taskType, parameters)
                            .flatMap(newTaskId -> {
                                // 更新原任务记录
                                record.setLastRetryTime(LocalDateTime.now());
                                record.setUpdatedAt(LocalDateTime.now());
                                
                                return taskRecordRepository.save(record)
                                        .thenReturn(newTaskId);
                            });
                })
                .doOnSuccess(newTaskId -> log.info("任务重试成功: originalTaskId={}, newTaskId={}", taskId, newTaskId))
                .doOnError(e -> log.error("任务重试失败: taskId={}, error={}", taskId, e.getMessage()));
    }
    
    /**
     * 重试失败的子任务
     * 
     * @param taskId 任务ID
     * @param subTaskId 子任务ID
     * @param userId 当前用户ID
     * @param isAdmin 是否为管理员
     */
    public Mono<String> retryFailedSubTask(String taskId, String subTaskId, String userId, boolean isAdmin) {
        return taskRecordRepository.findById(taskId)
                .flatMap(record -> {
                    // ✅ 管理员可以重试所有任务，普通用户只能重试自己的任务
                    if (!isAdmin && !record.getUserId().equals(userId)) {
                        log.warn("用户 {} 尝试重试其他用户的子任务: taskId={}, subTaskId={}, taskUserId={}", 
                                userId, taskId, subTaskId, record.getUserId());
                        return Mono.error(new IllegalArgumentException("无权限重试此任务"));
                    }
                    
                    log.info("开始重试子任务: taskId={}, subTaskId={}, userId={}, isAdmin={}, taskUserId={}", 
                            taskId, subTaskId, userId, isAdmin, record.getUserId());
                    
                    // 查找子任务
                    KnowledgeExtractionTaskRecord.SubTaskInfo subTask = record.getSubTasks().stream()
                            .filter(st -> st.getSubTaskId().equals(subTaskId))
                            .findFirst()
                            .orElse(null);
                    
                    if (subTask == null) {
                        return Mono.error(new IllegalArgumentException("子任务不存在: " + subTaskId));
                    }
                    
                    if (subTask.getStatus() != KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.FAILED) {
                        return Mono.error(new IllegalStateException("子任务状态不是FAILED，无法重试"));
                    }
                    
                    // 构建子任务参数（从原子任务信息中获取）
                    Map<String, Object> parameters = new HashMap<>();
                    parameters.put("groupName", subTask.getGroupName());
                    parameters.put("extractionTypes", subTask.getExtractionTypes());
                    parameters.put("modelConfigId", record.getModelConfigId());
                    parameters.put("modelType", record.getModelType());
                    parameters.put("parentTaskId", taskId);
                    
                    // 需要从原任务中获取小说内容
                    // TODO: 这里需要重新获取小说内容，或者从缓存中读取
                    
                    // 提交子任务
                    return taskSubmissionService.submitTask(userId, "KNOWLEDGE_EXTRACTION_GROUP", parameters)
                            .flatMap(newSubTaskId -> {
                                // 更新子任务状态为待执行
                                subTask.setStatus(KnowledgeExtractionTaskRecord.SubTaskInfo.SubTaskStatus.PENDING);
                                subTask.setErrorMessage(null);
                                
                                record.setUpdatedAt(LocalDateTime.now());
                                
                                return taskRecordRepository.save(record)
                                        .thenReturn(newSubTaskId);
                            });
                })
                .doOnSuccess(newSubTaskId -> log.info("子任务重试成功: taskId={}, subTaskId={}, newSubTaskId={}", 
                        taskId, subTaskId, newSubTaskId))
                .doOnError(e -> log.error("子任务重试失败: taskId={}, subTaskId={}, error={}", 
                        taskId, subTaskId, e.getMessage()));
    }
    
    /**
     * 获取失败任务统计
     */
    /**
     * 获取所有失败任务统计（管理员）
     */
    public Mono<Map<String, Object>> getAllFailureStatistics() {
        return taskRecordRepository.findByStatusAndRetryCountLessThanOrderByCreatedAtDesc(
                        KnowledgeExtractionTaskRecord.TaskStatus.FAILED, 
                        3)
                .collectList()
                .map(tasks -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("totalFailed", tasks.size());
                    
                    // 按失败原因分类统计
                    Map<KnowledgeExtractionTaskRecord.FailureReason, Long> byReason = tasks.stream()
                            .collect(java.util.stream.Collectors.groupingBy(
                                    t -> t.getFailureReason() != null ? t.getFailureReason() : 
                                         KnowledgeExtractionTaskRecord.FailureReason.UNKNOWN,
                                    java.util.stream.Collectors.counting()));
                    
                    stats.put("byReason", byReason);
                    stats.put("canRetry", tasks.stream().filter(KnowledgeExtractionTaskRecord::canRetry).count());
                    
                    return stats;
                });
    }
    
    /**
     * 获取用户失败任务统计
     */
    public Mono<Map<String, Object>> getFailureStatistics(String userId) {
        return taskRecordRepository.findByUserIdAndStatusAndRetryCountLessThan(
                        userId, 
                        KnowledgeExtractionTaskRecord.TaskStatus.FAILED, 
                        3)
                .collectList()
                .map(tasks -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("totalFailed", tasks.size());
                    
                    // 按失败原因分类统计
                    Map<KnowledgeExtractionTaskRecord.FailureReason, Long> byReason = tasks.stream()
                            .collect(java.util.stream.Collectors.groupingBy(
                                    t -> t.getFailureReason() != null ? t.getFailureReason() : 
                                         KnowledgeExtractionTaskRecord.FailureReason.UNKNOWN,
                                    java.util.stream.Collectors.counting()));
                    
                    stats.put("byReason", byReason);
                    stats.put("canRetry", tasks.stream().filter(KnowledgeExtractionTaskRecord::canRetry).count());
                    
                    return stats;
                });
    }
}

