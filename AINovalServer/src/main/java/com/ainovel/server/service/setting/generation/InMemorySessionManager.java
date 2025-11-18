package com.ainovel.server.service.setting.generation;

import com.ainovel.server.domain.model.setting.generation.SettingGenerationSession;
import com.ainovel.server.domain.model.setting.generation.SettingNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 内存会话管理器
 * 在内存中管理设定生成会话
 */
@Slf4j
@Service
public class InMemorySessionManager {
    
    private final Map<String, SettingGenerationSession> sessions = new ConcurrentHashMap<>();
    
    /**
     * 创建新会话
     */
    public Mono<SettingGenerationSession> createSession(String userId, String novelId, 
                                                       String initialPrompt, String strategy) {
        return createSession(userId, novelId, initialPrompt, strategy, null);
    }
    
    /**
     * 创建新会话（支持promptTemplateId）
     */
    public Mono<SettingGenerationSession> createSession(String userId, String novelId, 
                                                       String initialPrompt, String strategy, String promptTemplateId) {
        return createSession(null, userId, novelId, initialPrompt, strategy, promptTemplateId);
    }
    
    /**
     * 创建新会话（支持前端传入sessionId）
     * @param sessionId 前端生成的sessionId（可选，如果为null则后端自动生成UUID）
     */
    public Mono<SettingGenerationSession> createSession(String sessionId, String userId, String novelId, 
                                                       String initialPrompt, String strategy, String promptTemplateId) {
        // 如果前端没有提供sessionId，则后端生成
        if (sessionId == null || sessionId.isBlank()) {
            sessionId = UUID.randomUUID().toString();
            log.info("前端未提供sessionId，后端生成: {}", sessionId);
        } else {
            log.info("使用前端提供的sessionId: {}", sessionId);
        }
        
        LocalDateTime now = LocalDateTime.now();
        
        SettingGenerationSession session = SettingGenerationSession.builder()
            .sessionId(sessionId)
            .userId(userId)
            .novelId(novelId)
            .initialPrompt(initialPrompt)
            .strategy(strategy)
            .promptTemplateId(promptTemplateId)
            .status(SettingGenerationSession.SessionStatus.INITIALIZING)
            .createdAt(now)
            .updatedAt(now)
            .expiresAt(now.plusHours(24))
            .build();
        
        sessions.put(sessionId, session);
        log.info("Created session: {} for user: {}, strategy: {}, templateId: {}", 
            sessionId, userId, strategy, promptTemplateId);
        
        return Mono.just(session);
    }
    
    /**
     * 创建会话（基于历史记录数据）
     */
    public Mono<SettingGenerationSession> createSessionFromHistoryData(
            String sessionId, String userId, String novelId, String initialPrompt, 
            String strategy, Map<String, SettingNode> nodes, java.util.List<String> rootNodeIds) {
        return createSessionFromHistoryData(sessionId, userId, novelId, initialPrompt, 
            strategy, nodes, rootNodeIds, null);
    }
    
    /**
     * 创建会话（基于历史记录数据，支持promptTemplateId）
     */
    public Mono<SettingGenerationSession> createSessionFromHistoryData(
            String sessionId, String userId, String novelId, String initialPrompt, 
            String strategy, Map<String, SettingNode> nodes, java.util.List<String> rootNodeIds, 
            String promptTemplateId) {
        log.info("Attempting to create session from history: {}", sessionId);
        
        LocalDateTime now = LocalDateTime.now();
        
        SettingGenerationSession session = SettingGenerationSession.builder()
            .sessionId(sessionId)
            .userId(userId)
            .novelId(novelId)
            .initialPrompt(initialPrompt)
            .strategy(strategy)
            .promptTemplateId(promptTemplateId)
            .status(SettingGenerationSession.SessionStatus.COMPLETED)
            .fromExistingHistory(true)
            .sourceHistoryId(sessionId)
            .generatedNodes(nodes)
            .rootNodeIds(rootNodeIds)
            .createdAt(now)
            .updatedAt(now)
            .expiresAt(now.plusHours(24))
            .build();
        
        sessions.put(sessionId, session);
        log.info("Created session from history data: {} for user: {}, nodes: {}, templateId: {}", 
            sessionId, userId, nodes.size(), promptTemplateId);
        
        return Mono.just(session);
    }
    
    /**
     * 获取会话
     */
    public Mono<SettingGenerationSession> getSession(String sessionId) {
        SettingGenerationSession session = sessions.get(sessionId);
        if (session == null) {
            return Mono.empty();
        }
        
        // 检查是否过期
        if (session.getExpiresAt().isBefore(LocalDateTime.now())) {
            sessions.remove(sessionId);
            log.info("Session expired and removed: {}", sessionId);
            return Mono.empty();
        }
        log.debug("Session found: {}", sessionId); // 降级为DEBUG，避免频繁日志
        
        return Mono.just(session);
    }
    
    /**
     * 保存会话
     */
    public Mono<SettingGenerationSession> saveSession(SettingGenerationSession session) {
        session.setUpdatedAt(LocalDateTime.now());
        sessions.put(session.getSessionId(), session);
        return Mono.just(session);
    }
    
    /**
     * 更新会话状态
     */
    public Mono<SettingGenerationSession> updateSessionStatus(String sessionId, 
                                                            SettingGenerationSession.SessionStatus status) {
        return getSession(sessionId)
            .flatMap(session -> {
                session.setStatus(status);
                return saveSession(session);
            });
    }
    
    /**
     * 添加节点到会话
     */
    public Mono<SettingGenerationSession> addNodeToSession(String sessionId, SettingNode node) {
        return getSession(sessionId)
            .flatMap(session -> {
                session.addNode(node);
                return saveSession(session);
            });
    }
    
    /**
     * 从会话中删除节点
     */
    public Mono<SettingGenerationSession> removeNodeFromSession(String sessionId, String nodeId) {
        return getSession(sessionId)
            .flatMap(session -> {
                session.removeNodeAndDescendants(nodeId);
                return saveSession(session);
            });
    }
    
    /**
     * 设置错误信息
     */
    public Mono<SettingGenerationSession> setSessionError(String sessionId, String errorMessage) {
        return getSession(sessionId)
            .flatMap(session -> {
                session.setStatus(SettingGenerationSession.SessionStatus.ERROR);
                session.setErrorMessage(errorMessage);
                return saveSession(session);
            });
    }
    
    /**
     * 删除会话
     */
    public Mono<Void> deleteSession(String sessionId) {
        sessions.remove(sessionId);
        log.info("Deleted session: {}", sessionId);
        return Mono.empty();
    }
    
    /**
     * 获取所有活跃会话数
     */
    public int getActiveSessionCount() {
        return sessions.size();
    }
    
    /**
     * 定期清理过期会话
     */
    @Scheduled(fixedDelay = 3600000) // 每小时执行一次
    public void cleanupExpiredSessions() {
        LocalDateTime now = LocalDateTime.now();
        int removedCount = 0;
        
        for (Map.Entry<String, SettingGenerationSession> entry : sessions.entrySet()) {
            if (entry.getValue().getExpiresAt().isBefore(now)) {
                sessions.remove(entry.getKey());
                removedCount++;
            }
        }
        
        if (removedCount > 0) {
            log.info("Cleaned up {} expired sessions", removedCount);
        }
    }
}