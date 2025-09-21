package com.ainovel.server.service.ai.langchain4j;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.model.openai.OpenAiStreamingChatModel;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * SiliconFlow的LangChain4j实现 使用OpenAI兼容模式
 */
@Slf4j
public class SiliconFlowLangChain4jModelProvider extends AbstractUnifiedModelProvider {

    @Autowired
    private ApplicationContext applicationContext;

    private static final String DEFAULT_API_ENDPOINT = "https://api.siliconflow.cn/v1";

    /**
     * 构造函数
     *
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点
     * @param listenerManager 监听器管理器
     */
    public SiliconFlowLangChain4jModelProvider(String modelName, String apiKey, String apiEndpoint, 
                                             ChatModelListenerManager listenerManager) {
        super("siliconflow", modelName, apiKey, apiEndpoint, null, listenerManager);
    }

    @Override
    protected void initModels() {
        try {
            // 获取API端点
            String baseUrl = getApiEndpoint(DEFAULT_API_ENDPOINT);

            // 配置系统代理
            configureSystemProxy();

            // 获取所有注册的监听器
            List<dev.langchain4j.model.chat.listener.ChatModelListener> listeners = getListeners();

            // 创建非流式模型
            var chatBuilder = OpenAiChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .logRequests(true)
                    .logResponses(true)
                    .timeout(Duration.ofSeconds(300));
            
            if (!listeners.isEmpty()) {
                chatBuilder.listeners(listeners);
            }
            this.chatModel = chatBuilder.build();

            // 创建流式模型
            var streamingBuilder = OpenAiStreamingChatModel.builder()
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .baseUrl(baseUrl)
                    .logRequests(true)
                    .logResponses(true)
                    .timeout(Duration.ofSeconds(300));
            
            if (!listeners.isEmpty()) {
                streamingBuilder.listeners(listeners);
            }
            this.streamingChatModel = streamingBuilder.build();

            log.info("SiliconFlow模型初始化成功: {}", modelName);
        } catch (Exception e) {
            log.error("初始化SiliconFlow模型时出错", e);
            this.chatModel = null;
            this.streamingChatModel = null;
        }
    }

    /**
     * 测试SiliconFlow API
     *
     * @return 测试结果
     */
    public String testSiliconFlowApi() {
        if (chatModel == null) {
            return "模型未初始化";
        }

        // 注意：由于LangChain4j API的变化，此测试方法需要更新
        // 暂时返回一个提示信息
        return "API测试功能暂未实现，请使用generateContent方法进行测试";
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
                .filter(calc -> "siliconflow".equals(calc.getProviderName()))
                .findFirst()
                .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        log.info("开始SiliconFlow流式生成，模型: {}", modelName);

        // 标记是否已经收到了任何内容
        final AtomicBoolean hasReceivedContent = new AtomicBoolean(false);

        return super.generateContentStream(request)
                .doOnSubscribe(__ -> log.info("SiliconFlow流式生成已订阅"))
                .doOnNext(content -> {
                    if (!"heartbeat".equals(content) && !content.startsWith("错误：")) {
                        // 标记已收到有效内容
                        hasReceivedContent.set(true);
                        log.debug("SiliconFlow生成内容: {}", content);
                    }
                })
                .doOnComplete(() -> log.info("SiliconFlow流式生成完成"))
                .doOnError(e -> log.error("SiliconFlow流式生成出错", e))
                .doOnCancel(() -> {
                    if (hasReceivedContent.get()) {
                        // 如果已收到内容但客户端取消了，记录不同的日志但允许模型继续生成
                        log.info("SiliconFlow流式生成客户端取消了连接，但已收到内容，保持模型连接以完成生成");
                    } else {
                        // 如果没有收到任何内容且客户端取消了，记录取消日志
                        log.info("SiliconFlow流式生成被取消，未收到任何内容");
                    }
                });
    }

    @Override
    protected Flux<ModelInfo> callApiForModels(String apiKey, String apiEndpoint) {
        log.info("获取SiliconFlow模型列表");

        String baseUrl = apiEndpoint != null && !apiEndpoint.trim().isEmpty() ?
                apiEndpoint : DEFAULT_API_ENDPOINT;

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
                        log.debug("SiliconFlow模型列表响应: {}", response);
                        // 简化起见，返回空让基类使用统一的默认列表
                        return Flux.<ModelInfo>empty();
                    } catch (Exception e) {
                        log.error("解析SiliconFlow模型列表时出错", e);
                        return Flux.<ModelInfo>empty();
                    }
                })
                .onErrorResume(e -> Flux.<ModelInfo>empty());
    }

}
