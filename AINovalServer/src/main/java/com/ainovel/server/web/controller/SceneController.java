package com.ainovel.server.web.controller;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.UUID;
import java.util.ArrayList;

import org.springframework.http.HttpStatus;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.domain.model.Scene.HistoryEntry;
import com.ainovel.server.domain.model.SceneVersionDiff;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.web.base.ReactiveBaseController;
import com.ainovel.server.web.dto.ChapterIdDto;
import com.ainovel.server.web.dto.IdDto;
import com.ainovel.server.web.dto.NovelIdDto;
import com.ainovel.server.web.dto.NovelIdTypeDto;
import com.ainovel.server.web.dto.SceneContentUpdateDto;
import com.ainovel.server.web.dto.SceneRestoreDto;
import com.ainovel.server.web.dto.SceneUpdateDto;
import com.ainovel.server.web.dto.SceneVersionCompareDto;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * 场景控制器
 */
@RestController
@RequestMapping("/api/v1/scenes")
@RequiredArgsConstructor
@Slf4j
public class SceneController extends ReactiveBaseController {

    private final SceneService sceneService;

    /**
     * 获取场景详情
     * 
     * @param idDto 包含场景ID的DTO
     * @return 场景信息
     */
    @PostMapping("/get")
    public Mono<Scene> getScene(@RequestBody IdDto idDto) {
        return sceneService.findSceneById(idDto.getId());
    }

    /**
     * 根据章节ID获取场景
     * 
     * @param chapterIdDto 包含章节ID的DTO
     * @return 场景列表
     */
    @PostMapping("/get-by-chapter")
    public Flux<Scene> getSceneByChapter(@RequestBody ChapterIdDto chapterIdDto) {
        return sceneService.findSceneByChapterId(chapterIdDto.getChapterId());
    }

    /**
     * 根据章节ID获取场景并按顺序排序
     * 
     * @param chapterIdDto 包含章节ID的DTO
     * @return 排序后的场景列表
     */
    @PostMapping("/get-by-chapter-ordered")
    public Flux<Scene> getSceneByChapterOrdered(@RequestBody ChapterIdDto chapterIdDto) {
        return sceneService.findSceneByChapterIdOrdered(chapterIdDto.getChapterId());
    }

    /**
     * 根据小说ID获取所有场景
     * 
     * @param novelIdDto 包含小说ID的DTO
     * @return 场景列表
     */
    @PostMapping("/get-by-novel")
    public Flux<Scene> getScenesByNovel(@RequestBody NovelIdDto novelIdDto) {
        return sceneService.findScenesByNovelId(novelIdDto.getNovelId());
    }

    /**
     * 根据小说ID获取所有场景并按章节和顺序排序
     * 
     * @param novelIdDto 包含小说ID的DTO
     * @return 排序后的场景列表
     */
    @PostMapping("/get-by-novel-ordered")
    public Flux<Scene> getScenesByNovelOrdered(@RequestBody NovelIdDto novelIdDto) {
        return sceneService.findScenesByNovelIdOrdered(novelIdDto.getNovelId());
    }

    /**
     * 根据小说ID和场景类型获取场景
     * 
     * @param novelIdTypeDto 包含小说ID和场景类型的DTO
     * @return 场景列表
     */
    @PostMapping("/get-by-novel-type")
    public Flux<Scene> getScenesByNovelAndType(@RequestBody NovelIdTypeDto novelIdTypeDto) {
        return sceneService.findScenesByNovelIdAndType(novelIdTypeDto.getNovelId(), novelIdTypeDto.getType());
    }

    /**
     * 创建场景
     * 
     * @param scene 场景信息
     * @return 创建的场景
     */
    @PostMapping("/create")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Scene> createScene(@RequestBody Scene scene) {
        return sceneService.createScene(scene);
    }

    /**
     * 批量创建场景
     * 
     * @param scenes 场景列表
     * @return 创建的场景列表
     */
    @PostMapping("/create-batch")
    @ResponseStatus(HttpStatus.CREATED)
    public Flux<Scene> createScenes(@RequestBody List<Scene> scenes) {
        return sceneService.createScenes(scenes);
    }

    /**
     * 更新场景
     * 
     * @param sceneUpdateDto 包含场景ID和更新信息的DTO
     * @return 更新后的场景
     */
    @PostMapping("/update")
    public Mono<Scene> updateScene(@RequestBody SceneUpdateDto sceneUpdateDto) {
        return sceneService.updateScene(sceneUpdateDto.getId(), sceneUpdateDto.getScene());
    }

    /**
     * 创建或更新场景
     * 如果场景不存在则创建，存在则更新
     * 
     * @param scene 场景信息
     * @return 创建或更新后的场景
     */
    @PostMapping("/upsert")
    public Mono<Scene> upsertScene(@RequestBody Scene scene) {
        return sceneService.upsertScene(scene);
    }

    /**
     * 批量创建或更新场景
     * 
     * @param scenes 场景列表
     * @return 创建或更新后的场景列表
     */
    @PostMapping("/upsert-batch")
    public Flux<Scene> upsertScenes(@RequestBody List<Scene> scenes) {
        return sceneService.upsertScenes(scenes);
    }

    /**
     * 删除场景
     * 
     * @param idDto 包含场景ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteScene(@RequestBody IdDto idDto) {
        return sceneService.deleteScene(idDto.getId());
    }

    /**
     * 删除小说的所有场景
     * 
     * @param novelIdDto 包含小说ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete-by-novel")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteScenesByNovel(@RequestBody NovelIdDto novelIdDto) {
        return sceneService.deleteScenesByNovelId(novelIdDto.getNovelId());
    }

    /**
     * 删除章节的所有场景
     * 
     * @param chapterIdDto 包含章节ID的DTO
     * @return 操作结果
     */
    @PostMapping("/delete-by-chapter")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteScenesByChapter(@RequestBody ChapterIdDto chapterIdDto) {
        return sceneService.deleteScenesByChapterId(chapterIdDto.getChapterId());
    }

    /**
     * 更新场景内容并保存历史版本
     * 
     * @param updateDto 更新数据传输对象
     * @return 更新后的场景
     */
    @PostMapping("/update-content")
    public Mono<Scene> updateSceneContent(@RequestBody SceneContentUpdateDto updateDto) {
        return sceneService.updateSceneContent(updateDto.getId(), updateDto.getContent(), updateDto.getUserId(),
                updateDto.getReason());
    }

    /**
     * 获取场景的历史版本列表
     * 
     * @param idDto 包含场景ID的DTO
     * @return 历史版本列表
     */
    @PostMapping("/get-history")
    public Mono<List<HistoryEntry>> getSceneHistory(@RequestBody IdDto idDto) {
        return sceneService.getSceneHistory(idDto.getId());
    }

    /**
     * 恢复场景到指定的历史版本
     * 
     * @param restoreDto 恢复数据传输对象
     * @return 恢复后的场景
     */
    @PostMapping("/restore")
    public Mono<Scene> restoreSceneVersion(@RequestBody SceneRestoreDto restoreDto) {
        return sceneService.restoreSceneVersion(restoreDto.getId(), restoreDto.getHistoryIndex(),
                restoreDto.getUserId(), restoreDto.getReason());
    }

    /**
     * 对比两个场景版本
     * 
     * @param compareDto 对比数据传输对象
     * @return 差异信息
     */
    @PostMapping("/compare")
    public Mono<SceneVersionDiff> compareSceneVersions(@RequestBody SceneVersionCompareDto compareDto) {
        return sceneService.compareSceneVersions(compareDto.getId(), compareDto.getVersionIndex1(),
                compareDto.getVersionIndex2());
    }

    @PostMapping("/update-batch")
    public Mono<List<Scene>> updateScenesBatch(@RequestBody Map<String, Object> requestData) {
        try {
            String novelId = (String) requestData.get("novelId");
            
            if (StringUtils.isEmpty(novelId)) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID不能为空"));
            }
            
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> scenes = (List<Map<String, Object>>) requestData.get("scenes");
            
            if (scenes == null || scenes.isEmpty()) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "场景数据不能为空"));
            }
            
            // 将Map列表转换为Scene对象列表
            ObjectMapper mapper = new ObjectMapper();
            List<Scene> sceneList = scenes.stream()
                    .map(sceneMap -> mapper.convertValue(sceneMap, Scene.class))
                    .collect(Collectors.toList());
            
            // 批量更新场景，返回更新后的场景列表
            return sceneService.updateScenesBatch(sceneList);
        } catch (Exception e) {
            log.error("批量更新场景失败", e);
            return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "批量更新场景失败: " + e.getMessage()));
        }
    }
    
    /**
     * 细粒度添加场景：只需传入必要的场景信息，不需要整个小说结构
     * 
     * @param requestData 包含小说ID、章节ID和场景基本信息的请求
     * @return 新创建的场景
     */
    @PostMapping("/add-scene-fine")
    public Mono<Scene> addSceneFine(@RequestBody Map<String, Object> requestData) {
        try {
            String novelId = (String) requestData.get("novelId");
            String chapterId = (String) requestData.get("chapterId");
            String title = (String) requestData.get("title");
            String summary = (String) requestData.get("summary");
            String content = (String) requestData.get("content"); // 新增：支持同时设置内容
            Integer position = requestData.get("position") != null ? 
                    Integer.valueOf(requestData.get("position").toString()) : null;
            
            if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(chapterId)) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和章节ID不能为空"));
            }
            
            if (StringUtils.isEmpty(title)) {
                title = "新场景";
            }
            
            log.info("细粒度添加场景: novelId={}, chapterId={}, title={}", novelId, chapterId, title);
            
            return sceneService.addScene(novelId, chapterId, title, summary, content, position)
                    .doOnSuccess(scene -> log.info("细粒度添加场景成功: sceneId={}", scene.getId()));
        } catch (Exception e) {
            log.error("细粒度添加场景失败", e);
            return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "添加场景失败: " + e.getMessage()));
        }
    }
    
    /**
     * 细粒度删除场景：只需传入场景ID
     * 
     * @param requestData 包含场景ID的请求
     * @return 操作结果
     */
    @PostMapping("/delete-scene-fine")
    public Mono<Boolean> deleteSceneFine(@RequestBody Map<String, String> requestData) {
        String sceneId = requestData.get("sceneId");
        
        if (StringUtils.isEmpty(sceneId)) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "场景ID不能为空"));
        }
        
        log.info("细粒度删除场景: sceneId={}", sceneId);
        
        return sceneService.deleteSceneById(sceneId)
                .doOnSuccess(success -> {
                    if (success) {
                        log.info("细粒度删除场景成功: sceneId={}", sceneId);
                    } else {
                        log.warn("细粒度删除场景失败: sceneId={}", sceneId);
                    }
                });
    }
    
    /**
     * 细粒度批量添加场景：一次添加多个场景到同一章节
     * 
     * @param requestData 包含小说ID、章节ID和场景列表的请求
     * @return 新创建的场景列表
     */
    @PostMapping("/add-scenes-batch-fine")
    public Mono<List<Scene>> addScenesBatchFine(@RequestBody Map<String, Object> requestData) {
        try {
            String novelId = (String) requestData.get("novelId");
            String chapterId = (String) requestData.get("chapterId");
            
            if (StringUtils.isEmpty(novelId) || StringUtils.isEmpty(chapterId)) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "小说ID和章节ID不能为空"));
            }
            
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> sceneDataList = (List<Map<String, Object>>) requestData.get("scenes");
            
            if (sceneDataList == null || sceneDataList.isEmpty()) {
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "场景数据不能为空"));
            }
            
            log.info("细粒度批量添加场景: novelId={}, chapterId={}, 场景数量={}", 
                     novelId, chapterId, sceneDataList.size());
            
            // 创建场景列表
            List<Scene> newScenes = new ArrayList<>();
            for (Map<String, Object> sceneData : sceneDataList) {
                Scene scene = new Scene();
                scene.setId(UUID.randomUUID().toString()); // 生成新ID
                scene.setNovelId(novelId);
                scene.setChapterId(chapterId);
                scene.setTitle((String) sceneData.get("title"));
                scene.setSummary((String) sceneData.get("summary"));
                scene.setContent((String) sceneData.getOrDefault("content", "[{\"insert\":\"\\n\"}]"));
                scene.setWordCount(0); // 初始字数
                
                newScenes.add(scene);
            }
            
            // 批量创建场景
            return sceneService.createScenes(newScenes)
                    .collectList()
                    .doOnSuccess(scenes -> log.info("细粒度批量添加场景成功: 数量={}", scenes.size()));
        } catch (Exception e) {
            log.error("细粒度批量添加场景失败", e);
            return Mono.error(new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "批量添加场景失败: " + e.getMessage()));
        }
    }
}