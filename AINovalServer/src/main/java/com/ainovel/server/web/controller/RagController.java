package com.ainovel.server.web.controller;

import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.service.AIService;
import com.ainovel.server.service.IndexingService;
import com.ainovel.server.service.NovelRagAssistant;
import com.ainovel.server.web.base.ReactiveBaseController;
import com.ainovel.server.web.dto.NovelIdDto;
import com.ainovel.server.web.dto.RagQueryDto;
import com.ainovel.server.web.dto.RagQueryResultDto;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * RAG功能控制器 提供基于检索增强生成(RAG)的知识库查询和管理功能
 */
@Slf4j
@RestController
@RequestMapping("/api/rag")
@CrossOrigin(origins = "*", maxAge = 3600)
@RequiredArgsConstructor
public class RagController extends ReactiveBaseController {

    private final IndexingService indexingService;
    private final NovelRagAssistant novelRagAssistant;
    private final AIService aiService;

    /**
     * 处理RAG知识库查询
     *
     * @param queryDto 查询DTO
     * @return 查询结果
     */
    @PostMapping("/query")
    public Mono<RagQueryResultDto> queryKnowledgeBase(@RequestBody RagQueryDto queryDto) {
        log.info("收到RAG查询请求: {}", queryDto);
        
        // 获取RAG上下文
        return novelRagAssistant.queryWithRagContext(queryDto.getNovelId(), queryDto.getQuery())
                .flatMap(context -> {
                    // 创建AI请求
                    AIRequest request = new AIRequest();
                    request.setModel("gpt-3.5-turbo"); // 使用默认模型或从配置获取
                    request.setTemperature(0.3); // 设置较低的温度以获得更精确的回答
                    request.setMaxTokens(1000);
                    
                    // 创建系统消息
                    AIRequest.Message systemMessage = new AIRequest.Message();
                    systemMessage.setRole("system");
                    systemMessage.setContent("你是一个专业的小说顾问，基于提供的相关上下文和设定信息回答问题。只使用提供的信息回答，如果信息不足，坦率说明无法确定。");
                    
                    // 创建用户消息，包含上下文和查询
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(context + "\n\n## 问题\n\n" + queryDto.getQuery() + 
                                          "\n\n请根据提供的背景信息回答上述问题。如果背景信息中没有相关内容，请直接回答「我没有足够的信息来回答这个问题」。");
                    
                    request.getMessages().add(systemMessage);
                    request.getMessages().add(userMessage);
                    
                    // 调用AI服务
                    // 该直连接口已废弃，此处保持最小兼容：直接返回请求内容
                    return reactor.core.publisher.Mono.just(request)
                            .map(AIRequest::getPrompt)
                            .map(result -> new RagQueryResultDto(result, queryDto.getQuery()));
                })
                .doOnSuccess(response -> log.info("RAG查询完成: {}", queryDto.getQuery()));
    }

    /**
     * 重新索引小说知识库
     *
     * @param novelIdDto 小说ID DTO
     * @return 操作结果
     */
    @PostMapping("/reindex")
    public Mono<String> reindexNovel(@RequestBody NovelIdDto novelIdDto) {
        log.info("收到重新索引请求: {}", novelIdDto.getNovelId());
        return indexingService.indexNovel(novelIdDto.getNovelId())
                .thenReturn("小说重新索引成功: " + novelIdDto.getNovelId())
                .doOnSuccess(result -> log.info("小说重新索引完成: {}", novelIdDto.getNovelId()));
    }

    /**
     * 删除小说知识库索引
     *
     * @param novelIdDto 小说ID DTO
     * @return 操作结果
     */
    @PostMapping("/delete-indices")
    public Mono<String> deleteNovelIndices(@RequestBody NovelIdDto novelIdDto) {
        log.info("收到删除索引请求: {}", novelIdDto.getNovelId());
        return indexingService.deleteNovelIndices(novelIdDto.getNovelId())
                .thenReturn("小说索引删除成功: " + novelIdDto.getNovelId())
                .doOnSuccess(result -> log.info("小说索引删除完成: {}", novelIdDto.getNovelId()));
    }
}
