import 'dart:async';
// ignore_for_file: unnecessary_import

// AppConfig 不再直接使用，保留由 SseClient 统一处理
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/task_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/services/api_service/base/sse_client.dart';

class TaskRepositoryImpl implements TaskRepository {
  final ApiClient apiClient;
  TaskRepositoryImpl({required this.apiClient});

  @override
  Stream<Map<String, dynamic>> streamUserTaskEvents({String? userId}) {
        // Web-only：统一使用 SseClient(EventSource) 实现
    final query = <String, String>{};
    if (userId != null) query['userId'] = userId;
    AppLogger.i('TaskRepository', 'SSE(Web) 连接启动: /api/tasks/events${query.isNotEmpty ? '?userId=${query['userId']}' : ''}');
    return SseClient().streamEvents<Map<String, dynamic>>(
      path: '/api/tasks/events',
      parser: (json) => Map<String, dynamic>.from(json),
      queryParams: query.isEmpty ? null : query,
    );
  }

  @override
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final result = await apiClient.get('/api/tasks/$taskId/status');
    if (result is Map<String, dynamic>) {
      return result;
    }
    return {'taskId': taskId, 'status': 'UNKNOWN'};
  }
  
  @override
  Future<List<Map<String, dynamic>>> getUserHistoryTasks({
    String? status,
    int page = 0,
    int size = 5,
  }) async {
    try {
      AppLogger.d('TaskRepository', '🔍 获取用户历史任务: status=$status, page=$page, size=$size');
      
      final Map<String, dynamic> queryParams = {
        'page': page.toString(),
        'size': size.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      
      final result = await apiClient.getWithParams('/api/tasks/list', queryParameters: queryParams);
      
      if (result is List) {
        final List<Map<String, dynamic>> tasks = [];
        for (final item in result) {
          if (item is Map<String, dynamic>) {
            tasks.add(item);
          }
        }
        AppLogger.d('TaskRepository', '✅ 获取用户历史任务成功: ${tasks.length}条');
        return tasks;
      } else {
        AppLogger.w('TaskRepository', '❌ 历史任务响应格式错误: 期望List但收到${result.runtimeType}');
        return [];
      }
    } catch (e) {
      AppLogger.e('TaskRepository', '❌ 获取用户历史任务失败', e);
      return [];
    }
  }
  
  @override
  Future<TaskListResult> getUserHistoryTasksPaged({
    String? status,
    int page = 0,
    int size = 5,
  }) async {
    try {
      AppLogger.d('TaskRepository', '🔍 获取用户历史任务分页: status=$status, page=$page, size=$size');
      
      final Map<String, dynamic> queryParams = {
        'page': page.toString(),
        'size': size.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      
      final result = await apiClient.getWithParams('/api/tasks/list', queryParameters: queryParams);
      
      if (result is List) {
        final List<Map<String, dynamic>> tasks = [];
        for (final item in result) {
          if (item is Map<String, dynamic>) {
            tasks.add(item);
          }
        }
        
        // 仅按父任务计算 hasMore：后端按父任务分页，但返回扁平（父+子）
        // 这里通过 parentTaskId 为空的条目数 来判断是否满额
        final int parentCount = tasks.where((t) => (t['parentTaskId'] == null || (t['parentTaskId'] as String?)?.isEmpty == true)).length;
        final bool hasMore = parentCount == size;
        
        AppLogger.d('TaskRepository', '✅ 获取用户历史任务分页成功: ${tasks.length}条, hasMore=$hasMore');
        return TaskListResult(
          tasks: tasks,
          hasMore: hasMore,
          currentPage: page,
        );
      } else {
        AppLogger.w('TaskRepository', '❌ 历史任务分页响应格式错误: 期望List但收到${result.runtimeType}');
        return TaskListResult(tasks: [], hasMore: false, currentPage: page);
      }
    } catch (e) {
      AppLogger.e('TaskRepository', '❌ 获取用户历史任务分页失败', e);
      return TaskListResult(tasks: [], hasMore: false, currentPage: page);
    }
  }
}


