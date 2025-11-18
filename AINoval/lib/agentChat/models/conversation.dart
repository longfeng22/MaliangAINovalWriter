/// 对话模型
/// Conversation model

import 'package:equatable/equatable.dart';
import 'message.dart';
import 'snapshot.dart';

/// 对话模型
/// Conversation model
class Conversation extends Equatable {
  final String id;
  final String title;
  final List<Message> messages;
  final List<Snapshot> snapshots;
  
  const Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.snapshots,
  });
  
  @override
  List<Object?> get props => [id, title, messages, snapshots];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'snapshots': snapshots.map((s) => s.toJson()).toList(),
  };
  
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String,
    messages: (json['messages'] as List)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList(),
    snapshots: (json['snapshots'] as List)
        .map((s) => Snapshot.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
  
  Conversation copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    List<Snapshot>? snapshots,
  }) => Conversation(
    id: id ?? this.id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    snapshots: snapshots ?? this.snapshots,
  );
  
  /// 是否为空对话
  bool get isEmpty => messages.isEmpty;
  
  /// 是否有消息
  bool get hasMessages => messages.isNotEmpty;
  
  /// 消息数量
  int get messageCount => messages.length;
  
  /// 快照数量
  int get snapshotCount => snapshots.length;
  
  /// 最后一条消息
  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;
  
  /// 最后一个快照
  Snapshot? get lastSnapshot => snapshots.isNotEmpty ? snapshots.last : null;
  
  /// 获取快照索引
  int getSnapshotIndex(String snapshotId) {
    return snapshots.indexWhere((s) => s.id == snapshotId);
  }
  
  /// 回退到指定快照
  Conversation rollbackToSnapshot(String snapshotId) {
    final snapshotIndex = getSnapshotIndex(snapshotId);
    if (snapshotIndex == -1) return this;
    
    // 保留到该快照为止的快照
    final newSnapshots = snapshots.sublist(0, snapshotIndex + 1);
    
    // 计算该快照对应的消息数量（简化处理：每两个快照对应一条消息）
    final messageCount = (snapshotIndex / 2).floor();
    final newMessages = messages.sublist(0, messageCount);
    
    return copyWith(
      messages: newMessages,
      snapshots: newSnapshots,
    );
  }
}





