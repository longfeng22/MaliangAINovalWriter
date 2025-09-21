package com.ainovel.server.domain.model;

import java.time.LocalDateTime;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * AI模型定价信息实体
 * 用于存储各个提供商的模型定价数据
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "model_pricing")
public class ModelPricing {
    
    @Id
    private String id;
    
    /**
     * 提供商名称
     */
    @Indexed
    private String provider;
    
    /**
     * 模型ID
     */
    @Indexed
    private String modelId;
    
    /**
     * 模型名称
     */
    private String modelName;
    
    /**
     * 输入token价格（每1000个token的美元价格）
     */
    private Double inputPricePerThousandTokens;
    
    /**
     * 输出token价格（每1000个token的美元价格）
     */
    private Double outputPricePerThousandTokens;
    
    /**
     * 统一价格（如果输入输出使用相同价格）
     */
    private Double unifiedPricePerThousandTokens;
    
    /**
     * 最大上下文token数
     */
    private Integer maxContextTokens;
    
    /**
     * 是否支持流式输出
     */
    private Boolean supportsStreaming;
    
    /**
     * 模型描述
     */
    private String description;
    
    /**
     * 额外的定价信息（如训练价格、批处理价格等）
     */
    @Builder.Default
    private Map<String, Double> additionalPricing = new java.util.HashMap<>();
    
    /**
     * 定价数据来源
     */
    private PricingSource source;
    
    /**
     * 定价数据创建时间
     */
    private LocalDateTime createdAt;
    
    /**
     * 定价数据更新时间
     */
    private LocalDateTime updatedAt;
    
    /**
     * 定价数据版本号
     */
    private Integer version;
    
    /**
     * 是否激活
     */
    @Builder.Default
    private Boolean active = true;
    
    /**
     * 定价数据来源枚举
     */
    public enum PricingSource {
        /**
         * 官方API获取
         */
        OFFICIAL_API,
        
        /**
         * 手动配置
         */
        MANUAL,
        
        /**
         * 网页爬取
         */
        WEB_SCRAPING,
        
        /**
         * 默认配置
         */
        DEFAULT
    }
    
    /**
     * 计算输入token成本
     * 
     * @param tokenCount token数量
     * @return 成本（美元）
     */
    public double calculateInputCost(int tokenCount) {
        if (unifiedPricePerThousandTokens != null) {
            return (tokenCount / 1000.0) * unifiedPricePerThousandTokens;
        }
        if (inputPricePerThousandTokens != null) {
            return (tokenCount / 1000.0) * inputPricePerThousandTokens;
        }
        return 0.0;
    }
    
    /**
     * 计算输出token成本
     * 
     * @param tokenCount token数量
     * @return 成本（美元）
     */
    public double calculateOutputCost(int tokenCount) {
        if (unifiedPricePerThousandTokens != null) {
            return (tokenCount / 1000.0) * unifiedPricePerThousandTokens;
        }
        if (outputPricePerThousandTokens != null) {
            return (tokenCount / 1000.0) * outputPricePerThousandTokens;
        }
        return 0.0;
    }
    
    /**
     * 计算总成本
     * 
     * @param inputTokens 输入token数量
     * @param outputTokens 输出token数量
     * @return 总成本（美元）
     */
    public double calculateTotalCost(int inputTokens, int outputTokens) {
        return calculateInputCost(inputTokens) + calculateOutputCost(outputTokens);
    }
    
    /**
     * 转换为ModelInfo对象
     * 
     * @return ModelInfo对象
     */
    public ModelInfo toModelInfo() {
        ModelInfo.ModelInfoBuilder builder = ModelInfo.builder()
                .id(modelId)
                .name(modelName)
                .provider(provider)
                .description(description)
                .maxTokens(maxContextTokens)
                .supportsStreaming(supportsStreaming);
        
        if (unifiedPricePerThousandTokens != null) {
            builder.pricing(Map.of("unified", unifiedPricePerThousandTokens));
        } else {
            Map<String, Double> pricing = new java.util.HashMap<>();
            if (inputPricePerThousandTokens != null) {
                pricing.put("input", inputPricePerThousandTokens);
            }
            if (outputPricePerThousandTokens != null) {
                pricing.put("output", outputPricePerThousandTokens);
            }
            if (additionalPricing != null) {
                pricing.putAll(additionalPricing);
            }
            builder.pricing(pricing);
        }
        
        return builder.build();
    }
}