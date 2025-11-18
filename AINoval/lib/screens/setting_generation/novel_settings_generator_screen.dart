import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/auth/auth_bloc.dart';
import '../../blocs/setting_generation/setting_generation_bloc.dart';
import '../../blocs/setting_generation/setting_generation_event.dart';
import '../../blocs/setting_generation/setting_generation_state.dart';
import '../../models/unified_ai_model.dart';
import '../../utils/logger.dart';
import 'package:ainoval/services/api_service/repositories/setting_generation_repository.dart';
import 'package:ainoval/blocs/novel_list/novel_list_bloc.dart';
import 'package:ainoval/screens/editor/editor_screen.dart';
import 'package:ainoval/models/novel_summary.dart';
import 'widgets/settings_tree_widget.dart';
import 'widgets/editor_panel_widget.dart';
import 'widgets/history_panel_widget.dart';
import 'widgets/generation_control_panel.dart';
// import 'widgets/ai_shimmer_placeholder.dart';
import 'widgets/results_preview_panel.dart';
import 'widgets/golden_three_chapters_dialog.dart';
import '../../config/app_config.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/models/compose_preview.dart';
import 'package:ainoval/utils/web_theme.dart';
// 📚 知识库集成
import 'package:ainoval/models/knowledge_base_integration_mode.dart';

/// 小说设定生成器主屏幕
class NovelSettingsGeneratorScreen extends StatefulWidget {
  final String? novelId;
  final String? initialPrompt;
  final UnifiedAIModel? selectedModel;
  final String? selectedStrategy; // 预选择的策略
  final bool autoStart; // 是否自动开始生成
  final bool autoLoadFirstHistory; // 是否自动加载第一条历史记录
  // 📚 知识库集成参数
  final KnowledgeBaseIntegrationMode? initialKnowledgeBaseMode;
  final List<SelectedKnowledgeBaseItem>? initialSelectedKnowledgeBases;
  // 📚 混合模式专用：用于参考的知识库（用于区分复用和参考）
  final List<SelectedKnowledgeBaseItem>? initialReferenceKnowledgeBases;

  const NovelSettingsGeneratorScreen({
    Key? key,
    this.novelId,
    this.initialPrompt,
    this.selectedModel,
    this.selectedStrategy,
    this.autoStart = false,
    this.autoLoadFirstHistory = false,
    this.initialKnowledgeBaseMode,
    this.initialSelectedKnowledgeBases,
    this.initialReferenceKnowledgeBases,
  }) : super(key: key);

  @override
  State<NovelSettingsGeneratorScreen> createState() => _NovelSettingsGeneratorScreenState();
}

class _ComposeResultsBridge extends StatefulWidget {
  @override
  State<_ComposeResultsBridge> createState() => _ComposeResultsBridgeState();
}

class _ComposeResultsBridgeState extends State<_ComposeResultsBridge> {
  late var _subPreview;
  late var _subGenerating;
  List<ChapterPreviewData> _chapters = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<SettingGenerationBloc>();
    _subPreview = bloc.composePreviewStream.listen((list) {
      setState(() {
        _chapters = list
            .map((c) => ChapterPreviewData(title: c.title, outline: c.outline, content: c.content))
            .toList();
      });
    });
    _subGenerating = bloc.composeGeneratingStream.listen((v) {
      setState(() => _isGenerating = v);
    });
  }

  @override
  void dispose() {
    _subPreview.cancel();
    _subGenerating.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResultsPreviewPanel(
      chapters: _chapters,
      isGenerating: _isGenerating,
      onChapterChanged: (index, updated) {
        setState(() {
          _chapters[index] = updated;
        });
      },
    );
  }
}

class _NovelSettingsGeneratorScreenState extends State<NovelSettingsGeneratorScreen> {
  // 保存最后一次生成的参数，用于重试
  String? _lastInitialPrompt;
  String? _lastStrategy;
  String? _lastModelConfigId;
  // 新增：主区域视图切换（设定/结果预览）
  String _mainSection = 'settings'; // settings | results
  // 监听后端写作就绪信号，控制头部"开始写作"按钮
  ComposeReadyInfo? _composeReady;
  var _composeReadySub;
  // 🔧 新增：监听黄金三章生成状态
  bool _composeGenerating = false;
  var _composeGeneratingSub;
  
  @override
  void initState() {
    super.initState();
    
    // 保存初始参数
    _lastInitialPrompt = widget.initialPrompt;
    _lastStrategy = widget.selectedStrategy;
    if (widget.selectedModel != null) {
      _lastModelConfigId = widget.selectedModel!.id;
    } else {
      final aiState = context.read<AiConfigBloc>().state;
      final defaultConfig = aiState.defaultConfig ??
          (aiState.validatedConfigs.isNotEmpty ? aiState.validatedConfigs.first : null);
      _lastModelConfigId = defaultConfig?.id ?? '';
    }
    
    // 无论是否登录都尝试加载策略：未登录加载“公开策略”，已登录加载“可用策略”
    try {
      final currentState = context.read<SettingGenerationBloc>().state;
      if (currentState is SettingGenerationInitial || currentState is SettingGenerationError) {
        AppLogger.i('NovelSettingsGeneratorScreen', '需要加载策略，当前状态: ${currentState.runtimeType}');
        context.read<SettingGenerationBloc>().add(LoadStrategiesEvent(
          novelId: widget.novelId,
        ));
      }

      // 仅在已登录时加载用户历史记录
      final authed = context.read<AuthBloc>().state is AuthAuthenticated;
      if (authed) {
        context.read<SettingGenerationBloc>().add(const GetUserHistoriesEvent());
      }
    } catch (_) {}
    
    // 如果设置了自动开始或自动加载历史，这里直接触发
    // 📚 复用模式允许空提示词
    final shouldAutoStart = widget.autoStart == true && 
        ((widget.initialPrompt?.trim().isNotEmpty ?? false) || 
         widget.initialKnowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse);
    if (shouldAutoStart) {
      // 保持中间为"设定"面板，仅后台自动开始生成
      _autoStartGeneration();
    }
    if (widget.autoLoadFirstHistory == true) {
      _autoLoadFirstHistory();
    }

    // 订阅就绪流
    try {
      final bloc = context.read<SettingGenerationBloc>();
      _composeReadySub = bloc.composeReadyStream.listen((info) {
        if (!mounted) {
          _composeReady = info;
          return;
        }
        setState(() => _composeReady = info);
      });
      
      // 🔧 新增：订阅生成状态流
      _composeGeneratingSub = bloc.composeGeneratingStream.listen((generating) {
        if (!mounted) {
          _composeGenerating = generating;
          return;
        }
        setState(() => _composeGenerating = generating);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _composeReadySub?.cancel();
      // 🔧 新增：取消生成状态订阅
      _composeGeneratingSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  // 注意：类未结束，后续方法均属于 _NovelSettingsGeneratorScreenState





  void _autoStartGeneration() {
    // 延迟一小段时间确保BLoC状态已经准备好
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final bloc = context.read<SettingGenerationBloc>();
        final currentState = bloc.state;
        
        // 只要状态中能拿到策略（Ready/InProgress/Completed），就可以发起新的生成
        if (currentState is SettingGenerationReady ||
            currentState is SettingGenerationInProgress ||
            currentState is SettingGenerationCompleted) {
          // 📚 复用模式允许空提示词
          final isReuseMode = widget.initialKnowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse;
          final hasPrompt = widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty;
          
          if (!isReuseMode && !hasPrompt) return; // 非复用模式需要提示词
          
          final initialPrompt = widget.initialPrompt?.trim() ?? '';

          final strategies = currentState is SettingGenerationReady
              ? currentState.strategies
              : currentState is SettingGenerationInProgress
                  ? currentState.strategies
                  : (currentState as SettingGenerationCompleted).strategies;

          // 🔧 修复：正确处理传入的策略参数 - 可能是名称或ID
          String? strategyId;
          if (widget.selectedStrategy != null) {
            // 首先假设传入的是ID，查找对应策略
            try {
              strategies.firstWhere(
                (s) => s.promptTemplateId == widget.selectedStrategy,
              );
              // 找到了，说明传入的是ID
              strategyId = widget.selectedStrategy;
            } catch (e) {
              // 没找到，尝试按名称查找
              try {
                var strategyByName = strategies.firstWhere(
                  (s) => s.name == widget.selectedStrategy,
                );
                // 找到了，使用其ID
                strategyId = strategyByName.promptTemplateId;
              } catch (e2) {
                // 都没找到，使用默认
                strategyId = null;
              }
            }
          }

          final lastStrategy = strategyId ??
              (strategies.isNotEmpty ? strategies.first.promptTemplateId : '');

          String modelConfigId;
          if (widget.selectedModel != null) {
            modelConfigId = widget.selectedModel!.id;
          } else {
            final aiState = context.read<AiConfigBloc>().state;
            final defaultConfig = aiState.defaultConfig ??
                (aiState.validatedConfigs.isNotEmpty ? aiState.validatedConfigs.first : null);
            modelConfigId = defaultConfig?.id ?? '';
          }

          // 确保有有效的策略才开始生成
          if (lastStrategy.isNotEmpty) {
            final selected = widget.selectedModel;
            final bool usePublic = selected != null && selected.isPublic;
            final String? publicProvider = usePublic ? selected.provider : null;
            final String? publicModelId = usePublic ? selected.modelId : null;

            // 📚 构建知识库参数
            final knowledgeBaseMode = widget.initialKnowledgeBaseMode?.name.toUpperCase();
            List<String>? knowledgeBaseIds;
            List<String>? reuseKnowledgeBaseIds;
            List<String>? referenceKnowledgeBaseIds;
            Map<String, List<String>>? knowledgeBaseCategories;
            
            // 📚 混合模式：分别处理复用和参考列表
            if (widget.initialKnowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) {
              if (widget.initialSelectedKnowledgeBases != null && 
                  widget.initialSelectedKnowledgeBases!.isNotEmpty) {
                reuseKnowledgeBaseIds = widget.initialSelectedKnowledgeBases!
                    .map((item) => item.knowledgeBaseId)
                    .toList();
              }
              
              if (widget.initialReferenceKnowledgeBases != null && 
                  widget.initialReferenceKnowledgeBases!.isNotEmpty) {
                referenceKnowledgeBaseIds = widget.initialReferenceKnowledgeBases!
                    .map((item) => item.knowledgeBaseId)
                    .toList();
              }
              
              // 合并分类
              knowledgeBaseCategories = {};
              if (widget.initialSelectedKnowledgeBases != null) {
                for (var item in widget.initialSelectedKnowledgeBases!) {
                  knowledgeBaseCategories[item.knowledgeBaseId] = 
                      item.selectedCategories.map((cat) => cat.value).toList();
                }
              }
              if (widget.initialReferenceKnowledgeBases != null) {
                for (var item in widget.initialReferenceKnowledgeBases!) {
                  knowledgeBaseCategories[item.knowledgeBaseId] = 
                      item.selectedCategories.map((cat) => cat.value).toList();
                }
              }
            } else {
              // 📚 复用或仿写模式：使用通用的knowledgeBaseIds
              knowledgeBaseIds = widget.initialSelectedKnowledgeBases
                  ?.map((item) => item.knowledgeBaseId)
                  .toList();
              knowledgeBaseCategories = widget.initialSelectedKnowledgeBases != null
                  ? Map<String, List<String>>.fromEntries(
                      widget.initialSelectedKnowledgeBases!.map((item) => MapEntry(
                        item.knowledgeBaseId,
                        item.selectedCategories.map((cat) => cat.value).toList(),
                      )),
                    )
                  : null;
            }

            bloc.add(
              StartGenerationEvent(
                initialPrompt: initialPrompt,
                promptTemplateId: lastStrategy,
                novelId: widget.novelId,
                modelConfigId: modelConfigId,
                userId: AppConfig.userId ?? 'current_user',
                usePublicTextModel: usePublic,
                textPhasePublicProvider: publicProvider,
                textPhasePublicModelId: publicModelId,
                // 📚 知识库集成参数
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
          } else {
            // 策略列表为空，等待重新加载
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                _autoStartGeneration();
              }
            });
          }
        } else {
          // 如果策略还没加载完成，再等待一会儿
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _autoStartGeneration();
            }
          });
        }
      }
    });
  }

  void _autoLoadFirstHistory() {
    // 延迟一小段时间确保BLoC状态已经准备好
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final bloc = context.read<SettingGenerationBloc>();
        final currentState = bloc.state;
        
        // 确保策略已经加载完成
        if (currentState is SettingGenerationReady) {
          // 检查是否有历史记录
          if (currentState.sessions.isNotEmpty) {
            // 获取第一条历史记录的ID
            final firstSession = currentState.sessions.first;

            String modelConfigId;
            if (widget.selectedModel != null) {
              modelConfigId = widget.selectedModel!.id;
            } else {
              final aiState = context.read<AiConfigBloc>().state;
              final defaultConfig = aiState.defaultConfig ??
                  (aiState.validatedConfigs.isNotEmpty ? aiState.validatedConfigs.first : null);
              modelConfigId = defaultConfig?.id ?? '';
            }

            // 使用现有的事件加载历史记录详情
            bloc.add(CreateSessionFromHistoryEvent(
              historyId: firstSession.historyId ?? firstSession.sessionId,
              userId: AppConfig.userId ?? 'current_user',
              modelConfigId: modelConfigId,
              editReason: '自动加载历史记录',
            ));
            AppLogger.i('NovelSettingsGeneratorScreen', '自动加载第一条历史记录: ${firstSession.historyId ?? firstSession.sessionId}');
          } else {
            AppLogger.i('NovelSettingsGeneratorScreen', '没有历史记录可加载');
          }
        } else {
          // 如果策略还没加载完成，再等待一会儿
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _autoLoadFirstHistory();
            }
          });
        }
      }
    });
  }

  // ========== 生成入口面板（未使用，保留为未来扩展） ==========
  // ignore: unused_element
  void _openGenerationPanel({String defaultType = 'outline', int defaultChapters = 3}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String source = 'settings'; // settings | prompt
    String genType = defaultType; // outline | chapters
    int chapterCount = defaultChapters;
    final TextEditingController promptCtrl = TextEditingController(text: _lastInitialPrompt ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: const Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  const Text('生成入口', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 来源选择
              Text('来源', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(children: [
                ChoiceChip(
                  label: const Text('基于设定'),
                  selected: source == 'settings',
                  onSelected: (_) => setState(() { source = 'settings'; }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('自由提示词'),
                  selected: source == 'prompt',
                  onSelected: (_) => setState(() { source = 'prompt'; }),
                ),
              ]),
              const SizedBox(height: 12),
              if (source == 'prompt') ...[
                Text('提示词', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: promptCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                    hintText: '例如：写一个硬核悬疑与家庭剧交织的故事骨架',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 类型选择
              Text('生成类型', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(children: [
                ChoiceChip(
                  label: const Text('小说大纲'),
                  selected: genType == 'outline',
                  onSelected: (_) => setState(() { genType = 'outline'; }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('章节/黄金三章'),
                  selected: genType == 'chapters',
                  onSelected: (_) => setState(() { genType = 'chapters'; }),
                ),
              ]),
              const SizedBox(height: 12),
              if (genType == 'chapters') ...[
                Row(
                  children: [
                    const Text('章节数量'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 12,
                        divisions: 11,
                        label: '$chapterCount',
                        value: chapterCount.toDouble(),
                        onChanged: (v) => setState(() { chapterCount = v.round(); }),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('$chapterCount', textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // 关闭面板
                        Navigator.of(ctx).pop();
                        // 切换到结果预览
                        setState(() {
                          _mainSection = 'results';
                        });
                      },
                      child: const Text('开始生成'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用ValueListenableBuilder监听主题变化
    return ValueListenableBuilder<String>(
      valueListenable: WebTheme.variantListenable,
      builder: (context, variant, _) {
        return Theme(
          data: Theme.of(context).copyWith(
            scaffoldBackgroundColor: WebTheme.getBackgroundColor(context),
            cardColor: WebTheme.getSurfaceColor(context),
          ),
          child: Scaffold(
            backgroundColor: WebTheme.getBackgroundColor(context),
            appBar: _buildAppBar(context),
            body: BlocConsumer<SettingGenerationBloc, SettingGenerationState>(
              listener: (context, state) {
                if (state is SettingGenerationError) {
                  // 🔧 修复：只在错误不可恢复或者是致命错误时显示全局消息
                  // 普通生成错误让中间栏处理，不显示全局错误
                  if (!state.isRecoverable && state.message.contains('网络') || state.message.contains('连接')) {
                    TopToast.error(context, state.message);
                  }
                } else if (state is SettingGenerationNodeUpdating) {
                  // 保持原态，不在build中做任何重建操作；如需提示，由具体事件驱动
                } else if (state is SettingGenerationCompleted && (state.message.contains('保存') || state.message.contains('修改完成'))) {
                  TopToast.success(context, state.message);
                  // 对话框已在按钮点击时 pop，这里不再 pop 页面本身
                }
              },
              // 🔧 新增：添加buildWhen条件，避免在节点修改时重建整个界面
              buildWhen: (previous, current) {
                // 🔧 关键修复：节点修改状态变化时不重建主界面，避免历史面板重置
                if (previous is SettingGenerationCompleted && current is SettingGenerationNodeUpdating) {
                  AppLogger.i('NovelSettingsGeneratorScreen', '🚫 阻止节点修改时的界面重建');
                  return false;
                }
                
                if (previous is SettingGenerationNodeUpdating && current is SettingGenerationCompleted) {
                  AppLogger.i('NovelSettingsGeneratorScreen', '🚫 阻止节点修改完成时的界面重建');
                  return false;
                }
                
                // 🔧 只在关键状态变化时才重建界面
                final previousType = previous.runtimeType;
                final currentType = current.runtimeType;
                
                // 允许重建的状态变化
                final allowedStateChanges = [
                  // 初始状态 -> 其他状态
                  'SettingGenerationInitial',
                  // 加载状态 -> 其他状态  
                  'SettingGenerationLoading',
                  // 就绪状态 -> 其他状态
                  'SettingGenerationReady',
                  // 生成中 -> 完成
                  'SettingGenerationInProgress',
                  // 错误状态 -> 其他状态
                  'SettingGenerationError',
                  // 保存状态 -> 其他状态
                  'SettingGenerationSaved',
                ];
                
                bool shouldRebuild = allowedStateChanges.contains(previousType.toString()) || 
                                    allowedStateChanges.contains(currentType.toString());
                
                AppLogger.i('NovelSettingsGeneratorScreen', 
                    '🔄 状态变化检查: $previousType -> $currentType, 是否重建: $shouldRebuild');
                
                return shouldRebuild;
              },
              builder: (context, state) {
                if (state is SettingGenerationInitial) {
                  return _buildLoadingView(state);
                } else if (state is SettingGenerationLoading) {
                  // 🔧 简化：保存快照操作不影响主界面状态，只更新历史记录
                  if (state.message != null && state.message!.contains('保存')) {
                    // 保存操作 - 保持主内容显示，不显示加载覆盖
                    return _buildMainContent(context, state);
                  } else {
                    // 其他加载状态（如初始化、生成等） - 显示全屏加载
                    return _buildLoadingView(state);
                  }
                } else {
                  return _buildMainContent(context, state);
                }
              },
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final bool compactActions = MediaQuery.of(context).size.width < 1100;
    
    return AppBar(
      elevation: 0,
      backgroundColor: WebTheme.getBackgroundColor(context),
      foregroundColor: WebTheme.getTextColor(context),
      title: Row(
        children: [
          Icon(
            Icons.psychology,
            color: WebTheme.getPrimaryColor(context),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '小说设定生成器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: WebTheme.getBorderColor(context),
        ),
      ),
      actions: [
        // 停止生成按钮：仅在生成中可用
        // BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
        //   builder: (context, state) {
        //     bool generating = false;
        //     String? sessionId;
        //     if (state is SettingGenerationInProgress) {
        //       generating = state.isGenerating;
        //       sessionId = state.activeSessionId;
        //     } else if (state is SettingGenerationNodeUpdating) {
        //       // 节点修改进行中也显示“停止生成”按钮
        //       generating = state.isUpdating;
        //       sessionId = state.activeSessionId;
        //     }
        //     return _buildHeaderButton(
        //       icon: Icons.stop_circle_outlined,
        //       label: '停止生成',
        //       onPressed: generating && sessionId != null
        //           ? () {
        //               context.read<SettingGenerationBloc>().add(
        //                 CancelSessionEvent(sessionId!),
        //               );
        //             }
        //           : null,
        //       enabled: generating && sessionId != null,
        //     );
        //   },
        // ),
        const SizedBox(width: 8),
        BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
          // 仅当 canSave 状态变化时才重建，避免频繁 build
          buildWhen: (previous, current) {
            bool _canSave(SettingGenerationState s) =>
                s is SettingGenerationCompleted ||
                s is SettingGenerationNodeUpdating ||
                (s is SettingGenerationInProgress &&
                    s.activeSession.rootNodes.isNotEmpty);

            return _canSave(previous) != _canSave(current);
          },
          builder: (context, state) {
            final canSave = state is SettingGenerationCompleted ||
                state is SettingGenerationNodeUpdating ||
                (state is SettingGenerationInProgress &&
                    state.activeSession.rootNodes.isNotEmpty);

            // 仅当 buildWhen 返回 true 时才会进入这里，日志也只会打印一次
            AppLogger.i('SaveButton',
                '保存按钮状态变更: canSave=$canSave, novelId=${widget.novelId ?? "null"}');

            return Row(
              children: [
                _buildHeaderButton(
                  icon: Icons.save,
                  label: '保存设定',
                  onPressed: canSave
                      ? () {
                          AppLogger.i(
                              'SaveButton', '点击保存按钮，novelId=${widget.novelId}');

                          if (widget.novelId != null) {
                            // 场景1: 有明确的小说ID，直接保存
                            context.read<SettingGenerationBloc>().add(
                              SaveGeneratedSettingsEvent(widget.novelId!),
                            );
                          } else {
                            // 场景2: 没有小说ID（新建小说场景），显示保存选项对话框
                            _showSaveOptionsDialog(context, state);
                          }
                        }
                      : null,
                  enabled: canSave,
                  compact: compactActions,
                ),
                // const SizedBox(width: 8),
                // _buildHeaderButton(
                //   icon: Icons.update,
                //   label: '更新历史',
                //   onPressed: canSave
                //       ? () {
                //           AppLogger.i('UpdateHistoryButton', '点击更新历史按钮');
                //           context.read<SettingGenerationBloc>().add(
                //             SaveGeneratedSettingsEvent(widget.novelId, updateExisting: true),
                //           );
                //         }
                //       : null,
                //   enabled: canSave,
                // ),
              ],
            );
          },
        ),
        // const SizedBox(width: 8),
        // _buildHeaderButton(
        //   icon: Icons.description,
        //   label: '生成大纲',
        //   onPressed: () {
        //     // 从设定生成BLoC获取当前活跃会话ID，作为settingSessionId传入
        //     String? sid;
        //     final s = context.read<SettingGenerationBloc>().state;
        //     if (s is SettingGenerationInProgress) {
        //       sid = s.activeSessionId;
        //     } else if (s is SettingGenerationReady) {
        //       sid = s.activeSessionId;
        //     } else if (s is SettingGenerationCompleted) {
        //       sid = s.activeSessionId;
        //     }
        //     showGoldenThreeChaptersDialog(
        //       context,
        //       novel: null,
        //       settings: const [],
        //       settingGroups: const [],
        //       snippets: const [],
        //       initialSelectedUnifiedModel: widget.selectedModel,
        //       settingSessionId: sid,
        //       onStarted: () => setState(() => _mainSection = 'results'),
        //     );
        //   },
        //   enabled: true,
        // ),
        const SizedBox(width: 8),
        _buildHeaderButton(
          icon: Icons.book,
          label: '生成黄金三章',
          onPressed: () {
            // 从设定生成BLoC获取当前活跃会话ID，作为settingSessionId传入
            String? sid;
            final s = context.read<SettingGenerationBloc>().state;
            if (s is SettingGenerationInProgress) {
              sid = s.activeSessionId;
            } else if (s is SettingGenerationReady) {
              sid = s.activeSessionId;
            } else if (s is SettingGenerationCompleted) {
              sid = s.activeSessionId;
            }
            
            showGoldenThreeChaptersDialog(
              context,
              novel: null,
              settings: const [],
              settingGroups: const [],
              snippets: const [],
              initialSelectedUnifiedModel: widget.selectedModel,
              settingSessionId: sid,
              onStarted: () => setState(() {
                _mainSection = 'results';
                // 🔧 关键：显式标记"黄金三章生成中"，并清空就绪标志
                _composeGenerating = true;
                _composeReady = null;
              }),
            );
          },
          enabled: true,
          variant: 'primary',
          compact: compactActions,
        ),
        const SizedBox(width: 8),
        // 根据会话状态决定是否允许开始写作
        _buildHeaderButton(
          icon: Icons.play_arrow,
          label: '开始写作',
          onPressed: () async {
            try {
              // 🔧 修改逻辑：支持黄金三章标志为空或者为true时开始创作
              final streamInfo = _composeReady; // 从stream获取的信息
              ComposeReadyInfo? stateInfo; // 从BLoC状态获取的信息
              
              // 尝试从BLoC状态获取composeReady信息
              final s = context.read<SettingGenerationBloc>().state;
              if (s is SettingGenerationInProgress) {
                stateInfo = s.composeReady;
              } else if (s is SettingGenerationCompleted) {
                stateInfo = s.composeReady;
              } else if (s is SettingGenerationReady) {
                stateInfo = s.composeReady;
              }
              
              // 优先使用stream信息，其次使用状态信息
              final info = streamInfo ?? stateInfo;
              
              // 🔧 新逻辑：区分黄金三章生成和历史记录情况
              if (_composeGenerating) {
                // 正在生成黄金三章：必须等待后端ready信号
                if (info == null || !info.ready) {
                  TopToast.error(context, '黄金三章尚未就绪，请等待生成完成…');
                  return;
                }
              } else {
                // 不在生成状态（历史记录等）：只在明确标记为not ready时才阻止
                if (info != null && !info.ready) {
                  TopToast.error(context, '黄金三章尚未就绪：${info.reason}');
                  return;
                }
              }
              
              // info为null（历史记录等情况）或ready为true时都可以继续
              // 尝试从 BLoC 拿当前活跃 sessionId
              String? sessionId;
              if (s is SettingGenerationInProgress) {
                sessionId = s.activeSessionId;
              } else if (s is SettingGenerationCompleted) {
                sessionId = s.activeSessionId;
              }
              final repo = context.read<SettingGenerationRepository>();
              // 统一 novelId 选择策略：composeReady → activeSession（历史会话不回退到props）
              String? novelIdToUse;
              try {
                // 🔧 修复：安全地访问info.novelId
                if (info != null && info.novelId.isNotEmpty) {
                  novelIdToUse = info.novelId;
                }
                if ((novelIdToUse == null || novelIdToUse.isEmpty)) {
                  if (s is SettingGenerationInProgress) {
                    novelIdToUse = s.activeSession.novelId;
                  } else if (s is SettingGenerationCompleted) {
                    novelIdToUse = s.activeSession.novelId;
                  }
                }
                // 历史会话下 novelId 由后端生成/绑定，不再回退到 props.novelId
              } catch (_) {}
              try {
                AppLogger.i('NovelSettingsGenerator', 'StartWriting: sessionId=' + (sessionId ?? 'null') + ', novelIdToUse=' + (novelIdToUse ?? 'null'));
              } catch (_) {}
              final nid = await repo.startWriting(
                sessionId: sessionId,
                novelId: novelIdToUse,
                historyId: null,
              );
              if (nid == null || nid.isEmpty) {
                TopToast.error(context, '开始写作失败：未返回小说ID');
                return;
              }
              // 刷新小说列表并跳转编辑器
              context.read<NovelListBloc>().add(RefreshNovels());
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EditorScreen(
                  novel: NovelSummary(
                    id: nid,
                    title: '未命名小说',
                    coverUrl: '',
                    lastEditTime: DateTime.now(),
                    serverUpdatedAt: DateTime.now(),
                    wordCount: 0,
                    readTime: 0,
                    version: 1,
                    completionPercentage: 0,
                    contributors: const [],
                    actCount: 0,
                    chapterCount: 0,
                    sceneCount: 0,
                  ),
                ),
              ));
            } catch (e) {
              TopToast.error(context, '开始写作异常：$e');
            }
          },
          // 🔧 修改动态控制逻辑：考虑黄金三章生成状态
          enabled: () {
            final streamInfo = _composeReady; // 从stream获取的信息
            ComposeReadyInfo? stateInfo; // 从BLoC状态获取的信息
            
            // 尝试从BLoC状态获取composeReady信息
            final state = context.watch<SettingGenerationBloc>().state;
            if (state is SettingGenerationInProgress) {
              stateInfo = state.composeReady;
            } else if (state is SettingGenerationCompleted) {
              stateInfo = state.composeReady;
            } else if (state is SettingGenerationReady) {
              stateInfo = state.composeReady;
            }
            
            // 优先使用stream信息，其次使用状态信息
            final info = streamInfo ?? stateInfo;
            
            // 🔧 关键逻辑：区分黄金三章生成和历史记录情况
            if (_composeGenerating) {
              // 正在生成黄金三章：必须等待后端ready信号
              return false;
            } else {
              // 不在生成状态（历史记录等）：info为null或ready为true时都可用
              if (info != null && !info.ready) {
                return false; // 明确标记为not ready时禁用
              }
              
              // 确保有活跃会话
              String? sid;
              if (state is SettingGenerationInProgress) sid = state.activeSessionId;
              else if (state is SettingGenerationCompleted) sid = state.activeSessionId;
              
              return sid != null && sid.isNotEmpty;
            }
          }(),
          variant: 'primary',
          compact: compactActions,
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool enabled,
    String variant = 'outline',
    bool compact = false,
  }) {
    
    if (variant == 'primary') {
      return ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 16),
        label: compact ? const SizedBox.shrink() : Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        style: WebTheme.getPrimaryButtonStyle(context),
      );
    }
    
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16),
      label: compact ? const SizedBox.shrink() : Text(
        label,
        style: const TextStyle(fontSize: 14),
      ),
      style: WebTheme.getSecondaryButtonStyle(context),
    );
  }

  Widget _buildLoadingView(SettingGenerationState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            state is SettingGenerationLoading && state.message != null
                ? state.message!
                : '正在初始化...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }



  Widget _buildMainContent(BuildContext context, SettingGenerationState state) {
    
    return Container(
      color: WebTheme.getBackgroundColor(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 响应式布局：桌面/平板/手机
          final screenWidth = constraints.maxWidth;
          
          // 移动端布局 (< 768px)
          if (screenWidth < 768) {
            return _buildMobileLayout(context, state);
          }
          
          // 平板端布局 (768px - 1024px)
          if (screenWidth < 1024) {
            return _buildTabletLayout(context, state);
          }
          
          // 桌面端布局 (>= 1024px)
          return _buildDesktopLayout(context, state, screenWidth);
        },
      ),
    );
  }
  
  Widget _buildDesktopLayout(BuildContext context, SettingGenerationState state, double screenWidth) {
    // 新的布局比例：左侧历史记录1.5个单位，创作控制台2个单位，中间6个单位，右侧2.5个单位（总12个单位）
    final totalWidth = screenWidth;
    final historyWidth = (totalWidth * 1.5 / 12); // 历史记录面板
    final controlWidth = (totalWidth * 2 / 12); // 创作控制台面板  
    final centerWidth = (totalWidth * 6 / 12); // 中间内容区域
    final rightWidth = (totalWidth * 2.5 / 12); // 右侧面板
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch, // 让所有面板高度一致
      children: [
        // 最左侧 - 历史记录面板
        Container(
          width: historyWidth,
          color: WebTheme.getSurfaceColor(context),
          child: const HistoryPanelWidget(),
        ),
        // 左侧 - 创作控制台面板
        Container(
          width: controlWidth,
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context),
            border: Border(
              left: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
            ),
          ),
          child: GenerationControlPanel(
            initialPrompt: widget.initialPrompt,
            selectedModel: widget.selectedModel,
            initialStrategy: widget.selectedStrategy,
            // 📚 传递知识库参数
            initialKnowledgeBaseMode: widget.initialKnowledgeBaseMode,
            initialSelectedKnowledgeBases: widget.initialSelectedKnowledgeBases,
            initialReferenceKnowledgeBases: widget.initialReferenceKnowledgeBases,
            onGenerationStart: (prompt, strategy, modelConfigId) {
              setState(() {
                _lastInitialPrompt = prompt;
                _lastStrategy = strategy;
                _lastModelConfigId = modelConfigId;
              });
            },
          ),
        ),
        // 中间主内容区 - 无缝连接
        Container(
          width: centerWidth,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
              right: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMainHeader(),
              // 超时/状态提示条
              if (_mainSection == 'settings') _buildStatusBanner(),
              Expanded(
                child: Container(
                  color: WebTheme.getBackgroundColor(context),
                  child: IndexedStack(
                    index: _mainSection == 'settings' ? 0 : 1,
                    children: [
                      SettingsTreeWidget(
                        lastInitialPrompt: _lastInitialPrompt,
                        lastStrategy: _lastStrategy,
                        lastModelConfigId: _lastModelConfigId,
                        novelId: widget.novelId,
                        userId: AppConfig.userId,
                      ),
                      _ComposeResultsBridge(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 右侧编辑面板 - 无缝连接，隐藏微调区域
        Container(
          width: rightWidth,
          color: WebTheme.getSurfaceColor(context),
          child: _mainSection == 'settings'
              ? EditorPanelWidget(novelId: widget.novelId)
              : Container(), // 隐藏黄金三章右侧微调区域
        ),
      ],
    );
  }
  
  Widget _buildTabletLayout(BuildContext context, SettingGenerationState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 历史记录面板 - 平板布局
        Expanded(
          flex: 1, // 10%
          child: Container(
            color: WebTheme.getSurfaceColor(context),
            child: const HistoryPanelWidget(),
          ),
        ),
        // 创作控制台面板 - 平板布局
        Expanded(
          flex: 2, // 20%
          child: Container(
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              border: Border(
                left: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
              ),
            ),
            child: GenerationControlPanel(
              initialPrompt: widget.initialPrompt,
              selectedModel: widget.selectedModel,
              initialStrategy: widget.selectedStrategy,
              // 📚 传递知识库参数
              initialKnowledgeBaseMode: widget.initialKnowledgeBaseMode,
              initialSelectedKnowledgeBases: widget.initialSelectedKnowledgeBases,
              initialReferenceKnowledgeBases: widget.initialReferenceKnowledgeBases,
              onGenerationStart: (prompt, strategy, modelConfigId) {
                setState(() {
                  _lastInitialPrompt = prompt;
                  _lastStrategy = strategy;
                  _lastModelConfigId = modelConfigId;
                });
              },
            ),
          ),
        ),
        // 中间内容区 - 平板占主要空间
        Expanded(
          flex: 6, // 60%
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
                right: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMainHeader(),
                if (_mainSection == 'settings') _buildStatusBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _mainSection == 'settings' ? 0 : 1,
                    children: [
                      SettingsTreeWidget(
                        lastInitialPrompt: _lastInitialPrompt,
                        lastStrategy: _lastStrategy,
                        lastModelConfigId: _lastModelConfigId,
                        novelId: widget.novelId,
                        userId: AppConfig.userId,
                      ),
                      _ComposeResultsBridge(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 右侧面板 - 平板布局保持紧凑
        Expanded(
          flex: 1, // 10%
          child: Container(
            color: WebTheme.getSurfaceColor(context),
            child: _mainSection == 'settings'
                ? EditorPanelWidget(novelId: widget.novelId)
                : Container(), // 隐藏微调区域
          ),
        ),
      ],
    );
  }
  
  Widget _buildMobileLayout(BuildContext context, SettingGenerationState state) {
    // 移动端使用垂直布局
    return Column(
      children: [
        _buildMainHeader(),
        Expanded(
          child: IndexedStack(
            index: _mainSection == 'settings' ? 0 : 1,
            children: [
              SettingsTreeWidget(
                lastInitialPrompt: _lastInitialPrompt,
                lastStrategy: _lastStrategy,
                lastModelConfigId: _lastModelConfigId,
                novelId: widget.novelId,
                userId: AppConfig.userId,
              ),
              _ComposeResultsBridge(),
            ],
          ),
        ),
      ],
    );
  }

  // 统一的顶部状态提示条（用于请求超时等非致命状态）
  Widget _buildStatusBanner() {
    return BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
      buildWhen: (prev, curr) {
        String? op(Object s) {
          if (s is SettingGenerationInProgress) return s.currentOperation;
          if (s is SettingGenerationCompleted) return null;
          if (s is SettingGenerationReady) return null;
          return null;
        }
        return op(prev) != op(curr);
      },
      builder: (context, state) {
        String? operation;
        if (state is SettingGenerationInProgress) {
          operation = state.currentOperation;
        }
        if (operation == null || operation.trim().isEmpty) {
          return const SizedBox(height: 0);
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context),
            border: Border(
              bottom: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: WebTheme.getPrimaryColor(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  operation,
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          // 标题
          Text(
            '设定总览',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(width: 24),
          // 控件靠左显示 - 不使用Expanded和Flexible
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: WebTheme.getBackgroundColor(context),
              border: Border.all(color: WebTheme.getBorderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMainSectionButton('设定', 'settings', _mainSection == 'settings'),
                _buildMainSectionButton('结果预览', 'results', _mainSection == 'results'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildViewModeToggle(),
          // 用Spacer占据剩余空间，让控件保持靠左
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
      builder: (context, state) {
        String currentMode = 'compact';
        if (state is SettingGenerationReady) {
          currentMode = state.viewMode;
        } else if (state is SettingGenerationInProgress) {
          currentMode = state.viewMode;
        } else if (state is SettingGenerationCompleted) {
          currentMode = state.viewMode;
        }

        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: WebTheme.getBackgroundColor(context),
            border: Border.all(color: WebTheme.getBorderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildViewModeButton(
                icon: Icons.view_list,
                mode: 'compact',
                label: '紧凑视图',
                isSelected: currentMode == 'compact',
              ),
              _buildViewModeButton(
                icon: Icons.view_module,
                mode: 'detailed',
                label: '详细视图',
                isSelected: currentMode == 'detailed',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required String mode,
    required String label,
    required bool isSelected,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () {
          context.read<SettingGenerationBloc>().add(
            ToggleViewModeEvent(mode),
          );
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? WebTheme.getSurfaceColor(context)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected 
                ? WebTheme.getTextColor(context)
                : WebTheme.getSecondaryTextColor(context),
          ),
        ),
      ),
    );
  }

  // ========== 新增：主区域切换按钮 ==========
  Widget _buildMainSectionButton(String label, String value, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _mainSection = value;
        });
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? WebTheme.getSurfaceColor(context)
              : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            color: isSelected 
                ? WebTheme.getTextColor(context)
                : WebTheme.getSecondaryTextColor(context),
          ),
        ),
      ),
    );
  }


  /// 显示保存选项对话框
  /// 
  /// 当没有明确的小说ID时，提供两种快照保存选项：
  /// 1. 保存为独立快照（不关联任何小说）
  /// 2. 关联到现有小说并保存
  void _showSaveOptionsDialog(BuildContext context, SettingGenerationState state) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存设定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请选择如何保存生成的设定：'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Text(
                '💡 设定将被保存为历史记录快照，可用于版本管理和后续编辑',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _updateCurrentHistory(context, state);
            },
            child: const Text('更新当前历史'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _saveAsIndependentSnapshot(context, state);
            },
            child: const Text('保存为独立快照'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showSelectNovelDialog(context, state);
            },
            child: const Text('关联到现有小说'),
          ),
        ],
      ),
    );
  }

  /// 更新当前历史记录
  /// 
  /// 直接更新当前会话对应的历史记录，不创建新的历史记录
  void _updateCurrentHistory(BuildContext context, SettingGenerationState state) {
    AppLogger.i('SaveButton', '更新当前历史记录');
    
    // 使用当前的novelId和updateExisting=true来更新历史记录
    context.read<SettingGenerationBloc>().add(
      SaveGeneratedSettingsEvent(widget.novelId, updateExisting: true),
    );
  }

  /// 保存为独立快照
  /// 
  /// 不关联任何小说，直接保存为独立的历史记录快照
  void _saveAsIndependentSnapshot(BuildContext context, SettingGenerationState state) {
    AppLogger.i('SaveButton', '保存为独立快照');
    
    // 传入null作为novelId，表示保存为独立快照
    context.read<SettingGenerationBloc>().add(
      SaveGeneratedSettingsEvent(null),
    );
  }

  /// 显示选择现有小说对话框
  void _showSelectNovelDialog(BuildContext context, SettingGenerationState state) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关联到现有小说'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请选择要关联的小说：'),
            const SizedBox(height: 16),
            Container(
              height: 300,
              width: double.maxFinite,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.library_books, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      '小说列表功能正在开发中',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Text(
                      '暂时请使用"保存为独立快照"功能',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // TODO: 实现关联到选中小说的逻辑
              TopToast.info(context, '小说列表功能开发中，请先使用独立快照功能');
            },
            child: const Text('关联并保存'),
          ),
        ],
      ),
    );
  }


}

// ========== 新增：结果预览的微调面板（右侧） ==========
class _ResultsTuningPanel extends StatefulWidget {
  final bool isGeneratingOutline;
  final bool isGeneratingChapters;
  final void Function(String prompt) onRefine;
  final VoidCallback onRegenerate;
  final void Function(int n) onAppendChapters;

  const _ResultsTuningPanel({
    Key? key,
    required this.isGeneratingOutline,
    required this.isGeneratingChapters,
    required this.onRefine,
    required this.onRegenerate,
    required this.onAppendChapters,
  }) : super(key: key);

  @override
  State<_ResultsTuningPanel> createState() => _ResultsTuningPanelState();
}

class _ResultsTuningPanelState extends State<_ResultsTuningPanel> {
  final TextEditingController _refineCtrl = TextEditingController();
  int _appendCount = 2;

  @override
  void dispose() {
    _refineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.tune, size: 20, color: const Color(0xFF6366F1)),
              const SizedBox(width: 8),
              const Text('结果微调', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _refineCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：节奏更快、强化主角动机、加重悬疑氛围……',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _refineCtrl.text.trim().isEmpty ? null : () => widget.onRefine(_refineCtrl.text.trim()),
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('应用微调'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onRegenerate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('整体重生成'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  const Text('追加章节'),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$_appendCount',
                      value: _appendCount.toDouble(),
                      onChanged: (v) => setState(() { _appendCount = v.round(); }),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => widget.onAppendChapters(_appendCount),
                    child: const Text('追加'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 简单的章节占位模型
// 已移除旧的章节占位模型，预览改为使用 ChapterPreviewData
