package com.ainovel.server.service.prompt;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.prompt.providers.AIChatPromptProvider;
import com.ainovel.server.service.prompt.providers.NovelGenerationPromptProvider;
import com.ainovel.server.service.prompt.providers.ProfessionalFictionPromptProvider;
import com.ainovel.server.service.prompt.providers.SceneBeatGenerationPromptProvider;
import com.ainovel.server.service.prompt.providers.SceneToSummaryPromptProvider;
import com.ainovel.server.service.prompt.providers.SummaryToScenePromptProvider;
import com.ainovel.server.service.prompt.providers.TextExpansionPromptProvider;
import com.ainovel.server.service.prompt.providers.TextRefactorPromptProvider;
import com.ainovel.server.service.prompt.providers.TextSummaryPromptProvider;
import com.ainovel.server.service.prompt.providers.SettingTreeGenerationPromptProvider;
import com.ainovel.server.service.prompt.providers.NovelComposePromptProvider;
import com.ainovel.server.service.prompt.providers.StoryPlotContinuationPromptProvider;

import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;

/**
 * 提示词提供器工厂
 * 管理所有AI功能的提示词提供器
 */
@Slf4j
@Component
public class PromptProviderFactory {

    private final Map<AIFeatureType, AIFeaturePromptProvider> providers = new ConcurrentHashMap<>();

    @Autowired
    private TextExpansionPromptProvider textExpansionPromptProvider;

    @Autowired
    private AIChatPromptProvider aiChatPromptProvider;

    @Autowired
    private TextRefactorPromptProvider textRefactorPromptProvider;
    
    @Autowired
    private TextSummaryPromptProvider textSummaryPromptProvider;
    
    @Autowired
    private ProfessionalFictionPromptProvider professionalFictionPromptProvider;

    @Autowired
    private SceneToSummaryPromptProvider sceneToSummaryPromptProvider;

    @Autowired
    private SummaryToScenePromptProvider summaryToScenePromptProvider;

    @Autowired
    private NovelGenerationPromptProvider novelGenerationPromptProvider;

    @Autowired
    private SceneBeatGenerationPromptProvider sceneBeatGenerationPromptProvider;

    @Autowired
    private SettingTreeGenerationPromptProvider settingTreeGenerationPromptProvider;

    @Autowired
    private NovelComposePromptProvider novelComposePromptProvider;

    @Autowired
    private StoryPlotContinuationPromptProvider storyPlotContinuationPromptProvider;

    @PostConstruct
    public void initializeProviders() {
        // 注册所有提示词提供器
        registerProvider(textExpansionPromptProvider);
        registerProvider(aiChatPromptProvider);
        registerProvider(textRefactorPromptProvider);
        registerProvider(textSummaryPromptProvider);
        registerProvider(professionalFictionPromptProvider);
        registerProvider(sceneToSummaryPromptProvider);
        registerProvider(summaryToScenePromptProvider);
        registerProvider(novelGenerationPromptProvider);
        registerProvider(sceneBeatGenerationPromptProvider);
        registerProvider(settingTreeGenerationPromptProvider);
        registerProvider(novelComposePromptProvider);
        registerProvider(storyPlotContinuationPromptProvider);
        
        log.info("提示词提供器注册完成，可用类型: {}", providers.keySet());
    }

    /**
     * 注册提示词提供器
     */
    public void registerProvider(AIFeaturePromptProvider provider) {
        AIFeatureType featureType = provider.getFeatureType();
        providers.put(featureType, provider);
        log.info("注册提示词提供器: {} -> {}", featureType, provider.getClass().getSimpleName());
    }

    /**
     * 获取指定功能类型的提示词提供器
     */
    public AIFeaturePromptProvider getProvider(AIFeatureType featureType) {
        AIFeaturePromptProvider provider = providers.get(featureType);
        if (provider == null) {
            log.warn("未找到功能类型 {} 的提示词提供器", featureType);
        }
        return provider;
    }

    /**
     * 获取所有注册的提示词提供器
     */
    public List<AIFeaturePromptProvider> getAllProviders() {
        return List.copyOf(providers.values());
    }

    /**
     * 检查是否存在指定功能类型的提示词提供器
     */
    public boolean hasProvider(AIFeatureType featureType) {
        return providers.containsKey(featureType);
    }

    /**
     * 获取所有支持的功能类型
     */
    public java.util.Set<AIFeatureType> getSupportedFeatureTypes() {
        return providers.keySet();
    }

    /**
     * 获取指定功能类型支持的占位符
     */
    public java.util.Set<String> getSupportedPlaceholders(AIFeatureType featureType) {
        AIFeaturePromptProvider provider = getProvider(featureType);
        return provider != null ? provider.getSupportedPlaceholders() : java.util.Set.of();
    }
} 