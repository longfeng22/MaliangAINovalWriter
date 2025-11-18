package com.ainovel.server.service.fanqie.dto;

import com.ainovel.server.service.fanqie.dto.FanqieNovelInfo;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 番茄小说搜索结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieSearchResult {
    
    /**
     * 搜索结果列表
     */
    private List<FanqieNovelInfo> results;
}

