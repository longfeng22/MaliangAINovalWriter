package com.ainovel.server.web.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * 番茄小说搜索结果响应DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FanqieSearchResultResponse {
    
    /**
     * 小说列表
     */
    private List<FanqieNovelItem> novels;
    
    /**
     * 番茄小说条目DTO
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class FanqieNovelItem {
        private String novelId;
        private String title;
        private String author;
        private String description;
        private String coverImageUrl;
        private String category;
        private String score;
        private String completionStatus;
        private List<String> tags;
        private Integer chapterCount;
        
        /**
         * 是否已在知识库中缓存
         */
        private Boolean cached;
        
        /**
         * 知识库ID（如果已缓存）
         */
        private String knowledgeBaseId;
    }
}

