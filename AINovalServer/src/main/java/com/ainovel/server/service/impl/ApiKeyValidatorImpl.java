package com.ainovel.server.service.impl;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.ainovel.server.service.ApiKeyValidator;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.service.ai.factory.AIModelProviderFactory;
import com.ainovel.server.service.ai.capability.ProviderCapabilityService;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * API Key验证器实现
 * 负责验证各种AI提供商的API Key有效性
 */
@Slf4j
@Service
public class ApiKeyValidatorImpl implements ApiKeyValidator {
    
    private final AIModelProviderFactory providerFactory;
    private final ProviderCapabilityService capabilityService;
    
    @Autowired
    public ApiKeyValidatorImpl(AIModelProviderFactory providerFactory, ProviderCapabilityService capabilityService) {
        this.providerFactory = providerFactory;
        this.capabilityService = capabilityService;
    }
    
    @Override
    public Mono<Boolean> validate(String provider, String apiKey, String apiEndpoint) {
        return validate(null, provider, "default", apiKey, apiEndpoint);
    }
    
    @Override
    public Mono<Boolean> validate(String userId, String provider, String modelName, String apiKey, String apiEndpoint) {
        log.info("[ApiKeyValidator] 开始验证API Key: provider={}, modelName={}, userId={}, endpoint={}", 
                provider, modelName, userId, apiEndpoint);
        
        try {
            // 创建临时的AI模型提供商实例用于验证（禁用可观测性，避免监听器与追踪日志）
            AIModelProvider modelProvider = providerFactory.createProvider(provider, modelName, apiKey, apiEndpoint, false);
            log.info("[ApiKeyValidator] 已创建Provider实例: class={}, providerName={}, modelName={}", 
                    modelProvider.getClass().getName(), modelProvider.getProviderName(), modelProvider.getModelName());
            
            if (modelProvider == null) {
                log.warn("无法创建提供商实例: provider={}, modelName={}", provider, modelName);
                return Mono.just(false);
            }
            
            // 调用提供商的验证方法
            return modelProvider.validateApiKey()
                    .flatMap(valid -> {
                        log.info("[ApiKeyValidator] Provider.validateApiKey 返回: {} (provider={}, model={})", valid, provider, modelName);
                        return Mono.just(valid);
                    })
                    .doOnNext(isValid -> {
                        log.info("[ApiKeyValidator] API Key验证{}: provider={}, modelName={}", isValid ? "成功" : "失败", provider, modelName);
                    })
                    .onErrorResume(error -> {
                        log.error("[ApiKeyValidator] Provider.validateApiKey 异常: provider={}, modelName={}, error={}", 
                                provider, modelName, error.getMessage(), error);
                        // 兜底：尝试使用 CapabilityService 的轻量连通性校验（例如 Qwen 走 /compatible-mode/v1/models）
                        if (capabilityService != null) {
                            log.info("[ApiKeyValidator] 尝试使用 CapabilityService.testApiKey 进行兜底校验: provider={}", provider);
                            return capabilityService.testApiKey(provider, apiKey, apiEndpoint)
                                    .doOnNext(ok -> log.info("[ApiKeyValidator] CapabilityService.testApiKey 返回: {} (provider={})", ok, provider))
                                    .onErrorResume(e -> {
                                        log.error("[ApiKeyValidator] CapabilityService.testApiKey 异常: provider={}, error={}", provider, e.getMessage(), e);
                                        return Mono.just(false);
                                    });
                        }
                        return Mono.just(false);
                    });
        } catch (Exception e) {
            log.error("[ApiKeyValidator] 创建提供商实例时发生错误: provider={}, modelName={}, error={}", 
                    provider, modelName, e.getMessage(), e);
            return Mono.just(false);
        }
    }
} 