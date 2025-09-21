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
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/widgets/common/index.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart'; // 🚀 新增：导入PromptNewBloc
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';

import 'package:ainoval/widgets/common/multi_select_instructions_with_presets.dart' as multi_select;
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/config/app_config.dart';
// ignore_for_file: unused_import
import 'package:ainoval/widgets/common/model_selector.dart' as ModelSelectorWidget;

/// 重构对话框
/// 用于重构现有文本内容
class RefactorDialog extends StatefulWidget {
  /// 构造函数
  const RefactorDialog({
    super.key,
    this.aiConfigBloc,
    this.selectedModel,
    this.onModelChanged,
    this.onGenerate,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.selectedText,
    this.onStreamingGenerate,
    this.initialInstructions,
    this.initialStyle,
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

  /// 小说数据（用于构建上下文选择）
  final Novel? novel;
  
  /// 设定数据
  final List<NovelSettingItem> settings;
  
  /// 设定组数据
  final List<SettingGroup> settingGroups;
  
  /// 片段数据
  final List<NovelSnippet> snippets;

  /// 选中的文本（用于重构）
  final String? selectedText;
  
  /// 🚀 新增：流式生成回调
  final Function(UniversalAIRequest, UnifiedAIModel)? onStreamingGenerate;

  /// 🚀 新增：初始化参数，用于返回表单时恢复设置
  final String? initialInstructions;
  final String? initialStyle;
  final bool? initialEnableSmartContext;
  final ContextSelectionData? initialContextSelections;
  
  /// 🚀 新增：初始化统一模型参数
  final UnifiedAIModel? initialSelectedUnifiedModel;

  @override
  State<RefactorDialog> createState() => _RefactorDialogState();
}

class _RefactorDialogState extends State<RefactorDialog> with AIDialogCommonLogic {
  // 控制器
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _styleController = TextEditingController();
  
  // 状态变量
  UnifiedAIModel? _selectedUnifiedModel; // 🚀 统一AI模型
  String? _selectedStyle;
  bool _enableSmartContext = true; // 🚀 新增：智能上下文开关，默认开启
  AIPromptPreset? _currentPreset; // 🚀 新增：当前选中的预设
  String? _selectedPromptTemplateId; // 🚀 新增：选中的提示词模板ID
  double _temperature = 0.7; // 🚀 新增：温度参数
  double _topP = 0.9; // 🚀 新增：Top-P参数
  // 🚀 新增：临时编辑的提示词（系统/用户）
  String? _customSystemPrompt;
  String? _customUserPrompt;
  
  // 模型选择器key（用于FormDialogTemplate）
  final GlobalKey _modelSelectorKey = GlobalKey();
  
  // 临时Overlay用于模型下拉菜单
  OverlayEntry? _tempOverlay;
  
  // 上下文选择数据
  late ContextSelectionData _contextSelectionData;

  // 重构指令预设
  final List<multi_select.InstructionPreset> _refactorPresets = [
    const multi_select.InstructionPreset(
      id: 'dramatic',
      title: '增强戏剧性',
      content: '让这段文字更具戏剧性和冲突感，增强情节张力。',
      description: '提升戏剧张力和冲突',
    ),
    const multi_select.InstructionPreset(
      id: 'style',
      title: '改变风格',
      content: '请将这段文字改写为更优雅/现代/古典的文学风格。',
      description: '调整文学风格和语调',
    ),
    const multi_select.InstructionPreset(
      id: 'pov',
      title: '转换视角',
      content: '请将这段文字从第一人称改写为第三人称（或相反）。',
      description: '改变叙述视角',
    ),
    const multi_select.InstructionPreset(
      id: 'mood',
      title: '调整情绪',
      content: '请调整这段文字的情绪氛围，使其更加轻松/严肃/神秘/温馨。',
      description: '改变情绪氛围',
    ),
  ];

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
    if (widget.initialStyle != null) {
      _selectedStyle = widget.initialStyle;
    }
    if (widget.initialEnableSmartContext != null) {
      _enableSmartContext = widget.initialEnableSmartContext!;
    }
    
    // 🚀 初始化新的参数默认值
    _selectedPromptTemplateId = null;
    _temperature = 0.7;
    _topP = 0.9;
    
    // 🚀 添加调试日志
    debugPrint('RefactorDialog 初始化上下文选择数据');
    debugPrint('RefactorDialog Novel: ${widget.novel?.title}');
    debugPrint('RefactorDialog Settings: ${widget.settings.length}');
    debugPrint('RefactorDialog Setting Groups: ${widget.settingGroups.length}');
    debugPrint('RefactorDialog Snippets: ${widget.snippets.length}');
    
    // 初始化上下文选择数据
    if (widget.initialContextSelections != null) {
      // 🚀 使用传入的上下文选择数据
      _contextSelectionData = widget.initialContextSelections!;
      debugPrint('RefactorDialog 使用传入的上下文选择数据');
    } else if (widget.novel != null) {
      // 🚀 修复：使用包含设定和片段的构建方法
      _contextSelectionData = ContextSelectionDataBuilder.fromNovelWithContext(
        widget.novel!,
        settings: widget.settings,
        settingGroups: widget.settingGroups,
        snippets: widget.snippets,
      );
      debugPrint('RefactorDialog 从Novel构建上下文选择数据成功');
    } else {
      // 🚀 修复：如果novel为null，创建包含其他数据的fallback
      final demoItems = _createDemoContextItems();
      final flatItems = <String, ContextSelectionItem>{};
      _buildFlatItems(demoItems, flatItems);
      
      _contextSelectionData = ContextSelectionData(
        novelId: 'demo_novel',
        availableItems: demoItems,
        flatItems: flatItems,
      );
      debugPrint('RefactorDialog 创建演示上下文选择数据');
    }

    // 🚀 初始化统一模型参数
    if (widget.initialSelectedUnifiedModel != null) {
      _selectedUnifiedModel = widget.initialSelectedUnifiedModel;
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
    
    // 移除已有的overlay
    _tempOverlay?.remove();
    
    // 使用UnifiedAIModelDropdown.show弹出菜单
    _tempOverlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: buttonRect,
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
    
    // 由 UnifiedAIModelDropdown.show 内部负责插入 OverlayEntry
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
    _styleController.dispose();
    _tempOverlay?.remove(); // 清理临时overlay
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 为FormDialogTemplate提供必要的Bloc，避免在内部widget中读取失败
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<AiConfigBloc>()),
        BlocProvider.value(value: context.read<PromptNewBloc>()),
      ],
      child: FormDialogTemplate(
        title: '重构文本',
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
        presetFeatureType: 'TEXT_REFACTOR',
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
      ),
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
          presets: _refactorPresets,
          title: '指令',
          description: '应该如何重构文本？',
          placeholder: 'e.g. 重写以提高清晰度',
          dropdownPlaceholder: '选择指令预设',
          onReset: _handleResetInstructions,
          onExpand: _handleExpandInstructions,
          onCopy: _handleCopyInstructions,
          onSelectionChanged: _handlePresetSelectionChanged,
        ),

        const SizedBox(height: 16),

        // 重构方式字段
        FormFieldFactory.createLengthField<String>(
          options: const [
            RadioOption(value: 'clarity', label: '清晰度'),
            RadioOption(value: 'flow', label: '流畅性'),
            RadioOption(value: 'tone', label: '语调'),
          ],
          value: _selectedStyle,
          onChanged: _handleStyleChanged,
          title: '重构方式',
          description: '重点关注哪个方面？',
          onReset: _handleResetStyle,
          alternativeInput: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 40),
            child: TextField(
              controller: _styleController,
              decoration: InputDecoration(
                hintText: 'e.g. 更加正式',
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
                  _selectedStyle = null;
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
          description: '使用AI自动检索相关背景信息，提升重构质量',
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：关联提示词模板选择字段
        FormFieldFactory.createPromptTemplateSelectionField(
          selectedTemplateId: _selectedPromptTemplateId,
          onTemplateSelected: _handlePromptTemplateSelected,
          aiFeatureType: 'TEXT_REFACTOR', // 🚀 使用标准API字符串格式
          title: '关联提示词模板',
          description: '选择要关联的提示词模板（可选）',
          onReset: _handleResetPromptTemplate,
          onTemporaryPromptsSaved: (sys, user) {
            setState(() {
              _customSystemPrompt = sys.trim().isEmpty ? null : sys.trim();
              _customUserPrompt = user.trim().isEmpty ? null : user.trim();
            });
            debugPrint('已临时保存自定义提示词: system=${_customSystemPrompt?.length ?? 0} chars, user=${_customUserPrompt?.length ?? 0} chars');
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
                const Icon(
                  Icons.preview_outlined,
                  size: 48,
                  color: Colors.grey,
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

    // 🚀 使用公共逻辑创建模型配置
    final modelConfig = createModelConfig(_selectedUnifiedModel!);

    // 🚀 使用公共逻辑创建元数据
    final metadata = createModelMetadata(_selectedUnifiedModel!, {
      'action': 'refactor',
      'source': 'preview',
      'contextCount': _contextSelectionData.selectedCount,
      'originalLength': widget.selectedText?.length ?? 0,
      'enableSmartContext': _enableSmartContext,
    });

    // 构建预览请求
    final request = UniversalAIRequest(
      requestType: AIRequestType.refactor,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: widget.selectedText!,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'style': _selectedStyle ?? _styleController.text.trim(),
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
      'action': 'refactor',
      'source': 'refactor_dialog',
      'contextCount': _contextSelectionData.selectedCount,
      'originalLength': widget.selectedText?.length ?? 0,
      'enableSmartContext': _enableSmartContext,
    });

    return UniversalAIRequest(
      requestType: AIRequestType.refactor,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: widget.selectedText,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'style': _selectedStyle ?? _styleController.text.trim(),
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

  // 事件处理器

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
        onStyleChanged: (style) {
          setState(() {
            if (style != null && ['clarity', 'flow', 'tone'].contains(style)) {
              _selectedStyle = style;
              _styleController.clear();
            } else if (style != null) {
              _selectedStyle = null;
              _styleController.text = style;
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
      AppLogger.e('RefactorDialog', '应用预设失败', e);
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
    AppLogger.i('RefactorDialog', '预设创建成功: ${preset.presetName}');
  }

  void _handleGenerate() async {
    // 检查必填字段
    if (_instructionsController.text.trim().isEmpty) {
      TopToast.error(context, '请输入重构指令');
      return;
    }

    if (_selectedUnifiedModel == null) {
      TopToast.error(context, '请选择AI模型');
      return;
    }

    if (widget.selectedText == null || widget.selectedText!.trim().isEmpty) {
      TopToast.error(context, '没有选中的文本内容');
      return;
    }

    debugPrint('指令: ${_instructionsController.text}');
    debugPrint('选中的上下文: ${_contextSelectionData.selectedCount}');
    for (final item in _contextSelectionData.selectedItems.values) {
      debugPrint('- ${item.title} (${item.type.displayName})');
    }

    // 🚀 新增：对于公共模型，先进行积分预估和确认
    final currentRequest = _buildCurrentRequest();
    if (currentRequest != null) {
      bool shouldProceed = await handlePublicModelCreditConfirmation(_selectedUnifiedModel!, currentRequest);
      if (!shouldProceed) {
        return; // 用户取消或积分不足，停止执行
      }
    }

    // 启动流式生成，并关闭对话框
    _startStreamingGeneration();
    Navigator.of(context).pop();
  }

  /// 启动流式生成
  void _startStreamingGeneration() {
    try {
      // 🚀 使用公共逻辑创建模型配置
      final modelConfig = createModelConfig(_selectedUnifiedModel!);

      // 🚀 使用公共逻辑创建元数据
      final metadata = createModelMetadata(_selectedUnifiedModel!, {
        'action': 'refactor',
        'source': 'selection_toolbar',
        'contextCount': _contextSelectionData.selectedCount,
        'originalLength': widget.selectedText?.length ?? 0,
        'enableSmartContext': _enableSmartContext,
      });

      // 构建AI请求
      final request = UniversalAIRequest(
        requestType: AIRequestType.refactor,
        userId: AppConfig.userId ?? 'unknown',
        novelId: widget.novel?.id,
        modelConfig: modelConfig,
        selectedText: widget.selectedText!,
        instructions: _instructionsController.text.trim(),
        contextSelections: _contextSelectionData,
        enableSmartContext: _enableSmartContext,
        parameters: {
          'style': _selectedStyle ?? _styleController.text.trim(),
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

      // 如果有流式生成回调，调用它
      if (widget.onStreamingGenerate != null) {
        // 使用统一模型
        widget.onStreamingGenerate!(request, _selectedUnifiedModel!);
      }
      
      // 通过回调通知父组件开始流式生成（用于日志记录）
      widget.onGenerate?.call();
      
      debugPrint('流式重构生成已启动: 模型=${_selectedUnifiedModel!.displayName}, 智能上下文=$_enableSmartContext, 原文长度=${widget.selectedText?.length ?? 0}');
      
    } catch (e) {
      TopToast.error(context, '启动生成失败: $e');
      debugPrint('启动重构生成失败: $e');
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

  void _handleContextSelectionChanged(ContextSelectionData newData) {
    setState(() {
      _contextSelectionData = newData;
    });
    debugPrint('上下文选择改变: ${newData.selectedCount} 个项目被选中');
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
    debugPrint('上下文选择重置');
  }

  void _handleStyleChanged(String? value) {
    setState(() {
      _selectedStyle = value;
    });
  }

  void _handleResetStyle() {
    setState(() {
      _selectedStyle = null;
    });
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
}

/// 显示重构对话框的便捷函数
void showRefactorDialog(
  BuildContext context, {
  @Deprecated('Use initialSelectedUnifiedModel instead') UserAIModelConfigModel? selectedModel,
  @Deprecated('No longer used') ValueChanged<UserAIModelConfigModel?>? onModelChanged,
  VoidCallback? onGenerate,
  Novel? novel,
  List<NovelSettingItem> settings = const [],
  List<SettingGroup> settingGroups = const [],
  List<NovelSnippet> snippets = const [],
  String? selectedText,
  Function(UniversalAIRequest, UnifiedAIModel)? onStreamingGenerate,
  // 🚀 新增：初始化参数
  String? initialInstructions,
  String? initialStyle,
  bool? initialEnableSmartContext,
  ContextSelectionData? initialContextSelections,
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
        child: RefactorDialog(
      aiConfigBloc: context.read<AiConfigBloc>(),
      selectedModel: selectedModel,
      onModelChanged: onModelChanged,
      onGenerate: onGenerate,
      novel: novel,
      settings: settings,
      settingGroups: settingGroups,
      snippets: snippets,
      selectedText: selectedText,
      onStreamingGenerate: onStreamingGenerate,
      initialInstructions: initialInstructions,
      initialStyle: initialStyle,
      initialEnableSmartContext: initialEnableSmartContext,
      initialContextSelections: initialContextSelections,
      initialSelectedUnifiedModel: initialSelectedUnifiedModel,
        ),
      );
    },
  );
} 