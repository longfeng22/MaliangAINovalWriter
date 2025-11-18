package com.ainovel.server.service.fanqie.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说列表查询请求参数
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieNovelListRequest {
    
    /**
     * 页码（默认: 1）
     */
    @Builder.Default
    private Integer page = 1;
    
    /**
     * 每页数量（默认: 10，最大: 50）
     */
    @Builder.Default
    private Integer perPage = 10;
    
    /**
     * 标题搜索（模糊匹配，不区分大小写）
     */
    private String search;
    
    /**
     * 标签筛选（逗号分隔，匹配任意一个）
     */
    private String tags;
    
    /**
     * 状态筛选（如: "连载中", "已完结"）
     */
    private String status;
    
    /**
     * 排序字段（可选值: last_crawled_at, created_at, total_chapters, title）
     * 默认: last_crawled_at
     */
    @Builder.Default
    private String sort = "last_crawled_at";
    
    /**
     * 排序方向（可选值: asc, desc）
     * 默认: desc
     */
    @Builder.Default
    private String order = "desc";
}


