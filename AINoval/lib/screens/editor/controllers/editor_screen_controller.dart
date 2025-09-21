import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;
import 'package:ainoval/blocs/novel_list/novel_list_bloc.dart';

import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/screens/editor/components/editor_main_area.dart';

import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/impl/editor_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/prompt_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/prompt_repository.dart';
import 'package:ainoval/services/local_storage_service.dart';
import 'package:ainoval/services/sync_service.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:ainoval/utils/word_count_analyzer.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' hide EditorState;
import 'package:collection/collection.dart';

import '../../../services/api_service/repositories/impl/novel_ai_repository_impl.dart';
import '../../../services/api_service/repositories/novel_ai_repository.dart'; // Add this line
import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/services/api_service/repositories/novel_setting_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_setting_repository_impl.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';

// 添加这些顶层定义，放在import语句之后，类定义之前
// 滚动状态枚举
enum ScrollState { idle, userScrolling, inertialScrolling }

// 滚动信息类，包含速度和是否快速滚动的标志
class _ScrollInfo {
  final double speed;
  final bool isRapid;
  
  _ScrollInfo(this.speed, this.isRapid);
}

/// 编辑器屏幕控制器
/// 负责管理编辑器屏幕的状态和逻辑
class EditorScreenController extends ChangeNotifier {
  EditorScreenController({
    required this.novel,
    required this.vsync,
  }) {
    _init();
  }

  final NovelSummary novel;
  final TickerProvider vsync;

  // BLoC实例
  late final editor_bloc.EditorBloc editorBloc;
  late final SettingBloc settingBloc; // 🚀 新增：SettingBloc实例

  // 服务实例
  late final ApiClient apiClient;
  late final EditorRepositoryImpl editorRepository;
  late final PromptRepository promptRepository;
  late final NovelAIRepository novelAIRepository;
  late final LocalStorageService localStorageService;
  late final SyncService syncService;
  late final NovelSettingRepository novelSettingRepository; // 🚀 新增：设定仓库实例

  // 控制器
  late final TabController tabController;
  final ScrollController scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();

  // GlobalKey for EditorMainArea
  final GlobalKey<EditorMainAreaState> editorMainAreaKey = GlobalKey<EditorMainAreaState>();

  // 编辑器状态
  bool isPlanViewActive = false;
  bool isNextOutlineViewActive = false;
  bool isPromptViewActive = false;
  String? currentUserId;
  String? lastActiveSceneId; // 记录最后活动的场景ID，用于判断场景是否发生变化

  // 控制器集合
  final Map<String, QuillController> sceneControllers = {};
  final Map<String, TextEditingController> sceneTitleControllers = {};
  final Map<String, TextEditingController> sceneSubtitleControllers = {};
  final Map<String, TextEditingController> sceneSummaryControllers = {};
  final Map<String, GlobalKey> sceneKeys = {};

  // 标记是否处于初始加载阶段，用于防止组件过早触发加载请求
  bool _initialLoadFlag = false;

  // 获取初始加载标志，用于外部组件(如ChapterSection)判断是否应该触发加载
  bool get isInInitialLoading => _initialLoadFlag;

  // 新增变量
  double? _currentScrollSpeed;

  // 滚动相关变量
  DateTime? _lastScrollHandleTime;
  DateTime? _lastScrollTime;
  double? _lastScrollPosition;
  static const Duration _scrollThrottleInterval = Duration(milliseconds: 800); // 增加到800ms
  Timer? _inertialScrollTimer;
  // 添加滚动状态变量
  ScrollState _scrollState = ScrollState.idle;
  // 动态调整节流间隔
  int _currentThrottleMs = 350; // 默认节流时间

  // 防抖变量，避免频繁触发加载
  DateTime? _lastLoadTime;
  String? _lastDirection;
  String? _lastFromChapterId;
  bool _isLoadingMore = false;

  // 公共 getter，用于 UI 访问加载状态
  bool get isLoadingMore => _isLoadingMore;

  // 用于滚动事件的节流控制
  DateTime? _lastScrollProcessTime;

  // 添加摘要加载状态管理
  bool _isLoadingSummaries = false;
  DateTime? _lastSummaryLoadTime;
  static const Duration _summaryLoadThrottleInterval = Duration(seconds: 60); // 1分钟内不重复加载

  // 新增：在EditorScreenController中添加
  bool get hasReachedEnd => 
      editorBloc.state is editor_bloc.EditorLoaded && 
      (editorBloc.state as editor_bloc.EditorLoaded).hasReachedEnd;

  bool get hasReachedStart => 
      editorBloc.state is editor_bloc.EditorLoaded && 
      (editorBloc.state as editor_bloc.EditorLoaded).hasReachedStart;

  // 用于EditorBloc状态监听的字段
  int? _lastScenesCount;
  int? _lastChaptersCount;
  int? _lastActsCount;

  // 添加更多的状态变量
  bool _isFullscreenLoading = false;
  String _loadingMessage = '正在加载编辑器...';
  // 平滑进度动画：目标值与显示值分离
  double _progressAnimated = 0.0; // 对外展示用
  double _progressTarget = 0.0;   // 内部目标值
  Timer? _progressTimer;          // 平滑补间计时器
  DateTime? _overlayShownAt;      // 覆盖层显示起始时间
  bool _hasCompletedInitialLoad = false; // 首次数据就绪标记

  // 提供getter供UI使用
  bool get isFullscreenLoading => _isFullscreenLoading;
  String get loadingMessage => _loadingMessage;
  double get loadingProgress => _progressAnimated;

  // 新增：用于跟踪最近滚动方向的变量
  // String _lastEffectiveScrollDirection = 'none'; // 移除此行

  // 添加事件订阅变量
  StreamSubscription<NovelStructureUpdatedEvent>? _novelStructureSubscription;

  // 新增：dispose状态跟踪
  bool _isDisposed = false;
  
  // 🚀 新增：提供SettingBloc访问接口
  SettingBloc get settingBlocInstance => settingBloc;

  // 🚀 新增：级联菜单数据管理
  ContextSelectionData? _cascadeMenuData;
  DateTime? _lastCascadeMenuUpdateTime;
  static const Duration _cascadeMenuUpdateThrottle = Duration(milliseconds: 500);

  // 🚀 新增：获取级联菜单数据的公共接口
  ContextSelectionData? get cascadeMenuData => _cascadeMenuData;
  
  // 🚀 新增：检查级联菜单数据是否已就绪
  bool get isCascadeMenuDataReady => _cascadeMenuData != null;

  // 检查是否有任何加载正在进行
  bool _isAnyLoading() {
    // 检查编辑器状态
    if (editorBloc.state is editor_bloc.EditorLoaded) {
      final state = editorBloc.state as editor_bloc.EditorLoaded;
      if (state.isLoading) return true;
    }

    // 检查控制器状态
    if (_isLoadingMore) return true;

    // 检查加载冷却时间
    if (_lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!).inSeconds < 1) {
      return true;
    }

    return false;
  }

  // 初始化方法
  void _init() {
    // 启用全屏加载状态
    _isFullscreenLoading = true;
    _progressAnimated = 0.0;
    _progressTarget = 0.0;
    _overlayShownAt = DateTime.now();
    _startProgressTicker();
    _updateLoadingProgress('正在初始化编辑器核心组件...');

    // 🚀 立即同步初始化核心组件，确保editorBloc等立即可用
    _initializeCoreComponentsSync();
    
    // 🚀 异步初始化SettingBloc，但不阻塞主流程
    _initializeSettingBlocAsync();
  }
  
  // 🚀 修改：同步初始化核心组件，确保立即可用
  void _initializeCoreComponentsSync() {
    // 创建必要的实例
    apiClient = ApiClient();
    editorRepository = EditorRepositoryImpl();
    promptRepository = PromptRepositoryImpl(apiClient);
    novelAIRepository = NovelAIRepositoryImpl(apiClient: apiClient);
    localStorageService = LocalStorageService();
    
    // 🚀 立即创建设定仓库和SettingBloc（但不等待数据加载）
    novelSettingRepository = NovelSettingRepositoryImpl(apiClient: apiClient);
    settingBloc = SettingBloc(settingRepository: novelSettingRepository);
    
    tabController = TabController(length: 4, vsync: vsync);
    
    _updateLoadingProgress('正在启动编辑器服务...');

    // 初始化EditorBloc
    editorBloc = editor_bloc.EditorBloc(
      repository: editorRepository,
      novelId: novel.id,
    );
    
    // 监听EditorBloc状态变化，用于更新UI
    _setupEditorBlocListener();

    // 添加对小说结构更新事件的监听
    _setupNovelStructureListener();
    
    // 🚀 新增：在编辑器数据加载后初始化级联菜单数据
    _initializeCascadeMenuDataWhenReady();

    _updateLoadingProgress('正在初始化同步服务...');
    
    // 初始化同步服务
    syncService = SyncService(
      apiService: apiClient,
      localStorageService: localStorageService,
    );

    // 初始化同步服务并设置当前小说
    syncService.init().then((_) {
      syncService.setCurrentNovelId(novel.id).then((_) {
        AppLogger.i('EditorScreenController', '已设置当前小说ID: ${novel.id}');
        _updateLoadingProgress('正在加载小说结构...');
      });
    });

    // 2. 主编辑区使用分页加载，仅加载必要的章节场景内容
    String? lastEditedChapterId = novel.lastEditedChapterId;
    AppLogger.i('EditorScreenController', '使用分页加载初始化编辑器，最后编辑章节ID: $lastEditedChapterId');

    _updateLoadingProgress('正在加载编辑区内容...');
    
    // 添加延迟以避免初始化同时发送大量请求
    Future.delayed(const Duration(milliseconds: 500), () {
          // 🚀 新增：在加载编辑器内容之前，先加载用户编辑器设置
    if (currentUserId != null) {
      AppLogger.i('EditorScreenController', '开始加载用户编辑器设置: userId=$currentUserId');
      editorBloc.add(editor_bloc.LoadUserEditorSettings(userId: currentUserId!));
    }
    
    // 使用一次性加载API获取全部小说内容
    AppLogger.i('EditorScreenController', '开始一次性加载小说数据: ${novel.id}');
    
    editorBloc.add(editor_bloc.LoadEditorContentPaginated(
      novelId: novel.id,
      loadAllSummaries: false, // 不加载所有摘要，减少初始加载量
    ));
    
    // 🚀 新增：如果有上次编辑的章节ID，自动设置为沉浸模式目标章节
    if (lastEditedChapterId != null && lastEditedChapterId.isNotEmpty) {
      AppLogger.i('EditorScreenController', '检测到上次编辑章节，准备进入沉浸模式: $lastEditedChapterId');
      
      // 等待小说数据加载完成后再进入沉浸模式
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!_isDisposed) {
          AppLogger.i('EditorScreenController', '进入上次编辑章节的沉浸模式: $lastEditedChapterId');
          editorBloc.add(editor_bloc.SwitchToImmersiveMode(chapterId: lastEditedChapterId));
          editorBloc.add(editor_bloc.SetFocusChapter(chapterId: lastEditedChapterId));
        }
      });
    }
      // 等待真实数据就绪与首帧渲染完成后再结束覆盖层
    });

    // 防止在初始化时ChapterSection组件触发大量加载
    _initialLoadFlag = true;
    Future.delayed(const Duration(seconds: 3), () {
      _initialLoadFlag = false;
      AppLogger.i('EditorScreenController', '初始加载限制已解除，允许正常分页加载');
    });

    currentUserId = AppConfig.userId;
    if (currentUserId == null) {
      AppLogger.e(
          'EditorScreenController', 'User ID is null. Some features might be limited.');
    }

    
    // 初始化性能优化（新增）
    _initializePerformanceOptimization();
  }
  
  // 🚀 新增：异步初始化SettingBloc并等待完成，但不阻塞主流程
  Future<void> _initializeSettingBlocAsync() async {
    // 🚀 修复：检查是否已经disposed
    if (_isDisposed) {
      AppLogger.w('EditorScreenController', '控制器已销毁，跳过SettingBloc异步初始化');
      return;
    }
    
    AppLogger.i('EditorScreenController', '🚀 开始SettingBloc异步初始化 - 小说ID: ${novel.id}');
    
    // 延迟一点时间，让主界面先显示出来
    await Future.delayed(const Duration(milliseconds: 100));
    
    // 🚀 修复：再次检查是否已经disposed
    if (_isDisposed) {
      AppLogger.w('EditorScreenController', '延迟后控制器已销毁，跳过SettingBloc数据加载');
      return;
    }
    
    _updateLoadingProgress('正在加载小说设定数据...');
    
    // 🚀 关键：现在异步等待SettingBloc初始化完成
    await _waitForSettingBlocInitialization();
    
    // 🚀 修复：完成后检查是否已经disposed
    if (_isDisposed) {
      AppLogger.w('EditorScreenController', 'SettingBloc初始化完成，但控制器已销毁');
      return;
    }
    
    AppLogger.i('EditorScreenController', '🎉 SettingBloc异步初始化完成！设定功能现在可用');
  }
  
  // 🚀 新增：等待SettingBloc初始化完成
  Future<void> _waitForSettingBlocInitialization() async {
    // 🚀 修复：检查是否已经disposed
    if (_isDisposed) {
      AppLogger.w('EditorScreenController', '控制器已销毁，跳过SettingBloc数据等待');
      return;
    }
    
    final completer = Completer<void>();
    bool groupsLoaded = false;
    bool itemsLoaded = false;
    
    AppLogger.i('EditorScreenController', '⏳ 开始加载设定数据...');
    
    // 监听SettingBloc状态变化
    late StreamSubscription<SettingState> subscription;
    subscription = settingBloc.stream.listen((state) {
      // 🚀 修复：在监听器中检查是否已经disposed
      if (_isDisposed) {
        AppLogger.w('EditorScreenController', '控制器已销毁，取消SettingBloc状态监听');
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      
      // 检查组数据加载状态
      if (state.groupsStatus == SettingStatus.success) {
        if (!groupsLoaded) {
          groupsLoaded = true;
          AppLogger.i('EditorScreenController', '✅ 设定组加载完成 - 数量: ${state.groups.length}');
        }
      }
      
      // 检查条目数据加载状态
      if (state.itemsStatus == SettingStatus.success) {
        if (!itemsLoaded) {
          itemsLoaded = true;
          AppLogger.i('EditorScreenController', '✅ 设定条目加载完成 - 数量: ${state.items.length}');
        }
      }
      
      // 两个都加载完成时，完成等待
      if (groupsLoaded && itemsLoaded) {
        AppLogger.i('EditorScreenController', '🎉 SettingBloc初始化完成！');
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      
      // 处理失败情况
      if (state.groupsStatus == SettingStatus.failure || state.itemsStatus == SettingStatus.failure) {
        AppLogger.w('EditorScreenController', '⚠️ 设定数据加载失败，继续初始化流程');
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    
    // 开始加载设定数据
    settingBloc.add(LoadSettingGroups(novel.id));
    settingBloc.add(LoadSettingItems(novelId: novel.id));
    
    // 设置超时保护，避免无限等待
    try {
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.w('EditorScreenController', '⚠️ SettingBloc初始化超时，继续初始化流程');
          subscription.cancel();
        },
      );
    } catch (e) {
      AppLogger.e('EditorScreenController', 'SettingBloc初始化异常', e);
      subscription.cancel();
    }
  }
  
  // 监听EditorBloc状态变化
  void _setupEditorBlocListener() {
    editorBloc.stream.listen((state) {
      if (state is editor_bloc.EditorLoaded) {
        // 首次数据加载完成时，推进进度并等待首帧渲染
        if (_isFullscreenLoading && !_hasCompletedInitialLoad && !state.isLoading) {
          _hasCompletedInitialLoad = true;
          _loadingMessage = '正在渲染编辑器...';
          _setProgressTarget(0.98); // 数据就绪后推进到98%
          notifyListeners();
          _completeLoadingWhenFirstFrameReady();
        }
        // 检查加载状态和章节/场景计数
        
        // 计算当前场景和章节总数
        int currentScenesCount = 0;
        int currentChaptersCount = 0;
        int currentActsCount = state.novel.acts.length;
        
        for (final act in state.novel.acts) {
          currentChaptersCount += act.chapters.length;
          for (final chapter in act.chapters) {
            currentScenesCount += chapter.scenes.length;
          }
        }
        
        bool shouldRefreshUI = false;
        
        // 检测结构变化
        if (_lastScenesCount != null) {
          // Act数量变化
          if (_lastActsCount != null && _lastActsCount != currentActsCount) {
            AppLogger.i('EditorScreenController', 
                '检测到Act数量变化: ${_lastActsCount}->$currentActsCount，触发UI更新');
            shouldRefreshUI = true;
          }
          
          // 章节数量变化
          if (_lastChaptersCount != null && _lastChaptersCount != currentChaptersCount) {
            AppLogger.i('EditorScreenController', 
                '检测到章节数量变化: ${_lastChaptersCount}->$currentChaptersCount，触发UI更新');
            shouldRefreshUI = true;
          }
          
          // 场景数量变化
          if (_lastScenesCount != currentScenesCount) {
            AppLogger.i('EditorScreenController', 
                '检测到场景数量变化: ${_lastScenesCount}->$currentScenesCount，触发UI更新');
            shouldRefreshUI = true;
          }
        }
        
        // 加载状态变化检测
        if (!state.isLoading && _isLoadingMore) {
          AppLogger.i('EditorScreenController', '加载完成，通知UI刷新');
          shouldRefreshUI = true;
          _isLoadingMore = false;
        }
        
        // 更新记录的数量
        _lastActsCount = currentActsCount;
        _lastScenesCount = currentScenesCount;
        _lastChaptersCount = currentChaptersCount;
        
        // 记录加载状态
        _isLoadingMore = state.isLoading;
        
        // 如果需要刷新UI，通知EditorMainArea
        if (shouldRefreshUI) {
          _notifyMainAreaToRefresh();
          
          // 🚀 新增：小说结构变化时更新级联菜单数据
          _updateCascadeMenuData();
        }
      } else if (state is editor_bloc.EditorLoading) {
        // 记录Loading状态开始
        _isLoadingMore = true;
      }
    });
  }
  
  // 通知EditorMainArea刷新UI
  void _notifyMainAreaToRefresh() {
    if (editorMainAreaKey.currentState != null) {
      // 直接调用EditorMainArea的refreshUI方法
      editorMainAreaKey.currentState!.refreshUI();
      AppLogger.i('EditorScreenController', '通知EditorMainArea刷新UI');
    } else {
      AppLogger.w('EditorScreenController', '无法获取EditorMainArea实例，无法刷新UI');
      
      // 如果无法获取EditorMainArea实例，使用备用方案
      try {
        // 尝试通过setState刷新
        editorMainAreaKey.currentState?.setState(() {
          AppLogger.i('EditorScreenController', '尝试通过setState刷新EditorMainArea');
        });
      } catch (e) {
        AppLogger.e('EditorScreenController', '尝试刷新EditorMainArea失败', e);
      }
      
      // 通过重建整个编辑区来强制刷新
      notifyListeners();
    }
  }


  // 性能监控变量
  Timer? _scrollPerformanceTimer;
  final List<double> _scrollPerformanceStats = [];
  double _maxFrameDuration = 0;
  Stopwatch _scrollStopwatch = Stopwatch();

  // 为指定章节手动加载场景内容
  void loadScenesForChapter(String actId, String chapterId) {
    AppLogger.i('EditorScreenController', '手动加载卷 $actId 章节 $chapterId 的场景');
    
    editorBloc.add(editor_bloc.LoadMoreScenes(
      fromChapterId: chapterId,
      actId: actId,
      direction: 'center',
      chaptersLimit: 2, // 加载当前章节及其前后章节
    ));
  }

  // 为章节目录加载所有场景内容（不分页）
  void loadAllScenesForChapter(String actId, String chapterId, {bool disableAutoScroll = true}) {
    AppLogger.i('EditorScreenController', '加载章节的所有场景内容: $chapterId, 禁用自动滚动: $disableAutoScroll');

    // 始终禁用自动跳转，通过不传递targetScene相关参数实现
    editorBloc.add(editor_bloc.LoadMoreScenes(
      fromChapterId: chapterId,
      actId: actId,
      direction: 'center',
      chaptersLimit: 10, // 设置较大的限制，尝试加载更多场景
    ));
  }

  // 预加载章节场景但不改变焦点
  Future<void> preloadChapterScenes(String chapterId, {String? actId}) async {
    AppLogger.i('EditorScreenController', '预加载章节场景: 章节ID=$chapterId, ${actId != null ? "卷ID=$actId" : "自动查找卷ID"}');

    // 检查当前状态，如果场景已经加载，则不需要再次加载
    final state = editorBloc.state;
    if (state is editor_bloc.EditorLoaded) {
      // 如果没有提供actId，则自动查找章节所属的卷
      String? targetActId = actId;
      if (targetActId == null) {
        // 在当前加载的小说结构中查找章节所属的卷
        for (final act in state.novel.acts) {
          for (final chapter in act.chapters) {
            if (chapter.id == chapterId) {
              targetActId = act.id;
              break;
            }
          }
          if (targetActId != null) break;
        }
        
        if (targetActId == null) {
          AppLogger.w('EditorScreenController', '无法确定章节 $chapterId 所属的卷ID');
          return;
        }
      }
      
      // 检查目标章节是否已经存在场景
      bool hasScenes = false;
      
      // 先在已加载的Acts中查找章节
      for (final act in state.novel.acts) {
        if (act.id == targetActId) {
          for (final chapter in act.chapters) {
            if (chapter.id == chapterId) {
              hasScenes = chapter.scenes.isNotEmpty;
              break;
            }
          }
          break;
        }
      }
      
      // 如果章节已经有场景，就不需要再次加载
      if (hasScenes) {
        AppLogger.i('EditorScreenController', '章节 $chapterId 已有场景，不需要重新加载');
        return;
      }

      // 为防止方法返回void类型导致的错误，创建一个Completer
      final completer = Completer<void>();
      
      // 定义一个订阅变量
      StreamSubscription<editor_bloc.EditorState>? subscription;
      
      // 监听状态变化，以便在加载完成时完成Future
      subscription = editorBloc.stream.listen((state) {
        if (state is editor_bloc.EditorLoaded && !state.isLoading) {
          // 检查章节是否已有场景
          bool nowHasScenes = false;
          for (final act in state.novel.acts) {
            if (act.id == targetActId) {
              for (final chapter in act.chapters) {
                if (chapter.id == chapterId) {
                  nowHasScenes = chapter.scenes.isNotEmpty;
                  break;
                }
              }
              break;
            }
          }
          
          if (nowHasScenes) {
            AppLogger.i('EditorScreenController', '章节 $chapterId 场景已成功加载');
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete();
          }
        }
      });
      
      // 设置超时，防止无限等待
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          AppLogger.w('EditorScreenController', '预加载章节场景超时');
          subscription?.cancel();
          completer.complete(); // 即使超时也完成Future
        }
      });

      // 使用参数preventFocusChange=true确保不会改变焦点
      editorBloc.add(editor_bloc.LoadMoreScenes(
        fromChapterId: chapterId,
        actId: targetActId,
        direction: 'center',
        chaptersLimit: 5,
        preventFocusChange: true, // 设置为true避免改变焦点
        loadFromLocalOnly: false  // 从服务器加载，确保有最新数据
      ));
      
      // 返回Future，以便调用者等待加载完成
      return completer.future;
    }
  }

  // 🚀 修改：切换Plan视图使用EditorBloc的模式切换
  void togglePlanView() {
    AppLogger.i('EditorScreenController', '切换Plan视图，当前状态: $isPlanViewActive');
    
    // 切换状态
    isPlanViewActive = !isPlanViewActive;

    // 如果激活Plan视图，关闭剧情推演视图
    if (isPlanViewActive) {
      isNextOutlineViewActive = false;
      // 🚀 修改：使用EditorBloc切换到Plan模式
      editorBloc.add(const editor_bloc.SwitchToPlanView());
    } else {
      // 🚀 修改：使用EditorBloc切换到Write模式（包含无感刷新）
      editorBloc.add(const editor_bloc.SwitchToWriteView());
    }

    // 记录日志
    AppLogger.i('EditorScreenController', '切换后的Plan视图状态: $isPlanViewActive');

    notifyListeners();
  }

  // 切换剧情推演视图
  void toggleNextOutlineView() {
    AppLogger.i('EditorScreenController', '切换剧情推演视图，当前状态: $isNextOutlineViewActive');

    // 切换状态
    isNextOutlineViewActive = !isNextOutlineViewActive;

    // 如果激活剧情推演视图，关闭其他视图
    if (isNextOutlineViewActive) {
      isPlanViewActive = false;
      isPromptViewActive = false;
    }

    // 记录日志
    AppLogger.i('EditorScreenController', '切换后的剧情推演视图状态: $isNextOutlineViewActive');

    notifyListeners();
  }

  // 切换提示词视图
  void togglePromptView() {
    AppLogger.i('EditorScreenController', '切换提示词视图，当前状态: $isPromptViewActive');

    // 切换状态
    isPromptViewActive = !isPromptViewActive;

    // 如果激活提示词视图，关闭其他视图
    if (isPromptViewActive) {
      isPlanViewActive = false;
      isNextOutlineViewActive = false;
    }

    // 记录日志
    AppLogger.i('EditorScreenController', '切换后的提示词视图状态: $isPromptViewActive');

    notifyListeners();
  }

  // 获取同步服务并同步当前小说
  Future<void> syncCurrentNovel() async {
    try {
      final editorRepository = EditorRepositoryImpl();
      final localStorageService = editorRepository.getLocalStorageService();

      // 检查是否有要同步的内容
      final novelId = novel.id;
      final novelSyncList = await localStorageService.getSyncList('novel');
      final sceneSyncList = await localStorageService.getSyncList('scene');
      final editorSyncList = await localStorageService.getSyncList('editor');

      final hasNovelToSync = novelSyncList.contains(novelId);
      final hasScenesToSync = sceneSyncList.any((sceneKey) => sceneKey.startsWith(novelId));
      final hasEditorToSync = editorSyncList.any((editorKey) => editorKey.startsWith(novelId));

      if (hasNovelToSync || hasScenesToSync || hasEditorToSync) {
        AppLogger.i('EditorScreenController', '检测到待同步内容，执行退出前同步: ${novel.id}');

        // 使用已初始化的同步服务执行同步
        await syncService.syncAll();

        AppLogger.i('EditorScreenController', '退出前同步完成: ${novel.id}');
      } else {
        AppLogger.i('EditorScreenController', '没有待同步内容，跳过退出前同步: ${novel.id}');
      }
    } catch (e) {
      AppLogger.e('EditorScreenController', '退出前同步失败', e);
    }
  }

  // 清理所有控制器
  void clearAllControllers() {
    AppLogger.i('EditorScreenController', '清理所有控制器');
    for (final controller in sceneControllers.values) {
      try {
        controller.dispose();
      } catch (e) {
        AppLogger.e('EditorScreenController', '关闭场景控制器失败', e);
      }
    }
    sceneControllers.clear();

    for (final controller in sceneTitleControllers.values) {
      controller.dispose();
    }
    sceneTitleControllers.clear();
    for (final controller in sceneSubtitleControllers.values) {
      controller.dispose();
    }
    sceneSubtitleControllers.clear();
    for (final controller in sceneSummaryControllers.values) {
      controller.dispose();
    }
    sceneSummaryControllers.clear();
    // Clear GlobalKeys map
    sceneKeys.clear();
  }

  // 获取可见场景ID列表
  List<String> _getVisibleSceneIds() {
    if (editorBloc.state is! editor_bloc.EditorLoaded) return [];

    final state = editorBloc.state as editor_bloc.EditorLoaded;
    final visibleSceneIds = <String>[];

    // 提取所有场景ID
    for (final act in state.novel.acts) {
      for (final chapter in act.chapters) {
        for (final scene in chapter.scenes) {
          final sceneId = '${act.id}_${chapter.id}_${scene.id}';

          // 检查该场景是否可见
          final key = sceneKeys[sceneId];
          if (key?.currentContext != null) {
            final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final scenePosition = renderBox.localToGlobal(Offset.zero);
              final sceneHeight = renderBox.size.height;

              // 计算场景的顶部和底部位置
              final sceneTop = scenePosition.dy;
              final sceneBottom = sceneTop + sceneHeight;

              // 获取屏幕高度
              final screenHeight = MediaQuery.of(key.currentContext!).size.height;

              // 扩展可见区域，预加载前后的场景
              final extendedVisibleTop = -screenHeight;
              final extendedVisibleBottom = screenHeight * 2;

              // 判断场景是否在可见区域内
              if (sceneBottom >= extendedVisibleTop && sceneTop <= extendedVisibleBottom) {
                visibleSceneIds.add(sceneId);
              }
            }
          }
        }
      }
    }

    // 如果没有可见场景（可能还在初始加载），添加活动场景
    if (visibleSceneIds.isEmpty && state.activeActId != null &&
        state.activeChapterId != null && state.activeSceneId != null) {
      visibleSceneIds.add('${state.activeActId}_${state.activeChapterId}_${state.activeSceneId}');
    }

    return visibleSceneIds;
  }





  // 确保控制器的优化版本
  void ensureControllersForNovel(novel_models.Novel novel) {
    // 获取并处理当前可见场景
    final visibleSceneIds = _getVisibleSceneIds();

    // 仅为可见场景创建控制器
    bool controllersCreated = false;

    // 遍历当前加载的小说数据
    for (final act in novel.acts) {
      for (final chapter in act.chapters) {
        for (final scene in chapter.scenes) {
          final sceneId = '${act.id}_${chapter.id}_${scene.id}';

          // 如果是可见场景，且控制器不存在，则创建
          if (visibleSceneIds.contains(sceneId) && !sceneControllers.containsKey(sceneId)) {
            _createControllerForScene(act.id, chapter.id, scene);
            controllersCreated = true;
          }
        }
      }
    }

    // 只在创建了新控制器时输出日志
    if (controllersCreated) {
      AppLogger.d('EditorScreenController', '已为可见场景创建控制器，当前控制器数: ${sceneControllers.length}');
    }
  }

  // 为单个场景创建控制器
  void _createControllerForScene(String actId, String chapterId, novel_models.Scene scene) {
    final sceneId = '${actId}_${chapterId}_${scene.id}';

    try {
      // 🚀 修复：检查是否是新建场景，确保使用正确的空内容
      String contentToUse = scene.content;
      

      
      // 创建QuillController
      final controller = QuillController(
        document: _parseDocumentSafely(contentToUse),
        selection: const TextSelection.collapsed(offset: 0),
      );

      // 创建摘要控制器
      final summaryController = TextEditingController(
        text: scene.summary.content,
      );

      // 存储控制器
      sceneControllers[sceneId] = controller;
      sceneSummaryControllers[sceneId] = summaryController;

      // 创建GlobalKey
      if (!sceneKeys.containsKey(sceneId)) {
        sceneKeys[sceneId] = GlobalKey();
      }
    } catch (e) {
      AppLogger.e('EditorScreenController', '为场景创建控制器失败: $sceneId', e);

      // 创建默认控制器
      sceneControllers[sceneId] = QuillController(
        document: Document.fromJson([{'insert': '\n'}]),
        selection: const TextSelection.collapsed(offset: 0),
      );
      sceneSummaryControllers[sceneId] = TextEditingController(text: '');
    }
  }

  // 安全解析文档内容
  Document _parseDocumentSafely(String content) {
    try {
      if (content.isEmpty) {
        return Document.fromJson([{'insert': '\n'}]);
      }

      final dynamic decodedContent = jsonDecode(content);

      // 处理不同的内容格式
      if (decodedContent is List) {
        // 如果直接是List，验证格式后使用
        return Document.fromJson(decodedContent);
      } else if (decodedContent is Map<String, dynamic>) {
        // 检查是否是Quill格式的对象（包含ops字段）
        if (decodedContent.containsKey('ops') && decodedContent['ops'] is List) {
          return Document.fromJson(decodedContent['ops'] as List);
        } else {
          // 不是标准Quill格式，记录详细错误信息
          AppLogger.e('EditorScreenController', '解析场景内容失败: 不是有效的Quill文档格式 ${decodedContent.runtimeType}');
          return Document.fromJson([{'insert': '\n'}]);
        }
      } else {
        // 不支持的内容格式
        AppLogger.e('EditorScreenController', '解析场景内容失败: 不支持的内容格式 ${decodedContent.runtimeType}');
        return Document.fromJson([{'insert': '\n'}]);
      }
    } catch (e) {
      AppLogger.e('EditorScreenController', '解析场景内容失败', e);
      // 不再返回"内容加载失败"而是返回空文档，避免显示错误信息
      return Document.fromJson([{'insert': '\n'}]);
    }
  }

  // 场景控制器防抖定时器
  Timer? _visibleScenesDebounceTimer;

  // 通知小说列表刷新
  void notifyNovelListRefresh(BuildContext context) {
    try {
      // 尝试获取NovelListBloc并触发刷新
      try {
        context.read<NovelListBloc>().add(LoadNovels());
        AppLogger.i('EditorScreenController', '已触发小说列表刷新');
      } catch (e) {
        AppLogger.w('EditorScreenController', '小说列表Bloc不可用，无法触发刷新');
      }
    } catch (e) {
      AppLogger.e('EditorScreenController', '尝试刷新小说列表时出错', e);
    }
  }

  // 添加小说结构更新事件监听
  void _setupNovelStructureListener() {
    _novelStructureSubscription = EventBus.instance.on<NovelStructureUpdatedEvent>().listen((event) {
      if (event.novelId == novel.id) {
        AppLogger.i('EditorScreenController', '收到小说结构更新事件: ${event.updateType}. 此事件现在主要由Sidebar处理，EditorScreenController不再因此刷新主编辑区。');
        
        // 对于特定的事件，选择性刷新
        if (event.updateType == 'MERGE_NEW_CHAPTER' || 
            event.updateType == 'SCENE_CONTENT_UPDATED') {
          AppLogger.i('EditorScreenController', '检测到需刷新事件，触发编辑器刷新: ${event.updateType}');
          editorBloc.add(const editor_bloc.RefreshEditorData(
            preserveActiveScene: true,
            source: 'structure_update',
          ));
        } else if (event.updateType == 'SCENE_ADDED') {
          // 场景已添加：若当前状态里已包含该场景，则跳过刷新，避免重复拉取导致锚点短暂失效
          try {
            final currentState = editorBloc.state;
            if (currentState is editor_bloc.EditorLoaded) {
              final String? chapterId = event.data['chapterId']?.toString();
              final String? sceneId = event.data['sceneId']?.toString();
              bool alreadyPresent = false;
              if (chapterId != null && sceneId != null) {
                for (final act in currentState.novel.acts) {
                  for (final chapter in act.chapters) {
                    if (chapter.id == chapterId) {
                      for (final scene in chapter.scenes) {
                        if (scene.id == sceneId) { alreadyPresent = true; break; }
                      }
                      break;
                    }
                  }
                  if (alreadyPresent) break;
                }
              }
              if (!alreadyPresent) {
                AppLogger.i('EditorScreenController', '新增场景未出现在当前状态，触发一次无感刷新');
                editorBloc.add(const editor_bloc.RefreshEditorData(
                  preserveActiveScene: true,
                  source: 'structure_update_scene_added',
                ));
              } else {
                AppLogger.i('EditorScreenController', '新增场景已在当前状态中，跳过刷新');
              }
            }
          } catch (e) {
            AppLogger.w('EditorScreenController', '处理SCENE_ADDED事件时校验失败，退回刷新', e);
            editorBloc.add(const editor_bloc.RefreshEditorData(
              preserveActiveScene: true,
              source: 'structure_update_scene_added_fallback',
            ));
          }
        } else if (event.updateType == 'NOVEL_STRUCTURE_SAVED' || event.updateType == 'CHAPTER_ADDED') {
          // 结构保存或新增章节后，校验焦点章节是否仍然存在
          try {
            final currentState = editorBloc.state;
            if (currentState is editor_bloc.EditorLoaded) {
              final String? focusChapterId = currentState.focusChapterId;
              bool exists = false;
              if (focusChapterId != null) {
                for (final act in currentState.novel.acts) {
                  for (final chapter in act.chapters) {
                    if (chapter.id == focusChapterId) { exists = true; break; }
                  }
                  if (exists) break;
                }
              }
              if (!exists) {
                final String? fallback = currentState.activeChapterId ?? currentState.novel.lastEditedChapterId;
                if (fallback != null) {
                  AppLogger.i('EditorScreenController', '焦点章节已失效，回退并重设焦点: $fallback');
                  editorBloc.add(editor_bloc.SetFocusChapter(chapterId: fallback));
                }
              }
            }
          } catch (e) {
            AppLogger.w('EditorScreenController', '刷新后焦点章节校验失败', e);
          }
        }
        // _refreshNovelStructure(); // 注释掉此行，防止主编辑区刷新
      }
    });

    // 监听通用的外部场景内容更新事件：就地更新对应QuillController并保持滚动/焦点
    EventBus.instance.on<SceneContentExternallyUpdatedEvent>().listen((event) {
      if (event.novelId != novel.id) return;
      try {
        final String compositeId = () {
          if (event.actId != null) {
            return '${event.actId}_${event.chapterId}_${event.sceneId}';
          }
          // 若缺失actId，从EditorBloc的当前状态定位
          final currentState = editorBloc.state;
          if (currentState is editor_bloc.EditorLoaded) {
            for (final act in currentState.novel.acts) {
              for (final chapter in act.chapters) {
                if (chapter.id == event.chapterId) {
                  return '${act.id}_${event.chapterId}_${event.sceneId}';
                }
              }
            }
          }
          // 回退：若未能定位，则使用活动上下文（可能不是目标场景）
          if (currentState is editor_bloc.EditorLoaded &&
              currentState.activeActId != null &&
              currentState.activeChapterId != null) {
            return '${currentState.activeActId}_${event.chapterId}_${event.sceneId}';
          }
          return '';
        }();
        if (compositeId.isEmpty) return;

        final controller = sceneControllers[compositeId];
        if (controller != null) {
          // 确保内容为标准Quill JSON
          final doc = _parseDocumentSafely(event.content);
          controller.document = doc;
          AppLogger.i('EditorScreenController', '已就地刷新场景内容: $compositeId');

          // 同步更新EditorBloc中的模型（本地，不触发服务器同步），避免对话框作用域下Provider获取失败
          try {
            final currentState = editorBloc.state;
            if (currentState is editor_bloc.EditorLoaded) {
              // 定位actId（通过chapterId查找所在act）
              String? actId;
              for (final act in currentState.novel.acts) {
                final found = act.chapters.any((c) => c.id == event.chapterId);
                if (found) { actId = act.id; break; }
              }
              if (actId != null) {
                // 计算字数（基于Quill Delta）
                final String wc = WordCountAnalyzer.countWords(event.content).toString();

                editorBloc.add(editor_bloc.SaveSceneContent(
                  novelId: novel.id,
                  actId: actId,
                  chapterId: event.chapterId,
                  sceneId: event.sceneId,
                  content: event.content,
                  wordCount: wc,
                  localOnly: true,
                ));
              }
            }
          } catch (e) {
            AppLogger.w('EditorScreenController', '就地刷新后同步本地模型失败（忽略，不影响UI）', e);
          }
        } else {
          // 控制器尚未创建，下一次ensureControllers会加载；也触发一次轻量刷新以稳妥
          AppLogger.i('EditorScreenController', '未找到控制器，触发无感刷新以创建控制器: $compositeId');
          editorBloc.add(const editor_bloc.RefreshEditorData(
            preserveActiveScene: true,
            source: 'external_scene_update',
          ));
        }
      } catch (e) {
        AppLogger.w('EditorScreenController', '处理外部场景内容更新事件失败', e);
      }
    });
  }
  
  // 释放资源
  @override
  void dispose() {
    AppLogger.i('EditorScreenController', '开始销毁编辑器控制器');
    
    // 设置dispose标志
    _isDisposed = true;

    // 停止性能监控
    _scrollPerformanceTimer?.cancel();

    // 释放所有控制器
    for (final controller in sceneControllers.values) {
      controller.dispose();
    }
    sceneControllers.clear();

    // 释放其他控制器
    for (final controller in sceneSummaryControllers.values) {
      controller.dispose();
    }
    sceneSummaryControllers.clear();

    scrollController.dispose();

    // 释放TabController
    tabController.dispose();

    // 释放FocusNode
    focusNode.dispose();

    // 尝试同步当前小说数据
    syncCurrentNovel();

    // 清理控制器资源
    clearAllControllers();

    // 关闭同步服务
    syncService.dispose();

    // 清理BLoC
    editorBloc.close();
    
    // 🚀 新增：清理SettingBloc
    settingBloc.close();

    // 🚀 移除：不再需要清理PlanBloc
    // planBloc.close();

    // 取消小说结构更新事件订阅
    _novelStructureSubscription?.cancel();

    super.dispose();
  }

  // /// 加载所有场景摘要
  // void loadAllSceneSummaries() {
  //   // 防止重复加载，添加节流控制
  //   final now = DateTime.now();
  //   if (_isLoadingSummaries) {
  //     AppLogger.i('EditorScreenController', '正在加载摘要，跳过重复请求');
  //     return;
  //   }
    
  //   if (_lastSummaryLoadTime != null && 
  //       now.difference(_lastSummaryLoadTime!) < _summaryLoadThrottleInterval) {
  //     AppLogger.i('EditorScreenController', 
  //         '摘要加载过于频繁，上次加载时间: ${_lastSummaryLoadTime!.toString()}, 跳过此次请求');
  //     return;
  //   }
    
  //   _isLoadingSummaries = true;
  //   _lastSummaryLoadTime = now;
    
  //   AppLogger.i('EditorScreenController', '开始加载所有场景摘要');
    
  //   // 使用带有场景摘要的API直接加载完整小说数据
  //   editorRepository.getNovelWithSceneSummaries(novel.id).then((novelWithSummaries) {
  //     if (novelWithSummaries != null) {
  //       AppLogger.i('EditorScreenController', '已加载所有场景摘要');

  //       // 更新编辑器状态
  //       editorBloc.add(editor_bloc.LoadEditorContentPaginated(
  //         novelId: novel.id,
  //         lastEditedChapterId: novel.lastEditedChapterId,
  //         chaptersLimit: 10,
  //         loadAllSummaries: true,  // 指示加载所有摘要
  //       ));
  //     } else {
  //       AppLogger.w('EditorScreenController', '加载所有场景摘要失败');
  //     }
  //   }).catchError((error) {
  //     AppLogger.e('EditorScreenController', '加载所有场景摘要出错', error);
  //   }).whenComplete(() {
  //     // 无论成功失败，完成后更新状态
  //     _isLoadingSummaries = false;
  //   });
  // }


  // 更新加载进度和消息
  void _updateLoadingProgress(String message, {bool isComplete = false}) {
    // 🚀 修复：检查是否已经disposed，避免在disposed后调用notifyListeners
    if (_isDisposed) {
      AppLogger.w('EditorScreenController', '控制器已销毁，跳过加载进度更新: $message');
      return;
    }
    
    _loadingMessage = message;
    
    if (isComplete) {
      _setProgressTarget(1.0);
    } else {
      // 每个阶段把目标值推进一段，但不超过0.9，避免过早完成
      final double nextTarget = (_progressTarget + 0.15).clamp(0.0, 0.9);
      _setProgressTarget(nextTarget);
    }
    
    AppLogger.i('EditorScreenController', 
        '加载进度更新(目标): ${(loadingProgress * 100).toInt()}% -> ${(_progressTarget * 100).toInt()}%, 消息: $_loadingMessage');
    
    // 通知UI更新加载状态
    notifyListeners();
  }

  // 启动进度补间计时器
  void _startProgressTicker() {
    _progressTimer ??= Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_isDisposed) {
        _stopProgressTicker();
        return;
      }
      const double easing = 0.12; // 趋近速度
      final double delta = _progressTarget - _progressAnimated;
      if (delta.abs() < 0.002) {
        _progressAnimated = _progressTarget;
        if (_progressTarget >= 1.0) {
          // 完成后停止计时器
          _stopProgressTicker();
        }
      } else {
        _progressAnimated += delta * easing;
      }
      // 仅在覆盖层可见时刷新
      if (_isFullscreenLoading) {
        notifyListeners();
      }
    });
  }

  void _stopProgressTicker() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _setProgressTarget(double value) {
    _progressTarget = value.clamp(0.0, 1.0);
    if (_progressTimer == null) {
      _startProgressTicker();
    }
  }

  // 数据就绪后等待首帧渲染结束再关闭覆盖层
  void _completeLoadingWhenFirstFrameReady() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 保证覆盖层至少显示一定时间，避免闪烁
        final minVisible = const Duration(milliseconds: 800);
        final shown = _overlayShownAt ?? DateTime.now();
        final elapsed = DateTime.now().difference(shown);
        if (elapsed < minVisible) {
          await Future.delayed(minVisible - elapsed);
        }
        _setProgressTarget(1.0);
        // 给进度动画一点时间到达100%
        await Future.delayed(const Duration(milliseconds: 200));
        _isFullscreenLoading = false;
        notifyListeners();
      });
    } catch (e) {
      AppLogger.w('EditorScreenController', '等待首帧渲染失败，提前关闭加载覆盖层', e);
      _isFullscreenLoading = false;
      notifyListeners();
    }
  }
  
  // 显示全屏加载动画
  void showFullscreenLoading(String message) {
    _loadingMessage = message;
    _isFullscreenLoading = true;
    _overlayShownAt = DateTime.now();
    _startProgressTicker();
    notifyListeners();
  }
  
  // 隐藏全屏加载动画
  void hideFullscreenLoading() {
    _isFullscreenLoading = false;
    _stopProgressTicker();
    notifyListeners();
  }
  
  /// 创建新卷，并自动创建一个章节和一个场景
  /// 完成后会将焦点设置到新创建的章节和场景
  Future<void> createNewAct() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final defaultActTitle = '新卷 $timestamp';

    showFullscreenLoading('正在创建新卷...');
    AppLogger.i('EditorScreenController', '开始创建新卷: $defaultActTitle');

    try {
        // Step 1: Create New Act
        final String newActId = await _internalCreateNewAct(defaultActTitle);
        AppLogger.i('EditorScreenController', '新卷创建成功，ID: $newActId');

        _loadingMessage = '正在创建新章节...';
        notifyListeners();

        // Step 2: Create New Chapter
        final String newChapterId = await _internalCreateNewChapter(newActId, '新章节 $timestamp');
        AppLogger.i('EditorScreenController', '新章节创建成功，ID: $newChapterId');

        _loadingMessage = '正在创建新场景...';
        notifyListeners();

        // Step 3: Create New Scene
        final String newSceneId = await _internalCreateNewScene(newActId, newChapterId, 'scene_$timestamp');
        AppLogger.i('EditorScreenController', '新场景创建成功，ID: $newSceneId');

        _loadingMessage = '正在设置编辑焦点...';
        notifyListeners();

        // Step 4: Set Focus
        editorBloc.add(editor_bloc.SetActiveChapter(
            actId: newActId,
            chapterId: newChapterId,
        ));
        editorBloc.add(editor_bloc.SetActiveScene(
            actId: newActId,
            chapterId: newChapterId,
            sceneId: newSceneId,
        ));
        editorBloc.add(editor_bloc.SetFocusChapter(
            chapterId: newChapterId,
        ));

        _notifyMainAreaToRefresh();
        hideFullscreenLoading();
        AppLogger.i('EditorScreenController', '新卷创建流程完成: actId=$newActId, chapterId=$newChapterId, sceneId=$newSceneId');

    } catch (e) {
        AppLogger.e('EditorScreenController', '创建新卷流程失败', e);
        hideFullscreenLoading();
        // Optionally, show an error message to the user
    }
  }

  // Helper method to create Act and wait for completion
  Future<String> _internalCreateNewAct(String title) async {
    final completer = Completer<String>();
    StreamSubscription<editor_bloc.EditorState>? subscription;

    final initialState = editorBloc.state;
    int initialActCount = 0;
    List<String> initialActIds = [];
    if (initialState is editor_bloc.EditorLoaded) {
        initialActCount = initialState.novel.acts.length;
        initialActIds = initialState.novel.acts.map((act) => act.id).toList();
    }

    subscription = editorBloc.stream.listen((state) {
        if (state is editor_bloc.EditorLoaded && !state.isLoading) {
            if (state.novel.acts.length > initialActCount) {
                final newAct = state.novel.acts.firstWhereOrNull(
                    (act) => !initialActIds.contains(act.id)
                );
                if (newAct != null) {
                  subscription?.cancel();
                  if (!completer.isCompleted) {
                      completer.complete(newAct.id);
                  }
                } else if (state.novel.acts.isNotEmpty && state.novel.acts.length > initialActCount) {
                    // Fallback: if specific new act not found but count increased, assume last one
                    final potentialNewAct = state.novel.acts.last;
                    // Basic check to avoid completing with an old act if list got reordered somehow
                    if (!initialActIds.contains(potentialNewAct.id)) {
                        subscription?.cancel();
                        if (!completer.isCompleted) {
                            completer.complete(potentialNewAct.id);
                        }
                    }
                }
            }
        }
    });

    editorBloc.add(editor_bloc.AddNewAct(title: title));

    try {
        return await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
            subscription?.cancel();
            throw Exception('创建新卷超时');
        });
    } catch (e) {
        subscription?.cancel();
        rethrow;
    }
}

// Helper method to create Chapter and wait for completion
Future<String> _internalCreateNewChapter(String actId, String title) async {
    final completer = Completer<String>();
    StreamSubscription<editor_bloc.EditorState>? subscription;

    final initialChapterState = editorBloc.state;
    int initialChapterCountInAct = 0;
    List<String> initialChapterIdsInAct = [];
    if (initialChapterState is editor_bloc.EditorLoaded) {
        final act = initialChapterState.novel.acts.firstWhereOrNull((a) => a.id == actId);
        if (act != null) {
            initialChapterCountInAct = act.chapters.length;
            initialChapterIdsInAct = act.chapters.map((ch) => ch.id).toList();
        }
    }
    
    subscription = editorBloc.stream.listen((state) {
        if (state is editor_bloc.EditorLoaded && !state.isLoading) {
            final currentAct = state.novel.acts.firstWhereOrNull((a) => a.id == actId);
            if (currentAct != null && currentAct.chapters.length > initialChapterCountInAct) {
                 final newChapter = currentAct.chapters.firstWhereOrNull(
                    (ch) => !initialChapterIdsInAct.contains(ch.id)
                );
                if (newChapter != null) {
                    subscription?.cancel();
                    if (!completer.isCompleted) {
                        completer.complete(newChapter.id);
                    }
                } else if (currentAct.chapters.isNotEmpty && currentAct.chapters.length > initialChapterCountInAct) {
                    final potentialNewChapter = currentAct.chapters.last;
                    if (!initialChapterIdsInAct.contains(potentialNewChapter.id)){
                        subscription?.cancel();
                        if (!completer.isCompleted) {
                            completer.complete(potentialNewChapter.id);
                        }
                    }
                }
            }
        }
    });

    editorBloc.add(editor_bloc.AddNewChapter(
        novelId: editorBloc.novelId,
        actId: actId,
        title: title,
    ));

    try {
        return await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
            subscription?.cancel();
            throw Exception('创建新章节超时');
        });
    } catch (e) {
        subscription?.cancel();
        rethrow;
    }
}


// Helper method to create Scene and wait for completion
Future<String> _internalCreateNewScene(String actId, String chapterId, String sceneIdProposal) async {
    final completer = Completer<String>();
    StreamSubscription<editor_bloc.EditorState>? subscription;

    final initialSceneState = editorBloc.state;
    int initialSceneCountInChapter = 0;
    List<String> initialSceneIdsInChapter = [];

    if (initialSceneState is editor_bloc.EditorLoaded) {
        final act = initialSceneState.novel.acts.firstWhereOrNull((a) => a.id == actId);
        if (act != null) {
            final chapter = act.chapters.firstWhereOrNull((c) => c.id == chapterId);
            if (chapter != null) {
                initialSceneCountInChapter = chapter.scenes.length;
                initialSceneIdsInChapter = chapter.scenes.map((sc) => sc.id).toList();
            }
        }
    }

    subscription = editorBloc.stream.listen((state) {
        if (state is editor_bloc.EditorLoaded && !state.isLoading) {
            final currentAct = state.novel.acts.firstWhereOrNull((a) => a.id == actId);
            if (currentAct != null) {
                final currentChapter = currentAct.chapters.firstWhereOrNull((c) => c.id == chapterId);
                if (currentChapter != null && currentChapter.scenes.length > initialSceneCountInChapter) {
                    final newScene = currentChapter.scenes.firstWhereOrNull(
                        (sc) => !initialSceneIdsInChapter.contains(sc.id)
                    );
                    if (newScene != null) {
                        subscription?.cancel();
                        if (!completer.isCompleted) {
                            completer.complete(newScene.id);
                        }
                    } else if (currentChapter.scenes.isNotEmpty && currentChapter.scenes.length > initialSceneCountInChapter){
                        final potentialNewScene = currentChapter.scenes.last;
                        if (!initialSceneIdsInChapter.contains(potentialNewScene.id)) {
                            subscription?.cancel();
                            if (!completer.isCompleted) {
                                completer.complete(potentialNewScene.id);
                            }
                        }
                    }
                }
            }
        }
    });

    editorBloc.add(editor_bloc.AddNewScene(
        novelId: editorBloc.novelId,
        actId: actId,
        chapterId: chapterId,
        sceneId: sceneIdProposal, // Use the proposed ID
    ));

   try {
        return await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
            subscription?.cancel();
            throw Exception('创建新场景超时');
        });
    } catch (e) {
        subscription?.cancel();
        rethrow;
    }
}


/// 启用性能监控和优化（已禁用）
void _initializePerformanceOptimization() {
  // 性能监控已移除
}

/// 预热文档解析器（已禁用）








/// 智能预加载策略（已禁用）
void _intelligentPreloading() {
  // 智能预加载功能已移除
}



  // 🚀 新增：等待编辑器就绪后初始化级联菜单数据
  void _initializeCascadeMenuDataWhenReady() {
    // 监听EditorBloc状态，等待加载完成后初始化级联菜单数据
    editorBloc.stream.listen((state) {
      if (state is editor_bloc.EditorLoaded && _cascadeMenuData == null) {
        AppLogger.i('EditorScreenController', '编辑器加载完成，开始初始化级联菜单数据');
        _initializeCascadeMenuData();
      }
    });
  }

  // 🚀 新增：初始化级联菜单数据
  Future<void> _initializeCascadeMenuData() async {
    try {
      AppLogger.i('EditorScreenController', '开始初始化级联菜单数据');
      await _buildCascadeMenuData();
      AppLogger.i('EditorScreenController', '级联菜单数据初始化完成');
    } catch (e) {
      AppLogger.e('EditorScreenController', '初始化级联菜单数据失败', e);
    }
  }

  // 🚀 新增：构建级联菜单数据
  Future<void> _buildCascadeMenuData() async {
    // 节流控制，避免频繁重建
    final now = DateTime.now();
    if (_lastCascadeMenuUpdateTime != null &&
        now.difference(_lastCascadeMenuUpdateTime!) < _cascadeMenuUpdateThrottle) {
      AppLogger.d('EditorScreenController', '级联菜单数据更新被节流');
      return;
    }
    _lastCascadeMenuUpdateTime = now;

    try {
      // 获取当前编辑器状态
      final editorState = editorBloc.state;
      if (editorState is! editor_bloc.EditorLoaded) {
        AppLogger.w('EditorScreenController', '编辑器未加载，无法构建级联菜单数据');
        return;
      }

      // 获取设定和片段数据
      List<NovelSettingItem> settings = [];
      List<SettingGroup> settingGroups = [];
      List<NovelSnippet> snippets = [];

      // 🚀 从SettingBloc获取设定数据
      if (!_isDisposed) {
        final settingState = settingBloc.state;
        settings = settingState.items;
        settingGroups = settingState.groups;
        
        AppLogger.d('EditorScreenController', 
            '获取设定数据: ${settings.length}个设定项, ${settingGroups.length}个设定组');
      }

      // 🚀 构建完整的上下文选择数据
      _cascadeMenuData = ContextSelectionDataBuilder.fromNovelWithContext(
        editorState.novel,
        settings: settings,
        settingGroups: settingGroups,
        snippets: snippets,
      );

      AppLogger.i('EditorScreenController', 
          '级联菜单数据构建完成: ${_cascadeMenuData?.availableItems.length ?? 0}个可选项');

      // 🚀 通知监听者数据已更新
      notifyListeners();

    } catch (e) {
      AppLogger.e('EditorScreenController', '构建级联菜单数据失败', e);
    }
  }

  // 🚀 新增：更新级联菜单数据（响应小说结构变化）
  void _updateCascadeMenuData() {
    if (_isDisposed) return;
    
    AppLogger.d('EditorScreenController', '小说结构变化，更新级联菜单数据');
    
    // 异步更新，避免阻塞UI
    Future.microtask(() async {
      if (!_isDisposed) {
        await _buildCascadeMenuData();
      }
    });
  }

  // 🚀 新增：手动刷新级联菜单数据
  Future<void> refreshCascadeMenuData() async {
    AppLogger.i('EditorScreenController', '手动刷新级联菜单数据');
    await _buildCascadeMenuData();
  }

  // 🚀 新增：选择级联菜单项
  void selectCascadeMenuItem(String itemId) {
    if (_cascadeMenuData == null) {
      AppLogger.w('EditorScreenController', '级联菜单数据未就绪，无法选择项目: $itemId');
      return;
    }

    AppLogger.i('EditorScreenController', '选择级联菜单项: $itemId');
    
    try {
      // 更新选择状态
      _cascadeMenuData = _cascadeMenuData!.selectItem(itemId);
      
      // 处理导航逻辑
      _handleCascadeMenuNavigation(itemId);
      
      notifyListeners();
    } catch (e) {
      AppLogger.e('EditorScreenController', '选择级联菜单项失败: $itemId', e);
    }
  }

  // 🚀 新增：沉浸模式相关方法
  
  /// 切换沉浸模式
  void toggleImmersiveMode() {
    if (_isDisposed) return;
    
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      AppLogger.w('EditorScreenController', '编辑器未加载，无法切换沉浸模式');
      return;
    }
    
    if (currentState.isImmersiveMode) {
      // 切换到普通模式
      switchToNormalMode();
    } else {
      // 切换到沉浸模式
      switchToImmersiveMode();
    }
  }
  
  /// 切换到沉浸模式
  void switchToImmersiveMode({String? chapterId}) {
    if (_isDisposed) return;
    
    AppLogger.i('EditorScreenController', '切换到沉浸模式，指定章节: $chapterId');
    
    // 更新布局管理器状态
    try {
      final layoutManager = _getLayoutManager();
      layoutManager?.enableImmersiveMode();
    } catch (e) {
      AppLogger.w('EditorScreenController', '无法获取布局管理器', e);
    }
    
    // 发送沉浸模式事件到EditorBloc
    editorBloc.add(editor_bloc.SwitchToImmersiveMode(chapterId: chapterId));
    
    notifyListeners();
  }
  
  /// 切换到普通模式
  void switchToNormalMode() {
    if (_isDisposed) return;
    
    AppLogger.i('EditorScreenController', '切换到普通模式');
    
    // 更新布局管理器状态
    try {
      final layoutManager = _getLayoutManager();
      layoutManager?.disableImmersiveMode();
    } catch (e) {
      AppLogger.w('EditorScreenController', '无法获取布局管理器', e);
    }
    
    // 发送普通模式事件到EditorBloc
    editorBloc.add(const editor_bloc.SwitchToNormalMode());
    
    notifyListeners();
  }
  
  /// 导航到下一章（普通/沉浸模式通用）
  void navigateToNextChapter() {
    if (_isDisposed) return;
    
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      AppLogger.w('EditorScreenController', '编辑器未加载，无法导航到下一章');
      return;
    }
    
    AppLogger.i('EditorScreenController', '导航到下一章');
    editorBloc.add(const editor_bloc.NavigateToNextChapter());
  }
  
  /// 导航到上一章（普通/沉浸模式通用）
  void navigateToPreviousChapter() {
    if (_isDisposed) return;
    
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      AppLogger.w('EditorScreenController', '编辑器未加载，无法导航到上一章');
      return;
    }
    
    AppLogger.i('EditorScreenController', '导航到上一章');
    editorBloc.add(const editor_bloc.NavigateToPreviousChapter());
  }
  
  /// 检查是否为沉浸模式
  bool get isImmersiveMode {
    final currentState = editorBloc.state;
    return currentState is editor_bloc.EditorLoaded && currentState.isImmersiveMode;
  }
  
  /// 获取当前沉浸模式的章节ID
  String? get immersiveChapterId {
    final currentState = editorBloc.state;
    if (currentState is editor_bloc.EditorLoaded && currentState.isImmersiveMode) {
      return currentState.immersiveChapterId;
    }
    return null;
  }
  
  /// 检查是否可以导航到下一章（普通/沉浸模式通用）
  bool get canNavigateToNextChapter {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return false;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return false;
    
    // 查找是否有下一章
    bool foundCurrent = false;
    for (final act in currentState.novel.acts) {
      for (final chapter in act.chapters) {
        if (foundCurrent) {
          return true; // 找到下一章
        }
        if (chapter.id == currentChapterId) {
          foundCurrent = true;
        }
      }
    }
    return false;
  }
  
  /// 检查是否可以导航到上一章（普通/沉浸模式通用）
  bool get canNavigateToPreviousChapter {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return false;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return false;
    
    // 遍历找到当前章节的位置，检查是否有上一章
    String? previousChapterId;
    for (final act in currentState.novel.acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == currentChapterId) {
          return previousChapterId != null; // 如果有上一章节ID，说明可以导航
        }
        previousChapterId = chapter.id;
      }
    }
    return false;
  }
  
  /// 🚀 新增：检查当前章节是否为第一章（普通/沉浸模式通用）
  bool get isCurrentChapterFirst {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return false;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return false;
    
    // 检查是否是第一个卷的第一章
    if (currentState.novel.acts.isNotEmpty) {
      final firstAct = currentState.novel.acts.first;
      if (firstAct.chapters.isNotEmpty) {
        return firstAct.chapters.first.id == currentChapterId;
      }
    }
    return false;
  }
  
  /// 🚀 新增：检查当前章节是否为最后一章（普通/沉浸模式通用）
  bool get isCurrentChapterLast {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return false;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return false;
    
    // 检查是否是最后一个卷的最后一章
    if (currentState.novel.acts.isNotEmpty) {
      final lastAct = currentState.novel.acts.last;
      if (lastAct.chapters.isNotEmpty) {
        return lastAct.chapters.last.id == currentChapterId;
      }
    }
    return false;
  }
  
  /// 🚀 新增：获取当前章节信息（普通/沉浸模式通用）
  Map<String, dynamic> get currentChapterInfo {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return {};
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return {};
    
    for (int actIndex = 0; actIndex < currentState.novel.acts.length; actIndex++) {
      final act = currentState.novel.acts[actIndex];
      for (int chapterIndex = 0; chapterIndex < act.chapters.length; chapterIndex++) {
        final chapter = act.chapters[chapterIndex];
        if (chapter.id == currentChapterId) {
          return {
            'actId': act.id,
            'actTitle': act.title,
            'actIndex': actIndex,
            'chapterId': chapter.id,
            'chapterTitle': chapter.title,
            'chapterIndex': chapterIndex,
            'isFirstAct': actIndex == 0,
            'isLastAct': actIndex == currentState.novel.acts.length - 1,
            'isFirstChapter': chapterIndex == 0,
            'isLastChapter': chapterIndex == act.chapters.length - 1,
            'totalActs': currentState.novel.acts.length,
            'totalChaptersInAct': act.chapters.length,
            'totalScenes': chapter.scenes.length,
          };
        }
      }
    }
    return {};
  }
  
  /// 🚀 新增：获取下一章信息（普通/沉浸模式通用）
  Map<String, dynamic>? get nextChapterInfo {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return null;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return null;
    
    bool foundCurrent = false;
    for (int actIndex = 0; actIndex < currentState.novel.acts.length; actIndex++) {
      final act = currentState.novel.acts[actIndex];
      for (int chapterIndex = 0; chapterIndex < act.chapters.length; chapterIndex++) {
        final chapter = act.chapters[chapterIndex];
        if (foundCurrent) {
          return {
            'actId': act.id,
            'actTitle': act.title,
            'actIndex': actIndex,
            'chapterId': chapter.id,
            'chapterTitle': chapter.title,
            'chapterIndex': chapterIndex,
            'isFirstAct': actIndex == 0,
            'isLastAct': actIndex == currentState.novel.acts.length - 1,
            'isFirstChapter': chapterIndex == 0,
            'isLastChapter': chapterIndex == act.chapters.length - 1,
          };
        }
        if (chapter.id == currentChapterId) {
          foundCurrent = true;
        }
      }
    }
    return null;
  }
  
  /// 🚀 新增：获取上一章信息（普通/沉浸模式通用）
  Map<String, dynamic>? get previousChapterInfo {
    final currentState = editorBloc.state;
    if (currentState is! editor_bloc.EditorLoaded) {
      return null;
    }
    
    final String? currentChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (currentChapterId == null) return null;
    
    Map<String, dynamic>? previousInfo;
    for (int actIndex = 0; actIndex < currentState.novel.acts.length; actIndex++) {
      final act = currentState.novel.acts[actIndex];
      for (int chapterIndex = 0; chapterIndex < act.chapters.length; chapterIndex++) {
        final chapter = act.chapters[chapterIndex];
        if (chapter.id == currentChapterId) {
          return previousInfo;
        }
        previousInfo = {
          'actId': act.id,
          'actTitle': act.title,
          'actIndex': actIndex,
          'chapterId': chapter.id,
          'chapterTitle': chapter.title,
          'chapterIndex': chapterIndex,
          'isFirstAct': actIndex == 0,
          'isLastAct': actIndex == currentState.novel.acts.length - 1,
          'isFirstChapter': chapterIndex == 0,
          'isLastChapter': chapterIndex == act.chapters.length - 1,
        };
      }
    }
    return null;
  }
  
  /// 获取布局管理器的辅助方法
  EditorLayoutManager? _getLayoutManager() {
    try {
      // 这里假设布局管理器通过某种方式可以访问
      // 在实际实现中，可能需要通过Provider或其他方式获取
      return null; // 临时返回null，实际使用时需要实现
    } catch (e) {
      AppLogger.w('EditorScreenController', '获取布局管理器失败', e);
      return null;
    }
  }

  // 🚀 新增：处理级联菜单导航
  void _handleCascadeMenuNavigation(String itemId) {
    if (_cascadeMenuData == null) return;

    final item = _cascadeMenuData!.flatItems[itemId];
    if (item == null) return;

    switch (item.type) {
      case ContextSelectionType.acts:
        // 导航到卷
        _navigateToAct(itemId);
        break;
      case ContextSelectionType.chapters:
        // 导航到章节
        _navigateToChapter(itemId);
        break;
      case ContextSelectionType.scenes:
        // 导航到场景
        _navigateToScene(itemId);
        break;
      default:
        AppLogger.d('EditorScreenController', '级联菜单项类型不需要导航: ${item.type}');
    }
  }

  // 🚀 新增：导航到卷
  void _navigateToAct(String itemId) {
    final actId = itemId;
    AppLogger.i('EditorScreenController', '导航到卷: $actId');
    
    // 查找卷中的第一个章节
    final editorState = editorBloc.state;
    if (editorState is editor_bloc.EditorLoaded) {
      for (final act in editorState.novel.acts) {
        if (act.id == actId && act.chapters.isNotEmpty) {
          editorBloc.add(editor_bloc.SetActiveChapter(
            actId: actId,
            chapterId: act.chapters.first.id,
          ));
          return;
        }
      }
    }
    
    AppLogger.w('EditorScreenController', '未找到卷或卷中没有章节: $actId');
  }

  // 🚀 新增：导航到章节
  void _navigateToChapter(String itemId) {
    try {
      // 🚀 处理扁平化章节ID (flat_前缀)
      String actualChapterId = itemId;
      if (itemId.startsWith('flat_')) {
        actualChapterId = itemId.substring(5); // 移除'flat_'前缀
      }
      
      // 查找章节所属的卷
      final editorState = editorBloc.state;
      if (editorState is editor_bloc.EditorLoaded) {
        for (final act in editorState.novel.acts) {
          for (final chapter in act.chapters) {
            if (chapter.id == actualChapterId) {
              AppLogger.i('EditorScreenController', '导航到章节: actId=${act.id}, chapterId=$actualChapterId');
              
              editorBloc.add(editor_bloc.SetActiveChapter(
                actId: act.id,
                chapterId: actualChapterId,
              ));
              
              // 如果章节有场景，设置第一个场景为活动场景
              if (chapter.scenes.isNotEmpty) {
                editorBloc.add(editor_bloc.SetActiveScene(
                  actId: act.id,
                  chapterId: actualChapterId,
                  sceneId: chapter.scenes.first.id,
                ));
              }
              
              // 🚀 新增：点击章节目录默认进入沉浸模式
              AppLogger.i('EditorScreenController', '切换到沉浸模式: $actualChapterId');
              switchToImmersiveMode(chapterId: actualChapterId);
              
              return;
            }
          }
        }
      }
      
      AppLogger.w('EditorScreenController', '未找到章节: $actualChapterId');
    } catch (e) {
      AppLogger.e('EditorScreenController', '导航到章节失败: $itemId', e);
    }
  }

  // 🚀 新增：导航到场景
  void _navigateToScene(String itemId) {
    try {
      // 🚀 处理扁平化场景ID (flat_前缀)
      String actualSceneId = itemId;
      if (itemId.startsWith('flat_')) {
        actualSceneId = itemId.substring(5); // 移除'flat_'前缀
      }
      
      // 查找场景所属的章节和卷
      final editorState = editorBloc.state;
      if (editorState is editor_bloc.EditorLoaded) {
        for (final act in editorState.novel.acts) {
          for (final chapter in act.chapters) {
            for (final scene in chapter.scenes) {
              if (scene.id == actualSceneId) {
                AppLogger.i('EditorScreenController', 
                    '导航到场景: actId=${act.id}, chapterId=${chapter.id}, sceneId=$actualSceneId');
                
                editorBloc.add(editor_bloc.SetActiveScene(
                  actId: act.id,
                  chapterId: chapter.id,
                  sceneId: actualSceneId,
                ));
                
                // 同时设置活动章节
                editorBloc.add(editor_bloc.SetActiveChapter(
                  actId: act.id,
                  chapterId: chapter.id,
                ));
                
                return;
              }
            }
          }
        }
      }
      
      AppLogger.w('EditorScreenController', '未找到场景: $actualSceneId');
    } catch (e) {
      AppLogger.e('EditorScreenController', '导航到场景失败: $itemId', e);
    }
  }

}
