package com.ainovel.server.web.controller;

import com.ainovel.server.security.CurrentUser;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentParameters;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.web.dto.TaskSubmissionResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;
import reactor.core.publisher.Mono;

/**
 * 自动续写小说章节内容任务控制器
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/api/tasks")
@RequiredArgsConstructor
public class TaskContinueWritingController {

    private final TaskSubmissionService taskSubmissionService;

    /**
     * 提交自动续写小说章节内容任务
     * 
     * @param currentUser 当前用户
     * @param request 请求参数
     * @return 任务提交响应的Mono
     */
    @PostMapping("/continue-writing")
    public Mono<ResponseEntity<TaskSubmissionResponse>> submitContinueWritingTask(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody ContinueWritingContentParameters request) {
        
        log.info("用户 {} 提交自动续写小说章节内容任务, 小说ID: {}, 章节数量: {}, 摘要AI配置: {}, 内容AI配置: {}, 上下文模式: {}, 公共模型(摘要/内容): {}/{}", 
                currentUser.getId(), request.getNovelId(), request.getNumberOfChapters(),
                request.getAiConfigIdSummary(), request.getAiConfigIdContent(), 
                request.getStartContextMode(), request.getSummaryPublicModelConfigId(), request.getContentPublicModelConfigId());
        
        // 自定义验证模型配置
        try {
            request.validate();
        } catch (IllegalArgumentException e) {
            log.warn("续写任务参数验证失败: {}", e.getMessage());
            TaskSubmissionResponse errorResponse = new TaskSubmissionResponse(null);
            return Mono.just(ResponseEntity.badRequest().body(errorResponse));
        }
        
        // 提交任务
        return taskSubmissionService.submitTask(
                currentUser.getId(),
                "CONTINUE_WRITING_CONTENT",
                request,
                null // 父任务ID为null
            )
            .map(taskId -> ResponseEntity.accepted().body(new TaskSubmissionResponse(taskId)))
            .onErrorResume(e -> {
                log.error("提交自动续写小说章节内容任务失败", e);
                TaskSubmissionResponse errorResponse = new TaskSubmissionResponse(null); 
                return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse));
            });
    }
} 