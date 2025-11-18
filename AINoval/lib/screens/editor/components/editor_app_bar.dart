import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:ainoval/screens/editor/components/immersive_mode_navigation.dart';

import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;
import 'package:ainoval/widgets/common/credit_display.dart';

class EditorAppBar extends StatelessWidget implements PreferredSizeWidget { // 新增写作按钮回调

  const EditorAppBar({
    super.key,
    required this.novelTitle,
    required this.wordCount,
    required this.isSaving,
    required this.lastSaveTime,
    required this.onBackPressed,
    required this.onChatPressed,
    required this.isChatActive,
    required this.onAiConfigPressed,
    required this.isSettingsActive,
    required this.onPlanPressed,
    required this.isPlanActive,
    required this.isWritingActive,
    this.onWritePressed, // 新增可选参数
    this.onAIGenerationPressed, // For AI Scene Generation
    this.onAISummaryPressed,
    this.onAutoContinueWritingPressed, 
    this.onAISettingGenerationPressed, // New: For AI Setting Generation
    this.onNextOutlinePressed,
    this.isAIGenerationActive = false, // This might now represent the dropdown itself or a specific item
    this.isAISummaryActive = false, // New: For AI Summary panel active state
    this.isAIContinueWritingActive = false, // New: For AI Continue Writing panel active state
    this.isAISettingGenerationActive = false, // New: For AI Setting Generation panel active state
    this.isNextOutlineActive = false,
    this.isDirty = false, // 新增: 是否存在未保存修改
    this.editorBloc, // 🚀 新增：编辑器BLoC实例，用于沉浸模式
  });
  final String novelTitle;
  final int wordCount;
  final bool isSaving;
  final DateTime? lastSaveTime;
  final VoidCallback onBackPressed;
  final VoidCallback onChatPressed;
  final bool isChatActive;
  final VoidCallback onAiConfigPressed;
  final bool isSettingsActive;
  final VoidCallback onPlanPressed;
  final bool isPlanActive;
  final bool isWritingActive;
  final VoidCallback? onWritePressed;
  final VoidCallback? onAIGenerationPressed; // AI 生成场景
  final VoidCallback? onAISummaryPressed;    // AI 生成摘要
  final VoidCallback? onAutoContinueWritingPressed; // 自动续写
  final VoidCallback? onAISettingGenerationPressed; // AI 生成设定 (New)
  final VoidCallback? onNextOutlinePressed;
  final bool isAIGenerationActive; // AI 生成场景面板激活状态
  final bool isAISummaryActive; // AI 生成摘要面板激活状态 (New)
  final bool isAIContinueWritingActive; // AI 自动续写面板激活状态 (New)
  final bool isAISettingGenerationActive; // AI 生成设定面板激活状态 (New)
  final bool isNextOutlineActive;
  final bool isDirty; // 新增字段
  final editor_bloc.EditorBloc? editorBloc; // 🚀 新增：编辑器BLoC实例

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String lastSaveText = '从未保存';
    if (lastSaveTime != null) {
      final formatter = DateFormat('HH:mm:ss');
      lastSaveText = '上次保存: ${formatter.format(lastSaveTime!.toLocal())}';
    }
    if (isSaving) {
      lastSaveText = '正在保存...';
    // 保存进行中，保持橙色提示
    } else if (isDirty) {
        // 未保存，使用黄色提示并附带上次保存时间
        final unsavedText = '尚未保存';
        if (lastSaveTime != null) {
          final formatter = DateFormat('HH:mm:ss');
          lastSaveText = '$unsavedText · 上次保存: ${formatter.format(lastSaveTime!.toLocal())}';
        } else {
          lastSaveText = unsavedText;
        }
    }

    // 构建实际显示的字数文本
    final String wordCountText = '${wordCount.toString()} 字';
    
    // Determine if the main "AI生成" dropdown should appear active
    // It can be active if any of its sub-panels are active
    final bool isAnyAIPanelActive = isAIGenerationActive || 
                                  isAISummaryActive || 
                                  isAIContinueWritingActive ||
                                  isAISettingGenerationActive;

    return AppBar(
      titleSpacing: 0,
      automaticallyImplyLeading: false, // 禁用自动leading按钮
      title: Row(
        children: [
          // 返回按钮
          IconButton(
            icon: const Icon(Icons.arrow_back),
            splashRadius: 22,
            onPressed: onBackPressed,
          ),

          // 左对齐的功能图标区域（自适应 + 横向滚动）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 宽度阈值：不足则隐藏文字，仅显示图标
                final bool showLabels = constraints.maxWidth > 780;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 大纲按钮
                      _buildNavButton(
                        context: context,
                        icon: Icons.view_kanban_outlined,
                        label: '大纲',
                        isActive: isPlanActive,
                        onPressed: onPlanPressed,
                        showLabel: showLabels,
                      ),

                      // 写作按钮
                      _buildNavButton(
                        context: context,
                        icon: Icons.edit_outlined,
                        label: '写作',
                        isActive: isWritingActive,
                        onPressed: onWritePressed ?? () {},
                        showLabel: showLabels,
                      ),

                      // 🚀 沉浸模式按钮
                      if (editorBloc != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: ImmersiveModeNavigation(
                            editorBloc: editorBloc!,
                          ),
                        ),

                      // 设置按钮
                      _buildNavButton(
                        context: context,
                        icon: Icons.settings_outlined,
                        label: '设置',
                        isActive: isSettingsActive,
                        onPressed: onAiConfigPressed,
                        showLabel: showLabels,
                      ),

                      // AI生成按钮 (Dropdown) - 自适应
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: _buildAdaptiveAIDropdownButton(
                          context: context,
                          showLabel: showLabels,
                          isActive: isAnyAIPanelActive,
                        ),
                      ),

                      // 剧情推演按钮
/*                       _buildNavButton(
                        context: context,
                        icon: Icons.device_hub_outlined, // Changed icon for better distinction
                        label: '剧情推演',
                        isActive: isNextOutlineActive,
                        onPressed: onNextOutlinePressed ?? () {},
                        showLabel: showLabels,
                      ), */

                      // 聊天按钮
                      _buildNavButton(
                        context: context,
                        icon: Icons.chat_bubble_outline,
                        label: '聊天',
                        isActive: isChatActive,
                        onPressed: onChatPressed,
                        showLabel: showLabels,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        // 积分显示（优雅紧凑，放在最右侧靠前位置）
        const Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: CreditDisplay(size: CreditDisplaySize.medium),
        ),
        // Word Count and Save Status
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
             children: [
              Row(
                children: [
                  Icon(
                    Icons.text_fields,
                    size: 14,
                    color: WebTheme.getPrimaryColor(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    wordCountText,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    isSaving
                        ? Icons.sync
                        : (isDirty ? Icons.warning_amber_outlined : Icons.check_circle_outline),
                    size: 14,
                    color: isSaving
                        ? theme.colorScheme.tertiary
                        : (isDirty ? theme.colorScheme.tertiary : theme.colorScheme.secondary),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lastSaveText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSaving
                          ? theme.colorScheme.tertiary
                          : (isDirty ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      elevation: 0,
      shape: Border(
        bottom: BorderSide(
          color: theme.dividerColor,
          width: 1.0,
        ),
      ),
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
    );
  }

  // 构建导航按钮的辅助方法
  Widget _buildNavButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
    bool showLabel = true,
  }) {
    final theme = Theme.of(context);

    final ButtonStyle commonStyle = TextButton.styleFrom(
      backgroundColor: isActive
          ? WebTheme.getPrimaryColor(context).withAlpha(76)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: showLabel
          ? TextButton.icon(
              icon: Icon(
                icon,
                size: 20,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? WebTheme.getPrimaryColor(context)
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              style: commonStyle,
              onPressed: onPressed,
            )
          : TextButton(
              style: commonStyle,
              onPressed: onPressed,
              child: Icon(
                icon,
                size: 20,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  /// 自适应的 AI 下拉按钮：在窄屏时仅显示图标
  Widget _buildAdaptiveAIDropdownButton({
    required BuildContext context,
    required bool showLabel,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      tooltip: 'AI辅助',
      onSelected: (value) {
        if (value == 'scene') {
          onAIGenerationPressed?.call();
        } else if (value == 'summary') {
          onAISummaryPressed?.call();
        } else if (value == 'continue-writing') {
          onAutoContinueWritingPressed?.call();
        } else if (value == 'setting-generation') {
          onAISettingGenerationPressed?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'scene',
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: isAIGenerationActive ? WebTheme.getPrimaryColor(context) : null,
              ),
              const SizedBox(width: 8),
              Text(
                'AI生成场景',
                style: TextStyle(
                  color: isAIGenerationActive ? WebTheme.getPrimaryColor(context) : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'summary',
          child: Row(
            children: [
              Icon(
                Icons.summarize_outlined,
                color: isAISummaryActive ? WebTheme.getPrimaryColor(context) : null,
              ),
              const SizedBox(width: 8),
              Text(
                'AI生成摘要',
                style: TextStyle(
                  color: isAISummaryActive ? WebTheme.getPrimaryColor(context) : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'continue-writing',
          child: Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                color: isAIContinueWritingActive ? WebTheme.getPrimaryColor(context) : null,
              ),
              const SizedBox(width: 8),
              Text(
                '自动续写',
                style: TextStyle(
                  color: isAIContinueWritingActive ? WebTheme.getPrimaryColor(context) : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'setting-generation',
          child: Row(
            children: [
              Icon(
                Icons.auto_fix_high_outlined,
                color: isAISettingGenerationActive ? WebTheme.getPrimaryColor(context) : null,
              ),
              const SizedBox(width: 8),
              Text(
                'AI生成设定',
                style: TextStyle(
                  color: isAISettingGenerationActive ? WebTheme.getPrimaryColor(context) : null,
                ),
              ),
            ],
          ),
        ),
      ],
      child: showLabel
          ? TextButton.icon(
              icon: Icon(
                Icons.psychology_alt_outlined,
                size: 20,
                color: isActive
                    ? WebTheme.getPrimaryColor(context)
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: Row(
                children: [
                  Text(
                    'AI辅助',
                    style: TextStyle(
                      color: isActive
                          ? WebTheme.getPrimaryColor(context)
                          : theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: isActive
                        ? WebTheme.getPrimaryColor(context)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              style: TextButton.styleFrom(
                backgroundColor: isActive
                    ? WebTheme.getPrimaryColor(context).withAlpha(76)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: null,
            )
          : TextButton(
              style: TextButton.styleFrom(
                backgroundColor: isActive
                    ? WebTheme.getPrimaryColor(context).withAlpha(76)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: null,
              child: Icon(
                Icons.psychology_alt_outlined,
                size: 20,
                color: isActive
                    ? WebTheme.getPrimaryColor(context)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
