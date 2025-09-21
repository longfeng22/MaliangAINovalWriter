import 'package:equatable/equatable.dart';
import '../../models/setting_generation_session.dart';
import '../../models/setting_node.dart';
import '../../models/setting_generation_event.dart' as event_model;
import '../../models/compose_preview.dart';
import '../../models/strategy_template_info.dart';
import '../../utils/setting_node_utils.dart'; // 导入工具类

abstract class SettingGenerationState extends Equatable {
  const SettingGenerationState();

  @override
  List<Object?> get props => [];
}

/// 初始状态
class SettingGenerationInitial extends SettingGenerationState {
  const SettingGenerationInitial();
}

/// 加载中
class SettingGenerationLoading extends SettingGenerationState {
  final String? message;

  const SettingGenerationLoading({this.message});

  @override
  List<Object?> get props => [message];
}

/// 策略已加载
class StrategiesLoaded extends SettingGenerationState {
  final List<StrategyTemplateInfo> strategies;

  const StrategiesLoaded(this.strategies);

  @override
  List<Object?> get props => [strategies];
}

/// 待机状态（准备开始生成）
class SettingGenerationReady extends SettingGenerationState {
  final List<StrategyTemplateInfo> strategies;
  final List<SettingGenerationSession> sessions;
  final String? activeSessionId;
  final String adjustmentPrompt;
  final String viewMode;
  // 🔧 新增：黄金三章状态标志
  final ComposeReadyInfo? composeReady;

  const SettingGenerationReady({
    required this.strategies,
    this.sessions = const [],
    this.activeSessionId,
    this.adjustmentPrompt = '',
    this.viewMode = 'compact',
    this.composeReady,
  });

  @override
  List<Object?> get props => [
        strategies,
        sessions,
        activeSessionId,
        adjustmentPrompt,
        viewMode,
        composeReady,
      ];

  SettingGenerationReady copyWith({
    List<StrategyTemplateInfo>? strategies,
    List<SettingGenerationSession>? sessions,
    String? activeSessionId,
    String? adjustmentPrompt,
    String? viewMode,
    ComposeReadyInfo? composeReady,
  }) {
    return SettingGenerationReady(
      strategies: strategies ?? this.strategies,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      adjustmentPrompt: adjustmentPrompt ?? this.adjustmentPrompt,
      viewMode: viewMode ?? this.viewMode,
      composeReady: composeReady ?? this.composeReady,
    );
  }
}

/// 节点渲染状态枚举
enum NodeRenderState {
  pending,     // 待渲染（在队列中）
  rendering,   // 正在渲染（动画中）
  rendered,    // 已渲染完成
}

/// 节点渲染信息
class NodeRenderInfo {
  final String nodeId;
  final NodeRenderState state;
  final DateTime? renderStartTime;
  final Duration? renderDuration;

  const NodeRenderInfo({
    required this.nodeId,
    required this.state,
    this.renderStartTime,
    this.renderDuration,
  });

  NodeRenderInfo copyWith({
    NodeRenderState? state,
    DateTime? renderStartTime,
    Duration? renderDuration,
  }) {
    return NodeRenderInfo(
      nodeId: nodeId,
      state: state ?? this.state,
      renderStartTime: renderStartTime ?? this.renderStartTime,
      renderDuration: renderDuration ?? this.renderDuration,
    );
  }
}

/// 生成中
class SettingGenerationInProgress extends SettingGenerationState {
  final List<StrategyTemplateInfo> strategies;
  final List<SettingGenerationSession> sessions;
  final String activeSessionId;
  final SettingGenerationSession activeSession;
  final String? selectedNodeId;
  final String viewMode;
  final String adjustmentPrompt;
  final Map<String, SettingNode> pendingChanges;
  final Set<String> highlightedNodeIds;
  final Map<String, List<SettingNode>> editHistory;
  final List<event_model.SettingGenerationEvent> events;
  final bool isGenerating;
  final String? currentOperation;
  // 新增：写作编排流的预览缓存（仅前端展示，不落库）
  final List<ComposeChapterPreview> composePreview;
  
  // 新增的渲染状态管理字段
  final Map<String, NodeRenderInfo> nodeRenderStates;
  final List<String> renderQueue;
  final Set<String> renderedNodeIds;

  final List<event_model.NodeCreatedEvent> pendingNodes;
  // 粘性警告（例如余额不足提醒），不会被后续普通事件覆盖
  final String? stickyWarning;
  // 🔧 新增：黄金三章状态标志
  final ComposeReadyInfo? composeReady;

  const SettingGenerationInProgress({
    required this.strategies,
    required this.sessions,
    required this.activeSessionId,
    required this.activeSession,
    this.selectedNodeId,
    this.viewMode = 'compact',
    this.adjustmentPrompt = '',
    this.pendingChanges = const {},
    this.highlightedNodeIds = const {},
    this.editHistory = const {},
    this.isGenerating = false,
    this.currentOperation,
    this.composePreview = const [],
    this.events = const [],
    this.nodeRenderStates = const {},
    this.renderQueue = const [],
    this.renderedNodeIds = const {},
    this.pendingNodes = const [],
    this.stickyWarning,
    this.composeReady,
  });

  @override
  List<Object?> get props => [
    strategies,
    sessions,
    activeSessionId,
    activeSession,
    selectedNodeId,
    viewMode,
    adjustmentPrompt,
    pendingChanges,
    highlightedNodeIds,
    editHistory,
    isGenerating,
    currentOperation,
    composePreview,
    events,
    nodeRenderStates,
    renderQueue,
    renderedNodeIds,
    stickyWarning,
    composeReady,
  ];

  SettingGenerationInProgress copyWith({
    List<StrategyTemplateInfo>? strategies,
    List<SettingGenerationSession>? sessions,
    String? activeSessionId,
    SettingGenerationSession? activeSession,
    String? selectedNodeId,
    String? viewMode,
    String? adjustmentPrompt,
    Map<String, SettingNode>? pendingChanges,
    Set<String>? highlightedNodeIds,
    Map<String, List<SettingNode>>? editHistory,
    bool? isGenerating,
    String? currentOperation,
    List<ComposeChapterPreview>? composePreview,
    List<event_model.SettingGenerationEvent>? events,
    Map<String, NodeRenderInfo>? nodeRenderStates,
    List<String>? renderQueue,
    Set<String>? renderedNodeIds,
    List<event_model.NodeCreatedEvent>? pendingNodes,
    String? stickyWarning,
    ComposeReadyInfo? composeReady,
  }) {
    return SettingGenerationInProgress(
      strategies: strategies ?? this.strategies,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSession: activeSession ?? this.activeSession,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      viewMode: viewMode ?? this.viewMode,
      adjustmentPrompt: adjustmentPrompt ?? this.adjustmentPrompt,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      highlightedNodeIds: highlightedNodeIds ?? this.highlightedNodeIds,
      editHistory: editHistory ?? this.editHistory,
      isGenerating: isGenerating ?? this.isGenerating,
      currentOperation: currentOperation ?? this.currentOperation,
      composePreview: composePreview ?? this.composePreview,
      events: events ?? this.events,
      nodeRenderStates: nodeRenderStates ?? this.nodeRenderStates,
      renderQueue: renderQueue ?? this.renderQueue,
      renderedNodeIds: renderedNodeIds ?? this.renderedNodeIds,
      pendingNodes: pendingNodes ?? this.pendingNodes,
      stickyWarning: stickyWarning ?? this.stickyWarning,
      composeReady: composeReady ?? this.composeReady,
    );
  }

  /// 获取当前选中的节点
  SettingNode? get selectedNode {
    if (selectedNodeId == null) return null;
    return SettingNodeUtils.findNodeInTree(activeSession.rootNodes, selectedNodeId!);
  }

  /// 获取可以渲染的节点列表（父节点为空或已渲染）
  List<String> get renderableNodeIds {
    return SettingNodeUtils.getRenderableNodeIds(
      activeSession.rootNodes,
      renderQueue,
      renderedNodeIds,
    );
  }
}

/// 生成完成
class SettingGenerationCompleted extends SettingGenerationState {
  final List<StrategyTemplateInfo> strategies;
  final List<SettingGenerationSession> sessions;
  final String activeSessionId;
  final SettingGenerationSession activeSession;
  final String? selectedNodeId;
  final String viewMode;
  final String adjustmentPrompt;
  final Map<String, SettingNode> pendingChanges;
  final Set<String> highlightedNodeIds;
  final Map<String, List<SettingNode>> editHistory;
  final List<event_model.SettingGenerationEvent> events;
  final String message;
  
  // 新增的渲染状态管理字段
  final Map<String, NodeRenderInfo> nodeRenderStates;
  final Set<String> renderedNodeIds;
  final String? stickyWarning;
  // 🔧 新增：黄金三章状态标志
  final ComposeReadyInfo? composeReady;

  const SettingGenerationCompleted({
    required this.strategies,
    required this.sessions,
    required this.activeSessionId,
    required this.activeSession,
    this.selectedNodeId,
    this.viewMode = 'compact',
    this.adjustmentPrompt = '',
    this.pendingChanges = const {},
    this.highlightedNodeIds = const {},
    this.editHistory = const {},
    this.events = const [],
    required this.message,
    this.nodeRenderStates = const {},
    this.renderedNodeIds = const {},
    this.stickyWarning,
    this.composeReady,
  });

  @override
  List<Object?> get props => [
    strategies,
    sessions,
    activeSessionId,
    activeSession,
    selectedNodeId,
    viewMode,
    adjustmentPrompt,
    pendingChanges,
    highlightedNodeIds,
    editHistory,
    events,
    message,
    nodeRenderStates,
    renderedNodeIds,
    stickyWarning,
    composeReady,
  ];

  SettingGenerationCompleted copyWith({
    List<StrategyTemplateInfo>? strategies,
    List<SettingGenerationSession>? sessions,
    String? activeSessionId,
    SettingGenerationSession? activeSession,
    String? selectedNodeId,
    String? viewMode,
    String? adjustmentPrompt,
    Map<String, SettingNode>? pendingChanges,
    Set<String>? highlightedNodeIds,
    Map<String, List<SettingNode>>? editHistory,
    List<event_model.SettingGenerationEvent>? events,
    String? message,
    Map<String, NodeRenderInfo>? nodeRenderStates,
    Set<String>? renderedNodeIds,
    String? stickyWarning,
    ComposeReadyInfo? composeReady,
  }) {
    return SettingGenerationCompleted(
      strategies: strategies ?? this.strategies,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSession: activeSession ?? this.activeSession,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      viewMode: viewMode ?? this.viewMode,
      adjustmentPrompt: adjustmentPrompt ?? this.adjustmentPrompt,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      highlightedNodeIds: highlightedNodeIds ?? this.highlightedNodeIds,
      editHistory: editHistory ?? this.editHistory,
      events: events ?? this.events,
      message: message ?? this.message,
      nodeRenderStates: nodeRenderStates ?? this.nodeRenderStates,
      renderedNodeIds: renderedNodeIds ?? this.renderedNodeIds,
      stickyWarning: stickyWarning ?? this.stickyWarning,
      composeReady: composeReady ?? this.composeReady,
    );
  }

  /// 获取当前选中的节点
  SettingNode? get selectedNode {
    if (selectedNodeId == null) return null;
    return SettingNodeUtils.findNodeInTree(activeSession.rootNodes, selectedNodeId!);
  }
}

/// 节点修改中状态（专门用于节点修改，避免整个设定树重新渲染）
class SettingGenerationNodeUpdating extends SettingGenerationState {
  final List<StrategyTemplateInfo> strategies;
  final List<SettingGenerationSession> sessions;
  final String activeSessionId;
  final SettingGenerationSession activeSession;
  final String? selectedNodeId;
  final String viewMode;
  final String adjustmentPrompt;
  final Map<String, SettingNode> pendingChanges;
  final Set<String> highlightedNodeIds;
  final Map<String, List<SettingNode>> editHistory;
  final List<event_model.SettingGenerationEvent> events;
  final String message;
  
  // 节点修改特有字段
  final String updatingNodeId; // 正在修改的节点ID
  final String modificationPrompt; // 修改提示词
  final String scope; // 修改范围
  final bool isUpdating; // 是否正在更新中
  
  // 渲染状态管理字段
  final Map<String, NodeRenderInfo> nodeRenderStates;
  final Set<String> renderedNodeIds;
  // 🔧 新增：黄金三章状态标志
  final ComposeReadyInfo? composeReady;

  const SettingGenerationNodeUpdating({
    required this.strategies,
    required this.sessions,
    required this.activeSessionId,
    required this.activeSession,
    this.selectedNodeId,
    this.viewMode = 'compact',
    this.adjustmentPrompt = '',
    this.pendingChanges = const {},
    this.highlightedNodeIds = const {},
    this.editHistory = const {},
    this.events = const [],
    this.message = '',
    required this.updatingNodeId,
    this.modificationPrompt = '',
    this.scope = 'self',
    this.isUpdating = false,
    this.nodeRenderStates = const {},
    this.renderedNodeIds = const {},
    this.composeReady,
  });

  @override
  List<Object?> get props => [
    strategies,
    sessions,
    activeSessionId,
    activeSession,
    selectedNodeId,
    viewMode,
    adjustmentPrompt,
    pendingChanges,
    highlightedNodeIds,
    editHistory,
    events,
    message,
    updatingNodeId,
    modificationPrompt,
    scope,
    isUpdating,
    nodeRenderStates,
    renderedNodeIds,
    composeReady,
  ];

  SettingGenerationNodeUpdating copyWith({
    List<StrategyTemplateInfo>? strategies,
    List<SettingGenerationSession>? sessions,
    String? activeSessionId,
    SettingGenerationSession? activeSession,
    String? selectedNodeId,
    String? viewMode,
    String? adjustmentPrompt,
    Map<String, SettingNode>? pendingChanges,
    Set<String>? highlightedNodeIds,
    Map<String, List<SettingNode>>? editHistory,
    List<event_model.SettingGenerationEvent>? events,
    String? message,
    String? updatingNodeId,
    String? modificationPrompt,
    String? scope,
    bool? isUpdating,
    Map<String, NodeRenderInfo>? nodeRenderStates,
    Set<String>? renderedNodeIds,
    ComposeReadyInfo? composeReady,
  }) {
    return SettingGenerationNodeUpdating(
      strategies: strategies ?? this.strategies,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSession: activeSession ?? this.activeSession,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      viewMode: viewMode ?? this.viewMode,
      adjustmentPrompt: adjustmentPrompt ?? this.adjustmentPrompt,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      highlightedNodeIds: highlightedNodeIds ?? this.highlightedNodeIds,
      editHistory: editHistory ?? this.editHistory,
      events: events ?? this.events,
      message: message ?? this.message,
      updatingNodeId: updatingNodeId ?? this.updatingNodeId,
      modificationPrompt: modificationPrompt ?? this.modificationPrompt,
      scope: scope ?? this.scope,
      isUpdating: isUpdating ?? this.isUpdating,
      nodeRenderStates: nodeRenderStates ?? this.nodeRenderStates,
      renderedNodeIds: renderedNodeIds ?? this.renderedNodeIds,
      composeReady: composeReady ?? this.composeReady,
    );
  }

  /// 获取当前选中的节点
  SettingNode? get selectedNode {
    if (selectedNodeId == null) return null;
    return SettingNodeUtils.findNodeInTree(activeSession.rootNodes, selectedNodeId!);
  }

  /// 获取正在修改的节点
  SettingNode? get updatingNode {
    return SettingNodeUtils.findNodeInTree(activeSession.rootNodes, updatingNodeId);
  }
}

/// 保存成功
class SettingGenerationSaved extends SettingGenerationState {
  final List<String> savedSettingIds;
  final String message;
  // 新增：保留会话列表和当前活跃会话ID，避免UI刷新
  final List<SettingGenerationSession> sessions;
  final String? activeSessionId;

  const SettingGenerationSaved({
    required this.savedSettingIds,
    this.message = '设定已成功保存',
    this.sessions = const [],
    this.activeSessionId,
  });

  @override
  List<Object?> get props => [savedSettingIds, message, sessions, activeSessionId];
}

/// 错误状态
class SettingGenerationError extends SettingGenerationState {
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final bool isRecoverable;
  // 新增：保留会话列表和当前活跃会话 ID，避免 UI 在错误时丢失历史记录
  final List<SettingGenerationSession> sessions;
  final String? activeSessionId;
  // 🔧 新增：黄金三章状态标志
  final ComposeReadyInfo? composeReady;

  const SettingGenerationError({
    required this.message,
    this.error,
    this.stackTrace,
    this.isRecoverable = true,
    this.sessions = const [],
    this.activeSessionId,
    this.composeReady,
  });

  @override
  List<Object?> get props => [
    message,
    error,
    stackTrace,
    isRecoverable,
    sessions,
    activeSessionId,
    composeReady,
  ];

  SettingGenerationError copyWith({
    String? message,
    dynamic error,
    StackTrace? stackTrace,
    bool? isRecoverable,
    List<SettingGenerationSession>? sessions,
    String? activeSessionId,
    ComposeReadyInfo? composeReady,
  }) {
    return SettingGenerationError(
      message: message ?? this.message,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      isRecoverable: isRecoverable ?? this.isRecoverable,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      composeReady: composeReady ?? this.composeReady,
    );
  }
}
