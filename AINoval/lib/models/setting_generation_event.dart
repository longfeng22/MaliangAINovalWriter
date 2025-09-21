import 'setting_node.dart';
import 'package:ainoval/utils/date_time_parser.dart';

/// 设定生成事件基类
abstract class SettingGenerationEvent {
  final String sessionId;
  final DateTime timestamp;
  final String eventType;

  const SettingGenerationEvent({
    required this.sessionId,
    required this.timestamp,
    required this.eventType,
  });

  factory SettingGenerationEvent.fromJson(Map<String, dynamic> json) {
    // 兼容后端 complete 事件的结束信号（无 eventType，但含 isComplete/finishReason）
    final dynamic rawType = json['eventType'];
    final String? eventType = rawType is String && rawType.isNotEmpty ? rawType : null;
    if (eventType == null) {
      final bool isComplete = (json['isComplete'] == true);
      final bool hasFinishReason = json['finishReason'] != null && json['finishReason'].toString().isNotEmpty;
      if (isComplete || hasFinishReason) {
        // 构造一个完成事件用于驱动前端状态收尾
        return GenerationCompletedEvent(
          sessionId: (json['sessionId'] as String?) ?? 'unknown-session',
          timestamp: DateTime.now(),
          stage: 'completed',
          message: '流式生成完成',
          resultSummary: null,
          affectedNodeIds: null,
        );
      }
      throw ArgumentError('Unknown event type: null');
    }
    
    switch (eventType) {
      case 'SESSION_STARTED':
        return SessionStartedEvent.fromJson(json);
      case 'NODE_CREATED':
        return NodeCreatedEvent.fromJson(json);
      case 'NODE_UPDATED':
        return NodeUpdatedEvent.fromJson(json);
      case 'NODE_DELETED':
        return NodeDeletedEvent.fromJson(json);
      case 'GENERATION_PROGRESS':
        return GenerationProgressEvent.fromJson(json);
      case 'GENERATION_COMPLETED':
        return GenerationCompletedEvent.fromJson(json);
      case 'GENERATION_ERROR':
        return GenerationErrorEvent.fromJson(json);
      case 'COST_ESTIMATION':
        return CostEstimationEvent.fromJson(json);
      default:
        throw ArgumentError('Unknown event type: $eventType');
    }
  }

  Map<String, dynamic> toJson();
}

/// 预计积分事件
class CostEstimationEvent extends SettingGenerationEvent {
  final int? estimatedCost;
  final int? estimatedInputTokens;
  final int? estimatedOutputTokens;
  final String? modelProvider;
  final String? modelId;
  final double? creditMultiplier;
  final bool? publicModel;

  const CostEstimationEvent({
    required String sessionId,
    required DateTime timestamp,
    this.estimatedCost,
    this.estimatedInputTokens,
    this.estimatedOutputTokens,
    this.modelProvider,
    this.modelId,
    this.creditMultiplier,
    this.publicModel,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'COST_ESTIMATION',
        );

  factory CostEstimationEvent.fromJson(Map<String, dynamic> json) {
    return CostEstimationEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      estimatedCost: (json['estimatedCost'] as num?)?.toInt(),
      estimatedInputTokens: (json['estimatedInputTokens'] as num?)?.toInt(),
      estimatedOutputTokens: (json['estimatedOutputTokens'] as num?)?.toInt(),
      modelProvider: json['modelProvider'] as String?,
      modelId: json['modelId'] as String?,
      creditMultiplier: (json['creditMultiplier'] as num?)?.toDouble(),
      publicModel: json['publicModel'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'estimatedCost': estimatedCost,
    'estimatedInputTokens': estimatedInputTokens,
    'estimatedOutputTokens': estimatedOutputTokens,
    'modelProvider': modelProvider,
    'modelId': modelId,
    'creditMultiplier': creditMultiplier,
    'publicModel': publicModel,
  };
}

/// 会话开始事件
class SessionStartedEvent extends SettingGenerationEvent {
  final String initialPrompt;
  final String strategy;

  const SessionStartedEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.initialPrompt,
    required this.strategy,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'SESSION_STARTED',
        );

  factory SessionStartedEvent.fromJson(Map<String, dynamic> json) {
    return SessionStartedEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      initialPrompt: json['initialPrompt'] as String,
      strategy: json['strategy'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'initialPrompt': initialPrompt,
    'strategy': strategy,
  };
}

/// 节点创建事件
class NodeCreatedEvent extends SettingGenerationEvent {
  final SettingNode node;
  final String? parentPath; // 从根节点到父节点的路径

  const NodeCreatedEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.node,
    this.parentPath,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'NODE_CREATED',
        );

  factory NodeCreatedEvent.fromJson(Map<String, dynamic> json) {
    return NodeCreatedEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      node: SettingNode.fromJson(json['node'] as Map<String, dynamic>),
      parentPath: json['parentPath'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'node': node.toJson(),
    'parentPath': parentPath,
  };
}

/// 节点更新事件
class NodeUpdatedEvent extends SettingGenerationEvent {
  final SettingNode node;
  final List<String> changedFields;

  const NodeUpdatedEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.node,
    required this.changedFields,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'NODE_UPDATED',
        );

  factory NodeUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return NodeUpdatedEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      node: SettingNode.fromJson(json['node'] as Map<String, dynamic>),
      changedFields: List<String>.from(json['changedFields'] ?? []),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'node': node.toJson(),
    'changedFields': changedFields,
  };
}

/// 节点删除事件
class NodeDeletedEvent extends SettingGenerationEvent {
  final List<String> deletedNodeIds;
  final String? reason;

  const NodeDeletedEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.deletedNodeIds,
    this.reason,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'NODE_DELETED',
        );

  factory NodeDeletedEvent.fromJson(Map<String, dynamic> json) {
    // 兼容旧的 'nodeId' 字段和新的 'deletedNodeIds' 字段
    List<String> ids = [];
    if (json.containsKey('deletedNodeIds')) {
      ids = List<String>.from(json['deletedNodeIds']);
    } else if (json.containsKey('nodeId')) {
      ids = [json['nodeId'] as String];
    }
    
    return NodeDeletedEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      deletedNodeIds: ids,
      reason: json['reason'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'deletedNodeIds': deletedNodeIds,
    'reason': reason,
  };
}

/// 生成进度事件
class GenerationProgressEvent extends SettingGenerationEvent {
  final String stage;
  final String message;
  final int? currentStep;
  final int? totalSteps;
  final String? nodeId;

  const GenerationProgressEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.stage,
    required this.message,
    this.currentStep,
    this.totalSteps,
    this.nodeId,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'GENERATION_PROGRESS',
        );

  factory GenerationProgressEvent.fromJson(Map<String, dynamic> json) {
    return GenerationProgressEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      stage: json['stage'] as String,
      message: json['message'] as String,
      currentStep: json['currentStep'] as int?,
      totalSteps: json['totalSteps'] as int?,
      nodeId: json['nodeId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'stage': stage,
    'message': message,
    'currentStep': currentStep,
    'totalSteps': totalSteps,
    'nodeId': nodeId,
  };
}

/// 生成完成事件
class GenerationCompletedEvent extends SettingGenerationEvent {
  final String stage;
  final String message;
  final String? resultSummary;
  final List<String>? affectedNodeIds;

  const GenerationCompletedEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.stage,
    required this.message,
    this.resultSummary,
    this.affectedNodeIds,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'GENERATION_COMPLETED',
        );

  factory GenerationCompletedEvent.fromJson(Map<String, dynamic> json) {
    return GenerationCompletedEvent(
      sessionId: json['sessionId'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      stage: json['stage'] as String? ?? 'completed',
      message: json['message'] as String? ?? '生成完成',
      resultSummary: json['resultSummary'] as String?,
      affectedNodeIds: json['affectedNodeIds'] != null 
        ? List<String>.from(json['affectedNodeIds'])
        : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'stage': stage,
    'message': message,
    'resultSummary': resultSummary,
    'affectedNodeIds': affectedNodeIds,
  };
}

/// 生成错误事件
class GenerationErrorEvent extends SettingGenerationEvent {
  final String errorCode;
  final String errorMessage;
  final String? stage;
  final String? nodeId;
  final bool? recoverable;
  final String? suggestionForUser;

  const GenerationErrorEvent({
    required String sessionId,
    required DateTime timestamp,
    required this.errorCode,
    required this.errorMessage,
    this.stage,
    this.nodeId,
    this.recoverable,
    this.suggestionForUser,
  }) : super(
          sessionId: sessionId,
          timestamp: timestamp,
          eventType: 'GENERATION_ERROR',
        );

  factory GenerationErrorEvent.fromJson(Map<String, dynamic> json) {
    // 兼容后端在 onErrorResume 分支可能未填充的字段
    final rawSessionId = json['sessionId'];
    final sessionId = (rawSessionId is String && rawSessionId.isNotEmpty)
        ? rawSessionId
        : 'unknown-session';
    final rawTimestamp = json['timestamp'];
    final timestamp = rawTimestamp != null
        ? parseBackendDateTime(rawTimestamp)
        : DateTime.now();
    return GenerationErrorEvent(
      sessionId: sessionId,
      timestamp: timestamp,
      errorCode: (json['errorCode'] as String?) ?? 'UNKNOWN_ERROR',
      errorMessage: (json['errorMessage'] as String?) ?? '发生错误',
      stage: json['stage'] as String?,
      nodeId: json['nodeId'] as String?,
      recoverable: json['recoverable'] as bool?,
      suggestionForUser: json['suggestionForUser'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'stage': stage,
    'nodeId': nodeId,
    'recoverable': recoverable,
    'suggestionForUser': suggestionForUser,
  };
}
