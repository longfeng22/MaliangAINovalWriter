package com.ainovel.server.repository;

import com.ainovel.server.domain.model.NovelKnowledgeBase;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;

/**
 * 小说知识库Repository
 */
@Repository
public interface NovelKnowledgeBaseRepository extends ReactiveMongoRepository<NovelKnowledgeBase, String> {
    
    /**
     * 根据番茄小说ID查询
     */
    Mono<NovelKnowledgeBase> findByFanqieNovelId(String fanqieNovelId);
    
    /**
     * 查询公共知识库
     */
    Flux<NovelKnowledgeBase> findByIsPublicTrueAndStatus(
            NovelKnowledgeBase.CacheStatus status, 
            Pageable pageable
    );
    
    /**
     * 查询用户的知识库
     */
    Flux<NovelKnowledgeBase> findByFirstImportUserId(String userId, Pageable pageable);
    
    /**
     * 根据标签查询公共知识库
     */
    Flux<NovelKnowledgeBase> findByIsPublicTrueAndStatusAndTagsIn(
            NovelKnowledgeBase.CacheStatus status,
            List<String> tags,
            Pageable pageable
    );
    
    /**
     * 统计公共知识库数量
     */
    Mono<Long> countByIsPublicTrueAndStatus(NovelKnowledgeBase.CacheStatus status);
    
    /**
     * 统计用户知识库数量
     */
    Mono<Long> countByFirstImportUserId(String userId);
}


