package com.ainovel.server.service.fanqie.impl;

import com.ainovel.server.service.fanqie.FanqieNovelService;
import com.ainovel.server.service.fanqie.dto.*;
import io.netty.channel.ChannelOption;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.Map;

/**
 * 番茄小说下载服务实现（内部API模式，无需认证）
 */
@Slf4j
@Service
public class FanqieNovelServiceImpl implements FanqieNovelService {
    
    private final WebClient webClient;
    
    public FanqieNovelServiceImpl(
            @Value("${fanqie.api.base-url:http://127.0.0.1:5000}") String baseUrl,
            @Value("${fanqie.api.timeout:30}") int timeoutSeconds
    ) {
        // 配置HttpClient
        HttpClient httpClient = HttpClient.create()
                .responseTimeout(Duration.ofSeconds(timeoutSeconds))
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10000);
        
        // 创建WebClient（内部API模式，无需认证）
        this.webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
        
        log.info("番茄小说服务客户端初始化完成（内部API模式），Base URL: {}", baseUrl);
    }
    
    @Override
    public Mono<String> login(String username, String password) {
        // 内部API模式，不需要登录
        log.warn("内部API模式下login方法已废弃，无需调用");
        return Mono.just("");
    }
    
    @Override
    public Mono<FanqieSearchResult> searchNovels(String query) {
        log.info("搜索番茄小说: {}", query);
        
        return webClient.get()
                .uri(uriBuilder -> uriBuilder
                        .path("/api/search")
                        .queryParam("query", query)
                        .build())
                .retrieve()
                .bodyToMono(FanqieSearchResult.class)
                .doOnSuccess(result -> log.info("搜索成功，找到 {} 个结果", 
                        result.getResults() != null ? result.getResults().size() : 0));
    }
    
    @Override
    public Mono<FanqieNovelListResponse> getNovelList(FanqieNovelListRequest request) {
        log.info("获取番茄小说列表: page={}, perPage={}, search={}, tags={}, status={}, sort={}, order={}", 
                request.getPage(), request.getPerPage(), request.getSearch(), 
                request.getTags(), request.getStatus(), request.getSort(), request.getOrder());
        
        return webClient.get()
                .uri(uriBuilder -> {
                    var builder = uriBuilder.path("/api/novels")
                            .queryParam("page", request.getPage())
                            .queryParam("per_page", request.getPerPage());
                    
                    // 添加可选参数
                    if (request.getSearch() != null && !request.getSearch().isEmpty()) {
                        builder.queryParam("search", request.getSearch());
                    }
                    if (request.getTags() != null && !request.getTags().isEmpty()) {
                        builder.queryParam("tags", request.getTags());
                    }
                    if (request.getStatus() != null && !request.getStatus().isEmpty()) {
                        builder.queryParam("status", request.getStatus());
                    }
                    if (request.getSort() != null && !request.getSort().isEmpty()) {
                        builder.queryParam("sort", request.getSort());
                    }
                    if (request.getOrder() != null && !request.getOrder().isEmpty()) {
                        builder.queryParam("order", request.getOrder());
                    }
                    
                    return builder.build();
                })
                .retrieve()
                .bodyToMono(FanqieNovelListResponse.class)
                .doOnSuccess(response -> log.info("获取小说列表成功: total={}, page={}/{}", 
                        response.getTotal(), response.getPage(), response.getPages()));
    }
    
    @Override
    public Mono<FanqieNovelDetail> getNovelDetail(String novelId) {
        log.info("获取番茄小说详情: {}", novelId);
        
        return webClient.get()
                .uri("/api/novels/{novelId}", novelId)
                .retrieve()
                .bodyToMono(FanqieNovelDetail.class)
                .doOnSuccess(detail -> log.info("获取小说详情成功: {}", detail.getTitle()));
    }
    
    @Override
    public Mono<FanqieDownloadTask> addNovelDownloadTask(String novelId, Integer maxChapters) {
        log.info("添加番茄小说下载任务: novelId={}, maxChapters={}", novelId, maxChapters);
        
        FanqieDownloadRequest request = FanqieDownloadRequest.builder()
                .novelId(novelId)
                .maxChapters(maxChapters)
                .build();
        
        return webClient.post()
                .uri("/api/novels")
                .bodyValue(request)
                .retrieve()
                .bodyToMono(FanqieDownloadTask.class)
                .doOnSuccess(task -> log.info("下载任务创建成功: taskId={}, status={}", 
                        task.getId(), task.getStatus()));
    }
    
    @Override
    public Mono<FanqieTaskList> getDownloadTasks() {
        log.info("获取番茄小说下载任务列表");
        
        return webClient.get()
                .uri("/api/tasks/list")
                .retrieve()
                .bodyToMono(FanqieTaskList.class)
                .doOnSuccess(taskList -> log.info("获取任务列表成功，共 {} 个任务", 
                        taskList.getTasks() != null ? taskList.getTasks().size() : 0));
    }
    
    @Override
    public Mono<FanqieDownloadTask> getTaskStatus(String celeryTaskId) {
        log.info("获取番茄小说任务状态: {}", celeryTaskId);
        
        return webClient.get()
                .uri("/api/tasks/status/{celeryTaskId}", celeryTaskId)
                .retrieve()
                .bodyToMono(FanqieDownloadTask.class)
                .doOnSuccess(task -> log.info("任务状态: {}", task.getStatus()));
    }
    
    @Override
    public Mono<FanqieDownloadTask> terminateTask(Long taskId) {
        log.info("终止番茄小说下载任务: {}", taskId);
        
        return webClient.post()
                .uri("/api/tasks/{taskId}/terminate", taskId)
                .retrieve()
                .bodyToMono(FanqieDownloadTask.class)
                .doOnSuccess(task -> log.info("任务终止成功: taskId={}", task.getId()));
    }
    
    @Override
    public Mono<String> deleteTask(Long taskId) {
        log.info("删除番茄小说任务记录: {}", taskId);
        
        return webClient.delete()
                .uri("/api/tasks/{taskId}", taskId)
                .retrieve()
                .bodyToMono(Map.class)
                .map(response -> (String) response.get("message"))
                .doOnSuccess(message -> log.info("任务删除成功: {}", message));
    }
    
    @Override
    public Mono<FanqieDownloadTask> redownloadTask(Long taskId) {
        log.info("重新下载番茄小说任务: {}", taskId);
        
        return webClient.post()
                .uri("/api/tasks/{taskId}/redownload", taskId)
                .retrieve()
                .bodyToMono(FanqieDownloadTask.class)
                .doOnSuccess(task -> log.info("重新下载任务创建成功: taskId={}", task.getId()));
    }
    
    @Override
    public Mono<FanqieChapterList> getChapterList(String novelId, Integer page, Integer perPage, String order) {
        log.info("获取番茄小说章节列表: novelId={}, page={}, perPage={}, order={}", 
                novelId, page, perPage, order);
        
        return webClient.get()
                .uri(uriBuilder -> uriBuilder
                        .path("/api/novels/{novelId}/chapters")
                        .queryParam("page", page != null ? page : 1)
                        .queryParam("per_page", perPage != null ? perPage : 50)
                        .queryParam("order", order != null ? order : "asc")
                        .build(novelId))
                .retrieve()
                .bodyToMono(FanqieChapterList.class)
                .doOnSuccess(chapterList -> log.info("获取章节列表成功，共 {} 章", 
                        chapterList.getTotal()));
    }
    
    @Override
    public Mono<FanqieChapter> getChapterContent(String novelId, String chapterId) {
        log.info("获取番茄小说章节内容: novelId={}, chapterId={}", novelId, chapterId);
        
        return webClient.get()
                .uri("/api/novels/{novelId}/chapters/{chapterId}", novelId, chapterId)
                .retrieve()
                .bodyToMono(FanqieChapter.class)
                .doOnSuccess(chapter -> log.info("获取章节内容成功: {}", chapter.getTitle()));
    }
    
    @Override
    public Flux<DataBuffer> downloadNovelFile(String novelId) {
        log.info("下载番茄小说EPUB文件: {}", novelId);
        
        return webClient.get()
                .uri("/api/novels/{novelId}/download", novelId)
                .retrieve()
                .bodyToFlux(DataBuffer.class)
                .doOnComplete(() -> log.info("EPUB文件下载完成: {}", novelId));
    }
    
    @Override
    public Flux<DataBuffer> getNovelCover(String novelId) {
        log.info("获取番茄小说封面: {}", novelId);
        
        return webClient.get()
                .uri("/api/novels/{novelId}/cover", novelId)
                .retrieve()
                .bodyToFlux(DataBuffer.class)
                .doOnComplete(() -> log.info("封面图片获取完成: {}", novelId));
    }
}

