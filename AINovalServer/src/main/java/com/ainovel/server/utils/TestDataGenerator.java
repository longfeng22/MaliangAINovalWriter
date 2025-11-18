package com.ainovel.server.utils;

import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.repository.NovelRepository;
import com.ainovel.server.repository.SceneRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/**
 * 测试数据生成器
 * 用于性能测试时自动生成和清理测试数据
 */
@Slf4j
@Component
@Profile("performance-test")  // ✅ 仅在性能测试环境启用
@RequiredArgsConstructor
public class TestDataGenerator {
    
    private final NovelRepository novelRepository;
    private final SceneRepository sceneRepository;
    
    /**
     * 生成测试数据
     * 
     * @param novelCount 小说数量
     * @param scenesPerNovel 每部小说的场景数
     * @return 生成结果统计
     */
    public Mono<TestDataStats> generateTestData(int novelCount, int scenesPerNovel) {
        log.info("开始生成测试数据: {} 部小说, 每部 {} 个场景", novelCount, scenesPerNovel);
        
        long startTime = System.currentTimeMillis();
        
        return Flux.range(1, novelCount)
            .flatMap(i -> {
                Novel novel = createTestNovel(i);
                
                return novelRepository.save(novel)
                    .flatMap(savedNovel -> {
                        List<Scene> scenes = createTestScenes(savedNovel.getId(), scenesPerNovel);
                        
                        return sceneRepository.saveAll(scenes)
                            .collectList()
                            .map(savedScenes -> 1); // 返回1表示成功处理1部小说
                    });
            }, 10) // 并发度10,加快生成速度
            .reduce(0, Integer::sum)
            .map(totalNovels -> {
                long duration = System.currentTimeMillis() - startTime;
                TestDataStats stats = new TestDataStats(
                    totalNovels,
                    totalNovels * scenesPerNovel,
                    duration
                );
                log.info("✅ 测试数据生成完成: {} 部小说, {} 个场景, 耗时: {}ms", 
                    stats.novelCount, stats.sceneCount, stats.durationMs);
                return stats;
            });
    }
    
    /**
     * 清空所有测试数据
     */
    public Mono<Void> cleanTestData() {
        log.info("开始清空测试数据...");
        
        return novelRepository.deleteAll()
            .then(sceneRepository.deleteAll())
            .doOnSuccess(v -> log.info("✅ 测试数据清空完成"));
    }
    
    /**
     * 清空指定前缀的测试数据
     * 
     * @param prefix ID前缀,例如 "test-novel"
     */
    public Mono<Long> cleanTestDataByPrefix(String prefix) {
        log.info("清空前缀为 {} 的测试数据...", prefix);
        
        return novelRepository.findAll()
            .filter(novel -> novel.getId() != null && novel.getId().startsWith(prefix))
            .flatMap(novel -> novelRepository.delete(novel))
            .count()
            .doOnSuccess(count -> log.info("✅ 删除了 {} 部测试小说", count));
    }
    
    /**
     * 统计当前数据量
     */
    public Mono<TestDataStats> getDataStats() {
        return Mono.zip(
            novelRepository.count(),
            sceneRepository.count()
        ).map(tuple -> new TestDataStats(
            tuple.getT1().intValue(),
            tuple.getT2().intValue(),
            0L
        ));
    }
    
    // ============ 私有方法 ============
    
    /**
     * 创建测试小说
     */
    private Novel createTestNovel(int index) {
        Novel novel = new Novel();
        novel.setId("test-novel-" + index);
        novel.setTitle("性能测试小说 " + index);
        novel.setDescription("这是用于性能测试的小说 #" + index + "。包含多个测试场景。");
        
        // ✅ 修复: genre是List<String>
        novel.setGenre(List.of(getGenre(index)));
        
        // ✅ 修复: author是Author对象
        Novel.Author author = Novel.Author.builder()
            .id("test-author")
            .username("测试作者")
            .build();
        novel.setAuthor(author);
        
        novel.setCreatedAt(LocalDateTime.now());
        novel.setUpdatedAt(LocalDateTime.now());
        novel.setIsReady(true);
        
        // 设置元数据
        Novel.Metadata metadata = Novel.Metadata.builder()
            .wordCount(index * 1000)
            .readTime(index * 10)
            .build();
        novel.setMetadata(metadata);
        
        return novel;
    }
    
    /**
     * 创建测试场景
     */
    private List<Scene> createTestScenes(String novelId, int count) {
        return IntStream.range(1, count + 1)
            .mapToObj(i -> {
                Scene scene = new Scene();
                scene.setId("scene-" + novelId + "-" + i);
                scene.setNovelId(novelId);
                scene.setTitle("场景 " + i);
                scene.setContent(generateSceneContent(i));
                
                // ✅ 修复: Scene使用sequence而不是order
                scene.setSequence(i);
                
                scene.setCreatedAt(LocalDateTime.now());
                scene.setUpdatedAt(LocalDateTime.now());
                return scene;
            })
            .collect(Collectors.toList());
    }
    
    /**
     * 生成场景内容 (500-1000字)
     */
    private String generateSceneContent(int index) {
        StringBuilder content = new StringBuilder();
        content.append("这是测试场景 #").append(index).append(" 的内容。");
        
        // 生成500-1000字的测试内容
        for (int i = 0; i < 50; i++) {
            content.append("这是第").append(i + 1).append("段测试文字。");
            content.append("用于模拟真实的小说场景内容。");
        }
        
        return content.toString();
    }
    
    /**
     * 根据索引返回不同的小说类型
     */
    private String getGenre(int index) {
        String[] genres = {"玄幻", "都市", "科幻", "历史", "武侠", "悬疑"};
        return genres[index % genres.length];
    }
    
    // ============ 内部类 ============
    
    /**
     * 测试数据统计
     */
    public static class TestDataStats {
        public final int novelCount;
        public final int sceneCount;
        public final long durationMs;
        
        public TestDataStats(int novelCount, int sceneCount, long durationMs) {
            this.novelCount = novelCount;
            this.sceneCount = sceneCount;
            this.durationMs = durationMs;
        }
    }
}


