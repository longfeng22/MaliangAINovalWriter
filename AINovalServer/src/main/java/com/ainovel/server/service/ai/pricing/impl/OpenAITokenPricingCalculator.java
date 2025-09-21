package com.ainovel.server.service.ai.pricing.impl;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.service.ai.pricing.AbstractTokenPricingCalculator;
import com.fasterxml.jackson.annotation.JsonProperty;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * OpenAI Token定价计算器
 * 支持从OpenAI官方API获取最新定价信息
 */
@Slf4j
@Component
public class OpenAITokenPricingCalculator extends AbstractTokenPricingCalculator {
    
    private static final String PROVIDER_NAME = "openai";
    private static final String OPENAI_API_BASE = "https://api.openai.com/v1";
    // kept for potential future pricing endpoints
    // private static final String PRICING_INFO_URL = OPENAI_API_BASE + "/models";
    
    @Override
    public String getProviderName() {
        return PROVIDER_NAME;
    }
    
    /**
     * 从OpenAI API同步定价信息
     * 
     * @param apiKey OpenAI API密钥
     * @return 同步结果
     */
    public Mono<List<ModelPricing>> syncPricingFromAPI(String apiKey) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            log.warn("OpenAI API key is not provided, using default pricing");
            return getDefaultOpenAIPricing();
        }
        
        WebClient webClient = WebClient.builder()
                .baseUrl(OPENAI_API_BASE)
                .build();
        
        return webClient.get()
                .uri("/models")
                .header("Authorization", "Bearer " + apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(OpenAIModelsResponse.class)
                .map(response -> response.getData().stream()
                        .filter(model -> isMainModel(model.getId()))
                        .map(this::convertToModelPricing)
                        .toList())
                .doOnSuccess(pricingList -> log.info("Successfully fetched {} OpenAI models", pricingList.size()))
                .onErrorResume(error -> {
                    log.error("Failed to fetch OpenAI models from API: {}", error.getMessage());
                    return getDefaultOpenAIPricing();
                });
    }
    
    /**
     * 检查是否为主要模型（过滤掉已废弃或特殊用途模型）
     * 
     * @param modelId 模型ID
     * @return 是否为主要模型
     */
    private boolean isMainModel(String modelId) {
        return modelId.startsWith("gpt-3.5") || 
               modelId.startsWith("gpt-4") || 
               modelId.contains("turbo") ||
               modelId.contains("davinci") ||
               modelId.contains("curie") ||
               modelId.contains("babbage") ||
               modelId.contains("ada");
    }
    
    /**
     * 转换OpenAI模型信息为定价信息
     * 
     * @param model OpenAI模型信息
     * @return 定价信息
     */
    private ModelPricing convertToModelPricing(OpenAIModel model) {
        // 根据模型ID获取对应的定价信息
        Map<String, Double> pricing = getKnownModelPricing(model.getId());
        
        return ModelPricing.builder()
                .provider(PROVIDER_NAME)
                .modelId(model.getId())
                .modelName(model.getId()) // OpenAI使用ID作为名称
                .inputPricePerThousandTokens(pricing.get("input"))
                .outputPricePerThousandTokens(pricing.get("output"))
                .maxContextTokens(getKnownModelContextLength(model.getId()))
                .supportsStreaming(true)
                .description("OpenAI " + model.getId() + " model")
                .source(ModelPricing.PricingSource.OFFICIAL_API)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .version(1)
                .active(true)
                .build();
    }
    
    /**
     * 获取已知模型的定价信息
     * 
     * @param modelId 模型ID
     * @return 定价信息Map (input, output)
     */
    private Map<String, Double> getKnownModelPricing(String modelId) {
        return switch (modelId) {
            // GPT-5 family
            case "gpt-5", "gpt-5-chat-latest" -> Map.of("input", 0.00125, "output", 0.01000);
            case "gpt-5-mini" -> Map.of("input", 0.00025, "output", 0.00200);
            case "gpt-5-nano" -> Map.of("input", 0.00005, "output", 0.00040);

            // GPT-4.1
            case "gpt-4.1" -> Map.of("input", 0.00200, "output", 0.00800);
            case "gpt-4.1-mini" -> Map.of("input", 0.00040, "output", 0.00160);
            case "gpt-4.1-nano" -> Map.of("input", 0.00010, "output", 0.00040);

            // GPT-4o
            case "gpt-4o" -> Map.of("input", 0.00250, "output", 0.01000);
            case "gpt-4o-2024-05-13" -> Map.of("input", 0.00500, "output", 0.01500);
            case "gpt-4o-mini" -> Map.of("input", 0.00015, "output", 0.00060);

            // Realtime / Audio
            case "gpt-realtime" -> Map.of("input", 0.00400, "output", 0.01600);
            case "gpt-4o-realtime-preview" -> Map.of("input", 0.00500, "output", 0.02000);
            case "gpt-4o-mini-realtime-preview" -> Map.of("input", 0.00060, "output", 0.00240);
            case "gpt-audio" -> Map.of("input", 0.00250, "output", 0.01000);
            case "gpt-4o-audio-preview" -> Map.of("input", 0.00250, "output", 0.01000);
            case "gpt-4o-mini-audio-preview" -> Map.of("input", 0.00015, "output", 0.00060);

            // o 系列
            case "o1" -> Map.of("input", 0.01500, "output", 0.06000);
            case "o1-pro" -> Map.of("input", 0.15000, "output", 0.60000);
            case "o3-pro" -> Map.of("input", 0.02000, "output", 0.08000);
            case "o3" -> Map.of("input", 0.00200, "output", 0.00800);
            case "o3-deep-research" -> Map.of("input", 0.01000, "output", 0.04000);
            case "o4-mini" -> Map.of("input", 0.00110, "output", 0.00440);
            case "o4-mini-deep-research" -> Map.of("input", 0.00200, "output", 0.00800);
            case "o3-mini" -> Map.of("input", 0.00110, "output", 0.00440);
            case "o1-mini" -> Map.of("input", 0.00110, "output", 0.00440);

            // Deprecated/legacy fallbacks (kept for compatibility)
            case "gpt-3.5-turbo", "gpt-3.5-turbo-0125" -> Map.of("input", 0.0005, "output", 0.0015);
            case "gpt-3.5-turbo-instruct" -> Map.of("input", 0.0015, "output", 0.0020);
            case "gpt-4", "gpt-4-0613" -> Map.of("input", 0.0300, "output", 0.0600);
            case "gpt-4-32k", "gpt-4-32k-0613" -> Map.of("input", 0.0600, "output", 0.1200);
            case "gpt-4-turbo", "gpt-4-turbo-2024-04-09" -> Map.of("input", 0.0100, "output", 0.0300);
            case "gpt-4o-vision-preview", "gpt-4-vision-preview" -> Map.of("input", 0.0100, "output", 0.0300);
            default -> Map.of("input", 0.002, "output", 0.002);
        };
    }
    
    /**
     * 获取已知模型的上下文长度
     * 
     * @param modelId 模型ID
     * @return 上下文长度
     */
    private Integer getKnownModelContextLength(String modelId) {
        return switch (modelId) {
            case "gpt-3.5-turbo", "gpt-3.5-turbo-0125" -> 16385;
            case "gpt-3.5-turbo-instruct" -> 4096;
            case "gpt-4", "gpt-4-0613" -> 8192;
            case "gpt-4-32k", "gpt-4-32k-0613" -> 32768;
            case "gpt-4-turbo", "gpt-4-turbo-2024-04-09" -> 128000;
            case "gpt-4o", "gpt-4o-2024-05-13", "gpt-4o-mini", "gpt-4o-mini-2024-07-18" -> 128000;
            case "gpt-4-vision-preview" -> 128000;
            default -> 4096; // 默认上下文长度
        };
    }
    
    /**
     * 获取默认OpenAI定价信息
     * 
     * @return 默认定价信息列表
     */
    public Mono<List<ModelPricing>> getDefaultOpenAIPricing() {
        List<ModelPricing> defaultPricing = List.of(
                // GPT-5 family
                createDefaultPricing("gpt-5", "GPT-5", 0.00125, 0.01000, 128000),
                createDefaultPricing("gpt-5-mini", "GPT-5 Mini", 0.00025, 0.00200, 128000),
                createDefaultPricing("gpt-5-nano", "GPT-5 Nano", 0.00005, 0.00040, 128000),
                createDefaultPricing("gpt-5-chat-latest", "GPT-5 Chat Latest", 0.00125, 0.01000, 128000),

                // GPT-4.1
                createDefaultPricing("gpt-4.1", "GPT-4.1", 0.00200, 0.00800, 128000),
                createDefaultPricing("gpt-4.1-mini", "GPT-4.1 Mini", 0.00040, 0.00160, 128000),
                createDefaultPricing("gpt-4.1-nano", "GPT-4.1 Nano", 0.00010, 0.00040, 128000),

                // GPT-4o
                createDefaultPricing("gpt-4o", "GPT-4o", 0.00250, 0.01000, 128000),
                createDefaultPricing("gpt-4o-2024-05-13", "GPT-4o 2024-05-13", 0.00500, 0.01500, 128000),
                createDefaultPricing("gpt-4o-mini", "GPT-4o Mini", 0.00015, 0.00060, 128000),

                // Realtime / Audio
                createDefaultPricing("gpt-realtime", "GPT Realtime", 0.00400, 0.01600, 128000),
                createDefaultPricing("gpt-4o-realtime-preview", "GPT-4o Realtime Preview", 0.00500, 0.02000, 128000),
                createDefaultPricing("gpt-4o-mini-realtime-preview", "GPT-4o Mini Realtime Preview", 0.00060, 0.00240, 128000),
                createDefaultPricing("gpt-audio", "GPT Audio", 0.00250, 0.01000, 128000),
                createDefaultPricing("gpt-4o-audio-preview", "GPT-4o Audio Preview", 0.00250, 0.01000, 128000),
                createDefaultPricing("gpt-4o-mini-audio-preview", "GPT-4o Mini Audio Preview", 0.00015, 0.00060, 128000),

                // o family
                createDefaultPricing("o1", "o1", 0.01500, 0.06000, 128000),
                createDefaultPricing("o1-pro", "o1 Pro", 0.15000, 0.60000, 128000),
                createDefaultPricing("o3-pro", "o3 Pro", 0.02000, 0.08000, 128000),
                createDefaultPricing("o3", "o3", 0.00200, 0.00800, 128000),
                createDefaultPricing("o3-deep-research", "o3 Deep Research", 0.01000, 0.04000, 128000),
                createDefaultPricing("o4-mini", "o4 Mini", 0.00110, 0.00440, 128000),
                createDefaultPricing("o4-mini-deep-research", "o4 Mini Deep Research", 0.00200, 0.00800, 128000),
                createDefaultPricing("o3-mini", "o3 Mini", 0.00110, 0.00440, 128000),
                createDefaultPricing("o1-mini", "o1 Mini", 0.00110, 0.00440, 128000)
        );
        
        return Mono.just(defaultPricing);
    }
    
    /**
     * 创建默认定价信息
     * 
     * @param modelId 模型ID
     * @param modelName 模型名称
     * @param inputPrice 输入价格
     * @param outputPrice 输出价格
     * @param maxTokens 最大token数
     * @return 定价信息
     */
    private ModelPricing createDefaultPricing(String modelId, String modelName, 
                                            double inputPrice, double outputPrice, int maxTokens) {
        return ModelPricing.builder()
                .provider(PROVIDER_NAME)
                .modelId(modelId)
                .modelName(modelName)
                .inputPricePerThousandTokens(inputPrice)
                .outputPricePerThousandTokens(outputPrice)
                .maxContextTokens(maxTokens)
                .supportsStreaming(true)
                .description("OpenAI " + modelName + " model")
                .source(ModelPricing.PricingSource.DEFAULT)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .version(1)
                .active(true)
                .build();
    }
    
    /**
     * OpenAI API响应结构
     */
    @Data
    private static class OpenAIModelsResponse {
        private String object;
        private List<OpenAIModel> data;
    }
    
    /**
     * OpenAI模型信息结构
     */
    @Data
    private static class OpenAIModel {
        private String id;
        private String object;
        private Long created;
        @JsonProperty("owned_by")
        private String ownedBy;
        private List<Permission> permission;
        private String root;
        private String parent;
    }
    
    /**
     * OpenAI模型权限结构
     */
    @Data
    private static class Permission {
        private String id;
        private String object;
        private Long created;
        @JsonProperty("allow_create_engine")
        private Boolean allowCreateEngine;
        @JsonProperty("allow_sampling")
        private Boolean allowSampling;
        @JsonProperty("allow_logprobs")
        private Boolean allowLogprobs;
        @JsonProperty("allow_search_indices")
        private Boolean allowSearchIndices;
        @JsonProperty("allow_view")
        private Boolean allowView;
        @JsonProperty("allow_fine_tuning")
        private Boolean allowFineTuning;
        private String organization;
        private String group;
        @JsonProperty("is_blocking")
        private Boolean isBlocking;
    }
}