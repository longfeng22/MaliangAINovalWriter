package com.ainovel.server.service;

import com.ainovel.server.domain.model.UserLoginLog;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * 用户登录日志服务接口
 */
public interface UserLoginLogService {
    
    /**
     * 记录登录日志
     * 
     * @param userId 用户ID
     * @param username 用户名
     * @param loginType 登录类型
     * @param ipAddress IP地址
     * @param userAgent User-Agent
     * @param success 是否成功
     * @param failureReason 失败原因
     * @return 保存的登录日志
     */
    Mono<UserLoginLog> recordLogin(String userId, String username, String loginType, 
                                   String ipAddress, String userAgent, 
                                   Boolean success, String failureReason);
    
    /**
     * 记录成功的登录
     */
    Mono<UserLoginLog> recordSuccessfulLogin(String userId, String username, String loginType, 
                                            String ipAddress, String userAgent);
    
    /**
     * 记录失败的登录
     */
    Mono<UserLoginLog> recordFailedLogin(String userId, String username, String loginType, 
                                        String ipAddress, String userAgent, String failureReason);
    
    /**
     * 查询用户的登录历史
     */
    Flux<UserLoginLog> getUserLoginHistory(String userId, int limit);
    
    /**
     * 查询指定时间范围内的登录日志
     */
    Flux<UserLoginLog> getLoginLogsByTimeRange(LocalDateTime start, LocalDateTime end);
    
    /**
     * 统计指定时间范围内的登录次数
     */
    Mono<Long> countLoginsByTimeRange(LocalDateTime start, LocalDateTime end);
    
    /**
     * 统计指定日期的独立登录用户数（去重）
     */
    Mono<Long> countUniqueLoginUsersByDate(LocalDateTime start, LocalDateTime end);
    
    /**
     * 获取每日登录统计数据
     */
    Mono<Map<String, Long>> getDailyLoginStats(LocalDateTime start, LocalDateTime end);
    
    /**
     * 清理过期的登录日志
     * 
     * @param before 删除此时间之前的日志
     * @return 删除的记录数
     */
    Mono<Long> cleanupOldLogs(LocalDateTime before);
    
    /**
     * 获取最近的登录日志
     */
    Flux<UserLoginLog> getRecentLoginLogs(int limit);
}

