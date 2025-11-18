package com.ainovel.server.service.fanqie.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说列表筛选条件
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieNovelListFilters {
    
    /**
     * 标题搜索关键词
     */
    private String search;
    
    /**
     * 标签筛选
     */
    private String tags;
    
    /**
     * 状态筛选
     */
    private String status;
    
    /**
     * 排序字段
     */
    private String sort;
    
    /**
     * 排序方向
     */
    private String order;
}


