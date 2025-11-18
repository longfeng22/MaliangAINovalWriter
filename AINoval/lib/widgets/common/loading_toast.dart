import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 加载中提示状态
enum LoadingToastState {
  loading,   // 加载中（带轮转动画）
  success,   // 成功
  error,     // 错误
}

/// 可控制的加载提示组件
/// 支持显示加载中状态（带轮转动画），并可以手动切换到成功/失败状态
class LoadingToast {
  static OverlayEntry? _currentOverlay;
  static _LoadingToastController? _controller;
  
  /// 显示加载中提示
  /// 
  /// [context] - 上下文
  /// [message] - 提示消息，如"正在添加..."
  /// 返回一个控制器，可以用来更新状态或关闭提示
  static _LoadingToastController show(
    BuildContext context, {
    required String message,
  }) {
    // 如果有正在显示的toast，先移除它
    hide();
    
    final overlay = Overlay.of(context);
    
    _controller = _LoadingToastController();
    
    _currentOverlay = OverlayEntry(
      builder: (context) => _LoadingToastWidget(
        controller: _controller!,
        initialMessage: message,
      ),
    );
    
    overlay.insert(_currentOverlay!);
    
    return _controller!;
  }
  
  /// 隐藏当前显示的提示
  static void hide() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _controller = null;
  }
}

/// 加载提示控制器
/// 用于控制提示的状态和内容
class _LoadingToastController {
  final ValueNotifier<LoadingToastState> _stateNotifier = 
      ValueNotifier(LoadingToastState.loading);
  final ValueNotifier<String> _messageNotifier = ValueNotifier('');
  
  /// 更新消息文本
  void updateMessage(String message) {
    _messageNotifier.value = message;
  }
  
  /// 切换到成功状态，并在指定时间后自动关闭
  void success(String message, {Duration duration = const Duration(seconds: 2)}) {
    _messageNotifier.value = message;
    _stateNotifier.value = LoadingToastState.success;
    
    // 自动关闭
    Future.delayed(duration, () {
      LoadingToast.hide();
    });
  }
  
  /// 切换到错误状态，并在指定时间后自动关闭
  void error(String message, {Duration duration = const Duration(seconds: 3)}) {
    _messageNotifier.value = message;
    _stateNotifier.value = LoadingToastState.error;
    
    // 自动关闭
    Future.delayed(duration, () {
      LoadingToast.hide();
    });
  }
  
  /// 直接关闭提示
  void dismiss() {
    LoadingToast.hide();
  }
  
  void dispose() {
    _stateNotifier.dispose();
    _messageNotifier.dispose();
  }
}

/// 加载提示组件的内部实现
class _LoadingToastWidget extends StatefulWidget {
  const _LoadingToastWidget({
    required this.controller,
    required this.initialMessage,
  });
  
  final _LoadingToastController controller;
  final String initialMessage;
  
  @override
  State<_LoadingToastWidget> createState() => _LoadingToastWidgetState();
}

class _LoadingToastWidgetState extends State<_LoadingToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  
  @override
  void initState() {
    super.initState();
    
    widget.controller._messageNotifier.value = widget.initialMessage;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    // 开始动画
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  /// 获取状态对应的配置
  _ToastConfig _getConfig(LoadingToastState state, bool isDark) {
    switch (state) {
      case LoadingToastState.loading:
        return _ToastConfig(
          backgroundColor: isDark ? WebTheme.darkGrey100 : WebTheme.white,
          textColor: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
          borderColor: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
        );
      case LoadingToastState.success:
        return _ToastConfig(
          backgroundColor: WebTheme.success,
          textColor: Colors.white,
          borderColor: null,
        );
      case LoadingToastState.error:
        return _ToastConfig(
          backgroundColor: WebTheme.error,
          textColor: Colors.white,
          borderColor: null,
        );
    }
  }
  
  /// 根据状态获取图标
  Widget _buildIcon(LoadingToastState state, Color color) {
    switch (state) {
      case LoadingToastState.loading:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );
      case LoadingToastState.success:
        return Icon(
          Icons.check_circle_outline,
          size: 18,
          color: color,
        );
      case LoadingToastState.error:
        return Icon(
          Icons.error_outline,
          size: 18,
          color: color,
        );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Positioned(
          top: 20 + (_slideAnimation.value * 60), // 从顶部向下滑入
          left: 0,
          right: 0,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Center(
              child: ValueListenableBuilder<LoadingToastState>(
                valueListenable: widget.controller._stateNotifier,
                builder: (context, state, _) {
                  final config = _getConfig(state, isDark);
                  
                  return ValueListenableBuilder<String>(
                    valueListenable: widget.controller._messageNotifier,
                    builder: (context, message, _) {
                      return Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 400,
                            minWidth: 200,
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: config.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                offset: const Offset(0, 4),
                                blurRadius: 12,
                                spreadRadius: 0,
                              ),
                            ],
                            border: config.borderColor != null
                                ? Border.all(
                                    color: config.borderColor!,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildIcon(state, config.textColor),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  message,
                                  style: TextStyle(
                                    color: config.textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 提示配置类
class _ToastConfig {
  const _ToastConfig({
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
  });
  
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
}

