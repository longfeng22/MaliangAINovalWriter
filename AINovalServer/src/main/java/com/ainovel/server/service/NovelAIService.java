package com.ainovel.server.service;

import java.util.List;
import java.util.Map;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.web.dto.GenerateSceneFromSummaryRequest;
import com.ainovel.server.web.dto.GenerateSceneFromSummaryResponse;
import com.ainovel.server.web.dto.SummarizeSceneRequest;
import com.ainovel.server.web.dto.SummarizeSceneResponse;
import com.ainovel.server.web.dto.OutlineGenerationChunk;
import com.ainovel.server.domain.model.NextOutline;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.web.dto.request.GenerateSettingsRequest;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 小说AI服务接口 专门处理与小说创作相关的AI功能
 */
public interface NovelAIService {

    /**
     * 生成小说内容
     *
     * @param request AI请求
     * @return AI响应
     */
    Mono<AIResponse> generateNovelContent(AIRequest request);

    /**
     * 生成小说内容（流式）
     *
     * @param request AI请求
     * @return 流式AI响应
     */
    Flux<String> generateNovelContentStream(AIRequest request);

    /**
     * 获取创作建议
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param suggestionType 建议类型（情节、角色、对话等）
     * @return 创作建议
     */
    Mono<AIResponse> getWritingSuggestion(String novelId, String sceneId, String suggestionType);

    /**
     * 获取创作建议（流式）
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param suggestionType 建议类型（情节、角色、对话等）
     * @return 流式创作建议
     */
    Flux<String> getWritingSuggestionStream(String novelId, String sceneId, String suggestionType);

    /**
     * 修改内容
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param content 原内容
     * @param instruction 修改指令
     * @return 修改后的内容
     */
    Mono<AIResponse> reviseContent(String novelId, String sceneId, String content, String instruction);

    /**
     * 修改内容（流式）
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param content 原内容
     * @param instruction 修改指令
     * @return 流式修改后的内容
     */
    Flux<String> reviseContentStream(String novelId, String sceneId, String content, String instruction);


    /**
     * 设置是否使用LangChain4j实现
     *
     * @param useLangChain4j 是否使用LangChain4j
     */
    void setUseLangChain4j(boolean useLangChain4j);

    /**
     * 清除用户的模型提供商缓存
     *
     * @param userId 用户ID
     * @return 操作结果
     */
    Mono<Void> clearUserProviderCache(String userId);

    /**
     * 清除所有模型提供商缓存
     *
     * @return 操作结果
     */
    Mono<Void> clearAllProviderCache();

    /**
     * 获取AI模型提供商
     *
     * @param userId 用户ID
     * @param modelName 模型名称
     * @return AI模型提供商
     */
    Mono<AIModelProvider> getAIModelProvider(String userId, String modelName);

    /**
     * 生成聊天响应
     *
     * @param userId 用户ID
     * @param sessionId 会话ID
     * @param content 用户消息内容
     * @param metadata 消息元数据
     * @return 聊天响应
     */
    Mono<AIResponse> generateChatResponse(String userId, String sessionId, String content, Map<String, Object> metadata);

    /**
     * 生成聊天响应（流式）
     *
     * @param userId 用户ID
     * @param sessionId 会话ID
     * @param content 用户消息内容
     * @param metadata 消息元数据
     * @return 流式聊天响应
     */
    Flux<String> generateChatResponseStream(String userId, String sessionId, String content, Map<String, Object> metadata);

    /**
     * 生成下一剧情大纲选项
     *
     * @param novelId 小说ID
     * @param currentContext 当前剧情上下文（可以是最近一个场景ID、章节ID或剧情描述）
     * @param numberOfOptions 希望生成的大纲选项数量（默认3）
     * @param authorGuidance 作者希望的剧情引导（可选）
     * @return 生成的多个剧情大纲选项
     */
    Mono<AIResponse> generateNextOutlines(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance);

    /**
     * 流式生成下一剧情大纲选项
     *
     * @param novelId 小说ID
     * @param currentContext 当前上下文
     * @param numberOfOptions 希望生成的选项数量
     * @param authorGuidance 作者引导
     * @return 包含剧情大纲选项块的 Flux 流
     */
    Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance);

    /**
     * 流式生成下一剧情大纲选项 (根据章节范围)
     *
     * @param novelId 小说ID
     * @param startChapterId 起始章节ID
     * @param endChapterId 结束章节ID
     * @param numberOfOptions 希望生成的选项数量
     * @param authorGuidance 作者引导
     * @return 包含剧情大纲选项块的 Flux 流
     */
    Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String startChapterId, String endChapterId, Integer numberOfOptions, String authorGuidance);

    /**
     * 流式生成下一剧情大纲选项 (带模型配置ID列表)
     *
     * @param novelId 小说ID
     * @param currentContext 当前上下文
     * @param numberOfOptions 希望生成的选项数量
     * @param authorGuidance 作者引导
     * @param selectedConfigIds 选定的AI模型配置ID列表
     * @return 包含剧情大纲选项块的 Flux 流
     */
    Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance, List<String> selectedConfigIds);

    /**
     * 流式生成下一剧情大纲选项 (根据章节范围，带模型配置ID列表)
     *
     * @param novelId 小说ID
     * @param startChapterId 起始章节ID
     * @param endChapterId 结束章节ID
     * @param numberOfOptions 希望生成的选项数量
     * @param authorGuidance 作者引导
     * @param selectedConfigIds 选定的AI模型配置ID列表
     * @return 包含剧情大纲选项块的 Flux 流
     */
    Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String startChapterId, String endChapterId, Integer numberOfOptions, String authorGuidance, List<String> selectedConfigIds);

    /**
     * 重新生成单个剧情大纲选项 (流式)
     *
     * @param novelId 小说ID
     * @param optionId 要重新生成的选项ID
     * @param userId 用户ID
     * @param modelConfigId 模型配置ID
     * @param regenerateHint 重新生成提示
     * @param originalStartChapterId (可选) 原始生成时的起始章节ID
     * @param originalEndChapterId (可选) 原始生成时的结束章节ID
     * @param originalAuthorGuidance (可选) 原始生成时的作者引导
     * @return 包含剧情大纲选项块的 Flux 流
     */
    Flux<OutlineGenerationChunk> regenerateSingleOutlineStream(String novelId, String optionId, String userId, String modelConfigId, String regenerateHint,
                                                              String originalStartChapterId, String originalEndChapterId, String originalAuthorGuidance);

    /**
     * 为指定场景生成摘要
     *
     * @param userId 用户ID
     * @param sceneId 场景ID
     * @param request 摘要请求参数
     * @return 包含摘要的响应
     */
    Mono<SummarizeSceneResponse> summarizeScene(String userId, String sceneId, SummarizeSceneRequest request);

    /**
     * 根据摘要生成场景内容 (流式)
     *
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param request 生成场景请求参数
     * @return 生成的场景内容流
     */
    Flux<String> generateSceneFromSummaryStream(String userId, String novelId, GenerateSceneFromSummaryRequest request);

    /**
     * 根据摘要生成场景内容 (非流式)
     *
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param request 生成场景请求参数
     * @return 包含生成场景内容的响应
     */
    Mono<GenerateSceneFromSummaryResponse> generateSceneFromSummary(String userId, String novelId, GenerateSceneFromSummaryRequest request);

    /**
     * 根据当前上下文（包含之前的摘要形成的大纲）生成下一个章节的单一摘要。
     *
     * @param userId            用户ID
     * @param novelId           小说ID
     * @param currentContext    当前的上下文信息，应包含足够的信息（如先前章节的摘要）来生成下一个摘要。
     * @param aiConfigIdSummary 用于生成摘要的AI配置ID (如果为null或空，则使用用户默认配置)。
     * @param writingStyle      可选的写作风格或指示。
     * @return 生成的下一个章节的摘要文本。
     */
    Mono<String> generateNextSingleSummary(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle);

    // Overload: 支持指定摘要生成的提示词模板ID
    Mono<String> generateNextSingleSummaryWithTemplate(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle, String summaryPromptTemplateId);

    // 新增：摘要流式生成（用于统一后扣费；上层可收集为字符串）
    Flux<String> generateNextSingleSummaryStream(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle, String summaryPromptTemplateId, String publicModelConfigId);

    /**
     * 根据配置ID获取AI模型提供商
     * @param userId 用户ID
     * @param configId 配置ID
     * @return AI模型提供商
     */
    Mono<AIModelProvider> getAIModelProviderByConfigId(String userId, String configId);

    Mono<List<NovelSettingItem>> generateNovelSettings(String novelId, String userId, GenerateSettingsRequest request);
}
