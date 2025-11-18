package com.ainovel.server.service.impl;

import com.ainovel.server.domain.model.FanqieNovelImportRecord;
import com.ainovel.server.repository.FanqieNovelImportRecordRepository;
import com.ainovel.server.service.FanqieNovelImportRecordService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;

/**
 * 番茄小说导入记录服务实现
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FanqieNovelImportRecordServiceImpl implements FanqieNovelImportRecordService {
    
    private final FanqieNovelImportRecordRepository repository;
    
    @Override
    public Mono<FanqieNovelImportRecord> create(FanqieNovelImportRecord record) {
        log.info("创建导入记录: fanqieNovelId={}, userId={}", 
                record.getFanqieNovelId(), record.getUserId());
        record.setStartTime(LocalDateTime.now());
        return repository.save(record);
    }
    
    @Override
    public Mono<FanqieNovelImportRecord> update(FanqieNovelImportRecord record) {
        log.info("更新导入记录: id={}", record.getId());
        return repository.save(record);
    }
    
    @Override
    public Mono<FanqieNovelImportRecord> getById(String recordId) {
        return repository.findById(recordId);
    }
    
    @Override
    public Mono<FanqieNovelImportRecord> getByTaskId(String taskId) {
        return repository.findAll()
                .filter(record -> taskId.equals(record.getTaskId()))
                .next();
    }
    
    @Override
    public Flux<FanqieNovelImportRecord> getUserImportHistory(String userId, int page, int size) {
        return repository.findAll()
                .filter(record -> userId.equals(record.getUserId()))
                .sort((r1, r2) -> r2.getStartTime().compareTo(r1.getStartTime()))
                .skip((long) page * size)
                .take(size);
    }
    
    @Override
    public Mono<FanqieNovelImportRecord> addLLMRequest(
            String recordId, 
            FanqieNovelImportRecord.LLMRequestRecord llmRequest) {
        
        return repository.findById(recordId)
                .flatMap(record -> {
                    record.getLlmRequests().add(llmRequest);
                    record.setTotalTokensUsed(record.getTotalTokensUsed() + llmRequest.getTokensUsed());
                    return repository.save(record);
                });
    }
}

