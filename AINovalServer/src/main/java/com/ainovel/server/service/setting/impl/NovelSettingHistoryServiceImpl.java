package com.ainovel.server.service.setting.impl;

import com.ainovel.server.domain.model.NovelSettingGenerationHistory;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.domain.model.NovelSettingItemHistory;
import com.ainovel.server.domain.model.setting.generation.SettingGenerationSession;
import com.ainovel.server.domain.model.setting.generation.SettingNode;

import com.ainovel.server.repository.NovelSettingGenerationHistoryRepository;
import com.ainovel.server.repository.NovelSettingItemHistoryRepository;
import com.ainovel.server.service.NovelSettingService;
import com.ainovel.server.service.setting.NovelSettingHistoryService;

import com.ainovel.server.service.setting.SettingConversionService;
import com.ainovel.server.service.setting.generation.InMemorySessionManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 设定历史记录服务实现类
 * 
 * 核心业务说明：
 * 1. 历史记录管理模式：
 *    - 历史记录是按用户维度管理的，不依赖于特定小说
 *    - 每个历史记录包含一个小说设定的完整快照
 *    - 支持跨小说查看和管理用户的所有历史记录
 * 
 * 2. 历史记录创建方式：
 *    a) 自动快照创建：
 *       - 用户进入小说设定生成页面时，如果没有历史记录，自动创建当前设定快照
 *       - 用户生成新设定完成后，自动创建历史记录保存生成结果
 *    b) 手动快照创建：
 *       - 用户可以主动为当前小说设定创建快照（通过复制等操作）
 * 
 * 3. 历史记录操作：
 *    - 查看：支持分页查看用户的所有历史记录，可按小说过滤
 *    - 编辑：基于历史记录创建新的编辑会话
 *    - 复制：创建现有历史记录的副本
 *    - 恢复：将历史记录中的设定恢复到小说中（支持跨小说恢复）
 *    - 删除：删除不需要的历史记录（支持批量删除）
 * 
 * 4. 版本管理：
 *    - 每个设定条目的变更都会记录在 NovelSettingItemHistory 中
 *    - 支持查看单个设定节点的完整变更历史
 *    - 提供版本号管理和变更追踪
 * 
 * 5. 数据一致性：
 *    - 历史记录引用实际的 NovelSettingItem 记录
 *    - 通过父子关系映射维护设定的树形结构
 *    - 删除历史记录时会清理相关的节点历史记录
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class NovelSettingHistoryServiceImpl implements NovelSettingHistoryService {

    private final NovelSettingGenerationHistoryRepository historyRepository;
    private final NovelSettingItemHistoryRepository itemHistoryRepository;
    private final SettingConversionService conversionService;
    private final InMemorySessionManager sessionManager;
    private final NovelSettingService novelSettingService;

    /**
     * 从完成的设定生成会话创建历史记录
     * 
     * 业务流程：
     * 1. 收集会话中生成的所有设定条目
     * 2. 构建父子关系映射和根节点列表  
     * 3. 创建历史记录主体信息
     * 4. 为每个设定条目创建节点变更历史
     * 5. 保存完整的历史记录到数据库
     * 
     * @param session 完成的设定生成会话
     * @param settingItemIds 生成的设定条目ID列表
     * @return 创建的历史记录
     */
    @Override
    public Mono<NovelSettingGenerationHistory> createHistoryFromSession(SettingGenerationSession session, 
                                                                       List<String> settingItemIds) {
        log.info("开始为会话 {} 创建历史记录", session.getSessionId());

        // 获取设定条目用于构建父子关系映射
        return Flux.fromIterable(settingItemIds)
                .flatMap(novelSettingService::getSettingItemById)
                .collectList()
                .flatMap(settingItems -> {
                    // 🔧 关键修复：使用 sessionId 作为 historyId，确保后端重启后能找到历史记录
                    // 这样前端持有的 sessionId 就能直接用于查询历史记录和修改节点
                    String historyId = session.getSessionId();
                    log.info("使用 sessionId 作为 historyId: {}", historyId);
                    
                    // 构建历史记录对象
                    NovelSettingGenerationHistory history = NovelSettingGenerationHistory.builder()
                            .historyId(historyId)  // 使用 sessionId 而不是生成新UUID
                            .userId(session.getUserId())
                            .novelId(session.getNovelId())
                            .title(generateHistoryTitle(session.getInitialPrompt(), session.getStrategy(), settingItemIds.size()))
                            .description("基于提示词：" + session.getInitialPrompt())
                            .initialPrompt(session.getInitialPrompt())
                            .strategy(session.getStrategy())
                            .promptTemplateId(session.getPromptTemplateId())
                            .modelConfigId((String) session.getMetadata().get("modelConfigId"))
                            .originalSessionId(session.getSessionId())
                            .status(session.getStatus())
                            .generatedSettingIds(settingItemIds)
                            .rootSettingIds(conversionService.getRootNodeIds(settingItems))
                            .parentChildMap(conversionService.buildParentChildMap(settingItems))
                            .settingsCount(settingItemIds.size())
                            .generationResult(determineGenerationResult(session))
                            .errorMessage(session.getErrorMessage())
                            .generationDuration(calculateGenerationDuration(session))
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .metadata(new HashMap<>(session.getMetadata()))
                            .build();

                    return historyRepository.save(history)
                            .flatMap(savedHistory -> {
                                // 为每个设定条目创建节点历史记录
                                return createNodeHistoriesForGeneration(savedHistory, settingItems)
                                        .then(Mono.just(savedHistory));
                            });
                })
                .doOnSuccess(savedHistory -> log.info("成功创建历史记录 {}", savedHistory.getHistoryId()))
                .doOnError(error -> log.error("创建历史记录失败: {}", error.getMessage(), error));
    }

    @Override
    public Mono<NovelSettingGenerationHistory> updateHistoryFromSession(SettingGenerationSession session, 
                                                                        List<String> settingItemIds,
                                                                        String targetHistoryId) {
        log.info("开始更新历史记录 {} 基于会话 {}", targetHistoryId, session.getSessionId());

        // 1. 先获取现有的历史记录
        return historyRepository.findById(targetHistoryId)
                .switchIfEmpty(Mono.error(new RuntimeException("目标历史记录不存在: " + targetHistoryId)))
                .flatMap(existingHistory -> {
                    // 2. 获取设定条目用于构建父子关系映射
                    return Flux.fromIterable(settingItemIds)
                            .flatMap(novelSettingService::getSettingItemById)
                            .collectList()
                            .flatMap(settingItems -> {
                                // 3. 更新历史记录对象（保留原有的historyId、createdAt等）
                                NovelSettingGenerationHistory updatedHistory = NovelSettingGenerationHistory.builder()
                                        .historyId(existingHistory.getHistoryId()) // 保留原有ID
                                        .userId(existingHistory.getUserId()) // 保留原有用户ID
                                        .novelId(existingHistory.getNovelId()) // 保留原有小说ID  
                                        .title(generateHistoryTitle(session.getInitialPrompt(), session.getStrategy(), settingItemIds.size()))
                                        .description("更新基于提示词：" + session.getInitialPrompt())
                                        .initialPrompt(session.getInitialPrompt())
                                        .strategy(session.getStrategy())
                                        .promptTemplateId(session.getPromptTemplateId())
                                        .modelConfigId((String) session.getMetadata().get("modelConfigId"))
                                        .originalSessionId(session.getSessionId())
                                        .status(session.getStatus())
                                        .generatedSettingIds(settingItemIds)
                                        .rootSettingIds(conversionService.getRootNodeIds(settingItems))
                                        .parentChildMap(conversionService.buildParentChildMap(settingItems))
                                        .settingsCount(settingItemIds.size())
                                        .generationResult(determineGenerationResult(session))
                                        .errorMessage(session.getErrorMessage())
                                        .generationDuration(calculateGenerationDuration(session))
                                        .createdAt(existingHistory.getCreatedAt()) // 保留原有创建时间
                                        .updatedAt(LocalDateTime.now()) // 只更新updatedAt
                                        .metadata(new HashMap<>(session.getMetadata()))
                                        .build();

                                return historyRepository.save(updatedHistory)
                                        .flatMap(savedHistory -> {
                                            // 4. 为设定条目创建更新历史记录，保留原有的历史记录
                                            return createNodeHistoriesForUpdate(savedHistory, settingItems)
                                                    .then(Mono.just(savedHistory));
                                        });
                            });
                })
                .doOnSuccess(updatedHistory -> log.info("成功更新历史记录 {}", updatedHistory.getHistoryId()))
                .doOnError(error -> log.error("更新历史记录失败: {}", error.getMessage(), error));
    }

    @Override
    public Flux<NovelSettingGenerationHistory> getNovelHistories(String novelId, String userId, Pageable pageable) {
        log.info("获取小说 {} 用户 {} 的历史记录", novelId, userId);
        
        if (pageable != null) {
            return historyRepository.findByNovelIdAndUserIdOrderByCreatedAtDesc(novelId, userId, pageable);
        } else {
            return historyRepository.findByNovelIdAndUserIdOrderByCreatedAtDesc(novelId, userId);
        }
    }

    @Override
    public Mono<NovelSettingGenerationHistory> getHistoryById(String historyId) {
        log.info("获取历史记录详情: {}", historyId);
        return historyRepository.findById(historyId)
                .switchIfEmpty(Mono.error(new RuntimeException("历史记录不存在: " + historyId)));
    }

    @Override
    public Mono<HistoryWithSettings> getHistoryWithSettings(String historyId) {
        log.info("获取历史记录和完整设定数据: {}", historyId);
        
        return getHistoryById(historyId)
                .flatMap(history -> {
                    // 获取历史记录关联的设定条目
                    return Flux.fromIterable(history.getGeneratedSettingIds())
                            .flatMap(novelSettingService::getSettingItemById)
                            .collectList()
                            .map(settings -> {
                                // 🔧 修复：构建完整的 SettingNode 树形结构
                                List<SettingNode> rootNodes = buildSettingNodeTree(history, settings);
                                return new HistoryWithSettings(history, rootNodes);
                            });
                });
    }

    @Override
    public Mono<Void> deleteHistory(String historyId, String userId) {
        log.info("删除历史记录: {} by user: {}", historyId, userId);
        
        return historyRepository.findById(historyId)
                .switchIfEmpty(Mono.error(new RuntimeException("历史记录不存在: " + historyId)))
                .flatMap(history -> {
                    if (!history.getUserId().equals(userId)) {
                        return Mono.error(new RuntimeException("无权限删除此历史记录"));
                    }
                    
                    // 删除关联的节点历史记录
                    return itemHistoryRepository.deleteByHistoryId(historyId)
                            .then(historyRepository.deleteById(historyId));
                });
    }

    @Override
    public Mono<SettingGenerationSession> createSessionFromHistory(String historyId, String newPrompt) {
        log.info("从历史记录 {} 创建新的编辑会话", historyId);
        
        return getHistoryWithSettings(historyId)
                .flatMap(historyWithSettings -> {
                    NovelSettingGenerationHistory history = historyWithSettings.history();
                    List<SettingNode> rootNodes = historyWithSettings.rootNodes();
                    
                    // 直接使用 SettingNode 树
                    List<SettingNode> nodes = flattenSettingNodeTree(rootNodes);
                    
                    // 创建新的会话
                    String prompt = newPrompt != null ? newPrompt : "编辑历史记录: " + history.getTitle();
                    return sessionManager.createSession(
                            history.getUserId(), 
                            null, // 切换历史时不继承历史记录中的 novelId
                            prompt, 
                            history.getStrategy()
                    ).flatMap(session -> {
                        // 将节点添加到会话中
                        nodes.forEach(node -> session.addNode(node));
                        
                        // 标记会话状态为编辑模式
                        session.setStatus(SettingGenerationSession.SessionStatus.GENERATING);
                        session.getMetadata().put("sourceHistoryId", historyId);
                        session.getMetadata().put("modelConfigId", history.getModelConfigId());
                        session.getMetadata().put("editMode", true);
                        // 再次确保 novelId 被置空
                        session.setNovelId(null);
                        
                        return sessionManager.saveSession(session);
                    });
                });
    }

    @Override
    public Mono<NovelSettingGenerationHistory> copyHistory(String sourceHistoryId, String copyReason, String userId) {
        log.info("复制历史记录: {} for user: {}", sourceHistoryId, userId);
        
        return getHistoryById(sourceHistoryId)
                .flatMap(sourceHistory -> {
                    if (!sourceHistory.getUserId().equals(userId)) {
                        return Mono.error(new RuntimeException("无权限复制此历史记录"));
                    }
                    
                    // 创建新的历史记录
                    NovelSettingGenerationHistory newHistory = NovelSettingGenerationHistory.builder()
                            .historyId(UUID.randomUUID().toString())
                            .userId(userId)
                            .novelId(sourceHistory.getNovelId())
                            .title(sourceHistory.getTitle() + " (副本)")
                            .description("复制自: " + sourceHistory.getTitle())
                            .initialPrompt(sourceHistory.getInitialPrompt())
                            .strategy(sourceHistory.getStrategy())
                            .modelConfigId(sourceHistory.getModelConfigId())
                            .originalSessionId(null) // 复制的历史记录没有原始会话ID
                            .status(sourceHistory.getStatus())
                            .generatedSettingIds(new ArrayList<>(sourceHistory.getGeneratedSettingIds())) // 引用相同的设定ID
                            .rootSettingIds(new ArrayList<>(sourceHistory.getRootSettingIds()))
                            .parentChildMap(new HashMap<>(sourceHistory.getParentChildMap()))
                            .settingsCount(sourceHistory.getSettingsCount())
                            .generationResult(sourceHistory.getGenerationResult())
                            .errorMessage(sourceHistory.getErrorMessage())
                            .generationDuration(sourceHistory.getGenerationDuration())
                            .sourceHistoryId(sourceHistoryId)
                            .copyReason(copyReason)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .metadata(new HashMap<>(sourceHistory.getMetadata()))
                            .build();
                    
                    return historyRepository.save(newHistory);
                });
    }

    @Override
    public Mono<List<String>> restoreHistoryToNovel(String historyId, String userId) {
        log.info("恢复历史记录 {} 到小说设定中 by user: {}", historyId, userId);
        
        return getHistoryWithSettings(historyId)
                .flatMap(historyWithSettings -> {
                    NovelSettingGenerationHistory history = historyWithSettings.history();
                    List<SettingNode> rootNodes = historyWithSettings.rootNodes();
                    
                    if (!history.getUserId().equals(userId)) {
                        return Mono.error(new RuntimeException("无权限恢复此历史记录"));
                    }
                    
                    // 将 SettingNode 树转换为 NovelSettingItem 列表
                    List<SettingNode> flatNodes = flattenSettingNodeTree(rootNodes);
                    List<NovelSettingItem> settings = flatNodes.stream()
                        .map(node -> conversionService.convertNodeToSettingItem(node, history.getNovelId(), userId))
                        .collect(Collectors.toList());
                    
                    // 保存所有设定条目到数据库（创建新的副本）
                    List<Mono<NovelSettingItem>> saveOperations = settings.stream()
                            .map(item -> {
                                // 重新生成ID和时间戳以避免冲突
                                item.setId(UUID.randomUUID().toString());
                                item.setCreatedAt(LocalDateTime.now());
                                item.setUpdatedAt(LocalDateTime.now());
                                return novelSettingService.createSettingItem(item);
                            })
                            .collect(Collectors.toList());
                    
                    return Flux.fromIterable(saveOperations)
                            .flatMap(mono -> mono)
                            .map(NovelSettingItem::getId)
                            .collectList();
                });
    }

    @Override
    public Mono<NovelSettingItemHistory> recordNodeChange(String settingItemId, String historyId, 
                                                        String operationType, NovelSettingItem beforeContent, 
                                                        NovelSettingItem afterContent, String changeDescription, 
                                                        String userId) {
        //log.debug("记录节点变更: settingItemId={}, operationType={}", settingItemId, operationType);
        
        return getNextVersionNumber(settingItemId)
                .flatMap(version -> {
                    NovelSettingItemHistory itemHistory = NovelSettingItemHistory.builder()
                            .id(UUID.randomUUID().toString())
                            .settingItemId(settingItemId)
                            .historyId(historyId)
                            .userId(userId)
                            .operationType(operationType)
                            .version(version)
                            .beforeContent(beforeContent)
                            .afterContent(afterContent)
                            .changeDescription(changeDescription)
                            .operationSource("AI_GENERATION") // 默认为AI生成
                            .createdAt(LocalDateTime.now())
                            .build();
                    
                    return itemHistoryRepository.save(itemHistory);
                });
    }

    @Override
    public Flux<NovelSettingItemHistory> getNodeHistories(String settingItemId, Pageable pageable) {
        log.debug("获取节点历史记录: {}", settingItemId);
        return itemHistoryRepository.findBySettingItemIdOrderByCreatedAtDesc(settingItemId, pageable);
    }

    @Override
    public Flux<NovelSettingItemHistory> getHistoryNodeChanges(String historyId) {
        log.debug("获取历史记录的所有节点变更: {}", historyId);
        return itemHistoryRepository.findByHistoryIdOrderByCreatedAtDesc(historyId);
    }


    /**
     * 从会话ID创建历史记录
     * 
     * 使用场景：在设定生成完成后，需要为生成结果创建历史记录快照
     * 
     * 业务流程：
     * 1. 验证会话是否存在及用户权限
     * 2. 将会话中的设定节点转换为数据库设定条目
     * 3. 保存所有设定条目到数据库
     * 4. 基于保存的设定条目创建历史记录
     * 
     * @param sessionId 会话ID
     * @param userId 用户ID（权限验证）
     * @param reason 创建原因说明
     * @return 创建的历史记录
     */
    @Override
    public Mono<NovelSettingGenerationHistory> createHistoryFromSession(String sessionId, String userId, String reason) {
        log.info("从会话ID {} 创建历史记录 by user: {}", sessionId, userId);
        
        return sessionManager.getSession(sessionId)
            .switchIfEmpty(Mono.error(new RuntimeException("会话不存在: " + sessionId)))
            .flatMap(session -> {
                if (!session.getUserId().equals(userId)) {
                    return Mono.error(new RuntimeException("无权限访问此会话"));
                }
                
                // 将会话的节点转换为设定条目
                List<NovelSettingItem> settingItems = conversionService.convertSessionToSettingItems(session, session.getNovelId());
                
                // 保存设定条目到数据库
                List<Mono<NovelSettingItem>> saveOperations = settingItems.stream()
                    .map(item -> novelSettingService.createSettingItem(item))
                    .collect(Collectors.toList());
                
                return Flux.fromIterable(saveOperations)
                    .flatMap(mono -> mono)
                    .collectList()
                    .flatMap(savedItems -> {
                        List<String> settingItemIds = savedItems.stream()
                            .map(NovelSettingItem::getId)
                            .collect(Collectors.toList());
                        
                        return createHistoryFromSession(session, settingItemIds);
                    });
            });
    }

    /**
     * 获取用户的历史记录列表（支持小说过滤）
     * 
     * 核心特性：
     * - 用户维度管理：按用户ID查询，不限定特定小说
     * - 可选过滤：可以通过 novelId 参数过滤特定小说的历史记录
     * - 分页支持：支持分页查询，提高大数据量场景下的性能
     * - 时间排序：始终按创建时间倒序返回，最新的记录在前
     * 
     * 使用场景：
     * 1. 用户查看自己的所有历史记录（novelId = null）
     * 2. 用户查看特定小说的历史记录（novelId 有值）
     * 3. 前端历史记录列表页面的数据源
     * 
     * @param userId 用户ID
     * @param novelId 小说ID过滤（可选，为null或空字符串表示不过滤）
     * @param pageable 分页参数（可选，为null表示不分页）
     * @return 历史记录流
     */
    @Override
    public Flux<NovelSettingGenerationHistory> getUserHistories(String userId, String novelId, Pageable pageable) {
        log.info("获取用户 {} 的历史记录，小说过滤: {}", userId, novelId);
        
        if (novelId != null && !novelId.trim().isEmpty()) {
            // 有小说ID过滤
            if (pageable != null) {
                return historyRepository.findByUserIdAndNovelIdOrderByCreatedAtDesc(userId, novelId, pageable);
            } else {
                return historyRepository.findByUserIdAndNovelIdOrderByCreatedAtDesc(userId, novelId);
            }
        } else {
            // 获取用户所有的历史记录
            if (pageable != null) {
                return historyRepository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
            } else {
                return historyRepository.findByUserIdOrderByCreatedAtDesc(userId);
            }
        }
    }

    /**
     * 将历史记录恢复到指定小说中（支持跨小说恢复）
     * 
     * 核心功能：
     * - 跨小说恢复：可以将一个小说的历史记录恢复到另一个小说中
     * - 数据隔离：创建设定条目的全新副本，避免数据冲突
     * - ID重生成：重新生成所有设定条目的ID和时间戳
     * - 权限验证：确保只有历史记录的所有者可以进行恢复操作
     * 
     * 业务流程：
     * 1. 获取历史记录及其包含的所有设定条目
     * 2. 验证用户是否有权限操作此历史记录
     * 3. 为每个设定条目创建新副本，更新小说ID为目标小说
     * 4. 重新生成ID和时间戳，避免与现有数据冲突
     * 5. 批量保存所有新设定条目到数据库
     * 6. 返回新创建的设定条目ID列表
     * 
     * 使用场景：
     * - 将某个小说的设定应用到新小说中
     * - 从历史版本恢复设定到当前小说
     * - 设定模板的复用和应用
     * 
     * @param historyId 历史记录ID
     * @param novelId 目标小说ID
     * @param userId 用户ID（权限验证）
     * @return 恢复后创建的设定条目ID列表
     */
    @Override
    public Mono<List<String>> restoreHistoryToNovel(String historyId, String novelId, String userId) {
        log.info("恢复历史记录 {} 到指定小说 {} by user: {}", historyId, novelId, userId);
        
        return getHistoryWithSettings(historyId)
                .flatMap(historyWithSettings -> {
                    NovelSettingGenerationHistory history = historyWithSettings.history();
                    List<SettingNode> rootNodes = historyWithSettings.rootNodes();
                    
                    if (!history.getUserId().equals(userId)) {
                        return Mono.error(new RuntimeException("无权限恢复此历史记录"));
                    }
                    
                    // 将 SettingNode 树转换为 NovelSettingItem 列表
                    List<SettingNode> flatNodes = flattenSettingNodeTree(rootNodes);
                    List<NovelSettingItem> settings = flatNodes.stream()
                        .map(node -> conversionService.convertNodeToSettingItem(node, novelId, userId))
                        .collect(Collectors.toList());
                    
                    // 保存所有设定条目到指定小说（创建新的副本）
                    List<Mono<NovelSettingItem>> saveOperations = settings.stream()
                            .map(item -> {
                                // 重新生成ID和时间戳，更新小说ID
                                item.setId(UUID.randomUUID().toString());
                                item.setNovelId(novelId); // 设置为目标小说ID
                                item.setCreatedAt(LocalDateTime.now());
                                item.setUpdatedAt(LocalDateTime.now());
                                return novelSettingService.createSettingItem(item);
                            })
                            .collect(Collectors.toList());
                    
                    return Flux.fromIterable(saveOperations)
                            .flatMap(mono -> mono)
                            .map(NovelSettingItem::getId)
                            .collectList();
                });
    }

    @Override
    public Mono<List<String>> copyHistoryItemsToNovel(String historyId, String novelId, String userId) {
        log.info("[历史拷贝] 直接复制历史记录条目到小说: historyId={}, novelId={}, userId={}", historyId, novelId, userId);
        return historyRepository.findById(historyId)
                .switchIfEmpty(Mono.error(new RuntimeException("历史记录不存在: " + historyId)))
                .flatMap(history -> {
                    if (!Objects.equals(history.getUserId(), userId)) {
                        return Mono.error(new RuntimeException("无权限恢复此历史记录"));
                    }
                    List<String> ids = history.getGeneratedSettingIds();
                    if (ids == null || ids.isEmpty()) {
                        log.info("[历史拷贝] 该历史无 generatedSettingIds，跳过");
                        return Mono.just(java.util.Collections.<String>emptyList());
                    }
                    // 批量查询源条目
                    return Flux.fromIterable(ids)
                            .flatMap(novelSettingService::getSettingItemById)
                            .collectList()
                            .flatMap(sourceItems -> {
                                try { log.info("[历史拷贝] 准备克隆设定条目数量: {}", (sourceItems != null ? sourceItems.size() : 0)); } catch (Exception ignore) {}
                                Map<String, List<String>> parentChildMap = history.getParentChildMap() != null
                                        ? new HashMap<>(history.getParentChildMap())
                                        : new HashMap<>();
                                // 先创建所有条目的浅拷贝并分配新ID
                                Map<String, String> oldToNewId = new HashMap<>();
                                List<NovelSettingItem> clones = new ArrayList<>();
                                for (NovelSettingItem src : sourceItems) {
                                    String newId = UUID.randomUUID().toString();
                                    oldToNewId.put(src.getId(), newId);
                                    NovelSettingItem clone = NovelSettingItem.builder()
                                            .id(newId)
                                            .novelId(novelId)
                                            .userId(userId)
                                            .name(src.getName())
                                            .type(src.getType())
                                            .description(src.getDescription())
                                            .attributes(src.getAttributes() != null ? new HashMap<>(src.getAttributes()) : null)
                                            .imageUrl(src.getImageUrl())
                                            .relationships(null) // 关系后续可按需复制
                                            .sceneIds(null) // 场景关联不复制
                                            .priority(src.getPriority())
                                            .generatedBy("HISTORY_RESTORE")
                                            .tags(src.getTags() != null ? new ArrayList<>(src.getTags()) : null)
                                            .status(src.getStatus())
                                            .vector(null)
                                            .createdAt(LocalDateTime.now())
                                            .updatedAt(LocalDateTime.now())
                                            .isAiSuggestion(false)
                                            .metadata(src.getMetadata() != null ? new HashMap<>(src.getMetadata()) : null)
                                            .parentId(null) // 先置空，稍后重建
                                            .childrenIds(null)
                                            .nameAliasTracking(src.getNameAliasTracking())
                                            .aiContextTracking(src.getAiContextTracking())
                                            .referenceUpdatePolicy(src.getReferenceUpdatePolicy())
                                            .build();
                                    clones.add(clone);
                                }
                                // 批量保存克隆条目
                                return novelSettingService.saveAll(clones)
                                        .collectList()
                                        .flatMap(saved -> {
                                            try { log.info("[历史拷贝] 已保存克隆条目数量: {}，开始重建父子关系", (saved != null ? saved.size() : 0)); } catch (Exception ignore) {}
                                            // 根据 parentChildMap 重建父子关系
                                            List<Mono<NovelSettingItem>> relOps = new ArrayList<>();
                                            for (Map.Entry<String, List<String>> e : parentChildMap.entrySet()) {
                                                String oldParent = e.getKey();
                                                String newParent = oldToNewId.get(oldParent);
                                                if (newParent == null) continue;
                                                for (String oldChild : e.getValue()) {
                                                    String newChild = oldToNewId.get(oldChild);
                                                    if (newChild == null) continue;
                                                    relOps.add(novelSettingService.setParentChildRelationship(newChild, newParent));
                                                }
                                            }
                                            return Flux.fromIterable(relOps)
                                                    .flatMap(m -> m)
                                                    .then(Mono.fromSupplier(() -> {
                                                        List<String> newIds = saved.stream().map(NovelSettingItem::getId).collect(Collectors.toList());
                                                        try { log.info("[历史拷贝] 关系重建完成，新条目数: {}", newIds.size()); } catch (Exception ignore) {}
                                                        return newIds;
                                                    }));
                                        });
                            });
                });
    }

    /**
     * 批量删除历史记录
     * 
     * 特性：
     * - 权限安全：只能删除属于当前用户的历史记录
     * - 容错处理：单个删除失败不影响其他记录的删除
     * - 关联清理：删除历史记录时会同时清理相关的节点历史记录
     * - 统计返回：返回实际成功删除的记录数量
     * 
     * 业务流程：
     * 1. 遍历每个历史记录ID
     * 2. 验证记录存在性和用户权限
     * 3. 删除关联的节点历史记录（NovelSettingItemHistory）
     * 4. 删除历史记录主体
     * 5. 统计成功删除的数量
     * 
     * 错误处理：
     * - 如果某个历史记录不存在或无权限访问，该记录删除失败但不影响其他记录
     * - 返回值反映实际删除成功的记录数量
     * 
     * @param historyIds 要删除的历史记录ID列表
     * @param userId 用户ID（权限验证）
     * @return 实际删除成功的记录数量
     */
    @Override
    public Mono<Integer> batchDeleteHistories(List<String> historyIds, String userId) {
        log.info("批量删除历史记录 {} by user: {}", historyIds, userId);
        
        if (historyIds == null || historyIds.isEmpty()) {
            return Mono.just(0);
        }
        
        return Flux.fromIterable(historyIds)
            .flatMap(historyId -> 
                historyRepository.findById(historyId)
                    .filter(history -> history.getUserId().equals(userId))
                    .flatMap(history -> {
                        // 删除关联的节点历史记录
                        return itemHistoryRepository.deleteByHistoryId(historyId)
                            .then(historyRepository.deleteById(historyId))
                            .thenReturn(1);
                    })
                    .onErrorReturn(0) // 如果删除失败，返回0
            )
            .reduce(Integer::sum)
            .defaultIfEmpty(0);
    }

    @Override 
    public Mono<Long> countUserHistories(String userId, String novelId) {
        if (novelId != null && !novelId.trim().isEmpty()) {
            return historyRepository.countByUserIdAndNovelId(userId, novelId);
        } else {
            return historyRepository.countByUserId(userId);
        }
    }

    @Override
    public String generateHistoryTitle(String initialPrompt, String strategy, Integer settingsCount) {
        if (initialPrompt == null || initialPrompt.trim().isEmpty()) {
            return String.format("%s策略生成 - %d个设定", strategy, settingsCount);
        }
        
        // 截取提示词的前20个字符作为标题
        String promptPreview = initialPrompt.length() > 20 ? 
                initialPrompt.substring(0, 20) + "..." : initialPrompt;
        
        return String.format("%s - %d个设定", promptPreview, settingsCount);
    }

    // ==================== 私有辅助方法 ====================

    /**
     * 为生成的设定创建节点历史记录
     */
    private Mono<Void> createNodeHistoriesForGeneration(NovelSettingGenerationHistory history, 
                                                       List<NovelSettingItem> settingItems) {
        List<Mono<NovelSettingItemHistory>> historyCreations = settingItems.stream()
                .map(item -> recordNodeChange(
                        item.getId(),
                        history.getHistoryId(),
                        "CREATE",
                        null,
                        item,
                        "AI生成设定",
                        history.getUserId()
                ))
                .collect(Collectors.toList());
        
        return Flux.fromIterable(historyCreations)
                .flatMap(mono -> mono)
                .then();
    }

    /**
     * 为更新的设定创建节点历史记录
     * 
     * 更新操作会保留原有的历史记录，只是新增UPDATE类型的记录
     */
    private Mono<Void> createNodeHistoriesForUpdate(NovelSettingGenerationHistory history, 
                                                   List<NovelSettingItem> settingItems) {
        // 获取现有设定条目作为beforeContent
        return Flux.fromIterable(settingItems)
                .flatMap(item -> {
                    // 查找该设定条目的最新历史记录，作为beforeContent
                    return itemHistoryRepository.findTopBySettingItemIdOrderByVersionDesc(item.getId())
                            .map(NovelSettingItemHistory::getAfterContent)
                            .flatMap(beforeContent -> recordNodeChange(
                                    item.getId(),
                                    history.getHistoryId(),
                                    "UPDATE",
                                    beforeContent,
                                    item,
                                    "更新设定历史记录",
                                    history.getUserId()
                            ))
                            // 如果没有历史记录（上游为空），以 beforeContent=null 记录一次变更
                            .switchIfEmpty(recordNodeChange(
                                    item.getId(),
                                    history.getHistoryId(),
                                    "UPDATE",
                                    null,
                                    item,
                                    "更新设定历史记录",
                                    history.getUserId()
                            ));
                })
                .then();
    }

    /**
     * 获取设定条目的下一个版本号
     */
    private Mono<Integer> getNextVersionNumber(String settingItemId) {
        return itemHistoryRepository.findTopBySettingItemIdOrderByVersionDesc(settingItemId)
                .map(history -> history.getVersion() + 1)
                .defaultIfEmpty(1);
    }

    /**
     * 确定生成结果状态
     */
    private String determineGenerationResult(SettingGenerationSession session) {
        switch (session.getStatus()) {
            case COMPLETED:
                return "SUCCESS";
            case ERROR:
                return "FAILED";
            default:
                return "PARTIAL_SUCCESS";
        }
    }

    /**
     * 计算生成耗时
     */
    private Duration calculateGenerationDuration(SettingGenerationSession session) {
        if (session.getCreatedAt() != null && session.getUpdatedAt() != null) {
            return Duration.between(session.getCreatedAt(), session.getUpdatedAt());
        }
        return Duration.ZERO;
    }

    /**
     * 🔧 新增：从设定条目列表构建完整的 SettingNode 树
     * 
     * @param history 历史记录对象
     * @param settingItems 所有设定条目
     * @return 构建好的根节点列表
     */
    private List<SettingNode> buildSettingNodeTree(NovelSettingGenerationHistory history, List<NovelSettingItem> settingItems) {
        log.info("开始构建 SettingNode 树形结构，总设定数: {}, 根节点数: {}", 
                 settingItems.size(), 
                 history.getRootSettingIds() != null ? history.getRootSettingIds().size() : 0);
        
        Map<String, NovelSettingItem> itemMap = new HashMap<>();
        settingItems.forEach(item -> itemMap.put(item.getId(), item));
        
        // 🔧 核心修复：使用 history 对象中存储的 parentChildMap 来构建树
        Map<String, List<String>> parentChildMap = history.getParentChildMap();
        if (parentChildMap == null || parentChildMap.isEmpty()) {
            log.warn("警告：历史记录 {} 的 parentChildMap 为空，可能导致树构建不完整", history.getHistoryId());
            parentChildMap = new HashMap<>(); // 避免空指针
        }
        final Map<String, List<String>> finalParentChildMap = parentChildMap;

        List<SettingNode> rootNodes = new ArrayList<>();
        List<String> rootSettingIds = history.getRootSettingIds();
        
        if (rootSettingIds != null && !rootSettingIds.isEmpty()) {
            rootSettingIds.forEach(rootId -> {
                NovelSettingItem rootItem = itemMap.get(rootId);
                if (rootItem != null) {
                    // 传递 parentChildMap 进行递归构建
                    rootNodes.add(createSettingNodeWithChildren(rootItem, itemMap, finalParentChildMap,1));
                } else {
                    log.warn("根节点ID {} 在设定项列表中未找到", rootId);
                }
            });
        } else {
            // 兼容没有 rootSettingIds 的旧数据
            log.warn("警告：历史记录 {} 没有 rootSettingIds，将通过 parentId=null 查找根节点", history.getHistoryId());
            settingItems.stream()
                .filter(item -> item.getParentId() == null)
                .forEach(rootItem -> rootNodes.add(createSettingNodeWithChildren(rootItem, itemMap, finalParentChildMap,1)));
        }
        
        log.info("构建 SettingNode 树形结构完成，根节点数量: {}", rootNodes.size());
        return rootNodes;
    }

    /**
     * 🔧 核心修复：递归创建包含子节点的 SettingNode 树（使用 parentChildMap）
     * 
     * @param parentItem 父节点条目
     * @param itemMap 所有设定条目的Map
     * @param parentChildMap 从历史记录中获取的父子关系图
     * @return 包含完整子树的 SettingNode
     */
    private SettingNode createSettingNodeWithChildren(NovelSettingItem parentItem, Map<String, NovelSettingItem> itemMap, Map<String, List<String>> parentChildMap, int depth) {
        // 1. 将 NovelSettingItem 转换为 SettingNode
        SettingNode node = conversionService.convertSettingItemToNode(parentItem);

        // 2. 递归构建子节点列表
        List<SettingNode> children = new ArrayList<>();
        
        // 先从 parentChildMap 获取子节点ID列表
        List<String> childIds = parentChildMap.get(parentItem.getId());

        // 兼容旧数据：若 parentChildMap 中没有记录，再使用 NovelSettingItem 的 childrenIds 字段
        if ((childIds == null || childIds.isEmpty()) && parentItem.getChildrenIds() != null && !parentItem.getChildrenIds().isEmpty()) {
            log.debug("节点 '{}' 在 parentChildMap 中未找到子节点，使用 childrenIds 字段 ({} 个)", parentItem.getName(), parentItem.getChildrenIds().size());
            childIds = parentItem.getChildrenIds();
        }
        
        if (childIds != null) {
            log.debug("节点 '{}' (层级 {}) 发现 {} 个子节点: {}", parentItem.getName(), depth, childIds.size(), childIds);
            childIds.forEach(childId -> {
                NovelSettingItem childItem = itemMap.get(childId);
                if (childItem != null) {
                    children.add(createSettingNodeWithChildren(childItem, itemMap, parentChildMap, depth + 1));
                } else {
                    log.warn("子节点ID {} 在设定项列表中未找到 (父节点: '{}')", childId, parentItem.getName());
                }
            });
        }
        
        // 3. 设置子节点列表
        node.setChildren(children);

        return node;
    }

    /**
     * 🔧 新增：将 SettingNode 树扁平化为列表
     * 
     * @param rootNodes 根节点列表
     * @return 扁平化的节点列表
     */
    private List<SettingNode> flattenSettingNodeTree(List<SettingNode> rootNodes) {
        List<SettingNode> result = new ArrayList<>();
        for (SettingNode rootNode : rootNodes) {
            collectAllNodes(rootNode, result);
        }
        return result;
    }

    /**
     * 🔧 新增：递归收集所有节点
     * 
     * @param node 当前节点
     * @param result 结果列表
     */
    private void collectAllNodes(SettingNode node, List<SettingNode> result) {
        result.add(node);
        if (node.getChildren() != null) {
            for (SettingNode child : node.getChildren()) {
                collectAllNodes(child, result);
            }
        }
    }
} 