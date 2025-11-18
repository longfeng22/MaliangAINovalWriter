package com.ainovel.server.ai.prompts;

/**
 * 章节大纲提取专用提示词类
 * 
 * ⚠️ 注意：本类用于知识提取任务中的章节大纲生成
 * 与 ChapterOutlinePromptProvider 的区别：
 * - ChapterOutlinePromptProvider：完整的Spring管理服务，继承BasePromptProvider，支持数据库模板、用户自定义、占位符解析等
 * - 本类：轻量级静态工具类，用于知识提取任务的快速调用，不需要Spring依赖注入
 * 
 * 为什么不继承BasePromptProvider？
 * 1. BasePromptProvider是一个重量级服务，包含：
 *    - 数据库模板查询和管理
 *    - 用户自定义模板支持
 *    - 占位符解析和内容提供器
 *    - Spring依赖注入和生命周期管理
 * 
 * 2. 知识提取任务是后台批处理，需要：
 *    - 快速、直接的提示词生成
 *    - 不依赖用户上下文和模板系统
 *    - 纯静态方法调用，无Spring依赖
 * 
 * 3. 架构分离原则：
 *    - BasePromptProvider体系用于用户主动交互场景（AI聊天、文本扩写等）
 *    - 静态提示词工具类用于系统自动化任务（知识提取、批处理等）
 */
public class ChapterOutlineExtractionPrompts {
    
    /**
     * 获取章节大纲生成的系统提示词
     */
    public static String getSystemPrompt() {
        return """
                你是一位专业的小说编辑和大纲策划师，擅长分析小说文本结构并提取章节大纲。
                
                你的任务是：
                1. 识别小说文本中的章节划分
                2. 为每一章生成简洁而全面的大纲
                3. 提取章节的核心情节、关键事件和人物动向
                4. 突出情节主线和转折点
                5. 返回结构化的JSON格式结果
                
                **核心原则：精准对应**
                - 有多少章节就生成多少个大纲
                - 不要遗漏任何章节
                - 不要多生成额外的章节
                
                **输出格式要求：**
                请以JSON数组格式返回结果，每个元素包含：
                {
                  "type": "EVENT",
                  "name": "第X章：章节标题",
                  "description": "章节概要（200-500字），包含：\\n- 核心情节\\n- 关键事件\\n- 人物动向\\n- 情节转折",
                  "tags": ["章节标签", "order:X"]
                }
                
                注意事项：
                - 如果没有明确章节标题，使用"第X章"作为标题
                - 大纲要简洁但信息完整
                - 按章节顺序排列
                - tags中必须包含 "order:X" 表示章节顺序
                - 直接输出JSON数组，不要添加markdown代码块标记
                - 确保JSON格式正确
                """;
    }
    
    /**
     * 获取章节大纲生成的用户提示词
     * 
     * @param novelContent 小说内容（完整，不截断）
     * @param expectedChapterCount 期望生成的章节数量
     * @return 用户提示词
     */
    public static String getUserPrompt(String novelContent, int expectedChapterCount) {
        return String.format("""
                请为以下小说文本生成结构化的章节大纲：
                
                【小说文本】
                %s
                
                【大纲要求】
                1. 按自然章节划分（识别章节标题）
                2. 每章包含：
                   - 章节标题
                   - 核心情节概要（200-500字）
                   - 关键事件
                   - 人物动向
                3. 大纲要突出情节主线和转折点
                
                **严格约束：**
                1. 必须生成 %d 个章节大纲
                2. type字段必须为：EVENT
                3. 每个章节大纲必须完整、独立
                4. 确保章节顺序正确（tags中包含 order:1, order:2, ...）
                5. 不要遗漏任何章节
                6. 不要多生成额外的章节
                
                请使用addChapterOutline工具函数返回每一章的大纲信息。
                """,
                novelContent,  // ✅ 完整内容，不截断
                expectedChapterCount);
    }
}


