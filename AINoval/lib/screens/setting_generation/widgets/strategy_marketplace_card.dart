import 'package:flutter/material.dart';
import '../../../models/admin/review_models.dart';

/// 策略市场卡片组件
/// 精美的策略展示卡片，支持点赞、收藏等交互
class StrategyMarketplaceCard extends StatefulWidget {
  final Map<String, dynamic> strategy;
  final VoidCallback? onLike;
  final VoidCallback? onFavorite;
  final VoidCallback? onUse;
  final VoidCallback? onCopy; // 🆕 复制为我的策略
  final VoidCallback? onTap; // 🆕 点击卡片查看详情
  final VoidCallback? onEdit; // 🆕 编辑策略
  final VoidCallback? onDelete; // 🆕 删除策略
  final VoidCallback? onShare; // 🆕 分享/提交审核
  final bool isMyStrategy; // 🆕 是否是我的策略

  const StrategyMarketplaceCard({
    super.key,
    required this.strategy,
    this.onLike,
    this.onFavorite,
    this.onUse,
    this.onCopy,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onShare,
    this.isMyStrategy = false,
  });

  @override
  State<StrategyMarketplaceCard> createState() => _StrategyMarketplaceCardState();
}

class _StrategyMarketplaceCardState extends State<StrategyMarketplaceCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final name = widget.strategy['name'] as String? ?? '未命名策略';
    final description = widget.strategy['description'] as String? ?? '';
    final likeCount = widget.strategy['likeCount'] as int? ?? 0;
    final favoriteCount = widget.strategy['favoriteCount'] as int? ?? 0;
    final usageCount = widget.strategy['usageCount'] as int? ?? 0;
    final isLiked = widget.strategy['isLiked'] as bool? ?? false;
    final isFavorite = widget.strategy['isFavorite'] as bool? ?? false;
    final rating = (widget.strategy['rating'] as num?)?.toDouble();
    final hidePrompts = widget.strategy['hidePrompts'] as bool? ?? false;
    final tags = (widget.strategy['tags'] as List?)?.cast<String>() ?? <String>[];
    final reviewStatus = widget.strategy['reviewStatus'] as String? ?? 'DRAFT'; // 审核状态
    
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: widget.onTap, // 🆕 点击卡片查看详情
          child: Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white,
              borderRadius: BorderRadius.circular(12), // iOS风格圆角
              border: Border.all(
                color: _isHovering
                    ? (theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.5)
                    : (theme.brightness == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6)),
                width: _isHovering ? 1.5 : 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHovering ? 0.15 : 0.05),
                  blurRadius: _isHovering ? 15 : 5,
                  offset: Offset(0, _isHovering ? 6 : 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                
                // 内容 - iOS风格
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部：标题、审核状态和隐私标志
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                                letterSpacing: -0.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 🆕 审核状态标签（仅在"我的"tab显示）
                          if (widget.isMyStrategy) ...[
                            const SizedBox(width: 6),
                            _buildReviewStatusBadge(reviewStatus),
                          ],
                          if (hidePrompts) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: '提示词已隐藏',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9F0A).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.lock_rounded,
                                  size: 12,
                                  color: const Color(0xFFFF9F0A),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // 描述 - iOS风格
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                          height: 1.4,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const Spacer(),
                      
                      // 标签 - iOS风格
                      if (tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: tags.take(3).map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                                letterSpacing: -0.1,
                              ),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      
                      // 评分 - iOS风格
                      if (rating != null && rating > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFCC00).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(5, (index) {
                                return Icon(
                                  index < rating.round() ? Icons.star : Icons.star_border,
                                  size: 14,
                                  color: const Color(0xFFFFCC00),
                                );
                              }),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFFCC00),
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      
                      // 统计信息和操作按钮
                      Row(
                        children: [
                          // 使用次数
                          _buildStatChip(
                            theme,
                            icon: Icons.play_circle_outline,
                            label: _formatCount(usageCount),
                            color: theme.colorScheme.tertiary,
                          ),
                          
                          const SizedBox(width: 8),
                          
                          // 收藏次数
                          _buildStatChip(
                            theme,
                            icon: Icons.bookmark_outline,
                            label: _formatCount(favoriteCount),
                            color: theme.colorScheme.secondary,
                          ),
                          
                          const Spacer(),
                          
                          // 收藏按钮
                          _buildIconButton(
                            theme,
                            icon: isFavorite ? Icons.bookmark : Icons.bookmark_border,
                            isActive: isFavorite,
                            onTap: widget.onFavorite,
                            activeColor: theme.colorScheme.secondary,
                          ),
                          
                          const SizedBox(width: 4),
                          
                          // 点赞按钮
                          _buildIconButton(
                            theme,
                            icon: isLiked ? Icons.favorite : Icons.favorite_border,
                            label: _formatCount(likeCount),
                            isActive: isLiked,
                            onTap: widget.onLike,
                            activeColor: Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // iOS风格操作按钮（悬浮时显示）
                if (_isHovering)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🆕 我的策略管理按钮
                        if (widget.isMyStrategy) ...[
                          // 编辑按钮
                          if (widget.onEdit != null)
                            _buildActionButton(
                              theme: theme,
                              icon: Icons.edit_rounded,
                              label: '编辑',
                              onTap: widget.onEdit,
                            ),
                          const SizedBox(width: 6),
                          
                          // 分享按钮（根据审核状态显示不同样式）
                          if (widget.onShare != null)
                            _buildShareButton(theme, reviewStatus),
                          const SizedBox(width: 6),
                          
                          // 删除按钮
                          if (widget.onDelete != null)
                            _buildActionButton(
                              theme: theme,
                              icon: Icons.delete_rounded,
                              label: '删除',
                              onTap: widget.onDelete,
                              color: const Color(0xFFFF3B30),
                            ),
                        ] else ...[
                          // 公开策略的按钮
                          // 复制按钮 - iOS风格
                          if (widget.onCopy != null)
                            _buildActionButton(
                              theme: theme,
                              icon: Icons.content_copy_rounded,
                              label: '复制',
                              onTap: widget.onCopy,
                            ),
                          
                          if (widget.onCopy != null) const SizedBox(width: 6),
                          
                          // 使用按钮 - iOS风格
                          GestureDetector(
                            onTap: widget.onUse,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: (theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '使用',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(ThemeData theme, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(ThemeData theme, {
    required IconData icon,
    String? label,
    required bool isActive,
    required VoidCallback? onTap,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : (theme.brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43)),
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? activeColor : (theme.brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43)),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  /// 🆕 构建审核状态标签
  Widget _buildReviewStatusBadge(String reviewStatus) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (reviewStatus) {
      case ReviewStatusConstants.draft:
        statusColor = const Color(0xFF8E8E93);
        statusText = '草稿';
        statusIcon = Icons.edit_note_rounded;
        break;
      case ReviewStatusConstants.pending:
        statusColor = const Color(0xFFFF9500);
        statusText = '审核中';
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case ReviewStatusConstants.approved:
        statusColor = const Color(0xFF34C759);
        statusText = '已分享';
        statusIcon = Icons.check_circle_rounded;
        break;
      case ReviewStatusConstants.rejected:
        statusColor = const Color(0xFFFF3B30);
        statusText = '未通过';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = const Color(0xFF8E8E93);
        statusText = '未知';
        statusIcon = Icons.help_outline_rounded;
    }

    return Tooltip(
      message: statusText,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              statusIcon,
              size: 11,
              color: statusColor,
            ),
            const SizedBox(width: 3),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: statusColor,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🆕 构建操作按钮
  Widget _buildActionButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final buttonColor = color ?? (theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF));
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.brightness == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: buttonColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: buttonColor,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🆕 构建分享按钮（根据审核状态显示不同样式）
  Widget _buildShareButton(ThemeData theme, String reviewStatus) {
    Color buttonColor;
    String buttonText;
    IconData buttonIcon;
    bool isEnabled;

    switch (reviewStatus) {
      case ReviewStatusConstants.draft:
      case ReviewStatusConstants.rejected:
        buttonColor = theme.brightness == Brightness.dark ? const Color(0xFF5E5CE6) : const Color(0xFF5856D6);
        buttonText = '分享';
        buttonIcon = Icons.share_rounded;
        isEnabled = true;
        break;
      case ReviewStatusConstants.pending:
        buttonColor = const Color(0xFF8E8E93);
        buttonText = '审核中';
        buttonIcon = Icons.hourglass_empty_rounded;
        isEnabled = false; // 审核中不可点击
        break;
      case ReviewStatusConstants.approved:
        buttonColor = const Color(0xFF34C759);
        buttonText = '已分享';
        buttonIcon = Icons.check_circle_rounded;
        isEnabled = false; // 已分享不可点击
        break;
      default:
        buttonColor = const Color(0xFF8E8E93);
        buttonText = '分享';
        buttonIcon = Icons.share_rounded;
        isEnabled = true;
    }

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: isEnabled ? widget.onShare : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.brightness == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                buttonIcon,
                size: 14,
                color: buttonColor,
              ),
              const SizedBox(width: 4),
              Text(
                buttonText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: buttonColor,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

