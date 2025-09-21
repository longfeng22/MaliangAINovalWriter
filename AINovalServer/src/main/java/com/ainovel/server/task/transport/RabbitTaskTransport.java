package com.ainovel.server.task.transport;

import com.ainovel.server.task.producer.TaskMessageProducer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/**
 * RabbitMQ 传输实现，包装 TaskMessageProducer。
 */
@Component
@ConditionalOnProperty(name = "task.transport", havingValue = "rabbit", matchIfMissing = true)
public class RabbitTaskTransport implements TaskTransport {

    private final TaskMessageProducer taskMessageProducer;

    @Autowired
    public RabbitTaskTransport(TaskMessageProducer taskMessageProducer) {
        this.taskMessageProducer = taskMessageProducer;
    }

    @Override
    public Mono<Void> dispatchTask(String taskId, String userId, String taskType, Object parameters) {
        return taskMessageProducer.sendTask(taskId, userId, taskType, parameters);
    }

    @Override
    public Mono<Void> dispatchTask(String taskId, String userId, String taskType, Object parameters, int retryCount) {
        return taskMessageProducer.sendToRetryExchange(taskId, userId, taskType, parameters, retryCount);
    }

    @Override
    public Mono<Void> dispatchDelayedRetryTask(String taskId, String userId, String taskType, Object parameters, int retryCount, long delayMillis) {
        return taskMessageProducer.sendDelayedRetryTask(taskId, userId, taskType, parameters, retryCount, delayMillis);
    }
}



