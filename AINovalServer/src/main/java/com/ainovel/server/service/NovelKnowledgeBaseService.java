package com.ainovel.server.service;

import com.ainovel.server.domain.model.NovelKnowledgeBase;
import com.ainovel.server.web.dto.request.KnowledgeBaseQueryRequest;
import com.ainovel.server.web.dto.response.KnowledgeBaseDetailResponse;
import com.ainovel.server.web.dto.response.KnowledgeBaseListResponse;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;

/**
 * 小说知识库服务接口
 */
public interface NovelKnowledgeBaseService {
    
    /**
     * 根据番茄小说ID查询知识库
     * 
     * @param fanqieNovelId 番茄小说ID
     * @return 知识库实体
     */
    Mono<NovelKnowledgeBase> getByFanqieNovelId(String fanqieNovelId);
    
    /**
     * 根据知识库ID查询
     * 
     * @param knowledgeBaseId 知识库ID
     * @return 知识库实体
     */
    Mono<NovelKnowledgeBase> getById(String knowledgeBaseId);
    
    /**
     * 创建知识库
     * 
     * @param knowledgeBase 知识库实体
     * @return 保存后的知识库实体
     */
    Mono<NovelKnowledgeBase> create(NovelKnowledgeBase knowledgeBase);
    
    /**
     * 更新知识库
     * 
     * @param knowledgeBase 知识库实体
     * @return 更新后的知识库实体
     */
    Mono<NovelKnowledgeBase> update(NovelKnowledgeBase knowledgeBase);
    
    /**
     * 增加引用次数
     * 
     * @param knowledgeBaseId 知识库ID
     * @return 更新后的知识库实体
     */
    Mono<NovelKnowledgeBase> incrementReferenceCount(String knowledgeBaseId);
    
    /**
     * 增加查看次数
     * 
     * @param knowledgeBaseId 知识库ID
     * @return 更新后的知识库实体
     */
    Mono<NovelKnowledgeBase> incrementViewCount(String knowledgeBaseId);
    
    /**
     * 切换点赞状态
     * 点赞时为作者增加1积分，取消点赞时扣除1积分
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 用户ID
     * @return 是否点赞（true=已点赞, false=取消点赞）
     */
    Mono<Boolean> toggleLike(String knowledgeBaseId, String userId);
    
    /**
     * 切换知识库公开状态
     * 只有知识库所有者可以操作
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 用户ID
     * @return 是否公开（true=公开, false=私密）
     */
    Mono<Boolean> togglePublic(String knowledgeBaseId, String userId);
    
    /**
     * 记录知识库引用
     * 引用时为作者增加1积分
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 引用用户ID
     * @return 操作结果
     */
    Mono<Void> recordReference(String knowledgeBaseId, String userId);
    
    /**
     * 查询公共知识库列表（分页、筛选、排序）
     * 
     * @param request 查询请求
     * @return 知识库列表响应
     */
    Mono<KnowledgeBaseListResponse> queryPublicKnowledgeBases(KnowledgeBaseQueryRequest request);
    
    /**
     * 查询用户的知识库列表（我的知识库）
     * 
     * @param userId 用户ID
     * @param request 查询请求
     * @return 知识库列表响应
     */
    Mono<KnowledgeBaseListResponse> queryUserKnowledgeBases(String userId, KnowledgeBaseQueryRequest request);
    
    /**
     * 获取知识库详情
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 当前用户ID（用于判断点赞状态等）
     * @return 知识库详情响应
     */
    Mono<KnowledgeBaseDetailResponse> getKnowledgeBaseDetail(String knowledgeBaseId, String userId);
    
    /**
     * 将知识库添加到用户的小说中
     * 
     * @param knowledgeBaseId 知识库ID
     * @param novelId 目标小说ID
     * @param userId 用户ID
     * @return 操作结果
     */
    Mono<Boolean> addToNovel(String knowledgeBaseId, String novelId, String userId);
    
    /**
     * 添加知识库到我的知识库
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 用户ID
     * @return 操作结果
     */
    Mono<Boolean> addToMyKnowledgeBase(String knowledgeBaseId, String userId);
    
    /**
     * 从我的知识库删除
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 用户ID
     * @return 操作结果
     */
    Mono<Boolean> removeFromMyKnowledgeBase(String knowledgeBaseId, String userId);
    
    /**
     * 检查知识库是否在我的知识库中
     * 
     * @param knowledgeBaseId 知识库ID
     * @param userId 用户ID
     * @return 是否存在
     */
    Mono<Boolean> isInMyKnowledgeBase(String knowledgeBaseId, String userId);
    
    /**
     * 批量查询缓存状态
     * 
     * @param fanqieNovelIds 番茄小说ID列表
     * @return Map<番茄小说ID, 缓存状态DTO>
     */
    Mono<Map<String, CacheStatusDTO>> getBatchCacheStatus(List<String> fanqieNovelIds);
    
    /**
     * 缓存状态DTO（内部类）
     */
    class CacheStatusDTO {
        private final boolean cached;
        private final String knowledgeBaseId;
        
        public CacheStatusDTO(boolean cached, String knowledgeBaseId) {
            this.cached = cached;
            this.knowledgeBaseId = knowledgeBaseId;
        }
        
        public boolean isCached() {
            return cached;
        }
        
        public String getKnowledgeBaseId() {
            return knowledgeBaseId;
        }
    }
}

