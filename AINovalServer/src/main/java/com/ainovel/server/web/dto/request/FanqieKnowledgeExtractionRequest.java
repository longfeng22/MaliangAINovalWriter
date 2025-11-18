package com.ainovel.server.web.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import java.util.List;

/**
 * 番茄小说知识提取请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieKnowledgeExtractionRequest {
    
    /**
     * 番茄小说ID
     */
    @NotBlank(message = "番茄小说ID不能为空")
    private String fanqieNovelId;
    
    /**
     * 提取类型列表（为空则使用默认全部类型）
     */
    private List<String> extractionTypes;
}

