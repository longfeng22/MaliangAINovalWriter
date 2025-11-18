/// 知识库卡片组件
library;

import 'package:flutter/material.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 知识库卡片组件
/// 
/// 类似淘宝商品卡片的设计
class KnowledgeBaseCardWidget extends StatefulWidget {
  final KnowledgeBaseCard card;
  final VoidCallback onTap;
  final bool isListMode;

  const KnowledgeBaseCardWidget({
    Key? key,
    required this.card,
    required this.onTap,
    this.isListMode = false,
  }) : super(key: key);

  @override
  State<KnowledgeBaseCardWidget> createState() => _KnowledgeBaseCardWidgetState();
}

class _KnowledgeBaseCardWidgetState extends State<KnowledgeBaseCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isListMode) {
      return _buildListCard();
    } else {
      return _buildGridCard();
    }
  }

  /// 网格卡片（横向布局）
  Widget _buildGridCard() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context),
          border: Border.all(
            color: _isHovered 
                ? WebTheme.getPrimaryColor(context).withOpacity(0.4)
                : WebTheme.getBorderColor(context),
            width: 1,
          ),
          boxShadow: _isHovered ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面 - 固定尺寸100*130
                Container(
                  width: 100,
                  height: 130,
                  child: _buildCover(),
                ),
                
                const SizedBox(width: 12),
                
                // 信息
                Expanded(
                  child: _buildInfo(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 列表卡片（横向布局）
  Widget _buildListCard() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context),
          border: Border.all(
            color: _isHovered 
                ? WebTheme.getPrimaryColor(context).withOpacity(0.4)
                : WebTheme.getBorderColor(context),
            width: 1,
          ),
          boxShadow: _isHovered ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面
                SizedBox(
                  width: 100,
                  height: 130,
                  child: _buildCover(),
                ),
                
                const SizedBox(width: 16),
                
                // 信息
                Expanded(
                  child: _buildInfo(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: WebTheme.getBorderColor(context).withOpacity(0.1),
            border: Border.all(
              color: WebTheme.getBorderColor(context),
              width: 1,
            ),
          ),
          child: widget.card.coverImageUrl != null && widget.card.coverImageUrl!.isNotEmpty
              ? Image.network(
                  widget.card.coverImageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // 记录错误信息，帮助调试
                    print('图片加载失败: ${widget.card.coverImageUrl}, 错误: $error');
                    return Center(
                      child: Icon(
                        Icons.library_books,
                        color: WebTheme.getSecondaryTextColor(context),
                        size: 32,
                      ),
                    );
                  },
                )
              : Center(
                  child: Icon(
                    Icons.library_books,
                    color: WebTheme.getSecondaryTextColor(context),
                    size: 32,
                  ),
                ),
        ),
        // ✅ 来源徽章（左上角）
        if (widget.card.isUserImported || (widget.card.fanqieNovelId != null && widget.card.fanqieNovelId!.isNotEmpty))
          Positioned(
            top: 4,
            left: 4,
            child: _buildSourceBadge(),
          ),
      ],
    );
  }

  Widget _buildSourceBadge() {
    final isUserImported = widget.card.isUserImported;
    final icon = isUserImported ? Icons.upload_file : Icons.travel_explore;
    final label = isUserImported ? '我的' : '番茄';
    final color = isUserImported ? const Color(0xFF4CAF50) : const Color(0xFFFF6600);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 上半部分：标题和作者
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                widget.card.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: WebTheme.getTextColor(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              if (widget.card.author != null) ...[
                const SizedBox(height: 6),
                Text(
                  '作者：${widget.card.author!}',
                  style: TextStyle(
                    fontSize: 11,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          
          // 中间部分：简介
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                widget.card.description,
                style: TextStyle(
                  fontSize: 11,
                  color: WebTheme.getSecondaryTextColor(context).withOpacity(0.8),
                  height: 1.3,
                ),
                maxLines: widget.isListMode ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          
          // 下半部分：统计信息和标签
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 统计信息
              _buildStats(),
              
              // 标签
              if (widget.card.tags != null && widget.card.tags!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildTags(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        _buildStatIcon(Icons.favorite, widget.card.likeCount),
        const SizedBox(width: 8),
        _buildStatIcon(Icons.bookmark, widget.card.referenceCount),
        const SizedBox(width: 8),
        _buildStatIcon(Icons.visibility, widget.card.viewCount),
        
        if (widget.card.importTime != null) ...[
          const Spacer(),
          Text(
            _formatTime(widget.card.importTime!),
            style: TextStyle(
              fontSize: 10,
              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatIcon(IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
        ),
        const SizedBox(width: 2),
        Text(
          _formatCount(count),
          style: TextStyle(
            fontSize: 10,
            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildTags() {
    final displayTags = widget.card.tags!.take(2).toList(); // 减少显示的标签数量
    
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: displayTags.map((tag) => _buildTag(tag)).toList(),
    );
  }

  Widget _buildTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 9,
          color: WebTheme.getPrimaryColor(context),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}天前';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}个月前';
    } else {
      return '${(difference.inDays / 365).floor()}年前';
    }
  }
}

