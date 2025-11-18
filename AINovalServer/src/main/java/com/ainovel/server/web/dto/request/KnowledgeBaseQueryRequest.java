package com.ainovel.server.web.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 知识库查询请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeBaseQueryRequest {
    
    /**
     * 搜索关键词
     */
    private String keyword;
    
    /**
     * 来源类型筛选（user_imported=用户导入, fanqie_novel=番茄小说）
     */
    private String sourceType;
    
    /**
     * 标签筛选
     */
    private List<String> tags;
    
    /**
     * 完结状态筛选
     */
    private String completionStatus;
    
    /**
     * 排序字段（likeCount, referenceCount, importTime等）
     */
    @Builder.Default
    private String sortBy = "likeCount";
    
    /**
     * 排序顺序（asc/desc）
     */
    @Builder.Default
    private String sortOrder = "desc";
    
    /**
     * 页码
     */
    @Builder.Default
    private int page = 0;
    
    /**
     * 每页大小
     */
    @Builder.Default
    private int size = 20;
}


