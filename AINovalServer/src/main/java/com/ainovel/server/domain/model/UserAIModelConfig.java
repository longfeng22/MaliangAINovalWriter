package com.ainovel.server.domain.model;

import java.time.LocalDateTime;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;
// Jasypt - 如果选择注解方式（需要确认响应式支持）
// import com.ulisesbocchio.jasyptspringboot.annotation.EncryptedString;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 用户自定义的AI模型配置
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "user_ai_model_configs")
// 确保用户、提供商、模型的组合是唯一的
@CompoundIndex(name = "user_provider_model_idx", def = "{'userId' : 1, 'provider': 1, 'modelName': 1}", unique = true)
// 索引 userId 和 isDefault 方便查找默认设置
@CompoundIndex(name = "user_default_idx", def = "{'userId' : 1, 'isDefault': 1}")
// 索引 userId 和 isToolDefault 方便查找工具调用默认设置
@CompoundIndex(name = "user_tool_default_idx", def = "{'userId' : 1, 'isToolDefault': 1}")
public class UserAIModelConfig {

    @Id
    private String id;

    @Indexed // 单独索引 userId 也很常用
    private String userId; // 用户ID

    private String provider; // 模型提供商 (e.g., "openai", "anthropic") - 存储小写

    private String modelName; // 模型名称 (e.g., "gpt-4", "claude-3-sonnet")

    private String alias; // 用户自定义别名 (方便用户选择)

    // Jasypt注解方式 (如果适用)
    // @EncryptedString
    private String apiKey; // 用户的API Key (将进行加密存储)

    private String apiEndpoint; // 可选的API Endpoint/Base URL

    @Builder.Default
    private boolean isValidated = false; // API Key是否已验证通过

    private String validationError; // 验证失败时的错误信息

    // 新增字段：是否为用户默认模型
    @Builder.Default
    private boolean isDefault = false;

    // 新增字段：是否为用户默认的工具调用模型（用于工具编排阶段，例如增量解析）
    @Builder.Default
    private boolean isToolDefault = false;

    private LocalDateTime createdAt;

    private LocalDateTime updatedAt;

    // 移除之前错误添加的方法
    // public void setIsValidated(Boolean valid) {
    //     throw new UnsupportedOperationException("Not supported yet.");
    // }
    public boolean getIsValidated() {
        return isValidated;
    }

    public void setIsValidated(Boolean valid) {
        this.isValidated = valid;
    }
}
