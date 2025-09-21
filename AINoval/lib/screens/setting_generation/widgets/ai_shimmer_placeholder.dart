import 'dart:async';
import 'package:flutter/material.dart';

/// 现代化AI设计的模糊占位组件
class AIShimmerPlaceholder extends StatefulWidget {
  const AIShimmerPlaceholder({Key? key}) : super(key: key);

  @override
  State<AIShimmerPlaceholder> createState() => _AIShimmerPlaceholderState();
}

class _AIShimmerPlaceholderState extends State<AIShimmerPlaceholder>
    with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _pulseAnimation;
  
  String _currentMessage = 'AI 正在构思设定架构...';
  late Timer _messageTimer;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // 首帧后再启动动画，避免在构建/热重启过程中驱动渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shimmerController.repeat();
      _pulseController.repeat(reverse: true);
      // 定期更换提示消息
      _messageTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
        if (mounted) {
          setState(() {
            _currentMessage = _getRandomMessage();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    if (_shimmerController.isAnimating) {
      _shimmerController.stop();
    }
    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    _shimmerController.dispose();
    _pulseController.dispose();
    _messageTimer.cancel();
    super.dispose();
  }

  String _getRandomMessage() {
    final messages = [
      'AI 正在构思设定架构...',
      '正在分析故事背景...',
      '构建世界观体系中...',
      '生成角色关系网络...',
      '设计情节主线框架...',
      '创造独特的设定元素...',
    ];
    return messages[DateTime.now().millisecond % messages.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1F2937).withOpacity(0.3) 
            : const Color(0xFFF9FAFB).withOpacity(0.3),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF374151) 
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI思考状态指示器
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(_pulseAnimation.value),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: Text(
                        _currentMessage,
                        key: ValueKey(_currentMessage),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          // 模糊的节点占位符
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(8, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildShimmerNode(
                      context,
                      level: index < 3 ? 0 : (index < 6 ? 1 : 2),
                      delay: index * 200.0,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerNode(BuildContext context, {required int level, required double delay}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leftPadding = level * 24.0 + 8.0;
    
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          margin: EdgeInsets.only(left: leftPadding),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)).withOpacity(0.3),
                (isDark ? const Color(0xFF4B5563) : const Color(0xFFF3F4F6)).withOpacity(0.6),
                (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)).withOpacity(0.3),
              ],
              stops: [
                (_shimmerAnimation.value - 1).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 1).clamp(0.0, 1.0),
              ],
            ),
          ),
          child: Row(
            children: [
              // 图标占位符
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)).withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 12),
              // 文字占位符
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)).withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 12,
                      width: MediaQuery.of(context).size.width * 0.6,
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)).withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 现代化的AI加载指示器
class AILoadingIndicator extends StatefulWidget {
  final String message;
  
  const AILoadingIndicator({
    Key? key,
    this.message = 'AI正在处理...',
  }) : super(key: key);

  @override
  State<AILoadingIndicator> createState() => _AILoadingIndicatorState();
}

class _AILoadingIndicatorState extends State<AILoadingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            widget.message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}