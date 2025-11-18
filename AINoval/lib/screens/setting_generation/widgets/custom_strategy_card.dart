import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/admin/review_models.dart';

/// 自定义策略卡片
class CustomStrategyCard extends StatelessWidget {
  final Map<String, dynamic> strategy;
  final bool isEditable;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const CustomStrategyCard({
    super.key,
    required this.strategy,
    this.isEditable = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    
    final name = strategy['name'] as String? ?? '未命名策略';
    final description = strategy['description'] as String? ?? '';
    final createdAt = strategy['createdAt'] as String?;
    final updatedAt = strategy['updatedAt'] as String?;
    final reviewStatus = strategy['reviewStatus'] as String? ?? 'DRAFT';
    final isPublic = strategy['isPublic'] as bool? ?? false;
    final expectedRootNodes = strategy['expectedRootNodes'] as int? ?? 0;
    final maxDepth = strategy['maxDepth'] as int? ?? 0;
    final tags = (strategy['tags'] as List?)?.cast<String>() ?? <String>[];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusChip(theme, reviewStatus, isPublic),
                  if (isEditable) ...[
                    const SizedBox(width: 8),
                    _buildActionButtons(context),
                  ],
                ],
              ),
              
              // 描述
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              // 配置信息
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    theme,
                    icon: Icons.account_tree,
                    label: '$expectedRootNodes 个根节点',
                  ),
                  _buildInfoChip(
                    theme,
                    icon: Icons.layers,
                    label: '深度 $maxDepth',
                  ),
                ],
              ),
              
              // 标签
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags.take(5).map((tag) => Chip(
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
              ],
              
              // 时间信息
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '创建于 ${createdAt != null ? dateFormat.format(DateTime.parse(createdAt)) : '未知'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                  if (updatedAt != null && updatedAt != createdAt) ...[
                    const SizedBox(width: 12),
                    Text(
                      '• 更新于 ${dateFormat.format(DateTime.parse(updatedAt))}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, String reviewStatus, bool isPublic) {
    Color color;
    String label;
    IconData icon;
    
    if (isPublic) {
      color = Colors.green;
      label = '已发布';
      icon = Icons.public;
    } else {
      switch (reviewStatus) {
        case ReviewStatusConstants.draft:
          color = Colors.grey;
          label = '草稿';
          icon = Icons.edit;
          break;
        case ReviewStatusConstants.pending:
          color = Colors.orange;
          label = '待审核';
          icon = Icons.pending;
          break;
        case ReviewStatusConstants.approved:
          color = Colors.green;
          label = '已通过';
          icon = Icons.check_circle;
          break;
        case ReviewStatusConstants.rejected:
          color = Colors.red;
          label = '已拒绝';
          icon = Icons.cancel;
          break;
        default:
          color = Colors.grey;
          label = reviewStatus;
          icon = Icons.info;
      }
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit),
              SizedBox(width: 8),
              Text('编辑'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(ThemeData theme, {required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}


