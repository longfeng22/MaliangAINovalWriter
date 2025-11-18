package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.jasypt.encryption.StringEncryptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import com.ainovel.server.domain.model.AIChatMessage;
import com.ainovel.server.domain.model.AIChatSession;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ChatMemoryConfig;
import com.ainovel.server.domain.model.UserAIModelConfig;
import com.ainovel.server.repository.AIChatMessageRepository;
import com.ainovel.server.repository.AIChatSessionRepository;
import com.ainovel.server.service.AIChatService;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.ChatMemoryService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Slf4j
@Service
public class AIChatServiceImpl implements AIChatService {

    private final AIChatSessionRepository sessionRepository;
    private final AIChatMessageRepository messageRepository;
    private final UserAIModelConfigService userAIModelConfigService;
    private final AIService aiService;
    private final ChatMemoryService chatMemoryService;
    private final StringEncryptor encryptor;
    private final com.ainovel.server.service.impl.content.ContentProviderFactory contentProviderFactory;
    // 已移除上游公共模型分支逻辑

    @Value("${ainovel.ai.default-system-model:gpt-3.5-turbo}")
    private String defaultSystemModelName;

    @Autowired
    public AIChatServiceImpl(AIChatSessionRepository sessionRepository,
            AIChatMessageRepository messageRepository,
            UserAIModelConfigService userAIModelConfigService,
            AIService aiService,
            ChatMemoryService chatMemoryService,
            StringEncryptor encryptor,
            com.ainovel.server.service.impl.content.ContentProviderFactory contentProviderFactory) {
        this.sessionRepository = sessionRepository;
        this.messageRepository = messageRepository;
        this.userAIModelConfigService = userAIModelConfigService;
        this.aiService = aiService;
        this.chatMemoryService = chatMemoryService;
        this.encryptor = encryptor;
        this.contentProviderFactory = contentProviderFactory;
    }

    @Override
    public Mono<AIChatSession> createSession(String userId, String novelId, String modelName, Map<String, Object> metadata) {
        if (StringUtils.hasText(modelName)) {
            log.info("尝试使用用户指定的模型名称创建会话: userId={}, modelName={}", userId, modelName);
            String provider;
            try {
                provider = aiService.getProviderForModel(modelName);
            } catch (IllegalArgumentException e) {
                log.warn("用户指定的模型名称无效: {}", modelName);
                return Mono.error(new IllegalArgumentException("指定的模型名称无效: " + modelName));
            }
            return userAIModelConfigService.getValidatedConfig(userId, provider, modelName)
                    .flatMap(config -> {
                        log.info("找到用户 {} 的模型 {} 对应配置 ID: {}", userId, modelName, config.getId());
                        return createSessionInternal(userId, novelId, config.getId(), metadata);
                    })
                    .switchIfEmpty(Mono.<AIChatSession>defer(() -> {
                        log.warn("用户 {} 指定的模型 {} 未找到有效的配置", userId, modelName);
                        return Mono.error(new RuntimeException("您选择的模型 '" + modelName + "' 未配置或未验证，请先在模型设置中配置。"));
                    }));
        } else {
            log.info("未指定模型，开始为用户 {} 智能选择模型...", userId);
            return findSuitableModelConfig(userId)
                    .flatMap(config -> createSessionInternal(userId, novelId, config.getId(), metadata));
        }
    }

    // 旧公共模型回退逻辑已移除：无私有配置时不再在此层选择公共模型，统一由上游传入可用的 modelConfigId

    private Mono<AIChatSession> createSessionInternal(String userId, String novelId, String selectedModelConfigId, Map<String, Object> metadata) {
        String sessionId = UUID.randomUUID().toString();
        AIChatSession session = AIChatSession.builder()
                .sessionId(sessionId)
                .userId(userId)
                .novelId(novelId)
                .selectedModelConfigId(selectedModelConfigId)
                .metadata(metadata)
                .status("ACTIVE")
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .messageCount(0)
                .build();

        log.info("创建新会话: userId={}, sessionId={}, selectedModelConfigId={}", userId, sessionId, selectedModelConfigId);
        return sessionRepository.save(session);
    }

    private Mono<UserAIModelConfig> findSuitableModelConfig(String userId) {
        return userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                .doOnNext(config -> log.info("找到用户 {} 的默认模型配置: configId={}, modelName={}", userId, config.getId(), config.getModelName()))
                .switchIfEmpty(Mono.<UserAIModelConfig>defer(() -> {
                    log.info("用户 {} 无默认模型，尝试查找第一个可用模型...", userId);
                    return userAIModelConfigService.getFirstValidatedConfiguration(userId)
                            .doOnNext(config -> log.info("找到用户 {} 的第一个可用模型配置: configId={}, modelName={}", userId, config.getId(), config.getModelName()));
                }));
    }

    // ==================== 🚀 支持novelId的会话管理方法 ====================

    @Override
    public Mono<AIChatSession> getSession(String userId, String novelId, String sessionId) {
        log.info("获取会话详情（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        return sessionRepository.findByUserIdAndNovelIdAndSessionId(userId, novelId, sessionId);
    }

    @Override
    public Flux<AIChatSession> listUserSessions(String userId, String novelId, int page, int size) {
        log.info("获取用户会话列表（支持novelId隔离） - userId: {}, novelId: {}, page: {}, size: {}", userId, novelId, page, size);
        return sessionRepository.findByUserIdAndNovelId(userId, novelId,
                PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "updatedAt")));
    }

    @Override
    public Mono<AIChatSession> updateSession(String userId, String novelId, String sessionId, Map<String, Object> updates) {
        log.info("更新会话（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        return sessionRepository.findByUserIdAndNovelIdAndSessionId(userId, novelId, sessionId)
                .cast(AIChatSession.class)
                .flatMap(session -> {
                    // 使用与原有方法相同的更新逻辑
                    return updateSessionInternal(session, updates, userId, sessionId);
                });
    }

    @Override
    public Mono<Void> deleteSession(String userId, String novelId, String sessionId) {
        log.warn("准备删除会话及其消息（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        return messageRepository.deleteBySessionId(sessionId)
                .then(sessionRepository.deleteByUserIdAndNovelIdAndSessionId(userId, novelId, sessionId))
                .doOnSuccess(v -> log.info("成功删除会话及其消息（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId))
                .doOnError(e -> log.error("删除会话时出错（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId, e));
    }

    @Override
    public Mono<Long> countUserSessions(String userId, String novelId) {
        return sessionRepository.countByUserIdAndNovelId(userId, novelId);
    }

    // ==================== 🚀 保留原有方法以确保向后兼容 ====================

    @Override
    @Deprecated
    public Mono<AIChatSession> getSession(String userId, String sessionId) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId);
    }

    @Override
    @Deprecated
    public Flux<AIChatSession> listUserSessions(String userId, int page, int size) {
        return sessionRepository.findByUserId(userId,
                PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "updatedAt")));
    }

    @Override
    @Deprecated
    public Mono<AIChatSession> updateSession(String userId, String sessionId, Map<String, Object> updates) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .cast(AIChatSession.class)
                .flatMap(session -> updateSessionInternal(session, updates, userId, sessionId));
    }

    // ==================== 🚀 内部辅助方法 ====================

    /**
     * 内部会话更新逻辑，供新旧方法共用
     */
    private Mono<AIChatSession> updateSessionInternal(AIChatSession session, Map<String, Object> updates, String userId, String sessionId) {
        boolean needsSave = false;
        Mono<AIChatSession> updateMono = Mono.just(session);

        if (updates.containsKey("title") && updates.get("title") instanceof String) {
            session.setTitle((String) updates.get("title"));
            needsSave = true;
        }
        if (updates.containsKey("status") && updates.get("status") instanceof String) {
            session.setStatus((String) updates.get("status"));
            needsSave = true;
        }
        if (updates.containsKey("metadata") && updates.get("metadata") instanceof Map) {
            session.setMetadata((Map<String, Object>) updates.get("metadata"));
            needsSave = true;
        }

        if (updates.containsKey("selectedModelConfigId") && updates.get("selectedModelConfigId") instanceof String newSelectedModelConfigId) {
            if (!newSelectedModelConfigId.equals(session.getSelectedModelConfigId())) {
                log.info("用户 {} 尝试更新会话 {} 的模型配置为 ID: {}", userId, sessionId, newSelectedModelConfigId);
                
                // 统一：不再区分公共/私有，直接尝试按配置验证；若需要公共配置，由上游传入可用configId
                updateMono = userAIModelConfigService.getConfigurationById(userId, newSelectedModelConfigId)
                        .filter(UserAIModelConfig::getIsValidated)
                        .flatMap(config -> {
                            log.info("找到并验证通过新的模型配置: configId={}, modelName={}", config.getId(), config.getModelName());
                            session.setSelectedModelConfigId(newSelectedModelConfigId);
                            session.setUpdatedAt(LocalDateTime.now());
                            log.info("会话 {} 模型配置已更新为: {}", sessionId, newSelectedModelConfigId);
                            return Mono.just(session);
                        })
                        .switchIfEmpty(Mono.<AIChatSession>defer(() -> {
                            log.warn("用户 {} 尝试更新会话 {} 到模型配置ID {}，但未找到有效或已验证的配置", userId, sessionId, newSelectedModelConfigId);
                            return Mono.error(new RuntimeException("无法更新到指定的模型配置 '" + newSelectedModelConfigId + "'，请确保配置存在且已验证。"));
                        }));
                needsSave = true;
            }
        }

        // 🚀 支持更新activePromptPresetId
        if (updates.containsKey("activePromptPresetId") && updates.get("activePromptPresetId") instanceof String) {
            session.setActivePromptPresetId((String) updates.get("activePromptPresetId"));
            needsSave = true;
        }

        final boolean finalNeedsSave = needsSave;
        return updateMono.flatMap(updatedSession -> {
            if (finalNeedsSave && !updatedSession.getStatus().equals("FAILED")) {
                updatedSession.setUpdatedAt(LocalDateTime.now());
                log.info("保存会话更新: userId={}, sessionId={}", userId, sessionId);
                return sessionRepository.save(updatedSession);
            }
            return Mono.just(updatedSession);
        });
    }

    @Override
    @Deprecated
    public Mono<Void> deleteSession(String userId, String sessionId) {
        log.warn("准备删除会话及其消息: userId={}, sessionId={}", userId, sessionId);
        return messageRepository.deleteBySessionId(sessionId)
                .then(sessionRepository.deleteByUserIdAndSessionId(userId, sessionId))
                .doOnSuccess(v -> log.info("成功删除会话及其消息: userId={}, sessionId={}", userId, sessionId))
                .doOnError(e -> log.error("删除会话时出错: userId={}, sessionId={}", userId, sessionId, e));
    }

    @Override
    @Deprecated
    public Mono<Long> countUserSessions(String userId) {
        return sessionRepository.countByUserId(userId);
    }

    @Override
    public Mono<AIChatMessage> sendMessage(String userId, String sessionId, String content, Map<String, Object> metadata) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .cast(AIChatSession.class)
                .flatMap(session -> {

                    // 🚀 检查是否需要自动生成标题
                    Mono<AIChatSession> sessionMono = Mono.just(session);
                    if (shouldGenerateTitle(session)) {
                        sessionMono = generateSessionTitle(session, content)
                                .flatMap(updatedSession -> sessionRepository.save(updatedSession))
                                .onErrorResume(e -> {
                                    log.warn("自动生成会话标题失败，继续使用原标题: sessionId={}, error={}", sessionId, e.getMessage());
                                    return Mono.just(session);
                                });
                    }

                    return sessionMono.flatMap(updatedSession -> {
                        return userAIModelConfigService.getConfigurationById(userId, updatedSession.getSelectedModelConfigId())
                                .filter(UserAIModelConfig::getIsValidated)
                                .switchIfEmpty(Mono.<UserAIModelConfig>defer(() -> {
                                    log.error("发送消息失败，会话 {} 使用的模型配置 {} 未验证", sessionId, updatedSession.getSelectedModelConfigId());
                                    return Mono.error(new RuntimeException("您当前的模型配置未验证，请先在设置中验证API Key。"));
                                }))
                                .flatMap(config -> {
                                    String modelName = config.getModelName();
                                    String userApiKey = config.getApiKey();

                                    if (userApiKey == null || userApiKey.trim().isEmpty()) {
                                        log.error("发送消息失败，用户 {} 的模型配置 {} 中未找到有效的API Key", userId, config.getId());
                                        return Mono.error(new RuntimeException("API Key未配置，请先在设置中添加API Key。"));
                                    }

                                    try {
                                        String decryptedApiKey = encryptor.decrypt(userApiKey);
                                        if (decryptedApiKey.length() < 10) {
                                            log.error("发送消息失败，解密后的API Key长度异常: userId={}, configId={}", userId, config.getId());
                                            return Mono.error(new RuntimeException("API Key格式错误，请重新配置。"));
                                        }

                                        String userMessageId = UUID.randomUUID().toString();
                                        AIRequest aiRequest = buildAIRequest(updatedSession, modelName, content, userMessageId, 20);

                                        return aiService.generateContent(aiRequest, decryptedApiKey, config.getApiEndpoint())
                                                .doOnNext(response -> {
                                                    log.info("AI响应接收成功: sessionId={}, responseLength={}", sessionId, 
                                                        response.getContent() != null ? response.getContent().length() : 0);
                                                })
                                                .flatMap(aiResponse -> {
                                                    // 保存用户消息
                                                    AIChatMessage userMessage = AIChatMessage.builder()
                                                            .sessionId(sessionId)
                                                            .userId(userId)
                                                            .role("user")
                                                            .content(content)
                                                            .modelName(modelName)
                                                            .metadata(metadata)
                                                            .status("SENT")
                                                            .messageType("TEXT")
                                                            .createdAt(LocalDateTime.now())
                                                            .build();

                                                    return messageRepository.save(userMessage)
                                                            .flatMap(savedUserMessage -> {
                                                                // 保存AI响应消息
                                                                AIChatMessage aiMessage = AIChatMessage.builder()
                                                                        .sessionId(sessionId)
                                                                        .userId(userId)
                                                                        .role("assistant")
                                                                        .content(aiResponse.getContent())
                                                                        .modelName(modelName)
                                                                        .metadata(aiResponse.getMetadata() != null ? aiResponse.getMetadata() : Map.of())
                                                                        .status("DELIVERED")
                                                                        .messageType("TEXT")
                                                                        .parentMessageId(savedUserMessage.getId())
                                                                        .tokenCount(aiResponse.getMetadata() != null ? (Integer) aiResponse.getMetadata().getOrDefault("tokenCount", 0) : 0)
                                                                        .createdAt(LocalDateTime.now())
                                                                        .build();

                                                                return messageRepository.save(aiMessage)
                                                                        .flatMap(savedAiMessage -> {
                                                                            // 更新会话统计
                                                                            updatedSession.setMessageCount(updatedSession.getMessageCount() + 2); // 用户消息 + AI消息
                                                                            updatedSession.setLastMessageAt(LocalDateTime.now());
                                                                            return sessionRepository.save(updatedSession)
                                                                                    .thenReturn(savedAiMessage);
                                                                        });
                                                            });
                                                });
                                    } catch (Exception e) {
                                        log.error("发送消息前解密 API Key 失败: userId={}, sessionId={}, configId={}", userId, sessionId, config.getId(), e);
                                        return Mono.error(new RuntimeException("API Key解密失败，请重新配置。"));
                                    }
                                });
                    });
                })
                .switchIfEmpty(Mono.<AIChatMessage>defer(() -> {
                    log.error("发送消息失败，未找到会话: userId={}, sessionId={}", userId, sessionId);
                    return Mono.error(new RuntimeException("会话不存在或已被删除。"));
                }));
    }

    /**
     * 判断是否需要自动生成标题
     */
    private boolean shouldGenerateTitle(AIChatSession session) {
        // 第一次发送消息（消息数量为0）且标题为空或是默认标题
        return session.getMessageCount() == 0 && 
               (session.getTitle() == null || 
                session.getTitle().trim().isEmpty() || 
                session.getTitle().equals("新的聊天") ||
                session.getTitle().equals("无标题会话") ||
                session.getTitle().startsWith("会话"));
    }

    /**
     * 自动生成会话标题
     */
    private Mono<AIChatSession> generateSessionTitle(AIChatSession session, String firstMessage) {
        return Mono.fromCallable(() -> {
            String generatedTitle;
            
            // 根据消息内容生成标题 - 使用前10个字符
            if (firstMessage.length() > 10) {
                // 取前10个字符作为标题基础
                String titleBase = firstMessage.substring(0, 10);
                // 如果最后一个字符不是完整的，尝试截取到最后一个完整的词
                int lastSpace = titleBase.lastIndexOf(' ');
                if (lastSpace > 5) { // 确保至少有5个字符
                    titleBase = titleBase.substring(0, lastSpace);
                }
                generatedTitle = titleBase + "...";
            } else {
                generatedTitle = firstMessage;
            }
            
            // 移除换行符和多余的空格
            generatedTitle = generatedTitle.replaceAll("\\s+", " ").trim();
            
            // 如果标题为空，使用默认格式
            if (generatedTitle.isEmpty()) {
                generatedTitle = "聊天会话 " + LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm"));
            }
            
            log.info("为会话 {} 生成标题（前10字符）: {}", session.getSessionId(), generatedTitle);
            
            // 更新会话标题
            session.setTitle(generatedTitle);
            session.setUpdatedAt(LocalDateTime.now());
            
            return session;
        });
    }

    @Override
    public Flux<AIChatMessage> streamMessage(String userId, String sessionId, String content, Map<String, Object> metadata) {
        return getSession(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                .flatMap(session -> {
                    // 🚀 检查是否需要自动生成标题
                    if (shouldGenerateTitle(session)) {
                        return generateSessionTitle(session, content)
                                .flatMap(updatedSession -> sessionRepository.save(updatedSession))
                                .onErrorResume(e -> {
                                    log.warn("自动生成会话标题失败，继续使用原标题: sessionId={}, error={}", sessionId, e.getMessage());
                                    return Mono.just(session);
                                });
                    }
                    return Mono.just(session);
                })
                .flatMapMany(session -> {
                    // 🚀 尝试从metadata中提取modelConfigId，优先使用前端传递的配置
                    String targetModelConfigId = session.getSelectedModelConfigId();
                    if (metadata != null && metadata.containsKey("aiConfig")) {
                        try {
                            @SuppressWarnings("unchecked")
                            Map<String, Object> aiConfig = (Map<String, Object>) metadata.get("aiConfig");
                            if (aiConfig.containsKey("modelConfigId") && aiConfig.get("modelConfigId") instanceof String) {
                                String frontendConfigId = (String) aiConfig.get("modelConfigId");
                                if (frontendConfigId != null && !frontendConfigId.isEmpty()) {
                                    targetModelConfigId = frontendConfigId;
                                    log.info("使用前端传递的模型配置ID: {} (会话当前配置: {})", frontendConfigId, session.getSelectedModelConfigId());
                                }
                            }
                        } catch (Exception e) {
                            log.warn("解析metadata中的aiConfig失败，使用会话默认配置: {}", e.getMessage());
                        }
                    }

                    final String finalConfigId = targetModelConfigId;
                    
                    return userAIModelConfigService.getConfigurationById(userId, finalConfigId)
                            .switchIfEmpty(Mono.error(new RuntimeException("无法找到或访问私有模型配置: " + finalConfigId)))
                            .flatMapMany(config -> {
                                if (!config.getIsValidated()) {
                                    log.error("流式消息失败，会话 {} 使用的模型配置 {} 未验证", sessionId, config.getId());
                                    return Flux.error(new RuntimeException("当前会话使用的模型配置无效或未验证。"));
                                }

                                String actualModelName = config.getModelName();
                                log.debug("流式处理: 会话 {} 使用模型配置 ID: {}, 实际模型名称: {}", sessionId, config.getId(), actualModelName);

                                AIChatMessage userMessage = AIChatMessage.builder()
                                        .sessionId(sessionId)
                                        .userId(userId)
                                        .role("user")
                                        .content(content)
                                        .modelName(actualModelName)
                                        .metadata(metadata)
                                        .status("SENT")
                                        .messageType("TEXT")
                                        .createdAt(LocalDateTime.now())
                                        .build();

                                return messageRepository.save(userMessage)
                                        .flatMapMany(savedUserMessage -> {
                                            session.setMessageCount(session.getMessageCount() + 1);

                                            String decryptedApiKey;
                                            try {
                                                decryptedApiKey = encryptor.decrypt(config.getApiKey());
                                            } catch (Exception e) {
                                                log.error("流式消息前解密 API Key 失败: userId={}, sessionId={}, configId={}", userId, sessionId, config.getId(), e);
                                                return Flux.error(new RuntimeException("处理请求失败，无法访问模型凭证。"));
                                            }

                                            AIRequest aiRequest = buildAIRequest(session, actualModelName, content, savedUserMessage.getId(), 20);

                                            log.info("准备调用流式AI服务: userId={}, sessionId={}, model={}, provider={}, configId={}",
                                                    userId, sessionId, actualModelName, config.getProvider(), config.getId());

                                            Flux<String> stream = aiService.generateContentStream(aiRequest, decryptedApiKey, config.getApiEndpoint())
                                                    .doOnSubscribe(subscription -> {
                                                        log.info("流式AI服务已被订阅 - sessionId: {}, model: {}", sessionId, actualModelName);
                                                    })
                                                    .doOnNext(chunk -> {
                                                        log.debug("流式AI生成内容块 - sessionId: {}, length: {}", sessionId, chunk != null ? chunk.length() : 0);
                                                    });

                                            StringBuilder responseBuilder = new StringBuilder();
                                            Mono<AIChatMessage> saveFullMessageMono = Mono.defer(() -> {
                                                String fullContent = responseBuilder.toString();
                                                if (StringUtils.hasText(fullContent)) {
                                                    AIChatMessage aiMessage = AIChatMessage.builder()
                                                            .sessionId(sessionId)
                                                            .userId(userId)
                                                            .role("assistant")
                                                            .content(fullContent)
                                                            .modelName(actualModelName)
                                                            .metadata(Map.of("streamed", true))
                                                            .status("DELIVERED")
                                                            .messageType("TEXT")
                                                            .parentMessageId(savedUserMessage.getId())
                                                            .tokenCount(0)
                                                            .createdAt(LocalDateTime.now())
                                                            .build();
                                                    log.debug("流式传输完成，保存完整AI消息: sessionId={}, length={}", sessionId, fullContent.length());
                                                    return messageRepository.save(aiMessage)
                                                            .flatMap(savedMsg -> {
                                                                session.setLastMessageAt(LocalDateTime.now());
                                                                session.setMessageCount(session.getMessageCount() + 1);
                                                                return sessionRepository.save(session).thenReturn(savedMsg);
                                                            });
                                                } else {
                                                    log.warn("流式响应为空，不保存AI消息: sessionId={}", sessionId);
                                                    session.setLastMessageAt(LocalDateTime.now());
                                                    return sessionRepository.save(session).then(Mono.empty());
                                                }
                                            });

                                            return stream
                                                    .doOnNext(responseBuilder::append)
                                                    .map(chunk -> AIChatMessage.builder()
                                                    .sessionId(sessionId)
                                                    .role("assistant")
                                                    .content(chunk)
                                                    .modelName(actualModelName)
                                                    .messageType("STREAM_CHUNK")
                                                    .status("STREAMING")
                                                    .createdAt(LocalDateTime.now())
                                                    .build())
                                                    .doOnComplete(() -> log.info("流式传输完成: sessionId={}", sessionId))
                                                    .doOnError(e -> log.error("流式传输过程中出错: sessionId={}, error={}", sessionId, e.getMessage()))
                                                    .concatWith(saveFullMessageMono.onErrorResume(e -> {
                                                        log.error("保存完整流式消息时出错: sessionId={}", sessionId, e);
                                                        return Mono.empty();
                                                    }).flux());
                                        });
                            });
                });
    }

    private AIRequest buildAIRequest(AIChatSession session, String modelName, String newContent, String userMessageId, int historyLimit) {
        return getRecentMessages(session.getSessionId(), userMessageId, historyLimit)
                .collectList()
                .map(history -> {
                    List<AIRequest.Message> messages = new ArrayList<>();
                    if (history != null) {
                        history.stream()
                                .map(msg -> AIRequest.Message.builder()
                                        .role(msg.getRole())
                                        .content(msg.getContent())
                                        .build())
                                .forEach(messages::add);
                    }
                    messages.add(AIRequest.Message.builder()
                            .role("user")
                            .content(newContent)
                            .build());

                    AIRequest request = new AIRequest();
                    request.setUserId(session.getUserId());
                    request.setModel(modelName);
                    request.setMessages(messages);
                    // 使用可变参数Map，避免后续链路对parameters执行put时报不可变异常
                    Map<String, Object> params = new java.util.HashMap<>();
                    if (session.getMetadata() != null) {
                        params.putAll(session.getMetadata());
                    }
                    request.setTemperature((Double) params.getOrDefault("temperature", 0.7));
                    request.setMaxTokens((Integer) params.getOrDefault("maxTokens", 1024));
                    request.setParameters(params);
                    // 统一：聊天使用 AI_CHAT 特性，traceId 由追踪装饰器生成
                    request.setFeatureType(com.ainovel.server.domain.model.AIFeatureType.AI_CHAT);

                    log.debug("Built AIRequest for model: {}, messages count: {}", modelName, messages.size());
                    return request;
                }).block();
    }

    private Flux<AIChatMessage> getRecentMessages(String sessionId, String excludeMessageId, int limit) {
        return messageRepository.findBySessionIdOrderByCreatedAtDesc(sessionId, limit + 1)
                .filter(msg -> !msg.getId().equals(excludeMessageId))
                .take(limit)
                .collectList()
                .flatMapMany(list -> Flux.fromIterable(list).sort((m1, m2) -> m1.getCreatedAt().compareTo(m2.getCreatedAt())));
    }

    @Override
    public Flux<AIChatMessage> getSessionMessages(String userId, String sessionId, int limit) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .switchIfEmpty(Mono.error(new SecurityException("无权访问此会话的消息")))
                .flatMapMany(session -> messageRepository.findBySessionIdOrderByCreatedAtDesc(sessionId, limit));
    }

    @Override
    public Mono<AIChatMessage> getMessage(String userId, String messageId) {
        return messageRepository.findById(messageId)
                .flatMap(message -> {
                    return sessionRepository.findByUserIdAndSessionId(userId, message.getSessionId())
                            .switchIfEmpty(Mono.error(new SecurityException("无权访问此消息")))
                            .thenReturn(message);
                });
    }

    @Override
    public Mono<Void> deleteMessage(String userId, String messageId) {
        return messageRepository.findById(messageId)
                .switchIfEmpty(Mono.error(new RuntimeException("消息不存在: " + messageId)))
                .flatMap(message -> sessionRepository.findByUserIdAndSessionId(userId, message.getSessionId())
                .switchIfEmpty(Mono.error(new SecurityException("无权删除此消息")))
                .then(messageRepository.deleteById(messageId)));
    }

    @Override
    public Mono<Long> countSessionMessages(String sessionId) {
        return messageRepository.countBySessionId(sessionId);
    }

    // ==================== 🚀 新增：支持novelId的消息管理方法 ====================

    @Override
    public Mono<AIChatMessage> sendMessage(String userId, String novelId, String sessionId, String content, UniversalAIRequestDto aiRequest) {
        log.info("发送消息（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMap(session -> sendMessage(userId, sessionId, content, aiRequest));
    }

    /**
     * 发送消息并获取响应（支持novelId隔离，使用metadata）
     */
    public Mono<AIChatMessage> sendMessage(String userId, String novelId, String sessionId, String content, Map<String, Object> metadata) {
        log.info("发送消息（支持novelId隔离+metadata） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMap(session -> sendMessage(userId, sessionId, content, metadata));
    }

    @Override
    public Flux<AIChatMessage> streamMessage(String userId, String novelId, String sessionId, String content, UniversalAIRequestDto aiRequest) {
        log.info("流式发送消息（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMapMany(session -> streamMessage(userId, sessionId, content, aiRequest));
    }

    @Override
    public Flux<AIChatMessage> getSessionMessages(String userId, String novelId, String sessionId, int limit) {
        log.info("获取会话消息历史（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}, limit: {}", userId, novelId, sessionId, limit);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMapMany(session -> getSessionMessages(userId, sessionId, limit));
    }

    // ==================== 🚀 新增：支持novelId的记忆模式方法 ====================

    @Override
    public Mono<AIChatMessage> sendMessageWithMemory(String userId, String novelId, String sessionId, String content, Map<String, Object> metadata, ChatMemoryConfig memoryConfig) {
        log.info("发送消息（记忆模式+novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMap(session -> sendMessageWithMemory(userId, sessionId, content, metadata, memoryConfig));
    }

    @Override
    public Flux<AIChatMessage> streamMessageWithMemory(String userId, String novelId, String sessionId, String content, Map<String, Object> metadata, ChatMemoryConfig memoryConfig) {
        log.info("流式发送消息（记忆模式+novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMapMany(session -> streamMessageWithMemory(userId, sessionId, content, metadata, memoryConfig));
    }

    @Override
    public Flux<AIChatMessage> getSessionMemoryMessages(String userId, String novelId, String sessionId, ChatMemoryConfig memoryConfig, int limit) {
        log.info("获取会话记忆消息（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMapMany(session -> getSessionMemoryMessages(userId, sessionId, memoryConfig, limit));
    }

    @Override
    public Mono<AIChatSession> updateSessionMemoryConfig(String userId, String novelId, String sessionId, ChatMemoryConfig memoryConfig) {
        log.info("更新会话记忆配置（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMap(session -> updateSessionMemoryConfig(userId, sessionId, memoryConfig));
    }

    @Override
    public Mono<Void> clearSessionMemory(String userId, String novelId, String sessionId) {
        log.info("清除会话记忆（支持novelId隔离） - userId: {}, novelId: {}, sessionId: {}", userId, novelId, sessionId);
        // 先验证会话属于指定小说
        return getSession(userId, novelId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或不属于指定小说")))
                .flatMap(session -> clearSessionMemory(userId, sessionId));
    }

    // ==================== 记忆模式支持方法 ====================

    @Override
    public Mono<AIChatMessage> sendMessageWithMemory(String userId, String sessionId, String content, Map<String, Object> metadata, ChatMemoryConfig memoryConfig) {
        return getSession(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                .flatMap(session -> {
                    // 🚀 检查是否需要自动生成标题
                    if (shouldGenerateTitle(session)) {
                        return generateSessionTitle(session, content)
                                .flatMap(updatedSession -> sessionRepository.save(updatedSession))
                                .onErrorResume(e -> {
                                    log.warn("自动生成会话标题失败，继续使用原标题: sessionId={}, error={}", sessionId, e.getMessage());
                                    return Mono.just(session);
                                });
                    }
                    return Mono.just(session);
                })
                .flatMap(session -> {
                    // 如果会话没有记忆配置，使用传入的配置
                    ChatMemoryConfig finalMemoryConfig = session.getMemoryConfig() != null ? session.getMemoryConfig() : memoryConfig;
                    // 统一：按配置ID创建Provider并调用
                    String effectiveConfigId = session.getSelectedModelConfigId();
                    com.ainovel.server.service.ai.AIModelProvider provider = aiService.createProviderByConfigId(userId, effectiveConfigId);
                    String actualModelName = provider.getModelName();
                    log.debug("记忆模式发送消息: sessionId={}, mode={}, model={}", sessionId, finalMemoryConfig.getMode(), actualModelName);

                    AIChatMessage userMessage = AIChatMessage.builder()
                            .sessionId(sessionId)
                            .userId(userId)
                            .role("user")
                            .content(content)
                            .modelName(actualModelName)
                            .metadata(metadata)
                            .status("SENT")
                            .messageType("TEXT")
                            .createdAt(LocalDateTime.now())
                            .build();

                    return messageRepository.save(userMessage)
                            .flatMap(savedUserMessage -> {
                                session.setMessageCount(session.getMessageCount() + 1);

                                // 使用记忆服务构建请求并调用Provider
                                return buildAIRequestWithMemory(session, actualModelName, content, savedUserMessage.getId(), finalMemoryConfig)
                                        .flatMap(provider::generateContent)
                                        .flatMap(aiResponse -> {
                                            AIChatMessage aiMessage = AIChatMessage.builder()
                                                    .sessionId(sessionId)
                                                    .userId(userId)
                                                    .role("assistant")
                                                    .content(aiResponse.getContent())
                                                    .modelName(actualModelName)
                                                    .metadata(aiResponse.getMetadata() != null ? aiResponse.getMetadata() : Map.of())
                                                    .status("DELIVERED")
                                                    .messageType("TEXT")
                                                    .parentMessageId(savedUserMessage.getId())
                                                    .tokenCount(aiResponse.getMetadata() != null ? (Integer) aiResponse.getMetadata().getOrDefault("tokenCount", 0) : 0)
                                                    .createdAt(LocalDateTime.now())
                                                    .build();

                                            return messageRepository.save(aiMessage)
                                                    .flatMap(savedAiMessage -> {
                                                        session.setLastMessageAt(LocalDateTime.now());
                                                        session.setMessageCount(session.getMessageCount() + 1);
                                                        return chatMemoryService.addMessage(sessionId, savedAiMessage, finalMemoryConfig)
                                                                .then(sessionRepository.save(session))
                                                                .thenReturn(savedAiMessage);
                                                    });
                                        });
                            });
                });
    }

    @Override
    public Flux<AIChatMessage> streamMessageWithMemory(String userId, String sessionId, String content, Map<String, Object> metadata, ChatMemoryConfig memoryConfig) {
        return getSession(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                .flatMap(session -> {
                    // 🚀 检查是否需要自动生成标题
                    if (shouldGenerateTitle(session)) {
                        return generateSessionTitle(session, content)
                                .flatMap(updatedSession -> sessionRepository.save(updatedSession))
                                .onErrorResume(e -> {
                                    log.warn("自动生成会话标题失败，继续使用原标题: sessionId={}, error={}", sessionId, e.getMessage());
                                    return Mono.just(session);
                                });
                    }
                    return Mono.just(session);
                })
                .flatMapMany(session -> {
                    // 如果会话没有记忆配置，使用传入的配置
                    ChatMemoryConfig finalMemoryConfig = session.getMemoryConfig() != null ? session.getMemoryConfig() : memoryConfig;
                    
                    // 统一：不在此层分支公共模型（流式）
                    
                    // 统一：按配置ID创建Provider并调用
                    String effectiveConfigId = session.getSelectedModelConfigId();
                    com.ainovel.server.service.ai.AIModelProvider provider = aiService.createProviderByConfigId(userId, effectiveConfigId);
                    String actualModelName = provider.getModelName();
                    log.debug("记忆模式流式处理: sessionId={}, mode={}, model={}", sessionId, finalMemoryConfig.getMode(), actualModelName);

                    AIChatMessage userMessage = AIChatMessage.builder()
                            .sessionId(sessionId)
                            .userId(userId)
                            .role("user")
                            .content(content)
                            .modelName(actualModelName)
                            .metadata(metadata)
                            .status("SENT")
                            .messageType("TEXT")
                            .createdAt(LocalDateTime.now())
                            .build();

                    return messageRepository.save(userMessage)
                            .flatMapMany(savedUserMessage -> {
                                session.setMessageCount(session.getMessageCount() + 1);
                                return buildAIRequestWithMemory(session, actualModelName, content, savedUserMessage.getId(), finalMemoryConfig)
                                        .flatMapMany(req -> provider.generateContentStream(req)
                                                .map(chunk -> AIChatMessage.builder()
                                                        .sessionId(sessionId)
                                                        .role("assistant")
                                                        .content(chunk)
                                                        .modelName(actualModelName)
                                                        .messageType("STREAM_CHUNK")
                                                        .status("STREAMING")
                                                        .createdAt(LocalDateTime.now())
                                                        .build())
                                                .doOnSubscribe(subscription -> log.info("流式AI服务已被订阅 - sessionId: {}, model: {}", sessionId, actualModelName))
                                                .doOnNext(msg -> log.debug("流式AI生成内容块 - sessionId: {}, length: {}", sessionId, msg.getContent() != null ? msg.getContent().length() : 0))
                                        );
                            });
                });
    }

    @Override
    public Flux<AIChatMessage> getSessionMemoryMessages(String userId, String sessionId, ChatMemoryConfig memoryConfig, int limit) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .switchIfEmpty(Mono.error(new SecurityException("无权访问此会话的消息")))
                .flatMapMany(session -> {
                    ChatMemoryConfig finalMemoryConfig = session.getMemoryConfig() != null ? session.getMemoryConfig() : memoryConfig;
                    return chatMemoryService.getMemoryMessages(sessionId, finalMemoryConfig, limit);
                });
    }

    @Override
    public Mono<AIChatSession> updateSessionMemoryConfig(String userId, String sessionId, ChatMemoryConfig memoryConfig) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                .flatMap(session -> {
                    return chatMemoryService.validateMemoryConfig(memoryConfig)
                            .flatMap(isValid -> {
                                if (!isValid) {
                                    return Mono.error(new IllegalArgumentException("无效的记忆配置"));
                                }
                                
                                session.setMemoryConfig(memoryConfig);
                                session.setUpdatedAt(LocalDateTime.now());
                                
                                log.info("更新会话记忆配置: sessionId={}, mode={}", sessionId, memoryConfig.getMode());
                                return sessionRepository.save(session);
                            });
                });
    }

    @Override
    public Mono<Void> clearSessionMemory(String userId, String sessionId) {
        return sessionRepository.findByUserIdAndSessionId(userId, sessionId)
                .switchIfEmpty(Mono.error(new SecurityException("无权访问此会话")))
                .flatMap(session -> {
                    log.info("清除会话记忆: userId={}, sessionId={}", userId, sessionId);
                    return chatMemoryService.clearMemory(sessionId);
                });
    }

    @Override
    public Flux<String> getSupportedMemoryModes() {
        return chatMemoryService.getSupportedMemoryModes();
    }

    /**
     * 使用记忆策略构建AI请求
     */
    private Mono<AIRequest> buildAIRequestWithMemory(AIChatSession session, String modelName, String newContent, String userMessageId, ChatMemoryConfig memoryConfig) {
        return chatMemoryService.getMemoryMessages(session.getSessionId(), memoryConfig, 100)
                .filter(msg -> !msg.getId().equals(userMessageId)) // 排除当前用户消息
                .collectList()
                .map(history -> {
                    List<AIRequest.Message> messages = new ArrayList<>();
                    
                    // 添加历史消息
                    history.stream()
                            .map(msg -> AIRequest.Message.builder()
                                    .role(msg.getRole())
                                    .content(msg.getContent())
                                    .build())
                            .forEach(messages::add);
                    
                    // 添加当前用户消息
                    messages.add(AIRequest.Message.builder()
                            .role("user")
                            .content(newContent)
                            .build());

                    AIRequest request = new AIRequest();
                    request.setUserId(session.getUserId());
                    request.setModel(modelName);
                    request.setMessages(messages);
                    
                    // 使用可变参数Map，避免后续链路对parameters执行put时报不可变异常
                    Map<String, Object> params = new java.util.HashMap<>();
                    if (session.getMetadata() != null) {
                        params.putAll(session.getMetadata());
                    }
                    request.setTemperature((Double) params.getOrDefault("temperature", 0.7));
                    request.setMaxTokens((Integer) params.getOrDefault("maxTokens", 1024));
                    request.setParameters(params);

                    log.debug("使用记忆策略构建 AIRequest: model={}, messages={}, mode={}", modelName, messages.size(), memoryConfig.getMode());
                    return request;
                });
    }

    // ==================== 🚀 新增：支持UniversalAIRequestDto的方法 ====================

    @Override
    public Mono<AIChatMessage> sendMessage(String userId, String sessionId, String content, UniversalAIRequestDto aiRequest) {
        log.info("发送消息（配置模式） - userId: {}, sessionId: {}, configId: {}", userId, sessionId, aiRequest != null ? aiRequest.getModelConfigId() : "null");
        
        if (aiRequest == null) {
            // 如果没有配置，回退到标准方法
            return sendMessage(userId, sessionId, content, Map.of());
        }
        
        return getSession(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                .flatMap(session -> {
                    // 统一路径：使用 aiService.createProviderByConfigId，公共逻辑在装饰器层处理
                    String modelConfigId = aiRequest.getModelConfigId() != null ? aiRequest.getModelConfigId() : session.getSelectedModelConfigId();
                    return Mono.fromCallable(() -> aiService.createProviderByConfigId(userId, modelConfigId))
                            .flatMap(provider -> {
                                String actualModelName = provider.getModelName();
                                
                                AIChatMessage userMessage = AIChatMessage.builder()
                                        .sessionId(sessionId)
                                        .userId(userId)
                                        .role("user")
                                        .content(content)
                                        .modelName(actualModelName)
                                        .metadata(Map.of())
                                        .status("SENT")
                                        .messageType("TEXT")
                                        .createdAt(LocalDateTime.now())
                                        .build();

                                return messageRepository.save(userMessage)
                                        .flatMap(savedUserMessage -> {
                                            session.setMessageCount(session.getMessageCount() + 1);

                                            // 构建 AIRequest
                                            AIRequest req = new AIRequest();
                                            req.setUserId(userId);
                                            req.setModel(actualModelName);
                                            AIRequest.Message msg = new AIRequest.Message();
                                            msg.setRole("user");
                                            msg.setContent(content);
                                            req.getMessages().add(msg);

                                            return provider.generateContent(req)
                                                    .flatMap(aiResp -> {
                                                        AIChatMessage aiMessage = AIChatMessage.builder()
                                                                .sessionId(sessionId)
                                                                .userId(userId)
                                                                .role("assistant")
                                                                .content(aiResp.getContent())
                                                                .modelName(actualModelName)
                                                                .metadata(Map.of())
                                                                .status("DELIVERED")
                                                                .messageType("TEXT")
                                                                .parentMessageId(savedUserMessage.getId())
                                                                .tokenCount(0)
                                                                .createdAt(LocalDateTime.now())
                                                                .build();

                                                        return messageRepository.save(aiMessage)
                                                                .flatMap(savedAiMessage -> {
                                                                    session.setLastMessageAt(LocalDateTime.now());
                                                                    session.setMessageCount(session.getMessageCount() + 1);
                                                                    return sessionRepository.save(session)
                                                                            .thenReturn(savedAiMessage);
                                                                });
                                                    });
                                        });
                            });
                })
                .doOnSuccess(message -> log.info("配置消息发送完成 - messageId: {}", message.getId()))
                .doOnError(error -> log.error("配置消息发送失败: {}", error.getMessage(), error));
    }

    @Override
    public Flux<AIChatMessage> streamMessage(String userId, String sessionId, String content, UniversalAIRequestDto aiRequest) {
        log.info("流式发送消息（配置模式） - userId: {}, sessionId: {}, configId: {}", userId, sessionId, aiRequest != null ? aiRequest.getModelConfigId() : "null");
        
        if (aiRequest == null) {
            // 如果没有配置，回退到标准方法
            return streamMessage(userId, sessionId, content, Map.of());
        }
        
        return getSession(userId, sessionId)
                .switchIfEmpty(Mono.error(new RuntimeException("会话不存在或无权访问: " + sessionId)))
                // 🚀 先检查是否需要自动生成标题（前10字符）
                .flatMap(session -> {
                    if (shouldGenerateTitle(session)) {
                        return generateSessionTitle(session, content)
                                .flatMap(updated -> sessionRepository.save(updated))
                                .onErrorResume(e -> {
                                    log.warn("自动生成会话标题失败，继续使用原标题: sessionId={}, error={}", sessionId, e.getMessage());
                                    return Mono.just(session);
                                });
                    }
                    return Mono.just(session);
                })
                .flatMapMany(session -> {
                    // 统一路径：使用 aiService.createProviderByConfigId，公共逻辑在装饰器层处理
                    String modelConfigId = aiRequest.getModelConfigId() != null ? aiRequest.getModelConfigId() : session.getSelectedModelConfigId();
                    
                    // 🚀 获取上下文数据（从contextSelections）
                    Mono<String> contextDataMono = getContextDataFromRequest(aiRequest);
                    
                    // 🚀 获取历史消息
                    Mono<List<AIChatMessage>> historyMono = getRecentMessages(sessionId, 10);
                    
                    return Mono.zip(
                            Mono.fromCallable(() -> aiService.createProviderByConfigId(userId, modelConfigId)),
                            contextDataMono,
                            historyMono
                    ).flatMapMany(tuple -> {
                        com.ainovel.server.service.ai.AIModelProvider provider = tuple.getT1();
                        String contextData = tuple.getT2();
                        List<AIChatMessage> historyMessages = tuple.getT3();
                        
                        String actualModelName = provider.getModelName();
                        
                        log.info("📊 聊天上下文信息 - 历史消息数: {}, 上下文数据长度: {}", 
                                historyMessages.size(), contextData != null ? contextData.length() : 0);
                        
                        AIChatMessage userMessage = AIChatMessage.builder()
                                .sessionId(sessionId)
                                .userId(userId)
                                .role("user")
                                .content(content)
                                .modelName(actualModelName)
                                .metadata(Map.of())
                                .status("SENT")
                                .messageType("TEXT")
                                .createdAt(LocalDateTime.now())
                                .build();

                        return messageRepository.save(userMessage)
                                .flatMapMany(savedUserMessage -> {
                                    session.setMessageCount(session.getMessageCount() + 1);

                                    // 🚀 构建完整的消息历史
                                    AIRequest req = new AIRequest();
                                    req.setUserId(userId);
                                    req.setModel(actualModelName);
                                    
                                    // 添加系统消息（包含上下文数据）
                                    if (contextData != null && !contextData.trim().isEmpty()) {
                                        AIRequest.Message systemMsg = new AIRequest.Message();
                                        systemMsg.setRole("system");
                                        systemMsg.setContent("以下是相关的上下文信息，请在回答时参考这些内容：\n\n" + contextData);
                                        req.getMessages().add(systemMsg);
                                        log.info("✅ 已添加系统上下文消息，长度: {}", contextData.length());
                                    }
                                    
                                    // 添加历史消息
                                    for (AIChatMessage historyMsg : historyMessages) {
                                        AIRequest.Message msg = new AIRequest.Message();
                                        msg.setRole(historyMsg.getRole());
                                        msg.setContent(historyMsg.getContent());
                                        req.getMessages().add(msg);
                                    }
                                    
                                    // 添加当前用户消息
                                    AIRequest.Message currentMsg = new AIRequest.Message();
                                    currentMsg.setRole("user");
                                    currentMsg.setContent(content);
                                    req.getMessages().add(currentMsg);
                                    
                                    log.info("📝 最终消息数量: {}, 包含 {} 条历史消息", 
                                            req.getMessages().size(), historyMessages.size());

                                    // 🚀 用于收集完整响应内容
                                    StringBuilder fullContent = new StringBuilder();
                                    
                                    // 🚀 创建保存完整消息的Mono（延迟执行）
                                    Mono<AIChatMessage> saveFullMessageMono = Mono.defer(() -> {
                                        if (fullContent.length() > 0) {
                                            AIChatMessage aiMessage = AIChatMessage.builder()
                                                    .sessionId(sessionId)
                                                    .userId(userId)
                                                    .role("assistant")
                                                    .content(fullContent.toString())
                                                    .modelName(actualModelName)
                                                    .status("SENT")
                                                    .messageType("TEXT")
                                                    .parentMessageId(savedUserMessage.getId())
                                                    .tokenCount(0)
                                                    .createdAt(LocalDateTime.now())
                                                    .build();
                                            log.info("💾 流式传输完成，保存完整AI消息: sessionId={}, length={}", 
                                                    sessionId, fullContent.length());
                                            return messageRepository.save(aiMessage)
                                                    .flatMap(savedMsg -> {
                                                        session.setLastMessageAt(LocalDateTime.now());
                                                        session.setMessageCount(session.getMessageCount() + 1);
                                                        return sessionRepository.save(session).thenReturn(savedMsg);
                                                    });
                                        } else {
                                            log.warn("流式响应为空，不保存AI消息: sessionId={}", sessionId);
                                            session.setLastMessageAt(LocalDateTime.now());
                                            return sessionRepository.save(session).then(Mono.empty());
                                        }
                                    });

                                    return provider.generateContentStream(req)
                                            .map(chunk -> {
                                                // 🚀 累积内容
                                                fullContent.append(chunk);
                                                
                                                return AIChatMessage.builder()
                                                        .sessionId(sessionId)
                                                        .role("assistant")
                                                        .content(chunk)
                                                        .modelName(actualModelName)
                                                        .messageType("STREAM_CHUNK")
                                                        .status("STREAMING")
                                                        .createdAt(LocalDateTime.now())
                                                        .build();
                                            })
                                            .doOnSubscribe(subscription -> {
                                                log.info("流式AI服务已被订阅 - sessionId: {}, model: {}", sessionId, actualModelName);
                                            })
                                            .doOnNext(message -> {
                                                log.debug("流式AI生成内容块 - sessionId: {}, length: {}", sessionId, message.getContent() != null ? message.getContent().length() : 0);
                                            })
                                            .doOnComplete(() -> log.info("✅ 流式传输完成: sessionId={}", sessionId))
                                            .doOnError(e -> log.error("❌ 流式传输过程中出错: sessionId={}, error={}", sessionId, e.getMessage()))
                                            // 🚀 在流结束后拼接保存完整消息的操作
                                            .concatWith(saveFullMessageMono.onErrorResume(e -> {
                                                log.error("❌ 保存完整流式消息时出错: sessionId={}", sessionId, e);
                                                return Mono.empty();
                                            }).flux());
                                });
                    });
                })
                .doOnComplete(() -> log.info("配置流式消息发送完成"))
                .doOnError(error -> log.error("配置流式消息发送失败: {}", error.getMessage(), error));
    }
    
    /**
     * 从UniversalAIRequestDto中获取上下文数据
     */
    private Mono<String> getContextDataFromRequest(UniversalAIRequestDto request) {
        if (request == null || request.getContextSelections() == null || request.getContextSelections().isEmpty()) {
            log.info("没有contextSelections，跳过上下文获取");
            return Mono.just("");
        }
        
        log.info("🔍 开始处理contextSelections，数量: {}", request.getContextSelections().size());
        
        // 使用ContentProviderFactory来处理contextSelections
        List<Mono<String>> contentMonos = new ArrayList<>();
        
        for (UniversalAIRequestDto.ContextSelectionDto selection : request.getContextSelections()) {
            String type = selection.getType();
            String id = selection.getId();
            
            if (type == null || id == null) {
                continue;
            }
            
            // 去掉可能的flat_前缀
            String resolvedId = id.startsWith("flat_") ? id.substring("flat_".length()) : id;
            
            log.info("📖 获取上下文: type={}, id={}", type, resolvedId);
            
            java.util.Optional<com.ainovel.server.service.impl.content.ContentProvider> providerOpt = 
                    contentProviderFactory.getProvider(type.toLowerCase());
            
            if (providerOpt.isPresent()) {
                Mono<String> contentMono = providerOpt.get().getContent(resolvedId, request)
                        .map(result -> {
                            String content = result.getContent();
                            String title = selection.getTitle() != null ? selection.getTitle() : type;
                            return "=== " + title + " ===\n" + content;
                        })
                        .onErrorResume(e -> {
                            log.warn("获取上下文失败: type={}, id={}, error={}", type, resolvedId, e.getMessage());
                            return Mono.just("");
                        });
                contentMonos.add(contentMono);
            } else {
                log.warn("未找到内容提供器: type={}", type);
            }
        }
        
        if (contentMonos.isEmpty()) {
            return Mono.just("");
        }
        
        // 合并所有上下文内容
        return Flux.merge(contentMonos)
                .filter(content -> content != null && !content.trim().isEmpty())
                .collect(java.util.stream.Collectors.joining("\n\n"))
                .doOnNext(context -> log.info("✅ 上下文数据获取成功，长度: {}", context.length()))
                .onErrorResume(e -> {
                    log.error("获取上下文数据失败: {}", e.getMessage(), e);
                    return Mono.just("");
                });
    }
    
    /**
     * 获取最近的N条消息
     */
    private Mono<List<AIChatMessage>> getRecentMessages(String sessionId, int limit) {
        return messageRepository.findBySessionIdOrderByCreatedAtDesc(sessionId, limit)
                .collectList()
                .map(messages -> {
                    // 反转列表，使其按时间正序排列
                    java.util.Collections.reverse(messages);
                    return messages;
                })
                .doOnNext(messages -> log.info("📜 获取到 {} 条历史消息", messages.size()));
    }



}
