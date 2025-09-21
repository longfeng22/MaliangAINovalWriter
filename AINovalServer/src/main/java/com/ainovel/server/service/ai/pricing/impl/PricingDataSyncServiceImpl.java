package com.ainovel.server.service.ai.pricing.impl;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.repository.ModelPricingRepository;
import com.ainovel.server.service.ai.pricing.PricingDataSyncService;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 定价数据同步服务实现
 */
@Slf4j
@Service
public class PricingDataSyncServiceImpl implements PricingDataSyncService {
    
    @Autowired
    private ModelPricingRepository modelPricingRepository;
    
    @Autowired(required = false)
    private OpenAITokenPricingCalculator openAICalculator;
    
    @Autowired(required = false)
    private AnthropicTokenPricingCalculator anthropicCalculator;
    
    @Autowired(required = false)
    private GeminiTokenPricingCalculator geminiCalculator;
    
    @Autowired(required = false)
    private GrokTokenPricingCalculator grokCalculator;
    
    @Autowired(required = false)
    private DoubaoTokenPricingCalculator doubaoCalculator;
    
    @Autowired(required = false)
    private ZhipuTokenPricingCalculator zhipuCalculator;
    
    @Autowired(required = false)
    private QwenTokenPricingCalculator qwenCalculator;
    
    /**
     * 支持自动同步的提供商映射
     */
    private final Map<String, Boolean> supportedProviders = new java.util.LinkedHashMap<>() {{
            put("openai", true);
            put("anthropic", false);
            put("gemini", false);
            put("grok", false);
            put("doubao", false);
            put("zhipu", false);
            put("qwen", false);
    }};
    
    /**
     * 同步状态缓存
     */
    private final Map<String, Instant> lastSyncTime = new ConcurrentHashMap<>();
    
    @Override
    public Mono<PricingSyncResult> syncProviderPricing(String provider) {
        Instant startTime = Instant.now();
        log.info("Starting pricing sync for provider: {}", provider);
        
        return switch (provider.toLowerCase()) {
            case "openai" -> syncOpenAIPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync OpenAI pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "anthropic" -> syncAnthropicPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Anthropic pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "gemini" -> syncGeminiPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Gemini pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "grok" -> syncGrokPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Grok pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "doubao" -> syncDoubaoPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Doubao pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "zhipu" -> syncZhipuPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Zhipu pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            case "qwen" -> syncQwenPricing()
                    .map(pricingList -> createSuccessResult(provider, pricingList.size(), startTime))
                    .onErrorResume(error -> {
                        log.error("Failed to sync Qwen pricing", error);
                        return Mono.just(createFailureResult(provider, List.of(error.getMessage()), startTime));
                    });
            
            default -> {
                String errorMsg = "Unsupported provider: " + provider;
                log.warn(errorMsg);
                yield Mono.just(createFailureResult(provider, List.of(errorMsg), startTime));
            }
        };
    }
    
    @Override
    public Flux<PricingSyncResult> syncAllProvidersPricing() {
        log.info("Starting pricing sync for all providers");
        
        return Flux.fromIterable(supportedProviders.keySet())
                .flatMap(this::syncProviderPricing)
                .doOnNext(result -> {
                    lastSyncTime.put(result.provider(), Instant.now());
                    log.info("Completed sync for provider {}: success={}, total={}", 
                            result.provider(), result.successCount(), result.totalModels());
                });
    }
    
    @Override
    public Mono<Boolean> isAutoSyncSupported(String provider) {
        return Mono.just(supportedProviders.getOrDefault(provider.toLowerCase(), false));
    }
    
    @Override
    public Flux<String> getSupportedProviders() {
        return Flux.fromIterable(supportedProviders.keySet());
    }
    
    @Override
    public Mono<ModelPricing> updateModelPricing(ModelPricing pricing) {
        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(
                pricing.getProvider(), pricing.getModelId())
                .flatMap(existing -> {
                    // 更新现有记录
                    existing.setInputPricePerThousandTokens(pricing.getInputPricePerThousandTokens());
                    existing.setOutputPricePerThousandTokens(pricing.getOutputPricePerThousandTokens());
                    existing.setUnifiedPricePerThousandTokens(pricing.getUnifiedPricePerThousandTokens());
                    existing.setMaxContextTokens(pricing.getMaxContextTokens());
                    existing.setSupportsStreaming(pricing.getSupportsStreaming());
                    existing.setDescription(pricing.getDescription());
                    existing.setAdditionalPricing(pricing.getAdditionalPricing());
                    existing.setSource(ModelPricing.PricingSource.MANUAL);
                    existing.setUpdatedAt(java.time.LocalDateTime.now());
                    existing.setVersion(existing.getVersion() + 1);
                    return modelPricingRepository.save(existing);
                })
                .switchIfEmpty(
                    // 创建新记录
                    Mono.defer(() -> {
                        pricing.setSource(ModelPricing.PricingSource.MANUAL);
                        pricing.setCreatedAt(java.time.LocalDateTime.now());
                        pricing.setUpdatedAt(java.time.LocalDateTime.now());
                        pricing.setVersion(1);
                        pricing.setActive(true);
                        return modelPricingRepository.save(pricing);
                    })
                );
    }
    
    @Override
    public Mono<PricingSyncResult> batchUpdatePricing(List<ModelPricing> pricingList) {
        Instant startTime = Instant.now();
        
        return Flux.fromIterable(pricingList)
                .flatMap(this::updateModelPricing)
                .collectList()
                .map(updatedList -> createSuccessResult("batch", updatedList.size(), startTime))
                .onErrorResume(error -> {
                    log.error("Failed to batch update pricing", error);
                    return Mono.just(createFailureResult("batch", List.of(error.getMessage()), startTime));
                });
    }
    
    /**
     * 同步OpenAI定价
     */
    private Mono<List<ModelPricing>> syncOpenAIPricing() {
        if (openAICalculator == null) {
            return Mono.just(List.of());
        }
        // 这里可以传入实际的API密钥，或者从配置中获取
        // 目前使用默认定价
        return openAICalculator.getDefaultOpenAIPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    /**
     * 同步Anthropic定价
     */
    private Mono<List<ModelPricing>> syncAnthropicPricing() {
        if (anthropicCalculator == null) {
            return Mono.just(List.of());
        }
        return anthropicCalculator.getDefaultAnthropicPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    /**
     * 同步Gemini定价
     */
    private Mono<List<ModelPricing>> syncGeminiPricing() {
        if (geminiCalculator == null) {
            return Mono.just(List.of());
        }
        return geminiCalculator.getDefaultGeminiPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    /**
     * 同步Grok定价
     */
    private Mono<List<ModelPricing>> syncGrokPricing() {
        if (grokCalculator == null) {
            return Mono.just(List.of());
        }
        return grokCalculator.getDefaultGrokPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    private Mono<List<ModelPricing>> syncDoubaoPricing() {
        if (doubaoCalculator == null) {
            return Mono.just(List.of());
        }
        return doubaoCalculator.getDefaultDoubaoPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    private Mono<List<ModelPricing>> syncZhipuPricing() {
        if (zhipuCalculator == null) {
            return Mono.just(List.of());
        }
        return zhipuCalculator.getDefaultZhipuPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    private Mono<List<ModelPricing>> syncQwenPricing() {
        if (qwenCalculator == null) {
            return Mono.just(List.of());
        }
        return qwenCalculator.getDefaultQwenPricing()
                .flatMap(pricingList -> 
                    Flux.fromIterable(pricingList)
                            .flatMap(this::saveOrUpdatePricing)
                            .collectList()
                );
    }
    
    /**
     * 保存或更新定价信息
     */
    private Mono<ModelPricing> saveOrUpdatePricing(ModelPricing pricing) {
        return modelPricingRepository.findByProviderAndModelIdAndActiveTrue(
                pricing.getProvider(), pricing.getModelId())
                .flatMap(existing -> {
                    // 只有当价格有变化时才更新
                    if (isPricingChanged(existing, pricing)) {
                        existing.setInputPricePerThousandTokens(pricing.getInputPricePerThousandTokens());
                        existing.setOutputPricePerThousandTokens(pricing.getOutputPricePerThousandTokens());
                        existing.setUnifiedPricePerThousandTokens(pricing.getUnifiedPricePerThousandTokens());
                        existing.setMaxContextTokens(pricing.getMaxContextTokens());
                        existing.setSupportsStreaming(pricing.getSupportsStreaming());
                        existing.setDescription(pricing.getDescription());
                        existing.setAdditionalPricing(pricing.getAdditionalPricing());
                        existing.setUpdatedAt(java.time.LocalDateTime.now());
                        existing.setVersion(existing.getVersion() + 1);
                        return modelPricingRepository.save(existing);
                    } else {
                        return Mono.just(existing);
                    }
                })
                .switchIfEmpty(
                    // 创建新记录
                    Mono.defer(() -> {
                        pricing.setCreatedAt(java.time.LocalDateTime.now());
                        pricing.setUpdatedAt(java.time.LocalDateTime.now());
                        pricing.setVersion(1);
                        pricing.setActive(true);
                        return modelPricingRepository.save(pricing);
                    })
                );
    }
    
    /**
     * 检查定价是否有变化
     */
    private boolean isPricingChanged(ModelPricing existing, ModelPricing newPricing) {
        return !java.util.Objects.equals(existing.getInputPricePerThousandTokens(), 
                newPricing.getInputPricePerThousandTokens()) ||
               !java.util.Objects.equals(existing.getOutputPricePerThousandTokens(), 
                newPricing.getOutputPricePerThousandTokens()) ||
               !java.util.Objects.equals(existing.getUnifiedPricePerThousandTokens(), 
                newPricing.getUnifiedPricePerThousandTokens()) ||
               !java.util.Objects.equals(existing.getMaxContextTokens(), 
                newPricing.getMaxContextTokens());
    }
    
    /**
     * 创建成功结果
     */
    private PricingSyncResult createSuccessResult(String provider, int count, Instant startTime) {
        long duration = Duration.between(startTime, Instant.now()).toMillis();
        return PricingSyncResult.success(provider, count, duration);
    }
    
    /**
     * 创建失败结果
     */
    private PricingSyncResult createFailureResult(String provider, List<String> errors, Instant startTime) {
        long duration = Duration.between(startTime, Instant.now()).toMillis();
        return PricingSyncResult.failure(provider, errors, duration);
    }
    
    /**
     * 获取上次同步时间
     * 
     * @param provider 提供商名称
     * @return 上次同步时间
     */
    public Instant getLastSyncTime(String provider) {
        return lastSyncTime.get(provider);
    }
    
    /**
     * 清理同步状态
     */
    public void clearSyncState() {
        lastSyncTime.clear();
    }
}