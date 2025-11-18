package com.ainovel.server.service;

import org.springframework.http.codec.ServerSentEvent;
import org.springframework.http.codec.multipart.FilePart;

import com.ainovel.server.web.dto.ImportStatus;
import com.ainovel.server.web.dto.ImportPreviewRequest;
import com.ainovel.server.web.dto.ImportPreviewResponse;
import com.ainovel.server.web.dto.ImportConfirmRequest;
import com.ainovel.server.web.dto.ChapterDetailDto;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;

/**
 * 小说导入服务接口 负责处理小说文件导入、解析和存储，以及通过SSE推送状态更新
 */
public interface ImportService {

    /**
     * 开始导入流程（原有的简单导入方法，保持向后兼容）
     *
     * @param filePart 上传的文件部分
     * @param userId 用户ID
     * @return 导入任务ID
     */
    Mono<String> startImport(FilePart filePart, String userId);

    /**
     * 上传文件并获取预览会话ID
     * 第一步：用户上传文件，系统返回临时会话ID
     *
     * @param filePart 上传的文件部分
     * @param userId 用户ID
     * @return 预览会话ID
     */
    Mono<String> uploadFileForPreview(FilePart filePart, String userId);

    /**
     * 获取导入预览
     * 第二步：根据用户配置解析文件并返回预览信息
     *
     * @param request 预览请求配置
     * @return 预览响应信息
     */
    Mono<ImportPreviewResponse> getImportPreview(ImportPreviewRequest request);

    /**
     * 确认并开始导入
     * 第三步：用户确认后开始正式导入流程
     *
     * @param request 确认导入请求
     * @return 导入任务ID
     */
    Mono<String> confirmAndStartImport(ImportConfirmRequest request);

    /**
     * 获取导入任务的状态流
     *
     * @param jobId 任务ID
     * @return 包含导入状态的SSE事件流
     */
    Flux<ServerSentEvent<ImportStatus>> getImportStatusStream(String jobId);

    /**
     * 取消导入任务
     *
     * @param jobId 任务ID
     * @return 是否成功取消 true:成功 false:失败或任务不存在
     */
    Mono<Boolean> cancelImport(String jobId);

    /**
     * 清理预览会话
     * 清理临时文件和会话数据
     *
     * @param previewSessionId 预览会话ID
     * @return 清理操作的Mono
     */
    Mono<Void> cleanupPreviewSession(String previewSessionId);
    
    /**
     * 从预览会话获取完整文本内容
     * 用于知识库拆书功能
     *
     * @param previewSessionId 预览会话ID
     * @param chapterLimit 章节限制（null表示整本，否则为前N章）
     * @return 完整的小说文本内容（包含标题和所有章节）
     */
    Mono<String> getFullContentFromPreviewSession(String previewSessionId, Integer chapterLimit);
    
    /**
     * 从预览会话获取总章节数
     *
     * @param previewSessionId 预览会话ID
     * @return 总章节数
     */
    Mono<Integer> getTotalChapterCountFromPreviewSession(String previewSessionId);
    
    /**
     * 从预览会话获取章节详情列表
     * 用于知识库拆书功能，获取每个章节的完整信息
     *
     * @param previewSessionId 预览会话ID
     * @param chapterLimit 章节限制（null表示整本，否则为前N章）
     * @return 章节详情列表
     */
    Mono<List<ChapterDetailDto>> getChapterDetailsFromPreviewSession(
            String previewSessionId, Integer chapterLimit);
}
