import 'dart:async';
import 'dart:math';
import 'dart:convert';
// import 'dart:html' as html;

import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:flutter/gestures.dart';

import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;
import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/screens/editor/widgets/selection_toolbar.dart';
import 'package:ainoval/screens/editor/widgets/ai_generation_toolbar.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/setting_reference_processor.dart';
import 'package:ainoval/utils/ai_generated_content_processor.dart';
import 'package:ainoval/services/api_service/repositories/universal_ai_repository.dart';
import 'package:ainoval/services/api_service/base/api_exception.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/scene_beat_data.dart';
import 'package:ainoval/screens/editor/components/text_generation_dialogs.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/word_count_analyzer.dart';
import 'package:provider/provider.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/screens/editor/widgets/menu_builder.dart';
import 'package:ainoval/screens/editor/widgets/setting_reference_hover.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ainoval/widgets/common/setting_preview_manager.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
// import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/editor_settings.dart';
// import 'package:ainoval/models/public_model_config.dart';
import 'package:ainoval/widgets/editor/overlay_scene_beat_manager.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// 场景编辑器组件，用于编辑小说中的单个场景
///
/// [title] 场景标题
/// [wordCount] 场景字数统计
/// [isActive] 当前场景是否处于激活状态
/// [actId] 所属篇章ID
/// [chapterId] 所属章节ID
/// [sceneId] 场景ID
/// [isFirst] 是否为章节中的第一个场景
/// [sceneIndex] 场景在章节中的序号，从1开始
/// [controller] 场景内容编辑控制器
/// [summaryController] 场景摘要编辑控制器
/// [editorBloc] 编辑器状态管理
/// [onContentChanged] 内容变更回调
class SceneEditor extends StatefulWidget {
  const SceneEditor({
    super.key,
    required this.title,
    required this.wordCount,
    required this.isActive,
    this.actId,
    this.chapterId,
    this.sceneId,
    this.isFirst = true,
    this.sceneIndex, // 添加场景序号参数
    required this.controller,
    required this.summaryController,
    required this.editorBloc,
    this.onContentChanged, // 添加回调函数
    this.isVisuallyNearby = true, // 新增参数，默认为true以保持当前行为
    // 🚀 新增：SelectionToolbar数据参数
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    // 编辑器设置
    this.editorSettings,
  });
  final String title;
  final int wordCount;
  final bool isActive;
  final String? actId;
  final String? chapterId;
  final String? sceneId;
  final bool isFirst;
  final int? sceneIndex; // 场景在章节中的序号，从1开始
  final QuillController controller;
  final TextEditingController summaryController;
  final editor_bloc.EditorBloc editorBloc;
  // 添加内容变更回调
  final Function(String content, int wordCount, {bool syncToServer})? onContentChanged;
  final bool isVisuallyNearby; // 新增参数声明

  // 🚀 新增：SelectionToolbar数据参数
  final novel_models.Novel? novel;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;
  
  // 编辑器设置
  final EditorSettings? editorSettings;

  @override
  State<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<SceneEditor> with AutomaticKeepAliveClientMixin {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  bool _isFocused = false;
  // 为编辑器创建一个Key
  late final Key _editorKey;
  // 内容更新防抖定时器
  Timer? _contentDebounceTimer;
  final FocusNode _summaryFocusNode = FocusNode();
  bool _isSummaryFocused = false;
  // 焦点防抖定时器
  Timer? _focusDebounceTimer;
  
  // 🚀 新增：活动状态设置防抖定时器
  Timer? _activeStateDebounceTimer;
  // 🚀 新增：记录最后设置的活动状态，避免重复设置
  String? _lastSetActiveActId;
  String? _lastSetActiveChapterId;
  String? _lastSetActiveSceneId;

  // 添加文本选择工具栏相关变量
  bool _showToolbar = false;
  final LayerLink _toolbarLayerLink = LayerLink();
  int _selectedTextWordCount = 0;
  Timer? _selectionDebounceTimer;
  bool _showToolbarAbove = false; // 默认在选区下方显示，简化计算
  final GlobalKey _editorContentKey = GlobalKey(); // 编辑器内容区域的key

  // 🚀 AI工具栏相关状态
  bool _showAIToolbar = false;
  final LayerLink _aiToolbarLayerLink = LayerLink();
  bool _isAIGenerating = false;
  String _aiModelName = '';
  String _generatedText = '';
  int _aiGeneratedWordCount = 0;
  int _currentStreamIndex = 0;
  int _lastInsertedOffset = 0;
  int _aiGeneratedStartOffset = 0;
  
  // 🚀 新增：流式生成批量插入缓冲
  String _pendingStreamText = '';

  // 🚀 新增：用于保存重试信息的变量
  UniversalAIRequest? _lastAIRequest;
  // 已移除：UserAIModelConfigModel? _lastAIModel; 现在使用_lastUnifiedModel
  String? _lastSelectedText;
  // 🚀 新增：保存统一模型信息（包含isPublic状态）
  UnifiedAIModel? _lastUnifiedModel;

  // 添加防抖处理
  String _pendingContent = '';
  String _lastSavedContent = ''; // 添加最后保存的内容，用于比较变化
  DateTime _lastChangeTime = DateTime.now(); // 添加最后变更时间
  int _pendingWordCount = 0;
  Timer? _syncTimer;
  final int _minorChangeThreshold = 5; // 定义微小改动的字符数阈值
  
  // 添加内容变化标志，用于在dispose时判断是否需要强制保存
  bool _hasUnsavedChanges = false;
  
  // 🚀 新增：设定引用处理状态标志，避免样式变化触发保存
  bool _isProcessingSettingReferences = false;
  int _lastSettingHash = 0; // 简单文本哈希，避免重复处理

  // 🚀 新增：AI生成状态标志，避免生成过程中触发保存

  // 添加滚动控制器，用于工具栏定位
  late final ScrollController _editorScrollController;
  
  // 设定引用处理相关
  Timer? _settingReferenceProcessTimer;
  String _lastProcessedText = '';
  String _lastProcessedDeltaContent = ''; // 上次处理的完整Delta内容
  DateTime _lastProcessingTime = DateTime(2000); // 上次处理时间
  static const Duration _minProcessingInterval = Duration(milliseconds: 1000); // 最小处理间隔

  // 🚀 新增：摘要组件滚动固定相关变量
  final GlobalKey _sceneContainerKey = GlobalKey(); // 场景容器的key
  final GlobalKey _summaryKey = GlobalKey(); // 摘要组件的key
  // 使用 ValueNotifier 代替频繁 setState
  final ValueNotifier<double> _summaryTopOffsetVN = ValueNotifier<double>(0.0); // 摘要Y偏移
  bool _isSummarySticky = false; // 摘要是否处于sticky状态
  Timer? _scrollPositionTimer; // 滚动位置更新定时器
  ScrollController? _parentScrollController; // 父级滚动控制器
  
  // 🚀 新增：流畅滚动优化变量
  double _lastCalculatedOffset = 0.0; // 上次计算的偏移量
  bool _lastStickyState = false; // 上次的sticky状态
  double _summaryHeight = 200.0; // 摘要组件的实际高度，默认200px
  static const double _positionThreshold = 2.0; // 位置变化阈值，减少闪烁
  
  // 🚀 新增：粘性滚动控制变量
  static const double _minSceneHeightForSticky = 400.0; // 最小场景高度，低于此高度不启用粘性
  static const double _summaryTopMargin = 16.0; // 摘要顶部边距
  static const double _summaryBottomMargin = 24.0; // 摘要底部边距
  static const double _bottomToolbarHeight = 40.0; // 🚀 新增：底部工具栏预留高度
  
  // 🚀 新增：摘要折叠控制变量
  static const double _summaryExpandedWidth = 280.0; // 展开时的宽度
  static const double _summaryCollapsedWidth = 40.0; // 折叠时的宽度（只显示按钮）
  static const double _summarySpacing = 16.0; // 摘要与编辑器的间距
  static const String _summaryCollapsedKey = 'scene_editor_summary_collapsed'; // 本地存储key
  bool _isSummaryCollapsed = false; // 摘要是否折叠

  // 🚀 新增：LayerLink目标的GlobalKey，用于工具栏检测位置
  final GlobalKey _toolbarTargetKey = GlobalKey();

  // 🚀 新增：AI生成状态标志，避免生成过程中触发保存

  // 添加一个延迟初始化标志
  bool _isEditorFullyInitialized = false;
  Timer? _streamingTimer;
  
  // 🎯 设定引用悬停状态管理
  final _hoverManager = SettingReferenceHoverManager();
  String? _hoveredSettingId;
  
  // ==================== Controller listeners管理 ====================
  StreamSubscription? _docChangeSub; // 监听 document.changes 的订阅，便于在 controller 切换时取消
  
  /// 获取当前小说ID
  String? _getNovelId() {
    final editorBloc = widget.editorBloc;
    if (editorBloc.state is editor_bloc.EditorLoaded) {
      final state = editorBloc.state as editor_bloc.EditorLoaded;
      return state.novel.id;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
      
      // 修改初始化Key的方式，确保唯一性
      final String sceneId = widget.sceneId ??
          (widget.actId != null && widget.chapterId != null
              ? '${widget.actId}_${widget.chapterId}'
              : widget.title.replaceAll(' ', '_').toLowerCase());
      // 使用ValueKey代替GlobalObjectKey
      _editorKey = ValueKey('editor_$sceneId');

      // 初始化滚动控制器
      _editorScrollController = ScrollController();

      // 监听焦点变化
      _focusNode.addListener(_onEditorFocusChange);
      _summaryFocusNode.addListener(_onSummaryFocusChange);
      
      // 🎯 监听设定引用悬停状态变化
      _hoverManager.addListener(_onSettingHoverChanged);

      // 添加控制器内容监听器（保存订阅以便后续取消）
      _docChangeSub = widget.controller.document.changes.listen(_onDocumentChange);

      // 添加文本选择变化监听
      widget.controller.addListener(_handleSelectionChange);
      
      // 监听EditorBloc状态变化，确保摘要控制器内容与模型保持同步
      _setupBlocListener();
      
      // 监听设定状态变化，处理设定引用
      _setupSettingBlocListener();
      
      // 监听内容加载完成，重新处理设定引用
      _setupContentLoadListener();
      
      // 初始化最后保存的内容（纯文本用于比较）
      _lastSavedContent = widget.controller.document.toPlainText();
      
      // 🚀 新增：设置摘要滚动固定监听
      _setupSummaryScrollListener();
      
      // 🚀 新增：从本地存储加载摘要折叠状态
      _loadSummaryCollapsedState();
      
      // 延迟完整初始化，优先显示基础UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 在渲染完成后再初始化复杂功能
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _isEditorFullyInitialized = true;
            });
            
            // 🎯 简化：直接处理设定引用，不再等待DOM
            AppLogger.i('SceneEditor', '🎯 开始设定引用处理: ${widget.sceneId}');
            //_checkAndProcessSettingReferences();
            
            // 🚀 新增：初始化摘要位置
            _updateSummaryPosition();
          }
        });
      });

  }

  /// 🚀 新增：从本地存储加载摘要折叠状态
  Future<void> _loadSummaryCollapsedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_summaryCollapsedKey) ?? false;
      if (mounted) {
        setState(() {
          _isSummaryCollapsed = collapsed;
        });
      }
    } catch (e) {
      AppLogger.e('SceneEditor', '加载摘要折叠状态失败: $e');
    }
  }

  /// 🚀 新增：保存摘要折叠状态到本地存储
  Future<void> _saveSummaryCollapsedState(bool collapsed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_summaryCollapsedKey, collapsed);
      AppLogger.v('SceneEditor', '保存摘要折叠状态: $collapsed');
    } catch (e) {
      AppLogger.e('SceneEditor', '保存摘要折叠状态失败: $e');
    }
  }

  /// 🎯 处理设定引用悬停状态变化
  void _onSettingHoverChanged() {
    if (!mounted) return;
    
    setState(() {
      _hoveredSettingId = _hoverManager.hoveredSettingId;
    });
  }

  void _onEditorFocusChange() {

      // 使用节流控制焦点更新频率
      _focusDebounceTimer?.cancel();
      _focusDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          final newFocusState = _focusNode.hasFocus;
          // 仅当焦点状态真正改变时更新状态
          if (_isFocused != newFocusState) {
            setState(() {
              _isFocused = newFocusState;
              
              // 🎯 当编辑器获得焦点时，处理设定引用（使用防抖）
              if (_isFocused && !_isProcessingSettingReferences) {
                ////AppLogger.d('SceneEditor', '📝 编辑器获得焦点，处理设定引用: ${widget.sceneId}');
                _processSettingReferencesDebounced();
              }
              
              // 🚀 优化：只有当获得焦点且确实需要改变活动状态时才设置活动元素
              if (_isFocused && widget.actId != null && widget.chapterId != null) {
                // 检查当前是否已经是活动状态
                final editorBloc = widget.editorBloc;
                if (editorBloc.state is editor_bloc.EditorLoaded) {
                  final state = editorBloc.state as editor_bloc.EditorLoaded;
                  final isAlreadyActive = state.activeActId == widget.actId &&
                      state.activeChapterId == widget.chapterId &&
                      state.activeSceneId == widget.sceneId;
                  
                  // 只有当不是活动状态时才设置
                  if (!isAlreadyActive) {
                    _setActiveElementsQuietly();
                  }
                  
                  // 如果场景节拍面板已显示且当前场景有sceneId，则切换到当前场景
                  if (widget.sceneId != null && 
                      OverlaySceneBeatManager.instance.isVisible && 
                      OverlaySceneBeatManager.instance.currentSceneId != widget.sceneId) {
                    AppLogger.i('SceneEditor', '🔄 场景获得焦点，切换场景节拍面板到: ${widget.sceneId}');
                    OverlaySceneBeatManager.instance.switchScene(widget.sceneId!);
                  }
                } else {
                  // 状态不明确时才设置
                  _setActiveElementsQuietly();
                }
              }
            });
            

          }
        }
      });

  }

  void _onSummaryFocusChange() {

      // 使用节流控制焦点更新频率
      _focusDebounceTimer?.cancel();
      _focusDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          final newFocusState = _summaryFocusNode.hasFocus;
          // 仅当焦点状态真正改变时更新状态
          if (_isSummaryFocused != newFocusState) {
            setState(() {
              _isSummaryFocused = newFocusState;
              // 🚀 优化：只有当获得焦点且确实需要改变活动状态时才设置活动元素
              if (_isSummaryFocused && widget.actId != null && widget.chapterId != null) {
                // 检查当前是否已经是活动状态
                final editorBloc = widget.editorBloc;
                if (editorBloc.state is editor_bloc.EditorLoaded) {
                  final state = editorBloc.state as editor_bloc.EditorLoaded;
                  final isAlreadyActive = state.activeActId == widget.actId &&
                      state.activeChapterId == widget.chapterId &&
                      state.activeSceneId == widget.sceneId;
                  
                  // 只有当不是活动状态时才设置
                  if (!isAlreadyActive) {
                    _setActiveElementsQuietly();
                  }
                } else {
                  // 状态不明确时才设置
                  _setActiveElementsQuietly();
                }
              }
            });
            

          }
        }
      });

  }

  // 设置活动元素 - 原始方法
  void _setActiveElements() {

      if (widget.actId != null && widget.chapterId != null) {
        widget.editorBloc.add(
            editor_bloc.SetActiveChapter(actId: widget.actId!, chapterId: widget.chapterId!));
        if (widget.sceneId != null) {
          widget.editorBloc.add(editor_bloc.SetActiveScene(
              actId: widget.actId!,
              chapterId: widget.chapterId!,
              sceneId: widget.sceneId!));
        }
      }

  }

  // 设置活动元素但不触发滚动 - 适用于编辑中场景（优化版）
  void _setActiveElementsQuietly() {

      if (widget.actId != null && widget.chapterId != null) {
        // 🚀 优化：检查是否与上次设置的状态相同，避免重复设置
        final bool isSameAsLastSet = _lastSetActiveActId == widget.actId &&
            _lastSetActiveChapterId == widget.chapterId &&
            _lastSetActiveSceneId == widget.sceneId;
        
        if (isSameAsLastSet) {
          AppLogger.v('SceneEditor', '跳过设置活动状态：与上次设置相同 ${widget.actId}/${widget.chapterId}/${widget.sceneId}');
          return;
        }
        
        // 🚀 使用防抖机制，避免短时间内频繁设置
        _activeStateDebounceTimer?.cancel();
        _activeStateDebounceTimer = Timer(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          
          // 直接使用BlocProvider获取EditorBloc实例
          final editorBloc = widget.editorBloc;
          
          // 检查当前活动状态，避免重复设置相同的活动元素
          if (editorBloc.state is editor_bloc.EditorLoaded) {
            final state = editorBloc.state as editor_bloc.EditorLoaded;
            
            // 只有当活动元素确实需要变化时才发出事件
            final needsToUpdateAct = state.activeActId != widget.actId;
            final needsToUpdateChapter = state.activeChapterId != widget.chapterId;
            final needsToUpdateScene = widget.sceneId != null && state.activeSceneId != widget.sceneId;
            
            if (needsToUpdateAct || needsToUpdateChapter) {
              ////AppLogger.d('SceneEditor', '设置活动章节: ${widget.actId}/${widget.chapterId}');
              editorBloc.add(editor_bloc.SetActiveChapter(
                actId: widget.actId!, 
                chapterId: widget.chapterId!,
                silent: true, // 🚀 使用静默模式，避免触发大范围UI刷新
              ));
              
              // 🚀 记录已设置的状态
              _lastSetActiveActId = widget.actId;
              _lastSetActiveChapterId = widget.chapterId;
            }
            
            if (needsToUpdateScene && widget.sceneId != null) {
              ////AppLogger.d('SceneEditor', '设置活动场景: ${widget.sceneId}');
              editorBloc.add(editor_bloc.SetActiveScene(
                actId: widget.actId!,
                chapterId: widget.chapterId!,
                sceneId: widget.sceneId!,
                silent: true, // 🚀 使用静默模式，避免触发大范围UI刷新
              ));
              
              // 🚀 记录已设置的场景状态
              _lastSetActiveSceneId = widget.sceneId;
            }
          } else {
            // 如果状态不是EditorLoaded，则使用原始方法
            _setActiveElements();
            
            // 🚀 记录已设置的状态
            _lastSetActiveActId = widget.actId;
            _lastSetActiveChapterId = widget.chapterId;
            _lastSetActiveSceneId = widget.sceneId;
          }
        });
      }

  }

  // 监听文档变化
  void _onDocumentChange(DocChange change) {

      if (!mounted) return;
      
      // 🚫 生成期间：跳过文档变更的重处理（编码/过滤/保存）
      if (_isAIGenerating) {
        AppLogger.v('SceneEditor', '⏭️ 生成中，跳过文档变更处理: ${widget.sceneId}');
        return;
      }

      // 🚀 关键修复：检查变化是否来源于设定引用样式应用
      final currentText = widget.controller.document.toPlainText();
      final currentDeltaJson = jsonEncode(widget.controller.document.toDelta().toJson());
      
      // 🎯 新增：如果完整内容相等且正在处理设定引用，直接跳过
      if (currentDeltaJson == _lastProcessedDeltaContent && _isProcessingSettingReferences) {
        AppLogger.v('SceneEditor', '⏭️ 场景内容完全相等且正在处理设定引用，跳过保存');
        return;
      }
      
      // 如果是样式变化且文本内容没有变化，则不触发保存
      if (currentText == _lastSavedContent && _isProcessingSettingReferences) {
        AppLogger.v('SceneEditor', '⏭️ 设定引用样式应用不触发保存');
        return;
      }

      // 🎯 新增：检查是否仅为样式变化（不是文本内容变化）
      if (_isOnlyStyleChange(change) && _isProcessingSettingReferences) {
        AppLogger.v('SceneEditor', '⏭️ 仅样式变化且正在处理设定引用，跳过');
        return;
      }

      // 🚀 修复关键问题：提取包含样式信息的完整Delta格式
      // 不再使用 toPlainText() 因为它会丢失所有样式属性
      final rawDeltaJson = currentDeltaJson; // 复用已计算的Delta JSON
      
      // 🧹 过滤设定引用相关的自定义样式，但保留其他样式（如粗体、斜体、下划线等）
      // 🎯 重新启用过滤，确保保存时不包含设定引用样式
      final filteredDeltaJson = SettingReferenceProcessor.filterSettingReferenceStyles(rawDeltaJson, caller: '_onDocumentChange');
      
      //////AppLogger.d('SceneEditor', '文档变化 - 过滤后保存Delta格式，原始长度: ${rawDeltaJson.length}, 过滤后长度: ${filteredDeltaJson.length}');

      // 使用防抖动机制，避免频繁发送保存请求
      _contentDebounceTimer?.cancel();
      _contentDebounceTimer = Timer(const Duration(milliseconds: 800), () {
        // 延长为800毫秒防抖，更好地应对快速输入
        _onTextChanged(filteredDeltaJson);
      });
      
      // 🎯 优化：只在真正的文本内容变化时才处理设定引用
      if (currentText != _lastSavedContent && !_isProcessingSettingReferences && 
          currentDeltaJson != _lastProcessedDeltaContent) {
        // 延迟处理设定引用，避免在文档变化处理过程中立即触发
        Timer(const Duration(milliseconds: 100), () {
          if (mounted) {
            _checkAndProcessSettingReferences();
          }
        });
      }
      

  }

  // 🎯 新增：检查是否仅为样式变化
  bool _isOnlyStyleChange(DocChange change) {
    try {
      // 检查变化是否只涉及格式化而不涉及文本插入/删除
      if (change.change.operations.every((op) {
        // 如果是retain操作且有attributes，说明是样式变化
        if (op.key == 'retain' && op.attributes != null) {
          return true;
        }
        // 如果是insert操作但插入的是空字符串且有attributes，也是样式变化
        if (op.key == 'insert' && op.data is String && (op.data as String).isEmpty && op.attributes != null) {
          return true;
        }
        return false;
      })) {
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.w('SceneEditor', '检查样式变化失败', e);
      return false;
    }
  }

  // 添加防抖处理
  void _onTextChanged(String content) {

      // 🚫 生成期间不进行保存与过滤，等待用户"应用/丢弃"后再处理
      if (_isAIGenerating) {
        AppLogger.v('SceneEditor', '⏭️ 生成中，跳过_onTextChanged: ${widget.sceneId}');
        return;
      }

      // 🚀 修复：避免在设定引用处理时触发保存
      if (_isProcessingSettingReferences) {
        AppLogger.v('SceneEditor', '🛑 设定引用处理中，跳过保存: ${widget.sceneId}');
        return;
      }
      
      // 🚫 如果文本内容未发生变化，直接跳过后续处理，防止重复保存
      final String currentPlainText = QuillHelper.deltaToText(content);
      if (currentPlainText == _lastSavedContent) {
        AppLogger.v('SceneEditor', '⏭️ 文本内容与最后保存内容一致，跳过保存: ${widget.sceneId}');
        return;
      }
      
      // 🆕 新增：如果有隐藏文本，使用过滤后的内容进行保存
      if (AIGeneratedContentProcessor.hasAnyHiddenText(controller: widget.controller)) {
        AppLogger.v('SceneEditor', '🫥 检测到隐藏文本，使用过滤后的内容保存: ${widget.sceneId}');
        // 使用过滤掉隐藏文本的内容
        content = AIGeneratedContentProcessor.getVisibleDeltaJsonOnly(controller: widget.controller);
      }
      
      // 🚀 修复：现在接收的是Delta JSON格式，包含完整样式信息
      // 先提取纯文本用于字数统计和变化检测
      final plainText = currentPlainText;
      final wordCount = WordCountAnalyzer.countWords(plainText);
      
      // 判断是否为微小改动（基于纯文本比较）
      final bool isMinorChange = _isMinorTextChange(plainText);
      
      // 记录变动信息
      AppLogger.v('SceneEditor', '文本变更 - Delta长度: ${content.length}, 字数: $wordCount, 是否微小改动: $isMinorChange');
      
      // 保存到本地变量，避免立即更新
      _pendingContent = content; // 🚀 现在保存的是包含样式的Delta JSON
      _pendingWordCount = wordCount;
      _lastChangeTime = DateTime.now();
      
      // 触发设定引用处理
      _checkAndProcessSettingReferences();
    
    // 标记有未保存的更改（基于纯文本比较）
    _hasUnsavedChanges = true;
    
    // 🚀 新增：通过正则快速检测Delta JSON中是否仍包含 AI 临时属性，避免漏判
    final bool hasTempAIMarks = content.contains('"ai-generated"') ||
        content.contains('"hidden-text"');
    
    // 只有在内容实际发生变化且没有临时标记时，才发送 UpdateSceneContent 事件
    if (widget.actId != null && widget.chapterId != null && widget.sceneId != null && !hasTempAIMarks) {
      // 🧹 确保保存时过滤设定引用样式，避免保存临时样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStylesForSave(_pendingContent, caller: '_onTextChanged');
      
      widget.editorBloc.add(
        editor_bloc.UpdateSceneContent(
          novelId: widget.editorBloc.novelId,
          actId: widget.actId!,
          chapterId: widget.chapterId!,
          sceneId: widget.sceneId!,
          content: filteredContent,
          wordCount: _pendingWordCount.toString(),
          isMinorChange: isMinorChange, // 传递是否为微小改动的标志
        ),
      );
    } else {
      // 如果有临时标记，记录日志并完全跳过该事件，避免任何远端保存
      AppLogger.v('SceneEditor', '🚫 存在临时标记，跳过 UpdateSceneContent: ${widget.sceneId}');
    }
    
    // 无论是否为微小改动，都更新最后保存的内容（纯文本用于比较）
    _lastSavedContent = plainText;
    
    // 重置防抖计时器 - 连续输入时只触发一次保存
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      // 等待2秒再保存本地，这样可以减少本地保存频率
      _saveLocalOnly();
    });
    
    // 设置同步计时器 - 每5分钟同步一次到服务器，仅当存在未保存更改时
    if (_syncTimer == null || !_syncTimer!.isActive) {
      _syncTimer = Timer(const Duration(minutes: 5), () {
        if (_hasUnsavedChanges) {
          _syncToServer();
        }
      });
    }

}
  
  // 检测是否为微小文本改动
  bool _isMinorTextChange(String plainText) {
    if (_lastSavedContent.isEmpty) return false;
    
    // 1. 检查变化的字符数
    final int lengthDiff = (plainText.length - _lastSavedContent.length).abs();
    
    // 2. 计算编辑距离 (简化版 - 仅考虑长度变化)
    // 对于完整的编辑距离(Levenshtein)需要更复杂的算法，这里简化处理
    final int editDistance = min(lengthDiff, _minorChangeThreshold + 1);
    
    // 3. 检查时间间隔 (如果刚刚保存过，更可能是微小改动)
    final timeSinceLastChange = DateTime.now().difference(_lastChangeTime);
    final bool isRecentChange = timeSinceLastChange < const Duration(seconds: 3);
    
    // 4. 综合判断 (字符变化很小，或者最近刚改过且变化不大)
    final bool isMinor = editDistance <= _minorChangeThreshold || 
                         (isRecentChange && editDistance <= _minorChangeThreshold * 2);
    
    AppLogger.v('SceneEditor', '变更分析 - 字符差异: $lengthDiff, 编辑距离: $editDistance, 时间间隔: ${timeSinceLastChange.inMilliseconds}ms, 判定为${isMinor ? "微小" : "重要"}改动');
    
    return isMinor;
  }

  // 保存到本地
  void _saveLocalOnly() {
        // 🚫 避免在AI生成过程中保存含有临时标记的内容
    if (_pendingContent.contains('"ai-generated"') || _pendingContent.contains('"hidden-text"')) {
      AppLogger.v('SceneEditor', '🚫 _saveLocalOnly 检测到临时AI标记，跳过本地保存: \\${widget.sceneId}');
      return;
    }
    if (widget.actId != null && widget.chapterId != null && widget.sceneId != null) {
      // 🧹 本地保存时过滤设定引用样式，避免保存临时样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStylesForSave(_pendingContent, caller: '_saveLocalOnly');
      
      // 直接调用EditorBloc保存，不触发同步
      widget.editorBloc.add(
        editor_bloc.SaveSceneContent(
          novelId: widget.editorBloc.novelId,
          actId: widget.actId!,
          chapterId: widget.chapterId!,
          sceneId: widget.sceneId!,
          content: filteredContent,
          wordCount: _pendingWordCount.toString(),
          localOnly: true, // 仅保存到本地
        ),
      );
      
      // 更新最后保存的内容（保存纯文本用于比较）
      _lastSavedContent = QuillHelper.deltaToText(_pendingContent);
    } else if (widget.onContentChanged != null) {
      // 🧹 本地保存时过滤设定引用样式，避免保存临时样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStylesForSave(_pendingContent, caller: '_saveLocalOnly_callback');
      
      // 如果提供了回调，使用回调函数
      widget.onContentChanged!(filteredContent, _pendingWordCount, syncToServer: false);
      
      // 更新最后保存的内容（保存纯文本用于比较）
      _lastSavedContent = QuillHelper.deltaToText(_pendingContent);
    }
  }
  
  // 同步到服务器
  void _syncToServer() {
    // 🚫 如果仍包含 AI 临时标记（ai-generated/hidden-text），直接跳过远端同步，避免在生成过程中保存至后端
    if (_pendingContent.contains('"ai-generated"') ||
        _pendingContent.contains('"hidden-text"')) {
      AppLogger.v('SceneEditor', '🚫 存在 AI 临时标记，跳过 _syncToServer');
      // 仍然保留 _hasUnsavedChanges = true ，这样在 Apply 之后可以正常同步
      return;
    }
    
    if (widget.actId != null && widget.chapterId != null && widget.sceneId != null) {
      // 🧹 同步到服务器时过滤设定引用样式，避免保存临时样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStylesForSave(_pendingContent, caller: '_syncToServer');
      
      // 使用EditorBloc同步到服务器
      widget.editorBloc.add(
        editor_bloc.SaveSceneContent(
          novelId: widget.editorBloc.novelId,
          actId: widget.actId!,
          chapterId: widget.chapterId!,
          sceneId: widget.sceneId!,
          content: filteredContent,
          wordCount: _pendingWordCount.toString(),
          localOnly: false, // 同步到服务器
        ),
      );
      
      // 更新最后保存的内容（保存纯文本用于比较）
      _lastSavedContent = QuillHelper.deltaToText(_pendingContent);
    } else if (widget.onContentChanged != null) {
      // 🧹 同步到服务器时过滤设定引用样式，避免保存临时样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStylesForSave(_pendingContent, caller: '_syncToServer_callback');
      
      // 如果提供了回调，使用回调函数
      widget.onContentChanged!(filteredContent, _pendingWordCount, syncToServer: true);
      
      // 更新最后保存的内容（保存纯文本用于比较）
      _lastSavedContent = QuillHelper.deltaToText(_pendingContent);
    }
  }

  // 处理文本选择变化
  void _handleSelectionChange() {

      // 若选区变化太快，跳过更新
      final selection = widget.controller.selection;
      if (selection.isCollapsed) {
        // 如果没有选择文本，隐藏工具栏
        if (_showToolbar) {
          setState(() {
            _showToolbar = false;
            _selectedTextWordCount = 0;
          });
        }
        return;
      }
      
      // 使用更高效的节流控制
      _selectionDebounceTimer?.cancel();
      _selectionDebounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        
        // 高效判断是否需要更新界面
        final selectedText = widget.controller.document
            .getPlainText(selection.start, selection.end - selection.start);
        final wordCount = WordCountAnalyzer.countWords(selectedText);
        
        // 仅当选择内容与上次不同时才更新
        if (!_showToolbar || _selectedTextWordCount != wordCount) {
          setState(() {
            _showToolbar = true;
            _selectedTextWordCount = wordCount;
            // 简化位置计算，使用固定位置
            _showToolbarAbove = false;
          });
          
          // 🚀 关键修复：选择区域变化时，强制重新构建LayerLink目标
          ////AppLogger.d('SceneEditor', '🎯 选择区域变化，触发LayerLink目标重新定位');
          
          // 🚀 强制触发下一帧重新构建，确保LayerLink目标位置更新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ////AppLogger.d('SceneEditor', '🔄 强制重新构建LayerLink目标位置');
              setState(() {
                // 这个setState专门用于强制重新构建LayerLink目标
              });
            }
          });
        }
        

      });

  }

  // // 简化的选区矩形计算
  // Rect _calculateSelectionRect() {
  //   try {
  //     // 获取编辑器渲染对象
  //     final RenderBox? editorBox =
  //         _editorContentKey.currentContext?.findRenderObject() as RenderBox?;
  //     if (editorBox == null) return Rect.zero;

  //     // 获取编辑器全局坐标
  //     final editorOffset = editorBox.localToGlobal(Offset.zero);
  //     final editorWidth = editorBox.size.width;

  //     // 创建一个固定位置，避免复杂计算
  //     return Rect.fromLTWH(
  //       editorWidth * 0.5 - 50, // 水平居中偏左
  //       50, // 固定在顶部下方50像素
  //       100, // 固定宽度
  //       30, // 固定高度
  //     );
  //   } catch (e) {
  //     return Rect.zero;
  //   }
  // }

  @override
  void dispose() {
    // 页面关闭前确保同步到服务器
    _debounceTimer?.cancel();
    _syncTimer?.cancel();
    _settingReferenceProcessTimer?.cancel(); // 取消设定引用处理定时器
    _scrollPositionTimer?.cancel(); // 🚀 取消摘要位置更新定时器
    
    // 强制保存未保存的更改
    if (_hasUnsavedChanges && 
        widget.actId != null && 
        widget.chapterId != null && 
        widget.sceneId != null &&
        _pendingContent.isNotEmpty) {
      
      AppLogger.i('SceneEditor', '组件销毁前强制保存场景内容: ${widget.sceneId}');
      
      // 🧹 确保保存前过滤设定引用样式
      final filteredContent = SettingReferenceProcessor.filterSettingReferenceStyles(_pendingContent, caller: 'dispose');
      
      // 获取当前摘要内容
      final currentSummary = widget.summaryController.text;
      
      // 立即触发强制保存事件
      widget.editorBloc.add(
        editor_bloc.ForceSaveSceneContent(
          novelId: widget.editorBloc.novelId,
          actId: widget.actId!,
          chapterId: widget.chapterId!,
          sceneId: widget.sceneId!,
          content: filteredContent,
          wordCount: _pendingWordCount.toString(),
          summary: currentSummary.isNotEmpty ? currentSummary : null,
        ),
      );
      
      AppLogger.i('SceneEditor', '强制保存事件已触发: ${widget.sceneId}');
    }
    
    _focusNode.removeListener(_onEditorFocusChange);
    _summaryFocusNode.removeListener(_onSummaryFocusChange);
    // 🎯 移除设定引用悬停状态监听
    _hoverManager.removeListener(_onSettingHoverChanged);
    _contentDebounceTimer?.cancel(); // 取消内容防抖定时器
    _selectionDebounceTimer?.cancel(); // 取消选择防抖定时器
    _focusDebounceTimer?.cancel(); // 取消焦点防抖定时器
    _activeStateDebounceTimer?.cancel(); // 🚀 取消活动状态防抖定时器
    _streamingTimer?.cancel(); // 取消AI流式输出定时器
    widget.controller.removeListener(_handleSelectionChange); // 移除选择变化监听
    
    // 🚀 移除摘要滚动监听
    _removeSummaryScrollListener();
    
    // 🚀 场景销毁时不需要特别处理，数据管理器会自动处理数据持久化
    if (widget.sceneId != null && 
        OverlaySceneBeatManager.instance.isVisible && 
        OverlaySceneBeatManager.instance.currentSceneId == widget.sceneId) {
      AppLogger.i('SceneEditor', '🔄 场景销毁，场景节拍数据由数据管理器自动管理: ${widget.sceneId}');
    }
    
    _focusNode.dispose();
    _summaryFocusNode.dispose();
    _editorScrollController.dispose(); // 释放滚动控制器
    _summaryTopOffsetVN.dispose();
    super.dispose();

    // 取消 document.changes 订阅，避免泄漏
    _docChangeSub?.cancel();
  }

  @override
  bool get wantKeepAlive => widget.isVisuallyNearby;

  @override
  Widget build(BuildContext context) {
    super.build(context);
  
      final theme = Theme.of(context);
      final bool isEditorOrSummaryFocused = _isFocused || _isSummaryFocused;



      return RepaintBoundary(
        child: _buildOptimizedSceneEditor(theme, isEditorOrSummaryFocused),
      );
 
  }
  
  // 优化后的场景编辑器构建方法
  Widget _buildOptimizedSceneEditor(ThemeData theme, bool isEditorOrSummaryFocused) {

      // 🚀 修改：使用Stack布局来实现摘要滚动固定效果
      return Container(
        key: _sceneContainerKey, // 🚀 添加场景容器key
        decoration: WebTheme.getCleanCardDecoration(context: context),
        // 调整卡片间距，代替之前的 SceneDivider
        margin: EdgeInsets.only(
            bottom: widget.isFirst ? 16.0 : 24.0, top: widget.isFirst ? 0 : 8.0),
        child: GestureDetector(
          onTapDown: (_) {
            // ⚠️ 原因：避免在指针事件分发期间同步重建/状态修改导致 MouseTracker 重入（Flutter Web 断言）
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // 🚀 优化：只在非焦点状态且活动状态确实需要改变时才进行激活操作
              if (!_isFocused && !_isSummaryFocused) {
                // 检查当前是否已经是活动状态
                final editorBloc = widget.editorBloc;
                if (editorBloc.state is editor_bloc.EditorLoaded) {
                  final state = editorBloc.state as editor_bloc.EditorLoaded;
                  final isAlreadyActive = state.activeActId == widget.actId &&
                      state.activeChapterId == widget.chapterId &&
                      state.activeSceneId == widget.sceneId;
                  
                  // 只有当不是活动状态时才设置
                  if (!isAlreadyActive) {
                    _setActiveElementsQuietly();
                  }
                } else {
                  // 状态不明确时才设置
                  _setActiveElementsQuietly();
                }
              }
            });
          },
          // 添加点击处理，但确保不会干扰子控件的焦点
          onTap: () {
            // ⚠️ 原因：同上，避免在指针事件回调里同步更改焦点树
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // 🚀 优化：如果编辑器还没有焦点，尝试获取焦点
              if (!_isFocused && !_isSummaryFocused && mounted) {
                // 只有当没有其他焦点时，才请求焦点
                if (!FocusScope.of(context).hasFocus && _focusNode.canRequestFocus) {
                  _focusNode.requestFocus();
                }
              }
            });
          },
          behavior: HitTestBehavior.translucent, // 确保即使有子组件也能接收手势
          child: Padding(
            padding: const EdgeInsets.all(16.0), // 卡片内部统一内边距
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 场景标题和字数统计 (移到卡片内部)
                _buildSceneHeader(
                    theme, isEditorOrSummaryFocused), // 传入 theme 和焦点状态
                const SizedBox(height: 12), // 增加标题和内容间距

                // 🚀 修改：使用Stack布局来实现摘要滚动固定
                Stack(
                  clipBehavior: Clip.none, // 🚀 关键：不裁剪超出边界的内容，确保窄条可见
                  children: [
                    // 编辑器区域 - 现在占用全宽度
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 编辑器区域 - 移除flex，让其自由填充
                        Expanded( 
                          child: Stack(
                            children: [
                              // 编辑器（包装在设定引用悬停检测组件中）
                              Stack(
                                children: [
                                  // 主编辑器
                                  _buildEditor(theme, isEditorOrSummaryFocused),
                                  // 动态跟随选择区域的LayerLink目标
                                  if (_showToolbar && _isEditorFullyInitialized)
                                    _buildEmbeddedLayerLinkTarget(),
                                  // AI工具栏的LayerLink目标
                                  if (_showAIToolbar && _isEditorFullyInitialized)
                                    _buildEmbeddedAILayerLinkTarget(),
                                ],
                              ),
                              // 文本选择工具栏
                              if (_showToolbar && _isEditorFullyInitialized)
                                Positioned(
                                  child: SelectionToolbar(
                                  
                                    controller: widget.controller,
                                    layerLink: _toolbarLayerLink,
                                    wordCount: _selectedTextWordCount,
                                    editorSize: _editorContentKey.currentContext
                                            ?.findRenderObject() is RenderBox
                                        ? (_editorContentKey.currentContext!
                                                .findRenderObject() as RenderBox)
                                            .size
                                        : const Size(300, 150),
                                    selectionRect: Rect.zero,
                                    showAbove: _showToolbarAbove,
                                    scrollController: _editorScrollController,
                                    // 🚀 修改：使用从props传递的数据，而不是null值
                                    novel: widget.novel,
                                    settings: widget.settings,
                                    settingGroups: widget.settingGroups,
                                    snippets: widget.snippets,
                                    novelId: _getNovelId(), // 传递小说ID
                                    onClosed: () {
                                      setState(() {
                                        _showToolbar = false;
                                      });
                                    },
                                    onFormatChanged: () {
                                      // 格式变更时可能需要更新选择状态
                                      _handleSelectionChange();
                                    },
                                    onSettingCreated: (settingItem) {
                                      // 处理设定创建成功 - 现在后端保存已在detail组件内部处理
                                      AppLogger.i('SceneEditor', '设定创建成功: ${settingItem.name}');
                                      // 可以在这里刷新侧边栏设定列表或做其他UI更新
                                    },
                                    onSnippetCreated: (snippet) {
                                      // 处理片段创建成功
                                      AppLogger.i('SceneEditor', '片段创建成功: ${snippet.title}');
                                      // 可以在这里刷新片段列表或做其他操作
                                    },
                                    onStreamingGenerationStarted: (request, model) {
                                      // 处理流式生成开始
                                      _handleStreamingGenerationStarted(request, model);
                                    },
                                    targetKey: _toolbarTargetKey,
                                  ),
                                ),
                              // AI生成工具栏
                              if (_showAIToolbar && _isEditorFullyInitialized)
                                Positioned(
                                  child: Builder(
                                    builder: (context) {
                                      // 检测是否位于前三行，参考写作工具栏逻辑
                                      bool isInFirstThreeLines = false;
                                      try {
                                        final selection = widget.controller.selection;
                                        final document = widget.controller.document;
                                        final plainText = document.toPlainText();
                                        final pos = selection.isCollapsed 
                                            ? selection.baseOffset 
                                            : selection.start;
                                        final safePos = pos.clamp(0, plainText.length);
                                        final before = plainText.substring(0, safePos);
                                        final lineBreaks = '\n'.allMatches(before).length;
                                        final lineNumber = lineBreaks + 1; // 1-based
                                        isInFirstThreeLines = lineNumber <= 3;
                                      } catch (_) {
                                        isInFirstThreeLines = false;
                                      }

                                      final bool showAbove = !isInFirstThreeLines; // 前三行强制下方
                                      final double offsetBelow = isInFirstThreeLines ? 180.0 : 30.0; // 参考写作工具栏

                                      return AIGenerationToolbar(
                                        layerLink: _aiToolbarLayerLink,
                                        onApply: _handleApplyGeneration,
                                        onRetry: _handleRetryGeneration,
                                        onDiscard: _handleDiscardGeneration,
                                        onSection: _handleSectionGeneration,
                                        onStop: _handleStopGeneration,
                                        wordCount: _aiGeneratedWordCount,
                                        modelName: _aiModelName,
                                        isGenerating: _isAIGenerating,
                                        showAbove: showAbove,
                                        offsetBelow: offsetBelow,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // 🚀 修改：动态宽度的占位空间 - 根据折叠状态调整
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: _isSummaryCollapsed 
                              ? (_summaryCollapsedWidth + _summarySpacing)
                              : (_summaryExpandedWidth + _summarySpacing),
                        ),
                      ],
                    ),
                    
                    // 🚀 修改：摘要区域 - 支持折叠/展开动画
                    if (_isSummaryCollapsed)
                      // 🚀 折叠状态：固定位置的悬浮书签
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _buildCollapsedSummary(theme, isEditorOrSummaryFocused),
                      )
                    else
                      // 🚀 展开状态：完整摘要区域
                      ValueListenableBuilder<double>(
                        valueListenable: _summaryTopOffsetVN,
                        builder: (context, offsetY, child) {
                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            top: offsetY,
                            right: 0,
                            bottom: 0,
                            width: _summaryExpandedWidth,
                            child: child!,
                          );
                        },
                        child: Container(
                          key: _summaryKey,
                          margin: const EdgeInsets.only(left: 0),
                          constraints: const BoxConstraints(
                            minHeight: 120,
                          ),
                          child: _buildSummaryArea(theme, isEditorOrSummaryFocused),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16), // 内容和底部间距
              ],
            ),
          ),
        ),
      );

  }
  
  Widget _buildSceneHeader(ThemeData theme, bool isFocused) {

      return Padding(
        // 移除底部 padding，由 SizedBox 控制
        padding: const EdgeInsets.only(bottom: 0.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, // 确保垂直居中对齐
          children: [
            // 添加场景序号
            if (widget.sceneIndex != null)
              Text(
                _getSceneIndexText(),
                style: WebTheme.getAlignedTextStyle(
                  baseStyle: theme.textTheme.titleSmall?.copyWith(
                    color: isFocused || widget.isActive
                        ? WebTheme.getTextColor(context)
                        : WebTheme.getSecondaryTextColor(context),
                    fontWeight: FontWeight.w600,
                  ) ?? const TextStyle(),
                ),
              ),
            Text(
              widget.title,
              style: WebTheme.getAlignedTextStyle(
                baseStyle: theme.textTheme.titleSmall?.copyWith(
                  color: isFocused || widget.isActive
                      ? WebTheme.getTextColor(context)
                      : WebTheme.getSecondaryTextColor(context),
                  fontWeight: FontWeight.w600,
                ) ?? const TextStyle(),
              ),
            ),
            const Spacer(),
            if (!widget.wordCount.isNaN)
              Text(
                widget.wordCount.toString(),
                style: WebTheme.getAlignedTextStyle(
                  baseStyle: theme.textTheme.bodySmall?.copyWith(
                    color: WebTheme.getSecondaryTextColor(context),
                    fontSize: 11,
                  ) ?? const TextStyle(),
                ),
              ),
          ],
        ),
      );

  }

  // 添加获取场景序号文本的方法
  String _getSceneIndexText() {
    if (widget.sceneIndex == null) return '';
    
    // 使用中文数字表示场景序号
    final List<String> chineseNumbers = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    
    if (widget.sceneIndex! <= 10) {
      return '场景${chineseNumbers[widget.sceneIndex!]} · ';
    } else if (widget.sceneIndex! < 20) {
      return '场景十${chineseNumbers[widget.sceneIndex! - 10]} · ';
    } else {
      // 对于更大的数字，直接使用阿拉伯数字
      return '场景${widget.sceneIndex} · ';
    }
  }

  /// 构建动态跟随选择区域的LayerLink目标
  /// 🚀 修复：使用实际的文档位置计算，而不是估算
  Widget _buildEmbeddedLayerLinkTarget() {
    final selection = widget.controller.selection;
    
    // 只有在有选择时才显示目标
    if (selection.isCollapsed) {
      return const SizedBox.shrink();
    }
    
    //////AppLogger.d('SceneEditor', '🎯 构建精确定位LayerLink目标 - 选择范围: ${selection.start}-${selection.end}');
    
    // 🚀 关键修复：计算选择区域的实际位置
    final targetPosition = _calculateSelectionPosition();
    
    return Positioned(
      // 保持同一个 Element，避免同帧出现多个 LeaderLayer
      // (移除动态 ValueKey，可用默认 key 策略)
      left: targetPosition.dx,
      top: targetPosition.dy,
      child: CompositedTransformTarget(
        link: _toolbarLayerLink,
        child: Container(
          key: _toolbarTargetKey,
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 构建AI工具栏的LayerLink目标
  Widget _buildEmbeddedAILayerLinkTarget() {
    // 当AI工具栏需要显示时，始终创建目标点
    if (!_showAIToolbar || !_isEditorFullyInitialized) {
      return const SizedBox.shrink();
    }

    final selection = widget.controller.selection;
    
    // 🚀 修复：获取编辑器宽度，X坐标始终保持在中间
    final RenderBox? editorBox = _editorContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (editorBox == null) {
      return const SizedBox.shrink();
    }
    
    // X坐标固定在编辑器中间
    final centerX = editorBox.size.width / 2;
    double targetY;

    if (selection.isCollapsed) {
      // 🚀 当没有文本选择时（光标折叠），只计算Y坐标
      try {
        final document = widget.controller.document;
        final plainText = document.toPlainText();
        final cursorOffset = selection.baseOffset;
        
        // 计算光标前的文本和行数
        final textBeforeCursor = plainText.substring(0, min(cursorOffset, plainText.length));
        final lines = textBeforeCursor.split('\n');
        final lineCount = lines.length - 1;
        
        // 获取编辑器设置
        final editorSettings = widget.editorSettings ?? const EditorSettings();
        final lineHeight = editorSettings.fontSize * editorSettings.lineSpacing;
        
        // 只计算Y坐标，基于光标所在行
        targetY = editorSettings.paddingVertical + (lineCount * lineHeight);
        
        //AppLogger.d('SceneEditor', '🎯 AI工具栏位置: X=$centerX(固定中间), Y=$targetY, 行数=$lineCount');
      } catch (e) {
        AppLogger.e('SceneEditor', '计算光标Y位置失败', e);
        // 回退到编辑器中下部位置
        targetY = editorBox.size.height * 0.8;
      }
    } else {
      // 有文本选择时，计算选择区域的Y坐标
      final selectionPosition = _calculateSelectionPosition();
      targetY = selectionPosition.dy;
    }

    final targetPosition = Offset(centerX, targetY);

    // === 二次修正：如果工具栏不在可视区域内，则强制居中显示 ===
    try {
      final viewportSize = MediaQuery.of(context).size;
      final RenderBox? editorBox2 = _editorContentKey.currentContext?.findRenderObject() as RenderBox?;
      if (editorBox2 != null) {
        final editorGlobal = editorBox2.localToGlobal(Offset.zero);

        // 与 AIGenerationToolbar 的偏移策略保持一致
        bool isInFirstThreeLines = false;
        try {
          final selection2 = widget.controller.selection;
          final document2 = widget.controller.document;
          final plain2 = document2.toPlainText();
          final pos2 = selection2.isCollapsed ? selection2.baseOffset : selection2.start;
          final safe2 = pos2.clamp(0, plain2.length);
          final before2 = plain2.substring(0, safe2);
          final lineBreaks2 = '\n'.allMatches(before2).length;
          final lineNumber2 = lineBreaks2 + 1; // 1-based
          isInFirstThreeLines = lineNumber2 <= 3;
        } catch (_) {
          isInFirstThreeLines = false;
        }

        final bool showAbove = !isInFirstThreeLines; // 与构建处一致
        final double offsetBelow = isInFirstThreeLines ? 180.0 : 30.0; // 与构建处一致
        final double offsetAbove = -60.0; // AIGenerationToolbar 默认
        final double followerOffsetY = showAbove ? offsetAbove : offsetBelow;

        // 估算"工具栏顶部"的全局Y坐标
        final double followerTopGlobalY = editorGlobal.dy + targetPosition.dy + followerOffsetY;

        // 若顶部超出屏幕，或大幅低于屏幕底部，则将其放到屏幕中间
        final double topGuard = 8.0;
        final double bottomGuard = viewportSize.height - 8.0;
        if (followerTopGlobalY < topGuard || followerTopGlobalY > bottomGuard) {
          final double screenCenterY = viewportSize.height / 2;
          // 反推目标点本地Y：editorGlobal + correctedY + followerOffsetY = screenCenterY
          final double correctedLocalY = screenCenterY - editorGlobal.dy - followerOffsetY;
          // 约束在编辑器内容内部
          targetY = correctedLocalY.clamp(0.0, editorBox2.size.height);
        }
      }
    } catch (_) {
      // 忽略修正失败，使用原位置
    }

    return Positioned(
      key: ValueKey('ai_target_${targetPosition.dx}_${targetY}_${selection.baseOffset}_${selection.extentOffset}'),
      left: targetPosition.dx,
      top: targetY,
      child: CompositedTransformTarget(
        link: _aiToolbarLayerLink,
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 🚀 新增：精确计算选择区域在编辑器中的位置
  Offset _calculateSelectionPosition() {
    try {
      final selection = widget.controller.selection;
      if (selection.isCollapsed) {
        ////AppLogger.d('SceneEditor', '❌ 选择已折叠，返回默认位置');
        return Offset.zero;
      }

      // 获取编辑器的渲染对象
      final RenderBox? editorBox = _editorContentKey.currentContext?.findRenderObject() as RenderBox?;
      if (editorBox == null) {
        ////AppLogger.d('SceneEditor', '❌ 编辑器渲染对象为空，返回默认位置');
        return Offset.zero;
      }

      // 🚀 关键修复：使用基于行数的精确计算，避免TextPainter的累积误差
      final document = widget.controller.document;
      final plainText = document.toPlainText();
      
      // 获取选择开始位置的文本
      final textBeforeSelection = plainText.substring(0, min(selection.start, plainText.length));
      
      // 🚀 使用编辑器设置获取准确的样式信息
      final editorSettings = widget.editorSettings ?? const EditorSettings();
      
      // 🚀 关键修复：计算行数和位置，使用更准确的方法
      final lines = textBeforeSelection.split('\n');
      final lineCount = lines.length - 1; // 减1因为最后一行不算换行
      final lastLineLength = lines.last.length;
      
      // 🚀 计算实际的行高（考虑编辑器的实际渲染）
      final actualLineHeight = editorSettings.fontSize * editorSettings.lineSpacing;
      
      // 🚀 关键修复：使用编辑器实际高度和文本总行数来计算比例因子
      final totalLines = plainText.split('\n').length;
      final actualEditorHeight = editorBox.size.height - (editorSettings.paddingVertical * 2);
      final heightPerLine = actualEditorHeight / totalLines;
      
      // 🚀 使用修正后的行高，在长文档中使用实际渲染的行高
      final correctedLineHeight = max(heightPerLine, actualLineHeight * 0.8); // 使用较小值，但有最小限制
      
      // 🚀 计算Y位置（基于修正的行高）
      final estimatedY = editorSettings.paddingVertical + (lineCount * correctedLineHeight);
      
      // 🚀 计算X位置：始终使用编辑器内容区域的中心，让工具栏水平居中
      final contentWidth = min(editorBox.size.width, editorSettings.maxLineWidth);
      final estimatedX = (contentWidth / 2) + editorSettings.paddingHorizontal;  // 内容区域中心
      final charWidth = editorSettings.fontSize * 0.6; // 仅用于日志
      
      final finalPosition = Offset(estimatedX, estimatedY);
      
      // 🚀 详细日志，包含修正信息
      //////AppLogger.d('SceneEditor', '✅ 修正选择区域位置: ${finalPosition.dx}, ${finalPosition.dy}');
      //////AppLogger.d('SceneEditor', '   选择位置: ${selection.start}-${selection.end}, 文本长度: ${textBeforeSelection.length}');
      //////AppLogger.d('SceneEditor', '   行数统计: 当前行=$lineCount, 总行数=$totalLines, 最后行长度=$lastLineLength');
      //////AppLogger.d('SceneEditor', '   编辑器尺寸: ${editorBox.size}, 实际内容高度: $actualEditorHeight');
      //////AppLogger.d('SceneEditor', '   行高计算: 理论行高=$actualLineHeight, 实际行高=$heightPerLine, 修正行高=$correctedLineHeight');
      //////AppLogger.d('SceneEditor', '   位置计算: X=$estimatedX (字符宽度=$charWidth), Y=$estimatedY');
      
      return finalPosition;
      
    } catch (e) {
      AppLogger.e('SceneEditor', '❌ 精确计算选择区域位置失败: $e');
      return Offset.zero;
    }
  }



  /// 🚀 构建完整的QuillEditorConfig，充分利用编辑器设置
  QuillEditorConfig _buildQuillEditorConfig(EditorSettings editorSettings) {
    return QuillEditorConfig(
      // 基础设置
      minHeight: editorSettings.minEditorHeight < 1200.0 ? 1200.0 : editorSettings.minEditorHeight,
      maxHeight: null, // 让场景编辑器自由扩展
      maxContentWidth: editorSettings.maxLineWidth,
      
      // 占位符和焦点
      placeholder: '开始写作...',
      autoFocus: false, // 禁用自动聚焦以减少不必要的渲染
      
      // 布局和间距
      padding: EdgeInsets.symmetric(
        vertical: editorSettings.paddingVertical,
        horizontal: editorSettings.paddingHorizontal,
      ),
      expands: false, // 不自动扩展，保持控制
      
      // 滚动设置
      scrollable: editorSettings.smoothScrolling,
      scrollPhysics: editorSettings.smoothScrolling 
          ? const BouncingScrollPhysics() 
          : const ClampingScrollPhysics(),
      
      // 文本设置
      textCapitalization: TextCapitalization.sentences,
      
      // 光标和选择
      showCursor: true,
      paintCursorAboveText: editorSettings.highlightActiveLine,
      enableInteractiveSelection: true,
      enableSelectionToolbar: true,
      
      // 键盘设置
      keyboardAppearance: editorSettings.darkModeEnabled 
          ? Brightness.dark 
          : Brightness.light,
      
      // 自定义样式和交互
      customStyles: _buildCustomStyles(editorSettings),
      customStyleBuilder: _buildCombinedCustomStyleBuilder(),
      customRecognizerBuilder: SettingReferenceInteractionMixin.getCustomRecognizerBuilder(
        onSettingReferenceClicked: (settingId) {
          AppLogger.i('SceneEditor', '🖱️ 设定引用被点击: $settingId');
          _handleSettingReferenceClicked(settingId);
        },
        onSettingReferenceHovered: null,
        onSettingReferenceHoverEnd: null,
      ),
      
      // 行为设置
      detectWordBoundary: true,
      enableAlwaysIndentOnTab: false,
      floatingCursorDisabled: !editorSettings.useTypewriterMode,
      
      // 其他高级设置
      onTapOutsideEnabled: true,
      disableClipboard: false,
      enableScribble: false, // 暂时禁用涂鸦功能
    );
  }

  // 为编辑器添加焦点处理
  Widget _buildEditor(ThemeData theme, bool isFocused) {

      // 获取编辑器设置
      final editorSettings = widget.editorSettings ?? const EditorSettings();
      
      // 在编辑器区域添加MouseRegion
      return MouseRegion(
        //cursor: SystemMouseCursors.text, // 在编辑器区域显示文本光标
        hitTestBehavior: HitTestBehavior.deferToChild, // 优先让子组件处理事件
        child: Container(
          key: _editorContentKey,
          constraints: BoxConstraints(
            maxWidth: editorSettings.maxLineWidth,
            minHeight: editorSettings.minEditorHeight < 1200.0 ? 1200.0 : editorSettings.minEditorHeight,
          ),
          // 使用动态背景色，兼容暗黑 / 亮色主题
          color: WebTheme.getSurfaceColor(context),
          child: Theme(
            data: theme.copyWith(
              // 确保QuillEditor的占位符没有下划线
              inputDecorationTheme: const InputDecorationTheme(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                hintStyle: TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.none, // 明确去掉下划线
                ),
              ),
            ),
            child: QuillEditor.basic(
              // 关键修复：使用依赖 editorSettings 的动态 Key，确保编辑器设置更新后立即重建
              key: ValueKey('editor_${widget.sceneId}_${widget.editorSettings?.hashCode ?? 0}'),
              controller: widget.controller,
              focusNode: _focusNode, // 使用编辑器的 FocusNode
              scrollController: _editorScrollController, // 使用实例变量的滚动控制器
              config: _buildQuillEditorConfig(editorSettings),
            ),
          ),
        ),
      );

  }

  /// 根据编辑器设置构建自定义样式
  DefaultStyles _buildCustomStyles(EditorSettings settings) {
    final baseTextStyle = TextStyle(
      color: WebTheme.getTextColor(context),
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Source Han Sans SC',
        'Source Han Sans CN',
        'Droid Sans Fallback',
        'sans-serif'
      ],
      fontWeight: settings.fontWeight,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      decoration: TextDecoration.none,
    );

    return DefaultStyles(
      // 段落样式 - 🚀 修复：移除默认左缩进，避免大空白
      paragraph: DefaultTextBlockStyle(
        baseTextStyle,
        HorizontalSpacing.zero, // 不使用默认缩进
        settings.paragraphSpacing > 0 
            ? VerticalSpacing(settings.paragraphSpacing, 0) 
            : VerticalSpacing.zero, // 🚀 修复：段落间距为0时使用zero
        VerticalSpacing.zero, // 🚀 修复：确保行间距也为zero
        null,
      ),
      // 占位符样式 - 🚀 修复：移除默认左缩进
      placeHolder: DefaultTextBlockStyle(
        baseTextStyle.copyWith(
          color: WebTheme.getSecondaryTextColor(context),
        ),
        HorizontalSpacing.zero, // 不使用默认缩进
        settings.paragraphSpacing > 0 
            ? VerticalSpacing(settings.paragraphSpacing, 0) 
            : VerticalSpacing.zero, // 🚀 修复：段落间距为0时使用zero
        VerticalSpacing.zero, // 🚀 修复：确保行间距也为zero
        null,
      ),
      // 粗体样式
      bold: baseTextStyle.copyWith(
        fontWeight: FontWeight.bold,
      ),
      // 斜体样式
      italic: baseTextStyle.copyWith(
        fontStyle: FontStyle.italic,
      ),
      // 下划线样式
      underline: baseTextStyle.copyWith(
        decoration: TextDecoration.underline,
      ),
      // 删除线样式
      strikeThrough: baseTextStyle.copyWith(
        decoration: TextDecoration.lineThrough,
      ),
      // 链接样式
      link: baseTextStyle.copyWith(
        color: settings.darkModeEnabled ? Colors.lightBlue : Colors.blue,
        decoration: TextDecoration.underline,
      ),
      // 标题样式 - 🚀 修复：移除默认左缩进
      h1: DefaultTextBlockStyle(
        baseTextStyle.copyWith(
          fontSize: settings.fontSize * 2.0,
          fontWeight: FontWeight.bold,
        ),
        HorizontalSpacing.zero, // 不使用默认缩进
        settings.paragraphSpacing > 0 
            ? VerticalSpacing(settings.paragraphSpacing * 2, 0) 
            : VerticalSpacing.zero, // 🚀 修复：段落间距为0时使用zero
        VerticalSpacing.zero, // 🚀 修复：确保行间距也为zero
        null,
      ),
      h2: DefaultTextBlockStyle(
        baseTextStyle.copyWith(
          fontSize: settings.fontSize * 1.5,
          fontWeight: FontWeight.bold,
        ),
        HorizontalSpacing.zero, // 不使用默认缩进
        settings.paragraphSpacing > 0 
            ? VerticalSpacing(settings.paragraphSpacing * 1.5, 0) 
            : VerticalSpacing.zero, // 🚀 修复：段落间距为0时使用zero
        VerticalSpacing.zero, // 🚀 修复：确保行间距也为zero
        null,
      ),
      h3: DefaultTextBlockStyle(
        baseTextStyle.copyWith(
          fontSize: settings.fontSize * 1.25,
          fontWeight: FontWeight.bold,
        ),
        HorizontalSpacing.zero, // 不使用默认缩进
        settings.paragraphSpacing > 0 
            ? VerticalSpacing(settings.paragraphSpacing, 0) 
            : VerticalSpacing.zero, // 🚀 修复：段落间距为0时使用zero
        VerticalSpacing.zero, // 🚀 修复：确保行间距也为zero
        null,
      ),
      // 内联代码样式
      inlineCode: InlineCodeStyle(
        backgroundColor: Colors.transparent,
        radius: const Radius.circular(3),
        style: baseTextStyle.copyWith(
          fontFamily: 'monospace',
        ),
      ),
      // 列表样式 - 🚀 保留缩进：列表项需要缩进来显示层级
      lists: DefaultListBlockStyle(
        baseTextStyle,
        HorizontalSpacing(settings.indentSize, 0), // 列表项保持缩进
        VerticalSpacing(settings.paragraphSpacing / 2, 0),
        VerticalSpacing(0, 0),
        null,
        null,
      ),
      // 引用样式 - 🚀 保留缩进：引用通常需要视觉上的缩进
      quote: DefaultTextBlockStyle(
        baseTextStyle.copyWith(
          color: WebTheme.getSecondaryTextColor(context),
          fontStyle: FontStyle.italic,
        ),
        HorizontalSpacing(settings.indentSize, 0), // 引用保持缩进
        VerticalSpacing(settings.paragraphSpacing, 0),
        VerticalSpacing(0, 0),
        BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 4,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 🎯 优化：只在真正需要时处理设定引用，避免频繁调用
    // 检查是否有实质性的依赖变化
    final hasSignificantChange = _hasSignificantDependencyChange();
    if (hasSignificantChange) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isProcessingSettingReferences) {
          ////AppLogger.d('SceneEditor', '🔄 依赖变化触发设定引用处理: ${widget.sceneId}');
          _processSettingReferencesDebounced(); // 使用防抖版本
        }
      });
    }
  }

  @override
  void didUpdateWidget(SceneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 🎯 优化：只在组件内容真正更新时处理设定引用
    final hasContentChange = oldWidget.sceneId != widget.sceneId ||
                           oldWidget.controller != widget.controller;
    
    if (hasContentChange && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isProcessingSettingReferences) {
          ////AppLogger.d('SceneEditor', '🔄 组件更新触发设定引用处理: ${widget.sceneId}');
          _processSettingReferencesDebounced(); // 使用防抖版本
        }
      });
    }

    // 🛠️ 当父组件替换了 controller（例如占位控制器异步解析完成后），
    // 需要把监听器从旧 controller 上移除并绑定到新的 controller，
    // 否则选区变化和文档变化都不会再触发当前组件的回调，
    // 从而导致 SelectionToolbar 无法弹出。
    if (oldWidget.controller != widget.controller) {
      // 移除旧 controller 的监听
      oldWidget.controller.removeListener(_handleSelectionChange);

      // 取消旧 controller 的 document 订阅
      _docChangeSub?.cancel();

      // 绑定新 controller 的监听
      widget.controller.addListener(_handleSelectionChange);

      // 重新订阅 document.changes 并保存引用
      _docChangeSub = widget.controller.document.changes.listen(_onDocumentChange);
    }
  }

  // 🎯 新增：检查是否有实质性的依赖变化
  bool _hasSignificantDependencyChange() {
    // 可以根据需要检查具体的依赖变化
    // 目前简化处理，减少不必要的触发
    return true; // 暂时保持原有行为，后续可以进一步优化
  }

  Widget _buildSummaryArea(ThemeData theme, bool isFocused) {
    // 🚀 只在展开状态下调用此方法，移除条件判断
    return Container(
      // 移除 margin，由 Row 的 SizedBox 控制
      padding: const EdgeInsets.all(12), // 调整摘要区内边距
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 使用动态表面色
        borderRadius: BorderRadius.circular(8), // 给摘要区本身加圆角
        // 🚀 新增：添加微妙的阴影效果，当摘要处于sticky状态时更明显
        boxShadow: _isSummarySticky ? [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max, // 🚀 修复：使用max避免溢出
        children: [
          // 摘要标题和右上角按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center, // 确保垂直居中对齐
            children: [
              Expanded(
                child: Text(
                  '摘要',
                  style: WebTheme.getAlignedTextStyle(
                    baseStyle: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isFocused || widget.isActive
                          ? WebTheme.getTextColor(context)
                          : WebTheme.getSecondaryTextColor(context),
                    ) ?? const TextStyle(),
                  ),
                ),
              ),
              // 🚀 新增：折叠按钮
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
                tooltip: '折叠摘要',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  AppLogger.i('SceneEditor', '🔵 点击折叠按钮，折叠摘要');
                  setState(() {
                    _isSummaryCollapsed = true;
                  });
                  _saveSummaryCollapsedState(true);
                  AppLogger.i('SceneEditor', '🔵 折叠状态已设置: $_isSummaryCollapsed');
                },
              ),
              const SizedBox(width: 4),
              // 摘要操作按钮（刷新、AI生成） - 移到右上角
              _buildSummaryActionButtons(theme, isFocused),
            ],
          ),

          const SizedBox(height: 8),

          // 🚀 优化：摘要内容 - 使用Expanded让其填充剩余空间
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WebTheme.getSurfaceColor(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                      controller: widget.summaryController,
                      focusNode: _summaryFocusNode,
                      style: WebTheme.getAlignedTextStyle(
                        baseStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: WebTheme.getTextColor(context), // 改为主要文字颜色
                          fontSize: 13,
                          height: 1.4,
                        ) ?? const TextStyle(),
                      ),
                      // 🚀 改为自适应高度：不限制最大行数
                      maxLines: null,
                      minLines: 2,
                      keyboardType: TextInputType.multiline, // 支持多行输入
                      textInputAction: TextInputAction.newline, // 支持换行
                    decoration: WebTheme.getBorderlessInputDecoration(
                      hintText: '添加场景摘要...',
                      context: context, // 传递context以设置正确的hintStyle
                    ),
                    // 🚀 自适应模式下禁用内部滚动，让外层滚动容器接管
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    onChanged: (value) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 1200), () {
                        // 🚀 新增：检查控制器是否仍然有效
                        if (!mounted || widget.summaryController.text != value) {
                          AppLogger.v('SceneEditor', '摘要控制器已失效或内容已变化，跳过保存: ${widget.sceneId}');
                          return;
                        }
                        
                        if (mounted &&
                            widget.actId != null &&
                            widget.chapterId != null &&
                            widget.sceneId != null) {
                          AppLogger.i('SceneEditor', '通过onChange保存摘要: ${widget.sceneId}');
                          widget.editorBloc.add(editor_bloc.UpdateSummary(
                            novelId: widget.editorBloc.novelId,
                            actId: widget.actId!,
                            chapterId: widget.chapterId!,
                            sceneId: widget.sceneId!,
                            summary: value,
                            shouldRebuild: true, // 改为true，确保UI更新和完整保存
                          ));
                        }
                        
                        // 🚀 新增：内容变化时更新摘要高度
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _updateSummaryHeight();
                            _updateSummaryPosition();
                          }
                        });
                      });
                    },
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 🚀 新增：摘要操作按钮区域
          _buildSummaryBottomActions(theme, isFocused),
        ],
      ),
    );
  }

  // 🚀 新增：折叠状态下的摘要UI（悬浮书签样式）
  Widget _buildCollapsedSummary(ThemeData theme, bool isFocused) {
    return Align(
      alignment: Alignment.topCenter, // 🚀 顶部对齐
      child: Container(
        width: 36, // 🚀 更窄的宽度，像书签一样
        height: 48, // 🚀 固定高度，只显示箭头
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomLeft: Radius.circular(8),
          ),
          border: Border.all(
            color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: WebTheme.getShadowColor(context, opacity: 0.15),
              blurRadius: 8,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Center(
          child: IconButton(
            icon: Icon(
              Icons.chevron_left,
              size: 20,
              color: WebTheme.getPrimaryColor(context),
            ),
            tooltip: '展开摘要',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              AppLogger.i('SceneEditor', '🔵 点击展开按钮');
              setState(() {
                _isSummaryCollapsed = false;
              });
              _saveSummaryCollapsedState(false);
            },
          ),
        ),
      ),
    );
  }
  
  // 🚀 新增：摘要底部操作按钮区域
  Widget _buildSummaryBottomActions(ThemeData theme, bool isFocused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start, // 🚀 改为左对齐，避免空间分散
      children: [
        // 🚀 最左边：更多操作按钮（三点菜单）
        if (widget.actId != null && widget.chapterId != null && widget.sceneId != null)
          MenuBuilder.buildSceneMenu(
            context: context,
            editorBloc: widget.editorBloc,
            actId: widget.actId!,
            chapterId: widget.chapterId!,
            sceneId: widget.sceneId!,
          ),
        
        if (widget.actId != null && widget.chapterId != null && widget.sceneId != null)
          const SizedBox(width: 4), // 🚀 减小间距
        
        // // 标签按钮
        // _SummaryActionButton(
        //   icon: Icons.label_outline,
        //   label: '标签',
        //   tooltip: '添加标签',
        //   onPressed: () {/* TODO */},
        // ),
        
        // const SizedBox(width: 4), // 🚀 减小间距
        
        // // Codex按钮
        // _SummaryActionButton(
        //   icon: Icons.lan_outlined,
        //   label: 'Codex',
        //   tooltip: '关联 Codex',
        //   onPressed: () {/* TODO */},
        // ),
        
        // 场景节拍按钮
        const SizedBox(width: 4), // 🚀 减小间距
        _SummaryActionButton(
          icon: Icons.auto_fix_high,
          label: '节拍',
          tooltip: '场景节拍生成',
          onPressed: () {
            if (widget.actId != null && 
                widget.chapterId != null && 
                widget.sceneId != null) {
              _showSceneBeatPanel();
            }
          },
        ),
        
        // AI生成场景按钮（仅在有摘要内容时显示）
        if (widget.summaryController.text.isNotEmpty) ...[
          const SizedBox(width: 4), // 🚀 减小间距
          _SummaryActionButton(
            icon: Icons.auto_stories,
            label: 'AI生成',
            tooltip: '从摘要生成场景内容',
            onPressed: () {
              if (widget.actId != null && 
                  widget.chapterId != null && 
                  widget.sceneId != null) {
                // 获取布局管理器并打开AI生成面板
                final layoutManager = Provider.of<EditorLayoutManager>(context, listen: false);
                
                // 保存当前摘要到EditorBloc中，以便AI生成面板可以获取到
                widget.editorBloc.add(
                  editor_bloc.SetPendingSummary(
                    summary: widget.summaryController.text,
                  ),
                );
                
                // 显示AI生成面板
                layoutManager.toggleAISceneGenerationPanel();
              }
            },
          ),
        ],
      ],
    );
  }

  // 新增：摘要区域右上角的操作按钮
  Widget _buildSummaryActionButtons(ThemeData theme, bool isFocused) {
    // 使用 Row + IconButton 实现
    return Row(
      mainAxisSize: MainAxisSize.min, // 重要：避免 Row 占用过多空间
      children: [
        IconButton(
          icon: Icon(Icons.refresh, size: 18, color: WebTheme.getSecondaryTextColor(context)),
          tooltip: '刷新摘要',
          onPressed: () {
            // 实现刷新摘要逻辑
            if (widget.summaryController.text.isNotEmpty &&
                widget.actId != null &&
                widget.chapterId != null &&
                widget.sceneId != null &&
                mounted) {
              // 🚀 新增：检查控制器是否仍然有效
              try {
                // 尝试访问控制器文本以验证其有效性
                final currentText = widget.summaryController.text;
                
                AppLogger.i('SceneEditor', '通过刷新按钮保存摘要: ${widget.sceneId}');
                widget.editorBloc.add(editor_bloc.UpdateSummary(
                  novelId: widget.editorBloc.novelId,
                  actId: widget.actId!,
                  chapterId: widget.chapterId!,
                  sceneId: widget.sceneId!,
                  summary: currentText,
                  shouldRebuild: true, // 修改为true，确保完整保存到后端
                ));
              } catch (e) {
                AppLogger.w('SceneEditor', '摘要控制器已失效，跳过刷新保存: ${widget.sceneId}', e);
              }
            }
          },
          splashRadius: 18,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          // 添加悬停效果
          hoverColor: WebTheme.getSurfaceColor(context),
        ),
        IconButton(
          icon: Icon(Icons.auto_awesome, size: 18, color: WebTheme.getSecondaryTextColor(context)),
          tooltip: 'AI 生成摘要',
          onPressed: () {
            // 使用新的摘要生成器
            if (widget.actId != null && 
                widget.chapterId != null && 
                widget.sceneId != null) {
              _showSummaryGenerator();
            }
          },
          splashRadius: 18,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          // 添加悬停效果
          hoverColor: WebTheme.getSurfaceColor(context),
        ),
      ],
    );
  }



  // 🚀 优化：添加SettingBloc状态监听，处理设定引用
  void _setupSettingBlocListener() {
    final novelId = _getNovelId();
    if (novelId == null) {
      AppLogger.w('SceneEditor', '⚠️ 无法获取小说ID，跳过设定引用监听设置');
      return;
    }
    
    AppLogger.i('SceneEditor', '🎯 设置SettingBloc监听器 - 场景: ${widget.sceneId}, 小说: $novelId');
    
    // 🚀 新增：立即检查当前状态，如果数据已存在则直接处理
    final currentState = context.read<SettingBloc>().state;
    if (currentState.itemsStatus == SettingStatus.success && currentState.items.isNotEmpty) {
      AppLogger.i('SceneEditor', '✅ 设定数据已就绪，立即处理引用 - 条目数量: ${currentState.items.length}');
      // 延迟一帧执行，确保组件已完全初始化
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAndProcessSettingReferences();
        }
      });
    } else {
      AppLogger.i('SceneEditor', '⏳ 设定数据尚未就绪 - 状态: ${currentState.itemsStatus}, 条目数量: ${currentState.items.length}');
    }
    
    // 🚀 优化：设置流监听器，响应后续的数据更新
    context.read<SettingBloc>().stream.listen((state) {
      if (!mounted) return;
      
      // 当设定项目加载完成时，处理设定引用
      if (state.itemsStatus == SettingStatus.success && state.items.isNotEmpty) {
        AppLogger.i('SceneEditor', '🔄 设定数据更新，重新处理引用 - 场景: ${widget.sceneId}, 条目数量: ${state.items.length}');
        _checkAndProcessSettingReferences();
      }
    });
  }
  
  // 🎯 优化：防抖处理设定引用，避免频繁调用
  void _processSettingReferencesDebounced() {
    //if (true) return;
    // 如果正在处理设定引用，跳过新的请求
    if (_isProcessingSettingReferences) {
      AppLogger.v('SceneEditor', '⏭️ 正在处理设定引用，跳过新的请求: ${widget.sceneId}');
      return;
    }
    // 生成期间不处理设定引用，避免与流式变更抢占主线程
    if (_isAIGenerating) {
      AppLogger.v('SceneEditor', '⏭️ 生成中，跳过设定引用处理请求: ${widget.sceneId}');
      return;
    }
    
    // 🎯 新增：检查距离上次处理的时间间隔
    final now = DateTime.now();
    final timeSinceLastProcessing = now.difference(_lastProcessingTime);
    if (timeSinceLastProcessing < _minProcessingInterval) {
      AppLogger.v('SceneEditor', '⏭️ 处理间隔过短，跳过设定引用处理: ${widget.sceneId}');
      return;
    }
    
    // 🎯 恢复设定引用处理调用
    _settingReferenceProcessTimer?.cancel();
    _settingReferenceProcessTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isProcessingSettingReferences) {
        _lastProcessingTime = DateTime.now();
        _processSettingReferences();
      }
    });
  }
  
  // 🎯 优化：智能处理设定引用（使用防抖和状态检查）
  void _checkAndProcessSettingReferences() {
    if (!mounted || _isProcessingSettingReferences || _isAIGenerating) {
      return;
    }
    
    //AppLogger.i('SceneEditor', '🎯 智能处理设定引用: ${widget.sceneId}');
    
    try {
      // 使用防抖机制避免频繁调用
      _processSettingReferencesDebounced();
    } catch (e) {
      AppLogger.w('SceneEditor', '处理设定引用失败', e);
    }
  }
  

  // 🚀 新增：检查元素是否在视口中可见
 
  
  // 处理设定引用 - Flutter原生实现
  void _processSettingReferences() {
    try {
      if (!mounted) return;
      
      // 🎯 新增：完整内容相等判断，包括样式信息
      final currentDeltaContent = jsonEncode(widget.controller.document.toDelta().toJson());
      final currentText = widget.controller.document.toPlainText();
      
      final int textHash = currentText.hashCode;
      if (textHash == _lastSettingHash) {
        // 文本无实质改动，跳过
        _isProcessingSettingReferences = false;
        return;
      }
      
      // 首先检查完整Delta内容是否相等（包含样式）
      if (currentDeltaContent == _lastProcessedDeltaContent) {
        ////AppLogger.d('SceneEditor', '⏭️ 场景内容完全相等，跳过设定引用处理');
        return;
      }
      
      // 其次检查纯文本内容是否相等（向后兼容）
      if (currentText == _lastProcessedText) {
        ////AppLogger.d('SceneEditor', '⏭️ 文本内容未变化，跳过设定引用处理');
        return;
      }
      
      // 🚀 关键修复：设置处理标志，避免样式变化触发保存
      _isProcessingSettingReferences = true;
      
      ////AppLogger.d('SceneEditor', '🔍 开始Flutter原生设定引用处理，文本长度: ${currentText.length}');
      ////AppLogger.d('SceneEditor', '📝 文本内容预览: ${currentText.length > 100 ? currentText.substring(0, 100) + "..." : currentText}');
      
      final settingState = context.read<SettingBloc>().state;
      final settingItems = settingState.items;
      
      AppLogger.i('SceneEditor', '📚 当前设定条目数量: ${settingItems.length}');
      // if (settingItems.isNotEmpty) {
      //   final validNames = settingItems.where((item) => item.name != null).map((item) => item.name!).join(', ');
      // }
      
      // 🚀 使用Flutter Quill原生Attribute系统处理设定引用
      SettingReferenceProcessor.processSettingReferences(
        document: widget.controller.document,
        settingItems: settingItems,
        controller: widget.controller,
      );
      
      // 🎯 更新：记录处理过的内容
      _lastProcessedText = currentText;
      _lastProcessedDeltaContent = currentDeltaContent;
      _lastSettingHash = textHash;
      
    } catch (e) {
      AppLogger.e('SceneEditor', 'Flutter原生设定引用处理失败', e);
    } finally {
      // 🚀 关键修复：无论成功失败都重置处理标志
      _isProcessingSettingReferences = false;
    }
  }
   

   
   // 处理设定引用点击
   void _handleSettingReferenceClicked(String settingId) {
     AppLogger.i('SceneEditor', '🖱️ 设定引用被点击: $settingId');
     
     final novelId = _getNovelId();
     if (novelId == null) {
       AppLogger.w('SceneEditor', '无法显示设定预览：缺少小说ID');
       return;
     }
     
     AppLogger.i('SceneEditor', '📋 设定引用详情: ID=$settingId, 小说=$novelId');
     
     // 🎯 显示设定预览卡片
     _showSettingPreviewCard(settingId, novelId);
     
     // 触发设定悬停回调
     //_handleSettingReferenceHovered(settingId);
   }

   /// 🎯 构建组合的自定义样式构建器
   /// 同时支持设定引用样式和AI生成内容样式
   TextStyle Function(Attribute) _buildCombinedCustomStyleBuilder() {
     return (Attribute attribute) {
       // 1. 处理设定引用样式（使用实际的悬停状态）
       final settingReferenceStyle = SettingReferenceInteractionMixin
           .getCustomStyleBuilderWithHover(hoveredSettingId: _hoveredSettingId)(attribute);
       
       // 2. 处理AI生成内容样式
       final aiGeneratedStyle = AIGeneratedContentProcessor
           .getCustomStyleBuilder()(attribute);
       
       // 3. 处理背景色属性（保持原有逻辑）
       if (attribute.key == 'background' && attribute.value != null) {
         final colorValue = attribute.value as String;
         
         try {
           // 解析颜色值（支持#FFF3CD格式）
           Color? backgroundColor;
           if (colorValue.startsWith('#')) {
             final hexColor = colorValue.substring(1);
             if (hexColor.length == 6) {
               backgroundColor = Color(int.parse('FF$hexColor', radix: 16));
             }
           }
           
           if (backgroundColor != null) {
             return TextStyle(backgroundColor: backgroundColor);
           }
         } catch (e) {
           AppLogger.w('SceneEditor', '解析背景色失败: $colorValue', e);
         }
       }
       
       // 4. 合并样式（优先级：AI生成 > 设定引用 > 其他）
       if (aiGeneratedStyle.color != null) {
         return aiGeneratedStyle;
       } else if (settingReferenceStyle.decoration != null) {
         return settingReferenceStyle;
       }
       
       // 返回空的TextStyle表示使用默认样式
       return const TextStyle();
     };
   }
   
   /// 显示设定预览卡片 - 使用通用管理器
   /// 
   /// 🎨 采用全局样式和主题的统一设定预览卡片
   /// 🚀 修复了Provider传递问题，确保详情卡片正常打开
   void _showSettingPreviewCard(String settingId, String novelId) {
     try {
       // 获取当前屏幕中心位置
       final screenSize = MediaQuery.of(context).size;
       final position = Offset(
         screenSize.width * 0.5, // 屏幕中心
         screenSize.height * 0.3, // 靠上一些
       );
       
       AppLogger.i('SceneEditor', '📍 显示设定预览卡片: $settingId');
       
       // 🚀 使用通用设定预览管理器，自动处理Provider传递问题
       SettingPreviewManager.show(
         context: context,
         settingId: settingId,
         novelId: novelId,
         position: position,
         onClose: () {
           ////AppLogger.d('SceneEditor', '设定预览卡片已关闭');
         },
         onDetailOpened: () {
           AppLogger.i('SceneEditor', '设定详情卡片已打开');
         },
       );
       
       AppLogger.i('SceneEditor', '✅ 设定预览卡片已显示');
       
     } catch (e) {
       AppLogger.e('SceneEditor', '显示设定预览卡片失败', e);
     }
   }

   /// 处理流式生成开始 - 支持统一AI模型
   void _handleStreamingGenerationStarted(UniversalAIRequest request, UnifiedAIModel model) {
     AppLogger.i('SceneEditor', '🚀 开始流式生成: ${request.requestType}, 模型: ${model.displayName} (公共:${model.isPublic})');
     // 🚀 若存在未应用的AI生成内容或隐藏文本，先自动应用为正文，避免并发生成导致上下文缺失
     try {
       final bool hasAIGen = AIGeneratedContentProcessor.hasAnyAIGeneratedContent(
         controller: widget.controller,
       );
       final bool hasHidden = AIGeneratedContentProcessor.hasAnyHiddenText(
         controller: widget.controller,
       );
       if (hasAIGen || hasHidden) {
         if (_isAIGenerating) {
           _handleStopGeneration();
         }
         _handleApplyGeneration();
       }
     } catch (_) {}
     
     // 🚀 新增：保存请求和统一模型配置，用于重试
     _lastAIRequest = request;
     _lastUnifiedModel = model;
     
     // 已移除 UserAIModelConfigModel 相关逻辑，现在使用 UnifiedAIModel
     
     AppLogger.i('SceneEditor', '💾 保存模型信息: ${model.displayName} (公共模型: ${model.isPublic})');
     
     // 获取当前选择范围
     final selection = widget.controller.selection;
     final selectedText = selection.isCollapsed ? '' : 
         widget.controller.document.toPlainText().substring(selection.start, selection.end);
     
     // 🚀 保存选中的文本，用于返回表单
     _lastSelectedText = selectedText;
     
     // 🆕 根据请求类型决定处理方式
     if ((request.requestType == AIRequestType.refactor || request.requestType == AIRequestType.summary) && !selection.isCollapsed) {
       // 重构或缩写：使用隐藏文本属性标记原选中的文本
       final mode = request.requestType == AIRequestType.refactor ? '重构' : '缩写';
       AppLogger.i('SceneEditor', '🫥 ${mode}模式：隐藏原选中文本 (${selectedText.length}字符)');
       AIGeneratedContentProcessor.markAsHidden(
         controller: widget.controller,
         startOffset: selection.start,
         length: selection.end - selection.start,
       );
       _lastInsertedOffset = selection.end; // 在隐藏文本后插入新内容
     } else {
       // 扩写或其他：在选中范围末尾插入新内容
       AppLogger.i('SceneEditor', '📝 扩写模式：在选中文本后插入新内容');
       _lastInsertedOffset = selection.end;
     }
     
     // 隐藏选择工具栏
     setState(() {
       _showToolbar = false;
       _showAIToolbar = true;
       _isAIGenerating = true;
       _aiModelName = model.displayName;
       _generatedText = '';
       _aiGeneratedWordCount = 0;
       _currentStreamIndex = 0;
       _pendingStreamText = '';
     });

     _aiGeneratedStartOffset = _lastInsertedOffset; // 记录AI生成内容的起始位置

     // 开始流式生成
     _startStreamingGeneration(request);
   }

   /// 开始流式生成
   Future<void> _startStreamingGeneration(UniversalAIRequest request) async {
     try {
       final universalAIRepository = context.read<UniversalAIRepository>();
       
       AppLogger.i('SceneEditor', '📡 发送流式AI请求');
       
       // 同步：如果是场景节拍生成，请先把浮动面板状态置为生成中
       try {
         final bool isSceneBeat = request.requestType == AIRequestType.sceneBeat;
         final String? sid = request.sceneId ?? widget.sceneId;
         if (isSceneBeat && sid != null && sid.isNotEmpty) {
           SceneBeatDataManager.instance.updateSceneStatus(sid, SceneBeatStatus.generating);
         }
       } catch (e) {
         AppLogger.w('SceneEditor', '同步场景节拍状态为生成中失败', e);
       }
       
       // 发送流式请求
       final stream = universalAIRepository.streamRequest(request);
       
       await for (final chunk in stream) {
         if (!mounted || !_isAIGenerating) {
           ////AppLogger.d('SceneEditor', '🛑 流式生成被中断: mounted=$mounted, _isAIGenerating=$_isAIGenerating');
           break;
         }
         
         // 🚀 修复：检查是否收到结束信号
         if (chunk.finishReason != null) {
           AppLogger.i('SceneEditor', '✅ 收到流式生成结束信号: ${chunk.finishReason}');
           // 立即停止生成状态
           setState(() {
             _isAIGenerating = false;
           });

           // 同步：如果是场景节拍生成，将面板状态置为已生成
           try {
             final bool isSceneBeat = request.requestType == AIRequestType.sceneBeat;
             final String? sid = request.sceneId ?? widget.sceneId;
             if (isSceneBeat && sid != null && sid.isNotEmpty) {
               SceneBeatDataManager.instance.updateSceneStatus(sid, SceneBeatStatus.generated);
             }
           } catch (e) {
             AppLogger.w('SceneEditor', '同步场景节拍完成状态失败', e);
           }
           // 🚀 扩写/重构/缩写等流式生成完成：刷新积分
           try {
             // ignore: use_build_context_synchronously
             context.read<CreditBloc>().add(const RefreshUserCredits());
           } catch (_) {}
           break;
         }
         
         if (chunk.content.isNotEmpty) {
           // 🚀 修复：使用同步方式逐字符显示，避免异步延迟导致的状态不一致
           await _appendTextCharByCharSync(chunk.content);
         }
         
         // 更新模型信息
         if (chunk.model != null) {
           setState(() {
             _aiModelName = chunk.model!;
           });
         }
       }
       
       // 🚀 确保在流结束时状态被正确重置
       if (mounted) {
         setState(() {
           _isAIGenerating = false;
         });
         AppLogger.i('SceneEditor', '✅ 流式生成完成，状态已重置');

         // 兜底：如果是场景节拍生成，确保面板状态为已生成
         try {
           final bool isSceneBeat = request.requestType == AIRequestType.sceneBeat;
           final String? sid = request.sceneId ?? widget.sceneId;
           if (isSceneBeat && sid != null && sid.isNotEmpty) {
             SceneBeatDataManager.instance.updateSceneStatus(sid, SceneBeatStatus.generated);
           }
         } catch (e) {
           AppLogger.w('SceneEditor', '兜底同步场景节拍完成状态失败', e);
         }

         // 🚀 触发生成完成回调（如果存在）
         if (_onSceneBeatGenerationComplete != null) {
           try {
             _onSceneBeatGenerationComplete!.call();
           } catch (e) {
             AppLogger.w('SceneEditor', '生成完成回调执行失败', e);
           }
           _onSceneBeatGenerationComplete = null; // 清理引用
         }
       }
       
     } catch (e) {
       AppLogger.e('SceneEditor', '流式生成失败', e);
       
       // 🚀 立即恢复隐藏的文本样式（重构/缩写的横杠样式）
       _restoreHiddenTextOnError();
       
       // 🚀 专门处理积分不足错误
       if (e is InsufficientCreditsException) {
         AppLogger.w('SceneEditor', '积分不足: ${e.message}');
         if (mounted) {
           _showInsufficientCreditsDialog(e, onReturnToForm: _returnToLastForm);
         }
       } else {
         AppLogger.e('SceneEditor', '流式生成其他错误', e);
       }
       
       // 异常情况下也要重置状态
       if (mounted) {
         setState(() {
           _isAIGenerating = false;
         });
       }
       
       // 同步：如果是场景节拍生成，错误时将状态置为 error，以恢复按钮可用
       try {
         final bool isSceneBeat = request.requestType == AIRequestType.sceneBeat;
         final String? sid = request.sceneId ?? widget.sceneId;
         if (isSceneBeat && sid != null && sid.isNotEmpty) {
           SceneBeatDataManager.instance.updateSceneStatus(sid, SceneBeatStatus.error);
         }
       } catch (e2) {
         AppLogger.w('SceneEditor', '同步场景节拍错误状态失败', e2);
       }
       
     } finally {
       // 最终确保状态被重置
       if (mounted && _isAIGenerating) {
         setState(() {
           _isAIGenerating = false;
         });
         AppLogger.i('SceneEditor', '🔄 最终重置AI生成状态');
       }
     }
   }

   /// 🚀 新增：同步的逐字符追加文本方法，避免异步延迟
   Future<void> _appendTextCharByCharSync(String text) async {
     try {
       // 合并当前收到的内容，帧级批量插入，避免字符级频繁更新
       _pendingStreamText += text;
       await Future<void>.delayed(Duration.zero);
       if (!mounted || !_isAIGenerating || _pendingStreamText.isEmpty) return;

       final String batch = _pendingStreamText;
       _pendingStreamText = '';

       // 插入整段文本
       widget.controller.document.insert(_lastInsertedOffset, batch);

       // 🎨 为新插入的文本整体添加AI生成标识
       AIGeneratedContentProcessor.markAsAIGenerated(
         controller: widget.controller,
         startOffset: _lastInsertedOffset,
         length: batch.length,
       );

       _generatedText += batch;
       _lastInsertedOffset += batch.length;
       _aiGeneratedWordCount = _generatedText.length;

       if (mounted) {
         setState(() {});
       }
     } catch (e) {
       AppLogger.e('SceneEditor', '批量插入过程中出错', e);

       // 🚀 恢复隐藏的文本样式
       _restoreHiddenTextOnError();

       // 如果出错，确保停止生成状态
       if (mounted) {
         setState(() {
           _isAIGenerating = false;
         });
       }
     }
   }

   /// 逐字符追加文本（保留原方法以防其他地方调用）
   Future<void> _appendTextCharByChar(String text) async {
     // 🚀 直接调用同步版本
     await _appendTextCharByCharSync(text);
   }

   /// 应用生成的文本
   void _handleApplyGeneration() {
     AppLogger.i('SceneEditor', '✅ 应用AI生成的文本');
     
     // 🎨 移除AI生成标识，将内容转为正常文本
     if (_generatedText.isNotEmpty) {
       final startOffset = _lastInsertedOffset - _generatedText.length;
       AIGeneratedContentProcessor.removeAIGeneratedMarks(
         controller: widget.controller,
         startOffset: startOffset,
         length: _generatedText.length,
       );
     }
     
     // 🆕 同时移除所有隐藏文本标识（如果是重构，隐藏的原文本将被永久删除）
     AIGeneratedContentProcessor.clearAllAIGeneratedMarks(controller: widget.controller);
     // 🗑️ 清除所有隐藏文本标识并物理删除被隐藏的文本
     _removeAllHiddenText();
     
     // 隐藏AI工具栏并重置状态
     setState(() {
       _showAIToolbar = false;
       _isAIGenerating = false;
       _generatedText = '';
       _aiGeneratedWordCount = 0;
       _pendingStreamText = '';
     });
     
     AppLogger.i('SceneEditor', '🎯 AI生成内容已应用为正常文本');
     
     // 📝 现在保存（隐藏文本已被自动过滤掉）
     _onTextChanged(jsonEncode(widget.controller.document.toDelta().toJson()));
   }

   /// 🆕 移除所有隐藏文本（物理删除）
   void _removeAllHiddenText() {
     try {
       final hiddenRanges = AIGeneratedContentProcessor.getHiddenTextRanges(
         controller: widget.controller,
       );
       
       if (hiddenRanges.isEmpty) return;
       
       AppLogger.i('SceneEditor', '🗑️ 物理删除 ${hiddenRanges.length} 个隐藏文本段落');
       
       // 从后往前删除，避免位置偏移问题
       final sortedRanges = hiddenRanges.toList()..sort((a, b) => b.start.compareTo(a.start));
       
       for (final range in sortedRanges) {
         widget.controller.document.delete(range.start, range.length);
         ////AppLogger.d('SceneEditor', '删除隐藏文本: 位置${range.start}, 长度${range.length}');
       }
       
       AppLogger.i('SceneEditor', '✅ 所有隐藏文本已物理删除');
       
     } catch (e) {
       AppLogger.e('SceneEditor', '删除隐藏文本失败', e);
     }
   }

   /// 重新生成
   void _handleRetryGeneration() {
     AppLogger.i('SceneEditor', '🔄 重新生成AI文本');
     
     // 删除已生成的文本
     if (_generatedText.isNotEmpty) {
       final startOffset = _lastInsertedOffset - _generatedText.length;
       widget.controller.document.delete(startOffset, _generatedText.length);
       _lastInsertedOffset = startOffset;
     }
     
     // 🆕 如果有隐藏文本，保持隐藏状态（重构模式重试时不恢复原文本）
     if (AIGeneratedContentProcessor.hasAnyHiddenText(controller: widget.controller)) {
       AppLogger.i('SceneEditor', '🔄 重构模式：检测到隐藏文本，保持隐藏状态准备重新生成');
     }
     
     // 重置状态并重新开始生成
     setState(() {
       _generatedText = '';
       _aiGeneratedWordCount = 0;
       _currentStreamIndex = 0;
       _isAIGenerating = true;
     });
     
     // 🚀 修改：检查是否有保存的请求，有则重新发起，没有则使用模拟数据
     if (_lastAIRequest != null && _lastUnifiedModel != null) {
       AppLogger.i('SceneEditor', '📡 重新发起AI请求: ${_lastAIRequest!.requestType.value}');
       _startStreamingGeneration(_lastAIRequest!);
     } else {
       AppLogger.w('SceneEditor', '⚠️ 没有保存的请求，使用模拟数据');
       _simulateStreamingGeneration();
     }
   }

   /// 模拟流式生成（用于测试）
   void _simulateStreamingGeneration() {
     AppLogger.i('SceneEditor', '🧪 模拟流式生成测试');
     
     const testText = '这是一段AI生成的测试文本，用于演示流式输出功能。文字会一个个地出现，营造出AI正在思考和写作的感觉。每个字符都会有一定的延迟，让用户感受到AI的创作过程。';
     
     // 逐字符显示文本
     _appendTextCharByChar(testText).then((_) {
       // 生成完成
       setState(() {
         _isAIGenerating = false;
       });
       AppLogger.i('SceneEditor', '✅ 模拟流式生成完成');
     });
   }

   /// 丢弃生成的文本
   void _handleDiscardGeneration() {
     AppLogger.i('SceneEditor', '❌ 丢弃AI生成的文本');
     
     // 首先停止生成（如果正在生成中）
     final wasGenerating = _isAIGenerating;
     
     // 删除已生成的文本
     if (_generatedText.isNotEmpty) {
       final startOffset = _lastInsertedOffset - _generatedText.length;
       widget.controller.document.delete(startOffset, _generatedText.length);
     }
     
     // 🆕 恢复所有隐藏文本（移除隐藏标识，让原文本重新显示）
     AIGeneratedContentProcessor.removeHiddenMarks(controller: widget.controller);
     AppLogger.i('SceneEditor', '👁️ 已恢复所有隐藏的原文本');
     
     // 隐藏AI工具栏并重置状态
     setState(() {
       _showAIToolbar = false;
       _isAIGenerating = false;
       _generatedText = '';
       _aiGeneratedWordCount = 0;
       _pendingStreamText = '';
     });
     
     if (wasGenerating) {
       AppLogger.i('SceneEditor', '🛑 AI生成已停止并丢弃');
     } else {
       AppLogger.i('SceneEditor', '🗑️ AI生成的文本已丢弃');
     }
   }

   /// 分段处理
   void _handleSectionGeneration() {
     AppLogger.i('SceneEditor', '📝 处理分段');
     // TODO: 实现分段功能
   }

   /// 停止生成
   void _handleStopGeneration() {
     AppLogger.i('SceneEditor', '🛑 停止AI生成');
     
     // 立即停止生成状态
     setState(() {
       _isAIGenerating = false;
     });
     
     AppLogger.i('SceneEditor', '✅ AI生成已手动停止');
   }

   /// 🚀 新增：在错误发生时恢复隐藏的文本样式
   void _restoreHiddenTextOnError() {
     try {
       // 检查是否有隐藏文本（重构/缩写时应用的横杠样式）
       if (AIGeneratedContentProcessor.hasAnyHiddenText(controller: widget.controller)) {
         AppLogger.i('SceneEditor', '🔄 检测到隐藏文本，恢复原文本样式（移除横杠）');
         
         // 移除隐藏标识，恢复原文本显示
         AIGeneratedContentProcessor.removeHiddenMarks(controller: widget.controller);
         
         AppLogger.i('SceneEditor', '✅ 隐藏文本样式已恢复');
       }
     } catch (e) {
       AppLogger.e('SceneEditor', '恢复隐藏文本样式失败', e);
     }
   }

   /// 🚀 新增：返回表单回调
   void _returnToLastForm() {
     if (_lastAIRequest == null || _lastSelectedText == null) {
       AppLogger.w('SceneEditor', '没有保存的请求信息，无法返回表单');
       return;
     }

     AppLogger.i('SceneEditor', '返回表单: ${_lastAIRequest!.requestType}, 文本长度: ${_lastSelectedText!.length}');

     // 🚀 获取必要的数据（从EditorBloc中获取）
     Novel? novel;
     List<NovelSettingItem> settings = [];
     List<SettingGroup> settingGroups = [];
     List<NovelSnippet> snippets = [];

     final editorBloc = widget.editorBloc;
     if (editorBloc.state is editor_bloc.EditorLoaded) {
       final state = editorBloc.state as editor_bloc.EditorLoaded;
       novel = state.novel;
       // TODO: 从状态中获取 settings, settingGroups, snippets
       // 暂时使用空列表，后续可以完善
     }

     // 🚀 从保存的请求中提取表单参数
     final lastRequest = _lastAIRequest!;
     final instructions = lastRequest.instructions;
     final enableSmartContext = lastRequest.enableSmartContext;
     final contextSelections = lastRequest.contextSelections;
     
     // 🚀 从参数中提取长度/风格等特定设置
     String? length;
     String? style;
     if (lastRequest.parameters != null) {
       length = lastRequest.parameters!['length']?.toString();
       style = lastRequest.parameters!['style']?.toString();
     }

     // 🚀 根据请求类型显示对应的表单，传递保存的参数
     switch (lastRequest.requestType) {
       case AIRequestType.expansion:
         showExpansionDialog(
           context,
           selectedText: _lastSelectedText!,
           // selectedModel: _lastAIModel,  // 已废弃，使用initialSelectedUnifiedModel
           novel: novel,
           settings: settings,
           settingGroups: settingGroups,
           snippets: snippets,
           // 🚀 恢复之前的设置
           initialInstructions: instructions,
           initialLength: length,
           initialEnableSmartContext: enableSmartContext,
           initialContextSelections: contextSelections,
           initialSelectedUnifiedModel: _lastUnifiedModel,
           onStreamingGenerate: (request, model) {
             _handleStreamingGenerationStarted(request, model);
           },
         );
         break;
       case AIRequestType.refactor:
         showRefactorDialog(
           context,
           selectedText: _lastSelectedText!,
           // selectedModel: _lastAIModel,  // 已废弃，使用initialSelectedUnifiedModel
           novel: novel,
           settings: settings,
           settingGroups: settingGroups,
           snippets: snippets,
           // 🚀 恢复之前的设置
           initialInstructions: instructions,
           initialStyle: style,
           initialEnableSmartContext: enableSmartContext,
           initialContextSelections: contextSelections,
           initialSelectedUnifiedModel: _lastUnifiedModel,
           onStreamingGenerate: (request, model) {
             _handleStreamingGenerationStarted(request, model);
           },
         );
         break;
       case AIRequestType.summary:
         showSummaryDialog(
           context,
           selectedText: _lastSelectedText!,
           // selectedModel: _lastAIModel,  // 已废弃，使用initialSelectedUnifiedModel
           novel: novel,
           settings: settings,
           settingGroups: settingGroups,
           snippets: snippets,
           // 🚀 恢复之前的设置
           initialInstructions: instructions,
           initialLength: length,
           initialEnableSmartContext: enableSmartContext,
           initialContextSelections: contextSelections,
           initialSelectedUnifiedModel: _lastUnifiedModel,
           onStreamingGenerate: (request, model) {
             _handleStreamingGenerationStarted(request, model);
           },
         );
         break;
       default:
         AppLogger.w('SceneEditor', '不支持的请求类型: ${lastRequest.requestType}');
         TopToast.error(context, '不支持的请求类型');
     }
   }

   /// 🚀 修改：显示积分不足对话框，支持返回表单
   void _showInsufficientCreditsDialog(InsufficientCreditsException ex, {VoidCallback? onReturnToForm}) {
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (BuildContext dialogContext) {
         return AlertDialog(
           title: Row(
             children: [
               Icon(
                 Icons.account_balance_wallet,
                 color: Theme.of(context).colorScheme.error,
               ),
               const SizedBox(width: 8),
               const Text('积分余额不足'),
             ],
           ),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text(ex.message),
               const SizedBox(height: 16),
               if (ex.requiredCredits != null) ...[
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                     borderRadius: BorderRadius.circular(8),
                   ),
                   child: Row(
                     children: [
                       Icon(
                         Icons.info_outline,
                         color: Theme.of(context).colorScheme.error,
                         size: 16,
                       ),
                       const SizedBox(width: 8),
                       Expanded(
                         child: Text(
                           '本次操作需要 ${ex.requiredCredits} 积分',
                           style: TextStyle(
                             color: Theme.of(context).colorScheme.onErrorContainer,
                             fontSize: 14,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
                 const SizedBox(height: 16),
               ],
               const Text(
                 '您可以：',
                 style: TextStyle(fontWeight: FontWeight.w500),
               ),
               const SizedBox(height: 8),
               const Text('• 充值积分以继续使用公共模型'),
               const Text('• 配置私有模型（使用自己的API Key）'),
               const Text('• 选择其他更便宜的模型'),
             ],
           ),
           actions: [
             TextButton(
               onPressed: () {
                 Navigator.of(dialogContext).pop();
                 // 🚀 恢复隐藏的文本样式
                 _restoreHiddenTextOnError();
                 // 重置AI工具栏状态
                 setState(() {
                   _showAIToolbar = false;
                   _isAIGenerating = false;
                 });
               },
               child: const Text('取消'),
             ),
             if (onReturnToForm != null) // 🚀 只有当有返回表单回调时才显示
               TextButton(
                 onPressed: () {
                   Navigator.of(dialogContext).pop();
                   // 🚀 恢复隐藏的文本样式
                   _restoreHiddenTextOnError();
                   // 🚀 重新显示选择工具栏
                   setState(() {
                     _showToolbar = true;
                     _showAIToolbar = false;
                     _isAIGenerating = false;
                   });
                   // 🚀 调用返回表单回调
                   onReturnToForm();
                 },
                 style: TextButton.styleFrom(
                   foregroundColor: Theme.of(context).colorScheme.primary,
                 ),
                 child: const Text('返回表单'),
               ),
             ElevatedButton(
               onPressed: () {
                 Navigator.of(dialogContext).pop();
                 // TODO: 跳转到充值页面或设置页面
                 // Navigator.pushNamed(context, '/settings/credits');
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('跳转到积分充值页面（功能开发中）')),
                 );
               },
               child: const Text('去充值'),
             ),
           ],
         );
       },
     );
   }

   


  // 监听内容加载完成，重新处理设定引用
  void _setupContentLoadListener() {
    widget.editorBloc.stream.listen((state) {
      if (!mounted) return;
      
      // 当内容发生变化时，重新处理设定引用
      if (state is editor_bloc.EditorLoaded) {
        // 延迟执行，确保UI已更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ////AppLogger.d('SceneEditor', '📝 内容加载完成，重新处理设定引用: ${widget.sceneId}');
            _checkAndProcessSettingReferences();
          }
        });
      }
    });
  }

  // 添加EditorBloc状态监听，确保摘要控制器内容与模型保持同步
  void _setupBlocListener() {
    widget.editorBloc.stream.listen((state) {
      if (!mounted) return;
      
      if (state is editor_bloc.EditorLoaded && 
          widget.sceneId != null && 
          widget.actId != null && 
          widget.chapterId != null) {
        try {
          // 使用更安全的查找方式
          bool found = false;
          String? modelSummaryContent;
          
          // 遍历所有元素查找指定场景
          for (final act in state.novel.acts) {
            if (act.id == widget.actId) {
              for (final chapter in act.chapters) {
                if (chapter.id == widget.chapterId) {
                  for (final scene in chapter.scenes) {
                    if (scene.id == widget.sceneId) {
                      found = true;
                      modelSummaryContent = scene.summary.content ?? '';
                      break;
                    }
                  }
                  if (found) break;
                }
              }
              if (found) break;
            }
          }
          
          // 如果场景不存在，则提前返回
          if (!found) {
            ////AppLogger.d('SceneEditor', '跳过摘要同步：场景不存在或已被删除: ${widget.sceneId}');
            return;
          }
          
          // 如果用户正在编辑摘要，避免用模型内容覆盖用户输入
          if (_summaryFocusNode.hasFocus) {
            return;
          }

          // 当前控制器中的文本
          final currentControllerText = widget.summaryController.text;
          
          // 仅当摘要控制器内容与模型不同时更新
          if (currentControllerText != modelSummaryContent) {
            // 判断变更方向
            if (currentControllerText.isNotEmpty && (modelSummaryContent == null || modelSummaryContent.isEmpty)) {
              // 如果控制器有内容但模型为空，说明是用户刚输入了内容但可能未保存成功
              // 重新触发保存操作确保内容被保存
              AppLogger.i('SceneEditor', '检测到摘要未同步到模型，重新保存: ${widget.sceneId}');
              
              // 将更新放在下一帧执行，避免在build过程中修改
              Future.microtask(() {
                if (mounted) {
                  // 触发摘要保存并强制重建UI以确保更新成功
                  widget.editorBloc.add(editor_bloc.UpdateSummary(
                    novelId: widget.editorBloc.novelId,
                    actId: widget.actId!,
                    chapterId: widget.chapterId!,
                    sceneId: widget.sceneId!,
                    summary: currentControllerText,
                    shouldRebuild: true, // 强制重建UI
                  ));
                }
              });
            } else if (modelSummaryContent != null && modelSummaryContent.isNotEmpty) {
              // 模型中有内容但控制器不同，更新控制器
              AppLogger.i('SceneEditor', '摘要内容从模型同步到控制器: ${widget.sceneId}');
              
              // 将更新放在下一帧执行，避免在build过程中修改
              Future.microtask(() {
                if (mounted) {
                  widget.summaryController.text = modelSummaryContent!;
                }
              });
            }
          }
        } catch (e, stackTrace) {
          // 记录详细错误信息但不抛出异常
          AppLogger.i('SceneEditor', '同步摘要控制器失败，可能是场景已被删除: ${widget.sceneId}');
          AppLogger.v('SceneEditor', '同步摘要控制器详细错误: ${e.toString()}', e, stackTrace);
        }
      }
    });
  }

  // 🚀 新增：设置摘要滚动固定监听
  void _setupSummaryScrollListener() {
    // 查找父级滚动控制器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findParentScrollController();
    });
  }

  // 🚀 新增：查找父级滚动控制器
  void _findParentScrollController() {
    try {
      // 通过context查找最近的Scrollable
      final scrollableState = Scrollable.maybeOf(context);
      if (scrollableState != null) {
        _parentScrollController = scrollableState.widget.controller;
        if (_parentScrollController != null) {
          _parentScrollController!.addListener(_onParentScroll);
          ////AppLogger.d('SceneEditor', '已找到并监听父级滚动控制器: ${widget.sceneId}');
        }
      }
    } catch (e) {
      AppLogger.w('SceneEditor', '查找父级滚动控制器失败: ${widget.sceneId}', e);
    }
  }

  // 🚀 新增：父级滚动监听
  void _onParentScroll() {
    if (!mounted || _parentScrollController == null) return;
    
    // 🚀 优化：使用requestAnimationFrame的思路，在下一帧更新位置
    _scrollPositionTimer?.cancel();
    _scrollPositionTimer = Timer(Duration.zero, () {
      if (mounted) {
        // 使用WidgetsBinding.instance.addPostFrameCallback确保在下一帧执行
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateSummaryPosition();
          }
        });
      }
    });
  }

  // 🚀 新增：更新摘要位置
  void _updateSummaryPosition() {
    if (!mounted) return;
    
    try {
      // 🚀 优化：首先更新摘要组件的实际高度
      _updateSummaryHeight();
      
      // 获取场景容器的位置信息
      final sceneRenderBox = _sceneContainerKey.currentContext?.findRenderObject() as RenderBox?;
      if (sceneRenderBox == null) return;
      
      // 获取场景容器在屏幕中的位置
      final scenePosition = sceneRenderBox.localToGlobal(Offset.zero);
      final sceneSize = sceneRenderBox.size;
      
      // 🚀 新增：检查场景高度，如果太小则不启用粘性滚动
      if (sceneSize.height < _minSceneHeightForSticky) {
        // 🚀 获取场景内容长度用于日志
        final contentLength = widget.controller.document.toPlainText().trim().length;
        //AppLogger.v('SceneEditor', '场景高度过小(${sceneSize.height}px < $_minSceneHeightForSticky)，内容长度: $contentLength，跳过粘性滚动: ${widget.sceneId}');
        
        // 重置为非粘性状态
        if (_isSummarySticky || _summaryTopOffsetVN.value != 0.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _summaryTopOffsetVN.value = 0.0;
                _isSummarySticky = false;
              });
              _lastCalculatedOffset = 0.0;
              _lastStickyState = false;
            }
          });
        }
        return;
      }
      
      // 获取屏幕可视区域
      final mediaQuery = MediaQuery.of(context);
      final screenHeight = mediaQuery.size.height;
      final topPadding = mediaQuery.padding.top;
      final viewportTop = topPadding;
      final viewportBottom = screenHeight;
      
      // 计算场景在视口中的位置
      final sceneTop = scenePosition.dy;
      final sceneBottom = sceneTop + sceneSize.height;
      
      double newTopOffset = 0.0;
      bool newStickyState = false;
      
      // 🚀 优化：计算安全的最大偏移，包含更多边距和底部工具栏高度
      const totalMargin = _summaryTopMargin + _summaryBottomMargin + _bottomToolbarHeight;
      final maxOffset = (sceneSize.height - _summaryHeight - totalMargin).clamp(0.0, sceneSize.height - totalMargin);
      
      // 🚀 优化：添加顶部边距到视口计算
      final adjustedViewportTop = viewportTop + _summaryTopMargin;
      
      // 场景顶部在视口上方，底部在视口内 - 摘要固定在视口顶部
      if (sceneTop < adjustedViewportTop && sceneBottom > adjustedViewportTop) {
        newTopOffset = (adjustedViewportTop - sceneTop).clamp(0.0, maxOffset);
        newStickyState = true;
      }
      // 场景完全在视口内 - 摘要跟随场景顶部
      else if (sceneTop >= adjustedViewportTop && sceneBottom <= viewportBottom) {
        newTopOffset = _summaryTopMargin; // 🚀 保持顶部边距
        newStickyState = false;
      }
      // 场景顶部在视口内，底部在视口下方 - 摘要固定但不超出场景底部
      else if (sceneTop < viewportBottom && sceneBottom > viewportBottom) {
        // 🚀 优化：考虑边距，确保摘要不会超出场景底部
        final idealOffset = adjustedViewportTop - sceneTop;
        newTopOffset = idealOffset.clamp(_summaryTopMargin, maxOffset);
        newStickyState = true;
      }
      // 场景完全在视口外 - 摘要跟随场景
      else {
        newTopOffset = _summaryTopMargin; // 🚀 保持顶部边距
        newStickyState = false;
      }
      
      // 🚀 优化：使用更大的阈值减少闪烁，并检查状态变化
      final offsetChanged = (_lastCalculatedOffset - newTopOffset).abs() > _positionThreshold;
      final stickyChanged = _lastStickyState != newStickyState;
      
      if (offsetChanged || stickyChanged) {
        // 🚀 优化：使用WidgetsBinding.instance.addPostFrameCallback确保UI更新的平滑性
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _summaryTopOffsetVN.value = newTopOffset;
              _isSummarySticky = newStickyState;
            });
            
            // 更新缓存的值
            _lastCalculatedOffset = newTopOffset;
            _lastStickyState = newStickyState;
            
            //AppLogger.v('SceneEditor', '摘要位置更新: offset=$newTopOffset, sticky=$newStickyState, height=$_summaryHeight, sceneHeight=${sceneSize.height}, 场景=${widget.sceneId}');
          }
        });
      }
      
    } catch (e) {
      AppLogger.w('SceneEditor', '更新摘要位置失败: ${widget.sceneId}', e);
    }
  }

  // 🚀 新增：更新摘要组件的实际高度
  void _updateSummaryHeight() {
    try {
      final summaryRenderBox = _summaryKey.currentContext?.findRenderObject() as RenderBox?;
      if (summaryRenderBox != null) {
        final actualHeight = summaryRenderBox.size.height;
        if ((actualHeight - _summaryHeight).abs() > 5.0) { // 只在高度变化超过5px时更新
          _summaryHeight = actualHeight;
          AppLogger.v('SceneEditor', '摘要高度更新: $_summaryHeight, 场景=${widget.sceneId}');
        }
      }
    } catch (e) {
      AppLogger.v('SceneEditor', '获取摘要高度失败，使用默认值: ${widget.sceneId}', e);
    }
  }

  // 🚀 新增：移除摘要滚动监听
  void _removeSummaryScrollListener() {
    if (_parentScrollController != null) {
      _parentScrollController!.removeListener(_onParentScroll);
      ////AppLogger.d('SceneEditor', '已移除父级滚动监听: ${widget.sceneId}');
    }
  }

  // 🚀 新增：显示摘要生成器
  void _showSummaryGenerator() {
    // 显示AI摘要面板（使用侧边栏方式）
    final layoutManager = context.read<EditorLayoutManager>();
    layoutManager.showAISummaryPanel();
  }

  // 🚀 新增：显示场景节拍面板
  void _showSceneBeatPanel() {
    if (widget.sceneId == null) return;
    
    AppLogger.i('SceneEditor', '🎯 显示场景节拍面板: ${widget.sceneId}');
    
    // 🚀 新增：获取编辑器状态管理器
    EditorScreenController? editorController;
    EditorLayoutManager? layoutManager;
    
    try {
      editorController = Provider.of<EditorScreenController>(context, listen: false);
      layoutManager = Provider.of<EditorLayoutManager>(context, listen: false);
      AppLogger.d('SceneEditor', '✅ 成功获取编辑器状态管理器');
    } catch (e) {
      AppLogger.w('SceneEditor', '⚠️ 获取编辑器状态管理器失败: $e');
    }
    
    // 使用Overlay场景节拍管理器显示面板
    OverlaySceneBeatManager.instance.show(
      context: context,
      sceneId: widget.sceneId!,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      // 🚀 新增：传递编辑器状态管理器
      editorController: editorController,
      layoutManager: layoutManager,
      onGenerate: (sceneId, request, model) {
        // 触发场景节拍生成
        AppLogger.i('SceneEditor', '🚀 触发场景节拍生成: $sceneId, 模型: ${model.displayName}');
        startSceneBeatGeneration(
          request: request,
          model: model,
          onGenerationComplete: () {
            AppLogger.i('SceneEditor', '✅ 场景节拍生成完成: $sceneId');
          },
        );
      },
    );
  }

  /// 🚀 新增：公开方法，用于从外部触发场景节拍的AI生成
  void startSceneBeatGeneration({
    required UniversalAIRequest request,
    required UnifiedAIModel model,
    VoidCallback? onGenerationComplete,
  }) {
    AppLogger.i('SceneEditor', '🎯 接收到场景节拍生成请求: ${model.displayName}');
    // 🚀 若存在未应用的AI生成内容或隐藏文本，先自动应用为正文，确保新请求包含最新上下文
    try {
      final bool hasAIGen = AIGeneratedContentProcessor.hasAnyAIGeneratedContent(
        controller: widget.controller,
      );
      final bool hasHidden = AIGeneratedContentProcessor.hasAnyHiddenText(
        controller: widget.controller,
      );
      if (hasAIGen || hasHidden) {
        if (_isAIGenerating) {
          _handleStopGeneration();
        }
        _handleApplyGeneration();
      }
    } catch (_) {}
    
    // 🚀 新增：保存请求和统一模型配置，用于重试
    _lastAIRequest = request;
    _lastUnifiedModel = model;
    _lastSelectedText = ''; // 场景节拍没有选中文本

    _aiGeneratedStartOffset = _lastInsertedOffset; // 记录AI生成内容的起始位置
    
    AppLogger.i('SceneEditor', '🚀 开始场景节拍流式生成，插入位置: $_lastInsertedOffset');
    
    // 🚀 修复：延迟一帧显示AI工具栏，确保光标位置和LayerLink目标正确计算
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // 显示AI工具栏并设置生成状态
      setState(() {
        _showToolbar = false;
        _showAIToolbar = true;
        _isAIGenerating = true;
        _aiModelName = model.displayName;
        _generatedText = '';
        _aiGeneratedWordCount = 0;
        _currentStreamIndex = 0;
        _pendingStreamText = '';
      });
      
      AppLogger.i('SceneEditor', '✅ AI工具栏已显示，LayerLink目标应该已正确定位');
      
      // 🚀 滚动到光标位置，确保AI工具栏可见
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCursorPosition();
      });
      
      // 保存回调
      _onSceneBeatGenerationComplete = onGenerationComplete;
      
      // 开始流式生成
      _startStreamingGeneration(request);
    });
  }

  /// 🚀 新增：滚动到光标位置，确保AI工具栏可见
  void _scrollToCursorPosition() {
    try {
      if (_editorContentKey.currentContext != null) {
        Scrollable.ensureVisible(
          _editorContentKey.currentContext!,
          alignment: 1.0, // 将目标放在视口底部
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      AppLogger.e('SceneEditor', '滚动到光标位置失败', e);
    }
  }

  // 🚀 新增：保存生成完成回调
  VoidCallback? _onSceneBeatGenerationComplete;
}

/// 🚀 新增：摘要操作按钮组件
class _SummaryActionButton extends StatelessWidget {
  const _SummaryActionButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onPressed,
  });
  
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: TextButton.icon(
        onPressed: onPressed ?? () {},
        icon: Icon(icon, size: 12, color: WebTheme.getSecondaryTextColor(context)), // 🚀 减小图标尺寸
        label: Text(
          label, 
          style: TextStyle(
            fontSize: 10, // 🚀 减小字体尺寸
            color: WebTheme.getSecondaryTextColor(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: WebTheme.getSecondaryTextColor(context),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), // 🚀 减小内边距
          minimumSize: const Size(0, 24), // 🚀 减小最小尺寸
          tapTargetSize: MaterialTapTargetSize.shrinkWrap, // 🚀 收缩点击目标尺寸
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)), // 🚀 减小圆角
          visualDensity: VisualDensity.compact,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.hovered)) {
                return WebTheme.getSurfaceColor(context).withOpacity(0.8);
              }
              return null;
            },
          ),
        ),
      ),
    );
  }
}
