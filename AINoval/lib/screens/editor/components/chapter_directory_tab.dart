import 'package:ainoval/blocs/editor/editor_bloc.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/blocs/sidebar/sidebar_bloc.dart';
import 'dart:async'; // Import for StreamSubscription
import 'package:ainoval/utils/event_bus.dart'; // Import EventBus and the event
import 'package:ainoval/widgets/common/app_search_field.dart';
import 'package:flutter/rendering.dart'; // Import for AutomaticKeepAliveClientMixin
// 🎯 拖放功能
import 'package:ainoval/models/context_drag_data.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/widgets/common/draggable_context_item.dart';

// 🚀 数据类，用于ListView.builder
class _ActItemData {
  final novel_models.Act act;
  final int actIndex;
  final bool isExpanded;
  final List<novel_models.Chapter> chaptersToDisplay;
  final String? activeChapterId;

  _ActItemData({
    required this.act,
    required this.actIndex,
    required this.isExpanded,
    required this.chaptersToDisplay,
    required this.activeChapterId,
  });
}

// 可展开的文本组件
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({
    required this.text,
    required this.isActiveScene,
    this.maxLines = 8,
  });

  final String text;
  final bool isActiveScene;
  final int maxLines;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;
  bool _isTextOverflowing = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 检查文本是否会溢出
        final textSpan = TextSpan(
          text: widget.text,
          style: TextStyle(
            fontSize: 11,
            color: widget.isActiveScene
                ? WebTheme.getTextColor(context)
                : WebTheme.getSecondaryTextColor(context),
            height: 1.4,
          ),
        );
        
        final textPainter = TextPainter(
          text: textSpan,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        );
        
        textPainter.layout(maxWidth: constraints.maxWidth);
        _isTextOverflowing = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: TextStyle(
                fontSize: 11,
                color: widget.isActiveScene
                    ? WebTheme.getTextColor(context)
                    : WebTheme.getSecondaryTextColor(context),
                height: 1.4,
              ),
              maxLines: _isExpanded ? null : widget.maxLines,
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (_isTextOverflowing)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isExpanded ? '收起' : '展开',
                        style: TextStyle(
                          fontSize: 10,
                          color: WebTheme.getPrimaryColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 12,
                        color: WebTheme.getPrimaryColor(context),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// 🚀 优化性能的独立组件 - 移除焦点监听
class _SceneListItem extends StatelessWidget {
  const _SceneListItem({
    required this.scene,
    required this.actId,
    required this.chapterId,
    required this.index,
    required this.onTap,
  });

  final novel_models.Scene scene;
  final String actId;
  final String chapterId;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 🚀 移除BlocBuilder监听，简化组件
    return _SceneItemContent(
      scene: scene,
      index: index,
      isActiveScene: false, // 🚀 暂时移除活跃状态检查
      onTap: onTap,
    );
  }
}

// 🚀 简化场景项内容组件
class _SceneItemContent extends StatelessWidget {
  const _SceneItemContent({
    required this.scene,
    required this.index,
    required this.isActiveScene,
    required this.onTap,
  });

  final novel_models.Scene scene;
  final int index;
  final bool isActiveScene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summaryText = scene.summary.content.isEmpty 
        ? '(无摘要)' 
        : scene.summary.content;

    // 🎯 构建场景UI
    final sceneWidget = Container(
      color: Colors.transparent, // 🚀 移除活跃状态颜色变化
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: WebTheme.getPrimaryColor(context).withOpacity(0.1),
          highlightColor: WebTheme.getPrimaryColor(context).withOpacity(0.05),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 场景图标指示器 - 简化
                    Icon(
                      Icons.article_outlined, // 🚀 统一使用outline图标
                      size: 12, 
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    const SizedBox(width: 6),
                    
                    // 场景标题
                    Expanded(
                      child: Text(
                        scene.title.isNotEmpty ? scene.title : 'Scene ${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500, // 🚀 统一字重
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                    ),
                    
                    // 最后编辑时间
                    Text(
                      _formatTimestamp(scene.lastEdited),
                      style: TextStyle(
                        fontSize: 9,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    
                    // 字数显示 - 简化
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey100,
                      child: Text(
                        '${scene.wordCount}',
                        style: TextStyle(
                          fontSize: 9,
                          color: WebTheme.getSecondaryTextColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 6),
                
                // 场景摘要 - 使用可展开组件
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey50 : WebTheme.grey50,
                  child: _ExpandableText(
                    text: summaryText,
                    isActiveScene: false, // 🚀 移除活跃状态
                    maxLines: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // 🎯 包装为可拖动的上下文项
    if (scene.id.isNotEmpty) {
      final dragData = ContextDragData(
        id: 'scene_${scene.id}', // 添加前缀以标识类型
        type: ContextSelectionType.scenes,
        title: scene.title.isNotEmpty ? scene.title : 'Scene ${index + 1}',
        subtitle: summaryText.length > 50 
            ? '${summaryText.substring(0, 50)}...' 
            : summaryText,
        metadata: {
          'sceneId': scene.id,
          'wordCount': scene.wordCount,
        },
      );
      
      return DraggableContextItem(
        data: dragData,
        enableDrag: true,
        onDragStarted: () {
          AppLogger.d('ChapterDirectoryTab', '🎯 开始拖动场景: ${scene.title}');
        },
        child: sceneWidget,
      );
    }
    
    return sceneWidget;
  }

  // 格式化时间戳为友好格式
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 7) {
      return '${timestamp.month}/${timestamp.day}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}

class _NoScenesWidget extends StatelessWidget {
  const _NoScenesWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Center(
        child: Text(
          '本章节暂无场景',
          style: TextStyle(
            fontSize: 11,
            color: WebTheme.getSecondaryTextColor(context),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// 🚀 优化：独立的章节组件 - 移除焦点监听和动画
class _ChapterItem extends StatefulWidget {
  const _ChapterItem({
    required this.act,
    required this.chapter,
    required this.chapterNumberInAct,
    required this.searchText,
    required this.expandedChapters,
    required this.onToggleChapter,
    required this.onNavigateToChapter,
  });

  final novel_models.Act act;
  final novel_models.Chapter chapter;
  final int chapterNumberInAct;
  final String searchText;
  final Map<String, bool> expandedChapters;
  final Function(String) onToggleChapter;
  final Function(String, String) onNavigateToChapter;

  @override
  State<_ChapterItem> createState() => _ChapterItemState();
}

class _ChapterItemState extends State<_ChapterItem> {
  @override
  Widget build(BuildContext context) {
    final isChapterExpandedForScenes = widget.expandedChapters[widget.chapter.id] ?? false;
    
    // 🚀 优化：只在展开时才过滤场景
    List<novel_models.Scene> scenesToDisplay = widget.chapter.scenes;
    if (widget.searchText.isNotEmpty) {
      scenesToDisplay = widget.chapter.scenes.where((scene) => 
        scene.summary.content.toLowerCase().contains(widget.searchText.toLowerCase())
      ).toList();
    }

    // 🎯 构建章节标题行
    final chapterHeader = Material(
            color: Colors.transparent,
            child: InkWell(
              splashColor: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              highlightColor: WebTheme.getPrimaryColor(context).withOpacity(0.05),
              onTap: () => widget.onToggleChapter(widget.chapter.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    // 🚀 移除动画，简化箭头图标
                    Transform.rotate(
                      angle: isChapterExpandedForScenes ? 0.0 : -1.5708,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    
                    // 🚀 移除活跃状态指示器
                    
                    Expanded(
                      child: Text(
                        '第${widget.chapterNumberInAct}章：${widget.chapter.title}',
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.w500, // 🚀 统一字重
                          color: WebTheme.getTextColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // 简化跳转按钮
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onNavigateToChapter(widget.act.id, widget.chapter.id),
                        child: Tooltip(
                          message: '跳转到此章节',
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.shortcut_rounded, 
                              size: 14,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey100,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notes_outlined,
                            size: 8,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${widget.chapter.scenes.length}',
                            style: TextStyle(
                              fontSize: 9,
                              color: WebTheme.getSecondaryTextColor(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
    
    // 🎯 包装章节标题为可拖动的
    final draggableHeader = widget.chapter.id.isNotEmpty
        ? DraggableContextItem(
            data: ContextDragData(
              id: 'chapter_${widget.chapter.id}',
              type: ContextSelectionType.chapters,
              title: '第${widget.chapterNumberInAct}章：${widget.chapter.title}',
              subtitle: '${widget.chapter.scenes.length}个场景',
              metadata: {
                'chapterId': widget.chapter.id,
                'actId': widget.act.id,
                'sceneCount': widget.chapter.scenes.length,
              },
            ),
            enableDrag: true,
            onDragStarted: () {
              AppLogger.d('ChapterDirectoryTab', '🎯 开始拖动章节: ${widget.chapter.title}');
            },
            child: chapterHeader,
          )
        : chapterHeader;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 1),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
        border: Border.all(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          draggableHeader,
          // 🚀 优化：只有展开时才构建场景列表
          if (isChapterExpandedForScenes)
            _buildScenesList(
              widget.act.id, 
              widget.chapter, 
              widget.searchText,
              scenesToDisplay,
            ),
        ],
      ),
    );
  }

  Widget _buildScenesList(
    String actId, 
    novel_models.Chapter chapter, 
    String searchText,
    List<novel_models.Scene> scenesToDisplay,
  ) {
    if (chapter.scenes.isEmpty) {
      return const _NoScenesWidget();
    }

    if (scenesToDisplay.isEmpty && searchText.isNotEmpty) {
      return const SizedBox.shrink();
    } else if (scenesToDisplay.isEmpty) {
      return const _NoScenesWidget();
    }

    // 🚀 使用ListView.builder替代原来的ListView.builder（优化itemExtent）
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
      itemCount: scenesToDisplay.length,
      // 🚀 添加itemExtent提高性能，根据场景项的大概高度估算
      itemExtent: null, // 保持动态高度以适应可展开文本
      itemBuilder: (context, index) {
        final scene = scenesToDisplay[index];
        return _SceneListItem(
          scene: scene,
          actId: actId,
          chapterId: chapter.id,
          index: index,
          onTap: () => widget.onNavigateToChapter(actId, chapter.id),
        );
      },
    );
  }
}

/// 章节目录标签页组件
class ChapterDirectoryTab extends StatefulWidget {
  const ChapterDirectoryTab({super.key, required this.novel});
  final NovelSummary novel;

  @override
  State<ChapterDirectoryTab> createState() => _ChapterDirectoryTabState();
}

class _ChapterDirectoryTabState extends State<ChapterDirectoryTab> 
    with AutomaticKeepAliveClientMixin<ChapterDirectoryTab> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedChapters = {};
  String _searchText = '';
  EditorScreenController? _editorController; // 改为可空类型

  // New state for managing expanded acts
  final Map<String, bool> _expandedActs = {};
  StreamSubscription<EditorState>? _editorBlocSubscription;
  StreamSubscription<NovelStructureUpdatedEvent>? _novelStructureUpdatedSubscription; // Added subscription
  
  // 🚀 新增：缓存上次的状态，避免不必要的同步
  String? _lastSyncedActiveActId;
  bool _hasInitialized = false;

  @override
  bool get wantKeepAlive => true; // 🚀 保持页面存活状态

  @override
  void initState() {
    super.initState();
    // 延迟获取EditorScreenController，使用Consumer或在build中获取
    
    // 监听搜索文本变化
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchText = _searchController.text;
        });
      }
    });
    
    // 使用postFrameCallback确保在widget树构建完成后再访问Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWithProvider();
    });
  }

  void _initializeWithProvider() {
    if (!mounted || _hasInitialized) return;
    
    try {
      _editorController = Provider.of<EditorScreenController>(context, listen: false);
      
      // 加载 SidebarBloc 数据
      final sidebarBloc = context.read<SidebarBloc>();
      final editorBloc = context.read<EditorBloc>(); // Get EditorBloc

      // 🚀 修复：一次性初始状态同步，不在build中重复调用
      _syncActiveActExpansion(editorBloc.state, sidebarBloc.state);

      _editorBlocSubscription = editorBloc.stream.listen((editorState) {
        _syncActiveActExpansion(editorState, context.read<SidebarBloc>().state);
        if (mounted) {
          setState(() {}); // Rebuild to reflect active act/chapter highlighting
        }
      });

      // Listen for novel structure updates from the EventBus
      _novelStructureUpdatedSubscription = EventBus.instance.on<NovelStructureUpdatedEvent>().listen((event) {
        if (!mounted || event.novelId != widget.novel.id) return;

        // 仅在初始化阶段用全量加载；其余使用增量更新，避免重复全量请求
        if (event.updateType == 'CHAPTER_ADDED') {
          sidebarBloc.add(ApplyIncrementalStructureUpdate(
            novelId: widget.novel.id,
            actId: event.data['actId']?.toString(),
            chapterId: event.data['chapterId']?.toString(),
            chapterTitle: 'AI生成章节',
          ));
          return;
        }
        if (event.updateType == 'SCENE_ADDED') {
          sidebarBloc.add(ApplyIncrementalStructureUpdate(
            novelId: widget.novel.id,
            chapterId: event.data['chapterId']?.toString(),
            sceneId: event.data['sceneId']?.toString(),
          ));
          return;
        }

        // 其他类型保留原逻辑（如遇到需要可再细化）
        AppLogger.i('ChapterDirectoryTab', 
          'Received NovelStructureUpdatedEvent: ${event.updateType}, using full reload as fallback');
        sidebarBloc.add(LoadNovelStructure(widget.novel.id));
      });
      
      // 使用日志记录当前状态
      if (sidebarBloc.state is SidebarInitial) {
        AppLogger.i('ChapterDirectoryTab', 'SidebarBloc 处于初始状态，开始加载小说结构');
        // 首次加载
        sidebarBloc.add(LoadNovelStructure(widget.novel.id));
      } else if (sidebarBloc.state is SidebarLoaded) {
        AppLogger.i('ChapterDirectoryTab', 'SidebarBloc 已加载，使用已有数据');
        // 如果已经加载，检查一下是否是当前小说的数据
        final state = sidebarBloc.state as SidebarLoaded;
        if (state.novelStructure.id != widget.novel.id) {
          AppLogger.w('ChapterDirectoryTab', 
            '当前加载的小说(${state.novelStructure.id})与目标小说(${widget.novel.id})不同，重新加载');
          sidebarBloc.add(LoadNovelStructure(widget.novel.id));
        } else {
          // 如果已经是当前小说，检查每个章节是否有场景
          int chaptersWithoutScenes = 0;
          for (final act in state.novelStructure.acts) {
            for (final chapter in act.chapters) {
              if (chapter.scenes.isEmpty) {
                chaptersWithoutScenes++;
              }
            }
          }
          
          if (chaptersWithoutScenes > 0) {
            AppLogger.i('ChapterDirectoryTab', 
              '发现 $chaptersWithoutScenes 个章节没有场景数据，重新加载小说结构');
            sidebarBloc.add(LoadNovelStructure(widget.novel.id));
          }
        }
      } else if (sidebarBloc.state is SidebarError) {
        AppLogger.e('ChapterDirectoryTab', 
          '之前加载小说结构失败，重试: ${(sidebarBloc.state as SidebarError).message}');
        // 之前加载失败，重试
        sidebarBloc.add(LoadNovelStructure(widget.novel.id));
      } else {
        AppLogger.w('ChapterDirectoryTab', '未知的SidebarBloc状态，重新加载');
        sidebarBloc.add(LoadNovelStructure(widget.novel.id));
      }
      
      _hasInitialized = true;
    } catch (e) {
      AppLogger.e('ChapterDirectoryTab', '初始化Provider时出错: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editorBlocSubscription?.cancel(); // Cancel subscription
    _novelStructureUpdatedSubscription?.cancel(); // Cancel new subscription
    super.dispose();
  }

  void _syncActiveActExpansion(EditorState editorState, SidebarState sidebarState) {
    if (!mounted) return; // 🚀 安全检查：确保组件仍然挂载
    
    if (editorState is EditorLoaded && editorState.activeActId != null) {
      final activeActId = editorState.activeActId!;
      
      // 🚀 优化：避免重复同步相同的activeActId
      if (_lastSyncedActiveActId == activeActId) {
        return;
      }
      
      if (sidebarState is SidebarLoaded) {
        bool actExists = sidebarState.novelStructure.acts.any((act) => act.id == activeActId);
        if (actExists && !(_expandedActs[activeActId] ?? false)) {
          // 🚀 修复：简化逻辑，直接在 mounted 检查后调用 setState
          setState(() {
            _expandedActs[activeActId] = true;
            _lastSyncedActiveActId = activeActId;
          });
        } else {
          _lastSyncedActiveActId = activeActId;
        }
      }
    }
  }
  
  // Toggle Act expansion state
  void _toggleAct(String actId) {
    if (mounted) {
      setState(() {
        _expandedActs[actId] = !(_expandedActs[actId] ?? false);
      });
    }
  }

  // 切换章节展开状态
  void _toggleChapter(String chapterId) async {
    final isCurrentlyExpanded = _expandedChapters[chapterId] ?? false;
    
    setState(() {
      _expandedChapters[chapterId] = !isCurrentlyExpanded;
    });

    if (!isCurrentlyExpanded) {
      AppLogger.i('ChapterDirectoryTab', '展开章节: $chapterId');
      // 场景预加载逻辑已移除
    } else {
      AppLogger.i('ChapterDirectoryTab', '收起章节: $chapterId');
    }
  }
  
  void _navigateToChapter(String actId, String chapterId) {
    final editorBloc = context.read<EditorBloc>();
    AppLogger.i('ChapterDirectoryTab', '准备跳转到章节: ActID=$actId, ChapterID=$chapterId');

    // 1. 设置活动章节和卷（这将触发EditorBloc状态更新）
    // 同时也将这个章节设置为焦点章节
    editorBloc.add(SetActiveChapter(
      actId: actId,
      chapterId: chapterId,
    ));
    editorBloc.add(SetFocusChapter(chapterId: chapterId));
    
    // 🚀 新增：点击章节目录默认进入沉浸模式
    AppLogger.i('ChapterDirectoryTab', '切换到沉浸模式: $chapterId');
    editorBloc.add(SwitchToImmersiveMode(chapterId: chapterId));


    // 2. 确保目标章节在视图中
    // 延迟执行，等待Bloc状态更新和UI重建
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return; // Check if the widget is still in the tree
      
      // 如果_editorController为空，尝试重新获取
      if (_editorController == null) {
        try {
          _editorController = Provider.of<EditorScreenController>(context, listen: false);
        } catch (e) {
          AppLogger.e('ChapterDirectoryTab', '无法获取EditorScreenController: $e');
          return;
        }
      }
      
      if (_editorController?.editorMainAreaKey.currentState != null) {
        AppLogger.i('ChapterDirectoryTab', '通过EditorMainArea滚动到章节: $chapterId');
        _editorController!.editorMainAreaKey.currentState!.scrollToChapter(chapterId); 
      } else {
        AppLogger.w('ChapterDirectoryTab', 'EditorMainAreaKey.currentState为空，无法滚动到章节');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🚀 必须调用父类的build方法
    
    // 🚀 优化：使用 BlocConsumer 分离监听和构建逻辑
    return BlocConsumer<SidebarBloc, SidebarState>(
      listener: (context, state) {
        // 🚀 仅在这里处理状态变化的副作用，不触发重建
        if (state is SidebarLoaded && mounted) {
          final editorState = context.read<EditorBloc>().state;
          _syncActiveActExpansion(editorState, state);
        }
      },
      builder: (context, sidebarState) {
        if (sidebarState is SidebarLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (sidebarState is SidebarLoaded) {
          return _buildMainContent(sidebarState);
        } else if (sidebarState is SidebarError) {
          return _buildErrorState(sidebarState);
        } else {
          return _buildInitialState();
        }
      },
    );
  }
  
  // 🚀 将主要内容提取为独立方法，提高可读性
  Widget _buildMainContent(SidebarLoaded sidebarState) {
    return Container(
      color: WebTheme.getBackgroundColor(context), // 🚀 修复：使用动态背景色
      child: Column(
        children: [
          // 搜索区域
          _buildSearchSection(),
          
          // 章节列表
          Expanded(
            child: sidebarState.novelStructure.acts.isEmpty
                ? _buildEmptyState()
                : _buildActList(sidebarState.novelStructure),
          ),
        ],
      ),
    );
  }
  
  // 🚀 错误状态组件
  Widget _buildErrorState(SidebarError sidebarState) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: WebTheme.error, size: 48),
          const SizedBox(height: 16),
          Text('加载目录失败: ${sidebarState.message}', 
            style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // 重新加载
              context.read<SidebarBloc>().add(LoadNovelStructure(widget.novel.id));
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
  
  // 🚀 初始状态组件
  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('正在初始化目录...', style: TextStyle(color: WebTheme.getSecondaryTextColor(context))),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
  
  Widget _buildSearchSection() {
    return Container(
      color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
      padding: const EdgeInsets.all(8.0),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey100,
          border: Border.all(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300),
        ),
        child: AppSearchField(
          controller: _searchController,
          hintText: '搜索章节和场景...',
          height: 30,
          onChanged: (value) {
            // 搜索功能已通过监听器处理
          },
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 56, color: WebTheme.grey300),
          const SizedBox(height: 20),
          Text(
            '暂无章节或卷',
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.w600, 
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '小说结构创建中，请稍后再试',
              style: TextStyle(fontSize: 12, color: WebTheme.getSecondaryTextColor(context)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActList(novel_models.Novel novel) {
    // 🚀 移除EditorBloc监听，简化逻辑
    String? activeChapterId; // 保留用于传递，但不再使用

    // 🚀 预处理所有要显示的卷数据
    List<_ActItemData> actItemsData = [];

    for (int actIndex = 0; actIndex < novel.acts.length; actIndex++) {
      final act = novel.acts[actIndex];
      bool isActExpanded = _expandedActs[act.id] ?? false;

      List<novel_models.Chapter> chaptersToShowInAct = act.chapters;
      bool actMatchesSearch = true; // Assume true if no search text

      if (_searchText.isNotEmpty) {
        // Filter chapters within this act
        chaptersToShowInAct = act.chapters.where((chapter) {
          bool chapterTitleMatches = chapter.title.toLowerCase().contains(_searchText.toLowerCase());
          bool sceneMatches = chapter.scenes.any((scene) => scene.summary.content.toLowerCase().contains(_searchText.toLowerCase()));
          return chapterTitleMatches || sceneMatches;
        }).toList();

        bool actTitleMatches = act.title.toLowerCase().contains(_searchText.toLowerCase());
        // Act is shown if its title matches OR it has chapters that match
        if (!actTitleMatches && chaptersToShowInAct.isEmpty) {
          continue; // Skip this act if neither title nor children match
        }
        actMatchesSearch = true; // Act is relevant to search
      }
      
      if (actMatchesSearch) {
        actItemsData.add(_ActItemData(
          act: act,
          actIndex: actIndex,
          isExpanded: isActExpanded,
          chaptersToDisplay: chaptersToShowInAct,
          activeChapterId: activeChapterId,
        ));
      }
    }
    
    if (actItemsData.isEmpty && _searchText.isNotEmpty) {
       return _buildNoSearchResults();
    }

    // 🚀 使用ListView.builder替代Column
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: actItemsData.length,
      itemBuilder: (context, index) {
        final actData = actItemsData[index];
        return _buildActItem(
          actData.act,
          actData.actIndex,
          actData.isExpanded,
          actData.chaptersToDisplay,
          actData.activeChapterId,
        );
      },
    );
  }

  Widget _buildActItem(
    novel_models.Act act,
    int actIndex,
    bool isExpanded,
    List<novel_models.Chapter> chaptersToDisplay,
    String? activeChapterId,
  ) {
    // Main column children for the Act item
    List<Widget> mainColumnChildren = [];

    // Act Title Widget - 简化，移除焦点状态
    Widget actTitleWidget = Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        highlightColor: WebTheme.getPrimaryColor(context).withOpacity(0.05),
        onTap: () => _toggleAct(act.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              // 🚀 移除动画，简化箭头
              Transform.rotate(
                angle: isExpanded ? 0.0 : -1.5708, // 0 or -90 degrees
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
              const SizedBox(width: 6),
              
              // 🚀 移除活跃状态指示器
              
              Expanded(
                child: Text(
                  act.title.isNotEmpty ? '第${actIndex + 1}卷: ${act.title}' : '第${actIndex + 1}卷',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context), // 🚀 统一颜色
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey100, // 🚀 修复：使用动态背景色
                child: Text(
                  '${act.chapters.length}章', // Display total chapters in this act
                  style: TextStyle(
                    fontSize: 10,
                    color: WebTheme.getSecondaryTextColor(context), // 🚀 统一颜色
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    mainColumnChildren.add(actTitleWidget);

    // int finalChapterCountForThisAct = 0; // Local count for this act

    if (isExpanded) {
      Widget chaptersSectionWidget;
      if (chaptersToDisplay.isNotEmpty) {
        chaptersSectionWidget = Container(
          color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
          padding: const EdgeInsets.only(top: 2.0, bottom: 2.0, left: 4.0, right: 4.0),
          // 🚀 直接在ListView.builder中构建章节项，避免预先创建列表
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: chaptersToDisplay.length,
            itemBuilder: (context, chapterIndex) {
              final chapter = chaptersToDisplay[chapterIndex];
              final chapterNumberInAct = chapterIndex + 1; // Chapter number within this act
              
              return _ChapterItem(
                act: act,
                chapter: chapter,
                chapterNumberInAct: chapterNumberInAct,
                searchText: _searchText,
                expandedChapters: _expandedChapters,
                onToggleChapter: _toggleChapter,
                onNavigateToChapter: _navigateToChapter,
              );
            },
          ),
        );
      } else if (_searchText.isNotEmpty && chaptersToDisplay.isEmpty) {
        // If searching and this act has no matching chapters to display
        chaptersSectionWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Text(
            '此卷内无匹配章节',
            style: TextStyle(fontSize: 11, color: WebTheme.getSecondaryTextColor(context), fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        );
      } else if (act.chapters.isEmpty) {
         // If the act originally has no chapters
        chaptersSectionWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Text(
            '此卷下暂无章节',
            style: TextStyle(fontSize: 11, color: WebTheme.getSecondaryTextColor(context), fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        );
      } else {
        // Fallback for other cases, e.g. chapters exist but all filtered out by a non-chapter-title search
         chaptersSectionWidget = const SizedBox.shrink(); // Or a more specific message
      }
      
      mainColumnChildren.add(chaptersSectionWidget);
    }

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
        border: Border(bottom: BorderSide(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mainColumnChildren, // Use the prepared list of widgets
      ),
    );
  }
  
  

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: WebTheme.grey400),
          const SizedBox(height: 16),
          Text(
            '没有匹配的卷、章节或场景',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试其他关键词重新搜索',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('清除搜索'),
            onPressed: () {
              _searchController.clear();
              if (mounted) {
                setState(() {
                  _searchText = '';
                });
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: WebTheme.getPrimaryColor(context),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
