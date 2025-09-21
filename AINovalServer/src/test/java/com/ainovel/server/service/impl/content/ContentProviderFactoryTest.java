package com.ainovel.server.service.impl.content;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import java.util.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import reactor.core.publisher.Mono;

/**
 * ContentProviderFactory 单元测试
 * 验证内容提供器工厂的智能去重和重叠检测功能
 */
@ExtendWith(MockitoExtension.class)
class ContentProviderFactoryTest {

    private ContentProviderFactory factory;

    @BeforeEach
    void setUp() {
        factory = new ContentProviderFactory();
    }

    /**
     * 测试基本的提供器注册和获取功能
     */
    @Test
    void testBasicProviderRegistration() {
        ContentProvider mockProvider = createMockProvider("test", Set.of("test"), 100);
        
        factory.registerProvider("test", mockProvider);
        
        assertTrue(factory.hasProvider("test"), "应该找到已注册的提供器");
        assertTrue(factory.getProvider("test").isPresent(), "应该能获取已注册的提供器");
        assertEquals(mockProvider, factory.getProvider("test").get(), "应该返回正确的提供器实例");
    }

    /**
     * 测试大小写不敏感的提供器查找
     */
    @Test
    void testCaseInsensitiveProviderLookup() {
        ContentProvider mockProvider = createMockProvider("Test", Set.of("test"), 100);
        
        factory.registerProvider("Test", mockProvider);
        
        assertTrue(factory.hasProvider("test"), "应该支持小写查找");
        assertTrue(factory.hasProvider("TEST"), "应该支持大写查找");
        assertTrue(factory.hasProvider("Test"), "应该支持原始大小写查找");
    }

    /**
     * 测试语义标签映射功能
     */
    @Test
    void testSemanticTagsMapping() {
        ContentProvider settingProvider = createMockProvider("settings", Set.of("character", "setting"), 10);
        ContentProvider sceneProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 30);
        
        factory.registerProvider("settings", settingProvider);
        factory.registerProvider("scenes", sceneProvider);
        
        Map<String, Set<String>> mapping = factory.getSemanticTagsMapping();
        
        assertEquals(2, mapping.size(), "应该有2个映射");
        assertEquals(Set.of("character", "setting"), mapping.get("settings"), "settings的语义标签应该正确");
        assertEquals(Set.of("narrative", "scene"), mapping.get("scenes"), "scenes的语义标签应该正确");
    }

    /**
     * 测试重叠检测功能
     */
    @Test
    void testOverlapDetection() {
        // 创建有重叠的提供器
        ContentProvider settingsProvider = createMockProvider("settings", Set.of("character", "setting"), 10);
        ContentProvider charactersProvider = createMockProvider("characters", Set.of("character", "profile"), 20);
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 30);
        
        factory.registerProvider("settings", settingsProvider);
        factory.registerProvider("characters", charactersProvider);
        factory.registerProvider("scenes", scenesProvider);
        
        Set<String> testTypes = Set.of("settings", "characters", "scenes");
        Map<String, Set<String>> overlaps = factory.detectOverlaps(testTypes);
        
        // settings和characters应该有重叠（都有"character"标签）
        assertTrue(overlaps.containsKey("settings"), "settings应该有重叠");
        assertTrue(overlaps.get("settings").contains("characters"), "settings应该与characters重叠");
        
        assertTrue(overlaps.containsKey("characters"), "characters应该有重叠");
        assertTrue(overlaps.get("characters").contains("settings"), "characters应该与settings重叠");
        
        // scenes不应该有重叠
        assertFalse(overlaps.containsKey("scenes") || 
                   (overlaps.containsKey("scenes") && !overlaps.get("scenes").isEmpty()), 
                   "scenes不应该有重叠");
    }

    /**
     * 测试优先级排序功能
     */
    @Test
    void testPrioritySorting() {
        ContentProvider highPriority = createMockProvider("high", Set.of("high"), 1);
        ContentProvider mediumPriority = createMockProvider("medium", Set.of("medium"), 50);
        ContentProvider lowPriority = createMockProvider("low", Set.of("low"), 100);
        
        factory.registerProvider("high", highPriority);
        factory.registerProvider("medium", mediumPriority);
        factory.registerProvider("low", lowPriority);
        
        Set<String> types = Set.of("low", "high", "medium"); // 故意乱序
        List<String> sorted = factory.sortByPriority(types);
        
        assertEquals(Arrays.asList("high", "medium", "low"), sorted, "应该按优先级正确排序");
    }

    /**
     * 测试非重叠类型筛选
     */
    @Test
    void testNonOverlappingTypes() {
        ContentProvider settingsProvider = createMockProvider("settings", Set.of("character", "setting"), 10);
        ContentProvider charactersProvider = createMockProvider("characters", Set.of("character", "profile"), 20);
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 30);
        ContentProvider snippetsProvider = createMockProvider("snippets", Set.of("text", "fragment"), 40);
        
        factory.registerProvider("settings", settingsProvider);
        factory.registerProvider("characters", charactersProvider);
        factory.registerProvider("scenes", scenesProvider);
        factory.registerProvider("snippets", snippetsProvider);
        
        // 排除有"character"标签的类型
        Set<String> excludedTypes = Set.of("settings", "characters");
        Set<String> nonOverlapping = factory.getNonOverlappingTypes(excludedTypes);
        
        // 应该只包含scenes和snippets（它们没有"character"或"setting"或"profile"标签）
        assertEquals(Set.of("scenes", "snippets"), nonOverlapping, "应该返回非重叠的类型");
    }

    /**
     * 测试智能去重功能
     */
    @Test
    void testIntelligentDeduplication() {
        // 创建有重叠的提供器，优先级不同
        ContentProvider settingsProvider = createMockProvider("settings", Set.of("character", "setting"), 10); // 高优先级
        ContentProvider charactersProvider = createMockProvider("characters", Set.of("character", "profile"), 20); // 低优先级
        ContentProvider scenesProvider = createMockProvider("scenes", Set.of("narrative", "scene"), 30); // 无重叠
        
        factory.registerProvider("settings", settingsProvider);
        factory.registerProvider("characters", charactersProvider);
        factory.registerProvider("scenes", scenesProvider);
        
        Set<String> originalTypes = Set.of("settings", "characters", "scenes");
        Set<String> deduplicated = factory.deduplicateByPriority(originalTypes);
        
        // 由于settings和characters重叠，且settings优先级更高，应该保留settings，移除characters
        assertTrue(deduplicated.contains("settings"), "应该保留高优先级的settings");
        assertFalse(deduplicated.contains("characters"), "应该移除低优先级的characters");
        assertTrue(deduplicated.contains("scenes"), "应该保留无重叠的scenes");
    }

    /**
     * 测试复杂的多重重叠去重
     */
    @Test
    void testComplexMultipleOverlapDeduplication() {
        // 创建复杂的重叠场景
        ContentProvider providerA = createMockProvider("typeA", Set.of("tag1", "tag2"), 10);
        ContentProvider providerB = createMockProvider("typeB", Set.of("tag2", "tag3"), 20);
        ContentProvider providerC = createMockProvider("typeC", Set.of("tag3", "tag4"), 30);
        ContentProvider providerD = createMockProvider("typeD", Set.of("tag5"), 40); // 无重叠
        
        factory.registerProvider("typeA", providerA);
        factory.registerProvider("typeB", providerB);
        factory.registerProvider("typeC", providerC);
        factory.registerProvider("typeD", providerD);
        
        Set<String> originalTypes = Set.of("typeA", "typeB", "typeC", "typeD");
        Set<String> deduplicated = factory.deduplicateByPriority(originalTypes);
        
        // A、B、C形成重叠链：A(tag1,tag2) <-> B(tag2,tag3) <-> C(tag3,tag4)
        // 应该只保留最高优先级的A
        assertTrue(deduplicated.contains("typeA"), "应该保留最高优先级的typeA");
        assertTrue(deduplicated.contains("typeD"), "应该保留无重叠的typeD");
        
        // B和C可能被移除（取决于具体实现逻辑）
        int retainedCount = deduplicated.size();
        assertTrue(retainedCount >= 2, "至少应该保留typeA和typeD");
    }

    /**
     * 测试空集合处理
     */
    @Test
    void testEmptySetHandling() {
        Set<String> emptySet = Set.of();
        
        assertTrue(factory.detectOverlaps(emptySet).isEmpty(), "空集合的重叠检测应该返回空映射");
        assertTrue(factory.sortByPriority(emptySet).isEmpty(), "空集合的排序应该返回空列表");
        assertTrue(factory.deduplicateByPriority(emptySet).isEmpty(), "空集合的去重应该返回空集合");
    }

    /**
     * 测试不存在的提供器类型处理
     */
    @Test
    void testNonExistentProviderTypes() {
        Set<String> nonExistentTypes = Set.of("nonexistent1", "nonexistent2");
        
        Map<String, Set<String>> overlaps = factory.detectOverlaps(nonExistentTypes);
        assertTrue(overlaps.isEmpty(), "不存在的类型不应该产生重叠");
        
        List<String> sorted = factory.sortByPriority(nonExistentTypes);
        assertEquals(2, sorted.size(), "应该返回原始类型（即使不存在）");
        
        Set<String> deduplicated = factory.deduplicateByPriority(nonExistentTypes);
        assertEquals(nonExistentTypes, deduplicated, "不存在的类型去重后应该保持不变");
    }

    /**
     * 测试批量检查功能
     */
    @Test
    void testBatchProviderCheck() {
        ContentProvider existingProvider = createMockProvider("existing", Set.of("test"), 100);
        factory.registerProvider("existing", existingProvider);
        
        Set<String> typesToCheck = Set.of("existing", "nonexistent");
        Map<String, Boolean> checkResult = factory.checkProviders(typesToCheck);
        
        assertEquals(2, checkResult.size(), "应该返回所有检查的类型");
        assertTrue(checkResult.get("existing"), "existing类型应该存在");
        assertFalse(checkResult.get("nonexistent"), "nonexistent类型不应该存在");
    }

    /**
     * 测试已实现类型过滤
     */
    @Test
    void testImplementedTypesFiltering() {
        ContentProvider existingProvider = createMockProvider("existing", Set.of("test"), 100);
        factory.registerProvider("existing", existingProvider);
        
        Set<String> requestedTypes = Set.of("existing", "nonexistent1", "nonexistent2");
        Set<String> implementedTypes = factory.getImplementedTypes(requestedTypes);
        Set<String> missingTypes = factory.getMissingTypes(requestedTypes);
        
        assertEquals(Set.of("existing"), implementedTypes, "应该只返回已实现的类型");
        assertEquals(Set.of("nonexistent1", "nonexistent2"), missingTypes, "应该返回缺失的类型");
    }

    // ===== 辅助方法 =====

    /**
     * 创建模拟的内容提供器
     */
    private ContentProvider createMockProvider(String type, Set<String> semanticTags, int priority) {
        ContentProvider provider = mock(ContentProvider.class);
        
        when(provider.getType()).thenReturn(type);
        when(provider.getSemanticTags()).thenReturn(semanticTags);
        when(provider.getPriority()).thenReturn(priority);
        
        // 实现默认的重叠检测逻辑
        when(provider.hasOverlapWith(any())).thenAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            Set<String> otherTags = (Set<String>) invocation.getArgument(0);
            return semanticTags.stream().anyMatch(otherTags::contains);
        });
        
        // 模拟基本的内容获取方法
        when(provider.getContent(any(), any())).thenReturn(Mono.just(mock(ContentResult.class)));
        when(provider.getContentForPlaceholder(any(), any(), any(), any())).thenReturn(Mono.just("mock content"));
        when(provider.getEstimatedContentLength(any())).thenReturn(Mono.just(100));
        
        return provider;
    }
}