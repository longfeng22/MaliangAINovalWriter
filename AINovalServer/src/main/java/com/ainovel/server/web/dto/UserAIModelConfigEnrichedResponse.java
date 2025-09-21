package com.ainovel.server.web.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.LocalDateTime;
import java.util.Map;

/**
 * 带价格与标签信息的用户AI模型配置响应DTO
 * 在原有 UserAIModelConfigResponse 字段基础上，追加模型的价格、标签、描述等信息
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record UserAIModelConfigEnrichedResponse(
        String id,
        String userId,
        String provider,
        String modelName,
        String alias,
        String apiEndpoint,
        Boolean isValidated,
        Boolean isDefault,
        Boolean isToolDefault,
        LocalDateTime createdAt,
        LocalDateTime updatedAt,
        String apiKey,
        // 模型信息增强字段
        Double inputPricePerThousandTokens,
        Double outputPricePerThousandTokens,
        Double unifiedPricePerThousandTokens,
        Integer maxContextTokens,
        String description,
        Map<String, Object> properties
) {}


