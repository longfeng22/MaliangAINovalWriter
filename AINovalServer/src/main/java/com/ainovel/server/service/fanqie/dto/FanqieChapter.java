package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说章节信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieChapter {
    
    /**
     * 章节ID
     */
    private String id;
    
    /**
     * 小说ID
     */
    @JsonProperty("novel_id")
    private String novelId;
    
    /**
     * 章节索引
     */
    private Integer index;
    
    /**
     * 章节标题
     */
    private String title;
    
    /**
     * 章节内容
     */
    private String content;
}



