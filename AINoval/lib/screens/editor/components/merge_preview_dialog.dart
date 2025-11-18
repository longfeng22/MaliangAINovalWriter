import 'package:ainoval/blocs/editor/editor_bloc.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/editor_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/task_repository_impl.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/utils/task_translation.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/loading_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 通用的“预览合并”对话框（从 AI 任务中心抽取）
class MergePreviewDialog extends StatefulWidget {
  const MergePreviewDialog({super.key, required this.event});
  final Map<String, dynamic> event;

  @override
  State<MergePreviewDialog> createState() => _MergePreviewDialogState();
}

class _MergePreviewDialogState extends State<MergePreviewDialog> {
  String _mergeMode = 'append'; // append | replace | new_chapter
  int _insertPosition = -1; // -1 末尾
  String? _generatedSummary;
  String? _generatedContent;
  String? _novelId;
  bool _loadingNovel = true; // 小说结构加载中

  // 标签页状态管理
  int _selectedTabIndex = 0; // 0: 摘要对比, 1: 内容对比

  // 目标选择
  String? _targetChapterId;
  String? _targetSceneId;
  List<Act> _acts = [];
  List<Chapter> _chapters = [];
  List<Scene> _scenesInTargetChapter = [];

  // 当前内容缓存
  String? _currentSummaryCache;
  String? _currentContentCache;

  @override
  void initState() {
    super.initState();

    _currentSummaryCache = null;
    _currentContentCache = null;

    final result = widget.event['result'];
    if (result is Map) {
      final rawSummary = result['generatedSummary']?.toString();
      if (rawSummary != null && rawSummary.isNotEmpty) {
        _generatedSummary = QuillHelper.isValidQuillFormat(rawSummary)
            ? QuillHelper.deltaToText(rawSummary)
            : rawSummary;
      }

      final rawContent = result['generatedContent']?.toString();
      AppLogger.i('AI任务合并', '初始化 - 原始生成内容: ${rawContent?.length ?? 0}个字符');
      AppLogger.i('AI任务合并', '初始化 - 生成内容预览: ${rawContent?.substring(0, 100) ?? "空"}...');

      if (rawContent != null && rawContent.isNotEmpty) {
        _generatedContent = QuillHelper.isValidQuillFormat(rawContent)
            ? QuillHelper.deltaToText(rawContent)
            : rawContent;
        AppLogger.i('AI任务合并', '初始化 - 处理后内容长度: ${_generatedContent?.length ?? 0}');
      } else {
        AppLogger.w('AI任务合并', '初始化 - 生成内容为空或null');
      }
    }
    _novelId = (widget.event['novelId'] ?? (result is Map ? result['novelId'] : null))?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreviewAndTargets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskType = widget.event['taskType']?.toString() ?? '';
    final taskTypeName = TaskTranslation.getTaskTypeName(taskType);

    return Container(
      width: 1300,
      height: 850,
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPreviewHeader(context, taskTypeName),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.dividerColor.withOpacity(0.1),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildContentPreview(context),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.dividerColor.withOpacity(0.1),
                ),
                SizedBox(
                  width: 400,
                  child: _buildConfigPanel(context),
                ),
              ],
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  Widget _buildPreviewHeader(BuildContext context, String taskTypeName) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.preview_outlined,
              size: 24,
              color: WebTheme.getPrimaryColor(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '内容预览与合并',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getOnSurfaceColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '任务类型：$taskTypeName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            iconSize: 24,
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.6),
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildTabButton(context, '摘要对比', 0),
              const SizedBox(width: 12),
              _buildTabButton(context, '内容对比', 1),
              const Spacer(),
              IconButton(
                onPressed: () {
                  _loadPreviewAndTargets();
                },
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 20,
                style: IconButton.styleFrom(
                  foregroundColor: WebTheme.getSecondaryColor(context),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _selectedTabIndex == 0
                  ? _buildSummaryComparison(context)
                  : _buildContentComparison(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryComparison(BuildContext context) {
    return Row(
      key: const ValueKey('summary_comparison'),
      children: [
        Expanded(
          child: _buildContentCard(
            context,
            title: '生成摘要',
            content: _generatedSummary ?? '正在加载摘要...',
            isGenerated: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildContentCard(
            context,
            title: '当前摘要',
            content: _loadCurrentSummaryContent(),
            isGenerated: false,
          ),
        ),
      ],
    );
  }

  Widget _buildContentComparison(BuildContext context) {
    return Row(
      key: const ValueKey('content_comparison'),
      children: [
        Expanded(
          child: _buildContentCard(
            context,
            title: '生成内容',
            content: () {
              AppLogger.i('AI任务合并', '显示生成内容 - 长度: ${_generatedContent?.length ?? 0}');
              return _generatedContent ?? '正在加载内容...';
            }(),
            isGenerated: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildContentCard(
            context,
            title: '当前内容',
            content: _loadCurrentSceneContent(),
            isGenerated: false,
          ),
        ),
      ],
    );
  }

  String _loadCurrentSummaryContent() {
    if (_mergeMode == 'new_chapter') {
      return '(新章节模式，无需对比当前摘要)';
    }
    if (_currentSummaryCache != null) {
      return _currentSummaryCache!;
    }
    if (_targetChapterId != null) {
      _loadCurrentChapterSummary();
      return '正在加载当前章节摘要...';
    }
    return '请选择目标章节以加载摘要';
  }

  String _loadCurrentSceneContent() {
    if (_mergeMode == 'new_chapter') {
      return '(新章节模式，无需对比当前内容)';
    }
    if (_currentContentCache != null) {
      return _currentContentCache!;
    }
    if (_mergeMode == 'replace' && _targetSceneId != null) {
      _loadCurrentSceneContentFromAPI();
      return '正在加载当前场景内容...';
    } else if (_mergeMode == 'append' && _targetChapterId != null) {
      _loadCurrentChapterLastSceneContent();
      return '正在加载章节末尾场景内容...';
    }
    return '请选择目标位置以加载内容';
  }

  Future<void> _loadCurrentChapterSummary() async {
    if (_targetChapterId == null) return;
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final repo = EditorRepositoryImpl(apiClient: api);
      final actId = _findActIdForChapter(_targetChapterId!);
      if (actId != null && _novelId != null) {
        final novel = await repo.getNovel(_novelId!);
        if (novel != null) {
          for (final act in novel.acts) {
            for (final chapter in act.chapters) {
              if (chapter.id == _targetChapterId) {
                if (mounted) {
                  setState(() {
                    final sceneSummaries = chapter.scenes
                        .where((scene) => scene.summary.content.isNotEmpty)
                        .map((scene) {
                          final summaryContent = scene.summary.content;
                          return QuillHelper.isValidQuillFormat(summaryContent)
                              ? QuillHelper.deltaToText(summaryContent)
                              : summaryContent;
                        })
                        .where((summary) => summary.trim().isNotEmpty)
                        .join('\n\n');
                    _currentSummaryCache = sceneSummaries.isNotEmpty ? sceneSummaries : '该章节暂无摘要';
                  });
                }
                return;
              }
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _currentSummaryCache = '无法加载章节摘要';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentSummaryCache = '加载摘要失败: $e';
        });
      }
    }
  }

  Future<void> _loadCurrentSceneContentFromAPI() async {
    if (_targetChapterId == null || _targetSceneId == null) return;
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final repo = EditorRepositoryImpl(apiClient: api);
      final actId = _findActIdForChapter(_targetChapterId!);
      if (actId != null && _novelId != null) {
        final scene = await repo.getSceneContent(_novelId!, actId, _targetChapterId!, _targetSceneId!);
        if (scene != null && mounted) {
          setState(() {
            final plainText = scene.content.isNotEmpty
                ? QuillHelper.deltaToText(scene.content)
                : '该场景暂无内容';
            _currentContentCache = plainText.trim().isNotEmpty ? plainText : '该场景暂无内容';
          });
        } else if (mounted) {
          setState(() {
            _currentContentCache = '无法加载场景内容';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentContentCache = '加载场景内容失败: $e';
        });
      }
    }
  }

  Future<void> _loadCurrentChapterLastSceneContent() async {
    if (_targetChapterId == null) return;
    try {
      if (_scenesInTargetChapter.isNotEmpty) {
        final lastScene = _scenesInTargetChapter.last;
        final api = RepositoryProvider.of<ApiClient>(context);
        final repo = EditorRepositoryImpl(apiClient: api);
        final actId = _findActIdForChapter(_targetChapterId!);
        if (actId != null && _novelId != null) {
          final scene = await repo.getSceneContent(_novelId!, actId, _targetChapterId!, lastScene.id);
          if (scene != null && mounted) {
            setState(() {
              final plainText = scene.content.isNotEmpty
                  ? QuillHelper.deltaToText(scene.content)
                  : '章节末尾场景暂无内容';
              _currentContentCache = plainText.trim().isNotEmpty ? plainText : '章节末尾场景暂无内容';
            });
          } else if (mounted) {
            setState(() {
              _currentContentCache = '无法加载章节末尾内容';
            });
          }
        }
      } else if (mounted) {
        setState(() {
          _currentContentCache = '该章节暂无场景';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentContentCache = '加载章节内容失败: $e';
        });
      }
    }
  }

  Widget _buildTabButton(BuildContext context, String text, int tabIndex) {
    final theme = Theme.of(context);
    final bool isActive = _selectedTabIndex == tabIndex;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = tabIndex;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? WebTheme.getPrimaryColor(context).withOpacity(0.2)
                  : theme.dividerColor.withOpacity(0.1),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? (tabIndex == 0 ? Icons.summarize : Icons.article)
                    : (tabIndex == 0 ? Icons.summarize_outlined : Icons.article_outlined),
                size: 16,
                color: isActive
                    ? WebTheme.getPrimaryColor(context)
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? WebTheme.getPrimaryColor(context)
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context, {
    required String title,
    required String content,
    required bool isGenerated,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isGenerated
                  ? WebTheme.getPrimaryColor(context).withOpacity(0.05)
                  : theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isGenerated ? Icons.auto_awesome : Icons.article_outlined,
                  size: 18,
                  color: isGenerated
                      ? WebTheme.getPrimaryColor(context)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isGenerated
                        ? WebTheme.getPrimaryColor(context)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  content.isEmpty ? '(无内容)' : content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: WebTheme.getOnSurfaceColor(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '合并配置',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: WebTheme.getOnSurfaceColor(context),
            ),
          ),
          const SizedBox(height: 20),
          _buildConfigSection(
            context,
            title: '合并模式',
            child: _buildMergeModeSelector(context),
          ),
          const SizedBox(height: 20),
          if (_chapters.isNotEmpty)
            _buildConfigSection(
              context,
              title: '目标章节',
              child: _buildChapterSelector(context),
            ),
          const SizedBox(height: 20),
          if (_mergeMode == 'append')
            _buildConfigSection(
              context,
              title: '插入位置',
              child: _buildPositionSelector(context),
            ),
          if (_mergeMode == 'replace')
            _buildConfigSection(
              context,
              title: '目标场景',
              child: _buildSceneSelector(context),
            ),
          if (_mergeMode == 'new_chapter') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '将在所选章节之后插入新章节',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          _buildTaskInfo(context),
        ],
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: WebTheme.getOnSurfaceColor(context),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildMergeModeSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
        value: _mergeMode,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        items: const [
          DropdownMenuItem(value: 'append', child: Text('作为新场景插入章节末尾')),
          DropdownMenuItem(value: 'replace', child: Text('替换现有内容')),
          DropdownMenuItem(value: 'new_chapter', child: Text('作为新章节插入')),
        ],
        onChanged: (v) {
          setState(() {
            _mergeMode = v ?? 'append';
            _currentSummaryCache = null;
            _currentContentCache = null;
          });
        },
      ),
    );
  }

  Widget _buildChapterSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: _targetChapterId,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        items: _chapters
            .map((c) => DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(c.title, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (!_loadingNovel && _chapters.isNotEmpty)
            ? (v) {
                setState(() {
                  _targetChapterId = v;
                  _rebuildScenesForTargetChapter();
                  _insertPosition = -1;
                  _currentSummaryCache = null;
                  _currentContentCache = null;
                });
              }
            : null,
      ),
    );
  }

  Widget _buildPositionSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        value: _insertPosition,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        items: [
          const DropdownMenuItem<int>(
            value: -1,
            child: Text('末尾（追加到最后）'),
          ),
          ..._scenesInTargetChapter.asMap().entries.map((e) {
            final idx = e.key;
            final scene = e.value;
            final title = scene.title.isNotEmpty ? scene.title : '场景${_getChineseNumber(idx + 1)}';
            return DropdownMenuItem<int>(
              value: idx,
              child: Text('在「$title」之后'),
            );
          }),
        ],
        onChanged: (_targetChapterId != null)
            ? (v) {
                setState(() {
                  _insertPosition = v ?? -1;
                  _currentContentCache = null;
                });
              }
            : null,
      ),
    );
  }

  Widget _buildSceneSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
        value: _targetSceneId,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        items: _scenesInTargetChapter
            .asMap()
            .entries
            .map((entry) {
              final index = entry.key;
              final scene = entry.value;
              final displayTitle = scene.title.isNotEmpty
                  ? scene.title
                  : '场景${_getChineseNumber(index + 1)}';
              return DropdownMenuItem(
                value: scene.id,
                child: Text(displayTitle, overflow: TextOverflow.ellipsis),
              );
            })
            .toList(),
        onChanged: (v) {
          setState(() {
            _targetSceneId = v;
            _currentContentCache = null;
          });
        },
      ),
    );
  }

  Widget _buildTaskInfo(BuildContext context) {
    final theme = Theme.of(context);
    final taskId = widget.event['taskId']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '任务信息',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${taskId.length > 8 ? taskId.substring(0, 8) : taskId}...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _loadingNovel ? null : _onMergeSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadingNovel) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.merge_type, size: 18),
                const SizedBox(width: 8),
                Text(_loadingNovel ? '处理中...' : '确认合并'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMergeSubmit() async {
    // 显示加载中提示
    final loadingController = LoadingToast.show(context, message: '正在添加内容...');
    
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final EditorRepository repo = EditorRepositoryImpl(apiClient: api);
      final String? novelIdOpt = _novelId;
      if (novelIdOpt == null || novelIdOpt.isEmpty) {
        loadingController.error('缺少小说ID，无法合并');
        return;
      }
      final String novelId = novelIdOpt;

      if (_mergeMode == 'new_chapter') {
        final chapterTitle = 'AI生成章节';
        final sceneTitle = 'AI生成场景';
        final String actIdForInsert = _targetChapterId != null 
            ? (_findActIdForChapter(_targetChapterId!) ?? _findFirstActId())
            : _findFirstActId();
        final created = await repo.addChapterWithScene(
          novelId,
          actIdForInsert,
          chapterTitle,
          sceneTitle,
          sceneSummary: _generatedSummary,
          sceneContent: _generatedContent,
          insertAfterChapterId: _targetChapterId, // 若选择了具体章节，则在其后插入
        );
        loadingController.success('已成功创建新章节：$chapterTitle');
        final String? newChapterId = created['chapterId']?.toString();
        // 延迟关闭对话框，让用户看到成功提示
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, {'newChapterId': newChapterId});
        });
        return;
      } else if (_mergeMode == 'append') {
        if (_targetChapterId == null) {
          loadingController.error('请选择目标章节');
          return;
        }
        final title = 'AI生成场景';
        final newScene = await repo.addSceneFine(
          novelId,
          _targetChapterId!,
          title,
          summary: _generatedSummary,
          content: _generatedContent,
          position: _insertPosition == -1 ? null : _insertPosition,
        );
        loadingController.success('已成功追加到目标章节：${newScene.title}');
      } else if (_mergeMode == 'replace') {
        if (_targetChapterId == null || _targetSceneId == null) {
          loadingController.error('请选择目标章节与场景');
          return;
        }
        final actId = _findActIdForChapter(_targetChapterId!);
        if (actId == null) {
          loadingController.error('无法定位目标章节所属卷');
          return;
        }
        if (_generatedContent == null || _generatedContent!.isEmpty) {
          loadingController.error('生成的内容为空，无法替换场景内容');
          return;
        }
        final content = _generatedContent!;
        final wordCount = content.length.toString();
        final summary = Summary(id: '${_targetSceneId!}_summary', content: _generatedSummary ?? '');
        await repo.saveSceneContent(novelId, actId, _targetChapterId!, _targetSceneId!, content, wordCount, summary);

        loadingController.success('已成功替换目标场景内容');

        if (mounted) {
          try {
            final editorBloc = context.read<EditorBloc>();
            final currentState = editorBloc.state;
            if (currentState is EditorLoaded && currentState.activeSceneId == _targetSceneId) {
              AppLogger.i('AI任务合并', '替换的是当前活动场景，强制刷新编辑器内容');
              editorBloc.add(SaveSceneContent(
                novelId: novelId,
                actId: actId,
                chapterId: _targetChapterId!,
                sceneId: _targetSceneId!,
                content: content,
                wordCount: wordCount.toString(),
                localOnly: true,
              ));
            }
          } catch (e) {
            AppLogger.w('AI任务合并', '无法访问EditorBloc，跳过强制刷新: $e');
          }
        }
        final quillJson = QuillHelper.ensureQuillFormat(content);
        EventBus.instance.fire(SceneContentExternallyUpdatedEvent(
          novelId: novelId,
          actId: actId,
          chapterId: _targetChapterId!,
          sceneId: _targetSceneId!,
          content: quillJson,
        ));
      }
      // 延迟关闭对话框，让用户看到成功提示
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      loadingController.error('合并失败: $e');
    }
  }

  Future<void> _loadPreviewAndTargets() async {
    try {
      final api = RepositoryProvider.of<ApiClient>(context);
      final EditorRepository repo = EditorRepositoryImpl(apiClient: api);
      final String? novelIdOpt = _novelId;
      if (novelIdOpt == null || novelIdOpt.isEmpty) {
        TopToast.error(context, '缺少小说ID，无法加载预览');
        return;
      }
      final String novelId = novelIdOpt;

      final Novel? loaded = await repo.getNovel(novelId);
      final Novel? novel = loaded;
      if (novel == null) {
        TopToast.error(context, '未能加载小说结构');
        return;
      }
      _acts = novel.acts;
      _chapters = novel.acts.expand((a) => a.chapters).toList();
      _targetChapterId ??= (_chapters.isNotEmpty ? _chapters.first.id : null);
      _rebuildScenesForTargetChapter();
      _loadingNovel = false;

      final result = widget.event['result'];
      if (result is Map) {
        final chapterId = result['generatedChapterId']?.toString();
        final sceneId = result['generatedInitialSceneId']?.toString();
        if ((chapterId != null && chapterId.isNotEmpty) && (sceneId != null && sceneId.isNotEmpty)) {
          final actId = _findActIdForChapter(chapterId);
          if (actId != null) {
            final scene = await repo.getSceneContent(novelId, actId, chapterId, sceneId);
            if (scene != null && mounted) {
              setState(() {
                _generatedContent = scene.content.isNotEmpty
                    ? QuillHelper.deltaToText(scene.content)
                    : scene.content;
                if ((_generatedSummary == null || _generatedSummary!.isEmpty) && scene.summary.content.isNotEmpty) {
                  final summaryContent = scene.summary.content;
                  _generatedSummary = QuillHelper.isValidQuillFormat(summaryContent)
                      ? QuillHelper.deltaToText(summaryContent)
                      : summaryContent;
                }
              });
            }
          }
        }
      }

      if ((_generatedContent == null || _generatedContent!.isEmpty)) {
        try {
          final taskRepo = TaskRepositoryImpl(apiClient: api);
          final taskId = widget.event['taskId']?.toString();
          if (taskId != null && taskId.isNotEmpty) {
            final status = await taskRepo.getTaskStatus(taskId);
            final res = status['result'];
            if (res is Map && mounted) {
              setState(() {
                final rawContent = res['generatedContent']?.toString() ?? '';
                AppLogger.i('AI任务合并', '兜底逻辑 - 从API获取的生成内容: ${rawContent.length}个字符');
                AppLogger.i('AI任务合并', '兜底逻辑 - 内容预览: ${rawContent.length > 100 ? rawContent.substring(0, 100) : rawContent}...');
                if (rawContent.isNotEmpty) {
                  _generatedContent = QuillHelper.isValidQuillFormat(rawContent)
                      ? QuillHelper.deltaToText(rawContent)
                      : rawContent;
                  AppLogger.i('AI任务合并', '兜底逻辑 - 处理后内容长度: ${_generatedContent?.length ?? 0}');
                } else {
                  _generatedContent = rawContent;
                  AppLogger.w('AI任务合并', '兜底逻辑 - API返回的内容仍为空');
                }
                if (_generatedSummary?.isNotEmpty != true) {
                  final rawSummary = res['generatedSummary']?.toString();
                  if (rawSummary != null && rawSummary.isNotEmpty) {
                    _generatedSummary = QuillHelper.isValidQuillFormat(rawSummary)
                        ? QuillHelper.deltaToText(rawSummary)
                        : rawSummary;
                  }
                }
              });
            }
          }
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String? _findActIdForChapter(String chapterId) {
    for (final act in _acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == chapterId) return act.id;
      }
    }
    return null;
  }

  String _findFirstActId() {
    if (_acts.isNotEmpty) {
      return _acts.first.id;
    }
    throw Exception('没有找到可用的卷(Act)');
  }

  void _rebuildScenesForTargetChapter() {
    _scenesInTargetChapter = [];
    if (_targetChapterId == null) return;
    for (final act in _acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == _targetChapterId) {
          _scenesInTargetChapter = chapter.scenes;
          _targetSceneId = _scenesInTargetChapter.isNotEmpty ? _scenesInTargetChapter.first.id : null;
          return;
        }
      }
    }
  }

  String _getChineseNumber(int number) {
    const chineseNumbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (number <= 0) return '零';
    if (number <= 10) return chineseNumbers[number - 1];
    if (number < 20) return '十${chineseNumbers[number - 11]}';
    if (number < 100) {
      final tens = number ~/ 10;
      final ones = number % 10;
      return '${chineseNumbers[tens - 1]}十${ones > 0 ? chineseNumbers[ones - 1] : ''}';
    }
    return number.toString();
  }
}


