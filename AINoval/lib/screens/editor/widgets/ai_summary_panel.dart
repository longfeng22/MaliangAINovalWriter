import 'package:ainoval/blocs/editor/editor_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/ai_request_models.dart';
// import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/widgets/common/form_dialog_template.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/widgets/common/scene_selector.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter/services.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

/// AI摘要生成面板，提供根据场景内容生成摘要的功能
class AISummaryPanel extends StatefulWidget {
  const AISummaryPanel({
    Key? key,
    required this.novelId,
    required this.onClose,
    this.isCardMode = false,
  }) : super(key: key);

  final String novelId;
  final VoidCallback onClose;
  final bool isCardMode; // 是否以卡片模式显示

  @override
  State<AISummaryPanel> createState() => _AISummaryPanelState();
}

class _AISummaryPanelState extends State<AISummaryPanel> with AIDialogCommonLogic {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _summaryController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  
  UnifiedAIModel? _selectedModel;
  bool _enableSmartContext = true;
  // bool _userScrolled = false; // 未使用，先注释避免警告
  // bool _contentEdited = false; // 未使用，先注释避免警告
  bool _isGenerating = false;
  bool _thisInstanceIsGenerating = false; // 标记是否是当前实例发起的生成请求
  late ContextSelectionData _contextSelectionData;
  String? _selectedPromptTemplateId;
  // 临时自定义提示词
  String? _customSystemPrompt;
  String? _customUserPrompt;
  bool _contextInitialized = false;

  @override
  void initState() {
    super.initState();
    // _contentEdited = false;
    
    // 监听滚动事件，检测用户是否主动滚动
    _scrollController.addListener(_handleUserScroll);
    
    // 初始化默认模型配置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDefaultModel();
      _initializeContextData();
    });
  }
  
  void _initializeDefaultModel() {
    final aiConfigState = context.read<AiConfigBloc>().state;
    final publicModelsState = context.read<PublicModelsBloc>().state;
    
    // 合并私有模型和公共模型
    final allModels = _combineModels(aiConfigState, publicModelsState);
    
    if (allModels.isNotEmpty && _selectedModel == null) {
      // 优先选择默认配置
      UnifiedAIModel? defaultModel;
      
      // 首先查找私有模型中的默认配置
      for (final model in allModels) {
        if (!model.isPublic && (model as PrivateAIModel).userConfig.isDefault) {
          defaultModel = model;
          break;
        }
      }
      
      // 如果没有默认私有模型，选择第一个公共模型
      defaultModel ??= allModels.firstWhere(
        (model) => model.isPublic,
        orElse: () => allModels.first,
      );
      
      setState(() {
        _selectedModel = defaultModel;
      });
    }
  }

  /// 合并私有模型和公共模型
  List<UnifiedAIModel> _combineModels(AiConfigState aiState, PublicModelsState publicState) {
    final List<UnifiedAIModel> allModels = [];
    
    // 添加已验证的私有模型
    final validatedConfigs = aiState.validatedConfigs;
    for (final config in validatedConfigs) {
      allModels.add(PrivateAIModel(config));
    }
    
    // 添加公共模型
    if (publicState is PublicModelsLoaded) {
      for (final publicModel in publicState.models) {
        allModels.add(PublicAIModel(publicModel));
      }
    }
    
    return allModels;
  }

  void _initializeContextData() {
    if (_contextInitialized) return;
    final editorState = context.read<EditorBloc>().state;
    if (editorState is EditorLoaded) {
      _contextSelectionData = ContextSelectionDataBuilder.fromNovel(editorState.novel);
      _contextInitialized = true;
    }
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_handleUserScroll);
    _scrollController.dispose();
    _summaryController.dispose();
    super.dispose();
  }
  
  void _handleUserScroll() {}
  
  /// 复制内容到剪贴板
  void _copyToClipboard(String content) {
    Clipboard.setData(ClipboardData(text: content)).then((_) {
      TopToast.success(context, '摘要已复制到剪贴板');
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EditorBloc, EditorState>(
      builder: (context, editorState) {
        if (editorState is! EditorLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return BlocConsumer<UniversalAIBloc, UniversalAIState>(
          listener: (context, state) {
            // 只处理摘要生成相关的状态变化
            if (state is UniversalAIStreaming) {
              // 检查是否是摘要生成请求
              if (_isSummaryRequest(state)) {
                setState(() {
                  _isGenerating = true;
                  _summaryController.text = state.partialResponse;
                   // _contentEdited = false;
                });
              }
            } else if (state is UniversalAISuccess) {
              // 检查是否是摘要生成请求
              if (_isSummaryRequest(state)) {
                setState(() {
                  _isGenerating = false;
                  _thisInstanceIsGenerating = false; // 重置实例生成标记
                  _summaryController.text = state.response.content;
                   // _contentEdited = false;
                });
              }
            } else if (state is UniversalAIError) {
              // 检查是否是摘要生成请求
              if (_isSummaryRequest(state)) {
                setState(() {
                  _isGenerating = false;
                  _thisInstanceIsGenerating = false; // 重置实例生成标记
                });
                TopToast.error(context, '生成摘要失败: ${state.message}');
              }
            } else if (state is UniversalAILoading) {
              // 检查是否是摘要生成请求
              if (_isSummaryRequest(state)) {
                setState(() {
                  _isGenerating = true;
                });
              }
            }
          },
          builder: (context, universalAIState) {
            return SafeArea(
              bottom: true,
              child: Column(
                children: [
                  // 面板标题栏
                  _buildHeader(context, editorState),

                  // 面板内容
                  Expanded(
                    child: _buildSummaryContentPanel(context, editorState),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, EditorLoaded state) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context),
            border: Border(
              bottom: BorderSide(
                color: WebTheme.getSecondaryBorderColor(context),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // 标题行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: WebTheme.getPrimaryColor(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.summarize,
                          size: 14,
                          color: WebTheme.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI摘要助手',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // 状态指示器
                      if (_isGenerating) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        ),
                        const SizedBox(width: 6),
                         Text(
                          '正在生成...',
                           style: TextStyle(
                            fontSize: 11,
                             color: WebTheme.getTextColor(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      
                      // 帮助按钮
                      Tooltip(
                        message: '使用说明',
                        child: IconButton(
                          icon: Icon(
                            Icons.help_outline, 
                            size: 16,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: WebTheme.getCardColor(context),
                                surfaceTintColor: Colors.transparent,
                                title: Text(
                                  'AI摘要生成说明',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: WebTheme.getTextColor(context),
                                  ),
                                ),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('1. 在上方选择AI模型与是否启用智能上下文。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                      const SizedBox(height: 6),
                                      Text('2. 先在左侧选择要生成摘要的场景。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                      const SizedBox(height: 6),
                                      Text('3. 点击“生成摘要”，进度会实时显示。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                      const SizedBox(height: 6),
                                      Text('4. 生成完成后可直接编辑，或点击“保存摘要”。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                      const SizedBox(height: 10),
                                      Text('小技巧：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WebTheme.getTextColor(context))),
                                      const SizedBox(height: 4),
                                      Text('· 小屏支持滚动查看完整内容与按钮。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                      Text('· 可通过“关联提示词模板”优化效果。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                    ],
                                  ),
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: WebTheme.getPrimaryColor(context),
                                      foregroundColor: WebTheme.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                    child: const Text('了解了', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(Icons.close, size: 16, color: WebTheme.getSecondaryTextColor(context)),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: const EdgeInsets.all(4),
                        onPressed: widget.onClose,
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ],
              ),
              
              // 当前场景信息行
              const SizedBox(height: 8),
              _buildCurrentSceneSelector(context, state),
            ],
          ),
         );
  }

  Widget _buildCurrentSceneSelector(BuildContext context, EditorLoaded state) {
    return SceneSelector(
      novel: state.novel,
      activeSceneId: state.activeSceneId,
      onSceneSelected: (sceneId, actId, chapterId) {
        // 更新活跃场景
        context.read<EditorBloc>().add(SetActiveScene(
          actId: actId,
          chapterId: chapterId,
          sceneId: sceneId,
        ));
      },
      onSummaryLoaded: (summary) {
        // 加载场景摘要到输入框
        setState(() {
          _summaryController.text = summary;
        });
      },
    );
  }

  // 构建摘要内容面板
  Widget _buildSummaryContentPanel(BuildContext context, EditorLoaded state) {
    final mq = MediaQuery.of(context);
    final bool isSmallScreen = mq.size.width < 1200 || mq.size.height < 800;
    final double outerPadding = isSmallScreen ? 8.0 : 10.0;

    return Padding(
      padding: EdgeInsets.all(outerPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部区域：可滚动，适配小屏幕
          Flexible(
            child: Scrollbar(
              thumbVisibility: MediaQuery.of(context).size.height < 800,
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 模型配置区域
                    _buildModelConfigSection(context, state),
                    const SizedBox(height: 10),
                    // 分割线
                    Container(
                      height: 1,
                      color: WebTheme.getSecondaryBorderColor(context),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),

          // 生成的摘要区域（底部区域保留，确保操作与内容显示良好）
          Expanded(
            child: _buildSummarySection(context, state),
          ),
        ],
      ),
    );
  }

  Widget _buildModelConfigSection(BuildContext context, EditorLoaded state) {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: WebTheme.getSecondaryBorderColor(context),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '模型设置',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          
          // 统一模型选择器
          _buildUnifiedModelSelector(context, state),
          
          const SizedBox(height: 12),
          
          // 智能上下文开关
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '智能上下文',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '启用后将自动检索相关的小说设定和背景信息',
                      style: TextStyle(
                        fontSize: 10,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _enableSmartContext,
                  activeColor: WebTheme.getPrimaryColor(context),
                  activeTrackColor: WebTheme.getSecondaryBorderColor(context),
                  inactiveThumbColor: WebTheme.getCardColor(context),
                  inactiveTrackColor: WebTheme.getSecondaryBorderColor(context),
                  onChanged: (value) {
                    setState(() {
                      _enableSmartContext = value;
                    });
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),

          // 上下文选择
          if (_contextInitialized)
            FormFieldFactory.createContextSelectionField(
              contextData: _contextSelectionData,
              onSelectionChanged: (newData) {
                setState(() {
                  _contextSelectionData = newData;
                });
              },
              title: '附加上下文',
              description: '选择要包含在生成中的上下文信息',
              onReset: () {
                setState(() {
                  _contextSelectionData = ContextSelectionDataBuilder.fromNovel(state.novel);
                });
              },
              dropdownWidth: 400,
              initialChapterId: state.activeChapterId,
              initialSceneId: state.activeSceneId,
            ),

          if (_contextInitialized) const SizedBox(height: 12),

          // 关联提示词模板
          FormFieldFactory.createPromptTemplateSelectionField(
            selectedTemplateId: _selectedPromptTemplateId,
            onTemplateSelected: (templateId) {
              setState(() {
                _selectedPromptTemplateId = templateId;
              });
            },
            aiFeatureType: 'SCENE_TO_SUMMARY',
            title: '关联提示词模板',
            description: '可选，选择一个提示词模板优化摘要生成',
            onReset: () {
              setState(() {
                _selectedPromptTemplateId = null;
              });
            },
            onTemporaryPromptsSaved: (sys, user) {
              setState(() {
                _customSystemPrompt = sys.trim().isEmpty ? null : sys.trim();
                _customUserPrompt = user.trim().isEmpty ? null : user.trim();
              });
            },
          ),

          const SizedBox(height: 12),

          // 生成按钮
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton.icon(
              onPressed: (_getActiveScene(state) == null || 
                         _getActiveScene(state)!.content.isEmpty ||
                         _selectedModel == null ||
                         _isGenerating)
                  ? null
                  : () => _generateSummary(context, state),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 14),
              label: Text(
                _isGenerating ? '生成中...' : '生成摘要',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统一模型选择器
  Widget _buildUnifiedModelSelector(BuildContext context, EditorLoaded state) {
    return BlocBuilder<AiConfigBloc, AiConfigState>(
      builder: (context, aiState) {
        return BlocBuilder<PublicModelsBloc, PublicModelsState>(
          builder: (context, publicState) {
            final allModels = _combineModels(aiState, publicState);
            
            return CompositedTransformTarget(
              link: _layerLink,
              child: InkWell(
                onTap: () {
                  _showModelDropdown(context, state, allModels);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _selectedModel != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedModel!.displayName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _selectedModel!.isPublic ? Colors.green[50] : Colors.blue[50],
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                            color: _selectedModel!.isPublic ? Colors.green[200]! : Colors.blue[200]!,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          _selectedModel!.isPublic ? '系统' : '私有',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _selectedModel!.isPublic ? Colors.green[700] : Colors.blue[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _selectedModel!.provider,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : const Text(
                                '选择AI模型',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.black54,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 显示模型选择下拉菜单
  void _showModelDropdown(BuildContext context, EditorLoaded state, List<UnifiedAIModel> allModels) {
    UnifiedAIModelDropdown.show(
      context: context,
      layerLink: _layerLink,
      selectedModel: _selectedModel,
      onModelSelected: (model) {
        setState(() {
          _selectedModel = model;
        });
      },
      showSettingsButton: false,
      maxHeight: 300,
      novel: state.novel,
    );
  }

  Widget _buildSummarySection(BuildContext context, EditorLoaded state) {
    final hasContent = _summaryController.text.isNotEmpty;
    final activeScene = _getActiveScene(state);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '生成的摘要',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (hasContent && !_isGenerating) ...[
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.copy, size: 14, color: Colors.black),
                      tooltip: '复制到剪贴板',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _copyToClipboard(_summaryController.text);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (activeScene != null) ...[
                    SizedBox(
                      height: 28,
                      child: ElevatedButton(
                        onPressed: _summaryController.text.trim().isEmpty 
                            ? null 
                            : () => _saveSummary(context, state, activeScene),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.grey[200],
                          disabledForegroundColor: Colors.grey,
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          '保存摘要',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.grey[300]!,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isGenerating && _summaryController.text.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '正在生成摘要...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  )
                : !hasContent && !_isGenerating
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.summarize,
                              color: Colors.grey,
                              size: 32,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '点击"生成摘要"按钮开始生成',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : TextField(
                        controller: _summaryController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(12),
                          border: InputBorder.none,
                          hintText: '生成的摘要将显示在这里',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.black,
                        ),
                        onChanged: (_) {
                          setState(() {
                             // _contentEdited = true;
                          });
                        },
                      ),
          ),
        ),
      ],
    );
  }

  /// 检查是否是摘要生成请求
  bool _isSummaryRequest(UniversalAIState state) {
    // 对于流式响应状态，只有当前实例发起的请求才处理
    if (state is UniversalAIStreaming) {
      return _thisInstanceIsGenerating;
    } 
    // 对于成功状态，检查请求类型
    else if (state is UniversalAISuccess) {
      return state.response.requestType == AIRequestType.sceneSummary;
    } 
    // 对于错误和加载状态，检查当前实例是否有生成任务
    else if (state is UniversalAIError || state is UniversalAILoading) {
      return _thisInstanceIsGenerating;
    }
    return false;
  }

  /// 生成摘要
  void _generateSummary(BuildContext context, EditorLoaded state) {
    final activeScene = _getActiveScene(state);
    if (activeScene == null || _selectedModel == null) return;

    // 清空现有内容
    _summaryController.clear();
    
    AppLogger.i('AISummaryPanel', '开始生成摘要，场景ID: ${activeScene.id}');

    // 使用公共逻辑创建模型配置（公共模型会被包装为临时配置）
    final modelConfig = createModelConfig(_selectedModel!);

    // 构建AI请求（先将Quill内容转换为纯文本）
    final String plainSceneText = QuillHelper.deltaToText(activeScene.content);
    // 构建元数据（包含公共模型标识）
    final metadata = createModelMetadata(_selectedModel!, {
      'actId': state.activeActId,
      'chapterId': state.activeChapterId,
      'sceneId': state.activeSceneId,
      'sceneTitle': activeScene.title,
      'wordCount': activeScene.wordCount,
      'action': 'scene_summary',
      'source': 'ai_summary_panel',
    });
    final request = UniversalAIRequest(
      requestType: AIRequestType.sceneSummary,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novelId,
      modelConfig: modelConfig,
      selectedText: plainSceneText, // 使用纯文本作为输入
      instructions: '请为这个小说场景生成一个准确、简洁的摘要，突出关键情节和重要细节。',
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'temperature': 0.7,
        'maxTokens': 500,
        'promptTemplateId': _selectedPromptTemplateId,
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: metadata,
    );

    // 公共模型预估积分并确认
    if (_selectedModel!.isPublic) {
      handlePublicModelCreditConfirmation(_selectedModel!, request).then((ok) {
        if (!ok) return;
        setState(() { _thisInstanceIsGenerating = true; });
        context.read<UniversalAIBloc>().add(SendAIStreamRequestEvent(request));
      });
      return;
    }

    // 发送流式请求（私有模型直接发送）
    setState(() { _thisInstanceIsGenerating = true; });
    context.read<UniversalAIBloc>().add(SendAIStreamRequestEvent(request));
  }

  void _saveSummary(BuildContext context, EditorLoaded state, Scene activeScene) {
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) return;
    
    // 保存摘要到场景
    context.read<EditorBloc>().add(
      UpdateSummary(
        novelId: widget.novelId,
        actId: state.activeActId!,
        chapterId: state.activeChapterId!,
        sceneId: activeScene.id,
        summary: summary,
      ),
    );
    
    // 显示保存成功提示
    TopToast.success(context, '摘要已保存');
    
    // 已移除未使用的编辑状态标记
    
    AppLogger.i('AISummaryPanel', '摘要已保存: ${activeScene.id}');
  }

  // 获取当前活动场景
  Scene? _getActiveScene(EditorLoaded state) {
    if (state.activeSceneId != null && state.activeActId != null && state.activeChapterId != null) {
      // 获取完整的场景对象而不仅仅是ID
      final scene = state.novel.getScene(state.activeActId!, state.activeChapterId!, sceneId: state.activeSceneId);
      return scene;
    }
    return null;
  }
}
