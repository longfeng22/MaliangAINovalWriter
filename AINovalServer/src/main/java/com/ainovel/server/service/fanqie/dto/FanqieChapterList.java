package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 番茄小说章节列表
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieChapterList {
    
    /**
     * 章节列表
     */
    private List<FanqieChapter> chapters;
    
    /**
     * 总数
     */
    private Integer total;
    
    /**
     * 当前页
     */
    private Integer page;
    
    /**
     * 每页数量
     */
    @JsonProperty("per_page")
    private Integer perPage;
    
    /**
     * 总页数
     */
    private Integer pages;
    
    /**
     * 小说ID
     */
    @JsonProperty("novel_id")
    private String novelId;
}



