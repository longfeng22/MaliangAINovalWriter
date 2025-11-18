package com.ainovel.server.task;

import reactor.core.publisher.Mono;
import java.util.List;
import java.util.Collections;

/**
 * 后台任务执行器接口，所有具体任务类型的执行器都应实现此接口
 * @param <P> 任务参数类型
 * @param <R> 任务结果类型
 */
public interface BackgroundTaskExecutable<P, R> {
    
    /**
     * 获取任务类型标识
     * @return 任务类型的唯一标识
     */
    String getTaskType();
    
    /**
     * 获取所有支持的任务类型列表
     * 默认返回单个任务类型，子类可以覆盖以支持多个任务类型
     * @return 支持的任务类型列表
     */
    default List<String> getSupportedTaskTypes() {
        return Collections.singletonList(getTaskType());
    }
    
    /**
     * 执行任务
     * @param context 任务上下文，包含任务参数和状态更新方法
     * @return 任务执行结果的Mono
     */
    Mono<R> execute(TaskContext<P> context);
    
    /**
     * 判断任务是否支持取消
     * @return 如果支持取消返回true，否则返回false
     */
    default boolean isCancellable() {
        return false;
    }
    
    /**
     * 取消任务
     * @param context 任务上下文
     * @return 完成信号
     */
    default Mono<Void> cancel(TaskContext<?> context) {
        return Mono.error(new UnsupportedOperationException("此任务类型不支持取消"));
    }
    
    /**
     * 获取任务的估计执行时间（秒）
     * @param context 任务上下文
     * @return 估计执行时间（秒）
     */
    default int getEstimatedExecutionTimeSeconds(TaskContext<P> context) {
        return 60; // 默认估计时间为1分钟
    }
    
    /**
     * 获取任务的最大执行时间（秒）
     * @return 最大执行时间（秒）
     */
    default int getMaxExecutionTimeSeconds() {
        return 3600; // 默认最大执行时间为1小时
    }
    
    /**
     * 检查任务参数是否有效
     * @param parameters 任务参数
     * @return 如果参数有效返回true，否则返回false
     */
    default boolean validateParameters(P parameters) {
        return parameters != null;
    }
    
    /**
     * 更新任务进度的辅助方法
     * @param context 任务上下文
     * @param progressData 进度数据
     * @return 更新操作的完成信号
     */
    default Mono<Void> updateProgress(TaskContext<P> context, Object progressData) {
        return context.updateProgress(progressData);
    }
    
    /**
     * 任务进入队列时的钩子（可选实现）
     * @param context 任务上下文
     * @return Mono<Void> 表示操作完成的信号
     */
    default Mono<Void> onQueued(TaskContext<P> context) {
        return Mono.empty();
    }
    
    /**
     * 任务开始执行时的钩子（可选实现）
     * @param context 任务上下文
     * @return Mono<Void> 表示操作完成的信号
     */
    default Mono<Void> onStarted(TaskContext<P> context) {
        return Mono.empty();
    }
    
    /**
     * 任务完成时的钩子（可选实现）
     * @param context 任务上下文
     * @param result 任务结果
     * @return Mono<Void> 表示操作完成的信号
     */
    default Mono<Void> onCompleted(TaskContext<P> context, R result) {
        return Mono.empty();
    }
    
    /**
     * 任务失败时的钩子（可选实现）
     * @param context 任务上下文
     * @param error 失败原因
     * @return Mono<Void> 表示操作完成的信号
     */
    default Mono<Void> onFailed(TaskContext<P> context, Throwable error) {
        return Mono.empty();
    }
} 