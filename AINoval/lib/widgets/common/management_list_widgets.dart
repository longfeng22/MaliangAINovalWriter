import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 顶部标题栏（用于提示词/预设管理列表）
class ManagementListTopBar extends StatelessWidget {
  const ManagementListTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDark ? WebTheme.darkGrey600 : WebTheme.grey700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: WebTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  subtitle,
                  style: WebTheme.bodySmall.copyWith(
                    color: WebTheme.getSecondaryTextColor(context),
                    height: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 类型标签（System/Public/Custom）
class ManagementTypeChip extends StatelessWidget {
  const ManagementTypeChip({
    super.key,
    required this.type,
  });

  final String type;

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    Color backgroundColor;
    Color textColor;
    String displayText;

    switch (type) {
      case 'System':
        backgroundColor = isDark ? const Color(0xFF2C3E50) : const Color(0xFFE3F2FD);
        textColor = isDark ? const Color(0xFF74B9FF) : const Color(0xFF1565C0);
        displayText = '系统';
        break;
      case 'Public':
        backgroundColor = isDark ? const Color(0xFF2D5016) : const Color(0xFFE8F5E8);
        textColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
        displayText = '公开';
        break;
      case 'Custom':
        backgroundColor = isDark ? const Color(0xFF4A2C2A) : const Color(0xFFF3E5F5);
        textColor = isDark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2);
        displayText = '自定义';
        break;
      default:
        backgroundColor = isDark ? WebTheme.darkGrey200 : WebTheme.grey100;
        textColor = WebTheme.getSecondaryTextColor(context);
        displayText = type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        displayText,
        style: WebTheme.labelSmall.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

/// 通用管理列表项
class ManagementListItem extends StatelessWidget {
  const ManagementListItem({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.leftIcon,
    required this.leftIconColor,
    required this.leftIconBgColor,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.trailing,
    this.statusBadges,
    this.showQuickStar = false,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final IconData leftIcon;
  final Color leftIconColor;
  final Color leftIconBgColor;
  final String title;
  final String? subtitle;
  final List<String> tags;
  final Widget? trailing;
  final List<Widget>? statusBadges;
  final bool showQuickStar;

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? WebTheme.darkGrey200 : WebTheme.grey100)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isSelected
            ? Border.all(
                color: isDark ? WebTheme.darkGrey400 : WebTheme.grey400,
                width: 1,
              )
            : Border.all(color: Colors.transparent, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 左侧图标
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: leftIconBgColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    leftIcon,
                    size: 12,
                    color: leftIconColor,
                  ),
                ),
                const SizedBox(width: 12),
                // 主要内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: WebTheme.bodyMedium.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected
                                    ? WebTheme.getTextColor(context)
                                    : WebTheme.getTextColor(context, isPrimary: false),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (statusBadges != null && statusBadges!.isNotEmpty) ...[
                            ..._intersperse(statusBadges!, const SizedBox(width: 4)),
                          ],
                          if (showQuickStar) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF4A4A4A)
                                    : const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Icon(
                                Icons.star,
                                size: 10,
                                color: Color(0xFFFF8F00),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: WebTheme.bodySmall.copyWith(
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: tags.take(3).map((t) => _buildTag(context, t)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Widget> _intersperse(List<Widget> widgets, Widget spacer) {
    if (widgets.length <= 1) return widgets;
    final result = <Widget>[];
    for (int i = 0; i < widgets.length; i++) {
      result.add(widgets[i]);
      if (i != widgets.length - 1) result.add(spacer);
    }
    return result;
  }

  Widget _buildTag(BuildContext context, String tag) {
    final isDark = WebTheme.isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? WebTheme.darkGrey300 : WebTheme.grey200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tag,
        style: WebTheme.labelSmall.copyWith(
          color: WebTheme.getSecondaryTextColor(context),
          fontSize: 10,
        ),
      ),
    );
  }
}



