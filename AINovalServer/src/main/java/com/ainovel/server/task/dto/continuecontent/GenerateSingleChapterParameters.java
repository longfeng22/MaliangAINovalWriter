package com.ainovel.server.task.dto.continuecontent;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class GenerateSingleChapterParameters {
    private String novelId;
    private int chapterIndex; // 1-based index of the chapter to generate within this task run
    private String currentContext; // Context for generating the summary
    private String aiConfigIdSummary;
    private String aiConfigIdContent;
    private String writingStyle; // Optional writing style prompt
    private int totalChapters; // Total chapters requested by the parent task
    private boolean requiresReview; // Flag for review step
    private String parentTaskId; // Keep track of the parent
    private boolean persistChanges; // Added field
    // Optional prompt template IDs
    private String summaryPromptTemplateId;
    private String contentPromptTemplateId;
    // Optional: public model config IDs
    private String summaryPublicModelConfigId;
    private String contentPublicModelConfigId;
} 