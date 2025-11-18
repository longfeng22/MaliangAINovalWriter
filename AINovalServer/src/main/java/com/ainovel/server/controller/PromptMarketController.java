package com.ainovel.server.controller;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.service.PromptMarketService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;

/**
 * 提示词市场控制器
 * 提供提示词模板的市场化功能API
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/prompt-market")
@Tag(name = "提示词市场", description = "提示词模板的市场化功能")
public class PromptMarketController {
    
    @Autowired
    private PromptMarketService marketService;
    
    /**
     * 获取公开提示词模板列表
     */
    @GetMapping("/templates")
    @Operation(summary = "获取公开提示词模板", description = "获取指定功能类型的公开提示词模板列表")
    public Mono<ApiResponse<List<EnhancedUserPromptTemplate>>> getPublicTemplates(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "功能类型，为空则返回所有类型") @RequestParam(required = false) AIFeatureType featureType,
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页数量") @RequestParam(defaultValue = "20") int size,
            @Parameter(description = "排序方式：latest(最新), popular(最受欢迎), mostUsed(最多使用), rating(评分)") 
            @RequestParam(defaultValue = "popular") String sortBy) {
        
        String userId = currentUser != null ? currentUser.getId() : null;
        log.info("📋 获取公开提示词模板: featureType={}, page={}, size={}, sortBy={}, userId={}", 
                featureType, page, size, sortBy, userId);
        
        var templates = featureType != null
                ? marketService.getPublicTemplates(featureType, userId, page, size, sortBy)
                : marketService.getAllPublicTemplates(userId, page, size, sortBy);
        
        return templates.collectList()
                .map(list -> {
                    log.info("✅ 返回 {} 个公开模板", list.size());
                    return ApiResponse.success(list);
                })
                .onErrorResume(error -> {
                    log.error("❌ 获取公开模板失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("获取失败: " + error.getMessage()));
                });
    }
    
    /**
     * 搜索公开提示词模板
     */
    @GetMapping("/templates/search")
    @Operation(summary = "搜索公开提示词模板", description = "根据关键词搜索公开模板")
    public Mono<ApiResponse<List<EnhancedUserPromptTemplate>>> searchTemplates(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "功能类型") @RequestParam(required = false) AIFeatureType featureType,
            @Parameter(description = "搜索关键词") @RequestParam String keyword,
            @Parameter(description = "页码") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "每页数量") @RequestParam(defaultValue = "20") int size) {
        
        String userId = currentUser != null ? currentUser.getId() : null;
        log.info("🔍 搜索公开提示词模板: keyword={}, featureType={}, userId={}", keyword, featureType, userId);
        
        return marketService.searchPublicTemplates(featureType, keyword, userId, page, size)
                .collectList()
                .map(list -> {
                    log.info("✅ 搜索到 {} 个模板", list.size());
                    return ApiResponse.success(list);
                })
                .onErrorResume(error -> {
                    log.error("❌ 搜索失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("搜索失败: " + error.getMessage()));
                });
    }
    
    /**
     * 点赞/取消点赞模板
     */
    @PostMapping("/templates/{templateId}/like")
    @Operation(summary = "点赞模板", description = "为模板点赞或取消点赞")
    public Mono<ApiResponse<Map<String, Object>>> toggleLike(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "模板ID") @PathVariable String templateId) {
        
        if (currentUser == null) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "请先登录"));
        }
        
        log.info("👍 切换点赞状态: templateId={}, userId={}", templateId, currentUser.getId());
        
        return marketService.toggleLike(templateId, currentUser.getId())
                .map(result -> {
                    log.info("✅ 点赞状态切换成功: isLiked={}, likeCount={}", 
                            result.get("isLiked"), result.get("likeCount"));
                    return ApiResponse.success(result);
                })
                .onErrorResume(error -> {
                    log.error("❌ 点赞操作失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("操作失败: " + error.getMessage()));
                });
    }
    
    /**
     * 收藏/取消收藏模板
     */
    @PostMapping("/templates/{templateId}/favorite")
    @Operation(summary = "收藏模板", description = "收藏或取消收藏模板")
    public Mono<ApiResponse<Map<String, Object>>> toggleFavorite(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "模板ID") @PathVariable String templateId) {
        
        if (currentUser == null) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "请先登录"));
        }
        
        log.info("⭐ 切换收藏状态: templateId={}, userId={}", templateId, currentUser.getId());
        
        return marketService.toggleFavorite(templateId, currentUser.getId())
                .map(result -> {
                    log.info("✅ 收藏状态切换成功: isFavorite={}, favoriteCount={}", 
                            result.get("isFavorite"), result.get("favoriteCount"));
                    return ApiResponse.success(result);
                })
                .onErrorResume(error -> {
                    log.error("❌ 收藏操作失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("操作失败: " + error.getMessage()));
                });
    }
    
    /**
     * 分享模板（提交审核）
     */
    @PostMapping("/templates/{templateId}/share")
    @Operation(summary = "分享模板", description = "将模板提交审核以便公开分享")
    public Mono<ApiResponse<String>> shareTemplate(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "模板ID") @PathVariable String templateId,
            @RequestBody(required = false) Map<String, Object> body) {
        
        if (currentUser == null) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "请先登录"));
        }
        
        log.info("🔗 分享模板: templateId={}, userId={}", templateId, currentUser.getId());
        Boolean hidePrompts = null;
        if (body != null && body.containsKey("hidePrompts")) {
            Object v = body.get("hidePrompts");
            if (v instanceof Boolean) hidePrompts = (Boolean) v;
        }

        return marketService.shareTemplate(templateId, currentUser.getId(), hidePrompts)
                .then(Mono.just(ApiResponse.success("模板已提交分享")))
                .onErrorResume(error -> {
                    log.error("❌ 分享失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("分享失败: " + error.getMessage()));
                });
    }
    
    /**
     * 设置提示词隐藏状态
     */
    @PostMapping("/templates/{templateId}/hide-prompts")
    @Operation(summary = "设置提示词隐藏", description = "设置是否隐藏系统提示词和用户提示词")
    public Mono<ApiResponse<EnhancedUserPromptTemplate>> setHidePrompts(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "模板ID") @PathVariable String templateId,
            @RequestBody HidePromptsRequest request) {
        
        if (currentUser == null) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "请先登录"));
        }
        
        log.info("🔒 设置提示词隐藏: templateId={}, userId={}, hide={}", 
                templateId, currentUser.getId(), request.isHide());
        
        return marketService.toggleHidePrompts(templateId, currentUser.getId(), request.isHide())
                .map(template -> {
                    log.info("✅ 提示词隐藏状态设置成功: hidePrompts={}", template.getHidePrompts());
                    return ApiResponse.success(template);
                })
                .onErrorResume(error -> {
                    log.error("❌ 设置失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("设置失败: " + error.getMessage()));
                });
    }
    
    /**
     * 记录模板使用并奖励积分
     */
    @PostMapping("/templates/{templateId}/use")
    @Operation(summary = "记录模板使用", description = "记录模板使用，增加使用次数并给作者奖励积分")
    public Mono<ApiResponse<String>> recordUsage(
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser,
            @Parameter(description = "模板ID") @PathVariable String templateId) {
        
        if (currentUser == null) {
            return Mono.just(ApiResponse.error("UNAUTHORIZED", "请先登录"));
        }
        
        log.info("📊 记录模板使用: templateId={}, userId={}", templateId, currentUser.getId());
        
        return marketService.recordUsageAndReward(templateId, currentUser.getId())
                .then(Mono.just(ApiResponse.success("使用记录成功")))
                .onErrorResume(error -> {
                    log.error("❌ 记录使用失败: {}", error.getMessage(), error);
                    // 使用记录失败不影响主流程，返回成功
                    return Mono.just(ApiResponse.success("使用记录成功"));
                });
    }
    
    /**
     * 获取模板的积分奖励信息
     */
    @GetMapping("/templates/{templateId}/reward-info")
    @Operation(summary = "获取积分奖励信息", description = "获取模板的引用积分奖励信息")
    public Mono<ApiResponse<Map<String, Object>>> getRewardInfo(
            @Parameter(description = "模板ID") @PathVariable String templateId) {
        
        log.info("📊 获取积分奖励信息: templateId={}", templateId);
        
        return marketService.getTemplateRewardInfo(templateId)
                .map(info -> {
                    log.info("✅ 积分信息: points={}, description={}", 
                            info.get("points"), info.get("description"));
                    return ApiResponse.success(info);
                })
                .onErrorResume(error -> {
                    log.error("❌ 获取积分信息失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("获取失败: " + error.getMessage()));
                });
    }
    
    /**
     * 获取所有功能类型的积分配置
     */
    @GetMapping("/reward-points")
    @Operation(summary = "获取积分配置", description = "获取所有功能类型的引用积分配置")
    public Mono<ApiResponse<Map<AIFeatureType, Long>>> getAllRewardPoints() {
        
        log.info("📊 获取所有功能类型的积分配置");
        
        return marketService.getAllRewardPoints()
                .map(pointsMap -> {
                    log.info("✅ 返回 {} 个功能类型的积分配置", pointsMap.size());
                    return ApiResponse.success(pointsMap);
                })
                .onErrorResume(error -> {
                    log.error("❌ 获取积分配置失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("获取失败: " + error.getMessage()));
                });
    }
    
    /**
     * 获取市场统计信息
     */
    @GetMapping("/statistics")
    @Operation(summary = "获取市场统计", description = "获取提示词市场的统计信息")
    public Mono<ApiResponse<PromptMarketService.MarketStatistics>> getStatistics() {
        
        log.info("📊 获取市场统计信息");
        
        return marketService.getMarketStatistics()
                .map(stats -> {
                    log.info("✅ 市场统计: 总模板数={}, 总作者数={}", 
                            stats.getTotalTemplates(), stats.getTotalAuthors());
                    return ApiResponse.success(stats);
                })
                .onErrorResume(error -> {
                    log.error("❌ 获取统计信息失败: {}", error.getMessage(), error);
                    return Mono.just(ApiResponse.error("获取失败: " + error.getMessage()));
                });
    }
    
    // ==================== DTO类 ====================
    
    @Data
    public static class HidePromptsRequest {
        private boolean hide;
    }
}


