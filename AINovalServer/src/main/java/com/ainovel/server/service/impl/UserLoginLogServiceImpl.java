package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.UserLoginLog;
import com.ainovel.server.repository.UserLoginLogRepository;
import com.ainovel.server.service.UserLoginLogService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * 用户登录日志服务实现
 */
@Service
public class UserLoginLogServiceImpl implements UserLoginLogService {
    
    private static final Logger logger = LoggerFactory.getLogger(UserLoginLogServiceImpl.class);
    
    private final UserLoginLogRepository loginLogRepository;
    
    @Autowired
    public UserLoginLogServiceImpl(UserLoginLogRepository loginLogRepository) {
        this.loginLogRepository = loginLogRepository;
    }
    
    @Override
    public Mono<UserLoginLog> recordLogin(String userId, String username, String loginType, 
                                         String ipAddress, String userAgent, 
                                         Boolean success, String failureReason) {
        UserLoginLog loginLog = UserLoginLog.builder()
                .userId(userId)
                .username(username)
                .loginTime(LocalDateTime.now())
                .loginType(loginType)
                .ipAddress(ipAddress)
                .userAgent(userAgent)
                .deviceType(parseDeviceType(userAgent))
                .osInfo(parseOSInfo(userAgent))
                .browserInfo(parseBrowserInfo(userAgent))
                .success(success)
                .failureReason(failureReason)
                .createdAt(LocalDateTime.now())
                .build();
        
        return loginLogRepository.save(loginLog)
                .doOnSuccess(log -> logger.info("记录登录日志成功: userId={}, loginType={}, success={}", 
                        userId, loginType, success))
                .doOnError(e -> logger.error("记录登录日志失败: userId={}, error={}", userId, e.getMessage()));
    }
    
    @Override
    public Mono<UserLoginLog> recordSuccessfulLogin(String userId, String username, String loginType, 
                                                   String ipAddress, String userAgent) {
        return recordLogin(userId, username, loginType, ipAddress, userAgent, true, null);
    }
    
    @Override
    public Mono<UserLoginLog> recordFailedLogin(String userId, String username, String loginType, 
                                               String ipAddress, String userAgent, String failureReason) {
        return recordLogin(userId, username, loginType, ipAddress, userAgent, false, failureReason);
    }
    
    @Override
    public Flux<UserLoginLog> getUserLoginHistory(String userId, int limit) {
        return loginLogRepository.findByUserIdOrderByLoginTimeDesc(userId)
                .take(limit);
    }
    
    @Override
    public Flux<UserLoginLog> getLoginLogsByTimeRange(LocalDateTime start, LocalDateTime end) {
        return loginLogRepository.findByLoginTimeBetween(start, end);
    }
    
    @Override
    public Mono<Long> countLoginsByTimeRange(LocalDateTime start, LocalDateTime end) {
        return loginLogRepository.countByLoginTimeBetween(start, end);
    }
    
    @Override
    public Mono<Long> countUniqueLoginUsersByDate(LocalDateTime start, LocalDateTime end) {
        return loginLogRepository.findByLoginTimeBetween(start, end)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .map(UserLoginLog::getUserId)
                .distinct()
                .count();
    }
    
    @Override
    public Mono<Map<String, Long>> getDailyLoginStats(LocalDateTime start, LocalDateTime end) {
        return loginLogRepository.findByLoginTimeBetween(start, end)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .collectList()
                .map(logs -> {
                    Map<String, Long> dailyStats = new HashMap<>();
                    
                    logs.forEach(log -> {
                        String date = log.getLoginTime().toLocalDate().toString();
                        dailyStats.merge(date, 1L, Long::sum);
                    });
                    
                    return dailyStats;
                });
    }
    
    @Override
    public Mono<Long> cleanupOldLogs(LocalDateTime before) {
        logger.info("开始清理 {} 之前的登录日志", before);
        return loginLogRepository.deleteByLoginTimeBefore(before)
                .doOnSuccess(count -> logger.info("成功清理 {} 条登录日志", count))
                .doOnError(e -> logger.error("清理登录日志失败", e));
    }
    
    @Override
    public Flux<UserLoginLog> getRecentLoginLogs(int limit) {
        return loginLogRepository.findTop100ByOrderByLoginTimeDesc()
                .take(limit);
    }
    
    /**
     * 从User-Agent解析设备类型
     */
    private String parseDeviceType(String userAgent) {
        if (userAgent == null) {
            return UserLoginLog.DeviceType.UNKNOWN;
        }
        
        String ua = userAgent.toLowerCase();
        if (ua.contains("mobile") || ua.contains("android") || ua.contains("iphone")) {
            return UserLoginLog.DeviceType.MOBILE;
        } else if (ua.contains("electron") || ua.contains("desktop")) {
            return UserLoginLog.DeviceType.DESKTOP;
        } else {
            return UserLoginLog.DeviceType.WEB;
        }
    }
    
    /**
     * 从User-Agent解析操作系统信息
     */
    private String parseOSInfo(String userAgent) {
        if (userAgent == null) {
            return "Unknown";
        }
        
        String ua = userAgent.toLowerCase();
        if (ua.contains("windows")) {
            return "Windows";
        } else if (ua.contains("mac os")) {
            return "macOS";
        } else if (ua.contains("linux")) {
            return "Linux";
        } else if (ua.contains("android")) {
            return "Android";
        } else if (ua.contains("iphone") || ua.contains("ipad")) {
            return "iOS";
        } else {
            return "Unknown";
        }
    }
    
    /**
     * 从User-Agent解析浏览器信息
     */
    private String parseBrowserInfo(String userAgent) {
        if (userAgent == null) {
            return "Unknown";
        }
        
        String ua = userAgent.toLowerCase();
        if (ua.contains("edg")) {
            return "Edge";
        } else if (ua.contains("chrome")) {
            return "Chrome";
        } else if (ua.contains("firefox")) {
            return "Firefox";
        } else if (ua.contains("safari") && !ua.contains("chrome")) {
            return "Safari";
        } else if (ua.contains("opera")) {
            return "Opera";
        } else {
            return "Unknown";
        }
    }
}

