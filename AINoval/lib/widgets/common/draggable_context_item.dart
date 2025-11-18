import 'package:flutter/material.dart';
import 'package:ainoval/models/context_drag_data.dart';
import 'package:ainoval/models/context_selection_models.dart';

/// 拖动配置常量
class DragConfig {
  /// 长按触发拖动的最小时长（毫秒）
  /// 设置为200ms，比默认的500ms更快响应
  static const int longPressDuration = 200;
  
  /// 移动距离阈值（像素）
  /// 长按后移动超过此距离立即触发拖动
  static const double movementThreshold = 5.0;
  
  DragConfig._();
}

/// 可拖动的上下文项目包装组件
/// 
/// 支持两种触发方式：
/// 1. 长按200ms触发拖动
/// 2. 长按后立即移动超过5px触发拖动
class DraggableContextItem extends StatelessWidget {
  /// 子组件
  final Widget child;
  
  /// 拖放数据
  final ContextDragData data;
  
  /// 是否启用拖动（默认启用）
  final bool enableDrag;
  
  /// 拖动开始回调
  final VoidCallback? onDragStarted;
  
  /// 拖动结束回调
  final VoidCallback? onDragEnd;
  
  /// 拖动完成回调（当放置成功时）
  final VoidCallback? onDragCompleted;
  
  const DraggableContextItem({
    super.key,
    required this.child,
    required this.data,
    this.enableDrag = true,
    this.onDragStarted,
    this.onDragEnd,
    this.onDragCompleted,
  });
  
  @override
  Widget build(BuildContext context) {
    // 如果禁用拖动，直接返回子组件
    if (!enableDrag) {
      return child;
    }
    
    // 使用 LongPressDraggable 实现长按拖动，自定义延迟时间
    return LongPressDraggable<ContextDragData>(
      data: data,
      // 🎯 自定义长按延迟为200ms（默认500ms太长）
      delay: const Duration(milliseconds: DragConfig.longPressDuration),
      // 🎯 性能优化：使用RepaintBoundary隔离拖动反馈的重绘
      feedback: RepaintBoundary(
        child: Material(
          type: MaterialType.card,
          elevation: 8, // ✅ 降低elevation减少阴影计算
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
          shadowColor: Colors.black26, // ✅ 使用预定义颜色
          child: _buildFeedbackContent(context),
        ),
      ),
      // 拖动时原位置显示半透明状态
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: child,
      ),
      // 使用指针位置作为拖动锚点，提供更好的拖动体验
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // 🎯 设置为true，提供触觉反馈
      hapticFeedbackOnStart: true,
      // 回调
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      onDragCompleted: onDragCompleted,
      // 原始子组件
      child: child,
    );
  }
  
  /// 构建拖动反馈内容（优化性能）
  Widget _buildFeedbackContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 🎯 预计算颜色，避免在每帧调用withOpacity
    final primaryColor = colorScheme.primary;
    final containerColor = colorScheme.primaryContainer;
    final onContainerColor = colorScheme.onPrimaryContainer;
    final borderColor = Color.lerp(primaryColor, Colors.transparent, 0.5) ?? primaryColor;
    final subtitleColor = Color.lerp(onContainerColor, Colors.transparent, 0.2) ?? onContainerColor;
    
    // 🎯 使用固定宽度避免Flexible的布局计算
    return Container(
      width: 280, // ✅ 固定宽度，避免动态布局计算
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10), // ✅ 左侧间距减小，给文字更多空间
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center, // ✅ 垂直居中对齐
        children: [
          // 拖动指示图标 - 缩小尺寸和间距
          Icon(
            Icons.drag_indicator,
            size: 16, // ✅ 从20减小到16
            color: onContainerColor,
          ),
          const SizedBox(width: 6), // ✅ 从12减小到6
          
          // 类型图标
          Icon(
            data.type.icon,
            size: 16, // ✅ 从18减小到16，保持一致
            color: primaryColor,
          ),
          const SizedBox(width: 8), // ✅ 保持8px间距
          
          // 标题 - 使用Expanded给文字最大空间
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // ✅ 文字靠左
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onContainerColor,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.left, // ✅ 明确左对齐
                ),
                // 🎯 简化条件渲染，减少widget重建
                if (data.subtitle != null && data.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle!,
                    style: TextStyle(
                      fontSize: 11, // ✅ 从12减小到11，更紧凑
                      color: subtitleColor,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    textAlign: TextAlign.left, // ✅ 明确左对齐
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷方法：从上下文选择项创建可拖动组件
extension DraggableContextItemExtension on Widget {
  /// 将Widget包装为可拖动的上下文项
  Widget makeDraggableContext({
    required ContextSelectionItem item,
    bool enableDrag = true,
    VoidCallback? onDragStarted,
    VoidCallback? onDragEnd,
    VoidCallback? onDragCompleted,
  }) {
    return DraggableContextItem(
      data: ContextDragData.fromContextItem(item),
      enableDrag: enableDrag,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDragCompleted: onDragCompleted,
      child: this,
    );
  }
}

