import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../utils/web_theme.dart';

/// 用户模板卡片组件
class UserTemplateCard extends StatelessWidget {
  final PromptTemplate template;
  final bool isSelected;
  final bool batchMode;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onFavorite;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onSelectionChanged;

  UserTemplateCard({
    Key? key,
    required this.template,
    this.isSelected = false,
    this.batchMode = false,
    this.onTap,
    this.onEdit,
    this.onShare,
    this.onFavorite,
    this.onDelete,
    this.onSelectionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected 
          ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
          : WebTheme.getCardColor(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 12),
              _buildContent(context),
              const SizedBox(height: 12),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        if (batchMode) ...[ 
          Checkbox(
            value: isSelected,
            onChanged: (value) => onSelectionChanged?.call(value ?? false),
          ),
          const SizedBox(width: 8),
        ],
        
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                  _buildStatusIndicators(context),
                ],
              ),
              if ((template.description ?? '').isNotEmpty) ...[ 
                const SizedBox(height: 4),
                Text(
                  template.description ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: WebTheme.getTextColor(context).withOpacity(0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        
        if (!batchMode) ...[
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => _buildMenuItems(),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusIndicators(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (template.isFavorite == true) 
          Container(
            margin: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.favorite,
              size: 16,
              color: Colors.red,
            ),
          ),
        if (template.isPublic == true) 
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
              ),
            ),
            child: Text(
              '已分享',
              style: TextStyle(
                fontSize: 10,
               color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (template.isPublic == false) 
          Container(
            margin: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.lock,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模板内容预览
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Text(
            template.content,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: WebTheme.getTextColor(context).withOpacity(0.8),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        
        if ((template.templateTags ?? const <String>[]).isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: (template.templateTags ?? const <String>[]) 
                .map((tag) => _buildTag(context, tag))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTag(BuildContext context, String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WebTheme.getTextColor(context).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 11,
          color: WebTheme.getTextColor(context).withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        // 功能类型
        if (template.aiFeatureType != null) ...[
          _buildFeatureTypeChip(context),
          const SizedBox(width: 12),
        ],
        
        // 创建时间
        Icon(
          Icons.access_time,
          size: 14,
          color: WebTheme.getTextColor(context).withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Text(
          _formatDateTime(template.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getTextColor(context).withOpacity(0.5),
          ),
        ),
        
        const SizedBox(width: 16),
        
        // 使用次数
        Icon(
          Icons.play_circle_outline,
          size: 14,
          color: WebTheme.getTextColor(context).withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Text(
          '使用 ${template.useCount ?? 0} 次',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getTextColor(context).withOpacity(0.5),
          ),
        ),
        
        const Spacer(),
        
        // 版本信息
        // 版本信息已移除（PromptTemplate 无版本字段）
      ],
    );
  }

  Widget _buildFeatureTypeChip(BuildContext context) {
    final featureType = template.aiFeatureType!;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getFeatureTypeColor(featureType).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _getFeatureTypeColor(featureType).withOpacity(0.3),
        ),
      ),
      child: Text(
        _getFeatureTypeLabel(featureType),
        style: TextStyle(
          fontSize: 11,
          color: _getFeatureTypeColor(featureType),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    List<PopupMenuEntry<String>> items = [];
    
    // 编辑选项
    items.add(const PopupMenuItem(
      value: 'edit',
      child: Row(
        children: [
          Icon(Icons.edit, size: 18),
          SizedBox(width: 8),
          Text('编辑'),
        ],
      ),
    ));
    
    // 收藏选项
    if (template.isFavorite != true) {
      items.add(const PopupMenuItem(
        value: 'favorite',
        child: Row(
          children: [
            Icon(Icons.favorite_border, size: 18),
            SizedBox(width: 8),
            Text('添加到收藏'),
          ],
        ),
      ));
    } else {
      items.add(const PopupMenuItem(
        value: 'unfavorite',
        child: Row(
          children: [
            Icon(Icons.favorite, size: 18, color: Colors.red),
            SizedBox(width: 8),
            Text('取消收藏'),
          ],
        ),
      ));
    }
    
    // 分享选项
    if (template.isPublic != true) {
      items.add(const PopupMenuItem(
        value: 'share',
        child: Row(
          children: [
            Icon(Icons.share, size: 18),
            SizedBox(width: 8),
            Text('分享到社区'),
          ],
        ),
      ));
    }
    
    items.add(const PopupMenuDivider());
    
    // 删除选项
    items.add(const PopupMenuItem(
      value: 'delete',
      child: Row(
        children: [
          Icon(Icons.delete, size: 18, color: Colors.red),
          SizedBox(width: 8),
          Text('删除', style: TextStyle(color: Colors.red)),
        ],
      ),
    ));
    
    return items;
  }

  Color _getFeatureTypeColor(AIFeatureType featureType) {
    final scheme = Theme.of(_cachedContext!).colorScheme;
    switch (featureType) {
      case AIFeatureType.aiChat:
        return scheme.primary;
      case AIFeatureType.novelGeneration:
        return scheme.secondary;
      case AIFeatureType.novelCompose:
        return scheme.secondary; // 与内容生成保持一致的视觉语义
      case AIFeatureType.textExpansion:
        return scheme.tertiary;
      case AIFeatureType.textRefactor:
        return scheme.primary;
      case AIFeatureType.textSummary:
        return scheme.secondary;
      case AIFeatureType.sceneToSummary:
        return scheme.tertiary;
      case AIFeatureType.summaryToScene:
        return scheme.primary;
      case AIFeatureType.professionalFictionContinuation:
        return scheme.primary;
      case AIFeatureType.sceneBeatGeneration:
        return scheme.secondary;
      case AIFeatureType.settingTreeGeneration:
        return scheme.tertiary;
      case AIFeatureType.storyPlotContinuation:
        return scheme.primary;
    }
  }

  String _getFeatureTypeLabel(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.aiChat:
        return 'AI聊天';
      case AIFeatureType.novelGeneration:
        return '场景生成';
      case AIFeatureType.novelCompose:
        return '设定编排';
      case AIFeatureType.textExpansion:
        return '扩写';
      case AIFeatureType.textRefactor:
        return '重构';
      case AIFeatureType.textSummary:
        return '总结';
      case AIFeatureType.sceneToSummary:
        return '场景转摘要';
      case AIFeatureType.summaryToScene:
        return '摘要转场景';
      case AIFeatureType.professionalFictionContinuation:
        return '专业续写';
      case AIFeatureType.sceneBeatGeneration:
        return '场景节拍';
      case AIFeatureType.settingTreeGeneration:
        return '设定树生成';
      case AIFeatureType.storyPlotContinuation:
        return '剧情续写';
    }
  }

  // 为了在私有方法中访问 theme，缓存一次 context（仅在 build 调用期间有效）
  final BuildContext? _cachedContext = null;

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected 
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : WebTheme.getCardColor(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 12),
              _buildContent(context),
              const SizedBox(height: 12),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'edit':
        onEdit?.call();
        break;
      case 'favorite':
      case 'unfavorite':
        onFavorite?.call();
        break;
      case 'share':
        onShare?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
    }
  }
}