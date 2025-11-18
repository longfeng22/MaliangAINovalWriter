package com.ainovel.server.service.prompt.providers;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.prompt.BasePromptProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Set;

/**
 * 知识提取功能提示词提供器
 * 基于 BasePromptProvider 实现知识提取相关的提示词管理
 */
@Slf4j
@Component
public class KnowledgeExtractionPromptProvider extends BasePromptProvider {

    // 默认系统提示词（复用KnowledgeExtractionPrompts）
    private static final String DEFAULT_SYSTEM_PROMPT = """
            你是一个专业的小说分析专家，擅长从小说文本中提取和总结各种创作技巧、风格特点和设定信息。
            
            你的任务是：
            1. 仔细阅读提供的小说文本
            2. 根据指定的分析类型，提取相关的知识点
            3. 每个知识点都要有清晰的名称和详细的描述
            4. 描述要具体、可操作，能够为其他创作者提供参考价值
            5. 返回结构化的JSON格式结果
            
            **输出格式要求：**
            请以JSON数组格式返回结果，每个元素包含：
            {
              "name": "设定名称",
              "description": "详细描述",
              "tags": ["标签1", "标签2"]
            }
            
            注意事项：
            - 提取的内容要基于实际文本，不要臆造
            - 描述要简洁明了，避免冗长
            - 每个知识点要有独特性，避免重复
            - 重点关注可以借鉴和学习的创作技巧
            - 直接输出JSON数组，不要添加markdown代码块标记
            - 确保JSON格式正确，每个设定都要完整
            """;

    // 默认用户提示词模板
    private static final String DEFAULT_USER_PROMPT = """
            请分析以下小说文本，提取"{{extractionType}}"相关的知识点：
            
            【小说文本】
            {{content}}
            
            【分析要求】
            {{typeSpecificPrompt}}
            
            请返回JSON数组格式的结果。
            """;

    public KnowledgeExtractionPromptProvider() {
        super(AIFeatureType.KNOWLEDGE_EXTRACTION_SETTING);
    }

    @Override
    protected Set<String> initializeSupportedPlaceholders() {
        return Set.of(
            "content",              // 小说内容
            "extractionType",       // 提取类型
            "typeSpecificPrompt",   // 类型特定提示词
            "novelTitle",           // 小说标题（可选）
            "novelAuthor"           // 小说作者（可选）
        );
    }

    @Override
    protected Map<String, String> initializePlaceholderDescriptions() {
        return Map.of(
            "content", "要分析的小说文本内容",
            "extractionType", "知识提取类型（如：叙事方式、文风、人物塑造等）",
            "typeSpecificPrompt", "针对特定类型的详细分析要求",
            "novelTitle", "小说标题（可选，用于上下文）",
            "novelAuthor", "小说作者（可选，用于风格分析）"
        );
    }

    @Override
    public String getDefaultSystemPrompt() {
        return DEFAULT_SYSTEM_PROMPT;
    }

    @Override
    public String getDefaultUserPrompt() {
        return DEFAULT_USER_PROMPT;
    }
}

