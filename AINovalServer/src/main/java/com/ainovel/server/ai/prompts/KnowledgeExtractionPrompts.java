package com.ainovel.server.ai.prompts;

import com.ainovel.server.domain.model.KnowledgeExtractionType;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 知识提取提示词管理类
 * 为不同类型的知识提取提供专用提示词模板
 */
public class KnowledgeExtractionPrompts {
    
    /**
     * 获取知识提取的系统提示词
     */
    public static String getSystemPrompt() {
        return """
                你是一个专业的小说分析专家，擅长从小说文本中提取和总结各种创作技巧、风格特点和设定信息。
                
                你的任务是：
                1. 仔细阅读提供的小说文本
                2. 根据指定的分析类型，提取相关的知识点
                3. 每个知识点都要有清晰的名称和详细的描述
                4. 描述要具体、可操作，能够为其他创作者提供参考价值
                5. 使用工具函数返回结构化的结果
                
                **核心原则：设定内聚**
                - 优先将相关内容整合到一个设定中，而不是拆分成多个
                - 每个设定应该是完整、独立、可直接应用的
                - 避免生成过多碎片化的设定
                
                注意事项：
                - 提取的内容要基于实际文本，不要臆造
                - 描述要简洁明了，避免冗长
                - 每个知识点要有独特性，避免重复
                - 重点关注可以借鉴和学习的创作技巧
                """;
    }
    
    /**
     * 获取组提取的用户提示词（一次性提取多个类型）
     */
    public static String getGroupUserPrompt(List<KnowledgeExtractionType> types, String novelContent) {
        StringBuilder promptBuilder = new StringBuilder();
        
        promptBuilder.append("请分析以下小说文本，一次性提取以下类型的知识点：\n\n");
        
        // 列出所有需要提取的类型
        for (int i = 0; i < types.size(); i++) {
            promptBuilder.append(String.format("%d. %s\n", i + 1, types.get(i).getDisplayName()));
        }
        
        promptBuilder.append("\n【小说文本】\n");
        promptBuilder.append(truncateContent(novelContent, 3000));
        promptBuilder.append("\n\n【分析要求】\n");
        
        // 为每个类型添加具体要求
        for (KnowledgeExtractionType type : types) {
            promptBuilder.append(String.format("\n## %s\n", type.getDisplayName()));
            promptBuilder.append(getTypeSpecificPrompt(type));
            promptBuilder.append("\n");
        }
        
        promptBuilder.append("\n请使用addKnowledgeSetting工具函数返回提取的知识点，每个知识点包含：\n");
        promptBuilder.append("- type: 设定类型（必须是上述类型之一）\n");
        promptBuilder.append("- name: 知识点的简短名称（5-15字）\n");
        promptBuilder.append("- description: 详细描述（200-500字）\n");
        promptBuilder.append("- tags: 相关标签列表（可选）\n");
        
        return promptBuilder.toString();
    }
    
    /**
     * 获取指定类型的用户提示词（单个类型）
     */
    public static String getUserPrompt(KnowledgeExtractionType type, String novelContent) {
        String typePrompt = getTypeSpecificPrompt(type);
        
        return String.format("""
                请分析以下小说文本，提取"%s"相关的知识点：
                
                【小说文本】
                %s
                
                【分析要求】
                %s
                
                请使用addKnowledgeSetting工具函数返回提取的知识点，每个知识点包含：
                - name: 知识点的简短名称（5-15字）
                - description: 详细描述（200-500字）
                - tags: 相关标签列表（可选）
                """, 
                type.getDisplayName(),
                truncateContent(novelContent, 3000),
                typePrompt);
    }
    
    /**
     * 获取类型特定的提示词
     */
    private static String getTypeSpecificPrompt(KnowledgeExtractionType type) {
        return switch (type) {
            case NARRATIVE_STYLE -> """
                    请分析小说的叙事方式，包括：
                    - 叙事视角（第一人称/第三人称/全知视角等）
                    - 叙事节奏（快节奏/慢节奏/节奏变化）
                    - 叙事手法（顺叙/倒叙/插叙/补叙）
                    - 时间线处理方式
                    - 场景切换技巧
                    
                    **严格约束：**
                    1. 只生成1个设定
                    2. type字段必须为：NARRATIVE_STYLE
                    3. 将所有叙事方式特点整合到一个设定中
                    4. 描述要完整、内聚，包含所有重要的叙事特点
                    5. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    6. 为了更好的展示叙事特点，要摘选出多个原文本片段，最好每个100字以上，放在描述末尾，多个片段用空行分割
                    """;
                    
            case WRITING_STYLE -> """
                    请分析小说的文风特点，包括：
                    - 语言风格（正式/口语化/文艺/幽默等）
                    - 句式特点（长句/短句/排比/对话密度等）
                    - 修辞手法（比喻/拟人/夸张等）
                    - 情感表达方式
                    - 氛围营造技巧
                    
                    **严格约束：**
                    1. 只生成1个设定
                    2. type字段必须为：WRITING_STYLE_FEATURE
                    3. 将所有文风特点整合到一个设定中
                    4. 描述要全面、连贯，涵盖所有显著的文风特色
                    5. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    6. 为了更好的展示文风特点，要摘选出多个原文本片段，最好每个100字以上，放在描述末尾，多个片段用空行分割
                    """;
                    
            case WORD_USAGE -> """
                    请分析小说的用词特点，包括：
                    - 词汇选择倾向（书面语/口语/网络用语/方言等）
                    - 专业术语使用
                    - 形容词和副词的运用
                    - 动词的选择特点
                    - 独特的语言习惯
                    
                    **严格约束：**
                    1. 只生成1个设定
                    2. type字段必须为：WORD_USAGE_FEATURE
                    3. 将所有用词特点整合到一个设定中
                    4. 描述要完整、系统，体现整体的用词风格
                    5. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    6. 为了更好的展示用词特点，要摘选出多个原文本片段，最好每个100字以上，放在描述末尾，多个片段用空行分割
                    """;
                    
            case CORE_CONFLICT -> """
                    请分析小说的核心冲突，包括：
                    - 主要矛盾类型
                    - 冲突的起因和发展
                    - 对立双方的诉求
                    - 冲突的激化节点
                    - 冲突解决方式或方向
                    
                    **严格约束：**
                    1. 只生成1个设定
                    2. type字段必须为：CORE_CONFLICT_SETTING
                    3. 将所有主要冲突整合到一个设定中
                    4. 描述要清晰、完整，涵盖冲突的全貌
                    """;
                    
            case SUSPENSE_DESIGN -> """
                    请分析小说的悬念设计，包括：
                    - 主要悬念点的设置
                    - 悬念的铺垫方式
                    - 信息披露的节奏
                    - 伏笔的埋设技巧
                    - 悬念的解答时机
                    
                    **严格约束：**
                    2. type字段必须为：SUSPENSE_ELEMENT
                    4. 描述要系统化，展现完整的悬念体系
                    5. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case STORY_PACING -> """
                    请分析小说的故事节奏，包括：
                    - 情节推进速度
                    - 紧张与舒缓的交替
                    - 高潮的分布
                    - 过渡段落的处理
                    - 信息量控制
                    
                    **严格约束：**
                    2. type字段必须为：PACING
                    4. 描述要全面，体现整体的节奏控制策略
                    5. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case CHARACTER_BUILDING -> """
                    请分析小说的人物塑造，包括：
                    - 主要角色的性格特点
                    - 人物形象的塑造手法
                    - 人物成长和变化
                    - 人物关系网络
                    - 人物对话特色
                    
                    **严格约束：**
                    1. 每个角色只生成1个设定（重要角色才提取）
                    2. type字段必须为：CHARACTER
                    3. 每个角色设定要完整、独立
                    5. 优先提取主要角色和有特色的角色
                    6. 描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case WORLDVIEW -> """
                    请分析小说的世界观设定，包括：
                    - 世界背景和历史
                    - 社会结构和规则
                    - 地理环境
                    - 文化和价值观
                    - 独特的世界观元素
                    提取多个个核心世界观设定。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case GOLDEN_FINGER -> """
                    请分析小说的金手指设定，包括：
                    - 金手指类型（系统/异能/空间/重生等）
                    - 能力表现形式
                    - 获得方式和成长路径
                    - 限制和代价
                    - 与剧情的结合
                    提取所有重要金手指设定。
                    """;
                    
            case RESONANCE -> """
                    请分析小说的情感共鸣点，包括：
                    - 引发读者共鸣的情节
                    - 普世情感的触发
                    - 价值观认同点
                    - 情感宣泄时刻
                    - 代入感的建立
                    提取3-5个情感共鸣点。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case PLEASURE_POINT -> """
                    请分析小说的爽点设计，包括：
                    - 主角的逆袭时刻
                    - 打脸桥段
                    - 能力展现
                    - 获得奖励/提升
                    - 解决困难的成就感
                    提取3-5个爽点设计。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case EXCITEMENT_POINT -> """
                    请分析小说的嗨点设计，包括：
                    - 战斗/竞技场景
                    - 高潮情节
                    - 突破性时刻
                    - 意外反转
                    - 激动人心的展开
                    提取3-5个嗨点设计。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case HOT_MEMES -> """
                    请分析小说中的热梗运用，包括：
                    - 网络流行梗
                    - 二次元梗
                    - 影视游戏梗
                    - 经典桥段改编
                    - 梗的使用场景和效果
                    提取所有重要热梗。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case FUNNY_POINTS -> """
                    请分析小说的搞笑点，包括：
                    - 幽默对话
                    - 搞笑情节
                    - 反差萌
                    - 吐槽点
                    - 喜剧效果的营造
                    提取所有重要搞笑点。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case CUSTOM -> """
                    请从整体角度分析小说，提取用户可能感兴趣的其他创作特点：
                    - 独特的创意点
                    - 有意思的设定
                    - 特殊的表现手法
                    - 值得借鉴的技巧
                    提取所有有价值的知识点。
                    描述要引用原文本的例子，避免空洞地描述，比如用如"",例子: 等引用证明
                    """;
                    
            case CHAPTER_OUTLINE -> """
                    请为小说生成章节大纲（此类型将单独处理）。
                    """;
        };
    }
    
    
    /**
     * 不再截断内容，直接返回完整内容
     * @deprecated 已废弃，改为传递完整内容给AI
     */
    @Deprecated
    private static String truncateContent(String content, int maxLength) {
        // ✅ 取消截断限制，返回完整内容
        return content;
    }
    
    /**
     * 获取所有提示词的token估算
     */
    public static Map<KnowledgeExtractionType, Integer> estimateTokens() {
        Map<KnowledgeExtractionType, Integer> estimates = new HashMap<>();
        
        // 粗略估算每种类型的token消耗（系统提示词 + 类型提示词 + 内容）
        // 假设中文平均1个字=1.5个token
        for (KnowledgeExtractionType type : KnowledgeExtractionType.values()) {
            if (type == KnowledgeExtractionType.CHAPTER_OUTLINE) {
                estimates.put(type, 6000); // 章节大纲需要更多token
            } else {
                estimates.put(type, 5000); // 一般知识提取
            }
        }
        
        return estimates;
    }
}

