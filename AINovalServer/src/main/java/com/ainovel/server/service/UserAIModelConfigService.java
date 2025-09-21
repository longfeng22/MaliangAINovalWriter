package com.ainovel.server.service;

import java.util.Map;

import com.ainovel.server.domain.model.UserAIModelConfig;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 用户AI模型配置管理服务接口
 */
public interface UserAIModelConfigService {

    /**
     * 添加用户模型配置 (添加后自动尝试验证)
     *
     * @param userId 用户ID
     * @param provider 提供商
     * @param modelName 模型名称
     * @param alias 别名
     * @param apiKey API Key
     * @param apiEndpoint API Endpoint (可选)
     * @return 创建并验证后的配置
     */
    Mono<UserAIModelConfig> addConfiguration(String userId, String provider, String modelName, String alias, String apiKey, String apiEndpoint);

    /**
     * 更新用户模型配置 (更新后需要重新验证)
     *
     * @param userId 用户ID
     * @param configId 配置ID
     * @param updates 包含要更新字段的Map (例如: alias, apiKey, apiEndpoint)
     * @return 更新并重新验证后的配置
     */
    Mono<UserAIModelConfig> updateConfiguration(String userId, String configId, Map<String, Object> updates);

    /**
     * 删除用户模型配置
     *
     * @param userId 用户ID
     * @param configId 配置ID
     * @return 完成信号
     */
    Mono<Void> deleteConfiguration(String userId, String configId);

    /**
     * 获取用户指定ID的配置
     *
     * @param userId 用户ID
     * @param configId 配置ID
     * @return 配置信息
     */
    Mono<UserAIModelConfig> getConfigurationById(String userId, String configId);

    /**
     * 列出用户所有的模型配置
     *
     * @param userId 用户ID
     * @return 配置列表
     */
    Flux<UserAIModelConfig> listConfigurations(String userId);

    /**
     * 列出用户所有已验证的模型配置
     *
     * @param userId 用户ID
     * @return 已验证的配置列表
     */
    Flux<UserAIModelConfig> listValidatedConfigurations(String userId);

    /**
     * 手动触发验证指定配置
     *
     * @param userId 用户ID
     * @param configId 配置ID
     * @return 验证后的配置信息
     */
    Mono<UserAIModelConfig> validateConfiguration(String userId, String configId);

    /**
     * 获取用户指定提供商和模型的已验证配置
     *
     * @param userId 用户ID
     * @param provider 提供商
     * @param modelName 模型名称
     * @return 已验证的配置信息，如果未找到或未验证则返回错误
     */
    Mono<UserAIModelConfig> getValidatedConfig(String userId, String provider, String modelName);

    /**
     * 设置用户的默认模型配置 会将指定configId设为默认，并将该用户其他所有配置设为非默认 要求该配置必须是已验证的
     * (isValidated=true)
     *
     * @param userId 用户ID
     * @param configId 要设为默认的配置ID
     * @return 更新后的默认配置
     */
    Mono<UserAIModelConfig> setDefaultConfiguration(String userId, String configId);

    /**
     * 设置用户的默认工具调用模型配置。
     * 要求该配置必须是已验证的。
     * 该方法会清除用户此前的工具调用默认配置标记。
     */
    Mono<UserAIModelConfig> setToolDefaultConfiguration(String userId, String configId);

    /**
     * 获取用户的默认模型配置 (必须是已验证的)
     *
     * @param userId 用户ID
     * @return 已验证的默认配置，如果不存在或未验证则返回 empty Mono
     */
    Mono<UserAIModelConfig> getValidatedDefaultConfiguration(String userId);

    /**
     * 获取用户的默认工具调用模型配置 (必须是已验证的)
     */
    Mono<UserAIModelConfig> getValidatedToolDefaultConfiguration(String userId);

    /**
     * 获取用户最近使用的已验证模型配置 (简化实现：获取第一个已验证的)
     *
     * @param userId 用户ID
     * @return 第一个找到的已验证配置，可能为空
     */
    Mono<UserAIModelConfig> getFirstValidatedConfiguration(String userId);

    /**
     * 获取用户配置的解密后API密钥
     * 
     * @param userId 用户ID
     * @param configId 配置ID
     * @return 解密后的API密钥
     */
    Mono<String> getDecryptedApiKey(String userId, String configId);
}
