package com.ainovel.server.service.ai.observability;

import com.ainovel.server.common.response.PagedResponse;
import com.ainovel.server.common.response.CursorPageResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import com.ainovel.server.domain.model.observability.LLMTrace;
import com.ainovel.server.repository.LLMTraceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import org.springframework.data.mongodb.core.aggregation.*;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * LLM链路追踪服务
 * 负责追踪数据的持久化和查询
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class LLMTraceService {

    private final LLMTraceRepository repository;
    @Autowired(required = false)
    private ReactiveMongoTemplate mongoTemplate;

    /**
     * 保存追踪记录 - 使用 MongoDB Upsert 避免竞态条件
     */
    public Mono<LLMTrace> save(LLMTrace trace) {
        // 基本参数验证
        if (trace == null) {
            return Mono.error(new IllegalArgumentException("trace 不能为空"));
        }
        
        // 如果没有 traceId，直接使用普通保存（无法进行 upsert）
        if (trace.getTraceId() == null || trace.getTraceId().isBlank()) {
            return repository.save(trace)
                    .doOnSuccess(saved -> log.debug("LLM追踪记录已保存(无traceId): objectId={}, provider={}, model={}",
                            saved.getId(), saved.getProvider(), saved.getModel()))
                    .doOnError(error -> log.error("保存LLM追踪记录失败(无traceId): provider={}, model={}", 
                            trace.getProvider(), trace.getModel(), error));
        }

        // 🔧 修复：使用 MongoDB 原子 upsert 操作避免竞态条件
        return upsertByTraceId(trace)
                .doOnSuccess(saved -> {
                    // 根据操作类型记录不同的日志
                    boolean isUpdate = saved.getId() != null && !saved.getId().equals(trace.getId());
                    if (isUpdate) {
                        log.info("🔄 LLM追踪记录已更新(upsert): traceId={}, objectId={}, provider={}, model={}",
                                saved.getTraceId(), saved.getId(), saved.getProvider(), saved.getModel());
                    } else {
                        log.info("✨ LLM追踪记录已新建(upsert): traceId={}, objectId={}, provider={}, model={}",
                                saved.getTraceId(), saved.getId(), saved.getProvider(), saved.getModel());
                    }
                })
                .doOnError(error -> {
                    // 检查是否是因为唯一索引冲突导致的错误
                    if (error.getMessage() != null && error.getMessage().contains("duplicate key")) {
                        log.warn("⚠️ 检测到traceId重复，这可能是正常的并发访问: traceId={}, error={}", 
                                trace.getTraceId(), error.getMessage());
                    } else {
                        log.error("❌ 保存LLM追踪记录失败(upsert): traceId={}, provider={}, model={}", 
                                trace.getTraceId(), trace.getProvider(), trace.getModel(), error);
                    }
                });
    }

    /**
     * 🔧 新增：基于 traceId 的原子 upsert 操作
     * 使用 MongoDB 的原子操作避免竞态条件
     */
    private Mono<LLMTrace> upsertByTraceId(LLMTrace trace) {
        if (mongoTemplate == null) {
            // 如果没有 ReactiveMongoTemplate，回退到传统方式
            log.warn("ReactiveMongoTemplate 未配置，回退到传统保存方式: traceId={}", trace.getTraceId());
            return repository.save(trace);
        }

        // 构建查询条件：根据 traceId 查找
        Query query = new Query(Criteria.where("traceId").is(trace.getTraceId()));
        
        // 构建更新操作：设置所有字段（完整替换，除了保持原有的 _id）
        Update update = new Update()
                .set("traceId", trace.getTraceId())
                .set("userId", trace.getUserId())
                .set("sessionId", trace.getSessionId())
                .set("correlationId", trace.getCorrelationId())
                .set("provider", trace.getProvider())
                .set("model", trace.getModel())
                .set("type", trace.getType())
                .set("businessType", trace.getBusinessType())
                .set("request", trace.getRequest())
                .set("response", trace.getResponse())
                .set("error", trace.getError())
                .set("performance", trace.getPerformance())
                .set("createdAt", trace.getCreatedAt() != null ? trace.getCreatedAt() : java.time.Instant.now());

        // 执行原子 upsert 操作
        return mongoTemplate.upsert(query, update, LLMTrace.class)
                .flatMap(updateResult -> {
                    // 获取操作后的完整文档
                    if (updateResult.getUpsertedId() != null) {
                        // 新插入的文档，根据新生成的 _id 查询
                        return mongoTemplate.findById(updateResult.getUpsertedId().asObjectId().getValue(), LLMTrace.class);
                    } else {
                        // 更新的现有文档，根据 traceId 查询
                        return mongoTemplate.findOne(query, LLMTrace.class);
                    }
                })
                .switchIfEmpty(Mono.error(new RuntimeException("Upsert 操作失败：无法获取操作后的文档")));
    }

    /**
     * 根据用户ID查询追踪记录
     */
    public Flux<LLMTrace> findByUserId(String userId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        return repository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
    }

    /**
     * 根据会话ID查询追踪记录
     */
    public Flux<LLMTrace> findBySessionId(String sessionId) {
        return repository.findBySessionIdOrderByCreatedAtDesc(sessionId);
    }

    /**
     * 查询性能统计信息
     */
    public Mono<PerformanceStats> getPerformanceStats(String provider, String model, Instant start, Instant end) {
        return repository.findByCreatedAtBetweenOrderByCreatedAtDesc(start, end, PageRequest.of(0, 1000))
                .filter(trace -> (provider == null || provider.equals(trace.getProvider())) &&
                               (model == null || model.equals(trace.getModel())))
                .collectList()
                .map(traces -> {
                    if (traces.isEmpty()) {
                        return new PerformanceStats();
                    }

                    long totalCalls = traces.size();
                    long errorCalls = traces.stream()
                            .mapToLong(trace -> trace.getError() != null ? 1 : 0)
                            .sum();

                    double avgDuration = traces.stream()
                            .filter(trace -> trace.getPerformance() != null && trace.getPerformance().getTotalDurationMs() != null)
                            .mapToLong(trace -> trace.getPerformance().getTotalDurationMs())
                            .average()
                            .orElse(0.0);

                    return PerformanceStats.builder()
                            .totalCalls(totalCalls)
                            .errorCalls(errorCalls)
                            .successRate((totalCalls - errorCalls) / (double) totalCalls * 100)
                            .avgDurationMs(avgDuration)
                            .build();
                });
    }

    /**
     * 性能统计数据
     */
    @lombok.Data
    @lombok.Builder
    @lombok.NoArgsConstructor
    @lombok.AllArgsConstructor
    public static class PerformanceStats {
        private long totalCalls;
        private long errorCalls;
        private double successRate;
        private double avgDurationMs;
    }

    // ==================== 管理后台专用方法 ====================

    /**
     * 获取所有追踪记录（分页）
     */
    public Flux<LLMTrace> findAllTraces(Pageable pageable) {
        return repository.findAllByOrderByCreatedAtDesc(pageable);
    }

    /**
     * 根据用户ID查询追踪记录（分页）
     */
    public Flux<LLMTrace> findTracesByUserId(String userId, Pageable pageable) {
        return repository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
    }

    /**
     * 根据提供商查询追踪记录（分页）
     */
    public Flux<LLMTrace> findTracesByProvider(String provider, Pageable pageable) {
        return repository.findByProviderOrderByCreatedAtDesc(provider, pageable);
    }

    /**
     * 根据模型查询追踪记录（分页）
     */
    public Flux<LLMTrace> findTracesByModel(String model, Pageable pageable) {
        return repository.findByModelOrderByCreatedAtDesc(model, pageable);
    }

    /**
     * 根据时间范围查询追踪记录（分页）
     */
    public Flux<LLMTrace> findTracesByTimeRange(LocalDateTime startTime, LocalDateTime endTime, Pageable pageable) {
        Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
        Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
        return repository.findByCreatedAtBetweenOrderByCreatedAtDesc(start, end, pageable);
    }

    /**
     * 搜索追踪记录
     */
    public Flux<LLMTrace> searchTraces(String userId, String provider, String model, String sessionId,
            Boolean hasError, String businessType, String correlationId, String traceId, LLMTrace.CallType type,
            String tag,
            LocalDateTime startTime, LocalDateTime endTime, Pageable pageable) {
        
        // 基础查询
        Flux<LLMTrace> baseQuery;
        if (startTime != null && endTime != null) {
            baseQuery = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            baseQuery = repository.findAll();
        }
        
        // 应用过滤条件
        return baseQuery
                .filter(trace -> userId == null || userId.equals(trace.getUserId()))
                .filter(trace -> provider == null || provider.equals(trace.getProvider()))
                .filter(trace -> model == null || model.equals(trace.getModel()))
                .filter(trace -> sessionId == null || sessionId.equals(trace.getSessionId()))
                .filter(trace -> hasError == null || 
                        (hasError && trace.getError() != null) || 
                        (!hasError && trace.getError() == null))
                .filter(trace -> businessType == null || businessType.equals(trace.getBusinessType()))
                .filter(trace -> correlationId == null || correlationId.equals(trace.getCorrelationId()))
                .filter(trace -> traceId == null || traceId.equals(trace.getTraceId()))
                .filter(trace -> type == null || type.equals(trace.getType()))
                .filter(trace -> tag == null || hasTag(trace, tag))
                .sort((t1, t2) -> t2.getCreatedAt().compareTo(t1.getCreatedAt()))
                .skip(pageable.getOffset())
                .take(pageable.getPageSize());
    }

    /**
     * 根据ID查询单个追踪记录
     */
    public Mono<LLMTrace> findTraceById(String traceId) {
        return repository.findByTraceId(traceId);
    }

    /**
     * 🔧 修复：根据traceId查询第一个匹配的追踪记录（处理重复记录的情况）
     */
    public Mono<LLMTrace> findFirstByTraceId(String traceId) {
        return repository.findFirstByTraceId(traceId)
                .doOnSuccess(trace -> {
                    if (trace != null) {
                        log.debug("找到第一个匹配的trace记录: traceId={}, objectId={}", traceId, trace.getId());
                    }
                });
    }

    // ==================== 管理后台分页响应方法 ====================

    /**
     * 获取所有追踪记录（分页响应）
     */
    public Mono<PagedResponse<LLMTrace>> findAllTracesPageable(int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        
        return Mono.zip(
                repository.findAllByOrderByCreatedAtDesc(pageable).collectList(),
                repository.count()
        ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
    }

    /**
     * 根据用户ID查询追踪记录（分页响应）
     */
    public Mono<PagedResponse<LLMTrace>> findTracesByUserIdPageable(String userId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        
        return Mono.zip(
                repository.findByUserIdOrderByCreatedAtDesc(userId, pageable).collectList(),
                repository.countByUserId(userId)
        ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
    }

    /**
     * 根据提供商查询追踪记录（分页响应）
     */
    public Mono<PagedResponse<LLMTrace>> findTracesByProviderPageable(String provider, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        
        return Mono.zip(
                repository.findByProviderOrderByCreatedAtDesc(provider, pageable).collectList(),
                repository.countByProvider(provider)
        ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
    }

    /**
     * 根据模型查询追踪记录（分页响应）
     */
    public Mono<PagedResponse<LLMTrace>> findTracesByModelPageable(String model, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        
        return Mono.zip(
                repository.findByModelOrderByCreatedAtDesc(model, pageable).collectList(),
                repository.countByModel(model)
        ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
    }

    /**
     * 根据时间范围查询追踪记录（分页响应）
     */
    public Mono<PagedResponse<LLMTrace>> findTracesByTimeRangePageable(LocalDateTime startTime, LocalDateTime endTime, int page, int size) {
        Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
        Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
        Pageable pageable = PageRequest.of(page, size);
        
        return Mono.zip(
                repository.findByCreatedAtBetweenOrderByCreatedAtDesc(start, end, pageable).collectList(),
                repository.countByCreatedAtBetween(start, end)
        ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
    }

    /**
     * 搜索追踪记录（分页响应）
     * 注意：由于复杂的过滤条件，这里使用内存过滤，性能可能不如数据库查询
     */
    public Mono<PagedResponse<LLMTrace>> searchTracesPageable(String userId, String provider, String model, String sessionId,
            Boolean hasError, String businessType, String correlationId, String traceId, LLMTrace.CallType type,
            String tag,
            LocalDateTime startTime, LocalDateTime endTime, int page, int size) {
        
        // 基础查询 - 先获取所有数据进行过滤
        Flux<LLMTrace> baseQuery;
        
        if (startTime != null && endTime != null) {
            Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
            Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
            baseQuery = repository.findByCreatedAtBetweenOrderByCreatedAtDesc(start, end, Pageable.unpaged());
        } else {
            baseQuery = repository.findAllByOrderByCreatedAtDesc(Pageable.unpaged());
        }
        
        // 应用过滤条件
        Flux<LLMTrace> filteredQuery = baseQuery
                .filter(trace -> userId == null || userId.equals(trace.getUserId()))
                .filter(trace -> provider == null || provider.equals(trace.getProvider()))
                .filter(trace -> model == null || model.equals(trace.getModel()))
                .filter(trace -> sessionId == null || sessionId.equals(trace.getSessionId()))
                .filter(trace -> hasError == null || 
                        (hasError && trace.getError() != null) || 
                        (!hasError && trace.getError() == null))
                .filter(trace -> businessType == null || businessType.equals(trace.getBusinessType()))
                .filter(trace -> correlationId == null || correlationId.equals(trace.getCorrelationId()))
                .filter(trace -> traceId == null || traceId.equals(trace.getTraceId()))
                .filter(trace -> type == null || type.equals(trace.getType()))
                .filter(trace -> tag == null || hasTag(trace, tag));
        
        // 分页处理
        return filteredQuery
                .collectList()
                .map(allFilteredResults -> {
                    long totalElements = allFilteredResults.size();
                    int startIndex = page * size;
                    int endIndex = Math.min(startIndex + size, allFilteredResults.size());
                    
                    List<LLMTrace> pageContent;
                    if (startIndex < allFilteredResults.size()) {
                        pageContent = allFilteredResults.subList(startIndex, endIndex);
                    } else {
                        pageContent = new ArrayList<>();
                    }
                    
                    return PagedResponse.of(pageContent, page, size, totalElements);
                });
    }

    private boolean hasTag(LLMTrace trace, String tag) {
        if (tag == null || tag.isEmpty()) return true;
        try {
            // 尝试从请求参数中读取标签信息（约定 providerSpecific.labels 或 providerSpecific.tags）
            Map<String, Object> providerSpecific = trace.getRequest() != null && trace.getRequest().getParameters() != null
                    ? trace.getRequest().getParameters().getProviderSpecific() : null;
            if (providerSpecific == null || providerSpecific.isEmpty()) return false;

            Object labels = providerSpecific.getOrDefault("labels", providerSpecific.get("tags"));
            if (labels == null) return false;
            if (labels instanceof String) {
                return ((String) labels).contains(tag);
            }
            if (labels instanceof List) {
                @SuppressWarnings("unchecked")
                List<Object> list = (List<Object>) labels;
                for (Object v : list) {
                    if (v != null && v.toString().equals(tag)) return true;
                }
            }
        } catch (Exception ignored) {
        }
        return false;
    }

    /**
     * 应用过滤条件，返回全部匹配结果（用于导出）
     */
    public Mono<List<LLMTrace>> filterAll(String userId, String provider, String model, String sessionId,
                                          Boolean hasError, String businessType, String correlationId, String traceId,
                                          LLMTrace.CallType type, String tag,
                                          LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> baseQuery;
        if (startTime != null && endTime != null) {
            Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
            Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
            baseQuery = repository.findByCreatedAtBetweenOrderByCreatedAtDesc(start, end, Pageable.unpaged());
        } else {
            baseQuery = repository.findAllByOrderByCreatedAtDesc(Pageable.unpaged());
        }

        return baseQuery
                .filter(trace -> userId == null || userId.equals(trace.getUserId()))
                .filter(trace -> provider == null || provider.equals(trace.getProvider()))
                .filter(trace -> model == null || model.equals(trace.getModel()))
                .filter(trace -> sessionId == null || sessionId.equals(trace.getSessionId()))
                .filter(trace -> hasError == null ||
                        (hasError && trace.getError() != null) ||
                        (!hasError && trace.getError() == null))
                .filter(trace -> businessType == null || businessType.equals(trace.getBusinessType()))
                .filter(trace -> correlationId == null || correlationId.equals(trace.getCorrelationId()))
                .filter(trace -> traceId == null || traceId.equals(trace.getTraceId()))
                .filter(trace -> type == null || type.equals(trace.getType()))
                .filter(trace -> tag == null || hasTag(trace, tag))
                .collectList();
    }

    /**
     * 统计趋势数据（按小时或天聚合）
     */
    public Mono<Map<String, Object>> getTrends(String metric, String groupBy,
                                               String businessType, String model, String provider,
                                               String interval,
                                               LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces
                .filter(t -> businessType == null || businessType.equals(t.getBusinessType()))
                .filter(t -> model == null || model.equals(t.getModel()))
                .filter(t -> provider == null || provider.equals(t.getProvider()))
                .collectList()
                .map(list -> buildTrendResponse(list, metric, groupBy, interval));
    }

    private Map<String, Object> buildTrendResponse(List<LLMTrace> list, String metric, String groupBy, String interval) {
        Map<String, Object> result = new HashMap<>();
        List<Map<String, Object>> series = new ArrayList<>();

        // 分桶
        Map<String, List<LLMTrace>> buckets = new HashMap<>();
        for (LLMTrace t : list) {
            java.time.ZonedDateTime zdt = t.getCreatedAt().atZone(java.time.ZoneId.systemDefault());
            String key = "day".equalsIgnoreCase(interval)
                    ? String.format("%04d-%02d-%02d", zdt.getYear(), zdt.getMonthValue(), zdt.getDayOfMonth())
                    : String.format("%04d-%02d-%02d %02d:00", zdt.getYear(), zdt.getMonthValue(), zdt.getDayOfMonth(), zdt.getHour());
            buckets.computeIfAbsent(key, k -> new ArrayList<>()).add(t);
        }

        List<String> sortedKeys = new ArrayList<>(buckets.keySet());
        sortedKeys.sort(String::compareTo);

        for (String key : sortedKeys) {
            List<LLMTrace> bucket = buckets.get(key);
            Map<String, Object> point = new HashMap<>();
            point.put("timestamp", key);

            switch (metric == null ? "count" : metric) {
                case "count": {
                    int cnt = bucket.size();
                    point.put("value", cnt);
                    break;
                }
                case "avgLatency": {
                    double avg = bucket.stream()
                            .filter(t -> t.getPerformance() != null && t.getPerformance().getTotalDurationMs() != null)
                            .mapToLong(t -> t.getPerformance().getTotalDurationMs())
                            .average().orElse(0);
                    point.put("value", avg);
                    break;
                }
                case "p90Latency": {
                    point.put("value", percentileLatency(bucket, 90));
                    break;
                }
                case "p95Latency": {
                    point.put("value", percentileLatency(bucket, 95));
                    break;
                }
                case "tokens": {
                    int tokens = bucket.stream()
                            .mapToInt(t -> {
                                try {
                                    return t.getResponse() != null && t.getResponse().getMetadata() != null
                                            && t.getResponse().getMetadata().getTokenUsage() != null
                                            && t.getResponse().getMetadata().getTokenUsage().getTotalTokenCount() != null
                                            ? t.getResponse().getMetadata().getTokenUsage().getTotalTokenCount() : 0;
                                } catch (Exception e) { return 0; }
                            })
                            .sum();
                    point.put("value", tokens);
                    break;
                }
                case "successRate":
                default: {
                    long total = bucket.size();
                    long success = bucket.stream().filter(t -> t.getError() == null).count();
                    point.put("value", total == 0 ? 0 : (double) success / total * 100);
                }
            }

            series.add(point);
        }

        result.put("series", series);
        result.put("metric", metric);
        result.put("interval", interval);
        return result;
    }

    private double percentileLatency(List<LLMTrace> traces, int percentile) {
        List<Long> values = traces.stream()
                .filter(t -> t.getPerformance() != null && t.getPerformance().getTotalDurationMs() != null)
                .map(t -> t.getPerformance().getTotalDurationMs())
                .sorted()
                .toList();
        if (values.isEmpty()) return 0;
        int index = (int) Math.ceil(percentile / 100.0 * values.size()) - 1;
        if (index < 0) index = 0;
        if (index >= values.size()) index = values.size() - 1;
        return values.get(index);
    }

    /**
     * 获取统计概览 - 使用MongoDB聚合查询（高性能）
     * 过滤掉知识库拆书和章节大纲提取类型
     */
    public Mono<Map<String, Object>> getOverviewStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        if (mongoTemplate == null) {
            log.warn("ReactiveMongoTemplate未配置，回退到传统查询方式");
            return getOverviewStatisticsLegacy(startTime, endTime);
        }

        try {
            List<AggregationOperation> operations = new ArrayList<>();
            
            // 构建匹配条件
            List<Criteria> criteriaList = new ArrayList<>();
            
            // 时间范围过滤
            if (startTime != null && endTime != null) {
                Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
                Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
                criteriaList.add(Criteria.where("createdAt").gte(start).lte(end));
            }
            
            // ✅ 过滤掉知识库拆书和章节大纲提取
            criteriaList.add(Criteria.where("businessType")
                    .nin("KNOWLEDGE_EXTRACTION", "OUTLINE_EXTRACTION", 
                         "KNOWLEDGE_EXTRACTION_FANQIE", "KNOWLEDGE_EXTRACTION_TEXT"));
            
            if (!criteriaList.isEmpty()) {
                operations.add(Aggregation.match(new Criteria().andOperator(
                        criteriaList.toArray(new Criteria[0]))));
            }
            
            // 聚合统计
            operations.add(Aggregation.group()
                    .count().as("totalCalls")
                    .sum(ConditionalOperators.when(Criteria.where("error").is(null)).then(1).otherwise(0)).as("successfulCalls")
                    .sum(ConditionalOperators.when(Criteria.where("error").ne(null)).then(1).otherwise(0)).as("failedCalls")
                    .avg("performance.requestLatencyMs").as("averageLatency")
                    .sum("response.metadata.tokenUsage.totalTokenCount").as("totalTokens"));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "llm_traces", Map.class)
                    .next()
                    .map(result -> {
                        Map<String, Object> stats = new HashMap<>();
                        long totalCalls = ((Number) result.getOrDefault("totalCalls", 0)).longValue();
                        long successfulCalls = ((Number) result.getOrDefault("successfulCalls", 0)).longValue();
                        long failedCalls = ((Number) result.getOrDefault("failedCalls", 0)).longValue();
                        
                        stats.put("totalCalls", totalCalls);
                        stats.put("successfulCalls", successfulCalls);
                        stats.put("failedCalls", failedCalls);
                        stats.put("successRate", totalCalls == 0 ? 0.0 : (double) successfulCalls / totalCalls * 100);
                        stats.put("averageLatency", result.getOrDefault("averageLatency", 0.0));
                        stats.put("totalTokens", ((Number) result.getOrDefault("totalTokens", 0)).intValue());
                        
                        log.info("✅ 聚合统计完成: totalCalls={}, successfulCalls={}, failedCalls={}", 
                                totalCalls, successfulCalls, failedCalls);
                        return stats;
                    })
                    .defaultIfEmpty(createEmptyStats());
        } catch (Exception e) {
            log.error("聚合查询失败，回退到传统方式", e);
            return getOverviewStatisticsLegacy(startTime, endTime);
        }
    }
    
    /**
     * 传统方式的统计概览（回退方案）
     */
    private Mono<Map<String, Object>> getOverviewStatisticsLegacy(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces
                // ✅ 过滤掉知识库相关类型
                .filter(t -> {
                    String bt = t.getBusinessType();
                    return bt == null || (!bt.equals("KNOWLEDGE_EXTRACTION") && 
                            !bt.equals("OUTLINE_EXTRACTION") &&
                            !bt.equals("KNOWLEDGE_EXTRACTION_FANQIE") &&
                            !bt.equals("KNOWLEDGE_EXTRACTION_TEXT"));
                })
                .collectList()
                .map(traceList -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("totalCalls", traceList.size());
                    
                    long successfulCalls = traceList.stream().filter(t -> t.getError() == null).count();
                    long failedCalls = traceList.stream().filter(t -> t.getError() != null).count();
                    
                    stats.put("successfulCalls", successfulCalls);
                    stats.put("failedCalls", failedCalls);
                    stats.put("successRate", traceList.isEmpty() ? 0.0 : (double) successfulCalls / traceList.size() * 100);
                    
                    if (!traceList.isEmpty()) {
                        double avgLatency = traceList.stream()
                                .filter(trace -> trace.getPerformance() != null && trace.getPerformance().getRequestLatencyMs() != null)
                                .mapToLong(trace -> trace.getPerformance().getRequestLatencyMs())
                                .average()
                                .orElse(0.0);
                        stats.put("averageLatency", avgLatency);
                        
                        int totalTokens = traceList.stream()
                                .filter(t -> t.getResponse() != null && t.getResponse().getMetadata() != null && t.getResponse().getMetadata().getTokenUsage() != null)
                                .mapToInt(t -> t.getResponse().getMetadata().getTokenUsage().getTotalTokenCount())
                                .sum();
                        stats.put("totalTokens", totalTokens);
                    }
                    
                    return stats;
                });
    }
    
    private Map<String, Object> createEmptyStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalCalls", 0);
        stats.put("successfulCalls", 0);
        stats.put("failedCalls", 0);
        stats.put("successRate", 0.0);
        stats.put("averageLatency", 0.0);
        stats.put("totalTokens", 0);
        return stats;
    }

    /**
     * 获取提供商统计
     */
    public Mono<Map<String, Object>> getProviderStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces.collectList()
                .map(traceList -> {
                    Map<String, Object> providerStats = new HashMap<>();
                    Map<String, Long> callsByProvider = new HashMap<>();
                    Map<String, Long> errorsByProvider = new HashMap<>();
                    Map<String, Double> avgDurationByProvider = new HashMap<>();

                    // 按提供商分组统计
                    traceList.forEach(trace -> {
                        String provider = trace.getProvider();
                        callsByProvider.merge(provider, 1L, Long::sum);
                        
                        if (trace.getError() != null) {
                            errorsByProvider.merge(provider, 1L, Long::sum);
                        }
                    });

                    // 计算平均延迟
                    for (String provider : callsByProvider.keySet()) {
                        double avgDuration = traceList.stream()
                                .filter(trace -> provider.equals(trace.getProvider()))
                                .filter(trace -> trace.getPerformance() != null && trace.getPerformance().getTotalDurationMs() != null)
                                .mapToLong(trace -> trace.getPerformance().getTotalDurationMs())
                                .average()
                                .orElse(0.0);
                        avgDurationByProvider.put(provider, avgDuration);
                    }

                    providerStats.put("callsByProvider", callsByProvider);
                    providerStats.put("errorsByProvider", errorsByProvider);
                    providerStats.put("avgDurationByProvider", avgDurationByProvider);
                    
                    return providerStats;
                });
    }

    /**
     * 获取模型统计 - 使用MongoDB聚合查询（高性能）
     * 过滤掉知识库拆书和章节大纲提取类型
     */
    public Mono<Map<String, Object>> getModelStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        if (mongoTemplate == null) {
            log.warn("ReactiveMongoTemplate未配置，回退到传统查询方式");
            return getModelStatisticsLegacy(startTime, endTime);
        }

        try {
            List<AggregationOperation> operations = new ArrayList<>();
            
            // 构建匹配条件
            List<Criteria> criteriaList = new ArrayList<>();
            
            // 时间范围过滤
            if (startTime != null && endTime != null) {
                Instant start = startTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
                Instant end = endTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
                criteriaList.add(Criteria.where("createdAt").gte(start).lte(end));
            }
            
            // ✅ 过滤掉知识库拆书和章节大纲提取
            criteriaList.add(Criteria.where("businessType")
                    .nin("KNOWLEDGE_EXTRACTION", "OUTLINE_EXTRACTION", 
                         "KNOWLEDGE_EXTRACTION_FANQIE", "KNOWLEDGE_EXTRACTION_TEXT"));
            
            if (!criteriaList.isEmpty()) {
                operations.add(Aggregation.match(new Criteria().andOperator(
                        criteriaList.toArray(new Criteria[0]))));
            }
            
            // 按模型分组统计
            operations.add(Aggregation.group("model")
                    .count().as("calls")
                    .sum(ConditionalOperators.when(Criteria.where("error").ne(null)).then(1).otherwise(0)).as("errors")
                    .sum("response.metadata.tokenUsage.totalTokenCount").as("tokens"));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "llm_traces", Map.class)
                    .collectList()
                    .map(results -> {
                        Map<String, Object> modelStats = new HashMap<>();
                        Map<String, Long> callsByModel = new HashMap<>();
                        Map<String, Long> errorsByModel = new HashMap<>();
                        Map<String, Integer> tokensByModel = new HashMap<>();
                        
                        for (Map<String, Object> result : results) {
                            String model = (String) result.get("_id");
                            if (model != null) {
                                callsByModel.put(model, ((Number) result.getOrDefault("calls", 0L)).longValue());
                                errorsByModel.put(model, ((Number) result.getOrDefault("errors", 0L)).longValue());
                                tokensByModel.put(model, ((Number) result.getOrDefault("tokens", 0)).intValue());
                            }
                        }
                        
                        modelStats.put("callsByModel", callsByModel);
                        modelStats.put("errorsByModel", errorsByModel);
                        modelStats.put("tokensByModel", tokensByModel);
                        
                        log.info("✅ 模型聚合统计完成: 模型数量={}", callsByModel.size());
                        return modelStats;
                    });
        } catch (Exception e) {
            log.error("模型聚合查询失败，回退到传统方式", e);
            return getModelStatisticsLegacy(startTime, endTime);
        }
    }
    
    /**
     * 传统方式的模型统计（回退方案）
     */
    private Mono<Map<String, Object>> getModelStatisticsLegacy(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces
                // ✅ 过滤掉知识库相关类型
                .filter(t -> {
                    String bt = t.getBusinessType();
                    return bt == null || (!bt.equals("KNOWLEDGE_EXTRACTION") && 
                            !bt.equals("OUTLINE_EXTRACTION") &&
                            !bt.equals("KNOWLEDGE_EXTRACTION_FANQIE") &&
                            !bt.equals("KNOWLEDGE_EXTRACTION_TEXT"));
                })
                .collectList()
                .map(traceList -> {
                    Map<String, Object> modelStats = new HashMap<>();
                    Map<String, Long> callsByModel = new HashMap<>();
                    Map<String, Long> errorsByModel = new HashMap<>();
                    Map<String, Integer> tokensByModel = new HashMap<>();

                    // 按模型分组统计
                    traceList.forEach(trace -> {
                        String model = trace.getModel();
                        callsByModel.merge(model, 1L, Long::sum);
                        
                        if (trace.getError() != null) {
                            errorsByModel.merge(model, 1L, Long::sum);
                        }

                        // 统计Token使用量
                        if (trace.getResponse() != null && 
                            trace.getResponse().getMetadata() != null && 
                            trace.getResponse().getMetadata().getTokenUsage() != null) {
                            Integer tokens = trace.getResponse().getMetadata().getTokenUsage().getTotalTokenCount();
                            if (tokens != null) {
                                tokensByModel.merge(model, tokens, Integer::sum);
                            }
                        }
                    });

                    modelStats.put("callsByModel", callsByModel);
                    modelStats.put("errorsByModel", errorsByModel);
                    modelStats.put("tokensByModel", tokensByModel);
                    
                    return modelStats;
                });
    }

    /**
     * 获取用户统计
     */
    public Mono<Map<String, Object>> getUserStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces.collectList()
                .map(traceList -> {
                    Map<String, Object> userStats = new HashMap<>();
                    Map<String, Long> callsByUser = new HashMap<>();
                    Map<String, Integer> tokensByUser = new HashMap<>();
                    Map<String, Long> errorsByUser = new HashMap<>();

                    // 按用户分组统计
                    traceList.forEach(trace -> {
                        String userId = trace.getUserId();
                        if (userId != null) {
                            callsByUser.merge(userId, 1L, Long::sum);
                            
                            if (trace.getError() != null) {
                                errorsByUser.merge(userId, 1L, Long::sum);
                            }

                            // 统计Token使用量
                            if (trace.getResponse() != null && 
                                trace.getResponse().getMetadata() != null && 
                                trace.getResponse().getMetadata().getTokenUsage() != null) {
                                Integer tokens = trace.getResponse().getMetadata().getTokenUsage().getTotalTokenCount();
                                if (tokens != null) {
                                    tokensByUser.merge(userId, tokens, Integer::sum);
                                }
                            }
                        }
                    });

                    userStats.put("callsByUser", callsByUser);
                    userStats.put("tokensByUser", tokensByUser);
                    userStats.put("errorsByUser", errorsByUser);
                    userStats.put("totalUsers", callsByUser.size());
                    
                    return userStats;
                });
    }

    /**
     * 获取指定用户按功能类型聚合的调用与Token统计
     */
    public Mono<Map<String, Object>> getUserFeatureStatistics(String userId, LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged())
                .filter(t -> userId.equals(t.getUserId()));
        } else {
            traces = repository.findByUserIdOrderByCreatedAtDesc(userId, Pageable.unpaged());
        }

        return traces.collectList().map(list -> {
            Map<String, Long> callsByFeature = new HashMap<>();
            Map<String, Integer> tokensByFeature = new HashMap<>();

            list.forEach(t -> {
                String feature = t.getBusinessType() != null ? t.getBusinessType() : "UNKNOWN";
                callsByFeature.merge(feature, 1L, Long::sum);
                if (t.getResponse() != null && t.getResponse().getMetadata() != null && t.getResponse().getMetadata().getTokenUsage() != null) {
                    Integer tokens = t.getResponse().getMetadata().getTokenUsage().getTotalTokenCount();
                    if (tokens != null) tokensByFeature.merge(feature, tokens, Integer::sum);
                }
            });

            Map<String, Object> res = new HashMap<>();
            res.put("callsByFeature", callsByFeature);
            res.put("tokensByFeature", tokensByFeature);
            return res;
        });
    }

    /**
     * 获取指定用户日维度Token消耗
     */
    public Mono<Map<String, Integer>> getUserDailyTokens(String userId, LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged())
                .filter(t -> userId.equals(t.getUserId()));
        } else {
            traces = repository.findByUserIdOrderByCreatedAtDesc(userId, Pageable.unpaged());
        }

        return traces.collectList().map(list -> {
            Map<String, Integer> daily = new HashMap<>();
            list.forEach(t -> {
                if (t.getResponse() != null && t.getResponse().getMetadata() != null && t.getResponse().getMetadata().getTokenUsage() != null
                    && t.getRequest() != null && t.getRequest().getTimestamp() != null) {
                    Integer tokens = t.getResponse().getMetadata().getTokenUsage().getTotalTokenCount();
                    if (tokens != null) {
                        String day = t.getRequest().getTimestamp().atZone(java.time.ZoneId.systemDefault()).toLocalDate().toString();
                        daily.merge(day, tokens, Integer::sum);
                    }
                }
            });
            return daily;
        });
    }

    /**
     * 获取错误统计
     */
    public Mono<Map<String, Object>> getErrorStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces.collectList()
                .map(traceList -> {
                    Map<String, Object> errorStats = new HashMap<>();
                    Map<String, Long> errorsByType = new HashMap<>();
                    Map<String, Long> errorsByProvider = new HashMap<>();
                    Map<String, Long> errorsByModel = new HashMap<>();
                    List<Map<String, Object>> recentErrors = new ArrayList<>();

                    // 只处理错误记录
                    List<LLMTrace> errorTraces = traceList.stream()
                            .filter(trace -> trace.getError() != null)
                            .toList();

                    errorTraces.forEach(trace -> {
                        String errorType = trace.getError().getType();
                        String provider = trace.getProvider();
                        String model = trace.getModel();

                        if (errorType != null) {
                            errorsByType.merge(errorType, 1L, Long::sum);
                        }
                        if (provider != null) {
                            errorsByProvider.merge(provider, 1L, Long::sum);
                        }
                        if (model != null) {
                            errorsByModel.merge(model, 1L, Long::sum);
                        }

                        // 最近10个错误
                        if (recentErrors.size() < 10) {
                            Map<String, Object> errorInfo = new HashMap<>();
                            errorInfo.put("traceId", trace.getTraceId());
                            errorInfo.put("provider", provider);
                            errorInfo.put("model", model);
                            errorInfo.put("errorType", errorType);
                            errorInfo.put("errorMessage", trace.getError().getMessage());
                            errorInfo.put("timestamp", trace.getError().getTimestamp());
                            recentErrors.add(errorInfo);
                        }
                    });

                    errorStats.put("totalErrors", (long) errorTraces.size());
                    errorStats.put("errorsByType", errorsByType);
                    errorStats.put("errorsByProvider", errorsByProvider);
                    errorStats.put("errorsByModel", errorsByModel);
                    errorStats.put("recentErrors", recentErrors);
                    
                    return errorStats;
                });
    }

    /**
     * 获取性能统计
     */
    public Mono<Map<String, Object>> getPerformanceStatistics(LocalDateTime startTime, LocalDateTime endTime) {
        Flux<LLMTrace> traces;
        if (startTime != null && endTime != null) {
            traces = findTracesByTimeRange(startTime, endTime, Pageable.unpaged());
        } else {
            traces = repository.findAll();
        }

        return traces.collectList()
                .map(traceList -> {
                    Map<String, Object> perfStats = new HashMap<>();
                    
                    // 过滤有效性能数据
                    List<LLMTrace> validTraces = traceList.stream()
                            .filter(trace -> trace.getPerformance() != null && trace.getPerformance().getTotalDurationMs() != null)
                            .toList();

                    if (!validTraces.isEmpty()) {
                        // 总耗时统计
                        double avgTotalDuration = validTraces.stream()
                                .mapToLong(trace -> trace.getPerformance().getTotalDurationMs())
                                .average()
                                .orElse(0.0);
                        long maxTotalDuration = validTraces.stream()
                                .mapToLong(trace -> trace.getPerformance().getTotalDurationMs())
                                .max()
                                .orElse(0L);
                        long minTotalDuration = validTraces.stream()
                                .mapToLong(trace -> trace.getPerformance().getTotalDurationMs())
                                .min()
                                .orElse(0L);

                        perfStats.put("avgTotalDuration", avgTotalDuration);
                        perfStats.put("maxTotalDuration", maxTotalDuration);
                        perfStats.put("minTotalDuration", minTotalDuration);

                        // 请求延迟统计
                        List<LLMTrace> requestLatencyTraces = validTraces.stream()
                                .filter(trace -> trace.getPerformance().getRequestLatencyMs() != null)
                                .toList();
                        
                        if (!requestLatencyTraces.isEmpty()) {
                            double avgRequestLatency = requestLatencyTraces.stream()
                                    .mapToLong(trace -> trace.getPerformance() != null ? trace.getPerformance().getRequestLatencyMs() : 0L)
                                    .average()
                                    .orElse(0.0);
                            perfStats.put("avgRequestLatency", avgRequestLatency);
                        }

                        // 首token延迟统计
                        List<LLMTrace> firstTokenTraces = validTraces.stream()
                                .filter(trace -> trace.getPerformance().getFirstTokenLatencyMs() != null)
                                .toList();
                        
                        if (!firstTokenTraces.isEmpty()) {
                            double avgFirstTokenLatency = firstTokenTraces.stream()
                                    .mapToLong(trace -> trace.getPerformance() != null ? trace.getPerformance().getFirstTokenLatencyMs() : 0L)
                                    .average()
                                    .orElse(0.0);
                            perfStats.put("avgFirstTokenLatency", avgFirstTokenLatency);
                        }

                        // 性能分布
                        long slowCalls = validTraces.stream()
                                .filter(trace -> trace.getPerformance().getTotalDurationMs() > 5000) // >5s
                                .count();
                        perfStats.put("slowCalls", slowCalls);
                        perfStats.put("slowCallsRate", (double) slowCalls / validTraces.size() * 100);
                    }

                    perfStats.put("totalCallsWithPerformanceData", validTraces.size());
                    
                    return perfStats;
                });
    }

    /**
     * 导出追踪记录
     */
    public Mono<List<LLMTrace>> exportTraces(Map<String, Object> filterCriteria) {
        return repository.findAll().collectList();
    }

    /**
     * 清理旧记录
     */
    public Mono<Long> cleanupOldTraces(LocalDateTime beforeTime) {
        Instant before = beforeTime.atZone(java.time.ZoneId.systemDefault()).toInstant();
        return repository.deleteByCreatedAtBefore(before);
    }

    /**
     * 获取系统健康状态
     */
    public Mono<Map<String, Object>> getSystemHealth() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "healthy");
        health.put("components", Map.of(
            "database", Map.of("status", "healthy"),
            "tracing", Map.of("status", "healthy")
        ));
        return Mono.just(health);
    }

    /**
     * 获取数据库状态
     */
    public Mono<Map<String, Object>> getDatabaseStatus() {
        return repository.count()
                .map(count -> {
                    Map<String, Object> status = new HashMap<>();
                    status.put("totalRecords", count);
                    status.put("status", "healthy");
                    return status;
                });
    }

    /**
     * 获取最近N条追踪记录（按创建时间倒序）
     */
    public Flux<LLMTrace> findRecent(int n) {
        return repository.findAllByOrderByCreatedAtDesc(org.springframework.data.domain.PageRequest.of(0, Math.max(1, n)));
    }

    /**
     * 游标分页（createdAt倒序，次键_id倒序）
     */
    public Mono<CursorPageResponse<LLMTrace>> findTracesByCursor(String cursor, int limit,
                                                                 String userId, String provider, String model, String sessionId,
                                                                 Boolean hasError, String businessType, String correlationId, String traceId,
                                                                 LLMTrace.CallType type, String tag,
                                                                 LocalDateTime startTime, LocalDateTime endTime) {
        if (mongoTemplate == null) {
            // 后备：模板不可用则退化为第一页固定大小
            return repository.findAllByOrderByCreatedAtDesc(org.springframework.data.domain.PageRequest.of(0, Math.max(1, limit)))
                    .collectList()
                    .map(list -> CursorPageResponse.<LLMTrace>builder().items(list).nextCursor(null).hasMore(false).build());
        }

        Query query = new Query();
        // 过滤条件
        if (userId != null) query.addCriteria(Criteria.where("userId").is(userId));
        if (provider != null) query.addCriteria(Criteria.where("provider").is(provider));
        if (model != null) query.addCriteria(Criteria.where("model").is(model));
        if (sessionId != null) query.addCriteria(Criteria.where("sessionId").is(sessionId));
        if (businessType != null) query.addCriteria(Criteria.where("businessType").is(businessType));
        if (correlationId != null) query.addCriteria(Criteria.where("correlationId").is(correlationId));
        if (traceId != null) query.addCriteria(Criteria.where("traceId").is(traceId));
        if (type != null) query.addCriteria(Criteria.where("type").is(type));
        if (hasError != null) {
            if (hasError) {
                query.addCriteria(Criteria.where("error").ne(null));
            } else {
                query.addCriteria(Criteria.where("error").is(null));
            }
        }
        if (startTime != null && endTime != null) {
            query.addCriteria(Criteria.where("createdAt").gte(startTime.atZone(java.time.ZoneId.systemDefault()).toInstant())
                    .lte(endTime.atZone(java.time.ZoneId.systemDefault()).toInstant()));
        }
        // 简单标签过滤（providerSpecific.labels|tags包含）
        if (tag != null) {
            query.addCriteria(new Criteria().orOperator(
                    Criteria.where("request.parameters.providerSpecific.labels").regex(".*" + java.util.regex.Pattern.quote(tag) + ".*"),
                    Criteria.where("request.parameters.providerSpecific.tags").regex(".*" + java.util.regex.Pattern.quote(tag) + ".*")
            ));
        }

        // 游标解析：cursor = createdAtMillis:objectIdHex
        if (cursor != null && !cursor.isBlank()) {
            try {
                String[] parts = cursor.split(":", 2);
                long ts = Long.parseLong(parts[0]);
                String oid = parts.length > 1 ? parts[1] : null;
                Criteria c = new Criteria().orOperator(
                        Criteria.where("createdAt").lt(java.time.Instant.ofEpochMilli(ts)),
                        new Criteria().andOperator(
                                Criteria.where("createdAt").is(java.time.Instant.ofEpochMilli(ts)),
                                Criteria.where("_id").lt(new org.bson.types.ObjectId(oid))
                        )
                );
                query.addCriteria(c);
            } catch (Exception ignore) {}
        }

        query.with(Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("_id")));
        query.limit(Math.max(1, Math.min(limit, 500)) + 1); // 多取1条判断hasMore

        return mongoTemplate.find(query, LLMTrace.class)
                .collectList()
                .map(list -> {
                    boolean hasMore = list.size() > limit;
                    List<LLMTrace> slice = hasMore ? list.subList(0, limit) : list;
                    String next = null;
                    if (hasMore && !slice.isEmpty()) {
                        LLMTrace last = slice.get(slice.size() - 1);
                        java.time.Instant cat = last.getCreatedAt();
                        String idHex = last.getId();
                        try {
                            // 如果id不是ObjectId字符串，跳过游标拼接
                            new org.bson.types.ObjectId(idHex);
                            next = cat.toEpochMilli() + ":" + idHex;
                        } catch (Exception e) {
                            next = String.valueOf(cat.toEpochMilli());
                        }
                    }
                    return CursorPageResponse.<LLMTrace>builder()
                            .items(slice)
                            .nextCursor(next)
                            .hasMore(hasMore)
                            .build();
                });
    }
} 