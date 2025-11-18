import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 全屏加载动画覆盖层 - 神笔马良阴阳太极风格
/// 在应用初始化、卷轴切换等耗时操作时显示
class FullscreenLoadingOverlay extends StatefulWidget {
  final String loadingMessage;
  final bool showProgressIndicator;
  final double progress; // 0.0 - 1.0 的进度值，如果提供将显示进度条而非无限循环指示器
  final Color? backgroundColor;
  final Color textColor;
  final bool useBlur; // 是否使用背景模糊效果
  final bool isVisible;

  const FullscreenLoadingOverlay({
    Key? key,
    this.loadingMessage = '正在加载，请稍候...',
    this.showProgressIndicator = true,
    this.progress = -1, // 默认为-1，表示不确定进度
    this.backgroundColor,
    this.textColor = const Color(0xFF4a5568),
    this.useBlur = false,
    this.isVisible = true,
  }) : super(key: key);

  @override
  State<FullscreenLoadingOverlay> createState() => _FullscreenLoadingOverlayState();
}

class _FullscreenLoadingOverlayState extends State<FullscreenLoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _taichiController;
  late AnimationController _breatheController;
  late AnimationController _inkController;

  @override
  void initState() {
    super.initState();
    
    // 太极旋转动画
    _taichiController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    // 图标呼吸动画
    _breatheController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    // 墨滴动画
    _inkController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _taichiController.dispose();
    _breatheController.dispose();
    _inkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          // 动态背景：暗黑用纯黑，亮色用白；允许外部覆盖
          color: widget.backgroundColor ?? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF000000) : Colors.white),
          child: Stack(
            children: [
              // 阴阳太极背景图案
              _buildTaichiBackground(),
              // 主要内容
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 标题
                    const Text(
                      '马良 AI 小说助手',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2d3748),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '神笔在手，妙笔生花',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF718096),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 50),
                    // 神笔太极图标
                    if (widget.showProgressIndicator)
                      AnimatedBuilder(
                        animation: _breatheController,
                        builder: (context, child) {
                          final breatheScale = 1.0 + (_breatheController.value * 0.05);
                          return Transform.scale(
                            scale: breatheScale,
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: _buildTaichiIcon(),
                            ),
                          );
                        },
                      ),
                    if (widget.showProgressIndicator && 
                        (widget.loadingMessage.isNotEmpty || widget.progress > 0))
                      const SizedBox(height: 30),
                    // 加载文字
                    if (widget.loadingMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          widget.loadingMessage,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: widget.textColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    // 进度条
                    if (widget.progress >= 0 && widget.progress <= 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _buildInkProgressBar(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建太极背景图案
  Widget _buildTaichiBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _taichiController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _taichiController.value * 2 * math.pi * 0.05, // 缓慢旋转
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF000000) : Colors.white,
              ),
              child: CustomPaint(
                painter: TaichiBackgroundPainter(_taichiController.value),
                size: Size.infinite,
              ),
            ),
          );
        },
      ),
    );
  }

  // 构建太极神笔图标
  Widget _buildTaichiIcon() {
    return AnimatedBuilder(
      animation: _taichiController,
      builder: (context, child) {
        return CustomPaint(
          painter: TaichiIconPainter(
            _taichiController.value,
            _inkController.value,
          ),
          size: const Size(140, 140),
        );
      },
    );
  }

  // 构建墨色进度条
  Widget _buildInkProgressBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度容器
        Container(
          width: 320,
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFFe2e8f0).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Stack(
            children: [
              // 进度条主体
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 320 * widget.progress,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2C2C2C),
                      Color(0xFF000000), 
                      Color(0xFF4A4A4A),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.6),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 太极背景画师
class TaichiBackgroundPainter extends CustomPainter {
  final double animation;

  TaichiBackgroundPainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    // 绘制非常淡的太极图案作为背景装饰
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.15;

    // 黑色圆形图案
    paint.color = Colors.black.withOpacity(0.01);
    canvas.drawCircle(
      Offset(centerX - 200, centerY - 150), 
      radius, 
      paint,
    );

    // 白色圆形图案  
    paint.color = Colors.grey.withOpacity(0.005);
    canvas.drawCircle(
      Offset(centerX + 180, centerY + 120), 
      radius * 0.8, 
      paint,
    );

    // 墨点图案
    paint.color = Colors.black.withOpacity(0.03);
    for (int i = 0; i < 20; i++) {
      final angle = (i / 20) * 2 * math.pi + animation * 0.2;
      final x = centerX + math.cos(angle) * (300 + i * 20);
      final y = centerY + math.sin(angle) * (200 + i * 15);
      canvas.drawCircle(Offset(x, y), 1 + (i % 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 太极神笔图标画师  
class TaichiIconPainter extends CustomPainter {
  final double taichiAnimation;
  final double inkAnimation;

  TaichiIconPainter(this.taichiAnimation, this.inkAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.3;

    // 保存画布状态
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(taichiAnimation * 2 * math.pi);

    // 绘制太极图
    _drawTaichiSymbol(canvas, paint, radius);

    // 恢复画布状态
    canvas.restore();

    // 绘制中央神笔（不旋转）
    _drawCentralBrush(canvas, paint, center, size);

    // 绘制飘散的墨滴
    _drawFloatingInk(canvas, paint, center, size);
  }

  void _drawTaichiSymbol(Canvas canvas, Paint paint, double radius) {
    // 太极外圈
    paint
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset.zero, radius + 2, paint);

    // 阴阳主体  
    paint.style = PaintingStyle.fill;
    
    // 黑色半圆
    paint.color = Colors.black.withOpacity(0.4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      0,
      math.pi,
      true,
      paint,
    );
    
    // 白色半圆
    paint.color = Colors.white.withOpacity(0.7);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      math.pi,
      math.pi,
      true,
      paint,
    );
    
    // 阴阳鱼
    paint.color = Colors.black.withOpacity(0.4);
    canvas.drawCircle(Offset(0, -radius / 2), radius / 2, paint);
    
    paint.color = Colors.white.withOpacity(0.7);  
    canvas.drawCircle(Offset(0, radius / 2), radius / 2, paint);
    
    // 阴阳眼
    paint.color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(Offset(0, -radius / 2), radius / 6, paint);
    
    paint.color = Colors.black.withOpacity(0.9);
    canvas.drawCircle(Offset(0, radius / 2), radius / 6, paint);
  }

  void _drawCentralBrush(Canvas canvas, Paint paint, Offset center, Size size) {
    // 笔杆阴影
    paint.color = Colors.black.withOpacity(0.3);
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx + 1, center.dy + 1),
        width: 5,
        height: 35,
      ),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(shadowRect, paint);

    // 笔杆主体
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.grey[600]!,
        Colors.grey[800]!,
        Colors.black,
        Colors.grey[700]!,
      ],
    ).createShader(Rect.fromCenter(
      center: center,
      width: 5,
      height: 35,
    ));
    
    final brushRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 5, height: 35),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(brushRect, paint);

    // 笔头金属环
    paint.shader = LinearGradient(
      colors: [
        Colors.grey[400]!,
        Colors.grey[600]!,
        Colors.grey[800]!,
      ],
    ).createShader(Rect.fromCenter(
      center: Offset(center.dx, center.dy + 10),
      width: 4,
      height: 4,
    ));
    
    final metalRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 10),
        width: 4,
        height: 4,
      ),
      const Radius.circular(0.5),
    );
    canvas.drawRRect(metalRect, paint);

    // 笔毛
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.grey[600]!,
        Colors.grey[800]!,
        Colors.black,
      ],
    ).createShader(Rect.fromCenter(
      center: Offset(center.dx, center.dy + 18),
      width: 3.6,
      height: 10,
    ));
    
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 18),
        width: 3.6,
        height: 10,
      ),
      paint,
    );
  }

  void _drawFloatingInk(Canvas canvas, Paint paint, Offset center, Size size) {
    paint.shader = null;
    paint.color = Colors.black.withOpacity(0.4);
    
    // 飘散的墨滴
    final inkPositions = [
      Offset(center.dx - 40, center.dy - 30),
      Offset(center.dx + 45, center.dy - 25),
      Offset(center.dx - 25, center.dy + 40),
    ];
    
    for (int i = 0; i < inkPositions.length; i++) {
      final offset = math.sin(inkAnimation * 2 * math.pi + i) * 5;
      final pos = Offset(
        inkPositions[i].dx,
        inkPositions[i].dy + offset,
      );
      canvas.drawCircle(pos, 1 + i * 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
} 