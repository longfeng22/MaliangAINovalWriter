package com.ainovel.server.repository;

import org.springframework.data.mongodb.repository.ReactiveMongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;

import com.ainovel.server.domain.model.ModelPricing;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 模型定价数据仓库
 */
@Repository
public interface ModelPricingRepository extends ReactiveMongoRepository<ModelPricing, String> {
    
    /**
     * 根据提供商查找所有激活的定价信息
     * 
     * @param provider 提供商名称
     * @return 定价信息列表
     */
    Flux<ModelPricing> findByProviderAndActiveTrue(String provider);
    
    /**
     * 根据提供商和模型ID查找定价信息
     * 
     * @param provider 提供商名称
     * @param modelId 模型ID
     * @return 定价信息
     */
    Mono<ModelPricing> findByProviderAndModelIdAndActiveTrue(String provider, String modelId);
    
    /**
     * 根据提供商和模型ID查找定价信息（包含非激活的）
     * 
     * @param provider 提供商名称
     * @param modelId 模型ID
     * @return 定价信息
     */
    Mono<ModelPricing> findByProviderAndModelId(String provider, String modelId);
    
    /**
     * 查找所有激活的定价信息
     * 
     * @return 定价信息列表
     */
    Flux<ModelPricing> findByActiveTrue();
    
    /**
     * 根据定价来源查找定价信息
     * 
     * @param source 定价来源
     * @return 定价信息列表
     */
    Flux<ModelPricing> findBySourceAndActiveTrue(ModelPricing.PricingSource source);
    
    /**
     * 根据提供商和定价来源查找定价信息
     * 
     * @param provider 提供商名称
     * @param source 定价来源
     * @return 定价信息列表
     */
    Flux<ModelPricing> findByProviderAndSourceAndActiveTrue(String provider, ModelPricing.PricingSource source);
    
    /**
     * 检查指定提供商和模型是否存在定价信息
     * 
     * @param provider 提供商名称
     * @param modelId 模型ID
     * @return 是否存在
     */
    Mono<Boolean> existsByProviderAndModelIdAndActiveTrue(String provider, String modelId);
    
    /**
     * 根据提供商删除所有定价信息（软删除）
     * 
     * @param provider 提供商名称
     * @return 更新数量
     */
    @Query("{ 'provider': ?0 }")
    Mono<Long> deactivateByProvider(String provider);
    
    /**
     * 获取所有支持的提供商列表
     * 
     * @return 提供商列表
     */
    @Query(value = "{ 'active': true }", fields = "{ 'provider': 1, '_id': 0 }")
    Flux<String> findDistinctProviders();
    
    /**
     * 根据价格范围查找模型
     * 
     * @param minPrice 最小价格
     * @param maxPrice 最大价格
     * @return 定价信息列表
     */
    @Query("{ 'active': true, $or: [ " +
           "{ 'inputPricePerThousandTokens': { $gte: ?0, $lte: ?1 } }, " +
           "{ 'outputPricePerThousandTokens': { $gte: ?0, $lte: ?1 } }, " +
           "{ 'unifiedPricePerThousandTokens': { $gte: ?0, $lte: ?1 } } ] }")
    Flux<ModelPricing> findByPriceRange(Double minPrice, Double maxPrice);
    
    /**
     * 根据最大token数范围查找模型
     * 
     * @param minTokens 最小token数
     * @param maxTokens 最大token数
     * @return 定价信息列表
     */
    @Query("{ 'active': true, 'maxContextTokens': { $gte: ?0, $lte: ?1 } }")
    Flux<ModelPricing> findByTokenRange(Integer minTokens, Integer maxTokens);
    
    /**
     * 根据模型ID查找相同模型ID的所有定价信息（跨提供商）
     * 
     * @param modelId 模型ID
     * @return 定价信息列表
     */
    Flux<ModelPricing> findByModelIdAndActiveTrue(String modelId);
    
    /**
     * 根据模型名称查找定价信息
     * 
     * @param modelName 模型名称
     * @return 定价信息列表
     */
    Flux<ModelPricing> findByModelNameAndActiveTrue(String modelName);
    
    /**
     * 根据模型ID前缀查找定价信息
     * 
     * @param modelIdPrefix 模型ID前缀
     * @return 定价信息列表
     */
    @Query("{ 'active': true, 'modelId': { $regex: '^?0', $options: 'i' } }")
    Flux<ModelPricing> findByModelIdStartingWithIgnoreCase(String modelIdPrefix);
}