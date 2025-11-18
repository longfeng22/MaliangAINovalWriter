package com.ainovel.server.task.dto.knowledge;

import com.ainovel.server.domain.model.NovelSettingItem;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 知识提取组任务结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class KnowledgeExtractionGroupResult {
    
    /**
     * 组名称
     */
    private String groupName;
    
    /**
     * 提取的设定列表
     */
    private List<NovelSettingItem> settings;
    
    /**
     * 是否成功
     */
    private boolean success;
    
    /**
     * 错误信息（如果失败）
     */
    private String errorMessage;
    
    /**
     * 使用的Token数
     */
    private Long tokensUsed;
}


