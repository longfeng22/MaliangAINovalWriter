package com.ainovel.server.web.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 知识库列表响应DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeBaseListResponse {
    
    /**
     * 知识库卡片列表
     */
    private List<KnowledgeBaseCard> items;
    
    /**
     * 总数量
     */
    private Integer totalCount;
    
    /**
     * 页码
     */
    private Integer page;
    
    /**
     * 每页大小
     */
    private Integer size;
    
    /**
     * 知识库卡片DTO
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class KnowledgeBaseCard {
        private String id;
        private String title;
        private String description;
        private String coverImageUrl;
        private String author;
        private List<String> tags;
        private Integer likeCount;
        private Integer referenceCount;
        private Integer viewCount;
        private LocalDateTime importTime;
        private String completionStatus;
        private Boolean isUserImported; // 是否为用户导入
        private String fanqieNovelId; // 番茄小说ID
    }
}


