package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说服务认证响应
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieAuthResponse {
    
    /**
     * JWT访问令牌
     */
    @JsonProperty("access_token")
    private String accessToken;
    
    /**
     * 错误消息
     */
    private String msg;
}



