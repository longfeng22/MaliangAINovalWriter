package com.ainovel.server.controller;

import java.math.BigDecimal;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.repository.ModelPricingRepository;
import com.ainovel.server.service.ai.pricing.PricingDataSyncService;
import com.ainovel.server.service.ai.pricing.TokenPricingCalculator;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 模型定价管理控制器
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/pricing")
@Tag(name = "ModelPricing", description = "模型定价管理API")
public class ModelPricingController {
    
    @Autowired
    private ModelPricingRepository modelPricingRepository;
    
    @Autowired
    private PricingDataSyncService pricingDataSyncService;
    
    @Autowired
    private List<TokenPricingCalculator> pricingCalculators;
    
    /**
     * 获取所有模型定价信息
     */
    @GetMapping
    @Operation(summary = "获取所有模型定价信息")
    public Mono<ResponseEntity<ApiResponse<List<ModelPricing>>>> getAllPricing() {
        return modelPricingRepository.findByActiveTrue()
                .collectList()
                .map(pricingList -> ResponseEntity.ok(ApiResponse.success(pricingList)))
                .doOnSuccess(response -> log.info("Retrieved {} pricing records", 
                        response.getBody().getData().size()));
    }
    
    /**
     * 根据提供商获取定价信息
     */
    @GetMapping("/provider/{provider}")
    @Operation(summary = "根据提供商获取定价信息")
    public Mono<ResponseEntity<ApiResponse<List<ModelPricing>>>> getPricingByProvider(
            @Parameter(description = "提供商名称") @PathVariable String provider) {
        return modelPricingRepository.findByProviderAndActiveTrue(provider)
                .collectList()
                .map(pricingList -> ResponseEntity.ok(ApiResponse.success(pricingList)))
                .doOnSuccess(response -> log.info("Retrieved {} pricing records for provider {}", 
                        response.getBody().getData().size(), provider));
    }
    
    /**
     * 获取特定模型的定价信息
     */
    @GetMapping("/provider/{provider}/model/{modelId}")
    @Operation(summary = "获取特定模型的定价信息")
    public Mono<ResponseEntity<ApiResponse<ModelPricing>>> getModelPricing(
            @Parameter(description = "提供商名称") @PathVariable String provider,
            @Parameter(description = "模型ID") @PathVariable String modelId) {
        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(provider, modelId)
                .map(pricing -> ResponseEntity.ok(ApiResponse.success(pricing)))
                .switchIfEmpty(Mono.just(ResponseEntity.notFound().build()));
    }
    
    /**
     * 计算Token成本
     */
    @PostMapping("/calculate")
    @Operation(summary = "计算Token成本")
    public Mono<ResponseEntity<ApiResponse<CostCalculationResult>>> calculateCost(
            @RequestBody CostCalculationRequest request) {
        
        // 查找对应的计算器
        TokenPricingCalculator calculator = pricingCalculators.stream()
                .filter(calc -> calc.getProviderName().equals(request.getProvider()))
                .findFirst()
                .orElse(null);
        
        if (calculator == null) {
            return Mono.just(ResponseEntity.badRequest()
                    .body(ApiResponse.error("不支持的提供商: " + request.getProvider())));
        }
        
        return calculator.calculateInputCost(request.getModelId(), request.getInputTokens())
                .zipWith(calculator.calculateOutputCost(request.getModelId(), request.getOutputTokens()))
                .zipWith(calculator.calculateTotalCost(request.getModelId(), 
                        request.getInputTokens(), request.getOutputTokens()))
                .map(tuple -> {
                    BigDecimal inputCost = tuple.getT1().getT1();
                    BigDecimal outputCost = tuple.getT1().getT2();
                    BigDecimal totalCost = tuple.getT2();
                    
                    CostCalculationResult result = new CostCalculationResult();
                    result.setProvider(request.getProvider());
                    result.setModelId(request.getModelId());
                    result.setInputTokens(request.getInputTokens());
                    result.setOutputTokens(request.getOutputTokens());
                    result.setInputCost(inputCost);
                    result.setOutputCost(outputCost);
                    result.setTotalCost(totalCost);
                    
                    return ResponseEntity.ok(ApiResponse.success(result));
                });
    }
    
    /**
     * 同步提供商定价信息
     */
    @PostMapping("/sync/{provider}")
    @Operation(summary = "同步提供商定价信息")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<PricingDataSyncService.PricingSyncResult>>> syncProviderPricing(
            @Parameter(description = "提供商名称") @PathVariable String provider) {
        return pricingDataSyncService.syncProviderPricing(provider)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .doOnSuccess(response -> log.info("Sync completed for provider {}: {}", 
                        provider, response.getBody().getData()));
    }
    
    /**
     * 同步所有提供商定价信息
     */
    @PostMapping("/sync-all")
    @Operation(summary = "同步所有提供商定价信息")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<List<PricingDataSyncService.PricingSyncResult>>>> syncAllPricing() {
        return pricingDataSyncService.syncAllProvidersPricing()
                .collectList()
                .map(results -> ResponseEntity.ok(ApiResponse.success(results)))
                .doOnSuccess(response -> log.info("Sync completed for all providers: {} results", 
                        response.getBody().getData().size()));
    }
    
    /**
     * 创建或更新模型定价
     */
    @PutMapping
    @Operation(summary = "创建或更新模型定价")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<ModelPricing>>> upsertPricing(
            @RequestBody ModelPricing pricing) {
        return pricingDataSyncService.updateModelPricing(pricing)
                .map(savedPricing -> ResponseEntity.ok(ApiResponse.success(savedPricing)))
                .doOnSuccess(response -> log.info("Updated pricing for {}:{}", 
                        pricing.getProvider(), pricing.getModelId()));
    }
    
    /**
     * 批量更新模型定价
     */
    @PutMapping("/batch")
    @Operation(summary = "批量更新模型定价")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<PricingDataSyncService.PricingSyncResult>>> batchUpdatePricing(
            @RequestBody List<ModelPricing> pricingList) {
        return pricingDataSyncService.batchUpdatePricing(pricingList)
                .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
                .doOnSuccess(response -> log.info("Batch update completed: {}", 
                        response.getBody().getData()));
    }
    
    /**
     * 删除模型定价（软删除）
     */
    @DeleteMapping("/provider/{provider}/model/{modelId}")
    @Operation(summary = "删除模型定价")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<Void>>> deletePricing(
            @Parameter(description = "提供商名称") @PathVariable String provider,
            @Parameter(description = "模型ID") @PathVariable String modelId) {
        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(provider, modelId)
                .flatMap(pricing -> {
                    pricing.setActive(false);
                    pricing.setUpdatedAt(java.time.LocalDateTime.now());
                    return modelPricingRepository.save(pricing);
                })
                .then(Mono.just(ResponseEntity.ok(ApiResponse.<Void>success())))
                .switchIfEmpty(Mono.just(ResponseEntity.notFound().build()))
                .doOnSuccess(response -> log.info("Deleted pricing for {}:{}", provider, modelId));
    }
    
    /**
     * 搜索模型定价
     */
    @GetMapping("/search")
    @Operation(summary = "搜索模型定价")
    public Flux<ModelPricing> searchPricing(
            @Parameter(description = "最小价格") @RequestParam(required = false) Double minPrice,
            @Parameter(description = "最大价格") @RequestParam(required = false) Double maxPrice,
            @Parameter(description = "最小Token数") @RequestParam(required = false) Integer minTokens,
            @Parameter(description = "最大Token数") @RequestParam(required = false) Integer maxTokens,
            @Parameter(description = "提供商") @RequestParam(required = false) String provider) {
        
        Flux<ModelPricing> query = modelPricingRepository.findByActiveTrue();
        
        if (provider != null && !provider.trim().isEmpty()) {
            query = modelPricingRepository.findByProviderAndActiveTrue(provider);
        }
        
        if (minPrice != null && maxPrice != null) {
            query = modelPricingRepository.findByPriceRange(minPrice, maxPrice);
        }
        
        if (minTokens != null && maxTokens != null) {
            query = modelPricingRepository.findByTokenRange(minTokens, maxTokens);
        }
        
        return query.doOnNext(pricing -> log.debug("Found pricing: {}:{}", 
                pricing.getProvider(), pricing.getModelId()));
    }
    
    /**
     * 获取支持的提供商列表
     */
    @GetMapping("/providers")
    @Operation(summary = "获取支持的提供商列表")
    public Flux<String> getSupportedProviders() {
        return pricingDataSyncService.getSupportedProviders()
                .doOnNext(provider -> log.debug("Supported provider: {}", provider));
    }
    
    /**
     * 检查模型是否存在定价信息（用于公共模型创建时的验证）
     */
    @GetMapping("/check/{provider}/{modelId}")
    @Operation(summary = "检查模型定价是否存在")
    public Mono<ResponseEntity<ApiResponse<PricingCheckResult>>> checkPricingExists(
            @Parameter(description = "提供商名称") @PathVariable String provider,
            @Parameter(description = "模型ID") @PathVariable String modelId) {
        
        return modelPricingRepository.existsByProviderAndModelIdAndActiveTrue(provider, modelId)
                .flatMap(exists -> {
                    if (exists) {
                        // 直接找到定价
                        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(provider, modelId)
                                .map(pricing -> ResponseEntity.ok(ApiResponse.success(
                                        PricingCheckResult.found(pricing, "精确匹配"))));
                    } else {
                        // 尝试查找备选定价
                        return findFallbackPricingInfo(provider, modelId);
                    }
                })
                .doOnSuccess(response -> log.info("Pricing check for {}:{} - exists: {}", 
                        provider, modelId, response.getBody().getData().isExists()));
    }
    
    /**
     * 为公共模型创建缺失的定价信息
     */
    @PostMapping("/create-for-model")
    @Operation(summary = "为公共模型创建定价信息")
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<ResponseEntity<ApiResponse<ModelPricing>>> createPricingForModel(
            @RequestBody CreatePricingRequest request) {
        
        // 检查是否已存在
        return modelPricingRepository.existsByProviderAndModelIdAndActiveTrue(request.getProvider(), request.getModelId())
                .flatMap(exists -> {
                    if (exists) {
                        return Mono.just(ResponseEntity.badRequest()
                                .body(ApiResponse.<ModelPricing>error("定价信息已存在")));
                    }
                    
                    // 创建新定价
                    ModelPricing pricing = ModelPricing.builder()
                            .provider(request.getProvider())
                            .modelId(request.getModelId())
                            .modelName(request.getModelName() != null ? request.getModelName() : request.getModelId())
                            .inputPricePerThousandTokens(request.getInputPricePerThousandTokens())
                            .outputPricePerThousandTokens(request.getOutputPricePerThousandTokens())
                            .unifiedPricePerThousandTokens(request.getUnifiedPricePerThousandTokens())
                            .maxContextTokens(request.getMaxContextTokens())
                            .supportsStreaming(request.getSupportsStreaming() != null ? request.getSupportsStreaming() : true)
                            .description(request.getDescription())
                            .source(ModelPricing.PricingSource.MANUAL)
                            .createdAt(java.time.LocalDateTime.now())
                            .updatedAt(java.time.LocalDateTime.now())
                            .version(1)
                            .active(true)
                            .build();
                    
                    return modelPricingRepository.save(pricing)
                            .map(savedPricing -> ResponseEntity.ok(ApiResponse.success(savedPricing)));
                })
                .doOnSuccess(response -> log.info("Created pricing for {}:{}", 
                        request.getProvider(), request.getModelId()));
    }
    
    /**
     * 查找备选定价信息（用于检查）
     */
    private Mono<ResponseEntity<ApiResponse<PricingCheckResult>>> findFallbackPricingInfo(String provider, String modelId) {
        // 查找相同模型ID的其他提供商定价
        return modelPricingRepository.findByModelIdAndActiveTrue(modelId)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .map(fallbackPricing -> ResponseEntity.ok(ApiResponse.success(
                        PricingCheckResult.fallbackFound(fallbackPricing, "相同模型ID"))))
                // 尝试模型名称匹配
                .switchIfEmpty(modelPricingRepository.findByModelNameAndActiveTrue(modelId)
                        .filter(pricing -> !provider.equals(pricing.getProvider()))
                        .next()
                        .map(fallbackPricing -> ResponseEntity.ok(ApiResponse.success(
                                PricingCheckResult.fallbackFound(fallbackPricing, "相同模型名称")))))
                // 尝试前缀匹配
                .switchIfEmpty(findByPrefixForCheck(provider, modelId))
                // 如果都没找到
                .switchIfEmpty(Mono.just(ResponseEntity.ok(ApiResponse.success(
                        PricingCheckResult.notFound()))));
    }
    
    /**
     * 前缀匹配查找（用于检查）
     */
    private Mono<ResponseEntity<ApiResponse<PricingCheckResult>>> findByPrefixForCheck(String provider, String modelId) {
        String prefix = extractModelPrefix(modelId);
        if (prefix.length() < 3) {
            return Mono.empty();
        }
        
        return modelPricingRepository.findByModelIdStartingWithIgnoreCase(prefix)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .map(fallbackPricing -> ResponseEntity.ok(ApiResponse.success(
                        PricingCheckResult.fallbackFound(fallbackPricing, "前缀匹配: " + prefix))));
    }
    
    /**
     * 提取模型前缀（复用CreditServiceImpl的逻辑）
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
     * 成本计算请求
     */
    @Data
    public static class CostCalculationRequest {
        private String provider;
        private String modelId;
        private int inputTokens;
        private int outputTokens;
    }
    
    /**
     * 成本计算结果
     */
    @Data
    public static class CostCalculationResult {
        private String provider;
        private String modelId;
        private int inputTokens;
        private int outputTokens;
        private BigDecimal inputCost;
        private BigDecimal outputCost;
        private BigDecimal totalCost;
        
        public String getFormattedTotalCost() {
            return String.format("$%.6f", totalCost);
        }
        
        public String getFormattedInputCost() {
            return String.format("$%.6f", inputCost);
        }
        
        public String getFormattedOutputCost() {
            return String.format("$%.6f", outputCost);
        }
    }
    
    /**
     * 定价检查结果
     */
    @Data
    public static class PricingCheckResult {
        private boolean exists;
        private String status; // "found", "fallback_available", "not_found"
        private String message;
        private ModelPricing exactPricing;
        private ModelPricing fallbackPricing;
        private String fallbackReason;
        
        public static PricingCheckResult found(ModelPricing pricing, String message) {
            PricingCheckResult result = new PricingCheckResult();
            result.exists = true;
            result.status = "found";
            result.message = message;
            result.exactPricing = pricing;
            return result;
        }
        
        public static PricingCheckResult fallbackFound(ModelPricing fallbackPricing, String reason) {
            PricingCheckResult result = new PricingCheckResult();
            result.exists = false;
            result.status = "fallback_available";
            result.message = "未找到精确匹配，但有可用备选方案：" + reason;
            result.fallbackPricing = fallbackPricing;
            result.fallbackReason = reason;
            return result;
        }
        
        public static PricingCheckResult notFound() {
            PricingCheckResult result = new PricingCheckResult();
            result.exists = false;
            result.status = "not_found";
            result.message = "未找到任何定价信息";
            return result;
        }
    }
    
    /**
     * 创建定价请求
     */
    @Data
    public static class CreatePricingRequest {
        private String provider;
        private String modelId;
        private String modelName;
        private Double inputPricePerThousandTokens;
        private Double outputPricePerThousandTokens;
        private Double unifiedPricePerThousandTokens;
        private Integer maxContextTokens;
        private Boolean supportsStreaming;
        private String description;
    }
}