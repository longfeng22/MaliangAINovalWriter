package com.ainovel.server.web.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.domain.dto.ApiKeyTestRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.domain.model.ModelListingCapability;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.ApiKeyValidator;
import com.ainovel.server.service.ai.capability.ProviderCapabilityService;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 统一的提供商/模型接口层
 * - 能力与测试API Key
 * - 模型与模型信息
 * - 模型分组
 *
 * 注意：路径前缀为 /api，结合全局 basePath(/api/v1) 形成 /api/v1/api/...，与前端既有路径保持兼容。
 */
@Slf4j
@RestController
@RequestMapping("/api/v1")
public class UnifiedProviderController {

    private final AIService aiService;
    private final ProviderCapabilityService capabilityService;
    private final ApiKeyValidator apiKeyValidator;

    @Autowired
    public UnifiedProviderController(AIService aiService, ProviderCapabilityService capabilityService, 
                                   ApiKeyValidator apiKeyValidator) {
        this.aiService = aiService;
        this.capabilityService = capabilityService;
        this.apiKeyValidator = apiKeyValidator;
    }

    // ===== Provider 能力相关 =====

    @GetMapping("/providers/{provider}/capability")
    public Mono<ResponseEntity<ModelListingCapability>> getProviderCapability(@PathVariable String provider) {
        log.info("获取提供商能力: {}", provider);
        return capabilityService.getProviderCapability(provider)
                .map(ResponseEntity::ok)
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping("/providers/{provider}/test-api-key")
    public Mono<ResponseEntity<Boolean>> testApiKey(@PathVariable String provider,
                                                    @RequestBody ApiKeyTestRequest request) {
        log.info("测试API密钥 (深度验证): provider={}", provider);
        
        // 优先使用请求中的模型名称，如果没有则使用默认模型
        String modelName = request.getModelName();
        if (modelName == null || modelName.trim().isEmpty()) {
            modelName = getDefaultModelName(provider);
            log.info("请求中未提供模型名称，使用默认模型: {}", modelName);
        } else {
            log.info("使用请求中指定的模型: {}", modelName);
        }
        
        // 创建final变量用于lambda表达式
        final String finalModelName = modelName;
        
        // 使用与create端点相同的ApiKeyValidator进行深度验证
        return apiKeyValidator.validate(null, provider, finalModelName, request.getApiKey(), request.getApiEndpoint())
                .map(ResponseEntity::ok)
                .doOnNext(result -> log.info("API Key验证结果: provider={}, modelName={}, result={}", 
                        provider, finalModelName, result.getBody()))
                .onErrorResume(e -> {
                    log.error("API Key验证异常: provider={}, modelName={}, error={}", provider, finalModelName, e.getMessage(), e);
                    return Mono.just(ResponseEntity.ok(false));
                })
                .defaultIfEmpty(ResponseEntity.ok(false));
    }

    @GetMapping("/providers/{provider}/default-endpoint")
    public ResponseEntity<String> getDefaultApiEndpoint(@PathVariable String provider) {
        String endpoint = capabilityService.getDefaultApiEndpoint(provider);
        if (endpoint != null) {
            return ResponseEntity.ok(endpoint);
        }
        return ResponseEntity.notFound().build();
    }

    // ===== 模型与模型信息 =====

    @GetMapping("/models/providers")
    public Flux<String> getProviders() {
        return aiService.getAvailableProviders();
    }

    @GetMapping("/models/providers/{provider}")
    public Flux<String> getModelsForProvider(@PathVariable String provider) {
        return aiService.getModelsForProvider(provider);
    }

    @GetMapping("/models/providers/{provider}/info")
    public Flux<ModelInfo> getModelInfosForProvider(@PathVariable String provider) {
        return aiService.getModelInfosForProvider(provider)
                .doOnError(e -> log.error("获取提供商 {} 的模型信息时出错: {}", provider, e.getMessage(), e));
    }

    @GetMapping("/models/providers/{provider}/info/auth")
    public Flux<ModelInfo> getModelInfosForProviderWithApiKey(@PathVariable String provider,
                                                              @RequestParam String apiKey,
                                                              @RequestParam(required = false) String apiEndpoint) {
        return aiService.getModelInfosForProviderWithApiKey(provider, apiKey, apiEndpoint)
                .doOnError(e -> log.error("使用API密钥获取提供商 {} 的模型信息时出错: {}", provider, e.getMessage(), e));
    }

    // ===== 模型分组 =====

    @GetMapping("/models/groups")
    public ResponseEntity<?> getModelGroups() {
        return ResponseEntity.ok(aiService.getModelGroups());
    }
    
    /**
     * 获取提供商的默认模型名称用于API Key验证
     * 这些模型名称与create端点使用的验证逻辑保持一致
     */
    private String getDefaultModelName(String provider) {
        String lowerProvider = provider.toLowerCase();
        switch (lowerProvider) {
            case "openai":
                return "gpt-4o-mini";
            case "anthropic":
                return "claude-3-5-sonnet-20241022";
            case "gemini":
                return "gemini-2.0-flash";
            case "qwen":
                return "qwen2.5-72b-instruct";
            case "zhipu":
                return "glm-4-flash";
            case "doubao":
                return "doubao-pro-128k";
            case "siliconflow":
                return "Qwen/Qwen2.5-7B-Instruct";
            case "openrouter":
                return "openai/gpt-4o-mini";
            case "grok":
                return "grok-2-1212";
            default:
                log.warn("未知提供商 {}，使用默认模型名称", provider);
                return "default";
        }
    }
}


