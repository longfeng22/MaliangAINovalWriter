package com.ainovel.server.service;

import com.ainovel.server.domain.model.FanqieNovelImportRecord;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 番茄小说导入记录服务接口
 */
public interface FanqieNovelImportRecordService {
    
    /**
     * 创建导入记录
     * 
     * @param record 导入记录
     * @return 保存后的记录
     */
    Mono<FanqieNovelImportRecord> create(FanqieNovelImportRecord record);
    
    /**
     * 更新导入记录
     * 
     * @param record 导入记录
     * @return 更新后的记录
     */
    Mono<FanqieNovelImportRecord> update(FanqieNovelImportRecord record);
    
    /**
     * 根据ID查询
     * 
     * @param recordId 记录ID
     * @return 导入记录
     */
    Mono<FanqieNovelImportRecord> getById(String recordId);
    
    /**
     * 根据任务ID查询
     * 
     * @param taskId 任务ID
     * @return 导入记录
     */
    Mono<FanqieNovelImportRecord> getByTaskId(String taskId);
    
    /**
     * 查询用户的导入历史
     * 
     * @param userId 用户ID
     * @param page 页码
     * @param size 每页大小
     * @return 导入记录列表
     */
    Flux<FanqieNovelImportRecord> getUserImportHistory(String userId, int page, int size);
    
    /**
     * 添加LLM请求记录
     * 
     * @param recordId 导入记录ID
     * @param llmRequest LLM请求记录
     * @return 更新后的记录
     */
    Mono<FanqieNovelImportRecord> addLLMRequest(
            String recordId, 
            FanqieNovelImportRecord.LLMRequestRecord llmRequest
    );
}


