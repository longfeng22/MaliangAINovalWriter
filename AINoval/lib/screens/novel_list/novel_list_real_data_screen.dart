import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/app_sidebar.dart';
import 'package:ainoval/widgets/common/user_avatar_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/auth/auth_bloc.dart';
import 'package:ainoval/blocs/novel_list/novel_list_bloc.dart';
import 'package:ainoval/blocs/novel_import/novel_import_bloc.dart';
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/widgets/common/compact_novel_card.dart';
import 'package:ainoval/widgets/common/animated_container_widget.dart';
import 'package:ainoval/widgets/common/dropdown_menu_widget.dart' as custom;
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/screens/editor/editor_screen.dart';
import 'package:ainoval/screens/novel_list/widgets/novel_import_three_step_dialog.dart';
import 'package:ainoval/services/api_service/repositories/novel_repository.dart';
import 'package:ainoval/l10n/app_localizations.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/screens/setting_generation/novel_settings_generator_screen.dart';
import 'package:ainoval/screens/settings/settings_panel.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';

import 'widgets/novel_input_new.dart';
import 'widgets/category_tags_new.dart';
import 'widgets/community_feed_new.dart';
import 'package:ainoval/services/api_service/repositories/subscription_repository.dart';
import 'package:ainoval/services/api_service/repositories/payment_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ainoval/models/admin/subscription_models.dart';
import 'package:ainoval/screens/subscription/subscription_screen.dart';
import 'widgets/analytics_dashboard.dart';
import 'package:ainoval/widgets/common/credit_display.dart';
import 'package:ainoval/screens/auth/enhanced_login_screen.dart';
import 'package:ainoval/widgets/common/icp_record_footer.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/widgets/common/notice_ticker.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/blocs/preset/preset_bloc.dart';
import 'package:ainoval/blocs/preset/preset_event.dart';
import 'package:ainoval/screens/unified_management/unified_management_screen.dart' deferred as unified_mgmt;
import 'package:ainoval/screens/prompt_market/prompt_market_dialog.dart';
import 'package:ainoval/blocs/theme/theme_bloc.dart';
import 'package:ainoval/blocs/theme/theme_event.dart';
import 'package:ainoval/screens/knowledge_base/fanqie_novel_search_screen.dart';
import 'package:ainoval/screens/knowledge_base/public_knowledge_base_list_screen.dart';
import 'package:ainoval/screens/knowledge_base/my_knowledge_base_list_screen.dart';
import 'package:ainoval/widgets/debug/sse_debug_panel.dart';
import 'package:ainoval/utils/event_bus.dart';

// 提供匿名模式下的登录弹窗与鉴权工具方法
Future<void> showLoginDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        child: const EnhancedLoginScreen(),
      ),
    ),
  );
  
  // 如果登录成功，刷新当前页面
  if (result == true && context.mounted) {
    // 触发页面状态刷新，重新获取认证状态
    print('🔄 登录成功，触发页面刷新');
    if (context.mounted) {
      // 可以触发一个全局状态更新或者页面重建
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const NovelListRealDataScreen(),
        ),
      );
    }
  }
}

Future<bool> ensureAuthenticated(BuildContext context) async {
  final authed = context.read<AuthBloc>().state is AuthAuthenticated;
  if (authed) return true;
  await showLoginDialog(context);
  return context.read<AuthBloc>().state is AuthAuthenticated;
}

class NovelListRealDataScreen extends StatefulWidget {
  const NovelListRealDataScreen({Key? key}) : super(key: key);

  @override
  State<NovelListRealDataScreen> createState() => _NovelListRealDataScreenState();
}

class _NovelListRealDataScreenState extends State<NovelListRealDataScreen> {
  String _prompt = '';
  bool _isSidebarExpanded = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  UnifiedAIModel? _selectedModel;
  String _currentRoute = 'home';
  
  // 移除本地 _promptLogin，统一使用顶层的 showLoginDialog/ensureAuthenticated

  @override
  void initState() {
    super.initState();
    // Load novels when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isAuthed = context.read<AuthBloc>().state is AuthAuthenticated;
      if (isAuthed && context.read<NovelListBloc>().state is! NovelListLoaded) {
        context.read<NovelListBloc>().add(LoadNovels());
      }
    });

    // 订阅“跳到提示词与预设”事件，保持左侧布局
    EventBus.instance.on<NavigateToUnifiedManagement>().listen((_) {
      if (!mounted) return;
      _handleNavigation('unified_management');
    });
  }

  void _handleTagClick(String newPrompt) {
    setState(() {
      _prompt = newPrompt;
    });
  }

  void _handlePromptChanged(String value) {
    if (_prompt == value) return;
    setState(() {
      _prompt = value;
    });
  }

  void _handleModelSelected(UnifiedAIModel? model) {
    setState(() {
      _selectedModel = model;
    });
  }

  /// 🔧 显示SSE调试面板（仅开发环境）
  void _showSseDebugPanel(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SseDebugPanel(),
    );
  }

  void _handleNavigation(String route) {
    switch (route) {
      case 'home':
        setState(() { _currentRoute = 'home'; });
        break;
      case 'novels':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'novels'; });
        // 可选：切回小说视图时刷新列表
        if (mounted && (context.read<AuthBloc>().state is AuthAuthenticated)) {
          context.read<NovelListBloc>().add(LoadNovels());
        }
        break;
      case 'analytics':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'analytics'; });
        break;
      case 'prompt_market':
        // 提示词市场 - 弹出对话框
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        _showPromptMarket();
        break;
      case 'unified_management':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'unified_management'; });
        // 进入统一管理时，确保数据加载到位
        try {
          context.read<PresetBloc>().add(const LoadAllPresetData());
        } catch (_) {}
        try {
          context.read<PromptNewBloc>().add(const LoadAllPromptPackages());
        } catch (_) {}
        break;
      case 'my_subscription':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        );
        break;
      case 'settings':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: context.read<AiConfigBloc>()),
              ],
              child: const NovelSettingsGeneratorScreen(),
            ),
          ),
        );
        break;
      case 'account_settings':
        // 需要登录
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        _showSettingsDialog();
        break;
      case 'fanqie_search':
        // 番茄小说搜索（AI拆书）- 作为子视图显示
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'fanqie_search'; });
        break;
      case 'public_knowledge_bases':
        // 公共知识库列表 - 作为子视图显示
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'public_knowledge_bases'; });
        break;
      case 'my_knowledge_bases':
        // 我的知识库列表 - 作为子视图显示
        if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
          showLoginDialog(context);
          return;
        }
        setState(() { _currentRoute = 'my_knowledge_bases'; });
        break;
      default:
        // 其他导航逻辑可以在此处添加
        break;
    }
  }

  /// 显示提示词市场对话框
  void _showPromptMarket() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const PromptMarketDialog(),
    );
    
    // 处理导航请求
    if (result != null && result['navigate_to'] == 'unified_management') {
      _handleNavigation('unified_management');
    }
  }

  void _showSettingsDialog() {
    final userId = AppConfig.userId;
    if (userId == null || userId.isEmpty) return;
    // 预先获取所需的 BLoC 实例，避免在对话框 builder 内访问已卸载的 State.context
    final aiConfigBloc = context.read<AiConfigBloc>();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: aiConfigBloc),
          ],
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            backgroundColor: Colors.transparent,
            child: SettingsPanel(
              stateManager: EditorStateManager(),
              userId: userId,
              onClose: () => Navigator.of(dialogContext).pop(),
              editorSettings: const EditorSettings(),
              onEditorSettingsChanged: (_) {},
              initialCategoryIndex: SettingsPanel.accountManagementCategoryIndex,
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: WebTheme.getBackgroundColor(context),
      body: Row(
        children: [
          // Sidebar - 完全保持原样
          AppSidebar(
            isExpanded: _isSidebarExpanded,
            isAuthed: context.watch<AuthBloc>().state is AuthAuthenticated,
            onRequireAuth: () => showLoginDialog(context),
            currentRoute: _currentRoute,
            onExpandedChanged: (expanded) {
              setState(() {
                _isSidebarExpanded = expanded;
              });
            },
            onNavigate: _handleNavigation,
          ),
                      // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar - 完全保持原样
                Container(
                  height: 60,
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: WebTheme.getBorderColor(context),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!_isSidebarExpanded) ...[
                        IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () {
                            setState(() {
                              _isSidebarExpanded = true;
                            });
                          },
                          color: WebTheme.getTextColor(context),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: _currentRoute == 'analytics'
                            ? Text(
                                '数据分析',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: WebTheme.getTextColor(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              )
                            : (_currentRoute == 'novels'
                                ? Text(
                                    '我的小说',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: WebTheme.getTextColor(context),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : (_currentRoute == 'unified_management'
                                    ? Text(
                                        '提示词与预设管理',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: WebTheme.getTextColor(context),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : NoticeTicker(
                                        initialMessages: const [
            '当前小说网站属于测试状态，欢迎大家加入qq群1062403092',
            '如果有报错和bug或者改进建议，欢迎大家在群里反馈'
                                        ],
                                      ))),
                      ),
                      const Spacer(),
                      // 🔧 开发环境：SSE调试按钮
                      if (AppConfig.environment == Environment.development) ...[
                        IconButton(
                          icon: const Icon(Icons.bug_report, size: 20),
                          onPressed: () => _showSseDebugPanel(context),
                          color: Colors.orange,
                          tooltip: 'SSE连接调试',
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Theme Toggle
                      IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode : Icons.dark_mode,
                          size: 20,
                        ),
                        onPressed: () => context.read<ThemeBloc>().add(ThemeToggled()),
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                      const SizedBox(width: 4),
                      // Credit display next to avatar
                      CreditDisplay(
                        size: CreditDisplaySize.small,
                        onTap: () async {
                          if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
                            await showLoginDialog(context);
                            if (!mounted) return;
                            if (!(context.read<AuthBloc>().state is AuthAuthenticated)) return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      // User Avatar with Menu
                      Padding(
                        padding: const EdgeInsets.only(right: 0),
                        child: UserAvatarMenu(
                          size: 16,
                          onMySubscription: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                            );
                          },
                          onOpenSettings: _showSettingsDialog,
                          onProfile: _showSettingsDialog,
                          onAccountSettings: _showSettingsDialog,
                        ),
                      ),
                    ],
                  ),
                ),
                // Content Area
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: _currentRoute == 'analytics'
                        ? const AnalyticsDashboard()
                        : _currentRoute == 'novels'
                            ? const NovelGridRealData()
                            : _currentRoute == 'unified_management'
                                ? FutureBuilder(
                                    future: unified_mgmt.loadLibrary(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.done) {
                                        return unified_mgmt.UnifiedManagementScreen();
                                      }
                                      return const Center(child: CircularProgressIndicator());
                                    },
                                  )
                                : _currentRoute == 'fanqie_search'
                                    ? const FanqieNovelSearchScreen()
                                    : _currentRoute == 'public_knowledge_bases'
                                        ? const PublicKnowledgeBaseListScreen()
                                        : _currentRoute == 'my_knowledge_bases'
                                            ? const MyKnowledgeBaseListScreen()
                                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.maxWidth;
                                  final bool isNarrow = width < 1024;
                                  final bool isMedium = width >= 1024 && width < 1400;
                                  final double rightPanelWidth = width >= 1600 ? 520 : (isMedium ? 440 : 520);
                                  final EdgeInsetsGeometry panelPadding = EdgeInsets.all(isNarrow ? 16 : 24);

                                  if (isNarrow) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // Left Panel - Input Area (小屏改为上方)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 16),
                                          padding: panelPadding,
                                          decoration: BoxDecoration(
                                            color: isDark
                                              ? WebTheme.darkGrey100.withOpacity(0.2)
                                              : WebTheme.grey100.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: WebTheme.getBorderColor(context).withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                NovelInputNew(
                                                  prompt: _prompt,
                                                  onPromptChanged: _handlePromptChanged,
                                                  selectedModel: _selectedModel,
                                                  onModelSelected: _handleModelSelected,
                                                ),
                                                const SizedBox(height: 16),
                                                CategoryTagsNew(
                                                  onTagClick: _handleTagClick,
                                                ),
                                                const SizedBox(height: 16),
                                                CommunityFeedNew(
                                                  onApplyPrompt: _handlePromptChanged,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Right Panel - 下方自适应宽度与高度
                                        Expanded(
                                          child: Container(
                                            padding: panelPadding,
                                            decoration: BoxDecoration(
                                              color: WebTheme.getCardColor(context),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: WebTheme.getBorderColor(context),
                                                width: 1,
                                              ),
                                            ),
                                            child: BlocProvider(
                                              create: (context) => NovelImportBloc(
                                                novelRepository: RepositoryProvider.of<NovelRepository>(context),
                                              ),
                                              child: BlocListener<NovelImportBloc, NovelImportState>(
                                                listener: (context, importState) {
                                                  if (importState is NovelImportSuccess && mounted) {
                                                    context.read<NovelListBloc>().add(RefreshNovels());
                                                  }
                                                },
                                                child: const NovelGridRealData(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  // 宽屏/中屏：维持左右布局，右栏宽度按断点缩放
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Left Panel - Input Area
                                      Expanded(
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 24),
                                          padding: panelPadding,
                                          decoration: BoxDecoration(
                                            color: isDark
                                              ? WebTheme.darkGrey100.withOpacity(0.2)
                                              : WebTheme.grey100.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: WebTheme.getBorderColor(context).withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                NovelInputNew(
                                                  prompt: _prompt,
                                                  onPromptChanged: _handlePromptChanged,
                                                  selectedModel: _selectedModel,
                                                  onModelSelected: _handleModelSelected,
                                                ),
                                                const SizedBox(height: 24),
                                                CategoryTagsNew(
                                                  onTagClick: _handleTagClick,
                                                ),
                                                const SizedBox(height: 24),
                                                CommunityFeedNew(
                                                  onApplyPrompt: _handlePromptChanged,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Right Panel - Novel Management / My Subscription
                                      Container(
                                        width: rightPanelWidth,
                                        height: MediaQuery.of(context).size.height - 60 - 48, // 减去顶栏和padding
                                        padding: panelPadding,
                                        decoration: BoxDecoration(
                                          color: WebTheme.getCardColor(context),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: WebTheme.getBorderColor(context),
                                            width: 1,
                                          ),
                                        ),
                                        child: BlocProvider(
                                          create: (context) => NovelImportBloc(
                                            novelRepository: RepositoryProvider.of<NovelRepository>(context),
                                          ),
                                          child: BlocListener<NovelImportBloc, NovelImportState>(
                                            listener: (context, importState) {
                                              if (importState is NovelImportSuccess && mounted) {
                                                context.read<NovelListBloc>().add(RefreshNovels());
                                              }
                                            },
                                            child: const NovelGridRealData(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                  ),
                ),
                // ICP备案信息
                const ICPRecordFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Right panel - Novel grid with real data from BLoC (完全一样的520px宽度)
class NovelGridRealData extends StatefulWidget {
  const NovelGridRealData({Key? key}) : super(key: key);

  @override
  State<NovelGridRealData> createState() => _NovelGridRealDataState();
}

class _NovelGridRealDataState extends State<NovelGridRealData> {
  String _filterStatus = '全部状态';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with title and action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的小说',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '管理您创作的小说作品',
                  style: TextStyle(
                    fontSize: 14,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
            // Create and Import buttons
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateNovelDialog(context, l10n),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.createNovel),
                  style: WebTheme.getPrimaryButtonStyle(context).copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showImportNovelDialog(context),
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text(l10n.importNovel),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: BorderSide(color: WebTheme.getBorderColor(context)),
                  ),
                ),
              ],
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Search bar and filters
        Row(
          children: [
            // Search box
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索小说标题...',
                  hintStyle: TextStyle(
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: WebTheme.getBorderColor(context),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: WebTheme.getBorderColor(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: WebTheme.getPrimaryColor(context),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontSize: 14,
                ),
                onChanged: (query) {
                  if (mounted) {
                    context.read<NovelListBloc>().add(SearchNovels(query: query));
                  }
                },
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Filter dropdown
            custom.DropdownMenuWidget(
              trigger: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: WebTheme.getBorderColor(context),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 16,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '筛选',
                      style: TextStyle(
                        fontSize: 14,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              items: [
                custom.MenuItemData(value: '全部状态', label: '全部状态'),
                custom.MenuItemData(value: '草稿', label: '草稿'),
                custom.MenuItemData(value: '连载中', label: '连载中'),
                custom.MenuItemData(value: '已完结', label: '已完结'),
              ],
              onItemSelected: (value) {
                setState(() {
                  _filterStatus = value;
                });
              },
            ),
            
            const SizedBox(width: 8),
            
            // Refresh button
            IconButton(
              onPressed: () {
                if (mounted) {
                  context.read<NovelListBloc>().add(RefreshNovels());
                }
              },
              icon: Icon(
                Icons.refresh,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Novel grid content - 使用真实数据（游客模式下显示引导）
        Expanded(
          child: BlocBuilder<NovelListBloc, NovelListState>(
            builder: (context, state) {
              final authed = context.watch<AuthBloc>().state is AuthAuthenticated;
              if (!authed) {
                // 游客模式：展示“开始我的创作之旅”引导
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WebTheme.getPrimaryColor(context).withOpacity(0.12),
                        ),
                        child: Icon(Icons.auto_awesome, size: 40, color: WebTheme.getPrimaryColor(context)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '开始我的创作之旅',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '登录后即可创建、导入和管理您的小说作品',
                        style: TextStyle(
                          fontSize: 14,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: () => showLoginDialog(context),
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text('立即登录'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (state is NovelListInitial || state is NovelListLoading) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              } else if (state is NovelListLoaded) {
                final novels = _getFilteredNovels(state.novels);
                
                if (novels.isEmpty) {
                  return _buildEmptyState();
                }

                // 自适应栅格：按容器宽度计算列数与纵横比，适配1080p与4K
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = _calculateGridColumnCount(width);
                    // 恢复未展开时的长宽比（0.75）
                    final childAspectRatio = 0.75;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: novels.length,
                      itemBuilder: (context, index) {
                        final novel = novels[index];
                        return AnimatedContainerWidget(
                          animationType: AnimationType.fadeIn,
                          delay: Duration(milliseconds: index * 100),
                          child: CompactNovelCard(
                            novel: novel,
                            onContinueWriting: () async {
                              if (!await ensureAuthenticated(context)) return;
                              _navigateToEditor(novel);
                            },
                            onEdit: () async {
                              if (!await ensureAuthenticated(context)) return;
                              _navigateToEditor(novel);
                            },
                            onShare: () {
                              TopToast.info(context, '分享功能将在下一个版本中实现');
                            },
                            onDelete: () async {
                              if (!await ensureAuthenticated(context)) return;
                              _showDeleteDialog(novel);
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              } else if (state is NovelListError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: WebTheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '加载失败',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.message,
                        style: TextStyle(
                          fontSize: 14,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          context.read<NovelListBloc>().add(RefreshNovels());
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  // 根据容器宽度自适应列数：
  // - >= 3200px: 6列（4K宽容器常见）
  // - >= 2400px: 5列
  // - >= 1800px: 4列（QHD/超宽）
  // - >= 1200px: 3列（FHD/1080p 主内容区域）
  // - 其他: 2列
  int _calculateGridColumnCount(double containerWidth) {
    if (containerWidth >= 3200) return 6;
    if (containerWidth >= 2400) return 5;
    if (containerWidth >= 1800) return 4;
    if (containerWidth >= 1200) return 3;
    return 2;
  }

  // 预留：如需按宽度动态调整纵横比，可在此恢复逻辑
  // 当前统一由调用处直接指定为0.75

  List<NovelSummary> _getFilteredNovels(List<NovelSummary> novels) {
    if (_filterStatus == '全部状态') {
      return novels;
    }
    
    return novels.where((novel) {
      final status = _getNovelStatus(novel);
      return status == _filterStatus;
    }).toList();
  }

  String _getNovelStatus(NovelSummary novel) {
    if (novel.wordCount < 1000) {
      return '草稿';
    } else if (novel.completionPercentage >= 100.0) {
      return '已完结';
    } else {
      return '连载中';
    }
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.menu_book,
          size: 64,
          color: WebTheme.getSecondaryTextColor(context),
        ),
        const SizedBox(height: 16),
        Text(
          '还没有小说作品',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '开始创作您的第一部小说吧！',
          style: TextStyle(
            fontSize: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            if (!await ensureAuthenticated(context)) return;
            if (mounted) {
              context.read<NovelListBloc>().add(CreateNovel(title: '新小说'));
            }
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('创建小说'),
          style: WebTheme.getPrimaryButtonStyle(context),
        ),
      ],
    );
  }

  void _navigateToEditor(NovelSummary novel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(novel: novel),
      ),
    ).then((result) {
      if (mounted && (result == 'refresh' || result == 'updated')) {
        context.read<NovelListBloc>().add(RefreshNovels());
      }
    });
  }

  void _showDeleteDialog(NovelSummary novel) {
    final parentContext = context;
    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除小说'),
        content: Text('确定要删除小说《${novel.title}》吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) {
                parentContext.read<NovelListBloc>().add(DeleteNovel(id: novel.id));
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: WebTheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showCreateNovelDialog(BuildContext context, AppLocalizations l10n) {
    // 未登录则弹出登录
    if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
      showLoginDialog(context);
      return;
    }
    final TextEditingController titleController = TextEditingController();
    final TextEditingController seriesController = TextEditingController();
    final parentContext = this.context;

    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              color: WebTheme.getTextColor(dialogContext),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(l10n.createNovel),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: l10n.novelTitle,
                hintText: l10n.novelTitleHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.book_outlined),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: seriesController,
              decoration: InputDecoration(
                labelText: l10n.seriesName,
                hintText: l10n.seriesNameHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.bookmarks_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '添加系列可以更好地组织您的作品',
                style: TextStyle(
                  fontSize: 12,
                  color: WebTheme.getSecondaryTextColor(dialogContext),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            onPressed: () {
              final title = titleController.text.trim();
              final series = seriesController.text.trim();

              if (title.isNotEmpty) {
                Navigator.pop(dialogContext);

                if (mounted) {
                  parentContext.read<NovelListBloc>().add(CreateNovel(
                        title: title,
                        seriesName: series.isNotEmpty ? series : null,
                      ));
                }
              }
            },
            icon: const Icon(Icons.check),
            label: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  void _showImportNovelDialog(BuildContext context) {
    // 未登录则弹出登录
    if (!(context.read<AuthBloc>().state is AuthAuthenticated)) {
      showLoginDialog(context);
      return;
    }
    showNovelImportThreeStepDialog(context);
  }
}

/// 右侧“我的订阅”面板（简版，调用已有仓库）
class _MySubscriptionPanel extends StatefulWidget {
  const _MySubscriptionPanel();

  @override
  State<_MySubscriptionPanel> createState() => _MySubscriptionPanelState();
}

class _MySubscriptionPanelState extends State<_MySubscriptionPanel> {
  final _publicRepo = PublicSubscriptionRepository();
  final _payRepo = PaymentRepository();
  bool _loading = true;
  List<SubscriptionPlan> _plans = const [];
  List<Map<String, dynamic>> _packs = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final plans = await _publicRepo.listActivePlans();
      final packs = await _publicRepo.listActiveCreditPacks();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _packs = packs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '加载订阅信息失败'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('订阅计划', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: WebTheme.getTextColor(context))),
          const SizedBox(height: 8),
          ..._plans.map(_planCard),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('积分补充包', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: WebTheme.getTextColor(context))),
          const SizedBox(height: 8),
          ..._packs.map(_packCard),
        ],
      ),
    );
  }

  Widget _planCard(SubscriptionPlan p) {
    final feats = p.features ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(p.planName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('${p.price.toStringAsFixed(2)} ${p.currency}')
              ],
            ),
            if ((p.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.description!),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (feats['ai.daily.calls'] != null) _chip('AI每日:${feats['ai.daily.calls']}'),
              if (feats['import.daily.limit'] != null) _chip('导入/日:${feats['import.daily.limit']}'),
              if (feats['novel.max.count'] != null) _chip('小说上限:${feats['novel.max.count']}'),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: () => _buyPlan(p, PayChannel.wechat), child: const Text('微信支付')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _buyPlan(p, PayChannel.alipay), child: const Text('支付宝')),
            ])
          ],
        ),
      ),
    );
  }

  Widget _packCard(Map<String, dynamic> pack) {
    final name = (pack['name'] ?? '').toString();
    final price = (pack['price'] ?? '').toString();
    final currency = (pack['currency'] ?? 'CNY').toString();
    final credits = (pack['credits'] ?? '').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text('$price $currency')
            ]),
            const SizedBox(height: 6),
            Text('包含积分：$credits'),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: () => _buyCreditPack(pack, PayChannel.wechat), child: const Text('微信支付')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _buyCreditPack(pack, PayChannel.alipay), child: const Text('支付宝')),
            ])
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: WebTheme.getPrimaryColor(context).withAlpha(24),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text),
  );

  Future<void> _buyPlan(SubscriptionPlan p, PayChannel channel) async {
    try {
      final order = await _payRepo.createPayment(planId: p.id!, channel: channel);
      if (order.paymentUrl.isNotEmpty) {
        final uri = Uri.parse(order.paymentUrl);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _buyCreditPack(Map<String, dynamic> pack, PayChannel channel) async {
    try {
      final id = (pack['id'] ?? '').toString();
      final order = await _payRepo.createCreditPackPayment(planId: id, channel: channel);
      if (order.paymentUrl.isNotEmpty) {
        final uri = Uri.parse(order.paymentUrl);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}