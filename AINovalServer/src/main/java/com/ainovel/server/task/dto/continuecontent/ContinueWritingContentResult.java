package com.ainovel.server.task.dto.continuecontent;

import com.ainovel.server.task.model.TaskStatus;
import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import lombok.Data;

import java.util.List;

/**
 * 自动续写小说章节内容任务结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ContinueWritingContentResult {
    
    /**
     * 生成的章节列表
     */
    private List<String> newChapterIds;
    
    /**
     * 成功生成的摘要数量
     */
    private int summariesGeneratedCount;
    
    /**
     * 成功生成的内容数量
     */
    private int contentGeneratedCount;
    
    /**
     * 失败的章节数量
     */
    private int failedChaptersCount;
    
    /**
     * 任务最终状态
     */
    private TaskStatus status;
    
    /**
     * 最后一次错误信息（如果有）
     */
    private String lastErrorMessage;
} 