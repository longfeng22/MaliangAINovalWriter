package com.ainovel.server.web.controller;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.domain.model.Scene.HistoryEntry;
import com.ainovel.server.service.ImportService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.web.base.ReactiveBaseController;
import com.ainovel.server.web.dto.AuthorIdDto;
import com.ainovel.server.web.dto.ChapterSceneDto;
import com.ainovel.server.web.dto.ChapterScenesDto;
import com.ainovel.server.web.dto.IdDto;
import com.ainovel.server.web.dto.ImportStatus;
import com.ainovel.server.web.dto.JobIdResponse;
import com.ainovel.server.web.dto.LoadMoreScenesRequestDto;
import com.ainovel.server.web.dto.NovelChapterDto;
import com.ainovel.server.web.dto.NovelChapterSceneDto;
import com.ainovel.server.web.dto.NovelWithScenesDto;
import com.ainovel.server.web.dto.NovelWithSummariesDto;
import com.ainovel.server.web.dto.PaginatedScenesRequestDto;
import com.ainovel.server.web.dto.SceneContentUpdateDto;
import com.ainovel.server.web.dto.SceneRestoreDto;
import com.ainovel.server.web.dto.SceneSearchDto;
import com.ainovel.server.web.dto.SceneVersionCompareDto;
import com.ainovel.server.web.dto.SceneVersionDiff;
import com.ainovel.server.web.dto.ChaptersAfterRequestDto;
import com.ainovel.server.web.dto.ChaptersForPreloadDto;
import com.ainovel.server.web.dto.ImportPreviewRequest;
import com.ainovel.server.web.dto.ImportPreviewResponse;
import com.ainovel.server.web.dto.ImportConfirmRequest;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.util.StringUtils;
import org.springframework.web.server.ResponseStatusException;

/**
 * 小说控制器
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/novels")
@RequiredArgsConstructor
public class NovelController extends ReactiveBaseController {

    private final NovelService novelService;
    private final SceneService sceneService;
    private final ImportService importService;
    private final com.ainovel.server.service.UsageQuotaService usageQuotaService;

    /**
     * 创建小说
     *
     * @param novel 小说信息
     * @return 创建的小说
     */
    @PostMapping("/create")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Novel> createNovel(@RequestBody Novel novel) {
        // 基于会员计划的小说数量限制
        if (novel.getAuthor() == null || novel.getAuthor().getId() == null) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "缺少作者ID"));
        }
        String userId = novel.getAuthor().getId();
        return usageQuotaService.canCreateMoreNovels(userId)
            .flatMap(can -> {
                if (!can) {
                    return Mono.error(new ResponseStatusException(HttpStatus.FORBIDDEN, "已达到可创建小说数量上限"));
                }
                return novelService.createNovel(novel)
                    .flatMap(created -> usageQuotaService.onNovelCreated(userId).thenReturn(created));
            });
    }

    /**
     * 获取小说详情
     *
     * @param idDto 包含小说ID的DTO
     * @return 小说信息
     */
    @PostMapping("/get")
    public Mono<Novel> getNovel(@RequestBody IdDto idDto) {
        return novelService.findNovelById(idDto.getId());
    }

    /**
     * 获取小说详情及其所有场景内容
     *
     * @param idDto 包含小说ID的DTO
     * @return 小说及其所有场景数据
     */
    @PostMapping("/get-with-scenes")
    public Mono<NovelWithScenesDto> getNovelWithScenes(@RequestBody IdDto idDto) {
        return novelService.getNovelWithAllScenes(idDto.getId());
    }

    /**
     * 获取小说详情及其所有场景内容（纯文本格式）
     *
     * @param idDto 包含小说ID的DTO
     * @return 小说及其所有场景数据
     */
    @PostMapping("/get-with-scenes-text")
    public Mono<NovelWithScenesDto> getNovelWithScenesText(@RequestBody IdDto idDto) {
        return novelService.getNovelWithAllScenesText(idDto.getId());
    }

    /**
     * 获取小说详情及其部分场景内容（分页加载） 基于上次编辑章节为中心，获取前后指定数量的章节
     *
     * @param paginatedScenesRequestDto 包含小说ID和分页参数的DTO
     * @return 小说及其分页加载的场景数据
     */
    @PostMapping("/get-with-paginated-scenes")
    public Mono<NovelWithScenesDto> getNovelWithPaginatedScenes(@RequestBody PaginatedScenesRequestDto paginatedScenesRequestDto) {
        String novelId = paginatedScenesRequestDto.getNovelId();
        String lastEditedChapterId = paginatedScenesRequestDto.getLastEditedChapterId();
        int chaptersLimit = paginatedScenesRequestDto.getChaptersLimit();

        log.info("获取小说分页场景数据: novelId={}, lastEditedChapterId={}, chaptersLimit={}",
                novelId, lastEditedChapterId, chaptersLimit);

        return novelService.getNovelWithPaginatedScenes(novelId, lastEditedChapterId, chaptersLimit);
    }

    /**
     * 获取当前章节后面指定数量的章节和场景内容，允许跨卷加载
     *
     * @param chaptersAfterRequestDto 包含小说ID、当前章节ID和章节数量限制的DTO
     * @return 小说及其后续章节的场景数据
     */
    @PostMapping("/get-chapters-after")
    public Mono<NovelWithScenesDto> getChaptersAfter(@RequestBody ChaptersAfterRequestDto chaptersAfterRequestDto) {
        String novelId = chaptersAfterRequestDto.getNovelId();
        String currentChapterId = chaptersAfterRequestDto.getCurrentChapterId();
        int chaptersLimit = chaptersAfterRequestDto.getChaptersLimit();
        boolean includeCurrentChapter = chaptersAfterRequestDto.isIncludeCurrentChapter();

        log.info("获取当前章节后面的章节: novelId={}, currentChapterId={}, chaptersLimit={}, includeCurrentChapter={}",
                novelId, currentChapterId, chaptersLimit, includeCurrentChapter);

        return novelService.getChaptersAfter(novelId, currentChapterId, chaptersLimit, includeCurrentChapter);
    }

    /**
     * 获取指定章节后面的章节列表（用于预加载）
     * 专门为预加载功能设计，只返回章节列表和场景内容，不返回完整小说结构
     *
     * @param chaptersAfterRequestDto 包含小说ID、当前章节ID和章节数量限制的DTO
     * @return 预加载章节数据DTO
     */
    @PostMapping("/get-chapters-for-preload")
    public Mono<ChaptersForPreloadDto> getChaptersForPreload(@RequestBody ChaptersAfterRequestDto chaptersAfterRequestDto) {
        String novelId = chaptersAfterRequestDto.getNovelId();
        String currentChapterId = chaptersAfterRequestDto.getCurrentChapterId();
        int chaptersLimit = chaptersAfterRequestDto.getChaptersLimit();
        boolean includeCurrentChapter = chaptersAfterRequestDto.isIncludeCurrentChapter();

        log.info("获取章节列表用于预加载: novelId={}, currentChapterId={}, chaptersLimit={}, includeCurrentChapter={}",
                novelId, currentChapterId, chaptersLimit, includeCurrentChapter);

        return novelService.getChaptersForPreload(novelId, currentChapterId, chaptersLimit, includeCurrentChapter)
                .doOnSuccess(dto -> log.info("预加载API成功返回，章节数: {}, 场景章节数: {}", 
                        dto.getChapterCount(), dto.getScenesByChapter().size()))
                .doOnError(e -> log.error("预加载API调用失败", e));
    }

    /**
     * 加载更多场景内容 根据方向（向上或向下）加载更多章节的场景内容
     *
     * @param loadMoreScenesRequestDto 包含小说ID、卷ID、方向和章节数量的DTO
     * @return 加载的更多场景数据，按章节组织
     */
    @PostMapping("/load-more-scenes")
    public Mono<Map<String, List<Scene>>> loadMoreScenes(@RequestBody LoadMoreScenesRequestDto loadMoreScenesRequestDto) {
        String novelId = loadMoreScenesRequestDto.getNovelId();
        String actId = loadMoreScenesRequestDto.getActId();
        String fromChapterId = loadMoreScenesRequestDto.getFromChapterId();
        String direction = loadMoreScenesRequestDto.getDirection();
        int chaptersLimit = loadMoreScenesRequestDto.getChaptersLimit();

        log.info("加载更多场景: novelId={}, actId={}, fromChapterId={}, direction={}, chaptersLimit={}",
                novelId, actId, fromChapterId, direction, chaptersLimit);

        return novelService.loadMoreScenes(novelId, actId, fromChapterId, direction, chaptersLimit);
    }

    /**
     * 更新小说及其所有场景内容
     *
     * @param novelWithScenesDto 包含小说信息及其所有场景数据的DTO
     * @return 更新后的小说及场景数据
     */
    @PostMapping("/update-with-scenes")
    public Mono<NovelWithScenesDto> updateNovelWithScenes(@RequestBody NovelWithScenesDto novelWithScenesDto) {
        Novel novel = novelWithScenesDto.getNovel();
        // 从 Map 中获取所有场景列表，并将它们合并成一个大的 List
        List<Scene> scenes = novelWithScenesDto.getScenesByChapter().values().stream()
                .flatMap(List::stream) // 将多个 List<Scene> 合并成一个 Stream<Scene>
                .toList(); // 收集成一个新的 List<Scene>

        // 确保所有场景关联到正确的小说ID
        // 注意：ChapterId 应该在构建 DTO 时已经正确设置在每个 Scene 对象中
        scenes.forEach(scene -> scene.setNovelId(novel.getId()));

        // 首先更新小说
        return novelService.updateNovel(novel.getId(), novel)
                // 然后更新所有场景
                .flatMap(updatedNovel -> {
                    // 使用upsertScenes批量更新场景
                    return sceneService.upsertScenes(scenes)
                            .collectList()
                            .map(updatedScenes -> {
                                // 将更新后的场景列表重新按 ChapterId 分组
                                Map<String, List<Scene>> updatedScenesByChapter = updatedScenes.stream()
                                        .collect(Collectors.groupingBy(Scene::getChapterId));

                                // 构建返回对象
                                NovelWithScenesDto result = new NovelWithScenesDto();
                                result.setNovel(updatedNovel);
                                // 设置分组后的 Map
                                result.setScenesByChapter(updatedScenesByChapter);
                                return result;
                            });
                });
    }

    /**
     * 更新小说
     *
     * @param novelUpdateDto 包含小说ID和更新信息的DTO
     * @return 更新后的小说
     */
    @PostMapping("/update")
    public Mono<Novel> updateNovel(@RequestBody Novel novel) {
        return novelService.updateNovel(novel.getId(), novel);
    }

    /**
     * 删除小说
     *
     * @param idDto 包含小说ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteNovel(@RequestBody IdDto idDto) {
        return novelService.deleteNovel(idDto.getId());
    }

    /**
     * 删除章节及其场景
     *
     * @param request 包含novelId, actId, chapterId的请求
     * @return 更新后的小说数据，包含场景
     */
    @PostMapping("/delete-chapter")
    public Mono<NovelWithScenesDto> deleteChapter(@RequestBody Map<String, String> request) {
        String novelId = request.get("novelId");
        String actId = request.get("actId");
        String chapterId = request.get("chapterId");
        
        log.info("收到删除章节请求: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
        
        if (novelId == null || actId == null || chapterId == null) {
            return Mono.error(new IllegalArgumentException("novelId, actId 和 chapterId 不能为空"));
        }
        
        return novelService.deleteChapter(novelId, actId, chapterId)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId))
                .doOnSuccess(dto -> log.info("章节删除成功并返回更新后的小说数据: novelId={}", novelId))
                .doOnError(e -> log.error("章节删除失败: novelId={}, actId={}, chapterId={}, 错误={}", 
                        novelId, actId, chapterId, e.getMessage()));
    }

    /**
     * 删除卷（Act）- 与日志中的 /api/v1/novels/act/delete 对应
     *
     * @param request 包含 novelId, actId 的请求
     * @return 更新后的小说数据，包含场景
     */
    @PostMapping("/act/delete")
    public Mono<NovelWithScenesDto> deleteAct(@RequestBody Map<String, String> request) {
        String novelId = request.get("novelId");
        String actId = request.get("actId");

        log.info("收到删除卷请求: novelId={}, actId={}", novelId, actId);

        if (novelId == null || actId == null) {
            return Mono.error(new IllegalArgumentException("novelId 和 actId 不能为空"));
        }

        return novelService.deleteActFine(novelId, actId)
                .flatMap(success -> {
                    if (Boolean.TRUE.equals(success)) {
                        return novelService.getNovelWithAllScenes(novelId);
                    } else {
                        return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "删除卷失败"));
                    }
                })
                .doOnSuccess(dto -> log.info("卷删除成功并返回更新后的小说数据: novelId={}", novelId))
                .doOnError(e -> log.error("卷删除失败: novelId={}, actId={}, 错误={}", novelId, actId, e.getMessage()));
    }

    /**
     * 删除章节（别名接口）- 与前端可能使用的 /api/v1/novels/chapter/delete 对齐
     * 逻辑同 delete-chapter，复用细粒度删除 + 返回全量结构
     */
    @PostMapping("/chapter/delete")
    public Mono<NovelWithScenesDto> deleteChapterAlias(@RequestBody Map<String, String> request) {
        String novelId = request.get("novelId");
        String actId = request.get("actId");
        String chapterId = request.get("chapterId");

        log.info("收到删除章节(别名)请求: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);

        if (novelId == null || actId == null || chapterId == null) {
            return Mono.error(new IllegalArgumentException("novelId, actId 和 chapterId 不能为空"));
        }

        return novelService.deleteChapterFine(novelId, actId, chapterId)
                .flatMap(success -> {
                    if (Boolean.TRUE.equals(success)) {
                        return novelService.getNovelWithAllScenes(novelId);
                    } else {
                        return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "删除章节失败"));
                    }
                })
                .doOnSuccess(dto -> log.info("章节删除(别名)成功并返回更新后的小说数据: novelId={}", novelId))
                .doOnError(e -> log.error("章节删除(别名)失败: novelId={}, actId={}, chapterId={}, 错误={}",
                        novelId, actId, chapterId, e.getMessage()));
    }

    /**
     * 获取作者的所有小说
     *
     * @param authorIdDto 包含作者ID的DTO
     * @return 小说列表
     */
    @PostMapping("/get-by-author")
    public Flux<Novel> getNovelsByAuthor(@RequestBody AuthorIdDto authorIdDto) {
        // 默认只返回已就绪的小说
        return novelService.findNovelsByAuthorId(authorIdDto.getAuthorId());
    }

    /**
     * 搜索小说
     *
     * @param searchDto 包含标题关键词的DTO
     * @return 小说列表
     */
    @PostMapping("/search")
    public Flux<Novel> searchNovels(@RequestBody SceneSearchDto searchDto) {
        return novelService.searchNovelsByTitle(searchDto.getTitle());
    }

    /**
     * 获取小说章节的场景内容（按顺序排序）
     *
     * @param novelChapterDto 包含小说ID和章节ID的DTO
     * @return 排序后的场景列表
     */
    @PostMapping("/get-chapter-scenes-ordered")
    public Flux<Scene> getChapterScenesOrdered(@RequestBody NovelChapterDto novelChapterDto) {
        return sceneService.findSceneByChapterIdOrdered(novelChapterDto.getChapterId())
                .filter(scene -> scene.getNovelId().equals(novelChapterDto.getNovelId()));
    }

    /**
     * 获取小说章节的特定场景内容
     *
     * @param novelChapterSceneDto 包含小说ID、章节ID和场景ID的DTO
     * @return 场景内容
     */
    @PostMapping("/get-chapter-scene")
    public Mono<Scene> getChapterScene(@RequestBody NovelChapterSceneDto novelChapterSceneDto) {
        return sceneService.findSceneById(novelChapterSceneDto.getSceneId())
                .filter(scene -> scene.getNovelId().equals(novelChapterSceneDto.getNovelId())
                && scene.getChapterId().equals(novelChapterSceneDto.getChapterId()))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")));
    }

    /**
     * 创建小说章节的场景内容
     *
     * @param chapterSceneDto 包含小说ID、章节ID和场景内容的DTO
     * @return 创建的场景
     */
    @PostMapping("/create-chapter-scene")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Scene> createChapterScene(@RequestBody ChapterSceneDto chapterSceneDto) {
        // 确保场景关联到正确的小说和章节
        Scene scene = chapterSceneDto.getScene();
        scene.setNovelId(chapterSceneDto.getNovelId());
        scene.setChapterId(chapterSceneDto.getChapterId());

        return sceneService.createScene(scene);
    }

    /**
     * 批量创建小说章节的场景内容
     *
     * @param chapterScenesDto 包含小说ID、章节ID和场景列表的DTO
     * @return 创建的场景列表
     */
    @PostMapping("/create-chapter-scenes-batch")
    @ResponseStatus(HttpStatus.CREATED)
    public Flux<Scene> createChapterScenes(@RequestBody ChapterScenesDto chapterScenesDto) {
        // 确保所有场景关联到正确的小说和章节
        List<Scene> scenes = chapterScenesDto.getScenes();
        scenes.forEach(scene -> {
            scene.setNovelId(chapterScenesDto.getNovelId());
            scene.setChapterId(chapterScenesDto.getChapterId());
        });

        return sceneService.createScenes(scenes);
    }

    /**
     * 创建或更新小说章节的场景内容
     *
     * @param chapterSceneDto 包含小说ID、章节ID和场景内容的DTO
     * @return 更新后的场景
     */
    @PostMapping("/upsert-chapter-scene")
    public Mono<Scene> createOrUpdateChapterScene(@RequestBody ChapterSceneDto chapterSceneDto) {
        // 确保场景关联到正确的小说和章节
        Scene scene = chapterSceneDto.getScene();
        scene.setNovelId(chapterSceneDto.getNovelId());
        scene.setChapterId(chapterSceneDto.getChapterId());

        return sceneService.upsertScene(scene);
    }

    /**
     * 批量创建或更新小说章节的场景内容
     *
     * @param chapterScenesDto 包含小说ID、章节ID和场景列表的DTO
     * @return 更新后的场景列表
     */
    @PostMapping("/upsert-chapter-scenes-batch")
    public Flux<Scene> createOrUpdateChapterScenes(@RequestBody ChapterScenesDto chapterScenesDto) {
        // 确保所有场景关联到正确的小说和章节
        List<Scene> scenes = chapterScenesDto.getScenes();
        scenes.forEach(scene -> {
            scene.setNovelId(chapterScenesDto.getNovelId());
            scene.setChapterId(chapterScenesDto.getChapterId());
        });

        return sceneService.upsertScenes(scenes);
    }

    /**
     * 更新小说章节的特定场景内容
     *
     * @param novelChapterSceneDto 包含小说ID、章节ID、场景ID和更新信息的DTO
     * @return 更新后的场景
     */
    @PostMapping("/update-chapter-scene")
    public Mono<Scene> updateChapterScene(@RequestBody NovelChapterSceneDto novelChapterSceneDto) {
        // 确保场景关联到正确的小说和章节，并设置正确的ID
        Scene scene = novelChapterSceneDto.getScene();
        scene.setId(novelChapterSceneDto.getSceneId());
        scene.setNovelId(novelChapterSceneDto.getNovelId());
        scene.setChapterId(novelChapterSceneDto.getChapterId());

        return sceneService.updateScene(novelChapterSceneDto.getSceneId(), scene);
    }

    /**
     * 删除小说章节的特定场景
     *
     * @param novelChapterSceneDto 包含小说ID、章节ID和场景ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete-chapter-scene")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteChapterScene(@RequestBody NovelChapterSceneDto novelChapterSceneDto) {
        return sceneService.findSceneById(novelChapterSceneDto.getSceneId())
                .filter(scene -> scene.getNovelId().equals(novelChapterSceneDto.getNovelId())
                && scene.getChapterId().equals(novelChapterSceneDto.getChapterId()))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")))
                .flatMap(scene -> sceneService.deleteScene(novelChapterSceneDto.getSceneId()));
    }

    /**
     * 删除小说章节的所有场景
     *
     * @param novelChapterDto 包含小说ID和章节ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete-chapter-scenes")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteChapterScenes(@RequestBody NovelChapterDto novelChapterDto) {
        return sceneService.findSceneByChapterId(novelChapterDto.getChapterId())
                .filter(scene -> scene.getNovelId().equals(novelChapterDto.getNovelId()))
                .map(Scene::getId)
                .flatMap(sceneService::deleteScene)
                .then();
    }

    // ============================== 场景版本控制相关API ==============================
    /**
     * 更新场景内容并保存历史版本
     *
     * @param sceneContentUpdateDto 包含小说ID、章节ID、场景ID和更新数据的DTO
     * @return 更新后的场景
     */
    @PostMapping("/update-chapter-scene-content")
    public Mono<Scene> updateChapterSceneContent(@RequestBody SceneContentUpdateDto sceneContentUpdateDto) {
        String sceneId = sceneContentUpdateDto.getId();
        String novelId = sceneContentUpdateDto.getNovelId();
        String chapterId = sceneContentUpdateDto.getChapterId();

        return sceneService.findSceneById(sceneId)
                .filter(scene -> scene.getNovelId().equals(novelId) && scene.getChapterId().equals(chapterId))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")))
                .flatMap(scene -> sceneService.updateSceneContent(sceneId, sceneContentUpdateDto.getContent(),
                sceneContentUpdateDto.getUserId(), sceneContentUpdateDto.getReason()));
    }

    /**
     * 获取场景的历史版本列表
     *
     * @param novelChapterSceneDto 包含小说ID、章节ID和场景ID的DTO
     * @return 历史版本列表
     */
    @PostMapping("/get-chapter-scene-history")
    public Mono<List<HistoryEntry>> getChapterSceneHistory(@RequestBody NovelChapterSceneDto novelChapterSceneDto) {
        return sceneService.findSceneById(novelChapterSceneDto.getSceneId())
                .filter(scene -> scene.getNovelId().equals(novelChapterSceneDto.getNovelId())
                && scene.getChapterId().equals(novelChapterSceneDto.getChapterId()))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")))
                .flatMap(scene -> sceneService.getSceneHistory(novelChapterSceneDto.getSceneId()));
    }

    /**
     * 恢复场景到指定的历史版本
     *
     * @param sceneRestoreDto 包含小说ID、章节ID、场景ID和恢复数据的DTO
     * @return 恢复后的场景
     */
    @PostMapping("/restore-chapter-scene")
    public Mono<Scene> restoreChapterSceneVersion(@RequestBody SceneRestoreDto sceneRestoreDto) {
        String sceneId = sceneRestoreDto.getId();
        String novelId = sceneRestoreDto.getNovelId();
        String chapterId = sceneRestoreDto.getChapterId();

        return sceneService.findSceneById(sceneId)
                .filter(scene -> scene.getNovelId().equals(novelId) && scene.getChapterId().equals(chapterId))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")))
                .flatMap(scene -> sceneService.restoreSceneVersion(sceneId, sceneRestoreDto.getHistoryIndex(),
                sceneRestoreDto.getUserId(), sceneRestoreDto.getReason()));
    }

    /**
     * 对比两个场景版本
     *
     * @param sceneVersionCompareDto 包含小说ID、章节ID、场景ID和对比数据的DTO
     * @return 差异信息
     */
    @PostMapping("/compare-chapter-scene-versions")
    public Mono<SceneVersionDiff> compareChapterSceneVersions(
            @RequestBody SceneVersionCompareDto sceneVersionCompareDto) {
        String sceneId = sceneVersionCompareDto.getId();
        String novelId = sceneVersionCompareDto.getNovelId();
        String chapterId = sceneVersionCompareDto.getChapterId();

        return sceneService.findSceneById(sceneId)
                .filter(scene -> scene.getNovelId().equals(novelId) && scene.getChapterId().equals(chapterId))
                .switchIfEmpty(Mono.error(new RuntimeException("场景不存在或不属于指定的小说和章节")))
                .flatMap(scene -> {
                    // 调用服务并转换返回类型
                    return sceneService.compareSceneVersions(sceneId, sceneVersionCompareDto.getVersionIndex1(),
                            sceneVersionCompareDto.getVersionIndex2())
                            .map(diff -> {
                                // 将domain模型转换为DTO
                                SceneVersionDiff dto = new SceneVersionDiff();
                                dto.setOriginalContent(diff.getOriginalContent());
                                dto.setNewContent(diff.getNewContent());
                                dto.setDiff(diff.getDiff());
                                return dto;
                            });
                });
    }

    /**
     * 导入小说文件
     *
     * @param filePart 上传的文件部分
     * @param currentUser 当前用户
     * @return 导入任务ID
     */
    @PostMapping(value = "/import", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Mono<ResponseEntity<JobIdResponse>> importNovel(
            @RequestPart("file") FilePart filePart,
            @RequestPart(value = "userId", required = false) String formUserId,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {

        log.info("接收到小说导入请求: {}，大小: {}", filePart.filename(), filePart.headers().getContentLength());

        // 如果当前用户ID为空，尝试使用表单中的用户ID
        final String userIdFinal;
        String userId = currentUser != null ? currentUser.getId() : null;
        if (userId == null || userId.isEmpty()) {
            if (formUserId != null && !formUserId.isEmpty()) {
                userId = formUserId;
                log.info("使用表单中的用户ID: {}", userId);
            } else {
                log.error("未能获取用户ID，无法导入小说");
                return Mono.just(ResponseEntity
                        .status(HttpStatus.UNAUTHORIZED)
                        .body(new JobIdResponse("错误：未能识别用户身份")));
            }
        }
        userIdFinal = userId;

        return usageQuotaService.canImportNovel(userIdFinal)
                .flatMap(can -> {
                    if (!can) {
                        return Mono.just(ResponseEntity
                                .status(HttpStatus.FORBIDDEN)
                                .body(new JobIdResponse("导入次数已达今日上限")));
                    }
                    return importService.startImport(filePart, userIdFinal)
                        .flatMap(jobId -> usageQuotaService.onNovelImported(userIdFinal).thenReturn(jobId))
                        .map(jobId -> ResponseEntity
                            .status(HttpStatus.ACCEPTED)
                            .body(new JobIdResponse(jobId)));
                })
                ;
    }

    /**
     * 获取导入任务状态流
     *
     * @param jobId 任务ID
     * @return SSE事件流
     */
    @GetMapping(value = "/import/{jobId}/status", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<ImportStatus>> getImportStatus(@PathVariable String jobId) {
        return importService.getImportStatusStream(jobId);
    }

    /**
     * 取消导入任务
     *
     * @param jobId 任务ID
     * @return 操作结果
     */
    @PostMapping("/import/{jobId}/cancel")
    public Mono<ResponseEntity<Map<String, Object>>> cancelImport(@PathVariable String jobId) {
        log.info("收到取消导入任务请求: {}", jobId);

        return importService.cancelImport(jobId)
                .map(success -> {
                    if (success) {
                        return ResponseEntity.ok(
                                Map.of(
                                        "status", "success",
                                        "message", "导入任务已成功取消"
                                )
                        );
                    } else {
                        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(
                                Map.of(
                                        "status", "failed",
                                        "message", "导入任务取消失败，任务可能不存在或已完成"
                                )
                        );
                    }
                });
    }

    /**
     * 上传文件用于预览
     * 新的导入流程第一步：上传文件获取预览会话ID
     *
     * @param filePart 上传的文件部分
     * @param formUserId 表单中的用户ID
     * @param currentUserId 当前用户ID
     * @return 预览会话ID
     */
    @PostMapping(value = "/import/upload-preview", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Mono<ResponseEntity<Map<String, String>>> uploadFileForPreview(
            @RequestPart("file") FilePart filePart,
            @RequestPart(value = "userId", required = false) String formUserId,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {

        log.info("接收到小说预览上传请求: {}，大小: {}", filePart.filename(), filePart.headers().getContentLength());

        // 获取用户ID
        String userId = currentUser != null ? currentUser.getId() : null;
        if (userId == null || userId.isEmpty()) {
            if (formUserId != null && !formUserId.isEmpty()) {
                userId = formUserId;
                log.info("使用表单中的用户ID: {}", userId);
            } else {
                log.error("未能获取用户ID，无法上传预览文件");
                return Mono.just(ResponseEntity
                        .status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "未能识别用户身份")));
            }
        }

        return importService.uploadFileForPreview(filePart, userId)
                .map(previewSessionId -> ResponseEntity.ok(
                        Map.of(
                                "previewSessionId", previewSessionId,
                                "fileName", filePart.filename() != null ? filePart.filename() : "unknown",
                                "status", "success"
                        )))
                .onErrorReturn(ResponseEntity
                        .status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(Map.of("error", "文件上传失败")));
    }

    /**
     * 获取导入预览
     * 新的导入流程第二步：根据配置获取文件解析预览
     *
     * @param request 预览请求
     * @return 预览响应
     */
    @PostMapping("/import/preview")
    public Mono<ResponseEntity<ImportPreviewResponse>> getImportPreview(
            @RequestBody ImportPreviewRequest request) {

        log.info("接收到导入预览请求: 会话ID={}, 标题={}, 章节限制={}", 
                request.getFileSessionId(), request.getCustomTitle(), request.getChapterLimit());

        return importService.getImportPreview(request)
                .map(ResponseEntity::ok)
                .onErrorResume(e -> {
                    log.error("获取导入预览失败", e);
                    return Mono.just(ResponseEntity
                            .status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(ImportPreviewResponse.builder()
                                    .warnings(List.of("获取预览失败: " + e.getMessage()))
                                    .build()));
                });
    }

    /**
     * 确认并开始导入
     * 新的导入流程第三步：用户确认配置后开始正式导入
     *
     * @param request 确认导入请求
     * @param currentUserId 当前用户ID
     * @return 导入任务ID
     */
    @PostMapping("/import/confirm")
    public Mono<ResponseEntity<JobIdResponse>> confirmAndStartImport(
            @RequestBody ImportConfirmRequest request,
            @AuthenticationPrincipal com.ainovel.server.security.CurrentUser currentUser) {

        String currentUserId = currentUser != null ? currentUser.getId() : null;
        log.info("接收到确认导入请求: 会话ID={}, 标题={}, 选中章节数={}, aiConfigId={}, enableAISummary={}, enableSmartContext={}, userId={}", 
                request.getPreviewSessionId(), request.getFinalTitle(), 
                request.getSelectedChapterIndexes() != null ? request.getSelectedChapterIndexes().size() : 0,
                request.getAiConfigId(), request.getEnableAISummary(), request.getEnableSmartContext(), request.getUserId());

        // 验证必要参数
        if (request.getPreviewSessionId() == null || request.getPreviewSessionId().isEmpty()) {
            return Mono.just(ResponseEntity
                    .status(HttpStatus.BAD_REQUEST)
                    .body(new JobIdResponse("预览会话ID不能为空")));
        }

        if (request.getFinalTitle() == null || request.getFinalTitle().trim().isEmpty()) {
            return Mono.just(ResponseEntity
                    .status(HttpStatus.BAD_REQUEST)
                    .body(new JobIdResponse("小说标题不能为空")));
        }

        if (!Boolean.TRUE.equals(request.getAcknowledgeRisks())) {
            return Mono.just(ResponseEntity
                    .status(HttpStatus.BAD_REQUEST)
                    .body(new JobIdResponse("请确认您已了解相关风险和成本")));
        }

        // 确保 userId 传递给后端业务层
        if ((request.getUserId() == null || request.getUserId().isBlank()) && currentUserId != null) {
            request.setUserId(currentUserId);
        }

        return importService.confirmAndStartImport(request)
                .map(jobId -> ResponseEntity
                        .status(HttpStatus.ACCEPTED)
                        .body(new JobIdResponse(jobId)))
                .onErrorResume(e -> {
                    log.error("确认导入失败", e);
                    return Mono.just(ResponseEntity
                            .status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(new JobIdResponse("确认导入失败: " + e.getMessage())));
                });
    }

    /**
     * 清理预览会话
     * 清理临时文件和会话数据
     *
     * @param request 包含预览会话ID的请求
     * @return 清理结果
     */
    @PostMapping("/import/cleanup-preview")
    public Mono<ResponseEntity<Map<String, String>>> cleanupPreviewSession(
            @RequestBody Map<String, String> request) {

        String previewSessionId = request.get("previewSessionId");
        
        if (previewSessionId == null || previewSessionId.isEmpty()) {
            return Mono.just(ResponseEntity
                    .status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", "预览会话ID不能为空")));
        }

        log.info("清理预览会话: {}", previewSessionId);

        return importService.cleanupPreviewSession(previewSessionId)
                .then(Mono.just(ResponseEntity.ok(
                        Map.of("status", "success", "message", "预览会话已清理"))))
                .onErrorReturn(ResponseEntity
                        .status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(Map.of("error", "清理预览会话失败")));
    }

    /**
     * 更新Act标题
     *
     * @param requestData 包含小说ID、Act ID和新标题的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/update-act-title")
    public Mono<NovelWithScenesDto> updateActTitle(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String title = requestData.get("title");

        log.info("更新Act标题: novelId={}, actId={}, title={}", novelId, actId, title);

        return novelService.updateActTitle(novelId, actId, title)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId));
    }

    /**
     * 更新Chapter标题
     *
     * @param requestData 包含小说ID、Act ID、Chapter ID和新标题的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/update-chapter-title")
    public Mono<NovelWithScenesDto> updateChapterTitle(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String chapterId = requestData.get("chapterId");
        String title = requestData.get("title");

        log.info("更新Chapter标题: novelId={}, actId={}, chapterId={}, title={}",
                novelId, actId, chapterId, title);

        return novelService.updateChapterTitle(novelId, chapterId, title)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId));
    }

    /**
     * 更新Scene摘要
     *
     * @param requestData 包含小说ID、Act ID、Chapter ID、Scene ID和新摘要的请求数据
     * @return 操作结果
     */
    @PostMapping("/update-scene-summary")
    public Mono<Scene> updateSceneSummary(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String chapterId = requestData.get("chapterId");
        String sceneId = requestData.get("sceneId");
        String summary = requestData.get("summary");

        log.info("更新Scene摘要: novelId={}, actId={}, chapterId={}, sceneId={}",
                novelId, actId, chapterId, sceneId);

        return sceneService.updateSummary(sceneId, summary);
    }

    /**
     * 添加新Act
     *
     * @param requestData 包含小说ID和标题的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/add-act")
    public Mono<NovelWithScenesDto> addAct(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String title = requestData.get("title");

        log.info("添加新Act: novelId={}, title={}", novelId, title);

        return novelService.addAct(novelId, title, null)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId));
    }

    /**
     * 添加新Chapter
     *
     * @param requestData 包含小说ID、Act ID和标题的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/add-chapter")
    public Mono<NovelWithScenesDto> addChapter(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String title = requestData.get("title");

        log.info("添加新Chapter: novelId={}, actId={}, title={}", novelId, actId, title);

        return novelService.addChapter(novelId, actId, title, null)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId));
    }


    /**
     * 删除Scene
     *
     * @param requestData 包含小说ID、Act ID、Chapter ID和Scene ID的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/delete-scene")
    public Mono<NovelWithScenesDto> deleteScene(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String chapterId = requestData.get("chapterId");
        String sceneId = requestData.get("sceneId");

        log.info("删除Scene: novelId={}, actId={}, chapterId={}, sceneId={}",
                novelId, actId, chapterId, sceneId);

        return sceneService.deleteSceneById(sceneId)
                .then(novelService.getNovelWithAllScenes(novelId));
    }

    /**
     * 移动Scene
     *
     * @param requestData 包含移动Scene所需信息的请求数据
     * @return 更新后的小说数据
     */
    @PostMapping("/scenes/move")
    public Mono<NovelWithScenesDto> moveScene(@RequestBody Map<String, Object> requestData) {
        String novelId = (String) requestData.get("novelId");
        String sourceSceneId = (String) requestData.get("sourceSceneId");
        String targetChapterId = (String) requestData.get("targetChapterId");
        Integer targetIndex = (Integer) requestData.get("targetIndex");

        log.info("移动Scene: novelId={}, sourceSceneId={}, targetChapterId={}, targetIndex={}",
                novelId, sourceSceneId, targetChapterId, targetIndex);

        return novelService.moveScene(novelId, sourceSceneId, targetChapterId, targetIndex)
                .flatMap(novel -> novelService.getNovelWithAllScenes(novelId));
    }

    /**
     * 获取小说详情及其场景摘要（适用于大纲视图） 与getNovelWithScenes不同，此接口只返回场景摘要，不返回完整内容，减少数据传输量
     *
     * @param idDto 包含小说ID的DTO
     * @return 小说及其场景摘要数据
     */
    @PostMapping("/get-with-scene-summaries")
    public Mono<NovelWithSummariesDto>  getNovelWithSceneSummaries(@RequestBody IdDto idDto) {
        String novelId = idDto.getId();
        log.info("获取小说及其场景摘要: novelId={}", novelId);

        return novelService.getNovelWithSceneSummaries(novelId);
    }

    /**
     * 更新小说元数据（标题、作者、系列）
     *
     * @param request 包含小说ID、标题、作者和系列信息的请求
     * @return 更新后的小说
     */
    @PostMapping("/{novelId}/metadata")
    public Mono<Novel> updateNovelMetadata(
            @PathVariable String novelId,
            @RequestBody Map<String, String> requestData) {
        String title = requestData.get("title");
        String author = requestData.get("author");
        String series = requestData.get("seriesName");

        log.info("更新小说元数据: novelId={}, title={}, author={}, series={}",
                novelId, title, author, series);

        return novelService.updateNovelMetadata(novelId, title, author, series);
    }

    /**
     * 获取封面上传凭证
     *
     * @param novelId 小说ID
     * @param requestData 包含文件名和内容类型的请求数据
     * @return 上传凭证（包含上传URL和其他必要参数）
     */
    @PostMapping("/{novelId}/cover-upload-credential")
    public Mono<Map<String, String>> getCoverUploadCredential(
            @PathVariable String novelId,
            @RequestBody Map<String, String> requestData) {
        String fileName = requestData.get("fileName");
        String contentType = requestData.get("contentType");

        if (fileName == null || fileName.isEmpty()) {
            fileName = "cover.jpg";
        }

        if (contentType == null || contentType.isEmpty()) {
            // 根据文件扩展名尝试猜测内容类型
            contentType = getContentTypeFromFileName(fileName);
        }

        log.info("获取封面上传凭证: novelId={}, fileName={}, contentType={}",
                novelId, fileName, contentType);

        final String finalFileName = fileName;
        final String finalContentType = contentType;

        return novelService.getCoverUploadCredential(novelId)
                .doOnNext(credential -> {
                    // 添加原始文件名到返回结果中，方便前端使用
                    credential.put("originalFileName", finalFileName);
                    if (finalContentType != null) {
                        credential.put("contentType", finalContentType);
                    }
                });
    }

    /**
     * 根据文件名获取内容类型
     */
    private String getContentTypeFromFileName(String fileName) {
        if (fileName == null || fileName.isEmpty()) {
            return "application/octet-stream";
        }

        String lowerFileName = fileName.toLowerCase();
        if (lowerFileName.endsWith(".jpg") || lowerFileName.endsWith(".jpeg")) {
            return "image/jpeg";
        } else if (lowerFileName.endsWith(".png")) {
            return "image/png";
        } else if (lowerFileName.endsWith(".gif")) {
            return "image/gif";
        } else if (lowerFileName.endsWith(".webp")) {
            return "image/webp";
        } else if (lowerFileName.endsWith(".bmp")) {
            return "image/bmp";
        } else if (lowerFileName.endsWith(".svg")) {
            return "image/svg+xml";
        }

        return "application/octet-stream";
    }

    /**
     * 更新小说封面URL
     *
     * @param request 包含小说ID和封面URL的请求
     * @return 更新后的小说
     */
    @PostMapping("/{novelId}/cover")
    public Mono<Novel> updateNovelCover(
            @PathVariable String novelId,
            @RequestBody Map<String, String> request) {
        String coverUrl = request.get("coverUrl");
        log.info("更新小说封面: novelId={}, coverUrl={}", novelId, coverUrl);

        return novelService.updateNovelCover(novelId, coverUrl);
    }

    /**
     * 归档小说
     *
     * @param idDto 包含小说ID的DTO
     * @return 已归档的小说
     */
    @PostMapping("/archive")
    public Mono<Novel> archiveNovel(@RequestBody IdDto idDto) {
        return novelService.archiveNovel(idDto.getId());
    }

    /**
     * 恢复已归档小说
     *
     * @param idDto 包含小说ID的DTO
     * @return 恢复后的小说
     */
    @PostMapping("/unarchive")
    public Mono<Novel> unarchiveNovel(@RequestBody IdDto idDto) {
        return novelService.unarchiveNovel(idDto.getId());
    }

    /**
     * 永久删除小说（物理删除）
     *
     * @param idDto 包含小说ID的DTO
     * @return 操作结果
     */
    @PostMapping("/permanently-delete")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> permanentlyDeleteNovel(@RequestBody IdDto idDto) {
        return novelService.permanentlyDeleteNovel(idDto.getId());
    }

    /**
     * 更新小说字数统计
     *
     * @param idDto 小说ID
     * @return 更新后的小说
     */
    @PostMapping("/update-word-count")
    public Mono<Novel> updateNovelWordCount(@RequestBody IdDto idDto) {
        return novelService.updateNovelWordCount(idDto.getId());
    }

    @PostMapping("/update-last-edited-chapter")
    public Mono<Void> updateLastEditedChapter(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String chapterId = requestData.get("chapterId");
        
        if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(chapterId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和章节ID不能为空"));
        }
        
        log.info("更新小说最后编辑章节ID: novelId={}, chapterId={}", novelId, chapterId);
        return novelService.updateLastEditedChapter(novelId, chapterId)
                .then();
    }
    
    @PostMapping("/update-word-counts")
    public Mono<Novel> updateNovelWordCounts(@RequestBody Map<String, Object> requestData) {
        String novelId = (String) requestData.get("novelId");
        
        if (StringUtils.isEmpty(novelId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID不能为空"));
        }
        
        try {
            @SuppressWarnings("unchecked")
            Map<String, Integer> sceneWordCounts = (Map<String, Integer>) requestData.get("sceneWordCounts");
            
            if (sceneWordCounts == null || sceneWordCounts.isEmpty()) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "场景字数数据不能为空"));
            }
            
            log.info("批量更新小说字数统计: novelId={}, 场景数量={}", novelId, sceneWordCounts.size());
            
            // 批量更新场景字数
            return Flux.fromIterable(sceneWordCounts.entrySet())
                    .flatMap(entry -> sceneService.updateSceneWordCount(entry.getKey(), entry.getValue()))
                    .then(novelService.updateNovelWordCount(novelId));
        } catch (Exception e) {
            log.error("更新小说字数统计失败", e);
            return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "更新小说字数统计失败: " + e.getMessage()));
        }
    }

    /**
     * 更新小说结构（只更新结构，不包含场景内容）
     *
     * @param novel 小说结构信息
     * @return 更新后的小说
     */
    @PostMapping("/update-structure")
    public Mono<Novel> updateNovelStructure(@RequestBody Novel novel) {
        if (novel == null || novel.getId() == null) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID不能为空"));
        }
        
        log.info("更新小说结构: novelId={}", novel.getId());
        
        return novelService.findNovelById(novel.getId())
                .switchIfEmpty(Mono.error(new ResponseStatusException(HttpStatus.NOT_FOUND, "小说不存在")))
                .flatMap(existingNovel -> {
                    // 只更新结构字段，保留其他元数据
                    if (novel.getStructure() != null) {
                        existingNovel.setStructure(novel.getStructure());
                    }
                    
                    // 如果需要更新lastEditedChapterId
                    if (novel.getLastEditedChapterId() != null) {
                        existingNovel.setLastEditedChapterId(novel.getLastEditedChapterId());
                    }
                    
                    // 更新时间戳
                    existingNovel.setUpdatedAt(LocalDateTime.now());
                    
                    return novelService.updateNovel(existingNovel.getId(), existingNovel);
                })
                .doOnSuccess(updatedNovel -> log.info("小说结构更新成功: novelId={}", updatedNovel.getId()))
                .doOnError(e -> log.error("小说结构更新失败: {}", e.getMessage()));
    }

    /**
     * 添加新卷 - 细粒度操作：只接收卷信息，不需要整个小说结构
     *
     * @param requestData 包含小说ID和新卷信息的请求数据
     * @return 新创建的卷信息
     */
    @PostMapping("/add-act-fine")
    public Mono<Novel.Act> addActFine(@RequestBody Map<String, Object> requestData) {
        String novelId = (String) requestData.get("novelId");
        String title = (String) requestData.get("title");
        String description = (String) requestData.get("description");
        
        if (StringUtils.isEmpty(novelId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID不能为空"));
        }
        
        if (StringUtils.isEmpty(title)) {
            title = "新卷";
        }
        
        log.info("细粒度添加新卷: novelId={}, title={}", novelId, title);
        
        return novelService.addActFine(novelId, title, description)
                .doOnSuccess(act -> log.info("细粒度添加新卷成功: novelId={}, actId={}", novelId, act.getId()));
    }
    
    /**
     * 添加新章节 - 细粒度操作：只接收章节信息，不需要整个小说结构
     *
     * @param requestData 包含小说ID、卷ID和新章节信息的请求数据
     * @return 新创建的章节信息
     */
    @PostMapping("/add-chapter-fine")
    public Mono<Novel.Chapter> addChapterFine(@RequestBody Map<String, Object> requestData) {
        String novelId = (String) requestData.get("novelId");
        String actId = (String) requestData.get("actId");
        String title = (String) requestData.get("title");
        String description = (String) requestData.get("description");
        
        if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(actId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和卷ID不能为空"));
        }
        
        if (StringUtils.isEmpty(title)) {
            title = "新章节";
        }
        
        log.info("细粒度添加新章节: novelId={}, actId={}, title={}", novelId, actId, title);
        
        return novelService.addChapterFine(novelId, actId, title, description)
                .doOnSuccess(chapter -> log.info("细粒度添加新章节成功: novelId={}, actId={}, chapterId={}", 
                        novelId, actId, chapter.getId()));
    }
    
    /**
     * 原子化添加章节和场景 - 在一个事务中同时创建章节和场景，避免数据不一致
     *
     * @param requestData 包含小说ID、卷ID、章节信息和场景信息的请求数据
     * @return 包含新创建章节和场景的响应数据
     */
    @PostMapping("/add-chapter-with-scene")
    public Mono<Map<String, Object>> addChapterWithScene(@RequestBody Map<String, Object> requestData) {
        String novelId = (String) requestData.get("novelId");
        String actId = (String) requestData.get("actId");
        String insertAfterChapterId = (String) requestData.get("insertAfterChapterId");
        String chapterTitle = (String) requestData.get("chapterTitle");
        String sceneTitle = (String) requestData.get("sceneTitle");
        String sceneSummary = (String) requestData.get("sceneSummary");
        String sceneContent = (String) requestData.get("sceneContent");
        
        if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(actId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和卷ID不能为空"));
        }
        
        if (StringUtils.isEmpty(chapterTitle)) {
            chapterTitle = "AI生成章节";
        }
        
        if (StringUtils.isEmpty(sceneTitle)) {
            sceneTitle = "AI生成场景";
        }
        
        log.info("原子化添加章节和场景: novelId={}, actId={}, afterChapterId={}, chapterTitle={}, sceneTitle={}", 
                novelId, actId, insertAfterChapterId, chapterTitle, sceneTitle);
        
        Mono<Map<String, Object>> op = (insertAfterChapterId != null && !insertAfterChapterId.isBlank())
                ? novelService.addChapterWithSceneAt(novelId, actId, insertAfterChapterId, chapterTitle, sceneTitle, sceneSummary, sceneContent)
                : novelService.addChapterWithScene(novelId, actId, chapterTitle, sceneTitle, sceneSummary, sceneContent);

        return op
                .doOnSuccess(result -> log.info("原子化添加章节和场景成功: novelId={}, chapterId={}, sceneId={}", 
                        novelId, result.get("chapterId"), result.get("sceneId")))
                .doOnError(e -> log.error("原子化添加章节和场景失败: novelId={}, actId={}, error={}", 
                        novelId, actId, e.getMessage()));
    }
    
    /**
     * 删除卷 - 细粒度操作：只接收小说ID和卷ID
     *
     * @param requestData 包含小说ID和卷ID的请求数据
     * @return 操作结果
     */
    @PostMapping("/delete-act-fine")
    public Mono<Boolean> deleteActFine(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        
        if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(actId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和卷ID不能为空"));
        }
        
        log.info("细粒度删除卷: novelId={}, actId={}", novelId, actId);
        
        return novelService.deleteActFine(novelId, actId)
                .doOnSuccess(success -> {
                    if (success) {
                        log.info("细粒度删除卷成功: novelId={}, actId={}", novelId, actId);
                    } else {
                        log.warn("细粒度删除卷失败: novelId={}, actId={}", novelId, actId);
                    }
                });
    }
    
    /**
     * 删除章节 - 细粒度操作：只接收小说ID、卷ID和章节ID
     *
     * @param requestData 包含小说ID、卷ID和章节ID的请求数据
     * @return 操作结果
     */
    @PostMapping("/delete-chapter-fine")
    public Mono<Boolean> deleteChapterFine(@RequestBody Map<String, String> requestData) {
        String novelId = requestData.get("novelId");
        String actId = requestData.get("actId");
        String chapterId = requestData.get("chapterId");
        
        if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(actId) || StringUtils.isEmpty(chapterId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID、卷ID和章节ID不能为空"));
        }
        
        log.info("细粒度删除章节: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
        
        return novelService.deleteChapterFine(novelId, actId, chapterId)
                .doOnSuccess(success -> {
                    if (success) {
                        log.info("细粒度删除章节成功: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
                    } else {
                        log.warn("细粒度删除章节失败: novelId={}, actId={}, chapterId={}", novelId, actId, chapterId);
                    }
                });
    }
}
