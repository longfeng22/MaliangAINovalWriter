/// 主题扩展 - 添加light和dark的ThemeData
/// Theme extension - Add light and dark ThemeData

import 'package:flutter/material.dart';
import 'theme_config.dart';

extension AgentChatThemeExtension on AgentChatThemeConfig {
  /// 浅色主题
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    primaryColor: AgentChatThemeConfig.lightPrimary.toColor(),
    scaffoldBackgroundColor: AgentChatThemeConfig.lightBackground.toColor(),
    cardColor: AgentChatThemeConfig.lightCard.toColor(),
    colorScheme: ColorScheme.light(
      primary: AgentChatThemeConfig.lightPrimary.toColor(),
      onPrimary: AgentChatThemeConfig.lightPrimaryForeground.toColor(),
      secondary: AgentChatThemeConfig.lightSecondary.toColor(),
      onSecondary: AgentChatThemeConfig.lightSecondaryForeground.toColor(),
      surface: AgentChatThemeConfig.lightCard.toColor(),
      onSurface: AgentChatThemeConfig.lightCardForeground.toColor(),
      error: AgentChatThemeConfig.lightDestructive.toColor(),
      onError: AgentChatThemeConfig.lightDestructiveForeground.toColor(),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
    ),
  );
  
  /// 深色主题
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    primaryColor: AgentChatThemeConfig.darkPrimary.toColor(),
    scaffoldBackgroundColor: AgentChatThemeConfig.darkBackground.toColor(),
    cardColor: AgentChatThemeConfig.darkCard.toColor(),
    colorScheme: ColorScheme.dark(
      primary: AgentChatThemeConfig.darkPrimary.toColor(),
      onPrimary: AgentChatThemeConfig.darkPrimaryForeground.toColor(),
      secondary: AgentChatThemeConfig.darkSecondary.toColor(),
      onSecondary: AgentChatThemeConfig.darkSecondaryForeground.toColor(),
      surface: AgentChatThemeConfig.darkCard.toColor(),
      onSurface: AgentChatThemeConfig.darkCardForeground.toColor(),
      error: AgentChatThemeConfig.darkDestructive.toColor(),
      onError: AgentChatThemeConfig.darkDestructiveForeground.toColor(),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
    ),
  );
}


