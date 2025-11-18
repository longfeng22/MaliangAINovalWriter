package com.ainovel.server.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;

/**
 * 用户登录日志实体
 * 用于记录用户每次登录的详细信息，支持数据分析和安全审计
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "user_login_logs")
@CompoundIndexes({
    @CompoundIndex(name = "userId_loginTime", def = "{'userId': 1, 'loginTime': -1}"),
    @CompoundIndex(name = "loginTime_userId", def = "{'loginTime': -1, 'userId': 1}")
})
public class UserLoginLog {
    
    @Id
    private String id;
    
    /**
     * 用户ID
     */
    @Indexed
    private String userId;
    
    /**
     * 用户名
     */
    private String username;
    
    /**
     * 登录时间
     */
    @Indexed
    private LocalDateTime loginTime;
    
    /**
     * 登录方式: password(用户名密码), phone(手机号), email(邮箱), refresh(刷新token)
     */
    private String loginType;
    
    /**
     * 登录IP地址
     */
    private String ipAddress;
    
    /**
     * User-Agent信息
     */
    private String userAgent;
    
    /**
     * 设备类型: web, mobile, desktop
     */
    private String deviceType;
    
    /**
     * 操作系统信息
     */
    private String osInfo;
    
    /**
     * 浏览器信息
     */
    private String browserInfo;
    
    /**
     * 登录是否成功
     */
    @Builder.Default
    private Boolean success = true;
    
    /**
     * 失败原因（如果登录失败）
     */
    private String failureReason;
    
    /**
     * 会话ID（可选）
     */
    private String sessionId;
    
    /**
     * 创建时间（用于数据清理）
     */
    private LocalDateTime createdAt;
    
    /**
     * 登录方式枚举
     */
    public static class LoginType {
        public static final String PASSWORD = "password";
        public static final String PHONE = "phone";
        public static final String EMAIL = "email";
        public static final String REFRESH = "refresh";
        public static final String ADMIN = "admin";
    }
    
    /**
     * 设备类型枚举
     */
    public static class DeviceType {
        public static final String WEB = "web";
        public static final String MOBILE = "mobile";
        public static final String DESKTOP = "desktop";
        public static final String UNKNOWN = "unknown";
    }
}

