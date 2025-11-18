package com.ainovel.server.controller;

import com.ainovel.server.common.response.ApiResponse;
import com.ainovel.server.domain.model.UserLoginLog;
import com.ainovel.server.repository.UserLoginLogRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * 管理员登录日志管理控制器
 */
@RestController
@RequestMapping("/api/v1/admin/login-logs")
@PreAuthorize("hasAuthority('ADMIN_VIEW_DASHBOARD')")
public class AdminUserLoginLogController {
    
    private static final Logger logger = LoggerFactory.getLogger(AdminUserLoginLogController.class);
    
    private final UserLoginLogRepository loginLogRepository;
    
    @Autowired
    public AdminUserLoginLogController(UserLoginLogRepository loginLogRepository) {
        this.loginLogRepository = loginLogRepository;
    }
    
    /**
     * 获取最近的登录日志
     */
    @GetMapping("/recent")
    public Mono<ResponseEntity<ApiResponse<List<UserLoginLog>>>> getRecentLoginLogs(
            @RequestParam(defaultValue = "50") int limit) {
        logger.info("获取最近{}条登录日志", limit);
        
        return loginLogRepository.findTop100ByOrderByLoginTimeDesc()
                .take(Math.min(limit, 100))
                .collectList()
                .map(logs -> ResponseEntity.ok(ApiResponse.success(logs)))
                .onErrorResume(e -> {
                    logger.error("获取最近登录日志失败", e);
                    return Mono.just(ResponseEntity.badRequest()
                            .body(ApiResponse.error("获取登录日志失败: " + e.getMessage())));
                });
    }
    
    /**
     * 根据时间范围查询登录日志
     */
    @GetMapping
    public Mono<ResponseEntity<ApiResponse<List<UserLoginLog>>>> getLoginLogsByTimeRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {
        logger.info("查询登录日志: {} 至 {}", startDate, endDate);
        
        LocalDateTime start = startDate.atStartOfDay();
        LocalDateTime end = endDate.atTime(23, 59, 59);
        
        return loginLogRepository.findByLoginTimeBetween(start, end)
                .collectList()
                .map(logs -> ResponseEntity.ok(ApiResponse.success(logs)))
                .onErrorResume(e -> {
                    logger.error("查询登录日志失败", e);
                    return Mono.just(ResponseEntity.badRequest()
                            .body(ApiResponse.error("查询登录日志失败: " + e.getMessage())));
                });
    }
    
    /**
     * 根据用户ID查询登录历史
     */
    @GetMapping("/user/{userId}")
    public Mono<ResponseEntity<ApiResponse<List<UserLoginLog>>>> getUserLoginHistory(
            @PathVariable String userId,
            @RequestParam(defaultValue = "20") int limit) {
        logger.info("查询用户{}的登录历史，限制{}条", userId, limit);
        
        return loginLogRepository.findByUserIdOrderByLoginTimeDesc(userId)
                .take(limit)
                .collectList()
                .map(logs -> ResponseEntity.ok(ApiResponse.success(logs)))
                .onErrorResume(e -> {
                    logger.error("查询用户登录历史失败", e);
                    return Mono.just(ResponseEntity.badRequest()
                            .body(ApiResponse.error("查询用户登录历史失败: " + e.getMessage())));
                });
    }
    
    /**
     * 获取登录统计数据
     */
    @GetMapping("/statistics")
    public Mono<ResponseEntity<ApiResponse<Map<String, Object>>>> getLoginStatistics(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {
        logger.info("获取登录统计数据: {} 至 {}", startDate, endDate);
        
        LocalDateTime start = startDate.atStartOfDay();
        LocalDateTime end = endDate.atTime(23, 59, 59);
        
        // 总登录次数
        Mono<Long> totalLoginsMono = loginLogRepository.countByLoginTimeBetween(start, end);
        
        // 成功登录次数
        Mono<Long> successLoginsMono = loginLogRepository.countByLoginTimeBetweenAndSuccess(start, end, true);
        
        // 独立用户数
        Mono<Long> uniqueUsersMono = loginLogRepository.findByLoginTimeBetween(start, end)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .map(UserLoginLog::getUserId)
                .distinct()
                .count();
        
        // 按登录方式统计
        Mono<Map<String, Long>> loginTypeStatsMono = loginLogRepository.findByLoginTimeBetween(start, end)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .collectList()
                .map(logs -> {
                    Map<String, Long> typeStats = new java.util.HashMap<>();
                    logs.forEach(log -> {
                        String type = log.getLoginType() != null ? log.getLoginType() : "unknown";
                        typeStats.merge(type, 1L, Long::sum);
                    });
                    return typeStats;
                });
        
        return Mono.zip(totalLoginsMono, successLoginsMono, uniqueUsersMono, loginTypeStatsMono)
                .map(tuple -> {
                    Map<String, Object> stats = new java.util.HashMap<>();
                    stats.put("totalLogins", tuple.getT1());
                    stats.put("successLogins", tuple.getT2());
                    stats.put("uniqueUsers", tuple.getT3());
                    stats.put("loginTypeStats", tuple.getT4());
                    stats.put("successRate", tuple.getT1() > 0 
                            ? (tuple.getT2().doubleValue() / tuple.getT1().doubleValue() * 100) 
                            : 0.0);
                    
                    return ResponseEntity.ok(ApiResponse.success(stats));
                })
                .onErrorResume(e -> {
                    logger.error("获取登录统计数据失败", e);
                    return Mono.just(ResponseEntity.badRequest()
                            .body(ApiResponse.error("获取登录统计数据失败: " + e.getMessage())));
                });
    }
    
    /**
     * 清理过期的登录日志
     */
    @DeleteMapping("/cleanup")
    @PreAuthorize("hasAuthority('ADMIN_SYSTEM_SETTINGS')")
    public Mono<ResponseEntity<ApiResponse<String>>> cleanupOldLogs(
            @RequestParam(defaultValue = "90") int daysToKeep) {
        logger.info("开始清理{}天前的登录日志", daysToKeep);
        
        LocalDateTime before = LocalDateTime.now().minusDays(daysToKeep);
        
        return loginLogRepository.deleteByLoginTimeBefore(before)
                .map(deletedCount -> {
                    logger.info("成功清理{}条登录日志", deletedCount);
                    return ResponseEntity.ok(ApiResponse.success(
                            String.format("成功清理%d条登录日志", deletedCount)));
                })
                .onErrorResume(e -> {
                    logger.error("清理登录日志失败", e);
                    return Mono.just(ResponseEntity.badRequest()
                            .body(ApiResponse.error("清理登录日志失败: " + e.getMessage())));
                });
    }
}

