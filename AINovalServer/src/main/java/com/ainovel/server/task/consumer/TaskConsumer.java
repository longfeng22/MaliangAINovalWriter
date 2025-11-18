package com.ainovel.server.task.consumer;

import com.ainovel.server.config.RabbitMQConfig;
import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.ExecutionResult;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.TaskContextImpl;
import com.ainovel.server.task.event.internal.*;
import com.ainovel.server.task.model.BackgroundTask;
import com.ainovel.server.task.model.TaskStatus;
import com.ainovel.server.task.producer.TaskMessageProducer;
import com.ainovel.server.task.service.TaskExecutorService;
import com.ainovel.server.task.service.TaskStateService;
import com.ainovel.server.task.service.TaskSubmissionService;
import com.ainovel.server.config.TaskConversionConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.ainovel.server.task.dto.continuecontent.ContinueWritingContentResult;
import com.ainovel.server.task.model.TaskStatus;
import com.rabbitmq.client.Channel;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;
import jakarta.annotation.PostConstruct;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import org.slf4j.MDC;

import java.io.IOException;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * 响应式任务消费者，负责处理RabbitMQ中的任务消息
 */
@Slf4j
@Component
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name = "task.transport", havingValue = "rabbit", matchIfMissing = true)
public class TaskConsumer {
    
    private static final int MAX_RETRY_ATTEMPTS = 3;
    
    private final TaskExecutorService taskExecutorService;
    private final TaskStateService taskStateService;
    private final TaskSubmissionService taskSubmissionService;
    private final ApplicationEventPublisher eventPublisher;
    private final TaskMessageProducer taskMessageProducer;
    private final TaskConversionConfig taskConversionConfig;
    private final ObjectMapper objectMapper;
    
    private final String nodeId;
    
    @Value("${task.retry.max-attempts:3}")
    private int maxRetryAttempts;
    
    @Value("${task.retry.delays:15000,60000,300000}")
    private String retryDelaysStr;
    
    private long[] retryDelays;
    
    @Autowired
    public TaskConsumer(
            TaskExecutorService taskExecutorService,
            TaskStateService taskStateService,
            TaskSubmissionService taskSubmissionService,
            ApplicationEventPublisher eventPublisher,
            TaskMessageProducer taskMessageProducer,
            TaskConversionConfig taskConversionConfig,
            @Qualifier("taskObjectMapper") ObjectMapper objectMapper) {
        this.taskExecutorService = taskExecutorService;
        this.taskStateService = taskStateService;
        this.taskSubmissionService = taskSubmissionService;
        this.eventPublisher = eventPublisher;
        this.taskMessageProducer = taskMessageProducer;
        this.taskConversionConfig = taskConversionConfig;
        this.objectMapper = objectMapper;
        
        // 生成节点ID
        String hostname;
        try {
            hostname = InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            hostname = "unknown-host";
        }
        this.nodeId = hostname + "-" + UUID.randomUUID().toString().substring(0, 8);
        
        // 不再在此处调用 initRetryDelays()
    }

    /**
     * 在依赖注入完成后初始化重试延迟
     */
    @PostConstruct
    public void initialize() {
        initRetryDelays();
    }
    
    /**
     * 初始化重试延迟时间配置
     */
    private void initRetryDelays() {
        if (retryDelaysStr == null) {
            log.error("Retry delays string (task.retry.delays) is null. Cannot initialize retry delays.");
            // 可以选择抛出异常或使用默认值
            throw new IllegalStateException("Configuration property 'task.retry.delays' is missing or not loaded.");
            // 或者使用默认值:
            // retryDelays = new long[]{15000, 60000, 300000};
            // log.warn("Using default retry delays: {}", Arrays.toString(retryDelays));
            // return;
        }
        String[] delayStrings = retryDelaysStr.split(",");
        retryDelays = new long[delayStrings.length];
        for (int i = 0; i < delayStrings.length; i++) {
            retryDelays[i] = Long.parseLong(delayStrings[i].trim());
        }
    }
    
    /**
     * 处理从任务队列接收的消息
     * 
     * @param message 消息
     * @param channel 通道
     * @throws IOException 如果消息处理失败
     */
    @RabbitListener(queues = "${spring.rabbitmq.template.default-receive-queue:tasks.queue}", 
                   containerFactory = "rabbitListenerContainerFactory")
    public void handleTaskMessage(Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        
        // 提取和记录任务ID和类型 (主要用于日志)
        final String taskIdFromHeader;
        final String taskTypeFromHeader;
        String tempTaskId = null;
        String tempTaskType = null;
        // 设置基础 MDC（队列路径/traceId）
        String consumerQueue = message.getMessageProperties().getConsumerQueue();
        if (consumerQueue != null) {
            MDC.put("path", "amqp:" + consumerQueue);
        }
        String traceId = (String) message.getMessageProperties().getHeaders().getOrDefault("x-trace-id", null);
        if (traceId == null || traceId.toString().isBlank()) {
            traceId = java.util.UUID.randomUUID().toString().replace("-", "");
        }
        MDC.put("traceId", traceId);
        Object userIdHeader = message.getMessageProperties().getHeaders().get("x-user-id");
        if (userIdHeader != null) {
            MDC.put("userId", userIdHeader.toString());
        }
        // 使用 x- 前缀查找 header
        if (message.getMessageProperties().getHeaders().containsKey("x-task-id")) { 
            tempTaskId = message.getMessageProperties().getHeaders().get("x-task-id").toString();
            log.info("从消息头中获取到任务ID (用于日志): {}", tempTaskId);
        }
        if (message.getMessageProperties().getHeaders().containsKey("x-task-type")) { 
            tempTaskType = message.getMessageProperties().getHeaders().get("x-task-type").toString();
            log.info("从消息头中获取到任务类型 (用于日志): {}", tempTaskType);
        }
        taskIdFromHeader = tempTaskId; // 赋值给 final 变量
        taskTypeFromHeader = tempTaskType; // 赋值给 final 变量
        if (taskIdFromHeader != null) MDC.put("taskId", taskIdFromHeader);
        if (taskTypeFromHeader != null) MDC.put("taskType", taskTypeFromHeader);

        try {
            log.info("收到消息: deliveryTag={}, messageId={}", 
                    deliveryTag, 
                    message.getMessageProperties().getMessageId());
            
            // 详细记录消息属性和内容信息
            log.debug("消息属性: headers={}, contentType={}, contentEncoding={}, correlationId={}", 
                    message.getMessageProperties().getHeaders(),
                    message.getMessageProperties().getContentType(),
                    message.getMessageProperties().getContentEncoding(),
                    message.getMessageProperties().getCorrelationId());
            
            // 记录原始消息体内容，帮助诊断问题
            try {
                String messageBodyStr = new String(message.getBody(), "UTF-8");
                log.debug("消息体内容: {}", messageBodyStr.length() > 500 ? 
                          messageBodyStr.substring(0, 500) + "..." : messageBodyStr);
            } catch (Exception e) {
                log.warn("无法记录消息体内容: {}", e.getMessage());
            }
            
            // 启动响应式处理链
            processMessageReactively(message)
                .doOnSuccess(v -> {
                    try {
                        ackMessage(channel, deliveryTag);
                        log.info("任务处理成功并确认: deliveryTag={}, taskId={}, taskType={}", 
                              deliveryTag, taskIdFromHeader, taskTypeFromHeader);
                    } catch (IOException e) {
                        log.error("确认消息时发生异常: deliveryTag={}, taskId={}", 
                              deliveryTag, taskIdFromHeader, e);
                    }
                })
                .doOnError(e -> {
                    try {
                        log.error("任务处理失败: deliveryTag={}, taskId={}, 错误: {}", 
                               deliveryTag, taskIdFromHeader, e.getMessage(), e);
                        nackMessage(channel, deliveryTag, false); // 发送到死信队列
                    } catch (IOException ioe) {
                        log.error("拒绝消息时发生异常: deliveryTag={}, taskId={}", 
                              deliveryTag, taskIdFromHeader, ioe);
                    }
                })
                .doFinally(signal -> MDC.clear())
                .subscribe(); // 订阅以触发执行
        } catch (Exception e) {
            log.error("处理消息异常: deliveryTag={}, 错误: {}", deliveryTag, e.getMessage(), e);
            nackMessage(channel, deliveryTag, false); // 发送到死信队列
        }
    }
    
    /**
     * 响应式处理消息的主逻辑
     * 
     * @param message 消息对象
     * @return 处理结果的Mono<Void>
     */
    private Mono<Void> processMessageReactively(Message message) {
        log.debug("开始处理消息: {}", message.getMessageProperties().getMessageId());
        
        // 获取消息属性
        MessageProperties props = message.getMessageProperties();
        byte[] body = message.getBody();
        
        // 获取任务ID
        String taskId = null;
        Object taskIdHeader = props.getHeaders().get("x-task-id"); // 使用 x- 前缀
        if (taskIdHeader != null) {
            taskId = taskIdHeader.toString();
            log.info("从消息头中获取任务ID: {}", taskId);
            
            // 检查任务ID是否符合UUID格式
            try {
                if (taskId != null && taskId.length() > 8) {
                    UUID.fromString(taskId);
                    log.debug("任务ID是有效的UUID格式");
                } else {
                    log.warn("任务ID不是标准UUID格式: {}", taskId);
                }
            } catch (IllegalArgumentException e) {
                log.warn("任务ID不是有效的UUID格式: {}, 错误: {}", taskId, e.getMessage());
            }
        } else {
            // 尝试从消息体解析任务ID (作为后备，如果确认 header 肯定有，可以移除)
            try {
                JsonNode rootNode = objectMapper.readTree(body);
                if (rootNode.has("taskId")) {
                    taskId = rootNode.get("taskId").asText();
                    log.info("从消息体JSON中获取任务ID: {}", taskId);
                    
                    // 验证JSON中的taskId是否有效
                    if (taskId != null && taskId.trim().length() > 0) {
                        try {
                            // 尝试验证是否为有效的UUID格式
                            if (taskId.length() >= 32) {
                                UUID.fromString(taskId);
                                log.debug("从JSON提取的任务ID是有效的UUID格式");
                            } else {
                                log.warn("从JSON中提取的任务ID不是标准UUID格式: {}", taskId);
                            }
                        } catch (IllegalArgumentException e) {
                            log.warn("从JSON中提取的任务ID格式无效: {}, 错误: {}", taskId, e.getMessage());
                        }
                    } else {
                        log.warn("从JSON中提取的任务ID为空或无效");
                    }
                }
            } catch (IOException e) {
                log.warn("解析消息体JSON失败，可能不是JSON或结构不符: {}", e.getMessage());
            }
            
            if (taskId == null) {
                log.error("消息中找不到任务ID (x-task-id header 和 body.taskId 均未找到)，无法处理: messageId={}", props.getMessageId());
                return Mono.error(new IllegalArgumentException("消息中找不到任务ID"));
            }
        }
        
        // 获取任务类型
        String taskType = null;
        Object taskTypeHeader = props.getHeaders().get("x-task-type"); // 使用 x- 前缀
        if (taskTypeHeader != null) {
            taskType = taskTypeHeader.toString();
            log.info("从消息头中获取任务类型: {}", taskType);
        } else {
            // 尝试从消息体解析任务类型 (作为后备)
            try {
                JsonNode rootNode = objectMapper.readTree(body);
                if (rootNode.has("taskType")) {
                    taskType = rootNode.get("taskType").asText();
                    log.info("从消息体JSON中获取任务类型: {}", taskType);
                }
            } catch (IOException e) {
                log.warn("解析消息体JSON失败，可能不是JSON或结构不符: {}", e.getMessage());
            }
            
            if (taskType == null) {
                log.error("消息中找不到任务类型 (x-task-type header 和 body.taskType 均未找到)，无法处理: taskId={}, messageId={}", 
                        taskId, props.getMessageId());
                return Mono.error(new IllegalArgumentException("消息中找不到任务类型"));
            }
        }
        
        // 获取消息中的重试次数
        int retryCount = 0;
        // retry count header 也使用 x- 前缀
        Object retryCountHeader = props.getHeaders().get("x-retry-count"); 
        if (retryCountHeader != null) {
            try {
                retryCount = Integer.parseInt(retryCountHeader.toString());
            } catch (NumberFormatException e) {
                log.warn("无法解析重试次数 header 'x-retry-count': {}, 默认设置为 0", retryCountHeader);
            }
        }
        
        final String finalTaskId = taskId;
        final String finalTaskType = taskType;
        final int finalRetryCount = retryCount;
        
        // 在执行异步流程前，同步检查一下任务是否存在，并记录当前状态
        try {
            boolean taskExists = taskStateService.getTask(finalTaskId)
                .map(task -> {
                    log.info("预检查 - 任务已存在: taskId={}, status={}, type={}", 
                             task.getId(), task.getStatus(), task.getTaskType());
                    return true;
                })
                .defaultIfEmpty(false)
                .block(Duration.ofSeconds(5)); // 添加超时以防阻塞太久
                
            if (!taskExists) {
                log.warn("预检查 - 找不到任务: taskId={}", finalTaskId);
                // 如果预检查找不到任务，可能意味着任务创建失败或已被删除，直接拒绝消息可能更安全
                // return Mono.error(new IllegalStateException("预检查找不到任务: " + finalTaskId));
            }
        } catch (Exception e) {
            // block 可能抛出 IllegalStateException 或其他异常
            log.error("预检查时发生错误: taskId={}, error={}", finalTaskId, e.getMessage(), e);
            // 根据策略决定是否继续处理
        }
        
        log.info("开始处理任务: id={}, type={}, retryCount={}", finalTaskId, finalTaskType, finalRetryCount);
        
        // 执行幂等性检查
        log.info("尝试将任务设置为运行状态: taskId={}, nodeId={}", finalTaskId, nodeId);
        
        // 首先检查任务当前状态
        return taskStateService.getTask(finalTaskId)
            .switchIfEmpty(Mono.<BackgroundTask>defer(() -> {
                // 如果 getTask 返回 empty，说明任务不存在
                log.error("幂等性检查前置: 找不到任务: taskId={}", finalTaskId);
                // 此处不应该继续执行，因为任务可能从未成功创建或已被删除
                return Mono.error(new IllegalStateException("任务不存在: " + finalTaskId));
            }))
            .flatMap(task -> {
                // 任务状态检查
                if (task.getStatus() == null) {
                    log.error("任务状态为null: taskId={}", finalTaskId);
                    // 状态异常，不继续处理
                    return Mono.error(new IllegalStateException("任务状态为null: " + finalTaskId)); 
                }
                
                // 检查状态是否允许执行
                TaskStatus currentStatus = task.getStatus();
                log.info("幂等性检查: taskId={}, 当前状态={}, 期望状态=[QUEUED, RETRYING]", 
                         finalTaskId, currentStatus);

                if (currentStatus == com.ainovel.server.task.model.TaskStatus.RUNNING) {
                    // 任务已在运行，检查是否是本节点
                    if (nodeId.equals(task.getExecutionNodeId())) {
                         log.warn("任务已在本节点运行 (幂等性检查): taskId={}, executionNodeId={}", 
                                 finalTaskId, task.getExecutionNodeId());
                    } else {
                         log.warn("任务已在其他节点运行 (幂等性检查): taskId={}, executionNodeId={}", 
                                 finalTaskId, task.getExecutionNodeId());
                    }
                    return Mono.just(false); // 返回 false 表示不需要执行 trySetRunning
                }
                
                if (currentStatus != com.ainovel.server.task.model.TaskStatus.QUEUED && 
                    currentStatus != com.ainovel.server.task.model.TaskStatus.RETRYING) {
                    log.warn("任务状态不是QUEUED或RETRYING而是{} (幂等性检查): taskId={}", 
                            currentStatus, finalTaskId);
                    // 状态不正确，不能设置为RUNNING
                    return Mono.just(false); // 返回 false 表示不需要执行 trySetRunning
                }
                
                // 状态正确 (QUEUED 或 RETRYING)，可以尝试设置为RUNNING
                log.info("任务状态符合预期，尝试原子更新为 RUNNING: taskId={}", finalTaskId);
                return taskStateService.trySetRunning(finalTaskId, nodeId);
            })
            .flatMap(isSetRunning -> { // isSetRunning 是 trySetRunning 的结果 (如果执行了的话)
                                      // 或者是在状态检查后直接返回的 false
                if (!isSetRunning) {
                    // 如果 isSetRunning 为 false，原因可能是：
                    // 1. 状态检查时发现已在运行或状态不符
                    // 2. trySetRunning 原子更新失败（被其他节点抢先）
                    log.warn("无法继续处理任务 (幂等性检查失败或原子更新失败): taskId={}, taskType={}", 
                          finalTaskId, finalTaskType);
                    
                    // 再次尝试获取任务当前状态,以便更好地诊断问题
                    return taskStateService.getTask(finalTaskId)
                        .doOnNext(task -> {
                            log.info("任务当前状态 (处理中止): taskId={}, status={}, executionNodeId={}, retryCount={}", 
                                  task.getId(), task.getStatus(), task.getExecutionNodeId(), task.getRetryCount());
                            
                            // 检查ID转换问题 (理论上不应发生在此处)
                            if (!task.getId().equals(finalTaskId)) {
                                log.error("严重错误: 获取的任务ID({})与请求的ID({})不一致!", 
                                        task.getId(), finalTaskId);
                            }
                        })
                        // switchIfEmpty 处理 getTask 失败的情况
                        .switchIfEmpty(Mono.<BackgroundTask>defer(() -> {
                            log.error("无法获取任务当前状态 (处理中止): taskId={}", finalTaskId);
                            return Mono.empty();
                        })) 
                        .then(Mono.empty()); // 处理链终止，返回空的 Mono<Void>
                }
                
                // isSetRunning 为 true，表示成功将任务状态更新为 RUNNING
                log.info("成功将任务设置为 RUNNING 状态，开始执行: taskId={}", finalTaskId);

                // 查找任务执行器
                return taskExecutorService.findExecutor(finalTaskType)
                    .doOnNext(executor -> log.info("找到任务执行器: taskType={}, executorClass={}", 
                              finalTaskType, executor.getClass().getName()))
                    .switchIfEmpty(Mono.<BackgroundTaskExecutable<Object, Object>>defer(() -> {
                        log.error("找不到任务类型为 {} 的执行器: taskId={}", finalTaskType, finalTaskId);
                        // 找不到执行器是严重错误，应该导致任务失败
                        return Mono.error(new IllegalArgumentException("找不到任务类型为 " + finalTaskType + " 的执行器"));
                    }))
                    .flatMap(executable -> {
                        // 发布任务开始事件（此处尚未获取 task 详情，无法安全获取 parentTaskId）
                        eventPublisher.publishEvent(new TaskStartedEvent(this, finalTaskId, finalTaskType, null, nodeId));
                        log.info("已发布任务开始事件: taskId={}, taskType={}", finalTaskId, finalTaskType);
                        
                        // 查询最新的任务信息 (可能包含刚更新的 RUNNING 状态)
                        return taskStateService.getTask(finalTaskId)
                            .switchIfEmpty(Mono.<BackgroundTask>defer(() -> {
                                log.error("获取任务信息失败 (准备执行前): taskId={}", finalTaskId);
                                return Mono.error(new IllegalStateException("获取任务信息失败: " + finalTaskId));
                            }))
                            .doOnNext(task -> log.info("获取到任务信息 (准备执行): taskId={}, taskType={}, userId={}, status={}", 
                                      task.getId(), task.getTaskType(), task.getUserId(), task.getStatus()))
                            .flatMap(task -> {
                                // 获取任务参数并转换为正确类型
                                log.debug("开始转换任务参数: taskId={}, taskType={}, 原始参数类型={}", 
                                        finalTaskId, finalTaskType, 
                                        (task.getParameters() != null ? task.getParameters().getClass().getName() : "null"));
                                return taskConversionConfig.convertParametersToType(finalTaskType, task.getParameters())
                                    .doOnError(error -> {
                                        log.error("参数转换失败: taskId={}, taskType={}, 错误: {}", 
                                                finalTaskId, finalTaskType, error.getMessage(), error);
                                    })
                                    .onErrorResume(error -> Mono.error(new IllegalArgumentException("参数转换失败", error))) // 包装错误
                                    .doOnNext(typedParams -> log.debug("转换后的任务参数: taskId={}, params={}", 
                                              finalTaskId, 
                                              (typedParams != null ? 
                                                      typedParams.getClass().getName() + "@" + 
                                                      Integer.toHexString(System.identityHashCode(typedParams)) : 
                                                      "null")))
                                    .flatMap(typedParams -> {
                                        // 创建任务上下文
                                        TaskContext<?> context = createTaskContext(
                                            task, finalTaskType, typedParams, finalRetryCount);
                                        log.debug("创建任务上下文: taskId={}, contextTaskId={}", 
                                               finalTaskId, context.getTaskId());
                                        
                                        // 测试获取相同的任务对象是否返回相同ID (一致性检查)
                                        if (!context.getTaskId().equals(finalTaskId)) {
                                            log.error("严重错误: 上下文中的任务ID({})与消息中的任务ID({})不一致!", 
                                                    context.getTaskId(), finalTaskId);
                                            // 这是严重问题，应该立即失败
                                            return Mono.error(new IllegalStateException("任务ID不一致")); 
                                        }
                                        
                                        // 记录任务执行前的任务信息
                                        taskStateService.getTask(finalTaskId)
                                            .doOnNext(taskBeforeExecution -> {
                                                log.info("任务执行前状态: taskId={}, status={}, executionNodeId={}, " +
                                                        "type={}, retryCount={}, parameters={}",
                                                        taskBeforeExecution.getId(),
                                                        taskBeforeExecution.getStatus(),
                                                        taskBeforeExecution.getExecutionNodeId(),
                                                        taskBeforeExecution.getTaskType(),
                                                        taskBeforeExecution.getRetryCount(),
                                                        taskBeforeExecution.getParameters());
                                            })
                                            .subscribeOn(Schedulers.boundedElastic()) // 在不同线程执行日志记录，避免阻塞主流程
                                            .subscribe(); // 触发执行，但不阻塞
                                        
                                        // 执行任务
                                        log.info("开始执行任务: taskId={}, taskType={}, retryCount={}/{}", 
                                              finalTaskId, finalTaskType, finalRetryCount, maxRetryAttempts);
                                        return executeTask(executable, context)
                                            .doOnSuccess(result -> {
                                                log.info("任务执行完成: taskId={}, taskType={}, 结果类型: {}", 
                                                          finalTaskId, finalTaskType, 
                                                          (result.getResult() != null ? result.getResult().getClass().getName() : "null"));
                                                
                                                // 记录任务执行后的任务信息
                                                taskStateService.getTask(finalTaskId)
                                                    .doOnNext(taskAfterExecution -> {
                                                        log.info("任务执行后状态: taskId={}, status={}, executionNodeId={}, " +
                                                                "type={}, retryCount={}",
                                                                taskAfterExecution.getId(),
                                                                taskAfterExecution.getStatus(),
                                                                taskAfterExecution.getExecutionNodeId(),
                                                                taskAfterExecution.getTaskType(),
                                                                taskAfterExecution.getRetryCount());
                                                    })
                                                    .subscribeOn(Schedulers.boundedElastic()) // 在不同线程执行
                                                    .subscribe(); // 触发执行
                                            })
                                            .doOnError(error -> log.error("任务执行失败: taskId={}, taskType={}, 错误: {}", 
                                                     finalTaskId, finalTaskType, error.getMessage(), error))
                                            .flatMap(result -> {
                        // 处理执行结果
                                                if (result.isSuccess()) {
                                                    // 成功完成
                            return handleSuccessResult(task, result.getResult());
                                                } else if (result.isRetryable() && finalRetryCount < maxRetryAttempts) {
                                                    // 可重试且未达到最大重试次数
                                                    return handleRetryableFailure(task, result.getError(), finalRetryCount);
                                                } else if (result.isRetryable()) {
                                                    // 可重试但已达到最大重试次数
                                                    return handleDeadLetter(task, result.getError(), "达到最大重试次数");
                                                } else if (result.isNonRetryable()) {
                                                    // 不可重试错误
                                                    return handleNonRetryableFailure(task, result.getError());
                                                } else if (result.isCancelled()) {
                                                    // 任务被取消
                                                    return handleCancellation(task);
                                                } else {
                                                    // 未知结果状态
                                                    log.error("未知的任务结果状态: taskId={}, status={}", finalTaskId, result.getStatus());
                                                    return Mono.error(new IllegalStateException("未知的任务结果状态"));
                                                }
                                            });
                                    });
                            });
                    });
            }); // flatMap(isSetRunning -> { ... }) 结束
    }
    
    /**
     * 创建任务上下文
     * 
     * @param task 任务对象
     * @param taskType 任务类型
     * @param parameters 任务参数
     * @param retryCount 重试次数
     * @return 任务上下文
     */
    @SuppressWarnings("unchecked")
    private <P> TaskContext<P> createTaskContext(
            BackgroundTask task, 
            String taskType, 
            Object parameters, 
            int retryCount) {
        
        return TaskContextImpl.<P>builder()
                .taskId(task.getId())
                .taskType(taskType)
                .userId(task.getUserId())
                .parameters((P) parameters)
                .executionNodeId(nodeId)
                .parentTaskId(task.getParentTaskId())
                .taskStateService(taskStateService)
                .taskSubmissionService(taskSubmissionService)
                .eventPublisher(eventPublisher)
                .build();
    }
    
    /**
     * 类型安全地执行任务
     * 
     * @param executable 任务执行器
     * @param context 任务上下文
     * @return 执行结果的Mono
     */
    @SuppressWarnings({"unchecked", "rawtypes"})
    private Mono<ExecutionResult<?>> executeTask(BackgroundTaskExecutable<?, ?> executable, TaskContext<?> context) {
        try {
            // 使用原始类型避免泛型问题
            log.info("开始执行任务, taskId={}, taskType={}, executableClass={}, contextParameters={}", 
                    context.getTaskId(), context.getTaskType(), 
                    executable.getClass().getSimpleName(),
                    (context.getParameters() != null ? context.getParameters().getClass().getSimpleName() : "null"));
            return taskExecutorService.executeTask((BackgroundTaskExecutable) executable, context);
        } catch (Exception e) {
            log.error("执行任务时发生异常: taskId={}", context.getTaskId(), e);
            return Mono.just(ExecutionResult.nonRetryableFailure(e));
        }
    }
    
    /**
     * 处理成功结果
     * 
     * @param task 任务对象
     * @param result 结果对象
     * @return 完成信号
     */
    private Mono<Void> handleSuccessResult(BackgroundTask task, Object result) {
        log.info("任务执行成功: taskId={}, taskType={}", task.getId(), task.getTaskType());
        try {
            // 针对父任务 CONTINUE_WRITING_CONTENT：返回 RUNNING 仅表示已进入子任务驱动流程，不应标记完成
            if (result instanceof ContinueWritingContentResult cResult) {
                if (cResult.getStatus() == TaskStatus.RUNNING) {
                    log.info("父任务初始结果为 RUNNING，记录进度，不发布 Completed: taskId={}", task.getId());
                    return taskStateService.recordProgress(task.getId(), cResult);
                }
            }
        } catch (Throwable ignore) {}

        // 其他任务（如子任务）仍按完成处理：先持久化，再发布 Completed 事件
        return taskStateService.recordCompletion(task.getId(), result)
                .doOnSuccess(v -> {
                    try {
                        eventPublisher.publishEvent(new TaskCompletedEvent(this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId(), result));
                    } catch (Throwable ex) {
                        log.warn("发布 TaskCompletedEvent 失败: taskId={} error={}", task.getId(), ex.toString());
                    }
                });
    }
    
    /**
     * 处理可重试的失败
     * 
     * @param task 任务对象
     * @param error 错误对象
     * @param retryCount 当前重试次数
     * @return 完成信号
     */
    private Mono<Void> handleRetryableFailure(BackgroundTask task, Throwable error, int retryCount) {
        log.info("任务将进行重试: taskId={}, taskType={}, retryCount={}/{}", 
                task.getId(), task.getTaskType(), retryCount, maxRetryAttempts);
        
        // 计算下次重试延迟
        long delayMillis = getRetryDelay(retryCount);
        Instant nextAttemptTime = Instant.now().plusMillis(delayMillis);
        
        // 创建错误信息Map
        Map<String, Object> errorInfo = createErrorInfoMap(error);
        
        // 发布任务重试事件
        eventPublisher.publishEvent(new TaskRetryingEvent(
                this, task.getId(), task.getTaskType(), task.getUserId(), 
                retryCount + 1, maxRetryAttempts, delayMillis, errorInfo));
        
        // 重新发送带有延迟的消息
        return taskMessageProducer.sendDelayedRetryTask(
                task.getId(), task.getUserId(), task.getTaskType(), task.getParameters(), 
                retryCount + 1, delayMillis)
            .then(taskStateService.recordRetrying(
                    task.getId(), retryCount + 1, error, nextAttemptTime));
    }
    
    /**
     * 处理不可重试的失败
     * 
     * @param task 任务对象
     * @param error 错误对象
     * @return 完成信号
     */
    private Mono<Void> handleNonRetryableFailure(BackgroundTask task, Throwable error) {
        log.error("任务执行失败（不可重试）: taskId={}, taskType={}", task.getId(), task.getTaskType(), error);
        
        // 创建错误信息Map
        Map<String, Object> errorInfo = createErrorInfoMap(error);
        
        // 发布任务失败事件
        eventPublisher.publishEvent(new TaskFailedEvent(
                this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId(), errorInfo, false));
        
        // 更新数据库状态
        return taskStateService.recordFailure(task.getId(), errorInfo, false);
    }
    
    /**
     * 处理达到最大重试次数的任务（死信）
     * 
     * @param task 任务对象
     * @param error 错误对象
     * @param reason 原因描述
     * @return 完成信号
     */
    private Mono<Void> handleDeadLetter(BackgroundTask task, Throwable error, String reason) {
        log.error("任务进入死信: taskId={}, taskType={}, reason={}", 
                task.getId(), task.getTaskType(), reason, error);
        
        // 创建错误信息Map
        Map<String, Object> errorInfo = createErrorInfoMap(error);
        errorInfo.put("deadLetterReason", reason);
        
        // 发布任务失败事件（标记为死信）
        eventPublisher.publishEvent(new TaskFailedEvent(
                this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId(), errorInfo, true));
        
        // 更新数据库状态
        return taskStateService.recordFailure(task.getId(), errorInfo, true);
    }
    
    /**
     * 处理任务取消
     * 
     * @param task 任务对象
     * @return 完成信号
     */
    private Mono<Void> handleCancellation(BackgroundTask task) {
        log.info("任务已被取消: taskId={}, taskType={}", task.getId(), task.getTaskType());
        
        // 发布任务取消事件
        eventPublisher.publishEvent(new TaskCancelledEvent(
                this, task.getId(), task.getTaskType(), task.getUserId(), task.getParentTaskId()));
        
        // 更新数据库状态
        return taskStateService.recordCancellation(task.getId());
    }
    
    /**
     * 确认消息
     * 
     * @param channel 通道
     * @param deliveryTag 投递标签
     * @throws IOException 如果确认失败
     */
    private void ackMessage(Channel channel, long deliveryTag) throws IOException {
        channel.basicAck(deliveryTag, false);
        log.debug("确认消息: deliveryTag={}", deliveryTag);
    }
    
    /**
     * 拒绝消息
     * 
     * @param channel 通道
     * @param deliveryTag 投递标签
     * @param requeue 是否重新排队
     * @throws IOException 如果拒绝失败
     */
    private void nackMessage(Channel channel, long deliveryTag, boolean requeue) throws IOException {
        channel.basicNack(deliveryTag, false, requeue);
        log.debug("拒绝消息: deliveryTag={}, requeue={}", deliveryTag, requeue);
    }
    
    /**
     * 获取重试延迟时间
     * 
     * @param retryCount 当前重试次数
     * @return 延迟毫秒数
     */
    private long getRetryDelay(int retryCount) {
        if (retryCount < retryDelays.length) {
            return retryDelays[retryCount];
        }
        // 如果重试次数超过配置的延迟数组长度，使用最后一个延迟值
        return retryDelays[retryDelays.length - 1];
    }
    
    /**
     * 创建错误信息Map
     * 
     * @param error 错误对象
     * @return 错误信息Map
     */
    private Map<String, Object> createErrorInfoMap(Throwable error) {
        Map<String, Object> errorInfo = new HashMap<>();
        errorInfo.put("message", error.getMessage());
        errorInfo.put("exceptionClass", error.getClass().getName());
        errorInfo.put("timestamp", Instant.now().toString());
        
        // 添加堆栈跟踪（可选，可能会增加存储开销）
        StackTraceElement[] stackTrace = error.getStackTrace();
        if (stackTrace != null && stackTrace.length > 0) {
            String[] stackTraceStrings = new String[Math.min(stackTrace.length, 10)]; // 限制堆栈深度
            for (int i = 0; i < stackTraceStrings.length; i++) {
                stackTraceStrings[i] = stackTrace[i].toString();
            }
            errorInfo.put("stackTrace", stackTraceStrings);
        }
        
        // 添加根本原因
        Throwable cause = error.getCause();
        if (cause != null && cause != error) {
            Map<String, String> causeInfo = new HashMap<>();
            causeInfo.put("message", cause.getMessage());
            causeInfo.put("exceptionClass", cause.getClass().getName());
            errorInfo.put("cause", causeInfo);
        }
        
        return errorInfo;
    }
} 