import 'package:ainoval/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull

/// 编辑器布局管理器
/// 负责管理编辑器的布局和尺寸
class EditorLayoutManager extends ChangeNotifier {
  EditorLayoutManager() {
    _loadSavedDimensions();
  }

  // 对象dispose状态跟踪
  bool _isDisposed = false;

  // 侧边栏可见性状态
  bool isEditorSidebarVisible = true;
  bool isAIChatSidebarVisible = false;
  bool isSettingsPanelVisible = false;
  bool isNovelSettingsVisible = false;
  bool isAISummaryPanelVisible = false;
  bool isAISceneGenerationPanelVisible = false;
  bool isAIContinueWritingPanelVisible = false;
  bool isAISettingGenerationPanelVisible = false;
  bool isPromptViewVisible = false;
  
  // 多面板显示时的顺序和位置
  final List<String> visiblePanels = [];
  static const String aiChatPanel = 'aiChatPanel';
  static const String aiSummaryPanel = 'aiSummaryPanel';
  static const String aiScenePanel = 'aiScenePanel';
  static const String aiContinueWritingPanel = 'aiContinueWritingPanel';
  static const String aiSettingGenerationPanel = 'aiSettingGenerationPanel';

  // 侧边栏宽度
  double editorSidebarWidth = 400;
  double chatSidebarWidth = 380;
  
  // 多面板模式下的单个面板宽度（优化1080p显示）
  Map<String, double> panelWidths = {
    aiChatPanel: 480, // 聊天侧边栏减小默认宽度以适配1080p
    aiSummaryPanel: 320, // 其他侧边栏减小宽度，确保1080p下按钮可见
    aiScenePanel: 320,
    aiContinueWritingPanel: 320,
    aiSettingGenerationPanel: 320,
  };

  // 侧边栏宽度限制
  static const double minEditorSidebarWidth = 220;
  static const double maxEditorSidebarWidth = 400;
  static const double minChatSidebarWidth = 280;
  static const double maxChatSidebarWidth = 500;
  static const double minPanelWidth = 280;
  static const double maxPanelWidth = 600; // 提升二分之一：400 * 1.5 = 600

  // 持久化键
  static const String editorSidebarWidthPrefKey = 'editor_sidebar_width';
  static const String chatSidebarWidthPrefKey = 'chat_sidebar_width';
  static const String panelWidthsPrefKey = 'multi_panel_widths';
  static const String visiblePanelsPrefKey = 'visible_panels';
  static const String lastHiddenPanelsPrefKey = 'last_hidden_panels';

  // 保存隐藏前的面板配置
  List<String> _lastHiddenPanelsConfig = [];

  // 布局变化标志 - 用于标识当前变化是否为纯布局变化
  bool _isLayoutOnlyChange = false;
  
  // 操作节流控制
  DateTime? _lastLayoutChangeTime;
  static const Duration _layoutChangeThrottle = Duration(milliseconds: 200);

  // 获取是否为纯布局变化
  bool get isLayoutOnlyChange => _isLayoutOnlyChange;
  
  // 重置布局变化标志
  void resetLayoutChangeFlag() {
    _isLayoutOnlyChange = false;
  }

  // 🔧 优化：更严格的节流通知机制，避免在关键操作期间触发不必要的布局变化
  void _notifyLayoutChange() {
    if (_isDisposed) return; // 防止在dispose后调用
    
    final now = DateTime.now();
    
    // 🔧 修复：更严格的节流控制，避免过于频繁的布局变化通知
    if (_lastLayoutChangeTime != null && 
        now.difference(_lastLayoutChangeTime!) < _layoutChangeThrottle) {
      // 在节流期间，仍然设置布局变化标志，但不触发通知
      _isLayoutOnlyChange = true;
      AppLogger.d('EditorLayoutManager', '节流: 跳过布局变化通知');
      return;
    }
    
    _lastLayoutChangeTime = now;
    _isLayoutOnlyChange = true;
    
    AppLogger.d('EditorLayoutManager', '触发布局变化通知');
    
    // 立即通知监听器
    notifyListeners();
    
    // 🔧 修复：延长标志重置时间，确保下游组件有足够时间处理布局变化
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isDisposed) { // 检查对象是否仍然有效
        _isLayoutOnlyChange = false;
        AppLogger.d('EditorLayoutManager', '重置布局变化标志');
      }
    });
  }

  // 加载保存的尺寸
  Future<void> _loadSavedDimensions() async {
    await _loadSavedEditorSidebarWidth();
    await _loadSavedChatSidebarWidth();
    await _loadSavedPanelWidths();
    await _loadSavedVisiblePanels();
    await _loadLastHiddenPanelsConfig();
  }

  // 加载保存的编辑器侧边栏宽度
  Future<void> _loadSavedEditorSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble(editorSidebarWidthPrefKey);
      if (savedWidth != null) {
        if (savedWidth >= minEditorSidebarWidth &&
            savedWidth <= maxEditorSidebarWidth) {
          editorSidebarWidth = savedWidth;
        }
      }
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '加载编辑器侧边栏宽度失败', e);
    }
  }

  // 保存编辑器侧边栏宽度
  Future<void> saveEditorSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(editorSidebarWidthPrefKey, editorSidebarWidth);
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '保存编辑器侧边栏宽度失败', e);
    }
  }

  // 加载保存的聊天侧边栏宽度
  Future<void> _loadSavedChatSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble(chatSidebarWidthPrefKey);
      if (savedWidth != null) {
        if (savedWidth >= minChatSidebarWidth &&
            savedWidth <= maxChatSidebarWidth) {
          chatSidebarWidth = savedWidth;
        }
      }
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '加载侧边栏宽度失败', e);
    }
  }
  
  // 加载保存的面板宽度
  Future<void> _loadSavedPanelWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidthsString = prefs.getString(panelWidthsPrefKey);
      if (savedWidthsString != null) {
        final savedWidthsList = savedWidthsString.split(',');
        if (savedWidthsList.isNotEmpty) {
          // 聊天面板保持新的默认值（600），其他面板加载保存的值
          if (savedWidthsList.isNotEmpty && savedWidthsList[0].isNotEmpty) {
            final savedChatWidth = double.tryParse(savedWidthsList.elementAtOrNull(0) ?? '');
            if (savedChatWidth != null) {
              panelWidths[aiChatPanel] = savedChatWidth.clamp(minPanelWidth, maxPanelWidth);
            }
          }
          panelWidths[aiSummaryPanel] = double.tryParse(savedWidthsList.elementAtOrNull(1) ?? panelWidths[aiSummaryPanel].toString())!.clamp(minPanelWidth, maxPanelWidth);
          panelWidths[aiScenePanel] = double.tryParse(savedWidthsList.elementAtOrNull(2) ?? panelWidths[aiScenePanel].toString())!.clamp(minPanelWidth, maxPanelWidth);
          if (savedWidthsList.length > 3) {
            panelWidths[aiContinueWritingPanel] = double.tryParse(savedWidthsList.elementAtOrNull(3) ?? panelWidths[aiContinueWritingPanel].toString())!.clamp(minPanelWidth, maxPanelWidth);
          }
          if (savedWidthsList.length > 4) {
            panelWidths[aiSettingGenerationPanel] = double.tryParse(savedWidthsList.elementAtOrNull(4) ?? panelWidths[aiSettingGenerationPanel].toString())!.clamp(minPanelWidth, maxPanelWidth);
          }
        }
      }
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '加载面板宽度失败', e);
    }
  }
  
  // 加载保存的可见面板
  Future<void> _loadSavedVisiblePanels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPanels = prefs.getStringList(visiblePanelsPrefKey);
      if (savedPanels != null) {
        visiblePanels.clear();
        visiblePanels.addAll(savedPanels);
        
        // 更新各面板的可见性状态
        isAIChatSidebarVisible = visiblePanels.contains(aiChatPanel);
        isAISummaryPanelVisible = visiblePanels.contains(aiSummaryPanel);
        isAISceneGenerationPanelVisible = visiblePanels.contains(aiScenePanel);
        isAIContinueWritingPanelVisible = visiblePanels.contains(aiContinueWritingPanel);
        isAISettingGenerationPanelVisible = visiblePanels.contains(aiSettingGenerationPanel);
      }
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '加载可见面板失败', e);
    }
  }

  // 保存聊天侧边栏宽度
  Future<void> saveChatSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(chatSidebarWidthPrefKey, chatSidebarWidth);
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '保存侧边栏宽度失败', e);
    }
  }
  
  // 保存面板宽度
  Future<void> savePanelWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final widthsString = [
        panelWidths[aiChatPanel],
        panelWidths[aiSummaryPanel],
        panelWidths[aiScenePanel],
        panelWidths[aiContinueWritingPanel],
        panelWidths[aiSettingGenerationPanel]
      ].join(',');
      await prefs.setString(panelWidthsPrefKey, widthsString);
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '保存面板宽度失败', e);
    }
  }
  
  // 保存可见面板
  Future<void> saveVisiblePanels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(visiblePanelsPrefKey, visiblePanels);
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '保存可见面板失败', e);
    }
  }

  // 加载隐藏前的面板配置
  Future<void> _loadLastHiddenPanelsConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedConfig = prefs.getStringList(lastHiddenPanelsPrefKey);
      if (savedConfig != null) {
        _lastHiddenPanelsConfig = savedConfig;
      }
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '加载隐藏面板配置失败', e);
    }
  }

  // 保存隐藏前的面板配置
  Future<void> _saveLastHiddenPanelsConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(lastHiddenPanelsPrefKey, _lastHiddenPanelsConfig);
    } catch (e) {
      AppLogger.e('EditorLayoutManager', '保存隐藏面板配置失败', e);
    }
  }

  // 更新编辑器侧边栏宽度
  void updateEditorSidebarWidth(double delta) {
    editorSidebarWidth = (editorSidebarWidth + delta).clamp(
      minEditorSidebarWidth,
      maxEditorSidebarWidth,
    );
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 更新聊天侧边栏宽度
  void updateChatSidebarWidth(double delta) {
    chatSidebarWidth = (chatSidebarWidth - delta).clamp(
      minChatSidebarWidth,
      maxChatSidebarWidth,
    );
    _notifyLayoutChange(); // 修复：添加missing的notifyListeners调用
  }
  
  // 更新指定面板宽度
  void updatePanelWidth(String panelId, double delta) {
    if (panelWidths.containsKey(panelId)) {
      panelWidths[panelId] = (panelWidths[panelId]! - delta).clamp(
        minPanelWidth,
        maxPanelWidth,
      );
      _notifyLayoutChange(); // 使用布局专用的通知方法
    }
  }

  // 切换编辑器侧边栏可见性
  void toggleEditorSidebar() {
    isEditorSidebarVisible = !isEditorSidebarVisible;
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 抽屉模式切换：当宽度小于阈值时展开到最大，当宽度大于等于阈值时收起到抽屉阈值
  void toggleEditorSidebarCompactMode() {
    const double drawerThreshold = 260.0;
    if (editorSidebarWidth < drawerThreshold) {
      expandEditorSidebarToMax();
    } else {
      collapseEditorSidebarToDrawer();
    }
  }

  // 收起到抽屉（通过设置较小宽度触发精简抽屉UI）
  void collapseEditorSidebarToDrawer() {
    editorSidebarWidth = minEditorSidebarWidth; // e.g. 220，会触发 < 260 的精简抽屉
    _notifyLayoutChange();
    saveEditorSidebarWidth();
  }

  // 展开到最大宽度
  void expandEditorSidebarToMax() {
    editorSidebarWidth = maxEditorSidebarWidth; // e.g. 400
    _notifyLayoutChange();
    saveEditorSidebarWidth();
  }

  // 显示编辑器侧边栏（幂等）
  void showEditorSidebar() {
    if (!isEditorSidebarVisible) {
      isEditorSidebarVisible = true;
      _notifyLayoutChange();
    }
  }

  // 隐藏编辑器侧边栏（幂等）
  void hideEditorSidebar() {
    if (isEditorSidebarVisible) {
      isEditorSidebarVisible = false;
      _notifyLayoutChange();
    }
  }

  // 切换AI聊天侧边栏可见性
  void toggleAIChatSidebar() {
    // 在多面板模式下
    if (visiblePanels.contains(aiChatPanel)) {
      // 如果已经可见，则移除
      visiblePanels.remove(aiChatPanel);
      isAIChatSidebarVisible = false;
    } else {
      // 如果不可见，则添加
      visiblePanels.add(aiChatPanel);
      isAIChatSidebarVisible = true;
    }
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 切换AI场景生成面板可见性
  void toggleAISceneGenerationPanel() {
    // 在多面板模式下
    if (visiblePanels.contains(aiScenePanel)) {
      // 如果已经可见，则移除
      visiblePanels.remove(aiScenePanel);
      isAISceneGenerationPanelVisible = false;
    } else {
      // 如果不可见，则添加
      visiblePanels.add(aiScenePanel);
      isAISceneGenerationPanelVisible = true;
    }
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 切换AI摘要面板可见性
  void toggleAISummaryPanel() {
    // 在多面板模式下
    if (visiblePanels.contains(aiSummaryPanel)) {
      // 如果已经可见，则移除
      visiblePanels.remove(aiSummaryPanel);
      isAISummaryPanelVisible = false;
    } else {
      // 如果不可见，则添加
      visiblePanels.add(aiSummaryPanel);
      isAISummaryPanelVisible = true;
    }
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 新增：切换AI自动续写面板可见性
  void toggleAIContinueWritingPanel() {
    if (visiblePanels.contains(aiContinueWritingPanel)) {
      visiblePanels.remove(aiContinueWritingPanel);
      isAIContinueWritingPanelVisible = false;
    } else {
      visiblePanels.add(aiContinueWritingPanel);
      isAIContinueWritingPanelVisible = true;
    }
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 切换设置面板可见性
  void toggleSettingsPanel() {
    isSettingsPanelVisible = !isSettingsPanelVisible;
    if (isSettingsPanelVisible) {
      // 设置面板是全屏遮罩，不影响其他面板的显示
    }
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 切换小说设置视图可见性
  void toggleNovelSettings() {
    isNovelSettingsVisible = !isNovelSettingsVisible;
    if (isNovelSettingsVisible) {
      // 小说设置视图会替换主编辑区域，不影响侧边面板
    }
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }
  
  // 获取面板是否为最后一个
  bool isLastPanel(String panelId) {
    return visiblePanels.length == 1 && visiblePanels.contains(panelId);
  }
  
  // 重新排序面板
  void reorderPanels(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = visiblePanels.removeAt(oldIndex);
    visiblePanels.insert(newIndex, item);
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  void toggleAISettingGenerationPanel() {
    if (visiblePanels.contains(aiSettingGenerationPanel)) {
      visiblePanels.remove(aiSettingGenerationPanel);
      isAISettingGenerationPanelVisible = false;
    } else {
      visiblePanels.add(aiSettingGenerationPanel);
      isAISettingGenerationPanelVisible = true;
    }
    saveVisiblePanels();
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 切换提示词视图可见性
  void togglePromptView() {
    isPromptViewVisible = !isPromptViewVisible;
    if (isPromptViewVisible) {
      // 提示词视图是全屏替换，不影响其他面板的显示
    }
    _notifyLayoutChange(); // 使用布局专用的通知方法
  }

  // 🚀 新增：沉浸模式状态管理
  bool isImmersiveModeEnabled = false;
  
  // 🚀 新增：切换沉浸模式
  void toggleImmersiveMode() {
    isImmersiveModeEnabled = !isImmersiveModeEnabled;
    AppLogger.i('EditorLayoutManager', '切换沉浸模式: $isImmersiveModeEnabled');
    _notifyLayoutChange();
  }
  
  // 🚀 新增：启用沉浸模式
  void enableImmersiveMode() {
    if (!isImmersiveModeEnabled) {
      isImmersiveModeEnabled = true;
      AppLogger.i('EditorLayoutManager', '启用沉浸模式');
      _notifyLayoutChange();
    }
  }
  
  // 🚀 新增：禁用沉浸模式
  void disableImmersiveMode() {
    if (isImmersiveModeEnabled) {
      isImmersiveModeEnabled = false;
      AppLogger.i('EditorLayoutManager', '禁用沉浸模式');
      _notifyLayoutChange();
    }
  }

  /// 隐藏所有AI面板
  void hideAllAIPanels() {
    if (visiblePanels.isNotEmpty) {
      // 保存当前配置
      _lastHiddenPanelsConfig = List<String>.from(visiblePanels);
      _saveLastHiddenPanelsConfig();
      
      // 隐藏所有面板
      visiblePanels.clear();
      isAIChatSidebarVisible = false;
      isAISummaryPanelVisible = false;
      isAISceneGenerationPanelVisible = false;
      isAIContinueWritingPanelVisible = false;
      isAISettingGenerationPanelVisible = false;
      
      saveVisiblePanels();
      _notifyLayoutChange();
    }
  }

  /// 恢复隐藏前的AI面板配置
  void restoreHiddenAIPanels() {
    if (_lastHiddenPanelsConfig.isNotEmpty) {
      // 恢复面板配置
      visiblePanels.clear();
      visiblePanels.addAll(_lastHiddenPanelsConfig);
      
      // 更新各面板的可见性状态
      isAIChatSidebarVisible = visiblePanels.contains(aiChatPanel);
      isAISummaryPanelVisible = visiblePanels.contains(aiSummaryPanel);
      isAISceneGenerationPanelVisible = visiblePanels.contains(aiScenePanel);
      isAIContinueWritingPanelVisible = visiblePanels.contains(aiContinueWritingPanel);
      isAISettingGenerationPanelVisible = visiblePanels.contains(aiSettingGenerationPanel);
      
      saveVisiblePanels();
      _notifyLayoutChange();
    } else {
      // 如果没有保存的配置，显示默认的AI聊天面板
      toggleAIChatSidebar();
    }
  }

  // 显示AI摘要面板
  void showAISummaryPanel() {
    if (!visiblePanels.contains(aiSummaryPanel)) {
      visiblePanels.add(aiSummaryPanel);
      isAISummaryPanelVisible = true;
      saveVisiblePanels();
      _notifyLayoutChange();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
