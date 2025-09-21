package com.ainovel.server.web.dto;

import com.ainovel.server.domain.model.UserAIModelConfig;
import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.LocalDateTime;

/**
 * 用户AI模型配置响应DTO
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record UserAIModelConfigResponse(
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
        String apiKey // 添加apiKey字段，用于保存解密后的密钥
) {

    /**
     * 从实体创建响应DTO
     */
    public static UserAIModelConfigResponse fromEntity(UserAIModelConfig entity) {
        return new UserAIModelConfigResponse(
                entity.getId(),
                entity.getUserId(),
                entity.getProvider(),
                entity.getModelName(),
                entity.getAlias() != null ? entity.getAlias() : entity.getModelName(), // 使用modelName作为默认alias
                entity.getApiEndpoint() != null ? entity.getApiEndpoint() : "", // 空字符串作为默认值
                entity.getIsValidated(),
                entity.isDefault(),
                entity.isToolDefault(),
                entity.getCreatedAt(),
                entity.getUpdatedAt(),
                null // API密钥默认不返回
        );
    }
    
    /**
     * 创建包含API密钥的新实例
     */
    public UserAIModelConfigResponse withApiKey(String apiKey) {
        return new UserAIModelConfigResponse(
                this.id,
                this.userId,
                this.provider,
                this.modelName,
                this.alias,
                this.apiEndpoint,
                this.isValidated,
                this.isDefault,
                this.isToolDefault,
                this.createdAt,
                this.updatedAt,
                apiKey
        );
    }
}
