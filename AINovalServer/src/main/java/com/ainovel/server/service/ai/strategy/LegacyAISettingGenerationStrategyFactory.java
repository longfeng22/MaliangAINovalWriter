package com.ainovel.server.service.ai.strategy;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import java.time.LocalDateTime;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.domain.model.SettingType;
import com.ainovel.server.service.EnhancedUserPromptService;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.service.dto.AiGeneratedSettingData;
import com.fasterxml.jackson.databind.ObjectMapper;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * AI设定生成策略工厂
 * 根据AI模型提供商类型选择合适的策略生成小说设定
 * @deprecated 使用新的设定生成模块替代
 */
@Slf4j
@Component("legacySettingGenerationStrategyFactory")
public class LegacyAISettingGenerationStrategyFactory {
    
    private final EnhancedUserPromptService promptService;
    private final ObjectMapper objectMapper;
    
    @Autowired
    public LegacyAISettingGenerationStrategyFactory(EnhancedUserPromptService promptService, ObjectMapper objectMapper) {
        this.promptService = promptService;
        this.objectMapper = objectMapper;
    }
    
    /**
     * 根据AI模型提供商创建合适的设定生成策略
     * 
     * @param aiModelProvider AI模型提供商
     * @return 设定生成策略
     */
    public SettingGenerationStrategy createStrategy(AIModelProvider aiModelProvider) {
        try {
            // 检查提供商名称判断是否支持结构化输出
            String providerName = aiModelProvider.getProviderName();
            
            // 根据提供商名称判断是否支持结构化JSON输出
            boolean supportsStructuredOutput = false;
            
            // 检查是否为支持结构化输出的模型提供商
            if (providerName != null) {
                providerName = providerName.toUpperCase();
                // 判断是否是已知支持结构化输出的提供商
                if (providerName.contains("OPENAI") || 
                    providerName.contains("AZURE") || 
                    providerName.contains("GEMINI") ||
                    providerName.contains("OLLAMA") ||
                    providerName.contains("MISTRAL") ||
                    providerName.contains("GOOGLE")) {
                    supportsStructuredOutput = true;
                    log.info("检测到支持结构化输出的模型提供商: {}", providerName);
                }
            }
            
            // 检查模型名称
            String modelName = aiModelProvider.getModelName();
            if (modelName != null) {
                modelName = modelName.toLowerCase();
                if (modelName.contains("gpt") || 
                    modelName.contains("gemini") ||
                    modelName.contains("claude") ||
                    modelName.contains("llama") ||
                    modelName.contains("mistral")) {
                    supportsStructuredOutput = true;
                    log.info("检测到支持结构化输出的模型: {}", modelName);
                }
            }
            
            if (supportsStructuredOutput) {
                return new StructuredOutputStrategy(promptService, objectMapper);
            } else {
                log.info("使用基于提示词的策略生成设定");
                return new PromptBasedStrategy(promptService, objectMapper);
            }
        } catch (Exception e) {
            log.warn("确定生成策略时出错，默认使用基于提示词的策略: {}", e.getMessage());
            return new PromptBasedStrategy(promptService, objectMapper);
        }
    }
    
    /**
     * 将生成的设定数据转换为NovelSettingItem实体
     * 
     * @param data 生成的设定数据
     * @param novelId 小说ID
     * @param userId 用户ID
     * @param validRequestedTypes 有效的请求类型列表
     * @return 小说设定项或null（如果数据无效）
     */
    public static NovelSettingItem convertToNovelSettingItem(
            AiGeneratedSettingData data, 
            String novelId, 
            String userId, 
            List<String> validRequestedTypes) {
            
        if (data.getName() == null || data.getName().trim().isEmpty() ||
            data.getType() == null || data.getType().trim().isEmpty() ||
            data.getDescription() == null || data.getDescription().trim().isEmpty()) {
            log.warn("AI生成的设定数据缺少必要字段 (name, type, 或 description): {}. 跳过此项。", data);
            return null; 
        }

        SettingType settingTypeEnum;
        String aiType = data.getType().trim().toUpperCase(); // 规范化AI输出

        // 验证AI返回的类型是否是原始请求的有效类型之一
        if (!validRequestedTypes.contains(aiType)) {
            log.warn("AI生成了类型 '{}' 但它不在有效的请求类型列表中 ({})，尝试映射或默认为OTHER。原始数据: {}",
                     aiType, validRequestedTypes, data);
            // 尝试映射到有效的枚举，或默认为OTHER
            try {
                settingTypeEnum = SettingType.fromValue(aiType); // 如果无法识别，这将映射为OTHER
            } catch (IllegalArgumentException e) {
                log.warn("严格枚举转换失败，AI类型 '{}' 默认为OTHER", aiType);
                settingTypeEnum = SettingType.OTHER;
            }
        } else {
            // 类型有效且被请求
            settingTypeEnum = SettingType.fromValue(aiType);
        }
        
        Map<String, String> attributes = data.getAttributes() != null ? data.getAttributes() : Collections.emptyMap();
        List<String> tags = data.getTags() != null ? data.getTags() : Collections.emptyList();
        String parentId = data.getParentId(); // 获取父设定ID

        return NovelSettingItem.builder()
                .id(UUID.randomUUID().toString())
                .novelId(novelId)
                .userId(userId)
                .name(data.getName().trim())
                .type(settingTypeEnum.getValue()) 
                .description(data.getDescription().trim())
                .attributes(attributes)
                .tags(tags)
                .parentId(parentId) // 设置父设定ID
                .priority(3) 
                .generatedBy("AI_SETTING_GENERATION")
                .status("SUGGESTED")
                .isAiSuggestion(true)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .relationships(Collections.emptyList())
                .sceneIds(Collections.emptyList())
                .imageUrl(null)
                .vector(null)
                .metadata(Collections.emptyMap())
                .build();
    }
} 