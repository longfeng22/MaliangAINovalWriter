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
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/widgets/common/index.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/multi_select_instructions_with_presets.dart' as multi_select;
// import 'package:ainoval/widgets/common/model_selector.dart' as ModelSelectorWidget; // unused
import 'package:ainoval/models/preset_models.dart';
// import 'package:ainoval/services/ai_preset_service.dart'; // unused
// import 'package:ainoval/screens/editor/widgets/dropdown_manager.dart'; // unused
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/context_selection_helper.dart';
import 'package:ainoval/config/app_config.dart';
// import 'package:ainoval/config/provider_icons.dart'; // unused
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
// duplicate imports removed
// import 'package:ainoval/blocs/public_models/public_models_bloc.dart'; // unused
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart'; // 🚀 新增：导入PromptNewBloc
import 'package:ainoval/models/unified_ai_model.dart';
import 'ai_dialog_common_logic.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';

/// 扩写对话框
/// 用于扩展现有文本内容
class ExpansionDialog extends StatefulWidget {
  /// 构造函数
  const ExpansionDialog({
    super.key,
    this.aiConfigBloc,
    this.selectedModel,
    this.onModelChanged,
    this.onGenerate,
    this.onStreamingGenerate,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.selectedText,
    this.initialInstructions,
    this.initialLength,
    this.initialEnableSmartContext,
    this.initialContextSelections,
    this.initialSelectedUnifiedModel,
  });

  /// AI配置Bloc
  final AiConfigBloc? aiConfigBloc;

  /// 当前选中的模型（已废弃，使用initialSelectedUnifiedModel）
  @Deprecated('Use initialSelectedUnifiedModel instead')
  final UserAIModelConfigModel? selectedModel;

  /// 模型改变回调（已废弃）
  @Deprecated('No longer used')
  final ValueChanged<UserAIModelConfigModel?>? onModelChanged;

  /// 生成回调
  final VoidCallback? onGenerate;

  /// 流式生成回调
  final Function(UniversalAIRequest request, UnifiedAIModel model)? onStreamingGenerate;

  /// 小说数据（用于构建上下文选择）
  final Novel? novel;
  
  /// 设定数据
  final List<NovelSettingItem> settings;
  
  /// 设定组数据
  final List<SettingGroup> settingGroups;
  
  /// 片段数据
  final List<NovelSnippet> snippets;

  /// 选中的文本（用于扩写）
  final String? selectedText;

  /// 🚀 新增：初始化参数，用于返回表单时恢复设置
  final String? initialInstructions;
  final String? initialLength;
  final bool? initialEnableSmartContext;
  final ContextSelectionData? initialContextSelections;

  /// 🚀 新增：初始化统一模型参数
  final UnifiedAIModel? initialSelectedUnifiedModel;

  @override
  State<ExpansionDialog> createState() => _ExpansionDialogState();
}

class _ExpansionDialogState extends State<ExpansionDialog> with AIDialogCommonLogic {
  // 控制器
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  
  // 状态变量
  UnifiedAIModel? _selectedUnifiedModel; // 🚀 统一AI模型
  String? _selectedLength;
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
  
  // 上下文选择数据
  late ContextSelectionData _contextSelectionData;

  // 扩写指令预设
  final List<multi_select.InstructionPreset> _expansionPresets = [
    const multi_select.InstructionPreset(
      id: 'descriptive',
      title: '描述性扩写',
      content: '请为这段文本添加更详细的描述，包括环境、感官细节和人物心理描写。',
      description: '增加环境描述和感官细节',
    ),
    const multi_select.InstructionPreset(
      id: 'dialogue',
      title: '对话扩写',
      content: '请为这段文本添加更多的对话和人物互动，展现人物性格。',
      description: '增加对话和人物互动',
    ),
    const multi_select.InstructionPreset(
      id: 'action',
      title: '动作扩写',
      content: '请为这段文本添加更多的动作描写和情节发展。',
      description: '增加动作描写和情节',
    ),
  ];

  OverlayEntry? _tempOverlay; // 🚀 临时Overlay，用于ModelSelector下拉菜单

  @override
  void initState() {
    super.initState();
    // 🚀 初始化统一模型
    _selectedUnifiedModel = widget.initialSelectedUnifiedModel;
    // 向后兼容：如果没有提供初始化统一模型但有旧模型，则转换
    if (_selectedUnifiedModel == null && widget.selectedModel != null) {
      _selectedUnifiedModel = PrivateAIModel(widget.selectedModel!);
    }
    
    // 🚀 恢复之前的表单设置
    if (widget.initialInstructions != null) {
      _instructionsController.text = widget.initialInstructions!;
    }
    if (widget.initialLength != null) {
      _selectedLength = widget.initialLength;
    }
    if (widget.initialEnableSmartContext != null) {
      _enableSmartContext = widget.initialEnableSmartContext!;
    }
    
    // 🚀 初始化新的参数默认值
    _selectedPromptTemplateId = null;
    _temperature = 0.7;
    _topP = 0.9;
    
    // 🚀 使用公共助手类初始化上下文选择数据
    _contextSelectionData = ContextSelectionHelper.initializeContextData(
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      initialSelections: widget.initialContextSelections,
    );
    debugPrint('ExpansionDialog 使用助手类初始化上下文选择数据完成: ${_contextSelectionData.selectedCount}个已选项');

    // 🚀 初始化统一模型
    if (widget.initialSelectedUnifiedModel != null) {
      _selectedUnifiedModel = widget.initialSelectedUnifiedModel!;
    }
  }



  /// Tab切换监听器
  void _onTabChanged(String tabId) {
    if (tabId == 'preview') { // 预览Tab
      _triggerPreview();
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _lengthController.dispose();
    // 清理临时Overlay，避免内存泄漏
    _tempOverlay?.remove();
    _tempOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 现在Bloc已经在外层showExpansionDialog中提供了，直接构建FormDialogTemplate
    return FormDialogTemplate(
        title: '扩写文本',
        tabs: const [
          TabItem(
            id: 'tweak',
            label: '调整',
            icon: Icons.edit,
          ),
          TabItem(
            id: 'preview',
            label: '预览',
            icon: Icons.preview,
          ),
        ],
        tabContents: [
          _buildTweakTab(),
          _buildPreviewTab(),
        ],
        showPresets: true,
        usePresetDropdown: true,
        presetFeatureType: 'TEXT_EXPANSION',
        currentPreset: _currentPreset,
        onPresetSelected: _handlePresetSelected,
        onCreatePreset: _showCreatePresetDialog,
        onManagePresets: _showManagePresetsPage,
        novelId: widget.novel?.id,
        showModelSelector: true, // 保留底部模型选择器按钮
        modelSelectorData: _selectedUnifiedModel != null
            ? ModelSelectorData(
                modelName: _selectedUnifiedModel!.displayName,
                maxOutput: '~12000 words',
                isModerated: true,
              )
            : const ModelSelectorData(
                modelName: '选择模型',
              ),
        onModelSelectorTap: _showModelSelectorDropdown, // 底部按钮触发下拉菜单
        modelSelectorKey: _modelSelectorKey,
        primaryActionLabel: '生成',
        onPrimaryAction: _handleGenerate,
        onClose: _handleClose,
        onTabChanged: _onTabChanged,
        aiConfigBloc: widget.aiConfigBloc,
      );
    
  }

  /// 构建调整选项卡
  Widget _buildTweakTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        
        // 指令字段
        FormFieldFactory.createMultiSelectInstructionsWithPresetsField(
          controller: _instructionsController,
          presets: _expansionPresets,
          title: '指令',
          description: '应该如何扩写文本？',
          placeholder: 'e.g. 描述设定',
          dropdownPlaceholder: '选择指令预设',
          onReset: _handleResetInstructions,
          onExpand: _handleExpandInstructions,
          onCopy: _handleCopyInstructions,
          onSelectionChanged: _handlePresetSelectionChanged,
        ),

        const SizedBox(height: 16),

        // 长度字段
        FormFieldFactory.createLengthField<String>(
          options: const [
            RadioOption(value: 'double', label: '双倍'),
            RadioOption(value: 'triple', label: '三倍'),
          ],
          value: _selectedLength,
          onChanged: _handleLengthChanged,
          title: '长度',
          description: '扩写后的文本应该多长？',
          onReset: _handleResetLength,
          alternativeInput: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 40),
            child: TextField(
              controller: _lengthController,
              decoration: InputDecoration(
                hintText: 'e.g. 400 words',
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
                    color: WebTheme.getPrimaryColor(context),
                    width: 1,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                fillColor: Theme.of(context).brightness == Brightness.dark 
                  ? WebTheme.darkGrey100 
                  : WebTheme.white,
                filled: true,
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _selectedLength = null;
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 附加上下文字段
        FormFieldFactory.createContextSelectionField(
          contextData: _contextSelectionData,
          onSelectionChanged: _handleContextSelectionChanged,
          title: '附加上下文',
          description: '为AI提供的任何额外信息',
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
          title: '智能上下文',
          description: '使用AI自动检索相关背景信息，提升生成质量',
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：关联提示词模板选择字段
        FormFieldFactory.createPromptTemplateSelectionField(
          selectedTemplateId: _selectedPromptTemplateId,
          onTemplateSelected: _handlePromptTemplateSelected,
          aiFeatureType: 'TEXT_EXPANSION', // 🚀 使用标准API字符串格式
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
            showActions: true,
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
                  '预览失败',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  state.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
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
                  Icons.preview_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                const Text(
                  '点击预览选项卡查看提示词',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _triggerPreview,
                  child: const Text('生成预览'),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  /// 触发预览请求
  void _triggerPreview() {
    if (_selectedUnifiedModel == null) {
      TopToast.warning(context, '请先选择AI模型');
      return;
    }

    if (widget.selectedText == null || widget.selectedText!.trim().isEmpty) {
      TopToast.warning(context, '没有选中的文本内容');
      return;
    }

    // 获取模型配置，根据模型类型获取适当的配置
    late UserAIModelConfigModel modelConfig;
    if (_selectedUnifiedModel!.isPublic) {
      // 对于公共模型，创建临时的模型配置用于API调用
      final publicModel = (_selectedUnifiedModel as PublicAIModel).publicConfig;
      modelConfig = UserAIModelConfigModel.fromJson({
        'id': publicModel.id,
        'userId': AppConfig.userId ?? 'unknown',
        'name': publicModel.displayName,
        'alias': publicModel.displayName,
        'modelName': publicModel.modelId,
        'provider': publicModel.provider,
        'apiEndpoint': '', // 公共模型没有单独的apiEndpoint
        'isDefault': false,
        'isValidated': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        // 公共模型的额外信息
        'isPublic': true,
        'creditMultiplier': publicModel.creditRateMultiplier ?? 1.0,
      });
    } else {
      // 对于私有模型，直接使用用户配置
      modelConfig = (_selectedUnifiedModel as PrivateAIModel).userConfig;
    }

    // 构建预览请求
    final request = UniversalAIRequest(
      requestType: AIRequestType.expansion,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: widget.selectedText!,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'length': _selectedLength ?? _lengthController.text.trim(),
        'temperature': _temperature, // 🚀 使用用户设置的温度值
        'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
        'maxTokens': 4000,
        'modelName': _selectedUnifiedModel!.modelId,
        'enableSmartContext': _enableSmartContext,
        'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: {
        'action': 'expand',
        'source': 'preview',
        'contextCount': _contextSelectionData.selectedCount,
        'originalLength': widget.selectedText?.length ?? 0,
        'modelName': _selectedUnifiedModel!.modelId,
        'modelProvider': _selectedUnifiedModel!.provider,
        'modelConfigId': _selectedUnifiedModel!.id,
        'enableSmartContext': _enableSmartContext,
      },
    );

    // 发送预览请求
    context.read<UniversalAIBloc>().add(PreviewAIRequestEvent(request));
  }

  /// 构建当前请求对象（用于保存预设）
  UniversalAIRequest? _buildCurrentRequest() {
    if (_selectedUnifiedModel == null) return null;

    // 🚀 使用公共逻辑创建模型配置
    final modelConfig = createModelConfig(_selectedUnifiedModel!);

    // 🚀 使用公共逻辑创建元数据
    final metadata = createModelMetadata(_selectedUnifiedModel!, {
      'action': 'expand',
      'source': 'expansion_dialog',
      'contextCount': _contextSelectionData.selectedCount,
      'originalLength': widget.selectedText?.length ?? 0,
      'enableSmartContext': _enableSmartContext,
    });

    return UniversalAIRequest(
      requestType: AIRequestType.expansion,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: widget.selectedText,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'length': _selectedLength ?? _lengthController.text.trim(),
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

  // 移除重复的预设创建方法，使用 AIDialogCommonLogic 中的公共方法

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
        onLengthChanged: (length) {
          setState(() {
            if (length != null && ['double', 'triple'].contains(length)) {
              _selectedLength = length;
              _lengthController.clear();
            } else if (length != null) {
              _selectedLength = null;
              _lengthController.text = length;
            }
          });
        },
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
          });
        },
        currentContextData: _contextSelectionData,
      );
    } catch (e) {
      AppLogger.e('ExpansionDialog', '应用预设失败', e);
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
    AppLogger.i('ExpansionDialog', '预设创建成功: ${preset.presetName}');
  }

  // 模型选择器点击处理已移除，现在使用内嵌的ModelSelector组件

  /// 显示模型选择器覆盖层（已禁用，现在使用内嵌的ModelSelector组件）
  void _showModelSelectorOverlay() {
    // 方法已禁用，现在使用内嵌的ModelSelector组件
    return;
    /*
    if (_modelSelectorOverlay != null) {
      _removeModelSelectorOverlay();
      return;
    }

    final aiConfigBloc = widget.aiConfigBloc ?? context.read<AiConfigBloc>();
    final validatedConfigs = aiConfigBloc.state.validatedConfigs;

    if (validatedConfigs.isEmpty) {
      debugPrint('No validated configs available');
      return;
    }

    // 获取模型选择器的位置
    final RenderBox? renderBox = _modelSelectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      debugPrint('Model selector render box not found');
      return;
    }
    
    final Offset position = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    
    // 计算菜单内容高度
    final groupedModels = _groupModelsByProvider(validatedConfigs);
    const double groupHeaderHeight = 20.0;
    const double modelItemHeight = 24.0;
    const double verticalPadding = 8.0;
    
    double totalItems = 0;
    for (var group in groupedModels.values) {
      totalItems += group.length;
    }
    
    final double contentHeight = (groupedModels.length * groupHeaderHeight) +
        (totalItems * modelItemHeight) + 
        (verticalPadding * 2);
    
    const double menuWidth = 280.0;
    final double menuHeight = contentHeight.clamp(160.0, 1200.0);
    
    // 获取屏幕尺寸用于边界检查
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    
    // 计算弹出位置：紧贴模型选择器上方
    double leftOffset = position.dx + (size.width - menuWidth) / 2; // 相对于模型选择器居中
    double topOffset = position.dy - menuHeight - 8; // 在模型选择器上方，留8px间距
    
    // 边界检查 - 确保不超出屏幕左右边界
    if (leftOffset < 16) {
      leftOffset = 16; // 左边距
    } else if (leftOffset + menuWidth > screenWidth - 16) {
      leftOffset = screenWidth - menuWidth - 16; // 右边距
    }
    
    // 边界检查 - 确保不超出屏幕上边界
    if (topOffset < 16) {
      topOffset = position.dy + size.height + 8; // 如果上方空间不足，显示在下方
    }

    _modelSelectorOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 透明背景，点击时关闭菜单
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeModelSelectorOverlay,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // 模型列表内容
          Positioned(
            left: leftOffset,
            top: topOffset,
            width: menuWidth,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainer,
              shadowColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.1),
              child: Container(
                height: menuHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withOpacity(0.3),
                  ),
                ),
                child: _buildModelListContent(validatedConfigs),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_modelSelectorOverlay!);
    */
  }

  void _removeModelSelectorOverlay() {
    // 方法已禁用，现在使用内嵌的ModelSelector组件
    return;
    /*
    _modelSelectorOverlay?.remove();
    _modelSelectorOverlay = null;
    */
  }

  /// 按供应商分组模型
  Map<String, List<UserAIModelConfigModel>> _groupModelsByProvider(
      List<UserAIModelConfigModel> configs) {
    final Map<String, List<UserAIModelConfigModel>> grouped = {};
    
    for (final config in configs) {
      final provider = config.provider;
      grouped.putIfAbsent(provider, () => []);
      grouped[provider]!.add(config);
    }
    
    // 对每个供应商的模型按名称排序，默认模型排在前面
    for (final models in grouped.values) {
      models.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.name.compareTo(b.name);
      });
    }
    
    return grouped;
  }

  /// 显示模型选择器下拉菜单
  void _showModelSelectorDropdown() {
    // 确保公共模型加载，避免仅私人模型为空时无法点击
    try {
      final publicBloc = context.read<PublicModelsBloc>();
      final st = publicBloc.state;
      if (st is PublicModelsInitial || st is PublicModelsError) {
        publicBloc.add(const LoadPublicModels());
      }
    } catch (_) {}

    // 获取底部模型按钮的位置
    final renderBox = _modelSelectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final anchorRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

    _tempOverlay?.remove();

    _tempOverlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: anchorRect,
      selectedModel: _selectedUnifiedModel,
      onModelSelected: (unifiedModel) {
        setState(() {
          _selectedUnifiedModel = unifiedModel;
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
  }

  void _handleGenerate() async {
    // 检查必填字段
    if (_selectedUnifiedModel == null) {
      TopToast.error(context, '请选择AI模型');
      return;
    }

    if (widget.selectedText == null || widget.selectedText!.trim().isEmpty) {
      TopToast.error(context, '没有选中的文本内容');
      return;
    }

    debugPrint('选中的上下文: ${_contextSelectionData.selectedCount}');
    for (final item in _contextSelectionData.selectedItems.values) {
      debugPrint('- ${item.title} (${item.type.displayName})');
    }

    // 🚀 新增：对于公共模型，先进行积分预估和确认
    if (_selectedUnifiedModel!.isPublic) {
      debugPrint('🚀 检测到公共模型，启动积分预估确认流程: ${_selectedUnifiedModel!.displayName}');
      bool shouldProceed = await _showCreditEstimationAndConfirm();
      if (!shouldProceed) {
        debugPrint('🚀 用户取消了积分预估确认，停止生成');
        return; // 用户取消或积分不足，停止执行
      }
      debugPrint('🚀 用户确认了积分预估，继续生成');
    } else {
      debugPrint('🚀 检测到私有模型，直接生成: ${_selectedUnifiedModel!.displayName}');
    }

    // 启动流式生成，并关闭对话框
    _startStreamingGeneration();
    Navigator.of(context).pop();
  }

  /// 启动流式生成
  void _startStreamingGeneration() {
    try {
      // 🚀 修复：为公共模型和私有模型创建正确的模型配置
      late UserAIModelConfigModel modelConfig;
      
      if (_selectedUnifiedModel!.isPublic) {
        // 对于公共模型，创建包含公共模型信息的临时配置
        final publicModel = (_selectedUnifiedModel as PublicAIModel).publicConfig;
        debugPrint('🚀 启动公共模型流式生成 - 显示名: ${publicModel.displayName}, 模型ID: ${publicModel.modelId}, 公共模型ID: ${publicModel.id}');
        modelConfig = UserAIModelConfigModel.fromJson({
          'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
          'userId': AppConfig.userId ?? 'unknown',
          'alias': publicModel.displayName,
          'modelName': publicModel.modelId,
          'provider': publicModel.provider,
          'apiEndpoint': '', // 公共模型没有单独的apiEndpoint
          'isDefault': false,
          'isValidated': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } else {
        // 对于私有模型，直接使用用户配置
        final privateModel = (_selectedUnifiedModel as PrivateAIModel).userConfig;
        debugPrint('🚀 启动私有模型流式生成 - 显示名: ${privateModel.name}, 模型名: ${privateModel.modelName}, 配置ID: ${privateModel.id}');
        modelConfig = privateModel;
      }

      // 构建AI请求
      final request = UniversalAIRequest(
        requestType: AIRequestType.expansion,
        userId: AppConfig.userId ?? 'unknown',
        novelId: widget.novel?.id,
        modelConfig: modelConfig,
        selectedText: widget.selectedText!,
        instructions: _instructionsController.text.trim(),
        contextSelections: _contextSelectionData,
        enableSmartContext: _enableSmartContext,
        parameters: {
          'length': _selectedLength ?? _lengthController.text.trim(),
          'temperature': _temperature, // 🚀 使用用户设置的温度值
          'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
          'maxTokens': 4000,
          'modelName': _selectedUnifiedModel!.modelId,
          'enableSmartContext': _enableSmartContext,
          'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
          if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
          if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
        },
        metadata: {
          'action': 'expand',
          'source': 'selection_toolbar',
          'contextCount': _contextSelectionData.selectedCount,
          'originalLength': widget.selectedText?.length ?? 0,
          'modelName': _selectedUnifiedModel!.modelId,
          'modelProvider': _selectedUnifiedModel!.provider,
          'modelConfigId': _selectedUnifiedModel!.id,
          'enableSmartContext': _enableSmartContext,
          // 🚀 新增：明确标识模型类型和公共模型的真实ID
          'isPublicModel': _selectedUnifiedModel!.isPublic,
          if (_selectedUnifiedModel!.isPublic) 'publicModelConfigId': (_selectedUnifiedModel as PublicAIModel).publicConfig.id,
          if (_selectedUnifiedModel!.isPublic) 'publicModelId': (_selectedUnifiedModel as PublicAIModel).publicConfig.id,
        },
      );

      // 通过回调通知父组件开始流式生成
      widget.onGenerate?.call();
      
      // 如果有流式生成回调，调用它
      if (widget.onStreamingGenerate != null) {
        widget.onStreamingGenerate!(request, _selectedUnifiedModel!);
      }
      
      debugPrint('流式扩写生成已启动: 模型=${_selectedUnifiedModel!.displayName}, 智能上下文=$_enableSmartContext, 原文长度=${widget.selectedText?.length ?? 0}');
      
    } catch (e) {
      TopToast.error(context, '启动生成失败: $e');
      debugPrint('启动扩写生成失败: $e');
    }
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
    debugPrint('展开指令编辑器');
  }

  void _handleCopyInstructions() {
    debugPrint('复制指令内容');
  }

  void _handleLengthChanged(String? value) {
    setState(() {
      _selectedLength = value;
      if (value != null) {
        _lengthController.clear(); // 清除文本输入
      }
    });
  }

  void _handleResetLength() {
    setState(() {
      _selectedLength = null;
      _lengthController.clear();
    });
  }

  void _handleContextSelectionChanged(ContextSelectionData newData) {
    setState(() {
      _contextSelectionData = newData;
    });
    debugPrint('上下文选择改变: ${newData.selectedCount} 个项目被选中');
  }

  void _handleResetContexts() {
    setState(() {
      // 🚀 使用公共助手类重置上下文选择
      _contextSelectionData = ContextSelectionHelper.initializeContextData(
        novel: widget.novel,
        settings: widget.settings,
        settingGroups: widget.settingGroups,
        snippets: widget.snippets,
      );
    });
    debugPrint('上下文选择重置');
  }

  void _handlePresetSelectionChanged(List<multi_select.InstructionPreset> selectedPresets) {
    debugPrint('选中的预设已改变: ${selectedPresets.map((p) => p.title).join(', ')}');
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
    debugPrint('选中的提示词模板ID: $templateId');
  }

  /// 🚀 新增：重置提示词模板选择
  void _handleResetPromptTemplate() {
    setState(() {
      _selectedPromptTemplateId = null;
    });
    debugPrint('重置提示词模板选择');
  }

  /// 🚀 新增：处理温度参数变化
  void _handleTemperatureChanged(double value) {
    setState(() {
      _temperature = value;
    });
    debugPrint('温度参数已更改: $value');
  }

  /// 🚀 新增：重置温度参数
  void _handleResetTemperature() {
    setState(() {
      _temperature = 0.7;
    });
    debugPrint('温度参数已重置为默认值: 0.7');
  }

  /// 🚀 新增：处理Top-P参数变化
  void _handleTopPChanged(double value) {
    setState(() {
      _topP = value;
    });
    debugPrint('Top-P参数已更改: $value');
  }

  /// 🚀 新增：重置Top-P参数
  void _handleResetTopP() {
    setState(() {
      _topP = 0.9;
    });
    debugPrint('Top-P参数已重置为默认值: 0.9');
  }

  /// 🚀 新增：显示积分预估和确认对话框
  Future<bool> _showCreditEstimationAndConfirm() async {
    try {
      // 构建预估请求
      final estimationRequest = _buildCurrentRequest();
      if (estimationRequest == null) {
        TopToast.error(context, '无法构建预估请求');
        return false;
      }

      // 显示积分预估确认对话框，传递UniversalAIBloc
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return BlocProvider.value(
            value: context.read<UniversalAIBloc>(),
            child: _CreditEstimationDialog(
              modelName: _selectedUnifiedModel!.displayName,
              request: estimationRequest,
              onConfirm: () => Navigator.of(dialogContext).pop(true),
              onCancel: () => Navigator.of(dialogContext).pop(false),
            ),
          );
        },
      ) ?? false;

    } catch (e) {
      AppLogger.e('ExpansionDialog', '积分预估失败', e);
      TopToast.error(context, '积分预估失败: $e');
      return false;
    }
  }
}

/// 🚀 新增：积分预估确认对话框
class _CreditEstimationDialog extends StatefulWidget {
  final String modelName;
  final UniversalAIRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _CreditEstimationDialog({
    super.key,
    required this.modelName,
    required this.request,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_CreditEstimationDialog> createState() => _CreditEstimationDialogState();
}

class _CreditEstimationDialogState extends State<_CreditEstimationDialog> {
  CostEstimationResponse? _costEstimation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _estimateCost();
  }

  Future<void> _estimateCost() async {
    try {
      // 🚀 调用真实的积分预估API
      final universalAIBloc = context.read<UniversalAIBloc>();
      universalAIBloc.add(EstimateCostEvent(widget.request));
    } catch (e) {
      setState(() {
        _errorMessage = '预估失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UniversalAIBloc, UniversalAIState>(
      listener: (context, state) {
        if (state is UniversalAICostEstimationSuccess) {
          setState(() {
            _costEstimation = state.costEstimation;
            _errorMessage = null;
          });
        } else if (state is UniversalAIError) {
          setState(() {
            _errorMessage = state.message;
            _costEstimation = null;
          });
        }
      },
      child: BlocBuilder<UniversalAIBloc, UniversalAIState>(
        builder: (context, state) {
          final isLoading = state is UniversalAILoading;
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 8),
                const Text('积分消耗预估'),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模型: ${widget.modelName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (isLoading) ...[
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('正在估算积分消耗...'),
                      ],
                    ),
                  ] else if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_costEstimation != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '预估消耗积分:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${_costEstimation!.estimatedCost}',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: WebTheme.getPrimaryColor(context),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (_costEstimation!.estimatedInputTokens != null || _costEstimation!.estimatedOutputTokens != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Token预估:',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                Text(
                                  '输入: ${_costEstimation!.estimatedInputTokens ?? 0}, 输出: ${_costEstimation!.estimatedOutputTokens ?? 0}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '实际消耗可能因内容长度和模型响应而有所不同',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  Text(
                    '确认要继续生成吗？',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : widget.onCancel,
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: isLoading || _errorMessage != null || _costEstimation == null ? null : widget.onConfirm,
                child: const Text('确认生成'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 显示扩写对话框的便捷函数
void showExpansionDialog(
  BuildContext context, {
  @Deprecated('Use initialSelectedUnifiedModel instead') UserAIModelConfigModel? selectedModel,
  @Deprecated('No longer used') ValueChanged<UserAIModelConfigModel?>? onModelChanged,
  VoidCallback? onGenerate,
  Function(UniversalAIRequest request, UnifiedAIModel model)? onStreamingGenerate,
  Novel? novel,
  List<NovelSettingItem> settings = const [],
  List<SettingGroup> settingGroups = const [],
  List<NovelSnippet> snippets = const [],
  String? selectedText,
  // 🚀 新增：初始化参数
  String? initialInstructions,
  String? initialLength,
  bool? initialEnableSmartContext,
  ContextSelectionData? initialContextSelections,
  // 🚀 新增：初始化统一模型参数
  UnifiedAIModel? initialSelectedUnifiedModel,
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
        child: ExpansionDialog(
          selectedModel: selectedModel,
          onModelChanged: onModelChanged,
          onGenerate: onGenerate,
          onStreamingGenerate: onStreamingGenerate,
          novel: novel,
          settings: settings,
          settingGroups: settingGroups,
          snippets: snippets,
          selectedText: selectedText,
          initialInstructions: initialInstructions,
          initialLength: initialLength,
          initialEnableSmartContext: initialEnableSmartContext,
          initialContextSelections: initialContextSelections,
          initialSelectedUnifiedModel: initialSelectedUnifiedModel,
        ),
      );
    },
  );
} 