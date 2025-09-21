import 'dart:async';

class TaskListResult {
  final List<Map<String, dynamic>> tasks;
  final bool hasMore;
  final int currentPage;
  final int totalCount;
  
  TaskListResult({
    required this.tasks,
    required this.hasMore,
    required this.currentPage,
    this.totalCount = 0,
  });
}

abstract class TaskRepository {
  /// 订阅当前用户的任务事件（SSE）。当后端不可用时可退化为轮询实现。
  Stream<Map<String, dynamic>> streamUserTaskEvents({String? userId});

  /// 查询单个任务状态
  Future<Map<String, dynamic>> getTaskStatus(String taskId);
  
  /// 获取用户历史任务列表
  Future<List<Map<String, dynamic>>> getUserHistoryTasks({
    String? status,
    int page = 0,
    int size = 20,
  });
  
  /// 获取用户历史任务列表（支持无限滚动分页）
  Future<TaskListResult> getUserHistoryTasksPaged({
    String? status,
    int page = 0,
    int size = 20,
  });
}


