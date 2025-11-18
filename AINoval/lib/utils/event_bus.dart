import 'dart:async';
import 'package:ainoval/models/novel_snippet.dart';

// 事件基类
abstract class AppEvent {
  const AppEvent();
}

// 小说结构更新事件
class NovelStructureUpdatedEvent extends AppEvent {
  final String novelId;
  final String updateType; // 'outline_saved', 'chapter_added', 'scene_added', etc.
  final Map<String, dynamic> data;

  const NovelStructureUpdatedEvent({
    required this.novelId,
    required this.updateType,
    required this.data,
  });
}

// 场景内容被外部更新（非当前编辑器直接输入）事件
class SceneContentExternallyUpdatedEvent extends AppEvent {
  final String novelId;
  final String? actId; // 可能为空，监听方可自行查找
  final String chapterId;
  final String sceneId;
  final String content; // 可以是纯文本，也可以是Quill JSON字符串

  const SceneContentExternallyUpdatedEvent({
    required this.novelId,
    required this.chapterId,
    required this.sceneId,
    required this.content,
    this.actId,
  });
}

// 片段创建事件
class SnippetCreatedEvent extends AppEvent {
  final NovelSnippet snippet;
  const SnippetCreatedEvent({required this.snippet});
}

// 片段更新事件（可扩展）
class SnippetUpdatedEvent extends AppEvent {
  final NovelSnippet snippet;
  const SnippetUpdatedEvent({required this.snippet});
}

// 片段删除事件（可扩展）
class SnippetDeletedEvent extends AppEvent {
  final String snippetId;
  final String novelId;
  const SnippetDeletedEvent({required this.snippetId, required this.novelId});
}

// 任务事件（SSE）接收事件
class TaskEventReceived extends AppEvent {
  final Map<String, dynamic> event;
  const TaskEventReceived({required this.event});
}

// 请求开始全局任务事件监听
class StartTaskEventsListening extends AppEvent {
  const StartTaskEventsListening();
}

// 请求停止全局任务事件监听
class StopTaskEventsListening extends AppEvent {
  const StopTaskEventsListening();
}

// 导航到“提示词与预设”页面事件（保持左侧布局）
class NavigateToUnifiedManagement extends AppEvent {
  const NavigateToUnifiedManagement();
}

// 事件总线单例
class EventBus {
  // 单例实例
  static final EventBus _instance = EventBus._internal();
  static EventBus get instance => _instance;

  // 事件流控制器
  final StreamController<AppEvent> _eventController = StreamController<AppEvent>.broadcast();

  // 获取事件流
  Stream<AppEvent> get eventStream => _eventController.stream;

  // 发送事件
  void fire(AppEvent event) {
    _eventController.add(event);
  }

  // 获取特定类型的事件流
  Stream<T> on<T extends AppEvent>() {
    return eventStream.where((event) => event is T).cast<T>();
  }

  // 私有构造函数，确保单例模式
  EventBus._internal();

  // 关闭事件总线
  void dispose() {
    _eventController.close();
  }
} 