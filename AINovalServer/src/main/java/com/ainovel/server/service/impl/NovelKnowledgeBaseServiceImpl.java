package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.NovelKnowledgeBase;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.domain.model.UserKnowledgeBaseRelation;
import com.ainovel.server.repository.NovelKnowledgeBaseRepository;
import com.ainovel.server.repository.UserKnowledgeBaseRelationRepository;
import com.ainovel.server.repository.UserRepository;
import com.ainovel.server.service.NovelKnowledgeBaseService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.NovelSettingService;
import com.ainovel.server.web.dto.request.KnowledgeBaseQueryRequest;
import com.ainovel.server.web.dto.response.KnowledgeBaseDetailResponse;
import com.ainovel.server.web.dto.response.KnowledgeBaseListResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 小说知识库服务实现
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class NovelKnowledgeBaseServiceImpl implements NovelKnowledgeBaseService {
    
    private final NovelKnowledgeBaseRepository repository;
    private final UserKnowledgeBaseRelationRepository relationRepository;
    private final NovelSettingService novelSettingService;
    private final NovelService novelService;
    private final UserRepository userRepository;
    
    @Override
    public Mono<NovelKnowledgeBase> getByFanqieNovelId(String fanqieNovelId) {
        log.info("根据番茄小说ID查询知识库: {}", fanqieNovelId);
        return repository.findByFanqieNovelId(fanqieNovelId);
    }
    
    @Override
    public Mono<NovelKnowledgeBase> getById(String knowledgeBaseId) {
        log.info("根据ID查询知识库: {}", knowledgeBaseId);
        return repository.findById(knowledgeBaseId);
    }
    
    @Override
    public Mono<NovelKnowledgeBase> create(NovelKnowledgeBase knowledgeBase) {
        log.info("创建知识库: {}", knowledgeBase.getTitle());
        knowledgeBase.setCreatedAt(LocalDateTime.now());
        knowledgeBase.setUpdatedAt(LocalDateTime.now());
        return repository.save(knowledgeBase);
    }
    
    @Override
    public Mono<NovelKnowledgeBase> update(NovelKnowledgeBase knowledgeBase) {
        log.info("更新知识库: {}", knowledgeBase.getId());
        knowledgeBase.setUpdatedAt(LocalDateTime.now());
        return repository.save(knowledgeBase);
    }
    
    @Override
    public Mono<NovelKnowledgeBase> incrementReferenceCount(String knowledgeBaseId) {
        log.info("增加知识库引用次数: {}", knowledgeBaseId);
        return repository.findById(knowledgeBaseId)
                .flatMap(kb -> {
                    kb.setReferenceCount(kb.getReferenceCount() + 1);
                    kb.setUpdatedAt(LocalDateTime.now());
                    return repository.save(kb);
                });
    }
    
    @Override
    public Mono<NovelKnowledgeBase> incrementViewCount(String knowledgeBaseId) {
        log.info("增加知识库查看次数: {}", knowledgeBaseId);
        return repository.findById(knowledgeBaseId)
                .flatMap(kb -> {
                    kb.setViewCount(kb.getViewCount() + 1);
                    kb.setUpdatedAt(LocalDateTime.now());
                    return repository.save(kb);
                });
    }
    
    @Override
    public Mono<Boolean> toggleLike(String knowledgeBaseId, String userId) {
        log.info("切换点赞状态: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        return repository.findById(knowledgeBaseId)
                .flatMap(kb -> {
                    boolean nowLiked;
                    String authorId = kb.getFirstImportUserId();
                    
                    if (kb.getLikedUserIds().contains(userId)) {
                        // 取消点赞
                        kb.getLikedUserIds().remove(userId);
                        kb.setLikeCount(Math.max(0, kb.getLikeCount() - 1));
                        nowLiked = false;
                        
                        // 扣除作者1积分
                        return userRepository.findById(authorId)
                                .flatMap(author -> {
                                    author.deductCredits(1L);
                                    return userRepository.save(author);
                                })
                                .then(repository.save(kb))
                                .thenReturn(nowLiked)
                                .onErrorResume(e -> {
                                    log.warn("扣除作者积分失败: authorId={}", authorId, e);
                                    return repository.save(kb).thenReturn(nowLiked);
                                });
                    } else {
                        // 添加点赞
                        kb.getLikedUserIds().add(userId);
                        kb.setLikeCount(kb.getLikeCount() + 1);
                        nowLiked = true;
                        
                        // 作者获得1积分
                        return userRepository.findById(authorId)
                                .flatMap(author -> {
                                    author.addCredits(1L);
                                    return userRepository.save(author);
                                })
                                .then(repository.save(kb))
                                .thenReturn(nowLiked)
                                .onErrorResume(e -> {
                                    log.warn("增加作者积分失败: authorId={}", authorId, e);
                                    return repository.save(kb).thenReturn(nowLiked);
                                });
                    }
                });
    }
    
    @Override
    public Mono<Boolean> togglePublic(String knowledgeBaseId, String userId) {
        log.info("切换公开状态: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        return repository.findById(knowledgeBaseId)
                .flatMap(kb -> {
                    // 验证权限：只有所有者可以操作
                    if (!kb.getFirstImportUserId().equals(userId)) {
                        return Mono.error(new IllegalAccessException("只有知识库所有者可以设置分享状态"));
                    }
                    
                    // 切换公开状态
                    Boolean newPublicStatus = !kb.getIsPublic();
                    kb.setIsPublic(newPublicStatus);
                    kb.setUpdatedAt(LocalDateTime.now());
                    
                    return repository.save(kb)
                            .thenReturn(newPublicStatus);
                })
                .onErrorResume(IllegalAccessException.class, e -> {
                    log.error("权限验证失败: {}", e.getMessage());
                    return Mono.error(new RuntimeException("权限不足"));
                });
    }
    
    @Override
    public Mono<Void> recordReference(String knowledgeBaseId, String userId) {
        log.info("记录知识库引用: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        return incrementReferenceCount(knowledgeBaseId)
                .flatMap(kb -> {
                    // 为作者增加1积分
                    String authorId = kb.getFirstImportUserId();
                    return userRepository.findById(authorId)
                            .flatMap(author -> {
                                author.addCredits(1L);
                                return userRepository.save(author);
                            })
                            .doOnSuccess(author -> log.info("知识库引用积分奖励: authorId={}, knowledgeBaseId={}", 
                                    authorId, knowledgeBaseId))
                            .onErrorResume(e -> {
                                log.warn("增加引用积分失败: authorId={}, error={}", authorId, e.getMessage());
                                return Mono.empty();
                            })
                            .then();
                });
    }
    
    @Override
    public Mono<KnowledgeBaseListResponse> queryPublicKnowledgeBases(KnowledgeBaseQueryRequest request) {
        log.info("查询公共知识库列表: keyword={}, page={}, size={}, sortBy={}", 
                request.getKeyword(), request.getPage(), request.getSize(), request.getSortBy());
        
        // 构建排序
        Sort sort = buildSort(request.getSortBy(), request.getSortOrder());
        PageRequest pageRequest = PageRequest.of(request.getPage(), request.getSize(), sort);
        
        // 查询数据（带keyword过滤）
        Flux<NovelKnowledgeBase> queryFlux;
        Mono<Long> countMono;
        
        if (request.getKeyword() != null && !request.getKeyword().trim().isEmpty()) {
            // 有keyword，进行标题或作者搜索
            String keyword = request.getKeyword().trim();
            log.info("使用关键词搜索: {}", keyword);
            queryFlux = repository.findByIsPublicTrueAndStatus(NovelKnowledgeBase.CacheStatus.COMPLETED, pageRequest)
                    .filter(kb -> {
                        // 前端过滤：标题或作者包含关键词
                        boolean matchTitle = kb.getTitle() != null && 
                                kb.getTitle().toLowerCase().contains(keyword.toLowerCase());
                        boolean matchAuthor = kb.getAuthor() != null && 
                                kb.getAuthor().toLowerCase().contains(keyword.toLowerCase());
                        return matchTitle || matchAuthor;
                    });
            
            // 统计时也要过滤（查询所有，不分页）
            countMono = repository.findByIsPublicTrueAndStatus(
                            NovelKnowledgeBase.CacheStatus.COMPLETED, 
                            PageRequest.of(0, Integer.MAX_VALUE))
                    .filter(kb -> {
                        boolean matchTitle = kb.getTitle() != null && 
                                kb.getTitle().toLowerCase().contains(keyword.toLowerCase());
                        boolean matchAuthor = kb.getAuthor() != null && 
                                kb.getAuthor().toLowerCase().contains(keyword.toLowerCase());
                        return matchTitle || matchAuthor;
                    })
                    .count();
        } else {
            // 无keyword，查询所有
            queryFlux = repository.findByIsPublicTrueAndStatus(NovelKnowledgeBase.CacheStatus.COMPLETED, pageRequest);
            countMono = repository.countByIsPublicTrueAndStatus(NovelKnowledgeBase.CacheStatus.COMPLETED);
        }
        
        return queryFlux
                .collectList()
                .zipWith(countMono)
                .map(tuple -> {
                    var items = tuple.getT1().stream()
                            .map(this::toKnowledgeBaseCard)
                            .collect(Collectors.toList());
                    
                    return KnowledgeBaseListResponse.builder()
                            .items(items)
                            .totalCount(tuple.getT2().intValue())
                            .page(request.getPage())
                            .size(request.getSize())
                            .build();
                });
    }
    
    @Override
    public Mono<KnowledgeBaseListResponse> queryUserKnowledgeBases(String userId, KnowledgeBaseQueryRequest request) {
        log.info("查询用户知识库列表: userId={}, sourceType={}, page={}, size={}", 
                userId, request.getSourceType(), request.getPage(), request.getSize());
        
        // 构建排序（基于关系表的addedAt字段）
        Sort sort = Sort.by(Sort.Direction.DESC, "addedAt");
        PageRequest pageRequest = PageRequest.of(request.getPage(), request.getSize(), sort);
        
        // ✅ 通过关系表查询用户的知识库
        return relationRepository.findByUserId(userId, pageRequest)
                .flatMap(relation -> 
                    repository.findById(relation.getKnowledgeBaseId())
                )
                // ✅ 根据sourceType进行筛选
                .filter(kb -> {
                    if (request.getSourceType() == null || request.getSourceType().isEmpty()) {
                        return true; // 不筛选
                    }
                    if ("user_imported".equals(request.getSourceType())) {
                        return kb.getIsUserImported() != null && kb.getIsUserImported();
                    } else if ("fanqie_novel".equals(request.getSourceType())) {
                        return kb.getFanqieNovelId() != null && !kb.getFanqieNovelId().isEmpty();
                    }
                    return true;
                })
                .map(kb -> toKnowledgeBaseCard(kb))
                .collectList()
                .zipWith(relationRepository.countByUserId(userId))
                .map(tuple -> {
                    List<KnowledgeBaseListResponse.KnowledgeBaseCard> filteredItems = tuple.getT1();
                    // 注意：因为是先分页再过滤，所以结果数量可能少于pageSize
                    // 更好的方案是先过滤再分页，但这需要修改查询逻辑
                    return KnowledgeBaseListResponse.builder()
                            .items(filteredItems)
                            .totalCount(tuple.getT2().intValue())
                            .page(request.getPage())
                            .size(request.getSize())
                            .build();
                });
    }
    
    @Override
    public Mono<KnowledgeBaseDetailResponse> getKnowledgeBaseDetail(String knowledgeBaseId, String userId) {
        log.info("获取知识库详情: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        return repository.findById(knowledgeBaseId)
                .flatMap(kb -> {
                    // 增加查看次数
                    return incrementViewCount(knowledgeBaseId)
                            .flatMap(updatedKb -> toDetailResponse(updatedKb, userId));
                });
    }
    
    @Override
    public Mono<Boolean> addToNovel(String knowledgeBaseId, String novelId, String userId) {
        log.info("将知识库添加到小说: knowledgeBaseId={}, novelId={}, userId={}", 
                knowledgeBaseId, novelId, userId);
        
        return repository.findById(knowledgeBaseId)
                .switchIfEmpty(Mono.error(new RuntimeException("知识库不存在: " + knowledgeBaseId)))
                .flatMap(kb -> {
                    // 收集所有设定列表
                    List<List<NovelSettingItem>> allSettingLists = new ArrayList<>();
                    
                    if (kb.getNarrativeStyleSettings() != null) {
                        allSettingLists.add(kb.getNarrativeStyleSettings());
                    }
                    if (kb.getCharacterPlotSettings() != null) {
                        allSettingLists.add(kb.getCharacterPlotSettings());
                    }
                    if (kb.getNovelFeatureSettings() != null) {
                        allSettingLists.add(kb.getNovelFeatureSettings());
                    }
                    if (kb.getHotMemesSettings() != null) {
                        allSettingLists.add(kb.getHotMemesSettings());
                    }
                    if (kb.getCustomSettings() != null) {
                        allSettingLists.add(kb.getCustomSettings());
                    }
                    if (kb.getReaderEmotionSettings() != null) {
                        allSettingLists.add(kb.getReaderEmotionSettings());
                    }
                    
                    // 扁平化所有设定
                    List<NovelSettingItem> allSettings = allSettingLists.stream()
                            .flatMap(List::stream)
                            .collect(Collectors.toList());
                    
                    if (allSettings.isEmpty()) {
                        log.warn("知识库中没有设定: knowledgeBaseId={}", knowledgeBaseId);
                        return Mono.just(false);
                    }
                    
                    log.info("准备复制 {} 个设定到小说: novelId={}", allSettings.size(), novelId);
                    
                    // 批量创建设定
                    return Flux.fromIterable(allSettings)
                            .flatMap(setting -> {
                                // 创建新的设定副本
                                NovelSettingItem newSetting = NovelSettingItem.builder()
                                        .novelId(novelId)
                                        .userId(userId)
                                        .name(setting.getName())
                                        .type(setting.getType())
                                        .description(String.format("[来自知识库: %s]\n\n%s", 
                                                kb.getTitle(), setting.getDescription()))
                                        .attributes(setting.getAttributes())
                                        .tags(mergeTags(setting.getTags(), "知识库导入"))
                                        .priority(setting.getPriority() != null ? setting.getPriority() : 5)
                                        .generatedBy("KNOWLEDGE_BASE_IMPORT")
                                        .status("active")
                                        .createdAt(LocalDateTime.now())
                                        .updatedAt(LocalDateTime.now())
                                        .build();
                                
                                return novelSettingService.createSettingItem(newSetting)
                                        .doOnSuccess(created -> 
                                                log.debug("成功创建设定: name={}", created.getName()))
                                        .onErrorResume(error -> {
                                            log.error("创建设定失败: name={}, error={}", 
                                                    setting.getName(), error.getMessage());
                                            return Mono.empty(); // 跳过失败的设定
                                        });
                            })
                            .collectList()
                            .flatMap(createdSettings -> {
                                log.info("成功创建 {}/{} 个设定", 
                                        createdSettings.size(), allSettings.size());
                                
                                // 增加知识库的引用次数
                                return incrementReferenceCount(knowledgeBaseId)
                                        .map(updatedKb -> createdSettings.size() > 0);
                            });
                })
                .onErrorResume(error -> {
                    log.error("添加知识库到小说失败: knowledgeBaseId={}, novelId={}, error={}", 
                            knowledgeBaseId, novelId, error.getMessage(), error);
                    return Mono.just(false);
                });
    }
    
    @Override
    public Mono<Map<String, CacheStatusDTO>> getBatchCacheStatus(List<String> fanqieNovelIds) {
        if (fanqieNovelIds == null || fanqieNovelIds.isEmpty()) {
            log.debug("批量查询缓存状态: 输入为空");
            return Mono.just(Map.of());
        }
        
        log.info("批量查询缓存状态: 小说数量={}", fanqieNovelIds.size());
        
        // 使用Flux批量查询
        return Flux.fromIterable(fanqieNovelIds)
                .flatMap(novelId -> 
                    repository.findByFanqieNovelId(novelId)
                            .map(kb -> Map.entry(novelId, 
                                    new CacheStatusDTO(true, kb.getId())))
                            .defaultIfEmpty(Map.entry(novelId, 
                                    new CacheStatusDTO(false, null)))
                )
                .collectMap(
                    Map.Entry::getKey,
                    Map.Entry::getValue
                )
                .doOnSuccess(result -> 
                    log.info("批量查询缓存状态完成: 总数={}, 已缓存={}", 
                            fanqieNovelIds.size(), 
                            result.values().stream().filter(CacheStatusDTO::isCached).count())
                );
    }
    
    /**
     * 合并标签
     */
    private List<String> mergeTags(List<String> originalTags, String newTag) {
        List<String> merged = new ArrayList<>();
        if (originalTags != null) {
            merged.addAll(originalTags);
        }
        if (newTag != null && !merged.contains(newTag)) {
            merged.add(newTag);
        }
        return merged;
    }
    
    /**
     * 构建排序
     */
    private Sort buildSort(String sortBy, String sortOrder) {
        Sort.Direction direction = "asc".equalsIgnoreCase(sortOrder) 
                ? Sort.Direction.ASC 
                : Sort.Direction.DESC;
        
        // 映射排序字段
        String field = switch (sortBy) {
            case "likeCount" -> "likeCount";
            case "referenceCount" -> "referenceCount";
            case "viewCount" -> "viewCount";
            case "importTime" -> "firstImportTime";
            default -> "firstImportTime";
        };
        
        return Sort.by(direction, field);
    }
    
    /**
     * 转换为知识库卡片DTO
     */
    private KnowledgeBaseListResponse.KnowledgeBaseCard toKnowledgeBaseCard(NovelKnowledgeBase kb) {
        return KnowledgeBaseListResponse.KnowledgeBaseCard.builder()
                .id(kb.getId())
                .title(kb.getTitle() != null ? kb.getTitle() : "未命名知识库")  // ✅ 提供默认值
                .description(kb.getDescription() != null ? kb.getDescription() : "")  // ✅ 提供默认值
                .coverImageUrl(kb.getCoverImageUrl())
                .author(kb.getAuthor())
                .tags(kb.getTags())
                .likeCount(kb.getLikeCount())
                .referenceCount(kb.getReferenceCount())
                .viewCount(kb.getViewCount())
                .importTime(kb.getFirstImportTime())
                .completionStatus(kb.getCompletionStatus() != null ? kb.getCompletionStatus().name() : null)
                .isUserImported(kb.getIsUserImported() != null ? kb.getIsUserImported() : false)  // ✅ 提供默认值
                .fanqieNovelId(kb.getFanqieNovelId())
                .build();
    }
    
    /**
     * 转换为详情响应DTO（异步加载大纲）
     */
    private Mono<KnowledgeBaseDetailResponse> toDetailResponse(NovelKnowledgeBase kb, String userId) {
        boolean isLiked = kb.getLikedUserIds().contains(userId);
        
        // 基础响应构建器
        KnowledgeBaseDetailResponse.KnowledgeBaseDetailResponseBuilder builder = KnowledgeBaseDetailResponse.builder()
                .id(kb.getId())
                .title(kb.getTitle())
                .description(kb.getDescription())
                .coverImageUrl(kb.getCoverImageUrl())
                .author(kb.getAuthor())
                .tags(kb.getTags())
                .completionStatus(kb.getCompletionStatus() != null ? kb.getCompletionStatus().name() : null)
                .likeCount(kb.getLikeCount())
                .referenceCount(kb.getReferenceCount())
                .viewCount(kb.getViewCount())
                .isLiked(isLiked)
                .importTime(kb.getFirstImportTime())
                .narrativeStyleSettings(kb.getNarrativeStyleSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()))
                .characterPlotSettings(kb.getCharacterPlotSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()))
                .novelFeatureSettings(kb.getNovelFeatureSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()))
                .hotMemesSettings(kb.getHotMemesSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()))
                .customSettings(kb.getCustomSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()))
                .readerEmotionSettings(kb.getReaderEmotionSettings().stream()
                        .map(KnowledgeBaseDetailResponse::fromNovelSettingItem)
                        .collect(Collectors.toList()));
        
        // 如果有大纲小说ID，加载大纲信息
        if (kb.getOutlineNovelId() != null && !kb.getOutlineNovelId().isEmpty()) {
            log.info("知识库包含大纲小说，开始加载: outlineNovelId={}", kb.getOutlineNovelId());
            return novelService.findNovelById(kb.getOutlineNovelId())
                    .map(novel -> {
                        List<KnowledgeBaseDetailResponse.ChapterOutlineDto> chapterOutlines = extractChapterOutlines(novel);
                        log.info("成功加载章节大纲: {} 章", chapterOutlines.size());
                        return builder.chapterOutlines(chapterOutlines).build();
                    })
                    .onErrorResume(error -> {
                        log.error("加载大纲小说失败: outlineNovelId={}, error={}", 
                                kb.getOutlineNovelId(), error.getMessage());
                        // 即使加载失败，也返回基础信息
                        return Mono.just(builder.chapterOutlines(new ArrayList<>()).build());
                    });
        } else {
            // 没有大纲，直接返回
            return Mono.just(builder.chapterOutlines(new ArrayList<>()).build());
        }
    }
    
    /**
     * 从Novel对象提取章节大纲
     */
    private List<KnowledgeBaseDetailResponse.ChapterOutlineDto> extractChapterOutlines(
            com.ainovel.server.domain.model.Novel novel) {
        
        List<KnowledgeBaseDetailResponse.ChapterOutlineDto> outlines = new ArrayList<>();
        
        if (novel.getStructure() != null && novel.getStructure().getActs() != null) {
            for (var act : novel.getStructure().getActs()) {
                if (act.getChapters() != null) {
                    for (var chapter : act.getChapters()) {
                        KnowledgeBaseDetailResponse.ChapterOutlineDto outline = 
                                KnowledgeBaseDetailResponse.ChapterOutlineDto.builder()
                                        .chapterId(chapter.getId())
                                        .title(chapter.getTitle())
                                        .summary(chapter.getDescription())
                                        .order(chapter.getOrder())
                                        .build();
                        outlines.add(outline);
                    }
                }
            }
        }
        
        // 按order排序
        outlines.sort((a, b) -> Integer.compare(a.getOrder() != null ? a.getOrder() : 0, 
                                                 b.getOrder() != null ? b.getOrder() : 0));
        
        return outlines;
    }
    
    @Override
    public Mono<Boolean> addToMyKnowledgeBase(String knowledgeBaseId, String userId) {
        log.info("添加知识库到我的知识库: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        // 检查知识库是否存在
        return repository.findById(knowledgeBaseId)
                .switchIfEmpty(Mono.error(new RuntimeException("知识库不存在: " + knowledgeBaseId)))
                .flatMap(kb -> {
                    // 检查关系是否已存在
                    return relationRepository.findByUserIdAndKnowledgeBaseId(userId, knowledgeBaseId)
                            .flatMap(existing -> {
                                log.info("用户已添加该知识库: userId={}, knowledgeBaseId={}", userId, knowledgeBaseId);
                                return Mono.just(true);
                            })
                            .switchIfEmpty(Mono.defer(() -> {
                                // 创建新关系
                                UserKnowledgeBaseRelation relation = UserKnowledgeBaseRelation.builder()
                                        .userId(userId)
                                        .knowledgeBaseId(knowledgeBaseId)
                                        .addType(UserKnowledgeBaseRelation.AddType.MANUAL_ADD)
                                        .addedAt(LocalDateTime.now())
                                        .lastUsedAt(LocalDateTime.now())
                                        .build();
                                
                                return relationRepository.save(relation)
                                        .flatMap(saved -> {
                                            log.info("成功添加知识库到我的知识库: userId={}, knowledgeBaseId={}", userId, knowledgeBaseId);
                                            // 增加引用计数
                                            return incrementReferenceCount(knowledgeBaseId)
                                                    .thenReturn(true);
                                        });
                            }));
                });
    }
    
    @Override
    public Mono<Boolean> removeFromMyKnowledgeBase(String knowledgeBaseId, String userId) {
        log.info("从我的知识库删除: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        return relationRepository.deleteByUserIdAndKnowledgeBaseId(userId, knowledgeBaseId)
                .then(Mono.just(true))
                .doOnSuccess(result -> log.info("成功从我的知识库删除: userId={}, knowledgeBaseId={}", userId, knowledgeBaseId))
                .onErrorResume(error -> {
                    log.error("从我的知识库删除失败: userId={}, knowledgeBaseId={}, error={}", 
                            userId, knowledgeBaseId, error.getMessage());
                    return Mono.just(false);
                });
    }
    
    @Override
    public Mono<Boolean> isInMyKnowledgeBase(String knowledgeBaseId, String userId) {
        log.debug("检查知识库是否在我的知识库中: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        return relationRepository.existsByUserIdAndKnowledgeBaseId(userId, knowledgeBaseId);
    }
}

