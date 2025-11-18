package com.ainovel.server.service.dto;

import java.util.List;
import java.util.Map;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * AI生成的设定数据传输对象
 * 用于存储和转换AI生成的JSON格式设定项数据
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiGeneratedSettingData {
    
    /**
     * 设定项名称
     */
    private String name;
    
    /**
     * 设定项类型
     */
    private String type;
    
    /**
     * 设定项描述
     */
    private String description;
    
    /**
     * 设定项属性（可选）
     */
    private Map<String, String> attributes;
    
    /**
     * 设定项标签（可选）
     */
    private List<String> tags;
    
    /**
     * 父设定ID（可选）
     * 用于建立设定之间的层级关系
     */
    private String parentId;
} 