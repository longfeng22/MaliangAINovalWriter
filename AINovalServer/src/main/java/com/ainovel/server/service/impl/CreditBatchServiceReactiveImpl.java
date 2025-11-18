package com.ainovel.server.service.impl;

import com.ainovel.server.service.CreditBatchService;
import com.ainovel.server.service.CreditService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * 积分批量处理服务 - Reactor响应式实现
 * 
 * 使用Reactor的成熟API：
 * 1. Sinks.many() - 响应式的多播发布器
 * 2. buffer() - 批量收集（时间窗口 + 数量限制）
 * 3. groupBy() - 按userId分组
 * 4. reduce() - 合并相同用户的积分
 * 
 * 相比手动实现的优势：
 * - 完全响应式，无阻塞
 * - 背压处理（backpressure）
 * - 自动资源管理
 * - 更简洁的代码
 */
@Service
@Slf4j
public class CreditBatchServiceReactiveImpl implements CreditBatchService {
    
    @Autowired
    private CreditService creditService;
    
    /**
     * 响应式的积分事件发布器
     * - Multicast：支持多个订阅者
     * - onBackpressureBuffer：背压时缓冲
     */
    private Sinks.Many<CreditEvent> creditEventSink;
    
    /**
     * 批处理窗口时间（毫秒）
     */
    private static final Duration WINDOW_DURATION = Duration.ofMillis(1000);
    
    /**
     * 批处理最大数量（达到此数量立即触发）
     */
    private static final int MAX_BATCH_SIZE = 50;
    
    /**
     * 统计信息
     */
    private final Map<String, Long> pendingCreditsSnapshot = new ConcurrentHashMap<>();
    
    @PostConstruct
    public void init() {
        // 创建响应式发布器
        creditEventSink = Sinks.many().multicast().onBackpressureBuffer();
        
        // 订阅事件流并处理
        creditEventSink.asFlux()
                // 🔥 关键1: bufferTimeout - 时间窗口 + 数量限制的批量收集
                // 每1秒或达到50条时触发批处理（两者先到先触发）
                .bufferTimeout(MAX_BATCH_SIZE, WINDOW_DURATION)
                // 过滤空批次
                .filter(events -> !events.isEmpty())
                // 🔥 关键2: 处理每个批次
                .flatMap(this::processBatch)
                // 错误处理：不中断流
                .onErrorContinue((error, obj) -> {
                    log.error("❌ 批量处理出错，继续处理下一批: error={}", error.getMessage(), error);
                })
                // 订阅（启动流）
                .subscribe(
                    count -> log.debug("✅ 批次处理完成: {} 个用户", count),
                    error -> log.error("❌ 批量处理流异常: {}", error.getMessage(), error),
                    () -> log.info("🛑 批量处理流已完成")
                );
        
        log.info("🚀 积分批量处理服务已启动 (Reactor响应式实现)");
    }
    
    @PreDestroy
    public void destroy() {
        // 优雅关闭：完成所有待处理的事件
        creditEventSink.tryEmitComplete();
        log.info("🛑 积分批量处理服务已关闭");
    }
    
    @Override
    public Mono<Boolean> queueCreditAddition(String userId, long amount, String reason) {
        if (userId == null || userId.isEmpty() || amount <= 0) {
            return Mono.just(false);
        }
        
        CreditEvent event = new CreditEvent(userId, amount, reason);
        
        // 🔥 发射事件到响应式流
        Sinks.EmitResult result = creditEventSink.tryEmitNext(event);
        
        if (result.isSuccess()) {
            log.debug("💰 积分事件已发射: userId={}, amount={}, reason={}", userId, amount, reason);
            // 更新快照（用于查询）
            pendingCreditsSnapshot.merge(userId, amount, Long::sum);
            return Mono.just(true);
        } else {
            log.warn("⚠️  积分事件发射失败: userId={}, result={}", userId, result);
            return Mono.just(false);
        }
    }
    
    /**
     * 处理一个批次的积分事件
     * 
     * @param events 批次内的所有事件
     * @return 处理的用户数量
     */
    private Mono<Integer> processBatch(List<CreditEvent> events) {
        if (events.isEmpty()) {
            return Mono.just(0);
        }
        
        log.info("🚀 开始处理批次: 事件数={}", events.size());
        
        // 🔥 关键3: groupBy + reduce - 按userId分组并合并积分
        return Flux.fromIterable(events)
                // 按userId分组
                .groupBy(CreditEvent::getUserId)
                // 对每个组进行reduce操作
                .flatMap(group -> 
                    group.reduce((event1, event2) -> {
                        // 合并积分
                        long totalAmount = event1.getAmount() + event2.getAmount();
                        // 合并原因
                        String combinedReason = combineReasons(
                            Arrays.asList(event1.getReason(), event2.getReason())
                        );
                        return new CreditEvent(event1.getUserId(), totalAmount, combinedReason);
                    })
                )
                // 收集所有合并后的事件
                .collectList()
                .flatMap(mergedEvents -> {
                    int userCount = mergedEvents.size();
                    long totalAmount = mergedEvents.stream()
                            .mapToLong(CreditEvent::getAmount)
                            .sum();
                    
                    log.info("📊 批次统计: 原始事件数={}, 合并后用户数={}, 总积分={}", 
                            events.size(), userCount, totalAmount);
                    
                    // 🔥 关键4: 并发执行数据库更新
                    return Flux.fromIterable(mergedEvents)
                            .flatMap(event -> 
                                creditService.addCredits(
                                    event.getUserId(), 
                                    event.getAmount(), 
                                    event.getReason()
                                )
                                .doOnSuccess(success -> {
                                    if (Boolean.TRUE.equals(success)) {
                                        log.info("  ✅ 积分更新成功: userId={}, amount={}", 
                                                event.getUserId(), event.getAmount());
                                        // 从快照中移除
                                        pendingCreditsSnapshot.remove(event.getUserId());
                                    } else {
                                        log.warn("  ⚠️  积分更新失败: userId={}", event.getUserId());
                                    }
                                })
                                .onErrorResume(error -> {
                                    log.error("  ❌ 积分更新异常: userId={}, error={}", 
                                            event.getUserId(), error.getMessage(), error);
                                    return Mono.just(false);
                                })
                                .thenReturn(1),
                                10  // 并发度：同时处理10个用户
                            )
                            .reduce(0, Integer::sum)
                            .doOnSuccess(count -> 
                                log.info("✅ 批次完成: 成功={}/{}, 总积分={}", 
                                        count, userCount, totalAmount)
                            );
                });
    }
    
    /**
     * 合并多个原因说明
     */
    private String combineReasons(List<String> reasons) {
        if (reasons.isEmpty()) {
            return "批量积分奖励";
        }
        if (reasons.size() == 1) {
            return reasons.get(0);
        }
        
        // 去重并限制长度
        List<String> uniqueReasons = reasons.stream()
                .distinct()
                .limit(3)
                .collect(Collectors.toList());
        
        if (reasons.size() > uniqueReasons.size()) {
            return String.format("批量积分奖励 (共%d项): %s...", 
                    reasons.size(), String.join(", ", uniqueReasons));
        } else {
            return String.format("批量积分奖励: %s", String.join(", ", uniqueReasons));
        }
    }
    
    @Override
    public Mono<Integer> flushBatch() {
        // Reactor模式下，流是自动处理的
        // 这个方法主要用于兼容接口
        log.info("ℹ️  Reactor模式下自动批量处理，无需手动flush");
        return Mono.just(0);
    }
    
    @Override
    public Mono<Map<String, Long>> getPendingCredits() {
        return Mono.just(new HashMap<>(pendingCreditsSnapshot));
    }
    
    @Override
    public Mono<Integer> clearQueue() {
        int size = pendingCreditsSnapshot.size();
        pendingCreditsSnapshot.clear();
        log.info("🧹 待处理快照已清空: {} 条记录", size);
        // 注意：已发射到流中的事件无法取消，只能清空快照
        return Mono.just(size);
    }
    
    /**
     * 积分事件
     */
    private static class CreditEvent {
        private final String userId;
        private final long amount;
        private final String reason;
        
        public CreditEvent(String userId, long amount, String reason) {
            this.userId = userId;
            this.amount = amount;
            this.reason = reason;
        }
        
        public String getUserId() {
            return userId;
        }
        
        public long getAmount() {
            return amount;
        }
        
        public String getReason() {
            return reason;
        }
    }
}

