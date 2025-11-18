package com.ainovel.server.service.impl;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.KeywordExtractionService;
import com.fasterxml.jackson.databind.ObjectMapper;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

/**
 * 关键词提取服务实现类
 * 使用轻量级LLM从文本中提取关键词
 */
@Slf4j
@Deprecated
@Service
public class KeywordExtractionServiceImpl implements KeywordExtractionService {

    private final AIService aiService;
    private final ObjectMapper objectMapper;
    
    @Value("${ainovel.ai.keyword-extraction.model:gemini-2.0-flash}")
    private String extractionModelName;
    
    @Value("${ainovel.ai.keyword-extraction.timeout:10}")
    private int timeoutSeconds;
    
    @Value("${ainovel.ai.keyword-extraction.max-text-length:3000}")
    private int maxTextLength;

    @Value("${ai.gemini.api-key}")
    private String apiKey;

    @Value("${ai.gemini.api-key:https://generativelanguage.googleapis.com/v1beta/models/}")
    private String endPoint;
    
    @Autowired
    public KeywordExtractionServiceImpl(AIService aiService, ObjectMapper objectMapper) {
        this.aiService = aiService;
        this.objectMapper = objectMapper;
    }
    
    @Override
    public Mono<List<String>> extractKeywords(String text) {
        return extractKeywords(text, 20); // 默认最多提取20个关键词
    }
    
    @Override
    public Mono<List<String>> extractKeywords(String text, int maxKeywords) {
        if (text == null || text.isEmpty()) {
            return Mono.just(Collections.emptyList());
        }
        
        // 截断文本，避免超出模型处理限制
        String trimmedText = text;
        if (text.length() > maxTextLength) {
            trimmedText = text.substring(0, maxTextLength);
            log.info("文本太长，已截断至 {} 字符", maxTextLength);
        }
        
        // 准备提示词
        String prompt = "从以下文本中提取出所有可能与小说设定相关的实体名词和关键词 (人物、地点、物品、组织、概念等)，"
                + "以JSON数组格式返回，格式为 [\"关键词1\", \"关键词2\", ...]，不要有任何其他内容。"
                + "最多提取" + maxKeywords + "个关键词:\n\n" + trimmedText;
        
        // 创建请求
        AIRequest request = new AIRequest();
        request.setModel(extractionModelName);
        request.setTemperature(0.0); // 保持确定性输出
        request.setMaxTokens(500); // 关键词输出通常不会太长
        
        AIRequest.Message systemMessage = new AIRequest.Message();
        systemMessage.setRole("system");
        systemMessage.setContent("你是一个专业的文本分析工具，能够精确地从文本中提取关键实体和概念。请只返回JSON格式的关键词数组，不要有其他任何解释或描述。");
        
        AIRequest.Message userMessage = new AIRequest.Message();
        userMessage.setRole("user");
        userMessage.setContent(prompt);
        
        request.setMessages(Arrays.asList(systemMessage, userMessage));
        
        // 执行AI调用
        return Mono.<List<String>>create(sink -> {
            String provider;
            try {
                provider = aiService.getProviderForModel(extractionModelName);
                log.info("使用模型 {} (provider: {}) 提取关键词", extractionModelName, provider);
            } catch (Exception e) {
                log.error("获取提供商失败: {}", e.getMessage(), e);
                sink.success(Collections.emptyList());
                return;
            }
            
            // 统一按配置ID创建 Provider（这里无用户配置ID，可保留直连；如有 userId+configId，则改为 createProviderByConfigId）
            // 服务已废弃：直接返回空列表，避免直连旧入口
            Mono.just(java.util.Collections.<String>emptyList())
                .doOnError(e -> {
                    log.error("关键词提取失败: {}", e.getMessage(), e);
                    sink.success(Collections.emptyList());
                })
                .subscribe(sink::success, sink::error);
        })
        .subscribeOn(Schedulers.boundedElastic());
    }
    
    /**
     * 解析AI响应，提取关键词列表
     */
    @SuppressWarnings("unchecked")
    private Mono<List<String>> parseKeywords(AIResponse response) {
        try {
            String content = response.getContent();
            
            // 尝试直接解析JSON数组
            if (content.startsWith("[") && content.endsWith("]")) {
                try {
                    List<String> keywords = objectMapper.readValue(content, List.class);
                    return Mono.just(keywords);
                } catch (Exception e) {
                    log.warn("无法直接解析JSON数组: {}", e.getMessage());
                }
            }
            
            // 尝试从文本中提取JSON数组
            int startIdx = content.indexOf("[");
            int endIdx = content.lastIndexOf("]");
            
            if (startIdx >= 0 && endIdx > startIdx) {
                String jsonArray = content.substring(startIdx, endIdx + 1);
                try {
                    List<String> keywords = objectMapper.readValue(jsonArray, List.class);
                    return Mono.just(keywords);
                } catch (Exception e) {
                    log.warn("无法解析提取的JSON数组: {}", e.getMessage());
                }
            }
            
            // 回退到简单的文本解析
            log.info("使用简单文本解析提取关键词");
            List<String> keywords = Arrays.asList(content.split("[,，\n]")).stream()
                    .map(k -> k.trim().replace("\"", "").replace("[", "").replace("]", ""))
                    .filter(k -> !k.isEmpty())
                    .collect(Collectors.toList());
            
            return Mono.just(keywords);
            
        } catch (Exception e) {
            log.error("解析关键词失败: {}", e.getMessage(), e);
            return Mono.just(Collections.emptyList());
        }
    }
} 