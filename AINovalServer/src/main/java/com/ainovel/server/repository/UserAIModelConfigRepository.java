package com.ainovel.server.repository;

import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;

import com.ainovel.server.domain.model.UserAIModelConfig;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Repository
public interface UserAIModelConfigRepository extends ReactiveMongoRepository<UserAIModelConfig, String> {

    Flux<UserAIModelConfig> findByUserId(String userId);

    Mono<UserAIModelConfig> findByUserIdAndId(String userId, String id);

    Mono<UserAIModelConfig> findByUserIdAndProviderAndModelName(String userId, String provider, String modelName);

    Mono<Void> deleteByUserIdAndId(String userId, String id);

    /**
     * 查找用户特定提供商和模型的已验证配置
     *
     * @param userId 用户ID
     * @param provider 提供商
     * @param modelName 模型名称
     * @param isValidated 是否已验证
     * @return 配置信息
     */
    Mono<UserAIModelConfig> findByUserIdAndProviderAndModelNameAndIsValidated(String userId, String provider, String modelName, boolean isValidated);

    /**
     * 查找用户所有已验证的配置
     *
     * @param userId 用户ID
     * @param isValidated 是否已验证
     * @return 配置列表
     */
    Flux<UserAIModelConfig> findByUserIdAndIsValidated(String userId, boolean isValidated);

    /**
     * 查找用户的默认配置
     *
     * @param userId 用户ID
     * @return 默认配置，可能为空
     */
    Mono<UserAIModelConfig> findByUserIdAndIsDefaultIsTrue(String userId);

    /**
     * 查找用户的工具调用默认配置
     *
     * @param userId 用户ID
     * @return 工具调用默认配置，可能为空
     */
    Mono<UserAIModelConfig> findByUserIdAndIsToolDefaultIsTrue(String userId);

    /**
     * 查找用户所有非默认的配置
     *
     * @param userId 用户ID
     * @return 非默认配置列表
     */
    Flux<UserAIModelConfig> findByUserIdAndIsDefaultIsFalse(String userId);
}
