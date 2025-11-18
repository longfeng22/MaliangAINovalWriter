import 'dart:convert';

import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/utils/logger.dart';

/// 上下文选择助手类
/// 
/// 提供统一的上下文选择管理方法，避免在不同组件中重复实现相同逻辑
class ContextSelectionHelper {
  
  /// 初始化上下文选择数据
  /// 
  /// 根据提供的小说、设定、片段数据构建完整的上下文选择结构
  static ContextSelectionData initializeContextData({
    Novel? novel,
    List<NovelSettingItem>? settings,
    List<SettingGroup>? settingGroups,
    List<NovelSnippet>? snippets,
    ContextSelectionData? initialSelections,
  }) {
    //AppLogger.d('ContextSelectionHelper', '🔧 初始化上下文选择数据');
    
    ContextSelectionData contextData;
    
    if (novel != null) {
      // 🚀 使用小说数据构建完整的上下文选择结构
      contextData = ContextSelectionDataBuilder.fromNovelWithContext(
        novel,
        settings: settings ?? [],
        settingGroups: settingGroups ?? [],
        snippets: snippets ?? [],
      );
      //AppLogger.d('ContextSelectionHelper', '✅ 从小说构建上下文数据成功: ${contextData.availableItems.length}个可选项');
    } else {
      // 🚀 创建演示数据作为回退
      contextData = _createFallbackContextData();
      //AppLogger.d('ContextSelectionHelper', '✅ 创建回退上下文数据: ${contextData.availableItems.length}个可选项');
    }
    
    // 🚀 如果有初始选择，应用到构建的数据中
    if (initialSelections != null && initialSelections.selectedCount > 0) {
      contextData = contextData.applyPresetSelections(initialSelections);
      //AppLogger.d('ContextSelectionHelper', '✅ 应用初始选择: ${contextData.selectedCount}个已选项');
    }
    
    // 🚀 默认预选三项：最近5章摘要、最近5章内容、全部设定（如果存在）
    try {
      if (novel != null && contextData.selectedCount == 0) {
        final String nid = novel.id;
        final List<String> defaultIds = <String>[
          'recent_chapters_summary_' + nid,
          'recent_chapters_content_' + nid,
          'settings_' + nid,
        ];
        ContextSelectionData preselected = contextData;
        for (final id in defaultIds) {
          if (preselected.flatItems.containsKey(id)) {
            preselected = preselected.selectItem(id);
          }
        }
        contextData = preselected;
      }
    } catch (_) {}
    
    return contextData;
  }
  
  /// 处理上下文选择变化
  /// 
  /// 这是核心方法，用于正确处理级联菜单的选择变化
  /// [currentData] 当前的上下文选择数据
  /// [newData] 从下拉菜单组件返回的新选择数据
  /// [isAddOperation] 是否为添加操作（true=添加，false=删除）
  static ContextSelectionData handleSelectionChanged(
    ContextSelectionData currentData,
    ContextSelectionData newData, {
    bool isAddOperation = true,
  }) {
    //AppLogger.d('ContextSelectionHelper', '🔄 处理上下文选择变化');
    //AppLogger.d('ContextSelectionHelper', '当前选择数: ${currentData.selectedCount}');
    //AppLogger.d('ContextSelectionHelper', '新数据选择数: ${newData.selectedCount}');
    //AppLogger.d('ContextSelectionHelper', '操作类型: ${isAddOperation ? "添加" : "删除"}');
    
    // 🚀 关键修复：直接使用新的选择数据，而不是合并
    // 下拉菜单组件已经处理了选择/取消选择的逻辑，我们只需要接受结果
    
    // 确保新数据具有完整的菜单结构
    if (newData.availableItems.length < currentData.availableItems.length) {
      // 如果新数据的菜单结构不完整，保持当前的菜单结构，只更新选择状态
      //AppLogger.d('ContextSelectionHelper', '🔧 修复不完整的菜单结构');
      
      // 重建具有完整结构的数据
      final updatedData = currentData.copyWith(
        selectedItems: {},
        flatItems: currentData.flatItems.map(
          (key, value) => MapEntry(key, value.copyWith(selectionState: SelectionState.unselected)),
        ),
      );
      
      // 应用新的选择
      ContextSelectionData result = updatedData;
      for (final selectedItem in newData.selectedItems.values) {
        if (result.flatItems.containsKey(selectedItem.id)) {
          result = result.selectItem(selectedItem.id);
        }
      }
      
      //AppLogger.d('ContextSelectionHelper', '✅ 选择处理完成: ${result.selectedCount}个已选项');
      return result;
    } else {
      // 菜单结构完整，直接使用新数据
      //AppLogger.d('ContextSelectionHelper', '✅ 直接使用新选择数据: ${newData.selectedCount}个已选项');
      return newData;
    }
  }
  
  /// 从保存的上下文选择字符串恢复选择状态
  /// 
  /// [baseData] 基础的完整菜单结构数据
  /// [savedContextSelectionsData] 保存的上下文选择JSON字符串
  static ContextSelectionData restoreSelectionsFromSaved(
    ContextSelectionData baseData,
    String? savedContextSelectionsData,
  ) {
    if (savedContextSelectionsData == null || savedContextSelectionsData.isEmpty) {
      //AppLogger.d('ContextSelectionHelper', '📭 没有保存的上下文选择数据');
      return baseData;
    }
    
    try {
      // 🚀 解析保存的选择数据
      final savedSelections = _parseSavedContextSelections(
        savedContextSelectionsData,
        baseData.novelId,
      );
      
      if (savedSelections.selectedCount > 0) {
        // 应用保存的选择到基础数据
        final restoredData = baseData.applyPresetSelections(savedSelections);
        //AppLogger.d('ContextSelectionHelper', '✅ 恢复上下文选择: ${restoredData.selectedCount}个已选项');
        return restoredData;
      }
    } catch (e) {
      AppLogger.e('ContextSelectionHelper', '恢复上下文选择失败', e);
    }
    
    return baseData;
  }
  
  /// 解析保存的上下文选择数据
  static ContextSelectionData _parseSavedContextSelections(String savedData, String novelId) {
    try {
      // 🚀 解析JSON数据
      final jsonData = jsonDecode(savedData) as Map<String, dynamic>;
      
      // 检查是否有selectedItems字段
      if (!jsonData.containsKey('selectedItems')) {
        AppLogger.w('ContextSelectionHelper', '保存的数据中没有selectedItems字段');
        return ContextSelectionData(novelId: novelId, availableItems: [], flatItems: {});
      }
      
      final contextList = jsonData['selectedItems'] as List<dynamic>;
      //AppLogger.d('ContextSelectionHelper', '解析保存的上下文选择: ${contextList.length}个项目');
      
      // 将已选择的项目转换为ContextSelectionItem
      final selectedItems = <String, ContextSelectionItem>{};
      final availableItems = <ContextSelectionItem>[];
      final flatItems = <String, ContextSelectionItem>{};
      
      for (var itemData in contextList) {
        final item = ContextSelectionItem(
          id: itemData['id'] ?? '',
          title: itemData['title'] ?? '',
          type: ContextSelectionType.values.firstWhere(
            (type) => type.displayName == itemData['type'],
            orElse: () => ContextSelectionType.fullNovelText,
          ),
          metadata: Map<String, dynamic>.from(itemData['metadata'] ?? {}),
          parentId: itemData['parentId'],
          selectionState: SelectionState.fullySelected, // 标记为已选择
        );
        
        selectedItems[item.id] = item;
        availableItems.add(item);
        flatItems[item.id] = item;
        
        //AppLogger.d('ContextSelectionHelper', '  ✅ ${item.type.displayName}:${item.id} (${item.title})');
      }
      
      return ContextSelectionData(
        novelId: novelId,
        selectedItems: selectedItems,
        availableItems: availableItems,
        flatItems: flatItems,
      );
    } catch (e) {
      AppLogger.e('ContextSelectionHelper', '解析保存的上下文选择数据失败', e);
      return ContextSelectionData(novelId: novelId, availableItems: [], flatItems: {});
    }
  }
  
  /// 获取用于保存的上下文选择字符串
  /// 
  /// [contextData] 当前的上下文选择数据
  static String? getSelectionsForSave(ContextSelectionData? contextData) {
    if (contextData == null || contextData.selectedCount == 0) {
      return null;
    }
    
    try {
      return contextData.toSaveString();
    } catch (e) {
      AppLogger.e('ContextSelectionHelper', '序列化上下文选择失败', e);
      return null;
    }
  }
  
  /// 清除所有选择
  /// 
  /// [currentData] 当前的上下文选择数据
  static ContextSelectionData clearAllSelections(ContextSelectionData currentData) {
    //AppLogger.d('ContextSelectionHelper', '🧹 清除所有上下文选择');
    
    return currentData.copyWith(
      selectedItems: {},
      flatItems: currentData.flatItems.map(
        (key, value) => MapEntry(key, value.copyWith(selectionState: SelectionState.unselected)),
      ),
    );
  }
  
  /// 创建回退的上下文选择数据（用于没有小说数据的情况）
  static ContextSelectionData _createFallbackContextData() {
    final demoItems = [
      ContextSelectionItem(
        id: 'demo_full_novel',
        title: 'Full Novel Text',
        type: ContextSelectionType.fullNovelText,
        subtitle: '包含所有小说文本，这将产生费用',
        metadata: {'wordCount': 0},
      ),
      ContextSelectionItem(
        id: 'demo_full_outline',
        title: 'Full Outline',
        type: ContextSelectionType.fullOutline,
        subtitle: '包含所有卷、章节和场景的完整大纲',
        metadata: {'actCount': 0, 'chapterCount': 0, 'sceneCount': 0},
      ),
    ];
    
    final flatItems = <String, ContextSelectionItem>{};
    for (final item in demoItems) {
      flatItems[item.id] = item;
    }
    
    return ContextSelectionData(
      novelId: 'demo_novel',
      availableItems: demoItems,
      flatItems: flatItems,
    );
  }
  
  /// 验证上下文选择数据的完整性
  /// 
  /// [contextData] 要验证的上下文选择数据
  static bool validateContextData(ContextSelectionData? contextData) {
    if (contextData == null) {
      AppLogger.w('ContextSelectionHelper', '❌ 上下文数据为null');
      return false;
    }
    
    if (contextData.availableItems.isEmpty) {
      AppLogger.w('ContextSelectionHelper', '❌ 上下文数据无可用项目');
      return false;
    }
    
    if (contextData.flatItems.isEmpty) {
      AppLogger.w('ContextSelectionHelper', '❌ 上下文数据扁平化映射为空');
      return false;
    }
    
    //AppLogger.d('ContextSelectionHelper', '✅ 上下文数据验证通过');
    return true;
  }
  
  /// 获取上下文选择的统计信息
  /// 
  /// [contextData] 上下文选择数据
  static Map<String, dynamic> getSelectionStats(ContextSelectionData? contextData) {
    if (contextData == null) {
      return {'totalItems': 0, 'selectedItems': 0, 'selectionTypes': []};
    }
    
    final selectedTypes = contextData.selectedItems.values
        .map((item) => item.type.displayName)
        .toSet()
        .toList();
    
    return {
      'totalItems': contextData.availableItems.length,
      'selectedItems': contextData.selectedCount,
      'selectionTypes': selectedTypes,
      'novelId': contextData.novelId,
    };
  }
}

/// 上下文选择数据扩展方法
extension ContextSelectionDataExt on ContextSelectionData {
  
  /// 转换为保存字符串
  String toSaveString() {
    if (selectedCount == 0) return '';
    
    final saveData = {
      'novelId': novelId,
             'selectedItems': selectedItems.values.map((item) => {
         'id': item.id,
         'title': item.title,
         'type': item.type.displayName,
         'metadata': item.metadata,
       }).toList(),
    };
    
    return saveData.toString(); // 简化的序列化，可以根据需要使用 jsonEncode
  }
  

} 