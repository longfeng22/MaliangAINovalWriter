package com.ainovel.server.repository;

import com.ainovel.server.domain.model.UserKnowledgeBaseRelation;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 用户知识库关系Repository
 */
@Repository
public interface UserKnowledgeBaseRelationRepository extends ReactiveMongoRepository<UserKnowledgeBaseRelation, String> {
    
    /**
     * 查询用户的所有知识库关系
     */
    Flux<UserKnowledgeBaseRelation> findByUserId(String userId, Pageable pageable);
    
    /**
     * 统计用户的知识库数量
     */
    Mono<Long> countByUserId(String userId);
    
    /**
     * 查询用户与知识库的关系
     */
    Mono<UserKnowledgeBaseRelation> findByUserIdAndKnowledgeBaseId(String userId, String knowledgeBaseId);
    
    /**
     * 删除用户与知识库的关系
     */
    Mono<Void> deleteByUserIdAndKnowledgeBaseId(String userId, String knowledgeBaseId);
    
    /**
     * 检查用户是否拥有该知识库
     */
    Mono<Boolean> existsByUserIdAndKnowledgeBaseId(String userId, String knowledgeBaseId);
    
    /**
     * 统计知识库的用户数量
     */
    Mono<Long> countByKnowledgeBaseId(String knowledgeBaseId);
}


