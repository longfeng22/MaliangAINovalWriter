import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../utils/web_theme.dart';

/// 公共模板卡片组件
class PublicTemplateCard extends StatelessWidget {
  final PromptTemplate template;
  final bool isSelected;
  final bool batchMode;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onReview;
  final VoidCallback? onPublish;
  final VoidCallback? onSetVerified;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onSelectionChanged;

  const PublicTemplateCard({
    Key? key,
    required this.template,
    this.isSelected = false,
    this.batchMode = false,
    this.onTap,
    this.onEdit,
    this.onDuplicate,
    this.onReview,
    this.onPublish,
    this.onSetVerified,
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
                  _buildStatusChips(context),
                ],
              ),
              if (template.description?.isNotEmpty == true) ...[ 
                const SizedBox(height: 4),
                Text(
                  template.description!,
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

  Widget _buildStatusChips(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (template.isVerified == true) 
          _buildStatusChip(context, '认证', Colors.orange),
        if (template.isPublic == true) 
          _buildStatusChip(context, '已发布', Colors.green),
        if (template.isPublic != true && template.isVerified != true)
          _buildStatusChip(context, '待审核', Colors.grey),
      ],
    );
  }

  Widget _buildStatusChip(BuildContext context, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Row(
      children: [
        if (template.templateTags?.isNotEmpty == true) ...[
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: template.templateTags!.take(5).map((tag) => 
                _buildTag(context, tag)).toList(),
            ),
          ),
        ] else
          const Expanded(child: SizedBox()),
        
        if (template.aiFeatureType != null) ...[
          const SizedBox(width: 12),
          _buildFeatureTypeChip(context),
        ],
      ],
    );
  }

  Widget _buildFeatureTypeChip(BuildContext context) {
    final featureType = _featureTypeToString(template.aiFeatureType!);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getFeatureTypeColor(featureType).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getFeatureTypeColor(featureType).withOpacity(0.3),
        ),
      ),
      child: Text(
        _getFeatureTypeLabel(featureType),
        style: TextStyle(
          fontSize: 12,
          color: _getFeatureTypeColor(featureType),
          fontWeight: FontWeight.w500,
        ),
      ),
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
        // 创建信息
        if (template.authorName != null) ...[
          Icon(
            Icons.person,
            size: 14,
            color: WebTheme.getTextColor(context).withOpacity(0.5),
          ),
          const SizedBox(width: 4),
          Text(
            template.authorName!,
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getTextColor(context).withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 16),
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
        
        // 评分信息
        if (template.averageRating != null && template.averageRating! > 0) ...[
          Icon(
            Icons.star,
            size: 14,
            color: Colors.amber,
          ),
          const SizedBox(width: 4),
          Text(
            '${template.averageRating!.toStringAsFixed(1)} (${template.ratingCount ?? 0})',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getTextColor(context).withOpacity(0.5),
            ),
          ),
        ] else
          Text(
            '暂无评分',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getTextColor(context).withOpacity(0.5),
            ),
          ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    List<PopupMenuEntry<String>> items = [];
    
    // 复制选项
    items.add(const PopupMenuItem(
      value: 'duplicate',
      child: Row(
        children: [
          Icon(Icons.copy, size: 18),
          SizedBox(width: 8),
          Text('复制为新模板'),
        ],
      ),
    ));
    
    // 根据状态显示不同操作
    if (template.isPublic != true) {
      items.add(const PopupMenuItem(
        value: 'review',
        child: Row(
          children: [
            Icon(Icons.rate_review, size: 18),
            SizedBox(width: 8),
            Text('审核'),
          ],
        ),
      ));
      
      items.add(const PopupMenuItem(
        value: 'publish',
        child: Row(
          children: [
            Icon(Icons.publish, size: 18),
            SizedBox(width: 8),
            Text('发布'),
          ],
        ),
      ));
    }
    
    if (template.isVerified != true) {
      items.add(PopupMenuItem(
        value: 'verify',
        child: Row(
          children: [
            Icon(Icons.verified, size: 18, color: Colors.orange),
            SizedBox(width: 8),
            Text('设为认证', style: TextStyle(color: Colors.orange)),
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

  Color _getFeatureTypeColor(String featureType) {
    switch (featureType) {
      case 'AI_CHAT':
        return Colors.blue;
      case 'SCENE_TO_SUMMARY':
      case 'SUMMARY_TO_SCENE':
        return Colors.green;
      case 'PROFESSIONAL_FICTION_CONTINUATION':
      case 'NOVEL_GENERATION':
      case 'NOVEL_COMPOSE':
        return Colors.orange;
      case 'TEXT_SUMMARY':
        return Colors.purple;
      case 'TEXT_EXPANSION':
      case 'TEXT_REFACTOR':
        return Colors.teal;
      case 'SCENE_BEAT_GENERATION':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getFeatureTypeLabel(String featureType) {
    switch (featureType) {
      case 'AI_CHAT':
        return 'AI聊天';
      case 'SCENE_TO_SUMMARY':
        return '场景摘要';
      case 'SUMMARY_TO_SCENE':
        return '摘要场景';
      case 'TEXT_EXPANSION':
        return '文本扩写';
      case 'TEXT_REFACTOR':
        return '文本重构';
      case 'TEXT_SUMMARY':
        return '文本总结';
      case 'NOVEL_GENERATION':
        return '小说生成';
      case 'NOVEL_COMPOSE':
        return '设定编排';
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return '专业续写';
      case 'SCENE_BEAT_GENERATION':
        return '场景节拍';
      default:
        return featureType;
    }
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
      case 'duplicate':
        onDuplicate?.call();
        break;
      case 'review':
        onReview?.call();
        break;
      case 'publish':
        onPublish?.call();
        break;
      case 'verify':
        onSetVerified?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
    }
  }

  String _featureTypeToString(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return 'SCENE_TO_SUMMARY';
      case AIFeatureType.summaryToScene:
        return 'SUMMARY_TO_SCENE';
      case AIFeatureType.textExpansion:
        return 'TEXT_EXPANSION';
      case AIFeatureType.textRefactor:
        return 'TEXT_REFACTOR';
      case AIFeatureType.textSummary:
        return 'TEXT_SUMMARY';
      case AIFeatureType.aiChat:
        return 'AI_CHAT';
      case AIFeatureType.novelGeneration:
        return 'NOVEL_GENERATION';
      case AIFeatureType.novelCompose:
        return 'NOVEL_COMPOSE';
      case AIFeatureType.professionalFictionContinuation:
        return 'PROFESSIONAL_FICTION_CONTINUATION';
      case AIFeatureType.sceneBeatGeneration:
        return 'SCENE_BEAT_GENERATION';
      case AIFeatureType.settingTreeGeneration:
        return 'SETTING_TREE_GENERATION';
      case AIFeatureType.settingGenerationTool:
        return 'SETTING_GENERATION_TOOL';
      case AIFeatureType.storyPlotContinuation:
        return 'STORY_PLOT_CONTINUATION';
      case AIFeatureType.knowledgeExtractionSetting:
        return 'KNOWLEDGE_EXTRACTION_SETTING';
      case AIFeatureType.knowledgeExtractionOutline:
        return 'KNOWLEDGE_EXTRACTION_OUTLINE';
    }
  }
}