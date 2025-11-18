import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../models/prompt_models.dart';
import '../../../utils/ai_feature_type_utils.dart';

/// 提示词模板卡片
/// 苹果风格设计的模板展示卡片
class PromptTemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback? onLike;
  final VoidCallback? onFavorite;
  final VoidCallback? onUse;
  final VoidCallback? onCopy;
  final VoidCallback? onTap;
  final VoidCallback? onEdit; // 🆕 编辑模板
  final VoidCallback? onDelete; // 🆕 删除模板
  final VoidCallback? onShare; // 🆕 分享/提交审核
  /// 当前窗口的AIFeatureType，只有匹配时才显示使用按钮
  final AIFeatureType? currentFeatureType;
  /// 是否是我的模板
  final bool isMyTemplate;

  const PromptTemplateCard({
    super.key,
    required this.template,
    this.onLike,
    this.onFavorite,
    this.onUse,
    this.onCopy,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onShare,
    this.currentFeatureType,
    this.isMyTemplate = false,
  });

  @override
  Widget build(BuildContext context) {
    final featureType = _parseFeatureType(template['featureType']);
    final isLiked = template['isLiked'] as bool? ?? false;
    final isFavorite = template['isFavorite'] as bool? ?? false;
    final likeCount = template['likeCount'] as int? ?? 0;
    final favoriteCount = template['favoriteCount'] as int? ?? 0;
    final usageCount = template['usageCount'] as int? ?? 0;
    final rewardPoints = AIFeatureTypeUtils.getRewardPoints(featureType);
    final typeColor = Color(AIFeatureTypeUtils.getColor(featureType));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：作者信息
            _buildAuthorHeader(context),
            
            // 功能类型标签和积分信息
            _buildTypeAndRewardBadges(context, featureType, typeColor, rewardPoints),
            
            // 标题和描述
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template['name'] ?? '未命名',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        template['description'] ?? '暂无描述',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 统计信息
            _buildStatistics(context, likeCount, favoriteCount, usageCount),
            
            // 操作按钮
            _buildActions(context, isLiked, isFavorite),
          ],
        ),
      ),
    );
  }

  /// 作者信息头部
  Widget _buildAuthorHeader(BuildContext context) {
    final authorName = template['authorName'] as String? ?? 
                      template['authorId'] as String? ?? 
                      '匿名作者';
    final authorAvatar = template['authorAvatar'] as String?;
    
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // 作者头像
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  CupertinoColors.systemBlue.withOpacity(0.8),
                  CupertinoColors.systemPurple.withOpacity(0.8),
                ],
              ),
              border: Border.all(
                color: CupertinoColors.separator.resolveFrom(context),
                width: 1.5,
              ),
            ),
            child: authorAvatar != null && authorAvatar.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      authorAvatar,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
                    ),
                  )
                : _buildDefaultAvatar(),
          ),
          const SizedBox(width: 8),
          
          // 作者名称
          Expanded(
            child: Text(
              authorName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 默认头像（首字母）
  Widget _buildDefaultAvatar() {
    final authorName = template['authorName'] as String? ?? 
                      template['authorId'] as String? ?? 
                      '匿';
    final initial = authorName.isNotEmpty ? authorName[0].toUpperCase() : '?';
    
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: CupertinoColors.white,
        ),
      ),
    );
  }

  /// 类型和积分徽章
  Widget _buildTypeAndRewardBadges(
    BuildContext context, 
    AIFeatureType featureType, 
    Color typeColor,
    int rewardPoints,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 功能类型标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: typeColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: typeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  AIFeatureTypeUtils.getShortName(featureType),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          
          // 积分信息
          if (rewardPoints > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(AIFeatureTypeUtils.getRewardLevelColor(featureType))
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.money_dollar_circle_fill,
                    size: 12,
                    color: Color(AIFeatureTypeUtils.getRewardLevelColor(featureType)),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '+$rewardPoints',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(AIFeatureTypeUtils.getRewardLevelColor(featureType)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatistics(
    BuildContext context,
    int likeCount,
    int favoriteCount,
    int usageCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildStatItem(
            context,
            CupertinoIcons.heart,
            likeCount,
            '点赞',
          ),
          const SizedBox(width: 16),
          _buildStatItem(
            context,
            CupertinoIcons.star,
            favoriteCount,
            '收藏',
          ),
          const SizedBox(width: 16),
          _buildStatItem(
            context,
            CupertinoIcons.chart_bar,
            usageCount,
            '使用',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    int count,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
        const SizedBox(width: 4),
        Text(
          _formatCount(count),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, bool isLiked, bool isFavorite) {
    // 获取模板的功能类型
    final templateFeatureType = _parseFeatureType(template['featureType']);
    final isPublic = template['isPublic'] as bool? ?? false;
    final hidePrompts = template['hidePrompts'] as bool? ?? false;
    
    // 只有当传入的currentFeatureType与模板的featureType一致时才显示使用按钮
    final showUseButton = currentFeatureType != null && 
                          currentFeatureType == templateFeatureType &&
                          onUse != null;
    // 复制按钮仅在公开且未隐藏提示词 且 提供onCopy回调 时显示
    final showCopyButton = !isMyTemplate && isPublic && !hidePrompts && onCopy != null;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 🆕 我的模板模式：显示编辑、删除、分享按钮
          if (isMyTemplate) ...[
            // 编辑按钮
            if (onEdit != null) ...[
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minSize: 0,
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onEdit,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.pencil,
                        size: 16,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '编辑',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            
            // 删除按钮
            if (onDelete != null) ...[
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minSize: 0,
                  color: CupertinoColors.systemRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onDelete,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.trash,
                        size: 16,
                        color: CupertinoColors.systemRed,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '删除',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            
            // 分享按钮
            if (onShare != null) ...[
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minSize: 0,
                  color: CupertinoColors.systemBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onShare,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.square_arrow_up,
                        size: 16,
                        color: CupertinoColors.systemBlue,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '分享',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ] else ...[
            // 公共模板模式：显示点赞、收藏、复制按钮
            // 点赞按钮
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                minSize: 0,
                color: isLiked 
                    ? CupertinoColors.systemPink.withOpacity(0.15)
                    : CupertinoColors.systemGrey6.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
                onPressed: onLike,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                      size: 16,
                      color: isLiked 
                          ? CupertinoColors.systemPink 
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isLiked ? '已赞' : '点赞',
                      style: TextStyle(
                        fontSize: 13,
                        color: isLiked 
                            ? CupertinoColors.systemPink 
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // 收藏按钮
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                minSize: 0,
                color: isFavorite 
                    ? CupertinoColors.systemYellow.withOpacity(0.15)
                    : CupertinoColors.systemGrey6.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
                onPressed: onFavorite,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 16,
                      color: isFavorite 
                          ? CupertinoColors.systemYellow 
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isFavorite ? '已藏' : '收藏',
                      style: TextStyle(
                        fontSize: 13,
                        color: isFavorite 
                            ? CupertinoColors.systemYellow 
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 复制按钮（只有公开且未隐藏提示词 才显示）
            if (showCopyButton) ...[
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minSize: 0,
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onCopy,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.doc_on_doc,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '复制',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],

          // 使用按钮（只有当功能类型匹配时才显示）
          if (showUseButton) ...[
            const SizedBox(width: 8),
            Expanded(
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 8),
                minSize: 0,
                borderRadius: BorderRadius.circular(10),
                onPressed: onUse,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '使用',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 辅助方法：格式化数字
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return count.toString();
    }
  }

  // 辅助方法：解析功能类型
  AIFeatureType _parseFeatureType(dynamic value) {
    if (value == null) return AIFeatureType.textExpansion;
    if (value is String) {
      return AIFeatureTypeHelper.fromApiString(value);
    }
    return AIFeatureType.textExpansion;
  }
}

