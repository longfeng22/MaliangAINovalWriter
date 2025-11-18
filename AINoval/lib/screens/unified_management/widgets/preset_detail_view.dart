import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/preset/preset_bloc.dart';
import 'package:ainoval/blocs/preset/preset_state.dart';
import 'package:ainoval/blocs/preset/preset_event.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/ai_feature_form_config.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/index.dart';
import 'package:ainoval/widgets/common/form_dialog_template.dart';
import 'package:ainoval/widgets/common/dynamic_form_field_widget.dart';
import 'package:ainoval/widgets/common/share_template_dialog.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/services/api_service/repositories/prompt_market_repository.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
// 移除未使用的 multi_select 引用

/// 预设详情视图
/// 提供预设的查看和编辑功能，包含设置和预览两个标签页
class PresetDetailView extends StatefulWidget {
  const PresetDetailView({super.key});

  @override
  State<PresetDetailView> createState() => _PresetDetailViewState();
}

class _PresetDetailViewState extends State<PresetDetailView>
    with SingleTickerProviderStateMixin {
  static const String _tag = 'PresetDetailView';
  
  late TabController _tabController;
  
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _presetNameController = TextEditingController();
  final TextEditingController _presetDescriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  
  String? _selectedPromptTemplate;
  bool _showInQuickAccess = false;
  bool _enableSmartContext = true;
  late ContextSelectionData _contextSelectionData;
  double _temperature = 0.7; // 🚀 新增：温度参数
  double _topP = 0.9; // 🚀 新增：Top-P参数
  
  AIPromptPreset? _editingPreset;
  bool _hasUnsavedChanges = false;
  
  // 🚀 新增：动态表单字段值映射表
  final Map<AIFormFieldType, dynamic> _formValues = {};
  
  // 🚀 新增：动态表单字段控制器映射表
  final Map<AIFormFieldType, TextEditingController> _formControllers = {};
  
  // 🚀 新增：当前AI功能类型
  AIFeatureType? _currentFeatureType;

  @override
  void initState() {
    super.initState();
    // 去掉“预览”页签，仅保留“设置”
    _tabController = TabController(length: 1, vsync: this);
    _contextSelectionData = FormFieldFactory.createPresetTemplateContextData();
    // 🚀 初始化新的参数默认值
    _temperature = 0.7;
    _topP = 0.9;
    
    // 🚀 初始化动态表单控制器
    _initializeFormControllers();
  }
  
  /// 🚀 初始化动态表单控制器
  void _initializeFormControllers() {
    // 为需要文本控制器的字段类型创建控制器
    final textFieldTypes = [
      AIFormFieldType.instructions,
      AIFormFieldType.length,
      AIFormFieldType.style,
      AIFormFieldType.memoryCutoff,
    ];
    
    for (final type in textFieldTypes) {
      _formControllers[type] = TextEditingController();
    }
  }



  @override
  void dispose() {
    _tabController.dispose();
    _instructionsController.dispose();
    _presetNameController.dispose();
    _presetDescriptionController.dispose();
    _tagsController.dispose();
    
    // 🚀 清理动态表单控制器
    for (final controller in _formControllers.values) {
      controller.dispose();
    }
    _formControllers.clear();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PresetBloc, PresetState>(
      builder: (context, state) {
        // 🚀 修复：在状态变化时同步内部数据
        if (!state.hasSelectedPreset) {
          // 如果没有选中预设，清空表单
          if (_editingPreset != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _clearForm();
            });
          }
          return _buildEmptyState();
        }

        // 🚀 修复：检查是否需要加载新的预设数据
        if (state.selectedPreset != _editingPreset) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadPresetData(state.selectedPreset);
          });
        }

        return _buildDetailView(state.selectedPreset!);
      },
    );
  }

  void _loadPresetData(AIPromptPreset? preset) {
    AppLogger.i(_tag, '🔄 开始加载预设数据: ${preset?.presetName ?? '空预设'}');
    
    if (preset == null) {
      _clearForm();
      return;
    }
    
    _editingPreset = preset;
    
    _presetNameController.text = preset.presetName ?? '';
    _presetDescriptionController.text = preset.presetDescription ?? '';
    _showInQuickAccess = preset.showInQuickAccess;
    _tagsController.text = preset.tags.join(', ');
    
    // 🚀 解析AI功能类型
    try {
      _currentFeatureType = AIFeatureTypeHelper.fromApiString(preset.aiFeatureType.toUpperCase());
      AppLogger.i(_tag, '解析AI功能类型: $_currentFeatureType');
    } catch (e) {
      AppLogger.w(_tag, '无法解析AI功能类型: ${preset.aiFeatureType}', e);
      _currentFeatureType = null;
    }
    
    // 🚀 修复：恢复关联的提示词模板
    _selectedPromptTemplate = preset.templateId;
    AppLogger.i(_tag, '恢复关联提示词模板: ${preset.templateId ?? "无关联模板"}');
    
    // 🚀 确保提示词数据已加载（用于模板选择下拉框）
    try {
      final promptNewBloc = context.read<PromptNewBloc>();
      if (promptNewBloc.state.promptPackages.isEmpty) {
        AppLogger.i(_tag, '📢 触发提示词数据加载以支持模板选择');
        promptNewBloc.add(const LoadAllPromptPackages());
      }
    } catch (e) {
      AppLogger.w(_tag, '无法访问PromptNewBloc，可能未注入到上下文中: $e');
    }
    
    final parsedRequest = preset.parsedRequest;
    if (parsedRequest != null) {
      AppLogger.i(_tag, '从预设解析出完整配置: ${preset.presetName}');
      
      if (parsedRequest.instructions != null && parsedRequest.instructions!.isNotEmpty) {
        _instructionsController.text = parsedRequest.instructions!;
      } else {
        _instructionsController.text = preset.effectiveUserPrompt;
      }
      
      if (parsedRequest.contextSelections != null && parsedRequest.contextSelections!.selectedCount > 0) {
        // 🚀 修复：在预设管理模式下，使用硬编码的上下文数据
        final originalContextData = parsedRequest.contextSelections!;
        final filteredContextData = _filterPresetTemplateContextData(originalContextData);
        
        _contextSelectionData = filteredContextData;
        AppLogger.i(_tag, '应用上下文选择: 原始${originalContextData.selectedCount}个项目，过滤后${filteredContextData.selectedCount}个项目');
      } else {
        // 🚀 如果没有上下文数据，使用硬编码的预设模板上下文
        _contextSelectionData = FormFieldFactory.createPresetTemplateContextData();
        AppLogger.i(_tag, '使用硬编码的预设模板上下文数据');
      }
      
      if (parsedRequest.parameters.isNotEmpty) {
        // 🚀 修复：直接设置状态，避免setState
        _enableSmartContext = parsedRequest.enableSmartContext;
        
        // 🚀 应用温度参数
        final temperature = parsedRequest.parameters['temperature'];
        if (temperature is double) {
          _temperature = temperature;
          AppLogger.i(_tag, '应用预设温度参数: $temperature');
        } else if (temperature is num) {
          _temperature = temperature.toDouble();
          AppLogger.i(_tag, '应用预设温度参数: ${temperature.toDouble()}');
        }
        
        // 🚀 应用Top-P参数
        final topP = parsedRequest.parameters['topP'];
        if (topP is double) {
          _topP = topP;
          AppLogger.i(_tag, '应用预设Top-P参数: $topP');
        } else if (topP is num) {
          _topP = topP.toDouble();
          AppLogger.i(_tag, '应用预设Top-P参数: ${topP.toDouble()}');
        }
        
        AppLogger.i(_tag, '应用参数设置: smartContext=$_enableSmartContext, temperature=$_temperature, topP=$_topP');
      }
      
      // 🚀 同步值到动态表单系统
      _syncToFormValues(parsedRequest);
    } else {
      _instructionsController.text = preset.effectiveUserPrompt;
      // 🚀 如果无法解析预设，使用硬编码的预设模板上下文
      _contextSelectionData = FormFieldFactory.createPresetTemplateContextData();
      AppLogger.i(_tag, '预设解析失败，使用硬编码的预设模板上下文数据');
    }
    
    _hasUnsavedChanges = false;
    
    // 🚀 修复：在方法最后统一触发UI更新
    if (mounted) {
      setState(() {
        // 状态已经在上面设置好了，这里只是触发重建
      });
    }
  }
  
  /// 🚀 同步解析后的请求数据到动态表单值
  void _syncToFormValues(UniversalAIRequest? request) {
    if (request == null) return;
    
    AppLogger.i(_tag, '🔄 同步解析请求数据到动态表单值');
    
    // 同步指令
    _formValues[AIFormFieldType.instructions] = request.instructions;
    _formControllers[AIFormFieldType.instructions]?.text = request.instructions ?? '';
    
    // 同步智能上下文
    _formValues[AIFormFieldType.smartContext] = request.enableSmartContext;
    
    // 同步温度
    _formValues[AIFormFieldType.temperature] = _temperature;
    
    // 同步Top-P
    _formValues[AIFormFieldType.topP] = _topP;
    
    // 同步快捷访问
    _formValues[AIFormFieldType.quickAccess] = _showInQuickAccess;
    
    // 同步提示词模板
    _formValues[AIFormFieldType.promptTemplate] = _selectedPromptTemplate;
    
    // 同步上下文选择
    _formValues[AIFormFieldType.contextSelection] = _contextSelectionData;
    
    // 根据不同功能类型同步特定字段
    if (request.parameters.isNotEmpty) {
      // 长度字段（用于扩写和缩写）
      final length = request.parameters['length'] as String?;
      if (length != null) {
        _formValues[AIFormFieldType.length] = length;
        _formControllers[AIFormFieldType.length]?.text = length;
      }
      
      // 样式字段（用于重构）
      final style = request.parameters['style'] as String?;
      if (style != null) {
        _formValues[AIFormFieldType.style] = style;
        _formControllers[AIFormFieldType.style]?.text = style;
      }
      
      // 记忆截断字段（用于聊天）
      final memoryCutoff = request.parameters['memoryCutoff'];
      if (memoryCutoff is int) {
        _formValues[AIFormFieldType.memoryCutoff] = memoryCutoff;
        _formControllers[AIFormFieldType.memoryCutoff]?.text = memoryCutoff.toString();
      }
    }
    
    AppLogger.i(_tag, '✅ 动态表单值同步完成');
  }

  /// 🚀 新增：过滤预设模板上下文数据，只保留硬编码的上下文类型
  ContextSelectionData _filterPresetTemplateContextData(ContextSelectionData originalData) {
    // 定义硬编码的上下文类型
    final hardcodedTypes = {
      ContextSelectionType.fullNovelText,
      ContextSelectionType.fullOutline,
      ContextSelectionType.novelBasicInfo,
      ContextSelectionType.recentChaptersContent,
      ContextSelectionType.recentChaptersSummary,
      ContextSelectionType.settings,
      ContextSelectionType.snippets,
      ContextSelectionType.chapters,
      ContextSelectionType.scenes,
      ContextSelectionType.settingGroups,
      ContextSelectionType.codexEntries,
    };

    // 过滤已选择的项目，只保留硬编码类型
    final filteredSelectedItems = <String, ContextSelectionItem>{};
    
    for (final item in originalData.selectedItems.values) {
      if (hardcodedTypes.contains(item.type) || item.metadata['isHardcoded'] == true) {
        // 创建硬编码版本的项目，移除具体的小说关联信息
        final hardcodedItem = _createHardcodedContextItem(item);
        filteredSelectedItems[hardcodedItem.id] = hardcodedItem;
      }
    }

    AppLogger.i(_tag, '上下文过滤: 原始${originalData.selectedCount}个 → 硬编码${filteredSelectedItems.length}个');

    // 如果过滤后没有项目，使用预设模板的硬编码上下文
    if (filteredSelectedItems.isEmpty) {
      AppLogger.i(_tag, '过滤后无有效上下文，使用预设模板硬编码上下文');
      return FormFieldFactory.createPresetTemplateContextData();
    }

    // 获取硬编码的可用项目列表
    final hardcodedAvailableItems = FormFieldFactory.createPresetTemplateContextData().availableItems;
    final hardcodedFlatItems = FormFieldFactory.createPresetTemplateContextData().flatItems;

    return ContextSelectionData(
      novelId: 'preset_template', // 使用预设模板标识
      selectedItems: filteredSelectedItems,
      availableItems: hardcodedAvailableItems,
      flatItems: hardcodedFlatItems,
    );
  }

  /// 🚀 新增：创建硬编码版本的上下文项目
  ContextSelectionItem _createHardcodedContextItem(ContextSelectionItem originalItem) {
    // 根据类型生成硬编码的ID和标题
    final hardcodedId = 'preset_${originalItem.type.displayName}';
    final hardcodedTitle = originalItem.type.displayName;
    
    // 移除具体的小说关联信息，只保留类型相关的元数据
    final hardcodedMetadata = <String, dynamic>{
      'isHardcoded': true,
      'contextType': originalItem.type.displayName,
    };

    return ContextSelectionItem(
      id: hardcodedId,
      title: hardcodedTitle,
      type: originalItem.type,
      subtitle: _getHardcodedSubtitle(originalItem.type),
      metadata: hardcodedMetadata,
      selectionState: SelectionState.fullySelected,
    );
  }

  /// 🚀 新增：获取硬编码上下文类型的子标题
  String _getHardcodedSubtitle(ContextSelectionType type) {
    switch (type) {
      case ContextSelectionType.fullNovelText:
        return '包含完整的小说文本内容';
      case ContextSelectionType.fullOutline:
        return '包含完整的小说大纲结构';
      case ContextSelectionType.novelBasicInfo:
        return '小说的基本信息（标题、作者、简介等）';
      case ContextSelectionType.recentChaptersContent:
        return '最近5章的内容';
      case ContextSelectionType.recentChaptersSummary:
        return '最近5章的摘要';
      case ContextSelectionType.settings:
        return '角色和世界观设定';
      case ContextSelectionType.snippets:
        return '参考片段和素材';
      case ContextSelectionType.chapters:
        return '当前章节内容';
      case ContextSelectionType.scenes:
        return '当前场景内容';
      case ContextSelectionType.settingGroups:
        return '设定组信息';
      case ContextSelectionType.codexEntries:
        return '词条和百科信息';
      default:
        return '硬编码上下文项目';
    }
  }

  void _clearForm() {
    AppLogger.i(_tag, '🧹 清空表单数据');
    _editingPreset = null;
    _presetNameController.clear();
    _presetDescriptionController.clear();
    _instructionsController.clear();
    _selectedPromptTemplate = null;
    _showInQuickAccess = false;
    _enableSmartContext = true;
    _contextSelectionData = FormFieldFactory.createPresetTemplateContextData();
    _temperature = 0.7; // 🚀 新增：重置温度参数
    _topP = 0.9; // 🚀 新增：重置Top-P参数
    _hasUnsavedChanges = false;
    _tagsController.clear();
    
    // 🚀 清空动态表单值和控制器
    _formValues.clear();
    for (final controller in _formControllers.values) {
      controller.clear();
    }
    _currentFeatureType = null;
    
    AppLogger.i(_tag, '🧹 表单清空完成 - 关联模板已重置为null');
  }

  /// 构建空状态视图
  Widget _buildEmptyState() {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: WebTheme.getSecondaryBorderColor(context),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.settings_suggest_outlined,
                size: 32,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '选择一个预设',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '在左侧列表中选择一个预设进行查看或编辑',
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建详情视图
  Widget _buildDetailView(AIPromptPreset preset) {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: Column(
        children: [
          // 顶部操作栏
          _buildTopActionBar(preset),
          
          // 标签栏（仅“设置”）
          _buildTabBar(),

          // 标签页内容（仅“设置”）
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSettingsTab(preset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建顶部操作栏
  Widget _buildTopActionBar(AIPromptPreset preset) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getSecondaryBorderColor(context),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // 预设类型图标
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: preset.isSystem 
                  ? (WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey100)
                  : WebTheme.getPrimaryColor(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              preset.isSystem ? Icons.settings : Icons.person,
              size: 16,
              color: preset.isSystem 
                  ? WebTheme.getSecondaryTextColor(context)
                  : WebTheme.white,
            ),
          ),
          const SizedBox(width: 10),
          
          // 预设名称
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.presetName ?? '未命名预设',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (preset.presetDescription != null && preset.presetDescription!.isNotEmpty)
                  Text(
                    preset.presetDescription!,
                    style: TextStyle(
                      fontSize: 11,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          
          // 状态指示器
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasUnsavedChanges)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: WebTheme.getPrimaryColor(context),
                    shape: BoxShape.circle,
                  ),
                ),
              
              if (preset.showInQuickAccess)
                Icon(
                  Icons.star,
                  size: 14,
                  color: Colors.amber,
                ),
            ],
          ),
          
          const SizedBox(width: 8),
          
          // 操作按钮组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🆕 分享按钮（最左侧）
              if (!preset.isSystem && !preset.isPublic) ...[
                _buildTextButton(
                  icon: Icons.share_rounded,
                  label: '分享',
                  tooltip: '分享预设到市场',
                  onPressed: () => _showShareDialog(preset),
                  backgroundColor: const Color(0xFF007AFF),
                  textColor: Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              
              if (!preset.isSystem) ...[
                _buildTextButton(
                  icon: Icons.save,
                  label: '保存',
                  tooltip: '保存',
                  onPressed: _hasUnsavedChanges ? () => _savePreset(preset) : null,
                ),
                const SizedBox(width: 4),
              ],
              _buildTextButton(
                icon: Icons.save_as,
                label: '另存为',
                tooltip: '另存为',
                onPressed: () => _saveAsPreset(preset),
              ),
              const SizedBox(width: 4),
              _buildTextButton(
                icon: preset.showInQuickAccess ? Icons.star : Icons.star_outline,
                label: '快捷',
                tooltip: preset.showInQuickAccess ? '取消快捷访问' : '设为快捷访问',
                onPressed: () => _toggleQuickAccess(preset),
              ),
              if (!preset.isSystem) ...[
                const SizedBox(width: 4),
                _buildTextButton(
                  icon: Icons.delete_outline,
                  label: '删除',
                  tooltip: '删除',
                  onPressed: () => _deletePreset(preset),
                  isDestructive: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 构建文本按钮（图标+文字）
  Widget _buildTextButton({
    required IconData icon,
    required String label,
    required String tooltip,
    VoidCallback? onPressed,
    Color? backgroundColor,
    Color? textColor,
    bool isDestructive = false,
  }) {
    final isDark = WebTheme.isDarkMode(context);
    final defaultBackgroundColor = isDark ? WebTheme.darkGrey200 : WebTheme.grey100;
    final defaultTextColor = onPressed != null 
        ? (isDestructive ? WebTheme.error : (isDark ? WebTheme.darkGrey600 : WebTheme.grey700))
        : (isDark ? WebTheme.darkGrey400 : WebTheme.grey400);
    
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: backgroundColor ?? defaultBackgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: textColor ?? defaultTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor ?? defaultTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// 显示分享对话框
  Future<void> _showShareDialog(AIPromptPreset preset) async {
    // 🚀 获取AI功能类型
    AIFeatureType? featureType;
    try {
      featureType = AIFeatureTypeHelper.fromApiString(preset.aiFeatureType.toUpperCase());
    } catch (e) {
      AppLogger.error(_tag, '无法解析AI功能类型: ${preset.aiFeatureType}', e);
      if (mounted) {
        TopToast.error(context, '无法确定预设类型');
      }
      return;
    }
    
    // 🚀 获取积分奖励信息
    int? rewardPoints;
    try {
      final marketRepo = PromptMarketRepository(ApiClient());
      final allPoints = await marketRepo.getAllRewardPoints();
      final featureTypeKey = featureType.toApiString();
      rewardPoints = allPoints[featureTypeKey];
    } catch (e) {
      AppLogger.error(_tag, '获取积分奖励信息失败: $e');
      rewardPoints = 1; // 默认1积分
    }
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => ShareTemplateDialog(
        templateId: preset.presetId,
        templateName: preset.presetName ?? '未命名预设',
        description: preset.presetDescription,
        featureType: featureType!,
        isPublic: preset.isPublic,
        reviewStatus: null, // 预设暂时没有审核状态
        usageCount: preset.useCount,
        rewardPoints: rewardPoints,
        hidePrompts: false, // 预设默认不隐藏
        hasSettingGenerationConfig: false, // 🆕 预设目前不包含设定生成配置
        onSubmitReview: (hidePrompts) async {
          Navigator.of(context).pop();
          await _submitPresetForReview(preset, hidePrompts);
        },
      ),
    );
  }
  
  /// 提交预设审核
  Future<void> _submitPresetForReview(AIPromptPreset preset, bool hidePrompts) async {
    try {
      // TODO: 实现预设分享API，需要支持hidePrompts参数
      // 当前预设系统还没有对应的分享接口，需要后端支持
      if (mounted) {
        final hideTip = hidePrompts ? '（已隐藏提示词）' : '';
        TopToast.info(context, '预设分享功能开发中$hideTip，敬请期待');
      }
      
      // 刷新数据
      context.read<PresetBloc>().add(const LoadAllPresetData());
    } catch (e) {
      AppLogger.error(_tag, '提交审核失败: $e');
      if (mounted) {
        TopToast.error(context, '提交失败: $e');
      }
    }
  }

  /// 构建标签栏
  Widget _buildTabBar() {
    return Container(
      // 对齐提示词详情的标签栏样式
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getSecondaryBorderColor(context),
            width: 1.0,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: WebTheme.getPrimaryColor(context),
        unselectedLabelColor: WebTheme.getSecondaryTextColor(context),
        indicatorColor: WebTheme.getPrimaryColor(context),
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('设置'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建设置标签页
  Widget _buildSettingsTab(AIPromptPreset preset) {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 基本信息
            _buildCompactBasicInfoSection(preset),
            
            const SizedBox(height: 20),
            
            // 分割线
            _buildDivider(),
            
            const SizedBox(height: 20),

            // 🚀 使用动态表单系统
            ..._buildDynamicFormFields(preset),
          ],
        ),
      ),
    );
  }

  /// 区段标题（对齐 EditUserPresetDialog 的风格）
  Widget _buildSectionHeader({
    required String title,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  void _showPromptHelper() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WebTheme.getSurfaceColor(context),
        surfaceTintColor: Colors.transparent,
        title: Text(
          '提示词写作技巧',
          style: TextStyle(
            color: WebTheme.getTextColor(context),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPromptTip('优化建议', const [
                '• 使用具体而非抽象的描述',
                '• 明确定义期望的输出格式',
                '• 提供具体的例子和情境',
                '• 根据功能类型调整提示词风格',
              ]),
              const SizedBox(height: 16),
              _buildPromptTip('功能特定建议', const [
                '聊天: 强调对话风格和个性',
                '场景生成: 注重描述细节和氛围',
                '续写: 保持风格一致性',
                '总结: 明确长度和要点',
                '大纲: 指定结构和层次',
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptTip(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 12,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            )),
      ],
    );
  }
  
  /// 🚀 构建动态表单字段
  List<Widget> _buildDynamicFormFields(AIPromptPreset preset) {
    if (_currentFeatureType == null) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '无法识别的AI功能类型: ${preset.aiFeatureType}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    
    // 获取当前功能类型的表单配置
    final formConfigs = AIFeatureFormConfig.getFormConfig(_currentFeatureType!);
    
    if (formConfigs.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前功能类型暂无配置的表单字段',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    
    // 对齐用户侧：分组渲染（指令区 / 上下文区 / 模板与参数区 / 其他）
    final widgets = <Widget>[];

    // 1) 指令相关
    final instructionTypes = {
      AIFormFieldType.instructions,
      AIFormFieldType.length,
      AIFormFieldType.style,
    };
    final instructionFields = formConfigs.where((c) => instructionTypes.contains(c.type)).toList();
    if (instructionFields.isNotEmpty) {
      widgets.add(_buildSectionHeader(title: '提示词配置', trailing: TextButton.icon(
        onPressed: _showPromptHelper,
        icon: const Icon(Icons.help_outline, size: 16),
        label: const Text('写作技巧'),
      )));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(_buildFieldList(preset, instructionFields));
      widgets.add(const SizedBox(height: 20));
      widgets.add(_buildDivider());
      widgets.add(const SizedBox(height: 20));
    }

    // 2) 上下文相关
    final contextTypes = {
      AIFormFieldType.contextSelection,
      AIFormFieldType.smartContext,
      AIFormFieldType.memoryCutoff,
    };
    final contextFields = formConfigs.where((c) => contextTypes.contains(c.type)).toList();
    if (contextFields.isNotEmpty) {
      widgets.add(_buildSectionHeader(title: '上下文与记忆'));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(_buildFieldList(preset, contextFields));
      widgets.add(const SizedBox(height: 20));
      widgets.add(_buildDivider());
      widgets.add(const SizedBox(height: 20));
    }

    // 3) 模板与参数
    final templateAndParams = formConfigs.where((c) =>
      c.type == AIFormFieldType.promptTemplate ||
      c.type == AIFormFieldType.temperature ||
      c.type == AIFormFieldType.topP
    ).toList();
    if (templateAndParams.isNotEmpty) {
      widgets.add(_buildSectionHeader(title: '模板与生成参数'));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(_buildFieldList(preset, templateAndParams));
      widgets.add(const SizedBox(height: 20));
      widgets.add(_buildDivider());
      widgets.add(const SizedBox(height: 20));
    }

    // 4) 其他（快捷访问等）
    final otherFields = formConfigs.where((c) =>
      !instructionTypes.contains(c.type) &&
      !contextTypes.contains(c.type) &&
      c.type != AIFormFieldType.promptTemplate &&
      c.type != AIFormFieldType.temperature &&
      c.type != AIFormFieldType.topP
    ).toList();
    if (otherFields.isNotEmpty) {
      widgets.add(_buildSectionHeader(title: '其他设置'));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(_buildFieldList(preset, otherFields));
    }

    return widgets;
  }

  List<Widget> _buildFieldList(AIPromptPreset preset, List<FormFieldConfig> fields) {
    final list = <Widget>[];
    for (int i = 0; i < fields.length; i++) {
      final config = fields[i];
      list.add(
        DynamicFormFieldWidget(
          config: config,
          values: _formValues,
          onValueChanged: _handleDynamicFormValueChanged,
          onReset: _handleDynamicFormFieldReset,
          contextSelectionData: _contextSelectionData,
          controllers: _formControllers,
          aiFeatureType: preset.aiFeatureType,
          isSystemPreset: preset.isSystem,
          isPublicPreset: preset.isPublic,
        ),
      );
      if (i < fields.length - 1) {
        list.add(const SizedBox(height: 16));
      }
    }
    return list;
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: WebTheme.getSecondaryBorderColor(context),
    );
  }
  
  /// 构建紧凑型基本信息部分
  Widget _buildCompactBasicInfoSection(AIPromptPreset preset) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            '基本信息',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          
          // 预设名称（对齐用户对话框样式：OutlineInputBorder、isDense、hint 颜色）
          _buildCompactFormField(
            label: '预设名称',
            child: TextFormField(
              controller: _presetNameController,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
              decoration: WebTheme.getBorderedInputDecoration(
                labelText: '预设名称',
                hintText: '输入预设名称',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                context: context,
              ),
              enabled: !preset.isSystem,
              onChanged: (_) => _markAsChanged(),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 预设描述（对齐用户对话框样式）
          _buildCompactFormField(
            label: '预设描述',
            child: TextFormField(
              controller: _presetDescriptionController,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
              decoration: WebTheme.getBorderedInputDecoration(
                labelText: '预设描述',
                hintText: '输入预设描述',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                context: context,
              ),
              enabled: !preset.isSystem,
              onChanged: (_) => _markAsChanged(),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 标签（对齐用户侧：逗号分隔输入框）
          _buildCompactFormField(
            label: '标签',
            child: TextFormField(
              controller: _tagsController,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
              decoration: WebTheme.getBorderedInputDecoration(
                labelText: '标签',
                hintText: '请输入标签，用逗号分隔',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                context: context,
              ),
              enabled: !preset.isSystem,
              onChanged: (_) => _markAsChanged(),
            ),
          ),

          const SizedBox(height: 12),

          // 功能类型和状态信息（横向布局）
          Row(
            children: [
              Expanded(
                child: _buildCompactInfoItem(
                  label: 'AI功能',
                  value: _getFeatureDisplayName(preset.aiFeatureType),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCompactInfoItem(
                  label: '类型',
                  value: preset.isSystem ? '系统预设' : '用户预设',
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: _buildCompactInfoItem(
                  label: '使用次数',
                  value: '${preset.useCount}',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCompactInfoItem(
                  label: '快捷访问',
                  value: preset.showInQuickAccess ? '是' : '否',
                ),
              ),
            ],
          ),
          
          // 标签
          if (preset.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildCompactFormField(
              label: '标签',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: preset.tags.map((tag) => _buildCompactTag(tag)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// 构建紧凑型表单字段
  Widget _buildCompactFormField({
    required String label,
    required Widget child,
  }) {
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
  
  /// 构建紧凑型信息项
  Widget _buildCompactInfoItem({
    required String label,
    required String value,
  }) {
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: WebTheme.getTextColor(context),
          ),
        ),
      ],
    );
  }
  
  /// 构建紧凑型标签
  Widget _buildCompactTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey200 : WebTheme.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WebTheme.getSecondaryBorderColor(context),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: WebTheme.getTextColor(context),
        ),
      ),
    );
  }
  
  /// 🚀 处理动态表单字段值变更
  void _handleDynamicFormValueChanged(AIFormFieldType type, dynamic value) {
    setState(() {
      _formValues[type] = value;
      
      // 同步到传统字段变量（保持兼容性）
      switch (type) {
        case AIFormFieldType.instructions:
          _instructionsController.text = value as String? ?? '';
          break;
        case AIFormFieldType.smartContext:
          _enableSmartContext = value as bool? ?? true;
          break;
        case AIFormFieldType.temperature:
          _temperature = value as double? ?? 0.7;
          break;
        case AIFormFieldType.topP:
          _topP = value as double? ?? 0.9;
          break;
        case AIFormFieldType.quickAccess:
          _showInQuickAccess = value as bool? ?? false;
          break;
        case AIFormFieldType.promptTemplate:
          _selectedPromptTemplate = value as String?;
          break;
        case AIFormFieldType.contextSelection:
          if (value is ContextSelectionData) {
            _contextSelectionData = value;
          }
          break;
        default:
          // 其他字段类型保存在_formValues中
          break;
      }
      
      _markAsChanged();
    });
    
    AppLogger.i(_tag, '动态表单字段值已更改: $type = $value');
  }
  
  /// 🚀 处理动态表单字段重置
  void _handleDynamicFormFieldReset(AIFormFieldType type) {
    setState(() {
      _formValues.remove(type);
      _formControllers[type]?.clear();
      
      // 重置传统字段变量（保持兼容性）
      switch (type) {
        case AIFormFieldType.instructions:
          _instructionsController.clear();
          break;
        case AIFormFieldType.smartContext:
          _enableSmartContext = true;
          _formValues[type] = true;
          break;
        case AIFormFieldType.temperature:
          _temperature = 0.7;
          _formValues[type] = 0.7;
          break;
        case AIFormFieldType.topP:
          _topP = 0.9;
          _formValues[type] = 0.9;
          break;
        case AIFormFieldType.quickAccess:
          _showInQuickAccess = false;
          _formValues[type] = false;
          break;
        case AIFormFieldType.promptTemplate:
          _selectedPromptTemplate = null;
          break;
        case AIFormFieldType.contextSelection:
          _contextSelectionData = FormFieldFactory.createPresetTemplateContextData();
          _formValues[type] = _contextSelectionData;
          break;
        default:
          // 其他字段类型的默认重置逻辑
          break;
      }
      
      _markAsChanged();
    });
    
    AppLogger.i(_tag, '动态表单字段已重置: $type');
  }

  // 移除未使用的 _buildBasicInfoSection 以消除告警

  // 预览功能已移除

  // 移除未使用的 _buildFormField

  // 移除未使用的 _buildTag

  // 移除未使用的 _buildAddTagButton

  /// 获取指令预设列表
  // 移除未使用的 _getInstructionPresets 以消除告警

  /// 获取功能类型显示名称
  String _getFeatureDisplayName(String featureType) {
    try {
      final type = AIFeatureTypeHelper.fromApiString(featureType.toUpperCase());
      return type.displayName;
    } catch (e) {
      return featureType;
    }
  }

  /// 将AIFeatureType映射到AIRequestType
  AIRequestType _mapFeatureTypeToRequestType(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.textExpansion:
        return AIRequestType.expansion;
      case AIFeatureType.textSummary:
        return AIRequestType.summary;
      case AIFeatureType.textRefactor:
        return AIRequestType.refactor;
      case AIFeatureType.aiChat:
        return AIRequestType.chat;
      case AIFeatureType.sceneToSummary:
        return AIRequestType.sceneSummary;
      case AIFeatureType.novelGeneration:
        return AIRequestType.generation;
      case AIFeatureType.novelCompose:
        return AIRequestType.novelCompose;
      case AIFeatureType.storyPlotContinuation:
        return AIRequestType.expansion; // 使用扩展类型
      default:
        return AIRequestType.expansion; // 默认类型
    }
  }

  /// 标记为已更改
  void _markAsChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  // 移除未使用的 handlers 以消除告警











  /// 🚀 新增：处理温度参数变化

  /// 🚀 新增：重置温度参数

  /// 🚀 新增：处理Top-P参数变化

  /// 🚀 新增：重置Top-P参数

  // 操作方法
    void _savePreset(AIPromptPreset preset) {
    AppLogger.i(_tag, '💾 开始保存预设: ${preset.presetId}');

    try {
      // 🚀 使用当前编辑状态而不是传入参数
      final currentPreset = _editingPreset ?? preset;
      
      // 🚀 重新构建 requestData（反映用户的所有修改）
      final updatedRequest = _buildUniversalAIRequestFromCurrentForm(currentPreset);
      final newRequestData = updatedRequest != null 
          ? jsonEncode(updatedRequest.toApiJson())
          : currentPreset.requestData; // 如果构建失败，保持原数据
      
      // 🚀 重新计算预设哈希
      final newPresetHash = _generatePresetHash(newRequestData);
      
      // 🚀 构建完整的更新对象（基于最新状态）
      final normalizedTemplateId = _normalizeTemplateIdForSave(_selectedPromptTemplate);
      final updatedPreset = AIPromptPreset(
        presetId: currentPreset.presetId,
        userId: currentPreset.userId,
        presetName: _presetNameController.text.trim(),
        presetDescription: _presetDescriptionController.text.trim().isNotEmpty
            ? _presetDescriptionController.text.trim()
            : null,
        presetTags: _parseTags(_tagsController.text),
        isFavorite: currentPreset.isFavorite,
        isPublic: currentPreset.isPublic,
        useCount: currentPreset.useCount,
        presetHash: newPresetHash,
        requestData: newRequestData, // 🚀 使用重新构建的 requestData
        systemPrompt: currentPreset.systemPrompt,
        userPrompt: _instructionsController.text.trim(),
        aiFeatureType: currentPreset.aiFeatureType,
        customSystemPrompt: currentPreset.customSystemPrompt,
        customUserPrompt: _instructionsController.text.trim().isNotEmpty 
            ? _instructionsController.text.trim() 
            : null,
        promptCustomized: _instructionsController.text.trim() != currentPreset.userPrompt,
        templateId: normalizedTemplateId,
        isSystem: currentPreset.isSystem,
        showInQuickAccess: _showInQuickAccess,
        createdAt: currentPreset.createdAt,
        updatedAt: DateTime.now(),
        lastUsedAt: currentPreset.lastUsedAt,
      );

      AppLogger.i(_tag, '📋 构建完整更新对象:');
      AppLogger.i(_tag, '  - 预设名称: ${updatedPreset.presetName}');
      AppLogger.i(_tag, '  - 预设描述: ${updatedPreset.presetDescription ?? "无"}');
      AppLogger.i(_tag, '  - 快捷访问: ${updatedPreset.showInQuickAccess}');
      AppLogger.i(_tag, '  - 指令长度: ${_instructionsController.text.length}');

      // 🚀 发送覆盖更新事件
      context.read<PresetBloc>().add(OverwritePreset(preset: updatedPreset));

      // 重置修改标记
      setState(() {
        _hasUnsavedChanges = false;
      });

      AppLogger.i(_tag, '✅ 覆盖更新请求已发送');
      
    } catch (e) {
      AppLogger.e(_tag, '❌ 构建保存请求失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _saveAsPreset(AIPromptPreset preset) {
    AppLogger.i(_tag, '📋 另存为预设: ${preset.presetId}');
    _showSaveAsDialog(preset);
  }

  /// 显示另存为对话框
  void _showSaveAsDialog(AIPromptPreset preset) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    
    // 设置默认名称
    nameController.text = '${_presetNameController.text.trim()} - 副本';
    descController.text = _presetDescriptionController.text.trim();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WebTheme.getSurfaceColor(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: WebTheme.getSecondaryBorderColor(context),
            width: 1,
          ),
        ),
        title: Text(
          '另存为新预设',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
              decoration: WebTheme.getBorderedInputDecoration(
                labelText: '新预设名称',
                hintText: '输入新预设名称',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                context: context,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
              decoration: WebTheme.getBorderedInputDecoration(
                labelText: '描述（可选）',
                hintText: '输入预设描述',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                context: context,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: WebTheme.getSecondaryTextColor(context),
              textStyle: TextStyle(fontSize: 13),
            ),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop();
                _performSaveAs(preset, name, descController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.getPrimaryColor(context),
              foregroundColor: WebTheme.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            child: const Text('另存为'),
          ),
        ],
      ),
    );
  }

  /// 执行另存为操作
  void _performSaveAs(AIPromptPreset preset, String newName, String newDescription) {
    AppLogger.i(_tag, '🚀 开始执行另存为: $newName');
    
    try {
      // 构建新的UniversalAIRequest
      final newRequest = _buildUniversalAIRequestFromCurrentForm(preset);
      if (newRequest == null) {
        throw Exception('无法构建有效的AI请求配置');
      }
      
      // 构建创建预设请求
      final createRequest = CreatePresetRequest(
        presetName: newName,
        presetDescription: newDescription.isNotEmpty ? newDescription : null,
        presetTags: _parseTags(_tagsController.text),
        request: newRequest,
      );
      
      AppLogger.i(_tag, '📋 创建请求已构建:');
      AppLogger.i(_tag, '  - 新预设名称: $newName');
      AppLogger.i(_tag, '  - 新预设描述: ${newDescription.isNotEmpty ? newDescription : "无"}');
      AppLogger.i(_tag, '  - 功能类型: ${preset.aiFeatureType}');
      AppLogger.i(_tag, '  - 指令长度: ${_instructionsController.text.length}');
      AppLogger.i(_tag, '  - 上下文项目数: ${_contextSelectionData.selectedCount}');
      AppLogger.i(_tag, '  - 关联模板ID: ${_selectedPromptTemplate ?? "无"}');
      
      // 发送创建事件到PresetBloc
      context.read<PresetBloc>().add(CreatePreset(request: createRequest));
      
      AppLogger.i(_tag, '✅ 另存为请求已发送');
      
    } catch (e) {
      AppLogger.e(_tag, '❌ 另存为操作失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('另存为失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  List<String>? _parseTags(String text) {
    final parts = text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts;
  }

  /// 从当前表单状态构建UniversalAIRequest
  UniversalAIRequest? _buildUniversalAIRequestFromCurrentForm(AIPromptPreset preset) {
    try {
      // 解析AI功能类型
      AIRequestType requestType;
      try {
        final featureType = AIFeatureTypeHelper.fromApiString(preset.aiFeatureType.toUpperCase());
        requestType = _mapFeatureTypeToRequestType(featureType);
      } catch (e) {
        AppLogger.w(_tag, '无法解析功能类型: ${preset.aiFeatureType}', e);
        requestType = AIRequestType.expansion; // 回退到默认类型
      }
      
      // 构建请求对象
      final normalizedTemplateId = _normalizeTemplateIdForSave(_selectedPromptTemplate);
      final request = UniversalAIRequest(
        requestType: requestType,
        userId: preset.userId,
        novelId: 'preset_template', // 预设模板使用特殊的novelId
        instructions: _instructionsController.text.trim().isNotEmpty 
            ? _instructionsController.text.trim() 
            : null,
        contextSelections: _contextSelectionData,
        enableSmartContext: _enableSmartContext,
        parameters: {
          'enableSmartContext': _enableSmartContext,
          'showInQuickAccess': _showInQuickAccess,
          'associatedTemplateId': normalizedTemplateId,
          'promptTemplateId': normalizedTemplateId,
          'temperature': _temperature, // 🚀 新增：温度参数
          'topP': _topP, // 🚀 新增：Top-P参数
        },
        metadata: {
          'source': 'preset_management',
          'action': 'save_as',
          'originalPresetId': preset.presetId,
          'contextCount': _contextSelectionData.selectedCount,
          'enableSmartContext': _enableSmartContext,
          'showInQuickAccess': _showInQuickAccess,
          'associatedTemplateId': normalizedTemplateId,
          'promptTemplateId': normalizedTemplateId,
          'temperature': _temperature, // 🚀 新增：温度参数
          'topP': _topP, // 🚀 新增：Top-P参数
        },
      );
      
      AppLogger.i(_tag, '🔧 UniversalAIRequest构建成功:');
      AppLogger.i(_tag, '  - requestType: ${request.requestType.value}');
      AppLogger.i(_tag, '  - userId: ${request.userId}');
      AppLogger.i(_tag, '  - novelId: ${request.novelId}');
      AppLogger.i(_tag, '  - 指令: ${request.instructions?.substring(0, request.instructions!.length.clamp(0, 50)) ?? "无"}...');
      
      return request;
      
    } catch (e) {
      AppLogger.e(_tag, '❌ 构建UniversalAIRequest失败', e);
      return null;
    }
  }

  /// 规范化模板ID以用于保存：
  /// - public_ 前缀移除，得到真实模板ID
  /// - system_default_ 视为不关联（返回null）
  String? _normalizeTemplateIdForSave(String? rawId) {
    if (rawId == null || rawId.isEmpty) return null;
    if (rawId.startsWith('public_')) return rawId.substring(7);
    if (rawId.startsWith('system_default_')) return null;
    return rawId;
  }

  void _toggleQuickAccess(AIPromptPreset preset) {
    AppLogger.i(_tag, '⭐ 切换快捷访问状态: ${preset.presetId}');
    AppLogger.i(_tag, '  - 当前状态: ${preset.showInQuickAccess ? "已启用" : "已禁用"}');
    AppLogger.i(_tag, '  - 预设类型: ${preset.isSystem ? "系统预设" : "用户预设"}');
    AppLogger.i(_tag, '  - 预设名称: ${preset.presetName}');
    
    // 检查预设是否有效
    if (preset.presetId.isEmpty) {
      AppLogger.e(_tag, '❌ 预设ID为空，无法切换快捷访问状态');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('操作失败：预设ID无效'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      context.read<PresetBloc>().add(TogglePresetQuickAccess(presetId: preset.presetId));
      AppLogger.i(_tag, '✅ 快捷访问切换请求已发送');
    } catch (e) {
      AppLogger.e(_tag, '❌ 发送快捷访问切换请求失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deletePreset(AIPromptPreset preset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WebTheme.getSurfaceColor(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: WebTheme.getSecondaryBorderColor(context),
            width: 1,
          ),
        ),
        title: Text(
          '确认删除',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        content: Text(
          '确定要删除预设"${preset.presetName}"吗？此操作无法撤销。',
          style: TextStyle(
            fontSize: 13,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: WebTheme.getSecondaryTextColor(context),
              textStyle: TextStyle(fontSize: 13),
            ),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              AppLogger.i(_tag, '删除预设: ${preset.presetId}');
              context.read<PresetBloc>().add(DeletePreset(presetId: preset.presetId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.error,
              foregroundColor: WebTheme.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 🚀 生成预设哈希值
  String _generatePresetHash(String requestDataJson) {
    try {
      final bytes = utf8.encode(requestDataJson);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      AppLogger.w(_tag, '生成预设哈希失败，使用时间戳: $e');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
}