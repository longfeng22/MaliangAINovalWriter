package com.ainovel.server.config;

import com.ainovel.server.domain.model.AIFeatureType;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import java.util.HashMap;
import java.util.Map;

/**
 * 提示词市场奖励配置
 * 配置不同AI功能类型的引用积分奖励数值
 */
@Configuration
@ConfigurationProperties(prefix = "prompt.market.reward")
@Data
public class PromptMarketRewardConfig {
    
    /**
     * 各功能类型的引用积分配置
     * key: AIFeatureType的字符串表示
     * value: 积分数值
     */
    private Map<String, Long> referencePoints = new HashMap<>();
    
    /**
     * 默认引用积分
     */
    private long defaultReferencePoints = 1L;
    
    /**
     * 点赞积分奖励
     */
    private long likePoints = 0L;
    
    /**
     * 收藏积分奖励
     */
    private long favoritePoints = 0L;
    
    /**
     * 初始化默认配置
     */
    public PromptMarketRewardConfig() {
        // 设定树生成 - 高价值功能，奖励3积分
        referencePoints.put("SETTING_TREE_GENERATION", 3L);
        
        // 专业续写功能 - 高价值功能，奖励3积分
        referencePoints.put("PROFESSIONAL_FICTION_CONTINUATION", 3L);
        
        // 小说编排 - 高价值功能，奖励2积分
        referencePoints.put("NOVEL_COMPOSE", 2L);
        
        // 场景节拍生成 - 中价值功能，奖励2积分
        referencePoints.put("SCENE_BEAT_GENERATION", 2L);
        
        // 故事剧情续写 - 中价值功能，奖励2积分
        referencePoints.put("STORY_PLOT_CONTINUATION", 2L);
        
        // 文本扩写 - 基础功能，奖励1积分
        referencePoints.put("TEXT_EXPANSION", 1L);
        
        // 文本重构 - 基础功能，奖励1积分
        referencePoints.put("TEXT_REFACTOR", 1L);
        
        // 文本缩写 - 基础功能，奖励1积分
        referencePoints.put("TEXT_SUMMARY", 1L);
        
        // 场景生成摘要 - 基础功能，奖励1积分
        referencePoints.put("SCENE_TO_SUMMARY", 1L);
        
        // 摘要生成场景 - 基础功能，奖励1积分
        referencePoints.put("SUMMARY_TO_SCENE", 1L);
        
        // AI聊天 - 基础功能，奖励1积分
        referencePoints.put("AI_CHAT", 1L);
        
        // 小说内容生成 - 基础功能，奖励1积分
        referencePoints.put("NOVEL_GENERATION", 1L);
        
        // 知识库拆书 - 设定提取 - 中价值功能，奖励2积分
        referencePoints.put("KNOWLEDGE_EXTRACTION_SETTING", 2L);
        
        // 知识库拆书 - 章节大纲生成 - 中价值功能，奖励2积分
        referencePoints.put("KNOWLEDGE_EXTRACTION_OUTLINE", 2L);
        
        // 设定生成工具调用 - 内部功能，不给积分
        referencePoints.put("SETTING_GENERATION_TOOL", 0L);
    }
    
    /**
     * 获取指定功能类型的引用积分
     * 
     * @param featureType 功能类型
     * @return 积分数值
     */
    public long getReferencePoints(AIFeatureType featureType) {
        if (featureType == null) {
            return defaultReferencePoints;
        }
        return referencePoints.getOrDefault(featureType.name(), defaultReferencePoints);
    }
    
    /**
     * 获取引用积分的描述信息
     * 
     * @param featureType 功能类型
     * @return 积分描述
     */
    public String getReferencePointsDescription(AIFeatureType featureType) {
        long points = getReferencePoints(featureType);
        if (points == 0) {
            return "不奖励积分";
        } else if (points == 1) {
            return "引用奖励 1 积分";
        } else {
            return String.format("引用奖励 %d 积分", points);
        }
    }
    
    /**
     * 获取所有功能类型的积分配置映射（用于前端展示）
     * 
     * @return 功能类型到积分的映射
     */
    public Map<AIFeatureType, Long> getAllReferencePoints() {
        Map<AIFeatureType, Long> result = new HashMap<>();
        for (AIFeatureType type : AIFeatureType.values()) {
            result.put(type, getReferencePoints(type));
        }
        return result;
    }
}


