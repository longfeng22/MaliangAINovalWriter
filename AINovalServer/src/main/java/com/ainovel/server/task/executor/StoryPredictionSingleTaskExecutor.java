package com.ainovel.server.task.executor;

import com.ainovel.server.task.BackgroundTaskExecutable;
import com.ainovel.server.task.TaskContext;
import com.ainovel.server.task.dto.storyprediction.StoryPredictionResult;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * STORY_PREDICTION_SINGLE 占位执行器
 *
 * 设计意图：
 * - 子任务用于进度展示与状态承载，真实生成逻辑由父任务在提交子任务后直接执行
 * - 此执行器快速确认并返回一个初始结果，避免“找不到执行器”的错误
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StoryPredictionSingleTaskExecutor implements BackgroundTaskExecutable<Map<String, Object>, StoryPredictionResult.PredictionItem> {

    @Override
    public String getTaskType() {
        return "STORY_PREDICTION_SINGLE";
    }

    @Override
    public Mono<StoryPredictionResult.PredictionItem> execute(TaskContext<Map<String, Object>> context) {
        Map<String, Object> params = context.getParameters();

        String predictionId = getString(params, "predictionId");
        if (predictionId == null || predictionId.isBlank()) {
            predictionId = UUID.randomUUID().toString();
        }
        String modelId = getString(params, "modelConfigId");
        String modelName = getString(params, "modelName");

        log.info("[SINGLE] 子任务占位执行: taskId={}, predictionId={}, modelId={}", context.getTaskId(), predictionId, modelId);

        StoryPredictionResult.PredictionItem item = StoryPredictionResult.PredictionItem.builder()
                .id(predictionId)
                .modelId(modelId)
                .modelName(modelName)
                .status("PENDING")
                .sceneStatus("PENDING")
                .createdAt(LocalDateTime.now())
                .build();

        return Mono.just(item);
    }

    private String getString(Map<String, Object> map, String key) {
        if (map == null) return null;
        Object v = map.get(key);
        return v != null ? String.valueOf(v) : null;
    }
}


