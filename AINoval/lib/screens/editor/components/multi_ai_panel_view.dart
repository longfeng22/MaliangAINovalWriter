import 'package:ainoval/screens/chat/widgets/ai_chat_sidebar.dart';
import 'package:ainoval/screens/editor/components/draggable_divider.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/screens/editor/widgets/ai_generation_panel.dart';
import 'package:ainoval/screens/editor/widgets/ai_setting_generation_panel.dart';
import 'package:ainoval/screens/editor/widgets/ai_summary_panel.dart';
import 'package:ainoval/screens/editor/widgets/continue_writing_form.dart';
import 'package:ainoval/services/api_service/repositories/user_ai_model_config_repository.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/services/api_service/repositories/novel_ai_repository.dart';
import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/event_bus.dart';
// imports for task events handled in AITaskCenterPanel removed

/// 多AI面板视图组件
/// 支持以卡片形式并排显示多个AI辅助面板，可拖拽调整大小和顺序
class MultiAIPanelView extends StatefulWidget {
  const MultiAIPanelView({
    Key? key,
    required this.novelId,
    required this.chapterId,
    required this.layoutManager,
    required this.userId,
    required this.userAiModelConfigRepository,
    required this.onContinueWritingSubmit,
    required this.editorRepository,
    required this.novelAIRepository,
  }) : super(key: key);

  final String novelId;
  final String? chapterId;
  final EditorLayoutManager layoutManager;
  final String? userId;
  final UserAIModelConfigRepository userAiModelConfigRepository;
  final Function(Map<String, dynamic> parameters) onContinueWritingSubmit;
  final EditorRepository editorRepository;
  final NovelAIRepository novelAIRepository;

  @override
  State<MultiAIPanelView> createState() => _MultiAIPanelViewState();
}

class _MultiAIPanelViewState extends State<MultiAIPanelView> {
  // 拖拽重排序相关状态
  String? _draggedPanelId;
  double _draggedPanelOffset = 0.0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final visiblePanels = widget.layoutManager.visiblePanels;
    final screenWidth = MediaQuery.of(context).size.width;
    // 优化屏幕尺寸判断：考虑1080p和更小屏幕的实际使用情况
    final bool isNarrow = screenWidth < 1600; // 提高阈值，包含1080p显示器
    final bool isVeryNarrow = screenWidth < 1200; // 调整极小屏幕阈值
    final bool isMobile = screenWidth < 900; // 移动设备阈值保持不变
    
    // 小屏策略：根据屏幕大小限制面板数量
    final List<String> effectivePanels;
    if (isMobile && visiblePanels.isNotEmpty) {
      effectivePanels = [visiblePanels.last]; // 移动设备只显示最新面板
    } else if (isVeryNarrow && visiblePanels.length > 1) {
      effectivePanels = [visiblePanels.last]; // 1200px以下只显示一个面板
    } else if (isNarrow && visiblePanels.length > 2) {
      effectivePanels = visiblePanels.take(2).toList(); // 1600px以下最多显示2个面板
    } else {
      effectivePanels = visiblePanels; // 大屏幕显示所有面板
    }
    
    if (effectivePanels.isEmpty) {
      return _buildToggleAllPanelsButton();
    }
    
    return Row(
      children: [
        // 添加面板之间的拖拽分隔线和面板内容
        for (int i = 0; i < effectivePanels.length; i++) ...[
          if (i > 0 && !isMobile) _buildDraggableDivider(effectivePanels[i]),
          _buildPanelContent(effectivePanels[i], i, isNarrow: isNarrow, isVeryNarrow: isVeryNarrow, isMobile: isMobile),
        ],
        
        // 全局隐藏/显示控制按钮
        _buildToggleAllPanelsButton(),
      ],
    );
  }
  
  /// 构建全局隐藏/显示所有面板的控制按钮
  Widget _buildToggleAllPanelsButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasVisiblePanels = widget.layoutManager.visiblePanels.isNotEmpty;
    
    return SizedBox(
      width: 32,
      child: Container(
        margin: const EdgeInsets.only(left: 8, right: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (hasVisiblePanels) {
                _hideAllPanels();
              } else {
                _showAllPanels();
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Tooltip(
              message: hasVisiblePanels ? '隐藏所有面板' : '显示面板',
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasVisiblePanels 
                        ? Icons.keyboard_arrow_right 
                        : Icons.keyboard_arrow_left,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 12,
                      height: 2,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// 隐藏所有面板
  void _hideAllPanels() {
    widget.layoutManager.hideAllAIPanels();
  }
  
  /// 恢复所有面板（显示之前保存的面板配置）
  void _showAllPanels() {
    widget.layoutManager.restoreHiddenAIPanels();
  }
  
  Widget _buildDraggableDivider(String panelId) {
    return DraggableDivider(
      onDragUpdate: (details) {
        final delta = details.delta.dx;
        widget.layoutManager.updatePanelWidth(panelId, delta);
      },
      onDragEnd: (_) {
        widget.layoutManager.savePanelWidths();
      },
    );
  }
  
  Widget _buildPanelContent(String panelId, int index, {required bool isNarrow, required bool isVeryNarrow, required bool isMobile}) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // 优化响应式宽度计算：根据屏幕大小动态调整
    double responsiveWidthRatio;
    if (isMobile) {
      responsiveWidthRatio = 0.9; // 移动设备使用90%宽度
    } else if (isVeryNarrow) {
      responsiveWidthRatio = 0.6; // 小屏幕使用60%宽度（适合1080p）
    } else if (isNarrow) {
      responsiveWidthRatio = 0.4; // 中等屏幕使用40%宽度
    } else {
      responsiveWidthRatio = 0.35; // 大屏幕保持原有35%
    }
    
    final double maxResponsiveWidth = (screenWidth * responsiveWidthRatio).clamp(
      EditorLayoutManager.minPanelWidth,
      EditorLayoutManager.maxPanelWidth,
    );
    
    double width = widget.layoutManager.panelWidths[panelId] ?? EditorLayoutManager.minPanelWidth;
    if (isNarrow) {
      width = width.clamp(EditorLayoutManager.minPanelWidth, maxResponsiveWidth);
    }
    
    // 计算拖拽时的偏移量
    double xOffset = 0.0;
    if (_isDragging && _draggedPanelId == panelId) {
      xOffset = _draggedPanelOffset.clamp(-50.0, 50.0); // 限制偏移量，避免布局问题
    }
    
    // 使用Material和Card为面板添加卡片风格
    return SizedBox(
      width: width,
      child: Transform.translate(
        offset: Offset(xOffset, 0),
        child: Card(
          elevation: _isDragging && _draggedPanelId == panelId ? 8 : 1,
          margin: EdgeInsets.zero, // 紧贴边缘
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero, // 取消圆角
            side: BorderSide(
              color: _isDragging && _draggedPanelId == panelId
                ? WebTheme.getPrimaryColor(context).withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: _isDragging && _draggedPanelId == panelId ? 2 : 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 可拖动的顶部把手（小屏禁用重排序，改为显示标题行）
              _buildDragHandle(panelId, index, isMobile: isMobile),
              
              // 面板内容
              Expanded(
                child: _buildPanel(panelId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle(String panelId, int index, {required bool isMobile}) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 面板类型标题映射
    final panelTitles = {
      EditorLayoutManager.aiChatPanel: 'AI聊天',
      EditorLayoutManager.aiSummaryPanel: 'AI摘要',
      EditorLayoutManager.aiScenePanel: 'AI场景生成',
      EditorLayoutManager.aiContinueWritingPanel: '自动续写',
      EditorLayoutManager.aiSettingGenerationPanel: 'AI生成设定',
    };
    
    final panelTitle = panelTitles[panelId] ?? '未知面板 ($panelId)';
    
    return GestureDetector(
      // 实现拖拽重排序（移动设备禁用）
      onPanStart: (!isMobile && widget.layoutManager.visiblePanels.length > 1) ? (details) {
        if (mounted) {
          setState(() {
            _draggedPanelId = panelId;
            _isDragging = true;
            _draggedPanelOffset = 0.0;
          });
        }
      } : null,
      onPanUpdate: (!isMobile && widget.layoutManager.visiblePanels.length > 1) ? (details) {
        if (_isDragging && _draggedPanelId == panelId && mounted) {
          setState(() {
            _draggedPanelOffset += details.delta.dx;
          });
          
          // 计算当前应该插入的位置
          _updatePanelOrder(details.globalPosition.dx);
        }
      } : null,
      onPanEnd: (!isMobile && widget.layoutManager.visiblePanels.length > 1) ? (details) {
        if (_isDragging && _draggedPanelId == panelId && mounted) {
          setState(() {
            _isDragging = false;
            _draggedPanelId = null;
            _draggedPanelOffset = 0.0;
          });
        }
      } : null,
      child: Container(
        height: 24,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _isDragging && _draggedPanelId == panelId
            ? WebTheme.getPrimaryColor(context).withOpacity(0.15)
            : colorScheme.secondaryContainer.withValues(alpha: 0.7),
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Panel icon and title
            Flexible(
              child: Row(
                children: [
                  Icon(
                    _getPanelIcon(panelId),
                    size: 14,
                    color: _isDragging && _draggedPanelId == panelId
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      panelTitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _isDragging && _draggedPanelId == panelId
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSecondaryContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Drag and close buttons
            Row(
              children: [
                // Drag handle icon
                if (!isMobile && widget.layoutManager.visiblePanels.length > 1)
                  Tooltip(
                    message: '拖动调整顺序',
                    child: Icon(
                      Icons.drag_handle,
                      size: 14,
                                              color: _isDragging && _draggedPanelId == panelId
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  
                // Close button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _closePanel(panelId);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: _isDragging && _draggedPanelId == panelId
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
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
  
  /// 根据拖拽位置更新面板顺序
  void _updatePanelOrder(double globalX) {
    if (_draggedPanelId == null || !mounted) return;
    
    final currentIndex = widget.layoutManager.visiblePanels.indexOf(_draggedPanelId!);
    if (currentIndex == -1) return;
    
    // 简化的位置计算：基于偏移量估算新位置
    int newIndex = currentIndex;
    final offset = _draggedPanelOffset;
    
    // 使用较大的阈值避免频繁重排序
    const threshold = 100.0;
    
    if (offset > threshold && currentIndex < widget.layoutManager.visiblePanels.length - 1) {
      newIndex = currentIndex + 1;
    } else if (offset < -threshold && currentIndex > 0) {
      newIndex = currentIndex - 1;
    }
    
    // 如果位置发生了变化，更新面板顺序
    if (newIndex != currentIndex && mounted) {
      widget.layoutManager.reorderPanels(currentIndex, newIndex);
      if (mounted) {
        setState(() {
          _draggedPanelOffset = 0.0; // 重置偏移量
        });
      }
    }
  }
  
  // 根据面板类型获取对应图标
  IconData _getPanelIcon(String panelId) {
    switch (panelId) {
      case EditorLayoutManager.aiChatPanel:
        return Icons.chat_outlined;
      case EditorLayoutManager.aiSummaryPanel:
        return Icons.summarize_outlined;
      case EditorLayoutManager.aiScenePanel:
        return Icons.auto_awesome_outlined;
      case EditorLayoutManager.aiContinueWritingPanel:
        return Icons.auto_stories_outlined;
      case EditorLayoutManager.aiSettingGenerationPanel:
        return Icons.auto_fix_high_outlined;
      default:
        return Icons.dashboard_outlined;
    }
  }
  
  // 关闭指定面板
  void _closePanel(String panelId) {
    switch (panelId) {
      case EditorLayoutManager.aiChatPanel:
        widget.layoutManager.toggleAIChatSidebar();
        break;
      case EditorLayoutManager.aiSummaryPanel:
        widget.layoutManager.toggleAISummaryPanel();
        break;
      case EditorLayoutManager.aiScenePanel:
        widget.layoutManager.toggleAISceneGenerationPanel();
        break;
      case EditorLayoutManager.aiContinueWritingPanel:
        widget.layoutManager.toggleAIContinueWritingPanel();
        break;
      case EditorLayoutManager.aiSettingGenerationPanel:
        widget.layoutManager.toggleAISettingGenerationPanel();
        break;
    }
  }
  
  Widget _buildPanel(String panelId) {
    switch (panelId) {
      case EditorLayoutManager.aiChatPanel:
        return _buildAIChatPanel();
      case EditorLayoutManager.aiSummaryPanel:
        return _buildAISummaryPanel();
      case EditorLayoutManager.aiScenePanel:
        return _buildAISceneGenerationPanel();
      case EditorLayoutManager.aiContinueWritingPanel:
        return _buildAIContinueWritingPanel();
      case EditorLayoutManager.aiSettingGenerationPanel:
        return _buildAISettingGenerationPanel();
      default:
        return Center(child: Text('未知面板类型: $panelId'));
    }
  }
  
  Widget _buildAIChatPanel() {
    return AIChatSidebar(
      novelId: widget.novelId,
      chapterId: widget.chapterId,
      onClose: widget.layoutManager.toggleAIChatSidebar,
      isCardMode: true,
    );
  }
  
  Widget _buildAISummaryPanel() {
    return AISummaryPanel(
      novelId: widget.novelId,
      onClose: widget.layoutManager.toggleAISummaryPanel,
      isCardMode: true,
    );
  }
  
  Widget _buildAISceneGenerationPanel() {
    return AIGenerationPanel(
      novelId: widget.novelId,
      onClose: widget.layoutManager.toggleAISceneGenerationPanel,
      isCardMode: true,
    );
  }

  Widget _buildAIContinueWritingPanel() {
    if (widget.userId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '请先登录以使用自动续写功能。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ContinueWritingForm(
      novelId: widget.novelId,
      userId: widget.userId!,
      userAiModelConfigRepository: widget.userAiModelConfigRepository,
      onCancel: widget.layoutManager.toggleAIContinueWritingPanel,
      onSubmit: _handleContinueWritingSubmit,
    );
  }

  /// 提交自动续写任务到后端
  Future<void> _handleContinueWritingSubmit(Map<String, dynamic> parameters) async {
    try {
      // 参数提取与兜底
      final String novelId = (parameters['novelId']?.toString() ?? widget.novelId);
      final int numberOfChapters = (parameters['numberOfChapters'] is int)
          ? parameters['numberOfChapters'] as int
          : int.tryParse(parameters['numberOfChapters']?.toString() ?? '1') ?? 1;
      final String aiConfigIdSummary = parameters['aiConfigIdSummary']?.toString() ?? '';
      final String aiConfigIdContent = parameters['aiConfigIdContent']?.toString() ?? '';
      final String startContextMode = parameters['startContextMode']?.toString() ?? 'AUTO';
      final int? contextChapterCount = parameters['contextChapterCount'] == null
          ? null
          : (parameters['contextChapterCount'] is int
              ? parameters['contextChapterCount'] as int
              : int.tryParse(parameters['contextChapterCount'].toString()));
      final String? customContext = parameters['customContext']?.toString();
      final String? writingStyle = parameters['writingStyle']?.toString();
      final bool requiresReview = false; // 默认不需要评审
      final bool persistChanges = false; // 默认不直接持久化，走预览合并
      final String? summaryPromptTemplateId = parameters['summaryPromptTemplateId']?.toString();
      final String? contentPromptTemplateId = parameters['contentPromptTemplateId']?.toString();
      final String? summaryPublicModelConfigId = parameters['summaryPublicModelConfigId']?.toString();
      final String? contentPublicModelConfigId = parameters['contentPublicModelConfigId']?.toString();

      // 调用后端
      final taskId = await widget.editorRepository.submitContinueWritingTask(
        novelId: novelId,
        numberOfChapters: numberOfChapters,
        aiConfigIdSummary: aiConfigIdSummary,
        aiConfigIdContent: aiConfigIdContent,
        startContextMode: startContextMode,
        contextChapterCount: contextChapterCount,
        customContext: customContext,
        writingStyle: writingStyle,
        requiresReview: requiresReview,
        persistChanges: persistChanges,
        summaryPromptTemplateId: summaryPromptTemplateId,
        contentPromptTemplateId: contentPromptTemplateId,
        summaryPublicModelConfigId: summaryPublicModelConfigId,
        contentPublicModelConfigId: contentPublicModelConfigId,
      );

      AppLogger.i('MultiAIPanelView', 'Continue Writing Submitted: taskId=$taskId, params=$parameters');
      if (mounted) {
        TopToast.success(context, '自动续写任务已提交 (ID: $taskId)');
      }

      // 继续调用外部回调以保持原有行为（日志/提示等）
      try {
        widget.onContinueWritingSubmit(parameters);
      } catch (_) {}

      // 立即广播占位提交事件，保障任务中心能立刻显示该任务（后续由SSE更新覆盖）
      try {
        final Map<String, dynamic> placeholder = {
          'type': 'TASK_SUBMITTED',
          'taskId': taskId,
          'taskType': 'CONTINUE_WRITING_CONTENT',
          'novelId': novelId,
          'ts': DateTime.now().millisecondsSinceEpoch,
        };
        EventBus.instance.fire(TaskEventReceived(event: placeholder));
        // 🔧 重要：不再主动触发 StartTaskEventsListening，避免多组件重复触发导致连接风暴
        // 🔧 SSE连接由 main.dart 统一管理，登录时自动启动，面板只需发送占位事件即可
        // if (AppConfig.authToken != null && AppConfig.authToken!.isNotEmpty) {
        //   EventBus.instance.fire(const StartTaskEventsListening());
        // } else {
        //   AppLogger.w('MultiAIPanelView', '跳过启动全局任务事件监听：未检测到有效token');
        // }
      } catch (_) {}
      // 完成由"AI任务中心"统一订阅与提示
    } catch (e, st) {
      AppLogger.e('MultiAIPanelView', '提交自动续写任务失败', e, st);
      if (mounted) {
        TopToast.error(context, '提交续写任务失败: ${e.toString()}');
      }
    }
  }

  Widget _buildAISettingGenerationPanel() {
    return AISettingGenerationPanel(
      novelId: widget.novelId,
      onClose: widget.layoutManager.toggleAISettingGenerationPanel,
      isCardMode: true,
      editorRepository: widget.editorRepository,
      novelAIRepository: widget.novelAIRepository,
    );
  }
} 