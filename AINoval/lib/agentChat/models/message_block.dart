/// 消息块模型定义
/// Message block model definitions
/// 
/// 对应TypeScript的MessageBlock类型系统

import 'package:equatable/equatable.dart';
import '../config/constants.dart';

/// 消息块基类
/// Base message block class
abstract class MessageBlock extends Equatable {
  const MessageBlock();
  
  String get type;
  
  /// 转换为JSON
  Map<String, dynamic> toJson();
  
  /// 从JSON创建
  static MessageBlock fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    
    switch (type) {
      case BlockType.text:
        return TextBlock.fromJson(json);
      case BlockType.tool:
        return ToolBlock.fromJson(json);
      case BlockType.thinking:
        return ThinkingBlock.fromJson(json);
      case BlockType.citation:
        return CitationBlock.fromJson(json);
      case BlockType.approval:
        return ToolApprovalBlock.fromJson(json);
      case BlockType.taskAssignment:
        return TaskAssignmentBlock.fromJson(json);
      default:
        throw Exception('Unknown block type: $type');
    }
  }
}

// ==================== 文本块 ====================

/// 文本块
/// Text block
class TextBlock extends MessageBlock {
  final String content;
  
  const TextBlock({required this.content});
  
  @override
  String get type => BlockType.text;
  
  @override
  List<Object?> get props => [content];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
  };
  
  factory TextBlock.fromJson(Map<String, dynamic> json) => TextBlock(
    content: json['content'] as String,
  );
  
  TextBlock copyWith({String? content}) => TextBlock(
    content: content ?? this.content,
  );
}

// ==================== 工具块 ====================

/// 工具详情
/// Tool details
class ToolDetails extends Equatable {
  final String title;
  final String content;
  
  const ToolDetails({
    required this.title,
    required this.content,
  });
  
  @override
  List<Object?> get props => [title, content];
  
  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
  };
  
  factory ToolDetails.fromJson(Map<String, dynamic> json) => ToolDetails(
    title: json['title'] as String,
    content: json['content'] as String,
  );
}

/// 工具块
/// Tool block
class ToolBlock extends MessageBlock {
  final String toolType;      // 'view' | 'crud'
  final String toolName;
  final String? operation;    // 'create' | 'update' | 'delete' | null
  final String status;        // 'running' | 'complete'
  final String? duration;
  final ToolDetails? details;
  final bool? applied;
  final bool? isExpanded;
  
  const ToolBlock({
    required this.toolType,
    required this.toolName,
    this.operation,
    required this.status,
    this.duration,
    this.details,
    this.applied,
    this.isExpanded,
  });
  
  @override
  String get type => BlockType.tool;
  
  @override
  List<Object?> get props => [
    toolType,
    toolName,
    operation,
    status,
    duration,
    details,
    applied,
    isExpanded,
  ];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'toolType': toolType,
    'toolName': toolName,
    if (operation != null) 'operation': operation,
    'status': status,
    if (duration != null) 'duration': duration,
    if (details != null) 'details': details!.toJson(),
    if (applied != null) 'applied': applied,
    if (isExpanded != null) 'isExpanded': isExpanded,
  };
  
  factory ToolBlock.fromJson(Map<String, dynamic> json) => ToolBlock(
    toolType: json['toolType'] as String,
    toolName: json['toolName'] as String,
    operation: json['operation'] as String?,
    status: json['status'] as String,
    duration: json['duration'] as String?,
    details: json['details'] != null 
        ? ToolDetails.fromJson(json['details'] as Map<String, dynamic>)
        : null,
    applied: json['applied'] as bool?,
    isExpanded: json['isExpanded'] as bool?,
  );
  
  ToolBlock copyWith({
    String? toolType,
    String? toolName,
    String? operation,
    String? status,
    String? duration,
    ToolDetails? details,
    bool? applied,
    bool? isExpanded,
  }) => ToolBlock(
    toolType: toolType ?? this.toolType,
    toolName: toolName ?? this.toolName,
    operation: operation ?? this.operation,
    status: status ?? this.status,
    duration: duration ?? this.duration,
    details: details ?? this.details,
    applied: applied ?? this.applied,
    isExpanded: isExpanded ?? this.isExpanded,
  );
}

// ==================== 思考块 ====================

/// 思考步骤
/// Thinking step
class ThinkingStep extends Equatable {
  final String id;
  final String type;      // 'plan' | 'thought' | 'observation'
  final String title;
  final String? detail;
  final String status;    // 'thinking' | 'complete'
  
  const ThinkingStep({
    required this.id,
    required this.type,
    required this.title,
    this.detail,
    required this.status,
  });
  
  @override
  List<Object?> get props => [id, type, title, detail, status];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (detail != null) 'detail': detail,
    'status': status,
  };
  
  factory ThinkingStep.fromJson(Map<String, dynamic> json) => ThinkingStep(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String?,
    status: json['status'] as String,
  );
  
  ThinkingStep copyWith({
    String? id,
    String? type,
    String? title,
    String? detail,
    String? status,
  }) => ThinkingStep(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    detail: detail ?? this.detail,
    status: status ?? this.status,
  );
}

/// 思考块
/// Thinking block
class ThinkingBlock extends MessageBlock {
  final List<ThinkingStep> steps;
  final bool isExpanded;
  
  const ThinkingBlock({
    required this.steps,
    required this.isExpanded,
  });
  
  @override
  String get type => BlockType.thinking;
  
  @override
  List<Object?> get props => [steps, isExpanded];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'steps': steps.map((s) => s.toJson()).toList(),
    'isExpanded': isExpanded,
  };
  
  factory ThinkingBlock.fromJson(Map<String, dynamic> json) => ThinkingBlock(
    steps: (json['steps'] as List)
        .map((s) => ThinkingStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    isExpanded: json['isExpanded'] as bool,
  );
  
  ThinkingBlock copyWith({
    List<ThinkingStep>? steps,
    bool? isExpanded,
  }) => ThinkingBlock(
    steps: steps ?? this.steps,
    isExpanded: isExpanded ?? this.isExpanded,
  );
}

// ==================== 引用块 ====================

/// 引用项
/// Citation item
class Citation extends Equatable {
  final String type;      // 'setting' | 'chapter' | 'outline' | 'fragment'
  final int number;
  final String preview;
  
  const Citation({
    required this.type,
    required this.number,
    required this.preview,
  });
  
  @override
  List<Object?> get props => [type, number, preview];
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'number': number,
    'preview': preview,
  };
  
  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    type: json['type'] as String,
    number: json['number'] as int,
    preview: json['preview'] as String,
  );
}

/// 引用块
/// Citation block
class CitationBlock extends MessageBlock {
  final List<Citation> citations;
  
  const CitationBlock({required this.citations});
  
  @override
  String get type => BlockType.citation;
  
  @override
  List<Object?> get props => [citations];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'citations': citations.map((c) => c.toJson()).toList(),
  };
  
  factory CitationBlock.fromJson(Map<String, dynamic> json) => CitationBlock(
    citations: (json['citations'] as List)
        .map((c) => Citation.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
  
  CitationBlock copyWith({
    List<Citation>? citations,
  }) => CitationBlock(
    citations: citations ?? this.citations,
  );
}

// ==================== 工具批准块 ====================

/// 工具批准块
/// Tool approval block
class ToolApprovalBlock extends MessageBlock {
  final String toolName;
  final String operation;   // 'create' | 'update' | 'delete' | 'view'
  final String description;
  final ToolDetails? details;
  
  const ToolApprovalBlock({
    required this.toolName,
    required this.operation,
    required this.description,
    this.details,
  });
  
  @override
  String get type => BlockType.approval;
  
  @override
  List<Object?> get props => [toolName, operation, description, details];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'toolName': toolName,
    'operation': operation,
    'description': description,
    if (details != null) 'details': details!.toJson(),
  };
  
  factory ToolApprovalBlock.fromJson(Map<String, dynamic> json) => ToolApprovalBlock(
    toolName: json['toolName'] as String,
    operation: json['operation'] as String,
    description: json['description'] as String,
    details: json['details'] != null
        ? ToolDetails.fromJson(json['details'] as Map<String, dynamic>)
        : null,
  );
  
  ToolApprovalBlock copyWith({
    String? toolName,
    String? operation,
    String? description,
    ToolDetails? details,
  }) => ToolApprovalBlock(
    toolName: toolName ?? this.toolName,
    operation: operation ?? this.operation,
    description: description ?? this.description,
    details: details ?? this.details,
  );
}

// ==================== 任务分配块 ====================

/// 任务分配项
/// Task assignment item
class TaskAssignment extends Equatable {
  final String agentId;
  final String agentName;
  final String task;
  final String reason;
  
  const TaskAssignment({
    required this.agentId,
    required this.agentName,
    required this.task,
    required this.reason,
  });
  
  @override
  List<Object?> get props => [agentId, agentName, task, reason];
  
  Map<String, dynamic> toJson() => {
    'agentId': agentId,
    'agentName': agentName,
    'task': task,
    'reason': reason,
  };
  
  factory TaskAssignment.fromJson(Map<String, dynamic> json) => TaskAssignment(
    agentId: json['agentId'] as String,
    agentName: json['agentName'] as String,
    task: json['task'] as String,
    reason: json['reason'] as String,
  );
}

/// 任务分配块（主管智能体使用）
/// Task assignment block (used by supervisor agent)
class TaskAssignmentBlock extends MessageBlock {
  final String analysis;
  final List<TaskAssignment> assignments;
  final String mode;  // 'parallel' | 'sequential'
  
  const TaskAssignmentBlock({
    required this.analysis,
    required this.assignments,
    required this.mode,
  });
  
  @override
  String get type => BlockType.taskAssignment;
  
  @override
  List<Object?> get props => [analysis, assignments, mode];
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'analysis': analysis,
    'assignments': assignments.map((a) => a.toJson()).toList(),
    'mode': mode,
  };
  
  factory TaskAssignmentBlock.fromJson(Map<String, dynamic> json) => TaskAssignmentBlock(
    analysis: json['analysis'] as String,
    assignments: (json['assignments'] as List)
        .map((a) => TaskAssignment.fromJson(a as Map<String, dynamic>))
        .toList(),
    mode: json['mode'] as String,
  );
  
  TaskAssignmentBlock copyWith({
    String? analysis,
    List<TaskAssignment>? assignments,
    String? mode,
  }) => TaskAssignmentBlock(
    analysis: analysis ?? this.analysis,
    assignments: assignments ?? this.assignments,
    mode: mode ?? this.mode,
  );
}

// ==================== 工具摘要 ====================

/// 工具摘要项
/// Tool summary item
class ToolSummaryItem extends Equatable {
  final String toolName;
  final String toolType;   // 'view' | 'crud'
  final int? created;
  final int? updated;
  final int? deleted;
  final int? viewCount;
  
  const ToolSummaryItem({
    required this.toolName,
    required this.toolType,
    this.created,
    this.updated,
    this.deleted,
    this.viewCount,
  });
  
  @override
  List<Object?> get props => [
    toolName,
    toolType,
    created,
    updated,
    deleted,
    viewCount,
  ];
  
  Map<String, dynamic> toJson() => {
    'toolName': toolName,
    'toolType': toolType,
    if (created != null) 'created': created,
    if (updated != null) 'updated': updated,
    if (deleted != null) 'deleted': deleted,
    if (viewCount != null) 'viewCount': viewCount,
  };
  
  factory ToolSummaryItem.fromJson(Map<String, dynamic> json) => ToolSummaryItem(
    toolName: json['toolName'] as String,
    toolType: json['toolType'] as String,
    created: json['created'] as int?,
    updated: json['updated'] as int?,
    deleted: json['deleted'] as int?,
    viewCount: json['viewCount'] as int?,
  );
}





