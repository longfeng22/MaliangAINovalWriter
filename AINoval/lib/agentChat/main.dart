/// Agent Chat独立启动入口
/// Agent Chat standalone entry point

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/theme_extension.dart';
import 'providers/chat_provider.dart';
import 'providers/agent_provider.dart';
import 'i18n/locale_provider.dart';
import 'screens/agent_chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgentChatApp());
}

/// Agent Chat应用
/// Agent Chat application
class AgentChatApp extends StatelessWidget {
  const AgentChatApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'Agent Chat',
            debugShowCheckedModeBanner: false,
            theme: AgentChatThemeExtension.light,
            darkTheme: AgentChatThemeExtension.dark,
            themeMode: ThemeMode.light,
            locale: Locale(localeProvider.currentLocale),
            supportedLocales: const [
              Locale('zh'),
              Locale('en'),
            ],
            home: const AgentChatScreen(),
          );
        },
      ),
    );
  }
}



