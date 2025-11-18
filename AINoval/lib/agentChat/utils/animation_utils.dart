/// 动画工具类
/// Animation utility class

import 'package:flutter/material.dart';
import '../config/theme_config.dart';

/// 动画工具
/// Animation utility
class AnimationUtils {
  /// 消息入场动画
  /// Message entrance animation (slide-up + fade)
  static SlideTransition slideUpFadeIn(
    Animation<double> animation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      )),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
  
  /// 脉冲动画（用于思考指示器）
  /// Pulse animation (for thinking indicator)
  static Widget pulsingWidget({
    required Widget child,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    return _PulsingWidget(
      duration: duration,
      child: child,
    );
  }
  
  /// 展开/折叠动画
  /// Expand/collapse animation
  static Widget expandCollapse({
    required Widget child,
    required bool isExpanded,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) {
    return AnimatedSize(
      duration: duration,
      curve: curve,
      child: isExpanded ? child : const SizedBox.shrink(),
    );
  }
  
  /// 渐变过渡
  /// Fade transition
  static Widget fadeTransition({
    required Widget child,
    required bool visible,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: duration,
      child: child,
    );
  }
  
  /// 缩放动画
  /// Scale animation
  static Widget scaleTransition({
    required Widget child,
    required bool visible,
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeOut,
  }) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
  
  /// 旋转动画
  /// Rotation animation
  static Widget rotationTransition({
    required Widget child,
    required bool rotated,
    Duration duration = const Duration(milliseconds: 200),
    double turns = 0.5, // 180度
  }) {
    return AnimatedRotation(
      turns: rotated ? turns : 0,
      duration: duration,
      child: child,
    );
  }
  
  /// 滑动过渡
  /// Slide transition
  static Widget slideTransition({
    required Widget child,
    required bool visible,
    Offset beginOffset = const Offset(1, 0), // 从右侧滑入
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : beginOffset,
      duration: duration,
      child: child,
    );
  }
  
  /// 悬停效果（亮度变化）
  /// Hover effect (brightness change)
  static Widget hoverBrightness({
    required Widget child,
    required bool isHovered,
    double brightness = 1.1,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      foregroundDecoration: BoxDecoration(
        color: isHovered 
            ? Colors.white.withOpacity(0.05)
            : Colors.transparent,
      ),
      child: child,
    );
  }
  
  /// 按钮按下效果（缩放）
  /// Button press effect (scale)
  static Widget pressEffect({
    required Widget child,
    required bool isPressed,
    double scale = 0.95,
  }) {
    return AnimatedScale(
      scale: isPressed ? scale : 1.0,
      duration: const Duration(milliseconds: 100),
      child: child,
    );
  }
  
  /// 加载指示器（旋转动画）
  /// Loading indicator (rotation animation)
  static Widget loadingIndicator({
    double size = 24,
    Color? color,
  }) {
    return _RotatingWidget(
      duration: const Duration(seconds: 1),
      child: Icon(
        Icons.refresh,
        size: size,
        color: color,
      ),
    );
  }
  
  /// 思考指示器（脉冲 + 轨道动画）
  /// Thinking indicator (pulse + orbital animation)
  static Widget thinkingIndicator({
    double size = 32,
    Color? color,
  }) {
    return _ThinkingIndicatorWidget(
      size: size,
      color: color,
    );
  }
  
  /// 抖动动画（错误提示）
  /// Shake animation (for error indication)
  static Widget shakeOnError({
    required Widget child,
    required bool hasError,
  }) {
    return _ShakeWidget(
      shouldShake: hasError,
      child: child,
    );
  }
}

// ==================== 内部Widget ====================

/// 脉冲Widget
class _PulsingWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  
  const _PulsingWidget({
    required this.child,
    required this.duration,
  });
  
  @override
  State<_PulsingWidget> createState() => _PulsingWidgetState();
}

class _PulsingWidgetState extends State<_PulsingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: ScaleTransition(
        scale: _animation,
        child: widget.child,
      ),
    );
  }
}

/// 旋转Widget
class _RotatingWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  
  const _RotatingWidget({
    required this.child,
    required this.duration,
  });
  
  @override
  State<_RotatingWidget> createState() => _RotatingWidgetState();
}

class _RotatingWidgetState extends State<_RotatingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: widget.child,
    );
  }
}

/// 思考指示器Widget
class _ThinkingIndicatorWidget extends StatefulWidget {
  final double size;
  final Color? color;
  
  const _ThinkingIndicatorWidget({
    required this.size,
    this.color,
  });
  
  @override
  State<_ThinkingIndicatorWidget> createState() => _ThinkingIndicatorWidgetState();
}

class _ThinkingIndicatorWidgetState extends State<_ThinkingIndicatorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AgentChatThemeConfig.thinkingPulseDuration,
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? 
        AgentChatThemeConfig.thinkingStateBg.toColor();
    
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外圈轨道动画
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: 1 + (_controller.value * 0.3),
                child: Opacity(
                  opacity: 1 - _controller.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // 中心点
          Container(
            width: widget.size * 0.3,
            height: widget.size * 0.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 抖动Widget
class _ShakeWidget extends StatefulWidget {
  final Widget child;
  final bool shouldShake;
  
  const _ShakeWidget({
    required this.child,
    required this.shouldShake,
  });
  
  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _animation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticIn),
    );
  }
  
  @override
  void didUpdateWidget(_ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldShake && !oldWidget.shouldShake) {
      _controller.forward(from: 0);
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}





