package com.ainovel.server.task.dto.knowledge;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 知识提取组任务参数
 * 用于单个提取组（如"文风叙事"、"人物情节"等）
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class KnowledgeExtractionGroupParameters {
    
    /**
     * 组名称（如：文风叙事、人物情节、小说特点等）
     */
    private String groupName;
    
    /**
     * 本组包含的提取类型
     */
    private List<String> extractionTypes;
    
    /**
     * 小说内容
     */
    private String content;
    
    /**
     * 模型配置ID
     */
    private String modelConfigId;
    
    /**
     * 模型类型（user/public）
     */
    private String modelType;
    
    /**
     * 父任务ID
     */
    private String parentTaskId;
    
    /**
     * 章节数量（用于章节大纲提取）
     */
    private Integer chapterCount;
}

