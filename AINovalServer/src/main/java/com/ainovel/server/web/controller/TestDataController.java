package com.ainovel.server.web.controller;

import com.ainovel.server.utils.TestDataGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * 测试数据管理控制器
 * 仅在性能测试环境启用
 */
@Slf4j
@RestController
@RequestMapping("/api/test-data")
@Profile("performance-test")  // ✅ 仅在性能测试环境可用
@RequiredArgsConstructor
public class TestDataController {
    
    private final TestDataGenerator testDataGenerator;
    
    /**
     * 生成测试数据
     * 
     * GET /api/test-data/generate?novelCount=100&scenesPerNovel=50
     */
    @PostMapping("/generate")
    public Mono<Map<String, Object>> generateData(
            @RequestParam(defaultValue = "100") int novelCount,
            @RequestParam(defaultValue = "50") int scenesPerNovel) {
        
        log.info("收到生成测试数据请求: novelCount={}, scenesPerNovel={}", novelCount, scenesPerNovel);
        
        // 参数验证
        if (novelCount < 1 || novelCount > 1000) {
            return Mono.just(Map.of(
                "success", false,
                "message", "novelCount必须在1-1000之间"
            ));
        }
        
        if (scenesPerNovel < 1 || scenesPerNovel > 500) {
            return Mono.just(Map.of(
                "success", false,
                "message", "scenesPerNovel必须在1-500之间"
            ));
        }
        
        return testDataGenerator.generateTestData(novelCount, scenesPerNovel)
            .map(stats -> Map.<String, Object>of(
                "success", true,
                "message", "测试数据生成成功",
                "novelCount", stats.novelCount,
                "sceneCount", stats.sceneCount,
                "totalScenes", stats.sceneCount,
                "durationMs", stats.durationMs
            ));
    }
    
    /**
     * 清空所有测试数据
     * 
     * DELETE /api/test-data/clean
     */
    @DeleteMapping("/clean")
    public Mono<Map<String, Object>> cleanData() {
        log.info("收到清空测试数据请求");
        
        return testDataGenerator.cleanTestData()
            .thenReturn(Map.<String, Object>of(
                "success", true,
                "message", "测试数据清空成功"
            ));
    }
    
    /**
     * 清空指定前缀的测试数据
     * 
     * DELETE /api/test-data/clean-prefix?prefix=test-novel
     */
    @DeleteMapping("/clean-prefix")
    public Mono<Map<String, Object>> cleanDataByPrefix(
            @RequestParam(defaultValue = "test-novel") String prefix) {
        
        log.info("收到清空前缀测试数据请求: prefix={}", prefix);
        
        return testDataGenerator.cleanTestDataByPrefix(prefix)
            .map(count -> Map.<String, Object>of(
                "success", true,
                "message", "清空完成",
                "deletedCount", count
            ));
    }
    
    /**
     * 获取当前数据统计
     * 
     * GET /api/test-data/stats
     */
    @GetMapping("/stats")
    public Mono<Map<String, Object>> getStats() {
        return testDataGenerator.getDataStats()
            .map(stats -> Map.<String, Object>of(
                "success", true,
                "novelCount", stats.novelCount,
                "sceneCount", stats.sceneCount
            ));
    }
}


