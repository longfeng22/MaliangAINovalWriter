/// 工具块组件
/// Tool block widget

import 'package:flutter/material.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../config/constants.dart';
import '../../utils/responsive_utils.dart';
import '../../utils/animation_utils.dart';
import '../../i18n/translations.dart';

/// 工具块Widget
/// Tool block widget
/// 
/// View类工具（蓝色）和CRUD类工具（绿/黄/红）
/// View tools (blue) and CRUD tools (green/yellow/red)
class ToolBlockWidget extends StatelessWidget {
  final ToolBlock block;
  final bool isDark;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onApply;
  final VoidCallback? onCancel;
  final Translations translations;
  
  const ToolBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
    this.onToggleExpand,
    this.onApply,
    this.onCancel,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    final toolColor = _getToolColor();
    final isRunning = block.status == ToolStatus.running;
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing2,
      ),
      decoration: BoxDecoration(
        color: toolColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
        border: Border.all(
          color: toolColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 工具头部
          _buildToolHeader(context, toolColor, isRunning, isCompact),
          
          // 工具详情（CRUD工具且已展开）
          if (block.toolType == ToolType.crud && 
              block.details != null && 
              (block.isExpanded ?? false))
            AnimationUtils.expandCollapse(
              isExpanded: true,
              child: _buildToolDetails(context, isCompact),
            ),
          
          // CRUD工具的操作按钮（已完成且未应用）
          if (block.toolType == ToolType.crud &&
              block.status == ToolStatus.complete &&
              !(block.applied ?? false) &&
              !isCompact)
            _buildActionButtons(context, toolColor),
        ],
      ),
    );
  }
  
  /// 构建工具头部
  Widget _buildToolHeader(
    BuildContext context,
    Color toolColor,
    bool isRunning,
    bool isCompact,
  ) {
    return InkWell(
      onTap: block.toolType == ToolType.crud && block.details != null
          ? onToggleExpand
          : null,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ResponsiveUtils.getBorderRadius(context)),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        ),
        child: Row(
          children: [
            // 工具图标
            if (isRunning)
              AnimationUtils.loadingIndicator(
                size: isCompact ? 18 : 20,
                color: toolColor,
              )
            else
              Icon(
                _getToolIcon(),
                size: isCompact ? 18 : 20,
                color: toolColor,
              ),
            
            SizedBox(width: AgentChatThemeConfig.spacing2),
            
            // 工具名称
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.toolName,
                    style: TextStyle(
                      fontSize: isCompact ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: toolColor,
                    ),
                  ),
                  if (block.operation != null) ...[
                    SizedBox(height: 2),
                    Text(
                      _getOperationText(block.operation!),
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        color: toolColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // 状态和时长
            if (block.status == ToolStatus.complete && block.duration != null) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AgentChatThemeConfig.spacing2,
                  vertical: AgentChatThemeConfig.spacing,
                ),
                decoration: BoxDecoration(
                  color: toolColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(
                    ResponsiveUtils.getBorderRadius(context) * 0.5,
                  ),
                ),
                child: Text(
                  block.duration!,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    color: toolColor,
                  ),
                ),
              ),
            ],
            
            // 展开图标（CRUD工具且有详情）
            if (block.toolType == ToolType.crud && block.details != null) ...[
              SizedBox(width: AgentChatThemeConfig.spacing),
              AnimationUtils.rotationTransition(
                rotated: block.isExpanded ?? false,
                turns: 0.5,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: isCompact ? 20 : 24,
                  color: toolColor,
                ),
              ),
            ],
            
            // 已应用标记
            if (block.applied ?? false) ...[
              SizedBox(width: AgentChatThemeConfig.spacing),
              Icon(
                Icons.check_circle,
                size: isCompact ? 18 : 20,
                color: AgentChatThemeConfig.toolCreateColor.toColor(),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// 构建工具详情
  Widget _buildToolDetails(BuildContext context, bool isCompact) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        0,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _getToolColor().withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: AgentChatThemeConfig.spacing2),
          
          // 标题
          if (block.details!.title.isNotEmpty) ...[
            Text(
              block.details!.title,
              style: TextStyle(
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: AgentChatThemeConfig.getColor(
                  AgentChatThemeConfig.lightForeground,
                  AgentChatThemeConfig.darkForeground,
                  isDark,
                ),
              ),
            ),
            SizedBox(height: AgentChatThemeConfig.spacing2),
          ],
          
          // 内容
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(AgentChatThemeConfig.spacing3),
            decoration: BoxDecoration(
              color: AgentChatThemeConfig.getColor(
                AgentChatThemeConfig.lightMuted,
                AgentChatThemeConfig.darkMuted,
                isDark,
              ),
              borderRadius: BorderRadius.circular(
                ResponsiveUtils.getBorderRadius(context) * 0.5,
              ),
            ),
            child: SelectableText(
              block.details!.content,
              style: TextStyle(
                fontSize: isCompact ? 12 : 13,
                fontFamily: AgentChatThemeConfig.fontMono,
                height: 1.5,
                color: AgentChatThemeConfig.getColor(
                  AgentChatThemeConfig.lightCardForeground,
                  AgentChatThemeConfig.darkCardForeground,
                  isDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建操作按钮
  Widget _buildActionButtons(BuildContext context, Color toolColor) {
    return Container(
      padding: EdgeInsets.all(AgentChatThemeConfig.spacing3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: toolColor.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 应用按钮
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onApply,
              icon: Icon(Icons.check, size: 16),
              label: Text(translations.apply),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgentChatThemeConfig.toolCreateColor.toColor(),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(
                  vertical: AgentChatThemeConfig.spacing2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveUtils.getBorderRadius(context) * 0.5,
                  ),
                ),
              ),
            ),
          ),
          
          SizedBox(width: AgentChatThemeConfig.spacing2),
          
          // 取消按钮
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: Icon(Icons.close, size: 16),
              label: Text(translations.cancel),
              style: OutlinedButton.styleFrom(
                foregroundColor: AgentChatThemeConfig.getColor(
                  AgentChatThemeConfig.lightMutedForeground,
                  AgentChatThemeConfig.darkMutedForeground,
                  isDark,
                ),
                side: BorderSide(
                  color: AgentChatThemeConfig.getColor(
                    AgentChatThemeConfig.lightBorder,
                    AgentChatThemeConfig.darkBorder,
                    isDark,
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: AgentChatThemeConfig.spacing2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveUtils.getBorderRadius(context) * 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 获取工具颜色
  Color _getToolColor() {
    if (block.toolType == ToolType.view) {
      return AgentChatThemeConfig.toolViewColor.toColor();
    } else {
      // CRUD工具根据操作类型返回不同颜色
      switch (block.operation) {
        case OperationType.create:
          return AgentChatThemeConfig.toolCreateColor.toColor();
        case OperationType.update:
          return AgentChatThemeConfig.toolUpdateColor.toColor();
        case OperationType.delete:
          return AgentChatThemeConfig.toolDeleteColor.toColor();
        default:
          return AgentChatThemeConfig.toolViewColor.toColor();
      }
    }
  }
  
  /// 获取工具图标
  IconData _getToolIcon() {
    if (block.toolType == ToolType.view) {
      return Icons.visibility_outlined;
    } else {
      switch (block.operation) {
        case OperationType.create:
          return Icons.add_circle_outline;
        case OperationType.update:
          return Icons.edit_outlined;
        case OperationType.delete:
          return Icons.delete_outline;
        default:
          return Icons.build_outlined;
      }
    }
  }
  
  /// 获取操作文本
  String _getOperationText(String operation) {
    switch (operation) {
      case OperationType.create:
        return translations.operationCreate;
      case OperationType.update:
        return translations.operationUpdate;
      case OperationType.delete:
        return translations.operationDelete;
      case OperationType.view:
        return translations.operationView;
      default:
        return operation;
    }
  }
}





