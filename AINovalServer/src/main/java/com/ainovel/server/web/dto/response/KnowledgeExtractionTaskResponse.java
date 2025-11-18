package com.ainovel.server.web.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 知识提取任务响应DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeExtractionTaskResponse {
    
    /**
     * 任务ID
     */
    private String taskId;
    
    /**
     * 任务状态
     */
    private String status;
    
    /**
     * 知识库ID
     */
    private String knowledgeBaseId;
    
    /**
     * 进度（0-100）
     */
    private Integer progress;
    
    /**
     * 消息
     */
    private String message;
    
    /**
     * 开始时间
     * ✅ 使用ISO 8601格式序列化时间
     */
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss")
    private LocalDateTime startTime;
    
    /**
     * 预计完成时间
     * ✅ 使用ISO 8601格式序列化时间
     */
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss")
    private LocalDateTime estimatedCompletionTime;
}

