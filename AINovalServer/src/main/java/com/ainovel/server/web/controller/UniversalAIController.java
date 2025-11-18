package com.ainovel.server.web.controller;

import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.web.dto.response.UniversalAIResponseDto;
import com.ainovel.server.web.dto.response.UniversalAIPreviewResponseDto;
import com.ainovel.server.service.UniversalAIService;
import com.ainovel.server.service.CostEstimationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import jakarta.validation.Valid;
import org.apache.skywalking.apm.toolkit.trace.Trace;


import java.time.Duration;
import java.util.UUID;

/**
 * 通用AI请求控制器
 * 支持多种类型的AI请求：聊天、扩写、总结、重构等
 */
@RestController
@RequestMapping("/api/v1/ai/universal")
@CrossOrigin(origins = "*")
public class UniversalAIController {

    private static final Logger logger = LoggerFactory.getLogger(UniversalAIController.class);
    private static final String SSE_EVENT_NAME = "message";

    @Autowired
    private UniversalAIService universalAIService;

    @Autowired
    private CostEstimationService costEstimationService;

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * 发送通用AI请求（非流式）
     *
     * @param request AI请求数据传输对象
     * @return 完整的AI响应
     */
    @Trace(operationName = "ai.universal.request")
    @PostMapping("/request")
    public Mono<ResponseEntity<UniversalAIResponseDto>> sendRequest(
            @Valid @RequestBody UniversalAIRequestDto request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        // 注入当前用户ID（若请求未显式携带）
        try {
            if ((request.getUserId() == null || request.getUserId().isBlank()) && currentUser != null && currentUser.getId() != null) {
                request.setUserId(currentUser.getId());
            }
        } catch (Exception ignore) {}

        logger.info("收到通用AI请求 - 类型: {}, 用户ID: {}, 模型配置: {}, 小说ID: {}", 
                   request.getRequestType(), request.getUserId(), 
                   request.getModelConfigId(), request.getNovelId());

        return universalAIService.processRequest(request)
                .map(ResponseEntity::ok)
                .doOnSuccess(result -> logger.info("通用AI请求完成 - 类型: {}", request.getRequestType()))
                .doOnError(error -> logger.error("通用AI请求失败 - 类型: {}, 错误: {}", 
                                                request.getRequestType(), error.getMessage()));
    }

    /**
     * [新增] 快速预估通用AI请求的积分成本
     *
     * @param request AI请求数据，至少包含requestType、provider和modelId
     * @return 预估的积分成本
     */
    @Trace(operationName = "ai.universal.estimate-cost")
    @PostMapping("/estimate-cost")
    public Mono<ResponseEntity<CostEstimationService.CostEstimationResponse>> estimateCost(
            @Valid @RequestBody UniversalAIRequestDto request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        try {
            if ((request.getUserId() == null || request.getUserId().isBlank()) && currentUser != null && currentUser.getId() != null) {
                request.setUserId(currentUser.getId());
            }
        } catch (Exception ignore) {}

        logger.info("收到快速积分预估请求 - 类型: {}, 用户ID: {}", 
                   request.getRequestType(), request.getUserId());

        return costEstimationService.estimateCost(request)
                .map(ResponseEntity::ok)
                .doOnSuccess(result -> {
                    if (result.getBody().isSuccess()) {
                        logger.info("快速积分预估完成 - 类型: {}, 预估成本: {} 积分", 
                                  request.getRequestType(), result.getBody().getEstimatedCost());
                    } else {
                        logger.warn("快速积分预估失败 - 类型: {}, 错误: {}", 
                                  request.getRequestType(), result.getBody().getErrorMessage());
                    }
                })
                .doOnError(error -> logger.error("快速积分预估失败 - 类型: {}, 错误: {}", 
                                                request.getRequestType(), error.getMessage()));
    }

    /**
     * 发送通用AI请求（流式）
     *
     * @param request AI请求数据传输对象
     * @return 流式AI响应
     */
    @Trace(operationName = "ai.universal.stream")
    @PostMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<String>> streamRequest(
            @Valid @RequestBody UniversalAIRequestDto request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        try {
            if ((request.getUserId() == null || request.getUserId().isBlank()) && currentUser != null && currentUser.getId() != null) {
                request.setUserId(currentUser.getId());
            }
        } catch (Exception ignore) {}

        logger.info("收到流式通用AI请求 - 类型: {}, 用户ID: {}, 模型配置: {}, 小说ID: {}", 
                   request.getRequestType(), request.getUserId(), 
                   request.getModelConfigId(), request.getNovelId());

        return universalAIService.processStreamRequest(request)
                .map(response -> {
                    try {
                        String jsonResponse = objectMapper.writeValueAsString(response);
                        return ServerSentEvent.<String>builder()
                                .id(UUID.randomUUID().toString())
                                .event(SSE_EVENT_NAME)
                                .data(jsonResponse)
                                .build();
                    } catch (Exception e) {
                        logger.error("序列化响应失败", e);
                        return ServerSentEvent.<String>builder()
                                .id(UUID.randomUUID().toString())
                                .event(SSE_EVENT_NAME)
                                .data("{\"error\":\"序列化失败\"}")
                                .build();
                    }
                })
                .delayElements(Duration.ofMillis(50)) // 控制发送频率
                .concatWith(Mono.just(ServerSentEvent.<String>builder()
                        .id(UUID.randomUUID().toString())
                        .event("complete")
                        .data("{\"data\":\"[DONE]\"}")
                        .build()))
                .onErrorResume(error -> {
                    logger.error("流式响应失败 - 类型: {}, 错误: {}",
                            request.getRequestType(), error.getMessage(), error);
                    try {
                        // 将余额不足等计费错误显式映射为 PAYMENT_REQUIRED，前端可精准识别
                        String code = (error.getMessage() != null && error.getMessage().contains("积分余额不足"))
                                ? "PAYMENT_REQUIRED" : "INTERNAL_SERVER_ERROR";
                        String errJson = objectMapper.writeValueAsString(
                                new com.ainovel.server.web.dto.ErrorResponse(code, error.getMessage())
                        );
                        return Flux.just(
                                ServerSentEvent.<String>builder()
                                        .id(UUID.randomUUID().toString())
                                        .event(SSE_EVENT_NAME)
                                        .data(errJson)
                                        .build(),
                                ServerSentEvent.<String>builder()
                                        .id(UUID.randomUUID().toString())
                                        .event("complete")
                                        .data("{\"data\":\"[DONE]\",\"hasError\":true}")
                                        .build()
                        );
                    } catch (Exception ex) {
                        // 兜底：无法序列化错误时，仍然返回简单的错误字符串
                        String fallback = String.format("{\"code\":\"INTERNAL_SERVER_ERROR\",\"message\":\"%s\"}", error.getMessage());
                        return Flux.just(
                                ServerSentEvent.<String>builder()
                                        .id(UUID.randomUUID().toString())
                                        .event(SSE_EVENT_NAME)
                                        .data(fallback)
                                        .build(),
                                ServerSentEvent.<String>builder()
                                        .id(UUID.randomUUID().toString())
                                        .event("complete")
                                        .data("{\"data\":\"[DONE]\",\"hasError\":true}")
                                        .build()
                        );
                    }
                })
                .doOnSubscribe(subscription -> logger.info("开始流式响应 - 类型: {}", request.getRequestType()))
                .doOnComplete(() -> logger.info("流式响应完成 - 类型: {}", request.getRequestType()))
                .doOnError(error -> logger.error("流式响应失败 - 类型: {}, 错误: {}", 
                                                request.getRequestType(), error.getMessage()));
    }

    /**
     * 预览AI请求（构建提示词但不发送给AI）
     *
     * @param request AI请求数据传输对象
     * @return 预览响应
     */
    @Trace(operationName = "ai.universal.preview")
    @PostMapping("/preview")
    public Mono<ResponseEntity<UniversalAIPreviewResponseDto>> previewRequest(
            @Valid @RequestBody UniversalAIRequestDto request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        try {
            if ((request.getUserId() == null || request.getUserId().isBlank()) && currentUser != null && currentUser.getId() != null) {
                request.setUserId(currentUser.getId());
            }
        } catch (Exception ignore) {}

        logger.info("收到AI预览请求 - 类型: {}, 用户ID: {}", 
                   request.getRequestType(), request.getUserId());

        return universalAIService.previewRequest(request)
                .map(ResponseEntity::ok)
                .doOnSuccess(result -> logger.info("AI预览完成 - 类型: {}", request.getRequestType()))
                .doOnError(error -> logger.error("AI预览失败 - 类型: {}, 错误: {}", 
                                                request.getRequestType(), error.getMessage()));
    }
} 