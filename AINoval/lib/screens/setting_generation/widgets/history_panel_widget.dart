import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_event.dart';
import '../../../blocs/setting_generation/setting_generation_state.dart';
import '../../../models/setting_generation_session.dart';

/// 历史面板组件
class HistoryPanelWidget extends StatefulWidget {
  const HistoryPanelWidget({Key? key}) : super(key: key);

  @override
  State<HistoryPanelWidget> createState() => _HistoryPanelWidgetState();
}

class _HistoryPanelWidgetState extends State<HistoryPanelWidget> {
  // 多选模式状态
  bool _isMultiSelectMode = false;
  final Set<String> _selectedSessionIds = {};

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
              builder: (context, state) {
                return _buildSessionList(context, state);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            _isMultiSelectMode ? '已选 ${_selectedSessionIds.length}' : '历史记录',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_isMultiSelectMode) ...[
            // 多选模式：显示批量删除和取消按钮
            IconButton(
              onPressed: _selectedSessionIds.isEmpty
                  ? null
                  : () => _handleBatchDelete(context),
              icon: const Icon(Icons.delete_outline),
              iconSize: 20,
              tooltip: '批量删除',
              color: Colors.red,
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isMultiSelectMode = false;
                  _selectedSessionIds.clear();
                });
              },
              icon: const Icon(Icons.close),
              iconSize: 20,
              tooltip: '取消',
            ),
          ] else ...[
            // 普通模式：显示多选和新建按钮
            IconButton(
              onPressed: () {
                setState(() {
                  _isMultiSelectMode = true;
                });
              },
              icon: const Icon(Icons.checklist),
              iconSize: 20,
              tooltip: '多选',
            ),
            IconButton(
              onPressed: () {
                context.read<SettingGenerationBloc>().add(
                  const CreateNewSessionEvent(),
                );
              },
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 20,
              tooltip: '新建会话',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionList(BuildContext context, SettingGenerationState state) {
    List<SettingGenerationSession> sessions = [];
    String? activeSessionId;
    
    if (state is SettingGenerationReady) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    } else if (state is SettingGenerationInProgress) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    } else if (state is SettingGenerationCompleted) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    } else if (state is SettingGenerationNodeUpdating) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    } else if (state is SettingGenerationSaved) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    } else if (state is SettingGenerationError) {
      sessions = state.sessions;
      activeSessionId = state.activeSessionId;
    }

    if (sessions.isEmpty) {
      return _buildEmptyView(context);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      child: ListView.builder(
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isActive = session.sessionId == activeSessionId;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildSessionItem(
              context,
              session,
              isActive,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 32,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无历史记录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem(
    BuildContext context,
    SettingGenerationSession session,
    bool isActive,
  ) {
    final isSelected = _selectedSessionIds.contains(session.sessionId);
    
    return InkWell(
      onTap: () {
        if (_isMultiSelectMode) {
          // 多选模式：切换选中状态
          setState(() {
            if (isSelected) {
              _selectedSessionIds.remove(session.sessionId);
            } else {
              _selectedSessionIds.add(session.sessionId);
            }
          });
        } else {
          // 普通模式：加载历史记录
          // 判断是否为历史会话（已保存的会话）
          final isHistorySession = session.status == SessionStatus.saved;
          
          final needFetch = session.rootNodes.isEmpty;

          if (isHistorySession || needFetch) {
            // saved 会话 或者 节点为空的会话，都尝试从后端拉取完整数据
            context.read<SettingGenerationBloc>().add(
              CreateSessionFromHistoryEvent(
                historyId: session.sessionId,
                userId: session.userId,
                editReason: '查看历史设定',
                modelConfigId: session.modelConfigId ?? 'default',
              ),
            );
          } else {
            // 本地已有节点数据，直接切换
            context.read<SettingGenerationBloc>().add(
              SelectSessionEvent(session.sessionId, isHistorySession: false),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? WebTheme.getPrimaryColor(context).withOpacity(0.2)
              : (isActive
                  ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
                  : Colors.transparent),
          border: (isSelected || isActive)
              ? Border.all(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isMultiSelectMode) ...[
              // 多选模式：显示复选框
              Icon(
                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: isSelected 
                    ? WebTheme.getPrimaryColor(context)
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 8),
            ] else ...[
              // 普通模式：显示状态图标
              _buildStatusIcon(session.status),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getSessionTitle(session),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isActive
                          ? WebTheme.getPrimaryColor(context)
                          : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(session.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isMultiSelectMode) ...[
              // 普通模式：显示删除按钮
              IconButton(
                onPressed: () => _handleDeleteSingle(context, session),
                icon: const Icon(Icons.delete_outline),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '删除',
                color: Colors.red.withOpacity(0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(SessionStatus status) {
    IconData icon;
    Color color;
    
    switch (status) {
      case SessionStatus.initializing:
        icon = Icons.pending;
        color = Colors.orange;
        break;
      case SessionStatus.generating:
        icon = Icons.autorenew;
        color = Colors.blue;
        break;
      case SessionStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SessionStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      case SessionStatus.saved:
        icon = Icons.cloud_done;
        color = Colors.teal;
        break;
    }
    
    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  String _getSessionTitle(SettingGenerationSession session) {
    final prompt = session.initialPrompt;
    if (prompt.length > 30) {
      return '${prompt.substring(0, 27)}...';
    }
    return prompt.isEmpty ? '新的创作...' : prompt;
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 处理单个删除
  void _handleDeleteSingle(BuildContext context, SettingGenerationSession session) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除历史记录"${_getSessionTitle(session)}"吗？\n\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<SettingGenerationBloc>().add(
                DeleteHistoryEvent(session.sessionId),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('历史记录已删除')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 处理批量删除
  void _handleBatchDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认批量删除'),
        content: Text('确定要删除选中的 ${_selectedSessionIds.length} 条历史记录吗？\n\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              final idsToDelete = _selectedSessionIds.toList();
              context.read<SettingGenerationBloc>().add(
                BatchDeleteHistoriesEvent(idsToDelete),
              );
              setState(() {
                _isMultiSelectMode = false;
                _selectedSessionIds.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除 ${idsToDelete.length} 条历史记录')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
