package com.ainovel.server.domain.model;

/**
 * AI功能类型枚举 用于定义不同AI功能的类型标识
 */
public enum AIFeatureType {
    /**
     * 场景生成摘要
     */
    SCENE_TO_SUMMARY,
    /**
     * 摘要生成场景
     */
    SUMMARY_TO_SCENE,
    
    /**
     * 文本扩写功能
     */
    TEXT_EXPANSION,
    
    /**
     * 文本重构功能
     */
    TEXT_REFACTOR,
    
    /**
     * 文本缩写功能
     */
    TEXT_SUMMARY,
    
    /**
     * AI聊天对话功能
     */
    AI_CHAT,
    
    /**
     * 小说内容生成功能
     */
    NOVEL_GENERATION,
    
    /**
     * 专业续写小说功能
     */
    PROFESSIONAL_FICTION_CONTINUATION,
    
    /**
     * 场景节拍生成功能
     */
    SCENE_BEAT_GENERATION,
    
    /**
     * AI设定树生成功能
     */
    SETTING_TREE_GENERATION

    ,
    /**
     * 设定生成工具调用阶段
     */
    SETTING_GENERATION_TOOL
    ,
    /**
     * 小说编排（大纲/章节/组合）
     */
    NOVEL_COMPOSE,
    
    /**
     * 故事剧情续写（总结当前剧情并生成下一个大纲）
     */
    STORY_PLOT_CONTINUATION,
    
    /**
     * 知识库拆书 - 设定提取（也用于积分预估）
     */
    KNOWLEDGE_EXTRACTION_SETTING,

    /**
     * 知识库拆书 - 章节大纲生成
     */
    KNOWLEDGE_EXTRACTION_OUTLINE

}
