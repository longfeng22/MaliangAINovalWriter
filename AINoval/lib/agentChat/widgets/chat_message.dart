/// 聊天消息组件
/// Chat message widget

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message.dart';
import '../models/message_block.dart';
import '../models/agent.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';
import 'blocks/blocks.dart';
import 'tool_summary.dart';

/// 聊天消息Widget
/// Chat message widget
/// 
/// 支持用户/AI/Supervisor角色，渲染所有块类型，消息操作等
/// Supports user/AI/supervisor roles, renders all block types, message actions, etc.
class ChatMessageWidget extends StatefulWidget {
  final Message message;
  final Agent? currentAgent;
  final bool isDark;
  final Translations translations;
  
  // 回调函数
  final Function(int blockIndex)? onToolToggleExpand;
  final Function(int blockIndex)? onToolApply;
  final Function(int blockIndex)? onToolCancel;
  final Function(int blockIndex)? onThinkingToggle;
  final Function(int blockIndex)? onToolApprove;
  final Function(int blockIndex)? onToolReject;
  final VoidCallback? onRollback;
  final Function(String newContent)? onEdit;
  final VoidCallback? onCopy;
  
  const ChatMessageWidget({
    super.key,
    required this.message,
    this.currentAgent,
    this.isDark = false,
    required this.translations,
    this.onToolToggleExpand,
    this.onToolApply,
    this.onToolCancel,
    this.onThinkingToggle,
    this.onToolApprove,
    this.onToolReject,
    this.onRollback,
    this.onEdit,
    this.onCopy,
  });
  
  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  bool _isHovered = false;
  bool _isEditing = false;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  
  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveUtils.getSpacing(context),
          vertical: AgentChatThemeConfig.spacing3,
        ),
        decoration: BoxDecoration(
          color: _getMessageBackgroundColor(),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像
            _buildAvatar(isCompact),
            
            SizedBox(width: AgentChatThemeConfig.spacing2),
            
            // 消息内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 消息头部（名称 + 时间 + 操作按钮）
                  _buildMessageHeader(isCompact),
                  
                  SizedBox(height: AgentChatThemeConfig.spacing),
                  
                  // 消息内容（编辑模式或正常显示）
                  if (_isEditing)
                    _buildEditMode(isCompact)
                  else
                    _buildMessageContent(isCompact),
                  
                  // 工具摘要（如果有）
                  if (widget.message.toolSummary != null &&
                      widget.message.toolSummary!.isNotEmpty)
                    ToolSummaryWidget(
                      summary: widget.message.toolSummary!,
                      isDark: widget.isDark,
                      translations: widget.translations,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建头像
  Widget _buildAvatar(bool isCompact) {
    final avatarSize = ResponsiveUtils.getAvatarSize(context);
    final avatarColor = _getAvatarColor();
    final avatarText = _getAvatarText();
    
    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        avatarText,
        style: TextStyle(
          fontSize: isCompact ? 16 : 18,
        ),
      ),
    );
  }
  
  /// 构建消息头部
  Widget _buildMessageHeader(bool isCompact) {
    return Row(
      children: [
        // 名称/智能体
        Expanded(
          child: Row(
            children: [
              Text(
                _getDisplayName(),
                style: TextStyle(
                  fontSize: isCompact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: AgentChatThemeConfig.getColor(
                    AgentChatThemeConfig.lightForeground,
                    AgentChatThemeConfig.darkForeground,
                    widget.isDark,
                  ),
                ),
              ),
              if (widget.message.agentName != null) ...[
                SizedBox(width: AgentChatThemeConfig.spacing),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightPrimary,
                      AgentChatThemeConfig.darkPrimary,
                      widget.isDark,
                    ).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.message.agentName!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightPrimary,
                        AgentChatThemeConfig.darkPrimary,
                        widget.isDark,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // 时间戳
        if (widget.message.timestamp != null) ...[
          Text(
            widget.message.timestamp!,
            style: TextStyle(
              fontSize: isCompact ? 11 : 12,
              color: AgentChatThemeConfig.getColor(
                AgentChatThemeConfig.lightMutedForeground,
                AgentChatThemeConfig.darkMutedForeground,
                widget.isDark,
              ),
            ),
          ),
        ],
        
        // 操作按钮（悬停显示）
        if (_isHovered && !isCompact && !_isEditing) ...[
          SizedBox(width: AgentChatThemeConfig.spacing),
          _buildActionButtons(),
        ],
      ],
    );
  }
  
  /// 构建操作按钮
  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 复制按钮
        if (widget.onCopy != null)
          _ActionButton(
            icon: Icons.content_copy,
            tooltip: widget.translations.copyMessage,
            onPressed: widget.onCopy!,
          ),
        
        // 编辑按钮（仅用户消息）
        if (widget.message.isUser && widget.onEdit != null) ...[
          SizedBox(width: 4),
          _ActionButton(
            icon: Icons.edit,
            tooltip: widget.translations.edit,
            onPressed: _enterEditMode,
          ),
        ],
        
        // 回退按钮
        if (widget.onRollback != null) ...[
          SizedBox(width: 4),
          _ActionButton(
            icon: Icons.history,
            tooltip: widget.translations.rollback,
            onPressed: widget.onRollback!,
          ),
        ],
      ],
    );
  }
  
  /// 构建编辑模式
  Widget _buildEditMode(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 编辑框
        TextField(
          controller: _editController,
          focusNode: _editFocusNode,
          maxLines: ResponsiveUtils.getInputMaxLines(context),
          decoration: InputDecoration(
            hintText: widget.translations.inputPlaceholder,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                ResponsiveUtils.getBorderRadius(context) * 0.5,
              ),
            ),
          ),
          onSubmitted: (_) => _saveEdit(),
        ),
        
        SizedBox(height: AgentChatThemeConfig.spacing2),
        
        // 编辑按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancelEdit,
              child: Text(widget.translations.cancel),
            ),
            SizedBox(width: AgentChatThemeConfig.spacing),
            ElevatedButton(
              onPressed: _saveEdit,
              child: Text(widget.translations.save),
            ),
          ],
        ),
      ],
    );
  }
  
  /// 构建消息内容
  Widget _buildMessageContent(bool isCompact) {
    return GestureDetector(
      onDoubleTap: widget.message.isUser && widget.onEdit != null 
          ? _enterEditMode 
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.message.blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;
          return _buildBlock(block, index, isCompact);
        }).toList(),
      ),
    );
  }
  
  /// 构建单个块
  Widget _buildBlock(MessageBlock block, int index, bool isCompact) {
    if (block is TextBlock) {
      return TextBlockWidget(
        block: block,
        isDark: widget.isDark,
      );
    } else if (block is CitationBlock) {
      return CitationBlockWidget(
        block: block,
        isDark: widget.isDark,
      );
    } else if (block is ThinkingBlock) {
      return ThinkingBlockWidget(
        block: block,
        isDark: widget.isDark,
        onToggle: widget.onThinkingToggle != null 
            ? () => widget.onThinkingToggle!(index)
            : null,
        translations: widget.translations,
      );
    } else if (block is ToolBlock) {
      return ToolBlockWidget(
        block: block,
        isDark: widget.isDark,
        onToggleExpand: widget.onToolToggleExpand != null
            ? () => widget.onToolToggleExpand!(index)
            : null,
        onApply: widget.onToolApply != null
            ? () => widget.onToolApply!(index)
            : null,
        onCancel: widget.onToolCancel != null
            ? () => widget.onToolCancel!(index)
            : null,
        translations: widget.translations,
      );
    } else if (block is ToolApprovalBlock) {
      return ApprovalBlockWidget(
        block: block,
        isDark: widget.isDark,
        onApprove: widget.onToolApprove != null
            ? () => widget.onToolApprove!(index)
            : null,
        onReject: widget.onToolReject != null
            ? () => widget.onToolReject!(index)
            : null,
        translations: widget.translations,
      );
    } else if (block is TaskAssignmentBlock) {
      return TaskAssignmentBlockWidget(
        block: block,
        isDark: widget.isDark,
        translations: widget.translations,
      );
    }
    return const SizedBox.shrink();
  }
  
  /// 进入编辑模式
  void _enterEditMode() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.message.allText;
    });
    _editFocusNode.requestFocus();
  }
  
  /// 保存编辑
  void _saveEdit() {
    final newContent = _editController.text.trim();
    if (newContent.isNotEmpty && widget.onEdit != null) {
      widget.onEdit!(newContent);
    }
    setState(() => _isEditing = false);
  }
  
  /// 取消编辑
  void _cancelEdit() {
    setState(() => _isEditing = false);
    _editController.clear();
  }
  
  /// 获取消息背景颜色
  Color _getMessageBackgroundColor() {
    if (widget.message.isUser) {
      return AgentChatThemeConfig.getColor(
        AgentChatThemeConfig.lightUserMessageBg,
        AgentChatThemeConfig.darkUserMessageBg,
        widget.isDark,
      ).withOpacity(0.05);
    }
    return Colors.transparent;
  }
  
  /// 获取头像颜色
  Color _getAvatarColor() {
    if (widget.message.isUser) {
      return Color(AvatarConfig.userAvatarColor);
    } else if (widget.message.isSupervisor) {
      return Color(AvatarConfig.supervisorAvatarColor);
    } else {
      return Color(AvatarConfig.aiAvatarColor);
    }
  }
  
  /// 获取头像文本
  String _getAvatarText() {
    if (widget.message.isUser) {
      return AvatarConfig.userIcon;
    } else if (widget.message.isSupervisor) {
      return AvatarConfig.supervisorIcon;
    } else {
      return AvatarConfig.aiIcon;
    }
  }
  
  /// 获取显示名称
  String _getDisplayName() {
    if (widget.message.isUser) {
      return '你';
    } else if (widget.message.isSupervisor) {
      return '主管';
    } else if (widget.message.agentName != null) {
      return widget.message.agentName!;
    } else {
      return 'AI助手';
    }
  }
}

/// 操作按钮Widget
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightMutedForeground,
              AgentChatThemeConfig.darkMutedForeground,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
      ),
    );
  }
}




