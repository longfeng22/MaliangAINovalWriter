package com.ainovel.server.service.ai.pricing;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.ModelPricing;
import com.ainovel.server.repository.ModelPricingRepository;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 定价初始化服务
 * 在应用启动时初始化和更新模型定价数据
 * 
 * 更新日志：
 * - 2025-06-27: 根据Google官方API文档更新Gemini 2.5系列定价
 * - 2025-06-27: 添加gemini-2.5-pro解决"模型定价信息不存在"错误
 * - 2025-06-27: 完善Grok模型定价信息
 */
@Slf4j
@Service
@Order(100) // 确保在其他组件初始化后执行
public class PricingInitializationService implements ApplicationRunner {
    
    @Autowired
    private ModelPricingRepository modelPricingRepository;
    
    @Autowired(required = false)
    private PricingDataSyncService pricingDataSyncService;
    
    /**
     * 是否在启动时自动同步定价
     */
    private boolean autoSyncOnStartup = true;
    
    @Override
    public void run(ApplicationArguments args) throws Exception {
        log.info("Starting pricing data initialization...");
        
        initializeDefaultPricing()
                .then(syncFromOfficialAPIs())
                .doOnSuccess(unused -> log.info("Pricing data initialization completed successfully"))
                .doOnError(error -> log.error("Error during pricing data initialization", error))
                .subscribe();
    }
    
    /**
     * 初始化默认定价数据
     * 
     * @return 初始化结果
     */
    public Mono<Void> initializeDefaultPricing() {
        log.info("Initializing default pricing data...");
        
        return Flux.fromIterable(getDefaultPricingData())
                .flatMap(this::saveIfNotExists)
                .then()
                .doOnSuccess(unused -> log.info("Default pricing data initialization completed"));
    }
    
    /**
     * 从官方API同步定价数据
     * 
     * @return 同步结果
     */
    public Mono<Void> syncFromOfficialAPIs() {
        if (!autoSyncOnStartup || pricingDataSyncService == null) {
            log.info("Auto sync on startup is disabled or sync service not available, skipping official API sync");
            return Mono.empty();
        }
        
        log.info("Syncing pricing data from official APIs...");
        
        return pricingDataSyncService.syncAllProvidersPricing()
                .doOnNext(result -> {
                    if (result.isSuccess()) {
                        log.info("Successfully synced {} models for provider {}", 
                                result.successCount(), result.provider());
                    } else if (result.isPartialSuccess()) {
                        log.warn("Partially synced {} out of {} models for provider {}, errors: {}", 
                                result.successCount(), result.totalModels(), result.provider(), result.errors());
                    } else {
                        log.error("Failed to sync pricing for provider {}, errors: {}", 
                                result.provider(), result.errors());
                    }
                })
                .then()
                .doOnSuccess(unused -> log.info("Official API pricing sync completed"));
    }
    
    /**
     * 保存定价数据（如果不存在）
     * 
     * @param pricing 定价数据
     * @return 保存结果
     */
    private Mono<ModelPricing> saveIfNotExists(ModelPricing pricing) {
        return modelPricingRepository.existsByProviderAndModelIdAndActiveTrue(
                pricing.getProvider(), pricing.getModelId())
                .flatMap(exists -> {
                    if (exists) {
                        log.debug("Pricing for {}:{} already exists, skipping", 
                                pricing.getProvider(), pricing.getModelId());
                        return Mono.empty();
                    } else {
                        pricing.setCreatedAt(LocalDateTime.now());
                        pricing.setUpdatedAt(LocalDateTime.now());
                        pricing.setVersion(1);
                        pricing.setActive(true);
                        return modelPricingRepository.save(pricing);
                    }
                });
    }
    
    /**
     * 获取默认定价数据
     * 热门模型的初始定价配置（基于2025年最新官方定价）
     * 
     * 价格转换说明：
     * - 官方定价通常以每百万token计算，这里转换为每千token
     * - Google Gemini: 基于 https://ai.google.dev/gemini-api/docs/pricing 
     * - 例如：Gemini 2.5 Pro 输入 $1.25/1M tokens = $0.00125/1K tokens
     * - 对于分层定价模型，使用较低价格作为基础价格
     * 
     * @return 默认定价数据列表
     */
    private List<ModelPricing> getDefaultPricingData() {
        return List.of(
                // OpenAI 模型 (2024年最新定价)
                createPricing("openai", "gpt-3.5-turbo", "GPT-3.5 Turbo", 
                        0.0005, 0.0015, 16385, "OpenAI GPT-3.5 Turbo模型 - 最新2024定价"),
                
                createPricing("openai", "gpt-4o", "GPT-4o", 
                        0.003, 0.01, 128000, "OpenAI GPT-4o模型 - 平衡性能与成本"),
                
                createPricing("openai", "gpt-4o-mini", "GPT-4o Mini", 
                        0.00015, 0.0006, 128000, "OpenAI GPT-4o Mini模型 - 最经济选择"),
                
                createPricing("openai", "gpt-4-turbo", "GPT-4 Turbo", 
                        0.01, 0.03, 128000, "OpenAI GPT-4 Turbo模型"),
                
                // Anthropic 模型 (2024年最新定价)
                createPricing("anthropic", "claude-3-5-haiku", "Claude 3.5 Haiku", 
                        0.0008, 0.004, 200000, "Anthropic Claude 3.5 Haiku - 最快最经济"),
                
                createPricing("anthropic", "claude-3-5-sonnet", "Claude 3.5 Sonnet", 
                        0.003, 0.015, 200000, "Anthropic Claude 3.5 Sonnet - 智能与速度平衡"),
                
                createPricing("anthropic", "claude-3-opus", "Claude 3 Opus", 
                        0.015, 0.075, 200000, "Anthropic Claude 3 Opus - 最强性能"),
                
                createPricing("anthropic", "claude-4-sonnet", "Claude 4 Sonnet", 
                        0.003, 0.015, 200000, "Anthropic Claude 4 Sonnet - 新一代模型"),
                
                createPricing("anthropic", "claude-4-opus", "Claude 4 Opus", 
                        0.015, 0.075, 200000, "Anthropic Claude 4 Opus - 顶级性能"),
                
                // Google Gemini 2.5 系列模型 (2025年最新官方定价)
                // 🚀 重要：添加 gemini-2.5-pro 解决 "模型定价信息不存在" 错误
                // Gemini 2.5 Pro - 最先进的多用途模型，分层定价：≤20万token: $1.25/1M输入+$10/1M输出，>20万token: $2.50/1M输入+$15/1M输出
                createPricing("gemini", "gemini-2.5-pro", "Gemini 2.5 Pro", 
                        0.00125, 0.01, 2000000, "Google Gemini 2.5 Pro - 最先进模型，擅长编码和复杂推理，分层定价"),
                
                // Gemini 2.5 Flash - 混合推理模型，支持思考预算，100万token上下文
                createPricing("gemini", "gemini-2.5-flash", "Gemini 2.5 Flash", 
                        0.0003, 0.0025, 1000000, "Google Gemini 2.5 Flash - 100万token上下文窗口，混合推理，音频$0.001输入"),
                
                // Gemini 2.5 Flash-Lite - 最小最具成本效益的模型
                createPricing("gemini", "gemini-2.5-flash-lite", "Gemini 2.5 Flash-Lite", 
                        0.0001, 0.0004, 1000000, "Google Gemini 2.5 Flash-Lite - 最小型最具成本效益，音频$0.0005输入"),
                
                // Gemini 2.5 Flash 原生音频模型
                createPricing("gemini", "gemini-2.5-flash-audio", "Gemini 2.5 Flash Audio", 
                        0.0005, 0.002, 1000000, "Google Gemini 2.5 Flash 原生音频 - 文字$0.0005输入+$0.002输出，音频$0.003输入+$0.012输出"),
                
                // Gemini 2.5 Flash TTS 文字转语音模型
                createPricing("gemini", "gemini-2.5-flash-tts", "Gemini 2.5 Flash TTS", 
                        0.0005, 0.01, 1000000, "Google Gemini 2.5 Flash TTS - 文字转语音，输入$0.0005，音频输出$0.01"),
                
                // Gemini 2.5 Pro TTS 文字转语音模型
                createPricing("gemini", "gemini-2.5-pro-tts", "Gemini 2.5 Pro TTS", 
                        0.001, 0.02, 2000000, "Google Gemini 2.5 Pro TTS - 强大文字转语音，输入$0.001，音频输出$0.02"),
                
                // Google Gemini 2.0 系列模型 (2025年最新发布)
                // Gemini 2.0 Flash - 最平衡的多模态模型，专为智能助理时代打造
                createPricing("gemini", "gemini-2.0-flash", "Gemini 2.0 Flash", 
                        0.0001, 0.0004, 1000000, "Google Gemini 2.0 Flash - 最平衡多模态模型，文字/图片/视频$0.0001输入，音频$0.0007输入"),
                
                // Gemini 2.0 Flash-Lite - 最小最具成本效益
                createPricing("gemini", "gemini-2.0-flash-lite", "Gemini 2.0 Flash-Lite", 
                        0.000075, 0.0003, 1000000, "Google Gemini 2.0 Flash-Lite - 最小型最具成本效益模型"),
                
                // Google Gemini 1.5 系列模型 (更新定价)
                // Gemini 1.5 Pro - 突破性200万token上下文，分层定价：≤128k: $1.25/1M输入+$5/1M输出，>128k: $2.50/1M输入+$10/1M输出
                createPricing("gemini", "gemini-1.5-pro", "Gemini 1.5 Pro", 
                        0.00125, 0.005, 2000000, "Google Gemini 1.5 Pro - 200万token上下文窗口，分层定价"),
                
                // Gemini 1.5 Flash - 更新定价，分层定价：≤128k: $0.075/1M输入+$0.30/1M输出，>128k: $0.15/1M输入+$0.60/1M输出
                createPricing("gemini", "gemini-1.5-flash", "Gemini 1.5 Flash", 
                        0.000075, 0.0003, 1000000, "Google Gemini 1.5 Flash - 高性价比，100万token上下文，分层定价"),
                
                // Gemini 1.5 Flash-8B - 更新定价，分层定价：≤128k: $0.0375/1M输入+$0.15/1M输出，>128k: $0.075/1M输入+$0.30/1M输出
                createPricing("gemini", "gemini-1.5-flash-8b", "Gemini 1.5 Flash-8B", 
                        0.0000375, 0.00015, 1000000, "Google Gemini 1.5 Flash-8B - 最小型模型，适用于低智能度场景，分层定价"),
                
                // Gemini 1.0 Pro - 经典版本
                createPricing("gemini", "gemini-1.0-pro", "Gemini 1.0 Pro", 
                        0.0005, 0.0015, 32760, "Google Gemini 1.0 Pro - 经典版本"),
                
                // 常用别名和变体
                createPricing("gemini", "gemini-pro", "Gemini Pro", 
                        0.0005, 0.0015, 32760, "Google Gemini Pro - 通用别名"),
                
                // Google 图像和视频生成模型
                createPricing("gemini", "imagen-3", "Imagen 3", 
                        0.03, 0.03, 1000000, "Google Imagen 3 - 先进图像生成模型，$0.03/图片"),
                
                createPricing("gemini", "veo-2", "Veo 2", 
                        0.35, 0.35, 1000000, "Google Veo 2 - 先进视频生成模型，$0.35/秒"),
                
                // Google 嵌入模型
                createPricing("gemini", "text-embedding-004", "Text Embedding 004", 
                        0.0, 0.0, 8192, "Google 文本嵌入 004 - 先进文本嵌入模型，免费使用"),
                
                // Google 开源模型 Gemma 系列
                createPricing("gemini", "gemma-3", "Gemma 3", 
                        0.0, 0.0, 8192, "Google Gemma 3 - 轻量级开放模型，免费使用"),
                
                createPricing("gemini", "gemma-3n", "Gemma 3n", 
                        0.0, 0.0, 8192, "Google Gemma 3n - 设备端优化开放模型，免费使用"),
                
                // X.AI Grok 模型 (2025年最新定价 - 基于官方API文档)
                // Grok 3 系列 - 旗舰模型，深度领域知识
                createPricing("grok", "grok-3", "Grok 3", 
                        0.003, 0.015, 131072, "X.AI Grok 3 - 旗舰模型，深度领域知识，缓存输入$0.00075/1K"),
                
                createPricing("grok", "grok-3-mini", "Grok 3 Mini", 
                        0.0003, 0.0005, 131072, "X.AI Grok 3 Mini - 轻量级思考模型，缓存输入$0.00007/1K"),
                
                createPricing("grok", "grok-3-fast", "Grok 3 Fast", 
                        0.005, 0.025, 131072, "X.AI Grok 3 Fast - 高性能快速版本，缓存输入$0.00125/1K"),
                
                createPricing("grok", "grok-3-mini-fast", "Grok 3 Mini Fast", 
                        0.0006, 0.004, 131072, "X.AI Grok 3 Mini Fast - 快速轻量版，缓存输入$0.00015/1K"),
                
                // Grok 2 系列 - 2024年12月更新版本
                createPricing("grok", "grok-2-vision-1212", "Grok 2 Vision", 
                        0.002, 0.01, 32768, "X.AI Grok 2 Vision (2024-12) - 支持视觉理解，图像输入$0.002/1K"),
                
                createPricing("grok", "grok-2-1212", "Grok 2", 
                        0.002, 0.01, 131072, "X.AI Grok 2 (2024-12) - 新一代推理模型"),
                
                // Grok 图像生成模型
                createPricing("grok", "grok-2-image-1212", "Grok 2 Image Gen", 
                        0.07, 0.07, 131072, "X.AI Grok 2 图像生成 - 高质量图像生成，$0.07/图片"),
                
                // 历史版本和别名
                createPricing("grok", "grok-beta", "Grok Beta", 
                        0.005, 0.015, 131072, "X.AI Grok Beta - 历史测试版本"),
                
                createPricing("grok", "grok-2", "Grok 2 Legacy", 
                        0.002, 0.01, 128000, "X.AI Grok 2 - 历史版本"),
                
                createPricing("grok", "grok-2-mini", "Grok 2 Mini Legacy", 
                        0.0002, 0.001, 128000, "X.AI Grok 2 Mini - 历史经济版本"),
                
                // SiliconFlow 模型
                createPricing("siliconflow", "qwen-plus", "Qwen Plus", 
                        0.0003, 0.0006, 32768, "SiliconFlow Qwen Plus模型"),
                
                createPricing("siliconflow", "deepseek-chat", "DeepSeek Chat", 
                        0.00014, 0.00028, 32768, "SiliconFlow DeepSeek Chat模型"),

                // SiliconFlow Qwen3-8B（免费）- 修复定价缺失导致的扣费调整失败
                createPricing("siliconflow", "Qwen/Qwen3-8B", "Qwen3-8B", 
                        0.0, 0.0, 32768, "SiliconFlow Qwen3-8B - 免费使用"),
                
                // OpenRouter 热门模型
                createPricing("openrouter", "anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet (OpenRouter)", 
                        0.003, 0.015, 200000, "通过OpenRouter访问的Claude 3.5 Sonnet"),
                
                createPricing("openrouter", "openai/gpt-4o-mini", "GPT-4o Mini (OpenRouter)", 
                        0.00015, 0.0006, 128000, "通过OpenRouter访问的GPT-4o Mini"),
                
                createPricing("openrouter", "google/gemini-2.0-flash", "Gemini 2.0 Flash (OpenRouter)", 
                        0.0001, 0.0004, 1000000, "通过OpenRouter访问的Gemini 2.0 Flash")
        );
    }
    
    /**
     * 创建定价信息
     * 
     * @param provider 提供商
     * @param modelId 模型ID
     * @param modelName 模型名称
     * @param inputPrice 输入价格
     * @param outputPrice 输出价格
     * @param maxTokens 最大token数
     * @param description 描述
     * @return 定价信息
     */
    private ModelPricing createPricing(String provider, String modelId, String modelName,
                                     double inputPrice, double outputPrice, int maxTokens, String description) {
        return ModelPricing.builder()
                .provider(provider)
                .modelId(modelId)
                .modelName(modelName)
                .inputPricePerThousandTokens(inputPrice)
                .outputPricePerThousandTokens(outputPrice)
                .maxContextTokens(maxTokens)
                .supportsStreaming(true)
                .description(description)
                .source(ModelPricing.PricingSource.DEFAULT)
                .active(true)
                .build();
    }
    
    /**
     * 创建统一定价信息
     * 
     * @param provider 提供商
     * @param modelId 模型ID
     * @param modelName 模型名称
     * @param unifiedPrice 统一价格
     * @param maxTokens 最大token数
     * @param description 描述
     * @return 定价信息
     */
    private ModelPricing createUnifiedPricing(String provider, String modelId, String modelName,
                                            double unifiedPrice, int maxTokens, String description) {
        return ModelPricing.builder()
                .provider(provider)
                .modelId(modelId)
                .modelName(modelName)
                .unifiedPricePerThousandTokens(unifiedPrice)
                .maxContextTokens(maxTokens)
                .supportsStreaming(true)
                .description(description)
                .source(ModelPricing.PricingSource.DEFAULT)
                .active(true)
                .build();
    }
    
    /**
     * 设置是否在启动时自动同步
     * 
     * @param autoSync 是否自动同步
     */
    public void setAutoSyncOnStartup(boolean autoSync) {
        this.autoSyncOnStartup = autoSync;
    }
}