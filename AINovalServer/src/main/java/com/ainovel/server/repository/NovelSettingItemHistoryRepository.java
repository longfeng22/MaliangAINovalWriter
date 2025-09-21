package com.ainovel.server.repository;

import com.ainovel.server.domain.model.NovelSettingItemHistory;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 设定节点历史记录仓库接口
 */
@Repository
public interface NovelSettingItemHistoryRepository extends ReactiveMongoRepository<NovelSettingItemHistory, String> {

    /**
     * 根据设定条目ID查找历史记录（按创建时间倒序）
     */
    Flux<NovelSettingItemHistory> findBySettingItemIdOrderByCreatedAtDesc(String settingItemId);

    /**
     * 根据设定条目ID查找历史记录（支持分页）
     */
    Flux<NovelSettingItemHistory> findBySettingItemIdOrderByCreatedAtDesc(String settingItemId, Pageable pageable);

    /**
     * 根据历史记录ID查找所有节点历史
     */
    Flux<NovelSettingItemHistory> findByHistoryIdOrderByCreatedAtDesc(String historyId);

    /**
     * 根据设定条目ID和版本号查找特定版本
     */
    Mono<NovelSettingItemHistory> findBySettingItemIdAndVersion(String settingItemId, Integer version);

    /**
     * 获取设定条目的最新版本记录（按版本倒序的第一条）
     * 使用派生查询以自动添加 limit(1)，避免非唯一结果错误
     */
    Mono<NovelSettingItemHistory> findTopBySettingItemIdOrderByVersionDesc(String settingItemId);

    /**
     * 统计设定条目的历史记录数量
     */
    @Query(value = "{ 'settingItemId': ?0 }", count = true)
    Mono<Long> countBySettingItemId(String settingItemId);

    /**
     * 删除设定条目的所有历史记录
     */
    Mono<Void> deleteBySettingItemId(String settingItemId);

    /**
     * 删除历史记录的所有节点历史
     */
    Mono<Void> deleteByHistoryId(String historyId);
} 