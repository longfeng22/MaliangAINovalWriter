package com.ainovel.server.domain.model;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 知识库拆书类型枚举
 * 定义了可以从小说中提取的知识类型
 */
public enum KnowledgeExtractionType {
    
    // 文风叙事组
    NARRATIVE_STYLE("NARRATIVE_STYLE", "叙事方式", "NARRATIVE_STYLE_GROUP", 
                    Arrays.asList(SettingType.NARRATIVE_STYLE)),
    WRITING_STYLE("WRITING_STYLE", "文风", "NARRATIVE_STYLE_GROUP", 
                   Arrays.asList(SettingType.WRITING_STYLE_FEATURE)),
    WORD_USAGE("WORD_USAGE", "用词特点", "NARRATIVE_STYLE_GROUP", 
               Arrays.asList(SettingType.WORD_USAGE_FEATURE)),
    
    // 情节设计组
    CORE_CONFLICT("CORE_CONFLICT", "核心冲突", "PLOT_DESIGN_GROUP", 
                  Arrays.asList(SettingType.CORE_CONFLICT_SETTING)),
    SUSPENSE_DESIGN("SUSPENSE_DESIGN", "悬念设计", "PLOT_DESIGN_GROUP", 
                    Arrays.asList(SettingType.SUSPENSE_ELEMENT)),
    STORY_PACING("STORY_PACING", "故事节奏", "PLOT_DESIGN_GROUP", 
                 Arrays.asList(SettingType.PACING)),
    
    // 人物塑造组
    CHARACTER_BUILDING("CHARACTER_BUILDING", "人物塑造", "CHARACTER_BUILDING_GROUP", 
                      Arrays.asList(SettingType.CHARACTER)),
    
    // 小说特点组
    WORLDVIEW("WORLDVIEW", "世界观", "NOVEL_FEATURE_GROUP", 
              Arrays.asList(SettingType.WORLDVIEW, SettingType.LORE)),
    GOLDEN_FINGER("GOLDEN_FINGER", "金手指", "NOVEL_FEATURE_GROUP", 
                  Arrays.asList(SettingType.GOLDEN_FINGER, SettingType.POWER_SYSTEM)),
    
    // 读者情绪组
    RESONANCE("RESONANCE", "共鸣", "READER_EMOTION_GROUP", 
              Arrays.asList(SettingType.THEME)),
    PLEASURE_POINT("PLEASURE_POINT", "爽点", "READER_EMOTION_GROUP", 
                   Arrays.asList(SettingType.PLEASURE_POINT)),
    EXCITEMENT_POINT("EXCITEMENT_POINT", "嗨点", "READER_EMOTION_GROUP", 
                     Arrays.asList(SettingType.ANTICIPATION_HOOK, SettingType.PLEASURE_POINT)),
    
    // 热梗搞笑点组
    HOT_MEMES("HOT_MEMES", "热梗", "HOT_MEMES_GROUP", 
              Arrays.asList(SettingType.TROPE)),
    FUNNY_POINTS("FUNNY_POINTS", "搞笑点", "HOT_MEMES_GROUP", 
                 Arrays.asList(SettingType.TROPE)),
    
    // 用户自定义组
    CUSTOM("CUSTOM", "用户自定义", "CUSTOM_GROUP", 
           Arrays.asList(SettingType.OTHER)),
    
    // 章节大纲（特殊类型，单独处理）
    CHAPTER_OUTLINE("CHAPTER_OUTLINE", "章节大纲", "CHAPTER_OUTLINE_GROUP", 
                    Arrays.asList(SettingType.EVENT, SettingType.PLOT_DEVICE));
    
    private final String value;
    private final String displayName;
    private final String groupName;
    private final List<SettingType> relatedSettingTypes;
    
    KnowledgeExtractionType(String value, String displayName, String groupName, 
                           List<SettingType> relatedSettingTypes) {
        this.value = value;
        this.displayName = displayName;
        this.groupName = groupName;
        this.relatedSettingTypes = relatedSettingTypes;
    }
    
    public String getValue() {
        return value;
    }
    
    public String getDisplayName() {
        return displayName;
    }
    
    public String getGroupName() {
        return groupName;
    }
    
    public List<SettingType> getRelatedSettingTypes() {
        return relatedSettingTypes;
    }
    
    public static KnowledgeExtractionType fromValue(String value) {
        for (KnowledgeExtractionType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("Unknown extraction type: " + value);
    }
    
    /**
     * 获取分组名称对应的所有提取类型
     */
    public static List<KnowledgeExtractionType> getByGroup(String groupName) {
        return Arrays.stream(values())
                .filter(type -> type.groupName.equals(groupName))
                .collect(Collectors.toList());
    }
    
    /**
     * 获取所有默认提取类型（番茄小说默认使用）
     */
    public static List<KnowledgeExtractionType> getAllDefaultTypes() {
        return Arrays.asList(
            // 文风叙事组
            NARRATIVE_STYLE, WRITING_STYLE, WORD_USAGE,
            // 人物情节组
            CORE_CONFLICT, SUSPENSE_DESIGN, STORY_PACING, CHARACTER_BUILDING,
            // 小说特点组
            WORLDVIEW, GOLDEN_FINGER,
            // 读者情绪组
            RESONANCE, PLEASURE_POINT, EXCITEMENT_POINT,
            // 热梗搞笑点组
            HOT_MEMES, FUNNY_POINTS
            // 注意：不包括CHAPTER_OUTLINE，因为它单独处理
        );
    }
    
    @Override
    public String toString() {
        return this.value;
    }
}

