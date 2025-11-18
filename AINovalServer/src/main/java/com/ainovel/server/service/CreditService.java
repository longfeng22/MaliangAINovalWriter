package com.ainovel.server.service;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.PublicModelConfig;

import reactor.core.publisher.Mono;

/**
 * 积分管理服务接口
 */
public interface CreditService {
    
    /**
     * 扣减用户积分
     * 
     * @param userId 用户ID
     * @param amount 扣减数量
     * @return 扣减结果（true表示成功，false表示余额不足）
     */
    Mono<Boolean> deductCredits(String userId, long amount);
    
    /**
     * 增加用户积分
     * 
     * @param userId 用户ID
     * @param amount 增加数量
     * @param reason 增加原因
     * @return 增加结果
     */
    Mono<Boolean> addCredits(String userId, long amount, String reason);
    
    /**
     * 获取用户当前积分余额
     * 
     * @param userId 用户ID
     * @return 积分余额
     */
    Mono<Long> getUserCredits(String userId);
    
    /**
     * 计算AI功能调用的积分成本
     * 
     * @param provider 提供商
     * @param modelId 模型ID
     * @param featureType AI功能类型
     * @param inputTokens 输入token数量
     * @param outputTokens 输出token数量
     * @return 积分成本
     */
    Mono<Long> calculateCreditCost(String provider, String modelId, AIFeatureType featureType, int inputTokens, int outputTokens);
    
    /**
     * 检查用户是否有足够积分使用指定功能
     * 
     * @param userId 用户ID
     * @param provider 提供商
     * @param modelId 模型ID
     * @param featureType AI功能类型
     * @param estimatedInputTokens 预估输入token数量
     * @param estimatedOutputTokens 预估输出token数量
     * @return 是否有足够积分
     */
    Mono<Boolean> hasEnoughCredits(String userId, String provider, String modelId, AIFeatureType featureType, int estimatedInputTokens, int estimatedOutputTokens);
    
    /**
     * 执行AI功能调用的积分扣减
     * 
     * @param userId 用户ID
     * @param provider 提供商
     * @param modelId 模型ID
     * @param featureType AI功能类型
     * @param inputTokens 实际输入token数量
     * @param outputTokens 实际输出token数量
     * @return 扣减结果和消费的积分数量
     */
    Mono<CreditDeductionResult> deductCreditsForAI(String userId, String provider, String modelId, AIFeatureType featureType, int inputTokens, int outputTokens);
    
    /**
     * 获取积分与美元的汇率
     * 
     * @return 汇率（1美元等于多少积分）
     */
    Mono<Double> getCreditToUsdRate();
    
    /**
     * 设置积分与美元的汇率
     * 
     * @param rate 新汇率
     * @return 设置结果
     */
    Mono<Boolean> setCreditToUsdRate(double rate);
    
    /**
     * 为新用户赠送初始积分
     * 
     * @param userId 用户ID
     * @return 赠送结果
     */
    Mono<Boolean> grantNewUserCredits(String userId);
    
    /**
     * 🚀 新增：基于AIRequest进行积分预估和余额校验
     * 直接使用最终的AIRequest进行精确的积分消耗预估和余额校验
     * 
     * @param aiRequest AI请求对象（包含完整的提示词信息）
     * @param publicModel 公共模型配置
     * @param featureType AI功能类型
     * @return 校验结果
     */
    Mono<CreditValidationResult> validateCreditsForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType);


    /**
     * 🚀 新增：直接在CreditService中进行AIRequest的积分预估
     * 避免对CostEstimationService的循环依赖
     * 
     * @param aiRequest AI请求对象（包含完整的提示词信息）
     * @param publicModel 公共模型配置
     * @param featureType AI功能类型
     * @return 预估结果
     */
    Mono<Long> estimateCreditsForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType);
    
    /**
     * 🚀 新增：预扣费机制 - 基于traceId的积分预扣费
     * 在AI调用前预先扣除预估费用，解决并发竞态条件
     * 
     * @param traceId AI请求的追踪ID
     * @param userId 用户ID
     * @param estimatedCost 预估费用
     * @param provider 模型提供商
     * @param modelId 模型ID
     * @param featureType AI功能类型
     * @return 预扣费结果
     */
    Mono<PreDeductionResult> preDeductCredits(String traceId, String userId, long estimatedCost, 
                                            String provider, String modelId, AIFeatureType featureType);
    
    /**
     * 🚀 新增：费用调整机制 - 基于真实消耗调整预扣费
     * 在AI调用完成后，根据真实token消耗调整费用差额
     * 
     * @param traceId AI请求的追踪ID
     * @param actualInputTokens 实际输入token数
     * @param actualOutputTokens 实际输出token数
     * @return 调整结果
     */
    Mono<CreditAdjustmentResult> adjustCreditsBasedOnActualUsage(String traceId, int actualInputTokens, int actualOutputTokens);



    
    /**
     * 🚀 新增：预扣费退还机制 - AI调用失败时退还预扣费
     * 
     * @param traceId AI请求的追踪ID
     * @return 退还结果
     */
    Mono<Boolean> refundPreDeduction(String traceId);
    
    /**
     * 积分校验结果
     */
    class CreditValidationResult {
        private final boolean valid;
        private final long currentCredits;
        private final long estimatedCost;
        private final String message;
        private final Integer estimatedInputTokens;
        private final Integer estimatedOutputTokens;
        
        public CreditValidationResult(boolean valid, long currentCredits, long estimatedCost, String message) {
            this.valid = valid;
            this.currentCredits = currentCredits;
            this.estimatedCost = estimatedCost;
            this.message = message;
            this.estimatedInputTokens = null;
            this.estimatedOutputTokens = null;
        }
        
        public CreditValidationResult(boolean valid, long currentCredits, long estimatedCost, String message, 
                                    Integer estimatedInputTokens, Integer estimatedOutputTokens) {
            this.valid = valid;
            this.currentCredits = currentCredits;
            this.estimatedCost = estimatedCost;
            this.message = message;
            this.estimatedInputTokens = estimatedInputTokens;
            this.estimatedOutputTokens = estimatedOutputTokens;
        }
        
        public boolean isValid() { return valid; }
        public long getCurrentCredits() { return currentCredits; }
        public long getEstimatedCost() { return estimatedCost; }
        public String getMessage() { return message; }
        public Integer getEstimatedInputTokens() { return estimatedInputTokens; }
        public Integer getEstimatedOutputTokens() { return estimatedOutputTokens; }
        
        public static CreditValidationResult success(long currentCredits, long estimatedCost) {
            return new CreditValidationResult(true, currentCredits, estimatedCost, "余额充足");
        }
        
        public static CreditValidationResult success(long currentCredits, long estimatedCost, 
                                                   Integer inputTokens, Integer outputTokens) {
            return new CreditValidationResult(true, currentCredits, estimatedCost, "余额充足", inputTokens, outputTokens);
        }
        
        public static CreditValidationResult failure(long currentCredits, long estimatedCost, String message) {
            return new CreditValidationResult(false, currentCredits, estimatedCost, message);
        }
    }
    
    /**
     * 预扣费结果
     */
    class PreDeductionResult {
        private final boolean success;
        private final long preDeductedAmount;
        private final long remainingCredits;
        private final String traceId;
        private final String message;
        
        public PreDeductionResult(boolean success, long preDeductedAmount, long remainingCredits, String traceId, String message) {
            this.success = success;
            this.preDeductedAmount = preDeductedAmount;
            this.remainingCredits = remainingCredits;
            this.traceId = traceId;
            this.message = message;
        }
        
        public boolean isSuccess() { return success; }
        public long getPreDeductedAmount() { return preDeductedAmount; }
        public long getRemainingCredits() { return remainingCredits; }
        public String getTraceId() { return traceId; }
        public String getMessage() { return message; }
        
        public static PreDeductionResult success(long preDeductedAmount, long remainingCredits, String traceId) {
            return new PreDeductionResult(true, preDeductedAmount, remainingCredits, traceId, "预扣费成功");
        }
        
        public static PreDeductionResult failure(String traceId, String message) {
            return new PreDeductionResult(false, 0, 0, traceId, message);
        }
    }
    
    /**
     * 费用调整结果
     */
    class CreditAdjustmentResult {
        private final boolean success;
        private final long adjustmentAmount;
        private final long actualCost;
        private final long originalPreDeduction;
        private final String adjustmentType; // "REFUND" 或 "ADDITIONAL_CHARGE"
        private final String traceId;
        private final String message;
        
        public CreditAdjustmentResult(boolean success, long adjustmentAmount, long actualCost, 
                                    long originalPreDeduction, String adjustmentType, String traceId, String message) {
            this.success = success;
            this.adjustmentAmount = adjustmentAmount;
            this.actualCost = actualCost;
            this.originalPreDeduction = originalPreDeduction;
            this.adjustmentType = adjustmentType;
            this.traceId = traceId;
            this.message = message;
        }
        
        public boolean isSuccess() { return success; }
        public long getAdjustmentAmount() { return adjustmentAmount; }
        public long getActualCost() { return actualCost; }
        public long getOriginalPreDeduction() { return originalPreDeduction; }
        public String getAdjustmentType() { return adjustmentType; }
        public String getTraceId() { return traceId; }
        public String getMessage() { return message; }
        
        public static CreditAdjustmentResult success(long adjustmentAmount, long actualCost, 
                                                   long originalPreDeduction, String adjustmentType, String traceId) {
            return new CreditAdjustmentResult(true, adjustmentAmount, actualCost, originalPreDeduction, 
                                            adjustmentType, traceId, "费用调整成功");
        }
        
        public static CreditAdjustmentResult failure(String traceId, String message) {
            return new CreditAdjustmentResult(false, 0, 0, 0, null, traceId, message);
        }
    }
    
    /**
     * 积分扣减结果
     */
    class CreditDeductionResult {
        private final boolean success;
        private final long creditsDeducted;
        private final String message;
        
        public CreditDeductionResult(boolean success, long creditsDeducted, String message) {
            this.success = success;
            this.creditsDeducted = creditsDeducted;
            this.message = message;
        }
        
        public boolean isSuccess() {
            return success;
        }
        
        public long getCreditsDeducted() {
            return creditsDeducted;
        }
        
        public String getMessage() {
            return message;
        }
        
        public static CreditDeductionResult success(long creditsDeducted) {
            return new CreditDeductionResult(true, creditsDeducted, "积分扣减成功");
        }
        
        public static CreditDeductionResult failure(String message) {
            return new CreditDeductionResult(false, 0, message);
        }
    }
}