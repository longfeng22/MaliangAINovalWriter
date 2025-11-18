package com.ainovel.server.domain.model.observability;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.annotation.PersistenceCreator;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import lombok.extern.slf4j.Slf4j;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.UUID;

/**
 * LLM调用链路追踪数据模型
 * 存储大模型调用的完整信息，用于监控、调试和分析
 */
@Slf4j
@Data
@Builder
@NoArgsConstructor(access = AccessLevel.PUBLIC)
@AllArgsConstructor(access = AccessLevel.PUBLIC)
    
@Document(collection = "llm_traces")
@CompoundIndexes({
    @CompoundIndex(name = "user_provider_model_idx", def = "{'userId': 1, 'provider': 1, 'model': 1}"),
    @CompoundIndex(name = "session_timestamp_idx", def = "{'sessionId': 1, 'request.timestamp': -1}"),
    @CompoundIndex(name = "provider_model_performance_idx", def = "{'provider': 1, 'model': 1, 'performance.totalDurationMs': -1}")
})
public class LLMTrace {



    @Id
    private String id;

    /**
     * 唯一链路ID
     */
    @Indexed(unique = true, sparse = true)
    private String traceId;

    /**
     * 关联ID，用于关联业务流程中的多个LLM调用
     */
    @Indexed
    private String correlationId;

    /**
     * 会话ID
     */
    @Indexed
    private String sessionId;

    /**
     * 用户ID
     */
    @Indexed
    private String userId;

    /**
     * 提供商名称
     */
    @Indexed
    private String provider;

    /**
     * 模型名称
     */
    @Indexed
    private String model;

    /**
     * 调用类型
     */
    @Indexed
    private CallType type;

    /**
     * 业务类型 - 反映具体的AI功能类型，如TEXT_EXPANSION、AI_CHAT等
     */
    @Indexed
    private String businessType;

    /**
     * 请求信息
     */
    @Builder.Default
    private Request request = new Request();

    /**
     * 响应信息（成功时填充）
     */
    private Response response;

    /**
     * 错误信息（失败时填充）
     */
    private Error error;

    /**
     * 性能指标
     */
    @Builder.Default
    private Performance performance = new Performance();

    /**
     * 文档创建时间
     */
    @Indexed
    @Builder.Default
    private Instant createdAt = Instant.now();

    /**
     * 调用类型枚举
     */
    public enum CallType {
        CHAT, STREAMING_CHAT, COMPLETION, STREAMING_COMPLETION
    }

    /**
     * 请求信息
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Request {
        private Instant timestamp;
        
        @Builder.Default
        private List<MessageInfo> messages = new ArrayList<>();
        
        @Builder.Default
        private Parameters parameters = new Parameters();
        
        @PersistenceCreator
        @JsonCreator
        public Request(
            @JsonProperty("timestamp") Instant timestamp,
            @JsonProperty("messages") List<MessageInfo> messages,
            @JsonProperty("parameters") Parameters parameters) {
            this.timestamp = timestamp;
            this.messages = messages != null ? messages : new ArrayList<>();
            this.parameters = parameters != null ? parameters : new Parameters();
        }
    }

    /**
     * 消息信息
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class MessageInfo {
        private String role;
        private String content;
        
        // 支持工具调用的消息
        @Builder.Default
        private List<ToolCallInfo> toolCalls = new ArrayList<>();
        
        @PersistenceCreator
        @JsonCreator
        public MessageInfo(
            @JsonProperty("role") String role,
            @JsonProperty("content") String content,
            @JsonProperty("toolCalls") List<ToolCallInfo> toolCalls) {
            this.role = role;
            this.content = content;
            this.toolCalls = toolCalls != null ? toolCalls : new ArrayList<>();
        }
    }

    /**
     * 工具调用信息
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class ToolCallInfo {
        private String id;
        private String type;
        private String functionName;
        private String arguments;
        
        @PersistenceCreator
        @JsonCreator
        public ToolCallInfo(
                @JsonProperty("id") String id,
                @JsonProperty("type") String type,
                @JsonProperty("functionName") String functionName,
                @JsonProperty("arguments") String arguments) {
            this.id = id;
            this.type = type;
            this.functionName = functionName;
            this.arguments = arguments;
        }
    }

    /**
     * 请求参数
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Parameters {
        // 通用参数
        private Double temperature;
        private Double topP;
        private Integer topK;
        private Integer maxOutputTokens;
        private String responseFormat;
        
        @Builder.Default
        private List<String> stopSequences = new ArrayList<>();
        
        // 工具/函数调用参数
        @Builder.Default
        private List<ToolSpecification> toolSpecifications = new ArrayList<>();
        private String toolChoice;
        
        // 提供商特定参数
        @Builder.Default
        private Map<String, Object> providerSpecific = new HashMap<>();
        
        @PersistenceCreator
        @JsonCreator
        public Parameters(
            @JsonProperty("temperature") Double temperature,
            @JsonProperty("topP") Double topP,
            @JsonProperty("topK") Integer topK,
            @JsonProperty("maxOutputTokens") Integer maxOutputTokens,
            @JsonProperty("responseFormat") String responseFormat,
            @JsonProperty("stopSequences") List<String> stopSequences,
            @JsonProperty("toolSpecifications") List<ToolSpecification> toolSpecifications,
            @JsonProperty("toolChoice") String toolChoice,
            @JsonProperty("providerSpecific") Object providerSpecific) {
            this.temperature = temperature;
            this.topP = topP;
            this.topK = topK;
            this.maxOutputTokens = maxOutputTokens;
            this.responseFormat = responseFormat;
            this.stopSequences = stopSequences != null ? stopSequences : new ArrayList<>();
            this.toolSpecifications = toolSpecifications != null ? toolSpecifications : new ArrayList<>();
            this.toolChoice = toolChoice;
            this.providerSpecific = safeConvertToMap(providerSpecific);
        }
        
        /**
         * 安全地将对象转换为Map<String, Object>
         */
        @SuppressWarnings("unchecked")
        private static Map<String, Object> safeConvertToMap(Object value) {
            if (value == null) {
                return new HashMap<>();
            }
            if (value instanceof Map) {
                try {
                    return (Map<String, Object>) value;
                } catch (ClassCastException e) {
                    // 如果类型转换失败，创建一个新的Map
                    Map<String, Object> result = new HashMap<>();
                    if (value instanceof Map<?, ?>) {
                        ((Map<?, ?>) value).forEach((k, v) -> 
                            result.put(k != null ? k.toString() : null, v));
                    }
                    return result;
                }
            }
            // 对于其他类型，包装在一个Map中
            Map<String, Object> result = new HashMap<>();
            result.put("value", value);
            return result;
        }
    }

    /**
     * 工具规范
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class ToolSpecification {
        private String name;
        private String description;
        private Map<String, Object> parameters;
        
        @PersistenceCreator
        @JsonCreator
        public ToolSpecification(
            @JsonProperty("name") String name,
            @JsonProperty("description") String description,
            @JsonProperty("parameters") Object parameters) {
            this.name = name;
            this.description = description;
            this.parameters = safeConvertToMap(parameters);
        }
        
        /**
         * 安全地将对象转换为Map<String, Object>
         */
        @SuppressWarnings("unchecked")
        private static Map<String, Object> safeConvertToMap(Object value) {
            if (value == null) {
                return new HashMap<>();
            }
            if (value instanceof Map) {
                try {
                    return (Map<String, Object>) value;
                } catch (ClassCastException e) {
                    // 如果类型转换失败，创建一个新的Map
                    Map<String, Object> result = new HashMap<>();
                    if (value instanceof Map<?, ?>) {
                        ((Map<?, ?>) value).forEach((k, v) -> 
                            result.put(k != null ? k.toString() : null, v));
                    }
                    return result;
                }
            }
            // 对于其他类型，包装在一个Map中
            Map<String, Object> result = new HashMap<>();
            result.put("value", value);
            return result;
        }
    }

    /**
     * 响应信息
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Response {
        private Instant timestamp;
        private MessageInfo message;
        private Metadata metadata;
        
        @PersistenceCreator
        @JsonCreator
        public Response(
                @JsonProperty("timestamp") Instant timestamp,
                @JsonProperty("message") MessageInfo message,
                @JsonProperty("metadata") Metadata metadata) {
            this.timestamp = timestamp;
            this.message = message;
            this.metadata = metadata;
        }

        /**
         * 兼容前端可观测性模型：将 message.content 暴露为根级 content
         */
        @com.fasterxml.jackson.annotation.JsonProperty("content")
        public String getContentForFrontend() {
            return this.message != null ? this.message.getContent() : null;
        }

        /**
         * 兼容前端可观测性模型：将 metadata.id 暴露为根级 id
         */
        @com.fasterxml.jackson.annotation.JsonProperty("id")
        public String getIdForFrontend() {
            return this.metadata != null ? this.metadata.getId() : null;
        }

        /**
         * 兼容前端可观测性模型：将 metadata.finishReason 暴露为根级 finishReason
         */
        @com.fasterxml.jackson.annotation.JsonProperty("finishReason")
        public String getFinishReasonForFrontend() {
            return this.metadata != null ? this.metadata.getFinishReason() : null;
        }

        /**
         * 兼容前端可观测性模型：将 TokenUsageInfo 转为 {promptTokens, completionTokens, totalTokens}
         */
        @com.fasterxml.jackson.annotation.JsonProperty("tokenUsage")
        public java.util.Map<String, java.lang.Integer> getTokenUsageForFrontend() {
            if (this.metadata == null || this.metadata.getTokenUsage() == null) {
                return null;
            }
            TokenUsageInfo u = this.metadata.getTokenUsage();
            java.util.Map<String, java.lang.Integer> map = new java.util.HashMap<>();
            if (u.getInputTokenCount() != null) {
                map.put("promptTokens", u.getInputTokenCount());
            }
            if (u.getOutputTokenCount() != null) {
                map.put("completionTokens", u.getOutputTokenCount());
            }
            if (u.getTotalTokenCount() != null) {
                map.put("totalTokens", u.getTotalTokenCount());
            }
            return map.isEmpty() ? null : map;
        }
    }

    /**
     * 兼容前端：将请求消息与响应消息中的 toolCalls 聚合为根级字段，并将参数解析为对象
     * 目标结构：[{ id, name, arguments: {...}, timestamp? }]
     */
    @com.fasterxml.jackson.annotation.JsonProperty("toolCalls")
    public List<Map<String, Object>> getToolCallsForFrontend() {
        List<Map<String, Object>> result = new ArrayList<>();

        // 从请求消息聚合
        try {
            if (this.request != null && this.request.getMessages() != null) {
                for (MessageInfo msg : this.request.getMessages()) {
                    if (msg.getToolCalls() != null) {
                        for (ToolCallInfo tc : msg.getToolCalls()) {
                            result.add(convertToolCallInfo(tc));
                        }
                    }
                }
            }
        } catch (Exception ignore) {}

        // 从响应消息聚合
        try {
            if (this.response != null && this.response.getMessage() != null && this.response.getMessage().getToolCalls() != null) {
                for (ToolCallInfo tc : this.response.getMessage().getToolCalls()) {
                    result.add(convertToolCallInfo(tc));
                }
            }
        } catch (Exception ignore) {}

        return result.isEmpty() ? null : result;
    }

    private Map<String, Object> convertToolCallInfo(ToolCallInfo info) {
        Map<String, Object> map = new HashMap<>();
        String id = info.getId() != null && !info.getId().isBlank() ? info.getId() : UUID.randomUUID().toString();
        map.put("id", id);
        String name = info.getFunctionName() != null && !info.getFunctionName().isBlank() ? info.getFunctionName() : info.getType();
        map.put("name", name);
        map.put("arguments", safeParseJsonToMap(info.getArguments()));
        return map;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> safeParseJsonToMap(String json) {
        if (json == null || json.isBlank()) {
            return new HashMap<>();
        }
        try {
            ObjectMapper mapper = new ObjectMapper();
            Object node = mapper.readValue(json, Object.class);
            if (node instanceof Map) {
                return (Map<String, Object>) node;
            }
            Map<String, Object> wrap = new HashMap<>();
            if (node instanceof List) {
                wrap.put("list", node);
            } else {
                wrap.put("value", node);
            }
            return wrap;
        } catch (Exception e) {
            Map<String, Object> wrap = new HashMap<>();
            wrap.put("raw", json);
            return wrap;
        }
    }

    /**
     * 响应元数据
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Metadata {
        private String id;
        private String finishReason;
        private TokenUsageInfo tokenUsage;
        
        // 提供商特定元数据
        @Builder.Default
        private Map<String, Object> providerSpecific = new HashMap<>();
        
        @PersistenceCreator
        @JsonCreator
        public Metadata(
            @JsonProperty("id") String id,
            @JsonProperty("finishReason") String finishReason,
            @JsonProperty("tokenUsage") TokenUsageInfo tokenUsage,
            @JsonProperty("providerSpecific") Object providerSpecific) {
            this.id = id;
            this.finishReason = finishReason;
            this.tokenUsage = tokenUsage;
            this.providerSpecific = safeConvertToMap(providerSpecific);
        }
        
        /**
         * 安全地将对象转换为Map<String, Object>
         */
        @SuppressWarnings("unchecked")
        private static Map<String, Object> safeConvertToMap(Object value) {
            if (value == null) {
                return new HashMap<>();
            }
            if (value instanceof Map) {
                try {
                    return (Map<String, Object>) value;
                } catch (ClassCastException e) {
                    // 如果类型转换失败，创建一个新的Map
                    Map<String, Object> result = new HashMap<>();
                    if (value instanceof Map<?, ?>) {
                        ((Map<?, ?>) value).forEach((k, v) -> 
                            result.put(k != null ? k.toString() : null, v));
                    }
                    return result;
                }
            }
            // 对于其他类型，包装在一个Map中
            Map<String, Object> result = new HashMap<>();
            result.put("value", value);
            return result;
        }
    }

    /**
     * Token使用情况
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class TokenUsageInfo {
        private Integer inputTokenCount;
        private Integer outputTokenCount;
        private Integer totalTokenCount;
        
        // 提供商特定Token信息
        @Builder.Default
        private Map<String, Object> providerSpecific = new HashMap<>();
        
        @PersistenceCreator
        @JsonCreator
        public TokenUsageInfo(
            @JsonProperty("inputTokenCount") Integer inputTokenCount,
            @JsonProperty("outputTokenCount") Integer outputTokenCount,
            @JsonProperty("totalTokenCount") Integer totalTokenCount,
            @JsonProperty("providerSpecific") Object providerSpecific) {
            this.inputTokenCount = inputTokenCount;
            this.outputTokenCount = outputTokenCount;
            this.totalTokenCount = totalTokenCount;
            this.providerSpecific = safeConvertToMap(providerSpecific);
        }
        
        /**
         * 安全地将对象转换为Map<String, Object>
         */
        @SuppressWarnings("unchecked")
        private static Map<String, Object> safeConvertToMap(Object value) {
            if (value == null) {
                return new HashMap<>();
            }
            if (value instanceof Map) {
                try {
                    return (Map<String, Object>) value;
                } catch (ClassCastException e) {
                    // 如果类型转换失败，创建一个新的Map
                    Map<String, Object> result = new HashMap<>();
                    if (value instanceof Map<?, ?>) {
                        ((Map<?, ?>) value).forEach((k, v) -> 
                            result.put(k != null ? k.toString() : null, v));
                    }
                    return result;
                }
            }
            // 对于其他类型，包装在一个Map中
            Map<String, Object> result = new HashMap<>();
            result.put("value", value);
            return result;
        }
    }

    /**
     * 错误信息
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Error {
        private Instant timestamp;
        private String message;
        private String type;
        private String stackTrace;
        
        @PersistenceCreator
        @JsonCreator
        public Error(
                @JsonProperty("timestamp") Instant timestamp,
                @JsonProperty("message") String message,
                @JsonProperty("type") String type,
                @JsonProperty("stackTrace") String stackTrace) {
            this.timestamp = timestamp;
            this.message = message;
            this.type = type;
            this.stackTrace = stackTrace;
        }
    }

    /**
     * 性能指标
     */
    @Data
    @Builder
    @NoArgsConstructor(access = AccessLevel.PUBLIC)
    public static class Performance {
        private Long requestLatencyMs;
        private Long firstTokenLatencyMs;
        private Long totalDurationMs;
        
        @PersistenceCreator
        @JsonCreator
        public Performance(
                @JsonProperty("requestLatencyMs") Long requestLatencyMs,
                @JsonProperty("firstTokenLatencyMs") Long firstTokenLatencyMs,
                @JsonProperty("totalDurationMs") Long totalDurationMs) {
            this.requestLatencyMs = requestLatencyMs;
            this.firstTokenLatencyMs = firstTokenLatencyMs;
            this.totalDurationMs = totalDurationMs;
        }
    }

    /**
     * 从AIRequest创建LLMTrace
     */
    public static LLMTrace fromRequest(String traceId, String provider, String model, AIRequest request) {
        // 从request的metadata中提取业务类型
        String businessType = null;
        if (request.getMetadata() != null) {
            Object requestType = request.getMetadata().get("requestType");
            if (requestType != null) {
                businessType = requestType.toString();
            }
        }
        
        LLMTrace trace = LLMTrace.builder()
                .traceId(traceId)
                .userId(request.getUserId())
                .sessionId(request.getSessionId())
                .provider(provider)
                .model(model)
                .type(CallType.CHAT)
                .businessType(businessType)
                .build();

        // 填充请求信息
        Request requestInfo = Request.builder()
                .timestamp(Instant.now())
                .build();

        // 转换消息
        List<MessageInfo> messages = new ArrayList<>();
        if (request.getPrompt() != null && !request.getPrompt().isEmpty()) {
            messages.add(MessageInfo.builder()
                    .role("system")
                    .content(request.getPrompt())
                    .build());
        }

        if (request.getMessages() != null) {
            for (AIRequest.Message msg : request.getMessages()) {
                MessageInfo.MessageInfoBuilder messageBuilder = MessageInfo.builder()
                        .role(msg.getRole())
                        .content(msg.getContent());
                
                // 转换工具调用请求
                if (msg.getToolExecutionRequests() != null && !msg.getToolExecutionRequests().isEmpty()) {
                    List<ToolCallInfo> toolCalls = new ArrayList<>();
                    for (AIRequest.ToolExecutionRequest toolRequest : msg.getToolExecutionRequests()) {
                        toolCalls.add(ToolCallInfo.builder()
                                .id(toolRequest.getId())
                                .type("function")
                                .functionName(toolRequest.getName())
                                .arguments(toolRequest.getArguments())
                                .build());
                    }
                    messageBuilder.toolCalls(toolCalls);
                }
                
                // 处理工具执行结果消息
                if ("tool".equals(msg.getRole()) && msg.getToolExecutionResult() != null) {
                    // 工具结果可以添加到消息内容中，或者作为特殊标识
                    AIRequest.ToolExecutionResult result = msg.getToolExecutionResult();
                    String resultContent = msg.getContent();
                    if (resultContent == null || resultContent.isEmpty()) {
                        resultContent = "Tool: " + result.getToolName() + ", Result: " + result.getResult();
                        messageBuilder.content(resultContent);
                    }
                }
                
                messages.add(messageBuilder.build());
            }
        }
        requestInfo.setMessages(messages);

        // 设置参数
        Parameters.ParametersBuilder paramsBuilder = Parameters.builder()
                .temperature(request.getTemperature())
                .maxOutputTokens(request.getMaxTokens());
        
        // 工具规范序列化交由 RichTraceChatModelListener 按配置决定是否写入
        
        // 仅提取并写入 providerSpecific（与业务标记位置一致）
        if (request.getParameters() != null) {
            Map<String, Object> providerSpecific = new HashMap<>();
            Object ps = request.getParameters().get("providerSpecific");
            if (ps instanceof Map<?, ?> m) {
                for (Map.Entry<?, ?> e : m.entrySet()) {
                    Object key = e.getKey();
                    if (key != null) {
                        providerSpecific.put(key.toString(), e.getValue());
                    }
                }
            }
            paramsBuilder.providerSpecific(providerSpecific);
        }
        
        requestInfo.setParameters(paramsBuilder.build());

        trace.setRequest(requestInfo);
        return trace;
    }

    /**
     * 设置流式调用类型
     */
    public void setStreamingType() {
        this.type = CallType.STREAMING_CHAT;
    }

    /**
     * 设置响应信息
     */
    public void setResponseFromAIResponse(AIResponse aiResponse, Instant timestamp) {
        MessageInfo messageInfo = MessageInfo.builder()
                .role("assistant")
                .content(aiResponse.getContent())
                .build();

        // 转换工具调用
        if (aiResponse.getToolCalls() != null) {
            List<ToolCallInfo> toolCalls = new ArrayList<>();
            for (AIResponse.ToolCall toolCall : aiResponse.getToolCalls()) {
                toolCalls.add(ToolCallInfo.builder()
                        .id(toolCall.getId())
                        .type(toolCall.getType())
                        .functionName(toolCall.getFunction() != null ? toolCall.getFunction().getName() : null)
                        .arguments(toolCall.getFunction() != null ? toolCall.getFunction().getArguments() : null)
                        .build());
            }
            messageInfo.setToolCalls(toolCalls);
        }

        TokenUsageInfo tokenUsage = null;
        if (aiResponse.getTokenUsage() != null) {
            tokenUsage = TokenUsageInfo.builder()
                    .inputTokenCount(aiResponse.getTokenUsage().getPromptTokens())
                    .outputTokenCount(aiResponse.getTokenUsage().getCompletionTokens())
                    .totalTokenCount(aiResponse.getTokenUsage().getTotalTokens())
                    .build();
        }

        Metadata metadata = Metadata.builder()
                .id(aiResponse.getId())
                .finishReason(aiResponse.getFinishReason())
                .tokenUsage(tokenUsage)
                .build();

        this.response = Response.builder()
                .timestamp(timestamp)
                .message(messageInfo)
                .metadata(metadata)
                .build();
    }

    /**
     * 设置流式响应信息（保持向后兼容）
     */
    public void setResponseFromStreamingResult(String content, Instant timestamp) {
        setResponseFromStreamingResult(content, timestamp, null);
    }

    /**
     * 设置流式响应信息（支持token信息）
     */
    public void setResponseFromStreamingResult(String content, Instant timestamp, Object tokenUsage) {
        MessageInfo messageInfo = MessageInfo.builder()
                .role("assistant")
                .content(content)
                .build();

        Metadata.MetadataBuilder metadataBuilder = Metadata.builder()
                .finishReason("stop");

        // 处理token使用信息
        if (tokenUsage instanceof AIResponse.TokenUsage aiResponseUsage) {
            TokenUsageInfo tokenUsageInfo = TokenUsageInfo.builder()
                    .inputTokenCount(aiResponseUsage.getPromptTokens())
                    .outputTokenCount(aiResponseUsage.getCompletionTokens())
                    .totalTokenCount(aiResponseUsage.getTotalTokens())
                    .build();
            metadataBuilder.tokenUsage(tokenUsageInfo);
        } else if (tokenUsage != null && hasTokenUsageMethods(tokenUsage)) {
            // 处理通用的token使用对象（如TokenUsageWrapper）
            try {
                Integer promptTokens = (Integer) tokenUsage.getClass().getMethod("getPromptTokens").invoke(tokenUsage);
                Integer completionTokens = (Integer) tokenUsage.getClass().getMethod("getCompletionTokens").invoke(tokenUsage);
                Integer totalTokens = (Integer) tokenUsage.getClass().getMethod("getTotalTokens").invoke(tokenUsage);
                
                TokenUsageInfo tokenUsageInfo = TokenUsageInfo.builder()
                        .inputTokenCount(promptTokens)
                        .outputTokenCount(completionTokens)
                        .totalTokenCount(totalTokens)
                        .build();
                metadataBuilder.tokenUsage(tokenUsageInfo);
            } catch (Exception e) {
                log.warn("无法解析token使用信息: {}", e.getMessage());
            }
        }

        this.response = Response.builder()
                .timestamp(timestamp)
                .message(messageInfo)
                .metadata(metadataBuilder.build())
                .build();
    }

    /**
     * 设置错误信息
     */
    public void setErrorFromThrowable(Throwable throwable, Instant timestamp) {
        this.error = Error.builder()
                .timestamp(timestamp)
                .message(throwable.getMessage())
                .type(throwable.getClass().getSimpleName())
                .stackTrace(getStackTraceAsString(throwable))
                .build();
    }

    private String getStackTraceAsString(Throwable throwable) {
        java.io.StringWriter sw = new java.io.StringWriter();
        java.io.PrintWriter pw = new java.io.PrintWriter(sw);
        throwable.printStackTrace(pw);
        return sw.toString();
    }

    /**
     * 检查对象是否有token使用的相关方法
     */
    private boolean hasTokenUsageMethods(Object tokenUsage) {
        try {
            Class<?> clazz = tokenUsage.getClass();
            return clazz.getMethod("getPromptTokens") != null &&
                   clazz.getMethod("getCompletionTokens") != null &&
                   clazz.getMethod("getTotalTokens") != null;
        } catch (NoSuchMethodException e) {
            return false;
        }
    }
    
    // 工具规范序列化已迁移到 RichTraceChatModelListener，且可通过配置开关控制
} 