package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.model.openai.OpenAiStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import reactor.core.publisher.Sinks;
import reactor.netty.http.client.HttpClient;
import io.netty.channel.ChannelOption;
import java.util.HashMap;
import java.util.Map;

/**
 * 豆包（字节跳动/火山引擎 Ark）- OpenAI 兼容模式 Provider
 * 说明：豆包官方提供 OpenAI-Compatible API，可通过 OpenAiChatModel 直接接入
 */
@Slf4j
public class DoubaoLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    // Ark OpenAI 兼容 API 基地址
    private static final String DEFAULT_API_ENDPOINT = "https://ark.cn-beijing.volces.com/api/v3";
    private static final ObjectMapper objectMapper = new ObjectMapper();
    private WebClient doubaoWebClient;


    public DoubaoLangChain4jModelProvider(
            String modelName,
            String apiKey,
            String apiEndpoint,
            ProxyConfig proxyConfig,
            ChatModelListenerManager listenerManager
    ) {
        super("doubao", modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);
            if (baseUrl == null || baseUrl.trim().isEmpty()) {
                baseUrl = DEFAULT_API_ENDPOINT;
            }

            // 初始化自定义WebClient用于处理豆包特有的reasoning_content
            initDoubaoWebClient(baseUrl);

            // 国内平台：不配置系统代理
            var listeners = getListeners();

            var chatBuilder = OpenAiChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            if (!listeners.isEmpty()) {
                chatBuilder.listeners(listeners);
            }
            this.chatModel = chatBuilder.build();

            var streamingBuilder = OpenAiStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .timeout(Duration.ofSeconds(300))
                    .logRequests(true)
                    .logResponses(true);
            if (!listeners.isEmpty()) {
                streamingBuilder.listeners(listeners);
            }
            this.streamingChatModel = streamingBuilder.build();

            log.info("Doubao(Ark) 模型初始化成功: {} @ {}", modelName, baseUrl);
        } catch (Exception e) {
            log.error("初始化 Doubao(Ark) 模型时出错", e);
            this.chatModel = null;
            this.streamingChatModel = null;
        }
    }

    /**
     * 初始化豆包专用WebClient
     */
    private void initDoubaoWebClient(String baseUrl) {
        HttpClient httpClient = HttpClient.create()
                .responseTimeout(Duration.ofSeconds(120))
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10000);
        
        this.doubaoWebClient = WebClient.builder()
                .baseUrl(baseUrl)
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
        
        log.info("豆包自定义WebClient已初始化，基础URL: {}", baseUrl);
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request) {
        int inputTokens = estimateInputTokens(request);
        int outputTokens = request.getMaxTokens() != null ? request.getMaxTokens() : 1000;
        
        try {
            var pricingCalculator = getPricingCalculator();
            if (pricingCalculator != null) {
                return pricingCalculator.calculateTotalCost(modelName, inputTokens, outputTokens)
                        .map(cost -> cost.doubleValue() * 7.2);
            }
        } catch (Exception e) {
            log.debug("使用PricingCalculator失败: {}", e.getMessage());
        }
        
        double defaultPrice = 0.0015;
        int totalTokens = inputTokens + outputTokens;
        double costInUSD = (totalTokens / 1000.0) * defaultPrice;
        return Mono.just(costInUSD * 7.2);
    }
    
    private com.ainovel.server.service.ai.pricing.TokenPricingCalculator getPricingCalculator() {
        try {
            return applicationContext.getBeansOfType(
                com.ainovel.server.service.ai.pricing.TokenPricingCalculator.class)
                .values().stream()
                .filter(calc -> "doubao".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        log.info("开始 Doubao 流式生成，模型: {}", modelName);
        final long connectionStartTime = System.currentTimeMillis();
        final AtomicLong firstResponseTime = new AtomicLong(0);
        
        // 使用自定义实现处理豆包的reasoning_content字段
        return generateDoubaoContentStream(request)
                .doOnNext(content -> {
                    if (firstResponseTime.get() == 0 && !"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        firstResponseTime.set(System.currentTimeMillis());
                        log.info("Doubao 首次响应耗时: {}ms, 模型: {}", (firstResponseTime.get() - connectionStartTime), modelName);
                    }
                })
                // 仅做换行符标准化，避免逐块排版破坏段落
                .map(this::normalizeLineBreaksSafely)
                .doOnError(e -> {
                    if (e instanceof WebClientResponseException wex) {
                        int status = wex.getStatusCode().value();
                        String body = null;
                        try { body = wex.getResponseBodyAsString(); } catch (Exception ignore) {}
                        log.error("Doubao 流式生成出错: status={}, message={}, body={}, 模型: {}",
                                status, wex.getMessage(), body, modelName, wex);
                    } else {
                        log.error("Doubao 流式生成出错: {}, 模型: {}", e.getMessage(), modelName, e);
                    }
                });
    }
    

    /**
     * 豆包专用流式内容生成方法
     * 参考Grok的自定义实现，处理豆包特有的reasoning_content字段
     */
    private Flux<String> generateDoubaoContentStream(AIRequest request) {
        if (isApiKeyEmpty()) {
            return Flux.just("错误：API密钥未配置");
        }

        // 创建Sink用于流式输出，参考Grok的实现
        Sinks.Many<String> sink = Sinks.many().unicast().onBackpressureBuffer();
        final long requestStartTime = System.currentTimeMillis();
        final AtomicLong firstChunkTime = new AtomicLong(0);

        try {
            // 构建请求体
            Map<String, Object> requestBody = createDoubaoRequestBody(request, true);
            //log.info("开始豆包流式请求, 模型: {}, 请求体: {}", modelName, requestBody);
            
            // 调用流式API
            doubaoWebClient.post()
                    .uri("/chat/completions")
                    .contentType(MediaType.APPLICATION_JSON)
                    .header("Authorization", "Bearer " + apiKey)
                    .bodyValue(requestBody)
                    .accept(MediaType.TEXT_EVENT_STREAM)
                    .retrieve()
                    .bodyToFlux(String.class)
                    .subscribe(
                        chunk -> {
                            try {
                                // 记录首个响应到达时间
                                if (firstChunkTime.get() == 0) {
                                    firstChunkTime.set(System.currentTimeMillis());
                                    log.info("豆包: 收到首个响应, 耗时: {}ms, 模型: {}, 内容: {}",
                                            firstChunkTime.get() - requestStartTime, modelName, chunk);
                                }
                                
                                // 解析流式响应
                                if (chunk.startsWith("data: ")) {
                                    chunk = chunk.substring(6);
                                }
                                
                                if ("[DONE]".equals(chunk) || chunk.isEmpty()) {
                                    log.debug("收到豆包流式结束标志 [DONE] 或空内容");
                                    return;
                                }
                                
                                // 详细日志：显示原始JSON
                                //log.info("豆包原始JSON响应: {}", chunk);
                                
                                DoubaoResponse doubaoResponse = objectMapper.readValue(chunk, DoubaoResponse.class);
                                if (doubaoResponse.getChoices() != null && !doubaoResponse.getChoices().isEmpty()) {
                                    DoubaoResponse.Choice choice = doubaoResponse.getChoices().get(0);
                                    if (choice.getDelta() != null) {
                                        // 详细日志：查看delta的所有字段
//                                        log.info("豆包Delta详情: content='{}', reasoning_content='{}', role='{}'",
//                                                choice.getDelta().getContent(),
//                                                choice.getDelta().getReasoningContent(),
//                                                choice.getDelta().getRole());
                                        
                                        // 优先处理reasoning_content，这是豆包特有的字段
                                        String content = choice.getDelta().getReasoningContent();
                                        if (content == null || content.isEmpty()) {
                                            // 回退到标准content字段
                                            content = choice.getDelta().getContent();
                                        }
                                        
                                        if (content != null && !content.isEmpty()) {
//                                            log.info("豆包解析到内容片段(原始): '{}'", content);
//                                            log.info("豆包内容包含换行符: \\n={}, \\r\\n={}, 实际换行={}",
//                                                    content.contains("\\n"),
//                                                    content.contains("\\r\\n"),
//                                                    content.contains("\n"));
//
                                            // 显示每个字符的详细信息（前30个字符）
                                            if (content.length() > 0) {
                                                StringBuilder charDetails = new StringBuilder();
                                                int limit = Math.min(content.length(), 30);
                                                for (int i = 0; i < limit; i++) {
                                                    char c = content.charAt(i);
                                                    charDetails.append(String.format("'%c'(%d) ", c, (int)c));
                                                }
                                                //log.info("豆包内容字符详情(前{}字符): {}", limit, charDetails.toString());
                                            }
                                            
                                            sink.tryEmitNext(content);
                                        } else {
                                            log.debug("豆包Delta中没有可用内容");
                                        }
                                    } else {
                                        log.debug("豆包Choice中没有Delta");
                                    }
                                } else {
                                    log.debug("豆包响应中没有Choices");
                                }
                            } catch (Exception e) {
                                log.error("解析豆包流式响应失败: {}", e.getMessage(), e);
                                sink.tryEmitNext("错误：" + e.getMessage());
                            }
                        },
                        error -> {
                            if (error instanceof WebClientResponseException wex) {
                                int status = wex.getStatusCode().value();
                                String body = null;
                                try { body = wex.getResponseBodyAsString(); } catch (Exception ignore) {}
                                if (body != null && body.length() > 2000) {
                                    body = body.substring(0, 2000);
                                }
                                log.error("豆包流式API调用失败 - 状态码: {}, message: {}, 响应体: {}", status, wex.getMessage(), body);
                                sink.tryEmitNext("错误：" + status + " " + wex.getMessage() + (body != null && !body.isEmpty() ? " - " + body : ""));
                            } else {
                                log.error("豆包流式API调用失败: {}", error.getMessage());
                                sink.tryEmitNext("错误：" + error.getMessage());
                            }
                            sink.tryEmitComplete();
                        },
                        () -> {
                            log.info("豆包流式生成完成，总耗时: {}ms", System.currentTimeMillis() - requestStartTime);
                            sink.tryEmitComplete();
                        }
                    );
            
            return sink.asFlux()
                    .timeout(Duration.ofSeconds(300))
                    .onErrorResume(e -> {
                        log.error("豆包流式生成内容时出错: {}", e.getMessage(), e);
                        return Flux.just("错误：" + e.getMessage());
                    });
                    
        } catch (Exception e) {
            log.error("豆包流式API调用失败", e);
            return Flux.just("错误：" + e.getMessage());
        }
    }

    /**
     * 创建豆包请求体
     */
    private Map<String, Object> createDoubaoRequestBody(AIRequest request, boolean isStream) {
        Map<String, Object> requestBody = new HashMap<>();
        
        requestBody.put("model", modelName);
        requestBody.put("messages", convertDoubaoMessages(request));
        
        // 设置温度
        if (request.getTemperature() != null) {
            requestBody.put("temperature", request.getTemperature());
        }
        
        // 设置最大令牌数 - 豆包特殊处理：限制不超过32768
        if (request.getMaxTokens() != null) {
            int maxTokens = request.getMaxTokens();
            // 豆包模型的max_tokens上限是32768，超出会返回400错误
            if (maxTokens > 32768) {
                log.warn("豆包模型max_tokens限制：原值{}超出上限32768，已自动调整", maxTokens);
                maxTokens = 32768;
            }
            requestBody.put("max_tokens", maxTokens);
        }
        
        // 如果是流式请求，设置stream参数
        if (isStream) {
            requestBody.put("stream", true);
        }
        
        return requestBody;
    }

    /**
     * 转换消息格式
     */
    private List<Map<String, Object>> convertDoubaoMessages(AIRequest request) {
        List<Map<String, Object>> messages = new ArrayList<>();
        
        // 如果存在系统提示，添加为系统消息
        if (request.getPrompt() != null && !request.getPrompt().isEmpty()) {
            Map<String, Object> systemMessage = new HashMap<>();
            systemMessage.put("role", "system");
            systemMessage.put("content", request.getPrompt());
            messages.add(systemMessage);
        }
        
        // 添加消息历史
        if (request.getMessages() != null) {
            for (AIRequest.Message message : request.getMessages()) {
                Map<String, Object> messageMap = new HashMap<>();
                messageMap.put("role", message.getRole());
                messageMap.put("content", message.getContent());
                messages.add(messageMap);
            }
        }
        
        return messages;
    }

    private String normalizeLineBreaksSafely(String content) {
        if (content == null || content.isEmpty() || "heartbeat".equals(content) || content.startsWith("错误：")) {
            return content;
        }
        String trimmed = content.trim();
        // 避免破坏JSON片段（工具调用或结构化输出）
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            return content;
        }
        // 将字面量换行转为真实换行
        if (content.contains("\\r\\n") || content.contains("\\n")) {
            return content.replace("\\r\\n", "\n").replace("\\n", "\n");
        }
        return content;
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty()
                ? apiEndpoint
                : DEFAULT_API_ENDPOINT;

        WebClient webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .build();

        return webClient.get()
                .uri("/models")
                .header("Authorization", "Bearer " + apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(String.class)
                .flatMapMany(response -> {
                    try {
                        ObjectMapper mapper = new ObjectMapper();
                        JsonNode root = mapper.readTree(response);
                        List<ModelInfo> models = new ArrayList<>();

                        JsonNode data = root.path("data");
                        if (!data.isArray() || data.isEmpty()) {
                            data = root.path("models");
                        }

                        if (data.isArray()) {
                            for (JsonNode n : data) {
                                String id = n.path("id").asText();
                                if (id == null || id.isEmpty()) continue;

                                int maxTokens = 128000;
                                if (n.has("context_length")) {
                                    try {
                                        maxTokens = n.path("context_length").asInt(128000);
                                    } catch (Exception ignore) {
                                    }
                                }

                                ModelInfo mi = ModelInfo.basic(id, id, "doubao")
                                        .withDescription("Doubao (Ark) 模型: " + id)
                                        .withMaxTokens(maxTokens);
                                models.add(mi);
                            }
                        }
                        return Flux.fromIterable(models);
                    } catch (Exception e) {
                        log.error("解析Doubao模型列表失败: {}", e.getMessage(), e);
                        return Flux.empty();
                    }
                })
                .onErrorResume(e -> Flux.empty());
    }

    /**
     * 豆包API响应结构
     * 参考Grok的响应结构，添加豆包特有的reasoning_content字段
     */
    @lombok.Data
    @lombok.NoArgsConstructor
    @JsonIgnoreProperties(ignoreUnknown = true)
    private static class DoubaoResponse {
        private String id;
        private String object;
        private long created;
        private String model;
        private List<Choice> choices;
        private Usage usage;
        @JsonProperty("system_fingerprint")
        private String systemFingerprint;
        
        @lombok.Data
        @lombok.NoArgsConstructor
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class Choice {
            private int index;
            private Message message;
            private Delta delta;
            @JsonProperty("finish_reason")
            private String finishReason;
        }
        
        @lombok.Data
        @lombok.NoArgsConstructor
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class Message {
            private String role;
            private String content;
            @JsonProperty("reasoning_content")
            private String reasoningContent;
        }
        
        @lombok.Data
        @lombok.NoArgsConstructor
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class Delta {
            private String role;
            private String content;
            // 豆包特有的reasoning_content字段
            @JsonProperty("reasoning_content")
            private String reasoningContent;
        }
        
        @lombok.Data
        @lombok.NoArgsConstructor
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class Usage {
            @JsonProperty("prompt_tokens")
            private int promptTokens;
            @JsonProperty("completion_tokens")
            private int completionTokens;
            @JsonProperty("total_tokens")
            private int totalTokens;
        }
    }

}




