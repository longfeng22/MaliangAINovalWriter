/// 引用栏组件
/// Reference bar widget

import 'package:flutter/material.dart';
import '../models/reference.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 引用栏Widget
/// Reference bar widget
/// 
/// 引用列表横向滚动，悬停显示删除按钮
/// Horizontal scrolling reference list with hover-to-show delete button
class ReferenceBar extends StatelessWidget {
  final List<Reference> references;
  final Function(String id)? onRemove;
  final bool isDark;
  final Translations translations;
  
  const ReferenceBar({
    super.key,
    required this.references,
    this.onRemove,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    if (references.isEmpty) return const SizedBox.shrink();
    
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.getSpacing(context),
        vertical: AgentChatThemeConfig.spacing2,
      ),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightCard,
          AgentChatThemeConfig.darkCard,
          isDark,
        ),
        border: Border(
          bottom: BorderSide(
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightBorder,
              AgentChatThemeConfig.darkBorder,
              isDark,
            ),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Padding(
            padding: EdgeInsets.only(
              left: AgentChatThemeConfig.spacing,
              bottom: AgentChatThemeConfig.spacing,
            ),
            child: Text(
              translations.references,
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: AgentChatThemeConfig.getColor(
                  AgentChatThemeConfig.lightMutedForeground,
                  AgentChatThemeConfig.darkMutedForeground,
                  isDark,
                ),
              ),
            ),
          ),
          
          // 引用列表
          SizedBox(
            height: isCompact ? 32 : 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: references.length,
              separatorBuilder: (context, index) => SizedBox(
                width: AgentChatThemeConfig.spacing,
              ),
              itemBuilder: (context, index) {
                final reference = references[index];
                return _ReferenceChip(
                  reference: reference,
                  onRemove: onRemove != null ? () => onRemove!(reference.id) : null,
                  isDark: isDark,
                  isCompact: isCompact,
                  translations: translations,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 引用芯片Widget
/// Reference chip widget
class _ReferenceChip extends StatefulWidget {
  final Reference reference;
  final VoidCallback? onRemove;
  final bool isDark;
  final bool isCompact;
  final Translations translations;
  
  const _ReferenceChip({
    required this.reference,
    this.onRemove,
    required this.isDark,
    required this.isCompact,
    required this.translations,
  });
  
  @override
  State<_ReferenceChip> createState() => _ReferenceChipState();
}

class _ReferenceChipState extends State<_ReferenceChip> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    final chipColor = _getReferenceColor(widget.reference.type);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: widget.isCompact ? 10 : 12,
          vertical: widget.isCompact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: chipColor.withOpacity(_isHovered ? 0.2 : 0.15),
          borderRadius: BorderRadius.circular(
            ResponsiveUtils.getBorderRadius(context) * 0.5,
          ),
          border: Border.all(
            color: chipColor.withOpacity(_isHovered ? 0.6 : 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 类型图标
            Icon(
              _getReferenceIcon(widget.reference.type),
              size: widget.isCompact ? 14 : 16,
              color: chipColor,
            ),
            SizedBox(width: AgentChatThemeConfig.spacing),
            
            // 引用信息
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.isCompact ? 120 : 180,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_getTypeText(widget.reference.type)} ${widget.reference.number}',
                    style: TextStyle(
                      fontSize: widget.isCompact ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      color: chipColor,
                    ),
                  ),
                  Text(
                    widget.reference.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.isCompact ? 10 : 11,
                      color: chipColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            
            // 删除按钮（悬停显示）
            if (_isHovered && widget.onRemove != null) ...[
              SizedBox(width: AgentChatThemeConfig.spacing),
              InkWell(
                onTap: widget.onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: chipColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// 获取引用类型颜色
  Color _getReferenceColor(String type) {
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
  IconData _getReferenceIcon(String type) {
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
  
  /// 获取类型文本
  String _getTypeText(String type) {
    switch (type) {
      case CitationType.setting:
        return widget.translations.refSetting;
      case CitationType.chapter:
        return widget.translations.refChapter;
      case CitationType.outline:
        return widget.translations.refOutline;
      case CitationType.fragment:
        return widget.translations.refFragment;
      default:
        return type;
    }
  }
}





