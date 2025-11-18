import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../utils/web_theme.dart';

/// 增强模板卡片组件
class EnhancedTemplateCard extends StatelessWidget {
  final EnhancedUserPromptTemplate template;
  final bool isSelected;
  final bool batchMode;
  final bool showUserInfo; // 是否显示用户信息（用户模板模式）
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReview;
  final VoidCallback? onToggleVerified;
  final VoidCallback? onTogglePublish;
  final VoidCallback? onViewStats;
  final VoidCallback? onViewDetails;
  final VoidCallback? onDuplicate;
  final ValueChanged<bool>? onSelectionChanged;

  const EnhancedTemplateCard({
    Key? key,
    required this.template,
    this.isSelected = false,
    this.batchMode = false,
    this.showUserInfo = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onReview,
    this.onToggleVerified,
    this.onTogglePublish,
    this.onViewStats,
    this.onViewDetails,
    this.onDuplicate,
    this.onSelectionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: WebTheme.getCardColor(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (batchMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: onSelectionChanged != null ? (value) => onSelectionChanged!(value ?? false) : null,
                      ),
                    ),
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: WebTheme.getTextColor(context),
                                ),
                              ),
                            ),
                            _buildStatusBadges(),
                          ],
                        ),
                        if (template.description?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              template.description!,
                              style: TextStyle(
                                color: WebTheme.getTextColor(context).withOpacity(0.7),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!batchMode)
                    PopupMenuButton<String>(
                      onSelected: _handleMenuAction,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'duplicate', child: Text('复制为新模板')),
                        if (template.isPublic == true && template.isVerified != true)
                          const PopupMenuItem(value: 'review', child: Text('审核')),
                        PopupMenuItem(
                          value: 'verify',
                          child: Text(template.isVerified == true ? '取消认证' : '设为认证'),
                        ),
                        PopupMenuItem(
                          value: 'publish',
                          child: Text(template.isPublic == true ? '取消发布' : '发布'),
                        ),
                        const PopupMenuItem(value: 'stats', child: Text('统计信息')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTemplateInfo(),
              const SizedBox(height: 12),
              _buildTemplateStats(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadges() {
    return Row(
      children: [
        if (template.isVerified == true)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green),
            ),
            child: const Text(
              '已认证',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (template.isPublic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue),
            ),
            child: const Text(
              '公开',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (template.isPublic && !template.isVerified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange),
            ),
            child: const Text(
              '待审核',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (!template.isPublic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey),
            ),
            child: const Text(
              '私有',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTemplateInfo() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildInfoItem(Icons.category, '功能类型', template.featureType.displayName),
        _buildInfoItem(Icons.language, '语言', template.language ?? 'zh'),
        if (template.tags.isNotEmpty)
          _buildInfoItem(Icons.label, '标签', template.tags.take(3).join(', ')),
        if (showUserInfo && template.userId.isNotEmpty)
          _buildInfoItem(Icons.account_circle, '用户ID', _truncateUserId(template.userId)),
        _buildInfoItem(Icons.person, '作者', template.authorId ?? '未知'),
        if (template.version != null)
          _buildInfoItem(Icons.history, '版本', template.version.toString()),
      ],
    );
  }
  
  String _truncateUserId(String userId) {
    if (userId.length > 12) {
      return '${userId.substring(0, 8)}...';
    }
    return userId;
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateStats() {
    return Row(
      children: [
        _buildStatChip(
          icon: Icons.play_arrow,
          label: '使用',
          value: template.usageCount.toString(),
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          icon: Icons.favorite,
          label: '收藏',
          value: (template.favoriteCount ?? 0).toString(),
        ),
        const SizedBox(width: 8),
        if (template.rating > 0)
          _buildStatChip(
            icon: Icons.star,
            label: '评分',
            value: template.rating.toStringAsFixed(1),
          ),
        const Spacer(),
        Text(
          '创建于 ${_formatDate(template.createdAt)}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            ' $label',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'duplicate':
        onDuplicate?.call();
        break;
      case 'review':
        onReview?.call();
        break;
      case 'verify':
        onToggleVerified?.call();
        break;
      case 'publish':
        onTogglePublish?.call();
        break;
      case 'stats':
        onViewStats?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
    }
  }
}