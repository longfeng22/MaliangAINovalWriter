package com.ainovel.server.config;

import com.ainovel.server.domain.model.User;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.web.server.WebFilter;

import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/**
 * SkyWalking链路追踪配置
 * 集成SkyWalking的链路追踪功能，自动记录SkyWalking TraceId到MDC和Reactor Context中
 * 
 * 注意：SkyWalking的traceId与业务层的traceId是不同的概念：
 * - sw_traceId: SkyWalking APM系统的链路追踪ID，用于性能监控和调用链分析
 * - traceId (业务层): LLM观测系统的追踪ID，用于扣费、幂等性控制等业务逻辑
 * 
 * 两者互不干扰，分别用于不同的场景。
 * 
 * 路径排除：
 * - SSE长连接接口（/api/v1/api/tasks/events）
 * - Admin后台接口（/api/v1/admin/**）
 * - Actuator监控接口（/actuator/**）
 * 这些接口不需要详细的链路追踪，避免产生大量无用数据
 * 
 * @author AINoval Team
 * @since 2025-10-09
 */
@Slf4j
@Configuration
public class SkyWalkingConfiguration {
    
    /**
     * 排除的路径列表（不进行详细追踪）
     * 这些路径仍然会有基本的日志记录，但不会注入TraceId到MDC
     */
    private static final List<String> EXCLUDED_PATHS = Arrays.asList(
            "/api/v1/api/tasks/events",      // SSE事件流接口
            "/api/v1/admin/",                // Admin后台接口
            "/actuator/",                    // Spring Actuator监控接口
            "/swagger-ui/",                  // Swagger UI
            "/v3/api-docs",                  // OpenAPI文档
            "/webjars/",                     // Webjars资源
            "/favicon.ico"                   // 网站图标
    );
    
    /**
     * 检查路径是否应该被排除
     */
    private boolean shouldExcludePath(String path) {
        if (path == null) {
            return false;
        }
        
        return EXCLUDED_PATHS.stream()
                .anyMatch(excludedPath -> path.startsWith(excludedPath) || path.contains(excludedPath));
    }
    
    /**
     * SkyWalking链路追踪过滤器
     * 将SkyWalking TraceId注入到MDC和Reactor Context中，确保整个请求链路都能追踪
     * 
     * 注意：
     * 1. 使用 sw_traceId 作为key，避免与业务层的 traceId 冲突
     * 2. 从Spring Security的SecurityContext中获取userId，确保安全性
     * 3. 排除SSE、Admin等接口，避免产生大量无用追踪数据
     */
    /**
     * 链路追踪上下文传播 Filter（WebFlux 专用）
     * 
     * 工作原理：
     * 1. 自己生成 traceId（简洁的16进制字符串）
     * 2. 从 Spring Security 获取 userId
     * 3. 生成 requestId  
     * 4. 将它们放入 Reactor Context
     * 5. 使用全局钩子在线程切换时自动恢复 MDC
     * 
     * 为什么需要自己生成 traceId：
     * - WebFlux 是响应式的，线程会频繁切换
     * - SkyWalking Agent 的自动 MDC 注入在 WebFlux 中不可靠
     * - 自生成的 traceId 更简单、可控
     * 
     * 关键点：
     * - ✅ 不在 Filter 入口直接操作 MDC（避免 ReadOnlyHttpHeaders 错误）
     * - ✅ 只调用一次 chain.filter（避免响应重复提交）
     * - ✅ 使用全局钩子实现 MDC 跨线程传播（线程安全）
     * - ✅ 简洁高效的 traceId 生成
     */
    /**
     * 生成简洁的 TraceId
     * 格式：时间戳后8位 + 随机6位16进制
     * 例如：a3b2c1d4e5f6
     */
    private String generateTraceId() {
        long timestamp = System.currentTimeMillis();
        int random = (int) (Math.random() * 0xFFFFFF);
        return String.format("%08x%06x", timestamp & 0xFFFFFFFF, random);
    }
    
    @Bean
    @Order(Ordered.LOWEST_PRECEDENCE - 100) // 在 Spring Security 认证之后执行
    public WebFilter skyWalkingContextFilter() {
        return (exchange, chain) -> {
            String path = exchange.getRequest().getURI().getPath();
            
            // 排除不需要追踪的路径
            if (shouldExcludePath(path)) {
                return chain.filter(exchange);
            }
            
            // 生成 traceId 和 requestId
            // 既然 SkyWalking Agent 的自动注入不工作，我们自己生成一个简单的 traceId
            final String traceId = generateTraceId();
            final String requestId = UUID.randomUUID().toString();
            
            // ✅ 核心逻辑：获取 userId，设置 MDC，实现跨线程传播
            return ReactiveSecurityContextHolder.getContext()
                .map(SecurityContext::getAuthentication)
                .filter(Authentication::isAuthenticated)
                .map(Authentication::getPrincipal)
                .cast(User.class)
                .map(User::getId)
                .defaultIfEmpty("anonymous")
                .flatMap(userId -> {
                    // 🔑 设置 MDC（会被全局钩子自动传播到所有 Reactor 操作符）
                    MDC.put("tid", traceId);
                    MDC.put("userId", userId);
                    MDC.put("requestId", requestId);
                    
                    return chain.filter(exchange)
                        .doOnSubscribe(subscription -> {
                            // 在订阅时确保 MDC 已设置（以防线程切换）
                            MDC.put("tid", traceId);
                            MDC.put("userId", userId);
                            MDC.put("requestId", requestId);
                        })
                        .doFinally(signalType -> {
                            // 请求结束时清理 MDC
                            MDC.remove("tid");
                            MDC.remove("userId");
                            MDC.remove("requestId");
                        })
                        .contextWrite(ctx -> ctx
                            .put("tid", traceId)          // 自生成的 TraceId
                            .put("userId", userId)        // 用户ID
                            .put("requestId", requestId)  // 请求ID
                        );
                });
        };
    }
    
}

