package com.ainovel.server.domain.model.billing;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;

import com.ainovel.server.domain.model.AIFeatureType;

import java.time.LocalDateTime;

/**
 * 预扣费记录
 * 用于存储AI请求的预扣费信息，支持后续的费用调整
 */
@Document(collection = "pre_deduction_records")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PreDeductionRecord {
    
    @Id
    private String id;
    
    /**
     * AI请求的追踪ID - 唯一标识
     */
    @Indexed(unique = true)
    private String traceId;
    
    /**
     * 用户ID
     */
    @Indexed
    private String userId;
    
    /**
     * 预扣费金额
     */
    private Long preDeductedAmount;
    
    /**
     * 模型提供商
     */
    private String provider;
    
    /**
     * 模型ID
     */
    private String modelId;
    
    /**
     * AI功能类型
     */
    private AIFeatureType featureType;
    
    /**
     * 记录状态
     */
    @Builder.Default
    private Status status = Status.PENDING;
    
    /**
     * 实际费用（调整后）
     */
    private Long actualCost;
    
    /**
     * 调整金额（正数为补扣，负数为退还）
     */
    private Long adjustmentAmount;
    
    /**
     * 调整类型
     */
    private String adjustmentType;
    
    /**
     * 创建时间
     */
    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();
    
    /**
     * 调整时间
     */
    private LocalDateTime adjustedAt;
    
    /**
     * 备注信息
     */
    private String remarks;
    
    /**
     * 预扣费记录状态
     */
    public enum Status {
        PENDING,    // 待调整（预扣费已完成，等待真实费用调整）
        ADJUSTED,   // 已调整（费用已根据真实消耗调整）
        REFUNDED,   // 已退还（AI调用失败，预扣费已退还）
        EXPIRED     // 已过期（长时间未调整，可能需要人工处理）
    }
    
    /**
     * 标记为已调整
     */
    public void markAsAdjusted(long actualCost, long adjustmentAmount, String adjustmentType) {
        this.status = Status.ADJUSTED;
        this.actualCost = actualCost;
        this.adjustmentAmount = adjustmentAmount;
        this.adjustmentType = adjustmentType;
        this.adjustedAt = LocalDateTime.now();
    }
    
    /**
     * 标记为已退还
     */
    public void markAsRefunded(String reason) {
        this.status = Status.REFUNDED;
        this.adjustedAt = LocalDateTime.now();
        this.remarks = reason;
    }
    
    /**
     * 获取最终费用
     */
    public long getFinalCost() {
        return actualCost != null ? actualCost : preDeductedAmount;
    }
}
