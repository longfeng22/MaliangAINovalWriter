import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_event.dart';
import '../../../blocs/setting_generation/setting_generation_state.dart';
import '../../../models/setting_node.dart';
import 'setting_node_widget.dart';
import 'ai_shimmer_placeholder.dart';
import '../../../utils/logger.dart';
import '../../../widgets/common/top_toast.dart';

/// 节点与层级信息的包装类
class _NodeWithLevel {
  final SettingNode node;
  final int level;

  const _NodeWithLevel({
    required this.node,
    required this.level,
  });
}

/// 设定树组件
class SettingsTreeWidget extends StatelessWidget {
  final String? lastInitialPrompt;
  final String? lastStrategy;
  final String? lastModelConfigId;
  final String? novelId;
  final String? userId;

  const SettingsTreeWidget({
    Key? key,
    this.lastInitialPrompt,
    this.lastStrategy,
    this.lastModelConfigId,
    this.novelId,
    this.userId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
      buildWhen: (previous, current) {
        // 类型变化：一定重建
        if (previous.runtimeType != current.runtimeType) return true;

        // 进行中：当节点树/渲染相关/选中/视图模式或操作文案改变时才重建
        if (previous is SettingGenerationInProgress && current is SettingGenerationInProgress) {
          return previous.activeSession.rootNodes != current.activeSession.rootNodes ||
              previous.renderedNodeIds != current.renderedNodeIds ||
              previous.selectedNodeId != current.selectedNodeId ||
              previous.viewMode != current.viewMode ||
              previous.currentOperation != current.currentOperation;
        }

        // 完成：当节点树/渲染集合/选中/视图模式/活跃会话切换时才重建
        if (previous is SettingGenerationCompleted && current is SettingGenerationCompleted) {
          return previous.activeSession.rootNodes != current.activeSession.rootNodes ||
              previous.renderedNodeIds != current.renderedNodeIds ||
              previous.selectedNodeId != current.selectedNodeId ||
              previous.viewMode != current.viewMode ||
              previous.activeSessionId != current.activeSessionId;
        }

        // 修改中：当节点树/渲染集合/选中/修改目标/是否更新中变化时才重建
        if (previous is SettingGenerationNodeUpdating && current is SettingGenerationNodeUpdating) {
          return previous.activeSession.rootNodes != current.activeSession.rootNodes ||
              previous.renderedNodeIds != current.renderedNodeIds ||
              previous.selectedNodeId != current.selectedNodeId ||
              previous.updatingNodeId != current.updatingNodeId ||
              previous.isUpdating != current.isUpdating;
        }

        // 就绪：会话/活跃会话/视图模式变化
        if (previous is SettingGenerationReady && current is SettingGenerationReady) {
          return previous.sessions != current.sessions ||
              previous.activeSessionId != current.activeSessionId ||
              previous.viewMode != current.viewMode;
        }

        // 其他状态：保守起见重建
        return true;
      },
      builder: (context, state) {
        // 🔧 新增：详细的状态日志
        AppLogger.i('SettingsTreeWidget', '🔄 状态变更: ${state.runtimeType}');
        
        // 加载状态
        if (state is SettingGenerationLoading) {
          AppLogger.i('SettingsTreeWidget', '⏳ 显示加载状态');
          return const AIShimmerPlaceholder();
        }
        
        // 生成进行中状态
        if (state is SettingGenerationInProgress) {
          AppLogger.i('SettingsTreeWidget', '🚀 显示生成进行中状态 - 已渲染节点: ${state.renderedNodeIds.length}');
          return _buildInProgressView(context, state);
        }
        
        // 🔧 新增：节点修改中状态
        if (state is SettingGenerationNodeUpdating) {
          AppLogger.i('SettingsTreeWidget', '🔧 显示节点修改中状态 - 修改节点: ${state.updatingNodeId}');
          return _buildNodeUpdatingView(context, state);
        }
        
        // 生成完成状态
        if (state is SettingGenerationCompleted) {
          AppLogger.i('SettingsTreeWidget', '✅ 显示完成状态 - 会话: ${state.activeSessionId}');
          return _buildCompletedView(context, state);
        }

        // 保存成功状态 - 仍然显示完成视图，避免界面闪烁
        if (state is SettingGenerationSaved) {
          AppLogger.i('SettingsTreeWidget', '💾 显示保存成功状态，会话数: ${state.sessions.length}');
          return _buildSavedView(context, state);
        }

        // 无会话状态
        if (state is SettingGenerationReady) {
          AppLogger.i('SettingsTreeWidget', '🎯 显示就绪状态，会话数: ${state.sessions.length}');
          return _buildNoSessionView(context, state);
        }

        // 错误状态
        if (state is SettingGenerationError) {
          AppLogger.w('SettingsTreeWidget', '❌ 显示错误状态: ${state.message}');
          return _buildErrorView(context, state);
        }

        // 默认状态（初始状态等）
        AppLogger.w('SettingsTreeWidget', '🤔 未知状态: ${state.runtimeType}');
        return _buildNoSessionView(context, state);
      },
    );
  }

  Widget _buildInProgressView(BuildContext context, SettingGenerationInProgress state) {
    // 如果没有任何已渲染的节点（不管渲染状态如何），显示等待状态
    if (state.renderedNodeIds.isEmpty) {
      return const AIShimmerPlaceholder();
    }
    
    // 显示流式渲染界面（进度/提示统一由父级状态条显示，避免重复）
    return Column(
      children: [
        Expanded(
          child: _buildStreamingTreeView(context, state),
        ),
      ],
    );
  }

  Widget _buildCompletedView(BuildContext context, SettingGenerationCompleted state) {
    // 🔧 新增：详细的渲染日志
    AppLogger.i('SettingsTreeWidget', '🎨 渲染完成状态视图 - 节点数: ${state.activeSession.rootNodes.length}, 会话ID: ${state.activeSessionId}');
    
    // 🔧 修复：当没有节点数据时，显示空状态提示
    if (state.activeSession.rootNodes.isEmpty) {
      AppLogger.w('SettingsTreeWidget', '⚠️ 会话中没有设定节点数据，显示空状态提示');
      return _buildEmptyStateView(context, '此历史记录暂无设定数据');
    }
    
    return _buildTreeView(
      context,
      state.activeSession.rootNodes,
      state.selectedNodeId,
      state.viewMode,
      state.renderedNodeIds,
    );
  }

  Widget _buildStreamingTreeView(BuildContext context, SettingGenerationInProgress state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1F2937).withOpacity(0.3) 
            : const Color(0xFFF9FAFB).withOpacity(0.3),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF1F2937) 
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: state.renderedNodeIds.isEmpty
          ? _buildWaitingForFirstNode(context)
          : _buildRenderableNodesListView(
              context,
              state.activeSession.rootNodes,
              state.selectedNodeId,
              state.viewMode,
              state.renderedNodeIds,
              state.nodeRenderStates,
            ),
    );
  }

  Widget _buildWaitingForFirstNode(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  WebTheme.getPrimaryColor(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AI 正在构思第一个设定节点...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建可渲染的节点列表视图
  Widget _buildRenderableNodesListView(
    BuildContext context,
    List<SettingNode> nodes,
    String? selectedNodeId,
    String viewMode,
    Set<String> renderedNodeIds,
    Map<String, NodeRenderInfo> nodeRenderStates,
  ) {
    // 获取所有需要渲染的节点（扁平化列表）
    final renderableNodes = _getRenderableNodesList(
      nodes,
      renderedNodeIds,
      nodeRenderStates,
    );

    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: renderableNodes.length,
      itemBuilder: (context, index) {
        final nodeInfo = renderableNodes[index];
        final node = nodeInfo.node;
        final level = nodeInfo.level;
        
        return Padding(
          padding: EdgeInsets.only(bottom: index < renderableNodes.length - 1 ? 4 : 0),
          child: SettingNodeWidget(
            node: node,
            selectedNodeId: selectedNodeId,
            viewMode: viewMode,
            level: level,
            renderedNodeIds: renderedNodeIds,
            nodeRenderStates: nodeRenderStates,
             renderChildren: false,
            onTap: (nodeId) {
              context.read<SettingGenerationBloc>().add(
                SelectNodeEvent(nodeId),
              );
            },
          ),
        );
      },
    );
  }

  /// 获取所有需要渲染的节点列表（扁平化，包含层级信息）
  List<_NodeWithLevel> _getRenderableNodesList(
    List<SettingNode> nodes,
    Set<String> renderedNodeIds,
    Map<String, NodeRenderInfo> nodeRenderStates,
    {
    int level = 0,
  }) {
    final List<_NodeWithLevel> result = [];
    
    for (final node in nodes) {
      // 只添加已经渲染的节点或正在渲染的节点
      if (renderedNodeIds.contains(node.id) || 
          nodeRenderStates[node.id]?.state == NodeRenderState.rendering) {
        
        result.add(_NodeWithLevel(node: node, level: level));
        
        // 递归添加子节点
        if (node.children != null && node.children!.isNotEmpty) {
          result.addAll(_getRenderableNodesList(
            node.children!,
            renderedNodeIds,
            nodeRenderStates,
            level: level + 1,
          ));
        }
      }
    }
    
    return result;
  }

  Widget _buildTreeView(
    BuildContext context,
    List<SettingNode> nodes,
    String? selectedNodeId,
    String viewMode,
    Set<String> renderedNodeIds,
  ) {
    // 🔧 新增：日志和空状态处理
    AppLogger.i('SettingsTreeWidget', '🌳 构建设定树视图 - 节点数: ${nodes.length}, 选中节点: $selectedNodeId');
    
    // 🔧 修复：当节点列表为空时，显示空状态提示
    if (nodes.isEmpty) {
      AppLogger.w('SettingsTreeWidget', '⚠️ 节点列表为空，显示空状态提示');
      return _buildEmptyStateView(context, '暂无设定数据');
    }
    
    // 🔧 如果 renderedNodeIds 为空（通常发生在生成已完成的状态），
    //    将所有可见节点都视为已渲染，避免由于 Opacity=0 导致的内容不可见。
    Set<String> effectiveRenderedIds = renderedNodeIds;
    if (effectiveRenderedIds.isEmpty) {
      effectiveRenderedIds = _collectAllNodeIds(nodes).toSet();
      AppLogger.i('SettingsTreeWidget', '🔧 renderedNodeIds 为空，自动填充所有节点ID (${effectiveRenderedIds.length})');
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1F2937).withOpacity(0.3) 
            : const Color(0xFFF9FAFB).withOpacity(0.3),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF1F2937) 
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: nodes.length,
        itemBuilder: (context, index) {
          final node = nodes[index];
          return Padding(
            padding: EdgeInsets.only(bottom: index < nodes.length - 1 ? 4 : 0),
            child: SettingNodeWidget(
              node: node,
              selectedNodeId: selectedNodeId,
              viewMode: viewMode,
              level: 0,
              renderedNodeIds: effectiveRenderedIds,
              nodeRenderStates: const {}, // 完成状态下不需要渲染状态
              onTap: (nodeId) {
                context.read<SettingGenerationBloc>().add(
                  SelectNodeEvent(nodeId),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 递归收集所有节点 ID
  List<String> _collectAllNodeIds(List<SettingNode> nodes) {
    final List<String> ids = [];
    for (final node in nodes) {
      ids.add(node.id);
      if (node.children != null && node.children!.isNotEmpty) {
        ids.addAll(_collectAllNodeIds(node.children!));
      }
    }
    return ids;
  }

  Widget _buildErrorView(BuildContext context, SettingGenerationError state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1F2937).withOpacity(0.3) 
            : const Color(0xFFF9FAFB).withOpacity(0.3),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF1F2937) 
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            '生成失败',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
                _getFriendlyErrorMessage(state.message),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                ),
            textAlign: TextAlign.center,
          ),
              const SizedBox(height: 24),
              // 重试按钮
              if (state.isRecoverable && _canRetry())
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _retryGeneration(context),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试生成'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark 
                            ? const Color(0xFFF9FAFB) 
                            : const Color(0xFF111827),
                        side: BorderSide(
                          color: isDark 
                              ? const Color(0xFF374151) 
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => _resetAndReload(context),
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: const Text('重新开始'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark 
                            ? const Color(0xFF9CA3AF) 
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 将后端错误信息转换为用户友好的提示
  String _getFriendlyErrorMessage(String originalMessage) {
    // 检查常见的错误模式并返回友好提示
    final message = originalMessage.toLowerCase();
    
    if (message.contains('timeout') || message.contains('超时')) {
      return 'AI生成响应时间过长，请稍后重试';
    }
    
    if (message.contains('network') || message.contains('connection') || 
        message.contains('网络') || message.contains('连接')) {
      return '网络连接不稳定，请检查网络后重试';
    }
    
    if (message.contains('rate limit') || message.contains('too many') || 
        message.contains('频率') || message.contains('限制')) {
      return '请求过于频繁，请稍等片刻后重试';
    }
    
    if (message.contains('invalid') || message.contains('无效') || 
        message.contains('bad request')) {
      return '请求参数有误，请重新配置后重试';
    }
    
    if (message.contains('unauthorized') || message.contains('permission') || 
        message.contains('未授权') || message.contains('权限')) {
      return '授权已过期，请重新登录后重试';
    }
    
    if (message.contains('server error') || message.contains('internal') || 
        message.contains('服务器') || message.contains('内部错误')) {
      return '服务器暂时无法处理请求，请稍后重试';
    }
    
    if (message.contains('model') || message.contains('模型')) {
      return 'AI模型暂时不可用，请尝试切换其他模型';
    }
    
    if (message.contains('quota') || message.contains('balance') || 
        message.contains('额度') || message.contains('余额')) {
      return '账户余额不足或已达到使用限额';
    }
    
    // 如果无法识别具体错误类型，返回通用友好提示
    return '生成过程中遇到问题，请重试或联系客服';
  }

  /// 检查是否可以重试
  bool _canRetry() {
    return lastInitialPrompt != null && 
           lastStrategy != null && 
           lastModelConfigId != null;
  }

  /// 重试生成
  void _retryGeneration(BuildContext context) {
    if (!_canRetry()) return;
    
    // 重试时无法保证仍保留公共模型对象，这里仅传基础参数；若有需要可在Bloc中从上次session metadata取回
    context.read<SettingGenerationBloc>().add(
      StartGenerationEvent(
        initialPrompt: lastInitialPrompt!,
        promptTemplateId: lastStrategy!,
        novelId: novelId,
        modelConfigId: lastModelConfigId!,
        userId: userId ?? 'current_user',
      ),
    );
  }

  /// 重置并重新加载
  void _resetAndReload(BuildContext context) {
    context.read<SettingGenerationBloc>().add(const LoadStrategiesEvent());
  }

  /// 构建空状态提示视图
  Widget _buildEmptyStateView(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 🔧 新增：构建节点修改中视图
  Widget _buildNodeUpdatingView(BuildContext context, SettingGenerationNodeUpdating state) {
    AppLogger.i('SettingsTreeWidget', '🔧 渲染节点修改中状态 - 修改节点: ${state.updatingNodeId}');
    
    // 使用TopToast显示修改提示
    if (state.isUpdating && state.message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TopToast.info(
          context,
          state.message,
        );
      });
    }
    
    // 显示设定树，突出显示正在修改的节点
    return _buildTreeView(
            context,
            state.activeSession.rootNodes,
            state.selectedNodeId,
            state.viewMode,
            state.renderedNodeIds,
    );
  }

  /// 🔧 新增：构建保存成功视图
  Widget _buildSavedView(BuildContext context, SettingGenerationSaved state) {
    AppLogger.i('SettingsTreeWidget', '💾 渲染保存成功状态');
    
    // 尝试从sessions中找到当前活跃会话以渲染
    if (state.sessions.isNotEmpty && state.activeSessionId != null) {
      final session = state.sessions.firstWhere(
        (s) => s.sessionId == state.activeSessionId,
        orElse: () => state.sessions.first,
      );
      return _buildTreeView(
        context,
        session.rootNodes,
        null, // 保存操作后保持原选中节点逻辑，可根据需要扩展
        'compact',
        const {},
      );
    }
    // 如果找不到会话，显示空状态
    AppLogger.w('SettingsTreeWidget', '⚠️ 保存状态下找不到活跃会话，显示空状态');
    return _buildEmptyStateView(context, '设定已保存，但无法显示内容');
  }

  /// 🔧 新增：构建无会话视图
  Widget _buildNoSessionView(BuildContext context, dynamic state) {
    // 检查是否有活跃会话
    if (state is SettingGenerationReady) {
      AppLogger.i('SettingsTreeWidget', '📋 渲染就绪状态 - 活跃会话: ${state.activeSessionId}');
      // 如果有活跃会话，显示对应的设定树
      if (state.activeSessionId != null && state.sessions.isNotEmpty) {
        final session = state.sessions.firstWhere(
          (s) => s.sessionId == state.activeSessionId,
          orElse: () => state.sessions.first,
        );
        // 如果会话有内容，显示设定树
        if (session.rootNodes.isNotEmpty) {
          AppLogger.i('SettingsTreeWidget', '🌳 就绪状态下显示设定树 - 节点数: ${session.rootNodes.length}');
          return _buildTreeView(
            context,
            session.rootNodes,
            null, // SettingGenerationReady 没有 selectedNodeId
            state.viewMode,
            const {},
          );
        }
      }
    }
    
    // 默认显示无会话提示
    AppLogger.i('SettingsTreeWidget', '📝 显示无会话提示');
    return _buildEmptyStateView(context, '请开始生成设定或选择已有历史记录');
  }
}
