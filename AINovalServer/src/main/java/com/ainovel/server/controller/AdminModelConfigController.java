package com.ainovel.server.controller;

import java.util.List;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.dto.PublicModelConfigDetailsDTO;
import com.ainovel.server.dto.PublicModelConfigRequestDTO;
import com.ainovel.server.dto.PublicModelConfigResponseDTO;
import com.ainovel.server.dto.PublicModelConfigWithKeysDTO;
import com.ainovel.server.repository.ModelPricingRepository;
import com.ainovel.server.service.PublicModelConfigService;

import org.jasypt.encryption.StringEncryptor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * 管理员模型配置管理控制器
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/admin/model-configs")
@PreAuthorize("hasAuthority('ADMIN_MANAGE_MODELS') or hasRole('SUPER_ADMIN')")
public class AdminModelConfigController {
    
    private final PublicModelConfigService publicModelConfigService;
    private final StringEncryptor encryptor;
    private final ModelPricingRepository modelPricingRepository;
    
    @Autowired
    public AdminModelConfigController(PublicModelConfigService publicModelConfigService, 
                                    StringEncryptor encryptor,
                                    ModelPricingRepository modelPricingRepository) {
        this.publicModelConfigService = publicModelConfigService;
        this.encryptor = encryptor;
        this.modelPricingRepository = modelPricingRepository;
    }
    
    /**
     * 获取所有公共模型配置的详细信息
     * 包含定价信息和使用统计
     */
    @GetMapping
    public Mono<ResponseEntity<ApiResponse<List<PublicModelConfigDetailsDTO>>>> getAllConfigs() {
        return publicModelConfigService.findAllWithDetails()
                .collectList()
                .map(configs -> ResponseEntity.ok(ApiResponse.success(configs)))
                .onErrorResume(e -> {
                    log.error("获取公共模型配置列表失败", e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 获取简单的公共模型配置列表（不包含详细信息）
     */
    @GetMapping("/simple")
    public Mono<ResponseEntity<ApiResponse<List<PublicModelConfigResponseDTO>>>> getSimpleConfigs() {
        return publicModelConfigService.findAll()
                .map(this::convertToResponseDTO)
                .collectList()
                .map(configs -> ResponseEntity.ok(ApiResponse.success(configs)))
                .onErrorResume(e -> {
                    log.error("获取简单公共模型配置列表失败", e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 根据ID获取模型配置
     */
    @GetMapping("/{id}")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> getConfigById(@PathVariable String id) {
        return publicModelConfigService.findById(id)
                .map(config -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(config))))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    /**
     * 根据ID获取模型配置详细信息（包含API Keys）
     * 仅供管理员使用
     */
    @GetMapping("/{id}/with-keys")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigWithKeysDTO>>> getConfigWithKeysById(@PathVariable String id) {
        return publicModelConfigService.findById(id)
                .map(config -> ResponseEntity.ok(ApiResponse.success(convertToWithKeysDTO(config))))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }
    
    /**
     * 创建新模型配置
     */
    @PostMapping
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> createConfig(
            @RequestBody PublicModelConfigRequestDTO requestDTO,
            @RequestParam(value = "validate", required = false, defaultValue = "false") boolean validate,
            @RequestParam(value = "checkPricing", required = false, defaultValue = "true") boolean checkPricing) {
        PublicModelConfig config = convertToEntity(requestDTO);
        
        // 首先进行定价验证
        Mono<Void> pricingValidation = Mono.empty();
        if (checkPricing) {
            pricingValidation = validateModelPricing(config.getProvider(), config.getModelId());
        }
        
        return pricingValidation
                .then(publicModelConfigService.createConfig(config))
                .flatMap(savedConfig -> {
                    if (validate) {
                        log.info("创建配置后立即验证API Key: {}", savedConfig.getId());
                        return publicModelConfigService.validateConfig(savedConfig.getId());
                    } else {
                        return Mono.just(savedConfig);
                    }
                })
                .map(finalConfig -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(finalConfig))))
                .onErrorResume(e -> {
                    log.error("创建公共模型配置失败", e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 验证模型定价信息是否存在
     */
    private Mono<Void> validateModelPricing(String provider, String modelId) {
        return modelPricingRepository.existsByProviderAndModelIdAndActiveTrue(provider, modelId)
                .flatMap(exists -> {
                    if (exists) {
                        log.info("✅ 模型定价验证通过: {}:{}", provider, modelId);
                        return Mono.<Void>empty();
                    } else {
                        log.warn("⚠️ 模型定价不存在，尝试查找备选方案: {}:{}", provider, modelId);
                        return findFallbackPricingValidation(provider, modelId);
                    }
                });
    }
    
    /**
     * 查找备选定价方案进行验证
     */
    private Mono<Void> findFallbackPricingValidation(String provider, String modelId) {
        // 查找相同模型ID的其他提供商定价
        return modelPricingRepository.findByModelIdAndActiveTrue(modelId)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .flatMap(fallbackPricing -> {
                    log.info("✅ 找到备选定价方案: {}:{} -> {}:{}", 
                            provider, modelId, fallbackPricing.getProvider(), fallbackPricing.getModelId());
                    return Mono.<Void>empty();
                })
                // 尝试模型名称匹配
                .switchIfEmpty(modelPricingRepository.findByModelNameAndActiveTrue(modelId)
                        .filter(pricing -> !provider.equals(pricing.getProvider()))
                        .next()
                        .flatMap(fallbackPricing -> {
                            log.info("✅ 根据模型名称找到备选定价: {}:{} -> {}:{}", 
                                    provider, modelId, fallbackPricing.getProvider(), fallbackPricing.getModelName());
                            return Mono.<Void>empty();
                        }))
                // 尝试前缀匹配
                .switchIfEmpty(findByPrefixValidation(provider, modelId))
                // 如果都没找到，抛出警告但不阻止创建
                .switchIfEmpty(Mono.fromRunnable(() -> 
                        log.warn("⚠️ 未找到模型定价信息和备选方案: {}:{}, 建议手动添加定价信息", provider, modelId)));
    }
    
    /**
     * 前缀匹配验证
     */
    private Mono<Void> findByPrefixValidation(String provider, String modelId) {
        String prefix = extractModelPrefix(modelId);
        if (prefix.length() < 3) {
            return Mono.empty();
        }
        
        return modelPricingRepository.findByModelIdStartingWithIgnoreCase(prefix)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .flatMap(fallbackPricing -> {
                    log.info("✅ 通过前缀匹配找到备选定价: {}:{} -> {}:{} (前缀: {})", 
                            provider, modelId, fallbackPricing.getProvider(), fallbackPricing.getModelId(), prefix);
                    return Mono.<Void>empty();
                });
    }
    
    /**
     * 提取模型前缀
     */
    private String extractModelPrefix(String modelId) {
        if (modelId == null || modelId.isEmpty()) {
            return "";
        }
        
        String[] separators = {"-", "_", "."};
        
        for (String separator : separators) {
            int index = modelId.indexOf(separator);
            if (index > 0) {
                return modelId.substring(0, index);
            }
        }
        
        int halfLength = modelId.length() / 2;
        return halfLength > 2 ? modelId.substring(0, halfLength) : modelId;
    }
    
    /**
     * 更新模型配置
     */
    @PutMapping("/{id}")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> updateConfig(
            @PathVariable String id, 
            @RequestBody PublicModelConfigRequestDTO requestDTO,
            @RequestParam(value = "validate", required = false, defaultValue = "false") boolean validate) {
        PublicModelConfig config = convertToEntity(requestDTO);
        
        return publicModelConfigService.updateConfig(id, config)
                .flatMap(updatedConfig -> {
                    if (validate) {
                        log.info("更新配置后立即验证API Key: {}", id);
                        return publicModelConfigService.validateConfig(id);
                    } else {
                        return Mono.just(updatedConfig);
                    }
                })
                .map(finalConfig -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(finalConfig))))
                .onErrorResume(e -> {
                    log.error("更新公共模型配置失败: {}", id, e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 删除模型配置
     */
    @DeleteMapping("/{id}")
    public Mono<ResponseEntity<ApiResponse<Void>>> deleteConfig(@PathVariable String id) {
        return publicModelConfigService.deleteConfig(id)
                .then(Mono.just(ResponseEntity.ok(ApiResponse.<Void>success())))
                .onErrorResume(e -> Mono.just(
                    ResponseEntity.badRequest().body(ApiResponse.<Void>error(e.getMessage()))
                ));
    }
    
    /**
     * 启用/禁用模型配置
     */
    @PatchMapping("/{id}/status")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfig>>> toggleConfigStatus(
            @PathVariable String id, 
            @RequestBody StatusRequest request) {
        return publicModelConfigService.toggleStatus(id, request.isEnabled())
                .map(updatedConfig -> ResponseEntity.ok(ApiResponse.success(updatedConfig)))
                .onErrorResume(e -> Mono.just(
                    ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()))
                ));
    }
    
    /**
     * 为模型配置添加支持的功能
     */
    @PostMapping("/{id}/features")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfig>>> addFeatureToConfig(
            @PathVariable String id, 
            @RequestBody FeatureRequest request) {
        return publicModelConfigService.addEnabledFeature(id, request.getFeatureType())
                .map(updatedConfig -> ResponseEntity.ok(ApiResponse.success(updatedConfig)))
                .onErrorResume(e -> Mono.just(
                    ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()))
                ));
    }
    
    /**
     * 从模型配置移除支持的功能
     */
    @DeleteMapping("/{id}/features/{featureType}")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfig>>> removeFeatureFromConfig(
            @PathVariable String id, 
            @PathVariable AIFeatureType featureType) {
        return publicModelConfigService.removeEnabledFeature(id, featureType)
                .map(updatedConfig -> ResponseEntity.ok(ApiResponse.success(updatedConfig)))
                .onErrorResume(e -> Mono.just(
                    ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()))
                ));
    }
    
    /**
     * 批量更新模型配置的积分汇率乘数
     */
    @PatchMapping("/credit-rate")
    public Mono<ResponseEntity<ApiResponse<List<PublicModelConfigResponseDTO>>>> updateCreditRates(
            @RequestBody List<CreditRateUpdate> updates) {
        return publicModelConfigService.batchUpdateCreditRates(updates)
                .map(this::convertToResponseDTO)
                .collectList()
                .map(updatedConfigs -> ResponseEntity.ok(ApiResponse.success(updatedConfigs)))
                .onErrorResume(e -> {
                    log.error("批量更新积分汇率失败", e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 验证指定配置的所有API Key
     */
    @PostMapping("/{id}/validate")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> validateConfig(@PathVariable String id) {
        return publicModelConfigService.validateConfig(id)
                .map(config -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(config))))
                .onErrorResume(e -> {
                    log.error("验证公共模型配置失败: {}", id, e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 为配置添加API Key
     */
    @PostMapping("/{id}/api-keys")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> addApiKey(
            @PathVariable String id,
            @RequestBody ApiKeyRequest request) {
        return publicModelConfigService.addApiKey(id, request.getApiKey(), request.getNote())
                .map(config -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(config))))
                .onErrorResume(e -> {
                    log.error("添加API Key失败: {}", id, e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 从配置中移除API Key
     */
    @DeleteMapping("/{id}/api-keys")
    public Mono<ResponseEntity<ApiResponse<PublicModelConfigResponseDTO>>> removeApiKey(
            @PathVariable String id,
            @RequestBody ApiKeyRequest request) {
        return publicModelConfigService.removeApiKey(id, request.getApiKey())
                .map(config -> ResponseEntity.ok(ApiResponse.success(convertToResponseDTO(config))))
                .onErrorResume(e -> {
                    log.error("移除API Key失败: {}", id, e);
                    return Mono.just(ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage())));
                });
    }
    
    /**
     * 状态请求DTO
     */
    public static class StatusRequest {
        private boolean enabled;
        
        public boolean isEnabled() {
            return enabled;
        }
        
        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }
    }
    
    /**
     * 功能请求DTO
     */
    public static class FeatureRequest {
        private AIFeatureType featureType;
        
        public AIFeatureType getFeatureType() {
            return featureType;
        }
        
        public void setFeatureType(AIFeatureType featureType) {
            this.featureType = featureType;
        }
    }
    
    /**
     * 积分汇率更新DTO
     */
    public static class CreditRateUpdate {
        private String configId;
        private Double creditRateMultiplier;
        
        public String getConfigId() {
            return configId;
        }
        
        public void setConfigId(String configId) {
            this.configId = configId;
        }
        
        public Double getCreditRateMultiplier() {
            return creditRateMultiplier;
        }
        
        public void setCreditRateMultiplier(Double creditRateMultiplier) {
            this.creditRateMultiplier = creditRateMultiplier;
        }
    }
    
    /**
     * API Key请求DTO
     */
    public static class ApiKeyRequest {
        private String apiKey;
        private String note;
        
        public String getApiKey() {
            return apiKey;
        }
        
        public void setApiKey(String apiKey) {
            this.apiKey = apiKey;
        }
        
        public String getNote() {
            return note;
        }
        
        public void setNote(String note) {
            this.note = note;
        }
    }
    
    /**
     * 转换实体为响应DTO
     */
    private PublicModelConfigResponseDTO convertToResponseDTO(PublicModelConfig config) {
        List<PublicModelConfigResponseDTO.ApiKeyStatusDTO> apiKeyStatuses = config.getApiKeys() != null
                ? config.getApiKeys().stream()
                        .map(entry -> PublicModelConfigResponseDTO.ApiKeyStatusDTO.builder()
                                .isValid(entry.getIsValid())
                                .validationError(entry.getValidationError())
                                .lastValidatedAt(entry.getLastValidatedAt())
                                .note(entry.getNote())
                                .build())
                        .collect(Collectors.toList())
                : List.of();
        
        return PublicModelConfigResponseDTO.builder()
                .id(config.getId())
                .provider(config.getProvider())
                .modelId(config.getModelId())
                .displayName(config.getDisplayName())
                .enabled(config.getEnabled())
                .apiEndpoint(config.getApiEndpoint())
                .isValidated(config.getIsValidated())
                .apiKeyPoolStatus(config.getApiKeyPoolStatus())
                .apiKeyStatuses(apiKeyStatuses)
                .enabledForFeatures(config.getEnabledForFeatures())
                .creditRateMultiplier(config.getCreditRateMultiplier())
                .maxConcurrentRequests(config.getMaxConcurrentRequests())
                .dailyRequestLimit(config.getDailyRequestLimit())
                .hourlyRequestLimit(config.getHourlyRequestLimit())
                .priority(config.getPriority())
                .description(config.getDescription())
                .tags(config.getTags())
                .createdAt(config.getCreatedAt())
                .updatedAt(config.getUpdatedAt())
                .createdBy(config.getCreatedBy())
                .updatedBy(config.getUpdatedBy())
                .build();
    }
    
    /**
     * 转换请求DTO为实体
     */
    private PublicModelConfig convertToEntity(PublicModelConfigRequestDTO requestDTO) {
        PublicModelConfig config = PublicModelConfig.builder()
                .provider(requestDTO.getProvider())
                .modelId(requestDTO.getModelId())
                .displayName(requestDTO.getDisplayName())
                .enabled(requestDTO.getEnabled())
                .apiEndpoint(requestDTO.getApiEndpoint())
                .enabledForFeatures(requestDTO.getEnabledForFeatures())
                .creditRateMultiplier(requestDTO.getCreditRateMultiplier())
                .maxConcurrentRequests(requestDTO.getMaxConcurrentRequests())
                .dailyRequestLimit(requestDTO.getDailyRequestLimit())
                .hourlyRequestLimit(requestDTO.getHourlyRequestLimit())
                .priority(requestDTO.getPriority())
                .description(requestDTO.getDescription())
                .tags(requestDTO.getTags())
                .build();
        
        // 转换API Key
        if (requestDTO.getApiKeys() != null) {
            for (PublicModelConfigRequestDTO.ApiKeyRequestDTO apiKeyDTO : requestDTO.getApiKeys()) {
                config.addApiKey(apiKeyDTO.getApiKey(), apiKeyDTO.getNote());
            }
        }
        
        return config;
    }

    /**
     * 转换实体为包含API Keys的响应DTO
     */
    private PublicModelConfigWithKeysDTO convertToWithKeysDTO(PublicModelConfig config) {
        List<PublicModelConfigWithKeysDTO.ApiKeyWithStatusDTO> apiKeyStatuses = config.getApiKeys() != null
                ? config.getApiKeys().stream()
                        .map(entry -> {
                            String decryptedApiKey = null;
                            try {
                                // 解密API Key用于管理界面显示
                                decryptedApiKey = encryptor.decrypt(entry.getApiKey());
                            } catch (Exception e) {
                                log.warn("解密API Key失败，返回加密值: configId={}, error={}", config.getId(), e.getMessage());
                                // 如果解密失败，仍然返回原始值（可能是明文或有问题的加密值）
                                decryptedApiKey = entry.getApiKey();
                            }
                            
                            return PublicModelConfigWithKeysDTO.ApiKeyWithStatusDTO.builder()
                                .apiKey(decryptedApiKey)
                                .isValid(entry.getIsValid())
                                .validationError(entry.getValidationError())
                                .lastValidatedAt(entry.getLastValidatedAt())
                                .note(entry.getNote())
                                .build();
                        })
                        .collect(Collectors.toList())
                : List.of();
        
        return PublicModelConfigWithKeysDTO.builder()
                .id(config.getId())
                .provider(config.getProvider())
                .modelId(config.getModelId())
                .displayName(config.getDisplayName())
                .enabled(config.getEnabled())
                .apiEndpoint(config.getApiEndpoint())
                .isValidated(config.getIsValidated())
                .apiKeyPoolStatus(config.getApiKeyPoolStatus())
                .apiKeyStatuses(apiKeyStatuses)
                .enabledForFeatures(config.getEnabledForFeatures())
                .creditRateMultiplier(config.getCreditRateMultiplier())
                .maxConcurrentRequests(config.getMaxConcurrentRequests())
                .dailyRequestLimit(config.getDailyRequestLimit())
                .hourlyRequestLimit(config.getHourlyRequestLimit())
                .priority(config.getPriority())
                .description(config.getDescription())
                .tags(config.getTags())
                .createdAt(config.getCreatedAt())
                .updatedAt(config.getUpdatedAt())
                .createdBy(config.getCreatedBy())
                .updatedBy(config.getUpdatedBy())
                .build();
    }
}