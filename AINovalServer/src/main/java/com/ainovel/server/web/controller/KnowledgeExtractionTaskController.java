package com.ainovel.server.web.controller;

import com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.service.KnowledgeExtractionTaskService;
import com.ainovel.server.common.response.ApiResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;

/**
 * AI拆书任务管理Controller
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/knowledge-extraction-tasks")
@RequiredArgsConstructor
public class KnowledgeExtractionTaskController {
    
    private final KnowledgeExtractionTaskService taskService;
    
    /**
     * 获取任务列表
     * 
     * @param status 任务状态（可选）
     * @param page 页码（从0开始）
     * @param size 每页大小
     * 
     * 管理员：返回所有任务
     * 普通用户：返回该用户的任务
     */
    @GetMapping
    public Mono<ApiResponse<Map<String, Object>>> getTaskList(
            Authentication authentication,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员（检查用户角色）
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        log.info("查询任务列表: userId={}, roles={}, isAdmin={}, status={}, page={}, size={}", 
                userId, user.getRoles(), isAdmin, status, page, size);
        
        KnowledgeExtractionTaskRecord.TaskStatus taskStatus = null;
        if (status != null && !status.isEmpty()) {
            try {
                taskStatus = KnowledgeExtractionTaskRecord.TaskStatus.valueOf(status.toUpperCase());
            } catch (IllegalArgumentException e) {
                return Mono.just(ApiResponse.error("无效的任务状态: " + status));
            }
        }
        
        KnowledgeExtractionTaskRecord.TaskStatus finalTaskStatus = taskStatus;
        
        // ✅ 管理员查询所有任务，普通用户只查询自己的任务
        if (isAdmin) {
            return taskService.getAllTasks(finalTaskStatus, page, size)
                    .collectList()
                    .zipWith(taskService.countAllTasks(finalTaskStatus))
                    .map(tuple -> {
                        Map<String, Object> result = new HashMap<>();
                        result.put("tasks", tuple.getT1());
                        result.put("total", tuple.getT2());
                        result.put("page", page);
                        result.put("size", size);
                        result.put("totalPages", (tuple.getT2() + size - 1) / size);
                        
                        log.info("✅ 管理员查询所有任务成功: status={}, 任务数量={}, 总数={}", 
                                status, tuple.getT1().size(), tuple.getT2());
                        
                        return ApiResponse.success(result);
                    })
                    .doOnError(e -> log.error("获取所有任务列表失败: error={}", e.getMessage()));
        } else {
            return taskService.getUserTasks(userId, finalTaskStatus, page, size)
                    .collectList()
                    .zipWith(taskService.countUserTasks(userId, finalTaskStatus))
                    .map(tuple -> {
                        Map<String, Object> result = new HashMap<>();
                        result.put("tasks", tuple.getT1());
                        result.put("total", tuple.getT2());
                        result.put("page", page);
                        result.put("size", size);
                        result.put("totalPages", (tuple.getT2() + size - 1) / size);
                        
                        log.info("✅ 用户查询任务成功: userId={}, status={}, 任务数量={}, 总数={}", 
                                userId, status, tuple.getT1().size(), tuple.getT2());
                        
                        return ApiResponse.success(result);
                    })
                    .doOnError(e -> log.error("获取任务列表失败: userId={}, error={}", userId, e.getMessage()));
        }
    }
    
    /**
     * 获取任务详情
     */
    @GetMapping("/{taskId}")
    public Mono<ApiResponse<KnowledgeExtractionTaskRecord>> getTaskDetail(
            Authentication authentication,
            @PathVariable String taskId) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        return taskService.getTaskDetail(taskId)
                .flatMap(task -> {
                    // ✅ 管理员可以查看所有任务，普通用户只能查看自己的任务
                    if (!isAdmin && !task.getUserId().equals(userId)) {
                        log.warn("用户 {} 尝试查看其他用户的任务: taskId={}, taskUserId={}", 
                                userId, taskId, task.getUserId());
                        return Mono.just(ApiResponse.<KnowledgeExtractionTaskRecord>error("无权限查看此任务"));
                    }
                    
                    log.info("查看任务详情: taskId={}, userId={}, isAdmin={}", taskId, userId, isAdmin);
                    return Mono.just(ApiResponse.success(task));
                })
                .switchIfEmpty(Mono.just(ApiResponse.error("任务不存在")))
                .doOnError(e -> log.error("获取任务详情失败: taskId={}, error={}", taskId, e.getMessage()));
    }
    
    /**
     * 重试失败的任务
     */
    @PostMapping("/{taskId}/retry")
    public Mono<ApiResponse<Map<String, String>>> retryTask(
            Authentication authentication,
            @PathVariable String taskId) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        return taskService.retryFailedTask(taskId, userId, isAdmin)
                .map(newTaskId -> {
                    Map<String, String> result = new HashMap<>();
                    result.put("originalTaskId", taskId);
                    result.put("newTaskId", newTaskId);
                    result.put("message", "任务已重新提交");
                    
                    log.info("任务重试成功: taskId={}, userId={}, isAdmin={}, newTaskId={}", 
                            taskId, userId, isAdmin, newTaskId);
                    return ApiResponse.success(result);
                })
                .onErrorResume(e -> {
                    log.error("重试任务失败: taskId={}, userId={}, error={}", taskId, userId, e.getMessage());
                    return Mono.just(ApiResponse.error("重试失败: " + e.getMessage()));
                });
    }
    
    /**
     * 重试失败的子任务
     */
    @PostMapping("/{taskId}/sub-tasks/{subTaskId}/retry")
    public Mono<ApiResponse<Map<String, String>>> retrySubTask(
            Authentication authentication,
            @PathVariable String taskId,
            @PathVariable String subTaskId) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        return taskService.retryFailedSubTask(taskId, subTaskId, userId, isAdmin)
                .map(newSubTaskId -> {
                    Map<String, String> result = new HashMap<>();
                    result.put("taskId", taskId);
                    result.put("originalSubTaskId", subTaskId);
                    result.put("newSubTaskId", newSubTaskId);
                    result.put("message", "子任务已重新提交");
                    
                    return ApiResponse.success(result);
                })
                .onErrorResume(e -> {
                    log.error("重试子任务失败: taskId={}, subTaskId={}, error={}", 
                            taskId, subTaskId, e.getMessage());
                    return Mono.just(ApiResponse.error("重试失败: " + e.getMessage()));
                });
    }
    
    /**
     * 获取任务统计信息
     * 
     * 管理员：返回所有任务的统计
     * 普通用户：返回该用户任务的统计
     */
    @GetMapping("/statistics")
    public Mono<ApiResponse<Map<String, Object>>> getStatistics(
            Authentication authentication) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员（检查用户角色）
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        log.info("查询统计信息: userId={}, roles={}, isAdmin={}", userId, user.getRoles(), isAdmin);
        
        // ✅ 管理员查询所有任务统计，普通用户只查询自己的统计
        if (isAdmin) {
            Mono<Long> totalMono = taskService.countAllTasks(null);
            Mono<Long> completedMono = taskService.countAllTasks(
                    KnowledgeExtractionTaskRecord.TaskStatus.COMPLETED);
            Mono<Long> failedMono = taskService.countAllTasks(
                    KnowledgeExtractionTaskRecord.TaskStatus.FAILED);
            Mono<Long> runningMono = taskService.countAllTasks(
                    KnowledgeExtractionTaskRecord.TaskStatus.EXTRACTING);
            
            return Mono.zip(totalMono, completedMono, failedMono, runningMono)
                    .flatMap(tuple -> {
                        Map<String, Object> stats = new HashMap<>();
                        stats.put("total", tuple.getT1());
                        stats.put("completed", tuple.getT2());
                        stats.put("failed", tuple.getT3());
                        stats.put("running", tuple.getT4());
                        stats.put("queued", tuple.getT1() - tuple.getT2() - tuple.getT3() - tuple.getT4());
                        
                        // 获取所有失败原因统计
                        return taskService.getAllFailureStatistics()
                                .map(failureStats -> {
                                    stats.put("failureDetails", failureStats);
                                    log.info("✅ 管理员统计信息: total={}, completed={}, failed={}, running={}", 
                                            tuple.getT1(), tuple.getT2(), tuple.getT3(), tuple.getT4());
                                    return ApiResponse.success(stats);
                                });
                    })
                    .doOnError(e -> log.error("获取统计信息失败: error={}", e.getMessage()));
        } else {
            Mono<Long> totalMono = taskService.countUserTasks(userId, null);
            Mono<Long> completedMono = taskService.countUserTasks(userId, 
                    KnowledgeExtractionTaskRecord.TaskStatus.COMPLETED);
            Mono<Long> failedMono = taskService.countUserTasks(userId, 
                    KnowledgeExtractionTaskRecord.TaskStatus.FAILED);
            Mono<Long> runningMono = taskService.countUserTasks(userId, 
                    KnowledgeExtractionTaskRecord.TaskStatus.EXTRACTING);
            
            return Mono.zip(totalMono, completedMono, failedMono, runningMono)
                    .flatMap(tuple -> {
                        Map<String, Object> stats = new HashMap<>();
                        stats.put("total", tuple.getT1());
                        stats.put("completed", tuple.getT2());
                        stats.put("failed", tuple.getT3());
                        stats.put("running", tuple.getT4());
                        stats.put("queued", tuple.getT1() - tuple.getT2() - tuple.getT3() - tuple.getT4());
                        
                        // 获取失败原因统计
                        return taskService.getFailureStatistics(userId)
                                .map(failureStats -> {
                                    stats.put("failureDetails", failureStats);
                                    return ApiResponse.success(stats);
                                });
                    })
                    .doOnError(e -> log.error("获取统计信息失败: userId={}, error={}", userId, e.getMessage()));
        }
    }
    
    /**
     * 批量重试失败任务
     */
    @PostMapping("/batch-retry")
    public Mono<ApiResponse<Map<String, Object>>> batchRetry(
            Authentication authentication,
            @RequestBody Map<String, Object> request) {
        
        // ✅ 正确获取用户信息
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        
        // ✅ 判断是否为管理员
        boolean isAdmin = user.getRoles() != null && user.getRoles().stream()
                .anyMatch(role -> role.toUpperCase().contains("ADMIN"));
        
        @SuppressWarnings("unchecked")
        java.util.List<String> taskIds = (java.util.List<String>) request.get("taskIds");
        
        if (taskIds == null || taskIds.isEmpty()) {
            return Mono.just(ApiResponse.error("taskIds不能为空"));
        }
        
        return reactor.core.publisher.Flux.fromIterable(taskIds)
                .flatMap(taskId -> taskService.retryFailedTask(taskId, userId, isAdmin)
                        .map(newTaskId -> Map.of("taskId", taskId, "newTaskId", newTaskId, "success", true))
                        .onErrorResume(e -> Mono.just(Map.of(
                                "taskId", taskId, 
                                "success", false, 
                                "error", e.getMessage()))))
                .collectList()
                .map(results -> {
                    long successCount = results.stream().filter(r -> (Boolean) r.get("success")).count();
                    long failedCount = results.size() - successCount;
                    
                    Map<String, Object> result = new HashMap<>();
                    result.put("total", results.size());
                    result.put("success", successCount);
                    result.put("failed", failedCount);
                    result.put("details", results);
                    
                    return ApiResponse.success(result);
                })
                .doOnError(e -> log.error("批量重试失败: userId={}, error={}", userId, e.getMessage()));
    }
}

