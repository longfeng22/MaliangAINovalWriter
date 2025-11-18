package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;

import com.ainovel.server.common.exception.ResourceNotFoundException;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.domain.model.Scene.HistoryEntry;
import com.ainovel.server.domain.model.SceneVersionDiff;
import com.ainovel.server.repository.SceneRepository;
import com.ainovel.server.service.IndexingService;
import com.ainovel.server.service.MetadataService;
import com.ainovel.server.service.SceneService;
import com.github.difflib.DiffUtils;
import com.github.difflib.UnifiedDiffUtils;
import com.github.difflib.patch.Patch;

import lombok.RequiredArgsConstructor;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;

import com.ainovel.server.domain.model.User;

/**
 * 场景服务实现
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SceneServiceImpl implements SceneService {

    private final SceneRepository sceneRepository;
    private final MetadataService metadataService;
    private final com.ainovel.server.service.analytics.WritingAnalyticsService writingAnalyticsService;

    @Lazy
    @Autowired
    private IndexingService indexingService;

    @Override
    public Mono<Scene> findSceneById(String id) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .map(this::ensureQuillFormat);  // 🔥 读取时也确保格式正确
    }

    @Override
    public Mono<Scene> getSceneById(String id) {
        // 简化版findSceneById，保持一致
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .map(this::ensureQuillFormat);  // 🔥 读取时也确保格式正确
    }
    
    /**
     * 确保场景内容是Quill Delta JSON格式
     * 用于读取时的格式保护，防止旧的纯文本数据被返回给前端
     */
    private Scene ensureQuillFormat(Scene scene) {
        if (scene == null || scene.getContent() == null || scene.getContent().isEmpty()) {
            return scene;
        }
        
        // 检查content是否是Quill格式
        if (!com.ainovel.server.common.util.RichTextUtil.isQuillDeltaJson(scene.getContent())) {
            // 不是Quill格式，需要转换
            String originalContent = scene.getContent();
            String quillContent = com.ainovel.server.common.util.RichTextUtil.plainTextToDeltaJson(originalContent);
            scene.setContent(quillContent);
            
            log.warn("⚠️ 检测到场景内容不是Quill格式，已自动转换。场景ID: {}, 原始长度: {}, 转换后长度: {}", 
                    scene.getId(), originalContent.length(), quillContent.length());
            
            // 🔥 关键：异步更新数据库，修复这条脏数据
            sceneRepository.save(scene)
                    .doOnSuccess(saved -> log.info("✅ 已自动修复数据库中的场景格式。场景ID: {}", scene.getId()))
                    .doOnError(error -> log.error("❌ 自动修复场景格式失败。场景ID: {}, 错误: {}", scene.getId(), error.getMessage()))
                    .subscribe();  // 异步执行，不阻塞当前请求
        }
        
        return scene;
    }

    @Override
    public Flux<Scene> findSceneByChapterId(String chapterId) {
        return sceneRepository.findByChapterId(chapterId)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Flux<Scene> findSceneByChapterIdOrdered(String chapterId) {
        return sceneRepository.findByChapterIdOrderBySequenceAsc(chapterId)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Flux<Scene> findScenesByNovelId(String novelId) {
        return sceneRepository.findByNovelId(novelId)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Flux<Scene> findScenesByNovelIdOrdered(String novelId) {
        return sceneRepository.findByNovelIdOrderByChapterIdAscSequenceAsc(novelId)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Flux<Scene> findScenesByChapterIds(List<String> chapterIds) {
        return sceneRepository.findByChapterIdIn(chapterIds)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Flux<Scene> findScenesByNovelIdAndType(String novelId, String sceneType) {
        return sceneRepository.findByNovelIdAndSceneType(novelId, sceneType)
                .map(this::ensureQuillFormat);  // 🔥 读取时确保格式
    }

    @Override
    public Mono<Scene> createScene(Scene scene) {
        // 设置创建和更新时间
        scene.setCreatedAt(LocalDateTime.now());
        scene.setUpdatedAt(LocalDateTime.now());

        // 设置初始版本
        scene.setVersion(1);

        // 使用元数据服务更新场景元数据（包括字数统计）
        final Scene updatedScene = metadataService.updateSceneMetadata(scene);

        // 如果没有设置序号，查找当前章节的最后一个场景序号并加1
        if (updatedScene.getSequence() == null) {
            return sceneRepository.findByChapterIdOrderBySequenceAsc(updatedScene.getChapterId())
                    .collectList()
                    .flatMap(scenes -> {
                        // 如果章节中没有场景，则序号为0
                        if (scenes.isEmpty()) {
                            updatedScene.setSequence(0);
                        } else {
                            // 获取最大序号并加1
                            int maxSequence = scenes.stream()
                                    .mapToInt(Scene::getSequence)
                                    .max()
                                    .orElse(-1);
                            updatedScene.setSequence(maxSequence + 1);
                        }
                        return sceneRepository.save(updatedScene)
                                .doOnSuccess(savedScene -> {
                                    // 异步触发小说元数据更新
                                    metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                                });
                    });
        }

        return sceneRepository.save(updatedScene)
                .doOnSuccess(savedScene -> {
                    // 异步触发小说元数据更新
                    metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                    // 记录写作事件（新建场景，delta=after-0）
                    try {
                        int after = savedScene.getWordCount() != null ? savedScene.getWordCount() : 0;
                        ReactiveSecurityContextHolder.getContext()
                            .map(ctx -> ctx.getAuthentication())
                            .map(this::extractUserId)
                            .defaultIfEmpty("system")
                            .flatMap(uid -> writingAnalyticsService.recordEvent(
                                com.ainovel.server.domain.model.analytics.WritingEvent.builder()
                                    .userId(uid)
                                    .novelId(savedScene.getNovelId())
                                    .chapterId(savedScene.getChapterId())
                                    .sceneId(savedScene.getId())
                                    .wordCountBefore(0)
                                    .wordCountAfter(after)
                                    .deltaWords(after)
                                    .source("MANUAL")
                                    .reason("createScene")
                                    .timestamp(LocalDateTime.now())
                                    .build()
                            )).subscribe();
                    } catch (Exception ignore) {}
                });
    }

    @Override
    public Flux<Scene> createScenes(List<Scene> scenes) {
        if (scenes.isEmpty()) {
            return Flux.empty();
        }

        // 设置创建和更新时间以及初始版本
        LocalDateTime now = LocalDateTime.now();
        scenes.forEach(scene -> {
            scene.setCreatedAt(now);
            scene.setUpdatedAt(now);
            scene.setVersion(1);
            // 使用元数据服务更新每个场景的元数据
            metadataService.updateSceneMetadata(scene);
        });

        // 按章节ID分组
        Map<String, List<Scene>> scenesByChapter = scenes.stream()
                .collect(Collectors.groupingBy(Scene::getChapterId));

        // 处理每个章节的场景
        List<Flux<Scene>> fluxes = new ArrayList<>();

        for (Map.Entry<String, List<Scene>> entry : scenesByChapter.entrySet()) {
            String chapterId = entry.getKey();
            List<Scene> chapterScenes = entry.getValue();

            // 获取章节中现有场景的最大序列号，然后设置新场景的序列号
            Flux<Scene> flux = sceneRepository.findByChapterIdOrderBySequenceAsc(chapterId)
                    .collectList()
                    .flatMapMany(existingScenes -> {
                        int nextSequence = 0;

                        if (!existingScenes.isEmpty()) {
                            // 获取当前章节中最大的序列号
                            nextSequence = existingScenes.stream()
                                    .mapToInt(Scene::getSequence)
                                    .max()
                                    .orElse(-1) + 1;
                        }

                        // 为每个新场景设置序列号（除非已设置）
                        for (Scene scene : chapterScenes) {
                            if (scene.getSequence() == null) {
                                scene.setSequence(nextSequence++);
                            }
                        }

                        return sceneRepository.saveAll(chapterScenes)
                                .doOnNext(savedScene -> {
                                    // 对每个保存的场景异步触发小说元数据更新
                                    metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                                });
                    });

            fluxes.add(flux);
        }

        return Flux.concat(fluxes);
    }

    @Override
    public Mono<Scene> updateScene(String id, Scene scene) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(existingScene -> {
                    // 保留原始ID和创建时间
                    scene.setId(existingScene.getId());
                    scene.setCreatedAt(existingScene.getCreatedAt());

                    // 更新版本和更新时间
                    scene.setVersion(existingScene.getVersion() + 1);
                    scene.setUpdatedAt(LocalDateTime.now());

                    // 如果没有设置小说ID或章节ID，使用原有的
                    if (scene.getNovelId() == null) {
                        scene.setNovelId(existingScene.getNovelId());
                    }
                    if (scene.getChapterId() == null) {
                        scene.setChapterId(existingScene.getChapterId());
                    }

                    // 如果没有设置序号，使用原有的
                    if (scene.getSequence() == null) {
                        scene.setSequence(existingScene.getSequence());
                    }

                    // 使用元数据服务更新场景元数据（包括字数统计）
                    final Scene updatedScene = metadataService.updateSceneMetadata(scene);
                    final Scene finalExistingScene = existingScene;

                    // 在更新场景时，检查内容是否发生变化
                    if (!Objects.equals(finalExistingScene.getContent(), updatedScene.getContent())) {
                        // 如果内容发生变化，添加历史记录
                        HistoryEntry historyEntry = new HistoryEntry();
                        historyEntry.setUpdatedAt(LocalDateTime.now());
                        historyEntry.setContent(finalExistingScene.getContent());
                        historyEntry.setUpdatedBy("system");
                        historyEntry.setReason("内容更新");

                        // 复制现有历史记录并添加新记录
                        if (updatedScene.getHistory() == null) {
                            updatedScene.setHistory(new ArrayList<>());
                        }
                        updatedScene.getHistory().addAll(finalExistingScene.getHistory());
                        updatedScene.getHistory().add(historyEntry);
                    } else {
                        // 如果内容没变，保留原有历史记录
                        updatedScene.setHistory(finalExistingScene.getHistory());
                    }

                    // 保存更新后的场景
                    return sceneRepository.save(updatedScene)
                            .doOnSuccess(savedScene -> {
                                // 异步触发小说元数据更新
                                metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                                // 若内容变化，记录写作事件
                                try {
                                    boolean contentChanged = !Objects.equals(finalExistingScene.getContent(), updatedScene.getContent());
                                    if (contentChanged) {
                                        int before = metadataService.calculateWordCount(finalExistingScene.getContent());
                                        int after = savedScene.getWordCount() != null ? savedScene.getWordCount() : metadataService.calculateWordCount(savedScene.getContent());
                                        int delta = after - before;
                                        ReactiveSecurityContextHolder.getContext()
                                            .map(ctx -> ctx.getAuthentication())
                                            .map(this::extractUserId)
                                            .defaultIfEmpty("system")
                                            .flatMap(uid -> writingAnalyticsService.recordEvent(
                                                com.ainovel.server.domain.model.analytics.WritingEvent.builder()
                                                    .userId(uid)
                                                    .novelId(savedScene.getNovelId())
                                                    .chapterId(savedScene.getChapterId())
                                                    .sceneId(savedScene.getId())
                                                    .wordCountBefore(before)
                                                    .wordCountAfter(after)
                                                    .deltaWords(delta)
                                                    .source("MANUAL")
                                                    .reason("updateScene")
                                                    .timestamp(LocalDateTime.now())
                                                    .build()
                                            )).subscribe();
                                    }
                                } catch (Exception ignore) {}
                            });
                });
    }

    @Override
    public Mono<Scene> upsertScene(Scene scene) {
        // 如果场景ID为空，则创建新场景
        if (scene.getId() == null || scene.getId().isEmpty()) {
            return createScene(scene);
        }

        // 否则尝试更新，如果不存在则创建
        return sceneRepository.findById(scene.getId())
                .flatMap(existingScene -> updateScene(existingScene.getId(), scene))
                .switchIfEmpty(createScene(scene));
    }

    @Override
    public Flux<Scene> upsertScenes(List<Scene> scenes) {
        return Flux.fromIterable(scenes)
                .flatMap(this::upsertScene);
    }

    @Override
    public Mono<Void> deleteScene(String id) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    String novelId = scene.getNovelId();
                    return sceneRepository.delete(scene)
                            .then(Mono.defer(() -> {
                                // 触发小说元数据更新（如果有novelId）
                                if (novelId != null && !novelId.isEmpty()) {
                                    return metadataService.updateNovelMetadata(novelId).then();
                                }
                                return Mono.empty();
                            }));
                });
    }

    @Override
    public Mono<Void> deleteScenesByNovelId(String novelId) {
        return sceneRepository.deleteByNovelId(novelId);
    }

    @Override
    public Mono<Void> deleteScenesByChapterId(String chapterId) {
        // 首先获取章节的场景列表，记录novelId
        return sceneRepository.findByChapterId(chapterId)
                .collectList()
                .flatMap(scenes -> {
                    if (scenes.isEmpty()) {
                        return Mono.empty();
                    }

                    // 获取novelId用于后续更新元数据
                    String novelId = scenes.get(0).getNovelId();

                    return sceneRepository.deleteByChapterId(chapterId)
                            .then(Mono.defer(() -> {
                                // 触发小说元数据更新
                                if (novelId != null && !novelId.isEmpty()) {
                                    return metadataService.updateNovelMetadata(novelId).then();
                                }
                                return Mono.empty();
                            }));
                });
    }

    @Override
    public Mono<Scene> updateSceneContent(String id, String content, String userId, String reason) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    // 🔥 关键修复：检查并转换content格式
                    String quillContent;
                    if (com.ainovel.server.common.util.RichTextUtil.isQuillDeltaJson(content)) {
                        // 已经是Quill格式，直接使用
                        quillContent = content;
                    } else {
                        // 纯文本格式，需要转换为Quill格式
                        quillContent = com.ainovel.server.common.util.RichTextUtil.plainTextToDeltaJson(content);
                        log.info("更新场景内容: 纯文本已转换为Quill Delta JSON格式。场景ID: {}", id);
                    }
                    
                    // 如果内容没有变化，直接返回
                    if (scene.getContent() != null && scene.getContent().equals(quillContent)) {
                        return Mono.just(scene);
                    }

                    // 保存当前内容到历史
                    HistoryEntry entry = new HistoryEntry();
                    entry.setUpdatedAt(LocalDateTime.now());
                    entry.setContent(scene.getContent());
                    entry.setUpdatedBy(userId);
                    entry.setReason(reason != null ? reason : "修改内容");

                    // 确保历史记录存在
                    if (scene.getHistory() == null) {
                        scene.setHistory(new ArrayList<>());
                    }

                    // 添加历史记录
                    scene.getHistory().add(entry);

                    // 更新内容和版本
                    scene.setContent(quillContent);
                    scene.setVersion(scene.getVersion() + 1);
                    scene.setUpdatedAt(LocalDateTime.now());

                    // 使用元数据服务更新场景字数（基于纯文本）
                    String plainText = com.ainovel.server.common.util.RichTextUtil.deltaJsonToPlainText(quillContent);
                    final int wordCount = plainText.length();
                    scene.setWordCount(wordCount);

                    final Scene updatedScene = scene;

                    // 保存到数据库
                    return sceneRepository.save(updatedScene)
                            .flatMap(savedScene -> {
                                // 触发场景索引
                                return indexingService.indexScene(savedScene)
                                        .thenReturn(savedScene);
                            })
                            .doOnSuccess(savedScene -> {
                                // 异步触发小说元数据更新
                                metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                                try {
                                    // 记录写作事件
                                    com.ainovel.server.domain.model.analytics.WritingEvent event =
                                        com.ainovel.server.domain.model.analytics.WritingEvent.builder()
                                            .userId(userId)
                                            .novelId(savedScene.getNovelId())
                                            .chapterId(savedScene.getChapterId())
                                            .sceneId(savedScene.getId())
                                            .wordCountBefore(scene.getWordCount())
                                            .wordCountAfter(savedScene.getWordCount())
                                            .deltaWords((savedScene.getWordCount() != null ? savedScene.getWordCount() : 0)
                                                - (scene.getWordCount() != null ? scene.getWordCount() : 0))
                                            .source("MANUAL")
                                            .reason(reason)
                                            .timestamp(java.time.LocalDateTime.now())
                                            .build();
                                    writingAnalyticsService.recordEvent(event).subscribe();
                                } catch (Exception ignore) {}
                            });
                });
    }

    @Override
    public Mono<Scene> updateSceneContent(String id, String content, String userId) {
        // 简化版，使用默认原因调用四参数版本
        return updateSceneContent(id, content, userId, "修改内容");
    }

    @Override
    public Mono<List<HistoryEntry>> getSceneHistory(String id) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .map(Scene::getHistory);
    }

    @Override
    public Mono<Scene> restoreSceneVersion(String id, int historyIndex, String userId, String reason) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    List<HistoryEntry> history = scene.getHistory();

                    // 检查历史索引是否有效
                    if (historyIndex < 0 || historyIndex >= history.size()) {
                        return Mono.error(new IllegalArgumentException("无效的历史版本索引: " + historyIndex));
                    }

                    // 获取历史版本内容
                    final String historyContent = history.get(historyIndex).getContent();

                    // 添加当前版本到历史记录
                    HistoryEntry currentVersion = new HistoryEntry();
                    currentVersion.setContent(scene.getContent());
                    currentVersion.setUpdatedAt(LocalDateTime.now());
                    currentVersion.setUpdatedBy(userId);
                    currentVersion.setReason("恢复版本前的备份: " + reason);
                    history.add(currentVersion);

                    // 更新内容、版本和时间
                    scene.setContent(historyContent);
                    scene.setVersion(scene.getVersion() + 1);
                    scene.setUpdatedAt(LocalDateTime.now());

                    // 使用元数据服务更新场景字数
                    scene.setWordCount(metadataService.calculateWordCount(historyContent));

                    final Scene updatedScene = scene;

                    // 添加恢复记录
                    HistoryEntry restoreEntry = new HistoryEntry();
                    restoreEntry.setContent(null); // 不存储内容，因为就是当前版本
                    restoreEntry.setUpdatedAt(LocalDateTime.now());
                    restoreEntry.setUpdatedBy(userId);
                    restoreEntry.setReason("恢复到历史版本 #" + (historyIndex + 1) + ": " + reason);
                    history.add(restoreEntry);

                    return sceneRepository.save(updatedScene)
                            .doOnSuccess(savedScene -> {
                                // 异步触发小说元数据更新
                                metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                            });
                });
    }

    @Override
    public Mono<Scene> updateSummary(String id, String summaryText) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    // 更新摘要
                    if (summaryText != null) {
                        scene.setSummary(summaryText);
                    }

                    // 更新场景
                    scene.setUpdatedAt(LocalDateTime.now());
                    return sceneRepository.save(scene);
                });
    }

    @Override
    public Mono<Scene> updateSceneSummary(String id, String summary, String userId) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    // 如果摘要没有变化，直接返回
                    if (scene.getSummary() != null && scene.getSummary().equals(summary)) {
                        return Mono.just(scene);
                    }

                    // 更新摘要
                    scene.setSummary(summary);
                    scene.setUpdatedAt(LocalDateTime.now());
                    scene.setVersion(scene.getVersion() + 1);

                    // 保存到数据库
                    return sceneRepository.save(scene)
                            .doOnSuccess(savedScene -> {
                                // 异步更新索引
                                indexingService.indexScene(savedScene).subscribe();
                            });
                });
    }

    @Override
    public Mono<Scene> addScene(String novelId, String chapterId, String title, String summaryText, String content, Integer position) {
        // 创建新场景
        Scene newScene = new Scene();
        newScene.setId(UUID.randomUUID().toString());
        newScene.setNovelId(novelId);
        newScene.setChapterId(chapterId);
        newScene.setTitle(title);
        
        // 设置场景内容：如果提供了content则使用，否则使用空Quill格式
        if (content != null && !content.trim().isEmpty()) {
            // 🔥 关键修复：检查content是否已经是Quill Delta JSON格式
            String quillContent;
            if (com.ainovel.server.common.util.RichTextUtil.isQuillDeltaJson(content)) {
                // 已经是Quill格式，直接使用
                quillContent = content;
                log.debug("场景内容已经是Quill Delta JSON格式，直接使用");
            } else {
                // 纯文本格式，需要转换为Quill格式
                quillContent = com.ainovel.server.common.util.RichTextUtil.plainTextToDeltaJson(content);
                log.info("场景内容是纯文本，已转换为Quill Delta JSON格式。原始长度: {}, 转换后长度: {}", 
                        content.length(), quillContent.length());
            }
            
            newScene.setContent(quillContent);
            // 计算实际的纯文本字数（不包括JSON格式字符）
            String plainText = com.ainovel.server.common.util.RichTextUtil.deltaJsonToPlainText(quillContent);
            newScene.setWordCount(plainText.length());
        } else {
            newScene.setContent("[{\"insert\":\"\\n\"}]"); // 初始内容为标准空Quill格式
            newScene.setWordCount(0); // 初始字数为0
        }
        
        newScene.setCreatedAt(LocalDateTime.now());
        newScene.setUpdatedAt(LocalDateTime.now());
        newScene.setVersion(1);
        newScene.setSummary(summaryText);

        if (position != null) {
            newScene.setSequence(position);
            return createScene(newScene);
        } else {
            // 查找当前章节中最大的场景序号
            return sceneRepository.findByChapterIdOrderBySequenceAsc(chapterId)
                    .collectList()
                    .flatMap(scenes -> {
                        int sequence = 0;
                        if (!scenes.isEmpty()) {
                            sequence = scenes.stream()
                                    .mapToInt(Scene::getSequence)
                                    .max()
                                    .orElse(-1) + 1;
                        }
                        newScene.setSequence(sequence);
                        return createScene(newScene);
                    });
        }
    }

    @Override
    public Mono<SceneVersionDiff> compareSceneVersions(String id, int versionIndex1, int versionIndex2) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .map(scene -> {
                    List<HistoryEntry> history = scene.getHistory();

                    // 获取版本1的内容
                    String content1;
                    if (versionIndex1 == -1) {
                        // -1表示当前版本
                        content1 = scene.getContent();
                    } else {
                        if (versionIndex1 < 0 || versionIndex1 >= history.size()) {
                            throw new IllegalArgumentException("无效的历史版本索引1: " + versionIndex1);
                        }
                        content1 = history.get(versionIndex1).getContent();
                    }

                    // 获取版本2的内容
                    String content2;
                    if (versionIndex2 == -1) {
                        // -1表示当前版本
                        content2 = scene.getContent();
                    } else {
                        if (versionIndex2 < 0 || versionIndex2 >= history.size()) {
                            throw new IllegalArgumentException("无效的历史版本索引2: " + versionIndex2);
                        }
                        content2 = history.get(versionIndex2).getContent();
                    }

                    // 使用DiffUtils计算差异
                    List<String> originalLines = Arrays.asList(content1.split("\n"));
                    List<String> revisedLines = Arrays.asList(content2.split("\n"));

                    // 计算差异
                    Patch<String> patch = DiffUtils.diff(originalLines, revisedLines);

                    // 生成统一差异格式
                    List<String> unifiedDiff = UnifiedDiffUtils.generateUnifiedDiff(
                            "原始版本", "修改版本", originalLines, patch, 3);

                    // 创建并返回差异对象
                    SceneVersionDiff diff = new SceneVersionDiff();
                    diff.setOriginalContent(content1);
                    diff.setNewContent(content2);
                    diff.setDiff(String.join("\n", unifiedDiff));

                    return diff;
                });
    }

    @Override
    public Mono<Boolean> deleteSceneById(String id) {
        return sceneRepository.findById(id)
                .flatMap(scene -> sceneRepository.delete(scene)
                        .thenReturn(true))
                .defaultIfEmpty(false);
    }

    @Override
    public Mono<Scene> updateSceneWordCount(String id, Integer wordCount) {
        return sceneRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + id)))
                .flatMap(scene -> {
                    scene.setWordCount(wordCount);
                    scene.setUpdatedAt(LocalDateTime.now());
                    return sceneRepository.save(scene)
                            .doOnSuccess(savedScene -> {
                                // 异步触发小说元数据更新
                                metadataService.triggerNovelMetadataUpdate(savedScene).subscribe();
                            });
                });
    }

    private String extractUserId(Authentication authentication) {
        if (authentication == null || authentication.getPrincipal() == null) {
            return "system";
        }
        Object principal = authentication.getPrincipal();
        if (principal instanceof User user) {
            return user.getId();
        }
        if (principal instanceof org.springframework.security.core.userdetails.User springUser) {
            return springUser.getUsername();
        }
        return principal.toString();
    }

    @Override
    public Mono<List<Scene>> updateScenesBatch(List<Scene> scenes) {
        if (scenes == null || scenes.isEmpty()) {
            return Mono.just(new ArrayList<>());
        }
        
        LocalDateTime now = LocalDateTime.now();
        
        return Flux.fromIterable(scenes)
                .flatMap(scene -> {
                    // 获取现有场景
                    return sceneRepository.findById(scene.getId())
                            .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景不存在: " + scene.getId())))
                            .flatMap(existingScene -> {
                                // 保留原始创建时间和版本
                                scene.setCreatedAt(existingScene.getCreatedAt());
                                scene.setVersion(existingScene.getVersion());
                                
                                // 设置更新时间
                                scene.setUpdatedAt(now);
                                
                                // 保存更新后的场景
                                return sceneRepository.save(scene);
                            });
                })
                .collectList()
                .doOnSuccess(savedScenes -> {
                    // 如果有相同小说的场景，只触发一次元数据更新
                    savedScenes.stream()
                            .map(Scene::getNovelId)
                            .distinct()
                            .forEach(novelId -> {
                                if (novelId != null && !novelId.isEmpty()) {
                                    // 使用现有的触发小说元数据更新方法
                                    // 创建一个假场景对象来触发更新
                                    Scene dummyScene = new Scene();
                                    dummyScene.setNovelId(novelId);
                                    metadataService.triggerNovelMetadataUpdate(dummyScene).subscribe();
                                }
                            });
                });
    }


}
