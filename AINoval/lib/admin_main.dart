import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'blocs/admin/admin_bloc.dart';
import 'config/app_config.dart';
import 'screens/admin/admin_login_screen.dart';
import 'services/api_service/repositories/impl/admin_repository_impl.dart';
import 'services/api_service/repositories/impl/admin/llm_observability_repository_impl.dart';
import 'services/api_service/repositories/impl/subscription_repository_impl.dart';
import 'services/api_service/repositories/impl/admin/billing_repository_impl.dart';
import 'services/api_service/repositories/impl/setting_generation_repository_impl.dart';
import 'services/api_service/repositories/admin/review_repository.dart';
import 'services/api_service/repositories/admin/review_repository_impl.dart';
import 'blocs/subscription/subscription_bloc.dart';
import 'services/api_service/base/api_client.dart';
import 'services/api_service/base/sse_client.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置为管理员模式
  AppConfig.setAdminMode(true);
  
  // 初始化服务
  await _setupAdminServices();
  
  runApp(const AdminApp());
}

Future<void> _setupAdminServices() async {
  final getIt = GetIt.instance;
  
  // 注册API客户端（如果还没有注册）
  if (!getIt.isRegistered<ApiClient>()) {
    getIt.registerLazySingleton<ApiClient>(() => ApiClient());
  }
  
  // 注册SSE客户端（如果还没有注册）
  if (!getIt.isRegistered<SseClient>()) {
    getIt.registerLazySingleton<SseClient>(() => SseClient());
  }
  
  // 注册管理员专用服务
  getIt.registerLazySingleton<AdminRepositoryImpl>(() => AdminRepositoryImpl());
  getIt.registerLazySingleton<LLMObservabilityRepositoryImpl>(() => 
      LLMObservabilityRepositoryImpl(apiClient: getIt<ApiClient>()));
  // 计费审计仓库
  getIt.registerLazySingleton<BillingRepositoryImpl>(() =>
      BillingRepositoryImpl(apiClient: getIt<ApiClient>()));
  // 订阅仓库与Bloc
  getIt.registerLazySingleton<SubscriptionRepositoryImpl>(() => SubscriptionRepositoryImpl(apiClient: getIt<ApiClient>()));
  getIt.registerFactory<SubscriptionBloc>(() => SubscriptionBloc(getIt<SubscriptionRepositoryImpl>()));
  
  // 策略仓库（审核功能需要）
  getIt.registerLazySingleton<SettingGenerationRepositoryImpl>(() => 
      SettingGenerationRepositoryImpl(
        apiClient: getIt<ApiClient>(),
        sseClient: getIt<SseClient>(),
      ));
  
  // 审核仓库
  getIt.registerLazySingleton<ReviewRepository>(() => ReviewRepositoryImpl(
    apiClient: getIt<ApiClient>(),
    strategyRepo: getIt<SettingGenerationRepositoryImpl>(),
    adminRepo: getIt<AdminRepositoryImpl>(),
  ));
  
  getIt.registerFactory<AdminBloc>(() => AdminBloc(getIt<AdminRepositoryImpl>()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Bloc Providers
        BlocProvider(create: (context) => GetIt.instance<AdminBloc>()),
        BlocProvider(create: (context) => GetIt.instance<SubscriptionBloc>()),
        // Repository Providers
        Provider<ReviewRepository>.value(
          value: GetIt.instance<ReviewRepository>(),
        ),
      ],
      child: MaterialApp(
        title: 'AI Novel Writer - Admin Dashboard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const AdminLoginScreen(),
      ),
    );
  }
}