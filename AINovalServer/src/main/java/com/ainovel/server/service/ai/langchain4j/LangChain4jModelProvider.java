package com.ainovel.server.service.ai.langchain4j;

import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.ProxySelector;
import java.net.SocketAddress;
import java.net.URI;
import java.io.IOException;
// duplicate imports removed

import com.ainovel.server.config.ProxyConfig;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.ModelInfo;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.service.ai.capability.ToolCallCapable;
import com.ainovel.server.service.ai.observability.ChatModelListenerManager;

import dev.langchain4j.agent.tool.ToolExecutionRequest;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.ToolExecutionResultMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.model.chat.ChatLanguageModel;
import dev.langchain4j.model.chat.StreamingChatLanguageModel;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.response.ChatResponse;
import dev.langchain4j.model.chat.response.StreamingChatResponseHandler;
import dev.langchain4j.agent.tool.ToolSpecification;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.util.retry.Retry;

/**
 * LangChain4j模型提供商基类 使用LangChain4j框架实现AI模型集成
 * 
 * 实现ToolCallCapable接口，支持工具调用功能
 */
@Slf4j
public abstract class LangChain4jModelProvider implements AIModelProvider, ToolCallCapable {

    @Getter
    protected final String providerName;

    @Getter
    protected final String modelName;

    @Getter
    protected final String apiKey;

    @Getter
    protected final String apiEndpoint;

    // 代理配置
    @Getter
    protected String proxyHost;

    @Getter
    protected int proxyPort;

    @Getter
    protected boolean proxyEnabled;

    private ProxyConfig proxyConfig;

    // LangChain4j模型实例
    protected ChatLanguageModel chatModel;
    protected StreamingChatLanguageModel streamingChatModel;
    
    // 监听器管理器 - 由工厂注入，支持多个监听器
    @Getter
    protected final ChatModelListenerManager listenerManager;

    /**
     * 构造函数
     *
     * @param providerName 提供商名称
     * @param modelName 模型名称
     * @param apiKey API密钥
     * @param apiEndpoint API端点
     * @param listenerManager 监听器管理器
     */
    protected LangChain4jModelProvider(String providerName, String modelName, String apiKey, String apiEndpoint, 
                                     ChatModelListenerManager listenerManager) {
        this.providerName = providerName;
        this.modelName = modelName;
        this.apiKey = apiKey;
        this.apiEndpoint = apiEndpoint;
        this.proxyEnabled = true;
        this.listenerManager = listenerManager;

        // 初始化模型
        initModels();
    }

    protected LangChain4jModelProvider(String providerName, String modelName, String apiKey, String apiEndpoint, 
                                     ProxyConfig proxyConfig, ChatModelListenerManager listenerManager) {
        this.providerName = providerName;
        this.modelName = modelName;
        this.apiKey = apiKey;
        this.apiEndpoint = apiEndpoint;
        this.proxyEnabled = true;
        this.proxyConfig = proxyConfig;
        this.listenerManager = listenerManager;

        // 初始化模型
        initModels();
    }

    /**
     * 初始化LangChain4j模型 子类必须实现此方法来创建具体的模型实例
     */
    protected abstract void initModels();
    
    /**
     * 获取监听器列表 - 统一的监听器管理
     * 子类可以直接使用此方法，避免重复代码
     * 支持多种监听器的动态注册和管理
     */
    protected List<dev.langchain4j.model.chat.listener.ChatModelListener> getListeners() {
        if (listenerManager == null) {
            log.warn("⚠️ ChatModelListenerManager 为 null，返回空监听器列表！模型: {}", modelName);
            return new ArrayList<>();
        }
        
        List<dev.langchain4j.model.chat.listener.ChatModelListener> listeners = listenerManager.getAllListeners();
        log.debug("为{}模型获取了 {} 个监听器: {}", modelName, listeners.size(), listenerManager.getListenerInfo());
        
        return listeners;
    }
    
    /**
     * 获取指定类型的监听器
     * @param listenerClass 监听器类型
     * @return 指定类型的监听器列表
     */
    protected <T extends dev.langchain4j.model.chat.listener.ChatModelListener> List<T> getListenersByType(Class<T> listenerClass) {
        if (listenerManager == null) {
            log.warn("⚠️ ChatModelListenerManager 为 null，返回空监听器列表！模型: {}", modelName);
            return new ArrayList<>();
        }
        
        return listenerManager.getListenersByType(listenerClass);
    }
    
    /**
     * 检查是否有指定类型的监听器
     * @param listenerClass 监听器类型
     * @return 是否存在该类型的监听器
     */
    protected boolean hasListener(Class<? extends dev.langchain4j.model.chat.listener.ChatModelListener> listenerClass) {
        return listenerManager != null && listenerManager.hasListener(listenerClass);
    }

    /**
     * 设置HTTP代理
     *
     * @param host 代理主机
     * @param port 代理端口
     */
    @Override
    public void setProxy(String host, int port) {
        this.proxyHost = host;
        this.proxyPort = port;
        this.proxyEnabled = true;

        // 重新初始化模型以应用代理设置
        initModels();
    }

    /**
     * 禁用HTTP代理
     */
    @Override
    public void disableProxy() {
        this.proxyEnabled = false;
        this.proxyHost = null;
        this.proxyPort = 0;

        // 重新初始化模型以应用代理设置
        initModels();
    }

    /**
     * 配置系统代理
     */
    protected void configureSystemProxy() throws NoSuchAlgorithmException, KeyManagementException {
        if (proxyConfig != null && proxyConfig.isEnabled()) {
            String host = proxyConfig.getHost();
            int port = proxyConfig.getPort();
            String type = proxyConfig.getType() != null ? proxyConfig.getType().toLowerCase() : "http";
            log.info("Gemini Provider: 检测到 ProxyConfig 已启用，准备配置代理: Type={}, Host={}, Port={}", type, host, port);

            // 可选：为当前JVM设置代理系统属性
            if (proxyConfig.isApplySystemProperties()) {
                if ("socks".equals(type)) {
                    System.setProperty("socksProxyHost", host);
                    System.setProperty("socksProxyPort", String.valueOf(port));
                    System.clearProperty("http.proxyHost");
                    System.clearProperty("http.proxyPort");
                    System.clearProperty("https.proxyHost");
                    System.clearProperty("https.proxyPort");
                    log.info("已设置 JVM 级 SOCKS 代理系统属性");
                } else {
                    System.setProperty("http.proxyHost", host);
                    System.setProperty("http.proxyPort", String.valueOf(port));
                    System.setProperty("https.proxyHost", host);
                    System.setProperty("https.proxyPort", String.valueOf(port));
                    System.clearProperty("socksProxyHost");
                    System.clearProperty("socksProxyPort");
                    log.info("已设置 JVM 级 http/https 代理系统属性");
                }
            }

            // 可选：为 Java 11+ HttpClient 设置全局 ProxySelector
            if (proxyConfig.isApplyProxySelector()) {
                try {
                    if ("socks".equals(type)) {
                        ProxySelector socksSelector = new ProxySelector() {
                            @Override
                            public List<Proxy> select(URI uri) {
                                return List.of(new Proxy(Proxy.Type.SOCKS, new InetSocketAddress(host, port)));
                            }

                            @Override
                            public void connectFailed(URI uri, SocketAddress sa, IOException ioe) {
                                log.warn("SOCKS 代理连接失败: uri={}, address={}, error={}", uri, sa, ioe.getMessage());
                            }
                        };
                        ProxySelector.setDefault(socksSelector);
                        log.info("已设置全局 SOCKS ProxySelector 指向 {}:{}", host, port);
                    } else {
                        ProxySelector.setDefault(ProxySelector.of(new InetSocketAddress(host, port)));
                        log.info("已设置全局 HTTP ProxySelector 指向 {}:{}", host, port);
                    }
                } catch (Exception e) {
                    log.warn("设置全局 ProxySelector 失败: {}", e.getMessage());
                }
            }

            // 可选：仅用于排障的信任所有证书
            if (proxyConfig.isTrustAllCerts()) {
                TrustManager[] trustAllCerts = new TrustManager[]{
                        new X509TrustManager() {
                            @Override
                            public void checkClientTrusted(X509Certificate[] x509Certificates, String s) throws CertificateException {}
                            @Override
                            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                            @Override
                            public void checkServerTrusted(X509Certificate[] certs, String authType) {}
                        }
                };
                SSLContext sc = SSLContext.getInstance("TLS");
                sc.init(null, trustAllCerts, new java.security.SecureRandom());
                HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());
                log.warn("已启用 trustAllCerts（仅建议用于排障），生产请关闭！");
            }
        } else {
            log.info("Gemini Provider: ProxyConfig 未启用或未配置，清除系统HTTP/S代理设置。");
            // 清除系统代理属性（仅当先前设置过时才有意义）
            if (proxyConfig != null && proxyConfig.isApplySystemProperties()) {
                System.clearProperty("http.proxyHost");
                System.clearProperty("http.proxyPort");
                System.clearProperty("https.proxyHost");
                System.clearProperty("https.proxyPort");
                System.clearProperty("socksProxyHost");
                System.clearProperty("socksProxyPort");
            }
            // 不主动改动 ProxySelector，避免影响进程内其他客户端；仅清除系统属性
            log.info("Gemini Provider: 已清除Java系统代理属性。");
        }
    }

    @Override
    public Mono<AIResponse> generateContent(AIRequest request) {
        if (isApiKeyEmpty()) {
            return Mono.error(new RuntimeException("API密钥未配置"));
        }

        if (chatModel == null) {
            return Mono.error(new RuntimeException("模型未初始化"));
        }

        // 使用defer延迟执行
        return Mono.defer(() -> {
            // 创建一个临时对象作为锁
            final Object syncLock = new Object();
            final AIResponse[] responseHolder = new AIResponse[1];
            final Throwable[] errorHolder = new Throwable[1];

            log.info("开始生成内容, 模型: {}, userId: {}", modelName, request.getUserId());

            // 记录开始时间
            final long startTime = System.currentTimeMillis();

            try {
                // 使用同步块保证完整执行
                synchronized (syncLock) {
                    // 转换请求为LangChain4j格式
                    List<ChatMessage> messages = convertToLangChain4jMessages(request);

                    // 🚀 检查是否有工具规范，使用专门字段
                    ChatResponse response;
                    if (request.getToolSpecifications() != null && !request.getToolSpecifications().isEmpty()) {
                        
                        // 安全转换工具规范列表
                        List<ToolSpecification> toolSpecs = new ArrayList<>();
                        for (Object obj : request.getToolSpecifications()) {
                            if (obj instanceof ToolSpecification) {
                                toolSpecs.add((ToolSpecification) obj);
                            }
                        }
                        
                        if (!toolSpecs.isEmpty()) {
                            log.debug("使用工具规范进行AI调用, 工具数量: {}", toolSpecs.size());
                            
                            try {
                                // 🚀 构建带工具的请求（无原生toolChoice可用，保持由请求参数强制）
                                ChatRequest chatRequest = ChatRequest.builder()
                                    .messages(messages)
                                    .toolSpecifications(toolSpecs)
                                    .build();
                                
                                response = chatModel.chat(chatRequest);
                            } catch (NullPointerException e) {
                                // 🚀 Gemini工具调用响应解析错误 - 这是LangChain4j的已知问题
                                log.error("Gemini工具调用出现NPE，这是LangChain4j解析Gemini响应的已知问题。错误: {}", e.getMessage());
                                log.debug("NPE详细信息", e);
                                throw new RuntimeException("Gemini模型工具调用功能暂时不可用，建议使用其他模型（如GPT-4、Claude等）进行设定生成。" +
                                    "技术详情：LangChain4j在解析Gemini工具调用响应时遇到空指针异常。", e);
                            } catch (Exception e) {
                                // 🚀 其他工具调用错误
                                log.error("工具调用失败: {}", e.getMessage());
                                log.debug("工具调用错误详细信息", e);
                                throw new RuntimeException("模型工具调用功能出现错误，请检查模型配置或尝试其他模型。错误: " + e.getMessage(), e);
                            }
                        } else {
                            // 工具规范列表为空，使用普通聊天
                            response = chatModel.chat(messages);
                        }
                    } else {
                        // 普通的聊天调用（无工具）
                        response = chatModel.chat(messages);
                    }

                    // 转换响应并保存到holder
                    responseHolder[0] = convertToAIResponse(response, request);
                    // 如果转换后为错误状态，则抛出异常以与流式行为保持一致
                    if (responseHolder[0] != null && "error".equalsIgnoreCase(responseHolder[0].getStatus())) {
                        String reason = responseHolder[0].getErrorReason() != null ? responseHolder[0].getErrorReason() : "生成内容失败";
                        throw new RuntimeException(reason);
                    }
                }

                // 记录完成时间
                log.info("内容生成完成, 耗时: {}ms, 模型: {}, userId: {}",
                        System.currentTimeMillis() - startTime, modelName, request.getUserId());

                // 返回结果
                return Mono.justOrEmpty(responseHolder[0])
                        .switchIfEmpty(Mono.error(new RuntimeException("生成的响应为空")));

            } catch (Exception e) {
                log.error("生成内容时出错, 模型: {}, userId: {}, 错误: {}",
                        modelName, request.getUserId(), e.getMessage(), e);
                // 保存错误
                errorHolder[0] = e;
                return Mono.error(new RuntimeException("生成内容时出错: " + e.getMessage(), e));
            }
        })
        .doOnCancel(() -> {
            // 请求被取消时的处理
            log.warn("AI内容生成请求被取消, 模型: {}, userId: {}, 但模型可能仍在后台继续生成",
                    modelName, request.getUserId());
        })
        .timeout(Duration.ofSeconds(120)) // 添加2分钟超时
        .retryWhen(Retry.backoff(2, Duration.ofSeconds(1))
                .filter(throwable -> !(throwable instanceof RuntimeException &&
                        throwable.getMessage() != null &&
                        throwable.getMessage().contains("API密钥未配置"))))
        .onErrorResume(e -> {
            // 与流式逻辑保持一致：直接向上抛出错误，不把错误写入内容
            return Mono.error(e);
        });
    }

    @Override
    public Flux<String> generateContentStream(AIRequest request) {
        if (isApiKeyEmpty()) {
            return Flux.just("错误：API密钥未配置");
        }

        if (streamingChatModel == null) {
            return Flux.just("错误：流式模型未初始化");
        }

        // 将副作用延迟到订阅时执行，避免方法调用即触发底层请求
        return Flux.defer(() -> {
            try {
            // 转换请求为LangChain4j格式
            List<ChatMessage> messages = convertToLangChain4jMessages(request);

            // 🚀 检查是否有工具规范，使用专门字段
            List<ToolSpecification> toolSpecs = null;
            if (request.getToolSpecifications() != null && !request.getToolSpecifications().isEmpty()) {
                
                // 安全转换工具规范列表
                List<ToolSpecification> specs = new ArrayList<>();
                for (Object obj : request.getToolSpecifications()) {
                    if (obj instanceof ToolSpecification) {
                        specs.add((ToolSpecification) obj);
                    }
                }
                
                if (!specs.isEmpty()) {
                    toolSpecs = specs;
                    log.debug("流式生成使用工具规范, 工具数量: {}", specs.size());
                }
            }

            // 创建Sink用于流式输出，支持暂停和缓冲
            // 使用replay()来缓存已发出的内容，避免订阅者错过早期响应
            Sinks.Many<String> sink = Sinks.many().replay().all();

            // 记录请求开始时间，用于问题诊断
            final long requestStartTime = System.currentTimeMillis();
            final AtomicLong firstChunkTime = new AtomicLong(0);
            // 标记是否已经收到了任何内容
            final AtomicBoolean hasReceivedContent = new AtomicBoolean(false);

            // 创建响应处理器
            StreamingChatResponseHandler handler = new StreamingChatResponseHandler() {
                @Override
                public void onPartialResponse(String partialResponse) {
                    // 记录首个响应到达时间
                    if (firstChunkTime.get() == 0) {
                        firstChunkTime.set(System.currentTimeMillis());
                        hasReceivedContent.set(true);
//                        log.info("收到首个LLM响应, 耗时: {}ms, 模型: {}, 内容长度: {}, 内容预览: '{}'",
//                                firstChunkTime.get() - requestStartTime, modelName,
//                                partialResponse != null ? partialResponse.length() : 0,
//                                partialResponse != null && partialResponse.length() > 50 ?
//                                    partialResponse.substring(0, 50) + "..." : partialResponse);
                    } else {
//                        log.debug("收到LLM后续响应, 模型: {}, 内容长度: {}", modelName,
//                                partialResponse != null ? partialResponse.length() : 0);
                    }

                    // 使用replay sink，无需检查订阅者数量，直接发送内容
                    Sinks.EmitResult result = sink.tryEmitNext(partialResponse);
                    if (result.isFailure()) {
                        log.warn("发送部分响应到sink失败, 结果: {}, 模型: {}", result, modelName);
                    }
                }

                @Override
                public void onCompleteResponse(ChatResponse response) {
                    long totalMs = System.currentTimeMillis() - requestStartTime;
                    log.info("LLM响应完成，总耗时: {}ms, 模型: {}, 响应元数据: {}",
                            totalMs, modelName, response != null ? response.metadata() : null);
                    // 若未收到任何partial且最终响应包含文本，作为补偿发出一次文本
                    if (!hasReceivedContent.get() && response != null && response.aiMessage() != null) {
                        try {
                            String finalText = response.aiMessage().text();
                            if (finalText != null && !finalText.trim().isEmpty()) {
                                Sinks.EmitResult emitResult = sink.tryEmitNext(finalText);
                                if (emitResult.isFailure()) {
                                    log.warn("在完成时补发最终文本失败: {}", emitResult);
                                } else {
                                    hasReceivedContent.set(true);
                                    firstChunkTime.compareAndSet(0, System.currentTimeMillis());
                                    log.debug("在完成时补发最终文本，长度: {}", finalText.length());
                                }
                            }
                        } catch (Exception e) {
                            log.warn("在完成时读取最终文本失败: {}", e.getMessage());
                        }
                    }
                    // 使用replay sink，无需检查订阅者数量，直接完成
                    Sinks.EmitResult result = sink.tryEmitComplete();
                    if (result.isFailure()) {
                        log.warn("完成sink失败, 结果: {}, 模型: {}", result, modelName);
                    }
                }

                @Override
                public void onError(Throwable error) {
                    log.error("LLM流式生成内容时出错，总耗时: {}ms, 模型: {}, 错误类型: {}",
                            System.currentTimeMillis() - requestStartTime, modelName, 
                            error.getClass().getSimpleName(), error);
                    // 直接通过错误终止，交由上游决定是否重试与如何呈现
                    sink.tryEmitError(error);
                }
            };

            // 调用流式模型并添加日志
            log.info("开始调用LLM流式模型 {}, 消息数量: {}, 工具数量: {}", modelName, messages.size(), 
                toolSpecs != null ? toolSpecs.size() : 0);
            
            // 🚀 根据是否有工具规范选择调用方式
            if (toolSpecs != null && !toolSpecs.isEmpty()) {
                try {
                    // 使用工具调用 - 构建ChatRequest（无原生toolChoice可用，保持由请求参数强制）
                    ChatRequest chatRequest = ChatRequest.builder()
                        .messages(messages)
                        .toolSpecifications(toolSpecs)
                        .build();
                    streamingChatModel.chat(chatRequest, handler);
                } catch (NullPointerException e) {
                    // 🚀 Gemini流式工具调用响应解析错误 - 这是LangChain4j的已知问题
                    log.error("Gemini流式工具调用出现NPE，这是LangChain4j解析Gemini响应的已知问题。错误: {}", e.getMessage());
                    log.debug("流式NPE详细信息", e);
                    // 返回错误流
                    return Flux.error(new RuntimeException("Gemini模型工具调用功能暂时不可用，建议使用其他模型（如GPT-4、Claude等）进行设定生成。" +
                        "技术详情：LangChain4j在解析Gemini工具调用响应时遇到空指针异常。", e));
                } catch (Exception e) {
                    // 🚀 其他流式工具调用错误
                    log.error("流式工具调用失败: {}", e.getMessage());
                    log.debug("流式工具调用错误详细信息", e);
                    // 返回错误流
                    return Flux.error(new RuntimeException("模型工具调用功能出现错误，请检查模型配置或尝试其他模型。错误: " + e.getMessage(), e));
                }
            } else {
                // 普通聊天
                streamingChatModel.chat(messages, handler);
            }
            
            log.info("LLM流式模型调用已发出，等待响应...");

            // 创建一个完成信号 - 用于控制心跳流的结束
            final Sinks.One<Boolean> completionSignal = Sinks.one();

            // 主内容流
            Flux<String> mainStream = sink.asFlux()
                    .doOnSubscribe(subscription -> {
                        log.info("主流被订阅, 模型: {}", modelName);
                    })
                    // 添加延迟重试，避免网络抖动导致请求失败
                    .retryWhen(Retry.backoff(1, Duration.ofSeconds(2))
                            .filter(error -> {
                                // 只对网络错误或超时错误进行重试
                                boolean isNetworkError = error instanceof java.net.SocketException
                                        || error instanceof java.io.IOException
                                        || error instanceof java.util.concurrent.TimeoutException;
                                if (isNetworkError) {
                                    log.warn("LLM流式生成遇到网络错误，将进行重试: {}", error.getMessage());
                                }
                                return isNetworkError;
                            })
                    )
                    .timeout(Duration.ofSeconds(300)) // 增加超时时间到300秒，避免大模型生成时间过长导致中断
                    .doOnComplete(() -> {
                        // 发出完成信号，通知心跳流停止
                        completionSignal.tryEmitValue(true);
                        log.debug("主流完成，已发送停止心跳信号, 模型: {}", modelName);
                    })
                    .doOnCancel(() -> {
                        // 取消时如果已经收到内容，不要关闭sink
                        if (!hasReceivedContent.get()) {
                            // 只有在没有收到任何内容时才完成sink
                            log.debug("主流取消，但未收到任何响应，发送停止心跳信号, 模型: {}", modelName);
                            completionSignal.tryEmitValue(true);
                        } else {
                            log.debug("主流取消，但已收到内容，保持sink开放以接收后续内容, 模型: {}", modelName);
                        }
                    })
                    .doOnError(error -> {
                        // 错误时也发出完成信号
                        completionSignal.tryEmitValue(true);
                        log.debug("主流出错，已发送停止心跳信号: {}, 模型: {}", error.getMessage(), modelName);
                    });

            // 心跳流，当completionSignal发出时停止
            Flux<String> heartbeatStream = Flux.interval(Duration.ofSeconds(15))
                    .map(tick -> {
                        log.debug("发送LLM心跳信号 #{}", tick);
                        return "heartbeat";
                    })
                    // 移除订阅者检查，因为replay sink会自动处理
                    // 使用takeUntil操作符，当completionSignal发出值时停止心跳
                    .takeUntilOther(completionSignal.asMono());

            // 合并主流和心跳流
            return Flux.merge(mainStream, heartbeatStream)
                    .doOnSubscribe(subscription -> {
                        log.info("合并流被订阅, 模型: {}", modelName);
                    })
                    .doOnNext(content -> {
//                        log.debug("合并流发出内容, 模型: {}, 类型: {}, 长度: {}",
//                                modelName,
//                                "heartbeat".equals(content) ? "心跳" : "内容",
//                                content != null ? content.length() : 0);
                    })
                    // 针对瞬时错误进行有限次数重试（例如 429 限流、上游繁忙、临时网络问题）
                    .retryWhen(Retry.backoff(2, Duration.ofSeconds(2))
                            .maxBackoff(Duration.ofSeconds(10))
                            .jitter(0.3)
                            .filter(err -> {
                                String cls = err.getClass().getName().toLowerCase();
                                String msg = err.getMessage() != null ? err.getMessage().toLowerCase() : "";
                                boolean isNetwork = err instanceof java.net.SocketException
                                        || err instanceof java.io.IOException
                                        || err instanceof java.util.concurrent.TimeoutException;
                                boolean isRateLimited = msg.contains("429")
                                        || msg.contains("rate limit")
                                        || msg.contains("quota")
                                        || msg.contains("temporarily")
                                        || msg.contains("retry shortly")
                                        || msg.contains("upstream")
                                        || msg.contains("resource_exhausted");
                                boolean isHttp = cls.contains("httpexception") || cls.contains("httpclient");
                                if (isRateLimited || isNetwork || isHttp) {
                                    log.warn("检测到瞬时错误，准备重试: {}", err.getMessage());
                                    return true;
                                }
                                return false;
                            })
                    )
                    // 最终错误直接抛出给上游，由业务流决定如何告警与终止
                    .doOnCancel(() -> {
                        // 如果已经收到内容，记录不同的日志
                        if (hasReceivedContent.get()) {
                            log.info("合并流被取消，但已收到内容，保持模型连接以完成生成。首次响应耗时: {}ms, 总耗时: {}ms, 模型: {}",
                                    firstChunkTime.get() - requestStartTime,
                                    System.currentTimeMillis() - requestStartTime,
                                    modelName);
                        } else {
                            log.info("合并流被取消，未收到任何内容，总耗时: {}ms, 模型: {}",
                                    System.currentTimeMillis() - requestStartTime, modelName);

                            // 只有在没有收到内容时才完成sink
                            try {
                                if (sink.currentSubscriberCount() > 0) {
                                    sink.tryEmitComplete();
                                }
                                // 确保心跳流也停止
                                completionSignal.tryEmitValue(true);
                            } catch (Exception ex) {
                                log.warn("取消流生成时完成sink出错，可以忽略, 模型: {}", modelName, ex);
                            }
                        }
                    });
            } catch (Exception e) {
                log.error("准备流式生成内容时出错", e);
                return Flux.error(e);
            }
        });
    }

    @Override
    public Mono<Double> estimateCost(AIRequest request) {
        // 默认实现，子类可以根据具体模型覆盖此方法
        // 简单估算，基于输入令牌数和输出令牌数
        int inputTokens = estimateInputTokens(request);
        int outputTokens = request.getMaxTokens() != null ? request.getMaxTokens() : 1000;

        // 默认价格（每1000个令牌的美元价格）
        double inputPricePerThousandTokens = 0.001;
        double outputPricePerThousandTokens = 0.002;

        // 计算成本（美元）
        double costInUSD = (inputTokens / 1000.0) * inputPricePerThousandTokens
                + (outputTokens / 1000.0) * outputPricePerThousandTokens;

        // 转换为人民币（假设汇率为7.2）
        double costInCNY = costInUSD * 7.2;

        return Mono.just(costInCNY);
    }

    @Override
    public Mono<Boolean> validateApiKey() {
        if (isApiKeyEmpty()) {
            return Mono.just(false);
        }

        if (chatModel == null) {
            return Mono.just(false);
        }

        // 尝试发送一个简单请求来验证API密钥
        try {
            List<ChatMessage> messages = new ArrayList<>();
            messages.add(new UserMessage("测试"));
            chatModel.chat(messages);
            return Mono.just(true);
        } catch (Exception e) {
            log.error("验证API密钥时出错", e);
            return Mono.just(false);
        }
    }

    /**
     * 获取提供商支持的模型列表
     * 这是基类的默认实现，子类可以根据需要覆盖此方法
     *
     * @return 模型信息列表
     */
    @Override
    public Flux<ModelInfo> listModels() {
        // 默认实现返回一个包含当前模型的列表
        // 这适用于不需要API密钥就能获取模型列表的提供商
        return Flux.just(createDefaultModelInfo());
    }

    /**
     * 使用API密钥获取提供商支持的模型列表
     * 这是基类的默认实现，子类可以根据需要覆盖此方法
     *
     * @param apiKey API密钥
     * @param apiEndpoint 可选的API端点
     * @return 模型信息列表
     */
    @Override
    public Flux<ModelInfo> listModelsWithApiKey(String apiKey, String apiEndpoint) {
        // 默认实现返回一个包含当前模型的列表
        // 这适用于需要API密钥才能获取模型列表的提供商
        if (isApiKeyEmpty(apiKey)) {
            return Flux.error(new RuntimeException("API密钥不能为空"));
        }

        return Flux.just(createDefaultModelInfo());
    }

    /**
     * 创建默认的模型信息对象
     *
     * @return 模型信息对象
     */
    protected ModelInfo createDefaultModelInfo() {
        return ModelInfo.basic(modelName, modelName, providerName)
                .withDescription("LangChain4j模型")
                .withMaxTokens(204800) // 默认值，子类应该覆盖
                .withUnifiedPrice(0.001); // 默认价格，子类应该覆盖
    }

    /**
     * 检查当前API密钥是否为空
     *
     * @return 是否为空
     */
    protected boolean isApiKeyEmpty() {
        return apiKey == null || apiKey.trim().isEmpty();
    }

    /**
     * 检查指定API密钥是否为空
     *
     * @param apiKey API密钥
     * @return 是否为空
     */
    protected boolean isApiKeyEmpty(String apiKey) {
        return apiKey == null || apiKey.trim().isEmpty();
    }

    /**
     * 将AIRequest转换为LangChain4j消息列表
     *
     * @param request AI请求
     * @return LangChain4j消息列表
     */
    protected List<ChatMessage> convertToLangChain4jMessages(AIRequest request) {
        List<ChatMessage> messages = new ArrayList<>();

        // 添加系统提示（如果有）
        if (request.getPrompt() != null && !request.getPrompt().isEmpty()) {
            messages.add(new SystemMessage(request.getPrompt()));
        }

        // 添加对话历史
        for (AIRequest.Message message : request.getMessages()) {
            ChatMessage convertedMessage = convertSingleMessageToLangChain4j(message);
            if (convertedMessage != null) {
                messages.add(convertedMessage);
            }
        }

        return messages;
    }

    /**
     * 将单个AIRequest.Message转换为LangChain4j ChatMessage
     *
     * @param message AIRequest消息
     * @return LangChain4j消息，如果转换失败则返回null
     */
    protected ChatMessage convertSingleMessageToLangChain4j(AIRequest.Message message) {
        if (message == null || message.getRole() == null) {
            log.warn("消息为空或角色为空，跳过转换");
            return null;
        }

        switch (message.getRole().toLowerCase()) {
            case "user":
                return convertToUserMessage(message);
                
            case "assistant":
                return convertToAiMessage(message);
                
            case "system":
                return convertToSystemMessage(message);
                
            case "tool":
                return convertToToolExecutionResultMessage(message);
                
            default:
                log.warn("未知的消息角色: {}，将作为用户消息处理", message.getRole());
                String defaultContent = message.getContent();
                if (defaultContent == null || defaultContent.trim().isEmpty()) {
                    log.warn("跳过未知角色的空消息");
                    return null;
                }
                return new UserMessage(defaultContent);
        }
    }

    /**
     * 转换为用户消息
     */
    private UserMessage convertToUserMessage(AIRequest.Message message) {
        String content = message.getContent();
        if (content == null || content.trim().isEmpty()) {
            log.warn("跳过转换空的用户消息");
            return null;
        }
        return new UserMessage(content);
    }

    /**
     * 转换为AI消息（支持工具调用）
     */
    private AiMessage convertToAiMessage(AIRequest.Message message) {
        String content = message.getContent();
        List<AIRequest.ToolExecutionRequest> toolRequests = message.getToolExecutionRequests();
        
        // 如果没有工具调用请求，创建简单的文本消息
        if (toolRequests == null || toolRequests.isEmpty()) {
            if (content == null || content.trim().isEmpty()) {
                log.warn("跳过转换空的AI消息");
                return null;
            }
            return new AiMessage(content);
        }
        
        // 转换工具调用请求
        List<ToolExecutionRequest> langchain4jToolRequests = 
            toolRequests.stream()
                .map(this::convertToLangChain4jToolRequest)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
        
        String safeContent = (content == null || content.trim().isEmpty()) ? "[tool_call]" : content;
        return new AiMessage(safeContent, langchain4jToolRequests);
    }

    /**
     * 转换为系统消息
     */
    private SystemMessage convertToSystemMessage(AIRequest.Message message) {
        String content = message.getContent();
        if (content == null || content.trim().isEmpty()) {
            log.warn("跳过空的系统消息");
            return null;
        }
        return new SystemMessage(content);
    }

    /**
     * 转换为工具执行结果消息
     */
    private ToolExecutionResultMessage convertToToolExecutionResultMessage(AIRequest.Message message) {
        AIRequest.ToolExecutionResult result = message.getToolExecutionResult();
        if (result == null) {
            log.warn("工具消息缺少执行结果");
            return new ToolExecutionResultMessage(
                "unknown", "unknown", message.getContent() != null ? message.getContent() : ""
            );
        }
        
        return new ToolExecutionResultMessage(
            result.getToolExecutionId() != null ? result.getToolExecutionId() : "unknown",
            result.getToolName() != null ? result.getToolName() : "unknown", 
            result.getResult() != null ? result.getResult() : ""
        );
    }

    /**
     * 将AIRequest.ToolExecutionRequest转换为LangChain4j ToolExecutionRequest
     */
    private ToolExecutionRequest convertToLangChain4jToolRequest(AIRequest.ToolExecutionRequest request) {
        if (request == null || request.getName() == null) {
            log.warn("工具执行请求为空或缺少名称");
            return null;
        }
        
        return ToolExecutionRequest.builder()
            .id(request.getId() != null ? request.getId() : UUID.randomUUID().toString())
            .name(request.getName())
            .arguments(request.getArguments() != null ? request.getArguments() : "{}")
            .build();
    }

    /**
     * 将LangChain4j响应转换为AIResponse
     *
     * @param chatResponse LangChain4j聊天响应
     * @param request 原始请求
     * @return AI响应
     */
    protected AIResponse convertToAIResponse(ChatResponse chatResponse, AIRequest request) {
        if (chatResponse == null) {
            log.warn("ChatResponse为空，返回错误响应");
            return createErrorResponse("ChatResponse为空", request);
        }

        AiMessage aiMessage = chatResponse.aiMessage();
        if (aiMessage == null) {
            log.warn("AiMessage为空，返回错误响应");
            return createErrorResponse("AiMessage为空", request);
        }

        // 创建基础响应
        AIResponse aiResponse = createBaseResponse("", request);

        // 1. 设置基本内容
        convertBasicContent(aiMessage, aiResponse);

        // 2. 转换工具调用信息
        convertToolCalls(aiMessage, aiResponse);

        // 3. 转换Token使用情况
        convertTokenUsage(chatResponse, aiResponse);

        // 4. 转换完成原因
        convertFinishReason(chatResponse, aiResponse);

        // 5. 转换元数据
        convertMetadata(chatResponse, aiResponse);

        // 6. 设置生成时间
        aiResponse.setCreatedAt(LocalDateTime.now());

        log.debug("成功转换ChatResponse到AIResponse，内容长度: {}, 工具调用数: {}", 
            aiResponse.getContent() != null ? aiResponse.getContent().length() : 0,
            aiResponse.getToolCalls() != null ? aiResponse.getToolCalls().size() : 0);

        return aiResponse;
    }

    /**
     * 转换基本内容
     */
    private void convertBasicContent(AiMessage aiMessage, AIResponse aiResponse) {
        // 设置主要内容
        String content = aiMessage.text();
        aiResponse.setContent(content != null ? content : "");

        // TODO: 未来如果LangChain4j支持推理内容，在这里处理
        // aiResponse.setReasoningContent(...);
    }

    /**
     * 转换工具调用信息
     */
    private void convertToolCalls(AiMessage aiMessage, AIResponse aiResponse) {
        if (!aiMessage.hasToolExecutionRequests()) {
            return;
        }

        List<AIResponse.ToolCall> toolCalls = aiMessage.toolExecutionRequests().stream()
            .map(this::convertToAIResponseToolCall)
            .filter(Objects::nonNull)
            .collect(Collectors.toList());

        aiResponse.setToolCalls(toolCalls);
        log.debug("转换了 {} 个工具调用", toolCalls.size());
    }

    /**
     * 将LangChain4j的ToolExecutionRequest转换为AIResponse.ToolCall
     */
    private AIResponse.ToolCall convertToAIResponseToolCall(ToolExecutionRequest request) {
        if (request == null) {
            return null;
        }

        return AIResponse.ToolCall.builder()
            .id(request.id())
            .type("function") // LangChain4j主要支持函数调用
            .function(AIResponse.Function.builder()
                .name(request.name())
                .arguments(request.arguments() != null ? request.arguments() : "{}")
                .build())
            .build();
    }

    /**
     * 转换Token使用情况
     */
    private void convertTokenUsage(ChatResponse chatResponse, AIResponse aiResponse) {
        dev.langchain4j.model.output.TokenUsage langchainTokenUsage = chatResponse.tokenUsage();
        
        AIResponse.TokenUsage tokenUsage = new AIResponse.TokenUsage();
        
        if (langchainTokenUsage != null) {
            // LangChain4j的TokenUsage可能有inputTokenCount和outputTokenCount
            try {
                Integer inputTokens = langchainTokenUsage.inputTokenCount();
                Integer outputTokens = langchainTokenUsage.outputTokenCount();
                
                tokenUsage.setPromptTokens(inputTokens != null ? inputTokens : 0);
                tokenUsage.setCompletionTokens(outputTokens != null ? outputTokens : 0);
                
                log.debug("转换Token使用情况: 输入={}, 输出={}, 总计={}", 
                    tokenUsage.getPromptTokens(), 
                    tokenUsage.getCompletionTokens(), 
                    tokenUsage.getTotalTokens());
            } catch (Exception e) {
                log.warn("转换Token使用情况时出错: {}", e.getMessage());
                // 保持默认值
            }
        } else {
            log.debug("ChatResponse中没有Token使用情况信息");
        }
        
        aiResponse.setTokenUsage(tokenUsage);
    }

    /**
     * 转换完成原因
     */
    private void convertFinishReason(ChatResponse chatResponse, AIResponse aiResponse) {
        dev.langchain4j.model.output.FinishReason langchainFinishReason = chatResponse.finishReason();
        
        String finishReason = "unknown";
        if (langchainFinishReason != null) {
            // 将LangChain4j的FinishReason转换为字符串
            finishReason = convertFinishReasonToString(langchainFinishReason);
        }
        
        aiResponse.setFinishReason(finishReason);
        log.debug("设置完成原因: {}", finishReason);
    }

    /**
     * 将LangChain4j的FinishReason转换为字符串
     */
    private String convertFinishReasonToString(dev.langchain4j.model.output.FinishReason finishReason) {
        if (finishReason == null) {
            return "unknown";
        }
        
        // LangChain4j的FinishReason枚举值转换
        String reason = finishReason.toString().toLowerCase();
        switch (reason) {
            case "stop":
                return "stop";
            case "length":
                return "length";
            case "tool_execution":
                return "tool_calls";
            case "content_filter":
                return "content_filter";
            default:
                return reason;
        }
    }

    /**
     * 转换元数据
     */
    private void convertMetadata(ChatResponse chatResponse, AIResponse aiResponse) {
        try {
            var metadata = chatResponse.metadata();
            if (metadata != null) {
                Map<String, Object> metadataMap = new HashMap<>();
                
                // 添加LangChain4j特定的元数据
                metadataMap.put("langchain4j_metadata", metadata.toString());
                
                // 如果有其他可访问的元数据字段，在这里添加
                // 例如：模型版本、请求ID等
                
                aiResponse.setMetadata(metadataMap);
                log.debug("转换元数据完成");
            }
        } catch (Exception e) {
            log.warn("转换元数据时出错: {}", e.getMessage());
            // 设置空的元数据映射
            aiResponse.setMetadata(new HashMap<>());
        }
    }



    /**
     * 创建基础AI响应
     *
     * @param content 内容
     * @param request 请求
     * @return AI响应
     */
    protected AIResponse createBaseResponse(String content, AIRequest request) {
        AIResponse response = new AIResponse();
        response.setId(UUID.randomUUID().toString());
        response.setModel(getModelName());
        response.setContent(content);
        response.setCreatedAt(LocalDateTime.now());
        response.setTokenUsage(new AIResponse.TokenUsage());
        return response;
    }

    /**
     * 创建错误响应
     *
     * @param errorMessage 错误消息
     * @param request 请求
     * @return 错误响应
     */
    protected AIResponse createErrorResponse(String errorMessage, AIRequest request) {
        AIResponse response = createBaseResponse("", request);
        response.setFinishReason("error");
        response.setStatus("error");
        response.setErrorReason(errorMessage);
        return response;
    }



    /**
     * 获取API端点
     *
     * @param defaultEndpoint 默认端点
     * @return 实际使用的端点
     */
    protected String getApiEndpoint(String defaultEndpoint) {
        return apiEndpoint != null && !apiEndpoint.trim().isEmpty() ? apiEndpoint : defaultEndpoint;
    }
    
    /**
     * 获取聊天模型实例
     * @return 聊天模型
     */
    public ChatLanguageModel getChatModel() {
        if (chatModel == null) {
            throw new IllegalStateException("Chat model not initialized for provider: " + providerName);
        }
        return chatModel;
    }
    
    /**
     * 获取流式聊天模型实例
     * @return 流式聊天模型
     */
    public StreamingChatLanguageModel getStreamingChatModel() {
        if (streamingChatModel == null) {
            throw new IllegalStateException("Streaming chat model not initialized for provider: " + providerName);
        }
        return streamingChatModel;
    }

    /**
     * 估算输入令牌数
     *
     * @param request AI请求
     * @return 估算的令牌数
     */
    protected int estimateInputTokens(AIRequest request) {
        int tokenCount = 0;

        // 估算提示中的令牌数
        if (request.getPrompt() != null) {
            tokenCount += estimateTokenCount(request.getPrompt());
        }

        // 估算消息中的令牌数
        for (AIRequest.Message message : request.getMessages()) {
            tokenCount += estimateTokenCount(message.getContent());
        }

        return tokenCount;
    }

    /**
     * 估算文本的令牌数
     *
     * @param text 文本
     * @return 令牌数
     */
    protected int estimateTokenCount(String text) {
        if (text == null || text.isEmpty()) {
            return 0;
        }
        // 简单估算：平均每个单词1.3个令牌
        return (int) (text.split("\\s+").length * 1.3);
    }
    
    // ====== ToolCallCapable 接口实现 ======
    
    /**
     * 获取支持工具调用的聊天模型
     * @return 聊天模型实例
     */
    @Override
    public ChatLanguageModel getToolCallableChatModel() {
        return getChatModel();
    }
    
    /**
     * 获取支持工具调用的流式聊天模型
     * @return 流式聊天模型实例
     */
    @Override
    public StreamingChatLanguageModel getToolCallableStreamingChatModel() {
        return getStreamingChatModel();
    }
}
