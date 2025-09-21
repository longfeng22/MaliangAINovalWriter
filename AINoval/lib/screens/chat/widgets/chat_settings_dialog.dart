import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/widgets/common/index.dart';
// import 'package:ainoval/widgets/common/model_selector.dart' as ModelSelectorWidget;
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/prompt_preview_widget.dart';
import 'package:ainoval/services/api_service/repositories/universal_ai_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/universal_ai_repository_impl.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/preset_models.dart';
// import 'package:ainoval/services/ai_preset_service.dart';
import 'package:ainoval/config/app_config.dart';
// import 'package:ainoval/config/provider_icons.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
// import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart'; // 🚀 新增：导入PromptNewBloc

/// 聊天设置对话框
/// 从模型选择器的"调整并生成"按钮触发
class ChatSettingsDialog extends StatefulWidget {
  /// 构造函数
  const ChatSettingsDialog({
    super.key,
    this.aiConfigBloc,
    this.selectedModel,
    this.onModelChanged,
    this.onSettingsSaved,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.initialChatConfig,
    this.onConfigChanged,
    this.initialContextSelections,
  });

  /// AI配置Bloc
  final AiConfigBloc? aiConfigBloc;

  /// 当前选中的模型
  final UserAIModelConfigModel? selectedModel;

  /// 模型改变回调
  final ValueChanged<UserAIModelConfigModel?>? onModelChanged;

  /// 设置保存回调
  final VoidCallback? onSettingsSaved;

  /// 小说数据（用于构建上下文选择）
  final Novel? novel;
  
  /// 设定数据
  final List<NovelSettingItem> settings;
  
  /// 设定组数据
  final List<SettingGroup> settingGroups;
  
  /// 片段数据
  final List<NovelSnippet> snippets;
  
  /// 🚀 新增：初始聊天配置
  final UniversalAIRequest? initialChatConfig;
  
  /// 🚀 新增：配置变更回调
  final ValueChanged<UniversalAIRequest>? onConfigChanged;
  
  /// 🚀 新增：初始上下文选择数据（从全局获取）
  final ContextSelectionData? initialContextSelections;

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> with AIDialogCommonLogic {
  // 控制器
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _memoryCutoffController = TextEditingController();
  
  // 状态变量
  UserAIModelConfigModel? _selectedModel;
  UnifiedAIModel? _selectedUnifiedModel; // 🚀 新增：统一模型对象
  bool _enableSmartContext = true; // 🚀 新增：智能上下文开关，默认开启
  AIPromptPreset? _currentPreset; // 🚀 新增：当前选中的预设
  String? _selectedPromptTemplateId; // 🚀 新增：选中的提示词模板ID
  // 临时自定义提示词
  String? _customSystemPrompt;
  String? _customUserPrompt;
  double _temperature = 0.7; // 🚀 新增：温度参数
  double _topP = 0.9; // 🚀 新增：Top-P参数
  
  // 模型选择器key（用于FormDialogTemplate）
  final GlobalKey _modelSelectorKey = GlobalKey();
  
  // 新的上下文选择数据
  late ContextSelectionData _contextSelectionData;
  
  int? _selectedMemoryCutoff = 14;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.selectedModel;
    
    // 🚀 初始化统一模型对象
    if (widget.selectedModel != null) {
      _selectedUnifiedModel = PrivateAIModel(widget.selectedModel!);
    }
    
    // 🚀 从传入的配置初始化表单状态
    if (widget.initialChatConfig != null) {
      final config = widget.initialChatConfig!;
      
      // 初始化指令
      if (config.instructions != null) {
        _instructionsController.text = config.instructions!;
      }
      
      // 初始化智能上下文开关
      _enableSmartContext = config.enableSmartContext;
      
      // 初始化记忆截断
      final memoryCutoff = config.parameters['memoryCutoff'] as int?;
      if (memoryCutoff != null) {
        _selectedMemoryCutoff = memoryCutoff;
      }
      
      // 🚀 初始化温度参数
      final temperature = config.parameters['temperature'];
      if (temperature is double) {
        _temperature = temperature;
      } else if (temperature is num) {
        _temperature = temperature.toDouble();
      }
      
      // 🚀 初始化Top-P参数
      final topP = config.parameters['topP'];
      if (topP is double) {
        _topP = topP;
      } else if (topP is num) {
        _topP = topP.toDouble();
      }
      
      // 🚀 初始化提示词模板ID
      final promptTemplateId = config.parameters['promptTemplateId'];
      if (promptTemplateId is String && promptTemplateId.isNotEmpty) {
        _selectedPromptTemplateId = promptTemplateId;
      }
      
      // 🚀 优先使用传入的上下文数据，然后应用配置中的选择
      if (widget.initialContextSelections != null) {
        _contextSelectionData = widget.initialContextSelections!;
        AppLogger.i('ChatSettingsDialog', '使用传入的上下文选择数据');
      } else {
        _contextSelectionData = _createDefaultContextSelectionData();
        AppLogger.i('ChatSettingsDialog', '创建默认上下文选择数据');
      }
      
      if (config.contextSelections != null && config.contextSelections!.selectedCount > 0) {
        // 将现有选择应用到完整菜单结构上
        _contextSelectionData = _contextSelectionData.applyPresetSelections(config.contextSelections!);
        AppLogger.i('ChatSettingsDialog', '从初始配置应用了 ${config.contextSelections!.selectedCount} 个上下文选择');
      }
    } else {
      // 🚀 没有传入配置时，优先使用传入的上下文数据并初始化默认参数
      if (widget.initialContextSelections != null) {
        _contextSelectionData = widget.initialContextSelections!;
        AppLogger.i('ChatSettingsDialog', '使用传入的上下文选择数据');
      } else {
        _contextSelectionData = _createDefaultContextSelectionData();
        AppLogger.i('ChatSettingsDialog', '创建默认上下文选择数据');
      }
      
      // 🚀 初始化默认参数值
      _selectedPromptTemplateId = null;
      _temperature = 0.7;
      _topP = 0.9;
    }
    
    // 添加临时调试
    if (widget.novel != null) {
      //print('Novel has ${widget.novel!.acts.length} acts');
      //print('Settings: ${widget.settings.length}');
      //print('Setting Groups: ${widget.settingGroups.length}');
      //print('Snippets: ${widget.snippets.length}');
      for (var act in widget.novel!.acts) {
        //print('Act: ${act.title} has ${act.chapters.length} chapters');
      }
    } else {
      //print('Novel is null');
    }
  }
  

  /// 🚀 创建默认的上下文选择数据
  ContextSelectionData _createDefaultContextSelectionData() {
    if (widget.novel != null) {
      // 使用包含设定和片段的构建方法
      return ContextSelectionDataBuilder.fromNovelWithContext(
        widget.novel!,
        settings: widget.settings,
        settingGroups: widget.settingGroups,
        snippets: widget.snippets,
      );
    } else {
      // 创建一个空的上下文选择数据作为fallback
      final demoItems = _createDemoContextItems();
      final flatItems = <String, ContextSelectionItem>{};
      _buildFlatItems(demoItems, flatItems);
      
      return ContextSelectionData(
        novelId: 'demo_novel',
        availableItems: demoItems,
        flatItems: flatItems,
      );
    }
  }

  /// 创建演示用的上下文项目
  List<ContextSelectionItem> _createDemoContextItems() {
    return [
      ContextSelectionItem(
        id: 'demo_full_novel',
        title: 'Full Novel Text',
        type: ContextSelectionType.fullNovelText,
        subtitle: '包含所有小说文本，这将产生费用',
        metadata: {'wordCount': 1490},
      ),
      ContextSelectionItem(
        id: 'demo_full_outline',
        title: 'Full Outline',
        type: ContextSelectionType.fullOutline,
        subtitle: '包含所有卷、章节和场景的完整大纲',
        metadata: {'actCount': 1, 'chapterCount': 4, 'sceneCount': 6},
      ),
      ContextSelectionItem(
        id: 'demo_acts',
        title: 'Acts',
        type: ContextSelectionType.acts,
        children: [
          ContextSelectionItem(
            id: 'demo_act_1',
            title: 'Act 1',
            type: ContextSelectionType.acts,
            parentId: 'demo_acts',
            metadata: {'chapterCount': 4},
            children: [
              ContextSelectionItem(
                id: 'demo_chapter_1',
                title: 'Chapter 1',
                type: ContextSelectionType.chapters,
                parentId: 'demo_act_1',
                metadata: {'sceneCount': 2, 'wordCount': 500},
              ),
              ContextSelectionItem(
                id: 'demo_chapter_4',
                title: 'Chapter 4',
                type: ContextSelectionType.chapters,
                parentId: 'demo_act_1',
                metadata: {'sceneCount': 1, 'wordCount': 300},
                children: [
                  ContextSelectionItem(
                    id: 'demo_scene_1',
                    title: 'Scene 1',
                    type: ContextSelectionType.scenes,
                    parentId: 'demo_chapter_4',
                    metadata: {'wordCount': 300},
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ];
  }

  /// 递归构建扁平化映射
  void _buildFlatItems(List<ContextSelectionItem> items, Map<String, ContextSelectionItem> flatItems) {
    for (final item in items) {
      flatItems[item.id] = item;
      if (item.children.isNotEmpty) {
        _buildFlatItems(item.children, flatItems);
      }
    }
  }

  /// 显示模型选择器下拉菜单
  void _showModelSelectorDropdown() {
    // 确保公共模型已加载（即使没有私人模型也应可选择公共模型）
    try {
      final publicBloc = context.read<PublicModelsBloc>();
      final publicState = publicBloc.state;
      if (publicState is PublicModelsInitial || publicState is PublicModelsError) {
        publicBloc.add(const LoadPublicModels());
      }
    } catch (_) {}
    
    // 获取模型按钮的位置
    final RenderBox? renderBox = _modelSelectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final buttonRect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    
    // 🚀 安全移除已有的overlay
    if (_tempOverlay != null && _tempOverlay!.mounted) {
      _tempOverlay!.remove();
    }
    _tempOverlay = null;
    
    // 使用UnifiedAIModelDropdown.show弹出菜单
    _tempOverlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: buttonRect,
      selectedModel: _selectedUnifiedModel,
      onModelSelected: (unifiedModel) {
        setState(() {
          _selectedUnifiedModel = unifiedModel;
          // 🚀 同时更新兼容性字段
          if (unifiedModel != null) {
            if (unifiedModel.isPublic) {
              // 对于公共模型，清空私有模型配置
              _selectedModel = null;
            } else {
              // 对于私有模型，保持向后兼容
              _selectedModel = (unifiedModel as PrivateAIModel).userConfig;
            }
          } else {
            _selectedModel = null;
          }
        });
      },
      showSettingsButton: true,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      onClose: () {
        _tempOverlay = null;
      },
    );
    // 由 UnifiedAIModelDropdown.show 内部负责插入 OverlayEntry
  }

  OverlayEntry? _tempOverlay;

  @override
  void dispose() {
    _instructionsController.dispose();
    _memoryCutoffController.dispose();
    // 🚀 安全清理临时overlay
    if (_tempOverlay != null && _tempOverlay!.mounted) {
      _tempOverlay!.remove();
    }
    _tempOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 尝试获取 UniversalAIRepository，如果不存在则创建默认实例
    late UniversalAIRepository repository;
    try {
      repository = RepositoryProvider.of<UniversalAIRepository>(context);
    } catch (e) {
      // 如果没有找到 Provider，创建一个新的实例
      //debug//print('Warning: UniversalAIRepository not found in context, creating fallback instance');
      repository = UniversalAIRepositoryImpl(
        apiClient: RepositoryProvider.of<ApiClient>(context),
      );
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => UniversalAIBloc(
            repository: repository,
          ),
        ),
        // 🚀 为FormDialogTemplate提供必要的Bloc
        BlocProvider.value(value: context.read<PromptNewBloc>()),
      ],
      child: FormDialogTemplate(
        title: 'Chat Settings',
        tabs: const [
          TabItem(
            id: 'tweak',
            label: 'Tweak',
            icon: Icons.edit,
          ),
          TabItem(
            id: 'preview',
            label: 'Preview',
            icon: Icons.preview,
          ),
          TabItem(
            id: 'edit',
            label: 'Edit',
            icon: Icons.settings,
          ),
        ],
        tabContents: [
          _buildTweakTab(),
          _buildPreviewTab(),
          _buildEditTab(),
        ],
        onTabChanged: _onTabChanged,
        showPresets: true,
        usePresetDropdown: true,
        presetFeatureType: 'AI_CHAT',
        currentPreset: _currentPreset,
        onPresetSelected: _handlePresetSelected,
        onCreatePreset: _showCreatePresetDialog,
        onManagePresets: _showManagePresetsPage,
        novelId: widget.novel?.id,
        showModelSelector: true, // 保留顶部模型选择器按钮
        modelSelectorData: _selectedUnifiedModel != null
            ? ModelSelectorData(
                modelName: _selectedUnifiedModel!.displayName,
                maxOutput: '~12000 words',
                isModerated: true,
              )
            : const ModelSelectorData(
                modelName: '选择模型',
              ),
        onModelSelectorTap: _showModelSelectorDropdown, // 顶部按钮触发下拉菜单
        modelSelectorKey: _modelSelectorKey,
        primaryActionLabel: 'Save',
        onPrimaryAction: _handleSave,
        onClose: _handleClose,
        // 传递 aiConfigBloc 到模板中
        aiConfigBloc: widget.aiConfigBloc,
      ),
    );
  }

  /// 构建调整选项卡
  Widget _buildTweakTab() {
    return Column(
      children: [
        
        // 指令字段
        FormFieldFactory.createInstructionsField(
          controller: _instructionsController,
          title: 'Instructions',
          description: 'Any (optional) additional instructions and roles for the AI',
          placeholder: 'e.g. You are a...',
          onReset: _handleResetInstructions,
          onExpand: _handleExpandInstructions,
          onCopy: _handleCopyInstructions,
        ),

        //const SizedBox(height: 32),

        // 附加上下文字段 - 使用新的上下文选择组件
        FormFieldFactory.createContextSelectionField(
          contextData: _contextSelectionData,
          onSelectionChanged: _handleContextSelectionChanged,
          title: 'Additional Context',
          description: 'Any additional information to provide to the AI',
          onReset: _handleResetContexts,
          dropdownWidth: 400,
          initialChapterId: null,
          initialSceneId: null,
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：智能上下文勾选组件
        SmartContextToggle(
          value: _enableSmartContext,
          onChanged: _handleSmartContextChanged,
          title: 'Smart Context',
          description: 'Use AI to automatically retrieve relevant background information',
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：关联提示词模板选择字段
        FormFieldFactory.createPromptTemplateSelectionField(
          selectedTemplateId: _selectedPromptTemplateId,
          onTemplateSelected: _handlePromptTemplateSelected,
          aiFeatureType: 'AI_CHAT', // 🚀 使用标准API字符串格式
          title: '关联提示词模板',
          description: '选择要关联的提示词模板（可选）',
          onReset: _handleResetPromptTemplate,
          onTemporaryPromptsSaved: (sys, user) {
            setState(() {
              _customSystemPrompt = sys.trim().isEmpty ? null : sys.trim();
              _customUserPrompt = user.trim().isEmpty ? null : user.trim();
            });
          },
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：温度滑动组件
        FormFieldFactory.createTemperatureSliderField(
          context: context,
          value: _temperature,
          onChanged: _handleTemperatureChanged,
          onReset: _handleResetTemperature,
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：Top-P滑动组件
        FormFieldFactory.createTopPSliderField(
          context: context,
          value: _topP,
          onChanged: _handleTopPChanged,
          onReset: _handleResetTopP,
        ),

        //const SizedBox(height: 32),

        // 记忆截断字段
        FormFieldFactory.createMemoryCutoffField(
          options: const [
            RadioOption(value: 14, label: '14 (Default)'),
            RadioOption(value: 28, label: '28'),
            RadioOption(value: 48, label: '48'),
            RadioOption(value: 64, label: '64'),
          ],
          value: _selectedMemoryCutoff,
          onChanged: _handleMemoryCutoffChanged,
          title: 'Memory Cutoff',
          description: 'Specify a maximum number of message pairs to be sent to the AI. Any messages exceeding this limit will be ignored.',
          customInput: TextField(
            controller: _memoryCutoffController,
            decoration: InputDecoration(
              hintText: 'e.g. 24',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark 
                    ? WebTheme.darkGrey300 
                    : WebTheme.grey300,
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark 
                    ? WebTheme.darkGrey300 
                    : WebTheme.grey300,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              fillColor: Theme.of(context).brightness == Brightness.dark 
                ? WebTheme.darkGrey100 
                : WebTheme.white,
              filled: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final intValue = int.tryParse(value);
              if (intValue != null) {
                setState(() {
                  _selectedMemoryCutoff = null; // 清除单选按钮选择
                });
              }
            },
          ),
          onReset: _handleResetMemoryCutoff,
        ),
      ],
    );
  }

  /// 构建预览选项卡
  Widget _buildPreviewTab() {
    return BlocBuilder<UniversalAIBloc, UniversalAIState>(
      builder: (context, state) {
        if (state is UniversalAILoading) {
          return const PromptPreviewLoadingWidget();
        } else if (state is UniversalAIPreviewSuccess) {
          return PromptPreviewWidget(
            previewResponse: state.previewResponse,
          );
        } else if (state is UniversalAIError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  '预览生成失败',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _triggerPreview,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        } else {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.preview,
                  size: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                SizedBox(height: 16),
                Text(
                  '切换到预览选项卡查看提示词预览',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  /// 构建编辑选项卡
  Widget _buildEditTab() {
    return const Center(
      child: Text(
        'Edit options will be displayed here',
        style: TextStyle(fontSize: 16),
      ),
    );
  }

  // 事件处理器
  
  /// 处理选项卡切换
  void _onTabChanged(String tabId) {
    if (tabId == 'preview') {
      _triggerPreview();
    }
  }

  /// 触发预览生成
  void _triggerPreview() {
    // 验证必填字段，如果缺少必要信息，仍然可以生成预览但会显示提示
    UserAIModelConfigModel modelConfig;
    if (_selectedModel == null) {
      // 创建占位符模型配置
      modelConfig = UserAIModelConfigModel.fromJson({
        'id': 'placeholder',
        'userId': AppConfig.userId ?? 'unknown',
        'name': '请选择模型',
        'alias': '请选择模型',
        'modelName': '请选择模型',
        'provider': 'unknown',
        'apiEndpoint': '',
        'isDefault': false,
        'isValidated': false,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } else {
      modelConfig = _selectedModel!;
    }

    // 构建预览请求
    final request = UniversalAIRequest(
      requestType: AIRequestType.chat,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: '', // 聊天设置通常不需要选中文本
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'memoryCutoff': _selectedMemoryCutoff ?? int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
        'temperature': _temperature, // 🚀 使用用户设置的温度值
        'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
        'maxTokens': 4000,
        'enableSmartContext': _enableSmartContext,
        'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: {
        'action': 'chat_settings',
        'source': 'preview',
        'contextCount': _contextSelectionData.selectedCount,
        'memoryCutoff': _selectedMemoryCutoff ?? int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
        'enableSmartContext': _enableSmartContext,
      },
    );

    // 发送预览请求
    context.read<UniversalAIBloc>().add(
      PreviewAIRequestEvent(request),
    );
  }

  /// 构建当前请求对象（用于保存预设）
  UniversalAIRequest? _buildCurrentRequest() {
    if (_selectedUnifiedModel == null) return null;

    // 🚀 使用公共逻辑创建模型配置
    final modelConfig = createModelConfig(_selectedUnifiedModel!);

    // 🚀 使用公共逻辑创建元数据
    final metadata = createModelMetadata(_selectedUnifiedModel!, {
      'action': 'chat',
      'source': 'chat_settings_dialog',
      'contextCount': _contextSelectionData.selectedCount,
      'memoryCutoff': _selectedMemoryCutoff ?? 
          int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
      'enableSmartContext': _enableSmartContext,
    });

    return UniversalAIRequest(
      requestType: AIRequestType.chat,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'memoryCutoff': _selectedMemoryCutoff ?? 
            int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
        'temperature': _temperature, // 🚀 使用用户设置的温度值
        'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
        'maxTokens': 4000,
        'modelName': _selectedUnifiedModel!.modelId,
        'enableSmartContext': _enableSmartContext,
        'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: metadata,
    );
  }

  /// 显示创建预设对话框
  void _showCreatePresetDialog() {
    final currentRequest = _buildCurrentRequest();
    if (currentRequest == null) {
      TopToast.warning(context, '无法创建预设：缺少表单数据');
      return;
    }
    showPresetNameDialog(currentRequest, onPresetCreated: _handlePresetCreated);
  }

  // 移除重复的预设相关方法，使用 AIDialogCommonLogic 中的公共方法

  /// 显示预设管理页面
  void _showManagePresetsPage() {
    // TODO: 实现预设管理页面
    TopToast.info(context, '预设管理功能开发中...');
  }

  /// 处理预设选择
  void _handlePresetSelected(AIPromptPreset preset) {
    try {
      // 设置当前预设
      setState(() {
        _currentPreset = preset;
      });
      
      // 🚀 使用公共方法应用预设配置
      applyPresetToForm(
        preset,
        instructionsController: _instructionsController,
        onSmartContextChanged: (value) {
          setState(() {
            _enableSmartContext = value;
          });
        },
        onPromptTemplateChanged: (templateId) {
          setState(() {
            _selectedPromptTemplateId = templateId;
          });
        },
        onTemperatureChanged: (temperature) {
          setState(() {
            _temperature = temperature;
          });
        },
        onTopPChanged: (topP) {
          setState(() {
            _topP = topP;
          });
        },
        onContextSelectionChanged: (contextData) {
          setState(() {
            _contextSelectionData = contextData;
          });
        },
        onModelChanged: (unifiedModel) {
          setState(() {
            _selectedUnifiedModel = unifiedModel;
            // 🚀 同时更新兼容性字段
            if (unifiedModel != null) {
              if (unifiedModel.isPublic) {
                // 对于公共模型，清空私有模型配置
                _selectedModel = null;
              } else {
                // 对于私有模型，保持向后兼容
                _selectedModel = (unifiedModel as PrivateAIModel).userConfig;
              }
            } else {
              _selectedModel = null;
            }
          });
        },
        currentContextData: _contextSelectionData,
      );
      
      // 🚀 特殊处理记忆截断参数
      final parsedRequest = preset.parsedRequest;
      if (parsedRequest?.parameters != null) {
        final memoryCutoff = parsedRequest!.parameters['memoryCutoff'] as int?;
        if (memoryCutoff != null) {
          setState(() {
            if ([14, 28, 48, 64].contains(memoryCutoff)) {
              _selectedMemoryCutoff = memoryCutoff;
              _memoryCutoffController.clear();
            } else {
              _selectedMemoryCutoff = null;
              _memoryCutoffController.text = memoryCutoff.toString();
            }
          });
        }
      }
    } catch (e) {
      AppLogger.e('ChatSettingsDialog', '应用预设失败', e);
      TopToast.error(context, '应用预设失败: $e');
    }
  }

  /// 处理预设创建
  void _handlePresetCreated(AIPromptPreset preset) {
    // 设置当前预设为新创建的预设
    setState(() {
      _currentPreset = preset;
    });
    
    TopToast.success(context, '预设 "${preset.presetName}" 创建成功');
    AppLogger.i('ChatSettingsDialog', '预设创建成功: ${preset.presetName}');
  }


  void _handleSave() async {
    //print('🔧 [ChatSettingsDialog] 保存聊天设置');
    //print('🔧 [ChatSettingsDialog] 选中的上下文: ${_contextSelectionData.selectedCount}');
    
    // 🚀 检查必填字段
    if (_selectedUnifiedModel == null) {
      TopToast.error(context, '请选择AI模型');
      return;
    }
    
    for (final item in _contextSelectionData.selectedItems.values) {
      //print('🔧 [ChatSettingsDialog] - ${item.title} (${item.type.displayName})');
    }
    
    // 🚀 构建新的聊天配置
    if (widget.onConfigChanged != null) {
      // 基于现有配置或创建新配置
      final baseConfig = widget.initialChatConfig ?? UniversalAIRequest(
        requestType: AIRequestType.chat,
        userId: AppConfig.userId ?? 'unknown',
        novelId: widget.novel?.id,
      );
      
      //print('🔧 [ChatSettingsDialog] 基础配置已有上下文: ${baseConfig.contextSelections?.selectedCount ?? 0}');
      
      // 🚀 创建模型配置
      final modelConfig = createModelConfig(_selectedUnifiedModel!);
      
      // 创建更新后的配置
      final updatedConfig = baseConfig.copyWith(
        modelConfig: modelConfig,
        instructions: _instructionsController.text.trim().isEmpty 
            ? null 
            : _instructionsController.text.trim(),
        contextSelections: _contextSelectionData,
        enableSmartContext: _enableSmartContext,
        parameters: {
          ...baseConfig.parameters,
          'memoryCutoff': _selectedMemoryCutoff ?? 
              int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
          'temperature': _temperature, // 🚀 使用用户设置的温度值
          'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
          'maxTokens': 4000,
          'enableSmartContext': _enableSmartContext,
          'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
          if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
          if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
        },
        metadata: createModelMetadata(_selectedUnifiedModel!, {
          ...baseConfig.metadata,
          'action': 'chat_settings',
          'source': 'settings_dialog',
          'contextCount': _contextSelectionData.selectedCount,
          'memoryCutoff': _selectedMemoryCutoff ?? 
              int.tryParse(_memoryCutoffController.text.trim()) ?? 14,
          'enableSmartContext': _enableSmartContext,
          'lastUpdated': DateTime.now().toIso8601String(),
        }),
      );
      
      // 🚀 如果是公共模型，显示积分预估确认对话框
      if (_selectedUnifiedModel!.isPublic) {
        //print('🔧 [ChatSettingsDialog] 公共模型，显示积分预估确认');
        final confirmed = await showCreditEstimationAndConfirm(updatedConfig);
        
        if (!confirmed) {
          //print('🔧 [ChatSettingsDialog] 用户取消了积分确认');
          return;
        }
        
        //print('🔧 [ChatSettingsDialog] 用户确认积分消耗');
      }
      
      //print('🔧 [ChatSettingsDialog] 调用配置变更回调');
      //print('🔧 [ChatSettingsDialog] 更新后配置上下文: ${updatedConfig.contextSelections?.selectedCount ?? 0}');
      
      // 调用配置变更回调
      widget.onConfigChanged!(updatedConfig);
      
      //print('🔧 [ChatSettingsDialog] 聊天配置已更新:');
      //print('🔧 [ChatSettingsDialog] - 指令: ${updatedConfig.instructions?.isNotEmpty == true ? "有" : "无"}');
      //print('🔧 [ChatSettingsDialog] - 上下文选择: ${updatedConfig.contextSelections?.selectedCount ?? 0}');
      //print('🔧 [ChatSettingsDialog] - 智能上下文: ${updatedConfig.enableSmartContext}');
      //print('🔧 [ChatSettingsDialog] - 记忆截断: ${updatedConfig.parameters['memoryCutoff']}');
    } else {
      //print('🚨 [ChatSettingsDialog] 警告：没有配置变更回调！');
    }
    
    widget.onSettingsSaved?.call();
    Navigator.of(context).pop();
  }

  void _handleClose() {
    Navigator.of(context).pop();
  }

  void _handleResetInstructions() {
    setState(() {
      _instructionsController.clear();
    });
  }

  void _handleExpandInstructions() {
    //debug//print('Expand instructions editor');
  }

  void _handleCopyInstructions() {
    //debug//print('Copy instructions content');
  }

  void _handleContextSelectionChanged(ContextSelectionData newData) {
    setState(() {
      _contextSelectionData = newData;
    });
    //debug//print('Context selection changed: ${newData.selectedCount} items selected');
  }

  void _handleResetContexts() {
    setState(() {
      if (widget.novel != null) {
        _contextSelectionData = ContextSelectionDataBuilder.fromNovelWithContext(
          widget.novel!,
          settings: widget.settings,
          settingGroups: widget.settingGroups,
          snippets: widget.snippets,
        );
      } else {
        final demoItems = _createDemoContextItems();
        final flatItems = <String, ContextSelectionItem>{};
        _buildFlatItems(demoItems, flatItems);
        
        _contextSelectionData = ContextSelectionData(
          novelId: 'demo_novel',
          availableItems: demoItems,
          flatItems: flatItems,
        );
      }
    });
    //debug//print('Context selection reset');
  }

  void _handleMemoryCutoffChanged(int? value) {
    setState(() {
      _selectedMemoryCutoff = value;
      if (value != null) {
        _memoryCutoffController.clear(); // 清除文本输入
      }
    });
  }

  void _handleResetMemoryCutoff() {
    setState(() {
      _selectedMemoryCutoff = 14; // 重置为默认值
      _memoryCutoffController.clear();
    });
  }

  void _handleSmartContextChanged(bool value) {
    setState(() {
      _enableSmartContext = value;
    });
  }

  /// 🚀 新增：处理提示词模板选择
  void _handlePromptTemplateSelected(String? templateId) {
    setState(() {
      _selectedPromptTemplateId = templateId;
    });
    //debug//print('选中的提示词模板ID: $templateId');
  }

  /// 🚀 新增：重置提示词模板选择
  void _handleResetPromptTemplate() {
    setState(() {
      _selectedPromptTemplateId = null;
    });
    //debug//print('重置提示词模板选择');
  }

  /// 🚀 新增：处理温度参数变化
  void _handleTemperatureChanged(double value) {
    setState(() {
      _temperature = value;
    });
    //debug//print('温度参数已更改: $value');
  }

  /// 🚀 新增：重置温度参数
  void _handleResetTemperature() {
    setState(() {
      _temperature = 0.7;
    });
    //debug//print('温度参数已重置为默认值: 0.7');
  }

  /// 🚀 新增：处理Top-P参数变化
  void _handleTopPChanged(double value) {
    setState(() {
      _topP = value;
    });
    //debug//print('Top-P参数已更改: $value');
  }

  /// 🚀 新增：重置Top-P参数
  void _handleResetTopP() {
    setState(() {
      _topP = 0.9;
    });
    //debug//print('Top-P参数已重置为默认值: 0.9');
  }
}

/// 显示聊天设置对话框的便捷函数
void showChatSettingsDialog(
  BuildContext context, {
  UserAIModelConfigModel? selectedModel,
  ValueChanged<UserAIModelConfigModel?>? onModelChanged,
  VoidCallback? onSettingsSaved,
  Novel? novel,
  List<NovelSettingItem> settings = const [],
  List<SettingGroup> settingGroups = const [],
  List<NovelSnippet> snippets = const [],
  UniversalAIRequest? initialChatConfig, // 🚀 新增：初始聊天配置
  ValueChanged<UniversalAIRequest>? onConfigChanged, // 🚀 新增：配置变更回调
  ContextSelectionData? initialContextSelections, // 🚀 新增：初始上下文选择数据
}) {
      showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        // 🚀 修复：为对话框提供必要的Bloc，避免在内部widget中读取失败
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<AiConfigBloc>()),
            BlocProvider.value(value: context.read<PromptNewBloc>()),
          ],
          child: ChatSettingsDialog(
        // 从当前上下文中获取AiConfigBloc
        aiConfigBloc: context.read<AiConfigBloc>(),
        selectedModel: selectedModel,
        onModelChanged: onModelChanged,
        onSettingsSaved: onSettingsSaved,
        novel: novel,
        settings: settings,
        settingGroups: settingGroups,
        snippets: snippets,
        initialChatConfig: initialChatConfig, // 🚀 传递初始配置
        onConfigChanged: onConfigChanged, // 🚀 传递配置变更回调
        initialContextSelections: initialContextSelections, // 🚀 传递初始上下文选择数据
          ),
        );
      },
    );
} 