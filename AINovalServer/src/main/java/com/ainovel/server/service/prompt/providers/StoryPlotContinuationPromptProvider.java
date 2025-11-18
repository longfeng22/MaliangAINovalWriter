package com.ainovel.server.service.prompt.providers;

import java.util.Set;

import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.prompt.BasePromptProvider;

/**
 * 故事剧情续写功能提示词提供器
 * 专门用于总结当前剧情并生成下一个大纲，适用于剧情推演场景
 */
@Component
public class StoryPlotContinuationPromptProvider extends BasePromptProvider {

    // 默认系统提示词
    private static final String DEFAULT_SYSTEM_PROMPT = """
            你是一位经验丰富的小说家和剧情策划师，专门负责分析现有故事内容并创造引人入胜的后续剧情发展。

            ## 当前任务要求
            - **用户指令**: {{instructions}}
          如果用户指令不为空，务必遵守用户指令

            ## 你的核心能力
            1. **剧情分析**：深度理解现有故事的人物关系、冲突设定和发展脉络
            2. **情节设计**：设计符合故事逻辑的后续发展，包含合理的转折和高潮
            3. **人物发展**：推进角色成长弧线，深化人物性格和关系变化
            4. **冲突升级**：合理设置新的冲突点和挑战，保持故事张力
            5. **世界观延续**：保持世界观设定的一致性，合理扩展故事背景

            ## 剧情续写原则
            - 深度理解已有故事的核心主题和风格基调
            - 严格按照指定的风格和长度要求执行
            - 保持角色行为的一致性和逻辑性
            - 设计有意义的情节推进，避免无目的的重复
            - 创造适度的悬念和冲突，推动故事发展
            - 考虑读者期待，平衡预期和惊喜

            ## 操作指南
            1. 仔细阅读并分析现有故事内容和背景设定
            2. 识别当前故事的核心冲突和未解决的线索
            3. 结合上下文信息理解人物关系和动机
            4. 根据指定要求设计后续剧情发展方向
            5. 直接输出后续剧情大纲，重点突出关键情节点和人物发展

            请准备根据用户提供的故事内容生成后续剧情发展。
            """;

    // 默认用户提示词
    private static final String DEFAULT_USER_PROMPT = """
            ## 需要续写的故事内容
            {{input}}

            ## 相关上下文
            {{context}}

            ## 续写要求
            请基于以上故事内容，分析当前剧情发展状况，然后生成一个引人入胜的后续剧情大纲。
            
            **输出格式要求：**
            1. 简要总结当前剧情要点
            2. 分析主要冲突和未解决的线索
            3. 提供后续剧情发展方向
            4. 突出关键情节点和转折

            请确保续写内容与原故事风格保持一致，并推动故事向前发展，注意剧情衔接要流畅,只输出正文和标题，不要添加任何其他内容。
            """;

    public StoryPlotContinuationPromptProvider() {
        super(AIFeatureType.STORY_PLOT_CONTINUATION);
    }

    @Override
    protected Set<String> initializeSupportedPlaceholders() {
        return Set.of(
            // 核心占位符（必需）
            "input", "context", "instructions",
            "novelTitle", "authorName",
            
            // 功能特定参数
            "length", "style",
            
            // 内容提供器占位符（已实现）
            "full_novel_text", "full_novel_summary",
            "act", "chapter", "scene", "setting", "snippet",
            
            // 剧情续写特有占位符
            "currentChapter", "mainCharacters", "plotPoints",
            "conflictPoints", "themeElements", "worldSetting"
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
    
    @Override
    public String getTemplateName() {
        return "故事剧情续写";
    }

    @Override
    public String getTemplateDescription() {
        return "专门用于分析现有剧情并生成后续发展大纲的提示词模板，适合剧情推演和故事续写场景";
    }

    @Override
    public String getTemplateIdentifier() {
        return "STORY_PLOT_CONTINUATION_1";
    }
}
