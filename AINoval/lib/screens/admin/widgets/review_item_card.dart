/// 审核项卡片组件
/// 显示待审核项的基本信息

import 'package:flutter/material.dart';
import '../../../models/admin/review_models.dart';
import '../../../utils/date_formatter.dart';

class ReviewItemCard extends StatelessWidget {
  final ReviewItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectChanged;

  const ReviewItemCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
            ? theme.colorScheme.primary
            : (isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // 选择框
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => onSelectChanged(value ?? false),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 16),

                // 类型图标
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getTypeColor(item.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getTypeIcon(item.type),
                    color: _getTypeColor(item.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // 主要信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(item.status, isDark),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(
                            icon: Icons.category_outlined,
                            label: item.type.displayName,
                            isDark: isDark,
                          ),
                          if (item.featureType != null)
                            _buildInfoChip(
                              icon: Icons.functions_rounded,
                              label: item.featureTypeDisplay,
                              isDark: isDark,
                              color: const Color(0xFF5856D6),
                            ),
                          if (item.authorName != null)
                            _buildInfoChip(
                              icon: Icons.person_outline,
                              label: item.authorName!,
                              isDark: isDark,
                            ),
                          _buildInfoChip(
                            icon: Icons.access_time,
                            label: _formatDate(item.submittedAt ?? item.createdAt),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // 操作按钮
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ReviewStatus status, bool isDark) {
    Color color;
    switch (status) {
      case ReviewStatus.pending:
        color = const Color(0xFFFF9500);
        break;
      case ReviewStatus.approved:
        color = const Color(0xFF34C759);
        break;
      case ReviewStatus.rejected:
        color = const Color(0xFFFF3B30);
        break;
      case ReviewStatus.draft:
        color = const Color(0xFF8E8E93);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.emoji,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required bool isDark,
    Color? color,
  }) {
    final chipColor = color ?? (isDark ? Colors.white54 : const Color(0xFF64748B));
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color != null 
          ? color.withOpacity(0.1)
          : (isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(6),
        border: color != null ? Border.all(color: color.withOpacity(0.3), width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: chipColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(ReviewItemType type) {
    switch (type) {
      case ReviewItemType.strategy:
        return Icons.psychology_outlined;
      case ReviewItemType.enhancedTemplate:
        return Icons.auto_awesome_outlined;
      case ReviewItemType.publicTemplate:
        return Icons.article_outlined;
      case ReviewItemType.userContent:
        return Icons.description_outlined;
    }
  }

  Color _getTypeColor(ReviewItemType type) {
    switch (type) {
      case ReviewItemType.strategy:
        return const Color(0xFF5856D6);
      case ReviewItemType.enhancedTemplate:
        return const Color(0xFFFF9500);
      case ReviewItemType.publicTemplate:
        return const Color(0xFF34C759);
      case ReviewItemType.userContent:
        return const Color(0xFF007AFF);
    }
  }

  String _formatDate(DateTime date) {
    // 使用公共的时间格式化函数
    return DateFormatter.formatRelative(date);
  }
}

