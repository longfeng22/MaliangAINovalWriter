import 'dart:async';
import 'package:ainoval/models/story_prediction_models.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/event_bus.dart';

/// 剧情推演服务
class StoryPredictionService {
  static const String _tag = 'StoryPredictionService';
  final ApiClient _apiClient;

  StoryPredictionService(this._apiClient);

  /// 创建剧情推演任务
  Future<StoryPredictionResponse> createStoryPredictionTask(
    String novelId,
    StoryPredictionRequest request,
  ) async {
    try {
      AppLogger.i(_tag, '创建剧情推演任务: novelId=$novelId, generationCount=${request.generationCount}');
      
      final response = await _apiClient.post(
        '/novels/$novelId/next-outlines/v2/story-prediction',
        data: request.toJson(),
      );

      AppLogger.d(_tag, '剧情推演任务创建成功: $response');
      return StoryPredictionResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '创建剧情推演任务失败', e);
      AppLogger.e(_tag, '错误堆栈', stackTrace);
      rethrow;
    }
  }

  /// 查询任务状态
  Future<TaskStatusResponse> getTaskStatus(
    String novelId,
    String taskId,
  ) async {
    try {
      AppLogger.d(_tag, '查询任务状态: novelId=$novelId, taskId=$taskId');
      
      final response = await _apiClient.get(
        '/novels/$novelId/next-outlines/v2/story-prediction/$taskId',
      );

      return TaskStatusResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '查询任务状态失败', e);
      AppLogger.e(_tag, '错误堆栈', stackTrace);
      rethrow;
    }
  }

  /// 取消任务
  Future<void> cancelTask(
    String novelId,
    String taskId,
  ) async {
    try {
      AppLogger.i(_tag, '取消任务: novelId=$novelId, taskId=$taskId');
      
      await _apiClient.post(
        '/novels/$novelId/next-outlines/v2/story-prediction/$taskId/cancel',
      );
      
      AppLogger.d(_tag, '任务取消成功');
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '取消任务失败', e);
      AppLogger.e(_tag, '错误堆栈', stackTrace);
      rethrow;
    }
  }

  /// 迭代优化剧情推演
  /// 
  /// 功能说明：
  /// 用户在生成多个推演结果后，可以选择一个最满意的结果，
  /// 提出修改意见，基于选定的结果继续推演，支持切换模型。
  Future<StoryPredictionResponse> refineStoryPrediction(
    String novelId,
    RefineStoryPredictionRequest request,
  ) async {
    try {
      AppLogger.i(_tag, '🔄 迭代优化剧情推演: novelId=$novelId, '
          'originalTaskId=${request.originalTaskId}, '
          'basePredictionId=${request.basePredictionId}, '
          'refinementLength=${request.refinementInstructions.length}');
      
      final response = await _apiClient.post(
        '/novels/$novelId/next-outlines/v2/story-prediction/refine',
        data: request.toJson(),
      );

      AppLogger.d(_tag, '✅ 迭代优化任务创建成功: $response');
      return StoryPredictionResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '❌ 创建迭代优化任务失败', e);
      AppLogger.e(_tag, '错误堆栈', stackTrace);
      rethrow;
    }
  }

  /// 监听任务进度的SSE流（通过全局EventBus）
  Stream<StoryPredictionEvent> subscribeToTaskProgress(
    String novelId,
    String taskId,
  ) async* {
    try {
      AppLogger.i(_tag, '🎯 开始监听任务进度: novelId=$novelId, taskId=$taskId');
      
      // 监听全局任务事件
      await for (final event in _listenToGlobalTaskEvents(taskId)) {
        yield event;
      }
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '监听任务进度失败', e);
      AppLogger.e(_tag, '错误堆栈', stackTrace);
      rethrow;
    }
  }



  /// 解析进度数据中的推演结果
  List<PredictionResult> parsePredictionResults(Object? progressData) {
    if (progressData == null) return [];
    
    try {
      final data = progressData as Map<String, dynamic>;
      final predictionProgress = data['predictionProgress'] as List?;
      
      if (predictionProgress == null) return [];
      
      return predictionProgress.map((item) {
        final progressItem = item as Map<String, dynamic>;
        return PredictionResult(
          id: progressItem['predictionId'] ?? '',
          modelName: progressItem['modelName'] ?? '',
          summary: progressItem['summary'] ?? '',
          sceneContent: progressItem['sceneContent'],
          status: _parseStatus(progressItem['status']),
          sceneStatus: _parseStatus(progressItem['sceneStatus']),
          createdAt: DateTime.now(), // 临时使用当前时间
          error: progressItem['error'],
        );
      }).toList();
    } catch (e) {
      AppLogger.w(_tag, '解析推演结果失败: $e');
      return [];
    }
  }

  /// 解析状态字符串为枚举
  PredictionStatus _parseStatus(String? status) {
    if (status == null) return PredictionStatus.pending;
    final s = status.toUpperCase();
    switch (s) {
      case 'PENDING':
        return PredictionStatus.pending;
      case 'GENERATING':
      case 'RUNNING':
      case 'STARTING':
      case 'SUMMARY_COMPLETED':
        return PredictionStatus.generating;
      case 'COMPLETED':
        return PredictionStatus.completed;
      case 'FAILED':
        return PredictionStatus.failed;
      case 'SKIPPED':
        return PredictionStatus.skipped;
      default:
        return PredictionStatus.pending;
    }
  }

  /// 监听全局任务事件
  Stream<StoryPredictionEvent> _listenToGlobalTaskEvents(String taskId) async* {
    AppLogger.i(_tag, '🎧 开始监听全局任务事件: taskId=$taskId');
    
    await for (final appEvent in EventBus.instance.eventStream) {
      if (appEvent is TaskEventReceived) {
        final eventData = appEvent.event;
        final eventTaskId = eventData['taskId'] as String?;
        
        AppLogger.d(_tag, '🎯 收到全局任务事件: taskId=$eventTaskId, type=${eventData['type']}');
        
        // 只处理当前任务的事件
        if (eventTaskId == taskId) {
          try {
            final String type = (eventData['type'] as String? ?? 'unknown');
            // 统一终态的 status 字段，避免后端未带 status 导致前端判定失败
            String status = (eventData['status'] as String? ?? '');
            if (status.isEmpty) {
              switch (type) {
                case 'TASK_COMPLETED':
                  status = 'COMPLETED'; break;
                case 'TASK_FAILED':
                  status = 'FAILED'; break;
                case 'TASK_CANCELLED':
                  status = 'CANCELLED'; break;
                case 'TASK_DEAD_LETTER':
                  status = 'DEAD_LETTER'; break;
                case 'TASK_COMPLETED_WITH_ERRORS':
                  status = 'COMPLETED_WITH_ERRORS'; break;
                default:
                  status = 'UNKNOWN';
              }
            }

            final event = StoryPredictionEvent(
              type: type,
              taskId: taskId,
              status: status,
              progress: eventData['progress'],
              result: eventData['result'],
              error: eventData['error'] as String?,
            );
            
            AppLogger.i(_tag, '✅ 转发任务事件: taskId=$taskId, type=${event.type}, status=${event.status}');
            yield event;
            
            // 如果任务进入终态（按事件类型判断），停止监听
            final typeUpper = (event.type).toUpperCase();
            const terminalTypes = {
              'TASK_COMPLETED', 'TASK_FAILED', 'TASK_CANCELLED', 'TASK_DEAD_LETTER', 'TASK_COMPLETED_WITH_ERRORS'
            };
            if (terminalTypes.contains(typeUpper)) {
              AppLogger.i(_tag, '🏁 任务终态，停止监听: taskId=$taskId, type=${event.type}');
              break;
            }
          } catch (e) {
            AppLogger.e(_tag, '解析任务事件失败: $e');
            // 发送错误事件
            yield StoryPredictionEvent(
              type: 'task_error',
              taskId: taskId,
              status: 'FAILED',
              error: 'Failed to parse task event: $e',
            );
          }
        }
      }
    }
  }
}
