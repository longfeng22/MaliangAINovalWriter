package com.ainovel.server.web.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import java.util.List;

/**
 * 从预览会话提取知识库请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PreviewSessionExtractionRequest {
    
    /**
     * 预览会话ID
     */
    @NotBlank(message = "预览会话ID不能为空")
    private String previewSessionId;
    
    /**
     * 小说标题
     */
    @NotBlank(message = "标题不能为空")
    private String title;
    
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
     * 章节限制（null表示整本，否则为前N章）
     */
    private Integer chapterLimit;
}


