package com.ainovel.server.service.fanqie.example;

import com.ainovel.server.service.fanqie.FanqieNovelService;
import com.ainovel.server.service.fanqie.dto.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Duration;

/**
 * 番茄小说服务使用示例
 * 
 * 注意：这只是示例代码，不会被实际加载到Spring容器中
 * 使用时请根据实际业务需求进行调整
 */
@Slf4j
// @Service  // 注释掉，仅作为示例
public class FanqieServiceUsageExample {
    
    @Autowired
    private FanqieNovelService fanqieNovelService;
    
    /**
     * 示例1: 搜索小说
     */
    public Mono<FanqieSearchResult> searchNovelExample() {
        String keyword = "斗罗大陆";
        
        return fanqieNovelService.searchNovels(keyword)
                .doOnSuccess(result -> {
                    log.info("搜索关键词: {}, 找到 {} 个结果", 
                            keyword, 
                            result.getResults() != null ? result.getResults().size() : 0);
                    
                    if (result.getResults() != null && !result.getResults().isEmpty()) {
                        result.getResults().forEach(novel -> {
                            log.info("- 小说ID: {}, 标题: {}, 作者: {}", 
                                    novel.getId(), novel.getTitle(), novel.getAuthor());
                        });
                    }
                })
                .doOnError(error -> {
                    log.error("搜索失败: {}", error.getMessage(), error);
                });
    }
    
    /**
     * 示例2: 获取小说详情
     */
    public Mono<FanqieNovelDetail> getNovelDetailExample(String novelId) {
        return fanqieNovelService.getNovelDetail(novelId)
                .doOnSuccess(detail -> {
                    log.info("=== 小说详情 ===");
                    log.info("标题: {}", detail.getTitle());
                    log.info("作者: {}", detail.getAuthor());
                    log.info("状态: {}", detail.getStatus());
                    log.info("标签: {}", detail.getTags());
                    log.info("总章节数: {}", detail.getTotalChapters());
                    log.info("简介: {}", detail.getDescription());
                })
                .doOnError(error -> {
                    log.error("获取小说详情失败: novelId={}, error={}", 
                            novelId, error.getMessage(), error);
                });
    }
    
    /**
     * 示例3: 添加下载任务（完整下载）
     */
    public Mono<FanqieDownloadTask> downloadFullNovelExample(String novelId) {
        return fanqieNovelService.addNovelDownloadTask(novelId, null)
                .doOnSuccess(task -> {
                    log.info("下载任务创建成功:");
                    log.info("- 任务ID: {}", task.getId());
                    log.info("- 小说ID: {}", task.getNovelId());
                    log.info("- 状态: {}", task.getStatus());
                    log.info("- Celery任务ID: {}", task.getCeleryTaskId());
                })
                .doOnError(error -> {
                    log.error("创建下载任务失败: novelId={}, error={}", 
                            novelId, error.getMessage(), error);
                });
    }
    
    /**
     * 示例4: 添加下载任务（预览模式，仅下载前10章）
     */
    public Mono<FanqieDownloadTask> downloadPreviewExample(String novelId) {
        int maxChapters = 10;
        
        return fanqieNovelService.addNovelDownloadTask(novelId, maxChapters)
                .doOnSuccess(task -> {
                    log.info("预览下载任务创建成功（最多{}章）: 任务ID={}", 
                            maxChapters, task.getId());
                });
    }
    
    /**
     * 示例5: 查询所有下载任务
     */
    public Mono<FanqieTaskList> listAllTasksExample() {
        return fanqieNovelService.getDownloadTasks()
                .doOnSuccess(taskList -> {
                    log.info("=== 下载任务列表 ===");
                    if (taskList.getTasks() != null && !taskList.getTasks().isEmpty()) {
                        taskList.getTasks().forEach(task -> {
                            log.info("任务ID: {}, 小说: {}, 状态: {}, 进度: {}%", 
                                    task.getId(),
                                    task.getNovel() != null ? task.getNovel().getTitle() : "未知",
                                    task.getStatus(),
                                    task.getProgress());
                        });
                    } else {
                        log.info("暂无下载任务");
                    }
                });
    }
    
    /**
     * 示例6: 查询特定任务状态
     */
    public Mono<FanqieDownloadTask> checkTaskStatusExample(String celeryTaskId) {
        return fanqieNovelService.getTaskStatus(celeryTaskId)
                .doOnSuccess(task -> {
                    log.info("任务状态查询结果:");
                    log.info("- 状态: {}", task.getStatus());
                    log.info("- 进度: {}%", task.getProgress());
                    log.info("- 消息: {}", task.getMessage());
                });
    }
    
    /**
     * 示例7: 获取章节列表
     */
    public Mono<FanqieChapterList> getChapterListExample(String novelId) {
        int page = 1;
        int perPage = 20;
        String order = "asc";
        
        return fanqieNovelService.getChapterList(novelId, page, perPage, order)
                .doOnSuccess(chapterList -> {
                    log.info("=== 章节列表 ===");
                    log.info("总章节数: {}", chapterList.getTotal());
                    log.info("当前页: {}/{}", chapterList.getPage(), chapterList.getPages());
                    
                    if (chapterList.getChapters() != null) {
                        chapterList.getChapters().forEach(chapter -> {
                            log.info("第{}章: {}", chapter.getIndex(), chapter.getTitle());
                        });
                    }
                });
    }
    
    /**
     * 示例8: 获取章节内容
     */
    public Mono<FanqieChapter> getChapterContentExample(String novelId, String chapterId) {
        return fanqieNovelService.getChapterContent(novelId, chapterId)
                .doOnSuccess(chapter -> {
                    log.info("=== 章节内容 ===");
                    log.info("章节: 第{}章 - {}", chapter.getIndex(), chapter.getTitle());
                    log.info("内容长度: {} 字", 
                            chapter.getContent() != null ? chapter.getContent().length() : 0);
                    log.info("内容预览: {}", 
                            chapter.getContent() != null && chapter.getContent().length() > 100 
                                    ? chapter.getContent().substring(0, 100) + "..." 
                                    : chapter.getContent());
                });
    }
    
    /**
     * 示例9: 完整的小说导入流程
     */
    public Mono<String> completeImportFlowExample(String keyword) {
        return fanqieNovelService.searchNovels(keyword)
                // 步骤1: 搜索小说
                .flatMap(searchResult -> {
                    if (searchResult.getResults() == null || searchResult.getResults().isEmpty()) {
                        return Mono.error(new RuntimeException("未找到小说: " + keyword));
                    }
                    
                    FanqieNovelInfo firstNovel = searchResult.getResults().get(0);
                    log.info("步骤1: 找到小说 - ID: {}, 标题: {}", 
                            firstNovel.getId(), firstNovel.getTitle());
                    
                    return Mono.just(firstNovel.getId());
                })
                // 步骤2: 获取详情
                .flatMap(novelId -> 
                    fanqieNovelService.getNovelDetail(novelId)
                            .map(detail -> {
                                log.info("步骤2: 获取详情 - 作者: {}, 章节数: {}", 
                                        detail.getAuthor(), detail.getTotalChapters());
                                return novelId;
                            })
                )
                // 步骤3: 创建下载任务
                .flatMap(novelId -> 
                    fanqieNovelService.addNovelDownloadTask(novelId, null)
                            .map(task -> {
                                log.info("步骤3: 创建下载任务 - 任务ID: {}, 状态: {}", 
                                        task.getId(), task.getStatus());
                                return task.getCeleryTaskId();
                            })
                )
                // 步骤4: 等待一段时间后检查状态（实际使用中应该用轮询或WebSocket）
                .flatMap(celeryTaskId -> 
                    Mono.delay(Duration.ofSeconds(5))
                            .then(fanqieNovelService.getTaskStatus(celeryTaskId))
                            .map(task -> {
                                log.info("步骤4: 检查状态 - 状态: {}, 进度: {}%", 
                                        task.getStatus(), task.getProgress());
                                return String.format("导入流程完成，任务状态: %s, 进度: %d%%", 
                                        task.getStatus(), task.getProgress());
                            })
                )
                // 错误处理
                .onErrorResume(error -> {
                    log.error("导入流程失败: {}", error.getMessage(), error);
                    return Mono.just("导入失败: " + error.getMessage());
                });
    }
    
    /**
     * 示例10: 带重试和超时的错误处理
     */
    public Mono<FanqieSearchResult> searchWithRetryExample(String keyword) {
        return fanqieNovelService.searchNovels(keyword)
                .timeout(Duration.ofSeconds(10))  // 10秒超时
                .retry(3)  // 失败重试3次
                .onErrorResume(error -> {
                    log.error("搜索失败（已重试3次）: {}", error.getMessage());
                    // 返回空结果而不是抛出异常
                    return Mono.just(FanqieSearchResult.builder()
                            .results(java.util.Collections.emptyList())
                            .build());
                });
    }
}



