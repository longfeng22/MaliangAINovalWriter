package com.ainovel.server.service.setting.generation;

import com.ainovel.server.domain.model.setting.generation.SettingGenerationEvent;
import com.ainovel.server.domain.model.setting.generation.SettingGenerationSession;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;

/**
 * 设定生成服务接口
 */
public interface ISettingGenerationService {
    
    /**
     * 启动设定生成
     */
    Mono<SettingGenerationSession> startGeneration(
        String userId,
        String novelId, // 可为null
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId
    );

    /**
     * 启动设定生成（混合模式：先文本后工具直通），不与设定会话持久化耦合
     */
    Mono<SettingGenerationSession> startGenerationHybrid(
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        String textEndSentinel,
        Boolean usePublicTextModel
    );
    
    /**
     * 从小说设定创建编辑会话
     * 
     * 用户选择模式说明：
     * - createNewSnapshot = true：创建新的设定快照，基于当前小说的最新设定状态
     * - createNewSnapshot = false：编辑上次的设定，使用用户在该小说的最新历史记录
     * 
     * 业务流程：
     * 1. 如果 createNewSnapshot = true：
     *    - 收集当前小说的所有设定条目
     *    - 创建新的历史记录快照
     *    - 基于新快照创建编辑会话
     * 
     * 2. 如果 createNewSnapshot = false：
     *    - 查找用户在该小说的最新历史记录
     *    - 如果存在历史记录，基于历史记录创建编辑会话
     *    - 如果不存在历史记录，自动创建新快照（等同于 createNewSnapshot = true）
     * 
     * @param novelId 小说ID
     * @param userId 用户ID
     * @param editReason 编辑原因/说明
     * @param modelConfigId 模型配置ID
     * @param createNewSnapshot 是否创建新快照（true=创建新快照，false=编辑上次设定）
     * @return 创建的编辑会话
     */
    Mono<SettingGenerationSession> startSessionFromNovel(
        String novelId,
        String userId,
        String editReason,
        String modelConfigId,
        boolean createNewSnapshot
    );
    
    /**
     * 获取生成事件流
     */
    Flux<SettingGenerationEvent> getGenerationEventStream(String sessionId);

    /**
     * 获取修改操作事件流
     */
    Flux<SettingGenerationEvent> getModificationEventStream(String sessionId);
    
    /**
     * 修改设定节点
     */
    Mono<Void> modifyNode(
        String sessionId, 
        String nodeId, 
        String modificationPrompt,
        String modelConfigId,
        String scope,
        Boolean isPublicModel,
        String publicModelConfigId
    );
    
    /**
     * 直接更新节点内容
     */
    Mono<Void> updateNodeContent(
        String sessionId,
        String nodeId,
        String newContent
    );
    
    /**
     * 保存生成的设定
     */
    Mono<SaveResult> saveGeneratedSettings(String sessionId, String novelId);
    
    /**
     * 保存生成的设定（支持更新现有历史记录）
     * 
     * @param sessionId 会话ID
     * @param novelId 小说ID
     * @param updateExisting 是否更新现有历史记录
     * @param targetHistoryId 目标历史记录ID（当updateExisting=true时使用）
     * @return 保存结果
     */
    Mono<SaveResult> saveGeneratedSettings(String sessionId, String novelId, boolean updateExisting, String targetHistoryId);
    
    /**
     * 获取可用的策略模板列表
     */
    Mono<List<StrategyTemplateInfo>> getAvailableStrategyTemplates();

    /**
     * 获取可用策略模板（含用户自定义），用户已登录时使用
     */
    Mono<List<StrategyTemplateInfo>> getAvailableStrategyTemplatesForUser(String userId);
    
    /**
     * 从历史记录创建新的编辑会话
     */
    Mono<SettingGenerationSession> startSessionFromHistory(String historyId, String newPrompt, String modelConfigId);

    /**
     * 获取会话状态
     */
    Mono<SessionStatus> getSessionStatus(String sessionId);

    /**
     * 取消生成会话
     */
    Mono<Void> cancelSession(String sessionId);

    /**
     * 基于会话进行整体调整生成
     * @param sessionId 会话ID
     * @param adjustmentPrompt 调整提示词（服务层会进行增强与合并）
     * @param modelConfigId 模型配置ID
     * @param promptTemplateId 使用的提示词模板ID（用于决定策略与提示风格）
     */
    Mono<Void> adjustSession(String sessionId, String adjustmentPrompt, String modelConfigId, String promptTemplateId);
    
    /**
     * 策略模板信息
     */
    record StrategyTemplateInfo(
        String promptTemplateId,
        String name,
        String description,
        int expectedRootNodes,
        int maxDepth,
        boolean isSystemStrategy,
        List<String> categories,
        List<String> tags
    ) {}

    /**
     * 策略信息（保留兼容性）
     */
    @Deprecated
    record StrategyInfo(
        String name,
        String description,
        int expectedRootNodeCount,
        int maxDepth
    ) {}

    /**
     * 会话状态信息
     */
    record SessionStatus(
        String status,
        Integer progress,
        String currentStep,
        Integer totalSteps,
        String errorMessage
    ) {}

    class SaveResult {
        private List<String> rootSettingIds;
        private String historyId;

        public SaveResult(List<String> rootSettingIds, String historyId) {
            this.rootSettingIds = rootSettingIds;
            this.historyId = historyId;
        }
        public List<String> getRootSettingIds() { return rootSettingIds; }
        public String getHistoryId() { return historyId; }
    }


}