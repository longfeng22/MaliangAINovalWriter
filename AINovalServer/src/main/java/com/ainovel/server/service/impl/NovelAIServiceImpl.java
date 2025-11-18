package com.ainovel.server.service.impl;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import com.ainovel.server.service.ai.strategy.LegacyAISettingGenerationStrategyFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;
import org.jasypt.encryption.StringEncryptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

import com.ainovel.server.common.util.RichTextUtil;
import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.AIResponse;
import com.ainovel.server.domain.model.NovelSettingItem;
import com.ainovel.server.domain.model.SettingType;
import com.ainovel.server.domain.model.UserAIModelConfig;
import com.ainovel.server.service.AIService;
import com.ainovel.server.service.KnowledgeService;
import com.ainovel.server.service.NovelAIService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.EnhancedUserPromptService;
import com.ainovel.server.service.SceneService;
import com.ainovel.server.service.UserAIModelConfigService;
import com.ainovel.server.service.UserPromptService;
// import com.ainovel.server.service.UserService;
import com.ainovel.server.service.ai.AIModelProvider;
import com.ainovel.server.web.dto.GenerateSceneFromSummaryRequest;
import com.ainovel.server.web.dto.GenerateSceneFromSummaryResponse;
import com.ainovel.server.web.dto.OutlineGenerationChunk;
import com.ainovel.server.web.dto.SummarizeSceneRequest;
import com.ainovel.server.web.dto.SummarizeSceneResponse;
import com.ainovel.server.web.dto.request.GenerateSettingsRequest;
import com.fasterxml.jackson.databind.ObjectMapper;

import dev.langchain4j.data.segment.TextSegment;
import dev.langchain4j.rag.content.Content;
import dev.langchain4j.rag.content.retriever.ContentRetriever;
import dev.langchain4j.rag.query.Query;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

// 添加策略相关导入
import com.ainovel.server.service.ai.strategy.SettingGenerationStrategy;

import com.ainovel.server.service.NovelSettingService;

/**
 * 小说AI服务实现类 专门处理与小说创作相关的AI功能
 */
@Slf4j
@Service
public class NovelAIServiceImpl implements NovelAIService {

    private final AIService aiService;
    private final KnowledgeService knowledgeService;
    private final NovelService novelService;
    private final EnhancedUserPromptService promptService;
    // private final UserService userService;
    private final SceneService sceneService;
    private final StringEncryptor encryptor; // Added
    private final ObjectMapper objectMapper; // Added

    // ❌ 已移除Provider缓存 - 修复用户数据串流问题
    // 原因：共享的StreamingChatLanguageModel实例在并发场景下会导致响应混乱
    // private final Map<String, Map<String, AIModelProvider>> userProviders = new ConcurrentHashMap<>();

    @Autowired
    private ContentRetriever contentRetriever;

    // 已暂未使用，避免未使用警告
    // @Autowired
    // private NovelRagAssistant novelRagAssistant;

    // @Autowired
    // private RagService ragService;

    @Autowired
    private UserPromptService userPromptService;

    @Autowired
    private UserAIModelConfigService userAIModelConfigService;

    @Autowired
    private NovelSettingService novelSettingService; // 需要添加这个依赖注入

    

    @Autowired
    public NovelAIServiceImpl(
            @Qualifier("AIServiceImpl") AIService aiService,
            KnowledgeService knowledgeService,
            NovelService novelService,
            EnhancedUserPromptService promptService,
            // UserService userService,
            SceneService sceneService,
            StringEncryptor encryptor,
            ObjectMapper objectMapper) { // Added
        this.aiService = aiService;
        this.knowledgeService = knowledgeService;
        this.novelService = novelService;
        this.promptService = promptService;
        // this.userService = userService;
        this.sceneService = sceneService;
        this.encryptor = encryptor;
        this.objectMapper = objectMapper; // Added
    }

    /**
     * 生成小说设定项
     * 
     * 设计模式：
     * 1. 策略模式(Strategy Pattern) - 通过SettingGenerationStrategy接口定义不同的生成策略
     *    - StructuredOutputStrategy: 针对支持结构化输出的模型特别优化
     *    - PromptBasedStrategy: 通用提示词策略，适用于各种模型
     * 
     * 2. 工厂方法(Factory Method) - 使用SettingGenerationStrategyFactory根据模型类型动态选择策略
     * 
     * 3. 适配器模式(Adapter Pattern) - 将不同类型的AI模型接口适配为统一的处理流程
     * 
     * 高可用设计：
     * - 完善的错误处理和回退机制，确保在各种异常情况下仍能给出合理响应
     * - 使用Reactive编程保证异步操作的高效和资源利用
     * - 策略降级：当首选策略失败时自动回退到备选策略
     * 
     * 高拓展性设计：
     * - 可以轻松添加新的生成策略以支持更多模型类型
     * - 解耦的设计使不同部分可以独立升级和修改
     * - 统一的数据模型转换确保输出一致性
     * 
     * @param novelId 小说ID
     * @param userId 用户ID
     * @param requestParams 生成设定的请求参数，包含范围、类型和数量等
     * @return 生成的小说设定项列表
     */
    @Override
    public Mono<List<NovelSettingItem>> generateNovelSettings(String novelId, String userId, GenerateSettingsRequest requestParams) {
        log.info("AI生成小说设定, novelId: {}, userId: {}, startChapter: {}, endChapter: {}, types: {}, modelConfigId: {}",
                novelId, userId, requestParams.getStartChapterId(), requestParams.getEndChapterId(), requestParams.getSettingTypes(), requestParams.getModelConfigId());

        // 验证设定类型并转换为字符串用于提示词
        List<String> validRequestedEnumValues = requestParams.getSettingTypes().stream()
            .map(typeStr -> {
                try {
                    // 尝试转换为枚举来验证，然后获取其字符串值
                    return SettingType.fromValue(typeStr).getValue();
                } catch (IllegalArgumentException e) {
                    log.warn("无效的设定类型被忽略: {}", typeStr);
                    return null; // 将被过滤掉
                }
            })
            .filter(Objects::nonNull)
            .distinct() // 确保类型唯一
            .collect(Collectors.toList());

        if (validRequestedEnumValues.isEmpty()) {
            log.error("未提供有效的设定类型, novelId: {}. 原始请求: {}", novelId, requestParams.getSettingTypes());
            return Mono.error(new IllegalArgumentException("未提供有效的设定类型，请检查类型值。"));
        }

        // 1. 使用前端传递的modelConfigId创建AI模型Provider
        Mono<AIModelProvider> providerMono = getAIModelProviderByConfigId(userId, requestParams.getModelConfigId())
            .switchIfEmpty(Mono.error(new RuntimeException("无法根据提供的modelConfigId创建AI模型提供商。")));

        // 2. 获取章节内容 - 确保即使没有内容也返回空字符串而不是Empty信号
        Mono<String> chapterContextMono = novelService.getChapterRangeContext(
                novelId, requestParams.getStartChapterId(), requestParams.getEndChapterId())
                .switchIfEmpty(Mono.just("")) // 避免Empty信号导致后续zip操作失败
                .subscribeOn(Schedulers.boundedElastic());
        
        // 3. 查询当前小说的已有设定（从数据库查询，而不是从请求参数获取）
        Mono<List<NovelSettingItem>> existingSettingsMono = novelSettingService
                .getNovelSettingItems(novelId, null, null, null, null, null, null)
                .collectList()
                .subscribeOn(Schedulers.boundedElastic());
        
        // 4. 获取策略工厂 (使用Spring的依赖注入)
        LegacyAISettingGenerationStrategyFactory strategyFactory = new LegacyAISettingGenerationStrategyFactory(promptService, objectMapper);

        // 5. 结合模型提供商、章节内容和已有设定，生成新设定
        return Mono.zip(providerMono, chapterContextMono, existingSettingsMono)
            .flatMap(tuple -> {
                AIModelProvider aiModelProvider = tuple.getT1();
                String chapterContext = tuple.getT2();
                List<NovelSettingItem> existingSettings = tuple.getT3();

                if (chapterContext == null || chapterContext.isEmpty()) {
                    log.warn("在章节范围 {} 到 {} 中未找到内容，返回空列表", 
                            requestParams.getStartChapterId(), requestParams.getEndChapterId());
                    return Mono.just(Collections.<NovelSettingItem>emptyList());
                }

                // 使用策略工厂获取生成策略
                SettingGenerationStrategy strategy = strategyFactory.createStrategy(aiModelProvider);
                
                // 构建已有设定上下文
                String existingSettingsContext = buildExistingSettingsContext(existingSettings);
                
                // 构建增强的用户指令，包含已有设定信息
                String enhancedInstructions = requestParams.getAdditionalInstructions();
                if (!existingSettingsContext.isEmpty()) {
                    enhancedInstructions = existingSettingsContext + "\n\n" + 
                        (requestParams.getAdditionalInstructions() != null ? requestParams.getAdditionalInstructions() : "");
                }
                
                // 使用策略生成设定
                return strategy.generateSettings(
                    novelId, 
                    userId, 
                    chapterContext,
                    validRequestedEnumValues,
                    requestParams.getMaxSettingsPerType(),
                    enhancedInstructions,
                    aiModelProvider
                );
            })
            .onErrorResume(e -> {
                log.error("生成设定过程中出现严重错误, novelId {}: {}", novelId, e.getMessage(), e);
                return Mono.error(new RuntimeException("生成小说设定失败: " + e.getMessage(), e));
            });
    }
    
    /**
     * 构建已有设定的上下文字符串
     * 从数据库查询到的设定列表转换为AI可理解的上下文
     */
    private String buildExistingSettingsContext(List<NovelSettingItem> existingSettings) {
        if (existingSettings == null || existingSettings.isEmpty()) {
            return "";
        }
        
        StringBuilder context = new StringBuilder();
        context.append("【当前已有设定】\n");
        context.append("请基于以下已有设定进行生成，如果新生成的设定与已有设定有关联，请填充正确的父设定ID（parentId）：\n\n");
        
        for (NovelSettingItem setting : existingSettings) {
            context.append("- ID: ").append(setting.getId() != null ? setting.getId() : "无").append("\n");
            context.append("  名称: ").append(setting.getName() != null ? setting.getName() : "无").append("\n");
            context.append("  类型: ").append(setting.getType() != null ? setting.getType() : "无").append("\n");
            if (setting.getParentId() != null && !setting.getParentId().isEmpty()) {
                context.append("  父设定ID: ").append(setting.getParentId()).append("\n");
            }
            if (setting.getDescription() != null && !setting.getDescription().isEmpty()) {
                context.append("  描述: ").append(setting.getDescription()).append("\n");
            }
            context.append("\n");
        }
        
        log.info("构建已有设定上下文，包含 {} 个设定项", existingSettings.size());
        return context.toString();
    }

    @Override
    public Mono<AIResponse> generateNovelContent(AIRequest request) {
        return enrichRequestWithContext(request)
                .flatMap(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMap(provider -> {
                                // 添加请求日志
                                log.info("开始向AI模型发送内容生成请求，用户ID: {}, 模型: {}",
                                        enrichedRequest.getUserId(), enrichedRequest.getModel());

                                // 直接使用业务请求调用提供商
                                return provider.generateContent(enrichedRequest)
                                        .doOnCancel(() -> {
                                            log.info("客户端取消了连接，但AI生成会在后台继续完成, 用户: {}, 模型: {}",
                                                    enrichedRequest.getUserId(), enrichedRequest.getModel());
                                        })
                                        .doOnSuccess(resp -> {
                                            log.info("AI内容生成成功完成，用户ID: {}, 模型: {}",
                                                    enrichedRequest.getUserId(), enrichedRequest.getModel());
                                        })
                                        .timeout(Duration.ofSeconds(600)) // 添加超时设置
                                        .onErrorResume(e -> {
                                            log.error("AI内容生成出错: {}", e.getMessage(), e);
                                            return Mono.error(new RuntimeException("AI内容生成失败: " + e.getMessage(), e));
                                        });
                            })
                            .retry(3); // 添加重试逻辑
                });
    }

    @Override
    public Flux<String> generateNovelContentStream(AIRequest request) {
        return enrichRequestWithContext(request)
                .flatMapMany(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMapMany(provider -> {
                                // 添加请求日志
                                log.info("开始向AI模型发送流式内容生成请求，用户ID: {}, 模型: {}",
                                        enrichedRequest.getUserId(), enrichedRequest.getModel());

                                // 记录开始时间和最后活动时间
                                final AtomicLong startTime = new AtomicLong(System.currentTimeMillis());
                                final AtomicLong lastActivityTime = new AtomicLong(System.currentTimeMillis());

                                // 直接使用业务请求调用提供商
                                Flux<String> upstream = provider.generateContentStream(enrichedRequest)
                                        .doOnSubscribe(sub -> {
                                            log.info("流式生成已订阅，用户ID: {}, 模型: {}",
                                                    enrichedRequest.getUserId(), enrichedRequest.getModel());
                                        })
                                        .doOnNext(chunk -> {
                                            // 只为非心跳消息更新活动时间
                                            if (!"heartbeat".equals(chunk)) {
                                                lastActivityTime.set(System.currentTimeMillis());
                                            }
                                        })
                                        .doOnComplete(() -> {
                                            long duration = System.currentTimeMillis() - startTime.get();
                                            long idleMs = System.currentTimeMillis() - lastActivityTime.get();
                                            log.info("流式内容生成成功完成，耗时: {}ms，最后空闲: {}ms，用户ID: {}, 模型: {}",
                                                    duration, idleMs, enrichedRequest.getUserId(), enrichedRequest.getModel());
                                        })
                                        .doOnCancel(() -> {
                                            log.info("流式生成被取消，但模型会在后台继续生成，用户ID: {}, 模型: {}",
                                                    enrichedRequest.getUserId(), enrichedRequest.getModel());
                                        })
                                        .timeout(Duration.ofSeconds(600)) // 添加超时设置
                                        .onErrorResume(e -> {
                                            log.error("流式内容生成出错: {}", e.getMessage(), e);
                                            return Flux.just("生成出错: " + e.getMessage());
                                        });
                                // 共享上游，避免多订阅触发重复请求
                                return upstream.publish().refCount(1);
                            });
                });
    }

    @Override
    public Mono<AIResponse> getWritingSuggestion(String novelId, String sceneId, String suggestionType) {
        return createSuggestionRequest(novelId, sceneId, suggestionType)
                .flatMap(this::enrichRequestWithContext)
                .flatMap(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMap(provider -> {
                                // 直接使用业务请求调用提供商
                                return provider.generateContent(enrichedRequest)
                                        .doOnError(e -> log.error("获取写作建议时出错: {}", e.getMessage(), e));
                            });
                });
    }

    @Override
    public Flux<String> getWritingSuggestionStream(String novelId, String sceneId, String suggestionType) {
        return createSuggestionRequest(novelId, sceneId, suggestionType)
                .flatMapMany(request -> enrichRequestWithContext(request)
                .flatMapMany(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMapMany(provider -> {
                                // 直接使用业务请求调用提供商
                                return provider.generateContentStream(enrichedRequest);
                            });
                }));
    }

    @Override
    public Mono<AIResponse> reviseContent(String novelId, String sceneId, String content, String instruction) {
        return createRevisionRequest(novelId, sceneId, content, instruction)
                .flatMap(this::enrichRequestWithContext)
                .flatMap(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMap(provider -> {
                                // 直接使用业务请求调用提供商
                                return provider.generateContent(enrichedRequest)
                                        .doOnError(e -> log.error("修改内容时出错: {}", e.getMessage(), e));
                            });
                });
    }

    @Override
    public Flux<String> reviseContentStream(String novelId, String sceneId, String content, String instruction) {
        return createRevisionRequest(novelId, sceneId, content, instruction)
                .flatMapMany(request -> enrichRequestWithContext(request)
                .flatMapMany(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMapMany(provider -> {
                                // 直接使用业务请求调用提供商
                                return provider.generateContentStream(enrichedRequest);
                            });
                }));
    }

    @Override
    public Mono<AIResponse> generateNextOutlines(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance) {
        log.info("为小说 {} 生成下一剧情大纲选项", novelId);

        // 设置默认值
        int optionsCount = numberOfOptions != null ? numberOfOptions : 3;
        String guidance = authorGuidance != null ? authorGuidance : "";

        return createNextOutlinesGenerationRequest(novelId, currentContext, optionsCount, guidance)
                .flatMap(this::enrichRequestWithContext)
                .flatMap(enrichedRequest -> {
                    // 获取AI模型提供商并直接调用
                    return getAIModelProvider(enrichedRequest.getUserId(), enrichedRequest.getModel())
                            .flatMap(provider -> {
                                // 直接使用业务请求调用提供商
                                return provider.generateContent(enrichedRequest);
                            });
                });
    }

    @Override
    public Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance) {
        log.info("为小说 {} 流式生成下一剧情大纲选项 (基于上下文)", novelId);

        // 使用默认用户配置
        return getCurrentUserId()
            .flatMap(userId -> userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                .map(config -> config.getId())
                .defaultIfEmpty("default")
                .map(configId -> List.of(configId)))
            .flatMapMany(defaultConfigIds -> 
                generateNextOutlinesStream(novelId, currentContext, numberOfOptions, authorGuidance, defaultConfigIds));
    }

    @Override
    public Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String startChapterId, String endChapterId, Integer numberOfOptions, String authorGuidance) {
        log.info("为小说 {} 流式生成下一剧情大纲选项 (指定章节范围), 起始章节: {}, 结束章节: {}",
                novelId, startChapterId, endChapterId);

        // 使用默认用户配置
        return getCurrentUserId()
            .flatMap(userId -> userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                .map(config -> config.getId())
                .defaultIfEmpty("default")
                .map(configId -> List.of(configId)))
            .flatMapMany(defaultConfigIds -> 
                generateNextOutlinesStream(novelId, startChapterId, endChapterId, numberOfOptions, authorGuidance, defaultConfigIds));
    }

    @Override
    public Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String currentContext, Integer numberOfOptions, String authorGuidance, List<String> selectedConfigIds) {
        log.info("为小说 {} 流式生成下一剧情大纲选项 (基于上下文), 选定的配置IDs: {}", novelId, selectedConfigIds);

        // 设置默认值
        final int optionsCount = numberOfOptions != null ? numberOfOptions : 3;
        final String guidance = authorGuidance != null ? authorGuidance : "";
        final List<String> configIds = (selectedConfigIds != null && !selectedConfigIds.isEmpty()) ? selectedConfigIds : List.of("default");

        // 直接使用传入的 currentContext
        String contextDescription = currentContext != null ? currentContext : "";

        return getCurrentUserId()
            .flatMapMany(userId ->
                Flux.range(0, optionsCount)
                    .flatMap(index -> {
                        // 选择对应索引的配置ID，如果索引超出列表长度则循环使用
                        String configId = configIds.get(index % configIds.size());
                        // 对于基于上下文的版本，start/end chapterId 为 null
                        return generateSingleOutlineOptionStream(userId, novelId, contextDescription, guidance, index, null, null, configId);
                    })
                    .subscribeOn(Schedulers.parallel())
            );
    }

    @Override
    public Flux<OutlineGenerationChunk> generateNextOutlinesStream(String novelId, String startChapterId, String endChapterId, Integer numberOfOptions, String authorGuidance, List<String> selectedConfigIds) {
        log.info("为小说 {} 流式生成下一剧情大纲选项 (指定章节范围), 起始章节: {}, 结束章节: {}, 选定的配置IDs: {}",
                novelId, startChapterId, endChapterId, selectedConfigIds);

        // 设置默认值
        final int optionsCount = numberOfOptions != null ? numberOfOptions : 3;
        final String guidance = authorGuidance != null ? authorGuidance : "";
        final List<String> configIds = (selectedConfigIds != null && !selectedConfigIds.isEmpty()) ? selectedConfigIds : List.of("default");

        // 创建上下文描述 (异步)
        return buildContextDescription(novelId, startChapterId, endChapterId)
            .flatMapMany(contextDescription -> // 使用 flatMapMany 处理异步上下文
                getCurrentUserId()
                    .flatMapMany(userId ->
                        Flux.range(0, optionsCount)
                            .flatMap(index -> {
                                // 选择对应索引的配置ID，如果索引超出列表长度则循环使用
                                String configId = configIds.get(index % configIds.size());
                                // 将获取到的 contextDescription 传递给单选项生成流
                                return generateSingleOutlineOptionStream(userId, novelId, contextDescription, guidance, index, startChapterId, endChapterId, configId);
                            })
                            .subscribeOn(Schedulers.parallel()) // 注意：subscribeOn 放在内层 Flux 上可能更合适
                    )
            )
             // 将 subscribeOn 移到外层，确保上下文构建也在合适的线程上执行
            .subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Flux<OutlineGenerationChunk> regenerateSingleOutlineStream(String novelId, String optionId, String userId, String modelConfigId, String regenerateHint,
                                                                    String originalStartChapterId, String originalEndChapterId, String originalAuthorGuidance) {
        log.info("重新生成单个剧情大纲: novelId={}, optionId={}, userId={}, modelConfigId={}, startChap={}, endChap={}, origGuidanceLen={}",
                novelId, optionId, userId, modelConfigId, originalStartChapterId, originalEndChapterId, originalAuthorGuidance != null ? originalAuthorGuidance.length() : 0);

        return Mono.defer(() -> {
            String hint = regenerateHint != null ? regenerateHint : "";

            // 基于获取到的原始上下文信息，重新构建上下文描述 (异步)
            return buildContextDescription(novelId, originalStartChapterId, originalEndChapterId)
                .map(contextDescription -> {
                     // 合并原始引导和新的提示
                     String effectiveGuidance = (originalAuthorGuidance != null ? originalAuthorGuidance : "")
                                                + (hint.isEmpty() ? "" : "\\n\\n重新生成提示: " + hint);
                     // 返回包含上下文和最终引导的 Pair 或自定义对象
                     return Map.entry(contextDescription, effectiveGuidance);
                });
        })
        .flatMapMany(contextAndGuidance -> {
            String contextDescription = contextAndGuidance.getKey();
            String finalGuidance = contextAndGuidance.getValue();
            int regenerateIndex = 0; // 重新生成总是对应一个选项，索引为0

            // 调用单选项生成逻辑
            return generateSingleOutlineOptionStream(userId, novelId, contextDescription, finalGuidance, regenerateIndex, originalStartChapterId, originalEndChapterId, modelConfigId)
                // 确保使用传入的 optionId 而不是生成新的
                .map(chunk -> {
                    // 替换 UUID 生成的 optionId 为前端传入的 optionId
                    return new OutlineGenerationChunk(
                        optionId,
                        chunk.getOptionTitle(),
                        chunk.getTextChunk(),
                        chunk.isFinalChunk(),
                        chunk.getError()
                    );
                });
            }
        )
        .subscribeOn(Schedulers.boundedElastic()); // 确保数据库查询和上下文构建在 BoundedElastic 上
    }

    /**
     * 构建章节范围的上下文描述 (返回 Mono<String>)
     */
    private Mono<String> buildContextDescription(String novelId, String startChapterId, String endChapterId) {
        // 实际实现应该从数据库获取章节内容或摘要
        return getNovelService().findNovelById(novelId)
            .flatMap(novel -> {
                if (startChapterId == null && endChapterId == null) {
                    // 如果没有指定章节范围，获取全部章节摘要
                    return getChapterSummariesAll(novelId, novel.getTitle());
                } else if (startChapterId != null && endChapterId != null) {
                    // 获取指定范围的章节摘要
                    return getChapterSummariesBetween(novelId, novel.getTitle(), startChapterId, endChapterId);
                } else if (startChapterId != null) {
                    // 从指定章节开始到结尾的摘要
                    return getChapterSummariesFrom(novelId, novel.getTitle(), startChapterId);
                } else { // endChapterId != null
                    // 从开头到指定章节的摘要
                    return getChapterSummariesUntil(novelId, novel.getTitle(), endChapterId);
                }
            })
            .onErrorResume(e -> {
                log.error("获取章节上下文描述出错 for novel {}: {}", novelId, e.getMessage(), e);
                // 返回一个通用的、不包含具体内容的上下文描述
                return Mono.just(String.format("基于小说 ID %s 的内容 (获取详细上下文失败)", novelId));
            })
            // 如果 findNovelById 返回 empty，也提供一个默认值
            .switchIfEmpty(Mono.fromSupplier(() -> {
                 log.warn("无法找到小说 {} 来构建上下文描述", novelId);
                 return String.format("基于小说 ID %s 的内容 (未找到小说)", novelId);
            }));
    }

    /**
     * 获取指定章节范围内的摘要 (返回 Mono<String>)
     */
    private Mono<String> getChapterSummariesBetween(String novelId, String novelTitle, String startChapterId, String endChapterId) {

        log.debug("获取小说 \'{}\' ({}) 从章节 {} 到 {} 的摘要", novelTitle, novelId, startChapterId, endChapterId);
        // 示例：调用 novelService (假设存在此方法)
        return novelService.getChapterRangeSummaries(novelId, startChapterId, endChapterId)
                .map(summaries -> {
                    if (summaries == null || summaries.isEmpty()) {
                        return String.format("基于小说《%s》从章节 %s 到章节 %s 的内容 (无摘要信息)", novelTitle, startChapterId, endChapterId);
                    }
                    return String.format("基于小说《%s》从章节 %s 到章节 %s 的内容:\\n%s", novelTitle, startChapterId, endChapterId, summaries);
                })
                .defaultIfEmpty(String.format("基于小说《%s》从章节 %s 到章节 %s 的内容 (无摘要信息)", novelTitle, startChapterId, endChapterId));
    }

    /**
     * 获取从指定章节开始到结尾的摘要 (返回 Mono<String>)
     */
    private Mono<String> getChapterSummariesFrom(String novelId, String novelTitle, String startChapterId) {

        log.debug("获取小说 \'{}\' ({}) 从章节 {} 开始的摘要", novelTitle, novelId, startChapterId);
        // 示例：调用 novelService (假设存在此方法)
         return novelService.getChapterRangeSummaries(novelId, startChapterId, null) // 假设 null 表示到结尾
                .map(summaries -> {
                    if (summaries == null || summaries.isEmpty()) {
                        return String.format("基于小说《%s》从章节 %s 开始的内容 (无摘要信息)", novelTitle, startChapterId);
                    }
                    return String.format("基于小说《%s》从章节 %s 开始的内容:\\n%s", novelTitle, startChapterId, summaries);
                })
                .defaultIfEmpty(String.format("基于小说《%s》从章节 %s 开始的内容 (无摘要信息)", novelTitle, startChapterId));
    }

    /**
     * 获取从开始到指定章节的摘要 (返回 Mono<String>)
     */
    private Mono<String> getChapterSummariesUntil(String novelId, String novelTitle, String endChapterId) {

        log.debug("获取小说 \'{}\' ({}) 到章节 {} 为止的摘要", novelTitle, novelId, endChapterId);
        // 示例：调用 novelService (假设存在此方法)
         return novelService.getChapterRangeSummaries(novelId, null, endChapterId) // 假设 null 表示从开头
                .map(summaries -> {
                    if (summaries == null || summaries.isEmpty()) {
                        return String.format("基于小说《%s》直到章节 %s 的内容 (无摘要信息)", novelTitle, endChapterId);
                    }
                    return String.format("基于小说《%s》直到章节 %s 的内容:\\n%s", novelTitle, endChapterId, summaries);
                })
                .defaultIfEmpty(String.format("基于小说《%s》直到章节 %s 的内容 (无摘要信息)", novelTitle, endChapterId));
    }

     /**
     * 获取所有章节的摘要 (返回 Mono<String>)
     */
    private Mono<String> getChapterSummariesAll(String novelId, String novelTitle) {

        log.debug("获取小说 \'{}\' ({}) 的所有章节摘要", novelTitle, novelId);
        // 示例：调用 novelService (假设存在此方法)
        return novelService.getChapterRangeSummaries(novelId, null, null) // 假设 null, null 表示全部
                .map(summaries -> {
                    if (summaries == null || summaries.isEmpty()) {
                        return String.format("基于小说《%s》的全部内容 (无摘要信息)", novelTitle);
                    }
                    return String.format("基于小说《%s》的全部内容:\\n%s", novelTitle, summaries);
                })
                .defaultIfEmpty(String.format("基于小说《%s》的全部内容 (无摘要信息)", novelTitle));
    }

    /**
     * 生成单个剧情大纲选项的流 (核心并发逻辑)
     * 此方法重载用于处理基于章节范围的请求
     */
    private Flux<OutlineGenerationChunk> generateSingleOutlineOptionStream(
        String userId, String novelId, String contextDescription, String authorGuidance, 
        int optionIndex, String startChapterId, String endChapterId, String configId) {

        String optionId = UUID.randomUUID().toString();
        log.info("开始为小说 {} 生成第 {} 个剧情选项，选项ID: {}, 使用配置ID: {}", 
                novelId, optionIndex + 1, optionId, configId);

        return createSingleOutlineGenerationRequest(userId, novelId, contextDescription, authorGuidance, startChapterId, endChapterId)
            .flatMap(request -> enrichRequestWithContext(request))
            .flatMapMany(enrichedRequest ->
                getAIModelProviderByConfigId(userId, configId)
                    .flatMapMany(provider ->
                        processProviderStream(provider, enrichedRequest, optionId, optionIndex)
                    )
                    .onErrorResume(e -> {
                        log.error("为选项 {} (选项ID: {}) 生成时出错: {}", optionIndex + 1, optionId, e.getMessage(), e);
                        return Flux.just(new OutlineGenerationChunk(optionId, "错误", "生成失败: " + e.getMessage(), true, e.getMessage()));
                    })
            );
    }
    
    /**
     * 生成单个剧情大纲选项的流 (核心并发逻辑)
     * 此方法重载用于处理基于普通上下文的请求
     */
    private Flux<OutlineGenerationChunk> generateSingleOutlineOptionStream(
        String userId, String novelId, String currentContext, String authorGuidance, int optionIndex, String configId) {

        String optionId = UUID.randomUUID().toString();
        log.info("开始为小说 {} 生成第 {} 个剧情选项 (基于上下文)，选项ID: {}, 使用配置ID: {}", 
                novelId, optionIndex + 1, optionId, configId);

        return createSingleOutlineGenerationRequest(userId, novelId, currentContext, authorGuidance)
            //.flatMap(request -> enrichRequestWithContext(request))
            .flatMapMany(enrichedRequest ->
                getAIModelProviderByConfigId(userId, configId)
                    .flatMapMany(provider ->
                        processProviderStream(provider, enrichedRequest, optionId, optionIndex)
                    )
                    .onErrorResume(e -> {
                        log.error("为选项 {} (选项ID: {}) 生成时出错: {}", optionIndex + 1, optionId, e.getMessage(), e);
                        return Flux.just(new OutlineGenerationChunk(optionId, "错误", "生成失败: " + e.getMessage(), true, e.getMessage()));
                    })
            );
    }

    /**
     * 处理来自 AI Provider 的流，提取标题并包装成 OutlineGenerationChunk
     */
    private Flux<OutlineGenerationChunk> processProviderStream(AIModelProvider provider, AIRequest request, String optionId, int optionIndex) {
        AtomicReference<String> extractedTitle = new AtomicReference<>(null);
        AtomicBoolean titleExtracted = new AtomicBoolean(false);
        StringBuilder buffer = new StringBuilder();
        final String titlePrefix = "TITLE:";
        final String contentPrefix = "CONTENT:";

        return provider.generateContentStream(request)
            .map(String::trim) // 去除首尾空格
            .filter(chunk -> !chunk.isEmpty() && !"heartbeat".equalsIgnoreCase(chunk)) // 过滤空或心跳
            .concatMap(chunk -> { // 使用 concatMap 保证顺序处理，处理标题提取
                if (!titleExtracted.get()) {
                    buffer.append(chunk);
                    String bufferedContent = buffer.toString();
                    int titleStartIndex = bufferedContent.indexOf(titlePrefix);
                    int contentStartIndex = bufferedContent.indexOf(contentPrefix);

                    if (titleStartIndex != -1 && contentStartIndex != -1 && contentStartIndex > titleStartIndex) {
                        // 提取标题
                        String title = bufferedContent.substring(titleStartIndex + titlePrefix.length(), contentStartIndex).trim();
                        extractedTitle.set(title);
                        titleExtracted.set(true);
                        log.info("选项 {} (选项ID: {}) 提取到标题: {}", optionIndex + 1, optionId, title);

                        // 清空 buffer 并处理 content 部分
                        String remainingContent = bufferedContent.substring(contentStartIndex + contentPrefix.length()).trim();
                        buffer.setLength(0); // 清空 buffer
                        if (!remainingContent.isEmpty()) {
                             // 返回标题后的第一个内容块
                            return Flux.just(new OutlineGenerationChunk(optionId, title, remainingContent, false, null));
                        } else {
                            // 如果 content 部分为空，则跳过，等待下一个 chunk
                             return Flux.empty();
                        }
                    } else if (bufferedContent.length() > 200) { // 如果缓存超过一定长度还没找到标题格式，则认为无标题
                        log.warn("选项 {} (选项ID: {}) 未能按预期格式提取标题，将使用默认标题", optionIndex + 1, optionId);
                        extractedTitle.set("剧情选项 " + (optionIndex + 1)); // 使用默认标题
                        titleExtracted.set(true);
                        String content = buffer.toString(); // 将整个 buffer 作为内容
                        buffer.setLength(0);
                        return Flux.just(new OutlineGenerationChunk(optionId, extractedTitle.get(), content, false, null));
                    } else {
                        // 继续缓冲，等待更多内容以提取标题
                        return Flux.empty();
                    }
                } else {
                    // 标题已提取，直接发送内容块
                    return Flux.just(new OutlineGenerationChunk(optionId, extractedTitle.get(), chunk, false, null));
                }
            })
            .concatWith(Mono.fromCallable(() -> { // 在流末尾添加 final chunk
                 log.info("选项 {} (选项ID: {}) 生成完成", optionIndex + 1, optionId);
                 // 确保即使标题提取失败，也有默认标题
                String finalTitle = titleExtracted.get() ? extractedTitle.get() : ("剧情选项 " + (optionIndex + 1));
                if (!titleExtracted.get() && buffer.length() > 0) {
                     // 如果标题提取失败，且 buffer 中有内容，需要发送最后一个 chunk
                     return new OutlineGenerationChunk(optionId, finalTitle, buffer.toString(), true, null);
                } else if (!titleExtracted.get() && buffer.length() == 0) {
                    // 标题提取失败且buffer为空，发送一个空的final chunk
                     return new OutlineGenerationChunk(optionId, finalTitle, "", true, null);
                } else {
                    // 正常结束，发送空的 final chunk
                    return new OutlineGenerationChunk(optionId, finalTitle, "", true, null);
                }
            }))
            .timeout(Duration.ofSeconds(600)) // 添加超时
            .doOnError(e -> log.error("处理选项 {} (选项ID: {}) 的流时出错: {}", optionIndex + 1, optionId, e.getMessage(), e))
            .onErrorResume(e -> { // 将流处理错误包装成 error chunk
                String errorTitle = extractedTitle.get() != null ? extractedTitle.get() : ("错误 - 选项 " + (optionIndex + 1));
                return Flux.just(new OutlineGenerationChunk(optionId, errorTitle, "处理流时出错: " + e.getMessage(), true, e.getMessage()));
            });
    }

    /**
     * 创建单个下一剧情大纲生成请求 (用于并发调用)
     */
    private Mono<AIRequest> createSingleOutlineGenerationRequest(String userId, String novelId, String context, String authorGuidance, String startChapterId, String endChapterId) {
        return promptService.getSingleOutlineGenerationPrompt()
                 .map(promptTemplate -> {
                     String prompt = promptTemplate
                             .replace("{{context}}", context)
                             .replace("{{authorGuidance}}", authorGuidance.isEmpty() ? "" : "作者引导：" + authorGuidance);

                    AIRequest request = new AIRequest();
                     request.setUserId(userId);
                     request.setNovelId(novelId);
                     request.setEnableContext(true); // Context 由外部传入
                    request.setFeatureType(AIFeatureType.NOVEL_COMPOSE);

                     // 添加章节范围元数据 (如果适用)
                     Map<String, Object> metadata = request.getMetadata();
                     if (metadata == null) {
                         metadata = new HashMap<>(); // Create a new mutable map if null
                         request.setMetadata(metadata);
                     } else if (!(metadata instanceof HashMap)) {
                         // 如果存在但不是可变的 HashMap (例如是不可变 Map)，则创建可变副本
                         log.warn("AIRequest metadata was not a HashMap ({}), creating a mutable copy.", metadata.getClass().getName());
                         metadata = new HashMap<>(metadata);
                         request.setMetadata(metadata);
                     }
                     if (startChapterId != null) metadata.put("startChapterId", startChapterId);
                     if (endChapterId != null) metadata.put("endChapterId", endChapterId);

                     // 设置参数 (可以根据需要调整)
                     request.setTemperature(0.75);
                     request.setMaxTokens(200000); // 单个选项的 token 可以适当减少

                     // 创建系统消息
                     AIRequest.Message systemMessage = new AIRequest.Message();
                     systemMessage.setRole("system");
                     systemMessage.setContent("你是一位专业的小说创作顾问。请根据提供的上下文和引导，生成一个后续剧情大纲选项。"
                             + "请严格按照以下格式输出，先输出标题，再输出内容："
                             + "\\nTITLE: [这里是剧情选项的简洁标题]"
                             + "\\nCONTENT: [这里是剧情选项的详细内容描述]");
                     request.getMessages().add(systemMessage);

                     // 创建用户消息
                     AIRequest.Message userMessage = new AIRequest.Message();
                     userMessage.setRole("user");
                     userMessage.setContent(prompt);
                     request.getMessages().add(userMessage);

                     return request;
                 });
    }

    /**
     * 创建单个下一剧情大纲生成请求 (重载，用于基于 general context)
     */
    private Mono<AIRequest> createSingleOutlineGenerationRequest(String userId, String novelId, String currentContext, String authorGuidance) {
        return createSingleOutlineGenerationRequest(userId, novelId, currentContext, authorGuidance, null, null); // 调用章节范围版本，传入null chapter IDs
    }

    @Override
    public Mono<AIResponse> generateChatResponse(String userId, String sessionId, String content, Map<String, Object> metadata) {
        return getAIModelProvider(userId, null)
                .flatMap(provider -> {
                    AIRequest request = new AIRequest();
                    request.setUserId(userId);
                    // 使用反射设置sessionId和metadata
                    try {
                        request.getClass().getMethod("setSessionId", String.class).invoke(request, sessionId);
                        request.getClass().getMethod("setMetadata", Map.class).invoke(request, metadata);
                    } catch (Exception e) {
                        log.error("Failed to set sessionId or metadata", e);
                    }

                    // 创建用户消息
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(content);
                    request.getMessages().add(userMessage);

                    return provider.generateContent(request);
                });
    }

    @Override
    public Flux<String> generateChatResponseStream(String userId, String sessionId, String content, Map<String, Object> metadata) {
        return getAIModelProvider(userId, null)
                .flatMapMany(provider -> {
                    AIRequest request = new AIRequest();
                    request.setUserId(userId);
                    // 使用反射设置sessionId和metadata
                    try {
                        request.getClass().getMethod("setSessionId", String.class).invoke(request, sessionId);
                        request.getClass().getMethod("setMetadata", Map.class).invoke(request, metadata);
                    } catch (Exception e) {
                        log.error("Failed to set sessionId or metadata", e);
                    }

                    // 创建用户消息
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(content);
                    request.getMessages().add(userMessage);

                    return provider.generateContentStream(request);
                });
    }

    /**
     * 使用上下文丰富AI请求
     *
     * @param request 原始请求
     * @return 丰富后的请求
     */
    private Mono<AIRequest> enrichRequestWithContext(AIRequest request) {
        // 如果没有指定小说ID，则直接返回原始请求
        if (request.getNovelId() == null || request.getNovelId().isEmpty()) {
            return Mono.just(request);
        }

        log.info("为请求丰富上下文，小说ID: {}", request.getNovelId());

        // 获取是否启用RAG
        boolean enableRag = request.getMetadata() != null
                && request.getMetadata().getOrDefault("enableRag", "false").toString().equalsIgnoreCase("true");

        if (!enableRag) {
            // 如果未启用RAG，使用原有逻辑
            return getNovelContextFromDatabase(request);
        }

        log.info("为请求使用RAG检索上下文，小说ID: {}", request.getNovelId());

        // 从请求中提取查询文本
        String queryText = extractQueryTextFromRequest(request);

        if (queryText.isEmpty()) {
            return getNovelContextFromDatabase(request);
        }

        // 使用ContentRetriever检索相关上下文
        // 将可能阻塞的操作放在boundedElastic调度器上执行
        return Mono.fromCallable(() -> {
            List<Content> relevantContents = contentRetriever.retrieve(Query.from(queryText));

            // 将Content转换为TextSegment
            List<TextSegment> relevantSegments = relevantContents.stream()
                    .map(Content::textSegment)
                    .collect(Collectors.toList());

            if (relevantSegments.isEmpty()) {
                log.info("RAG未找到相关上下文，使用数据库检索");
                return request;
            }

            log.info("RAG检索到 {} 个相关段落", relevantSegments.size());

            // 格式化检索到的上下文
            String relevantContext = formatRetrievedContext(relevantSegments);

            // 将检索到的上下文添加到系统消息中
            if (request.getMessages() == null) {
                request.setMessages(new ArrayList<>());
            }

            // 添加系统消息
            AIRequest.Message systemMessage = new AIRequest.Message();
            systemMessage.setRole("system");
            systemMessage.setContent("你是一位小说创作助手。以下是一些相关的上下文信息，可能对回答有帮助：\\n\\n" + relevantContext);

            // 在消息列表开头插入系统消息
            if (!request.getMessages().isEmpty()) {
                request.getMessages().add(0, systemMessage);
            } else {
                request.getMessages().add(systemMessage);
            }

            // 在元数据中标记已使用RAG
            if (request.getMetadata() != null) {
                request.getMetadata().put("usedRag", "true");
            }

            return request;
        })
                .subscribeOn(Schedulers.boundedElastic()) // 在boundedElastic调度器上执行可能阻塞的操作
                .onErrorResume(e -> {
                    log.error("使用RAG检索上下文时出错", e);
                    return getNovelContextFromDatabase(request);
                });
    }

    /**
     * 从数据库获取小说上下文
     *
     * @param request AI请求
     * @return 丰富的AI请求
     */
    private Mono<AIRequest> getNovelContextFromDatabase(AIRequest request) {
        // 原有的从数据库获取上下文的逻辑
        return knowledgeService.retrieveRelevantContext(extractQueryTextFromRequest(request), request.getNovelId())
                .subscribeOn(Schedulers.boundedElastic()) // 在boundedElastic调度器上执行可能阻塞的操作
                .map(context -> {
                    if (context != null && !context.isEmpty()) {
                        log.info("从知识库中获取到相关上下文");

                        if (request.getMessages() == null) {
                            request.setMessages(new ArrayList<>());
                        }

                        // 创建系统消息
                        AIRequest.Message systemMessage = new AIRequest.Message();
                        systemMessage.setRole("system");
                        systemMessage.setContent("你是一位小说创作助手。以下是一些相关的上下文信息，可能对回答有帮助：\\n\\n" + context);

                        // 在消息列表开头插入系统消息
                        if (!request.getMessages().isEmpty()) {
                            request.getMessages().add(0, systemMessage);
                        } else {
                            request.getMessages().add(systemMessage);
                        }
                    }
                    return request;
                })
                .onErrorResume(e -> {
                    log.error("获取知识库上下文时出错", e);
                    return Mono.just(request);
                })
                .defaultIfEmpty(request);
    }

    /**
     * 从请求中提取查询文本
     *
     * @param request AI请求
     * @return 查询文本
     */
    private String extractQueryTextFromRequest(AIRequest request) {
        // 从消息列表中提取用户最后一条消息
        if (request.getMessages() != null && !request.getMessages().isEmpty()) {
            return request.getMessages().stream()
                    .filter(msg -> "user".equals(msg.getRole()))
                    .reduce((first, second) -> second) // 获取最后一条用户消息
                    .map(AIRequest.Message::getContent)
                    .orElse("");
        }

        // 如果没有消息，则使用提示文本
        return request.getPrompt() != null ? request.getPrompt() : "";
    }

    /**
     * 格式化检索到的上下文
     *
     * @param segments 文本段落列表
     * @return 格式化的上下文
     */
    private String formatRetrievedContext(List<TextSegment> segments) {
        StringBuilder builder = new StringBuilder();

        for (int i = 0; i < segments.size(); i++) {
            TextSegment segment = segments.get(i);
            builder.append("段落 #").append(i + 1).append(":\\n");

            // 添加元数据信息（如果存在）
            if (segment.metadata() != null) {
                Map<String, Object> metadata = segment.metadata().toMap();
                if (metadata.containsKey("title")) {
                    builder.append("标题: ").append(metadata.get("title")).append("\\n");
                }
                if (metadata.containsKey("sourceType")) {
                    String sourceType = metadata.get("sourceType").toString();
                    if ("scene".equals(sourceType)) {
                        builder.append("类型: 场景\\n");
                    } else if ("novel_metadata".equals(sourceType)) {
                        builder.append("类型: 小说元数据\\n");
                    } else {
                        builder.append("类型: ").append(sourceType).append("\\n");
                    }
                }
            }

            // 添加文本内容
            builder.append(segment.text()).append("\\n\\n");
        }

        return builder.toString();
    }

    /**
     * 创建建议请求
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param suggestionType 建议类型
     * @return AI请求
     */
    private Mono<AIRequest> createSuggestionRequest(String novelId, String sceneId, String suggestionType) {
        return promptService.getSuggestionPrompt(suggestionType)
                .map(promptTemplate -> {
                    AIRequest request = new AIRequest();
                    request.setNovelId(novelId);
                    request.setSceneId(sceneId);
                    request.setEnableContext(true);
                    request.setFeatureType(AIFeatureType.AI_CHAT);

                    // 创建用户消息
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(promptTemplate);

                    request.getMessages().add(userMessage);
                    return request;
                });
    }

    /**
     * 创建修改请求
     *
     * @param novelId 小说ID
     * @param sceneId 场景ID
     * @param content 原内容
     * @param instruction 修改指令
     * @return AI请求
     */
    private Mono<AIRequest> createRevisionRequest(String novelId, String sceneId, String content, String instruction) {
        return promptService.getRevisionPrompt()
                .map(promptTemplate -> {
                    String prompt = promptTemplate
                            .replace("{{content}}", content)
                            .replace("{{instruction}}", instruction);

                    AIRequest request = new AIRequest();
                    request.setNovelId(novelId);
                    request.setSceneId(sceneId);
                    request.setEnableContext(true);
                    request.setFeatureType(AIFeatureType.AI_CHAT);

                    // 创建用户消息
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(prompt);

                    request.getMessages().add(userMessage);
                    return request;
                });
    }



    /**
     * 创建下一剧情大纲生成请求
     *
     * @param novelId 小说ID
     * @param currentContext 当前剧情上下文
     * @param numberOfOptions 希望生成的选项数量
     * @param authorGuidance 作者引导
     * @return AI请求
     */
    private Mono<AIRequest> createNextOutlinesGenerationRequest(String novelId, String currentContext, int numberOfOptions, String authorGuidance) {
        return promptService.getNextOutlinesGenerationPrompt()
                .map(promptTemplate -> {
                    // 根据提示词模板替换变量
                    String prompt = promptTemplate
                            .replace("{{context}}", currentContext)
                            .replace("{{numberOfOptions}}", String.valueOf(numberOfOptions))
                            .replace("{{authorGuidance}}", authorGuidance.isEmpty() ? "" : "作者引导：" + authorGuidance);

                    AIRequest request = new AIRequest();
                    request.setNovelId(novelId);
                    request.setEnableContext(true);
                    request.setFeatureType(AIFeatureType.NOVEL_COMPOSE);

                    // 设置较高的温度以获得多样性
                    request.setTemperature(0.8);
                    // 设置较大的最大令牌数，以确保生成足够详细的大纲
                    request.setMaxTokens(200000);

                    // 创建系统消息
                    AIRequest.Message systemMessage = new AIRequest.Message();
                    systemMessage.setRole("system");
                    systemMessage.setContent("你是一位专业的小说创作顾问，擅长为作者提供多样化的剧情发展选项。请确保每个选项都有明显的差异，提供真正不同的故事发展方向。");
                    request.getMessages().add(systemMessage);

                    // 创建用户消息
                    AIRequest.Message userMessage = new AIRequest.Message();
                    userMessage.setRole("user");
                    userMessage.setContent(prompt);

                    request.getMessages().add(userMessage);
                    return request;
                });
    }

    /**
     * 获取AI模型提供商
     *
     * @param userId 用户ID
     * @param modelName 模型名称
     * @return AI模型提供商
     */
    @Override
    public Mono<AIModelProvider> getAIModelProvider(String userId, String modelName) {
        log.info("获取用户 {} 的AI模型提供商，请求的模型: {}", userId, modelName == null ? "默认" : modelName);
        // 如果没有指定模型名称，则使用用户的默认模型
        if (modelName == null || modelName.isEmpty()) {
            return userAIModelConfigService.getValidatedDefaultConfiguration(userId)
                    .doOnNext(config -> log.info("找到用户 {} 的默认配置: Provider={}, Model={}", userId, config.getProvider(), config.getModelName()))
                    .flatMap(config -> {
                        if (config == null) {
                            log.warn("用户 {} 没有配置有效的默认AI模型", userId);
                            return Mono.error(new IllegalArgumentException("用户没有配置默认AI模型"));
                        }
                        return getOrCreateAIModelProvider(userId, config);
                    })
                    .switchIfEmpty(Mono.<AIModelProvider>defer(() -> { // 使用 defer 避免 switchIfEmpty 预先执行
                        log.warn("无法找到用户 {} 的默认AI模型配置", userId);
                        return Mono.error(new IllegalArgumentException("用户没有配置默认AI模型或默认配置无效"));
                    }));
        }

        // 如果指定了模型名称，则查找对应的配置
        return userAIModelConfigService.listConfigurations(userId)
                .filter(config -> modelName.equals(config.getModelName()))
                .next() // 获取第一个匹配的配置
                .doOnNext(config -> log.info("找到用户 {} 指定的模型配置: Provider={}, Model={}", userId, config.getProvider(), config.getModelName()))
                .flatMap(config -> getOrCreateAIModelProvider(userId, config))
                .switchIfEmpty(Mono.<AIModelProvider>defer(() -> { // 使用 defer 避免 switchIfEmpty 预先执行
                    log.warn("找不到用户 {} 指定的AI模型配置: {}", userId, modelName);
                    return Mono.error(new IllegalArgumentException("找不到指定的AI模型配置: " + modelName));
                }));
    }

    /**
     * 获取或创建AI模型提供商
     * 
     * ⚠️ 重要修改：已移除Provider缓存机制
     * 原因：共享的StreamingChatLanguageModel实例在并发场景下不是线程安全的，
     * 会导致不同用户的流式响应混乱（用户A看到用户B的生成内容）
     * 
     * 修复方案：每次请求都创建新的Provider实例，确保每个请求有独立的流式模型实例
     * 性能影响：Provider创建成本较低（主要是对象实例化），相比数据泄露风险可接受
     *
     * @param userId 用户ID
     * @param config AI模型配置
     * @return AI模型提供商
     */
    private Mono<AIModelProvider> getOrCreateAIModelProvider(String userId, UserAIModelConfig config) {
        // 检查配置是否有效
        if (config == null || config.getProvider() == null || config.getModelName() == null) {
            log.error("尝试为用户 {} 创建提供商时遇到无效配置: {}", userId, config);
            return Mono.error(new IllegalArgumentException("无效的AI模型配置"));
        }
        
        // 检查API Key是否存在
        String encryptedApiKey = config.getApiKey();
        if (encryptedApiKey == null || encryptedApiKey.isBlank()) {
            log.error("用户 {} 的模型配置 Provider={}, Model={} 缺少 API Key", userId, config.getProvider(), config.getModelName());
            // 注意：根据你的业务逻辑，这里可能应该抛出错误或者返回一个表示配置错误的特定状态
            // return Mono.error(new IllegalArgumentException("模型配置缺少 API Key")); // 取消注释以强制要求API Key
        }

        // ✅ 移除缓存逻辑 - 每次都创建新的Provider实例以避免并发问题
        log.info("为用户 {} 创建新的AI模型提供商: Provider={}, Model={}, Endpoint={}",
                userId, config.getProvider(), config.getModelName(), config.getApiEndpoint());

        // 解密 API Key
        String decryptedApiKey = null;
        if (encryptedApiKey != null && !encryptedApiKey.isBlank()) {
            try {
                decryptedApiKey = encryptor.decrypt(encryptedApiKey);
                log.debug("用户 {} 的模型 Provider={}, Model={} API Key 解密成功", userId, config.getProvider(), config.getModelName());
            } catch (Exception e) {
                log.error("为用户 {} 的模型 Provider={}, Model={} 解密 API Key 时失败", userId, config.getProvider(), config.getModelName(), e);
                return Mono.error(new RuntimeException("创建AI模型提供商失败，无法解密API Key", e));
            }
        } else {
            log.warn("用户 {} 的模型 Provider={}, Model={} API Key 为空，继续尝试创建提供商（可能适用于本地或无需Key的模型）", userId, config.getProvider(), config.getModelName());
        }

        // 使用AIService创建新的提供商（不再缓存）
        try {
            AIModelProvider newProvider = aiService.createProviderByConfigId(userId, config.getId());

            if (newProvider != null) {
                // ✅ 不再缓存Provider实例
                log.info("成功创建用户 {} 的AI模型提供商: {}", userId, config.getProvider() + ":" + config.getModelName());
                return Mono.just(newProvider);
            } else {
                log.error("AIService未能为用户 {} 创建提供商: Provider={}, Model={}", userId, config.getProvider(), config.getModelName());
                return Mono.error(new IllegalArgumentException("无法创建AI模型提供商: " + config.getProvider()));
            }
        } catch (Exception e) {
            log.error("为用户 {} 创建AI模型提供商时出错: Provider={}, Model={}", userId, config.getProvider(), config.getModelName(), e);
            return Mono.error(new RuntimeException("创建AI模型提供商失败", e));
        }
    }

    /**
     * 设置是否使用LangChain4j实现
     *
     * @param useLangChain4j 是否使用LangChain4j
     */
    @Override
    public void setUseLangChain4j(boolean useLangChain4j) {
        // 委托给AIService
        aiService.setUseLangChain4j(useLangChain4j);
        // ✅ 已移除缓存机制，无需清空缓存
        // userProviders.clear();
    }

    /**
     * 清除用户的模型提供商缓存
     * ✅ 已废弃：缓存机制已移除，此方法不再执行任何操作
     *
     * @param userId 用户ID
     * @return 操作结果
     */
    @Override
    public Mono<Void> clearUserProviderCache(String userId) {
        // ✅ 已移除缓存机制，直接返回空
        return Mono.empty();
    }

    /**
     * 清除所有模型提供商缓存
     * ✅ 已废弃：缓存机制已移除，此方法不再执行任何操作
     *
     * @return 操作结果
     */
    @Override
    public Mono<Void> clearAllProviderCache() {
        // ✅ 已移除缓存机制，直接返回空
        return Mono.empty();
    }

    /**
     * 为指定场景生成摘要
     *
     * @param userId 用户ID
     * @param sceneId 场景ID
     * @param request 摘要请求参数
     * @return 包含摘要的响应
     */
    @Override
    public Mono<SummarizeSceneResponse> summarizeScene(String userId, String sceneId, SummarizeSceneRequest request) {
        // Find the scene first to get novelId and content
        return sceneService.findSceneById(sceneId)
                .flatMap(scene -> {
                    final String novelId = scene.getNovelId(); // Get novelId here
                    final String sceneContent = scene.getContent();

                    // Then, check novel access permission
                    return novelService.findNovelById(novelId)
                            .flatMap(novel -> {
                                if (!novel.getAuthor().getId().equals(userId)) {
                                    return Mono.error(new AccessDeniedException("用户无权访问该场景对应的小说"));
                                }

                                // Fetch context and prompt template in parallel
                                Mono<String> contextMono = Mono.just("");
//                                Mono<String> contextMono = ragService.retrieveRelevantContext(
//                                        novelId, sceneId, AIFeatureType.SCENE_TO_SUMMARY);
                                Mono<String> promptTemplateMono = userPromptService.getPromptTemplate(
                                        userId, AIFeatureType.SCENE_TO_SUMMARY);

                                // Pass novelId and sceneContent along with context and template
                                return Mono.zip(Mono.just(novelId), Mono.just(sceneContent), contextMono, promptTemplateMono);
                            });
                })
                .flatMap(tuple -> {
                    // Unpack the tuple
                    String novelId = tuple.getT1();
                    String sceneContent = tuple.getT2();
                    String context = tuple.getT3();
                    String promptTemplate = tuple.getT4();

                    String finalPrompt = buildFinalPrompt(promptTemplate, context, sceneContent);

                    // Get AI config and call LLM
                    return resolveAiConfig(userId, request)
                            .flatMap(aiConfig -> {
                                AIRequest aiRequest = new AIRequest();
                                aiRequest.setUserId(userId);
                                aiRequest.setNovelId(novelId); // Use the novelId passed from the previous step
                                aiRequest.setModel(aiConfig.getModelName());

                                // System message
                                AIRequest.Message systemMessage = new AIRequest.Message();
                                systemMessage.setRole("system");
                                systemMessage.setContent("你是一个专业的小说编辑。请根据用户提供的场景内容和上下文信息，生成一个简洁的场景摘要。你的任务是只输出摘要本身，不包含任何标题、小标题、格式标记（如Markdown）、或其他解释性文字。");
                                aiRequest.getMessages().add(systemMessage);

                                // User message
                                AIRequest.Message userMessage = new AIRequest.Message();
                                userMessage.setRole("user");
                                userMessage.setContent(finalPrompt);
                                aiRequest.getMessages().add(userMessage);

                                aiRequest.setTemperature(0.7);

                                return getAIModelProvider(userId, aiConfig.getModelName())
                                        .flatMap(provider -> {
                                            log.info("开始向AI模型发送摘要生成请求，用户ID: {}, 模型: {}", userId, aiConfig.getModelName());
                                            return provider.generateContent(aiRequest)
                                                .doOnCancel(() -> log.info("客户端取消了连接，但AI生成会在后台继续完成, 用户: {}, 模型: {}", userId, aiConfig.getModelName()))
                                                .timeout(Duration.ofSeconds(600))
                                                .doOnSuccess(resp -> log.info("AI摘要生成成功完成，用户ID: {}, 模型: {}", userId, aiConfig.getModelName()))
                                                .onErrorResume(e -> {
                                                    log.error("AI内容生成出错: {}", e.getMessage(), e);
                                                    return Mono.error(new RuntimeException("AI生成摘要失败: " + e.getMessage(), e));
                                                });
                                        })
                                        .retry(3);
                            })
                            .map(response -> new SummarizeSceneResponse(response.getContent()));
                })
                .onErrorResume(e -> {
                    log.error("生成场景摘要时出错", e);
                    if (e instanceof AccessDeniedException) {
                        return Mono.error(e);
                    }
                     // Check for ResourceNotFoundException from sceneService.findSceneById
                    if (e instanceof com.ainovel.server.common.exception.ResourceNotFoundException) {
                         log.warn("请求摘要的场景未找到: {}", sceneId);
                         return Mono.error(new RuntimeException("找不到指定的场景: " + sceneId)); 
                    }
                    return Mono.error(new RuntimeException("生成摘要失败: " + e.getMessage()));
                });
    }

    /**
     * 构建最终提示词
     */
    private String buildFinalPrompt(String template, String context, String input) {
        // 使用PromptUtil工具类处理富文本和占位符替换
        Map<String, String> variables = new HashMap<>();

        // 1. 将输入的富文本转换为纯文本
        String plainTextInput = com.ainovel.server.common.util.PromptUtil.extractPlainTextFromRichText(input);
        // 2. 将 RAG 返回的 context (也可能是富文本) 转换为纯文本
        String plainContext = com.ainovel.server.common.util.PromptUtil.extractPlainTextFromRichText(context);

        // 3. 填充变量，添加多种兼容性变量名
        variables.put("input", plainTextInput); // 当前需要处理的内容
        variables.put("summary", plainTextInput); // summary 作为 input 的别名
        variables.put("content", plainTextInput); // content 作为 input 的别名
        variables.put("description", plainTextInput); // description 作为 input 的别名
        
        // 如果 RAG 上下文不为空，则添加带有说明的上下文
        if (plainContext != null && !plainContext.isBlank()) {
            variables.put("context", "## 相关上下文信息:\\n" + plainContext); 
        } else {
            variables.put("context", ""); // 如果无上下文，则为空字符串
        }

        // 4. 动态检测模板中的占位符
        try {
            // 简单的正则表达式来匹配 {{xxx}} 形式的占位符
            Pattern placeholderPattern = Pattern.compile("\\{\\{([^}]+)\\}\\}");
            Matcher matcher = placeholderPattern.matcher(template);
            
            Set<String> foundPlaceholders = new HashSet<>();
            while (matcher.find()) {
                foundPlaceholders.add(matcher.group(1).trim());
            }
            
            // 检查是否有未处理的占位符
            for (String placeholder : foundPlaceholders) {
                if (!variables.containsKey(placeholder)) {
                    log.warn("提示词模板中存在未处理的占位符: {}，将提供空值", placeholder);
                    // 为未知占位符提供默认空值
                    variables.put(placeholder, "");
                }
            }
        } catch (Exception e) {
            // 确保正则检测失败不会影响主流程
            log.warn("分析提示词模板占位符时发生错误: {}", e.getMessage());
        }

        // 5. 使用 PromptUtil 格式化模板 (formatPromptTemplate 内部会处理 template 的富文本)
        try {
            return com.ainovel.server.common.util.PromptUtil.formatPromptTemplate(template, variables);
        } catch (Exception e) {
            log.error("格式化提示词模板时出错: {}", e.getMessage(), e);
            // 构建一个后备提示词确保服务不中断
            return "输入内容:\\n" + plainTextInput + "\\n\\n上下文信息:\\n" + plainContext;
        }
    }

    /**
     * 重载 buildFinalPrompt 以适应新的参数结构，包括设定信息
     */
    private String buildFinalPrompt(String userPromptTemplate, String combinedContext, String summary, String styleInstructions) {
        Map<String, String> variables = new HashMap<>();
        
        // 提取并清理输入数据，确保处理空值
        String cleanSummary = RichTextUtil.deltaJsonToPlainText(summary != null ? summary : "");
        String cleanContext = RichTextUtil.deltaJsonToPlainText(combinedContext != null ? combinedContext : "");
        String cleanStyle = styleInstructions != null ? styleInstructions : "";
        
        // 基础变量映射
        variables.put("summary", cleanSummary);
        variables.put("context", cleanContext); // 现在context包含了设定信息
        variables.put("styleInstructions", cleanStyle);
        
        // 兼容性变量映射
        variables.put("input", cleanSummary);
        variables.put("content", cleanSummary);
        variables.put("description", cleanSummary);
        variables.put("instruction", cleanStyle);
        variables.put("style", cleanStyle);
        
        // 确保模板中可以使用settings变量 - 新增部分
        variables.put("settings", cleanContext.contains("## 相关设定信息") ? 
            cleanContext.substring(cleanContext.indexOf("## 相关设定信息")) : "");
        
        // 标记是否模板中包含风格相关的占位符
        boolean hasStylePlaceholder = false;
        Set<String> styleRelatedKeys = Set.of("styleInstructions", "instruction", "style");
        
        // 动态检测模板中的占位符
        try {
            Pattern placeholderPattern = Pattern.compile("\\{\\{([^}]+)\\}\\}");
            Matcher matcher = placeholderPattern.matcher(userPromptTemplate);
            
            Set<String> foundPlaceholders = new HashSet<>();
            while (matcher.find()) {
                String placeholder = matcher.group(1).trim();
                foundPlaceholders.add(placeholder);
                
                if (styleRelatedKeys.contains(placeholder)) {
                    hasStylePlaceholder = true;
                }
            }
            
            // 检查是否有未处理的占位符
            for (String placeholder : foundPlaceholders) {
                if (!variables.containsKey(placeholder)) {
                    log.warn("提示词模板中存在未处理的占位符: {}，将提供空值", placeholder);
                    variables.put(placeholder, "");
                }
            }
        } catch (Exception e) {
            log.warn("分析提示词模板占位符时发生错误: {}", e.getMessage());
        }
        
        // 使用 PromptUtil 格式化模板
        try {
            String formattedPrompt = com.ainovel.server.common.util.PromptUtil.formatPromptTemplate(userPromptTemplate, variables);
            
            // 如果没有风格相关占位符且风格指示不为空，则将风格指示添加到提示词前面
            if (!hasStylePlaceholder && !cleanStyle.isEmpty()) {
                formattedPrompt = "风格要求:\n" + cleanStyle + "\n\n" + formattedPrompt;
            }
            
            return formattedPrompt;
        } catch (Exception e) {
            log.error("格式化提示词模板时出错: {}", e.getMessage(), e);
            // 出错时构造一个简化的模板，确保服务不中断
            StringBuilder fallbackPrompt = new StringBuilder();
            if (!cleanStyle.isEmpty()) {
                fallbackPrompt.append("风格要求:\n").append(cleanStyle).append("\n\n");
            }
            fallbackPrompt.append("摘要:\n").append(cleanSummary).append("\n\n");
            fallbackPrompt.append("相关上下文和设定:\n").append(cleanContext);
            return fallbackPrompt.toString();
        }
    }

    /**
     * 根据摘要生成场景内容 (流式)
     *
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param request 生成场景请求参数
     * @return 生成的场景内容流
     */
    @Override
    public Flux<String> generateSceneFromSummaryStream(String userId, String novelId, GenerateSceneFromSummaryRequest request) {
        log.info("根据摘要生成场景内容(流式), userId: {}, novelId: {}", userId, novelId);

        // 验证用户对小说的访问权限
        return novelService.findNovelById(novelId)
                .flatMap(novel -> {
                    if (!novel.getAuthor().getId().equals(userId)) {
                        return Mono.error(new AccessDeniedException("用户无权访问该小说"));
                    }

                    // 并行获取RAG上下文、最后一个章节内容、系统提示、用户Prompt模板和相关设定
                    // 暂时禁用 RAG 上下文检索
                    Mono<String> ragContextMono = Mono.just("");
                    /*
                    Mono<String> ragContextMono = ragService.retrieveRelevantContext(
                            novelId, request.getChapterId(), request.getSummary(), AIFeatureType.SUMMARY_TO_SCENE)
                            .doOnNext(context -> {
                                if (context == null || context.isEmpty()) {
                                    log.info("RAG未返回相关上下文, 小说ID: {}, 章节ID: {}", 
                                            novelId, request.getChapterId() != null ? request.getChapterId() : "无");
                                } else {
                                    log.info("RAG返回相关上下文, 长度: {}, 小说ID: {}", 
                                            context.length(), novelId);
                                }
                            })
                            .defaultIfEmpty("") // 确保有默认值
                            .onErrorResume(e -> {
                                log.error("获取RAG上下文时出错, 小说ID: {}, 错误: {}", novelId, e.getMessage());
                                return Mono.just("");
                            });
                    */

                    // 获取上一个章节的内容
                    Mono<String> previousChapterContentMono;
                    if (request.getChapterId() != null && !request.getChapterId().isBlank()) {
                        previousChapterContentMono = novelService.getPreviousChapterId(novelId, request.getChapterId())
                            .flatMap(previousChapterId -> 
                                novelService.getChapterRangeContext(novelId, previousChapterId, previousChapterId)
                                .doOnNext(content -> {
                                    if (content == null || content.isEmpty()) {
                                        log.warn("上一章节内容为空, 章节ID: {}, 小说ID: {}", previousChapterId, novelId);
                                    } else {
                                        log.info("成功获取上一章节内容, 长度: {}, 章节ID: {}", content.length(), previousChapterId);
                                    }
                                })
                            )
                            .onErrorResume(e -> {
                                log.error("获取上一章节内容时出错, 章节ID: {}, 小说ID: {}, 错误: {}", 
                                         request.getChapterId(), novelId, e.getMessage());
                                return Mono.just("");  // 发生错误时返回空字符串而不是中断流程
                            })
                            .switchIfEmpty(Mono.<String>defer(() -> {
                                log.warn("未找到上一章节ID或内容, 章节ID: {}, 小说ID: {}", request.getChapterId(), novelId);
                                // 尝试直接获取当前章节内容作为备选
                                return novelService.getChapterRangeContext(novelId, request.getChapterId(), request.getChapterId())
                                    .doOnNext(content -> {
                                        if (content != null && !content.isEmpty()) {
                                            log.info("使用当前章节内容作为上下文, 长度: {}, 章节ID: {}", 
                                                   content.length(), request.getChapterId());
                                        }
                                    })
                                    .defaultIfEmpty("");
                            }));
                    } else {
                        // 如果当前请求没有 chapterId，则无法确定上一个章节
                        log.info("请求中未提供章节ID, 无法获取上一章内容, 小说ID: {}", novelId);
                        previousChapterContentMono = Mono.just("");
                    }
                    
                    // 获取相关设定信息 - 新增部分
                    Mono<String> relevantSettingsMono = getRelevantSettings(novelId, request.getSummary(), request.getChapterId())
                        .defaultIfEmpty("");
                    
                    // 合并RAG上下文、上一个章节的内容和相关设定
                    Mono<String> combinedContextMono = Mono.zip(ragContextMono, previousChapterContentMono, relevantSettingsMono)
                        .map(contextsTuple -> {
                            String ragContext = contextsTuple.getT1();
                            String prevChapterContent = contextsTuple.getT2();
                            String relevantSettings = contextsTuple.getT3(); // 新增部分
                            
                            StringBuilder combined = new StringBuilder();
                            
                            // 记录上下文合并情况
                            int ragContextLength = ragContext != null ? ragContext.length() : 0;
                            int prevChapterLength = prevChapterContent != null ? prevChapterContent.length() : 0;
                            int settingsLength = relevantSettings != null ? relevantSettings.length() : 0; // 新增部分
                            
                            log.info("合并上下文, RAG上下文长度: {}, 上一章内容长度: {}, 设定信息长度: {}, 小说ID: {}",
                                    ragContextLength, prevChapterLength, settingsLength, novelId);
                            
                            if (ragContext != null && !ragContext.isBlank()) {
                                combined.append("## RAG检索到的相关上下文:\n").append(ragContext).append("\n\n");
                            }
                            if (prevChapterContent != null && !prevChapterContent.isBlank()) {
                                combined.append("## 上一个章节完整内容:\n").append(RichTextUtil.deltaJsonToPlainText(prevChapterContent)).append("\n\n");
                            }
                            // 添加相关设定信息 - 新增部分
                            if (relevantSettings != null && !relevantSettings.isBlank()) {
                                combined.append(relevantSettings);
                            }
                            
                            String result = combined.toString();
                            log.info("最终上下文长度: {}, 小说ID: {}", result.length(), novelId);
                            return result;
                        });

                    Mono<String> systemPromptContentMono;
                    Mono<String> userPromptTemplateMono;

                    if (request.getPromptTemplateId() != null && !request.getPromptTemplateId().isBlank()) {
                        Mono<com.ainovel.server.domain.model.EnhancedUserPromptTemplate> selectedTemplateMono =
                                promptService.getPromptTemplateById(userId, request.getPromptTemplateId())
                                    .doOnNext(t -> log.info("使用指定的内容提示词模板: {}", t.getId()))
                                    .cache();

                        systemPromptContentMono = selectedTemplateMono
                                .map(t -> {
                                    String sys = t.getSystemPrompt();
                                    return (sys != null && !sys.isBlank()) ? sys : null;
                                })
                                .switchIfEmpty(promptService.getSystemMessageForFeature(AIFeatureType.SUMMARY_TO_SCENE))
                                .switchIfEmpty(Mono.just("你是一位富有创意的小说家。请根据用户提供的摘要、上下文信息、相关设定和风格要求，生成详细的小说场景内容。请确保生成的内容与设定保持一致。"));

                        userPromptTemplateMono = selectedTemplateMono
                                .map(t -> t.getUserPrompt())
                                .switchIfEmpty(userPromptService.getPromptTemplate(userId, AIFeatureType.SUMMARY_TO_SCENE))
                                .switchIfEmpty(promptService.getSuggestionPrompt(AIFeatureType.SUMMARY_TO_SCENE.name()));
                    } else {
                        systemPromptContentMono = promptService.getSystemMessageForFeature(AIFeatureType.SUMMARY_TO_SCENE)
                                .switchIfEmpty(Mono.just("你是一位富有创意的小说家。请根据用户提供的摘要、上下文信息、相关设定和风格要求，生成详细的小说场景内容。请确保生成的内容与设定保持一致。"));
                        userPromptTemplateMono = userPromptService.getPromptTemplate(userId, AIFeatureType.SUMMARY_TO_SCENE)
                                .switchIfEmpty(promptService.getSuggestionPrompt(AIFeatureType.SUMMARY_TO_SCENE.name()));
                    }

                    // 返回包含合并后上下文、系统提示、用户模板的Tuple
                    return Mono.zip(combinedContextMono, systemPromptContentMono, userPromptTemplateMono);
                })
                .flatMapMany(tuple -> {
                    String combinedContext = tuple.getT1();
                    String systemPromptContent = tuple.getT2();
                    String userPromptTemplate = tuple.getT3();

                    // 构建最终Prompt，包含用户风格指令
                    String styleInstructions = request.getAdditionalInstructions() != null ? request.getAdditionalInstructions() : "";
                    
                    log.info("构建最终提示词, 摘要长度: {}, 上下文长度: {}, 风格指令长度: {}, 小说ID: {}",
                            request.getSummary() != null ? request.getSummary().length() : 0,
                            combinedContext.length(),
                            styleInstructions.length(),
                            novelId);
                    
                    // 使用AtomicReference来存储最终的提示词
                    final AtomicReference<String> promptRef = new AtomicReference<>();
                    try {
                        String userPrompt = buildFinalPrompt(userPromptTemplate, combinedContext, request.getSummary(), styleInstructions);
                        log.info("成功构建最终提示词, 长度: {}, 小说ID: {}", userPrompt.length(), novelId);
                        promptRef.set(userPrompt);
                    } catch (Exception e) {
                        log.error("构建最终提示词时出错, 小说ID: {}, 错误: {}", novelId, e.getMessage(), e);
                        // 构建一个简单的后备提示词
                        String fallbackPrompt = "摘要:\n" + request.getSummary() + "\n\n相关上下文:\n" + 
                                         (combinedContext.length() > 500 ? combinedContext.substring(0, 500) + "..." : combinedContext);
                        log.info("使用后备提示词, 长度: {}", fallbackPrompt.length());
                        promptRef.set(fallbackPrompt);
                    }

                    // 统一：若外部传入公共模型配置ID，则直接按配置ID创建Provider（不做上游预扣费）
                    if (request.getPublicModelConfigId() != null && !request.getPublicModelConfigId().isBlank()) {
                        String publicModelConfigId = request.getPublicModelConfigId();
                        AIRequest aiRequest = new AIRequest();
                        aiRequest.setUserId(userId);
                        aiRequest.setNovelId(novelId);
                        aiRequest.setFeatureType(AIFeatureType.SUMMARY_TO_SCENE);
                        // 模型名可留空，由底层Provider自行处理；若需要也可写提示用名

                        AIRequest.Message systemMessage = new AIRequest.Message();
                        systemMessage.setRole("system");
                        systemMessage.setContent(systemPromptContent);
                        aiRequest.getMessages().add(systemMessage);

                        AIRequest.Message userMessage = new AIRequest.Message();
                        userMessage.setRole("user");
                        userMessage.setContent(promptRef.get());
                        aiRequest.getMessages().add(userMessage);

                        aiRequest.setTemperature(0.8);
                        aiRequest.setMaxTokens(200000);

                        return Flux.defer(() -> {
                                    var provider = aiService.createProviderByConfigId(userId, publicModelConfigId);
                                    return provider.generateContentStream(aiRequest);
                                })
                                .doOnSubscribe(sub -> log.info("模型流已订阅(公共配置ID), userId: {}, novelId: {}, configId: {}", userId, novelId, publicModelConfigId))
                                .filter(content -> !"heartbeat".equals(content))
                                .onErrorResume(err -> {
                                    log.error("公共配置生成流失败: {}", err.getMessage(), err);
                                    return Flux.error(err);
                                });
                    }

                    // 使用私人模型配置（原有逻辑）
                    Mono<UserAIModelConfig> cfgMono = Mono.justOrEmpty(request.getAiConfigId())
                            .filter(id -> !id.isBlank())
                            .flatMap(id -> userAIModelConfigService.getConfigurationById(userId, id)
                                    .doOnNext(c -> log.info("使用指定内容模型配置: {} (provider={}, model={})", id, c.getProvider(), c.getModelName()))
                                    .switchIfEmpty(userAIModelConfigService.getValidatedDefaultConfiguration(userId)))
                            .switchIfEmpty(userAIModelConfigService.getValidatedDefaultConfiguration(userId))
                            .switchIfEmpty(Mono.error(new RuntimeException("未找到有效的AI模型配置")));

                    return cfgMono.flatMapMany(aiConfig -> {
                                AIRequest aiRequest = new AIRequest();
                                aiRequest.setUserId(userId);
                                aiRequest.setNovelId(novelId);
                                aiRequest.setModel(aiConfig.getModelName());
                                aiRequest.setFeatureType(AIFeatureType.SUMMARY_TO_SCENE);

                                // 创建系统消息
                                AIRequest.Message systemMessage = new AIRequest.Message();
                                systemMessage.setRole("system");
                                systemMessage.setContent(systemPromptContent); // 使用从PromptService获取的系统提示
                                aiRequest.getMessages().add(systemMessage);

                                // 创建用户消息
                                AIRequest.Message userMessage = new AIRequest.Message();
                                userMessage.setRole("user");
                                userMessage.setContent(promptRef.get()); // 使用填充好的用户模板
                                aiRequest.getMessages().add(userMessage);

                                // 设置生成参数 - 场景生成可以设置稍高的温度以增加创意性
                                aiRequest.setTemperature(0.8);
                                aiRequest.setMaxTokens(200000);

                                // 获取AI模型提供商并调用流式生成
                                return getOrCreateAIModelProvider(userId, aiConfig)
                                        .doOnNext(provider -> log.info("获取到AI模型提供商: {}, 小说ID: {}", 
                                                                     provider.getClass().getSimpleName(), novelId))
                                        .flatMapMany(provider -> {
                                            return provider.generateContentStream(aiRequest)
                                                    .doOnSubscribe(sub -> {
                                                        log.info("模型流已订阅, userId: {}, novelId: {}", userId, novelId);
                                                    })
                                                    .filter(content -> !"heartbeat".equals(content))
                                                    .doOnCancel(() -> {
                                                        log.info("流被取消，允许模型后台继续生成, userId: {}, novelId: {}", userId, novelId);
                                                    });
                                        });
                            });
                })
                .onErrorResume(e -> {
                    log.error("生成场景内容时出错", e);
                    if (e instanceof AccessDeniedException) {
                        return Flux.error(e); // Propagate AccessDeniedException
                    }
                    return Flux.just("生成场景内容时出错: " + e.getMessage(), "[DONE]");
                });
    }

    /**
     * 根据摘要生成场景内容 (非流式)
     *
     * @param userId 用户ID
     * @param novelId 小说ID
     * @param request 生成场景请求参数
     * @return 包含生成场景内容的响应
     */
    @Override
    public Mono<GenerateSceneFromSummaryResponse> generateSceneFromSummary(String userId, String novelId, GenerateSceneFromSummaryRequest request) {
        log.info("根据摘要生成场景内容(非流式), userId: {}, novelId: {}", userId, novelId);

        // 使用流式API并收集结果
        return generateSceneFromSummaryStream(userId, novelId, request)
                .filter(chunk -> !"[DONE]".equals(chunk)) // Filter out the DONE marker
                .collect(StringBuilder::new, StringBuilder::append)
                .map(sb -> {
                    GenerateSceneFromSummaryResponse response = new GenerateSceneFromSummaryResponse();
                    response.setContent(sb.toString());
                    // 如果有场景ID，设置场景ID
                    if(request.getSceneId() != null) {
                        response.setSceneId(request.getSceneId());
                    }
                    return response;
                });
    }

    /**
     * 获取当前用户ID
     */
    private Mono<String> getCurrentUserId() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .filter(Authentication::isAuthenticated)
            .map(Authentication::getPrincipal)
            .cast(com.ainovel.server.domain.model.User.class)
            .map(user -> user.getId())
            .defaultIfEmpty("anonymous") // 给一个默认值，避免空指针
            .onErrorResume(e -> {
                log.warn("获取当前用户ID出错: {}", e.getMessage());
                return Mono.just("anonymous");
            });
    }

    /**
     * 获取 NovelService (避免循环依赖)
     */
    private NovelService getNovelService() {
        return this.novelService;
    }


    /**
     * 根据配置ID获取AI模型提供商
     * @param userId 用户ID
     * @param configId 配置ID
     * @return AI模型提供商
     */
    @Override
    public Mono<AIModelProvider> getAIModelProviderByConfigId(String userId, String configId) {
        log.info("获取 {} 的AI模型提供商，通过配置ID: {}", userId, configId);
        return Mono.fromCallable(() -> aiService.createProviderByConfigId(userId, configId))
                .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic())
                .switchIfEmpty(Mono.error(new RuntimeException("无法根据配置ID创建Provider: " + configId)))
                .onErrorResume(e -> Mono.error(new RuntimeException("创建Provider失败: " + e.getMessage(), e)));
    }

    // --- NEW METHOD IMPLEMENTATION --- 
    @Override
    public Mono<String> generateNextSingleSummary(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle) {
        log.info("生成下一个单章摘要, userId={}, novelId={}, configId={}, contextLength={}, style=\'{}\'",
                 userId, novelId, aiConfigIdSummary != null ? aiConfigIdSummary : "default", 
                 currentContext != null ? currentContext.length() : 0, writingStyle != null ? writingStyle : "none");
        
        // 如果上下文为空，返回错误
        if (currentContext == null || currentContext.isEmpty()) {
            log.error("上下文内容为空，无法生成下一章摘要");
            return Mono.error(new IllegalArgumentException("上下文内容不能为空"));
        }

        // 1. 获取AI配置
        Mono<UserAIModelConfig> configMono = Mono.justOrEmpty(aiConfigIdSummary)
            .flatMap(configId -> userAIModelConfigService.getConfigurationById(userId, configId))
            .switchIfEmpty(userAIModelConfigService.getValidatedDefaultConfiguration(userId))
            .switchIfEmpty(Mono.error(new RuntimeException("无法找到有效的AI配置")));

        // 2. 使用NovelRagAssistant检索相关上下文和设定
        //Mono<String> relevantContextMono = novelRagAssistant.retrieveRelevantContext(novelId, currentContext);
        //Mono<String> relevantSettingsMono = novelRagAssistant.retrieveRelevantSettings(novelId, currentContext);

        // 3. 构建作者引导（如果有写作风格）
        String authorGuidance = "";
        if (writingStyle != null && !writingStyle.isEmpty()) {
            authorGuidance = "写作风格: " + writingStyle;
        }

        // 4. 整合所有信息并生成请求
        String finalAuthorGuidance = authorGuidance;
        return configMono
            .flatMap(config -> {
                
                // 4.1 获取配置ID
                String configId = config.getId();
                
                // 4.2 生成一个UUID作为临时选项ID
                String optionId = UUID.randomUUID().toString();
                
                // 4.3 构建完整上下文
                StringBuilder enrichedContext = new StringBuilder(currentContext);
                
//                // 添加检索到的上下文（如果有）
//                if (!relevantContext.isEmpty()) {
//                    enrichedContext.append("\\n\\n## 相关上下文\\n\\n").append(relevantContext);
//                }
//
//                // 添加设定信息（如果有）
//                if (!relevantSettings.isEmpty()) {
//                    enrichedContext.append("\\n\\n## 相关设定\\n\\n").append(relevantSettings);
//                }
                
                // 4.4 使用NextOutline生成逻辑生成单个大纲选项
                return generateSingleOutlineOptionStream(
                        userId, 
                        novelId, 
                        enrichedContext.toString(), 
                        finalAuthorGuidance, 
                        0, // 单一选项时索引为0
                        configId
                    )
                    .reduce(new StringBuilder(), (sb, chunk) -> {
                        if (chunk.getError() != null) {
                            log.error("生成摘要出错: {}", chunk.getError());
                            throw new RuntimeException("生成摘要失败: " + chunk.getError());
                        }
                        return sb.append(chunk.getTextChunk());
                    })
                    .map(StringBuilder::toString)
                    .flatMap(outlineContent -> {
                        // 5. 解析生成的内容，提取出适合作为章节摘要的部分
                        return processOutlineToSummary(outlineContent);
                    })
                    .doOnSuccess(summary -> {
                        // 避免打印正文片段，改为仅打印长度
                        log.info("成功生成下一章摘要, 长度: {}", summary.length());
                    })
                    .onErrorResume(e -> {
                        log.error("生成下一章摘要失败: {}", e.getMessage(), e);
                        return Mono.error(new RuntimeException("生成摘要失败: " + e.getMessage()));
                    });
            });
    }

    @Override
    public Flux<String> generateNextSingleSummaryStream(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle, String summaryPromptTemplateId, String publicModelConfigId) {
        // 构建用于摘要的大纲请求（重用 createSingleOutlineGenerationRequest + processProviderStream）
        if (currentContext == null || currentContext.isEmpty()) {
            return Flux.error(new IllegalArgumentException("上下文内容不能为空"));
        }
        String authorGuidance = (writingStyle != null && !writingStyle.isEmpty()) ? ("写作风格: " + writingStyle) : "";
        StringBuilder enrichedContext = new StringBuilder(currentContext);

        Mono<AIRequest> reqMono;
        if (summaryPromptTemplateId != null && !summaryPromptTemplateId.isBlank()) {
            reqMono = promptService.getPromptTemplateById(userId, summaryPromptTemplateId)
                .map(t -> {
                    String sys = t.getSystemPrompt();
                    String usr = t.getUserPrompt();
                    if (usr == null || usr.isBlank()) {
                        usr = promptService.getSingleOutlineGenerationPrompt().block();
                    }
                AIRequest req = new AIRequest();
                    req.setUserId(userId);
                    req.setNovelId(novelId);
                req.setFeatureType(AIFeatureType.NOVEL_COMPOSE);
                    AIRequest.Message sysMsg = new AIRequest.Message();
                    sysMsg.setRole("system");
                    sysMsg.setContent((sys != null && !sys.isBlank()) ? sys : "你是一位专业的小说创作顾问。");
                    req.getMessages().add(sysMsg);
                    AIRequest.Message userMsg = new AIRequest.Message();
                    userMsg.setRole("user");
                    userMsg.setContent(usr.replace("{{context}}", enrichedContext.toString()).replace("{{authorGuidance}}", authorGuidance));
                    req.getMessages().add(userMsg);
                    req.setTemperature(0.75);
                    req.setMaxTokens(200000);
                    return req;
                })
                .switchIfEmpty(createSingleOutlineGenerationRequest(userId, novelId, enrichedContext.toString(), authorGuidance));
        } else {
            reqMono = createSingleOutlineGenerationRequest(userId, novelId, enrichedContext.toString(), authorGuidance);
        }

        if (publicModelConfigId != null && !publicModelConfigId.isBlank()) {
            return reqMono.flatMapMany(request -> {
                request.setUserId(userId);
                var provider = aiService.createProviderByConfigId(userId, publicModelConfigId);
                return provider.generateContentStream(request)
                        .filter(content -> !"heartbeat".equalsIgnoreCase(content))
                        .onErrorResume(err -> Flux.error(new RuntimeException("公共配置生成失败: " + err.getMessage(), err)));
            });
        }

        Mono<UserAIModelConfig> configMono = Mono.justOrEmpty(aiConfigIdSummary)
            .flatMap(configId -> userAIModelConfigService.getConfigurationById(userId, configId))
            .switchIfEmpty(userAIModelConfigService.getValidatedDefaultConfiguration(userId))
            .switchIfEmpty(Mono.error(new RuntimeException("无法找到有效的AI配置")));

        return reqMono.flatMapMany(req -> configMono.flatMapMany(cfg -> getOrCreateAIModelProvider(userId, cfg)
            .flatMapMany(provider -> provider.generateContentStream(req)
                .filter(content -> !"heartbeat".equalsIgnoreCase(content))
            )));
    }

    /**
     * 处理大纲内容，提取出适合作为章节摘要的部分
     */
    private Mono<String> processOutlineToSummary(String outlineContent) {
        if (outlineContent == null || outlineContent.isEmpty()) {
            return Mono.error(new RuntimeException("生成的大纲内容为空"));
        }
        
        // 尝试提取标题和内容
        Pattern titleContentPattern = Pattern.compile(
            "(?im)^\\s*(标题|TITLE|Title)\\s*[:\\：]\\s*(.*?)\\s*(?:\\n|$)\\s*(内容|CONTENT|Content)\\s*[:\\：]\\s*(.+)", 
            Pattern.DOTALL
        );
        
        Matcher titleContentMatcher = titleContentPattern.matcher(outlineContent);
        if (titleContentMatcher.find()) {
            // 如果匹配到标准的\"标题:...内容:...\"格式，提取内容部分
            String content = titleContentMatcher.group(4).trim();
            return Mono.just(content);
        }
        
        // 尝试识别大纲格式的内容
        Pattern outlinePattern = Pattern.compile("(?im)^\\s*(选项|大纲|剧情选项)\\s*\\d+\\s*[:\\：]\\s*(.+)$", Pattern.DOTALL);
        Matcher outlineMatcher = outlinePattern.matcher(outlineContent);
        if (outlineMatcher.find()) {
            String content = outlineMatcher.group(2).trim();
            return Mono.just(content);
        }
        
        // 如果没有找到特定格式，检查内容长度是否合理
        if (outlineContent.length() > 1000) {
            // 内容太长，可能不是摘要，进行简单截取
            return Mono.just(outlineContent.substring(0, 1000) + "...");
        }
        
        // 都不满足时，返回原始内容
        return Mono.just(outlineContent.trim());
    }

    /**
     * 获取与场景相关的设定信息
     * 
     * @param novelId 小说ID
     * @param summary 场景摘要
     * @param chapterId 章节ID
     * @return 相关设定信息的Mono
     */
    private Mono<String> getRelevantSettings(String novelId, String summary, String chapterId) {
        // 默认获取前5个最相关的设定
        int topK = 5;
        
        // 从摘要中提取上下文
        String contextText = RichTextUtil.deltaJsonToPlainText(summary != null ? summary : "");
        
        // 调用设定检索服务
        return novelSettingService.findRelevantSettings(novelId, contextText, chapterId, null, topK)
            .collectList()
            .map(settingItems -> {
                if (settingItems.isEmpty()) {
                    log.info("未找到与摘要相关的设定项, 小说ID: {}", novelId);
                    return "";
                }
                
                log.info("找到 {} 个与摘要相关的设定项, 小说ID: {}", settingItems.size(), novelId);
                
                // 格式化设定项为文本
                StringBuilder formattedSettings = new StringBuilder("## 相关设定信息\n\n");
                
                for (int i = 0; i < settingItems.size(); i++) {
                    NovelSettingItem item = settingItems.get(i);
                    formattedSettings.append(i + 1).append(". **").append(item.getName()).append("** (")
                        .append(item.getType()).append(")\n")
                        .append(item.getDescription()).append("\n\n");
                }
                
                return formattedSettings.toString();
            })
            .onErrorResume(e -> {
                log.error("获取相关设定时出错, 小说ID: {}, 错误: {}", novelId, e.getMessage());
                return Mono.just(""); // 发生错误时返回空字符串
            });
    }

    /**
     * 根据请求中的 aiConfigId 或用户默认配置解析 AI 配置
     */
    private Mono<UserAIModelConfig> resolveAiConfig(String userId, SummarizeSceneRequest request) {
        if (request != null && request.getAiConfigId() != null && !request.getAiConfigId().isBlank()) {
            return userAIModelConfigService.getConfigurationById(userId, request.getAiConfigId());
        }
        return userAIModelConfigService.getValidatedDefaultConfiguration(userId);
    }

    @Override
    public Mono<String> generateNextSingleSummaryWithTemplate(String userId, String novelId, String currentContext, String aiConfigIdSummary, String writingStyle, String summaryPromptTemplateId) {
        if (summaryPromptTemplateId == null || summaryPromptTemplateId.isBlank()) {
            return generateNextSingleSummary(userId, novelId, currentContext, aiConfigIdSummary, writingStyle);
        }
        if (currentContext == null || currentContext.isEmpty()) {
            return Mono.error(new IllegalArgumentException("上下文内容不能为空"));
        }
        Mono<UserAIModelConfig> configMono = Mono.justOrEmpty(aiConfigIdSummary)
            .flatMap(configId -> userAIModelConfigService.getConfigurationById(userId, configId))
            .switchIfEmpty(userAIModelConfigService.getValidatedDefaultConfiguration(userId))
            .switchIfEmpty(Mono.error(new RuntimeException("无法找到有效的AI配置")));
        String authorGuidance = (writingStyle != null && !writingStyle.isEmpty()) ? ("写作风格: " + writingStyle) : "";
        String finalAuthorGuidance = authorGuidance;
        StringBuilder enrichedContext = new StringBuilder(currentContext);
        String optionId = UUID.randomUUID().toString();
        return configMono.flatMapMany(config ->
            promptService.getPromptTemplateById(userId, summaryPromptTemplateId)
                .map(t -> {
                    String sys = t.getSystemPrompt();
                    String usr = t.getUserPrompt();
                    if (usr == null || usr.isBlank()) {
                        usr = promptService.getSingleOutlineGenerationPrompt().block();
                    }
                    try {
                        String prompt = usr
                            .replace("{{context}}", enrichedContext.toString())
                            .replace("{{authorGuidance}}", finalAuthorGuidance == null ? "" : finalAuthorGuidance);
                AIRequest req = new AIRequest();
                        req.setUserId(userId);
                        req.setNovelId(novelId);
                req.setFeatureType(AIFeatureType.NOVEL_COMPOSE);
                        AIRequest.Message sysMsg = new AIRequest.Message();
                        sysMsg.setRole("system");
                        sysMsg.setContent((sys != null && !sys.isBlank()) ? sys : "你是一位专业的小说创作顾问。");
                        req.getMessages().add(sysMsg);
                        AIRequest.Message userMsg = new AIRequest.Message();
                        userMsg.setRole("user");
                        userMsg.setContent(prompt);
                        req.getMessages().add(userMsg);
                        req.setTemperature(0.75);
                        req.setMaxTokens(200000);
                        return req;
                    } catch (Exception e) {
                        log.warn("应用摘要模板占位符失败，回退默认模板: {}", e.getMessage());
                        return createSingleOutlineGenerationRequest(userId, novelId, enrichedContext.toString(), finalAuthorGuidance).block();
                    }
                })
                .switchIfEmpty(createSingleOutlineGenerationRequest(userId, novelId, enrichedContext.toString(), finalAuthorGuidance))
                .flatMapMany(req -> getAIModelProviderByConfigId(userId, config.getId())
                    .flatMapMany(provider -> processProviderStream(provider, req, optionId, 0)))
        )
        .reduce(new StringBuilder(), (sb, chunk) -> {
            if (chunk.getError() != null) {
                log.error("生成摘要出错: {}", chunk.getError());
                throw new RuntimeException("生成摘要失败: " + chunk.getError());
            }
            return sb.append(chunk.getTextChunk());
        })
        .map(StringBuilder::toString)
        .flatMap(this::processOutlineToSummary);
    }
}

