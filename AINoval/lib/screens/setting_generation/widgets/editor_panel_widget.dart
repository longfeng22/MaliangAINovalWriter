import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_event.dart';
import '../../../blocs/setting_generation/setting_generation_state.dart';
import '../../../models/setting_node.dart';
import '../../../widgets/common/model_display_selector.dart';
import '../../../models/unified_ai_model.dart';
import '../../../utils/logger.dart';
// import '../../../config/app_config.dart';

/// 编辑面板组件
class EditorPanelWidget extends StatefulWidget {
  final String? novelId;
  
  const EditorPanelWidget({
    Key? key,
    this.novelId,
  }) : super(key: key);

  @override
  State<EditorPanelWidget> createState() => _EditorPanelWidgetState();
}

class _EditorPanelWidgetState extends State<EditorPanelWidget> {
  final TextEditingController _modificationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  UnifiedAIModel? _selectedModel;
  String _selectedScope = 'self';
  String? _currentNodeId;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 当用户输入修改提示时，立即触发重建以刷新“生成修改”按钮可用态
    _modificationController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _modificationController.dispose();
    _descriptionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        // Ctrl+Enter -> 生成修改
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter): const _GenerateModificationIntent(),
        // Ctrl+S -> 保存当前节点内容
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const _SaveNodeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GenerateModificationIntent: CallbackAction<_GenerateModificationIntent>(
            onInvoke: (intent) {
              _triggerGenerateModificationViaShortcut();
              return null;
            },
          ),
          _SaveNodeIntent: CallbackAction<_SaveNodeIntent>(
            onInvoke: (intent) {
              _triggerSaveNodeContentViaShortcut();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Card(
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
          _buildHeader(),
          Expanded(
            child: BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
              builder: (context, state) {
                return _buildContent(context, state);
              },
            ),
          ),
        ],
      ),
            ),
          ),
        ),
      );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.edit,
            size: 20,
            color: WebTheme.getPrimaryColor(context),
          ),
          const SizedBox(width: 8),
          Text(
            '节点编辑',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SettingGenerationState state) {
    SettingNode? selectedNode;
    bool hasSession = false;
    
    if (state is SettingGenerationInProgress) {
      selectedNode = state.selectedNode;
      hasSession = true;
    } else if (state is SettingGenerationCompleted) {
      selectedNode = _findNodeById(state.activeSession.rootNodes, state.selectedNodeId ?? '');
      hasSession = true;
    } else if (state is SettingGenerationNodeUpdating) {
      // 🔧 新增：支持节点修改状态
      selectedNode = _findNodeById(state.activeSession.rootNodes, state.selectedNodeId ?? '');
      hasSession = true;
    }

    if (selectedNode != null && selectedNode.id != _currentNodeId) {
      _currentNodeId = selectedNode.id;
      _descriptionController.text = selectedNode.description;
    } else if (selectedNode != null && _currentNodeId == selectedNode.id) {
      // 🔧 关键修复：即便选中的节点未变，只要描述发生变化也要同步到输入框
      if (_descriptionController.text != selectedNode.description) {
        _descriptionController.text = selectedNode.description;
      }
    } else if (selectedNode == null) {
      _currentNodeId = null;
      _descriptionController.text = '';
    }

    if (!hasSession) {
      return _buildNoSessionView();
    }

    if (selectedNode == null) {
      return _buildNoSelectionView();
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNodeInfo(selectedNode, hasSession),
            const SizedBox(height: 16),
            _buildModificationSection(),
            const SizedBox(height: 16),
            _buildScopeSelector(),
            const SizedBox(height: 16),
            _buildModelSelector(),
            const SizedBox(height: 16),
            _buildActionButtons(selectedNode),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSessionView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 48,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 16),
          Text(
            '无活跃会话',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '请先生成设定或选择已有会话',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelectionView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app,
            size: 48,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 16),
          Text(
            '未选中节点',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '请在中间面板中点击一个设定节点进行编辑',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNodeInfo(SettingNode node, bool hasSession) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.label,
                size: 16,
                color: WebTheme.getPrimaryColor(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                   style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getPrimaryColor(context),
                  ),
                ),
              ),
              _buildStatusChip(node.generationStatus),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '节点描述',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: '请输入节点描述...',
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.all(12),
                ),
                maxLines: 20,
                enabled: hasSession,
              ),
              const SizedBox(height: 8),
              // 保存节点设定按钮
              SizedBox(
                width: double.infinity,
                child: BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
                  builder: (context, state) {
                    return ElevatedButton(
                      onPressed: hasSession && _currentNodeId != null
                          ? () {
                              // 🔧 简化：直接更新节点内容
                              context.read<SettingGenerationBloc>().add(
                                UpdateNodeContentEvent(
                                  nodeId: _currentNodeId!,
                                  content: _descriptionController.text,
                                ),
                              );
                            }
                          : null,
                      style: WebTheme.getPrimaryButtonStyle(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save, size: 16),
                          const SizedBox(width: 6),
                          Text('保存节点设定', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(GenerationStatus status) {
    Color color;
    String text;
    
    switch (status) {
      case GenerationStatus.pending:
        color = Colors.orange;
        text = '待生成';
        break;
      case GenerationStatus.generating:
        color = Colors.blue;
        text = '生成中';
        break;
      case GenerationStatus.completed:
        color = Colors.green;
        text = '已完成';
        break;
      case GenerationStatus.failed:
        color = Colors.red;
        text = '失败';
        break;
      case GenerationStatus.modified:
        color = Colors.purple;
        text = '已修改';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '修改提示',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _modificationController,
          decoration: InputDecoration(
            hintText: '描述您希望对此节点做出的修改...',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
          ),
          maxLines: 20,
        ),
      ],
    );
  }

  Widget _buildScopeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '修改范围',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedScope,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
          ),
          items: const [
            DropdownMenuItem(
              value: 'self',
              child: Text('仅当前节点'),
            ),
            DropdownMenuItem(
              value: 'self_and_children',
              child: Text('当前节点及子节点'),
            ),
            DropdownMenuItem(
              value: 'children_only',
              child: Text('仅子节点'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedScope = value;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildModelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI模型',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ModelDisplaySelector(
          selectedModel: _selectedModel,
          onModelSelected: (model) {
            setState(() {
              _selectedModel = model;
            });
          },
          size: ModelDisplaySize.medium,
          height: 60, // 扩大一倍高度 (36px * 2)
          showIcon: true,
          showTags: true,
          showSettingsButton: false,
          placeholder: '选择AI模型',
        ),
      ],
    );
  }

  Widget _buildActionButtons(SettingNode node) {
    return Column(
      children: [
        BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
          builder: (context, state) {
            // 🔧 新增：判断是否正在修改当前节点
            bool isCurrentNodeUpdating = false;
            if (state is SettingGenerationNodeUpdating) {
              isCurrentNodeUpdating = state.updatingNodeId == node.id && state.isUpdating;
            }
            
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // 按钮可用条件：
                // 1. 不在当前节点的修改流程中
                // 2. 已输入修改提示
                // 3. 已选择模型
                onPressed: (isCurrentNodeUpdating || 
                            _modificationController.text.trim().isEmpty ||
                            _getModelConfigId(state) == null)
                    ? null
                    : () {
                        _handleNodeModification(node);
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isCurrentNodeUpdating) ...[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('修改中...'),
                    ] else ...[
                      const Icon(Icons.auto_fix_high, size: 16),
                      const SizedBox(width: 8),
                      Text('生成修改'),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
          builder: (context, state) {
            bool hasPendingChanges = false;
            if (state is SettingGenerationInProgress) {
              hasPendingChanges = state.pendingChanges.isNotEmpty;
            } else if (state is SettingGenerationCompleted) {
              hasPendingChanges = state.pendingChanges.isNotEmpty;
            } else if (state is SettingGenerationNodeUpdating) {
              hasPendingChanges = state.pendingChanges.isNotEmpty;
            }
            
            if (!hasPendingChanges) {
              return const SizedBox.shrink();
            }
            
            return Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<SettingGenerationBloc>().add(
                        const CancelPendingChangesEvent(),
                      );
                    },
                    style: WebTheme.getSecondaryButtonStyle(context),
                    child: const Text('取消', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<SettingGenerationBloc>().add(
                        const ApplyPendingChangesEvent(),
                      );
                    },
                    style: WebTheme.getPrimaryButtonStyle(context),
                    child: const Text('应用', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 在设定节点树中查找指定ID的节点
  SettingNode? _findNodeById(List<SettingNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
      if (node.children != null) {
        final found = _findNodeById(node.children!, id);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  void _handleNodeModification(SettingNode node) {
    final currentState = context.read<SettingGenerationBloc>().state;
    AppLogger.i('EditorPanelWidget', '🔧 开始节点修改 - 当前状态: ${currentState.runtimeType}, 节点ID: ${node.id}');

    // 计算模型配置ID：仅使用下拉框当前选择的模型
    final modelConfigId = _getModelConfigId(currentState);
    if (modelConfigId == null) {
      AppLogger.w('EditorPanelWidget', '❌ 未选择模型，无法修改');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择AI模型'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (currentState is SettingGenerationInProgress ||
        currentState is SettingGenerationCompleted ||
        currentState is SettingGenerationNodeUpdating) {
      AppLogger.i('EditorPanelWidget', '✅ 发送UpdateNodeEvent - 节点ID: ${node.id}');

      context.read<SettingGenerationBloc>().add(
        UpdateNodeEvent(
          nodeId: node.id,
          modificationPrompt: _modificationController.text.trim(),
          modelConfigId: modelConfigId,
          scope: _selectedScope,
          isPublicModel: _selectedModel?.isPublic,
          publicModelConfigId: _selectedModel?.isPublic == true ? _selectedModel!.id : null,
        ),
      );

      // 清空修改提示词
      _modificationController.clear();
    } else {
      AppLogger.w('EditorPanelWidget', '❌ 当前状态不支持节点修改: ${currentState.runtimeType}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前状态不支持节点修改，请先生成设定或加载历史记录'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// 获取当前可用的模型配置ID
  /// 仅使用下拉框当前选择的模型（不再回退到会话/metadata）
  String? _getModelConfigId(SettingGenerationState state) {
    return _selectedModel?.id;
  }

  // ====== 快捷键意图与处理 ======
}

class _GenerateModificationIntent extends Intent {
  const _GenerateModificationIntent();
}

class _SaveNodeIntent extends Intent {
  const _SaveNodeIntent();
}

extension on _EditorPanelWidgetState {
  void _triggerGenerateModificationViaShortcut() {
    // 条件：有选中节点 + 有修改提示 + 有模型
    if (_currentNodeId == null) return;
    if (_modificationController.text.trim().isEmpty) return;
    final currentState = context.read<SettingGenerationBloc>().state;
    final modelConfigId = _getModelConfigId(currentState);
    if (modelConfigId == null) return;

    context.read<SettingGenerationBloc>().add(
      UpdateNodeEvent(
        nodeId: _currentNodeId!,
        modificationPrompt: _modificationController.text.trim(),
        modelConfigId: modelConfigId,
        scope: _selectedScope,
        isPublicModel: _selectedModel?.isPublic,
        publicModelConfigId: _selectedModel?.isPublic == true ? _selectedModel!.id : null,
      ),
    );
  }

  void _triggerSaveNodeContentViaShortcut() {
    if (_currentNodeId == null) return;
    context.read<SettingGenerationBloc>().add(
      UpdateNodeContentEvent(
        nodeId: _currentNodeId!,
        content: _descriptionController.text,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已提交保存当前节点内容')),
    );
  }
}
