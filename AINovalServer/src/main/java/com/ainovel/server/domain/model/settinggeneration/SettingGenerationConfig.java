package com.ainovel.server.domain.model.settinggeneration;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 设定生成配置
 * 存储设定生成策略的核心业务配置，专注于实际业务需求
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SettingGenerationConfig {
    
    /**
     * 策略名称
     */
    private String strategyName;
    
    /**
     * 策略描述
     */
    private String description;
    
    /**
     * 节点模板配置列表
     */
    @Builder.Default
    private List<NodeTemplateConfig> nodeTemplates = new ArrayList<>();
    
    /**
     * 生成规则
     */
    @Builder.Default
    private GenerationRules rules = new GenerationRules();
    
    /**
     * 提示词配置
     */
    @Builder.Default
    private PromptTemplateConfig promptConfig = new PromptTemplateConfig();
    
    /**
     * 元数据
     */
    @Builder.Default
    private StrategyMetadata metadata = new StrategyMetadata();
    
    /**
     * 期望的根节点数量
     */
    @Builder.Default
    private Integer expectedRootNodes = -1; // -1表示不限制
    
    /**
     * 最大深度
     */
    @Builder.Default
    private Integer maxDepth = 5;
    
    /**
     * 策略版本
     */
    @Builder.Default
    private String version = "1.0.0";
    
    /**
     * 基础策略ID（如果是基于其他策略创建）
     */
    private String baseStrategyId;
    
    /**
     * 创建时间
     */
    private LocalDateTime createdAt;
    
    /**
     * 更新时间
     */
    private LocalDateTime updatedAt;
    
    /**
     * 使用次数
     */
    @Builder.Default
    private Long usageCount = 0L;
    
    /**
     * 是否为系统预设策略
     */
    @Builder.Default
    private Boolean isSystemStrategy = false;
}