package com.ainovel.server.task.listener;

import com.ainovel.server.config.RabbitMQConfig;
import com.rabbitmq.client.Channel;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Qualifier;
import java.nio.charset.StandardCharsets;
import com.ainovel.server.task.events.TaskEventPublisher;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;

/**
 * 任务事件监听器，用于处理任务事件消息
 */
@Slf4j
@Component
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name = "task.transport", havingValue = "rabbit", matchIfMissing = true)
public class TaskEventListener {

    private final TaskEventPublisher sseBroker;
    private final ObjectMapper objectMapper;

    @Autowired
    public TaskEventListener(TaskEventPublisher sseBroker, @Qualifier("taskObjectMapper") ObjectMapper objectMapper) {
        this.sseBroker = sseBroker;
        this.objectMapper = objectMapper;
    }

    /**
     * 处理任务事件消息
     * 
     * @param message 消息对象
     * @param channel RabbitMQ通道
     * @throws IOException 如果消息处理过程中发生IO异常
     */
    @RabbitListener(queues = RabbitMQConfig.TASKS_EVENTS_QUEUE)
    public void handleTaskEvent(Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        String taskId = null;
        String eventType = null;
        
        try {
            // 获取消息头中的任务ID和事件类型
            Map<String, Object> headers = message.getMessageProperties().getHeaders();
            taskId = (String) headers.get("x-task-id");
            eventType = (String) headers.get("x-event-type");
            
            log.info("收到任务事件: taskId={}, eventType={}", taskId, eventType);

            // 解析消息体为 Map，并透传到 SSE Broker（跨实例桥接）
            Map<String, Object> payload;
            try {
                String body = new String(message.getBody(), StandardCharsets.UTF_8);
                payload = objectMapper.readValue(body, new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>(){});
            } catch (Exception parseEx) {
                log.warn("任务事件消息体解析失败，使用空载荷: {}", parseEx.getMessage());
                payload = new java.util.HashMap<>();
            }
            // 补充必要字段，统一成 SSE 事件格式
            payload.putIfAbsent("type", eventType != null ? eventType : "TASK_UNKNOWN");
            payload.putIfAbsent("taskId", taskId);
            // 透传到 Publisher
            sseBroker.publish(payload);
            
            // 确认消息已处理
            channel.basicAck(deliveryTag, false);
            log.debug("任务事件处理成功: taskId={}, eventType={}", taskId, eventType);
            
        } catch (Exception e) {
            log.error("处理任务事件失败: taskId={}, eventType={}", taskId, eventType, e);
            
            // 拒绝消息并重新入队
            channel.basicNack(deliveryTag, false, true);
        }
    }
} 