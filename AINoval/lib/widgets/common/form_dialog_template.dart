import 'package:ainoval/widgets/common/multi_select_instructions_with_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_state.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/widgets/common/prompt_quick_edit_dialog.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/screens/prompt_market/prompt_market_dialog.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'dialog_container.dart';
import 'dialog_header.dart';
import 'custom_tab_bar.dart';
import 'form_fieldset.dart';
import 'custom_text_editor.dart';
import 'context_badge.dart';
import 'radio_button_group.dart';
import 'bottom_action_bar.dart';
import 'context_selection_dropdown_menu_anchor.dart';
import 'instructions_with_presets.dart';
import 'multi_select_instructions_with_presets.dart' as multi_select;

/// 表单对话框模板组件
/// 提供完整的对话框表单布局，支持多个Bloc的依赖注入
class FormDialogTemplate extends StatefulWidget {
  /// 构造函数
  const FormDialogTemplate({
    super.key,
    required this.title,
    required this.tabs,
    required this.tabContents,
    this.primaryActionLabel = '保存',
    this.onPrimaryAction,
    this.showModelSelector = true,
    this.modelSelectorData,
    this.onModelSelectorTap,
    this.modelSelectorKey,
    this.showPresets = false,
    this.onPresetsPressed,
    this.usePresetDropdown = false,
    this.presetFeatureType,
    this.currentPreset,
    this.onPresetSelected,
    this.onCreatePreset,
    this.onManagePresets,
    this.novelId,
    this.aiConfigBloc,
    this.onClose,
    this.onTabChanged,
  });

  /// 对话框标题
  final String title;

  /// 选项卡列表
  final List<TabItem> tabs;

  /// 选项卡内容列表
  final List<Widget> tabContents;

  /// 主要操作按钮文字
  final String primaryActionLabel;

  /// 主要操作回调
  final VoidCallback? onPrimaryAction;

  /// 是否显示模型选择器
  final bool showModelSelector;

  /// 模型选择器数据
  final ModelSelectorData? modelSelectorData;

  /// 模型选择器点击回调
  final VoidCallback? onModelSelectorTap;

  /// 模型选择器的 GlobalKey
  final GlobalKey? modelSelectorKey;

  /// 是否显示预设按钮
  final bool showPresets;

  /// 预设按钮回调
  final VoidCallback? onPresetsPressed;

  /// 是否使用新的预设下拉框
  final bool usePresetDropdown;

  /// 预设功能类型（用于过滤预设）
  final String? presetFeatureType;

  /// 当前选中的预设
  final AIPromptPreset? currentPreset;

  /// 预设选择回调
  final ValueChanged<AIPromptPreset>? onPresetSelected;

  /// 创建预设回调
  final VoidCallback? onCreatePreset;

  /// 管理预设回调
  final VoidCallback? onManagePresets;

  /// 小说ID（用于过滤预设）
  final String? novelId;

  /// AI配置Bloc（可选）
  final AiConfigBloc? aiConfigBloc;

  /// 关闭回调
  final VoidCallback? onClose;

  /// Tab切换回调
  final ValueChanged<String>? onTabChanged;

  @override
  State<FormDialogTemplate> createState() => _FormDialogTemplateState();
}

class _FormDialogTemplateState extends State<FormDialogTemplate> {
  late String _selectedTabId;

  @override
  void initState() {
    super.initState();
    _selectedTabId = widget.tabs.isNotEmpty ? widget.tabs.first.id : '';
  }

  @override
  Widget build(BuildContext context) {
    // 构建 providers 列表，确保至少有一个空的 provider
    final providers = <BlocProvider>[
      // 如果传入了aiConfigBloc，则提供给子组件使用
      if (widget.aiConfigBloc != null)
        BlocProvider<AiConfigBloc>.value(value: widget.aiConfigBloc!),
    ];

    // 如果没有任何 providers，添加一个空的 provider 避免 MultiBlocProvider 报错
    if (providers.isEmpty) {
      return DialogContainer(
        child: _buildDialogContent(),
      );
    }

    return MultiBlocProvider(
      providers: providers,
      child: DialogContainer(
        child: _buildDialogContent(),
      ),
    );
  }

  /// 构建对话框内容
  Widget _buildDialogContent() {
    return Column(
      children: [
        // 标题栏
        DialogHeader(
          title: widget.title,
          onClose: widget.onClose,
        ),

        // 内容区域
        Expanded(
          child: Column(
            children: [
              // 选项卡栏
              if (widget.tabs.isNotEmpty)
                CustomTabBar(
                  tabs: widget.tabs,
                  selectedTabId: _selectedTabId,
                  onTabChanged: (tabId) {
                    setState(() {
                      _selectedTabId = tabId;
                    });
                    // 调用外部回调
                    widget.onTabChanged?.call(tabId);
                  },
                  showPresets: widget.showPresets,
                  onPresetsPressed: widget.onPresetsPressed,
                  usePresetDropdown: widget.usePresetDropdown,
                  presetFeatureType: widget.presetFeatureType,
                  currentPreset: widget.currentPreset,
                  onPresetSelected: widget.onPresetSelected,
                  onCreatePreset: widget.onCreatePreset,
                  onManagePresets: widget.onManagePresets,
                  novelId: widget.novelId,
                ),

              // 选项卡内容
              Expanded(
                child: _buildTabContent(),
              ),
            ],
          ),
        ),

        // 底部操作栏
        BottomActionBar(
          modelSelector: widget.showModelSelector ? _buildModelSelector() : null,
          primaryAction: _buildPrimaryAction(),
        ),
      ],
    );
  }

  /// 构建选项卡内容
  Widget _buildTabContent() {
    final tabIndex = widget.tabs.indexWhere((tab) => tab.id == _selectedTabId);
    if (tabIndex == -1 || tabIndex >= widget.tabContents.length) {
      return const Center(child: Text('内容未找到'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: widget.tabContents[tabIndex],
    );
  }

  /// 构建模型选择器
  Widget? _buildModelSelector() {
    if (!widget.showModelSelector || widget.modelSelectorData == null) {
      return null;
    }

    final data = widget.modelSelectorData!;
    return Container(
      key: widget.modelSelectorKey,
      child: ModelSelector(
        modelName: data.modelName,
        onTap: widget.onModelSelectorTap,
        providerIcon: data.providerIcon,
        maxOutput: data.maxOutput,
        isModerated: data.isModerated,
      ),
    );
  }

  /// 构建主要操作按钮
  Widget _buildPrimaryAction() {
    final isDark = WebTheme.isDarkMode(context);

    return ElevatedButton(
      onPressed: widget.onPrimaryAction,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
        foregroundColor: isDark ? WebTheme.darkGrey50 : WebTheme.grey50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        widget.primaryActionLabel,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 模型选择器数据
class ModelSelectorData {
  /// 构造函数
  const ModelSelectorData({
    required this.modelName,
    this.providerIcon,
    this.maxOutput,
    this.isModerated = false,
  });

  /// 模型名称
  final String modelName;

  /// 提供商图标
  final Widget? providerIcon;

  /// 最大输出
  final String? maxOutput;

  /// 是否受监管
  final bool isModerated;
}

/// 常用表单字段工厂类
/// 提供快速创建常用表单字段的方法
class FormFieldFactory {
  /// 私有构造函数
  FormFieldFactory._();

  /// 创建指令输入字段
  static Widget createInstructionsField({
    TextEditingController? controller,
    String title = '指令',
    String description = '为AI提供的任务指令和角色说明',
    String placeholder = '请输入指令内容...',
    bool showReset = true,
    VoidCallback? onReset,
    VoidCallback? onExpand,
    VoidCallback? onCopy,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: CustomTextEditor(
        controller: controller,
        placeholder: placeholder,
        onExpand: onExpand,
        onCopy: onCopy,
      ),
    );
  }

  /// 创建带预设选项的指令输入字段
  static Widget createInstructionsWithPresetsField({
    TextEditingController? controller,
    List<InstructionPreset> presets = const [],
    String title = '指令',
    String description = '为AI提供的任务指令和角色说明',
    String placeholder = 'e.g. You are a...',
    String dropdownPlaceholder = 'Select \'Instructions\'...',
    bool isRequired = false,
    bool showReset = true,
    VoidCallback? onReset,
    VoidCallback? onExpand,
    VoidCallback? onCopy,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      showRequired: isRequired,
      child: InstructionsWithPresets(
        controller: controller,
        presets: presets,
        placeholder: placeholder,
        dropdownPlaceholder: dropdownPlaceholder,
        onExpand: onExpand,
        onCopy: onCopy,
      ),
    );
  }

  /// 创建多选指令预设字段
  static Widget createMultiSelectInstructionsWithPresetsField({
    TextEditingController? controller,
    List<multi_select.InstructionPreset> presets = const [],
    String title = '指令',
    String description = '为AI提供的任务指令和角色说明',
    String placeholder = 'e.g. You are a...',
    String dropdownPlaceholder = 'Select Instructions...',
    bool isRequired = false,
    bool showReset = true,
    VoidCallback? onReset,
    VoidCallback? onExpand,
    VoidCallback? onCopy,
    ValueChanged<List<multi_select.InstructionPreset>>? onSelectionChanged,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      showRequired: isRequired,
      child: multi_select.MultiSelectInstructionsWithPresets(
        controller: controller,
        presets: presets,
        placeholder: placeholder,
        dropdownPlaceholder: dropdownPlaceholder,
        onExpand: onExpand,
        onCopy: onCopy,
        onSelectionChanged: onSelectionChanged,
      ),
    );
  }

  /// 创建上下文字段
  static Widget createContextField({
    required List<ContextData> contexts,
    required ValueChanged<ContextData> onRemoveContext,
    required VoidCallback onAddContext,
    String title = '附加上下文',
    String description = '为AI提供的额外信息和参考资料',
    bool showReset = true,
    VoidCallback? onReset,
    Map<ContextData, GlobalKey>? contextKeys,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: Builder(
        builder: (context) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 添加上下文按钮
            SizedBox(
              height: 36, // 与 ContextBadge 保持一致的高度
              child: ElevatedButton.icon(
                onPressed: onAddContext,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Context',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF374151) // gray-700
                      : Colors.white,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFD1D5DB) // gray-300
                      : const Color(0xFF4B5563), // gray-600
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF374151) // gray-700
                        : const Color(0xFFD1D5DB), // gray-300
                    width: 1,
                  ),
                  elevation: 1,
                  shadowColor: Colors.black.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ),
            
            // 上下文标签列表
            ...contexts.map((contextData) => ContextBadge(
              data: contextData,
              onDelete: () => onRemoveContext(contextData),
              globalKey: contextKeys?[contextData],
            )).toList(),
          ],
        ),
      ),
    );
  }

  /// 创建长度选择字段
  static Widget createLengthField<T>({
    required List<RadioOption<T>> options,
    T? value,
    required ValueChanged<T?> onChanged,
    String title = '长度',
    String description = '生成内容的长度设置',
    bool isRequired = false,
    bool showReset = true,
    VoidCallback? onReset,
    Widget? alternativeInput,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      showRequired: isRequired,
      child: alternativeInput != null
        ? RadioButtonGroupWithSeparator<T>(
            radioGroup: RadioButtonGroup<T>(
              options: options,
              value: value,
              onChanged: onChanged,
              showClear: true,
            ),
            alternativeWidget: alternativeInput,
          )
        : RadioButtonGroup<T>(
            options: options,
            value: value,
            onChanged: onChanged,
            showClear: true,
          ),
    );
  }

  /// 创建记忆截断字段
  static Widget createMemoryCutoffField({
    required List<RadioOption<int>> options,
    int? value,
    required ValueChanged<int?> onChanged,
    String title = '记忆截断',
    String description = '指定发送给AI的最大消息对数，超出此限制的消息将被忽略',
    bool showReset = true,
    VoidCallback? onReset,
    Widget? customInput,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: customInput != null
        ? RadioButtonGroupWithSeparator<int>(
            radioGroup: RadioButtonGroup<int>(
              options: options,
              value: value,
              onChanged: onChanged,
            ),
            alternativeWidget: customInput,
          )
        : RadioButtonGroup<int>(
            options: options,
            value: value,
            onChanged: onChanged,
          ),
    );
  }

  /// 创建新版上下文选择字段
  static Widget createContextSelectionField({
    required ContextSelectionData contextData,
    required ValueChanged<ContextSelectionData> onSelectionChanged,
    String title = '附加上下文',
    String description = '选择要包含在对话中的上下文信息',
    bool showReset = true,
    VoidCallback? onReset,
    double? dropdownWidth,
    double maxDropdownHeight = 400,
    String? initialChapterId,
    String? initialSceneId,
    Map<ContextSelectionType, Color>? typeColorMap,
    Color Function(ContextSelectionType type, BuildContext context)? typeColorResolver,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上下文选择下拉框
          ContextSelectionDropdownBuilder.buildMenuAnchor(
            data: contextData,
            onSelectionChanged: onSelectionChanged,
            placeholder: '点击添加上下文',
            width: dropdownWidth,
            maxHeight: maxDropdownHeight,
            initialChapterId: initialChapterId,
            initialSceneId: initialSceneId,
            typeColorMap: typeColorMap,
            typeColorResolver: typeColorResolver,
          ),
          
          // 显示已选择的上下文标签
          if (contextData.selectedCount > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: contextData.selectedItems.values.map((item) {
                return ContextBadge(
                  data: ContextData(
                    id: item.id,
                    title: item.title,
                    subtitle: item.displaySubtitle,
                    icon: item.type.icon,
                  ),
                  onDelete: () {
                    final newData = contextData.deselectItem(item.id);
                    onSelectionChanged(newData);
                  },
                  maxWidth: 200,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 🚀 新增：创建提示词模板选择字段
  static Widget createPromptTemplateSelectionField({
    String? selectedTemplateId,
    required ValueChanged<String?> onTemplateSelected,
    required String aiFeatureType,
    String title = '关联提示词模板',
    String description = '选择要关联的提示词模板',
    bool showReset = true,
    VoidCallback? onReset,
    void Function(String systemPrompt, String userPrompt)? onTemporaryPromptsSaved,
    Set<PromptTemplateType>? allowedTypes,
    bool onlyVerifiedPublic = false,
    bool showMarketButton = true, // 🚀 新增：是否显示提示词市场按钮
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: _PromptTemplateDropdown(
        selectedTemplateId: selectedTemplateId,
        onTemplateSelected: onTemplateSelected,
        aiFeatureType: aiFeatureType,
        allowedTypes: allowedTypes,
        onlyVerifiedPublic: onlyVerifiedPublic,
        showMarketButton: showMarketButton,
        onEdit: (contextForEdit, currentTemplateId) {
          if (currentTemplateId == null || currentTemplateId.isEmpty) {
            ScaffoldMessenger.of(contextForEdit).showSnackBar(
              const SnackBar(content: Text('请先选择提示词模板')),
            );
            return;
          }
          showDialog(
            context: contextForEdit,
            barrierDismissible: true,
            builder: (dialogContext) {
              return PromptQuickEditDialog(
                templateId: currentTemplateId,
                aiFeatureType: aiFeatureType,
                onTemporaryPromptsSaved: (sys, user) {
                  if (onTemporaryPromptsSaved != null) {
                    onTemporaryPromptsSaved(sys, user);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 🚀 新增：创建快捷访问勾选字段
  static Widget createQuickAccessToggleField({
    required bool value,
    required ValueChanged<bool> onChanged,
    String title = '快捷访问',
    String description = '是否在快捷访问列表中显示此预设',
    bool showReset = true,
    VoidCallback? onReset,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: CheckboxListTile(
        value: value,
        onChanged: (bool? newValue) {
          if (newValue != null) {
            onChanged(newValue);
          }
        },
        title: const Text('显示在快捷访问列表'),
        subtitle: const Text('勾选后此预设将显示在功能对话框的快捷列表中'),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }

  /// 🚀 新增：创建温度滑动组件
  static Widget createTemperatureSliderField({
    required BuildContext context,
    required double value,
    required ValueChanged<double> onChanged,
    String title = '温度 (Temperature)',
    String description = '控制生成文本的随机性和创造性',
    bool showReset = true,
    VoidCallback? onReset,
    double min = 0.0,
    double max = 2.0,
    int divisions = 40,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: value.toStringAsFixed(2),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 60,
                child: Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '温度越高，文本越随机和创造性；温度越低，文本越确定和重复。推荐范围：0.7-1.0',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 🚀 新增：创建Top-P滑动组件
  static Widget createTopPSliderField({
    required BuildContext context,
    required double value,
    required ValueChanged<double> onChanged,
    String title = 'Top-P (Nucleus Sampling)',
    String description = '控制词汇选择的多样性',
    bool showReset = true,
    VoidCallback? onReset,
    double min = 0.0,
    double max = 1.0,
    int divisions = 100,
  }) {
    return FormFieldset(
      title: title,
      description: description,
      showReset: showReset,
      onReset: onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: value.toStringAsFixed(2),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 60,
                child: Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '从概率累计达到该值的词组中选择。较低值使文本更可预测，较高值增加多样性。推荐范围：0.8-0.95',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 🚀 新增：为预设模板创建硬编码上下文数据
  static ContextSelectionData createPresetTemplateContextData({
    String novelId = 'preset_template',
  }) {
    final hardcodedItems = [
      // 核心上下文项
      ContextSelectionItem(
        id: 'preset_full_novel_text',
        title: '全文内容',
        type: ContextSelectionType.fullNovelText,
        subtitle: '包含完整的小说文本内容',
        metadata: {'isHardcoded': true},
        order: 0,
      ),
      ContextSelectionItem(
        id: 'preset_full_outline',
        title: '完整大纲',
        type: ContextSelectionType.fullOutline,
        subtitle: '包含完整的小说大纲结构',
        metadata: {'isHardcoded': true},
        order: 1,
      ),
      ContextSelectionItem(
        id: 'preset_novel_basic_info',
        title: '小说基本信息',
        type: ContextSelectionType.novelBasicInfo,
        subtitle: '小说的基本信息（标题、作者、简介等）',
        metadata: {'isHardcoded': true},
        order: 2,
      ),
      ContextSelectionItem(
        id: 'preset_recent_chapters_content',
        title: '最近章节内容',
        type: ContextSelectionType.recentChaptersContent,
        subtitle: '最近5章的内容',
        metadata: {'isHardcoded': true},
        order: 3,
      ),
      ContextSelectionItem(
        id: 'preset_recent_chapters_summary',
        title: '最近章节摘要',
        type: ContextSelectionType.recentChaptersSummary,
        subtitle: '最近5章的摘要',
        metadata: {'isHardcoded': true},
        order: 4,
      ),
      
      // 结构化上下文
      ContextSelectionItem(
        id: 'preset_settings',
        title: '全部设定',
        type: ContextSelectionType.settings,
        subtitle: '角色和世界观设定',
        metadata: {'isHardcoded': true},
        order: 5,
      ),
      ContextSelectionItem(
        id: 'preset_snippets',
        title: '参考片段',
        type: ContextSelectionType.snippets,
        subtitle: '参考片段和素材',
        metadata: {'isHardcoded': true},
        order: 6,
      ),
      
      // 当前场景上下文
      ContextSelectionItem(
        id: 'preset_current_chapter',
        title: '当前章节',
        type: ContextSelectionType.chapters,
        subtitle: '当前章节内容',
        metadata: {'isHardcoded': true},
        order: 7,
      ),
      ContextSelectionItem(
        id: 'preset_current_scene',
        title: '当前场景',
        type: ContextSelectionType.scenes,
        subtitle: '当前场景内容',
        metadata: {'isHardcoded': true},
        order: 8,
      ),
    ];

    // 构建扁平化映射
    final flatItems = <String, ContextSelectionItem>{};
    for (final item in hardcodedItems) {
      flatItems[item.id] = item;
    }

    return ContextSelectionData(
      novelId: novelId,
      availableItems: hardcodedItems,
      flatItems: flatItems,
    );
  }

}

/// 🚀 新增：提示词模板下拉组件
class _PromptTemplateDropdown extends StatelessWidget {
  const _PromptTemplateDropdown({
    required this.selectedTemplateId,
    required this.onTemplateSelected,
    required this.aiFeatureType,
    this.onEdit,
    this.allowedTypes,
    this.onlyVerifiedPublic = false,
    this.showMarketButton = true,
  });

  final String? selectedTemplateId;
  final ValueChanged<String?> onTemplateSelected;
  final String aiFeatureType;
  final void Function(BuildContext context, String? currentTemplateId)? onEdit;
  final Set<PromptTemplateType>? allowedTypes;
  final bool onlyVerifiedPublic;
  final bool showMarketButton;

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 [_PromptTemplateDropdown] 构建下拉框，功能类型: $aiFeatureType');
    
    return BlocBuilder<PromptNewBloc, PromptNewState>(
      builder: (context, state) {
        debugPrint('🔍 [_PromptTemplateDropdown] BlocBuilder状态更新:');
        debugPrint('  - 状态类型: ${state.runtimeType}');
        debugPrint('  - 是否正在加载: ${state.isLoading}');
        debugPrint('  - 提示词包数量: ${state.promptPackages.length}');
        debugPrint('  - 状态状态: ${state.status}');

        // 如果还没有加载数据，先触发加载
        if (state.promptPackages.isEmpty && !state.isLoading && state.status == PromptNewStatus.initial) {
          debugPrint('📢 [_PromptTemplateDropdown] 触发提示词包加载请求');
          // 在下一帧触发加载，避免在build过程中修改状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<PromptNewBloc>().add(const LoadAllPromptPackages());
          });
        }

        // 显示加载指示器
        if (state.isLoading) {
          debugPrint('⏳ [_PromptTemplateDropdown] 显示加载指示器');
          return Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        // 显示错误状态
        if (state.status == PromptNewStatus.failure) {
          debugPrint('❌ [_PromptTemplateDropdown] 显示错误状态: ${state.errorMessage}');
          return Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.error),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '加载失败',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        // 提取模板数据
        final templates = _filterTemplates(
          _extractTemplatesFromState(state),
          allowedTypes,
          onlyVerifiedPublic,
        );
        debugPrint('📋 [_PromptTemplateDropdown] 可用模板选项: ${templates.length}个');
        for (final template in templates) {
          debugPrint('  - ${template.id}: ${template.name} (${template.type})');
        }

        // 验证选中的值是否在可用选项中
        final validSelectedValue = templates.any((t) => t.id == selectedTemplateId) 
            ? selectedTemplateId 
            : null;
        
        if (selectedTemplateId != null && validSelectedValue == null) {
          debugPrint('⚠️ [_PromptTemplateDropdown] 选中的模板ID不在可用选项中: $selectedTemplateId');
        } else if (validSelectedValue != null) {
          debugPrint('✅ [_PromptTemplateDropdown] 有效的选中值: $validSelectedValue');
        } else {
          debugPrint('ℹ️ [_PromptTemplateDropdown] 无选中值');
        }

        // 自定义美观下拉：带类型/次数标签
        return _PromptTemplatePrettyDropdown(
          options: templates,
          selectedId: validSelectedValue,
          onChanged: onTemplateSelected,
          aiFeatureType: aiFeatureType,
          showMarketButton: showMarketButton,
          onEdit: validSelectedValue == null
              ? null
              : () => onEdit?.call(context, validSelectedValue),
        );
      },
    );
  }

  /// 从状态中提取模板数据
  List<PromptTemplateOption> _extractTemplatesFromState(PromptNewState state) {
    // 获取当前功能类型的枚举值
    final AIFeatureType? featureType = _parseFeatureType(aiFeatureType);
    debugPrint('🎯 [_PromptTemplateDropdown] 解析功能类型: $aiFeatureType -> $featureType');
    
    if (featureType == null) {
      debugPrint('⚠️ [_PromptTemplateDropdown] 无法解析功能类型，返回空列表');
      return [];
    }

    // 获取指定功能类型的提示词包
    final package = state.promptPackages[featureType];
    if (package == null) {
      debugPrint('⚠️ [_PromptTemplateDropdown] 找不到功能类型对应的提示词包: $featureType');
      debugPrint('  - 可用的功能类型: ${state.promptPackages.keys.toList()}');
      return [];
    }

    final templates = <PromptTemplateOption>[];

    debugPrint('🔍 [_PromptTemplateDropdown] 处理功能类型: $featureType');
    debugPrint('  - 系统默认提示词: ${package.systemPrompt.defaultSystemPrompt.isNotEmpty ? '存在' : '不存在'}');
    debugPrint('  - 用户提示词数量: ${package.userPrompts.length}');
    debugPrint('  - 公开提示词数量: ${package.publicPrompts.length}');

    // 1. 🚀 添加系统默认模板（如果存在）
    if (package.systemPrompt.defaultSystemPrompt.isNotEmpty) {
      templates.add(PromptTemplateOption(
        id: 'system_default_${featureType.toString()}',
        name: '系统默认模板',
        type: PromptTemplateType.system,
        isPublic: false,
        hidePrompts: false,
      ));
      debugPrint('  + 系统默认模板: system_default_${featureType.toString()} - 系统默认模板');
    }

    // 2. 添加用户自定义提示词模板
    for (final userPrompt in package.userPrompts) {
      templates.add(PromptTemplateOption(
        id: userPrompt.id,
        name: userPrompt.name,
        type: PromptTemplateType.private,
        usageCount: userPrompt.usageCount,
        isPublic: false,
        hidePrompts: false,
      ));
      debugPrint('  + 用户模板: ${userPrompt.id} - ${userPrompt.name}');
    }

    // 3. 添加公开提示词模板（视为系统模板）
    for (final publicPrompt in package.publicPrompts) {
      templates.add(PromptTemplateOption(
        id: 'public_${publicPrompt.id}', // 添加前缀避免ID冲突
        name: publicPrompt.name,
        type: PromptTemplateType.public,
        isVerified: publicPrompt.isVerified,
        isPublic: true, // 🆕 标记为公开模板
        hidePrompts: publicPrompt.hidePrompts, // 🆕 使用公开模板的hidePrompts字段
      ));
      debugPrint('  + 公开模板: public_${publicPrompt.id} - ${publicPrompt.name}');
    }

    debugPrint('✅ [_PromptTemplateDropdown] 提取完成，总模板数: ${templates.length}');
    return templates;
  }

  /// 过滤模板选项，根据允许的类型与是否仅允许已验证公共模板
  List<PromptTemplateOption> _filterTemplates(
    List<PromptTemplateOption> options,
    Set<PromptTemplateType>? allowed,
    bool onlyVerifiedPublic,
  ) {
    if (allowed == null || allowed.isEmpty) return options;
    return options.where((o) {
      if (!allowed.contains(o.type)) return false;
      if (onlyVerifiedPublic && o.type == PromptTemplateType.public && !o.isVerified) return false;
      return true;
    }).toList();
  }

  /// 解析功能类型字符串
  AIFeatureType? _parseFeatureType(String featureTypeString) {
    try {
      return AIFeatureTypeHelper.fromApiString(featureTypeString.toUpperCase());
    } catch (e) {
      debugPrint('无法解析功能类型: $featureTypeString');
      return null;
    }
  }
}

/// 🚀 新增：模板类型
enum PromptTemplateType { system, public, private }

/// 🚀 新增：提示词模板选项数据模型
class PromptTemplateOption {
  final String id;
  final String name;
  final PromptTemplateType type;
  final int? usageCount; // 仅 private 关心
  final bool isVerified; // 仅 public 关心
  final bool hidePrompts; // 🆕 是否隐藏提示词（用于公开模板）
  final bool isPublic; // 🆕 是否为公开模板

  const PromptTemplateOption({
    required this.id,
    required this.name,
    required this.type,
    this.usageCount,
    this.isVerified = false,
    this.hidePrompts = false,
    this.isPublic = false,
  });
}

/// 🚀 新增：更美观的下拉组件（带标签/次数）
class _PromptTemplatePrettyDropdown extends StatelessWidget {
  const _PromptTemplatePrettyDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
    required this.aiFeatureType,
    this.onEdit,
    this.showMarketButton = true,
  });

  final List<PromptTemplateOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String aiFeatureType;
  final VoidCallback? onEdit;
  final bool showMarketButton;

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    final selected = options.firstWhere(
      (o) => o.id == selectedId,
      orElse: () => const PromptTemplateOption(id: '', name: '', type: PromptTemplateType.private),
    );

    final hasSelection = selectedId != null && selected.id.isNotEmpty;

    return Builder(
      builder: (buttonContext) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _showMenu(buttonContext),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _iconForType(hasSelection ? selected.type : null),
                  size: 16,
                  color: hasSelection
                      ? _iconColorForType(context, selected.type)
                      : (isDark ? WebTheme.darkGrey400 : WebTheme.grey400),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasSelection ? selected.name : '选择提示词模板',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: hasSelection ? FontWeight.w500 : FontWeight.normal,
                      color: hasSelection
                          ? (isDark ? WebTheme.darkGrey900 : WebTheme.grey900)
                          : (isDark ? WebTheme.darkGrey500 : WebTheme.grey500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasSelection)
                  _buildTrailingTag(context, selected),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey400,
                ),
                const SizedBox(width: 4),
                // 右侧编辑按钮（当已选择模板时显示）
                if (hasSelection)
                  Builder(
                    builder: (context) {
                      // 判断是否应该置灰编辑按钮：公开模板且作者隐藏了提示词
                      final shouldDisable = selected.isPublic && selected.hidePrompts;
                      final tooltipMessage = shouldDisable ? '作者隐藏提示词' : '编辑提示词';
                      
                      return Tooltip(
                        message: tooltipMessage,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: shouldDisable ? null : onEdit,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: shouldDisable
                                  ? (isDark ? WebTheme.darkGrey400.withOpacity(0.5) : WebTheme.grey400.withOpacity(0.5))
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // 🚀 提示词市场按钮（在编辑按钮之后）
                if (showMarketButton) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '提示词市场',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _openPromptMarket(context),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.store_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String?> (
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        offset.dy + size.height + 4,
      ),
      items: [
        PopupMenuItem<String?> (
          value: null,
          child: Row(
            children: [
              Icon(Icons.block, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              const Text('不关联模板'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        ...options.map((o) => PopupMenuItem<String?> (
              value: o.id,
              child: Row(
                children: [
                  Icon(_iconForType(o.type), size: 16, color: _iconColorForType(context, o.type)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (o.isVerified && o.type == PromptTemplateType.public) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.verified, size: 16, color: Theme.of(context).colorScheme.primary),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTrailingTag(context, o),
                ],
              ),
            )),
      ],
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shadowColor: WebTheme.getShadowColor(context, opacity: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
    ).then((String? value) {
      onChanged(value);
    });
  }

  /// 🚀 打开提示词市场对话框
  Future<void> _openPromptMarket(BuildContext context) async {
    // 解析当前的 AI 功能类型
    AIFeatureType? featureType;
    try {
      featureType = AIFeatureTypeHelper.fromApiString(aiFeatureType.toUpperCase());
    } catch (e) {
      debugPrint('⚠️ 无法解析AI功能类型: $aiFeatureType');
      if (context.mounted) {
        TopToast.error(context, '无法打开提示词市场：功能类型无效');
      }
      return;
    }

    // 打开提示词市场对话框
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => PromptMarketDialog(
        initialFeatureType: featureType,
      ),
    );

    // 处理导航请求：通过事件总线保持左侧布局跳转到「提示词与预设」
    if (result != null && result['navigate_to'] == 'unified_management') {
      if (context.mounted) {
        try { EventBus.instance.fire(const NavigateToUnifiedManagement()); } catch (_) {}
      }
      return;
    }

    // 处理返回结果
    if (result != null && result['id'] != null && context.mounted) {
      // 选中提示词模板
      final templateId = result['id'] as String;
      // 🔧 提示词市场的模板都是公开模板，需要添加 public_ 前缀以匹配下拉框选项
      final prefixedId = 'public_$templateId';
      debugPrint('📌 [_openPromptMarket] 从市场选择模板: 原始ID=$templateId, 带前缀ID=$prefixedId');
      onChanged(prefixedId);
      
      // 显示成功提示（因为在 prompt_market_dialog 中已经显示过了，这里就不再显示了）
      // TopToast.success(context, '已选择提示词: ${result['name']}');
    }
  }

  static IconData _iconForType(PromptTemplateType? type) {
    switch (type) {
      case PromptTemplateType.system:
        return Icons.settings;
      case PromptTemplateType.public:
        return Icons.public;
      case PromptTemplateType.private:
        return Icons.person;
      default:
        return Icons.description;
    }
  }

  static Color _iconColorForType(BuildContext context, PromptTemplateType type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case PromptTemplateType.system:
        return colorScheme.primary;
      case PromptTemplateType.public:
        return colorScheme.secondary;
      case PromptTemplateType.private:
        return colorScheme.tertiary;
    }
  }

  Widget _buildTrailingTag(BuildContext context, PromptTemplateOption option) {
    switch (option.type) {
      case PromptTemplateType.system:
        return _buildTag(context, label: '系统', color: Theme.of(context).colorScheme.primary);
      case PromptTemplateType.public:
        return _buildTag(context, label: '公共', color: Theme.of(context).colorScheme.secondary);
      case PromptTemplateType.private:
        final count = option.usageCount ?? 0;
        return _buildTag(
          context,
          label: count > 0 ? '${count}次' : '私有',
          color: count > 0 ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.onSurfaceVariant,
        );
    }
  }

  Widget _buildTag(BuildContext context, {required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}