import 'dart:io';
import 'dart:async';
// 🔧 Web平台需要dart:html用于页面刷新
import 'dart:html' as html show window;

// <<< 导入 AiConfigBloc >>>
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
// 导入聊天相关的类
import 'package:ainoval/blocs/auth/auth_bloc.dart';
import 'package:ainoval/blocs/chat/chat_bloc.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';
import 'package:ainoval/blocs/editor_version_bloc.dart';
import 'package:ainoval/blocs/novel_list/novel_list_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_bloc.dart';
import 'package:ainoval/config/app_config.dart'; // 引入 AppConfig
import 'package:ainoval/l10n/l10n.dart';
import 'package:ainoval/models/app_registration_config.dart';

// import 'package:ainoval/screens/novel_list/novel_list_screen.dart'; // 已删除，使用新页面
import 'package:ainoval/screens/novel_list/novel_list_real_data_screen.dart' deferred as novel_list;
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/base/sse_client.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' as flutter_sse;
// <<< 移除未使用的 Codex Impl 引用 >>>
// import 'package:ainoval/services/api_service/repositories/impl/codex_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/chat_repository.dart'; // <<< 导入接口
// ApiService import might not be needed directly in main unless provided
// import 'package:ainoval/services/api_service.dart';
import 'package:ainoval/services/api_service/repositories/impl/chat_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/credit_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_setting_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/public_model_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/storage_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/user_ai_model_config_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/setting_generation_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/universal_ai_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/preset_aggregation_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/ai_preset_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_snippet_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/knowledge_base_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/novel_repository.dart'; // <<< 导入接口
import 'package:ainoval/services/api_service/repositories/knowledge_base_repository.dart';
import 'package:ainoval/services/image_cache_service.dart';
// import 'package:ainoval/services/api_service/repositories/novel_setting_repository.dart';
import 'package:ainoval/services/api_service/repositories/credit_repository.dart';
import 'package:ainoval/services/api_service/repositories/public_model_repository.dart';
import 'package:ainoval/services/api_service/repositories/storage_repository.dart';
// <<< 导入 AI Config 仓库 >>>
import 'package:ainoval/services/api_service/repositories/user_ai_model_config_repository.dart';
import 'package:ainoval/services/api_service/repositories/setting_generation_repository.dart';
import 'package:ainoval/services/api_service/repositories/universal_ai_repository.dart';
import 'package:ainoval/services/api_service/repositories/preset_aggregation_repository.dart';
import 'package:ainoval/services/api_service/repositories/ai_preset_repository.dart';
import 'package:ainoval/services/api_service/repositories/novel_snippet_repository.dart';
import 'package:ainoval/services/auth_service.dart' as auth_service;
import 'package:ainoval/services/local_storage_service.dart';
import 'package:ainoval/services/novel_file_service.dart';
import 'package:ainoval/services/web_file_service.dart'; // 导入小说文件服务
// import 'package:ainoval/services/websocket_service.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ainoval/services/api_service/repositories/prompt_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/prompt_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/impl/task_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/task_repository.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:ainoval/services/task_event_cache.dart';
import 'package:ainoval/services/tab_coordination_service.dart';
// 重复导入清理（下方已存在这些导入）
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/utils/navigation_logger.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/blocs/theme/theme_bloc.dart';
import 'package:ainoval/blocs/theme/theme_event.dart';
import 'package:ainoval/blocs/theme/theme_state.dart';
// 导入预设管理BLoC
import 'package:ainoval/blocs/preset/preset_bloc.dart';
import 'package:ainoval/blocs/preset/preset_event.dart';
// 导入知识库BLoC
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
// 导入预设聚合仓储
import 'package:ainoval/screens/unified_management/unified_management_screen.dart' deferred as unified_mgmt;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 预加载中文与英文字体，避免 Web 首次渲染出现“方块/乱码”
    await _preloadFonts();

    // Web 平台下：覆盖 Flutter 全局错误处理，避免 Inspector 在处理 JS 对象时报错
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kIsWeb) {
        // 直接输出字符串化的异常信息，避免 DiagnosticsNode 转换
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        if (details.stack != null) {
          debugPrint(details.stack.toString());
        }
      } else {
        FlutterError.presentError(details);
      }
    };

    // 初始化日志系统
    AppLogger.init();

    // 初始化Hive本地存储
    await Hive.initFlutter();

    // 初始化注册配置
    await _initializeRegistrationConfig();

    // 创建必要的资源文件夹 - 仅在非Web平台执行
    if (!kIsWeb) {
      await _createResourceDirectories();
    }

    // 初始化LocalStorageService
    final localStorageService = LocalStorageService();
    await localStorageService.init();
    
    // 初始化跨标签页协调服务（仅Web平台）
    if (kIsWeb) {
      try {
        await TabCoordinationService().initialize();
        AppLogger.i('Main', '✅ 跨标签页协调服务已初始化');
      } catch (e) {
        AppLogger.w('Main', '⚠️ 跨标签页协调服务初始化失败，将降级为独立模式: $e');
      }
    }

    // 创建AuthService
    final authServiceInstance = auth_service.AuthService();
    // 注册为 ApiClient 的默认 AuthService，保证各处 new ApiClient() 都能感知 401 并登出
    ApiClient.registerDefaultAuthService(authServiceInstance);
    await authServiceInstance.init();

    // 创建 ApiClient 实例并传入 AuthService
    final apiClient = ApiClient(authService: authServiceInstance);
    
    // 创建 SseClient 实例 (单例模式) 并设置 AuthService
    final sseClient = SseClient();
    sseClient.setAuthService(authServiceInstance);
/* 
    // 创建ApiService (如果 ApiService 需要 ApiClient, 则传入)
    // 假设 ApiService 构造函数接受 apiClient (如果不需要则忽略)
    final apiService = ApiService(/* apiClient: apiClient */); 
    
    // 创建WebSocketService
    final webSocketService = WebSocketService(); */

    // 创建NovelRepository (它不再需要MockDataService)
    final novelRepository = NovelRepositoryImpl(/* apiClient: apiClient */);

    // 创建ChatRepository，并传入 ApiClient
    final chatRepository = ChatRepositoryImpl(
      apiClient: apiClient, // 使用直接创建的 apiClient
    );

    // 创建StorageRepository实例
    final storageRepository = StorageRepositoryImpl(apiClient);

    // 创建UserAIModelConfigRepository
    final userAIModelConfigRepository =
        UserAIModelConfigRepositoryImpl(apiClient: apiClient);

    // 创建PublicModelRepository
    final publicModelRepository = PublicModelRepositoryImpl(apiClient: apiClient);

    // 创建CreditRepository
    final creditRepository = CreditRepositoryImpl(apiClient: apiClient);

    // 创建NovelSettingRepository
    final novelSettingRepository = NovelSettingRepositoryImpl(apiClient: apiClient);



    // 创建PromptRepository
    final promptRepository = PromptRepositoryImpl(apiClient);

    // 创建NovelFileService
    final novelFileService = NovelFileService(
      novelRepository: novelRepository,
      // editorRepository 暂时为空，可以后续添加
    );

    // 创建WebFileService (仅在Web平台)
    WebFileService? webFileService;
    if (kIsWeb) {
      webFileService = WebFileService(
        novelRepository: novelRepository,
        // editorRepository 暂时为空，可以后续添加
      );
    }

    // 创建NovelSnippetRepository
    final novelSnippetRepository = NovelSnippetRepositoryImpl(apiClient);

    // 创建UniversalAIRepository
    final universalAIRepository = UniversalAIRepositoryImpl(apiClient: apiClient);

    // 创建PresetAggregationRepository
    final presetAggregationRepository = PresetAggregationRepositoryImpl(apiClient);

    // 创建AIPresetRepository
    final aiPresetRepository = AIPresetRepositoryImpl(apiClient: apiClient);

    // 创建KnowledgeBaseRepository
    final knowledgeBaseRepository = KnowledgeBaseRepositoryImpl(apiClient);

    // 创建SettingGenerationRepository
    final settingGenerationRepository = SettingGenerationRepositoryImpl(
      apiClient: apiClient,
      sseClient: sseClient,
    );

    // 初始化图片缓存服务（如需预热可在此调用）
    // ImageCacheService().prewarm();

    AppLogger.i('Main', '应用程序初始化完成，准备启动界面');

    runApp(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<auth_service.AuthService>.value(
            value: authServiceInstance),
        RepositoryProvider<ApiClient>.value(value: apiClient),
        RepositoryProvider<NovelRepository>.value(value: novelRepository),
        RepositoryProvider<ChatRepository>.value(value: chatRepository),
        RepositoryProvider<StorageRepository>.value(value: storageRepository),
        RepositoryProvider<UserAIModelConfigRepository>.value(
            value: userAIModelConfigRepository),
        RepositoryProvider<PublicModelRepository>.value(
            value: publicModelRepository),
        RepositoryProvider<CreditRepository>.value(
            value: creditRepository),
        RepositoryProvider<LocalStorageService>.value(
            value: localStorageService),
        RepositoryProvider<PromptRepository>(
          create: (context) => promptRepository,
        ),
        RepositoryProvider<NovelFileService>.value(
          value: novelFileService,
        ),
        if (kIsWeb && webFileService != null)
          RepositoryProvider<WebFileService>.value(
            value: webFileService,
          ),
        RepositoryProvider<NovelSnippetRepository>.value(
          value: novelSnippetRepository,
        ),
        RepositoryProvider<UniversalAIRepository>.value(
          value: universalAIRepository,
        ),
        RepositoryProvider<PresetAggregationRepository>.value(
          value: presetAggregationRepository,
        ),
        RepositoryProvider<AIPresetRepository>.value(
          value: aiPresetRepository,
        ),
        RepositoryProvider<SettingGenerationRepository>.value(
          value: settingGenerationRepository,
        ),
        RepositoryProvider<KnowledgeBaseRepository>.value(
          value: knowledgeBaseRepository,
        ),
        // 提供 TaskRepository 以供全局任务订阅
        RepositoryProvider<TaskRepository>(
          create: (_) => TaskRepositoryImpl(apiClient: apiClient),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authService: context.read<auth_service.AuthService>(),
            )..add(AuthInitialize()),
          ),
          BlocProvider<NovelListBloc>(
            create: (context) => NovelListBloc(
              repository: context.read<NovelRepository>(),
            ),
          ),
          BlocProvider<AiConfigBloc>(
            create: (context) => AiConfigBloc(
              repository: context.read<UserAIModelConfigRepository>(),
            ),
          ),
          BlocProvider<PublicModelsBloc>(
            create: (context) => PublicModelsBloc(
              repository: context.read<PublicModelRepository>(),
            ),
          ),
          BlocProvider<CreditBloc>(
            create: (context) => CreditBloc(
              repository: context.read<CreditRepository>(),
            ),
          ),
          BlocProvider<SettingGenerationBloc>(
            create: (context) => SettingGenerationBloc(
              repository: context.read<SettingGenerationRepository>(),
            ),
          ),
          /*
          BlocProvider<ReaderBloc>(
            create: (context) => ReaderBloc(
              repository: context.read<NovelRepository>(),
            ),
          ),
          */
          BlocProvider<ChatBloc>(
            create: (context) => ChatBloc(
              repository: context.read<ChatRepository>(),
              authService: context.read<auth_service.AuthService>(),
              aiConfigBloc: context.read<AiConfigBloc>(),
              publicModelsBloc: context.read<PublicModelsBloc>(),
              settingRepository: novelSettingRepository,
              snippetRepository: novelSnippetRepository,
            ),
          ),
          BlocProvider<EditorVersionBloc>(
            create: (context) => EditorVersionBloc(
              novelRepository: context.read<NovelRepository>(),
            ),
          ),
          BlocProvider<UniversalAIBloc>(
            create: (context) => UniversalAIBloc(
              repository: context.read<UniversalAIRepository>(),
            ),
          ),
          BlocProvider<PromptNewBloc>(
            create: (context) => PromptNewBloc(
              promptRepository: context.read<PromptRepository>(),
            ),
          ),
          BlocProvider<ThemeBloc>(
            create: (context) => ThemeBloc()..add(ThemeInitialize()),
          ),
          BlocProvider<PresetBloc>(
            create: (context) => PresetBloc(
              aggregationRepository: context.read<PresetAggregationRepository>(),
              presetRepository: context.read<AIPresetRepository>(),
            ),
          ),
          BlocProvider<KnowledgeBaseBloc>(
            create: (context) => KnowledgeBaseBloc(
              context.read<KnowledgeBaseRepository>(),
            ),
          ),
        ],
        child: const MyApp(),
      ),
    ));
  }, (error, stack) {
    // 兜底：捕获所有未处理异常并记录，避免在 Web 上出现 LegacyJavaScriptObject -> DiagnosticsNode 的崩溃
    AppLogger.e('Uncaught', '未捕获异常: $error', error, stack);
  });
}

// 预加载项目使用的关键字体，降低 Web 首渲出现中文方块/乱码的概率
Future<void> _preloadFonts() async {
  try {
    // 预加载 Noto Sans SC 字体（修复名称匹配）
    final noto = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    final notoBold = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
    final notoMedium = await rootBundle.load('assets/fonts/NotoSansSC-Medium.ttf');
    
    final notoLoader = FontLoader('Noto Sans SC') // 修复：使用正确的字体名称
      ..addFont(Future.value(ByteData.view(noto.buffer)))
      ..addFont(Future.value(ByteData.view(notoBold.buffer)))
      ..addFont(Future.value(ByteData.view(notoMedium.buffer)));
    await notoLoader.load();

    // 预加载 Roboto 字体
    final roboto = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final robotoBold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final robotoMedium = await rootBundle.load('assets/fonts/Roboto-Medium.ttf');
    
    final robotoLoader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.view(roboto.buffer)))
      ..addFont(Future.value(ByteData.view(robotoBold.buffer)))
      ..addFont(Future.value(ByteData.view(robotoMedium.buffer)));
    await robotoLoader.load();
    
    debugPrint('字体预加载完成: Noto Sans SC, Roboto');
  } catch (e) {
    debugPrint('字体预加载失败: $e');
  }
}

// 初始化注册配置
Future<void> _initializeRegistrationConfig() async {
  try {
    // 确保注册配置已初始化，设置默认值
    // 默认开启邮箱注册和手机注册，需要验证码验证
    final phoneEnabled = await AppRegistrationConfig.isPhoneRegistrationEnabled();
    final emailEnabled = await AppRegistrationConfig.isEmailRegistrationEnabled();
    final verificationRequired = await AppRegistrationConfig.isVerificationRequired();
    
    AppLogger.i('Registration', 
        '📝 注册配置已加载 - 邮箱注册: $emailEnabled, 手机注册: $phoneEnabled, 验证码验证: $verificationRequired');
    
    // 如果没有任何注册方式可用，启用默认的邮箱注册
    if (!phoneEnabled && !emailEnabled) {
      await AppRegistrationConfig.setEmailRegistrationEnabled(true);
      AppLogger.i('Registration', '🔧 已自动启用邮箱注册功能');
    }
  } catch (e) {
    AppLogger.e('Registration', '初始化注册配置失败', e);
  }
}

// 创建资源文件夹
Future<void> _createResourceDirectories() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final assetsDir = Directory('${appDir.path}/assets');
    final imagesDir = Directory('${assetsDir.path}/images');
    final iconsDir = Directory('${assetsDir.path}/icons');

    // 创建资源目录
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    // 创建图像目录
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 创建图标目录
    if (!await iconsDir.exists()) {
      await iconsDir.create(recursive: true);
    }

    AppLogger.i('ResourceDir', '资源文件夹创建成功');
  } catch (e) {
    AppLogger.e('ResourceDir', '创建资源文件夹失败', e);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _postLoginBootstrapped = false;
  // 新增：主题加载去重标记，避免每次重建都请求并覆盖本地预览
  bool _themeBootstrapped = false;
  String? _themeBootstrappedUserId;
  StreamSubscription<Map<String, dynamic>>? _taskEventSub;
  StreamSubscription<AppEvent>? _taskControlSub;
  // 任务事件监听"单飞"与节流控制，避免并发多连
  bool _isStartingTaskListener = false;
  String? _taskListenerUserId;
  DateTime? _lastTaskListenerStartAt;
  // 🔧 增加节流时间到5秒，防止连接风暴（特别是后端重启场景）
  static const Duration _taskListenerRestartDebounce = Duration(seconds: 5);
  
  // 🔧 重试控制：指数退避和最大重试次数
  int _sseConnectionRetryCount = 0; // 当前重试次数
  DateTime? _sseConnectionFirstFailureTime; // 首次失败时间
  static const int _maxSseRetries = 10; // 最大重试次数
  static const Duration _retryCountResetWindow = Duration(minutes: 5); // 5分钟内的失败计数窗口
  static const Duration _maxRetryWindow = Duration(minutes: 2); // 2分钟内重试超限则放弃
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ImageCacheService().clearCache();
    // 清理任务监听
    _taskEventSub?.cancel();
    _taskControlSub?.cancel();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // 🔧 Hot Reload时清理残留的SSE订阅状态
    // 这样Hot Reload后能正常重新建立连接
    if (_taskEventSub != null) {
      AppLogger.w('MyApp', '🔄 Hot Reload检测：清理残留的SSE订阅引用');
      try {
        _taskEventSub?.cancel();
      } catch (e) {
        AppLogger.w('MyApp', 'Hot Reload清理订阅失败: $e');
      }
      _taskEventSub = null;
      _isStartingTaskListener = false;
      
      // 🔧 重置重试计数器（Hot Reload后重新开始）
      _sseConnectionRetryCount = 0;
      _sseConnectionFirstFailureTime = null;
      
      // 如果当前是已认证状态，等待一小段时间后自动重连
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        AppLogger.i('MyApp', '🔄 Hot Reload后自动重新建立SSE连接');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _startGlobalTaskEventListener(authState.userId);
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 应用进入后台或被关闭时清理图片缓存
        ImageCacheService().clearCache();
        break;
      case AppLifecycleState.resumed:
        // 应用恢复时可以预加载一些图片
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return ValueListenableBuilder<String>(
          valueListenable: WebTheme.variantListenable,
          builder: (context, variant, _) {
            // 根据当前变体重建主题
            return MaterialApp(
          navigatorObservers: [NavigationLogger()],
          title: 'AINoval',
              theme: WebTheme.buildLightTheme(),
              darkTheme: WebTheme.buildDarkTheme(),
          themeMode: themeState.themeMode,
          initialRoute: '/',
          routes: {
        '/': (context) => BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (prev, curr) =>
              curr is AuthAuthenticated || curr is AuthUnauthenticated,
          listener: (context, state) async {
            AppLogger.i('MyApp', '🔔 AuthBloc状态变化: ${state.runtimeType}');
            
            if (state is AuthAuthenticated) {
              // 先恢复SSE允许
              try { SseClient().resumeAll(); } catch (_) {}
              if (_postLoginBootstrapped) {
                AppLogger.i('MyApp', '🔁 已完成登录后的初始化，跳过重复触发');
              }
              final userId = AppConfig.userId;
              if (userId != null) {
                AppLogger.i('MyApp',
                    'User authenticated, loading AiConfigs, PublicModels, Credits, Novels, Presets and PromptPackages for user $userId');
                // 并行加载用户AI配置、公共模型和用户积分
                if (!_postLoginBootstrapped) {
                  context.read<AiConfigBloc>().add(LoadAiConfigs(userId: userId));
                  context.read<PublicModelsBloc>().add(const LoadPublicModels());
                  // 每次登录都强制重新加载积分，避免复用上个账号缓存
                  context.read<CreditBloc>().add(const LoadUserCredits());
                  // 用户登录成功后，加载一次小说列表数据（仅在未加载时）
                  final novelState = context.read<NovelListBloc>().state;
                  if (novelState is! NovelListLoaded) {
                    context.read<NovelListBloc>().add(LoadNovels());
                  }
                  // 预设与提示词包
                  context.read<PresetBloc>().add(const LoadAllPresetData());
                  context.read<PromptNewBloc>().add(const LoadAllPromptPackages());
                  _postLoginBootstrapped = true;
                  // 登录时先不强制开启监听，改为按需：监听事件总线的开始/停止指令
                  _ensureTaskControlBusHook(userId);
                  // 确保全局任务事件监听已启动（幂等触发）——仅在已认证且存在token时
                  if (AppConfig.authToken != null && AppConfig.authToken!.isNotEmpty) {
                    try { EventBus.instance.fire(const StartTaskEventsListening()); } catch (_) {}
                  } else {
                    AppLogger.w('MyApp', '跳过启动任务事件监听：未检测到有效token');
                  }
                }
              } else {
                AppLogger.e('MyApp',
                    'User authenticated but userId is null in AppConfig!');
              }
            } else if (state is AuthUnauthenticated) {
              AppLogger.i('MyApp', '✅ 用户已退出登录，清理所有BLoC状态');
              // 全局挂起SSE，阻断任何新建连接
              try { SseClient().suspendAll(); } catch (_) {}
              _postLoginBootstrapped = false;
              // 重置主题加载去重，允许下次登录重新拉取一次主题
              _themeBootstrapped = false;
              _themeBootstrappedUserId = null;
              // 退出时取消任务监听
              try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
              await Future.delayed(const Duration(milliseconds: 180));
              try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
              _taskEventSub?.cancel();
              _taskEventSub = null;
              _taskControlSub?.cancel();
              _taskControlSub = null;
              // 重置监听状态
              _isStartingTaskListener = false;
              _taskListenerUserId = null;
              _lastTaskListenerStartAt = null;
              
              // 🔧 重置重试计数器
              _sseConnectionRetryCount = 0;
              _sseConnectionFirstFailureTime = null;
              
              // 清理所有BLoC状态，停止进行中的请求
              try {
                // 重置 AI 配置，避免跨用户复用本地缓存/内存状态
                context.read<AiConfigBloc>().add(const ResetAiConfigs());
              } catch (e) {
                AppLogger.w('MyApp', '重置AiConfigBloc状态失败', e);
              }
              try {
                // 清理小说列表状态
                context.read<NovelListBloc>().add(ClearNovels());
                AppLogger.i('MyApp', '✅ NovelListBloc状态已清理');
              } catch (e) {
                AppLogger.w('MyApp', '清理NovelListBloc状态失败', e);
              }
              
              // 清空积分显示为游客（0）
              try {
                context.read<CreditBloc>().add(const ClearCredits());
                AppLogger.i('MyApp', '✅ CreditBloc状态已清空');
              } catch (e) {
                AppLogger.w('MyApp', '清空CreditBloc状态失败', e);
              }
              
              // 清除用户显示名称为游客
              AppConfig.setUsername(null);
              AppConfig.setUserId(null);
              AppConfig.setAuthToken(null);
              // 可以根据需要添加其他BLoC的清理逻辑
              // 但暂时先清理最关键的小说列表，避免404请求
            } else if (state is AuthLoading) {
              AppLogger.i('MyApp', '⏳ 认证状态加载中...');
            } else if (state is AuthError) {
              AppLogger.w('MyApp', '❌ 认证错误: ${state.message}');
            }
          },
          buildWhen: (prev, curr) =>
              curr is AuthAuthenticated || curr is AuthUnauthenticated,
          builder: (context, state) {
            AppLogger.i('MyApp', '🏗️ 构建UI，当前状态: ${state.runtimeType}');
            
            if (state is AuthAuthenticated) {
              AppLogger.i(
                  'MyApp', '📚 显示小说列表界面');
              // 🚀 登录成功后异步加载并应用用户的主题变体，确保全局组件使用保存的主题色
              final userId = AppConfig.userId;
              if (userId != null && (!_themeBootstrapped || _themeBootstrappedUserId != userId)) {
                () async {
                  try {
                    // 捕获启动请求时的当前本地主题，用于避免覆盖用户正在预览的主题
                    final String startVariant = WebTheme.currentVariant;
                    final settings = await NovelRepositoryImpl.getInstance().getUserEditorSettings(userId);
                    // 仅当用户期间没有本地切换过主题时，才应用服务端主题，避免覆盖未保存的预览
                    if (WebTheme.currentVariant == startVariant) {
                      WebTheme.applyVariant(settings.themeVariant);
                      AppLogger.i('MyApp', '🎨 已应用用户主题变体: ${settings.themeVariant}');
                    } else {
                      AppLogger.i('MyApp', '⏭️ 用户在加载期间已变更主题，跳过覆盖服务端主题');
                    }
                    // 标记本次用户已完成主题引导加载，避免重复覆盖本地预览
                    if (mounted) {
                      setState(() {
                        _themeBootstrapped = true;
                        _themeBootstrappedUserId = userId;
                      });
                    } else {
                      _themeBootstrapped = true;
                      _themeBootstrappedUserId = userId;
                    }
                  } catch (e) {
                    AppLogger.w('MyApp', '无法应用用户主题变体: $e');
                  }
                }();
              }
              // 异步加载小说列表页面，实现代码分割
              return FutureBuilder(
                future: novel_list.loadLibrary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return novel_list.NovelListRealDataScreen();
                  }
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              );
            }
            // 未登录：默认展示小说列表的“游客模式”界面，受控于页面内的鉴权弹窗
            return FutureBuilder(
              future: novel_list.loadLibrary(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return novel_list.NovelListRealDataScreen();
                }
                return const Center(
                  child: CircularProgressIndicator(),
                );
              },
            );
          },
        ),
            '/unified-management': (context) => FutureBuilder(
              future: unified_mgmt.loadLibrary(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return unified_mgmt.UnifiedManagementScreen();
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),


          },
          debugShowCheckedModeBanner: false,

          // 添加完整的本地化支持
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.all,
          locale: const Locale('zh', 'CN'), // 设置默认语言为中文
        );
          },
        );
      },
    );
  }
}

extension _TaskEventBootstrap on _MyAppState {
  void _startGlobalTaskEventListener(String userId) {
    try {
      // 未认证（无token）直接跳过，避免误启动
      if (AppConfig.authToken == null || AppConfig.authToken!.isEmpty) {
        AppLogger.w('MyApp', '拒绝启动全局任务事件监听：未检测到有效token');
        return;
      }
      // 若已存在对同一用户的有效监听，跳过重复启动
      if (_taskEventSub != null && _taskListenerUserId == userId) {
        AppLogger.i('MyApp', '全局任务事件监听已在运行(userId=$userId)，跳过重复启动');
        return;
      }

      // 单飞：正在启动中则跳过并发触发
      if (_isStartingTaskListener) {
        AppLogger.i('MyApp', '全局任务事件监听正在启动中，跳过并发触发');
        return;
      }

      // 🔧 检查重试次数窗口，超过窗口则重置计数
      final now = DateTime.now();
      if (_sseConnectionFirstFailureTime != null) {
        if (now.difference(_sseConnectionFirstFailureTime!) > _MyAppState._retryCountResetWindow) {
          AppLogger.i('MyApp', '重试计数窗口已过，重置重试计数器（之前累计失败${_sseConnectionRetryCount}次）');
          _sseConnectionRetryCount = 0;
          _sseConnectionFirstFailureTime = null;
        }
      }
      
      // 🔧 检查是否超过最大重试次数
      if (_sseConnectionRetryCount >= _MyAppState._maxSseRetries) {
        if (_sseConnectionFirstFailureTime != null &&
            now.difference(_sseConnectionFirstFailureTime!) <= _MyAppState._maxRetryWindow) {
          AppLogger.e('MyApp', 
              '⛔ SSE连接失败次数过多（${_sseConnectionRetryCount}次），在${_MyAppState._maxRetryWindow.inSeconds}秒内超过最大重试限制，自动登出以防止连接风暴');
          
          // 🔧 触发自动登出
          try {
            final authService = context.read<auth_service.AuthService>();
            authService.logout();
            // 清理状态
            _sseConnectionRetryCount = 0;
            _sseConnectionFirstFailureTime = null;
            _isStartingTaskListener = false;
          } catch (e) {
            AppLogger.e('MyApp', '自动登出失败', e);
          }
          return;
        } else {
          // 超过2分钟，重置计数器允许重试
          AppLogger.w('MyApp', '超过最大重试窗口，重置计数器');
          _sseConnectionRetryCount = 0;
          _sseConnectionFirstFailureTime = null;
        }
      }
      
      // 🔧 指数退避：根据重试次数计算延迟时间
      final Duration baseDebounce = _MyAppState._taskListenerRestartDebounce;
      final Duration exponentialDelay = Duration(
        seconds: baseDebounce.inSeconds * (1 << _sseConnectionRetryCount.clamp(0, 4)) // 最多延迟5*2^4=80秒
      );
      
      // 节流：短时间内多次触发则忽略（使用指数退避时间）
      final lastStartAt = _lastTaskListenerStartAt;
      if (lastStartAt != null && now.difference(lastStartAt) < exponentialDelay) {
        final remainingSeconds = exponentialDelay.inSeconds - now.difference(lastStartAt).inSeconds;
        AppLogger.i('MyApp', 
            '全局任务事件监听启动过于频繁，已节流（重试${_sseConnectionRetryCount}次，需间隔${exponentialDelay.inSeconds}秒，还需等待${remainingSeconds}秒）');
        return;
      }

      _isStartingTaskListener = true;
      _lastTaskListenerStartAt = now;
      _taskListenerUserId = userId;

      final taskRepo = context.read<TaskRepository>();
      
      // 🔧 跨标签页协调：检查是否为主标签页
      if (kIsWeb && TabCoordinationService().initialized) {
        final tabCoord = TabCoordinationService();
        
        // 设置领导权变更回调
        tabCoord.onLeadershipChanged = (isLeader) {
          AppLogger.i('MyApp', '标签页角色变更: ${isLeader ? "主标签页" : "从属标签页"}');
          
          if (isLeader) {
            // 成为主标签页，启动SSE连接
            AppLogger.i('MyApp', '成为主标签页，启动SSE连接');
            _loadHistoryTasksAndStartSSE(userId, taskRepo).whenComplete(() {
              _isStartingTaskListener = false;
            });
          } else {
            // 成为从属标签页，取消SSE连接，监听转发事件
            AppLogger.i('MyApp', '成为从属标签页，取消SSE连接');
            _taskEventSub?.cancel();
            _taskEventSub = null;
            _isStartingTaskListener = false;
            
            // 监听主标签页转发的SSE事件
            _listenToForwardedEvents();
          }
        };
        
        // 根据当前角色决定行为
        if (tabCoord.isLeader) {
          AppLogger.i('MyApp', '当前为主标签页，启动SSE连接');
          _loadHistoryTasksAndStartSSE(userId, taskRepo).whenComplete(() {
            _isStartingTaskListener = false;
          });
        } else {
          AppLogger.i('MyApp', '当前为从属标签页，监听转发事件');
          _isStartingTaskListener = false;
          _listenToForwardedEvents();
        }
      } else {
        // 非Web平台或跨标签页协调未启用，使用原有逻辑
        _loadHistoryTasksAndStartSSE(userId, taskRepo).whenComplete(() {
          _isStartingTaskListener = false;
        });
      }
    } catch (e) {
      AppLogger.e('MyApp', '启动全局任务事件监听失败', e);
      _isStartingTaskListener = false;
    }
  }
  
  /// 监听主标签页转发的SSE事件（从属标签页使用）
  void _listenToForwardedEvents() {
    if (!kIsWeb || !TabCoordinationService().initialized) return;
    
    _taskEventSub?.cancel();
    _taskEventSub = TabCoordinationService().sseEventStream.listen((ev) {
      // 处理转发的SSE事件（与直接接收的SSE事件处理逻辑相同）
      final t = (ev['type'] ?? '').toString();
      
      if (t == 'HEARTBEAT') {
        try { TaskEventCache.instance.onEvent(ev); } catch (_) {}
        EventBus.instance.fire(TaskEventReceived(event: ev));
        return;
      }
      
      if (t == 'TASK_COMPLETED') {
        final taskType = (ev['taskType'] ?? '').toString();
        if (taskType == 'CONTINUE_WRITING_CONTENT') {
          AppLogger.i('MyApp', '(转发)自动续写任务完成，全局刷新用户积分');
          try {
            context.read<CreditBloc>().add(const RefreshUserCredits());
          } catch (e) {
            AppLogger.w('MyApp', '全局刷新积分失败', e);
          }
        }
      }
      
      try { TaskEventCache.instance.onEvent(ev); } catch (_) {}
      try {
        final id = (ev['taskId'] ?? '').toString();
        final pid = (ev['parentTaskId'] ?? '').toString();
        final hasResult = ev.containsKey('result');
        AppLogger.i('MyApp', '(转发)SSE事件: type=$t id=$id parent=$pid hasResult=$hasResult');
      } catch (_) {}
      EventBus.instance.fire(TaskEventReceived(event: ev));
    });
    
    AppLogger.i('MyApp', '✅ 已启动转发事件监听（从属标签页）');
  }
  
  /// 加载历史任务数据并启动SSE监听
  Future<void> _loadHistoryTasksAndStartSSE(String userId, TaskRepository taskRepo) async {
    try {
      AppLogger.i('MyApp', '开始加载用户历史任务数据...');
      
      // 使用 TaskRepository 获取历史任务（架构更清晰）
      final historyTasks = await taskRepo.getUserHistoryTasks(size: 50);
      
      if (historyTasks.isNotEmpty) {
        AppLogger.i('MyApp', '加载到 ${historyTasks.length} 条历史任务，正在初始化缓存...');
        TaskEventCache.instance.initializeHistoryTasks(historyTasks);
        AppLogger.i('MyApp', '历史任务缓存初始化完成');
      } else {
        AppLogger.i('MyApp', '未发现历史任务数据');
      }
    } catch (e) {
      AppLogger.w('MyApp', '加载历史任务数据失败，将仅依赖SSE获取新任务: $e');
    }
    
    // 二次校验：历史任务加载期间可能已被401清空token，避免误启动SSE
    if (AppConfig.authToken != null && AppConfig.authToken!.isNotEmpty) {
      _startSSEListener(userId, taskRepo);
    } else {
      AppLogger.w('MyApp', '跳过启动SSE监听：未检测到有效token（可能已登出/401）');
    }
  }
  
  /// 启动SSE监听器
  void _startSSEListener(String userId, TaskRepository taskRepo) {
    // 二次幂等防护：创建前再检查一次
    if (_taskEventSub != null) {
      AppLogger.i('MyApp', '检测到已有任务事件订阅，跳过重复创建');
      return;
    }
    _taskEventSub = taskRepo.streamUserTaskEvents(userId: userId).listen((ev) {
      // 🔧 连接成功，重置重试计数器
      if (_sseConnectionRetryCount > 0) {
        AppLogger.i('MyApp', '✅ SSE连接恢复正常，重置重试计数器（之前累计失败${_sseConnectionRetryCount}次）');
        _sseConnectionRetryCount = 0;
        _sseConnectionFirstFailureTime = null;
      }
      
      // 心跳也要向下游分发，用于面板刷新 _lastEventTs，避免误触发降级轮询
      final t = (ev['type'] ?? '').toString();
      
      // 🔧 处理版本更新通知（强制刷新）
      if (t == 'CLIENT_UPDATE_REQUIRED') {
        _handleClientUpdateRequired(ev);
        return;
      }
      
      if (t == 'HEARTBEAT') {
        try { TaskEventCache.instance.onEvent(ev); } catch (_) {}
        EventBus.instance.fire(TaskEventReceived(event: ev));
        return;
      }
      
      // 🚀 自动续写任务完成时刷新积分（全局处理，确保即使面板未打开也能刷新）
      if (t == 'TASK_COMPLETED') {
        final taskType = (ev['taskType'] ?? '').toString();
        if (taskType == 'CONTINUE_WRITING_CONTENT') {
          AppLogger.i('MyApp', '自动续写任务完成，全局刷新用户积分');
          try {
            context.read<CreditBloc>().add(const RefreshUserCredits());
          } catch (e) {
            AppLogger.w('MyApp', '全局刷新积分失败', e);
          }
        }
      }
      
      // 🔧 跨标签页协调：主标签页转发SSE事件到其他标签页
      if (kIsWeb && TabCoordinationService().initialized && TabCoordinationService().isLeader) {
        try {
          TabCoordinationService().forwardSseEvent(ev);
        } catch (e) {
          AppLogger.w('MyApp', '转发SSE事件到其他标签页失败: $e');
        }
      }
      
      // 广播到全局事件总线，供任意界面消费（如 AITaskCenterPanel）
      try { TaskEventCache.instance.onEvent(ev); } catch (_) {}
      try {
        final id = (ev['taskId'] ?? '').toString();
        final pid = (ev['parentTaskId'] ?? '').toString();
        final hasResult = ev.containsKey('result');
        AppLogger.i('MyApp', 'SSE事件: type=$t id=$id parent=$pid hasResult=$hasResult');
      } catch (_) {}
      EventBus.instance.fire(TaskEventReceived(event: ev));
    }, onError: (e, st) {
      AppLogger.w('MyApp', '任务事件流错误: $e');
      // 清空引用，但不立即重连，等待下次正常触发（避免错误后立即重连形成风暴）
      _taskEventSub = null;
      _isStartingTaskListener = false;
      
      // 🔧 增加失败计数
      _sseConnectionRetryCount++;
      if (_sseConnectionFirstFailureTime == null) {
        _sseConnectionFirstFailureTime = DateTime.now();
      }
      
      // 🔧 检测到连接被拒绝（达到并发限制）时，额外延迟
      final errorString = e.toString();
      if (errorString.contains('已达到最大并发连接数限制') || 
          errorString.contains('连接过于频繁')) {
        AppLogger.w('MyApp', '⚠️ 检测到连接被服务器拒绝，延迟10秒后才允许重连（累计失败${_sseConnectionRetryCount}次）');
        _lastTaskListenerStartAt = DateTime.now().add(const Duration(seconds: 5)); // 额外延迟5秒（总共10秒）
      } else {
        AppLogger.w('MyApp', '⚠️ SSE连接失败（累计失败${_sseConnectionRetryCount}次）');
      }
      
      // 🔧 检查是否达到最大重试次数
      if (_sseConnectionRetryCount >= _MyAppState._maxSseRetries) {
        AppLogger.e('MyApp', '⛔ SSE连接失败次数过多（${_sseConnectionRetryCount}次），已达到最大重试限制');
        // 不在这里登出，由下次启动时检查并登出
      }
    }, onDone: () {
      AppLogger.i('MyApp', '任务事件流已结束');
      // 清空引用，允许下次正常触发时重连
      _taskEventSub = null;
      _isStartingTaskListener = false;
    });
    AppLogger.i('MyApp', '全局任务事件监听已启动 (userId=$userId)');
  }

  void _stopGlobalTaskEventListener() {
    try {
      _taskEventSub?.cancel();
      _taskEventSub = null;
      AppLogger.i('MyApp', '全局任务事件监听已停止');
      _isStartingTaskListener = false;
    } catch (e) {
      AppLogger.w('MyApp', '停止全局任务事件监听失败', e);
    }
  }
  
  /// 🔧 处理客户端版本更新通知（优雅刷新）
  void _handleClientUpdateRequired(Map<String, dynamic> event) {
    AppLogger.w('MyApp', '⚠️ 收到客户端版本更新通知，准备优雅刷新页面');
    
    final message = event['message']?.toString() ?? '检测到新版本，需要刷新页面';
    final minVersion = event['minVersion']?.toString() ?? '未知';
    final currentVersion = AppConfig.clientVersion;
    
    AppLogger.i('MyApp', '版本信息 - 当前: $currentVersion, 最低要求: $minVersion');
    
    // 显示提示对话框
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.orange),
            SizedBox(width: 8),
            Text('版本更新'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Text('当前版本: $currentVersion', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('最低要求: $minVersion', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text(
              '点击"立即刷新"后，系统将：\n1. 断开当前连接\n2. 清理本地状态\n3. 登出当前账号\n4. 刷新页面到登录界面',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _performGracefulReload(),
            child: const Text('立即刷新', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  /// 🔧 执行优雅刷新（断开连接 → 清理状态 → 刷新页面）
  Future<void> _performGracefulReload() async {
    try {
      AppLogger.i('MyApp', '开始执行优雅刷新流程');
      
      // 1. 停止SSE连接
      AppLogger.i('MyApp', '步骤1: 停止SSE连接');
      _stopGlobalTaskEventListener();
      
      // 2. 清理跨标签页协调服务
      if (kIsWeb && TabCoordinationService().initialized) {
        AppLogger.i('MyApp', '步骤2: 清理跨标签页协调服务');
        try {
          TabCoordinationService().dispose();
        } catch (e) {
          AppLogger.w('MyApp', '清理跨标签页协调服务失败', e);
        }
      }
      
      // 3. 清理缓存（可选，根据需求决定）
      AppLogger.i('MyApp', '步骤3: 清理任务事件缓存');
      try {
        // TaskEventCache不提供clear方法，在刷新页面后会自动清理
        // TaskEventCache.instance.clear();
      } catch (e) {
        AppLogger.w('MyApp', '清理缓存失败', e);
      }
      
      // 4. 执行登出（版本更新时清理所有状态）
      AppLogger.i('MyApp', '步骤4: 执行登出清理认证状态');
      try {
        final authService = context.read<auth_service.AuthService>();
        await authService.logout();
        AppLogger.i('MyApp', '登出成功，认证状态已清理');
      } catch (e) {
        AppLogger.w('MyApp', '登出失败，将继续执行刷新', e);
        // 即使登出失败也继续刷新，刷新后会清理所有状态
      }
      
      // 5. 短暂延迟确保资源释放（增加延迟以确保登出请求完成）
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // 6. 刷新页面
      AppLogger.i('MyApp', '步骤5: 刷新页面');
      if (kIsWeb) {
        // Web平台使用window.location.reload()
        html.window.location.reload();
      } else {
        // 非Web平台（理论上不会收到此事件，但为了安全）
        AppLogger.w('MyApp', '非Web平台不支持自动刷新');
      }
    } catch (e, st) {
      AppLogger.e('MyApp', '执行优雅刷新失败', e, st);
      // 即使失败也尝试刷新
      if (kIsWeb) {
        html.window.location.reload();
      }
    }
  }

  void _ensureTaskControlBusHook(String userId) {
    // 已有则不重复挂钩
    if (_taskControlSub != null) return;
    _taskControlSub = EventBus.instance.eventStream.listen((evt) {
      if (evt is StartTaskEventsListening) {
        _startGlobalTaskEventListener(userId);
      } else if (evt is StopTaskEventsListening) {
        _stopGlobalTaskEventListener();
      }
    });
    AppLogger.i('MyApp', '任务监听控制总线已挂接');
  }
}


