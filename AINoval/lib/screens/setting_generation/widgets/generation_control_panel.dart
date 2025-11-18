import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_bloc.dart';
import '../../../blocs/setting_generation/setting_generation_event.dart';
import '../../../blocs/setting_generation/setting_generation_state.dart';
import '../../../models/unified_ai_model.dart';
import '../../../models/strategy_template_info.dart';
import '../../../models/setting_generation_session.dart';
import '../../../widgets/common/model_display_selector.dart';
import '../../../blocs/ai_config/ai_config_bloc.dart';
import 'strategy_selector_dropdown.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/screens/settings/settings_panel.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/models/knowledge_base_integration_mode.dart';
import 'package:ainoval/screens/setting_generation/widgets/knowledge_base_setting_selector.dart';

/// 生成控制面板
class GenerationControlPanel extends StatefulWidget {
  final String? initialPrompt;
  final UnifiedAIModel? selectedModel;
  final String? initialStrategy;
  final Function(String prompt, String strategy, String modelConfigId)? onGenerationStart;
  // 📚 知识库集成参数
  final KnowledgeBaseIntegrationMode? initialKnowledgeBaseMode;
  final List<SelectedKnowledgeBaseItem>? initialSelectedKnowledgeBases;
  // 📚 混合模式专用：参考列表
  final List<SelectedKnowledgeBaseItem>? initialReferenceKnowledgeBases;

  const GenerationControlPanel({
    Key? key,
    this.initialPrompt,
    this.selectedModel,
    this.initialStrategy,
    this.onGenerationStart,
    this.initialKnowledgeBaseMode,
    this.initialSelectedKnowledgeBases,
    this.initialReferenceKnowledgeBases,
  }) : super(key: key);

  @override
  State<GenerationControlPanel> createState() => _GenerationControlPanelState();
}

class _GenerationControlPanelState extends State<GenerationControlPanel> {
  late TextEditingController _promptController;
  UnifiedAIModel? _selectedModel;
  StrategyTemplateInfo? _selectedStrategy;
  // 🔧 跟踪当前活动的会话ID，用于检测会话切换
  String? _currentActiveSessionId;
  // 🔧 跟踪用户是否手动修改了原始创意，避免覆盖用户输入
  bool _userHasModifiedPrompt = false;
  // 📚 知识库集成模式
  KnowledgeBaseIntegrationMode _knowledgeBaseMode = KnowledgeBaseIntegrationMode.none;
  // 📚 选中的知识库项目（用于复用模式）
  List<SelectedKnowledgeBaseItem> _selectedKnowledgeBasesForReuse = [];
  // 📚 选中的知识库项目（用于仿写/混合模式）
  List<SelectedKnowledgeBaseItem> _selectedKnowledgeBasesForReference = [];

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.initialPrompt ?? '');
    // 注意：_selectedStrategy 将在策略加载完成后根据 widget.initialStrategy 设置

    // 获取用户默认模型配置
    final defaultConfig = context.read<AiConfigBloc>().state.defaultConfig ??
        (context.read<AiConfigBloc>().state.validatedConfigs.isNotEmpty
            ? context.read<AiConfigBloc>().state.validatedConfigs.first
            : null);

    _selectedModel = widget.selectedModel ??
        (defaultConfig != null ? PrivateAIModel(defaultConfig) : null);

    // 📚 初始化知识库参数
    if (widget.initialKnowledgeBaseMode != null) {
      _knowledgeBaseMode = widget.initialKnowledgeBaseMode!;
    }
    
    // 📚 混合模式：分别初始化复用和参考列表
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) {
      if (widget.initialSelectedKnowledgeBases != null && widget.initialSelectedKnowledgeBases!.isNotEmpty) {
        _selectedKnowledgeBasesForReuse = List.from(widget.initialSelectedKnowledgeBases!);
      }
      if (widget.initialReferenceKnowledgeBases != null && widget.initialReferenceKnowledgeBases!.isNotEmpty) {
        _selectedKnowledgeBasesForReference = List.from(widget.initialReferenceKnowledgeBases!);
      }
    } else if (widget.initialSelectedKnowledgeBases != null && widget.initialSelectedKnowledgeBases!.isNotEmpty) {
      // 📚 复用或仿写模式：根据模式分配到对应的列表
      if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse) {
        _selectedKnowledgeBasesForReuse = List.from(widget.initialSelectedKnowledgeBases!);
      } else {
        _selectedKnowledgeBasesForReference = List.from(widget.initialSelectedKnowledgeBases!);
      }
    }

    // 🔧 在初始化时同步当前活动会话的原始创意
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final currentState = context.read<SettingGenerationBloc>().state;
        _handleActiveSessionChange(currentState);
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  /// 🔧 新增：处理活动会话变化，自动填充原始创意
  void _handleActiveSessionChange(SettingGenerationState state) {
    String? activeSessionId;
    SettingGenerationSession? activeSession;

    // 从不同状态中提取活动会话信息
    if (state is SettingGenerationReady) {
      activeSessionId = state.activeSessionId;
      if (activeSessionId != null) {
        try {
          activeSession = state.sessions.firstWhere(
            (s) => s.sessionId == activeSessionId,
          );
        } catch (e) {
          activeSession = state.sessions.isNotEmpty ? state.sessions.first : null;
        }
      }
    } else if (state is SettingGenerationInProgress) {
      activeSessionId = state.activeSessionId;
      activeSession = state.activeSession;
    } else if (state is SettingGenerationCompleted) {
      activeSessionId = state.activeSessionId;
      activeSession = state.activeSession;
    } else if (state is SettingGenerationError) {
      activeSessionId = state.activeSessionId;
      if (activeSessionId != null) {
        try {
          activeSession = state.sessions.firstWhere(
            (s) => s.sessionId == activeSessionId,
          );
        } catch (e) {
          activeSession = state.sessions.isNotEmpty ? state.sessions.first : null;
        }
      }
    }

    // 检测会话是否发生变化
    if (_currentActiveSessionId != activeSessionId && activeSession != null) {
      _currentActiveSessionId = activeSessionId;
      
      // 🎯 核心功能：将历史记录的原始提示词填充到原始创意输入框
      final newPrompt = activeSession.initialPrompt;
      
      // 🔧 智能填充：只有在用户未手动修改原始创意时才自动填充
      // 或者当前输入框为空时总是填充
      final shouldUpdatePrompt = !_userHasModifiedPrompt || _promptController.text.trim().isEmpty;
      
      if (newPrompt.isNotEmpty && _promptController.text != newPrompt && shouldUpdatePrompt) {
        if (mounted) {
          setState(() {
            _promptController.text = newPrompt;
            // 重置用户修改标记，因为这是系统自动填充
            _userHasModifiedPrompt = false;
          });
        }
        
        // 📝 记录日志用于调试
        print('🔄 历史记录切换 - 原始创意已更新: ${newPrompt.substring(0, newPrompt.length > 50 ? 50 : newPrompt.length)}${newPrompt.length > 50 ? "..." : ""}');
      } else if (_userHasModifiedPrompt && newPrompt.isNotEmpty) {
        // 📝 用户已修改，不覆盖但记录日志
        print('🛡️ 历史记录切换 - 检测到用户已修改原始创意，跳过自动填充以保护用户输入');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return BlocListener<SettingGenerationBloc, SettingGenerationState>(
      listener: (context, state) {
        // 🔧 监听活动会话变化，自动填充原始创意
        _handleActiveSessionChange(state);
      },
      child: Container(
        color: WebTheme.getSurfaceColor(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Container(
                padding: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
                  ),
                ),
                child: Text(
                  '创作控制台',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 内容区域 - 自适应高度
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // 提示词输入区域 - 扩大空间
                        BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
                          builder: (context, state) {
                            return _buildPromptInput(state);
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // 策略选择器
                        _buildStrategySelector(),
                        const SizedBox(height: 16),
                        
                        // 📚 知识库模式选择器
                        _buildKnowledgeBaseModeSelector(),
                        const SizedBox(height: 16),
                        
                        // 📚 根据模式显示知识库选择器
                        if (_knowledgeBaseMode != KnowledgeBaseIntegrationMode.none) ...[
                          _buildKnowledgeBaseSelector(),
                          const SizedBox(height: 16),
                        ],
                        
                        // 模型选择器
                        _buildModelSelector(),
                        const SizedBox(height: 20),
                        
                        // 操作按钮
                        BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
                          builder: (context, state) {
                            return _buildActionButtons(state);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  

  Widget _buildPromptInput(SettingGenerationState state) {
    // 📚 复用模式下输入框不可编辑
    final isReadOnly = _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse;
    final hintText = isReadOnly
        ? '复用模式下无需输入提示词，直接选择知识库小说'
        : (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.imitation || 
           _knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid)
            ? '请详细描述生成需求，选中的知识库设定将作为参考加入提示词...'
            : '例如：一个发生在赛博朋克都市的侦探故事\n\n详细描述你的创作想法：\n• 故事背景和世界观设定\n• 主要角色的性格和关系\n• 核心冲突和情节走向\n• 想要表达的主题思想\n• 期望的风格和氛围...';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '原始创意',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: WebTheme.getBorderColor(context)),
            color: isReadOnly 
                ? WebTheme.getBorderColor(context).withOpacity(0.1)
                : null,
          ),
          child: TextField(
            controller: _promptController,
            enabled: !isReadOnly,
            readOnly: isReadOnly,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: WebTheme.getSecondaryTextColor(context),
                fontSize: 14,
                height: 1.4,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: isReadOnly 
                  ? WebTheme.getSecondaryTextColor(context)
                  : WebTheme.getTextColor(context),
            ),
            // 🎯 进一步扩大输入空间 - 支持更大的创作描述
            maxLines: 12,
            minLines: 6,
            textInputAction: TextInputAction.newline,
            onChanged: (value) {
              // 标记用户已手动修改原始创意
              _userHasModifiedPrompt = true;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStrategySelector() {
    return BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
      builder: (context, state) {
        List<StrategyTemplateInfo> strategies = []; // 策略列表
        bool isLoading = false;
        
        if (state is SettingGenerationReady) {
          strategies = state.strategies;
        } else if (state is SettingGenerationInProgress) {
          strategies = state.strategies;
        } else if (state is SettingGenerationCompleted) {
          strategies = state.strategies;
        } else if (state is SettingGenerationNodeUpdating) {
          // 节点修改过程中依然沿用已加载的策略，不显示加载骨架
          strategies = state.strategies;
        } else {
          isLoading = true;
        }

        // 🔧 修复：根据 initialStrategy 初始化选中的策略
        if (_selectedStrategy == null && strategies.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              StrategyTemplateInfo? initialSelected;
              if (widget.initialStrategy != null) {
                // 根据名称查找策略
                initialSelected = strategies.firstWhere(
                  (s) => s.name == widget.initialStrategy,
                  orElse: () => strategies.first,
                );
              } else {
                initialSelected = strategies.first;
              }
              setState(() {
                _selectedStrategy = initialSelected;
              });
            }
          });
        }

        // 确保当前选中的策略在可用列表中
        if (_selectedStrategy != null && !strategies.contains(_selectedStrategy)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && strategies.isNotEmpty) {
              setState(() {
                _selectedStrategy = strategies.first;
              });
            }
          });
        }

        return StrategySelectorDropdown(
          strategies: strategies,
          selectedStrategy: _selectedStrategy,
          isLoading: isLoading || strategies.isEmpty,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedStrategy = value;
              });
            }
          },
        );
      },
    );
  }

  Widget _buildModelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI模型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        ModelDisplaySelector(
          selectedModel: _selectedModel,
          onModelSelected: (model) {
            setState(() {
              _selectedModel = model;
            });
          },
          size: ModelDisplaySize.medium,
          height: 60,
          showIcon: true,
          showTags: true,
          showSettingsButton: false,
          placeholder: '选择AI模型',
        ),
      ],
    );
  }

  Widget _buildActionButtons(SettingGenerationState state) {
    final isGenerating = state is SettingGenerationInProgress && state.isGenerating;
    final hasGeneratedSettings = state is SettingGenerationInProgress ||
        state is SettingGenerationCompleted;
    
    // 📚 根据知识库模式决定按钮文本
    String buttonText = hasGeneratedSettings ? '重新生成' : '生成设定';
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse) {
      buttonText = '开始设定复用';
    }
    
    // 📚 根据知识库模式决定按钮是否可用
    bool canGenerate = false;
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse) {
      // 复用模式：只需选择知识库即可
      canGenerate = !isGenerating && 
                   _selectedModel != null && 
                   _selectedKnowledgeBasesForReuse.isNotEmpty;
    } else if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.none) {
      // 普通模式：需要输入提示词
      canGenerate = !isGenerating && 
                   _selectedModel != null && 
                   _promptController.text.trim().isNotEmpty;
    } else {
      // 仿写/混合模式：需要输入提示词和选择知识库
      canGenerate = !isGenerating && 
                   _selectedModel != null && 
                   _promptController.text.trim().isNotEmpty &&
                   _selectedKnowledgeBasesForReference.isNotEmpty;
    }

    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canGenerate
            ? () async {
                final ok = await _precheckToolModelAndMaybePrompt();
                if (!ok) return;
                final prompt = _promptController.text.trim();
                final strategy = _selectedStrategy;
                final modelConfigId = _selectedModel!.id;
                
                if (strategy != null) {
                  // 通知主屏幕更新参数 - 传递策略名称用于显示
                  widget.onGenerationStart?.call(prompt, strategy.name, modelConfigId);
                  
                  final model = _selectedModel!;
                  final bool usePublic = model.isPublic;
                  final String? publicProvider = usePublic ? model.provider : null;
                  final String? publicModelId = usePublic ? model.modelId : null;

                  // 📚 准备知识库参数
                  String? knowledgeBaseMode;
                  List<String>? knowledgeBaseIds;
                  List<String>? reuseKnowledgeBaseIds;
                  List<String>? referenceKnowledgeBaseIds;
                  Map<String, List<String>>? knowledgeBaseCategories;
                  
                  if (_knowledgeBaseMode != KnowledgeBaseIntegrationMode.none) {
                    knowledgeBaseMode = _knowledgeBaseMode.value;
                    
                    // 📚 混合模式：分别处理复用和参考
                    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) {
                      // 复用列表
                      if (_selectedKnowledgeBasesForReuse.isNotEmpty) {
                        reuseKnowledgeBaseIds = _selectedKnowledgeBasesForReuse
                            .map((item) => item.knowledgeBaseId)
                            .toList();
                      }
                      
                      // 参考列表
                      if (_selectedKnowledgeBasesForReference.isNotEmpty) {
                        referenceKnowledgeBaseIds = _selectedKnowledgeBasesForReference
                            .map((item) => item.knowledgeBaseId)
                            .toList();
                      }
                      
                      // 合并分类
                      knowledgeBaseCategories = {};
                      for (var item in _selectedKnowledgeBasesForReuse) {
                        knowledgeBaseCategories[item.knowledgeBaseId] = 
                            item.selectedCategories.map((c) => c.value).toList();
                      }
                      for (var item in _selectedKnowledgeBasesForReference) {
                        knowledgeBaseCategories[item.knowledgeBaseId] = 
                            item.selectedCategories.map((c) => c.value).toList();
                      }
                    } else {
                      // 📚 复用或仿写模式：使用通用的knowledgeBaseIds
                      final selectedItems = _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                          ? _selectedKnowledgeBasesForReuse
                          : _selectedKnowledgeBasesForReference;
                      
                      if (selectedItems.isNotEmpty) {
                        knowledgeBaseIds = selectedItems.map((item) => item.knowledgeBaseId).toList();
                        knowledgeBaseCategories = {};
                        for (var item in selectedItems) {
                          knowledgeBaseCategories[item.knowledgeBaseId] = 
                              item.selectedCategories.map((c) => c.value).toList();
                        }
                      }
                    }
                  }

                  context.read<SettingGenerationBloc>().add(
                    StartGenerationEvent(
                      initialPrompt: prompt,
                      promptTemplateId: strategy.promptTemplateId,
                      modelConfigId: modelConfigId,
                      usePublicTextModel: usePublic,
                      textPhasePublicProvider: publicProvider,
                      textPhasePublicModelId: publicModelId,
                      knowledgeBaseMode: knowledgeBaseMode,
                      knowledgeBaseIds: knowledgeBaseIds,
                      knowledgeBaseCategories: knowledgeBaseCategories,
                      // 📚 混合模式专用参数
                      reuseKnowledgeBaseIds: reuseKnowledgeBaseIds,
                      referenceKnowledgeBaseIds: referenceKnowledgeBaseIds,
                      // 🔧 结构化输出循环模式参数（默认启用）
                      useStructuredOutput: true,
                      structuredIterations: 3,
                    ),
                  );
                }
              }
            : null,
        style: WebTheme.getPrimaryButtonStyle(context),
        child: isGenerating
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '生成中...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                        ? Icons.file_copy
                        : (hasGeneratedSettings ? Icons.refresh : Icons.auto_awesome),
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    buttonText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 📚 构建知识库模式选择器
  Widget _buildKnowledgeBaseModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '知识库模式',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '使用知识库中的小说设定来辅助生成',
              child: Icon(
                Icons.help_outline,
                size: 16,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: WebTheme.getBorderColor(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<KnowledgeBaseIntegrationMode>(
            value: _knowledgeBaseMode,
            isExpanded: true,
            underline: const SizedBox(),
            icon: Icon(
              Icons.arrow_drop_down,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getTextColor(context),
            ),
            onChanged: (mode) {
              if (mode != null) {
                setState(() {
                  _knowledgeBaseMode = mode;
                  // 切换模式时清空选择
                  _selectedKnowledgeBasesForReuse = [];
                  _selectedKnowledgeBasesForReference = [];
                });
              }
            },
            items: KnowledgeBaseIntegrationMode.values.map((mode) {
              return DropdownMenuItem(
                value: mode,
                child: Tooltip(
                  message: mode.description,
                  child: Text(
                    mode.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // 显示模式说明
        if (_knowledgeBaseMode != KnowledgeBaseIntegrationMode.none) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              border: Border.all(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _knowledgeBaseMode.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: WebTheme.getTextColor(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 📚 构建知识库选择器
  Widget _buildKnowledgeBaseSelector() {
    // 混合模式：显示两个选择器（复用 + 参考）
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 复用知识库选择器
          Text(
            '复用知识库设定',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
              border: Border.all(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.2),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '这些设定将被直接复用（不经过AI）',
                    style: TextStyle(
                      fontSize: 11,
                      color: WebTheme.getTextColor(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          KnowledgeBaseSettingSelector(
            selectedItems: _selectedKnowledgeBasesForReuse,
            onSelectionChanged: (items) {
              setState(() {
                _selectedKnowledgeBasesForReuse = items;
              });
            },
            multipleSelection: true, // 混合模式下复用也支持多选
            hintText: '搜索要复用的知识库小说（支持多选）...',
          ),
          const SizedBox(height: 24),
          
          // 参考知识库选择器
          Text(
            '参考知识库设定',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: WebTheme.getSecondaryColor(context).withOpacity(0.05),
              border: Border.all(
                color: WebTheme.getSecondaryColor(context).withOpacity(0.2),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: WebTheme.getSecondaryColor(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '这些设定将加入提示词，作为AI参考',
                    style: TextStyle(
                      fontSize: 11,
                      color: WebTheme.getTextColor(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          KnowledgeBaseSettingSelector(
            selectedItems: _selectedKnowledgeBasesForReference,
            onSelectionChanged: (items) {
              setState(() {
                _selectedKnowledgeBasesForReference = items;
              });
            },
            multipleSelection: true,
            hintText: '搜索参考的知识库小说（支持多选）...',
          ),
        ],
      );
    }
    
    // 其他模式：单个选择器
    final selectedItems = _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
        ? _selectedKnowledgeBasesForReuse
        : _selectedKnowledgeBasesForReference;
    
    final multipleSelection = true; // 全部改为支持多选
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择知识库小说',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        KnowledgeBaseSettingSelector(
          selectedItems: selectedItems,
          onSelectionChanged: (items) {
            setState(() {
              if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse) {
                _selectedKnowledgeBasesForReuse = items;
              } else {
                _selectedKnowledgeBasesForReference = items;
              }
            });
          },
          multipleSelection: multipleSelection,
          hintText: '搜索知识库小说（支持多选）...',
        ),
      ],
    );
  }

  /// 轻量前置检查：当没有可用公共模型或缺少 jsonify/jsonIf 标签，且用户也未设置"工具调用默认"时，提示去设置。
  /// 返回 true 表示继续生成，false 表示用户选择了取消或去设置。
  Future<bool> _precheckToolModelAndMaybePrompt() async {
    // 用户已设置工具默认且已验证 → 直接通过
    final aiState = context.read<AiConfigBloc>().state;
    final hasToolDefault = aiState.configs.any((c) => c.isToolDefault && c.isValidated);
    if (hasToolDefault) return true;

    // 公共模型检查（仅在已加载时判断，避免阻塞）
    final publicBloc = context.read<PublicModelsBloc>();
    final publicState = publicBloc.state;
    bool needPrompt = false;
    if (publicState is PublicModelsLoaded) {
      final models = publicState.models;
      final tagsNeedles = {'jsonify', 'jsonif', 'json-if', 'json_if'};
      final hasJsonifyTag = models.any((m) => (m.tags ?? const <String>[]) 
          .map((t) => t.toLowerCase())
          .any((t) => tagsNeedles.contains(t)));
      final noPublic = models.isEmpty;
      needPrompt = noPublic || !hasJsonifyTag;
    } else {
      // 轻量：若未加载，不做拦截
      needPrompt = false;
    }

    if (!needPrompt) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请配置工具调用模型'),
        content: const Text('未检测到可用的公共工具模型或缺少 jsonify 标签。建议先在“模型服务管理”中设置一个工具调用默认模型（成本低、速度快），例如：Gemini 2.0 Flash。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(false);
              final userId = AppConfig.userId ?? '';
              await showDialog(
                context: context,
                barrierDismissible: true,
                builder: (dialogContext) => Dialog(
                  insetPadding: const EdgeInsets.all(16),
                  backgroundColor: Colors.transparent,
                  child: SettingsPanel(
                    stateManager: EditorStateManager(),
                    userId: userId,
                    onClose: () => Navigator.of(dialogContext).pop(),
                    editorSettings: const EditorSettings(),
                    onEditorSettingsChanged: (_) {},
                    initialCategoryIndex: 0, // 聚焦“模型服务”
                  ),
                ),
              );
            },
            child: const Text('去设置'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续生成'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }
}
