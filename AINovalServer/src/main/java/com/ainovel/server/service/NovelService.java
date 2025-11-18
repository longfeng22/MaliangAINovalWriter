package com.ainovel.server.service;

import java.util.List;
import java.util.Map;

import com.ainovel.server.domain.model.Character;
import com.ainovel.server.domain.model.Novel;
import com.ainovel.server.domain.model.Novel.Act;
import com.ainovel.server.domain.model.Novel.Chapter;
import com.ainovel.server.domain.model.NovelSceneContent;
import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.web.dto.CreatedChapterInfo;
import com.ainovel.server.web.dto.NovelWithScenesDto;
import com.ainovel.server.web.dto.NovelWithSummariesDto;
import com.ainovel.server.web.dto.ChaptersForPreloadDto;
import com.ainovel.server.service.cache.NovelStructureCache.ContainIndex;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 小说服务接口
 */
public interface NovelService {

    /**
     * 创建小说
     *
     * @param novel 小说信息
     * @return 创建的小说
     */
    Mono<Novel> createNovel(Novel novel);

    /**
     * 根据ID查找小说
     *
     * @param id 小说ID
     * @return 小说信息
     */
    Mono<Novel> findNovelById(String id);

    /**
     * 更新小说信息
     *
     * @param id 小说ID
     * @param novel 更新的小说信息
     * @return 更新后的小说
     */
    Mono<Novel> updateNovel(String id, Novel novel);

    /**
     * 更新小说元数据（标题、作者、系列）
     *
     * @param id 小说ID
     * @param title 标题
     * @param author 作者
     * @param series 系列
     * @return 更新后的小说
     */
    Mono<Novel> updateNovelMetadata(String id, String title, String author, String series);

    /**
     * 获取封面上传凭证
     *
     * @param novelId 小说ID
     * @return 上传凭证（包含上传URL和其他必要参数）
     */
    Mono<Map<String, String>> getCoverUploadCredential(String novelId);

    /**
     * 更新小说封面URL
     *
     * @param novelId 小说ID
     * @param coverUrl 封面图片URL
     * @return 更新后的小说
     */
    Mono<Novel> updateNovelCover(String novelId, String coverUrl);

    /**
     * 归档小说
     *
     * @param novelId 小说ID
     * @return 已归档的小说
     */
    Mono<Novel> archiveNovel(String novelId);

    /**
     * 恢复已归档小说
     *
     * @param novelId 小说ID
     * @return 恢复后的小说
     */
    Mono<Novel> unarchiveNovel(String novelId);

    /**
     * 永久删除小说（物理删除）
     *
     * @param novelId 小说ID
     * @return 操作结果
     */
    Mono<Void> permanentlyDeleteNovel(String novelId);

    /**
     * 更新小说信息及其场景内容
     *
     * @param id 小说ID
     * @param novel 更新的小说信息
     * @param scenesByChapter 按章节分组的场景列表
     * @return 更新后的小说
     */
    Mono<Novel> updateNovelWithScenes(String id, Novel novel, Map<String, List<Scene>> scenesByChapter);

    /**
     * 删除小说
     *
     * @param id 小说ID
     * @return 操作结果
     */
    Mono<Void> deleteNovel(String id);

    /**
     * 查找用户的所有小说
     *
     * @param authorId 作者ID
     * @return 小说列表
     */
    Flux<Novel> findNovelsByAuthorId(String authorId);

    /**
     * 根据标题搜索小说
     *
     * @param title 标题关键词
     * @return 小说列表
     */
    Flux<Novel> searchNovelsByTitle(String title);

    /**
     * 获取小说的所有场景
     *
     * @param novelId 小说ID
     * @return 场景列表
     */
    Flux<Scene> getNovelScenes(String novelId);


    /**
     * 获取小说的所有角色
     *
     * @param novelId 小说ID
     * @return 角色列表
     */
    Flux<Character> getNovelCharacters(String novelId);


    /**
     * 更新小说最后编辑的章节
     *
     * @param novelId 小说ID
     * @param chapterId 章节ID
     * @return 更新后的小说
     */
    Mono<Novel> updateLastEditedChapter(String novelId, String chapterId);

    /**
     * 获取章节上下文场景（前后五章）
     *
     * @param novelId 小说ID
     * @param authorId 作者ID
     * @return 场景列表
     */
    Mono<List<Scene>> getChapterContextScenes(String novelId, String authorId);

    /**
     * 获取整本小说内容，包括小说基本信息及其所有场景
     *
     * @param novelId 小说ID
     * @return 含小说及其所有场景数据的DTO
     */
    Mono<NovelWithScenesDto> getNovelWithAllScenes(String novelId);

    /**
     * 获取小说详情及其部分场景内容（分页加载） 基于上次编辑章节为中心，获取前后指定数量的章节及其场景内容
     *
     * @param novelId 小说ID
     * @param lastEditedChapterId 上次编辑的章节ID，作为页面中心点
     * @param chaptersLimit 要加载的章节数量限制（前后各加载多少章节）
     * @return 小说及其分页加载的场景数据
     */
    Mono<NovelWithScenesDto> getNovelWithPaginatedScenes(String novelId, String lastEditedChapterId, int chaptersLimit);

    /**
     * 加载更多场景内容 根据方向（向上或向下）加载更多章节的场景内容
     *
     * @param novelId 小说ID
     * @param actId 卷ID，用于限制在指定卷内分页加载
     * @param fromChapterId 从哪个章节开始加载
     * @param direction 加载方向，"up"表示向上加载，"down"表示向下加载
     * @param chaptersLimit 要加载的章节数量
     * @return 加载的更多场景数据，按章节组织
     */
    Mono<Map<String, List<Scene>>> loadMoreScenes(String novelId, String actId, String fromChapterId, String direction, int chaptersLimit);

    /**
     * 获取当前章节后面指定数量的章节和场景内容，允许跨卷加载
     *
     * @param novelId 小说ID
     * @param currentChapterId 当前章节ID
     * @param chaptersLimit 要加载的章节数量
     * @param includeCurrentChapter 是否包含当前章节的场景内容
     * @return 小说及其后续章节的场景数据
     */
    Mono<NovelWithScenesDto> getChaptersAfter(String novelId, String currentChapterId, int chaptersLimit, boolean includeCurrentChapter);

    /**
     * 更新卷标题
     *
     * @param novelId 小说ID
     * @param actId 卷ID
     * @param title 新标题
     * @return 更新后的小说
     */
    Mono<Novel> updateActTitle(String novelId, String actId, String title);

    /**
     * 更新章节标题
     *
     * @param novelId 小说ID
     * @param chapterId 章节ID
     * @param title 新标题
     * @return 更新后的小说
     */
    Mono<Novel> updateChapterTitle(String novelId, String chapterId, String title);

    /**
     * 添加新卷
     *
     * @param novelId 小说ID
     * @param title 卷标题
     * @param position 插入位置（如果为null则添加到末尾）
     * @return 更新后的小说
     */
    Mono<Novel> addAct(String novelId, String title, Integer position);

    /**
     * 添加新章节
     *
     * @param novelId 小说ID
     * @param actId 卷ID
     * @param title 章节标题
     * @param position 插入位置（如果为null则添加到末尾）
     * @return 更新后的小说
     */
    Mono<Novel> addChapter(String novelId, String actId, String title, Integer position);

    /**
     * 移动场景位置
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param targetChapterId 目标章节ID
     * @param targetPosition 目标位置
     * @return 更新后的小说
     */
    Mono<Novel> moveScene(String novelId, String sceneId, String targetChapterId, int targetPosition);

    /**
     * 获取小说详情及其场景摘要（不包含场景完整内容） 适用于大纲视图，减少数据传输量
     *
     * @param novelId 小说ID
     * @return 小说及其场景摘要
     */
    Mono<NovelWithSummariesDto> getNovelWithSceneSummaries(String novelId);

    /**
     * 计算并更新小说的总字数
     *
     * @param novelId 小说ID
     * @return 更新后的小说
     */
    Mono<Novel> updateNovelWordCount(String novelId);

    /**
     * 获取指定章节范围内的场景摘要
     *
     * @param novelId 小说ID
     * @param startChapterId 起始章节ID (null 表示从第一章开始)
     * @param endChapterId 结束章节ID (null 表示到最后一章)
     * @return 拼接后的摘要字符串
     */
    Mono<String> getChapterRangeSummaries(String novelId, String startChapterId, String endChapterId);

    /**
     * 获取指定章节范围内的场景内容
     *
     * @param novelId 小说ID
     * @param startChapterId 起始章节ID (null 表示从第一章开始)
     * @param endChapterId 结束章节ID (null 表示到最后一章)
     * @return 拼接后的场景内容字符串
     */
    Mono<String> getChapterRangeContext(String novelId, String startChapterId, String endChapterId);

    /**
     * 添加一个新章节到最后一卷的末尾，并创建一个包含初始摘要的空场景。
     *
     * @param novelId           小说ID
     * @param chapterTitle      新章节标题
     * @param initialSceneSummary 新场景的初始摘要 (会被放入第一个 Scene 的 summary 字段)
     * @param initialSceneTitle 新场景的标题
     * @return 包含新章节ID和新场景ID的 Mono<CreatedChapterInfo>
     */
    Mono<CreatedChapterInfo> addChapterWithInitialScene(String novelId, String chapterTitle, String initialSceneSummary, String initialSceneTitle);

    /**
     * 添加一个新章节到最后一卷的末尾，并创建一个包含初始摘要的空场景。
     *
     * @param novelId           小说ID
     * @param chapterTitle      新章节标题
     * @param initialSceneSummary 新场景的初始摘要 (会被放入第一个 Scene 的 summary 字段)
     * @param initialSceneTitle 新场景的标题
     * @param metadata         章节元数据，用于标记自动生成的内容等信息
     * @return 包含新章节ID和新场景ID的 Mono<CreatedChapterInfo>
     */
    Mono<CreatedChapterInfo> addChapterWithInitialScene(String novelId, String chapterTitle, String initialSceneSummary, String initialSceneTitle, Map<String, Object> metadata);

    /**
     * 更新指定场景的内容。
     *
     * @param novelId   小说ID (用于验证或日志记录)
     * @param chapterId 章节ID (用于验证或日志记录)
     * @param sceneId   要更新的场景ID
     * @param content   新的场景内容
     * @return 更新后的场景 Mono<Scene>
     */
    Mono<Scene> updateSceneContent(String novelId, String chapterId, String sceneId, String content);

    /**
     * 删除章节及其所有场景
     *
     * @param novelId   小说ID
     * @param actId     卷ID
     * @param chapterId 章节ID
     * @return 更新后的小说 Mono<Novel>
     */
    Mono<Novel> deleteChapter(String novelId, String actId, String chapterId);

    /**
     * 细粒度添加卷 - 只提供必要信息，不传整个结构
     *
     * @param novelId    小说ID
     * @param title      卷标题
     * @param description 卷描述 (可为null)
     * @return 新创建的卷信息
     */
    Mono<Act> addActFine(String novelId, String title, String description);

    /**
     * 细粒度添加章节 - 只提供必要信息，不传整个结构
     *
     * @param novelId    小说ID
     * @param actId      卷ID
     * @param title      章节标题
     * @param description 章节描述 (可为null)
     * @return 新创建的章节信息
     */
    Mono<Chapter> addChapterFine(String novelId, String actId, String title, String description);

    /**
     * 原子化添加章节和场景 - 在一个事务中同时创建章节和场景，避免数据不一致
     *
     * @param novelId 小说ID
     * @param actId 卷ID
     * @param chapterTitle 章节标题
     * @param sceneTitle 场景标题
     * @param sceneSummary 场景摘要
     * @param sceneContent 场景内容
     * @return 包含新创建章节和场景信息的Map
     */
    Mono<Map<String, Object>> addChapterWithScene(String novelId, String actId, 
            String chapterTitle, String sceneTitle, String sceneSummary, String sceneContent);

    /**
     * 原子化添加章节和场景，并插入到指定章节之后
     *
     * @param novelId             小说ID
     * @param actId               卷ID（用于限定插入位置所属卷）
     * @param insertAfterChapterId 要插入在其后的章节ID（同一卷内）。若为空或未找到，则追加到卷末尾
     * @param chapterTitle        新章节标题
     * @param sceneTitle          新场景标题
     * @param sceneSummary        新场景摘要
     * @param sceneContent        新场景内容
     * @return 包含新创建章节和场景信息的Map
     */
    Mono<Map<String, Object>> addChapterWithSceneAt(
            String novelId,
            String actId,
            String insertAfterChapterId,
            String chapterTitle,
            String sceneTitle,
            String sceneSummary,
            String sceneContent);

    /**
     * 细粒度删除卷 - 只提供ID，不传整个结构
     *
     * @param novelId    小说ID
     * @param actId      卷ID
     * @return 操作是否成功
     */
    Mono<Boolean> deleteActFine(String novelId, String actId);

    /**
     * 细粒度删除章节 - 只提供ID，不传整个结构
     *
     * @param novelId    小说ID
     * @param actId      卷ID
     * @param chapterId  章节ID
     * @return 操作是否成功
     */
    Mono<Boolean> deleteChapterFine(String novelId, String actId, String chapterId);

    /**
     * 获取指定章节的前一个章节ID
     *
     * @param novelId 小说ID
     * @param chapterId 当前章节ID
     * @return 前一个章节的ID
     */
    Mono<String> getPreviousChapterId(String novelId, String chapterId);

    /**
     * 获取指定章节后面的章节列表（用于预加载）
     * 专门为预加载功能设计，只返回章节列表和场景内容，不返回完整小说结构
     *
     * @param novelId 小说ID
     * @param currentChapterId 当前章节ID
     * @param chaptersLimit 要获取的章节数量限制
     * @param includeCurrentChapter 是否包含当前章节
     * @return 包含章节列表和场景数据的ChaptersForPreloadDto
     */
    Mono<ChaptersForPreloadDto> getChaptersForPreload(String novelId, String currentChapterId, int chaptersLimit, boolean includeCurrentChapter);

    Mono<NovelWithScenesDto> getNovelWithAllScenesText(String id);

    /**
     * 按照小说结构顺序获取所有场景
     * 替代 sceneService.findScenesByNovelIdOrdered 方法
     * 按照卷顺序 -> 章节顺序 -> 场景sequence排序
     * 
     * @param novelId 小说ID
     * @return 按顺序排列的场景列表
     */
    Flux<Scene> findScenesByNovelIdInOrder(String novelId);

    /**
     * 获取小说结构包含索引（章节/场景包含关系），异步缓存。
     */
    Mono<ContainIndex> getContainIndex(String novelId);
}
