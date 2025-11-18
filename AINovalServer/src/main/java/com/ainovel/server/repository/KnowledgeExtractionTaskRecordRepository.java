package com.ainovel.server.repository;

import com.ainovel.server.domain.model.KnowledgeExtractionTaskRecord;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;

/**
 * AI拆书任务记录Repository
 */
@Repository
public interface KnowledgeExtractionTaskRecordRepository extends ReactiveMongoRepository<KnowledgeExtractionTaskRecord, String> {
    
    /**
     * 查询所有任务列表（管理员，分页）
     */
    Flux<KnowledgeExtractionTaskRecord> findAllByOrderByCreatedAtDesc(Pageable pageable);
    
    /**
     * 根据状态查询任务列表（管理员，分页）
     */
    Flux<KnowledgeExtractionTaskRecord> findByStatusOrderByCreatedAtDesc(
            KnowledgeExtractionTaskRecord.TaskStatus status,
            Pageable pageable);
    
    /**
     * 根据状态统计任务数量
     */
    Mono<Long> countByStatus(KnowledgeExtractionTaskRecord.TaskStatus status);
    
    /**
     * 根据用户ID查询任务列表（分页）
     */
    Flux<KnowledgeExtractionTaskRecord> findByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);
    
    /**
     * 根据用户ID统计任务数量
     */
    Mono<Long> countByUserId(String userId);
    
    /**
     * 根据用户ID和状态查询任务列表
     */
    Flux<KnowledgeExtractionTaskRecord> findByUserIdAndStatusOrderByCreatedAtDesc(
            String userId, 
            KnowledgeExtractionTaskRecord.TaskStatus status, 
            Pageable pageable);
    
    /**
     * 根据用户ID和状态统计任务数量
     */
    Mono<Long> countByUserIdAndStatus(String userId, KnowledgeExtractionTaskRecord.TaskStatus status);
    
    /**
     * 根据导入记录ID查询任务
     */
    Mono<KnowledgeExtractionTaskRecord> findByImportRecordId(String importRecordId);
    
    /**
     * 根据知识库ID查询任务
     */
    Mono<KnowledgeExtractionTaskRecord> findByKnowledgeBaseId(String knowledgeBaseId);
    
    /**
     * 查询指定时间范围内的任务
     */
    Flux<KnowledgeExtractionTaskRecord> findByCreatedAtBetween(
            LocalDateTime startTime, 
            LocalDateTime endTime);
    
    /**
     * 查询所有失败的任务（用于重试或分析）
     */
    Flux<KnowledgeExtractionTaskRecord> findByStatusAndRetryCountLessThanOrderByCreatedAtDesc(
            KnowledgeExtractionTaskRecord.TaskStatus status, 
            Integer maxRetryCount);
    
    /**
     * 查询用户的失败任务
     */
    Flux<KnowledgeExtractionTaskRecord> findByUserIdAndStatusAndRetryCountLessThan(
            String userId,
            KnowledgeExtractionTaskRecord.TaskStatus status,
            Integer maxRetryCount);
}

