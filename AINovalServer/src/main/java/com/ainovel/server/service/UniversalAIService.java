package com.ainovel.server.service;

import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.web.dto.response.UniversalAIResponseDto;
import com.ainovel.server.web.dto.response.UniversalAIPreviewResponseDto;
import com.ainovel.server.domain.model.AIPromptPreset;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;

/**
 * 通用AI服务接口
 * 位于最顶层，统一处理各种类型的AI请求
 */
public interface UniversalAIService {

    /**
     * 处理通用AI请求（非流式）
     *
     * @param request 通用AI请求
     * @return AI响应
     */
    Mono<UniversalAIResponseDto> processRequest(UniversalAIRequestDto request);

    /**
     * 处理通用AI请求（流式）
     *
     * @param request 通用AI请求
     * @return AI响应流
     */
    Flux<UniversalAIResponseDto> processStreamRequest(UniversalAIRequestDto request);

    /**
     * 预览AI请求（构建提示词但不发送给AI）
     *
     * @param request 通用AI请求
     * @return 预览响应
     */
    Mono<UniversalAIPreviewResponseDto> previewRequest(UniversalAIRequestDto request);

    /**
     * 🔥 新增：构建初始的系统和用户消息（用于多轮对话场景）
     * 
     * @param request 通用AI请求
     * @return 包含system和user两条消息的列表
     */
    Mono<java.util.List<com.ainovel.server.web.dto.request.UniversalAIRequestDto.MessageDto>> buildInitialMessages(UniversalAIRequestDto request);
    
    /**
     * 🔥 新增：构建完整的 AIRequest（包含 system + user 消息）
     * 
     * @param request 通用AI请求
     * @return 完整的 AIRequest 对象
     */
    Mono<com.ainovel.server.domain.model.AIRequest> buildAIRequest(UniversalAIRequestDto request);
    
    /**
     * 🚀 新增：生成并存储提示词预设（供内部服务调用）
     * 
     * @param request 通用AI请求
     * @return 提示词生成结果
     */
    Mono<PromptGenerationResult> generateAndStorePrompt(UniversalAIRequestDto request);

    /**
     * 根据预设ID获取AI提示词预设
     * 
     * @param presetId 预设ID
     * @return AI提示词预设
     */
    Mono<AIPromptPreset> getPromptPresetById(String presetId);

    /**
     * 创建用户命名预设
     * @param request AI请求配置
     * @param presetName 预设名称
     * @param presetDescription 预设描述
     * @param presetTags 预设标签
     * @return 创建的预设
     */
    Mono<AIPromptPreset> createNamedPreset(UniversalAIRequestDto request, String presetName, 
                                          String presetDescription, java.util.List<String> presetTags);

    /**
     * 更新预设信息
     * @param presetId 预设ID
     * @param presetName 预设名称
     * @param presetDescription 预设描述
     * @param presetTags 预设标签
     * @return 更新后的预设
     */
    Mono<AIPromptPreset> updatePresetInfo(String presetId, String presetName, 
                                         String presetDescription, java.util.List<String> presetTags);

    /**
     * 更新预设的提示词
     * @param presetId 预设ID
     * @param customSystemPrompt 自定义系统提示词
     * @param customUserPrompt 自定义用户提示词
     * @return 更新后的预设
     */
    Mono<AIPromptPreset> updatePresetPrompts(String presetId, String customSystemPrompt, String customUserPrompt);

    /**
     * 获取用户的所有预设
     * @param userId 用户ID
     * @return 预设列表
     */
    Flux<AIPromptPreset> getUserPresets(String userId);

    /**
     * 根据小说ID获取用户预设（包含全局预设）
     * @param userId 用户ID
     * @param novelId 小说ID
     * @return 预设列表
     */
    Flux<AIPromptPreset> getUserPresetsByNovelId(String userId, String novelId);

    /**
     * 根据功能类型获取用户预设
     * @param userId 用户ID
     * @param featureType 功能类型
     * @return 预设列表
     */
    Flux<AIPromptPreset> getUserPresetsByFeatureType(String userId, String featureType);

    /**
     * 根据功能类型和小说ID获取用户预设（包含全局预设）
     * @param userId 用户ID
     * @param featureType 功能类型
     * @param novelId 小说ID
     * @return 预设列表
     */
    Flux<AIPromptPreset> getUserPresetsByFeatureTypeAndNovelId(String userId, String featureType, String novelId);

    /**
     * 搜索用户预设
     * @param userId 用户ID
     * @param keyword 关键词
     * @param tags 标签过滤
     * @param featureType 功能类型过滤
     * @return 匹配的预设列表
     */
    Flux<AIPromptPreset> searchUserPresets(String userId, String keyword, 
                                          java.util.List<String> tags, String featureType);

    /**
     * 根据小说ID搜索用户预设（包含全局预设）
     * @param userId 用户ID
     * @param keyword 关键词
     * @param tags 标签过滤
     * @param featureType 功能类型过滤
     * @param novelId 小说ID
     * @return 匹配的预设列表
     */
    Flux<AIPromptPreset> searchUserPresetsByNovelId(String userId, String keyword, 
                                                    java.util.List<String> tags, String featureType, String novelId);

    /**
     * 获取用户收藏的预设
     * @param userId 用户ID
     * @return 收藏的预设列表
     */
    Flux<AIPromptPreset> getUserFavoritePresets(String userId);

    /**
     * 根据小说ID获取用户收藏的预设（包含全局预设）
     * @param userId 用户ID
     * @param novelId 小说ID
     * @return 收藏的预设列表
     */
    Flux<AIPromptPreset> getUserFavoritePresetsByNovelId(String userId, String novelId);

    /**
     * 切换预设收藏状态
     * @param presetId 预设ID
     * @return 更新后的预设
     */
    Mono<AIPromptPreset> togglePresetFavorite(String presetId);

    /**
     * 删除预设
     * @param presetId 预设ID
     * @return 删除结果
     */
    Mono<Void> deletePreset(String presetId);

    /**
     * 复制预设
     * @param presetId 源预设ID
     * @param newPresetName 新预设名称
     * @return 复制的预设
     */
    Mono<AIPromptPreset> duplicatePreset(String presetId, String newPresetName);

    /**
     * 记录预设使用
     * @param presetId 预设ID
     * @return 更新后的预设
     */
    Mono<AIPromptPreset> recordPresetUsage(String presetId);

    /**
     * 获取预设统计信息
     * @param userId 用户ID
     * @return 统计信息
     */
    Mono<PresetStatistics> getPresetStatistics(String userId);

    /**
     * 根据小说ID获取预设统计信息（包含全局预设）
     * @param userId 用户ID
     * @param novelId 小说ID
     * @return 统计信息
     */
    Mono<PresetStatistics> getPresetStatisticsByNovelId(String userId, String novelId);

    /**
     * 预设统计信息
     */
    class PresetStatistics {
        private int totalPresets;
        private int favoritePresets;
        private int recentlyUsedPresets;
        private java.util.Map<String, Integer> presetsByFeatureType;
        private java.util.List<String> popularTags;
        
        // 构造函数、getter和setter
        public PresetStatistics() {}
        
        public PresetStatistics(int totalPresets, int favoritePresets, int recentlyUsedPresets,
                               java.util.Map<String, Integer> presetsByFeatureType, 
                               java.util.List<String> popularTags) {
            this.totalPresets = totalPresets;
            this.favoritePresets = favoritePresets;
            this.recentlyUsedPresets = recentlyUsedPresets;
            this.presetsByFeatureType = presetsByFeatureType;
            this.popularTags = popularTags;
        }
        
        // Getters and Setters
        public int getTotalPresets() { return totalPresets; }
        public void setTotalPresets(int totalPresets) { this.totalPresets = totalPresets; }
        
        public int getFavoritePresets() { return favoritePresets; }
        public void setFavoritePresets(int favoritePresets) { this.favoritePresets = favoritePresets; }
        
        public int getRecentlyUsedPresets() { return recentlyUsedPresets; }
        public void setRecentlyUsedPresets(int recentlyUsedPresets) { this.recentlyUsedPresets = recentlyUsedPresets; }
        
        public java.util.Map<String, Integer> getPresetsByFeatureType() { return presetsByFeatureType; }
        public void setPresetsByFeatureType(java.util.Map<String, Integer> presetsByFeatureType) { this.presetsByFeatureType = presetsByFeatureType; }
        
        public java.util.List<String> getPopularTags() { return popularTags; }
        public void setPopularTags(java.util.List<String> popularTags) { this.popularTags = popularTags; }
    }

    /**
     * 提示词生成结果DTO
     */
    class PromptGenerationResult {
        private String presetId;
        private String systemPrompt; // 仅系统提示词部分
        private String userPrompt;   // 用户提示词部分
        private String promptHash;   // 配置哈希值
        
        public PromptGenerationResult() {}
        
        public PromptGenerationResult(String presetId, String systemPrompt, String userPrompt, String promptHash) {
            this.presetId = presetId;
            this.systemPrompt = systemPrompt;
            this.userPrompt = userPrompt;
            this.promptHash = promptHash;
        }
        
        // Getters and Setters
        public String getPresetId() { return presetId; }
        public void setPresetId(String presetId) { this.presetId = presetId; }
        
        public String getSystemPrompt() { return systemPrompt; }
        public void setSystemPrompt(String systemPrompt) { this.systemPrompt = systemPrompt; }
        
        public String getUserPrompt() { return userPrompt; }
        public void setUserPrompt(String userPrompt) { this.userPrompt = userPrompt; }
        
        public String getPromptHash() { return promptHash; }
        public void setPromptHash(String promptHash) { this.promptHash = promptHash; }
    }
} 