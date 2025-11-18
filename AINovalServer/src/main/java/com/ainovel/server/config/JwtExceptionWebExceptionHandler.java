package com.ainovel.server.config;

import com.ainovel.server.common.response.ApiResponse;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.web.reactive.error.ErrorWebExceptionHandler;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.core.io.buffer.DataBufferFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;

/**
 * JWT异常处理器 - 专门处理JWT认证过程中的异常
 * 
 * 优先级设置为-2，确保在Spring Boot默认的ErrorWebExceptionHandler（优先级-1）之前执行
 * 
 * 目的：
 * 1. 避免JWT过期等预期业务异常打印完整的ERROR堆栈
 * 2. 统一JWT相关异常的响应格式
 * 3. 简化日志输出，只记录必要的WARN信息
 */
@Slf4j
@Component
@Order(-2)  // 优先级高于Spring Boot默认的ErrorWebExceptionHandler(-1)
public class JwtExceptionWebExceptionHandler implements ErrorWebExceptionHandler {

    private final ObjectMapper objectMapper;

    public JwtExceptionWebExceptionHandler(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public Mono<Void> handle(ServerWebExchange exchange, Throwable ex) {
        // 只处理JWT相关的异常，其他异常交给后续的Handler处理
        if (!isJwtRelatedError(ex)) {
            return Mono.error(ex);  // 不处理，传递给下一个Handler
        }

        // 提取真实的JWT异常（可能被包装）
        Throwable actualException = extractJwtException(ex);
        
        // 记录简洁的日志（WARN级别，不打印堆栈）
        logJwtException(actualException, exchange);

        // 构建响应
        HttpStatus status = HttpStatus.UNAUTHORIZED;
        ApiResponse<?> response = buildErrorResponse(actualException);

        // 设置响应头
        exchange.getResponse().setStatusCode(status);
        exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);

        // 序列化响应体
        DataBufferFactory bufferFactory = exchange.getResponse().bufferFactory();
        try {
            String json = objectMapper.writeValueAsString(response);
            DataBuffer buffer = bufferFactory.wrap(json.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        } catch (JsonProcessingException e) {
            log.error("序列化JWT错误响应失败", e);
            return Mono.error(e);
        }
    }

    /**
     * 判断是否是JWT相关的错误
     */
    private boolean isJwtRelatedError(Throwable ex) {
        if (ex instanceof ExpiredJwtException 
                || ex instanceof JwtException 
                || ex instanceof BadCredentialsException) {
            return true;
        }

        // 检查异常链
        Throwable current = ex;
        int depth = 0;
        while (current != null && depth < 5) {  // 限制检查深度
            if (current instanceof ExpiredJwtException 
                    || current instanceof JwtException 
                    || current instanceof BadCredentialsException) {
                return true;
            }
            current = current.getCause();
            depth++;
        }

        return false;
    }

    /**
     * 从异常链中提取真实的JWT异常
     */
    private Throwable extractJwtException(Throwable ex) {
        // 如果本身就是JWT异常，直接返回
        if (ex instanceof ExpiredJwtException || ex instanceof JwtException) {
            return ex;
        }

        // 遍历异常链
        Throwable current = ex;
        while (current != null) {
            if (current instanceof ExpiredJwtException || current instanceof JwtException) {
                return current;
            }
            current = current.getCause();
        }

        return ex;  // 没找到JWT异常，返回原异常
    }

    /**
     * 简洁地记录JWT异常（WARN级别，不打印堆栈）
     */
    private void logJwtException(Throwable ex, ServerWebExchange exchange) {
        String path = exchange.getRequest().getPath().value();
        String method = exchange.getRequest().getMethod().name();

        if (ex instanceof ExpiredJwtException) {
            // JWT过期是正常的业务场景，只记录WARN，不打印堆栈
            log.warn("⏰ JWT token已过期: {} {}", method, path);
        } else if (ex instanceof JwtException) {
            // JWT格式错误等，只记录异常类型，不打印堆栈
            log.warn("🔒 JWT token无效: {} (类型: {}) - {} {}", 
                    ex.getMessage(), 
                    ex.getClass().getSimpleName(),
                    method, 
                    path);
        } else if (ex instanceof BadCredentialsException) {
            // 认证失败，检查是否由JWT异常引起
            Throwable cause = ex.getCause();
            if (cause instanceof ExpiredJwtException) {
                log.warn("⏰ JWT token已过期(包装): {} {}", method, path);
            } else if (cause instanceof JwtException) {
                log.warn("🔒 JWT token无效(包装): {} - {} {}", 
                        cause.getClass().getSimpleName(), method, path);
            } else {
                log.warn("❌ 认证失败: {} - {} {}", ex.getMessage(), method, path);
            }
        }
    }

    /**
     * 根据异常类型构建错误响应
     */
    private ApiResponse<?> buildErrorResponse(Throwable ex) {
        if (ex instanceof ExpiredJwtException) {
            return ApiResponse.error("登录已过期，请重新登录", "TOKEN_EXPIRED");
        } else if (ex instanceof JwtException) {
            return ApiResponse.error("身份认证失败，请重新登录", "INVALID_TOKEN");
        } else if (ex instanceof BadCredentialsException) {
            Throwable cause = ex.getCause();
            if (cause instanceof ExpiredJwtException) {
                return ApiResponse.error("登录已过期，请重新登录", "TOKEN_EXPIRED");
            } else if (cause instanceof JwtException) {
                return ApiResponse.error("身份认证失败，请重新登录", "INVALID_TOKEN");
            }
            return ApiResponse.error("用户名或密码错误", "INVALID_CREDENTIALS");
        }

        return ApiResponse.error("身份认证失败", "AUTH_ERROR");
    }
}





