package com.ainovel.server.web.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import java.util.List;

/**
 * 用户文本知识提取请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TextKnowledgeExtractionRequest {
    
    /**
     * 小说标题
     */
    @NotBlank(message = "标题不能为空")
    private String title;
    
    /**
     * 小说内容
     */
    @NotBlank(message = "内容不能为空")
    private String content;
    
    /**
     * 小说简介
     */
    private String description;
    
    /**
     * 提取类型列表
     */
    @NotEmpty(message = "提取类型不能为空")
    private List<String> extractionTypes;
    
    /**
     * 模型配置ID
     */
    @NotBlank(message = "模型配置ID不能为空")
    private String modelConfigId;
    
    /**
     * 模型类型（public/user）
     */
    @NotBlank(message = "模型类型不能为空")
    private String modelType;
    
    /**
     * 章节数量（用于章节大纲提取）
     */
    private Integer chapterCount;
    
    /**
     * 预览会话ID（用于获取已解析的章节详情）
     */
    private String previewSessionId;
}

