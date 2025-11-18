package com.ainovel.server.domain.model;

import com.fasterxml.jackson.annotation.JsonValue;

/**
 * 小说设定类型枚举
 * 定义了可以由AI生成或用户创建的设定类型。
 * 与前端 AINoval/lib/models/setting_type.dart (或类似路径下的常量/枚举) 保持一致。
 */
public enum SettingType {
    CHARACTER("CHARACTER", "角色"),
    LOCATION("LOCATION", "地点"),
    ITEM("ITEM", "物品"),
    LORE("LORE", "背景知识"), // 世界观/传说/规则等
    FACTION("FACTION", "组织/势力"),
    EVENT("EVENT", "事件"),
    CONCEPT("CONCEPT", "概念/规则"), // 细化的规则或抽象概念
    CREATURE("CREATURE", "生物/种族"),
    MAGIC_SYSTEM("MAGIC_SYSTEM", "魔法体系"),
    TECHNOLOGY("TECHNOLOGY", "科技设定"),
    CULTURE("CULTURE", "文化"),
    HISTORY("HISTORY", "历史"),
    ORGANIZATION("ORGANIZATION", "组织"),
    // —— 通用叙事/世界构建扩展 ——
    WORLDVIEW("WORLDVIEW", "世界观"),
    PLEASURE_POINT("PLEASURE_POINT", "爽点"),
    ANTICIPATION_HOOK("ANTICIPATION_HOOK", "期待感钩子"),
    THEME("THEME", "主题"),
    TONE("TONE", "基调"),
    STYLE("STYLE", "文风"),
    TROPE("TROPE", "母题/套路"),
    PLOT_DEVICE("PLOT_DEVICE", "剧情装置"),
    POWER_SYSTEM("POWER_SYSTEM", "力量体系"),
    GOLDEN_FINGER("GOLDEN_FINGER", "金手指"),
    TIMELINE("TIMELINE", "时间线"),
    RELIGION("RELIGION", "宗教"),
    POLITICS("POLITICS", "政治"),
    ECONOMY("ECONOMY", "经济"),
    GEOGRAPHY("GEOGRAPHY", "地理"),
    
    // —— 细分的提取类型 ——
    NARRATIVE_STYLE("NARRATIVE_STYLE", "叙事方式"),
    WORD_USAGE_FEATURE("WORD_USAGE_FEATURE", "用词特点"),
    WRITING_STYLE_FEATURE("WRITING_STYLE_FEATURE", "文风特点"),
    CORE_CONFLICT_SETTING("CORE_CONFLICT_SETTING", "核心冲突"),
    SUSPENSE_ELEMENT("SUSPENSE_ELEMENT", "悬念设计"),
    PACING("PACING", "故事节奏"),
    
    OTHER("OTHER", "其他");

    private final String value;
    private final String displayName;

    SettingType(String value, String displayName) {
        this.value = value;
        this.displayName = displayName;
    }

    @JsonValue // This annotation is important for Jackson serialization/deserialization
    public String getValue() {
        return value;
    }

    public String getDisplayName() {
        return displayName;
    }

    public static SettingType fromValue(String value) {
        for (SettingType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        // Fallback to OTHER or throw an exception if strict matching is required
        // throw new IllegalArgumentException("Unknown setting type: " + value); 
        return OTHER; 
    }

    @Override
    public String toString() {
        return this.value;
    }
} 