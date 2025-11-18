import 'package:ainoval/blocs/editor/editor_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/widgets/common/scene_selector.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
// import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:flutter/services.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
// import 'package:ainoval/widgets/common/app_search_field.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/widgets/common/form_dialog_template.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';

/// AI生成面板，提供根据摘要生成场景的功能
class AIGenerationPanel extends StatefulWidget {
  const AIGenerationPanel({
    Key? key,
    required this.novelId,
    required this.onClose,
    this.isCardMode = false,
  }) : super(key: key);

  final String novelId;
  final VoidCallback onClose;
  final bool isCardMode; // 是否以卡片模式显示

  @override
  State<AIGenerationPanel> createState() => _AIGenerationPanelState();
}

class _AIGenerationPanelState extends State<AIGenerationPanel> with AIDialogCommonLogic {
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _styleController = TextEditingController();
  final TextEditingController _generatedContentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LayerLink _layerLink = LayerLink();
  
  UnifiedAIModel? _selectedModel;
  bool _enableSmartContext = true;
  bool _userScrolled = false;
  // bool _contentEdited = false; // 未使用，注释避免警告
  bool _isGenerating = false;
  // String _generatedText = '';
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
    
    // 监听滚动事件，检测用户是否主动滚动
    _scrollController.addListener(_handleUserScroll);
    
    // 初始化默认模型配置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDefaultModel();
      _initializeContextData();
    });
    
    // 读取待处理的摘要内容或当前场景的摘要
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorState = context.read<EditorBloc>().state;
      if (editorState is EditorLoaded) {
        if (editorState.pendingSummary != null && editorState.pendingSummary!.isNotEmpty) {
          // 优先使用待处理摘要
          _summaryController.text = editorState.pendingSummary!;
          
          // 清除待处理摘要，避免下次打开时仍然显示
          context.read<EditorBloc>().add(const SetPendingSummary(summary: ''));
        } else {
          // 自动导入当前场景的摘要
          _loadCurrentSceneSummary(editorState);
        }
      }
    });
  }
  
  void _initializeContextData() {
    if (_contextInitialized) return;
    final editorState = context.read<EditorBloc>().state;
    if (editorState is EditorLoaded) {
      _contextSelectionData = ContextSelectionDataBuilder.fromNovel(editorState.novel);
      _contextInitialized = true;
    }
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

  /// 加载当前场景的摘要到输入框
  void _loadCurrentSceneSummary(EditorLoaded state) {
    if (state.activeActId != null && 
        state.activeChapterId != null && 
        state.activeSceneId != null) {
      
      final scene = state.novel.getScene(
        state.activeActId!, 
        state.activeChapterId!, 
        sceneId: state.activeSceneId,
      );
      
      if (scene != null && scene.summary.content.isNotEmpty) {
        setState(() {
          _summaryController.text = scene.summary.content;
        });
      }
    }
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _styleController.dispose();
    _generatedContentController.dispose();
    _scrollController.removeListener(_handleUserScroll);
    _scrollController.dispose();
    super.dispose();
  }
  
  void _handleUserScroll() {
    if (_scrollController.hasClients) {
      // 如果用户向上滚动（滚动位置不在底部），标记为用户滚动
      if (_scrollController.position.pixels < 
          _scrollController.position.maxScrollExtent - 50) {
        _userScrolled = true;
      }
      
      // 如果用户滚动到底部，重置标记
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 10) {
        _userScrolled = false;
      }
    }
  }
  
  /// 复制内容到剪贴板
  void _copyToClipboard(String content) {
    Clipboard.setData(ClipboardData(text: content)).then((_) {
      TopToast.success(context, '内容已复制到剪贴板');
    });
  }

  Widget _buildModelConfigSection(BuildContext context, EditorLoaded state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WebTheme.getSecondaryBorderColor(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '模型设置',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          
          // 统一模型选择器
          _buildUnifiedModelSelector(context, state),
          
          const SizedBox(height: 10),
          
          // 智能上下文开关
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '智能上下文',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '自动检索相关设定和背景信息',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enableSmartContext,
                onChanged: (value) {
                  setState(() {
                    _enableSmartContext = value;
                  });
                },
                activeColor: Colors.black,
                activeTrackColor: Colors.grey[300],
                inactiveThumbColor: Colors.grey[400],
                inactiveTrackColor: Colors.grey[200],
              ),
            ],
          ),

          const SizedBox(height: 10),

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
              description: '为AI提供的任何额外信息',
              onReset: () {
                setState(() {
                  _contextSelectionData = ContextSelectionDataBuilder.fromNovel(state.novel);
                });
              },
              dropdownWidth: 400,
              initialChapterId: state.activeChapterId,
              initialSceneId: state.activeSceneId,
            ),

          if (_contextInitialized) const SizedBox(height: 10),

          // 关联提示词模板
          FormFieldFactory.createPromptTemplateSelectionField(
            selectedTemplateId: _selectedPromptTemplateId,
            onTemplateSelected: (templateId) {
              setState(() {
                _selectedPromptTemplateId = templateId;
              });
            },
            aiFeatureType: 'SUMMARY_TO_SCENE',
            title: '关联提示词模板',
            description: '可选，选择一个提示词模板优化生成效果',
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
                    color: WebTheme.getCardColor(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: WebTheme.getSecondaryBorderColor(context), width: 1),
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
                                     style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                       color: WebTheme.getTextColor(context),
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
                                          color: WebTheme.getSecondaryTextColor(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                              : Text(
                                '选择AI模型',
                                  style: TextStyle(
                                  fontSize: 13,
                                    color: WebTheme.getSecondaryTextColor(context),
                                ),
                              ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: WebTheme.getSecondaryTextColor(context),
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

  /// 构建章节下拉菜单选项
  List<DropdownMenuItem<String>> _buildChapterDropdownItems(Novel novel) {
    final items = <DropdownMenuItem<String>>[];

    for (final act in novel.acts) {
      // 添加Act分组标题
      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 3),
            child: Text(
              act.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ),
        ),
      );

      // 添加Act下的Chapter
      for (final chapter in act.chapters) {
        items.add(
          DropdownMenuItem<String>(
            value: chapter.id,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 8), // 缩进
                  const Icon(Icons.menu_book_outlined, size: 14, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return items;
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
              // 只处理场景生成相关的状态变化
              if (state is UniversalAIStreaming) {
                // 检查是否是场景生成请求
                if (_isGenerationRequest(state)) {
                  setState(() {
                    _isGenerating = true;
                    _generatedContentController.text = state.partialResponse;
                     // _contentEdited = false;
                  });
                  
                  // 如果用户没有主动滚动，自动滚动到底部
                  if (!_userScrolled && _scrollController.hasClients) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  }
                }
                          } else if (state is UniversalAISuccess) {
              // 检查是否是场景生成请求
              if (_isGenerationRequest(state)) {
                setState(() {
                  _isGenerating = false;
                  _thisInstanceIsGenerating = false; // 重置实例生成标记
                  _generatedContentController.text = state.response.content;
                   // _contentEdited = false;
                });
                // 🚀 生成完成后刷新积分
                try {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    // ignore: use_build_context_synchronously
                    context.read<CreditBloc>().add(const RefreshUserCredits());
                  });
                } catch (_) {}
              }
            } else if (state is UniversalAICancelled) {
              // 处理取消状态
              if (_thisInstanceIsGenerating) {
                setState(() {
                  _isGenerating = false;
                  _thisInstanceIsGenerating = false;
                });
              }
            } else if (state is UniversalAIError) {
                // 检查是否是场景生成请求
                if (_isGenerationRequest(state)) {
                  setState(() {
                    _isGenerating = false;
                    _thisInstanceIsGenerating = false; // 重置实例生成标记
                  });
                  TopToast.error(context, '生成场景失败: ${state.message}');
                }
              } else if (state is UniversalAILoading) {
                // 检查是否是场景生成请求
                if (_isGenerationRequest(state)) {
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
                      child: _buildSceneGenerationPanel(context, editorState),
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
                      Icons.auto_awesome,
                      size: 14,
                      color: WebTheme.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI场景生成',
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
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(WebTheme.getTextColor(context)),
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
                              'AI场景生成说明',
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
                                  Text('1. 在上方填写摘要/大纲，并选择AI模型与智能上下文。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 6),
                                  Text('2. 可填写“风格指令”（如：多对话、悬疑风格）。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 6),
                                  Text('3. 需要时选择“目标章节”，有助于上下文更准确。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 6),
                                  Text('4. 点击“生成场景”，可实时查看生成过程。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 6),
                                  Text('5. 生成后可复制、重新生成，或直接“添加为新场景”。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 10),
                                  Text('小技巧：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WebTheme.getTextColor(context))),
                                  const SizedBox(height: 4),
                                  Text('· 小屏支持滚动查看完整表单与按钮。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
                                  Text('· 可通过“关联提示词模板”提升生成质量。', style: TextStyle(fontSize: 12, color: WebTheme.getTextColor(context))),
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
          _buildCurrentSceneInfo(context, state),
        ],
      ),
    );
  }

  Widget _buildCurrentSceneInfo(BuildContext context, EditorLoaded state) {
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

  /// 构建场景生成面板
  Widget _buildSceneGenerationPanel(BuildContext context, EditorLoaded state) {
    final hasGenerated = _generatedContentController.text.isNotEmpty;
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
                    // 摘要文本输入
                    const Text(
                      '场景摘要/大纲',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: WebTheme.getCardColor(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: WebTheme.getSecondaryBorderColor(context),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _summaryController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: '请输入场景大纲或摘要，AI将根据此内容生成完整场景',
                          hintStyle: TextStyle(fontSize: 12, color: WebTheme.getSecondaryTextColor(context)),
                          contentPadding: const EdgeInsets.all(12),
                          border: InputBorder.none,
                          suffixIcon: _summaryController.text.isNotEmpty 
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    size: 16,
                                    color: WebTheme.getSecondaryTextColor(context),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () {
                                    setState(() {
                                      _summaryController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: WebTheme.getTextColor(context),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 风格指令输入
                    const Text(
                      '风格指令（可选）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: WebTheme.getCardColor(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: WebTheme.getSecondaryBorderColor(context),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _styleController,
                        decoration: InputDecoration(
                          hintText: '例如：多对话，少描写，悬疑风格',
                          hintStyle: TextStyle(fontSize: 12, color: WebTheme.getSecondaryTextColor(context)),
                          contentPadding: const EdgeInsets.all(12),
                          border: InputBorder.none,
                          suffixIcon: _styleController.text.isNotEmpty 
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    size: 16, 
                                    color: WebTheme.getSecondaryTextColor(context),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () {
                                    setState(() {
                                      _styleController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: WebTheme.getTextColor(context),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 章节选择（可选）
                    if (state.novel.acts.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '目标章节（可选）',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          if (state.activeChapterId != null)
                            OutlinedButton.icon(
                              onPressed: () {
                                // 查找当前章节信息
                                String chapterTitle = "";
                                for (final act in state.novel.acts) {
                                  for (final chapter in act.chapters) {
                                    if (chapter.id == state.activeChapterId) {
                                      chapterTitle = chapter.title;
                                      break;
                                    }
                                  }
                                  if (chapterTitle.isNotEmpty) break;
                                }
                                
                                if (chapterTitle.isNotEmpty) {
                                  // 添加章节相关信息到摘要
                                  final currentText = _summaryController.text;
                                  final chapterContext = "本场景为《$chapterTitle》章节的一部分，";
                                  if (currentText.isNotEmpty) {
                                    _summaryController.text = '$chapterContext$currentText';
                                  } else {
                                    _summaryController.text = chapterContext;
                                  }
                                }
                              },
                              icon: Icon(Icons.add_box_outlined, size: 14, color: WebTheme.getTextColor(context)),
                              label: Text(
                                '添加到摘要',
                                style: TextStyle(fontSize: 11, color: WebTheme.getTextColor(context)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: WebTheme.getSecondaryBorderColor(context), width: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 28),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: WebTheme.getCardColor(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: WebTheme.getSecondaryBorderColor(context),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: state.activeChapterId,
                            items: _buildChapterDropdownItems(state.novel),
                            onChanged: (chapterId) {
                              if (chapterId != null) {
                                // 查找选中章节所属的Act
                                String? actId;
                                for (final act in state.novel.acts) {
                                  for (final chapter in act.chapters) {
                                    if (chapter.id == chapterId) {
                                      actId = act.id;
                                      break;
                                    }
                                  }
                                  if (actId != null) break;
                                }

                                if (actId != null) {
                                  // 更新活跃章节
                                  context.read<EditorBloc>().add(SetActiveChapter(
                                    actId: actId,
                                    chapterId: chapterId,
                                  ));
                                }
                              }
                            },
                            style: TextStyle(
                              fontSize: 12,
                              color: WebTheme.getTextColor(context),
                            ),
                            hint: Text(
                              '选择一个目标章节',
                              style: TextStyle(
                                fontSize: 12,
                                color: WebTheme.getSecondaryTextColor(context),
                              ),
                            ),
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                            dropdownColor: WebTheme.getCardColor(context),
                            menuMaxHeight: 240,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 生成结果或操作区域（底部区域，按钮始终可触达）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasGenerated || _isGenerating) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '生成结果', 
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                      if (hasGenerated)
                        Row(
                          children: [
                            Tooltip(
                              message: '重新生成',
                              child: IconButton(
                                onPressed: () {
                                  // 重新生成内容
                                  context.read<EditorBloc>().add(
                                    GenerateSceneFromSummaryRequested(
                                      novelId: state.novel.id,
                                      summary: _summaryController.text,
                                      chapterId: state.activeChapterId,
                                      styleInstructions: _styleController.text.isNotEmpty
                                          ? _styleController.text
                                          : null,
                                      useStreamingMode: true,
                                    ),
                                  );
                                  
                                  // 重置用户滚动标记
                                  _userScrolled = false;
                                },
                                icon: Icon(Icons.refresh, size: 16, color: WebTheme.getSecondaryTextColor(context)),
                                tooltip: '重新生成',
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                            Tooltip(
                              message: '复制全文',
                              child: IconButton(
                                onPressed: () => _copyToClipboard(_generatedContentController.text),
                                icon: Icon(Icons.copy, size: 16, color: WebTheme.getSecondaryTextColor(context)),
                                tooltip: '复制全文',
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                            Tooltip(
                              message: '添加为新场景',
                              child: IconButton(
                                onPressed: () {
                                  // 将生成内容应用到编辑器
                                  if (state.activeActId != null && state.activeChapterId != null) {
                                    // 创建新场景并使用生成内容
                                    final sceneId = 'scene_${DateTime.now().millisecondsSinceEpoch}';
                                    
                                    // 添加新场景
                                    context.read<EditorBloc>().add(AddNewScene(
                                      novelId: widget.novelId,
                                      actId: state.activeActId!,
                                      chapterId: state.activeChapterId!,
                                      sceneId: sceneId,
                                    ));
                                    
                                    // 等待短暂时间，确保场景已添加
                                    Future.delayed(const Duration(milliseconds: 500), () {
                                      // 设置场景内容
                                      context.read<EditorBloc>().add(UpdateSceneContent(
                                        novelId: widget.novelId,
                                        actId: state.activeActId!,
                                        chapterId: state.activeChapterId!,
                                        sceneId: sceneId,
                                        content: _generatedContentController.text,
                                      ));
                                      
                                      // 设置为活动场景
                                      context.read<EditorBloc>().add(SetActiveScene(
                                        actId: state.activeActId!,
                                        chapterId: state.activeChapterId!,
                                        sceneId: sceneId,
                                      ));
                                      
                                      // 关闭生成面板
                                      widget.onClose();
                                      
                                      // 显示通知
                                      TopToast.success(context, '已创建新场景并应用生成内容');
                                    });
                                  }
                                },
                                icon: Icon(Icons.add_circle_outline, size: 16, color: WebTheme.getSecondaryTextColor(context)),
                                tooltip: '添加为新场景',
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _buildGenerationResultSection(context, state),
                  ),
                ],

                const SizedBox(height: 12),

                // 生成按钮区域
                _buildGenerationButtons(context, state),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationResultSection(BuildContext context, EditorLoaded state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isGenerating && _generatedContentController.text.isEmpty
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
                    '正在生成场景...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            )
          : !_generatedContentController.text.isNotEmpty && !_isGenerating
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Colors.grey[400],
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '点击"生成场景"按钮开始生成',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : TextField(
                  controller: _generatedContentController,
                  scrollController: _scrollController,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText: '生成的场景内容将显示在这里',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                  onChanged: (_) {
                    setState(() {
                      // _contentEdited = true;
                    });
                  },
                ),
    );
  }

  Widget _buildGenerationButtons(BuildContext context, EditorLoaded state) {
    final hasContent = _summaryController.text.isNotEmpty;
    
    if (!_isGenerating) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (hasContent && _selectedModel != null) ? () => _generateScene(context, state) : null,
          icon: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          label: const Text(
            '生成场景',
            style: TextStyle(fontSize: 13, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: (hasContent && _selectedModel != null) ? Colors.black : Colors.grey[400],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            context.read<UniversalAIBloc>().add(const StopStreamRequestEvent());
            setState(() {
              _thisInstanceIsGenerating = false;
              _isGenerating = false;
            });
          },
          icon: const Icon(Icons.cancel, size: 16, color: Colors.black87),
          label: const Text(
            '取消生成',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.grey, width: 1),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }
  }

  /// 检查是否是场景生成请求
  bool _isGenerationRequest(UniversalAIState state) {
    // 对于流式响应状态，只有当前实例发起的请求才处理
    if (state is UniversalAIStreaming) {
      return _thisInstanceIsGenerating;
    } 
    // 对于成功状态，检查请求类型
    else if (state is UniversalAISuccess) {
      return state.response.requestType == AIRequestType.generation;
    } 
    // 对于错误和加载状态，检查当前实例是否有生成任务
    else if (state is UniversalAIError || state is UniversalAILoading) {
      return _thisInstanceIsGenerating;
    }
    return false;
  }

  /// 生成场景
  void _generateScene(BuildContext context, EditorLoaded state) {
    if (_selectedModel == null) return;

    // 清空现有内容
    _generatedContentController.clear();
    
    AppLogger.i('AIGenerationPanel', '开始生成场景');

    // 使用公共逻辑创建模型配置（公共模型会被包装为临时配置）
    final modelConfig = createModelConfig(_selectedModel!);

    // 构建AI请求（将摘要文本按需从Quill Delta转换为纯文本）
    final String plainSummaryText = QuillHelper.deltaToText(_summaryController.text);
    final request = UniversalAIRequest(
      requestType: AIRequestType.generation,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novelId,
      chapterId: state.activeChapterId,
      sceneId: state.activeSceneId,
      modelConfig: modelConfig,
      selectedText: plainSummaryText, // 使用纯文本作为输入
      instructions: _styleController.text.isNotEmpty 
          ? '请根据以下摘要生成完整的小说场景。风格要求：${_styleController.text}'
          : '请根据以下摘要生成完整的小说场景。',
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'temperature': 0.8,
        'maxTokens': 2000,
        'promptTemplateId': _selectedPromptTemplateId,
        if (_customSystemPrompt != null) 'customSystemPrompt': _customSystemPrompt,
        if (_customUserPrompt != null) 'customUserPrompt': _customUserPrompt,
      },
      metadata: createModelMetadata(_selectedModel!, {
        'actId': state.activeActId,
        'chapterId': state.activeChapterId,
        'sceneId': state.activeSceneId,
        'action': 'summary_to_scene',
        'source': 'ai_generation_panel',
      }),
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

    // 私有模型直接发送
    setState(() { _thisInstanceIsGenerating = true; });
    context.read<UniversalAIBloc>().add(SendAIStreamRequestEvent(request));
  }
}