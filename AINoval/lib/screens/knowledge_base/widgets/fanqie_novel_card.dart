/// 番茄小说卡片组件
library;

import 'package:flutter/material.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/utils/web_theme.dart';
// import 'package:cached_network_image/cached_network_image.dart';

/// 番茄小说卡片组件
class FanqieNovelCard extends StatelessWidget {
  final FanqieNovelInfo novel;
  final VoidCallback onTap;

  const FanqieNovelCard({
    Key? key,
    required this.novel,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context),
            border: Border.all(
              color: WebTheme.getBorderColor(context),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              _buildCover(context),
              
              // 信息
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildInfo(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4, // 书籍封面比例
      child: Container(
        decoration: BoxDecoration(
          color: WebTheme.getBorderColor(context).withOpacity(0.1),
          border: Border.all(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
        child: novel.coverImageUrl != null
            ? Image.network(
                novel.coverImageUrl!,
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
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.book,
                    color: WebTheme.getSecondaryTextColor(context),
                    size: 48,
                  ),
                ),
              )
            : Center(
                child: Icon(
                  Icons.book,
                  color: WebTheme.getSecondaryTextColor(context),
                  size: 48,
                ),
              ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题
        Text(
          novel.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        
        const SizedBox(height: 6),
        
        // 作者
        if (novel.author != null)
          Text(
            '作者: ${novel.author}',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        
        const Spacer(),
        
        // 底部状态行
        Row(
          children: [
            if (novel.completionStatus != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getStatusColor(novel.completionStatus!).withOpacity(0.1),
                  border: Border.all(
                    color: _getStatusColor(novel.completionStatus!),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  novel.completionStatus!.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: _getStatusColor(novel.completionStatus!),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            if (novel.chapterCount != null)
              Text(
                '${novel.chapterCount}章',
                style: TextStyle(
                  fontSize: 11,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            const Spacer(),
            // ✅ 已拆书标签
            if (novel.cached == true)
              Icon(
                Icons.check_circle,
                size: 16,
                color: Colors.green,
              ),
          ],
        ),
      ],
    );
  }

  Color _getStatusColor(NovelCompletionStatus status) {
    switch (status) {
      case NovelCompletionStatus.completed:
        return Colors.green;
      case NovelCompletionStatus.ongoing:
        return Colors.blue;
      case NovelCompletionStatus.paused:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

