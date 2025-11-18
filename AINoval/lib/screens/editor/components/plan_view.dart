import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor;
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/components/editable_title.dart';
import 'package:ainoval/screens/editor/widgets/menu_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 大纲视图组件 - 显示小说的整体结构和各场景摘要
/// 支持Act、Chapter、Scene的层级管理和编辑功能
/// 🚀 重构：现在使用EditorBloc统一管理数据，提供无感刷新功能
class PlanView extends StatefulWidget {
  const PlanView({
    super.key,
    required this.novelId,
    required this.editorBloc, // 🚀 修改：使用EditorBloc替代PlanBloc
    this.onSwitchToWrite,
  });

  final String novelId;
  final editor.EditorBloc editorBloc; // 🚀 修改：改为EditorBloc
  final VoidCallback? onSwitchToWrite;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 🚀 修改：使用EditorBloc的事件
    widget.editorBloc.add(const editor.SwitchToPlanView());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebTheme.getMaterialWrapper(
      child: BlocBuilder<editor.EditorBloc, editor.EditorState>(
        bloc: widget.editorBloc,
        builder: (context, state) {
          // 🚀 修改：处理EditorState而不是PlanState
          if (state is! editor.EditorLoaded) {
            return Center(
              child: CircularProgressIndicator(color: WebTheme.getPrimaryColor(context)),
            );
          }

          final editorState = state;

          // 显示错误信息
          if (editorState.errorMessage != null) {
            return Center(
              child: Text(
                '加载失败: ${editorState.errorMessage}',
                style: TextStyle(color: WebTheme.getTextColor(context)),
              ),
            );
          }

          final novel = editorState.novel;

          return Container(
            // 使用动态背景色，兼容明暗主题
            color: WebTheme.getSurfaceColor(context),
            child: Column(
              children: [
                // 主要内容区 - 使用完全虚拟化的滚动
                Expanded(
                  child: _VirtualizedPlanView(
                    novel: novel,
                    novelId: widget.novelId,
                    editorBloc: widget.editorBloc,
                    onSwitchToWrite: widget.onSwitchToWrite,
                    scrollController: _scrollController,
                  ),
                ),
                // 底部工具栏
                _PlanToolbar(editorBloc: widget.editorBloc), // 🚀 修改：传递EditorBloc
              ],
            ),
          );
        },
      ),
    );
  }
}

// 已弃用：_ActSection（被虚拟化布局替代）

/// Act标题头部组件
class _ActHeader extends StatelessWidget {
  const _ActHeader({
    required this.act,
    required this.novelId,
    required this.editorBloc, // 🚀 修改：使用EditorBloc
  });

  final novel_models.Act act;
  final String novelId;
  final editor.EditorBloc editorBloc; // 🚀 修改：改为EditorBloc

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 折叠按钮
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: WebTheme.getSecondaryTextColor(context)),
          onPressed: () {
            // TODO(plan): 实现折叠功能
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        // Act标题（可编辑）
        Expanded(
          child: EditableTitle(
            initialText: act.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
            // 仅在提交（回车或失焦）时派发更新
            onSubmitted: (value) {
              editorBloc.add(editor.UpdateActTitle(
                actId: act.id,
                title: value,
              ));
            },
          ),
        ),
        // 添加章节按钮
        _SmallIconButton(
          icon: Icons.add,
          tooltip: '添加章节',
          onPressed: () {
            // 🚀 修改：使用EditorBloc事件
            editorBloc.add(editor.AddNewChapter(
              novelId: novelId,
              actId: act.id,
            ));
          },
        ),
        const SizedBox(width: 4),
        // 更多操作菜单（统一下拉样式）
        MenuBuilder.buildActMenu(
          context: context,
          editorBloc: editorBloc,
          actId: act.id,
          onRenamePressed: null,
          width: 220,
          align: 'right',
        ),
      ],
    );
  }
}

/// 章节卡片组件 - 自适应高度显示章节及其场景
// 已弃用：_ChapterCard（使用 _OptimizedChapterCard 取代）

/// 章节标题头部
class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.actId,
    required this.chapter,
    required this.editorBloc,
  });

  final String actId;
  final novel_models.Chapter chapter;
  final editor.EditorBloc editorBloc;

  @override
  Widget build(BuildContext context) {
    // 计算总字数
    final totalWords = chapter.scenes.fold<int>(
      0, 
      (sum, scene) => sum + (scene.content.length),
    );

    return Container(
      height: 30, // 🚀 修改：设置固定高度，章节头部缩短为原来的三分之一
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0), // 🚀 修改：去掉垂直内边距，使用固定高度
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: WebTheme.grey200)),
      ),
      child: Row(
        children: [
          // 拖拽手柄
          Icon(Icons.drag_indicator, size: 14, color: WebTheme.getSecondaryTextColor(context)),
          const SizedBox(width: 6),
          // 章节标题（可编辑）
          Expanded(
            child: EditableTitle(
              initialText: chapter.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              // 仅在提交（回车或失焦）时派发更新
              onSubmitted: (value) {
                editorBloc.add(editor.UpdateChapterTitle(
                  actId: actId,
                  chapterId: chapter.id,
                  title: value,
                ));
              },
            ),
          ),
          // 字数统计
          if (totalWords > 0) ...[
            Text(
              '$totalWords Words',
              style: TextStyle(
                fontSize: 11,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 编辑按钮
          _SmallIconButton(
            icon: Icons.edit,
            tooltip: '编辑章节',
            onPressed: () {
              _showEditDialog(
                context: context,
                title: '编辑章节标题',
                initialValue: chapter.title,
                onSave: (newTitle) {
                  editorBloc.add(editor.UpdateChapterTitle(
                    actId: actId,
                    chapterId: chapter.id,
                    title: newTitle,
                  ));
                },
              );
            },
          ),
          // 更多操作（统一下拉样式）
          MenuBuilder.buildChapterMenu(
            context: context,
            editorBloc: editorBloc,
            actId: actId,
            chapterId: chapter.id,
            onRenamePressed: null,
            width: 220,
            align: 'right',
          ),
        ],
      ),
    );
  }
}

/// 场景项组件 - 单个场景的显示和交互
class _SceneItem extends StatefulWidget {
  const _SceneItem({
    required this.actId,
    required this.chapterId,
    required this.scene,
    required this.sceneNumber,
    required this.novelId,
    required this.editorBloc,
  });

  final String actId;
  final String chapterId;
  final novel_models.Scene scene;
  final int sceneNumber;
  final String novelId;
  final editor.EditorBloc editorBloc;

  @override
  State<_SceneItem> createState() => _SceneItemState();
}

class _SceneItemState extends State<_SceneItem> {
  late TextEditingController _summaryController;
  bool _isEditing = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: widget.scene.summary.content);
    _summaryController.addListener(_onSummaryChanged);
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  void _onSummaryChanged() {
    final hasChanges = _summaryController.text != widget.scene.summary.content;
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  void _saveSummary() {
    if (_hasUnsavedChanges) {
      // 🚀 修改：使用EditorBloc的UpdateSummary事件
      widget.editorBloc.add(editor.UpdateSummary(
        novelId: widget.novelId,
        actId: widget.actId,
        chapterId: widget.chapterId,
        sceneId: widget.scene.id,
        summary: _summaryController.text,
      ));
      setState(() {
        _hasUnsavedChanges = false;
        _isEditing = false;
      });
    }
  }

  void _navigateToScene() {
    AppLogger.i('PlanView', '准备跳转到场景: ${widget.actId} - ${widget.chapterId} - ${widget.scene.id}');
    // 与章节目录一致：仅设置活动场景与章节，不触发加载或视图切换
    widget.editorBloc.add(editor.SetActiveScene(
      actId: widget.actId,
      chapterId: widget.chapterId,
      sceneId: widget.scene.id,
    ));
    widget.editorBloc.add(editor.SetActiveChapter(
      actId: widget.actId,
      chapterId: widget.chapterId,
    ));
    // 对齐章节目录：设置焦点章节并切换沉浸模式
    widget.editorBloc.add(editor.SetFocusChapter(chapterId: widget.chapterId));
    widget.editorBloc.add(editor.SwitchToImmersiveMode(chapterId: widget.chapterId));
    // 切换到写作视图
    widget.editorBloc.add(const editor.SwitchToWriteView());
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.scene.summary.content.isNotEmpty;
    final wordCount = widget.scene.content.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具栏区域 - 动态背景
          Container(
            height: 32, // 放大头部高度，提升可点击性
            decoration: BoxDecoration(
              color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // 增加垂直内边距
            child: Row(
              children: [
                // 拖拽手柄
                Icon(Icons.drag_indicator, size: 12, color: WebTheme.getSecondaryTextColor(context)),
                const SizedBox(width: 4),
                
                // 场景标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Scene ${widget.sceneNumber}',
                     style: TextStyle(
                       fontSize: 10,
                       fontWeight: FontWeight.w600,
                       color: WebTheme.getSecondaryTextColor(context),
                     ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // 字数统计（如果有）
                if (wordCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: WebTheme.getPrimaryColor(context).withOpacity(0.2), width: 0.5),
                    ),
                    child: Text(
                      '$wordCount Words',
                      style: TextStyle(
                        fontSize: 9,
                      color: WebTheme.getPrimaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                
                const Spacer(),
                
                
                // 跳转按钮
                _SmallIconButton(
                  icon: Icons.launch,
                  size: 16,
                  tooltip: '跳转到场景',
                  onPressed: _navigateToScene,
                ),
                
                const SizedBox(width: 6),
                
                // 编辑切换按钮
                _SmallIconButton(
                  icon: _isEditing ? Icons.visibility : Icons.edit,
                  size: 16,
                  tooltip: _isEditing ? '预览模式' : '编辑模式',
                  onPressed: () {
                    setState(() {
                      _isEditing = !_isEditing;
                    });
                  },
                ),
                
                const SizedBox(width: 6),
                
                // 更多操作菜单
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 12, color: Colors.black54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  offset: const Offset(-40, 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      height: 30,
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 12, color: Colors.red),
                          SizedBox(width: 6),
                          Text('删除场景', style: TextStyle(fontSize: 11, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'delete') {
                      _showDeleteDialog(
                        context: context,
                        title: '删除场景',
                        content: '确定要删除此场景吗？',
                        onConfirm: () {
                          widget.editorBloc.add(editor.DeleteScene(
                            novelId: widget.novelId,
                            actId: widget.actId,
                            chapterId: widget.chapterId,
                            sceneId: widget.scene.id,
                          ));
                        },
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          
          // 摘要内容区域 - 动态背景，支持直接编辑
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: 220,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: _isEditing 
              ? WebTheme.getMaterialWrapper(
                  child: TextField(
                    controller: _summaryController,
                    decoration: WebTheme.getBorderlessInputDecoration(
                      hintText: '输入场景摘要...',
                      context: context,
                    ),
                    style: TextStyle(
                      fontSize: 18,
                      color: WebTheme.getTextColor(context),
                      height: 1.8,
                    ),
                    maxLines: null,
                    minLines: 5,
                    onSubmitted: (_) => _saveSummary(),
                  ),
                )
              : GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditing = true;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    child: hasContent 
                      ? Text(
                          widget.scene.summary.content,
                          style: TextStyle(
                            fontSize: 18,
                            color: WebTheme.getTextColor(context),
                            height: 1.8,
                          ),
                        )
                      : Text(
                          '点击这里添加场景描述...',
                          style: TextStyle(
                            fontSize: 18,
                            color: WebTheme.getSecondaryTextColor(context),
                            fontStyle: FontStyle.italic,
                            height: 1.8,
                          ),
                        ),
                  ),
                ),
          ),
          
          // 底部按钮区域 - 浅灰色背景
          Container(
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _SmallButton(
                  icon: Icons.add,
                  label: 'Codex',
                  onPressed: () {
                    // TODO(plan): 添加Codex功能
                  },
                ),
                const SizedBox(width: 8),
                _SmallButton(
                  icon: Icons.label,
                  label: 'Label',
                  onPressed: () {
                    // TODO(plan): 添加标签功能
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 添加场景按钮
class _AddSceneButton extends StatelessWidget {
  const _AddSceneButton({
    required this.actId,
    required this.chapterId,
    required this.editorBloc,
  });

  final String actId;
  final String chapterId;
  final editor.EditorBloc editorBloc;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(Icons.add, size: 14, color: WebTheme.getSecondaryTextColor(context)),
        label: Text(
          '新场景',
          style: TextStyle(fontSize: 12, color: WebTheme.getSecondaryTextColor(context)),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () {
          editorBloc.add(editor.AddNewScene(
            novelId: editorBloc.novelId,
            actId: actId,
            chapterId: chapterId,
            sceneId: 'scene_${DateTime.now().millisecondsSinceEpoch}',
          ));
        },
      ),
    );
  }
}

/// 添加章节卡片
class _AddChapterCard extends StatelessWidget {
  const _AddChapterCard({
    required this.actId,
    required this.editorBloc,
  });

  final String actId;
  final editor.EditorBloc editorBloc;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : Colors.grey.shade300,
          style: BorderStyle.solid,
        ),
      ),
      child: Material(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            editorBloc.add(editor.AddNewChapter(
              novelId: editorBloc.novelId,
              actId: actId,
            ));
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline, size: 28, color: WebTheme.getSecondaryTextColor(context)),
                const SizedBox(height: 8),
                Text(
                  '新章节',
                  style: TextStyle(fontSize: 13, color: WebTheme.getSecondaryTextColor(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 已弃用：_LazyChapterGrid（被虚拟化布局替代）

// 已弃用：_LazyWrapLayout（被虚拟化布局替代）

/// 添加Act按钮
class _AddActButton extends StatelessWidget {
  const _AddActButton({required this.editorBloc});

  final editor.EditorBloc editorBloc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        icon: Icon(Icons.add, color: WebTheme.getSecondaryTextColor(context)),
        label: Text(
          '添加新Act',
          style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey400 : Colors.grey.shade400),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        onPressed: () {
          editorBloc.add(const editor.AddNewAct());
        },
      ),
    );
  }
}

/// 底部工具栏
class _PlanToolbar extends StatelessWidget {
  const _PlanToolbar({required this.editorBloc});

  final editor.EditorBloc editorBloc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        // 使用动态背景色，兼容暗黑 / 亮色
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          top: BorderSide(
            color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.add_box_outlined,
            label: '添加Act',
            onPressed: () => editorBloc.add(const editor.AddNewAct()),
          ),
          const SizedBox(width: 12),
          _ToolbarButton(
            icon: Icons.format_list_numbered,
            label: '大纲设置',
            onPressed: () {
              // TODO(plan): 实现大纲设置
            },
          ),
          const SizedBox(width: 12),
          _ToolbarButton(
            icon: Icons.filter_alt_outlined,
            label: '筛选',
            onPressed: () {
              // TODO(plan): 实现筛选功能
            },
          ),
          const SizedBox(width: 12),
          _ToolbarButton(
            icon: Icons.settings_outlined,
            label: '选项',
            onPressed: () {
              // TODO(plan): 实现选项功能
            },
          ),
        ],
      ),
    );
  }
}

/// 通用小图标按钮组件
class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 14,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(icon, size: size, color: WebTheme.getSecondaryTextColor(context)),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 8, minHeight: size + 8),
    );

    return tooltip != null 
        ? Tooltip(message: tooltip!, child: button)
        : button;
  }
}

/// 通用小按钮组件
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 12, color: WebTheme.getSecondaryTextColor(context)),
      label: Text(
        label,
        style: TextStyle(fontSize: 10, color: WebTheme.getSecondaryTextColor(context)),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: onPressed,
    );
  }
}

/// 工具栏按钮组件
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: Icon(icon, size: 16, color: WebTheme.getSecondaryTextColor(context)),
      label: Text(
        label,
        style: TextStyle(fontSize: 13, color: WebTheme.getSecondaryTextColor(context)),
      ),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

/// 显示编辑对话框的通用函数
void _showEditDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required Function(String) onSave,
}) {
  final controller = TextEditingController(text: initialValue);
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WebTheme.getSurfaceColor(context),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: WebTheme.getPrimaryColor(context)),
          ),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              onSave(controller.text.trim());
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: WebTheme.getPrimaryColor(context),
            foregroundColor: WebTheme.white,
          ),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 显示删除确认对话框的通用函数
void _showDeleteDialog({
  required BuildContext context,
  required String title,
  required String content,
  required VoidCallback onConfirm,
}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WebTheme.getSurfaceColor(context),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(content, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

/// 完全虚拟化的Plan视图 - 极致性能优化
class _VirtualizedPlanView extends StatelessWidget {
  const _VirtualizedPlanView({
    required this.novel,
    required this.novelId,
    required this.editorBloc,
    this.onSwitchToWrite,
    required this.scrollController,
  });

  final novel_models.Novel novel;
  final String novelId;
  final editor.EditorBloc editorBloc;
  final VoidCallback? onSwitchToWrite;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // 将所有内容展平为一个线性列表，实现真正的虚拟化滚动
    final List<_PlanItem> items = _buildFlatItemList();
    
    return CustomScrollView(
      controller: scrollController,
      cacheExtent: 200.0, // 减少缓存范围，提高性能
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= items.length) return null;
                
                final item = items[index];
                return _buildItemWidget(context, item);
              },
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建展平的项目列表
  List<_PlanItem> _buildFlatItemList() {
    final List<_PlanItem> items = [];
    
    for (int actIndex = 0; actIndex < novel.acts.length; actIndex++) {
      final act = novel.acts[actIndex];
      
      // 添加Act标题项
      items.add(_PlanItem(
        type: _PlanItemType.actHeader,
        act: act,
        actIndex: actIndex,
      ));
      
      // 添加章节项（分批处理，每批最多10个章节）
      const int batchSize = 10;
      for (int batchStart = 0; batchStart < act.chapters.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, act.chapters.length);
        final batchChapters = act.chapters.sublist(batchStart, batchEnd);
        
        items.add(_PlanItem(
          type: _PlanItemType.chapterBatch,
          act: act,
          chapters: batchChapters,
          batchStart: batchStart,
        ));
      }
      
      // 添加"添加章节"按钮
      items.add(_PlanItem(
        type: _PlanItemType.addChapter,
        act: act,
      ));
    }
    
    // 添加"添加Act"按钮
    items.add(_PlanItem(
      type: _PlanItemType.addAct,
    ));
    
    return items;
  }

  /// 构建单个项目的Widget
  Widget _buildItemWidget(BuildContext context, _PlanItem item) {
    switch (item.type) {
      case _PlanItemType.actHeader:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _ActHeader(
            act: item.act!,
            novelId: novelId,
            editorBloc: editorBloc,
          ),
        );
        
      case _PlanItemType.chapterBatch:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0, left: 16.0),
          child: _ChapterBatchWidget(
            act: item.act!,
            chapters: item.chapters!,
            novelId: novelId,
            editorBloc: editorBloc,
            onSwitchToWrite: onSwitchToWrite,
          ),
        );
        
      case _PlanItemType.addChapter:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0, left: 16.0),
          child: SizedBox(
            width: 450,
            child: _AddChapterCard(
              actId: item.act!.id,
              editorBloc: editorBloc,
            ),
          ),
        );
        
      case _PlanItemType.addAct:
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: _AddActButton(editorBloc: editorBloc),
        );
    }
  }
}

/// 章节批次Widget - 一次显示一批章节
class _ChapterBatchWidget extends StatelessWidget {
  const _ChapterBatchWidget({
    required this.act,
    required this.chapters,
    required this.novelId,
    required this.editorBloc,
    this.onSwitchToWrite,
  });

  final novel_models.Act act;
  final List<novel_models.Chapter> chapters;
  final String novelId;
  final editor.EditorBloc editorBloc;
  final VoidCallback? onSwitchToWrite;
  

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每行可以放多少个卡片
        const itemWidth = 450.0;
        const spacing = 16.0;
        final availableWidth = constraints.maxWidth;
        final itemsPerRow = ((availableWidth + spacing) / (itemWidth + spacing)).floor().clamp(1, 10);
        
        // 计算行数
        final totalRows = (chapters.length / itemsPerRow).ceil();
        
        return Column(
          children: List.generate(totalRows, (rowIndex) {
            final startIndex = rowIndex * itemsPerRow;
            final endIndex = (startIndex + itemsPerRow).clamp(0, chapters.length);
            
            return Padding(
              padding: EdgeInsets.only(bottom: rowIndex < totalRows - 1 ? 16.0 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = startIndex; i < endIndex; i++) ...[
                    if (i > startIndex) const SizedBox(width: 16.0),
                    SizedBox(
                      width: 450,
                      child: _OptimizedChapterCard(
                        actId: act.id,
                        chapter: chapters[i],
                        novelId: novelId,
                        editorBloc: editorBloc,
                        onSwitchToWrite: onSwitchToWrite,
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

/// 优化的章节卡片 - 保持原有功能但提升性能
class _OptimizedChapterCard extends StatefulWidget {
  const _OptimizedChapterCard({
    required this.actId,
    required this.chapter,
    required this.novelId,
    required this.editorBloc,
    this.onSwitchToWrite,
  });

  final String actId;
  final novel_models.Chapter chapter;
  final String novelId;
  final editor.EditorBloc editorBloc;
  final VoidCallback? onSwitchToWrite;

  @override
  State<_OptimizedChapterCard> createState() => _OptimizedChapterCardState();
}

class _OptimizedChapterCardState extends State<_OptimizedChapterCard> {
  bool _hasUnsavedInChapter = false;
  String? _unsavedSceneId;
  VoidCallback? _unsavedSceneSave;

  void _handleSceneUnsavedChanged(String sceneId, bool hasUnsaved, String currentSummary, VoidCallback? saveCallback) {
    setState(() {
      if (hasUnsaved) {
        _hasUnsavedInChapter = true;
        _unsavedSceneId = sceneId;
        _unsavedSceneSave = saveCallback;
      } else {
        if (_unsavedSceneId == sceneId) {
          _hasUnsavedInChapter = false;
          _unsavedSceneId = null;
          _unsavedSceneSave = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : Colors.grey.shade300,
          style: BorderStyle.solid,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 章节标题栏
          _ChapterHeader(
            actId: widget.actId,
            chapter: widget.chapter,
            editorBloc: widget.editorBloc,
          ),
          // 场景列表 - 优化版本，限制显示数量
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 场景列表 - 限制最多显示5个场景以提升性能
                ...widget.chapter.scenes.take(5).toList().asMap().entries.map((entry) =>
                  _OptimizedSceneItem(
                    actId: widget.actId,
                    chapterId: widget.chapter.id,
                    scene: entry.value,
                    sceneNumber: entry.key + 1,
                    novelId: widget.novelId,
                    editorBloc: widget.editorBloc,
                    onUnsavedChanged: _handleSceneUnsavedChanged,
                    onSwitchToWrite: widget.onSwitchToWrite,
                  ),
                ),
                // 如果有更多场景，显示省略提示
                if (widget.chapter.scenes.length > 5) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '还有 ${widget.chapter.scenes.length - 5} 个场景...',
                      style: TextStyle(
                        fontSize: 11,
                        color: WebTheme.getSecondaryTextColor(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_hasUnsavedInChapter) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _unsavedSceneSave == null ? null : () {
                            _unsavedSceneSave?.call();
                            setState(() {
                              _hasUnsavedInChapter = false;
                              _unsavedSceneId = null;
                              _unsavedSceneSave = null;
                            });
                          },
                          icon: const Icon(Icons.save, size: 16),
                          label: const Text('保存'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _AddSceneButton(
                          actId: widget.actId,
                          chapterId: widget.chapter.id,
                          editorBloc: widget.editorBloc,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _AddSceneButton(
                    actId: widget.actId,
                    chapterId: widget.chapter.id,
                    editorBloc: widget.editorBloc,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 优化的场景项组件 - 简化版本但保持核心功能
class _OptimizedSceneItem extends StatefulWidget {
  const _OptimizedSceneItem({
    required this.actId,
    required this.chapterId,
    required this.scene,
    required this.sceneNumber,
    required this.novelId,
    required this.editorBloc,
    required this.onUnsavedChanged,
    this.onSwitchToWrite,
  });

  final String actId;
  final String chapterId;
  final novel_models.Scene scene;
  final int sceneNumber;
  final String novelId;
  final editor.EditorBloc editorBloc;
  final void Function(String sceneId, bool hasUnsaved, String currentSummary, VoidCallback? saveCallback) onUnsavedChanged;
  final VoidCallback? onSwitchToWrite;

  @override
  State<_OptimizedSceneItem> createState() => _OptimizedSceneItemState();
}

class _OptimizedSceneItemState extends State<_OptimizedSceneItem> {
  late TextEditingController _summaryController;
  bool _isEditing = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: widget.scene.summary.content);
    _summaryController.addListener(_onSummaryChanged);
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  void _onSummaryChanged() {
    final hasChanges = _summaryController.text != widget.scene.summary.content;
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
      widget.onUnsavedChanged(
        widget.scene.id,
        _hasUnsavedChanges,
        _summaryController.text,
        _hasUnsavedChanges ? _saveSummary : null,
      );
    }
  }

  void _saveSummary() {
    if (_hasUnsavedChanges) {
      widget.editorBloc.add(editor.UpdateSummary(
        novelId: widget.novelId,
        actId: widget.actId,
        chapterId: widget.chapterId,
        sceneId: widget.scene.id,
        summary: _summaryController.text,
      ));
      setState(() {
        _hasUnsavedChanges = false;
        _isEditing = false;
      });
      widget.onUnsavedChanged(
        widget.scene.id,
        false,
        _summaryController.text,
        null,
      );
    }
  }

  void _navigateToScene() {
    // 与章节目录一致：仅设置活动场景与章节，不触发加载或视图切换
    widget.editorBloc.add(editor.SetActiveScene(
      actId: widget.actId,
      chapterId: widget.chapterId,
      sceneId: widget.scene.id,
    ));
    widget.editorBloc.add(editor.SetActiveChapter(
      actId: widget.actId,
      chapterId: widget.chapterId,
    ));
    // 对齐章节目录：设置焦点章节并切换沉浸模式
    widget.editorBloc.add(editor.SetFocusChapter(chapterId: widget.chapterId));
    widget.editorBloc.add(editor.SwitchToImmersiveMode(chapterId: widget.chapterId));
    // 切换到写作视图：优先调用上层回调以关闭Plan覆盖层
    if (widget.onSwitchToWrite != null) {
      widget.onSwitchToWrite!();
    } else {
      widget.editorBloc.add(const editor.SwitchToWriteView());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.scene.summary.content.isNotEmpty;
    final wordCount = widget.scene.content.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具栏区域 - 简化版
          Container(
            height: 28, // 放大高度
            decoration: BoxDecoration(
              color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey100 : WebTheme.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                // 场景标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'S${widget.sceneNumber}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
                
                const SizedBox(width: 6),
                
                // 字数统计（如果有）
                if (wordCount > 0) ...[
                  Text(
                    '${wordCount}w',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.blue.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                
                const Spacer(),
                
                
                // 跳转按钮
                _SmallIconButton(
                  icon: Icons.launch,
                  size: 14,
                  tooltip: '跳转到场景',
                  onPressed: _navigateToScene,
                ),
                
                // 编辑切换按钮
                _SmallIconButton(
                  icon: _isEditing ? Icons.visibility : Icons.edit,
                  size: 14,
                  tooltip: _isEditing ? '预览模式' : '编辑模式',
                  onPressed: () {
                    setState(() {
                      _isEditing = !_isEditing;
                    });
                  },
                ),
              ],
            ),
          ),
          
          // 摘要内容区域 - 放大版
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: 200, // 再放大
            ),
            padding: const EdgeInsets.all(8),
            child: _isEditing 
              ? TextField(
                  controller: _summaryController,
                  decoration: InputDecoration(
                    hintText: '输入场景摘要...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      fontSize: 18,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    color: WebTheme.getTextColor(context),
                    height: 1.8,
                  ),
                  maxLines: null,
                  minLines: 5,
                  onSubmitted: (_) => _saveSummary(),
                )
              : GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditing = true;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    child: hasContent 
                      ? Text(
                          widget.scene.summary.content,
                          style: TextStyle(
                            fontSize: 18,
                            color: WebTheme.getTextColor(context),
                            height: 1.8,
                          ),
                          // 自适应高度，不再省略
                        )
                      : Text(
                          '点击添加场景描述...',
                          style: TextStyle(
                            fontSize: 18,
                            color: WebTheme.getSecondaryTextColor(context),
                            fontStyle: FontStyle.italic,
                            height: 1.8,
                          ),
                        ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// Plan项目类型枚举
enum _PlanItemType {
  actHeader,
  chapterBatch,
  addChapter,
  addAct,
}

/// Plan项目数据类
class _PlanItem {
  const _PlanItem({
    required this.type,
    this.act,
    this.chapters,
    this.actIndex,
    this.batchStart,
  });

  final _PlanItemType type;
  final novel_models.Act? act;
  final List<novel_models.Chapter>? chapters;
  final int? actIndex;
  final int? batchStart;
} 