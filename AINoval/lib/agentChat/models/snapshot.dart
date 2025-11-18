/// 快照模型（用于时间旅行/回退）
/// Snapshot model (for time travel/rollback)

import 'package:equatable/equatable.dart';
import '../config/constants.dart';

/// 快照模型
/// Snapshot model
class Snapshot extends Equatable {
  final String id;
  final int timestamp;
  final String label;
  final String? description;
  final String type;  // 'message' | 'tool' | 'approval' | 'system'
  
  const Snapshot({
    required this.id,
    required this.timestamp,
    required this.label,
    this.description,
    required this.type,
  });
  
  @override
  List<Object?> get props => [id, timestamp, label, description, type];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp,
    'label': label,
    if (description != null) 'description': description,
    'type': type,
  };
  
  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
    id: json['id'] as String,
    timestamp: json['timestamp'] as int,
    label: json['label'] as String,
    description: json['description'] as String?,
    type: json['type'] as String,
  );
  
  Snapshot copyWith({
    String? id,
    int? timestamp,
    String? label,
    String? description,
    String? type,
  }) => Snapshot(
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    label: label ?? this.label,
    description: description ?? this.description,
    type: type ?? this.type,
  );
  
  /// 是否是消息快照
  bool get isMessage => type == SnapshotType.message;
  
  /// 是否是工具快照
  bool get isTool => type == SnapshotType.tool;
  
  /// 是否是批准快照
  bool get isApproval => type == SnapshotType.approval;
  
  /// 是否是系统快照
  bool get isSystem => type == SnapshotType.system;
  
  /// 格式化时间
  String get formattedTime {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  
  /// 格式化日期时间
  String get formattedDateTime {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}





