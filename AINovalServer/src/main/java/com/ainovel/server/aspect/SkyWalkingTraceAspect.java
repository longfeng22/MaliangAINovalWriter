package com.ainovel.server.aspect;

import lombok.extern.slf4j.Slf4j;
import org.apache.skywalking.apm.toolkit.trace.ActiveSpan;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.lang.reflect.Method;
import java.util.Arrays;

/**
 * SkyWalking链路追踪AOP切面
 * 自动为标注了特定注解的方法添加链路追踪
 * 
 * @author AINoval Team
 * @since 2025-10-09
 */
@Slf4j
@Aspect
@Component
public class SkyWalkingTraceAspect {
    
    /**
     * 环绕通知：拦截Service层方法
     * 自动添加链路追踪信息
     */
    @Around("execution(* com.ainovel.server.service..*.*(..))")
    public Object traceServiceMethods(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        String className = method.getDeclaringClass().getSimpleName();
        String methodName = method.getName();
        
        // 添加操作名称标签
        String operationName = className + "." + methodName;
        ActiveSpan.tag("operation", operationName);
        
        // 添加参数信息（注意：不要记录敏感信息）
        Object[] args = joinPoint.getArgs();
        if (args != null && args.length > 0) {
            // 只记录参数数量和类型，不记录具体值
            String paramTypes = Arrays.stream(args)
                    .map(arg -> arg != null ? arg.getClass().getSimpleName() : "null")
                    .reduce((a, b) -> a + ", " + b)
                    .orElse("none");
            ActiveSpan.tag("param_types", paramTypes);
        }
        
        long startTime = System.currentTimeMillis();
        
        try {
            Object result = joinPoint.proceed();
            
            // 处理响应式返回值
            if (result instanceof Mono) {
                return ((Mono<?>) result)
                        .doOnSuccess(value -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("result_type", "Mono");
                            log.debug("Service method traced: {}#{}, duration={}ms", 
                                    className, methodName, duration);
                        })
                        .doOnError(error -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("error", error.getClass().getSimpleName());
                            ActiveSpan.tag("error_message", error.getMessage());
                            log.error("Service method error: {}#{}, duration={}ms, error={}", 
                                    className, methodName, duration, error.getMessage());
                        });
            } else if (result instanceof Flux) {
                return ((Flux<?>) result)
                        .doOnComplete(() -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("result_type", "Flux");
                            log.debug("Service method traced: {}#{}, duration={}ms", 
                                    className, methodName, duration);
                        })
                        .doOnError(error -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("error", error.getClass().getSimpleName());
                            ActiveSpan.tag("error_message", error.getMessage());
                            log.error("Service method error: {}#{}, duration={}ms, error={}", 
                                    className, methodName, duration, error.getMessage());
                        });
            }
            
            // 非响应式返回值
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
            if (result != null) {
                ActiveSpan.tag("result_type", result.getClass().getSimpleName());
            }
            log.debug("Service method traced: {}#{}, duration={}ms", 
                    className, methodName, duration);
            
            return result;
            
        } catch (Throwable throwable) {
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("execution_time_ms", String.valueOf(duration));
            ActiveSpan.tag("error", throwable.getClass().getSimpleName());
            ActiveSpan.tag("error_message", throwable.getMessage());
            
            // 对于业务异常（如JWT过期、参数校验失败等），只记录错误消息，不打印堆栈
            if (isBusinessException(throwable)) {
                log.warn("Service method business error: {}#{}, duration={}ms, error={}", 
                        className, methodName, duration, throwable.getMessage());
            } else {
                // 系统异常才打印完整堆栈
                log.error("Service method error: {}#{}, duration={}ms, error={}", 
                        className, methodName, duration, throwable.getMessage(), throwable);
            }
            
            throw throwable;
        }
    }
    
    /**
     * 环绕通知：拦截Repository层方法
     * 监控数据库操作性能
     */
    @Around("execution(* com.ainovel.server.repository..*.*(..))")
    public Object traceRepositoryMethods(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        String className = method.getDeclaringClass().getSimpleName();
        String methodName = method.getName();
        
        String operationName = "DB." + className + "." + methodName;
        ActiveSpan.tag("operation", operationName);
        ActiveSpan.tag("db_type", "MongoDB");
        
        long startTime = System.currentTimeMillis();
        
        try {
            Object result = joinPoint.proceed();
            
            // 处理响应式返回值
            if (result instanceof Mono) {
                return ((Mono<?>) result)
                        .doOnSuccess(value -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("db_execution_time_ms", String.valueOf(duration));
                            if (duration > 1000) {
                                log.warn("Slow DB query detected: {}#{}, duration={}ms", 
                                        className, methodName, duration);
                            }
                        });
            } else if (result instanceof Flux) {
                return ((Flux<?>) result)
                        .doOnComplete(() -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("db_execution_time_ms", String.valueOf(duration));
                            if (duration > 1000) {
                                log.warn("Slow DB query detected: {}#{}, duration={}ms", 
                                        className, methodName, duration);
                            }
                        });
            }
            
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("db_execution_time_ms", String.valueOf(duration));
            if (duration > 1000) {
                log.warn("Slow DB query detected: {}#{}, duration={}ms", 
                        className, methodName, duration);
            }
            
            return result;
            
        } catch (Throwable throwable) {
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("db_execution_time_ms", String.valueOf(duration));
            ActiveSpan.tag("db_error", throwable.getClass().getSimpleName());
            
            log.error("DB operation error: {}#{}, duration={}ms, error={}", 
                    className, methodName, duration, throwable.getMessage());
            
            throw throwable;
        }
    }
    
    /**
     * 判断是否为业务异常（不需要打印完整堆栈）
     */
    private boolean isBusinessException(Throwable throwable) {
        String exceptionName = throwable.getClass().getName();
        // JWT相关异常
        if (exceptionName.startsWith("io.jsonwebtoken.")) {
            return true;
        }
        // 参数校验异常
        if (exceptionName.contains("IllegalArgumentException") 
                || exceptionName.contains("MethodArgumentNotValidException")
                || exceptionName.contains("BindException")) {
            return true;
        }
        // 自定义业务异常
        if (exceptionName.contains("BusinessException") 
                || exceptionName.contains("ServiceException")) {
            return true;
        }
        return false;
    }
    
    /**
     * 环绕通知：拦截AI相关方法
     * 监控AI调用性能和token使用情况
     */
    @Around("execution(* com.ainovel.server.ai..*.*(..))")
    public Object traceAIMethods(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        String className = method.getDeclaringClass().getSimpleName();
        String methodName = method.getName();
        
        String operationName = "AI." + className + "." + methodName;
        ActiveSpan.tag("operation", operationName);
        ActiveSpan.tag("component", "AI");
        
        long startTime = System.currentTimeMillis();
        
        try {
            Object result = joinPoint.proceed();
            
            // 处理响应式返回值
            if (result instanceof Mono) {
                return ((Mono<?>) result)
                        .doOnSuccess(value -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
                            log.debug("AI method traced: {}#{}, duration={}ms", 
                                    className, methodName, duration);
                        })
                        .doOnError(error -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("ai_error", error.getClass().getSimpleName());
                            log.error("AI method error: {}#{}, duration={}ms, error={}", 
                                    className, methodName, duration, error.getMessage());
                        });
            } else if (result instanceof Flux) {
                return ((Flux<?>) result)
                        .doOnComplete(() -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
                            log.debug("AI method traced: {}#{}, duration={}ms", 
                                    className, methodName, duration);
                        })
                        .doOnError(error -> {
                            long duration = System.currentTimeMillis() - startTime;
                            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
                            ActiveSpan.tag("ai_error", error.getClass().getSimpleName());
                            log.error("AI method error: {}#{}, duration={}ms, error={}", 
                                    className, methodName, duration, error.getMessage());
                        });
            }
            
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
            log.debug("AI method traced: {}#{}, duration={}ms", 
                    className, methodName, duration);
            
            return result;
            
        } catch (Throwable throwable) {
            long duration = System.currentTimeMillis() - startTime;
            ActiveSpan.tag("ai_execution_time_ms", String.valueOf(duration));
            ActiveSpan.tag("ai_error", throwable.getClass().getSimpleName());
            
            // 对于业务异常（如JWT过期、参数校验失败等），只记录错误消息，不打印堆栈
            if (isBusinessException(throwable)) {
                log.warn("AI method business error: {}#{}, duration={}ms, error={}", 
                        className, methodName, duration, throwable.getMessage());
            } else {
                // 系统异常才打印完整堆栈
                log.error("AI method error: {}#{}, duration={}ms, error={}", 
                        className, methodName, duration, throwable.getMessage(), throwable);
            }
            
            throw throwable;
        }
    }
}


