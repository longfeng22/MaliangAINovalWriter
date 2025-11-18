package com.ainovel.server.service.fanqie.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieNovelInfo {
    
    /**
     * 小说ID
     */
    private String id;
    
    /**
     * 小说标题
     */
    private String title;
    
    /**
     * 作者
     */
    private String author;
    
    /**
     * 封面图片URL
     */
    private String cover;
    
    /**
     * 小说简介/描述
     */
    private String description;
    
    /**
     * 小说分类（如：动漫衍生）
     */
    private String category;
    
    /**
     * 评分（如：8.5）
     */
    private String score;
}

