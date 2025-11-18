/// 工具摘要组件
/// Tool summary widget

import 'package:flutter/material.dart';
import '../models/message_block.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 工具摘要Widget
/// Tool summary widget
/// 
/// 显示工具调用统计（查看/CRUD计数）
/// Display tool invocation statistics (view/CRUD counts)
class ToolSummaryWidget extends StatelessWidget {
  final List<ToolSummaryItem> summary;
  final bool isDark;
  final Translations translations;
  
  const ToolSummaryWidget({
    super.key,
    required this.summary,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Container(
      margin: EdgeInsets.only(top: AgentChatThemeConfig.spacing2),
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing2 : AgentChatThemeConfig.spacing3,
      ),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightMuted,
          AgentChatThemeConfig.darkMuted,
          isDark,
        ).withOpacity(0.3),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context) * 0.5,
        ),
        border: Border.all(
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightBorder,
            AgentChatThemeConfig.darkBorder,
            isDark,
          ).withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: AgentChatThemeConfig.spacing2,
        runSpacing: AgentChatThemeConfig.spacing,
        children: summary.map((item) => _buildSummaryItem(
          context,
          item,
          isCompact,
        )).toList(),
      ),
    );
  }
  
  Widget _buildSummaryItem(
    BuildContext context,
    ToolSummaryItem item,
    bool isCompact,
  ) {
    final color = item.toolType == ToolType.view
        ? AgentChatThemeConfig.toolViewColor.toColor()
        : AgentChatThemeConfig.toolUpdateColor.toColor();
    
    final counts = <String>[];
    
    // 组装统计文本
    if (item.viewCount != null && item.viewCount! > 0) {
      counts.add(translations.viewCount(item.viewCount!));
    }
    if (item.created != null && item.created! > 0) {
      counts.add(translations.createCount(item.created!));
    }
    if (item.updated != null && item.updated! > 0) {
      counts.add(translations.updateCount(item.updated!));
    }
    if (item.deleted != null && item.deleted! > 0) {
      counts.add(translations.deleteCount(item.deleted!));
    }
    
    if (counts.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 10,
        vertical: isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context) * 0.4,
        ),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具图标
          Icon(
            item.toolType == ToolType.view
                ? Icons.visibility_outlined
                : Icons.edit_outlined,
            size: isCompact ? 12 : 14,
            color: color,
          ),
          SizedBox(width: 4),
          // 工具名称
          Text(
            item.toolName,
            style: TextStyle(
              fontSize: isCompact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          SizedBox(width: 4),
          // 统计数字
          Text(
            '(${counts.join(', ')})',
            style: TextStyle(
              fontSize: isCompact ? 10 : 11,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}





