package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 番茄小说下载请求
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieDownloadRequest {
    
    /**
     * 小说ID
     */
    @JsonProperty("novel_id")
    private String novelId;
    
    /**
     * 最大章节数（可选，用于预览）
     */
    @JsonProperty("max_chapters")
    private Integer maxChapters;
}



