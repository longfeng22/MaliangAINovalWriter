package com.ainovel.server.web.dto.response;

import com.ainovel.server.domain.model.NovelSettingItem;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * 知识库详情响应DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KnowledgeBaseDetailResponse {
    
    private String id;
    private String title;
    private String description;
    private String coverImageUrl;
    private String author;
    private List<String> tags;
    private String completionStatus;
    
    private Integer likeCount;
    private Integer referenceCount;
    private Integer viewCount;
    private Boolean isLiked;
    
    private LocalDateTime importTime;
    
    // 各类型设定
    private List<SettingItemDto> narrativeStyleSettings;
    private List<SettingItemDto> characterPlotSettings;
    private List<SettingItemDto> novelFeatureSettings;
    private List<SettingItemDto> hotMemesSettings;
    private List<SettingItemDto> customSettings;
    private List<SettingItemDto> readerEmotionSettings;
    
    // 章节大纲
    private List<ChapterOutlineDto> chapterOutlines;
    
    /**
     * 设定条目DTO
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class SettingItemDto {
        private String id;
        private String name;
        private String description;
        private String type;
        private Map<String, String> attributes;
        private List<String> tags;
    }
    
    /**
     * 章节大纲DTO
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ChapterOutlineDto {
        private String chapterId;
        private String title;
        private String summary;
        private Integer order;
    }
    
    /**
     * 从NovelSettingItem转换为SettingItemDto
     */
    public static SettingItemDto fromNovelSettingItem(NovelSettingItem item) {
        if (item == null) {
            return null;
        }
        return SettingItemDto.builder()
                .id(item.getId())
                .name(item.getName())
                .description(item.getDescription())
                .type(item.getType())
                .attributes(item.getAttributes())
                .tags(item.getTags())
                .build();
    }
}


