import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor;
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/screens/editor/widgets/novel_setting_sidebar.dart';
import 'package:ainoval/screens/editor/widgets/snippet_list_tab.dart';
import 'package:ainoval/screens/editor/widgets/snippet_edit_form.dart';
import 'package:ainoval/screens/editor/components/export_dialog.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/user_avatar_menu.dart';
import 'package:ainoval/screens/subscription/subscription_screen.dart';
import 'package:ainoval/screens/editor/components/ai_task_center_panel.dart';

import 'chapter_directory_tab.dart';

/// 保持存活状态的包装器组件
class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class EditorSidebar extends StatefulWidget {
  const EditorSidebar({
    super.key,
    required this.novel,
    required this.tabController,
    this.onOpenAIChat,
    this.onOpenSettings,
    this.onToggleSidebar,
    this.onAdjustWidth,
  });
  final NovelSummary novel;
  final TabController tabController;
  final VoidCallback? onOpenAIChat;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onAdjustWidth;

  @override
  State<EditorSidebar> createState() => _EditorSidebarState();
}

class _EditorSidebarState extends State<EditorSidebar> {
  final TextEditingController _searchController = TextEditingController();
  // String _selectedMode = 'codex';
  
  // 片段列表操作回调
  VoidCallback? _refreshSnippetList; // used via callbacks wiring
  Function(NovelSnippet)? _addSnippetToList; // used via callbacks wiring
  Function(NovelSnippet)? _updateSnippetInList; // used via callbacks wiring
  Function(String)? _removeSnippetFromList; // used via callbacks wiring

  String _selectedBottomBarItem = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 添加重建监控日志 - 现在应该不会频繁触发了
    AppLogger.d('EditorSidebar', '🔄 EditorSidebar.build() 被调用 - 监控重建');
    
    final theme = Theme.of(context);
    
    // 🚀 优化：直接使用父级提供的SettingBloc实例，避免重复创建
    final settingSidebarWidget = BlocProvider.value(
      value: context.read<SettingBloc>(),
      child: NovelSettingSidebar(novelId: widget.novel.id),
    );
          
    return Material(
      color: WebTheme.getBackgroundColor(context),
      child: Container(
        decoration: BoxDecoration(
          color: WebTheme.getBackgroundColor(context),
          border: Border(
            right: BorderSide(
              color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200,
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.03),
              blurRadius: 5,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部应用栏
            _buildAppBar(theme),

            // 标签页导航
            _buildTabBar(theme),

            // 标签页内容
            Expanded(
              child: TabBarView(
                controller: widget.tabController,
                children: [
                  // 设定库标签页（替换原来的Codex标签页）
                  settingSidebarWidget,

                  // 片段标签页
                  Builder(
                    builder: (context) {
                      return SnippetListTab(
                        key: ValueKey('snippet_list_${widget.novel.id}'),
                        novel: widget.novel,
                        onRefreshCallbackChanged: (callback) {
                          _refreshSnippetList = callback;
                        },
                        onAddSnippetCallbackChanged: (callback) {
                          _addSnippetToList = callback;
                        },
                        onUpdateSnippetCallbackChanged: (callback) {
                          _updateSnippetInList = callback;
                        },
                        onRemoveSnippetCallbackChanged: (callback) {
                          _removeSnippetFromList = callback;
                        },
                        onSnippetTap: (snippet) {
                          FloatingSnippetEditor.show(
                            context: context,
                            snippet: snippet,
                            onSaved: (updatedSnippet) {
                              // 判断是创建还是更新
                              if (snippet.id.isEmpty) {
                                // 创建新片段：直接添加到列表
                                _addSnippetToList?.call(updatedSnippet);
                              } else {
                                // 更新现有片段：更新列表中的片段
                                _updateSnippetInList?.call(updatedSnippet);
                              }
                            },
                            onDeleted: (snippetId) {
                              // 删除片段：从列表中移除
                              _removeSnippetFromList?.call(snippetId);
                            },
                          );
                        },
                      );
                    },
                  ),

                  // 章节目录标签页
                  Builder(
                    builder: (context) {
                      // 确保在有Provider访问权限的新BuildContext中构建ChapterDirectoryTab
                      return Consumer<EditorScreenController>(
                        builder: (context, controller, child) {
                          return ChapterDirectoryTab(novel: widget.novel);
                        },
                      );
                    },
                  ),

                  // AI任务中心
                  _KeepAliveWrapper(
                    child: AITaskCenterPanel(),
                  ),
                ],
              ),
            ),

            // 底部导航栏
            _buildBottomBar(theme),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: WebTheme.getBackgroundColor(context),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: 60, // 增加高度以适应新设计
      title: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 返回按钮
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: WebTheme.getSurfaceColor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // 可点击的设置和小说信息区域
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onOpenSettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        // 设置图标
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: WebTheme.getSurfaceColor(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.settings,
                            size: 16,
                            color: WebTheme.getTextColor(context),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // 小说标题和作者信息
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             mainAxisAlignment: MainAxisAlignment.center,
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Text(
                                 widget.novel.title,
                                 style: TextStyle(
                                   fontWeight: FontWeight.w600,
                                   fontSize: 15,
                                   color: WebTheme.getTextColor(context),
                                   height: 1.1,
                                 ),
                                 overflow: TextOverflow.ellipsis,
                                 maxLines: 1,
                               ),
                               Text(
                                 widget.novel.author ?? 'Erminia Osteen',
                                 style: TextStyle(
                                   color: WebTheme.getSecondaryTextColor(context),
                                   fontSize: 11,
                                   fontWeight: FontWeight.w400,
                                   height: 1.0,
                                 ),
                                 overflow: TextOverflow.ellipsis,
                                 maxLines: 1,
                               ),
                             ],
                           ),
                         ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // 右侧操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 侧边栏折叠按钮
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onToggleSidebar,
                      child: Icon(
                        Icons.menu_open,
                        size: 18,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // 调整宽度按钮
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onAdjustWidth,
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
      ),
      child: TabBar(
        controller: widget.tabController,
        labelColor: WebTheme.getTextColor(context),
        unselectedLabelColor: WebTheme.getSecondaryTextColor(context),
        indicatorColor: WebTheme.getTextColor(context),
        indicatorWeight: 2.0, // 减小指示器粗细
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13, // 减小字体大小
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 13, // 减小字体大小
        ),
        dividerColor: Colors.transparent,
        isScrollable: false, // 确保不可滚动，平均分配空间
        labelPadding: const EdgeInsets.symmetric(horizontal: 2.0), // 减小标签内边距
        padding: const EdgeInsets.symmetric(horizontal: 2.0), // 减小整体内边距
        tabs: const [
          Tab(
            icon: Icon(Icons.inventory_2_outlined, size: 18), // 修改图标来反映设定功能
            text: '设定库', // 改为"设定库"
            height: 60, // 与顶部 AppBar 高度一致
          ),
          Tab(
            icon: Icon(Icons.bookmark_border_outlined, size: 18), // 减小图标大小
            text: '片段',
            height: 60, // 与顶部 AppBar 高度一致
          ),
          Tab(
            icon: Icon(Icons.menu_outlined, size: 18), // 目录图标
            text: '章节目录', // "章节目录"
            height: 60, // 与顶部 AppBar 高度一致
          ),
          Tab(
            icon: Icon(Icons.auto_awesome, size: 18), // AI生成图标
            text: 'AI生成',
            height: 60, // 与顶部 AppBar 高度一致
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab({required IconData icon, required String text}) {
    return _KeepAliveWrapper(
      child: Container(
        color: WebTheme.getSurfaceColor(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: WebTheme.getSecondaryTextColor(context)),
              const SizedBox(height: 16),
              Text(
                text,
                style: TextStyle(fontSize: 16, color: WebTheme.getSecondaryTextColor(context)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 当侧边栏宽度较小时，仅显示图标；宽度充足时显示图标+文字
        final bool isCompact = constraints.maxWidth < 240;
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: WebTheme.getBackgroundColor(context),
            border: Border(
              top: BorderSide(
                color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200,
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              // 用户头像菜单
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: UserAvatarMenu(
                  size: 16,
                  showName: false,
                  onMySubscription: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                    );
                  },
                  onOpenSettings: widget.onOpenSettings,
                  onProfile: widget.onOpenSettings, // 个人资料也使用设置面板
                  onAccountSettings: widget.onOpenSettings, // 账户设置使用设置面板
                ),
              ),
              // 使用Expanded包裹SingleChildScrollView来确保按钮能够根据宽度滚动/自适应
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 帮助按钮
                      _buildBottomBarItem(
                        icon: Icons.help_outline,
                        label: '帮助',
                        showLabel: !isCompact,
                        selected: _selectedBottomBarItem == 'Help',
                        onTap: () {
                          setState(() {
                            _selectedBottomBarItem = 'Help';
                          });
                          // TODO: 实现帮助功能
                        },
                      ),
                      // 提示按钮
                      _buildBottomBarItem(
                        icon: Icons.lightbulb_outline,
                        label: '提示词和预设',
                        showLabel: !isCompact,
                        selected: _selectedBottomBarItem == 'Prompts',
                        onTap: () {
                          setState(() {
                            _selectedBottomBarItem = 'Prompts';
                          });
                          final controller = Provider.of<EditorScreenController>(context, listen: false);
                          controller.togglePromptView();
                        },
                      ),
                      // 导出按钮
                      _buildBottomBarItem(
                        icon: Icons.download_outlined,
                        label: '导出',
                        showLabel: !isCompact,
                        selected: _selectedBottomBarItem == 'Export',
                        onTap: () {
                          setState(() {
                            _selectedBottomBarItem = 'Export';
                          });
                          _showExportDialog();
                        },
                      ),
                      // 保存按钮
                      _buildBottomBarItem(
                        icon: Icons.save_outlined,
                        label: '保存',
                        showLabel: !isCompact,
                        selected: _selectedBottomBarItem == 'Save',
                        onTap: () {
                          setState(() {
                            _selectedBottomBarItem = 'Save';
                          });
                          // 手动保存：触发与自动保存一致的SaveContent事件
                          try {
                            final controller = Provider.of<EditorScreenController>(context, listen: false);
                            controller.editorBloc.add(const editor.SaveContent());
                          } catch (e) {
                            AppLogger.w('EditorSidebar', '手动保存触发失败', e);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建底部栏单个按钮
  Widget _buildBottomBarItem({
    required IconData icon,
    required String label,
    bool showLabel = true,
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final isDark = WebTheme.isDarkMode(context);
    
    // 修复选中状态的颜色配置，确保在暗黑模式下文字可见
    final Color foregroundColor;
    final Color backgroundColor;
    
    if (selected) {
      if (isDark) {
        // 暗黑模式下：选中时使用深灰背景+白字
        backgroundColor = WebTheme.darkGrey700;
        foregroundColor = WebTheme.white;
      } else {
        // 亮色模式下：选中时使用深色背景+白字
        backgroundColor = WebTheme.grey800;
        foregroundColor = WebTheme.white;
      }
    } else {
      // 未选中时：透明背景+半透明文字
      backgroundColor = Colors.transparent;
      foregroundColor = WebTheme.getTextColor(context).withOpacity(0.7);
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: foregroundColor,
              ),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: foregroundColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 显示导出对话框
  void _showExportDialog() {
    final controller = Provider.of<EditorScreenController>(context, listen: false);
    final novelId = widget.novel.id;
    final novelTitle = widget.novel.title;
    // 优先尝试从EditorBloc拿到缓存的完整小说，用于导出
    novel_models.Novel? cachedNovel;
    try {
      final state = controller.editorBloc.state;
      if (state is editor.EditorLoaded) {
        cachedNovel = state.novel;
      }
    } catch (_) {}

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ExportDialog(
          novelId: novelId,
          novelTitle: novelTitle,
          cachedNovel: cachedNovel,
        );
      },
    );
  }
}

class _CodexEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
        children: [
          Text(
            'YOUR CODEX IS EMPTY',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The Codex stores information about the world your story takes place in, its inhabitants and more.',
            style: TextStyle(
              color: WebTheme.getSecondaryTextColor(context),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              // 该点击应执行与"+ New Entry"按钮相同的操作
            },
            child: Text(
              '→ Create a new entry by clicking the button above.',
              style: TextStyle(
                color: WebTheme.getTextColor(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

