package com.ainovel.server.service;

import com.ainovel.server.web.dto.request.FanqieKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.request.TextKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.response.KnowledgeExtractionTaskResponse;
import reactor.core.publisher.Mono;

/**
 * 知识库拆书服务接口
 */
public interface KnowledgeExtractionService {
    
    /**
     * 从番茄小说提取知识库
     * 
     * @param request 提取请求
     * @param userId 用户ID
     * @return 任务响应
     */
    Mono<KnowledgeExtractionTaskResponse> extractFromFanqieNovel(
            FanqieKnowledgeExtractionRequest request, 
            String userId
    );
    
    /**
     * 从用户导入文本提取知识库
     * 
     * @param request 提取请求
     * @param userId 用户ID
     * @return 任务响应
     */
    Mono<KnowledgeExtractionTaskResponse> extractFromUserText(
            TextKnowledgeExtractionRequest request,
            String userId
    );
    
    /**
     * 获取拆书任务状态
     * 
     * @param taskId 任务ID
     * @return 任务响应
     */
    Mono<KnowledgeExtractionTaskResponse> getExtractionTaskStatus(String taskId);
}


