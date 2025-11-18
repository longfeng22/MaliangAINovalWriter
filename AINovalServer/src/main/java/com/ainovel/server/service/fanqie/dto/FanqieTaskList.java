package com.ainovel.server.service.fanqie.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 番茄小说任务列表
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieTaskList {
    
    /**
     * 任务列表
     */
    private List<FanqieDownloadTask> tasks;
}



