package com.ainovel.server.service.impl.content;

import com.ainovel.server.service.impl.content.providers.*;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import lombok.extern.slf4j.Slf4j;

import jakarta.annotation.PostConstruct;

/**
 * 内容提供器配置类
 * 自动注册所有内容提供器
 */
@Slf4j
@Configuration
public class ContentProviderConfiguration {

    @Autowired
    private ContentProviderFactory contentProviderFactory;

    @Autowired
    private FullNovelTextProvider fullNovelTextProvider;

    @Autowired
    private FullNovelSummaryProvider fullNovelSummaryProvider;

    @Autowired
    private ActProvider actProvider;

    @Autowired
    private ChapterProvider chapterProvider;

    @Autowired
    private SceneProvider sceneProvider;

    @Autowired
    private SettingProvider settingProvider;

    @Autowired
    private SnippetProvider snippetProvider;

    @Autowired
    private NovelBasicInfoProvider novelBasicInfoProvider;

    @Autowired
    private RecentChaptersProvider recentChaptersProvider;

    @Autowired
    private RecentChaptersSummaryProvider recentChaptersSummaryProvider;

    @Autowired
    private CurrentChapterContentProvider currentChapterContentProvider;

    @Autowired
    private CurrentSceneContentProvider currentSceneContentProvider;

    @Autowired
    private CurrentChapterSummariesProvider currentChapterSummariesProvider;

    @Autowired
    private PreviousChaptersContentProvider previousChaptersContentProvider;

    @Autowired
    private PreviousChaptersSummaryProvider previousChaptersSummaryProvider;

    @Autowired
    private CurrentSceneSummaryProvider currentSceneSummaryProvider;

    @Autowired
    private AllSettingsProvider allSettingsProvider;

    @PostConstruct
    public void initializeContentProviders() {
        // 注册所有内容提供器
        contentProviderFactory.registerProvider("full_novel_text", fullNovelTextProvider);
        contentProviderFactory.registerProvider("full_novel_summary", fullNovelSummaryProvider);
        contentProviderFactory.registerProvider("novel_basic_info", novelBasicInfoProvider);
        contentProviderFactory.registerProvider("recent_chapters_content", recentChaptersProvider);
        contentProviderFactory.registerProvider("recent_chapters_summary", recentChaptersSummaryProvider);
        // 新增固定类型
        contentProviderFactory.registerProvider("current_chapter_content", currentChapterContentProvider);
        contentProviderFactory.registerProvider("current_scene_content", currentSceneContentProvider);
        contentProviderFactory.registerProvider("current_chapter_summary", currentChapterSummariesProvider);
        contentProviderFactory.registerProvider("current_scene_summary", currentSceneSummaryProvider);
        contentProviderFactory.registerProvider("previous_chapters_content", previousChaptersContentProvider);
        contentProviderFactory.registerProvider("previous_chapters_summary", previousChaptersSummaryProvider);
        contentProviderFactory.registerProvider("act", actProvider);
        contentProviderFactory.registerProvider("chapter", chapterProvider);
        contentProviderFactory.registerProvider("scene", sceneProvider);
        contentProviderFactory.registerProvider("character", settingProvider);
        contentProviderFactory.registerProvider("location", settingProvider);
        contentProviderFactory.registerProvider("item", settingProvider);
        contentProviderFactory.registerProvider("lore", settingProvider);
        contentProviderFactory.registerProvider("snippet", snippetProvider);
        contentProviderFactory.registerProvider("setting_group", settingProvider);
        contentProviderFactory.registerProvider("setting_groups", settingProvider);
        contentProviderFactory.registerProvider("settings_by_type", settingProvider);
        
        // 添加替代映射，支持前端的不同命名方式
        contentProviderFactory.registerProvider("full_outline", fullNovelSummaryProvider);
        contentProviderFactory.registerProvider("acts", actProvider);
        contentProviderFactory.registerProvider("chapters", chapterProvider);
        contentProviderFactory.registerProvider("scenes", sceneProvider);
        contentProviderFactory.registerProvider("settings", settingProvider);
        contentProviderFactory.registerProvider("snippets", snippetProvider);
        // 新增：统一的“全部设定”提供器
        contentProviderFactory.registerProvider("all_settings", allSettingsProvider);
        
        log.info("内容提供器注册完成，可用类型: {}", contentProviderFactory.getAvailableTypes());
    }
} 