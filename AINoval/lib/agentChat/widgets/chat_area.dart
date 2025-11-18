/// 聊天区域组件
/// Chat area component

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../config/theme_config.dart';
import '../i18n/translations.dart';
import 'chat_message.dart';

/// 聊天区域Widget
class ChatArea extends StatefulWidget {
  final List<Message> messages;
  final Agent? currentAgent;
  final Translations translations;
  final Function(String messageId, int blockIndex)? onToolToggleExpand;
  final Function(String messageId, int blockIndex)? onToolApply;
  final Function(String messageId, int blockIndex)? onToolCancel;
  final Function(String messageId, int blockIndex)? onThinkingToggle;
  final Function(String messageId, int blockIndex)? onToolApprove;
  final Function(String messageId, int blockIndex)? onToolReject;
  final Function(String messageId)? onRollback;
  final Function(String messageId, String content)? onEdit;
  final Function(String messageId)? onCopy;
  
  const ChatArea({
    super.key,
    required this.messages,
    this.currentAgent,
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
  State<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends State<ChatArea> {
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }
  
  @override
  void didUpdateWidget(ChatArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }
  
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return _buildEmptyState();
    }
    
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.all(AgentChatThemeConfig.spacing4),
      itemCount: widget.messages.length,
      separatorBuilder: (context, index) => SizedBox(height: AgentChatThemeConfig.spacing4),
      itemBuilder: (context, index) {
        final message = widget.messages[index];
        return ChatMessageWidget(
          message: message,
          translations: widget.translations,
          onToolToggleExpand: (blockIndex) => widget.onToolToggleExpand?.call(message.id, blockIndex),
          onToolApply: (blockIndex) => widget.onToolApply?.call(message.id, blockIndex),
          onToolCancel: (blockIndex) => widget.onToolCancel?.call(message.id, blockIndex),
          onThinkingToggle: (blockIndex) => widget.onThinkingToggle?.call(message.id, blockIndex),
          onToolApprove: (blockIndex) => widget.onToolApprove?.call(message.id, blockIndex),
          onToolReject: (blockIndex) => widget.onToolReject?.call(message.id, blockIndex),
          onRollback: () => widget.onRollback?.call(message.id),
          onEdit: (content) => widget.onEdit?.call(message.id, content),
          onCopy: () => widget.onCopy?.call(message.id),
        );
      },
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AgentChatThemeConfig.lightMutedForeground.toColor().withOpacity(0.3),
          ),
          SizedBox(height: AgentChatThemeConfig.spacing4),
          Text(
            widget.translations.emptyState,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AgentChatThemeConfig.lightMutedForeground.toColor(),
            ),
          ),
          SizedBox(height: AgentChatThemeConfig.spacing2),
          Text(
            widget.translations.emptyStateHint,
            style: TextStyle(
              fontSize: 13,
              color: AgentChatThemeConfig.lightMutedForeground.toColor().withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
