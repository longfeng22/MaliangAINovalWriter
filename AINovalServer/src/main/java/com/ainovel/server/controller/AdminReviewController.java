package com.ainovel.server.controller;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.domain.model.ReviewStatusConstants;
import com.ainovel.server.service.AdminPromptTemplateService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 统一审核管理控制器
 * 整合策略、提示词等多种类型的审核
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/admin/reviews")
@PreAuthorize("hasRole('ADMIN')")
@Tag(name = "管理员审核管理", description = "统一的审核管理接口，支持策略、提示词等多种类型")
public class AdminReviewController {

    @Autowired
    private AdminPromptTemplateService adminTemplateService;
    
    @Autowired
    private com.ainovel.server.repository.EnhancedUserPromptTemplateRepository templateRepository;
    
    // ==================== 常量定义 ====================
    
    /**
     * 审核决策：批准
     */
    private static final String DECISION_APPROVED = "APPROVED";
    
    /**
     * 审核决策：拒绝
     */
    private static final String DECISION_REJECTED = "REJECTED";

    /**
     * 获取审核项列表
     */
    @GetMapping
    @Operation(summary = "获取审核项列表", description = "根据类型、状态等条件查询审核项")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getReviewItems(
            @Parameter(description = "审核类型") @RequestParam(required = false) String type,
            @Parameter(description = "审核状态") @RequestParam(required = false) String status,
            @Parameter(description = "功能类型") @RequestParam(required = false) String featureType,
            @Parameter(description = "关键词") @RequestParam(required = false) String keyword,
            @Parameter(description = "开始日期") @RequestParam(required = false) String startDate,
            @Parameter(description = "结束日期") @RequestParam(required = false) String endDate,
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页大小") @RequestParam(defaultValue = "20") int size,
            @Parameter(description = "排序字段") @RequestParam(defaultValue = "submittedAt") String sortBy,
            @Parameter(description = "排序方向") @RequestParam(defaultValue = "desc") String sortDir) {
        
        log.info("📋 获取审核项列表: type={}, status={}, featureType={}, page={}, size={}", type, status, featureType, page, size);

        try {
            // 🔧 修复：统一查询所有 reviewStatus=PENDING 的模板，不区分类型
            // 分享模板时只设置 reviewStatus，审核列表也应该只按 reviewStatus 查询
            Flux<ReviewItemDto> items = getAllReviewItems(status, featureType);

            return items
                    .collectList()
                    .map(reviewItems -> {
                        // 排序
                        List<ReviewItemDto> sortedItems = sortReviewItems(reviewItems, sortBy, sortDir);
                        
                        // 分页
                        int start = Math.min(page * size, sortedItems.size());
                        int end = Math.min(start + size, sortedItems.size());
                        List<ReviewItemDto> pagedItems = sortedItems.subList(start, end);
                        
                        Map<String, Object> result = new HashMap<>();
                        result.put("data", pagedItems);
                        result.put("totalElements", sortedItems.size());
                        result.put("totalPages", (sortedItems.size() + size - 1) / size);
                        result.put("currentPage", page);
                        result.put("pageSize", size);
                        
                        return ResponseEntity.ok(ApiResponse.success(result));
                    })
                    .onErrorResume(error -> {
                        log.error("❌ 获取审核项列表失败", error);
                        return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                                .body(ApiResponse.error("FETCH_FAILED", "获取审核项列表失败: " + error.getMessage())));
                    });
        } catch (Exception e) {
            log.error("❌ 获取审核项列表异常", e);
            return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("INTERNAL_ERROR", "服务器内部错误")));
        }
    }

    /**
     * 获取审核统计
     */
    @GetMapping("/statistics")
    @Operation(summary = "获取审核统计", description = "获取各类审核项的统计信息")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getReviewStatistics(
            @Parameter(description = "审核类型") @RequestParam(required = false) String type,
            @Parameter(description = "开始日期") @RequestParam(required = false) String startDate,
            @Parameter(description = "结束日期") @RequestParam(required = false) String endDate) {
        
        log.info("📊 获取审核统计: type={}", type);

        try {
            // 获取策略统计
            Mono<Map<String, Long>> strategyStats = getStrategyStatistics();
            
            // 获取模板统计
            Mono<Map<String, Long>> templateStats = getTemplateStatistics();
            
            return Mono.zip(strategyStats, templateStats)
                    .map(tuple -> {
                        Map<String, Long> sStats = tuple.getT1();
                        Map<String, Long> tStats = tuple.getT2();
                        
                        Map<String, Object> result = new HashMap<>();
                        result.put("totalPending", sStats.getOrDefault("pending", 0L) + tStats.getOrDefault("pending", 0L));
                        result.put("totalApproved", sStats.getOrDefault("approved", 0L) + tStats.getOrDefault("approved", 0L));
                        result.put("totalRejected", sStats.getOrDefault("rejected", 0L) + tStats.getOrDefault("rejected", 0L));
                        result.put("strategyPending", sStats.getOrDefault("pending", 0L));
                        result.put("templatePending", tStats.getOrDefault("pending", 0L));
                        
                        return ResponseEntity.ok(ApiResponse.success(result));
                    })
                    .onErrorResume(error -> {
                        log.error("❌ 获取审核统计失败", error);
                        Map<String, Object> emptyStats = new HashMap<>();
                        emptyStats.put("totalPending", 0);
                        emptyStats.put("totalApproved", 0);
                        emptyStats.put("totalRejected", 0);
                        return Mono.just(ResponseEntity.ok(ApiResponse.success(emptyStats)));
                    });
        } catch (Exception e) {
            log.error("❌ 获取审核统计异常", e);
            Map<String, Object> emptyStats = new HashMap<>();
            emptyStats.put("totalPending", 0);
            emptyStats.put("totalApproved", 0);
            emptyStats.put("totalRejected", 0);
            return Mono.just(ResponseEntity.ok(ApiResponse.success(emptyStats)));
        }
    }

    /**
     * 获取审核项详情
     */
    @GetMapping("/{itemId}")
    @Operation(summary = "获取审核项详情", description = "获取指定审核项的详细信息")
    public Mono<ResponseEntity<ApiResponse<ReviewItemDto>>> getReviewItemDetail(
            @PathVariable String itemId,
            @Parameter(description = "审核类型") @RequestParam String type) {
        
        log.info("📝 获取审核项详情: id={}, type={}", itemId, type);

        // 🔧 简化：统一从数据库查询，不再区分类型
        return templateRepository.findById(itemId)
                .map(template -> {
                    // 根据 featureType 判断类型标签
                    String typeLabel = com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION.equals(template.getFeatureType()) 
                        ? "STRATEGY" 
                        : "ENHANCED_TEMPLATE";
                    ReviewItemDto dto = mapTemplateToReviewItem(template, typeLabel);
                    return ResponseEntity.ok(ApiResponse.success(dto));
                })
                .switchIfEmpty(Mono.just(ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(ApiResponse.error("NOT_FOUND", "审核项不存在"))));
    }

    /**
     * 审核项目
     */
    @PostMapping("/{itemId}/review")
    @Operation(summary = "审核项目", description = "审核指定的项目")
    public Mono<ResponseEntity<ApiResponse<String>>> reviewItem(
            @PathVariable String itemId,
            @Parameter(description = "审核类型") @RequestParam String type,
            @Valid @RequestBody ReviewDecisionRequest decision,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        String adminId = currentUser.getId();
        log.info("✅ 审核项目: id={}, type={}, decision={}", itemId, type, decision.getDecision());

        // 统一使用模板审核接口，不再区分类型
        boolean approved = DECISION_APPROVED.equalsIgnoreCase(decision.getDecision());
        
        return adminTemplateService.reviewUserTemplate(
                        itemId,
                        approved,
                        adminId,
                        decision.getComment())
                .map(template -> ResponseEntity.ok(ApiResponse.success("审核完成")))
                .onErrorResume(error -> Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("REVIEW_FAILED", "审核失败: " + error.getMessage()))));
    }

    /**
     * 批量审核
     */
    @PostMapping("/batch")
    @Operation(summary = "批量审核", description = "批量审核多个项目")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> batchReview(
            @Valid @RequestBody BatchReviewRequest request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        
        String adminId = currentUser.getId();
        log.info("📦 批量审核: count={}, type={}", request.getItemIds().size(), request.getType());

        // 统一使用批量审核接口，不再区分类型
        boolean approved = DECISION_APPROVED.equalsIgnoreCase(request.getDecision());
        
        return adminTemplateService.batchReviewTemplates(
                        request.getItemIds(),
                        approved,
                        adminId)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .onErrorResume(error -> Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("BATCH_REVIEW_FAILED", "批量审核失败: " + error.getMessage()))));
    }

    // ==================== 辅助方法 ====================

    /**
     * 获取所有审核项（统一查询）
     * 不区分策略和模板，统一按 reviewStatus 查询
     */
    private Flux<ReviewItemDto> getAllReviewItems(String status, String featureType) {
        // 🔧 修复：支持查询所有状态（PENDING, APPROVED, REJECTED, DRAFT）
        log.debug("📋 查询审核项: status={}, featureType={}", status, featureType);
        
        // 根据状态查询不同的数据源
        Flux<EnhancedUserPromptTemplate> templateFlux;
        
        if (status == null || status.isEmpty()) {
            // 如果没有指定状态，查询所有模板
            templateFlux = templateRepository.findAll();
        } else if (ReviewStatusConstants.PENDING.equalsIgnoreCase(status)) {
            // 待审核：使用优化的查询方法
            templateFlux = adminTemplateService.findPendingTemplates();
        } else {
            // 其他状态：查询所有模板，然后按状态过滤
            templateFlux = templateRepository.findAll()
                    .filter(template -> status.equalsIgnoreCase(template.getReviewStatus()));
        }
        
        return templateFlux
                .filter(template -> {
                    // 如果指定了状态，再次确认状态匹配（防御性编程）
                    if (status != null && !status.isEmpty()) {
                        if (!status.equalsIgnoreCase(template.getReviewStatus())) {
                            return false;
                        }
                    }
                    
                    // 按功能类型筛选（如果指定）
                    if (featureType != null && !featureType.isEmpty()) {
                        try {
                            com.ainovel.server.domain.model.AIFeatureType filterType = 
                                com.ainovel.server.domain.model.AIFeatureType.valueOf(featureType);
                            return filterType.equals(template.getFeatureType());
                        } catch (IllegalArgumentException e) {
                            log.warn("⚠️ 无效的功能类型: {}", featureType);
                            return true;
                        }
                    }
                    return true;
                })
                .map(template -> {
                    // 根据 featureType 判断类型标签
                    String typeLabel = com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION.equals(template.getFeatureType()) 
                        ? "STRATEGY" 
                        : "ENHANCED_TEMPLATE";
                    return mapTemplateToReviewItem(template, typeLabel);
                })
                .doOnComplete(() -> log.debug("✅ 审核项查询完成"))
                .onErrorResume(error -> {
                    log.warn("⚠️ 获取审核项失败: {}", error.getMessage());
                    return Flux.empty();
                });
    }

    /**
     * 获取策略统计
     */
    private Mono<Map<String, Long>> getStrategyStatistics() {
        // 🔧 修复：应该查询所有 SETTING_TREE_GENERATION 类型的模板，而不是只查询 PENDING 的
        return templateRepository.findByFeatureType(com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                .collectList()
                .map(templates -> {
                    Map<String, Long> stats = new HashMap<>();
                    long pending = templates.stream()
                            .filter(t -> ReviewStatusConstants.PENDING.equals(t.getReviewStatus()))
                            .count();
                    long approved = templates.stream()
                            .filter(t -> ReviewStatusConstants.APPROVED.equals(t.getReviewStatus()))
                            .count();
                    long rejected = templates.stream()
                            .filter(t -> ReviewStatusConstants.REJECTED.equals(t.getReviewStatus()))
                            .count();
                    stats.put("pending", pending);
                    stats.put("approved", approved);
                    stats.put("rejected", rejected);
                    log.debug("📊 策略统计: pending={}, approved={}, rejected={}", pending, approved, rejected);
                    return stats;
                })
                .onErrorReturn(Collections.singletonMap("pending", 0L));
    }

    /**
     * 获取模板统计
     */
    private Mono<Map<String, Long>> getTemplateStatistics() {
        // 🔧 修复：应该查询所有非 SETTING_TREE_GENERATION 类型的模板，按状态统计
        return templateRepository.findAll()
                .filter(template -> template.getFeatureType() != com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION)
                .collectList()
                .map(templates -> {
                    Map<String, Long> stats = new HashMap<>();
                    long pending = templates.stream()
                            .filter(t -> ReviewStatusConstants.PENDING.equals(t.getReviewStatus()))
                            .count();
                    long approved = templates.stream()
                            .filter(t -> ReviewStatusConstants.APPROVED.equals(t.getReviewStatus()))
                            .count();
                    long rejected = templates.stream()
                            .filter(t -> ReviewStatusConstants.REJECTED.equals(t.getReviewStatus()))
                            .count();
                    stats.put("pending", pending);
                    stats.put("approved", approved);
                    stats.put("rejected", rejected);
                    log.debug("📊 模板统计: pending={}, approved={}, rejected={}", pending, approved, rejected);
                    return stats;
                })
                .onErrorReturn(Collections.singletonMap("pending", 0L));
    }

    /**
     * 映射模板到审核项DTO
     * 统一使用 EnhancedUserPromptTemplate 的 reviewStatus 字段
     */
    private ReviewItemDto mapTemplateToReviewItem(EnhancedUserPromptTemplate template, String type) {
        ReviewItemDto dto = new ReviewItemDto();
        
        // 基本信息
        dto.setId(template.getId() != null ? template.getId() : "");
        dto.setType(type);
        dto.setTitle(template.getName() != null ? template.getName() : "未命名");
        dto.setDescription(template.getDescription() != null ? template.getDescription() : "");
        dto.setAuthorId(template.getAuthorId() != null ? template.getAuthorId() : "");
        dto.setAuthorName(template.getAuthorName() != null ? template.getAuthorName() : "未知用户");
        dto.setFeatureType(template.getFeatureType() != null ? template.getFeatureType().name() : null);
        
        // 审核状态
        dto.setStatus(template.getReviewStatus() != null ? template.getReviewStatus() : ReviewStatusConstants.DRAFT);
        dto.setReviewComment(template.getReviewComment());
        dto.setReviewedAt(template.getReviewedAt());
        dto.setSubmittedAt(template.getSubmittedAt() != null ? template.getSubmittedAt() : 
                          (template.getSharedAt() != null ? template.getSharedAt() : template.getCreatedAt()));
        
        // 时间信息
        dto.setCreatedAt(template.getCreatedAt());
        dto.setUpdatedAt(template.getUpdatedAt());
        
        // 🆕 审核必需字段：提示词内容
        dto.setSystemPrompt(template.getSystemPrompt());
        dto.setUserPrompt(template.getUserPrompt());
        dto.setTags(template.getTags());
        dto.setCategories(template.getCategories());
        dto.setHidePrompts(template.getHidePrompts());
        
        // 🆕 策略配置（如果是策略类型）
        if (com.ainovel.server.domain.model.AIFeatureType.SETTING_TREE_GENERATION.equals(template.getFeatureType())) {
            dto.setSettingGenerationConfig(template.getSettingGenerationConfig());
        }
        
        // 🆕 统计信息
        dto.setUsageCount(template.getUsageCount());
        dto.setFavoriteCount(template.getFavoriteCount());
        dto.setRating(template.getRating());
        
        return dto;
    }

    /**
     * 排序审核项
     */
    private List<ReviewItemDto> sortReviewItems(List<ReviewItemDto> items, String sortBy, String sortDir) {
        Comparator<ReviewItemDto> comparator;
        
        switch (sortBy) {
            case "submittedAt":
                comparator = Comparator.comparing(
                        item -> item.getSubmittedAt() != null ? item.getSubmittedAt() : LocalDateTime.MIN,
                        Comparator.nullsLast(Comparator.naturalOrder()));
                break;
            case "createdAt":
                comparator = Comparator.comparing(
                        item -> item.getCreatedAt() != null ? item.getCreatedAt() : LocalDateTime.MIN,
                        Comparator.nullsLast(Comparator.naturalOrder()));
                break;
            case "title":
                comparator = Comparator.comparing(ReviewItemDto::getTitle, Comparator.nullsLast(String::compareToIgnoreCase));
                break;
            default:
                comparator = Comparator.comparing(
                        item -> item.getSubmittedAt() != null ? item.getSubmittedAt() : LocalDateTime.MIN,
                        Comparator.nullsLast(Comparator.naturalOrder()));
        }
        
        if ("desc".equalsIgnoreCase(sortDir)) {
            comparator = comparator.reversed();
        }
        
        return items.stream()
                .sorted(comparator)
                .collect(Collectors.toList());
    }

    // ==================== DTO类 ====================

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ReviewItemDto {
        private String id;
        private String type;
        private String featureType;  // AI功能类型
        private String title;
        private String description;
        private String authorId;
        private String authorName;
        private String status;
        private String reviewComment;
        private LocalDateTime submittedAt;
        private LocalDateTime reviewedAt;
        private LocalDateTime createdAt;
        private LocalDateTime updatedAt;
        
        // 🆕 审核必需字段
        private String systemPrompt;      // 系统提示词
        private String userPrompt;        // 用户提示词
        private List<String> tags;        // 标签
        private List<String> categories;  // 分类
        private Boolean hidePrompts;      // 是否隐藏提示词
        
        // 🆕 策略相关字段（如果是 SETTING_TREE_GENERATION 类型）
        private Object settingGenerationConfig;  // 策略配置
        
        // 🆕 统计信息
        private Long usageCount;          // 使用次数
        private Long favoriteCount;       // 收藏次数
        private Double rating;            // 评分
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ReviewDecisionRequest {
        private String decision;  // APPROVED, REJECTED, REVISION_REQUIRED
        private String comment;
        private List<String> rejectionReasons;
        private List<String> improvementSuggestions;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class BatchReviewRequest {
        private List<String> itemIds;
        private String type;
        private String decision;
        private String comment;
        private List<String> rejectionReasons;
        private List<String> improvementSuggestions;
    }
}

