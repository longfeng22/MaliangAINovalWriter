package com.ainovel.server.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 番茄小说服务配置（内部API模式，无需认证）
 */
@Data
@Configuration
@ConfigurationProperties(prefix = "fanqie.api")
public class FanqieNovelConfig {
    
    /**
     * 番茄小说服务API基础URL
     * 容器内部访问: http://fanqie:5000
     * 主机访问: http://localhost:5000
     * 同机器其他服务: http://127.0.0.1:5000
     * 默认: http://127.0.0.1:5000
     */
    private String baseUrl = "http://127.0.0.1:5000";
    
    /**
     * 请求超时时间（秒）
     * 默认: 30秒
     */
    private int timeout = 30;
    
    /**
     * 是否启用番茄小说服务
     * 默认: false
     */
    private boolean enabled = false;
}

