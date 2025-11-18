package com.ainovel.server.service.impl;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.mongodb.ReactiveMongoTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import com.mongodb.client.result.UpdateResult;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.domain.model.SystemConfig;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.domain.model.billing.PreDeductionRecord;
import com.ainovel.server.repository.PreDeductionRecordRepository;
import com.ainovel.server.service.TokenEstimationService;
import com.ainovel.server.repository.PublicModelConfigRepository;
import com.ainovel.server.repository.SystemConfigRepository;
import com.ainovel.server.repository.UserRepository;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.repository.ModelPricingRepository;

import reactor.core.publisher.Mono;
import lombok.extern.slf4j.Slf4j;

/**
 * 积分管理服务实现
 */
@Service
@Slf4j
public class CreditServiceImpl implements CreditService {
    
    private final UserRepository userRepository;
    private final SystemConfigRepository systemConfigRepository;
    private final PublicModelConfigRepository publicModelConfigRepository;
    private final ModelPricingRepository modelPricingRepository;
    private final ReactiveMongoTemplate mongoTemplate;
    private final ReactiveMongoTransactionManager transactionManager;
    private final PreDeductionRecordRepository preDeductionRecordRepository;
    private final TokenEstimationService tokenEstimationService;
    
    // 默认配置常量
    private static final double DEFAULT_CREDIT_TO_USD_RATE = 200.0; // 1美元 = 200积分 (即1积分 = 0.005美元)
    private static final long DEFAULT_NEW_USER_CREDITS = 200L; // 新用户赠送200积分
    // 输出token估算上限：3-4千字量级（近似），按4000 tokens封顶
    private static final int MAX_ESTIMATED_OUTPUT_TOKENS = 4000;
    
    @Autowired
    public CreditServiceImpl(UserRepository userRepository, 
                           SystemConfigRepository systemConfigRepository,
                           PublicModelConfigRepository publicModelConfigRepository,
                           ModelPricingRepository modelPricingRepository,
                           ReactiveMongoTemplate mongoTemplate,
                           ReactiveMongoTransactionManager transactionManager,
                           PreDeductionRecordRepository preDeductionRecordRepository,
                           TokenEstimationService tokenEstimationService) {
        this.userRepository = userRepository;
        this.systemConfigRepository = systemConfigRepository;
        this.publicModelConfigRepository = publicModelConfigRepository;
        this.modelPricingRepository = modelPricingRepository;
        this.mongoTemplate = mongoTemplate;
        this.transactionManager = transactionManager;
        this.preDeductionRecordRepository = preDeductionRecordRepository;
        this.tokenEstimationService = tokenEstimationService;
    }
    
    @Override
    public Mono<Boolean> deductCredits(String userId, long amount) {
        if (amount <= 0L) {
            return Mono.just(true);
        }
        Query query = new Query(Criteria.where("_id").is(userId).and("credits").gte(amount));
        Update update = new Update()
                .inc("credits", -amount)
                .inc("totalCreditsUsed", amount);
        return mongoTemplate.updateFirst(query, update, User.class)
                .map(UpdateResult::getModifiedCount)
                .map(modified -> modified != null && modified > 0)
                // 添加对MongoDB事务冲突的重试机制
                .retryWhen(reactor.util.retry.Retry.max(3)
                        .filter(err -> {
                            String m = err.getMessage() != null ? err.getMessage() : "";
                            return m.contains("WriteConflict") || 
                                   m.contains("TransientTransactionError") || 
                                   m.contains("112");
                        })
                        .doBeforeRetry(retrySignal -> {
                            log.warn("积分扣减遇到事务冲突，正在重试: userId={}, amount={}, 重试次数={}", 
                                    userId, amount, retrySignal.totalRetries() + 1);
                        })
                );
    }
    
    @Override
    public Mono<Boolean> addCredits(String userId, long amount, String reason) {
        if (amount == 0L) {
            return Mono.just(true);
        }
        Query query = new Query(Criteria.where("_id").is(userId));
        Update update = new Update().inc("credits", amount);
        return mongoTemplate.updateFirst(query, update, User.class)
                .map(UpdateResult::getModifiedCount)
                .map(modified -> modified != null && modified > 0)
                // 添加对MongoDB事务冲突的重试机制
                .retryWhen(reactor.util.retry.Retry.max(3)
                        .filter(err -> {
                            String m = err.getMessage() != null ? err.getMessage() : "";
                            return m.contains("WriteConflict") || 
                                   m.contains("TransientTransactionError") || 
                                   m.contains("112");
                        })
                        .doBeforeRetry(retrySignal -> {
                            log.warn("积分增加遇到事务冲突，正在重试: userId={}, amount={}, reason={}, 重试次数={}", 
                                    userId, amount, reason, retrySignal.totalRetries() + 1);
                        })
                );
    }
    
    @Override
    public Mono<Long> getUserCredits(String userId) {
        return userRepository.findById(userId)
                .map(user -> user.getCredits() != null ? user.getCredits() : 0L)
                .defaultIfEmpty(0L);
    }
    
    @Override
    public Mono<Long> calculateCreditCost(String provider, String modelId, AIFeatureType featureType, int inputTokens, int outputTokens) {
        return Mono.zip(
                getModelPricing(provider, modelId),
                getPublicModelConfig(provider, modelId),
                getCreditToUsdRate()
        ).map(tuple -> {
            ModelPricing modelPricing = tuple.getT1();
            PublicModelConfig config = tuple.getT2();
            double creditRate = tuple.getT3();
            
            // 验证模型是否支持该功能
            if (!config.isEnabledForFeature(featureType)) {
                throw new IllegalArgumentException("模型 " + provider + ":" + modelId + " 不支持功能: " + featureType);
            }
            
            // 计算美元成本
            double usdCost = modelPricing.calculateTotalCost(inputTokens, outputTokens);
            
            // 应用积分汇率乘数
            double multiplier = config.getCreditRateMultiplier() != null ? config.getCreditRateMultiplier() : 1.0;
            
            // 转换为积分并向上取整
            long creditCost = Math.round(Math.ceil(usdCost * creditRate * multiplier));

            // 诊断日志：帮助排查预估与实际差距
            try {
                Double unified = modelPricing.getUnifiedPricePerThousandTokens();
                Double inP = modelPricing.getInputPricePerThousandTokens();
                Double outP = modelPricing.getOutputPricePerThousandTokens();
                log.info("💡 [CostCalc] provider={}, modelId={}, featureType={}, inTokens={}, outTokens={}, pricing(unified={}, input={}, output={}), creditRate={}, multiplier={}, usdCost={}, creditCost(beforeMin)={}",
                        provider, modelId, featureType, inputTokens, outputTokens,
                        unified, inP, outP, creditRate, multiplier, usdCost, creditCost);
            } catch (Exception ignore) {}
            
            return Math.max(1L, creditCost); // 最小消费1积分
        });
    }
    
    @Override
    public Mono<Boolean> hasEnoughCredits(String userId, String provider, String modelId, AIFeatureType featureType, int estimatedInputTokens, int estimatedOutputTokens) {
        return Mono.zip(
                getUserCredits(userId),
                calculateCreditCost(provider, modelId, featureType, estimatedInputTokens, estimatedOutputTokens)
        ).map(tuple -> tuple.getT1() >= tuple.getT2());
    }
    
    @Override
    public Mono<CreditDeductionResult> deductCreditsForAI(String userId, String provider, String modelId, AIFeatureType featureType, int inputTokens, int outputTokens) {
        return calculateCreditCost(provider, modelId, featureType, inputTokens, outputTokens)
                .flatMap(creditCost -> 
                    deductCredits(userId, creditCost)
                            .map(success -> {
                                if (success) {
                                    return CreditDeductionResult.success(creditCost);
                                } else {
                                    return CreditDeductionResult.failure("积分余额不足，需要 " + creditCost + " 积分");
                                }
                            })
                )
                .onErrorResume(throwable -> 
                    Mono.just(CreditDeductionResult.failure("积分扣减失败: " + throwable.getMessage()))
                );
    }
    
    @Override
    public Mono<Double> getCreditToUsdRate() {
        return systemConfigRepository.findByConfigKey(SystemConfig.Keys.CREDIT_TO_USD_RATE)
                .map(config -> {
                    Double rate = config.getNumericValue();
                    return rate != null ? rate : DEFAULT_CREDIT_TO_USD_RATE;
                })
                .defaultIfEmpty(DEFAULT_CREDIT_TO_USD_RATE);
    }
    
    @Override
    @Transactional
    public Mono<Boolean> setCreditToUsdRate(double rate) {
        return systemConfigRepository.findByConfigKey(SystemConfig.Keys.CREDIT_TO_USD_RATE)
                .switchIfEmpty(createDefaultCreditRateConfig())
                .flatMap(config -> {
                    config.setConfigValue(String.valueOf(rate));
                    config.setUpdatedAt(java.time.LocalDateTime.now());
                    return systemConfigRepository.save(config);
                })
                .thenReturn(true)
                .onErrorReturn(false);
    }
    
    @Override
    @Transactional
    public Mono<Boolean> grantNewUserCredits(String userId) {
        return systemConfigRepository.findByConfigKey(SystemConfig.Keys.NEW_USER_CREDITS)
                .map(config -> {
                    Long credits = config.getLongValue();
                    return credits != null ? credits : DEFAULT_NEW_USER_CREDITS;
                })
                .defaultIfEmpty(DEFAULT_NEW_USER_CREDITS)
                .flatMap(credits -> addCredits(userId, credits, "新用户注册赠送"));
    }
    
    private Mono<ModelPricing> getModelPricing(String provider, String modelId) {
        log.debug("🔍 查找模型定价信息: provider={}, modelId={}", provider, modelId);
        
        return modelPricingRepository.findByProviderAndModelId(provider, modelId)
                .cast(ModelPricing.class)
                .switchIfEmpty(findFallbackPricing(provider, modelId))
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模型定价信息不存在: " + provider + ":" + modelId)));
    }
    
    /**
     * 查找备选定价信息的fallback逻辑
     * 1. 先在其他提供商中查找相同模型ID和名称的定价
     * 2. 如果没找到，尝试前缀匹配
     */
    private Mono<ModelPricing> findFallbackPricing(String provider, String modelId) {
        log.info("⚠️ 未找到精确定价信息 {}:{}, 开始查找备选方案", provider, modelId);
        
        // 第一步：在其他提供商中查找相同模型ID的定价
        return modelPricingRepository.findByModelIdAndActiveTrue(modelId)
                .filter(pricing -> !provider.equals(pricing.getProvider())) // 排除当前提供商
                .next()
                .flatMap(existingPricing -> {
                    log.info("✅ 在其他提供商中找到相同模型ID的定价: {}:{} -> {}:{}", 
                            provider, modelId, existingPricing.getProvider(), existingPricing.getModelId());
                    return createFallbackPricing(provider, modelId, existingPricing, "相同模型ID");
                })
                // 第二步：如果没找到相同模型ID，尝试根据模型名称查找
                .switchIfEmpty(findByModelName(provider, modelId))
                // 第三步：如果仍未找到，尝试前缀匹配
                .switchIfEmpty(findByPrefixMatch(provider, modelId));
    }
    
    /**
     * 根据模型名称查找定价
     */
    private Mono<ModelPricing> findByModelName(String provider, String modelId) {
        return modelPricingRepository.findByModelNameAndActiveTrue(modelId)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .flatMap(existingPricing -> {
                    log.info("✅ 根据模型名称找到定价: {}:{} -> {}:{}", 
                            provider, modelId, existingPricing.getProvider(), existingPricing.getModelName());
                    return createFallbackPricing(provider, modelId, existingPricing, "相同模型名称");
                });
    }
    
    /**
     * 前缀匹配查找定价
     */
    private Mono<ModelPricing> findByPrefixMatch(String provider, String modelId) {
        // 提取前缀（比如 deepseek-r1 -> deepseek）
        String prefix = extractModelPrefix(modelId);
        if (prefix.length() < 3) { // 前缀太短，不进行匹配
            return Mono.empty();
        }
        
        return modelPricingRepository.findByModelIdStartingWithIgnoreCase(prefix)
                .filter(pricing -> !provider.equals(pricing.getProvider()))
                .next()
                .flatMap(existingPricing -> {
                    log.info("✅ 通过前缀匹配找到定价: {}:{} -> {}:{} (前缀: {})", 
                            provider, modelId, existingPricing.getProvider(), existingPricing.getModelId(), prefix);
                    return createFallbackPricing(provider, modelId, existingPricing, "前缀匹配: " + prefix);
                });
    }
    
    /**
     * 创建备选定价信息
     */
    private Mono<ModelPricing> createFallbackPricing(String provider, String modelId, ModelPricing existingPricing, String fallbackReason) {
        ModelPricing fallbackPricing = ModelPricing.builder()
                .provider(provider)
                .modelId(modelId)
                .modelName(modelId)
                .inputPricePerThousandTokens(existingPricing.getInputPricePerThousandTokens())
                .outputPricePerThousandTokens(existingPricing.getOutputPricePerThousandTokens())
                .unifiedPricePerThousandTokens(existingPricing.getUnifiedPricePerThousandTokens())
                .maxContextTokens(existingPricing.getMaxContextTokens())
                .supportsStreaming(existingPricing.getSupportsStreaming())
                .description("自动生成的备选定价 - 基于 " + existingPricing.getProvider() + ":" + existingPricing.getModelId() + " (" + fallbackReason + ")")
                .additionalPricing(existingPricing.getAdditionalPricing())
                .source(ModelPricing.PricingSource.DEFAULT)
                .createdAt(java.time.LocalDateTime.now())
                .updatedAt(java.time.LocalDateTime.now())
                .version(1)
                .active(true)
                .build();
        
        // 保存到数据库以供后续使用
        return modelPricingRepository.save(fallbackPricing)
                .doOnSuccess(saved -> log.info("💾 保存备选定价信息: {}:{}", provider, modelId));
    }
    
    /**
     * 提取模型前缀
     * 例如：deepseek-r1 -> deepseek, gpt-4o-mini -> gpt-4, claude-3-opus -> claude-3
     */
    private String extractModelPrefix(String modelId) {
        if (modelId == null || modelId.isEmpty()) {
            return "";
        }
        
        // 常见的分隔符
        String[] separators = {"-", "_", "."};
        
        for (String separator : separators) {
            int index = modelId.indexOf(separator);
            if (index > 0) {
                return modelId.substring(0, index);
            }
        }
        
        // 如果没有分隔符，返回前一半
        int halfLength = modelId.length() / 2;
        return halfLength > 2 ? modelId.substring(0, halfLength) : modelId;
    }
    
    private Mono<PublicModelConfig> getPublicModelConfig(String provider, String modelId) {
        return publicModelConfigRepository.findByProviderAndModelId(provider, modelId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("模型配置不存在或未开放: " + provider + ":" + modelId)));
    }
    
    private Mono<SystemConfig> createDefaultCreditRateConfig() {
        SystemConfig config = SystemConfig.builder()
                .configKey(SystemConfig.Keys.CREDIT_TO_USD_RATE)
                .configValue(String.valueOf(DEFAULT_CREDIT_TO_USD_RATE))
                .description("积分与美元的汇率（1美元等于多少积分）")
                .configType(SystemConfig.ConfigType.NUMBER)
                .configGroup("credit")
                .enabled(true)
                .createdAt(java.time.LocalDateTime.now())
                .updatedAt(java.time.LocalDateTime.now())
                .build();
        
        return systemConfigRepository.save(config);
    }

    @Override
    public Mono<CreditValidationResult> validateCreditsForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType) {
        try {
            String userId = aiRequest.getUserId();
            
            // 🚀 重构：直接在CreditService中进行内容长度估算和积分计算，避免循环依赖
            Mono<Long> userCreditsMono = getUserCredits(userId);
            Mono<Long> estimatedCostMono = estimateCreditsForAIRequest(aiRequest, publicModel, featureType);
            
            return Mono.zip(userCreditsMono, estimatedCostMono)
                    .map(tuple -> {
                        long currentCredits = tuple.getT1();
                        long estimatedCost = tuple.getT2();
                        
                        if (currentCredits < estimatedCost) {
                            return CreditValidationResult.failure(currentCredits, estimatedCost, 
                                    String.format("积分余额不足，需要 %d 积分，当前余额 %d 积分", estimatedCost, currentCredits));
                        }
                        
                        return CreditValidationResult.success(currentCredits, estimatedCost, null, null);
                    })
                    .onErrorReturn(CreditValidationResult.success(0, 0)); // 出错时返回通过结果
        } catch (Exception e) {
            // 异常时返回通过结果，避免阻止正常流程
            return Mono.just(CreditValidationResult.success(0, 0));
        }
    }
    
    /**
     * 🚀 新增：直接在CreditService中进行AIRequest的积分预估
     * 避免对CostEstimationService的循环依赖
     */
    @Override
    public Mono<Long> estimateCreditsForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType) {
        // 检查模型是否启用 - 🚀 修复：确保最小预估费用至少为1积分
        if (!publicModel.getEnabled()) {
            log.warn("公共模型未启用，返回最小预估费用1积分: provider={}, modelId={}", 
                publicModel.getProvider(), publicModel.getModelId());
            return Mono.just(1L);
        }
        
        // 检查模型是否支持该功能 - 🚀 修复：确保最小预估费用至少为1积分
        if (!publicModel.isEnabledForFeature(featureType)) {
            log.warn("公共模型不支持该功能，返回最小预估费用1积分: provider={}, modelId={}, featureType={}", 
                publicModel.getProvider(), publicModel.getModelId(), featureType);
            return Mono.just(1L);
        }
        
        // 估算内容长度
        return estimateContentLengthFromAIRequest(aiRequest)
                .flatMap(totalLength -> {
                    log.info("🧮 [Estimate] 估算内容长度: {} 字符, model={}, featureType={}", totalLength, publicModel.getModelId(), featureType);
                    
                    // 估算token数量
                    return tokenEstimationService.estimateTokensByWordCount(totalLength, publicModel.getModelId())
                            .flatMap(inputTokens -> {
                                // 估算输出token（简化估算）
                                int outputTokens = estimateOutputTokens(inputTokens.intValue(), featureType);
                                
                                log.info("🧮 [Estimate] 估算tokens: input={}, output={} (rule={})", inputTokens, outputTokens, featureType);
                                
                                // 计算积分成本
                                return calculateCreditCost(publicModel.getProvider(), publicModel.getModelId(), 
                                        featureType, inputTokens.intValue(), outputTokens)
                                        .map(cost -> Math.max(1L, cost)) // 🚀 确保最小预估费用至少为1积分
                                        .doOnSuccess(cost -> log.info("🧮 [Estimate] 预估积分成本: {} (provider={}, model={}, featureType={}, input={}, output={})",
                                                cost, publicModel.getProvider(), publicModel.getModelId(), featureType, inputTokens, outputTokens));
                            })
                            .onErrorReturn(1L); // Token估算失败时返回最小费用
                })
                .onErrorReturn(1L); // 内容长度估算失败时返回最小费用
    }
    
    /**
     * 基于AIRequest估算内容长度（仅统计发送给模型的对话消息内容）。
     */
    private Mono<Integer> estimateContentLengthFromAIRequest(AIRequest aiRequest) {
        int messagesLength = 0;
        int messageCount = 0;
        if (aiRequest.getMessages() != null) {
            for (AIRequest.Message message : aiRequest.getMessages()) {
                if (message != null && message.getContent() != null) {
                    messagesLength += message.getContent().length();
                }
                messageCount++;
            }
        }
        int finalLength = Math.max(messagesLength, 100); // 保底
        try {
            log.info("🧮 [Estimate] 基于messages估算长度: messages={}, totalLength={}", messageCount, finalLength);
        } catch (Exception ignore) {}
        return Mono.just(finalLength);
    }
    
    /**
     * 估算输出token数量
     */
    private int estimateOutputTokens(int inputTokens, AIFeatureType featureType) {
        int estimated;
        switch (featureType) {
            case NOVEL_GENERATION:
            case PROFESSIONAL_FICTION_CONTINUATION:
            case NOVEL_COMPOSE:
                estimated = Math.max(inputTokens, 1000); // 小说生成通常输出较多
                break;
            case TEXT_SUMMARY:
            case SCENE_TO_SUMMARY:
                estimated = Math.min(inputTokens / 2, 500); // 摘要通常较短
                break;
            case SETTING_TREE_GENERATION:
            case SCENE_BEAT_GENERATION:
                estimated = Math.min(inputTokens, 800); // 设定生成中等长度
                break;
            case AI_CHAT:
                estimated = Math.min(inputTokens, 600); // 聊天响应中等长度
                break;
            case TEXT_EXPANSION:
                estimated = Math.max(inputTokens * 2, 800); // 扩写通常输出更多
                break;
            case TEXT_REFACTOR:
                estimated = inputTokens; // 重构通常长度相近
                break;
            case SUMMARY_TO_SCENE:
                estimated = Math.max(inputTokens * 3, 1200); // 摘要生成场景通常较长
                break;
            default:
                estimated = Math.min(inputTokens / 2, 500); // 默认中等长度
        }
        // 全局上限：不超过 4000 tokens
        int capped = Math.min(estimated, MAX_ESTIMATED_OUTPUT_TOKENS);
        try { log.info("🧮 [Estimate] 输出token估算: base={}, capped={} (cap={})", estimated, capped, MAX_ESTIMATED_OUTPUT_TOKENS); } catch (Exception ignore) {}
        return capped;
    }

    @Override
    public Mono<PreDeductionResult> preDeductCredits(String traceId, String userId, long estimatedCost, 
                                                    String provider, String modelId, AIFeatureType featureType) {
        log.info("🧾 [PreDeduct] 请求预扣: traceId={}, userId={}, provider={}, modelId={}, featureType={}, estimatedCost={}",
                traceId, userId, provider, modelId, featureType, estimatedCost);
        if (estimatedCost <= 0) {
            return Mono.just(PreDeductionResult.failure(traceId, "预估费用必须大于0"));
        }

        // 使用 TransactionalOperator 管理 Reactive 事务：幂等 -> 扣费 -> 写记录 -> 查余额
        TransactionalOperator operator = TransactionalOperator.create(transactionManager);
        return operator.execute(status ->
                preDeductionRecordRepository.existsByTraceId(traceId)
                        .flatMap(exists -> {
                            if (exists) {
                                log.warn("🧾 [PreDeduct] 已存在预扣费记录，跳过重复预扣: traceId={}", traceId);
                                return Mono.just(PreDeductionResult.failure(traceId, "该请求已存在预扣费记录"));
                            }
                            log.debug("🧾 [PreDeduct] 准备扣减用户余额: userId={}, estimatedCost={}", userId, estimatedCost);
                            Query userQuery = new Query(Criteria.where("_id").is(userId).and("credits").gte(estimatedCost));
                            Update userUpdate = new Update()
                                    .inc("credits", -estimatedCost)
                                    .inc("totalCreditsUsed", estimatedCost);
                            return mongoTemplate.updateFirst(userQuery, userUpdate, User.class)
                                    .flatMap(updateResult -> {
                                        boolean success = updateResult != null && updateResult.getModifiedCount() > 0;
                                        log.info("🧾 [PreDeduct] 扣减余额结果: success={}, modifiedCount={} (userId={}, traceId={})",
                                                success,
                                                updateResult != null ? updateResult.getModifiedCount() : 0,
                                                userId, traceId);
                                        if (!success) {
                                            log.warn("🧾 [PreDeduct] 余额不足或并发冲突导致扣减失败: userId={}, traceId={}, estimatedCost={}",
                                                    userId, traceId, estimatedCost);
                                            return getUserCredits(userId)
                                                    .map(current -> PreDeductionResult.failure(traceId,
                                                            String.format("积分余额不足，需要 %d 积分，当前余额 %d 积分", estimatedCost, current)));
                                        }
                                        PreDeductionRecord record = PreDeductionRecord.builder()
                                                .traceId(traceId)
                                                .userId(userId)
                                                .preDeductedAmount(estimatedCost)
                                                .provider(provider)
                                                .modelId(modelId)
                                                .featureType(featureType)
                                                .status(PreDeductionRecord.Status.PENDING)
                                                .build();
                                        return preDeductionRecordRepository.save(record)
                                                .doOnSuccess(saved -> {
                                                    try {
                                                        log.info("🧾 [PreDeduct] 预扣记录已保存: recordId={}, traceId={}, amount={}, provider={}, modelId={}, featureType={}",
                                                                saved != null ? saved.getId() : null, traceId, estimatedCost, provider, modelId, featureType);
                                                    } catch (Exception ignore) {}
                                                })
                                                .then(getUserCredits(userId)
                                                        .doOnSuccess(remaining -> log.info("🧾 [PreDeduct] 预扣成功: traceId={}, amount={}, 扣后余额remainingCredits={}",
                                                                traceId, estimatedCost, remaining))
                                                        .map(remaining -> PreDeductionResult.success(estimatedCost, remaining, traceId)));
                                    });
                        })
        ).single()
        .doOnSubscribe(sub -> log.debug("🧾 [PreDeduct] 事务开始: traceId={}", traceId))
        .doFinally(sig -> log.debug("🧾 [PreDeduct] 事务结束: traceId={}, signal={}", traceId, sig))
        .retryWhen(reactor.util.retry.Retry.max(10)
                .filter(err -> {
                    String m = err.getMessage() != null ? err.getMessage() : "";
                    return m.contains("WriteConflict") || m.contains("TransientTransactionError") || m.contains("NoSuchTransaction") || m.contains("251") || m.contains("112");
                })
                .doBeforeRetry(rs -> log.warn("[Tx] 预扣费事务重试: traceId={}, 次数={}, 错误={}", traceId, rs.totalRetries() + 1, rs.failure().getMessage()))
        )
        .onErrorResume(error -> {
            log.error("预扣费操作失败: traceId={}, userId={}, estimatedCost={}", traceId, userId, estimatedCost, error);
            return Mono.just(PreDeductionResult.failure(traceId, "预扣费操作失败: " + error.getMessage()));
        });
    }

    @Override
    public Mono<CreditAdjustmentResult> adjustCreditsBasedOnActualUsage(String traceId, int actualInputTokens, int actualOutputTokens) {
        log.info("🧾 [Adjust] 开始费用调整: traceId={}, inputTokens={}, outputTokens={}",
                traceId, actualInputTokens, actualOutputTokens);
        return preDeductionRecordRepository.findByTraceId(traceId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("未找到对应的预扣费记录: " + traceId)))
                .flatMap(record -> {
                    if (record.getStatus() != PreDeductionRecord.Status.PENDING) {
                        log.warn("🧾 [Adjust] 预扣费记录状态异常，跳过调整: traceId={}, status={}", traceId, record.getStatus());
                        return Mono.just(CreditAdjustmentResult.failure(traceId, 
                                "预扣费记录状态异常: " + record.getStatus()));
                    }
                    
                    // 计算实际费用
                    return calculateCreditCost(record.getProvider(), record.getModelId(), 
                            record.getFeatureType(), actualInputTokens, actualOutputTokens)
                            .flatMap(actualCost -> {
                                long preDeductedAmount = record.getPreDeductedAmount();
                                long adjustmentAmount = actualCost - preDeductedAmount;
                                log.info("🧾 [Adjust] 计算费用: traceId={}, preDeducted={}, actualCost={}, diff={}",
                                        traceId, preDeductedAmount, actualCost, adjustmentAmount);
                                
                                String adjustmentType;
                                Mono<Void> adjustmentMono;
                                
                                if (adjustmentAmount > 0) {
                                    // 需要补扣
                                    adjustmentType = "ADDITIONAL_CHARGE";
                                    log.info("🧾 [Adjust] 尝试补扣: traceId={}, userId={}, amount={}",
                                            traceId, record.getUserId(), adjustmentAmount);
                                    adjustmentMono = deductCredits(record.getUserId(), adjustmentAmount)
                                            .flatMap(success -> {
                                                if (!success) {
                                                    log.warn("🧾 [Adjust] 补扣失败(余额不足): traceId={}, userId={}, amount={}",
                                                            traceId, record.getUserId(), adjustmentAmount);
                                                    return Mono.error(new IllegalStateException("补扣费失败，用户余额不足"));
                                                }
                                                log.info("🧾 [Adjust] 补扣成功: traceId={}, userId={}, amount={}",
                                                        traceId, record.getUserId(), adjustmentAmount);
                                                return Mono.<Void>empty();
                                            });
                                } else if (adjustmentAmount < 0) {
                                    // 需要退还
                                    adjustmentType = "REFUND";
                                    long refund = -adjustmentAmount;
                                    log.info("🧾 [Adjust] 尝试退款: traceId={}, userId={}, amount={}",
                                            traceId, record.getUserId(), refund);
                                    adjustmentMono = addCredits(record.getUserId(), refund, 
                                            "AI调用实际费用退还 (traceId: " + traceId + ")")
                                            .doOnSuccess(ok -> log.info("🧾 [Adjust] 退款成功: traceId={}, userId={}, amount={}",
                                                    traceId, record.getUserId(), refund))
                                            .then();
                                } else {
                                    // 费用刚好相等，无需调整
                                    adjustmentType = "NO_ADJUSTMENT";
                                    adjustmentMono = Mono.<Void>empty();
                                }
                                
                                return adjustmentMono
                                        .then(Mono.defer(() -> {
                                            // 更新预扣费记录
                                            record.markAsAdjusted(actualCost, adjustmentAmount, adjustmentType);
                                            return preDeductionRecordRepository.save(record)
                                                    .doOnSuccess(r -> log.info("🧾 [Adjust] 预扣记录已结算: traceId={}, adjustmentType={}, diff={}",
                                                            traceId, adjustmentType, adjustmentAmount));
                                        }))
                                        .map(updatedRecord -> 
                                                CreditAdjustmentResult.success(adjustmentAmount, actualCost, 
                                                        preDeductedAmount, adjustmentType, traceId))
                                        .flatMap(result -> getUserCredits(record.getUserId())
                                                .doOnSuccess(remaining -> log.info("🧾 [Adjust] 调整完成: traceId={}, type={}, diff={}, 当前余额remainingCredits={}",
                                                        traceId, result.getAdjustmentType(), result.getAdjustmentAmount(), remaining))
                                                .thenReturn(result));
                            });
                })
                // 添加对MongoDB事务冲突的重试机制，与其他服务保持一致
                .retryWhen(reactor.util.retry.Retry.max(3)
                        .filter(err -> {
                            String m = err.getMessage() != null ? err.getMessage() : "";
                            // 包含 WriteConflict、TransientTransactionError 等MongoDB事务错误
                            return m.contains("WriteConflict") || 
                                   m.contains("NoSuchTransaction") || 
                                   m.contains("TransientTransactionError") || 
                                   m.contains("251") || 
                                   m.contains("112"); // WriteConflict错误代码
                        })
                        .doBeforeRetry(retrySignal -> {
                            log.warn("费用调整遇到事务冲突，正在重试: traceId={}, 重试次数={}, 错误={}", 
                                    traceId, retrySignal.totalRetries() + 1, retrySignal.failure().getMessage());
                        })
                        .onRetryExhaustedThrow((spec, signal) -> {
                            log.error("费用调整重试次数已用完: traceId={}, 最终错误={}", 
                                    traceId, signal.failure().getMessage());
                            return signal.failure();
                        })
                )
                .onErrorResume(error -> {
                    log.error("费用调整失败: traceId={}, actualInputTokens={}, actualOutputTokens={}", 
                            traceId, actualInputTokens, actualOutputTokens, error);
                    return Mono.just(CreditAdjustmentResult.failure(traceId, "费用调整失败: " + error.getMessage()));
                });
    }

    @Override
    public Mono<Boolean> refundPreDeduction(String traceId) {
        return preDeductionRecordRepository.findByTraceId(traceId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("未找到对应的预扣费记录: " + traceId)))
                .flatMap(record -> {
                    if (record.getStatus() != PreDeductionRecord.Status.PENDING) {
                        // 已处理的记录不需要退还
                        return Mono.just(true);
                    }
                    
                    // 退还预扣费
                    return addCredits(record.getUserId(), record.getPreDeductedAmount(), 
                            "AI调用失败预扣费退还 (traceId: " + traceId + ")")
                            .flatMap(success -> {
                                if (success) {
                                    // 更新记录状态
                                    record.markAsRefunded("AI调用失败");
                                    return preDeductionRecordRepository.save(record)
                                            .thenReturn(true);
                                } else {
                                    return Mono.just(false);
                                }
                            });
                })
                .onErrorResume(error -> {
                    log.error("预扣费退还失败: traceId={}", traceId, error);
                    return Mono.just(false);
                });
    }
}