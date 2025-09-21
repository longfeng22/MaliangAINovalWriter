import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart'; // 引入 intl 包用于日期格式化

import '../../../blocs/chat/chat_bloc.dart';
import '../../../blocs/chat/chat_event.dart';
import '../../../blocs/chat/chat_state.dart';
import '../../../blocs/editor/editor_bloc.dart';
import '../../../models/user_ai_model_config_model.dart'; // Import the model config
import '../../../models/novel_structure.dart';
import '../../../models/context_selection_models.dart';
import '../../../models/novel_setting_item.dart';
import '../../../models/novel_snippet.dart';
import '../../../models/setting_group.dart';
import 'chat_input.dart'; // 引入 ChatInput
import 'chat_message_bubble.dart'; // 引入 ChatMessageBubble
// 🚀 移除 TypingIndicator 导入，不再使用单独的等待指示器

/// AI聊天侧边栏组件，用于在编辑器右侧显示聊天功能
class AIChatSidebar extends StatefulWidget {
  const AIChatSidebar({
    Key? key,
    required this.novelId,
    this.chapterId,
    this.onClose,
    this.isCardMode = false,
    this.editorController, // 🚀 新增：接收EditorScreenController参数
  }) : super(key: key);

  final String novelId;
  final String? chapterId;
  final VoidCallback? onClose;
  final bool isCardMode; // 是否以卡片模式显示
  final dynamic editorController; // 🚀 新增：EditorScreenController实例

  @override
  State<AIChatSidebar> createState() => _AIChatSidebarState();
}

class _AIChatSidebarState extends State<AIChatSidebar> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // 记录已经完成上下文数据初始化的会话，避免重复检查
  final Set<String> _contextInitializedSessions = {};

  @override
  void initState() {
    super.initState();
    // --- Add initState Log ---
    AppLogger.i('AIChatSidebar',
        'initState called. Widget hash: ${identityHashCode(widget)}, State hash: ${identityHashCode(this)}');
    // Get the Bloc instance WITHOUT triggering a rebuild if already present
    final chatBloc = BlocProvider.of<ChatBloc>(context, listen: false);
    AppLogger.i('AIChatSidebar',
        'initState: Associated ChatBloc hash: ${identityHashCode(chatBloc)}');
    // --- End Add Log ---
    // 每次初始化侧边栏都强制重新加载指定小说的会话列表，防止沿用上一部小说的数据
    chatBloc.add(LoadChatSessions(novelId: widget.novelId));

    // 同时重新加载上下文数据（设定、片段等）
    chatBloc.add(LoadContextData(novelId: widget.novelId));
  }

  @override
  void didUpdateWidget(covariant AIChatSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果小说发生切换，重新拉取该小说的会话及上下文
    if (widget.novelId != oldWidget.novelId) {
      AppLogger.i('AIChatSidebar',
          'didUpdateWidget: novelId changed from \\${oldWidget.novelId} to \\${widget.novelId}, reloading sessions & context');

      final chatBloc = BlocProvider.of<ChatBloc>(context, listen: false);

      // 重新加载聊天会话列表
      chatBloc.add(LoadChatSessions(novelId: widget.novelId));

      // 重新加载上下文数据（设定、片段等）
      chatBloc.add(LoadContextData(novelId: widget.novelId));
    }
  }

  @override
  void dispose() {
    // --- Add dispose Log ---
    AppLogger.w('AIChatSidebar',
        'dispose() called. Widget hash: ${identityHashCode(widget)}, State hash: ${identityHashCode(this)}');
    // --- End Add Log ---
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 发送消息
  void _sendMessage() {
    final message = _messageController.text.trim();
    AppLogger.i('AIChatSidebar', '🚀 _sendMessage被调用，消息内容: "$message"');
    
    if (message.isNotEmpty) {
      final chatBloc = context.read<ChatBloc>();
      final currentState = chatBloc.state;
      
      AppLogger.i('AIChatSidebar', '🚀 当前ChatBloc状态: ${currentState.runtimeType}');
      if (currentState is ChatSessionActive) {
        AppLogger.i('AIChatSidebar', '🚀 当前会话ID: ${currentState.session.id}, isGenerating: ${currentState.isGenerating}');
      }
      
      AppLogger.i('AIChatSidebar', '🚀 发送SendMessage事件到ChatBloc，BLoC实例: ${identityHashCode(chatBloc)}, isClosed: ${chatBloc.isClosed}');
      chatBloc.add(SendMessage(content: message));
      _messageController.clear();
      AppLogger.i('AIChatSidebar', '🚀 SendMessage事件已发送，输入框已清空');
    } else {
      AppLogger.w('AIChatSidebar', '🚀 消息为空，不发送');
    }
  }

  // 选择会话
  void _selectSession(String sessionId) {
    context.read<ChatBloc>().add(SelectChatSession(sessionId: sessionId, novelId: widget.novelId));
  }

  // 创建新会话
  void _createNewThread() {
    context.read<ChatBloc>().add(CreateChatSession(
          title: '新对话 ${DateFormat('MM-dd HH:mm').format(DateTime.now())}',
          novelId: widget.novelId,
          chapterId: widget.chapterId,
        ));
  }

  // 🚀 已移除 _hasStreamingMessage 方法，不再需要检查流式消息

  /// 🚀 构建并更新上下文数据
  void _buildAndUpdateContextData(Novel novel, ChatSessionActive state) {
    final novelSettings = state.cachedSettings.cast<NovelSettingItem>();
    final novelSettingGroups = state.cachedSettingGroups.cast<SettingGroup>();
    final novelSnippets = state.cachedSnippets.cast<NovelSnippet>();
    
    AppLogger.i('AIChatSidebar', '🔧 构建上下文数据 - 设定: ${novelSettings.length}, 设定组: ${novelSettingGroups.length}, 片段: ${novelSnippets.length}');
    
    final newContextData = ContextSelectionDataBuilder.fromNovelWithContext(
      novel,
      settings: novelSettings,
      settingGroups: novelSettingGroups,
      snippets: novelSnippets,
    );
    
    AppLogger.i('AIChatSidebar', '🔧 构建的上下文数据包含 ${newContextData.availableItems.length} 个可用项目');
    
    // 获取当前会话配置并更新
    final chatBloc = context.read<ChatBloc>();
    final currentConfig = chatBloc.getSessionConfig(state.session.id, widget.novelId);
    
    if (currentConfig != null) {
      final updatedConfig = currentConfig.copyWith(
        contextSelections: newContextData,
      );
      
      AppLogger.i('AIChatSidebar', '🔧 更新ChatBloc配置，上下文项目: ${newContextData.availableItems.length} → ChatBloc');
      
      // 使用 Future.microtask 避免在 build 过程中直接调用 add
      Future.microtask(() {
        if (mounted) {
          chatBloc.add(UpdateChatConfiguration(
            sessionId: state.session.id,
            config: updatedConfig,
          ));
        }
      });
    } else {
      AppLogger.w('AIChatSidebar', '🚨 无法更新上下文数据：currentConfig为null，sessionId=${state.session.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Log the associated Bloc hash on build too, might be helpful
    final chatBloc = BlocProvider.of<ChatBloc>(context, listen: false);
    AppLogger.d('AIChatSidebar',
        'build called. Associated ChatBloc hash: ${identityHashCode(chatBloc)}');
    AppLogger.i('Screens/chat/widgets/ai_chat_sidebar',
        'Building AIChatSidebar widget');
    return Material(
      elevation: 4.0,
      child: Container(
        // 移除固定宽度，让父组件SizedBox控制宽度
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            // 顶部标题栏 - 在卡片模式下隐藏，因为多面板视图有自己的拖拽把手
            if (!widget.isCardMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: BlocBuilder<ChatBloc, ChatState>(
                        builder: (context, state) {
                          String title = 'AI 聊天助手';
                          if (state is ChatSessionActive) {
                            title = state.session.title;
                          } else if (state is ChatSessionsLoaded) {
                            title = '聊天列表';
                          }
                          return Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                    BlocBuilder<ChatBloc, ChatState>(
                      builder: (context, state) {
                        if (state is ChatSessionActive) {
                          return IconButton(
                            icon: const Icon(Icons.list),
                            tooltip: '返回列表',
                            onPressed: () {
                              context
                                  .read<ChatBloc>()
                                  .add(LoadChatSessions(novelId: widget.novelId));
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                      tooltip: '关闭侧边栏',
                      padding: const EdgeInsets.all(8.0),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

            // 聊天内容区域
            Expanded(
              child: BlocConsumer<ChatBloc, ChatState>(
                listener: (context, state) {
                  // 🚀 当会话激活且有缓存数据时，构建完整的上下文数据（仅限首次）
                  if (state is ChatSessionActive &&
                      !_contextInitializedSessions.contains(state.session.id)) {
                    final editorState = context.read<EditorBloc>().state;
                    if (editorState is EditorLoaded) {
                      final novel = editorState.novel;

                      // 检查是否需要构建上下文数据
                      final chatBloc = context.read<ChatBloc>();
                      final currentConfig = chatBloc.getSessionConfig(state.session.id, widget.novelId);

                      final hasContextData = state.cachedSettings.isNotEmpty ||
                          state.cachedSettingGroups.isNotEmpty ||
                          state.cachedSnippets.isNotEmpty;
                      final needsContextData =
                          (currentConfig?.contextSelections?.availableItems ?? const []).isEmpty;

                      final shouldBuildContext = hasContextData && needsContextData;

                      if (shouldBuildContext) {
                        AppLogger.i('AIChatSidebar',
                            '🚀 构建完整的上下文数据，缓存数据: ${state.cachedSettings.length}设定, ${state.cachedSettingGroups.length}组, ${state.cachedSnippets.length}片段');
                        _buildAndUpdateContextData(novel, state);
                      }

                      // 无论是否真正构建，只要检查过一次就标记，避免后续重复评估
                      _contextInitializedSessions.add(state.session.id);
                    }
                  }
                  
                  // 显示会话加载错误
                  if (state is ChatSessionsLoaded && state.error != null) {
                    TopToast.error(context, state.error!);
                  }
                  // 显示活动会话错误（例如加载历史失败或发送失败后）
                  if (state is ChatSessionActive && state.error != null) {
                    TopToast.error(context, state.error!);
                  }
                  // 滚动到底部逻辑保持不变
                  if (state is ChatSessionActive && !state.isLoadingHistory) {
                    // 仅在历史加载完成后滚动
                    _scrollToBottom();
                  }
                },
                // buildWhen 优化：避免不必要的重建，例如仅在关键状态或错误变化时重建
                buildWhen: (previous, current) {
                  // Always rebuild if state type changed completely
                  if (previous.runtimeType != current.runtimeType) return true;

                  // --- ChatSessionActive -> ChatSessionActive ---
                  if (previous is ChatSessionActive && current is ChatSessionActive) {
                    // 1. New / removed message
                    final bool lengthChanged =
                        previous.messages.length != current.messages.length;

                    // 2. Generation / loading flag flips
                    final bool flagChanged =
                        previous.isGenerating != current.isGenerating ||
                            previous.isLoadingHistory != current.isLoadingHistory;

                    final bool idChanged = previous.session.id != current.session.id;
                    // 3. Severe error / model switch / cached data updates
                    final bool metaChanged = idChanged ||
                          previous.error != current.error ||
                            previous.selectedModel?.id != current.selectedModel?.id ||
                            previous.cachedSettings != current.cachedSettings ||
                            previous.cachedSettingGroups != current.cachedSettingGroups ||
                            previous.cachedSnippets != current.cachedSnippets;

                    // NOTE: Streaming content updates keep the list length the same, so
                    //       lengthChanged will be false in that situation, effectively
                    //       preventing a rebuild on every token.
                    return lengthChanged || flagChanged || metaChanged;
                  }

                  // --- ChatSessionsLoaded -> ChatSessionsLoaded ---
                  if (previous is ChatSessionsLoaded && current is ChatSessionsLoaded) {
                    return previous.sessions != current.sessions || previous.error != current.error;
                  }

                  // Fallback: rebuild for other transitions we did not explicitly handle
                  return true;
                },
                builder: (context, state) {
                  AppLogger.i('Screens/chat/widgets/ai_chat_sidebar',
                      'Building chat UI for state: ${state.runtimeType}');
                  // --- 加载状态处理 ---
                  if (state is ChatSessionsLoading ||
                      state is ChatSessionLoading) {
                    AppLogger.d('AIChatSidebar builder',
                        'State is Loading, showing indicator.');
                    return const Center(child: CircularProgressIndicator());
                  }
                  // --- 错误状态处理 ---
                  else if (state is ChatError) {
                    AppLogger.d('AIChatSidebar builder',
                        'State is ChatError, showing error message.');
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('错误: ${state.message}',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    );
                  }
                  // --- 会话列表状态 ---
                  else if (state is ChatSessionsLoaded) {
                    AppLogger.d('AIChatSidebar builder',
                        'State is ChatSessionsLoaded with ${state.sessions.length} sessions.');
                    return _buildThreadsList(
                        context, state); // _buildThreadsList 会处理空列表
                  }
                  // --- 活动会话状态 ---
                  else if (state is ChatSessionActive) {
                    AppLogger.d('AIChatSidebar builder',
                        'State is ChatSessionActive. isLoadingHistory: ${state.isLoadingHistory}, isGenerating: ${state.isGenerating}');
                    return _buildChatView(context, state);
                  }
                  // --- 初始或其他状态 ---
                  else {
                    AppLogger.d('AIChatSidebar builder',
                        'State is Initial or unexpected, showing empty state.');
                    // 初始状态可以显示空状态或者加载列表
                    // context.read<ChatBloc>().add(LoadChatSessions(novelId: widget.novelId)); // 如果希望初始时自动加载
                    return _buildEmptyState(); // 或者 return const Center(child: CircularProgressIndicator()); 看设计需求
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(height: 20),
            Text(
              '开始一个新的对话',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '与AI助手交流，获取写作灵感、建议或进行头脑风暴',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createNewThread,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新建对话'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建会话列表
  Widget _buildThreadsList(BuildContext context, ChatSessionsLoaded state) {
    // 现在接收整个 state 以便访问 error
    final sessions = state.sessions;

    if (sessions.isEmpty) {
      // 即使列表为空，也不显示加载，显示空状态
      return _buildEmptyState();
    }
    return Column(
      children: [
        // 新建对话按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: OutlinedButton.icon(
            onPressed: _createNewThread,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('新建对话'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.8)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
        // 列表视图
        Expanded(
          child: ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color:
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
            ),
            itemBuilder: (context, index) {
              final session = sessions[index];
              // 获取当前活动会话 ID （需要 ChatBloc 的状态信息，这里假设可以从 context 获取）
              String? activeSessionId;
              final currentState = context.read<ChatBloc>().state;
              if (currentState is ChatSessionActive) {
                activeSessionId = currentState.session.id;
              }
              final bool isSelected = session.id == activeSessionId;

              return ListTile(
                leading: Icon(
                  isSelected ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  '最后更新: ${DateFormat('MM-dd HH:mm').format(session.lastUpdatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.8),
                      ),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: const Text('确认删除'),
                          content:
                              Text('确定要删除会话 "${session.title}" 吗？此操作无法撤销。'),
                          actions: <Widget>[
                            TextButton(
                              child: const Text('取消'),
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                            TextButton(
                              child: Text('删除',
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                              onPressed: () {
                                context.read<ChatBloc>().add(
                                    DeleteChatSession(sessionId: session.id));
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  tooltip: '删除会话',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                selected: isSelected,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.1),
                onTap: () => _selectSession(session.id),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              );
            },
          ),
        ),
      ],
    );
  }

  // 构建聊天视图
  Widget _buildChatView(BuildContext context, ChatSessionActive state) {
    // --- 获取当前会话选择的模型 ---
    // 现在可以直接从 state 获取 selectedModel
    final UserAIModelConfigModel? currentChatModel = state.selectedModel;

    return Column(
      children: [
        // 在卡片模式下显示简洁的返回按钮
        if (widget.isCardMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  tooltip: '返回列表',
                  onPressed: () {
                    context.read<ChatBloc>().add(LoadChatSessions(novelId: widget.novelId));
                  },
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                Expanded(
                  child: Text(
                    state.session.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        
        // 显示历史加载指示器
        if (state.isLoadingHistory)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        // 显示加载历史或发送消息时的错误信息（如果需要更持久的提示）
        // if (state.error != null)
        //   Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        //     child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        //   ),
        Expanded(
          child: ChatMessagesList(scrollController: _scrollController),
        ),
        // ChatInput 背景应与聊天视图背景一致或略有区分
        Container(
          color: Theme.of(context).colorScheme.surface,
          child: BlocBuilder<EditorBloc, EditorState>(
            builder: (context, editorState) {
              Novel? novel;
              if (editorState is EditorLoaded) {
                novel = editorState.novel;
              }
              
              // 🚀 使用BlocBuilder获取当前会话的配置
              return BlocBuilder<ChatBloc, ChatState>(
                buildWhen: (previous, current) {
                  // 只有当与当前会话相关的配置发生实际变化时才重建，避免流式 token 触发
                  if (previous is ChatSessionActive && current is ChatSessionActive) {
                    // 不同会话 → 必须重建
                    if (previous.session.id != current.session.id) return true;

                    // ChatBloc 在更新配置（模型或上下文）时会带上 configUpdateTimestamp
                    if (previous.configUpdateTimestamp != current.configUpdateTimestamp) {
                      return true;
                    }

                    return false; // 同会话且配置没变 → 不重建
                  }

                  // 其它类型转变，例如从活动回到列表或错误，再由父 BlocConsumer 处理
                  return false;
                },
                builder: (context, chatState) {
                  final chatBloc = context.read<ChatBloc>();
                  final currentConfig = chatBloc.getSessionConfig(state.session.id, widget.novelId);
                  
                  // 配置获取完成
                  
                  return ChatInput(
                    key: ValueKey('chat_input_${state.session.id}_${currentConfig?.contextSelections?.selectedCount ?? 0}'), // 🚀 添加key确保Widget正确更新
                    controller: _messageController,
                    onSend: _sendMessage,
                    isGenerating: state.isGenerating,
                    onCancel: () {
                      context.read<ChatBloc>().add(const CancelOngoingRequest());
                    },
                    initialModel: currentChatModel,
                    novel: novel, // 传入从EditorBloc获取的novel数据
                    contextData: widget.editorController?.cascadeMenuData, // 🚀 使用EditorScreenController维护的级联菜单数据（死的结构）
                    onContextChanged: (newContextData) {
                      // 🚀 如果需要通知EditorScreenController级联菜单数据变化，可以在这里处理
                      // 但通常不需要，因为EditorScreenController维护的是结构数据，不是选择状态
                      //print('🔧 [AIChatSidebar] 级联菜单数据变化通知: ${newContextData.selectedCount}个选择');
                    },
                    settings: state.cachedSettings.cast<NovelSettingItem>(),
                    settingGroups: state.cachedSettingGroups.cast<SettingGroup>(),
                    snippets: state.cachedSnippets.cast<NovelSnippet>(),
                    // 🚀 添加聊天配置支持，确保设置对话框能够同步
                    chatConfig: currentConfig,
                    onConfigChanged: (updatedConfig) {
                      //print('🔧 [AIChatSidebar] 聊天配置已更新，发送到ChatBloc');
                      //print('🔧 [AIChatSidebar] 更新后配置上下文: ${updatedConfig.contextSelections?.selectedCount ?? 0}');
                      
                      // 发送配置更新事件到ChatBloc
                      context.read<ChatBloc>().add(UpdateChatConfiguration(
                        sessionId: state.session.id,
                        config: updatedConfig,
                      ));
                    },
                    // 🚀 初始定位到当前章节/场景
                    initialChapterId: widget.chapterId,
                    initialSceneId: null,
                    onModelSelected: (selectedModel) {
                      if (selectedModel != null &&
                          selectedModel.id != currentChatModel?.id) {
                        // 使用正确的事件类
                        context.read<ChatBloc>().add(UpdateChatModel(
                              sessionId: state.session.id,
                              modelConfigId: selectedModel.id,
                            ));
                        AppLogger.i('AIChatSidebar',
                            'Model selected event dispatched: ${selectedModel.id} for session ${state.session.id}');
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class ChatMessagesList extends StatelessWidget {
  final ScrollController scrollController;
  const ChatMessagesList({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (previous, current) {
        if (previous is ChatSessionActive && current is ChatSessionActive) {
          // 仅当消息列表实例或长度发生变化时重建，实现流式刷新
          return previous.messages != current.messages;
        }
        return false;
      },
      builder: (context, state) {
        if (state is! ChatSessionActive) {
          return const SizedBox.shrink();
        }
        final messages = state.messages;
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return ChatMessageBubble(
                message: message,
                onActionSelected: (action) {
                  context.read<ChatBloc>().add(ExecuteAction(action: action));
                },
              );
            },
          ),
        );
      },
    );
  }
}
