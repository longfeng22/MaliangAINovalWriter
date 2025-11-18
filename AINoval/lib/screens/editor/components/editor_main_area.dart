import 'dart:async';
import 'dart:math' as math;

import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;
import 'package:ainoval/blocs/sidebar/sidebar_bloc.dart';
import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/services/api_service/repositories/novel_snippet_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/web_theme.dart';

// 🚀 新增：导入编辑器状态管理相关类
import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:ainoval/screens/editor/components/scene_editor.dart';
import 'package:ainoval/screens/editor/components/volume_navigation_buttons.dart';
import 'package:ainoval/screens/editor/components/boundary_indicator.dart';
import 'package:ainoval/screens/editor/utils/document_parser.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/screens/editor/components/editor_data_manager.dart';
import 'package:ainoval/screens/editor/components/center_anchor_list_builder.dart' as anchor;
import 'package:ainoval/widgets/editor/overlay_scene_beat_manager.dart';
import 'package:ainoval/models/scene_beat_data.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/screens/editor/widgets/ai_generation_toolbar.dart';
import 'package:ainoval/utils/ai_generated_content_processor.dart';
import 'package:ainoval/screens/editor/components/expansion_dialog.dart';
import 'package:ainoval/screens/editor/components/story_prediction_dialog.dart';
import 'package:ainoval/components/editable_title.dart';
import 'package:ainoval/screens/editor/widgets/menu_builder.dart';

/// 编辑器主要内容区域 - 使用 Center Anchor ListView 的新实现
/// 
/// 🚀 现在支持从指定章节开始上下渲染，实现真正的无感切换
/// 现在支持从Bloc获取小说设定和片段数据，并传递给SelectionToolbar
class EditorMainArea extends StatefulWidget {
  const EditorMainArea({
    super.key,
    required this.novel,
    required this.editorBloc,
    required this.sceneControllers,
    required this.sceneSummaryControllers,
    this.activeActId,
    this.activeChapterId,
    this.activeSceneId,
    required this.scrollController,
    required this.sceneKeys,
    // 🚀 新增：编辑器设置参数
    this.editorSettings,
  });
  
  final novel_models.Novel novel;
  final editor_bloc.EditorBloc editorBloc;
  final Map<String, QuillController> sceneControllers;
  final Map<String, TextEditingController> sceneSummaryControllers;
  final String? activeActId;
  final String? activeChapterId;
  final String? activeSceneId;
  final ScrollController scrollController;
  final Map<String, GlobalKey> sceneKeys;
  // 🚀 新增：编辑器设置字段
  final EditorSettings? editorSettings;

  @override
  State<EditorMainArea> createState() => EditorMainAreaState();
}

/// 编辑器项目类型枚举 (本地版本，兼容原有代码)
enum EditorItemType {
  actHeader,
  chapterHeader,
  scene,
  addSceneButton,
  addChapterButton,
  addActButton,
  actFooter,
  storyPredictionButton,
}

/// 编辑器项目数据类 (本地版本，兼容原有代码)
class EditorItem {
  final EditorItemType type;
  final String id;
  final novel_models.Act? act;
  final novel_models.Chapter? chapter;
  final novel_models.Scene? scene;
  final int? actIndex;
  final int? chapterIndex;
  final int? sceneIndex;
  final bool isLastInChapter;
  final bool isLastInAct;
  final bool isLastInNovel;

  EditorItem({
    required this.type,
    required this.id,
    this.act,
    this.chapter,
    this.scene,
    this.actIndex,
    this.chapterIndex,
    this.sceneIndex,
    this.isLastInChapter = false,
    this.isLastInAct = false,
    this.isLastInNovel = false,
  });
}

class EditorMainAreaState extends State<EditorMainArea> {
  // 🚀 重构：使用EditorItemManager替换原来的数据结构
  final EditorItemManager _editorItems = EditorItemManager();
  
  // 🚀 粘滞center key缓存，避免锚点短暂失效时滚到顶部
  Key? _lastCenterKey;
  
  // 添加控制器创建时间跟踪
  final Map<String, DateTime> _controllerCreationTime = {};
  
  // 🚀 新增：为SelectionToolbar提供数据的状态变量
  novel_models.Novel? _fullNovel;
  List<NovelSettingItem> _settings = [];
  List<SettingGroup> _settingGroups = [];
  List<NovelSnippet> _snippets = [];
  bool _dataLoaded = false;
  
  // 🚀 新增：智能预加载相关变量
  bool _isScrolling = false;
  Timer? _scrollEndTimer;
  Timer? _preloadTimer;
  final Duration _scrollDebounceDelay = const Duration(milliseconds: 500);
  final Duration _preloadDelay = const Duration(milliseconds: 100);
  
  // 🚀 新增：视口和预加载范围管理
  int _currentViewportStart = 0;
  int _currentViewportEnd = 0;
  int _preloadRangeStart = 0;
  int _preloadRangeEnd = 0;
  final Set<String> _preloadedSceneKeys = {};
  
  // 🚀 新增：滚动时间跟踪
  DateTime _lastScrollTime = DateTime.now();
  
  // 🚀 新增：快速跳转/拖拽滚动条检测
  bool _isProgrammaticJump = false;
  bool _isFastDragJump = false;
  static const double _fastDragThresholdPxPerSecond = 1200;
  
  // 🚀 新增：视口计算相关常量
  static const double _estimatedItemHeight = 300.0;
  static const int _preloadWindowSize = 5;
  
  // 🚀 新增：滚动位置保持相关变量
  double _lastKnownScrollOffset = 0.0;
  bool _isPreservingScrollPosition = false;
  final Map<String, double> _itemHeights = {};
  
  // 🚀 新增：更保守的清理控制
  DateTime _lastCleanupTime = DateTime.now();
  static const Duration _minCleanupInterval = Duration(minutes: 2);
  
  // 🚀 新增：沉浸模式状态缓存，用于检测状态变化
  bool? _lastImmersiveMode;
  String? _lastImmersiveChapterId;
  
  // 🚀 新增：无感切换相关变量
  bool _isPreparingScrollPosition = false;
  double? _preparedScrollOffset;
  
  // （移除重复声明）
  
  // 🚀 新增：编辑器状态管理
  EditorScreenController? _editorController;
  EditorLayoutManager? _layoutManager;

  /// 🚀 当锚点在本帧失效时，保留并恢复当前滚动位置，避免跳到顶部
  void _preserveScrollPositionOnAnchorLoss() {
    if (_isPreservingScrollPosition) return;
    final controller = widget.scrollController;
    if (!controller.hasClients) return;
    final double current = controller.offset;
    _isPreservingScrollPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (controller.hasClients) {
          controller.jumpTo(current);
        }
      } catch (_) {}
      _isPreservingScrollPosition = false;
    });
  }

  // 🚀 场景的GlobalKey映射，用于追踪场景位置
  final Map<String, GlobalKey> _sceneGlobalKeys = {};

  @override
  void initState() {
    super.initState();
    _setupScrollListener();
    _loadDataForSelectionToolbar();
    // 根据传入的编辑器设置应用主题变体
    // 变体由全局统一应用，这里不再本地应用以避免时序竞争
    // _applyThemeVariantFromSettings();
    
    // 🚀 新增：获取编辑器状态管理器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeEditorState();
      _initialPreload();
    });
  }
  
  /// 🚀 新增：初始化编辑器状态
  void _initializeEditorState() {
    try {
      // 通过Provider获取编辑器状态管理器
      _editorController = Provider.of<EditorScreenController>(context, listen: false);
      _layoutManager = Provider.of<EditorLayoutManager>(context, listen: false);
      
      // 🚀 新增：初始化沉浸模式状态缓存
      final editorState = widget.editorBloc.state;
      if (editorState is editor_bloc.EditorLoaded) {
        _lastImmersiveMode = editorState.isImmersiveMode;
        _lastImmersiveChapterId = editorState.immersiveChapterId;
        AppLogger.i('EditorMainArea', '初始化沉浸模式状态缓存 - 模式:$_lastImmersiveMode, 章节:$_lastImmersiveChapterId');
      }
      
      AppLogger.i('EditorMainArea', '✅ 成功获取编辑器状态管理器');
    } catch (e) {
      AppLogger.w('EditorMainArea', '⚠️ 获取编辑器状态管理器失败: $e');
    }
  }

  @override
  void didUpdateWidget(EditorMainArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检查小说结构是否发生变化
    if (oldWidget.novel != widget.novel) {
      // 不再需要_buildEditorItems，由CenterAnchorListBuilder处理
      AppLogger.i('EditorMainArea', '检测到小说结构变化');
    }

    // 当编辑器设置的主题变体变化时，应用新的主题变体
    final String? oldVariant = oldWidget.editorSettings?.themeVariant;
    final String? newVariant = widget.editorSettings?.themeVariant;
    if (oldVariant != newVariant) {
      // _applyThemeVariantFromSettings(); // 统一由全局处理，避免局部覆盖
      if (mounted) setState(() {});
    }
  }

  /// 🚀 新增：获取当前小说数据
  novel_models.Novel _getCurrentNovel() {
    // 优先使用EditorBloc中的最新数据
    final blocState = widget.editorBloc.state;
    if (blocState is editor_bloc.EditorLoaded) {
      return blocState.novel;
    }
    // 回退到widget传入的数据
    return widget.novel;
  }

  /// 应用来自编辑器设置的主题变体
  void _applyThemeVariantFromSettings() {
    try {
      final String variant = widget.editorSettings?.themeVariant ?? 'monochrome';
      WebTheme.applyVariant(variant);
      AppLogger.i('EditorMainArea', '应用主题变体: $variant');
    } catch (e) {
      AppLogger.w('EditorMainArea', '应用主题变体失败', e);
    }
  }

  /// 🚀 新增：转换anchor.EditorItem到本地EditorItem
  EditorItem _convertAnchorItemToLocal(anchor.EditorItem anchorItem) {
    return EditorItem(
      type: _convertItemType(anchorItem.type),
      id: anchorItem.id,
      act: anchorItem.act,
      chapter: anchorItem.chapter,
      scene: anchorItem.scene,
      actIndex: anchorItem.actIndex,
      chapterIndex: anchorItem.chapterIndex,
      sceneIndex: anchorItem.sceneIndex,
      isLastInChapter: anchorItem.isLastInChapter,
      isLastInAct: anchorItem.isLastInAct,
      isLastInNovel: anchorItem.isLastInNovel,
    );
  }

  /// 转换item类型
  EditorItemType _convertItemType(anchor.EditorItemType anchorType) {
    switch (anchorType) {
      case anchor.EditorItemType.actHeader:
        return EditorItemType.actHeader;
      case anchor.EditorItemType.chapterHeader:
        return EditorItemType.chapterHeader;
      case anchor.EditorItemType.scene:
        return EditorItemType.scene;
      case anchor.EditorItemType.addSceneButton:
        return EditorItemType.addSceneButton;
      case anchor.EditorItemType.addChapterButton:
        return EditorItemType.addChapterButton;
      case anchor.EditorItemType.addActButton:
        return EditorItemType.addActButton;
      case anchor.EditorItemType.actFooter:
        return EditorItemType.actFooter;
      case anchor.EditorItemType.storyPredictionButton:
        return EditorItemType.storyPredictionButton;
    }
  }

  /// 🚀 新增：构建多个slivers的组合
  Widget _buildMultipleSlivers(List<Widget> slivers) {
    // 如果只有一个sliver，直接返回
    if (slivers.length == 1) {
      return slivers.first;
    }
    
    // 使用SliverList包装多个slivers
    return SliverMainAxisGroup(slivers: slivers);
  }

  /// 用于滚动到指定章节或场景
  void scrollToChapter(String chapterId) {
    AppLogger.i('EditorMainArea', '滚动到章节: $chapterId (使用center anchor)');
    
    // 🚀 关键改进：直接触发重建，使用center anchor
    final editorState = widget.editorBloc.state;
    if (editorState is editor_bloc.EditorLoaded) {
      // 设置focusChapterId来触发center anchor重建
      widget.editorBloc.add(editor_bloc.SetFocusChapter(chapterId: chapterId));
    }
  }
  
  void scrollToScene(String sceneId) {
    AppLogger.i('EditorMainArea', '滚动到场景: $sceneId');
    
    // 查找场景所属的章节
    final novel = _getCurrentNovel();
    for (final act in novel.acts) {
      for (final chapter in act.chapters) {
        for (final scene in chapter.scenes) {
          if (scene.id == sceneId) {
            // 先滚动到章节
            scrollToChapter(chapter.id);
            return;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<editor_bloc.EditorBloc, editor_bloc.EditorState>(
      bloc: widget.editorBloc,
      listener: (context, state) {
        // 响应状态变化
        if (state is editor_bloc.EditorLoaded) {
          // 🚀 修复：检查沉浸模式状态变化
          bool shouldRebuild = false;
          
          // 1. 小说对象变化时重建
          if (state.novel != widget.novel) {
            shouldRebuild = true;
            AppLogger.i('EditorMainArea', '检测到小说对象变化，触发重建');
          }
          
          // 2. 沉浸模式状态变化时重建  
          if (state.isImmersiveMode != _lastImmersiveMode || 
              state.immersiveChapterId != _lastImmersiveChapterId) {
            shouldRebuild = true;
            AppLogger.i('EditorMainArea', '检测到沉浸模式状态变化，触发重建 - 模式:${state.isImmersiveMode}, 章节:${state.immersiveChapterId}');
            
            // 更新缓存状态
            _lastImmersiveMode = state.isImmersiveMode;
            _lastImmersiveChapterId = state.immersiveChapterId;
          }
          
          // 3. focusChapterId变化时重建（用于center anchor）
          if (state.focusChapterId != null) {
            shouldRebuild = true;
            AppLogger.i('EditorMainArea', '检测到focusChapterId变化，触发center anchor重建: ${state.focusChapterId}');
          }
          
          if (shouldRebuild) {
            // 使用setState触发重建，让_buildScrollView使用新的状态
            setState(() {});
          }
        }
      },
      child: _buildScrollView(),
    );
  }
  
  /// 🚀 辅助方法：移除sliver的key，避免与SliverPadding的key冲突
  Widget _removeSliverKey(Widget sliver) {
    if (sliver is SliverList) {
      return SliverList(
        // key: null, // 明确不设置key
        delegate: sliver.delegate,
      );
    } else if (sliver is SliverToBoxAdapter) {
      return SliverToBoxAdapter(
        // key: null, // 明确不设置key
        child: sliver.child,
      );
    }
    // 对于其他类型的sliver，直接返回（大多数情况下是SliverList）
    return sliver;
  }

  /// 🚀 核心方法：构建使用center anchor的滚动视图
  Widget _buildScrollView() {
    final editorState = widget.editorBloc.state;
    final hasReachedStart = editorState is editor_bloc.EditorLoaded && editorState.hasReachedStart;
    final hasReachedEnd = editorState is editor_bloc.EditorLoaded && editorState.hasReachedEnd;
    
    // 🚀 新增：确定锚点章节ID和模式
    String? anchorChapterId;
    bool isImmersiveMode = false;
    String? immersiveChapterId;
    
    if (editorState is editor_bloc.EditorLoaded) {
      isImmersiveMode = editorState.isImmersiveMode;
      immersiveChapterId = editorState.immersiveChapterId;
      
      // 🚀 关键：从focusChapterId获取锚点章节（用于无感切换）
      anchorChapterId = editorState.focusChapterId;
      
      AppLogger.i('EditorMainArea', 
          '构建scrollView - 沉浸模式:$isImmersiveMode, 沉浸章节:$immersiveChapterId, 锚点章节:$anchorChapterId');
    }
    
    // 🚀 核心：使用CenterAnchorListBuilder构建slivers
    final listBuilder = anchor.CenterAnchorListBuilder(
      novel: _getCurrentNovel(),
      anchorChapterId: anchorChapterId,
      isImmersiveMode: isImmersiveMode,
      immersiveChapterId: immersiveChapterId,
    );
    
    final contentSlivers = listBuilder.buildCenterAnchoredSlivers(
      itemBuilder: (anchor.EditorItem item) {
        // 转换anchor.EditorItem到本地EditorItem
        final localItem = _convertAnchorItemToLocal(item);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: _buildEditorItem(localItem),
          ),
        );
      },
    );
    
    // 🚀 构建最终的slivers列表
    // 粘滞center key：如果本次为null而上一帧有有效key，则沿用上一帧的key，避免跳到顶部
    final Key? computedCenterKey = listBuilder.getCenterAnchorKey();
    // 只在本次计算到有效key时更新缓存
    if (computedCenterKey != null) {
      _lastCenterKey = computedCenterKey;
    }
    final centerKey = computedCenterKey ?? _lastCenterKey;
    AppLogger.i('EditorMainArea', '开始构建最终slivers - centerKey: $centerKey, contentSlivers数量: ${contentSlivers.length}');
    
    final allSlivers = <Widget>[
      // 开始边界指示器
      if (hasReachedStart)
        SliverToBoxAdapter(child: BoundaryIndicator(isTop: true)),
      
      // 🚀 关键修复：主要内容 - 处理center key的转移
      ...contentSlivers.map((sliver) {
        // 检查这个sliver是否有center key
        final hasCenterKey = centerKey != null && sliver.key == centerKey;
        
        if (hasCenterKey) {
          AppLogger.i('EditorMainArea', '🎯 找到center key sliver，转移key到SliverPadding - key: $centerKey');
        }
        
        return SliverPadding(
          // 🚀 关键：如果原sliver有center key，转移到SliverPadding上
          key: hasCenterKey ? centerKey : null,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          sliver: hasCenterKey 
            ? _removeSliverKey(sliver) // 移除原sliver的key避免冲突
            : sliver,
        );
      }),
      
      // 结束边界指示器
      if (hasReachedEnd)
        SliverToBoxAdapter(child: BoundaryIndicator(isTop: false)),
    ];
    
    // 🚀 最终验证：确认center key在最终slivers中存在，并决定最终传入的center
    Key? finalCenterKey;
    if (centerKey != null) {
      final hasMatchingSliver = allSlivers.any((sliver) => sliver.key == centerKey);
      AppLogger.i('EditorMainArea', '最终验证center key - key: $centerKey, 找到匹配: $hasMatchingSliver, 总slivers: ${allSlivers.length}');
      finalCenterKey = hasMatchingSliver ? centerKey : null;
      if (!hasMatchingSliver) {
        // 锚点短暂失效：保留并恢复当前滚动位置，避免跳到顶部
        _preserveScrollPositionOnAnchorLoss();
      }
    } else {
      finalCenterKey = null;
      // 无center：同样兜底
      _preserveScrollPositionOnAnchorLoss();
    }
    
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        controller: widget.scrollController,
        // 🚀 关键：设置center anchor
        center: finalCenterKey,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: allSlivers,
      ),
    );
  }
  
  Widget _buildEditorItem(EditorItem item) {
    switch (item.type) {
      case EditorItemType.actHeader:
        return _buildActHeader(item);
      case EditorItemType.chapterHeader:
        return _buildChapterHeader(item);
      case EditorItemType.scene:
        return _buildSceneEditor(item);
      case EditorItemType.addSceneButton:
        return _buildAddSceneButton(item);
      case EditorItemType.addChapterButton:
        return _buildAddChapterButton(item);
      case EditorItemType.addActButton:
        return _buildAddActButton(item);
      case EditorItemType.actFooter:
        return _buildActFooter(item);
      case EditorItemType.storyPredictionButton:
        return _buildStoryPredictionButton(item);
    }
  }
  
  Widget _buildActHeader(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.book, color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey600 : WebTheme.grey800),
          const SizedBox(width: 12),
          // 卷序号前缀
          Text(
            '第${item.actIndex}卷 · ',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: WebTheme.getTextColor(context),
            ),
          ),
          // 可编辑卷标题
          Expanded(
            child: EditableTitle(
              initialText: item.act!.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
              textAlign: TextAlign.left,
              // 仅在提交时派发更新
              onSubmitted: (value) {
                widget.editorBloc.add(editor_bloc.UpdateActTitle(
                  actId: item.act!.id,
                  title: value,
                ));
              },
            ),
          ),
          const SizedBox(width: 8),
          // 统一三点菜单（卷）
          MenuBuilder.buildActMenu(
            context: context,
            editorBloc: widget.editorBloc,
            actId: item.act!.id,
            onRenamePressed: null,
            width: 220,
            align: 'right',
          ),
        ],
      ),
    );
  }
  
  Widget _buildChapterHeader(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.article, color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey600 : WebTheme.grey700),
          const SizedBox(width: 8),
          // 章节序号前缀
          Text(
            '第${item.chapterIndex}章 · ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          // 可编辑章节标题
          Expanded(
            child: EditableTitle(
              initialText: item.chapter!.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              textAlign: TextAlign.left,
              // 仅在提交时派发更新
              onSubmitted: (value) {
                widget.editorBloc.add(editor_bloc.UpdateChapterTitle(
                  actId: item.act!.id,
                  chapterId: item.chapter!.id,
                  title: value,
                ));
              },
            ),
          ),
          const SizedBox(width: 8),
          // 统一三点菜单（章节）
          MenuBuilder.buildChapterMenu(
            context: context,
            editorBloc: widget.editorBloc,
            actId: item.act!.id,
            chapterId: item.chapter!.id,
            onRenamePressed: null,
            width: 220,
            align: 'right',
          ),
        ],
      ),
    );
  }
  
  Widget _buildSceneEditor(EditorItem item) {
    final scene = item.scene!;
    final sceneKey = '${item.act!.id}_${item.chapter!.id}_${scene.id}';
    
    // 🚀 提前创建GlobalKey，用于约束面板追踪
    final sceneGlobalKey = _sceneGlobalKeys.putIfAbsent(
      sceneKey, 
      () => GlobalKey(debugLabel: 'scene_$sceneKey'),
    );
    
    // 🚀 优化：检查控制器是否存在
    final controller = widget.sceneControllers[sceneKey];
    final summaryController = widget.sceneSummaryControllers[sceneKey];
    
    // 🚀 关键修复：只有控制器不存在且正在滚动时，才显示占位符
    if (controller == null || summaryController == null) {
      // 快速跳转期间返回轻量占位以避免创建控制器
      if (_isProgrammaticJump || _isFastDragJump) {
        return const SizedBox(height: _estimatedItemHeight);
      }
      // 🚀 关键修复：滚动状态下不创建控制器，显示占位符
      if (_isScrolling) {
        return _buildStableScenePlaceholder(item);
      }
      
      // 🚀 关键修复：非滚动状态立即创建控制器
      _createSceneControllerWithPositionPreservation(sceneKey, scene);
      
      // 再次尝试获取控制器
      final immediateController = widget.sceneControllers[sceneKey];
      final immediateSummaryController = widget.sceneSummaryControllers[sceneKey];
      
      // 如果还是没有，返回占位符
      if (immediateController == null || immediateSummaryController == null) {
        AppLogger.w('EditorMainArea', '立即创建失败，显示占位符: $sceneKey');
        return _buildStableScenePlaceholder(item);
      }
      
      // 使用立即创建的控制器
      return _buildRealSceneEditor(item, immediateController, immediateSummaryController, sceneGlobalKey);
    }
    
    // 🚀 关键修复：如果控制器存在，即使在滚动也显示真实编辑器
    return _buildRealSceneEditor(item, controller, summaryController, sceneGlobalKey);
  }
  
  /// 🚀 新增：构建真实的场景编辑器
  Widget _buildRealSceneEditor(EditorItem item, QuillController controller, TextEditingController summaryController, GlobalKey sceneGlobalKey) {
    final scene = item.scene!;
    final sceneKey = '${item.act!.id}_${item.chapter!.id}_${scene.id}';
    
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxContentWidth = 1800.0;
        final availableWidth = constraints.maxWidth;
        final leftSpace = (availableWidth - maxContentWidth) / 2;
        
        // 只有当左侧空白>=340px时才显示面板
        final showPanel = leftSpace >= 340;
        
        // 直接返回居中的场景编辑器，场景节拍面板在外层浮动布局中处理
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Container(
              key: sceneGlobalKey, // 添加GlobalKey用于位置追踪
              child: SceneEditor(
                key: ValueKey('scene_editor_$sceneKey'),
                title: scene.title.isNotEmpty ? scene.title : '场景 ${item.sceneIndex}',
                wordCount: scene.wordCount,
                isActive: scene.id == widget.activeSceneId && 
                          item.chapter!.id == widget.activeChapterId && 
                          item.act!.id == widget.activeActId,
                actId: item.act!.id,
                chapterId: item.chapter!.id,
                sceneId: scene.id,
                isFirst: item.sceneIndex == 1,
                sceneIndex: item.sceneIndex,
                controller: controller,
                summaryController: summaryController,
                editorBloc: widget.editorBloc,
                // 🚀 新增：传递SelectionToolbar需要的数据
                novel: _fullNovel,
                settings: _settings,
                settingGroups: _settingGroups,
                snippets: _snippets,
                // 🚀 新增：传递编辑器设置
                editorSettings: widget.editorSettings,
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildActFooter(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      height: 32,
      child: const Divider(),
    );
  }
  
  /// 🚀 新增：构建稳定高度的场景占位符，确保不影响滚动位置
  Widget _buildStableScenePlaceholder(EditorItem item) {
    final scene = item.scene!;
    
    // 🚀 关键修复：使用固定高度，确保占位符和真实场景高度相近
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0, top: 8.0),
      padding: const EdgeInsets.all(16.0),
      height: 240, // 🚀 关键修复：固定高度240px，接近真实场景编辑器高度
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 左侧：场景信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 场景标题
                Text(
                  '${item.sceneIndex != null ? "场景${item.sceneIndex} · " : ""}${scene.title.isNotEmpty ? scene.title : "场景"}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: WebTheme.grey700,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                
                const SizedBox(height: 12),
                
                // 模拟内容区域
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 32,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${scene.wordCount} 字',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // 底部操作栏占位
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// 🚀 新增：创建场景控制器并保持滚动位置
  void _createSceneControllerWithPositionPreservation(String sceneKey, novel_models.Scene scene) {
    // 检查是否已经有控制器
    if (widget.sceneControllers.containsKey(sceneKey)) {
      return;
    }
    
    try {
      // 创建控制器
      _createSceneControllerNow(sceneKey, scene);
    } catch (e) {
      AppLogger.e('EditorMainArea', '创建场景控制器失败: $sceneKey', e);
      
      // 创建默认控制器
      widget.sceneControllers[sceneKey] = QuillController(
        document: Document.fromJson([{'insert': '\n'}]),
        selection: const TextSelection.collapsed(offset: 0),
      );
      widget.sceneSummaryControllers[sceneKey] = TextEditingController(text: '');
      _controllerCreationTime[sceneKey] = DateTime.now();
    }
  }
  
  /// 🚀 新增：立即创建场景控制器
  Future<void> _createSceneControllerNow(String sceneKey, novel_models.Scene scene) async {
    // 检查是否已经有控制器
    if (widget.sceneControllers.containsKey(sceneKey)) {
      return;
    }

    try {
      // 🚀 修复：检查是否是新建场景，确保使用正确的空内容
      String contentToUse = scene.content;
      

      
      // 先放一个空控制器占位，保持 UI 流畅
      final placeholderController = QuillController(
        document: Document.fromJson([{'insert': '\n'}]),
        selection: const TextSelection.collapsed(offset: 0),
      );
      widget.sceneControllers[sceneKey] = placeholderController;
      widget.sceneSummaryControllers[sceneKey] = TextEditingController(text: scene.summary.content);
      _controllerCreationTime[sceneKey] = DateTime.now();

      // 异步解析实际文档（带缓存 + isolate）
      final doc = await DocumentParser.parseDocumentSafely(contentToUse);

      // 如果组件仍在并且 map 仍指向 placeholder，则替换
      if (mounted && widget.sceneControllers[sceneKey] == placeholderController) {
        final newController = QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
        widget.sceneControllers[sceneKey] = newController;
        if (mounted) setState(() {}); // 触发重建显示真实内容
      }
    } catch (e) {
      AppLogger.e('EditorMainArea', '异步创建场景控制器失败: $sceneKey', e);
    }
  }
  
  /// 🚀 新增：智能滚动监听处理
  void _onScroll() {
    if (!mounted) return;
    
    final scrollController = widget.scrollController;
    if (!scrollController.hasClients) return;
    
    // 🚀 修复：如果正在保持滚动位置，不处理滚动事件
    if (_isPreservingScrollPosition) {
      return;
    }
    
    // 当前滚动偏移量
    final double currentOffset = scrollController.offset;

    // 计算速度检测拖拽滚动条（先计算dt，再更新_lastScrollTime）
    final DateTime now = DateTime.now();
    final int dt = now.difference(_lastScrollTime).inMilliseconds;
    if (dt > 0) {
      final double speed = ((_lastKnownScrollOffset - currentOffset).abs() / dt) * 1000;
      _isFastDragJump = speed > _fastDragThresholdPxPerSecond;
    }
    // 更新滚动时间
    _lastScrollTime = now;

    // 如果是快速拖拽或程序跳转，跳过繁重逻辑
    if (_isProgrammaticJump || _isFastDragJump) {
      _lastKnownScrollOffset = currentOffset;
      // 仍然使用timer等待结束
      _scrollEndTimer?.cancel();
      _scrollEndTimer = Timer(_scrollDebounceDelay, () {
        if (mounted) {
          _onScrollEnd();
        }
      });
      return;
    }

    // 仅当位移超过阈值时才重新计算视口
    if ((_lastKnownScrollOffset - currentOffset).abs() > 32) {
      _lastKnownScrollOffset = currentOffset;
      _calculateViewportRange();
    }
    
    // 🚀 修复：只在用户主动滚动时标记滚动状态
    if (!_isScrolling) {
      _isScrolling = true;
    }
    
    // 🚀 关键修复：滚动时不立即预加载，等用户停止滚动后再处理
    // 重置滚动结束计时器
    _scrollEndTimer?.cancel();
    _scrollEndTimer = Timer(_scrollDebounceDelay, () {
      if (mounted) {
        _onScrollEnd();
      }
    });
  }
  
  /// 🚀 新增：滚动结束处理
  void _onScrollEnd() {
    if (!mounted) return;
    _isFastDragJump = false;
    
    _isScrolling = false;
    
    // 计算预加载范围
    _calculatePreloadRange();
    
    // 执行智能预加载
    _processSmartPreload();
    
    // 为当前视口创建控制器
    _createControllersForCurrentViewport();
    
    // 清理超出范围的控制器（使用现有方法）
    _finalizePreload();
  }
  
  /// 🚀 新增：计算当前视口范围
  void _calculateViewportRange() {
    final scrollController = widget.scrollController;
    final scrollOffset = scrollController.offset;
    final viewportHeight = scrollController.position.viewportDimension;
    
    // 计算视口内的item索引范围
    _currentViewportStart = (scrollOffset / _estimatedItemHeight).floor().clamp(0, 100); // 使用固定最大值
    _currentViewportEnd = ((scrollOffset + viewportHeight) / _estimatedItemHeight).ceil().clamp(0, 100);
  }
  
  /// 🚀 新增：计算预加载范围
  void _calculatePreloadRange() {
    // 在视口上下各扩展一个窗口
    _preloadRangeStart = (_currentViewportStart - _preloadWindowSize).clamp(0, 100);
    _preloadRangeEnd = (_currentViewportEnd + _preloadWindowSize).clamp(0, 100);
  }
  
  /// 🚀 新增：智能预加载处理
  void _processSmartPreload() {
    // 预加载逻辑简化，主要依赖于center anchor的按需加载
  }
  
  /// 🚀 新增：完成预加载（滚动结束后的清理）
  void _finalizePreload() {
    // 🚀 关键修复：滚动结束后立即为当前视口创建控制器
    _createControllersForCurrentViewport();
  }
  
  /// 🚀 新增：为当前视口创建控制器
  void _createControllersForCurrentViewport() {
    // 简化的控制器创建逻辑
    if (mounted) {
      setState(() {});
    }
  }
  
  /// 🚀 新增：初始预加载
  void _initialPreload() {
    // 初始预加载逻辑简化
  }
  
  /// 🚀 新增：构建添加场景按钮
  Widget _buildAddSceneButton(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _AddButton(
          icon: Icons.add_circle_outline,
          label: '添加场景',
          tooltip: '在此章节添加新场景',
          onPressed: () => _addNewScene(item.act!.id, item.chapter!.id),
          style: _AddButtonStyle.scene,
        ),
      ),
    );
  }

  /// 🚀 新增：构建添加章节按钮
  Widget _buildAddChapterButton(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _AddButton(
          icon: Icons.library_add_outlined,
          label: '添加章节',
          tooltip: '在此卷添加新章节',
          onPressed: () => _addNewChapter(item.act!.id),
          style: _AddButtonStyle.chapter,
        ),
      ),
    );
  }

  /// 🚀 新增：构建添加卷按钮
  Widget _buildAddActButton(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _AddButton(
          icon: Icons.auto_stories_outlined,
          label: '添加新卷',
          tooltip: '在小说末尾添加新卷',
          onPressed: _addNewAct,
          style: _AddButtonStyle.act,
        ),
      ),
    );
  }
  
  /// 🚀 新增：构建剧情推演按钮（暂时隐藏）
  Widget _buildStoryPredictionButton(EditorItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => _showStoryPredictionDialog(item.chapter!),
          icon: Icon(
            Icons.auto_stories,
            size: 18,
            color: WebTheme.isDarkMode(context) 
              ? Colors.deepPurple[300] 
              : Colors.deepPurple[700],
          ),
          label: Text(
            '剧情推演',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.isDarkMode(context) 
                ? Colors.deepPurple[300] 
                : Colors.deepPurple[700],
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            side: BorderSide(
              color: WebTheme.isDarkMode(context) 
                ? Colors.deepPurple[300]! 
                : Colors.deepPurple[700]!,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
    
  }

  /// 🚀 新增：添加新场景
  void _addNewScene(String actId, String chapterId) {
    final newSceneId = DateTime.now().millisecondsSinceEpoch.toString();
    AppLogger.i('EditorMainArea', '添加新场景：actId=$actId, chapterId=$chapterId, sceneId=$newSceneId');
    
    widget.editorBloc.add(editor_bloc.AddNewScene(
      novelId: widget.editorBloc.novelId,
      actId: actId,
      chapterId: chapterId,
      sceneId: newSceneId,
    ));
  }
  
  /// 🚀 新增：显示剧情推演对话框
  void _showStoryPredictionDialog(novel_models.Chapter chapter) {
    AppLogger.i('EditorMainArea', '显示剧情推演对话框：chapterId=${chapter.id}');
    
    // 🚀 修复：使用新的便捷函数，传递完整的小说数据
    showStoryPredictionDialog(
      context,
      novelId: widget.editorBloc.novelId,
      chapter: chapter,
      novel: _fullNovel,
      settings: _settings,
      settingGroups: _settingGroups,
      snippets: _snippets,
      onCancel: () {
        AppLogger.i('EditorMainArea', '取消剧情推演');
      },
      onGenerate: (config) {
        AppLogger.i('EditorMainArea', '开始生成剧情推演: $config');
        Navigator.of(context).pop();
        
        // TODO: 处理剧情推演生成请求
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('剧情推演生成功能开发中...'),
            duration: Duration(seconds: 3),
          ),
        );
      },
    );
  }

  /// 🚀 新增：添加新章节
  void _addNewChapter(String actId) {
    AppLogger.i('EditorMainArea', '添加新章节：actId=$actId');
    
    widget.editorBloc.add(editor_bloc.AddNewChapter(
      novelId: widget.editorBloc.novelId,
      actId: actId,
      title: '新章节',
    ));
  }

  void _addNewAct() {
    widget.editorBloc.add(editor_bloc.AddNewAct(title: '新卷'));
  }

  // 提供刷新方法供外部调用
  void refreshUI() {
    if (mounted) {
      setState(() {
        // 由CenterAnchorListBuilder自动处理重建
      });
    }
  }

  @override
  void dispose() {
    // 🚀 新增：隐藏场景节拍面板，解绑生命周期
    AppLogger.i('EditorMainArea', '🚀 EditorMainArea销毁，隐藏场景节拍面板');
    OverlaySceneBeatManager.instance.hide();
    
    // 清理定时器
    _scrollEndTimer?.cancel();
    _preloadTimer?.cancel();
    
    // 移除滚动监听器
    widget.scrollController.removeListener(_onScroll);
    
    // 清理所有控制器
    _disposeAllControllers();
    
    super.dispose();
  }
  
  /// 清理所有控制器
  void _disposeAllControllers() {
    final sceneKeys = widget.sceneControllers.keys.toList();
    for (final sceneKey in sceneKeys) {
      _disposeSceneController(sceneKey);
    }
    _controllerCreationTime.clear();
    _sceneGlobalKeys.clear(); // 清理GlobalKey映射
    AppLogger.i('EditorMainArea', '已清理所有场景控制器');
  }

  /// 🚀 新增：设置滚动监听器
  void _setupScrollListener() {
    widget.scrollController.addListener(_onScroll);
  }
  
  /// 安全地释放场景控制器
  void _disposeSceneController(String sceneKey) {
    try {
      final quillController = widget.sceneControllers[sceneKey];
      final summaryController = widget.sceneSummaryControllers[sceneKey];
      
      if (quillController != null && summaryController != null) {
        // 标记为待清理，但不立即从Map中移除
        _controllerCreationTime[sceneKey] = DateTime.fromMillisecondsSinceEpoch(0); // 设置为很早的时间作为标记
        
        // 延迟更长时间后再真正清理，确保UI已经更新
        Future.delayed(const Duration(seconds: 2), () {
          try {
            // 再次检查是否可以安全清理
            if (widget.sceneControllers.containsKey(sceneKey) && 
                _controllerCreationTime[sceneKey]?.millisecondsSinceEpoch == 0) {
              
              // 现在可以安全移除引用
              widget.sceneControllers.remove(sceneKey);
              widget.sceneSummaryControllers.remove(sceneKey);
              _controllerCreationTime.remove(sceneKey);
              widget.sceneKeys.remove(sceneKey);
              
              // 最后释放控制器
              quillController.dispose();
              summaryController.dispose();
            }
          } catch (e) {
            AppLogger.w('EditorMainArea', '延迟释放控制器时出错: $sceneKey', e);
          }
        });
      }
      
    } catch (e) {
      AppLogger.w('EditorMainArea', '标记控制器销毁时出错: $sceneKey', e);
    }
  }

  /// 🚀 新增：加载SelectionToolbar需要的数据
  Future<void> _loadDataForSelectionToolbar() async {
    try {
      // 🚀 修复：直接使用widget.novel而不是等待SidebarBloc
      setState(() {
        _fullNovel = widget.novel; // 直接使用传入的novel
      });
      
      // 触发设定数据加载
      final settingBloc = context.read<SettingBloc>();
      settingBloc.add(LoadSettingGroups(widget.novel.id));
      settingBloc.add(LoadSettingItems(novelId: widget.novel.id));
      
      // 加载片段数据
      _loadSnippetsData();
      
      // 监听Bloc状态变化
      _setupBlocListeners();
      
    } catch (e) {
      AppLogger.e('EditorMainArea', '加载SelectionToolbar数据失败', e);
    }
  }
  
  /// 🚀 新增：设置Bloc监听器
  void _setupBlocListeners() {
    // 🚀 修复：不再等待SidebarBloc，直接使用widget.novel
    // 如果需要监听小说结构变化，可以监听EditorBloc
    widget.editorBloc.stream.listen((editorState) {
      if (mounted && editorState is editor_bloc.EditorLoaded) {
        // 当编辑器状态更新时，更新novel数据
        setState(() {
          _fullNovel = editorState.novel;
        });
        _checkDataLoaded();
      }
    });
    
    // 监听SettingBloc获取设定数据
    context.read<SettingBloc>().stream.listen((settingState) {
      if (mounted) {
        setState(() {
          _settings = settingState.items;
          _settingGroups = settingState.groups;
        });
        _checkDataLoaded();
      }
    });
  }
  
  /// 🚀 新增：加载片段数据
  Future<void> _loadSnippetsData() async {
    try {
      final snippetRepository = context.read<NovelSnippetRepository>();
      final result = await snippetRepository.getSnippetsByNovelId(
        widget.novel.id,
        page: 0,
        size: 50, // 限制数量避免过多数据
      );
      
      if (mounted) {
        setState(() {
          _snippets = result.content;
        });
        _checkDataLoaded();
      }
    } catch (e) {
      AppLogger.e('EditorMainArea', '加载片段数据失败', e);
      if (mounted) {
        setState(() {
          _snippets = [];
        });
        _checkDataLoaded();
      }
    }
  }
  
  /// 🚀 新增：检查数据是否全部加载完成
  void _checkDataLoaded() {
    final isLoaded = _fullNovel != null; // 其他数据允许为空
    if (isLoaded != _dataLoaded) {
      setState(() {
        _dataLoaded = isLoaded;
      });
    }
  }
}

/// 🚀 新增：添加按钮样式枚举
enum _AddButtonStyle {
  scene,
  chapter,
  act,
}

/// 🚀 新增：通用添加按钮组件
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.style,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final _AddButtonStyle style;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 根据样式类型设置不同的视觉效果
    late final Color primaryColor;
    late final Color backgroundColor;
    late final double iconSize;
    late final double fontSize;
    late final EdgeInsets padding;
    
    switch (style) {
      case _AddButtonStyle.scene:
        primaryColor = WebTheme.getSecondaryTextColor(context);
        backgroundColor = WebTheme.getSurfaceColor(context);
        iconSize = 18;
        fontSize = 14;
        padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
        break;
      case _AddButtonStyle.chapter:
        primaryColor = WebTheme.getTextColor(context);
        backgroundColor = WebTheme.getSurfaceColor(context);
        iconSize = 20;
        fontSize = 15;
        padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
        break;
      case _AddButtonStyle.act:
        primaryColor = WebTheme.getTextColor(context);
        backgroundColor = WebTheme.getSurfaceColor(context);
        iconSize = 22;
        fontSize = 16;
        padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
        break;
    }

    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: primaryColor),
      label: Text(
        label,
        style: TextStyle(
          color: primaryColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        backgroundColor: backgroundColor,
        side: BorderSide.none,
        padding: padding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) {
              return primaryColor.withOpacity(0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return primaryColor.withOpacity(0.12);
            }
            return null;
          },
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}