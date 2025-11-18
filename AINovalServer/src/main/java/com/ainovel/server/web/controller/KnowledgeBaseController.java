package com.ainovel.server.web.controller;

import com.ainovel.server.common.exception.FanqieNovelException;
import com.ainovel.server.common.exception.KnowledgeBaseException;
import com.ainovel.server.common.exception.KnowledgeExtractionException;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.service.KnowledgeExtractionService;
import com.ainovel.server.service.NovelKnowledgeBaseService;
import com.ainovel.server.service.fanqie.FanqieNovelService;
import com.ainovel.server.web.dto.request.FanqieKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.request.KnowledgeBaseQueryRequest;
import com.ainovel.server.web.dto.request.TextKnowledgeExtractionRequest;
import com.ainovel.server.web.dto.request.PreviewSessionExtractionRequest;
import com.ainovel.server.web.dto.response.*;
import com.ainovel.server.service.ImportService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 知识库Controller
 * 提供番茄小说搜索、知识提取、知识库管理等功能
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/knowledge-bases")
@RequiredArgsConstructor
public class KnowledgeBaseController {
    
    private final NovelKnowledgeBaseService knowledgeBaseService;
    private final KnowledgeExtractionService extractionService;
    private final FanqieNovelService fanqieNovelService;
    private final ImportService importService;
    
    /**
     * 搜索番茄小说
     * 公开接口，无需认证
     */
    @GetMapping("/fanqie/search")
    public Mono<FanqieSearchResultResponse> searchFanqieNovels(@RequestParam String query) {
        log.info("搜索番茄小说: query={}", query);
        
        if (query == null || query.trim().isEmpty()) {
            return Mono.error(new FanqieNovelException("搜索关键词不能为空", "INVALID_QUERY"));
        }
        
        return fanqieNovelService.searchNovels(query)
                .flatMap(searchResult -> {
                    // 先获取所有小说ID
                    var novelIds = searchResult.getResults().stream()
                            .map(novelInfo -> novelInfo.getId())
                            .toList();
                    
                    log.info("搜索完成: query={}, 结果数={}, 开始批量检查缓存状态", query, novelIds.size());
                    
                    // ✅ 批量查询缓存状态
                    return knowledgeBaseService.getBatchCacheStatus(novelIds)
                            .map(cacheStatusMap -> {
                                // 映射结果并附加缓存状态
                                var novels = searchResult.getResults().stream()
                                        .map(novelInfo -> {
                                            var cacheStatus = cacheStatusMap.get(novelInfo.getId());
                                            return FanqieSearchResultResponse.FanqieNovelItem.builder()
                                                    .novelId(novelInfo.getId())
                                                    .title(novelInfo.getTitle())
                                                    .author(novelInfo.getAuthor())
                                                    .description(novelInfo.getDescription())
                                                    .coverImageUrl(novelInfo.getCover())
                                                    .category(novelInfo.getCategory())
                                                    .score(novelInfo.getScore())
                                                    .cached(cacheStatus != null && cacheStatus.isCached())
                                                    .knowledgeBaseId(cacheStatus != null ? cacheStatus.getKnowledgeBaseId() : null)
                                                    .build();
                                        })
                                        .toList();
                                
                                long cachedCount = novels.stream().filter(n -> Boolean.TRUE.equals(n.getCached())).count();
                                log.info("搜索结果处理完成: 总数={}, 已缓存={}", novels.size(), cachedCount);
                                
                                return FanqieSearchResultResponse.builder()
                                        .novels(novels)
                                        .build();
                            });
                })
                .onErrorMap(e -> {
                    if (e instanceof FanqieNovelException) {
                        return e;
                    }
                    log.error("搜索番茄小说失败: query={}, error={}", query, e.getMessage(), e);
                    return new FanqieNovelException("搜索番茄小说失败: " + e.getMessage(), "SEARCH_FAILED", e);
                });
    }
    
    /**
     * 获取番茄小说详情
     * 公开接口，无需认证
     */
    @GetMapping("/fanqie/{novelId}")
    public Mono<Map<String, Object>> getFanqieNovelDetail(@PathVariable String novelId) {
        log.info("获取番茄小说详情: novelId={}", novelId);
        
        if (novelId == null || novelId.trim().isEmpty()) {
            return Mono.error(new FanqieNovelException("小说ID不能为空", "INVALID_NOVEL_ID"));
        }
        
        return fanqieNovelService.getNovelDetail(novelId)
                .map(detail -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("novelId", detail.getId());
                    response.put("title", detail.getTitle());
                    response.put("author", detail.getAuthor());
                    response.put("description", detail.getDescription());
                    response.put("coverImageUrl", detail.getCoverImageUrl());
                    response.put("completionStatus", detail.getStatus());
                    response.put("chapterCount", detail.getTotalChapters());
                    
                    log.info("获取番茄小说详情成功: novelId={}, title={}", novelId, detail.getTitle());
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof FanqieNovelException) {
                        return e;
                    }
                    log.error("获取番茄小说详情失败: novelId={}, error={}", novelId, e.getMessage(), e);
                    return new FanqieNovelException("获取小说详情失败: " + e.getMessage(), "DETAIL_FETCH_FAILED", e);
                });
    }
    
    /**
     * 检查番茄小说缓存状态
     */
    @GetMapping("/fanqie/{novelId}/cache-status")
    public Mono<Map<String, Object>> checkCacheStatus(@PathVariable String novelId) {
        log.info("检查缓存状态: {}", novelId);
        
        return knowledgeBaseService.getByFanqieNovelId(novelId)
                .map(kb -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("cached", true);
                    response.put("knowledgeBaseId", kb.getId());
                    response.put("status", kb.getStatus().name());
                    response.put("cacheTime", kb.getCacheTime());
                    return response;
                })
                .switchIfEmpty(Mono.fromSupplier(() -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("cached", false);
                    return response;
                }));
    }
    
    /**
     * 从番茄小说提取知识库
     * 需要认证
     */
    @PostMapping("/extract/fanqie")
    public Mono<KnowledgeExtractionTaskResponse> extractFromFanqieNovel(
            @Valid @RequestBody FanqieKnowledgeExtractionRequest request,
            Authentication authentication) {
        
        // ✅ 正确获取userId：从Principal获取User对象，再取id
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("从番茄小说提取知识库: fanqieNovelId={}, userId={}", 
                request.getFanqieNovelId(), userId);
        
        return extractionService.extractFromFanqieNovel(request, userId)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeExtractionException) {
                        return e;
                    }
                    log.error("从番茄小说提取知识库失败: fanqieNovelId={}, userId={}, error={}", 
                            request.getFanqieNovelId(), userId, e.getMessage(), e);
                    return new KnowledgeExtractionException("知识提取失败: " + e.getMessage(), 
                            "EXTRACTION_FAILED", e);
                });
    }
    
    /**
     * 从用户文本提取知识库
     * 需要认证
     */
    @PostMapping("/extract/text")
    public Mono<KnowledgeExtractionTaskResponse> extractFromText(
            @Valid @RequestBody TextKnowledgeExtractionRequest request,
            Authentication authentication) {
        
        // ✅ 正确获取userId
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("从用户文本提取知识库: title={}, userId={}", request.getTitle(), userId);
        
        return extractionService.extractFromUserText(request, userId)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeExtractionException) {
                        return e;
                    }
                    log.error("从用户文本提取知识库失败: title={}, userId={}, error={}", 
                            request.getTitle(), userId, e.getMessage(), e);
                    return new KnowledgeExtractionException("知识提取失败: " + e.getMessage(), 
                            "EXTRACTION_FAILED", e);
                });
    }
    
    /**
     * 从预览会话提取知识库
     * 需要认证
     * 用于用户导入小说拆书功能
     */
    @PostMapping("/extract/from-preview")
    public Mono<KnowledgeExtractionTaskResponse> extractFromPreviewSession(
            @Valid @RequestBody PreviewSessionExtractionRequest request,
            Authentication authentication) {
        
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("从预览会话提取知识库: sessionId={}, title={}, chapterLimit={}, userId={}", 
                request.getPreviewSessionId(), request.getTitle(), request.getChapterLimit(), userId);
        
        // ✅ 先获取章节数量
        return importService.getTotalChapterCountFromPreviewSession(request.getPreviewSessionId())
                .flatMap(chapterCount -> 
                    // 然后获取完整文本内容（支持章节限制）
                    importService.getFullContentFromPreviewSession(request.getPreviewSessionId(), request.getChapterLimit())
                        .map(content -> new Object[]{content, chapterCount})
                )
                .flatMap(data -> {
                    String content = (String) data[0];
                    Integer totalChapterCount = (Integer) data[1];
                    
                    // 创建文本提取请求
                    TextKnowledgeExtractionRequest extractionRequest = TextKnowledgeExtractionRequest.builder()
                            .title(request.getTitle())
                            .content(content)
                            .description(request.getDescription())
                            .extractionTypes(request.getExtractionTypes())
                            .modelConfigId(request.getModelConfigId())
                            .modelType(request.getModelType())
                            .chapterCount(request.getChapterLimit() != null ? request.getChapterLimit() : totalChapterCount)  // ✅ 使用用户选择的章节限制
                            .previewSessionId(request.getPreviewSessionId())  // ✅ 传递previewSessionId
                            .build();
                    
                    log.info("从预览会话提取知识库: 文本长度={}, 用户选择章节数={}, 总章节数={}", 
                            content.length(), request.getChapterLimit(), totalChapterCount);
                    
                    // 调用提取服务
                    return extractionService.extractFromUserText(extractionRequest, userId);
                })
                // ⚠️ 不在这里清理预览会话！
                // 后台任务还需要使用previewSession获取章节详情
                // 清理操作会在TaskExecutor中获取完数据后执行
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeExtractionException) {
                        return e;
                    }
                    log.error("从预览会话提取知识库失败: sessionId={}, userId={}, error={}", 
                            request.getPreviewSessionId(), userId, e.getMessage(), e);
                    return new KnowledgeExtractionException("知识提取失败: " + e.getMessage(), 
                            "EXTRACTION_FAILED", e);
                });
    }
    
    /**
     * 获取拆书任务状态
     * 需要认证
     */
    @GetMapping("/extraction-task/{taskId}")
    public Mono<KnowledgeExtractionTaskResponse> getExtractionTaskStatus(
            @PathVariable String taskId,
            Authentication authentication) {
        
        // ✅ 正确获取userId
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("获取拆书任务状态: taskId={}, userId={}", taskId, userId);
        
        if (taskId == null || taskId.trim().isEmpty()) {
            return Mono.error(new KnowledgeExtractionException("任务ID不能为空", "INVALID_TASK_ID"));
        }
        
        return extractionService.getExtractionTaskStatus(taskId)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeExtractionException) {
                        return e;
                    }
                    log.error("获取拆书任务状态失败: taskId={}, userId={}, error={}", 
                            taskId, userId, e.getMessage(), e);
                    return new KnowledgeExtractionException("获取任务状态失败: " + e.getMessage(), 
                            "TASK_STATUS_FETCH_FAILED", e);
                });
    }
    
    /**
     * 查询公共知识库列表
     * 公开接口，无需认证
     */
    @GetMapping("/public")
    public Mono<KnowledgeBaseListResponse> queryPublicKnowledgeBases(
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) List<String> tags,
            @RequestParam(required = false) String completionStatus,
            @RequestParam(defaultValue = "likeCount") String sortBy,
            @RequestParam(defaultValue = "desc") String sortOrder,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        
        log.info("查询公共知识库列表: page={}, size={}", page, size);
        
        KnowledgeBaseQueryRequest request = KnowledgeBaseQueryRequest.builder()
                .keyword(keyword)
                .tags(tags)
                .completionStatus(completionStatus)
                .sortBy(sortBy)
                .sortOrder(sortOrder)
                .page(page)
                .size(size)
                .build();
        
        return knowledgeBaseService.queryPublicKnowledgeBases(request)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("查询公共知识库列表失败: page={}, size={}, error={}", 
                            page, size, e.getMessage(), e);
                    return new KnowledgeBaseException("查询知识库列表失败: " + e.getMessage(), 
                            "QUERY_FAILED", e);
                });
    }
    
    /**
     * 查询我的知识库列表
     * 需要认证
     */
    @GetMapping("/my")
    public Mono<KnowledgeBaseListResponse> queryMyKnowledgeBases(
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String sourceType, // user_imported / fanqie_novel
            @RequestParam(defaultValue = "importTime") String sortBy,
            @RequestParam(defaultValue = "desc") String sortOrder,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            Authentication authentication) {
        
        // ✅ 正确获取userId
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("查询我的知识库列表: userId={}, sourceType={}, page={}, size={}", 
                userId, sourceType, page, size);
        
        KnowledgeBaseQueryRequest request = KnowledgeBaseQueryRequest.builder()
                .keyword(keyword)
                .sourceType(sourceType)
                .sortBy(sortBy)
                .sortOrder(sortOrder)
                .page(page)
                .size(size)
                .build();
        
        return knowledgeBaseService.queryUserKnowledgeBases(userId, request)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("查询我的知识库列表失败: userId={}, page={}, size={}, error={}", 
                            userId, page, size, e.getMessage(), e);
                    return new KnowledgeBaseException("查询知识库列表失败: " + e.getMessage(), 
                            "QUERY_FAILED", e);
                });
    }
    
    /**
     * 获取知识库详情
     * 公开接口（可选认证，用于识别用户点赞状态）
     */
    @GetMapping("/{knowledgeBaseId}/detail")
    public Mono<KnowledgeBaseDetailResponse> getKnowledgeBaseDetail(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        // ✅ 正确获取userId（可能为null，公开接口）- 声明为final以在lambda中使用
        final String userId = (authentication != null && authentication.getPrincipal() instanceof User)
                ? ((User) authentication.getPrincipal()).getId()
                : null;
        log.info("获取知识库详情: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        if (knowledgeBaseId == null || knowledgeBaseId.trim().isEmpty()) {
            return Mono.error(new KnowledgeBaseException("知识库ID不能为空", "INVALID_ID"));
        }
        
        return knowledgeBaseService.getKnowledgeBaseDetail(knowledgeBaseId, userId)
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("获取知识库详情失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("获取知识库详情失败: " + e.getMessage(), 
                            "DETAIL_FETCH_FAILED", e);
                });
    }
    
    /**
     * 切换点赞
     * 需要认证
     * 点赞时为作者增加1积分
     */
    @PostMapping("/{knowledgeBaseId}/like")
    public Mono<Map<String, Object>> toggleLike(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        // ✅ 正确获取userId
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("切换点赞: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        if (knowledgeBaseId == null || knowledgeBaseId.trim().isEmpty()) {
            return Mono.error(new KnowledgeBaseException("知识库ID不能为空", "INVALID_ID"));
        }
        
        return knowledgeBaseService.toggleLike(knowledgeBaseId, userId)
                .map(isLiked -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", true);
                    response.put("isLiked", isLiked);
                    response.put("message", isLiked ? "点赞成功，作者获得1积分" : "取消点赞");
                    
                    log.info("点赞切换成功: knowledgeBaseId={}, userId={}, isLiked={}", 
                            knowledgeBaseId, userId, isLiked);
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("切换点赞失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("切换点赞失败: " + e.getMessage(), 
                            "LIKE_TOGGLE_FAILED", e);
                });
    }
    
    /**
     * 切换知识库分享状态
     * 需要认证
     * 只有知识库所有者可以设置分享
     */
    @PostMapping("/{knowledgeBaseId}/toggle-public")
    public Mono<Map<String, Object>> togglePublic(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("切换分享状态: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        if (knowledgeBaseId == null || knowledgeBaseId.trim().isEmpty()) {
            return Mono.error(new KnowledgeBaseException("知识库ID不能为空", "INVALID_ID"));
        }
        
        return knowledgeBaseService.togglePublic(knowledgeBaseId, userId)
                .map(isPublic -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", true);
                    response.put("isPublic", isPublic);
                    response.put("message", isPublic ? "已公开分享" : "已设为私密");
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("切换分享状态失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("操作失败: " + e.getMessage(), 
                            "TOGGLE_PUBLIC_FAILED", e);
                });
    }
    
    /**
     * 将知识库添加到我的小说
     * 需要认证
     */
    @PostMapping("/{knowledgeBaseId}/add-to-novel")
    public Mono<Map<String, Object>> addToNovel(
            @PathVariable String knowledgeBaseId,
            @RequestBody Map<String, String> request,
            Authentication authentication) {
        
        // ✅ 正确获取userId
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        String novelId = request.get("novelId");
        log.info("将知识库添加到小说: knowledgeBaseId={}, novelId={}, userId={}", 
                knowledgeBaseId, novelId, userId);
        
        if (knowledgeBaseId == null || knowledgeBaseId.trim().isEmpty()) {
            return Mono.error(new KnowledgeBaseException("知识库ID不能为空", "INVALID_KB_ID"));
        }
        
        if (novelId == null || novelId.trim().isEmpty()) {
            return Mono.error(new KnowledgeBaseException("小说ID不能为空", "INVALID_NOVEL_ID"));
        }
        
        return knowledgeBaseService.addToNovel(knowledgeBaseId, novelId, userId)
                .map(success -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", success);
                    response.put("message", success ? "知识库已成功添加到小说" : "添加失败");
                    
                    log.info("将知识库添加到小说完成: knowledgeBaseId={}, novelId={}, userId={}, success={}", 
                            knowledgeBaseId, novelId, userId, success);
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("将知识库添加到小说失败: knowledgeBaseId={}, novelId={}, userId={}, error={}", 
                            knowledgeBaseId, novelId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("添加知识库到小说失败: " + e.getMessage(), 
                            "ADD_TO_NOVEL_FAILED", e);
                });
    }
    
    /**
     * 添加到我的知识库
     * 需要认证
     */
    @PostMapping("/{knowledgeBaseId}/add-to-my")
    public Mono<Map<String, Object>> addToMyKnowledgeBase(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("添加到我的知识库: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        return knowledgeBaseService.addToMyKnowledgeBase(knowledgeBaseId, userId)
                .map(success -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", success);
                    response.put("message", success ? "已添加到我的知识库" : "添加失败");
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("添加到我的知识库失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("添加到我的知识库失败: " + e.getMessage(), 
                            "ADD_TO_MY_KB_FAILED", e);
                });
    }
    
    /**
     * 从我的知识库删除
     * 需要认证
     */
    @DeleteMapping("/{knowledgeBaseId}/remove-from-my")
    public Mono<Map<String, Object>> removeFromMyKnowledgeBase(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.info("从我的知识库删除: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        return knowledgeBaseService.removeFromMyKnowledgeBase(knowledgeBaseId, userId)
                .map(success -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("success", success);
                    response.put("message", success ? "已从我的知识库删除" : "删除失败");
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("从我的知识库删除失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("从我的知识库删除失败: " + e.getMessage(), 
                            "REMOVE_FROM_MY_KB_FAILED", e);
                });
    }
    
    /**
     * 检查是否在我的知识库中
     * 需要认证
     */
    @GetMapping("/{knowledgeBaseId}/is-in-my")
    public Mono<Map<String, Object>> isInMyKnowledgeBase(
            @PathVariable String knowledgeBaseId,
            Authentication authentication) {
        
        User user = (User) authentication.getPrincipal();
        String userId = user.getId();
        log.debug("检查是否在我的知识库中: knowledgeBaseId={}, userId={}", knowledgeBaseId, userId);
        
        return knowledgeBaseService.isInMyKnowledgeBase(knowledgeBaseId, userId)
                .map(isIn -> {
                    Map<String, Object> response = new HashMap<>();
                    response.put("isInMyKnowledgeBase", isIn);
                    return response;
                })
                .onErrorMap(e -> {
                    if (e instanceof KnowledgeBaseException) {
                        return e;
                    }
                    log.error("检查是否在我的知识库中失败: knowledgeBaseId={}, userId={}, error={}", 
                            knowledgeBaseId, userId, e.getMessage(), e);
                    return new KnowledgeBaseException("检查失败: " + e.getMessage(), 
                            "CHECK_MY_KB_FAILED", e);
                });
    }
}

