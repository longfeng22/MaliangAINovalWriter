package com.ainovel.server.controller;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;

import com.ainovel.server.service.AdminPromptTemplateService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
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
import java.util.List;
import java.util.Map;

/**
 * 管理员提示词模板管理控制器
 * 基于 EnhancedUserPromptTemplate 的统一管理
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/admin/prompt-templates")
@PreAuthorize("hasRole('ADMIN')")
@Tag(name = "管理员模板管理", description = "基于增强用户提示词模板的统一管理")
public class AdminPromptTemplateController {

    @Autowired
    private AdminPromptTemplateService adminTemplateService;

    // ==================== 公共模板查询 ====================

    /**
     * 获取所有公共模板
     */
    @GetMapping("/public")
    @Operation(summary = "获取所有公共模板", description = "获取系统中所有的公共提示词模板")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getAllPublicTemplates(
            @RequestParam(required = false) String featureType) {
        log.info("管理员获取公共模板，功能类型过滤: {}", featureType);
        
        Flux<EnhancedUserPromptTemplate> templates = featureType != null && !featureType.isEmpty()
                ? adminTemplateService.findPublicTemplatesByFeatureType(AIFeatureType.valueOf(featureType))
                : adminTemplateService.findAllPublicTemplates();
                
        return ResponseEntity.ok(templates);
    }

    /**
     * 获取待审核模板
     */
    @GetMapping("/pending")
    @Operation(summary = "获取待审核模板", description = "获取用户提交的待审核模板列表")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getPendingTemplates() {
        log.info("管理员获取待审核模板");
        return ResponseEntity.ok(adminTemplateService.findPendingTemplates());
    }

    /**
     * 获取已验证模板
     */
    @GetMapping("/verified")
    @Operation(summary = "获取已验证模板", description = "获取官方认证的模板列表")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getVerifiedTemplates() {
        log.info("管理员获取已验证模板");
        return ResponseEntity.ok(adminTemplateService.findVerifiedTemplates());
    }

    /**
     * 搜索公共模板
     */
    @GetMapping("/search")
    @Operation(summary = "搜索公共模板", description = "根据关键词、功能类型等条件搜索公共模板")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> searchPublicTemplates(
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String featureType,
            @RequestParam(required = false) Boolean verified,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        log.info("管理员搜索公共模板: 关键词={}, 功能类型={}, 验证状态={}", keyword, featureType, verified);
        
        AIFeatureType feature = featureType != null && !featureType.isEmpty() 
                ? AIFeatureType.valueOf(featureType) : null;
                
        Flux<EnhancedUserPromptTemplate> results = adminTemplateService.searchPublicTemplates(
                keyword, feature, verified, page, size);
                
        return ResponseEntity.ok(results);
    }

    /**
     * 获取热门公共模板
     */
    @GetMapping("/popular")
    @Operation(summary = "获取热门模板", description = "获取使用量和评分最高的公共模板")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getPopularTemplates(
            @RequestParam(required = false) String featureType,
            @RequestParam(defaultValue = "10") int limit) {
        log.info("管理员获取热门模板: 功能类型={}, 限制={}", featureType, limit);
        
        AIFeatureType feature = featureType != null && !featureType.isEmpty() 
                ? AIFeatureType.valueOf(featureType) : null;
                
        Flux<EnhancedUserPromptTemplate> templates = adminTemplateService.getPopularPublicTemplates(feature, limit);
        return ResponseEntity.ok(templates);
    }

    /**
     * 获取最新公共模板
     */
    @GetMapping("/latest")
    @Operation(summary = "获取最新模板", description = "获取最近创建的公共模板")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getLatestTemplates(
            @RequestParam(required = false) String featureType,
            @RequestParam(defaultValue = "10") int limit) {
        log.info("管理员获取最新模板: 功能类型={}, 限制={}", featureType, limit);
        
        AIFeatureType feature = featureType != null && !featureType.isEmpty() 
                ? AIFeatureType.valueOf(featureType) : null;
                
        Flux<EnhancedUserPromptTemplate> templates = adminTemplateService.getLatestPublicTemplates(feature, limit);
        return ResponseEntity.ok(templates);
    }

    /**
     * 获取所有用户模板（包括私有和公共）
     */
    @GetMapping("/all-user")
    @Operation(summary = "获取所有用户模板", description = "分页获取系统中所有用户的模板（包括私有和公共）")
    public ResponseEntity<Flux<EnhancedUserPromptTemplate>> getAllUserTemplates(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String search) {
        log.info("管理员获取所有用户模板: page={}, size={}, search={}", page, size, search);
        
        Flux<EnhancedUserPromptTemplate> templates = adminTemplateService.findAllUserTemplates(page, size, search);
        return ResponseEntity.ok(templates);
    }

    // ==================== 模板创建与更新 ====================

    /**
     * 创建官方模板
     */
    @PostMapping("/official")
    @Operation(summary = "创建官方模板", description = "创建新的官方认证提示词模板")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> createOfficialTemplate(
            @Valid @RequestBody EnhancedUserPromptTemplate template,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 创建官方模板: {}", adminId, template.getName());
        
        return adminTemplateService.createOfficialTemplate(template, adminId)
                .map(savedTemplate -> ResponseEntity.ok(ApiResponse.success(savedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("创建官方模板失败")));
    }

    /**
     * 更新公共模板
     */
    @PutMapping("/{templateId}")
    @Operation(summary = "更新公共模板", description = "更新指定的公共模板信息")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> updatePublicTemplate(
            @PathVariable String templateId,
            @Valid @RequestBody EnhancedUserPromptTemplate template,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 更新公共模板: {}", adminId, templateId);
        
        return adminTemplateService.updatePublicTemplate(templateId, template, adminId)
                .map(updatedTemplate -> ResponseEntity.ok(ApiResponse.success(updatedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("更新公共模板失败")));
    }

    /**
     * 删除公共模板
     */
    @DeleteMapping("/{templateId}")
    @Operation(summary = "删除公共模板", description = "删除指定的公共模板")
    public Mono<ResponseEntity<ApiResponse<String>>> deletePublicTemplate(
            @PathVariable String templateId,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 删除公共模板: {}", adminId, templateId);
        
        return adminTemplateService.deletePublicTemplate(templateId, adminId)
                .then(Mono.just(ResponseEntity.ok(ApiResponse.success("模板删除成功"))))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("删除模板失败")));
    }

    // ==================== 审核与发布管理 ====================

    /**
     * 审核用户模板
     */
    @PostMapping("/{templateId}/review")
    @Operation(summary = "审核用户模板", description = "审核用户提交的模板，决定是否通过并公开")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> reviewTemplate(
            @PathVariable String templateId,
            @RequestParam boolean approved,
            @RequestParam(required = false) String reviewComment,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 审核模板 {}: {}", adminId, templateId, approved ? "通过" : "拒绝");
        
        return adminTemplateService.reviewUserTemplate(templateId, approved, adminId, reviewComment)
                .map(reviewedTemplate -> ResponseEntity.ok(ApiResponse.success(reviewedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("审核模板失败")));
    }

    /**
     * 发布模板
     */
    @PostMapping("/{templateId}/publish")
    @Operation(summary = "发布模板", description = "将模板设置为公开状态")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> publishTemplate(
            @PathVariable String templateId,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 发布模板: {}", adminId, templateId);
        
        return adminTemplateService.publishTemplate(templateId, adminId)
                .map(publishedTemplate -> ResponseEntity.ok(ApiResponse.success(publishedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("发布模板失败")));
    }

    /**
     * 取消发布模板
     */
    @PostMapping("/{templateId}/unpublish")
    @Operation(summary = "取消发布模板", description = "将模板设置为私有状态")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> unpublishTemplate(
            @PathVariable String templateId,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 取消发布模板: {}", adminId, templateId);
        
        return adminTemplateService.unpublishTemplate(templateId, adminId)
                .map(unpublishedTemplate -> ResponseEntity.ok(ApiResponse.success(unpublishedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("取消发布模板失败")));
    }

    /**
     * 设置验证状态
     */
    @PostMapping("/{templateId}/verify")
    @Operation(summary = "设置验证状态", description = "设置模板的官方认证状态")
    public Mono<ResponseEntity<ApiResponse<EnhancedUserPromptTemplate>>> setVerified(
            @PathVariable String templateId,
            @RequestParam boolean verified,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 设置模板 {} 验证状态: {}", adminId, templateId, verified);
        
        return adminTemplateService.setVerified(templateId, verified, adminId)
                .map(verifiedTemplate -> ResponseEntity.ok(ApiResponse.success(verifiedTemplate)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("设置验证状态失败")));
    }

    // ==================== 批量操作 ====================

    /**
     * 批量审核模板
     */
    @PostMapping("/batch/review")
    @Operation(summary = "批量审核模板", description = "批量审核多个用户提交的模板")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> batchReview(
            @RequestBody List<String> templateIds,
            @RequestParam boolean approved,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 批量审核 {} 个模板: {}", adminId, templateIds.size(), approved ? "通过" : "拒绝");
        
        return adminTemplateService.batchReviewTemplates(templateIds, approved, adminId)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("批量审核失败")));
    }

    /**
     * 批量设置验证状态
     */
    @PostMapping("/batch/verify")
    @Operation(summary = "批量设置验证状态", description = "批量设置多个模板的官方认证状态")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> batchSetVerified(
            @RequestBody List<String> templateIds,
            @RequestParam boolean verified,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 批量设置 {} 个模板验证状态: {}", adminId, templateIds.size(), verified);
        
        return adminTemplateService.batchSetVerified(templateIds, verified, adminId)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("批量设置验证状态失败")));
    }

    /**
     * 批量发布/取消发布
     */
    @PostMapping("/batch/publish")
    @Operation(summary = "批量发布操作", description = "批量发布或取消发布多个模板")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> batchPublish(
            @RequestBody List<String> templateIds,
            @RequestParam boolean publish,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 批量{}发布 {} 个模板", adminId, publish ? "" : "取消", templateIds.size());
        
        return adminTemplateService.batchPublishTemplates(templateIds, publish, adminId)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("批量发布操作失败")));
    }

    // ==================== 统计与分析 ====================

    /**
     * 获取模板使用统计
     */
    @GetMapping("/{templateId}/statistics")
    @Operation(summary = "获取模板统计", description = "获取指定模板的详细使用统计信息")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getTemplateStatistics(
            @PathVariable String templateId) {
        log.info("获取模板 {} 的使用统计", templateId);
        
        return adminTemplateService.getTemplateUsageStatistics(templateId)
                .map(stats -> ResponseEntity.ok(ApiResponse.success(stats)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("获取模板统计失败")));
    }

    /**
     * 获取公共模板统计
     */
    @GetMapping("/statistics/public")
    @Operation(summary = "获取公共模板统计", description = "获取所有公共模板的统计信息")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getPublicTemplatesStatistics() {
        log.info("获取公共模板统计信息");
        
        return adminTemplateService.getPublicTemplatesStatistics()
                .map(stats -> ResponseEntity.ok(ApiResponse.success(stats)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("获取公共模板统计失败")));
    }

    /**
     * 获取用户模板统计
     */
    @GetMapping("/statistics/user")
    @Operation(summary = "获取用户模板统计", description = "获取指定用户或所有用户的模板统计")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getUserTemplatesStatistics(
            @RequestParam(required = false) String userId) {
        log.info("获取用户模板统计信息: {}", userId);
        
        return adminTemplateService.getUserTemplatesStatistics(userId)
                .map(stats -> ResponseEntity.ok(ApiResponse.success(stats)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("获取用户模板统计失败")));
    }

    /**
     * 获取系统模板统计
     */
    @GetMapping("/statistics/system")
    @Operation(summary = "获取系统模板统计", description = "获取整个系统的模板统计信息")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getSystemTemplatesStatistics() {
        log.info("获取系统模板统计信息");
        
        return adminTemplateService.getSystemTemplatesStatistics()
                .map(stats -> ResponseEntity.ok(ApiResponse.success(stats)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("获取系统模板统计失败")));
    }

    // ==================== 导入导出 ====================

    /**
     * 导出公共模板
     */
    @PostMapping("/export")
    @Operation(summary = "导出公共模板", description = "导出指定的公共模板，如果不指定则导出全部")
    public Mono<ResponseEntity<ApiResponse<List<EnhancedUserPromptTemplate>>>> exportTemplates(
            @RequestBody(required = false) List<String> templateIds,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 导出模板", adminId);
        
        List<String> ids = templateIds != null ? templateIds : List.of();
        
        return adminTemplateService.exportPublicTemplates(ids, adminId)
                .map(templates -> ResponseEntity.ok(ApiResponse.success(templates)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("导出模板失败")));
    }

    /**
     * 导入公共模板
     */
    @PostMapping("/import")
    @Operation(summary = "导入公共模板", description = "导入公共模板数据，自动设置为官方认证")
    public Mono<ResponseEntity<ApiResponse<List<EnhancedUserPromptTemplate>>>> importTemplates(
            @RequestBody List<EnhancedUserPromptTemplate> templates,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {
        String adminId = currentUser.getId();
        log.info("管理员 {} 导入 {} 个模板", adminId, templates.size());
        
        return adminTemplateService.importPublicTemplates(templates, adminId)
                .map(importedTemplates -> ResponseEntity.ok(ApiResponse.success(importedTemplates)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("导入模板失败")));
    }

    // ==================== 模板详情 ====================

    /**
     * 获取模板详情
     */
    @GetMapping("/{templateId}")
    @Operation(summary = "获取模板详情", description = "获取指定模板的完整信息")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getTemplateDetails(
            @PathVariable String templateId) {
        log.info("获取模板详情: {}", templateId);
        
        return adminTemplateService.getTemplateUsageStatistics(templateId)
                .map(details -> ResponseEntity.ok(ApiResponse.success(details)))
                .onErrorReturn(ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(ApiResponse.error("模板不存在")));
    }
}