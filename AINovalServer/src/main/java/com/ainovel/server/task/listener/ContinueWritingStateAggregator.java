package com.ainovel.server.task.listener;

import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Novel.Chapter;
import com.ainovel.server.repository.BackgroundTaskRepository;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentParameters;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentProgress;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentResult;
import com.ainovel.server.task.dto.continuecontent.GenerateSingleChapterResult;
import com.ainovel.server.task.event.internal.TaskCompletedEvent;
import com.ainovel.server.task.event.internal.TaskFailedEvent;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;
import com.ainovel.server.task.service.TaskStateService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 继续写作任务 (CONTINUE_WRITING_CONTENT) 状态聚合器
 * 监听 GenerateSingleChapterTask 子任务的事件，更新父任务状态。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ContinueWritingStateAggregator {
    
    private final TaskStateService taskStateService;
    private final NovelService novelService;
    private final ApplicationEventPublisher eventPublisher;
    
    // 用于确保事件幂等性处理的缓存
    private final ConcurrentHashMap<String, Boolean> processedEventIds = new ConcurrentHashMap<>();
    
    /**
     * 处理 GenerateSingleChapterTask 完成事件
     */
    @EventListener
    @Async
    public void onSingleChapterCompleted(TaskCompletedEvent event) {
        handleSingleChapterEvent(event, true);
    }
    
    /**
     * 处理 GenerateSingleChapterTask 失败事件
     */
    @EventListener
    @Async
    public void onSingleChapterFailed(TaskFailedEvent event) {
        handleSingleChapterEvent(event, false);
    }
    
    private void handleSingleChapterEvent(Object eventObject, boolean success) {
        String eventId;
        String taskId;
        TaskFailedEvent failedEvent = null; // Keep the reference
        
        if (eventObject instanceof TaskCompletedEvent) {
            TaskCompletedEvent event = (TaskCompletedEvent) eventObject;
            eventId = event.getEventId();
            taskId = event.getTaskId();
            log.debug("接收到 GenerateSingleChapterTask 完成事件: {}", taskId);
        } else if (eventObject instanceof TaskFailedEvent) {
            failedEvent = (TaskFailedEvent) eventObject;
            eventId = failedEvent.getEventId();
            taskId = failedEvent.getTaskId();
            String errorMessage = failedEvent.getErrorInfo() != null ? failedEvent.getErrorInfo().toString() : "未知错误";
            log.warn("接收到 GenerateSingleChapterTask 失败事件: {}, 错误: {}", taskId, errorMessage);
        } else {
            return; // Should not happen
        }
        
        // 检查事件幂等性
        if (!checkAndMarkEventProcessed(eventId)) {
            log.debug("事件已处理，跳过: {}", eventId);
            return;
        }
        
        final TaskFailedEvent finalFailedEvent = failedEvent; // Make it final for lambda

        taskStateService.getTask(taskId)
            .flatMap(task -> {
                if (task == null) {
                    log.warn("找不到任务: {}", taskId);
                    return Mono.empty();
                }
                
                // *** 检查任务类型 ***
                if (!"GENERATE_SINGLE_CHAPTER".equals(task.getTaskType())) {
                    log.trace("任务类型不匹配 ({} != GENERATE_SINGLE_CHAPTER)，ContinueWritingStateAggregator 跳过处理: {}", task.getTaskType(), taskId);
                    return Mono.empty();
                }
                
                String parentTaskId = task.getParentTaskId();
                if (parentTaskId == null) {
                    log.info("任务 {} 不是子任务，无需聚合状态。", taskId);
                    return Mono.empty();
                }
                
                // 获取父任务
                return taskStateService.getTask(parentTaskId)
                        .flatMap(parentTask -> updateParentProgress(parentTask, task, eventObject, success, finalFailedEvent));
            })
            .subscribe(
                null,
                error -> log.error("处理 GenerateSingleChapterTask 事件时发生错误 (任务ID: {}): {}", taskId, error.getMessage(), error)
            );
    }
    
    private Mono<Void> updateParentProgress(BackgroundTask parentTask, BackgroundTask childTask, Object childEventObject, boolean success, TaskFailedEvent failedEvent) {
        String parentTaskId = parentTask.getId();
        String childTaskId = childTask.getId();
        String errorMessage = null;
        Object childResult = null;
        
        if(success && childEventObject instanceof TaskCompletedEvent) {
             childResult = ((TaskCompletedEvent) childEventObject).getResult();
        } else if (!success && failedEvent != null) {
             errorMessage = failedEvent.getErrorInfo() != null ? failedEvent.getErrorInfo().toString() : "未知错误";
        }
        
        // --- 获取并更新进度 --- 
        ContinueWritingContentProgress currentProgress = getOrCreateProgress(parentTask);
        int chapterIndex = -1; // Get chapter index from child result or params
        
        if (success && childResult instanceof GenerateSingleChapterResult) {
            GenerateSingleChapterResult singleChapterResult = (GenerateSingleChapterResult) childResult;
            chapterIndex = singleChapterResult.getChapterIndex();
            if (success && singleChapterResult.isContentGenerated()) { // Only count fully completed chapters towards completed count
                 currentProgress.getCompletedChapterIds().add(singleChapterResult.getGeneratedChapterId());
            } else if (!success) {
                 currentProgress.setLastError("章节 " + chapterIndex + " 失败: " + errorMessage);
            }
        } else if (childTask.getParameters() instanceof Map) {
             // Fallback: Try getting index from parameters if result is Map or null on failure
             try {
                  Map<String, Object> paramsMap = (Map<String, Object>) childTask.getParameters();
                  if (paramsMap.containsKey("chapterIndex")) {
                       chapterIndex = ((Number) paramsMap.get("chapterIndex")).intValue();
                  } 
             } catch (Exception e) {
                  log.warn("无法从子任务参数中获取 chapterIndex: {}", childTaskId, e);
             }
             if (!success) {
                  currentProgress.setLastError("章节 " + (chapterIndex > 0 ? chapterIndex : "?") + " 失败: " + errorMessage);
             }
        } else {
             log.warn("无法确定子任务 {} 的章节索引。", childTaskId);
             if (!success) {
                   currentProgress.setLastError("未知章节失败: " + errorMessage);
             }
        }
        
        if (success) {
            currentProgress.setChaptersCompleted(currentProgress.getChaptersCompleted() + 1);
        } else {
            currentProgress.setFailedChapters(currentProgress.getFailedChapters() + 1);
        }
        int processedCount = currentProgress.getChaptersCompleted() + currentProgress.getFailedChapters();
        currentProgress.setCurrentStep(determineNextStep(processedCount, currentProgress.getTotalChapters(), chapterIndex, success));
        
        log.info("更新父任务 {} 进度: 完成={}, 失败={}, 总计={}, 下一步={}",
                parentTaskId, currentProgress.getChaptersCompleted(), currentProgress.getFailedChapters(),
                currentProgress.getTotalChapters(), currentProgress.getCurrentStep());
        
        // --- 检查父任务是否完成 --- 
        boolean isParentTaskComplete = processedCount >= currentProgress.getTotalChapters();
        
        // --- 更新进度并可能结束父任务 --- 
        Mono<Void> progressUpdateMono = taskStateService.recordProgress(parentTaskId, currentProgress);
        
        if (isParentTaskComplete) {
            log.info("父任务 {} 所有子任务已处理 ({} / {})。正在结束任务...",
                    parentTaskId, processedCount, currentProgress.getTotalChapters());
            return progressUpdateMono.then(completeParentTask(parentTask, currentProgress));
        } else {
            return progressUpdateMono;
        }
    }
    
    private ContinueWritingContentProgress getOrCreateProgress(BackgroundTask parentTask) {
        Object progressObj = parentTask.getProgress();
        if (progressObj instanceof ContinueWritingContentProgress) {
            return (ContinueWritingContentProgress) progressObj;
        } else {
            log.warn("父任务 {} 进度丢失或类型错误，重新创建。参数: {}", parentTask.getId(), parentTask.getParameters());
            ContinueWritingContentProgress newProgress = new ContinueWritingContentProgress();
            if (parentTask.getParameters() instanceof ContinueWritingContentParameters) {
                 newProgress.setTotalChapters(((ContinueWritingContentParameters) parentTask.getParameters()).getNumberOfChapters());
            } else {
                 newProgress.setTotalChapters(0); // Or try to infer from somewhere else
            }
            newProgress.setChaptersCompleted(0);
            newProgress.setFailedChapters(0);
            newProgress.setCurrentStep("RECOVERING");
            return newProgress;
        }
    }
    
    private String determineNextStep(int processedCount, int totalChapters, int lastChapterIndex, boolean lastSuccess) {
         if (processedCount >= totalChapters) {
              return "FINISHED";
         } else if (lastChapterIndex > 0) {
             // Assuming the next step is triggered by the child task itself
             // This state primarily reflects the *last completed* step
             return (lastSuccess ? "COMPLETED_CHAPTER_" : "FAILED_CHAPTER_") + lastChapterIndex;
         } else {
             return "PROCESSING_CHAPTER_" + (processedCount + 1);
         }
    }
    
    private Mono<Void> completeParentTask(BackgroundTask parentTask, ContinueWritingContentProgress finalProgress) {
        String taskId = parentTask.getId();
        TaskStatus finalStatus;
        int successCount = finalProgress.getChaptersCompleted(); // Assuming completed means summary+content generated
        int failedCount = finalProgress.getFailedChapters();
        int summariesGeneratedApproximation = successCount + failedCount; // Approximation, as failure might happen after summary
        
        if (failedCount == 0) {
            finalStatus = TaskStatus.COMPLETED;
        } else if (successCount == 0) {
            finalStatus = TaskStatus.FAILED;
        } else {
            finalStatus = TaskStatus.COMPLETED_WITH_ERRORS;
        }
        
        ContinueWritingContentResult result = ContinueWritingContentResult.builder()
                .newChapterIds(finalProgress.getCompletedChapterIds()) // Use IDs collected during progress
                .summariesGeneratedCount(summariesGeneratedApproximation) // Approximation
                .contentGeneratedCount(successCount)
                .failedChaptersCount(failedCount)
                .status(finalStatus)
                .lastErrorMessage(finalProgress.getLastError())
                .build();
        
        log.info("完成父任务 {}: 状态={}, 结果章节数={}", taskId, finalStatus, result.getNewChapterIds().size());
        
        if (finalStatus == TaskStatus.FAILED) {
            String errorMsg = finalProgress.getLastError() != null ? finalProgress.getLastError() : "续写任务失败";
            java.util.Map<String, Object> errorInfo = new java.util.HashMap<>();
            errorInfo.put("message", errorMsg);
            // 先持久化，再发布事件（以保证状态接口可见）
            return taskStateService.recordFailure(taskId, errorInfo, true)
                .doOnSuccess(v -> {
                    try {
                        eventPublisher.publishEvent(new com.ainovel.server.task.event.internal.TaskFailedEvent(
                            this, taskId, parentTask.getTaskType(), parentTask.getUserId(), errorInfo, true));
                    } catch (Throwable ex) {
                        log.warn("发布父任务失败事件出错: taskId={} error={}", taskId, ex.toString());
                    }
                });
        } else {
            // 完成：先持久化，再发布 Completed 事件
            return taskStateService.recordCompletion(taskId, result)
                .doOnSuccess(v -> {
                    try {
                        eventPublisher.publishEvent(new com.ainovel.server.task.event.internal.TaskCompletedEvent(
                            this, taskId, parentTask.getTaskType(), parentTask.getUserId(), result));
                    } catch (Throwable ex) {
                        log.warn("发布父任务完成事件出错: taskId={} error={}", taskId, ex.toString());
                    }
                });
        }
    }
    
    /**
     * 检查并标记事件处理状态，确保幂等性
     */
    private boolean checkAndMarkEventProcessed(String eventId) {
        if (eventId == null) {
            log.warn("事件 ID 为 null，无法进行幂等性检查。");
            return false; // Or throw an error? Treat as already processed to be safe?
        }
        return processedEventIds.putIfAbsent(eventId, Boolean.TRUE) == null;
    }
} 