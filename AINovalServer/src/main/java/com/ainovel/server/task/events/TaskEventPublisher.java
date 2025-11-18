package com.ainovel.server.task.events;

import reactor.core.publisher.Flux;

import java.util.Map;

/**
 * 抽象任务事件发布接口。
 * 由基础设施层实现，对外提供统一的事件流与发布能力。
 */
public interface TaskEventPublisher {

    /**
     * 获取统一的任务事件流（用于 SSE 输出）。
     */
    Flux<Map<String, Object>> events();

    /**
     * 直接发布一条事件（Map 版本）。
     */
    void publish(Map<String, Object> event);

    /**
     * 发布一条事件（字段版本）。
     */
    void publish(String type, String taskId, String taskType, String userId, Map<String, Object> more);
}



