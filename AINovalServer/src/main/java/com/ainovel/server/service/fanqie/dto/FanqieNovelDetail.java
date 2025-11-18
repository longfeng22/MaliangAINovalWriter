package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 番茄小说详细信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieNovelDetail {
    
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
     * 小说简介
     */
    private String description;
    
    /**
     * 状态
     */
    private String status;
    
    /**
     * 标签
     */
    private String tags;
    
    /**
     * 总章节数
     */
    @JsonProperty("total_chapters")
    private Integer totalChapters;
    
    /**
     * 封面图片URL
     */
    @JsonProperty("cover_image_url")
    private String coverImageUrl;
    
    /**
     * 最后爬取时间
     */
    @JsonProperty("last_crawled_at")
    private LocalDateTime lastCrawledAt;
    
    /**
     * 创建时间
     */
    @JsonProperty("created_at")
    private LocalDateTime createdAt;
}



