package com.ainovel.server.web.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 章节详情DTO
 * 用于拆书任务中传递章节的完整信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ChapterDetailDto {
    
    /**
     * 章节索引（从1开始）
     */
    private Integer index;
    
    /**
     * 章节ID（用于关联）
     */
    private String chapterId;
    
    /**
     * 章节标题
     */
    private String title;
    
    /**
     * 章节内容
     */
    private String content;
    
    /**
     * 字数统计
     */
    private Integer wordCount;
}

