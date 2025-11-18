package com.ainovel.server.service.prompt.providers;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.prompt.BasePromptProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Set;

/**
 * 章节大纲生成功能提示词提供器
 * 专门用于从小说文本中提取和生成章节大纲
 */
@Slf4j
@Component
public class ChapterOutlinePromptProvider extends BasePromptProvider {

    // 默认系统提示词
    private static final String DEFAULT_SYSTEM_PROMPT = """
            你是一位专业的小说编辑和大纲策划师，擅长分析小说文本结构并提取章节大纲。
            
            你的任务是：
            1. 识别小说文本中的章节划分
            2. 为每一章生成简洁而全面的大纲
            3. 提取章节的核心情节、关键事件和人物动向
            4. 突出情节主线和转折点
            5. 返回结构化的JSON格式结果
            
            **输出格式要求：**
            请以JSON数组格式返回结果，每个元素包含：
            {
              "name": "第X章：章节标题",
              "description": "章节概要（50-100字），包含：\\n- 核心情节\\n- 关键事件\\n- 人物动向\\n- 情节转折",
              "tags": ["章节标签", "情节类型"]
            }
            
            注意事项：
            - 如果没有明确章节标题，使用"第X章"作为标题
            - 大纲要简洁但信息完整
            - 按章节顺序排列
            - 直接输出JSON数组，不要添加markdown代码块标记
            - 确保JSON格式正确
            """;

    // 默认用户提示词模板
    private static final String DEFAULT_USER_PROMPT = """
            请为以下小说文本生成结构化的章节大纲：
            
            【小说文本】
            {{content}}
            
            【大纲要求】
            1. 按自然章节划分（识别章节标题或根据内容划分）
            2. 每章包含：
               - 章节标题
               - 核心情节概要（50-100字）
               - 关键事件列表
               - 主要人物动向
               - 重要的情节转折点
            3. 大纲要突出故事主线和发展脉络
            4. 标注重要的伏笔和铺垫
            
            请返回JSON数组格式的章节大纲。
            """;

    public ChapterOutlinePromptProvider() {
        super(AIFeatureType.KNOWLEDGE_EXTRACTION_OUTLINE);
    }

    @Override
    protected Set<String> initializeSupportedPlaceholders() {
        return Set.of(
            "content",          // 小说内容
            "novelTitle",       // 小说标题（可选）
            "novelAuthor",      // 小说作者（可选）
            "chapterRange",     // 章节范围（可选，如"1-10章"）
            "outlineDetail"     // 大纲详细程度（可选：简略/详细）
        );
    }

    @Override
    protected Map<String, String> initializePlaceholderDescriptions() {
        return Map.of(
            "content", "要分析的小说文本内容",
            "novelTitle", "小说标题（可选）",
            "novelAuthor", "小说作者（可选）",
            "chapterRange", "要生成大纲的章节范围（可选）",
            "outlineDetail", "大纲详细程度：简略/详细（可选）"
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

