import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service/repositories/setting_generation_repository.dart';
import '../../../utils/logger.dart';

/// 策略详情对话框
/// 显示策略的完整信息，支持隐私保护
class StrategyDetailDialog extends StatefulWidget {
  final String strategyId;
  final String strategyName;

  const StrategyDetailDialog({
    super.key,
    required this.strategyId,
    required this.strategyName,
  });

  @override
  State<StrategyDetailDialog> createState() => _StrategyDetailDialogState();
}

class _StrategyDetailDialogState extends State<StrategyDetailDialog> {
  static const String _tag = 'StrategyDetailDialog';
  
  late final SettingGenerationRepository _repository;
  Map<String, dynamic>? _strategyDetail;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SettingGenerationRepository>();
    _loadStrategyDetail();
  }

  Future<void> _loadStrategyDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await _repository.getStrategyDetail(strategyId: widget.strategyId);
      setState(() {
        _strategyDetail = detail;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error(_tag, '加载策略详情失败', e);
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    final isDark = theme.brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: screenSize.width < 600 ? screenSize.width * 0.95 : 
               screenSize.width < 900 ? 700 : 800,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14), // iOS风格圆角
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
              blurRadius: 40,
              offset: const Offset(0, 20),
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              Flexible(
                child: _buildBody(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // iOS风格图标
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF0A84FF), const Color(0xFF0066CC)]
                  : [const Color(0xFF007AFF), const Color(0xFF0051D5)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.description_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.strategyName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // iOS风格关闭按钮
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.close,
                size: 18,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadStrategyDetail,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_strategyDetail == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('策略详情不可用'),
        ),
      );
    }

    final hidePrompts = _strategyDetail!['hidePrompts'] as bool? ?? false;
    final description = _strategyDetail!['description'] as String? ?? '无描述';
    final systemPrompt = _strategyDetail!['systemPrompt'] as String?;
    final userPrompt = _strategyDetail!['userPrompt'] as String?;
    final isPublic = _strategyDetail!['isPublic'] as bool? ?? false;
    final rating = (_strategyDetail!['rating'] as num?)?.toDouble();
    final usageCount = _strategyDetail!['usageCount'] as int? ?? 0;
    final likeCount = _strategyDetail!['likeCount'] as int? ?? 0;

    final isDark = theme.brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // iOS风格紧凑的状态和统计信息
          Row(
            children: [
              // 状态标签
              if (isPublic)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_rounded, size: 13, color: const Color(0xFF34C759)),
                      const SizedBox(width: 5),
                      Text(
                        '公开',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF34C759),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isPublic && hidePrompts) const SizedBox(width: 8),
              if (hidePrompts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 13, color: const Color(0xFFFF9F0A)),
                      const SizedBox(width: 5),
                      Text(
                        '提示词已隐藏',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF9F0A),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              
              const Spacer(),
              
              // 紧凑的统计信息
              _buildCompactStat(theme, Icons.favorite, '$likeCount', const Color(0xFFFF3B30)),
              const SizedBox(width: 14),
              _buildCompactStat(theme, Icons.play_circle_outline, '$usageCount', isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)),
              if (rating != null && rating > 0) ...[
                const SizedBox(width: 14),
                _buildCompactStat(theme, Icons.star, rating.toStringAsFixed(1), const Color(0xFFFFCC00)),
              ],
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 描述 - iOS风格
          _buildSection(
            theme,
            title: '策略描述',
            icon: Icons.description_rounded,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                  width: 0.5,
                ),
              ),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 系统提示词
          _buildSection(
            theme,
            title: '系统提示词',
            subtitle: 'System Prompt',
            icon: Icons.settings_suggest_rounded,
            child: hidePrompts
                ? _buildHiddenPrompt(theme)
                : _buildPromptContent(theme, systemPrompt ?? '无'),
          ),
          
          const SizedBox(height: 24),
          
          // 用户提示词
          _buildSection(
            theme,
            title: '用户提示词',
            subtitle: 'User Prompt',
            icon: Icons.person_rounded,
            child: hidePrompts
                ? _buildHiddenPrompt(theme)
                : _buildPromptContent(theme, userPrompt ?? '无'),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // 紧凑的统计信息组件
  Widget _buildCompactStat(ThemeData theme, IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    ThemeData theme, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // iOS风格彩色图标
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getIconGradient(icon, isDark),
                ),
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: _getIconGradient(icon, isDark)[0].withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  // iOS风格图标渐变色
  List<Color> _getIconGradient(IconData icon, bool isDark) {
    if (icon == Icons.description_rounded) {
      return isDark 
        ? [const Color(0xFFFF9500), const Color(0xFFFF6B00)]
        : [const Color(0xFFFF9F0A), const Color(0xFFFF7A00)];
    } else if (icon == Icons.settings_suggest_rounded) {
      return isDark 
        ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
        : [const Color(0xFF5856D6), const Color(0xFF4947CC)];
    } else if (icon == Icons.person_rounded) {
      return isDark 
        ? [const Color(0xFF32ADE6), const Color(0xFF0A84FF)]
        : [const Color(0xFF30B0C7), const Color(0xFF007AFF)];
    }
    return isDark 
      ? [const Color(0xFF0A84FF), const Color(0xFF0066CC)]
      : [const Color(0xFF007AFF), const Color(0xFF0051D5)];
  }

  Widget _buildHiddenPrompt(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF3B30).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFFFF3B30), const Color(0xFFFF2D20)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '内容已隐藏',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF3B30),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '策略作者选择了隐藏提示词以保护创意',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptContent(ThemeData theme, String content) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // iOS风格头部工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 14,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                ),
                const SizedBox(width: 6),
                Text(
                  '提示词内容',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                // iOS风格复制按钮
                GestureDetector(
                  onTap: () => _copyToClipboard(content),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.content_copy_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '复制',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Container(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'Menlo', // iOS等宽字体
                fontSize: 13,
                height: 1.5,
                color: isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            const Text(
              '已复制到剪贴板',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF34C759), // iOS绿色
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}



