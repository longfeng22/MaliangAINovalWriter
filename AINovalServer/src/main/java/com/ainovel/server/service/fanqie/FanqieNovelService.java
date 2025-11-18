package com.ainovel.server.service.fanqie;

import com.ainovel.server.service.fanqie.dto.*;
import org.springframework.core.io.buffer.DataBuffer;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 番茄小说下载服务接口
 * 提供与番茄小说下载服务的集成功能
 */
public interface FanqieNovelService {
    
    /**
     * 用户登录，获取访问令牌
     * 
     * @param username 用户名
     * @param password 密码
     * @return 访问令牌
     */
    Mono<String> login(String username, String password);
    
    /**
     * 搜索小说
     * 
     * @param query 搜索关键词
     * @return 搜索结果列表
     */
    Mono<FanqieSearchResult> searchNovels(String query);
    
    /**
     * 获取小说列表（支持筛选、搜索和排序）
     * 
     * @param request 查询参数
     * @return 小说列表响应
     */
    Mono<FanqieNovelListResponse> getNovelList(FanqieNovelListRequest request);
    
    /**
     * 获取小说详情
     * 
     * @param novelId 小说ID
     * @return 小说详细信息
     */
    Mono<FanqieNovelDetail> getNovelDetail(String novelId);
    
    /**
     * 添加小说并开始下载
     * 
     * @param novelId 小说ID
     * @param maxChapters 最大章节数（可选）
     * @return 下载任务信息
     */
    Mono<FanqieDownloadTask> addNovelDownloadTask(String novelId, Integer maxChapters);
    
    /**
     * 获取下载任务列表
     * 
     * @return 任务列表
     */
    Mono<FanqieTaskList> getDownloadTasks();
    
    /**
     * 获取任务状态（通过Celery Task ID）
     * 
     * @param celeryTaskId Celery任务ID
     * @return 任务状态信息
     */
    Mono<FanqieDownloadTask> getTaskStatus(String celeryTaskId);
    
    /**
     * 终止下载任务
     * 
     * @param taskId 任务ID
     * @return 终止结果
     */
    Mono<FanqieDownloadTask> terminateTask(Long taskId);
    
    /**
     * 删除任务记录
     * 
     * @param taskId 任务ID
     * @return 删除结果消息
     */
    Mono<String> deleteTask(Long taskId);
    
    /**
     * 重新下载任务
     * 
     * @param taskId 任务ID
     * @return 新的下载任务信息
     */
    Mono<FanqieDownloadTask> redownloadTask(Long taskId);
    
    /**
     * 获取小说章节列表
     * 
     * @param novelId 小说ID
     * @param page 页码
     * @param perPage 每页数量
     * @param order 排序方式（asc/desc）
     * @return 章节列表
     */
    Mono<FanqieChapterList> getChapterList(String novelId, Integer page, Integer perPage, String order);
    
    /**
     * 获取章节内容
     * 
     * @param novelId 小说ID
     * @param chapterId 章节ID
     * @return 章节详细信息
     */
    Mono<FanqieChapter> getChapterContent(String novelId, String chapterId);
    
    /**
     * 下载小说文件（EPUB）
     * 
     * @param novelId 小说ID
     * @return EPUB文件数据流
     */
    Flux<DataBuffer> downloadNovelFile(String novelId);
    
    /**
     * 获取小说封面图片
     * 
     * @param novelId 小说ID
     * @return 封面图片数据流
     */
    Flux<DataBuffer> getNovelCover(String novelId);
}



