package com.ainovel.server.repository;

import com.ainovel.server.domain.model.UserLoginLog;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;

/**
 * 用户登录日志Repository
 */
@Repository
public interface UserLoginLogRepository extends ReactiveMongoRepository<UserLoginLog, String> {
    
    /**
     * 根据用户ID查询登录日志，按时间倒序
     */
    Flux<UserLoginLog> findByUserIdOrderByLoginTimeDesc(String userId);
    
    /**
     * 查询指定时间范围内的登录日志
     */
    Flux<UserLoginLog> findByLoginTimeBetween(LocalDateTime start, LocalDateTime end);
    
    /**
     * 查询指定时间范围内某个用户的登录日志
     */
    Flux<UserLoginLog> findByUserIdAndLoginTimeBetween(String userId, LocalDateTime start, LocalDateTime end);
    
    /**
     * 统计指定时间范围内的登录次数
     */
    Mono<Long> countByLoginTimeBetween(LocalDateTime start, LocalDateTime end);
    
    /**
     * 统计指定时间范围内某个用户的登录次数
     */
    Mono<Long> countByUserIdAndLoginTimeBetween(String userId, LocalDateTime start, LocalDateTime end);
    
    /**
     * 统计指定时间范围内成功登录的次数
     */
    Mono<Long> countByLoginTimeBetweenAndSuccess(LocalDateTime start, LocalDateTime end, Boolean success);
    
    /**
     * 删除指定时间之前的日志（用于数据清理）
     */
    Mono<Long> deleteByLoginTimeBefore(LocalDateTime before);
    
    /**
     * 查询最近N条登录日志
     */
    Flux<UserLoginLog> findTop100ByOrderByLoginTimeDesc();
    
    /**
     * 根据登录方式查询
     */
    Flux<UserLoginLog> findByLoginTypeAndLoginTimeBetween(String loginType, LocalDateTime start, LocalDateTime end);
}

