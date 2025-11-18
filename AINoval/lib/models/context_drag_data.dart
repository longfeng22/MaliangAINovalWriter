import 'package:ainoval/models/context_selection_models.dart';

/// 上下文拖放数据模型
/// 
/// 用于在拖放操作中传递上下文项目信息
class ContextDragData {
  /// 唯一标识符
  final String id;
  
  /// 上下文项目类型
  final ContextSelectionType type;
  
  /// 显示标题
  final String title;
  
  /// 副标题（可选）
  final String? subtitle;
  
  /// 元数据（可选）
  final Map<String, dynamic>? metadata;
  
  /// 构造函数
  const ContextDragData({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.metadata,
  });
  
  /// 从上下文选择项创建拖放数据
  factory ContextDragData.fromContextItem(ContextSelectionItem item) {
    return ContextDragData(
      id: item.id,
      type: item.type,
      title: item.title,
      subtitle: item.displaySubtitle.isNotEmpty ? item.displaySubtitle : null,
      metadata: item.metadata.isNotEmpty ? item.metadata : null,
    );
  }
  
  @override
  String toString() {
    return 'ContextDragData(id: $id, type: $type, title: $title)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContextDragData &&
        other.id == id &&
        other.type == type &&
        other.title == title;
  }
  
  @override
  int get hashCode => Object.hash(id, type, title);
}


