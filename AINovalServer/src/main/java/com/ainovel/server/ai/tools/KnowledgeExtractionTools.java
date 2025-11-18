package com.ainovel.server.ai.tools;

import dev.langchain4j.agent.tool.Tool;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;

/**
 * 知识提取工具类
 * 提供给LLM调用的工具方法，用于返回结构化的知识点
 */
@Slf4j
public class KnowledgeExtractionTools {
    
    private final List<KnowledgeSettingResult> extractedSettings = new ArrayList<>();
    private final List<ChapterOutlineResult> extractedOutlines = new ArrayList<>();
    
    /**
     * 添加一个知识设定
     * 
     * @param name 设定名称（5-15字）
     * @param description 设定描述（50-200字）
     * @param tags 相关标签（可选，多个标签用逗号分隔）
     * @return 添加结果
     */
    @Tool("添加一个知识设定。name是设定的简短名称，description是详细描述，tags是相关标签（可选）")
    public String addKnowledgeSetting(String name, String description, String tags) {
        log.info("添加知识设定: name={}, descLength={}", name, description.length());
        
        if (name == null || name.trim().isEmpty()) {
            return "失败：设定名称不能为空";
        }
        
        if (description == null || description.trim().isEmpty()) {
            return "失败：设定描述不能为空";
        }
        
        List<String> tagList = new ArrayList<>();
        if (tags != null && !tags.trim().isEmpty()) {
            String[] tagArray = tags.split("[,，]");
            for (String tag : tagArray) {
                String trimmed = tag.trim();
                if (!trimmed.isEmpty()) {
                    tagList.add(trimmed);
                }
            }
        }
        
        KnowledgeSettingResult setting = KnowledgeSettingResult.builder()
                .name(name.trim())
                .description(description.trim())
                .tags(tagList)
                .build();
        
        extractedSettings.add(setting);
        
        return String.format("成功添加设定：%s（已添加 %d 个设定）", 
                name, extractedSettings.size());
    }
    
    /**
     * 添加章节大纲
     * 
     * @param chapterTitle 章节标题
     * @param summary 章节概要
     * @param order 章节顺序（从1开始）
     * @return 添加结果
     */
    @Tool("添加一个章节大纲。chapterTitle是章节标题，summary是章节概要，order是章节顺序号")
    public String addChapterOutline(String chapterTitle, String summary, int order) {
        log.info("添加章节大纲: chapter={}, order={}", chapterTitle, order);
        
        if (chapterTitle == null || chapterTitle.trim().isEmpty()) {
            return "失败：章节标题不能为空";
        }
        
        if (summary == null || summary.trim().isEmpty()) {
            return "失败：章节概要不能为空";
        }
        
        if (order < 1) {
            return "失败：章节顺序必须从1开始";
        }
        
        ChapterOutlineResult outline = ChapterOutlineResult.builder()
                .chapterTitle(chapterTitle.trim())
                .summary(summary.trim())
                .order(order)
                .build();
        
        extractedOutlines.add(outline);
        
        return String.format("成功添加章节大纲：第%d章 %s（已添加 %d 章）", 
                order, chapterTitle, extractedOutlines.size());
    }
    
    /**
     * 获取所有提取的设定
     */
    public List<KnowledgeSettingResult> getExtractedSettings() {
        return new ArrayList<>(extractedSettings);
    }
    
    /**
     * 获取所有提取的章节大纲
     */
    public List<ChapterOutlineResult> getExtractedOutlines() {
        return new ArrayList<>(extractedOutlines);
    }
    
    /**
     * 清空提取结果
     */
    public void clear() {
        extractedSettings.clear();
        extractedOutlines.clear();
    }
    
    /**
     * 知识设定结果
     */
    @lombok.Data
    @lombok.Builder
    @lombok.NoArgsConstructor
    @lombok.AllArgsConstructor
    public static class KnowledgeSettingResult {
        private String name;
        private String description;
        private List<String> tags;
    }
    
    /**
     * 章节大纲结果
     */
    @lombok.Data
    @lombok.Builder
    @lombok.NoArgsConstructor
    @lombok.AllArgsConstructor
    public static class ChapterOutlineResult {
        private String chapterTitle;
        private String summary;
        private Integer order;
    }
}


