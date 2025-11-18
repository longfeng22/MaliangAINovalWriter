package com.ainovel.server.service;

import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.domain.model.AIRequest;
import com.ainovel.server.domain.model.PublicModelConfig;
import com.ainovel.server.domain.model.AIFeatureType;
import reactor.core.publisher.Mono;
import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

/**
 * 积分成本预估服务接口
 * 提供快速的AI请求积分成本预估功能
 */
public interface CostEstimationService {

    /**
     * 快速预估通用AI请求的积分成本
     * @param request AI请求数据
     * @return 预估结果
     */
    Mono<CostEstimationResponse> estimateCost(UniversalAIRequestDto request);

    /**
     * 🚀 新增：直接基于AIRequest进行积分成本预估
     * @param aiRequest AI请求对象
     * @param publicModel 公共模型配置
     * @param featureType AI功能类型
     * @return 预估结果
     */
    Mono<CostEstimationResponse> estimateCostForAIRequest(AIRequest aiRequest, PublicModelConfig publicModel, AIFeatureType featureType);

    /**
     * 积分预估响应DTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class CostEstimationResponse {
        private Long estimatedCost;
        private boolean success;
        private String errorMessage;
        private Integer estimatedInputTokens;
        private Integer estimatedOutputTokens;
        private String modelProvider;
        private String modelId;
        private Double creditMultiplier;

        public CostEstimationResponse(Long cost, boolean success) {
            this.estimatedCost = cost;
            this.success = success;
        }

        public CostEstimationResponse(Long cost, boolean success, String errorMessage) {
            this.estimatedCost = cost;
            this.success = success;
            this.errorMessage = errorMessage;
        }
    }
} 