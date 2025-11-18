package com.ainovel.server.service.impl;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.repository.PublicModelConfigRepository;
import com.ainovel.server.repository.UserRepository;
import com.ainovel.server.service.AIFeatureAuthorizationService;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.RoleService;
import com.ainovel.server.security.PermissionConstants;

import reactor.core.publisher.Mono;

/**
 * AI功能授权服务实现
 */
@Service
public class AIFeatureAuthorizationServiceImpl implements AIFeatureAuthorizationService {
    
    private final UserRepository userRepository;
    private final RoleService roleService;
    private final CreditService creditService;
    private final PublicModelConfigRepository publicModelConfigRepository;
    
    @Autowired
    public AIFeatureAuthorizationServiceImpl(UserRepository userRepository,
                                           RoleService roleService,
                                           CreditService creditService,
                                           PublicModelConfigRepository publicModelConfigRepository) {
        this.userRepository = userRepository;
        this.roleService = roleService;
        this.creditService = creditService;
        this.publicModelConfigRepository = publicModelConfigRepository;
    }
    
    @Override
    public Mono<Boolean> hasFeaturePermission(String userId, AIFeatureType featureType) {
        return userRepository.findById(userId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + userId)))
                .flatMap(user -> {
                    if (!user.isActive()) {
                        return Mono.just(false);
                    }
                    
                    return roleService.getUserPermissions(user.getRoleIds())
                            .map(permissions -> {
                                String requiredPermission = getRequiredPermission(featureType);
                                return permissions.contains(requiredPermission);
                            });
                });
    }
    
    @Override
    public Mono<AIFeatureAuthorizationResult> authorizeFeatureUsage(String userId, String provider, String modelId, 
                                                                   AIFeatureType featureType, int estimatedInputTokens, int estimatedOutputTokens) {
        
        return Mono.zip(
                hasFeaturePermission(userId, featureType),
                validateModelAvailability(provider, modelId, featureType),
                creditService.calculateCreditCost(provider, modelId, featureType, estimatedInputTokens, estimatedOutputTokens),
                creditService.getUserCredits(userId)
        ).map(tuple -> {
            boolean hasPermission = tuple.getT1();
            boolean modelAvailable = tuple.getT2();
            long estimatedCost = tuple.getT3();
            long userCredits = tuple.getT4();
            
            if (!hasPermission) {
                return AIFeatureAuthorizationResult.denied("您没有权限使用此功能: " + featureType);
            }
            
            if (!modelAvailable) {
                return AIFeatureAuthorizationResult.denied("模型不可用或不支持此功能: " + provider + ":" + modelId);
            }
            
            if (userCredits < estimatedCost) {
                return AIFeatureAuthorizationResult.denied("积分余额不足，需要 " + estimatedCost + " 积分，当前余额 " + userCredits);
            }
            
            return AIFeatureAuthorizationResult.authorized(estimatedCost);
        }).onErrorResume(throwable -> 
            Mono.just(AIFeatureAuthorizationResult.denied("授权检查失败: " + throwable.getMessage()))
        );
    }
    
    @Override
    @Transactional
    public Mono<AIFeatureExecutionResult> executeFeatureWithCredits(String userId, String provider, String modelId, 
                                                                   AIFeatureType featureType, int inputTokens, int outputTokens) {
        
        // 首先检查权限和模型可用性
        return authorizeFeatureUsage(userId, provider, modelId, featureType, inputTokens, outputTokens)
                .flatMap(authResult -> {
                    if (!authResult.isAuthorized()) {
                        return Mono.just(AIFeatureExecutionResult.failure(authResult.getMessage()));
                    }
                    
                    // 执行积分扣减
                    return creditService.deductCreditsForAI(userId, provider, modelId, featureType, inputTokens, outputTokens)
                            .map(deductionResult -> {
                                if (deductionResult.isSuccess()) {
                                    return AIFeatureExecutionResult.success(deductionResult.getCreditsDeducted());
                                } else {
                                    return AIFeatureExecutionResult.failure(deductionResult.getMessage());
                                }
                            });
                })
                .onErrorResume(throwable -> 
                    Mono.just(AIFeatureExecutionResult.failure("执行失败: " + throwable.getMessage()))
                );
    }
    
    private String getRequiredPermission(AIFeatureType featureType) {
        return switch (featureType) {
            case SCENE_TO_SUMMARY -> PermissionConstants.FEATURE_SCENE_TO_SUMMARY;
            case SUMMARY_TO_SCENE -> PermissionConstants.FEATURE_SUMMARY_TO_SCENE;
            case TEXT_EXPANSION -> PermissionConstants.FEATURE_TEXT_EXPANSION;
            case TEXT_REFACTOR -> PermissionConstants.FEATURE_TEXT_REFACTOR;
            case TEXT_SUMMARY -> PermissionConstants.FEATURE_TEXT_SUMMARY;
            case AI_CHAT -> PermissionConstants.FEATURE_AI_CHAT;
            case NOVEL_GENERATION -> PermissionConstants.FEATURE_NOVEL_GENERATION;
            case PROFESSIONAL_FICTION_CONTINUATION -> PermissionConstants.FEATURE_PROFESSIONAL_FICTION_CONTINUATION;
            case SCENE_BEAT_GENERATION -> PermissionConstants.FEATURE_SCENE_BEAT_GENERATION;
            case SETTING_TREE_GENERATION -> PermissionConstants.FEATURE_SETTING_TREE_GENERATION;
            case SETTING_GENERATION_TOOL -> PermissionConstants.FEATURE_SETTING_TREE_GENERATION;
            case NOVEL_COMPOSE -> PermissionConstants.FEATURE_NOVEL_COMPOSE;
            default -> { throw new IllegalArgumentException("Unsupported feature type: " + featureType); }
        };
    }
    
    private Mono<Boolean> validateModelAvailability(String provider, String modelId, AIFeatureType featureType) {
        return publicModelConfigRepository.findByProviderAndModelId(provider, modelId)
                .map(config -> config.isEnabledForFeature(featureType))
                .defaultIfEmpty(false);
    }
}