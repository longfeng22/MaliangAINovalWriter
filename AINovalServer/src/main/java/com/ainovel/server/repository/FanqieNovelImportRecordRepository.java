package com.ainovel.server.repository;

import com.ainovel.server.domain.model.FanqieNovelImportRecord;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 番茄小说导入记录Repository
 */
@Repository
public interface FanqieNovelImportRecordRepository extends ReactiveMongoRepository<FanqieNovelImportRecord, String> {
    
    /**
     * 根据任务ID查询
     */
    Mono<FanqieNovelImportRecord> findByTaskId(String taskId);
    
    /**
     * 根据番茄小说ID和用户ID查询
     */
    Flux<FanqieNovelImportRecord> findByFanqieNovelIdAndUserId(String fanqieNovelId, String userId);
    
    /**
     * 查询用户的导入历史
     */
    Flux<FanqieNovelImportRecord> findByUserIdOrderByStartTimeDesc(String userId, Pageable pageable);
    
    /**
     * 根据知识库ID查询
     */
    Mono<FanqieNovelImportRecord> findByKnowledgeBaseId(String knowledgeBaseId);
}


