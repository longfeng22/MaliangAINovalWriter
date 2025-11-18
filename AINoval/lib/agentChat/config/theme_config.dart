/// Agent Chat 主题配置
/// Theme configuration for Agent Chat
/// 
/// 集中管理所有颜色、字体、间距配置，方便后续修改
/// Centralized management of all colors, fonts, and spacing for easy customization

import 'package:flutter/material.dart';

/// HSL颜色辅助�?
/// HSL color helper class
class ColorToken {
  final double hue;        // 色相 0-360
  final double saturation; // 饱和�?0-100
  final double lightness;  // 亮度 0-100
  final double alpha;      // 透明�?0-1

  const ColorToken(this.hue, this.saturation, this.lightness, [this.alpha = 1.0]);

  Color toColor() {
    return HSLColor.fromAHSL(
      alpha,
      hue,
      saturation / 100.0,
      lightness / 100.0,
    ).toColor();
  }
}

/// 主题配置�?
/// Theme configuration class
class AgentChatThemeConfig {
  // ==================== Light Mode 颜色配置 ====================
  
  /// 1. 背景�?- 45° 100% 96.86%
  static const ColorToken lightBackground = ColorToken(45, 100, 96.86);
  
  /// 2. 前景�?文本主色 - 38.18° 53.23% 24.31%
  static const ColorToken lightForeground = ColorToken(38.18, 53.23, 24.31);
  
  /// 3. 边框�?- 44.21° 26.76% 86.08%
  static const ColorToken lightBorder = ColorToken(44.21, 26.76, 86.08);
  
  /// 4. 卡片背景 - 47.14° 87.5% 96.86%
  static const ColorToken lightCard = ColorToken(47.14, 87.5, 96.86);
  
  /// 5. 卡片前景�?- 210° 25% 7.8431%
  static const ColorToken lightCardForeground = ColorToken(210, 25, 7.8431);
  
  /// 6. 卡片边框 - 0° 0% 94%
  static const ColorToken lightCardBorder = ColorToken(0, 0, 94);
  
  /// 7. 主色/Primary - 38.23° 87.6% 74.71% (琥珀色主�?
  static const ColorToken lightPrimary = ColorToken(38.23, 87.6, 74.71);
  
  /// 8. 主色前景 - 39.27° 43.31% 24.9%
  static const ColorToken lightPrimaryForeground = ColorToken(39.27, 43.31, 24.9);
  
  /// 9. 次要�?- 39.27° 43.31% 24.9%
  static const ColorToken lightSecondary = ColorToken(39.27, 43.31, 24.9);
  
  /// 10. 次要色前�?- 39.75° 86.96% 81.96%
  static const ColorToken lightSecondaryForeground = ColorToken(39.75, 86.96, 81.96);
  
  /// 11. 静音/禁用背景 - 38.4° 60.98% 91.96%
  static const ColorToken lightMuted = ColorToken(38.4, 60.98, 91.96);
  
  /// 12. 静音前景 - 38.18° 53.23% 24.31%
  static const ColorToken lightMutedForeground = ColorToken(38.18, 53.23, 24.31);
  
  /// 13. 强调�?- 74.4° 39.68% 87.65%
  static const ColorToken lightAccent = ColorToken(74.4, 39.68, 87.65);
  
  /// 14. 强调色前�?- 91.43° 10.55% 39.02%
  static const ColorToken lightAccentForeground = ColorToken(91.43, 10.55, 39.02);
  
  /// 15. 危险/删除�?- 0.49° 54.19% 55.49%
  static const ColorToken lightDestructive = ColorToken(0.49, 54.19, 55.49);
  
  /// 16. 危险色前�?- 0° 0% 100%
  static const ColorToken lightDestructiveForeground = ColorToken(0, 0, 100);
  
  /// 17. 输入框边�?- 44.21° 26.76% 86.08%
  static const ColorToken lightInput = ColorToken(44.21, 26.76, 86.08);
  
  /// 18. 焦点�?- 39.27° 43.31% 24.9%
  static const ColorToken lightRing = ColorToken(39.27, 43.31, 24.9);

  // ==================== Dark Mode 颜色配置 ====================
  
  /// 19. 暗色背景 - 0° 0% 0%
  static const ColorToken darkBackground = ColorToken(0, 0, 0);
  
  /// 20. 暗色前景 - 200° 6.67% 91.18%
  static const ColorToken darkForeground = ColorToken(200, 6.67, 91.18);
  
  /// 21. 暗色边框 - 210° 5.26% 14.90%
  static const ColorToken darkBorder = ColorToken(210, 5.26, 14.90);
  
  /// 22. 暗色卡片 - 228° 9.80% 10%
  static const ColorToken darkCard = ColorToken(228, 9.80, 10);
  
  /// 23. 暗色卡片前景 - 0° 0% 85.10%
  static const ColorToken darkCardForeground = ColorToken(0, 0, 85.10);
  
  /// 24. 暗色卡片边框 - 240° 8% 15%
  static const ColorToken darkCardBorder = ColorToken(240, 8, 15);
  
  /// 25. 暗色主色 - 203.77° 87.60% 52.55%
  static const ColorToken darkPrimary = ColorToken(203.77, 87.60, 52.55);
  
  /// 26. 暗色主色前景 - 0° 0% 100%
  static const ColorToken darkPrimaryForeground = ColorToken(0, 0, 100);
  
  /// 27. 暗色次要�?- 195° 15.38% 94.90%
  static const ColorToken darkSecondary = ColorToken(195, 15.38, 94.90);
  
  /// 28. 暗色次要色前�?- 210° 25% 7.84%
  static const ColorToken darkSecondaryForeground = ColorToken(210, 25, 7.84);
  
  /// 29. 暗色静音背景 - 0° 0% 9.41%
  static const ColorToken darkMuted = ColorToken(0, 0, 9.41);
  
  /// 30. 暗色静音前景 - 210° 3.39% 46.27%
  static const ColorToken darkMutedForeground = ColorToken(210, 3.39, 46.27);
  
  /// 31. 暗色强调 - 205.71° 70% 7.84%
  static const ColorToken darkAccent = ColorToken(205.71, 70, 7.84);
  
  /// 32. 暗色强调前景 - 203.77° 87.60% 52.55%
  static const ColorToken darkAccentForeground = ColorToken(203.77, 87.60, 52.55);
  
  /// 33. 暗色危险�?- 356.30° 90.56% 54.31%
  static const ColorToken darkDestructive = ColorToken(356.30, 90.56, 54.31);
  
  /// 34. 暗色危险前景 - 0° 0% 100%
  static const ColorToken darkDestructiveForeground = ColorToken(0, 0, 100);
  
  /// 35. 暗色输入边框 - 207.69° 27.66% 18.43%
  static const ColorToken darkInput = ColorToken(207.69, 27.66, 18.43);
  
  /// 36. 暗色焦点�?- 202.82° 89.12% 53.14%
  static const ColorToken darkRing = ColorToken(202.82, 89.12, 53.14);

  // ==================== 功能性颜�?====================
  
  /// AI消息背景 (Light) - 240° 8% 14%
  static const ColorToken lightAiMessageBg = ColorToken(240, 8, 14);
  
  /// AI消息背景 (Dark) - 240° 8% 14%
  static const ColorToken darkAiMessageBg = ColorToken(240, 8, 14);
  
  /// 用户消息背景 (Light) - 270° 40% 20%
  static const ColorToken lightUserMessageBg = ColorToken(270, 40, 20);
  
  /// 用户消息背景 (Dark) - 270° 40% 20%
  static const ColorToken darkUserMessageBg = ColorToken(270, 40, 20);
  
  /// 工具调用指示 - 蓝色 200° 60% 25%
  static const ColorToken toolCallBg = ColorToken(200, 60, 25);
  
  /// 引用标记 - 紫色 270° 50% 25%
  static const ColorToken citationBg = ColorToken(270, 50, 25);
  
  /// 思考状�?- 紫色 270° 70% 50%
  static const ColorToken thinkingStateBg = ColorToken(270, 70, 50);
  
  /// View工具颜色 - 蓝色
  static const ColorToken toolViewColor = ColorToken(210, 80, 60);
  
  /// CRUD创建工具 - 绿色
  static const ColorToken toolCreateColor = ColorToken(120, 60, 45);
  
  /// CRUD更新工具 - 黄色
  static const ColorToken toolUpdateColor = ColorToken(45, 90, 60);
  
  /// CRUD删除工具 - 红色
  static const ColorToken toolDeleteColor = ColorToken(0, 70, 55);
  
  /// 批准块边�?- 警告�?
  static const ColorToken approvalBorderColor = ColorToken(45, 100, 51);

  // ==================== 引用类型颜色 ====================
  
  /// 设定引用 - 紫色
  static const ColorToken citationSetting = ColorToken(270, 70, 60);
  
  /// 章节引用 - 蓝色
  static const ColorToken citationChapter = ColorToken(210, 70, 60);
  
  /// 大纲引用 - 绿色
  static const ColorToken citationOutline = ColorToken(150, 60, 50);
  
  /// 片段引用 - 橙色
  static const ColorToken citationFragment = ColorToken(30, 80, 60);

  // ==================== Typography & Spacing ====================
  
  /// 字体家族 - Sans Serif (Light)
  static const String fontSansLight = 'Lora'; // 对应 'Lora', serif
  
  /// 字体家族 - Sans Serif (Dark)
  static const String fontSansDark = 'Noto Sans SC'; // 对应 Open Sans
  
  /// 字体家族 - Monospace
  static const String fontMono = 'Roboto Mono'; // 对应 Menlo/Space Grotesk
  
  /// 圆角半径 (Light)
  static const double radiusLight = 14.0; // 0.875rem = 14px
  
  /// 圆角半径 (Dark)
  static const double radiusDark = 20.8; // 1.3rem = 20.8px
  
  /// 基础间距单位
  static const double spacing = 4.0; // 0.25rem = 4px
  
  /// 间距倍数
  static const double spacing2 = spacing * 2;  // 8px
  static const double spacing3 = spacing * 3;  // 12px
  static const double spacing4 = spacing * 4;  // 16px
  static const double spacing6 = spacing * 6;  // 24px
  static const double spacing8 = spacing * 8;  // 32px
  static const double spacing12 = spacing * 12; // 48px
  static const double spacing16 = spacing * 16; // 64px

  // ==================== 响应式断�?====================
  
  /// 移动端最大宽�?
  static const double mobileMaxWidth = 639;
  
  /// 平板最小宽�?
  static const double tabletMinWidth = 640;
  
  /// 平板最大宽�?
  static const double tabletMaxWidth = 1023;
  
  /// 桌面最小宽�?
  static const double desktopMinWidth = 1024;

  // ==================== 动画配置 ====================
  
  /// 思考指示器脉冲动画时长
  static const Duration thinkingPulseDuration = Duration(milliseconds: 1500);
  
  /// 消息入场动画时长
  static const Duration messageEntranceDuration = Duration(milliseconds: 200);
  
  /// 工具展开/折叠动画时长
  static const Duration toolExpandDuration = Duration(milliseconds: 300);
  
  /// 标签切换动画时长
  static const Duration tabSwitchDuration = Duration(milliseconds: 150);

  // ==================== 辅助方法 ====================
  
  /// 根据当前主题获取颜色
  /// Get color based on current theme
  static Color getColor(ColorToken light, ColorToken dark, bool isDark) {
    return isDark ? dark.toColor() : light.toColor();
  }
  
  /// 生成Flutter ThemeData (Light)
  static ThemeData getLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: lightPrimary.toColor(),
      scaffoldBackgroundColor: lightBackground.toColor(),
      cardColor: lightCard.toColor(),
      dividerColor: lightBorder.toColor(),
      colorScheme: ColorScheme.light(
        primary: lightPrimary.toColor(),
        onPrimary: lightPrimaryForeground.toColor(),
        secondary: lightSecondary.toColor(),
        onSecondary: lightSecondaryForeground.toColor(),
        error: lightDestructive.toColor(),
        onError: lightDestructiveForeground.toColor(),
        surface: lightCard.toColor(),
        onSurface: lightCardForeground.toColor(),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: lightForeground.toColor()),
        bodyMedium: TextStyle(color: lightForeground.toColor()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderSide: BorderSide(color: lightInput.toColor()),
          borderRadius: BorderRadius.circular(radiusLight),
        ),
      ),
    );
  }
  
  /// 生成Flutter ThemeData (Dark)
  static ThemeData getDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: darkPrimary.toColor(),
      scaffoldBackgroundColor: darkBackground.toColor(),
      cardColor: darkCard.toColor(),
      dividerColor: darkBorder.toColor(),
      colorScheme: ColorScheme.dark(
        primary: darkPrimary.toColor(),
        onPrimary: darkPrimaryForeground.toColor(),
        secondary: darkSecondary.toColor(),
        onSecondary: darkSecondaryForeground.toColor(),
        error: darkDestructive.toColor(),
        onError: darkDestructiveForeground.toColor(),
        surface: darkCard.toColor(),
        onSurface: darkCardForeground.toColor(),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: darkForeground.toColor()),
        bodyMedium: TextStyle(color: darkForeground.toColor()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderSide: BorderSide(color: darkInput.toColor()),
          borderRadius: BorderRadius.circular(radiusDark),
        ),
      ),
    );
  }
  
  /// 判断当前屏幕类型
  /// Determine current screen type
  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width <= mobileMaxWidth) {
      return ScreenType.mobile;
    } else if (width <= tabletMaxWidth) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }
  
  /// 根据屏幕类型获取间距
  /// Get spacing based on screen type
  static double getResponsiveSpacing(ScreenType type, {
    double mobile = spacing2,
    double tablet = spacing3,
    double desktop = spacing4,
  }) {
    switch (type) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet;
      case ScreenType.desktop:
        return desktop;
    }
  }
}

/// 屏幕类型枚举
/// Screen type enum
enum ScreenType {
  mobile,
  tablet,
  desktop,
}




