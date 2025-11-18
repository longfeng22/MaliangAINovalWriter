import 'dart:async';

import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/impl/task_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/task_repository.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:ainoval/utils/task_translation.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/loading_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/services/api_service/repositories/impl/editor_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/services/task_event_cache.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';
import 'package:ainoval/blocs/editor/editor_bloc.dart';

/// AI 任务中心：展示任务流与完成后的“预览合并”入口
class AITaskCenterPanel extends StatefulWidget {
  const AITaskCenterPanel({super.key});

  @override
  State<AITaskCenterPanel> createState() => _AITaskCenterPanelState();
}

class _AITaskCenterPanelState extends State<AITaskCenterPanel> {
  late final TaskRepository _repo;
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<TaskEventReceived>? _busSub;
  Timer? _pollTimer;
  int _lastEventTs = 0; // 记录最近一次事件到达时间，用于智能轮询

  final List<Map<String, dynamic>> _events = [];
  final Map<String, Map<String, dynamic>> _tasks = {}; // 按 taskId 聚合最新状态
  final Map<String, List<Map<String, dynamic>>> _childrenByParent = {}; // 父任务 -> 子任务列表
  final List<Map<String, dynamic>> _historyTasks = []; // 历史任务列表
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;
  int _currentHistoryPage = 0;
  final ScrollController _scrollController = ScrollController();

  String _formatTime(dynamic ts) {
    try {
      if (ts == null) return '';
      if (ts is String) {
        final dt = DateTime.tryParse(ts);
        if (dt != null) return dt.toLocal().toString();
      }
      if (ts is int) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return dt.toLocal().toString();
      }
      return ts.toString();
    } catch (_) {
      return '';
    }
  }
  
  /// 获取任务的模型信息
  String _getModelInfo(Map<String, dynamic> task) {
    final String taskType = task['taskType'] ?? '';
    
    // 处理剧情推演子任务
    if (taskType == 'STORY_PREDICTION_SINGLE') {
      // 从任务进度或结果中提取模型信息
      final progress = task['progress'];
      final result = task['result'];
      
      // 尝试从进度中获取模型信息
      if (progress is Map<String, dynamic>) {
        final predictionProgress = progress['predictionProgress'];
        if (predictionProgress is List && predictionProgress.isNotEmpty) {
          final firstPrediction = predictionProgress[0];
          if (firstPrediction is Map<String, dynamic>) {
            final modelName = firstPrediction['modelName'];
            if (modelName != null && modelName.isNotEmpty) {
              return '模型: $modelName';
            }
          }
        }
      }
      
      // 尝试从结果中获取模型信息
      if (result is Map<String, dynamic>) {
        final predictions = result['predictions'];
        if (predictions is List && predictions.isNotEmpty) {
          final firstPrediction = predictions[0];
          if (firstPrediction is Map<String, dynamic>) {
            final modelName = firstPrediction['modelName'];
            if (modelName != null && modelName.isNotEmpty) {
              return '模型: $modelName';
            }
          }
        }
      }
    }
    
    // 处理自动续写子任务
    if (taskType == 'GENERATE_SINGLE_CHAPTER') {
      final result = task['result'];
      if (result is Map<String, dynamic>) {
        final summaryModel = result['summaryModelName'];
        final contentModel = result['contentModelName'];
        
        List<String> modelParts = [];
        if (summaryModel != null && summaryModel.isNotEmpty) {
          modelParts.add('生成摘要 $summaryModel');
        }
        if (contentModel != null && contentModel.isNotEmpty) {
          modelParts.add('生成内容 $contentModel');
        }
        
        if (modelParts.isNotEmpty) {
          return modelParts.join(' ');
        }
      }
    }
    
    return '';
  }

  /// 获取详细模型信息（摘要/内容模型）
  String _getDetailedModelInfo(Map<String, dynamic> task) {
    final String taskType = task['taskType'] ?? '';
    final progress = task['progress'];
    final result = task['result'];

    // 自动续写：Prefer result.summaryModelName/contentModelName
    if (taskType == 'GENERATE_SINGLE_CHAPTER') {
      if (result is Map<String, dynamic>) {
        final s = (result['summaryModelName'] ?? '').toString();
        final c = (result['contentModelName'] ?? '').toString();
        final parts = <String>[];
        if (s.isNotEmpty) parts.add('摘要生成 $s');
        if (c.isNotEmpty) parts.add('内容生成 $c');
        return parts.join('  ·  ');
      }
    }

    // 剧情推演：若结果中包含predictions，取第一个的modelName
    if (taskType == 'STORY_PREDICTION_SINGLE') {
      String? model;
      if (progress is Map<String, dynamic>) {
        final list = progress['predictionProgress'];
        if (list is List && list.isNotEmpty && list.first is Map) {
          model = (list.first['modelName'] ?? '').toString();
        }
      }
      if ((model == null || model.isEmpty) && result is Map<String, dynamic>) {
        final preds = result['predictions'];
        if (preds is List && preds.isNotEmpty && preds.first is Map) {
          model = (preds.first['modelName'] ?? '').toString();
        }
      }
      return model != null && model.isNotEmpty ? '模型 $model' : '';
    }

    return '';
  }

  @override
  void initState() {
    super.initState();
    final api = RepositoryProvider.of<ApiClient>(context);
    _repo = TaskRepositoryImpl(apiClient: api);
    // 先用全局缓存快照填充，避免“进入面板时为空”的错觉
    try {
      final snap = TaskEventCache.instance.getSnapshot();
      _events
        ..clear()
        ..addAll(snap.events);
      _tasks
        ..clear()
        ..addAll(snap.tasks);
      _childrenByParent
        ..clear()
        ..addAll(snap.childrenByParent);
      AppLogger.i('AITaskCenterPanel', '初始化快照: events=${_events.length}, tasks=${_tasks.length}, parents=${_childrenByParent.length}');
    } catch (_) {}
    // 🔧 面板不再直接订阅 SSE，统一通过全局事件总线接收
    // 🔧 重要：不再主动触发 StartTaskEventsListening，避免多组件重复触发导致连接风暴
    // 🔧 SSE连接由 main.dart 统一管理，登录时自动启动，面板只需被动接收事件即可
    // if (AppConfig.authToken != null && AppConfig.authToken!.isNotEmpty) {
    //   try { EventBus.instance.fire(const StartTaskEventsListening()); } catch (_) {}
    // } else {
    //   AppLogger.w('AITaskCenterPanel', '跳过启动全局任务事件监听：未检测到有效token');
    // }
    
    // 初始加载历史任务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistoryTasks();
    });

    // 监听滚动触底，自动加载更多（每次5条父任务）
    _scrollController.addListener(() {
      if (!_hasMoreHistory || _isLoadingHistory) return;
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // 仅在列表可滚动且接近底部时触发，避免初始内容不足时误触发
      if (position.maxScrollExtent <= 0) return;
      if (position.pixels < position.maxScrollExtent - 120) return;
      _loadHistoryTasks();
    });

    // 同步订阅全局事件总线（由 main.dart 全局监听后广播），避免面板未打开时漏事件
    _busSub = EventBus.instance.on<TaskEventReceived>().listen((evt) {
      final ev = evt.event;
      final ty = (ev['type'] ?? '').toString();
      if (ty == 'HEARTBEAT') {
        // 心跳也视为SSE活跃，刷新最后事件时间，避免误触发轮询
        _lastEventTs = DateTime.now().millisecondsSinceEpoch;
        return; // UI 不展示心跳
      }
      AppLogger.i('AITaskCenterPanel', 'BUS事件: type=${ev['type']} id=${ev['taskId']} parent=${ev['parentTaskId'] ?? ev['parentId']} hasResult=${ev.containsKey('result')}');
      
      final String taskId = (ev['taskId'] ?? '').toString();
      if (taskId.isEmpty) return;
      final String? parentId = (ev['parentTaskId'] ?? ev['parentId'])?.toString();
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      _lastEventTs = nowTs;
      
      // 🚀 自动续写任务完成时刷新积分
      if (ty == 'TASK_COMPLETED') {
        final taskType = (ev['taskType'] ?? '').toString();
        if (taskType == 'CONTINUE_WRITING_CONTENT') {
          AppLogger.i('AITaskCenterPanel', '自动续写任务完成，刷新用户积分');
          try {
            context.read<CreditBloc>().add(const RefreshUserCredits());
          } catch (e) {
            AppLogger.w('AITaskCenterPanel', '刷新积分失败', e);
          }
        }
      }
      
      // 写入全局缓存
      try { TaskEventCache.instance.onEvent(ev); } catch (_) {}
      _events.insert(0, ev);
      final merged = Map<String, dynamic>.from(_tasks[taskId] ?? {});
      final prevType = (merged['type'] ?? '').toString();
      merged.addAll(ev);
      // 终态守护：一旦进入终态，后续的非终态事件不再回退状态
      const terminalTypes = {
        'TASK_COMPLETED', 'TASK_FAILED', 'TASK_CANCELLED', 'TASK_DEAD_LETTER', 'TASK_COMPLETED_WITH_ERRORS'
      };
      final bool wasTerminal = terminalTypes.contains(prevType);
      final bool nowTerminal = terminalTypes.contains(ty);
      if (wasTerminal && !nowTerminal) {
        // 保持终态，不回退到进行中；同时不恢复进度
        merged['type'] = prevType;
        merged.remove('progress');
      } else if (nowTerminal) {
        // 进入终态时，清理progress
        merged.remove('progress');
        // 同步一个标准status字段，便于其他分支直接读取
        switch (ty) {
          case 'TASK_COMPLETED':
            merged['status'] = 'COMPLETED';
            break;
          case 'TASK_FAILED':
            merged['status'] = 'FAILED';
            break;
          case 'TASK_CANCELLED':
            merged['status'] = 'CANCELLED';
            break;
          case 'TASK_DEAD_LETTER':
            merged['status'] = 'DEAD_LETTER';
            break;
          case 'TASK_COMPLETED_WITH_ERRORS':
            merged['status'] = 'COMPLETED_WITH_ERRORS';
            break;
        }
      }
      // 只有在原始事件包含时间戳或者是新任务时才更新时间戳，避免轮询导致的排序变化
      if (ev.containsKey('ts') || !_tasks.containsKey(taskId)) {
        merged['ts'] = ev['ts'] ?? merged['ts'] ?? nowTs;
      }
      _tasks[taskId] = merged;
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
      if (mounted) setState(() {});
      AppLogger.i('AITaskCenterPanel', 'BUS更新后: tasks=${_tasks.length} childrenParents=${_childrenByParent.length}');
    });

    // 优化后的轮询：仅在SSE连接异常时作为降级方案
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // 未认证或尚未收到任何事件（_lastEventTs=0）时，不进行降级轮询，避免无意义请求
      if (AppConfig.authToken == null || AppConfig.authToken!.isEmpty || _lastEventTs == 0) {
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      // 只有在30秒内没有任何事件到达时才轮询，说明SSE可能断开
      if (now - _lastEventTs < 30000) {
        return; // SSE正常工作，无需轮询
      }
      
      AppLogger.w('AITaskCenterPanel', 'SSE事件长时间无更新，启动降级轮询');
      
      // 只轮询运行中的任务，已完成/失败的任务不需要轮询
      final runningTasks = _tasks.values.where((t) {
        final ty = (t['type'] ?? '').toString();
        return ty == 'TASK_STARTED' || ty == 'TASK_SUBMITTED' || ty == 'TASK_PROGRESS';
      }).toList();
      
      // 限制轮询任务数量，避免过多请求
      final tasksToCheck = runningTasks.take(5).toList();
      
      for (final t in tasksToCheck) {
        final id = (t['taskId'] ?? '').toString();
        if (id.isEmpty) continue;
        try {
          final status = await _repo.getTaskStatus(id);
          if (status.isNotEmpty) {
            final merged = Map<String, dynamic>.from(_tasks[id] ?? {});
            // 映射后端返回结构为统一字段
            if (status['status'] == 'COMPLETED') {
              merged['type'] = 'TASK_COMPLETED';
              if (status['result'] is Map) merged['result'] = status['result'];
            } else if (status['status'] == 'FAILED') {
              merged['type'] = 'TASK_FAILED';
              if (status['error'] != null) merged['error'] = status['error'];
            }
            // 轮询获取的状态更新不修改时间戳，避免影响排序
            _tasks[id] = merged;
          }
        } catch (e) {
          AppLogger.w('AITaskCenterPanel', '轮询任务状态失败: taskId=$id', e);
        }
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sub?.cancel();
    _busSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 加载历史任务
  Future<void> _loadHistoryTasks() async {
    if (_isLoadingHistory || !_hasMoreHistory) return;
    
    setState(() {
      _isLoadingHistory = true;
    });
    
    try {
      AppLogger.i('AITaskCenterPanel', '加载历史任务: page=$_currentHistoryPage');
      // 每次仅请求5条父任务（后端按父任务分页）
      final result = await _repo.getUserHistoryTasksPaged(page: _currentHistoryPage, size: 5);
      
      if (result.tasks.isNotEmpty) {
        // 处理任务数据，构建父子关系
        for (final task in result.tasks) {
          final taskId = (task['taskId'] ?? '').toString();
          if (taskId.isEmpty) continue;
          
          // 更新任务状态
          _tasks[taskId] = task;
          
          // 处理父子关系
          final parentId = (task['parentTaskId'] ?? '').toString();
          if (parentId.isNotEmpty) {
            final list = _childrenByParent.putIfAbsent(parentId, () => <Map<String, dynamic>>[]);
            final idx = list.indexWhere((m) => (m['taskId'] ?? '') == taskId);
            if (idx >= 0) {
              list[idx] = task;
            } else {
              list.add(task);
            }
            list.sort((a, b) => ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));
          } else {
            // 父任务添加到历史任务列表
            final existingIndex = _historyTasks.indexWhere((t) => (t['taskId'] ?? '') == taskId);
            if (existingIndex >= 0) {
              _historyTasks[existingIndex] = task;
            } else {
              _historyTasks.add(task);
            }
          }
        }
        
        _currentHistoryPage++;
        _hasMoreHistory = result.hasMore;
        
        AppLogger.i('AITaskCenterPanel', '历史任务加载成功: ${result.tasks.length}条, hasMore=${result.hasMore}');
      } else {
        _hasMoreHistory = false;
        AppLogger.i('AITaskCenterPanel', '没有更多历史任务');
      }
    } catch (e) {
      AppLogger.e('AITaskCenterPanel', '加载历史任务失败', e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏 - 使用现代化设计
        _buildHeader(context),
        
        // 分隔线
        Divider(
          height: 1,
          thickness: 1,
          color: theme.dividerColor.withOpacity(0.1),
        ),
        
        // 任务列表
        Expanded(
          child: _buildTaskList(context),
        ),
      ],
    );
  }

  /// 构建现代化的标题栏
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 20,
            color: WebTheme.getPrimaryColor(context),
          ),
          const SizedBox(width: 8),
          Text(
            'AI任务中心',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: WebTheme.getOnSurfaceColor(context),
            ),
          ),
          const Spacer(),
          // 刷新按钮
          IconButton(
            onPressed: () {
              // 触发刷新
              setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded),
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            style: IconButton.styleFrom(
              foregroundColor: WebTheme.getSecondaryColor(context),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建任务列表
  Widget _buildTaskList(BuildContext context) {
    // 合并实时任务和历史任务（只展示父任务，且排除拆书任务）
    final realtimeTasks = _tasks.values
        .where((t) {
          // 只显示父任务
          if (t['parentTaskId'] != null && t['parentTaskId'].toString().isNotEmpty) {
            return false;
          }
          
          // 排除拆书任务类型
          final taskType = (t['taskType'] ?? '').toString();
          const bookExtractionTypes = [
            'KNOWLEDGE_EXTRACTION_FANQIE', 
            'KNOWLEDGE_EXTRACTION_TEXT', 
            'KNOWLEDGE_EXTRACTION_GROUP'
          ];
          if (bookExtractionTypes.contains(taskType)) {
            return false;
          }
          
          return true;
        })
        .toList();
    
    // 去重合并历史任务
    final allTasks = <Map<String, dynamic>>[];
    final taskIds = <String>{};
    
    // 先添加实时任务
    for (final task in realtimeTasks) {
      final taskId = (task['taskId'] ?? '').toString();
      if (taskId.isNotEmpty && !taskIds.contains(taskId)) {
        allTasks.add(task);
        taskIds.add(taskId);
      }
    }
    
    // 再添加历史任务（避免重复，且排除拆书任务）
    for (final task in _historyTasks) {
      final taskId = (task['taskId'] ?? '').toString();
      if (taskId.isEmpty || taskIds.contains(taskId)) {
        continue;
      }
      
      // 排除拆书任务类型
      final taskType = (task['taskType'] ?? '').toString();
      const bookExtractionTypes = [
        'KNOWLEDGE_EXTRACTION_FANQIE', 
        'KNOWLEDGE_EXTRACTION_TEXT', 
        'KNOWLEDGE_EXTRACTION_GROUP'
      ];
      if (bookExtractionTypes.contains(taskType)) {
        continue;
      }
      
      allTasks.add(task);
      taskIds.add(taskId);
    }
    
    // 按时间倒序排列
    allTasks.sort((a, b) => ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));

    if (allTasks.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: allTasks.length + (_hasMoreHistory ? 1 : 0), // 加载更多按钮
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (index >= allTasks.length) {
          // 显示加载更多按钮
          return _buildLoadMoreButton(context);
        }
        final task = allTasks[index];
        return _buildTaskCard(context, task);
      },
    );
  }

  /// 构建加载更多按钮
  Widget _buildLoadMoreButton(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        onPressed: _isLoadingHistory ? null : _loadHistoryTasks,
        style: ElevatedButton.styleFrom(
          backgroundColor: WebTheme.getSurfaceColor(context),
          foregroundColor: WebTheme.getPrimaryColor(context),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
        child: _isLoadingHistory
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    WebTheme.getPrimaryColor(context),
                  ),
                ),
              )
            : Text(
                '加载更多历史任务',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 48,
            color: theme.colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无任务',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始使用AI功能创建任务吧',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建任务卡片
  Widget _buildTaskCard(BuildContext context, Map<String, dynamic> task) {
    final theme = Theme.of(context);
    final type = (task['type'] ?? '').toString();
    final taskId = (task['taskId'] ?? '').toString();
    final taskType = (task['taskType'] ?? '').toString();
    final ts = task['ts'] ?? (task['timestamps']?['updatedAt']);
                final children = _childrenByParent[taskId] ?? const [];
                final hasChildren = children.isNotEmpty;
    
    // 使用翻译工具获取中文名称
    final taskTypeName = TaskTranslation.getTaskTypeName(taskType);
    final statusName = TaskTranslation.getSmartTaskStatus(task);
    final statusColor = TaskTranslation.getTaskStatusColor(statusName);
    final isCompleted = TaskTranslation.isTaskCompleted(type);
    final isRunning = TaskTranslation.isTaskRunning(type);
    final isFailed = TaskTranslation.isTaskFailed(type);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: _buildStatusIcon(statusColor, isCompleted, isRunning, isFailed),
        title: Row(
          children: [
            Expanded(
              child: Text(
                taskTypeName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getOnSurfaceColor(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(context, statusName, statusColor),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTime(ts),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              if (hasChildren) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.account_tree,
                      size: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${children.length}个子任务',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        children: hasChildren ? _buildChildrenTasks(context, children) : [],
      ),
    );
  }

  /// 构建状态图标
  Widget _buildStatusIcon(String statusColor, bool isCompleted, bool isRunning, bool isFailed) {
    IconData iconData;
    Color iconColor;
    
    if (isCompleted) {
      iconData = Icons.check_circle_outline;
      iconColor = Colors.green;
    } else if (isFailed) {
      iconData = Icons.error_outline;
      iconColor = Colors.red;
    } else if (isRunning) {
      iconData = Icons.radio_button_checked;
      iconColor = Colors.blue;
    } else {
      iconData = Icons.radio_button_unchecked;
      iconColor = Colors.grey;
    }
    
    return Icon(
      iconData,
      size: 20,
      color: iconColor,
    );
  }

  /// 构建状态徽章
  Widget _buildStatusBadge(BuildContext context, String statusName, String statusColor) {
    Color backgroundColor;
    Color textColor;
    
    switch (statusColor) {
      case 'success':
        backgroundColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green.shade700;
        break;
      case 'error':
        backgroundColor = Colors.red.withOpacity(0.1);
        textColor = Colors.red.shade700;
        break;
      case 'primary':
        backgroundColor = WebTheme.getPrimaryColor(context).withOpacity(0.1);
        textColor = WebTheme.getPrimaryColor(context);
        break;
      case 'warning':
        backgroundColor = Colors.orange.withOpacity(0.1);
        textColor = Colors.orange.shade700;
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey.shade700;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusName,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建子任务列表
  List<Widget> _buildChildrenTasks(BuildContext context, List<Map<String, dynamic>> children) {
    return children.map((child) {
      final cType = (child['type'] ?? '').toString();
      final cTaskType = (child['taskType'] ?? '').toString();
      final cTs = child['ts'] ?? (child['timestamps']?['updatedAt']);
      
      // 使用翻译工具
      final cTaskTypeName = TaskTranslation.getTaskTypeName(cTaskType);
      final cStatusName = TaskTranslation.getSmartTaskStatus(child);
      final cStatusColor = TaskTranslation.getTaskStatusColor(cStatusName);
      final isCompleted = TaskTranslation.isTaskCompleted(cType);
      
      // 对子任务（单章生成、剧情预测）完成时提供"预览合并"
      final bool canPreview = isCompleted && (cTaskType == 'GENERATE_SINGLE_CHAPTER' || cTaskType == 'STORY_PREDICTION_SINGLE');
      
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WebTheme.getBackgroundColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            _buildStatusIcon(cStatusColor, isCompleted, TaskTranslation.isTaskRunning(cType), TaskTranslation.isTaskFailed(cType)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cTaskTypeName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // 显示模型信息
                  if (_getModelInfo(child).isNotEmpty) ...[
                    Text(
                      _getModelInfo(child),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                  ],
                  // 详细模型信息：摘要/内容生成所用模型
                  if (_getDetailedModelInfo(child).isNotEmpty) ...[
                    Text(
                      _getDetailedModelInfo(child),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 11,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      _buildStatusBadge(context, cStatusName, cStatusColor),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(cTs),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canPreview) ...[
              const SizedBox(width: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: ElevatedButton(
                  onPressed: () => _openMergePreview(context, child),
                  style: WebTheme.getPrimaryButtonStyle(context).copyWith(
                    minimumSize: MaterialStateProperty.all(const Size(64, 32)),
                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  ),
                  child: const Text('预览合并'),
                ),
              ),
            ],
          ],
        ),
      );
    }).toList();
  }

  void _openMergePreview(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: _MergePreviewDialog(event: event),
      ),
    );
  }
}

class _MergePreviewDialog extends StatefulWidget {
  const _MergePreviewDialog({required this.event});
  final Map<String, dynamic> event;

  @override
  State<_MergePreviewDialog> createState() => _MergePreviewDialogState();
}

class _MergePreviewDialogState extends State<_MergePreviewDialog> {
  String _mergeMode = 'append'; // append | replace | new_chapter
  int _insertPosition = -1; // -1 末尾
  String? _generatedSummary;
  String? _generatedContent;
  String? _novelId;
  bool _loadingNovel = true; // 小说结构加载中
  
  // 标签页状态管理
  int _selectedTabIndex = 0; // 0: 摘要对比, 1: 内容对比

  // 目标选择
  String? _targetChapterId;
  String? _targetSceneId;
  List<Act> _acts = [];
  List<Chapter> _chapters = [];
  List<Scene> _scenesInTargetChapter = [];

  @override
  void initState() {
    super.initState();
    
    // 初始化内容缓存
    _currentSummaryCache = null;
    _currentContentCache = null;
    
    final result = widget.event['result'];
    if (result is Map) {
      // 处理生成的摘要，去掉可能的quill格式
      final rawSummary = result['generatedSummary']?.toString();
      if (rawSummary != null && rawSummary.isNotEmpty) {
        _generatedSummary = QuillHelper.isValidQuillFormat(rawSummary) 
            ? QuillHelper.deltaToText(rawSummary) 
            : rawSummary;
      }
      
      // 处理生成的内容，去掉可能的quill格式
      final rawContent = result['generatedContent']?.toString();
      AppLogger.i('AI任务合并', '初始化 - 原始生成内容: ${rawContent?.length ?? 0}个字符');
      AppLogger.i('AI任务合并', '初始化 - 生成内容预览: ${rawContent != null && rawContent.length > 100 ? rawContent.substring(0, 100) : rawContent ?? "空"}...');
      
      if (rawContent != null && rawContent.isNotEmpty) {
        _generatedContent = QuillHelper.isValidQuillFormat(rawContent) 
            ? QuillHelper.deltaToText(rawContent) 
            : rawContent;
        AppLogger.i('AI任务合并', '初始化 - 处理后内容长度: ${_generatedContent?.length ?? 0}');
      } else {
        AppLogger.w('AI任务合并', '初始化 - 生成内容为空或null');
      }
      // 兼容服务端字段：若没有直接正文，但有章节/场景ID，稍后异步拉取
    }
    _novelId = (widget.event['novelId'] ?? (result is Map ? result['novelId'] : null))?.toString();
    // 异步加载预览数据与目标列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreviewAndTargets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskType = widget.event['taskType']?.toString() ?? '';
    final taskTypeName = TaskTranslation.getTaskTypeName(taskType);
    
    return Container(
      width: 1300,
      height: 850,
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 现代化标题栏
          _buildPreviewHeader(context, taskTypeName),
          
          // 分隔线
          Divider(
            height: 1,
            thickness: 1,
            color: theme.dividerColor.withOpacity(0.1),
          ),
          
          // 主要内容区域
          Expanded(
            child: Row(
              children: [
                // 左侧：生成内容预览
                Expanded(
                  flex: 3,
                  child: _buildContentPreview(context),
                ),
                
                // 分隔线
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.dividerColor.withOpacity(0.1),
                ),
                
                // 右侧：配置面板
                SizedBox(
                  width: 400,
                  child: _buildConfigPanel(context),
                ),
              ],
            ),
          ),
          
          // 底部操作栏
          _buildActionBar(context),
        ],
      ),
    );
  }

  /// 构建预览标题栏
  Widget _buildPreviewHeader(BuildContext context, String taskTypeName) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
            child: Row(
              children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.preview_outlined,
              size: 24,
              color: WebTheme.getPrimaryColor(context),
            ),
                ),
                const SizedBox(width: 16),
                Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '内容预览与合并',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getOnSurfaceColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '任务类型：$taskTypeName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            iconSize: 24,
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.6),
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建内容预览区域
  Widget _buildContentPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标签栏
          Row(
            children: [
              _buildTabButton(context, '摘要对比', 0),
              const SizedBox(width: 12),
              _buildTabButton(context, '内容对比', 1),
              const Spacer(),
              IconButton(
                onPressed: () {
                  // 刷新预览
                  _loadPreviewAndTargets();
                },
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 20,
                style: IconButton.styleFrom(
                  foregroundColor: WebTheme.getSecondaryColor(context),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 对比内容
          Expanded(
            child: _buildComparisonContent(context),
          ),
        ],
      ),
    );
  }

  /// 构建对比内容
  Widget _buildComparisonContent(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _selectedTabIndex == 0 
          ? _buildSummaryComparison(context)
          : _buildContentComparison(context),
    );
  }

  /// 构建摘要对比
  Widget _buildSummaryComparison(BuildContext context) {
    return Row(
      key: const ValueKey('summary_comparison'),
      children: [
        Expanded(
          child: _buildContentCard(
            context,
            title: '生成摘要',
            content: _generatedSummary ?? '正在加载摘要...',
            isGenerated: true,
          ),
        ),
                  const SizedBox(width: 16),
        Expanded(
          child: _buildContentCard(
            context,
            title: '当前摘要',
            content: _loadCurrentSummaryContent(),
            isGenerated: false,
                    ),
                  ),
                ],
    );
  }

  /// 构建内容对比
  Widget _buildContentComparison(BuildContext context) {
    return Row(
      key: const ValueKey('content_comparison'),
      children: [
        Expanded(
          child: _buildContentCard(
            context,
            title: '生成内容',
            content: () {
              AppLogger.i('AI任务合并', '显示生成内容 - 长度: ${_generatedContent?.length ?? 0}');
              return _generatedContent ?? '正在加载内容...';
            }(),
            isGenerated: true,
          ),
        ),
                  const SizedBox(width: 16),
        Expanded(
          child: _buildContentCard(
            context,
            title: '当前内容',
            content: _loadCurrentSceneContent(),
            isGenerated: false,
          ),
        ),
      ],
    );
  }

  /// 当前内容缓存
  String? _currentSummaryCache;
  String? _currentContentCache;

  /// 加载当前摘要内容
  String _loadCurrentSummaryContent() {
    if (_mergeMode == 'new_chapter') {
      return '(新章节模式，无需对比当前摘要)';
    }
    
    if (_currentSummaryCache != null) {
      return _currentSummaryCache!;
    }
    
    if (_targetChapterId != null) {
      _loadCurrentChapterSummary();
      return '正在加载当前章节摘要...';
    }
    
    return '请选择目标章节以加载摘要';
  }

  /// 加载当前场景内容
  String _loadCurrentSceneContent() {
    if (_mergeMode == 'new_chapter') {
      return '(新章节模式，无需对比当前内容)';
    }
    
    if (_currentContentCache != null) {
      return _currentContentCache!;
    }
    
    if (_mergeMode == 'replace' && _targetSceneId != null) {
      _loadCurrentSceneContentFromAPI();
      return '正在加载当前场景内容...';
    } else if (_mergeMode == 'append' && _targetChapterId != null) {
      _loadCurrentChapterLastSceneContent();
      return '正在加载章节末尾场景内容...';
    }
    
    return '请选择目标位置以加载内容';
  }

  /// 异步加载当前章节摘要
  Future<void> _loadCurrentChapterSummary() async {
    if (_targetChapterId == null) return;
    
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final repo = EditorRepositoryImpl(apiClient: api);
      final actId = _findActIdForChapter(_targetChapterId!);
      
      if (actId != null && _novelId != null) {
        final novel = await repo.getNovel(_novelId!);
        if (novel != null) {
          for (final act in novel.acts) {
            for (final chapter in act.chapters) {
                if (chapter.id == _targetChapterId) {
                if (mounted) {
                  setState(() {
                    // Chapter类没有summary字段，通过场景摘要组成章节摘要
                    final sceneSummaries = chapter.scenes
                        .where((scene) => scene.summary.content.isNotEmpty)
                        .map((scene) {
                          // 处理摘要内容，去掉可能的quill格式
                          final summaryContent = scene.summary.content;
                          return QuillHelper.isValidQuillFormat(summaryContent) 
                              ? QuillHelper.deltaToText(summaryContent) 
                              : summaryContent;
                        })
                        .where((summary) => summary.trim().isNotEmpty)
                        .join('\n\n');
                    _currentSummaryCache = sceneSummaries.isNotEmpty ? sceneSummaries : '该章节暂无摘要';
                  });
                }
                return;
              }
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _currentSummaryCache = '无法加载章节摘要';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentSummaryCache = '加载摘要失败: $e';
        });
      }
    }
  }

  /// 异步加载当前场景内容
  Future<void> _loadCurrentSceneContentFromAPI() async {
    if (_targetChapterId == null || _targetSceneId == null) return;
    
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final repo = EditorRepositoryImpl(apiClient: api);
      final actId = _findActIdForChapter(_targetChapterId!);
      
      if (actId != null && _novelId != null) {
        final scene = await repo.getSceneContent(_novelId!, actId, _targetChapterId!, _targetSceneId!);
        if (scene != null && mounted) {
          setState(() {
            // 将quill格式转换为纯文本
            final plainText = scene.content.isNotEmpty 
                ? QuillHelper.deltaToText(scene.content)
                : '该场景暂无内容';
            _currentContentCache = plainText.trim().isNotEmpty ? plainText : '该场景暂无内容';
          });
        } else if (mounted) {
          setState(() {
            _currentContentCache = '无法加载场景内容';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentContentCache = '加载场景内容失败: $e';
        });
      }
    }
  }

  /// 异步加载章节末尾场景内容
  Future<void> _loadCurrentChapterLastSceneContent() async {
    if (_targetChapterId == null) return;
    
    try {
      if (_scenesInTargetChapter.isNotEmpty) {
        final lastScene = _scenesInTargetChapter.last;
        final api = RepositoryProvider.of<ApiClient>(context);
        final repo = EditorRepositoryImpl(apiClient: api);
        final actId = _findActIdForChapter(_targetChapterId!);
        
        if (actId != null && _novelId != null) {
          final scene = await repo.getSceneContent(_novelId!, actId, _targetChapterId!, lastScene.id);
          if (scene != null && mounted) {
            setState(() {
              // 将quill格式转换为纯文本
              final plainText = scene.content.isNotEmpty 
                  ? QuillHelper.deltaToText(scene.content)
                  : '章节末尾场景暂无内容';
              _currentContentCache = plainText.trim().isNotEmpty ? plainText : '章节末尾场景暂无内容';
            });
          } else if (mounted) {
            setState(() {
              _currentContentCache = '无法加载章节末尾内容';
            });
          }
        }
      } else if (mounted) {
        setState(() {
          _currentContentCache = '该章节暂无场景';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentContentCache = '加载章节内容失败: $e';
        });
      }
    }
  }

  /// 获取中文数字
  String _getChineseNumber(int number) {
    const chineseNumbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (number <= 0) return '零';
    if (number <= 10) return chineseNumbers[number - 1];
    if (number < 20) return '十${chineseNumbers[number - 11]}';
    if (number < 100) {
      final tens = number ~/ 10;
      final ones = number % 10;
      return '${chineseNumbers[tens - 1]}十${ones > 0 ? chineseNumbers[ones - 1] : ''}';
    }
    return number.toString(); // 大于100直接用阿拉伯数字
  }

  /// 构建标签按钮
  Widget _buildTabButton(BuildContext context, String text, int tabIndex) {
    final theme = Theme.of(context);
    final bool isActive = _selectedTabIndex == tabIndex;
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = tabIndex;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive 
                ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive 
                  ? WebTheme.getPrimaryColor(context).withOpacity(0.2)
                  : theme.dividerColor.withOpacity(0.1),
              width: 1.5,
            ),
          ),
            child: Row(
            mainAxisSize: MainAxisSize.min,
              children: [
              Icon(
                isActive 
                    ? (tabIndex == 0 ? Icons.summarize : Icons.article)
                    : (tabIndex == 0 ? Icons.summarize_outlined : Icons.article_outlined),
                size: 16,
                color: isActive 
                    ? WebTheme.getPrimaryColor(context)
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive 
                      ? WebTheme.getPrimaryColor(context)
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建内容卡片
  Widget _buildContentCard(BuildContext context, {
    required String title,
    required String content,
    required bool isGenerated,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isGenerated 
                  ? WebTheme.getPrimaryColor(context).withOpacity(0.05)
                  : theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
              child: Row(
                children: [
                Icon(
                  isGenerated ? Icons.auto_awesome : Icons.article_outlined,
                  size: 18,
                  color: isGenerated 
                      ? WebTheme.getPrimaryColor(context)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isGenerated 
                        ? WebTheme.getPrimaryColor(context)
                        : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  content.isEmpty ? '(无内容)' : content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: WebTheme.getOnSurfaceColor(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建配置面板
  Widget _buildConfigPanel(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Text(
            '合并配置',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: WebTheme.getOnSurfaceColor(context),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // 合并模式选择
          _buildConfigSection(
            context,
            title: '合并模式',
            child: _buildMergeModeSelector(context),
          ),
          
          const SizedBox(height: 20),
          
          // 目标章节选择
          if (_chapters.isNotEmpty)
            _buildConfigSection(
              context,
              title: '目标章节',
              child: _buildChapterSelector(context),
            ),
          
          const SizedBox(height: 20),
          
          // 额外配置
          if (_mergeMode == 'append')
            _buildConfigSection(
              context,
              title: '插入位置',
              child: _buildPositionSelector(context),
            ),
          
          if (_mergeMode == 'replace')
            _buildConfigSection(
              context,
              title: '目标场景',
              child: _buildSceneSelector(context),
            ),
          
          if (_mergeMode == 'new_chapter') ...[
            const SizedBox(height: 12),
        Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
        Expanded(
                    child: Text(
                      '将在所选章节之后插入新章节',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                      ),
          ),
        ),
      ],
              ),
            ),
          ],
          
          const Spacer(),
          
          // 任务信息
          _buildTaskInfo(context),
        ],
      ),
    );
  }

  /// 构建配置节
  Widget _buildConfigSection(BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: WebTheme.getOnSurfaceColor(context),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  /// 构建合并模式选择器
  Widget _buildMergeModeSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
                  value: _mergeMode,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
                  items: const [
          DropdownMenuItem(value: 'append', child: Text('作为新场景插入章节末尾')),
                    DropdownMenuItem(value: 'replace', child: Text('替换现有内容')),
                    DropdownMenuItem(value: 'new_chapter', child: Text('作为新章节插入')),
                  ],
        onChanged: (v) {
          setState(() {
            _mergeMode = v ?? 'append';
            // 清空内容缓存以重新加载
            _currentSummaryCache = null;
            _currentContentCache = null;
          });
        },
      ),
    );
  }

  /// 构建章节选择器
  Widget _buildChapterSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _targetChapterId,
                    decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
                    ),
                    items: _chapters
                        .map((c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(c.title, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (!_loadingNovel && _chapters.isNotEmpty)
                        ? (v) {
                            setState(() {
                              _targetChapterId = v;
                              _rebuildScenesForTargetChapter();
                              _insertPosition = -1;
                  // 清空内容缓存以重新加载
                  _currentSummaryCache = null;
                  _currentContentCache = null;
                            });
                          }
                        : null,
                  ),
    );
  }

  /// 构建位置选择器
  Widget _buildPositionSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: _insertPosition,
                      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('末尾（追加到最后）'),
                        ),
                        ..._scenesInTargetChapter.asMap().entries.map((e) {
                          final idx = e.key;
            final scene = e.value;
            final title = scene.title.isNotEmpty 
                ? scene.title 
                : '场景${_getChineseNumber(idx + 1)}';
                          return DropdownMenuItem<int>(
                            value: idx,
              child: Text('在「$title」之后'),
                          );
                        }),
                      ],
                      onChanged: (_targetChapterId != null)
            ? (v) {
                setState(() {
                  _insertPosition = v ?? -1;
                  // 清空内容缓存以重新加载
                  _currentContentCache = null;
                });
              }
                          : null,
                    ),
    );
  }

  /// 构建场景选择器
  Widget _buildSceneSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
                    value: _targetSceneId,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        items: _scenesInTargetChapter
            .asMap()
            .entries
            .map((entry) {
              final index = entry.key;
              final scene = entry.value;
              final displayTitle = scene.title.isNotEmpty 
                  ? scene.title 
                  : '场景${_getChineseNumber(index + 1)}';
              return DropdownMenuItem(
                value: scene.id, 
                child: Text(displayTitle, overflow: TextOverflow.ellipsis),
              );
            })
            .toList(),
        onChanged: (v) {
          setState(() {
            _targetSceneId = v;
            // 清空内容缓存以重新加载
            _currentContentCache = null;
          });
        },
      ),
    );
  }

  /// 构建任务信息
  Widget _buildTaskInfo(BuildContext context) {
    final theme = Theme.of(context);
    final taskId = widget.event['taskId']?.toString() ?? '';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
        ),
      ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(
            '任务信息',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${taskId.length > 8 ? taskId.substring(0, 8) : taskId}...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontFamily: 'monospace',
              ),
            ),
          ],
      ),
    );
  }

  /// 构建操作栏
  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
      children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('取消'),
          ),
          
          const SizedBox(width: 12),
          
          ElevatedButton(
            onPressed: _loadingNovel ? null : _onMergeSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadingNovel) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.merge_type, size: 18),
                const SizedBox(width: 8),
                Text(_loadingNovel ? '处理中...' : '确认合并'),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _onMergeSubmit() async {
    // 显示加载中提示
    final loadingController = LoadingToast.show(context, message: '正在添加内容...');
    
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final EditorRepository repo = EditorRepositoryImpl(apiClient: api);
      final String? novelIdOpt = _novelId;
      if (novelIdOpt == null || novelIdOpt.isEmpty) {
        loadingController.error('缺少小说ID，无法合并');
        return;
      }
      final String novelId = novelIdOpt;

      if (_mergeMode == 'new_chapter') {
        // 原子化创建新章节和场景
        final chapterTitle = 'AI生成章节';
        final sceneTitle = 'AI生成场景';
        final String actIdForInsert = _targetChapterId != null 
            ? (_findActIdForChapter(_targetChapterId!) ?? _findFirstActId())
            : _findFirstActId();
        await repo.addChapterWithScene(
          novelId, 
          actIdForInsert, 
          chapterTitle, 
          sceneTitle, 
          sceneSummary: _generatedSummary, 
          sceneContent: _generatedContent,
          insertAfterChapterId: _targetChapterId // 若选择了目标章节，则在其后插入
        );
        
        loadingController.success('已成功创建新章节：$chapterTitle');
        
        // addChapterWithScene已经发布了CHAPTER_ADDED和SCENE_ADDED事件，会自动触发刷新
      } else if (_mergeMode == 'append') {
        if (_targetChapterId == null) {
          loadingController.error('请选择目标章节');
          return;
        }
        final title = 'AI生成场景';
        final newScene = await repo.addSceneFine(novelId, _targetChapterId!, title, summary: _generatedSummary, content: _generatedContent, position: _insertPosition == -1 ? null : _insertPosition);
        
        loadingController.success('已成功追加到目标章节：${newScene.title}');
        
        // addSceneFine已经发布了NovelStructureUpdatedEvent，不需要额外刷新
      } else if (_mergeMode == 'replace') {
        if (_targetChapterId == null || _targetSceneId == null) {
          loadingController.error('请选择目标章节与场景');
          return;
        }
        final actId = _findActIdForChapter(_targetChapterId!);
        if (actId == null) {
          loadingController.error('无法定位目标章节所属卷');
          return;
        }
        // 调试：检查生成的内容
        AppLogger.i('AI任务合并', '替换模式 - 生成的内容长度: ${_generatedContent?.length ?? 0}');
        AppLogger.i('AI任务合并', '替换模式 - 生成的摘要长度: ${_generatedSummary?.length ?? 0}');
        
        if (_generatedContent == null || _generatedContent!.isEmpty) {
          loadingController.error('生成的内容为空，无法替换场景内容');
          return;
        }
        
        final content = _generatedContent!;
        final wordCount = content.length.toString();
        final summary = Summary(id: '${_targetSceneId!}_summary', content: _generatedSummary ?? '');
        await repo.saveSceneContent(novelId, actId, _targetChapterId!, _targetSceneId!, content, wordCount, summary);
        
        loadingController.success('已成功替换目标场景内容');
        
        // 强制刷新当前活动场景的内容 - 如果替换的是当前正在编辑的场景
        if (mounted) {
          try {
            final editorBloc = context.read<EditorBloc>();
            final currentState = editorBloc.state;
            
            if (currentState is EditorLoaded && 
                currentState.activeSceneId == _targetSceneId) {
              AppLogger.i('AI任务合并', '替换的是当前活动场景，强制刷新编辑器内容');
              
              // 直接设置新的场景内容到EditorBloc
              editorBloc.add(SaveSceneContent(
                novelId: novelId,
                actId: actId,
                chapterId: _targetChapterId!,
                sceneId: _targetSceneId!,
                content: content,
                wordCount: wordCount.toString(),
                localOnly: true, // 只更新本地，不再同步到服务器
              ));
            }
          } catch (e) {
            AppLogger.w('AI任务合并', '无法访问EditorBloc，跳过强制刷新: $e');
          }
        }
        
        // 通过事件总线通知场景内容外部更新（通用刷新通道）
        // 使用QuillHelper确保为标准Quill JSON，避免 /n/n 占位符
        final quillJson = QuillHelper.ensureQuillFormat(content);
        EventBus.instance.fire(SceneContentExternallyUpdatedEvent(
          novelId: novelId,
          actId: actId,
          chapterId: _targetChapterId!,
          sceneId: _targetSceneId!,
          content: quillJson,
        ));
      }
      // 延迟关闭面板，让用户看到成功提示
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      loadingController.error('合并失败: $e');
    }
  }

  Future<void> _loadPreviewAndTargets() async {
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final EditorRepository repo = EditorRepositoryImpl(apiClient: api);
      final String? novelIdOpt = _novelId;
      if (novelIdOpt == null || novelIdOpt.isEmpty) {
        TopToast.error(context, '缺少小说ID，无法加载预览');
        return;
      }
      final String novelId = novelIdOpt;

      // 先尝试刷新小说结构
      final Novel? loaded = await repo.getNovel(novelId);
      final Novel? novel = loaded;
      if (novel == null) {
        TopToast.error(context, '未能加载小说结构');
        return;
      }
      _acts = novel.acts;
      _chapters = novel.acts.expand((a) => a.chapters).toList();
      _targetChapterId ??= (_chapters.isNotEmpty ? _chapters.first.id : null);
      _rebuildScenesForTargetChapter();
      _loadingNovel = false;

      // 如果是单章任务，尝试加载生成内容
      final result = widget.event['result'];
      if (result is Map) {
        final chapterId = result['generatedChapterId']?.toString();
        final sceneId = result['generatedInitialSceneId']?.toString();
        if ((chapterId != null && chapterId.isNotEmpty) && (sceneId != null && sceneId.isNotEmpty)) {
          final actId = _findActIdForChapter(chapterId);
          if (actId != null) {
            final scene = await repo.getSceneContent(novelId, actId, chapterId, sceneId);
            if (scene != null && mounted) {
              setState(() {
                // 将quill格式转换为纯文本
                _generatedContent = scene.content.isNotEmpty 
                    ? QuillHelper.deltaToText(scene.content)
                    : scene.content;
                if ((_generatedSummary == null || _generatedSummary!.isEmpty) && scene.summary.content.isNotEmpty) {
                  final summaryContent = scene.summary.content;
                  _generatedSummary = QuillHelper.isValidQuillFormat(summaryContent) 
                      ? QuillHelper.deltaToText(summaryContent) 
                      : summaryContent;
                }
              });
            }
          }
        }
      }

      // 兜底：若仍无正文，尝试通过任务状态接口获取（需要后端 >= 本次修改）
      if ((_generatedContent == null || _generatedContent!.isEmpty)) {
        try {
          final api = RepositoryProvider.of<ApiClient>(context);
          final taskRepo = TaskRepositoryImpl(apiClient: api);
          final taskId = widget.event['taskId']?.toString();
          if (taskId != null && taskId.isNotEmpty) {
            final status = await taskRepo.getTaskStatus(taskId);
            final res = status['result'];
            if (res is Map && mounted) {
              setState(() {
                // 处理生成的内容，去掉可能的quill格式
                final rawContent = res['generatedContent']?.toString() ?? '';
                AppLogger.i('AI任务合并', '兜底逻辑 - 从API获取的生成内容: ${rawContent.length}个字符');
                AppLogger.i('AI任务合并', '兜底逻辑 - 内容预览: ${rawContent.length > 100 ? rawContent.substring(0, 100) : rawContent}...');
                
                if (rawContent.isNotEmpty) {
                  _generatedContent = QuillHelper.isValidQuillFormat(rawContent) 
                      ? QuillHelper.deltaToText(rawContent) 
                      : rawContent;
                  AppLogger.i('AI任务合并', '兜底逻辑 - 处理后内容长度: ${_generatedContent?.length ?? 0}');
                } else {
                  _generatedContent = rawContent;
                  AppLogger.w('AI任务合并', '兜底逻辑 - API返回的内容仍为空');
                }
                
                // 处理生成的摘要，去掉可能的quill格式
                if (_generatedSummary?.isNotEmpty != true) {
                  final rawSummary = res['generatedSummary']?.toString();
                  if (rawSummary != null && rawSummary.isNotEmpty) {
                    _generatedSummary = QuillHelper.isValidQuillFormat(rawSummary) 
                        ? QuillHelper.deltaToText(rawSummary) 
                        : rawSummary;
                  }
                }
              });
            }
          }
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String? _findActIdForChapter(String chapterId) {
    for (final act in _acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == chapterId) return act.id;
      }
    }
    return null;
  }

  String _findFirstActId() {
    if (_acts.isNotEmpty) {
      return _acts.first.id;
    }
    throw Exception('没有找到可用的卷(Act)');
  }

  void _rebuildScenesForTargetChapter() {
    _scenesInTargetChapter = [];
    if (_targetChapterId == null) return;
    for (final act in _acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == _targetChapterId) {
          _scenesInTargetChapter = chapter.scenes;
          _targetSceneId = _scenesInTargetChapter.isNotEmpty ? _scenesInTargetChapter.first.id : null;
          return;
        }
      }
    }
  }
}


