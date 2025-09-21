package com.ainovel.server.domain.model;

import java.time.LocalDateTime;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 系统配置实体类
 * 用于存储全局业务参数和系统设置
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "system_configs")
public class SystemConfig {
    
    @Id
    private String id;
    
    /**
     * 配置键（唯一标识符）
     */
    @Indexed(unique = true)
    private String configKey;
    
    /**
     * 配置值
     */
    private String configValue;
    
    /**
     * 配置描述
     */
    private String description;
    
    /**
     * 配置类型
     */
    private ConfigType configType;
    
    /**
     * 配置分组
     */
    private String configGroup;
    
    /**
     * 是否启用
     */
    @Builder.Default
    private Boolean enabled = true;
    
    /**
     * 是否只读（只读配置不能通过API修改）
     */
    @Builder.Default
    private Boolean readOnly = false;
    
    /**
     * 配置的默认值
     */
    private String defaultValue;
    
    /**
     * 配置值的验证规则（正则表达式）
     */
    private String validationRule;
    
    /**
     * 配置的最小值（用于数值类型）
     */
    private String minValue;
    
    /**
     * 配置的最大值（用于数值类型）
     */
    private String maxValue;
    
    /**
     * 创建时间
     */
    private LocalDateTime createdAt;
    
    /**
     * 更新时间
     */
    private LocalDateTime updatedAt;
    
    /**
     * 创建者用户ID
     */
    private String createdBy;
    
    /**
     * 最后修改者用户ID
     */
    private String updatedBy;
    
    /**
     * 配置类型枚举
     */
    public enum ConfigType {
        /**
         * 字符串类型
         */
        STRING,
        
        /**
         * 数值类型
         */
        NUMBER,
        
        /**
         * 布尔类型
         */
        BOOLEAN,
        
        /**
         * JSON类型
         */
        JSON,
        
        /**
         * 密钥类型（敏感信息）
         */
        SECRET
    }
    
    /**
     * 常用配置键常量
     */
    public static class Keys {
        /**
         * 积分与美元的汇率
         */
        public static final String CREDIT_TO_USD_RATE = "CREDIT_TO_USD_RATE";
        
        /**
         * 新用户注册赠送积分
         */
        public static final String NEW_USER_CREDITS = "NEW_USER_CREDITS";
        
        /**
         * 每日免费积分额度
         */
        public static final String DAILY_FREE_CREDITS = "DAILY_FREE_CREDITS";
        
        /**
         * 系统维护模式
         */
        public static final String MAINTENANCE_MODE = "MAINTENANCE_MODE";
        
        /**
         * 最大并发AI请求数
         */
        public static final String MAX_CONCURRENT_AI_REQUESTS = "MAX_CONCURRENT_AI_REQUESTS";
        
        /**
         * 默认用户角色
         */
        public static final String DEFAULT_USER_ROLE = "DEFAULT_USER_ROLE";
        
        /**
         * JWT令牌过期时间（小时）
         */
        public static final String JWT_EXPIRATION_HOURS = "JWT_EXPIRATION_HOURS";
        
        /**
         * 文件上传最大大小（MB）
         */
        public static final String MAX_FILE_UPLOAD_SIZE_MB = "MAX_FILE_UPLOAD_SIZE_MB";
        
        /**
         * 是否开启用户注册
         */
        public static final String ENABLE_USER_REGISTRATION = "ENABLE_USER_REGISTRATION";
        
        /**
         * 是否开启邮件验证
         */
        public static final String ENABLE_EMAIL_VERIFICATION = "ENABLE_EMAIL_VERIFICATION";

        /**
         * 计费处理窗口（最近N小时），字符串数值，留空表示不限
         */
        public static final String BILLING_PROCESS_SINCE_HOURS = "BILLING_PROCESS_SINCE_HOURS";

        /**
         * 计费处理开始时间（ISO-8601字符串），优先级高于 HOURS，留空表示不限
         */
        public static final String BILLING_PROCESS_SINCE_TIME = "BILLING_PROCESS_SINCE_TIME";
    }
    
    /**
     * 获取字符串值
     * 
     * @return 字符串值
     */
    public String getStringValue() {
        return configValue;
    }
    
    /**
     * 获取数值
     * 
     * @return 数值
     */
    public Double getNumericValue() {
        try {
            return configValue != null ? Double.parseDouble(configValue) : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }
    
    /**
     * 获取整数值
     * 
     * @return 整数值
     */
    public Integer getIntegerValue() {
        try {
            return configValue != null ? Integer.parseInt(configValue) : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }
    
    /**
     * 获取长整数值
     * 
     * @return 长整数值
     */
    public Long getLongValue() {
        try {
            return configValue != null ? Long.parseLong(configValue) : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }
    
    /**
     * 获取布尔值
     * 
     * @return 布尔值
     */
    public Boolean getBooleanValue() {
        if (configValue == null) {
            return null;
        }
        return Boolean.parseBoolean(configValue);
    }
    
    /**
     * 验证配置值是否有效
     * 
     * @param value 待验证的值
     * @return 是否有效
     */
    public boolean isValidValue(String value) {
        if (value == null && defaultValue != null) {
            value = defaultValue;
        }
        
        if (validationRule != null && !value.matches(validationRule)) {
            return false;
        }
        
        if (configType == ConfigType.NUMBER) {
            try {
                double numValue = Double.parseDouble(value);
                if (minValue != null && numValue < Double.parseDouble(minValue)) {
                    return false;
                }
                if (maxValue != null && numValue > Double.parseDouble(maxValue)) {
                    return false;
                }
            } catch (NumberFormatException e) {
                return false;
            }
        }
        
        return true;
    }
}