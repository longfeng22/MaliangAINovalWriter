package com.ainovel.server.service.ai.langchain4j;

import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.capability.ProviderCapabilityDetector;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;
import com.ainovel.server.service.ai.pricing.TokenPricingCalculator;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;

/**
 * 统一的模型提供商基类
 * 自动从CapabilityDetector和PricingCalculator获取模型数据，避免重复定义
 */
@Slf4j
public abstract class AbstractUnifiedModelProvider extends LangChain4jModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private ProviderCapabilityDetector capabilityDetector;
    private TokenPricingCalculator pricingCalculator;

    public AbstractUnifiedModelProvider(String providerName, String modelName, String apiKey, 
                                      String apiEndpoint, ProxyConfig proxyConfig, 
                                      ChatModelListenerManager listenerManager) {
        super(providerName, modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    /**
     * 获取统一的默认模型列表
     * 从CapabilityDetector获取基础信息，从PricingCalculator获取价格信息
     */
    protected List<ModelInfo> getUnifiedDefaultModels() {
        try {
            // 懒加载获取相关服务
            if (capabilityDetector == null) {
                capabilityDetector = getCapabilityDetector();
            }
            if (pricingCalculator == null) {
                pricingCalculator = getPricingCalculator();
            }

            if (capabilityDetector == null) {
                log.warn("未找到 {} 的CapabilityDetector，使用空列表", providerName);
                return List.of();
            }

            // 从CapabilityDetector获取默认模型
            List<ModelInfo> models = capabilityDetector.getDefaultModels().collectList().block();
            if (models == null || models.isEmpty()) {
                log.warn("CapabilityDetector返回空模型列表: {}", providerName);
                return List.of();
            }

            // 如果有PricingCalculator，尝试补充价格信息
            if (pricingCalculator != null) {
                for (ModelInfo model : models) {
                    try {
                        // 尝试获取定价信息
                        var inputPrice = pricingCalculator.getInputPricePerThousandTokens(model.getId()).block();
                        var outputPrice = pricingCalculator.getOutputPricePerThousandTokens(model.getId()).block();
                        
                        if (inputPrice != null && outputPrice != null) {
                            // 更新模型价格信息
                            Map<String, Double> pricing = model.getPricing();
                            if (pricing != null) {
                                pricing.put("input", inputPrice.doubleValue());
                                pricing.put("output", outputPrice.doubleValue());
                            } else {
                                model.withInputPrice(inputPrice.doubleValue())
                                     .withOutputPrice(outputPrice.doubleValue());
                            }
                        }
                    } catch (Exception e) {
                        log.debug("无法获取模型 {} 的定价信息: {}", model.getId(), e.getMessage());
                    }
                }
            }

            log.debug("获取到 {} 个 {} 模型", models.size(), providerName);
            return models;
            
        } catch (Exception e) {
            log.error("获取统一默认模型列表失败: {}", e.getMessage(), e);
            return List.of();
        }
    }

    /**
     * 获取CapabilityDetector
     */
    private ProviderCapabilityDetector getCapabilityDetector() {
        try {
            Map<String, ProviderCapabilityDetector> detectors = 
                applicationContext.getBeansOfType(ProviderCapabilityDetector.class);
            
            for (ProviderCapabilityDetector detector : detectors.values()) {
                if (providerName.equals(detector.getProviderName())) {
                    return detector;
                }
            }
        } catch (Exception e) {
            log.debug("获取CapabilityDetector失败: {}", e.getMessage());
        }
        return null;
    }

    /**
     * 获取PricingCalculator
     */
    private TokenPricingCalculator getPricingCalculator() {
        try {
            Map<String, TokenPricingCalculator> calculators = 
                applicationContext.getBeansOfType(TokenPricingCalculator.class);
            
            for (TokenPricingCalculator calculator : calculators.values()) {
                if (providerName.equals(calculator.getProviderName())) {
                    return calculator;
                }
            }
        } catch (Exception e) {
            log.debug("获取PricingCalculator失败: {}", e.getMessage());
        }
        return null;
    }

    /**
     * 统一的模型列表获取方法
     * 子类可以重写此方法来自定义逻辑，但默认使用统一的数据源
     */
    @Override
    public Flux<ModelInfo> listModelsWithApiKey(String apiKey, String apiEndpoint) {
        if (isApiKeyEmpty(apiKey)) {
            return Flux.error(new RuntimeException("API密钥不能为空"));
        }

        // 先尝试调用API获取模型列表
        return callApiForModels(apiKey, apiEndpoint)
                .switchIfEmpty(Flux.fromIterable(getUnifiedDefaultModels()))
                .onErrorResume(e -> {
                    log.warn("调用API获取模型列表失败，使用默认列表: {}", e.getMessage());
                    return Flux.fromIterable(getUnifiedDefaultModels());
                });
    }

    /**
     * 调用API获取模型列表的抽象方法
     * 子类需要实现具体的API调用逻辑
     */
    protected abstract Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint);
}
