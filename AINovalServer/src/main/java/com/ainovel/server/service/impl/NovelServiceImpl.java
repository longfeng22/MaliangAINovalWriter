package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import com.ainovel.server.common.util.PromptUtil;
import com.ainovel.server.common.util.RichTextUtil;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;

import com.ainovel.server.common.exception.ResourceNotFoundException;
import com.ainovel.server.domain.model.Character;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Novel.Act;
import com.ainovel.server.domain.model.Novel.Chapter;
import com.ainovel.server.domain.model.Novel.Structure;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.repository.NovelRepository;
import com.ainovel.server.repository.SceneRepository;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.StorageService;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.web.dto.CreatedChapterInfo;
import com.ainovel.server.web.dto.NovelWithScenesDto;
import com.ainovel.server.web.dto.NovelWithSummariesDto;
import com.ainovel.server.web.dto.SceneSummaryDto;
import com.ainovel.server.web.dto.ChaptersForPreloadDto;
import com.ainovel.server.service.cache.NovelStructureCache;
import com.ainovel.server.service.cache.NovelStructureCache.ContainIndex;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.util.function.Tuple2;
import org.springframework.util.StringUtils;

/**
 * 小说服务实现类
 */
@Slf4j

@Service
@RequiredArgsConstructor
public class NovelServiceImpl implements NovelService {

    private final NovelRepository novelRepository;
    private final SceneRepository sceneRepository;
    private final StorageService storageService;
    private final SceneService sceneService;
    private final ReactiveMongoTemplate reactiveMongoTemplate;
    private final NovelStructureCache structureCache;

    @Override
    public Mono<Novel> createNovel(Novel novel) {
        novel.setCreatedAt(LocalDateTime.now());
        novel.setUpdatedAt(LocalDateTime.now());
        // 确保新创建的小说默认为就绪状态
        if (novel.getIsReady() == null) {
            novel.setIsReady(true);
        }
        return novelRepository.save(novel)
                .doOnSuccess(saved -> log.info("创建小说成功: {} (isReady: {})", saved.getId(), saved.getIsReady()));
    }

    @Override
    public Mono<Novel> findNovelById(String id) {
        return novelRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", id)));
    }

    @Override
    public Mono<Novel> updateNovel(String id, Novel updatedNovel) {
        return novelRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", id)))
                .flatMap(existingNovel -> {
                    // 使用智能合并逻辑处理结构更新（仅当明确提供了非空的结构变更时）
                    if (updatedNovel.getStructure() != null
                            && updatedNovel.getStructure().getActs() != null
                            && !updatedNovel.getStructure().getActs().isEmpty()) {
                        smartMergeNovelStructure(existingNovel, updatedNovel);
                    }
                    
                    // 更新其他非结构字段
                    if (updatedNovel.getTitle() != null) {
                        existingNovel.setTitle(updatedNovel.getTitle());
                    }
                    if (updatedNovel.getDescription() != null) {
                        existingNovel.setDescription(updatedNovel.getDescription());
                    }
                    if (updatedNovel.getGenre() != null) {
                        existingNovel.setGenre(updatedNovel.getGenre());
                    }
                    if (updatedNovel.getCoverImage() != null) {
                        existingNovel.setCoverImage(updatedNovel.getCoverImage());
                    }
                    if (updatedNovel.getStatus() != null) {
                        existingNovel.setStatus(updatedNovel.getStatus());
                    }
                    if (updatedNovel.getTags() != null) {
                        existingNovel.setTags(updatedNovel.getTags());
                    }
                    // 新增：更新就绪状态
                    if (updatedNovel.getIsReady() != null) {
                        existingNovel.setIsReady(updatedNovel.getIsReady());
                    }
                    if (updatedNovel.getMetadata() != null) {
                        existingNovel.setMetadata(updatedNovel.getMetadata());
                    }
                    if (updatedNovel.getLastEditedChapterId() != null) {
                        existingNovel.setLastEditedChapterId(updatedNovel.getLastEditedChapterId());
                    }

                    // 更新时间戳
                    existingNovel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(existingNovel);
                })
                .doOnSuccess(savedNovel -> {
                    log.info("智能合并更新小说成功: {}, isReady: {}", savedNovel.getId(), savedNovel.getIsReady());
                })
                .doOnError(error -> {
                    log.error("智能合并更新小说失败: {}", error.getMessage(), error);
                });
    }

    @Override
    public Mono<Novel> updateNovelWithScenes(String id, Novel novel, Map<String, List<Scene>> scenesByChapter) {
        // 首先更新小说信息
        return updateNovel(id, novel)
                .flatMap(updatedNovel -> {
                    // 如果场景列表为空，直接返回更新后的小说
                    if (scenesByChapter == null || scenesByChapter.isEmpty()) {
                        return Mono.just(updatedNovel);
                    }

                    // 创建一个列表来保存所有场景更新操作
                    List<Mono<Scene>> sceneUpdateOperations = new ArrayList<>();

                    // 对每个章节的场景进行更新
                    for (Map.Entry<String, List<Scene>> entry : scenesByChapter.entrySet()) {
                        String chapterId = entry.getKey();
                        List<Scene> scenes = entry.getValue();

                        // 过滤出属于当前小说和章节的场景
                        scenes.forEach(scene -> {
                            // 确保场景关联到正确的小说和章节
                            scene.setNovelId(id);
                            scene.setChapterId(chapterId);

                            // 添加更新操作到列表中
                            sceneUpdateOperations.add(sceneRepository.save(scene));
                        });
                    }

                    // 如果没有需要更新的场景，直接返回更新后的小说
                    if (sceneUpdateOperations.isEmpty()) {
                        return Mono.just(updatedNovel);
                    }

                    // 并行执行所有场景更新操作
                    return Flux.merge(sceneUpdateOperations)
                            .collectList()
                            .map(updatedScenes -> {
                                log.info("成功更新小说 {} 的 {} 个场景", id, updatedScenes.size());
                                return updatedNovel;
                            });
                })
                .doOnSuccess(updated -> log.info("更新小说及其场景成功: {}", updated.getId()));
    }

    @Override
    public Mono<Void> deleteNovel(String id) {
        return novelRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", id)))
                .flatMap(novel -> novelRepository.delete(novel))
                .doOnSuccess(v -> log.info("删除小说成功: {}", id));
    }

    @Override
    public Mono<Novel> updateNovelMetadata(String id, String title, String author, String series) {
        return novelRepository.findById(id)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", id)))
                .flatMap(existingNovel -> {
                    // 更新元数据字段
                    if (title != null) {
                        existingNovel.setTitle(title);
                    }

                    // 作者信息需要特殊处理，因为是一个对象
                    if (author != null && existingNovel.getAuthor() != null) {
                        // 这里假设只更新作者的用户名，保留原有的作者ID
                        existingNovel.getAuthor().setUsername(author);
                    }

                    // 系列信息可能需要添加到元数据中，因为Novel类里没有series字段
                    if (series != null) {
                        // 将系列信息添加到标签中
                        List<String> tags = existingNovel.getTags();
                        if (tags == null) {
                            tags = new ArrayList<>();
                            existingNovel.setTags(tags);
                        }

                        // 移除旧的系列标签（如果存在）
                        tags.removeIf(tag -> tag.startsWith("series:"));

                        // 添加新的系列标签
                        tags.add("series:" + series);
                    }

                    // 更新时间戳
                    existingNovel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(existingNovel);
                })
                .doOnSuccess(updated -> log.info("更新小说元数据成功: {}", updated.getId()));
    }

    @Override
    public Mono<Map<String, String>> getCoverUploadCredential(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> storageService.getCoverUploadCredential(novelId,
                "cover.jpg", "image/jpeg"));

    }

    @Override
    public Mono<Novel> updateNovelCover(String novelId, String coverUrl) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(existingNovel -> {
                    // 获取旧的封面URL
                    String oldCoverImage = existingNovel.getCoverImage();

                    // 更新封面URL
                    existingNovel.setCoverImage(coverUrl);
                    existingNovel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(existingNovel)
                            .flatMap(updatedNovel -> {
                                // 如果有旧封面且与新封面不同，尝试删除旧封面
                                if (oldCoverImage != null && !oldCoverImage.isEmpty()
                                        && !oldCoverImage.equals(coverUrl)) {
                                    // 尝试从URL中提取key
                                    String oldCoverKey = extractCoverKeyFromUrl(oldCoverImage);
                                    if (oldCoverKey != null) {
                                        return storageService.deleteCover(oldCoverKey)
                                                .onErrorResume(e -> {
                                                    log.warn("删除旧封面失败: {}, 错误: {}", oldCoverKey, e.getMessage());
                                                    return Mono.just(false);
                                                })
                                                .thenReturn(updatedNovel);
                                    }
                                }
                                return Mono.just(updatedNovel);
                            });
                })
                .doOnSuccess(updated -> log.info("更新小说封面成功: {}, 新封面URL: {}", updated.getId(), coverUrl));
    }

    /**
     * 从封面URL中提取存储键 这个方法需要根据实际的URL格式进行调整
     */
    private String extractCoverKeyFromUrl(String coverUrl) {
        try {
            if (coverUrl == null || coverUrl.isEmpty()) {
                return null;
            }

            // 示例: 从URL https://bucket.endpoint/covers/novelId/filename.jpg 提取 covers/novelId/filename.jpg
            int protocolEnd = coverUrl.indexOf("://");
            if (protocolEnd > 0) {
                String withoutProtocol = coverUrl.substring(protocolEnd + 3);
                int pathStart = withoutProtocol.indexOf('/');
                if (pathStart > 0) {
                    return withoutProtocol.substring(pathStart + 1);
                }
            }

            return null;
        } catch (Exception e) {
            log.warn("从URL提取封面键失败: {}, 错误: {}", coverUrl, e.getMessage());
            return null;
        }
    }

    @Override
    public Mono<Novel> archiveNovel(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(existingNovel -> {
                    // 将小说标记为已归档
                    existingNovel.setIsArchived(true);
                    existingNovel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(existingNovel);
                })
                .doOnSuccess(updated -> log.info("小说归档成功: {}", updated.getId()));
    }

    @Override
    public Mono<Novel> unarchiveNovel(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(existingNovel -> {
                    // 将小说标记为未归档
                    existingNovel.setIsArchived(false);
                    existingNovel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(existingNovel);
                })
                .doOnSuccess(updated -> log.info("小说恢复归档成功: {}", updated.getId()));
    }

    @Override
    public Mono<Void> permanentlyDeleteNovel(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 先删除与该小说相关的所有场景
                    return sceneRepository.deleteByNovelId(novelId)
                            .then(novelRepository.delete(novel));
                })
                .doOnSuccess(v -> log.info("永久删除小说及其所有场景成功: {}", novelId));
    }

    @Override
    public Flux<Novel> findNovelsByAuthorId(String authorId) {
        return novelRepository.findByAuthorId(authorId);
    }

    @Override
    public Flux<Novel> searchNovelsByTitle(String title) {
        return novelRepository.findByTitleContaining(title);
    }

    @Override
    public Flux<Scene> getNovelScenes(String novelId) {
        return sceneRepository.findByNovelId(novelId);
    }

    @Override
    public Flux<Character> getNovelCharacters(String novelId) {
        // 暂时返回空结果，后续实现
        log.info("获取小说角色列表: {}", novelId);
        return Flux.empty();
    }


    @Override
    public Mono<Novel> updateLastEditedChapter(String novelId, String chapterId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    novel.setLastEditedChapterId(chapterId);
                    novel.setUpdatedAt(LocalDateTime.now());
                    return novelRepository.save(novel);
                })
                .doOnSuccess(updated -> log.info("更新小说最后编辑章节成功: {}, 章节: {}", novelId, chapterId));
    }

    public Mono<List<Scene>> getChapterContextScenes(String novelId, String authorId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 检查作者权限
                    if (!novel.getAuthor().getId().equals(authorId)) {
                        return Mono.error(new SecurityException("无权访问该小说"));
                    }

                    String lastEditedChapterId = novel.getLastEditedChapterId();
                    if (lastEditedChapterId == null || lastEditedChapterId.isEmpty()) {
                        // 如果没有上次编辑的章节，则获取第一个章节
                        if (novel.getStructure() != null
                                && !novel.getStructure().getActs().isEmpty()
                                && !novel.getStructure().getActs().get(0).getChapters().isEmpty()) {
                            lastEditedChapterId = novel.getStructure().getActs().get(0).getChapters().get(0).getId();
                        } else {
                            // 没有章节，返回空列表
                            return Mono.just(new ArrayList<>());
                        }
                    }

                    // 获取前后五章的章节ID列表
                    List<String> contextChapterIds = getContextChapterIds(novel, lastEditedChapterId, 5);

                    // 获取这些章节的所有场景ID
                    List<String> sceneIds = new ArrayList<>();
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            if (contextChapterIds.contains(chapter.getId())) {
                                sceneIds.addAll(chapter.getSceneIds());
                            }
                        }
                    }

                    // 获取所有场景内容
                    return Flux.fromIterable(sceneIds)
                            .flatMap(sceneRepository::findById)
                            .collectList();
                });
    }

    /**
     * 获取指定章节前后n章的章节ID列表
     *
     * @param novel 小说
     * @param chapterId 当前章节ID
     * @param n 前后章节数
     * @return 章节ID列表
     */
    private List<String> getContextChapterIds(Novel novel, String chapterId, int n) {
        List<String> allChapterIds = new ArrayList<>();

        // 提取所有章节ID并记录它们的顺序
        for (Novel.Act act : novel.getStructure().getActs()) {
            for (Novel.Chapter chapter : act.getChapters()) {
                allChapterIds.add(chapter.getId());
            }
        }

        // 找到当前章节的索引
        int currentIndex = allChapterIds.indexOf(chapterId);
        if (currentIndex == -1) {
            // 如果找不到当前章节，返回前n章
            return allChapterIds.stream()
                    .limit(Math.min(n, allChapterIds.size()))
                    .collect(Collectors.toList());
        }

        // 计算前后n章的范围
        int startIndex = Math.max(0, currentIndex - n);
        int endIndex = Math.min(allChapterIds.size() - 1, currentIndex + n);

        // 提取前后n章的ID
        return allChapterIds.subList(startIndex, endIndex + 1);
    }

    @Override
    public Mono<NovelWithScenesDto> getNovelWithAllScenes(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取所有章节ID
                    List<String> allChapterIds = new ArrayList<>();
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            allChapterIds.add(chapter.getId());
                        }
                    }

                    // 如果没有章节，直接返回只有小说信息的DTO
                    if (allChapterIds.isEmpty()) {
                        return Mono.just(NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 查询所有场景并按章节分组
                    return sceneRepository.findByNovelId(novelId)
                            .collectList()
                            .map(scenes -> {
                                // 按章节ID分组
                                Map<String, List<Scene>> scenesByChapter = scenes.stream()
                                        .collect(Collectors.groupingBy(Scene::getChapterId));

                                // 构建并返回DTO
                                return NovelWithScenesDto.builder()
                                        .novel(novel)
                                        .scenesByChapter(scenesByChapter)
                                        .build();
                            });
                })
                .doOnSuccess(dto -> log.info("获取小说及其所有场景成功，小说ID: {}", novelId));
    }

    @Override
    public Mono<NovelWithScenesDto> getNovelWithPaginatedScenes(String novelId, String lastEditedChapterId, int chaptersLimit) {
        log.info("分页获取小说内容，novelId={}, lastEditedChapterId={}, chaptersLimit={}",
                novelId, lastEditedChapterId, chaptersLimit);

        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取所有章节ID，并保持它们的顺序
                    List<String> allChapterIds = new ArrayList<>();
                    Map<String, Novel.Act> actsByChapterId = new HashMap<>(); // 用于后续查找chapter所属的act

                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            allChapterIds.add(chapter.getId());
                            actsByChapterId.put(chapter.getId(), act);
                        }
                    }

                    // 如果没有章节，直接返回只有小说信息的DTO
                    if (allChapterIds.isEmpty()) {
                        return Mono.just(NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 确定中心章节
                    String centerChapterId = lastEditedChapterId;

                    // 如果未提供lastEditedChapterId或者它不在章节列表中
                    if (centerChapterId == null || centerChapterId.isEmpty() || !allChapterIds.contains(centerChapterId)) {
                        // 使用novel的lastEditedChapterId字段，尝试使用它
                        centerChapterId = novel.getLastEditedChapterId();
                        // 如果lastEditedChapterId也无效，使用第一个章节
                        if (centerChapterId == null || centerChapterId.isEmpty() || !allChapterIds.contains(centerChapterId)) {
                            centerChapterId = allChapterIds.getFirst();
                        }
                    }

                    // 确定加载范围
                    int centerIndex = allChapterIds.indexOf(centerChapterId);
                    int startIndex = Math.max(0, centerIndex - chaptersLimit);
                    int endIndex = Math.min(allChapterIds.size() - 1, centerIndex + chaptersLimit);

                    // 获取要加载的章节ID列表
                    List<String> chapterIdsToLoad = allChapterIds.subList(startIndex, endIndex + 1);

                    log.info("分页加载章节，中心章节={}, 总章节数={}, 加载章节数={}, 范围从{}到{}",
                            centerChapterId, allChapterIds.size(), chapterIdsToLoad.size(), startIndex, endIndex);




                    // 获取这些章节的场景
                    return Flux.fromIterable(chapterIdsToLoad)
                            .flatMap(sceneRepository::findByChapterId)
                            .collectList()
                            .map(scenes -> {
                                // 按章节ID分组，明确指定返回类型
                                final Map<String, List<Scene>> scenesByChapter = scenes.stream()
                                        .collect(Collectors.groupingBy(
                                                Scene::getChapterId,
                                                Collectors.toList() // 明确指定下游收集器
                                        ));

                                // 构建并返回DTO
                                return NovelWithScenesDto.builder()
                                        .novel(novel)
                                        .scenesByChapter(scenesByChapter)
                                        .build();
                            });
                })
                .doOnSuccess(dto -> log.info("分页获取小说及场景成功，小说ID: {}, 中心章节ID: {}, 加载章节数: {}",
                novelId, lastEditedChapterId, dto.getScenesByChapter().size()))
                .doOnError(e -> log.error("分页获取小说内容失败", e));
    }

    @Override
    public Mono<Map<String, List<Scene>>> loadMoreScenes(String novelId, String actIdConstraint, String fromChapterId, String direction, int chaptersLimit) {
        log.info("加载更多场景: novelId={}, actId={}, fromChapterId={}, direction={}, chaptersLimit={}", 
                novelId, actIdConstraint, fromChapterId, direction, chaptersLimit);
        
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 准备一个章节的ID列表，以便确定加载范围
                    List<String> allChapterIds = new ArrayList<>();
                    
                    // 如果指定了actId，只加载该卷内的章节
                    if (StringUtils.hasText(actIdConstraint)) {
                        // 查找指定的卷
                        Act targetAct = null;
                        for (Act act : novel.getStructure().getActs()) {
                            if (act.getId().equals(actIdConstraint)) {
                                targetAct = act;
                                break;
                            }
                        }
                        
                        if (targetAct == null) {
                            log.warn("找不到指定的卷: {}", actIdConstraint);
                            return Mono.just(new HashMap<>());
                        }
                        
                        // 从指定卷中收集章节ID
                        for (Chapter chapter : targetAct.getChapters()) {
                            allChapterIds.add(chapter.getId());
                        }
                        
                        log.info("根据卷ID {}，找到 {} 个章节", actIdConstraint, allChapterIds.size());
                    } else {
                        // 没有指定actId，按照原有逻辑加载所有卷的章节
                        for (Act act : novel.getStructure().getActs()) {
                            for (Chapter chapter : act.getChapters()) {
                                allChapterIds.add(chapter.getId());
                            }
                        }
                        log.info("未指定卷ID，小说 {} 共有 {} 个章节", novelId, allChapterIds.size());
                    }
                    
                    if (allChapterIds.isEmpty()) {
                        log.info("没有可加载的章节，返回空结果");
                        return Mono.just(new HashMap<>());
                    }
                    
                    int fromIndex = -1;
                    if (fromChapterId != null) {
                        fromIndex = allChapterIds.indexOf(fromChapterId); // 当前章节在所有章节列表中的索引
                        if (fromIndex == -1) {
                            log.error("找不到指定的章节: {}", fromChapterId);
                            return Mono.just(new HashMap<>());
                        }
                    }
                    
                    List<String> chapterIdsToLoad;

                    if ("up".equalsIgnoreCase(direction)) {
                        // 向上加载
                        if (fromIndex <= 0) {
                            // 已经是第一章，没有更多内容可加载
                            log.info("已经是第一章，没有更多内容可向上加载");
                            return Mono.just(new HashMap<>());
                        }
                        int startIndex = Math.max(0, fromIndex - chaptersLimit);
                        chapterIdsToLoad = allChapterIds.subList(startIndex, fromIndex); // 不包括 fromIndex 章节本身
                        log.info("向上加载章节，从索引{}到{}，共{}个章节", startIndex, fromIndex, chapterIdsToLoad.size());
                    } else if ("center".equalsIgnoreCase(direction)) {
                        // 中心加载 - 如果是初始加载（fromChapterId为null），加载前几章
                        if (fromIndex == -1) {
                            int endIndex = Math.min(allChapterIds.size(), chaptersLimit);
                            chapterIdsToLoad = allChapterIds.subList(0, endIndex);
                            log.info("初始加载章节，加载前{}章，实际加载{}章", chaptersLimit, chapterIdsToLoad.size());
                        } else {
                            // 加载当前章节和它周围的章节
                            int beforeCount = chaptersLimit / 2;
                            int afterCount = chaptersLimit - beforeCount;
                            int startIndex = Math.max(0, fromIndex - beforeCount);
                            int endIndex = Math.min(allChapterIds.size(), fromIndex + afterCount + 1); // +1 因为要包含当前章节
                            chapterIdsToLoad = allChapterIds.subList(startIndex, endIndex);
                            log.info("中心加载章节，从索引{}到{}，共{}个章节", startIndex, endIndex, chapterIdsToLoad.size());
                        }
                    } else { // "down"
                        // 向下加载
                        if (fromIndex == -1) {
                            // 初始加载
                            int endIndex = Math.min(allChapterIds.size(), chaptersLimit);
                            chapterIdsToLoad = allChapterIds.subList(0, endIndex);
                            log.info("初始向下加载，加载前{}章，实际加载{}章", chaptersLimit, chapterIdsToLoad.size());
                        } else if (fromIndex >= allChapterIds.size() - 1) {
                            // 已经是最后一章，没有更多内容可加载
                            log.info("已经是最后一章，没有更多内容可向下加载");
                            return Mono.just(new HashMap<>());
                        } else {
                            int startIndex = fromIndex + 1; // 从fromChapterId的下一个开始
                            int endIndex = Math.min(allChapterIds.size(), startIndex + chaptersLimit);
                            chapterIdsToLoad = allChapterIds.subList(startIndex, endIndex);
                            log.info("向下加载章节，从索引{}到{}，共{}个章节", startIndex, endIndex, chapterIdsToLoad.size());
                        }
                    }

                    // 如果没有章节可加载，返回空结果
                    if (chapterIdsToLoad.isEmpty()) {
                        Map<String, List<Scene>> emptyResult = new HashMap<>();
                        log.info("没有章节可加载，返回空结果");
                        return Mono.just(emptyResult);
                    }

                    // 加载每个章节的场景
                    return Flux.fromIterable(chapterIdsToLoad)
                            .flatMap(chapterId -> 
                                // 为每个章节加载场景
                                sceneRepository.findByChapterId(chapterId)
                                    .collectList()
                                    .doOnNext(scenes -> log.info("章节 {} 的场景数量: {}", chapterId, scenes.size()))
                            )
                            .collectList()
                            .map(sceneLists -> {
                                Map<String, List<Scene>> groupedScenes = new HashMap<>();
                                // 将场景按章节ID分组
                                for (int i = 0; i < chapterIdsToLoad.size() && i < sceneLists.size(); i++) {
                                    String chapterId = chapterIdsToLoad.get(i);
                                    List<Scene> scenes = sceneLists.get(i);
                                    groupedScenes.put(chapterId, scenes);
                                }
                                return groupedScenes;
                            })
                            .doOnSuccess(result -> log.info("加载更多场景成功，加载章节数: {}", result.size()));
                });
    }

    @Override
    public Mono<Novel> updateActTitle(String novelId, String actId, String title) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }

                    // 查找指定的卷
                    boolean actFound = false;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            act.setTitle(title);
                            actFound = true;
                            break;
                        }
                    }

                    if (!actFound) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }

                    // 更新小说
                    novel.setUpdatedAt(LocalDateTime.now());
                    return novelRepository.save(novel);
                })
                .doOnSuccess(updated -> log.info("更新卷标题成功: 小说 {}, 卷 {}, 新标题: {}", novelId, actId, title));
    }

    @Override
    public Mono<Novel> updateChapterTitle(String novelId, String chapterId, String title) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }

                    // 查找指定的章节
                    boolean chapterFound = false;
                    outerLoop:
                    for (Act act : structure.getActs()) {
                        if (act.getChapters() == null) {
                            continue;
                        }

                        for (Chapter chapter : act.getChapters()) {
                            if (chapter.getId().equals(chapterId)) {
                                chapter.setTitle(title);
                                chapterFound = true;
                                break outerLoop;
                            }
                        }
                    }

                    if (!chapterFound) {
                        return Mono.error(new ResourceNotFoundException("章节", chapterId));
                    }

                    // 更新小说
                    novel.setUpdatedAt(LocalDateTime.now());
                    return novelRepository.save(novel);
                })
                .doOnSuccess(updated -> log.info("更新章节标题成功: 小说 {}, 章节 {}, 新标题: {}", novelId, chapterId, title));
    }

    @Override
    public Mono<Novel> addAct(String novelId, String title, Integer position) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构，如果不存在则创建
                    Structure structure = novel.getStructure();
                    if (structure == null) {
                        structure = new Structure();
                        novel.setStructure(structure);
                    }

                    if (structure.getActs() == null) {
                        structure.setActs(new ArrayList<>());
                    }

                    // 创建新卷
                    Act newAct = new Act();
                    newAct.setId(UUID.randomUUID().toString());
                    newAct.setTitle(title);
                    newAct.setChapters(new ArrayList<>());

                    // 插入到指定位置或末尾
                    List<Act> acts = structure.getActs();
                    if (position != null && position >= 0 && position <= acts.size()) {
                        acts.add(position, newAct);
                    } else {
                        acts.add(newAct);
                    }

                    // 更新小说
                    novel.setUpdatedAt(LocalDateTime.now());
                    return novelRepository.save(novel);
                })
                .doOnSuccess(updated -> log.info("添加新卷成功: 小说 {}, 卷标题: {}", novelId, title));
    }

    @Override
    public Mono<Novel> addChapter(String novelId, String actId, String title, Integer position) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }

                    // 查找指定的卷
                    Act targetAct = null;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            break;
                        }
                    }

                    if (targetAct == null) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }

                    // 确保章节列表已初始化
                    if (targetAct.getChapters() == null) {
                        targetAct.setChapters(new ArrayList<>());
                    }

                    // 创建新章节
                    Chapter newChapter = new Chapter();
                    newChapter.setId(UUID.randomUUID().toString());
                    newChapter.setTitle(title);

                    // 插入到指定位置或末尾
                    List<Chapter> chapters = targetAct.getChapters();
                    if (position != null && position >= 0 && position <= chapters.size()) {
                        chapters.add(position, newChapter);
                    } else {
                        chapters.add(newChapter);
                    }

                    // 更新小说
                    novel.setUpdatedAt(LocalDateTime.now());
                    return novelRepository.save(novel);
                })
                .doOnSuccess(updated -> log.info("添加新章节成功: 小说 {}, 卷 {}, 章节标题: {}", novelId, actId, title));
    }

    @Override
    public Mono<Novel> moveScene(String novelId, String sceneId, String targetChapterId, int targetPosition) {
        return sceneRepository.findById(sceneId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景", sceneId)))
                .flatMap(scene -> {
                    // 检查场景是否属于这本小说
                    if (!scene.getNovelId().equals(novelId)) {
                        return Mono.error(new IllegalArgumentException("场景不属于指定的小说"));
                    }

                    String sourceChapterId = scene.getChapterId();

                    // 更新场景的章节ID和序列号
                    scene.setChapterId(targetChapterId);

                    // 获取目标章节的所有场景
                    return sceneRepository.findByChapterIdOrderBySequenceAsc(targetChapterId)
                            .collectList()
                            .flatMap(targetScenes -> {
                                // 如果是同一个章节内移动
                                if (sourceChapterId.equals(targetChapterId)) {
                                    // 删除当前场景
                                    targetScenes.removeIf(s -> s.getId().equals(sceneId));
                                }

                                // 检查目标位置是否有效
                                int insertPosition = Math.min(targetPosition, targetScenes.size());

                                // 插入场景到目标位置
                                targetScenes.add(insertPosition, scene);

                                // 更新所有场景的序列号
                                for (int i = 0; i < targetScenes.size(); i++) {
                                    targetScenes.get(i).setSequence(i);
                                }

                                // 保存所有更新的场景
                                return sceneRepository.saveAll(targetScenes).collectList()
                                        .flatMap(savedScenes -> {
                                            // 如果是不同章节间移动，需要更新源章节的场景序列号
                                            if (!sourceChapterId.equals(targetChapterId)) {
                                                return sceneRepository.findByChapterIdOrderBySequenceAsc(sourceChapterId)
                                                        .collectList()
                                                        .flatMap(sourceScenes -> {
                                                            // 删除当前场景（虽然已经移走，但可能仍在列表中）
                                                            sourceScenes.removeIf(s -> s.getId().equals(sceneId));

                                                            // 更新所有源章节场景的序列号
                                                            for (int i = 0; i < sourceScenes.size(); i++) {
                                                                sourceScenes.get(i).setSequence(i);
                                                            }

                                                            // 保存所有更新的源章节场景
                                                            return sceneRepository.saveAll(sourceScenes)
                                                                    .collectList()
                                                                    .then(novelRepository.findById(novelId));
                                                        });
                                            } else {
                                                return novelRepository.findById(novelId);
                                            }
                                        });
                            });
                })
                .doOnSuccess(novel -> log.info("移动场景成功: 场景 {}, 目标章节 {}, 目标位置 {}", sceneId, targetChapterId, targetPosition));
    }

    @Override
    public Mono<NovelWithSummariesDto> getNovelWithSceneSummaries(String novelId) {
        log.info("获取小说及其场景摘要，novelId={}", novelId);

        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取所有章节，建立章节ID到Chapter对象的映射
                    Map<String, Novel.Chapter> chapterMap = new HashMap<>();
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            chapterMap.put(chapter.getId(), chapter);
                        }
                    }

                    // 如果没有章节，直接返回只有小说信息的DTO
                    if (chapterMap.isEmpty()) {
                        return Mono.just(NovelWithSummariesDto.builder()
                                .novel(novel)
                                .sceneSummariesByChapter(new HashMap<>())
                                .build());
                    }

                    // 查询所有场景并按章节分组，但只保留摘要相关信息
                    return sceneRepository.findByNovelId(novelId)
                            .collectList()
                            .map(scenes -> {
                                // 将场景转换为摘要DTO
                                List<SceneSummaryDto> summaries = scenes.stream()
                                        .map(scene -> SceneSummaryDto.builder()
                                        .id(scene.getId())
                                        .novelId(scene.getNovelId())
                                        .chapterId(scene.getChapterId())
                                        .title(scene.getTitle())
                                        .summary(scene.getSummary())
                                        .sequence(scene.getSequence())
                                        .wordCount(calculateWordCount(scene.getContent()))
                                        .updatedAt(scene.getUpdatedAt())
                                        .build())
                                        .collect(Collectors.toList());

                                // 按章节ID分组
                                Map<String, List<SceneSummaryDto>> summariesByChapter = summaries.stream()
                                        .collect(Collectors.groupingBy(SceneSummaryDto::getChapterId));

                                // ✅ 新旧版本兼容：为没有Scene的章节使用Chapter.description作为fallback
                                for (Map.Entry<String, Novel.Chapter> entry : chapterMap.entrySet()) {
                                    String chapterId = entry.getKey();
                                    Novel.Chapter chapter = entry.getValue();
                                    
                                    // 如果该章节没有Scene，或者Scene的summary为空
                                    List<SceneSummaryDto> chapterScenes = summariesByChapter.get(chapterId);
                                    boolean needsFallback = chapterScenes == null || chapterScenes.isEmpty() ||
                                            chapterScenes.stream().allMatch(s -> s.getSummary() == null || s.getSummary().isEmpty());
                                    
                                    if (needsFallback && chapter.getDescription() != null && !chapter.getDescription().isEmpty()) {
                                        // 使用Chapter.description创建一个虚拟的SceneSummaryDto
                                        SceneSummaryDto fallbackSummary = SceneSummaryDto.builder()
                                                .id("fallback_" + chapterId) // 虚拟ID，标记为fallback
                                                .novelId(novelId)
                                                .chapterId(chapterId)
                                                .title(chapter.getTitle())
                                                .summary(chapter.getDescription()) // ✅ 使用Chapter.description
                                                .sequence(1)
                                                .wordCount(0)
                                                .updatedAt(novel.getUpdatedAt())
                                                .build();
                                        
                                        summariesByChapter.put(chapterId, List.of(fallbackSummary));
                                        log.debug("章节 {} 使用Chapter.description作为摘要fallback", chapter.getTitle());
                                    }
                                }

                                // 构建并返回DTO
                                return NovelWithSummariesDto.builder()
                                        .novel(novel)
                                        .sceneSummariesByChapter(summariesByChapter)
                                        .build();
                            });
                })
                .doOnSuccess(dto -> log.info("获取小说及其场景摘要成功，小说ID: {}, 章节数: {}",
                novelId, dto.getSceneSummariesByChapter().size()))
                .doOnError(e -> log.error("获取小说及其场景摘要失败", e));
    }

    /**
     * 计算文本内容的字数
     *
     * @param content 文本内容
     * @return 字数
     */
    private Integer calculateWordCount(String content) {
        if (content == null || content.isEmpty()) {
            return 0;
        }

        // 简单实现，去除HTML标记和特殊字符后统计
        String plainText = content.replaceAll("<[^>]*>", "") // 移除HTML标签
                .replaceAll("\\s+", " ") // 将多个空白字符合并为一个
                .trim();

        // 统计中文字符数量（使用正则表达式匹配中文字符）
        int chineseCount = 0;
        for (char c : plainText.toCharArray()) {
            if (isChinese(c)) {
                chineseCount++;
            }
        }

        // 英文部分按空格分词
        String englishOnly = plainText.replaceAll("[^\\x00-\\x7F]+", " ").trim();
        int englishWordCount = englishOnly.isEmpty() ? 0 : englishOnly.split("\\s+").length;

        return chineseCount + englishWordCount;
    }

    /**
     * 判断字符是否是中文
     *
     * @param c 字符
     * @return 是否是中文
     */
    private boolean isChinese(char c) {
        return c >= 0x4E00 && c <= 0x9FA5; // Unicode CJK统一汉字范围
    }

    /**
     * 计算并更新小说的总字数
     *
     * @param novelId 小说ID
     * @return 更新后的小说
     */
    @Override
    public Mono<Novel> updateNovelWordCount(String novelId) {
        return findNovelById(novelId)
                .flatMap(novel -> {
                    // 使用 SceneRepository 获取所有关联的场景
                    return sceneRepository.findByNovelId(novelId)
                            .flatMap(scene -> {
                                                                // 更新小说元数据
                                                                if (novel.getMetadata() == null) {
                                                                    novel.setMetadata(Novel.Metadata.builder().build());
                                                                }
                                // 计算每个场景的字数
                                return Mono.fromCallable(() -> calculateWordCount(scene.getContent()))
                                        .subscribeOn(Schedulers.boundedElastic()); // 将计算放在弹性线程池
                            })
                            .reduce(0, Integer::sum) // 累加所有场景的字数
                            .flatMap(totalWordCount -> {
                                // 计算估计阅读时间 (假设每分钟阅读300字)
                                int readTime = totalWordCount / 300;
                                if (readTime < 1 && totalWordCount > 0) {
                                    readTime = 1; // 最小阅读时间为1分钟
                                }
                                novel.getMetadata().setWordCount(totalWordCount);
                                novel.getMetadata().setReadTime(readTime);
                                novel.setUpdatedAt(novel.getUpdatedAt());
                                return novelRepository.save(novel);
                            });
                })
                .doOnSuccess(updatedNovel -> log.info("小说 {} 字数更新为: {}", novelId, updatedNovel.getMetadata().getWordCount()))
                .onErrorResume(e -> {
                    log.error("更新小说 {} 字数失败: {}", novelId, e.getMessage(), e);
                    return Mono.error(e);
                });
    }

    @Override
    public Mono<String> getChapterRangeSummaries(String novelId, String startChapterId, String endChapterId) {
        return findNovelById(novelId)
            .<String>flatMap(novel -> { // 显式指定 flatMap 返回类型为 Mono<String>
                Structure structure = novel.getStructure();
                if (structure == null || structure.getActs() == null || structure.getActs().isEmpty()) {
                    log.warn("小说 {} 没有有效的结构或章节信息，无法获取摘要范围", novelId);
                    return Mono.just(""); // 或者返回特定错误信息
                }

                // 获取所有章节的扁平列表，方便查找索引
                List<Chapter> allChapters = structure.getActs().stream()
                    .flatMap(act -> act.getChapters().stream())
                    .collect(Collectors.toList());

                if (allChapters.isEmpty()) {
                     log.warn("小说 {} 结构中没有章节，无法获取摘要范围", novelId);
                    return Mono.just("");
                }

                int startIndex = 0;
                int endIndex = allChapters.size() - 1;

                // 确定起始索引
                if (startChapterId != null) {
                    boolean foundStart = false;
                    for (int i = 0; i < allChapters.size(); i++) {
                        if (allChapters.get(i).getId().equals(startChapterId)) {
                            startIndex = i;
                            foundStart = true;
                            break;
                        }
                    }
                    if (!foundStart) {
                         log.warn("未找到起始章节ID: {}, 将从第一章开始", startChapterId);
                    }
                }

                // 确定结束索引
                if (endChapterId != null) {
                     boolean foundEnd = false;
                    for (int i = 0; i < allChapters.size(); i++) {
                        if (allChapters.get(i).getId().equals(endChapterId)) {
                            endIndex = i;
                            foundEnd = true;
                            break;
                        }
                    }
                     if (!foundEnd) {
                         log.warn("未找到结束章节ID: {}, 将到最后一章结束", endChapterId);
                         endIndex = allChapters.size() - 1; // 确保 endIndex 有效
                    }
                }

                // 确保索引有效且 startIndex <= endIndex
                if (startIndex > endIndex) {
                    log.warn("起始章节索引 ({}) 大于结束章节索引 ({}), 无法获取摘要范围", startIndex, endIndex);
                    return Mono.just("");
                }

                // 获取指定范围内的章节ID列表
                List<String> targetChapterIds = allChapters.subList(startIndex, endIndex + 1).stream()
                    .map(Chapter::getId)
                    .collect(Collectors.toList());

                 log.debug("获取小说 {} 从索引 {} 到 {} 的章节摘要, 章节ID列表: {}", novelId, startIndex, endIndex, targetChapterIds);

                // 并行获取所有目标章节的场景，然后串行处理拼接（保证顺序）
                return Flux.fromIterable(targetChapterIds)
                    .<String>concatMap(chapterId -> sceneService.findSceneByChapterId(chapterId) // 使用注入的 SceneService
                        .filter(scene -> scene.getSummary() != null && !scene.getSummary().isBlank())
                        .map(Scene::getSummary)
                        .collect(Collectors.joining("\n\n")) // 拼接单个章节内的摘要
                    )
                    .filter(chapterSummary -> !chapterSummary.isEmpty())
                    .collect(Collectors.joining("\n\n---\n\n")) // 拼接不同章节的摘要，用分隔符区分
                    .defaultIfEmpty(""); // 如果没有找到任何摘要，返回空字符串
            })
            .onErrorResume(e -> {
                log.error("获取小说 {} 章节范围摘要时出错: {}", novelId, e.getMessage(), e);
                // 可以返回一个错误提示字符串，或者空字符串，或者重新抛出异常
                return Mono.just("获取章节摘要时发生错误。");
            });
    }
    
    @Override
    public Mono<String> getChapterRangeContext(String novelId, String startChapterId, String endChapterId) {
        return findNovelById(novelId)
            .<String>flatMap(novel -> { // 显式指定 flatMap 返回类型为 Mono<String>
                Structure structure = novel.getStructure();
                if (structure == null || structure.getActs() == null || structure.getActs().isEmpty()) {
                    log.warn("小说 {} 没有有效的结构或章节信息，无法获取内容范围", novelId);
                    return Mono.just(""); // 或者返回特定错误信息
                }

                // 获取所有章节的扁平列表，方便查找索引
                List<Chapter> allChapters = structure.getActs().stream()
                    .flatMap(act -> act.getChapters().stream())
                    .collect(Collectors.toList());

                if (allChapters.isEmpty()) {
                     log.warn("小说 {} 结构中没有章节，无法获取内容范围", novelId);
                    return Mono.just("");
                }

                int startIndex = 0;
                int endIndex = allChapters.size() - 1;

                // 确定起始索引
                if (startChapterId != null) {
                    boolean foundStart = false;
                    for (int i = 0; i < allChapters.size(); i++) {
                        if (allChapters.get(i).getId().equals(startChapterId)) {
                            startIndex = i;
                            foundStart = true;
                            break;
                        }
                    }
                    if (!foundStart) {
                         log.warn("未找到起始章节ID: {}, 将从第一章开始", startChapterId);
                    }
                }

                // 确定结束索引
                if (endChapterId != null) {
                     boolean foundEnd = false;
                    for (int i = 0; i < allChapters.size(); i++) {
                        if (allChapters.get(i).getId().equals(endChapterId)) {
                            endIndex = i;
                            foundEnd = true;
                            break;
                        }
                    }
                     if (!foundEnd) {
                         log.warn("未找到结束章节ID: {}, 将到最后一章结束", endChapterId);
                         endIndex = allChapters.size() - 1; // 确保 endIndex 有效
                    }
                }

                // 确保索引有效且 startIndex <= endIndex
                if (startIndex > endIndex) {
                    log.warn("起始章节索引 ({}) 大于结束章节索引 ({}), 无法获取内容范围", startIndex, endIndex);
                    return Mono.just("");
                }

                // 获取指定范围内的章节ID列表
                List<String> targetChapterIds = allChapters.subList(startIndex, endIndex + 1).stream()
                    .map(Chapter::getId)
                    .collect(Collectors.toList());

                 log.debug("获取小说 {} 从索引 {} 到 {} 的章节内容, 章节ID列表: {}", novelId, startIndex, endIndex, targetChapterIds);

                // 并行获取所有目标章节的场景，然后串行处理拼接（保证顺序）
                return Flux.fromIterable(targetChapterIds)
                    .<String>concatMap(chapterId -> {
                        // 获取章节标题
                        String chapterTitle = allChapters.stream()
                            .filter(chapter -> chapter.getId().equals(chapterId))
                            .findFirst()
                            .map(Chapter::getTitle)
                            .orElse("未命名章节");
                        
                        // 为每个章节创建一个包含标题和内容的字符串
                        return sceneService.findSceneByChapterIdOrdered(chapterId) // 使用有序的场景检索
                            .map(scene -> {
                                // 获取场景标题和内容
                                String sceneTitle = scene.getTitle() != null ? scene.getTitle() : "场景";
                                String sceneContent = RichTextUtil.deltaJsonToPlainText(scene.getContent() != null ? scene.getContent() : "");


                                
                                // 返回格式化的场景内容
                                return String.format("【场景：%s】\n%s", sceneTitle, sceneContent);
                            })
                            .collect(Collectors.joining("\n\n")) // 拼接同一章节中的所有场景
                            .map(scenesContent -> {
                                // 添加章节标题作为前缀
                                return String.format("%s\n\n%s", chapterTitle, scenesContent);
                            })
                            .defaultIfEmpty(String.format("## %s\n\n(无内容)", chapterTitle)); // 如果章节没有场景，添加默认提示
                    })
                    .collect(Collectors.joining("\n\n---\n\n")) // 拼接不同章节的内容，用分隔符区分
                    .defaultIfEmpty(""); // 如果没有找到任何内容，返回空字符串
            })
            .onErrorResume(e -> {
                log.error("获取小说 {} 章节范围内容时出错: {}", novelId, e.getMessage(), e);
                // 可以返回一个错误提示字符串，或者空字符串，或者重新抛出异常
                return Mono.just("获取章节内容时发生错误。");
            });
    }

    @Override
    public Mono<CreatedChapterInfo> addChapterWithInitialScene(
            String novelId, String chapterTitle, String initialSceneSummary, String initialSceneTitle) {
        // 调用带元数据版本，提供空的元数据Map
        return addChapterWithInitialScene(novelId, chapterTitle, initialSceneSummary, initialSceneTitle, new HashMap<>());
    }

    @Override
    public Mono<CreatedChapterInfo> addChapterWithInitialScene(
        String novelId, String chapterTitle, String initialSceneSummary, 
        String initialSceneTitle, Map<String, Object> metadata) {
        
        // 添加元数据参数支持
        return novelRepository.findById(novelId)
            .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
            .flatMap(novel -> {
                Structure structure = novel.getStructure();
                Act targetAct;

                // 确保 Structure 和 Acts 列表存在
                if (structure == null) {
                    structure = new Structure();
                    novel.setStructure(structure);
                }
                if (structure.getActs() == null) {
                    structure.setActs(new ArrayList<>());
                }

                // 查找最后一卷，如果不存在则创建
                if (structure.getActs().isEmpty()) {
                    log.info("小说 {} 没有卷，创建第一卷", novelId);
                    Act newAct = Act.builder()
                        .id(UUID.randomUUID().toString())
                        .title("第一卷")
                        .chapters(new ArrayList<>())
                        .build();
                    structure.getActs().add(newAct);
                    targetAct = newAct;
                } else {
                    targetAct = structure.getActs().get(structure.getActs().size() - 1);
                }

                // 确保目标 Act 的 Chapters 列表存在
                if (targetAct.getChapters() == null) {
                    targetAct.setChapters(new ArrayList<>());
                }

                // 创建新场景
                Scene newScene = Scene.builder()
                    .id(UUID.randomUUID().toString())
                    .novelId(novelId)
                    // chapterId 将在下面设置
                    .title(initialSceneTitle != null ? initialSceneTitle : "场景 1") // 使用传入标题或默认值
                    .summary(initialSceneSummary)
                    .content("") // 初始内容为空
                    .sequence(0) // 第一个场景
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build();

                // 创建新章节
                Chapter newChapter = Chapter.builder()
                    .id(UUID.randomUUID().toString())
                    .title(chapterTitle)
                    .sceneIds(Collections.singletonList(newScene.getId()))
                    .metadata(metadata) // 设置传入的元数据
                    .build();

                // 设置场景的 chapterId
                newScene.setChapterId(newChapter.getId());

                // 添加新章节到目标 Act
                targetAct.getChapters().add(newChapter);

                // 更新小说更新时间
                novel.setUpdatedAt(LocalDateTime.now());

                // 首先保存场景 (因为 Novel 不直接内嵌 Scene)
                return sceneRepository.save(newScene)
                    .flatMap(savedScene -> {
                        // 然后保存更新后的小说结构
                        return novelRepository.save(novel)
                            .then(Mono.just(new CreatedChapterInfo(newChapter.getId(), savedScene.getId(), initialSceneSummary)));
                    });
            })
            .doOnSuccess(info -> log.info("添加新章节和初始场景成功: 小说 {}, 章节 {}, 场景 {}", novelId, info.getChapterId(), info.getSceneId()))
            .doOnError(e -> log.error("添加新章节和初始场景失败: 小说 {}, 错误: {}", novelId, e.getMessage()));
    }

    @Override
    public Mono<Scene> updateSceneContent(String novelId, String chapterId, String sceneId, String content) {
        return sceneRepository.findById(sceneId)
            .switchIfEmpty(Mono.error(new ResourceNotFoundException("场景", sceneId)))
            .flatMap(scene -> {
                // 可选：验证 novelId 和 chapterId 是否匹配
                if (!scene.getNovelId().equals(novelId)) {
                     log.warn("场景 {} 的 novelId ({}) 与请求 novelId ({}) 不匹配", sceneId, scene.getNovelId(), novelId);
                    // return Mono.error(new IllegalArgumentException("Scene novelId mismatch")); // 可以选择报错或仅警告
                }
                 if (!scene.getChapterId().equals(chapterId)) {
                     log.warn("场景 {} 的 chapterId ({}) 与请求 chapterId ({}) 不匹配", sceneId, scene.getChapterId(), chapterId);
                    // return Mono.error(new IllegalArgumentException("Scene chapterId mismatch")); // 可以选择报错或仅警告
                }

                scene.setContent(PromptUtil.convertPlainTextToQuillDelta(content));
                scene.setUpdatedAt(LocalDateTime.now());
                // 可以考虑调用 calculateWordCount 并设置 scene.wordCount
                // scene.setWordCount(calculateWordCount(content));

                return sceneRepository.save(scene);
            })
            .doOnSuccess(savedScene -> log.info("更新场景内容成功: 场景 {}", savedScene.getId()))
            .doOnError(e -> log.error("更新场景内容失败: 场景 {}, 错误: {}", sceneId, e.getMessage()));
    }

    @Override
    public Mono<Novel> deleteChapter(String novelId, String actId, String chapterId) {
        log.info("开始删除章节: 小说={}, 卷={}, 章节={}", novelId, actId, chapterId);
        
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }

                    // 查找指定的卷和章节
                    boolean chapterFound = false;
                    Act targetAct = null;
                    
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            if (act.getChapters() != null) {
                                Iterator<Chapter> chapterIterator = act.getChapters().iterator();
                                while (chapterIterator.hasNext()) {
                                    Chapter chapter = chapterIterator.next();
                                    if (chapter.getId().equals(chapterId)) {
                                        chapterIterator.remove();
                                        chapterFound = true;
                                        break;
                                    }
                                }
                            }
                            break;
                        }
                    }

                    if (targetAct == null) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }

                    if (!chapterFound) {
                        return Mono.error(new ResourceNotFoundException("章节", chapterId));
                    }

                    // 更新小说
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 更新最后编辑的章节ID（如果被删除的章节是最后编辑的章节）
                    if (chapterId.equals(novel.getLastEditedChapterId())) {
                        // 查找其他可用章节
                        String newLastEditedChapterId = null;
                        if (targetAct.getChapters() != null && !targetAct.getChapters().isEmpty()) {
                            // 优先使用同一卷中的章节
                            newLastEditedChapterId = targetAct.getChapters().get(0).getId();
                        } else {
                            // 查找其他卷中的章节
                            for (Act act : structure.getActs()) {
                                if (act.getChapters() != null && !act.getChapters().isEmpty()) {
                                    newLastEditedChapterId = act.getChapters().get(0).getId();
                                    break;
                                }
                            }
                        }
                        novel.setLastEditedChapterId(newLastEditedChapterId);
                    }
                    
                    // 先保存小说，删除章节结构
                    return novelRepository.save(novel)
                            .flatMap(savedNovel -> {
                                // 然后删除章节的所有场景数据
                                return sceneService.deleteScenesByChapterId(chapterId)
                                        .thenReturn(savedNovel);
                            });
                })
                .doOnSuccess(novel -> log.info("章节删除成功: 小说={}, 卷={}, 章节={}", novelId, actId, chapterId))
                .doOnError(e -> log.error("章节删除失败: 小说={}, 卷={}, 章节={}, 原因={}", 
                        novelId, actId, chapterId, e.getMessage()));
    }
    
    @Override
    public Mono<Act> addActFine(String novelId, String title, String description) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构，如果不存在则创建
                    Structure structure = novel.getStructure();
                    if (structure == null) {
                        structure = new Structure();
                        novel.setStructure(structure);
                    }
                    
                    if (structure.getActs() == null) {
                        structure.setActs(new ArrayList<>());
                    }
                    
                    // 创建新卷，设置唯一ID
                    String actId = UUID.randomUUID().toString();
                    Act newAct = Act.builder()
                            .id(actId)
                            .title(title)
                            .description(description)
                            .chapters(new ArrayList<>())
                            .build();
                    
                    // 添加到卷列表末尾
                    structure.getActs().add(newAct);
                    
                    // 更新时间戳
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 保存小说
                    return novelRepository.save(novel)
                            .thenReturn(newAct);
                })
                .doOnSuccess(act -> log.info("成功添加新卷: novelId={}, actId={}, title={}", 
                        novelId, act.getId(), title))
                .doOnError(e -> log.error("添加新卷失败: novelId={}, title={}, error={}", 
                        novelId, title, e.getMessage()));
    }
    
    @Override
    public Mono<Chapter> addChapterFine(String novelId, String actId, String title, String description) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }
                    
                    // 查找指定的卷
                    Act targetAct = null;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            break;
                        }
                    }
                    
                    if (targetAct == null) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }
                    
                    // 确保章节列表已初始化
                    if (targetAct.getChapters() == null) {
                        targetAct.setChapters(new ArrayList<>());
                    }
                    
                    // 创建新章节，设置唯一ID
                    String chapterId = UUID.randomUUID().toString();
                    Chapter newChapter = Chapter.builder()
                            .id(chapterId)
                            .title(title)
                            .description(description)
                            .sceneIds(new ArrayList<>())
                            .build();
                    
                    // 添加到章节列表末尾
                    targetAct.getChapters().add(newChapter);
                    
                    // 更新时间戳
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 保存小说
                    return novelRepository.save(novel)
                            .thenReturn(newChapter);
                })
                .doOnSuccess(chapter -> log.info("成功添加新章节: novelId={}, actId={}, chapterId={}, title={}", 
                        novelId, actId, chapter.getId(), title))
                .doOnError(e -> log.error("添加新章节失败: novelId={}, actId={}, title={}, error={}", 
                        novelId, actId, title, e.getMessage()));
    }
    
    @Override
    @Transactional
    public Mono<Map<String, Object>> addChapterWithScene(String novelId, String actId, 
            String chapterTitle, String sceneTitle, String sceneSummary, String sceneContent) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }
                    
                    // 查找指定的卷
                    Act targetAct = null;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            break;
                        }
                    }
                    
                    if (targetAct == null) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }
                    
                    // 确保章节列表已初始化
                    if (targetAct.getChapters() == null) {
                        targetAct.setChapters(new ArrayList<>());
                    }
                    
                    // 第1步：创建新章节
                    String chapterId = UUID.randomUUID().toString();
                    Chapter newChapter = Chapter.builder()
                            .id(chapterId)
                            .title(chapterTitle)
                            .sceneIds(new ArrayList<>())
                            .build();
                    
                    // 添加到章节列表末尾
                    targetAct.getChapters().add(newChapter);
                    
                    // 第2步：创建新场景
                    String sceneId = UUID.randomUUID().toString();
                    
                    // 设置内容：如果提供了content则使用，否则使用空Quill格式
                    String finalContent;
                    int wordCount;
                    if (sceneContent != null && !sceneContent.trim().isEmpty()) {
                        // 🔥 关键修复：检查content是否已经是Quill Delta JSON格式
                        if (com.ainovel.server.common.util.RichTextUtil.isQuillDeltaJson(sceneContent)) {
                            // 已经是Quill格式，直接使用
                            finalContent = sceneContent;
                            log.debug("addChapterWithScene: 场景内容已经是Quill Delta JSON格式，直接使用");
                        } else {
                            // 纯文本格式，需要转换为Quill格式
                            finalContent = com.ainovel.server.common.util.RichTextUtil.plainTextToDeltaJson(sceneContent);
                            log.info("addChapterWithScene: 场景内容是纯文本，已转换为Quill Delta JSON格式。原始长度: {}, 转换后长度: {}", 
                                    sceneContent.length(), finalContent.length());
                        }
                        // 计算实际的纯文本字数（不包括JSON格式字符）
                        String plainText = com.ainovel.server.common.util.RichTextUtil.deltaJsonToPlainText(finalContent);
                        wordCount = plainText.length();
                    } else {
                        finalContent = "[{\"insert\":\"\\n\"}]"; // 标准空Quill格式
                        wordCount = 0;
                    }
                    
                    Scene newScene = Scene.builder()
                            .id(sceneId)
                            .novelId(novelId) // 添加缺失的novelId字段
                            .chapterId(chapterId)
                            .title(sceneTitle)
                            .content(finalContent)
                            .summary(sceneSummary != null ? sceneSummary : "")
                            .wordCount(wordCount)
                            .sequence(1)
                            .version(1)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .build();
                    
                    // 将场景ID添加到章节的sceneIds列表
                    newChapter.getSceneIds().add(sceneId);
                    
                    // 更新时间戳
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 第3步：原子化保存（先保存小说结构，再保存场景内容）
                    return novelRepository.save(novel)
                            .doOnSuccess(savedNovel -> log.info("原子化操作：小说结构已保存，novelId={}, 新章节={}", 
                                    savedNovel.getId(), chapterId))
                            .then(sceneRepository.save(newScene))
                            .doOnSuccess(savedScene -> log.info("原子化操作：场景已保存，sceneId={}, novelId={}, chapterId={}", 
                                    savedScene.getId(), savedScene.getNovelId(), savedScene.getChapterId()))
                            .then(Mono.fromCallable(() -> {
                                Map<String, Object> result = new HashMap<>();
                                result.put("chapterId", chapterId);
                                result.put("chapter", newChapter);
                                result.put("sceneId", sceneId);
                                result.put("scene", newScene);
                                log.info("原子化操作完成：chapterId={}, sceneId={}, 场景内容长度={}", 
                                        chapterId, sceneId, finalContent.length());
                                return result;
                            }));
                })
                .doOnSuccess(result -> log.info("成功原子化创建章节和场景: novelId={}, chapterId={}, sceneId={}", 
                        novelId, result.get("chapterId"), result.get("sceneId")))
                .doOnError(e -> log.error("原子化创建章节和场景失败: novelId={}, actId={}, error={}", 
                        novelId, actId, e.getMessage()));
    }

    @Override
    @Transactional
    public Mono<Map<String, Object>> addChapterWithSceneAt(
            String novelId,
            String actId,
            String insertAfterChapterId,
            String chapterTitle,
            String sceneTitle,
            String sceneSummary,
            String sceneContent) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.error(new ResourceNotFoundException("小说结构不存在", novelId));
                    }

                    Act targetAct = null;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            break;
                        }
                    }
                    if (targetAct == null) {
                        return Mono.error(new ResourceNotFoundException("卷", actId));
                    }
                    if (targetAct.getChapters() == null) {
                        targetAct.setChapters(new ArrayList<>());
                    }

                    // 计算插入位置：默认末尾；若提供了 insertAfterChapterId 且存在，则插入在其后
                    int insertIndex = targetAct.getChapters().size();
                    if (insertAfterChapterId != null && !insertAfterChapterId.isBlank()) {
                        for (int i = 0; i < targetAct.getChapters().size(); i++) {
                            if (insertAfterChapterId.equals(targetAct.getChapters().get(i).getId())) {
                                insertIndex = Math.min(i + 1, targetAct.getChapters().size());
                                break;
                            }
                        }
                    }

                    // 创建新章节
                    String chapterId = UUID.randomUUID().toString();
                    Chapter newChapter = Chapter.builder()
                            .id(chapterId)
                            .title(chapterTitle)
                            .sceneIds(new ArrayList<>())
                            .build();
                    targetAct.getChapters().add(insertIndex, newChapter);

                    // 创建新场景
                    String sceneId = UUID.randomUUID().toString();
                    String finalContent;
                    int wordCount;
                    if (sceneContent != null && !sceneContent.trim().isEmpty()) {
                        // 🔥 关键修复：检查content是否已经是Quill Delta JSON格式
                        if (com.ainovel.server.common.util.RichTextUtil.isQuillDeltaJson(sceneContent)) {
                            // 已经是Quill格式，直接使用
                            finalContent = sceneContent;
                            log.debug("addChapterWithSceneAt: 场景内容已经是Quill Delta JSON格式，直接使用");
                        } else {
                            // 纯文本格式，需要转换为Quill格式
                            finalContent = com.ainovel.server.common.util.RichTextUtil.plainTextToDeltaJson(sceneContent);
                            log.info("addChapterWithSceneAt: 场景内容是纯文本，已转换为Quill Delta JSON格式。原始长度: {}, 转换后长度: {}", 
                                    sceneContent.length(), finalContent.length());
                        }
                        // 计算实际的纯文本字数（不包括JSON格式字符）
                        String plainText = com.ainovel.server.common.util.RichTextUtil.deltaJsonToPlainText(finalContent);
                        wordCount = plainText.length();
                    } else {
                        finalContent = "[{\"insert\":\"\\n\"}]";
                        wordCount = 0;
                    }

                    Scene newScene = Scene.builder()
                            .id(sceneId)
                            .novelId(novelId)
                            .chapterId(chapterId)
                            .title(sceneTitle)
                            .content(finalContent)
                            .summary(sceneSummary != null ? sceneSummary : "")
                            .wordCount(wordCount)
                            .sequence(1)
                            .version(1)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .build();
                    newChapter.getSceneIds().add(sceneId);

                    novel.setUpdatedAt(LocalDateTime.now());

                    return novelRepository.save(novel)
                            .then(sceneRepository.save(newScene))
                            .then(Mono.fromCallable(() -> {
                                Map<String, Object> result = new HashMap<>();
                                result.put("chapterId", chapterId);
                                result.put("chapter", newChapter);
                                result.put("sceneId", sceneId);
                                result.put("scene", newScene);
                                return result;
                            }));
                })
                .doOnSuccess(result -> log.info("成功原子化插入章节与场景: novelId={}, actId={}, afterChapterId={}, newChapterId={}, sceneId={}",
                        novelId, actId, insertAfterChapterId, result.get("chapterId"), result.get("sceneId")))
                .doOnError(e -> log.error("原子化插入章节与场景失败: novelId={}, actId={}, afterChapterId={}, error={}",
                        novelId, actId, insertAfterChapterId, e.getMessage()));
    }
    
    @Override
    public Mono<Boolean> deleteActFine(String novelId, String actId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.just(false); // 结构不存在，无需删除
                    }
                    
                    // 查找并移除指定的卷
                    Act removedAct = null;
                    Iterator<Act> actIterator = structure.getActs().iterator();
                    while (actIterator.hasNext()) {
                        Act act = actIterator.next();
                        if (act.getId().equals(actId)) {
                            removedAct = act;
                            actIterator.remove();
                            break;
                        }
                    }
                    
                    if (removedAct == null) {
                        return Mono.just(false); // 卷不存在，无需删除
                    }
                    
                    // 收集被删除卷中的所有章节ID
                    List<String> removedChapterIds = new ArrayList<>();
                    if (removedAct.getChapters() != null) {
                        for (Chapter chapter : removedAct.getChapters()) {
                            removedChapterIds.add(chapter.getId());
                        }
                    }
                    
                    // 检查最后编辑的章节ID是否需要更新
                    if (novel.getLastEditedChapterId() != null && 
                            removedChapterIds.contains(novel.getLastEditedChapterId())) {
                        // 最后编辑的章节被删除，需要更新
                        String newLastEditedChapterId = null;
                        
                        // 寻找其他卷中的章节作为新的最后编辑章节
                        for (Act act : structure.getActs()) {
                            if (act.getChapters() != null && !act.getChapters().isEmpty()) {
                                newLastEditedChapterId = act.getChapters().get(0).getId();
                                break;
                            }
                        }
                        
                        novel.setLastEditedChapterId(newLastEditedChapterId);
                    }
                    
                    // 更新时间戳
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 保存更新后的小说结构
                    return novelRepository.save(novel)
                            .flatMap(savedNovel -> {
                                // 删除所有相关章节的场景
                                List<Mono<Void>> deleteOperations = new ArrayList<>();
                                for (String chapterId : removedChapterIds) {
                                    deleteOperations.add(sceneService.deleteScenesByChapterId(chapterId));
                                }
                                
                                if (deleteOperations.isEmpty()) {
                                    return Mono.just(true);
                                }
                                
                                return Mono.when(deleteOperations)
                                        .thenReturn(true);
                            });
                })
                .doOnSuccess(success -> {
                    if (success) {
                        log.info("成功删除卷: novelId={}, actId={}", novelId, actId);
                    } else {
                        log.warn("删除卷失败: 卷不存在, novelId={}, actId={}", novelId, actId);
                    }
                })
                .doOnError(e -> log.error("删除卷出错: novelId={}, actId={}, error={}", 
                        novelId, actId, e.getMessage()))
                .onErrorResume(e -> {
                    log.error("删除卷发生异常: ", e);
                    return Mono.just(false);
                });
    }
    
    @Override
    public Mono<Boolean> deleteChapterFine(String novelId, String actId, String chapterId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取小说结构
                    Structure structure = novel.getStructure();
                    if (structure == null || structure.getActs() == null) {
                        return Mono.just(false); // 结构不存在，无需删除
                    }
                    
                    // 查找指定的卷
                    Act targetAct = null;
                    for (Act act : structure.getActs()) {
                        if (act.getId().equals(actId)) {
                            targetAct = act;
                            break;
                        }
                    }
                    
                    if (targetAct == null || targetAct.getChapters() == null) {
                        return Mono.just(false); // 卷不存在或没有章节，无需删除
                    }
                    
                    // 查找并移除指定的章节
                    boolean chapterRemoved = false;
                    Iterator<Chapter> chapterIterator = targetAct.getChapters().iterator();
                    while (chapterIterator.hasNext()) {
                        Chapter chapter = chapterIterator.next();
                        if (chapter.getId().equals(chapterId)) {
                            chapterIterator.remove();
                            chapterRemoved = true;
                            break;
                        }
                    }
                    
                    if (!chapterRemoved) {
                        return Mono.just(false); // 章节不存在，无需删除
                    }
                    
                    // 检查最后编辑的章节ID是否需要更新
                    if (chapterId.equals(novel.getLastEditedChapterId())) {
                        // 最后编辑的章节被删除，需要更新
                        String newLastEditedChapterId = null;
                        
                        // 优先在同一卷中查找章节
                        if (targetAct.getChapters() != null && !targetAct.getChapters().isEmpty()) {
                            newLastEditedChapterId = targetAct.getChapters().get(0).getId();
                        } else {
                            // 在其他卷中查找章节
                            for (Act act : structure.getActs()) {
                                if (act.getChapters() != null && !act.getChapters().isEmpty()) {
                                    newLastEditedChapterId = act.getChapters().get(0).getId();
                                    break;
                                }
                            }
                        }
                        
                        novel.setLastEditedChapterId(newLastEditedChapterId);
                    }
                    
                    // 更新时间戳
                    novel.setUpdatedAt(LocalDateTime.now());
                    
                    // 保存更新后的小说结构
                    return novelRepository.save(novel)
                            .then(sceneService.deleteScenesByChapterId(chapterId))
                            .thenReturn(true);
                })
                .doOnSuccess(success -> {
                    if (success) {
                        log.info("成功删除章节: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
                    } else {
                        log.warn("删除章节失败: 章节不存在, novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
                    }
                })
                .doOnError(e -> log.error("删除章节出错: novelId={}, actId={}, chapterId={}, error={}", 
                        novelId, actId, chapterId, e.getMessage()))
                .onErrorResume(e -> {
                    log.error("删除章节发生异常: ", e);
                    return Mono.just(false);
                });
    }

    /**
     * 智能合并小说结构
     * 策略：保留前端对标题、顺序等的修改，同时避免前端更新覆盖后台生成的内容
     */
    private void smartMergeNovelStructure(Novel existingNovel, Novel updatedNovel) {
        if (existingNovel.getStructure() == null) {
            // 数据库中没有结构，直接使用前端的结构
            existingNovel.setStructure(updatedNovel.getStructure());
            return;
        }
        
        if (updatedNovel.getStructure() == null) {
            // 前端没有提供结构，保留现有结构
            return;
        }
        
        // 构建现有章节和场景的映射，以便快速查找
        Map<String, Chapter> existingChaptersMap = new HashMap<>();
        Map<String, Set<String>> existingChapterScenesMap = new HashMap<>();
        buildChapterAndSceneMap(existingNovel, existingChaptersMap, existingChapterScenesMap);
        
        // 合并卷结构
        List<Act> mergedActs = new ArrayList<>();
        
        if (updatedNovel.getStructure().getActs() != null) {
            for (Act updatedAct : updatedNovel.getStructure().getActs()) {
                // 在现有结构中查找对应的卷
                Act existingAct = findActById(existingNovel, updatedAct.getId());
                
                Act mergedAct;
                if (existingAct == null) {
                    // 全新的卷，直接添加
                    mergedAct = updatedAct;
                    log.info("智能合并: 添加全新卷 {}", updatedAct.getId());
                } else {
                    // 合并章节内容
                    List<Chapter> mergedChapters = smartMergeChapters(
                        existingAct.getChapters(), 
                        updatedAct.getChapters(),
                        existingChaptersMap,
                        existingChapterScenesMap
                    );
                    
                    // 使用更新后的卷信息，但保留合并后的章节
                    mergedAct = new Act();
                    mergedAct.setId(updatedAct.getId());
                    mergedAct.setTitle(updatedAct.getTitle());
                    mergedAct.setDescription(updatedAct.getDescription());
                    mergedAct.setOrder(updatedAct.getOrder());
                    mergedAct.setMetadata(updatedAct.getMetadata());
                    mergedAct.setChapters(mergedChapters);
                    
                    log.info("智能合并: 更新卷 {}, 标题: {}, 合并后章节数: {}", 
                        mergedAct.getId(), mergedAct.getTitle(), mergedChapters.size());
                }
                
                mergedActs.add(mergedAct);
            }
        }
        
        // 检查是否有需要保留的现有卷（前端可能删除了一些卷）
        if (existingNovel.getStructure().getActs() != null) {
            for (Act existingAct : existingNovel.getStructure().getActs()) {
                boolean actExists = false;
                if (updatedNovel.getStructure().getActs() != null) {
                    for (Act updatedAct : updatedNovel.getStructure().getActs()) {
                        if (updatedAct.getId().equals(existingAct.getId())) {
                            actExists = true;
                            break;
                        }
                    }
                }
                
                if (!actExists) {
                    // 检查该卷中是否有近期生成的章节（例如过去24小时内）
                    boolean hasRecentGeneratedChapters = checkForRecentGeneratedChapters(existingAct);
                    if (hasRecentGeneratedChapters) {
                        // 保留含有最近生成章节的卷
                        mergedActs.add(existingAct);
                        log.warn("智能合并: 保留前端已删除但含有最近生成章节的卷 {}", existingAct.getId());
                    }
                }
            }
        }
        
        // 设置合并后的结构
        existingNovel.getStructure().setActs(mergedActs);
        log.info("智能合并完成: 合并后卷数量 {}", mergedActs.size());
    }

    /**
     * 构建章节和场景映射
     */
    private void buildChapterAndSceneMap(Novel novel, 
                                        Map<String, Chapter> chaptersMap, 
                                        Map<String, Set<String>> chapterScenesMap) {
        if (novel.getStructure() != null && novel.getStructure().getActs() != null) {
            for (Act act : novel.getStructure().getActs()) {
                if (act.getChapters() != null) {
                    for (Chapter chapter : act.getChapters()) {
                        chaptersMap.put(chapter.getId(), chapter);
                        
                        if (chapter.getSceneIds() != null) {
                            chapterScenesMap.put(chapter.getId(), new HashSet<>(chapter.getSceneIds()));
                        }
                    }
                }
            }
        }
    }

    /**
     * 根据ID查找卷
     */
    private Act findActById(Novel novel, String actId) {
        if (novel.getStructure() != null && novel.getStructure().getActs() != null) {
            for (Act act : novel.getStructure().getActs()) {
                if (act.getId().equals(actId)) {
                    return act;
                }
            }
        }
        return null;
    }

    /**
     * 智能合并章节列表
     */
    private List<Chapter> smartMergeChapters(
        List<Chapter> existingChapters, 
        List<Chapter> updatedChapters,
        Map<String, Chapter> existingChaptersMap,
        Map<String, Set<String>> existingChapterScenesMap
    ) {
        // 无需合并的情况
        if (existingChapters == null || existingChapters.isEmpty()) {
            return updatedChapters;
        }
        if (updatedChapters == null || updatedChapters.isEmpty()) {
            return existingChapters;
        }
        
        List<Chapter> mergedChapters = new ArrayList<>();
        
        // 对前端提交的章节列表进行处理
        for (Chapter updatedChapter : updatedChapters) {
            // 先判断是否是现有章节
            Chapter existingChapter = existingChaptersMap.get(updatedChapter.getId());
            
            if (existingChapter == null) {
                // 全新的章节，直接添加
                mergedChapters.add(updatedChapter);
                log.info("智能合并章节: 添加新章节 {}", updatedChapter.getId());
                continue;
            }
            
            // 章节已存在，需要合并场景信息
            Chapter mergedChapter = new Chapter();
            // 基本属性使用前端提交的版本
            mergedChapter.setId(updatedChapter.getId());
            mergedChapter.setTitle(updatedChapter.getTitle());
            mergedChapter.setOrder(updatedChapter.getOrder());
            mergedChapter.setMetadata(updatedChapter.getMetadata());
            
            // 智能合并场景ID列表
            List<String> mergedSceneIds = smartMergeSceneIds(
                existingChapter.getSceneIds(),
                updatedChapter.getSceneIds(),
                existingChapterScenesMap.get(updatedChapter.getId()),
                isRecentGenerated(existingChapter)
            );
            
            mergedChapter.setSceneIds(mergedSceneIds);
            mergedChapters.add(mergedChapter);
        }
        
        // 检查是否有需要保留的章节（前端删除但后台刚生成的）
        for (Chapter existingChapter : existingChapters) {
            boolean chapterExists = false;
            for (Chapter updatedChapter : updatedChapters) {
                if (updatedChapter.getId().equals(existingChapter.getId())) {
                    chapterExists = true;
                    break;
                }
            }
            
            if (!chapterExists && isRecentGenerated(existingChapter)) {
                // 前端删除了一个最近生成的章节，需要保留
                mergedChapters.add(existingChapter);
                log.warn("智能合并章节: 保留前端已删除但最近生成的章节 {}", existingChapter.getId());
            }
        }
        
        return mergedChapters;
    }

    /**
     * 判断章节是否是最近生成的
     * 可以基于时间戳或特定的元数据标记
     */
    private boolean isRecentGenerated(Chapter chapter) {
        if (chapter.getMetadata() != null) {
            // 检查是否有自动生成的标记
            Object isGenerated = chapter.getMetadata().get("isAutoGenerated");
            if (isGenerated instanceof Boolean && (Boolean) isGenerated) {
                // 检查生成时间
                Object generatedTime = chapter.getMetadata().get("generatedTimestamp");
                if (generatedTime instanceof Long) {
                    long timestamp = (Long) generatedTime;
                    // 检查是否在过去24小时内生成
                    return System.currentTimeMillis() - timestamp < 24 * 60 * 60 * 1000;
                }
                return true; // 如果有生成标记但没有时间戳，默认保留
            }
        }
        return false;
    }

    /**
     * 检查卷中是否有最近生成的章节
     */
    private boolean checkForRecentGeneratedChapters(Act act) {
        if (act.getChapters() != null) {
            for (Chapter chapter : act.getChapters()) {
                if (isRecentGenerated(chapter)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 智能合并场景ID列表
     */
    private List<String> smartMergeSceneIds(
        List<String> existingSceneIds, 
        List<String> updatedSceneIds,
        Set<String> originalSceneIdsSet,
        boolean isRecentGenerated
    ) {
        // 无需合并的情况
        if (existingSceneIds == null || existingSceneIds.isEmpty()) {
            return updatedSceneIds;
        }
        if (updatedSceneIds == null || updatedSceneIds.isEmpty()) {
            return existingSceneIds;
        }
        
        // 如果是最近生成的章节，且场景列表有变化，需要保留原有场景
        if (isRecentGenerated) {
            Set<String> updatedSceneIdsSet = new HashSet<>(updatedSceneIds);
            
            // 检查是否有场景被删除
            boolean hasSceneRemoved = false;
            if (originalSceneIdsSet != null) {
                for (String originalSceneId : originalSceneIdsSet) {
                    if (!updatedSceneIdsSet.contains(originalSceneId)) {
                        hasSceneRemoved = true;
                        break;
                    }
                }
            }
            
            if (hasSceneRemoved) {
                log.warn("智能合并场景: 前端尝试删除最近生成章节的场景，保留原有场景列表");
                return existingSceneIds;
            }
        }
        
        // 默认使用前端提交的场景列表
        return updatedSceneIds;
    }

    /**
     * 获取指定章节的前一个章节ID
     *
     * @param novelId 小说ID
     * @param chapterId 当前章节ID
     * @return 前一个章节的ID
     */
    @Override
    public Mono<String> getPreviousChapterId(String novelId, String chapterId) {
        return findNovelById(novelId)
            .flatMap(novel -> {
                // 获取所有章节的有序列表
                List<String> chapterIds = new ArrayList<>();
                if (novel.getStructure() != null && novel.getStructure().getActs() != null) {
                    for (Act act : novel.getStructure().getActs()) {
                        if (act.getChapters() != null) {
                            for (Chapter chapter : act.getChapters()) {
                                chapterIds.add(chapter.getId());
                            }
                        }
                    }
                }
                
                // 找到当前章节的索引
                int currentIndex = chapterIds.indexOf(chapterId);
                if (currentIndex <= 0) {
                    // 如果是第一章或未找到，则返回空
                    return Mono.empty();
                }
                
                // 否则返回前一章的ID
                return Mono.just(chapterIds.get(currentIndex - 1));
            });
    }

    @Override
    public Mono<NovelWithScenesDto> getChaptersAfter(String novelId, String currentChapterId, int chaptersLimit, boolean includeCurrentChapter) {
        log.info("获取当前章节后面的章节: novelId={}, currentChapterId={}, chaptersLimit={}, includeCurrentChapter={}", 
                novelId, currentChapterId, chaptersLimit, includeCurrentChapter);
        
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取所有章节ID，并保持它们的顺序
                    List<String> allChapterIds = new ArrayList<>();
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        for (Novel.Chapter chapter : act.getChapters()) {
                            allChapterIds.add(chapter.getId());
                        }
                    }

                    // 如果没有章节，直接返回只有小说信息的DTO
                    if (allChapterIds.isEmpty()) {
                        return Mono.just(NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 找到当前章节的索引
                    int currentIndex = allChapterIds.indexOf(currentChapterId);
                    if (currentIndex == -1) {
                        log.warn("找不到指定的当前章节: {}, 将从第一章开始加载", currentChapterId);
                        currentIndex = -1; // 从第一章开始
                    }

                    // 确定要加载的章节范围
                    List<String> chapterIdsToLoad;
                    if (currentIndex == -1) {
                        // 从第一章开始加载
                        int endIndex = Math.min(allChapterIds.size(), chaptersLimit);
                        chapterIdsToLoad = allChapterIds.subList(0, endIndex);
                        log.info("从第一章开始加载，加载章节数: {}", chapterIdsToLoad.size());
                    } else if (currentIndex >= allChapterIds.size() - 1 && !includeCurrentChapter) {
                        // 已经是最后一章且不包含当前章节，没有后续章节
                        log.info("已经是最后一章且不包含当前章节，没有后续章节可加载");
                        return Mono.just(NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(new HashMap<>())
                                .build());
                    } else {
                        // 根据includeCurrentChapter参数确定起始位置
                        int startIndex;
                        if (includeCurrentChapter) {
                            // 包含当前章节
                            startIndex = Math.max(0, currentIndex);
                            log.info("包含当前章节，从章节索引{}开始加载", startIndex);
                        } else {
                            // 不包含当前章节，从下一章开始
                            startIndex = currentIndex + 1;
                            log.info("不包含当前章节，从章节索引{}开始加载", startIndex);
                        }
                        
                        // 检查是否有章节可加载
                        if (startIndex >= allChapterIds.size()) {
                            log.info("没有更多章节可加载");
                            return Mono.just(NovelWithScenesDto.builder()
                                    .novel(novel)
                                    .scenesByChapter(new HashMap<>())
                                    .build());
                        }
                        
                        int endIndex = Math.min(allChapterIds.size(), startIndex + chaptersLimit);
                        chapterIdsToLoad = allChapterIds.subList(startIndex, endIndex);
                        log.info("最终加载章节范围: {} 到 {}, 共{}章", startIndex, endIndex - 1, chapterIdsToLoad.size());
                    }

                    // 如果没有章节可加载，返回空结果
                    if (chapterIdsToLoad.isEmpty()) {
                        return Mono.just(NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 查询指定章节的场景并按章节分组
                    return Flux.fromIterable(chapterIdsToLoad)
                            .flatMap(sceneRepository::findByChapterId)
                            .collectList()
                            .map(scenes -> {
                                // 按章节ID分组
                                Map<String, List<Scene>> scenesByChapter = scenes.stream().map(scene -> {
                                    scene.setContent(RichTextUtil.deltaJsonToPlainText(scene.getContent()));
                                    return scene;
                                })
                                        .collect(Collectors.groupingBy(Scene::getChapterId));

                                // 构建并返回DTO
                                return NovelWithScenesDto.builder()
                                        .novel(novel)
                                        .scenesByChapter(scenesByChapter)
                                        .build();
                            });
                })
                .doOnSuccess(dto -> log.info("获取当前章节后面的章节成功，小说ID: {}, 当前章节ID: {}, 加载章节数: {}",
                        novelId, currentChapterId, dto.getScenesByChapter().size()))
                .doOnError(e -> log.error("获取当前章节后面的章节失败", e));
    }

    @Override
    public Mono<ChaptersForPreloadDto> getChaptersForPreload(String novelId, String currentChapterId, int chaptersLimit, boolean includeCurrentChapter) {
        log.info("获取章节列表用于预加载: novelId={}, currentChapterId={}, chaptersLimit={}, includeCurrentChapter={}", 
                novelId, currentChapterId, chaptersLimit, includeCurrentChapter);
        
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMap(novel -> {
                    // 获取所有章节ID，并保持它们的顺序
                    List<Chapter> allChapters = new ArrayList<>();
                    for (Novel.Act act : novel.getStructure().getActs()) {
                        allChapters.addAll(act.getChapters());
                    }

                    // 如果没有章节，直接返回空结果
                    if (allChapters.isEmpty()) {
                        return Mono.just(ChaptersForPreloadDto.builder()
                                .chapters(new ArrayList<>())
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 找到当前章节的索引
                    int currentIndex = -1;
                    for (int i = 0; i < allChapters.size(); i++) {
                        if (allChapters.get(i).getId().equals(currentChapterId)) {
                            currentIndex = i;
                            break;
                        }
                    }
                    
                    if (currentIndex == -1) {
                        log.warn("找不到指定的当前章节: {}, 将从第一章开始加载", currentChapterId);
                        currentIndex = -1; // 从第一章开始
                    }

                    // 确定要加载的章节范围
                    List<Chapter> chaptersToLoad;
                    if (currentIndex == -1) {
                        // 从第一章开始加载
                        int endIndex = Math.min(allChapters.size(), chaptersLimit);
                        chaptersToLoad = allChapters.subList(0, endIndex);
                        log.info("从第一章开始加载，加载章节数: {}", chaptersToLoad.size());
                    } else if (currentIndex >= allChapters.size() - 1 && !includeCurrentChapter) {
                        // 已经是最后一章且不包含当前章节，没有后续章节
                        log.info("已经是最后一章且不包含当前章节，没有后续章节可加载");
                        return Mono.just(ChaptersForPreloadDto.builder()
                                .chapters(new ArrayList<>())
                                .scenesByChapter(new HashMap<>())
                                .build());
                    } else {
                        // 根据includeCurrentChapter参数确定起始位置
                        int startIndex;
                        if (includeCurrentChapter) {
                            // 包含当前章节
                            startIndex = Math.max(0, currentIndex);
                            log.info("包含当前章节，从章节索引{}开始加载", startIndex);
                        } else {
                            // 不包含当前章节，从下一章开始
                            startIndex = currentIndex + 1;
                            log.info("不包含当前章节，从章节索引{}开始加载", startIndex);
                        }
                        
                        // 检查是否有章节可加载
                        if (startIndex >= allChapters.size()) {
                            log.info("没有更多章节可加载");
                            return Mono.just(ChaptersForPreloadDto.builder()
                                    .chapters(new ArrayList<>())
                                    .scenesByChapter(new HashMap<>())
                                    .build());
                        }
                        
                        int endIndex = Math.min(allChapters.size(), startIndex + chaptersLimit);
                        chaptersToLoad = allChapters.subList(startIndex, endIndex);
                        log.info("最终加载章节范围: {} 到 {}, 共{}章", startIndex, endIndex - 1, chaptersToLoad.size());
                    }

                    // 如果没有章节可加载，返回空结果
                    if (chaptersToLoad.isEmpty()) {
                        return Mono.just(ChaptersForPreloadDto.builder()
                                .chapters(new ArrayList<>())
                                .scenesByChapter(new HashMap<>())
                                .build());
                    }

                    // 提取章节ID列表
                    List<String> chapterIdsToLoad = chaptersToLoad.stream()
                            .map(Chapter::getId)
                            .collect(Collectors.toList());

                    // 查询指定章节的场景并按章节分组
                    return Flux.fromIterable(chapterIdsToLoad)
                            .flatMap(sceneRepository::findByChapterId)
                            .collectList()
                            .map(scenes -> {
                                // 按章节ID分组场景
                                Map<String, List<Scene>> scenesByChapter = scenes.stream()
                                        .map(scene -> {
                                            // 转换场景内容为纯文本
                                            scene.setContent(RichTextUtil.deltaJsonToPlainText(scene.getContent()));
                                            return scene;
                                        })
                                        .collect(Collectors.groupingBy(Scene::getChapterId));

                                // 构建并返回DTO
                                return ChaptersForPreloadDto.builder()
                                        .chapters(chaptersToLoad)
                                        .scenesByChapter(scenesByChapter)
                                        .build();
                            });
                })
                .doOnSuccess(result -> {
                    log.info("获取章节列表用于预加载成功，小说ID: {}, 当前章节ID: {}, 加载章节数: {}, 场景章节数: {}",
                            novelId, currentChapterId, result.getChapterCount(), result.getScenesByChapter().size());
                })
                .doOnError(e -> log.error("获取章节列表用于预加载失败", e));
    }

    @Override
    public Mono<NovelWithScenesDto> getNovelWithAllScenesText(String id) {
        return novelRepository.findById(id)
        .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", id)))
        .flatMap(novel -> {
            // 获取所有章节ID
            List<String> allChapterIds = new ArrayList<>();
            for (Novel.Act act : novel.getStructure().getActs()) {
                for (Novel.Chapter chapter : act.getChapters()) {
                    allChapterIds.add(chapter.getId());
                }
            }

            // 如果没有章节，直接返回只有小说信息的DTO
            if (allChapterIds.isEmpty()) {
                return Mono.just(NovelWithScenesDto.builder()
                        .novel(novel)
                        .scenesByChapter(new HashMap<>())
                        .build());
            }

            // 查询所有场景并按章节分组
            return sceneRepository.findByNovelId(id)
                    .collectList()
                    .map(scenes -> {
                        // 按章节ID分组
                        Map<String, List<Scene>> scenesByChapter = scenes.stream().map(scene -> {
                            scene.setContent(RichTextUtil.deltaJsonToPlainText(scene.getContent()));
                            return scene;
                        })
                                .collect(Collectors.groupingBy(Scene::getChapterId));

                        // 构建并返回DTO
                        return NovelWithScenesDto.builder()
                                .novel(novel)
                                .scenesByChapter(scenesByChapter)
                                .build();
                    });
        })
        .doOnSuccess(dto -> log.info("获取小说及其所有场景成功，小说ID: {}", id));
    }

    /**
     * 按照小说结构顺序获取所有场景
     * 替代 sceneService.findScenesByNovelIdOrdered 方法
     * 按照卷顺序 -> 章节顺序 -> 场景sequence排序
     * 
     * @param novelId 小说ID
     * @return 按顺序排列的场景列表
     */
    public Flux<Scene> findScenesByNovelIdInOrder(String novelId) {
        return novelRepository.findById(novelId)
                .switchIfEmpty(Mono.error(new ResourceNotFoundException("小说", novelId)))
                .flatMapMany(novel -> {
                    // 检查小说结构是否存在
                    if (novel.getStructure() == null || novel.getStructure().getActs() == null) {
                        log.warn("小说 {} 没有结构信息，返回空场景列表", novelId);
                        return Flux.empty();
                    }

                    // 按照卷顺序和章节顺序收集所有章节ID
                    List<String> orderedChapterIds = new ArrayList<>();
                    
                    // 按卷的order排序（如果有的话），否则按列表顺序
                    List<Act> sortedActs = novel.getStructure().getActs().stream()
                            .sorted((a, b) -> {
                                Integer orderA = a.getOrder();
                                Integer orderB = b.getOrder();
                                if (orderA != null && orderB != null) {
                                    return Integer.compare(orderA, orderB);
                                }
                                // 如果没有order字段，保持原有顺序
                                return 0;
                            })
                            .collect(Collectors.toList());

                    for (Act act : sortedActs) {
                        if (act.getChapters() != null) {
                            // 按章节的order排序（如果有的话），否则按列表顺序
                            List<Chapter> sortedChapters = act.getChapters().stream()
                                    .sorted((a, b) -> {
                                        Integer orderA = a.getOrder();
                                        Integer orderB = b.getOrder();
                                        if (orderA != null && orderB != null) {
                                            return Integer.compare(orderA, orderB);
                                        }
                                        // 如果没有order字段，保持原有顺序
                                        return 0;
                                    })
                                    .collect(Collectors.toList());
                            
                            for (Chapter chapter : sortedChapters) {
                                orderedChapterIds.add(chapter.getId());
                            }
                        }
                    }

                    if (orderedChapterIds.isEmpty()) {
                        log.info("小说 {} 没有章节，返回空场景列表", novelId);
                        return Flux.empty();
                    }

                    log.debug("小说 {} 按顺序的章节ID数量: {}", novelId, orderedChapterIds.size());

                    // 🚀 单次按小说ID取回所有场景，内存中按章节顺序与场景sequence排序，避免逐章节 N 次查询
                    return sceneRepository.findByNovelId(novelId)
                            .collectList()
                            .flatMapMany(allScenes -> {
                                if (allScenes.isEmpty()) {
                                    return Flux.empty();
                                }

                                // 章节顺序映射：chapterId -> 顺序索引
                                Map<String, Integer> chapterOrderIndex = new HashMap<>();
                                for (int i = 0; i < orderedChapterIds.size(); i++) {
                                    chapterOrderIndex.put(orderedChapterIds.get(i), i);
                                }

                                // 按章节顺序索引 + 场景sequence 排序
                                allScenes.sort((s1, s2) -> {
                                    Integer idx1 = chapterOrderIndex.getOrDefault(s1.getChapterId(), Integer.MAX_VALUE);
                                    Integer idx2 = chapterOrderIndex.getOrDefault(s2.getChapterId(), Integer.MAX_VALUE);
                                    int cmp = Integer.compare(idx1, idx2);
                                    if (cmp != 0) return cmp;
                                    Integer seq1 = s1.getSequence() == null ? Integer.MAX_VALUE : s1.getSequence();
                                    Integer seq2 = s2.getSequence() == null ? Integer.MAX_VALUE : s2.getSequence();
                                    return Integer.compare(seq1, seq2);
                                });

                                log.debug("小说 {} 全量场景载入完成: {} 个", novelId, allScenes.size());
                                return Flux.fromIterable(allScenes);
                            });
                })
                .doOnComplete(() -> log.debug("完成获取小说 {} 的有序场景列表", novelId))
                .doOnError(error -> log.warn("获取小说 {} 的有序场景列表失败: {}", novelId, error.getMessage()));
    }

    /**
     * 获取包含索引（章节/场景包含关系）
     */
    public Mono<ContainIndex> getContainIndex(String novelId) {
        return structureCache.getIndex(novelId, () ->
                this.findScenesByNovelIdInOrder(novelId)
                    .collectList()
                    .map(NovelStructureCache::buildIndex));
    }

    /**
     * 当小说结构被修改（增删章节/场景）时调用以失效缓存。
     */
    private void invalidateStructureCache(String novelId) {
        structureCache.evict(novelId);
    }

}
