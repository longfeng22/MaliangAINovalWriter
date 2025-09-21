package com.ainovel.server.domain.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * API密钥测试请求DTO
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ApiKeyTestRequest {
    
    /**
     * API密钥
     */
    private String apiKey;
    
    /**
     * API端点（可选）
     */
    private String apiEndpoint;
    
    /**
     * 模型名称（可选，如果不提供则使用默认模型）
     */
    private String modelName;
} 