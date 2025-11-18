import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/widgets/common/top_toast.dart';

import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/screens/settings/widgets/ai_config_form.dart';
import 'package:ainoval/screens/settings/widgets/model_service_list_page.dart';
import 'package:ainoval/screens/settings/widgets/editor_settings_panel.dart';
import 'package:ainoval/screens/settings/widgets/membership_panel.dart' as membership;
import 'package:ainoval/screens/settings/widgets/account_management_panel.dart';
// import 'package:ainoval/widgets/common/settings_widgets.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_repository_impl.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/web_theme.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.onClose,
    required this.userId,
    this.editorSettings,
    this.onEditorSettingsChanged,
    required this.stateManager,
    this.initialCategoryIndex = 0,
  });
  final VoidCallback onClose;
  final String userId;
  final EditorSettings? editorSettings;
  final Function(EditorSettings)? onEditorSettingsChanged;
  final EditorStateManager stateManager;
  final int initialCategoryIndex;

  /// 账户管理分类的索引
  static const int accountManagementCategoryIndex = 1;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  int _selectedIndex = 0; // Track the selected category index
  UserAIModelConfigModel?
      _configToEdit; // Track config being edited, null for add mode
  bool _showAddEditForm = false; // Flag to show the add/edit form view
  late EditorSettings _editorSettings;
  // 🚀 新增：NovelRepository实例用于调用后端API
  late NovelRepositoryImpl _novelRepository;

  // Define category titles and icons (adjust as needed)
  final List<Map<String, dynamic>> _categories = [
    {'title': '模型服务', 'icon': Icons.cloud_queue},
    {'title': '账户管理', 'icon': Icons.account_circle_outlined},
    {'title': '会员与订阅', 'icon': Icons.workspace_premium},
    // {'title': '默认模型', 'icon': Icons.star_border}, // Example: Can be added later
    // {'title': '网络搜索', 'icon': Icons.search},
    // {'title': 'MCP 服务器', 'icon': Icons.dns},
    {'title': '常规设置', 'icon': Icons.settings_outlined},
    {'title': '显示设置', 'icon': Icons.display_settings},
    {'title': '主题设置', 'icon': Icons.palette_outlined},
    {'title': '编辑器设置', 'icon': Icons.edit_note},
    // {'title': '快捷方式', 'icon': Icons.shortcut},
    // {'title': '快捷助手', 'icon': Icons.assistant_photo},
    // {'title': '数据设置', 'icon': Icons.data_usage},
    // {'title': '关于我们\', 'icon': Icons.info_outline},
  ];

  @override
  void initState() {
    super.initState();
    _editorSettings = widget.editorSettings ?? const EditorSettings();
    // 🚀 初始化NovelRepository
    _novelRepository = NovelRepositoryImpl();
    // 设置初始分类索引
    _selectedIndex = widget.initialCategoryIndex;
  }

  void _showAddForm() {
    // <<< Explicitly trigger provider loading every time we enter add mode >>>
    // Ensure context is available and mounted before reading bloc
    if (mounted) {
      context.read<AiConfigBloc>().add(LoadAvailableProviders());
    }
    setState(() {
      _configToEdit = null; // Clear any previous edit state
      _showAddEditForm = true;
    });
  }

  void _hideAddEditForm() {
    setState(() {
      // Optionally clear BLoC state related to model loading if needed
      // context.read<AiConfigBloc>().add(ClearProviderModels());
      _configToEdit = null;
      _showAddEditForm = false;
    });
  }

  // 新增方法：显示编辑表单
  void _showEditForm(UserAIModelConfigModel config) {
    // 检查Bloc是否已有该Provider的模型，若无则加载
    if (mounted) {
      final bloc = context.read<AiConfigBloc>();
      final cachedGroup = bloc.state.modelGroups[config.provider];
      final hasCache = cachedGroup != null && cachedGroup.allModelsInfo.isNotEmpty;
      if (!hasCache) {
        bloc.add(LoadModelsForProvider(provider: config.provider));
      } else {
        AppLogger.d('SettingsPanel', '编辑模式使用缓存的模型列表，provider=${config.provider}');
      }
    }

    setState(() {
      _configToEdit = config; // 设置要编辑的配置
      _showAddEditForm = true; // 显示表单
      _selectedIndex = 0; // 确保在 '模型服务' 类别下
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 4.0,
      borderRadius: BorderRadius.circular(16.0),
      color: Colors.transparent, // Make Material transparent
      child: Container(
        // 自适应：根据可用空间限制最大宽高，且在小屏下铺满
        constraints: const BoxConstraints(
          maxWidth: 1400,
          maxHeight: 1000,
          minWidth: 320,
          minHeight: 400,
        ),
        width: MediaQuery.of(context).size.width.clamp(320, 1400),
        height: MediaQuery.of(context).size.height.clamp(400, 1000),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surface.withAlpha(217) // 0.85 opacity
              : theme.colorScheme.surface.withAlpha(242), // 0.95 opacity
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withAlpha(77) // 0.3 opacity
                  : Colors.black.withAlpha(26), // 0.1 opacity
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(26) // 0.1 opacity
                : Colors.white.withAlpha(153), // 0.6 opacity
            width: 0.5,
          ),
        ),
        // 添加背景模糊效果
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Left Navigation Rail
            Container(
              width: (MediaQuery.of(context).size.width <= 640)
                  ? 140
                  : (MediaQuery.of(context).size.width <= 1024 ? 180 : 220),
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withAlpha(51) // 0.2 opacity
                    : theme.colorScheme.surfaceContainerLowest.withAlpha(179), // 0.7 opacity
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  bottomLeft: Radius.circular(16.0),
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(13) // 0.05 opacity
                      : Colors.white.withAlpha(77), // 0.3 opacity
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withAlpha(51) // 0.2 opacity
                        : Colors.black.withAlpha(13), // 0.05 opacity
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ListView.builder(
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? theme.colorScheme.primary.withAlpha(38) // 0.15 opacity
                                : theme.colorScheme.primary.withAlpha(26)) // 0.1 opacity
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withAlpha(26), // 0.1 opacity
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ] : [],
                      ),
                      child: ListTile(
                        leading: Icon(
                          category['icon'] as IconData?,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20, // Smaller icon
                        ),
                        title: Text(
                          category['title'] as String,
                          style: TextStyle(
                            fontSize: 13, // Slightly smaller font
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedIndex = index;
                            _hideAddEditForm(); // Hide form when changing category
                          });
                        },
                        selected: isSelected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 4.0),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Right Content Area
            Expanded(
              child: ClipRRect(
                // Clip content to rounded corners
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16.0),
                  bottomRight: Radius.circular(16.0),
                ),
                child: Container(
                  // Add a background for the content area if needed
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.cardColor.withAlpha(179) // 0.7 opacity
                        : theme.cardColor.withAlpha(217), // 0.85 opacity
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withAlpha(51) // 0.2 opacity
                            : Colors.black.withAlpha(13), // 0.05 opacity
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Listener for Feedback Toasts
                      BlocListener<AiConfigBloc, AiConfigState>(
                        listenWhen: (previous, current) =>
                            previous.actionStatus != current.actionStatus,
                        listener: (context, state) {
                          if (!mounted) return;

                          if (state.actionStatus == AiConfigActionStatus.error ||
                              state.actionStatus == AiConfigActionStatus.success) {
                            widget.stateManager.setModelOperationInProgress(false);
                          }

                          // Show Toast for errors
                          if (state.actionStatus ==
                                  AiConfigActionStatus.error &&
                              state.actionErrorMessage != null) {
                            TopToast.error(context, '操作失败: ${state.actionErrorMessage!}');
                          }
                          // Show Toast for success
                          else if (state.actionStatus ==
                              AiConfigActionStatus.success) {
                            TopToast.success(context, '操作成功');
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            MediaQuery.of(context).size.width <= 480 ? 16.0 : 24.0,
                            MediaQuery.of(context).size.width <= 480 ? 24.0 : 40.0,
                            MediaQuery.of(context).size.width <= 480 ? 16.0 : 24.0,
                            MediaQuery.of(context).size.width <= 480 ? 16.0 : 24.0,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeOutQuint,
                            switchOutCurve: Curves.easeInQuint,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              // Using Key on the child ensures AnimatedSwitcher differentiates them
                              return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.05, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  )
                              );
                            },
                            // Directly determine the child and its key here
                            child: _showAddEditForm &&
                                    _selectedIndex ==
                                        0 // Only show form for '模型服务'
                                ? _buildAiConfigForm(
                                    key: ValueKey(_configToEdit?.id ??
                                        'add')) // Form View
                                : _buildCategoryListContent(
                                    key: ValueKey('list_$_selectedIndex'),
                                    index:
                                        _selectedIndex), // List View or other categories
                          ),
                        ),
                      ),
                      // Close Button - Positioned relative to the Stack
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withAlpha(51) // 0.2 opacity
                                : Colors.white.withAlpha(128), // 0.5 opacity
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(26), // 0.1 opacity
                                blurRadius: 4,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: '关闭设置',
                            onPressed: widget.onClose,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Renamed for clarity and added index parameter
  Widget _buildCategoryListContent({required Key key, required int index}) {
    final categoryTitle = _categories[index]['title'] as String;

    switch (categoryTitle) {
      case '模型服务':
        return ModelServiceListPage(
          key: key,
          userId: widget.userId,
          onAddNew: _showAddForm,
          onEditConfig: _showEditForm, // 传递编辑回调
          editorStateManager: widget.stateManager,
        );
      case '账户管理':
        return AccountManagementPanel(key: key);
      case '会员与订阅':
        return LayoutBuilder(
          key: const ValueKey('membership_panel'),
          builder: (context, constraints) {
            final double horizontalPadding = constraints.maxWidth <= 480 ? 8 : 16;
            final double cardPadding = constraints.maxWidth <= 480 ? 8 : 12;
            final double titleSize = constraints.maxWidth <= 480 ? 18 : 20;
            return SingleChildScrollView(
              padding: EdgeInsets.all(horizontalPadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('会员计划', style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          const membership.MembershipPanel(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      case '编辑器设置':
        return EditorSettingsPanel(
          key: key,
          settings: _editorSettings,
          onSettingsChanged: (newSettings) {
            setState(() {
              _editorSettings = newSettings;
            });
            widget.onEditorSettingsChanged?.call(newSettings);
          },
          onSave: () async {
            // 🚀 修复：实际调用后端API保存编辑器设置
            try {
              AppLogger.i('SettingsPanel', '开始保存用户编辑器设置: userId=${widget.userId}');
              
              final savedSettings = await _novelRepository.saveUserEditorSettings(
                widget.userId, 
                _editorSettings
              );
              
              AppLogger.i('SettingsPanel', '成功保存用户编辑器设置');
              
              // 更新本地状态
              setState(() {
                _editorSettings = savedSettings;
              });
              
              // 通知父组件
              widget.onEditorSettingsChanged?.call(savedSettings);
              
            } catch (e) {
              AppLogger.e('SettingsPanel', '保存用户编辑器设置失败: $e');
              
              // 显示错误提示
              if (mounted) {
                TopToast.error(context, '保存编辑器设置失败: $e');
              }
              
              // 重新抛出异常，让EditorSettingsPanel的错误处理机制处理
              rethrow;
            }
          },
          onReset: () async {
            // 🚀 修复：实际调用后端API重置编辑器设置
            try {
              AppLogger.i('SettingsPanel', '开始重置用户编辑器设置: userId=${widget.userId}');
              
              final defaultSettings = await _novelRepository.resetUserEditorSettings(widget.userId);
              
              AppLogger.i('SettingsPanel', '成功重置用户编辑器设置');
              
              setState(() {
                _editorSettings = defaultSettings;
              });
              
              widget.onEditorSettingsChanged?.call(defaultSettings);
              
            } catch (e) {
              AppLogger.e('SettingsPanel', '重置用户编辑器设置失败: $e');
              
              // 显示错误提示
              if (mounted) {
                TopToast.error(context, '重置编辑器设置失败: $e');
              }
            }
          },
        );
      case '主题设置':
        return _ThemeSettingsPage(
          key: key,
          currentVariant: _editorSettings.themeVariant,
          onChanged: (variant) {
            // 更新本地 EditorSettings 并立即应用
            setState(() {
              _editorSettings = _editorSettings.copyWith(themeVariant: variant);
            });
            WebTheme.applyVariant(variant);
            // 同步给外层
            widget.onEditorSettingsChanged?.call(_editorSettings);
          },
          onSave: () async {
            try {
              AppLogger.i('SettingsPanel', '保存主题设置: ${_editorSettings.themeVariant}');
              final saved = await _novelRepository.saveUserEditorSettings(
                widget.userId,
                _editorSettings,
              );
              setState(() {
                _editorSettings = saved;
              });
              // 关键：以服务端返回为准重新应用，避免非法/回退
              WebTheme.applyVariant(saved.themeVariant);
              widget.onEditorSettingsChanged?.call(saved);
              TopToast.success(context, '主题设置已保存');
            } catch (e) {
              TopToast.error(context, '保存主题设置失败: $e');
              rethrow;
            }
          },
          onReset: () async {
            try {
              AppLogger.i('SettingsPanel', '重置主题设置');
              final defaults = await _novelRepository.resetUserEditorSettings(widget.userId);
              setState(() {
                _editorSettings = defaults;
              });
              WebTheme.applyVariant(_editorSettings.themeVariant);
              widget.onEditorSettingsChanged?.call(defaults);
            } catch (e) {
              TopToast.error(context, '重置主题设置失败: $e');
            }
          },
        );
      default:
        return Center(
            key: key,
            child: Text('这里将显示 $categoryTitle 设置',
                style: Theme.of(context).textTheme.bodyLarge));
    }
  }

  // Builds the actual form widget, added key parameter
  Widget _buildAiConfigForm({required Key key}) {
    // REMOVE the BlocListener that was here, as it might prematurely hide the form.
    // Success/failure should be handled internally by AiConfigForm or via callbacks if needed.
    return AiConfigForm(
      // The actual form content
      key: key, // Pass the key provided by the parent
      userId: widget.userId,
      configToEdit: _configToEdit, // Pass the current configToEdit state
      onCancel: _hideAddEditForm, // Use the hide function for cancel
    );
  }


}

/// 主题设置页（简洁 UI）
class _ThemeSettingsPage extends StatelessWidget {
  const _ThemeSettingsPage({
    super.key,
    required this.currentVariant,
    required this.onChanged,
    required this.onSave,
    required this.onReset,
  });

  final String currentVariant;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSave;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = const [
      {'key': WebTheme.variantMonochrome, 'label': '黑白（默认）'},
      {'key': WebTheme.variantBlueWhite, 'label': '蓝白'},
      {'key': WebTheme.variantPinkWhite, 'label': '粉白'},
      {'key': WebTheme.variantPaper, 'label': '书页米色'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('主题设置', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(opt['label'] as String),
                selected: currentVariant == (opt['key'] as String),
                onSelected: (_) => onChanged(opt['key'] as String),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('重置为默认'),
            ),
          ],
        ),
      ],
    );
  }
}
