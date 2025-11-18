package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Map;
import java.util.Objects;

import org.jasypt.encryption.StringEncryptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import com.ainovel.server.domain.model.UserAIModelConfig;
import com.ainovel.server.repository.UserAIModelConfigRepository;
import com.ainovel.server.service.ApiKeyValidator;
import com.ainovel.server.service.UserAIModelConfigService; // Add Jasypt import

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Slf4j
@Service
public class UserAIModelConfigServiceImpl implements UserAIModelConfigService {

    private final UserAIModelConfigRepository configRepository;
    private final ApiKeyValidator apiKeyValidator;
    private final StringEncryptor encryptor;

    @Autowired
    public UserAIModelConfigServiceImpl(UserAIModelConfigRepository configRepository,
            ApiKeyValidator apiKeyValidator,
            StringEncryptor encryptor) {
        this.configRepository = configRepository;
        this.apiKeyValidator = apiKeyValidator;
        this.encryptor = encryptor;
    }

    @Override
    public Mono<UserAIModelConfig> addConfiguration(String userId, String provider, String modelName, String alias, String apiKey, String apiEndpoint) {
        if (!StringUtils.hasText(userId) || !StringUtils.hasText(provider) || !StringUtils.hasText(modelName) || !StringUtils.hasText(apiKey)) {
            return Mono.error(new IllegalArgumentException("用户ID、提供商、模型名称和API Key不能为空"));
        }

        String lowerCaseProvider = provider.toLowerCase();
        String encryptedApiKey;
        try {
            encryptedApiKey = encryptor.encrypt(apiKey);
        } catch (Exception e) {
            log.error("加密 API Key 时出错 for user {}", userId, e);
            return Mono.error(new RuntimeException("API Key 加密失败"));
        }

        // 直接保存配置，不再检查模型支持（这个检查移到业务层）
        return Mono.just(Collections.<String>emptyList())
                .flatMap(supportedModels -> {
/*                    if (!supportedModels.contains(modelName)) {
                        return Mono.error(new IllegalArgumentException("提供商 '" + lowerCaseProvider + "' 不支持模型 '" + modelName + "'"));
                    }*/

                    UserAIModelConfig newConfig = UserAIModelConfig.builder()
                            .userId(userId)
                            .provider(lowerCaseProvider)
                            .modelName(modelName)
                            .alias(StringUtils.hasText(alias) ? alias : modelName)
                            .apiKey(encryptedApiKey)
                            .apiEndpoint(apiEndpoint)
                            .isValidated(false)
                            .isDefault(false)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .build();

                    return configRepository.save(newConfig)
                            .flatMap(this::performValidation)
                            .onErrorResume(e -> {
                                log.error("添加配置失败: userId={}, provider={}, modelName={}", userId, lowerCaseProvider, modelName, e);
                                if (e.getMessage() != null && e.getMessage().contains("duplicate key error")) {
                                    return Mono.error(new RuntimeException("添加配置失败，已存在相同的模型配置。"));
                                }
                                return Mono.error(new RuntimeException("添加配置时发生数据库错误。", e));
                            });
                })
                .onErrorResume(IllegalArgumentException.class, e -> {
                    log.warn("添加配置检查失败: {}", e.getMessage());
                    return Mono.error(e);
                });
    }

    @Override
    public Mono<UserAIModelConfig> updateConfiguration(String userId, String configId, Map<String, Object> updates) {
        return configRepository.findByUserIdAndId(userId, configId)
                .switchIfEmpty(Mono.error(new RuntimeException("配置不存在或无权访问")))
                .flatMap(config -> {
                    boolean needsRevalidation = false;
                    boolean apiKeyUpdated = false;
                    String newApiKey = null;

                    if (updates.containsKey("alias") && StringUtils.hasText((String) updates.get("alias"))) {
                        config.setAlias((String) updates.get("alias"));
                    }
                    if (updates.containsKey("apiKey") && StringUtils.hasText((String) updates.get("apiKey"))) {
                        newApiKey = (String) updates.get("apiKey");
                        needsRevalidation = true;
                        apiKeyUpdated = true;
                    }
                    if (updates.containsKey("apiEndpoint")) {
                        String newEndpoint = (String) updates.get("apiEndpoint");
                        if (!Objects.equals(config.getApiEndpoint(), newEndpoint)) {
                            config.setApiEndpoint(newEndpoint);
                            needsRevalidation = true;
                        }
                    }
                    if (updates.containsKey("isDefault")) {
                        log.warn("尝试通过 updateConfiguration 修改 isDefault 状态，已忽略。请使用 setDefaultConfiguration。 userId={}, configId={}", userId, configId);
                    }

                    config.setUpdatedAt(LocalDateTime.now());

                    if (apiKeyUpdated) {
                        try {
                            config.setApiKey(encryptor.encrypt(newApiKey));
                        } catch (Exception e) {
                            log.error("更新配置时加密 API Key 失败: userId={}, configId={}", userId, configId, e);
                            return Mono.error(new RuntimeException("API Key 加密失败"));
                        }
                    }

                    if (needsRevalidation) {
                        config.setIsValidated(false);
                        config.setValidationError(null);
                        return configRepository.save(config).flatMap(this::performValidation);
                    } else {
                        return configRepository.save(config);
                    }
                });
    }

    @Override
    public Mono<Void> deleteConfiguration(String userId, String configId) {
        return configRepository.deleteByUserIdAndId(userId, configId);
    }

    @Override
    public Mono<UserAIModelConfig> getConfigurationById(String userId, String configId) {
        return configRepository.findByUserIdAndId(userId, configId);
    }

    @Override
    public Flux<UserAIModelConfig> listConfigurations(String userId) {
        return configRepository.findByUserId(userId);
    }

    @Override
    public Flux<UserAIModelConfig> listValidatedConfigurations(String userId) {
        return configRepository.findByUserIdAndIsValidated(userId, true);
    }

    @Override
    public Mono<UserAIModelConfig> validateConfiguration(String userId, String configId) {
        return configRepository.findByUserIdAndId(userId, configId)
                .switchIfEmpty(Mono.error(new RuntimeException("配置不存在或无权访问")))
                .flatMap(this::performValidation);
    }

    @Override
    public Mono<UserAIModelConfig> getValidatedConfig(String userId, String provider, String modelName) {
        return configRepository.findByUserIdAndProviderAndModelNameAndIsValidated(userId, provider.toLowerCase(), modelName, true)
                .switchIfEmpty(Mono.error(new RuntimeException("未找到用户 '" + userId + "' 的模型 '" + provider + "/" + modelName + "' 的已验证配置")));
    }

    @Override
    @Transactional
    public Mono<UserAIModelConfig> setDefaultConfiguration(String userId, String configId) {
        return configRepository.findByUserIdAndId(userId, configId)
                .switchIfEmpty(Mono.error(new RuntimeException("配置不存在或无权访问")))
                .flatMap(targetConfig -> {
                    if (!targetConfig.getIsValidated()) {
                        return Mono.error(new IllegalArgumentException("无法将未验证的配置设为默认"));
                    }
                    if (targetConfig.isDefault()) {
                        return Mono.just(targetConfig);
                    }

                    Mono<Void> clearCurrentDefault = configRepository.findByUserIdAndIsDefaultIsTrue(userId)
                            .filter(currentDefault -> !currentDefault.getId().equals(configId))
                            .flatMap(currentDefault -> {
                                currentDefault.setDefault(false);
                                currentDefault.setUpdatedAt(LocalDateTime.now());
                                return configRepository.save(currentDefault);
                            })
                            .then();

                    return clearCurrentDefault.then(Mono.defer(() -> {
                        targetConfig.setDefault(true);
                        targetConfig.setUpdatedAt(LocalDateTime.now());
                        return configRepository.save(targetConfig);
                    }));
                });
    }

    @Override
    @Transactional
    public Mono<UserAIModelConfig> setToolDefaultConfiguration(String userId, String configId) {
        return configRepository.findByUserIdAndId(userId, configId)
                .switchIfEmpty(Mono.error(new RuntimeException("配置不存在或无权访问")))
                .flatMap(targetConfig -> {
                    if (!targetConfig.getIsValidated()) {
                        return Mono.error(new IllegalArgumentException("无法将未验证的配置设为工具调用默认"));
                    }
                    if (targetConfig.isToolDefault()) {
                        return Mono.just(targetConfig);
                    }

                    Mono<Void> clearCurrentToolDefault = configRepository.findByUserIdAndIsToolDefaultIsTrue(userId)
                            .filter(currentDefault -> !currentDefault.getId().equals(configId))
                            .flatMap(currentDefault -> {
                                currentDefault.setToolDefault(false);
                                currentDefault.setUpdatedAt(LocalDateTime.now());
                                return configRepository.save(currentDefault);
                            })
                            .then();

                    return clearCurrentToolDefault.then(Mono.defer(() -> {
                        targetConfig.setToolDefault(true);
                        targetConfig.setUpdatedAt(LocalDateTime.now());
                        return configRepository.save(targetConfig);
                    }));
                });
    }

    @Override
    public Mono<UserAIModelConfig> getValidatedDefaultConfiguration(String userId) {
        return configRepository.findByUserIdAndIsDefaultIsTrue(userId)
                .filter(config -> config.getIsValidated());
    }

    @Override
    public Mono<UserAIModelConfig> getValidatedToolDefaultConfiguration(String userId) {
        return configRepository.findByUserIdAndIsToolDefaultIsTrue(userId)
                .filter(config -> config.getIsValidated());
    }

    @Override
    public Mono<UserAIModelConfig> getFirstValidatedConfiguration(String userId) {
        return configRepository.findByUserIdAndIsValidated(userId, true)
                .next();
    }

    private Mono<UserAIModelConfig> performValidation(UserAIModelConfig config) {
        String decryptedApiKey;
        try {
            decryptedApiKey = encryptor.decrypt(config.getApiKey());
        } catch (Exception e) {
            log.error("验证前解密 API Key 失败: userId={}, configId={}, provider={}, model={}", config.getUserId(), config.getId(), config.getProvider(), config.getModelName(), e);
            config.setIsValidated(false);
            config.setValidationError("API Key 解密失败，无法验证");
            config.setUpdatedAt(LocalDateTime.now());
            return configRepository.save(config);
        }

        log.info("开始验证配置 (使用解密后Key): userId={}, provider={}, model={}", config.getUserId(), config.getProvider(), config.getModelName());
        return apiKeyValidator.validate(config.getUserId(), config.getProvider(), config.getModelName(), decryptedApiKey, config.getApiEndpoint())
                .flatMap(isValid -> {
                    log.info("配置验证结果: userId={}, provider={}, model={}, isValid={}", config.getUserId(), config.getProvider(), config.getModelName(), isValid);
                    config.setIsValidated(isValid);
                    config.setValidationError(isValid ? null : "API Key 验证失败");
                    config.setUpdatedAt(LocalDateTime.now());
                    return configRepository.save(config);
                })
                .onErrorResume(e -> {
                    log.error("验证配置时 AI Service 调用出错: userId={}, provider={}, model={}, error={}", config.getUserId(), config.getProvider(), config.getModelName(), e.getMessage(), e);
                    config.setIsValidated(false);
                    
                    // 提供更详细的错误信息
                    String errorMessage = e.getMessage();
                    if (errorMessage == null || errorMessage.trim().isEmpty()) {
                        errorMessage = "验证过程中发生未知错误";
                    }
                    
                    // 针对常见错误提供更友好的错误信息
                    if (errorMessage.contains("401") || errorMessage.contains("Unauthorized")) {
                        errorMessage = "API Key无效或已过期，请检查密钥是否正确";
                    } else if (errorMessage.contains("403") || errorMessage.contains("Forbidden")) {
                        errorMessage = "API Key权限不足，请检查密钥权限设置";
                    } else if (errorMessage.contains("404") || errorMessage.contains("Not Found")) {
                        errorMessage = "API端点不存在或模型不可用，请检查端点URL和模型名称";
                    } else if (errorMessage.contains("timeout") || errorMessage.contains("timed out")) {
                        errorMessage = "请求超时，请检查网络连接或API端点是否可达";
                    } else if (errorMessage.contains("Connection refused") || errorMessage.contains("UnknownHostException")) {
                        errorMessage = "无法连接到API端点，请检查网络连接和端点URL";
                    } else if (errorMessage.contains("SSL") || errorMessage.contains("certificate")) {
                        errorMessage = "SSL证书验证失败，请检查端点的SSL配置";
                    }
                    
                    config.setValidationError(errorMessage);
                    config.setUpdatedAt(LocalDateTime.now());
                    return configRepository.save(config);
                });
    }

    @Override
    public Mono<String> getDecryptedApiKey(String userId, String configId) {
        //log.debug("获取解密的API密钥: userId={}, configId={}", userId, configId);
        return getConfigurationById(userId, configId)
            .flatMap(config -> {
                try {
                    String decryptedApiKey = null;
                    // 检查配置中是否有API密钥
                    if (config.getApiKey() != null && !config.getApiKey().isEmpty()) {
                        decryptedApiKey = encryptor.decrypt(config.getApiKey());
                    } else {
                        log.warn("配置没有API密钥: userId={}, configId={}", userId, configId);
                        return Mono.empty();
                    }
                    return Mono.just(decryptedApiKey);
                } catch (Exception e) {
                    log.error("解密API密钥失败: userId={}, configId={}", userId, configId, e);
                    return Mono.error(new RuntimeException("解密API密钥失败: " + e.getMessage(), e));
                }
            })
            .switchIfEmpty(Mono.error(new RuntimeException("找不到配置或API密钥为空: userId=" + userId + ", configId=" + configId)));
    }
}
