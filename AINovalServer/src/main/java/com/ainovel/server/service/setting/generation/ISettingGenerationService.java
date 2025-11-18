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
     * 启动支持知识库集成的设定生成
     * 
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param initialPrompt 用户提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param usePublicTextModel 是否使用公共文本模型
     * @param knowledgeBaseMode 知识库模式 (NONE/REUSE/IMITATION/HYBRID)
     * @param knowledgeBaseIds 知识库ID列表
     * @param knowledgeBaseCategories 知识库分类映射
     * @return 会话Mono
     */
    Mono<SettingGenerationSession> startGenerationWithKnowledgeBase(
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        Boolean usePublicTextModel,
        String knowledgeBaseMode,
        java.util.List<String> knowledgeBaseIds,
        java.util.Map<String, java.util.List<String>> knowledgeBaseCategories
    );
    
    /**
     * 混合模式知识库集成（区分复用和参考）
     * 
     * @param userId 用户ID
     * @param novelId 小说ID（可选）
     * @param initialPrompt 初始提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param usePublicTextModel 是否使用公共文本模型
     * @param reuseKnowledgeBaseIds 用于复用的知识库ID列表
     * @param referenceKnowledgeBaseIds 用于参考的知识库ID列表（可选）
     * @param knowledgeBaseCategories 知识库分类过滤
     * @return 生成会话
     */
    Mono<SettingGenerationSession> startGenerationWithKnowledgeBaseHybrid(
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        Boolean usePublicTextModel,
        java.util.List<String> reuseKnowledgeBaseIds,
        java.util.List<String> referenceKnowledgeBaseIds,
        java.util.Map<String, java.util.List<String>> knowledgeBaseCategories
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
     * 删除节点及其所有子节点
     * 
     * @param sessionId 会话ID
     * @param nodeId 节点ID
     * @return 被删除的所有节点ID列表（包括子节点）
     */
    Mono<List<String>> deleteNode(String sessionId, String nodeId);
    
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
     * 启动设定生成（结构化输出循环模式）
     * 不使用工具调用，直接输出JSON，循环最多N次直到满足质量要求
     *
     * @param userId 用户ID
     * @param novelId 小说ID（可为null）
     * @param initialPrompt 初始提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param maxIterations 最大迭代次数（默认3）
     * @return 会话Mono
     */
    Mono<SettingGenerationSession> startGenerationStructured(
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        Integer maxIterations
    );
    
    /**
     * 启动设定生成（结构化输出循环模式 + 知识库集成）
     *
     * @param userId 用户ID
     * @param novelId 小说ID（可为null）
     * @param initialPrompt 初始提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param maxIterations 最大迭代次数（默认3）
     * @param knowledgeBaseMode 知识库模式 (NONE/REUSE/IMITATION/HYBRID)
     * @param knowledgeBaseIds 知识库ID列表（REUSE/IMITATION模式使用）
     * @param reuseKnowledgeBaseIds 用于复用的知识库ID列表（HYBRID模式专用，优先级高于knowledgeBaseIds）
     * @param referenceKnowledgeBaseIds 用于参考的知识库ID列表（HYBRID模式专用）
     * @param knowledgeBaseCategories 知识库分类映射
     * @return 会话Mono
     */
    Mono<SettingGenerationSession> startGenerationStructuredWithKnowledgeBase(
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        Integer maxIterations,
        String knowledgeBaseMode,
        java.util.List<String> knowledgeBaseIds,
        java.util.List<String> reuseKnowledgeBaseIds,
        java.util.List<String> referenceKnowledgeBaseIds,
        java.util.Map<String, java.util.List<String>> knowledgeBaseCategories
    );
    
    /**
     * 🔧 新增：支持前端传入sessionId的重载方法
     * 启动设定生成（结构化输出循环模式 + 知识库集成）
     *
     * @param sessionId 前端生成的sessionId（可选，如果为null则后端自动生成）
     * @param userId 用户ID
     * @param novelId 小说ID（可为null）
     * @param initialPrompt 初始提示词
     * @param promptTemplateId 提示词模板ID
     * @param modelConfigId 模型配置ID
     * @param maxIterations 最大迭代次数（默认3）
     * @param knowledgeBaseMode 知识库模式 (NONE/REUSE/IMITATION/HYBRID)
     * @param knowledgeBaseIds 知识库ID列表（REUSE/IMITATION模式使用）
     * @param reuseKnowledgeBaseIds 用于复用的知识库ID列表（HYBRID模式专用，优先级高于knowledgeBaseIds）
     * @param referenceKnowledgeBaseIds 用于参考的知识库ID列表（HYBRID模式专用）
     * @param knowledgeBaseCategories 知识库分类映射
     * @return 会话Mono
     */
    Mono<SettingGenerationSession> startGenerationStructuredWithKnowledgeBase(
        String sessionId,
        String userId,
        String novelId,
        String initialPrompt,
        String promptTemplateId,
        String modelConfigId,
        Integer maxIterations,
        String knowledgeBaseMode,
        java.util.List<String> knowledgeBaseIds,
        java.util.List<String> reuseKnowledgeBaseIds,
        java.util.List<String> referenceKnowledgeBaseIds,
        java.util.Map<String, java.util.List<String>> knowledgeBaseCategories
    );
    
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