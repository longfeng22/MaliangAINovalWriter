import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/services/image_cache_service.dart';

class CompactNovelCard extends StatefulWidget {
  final NovelSummary novel;
  final VoidCallback? onContinueWriting;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  const CompactNovelCard({
    Key? key,
    required this.novel,
    this.onContinueWriting,
    this.onEdit,
    this.onShare,
    this.onDelete,
  }) : super(key: key);

  @override
  State<CompactNovelCard> createState() => _CompactNovelCardState();
}

class _CompactNovelCardState extends State<CompactNovelCard> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getNovelStatus() {
    if (widget.novel.wordCount < 1000) {
      return '草稿';
    } else if (widget.novel.completionPercentage >= 100.0) {
      return '已完结';
    } else {
      return '连载中';
    }
  }

  Color _getStatusColor(String status, BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    switch (status) {
      case '草稿':
        return isDark ? WebTheme.darkGrey400 : WebTheme.grey400;
      case '连载中':
        return Theme.of(context).colorScheme.primary;
      case '已完结':
        return Theme.of(context).colorScheme.secondary;
      default:
        return isDark ? WebTheme.darkGrey400 : WebTheme.grey400;
    }
  }

  Color _getStatusBackgroundColor(String status, BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    switch (status) {
      case '草稿':
        return isDark ? WebTheme.darkGrey200 : WebTheme.grey200;
      case '连载中':
        return Theme.of(context).colorScheme.primaryContainer.withOpacity(isDark ? 0.2 : 1.0);
      case '已完结':
        return Theme.of(context).colorScheme.secondaryContainer.withOpacity(isDark ? 0.2 : 1.0);
      default:
        return isDark ? WebTheme.darkGrey200 : WebTheme.grey200;
    }
  }

  String _getCoverImageUrl() {
    if (widget.novel.coverUrl.isNotEmpty) {
      return widget.novel.coverUrl;
    }
    // Use Picsum Photos as fallback with unique ID based on novel ID
    final randomId = widget.novel.id.hashCode.abs() % 1000;
    return 'https://picsum.photos/400/300?random=$randomId';
  }

  String _formatLastEditTime() {
    final now = DateTime.now();
    final diff = now.difference(widget.novel.lastEditTime);
    
    if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            transform: Matrix4.identity()
              ..scale(_isHovered ? 1.02 : 1.0),
            decoration: BoxDecoration(
              color: WebTheme.getCardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHovered 
                  ? (isDark ? WebTheme.darkGrey500 : WebTheme.grey500)
                  : WebTheme.getBorderColor(context),
                width: 1,
              ),
              boxShadow: _isHovered ? [
                BoxShadow(
                  color: WebTheme.getShadowColor(context, opacity: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ] : [
                BoxShadow(
                  color: WebTheme.getShadowColor(context, opacity: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cover Image Area - 更紧凑的比例
                  Expanded(
                    flex: 3,
                    child: AspectRatio(
                      aspectRatio: 3 / 2,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                (isDark ? WebTheme.darkGrey300 : WebTheme.grey300).withOpacity(0.2),
                                (isDark ? WebTheme.darkGrey200 : WebTheme.grey200).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: ImageCacheService().getAdaptiveImage(
                            imageUrl: _getCoverImageUrl(),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            backgroundColor: WebTheme.getCardColor(context),
                            borderRadius: BorderRadius.circular(12),
                            placeholder: 'menu_book',
                          ),
                        ),
                        // Status Badge
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusBackgroundColor(_getNovelStatus(), context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getNovelStatus(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _getStatusColor(_getNovelStatus(), context),
                              ),
                            ),
                          ),
                        ),
                        // More Options Button
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: (isDark ? WebTheme.darkGrey100 : WebTheme.white).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                            child: PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_horiz,
                                size: 14,
                                color: WebTheme.getTextColor(context, isPrimary: false),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 14, color: WebTheme.getTextColor(context, isPrimary: false)),
                                      const SizedBox(width: 6),
                                      const Text('编辑', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: Row(
                                    children: [
                                      Icon(Icons.share, size: 14, color: WebTheme.getTextColor(context, isPrimary: false)),
                                      const SizedBox(width: 6),
                                      const Text('分享', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 14, color: WebTheme.error),
                                      const SizedBox(width: 6),
                                      Text('删除', style: TextStyle(color: WebTheme.error, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    widget.onEdit?.call();
                                    break;
                                  case 'share':
                                    widget.onShare?.call();
                                    break;
                                  case 'delete':
                                    widget.onDelete?.call();
                                    break;
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  // Content Area - 修复溢出问题的紧凑布局
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6), // 减少顶部和底部边距
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            widget.novel.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isHovered 
                                ? WebTheme.getPrimaryColor(context)
                                : WebTheme.getTextColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Description - 灵活高度分配
                          Flexible(
                            child: Text(
                              widget.novel.description.isNotEmpty 
                                ? widget.novel.description 
                                : '暂无描述',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: WebTheme.getSecondaryTextColor(context),
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3), // 减少间距
                          // Category and Rating
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), // 减少垂直内边距
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: WebTheme.getBorderColor(context),
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.novel.seriesName.isNotEmpty 
                                    ? widget.novel.seriesName 
                                    : '独立作品',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: WebTheme.getTextColor(context, isPrimary: false),
                                  ),
                                ),
                              ),
                              if (widget.novel.completionPercentage > 0) ...[
                                const SizedBox(width: 4), // 减少间距
                                Row(
                                  children: [
                                    Icon(
                                      Icons.percent,
                                      size: 11, // 稍微减小图标
                                      color: Theme.of(context).colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 1),
                                    Text(
                                      '${widget.novel.completionPercentage.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: WebTheme.getSecondaryTextColor(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3), // 减少间距
                          // Stats - 单行显示
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.menu_book,
                                    size: 9,
                                    color: WebTheme.getSecondaryTextColor(context),
                                  ),
                                  const SizedBox(width: 1),
                                  Text(
                                    '${(widget.novel.wordCount / 1000).toStringAsFixed(0)}k字',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: WebTheme.getSecondaryTextColor(context),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.schedule,
                                    size: 9,
                                    color: WebTheme.getSecondaryTextColor(context),
                                  ),
                                  const SizedBox(width: 1),
                                  Text(
                                    '${widget.novel.readTime}分钟',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: WebTheme.getSecondaryTextColor(context),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _formatLastEditTime(),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: WebTheme.getSecondaryTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4), // 减少间距
                          // Continue Writing Button - 确保不会溢出
                          SizedBox(
                            width: double.infinity,
                            height: 22, // 稍微减小按钮高度
                            child: OutlinedButton(
                              onPressed: widget.onContinueWriting,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _isHovered
                                  ? WebTheme.white
                                  : WebTheme.getTextColor(context),
                                backgroundColor: _isHovered
                                  ? WebTheme.getPrimaryColor(context)
                                  : Colors.transparent,
                                side: BorderSide(
                                  color: WebTheme.getBorderColor(context),
                                  width: 1,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8), // 减少水平内边距
                                minimumSize: Size.zero, // 允许按钮收缩到最小尺寸
                              ),
                              child: const Text(
                                '继续创作',
                                style: TextStyle(
                                  fontSize: 11, // 稍微减小字体
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}