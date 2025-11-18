package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 番茄小说列表响应
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieNovelListResponse {
    
    /**
     * 小说列表
     */
    private List<FanqieNovelDetail> novels;
    
    /**
     * 总数
     */
    private Integer total;
    
    /**
     * 当前页码
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
     * 当前应用的筛选条件
     */
    private FanqieNovelListFilters filters;
}


