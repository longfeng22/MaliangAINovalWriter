/// 工具批准块组件
/// Tool approval block widget

import 'package:flutter/material.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../config/constants.dart';
import '../../utils/responsive_utils.dart';
import '../../i18n/translations.dart';

/// 工具批准块Widget
/// Tool approval block widget
/// 
/// 人工批准界面，显示操作详情，支持批准/拒绝
/// Human approval interface with operation details and approve/reject actions
class ApprovalBlockWidget extends StatefulWidget {
  final ToolApprovalBlock block;
  final bool isDark;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final Translations translations;
  
  const ApprovalBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
    this.onApprove,
    this.onReject,
    required this.translations,
  });
  
  @override
  State<ApprovalBlockWidget> createState() => _ApprovalBlockWidgetState();
}

class _ApprovalBlockWidgetState extends State<ApprovalBlockWidget> {
  bool _showDetails = false;
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    final warningColor = AgentChatThemeConfig.approvalBorderColor.toColor();
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing2,
      ),
      decoration: BoxDecoration(
        color: warningColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
        border: Border.all(
          color: warningColor,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 警告头部
          Container(
            padding: EdgeInsets.all(
              isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
            ),
            decoration: BoxDecoration(
              color: warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(ResponsiveUtils.getBorderRadius(context) - 2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: isCompact ? 20 : 24,
                  color: warningColor,
                ),
                SizedBox(width: AgentChatThemeConfig.spacing2),
                Expanded(
                  child: Text(
                    widget.translations.awaitingApproval,
                    style: TextStyle(
                      fontSize: isCompact ? 14 : 15,
                      fontWeight: FontWeight.bold,
                      color: warningColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 工具信息和描述
          Padding(
            padding: EdgeInsets.all(
              isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 工具名称和操作
                Row(
                  children: [
                    Icon(
                      _getOperationIcon(widget.block.operation),
                      size: isCompact ? 18 : 20,
                      color: _getOperationColor(widget.block.operation),
                    ),
                    SizedBox(width: AgentChatThemeConfig.spacing),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 14,
                            color: AgentChatThemeConfig.getColor(
                              AgentChatThemeConfig.lightForeground,
                              AgentChatThemeConfig.darkForeground,
                              widget.isDark,
                            ),
                          ),
                          children: [
                            TextSpan(
                              text: widget.block.toolName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: _getOperationText(widget.block.operation),
                              style: TextStyle(
                                color: _getOperationColor(widget.block.operation),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: AgentChatThemeConfig.spacing2),
                
                // 描述
                Text(
                  widget.block.description,
                  style: TextStyle(
                    fontSize: isCompact ? 13 : 14,
                    height: 1.5,
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightCardForeground,
                      AgentChatThemeConfig.darkCardForeground,
                      widget.isDark,
                    ),
                  ),
                ),
                
                // 查看详情按钮（如果有详情）
                if (widget.block.details != null) ...[
                  SizedBox(height: AgentChatThemeConfig.spacing2),
                  InkWell(
                    onTap: () => setState(() => _showDetails = !_showDetails),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showDetails
                              ? widget.translations.hideDetails
                              : widget.translations.viewDetails,
                          style: TextStyle(
                            fontSize: isCompact ? 12 : 13,
                            fontWeight: FontWeight.w500,
                            color: AgentChatThemeConfig.getColor(
                              AgentChatThemeConfig.lightPrimary,
                              AgentChatThemeConfig.darkPrimary,
                              widget.isDark,
                            ),
                          ),
                        ),
                        SizedBox(width: AgentChatThemeConfig.spacing),
                        Icon(
                          _showDetails
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 16,
                          color: AgentChatThemeConfig.getColor(
                            AgentChatThemeConfig.lightPrimary,
                            AgentChatThemeConfig.darkPrimary,
                            widget.isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // 详情内容
                if (_showDetails && widget.block.details != null) ...[
                  SizedBox(height: AgentChatThemeConfig.spacing2),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(AgentChatThemeConfig.spacing3),
                    decoration: BoxDecoration(
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightMuted,
                        AgentChatThemeConfig.darkMuted,
                        widget.isDark,
                      ),
                      borderRadius: BorderRadius.circular(
                        ResponsiveUtils.getBorderRadius(context) * 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.block.details!.title.isNotEmpty) ...[
                          Text(
                            widget.block.details!.title,
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 13,
                              fontWeight: FontWeight.w600,
                              color: AgentChatThemeConfig.getColor(
                                AgentChatThemeConfig.lightForeground,
                                AgentChatThemeConfig.darkForeground,
                                widget.isDark,
                              ),
                            ),
                          ),
                          SizedBox(height: AgentChatThemeConfig.spacing),
                        ],
                        SelectableText(
                          widget.block.details!.content,
                          style: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            fontFamily: AgentChatThemeConfig.fontMono,
                            height: 1.5,
                            color: AgentChatThemeConfig.getColor(
                              AgentChatThemeConfig.lightCardForeground,
                              AgentChatThemeConfig.darkCardForeground,
                              widget.isDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // 操作按钮
          Container(
            padding: EdgeInsets.all(
              isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: warningColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // 批准按钮
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onApprove,
                    icon: Icon(Icons.check_circle_outline, size: isCompact ? 16 : 18),
                    label: Text(widget.translations.approve),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgentChatThemeConfig.toolCreateColor.toColor(),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        vertical: isCompact 
                            ? AgentChatThemeConfig.spacing2 
                            : AgentChatThemeConfig.spacing3,
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
                
                // 拒绝按钮
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onReject,
                    icon: Icon(Icons.cancel_outlined, size: isCompact ? 16 : 18),
                    label: Text(widget.translations.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AgentChatThemeConfig.toolDeleteColor.toColor(),
                      side: BorderSide(
                        color: AgentChatThemeConfig.toolDeleteColor.toColor(),
                        width: 1.5,
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: isCompact 
                            ? AgentChatThemeConfig.spacing2 
                            : AgentChatThemeConfig.spacing3,
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
          ),
        ],
      ),
    );
  }
  
  /// 获取操作图标
  IconData _getOperationIcon(String operation) {
    switch (operation) {
      case OperationType.create:
        return Icons.add_circle_outline;
      case OperationType.update:
        return Icons.edit_outlined;
      case OperationType.delete:
        return Icons.delete_outline;
      case OperationType.view:
        return Icons.visibility_outlined;
      default:
        return Icons.help_outline;
    }
  }
  
  /// 获取操作颜色
  Color _getOperationColor(String operation) {
    switch (operation) {
      case OperationType.create:
        return AgentChatThemeConfig.toolCreateColor.toColor();
      case OperationType.update:
        return AgentChatThemeConfig.toolUpdateColor.toColor();
      case OperationType.delete:
        return AgentChatThemeConfig.toolDeleteColor.toColor();
      case OperationType.view:
        return AgentChatThemeConfig.toolViewColor.toColor();
      default:
        return AgentChatThemeConfig.toolViewColor.toColor();
    }
  }
  
  /// 获取操作文本
  String _getOperationText(String operation) {
    switch (operation) {
      case OperationType.create:
        return widget.translations.operationCreate;
      case OperationType.update:
        return widget.translations.operationUpdate;
      case OperationType.delete:
        return widget.translations.operationDelete;
      case OperationType.view:
        return widget.translations.operationView;
      default:
        return operation;
    }
  }
}





