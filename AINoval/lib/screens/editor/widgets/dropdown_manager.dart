import 'package:ainoval/blocs/editor/editor_bloc.dart';
import 'package:ainoval/screens/editor/widgets/custom_dropdown.dart';
import 'package:ainoval/screens/editor/widgets/menu_definitions.dart';
import 'package:ainoval/screens/editor/widgets/preset_menu_definitions.dart';
import 'package:ainoval/services/ai_preset_service.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:flutter/material.dart';

/// 下拉菜单管理器
/// 
/// 用于统一构建和管理所有下拉菜单，包括Act、Chapter、Scene和Model的菜单
class DropdownManager {
  /// 菜单构建上下文
  final BuildContext context;
  
  /// 编辑器状态管理（模型菜单时可为null）
  final EditorBloc? editorBloc;
  
  /// 菜单显示设置
  final DropdownDisplaySettings displaySettings;

  DropdownManager({
    required this.context,
    required this.editorBloc,
    this.displaySettings = const DropdownDisplaySettings(),
  });

  /// 构建Act菜单
  Widget buildActMenu({
    required String actId,
    Function()? onRenamePressed,
    IconData? icon,
    String? tooltip,
  }) {
    return _buildMenu(
      menuItems: ActMenuDefinitions.getMenuItems(),
      id: actId,
      secondaryId: null,
      tertiaryId: null,
      onRenamePressed: onRenamePressed,
      icon: icon ?? Icons.more_vert,
      tooltip: tooltip ?? 'Act操作',
      width: displaySettings.actMenuWidth,
      align: displaySettings.actMenuAlign,
    );
  }

  /// 构建Chapter菜单
  Widget buildChapterMenu({
    required String actId,
    required String chapterId,
    Function()? onRenamePressed,
    IconData? icon,
    String? tooltip,
  }) {
    // 动态统计该章节下的场景数量，用作菜单顶部信息
    int? sceneCount;
    try {
      final state = editorBloc?.state;
      if (state is EditorLoaded) {
        final novel = state.novel;
        for (final act in novel.acts) {
          if (act.id == actId) {
            for (final chapter in act.chapters) {
              if (chapter.id == chapterId) {
                sceneCount = chapter.scenes.length;
                break;
              }
            }
            break;
          }
        }
      }
    } catch (_) {}

    // 构建带有“章节信息：共N个场景”的菜单项，放在最前面
    final List<dynamic> items = [];
    if (sceneCount != null) {
      items.add(MenuItemData(
        icon: Icons.info_outline,
        label: '共${sceneCount}个场景',
        onTap: null,
        disabled: true,
      ));
      items.add("divider");
    }
    items.addAll(ChapterMenuDefinitions.getMenuItems());

    return _buildMenu(
      menuItems: items,
      id: actId,
      secondaryId: chapterId,
      tertiaryId: null,
      onRenamePressed: onRenamePressed,
      icon: icon ?? Icons.more_vert,
      tooltip: tooltip ?? '章节操作',
      width: displaySettings.chapterMenuWidth,
      align: displaySettings.chapterMenuAlign,
    );
  }

  /// 构建Scene菜单
  Widget buildSceneMenu({
    required String actId,
    required String chapterId,
    required String sceneId,
    IconData? icon,
    String? tooltip,
  }) {
    return _buildMenu(
      menuItems: SceneMenuDefinitions.getMenuItems(),
      id: actId,
      secondaryId: chapterId,
      tertiaryId: sceneId,
      icon: icon ?? Icons.more_horiz,
      tooltip: tooltip ?? '场景操作',
      width: displaySettings.sceneMenuWidth,
      align: displaySettings.sceneMenuAlign,
    );
  }

  /// 构建Model菜单
  Widget buildModelMenu({
    required String configId,
    required bool isValidated,
    required bool isDefault,
    required bool isToolDefault,
    required Future<void> Function(String) onValidate,
    required Future<void> Function(String) onSetDefault,
    required Future<void> Function(String) onSetToolDefault,
    required Future<void> Function(String) onEdit,
    required Future<void> Function(String) onDelete,
    IconData? icon,
    String? tooltip,
  }) {
    final menuItems = ModelMenuDefinitions.getMenuItems(
      isValidated: isValidated,
      isDefault: isDefault,
      isToolDefault: isToolDefault,
      onValidate: onValidate,
      onSetDefault: onSetDefault,
      onSetToolDefault: onSetToolDefault,
      onEdit: onEdit,
      onDelete: onDelete,
    );

    return _buildModelMenu(
      menuItems: menuItems,
      configId: configId,
      icon: icon ?? Icons.more_vert,
      tooltip: tooltip ?? '模型操作',
      width: displaySettings.modelMenuWidth,
      align: displaySettings.modelMenuAlign,
    );
  }

  /// 构建预设菜单
  Widget buildPresetMenu({
    required String featureType,
    required Function() onCreatePreset,
    required Function() onManagePresets,
    required Function(AIPromptPreset preset) onPresetSelected,
    IconData? icon,
    String? tooltip,
  }) {
    return CustomDropdown(
      width: displaySettings.presetMenuWidth,
      align: displaySettings.presetMenuAlign,
      trigger: IconButton(
        icon: Icon(icon ?? Icons.bookmark_border, size: 18),
        onPressed: null, // 由CustomDropdown处理点击
        tooltip: tooltip ?? '预设管理',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        splashRadius: 20,
      ),
      child: FutureBuilder<List<dynamic>>(
        future: PresetMenuDefinitions.getDynamicMenuItems(
          featureType: featureType,
          onCreatePreset: onCreatePreset,
          onManagePresets: onManagePresets,
          onPresetSelected: onPresetSelected,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final menuItems = snapshot.data ?? [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildPresetMenuItemWidgets(
              menuItems,
              featureType,
            ),
          );
        },
      ),
    );
  }

  /// 内部方法：构建通用菜单
  Widget _buildMenu({
    required List<dynamic> menuItems,
    required String id,
    String? secondaryId,
    String? tertiaryId,
    Function()? onRenamePressed,
    required IconData icon,
    required String tooltip,
    double width = 240,
    String align = 'left',
  }) {
    return CustomDropdown(
      width: width,
      align: align,
      trigger: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: null, // 由CustomDropdown处理点击
        tooltip: tooltip,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        splashRadius: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildMenuItemWidgets(
          menuItems,
          id,
          secondaryId,
          tertiaryId,
          onRenamePressed,
        ),
      ),
    );
  }

  /// 内部方法：构建模型菜单
  Widget _buildModelMenu({
    required List<dynamic> menuItems,
    required String configId,
    required IconData icon,
    required String tooltip,
    double width = 180,
    String align = 'right',
  }) {
    return CustomDropdown(
      width: width,
      align: align,
      trigger: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: null, // 由CustomDropdown处理点击
        tooltip: tooltip,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        splashRadius: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildModelMenuItemWidgets(
          menuItems,
          configId,
        ),
      ),
    );
  }

  /// 构建菜单项列表
  List<Widget> _buildMenuItemWidgets(
    List<dynamic> menuItems,
    String id,
    String? secondaryId,
    String? tertiaryId,
    Function()? onRenamePressed,
  ) {
    final List<Widget> widgets = [];

    for (final item in menuItems) {
      if (item is String && item == "divider") {
        widgets.add(const DropdownDivider());
      } else if (item is MenuSectionData) {
        widgets.add(
          DropdownSection(
            title: item.title,
            children: item.items.map((menuItem) {
              return _buildSingleMenuItem(
                menuItem,
                id,
                secondaryId,
                tertiaryId,
                onRenamePressed,
              );
            }).toList(),
          ),
        );
      } else if (item is MenuItemData) {
        widgets.add(
          _buildSingleMenuItem(
            item,
            id,
            secondaryId,
            tertiaryId,
            onRenamePressed,
          ),
        );
      }
    }

    return widgets;
  }

  /// 构建模型菜单项列表
  List<Widget> _buildModelMenuItemWidgets(
    List<dynamic> menuItems,
    String configId,
  ) {
    final List<Widget> widgets = [];

    for (final item in menuItems) {
      if (item is String && item == "divider") {
        widgets.add(const DropdownDivider());
      } else if (item is ModelMenuSectionData) {
        widgets.add(
          DropdownSection(
            title: item.title,
            children: item.items.map((menuItem) {
              return _buildSingleModelMenuItem(menuItem, configId);
            }).toList(),
          ),
        );
      } else if (item is ModelMenuItemData) {
        widgets.add(_buildSingleModelMenuItem(item, configId));
      }
    }

    return widgets;
  }

  /// 构建单个菜单项
  Widget _buildSingleMenuItem(
    MenuItemData item,
    String id,
    String? secondaryId,
    String? tertiaryId,
    Function()? onRenamePressed,
  ) {
    // 特殊处理重命名操作，因为需要直接访问State
    Future<void> Function()? onTapHandler;
    if (item.label == '重命名Act' || item.label == '重命名章节') {
      onTapHandler = null;
    } else if (item.onTap != null) {
      onTapHandler = () async {
        await item.onTap!(context, editorBloc!, id, secondaryId, tertiaryId);
      };
    }

    return DropdownItem(
      icon: item.icon,
      label: item.label,
      hasSubmenu: item.hasSubmenu,
      disabled: item.disabled,
      isDangerous: item.isDangerous,
      onTap: onTapHandler,
    );
  }

  /// 构建单个模型菜单项
  Widget _buildSingleModelMenuItem(
    ModelMenuItemData item,
    String configId,
  ) {
    Future<void> Function()? onTapHandler;
    if (item.onTap != null) {
      onTapHandler = () async {
        await item.onTap!(configId);
      };
    }

    return DropdownItem(
      icon: item.icon,
      label: item.label,
      hasSubmenu: item.hasSubmenu,
      disabled: item.disabled,
      isDangerous: item.isDangerous,
      onTap: onTapHandler,
    );
  }

  /// 构建预设菜单项列表
  List<Widget> _buildPresetMenuItemWidgets(
    List<dynamic> menuItems,
    String featureType,
  ) {
    final List<Widget> widgets = [];
    final presetService = AIPresetService();

    for (final item in menuItems) {
      if (item is String && item == "divider") {
        widgets.add(const DropdownDivider());
      } else if (item is PresetMenuSectionData) {
        widgets.add(
          DropdownSection(
            title: item.title,
            children: item.items.map((menuItem) {
              return _buildSinglePresetMenuItem(menuItem, presetService, featureType);
            }).toList(),
            dividerAtBottom: item.dividerAtBottom,
          ),
        );
      } else if (item is PresetMenuItemData) {
        widgets.add(_buildSinglePresetMenuItem(item, presetService, featureType));
      }
    }

    return widgets;
  }

  /// 构建单个预设菜单项
  Widget _buildSinglePresetMenuItem(
    PresetMenuItemData item,
    AIPresetService presetService,
    String featureType,
  ) {
    Future<void> Function()? onTapHandler;
    if (item.onTap != null) {
      onTapHandler = () async {
        await item.onTap!(context, presetService, featureType);
      };
    }

    return DropdownItem(
      icon: item.icon,
      label: item.label,
      hasSubmenu: item.hasSubmenu,
      disabled: item.disabled,
      isDangerous: item.isDangerous,
      onTap: onTapHandler,
    );
  }
}

/// 下拉菜单显示设置
class DropdownDisplaySettings {
  final double actMenuWidth;
  final double chapterMenuWidth;
  final double sceneMenuWidth;
  final double modelMenuWidth;
  final double presetMenuWidth;
  final String actMenuAlign;
  final String chapterMenuAlign;
  final String sceneMenuAlign;
  final String modelMenuAlign;
  final String presetMenuAlign;

  const DropdownDisplaySettings({
    this.actMenuWidth = 240,
    this.chapterMenuWidth = 240,
    this.sceneMenuWidth = 240,
    this.modelMenuWidth = 180,
    this.presetMenuWidth = 280,
    this.actMenuAlign = 'left',
    this.chapterMenuAlign = 'right',
    this.sceneMenuAlign = 'right',
    this.modelMenuAlign = 'right',
    this.presetMenuAlign = 'right',
  });
} 