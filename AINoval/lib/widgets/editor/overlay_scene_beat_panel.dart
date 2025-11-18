import 'dart:convert';
import 'dart:math' show max;
import 'package:ainoval/models/scene_beat_data.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/context_selection_dropdown_menu_anchor.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/context_selection_helper.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/screens/editor/components/scene_beat_edit_dialog.dart';
import 'package:ainoval/screens/editor/components/ai_dialog_common_logic.dart';
import 'package:ainoval/widgets/common/preset_dropdown_button.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:collection/collection.dart';

/// Overlay版本的场景节拍面板
/// 固定在屏幕左侧中间位置，与滚动内容解耦
class OverlaySceneBeatPanel extends StatefulWidget {
  const OverlaySceneBeatPanel({
    super.key,
    required this.sceneId,
    required this.data,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.onDataChanged,
    this.onGenerate,
    this.onClose,
  });

  final String sceneId;
  final SceneBeatData data;
  final Novel? novel;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;
  final ValueChanged<SceneBeatData>? onDataChanged;
  final Function(UniversalAIRequest, UnifiedAIModel)? onGenerate;
  final VoidCallback? onClose;

  @override
  State<OverlaySceneBeatPanel> createState() => _OverlaySceneBeatPanelState();
}

class _OverlaySceneBeatPanelState extends State<OverlaySceneBeatPanel>
    with SingleTickerProviderStateMixin, AIDialogCommonLogic {
  bool _isExpanded = false;
  
  OverlayEntry? _tempOverlay;
  late TextEditingController _quickInstructionsController;
  late TextEditingController _customLengthController;
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;
  late Animation<double> _fadeAnimation;
  late String _currentLength;
  AIPromptPreset? _currentPreset;
  late ContextSelectionData _contextData;
  bool _skipNextContextRebuild = false; // 🚀 本地更新后跳过一次重建
  bool _includeCurrentSceneAsInput = true; // 🚀 默认将当前场景摘要与内容作为输入
  
  // 🚀 新增：缓存布局计算结果，避免频繁重建
  double? _cachedLeft;
  double? _cachedTop;
  double? _cachedScreenWidth;
  double? _cachedScreenHeight;
  double? _cachedPanelWidth;  // 🚀 新增：缓存面板宽度
  
  UnifiedAIModel? _selectedUnifiedModel;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadSelectedModel();
    _initializeQuickInstructions();
    _currentLength = widget.data.selectedLength ?? '400';
    _customLengthController = TextEditingController(text: _currentLength);
    _contextData = _createContextData();
    _persistDefaultContextIfNeeded();
  }

  @override
  void didUpdateWidget(OverlaySceneBeatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 场景切换时同步配置
    if (oldWidget.sceneId != widget.sceneId) {
      AppLogger.i('OverlaySceneBeatPanel', '场景切换: ${oldWidget.sceneId} -> ${widget.sceneId}');
      _syncConfigFromData();
      // 🚀 清除缓存，强制重新计算位置
      _clearLayoutCache();
    }
    
    // 🚀 优化：只在关键数据变化时才同步配置
    if (_shouldSyncConfig(oldWidget.data, widget.data)) {
      _syncConfigFromData();
    }

    // 仅当依赖发生变化时才重建上下文数据
    if (_shouldRebuildContextData(oldWidget)) {
      setState(() {
        _contextData = _createContextData();
      });
    }
  }
  
  /// 🚀 判断是否需要同步配置（避免无意义的同步）
  bool _shouldSyncConfig(SceneBeatData oldData, SceneBeatData newData) {
    return oldData.selectedUnifiedModelId != newData.selectedUnifiedModelId ||
           oldData.selectedLength != newData.selectedLength ||
           oldData.requestData != newData.requestData;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tempOverlay?.remove();
    _quickInstructionsController.dispose();
    _customLengthController.dispose();
    super.dispose();
  }
  
  /// 🚀 清除布局缓存
  void _clearLayoutCache() {
    _cachedLeft = null;
    _cachedTop = null;
    _cachedScreenWidth = null;
    _cachedScreenHeight = null;
    _cachedPanelWidth = null;  // 🚀 清除面板宽度缓存
  }
  
  /// 🚀 计算布局位置（带缓存，保持原有定位逻辑不变）
  ({double left, double top}) _calculatePosition(BuildContext context, double panelWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // 🚀 缓存检查：屏幕尺寸和面板宽度都没变化时才使用缓存
    if (_cachedScreenWidth == screenWidth && 
        _cachedScreenHeight == screenHeight && 
        _cachedPanelWidth == panelWidth &&
        _cachedLeft != null && 
        _cachedTop != null) {
      return (left: _cachedLeft!, top: _cachedTop!);
    }
    
    // ===== 保持原有定位逻辑完全不变 =====
    const double _kMaxContentWidth = 1100.0; // 与编辑器中心内容宽度保持一致
    const double _kMargin = 20.0; // 与内容之间的间距
    const double _kMinLeft = 280.0; // 左侧边栏宽度，避免遮挡
    final double leftSpace = (screenWidth - _kMaxContentWidth) / 2;
    double computedLeft = _kMargin;
    if (leftSpace > panelWidth + _kMargin) {
      computedLeft = leftSpace - panelWidth - _kMargin;
    }

    // 确保不会覆盖左侧边栏
    computedLeft = max(computedLeft, _kMinLeft);
    
    final double computedTop = screenHeight * 0.4;
    
    // 🚀 缓存计算结果（包括面板宽度）
    _cachedLeft = computedLeft;
    _cachedTop = computedTop;
    _cachedScreenWidth = screenWidth;
    _cachedScreenHeight = screenHeight;
    _cachedPanelWidth = panelWidth;
    
    return (left: computedLeft, top: computedTop);
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _widthAnimation = Tween<double>(
      begin: 120.0,
      end: 360.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
  }

  void _initializeQuickInstructions() {
    final parsedRequest = widget.data.parsedRequest;
    _quickInstructionsController = TextEditingController(
      text: parsedRequest?.instructions ?? '一个关键时刻，重要的事情发生改变，推动故事发展。',
    );
  }

  void _syncConfigFromData() {
    final parsedRequest = widget.data.parsedRequest;
    if (parsedRequest?.instructions != null &&
        parsedRequest!.instructions != _quickInstructionsController.text) {
      _quickInstructionsController.text = parsedRequest.instructions!;
    }

    if (widget.data.selectedUnifiedModelId != null &&
        widget.data.selectedUnifiedModelId!.isNotEmpty &&
        _selectedUnifiedModel?.id != widget.data.selectedUnifiedModelId) {
      _loadSelectedModel();
    }

    if (widget.data.selectedLength != null &&
        widget.data.selectedLength != _currentLength) {
      setState(() {
        _currentLength = widget.data.selectedLength!;
        if (_customLengthController.text != _currentLength) {
          _customLengthController.text = _currentLength;
        }
      });
    }
  }

  void _loadSelectedModel() {
    final modelId = widget.data.selectedUnifiedModelId;
    if (modelId == null || modelId.isEmpty) {
      AppLogger.d('OverlaySceneBeatPanel', '没有保存的模型ID，跳过加载');
      return;
    }

    AppLogger.d('OverlaySceneBeatPanel', '尝试加载模型ID: $modelId');

    final unifiedModel = _findUnifiedModelById(modelId);
    if (unifiedModel != null) {
      AppLogger.d('OverlaySceneBeatPanel', '成功加载模型: ${unifiedModel.displayName}');
      setState(() {
        _selectedUnifiedModel = unifiedModel;
      });
    } else {
      AppLogger.w('OverlaySceneBeatPanel', '未找到ID=$modelId 对应的模型');
    }
  }

  UnifiedAIModel? _findUnifiedModelById(String id) {
    AppLogger.d('OverlaySceneBeatPanel', '查找模型ID: $id');

    // 1. 私有模型（用户配置）
    try {
      final aiConfigState = context.read<AiConfigBloc>().state;
      AppLogger.d('OverlaySceneBeatPanel',
          '搜索私有模型，可用配置数量: ${aiConfigState.configs.length}');
      final privateConfig = aiConfigState.configs.firstWhereOrNull(
        (c) => c.id == id,
      );
      if (privateConfig != null) {
        AppLogger.d('OverlaySceneBeatPanel', '在私有模型中找到: ${privateConfig.name}');
        return PrivateAIModel(privateConfig);
      }
    } catch (e) {
      AppLogger.e('OverlaySceneBeatPanel', '读取 AiConfigBloc 失败或未找到私有模型: $e');
    }

    // 2. 公共模型
    try {
      final publicState = context.read<PublicModelsBloc>().state;
      AppLogger.d('OverlaySceneBeatPanel', '搜索公共模型，状态类型: ${publicState.runtimeType}');
      if (publicState is PublicModelsLoaded) {
        AppLogger.d('OverlaySceneBeatPanel',
            '搜索公共模型，可用模型数量: ${publicState.models.length}');
        final publicModel = publicState.models.firstWhereOrNull(
          (m) => m.id == id,
        );
        if (publicModel != null) {
          AppLogger.d('OverlaySceneBeatPanel', '在公共模型中找到: ${publicModel.displayName}');
          return PublicAIModel(publicModel);
        }
      }
    } catch (e) {
      AppLogger.e('OverlaySceneBeatPanel', '读取 PublicModelsBloc 失败或未找到公共模型: $e');
    }

    AppLogger.w('OverlaySceneBeatPanel', '未找到ID为 $id 的模型');
    return null;
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
    
    // 🚀 展开/折叠时清除位置缓存
    _clearLayoutCache();
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 降低日志频率：仅在状态变化时记录，避免生成期间的频繁日志
    if (widget.data.status != SceneBeatStatus.generating) {
      AppLogger.d('OverlaySceneBeatPanel',
          '构建场景节拍面板 - 场景: ${widget.sceneId}, 状态: ${widget.data.status.name}, 可生成: ${widget.data.status.canGenerate}, 已选择模型: ${_selectedUnifiedModel?.displayName ?? "无"}');
    }

    // 🚀 如果是生成状态且面板是折叠的，使用静态构建避免频繁重建
    if (widget.data.status == SceneBeatStatus.generating && !_isExpanded) {
      return _buildStaticCollapsedPanel(context);
    }

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, _) {
        final panelWidth = _widthAnimation.value.clamp(120.0, 360.0); // 🚀 限制面板最小/最大宽度
        final position = _calculatePosition(context, panelWidth);

        return Positioned(
          left: position.left,
          top: position.top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            shadowColor: Colors.black.withOpacity(0.3),
            child: Container(
              width: panelWidth,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isExpanded ? _buildExpandedContent() : _buildCollapsedContent(),
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// 🚀 构建静态的折叠面板（避免动画重建）
  Widget _buildStaticCollapsedPanel(BuildContext context) {
    final position = _calculatePosition(context, 120.0); // 折叠状态固定宽度
    
    return Positioned(
      left: position.left,
      top: position.top,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        shadowColor: Colors.black.withOpacity(0.3),
        child: Container(
          width: 120,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildCollapsedContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent() {
    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '场景节拍',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 600),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          _buildHeader(),
          const SizedBox(height: 12),
          
          // 内容区域
          Flexible(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    
                    // 预设选择和编辑按钮
                    _buildPresetAndEditRow(),
                    const SizedBox(height: 12),
                    
                    // 快速指令输入框
                    _buildQuickInstructionsField(),
                    const SizedBox(height: 12),
                    
                    // 🚀 勾选：将当前场景摘要与内容作为输入
                    _buildIncludeCurrentSceneToggle(),
                    const SizedBox(height: 12),
                    
                    // 上下文选择组件
                    _buildContextSelectionField(),
                    const SizedBox(height: 12),
                    
                    // 字数单独一排（含自定义输入）
                    _buildLengthRow(),
                    const SizedBox(height: 12),

                    // 模型与发送在一行
                    _buildModelGenerateRow(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncludeCurrentSceneToggle() {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: _includeCurrentSceneAsInput,
            onChanged: (val) {
              setState(() {
                _includeCurrentSceneAsInput = val ?? true;
              });
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '将当前场景摘要与内容作为输入（selectedText）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
          ),
        )
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.auto_stories,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '场景节拍',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 关闭按钮
        IconButton(
          onPressed: widget.onClose,
          icon: const Icon(Icons.close, size: 18),
          iconSize: 18,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(width: 4),
        // 折叠按钮
        IconButton(
          onPressed: _toggleExpanded,
          icon: const Icon(Icons.keyboard_arrow_left, size: 18),
          iconSize: 18,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetAndEditRow() {
    return Row(
      children: [
        // 预设选择器部分
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '预设',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              PresetDropdownButton(
                featureType: 'SCENE_BEAT_GENERATION',
                currentPreset: _currentPreset,
                onPresetSelected: _handlePresetSelected,
                onCreatePreset: _handleCreatePreset,
                onManagePresets: _showManagePresetsPage,
                novelId: widget.novel?.id,
                label: '选择预设',
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // 编辑按钮部分
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '详细配置',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _showEditDialog,
              icon: Icon(
                Icons.edit,
                size: 14,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              label: Text(
                '修改详细设置',
                style: WebTheme.labelSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: WebTheme.getSecondaryTextColor(context),
                backgroundColor: Colors.transparent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContextSelectionField() {
    // 🚀 使用缓存的上下文数据，避免重复计算
    final contextData = _contextData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '上下文',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 🚀 优化：减少条件检查和组件重建
              if (ContextSelectionHelper.validateContextData(contextData))
                ContextSelectionDropdownBuilder.buildMenuAnchor(
                  data: contextData,
                  onSelectionChanged: (newData) {
                    final updatedData = ContextSelectionHelper.handleSelectionChanged(
                      contextData,
                      newData,
                    );
                    _updateContextData(updatedData);
                  },
                  placeholder: '+ 添加上下文',
                  maxHeight: 300,
                  // 通过 sceneId 反推当前章节用于初始滚动定位
                  initialChapterId: _getActiveChapterId(),
                  initialSceneId: widget.sceneId,
                )
              else
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '上下文数据无效',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 🚀 已选择的上下文项目（优化渲染）
              ...contextData.selectedItems.values.map<Widget>((item) {
                return Container(
                  height: 32,
                  constraints: const BoxConstraints(maxWidth: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.75),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.type.icon,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          final newData = contextData.deselectItem(item.id);
                          _updateContextData(newData);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickInstructionsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '指令',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: _quickInstructionsController,
            maxLines: 3,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            decoration: InputDecoration(
              hintText: '快速指令...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontSize: 11,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(8),
            ),
            onChanged: _updateQuickInstructions,
          ),
        ),
      ],
    );
  }

  Widget _buildLengthRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '字数',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
            ...['200', '400', '600'].asMap().entries.map((entry) {
              final index = entry.key;
              final length = entry.value;
              final isSelected = _currentLength == length;
              return GestureDetector(
                onTap: () => _updateLength(length),
                child: Container(
                  width: 50,
                  margin: EdgeInsets.only(right: index < 2 ? 6 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    length,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                ),
              );
            }).toList(),

            // 自定义字数输入框
            SizedBox(
              width: 76,
              child: TextField(
                controller: _customLengthController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLines: 1,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: '自定义',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
                ),
                onSubmitted: _handleCustomLengthSubmitted,
                onEditingComplete: () {
                  _handleCustomLengthSubmitted(_customLengthController.text);
                },
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '字',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelGenerateRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '模型 & 生成',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        _buildModelGenerateButton(),
      ],
    );
  }

  Widget _buildModelGenerateButton() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // 模型选择部分
          Expanded(
            child: GestureDetector(
              onTap: () {
                AppLogger.d('OverlaySceneBeatPanel', '模型选择区域被点击！');
                _showModelSelectorDropdown();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.3),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    bottomLeft: Radius.circular(5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedUnifiedModel?.displayName ?? '选择模型',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 生成按钮部分
          Container(
            width: 40,
            height: 36,
            decoration: BoxDecoration(
              color: widget.data.status.canGenerate
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(5),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.data.status.canGenerate
                    ? () {
                        AppLogger.d('OverlaySceneBeatPanel',
                            '生成按钮被点击！状态: ${widget.data.status.name}');
                        _handleGenerate();
                      }
                    : () {
                        AppLogger.w('OverlaySceneBeatPanel',
                            '生成按钮被点击但状态不允许生成: ${widget.data.status.name}');
                      },
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: widget.data.status.canGenerate
                      ? Colors.white
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePresetSelected(AIPromptPreset preset) {
    try {
      setState(() {
        _currentPreset = preset;
      });

      applyPresetToForm(
        preset,
        instructionsController: _quickInstructionsController,
        onLengthChanged: (length) {
          setState(() {
            if (length != null && ['200', '400', '600'].contains(length)) {
              _currentLength = length;
            } else if (length != null) {
              _currentLength = length; // 自定义长度作为当前值
            }
          });
          // 同步到数据模型
          final updated = widget.data.copyWith(
            selectedLength: _currentLength,
            updatedAt: DateTime.now(),
          );
          widget.onDataChanged?.call(updated);
        },
        onSmartContextChanged: (value) {
          final updated = widget.data.copyWith(
            enableSmartContext: value,
            updatedAt: DateTime.now(),
          );
          widget.onDataChanged?.call(updated);
        },
        onPromptTemplateChanged: (templateId) {
          final updated = widget.data.copyWith(
            selectedPromptTemplateId: templateId,
            updatedAt: DateTime.now(),
          );
          widget.onDataChanged?.call(updated);
        },
        onTemperatureChanged: (temperature) {
          final updated = widget.data.copyWith(
            temperature: temperature,
            updatedAt: DateTime.now(),
          );
          widget.onDataChanged?.call(updated);
        },
        onTopPChanged: (topP) {
          final updated = widget.data.copyWith(
            topP: topP,
            updatedAt: DateTime.now(),
          );
          widget.onDataChanged?.call(updated);
        },
        onContextSelectionChanged: (contextData) {
          _updateContextData(contextData);
        },
        onModelChanged: (unifiedModel) {
          setState(() {
            _selectedUnifiedModel = unifiedModel;
          });
          if (unifiedModel != null) {
            _updateModelSelection(unifiedModel);
          }
        },
        currentContextData: _contextData,
      );

      // 同步指令到请求数据
      _updateQuickInstructions(_quickInstructionsController.text);

      // 记录最后使用的预设ID
      final updatedWithPreset = widget.data.copyWith(
        lastUsedPresetId: preset.presetId,
        updatedAt: DateTime.now(),
      );
      widget.onDataChanged?.call(updatedWithPreset);
    } catch (e) {
      AppLogger.e('OverlaySceneBeatPanel', '应用预设失败', e);
      TopToast.error(context, '应用预设失败: $e');
    }
  }

  void _handleCreatePreset() {
    // 基于当前 UI 构建请求
    final request = _buildAIRequest();
    if (request == null) {
      TopToast.warning(context, '请先选择AI模型');
      return;
    }
    showPresetNameDialog(request, onPresetCreated: (preset) {
      setState(() {
        _currentPreset = preset;
      });
      TopToast.success(context, '预设 "${preset.presetName}" 创建成功');
    });
  }

  void _showManagePresetsPage() {
    TopToast.info(context, '预设管理功能开发中...');
  }

  void _showModelSelectorDropdown() {
    AppLogger.d('OverlaySceneBeatPanel', '显示模型选择器');

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      AppLogger.w('OverlaySceneBeatPanel', '无法获取RenderBox');
      return;
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final anchorRect =
        Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

    _tempOverlay?.remove();

    AppLogger.d('OverlaySceneBeatPanel', '创建模型选择器下拉框');

    _tempOverlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: anchorRect,
      selectedModel: _selectedUnifiedModel,
      onModelSelected: (unifiedModel) {
        AppLogger.d('OverlaySceneBeatPanel',
            '模型选择完成: ${unifiedModel?.displayName ?? "null"}');
        setState(() {
          _selectedUnifiedModel = unifiedModel;
        });
        _updateModelSelection(unifiedModel!);
      },
      showSettingsButton: true,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      onClose: () {
        AppLogger.d('OverlaySceneBeatPanel', '模型选择器已关闭');
        _tempOverlay = null;
      },
    );
  }

  void _updateQuickInstructions(String value) {
    final parsedRequest = widget.data.parsedRequest;
    if (parsedRequest != null) {
      final updatedRequest = UniversalAIRequest(
        requestType: parsedRequest.requestType,
        userId: parsedRequest.userId,
        novelId: parsedRequest.novelId,
        modelConfig: parsedRequest.modelConfig,
        prompt: parsedRequest.prompt,
        instructions: value,
        contextSelections: parsedRequest.contextSelections,
        enableSmartContext: parsedRequest.enableSmartContext,
        parameters: parsedRequest.parameters,
        metadata: parsedRequest.metadata,
      );

      final updatedData = widget.data.updateRequestData(updatedRequest);
      widget.onDataChanged?.call(updatedData);
    }
  }

  void _updateLength(String length) {
    setState(() {
      _currentLength = length;
      if (_customLengthController.text != length) {
        _customLengthController.text = length;
      }
    });

    final updatedData = widget.data.copyWith(
      selectedLength: length,
      updatedAt: DateTime.now(),
    );
    widget.onDataChanged?.call(updatedData);
  }

  void _handleCustomLengthSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return;
    // 合理范围保护（50-5000），可根据需要调整
    final clamped = parsed.clamp(50, 5000);
    final finalValue = clamped.toString();
    _updateLength(finalValue);
  }

  void _updateModelSelection(UnifiedAIModel model) {
    AppLogger.d('OverlaySceneBeatPanel',
        '更新模型选择: ${model.displayName} (ID: ${model.id})');

    final updatedData = widget.data.copyWith(
      selectedUnifiedModelId: model.id,
      updatedAt: DateTime.now(),
    );

    AppLogger.d('OverlaySceneBeatPanel', '调用onDataChanged回调');
    widget.onDataChanged?.call(updatedData);

    AppLogger.d('OverlaySceneBeatPanel', '模型选择更新完成');
  }

  void _updateContextData(ContextSelectionData newData) {
    setState(() {
      _contextData = newData;
    });

    final updatedData = widget.data.copyWith(
      contextSelectionsData: newData.selectedCount > 0
          ? jsonEncode({
              'novelId': newData.novelId,
              'selectedItems': newData.selectedItems.values
                  .map((item) => {
                        'id': item.id,
                        'title': item.title,
                        'type': item.type.value,
                        'metadata': item.metadata,
                      })
                  .toList(),
            })
          : null,
      updatedAt: DateTime.now(),
    );
    // 🚀 标记：这是一次本地触发的上下文更新，下一次来自父组件的数据变更触发的上下文重建将被跳过
    _skipNextContextRebuild = true;
    widget.onDataChanged?.call(updatedData);
  }

  void _showEditDialog() {
    showSceneBeatEditDialog(
      context,
      data: widget.data,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      selectedUnifiedModel: _selectedUnifiedModel,
      onDataChanged: (updatedData) {
        // 本地同步
        setState(() {
          _currentLength = updatedData.selectedLength ?? _currentLength;
          if (_customLengthController.text != _currentLength) {
            _customLengthController.text = _currentLength;
          }

          // 同步指令
          final parsed = updatedData.parsedRequest;
          if (parsed?.instructions != null) {
            _quickInstructionsController.text = parsed!.instructions!;
          }

          // 同步模型
          if (updatedData.selectedUnifiedModelId != null &&
              updatedData.selectedUnifiedModelId != _selectedUnifiedModel?.id) {
            _loadSelectedModel();
          }
        });

        // 继续向上传递
        widget.onDataChanged?.call(updatedData);
      },
      onGenerate: widget.onGenerate,
    );
  }

  void _handleGenerate() async {
    AppLogger.d('OverlaySceneBeatPanel', '开始生成处理流程');

    if (_selectedUnifiedModel == null) {
      AppLogger.w('OverlaySceneBeatPanel', '未选择AI模型');
      TopToast.warning(context, '请先选择AI模型');
      return;
    }

    AppLogger.d('OverlaySceneBeatPanel', '已选择模型: ${_selectedUnifiedModel!.displayName}');

    // 构建AI请求
    final request = _buildAIRequest();
    if (request == null) {
      AppLogger.e('OverlaySceneBeatPanel', '构建AI请求失败');
      TopToast.error(context, '构建AI请求失败');
      return;
    }

    AppLogger.d('OverlaySceneBeatPanel', 'AI请求构建成功: ${request.requestType}');

    // 对于公共模型，先进行积分预估和确认
    if (_selectedUnifiedModel!.isPublic) {
      AppLogger.d('OverlaySceneBeatPanel',
          '检测到公共模型，启动积分预估确认流程: ${_selectedUnifiedModel!.displayName}');
      bool shouldProceed = await _showCreditEstimationAndConfirm(request);
      if (!shouldProceed) {
        AppLogger.d('OverlaySceneBeatPanel', '用户取消了积分预估确认，停止生成');
        return;
      }
      AppLogger.d('OverlaySceneBeatPanel', '用户确认了积分预估，继续生成');
    } else {
      AppLogger.d('OverlaySceneBeatPanel',
          '检测到私有模型，直接生成: ${_selectedUnifiedModel!.displayName}');
    }

    AppLogger.d('OverlaySceneBeatPanel', '开始调用onGenerate回调');

    // 启动流式生成
    widget.onGenerate?.call(request, _selectedUnifiedModel!);

    AppLogger.d('OverlaySceneBeatPanel', '更新状态为生成中');

    // 更新状态为生成中
    final updatedData = widget.data.updateStatus(SceneBeatStatus.generating);
    widget.onDataChanged?.call(updatedData);

    AppLogger.d('OverlaySceneBeatPanel', '生成流程已启动');
  }

  UniversalAIRequest? _buildAIRequest() {
    if (_selectedUnifiedModel == null) return null;

    final parsedRequest = widget.data.parsedRequest;
    final String? selectedText = _includeCurrentSceneAsInput
        ? _buildSelectedTextFromCurrentScene()
        : null;

    // 创建模型配置
    late UserAIModelConfigModel modelConfig;
    if (_selectedUnifiedModel!.isPublic) {
      final publicModel = (_selectedUnifiedModel as PublicAIModel).publicConfig;
      modelConfig = UserAIModelConfigModel.fromJson({
        'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
        'userId': AppConfig.userId ?? 'unknown',
        'alias': publicModel.displayName,
        'modelName': publicModel.modelId,
        'provider': publicModel.provider,
        'apiEndpoint': '',
        'isDefault': false,
        'isValidated': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } else {
      modelConfig = (_selectedUnifiedModel as PrivateAIModel).userConfig;
    }

    return UniversalAIRequest(
      requestType: AIRequestType.sceneBeat,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      chapterId: _getActiveChapterId(),
      sceneId: widget.sceneId,
      modelConfig: modelConfig,
      prompt: parsedRequest?.prompt ?? '续写故事。',
      selectedText: selectedText,
      instructions: _quickInstructionsController.text.trim(),
      contextSelections: widget.data.parsedContextSelections,
      enableSmartContext: widget.data.enableSmartContext,
      parameters: {
        'length': _currentLength,
        'temperature': widget.data.temperature,
        'topP': widget.data.topP,
        'maxTokens': 4000,
        'modelName': _selectedUnifiedModel!.modelId,
        'enableSmartContext': widget.data.enableSmartContext,
        'promptTemplateId': widget.data.selectedPromptTemplateId,
      },
      metadata: {
        'action': 'scene_beat',
        'source': 'overlay_scene_beat_panel',
        'featureType': 'SCENE_BEAT_GENERATION',
        'modelName': _selectedUnifiedModel!.modelId,
        'modelProvider': _selectedUnifiedModel!.provider,
        'modelConfigId': _selectedUnifiedModel!.id,
        'isPublicModel': _selectedUnifiedModel!.isPublic,
        if (_selectedUnifiedModel!.isPublic)
          'publicModelConfigId': (_selectedUnifiedModel as PublicAIModel).publicConfig.id,
        if (_selectedUnifiedModel!.isPublic)
          'publicModelId': (_selectedUnifiedModel as PublicAIModel).publicConfig.id,
      },
    );
  }

  String? _buildSelectedTextFromCurrentScene() {
    try {
      if (widget.novel == null || widget.sceneId.isEmpty) return null;
      for (final act in widget.novel!.acts) {
        for (final chapter in act.chapters) {
          for (final scene in chapter.scenes) {
            if (scene.id == widget.sceneId) {
              final String summary = (scene.summary.content).toString();
              final String plainContent = QuillHelper.deltaToText(scene.content);
              final buffer = StringBuffer();
              buffer.writeln('【当前场景摘要】');
              buffer.writeln(summary.trim().isEmpty ? '(无摘要)' : summary.trim());
              buffer.writeln();
              buffer.writeln('【当前场景内容】');
              buffer.writeln(plainContent.trim().isEmpty ? '(无内容)' : plainContent.trim());
              return buffer.toString().trim();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String? _getActiveChapterId() {
    try {
      // 通过 sceneId 反查章节：先在 novel 中找到含该 scene 的章节
      if (widget.novel == null || widget.sceneId.isEmpty) return null;
      for (final act in widget.novel!.acts) {
        for (final chapter in act.chapters) {
          if (chapter.scenes.any((s) => s.id == widget.sceneId)) {
            return chapter.id;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _showCreditEstimationAndConfirm(UniversalAIRequest request) async {
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return BlocProvider.value(
                value: context.read<UniversalAIBloc>(),
                child: _CreditEstimationDialog(
                  modelName: _selectedUnifiedModel!.displayName,
                  request: request,
                  onConfirm: () => Navigator.of(dialogContext).pop(true),
                  onCancel: () => Navigator.of(dialogContext).pop(false),
                ),
              );
            },
          ) ??
          false;
    } catch (e) {
      AppLogger.e('OverlaySceneBeatPanel', '积分预估失败', e);
      TopToast.error(context, '积分预估失败: $e');
      return false;
    }
  }

  bool _shouldRebuildContextData(OverlaySceneBeatPanel oldWidget) {
    // 🚀 修复：更精确地判断上下文数据是否需要重建
    // 只有当基础数据（小说、设定等）或上下文选择的序列化数据真正变化时才重建
    if (widget.novel != oldWidget.novel ||
        widget.settings != oldWidget.settings ||
        widget.settingGroups != oldWidget.settingGroups ||
        widget.snippets != oldWidget.snippets) {
      AppLogger.d('OverlaySceneBeatPanel', '🔄 基础数据变化，需要重建上下文');
      return true;
    }
    
    // 🚀 比较序列化的上下文选择数据，而不是解析后的对象
    final oldContextData = oldWidget.data.contextSelectionsData;
    final newContextData = widget.data.contextSelectionsData;
    
    if (oldContextData != newContextData) {
      if (_skipNextContextRebuild) {
        // 🚀 跳过一次：这是由本地 setState + onDataChanged 触发的回流
        _skipNextContextRebuild = false;
        AppLogger.d('OverlaySceneBeatPanel', '⏭️ 跳过一次上下文重建（本地更新回流）');
        return false;
      }
      AppLogger.d('OverlaySceneBeatPanel', '🔄 上下文选择数据变化，需要重建上下文');
      return true;
    }
    
    // 🚀 所有关键数据都没有变化，无需重建
    return false;
  }

  ContextSelectionData _createContextData() {
    // 构建基础数据，优先应用已保存的选择
    ContextSelectionData data = ContextSelectionHelper.initializeContextData(
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      initialSelections: widget.data.parsedContextSelections,
    );
    return data;
  }

  /// 当应用了默认上下文时，持久化到数据模型，确保请求包含默认上下文
  void _persistDefaultContextIfNeeded() {
    final bool hasSaved = (widget.data.parsedContextSelections?.selectedCount ?? 0) > 0;
    if (!hasSaved && _contextData.selectedCount > 0) {
      // 使用下一帧提交，避免initState阶段的同步更新引发抖动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateContextData(_contextData);
      });
    }
  }
}

/// 积分预估确认对话框
class _CreditEstimationDialog extends StatefulWidget {
  final String modelName;
  final UniversalAIRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _CreditEstimationDialog({
    required this.modelName,
    required this.request,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_CreditEstimationDialog> createState() => _CreditEstimationDialogState();
}

class _CreditEstimationDialogState extends State<_CreditEstimationDialog> {
  CostEstimationResponse? _costEstimation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _estimateCost();
  }

  Future<void> _estimateCost() async {
    try {
      final universalAIBloc = context.read<UniversalAIBloc>();
      universalAIBloc.add(EstimateCostEvent(widget.request));
    } catch (e) {
      setState(() {
        _errorMessage = '预估失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UniversalAIBloc, UniversalAIState>(
      listener: (context, state) {
        if (state is UniversalAICostEstimationSuccess) {
          setState(() {
            _costEstimation = state.costEstimation;
            _errorMessage = null;
          });
        } else if (state is UniversalAIError) {
          setState(() {
            _errorMessage = state.message;
            _costEstimation = null;
          });
        }
      },
      child: BlocBuilder<UniversalAIBloc, UniversalAIState>(
        builder: (context, state) {
          final isLoading = state is UniversalAILoading;

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('积分消耗预估'),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模型: ${widget.modelName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (isLoading) ...[
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('正在估算积分消耗...'),
                      ],
                    ),
                  ] else if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_costEstimation != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '预估消耗积分:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${_costEstimation!.estimatedCost}',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (_costEstimation!.estimatedInputTokens != null ||
                              _costEstimation!.estimatedOutputTokens != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Token预估:',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                                Text(
                                  '输入: ${_costEstimation!.estimatedInputTokens ?? 0}, 输出: ${_costEstimation!.estimatedOutputTokens ?? 0}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '实际消耗可能因内容长度和模型响应而有所不同',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    '确认要继续生成场景节拍吗？',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : widget.onCancel,
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: isLoading || _errorMessage != null || _costEstimation == null
                    ? null
                    : widget.onConfirm,
                child: const Text('确认生成'),
              ),
            ],
          );
        },
      ),
    );
  }
} 