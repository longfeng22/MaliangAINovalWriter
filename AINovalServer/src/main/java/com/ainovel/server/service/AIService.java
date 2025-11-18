package com.ainovel.server.service;

import java.util.List;
import java.util.Map;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.AIModelProvider;

import dev.langchain4j.agent.tool.ToolSpecification;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.response.ChatResponse;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 基础AI服务接口 只处理与AI模型交互的基础功能，不包含业务逻辑
 */
public interface AIService {

    /**
     * 生成内容 (非流式)
     *
     * @param request 包含提示、消息、模型名、参数等的请求对象
     * @param apiKey 用户提供的API Key
     * @param apiEndpoint 用户提供的API Endpoint (可选)
     * @return AI响应
     */
    Mono<AIResponse> generateContent(AIRequest request, String apiKey, String apiEndpoint);

    /**
     * 生成内容 (流式)
     *
     * @param request 包含提示、消息、模型名、参数等的请求对象
     * @param apiKey 用户提供的API Key
     * @param apiEndpoint 用户提供的API Endpoint (可选)
     * @return 响应内容流
     */
    Flux<String> generateContentStream(AIRequest request, String apiKey, String apiEndpoint);

    /**
     * 获取系统支持的所有模型
     *
     * @return 模型名称流
     */
    Flux<String> getAvailableModels();

    /**
     * 估算请求成本 (可能需要API Key)
     *
     * @param request 请求对象
     * @param apiKey API Key
     * @param apiEndpoint API Endpoint (可选)
     * @return 估算成本
     */
    Mono<Double> estimateCost(AIRequest request, String apiKey, String apiEndpoint);



    /**
     * 获取指定模型的提供商名称
     *
     * @param modelName 模型名称
     * @return 提供商名称 (小写)
     */
    String getProviderForModel(String modelName);

    /**
     * 获取指定提供商支持的模型列表
     *
     * @param provider 提供商名称 (小写)
     * @return 模型列表
     */
    Flux<String> getModelsForProvider(String provider);

    /**
     * 获取指定提供商支持的模型详细信息
     *
     * @param provider 提供商名称 (小写)
     * @return 模型信息列表
     */
    Flux<ModelInfo> getModelInfosForProvider(String provider);

    /**
     * 使用API密钥获取指定提供商支持的模型详细信息
     *
     * @param provider 提供商名称 (小写)
     * @param apiKey API密钥
     * @param apiEndpoint API端点 (可选)
     * @return 模型信息列表
     */
    Flux<ModelInfo> getModelInfosForProviderWithApiKey(String provider, String apiKey, String apiEndpoint);

    /**
     * 获取所有支持的提供商
     *
     * @return 提供商名称列表 (小写)
     */
    Flux<String> getAvailableProviders();

    /**
     * 获取模型分组信息
     *
     * @return 模型分组Map
     */
    Map<String, List<String>> getModelGroups();

    /**
     * 创建AI模型提供商实例 (内部使用或高级场景)
     *
     * @param provider 提供商名称
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点 (可选)
     * @return AI模型提供商实例
     */
    // 已废弃并删除实现：请使用 createProviderByConfigId

    /**
     * 根据配置ID创建AI模型提供商（统一入口）。
     * - 优先解析用户私有配置；不存在则回退公共配置
     * - 自动解密/获取API Key与Endpoint
     * - 自动挂载装饰器链（Billing→Tracing→Provider）
     */
    AIModelProvider createProviderByConfigId(String userId, String configId);

    /**
     * 设置是否使用LangChain4j实现 (全局配置)
     *
     * @param useLangChain4j 是否使用LangChain4j
     */
    void setUseLangChain4j(boolean useLangChain4j);
    
    /**
     * 使用工具调用生成内容 (LangChain4j)
     *
     * @param messages 聊天消息列表
     * @param toolSpecifications 工具规范列表
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点 (可选)
     * @param config 额外配置参数
     * @return 聊天响应
     */
    Mono<ChatResponse> chatWithTools(
        List<ChatMessage> messages,
        List<ToolSpecification> toolSpecifications,
        String modelName,
        String apiKey,
        String apiEndpoint,
        Map<String, String> config
    );
    
    /**
     * 执行工具调用循环
     * 自动处理多轮工具调用，直到AI不再请求工具或达到最大迭代次数
     *
     * @param messages 初始消息列表
     * @param toolSpecifications 工具规范列表
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点 (可选)
     * @param config 额外配置参数
     * @param maxIterations 最大迭代次数
     * @return 完整的对话历史（包含工具调用和结果）
     */
    Mono<List<ChatMessage>> executeToolCallLoop(
        List<ChatMessage> messages,
        List<ToolSpecification> toolSpecifications,
        String modelName,
        String apiKey,
        String apiEndpoint,
        Map<String, String> config,
        int maxIterations
    );

}
