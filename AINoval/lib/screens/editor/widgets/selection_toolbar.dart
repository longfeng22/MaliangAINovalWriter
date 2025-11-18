// import 'dart:math' as math;

import 'package:ainoval/models/unified_ai_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:async';

import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/screens/editor/widgets/novel_setting_detail.dart';
import 'package:ainoval/screens/editor/widgets/snippet_edit_form.dart';
import 'package:ainoval/screens/editor/components/text_generation_dialogs.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/preset_quick_menu_refactored.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/utils/logger.dart';
// import 'package:ainoval/config/provider_icons.dart';
import 'package:ainoval/utils/web_theme.dart';
import '../../../config/app_config.dart';

/// 统一的工具栏菜单组件
class ToolbarMenuButton<T> extends StatelessWidget {
  const ToolbarMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    required this.isDark,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final List<ToolbarMenuItem<T>> items;
  final ValueChanged<T?> onSelected;
  final bool isDark;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        opaque: true,
        child: PopupMenuButton<T>(
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under, // 菜单出现在按钮下方
          color: WebTheme.getBackgroundColor(context), // 主题背景色
          elevation: 1, // 减少阴影
          shadowColor: Theme.of(context).colorScheme.shadow.withOpacity(0.12), // 主题阴影色
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200,
              width: 1,
            ),
          ),
          offset: const Offset(0, 2), // 微小偏移确保不覆盖按钮
          itemBuilder: (context) => items.map<PopupMenuEntry<T>>((item) {
            if (item.isDivider) {
              return const PopupMenuDivider();
            }
            
            return PopupMenuItem<T>(
              value: item.value,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                opaque: true,
                child: item.child,
              ),
            );
          }).toList(),
          onSelected: onSelected,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: isActive ? BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive 
                      ? WebTheme.getPrimaryColor(context)
                      : WebTheme.getSecondaryTextColor(context),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more,
                  size: 12,
                  color: isActive 
                      ? WebTheme.getPrimaryColor(context)
                      : WebTheme.getSecondaryTextColor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具栏菜单项
class ToolbarMenuItem<T> {
  const ToolbarMenuItem({
    required this.value,
    required this.child,
    this.isDivider = false,
  });

  /// 创建分隔线
  const ToolbarMenuItem.divider()
      : value = null,
        child = const SizedBox.shrink(),
        isDivider = true;

  final T? value;
  final Widget child;
  final bool isDivider;
}

/// 颜色菜单项组件
class ColorMenuItem extends StatelessWidget {
  const ColorMenuItem({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: color == WebTheme.getBackgroundColor(context) 
                ? Border.all(color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey200, width: 1)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: WebTheme.getTextColor(context),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// 文本选中上下文工具栏
///
/// 当用户在编辑器中选中文本时显示的浮动工具栏，提供格式化和自定义操作按钮
class SelectionToolbar extends StatefulWidget {
  /// 创建一个选中工具栏
  ///
  /// [controller] 富文本编辑器控制器
  /// [layerLink] 用于定位工具栏的层链接
  /// [onClosed] 工具栏关闭时的回调
  /// [onFormatChanged] 格式变更时的回调
  /// [wordCount] 选中文本的字数
  /// [showAbove] 是否显示在选区上方，默认为true
  /// [scrollController] 滚动控制器，用于检测滚动位置
  /// [novelId] 小说ID，用于创建设定和片段
  /// [onSettingCreated] 设定创建成功回调
  /// [onSnippetCreated] 片段创建成功回调
  /// [onStreamingGenerationStarted] 流式生成开始回调
  const SelectionToolbar({
    super.key,
    required this.controller,
    required this.layerLink,
    required this.editorSize,
    required this.selectionRect,
    this.onClosed,
    this.onFormatChanged,
    this.wordCount = 0,
    this.showAbove = true,
    this.scrollController,
    this.novelId,
    this.onSettingCreated,
    this.onSnippetCreated,
    this.onStreamingGenerationStarted,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.targetKey,
  });

  /// 富文本编辑器控制器
  final QuillController controller;

  /// 用于定位工具栏的层链接
  final LayerLink layerLink;

  /// 编辑器尺寸
  final Size editorSize;

  /// 选区矩形
  final Rect selectionRect;

  /// 工具栏关闭时的回调
  final VoidCallback? onClosed;

  /// 格式变更时的回调
  final VoidCallback? onFormatChanged;

  /// 选中文本的字数
  final int wordCount;

  /// 是否显示在选区上方，默认为true
  final bool showAbove;

  /// 滚动控制器，用于检测滚动位置
  final ScrollController? scrollController;

  /// 小说ID，用于创建设定和片段
  final String? novelId;

  /// 设定创建成功回调
  final Function(NovelSettingItem)? onSettingCreated;

  /// 片段创建成功回调
  final Function(NovelSnippet)? onSnippetCreated;

  /// 流式生成开始回调 - 支持统一AI模型
  final Function(UniversalAIRequest request, UnifiedAIModel model)? onStreamingGenerationStarted;

  /// 小说数据，用于AI功能的上下文
  final Novel? novel;

  /// 设定数据，用于AI功能的上下文
  final List<NovelSettingItem> settings;

  /// 设定组数据，用于AI功能的上下文
  final List<SettingGroup> settingGroups;

  /// 片段数据，用于AI功能的上下文
  final List<NovelSnippet> snippets;

  /// LayerLink目标对应的GlobalKey，用于计算全局位置
  final GlobalKey? targetKey;

  @override
  State<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<SelectionToolbar> {
  late final FocusNode _toolbarFocusNode;
  final GlobalKey _toolbarKey = GlobalKey();
  
  // 行间距常量，用于计算工具栏与文本的距离
  static const double _lineSpacing = 6.0;
  
  // 工具栏高度预估（用于位置计算）
  static const double _defaultToolbarHeight = 120.0;
  double _toolbarHeight = _defaultToolbarHeight;

  // AI功能相关状态
  OverlayEntry? _aiMenuOverlay;
  final Map<String, GlobalKey> _aiButtonKeys = {
    'expand': GlobalKey(),
    'rewrite': GlobalKey(),
    'compress': GlobalKey(),
  };
  String? _currentAiMode; // 当前AI操作模式：'expand', 'rewrite', 'compress'
  UserAIModelConfigModel? _selectedModel; // 保持向后兼容
  UnifiedAIModel? _selectedUnifiedModel; // 新的统一模型

  // 🚀 新增：保存工具栏出现时的选区，防止点击按钮后选区丢失导致无法应用格式
  late final TextSelection _initialSelection;

  // 🚀 新增：滚动监听，滚动时重新计算工具栏位置
  Timer? _scrollDebounce;

  // ==================== 动画相关状态 ====================
  // 上一次计算得到的工具栏偏移，用于在新旧偏移之间做插值动画
  Offset _lastOffset = Offset.zero;

  // 第一帧无需动画，避免工具栏从(0,0)滑入导致闪烁
  bool _firstBuild = true;

  @override
  void initState() {
    super.initState();
    _toolbarFocusNode = FocusNode();

    // 记录工具栏打开时的选区
    _initialSelection = widget.controller.selection;

    // 初始化后计算位置
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateToolbarHeight());

    _attachScrollListener();
  }

  @override
  void didUpdateWidget(covariant SelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollListener(oldWidget.scrollController);
      _attachScrollListener();
    }
  }

  void _attachScrollListener() {
    widget.scrollController?.addListener(_handleScroll);
  }

  void _detachScrollListener(ScrollController? controller) {
    controller?.removeListener(_handleScroll);
  }

  void _handleScroll() {
    // 使用微节流，减少setState调用频率
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {}); // 触发重建，重新计算偏移
    });
  }

  void _updateToolbarHeight() {
    if (_toolbarKey.currentContext != null) {
      final h = (_toolbarKey.currentContext!.findRenderObject() as RenderBox).size.height;
      if ((h - _toolbarHeight).abs() > 1) {
        setState(() {
          _toolbarHeight = h;
        });
      }
    }
  }

  void _adjustPosition() {
    // 获取工具栏尺寸
    final RenderBox? toolbarBox =
        _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
    if (toolbarBox == null) return;
    
    // 通知父组件调整位置（如果需要）
    if (widget.onFormatChanged != null) {
      widget.onFormatChanged!();
    }
  }

  /// 检查选中区域是否在前三行
  bool _isSelectionInFirstThreeLines() {
    try {
      // 🚀 使用与_applyAttribute相同的逻辑获取选区，确保一致性
      TextSelection selection = widget.controller.selection;
      if (selection.isCollapsed) {
        // 如果当前选区已折叠，使用初始选区
        selection = _initialSelection;
      }
      
      if (selection.isCollapsed) {
        return false;
      }
      
      // 获取文档内容
      final document = widget.controller.document;
      
      // 获取选区开始位置之前的文本
      final String textBeforeSelection = document.getPlainText(0, selection.start);
      
      // 计算换行符数量来判断行数
      final lineBreakCount = '\n'.allMatches(textBeforeSelection).length;
      
      // 行数 = 换行符数量 + 1 (因为第一行没有换行符)
      // 前三行的行数范围是 1, 2, 3，对应换行符数量为 0, 1, 2
      final lineNumber = lineBreakCount + 1;
      
      AppLogger.d('SelectionToolbar', '选区开始位置在第 $lineNumber 行（换行符数量: $lineBreakCount）');
      
      return lineNumber <= 3;
    } catch (e) {
      AppLogger.e('SelectionToolbar', '检查选区行数失败: $e');
      return false;
    }
  }

  /// 计算工具栏应该显示的位置偏移
  /// 基于视窗坐标系，通过LayerLink获取选区相对于视窗的偏移量
  Offset _calculateToolbarOffset() {
    try {
      AppLogger.d('SelectionToolbar', '🚀 开始计算工具栏位置偏移（基于视窗坐标系，不使用selectionRect和TextPainter）');
      
      final selection = widget.controller.selection;
      AppLogger.d('SelectionToolbar', '📝 文本选择状态: start=${selection.start}, end=${selection.end}, isCollapsed=${selection.isCollapsed}');
      
      if (selection.isCollapsed) {
        AppLogger.d('SelectionToolbar', '❌ 选择已折叠，返回默认位置 Offset(0, -60)');
        return const Offset(0, -60); // 默认位置
      }

      // 步骤1: 获取视窗尺寸信息
      final viewportSize = MediaQuery.of(context).size;
      AppLogger.d('SelectionToolbar', '📱 视窗尺寸: width=${viewportSize.width}, height=${viewportSize.height}');

      // 步骤2: 通过LayerLink获取目标组件的位置信息
      AppLogger.d('SelectionToolbar', '🔗 使用LayerLink作为定位基准，LayerLink会自动跟踪选择区域位置');

      // 步骤3: 获取当前滚动位置
      double scrollOffset = 0.0;
      if (widget.scrollController != null && widget.scrollController!.hasClients) {
        scrollOffset = widget.scrollController!.offset;
        AppLogger.d('SelectionToolbar', '📜 滚动控制器状态: 有客户端连接，滚动偏移=$scrollOffset');
      } else {
        AppLogger.d('SelectionToolbar', '📜 滚动控制器状态: 无客户端连接或为null，滚动偏移=$scrollOffset');
      }

      // 步骤4: 获取编辑器在视窗中的位置信息
      final editorSize = widget.editorSize;
      AppLogger.d('SelectionToolbar', '📝 编辑器尺寸: width=${editorSize.width}, height=${editorSize.height}');

      // 步骤5: 计算视窗边界约束
      final viewportTop = 0.0;
      final viewportBottom = viewportSize.height;
      AppLogger.d('SelectionToolbar', '🔲 视窗边界: 顶部=$viewportTop, 底部=$viewportBottom');

      // 🚀 使用传入的 targetKey 获取 LayerLink 目标的全局位置
      double leaderTopInViewport = 0;
      double leaderBottomInViewport = 0;
      if (widget.targetKey?.currentContext != null) {
        final RenderBox box = widget.targetKey!.currentContext!.findRenderObject() as RenderBox;
        final Offset global = box.localToGlobal(Offset.zero);
        leaderTopInViewport = global.dy;
        leaderBottomInViewport = leaderTopInViewport + box.size.height;
        AppLogger.d('SelectionToolbar', '📍 目标全局Y=$leaderTopInViewport');
      } else {
        // 回退方案：使用scrollOffset近似
        leaderTopInViewport = scrollOffset;
        leaderBottomInViewport = leaderTopInViewport + _lineSpacing;
      }

      // ================= 新增：根据可用空间决定显示在上方还是下方 =================
      // 计算选区上方和下方可用空间
      final double spaceAbove = leaderTopInViewport - (_lineSpacing + _toolbarHeight);
      final double spaceBelow = viewportBottom - leaderBottomInViewport - (_lineSpacing + _toolbarHeight);

      // 默认取传入的showAbove作为初始值
      bool shouldShowAbove = widget.showAbove;

      // 🚀 新增：检查选中区域是否在前三行，如果是则强制显示在下方
      final isInFirstThreeLines = _isSelectionInFirstThreeLines();
      AppLogger.d('SelectionToolbar', '前三行检测结果: $isInFirstThreeLines, 原始shouldShowAbove: ${widget.showAbove}');
      
      if (isInFirstThreeLines) {
        shouldShowAbove = false;
        AppLogger.d('SelectionToolbar', '检测到选中区域在前三行，强制显示在下方：shouldShowAbove=$shouldShowAbove');
      }
      // 如果当前方向空间不足，而另一侧空间充足，则自动切换方向
      else if (shouldShowAbove && spaceAbove < 0 && spaceBelow > 0) {
        shouldShowAbove = false; // 改为显示在下方
        AppLogger.d('SelectionToolbar', '空间不足，切换到下方显示：shouldShowAbove=$shouldShowAbove');
      } else if (!shouldShowAbove && spaceBelow < 0 && spaceAbove > 0) {
        shouldShowAbove = true;  // 改为显示在上方
        AppLogger.d('SelectionToolbar', '空间不足，切换到上方显示：shouldShowAbove=$shouldShowAbove');
      }
      
      AppLogger.d('SelectionToolbar', '最终shouldShowAbove决定: $shouldShowAbove (spaceAbove: $spaceAbove, spaceBelow: $spaceBelow)');
      // ========================================================================

      // 根据最终方向计算 yOffset
      double yOffset;
      if (shouldShowAbove) {
        yOffset = -_toolbarHeight - _lineSpacing;
      } else {
        // 🚀 对于前三行的情况，使用更大的下方间距
        if (isInFirstThreeLines) {
          yOffset = _lineSpacing * 30; // 24.0 像素，避免遮挡前三行文本
          AppLogger.d('SelectionToolbar', '前三行使用更大下方间距: $yOffset');
        } else {
          yOffset = _lineSpacing;
        }
      }

      // 边界检查，确保工具栏不会被视口裁剪
      final maxUpwardOffset = -leaderTopInViewport + viewportTop + _lineSpacing;
      final maxDownwardOffset = viewportBottom - leaderBottomInViewport - _toolbarHeight - _lineSpacing;
      yOffset = yOffset.clamp(maxUpwardOffset, maxDownwardOffset).toDouble();

      final finalOffset = Offset(0, yOffset);
      AppLogger.d('SelectionToolbar', '📐 计算完成，最终Offset=$finalOffset (shouldShowAbove=$shouldShowAbove)');
      return finalOffset;

    } catch (e) {
      AppLogger.e('SelectionToolbar', '❌ 计算工具栏位置失败: $e');
      // 发生错误时使用默认位置，但也要考虑前三行检测
      bool shouldShowAbove = widget.showAbove;
      
      // 🚀 即使在错误恢复时也检查前三行
      final isInFirstThreeLines = _isSelectionInFirstThreeLines();
      AppLogger.d('SelectionToolbar', '🔧 错误恢复时前三行检测结果: $isInFirstThreeLines, 原始shouldShowAbove: ${widget.showAbove}');
      
      if (isInFirstThreeLines) {
        shouldShowAbove = false;
        AppLogger.d('SelectionToolbar', '🔧 错误恢复时检测到前三行，强制显示在下方：shouldShowAbove=$shouldShowAbove');
      }
      
      // 🚀 错误恢复时也为前三行使用更大间距
      final yOffset = shouldShowAbove ? -60.0 : (isInFirstThreeLines ? 30.0 : 20.0);
      final errorOffset = Offset(0, yOffset);
      AppLogger.d('SelectionToolbar', '🔧 错误恢复，使用默认位置: $errorOffset (shouldShowAbove=$shouldShowAbove, isInFirstThreeLines=$isInFirstThreeLines)');
      return errorOffset;
    }
  }

  @override
  void dispose() {
    _toolbarFocusNode.dispose();
    _removeAiMenuOverlay();
    _detachScrollListener(widget.scrollController);
    _scrollDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateToolbarHeight());

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 🚀 使用智能偏移，保证工具栏始终在视图内
    final toolbarOffset = _calculateToolbarOffset();

    AppLogger.d('SelectionToolbar', '🎯 使用动态LayerLink跟随，offset: $toolbarOffset');

    // 构建工具栏，使用 TweenAnimationBuilder 在新旧偏移之间进行平滑插值
    final toolbarBody = MouseRegion(
      cursor: SystemMouseCursors.click, // 在工具栏上显示手型光标
      opaque: true, // 阻止鼠标事件穿透到底层编辑器
      hitTestBehavior: HitTestBehavior.opaque, // 确保立即捕获鼠标事件
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 600,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：字数统计和撤销重做按钮
              _buildTopRow(isDark),
              const SizedBox(height: 4),
              // 第二行：格式化按钮和功能按钮
              _buildBottomRow(isDark),
            ],
          ),
        ),
      ),
    );

    // 计算 Tween 的起始值
    final Offset tweenBegin = _firstBuild ? toolbarOffset : _lastOffset;
    final Offset tweenEnd = toolbarOffset;

    // 在本帧结束时记录当前 offset，用于下一次动画起点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastOffset = toolbarOffset;
      _firstBuild = false;
    });

    return TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(begin: tweenBegin, end: tweenEnd),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, animatedOffset, child) {
        return CompositedTransformFollower(
          link: widget.layerLink,
          key: _toolbarKey,
          offset: animatedOffset,
          followerAnchor: Alignment.bottomCenter, // 工具栏底部中心作为锚点
          targetAnchor: Alignment.topCenter,      // 目标顶部中心作为锚点
          showWhenUnlinked: false,
          child: child,
        );
      },
      child: toolbarBody,
    );
  }

  /// 构建顶部行（字数统计和撤销重做）
  Widget _buildTopRow(bool isDark) {
    return _buildToolbarContainer(
      isDark: isDark,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字数统计
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${widget.wordCount} Word${widget.wordCount == 1 ? '' : 's'}',
              style: TextStyle(
                color: isDark ? WebTheme.darkGrey400 : WebTheme.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 分隔线
          Container(
            width: 1,
            height: 32,
           color: isDark ? WebTheme.darkGrey300 : WebTheme.white,
          ),
          // 撤销重做按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                icon: Icons.undo,
                tooltip: '撤销',
                isDark: isDark,
                isEnabled: widget.controller.hasUndo,
                onPressed: () {
                  if (widget.controller.hasUndo) {
                    widget.controller.undo();
                  }
                },
              ),
              _buildActionButton(
                icon: Icons.redo,
                tooltip: '重做',
                isDark: isDark,
                isEnabled: widget.controller.hasRedo,
                onPressed: () {
                  if (widget.controller.hasRedo) {
                    widget.controller.redo();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建底部行（格式化和功能按钮）
  Widget _buildBottomRow(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算可用宽度
        final availableWidth = constraints.maxWidth;
        final buttonGroupsWidth = _estimateButtonGroupsWidth();
        
        // 如果空间不足，使用两行布局
        if (buttonGroupsWidth > availableWidth) {
          return _buildTwoRowLayout(isDark);
        } else {
          return _buildSingleRowLayout(isDark);
        }
      },
    );
  }

  /// 构建单行布局
  Widget _buildSingleRowLayout(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：格式化按钮组 - 使用Flexible包装以防溢出
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 格式化按钮组
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormatButton(
                          icon: Icons.format_bold,
                          tooltip: '加粗',
                          attribute: Attribute.bold,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.format_italic,
                          tooltip: '斜体',
                          attribute: Attribute.italic,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.format_underlined,
                          tooltip: '下划线',
                          attribute: Attribute.underline,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.strikethrough_s,
                          tooltip: '删除线',
                          attribute: Attribute.strikeThrough,
                          isDark: isDark,
                        ),
                        _buildTextColorButton(isDark),
                        _buildHighlightButton(isDark),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 引用、标题、列表按钮组
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormatButton(
                          icon: Icons.format_quote,
                          tooltip: '引用',
                          attribute: Attribute.blockQuote,
                          isDark: isDark,
                        ),
                        _buildDropdownButton(
                          icon: Icons.title,
                          tooltip: '标题',
                          isDark: isDark,
                          items: [
                            _DropdownItem('标题 1', () => _applyAttribute(Attribute.h1)),
                            _DropdownItem('标题 2', () => _applyAttribute(Attribute.h2)),
                            _DropdownItem('标题 3', () => _applyAttribute(Attribute.h3)),
                            _DropdownItem('普通文本', () => _clearHeadingAttribute()),
                          ],
                        ),
                        _buildDropdownButton(
                          icon: Icons.format_list_numbered,
                          tooltip: '列表',
                          isDark: isDark,
                          items: [
                            _DropdownItem('无序列表', () => _applyAttribute(Attribute.ul)),
                            _DropdownItem('有序列表', () => _applyAttribute(Attribute.ol)),
                            _DropdownItem('检查列表', () => _applyAttribute(Attribute.checked)),
                            _DropdownItem('移除列表', () => _clearListAttribute()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 功能按钮组（片段、设定、章节）
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          icon: Icons.note_add,
                          text: '片段',
                          tooltip: '添加为片段',
                          isDark: isDark,
                          onPressed: () => _createSnippetFromSelection(),
                        ),
                        _buildActionButtonWithText(
                          icon: Icons.library_books,
                          text: '设定',
                          tooltip: '添加为设定',
                          isDark: isDark,
                          onPressed: () => _createSettingFromSelection(),
                        ),
                        _buildActionButtonWithText(
                          icon: Icons.view_module,
                          text: '章节',
                          tooltip: '设置为章节',
                          isDark: isDark,
                          onPressed: () {
                            AppLogger.i('SelectionToolbar', '设置为章节');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 第二行：AI功能按钮 - 使用Flexible包装以防溢出
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 扩写按钮
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['expand'],
                          icon: Icons.expand_more,
                          text: '扩写',
                          tooltip: '扩写选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('expand'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 重构按钮
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['rewrite'],
                          icon: Icons.refresh,
                          text: '重构',
                          tooltip: '重构选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('rewrite'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 缩写按钮
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['compress'],
                          icon: Icons.compress,
                          text: '缩写',
                          tooltip: '缩写选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('compress'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建两行布局（当空间不足时）
  Widget _buildTwoRowLayout(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：格式化按钮
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 格式化按钮组
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormatButton(
                          icon: Icons.format_bold,
                          tooltip: '加粗',
                          attribute: Attribute.bold,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.format_italic,
                          tooltip: '斜体',
                          attribute: Attribute.italic,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.format_underlined,
                          tooltip: '下划线',
                          attribute: Attribute.underline,
                          isDark: isDark,
                        ),
                        _buildFormatButton(
                          icon: Icons.strikethrough_s,
                          tooltip: '删除线',
                          attribute: Attribute.strikeThrough,
                          isDark: isDark,
                        ),
                        _buildTextColorButton(isDark),
                        _buildHighlightButton(isDark),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 引用、标题、列表按钮组
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormatButton(
                          icon: Icons.format_quote,
                          tooltip: '引用',
                          attribute: Attribute.blockQuote,
                          isDark: isDark,
                        ),
                        _buildDropdownButton(
                          icon: Icons.title,
                          tooltip: '标题',
                          isDark: isDark,
                          items: [
                            _DropdownItem('标题 1', () => _applyAttribute(Attribute.h1)),
                            _DropdownItem('标题 2', () => _applyAttribute(Attribute.h2)),
                            _DropdownItem('标题 3', () => _applyAttribute(Attribute.h3)),
                            _DropdownItem('普通文本', () => _clearHeadingAttribute()),
                          ],
                        ),
                        _buildDropdownButton(
                          icon: Icons.format_list_numbered,
                          tooltip: '列表',
                          isDark: isDark,
                          items: [
                            _DropdownItem('无序列表', () => _applyAttribute(Attribute.ul)),
                            _DropdownItem('有序列表', () => _applyAttribute(Attribute.ol)),
                            _DropdownItem('检查列表', () => _applyAttribute(Attribute.checked)),
                            _DropdownItem('移除列表', () => _clearListAttribute()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 第二行：功能按钮和AI按钮
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 功能按钮组（片段、设定、章节）
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          icon: Icons.note_add,
                          text: '片段',
                          tooltip: '添加为片段',
                          isDark: isDark,
                          onPressed: () => _createSnippetFromSelection(),
                        ),
                        _buildActionButtonWithText(
                          icon: Icons.library_books,
                          text: '设定',
                          tooltip: '添加为设定',
                          isDark: isDark,
                          onPressed: () => _createSettingFromSelection(),
                        ),
                        _buildActionButtonWithText(
                          icon: Icons.view_module,
                          text: '章节',
                          tooltip: '设置为章节',
                          isDark: isDark,
                          onPressed: () {
                            AppLogger.i('SelectionToolbar', '设置为章节');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // AI功能按钮组
                Flexible(
                  child: _buildToolbarContainer(
                    isDark: isDark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['expand'],
                          icon: Icons.expand_more,
                          text: '扩写',
                          tooltip: '扩写选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('expand'),
                        ),
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['rewrite'],
                          icon: Icons.refresh,
                          text: '重构',
                          tooltip: '重构选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('rewrite'),
                        ),
                        _buildActionButtonWithText(
                          key: _aiButtonKeys['compress'],
                          icon: Icons.compress,
                          text: '缩写',
                          tooltip: '缩写选中内容',
                          isDark: isDark,
                          onPressed: () => _showAiMenu('compress'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 估算按钮组总宽度（用于判断是否需要换行）
  double _estimateButtonGroupsWidth() {
    // 🚀 修改：只估算第一行的宽度（格式化+引用标题列表+功能按钮组）
    // 这样可以确保片段和设定始终保持在第一行
    // 格式化按钮组: 6个按钮 * 32px ≈ 200px
    // 引用标题列表按钮组: 3个按钮 * 32px ≈ 100px  
    // 功能按钮组: 3个带文本按钮 * 60px ≈ 180px
    // 间距: 2个 * 4px = 8px
    return 200 + 100 + 180 + 8; // ≈ 488px（不包含AI按钮组）
  }

  /// 构建工具栏容器
  Widget _buildToolbarContainer({
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        // 浅色主题下黑底，深色主题沿用表面色
        color: isDark ? WebTheme.getSurfaceColor(context) : WebTheme.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: isDark ? 0.1 : 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: WebTheme.getSecondaryBorderColor(context),
          width: 1,
        ),
      ),
      child: child,
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onPressed,
    bool isEnabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        opaque: true,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 16,
              color: isEnabled 
                  ? (isDark ? WebTheme.darkGrey400 : WebTheme.white)
                  : (isDark ? WebTheme.darkGrey500 : WebTheme.white.withOpacity(0.6)),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建带文本的操作按钮
  Widget _buildActionButtonWithText({
    Key? key,
    required IconData icon,
    required String text,
    required String tooltip,
    required bool isDark,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        opaque: true,
        child: InkWell(
          key: key,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isDark ? const Color(0xFF6B7280) : Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: isDark ? WebTheme.darkGrey400 : WebTheme.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建格式按钮
  Widget _buildFormatButton({
    required IconData icon,
    required String tooltip,
    required Attribute attribute,
    required bool isDark,
  }) {
    // 检查当前选中文本是否已应用了该属性
    final currentStyle = widget.controller.getSelectionStyle();
    final bool isActive;
    
    // 对于不同类型的属性，采用不同的判断逻辑
    if (attribute.key == 'bold' || attribute.key == 'italic' || 
        attribute.key == 'underline' || attribute.key == 'strike') {
      // 对于简单的开关型属性，判断是否存在且值为true
      isActive = currentStyle.attributes.containsKey(attribute.key) &&
          currentStyle.attributes[attribute.key]?.value == true;
    } else if (attribute.key == 'blockquote') {
      // 对于块引用，判断是否存在
      isActive = currentStyle.attributes.containsKey(attribute.key);
    } else {
      // 对于其他属性（如标题），判断是否存在且值匹配
      isActive = currentStyle.attributes.containsKey(attribute.key) &&
          (currentStyle.attributes[attribute.key]?.value == attribute.value);
    }

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        opaque: true,
        child: InkWell(
          onTap: () => _applyAttribute(attribute),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: isActive ? BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ) : null,
            child: Icon(
              icon,
              size: 16,
              color: isActive 
                  ? const Color(0xFF3B82F6) // 蓝色激活状态
                  : (isDark ? const Color(0xFF6B7280) : Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建文字颜色按钮
  Widget _buildTextColorButton(bool isDark) {
    // 检查是否设置了文字颜色
    final currentStyle = widget.controller.getSelectionStyle();
    final bool hasTextColor = currentStyle.attributes.containsKey('color');
    
    return ToolbarMenuButton<Color>(
      icon: Icons.text_format,
      tooltip: '文字颜色',
      isDark: isDark,
      isActive: hasTextColor,
      items: [
        ToolbarMenuItem(
          value: Colors.black,
          child: const ColorMenuItem(color: Colors.black, label: '黑色'),
        ),
        ToolbarMenuItem(
          value: Colors.red,
          child: const ColorMenuItem(color: Colors.red, label: '红色'),
        ),
        ToolbarMenuItem(
          value: Colors.blue,
          child: const ColorMenuItem(color: Colors.blue, label: '蓝色'),
        ),
        ToolbarMenuItem(
          value: Colors.green,
          child: const ColorMenuItem(color: Colors.green, label: '绿色'),
        ),
        ToolbarMenuItem(
          value: Colors.orange,
          child: const ColorMenuItem(color: Colors.orange, label: '橙色'),
        ),
        ToolbarMenuItem(
          value: Colors.purple,
          child: const ColorMenuItem(color: Colors.purple, label: '紫色'),
        ),
        ToolbarMenuItem(
          value: Colors.grey,
          child: const ColorMenuItem(color: Colors.grey, label: '灰色'),
        ),
        const ToolbarMenuItem.divider(),
        ToolbarMenuItem(
          value: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.clear, size: 16, color: Colors.black),
              const SizedBox(width: 8),
              const Text(
                '默认颜色',
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
      onSelected: (color) {
        if (color != null) {
          // 将颜色转换为十六进制字符串格式，Flutter Quill期望的是这种格式
          final hexColor = '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}';
          _applyAttribute(Attribute('color', AttributeScope.inline, hexColor));
        } else {
          _applyAttribute(Attribute.clone(const Attribute('color', AttributeScope.inline, null), null));
        }
      },
    );
  }

  /// 构建背景颜色按钮
  Widget _buildHighlightButton(bool isDark) {
    // 检查是否设置了背景颜色
    final currentStyle = widget.controller.getSelectionStyle();
    final bool hasBackgroundColor = currentStyle.attributes.containsKey('background');
    
    return ToolbarMenuButton<Color>(
      icon: Icons.palette,
      tooltip: '背景颜色',
      isDark: isDark,
      isActive: hasBackgroundColor,
      items: [
        ToolbarMenuItem(
          value: Colors.red,
          child: const ColorMenuItem(color: Colors.red, label: '红色'),
        ),
        ToolbarMenuItem(
          value: Colors.orange,
          child: const ColorMenuItem(color: Colors.orange, label: '橙色'),
        ),
        ToolbarMenuItem(
          value: Colors.yellow,
          child: const ColorMenuItem(color: Colors.yellow, label: '黄色'),
        ),
        ToolbarMenuItem(
          value: Colors.green,
          child: const ColorMenuItem(color: Colors.green, label: '绿色'),
        ),
        ToolbarMenuItem(
          value: Colors.blue,
          child: const ColorMenuItem(color: Colors.blue, label: '蓝色'),
        ),
        ToolbarMenuItem(
          value: Colors.purple,
          child: const ColorMenuItem(color: Colors.purple, label: '紫色'),
        ),
        ToolbarMenuItem(
          value: Colors.pink,
          child: const ColorMenuItem(color: Colors.pink, label: '粉色'),
        ),
        ToolbarMenuItem(
          value: Colors.grey,
          child: const ColorMenuItem(color: Colors.grey, label: '灰色'),
        ),
        const ToolbarMenuItem.divider(),
        ToolbarMenuItem(
          value: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.clear, size: 16, color: Colors.black),
              const SizedBox(width: 8),
              const Text(
                '移除颜色',
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
      onSelected: (color) {
        if (color != null) {
          // 将颜色转换为十六进制字符串格式，Flutter Quill期望的是这种格式
          final hexColor = '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}';
          _applyAttribute(Attribute('background', AttributeScope.inline, hexColor));
        } else {
          _applyAttribute(Attribute.clone(const Attribute('background', AttributeScope.inline, null), null));
        }
      },
    );
  }

  /// 构建下拉按钮
  Widget _buildDropdownButton({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required List<_DropdownItem> items,
  }) {
    // 检查是否有相关属性被激活
    final currentStyle = widget.controller.getSelectionStyle();
    bool isActive = false;
    
    // 根据tooltip判断是什么类型的按钮
    if (tooltip == '标题') {
      isActive = currentStyle.attributes.containsKey('header') ||
                 currentStyle.attributes.containsKey('h1') ||
                 currentStyle.attributes.containsKey('h2') ||
                 currentStyle.attributes.containsKey('h3');
    } else if (tooltip == '列表') {
      isActive = currentStyle.attributes.containsKey('list') ||
                 currentStyle.attributes.containsKey('ul') ||
                 currentStyle.attributes.containsKey('ol') ||
                 currentStyle.attributes.containsKey('checked');
    }
    
    final toolbarItems = items.map((item) => ToolbarMenuItem<VoidCallback>(
      value: item.onTap,
      child: Text(
        item.text,
        style: const TextStyle(color: Colors.black, fontSize: 14),
      ),
    )).toList();
    
    return ToolbarMenuButton<VoidCallback>(
      icon: icon,
      tooltip: tooltip,
      isDark: isDark,
      isActive: isActive,
      items: toolbarItems,
      onSelected: (callback) => callback?.call(),
    );
  }

  /// 应用文本属性
  void _applyAttribute(Attribute attribute) {
    try {
      // 🚀 关键修复：如果当前选区已折叠，恢复为最初的选区
      TextSelection currentSelection = widget.controller.selection;
      if (currentSelection.isCollapsed) {
        AppLogger.d('SelectionToolbar', '当前选区已折叠，恢复为初始选区');
        currentSelection = _initialSelection;
        // 恢复选区到编辑器中，避免 Quill 自动收起选区
        widget.controller.updateSelection(currentSelection, ChangeSource.local);
      }

      // 获取选区信息
      final int start = currentSelection.start;
      final int end = currentSelection.end;
      final length = end - start;

      // 检查当前选中文本是否已应用了该属性
      final currentStyle = widget.controller.getSelectionStyle();
      final bool hasAttribute = currentStyle.attributes
              .containsKey(attribute.key) &&
          (currentStyle.attributes[attribute.key]?.value == attribute.value);

      AppLogger.i(
          'SelectionToolbar', '当前选区位置: start=$start, end=$end, length=$length');
      AppLogger.i('SelectionToolbar',
          '当前样式状态: ${attribute.key}=${hasAttribute ? '已应用' : '未应用'}');
      AppLogger.d('SelectionToolbar', '当前样式完整内容: ${currentStyle.attributes}');

      // 如果已应用该属性，则移除它；否则添加它
      if (hasAttribute) {
        // 创建一个同名但值为null的属性来移除格式
        final nullAttribute = Attribute.clone(attribute, null);
        widget.controller.formatText(start, length, nullAttribute);
        AppLogger.i('SelectionToolbar', '移除格式: ${attribute.key}');
      } else {
        // 应用格式
        widget.controller.formatText(start, length, attribute);
        AppLogger.i(
            'SelectionToolbar', '应用格式: ${attribute.key}=${attribute.value}');
      }

      if (widget.onFormatChanged != null) {
        widget.onFormatChanged!();
      }
    } catch (e, stackTrace) {
      AppLogger.e('SelectionToolbar', '应用/移除格式失败', e, stackTrace);
    }
  }

  /// 清除标题属性
  void _clearHeadingAttribute() {
    try {
      // 确保选中文本有效
      if (widget.controller.selection.isCollapsed) {
        AppLogger.i('SelectionToolbar', '无选中文本，无法清除标题格式');
        return;
      }

      final int start = widget.controller.selection.start;
      final int end = widget.controller.selection.end;
      final length = end - start;

      // 移除所有标题相关属性
      for (final attr in [Attribute.h1, Attribute.h2, Attribute.h3]) {
        if (widget.controller
            .getSelectionStyle()
            .attributes
            .containsKey(attr.key)) {
          widget.controller
              .formatText(start, length, Attribute.clone(attr, null));
        }
      }

      AppLogger.i('SelectionToolbar', '清除标题格式');

      if (widget.onFormatChanged != null) {
        widget.onFormatChanged!();
      }
    } catch (e, stackTrace) {
      AppLogger.e('SelectionToolbar', '清除标题格式失败', e, stackTrace);
    }
  }

  /// 清除列表属性
  void _clearListAttribute() {
    try {
      // 确保选中文本有效
      if (widget.controller.selection.isCollapsed) {
        AppLogger.i('SelectionToolbar', '无选中文本，无法清除列表格式');
        return;
      }

      final int start = widget.controller.selection.start;
      final int end = widget.controller.selection.end;
      final length = end - start;

      // 移除所有列表相关属性
      for (final attr in [Attribute.ul, Attribute.ol, Attribute.checked]) {
        if (widget.controller
            .getSelectionStyle()
            .attributes
            .containsKey(attr.key)) {
          widget.controller
              .formatText(start, length, Attribute.clone(attr, null));
        }
      }

      AppLogger.i('SelectionToolbar', '清除列表格式');

      if (widget.onFormatChanged != null) {
        widget.onFormatChanged!();
      }
    } catch (e, stackTrace) {
      AppLogger.e('SelectionToolbar', '清除列表格式失败', e, stackTrace);
    }
  }

  /// 获取选中的文本内容
  String _getSelectedText() {
    try {
      final selection = widget.controller.selection;
      if (selection.isCollapsed) {
        return '';
      }

      final document = widget.controller.document;
      final selectedText = document.getPlainText(
        selection.start,
        selection.end - selection.start,
      );

      return selectedText.trim();
    } catch (e) {
      AppLogger.e('SelectionToolbar', '获取选中文本失败', e);
      return '';
    }
  }

  /// 从选中内容创建片段
  void _createSnippetFromSelection() {
    if (widget.novelId == null) {
      AppLogger.w('SelectionToolbar', '缺少novelId，无法创建片段');
      TopToast.error(context, '无法创建片段：缺少小说信息');
      return;
    }

    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      AppLogger.w('SelectionToolbar', '无选中文本，无法创建片段');
      TopToast.warning(context, '请先选择要添加为片段的文本');
      return;
    }

    AppLogger.i('SelectionToolbar', '创建片段，选中文本: ${selectedText.substring(0, selectedText.length.clamp(0, 50))}...');

    // 创建临时片段对象，用于编辑
    final tempSnippet = NovelSnippet(
      id: '', // 空ID表示新建
      userId: '', // 将在保存时由后端填充
      novelId: widget.novelId!,
      title: '', // 用户在编辑界面填写
      content: selectedText, // 预填充选中的内容
      metadata: const SnippetMetadata(
        wordCount: 0,
        characterCount: 0,
        viewCount: 0,
        sortWeight: 0,
      ),
      isFavorite: false,
      status: 'ACTIVE',
      version: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 显示片段编辑浮动卡片
    FloatingSnippetEditor.show(
      context: context,
      snippet: tempSnippet,
      onSaved: (savedSnippet) {
        AppLogger.i('SelectionToolbar', '片段创建成功: ${savedSnippet.title}');
        widget.onSnippetCreated?.call(savedSnippet);
        TopToast.success(context, '片段"${savedSnippet.title}"创建成功');
      },
    );
  }

  /// 从选中内容创建设定
  void _createSettingFromSelection() {
    if (widget.novelId == null) {
      AppLogger.w('SelectionToolbar', '缺少novelId，无法创建设定');
      TopToast.error(context, '无法创建设定：缺少小说信息');
      return;
    }

    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      AppLogger.w('SelectionToolbar', '无选中文本，无法创建设定');
      TopToast.warning(context, '请先选择要添加为设定的文本');
      return;
    }

    AppLogger.i('SelectionToolbar', '创建设定，选中文本: ${selectedText.substring(0, selectedText.length.clamp(0, 50))}...');

    // 显示设定编辑浮动卡片
    FloatingNovelSettingDetail.show(
      context: context,
      itemId: null, // null表示新建
      novelId: widget.novelId!,
      isEditing: true,
      prefilledDescription: selectedText, // 预填充选中的文本
      onSave: (settingItem, groupId) {
        AppLogger.i('SelectionToolbar', '设定创建成功: ${settingItem.name}');
        widget.onSettingCreated?.call(settingItem);
        TopToast.success(context, '设定"${settingItem.name}"创建成功');
      },
      onCancel: () {
        AppLogger.d('SelectionToolbar', '取消创建设定');
      },
    );
  }

  /// 移除AI预设菜单覆盖层
  void _removeAiMenuOverlay() {
    _aiMenuOverlay?.remove();
    _aiMenuOverlay = null;
    _currentAiMode = null;
  }

  /// 显示AI功能菜单
  void _showAiMenu(String mode) {
    _currentAiMode = mode;
    
    // 获取当前选中的文本
    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      TopToast.warning(context, '请先选择要处理的文本');
      return;
    }

    AppLogger.i('SelectionToolbar', '显示AI预设菜单: $mode, 选中文本: ${selectedText.substring(0, selectedText.length.clamp(0, 50))}...');

    // 显示预设快捷菜单
    _showPresetQuickMenu(mode, selectedText);
  }

  /// 显示预设快捷菜单（使用MenuAnchor重构版本）
  void _showPresetQuickMenu(String mode, String selectedText) {
    _removeAiMenuOverlay(); // 先清理任何现有菜单
    
    final requestType = _getRequestTypeFromMode(mode);
    final buttonKey = _aiButtonKeys[mode];
    
    if (buttonKey?.currentContext == null) {
      AppLogger.w('SelectionToolbar', '无法找到按钮context，无法显示菜单');
      return;
    }

    final RenderBox buttonBox = buttonKey!.currentContext!.findRenderObject() as RenderBox;
    final buttonGlobalPosition = buttonBox.localToGlobal(Offset.zero);
    final buttonSize = buttonBox.size;

    // 直接在当前位置显示MenuAnchor组件，不使用额外的Overlay
    final overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 点击空白处关闭菜单
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeAiMenuOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            // 菜单本身
            Positioned(
              left: buttonGlobalPosition.dx,
              top: buttonGlobalPosition.dy + buttonSize.height + 4,
              child: PresetQuickMenuRefactored(
                requestType: requestType,
                selectedText: selectedText,
                defaultModel: _selectedModel,
                onPresetSelected: (preset) {
                  _removeAiMenuOverlay();
                  _handlePresetSelection(preset, selectedText);
                },
                onAdjustAndGenerate: () {
                  _removeAiMenuOverlay();
                  _handleAdjustAndGenerate(mode, selectedText);
                },
                onPresetWithModelSelected: (preset, model) {
                  _removeAiMenuOverlay();
                  _handlePresetWithModelSelection(preset, model, selectedText);
                },
                onStreamingGenerate: (request, model) {
                  _removeAiMenuOverlay();
                  _handleStreamingGeneration(request, model);
                },
                onMenuClosed: _removeAiMenuOverlay,
                novel: widget.novel,
                settings: widget.settings,
                settingGroups: widget.settingGroups,
                snippets: widget.snippets,
              ),
            ),
          ],
        ),
      ),
    );
    
    _aiMenuOverlay = overlayEntry;
    Overlay.of(context).insert(overlayEntry);
  }

  /// 从模式字符串获取AIRequestType
  AIRequestType _getRequestTypeFromMode(String mode) {
    return switch (mode) {
      'expand' => AIRequestType.expansion,
      'rewrite' => AIRequestType.refactor,
      'compress' => AIRequestType.summary,
      _ => AIRequestType.expansion,
    };
  }


  /// 处理预设选择
  void _handlePresetSelection(AIPromptPreset preset, String selectedText) {
    AppLogger.i('SelectionToolbar', '选择预设: ${preset.displayName}');
    
    // TODO: 这里需要实现预设应用逻辑
    // 1. 从预设中提取模型配置
    // 2. 构建UniversalAIRequest
    // 3. 启动流式生成
    
    TopToast.info(context, '使用预设"${preset.displayName}"处理文本...');
    
    // 示例：构建基本的AI请求
    final requestType = _getRequestTypeFromMode(_currentAiMode ?? 'expand');
    
    // 这里需要根据预设内容构建完整的请求
    // 暂时使用默认模型进行处理
    if (_selectedModel != null) {
      final request = UniversalAIRequest(
        requestType: requestType,
        userId: AppConfig.userId ?? 'current_user', // 从AppConfig获取当前用户ID
        novelId: widget.novel?.id,
        selectedText: selectedText,
        modelConfig: _selectedModel,
        prompt: preset.userPrompt,
        instructions: preset.systemPrompt,
      );
      
      // 将UserAIModelConfigModel包装为PrivateAIModel
      final unifiedModel = PrivateAIModel(_selectedModel!);
      _handleStreamingGeneration(request, unifiedModel);
    } else {
      TopToast.warning(context, '请先配置AI模型');
    }
  }

  /// 🚀 处理预设+模型级联选择 - 支持统一AI模型
  void _handlePresetWithModelSelection(AIPromptPreset preset, UnifiedAIModel model, String selectedText) {
    AppLogger.i('SelectionToolbar', '级联选择: 预设=${preset.displayName}, 模型=${model.displayName} (公共:${model.isPublic})');
    
    // 关闭AI菜单
    _removeAiMenuOverlay();
    
    // 构建AI请求
    final requestType = _getRequestTypeFromMode(_currentAiMode ?? 'expand');
    
    // 构建模型配置
    late UserAIModelConfigModel modelConfig;
    if (model.isPublic) {
      // 对于公共模型，创建临时的模型配置
      final publicModel = (model as PublicAIModel).publicConfig;
      modelConfig = UserAIModelConfigModel.fromJson({
        'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
        'userId': AppConfig.userId ?? 'current_user', // 从AppConfig获取当前用户ID
        'name': publicModel.displayName,
        'alias': publicModel.displayName,
        'modelName': publicModel.modelId,
        'provider': publicModel.provider,
        'apiEndpoint': '', // 公共模型没有单独的apiEndpoint
        'isDefault': false,
        'isValidated': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } else {
      // 对于私有模型，直接使用用户配置
      modelConfig = (model as PrivateAIModel).userConfig;
    }
    
    final request = UniversalAIRequest(
      requestType: requestType,
      userId: AppConfig.userId ?? 'current_user', // 从AppConfig获取当前用户ID
      novelId: widget.novel?.id,
      selectedText: selectedText,
      modelConfig: modelConfig,
      prompt: preset.userPrompt,
      instructions: preset.systemPrompt,
      metadata: {
        'action': requestType.name,
        'source': 'selection_toolbar',
        'presetId': preset.presetId,
        'modelName': model.modelId,
        'modelProvider': model.provider,
        'modelConfigId': model.id,
        'isPublicModel': model.isPublic,
        if (model.isPublic) 'publicModelConfigId': (model as PublicAIModel).publicConfig.id,
        if (model.isPublic) 'publicModelId': (model as PublicAIModel).publicConfig.id,
      },
    );
    
    // 显示选择信息
    TopToast.info(context, '使用"${model.displayName}"运行预设"${preset.displayName}"');
    
    // 启动流式生成
    _handleStreamingGeneration(request, model);
  }

  // 🚀 注释：旧的模型选择逻辑已移至PresetQuickMenu组件
  // 以下方法已不再需要，因为现在使用预设快捷菜单替代直接的模型选择

  /// 处理调整并生成
  void _handleAdjustAndGenerate(String mode, String selectedText) {
    final modeText = mode == 'expand' ? '扩写' : mode == 'rewrite' ? '重构' : '缩写';
    AppLogger.i('SelectionToolbar', '显示${modeText}设置对话框，选中文本: ${selectedText.substring(0, selectedText.length.clamp(0, 50))}...');
    
    // 🚀 获取默认模型配置
    UserAIModelConfigModel? modelToUse = _selectedModel;
    if (modelToUse == null) {
      // 使用BlocBuilder模式获取默认模型
      final aiConfigBloc = BlocProvider.of<AiConfigBloc>(context, listen: false);
      final aiConfigState = aiConfigBloc.state;
      final validatedConfigs = aiConfigState.validatedConfigs;
      
      if (aiConfigState.defaultConfig != null &&
          validatedConfigs.any((c) => c.id == aiConfigState.defaultConfig!.id)) {
        modelToUse = aiConfigState.defaultConfig;
      } else if (validatedConfigs.isNotEmpty) {
        modelToUse = validatedConfigs.first;
      }
      
      // 更新当前选中模型，避免下次重复查找
      _selectedModel = modelToUse;
      
      AppLogger.i('SelectionToolbar', '自动选择默认模型: ${modelToUse?.alias ?? 'null'}');
    }
    
    // 添加调试信息
    AppLogger.d('SelectionToolbar', '传入数据检查:');
    AppLogger.d('SelectionToolbar', '- Novel: ${widget.novel?.title ?? 'null'}');
    AppLogger.d('SelectionToolbar', '- Settings: ${widget.settings.length}');
    AppLogger.d('SelectionToolbar', '- Setting Groups: ${widget.settingGroups.length}');
    AppLogger.d('SelectionToolbar', '- Snippets: ${widget.snippets.length}');
    AppLogger.d('SelectionToolbar', '- Selected Model: ${modelToUse?.alias ?? 'null'}');
    
    // 根据模式显示对应的表单对话框
    switch (mode) {
      case 'expand':
        showExpansionDialog(
          context,
          selectedText: selectedText,
          selectedModel: modelToUse,
          novel: widget.novel,
          settings: widget.settings,
          settingGroups: widget.settingGroups,
          snippets: widget.snippets,
          onGenerate: () => _handleDirectGeneration(mode, selectedText),
          onStreamingGenerate: (request, model) => _handleStreamingGeneration(request, model),
        );
        break;
      case 'rewrite':
        showRefactorDialog(
          context,
          selectedText: selectedText,
          selectedModel: modelToUse,
          novel: widget.novel,
          settings: widget.settings,
          settingGroups: widget.settingGroups,
          snippets: widget.snippets,
          onGenerate: () => _handleDirectGeneration(mode, selectedText),
          onStreamingGenerate: (request, model) => _handleStreamingGeneration(request, model),
        );
        break;
      case 'compress':
        showSummaryDialog(
          context,
          selectedText: selectedText,
          selectedModel: modelToUse,
          novel: widget.novel,
          settings: widget.settings,
          settingGroups: widget.settingGroups,
          snippets: widget.snippets,
          onGenerate: () => _handleDirectGeneration(mode, selectedText),
          onStreamingGenerate: (request, model) => _handleStreamingGeneration(request, model),
        );
        break;
    }
  }

  /// 处理直接生成（从表单对话框触发）
  void _handleDirectGeneration(String mode, String selectedText) {
    final modeText = mode == 'expand' ? '扩写' : mode == 'rewrite' ? '重构' : '缩写';
    AppLogger.i('SelectionToolbar', '开始AI生成: $modeText, 模型: ${_selectedModel?.alias ?? '未选择'}');
    
    // TODO: 实现实际的AI生成逻辑
    TopToast.info(context, '开始${modeText}选中内容...');
  }


  // 重载方法支持UnifiedAIModel
  void _handleStreamingGeneration(UniversalAIRequest request, UnifiedAIModel model) {
    AppLogger.i('SelectionToolbar', '启动流式生成: ${request.requestType}, 模型: ${model.displayName} (公共:${model.isPublic})');
    
    // 先通知父组件开始流式生成（⚠️ 必须在隐藏工具栏之前，避免回调丢失）
    if (widget.onStreamingGenerationStarted != null) {
      widget.onStreamingGenerationStarted!(request, model);
    } else {
      AppLogger.w('SelectionToolbar', '没有流式生成回调处理器');
      // 显示默认消息
      TopToast.info(context, '开始流式生成...');
    }

    // 最后隐藏工具栏
    widget.onClosed?.call();
  }

}

/// 下拉菜单项数据类
class _DropdownItem {
  final String text;
  final VoidCallback onTap;

  const _DropdownItem(this.text, this.onTap);
}
