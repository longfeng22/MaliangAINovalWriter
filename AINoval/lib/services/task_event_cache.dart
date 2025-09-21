import 'dart:async';

/// 前端全局任务事件缓存与聚合器
/// - 缓存最近事件与任务最新状态，支持晚到的界面初始化时回放当前聚合状态
class TaskEventCache {
  TaskEventCache._internal();
  static final TaskEventCache instance = TaskEventCache._internal();

  final List<Map<String, dynamic>> _events = <Map<String, dynamic>>[]; // 最近事件（可限制大小）
  final Map<String, Map<String, dynamic>> _tasks = <String, Map<String, dynamic>>{}; // taskId -> latest
  final Map<String, List<Map<String, dynamic>>> _childrenByParent = <String, List<Map<String, dynamic>>>{};

  final StreamController<void> _updates = StreamController<void>.broadcast();
  Stream<void> get updates => _updates.stream;

  /// 供 UI 初始化时获取当前聚合快照
  TaskEventSnapshot getSnapshot() {
    return TaskEventSnapshot(
      events: List<Map<String, dynamic>>.from(_events),
      tasks: Map<String, Map<String, dynamic>>.from(_tasks),
      childrenByParent: _childrenByParent.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v))),
    );
  }

  /// 批量初始化历史任务数据
  void initializeHistoryTasks(List<Map<String, dynamic>> historyTasks) {
    for (final task in historyTasks) {
      final String taskId = (task['taskId'] ?? '').toString();
      if (taskId.isEmpty) continue;
      
      final String? parentId = (task['parentTaskId'])?.toString();
      
      // 更新任务聚合
      _tasks[taskId] = Map<String, dynamic>.from(task);
      
      // 维护父子映射
      if (parentId != null && parentId.isNotEmpty) {
        final list = _childrenByParent.putIfAbsent(parentId, () => <Map<String, dynamic>>[]);
        final idx = list.indexWhere((m) => (m['taskId'] ?? '') == taskId);
        if (idx >= 0) {
          list[idx] = Map<String, dynamic>.from(task);
        } else {
          list.add(Map<String, dynamic>.from(task));
        }
        list.sort((a, b) => ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));
      }
    }
    
    // 广播有更新
    _updates.add(null);
  }

  /// 处理一条事件，更新聚合缓存并广播更新信号
  void onEvent(Map<String, dynamic> ev) {
    final String type = (ev['type'] ?? '').toString();
    if (type == 'HEARTBEAT') return;
    final String taskId = (ev['taskId'] ?? '').toString();
    if (taskId.isEmpty) return;

    final String? parentId = (ev['parentTaskId'] ?? ev['parentId'])?.toString();
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    // 记录事件（限制最大 500 条）
    _events.insert(0, ev);
    if (_events.length > 500) {
      _events.removeRange(500, _events.length);
    }

    // 更新任务聚合
    final merged = Map<String, dynamic>.from(_tasks[taskId] ?? {});
    merged.addAll(ev);
    merged['ts'] = ev['ts'] ?? merged['ts'] ?? nowTs;
    _tasks[taskId] = merged;

    // 维护父子映射
    if (parentId != null && parentId.isNotEmpty) {
      final list = _childrenByParent.putIfAbsent(parentId, () => <Map<String, dynamic>>[]);
      final idx = list.indexWhere((m) => (m['taskId'] ?? '') == taskId);
      if (idx >= 0) {
        list[idx] = merged;
      } else {
        list.add(merged);
      }
      list.sort((a, b) => ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));
    }

    // 广播有更新
    _updates.add(null);
  }
}

class TaskEventSnapshot {
  final List<Map<String, dynamic>> events;
  final Map<String, Map<String, dynamic>> tasks;
  final Map<String, List<Map<String, dynamic>>> childrenByParent;

  TaskEventSnapshot({
    required this.events,
    required this.tasks,
    required this.childrenByParent,
  });
}


