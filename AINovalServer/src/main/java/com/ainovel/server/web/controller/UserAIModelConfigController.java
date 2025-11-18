package com.ainovel.server.web.controller;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.domain.model.UserAIModelConfig;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.ai.capability.ProviderCapabilityService;
import com.ainovel.server.repository.ModelPricingRepository;
import com.ainovel.server.web.dto.AIModelConfigDto;
import com.ainovel.server.web.dto.CreateUserAIModelConfigRequest;
import com.ainovel.server.web.dto.ListUserConfigsRequest;
import com.ainovel.server.web.dto.ProviderModelsRequest;
import com.ainovel.server.web.dto.UpdateUserAIModelConfigRequest;
import com.ainovel.server.web.dto.UserAIModelConfigResponse;
import com.ainovel.server.web.dto.UserIdConfigIndexDto;
import com.ainovel.server.web.dto.UserIdDto;
import com.ainovel.server.web.dto.UserAIModelConfigEnrichedResponse;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Slf4j

@RestController
@RequestMapping("/api/v1/user-ai-configs")
@Tag(name = "用户AI模型配置管理", description = "管理用户个人配置的AI模型及其凭证 (所有操作使用POST)")
public class UserAIModelConfigController {

    private final UserAIModelConfigService configService;
    private final AIService aiService;
    @Autowired
    private ProviderCapabilityService capabilityService;
    @Autowired
    private ModelPricingRepository modelPricingRepository;

    @Autowired
    public UserAIModelConfigController(UserAIModelConfigService configService, AIService aiService) {
        this.configService = configService;
        this.aiService = aiService;
    }

    @PostMapping("/providers/list")
    @Operation(summary = "获取系统支持的AI提供商列表")
    public Mono<List<String>> listAvailableProviders() {
        return aiService.getAvailableProviders().collectList();
    }

    @PostMapping("/providers/models/list")
    @Operation(summary = "获取指定AI提供商支持的模型信息列表(默认或根据能力获取)")
    public Flux<ModelInfo> listModelsForProvider(
            @Valid @RequestBody ProviderModelsRequest request) {
        log.info("请求获取提供商 '{}' 的模型信息列表 (Controller)", request.provider());
        // 使用 CapabilityService 的默认模型，并尝试补齐定价信息
        return capabilityService.getDefaultModels(request.provider())
                .flatMap(this::enrichModelInfoPricing)
                .doOnError(e -> log.error("在 Controller 层获取提供商 '{}' 的模型信息时出错: {}", request.provider(), e.getMessage(), e));
    }

    /**
     * 获取用户的默认AI模型配置
     *
     * @param userIdDto 包含用户ID的DTO
     * @return 默认AI模型配置
     */
    @PostMapping("/get-default")
    @Operation(summary = "获取用户的默认AI模型配置")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> getUserDefaultAIModel(@RequestBody UserIdDto userIdDto) {
        log.debug("Request to get default AI model config for user: {}", userIdDto.getUserId());
        return configService.getValidatedDefaultConfiguration(userIdDto.getUserId())
                .map(UserAIModelConfigResponse::fromEntity)
                .map(ResponseEntity::ok)
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    /**
     * 添加AI模型配置
     *
     * @param aiModelConfigDto 包含用户ID和AI模型配置的DTO
     * @return 创建的AI模型配置
     */
    @PostMapping("/add")
    @Operation(summary = "添加AI模型配置（兼容旧接口）")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserAIModelConfigResponse> addAIModelConfig(@RequestBody AIModelConfigDto aiModelConfigDto) {
        String userId = aiModelConfigDto.getUserId();
        Object configObj = aiModelConfigDto.getConfig();
        Map<String, Object> config = new java.util.HashMap<>();
        if (configObj instanceof Map<?, ?> map) {
            for (Map.Entry<?, ?> e : map.entrySet()) {
                Object k = e.getKey();
                if (k instanceof String key) {
                    config.put(key, e.getValue());
                }
            }
        }

        String provider = (String) config.get("provider");
        String modelName = (String) config.get("modelName");
        String apiKey = (String) config.get("apiKey");
        String apiEndpoint = (String) config.get("apiEndpoint");

        log.debug("Request to add AI model config (legacy): userId={}, provider={}, model={}",
                userId, provider, modelName);

        return configService.addConfiguration(
                userId,
                provider,
                modelName,
                modelName, // 使用模型名称作为默认别名
                apiKey,
                apiEndpoint
        ).map(UserAIModelConfigResponse::fromEntity);
    }

    /**
     * 获取用户的AI模型配置列表
     *
     * @param userIdDto 包含用户ID的DTO
     * @return AI模型配置列表
     */
    @PostMapping("/list")
    @Operation(summary = "获取用户的AI模型配置列表（兼容旧接口）")
    public Mono<List<UserAIModelConfigResponse>> getUserAIModels(@RequestBody UserIdDto userIdDto) {
        log.debug("Request to get AI model configs (legacy) for user: {}", userIdDto.getUserId());
        return configService.listConfigurations(userIdDto.getUserId())
                .map(UserAIModelConfigResponse::fromEntity)
                .collectList();
    }

    /**
     * 更新AI模型配置
     *
     * @param userIdConfigIndexDto 包含用户ID、配置索引和更新的AI模型配置的DTO
     * @return 更新后的配置
     */
    @PostMapping("/update")
    @Operation(summary = "更新AI模型配置（兼容旧接口）")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> updateAIModelConfig(@RequestBody UserIdConfigIndexDto userIdConfigIndexDto) {
        String userId = userIdConfigIndexDto.getUserId();
        int configIndex = userIdConfigIndexDto.getConfigIndex();
        Object cfgObj = userIdConfigIndexDto.getConfig();
        Map<String, Object> configData = new java.util.HashMap<>();
        if (cfgObj instanceof Map<?, ?> map) {
            for (Map.Entry<?, ?> e : map.entrySet()) {
                Object k = e.getKey();
                if (k instanceof String key) {
                    configData.put(key, e.getValue());
                }
            }
        }

        log.debug("Request to update AI model config (legacy): userId={}, configIndex={}", userId, configIndex);

        // 首先根据索引查询configId
        return configService.listConfigurations(userId)
                .collectList()
                .flatMap(configs -> {
                    if (configIndex < 0 || configIndex >= configs.size()) {
                        log.warn("Config index out of bounds: userId={}, configIndex={}, size={}",
                                userId, configIndex, configs.size());
                        return Mono.just(ResponseEntity.badRequest().build());
                    }

                    String configId = configs.get(configIndex).getId();
                    Map<String, Object> updates = new java.util.HashMap<>();

                    if (configData.containsKey("provider")) {
                        log.warn("Cannot update provider via legacy API");
                    }
                    if (configData.containsKey("modelName")) {
                        log.warn("Cannot update modelName via legacy API");
                    }
                    if (configData.containsKey("alias")) {
                        updates.put("alias", configData.get("alias"));
                    }
                    if (configData.containsKey("apiKey")) {
                        updates.put("apiKey", configData.get("apiKey"));
                    }
                    if (configData.containsKey("apiEndpoint")) {
                        updates.put("apiEndpoint", configData.get("apiEndpoint"));
                    }

                    if (updates.isEmpty()) {
                        log.warn("No valid updates for config: userId={}, configId={}", userId, configId);
                        return Mono.just(ResponseEntity.badRequest().build());
                    }

                    return configService.updateConfiguration(userId, configId, updates)
                            .map(UserAIModelConfigResponse::fromEntity)
                            .map(ResponseEntity::ok)
                            .onErrorResume(e -> {
                                log.error("Error updating config: userId={}, configId={}, error={}",
                                        userId, configId, e.getMessage());
                                return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build());
                            });
                });
    }

    /**
     * 删除AI模型配置
     *
     * @param userIdConfigIndexDto 包含用户ID和配置索引的DTO
     * @return 操作结果
     */
    @PostMapping("/delete")
    @Operation(summary = "删除AI模型配置（兼容旧接口）")
    public Mono<ResponseEntity<Void>> deleteAIModelConfig(@RequestBody UserIdConfigIndexDto userIdConfigIndexDto) {
        String userId = userIdConfigIndexDto.getUserId();
        int configIndex = userIdConfigIndexDto.getConfigIndex();

        log.debug("Request to delete AI model config (legacy): userId={}, configIndex={}", userId, configIndex);

        // 首先根据索引查询configId
        return configService.listConfigurations(userId)
                .collectList()
                .flatMap(configs -> {
                    if (configIndex < 0 || configIndex >= configs.size()) {
                        log.warn("Config index out of bounds: userId={}, configIndex={}, size={}",
                                userId, configIndex, configs.size());
                        return Mono.just(ResponseEntity.badRequest().<Void>build());
                    }

                    String configId = configs.get(configIndex).getId();
                    return configService.deleteConfiguration(userId, configId)
                            .thenReturn(ResponseEntity.noContent().<Void>build())
                            .onErrorResume(e -> {
                                log.error("Error deleting config: userId={}, configId={}, error={}",
                                        userId, configId, e.getMessage());
                                return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).<Void>build());
                            });
                });
    }

    /**
     * 设置默认AI模型配置
     *
     * @param userIdConfigIndexDto 包含用户ID和配置索引的DTO
     * @return 更新后的配置
     */
    @PostMapping("/set-default")
    @Operation(summary = "设置默认AI模型配置（兼容旧接口）")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> setDefaultAIModelConfig(@RequestBody UserIdConfigIndexDto userIdConfigIndexDto) {
        String userId = userIdConfigIndexDto.getUserId();
        int configIndex = userIdConfigIndexDto.getConfigIndex();

        log.debug("Request to set default AI model config (legacy): userId={}, configIndex={}", userId, configIndex);

        // 首先根据索引查询configId
        return configService.listConfigurations(userId)
                .collectList()
                .flatMap(configs -> {
                    if (configIndex < 0 || configIndex >= configs.size()) {
                        log.warn("Config index out of bounds: userId={}, configIndex={}, size={}",
                                userId, configIndex, configs.size());
                        return Mono.just(ResponseEntity.badRequest().build());
                    }

                    String configId = configs.get(configIndex).getId();
                    return configService.setDefaultConfiguration(userId, configId)
                            .map(UserAIModelConfigResponse::fromEntity)
                            .map(ResponseEntity::ok)
                            .onErrorResume(e -> {
                                log.error("Error setting default config: userId={}, configId={}, error={}",
                                        userId, configId, e.getMessage());
                                if (e instanceof IllegalArgumentException) {
                                    return Mono.just(ResponseEntity.badRequest().build());
                                }
                                return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build());
                            });
                });
    }

    @PostMapping("/users/{userId}/create")
    @Operation(summary = "添加新的用户AI模型配置")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserAIModelConfigResponse> addConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Valid @RequestBody CreateUserAIModelConfigRequest request) {
        log.debug("Request to add config for user {}: {}", userId, request);
        return configService.addConfiguration(userId, request.provider(), request.modelName(), request.alias(), request.apiKey(), request.apiEndpoint())
                .map(UserAIModelConfigResponse::fromEntity)
                .doOnError(e -> log.error("Error adding config for user {}: {}", userId, e.getMessage()));
    }

    @PostMapping("/users/{userId}/list")
    @Operation(summary = "列出用户所有的AI模型配置")
    public Mono<List<UserAIModelConfigResponse>> listConfigurations(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @RequestBody(required = false) ListUserConfigsRequest request) {
        boolean validatedOnly = request != null && request.validatedOnly() != null && request.validatedOnly();
        log.debug("Request to list configs for user {}: validatedOnly={}", userId, validatedOnly);
        Flux<UserAIModelConfig> configsFlux = validatedOnly
                ? configService.listValidatedConfigurations(userId)
                : configService.listConfigurations(userId);
        return configsFlux.map(UserAIModelConfigResponse::fromEntity).collectList();
    }

    @PostMapping("/users/{userId}/list-enriched")
    @Operation(summary = "列出用户所有AI模型配置（带价格与标签信息）")
    public Mono<List<UserAIModelConfigEnrichedResponse>> listConfigurationsEnriched(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @RequestBody(required = false) ListUserConfigsRequest request) {
        boolean validatedOnly = request != null && request.validatedOnly() != null && request.validatedOnly();
        log.debug("Request to list enriched configs for user {}: validatedOnly={}", userId, validatedOnly);

        Flux<UserAIModelConfig> configsFlux = validatedOnly
                ? configService.listValidatedConfigurations(userId)
                : configService.listConfigurations(userId);

        // 将用户配置与AIService返回的模型信息合并（包含 CapabilityDetector 的标签与 AbstractTokenPricingCalculator 的价格）
        return configsFlux.flatMap(config -> {
            String provider = config.getProvider();
            String modelName = config.getModelName();
            // 使用 CapabilityService 默认模型，随后补齐价格
            Mono<ModelInfo> infoMono = capabilityService.getDefaultModels(provider)
                    .filter(mi -> modelName.equalsIgnoreCase(mi.getId()) || modelName.equalsIgnoreCase(mi.getName()))
                    .next()
                    .switchIfEmpty(Mono.just(ModelInfo.basic(modelName, modelName, provider)));

            return infoMono.flatMap(this::enrichModelInfoPricing)
                    .map(mi -> new UserAIModelConfigEnrichedResponse(
                            config.getId(),
                            config.getUserId(),
                            config.getProvider(),
                            config.getModelName(),
                            config.getAlias() != null ? config.getAlias() : config.getModelName(),
                            config.getApiEndpoint() != null ? config.getApiEndpoint() : "",
                            config.getIsValidated(),
                            config.isDefault(),
                            config.isToolDefault(),
                            config.getCreatedAt(),
                            config.getUpdatedAt(),
                            null, // apiKey 不在该接口返回
                            // 定价字段从已补齐的 ModelInfo.pricing 读取
                            mi.getPricing() != null ? mi.getPricing().get("input") : null,
                            mi.getPricing() != null ? mi.getPricing().get("output") : null,
                            mi.getPricing() != null ? mi.getPricing().get("unified") : null,
                            mi.getMaxTokens(),
                            mi.getDescription(),
                            mi.getProperties()
                    ));
        }).collectList();
    }

    // 补齐模型的定价信息（基于 ModelPricingRepository）
    private Mono<ModelInfo> enrichModelInfoPricing(ModelInfo modelInfo) {
        if (modelInfo == null || modelInfo.getProvider() == null || modelInfo.getId() == null) {
            return Mono.just(modelInfo);
        }
        // 如果已有价格，直接返回
        Map<String, Double> pricingMap = modelInfo.getPricing();
        if (pricingMap != null && (!pricingMap.isEmpty())) {
            return Mono.just(modelInfo);
        }
        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(modelInfo.getProvider(), modelInfo.getId())
                .map(pricing -> {
                    Map<String, Double> map = modelInfo.getPricing();
                    if (map == null) {
                        map = new java.util.HashMap<>();
                        modelInfo.setPricing(map);
                    }
                    if (pricing.getUnifiedPricePerThousandTokens() != null) {
                        map.put("unified", pricing.getUnifiedPricePerThousandTokens());
                    } else {
                        if (pricing.getInputPricePerThousandTokens() != null) {
                            map.put("input", pricing.getInputPricePerThousandTokens());
                        }
                        if (pricing.getOutputPricePerThousandTokens() != null) {
                            map.put("output", pricing.getOutputPricePerThousandTokens());
                        }
                    }
                    // 仅在缺失时补齐描述与上下文长度
                    if (modelInfo.getMaxTokens() == null && pricing.getMaxContextTokens() != null) {
                        modelInfo.setMaxTokens(pricing.getMaxContextTokens());
                    }
                    if ((modelInfo.getDescription() == null || modelInfo.getDescription().isEmpty()) && pricing.getDescription() != null) {
                        modelInfo.setDescription(pricing.getDescription());
                    }
                    if (pricing.getSupportsStreaming() != null) {
                        modelInfo.setSupportsStreaming(pricing.getSupportsStreaming());
                    }
                    return modelInfo;
                })
                .defaultIfEmpty(modelInfo);
    }

    @PostMapping("/users/{userId}/list-with-api-keys")
    @Operation(summary = "列出用户所有的AI模型配置(包含解密后的API密钥)")
    public Mono<List<UserAIModelConfigResponse>> listConfigurationsWithApiKeys(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @RequestBody(required = false) ListUserConfigsRequest request) {
        boolean validatedOnly = request != null && request.validatedOnly() != null && request.validatedOnly();
        log.debug("Request to list configs with API keys for user {}: validatedOnly={}", userId, validatedOnly);
        Flux<UserAIModelConfig> configsFlux = validatedOnly
                ? configService.listValidatedConfigurations(userId)
                : configService.listConfigurations(userId);
                
        return configsFlux
                .flatMap(config -> {
                    // 获取解密后的API密钥
                    return configService.getDecryptedApiKey(userId, config.getId())
                            .map(decryptedKey -> {
                                // 创建包含解密API密钥的响应
                                UserAIModelConfigResponse response = UserAIModelConfigResponse.fromEntity(config);
                                // 在这里添加解密后的API密钥到响应中
                                return response.withApiKey(decryptedKey);
                            })
                            .onErrorResume(e -> {
                                log.warn("无法解密API密钥 for config {}: {}", config.getId(), e.getMessage());
                                // 如果解密失败，仍然返回配置，但不包含API密钥
                                return Mono.just(UserAIModelConfigResponse.fromEntity(config));
                            });
                })
                .collectList();
    }

    @PostMapping("/users/{userId}/get/{configId}")
    @Operation(summary = "获取指定ID的用户AI模型配置")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> getConfigurationById(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId) {
        log.debug("Request to get config by ID for user {}: configId={}", userId, configId);
        return configService.getConfigurationById(userId, configId)
                .map(UserAIModelConfigResponse::fromEntity)
                .map(ResponseEntity::ok)
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping("/users/{userId}/update/{configId}")
    @Operation(summary = "更新指定ID的用户AI模型配置")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> updateConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId,
            @Valid @RequestBody UpdateUserAIModelConfigRequest request) {
        log.debug("Request to update config for user {}: configId={}, updates={}", userId, configId, request);
        Map<String, Object> updates = new java.util.HashMap<>();
        if (request.alias() != null) {
            updates.put("alias", request.alias());
        }
        if (request.apiKey() != null) {
            updates.put("apiKey", request.apiKey());
        }
        if (request.apiEndpoint() != null) {
            updates.put("apiEndpoint", request.apiEndpoint());
        }
        if (updates.isEmpty()) {
            log.warn("Update request for user {} config {} has no fields to update.", userId, configId);
            return Mono.just(ResponseEntity.badRequest().build());
        }

        return configService.updateConfiguration(userId, configId, updates)
                .map(UserAIModelConfigResponse::fromEntity)
                .map(ResponseEntity::ok)
                .onErrorResume(e -> {
                    log.error("更新配置失败: userId={}, configId={}, error={}", userId, configId, e.getMessage(), e);
                    if (e instanceof IllegalArgumentException) {
                        return Mono.just(ResponseEntity.badRequest().build());
                    }
                    if (e instanceof RuntimeException && e.getMessage() != null && e.getMessage().contains("配置不存在")) {
                        return Mono.just(ResponseEntity.notFound().build());
                    }
                    if (e instanceof RuntimeException && e.getMessage() != null && e.getMessage().contains("加密失败")) {
                        return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).<UserAIModelConfigResponse>build());
                    }
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).<UserAIModelConfigResponse>build());
                });
    }

    @PostMapping("/users/{userId}/delete/{configId}")
    @Operation(summary = "删除指定ID的用户AI模型配置")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId) {
        log.debug("Request to delete config for user {}: configId={}", userId, configId);
        return configService.deleteConfiguration(userId, configId);
    }

    @PostMapping("/users/{userId}/validate/{configId}")
    @Operation(summary = "手动触发指定配置的API Key验证")
    public Mono<ResponseEntity<Object>> validateConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId) {
        log.debug("Request to validate config for user {}: configId={}", userId, configId);
        return configService.validateConfiguration(userId, configId)
                .map(config -> {
                    UserAIModelConfigResponse response = UserAIModelConfigResponse.fromEntity(config);
                    if (config.getIsValidated()) {
                        // 验证成功
                        return ResponseEntity.ok((Object) response);
                    } else {
                        // 验证失败，返回带错误信息的响应
                        Map<String, Object> errorResponse = new HashMap<>();
                        errorResponse.put("success", false);
                        errorResponse.put("error", config.getValidationError() != null ? config.getValidationError() : "API Key验证失败");
                        errorResponse.put("config", response);
                        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body((Object) errorResponse);
                    }
                })
                .onErrorResume(e -> {
                    log.error("验证配置失败: userId={}, configId={}, error={}", userId, configId, e.getMessage(), e);
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("success", false);
                    errorResponse.put("error", e.getMessage());
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body((Object) errorResponse));
                })
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping("/users/{userId}/set-default/{configId}")
    @Operation(summary = "设置指定配置为用户的默认模型")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> setDefaultConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId) {
        log.debug("Request to set default config for user {}: configId={}", userId, configId);
        return configService.setDefaultConfiguration(userId, configId)
                .map(UserAIModelConfigResponse::fromEntity)
                .map(ResponseEntity::ok)
                .onErrorResume(IllegalArgumentException.class, e -> {
                    log.warn("设置默认配置失败 (参数错误): userId={}, configId={}, error={}", userId, configId, e.getMessage());
                    return Mono.just(ResponseEntity.badRequest().build());
                })
                .onErrorResume(RuntimeException.class, e -> {
                    log.error("设置默认配置失败 (运行时错误): userId={}, configId={}, error={}", userId, configId, e.getMessage(), e);
                    if (e.getMessage() != null && e.getMessage().contains("配置不存在")) {
                        return Mono.just(ResponseEntity.notFound().build());
                    }
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build());
                });
    }

    @PostMapping("/users/{userId}/set-tool-default/{configId}")
    @Operation(summary = "设置指定配置为用户的工具调用默认模型")
    public Mono<ResponseEntity<UserAIModelConfigResponse>> setToolDefaultConfiguration(
            @Parameter(description = "用户ID", required = true) @PathVariable String userId,
            @Parameter(description = "配置ID", required = true) @PathVariable String configId) {
        log.debug("Request to set tool-default config for user {}: configId={}", userId, configId);
        return configService.setToolDefaultConfiguration(userId, configId)
                .map(UserAIModelConfigResponse::fromEntity)
                .map(ResponseEntity::ok)
                .onErrorResume(IllegalArgumentException.class, e -> {
                    log.warn("设置工具默认配置失败 (参数错误): userId={}, configId={}, error={}", userId, configId, e.getMessage());
                    return Mono.just(ResponseEntity.badRequest().build());
                })
                .onErrorResume(RuntimeException.class, e -> {
                    log.error("设置工具默认配置失败 (运行时错误): userId={}, configId={}, error={}", userId, configId, e.getMessage(), e);
                    if (e.getMessage() != null && e.getMessage().contains("配置不存在")) {
                        return Mono.just(ResponseEntity.notFound().build());
                    }
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build());
                });
    }
}
