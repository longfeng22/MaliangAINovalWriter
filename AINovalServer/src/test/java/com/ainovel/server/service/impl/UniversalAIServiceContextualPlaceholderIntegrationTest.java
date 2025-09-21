package com.ainovel.server.service.impl;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.util.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.ainovel.server.service.impl.content.ContentProviderFactory;
import com.ainovel.server.service.impl.content.ContentProvider;
import com.ainovel.server.service.prompt.impl.ContextualPlaceholderResolver;
import com.ainovel.server.service.prompt.impl.ContentProviderPlaceholderResolver;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;

import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

/**
 * 上下文占位符去重功能集成测试
 * 验证专用占位符和{{context}}占位符的协调工作
 */
@ExtendWith(MockitoExtension.class)
class UniversalAIServiceContextualPlaceholderIntegrationTest {

    @Mock
    private ContentProviderFactory contentProviderFactory;
    
    @Mock
    private ContentProviderPlaceholderResolver delegateResolver;
    
    private ContextualPlaceholderResolver contextualResolver;
    
    private String userId = "test-user";
    private String novelId = "test-novel";

    @BeforeEach
    void setUp() {
        contextualResolver = new ContextualPlaceholderResolver();
        // 通过反射设置私有字段进行测试
        try {
            var factoryField = ContextualPlaceholderResolver.class.getDeclaredField("contentProviderFactory");
            factoryField.setAccessible(true);
            factoryField.set(contextualResolver, contentProviderFactory);
            
            var delegateField = ContextualPlaceholderResolver.class.getDeclaredField("delegateResolver");
            delegateField.setAccessible(true);
            delegateField.set(contextualResolver, delegateResolver);
        } catch (Exception e) {
            throw new RuntimeException("Failed to setup test", e);
        }
    }

    /**
     * 场景1：用户选择了snippets，模板同时包含{{snippets}}和{{context}}
     * 期望：{{snippets}}填充片段内容，{{context}}只包含其他类型的内容
     */
    @Test
    void testSnippetsAndContextSeparation() {
        // 准备模板
        String template = "参考片段：{{snippets}}\n\n补充上下文：{{context}}";
        
        // 准备参数和上下文选择
        Map<String, Object> parameters = new HashMap<>();
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = Arrays.asList(
            createContextSelection("snippet_1", "测试片段", "snippets"),
            createContextSelection("scene_1", "测试场景", "scenes")
        );
        parameters.put("contextSelections", contextSelections);

        // 模拟专用占位符解析
        when(delegateResolver.resolvePlaceholder(eq("snippets"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.just("这是一个重要的故事片段"));

        // 模拟内容提供器
        ContentProvider snippetsProvider = createMockProvider("snippets", Set.of("snippet", "text"), 10);
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 20);
        
        when(contentProviderFactory.getProvider("snippets")).thenReturn(Optional.of(snippetsProvider));
        when(contentProviderFactory.getProvider("scenes")).thenReturn(Optional.of(scenesProvider));
        
        when(scenesProvider.getContentForPlaceholder(userId, novelId, "scene_1", parameters))
            .thenReturn(Mono.just("夜晚的森林场景"));

        // 执行测试
        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                // 验证snippets占位符被正确填充
                assertTrue(result.contains("参考片段：这是一个重要的故事片段"), 
                          "snippets占位符应该被正确替换");
                
                // 验证context只包含场景内容，不包含片段内容
                assertTrue(result.contains("补充上下文：夜晚的森林场景"), 
                          "context应该包含场景内容");
                
                // 验证没有重复内容
                String contextPart = result.substring(result.indexOf("补充上下文："));
                assertFalse(contextPart.contains("重要的故事片段"), 
                           "context不应该重复包含snippets内容");
                           
                return true;
            })
            .verifyComplete();
    }

    /**
     * 场景2：用户同时选择了多种类型，模板包含部分专用占位符和{{context}}
     * 期望：专用占位符优先处理，{{context}}排除已处理的类型
     */
    @Test
    void testMultipleSpecializedPlaceholdersWithContext() {
        String template = "角色：{{settings}}\n内容：{{context}}\n指导：{{instructions}}";
        
        Map<String, Object> parameters = new HashMap<>();
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = Arrays.asList(
            createContextSelection("setting_1", "主角设定", "settings"),
            createContextSelection("snippet_1", "故事片段", "snippets"),
            createContextSelection("scene_1", "当前场景", "scenes")
        );
        parameters.put("contextSelections", contextSelections);
        parameters.put("instructions", "请创作一个吸引人的故事");

        // 模拟专用占位符解析
        when(delegateResolver.resolvePlaceholder(eq("settings"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.just("主角是一位年轻的法师"));
        when(delegateResolver.resolvePlaceholder(eq("instructions"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.just("请创作一个吸引人的故事"));

        // 模拟内容提供器
        ContentProvider settingsProvider = createMockProvider("settings", Set.of("character", "setting"), 5);
        ContentProvider snippetsProvider = createMockProvider("snippets", Set.of("snippet", "text"), 10);
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 15);
        
        when(contentProviderFactory.getProvider("settings")).thenReturn(Optional.of(settingsProvider));
        when(contentProviderFactory.getProvider("snippets")).thenReturn(Optional.of(snippetsProvider));
        when(contentProviderFactory.getProvider("scenes")).thenReturn(Optional.of(scenesProvider));
        
        when(snippetsProvider.getContentForPlaceholder(userId, novelId, "snippet_1", parameters))
            .thenReturn(Mono.just("魔法森林的冒险"));
        when(scenesProvider.getContentForPlaceholder(userId, novelId, "scene_1", parameters))
            .thenReturn(Mono.just("阳光透过树叶洒向大地"));

        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                // 验证专用占位符被正确处理
                assertTrue(result.contains("角色：主角是一位年轻的法师"), 
                          "settings占位符应该被正确处理");
                assertTrue(result.contains("指导：请创作一个吸引人的故事"), 
                          "instructions占位符应该被正确处理");
                
                // 验证context包含snippets和scenes，但不包含settings
                String[] parts = result.split("内容：");
                if (parts.length > 1) {
                    String contextPart = parts[1].split("指导：")[0];
                    assertTrue(contextPart.contains("魔法森林的冒险"), 
                              "context应该包含snippets内容");
                    assertTrue(contextPart.contains("阳光透过树叶洒向大地"), 
                              "context应该包含scenes内容");
                    assertFalse(contextPart.contains("年轻的法师"), 
                               "context不应该重复包含settings内容");
                }
                
                return true;
            })
            .verifyComplete();
    }

    /**
     * 场景3：只有{{context}}占位符，验证标准行为
     */
    @Test
    void testContextOnlyBehavior() {
        String template = "基于以下背景创作故事：{{context}}";
        
        Map<String, Object> parameters = new HashMap<>();
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = Arrays.asList(
            createContextSelection("snippet_1", "开头", "snippets"),
            createContextSelection("scene_1", "场景", "scenes")
        );
        parameters.put("contextSelections", contextSelections);

        // 模拟内容提供器
        ContentProvider snippetsProvider = createMockProvider("snippets", Set.of("snippet"), 10);
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("scene"), 20);
        
        when(contentProviderFactory.getProvider("snippets")).thenReturn(Optional.of(snippetsProvider));
        when(contentProviderFactory.getProvider("scenes")).thenReturn(Optional.of(scenesProvider));
        
        when(snippetsProvider.getContentForPlaceholder(userId, novelId, "snippet_1", parameters))
            .thenReturn(Mono.just("从前有一个魔法王国"));
        when(scenesProvider.getContentForPlaceholder(userId, novelId, "scene_1", parameters))
            .thenReturn(Mono.just("王宫大厅金碧辉煌"));

        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                assertTrue(result.contains("从前有一个魔法王国"), "应该包含snippets内容");
                assertTrue(result.contains("王宫大厅金碧辉煌"), "应该包含scenes内容");
                return true;
            })
            .verifyComplete();
    }

    // ===== 辅助方法 =====

    private UniversalAIRequestDto.ContextSelectionDto createContextSelection(String id, String title, String type) {
        return UniversalAIRequestDto.ContextSelectionDto.builder()
            .id(id)
            .title(title)
            .type(type)
            .metadata(new HashMap<>())
            .build();
    }

    private ContentProvider createMockProvider(String type, Set<String> semanticTags, int priority) {
        ContentProvider provider = mock(ContentProvider.class);
        
        when(provider.getType()).thenReturn(type);
        when(provider.getSemanticTags()).thenReturn(semanticTags);
        when(provider.getPriority()).thenReturn(priority);
        
        when(provider.hasOverlapWith(any())).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            Set<String> otherTags = (Set<String>) invocation.getArgument(0);
            return semanticTags.stream().anyMatch(otherTags::contains);
        });
        
        return provider;
    }
}