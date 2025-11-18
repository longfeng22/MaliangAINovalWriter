import 'package:flutter/material.dart';
import 'package:ainoval/models/context_drag_data.dart';

/// 上下文拖放目标包装组件
/// 
/// 将+Context按钮等组件包装为可接收拖放的目标区域
/// 支持扩展的拖放接受范围，提升用户体验
class ContextDropTarget extends StatefulWidget {
  /// 子组件（通常是+Context按钮）
  final Widget child;
  
  /// 接收拖放数据的回调
  final void Function(ContextDragData data) onAccept;
  
  /// 是否启用拖放目标（默认启用）
  final bool enabled;
  
  /// 拖放悬停时的边框颜色（可选，默认使用主题色）
  final Color? hoverBorderColor;
  
  /// 拖放悬停时的背景颜色（可选，默认使用主题色）
  final Color? hoverBackgroundColor;
  
  /// 扩展拖放接受范围（像素）
  /// 默认在四周各扩展24px，让用户更容易拖放
  final EdgeInsets hitTestPadding;
  
  const ContextDropTarget({
    super.key,
    required this.child,
    required this.onAccept,
    this.enabled = true,
    this.hoverBorderColor,
    this.hoverBackgroundColor,
    this.hitTestPadding = const EdgeInsets.all(24), // 🎯 默认扩展24px
  });
  
  @override
  State<ContextDropTarget> createState() => _ContextDropTargetState();
}

class _ContextDropTargetState extends State<ContextDropTarget>
    with SingleTickerProviderStateMixin {
  bool _isHovering = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    
    // 确定悬停时的颜色
    final hoverBorderColor = widget.hoverBorderColor ?? colorScheme.primary;
    final hoverBackgroundColor = widget.hoverBackgroundColor ?? 
        colorScheme.primary.withOpacity(0.1);
    
    // 🎯 使用Stack扩展拖放接受范围
    // 底层是透明的扩展区域，上层是实际按钮
    return DragTarget<ContextDragData>(
      hitTestBehavior: HitTestBehavior.translucent,
      // 悬停进入
      onWillAcceptWithDetails: (details) {
        if (!_isHovering) {
          setState(() => _isHovering = true);
          _animationController.forward();
        }
        return true;
      },
      // 悬停离开
      onLeave: (_) {
        if (_isHovering) {
          setState(() => _isHovering = false);
          _animationController.reverse();
        }
      },
      // 接收拖放数据
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        _animationController.reverse();
        widget.onAccept(details.data);
      },
      // 构建UI
      builder: (context, candidateData, rejectedData) {
        return AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            // 🎯 使用Container添加padding来扩展接受范围
            return Container(
              // 添加padding扩展拖放接受区域
              padding: widget.hitTestPadding,
              // 透明色，不影响布局但可以接收事件
              color: Colors.transparent,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: _isHovering
                        ? Border.all(
                            color: hoverBorderColor,
                            width: 2,
                          )
                        : null,
                    color: _isHovering ? hoverBackgroundColor : null,
                    boxShadow: _isHovering
                        ? [
                            BoxShadow(
                              color: hoverBorderColor.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: widget.child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 快捷方法扩展
extension ContextDropTargetExtension on Widget {
  /// 将Widget包装为可接收拖放的目标
  Widget makeDropTarget({
    required void Function(ContextDragData data) onAccept,
    bool enabled = true,
    Color? hoverBorderColor,
    Color? hoverBackgroundColor,
    EdgeInsets hitTestPadding = const EdgeInsets.all(24), // 🎯 支持自定义扩展范围
  }) {
    return ContextDropTarget(
      onAccept: onAccept,
      enabled: enabled,
      hoverBorderColor: hoverBorderColor,
      hoverBackgroundColor: hoverBackgroundColor,
      hitTestPadding: hitTestPadding,
      child: this,
    );
  }
}

