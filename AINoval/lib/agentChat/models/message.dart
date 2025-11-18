/// 消息模型
/// Message model

import 'package:equatable/equatable.dart';
import 'message_block.dart';
import '../config/constants.dart';

/// 消息模型
/// Message model
class Message extends Equatable {
  final String id;
  final String role;            // 'user' | 'assistant' | 'supervisor'
  final String? agentId;        // 回答的智能体ID（assistant消息使用）
  final String? agentName;      // 回答的智能体名称（assistant消息使用）
  final List<MessageBlock> blocks;
  final List<ToolSummaryItem>? toolSummary;
  final String? timestamp;
  
  const Message({
    required this.id,
    required this.role,
    this.agentId,
    this.agentName,
    required this.blocks,
    this.toolSummary,
    this.timestamp,
  });
  
  @override
  List<Object?> get props => [
    id,
    role,
    agentId,
    agentName,
    blocks,
    toolSummary,
    timestamp,
  ];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    if (agentId != null) 'agentId': agentId,
    if (agentName != null) 'agentName': agentName,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (toolSummary != null)
      'toolSummary': toolSummary!.map((t) => t.toJson()).toList(),
    if (timestamp != null) 'timestamp': timestamp,
  };
  
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    role: json['role'] as String,
    agentId: json['agentId'] as String?,
    agentName: json['agentName'] as String?,
    blocks: (json['blocks'] as List)
        .map((b) => MessageBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
    toolSummary: json['toolSummary'] != null
        ? (json['toolSummary'] as List)
            .map((t) => ToolSummaryItem.fromJson(t as Map<String, dynamic>))
            .toList()
        : null,
    timestamp: json['timestamp'] as String?,
  );
  
  Message copyWith({
    String? id,
    String? role,
    String? agentId,
    String? agentName,
    List<MessageBlock>? blocks,
    List<ToolSummaryItem>? toolSummary,
    String? timestamp,
  }) => Message(
    id: id ?? this.id,
    role: role ?? this.role,
    agentId: agentId ?? this.agentId,
    agentName: agentName ?? this.agentName,
    blocks: blocks ?? this.blocks,
    toolSummary: toolSummary ?? this.toolSummary,
    timestamp: timestamp ?? this.timestamp,
  );
  
  /// 是否是用户消息
  bool get isUser => role == MessageRole.user;
  
  /// 是否是AI消息
  bool get isAssistant => role == MessageRole.assistant;
  
  /// 是否是主管消息
  bool get isSupervisor => role == MessageRole.supervisor;
  
  /// 获取所有文本内容
  String get allText {
    return blocks
        .whereType<TextBlock>()
        .map((b) => b.content)
        .join('\n');
  }
  
  /// 获取所有工具块
  List<ToolBlock> get toolBlocks {
    return blocks.whereType<ToolBlock>().toList();
  }
  
  /// 获取所有批准块
  List<ToolApprovalBlock> get approvalBlocks {
    return blocks.whereType<ToolApprovalBlock>().toList();
  }
  
  /// 是否有待批准的工具
  bool get hasPendingApproval {
    return approvalBlocks.isNotEmpty;
  }
}





