package com.ainovel.server.service.fanqie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 番茄小说下载任务
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieDownloadTask {
    
    /**
     * 任务ID
     */
    private Long id;
    
    /**
     * 小说ID
     */
    @JsonProperty("novel_id")
    private String novelId;
    
    /**
     * 用户ID
     */
    @JsonProperty("user_id")
    private Long userId;
    
    /**
     * 任务状态：PENDING, DOWNLOADING, PROCESSING, COMPLETED, FAILED, TERMINATED
     */
    private String status;
    
    /**
     * 进度（0-100）
     */
    private Integer progress;
    
    /**
     * 消息
     */
    private String message;
    
    /**
     * Celery任务ID
     */
    @JsonProperty("celery_task_id")
    private String celeryTaskId;
    
    /**
     * 小说信息
     */
    private FanqieNovelInfo novel;
    
    /**
     * 创建时间
     */
    @JsonProperty("created_at")
    private LocalDateTime createdAt;
    
    /**
     * 更新时间
     */
    @JsonProperty("updated_at")
    private LocalDateTime updatedAt;
}



