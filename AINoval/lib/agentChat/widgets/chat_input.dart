/// 聊天输入框组件
/// Chat input component

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 聊天输入Widget
class ChatInput extends StatefulWidget {
  final Function(String message, bool deepThinking) onSend;
  final Agent? currentAgent;
  final String collaborationMode;
  final Function(String mode) onModeChange;
  final Translations translations;
  final bool disabled;
  
  const ChatInput({
    super.key,
    required this.onSend,
    this.currentAgent,
    required this.collaborationMode,
    required this.onModeChange,
    required this.translations,
    this.disabled = false,
  });
  
  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  bool _deepThinking = false;
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.disabled) {
      widget.onSend(text, _deepThinking);
      _controller.clear();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Container(
      padding: EdgeInsets.all(ResponsiveUtils.getSpacing(context)),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.lightCard.toColor().withOpacity(0.8),
        border: Border(
          top: BorderSide(color: AgentChatThemeConfig.lightBorder.toColor()),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 智能体信息和模式切换
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.currentAgent != null)
                Row(
                  children: [
                    Icon(Icons.smart_toy, size: 14, color: AgentChatThemeConfig.lightPrimary.toColor()),
                    SizedBox(width: AgentChatThemeConfig.spacing),
                    Text(
                      widget.currentAgent!.name,
                      style: TextStyle(fontSize: isCompact ? 12 : 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              Row(
                children: [
                  _buildModeToggle(isCompact),
                  if (!isCompact) ...[
                    SizedBox(width: AgentChatThemeConfig.spacing2),
                    Text(
                      widget.collaborationMode == CollaborationMode.team
                          ? widget.translations.teamMode
                          : widget.translations.authorMode,
                      style: TextStyle(fontSize: 12, color: AgentChatThemeConfig.lightMutedForeground.toColor()),
                    ),
                  ],
                ],
              ),
            ],
          ),
          SizedBox(height: AgentChatThemeConfig.spacing2),
          
          // 输入框
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 深度思考按钮
              IconButton(
                icon: Icon(Icons.psychology, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: _deepThinking
                      ? AgentChatThemeConfig.lightPrimary.toColor()
                      : AgentChatThemeConfig.lightMuted.toColor(),
                  foregroundColor: _deepThinking
                      ? Colors.white
                      : AgentChatThemeConfig.lightForeground.toColor(),
                ),
                onPressed: () => setState(() => _deepThinking = !_deepThinking),
                tooltip: widget.translations.deepThinking,
              ),
              SizedBox(width: AgentChatThemeConfig.spacing2),
              
              // 文本输入
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: widget.translations.inputPlaceholder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        ResponsiveUtils.getBorderRadius(context) * 0.5,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AgentChatThemeConfig.spacing3,
                      vertical: AgentChatThemeConfig.spacing2,
                    ),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              SizedBox(width: AgentChatThemeConfig.spacing2),
              
              // 发送按钮
              IconButton(
                icon: Icon(Icons.send, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: _controller.text.trim().isEmpty
                      ? AgentChatThemeConfig.lightMuted.toColor()
                      : AgentChatThemeConfig.lightPrimary.toColor(),
                  foregroundColor: Colors.white,
                ),
                onPressed: _controller.text.trim().isEmpty ? null : _handleSend,
                tooltip: widget.translations.send,
              ),
            ],
          ),
          
          // 提示文本
          SizedBox(height: AgentChatThemeConfig.spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _deepThinking
                    ? widget.translations.deepThinkingEnabled
                    : widget.translations.inputHint,
                style: TextStyle(
                  fontSize: 11,
                  color: _deepThinking
                      ? AgentChatThemeConfig.lightPrimary.toColor()
                      : AgentChatThemeConfig.lightMutedForeground.toColor(),
                ),
              ),
              if (_controller.text.isNotEmpty)
                Text(
                  '${_controller.text.length} ${widget.translations.characterCount}',
                  style: TextStyle(fontSize: 11, color: AgentChatThemeConfig.lightMutedForeground.toColor()),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildModeToggle(bool isCompact) {
    final isTeamMode = widget.collaborationMode == CollaborationMode.team;
    
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.lightMuted.toColor(),
        borderRadius: BorderRadius.circular(ResponsiveUtils.getBorderRadius(context) * 0.4),
      ),
      child: Row(
        children: [
          _buildModeButton(
            label: isCompact ? '作' : widget.translations.authorMode,
            isSelected: !isTeamMode,
            onTap: () => widget.onModeChange(CollaborationMode.author),
          ),
          SizedBox(width: 2),
          _buildModeButton(
            label: isCompact ? '团' : widget.translations.teamMode,
            isSelected: isTeamMode,
            onTap: () => widget.onModeChange(CollaborationMode.team),
          ),
        ],
      ),
    );
  }
  
  Widget _buildModeButton({required String label, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AgentChatThemeConfig.lightPrimary.toColor() : Colors.transparent,
          borderRadius: BorderRadius.circular(ResponsiveUtils.getBorderRadius(context) * 0.3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : AgentChatThemeConfig.lightForeground.toColor(),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
