package com.ainovel.server.service.impl;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.ainovel.server.controller.AdminDashboardController.*;
import com.ainovel.server.repository.UserRepository;
import com.ainovel.server.repository.NovelRepository;
import com.ainovel.server.repository.AIChatMessageRepository;
import com.ainovel.server.repository.UserLoginLogRepository;
import com.ainovel.server.service.AdminDashboardService;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.domain.model.Novel;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.aggregation.*;
import org.springframework.data.mongodb.core.query.Criteria;

import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;

import java.time.LocalDateTime;
import java.time.LocalDate;
import java.util.List;
import java.util.ArrayList;
import java.util.stream.Collectors;
import java.util.Map;

/**
 * 管理员仪表板服务实现
 */
@Service
public class AdminDashboardServiceImpl implements AdminDashboardService {
    
    private static final Logger logger = LoggerFactory.getLogger(AdminDashboardServiceImpl.class);
    
    private final UserRepository userRepository;
    private final NovelRepository novelRepository;
    private final AIChatMessageRepository aiChatMessageRepository;
    private final UserLoginLogRepository loginLogRepository;
    
    @Autowired(required = false)
    private ReactiveMongoTemplate mongoTemplate;
    
    @Autowired
    public AdminDashboardServiceImpl(UserRepository userRepository, 
                                   NovelRepository novelRepository,
                                   AIChatMessageRepository aiChatMessageRepository,
                                   UserLoginLogRepository loginLogRepository) {
        this.userRepository = userRepository;
        this.novelRepository = novelRepository;
        this.aiChatMessageRepository = aiChatMessageRepository;
        this.loginLogRepository = loginLogRepository;
    }
    
    @Override
    public Mono<DashboardStats> getDashboardStats() {
        long startTime = System.currentTimeMillis();
        logger.info("⏰ [性能监控] 开始获取管理员仪表板统计数据");
        
        // 并行获取各种统计数据，并添加性能监控
        Mono<Long> totalUsersMono = userRepository.count()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] totalUsers 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Long> activeUsersMono = getActiveUsersCount()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] activeUsers 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Long> totalNovelsMono = novelRepository.count()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] totalNovels 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Long> aiRequestsTodayMono = getAiRequestsToday()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] aiRequestsToday 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Double> creditsConsumedMono = getTotalCreditsConsumed()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] creditsConsumed 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<ChartData>> userGrowthDataMono = getUserGrowthData()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] userGrowthData 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<ChartData>> requestsDataMono = getRequestsData()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] requestsData 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<ActivityItem>> recentActivitiesMono = getRecentActivities()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] recentActivities 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<ChartData>> dailyLoginDataMono = getDailyLoginData()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] dailyLoginData 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<ChartData>> dailyRegistrationDataMono = getDailyRegistrationData()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] dailyRegistrationData 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<List<UserNovelStats>> userNovelStatsMono = getUserNovelStats()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] userNovelStats 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Long> newUsersTodayMono = getNewUsersToday()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] newUsersToday 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        Mono<Long> loginsTodayMono = getLoginsToday()
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] loginsToday 查询完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        
        // Mono.zip最多支持8个参数，需要分两批
        Mono<?> firstBatch = Mono.zip(totalUsersMono, activeUsersMono, totalNovelsMono, 
                                      aiRequestsTodayMono, creditsConsumedMono, userGrowthDataMono,
                                      requestsDataMono, recentActivitiesMono)
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] firstBatch 完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        
        Mono<?> secondBatch = Mono.zip(dailyLoginDataMono, dailyRegistrationDataMono, 
                                       userNovelStatsMono, newUsersTodayMono, loginsTodayMono)
                .doOnSuccess(v -> logger.info("⏱️ [性能监控] secondBatch 完成，耗时: {}ms", System.currentTimeMillis() - startTime));
        
        return Mono.zip(firstBatch, secondBatch)
                .map(tuple -> {
                    @SuppressWarnings("unchecked")
                    var first = (reactor.util.function.Tuple8<Long, Long, Long, Long, Double, 
                                 List<ChartData>, List<ChartData>, List<ActivityItem>>) tuple.getT1();
                    @SuppressWarnings("unchecked")
                    var second = (reactor.util.function.Tuple5<List<ChartData>, List<ChartData>, 
                                  List<UserNovelStats>, Long, Long>) tuple.getT2();
                    
                    DashboardStats stats = new DashboardStats(
                        first.getT1().intValue(),  // totalUsers
                        first.getT2().intValue(),  // activeUsers
                        first.getT3().intValue(),  // totalNovels
                        first.getT4().intValue(),  // aiRequestsToday
                        first.getT5(),             // creditsConsumed
                        first.getT6(),             // userGrowthData
                        first.getT7(),             // requestsData
                        first.getT8(),             // recentActivities
                        second.getT1(),            // dailyLoginData
                        second.getT2(),            // dailyRegistrationData
                        second.getT3(),            // userNovelStats
                        second.getT4().intValue(), // newUsersToday
                        second.getT5().intValue()  // loginsToday
                    );
                    
                    long totalTime = System.currentTimeMillis() - startTime;
                    logger.info("✅ [性能监控] 成功获取管理员仪表板统计数据，总耗时: {}ms", totalTime);
                    logger.debug("仪表板数据: totalUsers={}, activeUsers={}, totalNovels={}, newUsersToday={}, loginsToday={}",
                            stats.getTotalUsers(), stats.getActiveUsers(), stats.getTotalNovels(), 
                            stats.getNewUsersToday(), stats.getLoginsToday());
                    
                    return stats;
                })
                .doOnError(e -> {
                    long totalTime = System.currentTimeMillis() - startTime;
                    logger.error("❌ [性能监控] 获取管理员仪表板统计数据失败，耗时: {}ms", totalTime, e);
                });
    }
    
    /**
     * 创建安全的ActivityItem，确保所有字段都非空
     */
    private ActivityItem createSafeActivityItem(String id, String userId, String userName, 
                                              String action, String description, 
                                              LocalDateTime timestamp, String metadata) {
        return new ActivityItem(
            id != null ? id : "unknown",
            userId != null ? userId : "unknown", 
            userName != null ? userName : "未知用户",
            action != null ? action : "未知操作",
            description != null ? description : "无描述",
            timestamp != null ? timestamp : LocalDateTime.now(),
            metadata != null ? metadata : "{}"
        );
    }
    
    private Mono<Long> getActiveUsersCount() {
        long startTime = System.currentTimeMillis();
        // 定义活跃用户为最近30天内登录过的独立用户数
        LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);
        LocalDateTime now = LocalDateTime.now();
        
        logger.debug("🔍 [性能监控] getActiveUsersCount 开始查询: 查询范围 {} 到 {}", thirtyDaysAgo, now);
        
        return loginLogRepository.findByLoginTimeBetween(thirtyDaysAgo, now)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .map(log -> log.getUserId())
                .distinct()
                .count()
                .doOnSuccess(count -> {
                    long elapsedTime = System.currentTimeMillis() - startTime;
                    logger.debug("✅ [性能监控] getActiveUsersCount 查询完成，耗时: {}ms, 活跃用户数: {}", 
                            elapsedTime, count);
                })
                .doOnError(e -> {
                    long elapsedTime = System.currentTimeMillis() - startTime;
                    logger.error("❌ [性能监控] getActiveUsersCount 查询失败，耗时: {}ms", elapsedTime, e);
                })
                .onErrorReturn(0L);
    }
    
    private Mono<Long> getAiRequestsToday() {
        LocalDate today = LocalDate.now();
        LocalDateTime startOfDay = today.atStartOfDay();
        LocalDateTime endOfDay = today.atTime(23, 59, 59);
        
        return aiChatMessageRepository.countByCreatedAtBetween(startOfDay, endOfDay)
            .onErrorReturn(0L); // 如果查询失败，返回0
    }
    
    private Mono<Double> getTotalCreditsConsumed() {
        return userRepository.findByTotalCreditsUsedGreaterThan(0L)
                .map(user -> user.getTotalCreditsUsed() != null ? user.getTotalCreditsUsed().doubleValue() : 0.0)
                .reduce(0.0, Double::sum)
                .onErrorReturn(0.0); // 如果查询失败，返回0.0
    }
    
    /**
     * 获取用户增长数据（最近7天）- 使用MongoDB聚合查询优化
     */
    private Mono<List<ChartData>> getUserGrowthData() {
        if (mongoTemplate == null) {
            return getUserGrowthDataLegacy();
        }
        
        try {
            LocalDateTime now = LocalDateTime.now();
            LocalDateTime sevenDaysAgo = now.minusDays(6).toLocalDate().atStartOfDay();
            
            List<AggregationOperation> operations = new ArrayList<>();
            operations.add(Aggregation.match(Criteria.where("createdAt").gte(sevenDaysAgo).lte(now)));
            operations.add(Aggregation.project()
                    .and(DateOperators.dateOf("createdAt").withTimezone(DateOperators.Timezone.valueOf("Asia/Shanghai"))
                            .toString("%Y-%m-%d")).as("date"));
            operations.add(Aggregation.group("date").count().as("count"));
            operations.add(Aggregation.project().and("_id").as("date").and("count").as("count"));
            operations.add(Aggregation.sort(org.springframework.data.domain.Sort.by(
                    org.springframework.data.domain.Sort.Order.asc("date"))));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "users", Map.class)
                    .collectList()
                    .map(results -> {
                        List<ChartData> chartDataList = new ArrayList<>();
                        for (int i = 6; i >= 0; i--) {
                            LocalDateTime date = now.minusDays(i);
                            String dateStr = date.toLocalDate().toString();
                            double count = results.stream()
                                    .filter(r -> dateStr.equals(r.get("date")))
                                    .findFirst()
                                    .map(r -> ((Number) r.getOrDefault("count", 0)).doubleValue())
                                    .orElse(0.0);
                            chartDataList.add(new ChartData(dateStr, count, date));
                        }
                        return chartDataList;
                    })
                    .onErrorResume(e -> getUserGrowthDataLegacy());
        } catch (Exception e) {
            return getUserGrowthDataLegacy();
        }
    }
    
    private Mono<List<ChartData>> getUserGrowthDataLegacy() {
        LocalDateTime now = LocalDateTime.now();
        List<Mono<ChartData>> dailyDataMonos = new ArrayList<>();
        for (int i = 6; i >= 0; i--) {
            final LocalDateTime date = now.minusDays(i);
            final LocalDateTime startOfDay = date.toLocalDate().atStartOfDay();
            final LocalDateTime endOfDay = date.toLocalDate().atTime(23, 59, 59);
            Mono<ChartData> dailyDataMono = userRepository
                    .countByCreatedAtBetween(startOfDay, endOfDay)
                    .map(count -> new ChartData(date.toLocalDate().toString(), count.doubleValue(), date));
            dailyDataMonos.add(dailyDataMono);
        }
        return Flux.fromIterable(dailyDataMonos).flatMap(mono -> mono).collectList().onErrorReturn(new ArrayList<>());
    }
    
    /**
     * 获取AI请求数据（最近24小时）- 使用MongoDB聚合查询优化
     */
    private Mono<List<ChartData>> getRequestsData() {
        if (mongoTemplate == null) {
            return getRequestsDataLegacy();
        }
        
        try {
            LocalDateTime now = LocalDateTime.now();
            LocalDateTime twentyFourHoursAgo = now.minusHours(23).withMinute(0).withSecond(0).withNano(0);
            
            List<AggregationOperation> operations = new ArrayList<>();
            operations.add(Aggregation.match(Criteria.where("createdAt").gte(twentyFourHoursAgo).lte(now)));
            operations.add(Aggregation.project()
                    .and(DateOperators.dateOf("createdAt").withTimezone(DateOperators.Timezone.valueOf("Asia/Shanghai"))
                            .toString("%Y-%m-%d %H:00")).as("hour"));
            operations.add(Aggregation.group("hour").count().as("count"));
            operations.add(Aggregation.project().and("_id").as("hour").and("count").as("count"));
            operations.add(Aggregation.sort(org.springframework.data.domain.Sort.by(
                    org.springframework.data.domain.Sort.Order.asc("hour"))));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "ai_chat_messages", Map.class)
                    .collectList()
                    .map(results -> {
                        List<ChartData> chartDataList = new ArrayList<>();
                        for (int i = 23; i >= 0; i--) {
                            LocalDateTime hour = now.minusHours(i);
                            String hourStr = String.format("%s %02d:00", hour.toLocalDate(), hour.getHour());
                            double count = results.stream()
                                    .filter(r -> hourStr.equals(r.get("hour")))
                                    .findFirst()
                                    .map(r -> ((Number) r.getOrDefault("count", 0)).doubleValue())
                                    .orElse(0.0);
                            chartDataList.add(new ChartData(String.format("%02d:00", hour.getHour()), count, hour));
                        }
                        return chartDataList;
                    })
                    .onErrorResume(e -> getRequestsDataLegacy());
        } catch (Exception e) {
            return getRequestsDataLegacy();
        }
    }
    
    private Mono<List<ChartData>> getRequestsDataLegacy() {
        LocalDateTime now = LocalDateTime.now();
        List<Mono<ChartData>> hourlyDataMonos = new ArrayList<>();
        for (int i = 23; i >= 0; i--) {
            final LocalDateTime hour = now.minusHours(i);
            final LocalDateTime startOfHour = hour.withMinute(0).withSecond(0).withNano(0);
            final LocalDateTime endOfHour = hour.withMinute(59).withSecond(59).withNano(999999999);
            Mono<ChartData> hourlyDataMono = aiChatMessageRepository
                    .countByCreatedAtBetween(startOfHour, endOfHour)
                    .map(count -> new ChartData(String.format("%02d:00", hour.getHour()), count.doubleValue(), hour));
            hourlyDataMonos.add(hourlyDataMono);
        }
        return Flux.fromIterable(hourlyDataMonos).flatMap(mono -> mono).collectList().onErrorReturn(new ArrayList<>());
    }
    
    private Mono<List<ActivityItem>> getRecentActivities() {
        // 获取最近的用户注册活动
        Mono<List<ActivityItem>> recentUsersMono = userRepository
                .findTop10ByOrderByCreatedAtDesc()
                .take(5)
                .map(user -> createSafeActivityItem(
                    "user_" + (user.getId() != null ? user.getId() : "unknown"),
                    user.getId(),
                    user.getDisplayName() != null ? user.getDisplayName() : user.getUsername(),
                    "用户注册",
                    "新用户注册成功",
                    user.getCreatedAt(),
                    String.format("{\"email\":\"%s\"}", 
                        user.getEmail() != null ? user.getEmail() : "unknown@example.com")
                ))
                .collectList();
        
        // 获取最近的小说创建活动
        Mono<List<ActivityItem>> recentNovelsMono = novelRepository
                .findTop10ByOrderByCreatedAtDesc()
                .take(5)
                .map(novel -> {
                    Novel.Author author = novel.getAuthor();
                    return createSafeActivityItem(
                        "novel_" + (novel.getId() != null ? novel.getId() : "unknown"),
                        author != null ? author.getId() : null,
                        author != null ? author.getUsername() : null,
                        "小说创建",
                        String.format("创建了新小说《%s》", 
                            novel.getTitle() != null ? novel.getTitle() : "无标题"),
                        novel.getCreatedAt(),
                        String.format("{\"novelId\":\"%s\",\"title\":\"%s\"}", 
                            novel.getId() != null ? novel.getId() : "unknown",
                            novel.getTitle() != null ? novel.getTitle() : "无标题")
                    );
                })
                .collectList();
        
        // 获取最近的AI聊天活动
        Mono<List<ActivityItem>> recentMessagesMono = aiChatMessageRepository
                .findTop20ByOrderByCreatedAtDesc()
                .take(5)
                .filter(message -> "user".equals(message.getRole())) // 只显示用户消息
                .map(message -> createSafeActivityItem(
                    "message_" + (message.getId() != null ? message.getId() : "unknown"),
                    message.getUserId(),
                    "用户", // 这里可以后续优化关联用户信息
                    "AI对话",
                    "使用AI进行对话交流",
                    message.getCreatedAt(),
                    String.format("{\"model\":\"%s\",\"sessionId\":\"%s\"}", 
                        message.getModelName() != null ? message.getModelName() : "unknown",
                        message.getSessionId() != null ? message.getSessionId() : "unknown")
                ))
                .collectList();
        
        // 合并所有活动并按时间排序
        return Mono.zip(recentUsersMono, recentNovelsMono, recentMessagesMono)
                .map(tuple -> {
                    List<ActivityItem> allActivities = new ArrayList<>();
                    allActivities.addAll(tuple.getT1());
                    allActivities.addAll(tuple.getT2());
                    allActivities.addAll(tuple.getT3());
                    
                    return allActivities.stream()
                            .sorted((a, b) -> b.getTimestamp().compareTo(a.getTimestamp()))
                            .limit(10)
                            .collect(Collectors.toList());
                })
                .onErrorReturn(new ArrayList<>()); // 如果查询失败，返回空列表而不是错误
    }
    
    /**
     * 获取每日登录统计数据（最近30天）- 使用MongoDB聚合查询优化
     * 使用登录日志表进行精准统计，按天去重用户ID
     */
    private Mono<List<ChartData>> getDailyLoginData() {
        if (mongoTemplate == null) {
            logger.warn("ReactiveMongoTemplate未配置，使用传统查询方式");
            return getDailyLoginDataLegacy();
        }
        
        try {
            LocalDateTime now = LocalDateTime.now();
            LocalDateTime thirtyDaysAgo = now.minusDays(29).toLocalDate().atStartOfDay();
            
            List<AggregationOperation> operations = new ArrayList<>();
            
            // 匹配最近30天且成功的登录记录
            operations.add(Aggregation.match(
                    new Criteria().andOperator(
                            Criteria.where("loginTime").gte(thirtyDaysAgo).lte(now),
                            Criteria.where("success").is(true)
                    )));
            
            // 按日期和用户ID分组（去重）
            operations.add(Aggregation.project()
                    .and(DateOperators.dateOf("loginTime").withTimezone(DateOperators.Timezone.valueOf("Asia/Shanghai"))
                            .toString("%Y-%m-%d")).as("date")
                    .and("userId").as("userId"));
            
            // 按日期分组，统计独立用户数
            operations.add(Aggregation.group("date")
                    .addToSet("userId").as("userIds"));
            
            // 计算每天的独立用户数
            operations.add(Aggregation.project()
                    .and("_id").as("date")
                    .and(ArrayOperators.Size.lengthOfArray("userIds")).as("count"));
            
            // 排序
            operations.add(Aggregation.sort(org.springframework.data.domain.Sort.by(
                    org.springframework.data.domain.Sort.Order.asc("date"))));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "user_login_logs", Map.class)
                    .collectList()
                    .map(results -> {
                        List<ChartData> chartDataList = new ArrayList<>();
                        
                        // 创建30天的完整数据（包括0值的日期）
                        for (int i = 29; i >= 0; i--) {
                            LocalDateTime date = now.minusDays(i);
                            String dateStr = date.toLocalDate().toString();
                            
                            // 查找该日期的统计结果
                            double count = results.stream()
                                    .filter(r -> dateStr.equals(r.get("date")))
                                    .findFirst()
                                    .map(r -> ((Number) r.getOrDefault("count", 0)).doubleValue())
                                    .orElse(0.0);
                            
                            chartDataList.add(new ChartData(dateStr, count, date));
                        }
                        
                        logger.debug("✅ 登录数据聚合完成: 获取{}天数据", chartDataList.size());
                        return chartDataList;
                    })
                    .onErrorResume(e -> {
                        logger.error("聚合查询失败，回退到传统方式", e);
                        return getDailyLoginDataLegacy();
                    });
        } catch (Exception e) {
            logger.error("聚合查询异常，回退到传统方式", e);
            return getDailyLoginDataLegacy();
        }
    }
    
    /**
     * 传统方式获取登录数据（回退方案）
     */
    private Mono<List<ChartData>> getDailyLoginDataLegacy() {
        LocalDateTime now = LocalDateTime.now();
        List<Mono<ChartData>> dailyDataMonos = new ArrayList<>();
        
        for (int i = 29; i >= 0; i--) {
            final LocalDateTime date = now.minusDays(i);
            final LocalDateTime startOfDay = date.toLocalDate().atStartOfDay();
            final LocalDateTime endOfDay = date.toLocalDate().atTime(23, 59, 59);
            
            Mono<ChartData> dailyDataMono = loginLogRepository
                    .findByLoginTimeBetween(startOfDay, endOfDay)
                    .filter(log -> log.getSuccess() != null && log.getSuccess())
                    .map(log -> log.getUserId())
                    .distinct()
                    .count()
                    .map(count -> new ChartData(
                        date.toLocalDate().toString(),
                        count.doubleValue(),
                        date
                    ));
            
            dailyDataMonos.add(dailyDataMono);
        }
        
        return Flux.fromIterable(dailyDataMonos)
                .flatMap(mono -> mono)
                .collectList()
                .onErrorReturn(new ArrayList<>());
    }
    
    /**
     * 获取每日注册统计数据（最近30天）- 使用MongoDB聚合查询优化
     */
    private Mono<List<ChartData>> getDailyRegistrationData() {
        if (mongoTemplate == null) {
            return getDailyRegistrationDataLegacy();
        }
        
        try {
            LocalDateTime now = LocalDateTime.now();
            LocalDateTime thirtyDaysAgo = now.minusDays(29).toLocalDate().atStartOfDay();
            
            List<AggregationOperation> operations = new ArrayList<>();
            
            operations.add(Aggregation.match(
                    Criteria.where("createdAt").gte(thirtyDaysAgo).lte(now)));
            
            operations.add(Aggregation.project()
                    .and(DateOperators.dateOf("createdAt").withTimezone(DateOperators.Timezone.valueOf("Asia/Shanghai"))
                            .toString("%Y-%m-%d")).as("date"));
            
            operations.add(Aggregation.group("date").count().as("count"));
            
            operations.add(Aggregation.project()
                    .and("_id").as("date")
                    .and("count").as("count"));
            
            operations.add(Aggregation.sort(org.springframework.data.domain.Sort.by(
                    org.springframework.data.domain.Sort.Order.asc("date"))));
            
            Aggregation aggregation = Aggregation.newAggregation(operations);
            
            return mongoTemplate.aggregate(aggregation, "users", Map.class)
                    .collectList()
                    .map(results -> {
                        List<ChartData> chartDataList = new ArrayList<>();
                        for (int i = 29; i >= 0; i--) {
                            LocalDateTime date = now.minusDays(i);
                            String dateStr = date.toLocalDate().toString();
                            double count = results.stream()
                                    .filter(r -> dateStr.equals(r.get("date")))
                                    .findFirst()
                                    .map(r -> ((Number) r.getOrDefault("count", 0)).doubleValue())
                                    .orElse(0.0);
                            chartDataList.add(new ChartData(dateStr, count, date));
                        }
                        return chartDataList;
                    })
                    .onErrorResume(e -> {
                        logger.error("注册数据聚合查询失败", e);
                        return getDailyRegistrationDataLegacy();
                    });
        } catch (Exception e) {
            return getDailyRegistrationDataLegacy();
        }
    }
    
    private Mono<List<ChartData>> getDailyRegistrationDataLegacy() {
        LocalDateTime now = LocalDateTime.now();
        List<Mono<ChartData>> dailyDataMonos = new ArrayList<>();
        for (int i = 29; i >= 0; i--) {
            final LocalDateTime date = now.minusDays(i);
            final LocalDateTime startOfDay = date.toLocalDate().atStartOfDay();
            final LocalDateTime endOfDay = date.toLocalDate().atTime(23, 59, 59);
            Mono<ChartData> dailyDataMono = userRepository
                    .countByCreatedAtBetween(startOfDay, endOfDay)
                    .map(count -> new ChartData(
                        date.toLocalDate().toString(),
                        count.doubleValue(),
                        date
                    ));
            dailyDataMonos.add(dailyDataMono);
        }
        return Flux.fromIterable(dailyDataMonos)
                .flatMap(mono -> mono)
                .collectList()
                .onErrorReturn(new ArrayList<>());
    }
    
    /**
     * 获取用户创作小说统计（Top 10用户）
     * 优化：限制查询数量，避免全表扫描
     */
    private Mono<List<UserNovelStats>> getUserNovelStats() {
        long startTime = System.currentTimeMillis();
        logger.debug("🔍 [性能监控] getUserNovelStats 开始查询");
        
        return novelRepository.findAll()
                .filter(novel -> novel.getAuthor() != null && novel.getAuthor().getId() != null)
                .take(1000) // 限制最多处理1000条数据，避免全表扫描导致超时
                .groupBy(novel -> novel.getAuthor().getId())
                .flatMap(group -> group.collectList()
                        .map(novels -> {
                            if (novels.isEmpty()) return null;
                            Novel firstNovel = novels.get(0);
                            Novel.Author author = firstNovel.getAuthor();
                            
                            LocalDateTime lastCreated = novels.stream()
                                    .map(Novel::getCreatedAt)
                                    .filter(date -> date != null)
                                    .max(LocalDateTime::compareTo)
                                    .orElse(LocalDateTime.now());
                            
                            return new UserNovelStats(
                                    author.getId(),
                                    author.getUsername() != null ? author.getUsername() : "未知用户",
                                    null, // Novel.Author没有displayName字段
                                    novels.size(),
                                    lastCreated
                            );
                        }))
                .filter(stats -> stats != null)
                .collectList()
                .map(list -> {
                    long elapsedTime = System.currentTimeMillis() - startTime;
                    logger.debug("✅ [性能监控] getUserNovelStats 查询完成，耗时: {}ms, 用户数: {}", 
                            elapsedTime, list.size());
                    return list.stream()
                            .sorted((a, b) -> Integer.compare(b.getNovelCount(), a.getNovelCount()))
                            .limit(10)
                            .collect(Collectors.toList());
                })
                .doOnError(e -> {
                    long elapsedTime = System.currentTimeMillis() - startTime;
                    logger.error("❌ [性能监控] getUserNovelStats 查询失败，耗时: {}ms", elapsedTime, e);
                })
                .onErrorReturn(new ArrayList<>());
    }
    
    /**
     * 获取今日新注册用户数
     */
    private Mono<Long> getNewUsersToday() {
        LocalDate today = LocalDate.now();
        LocalDateTime startOfDay = today.atStartOfDay();
        LocalDateTime endOfDay = today.atTime(23, 59, 59);
        
        return userRepository.countByCreatedAtBetween(startOfDay, endOfDay)
                .onErrorReturn(0L);
    }
    
    /**
     * 获取今日登录用户数（独立用户数，去重）
     * 使用登录日志表进行精准统计
     */
    private Mono<Long> getLoginsToday() {
        LocalDate today = LocalDate.now();
        LocalDateTime startOfDay = today.atStartOfDay();
        LocalDateTime endOfDay = today.atTime(23, 59, 59);
        
        return loginLogRepository.findByLoginTimeBetween(startOfDay, endOfDay)
                .filter(log -> log.getSuccess() != null && log.getSuccess())
                .map(log -> log.getUserId())
                .distinct()
                .count()
                .onErrorReturn(0L);
    }
}