package com.ainovel.server.task.dto.continuecontent;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class GenerateSingleChapterResult implements Serializable {
    /**
     * 归属小说ID，便于前端定位与聚合
     */
    private String novelId;

    private String generatedChapterId;
    private String generatedInitialSceneId;
    private String generatedSummary;
    /**
     * 本次生成的正文内容（persist=false 时通过事件直接下发，避免前端再查库拉空）
     */
    private String generatedContent;
    private boolean contentGenerated;
    private boolean contentPersisted;
    private int chapterIndex;
    
    /**
     * 生成摘要使用的模型名称
     */
    private String summaryModelName;
    
    /**
     * 生成内容使用的模型名称
     */
    private String contentModelName;
    
    // Optional: Add content snippet if needed, but might be large
} 