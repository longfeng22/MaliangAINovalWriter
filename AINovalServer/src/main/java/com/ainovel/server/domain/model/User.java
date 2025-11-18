package com.ainovel.server.domain.model;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 用户领域模型
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "users")
public class User {
    
    @Id
    private String id;
    
    @Indexed(unique = true)
    private String username;
    
    private String password;
    
    @Indexed(unique = true, sparse = true)
    private String email;
    
    /**
     * 手机号码
     */
    @Indexed(unique = true, sparse = true)
    private String phone;
    
    /**
     * 邮箱是否已验证
     */
    @Builder.Default
    private Boolean emailVerified = false;
    
    /**
     * 手机号码是否已验证
     */
    @Builder.Default
    private Boolean phoneVerified = false;
    
    private String displayName;
    
    private String avatar;
    
    /**
     * 用户角色ID列表
     */
    @Builder.Default
    private List<String> roleIds = new ArrayList<>();

    /**
     * 用户角色名称列表（为了兼容性保留）
     */
    @Builder.Default
    private List<String> roles = new ArrayList<>();
    
    /**
     * 用户当前积分余额
     */
    @Builder.Default
    private Long credits = 0L;
    
    /**
     * 用户总消费积分
     */
    @Builder.Default
    private Long totalCreditsUsed = 0L;
    
    /**
     * 当前有效订阅ID
     */
    private String currentSubscriptionId;
    
    /**
     * 账户状态
     */
    @Builder.Default
    private AccountStatus accountStatus = AccountStatus.ACTIVE;
    
    /**
     * 用户偏好设置
     */
    @Builder.Default
    private Map<String, Object> preferences = new HashMap<>();
    
    private LocalDateTime createdAt;
    
    private LocalDateTime updatedAt;
    
    /**
     * 最后登录时间
     */
    private LocalDateTime lastLoginAt;

    /**
     * JWT 版本号（用于强制失效旧token）
     */
    @Builder.Default
    private Integer tokenVersion = 1;
    
    /**
     * 账户状态枚举
     */
    public enum AccountStatus {
        /**
         * 活跃状态
         */
        ACTIVE,
        
        /**
         * 暂停状态
         */
        SUSPENDED,
        
        /**
         * 禁用状态
         */
        DISABLED,
        
        /**
         * 待验证状态
         */
        PENDING_VERIFICATION
    }
    
    /**
     * 检查用户是否有指定角色
     * 
     * @param roleId 角色ID
     * @return 是否拥有该角色
     */
    public boolean hasRole(String roleId) {
        return roleIds != null && roleIds.contains(roleId);
    }
    
    /**
     * 添加角色
     * 
     * @param roleId 角色ID
     */
    public void addRole(String roleId) {
        if (roleIds == null) {
            roleIds = new ArrayList<>();
        }
        if (!roleIds.contains(roleId)) {
            roleIds.add(roleId);
        }
    }
    
    /**
     * 移除角色
     * 
     * @param roleId 角色ID
     */
    public void removeRole(String roleId) {
        if (roleIds != null) {
            roleIds.remove(roleId);
        }
    }
    
    /**
     * 检查积分是否充足
     * 
     * @param requiredCredits 需要的积分数
     * @return 是否充足
     */
    public boolean hasEnoughCredits(long requiredCredits) {
        return credits != null && credits >= requiredCredits;
    }
    
    /**
     * 扣减积分
     * 
     * @param amount 扣减数量
     * @return 是否成功
     */
    public boolean deductCredits(long amount) {
        if (!hasEnoughCredits(amount)) {
            return false;
        }
        credits -= amount;
        totalCreditsUsed = (totalCreditsUsed == null ? 0L : totalCreditsUsed) + amount;
        return true;
    }
    
    /**
     * 增加积分
     * 
     * @param amount 增加数量
     */
    public void addCredits(long amount) {
        credits = (credits == null ? 0L : credits) + amount;
    }
    
    /**
     * 检查账户是否活跃
     * 
     * @return 是否活跃
     */
    public boolean isActive() {
        return accountStatus == AccountStatus.ACTIVE;
    }

} 