package com.ainovel.server.service.ai.strategy;

import com.ainovel.server.ai.prompts.KnowledgeExtractionPrompts;
import com.ainovel.server.ai.prompts.ChapterOutlineExtractionPrompts;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.KnowledgeExtractionType;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.utils.JsonRepairUtils;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 知识提取策略 - 使用结构化输出
 * 从小说文本中提取结构化的知识点
 */
@Slf4j
@RequiredArgsConstructor
public class KnowledgeExtractionStrategy {
    
    private final AIModelProvider aiModelProvider;
    private final ObjectMapper objectMapper;
    
    /**
     * 一次性提取组内所有类型的知识点
     * 
     * @param types 提取类型列表
     * @param content 小说内容
     * @param novelId 小说ID（可选）
     * @param userId 用户ID
     * @param chapterCount 章节数量（可选，用于章节大纲提取）
     * @param modelConfigId 模型配置ID（用于计费识别）
     * @param modelType 模型类型（user/public，用于计费识别）
     * @return 提取的设定列表
     */
    public Mono<List<NovelSettingItem>> extractKnowledgeForGroup(
            List<KnowledgeExtractionType> types,
            String content,
            String novelId,
            String userId,
            Integer chapterCount,
            String modelConfigId,
            String modelType) {  // ✅ 添加模型配置参数
        
        if (types == null || types.isEmpty()) {
            return Mono.just(Collections.emptyList());
        }
        
        // 如果只有一个type，使用单个提取方法
        if (types.size() == 1) {
            return extractKnowledge(types.get(0), content, novelId, userId, chapterCount, modelConfigId, modelType);
        }
        
        log.info("🎯 开始一次性提取知识组: types={}, contentLength={}", 
                types.stream().map(KnowledgeExtractionType::getDisplayName).toList(),
                content.length());
        
        try {
            // 构建AI请求
            AIRequest request = new AIRequest();
            request.setUserId(userId);
            request.setNovelId(novelId);
            
            // ✅ 设置模型配置ID用于计费识别
            if (modelConfigId != null && !modelConfigId.isBlank()) {
                request.getParameters().put("modelConfigId", modelConfigId);
                // ✅ 如果是公共模型（modelType不是"user"），同时设置publicModelConfigId
                if (!"user".equalsIgnoreCase(modelType)) {
                    if (request.getMetadata() == null) {
                        request.setMetadata(new java.util.HashMap<>());
                    }
                    request.getMetadata().put("publicModelConfigId", modelConfigId);
                    log.debug("✅ 设置公共模型标记: modelConfigId={}", modelConfigId);
                }
            }
            
            // ✅ 检查是否是章节大纲且有章节数量
            boolean isChapterOutline = types.stream()
                    .anyMatch(type -> type == KnowledgeExtractionType.CHAPTER_OUTLINE);
            
            // ✅ 根据是否包含章节大纲设置业务类型
            if (isChapterOutline) {
                request.setFeatureType(AIFeatureType.KNOWLEDGE_EXTRACTION_OUTLINE);
            } else {
                request.setFeatureType(AIFeatureType.KNOWLEDGE_EXTRACTION_SETTING);
            }
            
            // 系统消息
            AIRequest.Message systemMessage = new AIRequest.Message();
            systemMessage.setRole("system");
            systemMessage.setContent(KnowledgeExtractionPrompts.getSystemPrompt() + 
                    "\n\n**输出格式要求：**\n" +
                    "请以JSON数组格式返回结果，每个元素包含：\n" +
                    "{\n" +
                    "  \"type\": \"设定类型\",\n" +
                    "  \"name\": \"设定名称\",\n" +
                    "  \"description\": \"详细描述\",\n" +
                    "  \"tags\": [\"标签1\", \"标签2\"]\n" +
                    "}\n\n" +
                    "注意：\n" +
                    "1. type字段必须从指定的设定类型中选择\n" +
                    "2. 直接输出JSON数组，不要添加markdown代码块标记\n" +
                    "3. 确保JSON格式正确\n" +
                    "4. 每个设定都要完整\n" +
                    "5. 设定数量没有限制，但是重要的设定必须多提取");
            request.getMessages().add(systemMessage);
            
            // 用户消息 - 组合多个类型的提示词
            AIRequest.Message userMessage = new AIRequest.Message();
            userMessage.setRole("user");
            if (isChapterOutline && chapterCount != null && chapterCount > 0) {
                log.info("📖 章节大纲提取: 使用专用提示词类，期望章节数={}", chapterCount);
                // ✅ 使用专门的章节大纲提示词类
                AIRequest.Message chapterSystemMessage = new AIRequest.Message();
                chapterSystemMessage.setRole("system");
                chapterSystemMessage.setContent(ChapterOutlineExtractionPrompts.getSystemPrompt());
                request.getMessages().clear();  // 清除旧的系统消息
                request.getMessages().add(chapterSystemMessage);  // 使用章节大纲专用系统提示词
                
                userMessage.setContent(ChapterOutlineExtractionPrompts.getUserPrompt(content, chapterCount));
            } else {
                userMessage.setContent(KnowledgeExtractionPrompts.getGroupUserPrompt(types, content));
            }
            
            request.getMessages().add(userMessage);
            
            // 调用AI生成内容
            return aiModelProvider.generateContent(request)
                    .flatMap(response -> retrieveCompleteJson(aiModelProvider, request, response.getContent(), 3))
                    .flatMap(jsonContent -> parseKnowledgeJsonForGroup(jsonContent, types, novelId, userId))
                    .onErrorResume(error -> {
                        log.error("知识组提取失败: types={}, error={}", 
                                types.stream().map(KnowledgeExtractionType::getDisplayName).toList(),
                                error.getMessage(), error);
                        // 返回空列表而不是失败
                        return Mono.just(Collections.emptyList());
                    });
                    
        } catch (Exception e) {
            log.error("知识组提取异常: types={}, error={}", 
                    types.stream().map(KnowledgeExtractionType::getDisplayName).toList(),
                    e.getMessage(), e);
            return Mono.just(Collections.emptyList());
        }
    }
    
    /**
     * 提取知识点（单个类型）
     * 
     * @param type 提取类型
     * @param content 小说内容
     * @param novelId 小说ID（可选）
     * @param userId 用户ID
     * @param chapterCount 章节数量（可选，仅用于章节大纲）
     * @param modelConfigId 模型配置ID（用于计费识别）
     * @param modelType 模型类型（user/public，用于计费识别）
     * @return 提取的设定列表
     */
    public Mono<List<NovelSettingItem>> extractKnowledge(
            KnowledgeExtractionType type,
            String content,
            String novelId,
            String userId,
            Integer chapterCount,
            String modelConfigId,
            String modelType) {
        
        log.info("开始提取知识: type={}, contentLength={}, chapterCount={}", 
                type.getDisplayName(), content.length(), chapterCount);
        
        try {
            // 构建AI请求
            AIRequest request = new AIRequest();
            request.setUserId(userId);
            request.setNovelId(novelId);
            
            // ✅ 设置模型配置ID用于计费识别
            if (modelConfigId != null && !modelConfigId.isBlank()) {
                request.getParameters().put("modelConfigId", modelConfigId);
                // ✅ 如果是公共模型（modelType不是"user"），同时设置publicModelConfigId
                if (!"user".equalsIgnoreCase(modelType)) {
                    if (request.getMetadata() == null) {
                        request.setMetadata(new java.util.HashMap<>());
                    }
                    request.getMetadata().put("publicModelConfigId", modelConfigId);
                    log.debug("✅ 设置公共模型标记: modelConfigId={}", modelConfigId);
                }
            }
            
            // ✅ 根据提取类型设置业务类型
            if (type == KnowledgeExtractionType.CHAPTER_OUTLINE) {
                request.setFeatureType(AIFeatureType.KNOWLEDGE_EXTRACTION_OUTLINE);
            } else {
                request.setFeatureType(AIFeatureType.KNOWLEDGE_EXTRACTION_SETTING);
            }
            
            // ✅ 检查是否是章节大纲且有章节数量
            if (type == KnowledgeExtractionType.CHAPTER_OUTLINE && chapterCount != null && chapterCount > 0) {
                log.info("📖 单个章节大纲提取: 使用专用提示词类，期望章节数={}", chapterCount);
                
                // 系统消息 - 使用章节大纲专用提示词
                AIRequest.Message systemMessage = new AIRequest.Message();
                systemMessage.setRole("system");
                systemMessage.setContent(ChapterOutlineExtractionPrompts.getSystemPrompt());
                request.getMessages().add(systemMessage);
                
                // 用户消息 - 使用章节大纲专用提示词
                AIRequest.Message userMessage = new AIRequest.Message();
                userMessage.setRole("user");
                userMessage.setContent(ChapterOutlineExtractionPrompts.getUserPrompt(content, chapterCount));
                request.getMessages().add(userMessage);
            } else {
                // 普通知识提取
                // 系统消息
                AIRequest.Message systemMessage = new AIRequest.Message();
                systemMessage.setRole("system");
                systemMessage.setContent(KnowledgeExtractionPrompts.getSystemPrompt() + 
                        "\n\n**输出格式要求：**\n" +
                        "请以JSON数组格式返回结果，每个元素包含：\n" +
                        "{\n" +
                        "  \"type\": \"设定类型\",\n" +
                        "  \"name\": \"设定名称\",\n" +
                        "  \"description\": \"详细描述\",\n" +
                        "  \"tags\": [\"标签1\", \"标签2\"]\n" +
                        "}\n\n" +
                        "注意：\n" +
                        "1. type字段必须严格按照提示词中指定的类型返回\n" +
                        "2. 直接输出JSON数组，不要添加markdown代码块标记\n" +
                        "3. 确保JSON格式正确\n" +
                        "4. 每个设定都要完整");
                request.getMessages().add(systemMessage);
                
                // 用户消息
                AIRequest.Message userMessage = new AIRequest.Message();
                userMessage.setRole("user");
                userMessage.setContent(KnowledgeExtractionPrompts.getUserPrompt(type, content));
                request.getMessages().add(userMessage);
            }
            
            // 调用AI生成内容
            return aiModelProvider.generateContent(request)
                    .flatMap(response -> retrieveCompleteJson(aiModelProvider, request, response.getContent(), 3))
                    .flatMap(jsonContent -> parseKnowledgeJson(jsonContent, type, novelId, userId))
                    .onErrorResume(error -> {
                        log.error("知识提取失败: type={}, error={}", type.getDisplayName(), error.getMessage(), error);
                        // 返回空列表而不是失败
                        return Mono.just(Collections.emptyList());
                    });
                    
        } catch (Exception e) {
            log.error("知识提取异常: type={}, error={}", type.getDisplayName(), e.getMessage(), e);
            return Mono.just(Collections.emptyList());
        }
    }
    
    /**
     * 解析知识JSON（组提取）
     */
    private Mono<List<NovelSettingItem>> parseKnowledgeJsonForGroup(
            String jsonContent,
            List<KnowledgeExtractionType> types,
            String novelId,
            String userId) {
        
        // 组提取使用相同的解析逻辑，但支持多种type
        try {
            JsonNode rootNode = objectMapper.readTree(jsonContent);
            
            if (!rootNode.isArray()) {
                log.warn("JSON不是数组格式，尝试提取: types={}", 
                        types.stream().map(KnowledgeExtractionType::getDisplayName).toList());
                return attemptJsonRepairForGroup(jsonContent, types, novelId, userId);
            }
            
            List<NovelSettingItem> items = new ArrayList<>();
            
            for (JsonNode node : rootNode) {
                try {
                    String name = node.has("name") ? node.get("name").asText() : null;
                    String description = node.has("description") ? node.get("description").asText() : null;
                    
                    if (name != null && description != null) {
                        // 提取type字段
                        String settingType;
                        if (node.has("type") && !node.get("type").asText().isEmpty()) {
                            settingType = node.get("type").asText();
                            log.debug("✅ 使用AI返回的type: {}", settingType);
                        } else {
                            // ✅ 没有type字段时，根据提取类型列表推断（使用第一个作为默认值）
                            settingType = inferSettingType(types.get(0));
                            log.warn("⚠️ AI未返回type字段，使用提取类型 {} 推断为: {}", 
                                    types.get(0).getDisplayName(), settingType);
                        }
                        
                        // 提取标签
                        List<String> tags = new ArrayList<>();
                        if (node.has("tags") && node.get("tags").isArray()) {
                            for (JsonNode tagNode : node.get("tags")) {
                                tags.add(tagNode.asText());
                            }
                        }
                        
                        // 创建NovelSettingItem
                        NovelSettingItem item = NovelSettingItem.builder()
                                .id(java.util.UUID.randomUUID().toString())
                                .novelId(novelId)
                                .userId(userId)
                                .name(name)
                                .description(description)
                                .type(settingType)
                                .tags(tags)
                                .priority(5)
                                .generatedBy("KNOWLEDGE_EXTRACTION")
                                .status("active")
                                .createdAt(LocalDateTime.now())
                                .updatedAt(LocalDateTime.now())
                                .build();
                        
                        items.add(item);
                    }
                } catch (Exception e) {
                    log.warn("跳过无效的知识点: {}", e.getMessage());
                }
            }
            
            log.info("成功解析 {} 个知识点: types={}", items.size(), 
                    types.stream().map(KnowledgeExtractionType::getDisplayName).toList());
            return Mono.just(items);
            
        } catch (JsonProcessingException e) {
            log.error("JSON解析失败: types={}, error={}", 
                    types.stream().map(KnowledgeExtractionType::getDisplayName).toList(),
                    e.getMessage());
            return attemptJsonRepairForGroup(jsonContent, types, novelId, userId);
        }
    }
    
    /**
     * 尝试修复JSON（组提取）
     */
    private Mono<List<NovelSettingItem>> attemptJsonRepairForGroup(
            String jsonContent,
            List<KnowledgeExtractionType> types,
            String novelId,
            String userId) {
        
        log.info("尝试修复JSON: types={}", types.stream().map(KnowledgeExtractionType::getDisplayName).toList());
        
        try {
            String repairedJson = JsonRepairUtils.repairJson(jsonContent);
            if (repairedJson != null) {
                return parseKnowledgeJsonForGroup(repairedJson, types, novelId, userId);
            }
        } catch (Exception repairError) {
            log.warn("JSON修复失败: {}", repairError.getMessage());
        }
        
        // 修复失败，返回空列表
        return Mono.just(Collections.emptyList());
    }
    
    /**
     * 解析知识JSON（单个类型）
     */
    private Mono<List<NovelSettingItem>> parseKnowledgeJson(
            String jsonContent,
            KnowledgeExtractionType type,
            String novelId,
            String userId) {
        
        try {
            // 解析JSON数组
            JsonNode rootNode = objectMapper.readTree(jsonContent);
            
            if (!rootNode.isArray()) {
                log.warn("JSON不是数组格式，尝试提取: type={}", type.getDisplayName());
                return attemptJsonRepair(jsonContent, type, novelId, userId);
            }
            
            List<NovelSettingItem> items = new ArrayList<>();
            
            for (JsonNode node : rootNode) {
                try {
                    String name = node.has("name") ? node.get("name").asText() : null;
                    String description = node.has("description") ? node.get("description").asText() : null;
                    
                    if (name != null && description != null) {
                        // 提取type字段（优先使用AI返回的type，否则根据提取类型推断）
                        String settingType;
                        if (node.has("type") && !node.get("type").asText().isEmpty()) {
                            settingType = node.get("type").asText();
                            log.debug("✅ 使用AI返回的type: {}", settingType);
                        } else {
                            // ✅ 根据当前提取类型推断对应的设定类型
                            settingType = inferSettingType(type);
                            log.warn("⚠️ AI未返回type字段，使用提取类型 {} 推断为: {}", 
                                    type.getDisplayName(), settingType);
                        }
                        
                        // 提取标签
                        List<String> tags = new ArrayList<>();
                        if (node.has("tags") && node.get("tags").isArray()) {
                            for (JsonNode tagNode : node.get("tags")) {
                                tags.add(tagNode.asText());
                            }
                        }
                        
                        // 创建NovelSettingItem
                        NovelSettingItem item = NovelSettingItem.builder()
                                .id(java.util.UUID.randomUUID().toString())
                                .novelId(novelId)
                                .userId(userId)
                                .name(name)
                                .description(description)
                                .type(settingType)
                                .tags(tags)
                                .priority(5)
                                .generatedBy("KNOWLEDGE_EXTRACTION")
                                .status("active")
                                .createdAt(LocalDateTime.now())
                                .updatedAt(LocalDateTime.now())
                                .build();
                        
                        items.add(item);
                    }
                } catch (Exception e) {
                    log.warn("跳过无效的知识点: {}", e.getMessage());
                }
            }
            
            log.info("成功解析 {} 个知识点: type={}", items.size(), type.getDisplayName());
            return Mono.just(items);
            
        } catch (JsonProcessingException e) {
            log.error("JSON解析失败: type={}, error={}", type.getDisplayName(), e.getMessage());
            return attemptJsonRepair(jsonContent, type, novelId, userId);
        }
    }
    
    /**
     * 尝试修复JSON
     */
    private Mono<List<NovelSettingItem>> attemptJsonRepair(
            String jsonContent,
            KnowledgeExtractionType type,
            String novelId,
            String userId) {
        
        log.info("尝试修复JSON: type={}", type.getDisplayName());
        
        try {
            // 使用工具类修复JSON
            String repairedJson = JsonRepairUtils.repairJson(jsonContent);
            if (repairedJson != null) {
                return parseKnowledgeJson(repairedJson, type, novelId, userId);
            }
        } catch (Exception repairError) {
            log.warn("JSON修复失败: {}", repairError.getMessage());
        }
        
        // 尝试提取部分有效的JSON对象
        try {
            List<NovelSettingItem> partialItems = extractPartialValidJsonObjects(
                    jsonContent, type, novelId, userId);
            if (!partialItems.isEmpty()) {
                log.info("部分JSON提取成功: {} 个知识点", partialItems.size());
                return Mono.just(partialItems);
            }
        } catch (Exception partialError) {
            log.warn("部分JSON提取失败: {}", partialError.getMessage());
        }
        
        // 所有修复尝试都失败，返回空列表
        log.warn("无法解析AI响应，返回空列表: type={}", type.getDisplayName());
        return Mono.just(Collections.emptyList());
    }
    
    /**
     * 提取部分有效的JSON对象
     */
    private List<NovelSettingItem> extractPartialValidJsonObjects(
            String jsonContent,
            KnowledgeExtractionType type,
            String novelId,
            String userId) {
        
        List<NovelSettingItem> result = new ArrayList<>();
        
        // 使用正则表达式找到所有完整的JSON对象
        Pattern objectPattern = Pattern.compile("\\{[^{}]*(?:\\{[^{}]*\\}[^{}]*)*\\}");
        Matcher matcher = objectPattern.matcher(jsonContent);
        
        while (matcher.find()) {
            String objectJson = matcher.group();
            try {
                JsonNode node = objectMapper.readTree(objectJson);
                String name = node.has("name") ? node.get("name").asText() : null;
                String description = node.has("description") ? node.get("description").asText() : null;
                
                // ✅ 提取type字段（部分JSON修复场景）
                String settingType;
                if (node.has("type") && !node.get("type").asText().isEmpty()) {
                    settingType = node.get("type").asText();
                } else {
                    // 根据提取类型推断
                    settingType = inferSettingType(type);
                    log.debug("部分JSON提取: 推断type为 {}", settingType);
                }
                
                if (name != null && description != null) {
                    List<String> tags = new ArrayList<>();
                    if (node.has("tags") && node.get("tags").isArray()) {
                        for (JsonNode tagNode : node.get("tags")) {
                            tags.add(tagNode.asText());
                        }
                    }
                    
                    NovelSettingItem item = NovelSettingItem.builder()
                            .id(java.util.UUID.randomUUID().toString())
                            .novelId(novelId)
                            .userId(userId)
                            .name(name)
                            .description(description)
                            .type(settingType)
                            .tags(tags)
                            .priority(5)
                            .generatedBy("KNOWLEDGE_EXTRACTION")
                            .status("active")
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .build();
                    
                    result.add(item);
                }
            } catch (Exception e) {
                log.debug("跳过无效的JSON对象: {}", objectJson.substring(0, Math.min(100, objectJson.length())));
            }
        }
        
        return result;
    }
    
    /**
     * 递归向AI请求直到获取到完整且可解析的JSON
     */
    private Mono<String> retrieveCompleteJson(
            AIModelProvider provider,
            AIRequest baseRequest,
            String initialContent,
            int attemptsLeft) {
        
        return Mono.fromCallable(() -> {
            try {
                return extractJsonFromResponse(initialContent);
            } catch (Exception e) {
                log.debug("JSON提取失败: {}", e.getMessage());
                return null;
            }
        }).flatMap(json -> {
            if (json != null) {
                // 验证提取的JSON是否可以解析
                try {
                    objectMapper.readTree(json);
                    log.debug("JSON提取成功，长度: {}", json.length());
                    return Mono.just(json);
                } catch (JsonProcessingException e) {
                    log.warn("提取的JSON无法解析: {}", e.getMessage());
                }
            }
            
            if (attemptsLeft <= 0) {
                log.warn("多次尝试后仍无法解析完整JSON，返回原始内容");
                return Mono.just(initialContent);
            }
            
            log.info("JSON未完整，尝试让模型继续输出，剩余尝试: {}", attemptsLeft);
            
            // 构建继续请求
            AIRequest continueReq = new AIRequest();
            continueReq.setUserId(baseRequest.getUserId());
            continueReq.setNovelId(baseRequest.getNovelId());
            
            AIRequest.Message systemMsg = new AIRequest.Message();
            systemMsg.setRole("system");
            systemMsg.setContent("你之前输出的JSON数组不完整，请继续输出剩余内容。" +
                    "不要重复已输出的内容，直接继续，确保JSON完整有效。");
            continueReq.getMessages().add(systemMsg);
            
            AIRequest.Message assistantMsg = new AIRequest.Message();
            assistantMsg.setRole("assistant");
            String tail = initialContent.length() > 2000 ? 
                    initialContent.substring(initialContent.length() - 2000) : initialContent;
            assistantMsg.setContent(tail);
            continueReq.getMessages().add(assistantMsg);
            
            AIRequest.Message userMsg = new AIRequest.Message();
            userMsg.setRole("user");
            userMsg.setContent("请继续输出JSON数组，从上面的末尾直接继续。");
            continueReq.getMessages().add(userMsg);
            
            return provider.generateContent(continueReq)
                    .flatMap(resp -> {
                        String combined = initialContent + resp.getContent();
                        return retrieveCompleteJson(provider, baseRequest, combined, attemptsLeft - 1);
                    })
                    .onErrorResume(error -> {
                        log.error("重试请求失败: {}", error.getMessage());
                        return Mono.just(initialContent);
                    });
        });
    }
    
    /**
     * 从AI响应中提取JSON
     */
    private String extractJsonFromResponse(String response) {
        if (response == null || response.isEmpty()) {
            throw new IllegalArgumentException("AI响应为空");
        }
        
        // 使用工具类提取JSON
        String extractedJson = JsonRepairUtils.extractJsonFromResponse(response);
        if (extractedJson != null) {
            return extractedJson;
        }
        
        throw new IllegalArgumentException("无法从响应中提取JSON");
    }
    
    /**
     * 根据知识提取类型推断SettingType
     * ✅ 优化：确保每个提取类型都能正确映射到对应的设定类型，不会错误返回OTHER
     */
    private String inferSettingType(KnowledgeExtractionType type) {
        if (type.getRelatedSettingTypes() != null && !type.getRelatedSettingTypes().isEmpty()) {
            String inferredType = type.getRelatedSettingTypes().get(0).name();
            log.debug("根据提取类型 {} 推断设定类型: {}", type.getDisplayName(), inferredType);
            return inferredType;
        }
        // ⚠️ 只有在真的找不到映射关系时才返回OTHER（理论上不应该发生）
        log.warn("⚠️ 无法为提取类型 {} 找到对应的设定类型，回退到OTHER", type.getDisplayName());
        return "OTHER";
    }
}

