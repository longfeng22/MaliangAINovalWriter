package com.ainovel.server.repository;

import com.ainovel.server.domain.model.billing.PreDeductionRecord;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

/**
 * 预扣费记录仓储接口
 */
@Repository
public interface PreDeductionRecordRepository extends ReactiveMongoRepository<PreDeductionRecord, String> {
    
    /**
     * 根据traceId查找预扣费记录
     */
    Mono<PreDeductionRecord> findByTraceId(String traceId);
    
    /**
     * 根据traceId删除预扣费记录
     */
    Mono<Void> deleteByTraceId(String traceId);
    
    /**
     * 检查traceId是否存在
     */
    Mono<Boolean> existsByTraceId(String traceId);
}
