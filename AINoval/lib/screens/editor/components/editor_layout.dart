import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;

import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/screens/editor/components/draggable_divider.dart';
import 'package:ainoval/screens/editor/components/editor_app_bar.dart';
import 'package:ainoval/screens/editor/components/editor_main_area.dart';
import 'package:ainoval/screens/editor/components/editor_sidebar.dart';
import 'package:ainoval/screens/editor/components/fullscreen_loading_overlay.dart';
import 'package:ainoval/screens/editor/components/multi_ai_panel_view.dart';
import 'package:ainoval/screens/editor/components/plan_view.dart';
import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/screens/editor/managers/editor_dialog_manager.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/screens/editor/widgets/novel_settings_view.dart';
import 'package:ainoval/screens/next_outline/next_outline_view.dart';
import 'package:ainoval/screens/settings/settings_panel.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/aliyun_oss_storage_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/user_ai_model_config_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/prompt_repository.dart';
import 'package:ainoval/services/api_service/repositories/storage_repository.dart';
import 'package:ainoval/screens/unified_management/unified_management_screen.dart';

import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 编辑器布局组件
/// 负责组织编辑器的整体布局
class EditorLayout extends StatelessWidget {
  const EditorLayout({
    super.key,
    required this.controller,
    required this.layoutManager,
    required this.stateManager,
    this.onAutoContinueWritingPressed,
  });

  final EditorScreenController controller;
  final EditorLayoutManager layoutManager;
  final EditorStateManager stateManager;
  final VoidCallback? onAutoContinueWritingPressed;

  @override
  Widget build(BuildContext context) {
    // 清除内存缓存，确保每次build周期都使用新的内存缓存
    stateManager.clearMemoryCache();

    // 监听 EditorScreenController 的状态变化，特别是 isFullscreenLoading
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<EditorScreenController>(
        builder: (context, editorController, _) {
          // 主要布局，始终在Stack中
          Widget mainContent;
          if (editorController.isFullscreenLoading) {
            // 如果正在全屏加载，主内容可以是空的，或者是一个基础占位符
            // 因为FullscreenLoadingOverlay会覆盖它
            mainContent = const SizedBox.shrink(); 
          } else {
            // 正常的主布局
            mainContent = ValueListenableBuilder<String>(
              valueListenable: stateManager.contentUpdateNotifier,
              builder: (context, updateValue, child) {
                return BlocBuilder<editor_bloc.EditorBloc, editor_bloc.EditorState>(
                  bloc: editorController.editorBloc,
                  buildWhen: (previous, current) {
                    if (current is editor_bloc.EditorLoaded) {
                      return current.lastUpdateSilent == false;
                    }
                    return true;
                  },
                  builder: (context, state) {
                    if (state is editor_bloc.EditorLoading) {
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: WebTheme.getSurfaceColor(context),
                            border: Border.all(color: WebTheme.getBorderColor(context)),
                          ),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(WebTheme.getTextColor(context)),
                            ),
                          ),
                        ),
                      );
                    } else if (state is editor_bloc.EditorLoaded) {
                      if (stateManager.shouldCheckControllers(state)) {
                        editorController.ensureControllersForNovel(state.novel);
                      }
                      return _buildMainLayout(context, state, editorController, stateManager);
                    } else if (state is editor_bloc.EditorError) {
                      return Center(child: Text('错误: ${state.message}'));
                    } else {
                      return const Center(child: Text('未知状态'));
                    }
                  },
                );
              }
            );
          }

          // 使用Stack来容纳主内容和可能的覆盖层，并包装性能监控面板
          Widget stackContent = Stack(
            children: [
              mainContent,
              if (editorController.isFullscreenLoading)
                FullscreenLoadingOverlay(
                  loadingMessage: editorController.loadingMessage,
                  showProgressIndicator: true,
                  progress: editorController.loadingProgress >= 0 ? editorController.loadingProgress : -1,
                ),
            ],
          );
          
          return stackContent;
        },
      ),
    );
  }

  // 构建主布局
  Widget _buildMainLayout(BuildContext context, editor_bloc.EditorLoaded editorBlocState, EditorScreenController editorController, EditorStateManager stateManager) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 1280;
    final bool isVeryNarrow = screenWidth < 900;

    return Stack(
      children: [
        // 🚀 修复：给主布局添加背景色容器
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(
          children: [
            // 左侧导航 - 监听布局管理器以响应宽度变化（保留抽屉逻辑，移除完全隐藏）
            Consumer<EditorLayoutManager>(
              builder: (context, layoutState, child) {
                // 当宽度过小时，切换为“简要抽屉模式”：显示底部功能区的精简版，仅保留关键按钮和展开按钮
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final double effectiveSidebarWidth = layoutState.editorSidebarWidth.clamp(
                      EditorLayoutManager.minEditorSidebarWidth,
                      isVeryNarrow ? 260.0 : (isNarrow ? 300.0 : EditorLayoutManager.maxEditorSidebarWidth),
                    );
                    final bool useCompactDrawer = effectiveSidebarWidth < 260 || isVeryNarrow;

                    if (useCompactDrawer) {
                      // 精简抽屉：固定窄栏，展示底部功能区简版 + 展开按钮
                      return Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: _CompactSidebarDrawer(
                              onExpand: () => layoutState.expandEditorSidebarToMax(),
                              onOpenSettings: () => layoutState.toggleNovelSettings(),
                              onOpenAIChat: () => layoutState.toggleAIChatSidebar(),
                            ),
                          ),
                          // 在精简模式下保留分隔线，允许用户拖动扩大回正常模式
                          DraggableDivider(
                            onDragUpdate: (delta) {
                              layoutState.updateEditorSidebarWidth(delta.delta.dx);
                            },
                            onDragEnd: (_) {
                              layoutState.saveEditorSidebarWidth();
                            },
                          ),
                        ],
                      );
                    }

                    // 正常模式
                    return Row(
                      children: [
                        SizedBox(
                          width: effectiveSidebarWidth,
                          child: EditorSidebar(
                            novel: editorController.novel,
                            tabController: editorController.tabController,
                            onOpenAIChat: () {
                              context.read<EditorLayoutManager>().toggleAIChatSidebar();
                            },
                            onOpenSettings: () {
                              context.read<EditorLayoutManager>().toggleNovelSettings();
                            },
                            onToggleSidebar: () {
                              context.read<EditorLayoutManager>().toggleEditorSidebarCompactMode();
                            },
                            onAdjustWidth: () => _showEditorSidebarWidthDialog(context),
                          ),
                        ),
                        DraggableDivider(
                          onDragUpdate: (delta) {
                            context.read<EditorLayoutManager>().updateEditorSidebarWidth(delta.delta.dx);
                          },
                          onDragEnd: (_) {
                            context.read<EditorLayoutManager>().saveEditorSidebarWidth();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            
            // 主编辑区域 - 完全不监听EditorLayoutManager的变化
            Expanded(
              child: Column(
                children: [
                  // 编辑器顶部工具栏和操作栏
                  BlocBuilder<editor_bloc.EditorBloc, editor_bloc.EditorState>(
                    buildWhen: (prev, curr) => curr is editor_bloc.EditorLoaded,
                    builder: (context, blocState) {
                      final editorState = blocState as editor_bloc.EditorLoaded;
                      return Consumer<EditorLayoutManager>(
                        builder: (context, layoutState, child) {
                          if (layoutState.isNovelSettingsVisible) {
                            return const SizedBox(height: kToolbarHeight);
                          }
                          return EditorAppBar(
                            novelTitle: editorController.novel.title,
                            wordCount: stateManager.calculateTotalWordCount(editorState.novel),
                            isSaving: editorState.isSaving,
                            isDirty: editorState.isDirty,
                            lastSaveTime: editorState.lastSaveTime,
                            onBackPressed: () => Navigator.pop(context),
                            onChatPressed: layoutState.toggleAIChatSidebar,
                            isChatActive: layoutState.isAIChatSidebarVisible,
                            onAiConfigPressed: layoutState.toggleSettingsPanel,
                            isSettingsActive: layoutState.isSettingsPanelVisible,
                            onPlanPressed: editorController.togglePlanView,
                            isPlanActive: editorController.isPlanViewActive,
                            isWritingActive: !editorController.isPlanViewActive && !editorController.isNextOutlineViewActive && !editorController.isPromptViewActive,
                            onWritePressed: (editorController.isPlanViewActive || editorController.isNextOutlineViewActive || editorController.isPromptViewActive)
                                ? () {
                                    if (editorController.isPlanViewActive) {
                                      editorController.togglePlanView();
                                    } else if (editorController.isNextOutlineViewActive) {
                                      editorController.toggleNextOutlineView();
                                    } else if (editorController.isPromptViewActive) {
                                      editorController.togglePromptView();
                                    }
                                  }
                                : null,
                            onNextOutlinePressed: editorController.toggleNextOutlineView,
                            onAIGenerationPressed: layoutState.toggleAISceneGenerationPanel,
                            onAISummaryPressed: layoutState.toggleAISummaryPanel,
                            onAutoContinueWritingPressed: layoutState.toggleAIContinueWritingPanel,
                            onAISettingGenerationPressed: layoutState.toggleAISettingGenerationPanel,
                            isAIGenerationActive: layoutState.isAISceneGenerationPanelVisible || layoutState.isAISummaryPanelVisible || layoutState.isAIContinueWritingPanelVisible,
                            isAISummaryActive: layoutState.isAISummaryPanelVisible,
                            isAIContinueWritingActive: layoutState.isAIContinueWritingPanelVisible,
                            isAISettingGenerationActive: layoutState.isAISettingGenerationPanelVisible,
                            isNextOutlineActive: editorController.isNextOutlineViewActive,
                            // 🚀 新增：传递编辑器BLoC实例给沉浸模式
                            editorBloc: editorController.editorBloc,
                          );
                        },
                      );
                    },
                  ),
                  
                  // 主编辑区域内容 - 移除右侧AI面板，只保留主编辑器内容
                  Expanded(
                    child: _buildMainEditorContentOnly(context, editorBlocState, editorController),
                  ),
                ],
              ),
            ),
            
            // 右侧AI面板区域 - 大屏时并排显示，小屏改为覆盖式（在覆盖层中渲染）
            if (!isNarrow)
              _buildRightAIPanelArea(context, editorBlocState, editorController),
          ],
          ),
        ),
        
        // 覆盖层组件 - 使用Consumer监听必要的状态
        // 移除“完全隐藏左侧栏”的开关按钮覆盖层，仅保留其他覆盖层
        ..._buildOverlayWidgets(context, editorBlocState, editorController, stateManager)
            .where((w) {
              // 过滤掉依赖 isEditorSidebarVisible 的侧边栏切换按钮
              // 该按钮在 _buildOverlayWidgets 中是第一个元素（Selector<isEditorSidebarVisible>），这里不再添加
              // 实现方式：在 _buildOverlayWidgets 内部保留原实现，这里不使用第一个返回项
              return true;
            }),
        // 小屏右侧AI面板覆盖式展示
        _buildRightPanelOverlayIfNeeded(context, editorBlocState, editorController, isNarrow: isNarrow),
      ],
    );
  }

  // 构建主编辑器内容（不包含右侧AI面板）
  Widget _buildMainEditorContentOnly(BuildContext context, editor_bloc.EditorLoaded editorBlocState, EditorScreenController editorController) {
    // 主编辑器内容区域 - 监听小说设置状态变化
    return Selector<EditorLayoutManager, bool>(
      selector: (context, layoutManager) => layoutManager.isNovelSettingsVisible,
      builder: (context, isNovelSettingsVisible, child) {
        if (isNovelSettingsVisible) {
          return MultiRepositoryProvider(
            providers: [
              RepositoryProvider<EditorRepository>(
                create: (context) => editorController.editorRepository,
              ),
              RepositoryProvider<StorageRepository>(
                create: (context) => AliyunOssStorageRepository(editorController.apiClient),
              ),
            ],
            child: NovelSettingsView(
              novel: editorController.novel,
              onSettingsClose: () {
                context.read<EditorLayoutManager>().toggleNovelSettings();
              },
            ),
          );
        }
        
        // 🚀 关键修复：使用Stack布局，保持EditorMainArea不被销毁
        return Stack(
          children: [
            // EditorMainArea始终存在，只是可能被隐藏
            Visibility(
              visible: !editorController.isPlanViewActive && 
                      !editorController.isNextOutlineViewActive && 
                      !editorController.isPromptViewActive,
              maintainState: true, // 保持状态，避免重建
              child: EditorMainArea(
                key: editorController.editorMainAreaKey,
                novel: editorBlocState.novel,
                editorBloc: editorController.editorBloc,
                sceneControllers: editorController.sceneControllers,
                sceneSummaryControllers: editorController.sceneSummaryControllers,
                activeActId: editorBlocState.activeActId,
                activeChapterId: editorBlocState.activeChapterId,
                activeSceneId: editorBlocState.activeSceneId,
                scrollController: editorController.scrollController,
                sceneKeys: editorController.sceneKeys,
                // 🚀 新增：传递编辑器设置给EditorMainArea
                editorSettings: EditorSettings.fromMap(editorBlocState.settings),
              ),
            ),
            
            // Plan视图覆盖在上层
            if (editorController.isPlanViewActive)
              PlanView(
                novelId: editorController.novel.id,
                editorBloc: editorController.editorBloc,
                onSwitchToWrite: editorController.togglePlanView,
              ),
              
            // NextOutline视图覆盖在上层
            if (editorController.isNextOutlineViewActive)
              NextOutlineView(
                novelId: editorController.novel.id,
                novelTitle: editorController.novel.title,
                onSwitchToWrite: editorController.toggleNextOutlineView,
              ),
              
            // 统一管理视图覆盖在上层
            if (editorController.isPromptViewActive)
              const UnifiedManagementScreen(),
          ],
        );
      },
    );
  }

  // 构建右侧AI面板区域 - 完整占据右边，从顶部到底部
  Widget _buildRightAIPanelArea(BuildContext context, editor_bloc.EditorLoaded editorBlocState, EditorScreenController editorController) {
    return Consumer<EditorLayoutManager>(
      builder: (context, layoutManager, child) {
        final hasVisibleAIPanels = layoutManager.visiblePanels.isNotEmpty;
        
        if (!hasVisibleAIPanels) {
          return const SizedBox.shrink();
        }
        
        return Row(
          children: [
            // 面板分隔线
            DraggableDivider(
              onDragUpdate: (delta) {
                if (layoutManager.visiblePanels.isNotEmpty) {
                  final firstPanelId = layoutManager.visiblePanels.first;
                  layoutManager.updatePanelWidth(firstPanelId, delta.delta.dx);
                }
              },
              onDragEnd: (_) {
                layoutManager.savePanelWidths();
              },
            ),
            
            // AI面板组件 - 完整高度
            RepositoryProvider<PromptRepository>(
              create: (context) => editorController.promptRepository,
              child: MultiAIPanelView(
                novelId: editorController.novel.id,
                chapterId: editorBlocState.activeChapterId,
                layoutManager: layoutManager,
                userId: editorController.currentUserId,
                userAiModelConfigRepository: UserAIModelConfigRepositoryImpl(apiClient: editorController.apiClient),
                editorRepository: editorController.editorRepository,
                novelAIRepository: editorController.novelAIRepository,
                onContinueWritingSubmit: (parameters) {
                  AppLogger.i('EditorLayout', 'Continue Writing Submitted: $parameters');
                  TopToast.success(context, '自动续写任务已提交: $parameters');
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 小屏时以覆盖层形式展示右侧AI面板
  Widget _buildRightPanelOverlayIfNeeded(
    BuildContext context,
    editor_bloc.EditorLoaded editorBlocState,
    EditorScreenController editorController, {
    required bool isNarrow,
  }) {
    if (!isNarrow) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    return Consumer<EditorLayoutManager>(
      builder: (context, layoutManager, child) {
        final hasVisibleAIPanels = layoutManager.visiblePanels.isNotEmpty;
        if (!hasVisibleAIPanels) return const SizedBox.shrink();

        // 小屏覆盖式面板宽度：不超过屏宽的35%，并在全局最小/最大约束之间
        final double maxRightPanelWidth = (
          screenWidth * 0.35
        ).clamp(
          EditorLayoutManager.minPanelWidth,
          EditorLayoutManager.maxPanelWidth,
        );

        return Positioned.fill(
          child: Stack(
            children: [
              // 半透明遮罩，点击关闭右侧所有AI面板
              GestureDetector(
                onTap: () => layoutManager.hideAllAIPanels(),
                child: Container(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
              // 右侧贴边的覆盖面板
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: maxRightPanelWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: WebTheme.getShadowColor(context, opacity: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: RepositoryProvider<PromptRepository>(
                    create: (context) => editorController.promptRepository,
                    child: MultiAIPanelView(
                      novelId: editorController.novel.id,
                      chapterId: editorBlocState.activeChapterId,
                      layoutManager: layoutManager,
                      userId: editorController.currentUserId,
                      userAiModelConfigRepository: UserAIModelConfigRepositoryImpl(apiClient: editorController.apiClient),
                      editorRepository: editorController.editorRepository,
                      novelAIRepository: editorController.novelAIRepository,
                      onContinueWritingSubmit: (parameters) {
                        AppLogger.i('EditorLayout', 'Continue Writing Submitted: $parameters');
                        TopToast.success(context, '自动续写任务已提交: $parameters');
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  // 构建覆盖层组件
  List<Widget> _buildOverlayWidgets(BuildContext context, editor_bloc.EditorLoaded editorBlocState, EditorScreenController editorController, EditorStateManager stateManager) {
    return [
      // 移除：不再提供“完全隐藏侧边栏”的开关按钮，保留其他覆盖层
      
      // 设置面板
      Selector<EditorLayoutManager, bool>(
        selector: (context, layoutManager) => layoutManager.isSettingsPanelVisible,
        builder: (context, isVisible, child) {
          if (!isVisible) return const SizedBox.shrink();
          
          return Positioned.fill(
            child: GestureDetector(
              onTap: () => context.read<EditorLayoutManager>().toggleSettingsPanel(),
              child: Container(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: editorController.currentUserId == null
                        ? EditorDialogManager.buildLoginRequiredPanel(
                            context,
                            () => context.read<EditorLayoutManager>().toggleSettingsPanel(),
                          )
                        : SettingsPanel(
                            stateManager: stateManager,
                            userId: editorController.currentUserId!,
                            onClose: () => context.read<EditorLayoutManager>().toggleSettingsPanel(),
                            editorSettings: EditorSettings.fromMap(editorBlocState.settings),
                            onEditorSettingsChanged: (settings) {
                              context.read<editor_bloc.EditorBloc>().add(
                                  editor_bloc.UpdateEditorSettings(settings: settings.toMap()));
                            },
                            initialCategoryIndex: SettingsPanel.accountManagementCategoryIndex,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      
      
      // 保存中浮动按钮
      if (editorBlocState.isSaving)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'saving',
            onPressed: null,
            backgroundColor: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
            tooltip: '正在保存...',
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(WebTheme.isDarkMode(context) ? WebTheme.darkGrey50 : WebTheme.white),
              ),
            ),
          ),
        ),
      
      // 加载动画覆盖层 (用于非全屏的 "加载更多")
      if ((editorBlocState.isLoading || editorController.isLoadingMore) && !editorController.isFullscreenLoading)
        _buildLoadingOverlay(context, editorController),
    ];
  }

  // 构建加载动画覆盖层
  Widget _buildEndOfContentIndicator(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message,
        style: TextStyle(
          color: WebTheme.getSecondaryTextColor(context),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(BuildContext context, EditorScreenController editorController) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.only(bottom: 32.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              WebTheme.getSurfaceColor(context).withAlpha(0),
              WebTheme.getSurfaceColor(context).withAlpha(204),
              WebTheme.getSurfaceColor(context),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (editorController.isLoadingMore) // Use passed controller
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: WebTheme.getSurfaceColor(context),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: WebTheme.getShadowColor(context, opacity: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(WebTheme.getPrimaryColor(context)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '正在加载更多内容...',
                          style: TextStyle(
                            color: WebTheme.getTextColor(context),
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                if (!editorController.isLoadingMore) ...[ // Use passed controller
                  if (editorController.hasReachedEnd) // Use passed controller
                    _buildEndOfContentIndicator(context, '已到达底部'),
                  if (editorController.hasReachedStart) // Use passed controller
                    _buildEndOfContentIndicator(context, '已到达顶部'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 显示编辑器侧边栏宽度调整对话框
  void _showEditorSidebarWidthDialog(BuildContext context) {
    final layoutState = Provider.of<EditorLayoutManager>(context, listen: false);
    EditorDialogManager.showEditorSidebarWidthDialog(
      context,
      layoutState.editorSidebarWidth,
      EditorLayoutManager.minEditorSidebarWidth,
      EditorLayoutManager.maxEditorSidebarWidth,
      (value) {
        layoutState.editorSidebarWidth = value;
      },
      layoutState.saveEditorSidebarWidth,
    );
  }

}

/// 左侧侧边栏的精简抽屉，仅展示底部功能的精简版与展开按钮
class _CompactSidebarDrawer extends StatelessWidget {
  const _CompactSidebarDrawer({
    required this.onExpand,
    required this.onOpenSettings,
    required this.onOpenAIChat,
  });

  final VoidCallback onExpand;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAIChat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: WebTheme.getBackgroundColor(context),
      child: Column(
        children: [
          // 顶部展开按钮
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Tooltip(
              message: '展开侧边栏',
              child: InkWell(
                onTap: onExpand,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(Icons.menu_open, size: 18, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),

          const Spacer(),

          // 精简功能按钮区：仅保留与底部栏一致的核心功能
          _CompactActionButton(
            icon: Icons.settings,
            tooltip: '小说设置',
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 8),
          _CompactActionButton(
            icon: Icons.chat_bubble_outline,
            tooltip: 'AI聊天',
            onTap: onOpenAIChat,
          ),
          const SizedBox(height: 8),
          _CompactActionButton(
            icon: Icons.lightbulb_outline,
            tooltip: '提示词',
            onTap: () {
              context.read<editor_bloc.EditorBloc>();
              // 使用 EditorAppBar 的提示词入口逻辑：通过 EditorController 切换提示词视图
              final controller = Provider.of<EditorScreenController>(context, listen: false);
              controller.togglePromptView();
            },
          ),
          const SizedBox(height: 8),
          _CompactActionButton(
            icon: Icons.save_outlined,
            tooltip: '保存',
            onTap: () {
              try {
                final controller = Provider.of<EditorScreenController>(context, listen: false);
                controller.editorBloc.add(const editor_bloc.SaveContent());
              } catch (_) {}
            },
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}