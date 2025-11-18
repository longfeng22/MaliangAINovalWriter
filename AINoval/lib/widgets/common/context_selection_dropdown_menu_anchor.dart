import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/models/context_selection_models.dart';
// 🎯 拖放功能
import 'package:ainoval/widgets/common/context_drop_target.dart';
import 'package:ainoval/utils/logger.dart';

/// 基于MenuAnchor的上下文选择下拉框组件（官方级联菜单实现）
class ContextSelectionDropdownMenuAnchor extends StatefulWidget {
  const ContextSelectionDropdownMenuAnchor({
    super.key,
    required this.data,
    required this.onSelectionChanged,
    this.placeholder = '选择上下文',
    this.maxHeight = 400,
    this.width,
    this.initialChapterId,
    this.initialSceneId,
    this.typeColorMap,
    this.typeColorResolver,
  });

  /// 上下文选择数据
  final ContextSelectionData data;

  /// 选择变化回调
  final ValueChanged<ContextSelectionData> onSelectionChanged;

  /// 占位符文字
  final String placeholder;

  /// 下拉框最大高度
  final double maxHeight;

  /// 宽度
  final double? width;

  /// 初始聚焦的章节ID（用于长列表初始滚动定位）
  final String? initialChapterId;

  /// 初始聚焦的场景ID（用于长列表初始滚动定位）
  final String? initialSceneId;

  /// 自定义类型-颜色映射（优先级低于 typeColorResolver）
  final Map<ContextSelectionType, Color>? typeColorMap;

  /// 自定义颜色解析器（优先级最高）
  final Color Function(ContextSelectionType type, BuildContext context)? typeColorResolver;

  @override
  State<ContextSelectionDropdownMenuAnchor> createState() => 
      _ContextSelectionDropdownMenuAnchorState();
}

class _ContextSelectionDropdownMenuAnchorState 
    extends State<ContextSelectionDropdownMenuAnchor> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    final double menuWidth = widget.width ?? 280;
    
    return MenuAnchor(
      controller: _menuController,
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.surfaceContainer,
        ),
        elevation: WidgetStateProperty.all(8),
        shadowColor: WidgetStateProperty.all(
          WebTheme.getShadowColor(context, opacity: 0.3),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
      builder: (context, controller, child) {
        return _buildTriggerButton(context, controller, isDark);
      },
      menuChildren: [
        // 头部操作栏
        _buildHeaderMenuItem(context, isDark, menuWidth),
        
        // 分割线
        const Divider(height: 1),

        // 🚀 基本选项：全部设定（与小说基本信息同类的基础项表现）
        if (_hasSettingsRoot()) _buildAllSettingsQuickMenuItem(context, isDark, menuWidth),
        
        // 分割线（与主菜单分隔）
        if (_hasSettingsRoot()) const Divider(height: 1),
        
        // 菜单项（对长列表进行虚拟化构建）
        ...widget.data.availableItems.map((item) => _buildMenuItem(item, context, menuWidth)),
        
        // 底部取消选择选项
        if (widget.data.selectedCount > 0) ...[
          const Divider(height: 1),
          _buildCancelSelectionMenuItem(context, isDark, menuWidth),
        ],
      ],
    );
  }

  /// 构建触发按钮
  Widget _buildTriggerButton(BuildContext context, MenuController controller, bool isDark) {
    // 🎯 构建按钮UI
    final buttonWidget = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            // 🚀 首次打开时，如果没有任何选择，则预选默认三项：最近5章摘要、最近5章内容、全部设定
            try {
              if (widget.data.selectedCount == 0) {
                final String nid = widget.data.novelId;
                final List<String> defaultIds = [
                  'recent_chapters_summary_' + nid,
                  'recent_chapters_content_' + nid,
                  'settings_' + nid,
                ];
                ContextSelectionData newData = widget.data;
                for (final id in defaultIds) {
                  if (widget.data.flatItems.containsKey(id)) {
                    newData = newData.selectItem(id);
                  }
                }
                if (newData.selectedCount > 0) {
                  widget.onSelectionChanged(newData);
                }
              }
            } catch (_) {}
            controller.open();
          }
        },
        borderRadius: BorderRadius.circular(6),
        splashColor: WebTheme.getPrimaryColor(context).withOpacity(0.10),
        highlightColor: WebTheme.getPrimaryColor(context).withOpacity(0.12),
        child: Container(
          height: 36, // 与标签高度保持一致
          padding: const EdgeInsets.only(left: 6, right: 10, top: 8, bottom: 8), // 调整垂直内边距以居中
          decoration: BoxDecoration(
            color: Colors.transparent, // 背景透明
            border: Border.all(
              color: Colors.transparent, // 边框透明
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6), // rounded-md
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min, // 让按钮自适应内容大小
            children: [
              // 加号图标
              Icon(
                Icons.add,
                size: 16, // w-4 h-4 对应16px
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6), // gap-1.5 对应约6px
              
              // Context文本
              Text(
                'Context',
                style: TextStyle(
                  fontSize: 12, // text-xs 对应12px
                  fontWeight: FontWeight.w600, // font-semibold
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5, // tracking-wide
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
    // 🎯 包装为拖放目标
    return ContextDropTarget(
      onAccept: (dragData) {
        AppLogger.i('ContextSelectionDropdownMenuAnchor', 
            '🎯 接收拖放: ${dragData.title} (${dragData.type})');
        
        // 根据拖放的数据类型，自动添加到上下文选择
        try {
          // 🎯 智能ID映射
          String actualId = dragData.id;
          
          // 章节和场景需要添加 flat_ 前缀
          if (actualId.startsWith('chapter_')) {
            actualId = 'flat_${actualId.substring(8)}';
          } else if (actualId.startsWith('scene_')) {
            actualId = 'flat_${actualId.substring(6)}';
          }
          // 片段(snippet_xxx)、设定项、设定组(setting_group_xxx)、设定分类(type_xxx)直接使用原始ID，无需转换
          
          // 如果flatItems中存在这个ID，则选中它
          if (widget.data.flatItems.containsKey(actualId)) {
            final newData = widget.data.selectItem(actualId);
            widget.onSelectionChanged(newData);
            
            AppLogger.i('ContextSelectionDropdownMenuAnchor', 
                '✅ 成功添加到上下文: ${dragData.title} (ID: $actualId)');
          } else {
            AppLogger.w('ContextSelectionDropdownMenuAnchor', 
                '⚠️ 无法找到对应的上下文项: ${dragData.id} -> $actualId\n'
                '可用的ID示例: ${widget.data.flatItems.keys.take(5).join(", ")}...');
          }
        } catch (e, stackTrace) {
          AppLogger.e('ContextSelectionDropdownMenuAnchor', 
              '❌ 添加上下文失败: ${dragData.id}', e, stackTrace);
        }
      },
      child: buttonWidget,
    );
  }

  /// 是否存在"全部设定"根节点（settings_${novelId}）
  bool _hasSettingsRoot() {
    final String settingsId = 'settings_' + widget.data.novelId;
    return widget.data.flatItems.containsKey(settingsId);
  }

  /// 构建“全部设定”快捷菜单项（表现为基础项，类型视觉与小说基本信息一致）
  Widget _buildAllSettingsQuickMenuItem(BuildContext context, bool isDark, double menuWidth) {
    final String settingsId = 'settings_' + widget.data.novelId;
    final bool isSelected = widget.data.selectedItems.containsKey(settingsId) ||
        (widget.data.flatItems[settingsId]?.selectionState.isSelected == true);

    return MenuItemButton(
      style: _getMenuItemButtonStyle(menuWidth),
      onPressed: () {
        final item = widget.data.flatItems[settingsId];
        if (item != null) {
          _onItemTap(item);
        }
      },
      child: SizedBox(
        width: menuWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 选择状态图标（使用非容器样式的选择图标）
            isSelected
                ? Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary)
                : Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                    ),
                  ),
            const SizedBox(width: 12),
            // 使用“小说基本信息”类型的图标与颜色表现
            Icon(
              ContextSelectionType.novelBasicInfo.icon,
              size: 16,
              color: _getTypeIconColor(ContextSelectionType.novelBasicInfo, context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '全部设定',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '角色与世界观的全部设定',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建头部菜单项
  Widget _buildHeaderMenuItem(BuildContext context, bool isDark, double menuWidth) {
    return MenuItemButton(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        minimumSize: WidgetStateProperty.all(Size(menuWidth, 44)),
        alignment: Alignment.centerLeft,
      ),
      onPressed: null, // 禁用点击
      child: SizedBox(
        width: menuWidth,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '添加上下文',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          const Spacer(),
          
          // 清除选择按钮
          if (widget.data.selectedCount > 0)
            InkWell(
              onTap: () {
                _clearSelection();
                _menuController.close();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '清除选择',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem(ContextSelectionItem item, BuildContext context, double menuWidth) {
    final isDark = WebTheme.isDarkMode(context);
    final bool isGroup = item.type == ContextSelectionType.contentFixedGroup || item.type == ContextSelectionType.summaryFixedGroup;
    
    if (isGroup) {
      // 固定分组（内容/摘要）：使用普通子项列表，避免可滚动视图在菜单中的布局问题
      return SubmenuButton(
        style: _getMenuItemButtonStyle(menuWidth),
        child: _buildMenuItemContent(context, item, true),
        menuChildren: [
          // 直接渲染子项列表（数量较少，无需虚拟化）
          ...item.children.map((child) => _buildSubMenuItem(child, context, menuWidth)),
          const Divider(height: 1),
          _buildSubmenuCancelSelectionMenuItem(item, isDark, menuWidth),
        ],
      );
    }

    if (item.hasChildren && item.children.isNotEmpty) {
      // 有子项的容器项 - 使用SubmenuButton
      return SubmenuButton(
        style: _getMenuItemButtonStyle(menuWidth),
        child: _buildMenuItemContent(context, item, true),
        // 用 Builder 包裹，确保子菜单获得稳定的布局上下文
        menuChildren: [
          Builder(builder: (subCtx) {
            return _buildVirtualizedSubmenuList(
              parent: item,
              context: subCtx,
              // 行高大约44，对齐 _getMenuItemButtonStyle 的 minimumSize
              itemExtent: 44,
              maxHeight: widget.maxHeight,
              menuWidth: menuWidth,
            );
          }),
          const Divider(height: 1),
          _buildSubmenuCancelSelectionMenuItem(item, isDark, menuWidth),
        ],
      );
    } else if (item.hasChildren && item.children.isEmpty) {
      // 空容器项 - 使用SubmenuButton显示空状态
      return SubmenuButton(
        style: _getMenuItemButtonStyle(menuWidth),
        child: _buildMenuItemContent(context, item, true),
        menuChildren: [
          _buildEmptySubmenuContent(item, isDark, menuWidth),
        ],
      );
    } else {
      // 叶子节点项 - 使用MenuItemButton
      return MenuItemButton(
        style: _getMenuItemButtonStyle(menuWidth),
        onPressed: () => _onItemTap(item),
        child: SizedBox(width: menuWidth, child: _buildMenuItemContent(context, item, false)),
      );
    }
  }

  /// 使用虚拟化方式渲染子菜单列表，支持初始滚动到目标章节/场景
  Widget _buildVirtualizedSubmenuList({
    required ContextSelectionItem parent,
    required BuildContext context,
    required double itemExtent,
    required double maxHeight,
    required double menuWidth,
  }) {
    // 计算初始滚动定位索引
    final int initialIndex = _computeInitialIndexForParent(parent);

    // 计算高度：最多不超过 maxHeight，也不超过总高度
    final double computedHeight = (parent.children.length * itemExtent).clamp(
      itemExtent,
      maxHeight,
    );

    // 使用固定高度盒子，确保子 ListView 获得有界约束，避免 RenderBox 未布局错误
    return SizedBox(
      height: computedHeight,
      width: menuWidth,
      child: _VirtualizedMenuList(
        items: parent.children,
        itemExtent: itemExtent,
        initialIndex: initialIndex >= 0 ? initialIndex : null,
        itemBuilder: (child) => _buildSubMenuItem(child, context, menuWidth),
      ),
    );
  }

  /// 计算在父级子项中的初始索引，用于滚动到当前章节/场景
  int _computeInitialIndexForParent(ContextSelectionItem parent) {
    // 优先使用场景定位
    if (widget.initialSceneId != null && widget.initialSceneId!.isNotEmpty) {
      final sceneId = widget.initialSceneId!;
      // 支持平铺ID（flat_ 前缀）与层级ID
      final flatSceneId = 'flat_${sceneId}';
      for (int i = 0; i < parent.children.length; i++) {
        final child = parent.children[i];
        if (child.id == sceneId || child.id == flatSceneId) {
          return i;
        }
      }
    }
    // 其次使用章节定位
    if (widget.initialChapterId != null && widget.initialChapterId!.isNotEmpty) {
      final chapterId = widget.initialChapterId!;
      final flatChapterId = 'flat_${chapterId}';
      for (int i = 0; i < parent.children.length; i++) {
        final child = parent.children[i];
        if (child.id == chapterId || child.id == flatChapterId) {
          return i;
        }
      }
    }
    return -1;
  }

  /// 构建子菜单项
  Widget _buildSubMenuItem(ContextSelectionItem item, BuildContext context, double menuWidth) {
    return MenuItemButton(
      style: _getMenuItemButtonStyle(menuWidth),
      onPressed: () => _onItemTap(item),
      child: SizedBox(width: menuWidth, child: _buildMenuItemContent(context, item, false)),
    );
  }

  /// 构建菜单项内容
  Widget _buildMenuItemContent(BuildContext context, ContextSelectionItem item, bool isContainer) {
    final bool isRadioGroupChild = item.parentId != null && (widget.data.flatItems[item.parentId!]!.type == ContextSelectionType.contentFixedGroup || widget.data.flatItems[item.parentId!]!.type == ContextSelectionType.summaryFixedGroup);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 选择状态图标（固定分组子项用单选样式）
        if (isRadioGroupChild)
          Icon(
            item.selectionState.isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: item.selectionState.isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
          )
        else
          _buildSelectionIcon(context, item.selectionState, isContainer),
        
        const SizedBox(width: 12),
        
        // 类型图标
        Icon(
          item.type.icon,
          size: 16,
          color: _getTypeIconColor(item.type, context),
        ),
        
        const SizedBox(width: 12),
        
        // 标题和副标题
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: item.selectionState.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.displaySubtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.displaySubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 构建空子菜单内容
  Widget _buildEmptySubmenuContent(ContextSelectionItem item, bool isDark, double menuWidth) {
    String emptyMessage;
    
    switch (item.type) {
      case ContextSelectionType.acts:
        emptyMessage = '没有卷';
        break;
      case ContextSelectionType.chapters:
        emptyMessage = '没有章节';
        break;
      case ContextSelectionType.scenes:
        emptyMessage = '没有场景';
        break;
      default:
        emptyMessage = '暂无内容';
        break;
    }
    
    // 使用固定高度的容器，避免未布局的 TapRegion/hitTest 问题
    return SizedBox(
      height: 80,
      width: menuWidth,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 获取菜单项按钮样式
  ButtonStyle _getMenuItemButtonStyle(double menuWidth) {
    return ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      minimumSize: WidgetStateProperty.all(Size(menuWidth, 44)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
    );
  }

  /// 构建选择状态图标
  Widget _buildSelectionIcon(BuildContext context, SelectionState state, bool isContainer) {
    final scheme = Theme.of(context).colorScheme;
    // 容器类型（Acts、Chapters、Scenes）的显示逻辑
    if (isContainer) {
      switch (state) {
        case SelectionState.fullySelected:
        case SelectionState.partiallySelected:
          // 容器有子项被选中时显示圆点
          return Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSurfaceVariant,
            ),
            child: Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.onSurface,
                ),
              ),
            ),
          );
        case SelectionState.unselected:
          // 容器没有子项被选中时不显示图标
          return const SizedBox(width: 16, height: 16);
      }
    }
    
    // 非容器类型（Full Novel Text、Full Outline等）的显示逻辑
    switch (state) {
      case SelectionState.fullySelected:
        return Icon(
          Icons.check_circle,
          size: 16,
          color: scheme.primary,
        );
      case SelectionState.partiallySelected:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.outlineVariant,
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
      case SelectionState.unselected:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1.5,
            ),
          ),
        );
    }
  }

  /// 获取类型图标颜色
  Color _getTypeIconColor(ContextSelectionType type, BuildContext context) {
    // 优先使用外部解析器
    if (widget.typeColorResolver != null) {
      try {
        return widget.typeColorResolver!(type, context);
      } catch (_) {}
    }
    // 其次使用外部映射
    if (widget.typeColorMap != null) {
      final mapped = widget.typeColorMap![type];
      if (mapped != null) return mapped;
    }
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case ContextSelectionType.fullNovelText:
        return scheme.primary;
      case ContextSelectionType.fullOutline:
        return scheme.secondary;
      case ContextSelectionType.contentFixedGroup:
        return scheme.primary;
      case ContextSelectionType.summaryFixedGroup:
        return scheme.secondary;
      case ContextSelectionType.currentSceneContent:
        return scheme.primary;
      case ContextSelectionType.currentSceneSummary:
        return scheme.secondary;
      case ContextSelectionType.currentChapterContent:
        return scheme.primary;
      case ContextSelectionType.currentChapterSummaries:
        return scheme.secondary;
      case ContextSelectionType.previousChaptersContent:
        return scheme.primary;
      case ContextSelectionType.previousChaptersSummary:
        return scheme.secondary;
      case ContextSelectionType.novelBasicInfo:
        return scheme.tertiary;
      case ContextSelectionType.recentChaptersContent:
        return scheme.primary;
      case ContextSelectionType.recentChaptersSummary:
        return scheme.secondary;
      case ContextSelectionType.acts:
        return scheme.tertiary;
      case ContextSelectionType.chapters:
        return scheme.secondary;
      case ContextSelectionType.scenes:
        return scheme.primary;
      case ContextSelectionType.snippets:
        return scheme.secondary;
      case ContextSelectionType.settings:
        return scheme.tertiary;
      case ContextSelectionType.settingGroups:
        return scheme.secondary;
      case ContextSelectionType.settingsByType:
        return scheme.secondary;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  /// 获取显示文本
  // String _getDisplayText() {
  //   if (widget.data.selectedCount == 0) {
  //     return widget.placeholder;
  //   } else if (widget.data.selectedCount == 1) {
  //     final selectedItem = widget.data.selectedItems.values.first;
  //     return selectedItem.title;
  //   } else {
  //     return '已选择 ${widget.data.selectedCount} 项';
  //   }
  // }

  /// 项目点击处理
  void _onItemTap(ContextSelectionItem item) {
    ContextSelectionData newData;
    
    if (item.selectionState.isSelected) {
      // 取消选择
      newData = widget.data.deselectItem(item.id);
    } else {
      // 选择
      newData = widget.data.selectItem(item.id);
    }
    
    widget.onSelectionChanged(newData);
    
    // 保持菜单开启，允许多选
    // 如果需要选择后自动关闭，可以调用 _menuController.close();
  }

  /// 清除选择
  void _clearSelection() {
    final newData = ContextSelectionData(
      novelId: widget.data.novelId,
      availableItems: widget.data.availableItems,
      flatItems: widget.data.flatItems.map(
        (key, value) => MapEntry(key, value.copyWith(selectionState: SelectionState.unselected)),
      ),
    );
    
    widget.onSelectionChanged(newData);
  }

  /// 构建取消选择菜单项
  Widget _buildCancelSelectionMenuItem(BuildContext context, bool isDark, double menuWidth) {
    return MenuItemButton(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        minimumSize: WidgetStateProperty.all(Size(menuWidth, 44)),
        alignment: Alignment.centerLeft,
      ),
      onPressed: () {
        _clearSelection();
        _menuController.close();
      },
      child: SizedBox(
        width: menuWidth,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.clear_all,
            size: 16,
            color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
          ),
          const SizedBox(width: 12),
          Text(
            '取消当前所选的选择',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? WebTheme.darkGrey700 : WebTheme.grey600,
              height: 1.2,
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 构建底部留白
  // Widget _buildBottomSpacing() {
  //   return MenuItemButton(
  //     style: ButtonStyle(
  //       padding: WidgetStateProperty.all(EdgeInsets.zero),
  //       backgroundColor: WidgetStateProperty.all(Colors.transparent),
  //       overlayColor: WidgetStateProperty.all(Colors.transparent),
  //       minimumSize: WidgetStateProperty.all(const Size.fromHeight(20)),
  //     ),
  //     onPressed: null,
  //     child: const SizedBox.shrink(),
  //   );
  // }

  /// 构建子菜单取消选择菜单项
  Widget _buildSubmenuCancelSelectionMenuItem(ContextSelectionItem parentItem, bool isDark, double menuWidth) {
    // 检查父级项目下是否有选中的子项
    final hasSelectedChildren = parentItem.children.any((child) => child.selectionState.isSelected);
    
    // 在调试模式下输出详细信息, 生产环境默认静默
    if (kDebugMode) {
      // debug logs removed in release
    }
    
    // 🚀 即使没有选中项也显示，但禁用状态（用于调试）
    // if (!hasSelectedChildren) {
    //   return const SizedBox.shrink();
    // }
    
    return MenuItemButton(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        minimumSize: WidgetStateProperty.all(Size(menuWidth, 44)),
        alignment: Alignment.centerLeft,
        // 🚀 如果没有选中项，禁用按钮但仍显示
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (!hasSelectedChildren) {
            return Colors.transparent;
          }
          return null;
        }),
      ),
      onPressed: hasSelectedChildren ? () {
        if (kDebugMode) //debugPrint('🚀 执行子菜单取消选择: ${parentItem.title}');
        _clearSubmenuSelection(parentItem);
        _menuController.close();
      } : null, // 🚀 没有选中项时禁用
      child: SizedBox(
        width: menuWidth,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.clear_outlined,
            size: 16,
            color: hasSelectedChildren 
                ? (isDark ? WebTheme.darkGrey500 : WebTheme.grey500)
                : (isDark ? WebTheme.darkGrey300 : WebTheme.grey300), // 🚀 禁用状态颜色
          ),
          const SizedBox(width: 12),
          Text(
            hasSelectedChildren 
                ? '取消当前子菜单选择'
                : '取消当前子菜单选择 (无选中项)', // 🚀 显示状态信息
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: hasSelectedChildren
                  ? (isDark ? WebTheme.darkGrey700 : WebTheme.grey600)
                  : (isDark ? WebTheme.darkGrey400 : WebTheme.grey400), // 🚀 禁用状态颜色
              height: 1.2,
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 清除子菜单选择
  void _clearSubmenuSelection(ContextSelectionItem parentItem) {
    ContextSelectionData newData = widget.data;
    
    
    widget.onSelectionChanged(newData);
  }
}

/// 上下文选择下拉框构建器（MenuAnchor版本）
class ContextSelectionDropdownBuilder {
  /// 创建基于MenuAnchor的上下文选择下拉框
  static Widget buildMenuAnchor({
    required ContextSelectionData data,
    required ValueChanged<ContextSelectionData> onSelectionChanged,
    String placeholder = '选择上下文',
    double? width,
    double maxHeight = 400,
    String? initialChapterId,
    String? initialSceneId,
    Map<ContextSelectionType, Color>? typeColorMap,
    Color Function(ContextSelectionType type, BuildContext context)? typeColorResolver,
  }) {
    return ContextSelectionDropdownMenuAnchor(
      data: data,
      onSelectionChanged: onSelectionChanged,
      placeholder: placeholder,
      width: width,
      maxHeight: maxHeight,
      initialChapterId: initialChapterId,
      initialSceneId: initialSceneId,
      typeColorMap: typeColorMap,
      typeColorResolver: typeColorResolver,
    );
  }
} 

/// 子菜单虚拟化列表，支持初始定位到指定索引
class _VirtualizedMenuList extends StatefulWidget {
  const _VirtualizedMenuList({
    required this.items,
    required this.itemExtent,
    required this.itemBuilder,
    this.initialIndex,
  });

  final List<ContextSelectionItem> items;
  final double itemExtent;
  final int? initialIndex;
  final Widget Function(ContextSelectionItem item) itemBuilder;

  @override
  State<_VirtualizedMenuList> createState() => _VirtualizedMenuListState();
}

class _VirtualizedMenuListState extends State<_VirtualizedMenuList> {
  late final ScrollController _controller;
  bool _didJump = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    if (widget.initialIndex != null && widget.initialIndex! >= 0) {
      // 延迟到首帧后跳转，避免布局尚未完成导致的异常
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_didJump) {
          final double offset = widget.initialIndex! * widget.itemExtent;
          _controller.jumpTo(offset.clamp(0.0, (_controller.position.maxScrollExtent)));
          _didJump = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: ListView.builder(
          controller: _controller,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemExtent: widget.itemExtent,
          itemCount: widget.items.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          addSemanticIndexes: false,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            // 子项本身已经包含视觉与交互，这里直接返回
            return widget.itemBuilder(item);
          },
        ),
      ),
    );
  }
}