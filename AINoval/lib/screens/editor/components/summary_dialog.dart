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
import 'package:ainoval/widgets/common/top_toast.dart';
// import 'package:ainoval/widgets/common/model_selector.dart' as ModelSelectorWidget; // unused
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
// import 'package:ainoval/blocs/public_models/public_models_bloc.dart'; // unused
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart'; // 🚀 新增：导入PromptNewBloc
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/services/api_service/repositories/universal_ai_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/universal_ai_repository_impl.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/preset_models.dart';
// import 'package:ainoval/services/ai_preset_service.dart'; // unused
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/widgets/common/prompt_preview_widget.dart';
// import 'package:ainoval/config/provider_icons.dart'; // unused
import 'package:ainoval/utils/logger.dart';

/// 缩写对话框
/// 用于缩短现有文本内容
class SummaryDialog extends StatefulWidget {
  /// 构造函数
  const SummaryDialog({
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

  /// 小说数据（用于构建上下文选择）
  final Novel? novel;
  
  /// 设定数据
  final List<NovelSettingItem> settings;
  
  /// 设定组数据
  final List<SettingGroup> settingGroups;
  
  /// 片段数据
  final List<NovelSnippet> snippets;

  /// 选中的文本（用于缩写）
  final String? selectedText;
  
  /// 🚀 新增：流式生成回调
  final Function(UniversalAIRequest, UnifiedAIModel)? onStreamingGenerate;

  /// 🚀 新增：初始化参数，用于返回表单时恢复设置
  final String? initialInstructions;
  final String? initialLength;
  final bool? initialEnableSmartContext;
  final ContextSelectionData? initialContextSelections;
  
  /// 🚀 新增：初始化统一模型参数
  final UnifiedAIModel? initialSelectedUnifiedModel;

  @override
  State<SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<SummaryDialog> with AIDialogCommonLogic {
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
    
    // 🚀 添加调试日志
    debugPrint('SummaryDialog 初始化上下文选择数据');
    debugPrint('SummaryDialog Novel: ${widget.novel?.title}');
    debugPrint('SummaryDialog Settings: ${widget.settings.length}');
    debugPrint('SummaryDialog Setting Groups: ${widget.settingGroups.length}');
    debugPrint('SummaryDialog Snippets: ${widget.snippets.length}');
    
    // 初始化上下文选择数据
    if (widget.initialContextSelections != null) {
      // 🚀 使用传入的上下文选择数据
      _contextSelectionData = widget.initialContextSelections!;
      debugPrint('SummaryDialog 使用传入的上下文选择数据');
    } else if (widget.novel != null) {
      // 🚀 修复：使用包含设定和片段的构建方法
      _contextSelectionData = ContextSelectionDataBuilder.fromNovelWithContext(
        widget.novel!,
        settings: widget.settings,
        settingGroups: widget.settingGroups,
        snippets: widget.snippets,
      );
      debugPrint('SummaryDialog 从Novel构建上下文选择数据成功');
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
      debugPrint('SummaryDialog 创建演示上下文选择数据');
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
    // 确保公共模型已加载，无私人模型时仍可选择公共模型
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

  OverlayEntry? _tempOverlay;

  @override
  void dispose() {
    _instructionsController.dispose();
    _lengthController.dispose();
    _tempOverlay?.remove(); // 清理临时overlay
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
      debugPrint('Warning: UniversalAIRepository not found in context, creating fallback instance');
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
        title: '缩写文本',
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
        onTabChanged: _onTabChanged,
        showPresets: true,
        usePresetDropdown: true,
        presetFeatureType: 'TEXT_SUMMARY',
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
        primaryActionLabel: '生成',
        onPrimaryAction: _handleGenerate,
        onClose: _handleClose,
        aiConfigBloc: widget.aiConfigBloc,
      ),
    );
  }

  /// 构建调整选项卡
  Widget _buildTweakTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        
        // 长度字段（必填）
        FormFieldFactory.createLengthField<String>(
          options: const [
            RadioOption(value: 'half', label: '一半'),
            RadioOption(value: 'quarter', label: '四分之一'),
            RadioOption(value: 'paragraph', label: '单段落'),
          ],
          value: _selectedLength,
          onChanged: _handleLengthChanged,
          title: '长度',
          description: '缩短后的文本应该多长？',
          isRequired: true,
          onReset: _handleResetLength,
          alternativeInput: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 40),
            child: TextField(
              controller: _lengthController,
              decoration: InputDecoration(
                hintText: 'e.g. 100 words',
                isDense: true,
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
              ),
              onChanged: (value) {
                setState(() {
                  _selectedLength = null; // 清除单选按钮选择
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 指令字段（可选）
        FormFieldFactory.createInstructionsField(
          controller: _instructionsController,
          title: '指令',
          description: '为AI提供的任何（可选）额外指令和角色',
          placeholder: 'e.g. You are a...',
          onReset: _handleResetInstructions,
          onExpand: _handleExpandInstructions,
          onCopy: _handleCopyInstructions,
        ),
        
        const SizedBox(height: 16),

        // 🚀 新增：附加上下文字段
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
          description: '使用AI自动检索相关背景信息，提升缩写质量',
        ),
        
        const SizedBox(height: 16),
        
        // 🚀 新增：关联提示词模板选择字段
        FormFieldFactory.createPromptTemplateSelectionField(
          selectedTemplateId: _selectedPromptTemplateId,
          onTemplateSelected: _handlePromptTemplateSelected,
          aiFeatureType: 'TEXT_SUMMARY', // 🚀 使用标准API字符串格式
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

  /// 构建当前请求对象（用于保存预设）
  UniversalAIRequest? _buildCurrentRequest() {
    if (_selectedUnifiedModel == null) return null;

    // 🚀 使用公共逻辑创建模型配置
    final modelConfig = createModelConfig(_selectedUnifiedModel!);

    // 🚀 使用公共逻辑创建元数据
    final metadata = createModelMetadata(_selectedUnifiedModel!, {
      'action': 'summary',
      'source': 'summary_dialog',
      'contextCount': _contextSelectionData.selectedCount,
      'originalLength': widget.selectedText?.length ?? 0,
      'enableSmartContext': _enableSmartContext,
    });

    return UniversalAIRequest(
      requestType: AIRequestType.summary,
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
        onLengthChanged: (length) {
          setState(() {
            if (length != null && ['half', 'quarter', 'paragraph'].contains(length)) {
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
      AppLogger.e('SummaryDialog', '应用预设失败', e);
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
    AppLogger.i('SummaryDialog', '预设创建成功: ${preset.presetName}');
  }
  
  /// 处理选项卡切换
  void _onTabChanged(String tabId) {
    if (tabId == 'preview') {
      _triggerPreview();
    }
  }

  /// 触发预览生成
  void _triggerPreview() {
    // 验证必填字段，如果缺少必要信息，仍然可以生成预览但会显示错误提示
    UserAIModelConfigModel modelConfig;
    if (_selectedUnifiedModel == null) {
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
      // 🚀 使用公共逻辑创建模型配置
      modelConfig = createModelConfig(_selectedUnifiedModel!);
    }

    String selectedText;
    if (widget.selectedText == null || widget.selectedText!.trim().isEmpty) {
      selectedText = '请选择要缩写的文本';
    } else {
      selectedText = widget.selectedText!;
    }

    // 🚀 使用公共逻辑创建元数据（仅在有模型时）
    Map<String, dynamic> metadata;
    if (_selectedUnifiedModel != null) {
      metadata = createModelMetadata(_selectedUnifiedModel!, {
        'action': 'summary',
        'source': 'preview',
        'contextCount': _contextSelectionData.selectedCount,
        'originalLength': widget.selectedText?.length ?? 0,
        'enableSmartContext': _enableSmartContext,
      });
    } else {
      metadata = {
        'action': 'summary',
        'source': 'preview',
        'contextCount': _contextSelectionData.selectedCount,
        'originalLength': widget.selectedText?.length ?? 0,
        'enableSmartContext': _enableSmartContext,
      };
    }

    // 构建预览请求
    final request = UniversalAIRequest(
      requestType: AIRequestType.summary,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      modelConfig: modelConfig,
      selectedText: selectedText,
      instructions: _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'length': _selectedLength ?? _lengthController.text.trim(),
        'temperature': _temperature, // 🚀 使用用户设置的温度值
        'topP': _topP, // 🚀 新增：使用用户设置的Top-P值
        'maxTokens': 4000,
        if (_selectedUnifiedModel != null) 'modelName': _selectedUnifiedModel!.modelId,
        'enableSmartContext': _enableSmartContext,
        'promptTemplateId': _selectedPromptTemplateId, // 🚀 新增：关联提示词模板ID
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: metadata,
    );

    // 发送预览请求
    context.read<UniversalAIBloc>().add(
      PreviewAIRequestEvent(request),
    );
  }

  void _handleGenerate() async {
    // 检查必填字段
    if (_selectedLength == null && _lengthController.text.trim().isEmpty) {
      TopToast.error(context, '请选择或输入目标长度');
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

    debugPrint('缩写长度: ${_selectedLength ?? _lengthController.text.trim()}');
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
        'action': 'summary',
        'source': 'selection_toolbar',
        'contextCount': _contextSelectionData.selectedCount,
        'originalLength': widget.selectedText?.length ?? 0,
        'enableSmartContext': _enableSmartContext,
      });

      // 构建AI请求
      final request = UniversalAIRequest(
        requestType: AIRequestType.summary,
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
        metadata: metadata,
      );

      // 如果有流式生成回调，调用它
      if (widget.onStreamingGenerate != null) {
        // 使用统一模型
        widget.onStreamingGenerate!(request, _selectedUnifiedModel!);
      }
      
      // 通过回调通知父组件开始流式生成（用于日志记录）
      widget.onGenerate?.call();
      
      debugPrint('流式缩写生成已启动: 模型=${_selectedUnifiedModel!.displayName}, 智能上下文=$_enableSmartContext, 原文长度=${widget.selectedText?.length ?? 0}');
      
    } catch (e) {
      TopToast.error(context, '启动生成失败: $e');
      debugPrint('启动缩写生成失败: $e');
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

/// 显示缩写对话框的便捷函数
void showSummaryDialog(
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
  String? initialLength,
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
        child: SummaryDialog(
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
      initialLength: initialLength,
      initialEnableSmartContext: initialEnableSmartContext,
      initialContextSelections: initialContextSelections,
      initialSelectedUnifiedModel: initialSelectedUnifiedModel,
        ),
      );
    },
  );
} 