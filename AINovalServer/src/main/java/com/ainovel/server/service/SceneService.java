package com.ainovel.server.service;

import java.util.List;

import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.domain.model.Scene.HistoryEntry;
import com.ainovel.server.domain.model.SceneVersionDiff;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 场景服务接口
 */
public interface SceneService {

    /**
     * 根据ID查找场景
     *
     * @param id 场景ID
     * @return 场景信息
     */
    Mono<Scene> findSceneById(String id);

    /**
     * 根据章节ID查找场景
     *
     * @param chapterId 章节ID
     * @return 场景列表
     */
    Flux<Scene> findSceneByChapterId(String chapterId);

    /**
     * 根据章节ID查找场景并按顺序排序
     *
     * @param chapterId 章节ID
     * @return 排序后的场景列表
     */
    Flux<Scene> findSceneByChapterIdOrdered(String chapterId);

    /**
     * 根据小说ID查找场景列表
     *
     * @param novelId 小说ID
     * @return 场景列表
     */
    Flux<Scene> findScenesByNovelId(String novelId);

    /**
     * 根据小说ID查找场景列表并按章节和顺序排序
     *
     * @param novelId 小说ID
     * @return 排序后的场景列表
     */
    Flux<Scene> findScenesByNovelIdOrdered(String novelId);

    /**
     * 根据章节ID列表查找场景
     *
     * @param chapterIds 章节ID列表
     * @return 场景列表
     */
    Flux<Scene> findScenesByChapterIds(List<String> chapterIds);

    /**
     * 根据小说ID和场景类型查找场景
     *
     * @param novelId 小说ID
     * @param sceneType 场景类型
     * @return 场景列表
     */
    Flux<Scene> findScenesByNovelIdAndType(String novelId, String sceneType);

    /**
     * 创建场景
     *
     * @param scene 场景信息
     * @return 创建的场景
     */
    Mono<Scene> createScene(Scene scene);

    /**
     * 批量创建场景
     *
     * @param scenes 场景列表
     * @return 创建的场景列表
     */
    Flux<Scene> createScenes(List<Scene> scenes);

    /**
     * 更新场景
     *
     * @param id 场景ID
     * @param scene 更新的场景信息
     * @return 更新后的场景
     */
    Mono<Scene> updateScene(String id, Scene scene);

    /**
     * 创建或更新场景 如果场景不存在则创建，存在则更新
     *
     * @param scene 场景信息
     * @return 创建或更新后的场景
     */
    Mono<Scene> upsertScene(Scene scene);

    /**
     * 批量创建或更新场景
     *
     * @param scenes 场景列表
     * @return 创建或更新后的场景列表
     */
    Flux<Scene> upsertScenes(List<Scene> scenes);

    /**
     * 删除场景
     *
     * @param id 场景ID
     * @return 操作结果
     */
    Mono<Void> deleteScene(String id);

    /**
     * 删除小说的所有场景
     *
     * @param novelId 小说ID
     * @return 操作结果
     */
    Mono<Void> deleteScenesByNovelId(String novelId);

    /**
     * 删除章节的所有场景
     *
     * @param chapterId 章节ID
     * @return 操作结果
     */
    Mono<Void> deleteScenesByChapterId(String chapterId);

    /**
     * 更新场景内容并保存历史版本
     *
     * @param id 场景ID
     * @param content 新内容
     * @param userId 用户ID
     * @param reason 修改原因
     * @return 更新后的场景
     */
    Mono<Scene> updateSceneContent(String id, String content, String userId, String reason);

    /**
     * 获取场景的历史版本列表
     *
     * @param id 场景ID
     * @return 历史版本列表
     */
    Mono<List<HistoryEntry>> getSceneHistory(String id);

    /**
     * 恢复场景到指定的历史版本
     *
     * @param id 场景ID
     * @param historyIndex 历史版本索引
     * @param userId 用户ID
     * @param reason 恢复原因
     * @return 恢复后的场景
     */
    Mono<Scene> restoreSceneVersion(String id, int historyIndex, String userId, String reason);

    /**
     * 对比两个场景版本
     *
     * @param id 场景ID
     * @param versionIndex1 版本1索引 (-1表示当前版本)
     * @param versionIndex2 版本2索引
     * @return 差异信息
     */
    Mono<SceneVersionDiff> compareSceneVersions(String id, int versionIndex1, int versionIndex2);

    /**
     * 根据ID删除场景
     *
     * @param id 场景ID
     * @return 操作结果
     */
    Mono<Boolean> deleteSceneById(String id);

    /**
     * 更新场景摘要
     *
     * @param id 场景ID
     * @param summary 新摘要内容
     * @return 更新后的场景
     */
    Mono<Scene> updateSummary(String id, String summary);

    /**
     * 添加新场景
     *
     * @param novelId 小说ID
     * @param chapterId 章节ID
     * @param title 场景标题
     * @param summary 场景摘要
     * @param content 场景内容（可选）
     * @param position 插入位置（如果为null则添加到末尾）
     * @return 创建的场景
     */
    Mono<Scene> addScene(String novelId, String chapterId, String title, String summary, String content, Integer position);

    /**
     * 根据ID获取场景，简化版findSceneById
     *
     * @param id 场景ID
     * @return 场景信息
     */
    Mono<Scene> getSceneById(String id);
    
    /**
     * 更新场景内容
     *
     * @param id 场景ID
     * @param content 新内容
     * @param userId 用户ID
     * @return 更新后的场景
     */
    Mono<Scene> updateSceneContent(String id, String content, String userId);
    
    /**
     * 更新场景摘要内容，支持任务执行器
     *
     * @param id 场景ID
     * @param summary 新摘要内容
     * @param userId 用户ID
     * @return 更新后的场景
     */
    Mono<Scene> updateSceneSummary(String id, String summary, String userId);
    
    /**
     * 更新场景字数统计
     *
     * @param id 场景ID
     * @param wordCount 字数
     * @return 更新后的场景
     */
    Mono<Scene> updateSceneWordCount(String id, Integer wordCount);
    
    /**
     * 批量更新场景列表
     *
     * @param scenes 要更新的场景列表
     * @return 更新后的场景列表
     */
    Mono<List<Scene>> updateScenesBatch(List<Scene> scenes);
}
