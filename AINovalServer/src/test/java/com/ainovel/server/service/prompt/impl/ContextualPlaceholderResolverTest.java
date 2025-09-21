package com.ainovel.server.service.prompt.impl;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.util.*;
import java.util.concurrent.ThreadLocalRandom;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.ainovel.server.service.impl.content.ContentProviderFactory;
import com.ainovel.server.service.impl.content.ContentProvider;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;

import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

/**
 * ContextualPlaceholderResolver 单元测试
 * 验证专用占位符和通用占位符的协调处理逻辑
 */
@ExtendWith(MockitoExtension.class)
class ContextualPlaceholderResolverTest {

    @Mock
    private ContentProviderFactory contentProviderFactory;

    @Mock
    private ContentProviderPlaceholderResolver delegateResolver;

    @InjectMocks
    private ContextualPlaceholderResolver contextualResolver;

    private String userId;
    private String novelId;
    private Map<String, Object> parameters;

    @BeforeEach
    void setUp() {
        userId = "test-user-" + ThreadLocalRandom.current().nextInt(1000);
        novelId = "test-novel-" + ThreadLocalRandom.current().nextInt(1000);
        parameters = new HashMap<>();
    }

    /**
     * 测试专用占位符优先处理，{{context}}不包含重复内容
     */
    @Test
    void testSpecializedPlaceholdersPriority() {
        // 准备测试模板
        String template = "角色设定：{{settings}}\n\n故事片段：{{snippets}}\n\n完整上下文：{{context}}";
        
        // 模拟前端传递的上下文选择
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = Arrays.asList(
            createContextSelection("setting_1", "角色设定", "settings"),
            createContextSelection("snippet_1", "故事片段", "snippets"),
            createContextSelection("scene_1", "场景内容", "scenes")
        );
        parameters.put("contextSelections", contextSelections);

        // 模拟专用占位符解析结果
        when(delegateResolver.resolvePlaceholder(eq("settings"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.just("主角：张三，性格：勇敢"));
        
        when(delegateResolver.resolvePlaceholder(eq("snippets"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.just("张三走进了神秘的森林"));

        // 模拟内容提供器 - 只需要为{{context}}占位符用到的providers添加模拟
        // settings和snippets通过专用占位符处理，不需要ContentProvider
        ContentProvider sceneProvider = mock(ContentProvider.class);
        
        when(contentProviderFactory.getProvider("scenes")).thenReturn(Optional.of(sceneProvider));
        
        // 只有场景内容会通过{{context}}占位符调用ContentProvider
        when(sceneProvider.getContentForPlaceholder(eq(userId), eq(novelId), eq("scene_1"), any()))
            .thenReturn(Mono.just("场景详细描述：夜晚的森林充满了神秘感"));

        // 执行测试
        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                System.out.println("=== 测试结果调试 ===");
                System.out.println("完整结果：\n" + result);
                System.out.println("==================");
                // 验证专用占位符被正确替换
                assertTrue(result.contains("主角：张三，性格：勇敢"), "settings占位符应该被替换");
                assertTrue(result.contains("张三走进了神秘的森林"), "snippets占位符应该被替换");
                
                // 验证{{context}}只包含场景内容，不包含已通过专用占位符处理的设定和片段
                assertTrue(result.contains("场景详细描述：夜晚的森林充满了神秘感"), "context应该包含场景内容");
                
                // 在context部分不应该再次出现设定和片段内容，只应该包含场景内容
                String[] parts = result.split("完整上下文：");
                if (parts.length > 1) {
                    String contextPart = parts[1];
                    // context应该只包含场景内容，排除已被专用占位符处理的settings和snippets
                    assertFalse(contextPart.contains("设定内容：主角是勇敢的战士"), "context不应该重复包含settings内容");
                    assertFalse(contextPart.contains("片段内容：冒险开始了"), "context不应该重复包含snippets内容");
                    assertTrue(contextPart.contains("场景详细描述：夜晚的森林充满了神秘感"), "context应该包含未被专用占位符处理的场景内容");
                }
                
                return true;
            })
            .verifyComplete();
    }

    /**
     * 测试只有{{context}}占位符时的标准行为
     */
    @Test
    void testContextPlaceholderOnly() {
        String template = "请基于以下上下文生成内容：{{context}}";
        
        // 模拟上下文选择
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = Arrays.asList(
            createContextSelection("scene_1", "场景1", "scenes"),
            createContextSelection("character_1", "角色1", "characters")
        );
        parameters.put("contextSelections", contextSelections);

        // 模拟内容提供器
        ContentProvider sceneProvider = mock(ContentProvider.class);
        ContentProvider characterProvider = mock(ContentProvider.class);
        
        when(contentProviderFactory.getProvider("scenes")).thenReturn(Optional.of(sceneProvider));
        when(contentProviderFactory.getProvider("characters")).thenReturn(Optional.of(characterProvider));
        
        when(sceneProvider.getContentForPlaceholder(eq(userId), eq(novelId), eq("scene_1"), any()))
            .thenReturn(Mono.just("森林中的小屋"));
        when(characterProvider.getContentForPlaceholder(eq(userId), eq(novelId), eq("character_1"), any()))
            .thenReturn(Mono.just("勇敢的骑士"));

        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                assertTrue(result.contains("森林中的小屋"), "应该包含场景内容");
                assertTrue(result.contains("勇敢的骑士"), "应该包含角色内容");
                return true;
            })
            .verifyComplete();
    }

    /**
     * 测试空模板处理
     */
    @Test
    void testEmptyTemplate() {
        StepVerifier.create(contextualResolver.resolveTemplate("", parameters, userId, novelId))
            .expectNext("")
            .verifyComplete();
            
        StepVerifier.create(contextualResolver.resolveTemplate(null, parameters, userId, novelId))
            .expectNext("")
            .verifyComplete();
    }

    /**
     * 测试无占位符模板
     */
    @Test
    void testTemplateWithoutPlaceholders() {
        String template = "这是一个没有占位符的模板";
        
        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNext(template)
            .verifyComplete();
    }

    /**
     * 测试专用占位符标识
     */
    @Test
    void testSpecializedPlaceholderIdentification() {
        assertTrue(contextualResolver.supports("settings"), "应该支持settings占位符");
        assertTrue(contextualResolver.supports("snippets"), "应该支持snippets占位符");
        assertTrue(contextualResolver.supports("context"), "应该支持context占位符");
        
        // 模拟delegate resolver的行为
        when(delegateResolver.supports("other")).thenReturn(false);
        assertFalse(contextualResolver.supports("other"), "不应该支持未知占位符");
    }

    /**
     * 测试错误处理
     */
    @Test
    void testErrorHandling() {
        String template = "测试：{{settings}}，上下文：{{context}}";
        
        // 模拟专用占位符解析失败
        when(delegateResolver.resolvePlaceholder(eq("settings"), any(), eq(userId), eq(novelId)))
            .thenReturn(Mono.error(new RuntimeException("解析失败")));

        // 应该能处理错误并继续处理其他占位符
        StepVerifier.create(contextualResolver.resolveTemplate(template, parameters, userId, novelId))
            .expectNextMatches(result -> {
                // 即使settings解析失败，context部分仍应正常处理
                assertTrue(result.contains("上下文："), "context占位符应该被处理");
                return true;
            })
            .verifyError();
    }

    /**
     * 测试线程安全性 - 并发解析不同模板
     */
    @Test
    void testThreadSafety() {
        String template1 = "模板1：{{settings}}";
        String template2 = "模板2：{{snippets}}";
        
        when(delegateResolver.resolvePlaceholder(eq("settings"), any(), any(), any()))
            .thenReturn(Mono.just("设定内容"));
        when(delegateResolver.resolvePlaceholder(eq("snippets"), any(), any(), any()))
            .thenReturn(Mono.just("片段内容"));

        // 并发执行
        Mono<String> result1 = contextualResolver.resolveTemplate(template1, parameters, userId, novelId);
        Mono<String> result2 = contextualResolver.resolveTemplate(template2, parameters, "other-user", "other-novel");
        
        StepVerifier.create(Mono.zip(result1, result2))
            .expectNextMatches(tuple -> {
                String r1 = tuple.getT1();
                String r2 = tuple.getT2();
                return r1.contains("设定内容") && r2.contains("片段内容");
            })
            .verifyComplete();
    }

    // ===== 辅助方法 =====

    /**
     * 创建模拟的上下文选择DTO
     */
    private UniversalAIRequestDto.ContextSelectionDto createContextSelection(String id, String title, String type) {
        return UniversalAIRequestDto.ContextSelectionDto.builder()
            .id(id)
            .title(title)
            .type(type)
            .metadata(new HashMap<>())
            .build();
    }
}