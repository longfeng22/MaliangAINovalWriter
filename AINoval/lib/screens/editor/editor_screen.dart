import 'package:ainoval/blocs/auth/auth_bloc.dart';
import 'package:ainoval/blocs/sidebar/sidebar_bloc.dart';
// import 'package:ainoval/config/app_config.dart';
// import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/screens/editor/components/editor_layout.dart';
import 'package:ainoval/screens/editor/controllers/editor_screen_controller.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
// import 'package:ainoval/screens/editor/widgets/continue_writing_form.dart';
// import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
// import 'package:ainoval/services/api_service/repositories/user_ai_model_config_repository.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
// import 'package:ainoval/utils/logger.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
// import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/services/api_service/repositories/novel_setting_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_setting_repository_impl.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
// import 'package:ainoval/services/api_service/repositories/prompt_repository.dart';
// import 'package:ainoval/services/api_service/repositories/impl/prompt_repository_impl.dart';
// import 'package:ainoval/screens/prompt/prompt_screen.dart';

/// 编辑器屏幕
/// 使用设计模式重构后的编辑器屏幕，将功能拆分为多个组件
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.novel,
  });
  final NovelSummary novel;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  late final EditorScreenController _controller;
  late final EditorLayoutManager _layoutManager;
  late final EditorStateManager _stateManager;
  late final PromptNewBloc _promptNewBloc;
  


  late final SidebarBloc _sidebarBloc;

  @override
  void initState() {
    super.initState();
    _controller = EditorScreenController(
      novel: widget.novel,
      vsync: this,
    );
    _layoutManager = EditorLayoutManager();
    _stateManager = EditorStateManager();
    
    // 初始化 SidebarBloc
    _sidebarBloc = SidebarBloc(
      editorRepository: _controller.editorRepository,
    );
    
    // 初始化 PromptNewBloc
    _promptNewBloc = PromptNewBloc(
      promptRepository: _controller.promptRepository,
    );
    
    // 加载小说结构数据
    _sidebarBloc.add(LoadNovelStructure(widget.novel.id));
    

  }
  

  
  // 自动续写对话框显示控制
  void _showAutoContinueWritingDialog() {
    // 暂时留空，功能待实现
  }

  @override
  void dispose() {
    // 关闭SidebarBloc
    _sidebarBloc.close();
    
    // 关闭PromptNewBloc
    _promptNewBloc.close();
    
    // 尝试同步当前小说数据
    _controller.syncCurrentNovel();

    // 通知小说列表页面刷新数据
    _controller.notifyNovelListRefresh(context);

    // 释放控制器资源
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => curr is AuthUnauthenticated,
      listener: (context, state) {
        // 监听认证状态变化，当用户未认证时导航回登录页面
        if (state is AuthUnauthenticated) {
          // 确保在widget仍然挂载时执行导航
          if (mounted) {
            // 使用pushNamedAndRemoveUntil清除导航栈并返回根路由（主页会按未登录态渲染）
            try {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            } catch (_) {
              // 回退方案：尽力返回到第一个路由
              try {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } catch (_) {}
            }
          }
        }
      },
              child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<NovelSettingRepository>(
            create: (context) => NovelSettingRepositoryImpl(
              // 复用全局提供的 ApiClient，确保401时能触发统一的登出逻辑
              apiClient: context.read<ApiClient>(),
            ),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            // 确保AuthBloc在编辑器中可用
            BlocProvider.value(value: context.read<AuthBloc>()),
            BlocProvider.value(value: _controller.editorBloc),
            BlocProvider.value(value: _sidebarBloc),
            BlocProvider.value(value: _promptNewBloc),
            ChangeNotifierProvider.value(value: _controller),
            ChangeNotifierProvider.value(value: _layoutManager),
            BlocProvider.value(value: _controller.settingBlocInstance),
          ],
          child: ValueListenableBuilder<String>(
            valueListenable: WebTheme.variantListenable,
            builder: (context, variant, _) {
              // 通过监听变体，确保本地Theme随全局主题变更而重建
              return Theme(
                data: Theme.of(context).copyWith(
                  // 使用全局主题的颜色，随变体变更
                  scaffoldBackgroundColor: Theme.of(context).scaffoldBackgroundColor, // 使用正确的背景色
                  cardColor: Theme.of(context).colorScheme.surface, // 使用动态卡片背景色
                ),
                child: EditorLayout(
                  controller: _controller,
                  layoutManager: _layoutManager,
                  stateManager: _stateManager,
                  onAutoContinueWritingPressed: _showAutoContinueWritingDialog,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
