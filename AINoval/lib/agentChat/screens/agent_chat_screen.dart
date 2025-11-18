/// Agent Chat主页面
/// Agent Chat main screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/agent_provider.dart';
import '../services/chat_service.dart';
import '../i18n/locale_provider.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../models/models.dart';
import '../widgets/conversation_tabs.dart';
import '../widgets/chat_area.dart';
import '../widgets/reference_bar.dart';
import '../widgets/chat_input.dart';
import '../widgets/agent_manager.dart';

/// Agent Chat主屏幕
/// Agent Chat main screen
class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});
  
  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final ChatService _chatService = ChatService();
  double _sidebarWidth = SidebarConfig.defaultWidth;
  bool _isFullscreen = false;
  bool _isDragging = false;
  bool _showAgentManager = false;
  
  @override
  void initState() {
    super.initState();
    // 初始化providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      final agentProvider = context.read<AgentProvider>();
      final localeProvider = context.read<LocaleProvider>();
      
      chatProvider.initialize();
      agentProvider.initialize(localeProvider.t);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_showAgentManager) {
      return _buildAgentManager();
    }
    
    return Scaffold(
      body: Row(
        children: [
          // 左侧空白区域
          if (!_isFullscreen)
            Expanded(child: Container(color: AgentChatThemeConfig.lightMuted.toColor().withOpacity(0.05))),
          
          // 可拖拽分隔条
          if (!_isFullscreen)
            _buildResizeHandle(),
          
          // 右侧聊天区域
          _buildChatSidebar(),
        ],
      ),
    );
  }
  
  Widget _buildResizeHandle() {
    return GestureDetector(
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanUpdate: (details) {
        setState(() {
          final newWidth = MediaQuery.of(context).size.width - details.globalPosition.dx;
          _sidebarWidth = newWidth.clamp(
            SidebarConfig.minWidth,
            MediaQuery.of(context).size.width - SidebarConfig.maxWidthOffset,
          );
        });
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      onDoubleTap: () => setState(() => _isFullscreen = !_isFullscreen),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: _isDragging ? 6 : 4,
          color: _isDragging
              ? AgentChatThemeConfig.lightPrimary.toColor()
              : AgentChatThemeConfig.lightBorder.toColor(),
        ),
      ),
    );
  }
  
  Widget _buildChatSidebar() {
    final chatProvider = context.watch<ChatProvider>();
    final agentProvider = context.watch<AgentProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final translations = localeProvider.t;
    
    return Container(
      width: _isFullscreen ? double.infinity : _sidebarWidth,
      decoration: BoxDecoration(
        border: _isFullscreen ? null : Border(
          left: BorderSide(color: AgentChatThemeConfig.lightBorder.toColor()),
        ),
      ),
      child: Column(
        children: [
          // 对话标签栏
          ConversationTabs(
            conversations: chatProvider.conversations,
            activeId: chatProvider.activeConversationId,
            onTabClick: chatProvider.switchConversation,
            onTabClose: chatProvider.closeConversation,
            onNewChat: chatProvider.createConversation,
            snapshots: chatProvider.activeConversation?.snapshots ?? [],
            currentSnapshotId: chatProvider.currentSnapshotId,
            onRestore: chatProvider.restoreSnapshot,
            onOpenAgentManager: () => setState(() => _showAgentManager = true),
            translations: translations,
          ),
          
          // 聊天区域
          Expanded(
            child: ChatArea(
              messages: chatProvider.activeConversation?.messages ?? [],
              currentAgent: agentProvider.activeAgent,
              translations: translations,
              onToolToggleExpand: _handleToolToggleExpand,
              onToolApply: _handleToolApply,
              onToolCancel: _handleToolCancel,
              onThinkingToggle: _handleThinkingToggle,
              onToolApprove: _handleToolApprove,
              onToolReject: _handleToolReject,
              onRollback: chatProvider.rollbackMessage,
              onEdit: (messageId, content) {
                chatProvider.editMessage(messageId, content);
                _handleSendMessage(content, false);
              },
              onCopy: (messageId) {
                // 复制功能
              },
            ),
          ),
          
          // 引用栏
          ReferenceBar(
            references: chatProvider.references,
            onRemove: chatProvider.removeReference,
            translations: translations,
          ),
          
          // 输入框
          ChatInput(
            onSend: _handleSendMessage,
            currentAgent: agentProvider.activeAgent,
            collaborationMode: agentProvider.collaborationMode,
            onModeChange: agentProvider.setCollaborationMode,
            translations: translations,
          ),
        ],
      ),
    );
  }
  
  Widget _buildAgentManager() {
    final agentProvider = context.watch<AgentProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    
    return AgentManager(
      agents: agentProvider.agents,
      activeAgentId: agentProvider.activeAgentId,
      onAgentSelect: (agentId) {
        agentProvider.selectAgent(agentId);
        setState(() => _showAgentManager = false);
      },
      onAgentCreate: agentProvider.createAgent,
      onAgentUpdate: agentProvider.updateAgent,
      onAgentDelete: agentProvider.deleteAgent,
      onClose: () => setState(() => _showAgentManager = false),
      translations: localeProvider.t,
    );
  }
  
  void _handleSendMessage(String message, bool deepThinking) async {
    final chatProvider = context.read<ChatProvider>();
    final agentProvider = context.read<AgentProvider>();
    
    // 添加用户消息
    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      blocks: [TextBlock(content: message)],
      timestamp: _getTimestamp(),
    );
    chatProvider.addMessage(userMessage);
    chatProvider.createSnapshot('用户消息', message, SnapshotType.message);
    
    // 生成AI响应
    final aiMessageId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final requireApproval = message.contains('修改') || message.contains('更新') || message.contains('删除');
    
    await for (final responseMessage in _chatService.generateResponse(
      messageId: aiMessageId,
      agent: agentProvider.activeAgent!,
      userMessage: message,
      deepThinking: deepThinking,
      requireApproval: requireApproval,
    )) {
      // 检查消息是否已存在
      final existingMessages = chatProvider.activeConversation?.messages ?? [];
      final messageExists = existingMessages.any((m) => m.id == aiMessageId);
      
      if (messageExists) {
        chatProvider.updateMessage(aiMessageId, responseMessage);
      } else {
        chatProvider.addMessage(responseMessage);
      }
    }
  }
  
  void _handleToolToggleExpand(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null && blockIndex < message.blocks.length) {
      final block = message.blocks[blockIndex];
      if (block is ToolBlock) {
        final newBlocks = List<MessageBlock>.from(message.blocks);
        newBlocks[blockIndex] = block.copyWith(isExpanded: !(block.isExpanded ?? false));
        chatProvider.updateMessage(messageId, message.copyWith(blocks: newBlocks));
      }
    }
  }
  
  void _handleToolApply(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null && blockIndex < message.blocks.length) {
      final block = message.blocks[blockIndex];
      if (block is ToolBlock) {
        final newBlocks = List<MessageBlock>.from(message.blocks);
        newBlocks[blockIndex] = block.copyWith(applied: true);
        chatProvider.updateMessage(messageId, message.copyWith(blocks: newBlocks));
      }
    }
  }
  
  void _handleToolCancel(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null) {
      final newBlocks = List<MessageBlock>.from(message.blocks);
      newBlocks.removeAt(blockIndex);
      chatProvider.updateMessage(messageId, message.copyWith(blocks: newBlocks));
    }
  }
  
  void _handleThinkingToggle(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null && blockIndex < message.blocks.length) {
      final block = message.blocks[blockIndex];
      if (block is ThinkingBlock) {
        final newBlocks = List<MessageBlock>.from(message.blocks);
        newBlocks[blockIndex] = block.copyWith(isExpanded: !block.isExpanded);
        chatProvider.updateMessage(messageId, message.copyWith(blocks: newBlocks));
      }
    }
  }
  
  void _handleToolApprove(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final agentProvider = context.read<AgentProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null) {
      final completedMessage = _chatService.completeToolExecution(message, agentProvider.activeAgent!);
      chatProvider.updateMessage(messageId, completedMessage);
      chatProvider.createSnapshot('工具执行完成', '设定管理已更新', SnapshotType.tool);
    }
  }
  
  void _handleToolReject(String messageId, int blockIndex) {
    final chatProvider = context.read<ChatProvider>();
    final message = chatProvider.activeConversation?.messages
        .firstWhere((m) => m.id == messageId);
    
    if (message != null) {
      final newBlocks = message.blocks.where((b) => b.type != BlockType.approval).toList();
      newBlocks.add(TextBlock(content: '❌ 工具执行已被取消。'));
      chatProvider.updateMessage(messageId, message.copyWith(blocks: newBlocks));
      chatProvider.createSnapshot('拒绝工具', '用户拒绝工具执行', SnapshotType.approval);
    }
  }
  
  String _getTimestamp() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }
}



