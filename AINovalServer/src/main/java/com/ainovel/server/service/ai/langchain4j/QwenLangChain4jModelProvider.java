package com.ainovel.server.service.ai.langchain4j;
import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.community.model.dashscope.QwenChatModel;
import dev.langchain4j.community.model.dashscope.QwenStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 通义千问（DashScope 官方 SDK）Provider
 * 推荐使用 DashScope 官方端点（文本生成）：
 * https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation
 */
@Slf4j
public class QwenLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    // 注意：LangChain4j 的 QwenChatModel 内部会拼接官方 SDK 的路径（/api/v1/services/aigc/text-generation/generation）。
    // 这里的 baseUrl 只能是主机（或最多到 /api/v1），否则会出现路径重复，导致 400: No static resource ... 错误。
    private static final String DEFAULT_API_ENDPOINT = "https://dashscope.aliyuncs.com";
    // 兼容模式（OpenAI风格）用于 /models 探测与轻量校验
    private static final String COMPATIBLE_MODE_BASE = "https://dashscope.aliyuncs.com/compatible-mode/v1";


    public QwenLangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint, ProxyConfig proxyConfig,
                                        ChatModelListenerManager listenerManager) {
        super("qwen", modelName, apiKey, apiEndpoint, proxyConfig, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);
            if (baseUrl == null || baseUrl.trim().isEmpty()) {
                baseUrl = DEFAULT_API_ENDPOINT;
            }
            // 规范化：如果传入了完整路径（含 /api/v1 或 services/aigc/...），仅保留主机，避免路径重复
            baseUrl = normalizeDashScopeBaseUrl(baseUrl);
            // 国内平台：不配置系统代理

            var listeners = getListeners();

            var chatBuilder = QwenChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl);
            if (!listeners.isEmpty()) chatBuilder.listeners(listeners);
            this.chatModel = chatBuilder.build();

            var streamingBuilder = QwenStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl);
            if (!listeners.isEmpty()) streamingBuilder.listeners(listeners);
            this.streamingChatModel = streamingBuilder.build();

            log.info("Qwen(DashScope 官方) 模型初始化成功: {} @ {}", modelName, baseUrl);
        } catch (Exception e) {
            log.error("初始化 Qwen 模型时出错", e);
            this.chatModel = null;
            this.streamingChatModel = null;
        }
    }

    /**
     * 规范化 DashScope baseUrl：
     * - 如果传入了包含 \"/api/\"、\"/compatible-mode/\" 或 \"/services/aigc/text-generation/generation\" 的完整路径，
     *   则仅保留协议+主机部分，避免 SDK 再次拼接导致路径重复。
     */
    private String normalizeDashScopeBaseUrl(String maybeFullUrl) {
        try {
            if (maybeFullUrl == null || maybeFullUrl.trim().isEmpty()) {
                return DEFAULT_API_ENDPOINT;
            }
            String trimmed = maybeFullUrl.trim();
            // 如果是纯主机（不包含路径），直接返回
            if (!(trimmed.contains("/api/") || trimmed.contains("/compatible-mode/") || trimmed.contains("/services/"))) {
                return trimmed;
            }
            java.net.URI uri = java.net.URI.create(trimmed);
            if (uri.getScheme() != null && uri.getHost() != null) {
                String host = uri.getScheme() + "://" + uri.getHost();
                // 保留端口（如有）
                if (uri.getPort() > 0) {
                    host = host + ":" + uri.getPort();
                }
                return host;
            }
            // 兜底：返回默认主机
            return DEFAULT_API_ENDPOINT;
        } catch (Exception ignore) {
            return DEFAULT_API_ENDPOINT;
        }
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
                .filter(calc -> "qwen".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public Mono<Boolean> validateApiKey() {
        return Mono.fromCallable(() -> {
            String baseUrl = (this.apiEndpoint != null && !this.apiEndpoint.trim().isEmpty())
                    ? (this.apiEndpoint.contains("/compatible-mode/") ? this.apiEndpoint : COMPATIBLE_MODE_BASE)
                    : COMPATIBLE_MODE_BASE;

            String url = baseUrl.endsWith("/") ? baseUrl + "models" : baseUrl + "/models";
            log.info("[Qwen] validateApiKey via JDK HttpClient: {}", url);

            HttpClient client = HttpClient.newHttpClient();
            HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .GET()
                    .header("Authorization", "Bearer " + this.apiKey)
                    .header("Accept", "application/json")
                    .build();
            HttpResponse<Void> resp = client.send(request, HttpResponse.BodyHandlers.discarding());
            boolean ok = resp.statusCode() >= 200 && resp.statusCode() < 300;
            log.info("[Qwen] validateApiKey status={}", resp.statusCode());
            return ok;
        }).onErrorResume(e -> {
            log.error("[Qwen] validateApiKey exception (JDK client): {}", e.getMessage(), e);
            return Mono.just(false);
        });
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty()
                ? (apiEndpoint.contains("/compatible-mode/") ? apiEndpoint : COMPATIBLE_MODE_BASE)
                : COMPATIBLE_MODE_BASE;

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
                                    } catch (Exception ignore) { }
                                }

                                ModelInfo mi = ModelInfo.basic(id, id, "qwen")
                                        .withDescription("Qwen (DashScope) 模型: " + id)
                                        .withMaxTokens(maxTokens);
                                models.add(mi);
                            }
                        }
                        return Flux.fromIterable(models);
                    } catch (Exception e) {
                        log.error("解析Qwen模型列表失败: {}", e.getMessage(), e);
                        return Flux.empty();
                    }
                })
                .onErrorResume(e -> Flux.empty());
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        // 对于 qwen3 系列，优先走兼容模式一次性补全，避免 SDK 流式 404
        if (modelName != null && modelName.startsWith("qwen3")) {
            return Flux.defer(() -> {
                try {
                    String baseUrl = (this.apiEndpoint != null && !this.apiEndpoint.trim().isEmpty())
                            ? (this.apiEndpoint.contains("/compatible-mode/") ? this.apiEndpoint : COMPATIBLE_MODE_BASE)
                            : COMPATIBLE_MODE_BASE;
                    String url = baseUrl.endsWith("/") ? baseUrl + "chat/completions" : baseUrl + "/chat/completions";

                    // 构造 OpenAI chat 完整参数
                    Map<String, Object> payload = new HashMap<>();
                    payload.put("model", modelName);
                    payload.put("temperature", request.getTemperature() != null ? request.getTemperature() : 0.7);
                    payload.put("max_tokens", request.getMaxTokens() != null ? request.getMaxTokens() : 1000);

                    // 消息
                    var messages = request.getMessages().stream().map(m -> {
                        Map<String, Object> mm = new HashMap<>();
                        String role = m.getRole();
                        if (role == null) role = "user";
                        mm.put("role", role);
                        mm.put("content", m.getContent() != null ? m.getContent() : "");
                        return mm;
                    }).collect(Collectors.toList());
                    // 前置系统提示
                    if (request.getPrompt() != null && !request.getPrompt().isBlank()) {
                        Map<String, Object> sys = new HashMap<>();
                        sys.put("role", "system");
                        sys.put("content", request.getPrompt());
                        messages.add(0, sys);
                    }
                    payload.put("messages", messages);

                    // 发送 HTTP（非流式），拿到完整内容，组装为单次流输出
                    HttpClient client = HttpClient.newHttpClient();
                    ObjectMapper mapper = new ObjectMapper();
                    String body = mapper.writeValueAsString(payload);
                    HttpRequest httpReq = HttpRequest.newBuilder(URI.create(url))
                            .header("Authorization", "Bearer " + this.apiKey)
                            .header("Content-Type", "application/json")
                            .POST(HttpRequest.BodyPublishers.ofString(body))
                            .build();
                    log.info("[Qwen] compatible-mode chat.completions POST -> {} (len={})", url, body.length());
                    HttpResponse<String> resp = client.send(httpReq, HttpResponse.BodyHandlers.ofString());
                    if (resp.statusCode() / 100 == 2) {
                        String respBody = resp.body();
                        JsonNode root = mapper.readTree(respBody);
                        String content = "";
                        JsonNode choices = root.path("choices");
                        if (choices.isArray() && choices.size() > 0) {
                            JsonNode msg = choices.get(0).path("message");
                            content = msg.path("content").asText("");
                        }
                        if (content == null) content = "";
                        String finalContent = content;
                        return Flux.just(finalContent);
                    } else {
                        log.error("[Qwen] compatible-mode chat.completions HTTP {}: {}", resp.statusCode(), resp.body());
                        return Flux.error(new RuntimeException("Qwen compatible-mode chat failed: HTTP " + resp.statusCode()));
                    }
                } catch (Exception e) {
                    log.error("[Qwen] compatible-mode chat exception: {}", e.getMessage(), e);
                    return Flux.error(e);
                }
            });
        }
        // 其他模型维持基类流式实现
        return super.generateContentStream(request);
    }

}




