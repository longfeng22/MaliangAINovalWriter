/// 引用块组件
/// Citation block widget

import 'package:flutter/material.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../config/constants.dart';
import '../../utils/responsive_utils.dart';

/// 引用块Widget
/// Citation block widget
/// 
/// 四种类型颜色区分（setting/chapter/outline/fragment）
/// Four types with color distinction
class CitationBlockWidget extends StatefulWidget {
  final CitationBlock block;
  final bool isDark;
  
  const CitationBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
  });
  
  @override
  State<CitationBlockWidget> createState() => _CitationBlockWidgetState();
}

class _CitationBlockWidgetState extends State<CitationBlockWidget> {
  int? _hoveredIndex;
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing2,
      ),
      child: Wrap(
        spacing: AgentChatThemeConfig.spacing,
        runSpacing: AgentChatThemeConfig.spacing,
        children: widget.block.citations.asMap().entries.map((entry) {
          final index = entry.key;
          final citation = entry.value;
          return _buildCitationBadge(context, citation, index, isCompact);
        }).toList(),
      ),
    );
  }
  
  Widget _buildCitationBadge(
    BuildContext context,
    Citation citation,
    int index,
    bool isCompact,
  ) {
    final badgeColor = _getCitationColor(citation.type);
    final isHovered = _hoveredIndex == index;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: Tooltip(
        message: citation.preview,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 10,
            vertical: isCompact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(isHovered ? 0.2 : 0.15),
            borderRadius: BorderRadius.circular(
              ResponsiveUtils.getBorderRadius(context) * 0.5,
            ),
            border: Border.all(
              color: badgeColor.withOpacity(isHovered ? 0.6 : 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 类型图标
              Icon(
                _getCitationIcon(citation.type),
                size: isCompact ? 12 : 14,
                color: badgeColor,
              ),
              SizedBox(width: AgentChatThemeConfig.spacing),
              // 编号
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${citation.number}',
                  style: TextStyle(
                    fontSize: isCompact ? 10 : 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (!isCompact) ...[
                SizedBox(width: AgentChatThemeConfig.spacing),
                // 预览文本（桌面端显示）
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    citation.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  /// 获取引用类型颜色
  /// Get citation type color
  Color _getCitationColor(String type) {
    switch (type) {
      case CitationType.setting:
        return AgentChatThemeConfig.citationSetting.toColor();
      case CitationType.chapter:
        return AgentChatThemeConfig.citationChapter.toColor();
      case CitationType.outline:
        return AgentChatThemeConfig.citationOutline.toColor();
      case CitationType.fragment:
        return AgentChatThemeConfig.citationFragment.toColor();
      default:
        return AgentChatThemeConfig.citationSetting.toColor();
    }
  }
  
  /// 获取引用类型图标
  /// Get citation type icon
  IconData _getCitationIcon(String type) {
    switch (type) {
      case CitationType.setting:
        return Icons.settings_outlined;
      case CitationType.chapter:
        return Icons.menu_book_outlined;
      case CitationType.outline:
        return Icons.list_alt_outlined;
      case CitationType.fragment:
        return Icons.description_outlined;
      default:
        return Icons.bookmark_outline;
    }
  }
}





