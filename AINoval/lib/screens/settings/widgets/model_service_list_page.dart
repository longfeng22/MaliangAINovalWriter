import 'package:ainoval/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:collection/collection.dart';

import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/screens/settings/widgets/model_provider_group_card.dart';
import 'package:ainoval/screens/settings/widgets/model_service_header.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/config/provider_icons.dart';

/// 模型服务列表页面
/// 显示按提供商分组的模型服务列表
class ModelServiceListPage extends StatefulWidget {
  const ModelServiceListPage({
    super.key,
    required this.userId,
    required this.onAddNew,
    required this.onEditConfig,
    required this.editorStateManager,
  });

  final String userId;
  final VoidCallback onAddNew;
  final Function(UserAIModelConfigModel) onEditConfig;
  final EditorStateManager editorStateManager;

  @override
  State<ModelServiceListPage> createState() => _ModelServiceListPageState();
}

class _ModelServiceListPageState extends State<ModelServiceListPage> {
  String _searchQuery = '';
  String _filterValue = 'all';
  Map<String, bool> _expandedProviders = {};
  
  // 添加缓存机制
  DateTime? _lastLoadTime;
  static const Duration _cacheValidDuration = Duration(minutes: 3);
  bool _isInitialLoad = true;

  bool get _shouldRefreshConfigs {
    if (_lastLoadTime == null || _isInitialLoad) return true;
    return DateTime.now().difference(_lastLoadTime!) > _cacheValidDuration;
  }

  @override
  void initState() {
    super.initState();
    _loadUserConfigs();
  }

  void _loadUserConfigs() {
    // 检查是否需要刷新
    if (!_shouldRefreshConfigs) {
      AppLogger.d('ModelServiceListPage', '使用缓存数据，跳过重新加载');
      return;
    }
    
    AppLogger.i('ModelServiceListPage', '开始加载用户配置');
    _lastLoadTime = DateTime.now();
    _isInitialLoad = false;
    
    context.read<AiConfigBloc>().add(LoadAiConfigs(userId: widget.userId));
  }

  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _handleFilterChange(String value) {
    setState(() {
      _filterValue = value;
    });
  }

  void _handleSetDefault(String configId) {
    AppLogger.i('ModelServiceListPage', '设置默认配置: $configId');
    widget.editorStateManager.setModelOperationInProgress(true);
    context.read<AiConfigBloc>().add(SetDefaultAiConfig(
      userId: widget.userId,
      configId: configId,
    ));
  }

  void _handleSetToolDefault(String configId) {
    AppLogger.i('ModelServiceListPage', '设置工具默认配置: $configId');
    widget.editorStateManager.setModelOperationInProgress(true);
    context.read<AiConfigBloc>().add(SetToolDefaultAiConfig(
      userId: widget.userId,
      configId: configId,
    ));
  }

  void _handleValidate(String configId) {
    AppLogger.i('ModelServiceListPage', '验证配置: $configId');
    widget.editorStateManager.setModelOperationInProgress(true);
    context.read<AiConfigBloc>().add(ValidateAiConfig(
      userId: widget.userId,
      configId: configId,
    ));
  }

  void _handleEdit(String configId) {
    final config = context.read<AiConfigBloc>().state.configs.firstWhereOrNull((c) => c.id == configId);
    if (config != null) {
      widget.onEditConfig(config);
    } else {
      TopToast.warning(context, "未找到要编辑的配置");
    }
  }

  void _handleDelete(String configId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除这个模型服务配置吗？此操作无法撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('删除'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                AppLogger.i('ModelServiceListPage', '删除配置: $configId');
                
                // 使缓存失效
                _lastLoadTime = null;
                
                context.read<AiConfigBloc>().add(DeleteAiConfig(
                  userId: widget.userId,
                  configId: configId,
                ));
              },
            ),
          ],
        );
      },
    );
  }

  void _handleAddModel(String provider) {
    // 调用父组件的回调，并传递选中的提供商
    widget.onAddNew();
  }

  void _handleToggleProvider(String provider) {
    setState(() {
      _expandedProviders[provider] = !(_expandedProviders[provider] ?? true);
    });
  }

  // 过滤配置列表
  List<UserAIModelConfigModel> _getFilteredConfigs(List<UserAIModelConfigModel> configs) {
    return configs.where((config) {
      final matchesSearch = _searchQuery.isEmpty ||
          config.alias.toLowerCase().contains(_searchQuery) ||
          config.provider.toLowerCase().contains(_searchQuery) ||
          config.modelName.toLowerCase().contains(_searchQuery);

      bool matchesFilter = true;
      if (_filterValue == 'verified') {
        matchesFilter = config.isValidated;
      } else if (_filterValue == 'unverified') {
        matchesFilter = !config.isValidated;
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // 按提供商分组配置
  Map<String, List<UserAIModelConfigModel>> _groupConfigsByProvider(List<UserAIModelConfigModel> configs) {
    final Map<String, List<UserAIModelConfigModel>> grouped = {};
    
    for (final config in configs) {
      final provider = config.provider;
      if (!grouped.containsKey(provider)) {
        grouped[provider] = [];
      }
      grouped[provider]!.add(config);
    }
    
    return grouped;
  }

  // 获取提供商信息
  Map<String, dynamic> _getProviderInfo(String provider) {
    return {
      'name': ProviderIcons.getProviderDisplayName(provider),
      'description': _getProviderDescription(provider),
      'icon': Icons.api, // 保留作为备用，但实际使用ProviderIcons
      'color': ProviderIcons.getProviderColor(provider),
    };
  }

  // 获取提供商描述
  String _getProviderDescription(String provider) {
    switch (provider.toLowerCase()) {
      case 'openai':
        return '适用于多种场景的先进语言模型';
      case 'anthropic':
        return '注重安全性的 Constitutional AI 模型';
      case 'google':
      case 'gemini':
        return 'Gemini 模型与 PaLM 系列';
      case 'openrouter':
        return '聚合多家模型的统一 API';
      case 'ollama':
        return '本地模型运行环境';
      case 'microsoft':
      case 'azure':
        return '微软 Azure OpenAI 服务';
      case 'meta':
      case 'llama':
        return 'Meta 大语言模型';
      case 'deepseek':
        return 'DeepSeek 语言模型';
      case 'zhipu':
      case 'glm':
        return 'GLM/ChatGLM 系列模型';
      case 'qwen':
      case 'tongyi':
        return '阿里云通义千问模型';
      case 'doubao':
      case 'bytedance':
        return '字节跳动豆包模型';
      case 'mistral':
        return 'Mistral 语言模型';
      case 'perplexity':
        return 'Perplexity 搜索与推理';
      case 'huggingface':
      case 'hf':
        return 'Hugging Face 模型库与推理';
      case 'stability':
        return 'Stability AI 生成模型';
      case 'xai':
      case 'grok':
        return 'xAI Grok 对话模型';
      case 'siliconcloud':
      case 'siliconflow':
        return '硅基流动模型服务';
      default:
        return 'AI 模型提供商';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // 头部
          ModelServiceHeader(
            onSearch: _handleSearch,
            onAddNew: widget.onAddNew,
            onFilterChange: _handleFilterChange,
          ),

          // 内容区域
          Expanded(
            child: BlocListener<AiConfigBloc, AiConfigState>(
              listener: (context, state) {
                // 处理验证成功后的状态重置
                if (state.actionStatus == AiConfigActionStatus.success ||
                    state.actionStatus == AiConfigActionStatus.error) {
                  widget.editorStateManager.setModelOperationInProgress(false);
                  
                  // 在操作成功后，标记需要刷新缓存
                  if (state.actionStatus == AiConfigActionStatus.success) {
                    _lastLoadTime = null; // 使缓存失效
                  }
                }
                
                // 显示操作结果提示 - 但排除API Key验证成功（由ai_config_form处理）
                if (state.actionStatus == AiConfigActionStatus.error && 
                    state.actionErrorMessage != null) {
                  TopToast.error(context, state.actionErrorMessage!);
                }
                // 注意：success状态的提示由具体的表单组件处理，避免重复提示
              },
              child: BlocBuilder<AiConfigBloc, AiConfigState>(
                builder: (context, state) {
                if (state.status == AiConfigStatus.loading && state.configs.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (state.errorMessage != null && state.configs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '加载失败',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            _lastLoadTime = null; // 强制刷新
                            _loadUserConfigs();
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }

                final filteredConfigs = _getFilteredConfigs(state.configs);
                final groupedConfigs = _groupConfigsByProvider(filteredConfigs);

                if (groupedConfigs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _filterValue != 'all'
                              ? '没有找到匹配的模型服务'
                              : '您还没有配置任何模型服务',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_searchQuery.isEmpty && _filterValue == 'all')
                          ElevatedButton.icon(
                            onPressed: widget.onAddNew,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('添加模型服务'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupedConfigs.length,
                  itemBuilder: (context, index) {
                    final provider = groupedConfigs.keys.elementAt(index);
                    final configs = groupedConfigs[provider]!;
                    final providerInfo = _getProviderInfo(provider);
                    final isExpanded = _expandedProviders[provider] ?? true;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ModelProviderGroupCard(
                        provider: provider,
                        providerName: providerInfo['name'],
                        description: providerInfo['description'],
                        icon: providerInfo['icon'],
                        color: providerInfo['color'],
                        configs: configs,
                        isExpanded: isExpanded,
                        onToggleExpanded: () => _handleToggleProvider(provider),
                        onAddModel: () => _handleAddModel(provider),
                        onSetDefault: _handleSetDefault,
                        onSetToolDefault: _handleSetToolDefault,
                        onValidate: _handleValidate,
                        onEdit: _handleEdit,
                        onDelete: _handleDelete,
                      ),
                    );
                  },
                );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
