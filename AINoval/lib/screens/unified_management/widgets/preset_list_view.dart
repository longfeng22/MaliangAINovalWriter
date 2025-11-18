import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/blocs/preset/preset_bloc.dart';
import 'package:ainoval/blocs/preset/preset_state.dart';
import 'package:ainoval/blocs/preset/preset_event.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/loading_indicator.dart';
import 'package:ainoval/widgets/common/management_list_widgets.dart';

/// 预设列表视图
/// 按AI功能类型分组显示预设，支持系统预设和用户预设
/// 🚀 重构：与提示词页面的分组设计对齐
class PresetListView extends StatefulWidget {
  const PresetListView({
    super.key,
    required this.onPresetSelected,
  });

  final Function(String presetId) onPresetSelected;

  @override
  State<PresetListView> createState() => _PresetListViewState();
}

class _PresetListViewState extends State<PresetListView> {
  static const String _tag = 'PresetListView';
  final TextEditingController _searchController = TextEditingController();
  
  // 展开状态 - 🚀 修改：使用AIFeatureType作为key
  final Set<AIFeatureType> _expandedGroups = {};
  
  // 🚀 添加缓存以避免重复转换
  Map<String, List<AIPromptPreset>>? _lastStringGrouped;
  Map<AIFeatureType, List<AIPromptPreset>>? _cachedFeatureTypeGrouped;
  
  // 🚀 优化构建：避免不必要的重建（已通过缓存实现，无需此字段）

  @override
  void initState() {
    super.initState();
    // 预设数据已在用户登录时通过聚合接口预加载，无需重复加载
    // 直接使用BLoC中已有的缓存数据
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          right: BorderSide(
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部标题栏（共享）
          const ManagementListTopBar(
            title: '预设管理',
            subtitle: 'AI 预设模板库',
            icon: Icons.settings_suggest,
          ),

          // 搜索框
          _buildSearchBar(),

          // 分隔线
          Container(
            height: 1,
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
          ),

          // 预设列表
          Expanded(
            child: BlocBuilder<PresetBloc, PresetState>(
              builder: (context, state) => _buildContent(state),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部标题栏由共享组件 ManagementListTopBar 提供

  /// 构建搜索框
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: _searchController,
        decoration: WebTheme.getBorderedInputDecoration(
          hintText: '搜索预设...',
          context: context,
        ).copyWith(
          filled: true,
          fillColor: WebTheme.getSurfaceColor(context),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 18,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    context.read<PresetBloc>().add(const ClearPresetSearch());
                    setState(() {});
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: WebTheme.bodyMedium.copyWith(color: WebTheme.getTextColor(context)),
        onChanged: (value) {
          setState(() {});
          if (value.trim().isEmpty) {
            context.read<PresetBloc>().add(const ClearPresetSearch());
          } else {
            context.read<PresetBloc>().add(SearchPresets(query: value.trim()));
          }
        },
      ),
    );
  }

  /// 构建内容
  Widget _buildContent(PresetState state) {
    if (state.isLoading && state.groupedPresets.isEmpty && state.searchResults.isEmpty) {
      return _buildLoadingView();
    } else if (state.hasError) {
      return _buildErrorView(state.errorMessage!);
    } else if (state.isSearching) {
      return _buildSearchResults(state.searchResults);
    } else if (state.groupedPresets.isEmpty) {
      return _buildEmptyView();
    } else {
      // 🚀 修改：转换分组预设数据，按AIFeatureType分组
      final groupedByFeatureType = _convertToFeatureTypeGrouping(state.groupedPresets);
      return _buildPresetList(groupedByFeatureType, state);
    }
  }

  /// 构建搜索结果列表（与条目样式保持一致）
  Widget _buildSearchResults(List<AIPromptPreset> results) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          '没有找到匹配的预设',
          style: WebTheme.bodyMedium.copyWith(
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
      );
    }

    final selectedId = context.read<PresetBloc>().state.selectedPreset?.presetId;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final preset = results[index];
        final isSelected = preset.presetId == selectedId;
        return _buildPresetItem(preset, isSelected: isSelected);
      },
    );
  }

  /// 🚀 优化：转换分组预设数据，智能增量更新
  Map<AIFeatureType, List<AIPromptPreset>> _convertToFeatureTypeGrouping(
    Map<String, List<AIPromptPreset>> stringGrouped
  ) {
    // 🚀 检查缓存：如果数据没有变化，直接返回缓存结果
    if (_lastStringGrouped != null && 
        _cachedFeatureTypeGrouped != null &&
        _isGroupedDataEqual(_lastStringGrouped!, stringGrouped)) {
      return _cachedFeatureTypeGrouped!;
    }
    
    // 🚀 检查是否为增量更新（只新增了预设）
    if (_lastStringGrouped != null && 
        _cachedFeatureTypeGrouped != null &&
        _isIncrementalUpdate(_lastStringGrouped!, stringGrouped)) {
      
      AppLogger.i(_tag, '🚀 检测到增量更新，执行平滑更新');
      return _performIncrementalUpdate(_lastStringGrouped!, stringGrouped);
    }
    
    AppLogger.i(_tag, '🔧 完整转换分组预设数据，原始分组数: ${stringGrouped.length}');
    final Map<AIFeatureType, List<AIPromptPreset>> featureTypeGrouped = {};
    
    for (final entry in stringGrouped.entries) {
      try {
        // 🚀 首先尝试解析标准格式
        final featureType = AIFeatureTypeHelper.fromApiString(entry.key.toUpperCase());
        featureTypeGrouped[featureType] = entry.value;
      } catch (e) {
        // 🚀 兼容性处理：如果标准格式解析失败，尝试简化格式映射
        final mappedFeatureType = _mapLegacyFeatureType(entry.key);
        if (mappedFeatureType != null) {
          AppLogger.w(_tag, '兼容性映射: ${entry.key} -> ${mappedFeatureType.name}');
          featureTypeGrouped[mappedFeatureType] = entry.value;
        } else {
          AppLogger.w(_tag, '无法解析功能类型: ${entry.key}', e);
          // 对于无法解析的功能类型，跳过
        }
      }
    }
    
    // 🚀 更新缓存（深拷贝列表以避免引用共享）
    _lastStringGrouped = stringGrouped.map((k, v) => MapEntry(k, List<AIPromptPreset>.from(v)));
    _cachedFeatureTypeGrouped = featureTypeGrouped.map((k, v) => MapEntry(k, List<AIPromptPreset>.from(v)));
    
    AppLogger.i(_tag, '✅ 转换完成，最终分组数: ${featureTypeGrouped.length}');
    return featureTypeGrouped;
  }

  /// 🚀 新增：检查分组数据是否相等
  bool _isGroupedDataEqual(
    Map<String, List<AIPromptPreset>> map1,
    Map<String, List<AIPromptPreset>> map2,
  ) {
    if (map1.length != map2.length) return false;
    
    for (final entry in map1.entries) {
      final key = entry.key;
      final list1 = entry.value;
      final list2 = map2[key];
      
      if (list2 == null || list1.length != list2.length) return false;
      
      // 简化比较：只比较预设ID和长度
      for (int i = 0; i < list1.length; i++) {
        if (list1[i].presetId != list2[i].presetId) return false;
      }
    }
    
    return true;
  }

  /// 🚀 新增：检查是否为增量更新（只新增或删除了少量预设）
  bool _isIncrementalUpdate(
    Map<String, List<AIPromptPreset>> oldMap,
    Map<String, List<AIPromptPreset>> newMap,
  ) {
    // 如果分组数量发生变化，可能是新增了新的功能类型，仍可以增量处理
    if ((newMap.length - oldMap.length).abs() > 1) return false;
    
    int totalChanges = 0;
    
    // 检查每个分组的变化
    final allKeys = {...oldMap.keys, ...newMap.keys};
    for (final key in allKeys) {
      final oldList = oldMap[key] ?? [];
      final newList = newMap[key] ?? [];
      
      final lengthDiff = (newList.length - oldList.length).abs();
      totalChanges += lengthDiff;
      
      // 如果单个分组变化太大，不适合增量更新
      if (lengthDiff > 3) return false;
    }
    
    // 总变化数量不超过5个认为是增量更新
    return totalChanges <= 5;
  }

  /// 🚀 新增：执行增量更新
  Map<AIFeatureType, List<AIPromptPreset>> _performIncrementalUpdate(
    Map<String, List<AIPromptPreset>> oldStringGrouped,
    Map<String, List<AIPromptPreset>> newStringGrouped,
  ) {
    final result = Map<AIFeatureType, List<AIPromptPreset>>.from(_cachedFeatureTypeGrouped!);
    
    // 检查每个分组的变化
    for (final entry in newStringGrouped.entries) {
      final key = entry.key;
      final newList = entry.value;
      final oldList = oldStringGrouped[key] ?? [];
      
      // 如果这个分组有变化，更新对应的FeatureType分组
      if (newList.length != oldList.length || 
          !_arePresetListsEqual(oldList, newList)) {
        
        try {
          final featureType = AIFeatureTypeHelper.fromApiString(key.toUpperCase());
          result[featureType] = newList;
          AppLogger.i(_tag, '📋 增量更新分组: $key (${oldList.length} -> ${newList.length})');
        } catch (e) {
          final mappedFeatureType = _mapLegacyFeatureType(key);
          if (mappedFeatureType != null) {
            result[mappedFeatureType] = newList;
            AppLogger.i(_tag, '📋 增量更新分组(映射): $key -> ${mappedFeatureType.name}');
          }
        }
      }
    }
    
    // 检查是否有分组被删除
    for (final oldKey in oldStringGrouped.keys) {
      if (!newStringGrouped.containsKey(oldKey)) {
        try {
          final featureType = AIFeatureTypeHelper.fromApiString(oldKey.toUpperCase());
          result.remove(featureType);
          AppLogger.i(_tag, '📋 移除分组: $oldKey');
        } catch (e) {
          final mappedFeatureType = _mapLegacyFeatureType(oldKey);
          if (mappedFeatureType != null) {
            result.remove(mappedFeatureType);
            AppLogger.i(_tag, '📋 移除分组(映射): $oldKey');
          }
        }
      }
    }
    
    // 更新缓存（深拷贝列表以避免引用共享）
    _lastStringGrouped = newStringGrouped.map((k, v) => MapEntry(k, List<AIPromptPreset>.from(v)));
    _cachedFeatureTypeGrouped = result.map((k, v) => MapEntry(k, List<AIPromptPreset>.from(v)));
    
    return result;
  }

  /// 🚀 新增：检查两个预设列表是否相等
  bool _arePresetListsEqual(List<AIPromptPreset> list1, List<AIPromptPreset> list2) {
    if (list1.length != list2.length) return false;
    
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].presetId != list2[i].presetId) return false;
    }
    
    return true;
  }

  /// 🚀 新增：映射简化格式的功能类型到标准枚举
  AIFeatureType? _mapLegacyFeatureType(String legacyType) {
    switch (legacyType.toUpperCase()) {
      case 'TEXT_EXPANSION':
        return AIFeatureType.textExpansion;
      case 'TEXT_SUMMARY':
        return AIFeatureType.textSummary;
      case 'TEXT_REFACTOR':
        return AIFeatureType.textRefactor;
      case 'AI_CHAT':
        return AIFeatureType.aiChat;
      case 'NOVEL_GENERATION':
        return AIFeatureType.novelGeneration;
      case 'SCENE_TO_SUMMARY':
        return AIFeatureType.sceneToSummary;
      default:
        return null; // 未知的简化类型
    }
  }

  /// 构建加载视图
  Widget _buildLoadingView() {
    return const Center(
      child: LoadingIndicator(message: '加载预设中...'),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: WebTheme.headlineSmall.copyWith(
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: WebTheme.bodyMedium.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // 🚀 使用新的一次性加载接口重试
              context.read<PresetBloc>().add(const LoadAllPresetData());
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建空视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_suggest_outlined,
            size: 64,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无预设',
            style: WebTheme.headlineSmall.copyWith(
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '您还没有创建任何预设',
            style: WebTheme.bodyMedium.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 🚀 修改：构建预设列表，使用AIFeatureType分组
  Widget _buildPresetList(Map<AIFeatureType, List<AIPromptPreset>> groupedPresets, PresetState state) {
    // 默认展开第一个组
    if (_expandedGroups.isEmpty && groupedPresets.isNotEmpty) {
      _expandedGroups.add(groupedPresets.keys.first);
    }

    final sortedFeatureTypes = _getSortedFeatureTypes(groupedPresets.keys.toList());

    return ListView.builder(
      key: const ValueKey('preset_list'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedFeatureTypes.length,
      itemBuilder: (context, index) {
        final featureType = sortedFeatureTypes[index];
        final presets = groupedPresets[featureType]!;
        final isExpanded = _expandedGroups.contains(featureType);

        return _buildFeatureTypeSection(featureType, presets, state, isExpanded);
      },
    );
  }

  /// 🚀 新增：获取排序后的功能类型列表
  List<AIFeatureType> _getSortedFeatureTypes(List<AIFeatureType> featureTypes) {
    // 定义功能类型的优先级顺序，与提示词页面保持一致
    const order = [
      AIFeatureType.textExpansion,
      AIFeatureType.textRefactor,
      AIFeatureType.textSummary,
      AIFeatureType.aiChat,
      AIFeatureType.sceneToSummary,
      AIFeatureType.summaryToScene,
      AIFeatureType.novelGeneration,
      AIFeatureType.professionalFictionContinuation,
    ];
    
    final sorted = <AIFeatureType>[];
    
    // 首先添加预定义顺序中存在的类型
    for (final type in order) {
      if (featureTypes.contains(type)) {
        sorted.add(type);
      }
    }
    
    // 然后添加其他未在预定义顺序中的类型
    for (final type in featureTypes) {
      if (!sorted.contains(type)) {
        sorted.add(type);
      }
    }
    
    return sorted;
  }

  /// 对齐提示词列表的分组样式（ExpansionTile）
  Widget _buildFeatureTypeSection(
    AIFeatureType featureType,
    List<AIPromptPreset> presets,
    PresetState state,
    bool isExpanded,
  ) {
    final isDark = WebTheme.isDarkMode(context);
    final color = _getFeatureTypeColor(featureType);

    return ExpansionTile(
      initiallyExpanded: isExpanded,
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: EdgeInsets.zero,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          _getFeatureTypeIcon(featureType),
          size: 14,
          color: color,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              featureType.displayName,
              style: WebTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 数量徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${presets.length}',
              style: WebTheme.labelSmall.copyWith(
                color: WebTheme.getSecondaryTextColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 新建按钮
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _createNewPreset(featureType),
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 展开/折叠图标
          Icon(
            Icons.expand_more,
            size: 20,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ],
      ),
      children: presets
          .map((preset) => _buildPresetItem(
                preset,
                isSelected: state.selectedPreset?.presetId == preset.presetId,
              ))
          .toList(),
      onExpansionChanged: (expanded) {
        setState(() {
          if (expanded) {
            _expandedGroups.add(featureType);
          } else {
            _expandedGroups.remove(featureType);
          }
        });
      },
    );
  }

  /// 构建预设项（使用共享列表项）
  Widget _buildPresetItem(AIPromptPreset preset, {required bool isSelected}) {
    final iconColor = preset.isSystem ? const Color(0xFF1565C0) : const Color(0xFF7B1FA2);
    return ManagementListItem(
      isSelected: isSelected,
      onTap: () {
        widget.onPresetSelected(preset.presetId);
        context.read<PresetBloc>().add(SelectPreset(presetId: preset.presetId));
      },
      leftIcon: preset.isSystem ? Icons.settings : Icons.person,
      leftIconColor: iconColor,
      leftIconBgColor: iconColor.withOpacity(0.1),
      title: preset.presetName ?? '未命名预设',
      subtitle: (preset.presetDescription != null && preset.presetDescription!.isNotEmpty)
          ? preset.presetDescription!
          : null,
      tags: preset.tags,
      trailing: ManagementTypeChip(type: preset.isSystem ? 'System' : 'Custom'),
      statusBadges: const [],
      showQuickStar: preset.showInQuickAccess,
    );
  }

  // 标签与类型Chip由共享组件提供

  /// 🚀 与提示词页面保持一致：获取功能类型图标
  IconData _getFeatureTypeIcon(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return Icons.summarize;
      case AIFeatureType.summaryToScene:
        return Icons.expand_more;
      case AIFeatureType.textExpansion:
        return Icons.unfold_more;
      case AIFeatureType.textRefactor:
        return Icons.edit;
      case AIFeatureType.textSummary:
        return Icons.notes;
      case AIFeatureType.aiChat:
        return Icons.chat;
      case AIFeatureType.novelGeneration:
        return Icons.create;
      case AIFeatureType.novelCompose:
        return Icons.dashboard_customize;
      case AIFeatureType.professionalFictionContinuation:
        return Icons.auto_stories;
      case AIFeatureType.sceneBeatGeneration:
        return Icons.timeline;
      case AIFeatureType.settingTreeGeneration:
        return Icons.account_tree;
      case AIFeatureType.settingGenerationTool:
        return Icons.build;
      case AIFeatureType.storyPlotContinuation:
        return Icons.auto_fix_high;
      case AIFeatureType.knowledgeExtractionSetting:
        return Icons.import_contacts;
      case AIFeatureType.knowledgeExtractionOutline:
        return Icons.list_alt;
    }
  }

  /// 🚀 与提示词页面保持一致：获取功能类型颜色
  Color _getFeatureTypeColor(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return const Color(0xFF1976D2); // 蓝色
      case AIFeatureType.summaryToScene:
        return const Color(0xFF388E3C); // 绿色
      case AIFeatureType.textExpansion:
        return const Color(0xFF7B1FA2); // 紫色
      case AIFeatureType.textRefactor:
        return const Color(0xFFE64A19); // 深橙色
      case AIFeatureType.textSummary:
        return const Color(0xFF5D4037); // 棕色
      case AIFeatureType.aiChat:
        return const Color(0xFF0288D1); // 青色
      case AIFeatureType.novelGeneration:
        return const Color(0xFFD32F2F); // 红色
      case AIFeatureType.novelCompose:
        return const Color(0xFFD32F2F);
      case AIFeatureType.professionalFictionContinuation:
        return const Color(0xFF303F9F); // 靛蓝色
      case AIFeatureType.sceneBeatGeneration:
        return const Color(0xFF795548); // 棕色
      case AIFeatureType.settingTreeGeneration:
        return const Color(0xFF689F38); // 浅绿色
      case AIFeatureType.settingGenerationTool:
        return const Color(0xFF757575); // 灰色
      case AIFeatureType.storyPlotContinuation:
        return const Color(0xFF8E24AA); // 紫色系
      case AIFeatureType.knowledgeExtractionSetting:
        return const Color(0xFFFF6F00); // 橙色
      case AIFeatureType.knowledgeExtractionOutline:
        return const Color(0xFFF57C00); // 深橙
    }
  }

  /// 创建新预设
  void _createNewPreset(AIFeatureType featureType) {
    AppLogger.i(_tag, '创建新预设: ${featureType.displayName}');
    // TODO: 实现创建新预设的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('创建${featureType.displayName}预设')),
    );
  }
}