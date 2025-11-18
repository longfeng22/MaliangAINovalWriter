package com.ainovel.server.service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * 提示词市场服务接口
 * 提供提示词模板的市场化功能：点赞、收藏、分享、引用积分等
 */
public interface PromptMarketService {
    
    // ==================== 市场浏览 ====================
    
    /**
     * 获取指定功能类型的公开提示词模板
     * 
     * @param featureType 功能类型
     * @param userId 当前用户ID（用于标记用户的点赞/收藏状态）
     * @param page 页码
     * @param size 每页数量
     * @param sortBy 排序方式：latest(最新), popular(最受欢迎), mostUsed(最多使用)
     * @return 公开模板列表
     */
    Flux<EnhancedUserPromptTemplate> getPublicTemplates(
            AIFeatureType featureType, 
            String userId, 
            int page, 
            int size, 
            String sortBy
    );
    
    /**
     * 获取所有功能类型的公开提示词模板（用于"全部"标签）
     * 
     * @param userId 当前用户ID
     * @param page 页码
     * @param size 每页数量
     * @param sortBy 排序方式
     * @return 公开模板列表
     */
    Flux<EnhancedUserPromptTemplate> getAllPublicTemplates(
            String userId, 
            int page, 
            int size, 
            String sortBy
    );
    
    /**
     * 搜索公开提示词模板
     * 
     * @param featureType 功能类型（可选）
     * @param keyword 搜索关键词
     * @param userId 当前用户ID
     * @param page 页码
     * @param size 每页数量
     * @return 搜索结果
     */
    Flux<EnhancedUserPromptTemplate> searchPublicTemplates(
            AIFeatureType featureType,
            String keyword,
            String userId,
            int page,
            int size
    );
    
    // ==================== 互动功能 ====================
    
    /**
     * 点赞/取消点赞模板
     * 
     * @param templateId 模板ID
     * @param userId 用户ID
     * @return 点赞后的状态 {isLiked: boolean, likeCount: long}
     */
    Mono<Map<String, Object>> toggleLike(String templateId, String userId);
    
    /**
     * 收藏/取消收藏模板
     * 
     * @param templateId 模板ID
     * @param userId 用户ID
     * @return 收藏后的状态 {isFavorite: boolean, favoriteCount: long}
     */
    Mono<Map<String, Object>> toggleFavorite(String templateId, String userId);
    
    /**
     * 分享模板（提交审核以公开）
     * 
     * @param templateId 模板ID
     * @param userId 用户ID
     * @return 提交结果
     */
    Mono<Void> shareTemplate(String templateId, String userId, Boolean hidePrompts);
    
    /**
     * 隐藏/显示提示词
     * 
     * @param templateId 模板ID
     * @param userId 用户ID
     * @param hide 是否隐藏
     * @return 更新后的模板
     */
    Mono<EnhancedUserPromptTemplate> toggleHidePrompts(String templateId, String userId, boolean hide);
    
    // ==================== 引用与积分 ====================
    
    /**
     * 记录模板引用，增加使用次数并给作者奖励积分
     * 
     * @param templateId 模板ID
     * @param userId 使用者ID
     * @return 处理结果
     */
    Mono<Void> recordUsageAndReward(String templateId, String userId);
    
    /**
     * 获取模板的引用积分信息
     * 
     * @param templateId 模板ID
     * @return 积分信息 {points: long, description: string}
     */
    Mono<Map<String, Object>> getTemplateRewardInfo(String templateId);
    
    /**
     * 获取所有功能类型的积分配置
     * 
     * @return 功能类型到积分的映射
     */
    Mono<Map<AIFeatureType, Long>> getAllRewardPoints();
    
    // ==================== 统计信息 ====================
    
    /**
     * 获取市场统计信息
     * 
     * @return 统计数据
     */
    Mono<MarketStatistics> getMarketStatistics();
    
    /**
     * 市场统计信息DTO
     */
    class MarketStatistics {
        private long totalTemplates;
        private long totalAuthors;
        private long totalUsages;
        private long totalLikes;
        private long totalFavorites;
        private Map<AIFeatureType, Long> templateCountByFeature;
        
        // getters and setters
        public long getTotalTemplates() { return totalTemplates; }
        public void setTotalTemplates(long totalTemplates) { this.totalTemplates = totalTemplates; }
        
        public long getTotalAuthors() { return totalAuthors; }
        public void setTotalAuthors(long totalAuthors) { this.totalAuthors = totalAuthors; }
        
        public long getTotalUsages() { return totalUsages; }
        public void setTotalUsages(long totalUsages) { this.totalUsages = totalUsages; }
        
        public long getTotalLikes() { return totalLikes; }
        public void setTotalLikes(long totalLikes) { this.totalLikes = totalLikes; }
        
        public long getTotalFavorites() { return totalFavorites; }
        public void setTotalFavorites(long totalFavorites) { this.totalFavorites = totalFavorites; }
        
        public Map<AIFeatureType, Long> getTemplateCountByFeature() { return templateCountByFeature; }
        public void setTemplateCountByFeature(Map<AIFeatureType, Long> templateCountByFeature) { 
            this.templateCountByFeature = templateCountByFeature; 
        }
    }
}


