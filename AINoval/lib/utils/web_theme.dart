import 'package:flutter/material.dart';

/// 内部使用的调色板定义（顶层私有类，以满足 Dart 语法）
class _Palette {
  final Color background;
  final Color surface;
  final Color card;
  final Color primary;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color borderSecondary;
  final Color emptyState;

  const _Palette({
    required this.background,
    required this.surface,
    required this.card,
    required this.primary,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.borderSecondary,
    required this.emptyState,
  });
}

/// Web应用的统一主题配置
/// 采用现代简洁的黑白配色方案，不使用蓝色等鲜艳颜色
class WebTheme {
  /// 私有构造函数，防止实例化
  WebTheme._();

  // ============= 主题变体支持 =============
  /// 可选的主题变体
  static const String variantMonochrome = 'monochrome';
  static const String variantBlueWhite = 'blueWhite';
  static const String variantPinkWhite = 'pinkWhite';
  static const String variantPaper = 'paperWhite';

  /// 当前主题变体（全局，简单实现）
  static String _currentVariant = variantMonochrome;

  /// 设置当前主题变体
  static void applyVariant(String variant) {
    if (variant == variantBlueWhite ||
        variant == variantPinkWhite ||
        variant == variantPaper ||
        variant == variantMonochrome) {
      _currentVariant = variant;
      try {
        variantNotifier.value = variant;
      } catch (_) {}
    } else {
      _currentVariant = variantMonochrome;
      try {
        variantNotifier.value = variantMonochrome;
      } catch (_) {}
    }
  }

  /// 获取当前主题变体
  static String get currentVariant => _currentVariant;

  /// 颜色调色板（见顶层类 _Palette）

  /// 根据主题变体与明暗模式获取调色板
  static _Palette _getPalette(BuildContext context) {
    final bool isDark = isDarkMode(context);

    // 纸张风格（偏米色）
    if (_currentVariant == variantPaper && !isDark) {
      final background = const Color(0xFFF6F1E7); // 纸张背景
      final surface = const Color(0xFFFAF6EE);
      final border = const Color(0xFFE7DECC);
      return _Palette(
        background: background,
        surface: surface,
        card: surface,
        primary: const Color(0xFF3E3A2F),
        secondary: const Color(0xFF6B675D),
        textPrimary: const Color(0xFF2F2B21),
        textSecondary: const Color(0xFF6E6856),
        border: border,
        borderSecondary: const Color(0xFFD7CCB6),
        emptyState: const Color(0xFFF3ECE0),
      );
    }

    // 蓝白风格（亮色）
    if (_currentVariant == variantBlueWhite && !isDark) {
      return const _Palette(
        background: white,
        surface: grey50,
        card: white,
        primary: Color(0xFF1E88E5),
        secondary: Color(0xFF1565C0),
        textPrimary: grey900,
        textSecondary: grey700,
        border: grey300,
        borderSecondary: grey200,
        emptyState: grey50,
      );
    }

    // 粉白风格（亮色）
    if (_currentVariant == variantPinkWhite && !isDark) {
      return const _Palette(
        background: white,
        surface: grey50,
        card: white,
        primary: Color(0xFFD81B60),
        secondary: Color(0xFFAD1457),
        textPrimary: grey900,
        textSecondary: grey700,
        border: grey300,
        borderSecondary: grey200,
        emptyState: grey50,
      );
    }

    // 暗色模式：保持原来的暗色基调
    if (isDark) {
      return const _Palette(
        background: darkBackground,
        surface: darkGrey100,
        card: darkGrey100,
        primary: darkPrimary,
        secondary: darkSecondary,
        textPrimary: darkGrey900,
        textSecondary: darkGrey700,
        border: darkGrey200,
        borderSecondary: darkGrey300,
        emptyState: darkGrey200,
      );
    }

    // 默认：黑白单色
    return const _Palette(
      background: lightBackground,
      surface: white,
      card: white,
      primary: lightPrimary,
      secondary: lightSecondary,
      textPrimary: grey900,
      textSecondary: grey700,
      border: grey200,
      borderSecondary: grey300,
      emptyState: grey50,
    );
  }

  /// 无需上下文的调色板获取（用于构建全局 ThemeData）
  static _Palette _getPaletteForBrightness(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    if (_currentVariant == variantPaper && !isDark) {
      final background = const Color(0xFFF6F1E7);
      final surface = const Color(0xFFFAF6EE);
      final border = const Color(0xFFE7DECC);
      return _Palette(
        background: background,
        surface: surface,
        card: surface,
        primary: const Color(0xFF3E3A2F),
        secondary: const Color(0xFF6B675D),
        textPrimary: const Color(0xFF2F2B21),
        textSecondary: const Color(0xFF6E6856),
        border: border,
        borderSecondary: const Color(0xFFD7CCB6),
        emptyState: const Color(0xFFF3ECE0),
      );
    }

    if (_currentVariant == variantBlueWhite && !isDark) {
      return const _Palette(
        background: white,
        surface: grey50,
        card: white,
        primary: Color(0xFF1E88E5),
        secondary: Color(0xFF1565C0),
        textPrimary: grey900,
        textSecondary: grey700,
        border: grey300,
        borderSecondary: grey200,
        emptyState: grey50,
      );
    }

    if (_currentVariant == variantPinkWhite && !isDark) {
      return const _Palette(
        background: white,
        surface: grey50,
        card: white,
        primary: Color(0xFFD81B60),
        secondary: Color(0xFFAD1457),
        textPrimary: grey900,
        textSecondary: grey700,
        border: grey300,
        borderSecondary: grey200,
        emptyState: grey50,
      );
    }

    if (isDark) {
      return const _Palette(
        background: darkBackground,
        surface: darkGrey100,
        card: darkGrey100,
        primary: darkPrimary,
        secondary: darkSecondary,
        textPrimary: darkGrey900,
        textSecondary: darkGrey700,
        border: darkGrey200,
        borderSecondary: darkGrey300,
        emptyState: darkGrey200,
      );
    }

    return const _Palette(
      background: lightBackground,
      surface: white,
      card: white,
      primary: lightPrimary,
      secondary: lightSecondary,
      textPrimary: grey900,
      textSecondary: grey700,
      border: grey200,
      borderSecondary: grey300,
      emptyState: grey50,
    );
  }

  /// 主题变体的变更通知器
  static final ValueNotifier<String> variantNotifier =
      ValueNotifier<String>(_currentVariant);

  /// 提供给外部监听
  static ValueNotifier<String> get variantListenable => variantNotifier;

  // 基础颜色 - 黑白配色
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  
  // 灰色系列 - 用于不同层次的视觉分层
  static const Color grey50 = Color(0xFFFAFAFA);   // 最浅的背景
  static const Color grey100 = Color(0xFFF5F5F5);  // 卡片背景
  static const Color grey200 = Color(0xFFEEEEEE);  // 分割线
  static const Color grey300 = Color(0xFFE0E0E0);  // 边框
  static const Color grey400 = Color(0xFFBDBDBD);  // 禁用文字
  static const Color grey500 = Color(0xFF757575);  // 次要文字 - 加深一些
  static const Color grey600 = Color(0xFF616161);  // 图标 - 加深一些
  static const Color grey700 = Color(0xFF424242);  // 主要文字
  static const Color grey800 = Color(0xFF212121);  // 标题文字
  static const Color grey900 = Color(0xFF000000);  // 最深的文字

  // 暗色主题的灰色系列
  static const Color darkGrey50 = Color(0xFF1A1A1A);   // 最深的背景
  static const Color darkGrey100 = Color(0xFF2D2D2D);  // 卡片背景
  static const Color darkGrey200 = Color(0xFF404040);  // 分割线
  static const Color darkGrey300 = Color(0xFF525252);  // 边框
  static const Color darkGrey400 = Color(0xFF737373);  // 禁用文字
  static const Color darkGrey500 = Color(0xFF9E9E9E);  // 次要文字
  static const Color darkGrey600 = Color(0xFFBDBDBD);  // 图标
  static const Color darkGrey700 = Color(0xFFE0E0E0);  // 主要文字
  static const Color darkGrey800 = Color(0xFFF5F5F5);  // 标题文字
  static const Color darkGrey900 = Color(0xFFFFFFFF);  // 最亮的文字

  // 功能性颜色 - 使用灰色调，保持一致性
  static const Color success = Color(0xFF2E7D32);     // 成功 - 深绿
  static const Color warning = Color(0xFFE65100);     // 警告 - 深橙
  static const Color error = Color(0xFFD32F2F);       // 错误 - 深红
  static const Color info = Color(0xFF424242);        // 信息 - 深灰

  // 亮色主题配色
  static const Color lightPrimary = grey900;          // 主色调
  static const Color lightSecondary = grey700;        // 次要色调
  static const Color lightBackground = white;         // 主背景
  static const Color lightSurface = grey50;           // 表面背景
  static const Color lightCard = white;               // 卡片背景
  static const Color lightOnPrimary = white;          // 主色调上的文字
  static const Color lightOnSecondary = white;        // 次要色调上的文字
  static const Color lightOnBackground = grey900;     // 背景上的文字
  static const Color lightOnSurface = grey900;        // 表面上的文字

  // 暗色主题配色
  static const Color darkPrimary = darkGrey900;       // 主色调
  static const Color darkSecondary = darkGrey700;     // 次要色调
  static const Color darkBackground = darkGrey50;     // 主背景
  static const Color darkSurface = darkGrey100;       // 表面背景
  static const Color darkCard = darkGrey100;          // 卡片背景
  static const Color darkOnPrimary = darkGrey50;      // 主色调上的文字
  static const Color darkOnSecondary = darkGrey50;    // 次要色调上的文字
  static const Color darkOnBackground = darkGrey900;  // 背景上的文字
  static const Color darkOnSurface = darkGrey900;     // 表面上的文字

  /// 文字样式定义
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 14, // 从16降低到14，适配1080p显示
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 12, // 从14降低到12，适配1080p显示
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 14, // 从16降低到14，适配1080p显示
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 12, // 从14降低到12，适配1080p显示
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  /// 亮色主题
  static ThemeData buildLightTheme() {
    final p = _getPaletteForBrightness(Brightness.light);
      return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.light(
        brightness: Brightness.light,
        primary: p.primary,
        onPrimary: lightOnPrimary,
        secondary: p.secondary,
        onSecondary: lightOnSecondary,
        error: error,
        onError: white,
        surface: p.background,
        onSurface: p.textPrimary,
        outline: p.borderSecondary,
        // 统一扩展：补齐常用的容器/变体色，避免默认Material色系导致风格不一致
        outlineVariant: p.border,
      ).copyWith(
        // 容器色使用主/次色，具体透明度由调用处控制
        primaryContainer: p.primary,
        onPrimaryContainer: lightOnPrimary,
        secondaryContainer: p.secondary,
        onSurfaceVariant: p.textSecondary,
        surfaceContainerHighest: p.surface,
      ),
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.card,
        foregroundColor: p.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ).copyWith(color: p.textPrimary),
        iconTheme: IconThemeData(
          color: p.textSecondary,
          size: 24,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: TextStyle(
          color: p.textSecondary,
          decoration: TextDecoration.none,
        ),
        hintStyle: TextStyle(
          color: p.textSecondary,
          decoration: TextDecoration.none,
        ),
      ),
      iconTheme: IconThemeData(
        color: p.textSecondary,
        size: 24,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.transparent,
        thickness: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
    );
  }

  /// 暗色主题
  static ThemeData buildDarkTheme() {
    final p = _getPaletteForBrightness(Brightness.dark);
      return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        primary: p.primary,
        onPrimary: darkOnPrimary,
        secondary: p.secondary,
        onSecondary: darkOnSecondary,
        error: error,
        onError: white,
        surface: p.background,
        onSurface: p.textPrimary,
        outline: p.borderSecondary,
        outlineVariant: p.border,
      ).copyWith(
        primaryContainer: p.primary,
        onPrimaryContainer: darkOnPrimary,
        secondaryContainer: p.secondary,
        onSurfaceVariant: p.textSecondary,
        surfaceContainerHighest: p.surface,
      ),
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.card,
        foregroundColor: p.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ).copyWith(color: p.textPrimary),
        iconTheme: IconThemeData(
          color: p.textSecondary,
          size: 24,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // 暗色模式下主按钮使用黑底白字
          backgroundColor: black,
          foregroundColor: white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // 明确透明背景，避免出现白底
          backgroundColor: Colors.transparent,
          foregroundColor: p.textPrimary,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 与 Elevated 保持一致：黑底白字
          backgroundColor: black,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: TextStyle(
          color: p.textSecondary,
          decoration: TextDecoration.none,
        ),
        hintStyle: TextStyle(
          color: p.textSecondary,
          decoration: TextDecoration.none,
        ),
      ),
      iconTheme: IconThemeData(
        color: p.textSecondary,
        size: 24,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.transparent,
        thickness: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
    );
  }

  /// 便捷方法：获取当前主题的颜色
  static Color getPrimaryColor(BuildContext context) {
    final p = _getPalette(context);
    return p.primary;
  }

  static Color getSecondaryColor(BuildContext context) {
    final p = _getPalette(context);
    return p.secondary;
  }

  static Color getBackgroundColor(BuildContext context) {
    final p = _getPalette(context);
    return p.background;
  }

  static Color getSurfaceColor(BuildContext context) {
    final p = _getPalette(context);
    return p.surface;
  }

  static Color getOnSurfaceColor(BuildContext context) {
    final p = _getPalette(context);
    return p.textPrimary;
  }

  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// 统一的按钮样式
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: grey900,
    foregroundColor: white,
    elevation: 2,
    shadowColor: grey300.withValues(alpha: 0.3),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  static ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: grey900,
    side: const BorderSide(color: grey300, width: 1.5),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  static ButtonStyle iconButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: grey900,
    foregroundColor: white,
    elevation: 3,
    shadowColor: grey300.withValues(alpha: 0.4),
    padding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    minimumSize: const Size(120, 50),
  );

  /// 获取主要按钮样式
  static ButtonStyle getPrimaryButtonStyle(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    final p = _getPalette(context);
    return ElevatedButton.styleFrom(
      backgroundColor: isDark ? black : p.primary,
      foregroundColor: white,
      elevation: 2,
      shadowColor: isDark ? black.withValues(alpha: 0.4) : grey300.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 获取图标按钮样式
  static ButtonStyle getIconButtonStyle(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    final p = _getPalette(context);
    return ElevatedButton.styleFrom(
      backgroundColor: isDark ? black : p.primary,
      foregroundColor: white,
      elevation: 3,
      shadowColor: isDark ? black.withValues(alpha: 0.4) : grey300.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      minimumSize: const Size(120, 50),
    );
  }

  /// 获取次要按钮样式（outline样式）
  static ButtonStyle getSecondaryButtonStyle(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    final p = _getPalette(context);
    return OutlinedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: p.textPrimary,
      side: BorderSide(
        color: isDark ? darkGrey400 : p.border,
        width: 1.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 0,
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 获取无边框的输入框装饰样式（用于编辑器标题等）
  static InputDecoration getBorderlessInputDecoration({
    String? hintText,
    String? labelText,
    bool isDense = true,
    EdgeInsetsGeometry? contentPadding,
    BuildContext? context,
  }) {
    return InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      hintText: hintText,
      labelText: labelText,
      isDense: isDense,
      contentPadding: contentPadding ?? EdgeInsets.zero,
      hintStyle: context != null 
        ? TextStyle(
            color: getSecondaryTextColor(context),
            decoration: TextDecoration.none, // 明确去掉下划线
          )
        : const TextStyle(
            color: grey500,
            decoration: TextDecoration.none, // 明确去掉下划线
          ),
      labelStyle: context != null
        ? TextStyle(
            color: getSecondaryTextColor(context),
            decoration: TextDecoration.none, // 明确去掉下划线
          )
        : const TextStyle(
            color: grey600,
            decoration: TextDecoration.none, // 明确去掉下划线
          ),
    );
  }

  /// 获取有边框的输入框装饰样式（用于表单）
  static InputDecoration getBorderedInputDecoration({
    String? hintText,
    String? labelText,
    bool isDense = true,
    EdgeInsetsGeometry? contentPadding,
    BuildContext? context,
  }) {
    final isDark = context != null ? isDarkMode(context) : false;
    
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? darkGrey300 : grey300,
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? darkGrey300 : grey300,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? darkGrey600 : grey600,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: error,
          width: 1,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? darkGrey200 : grey200,
          width: 1,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: error,
          width: 2,
        ),
      ),
      filled: true,
      fillColor: context != null 
        ? (isDark ? darkGrey50 : white)
        : white,
      hintText: hintText,
      labelText: labelText,
      isDense: isDense,
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      hintStyle: context != null 
        ? TextStyle(
            color: getSecondaryTextColor(context),
            decoration: TextDecoration.none,
          )
        : const TextStyle(
            color: grey500,
            decoration: TextDecoration.none,
          ),
      labelStyle: context != null
        ? TextStyle(
            color: getSecondaryTextColor(context),
            decoration: TextDecoration.none,
          )
        : const TextStyle(
            color: grey600,
            decoration: TextDecoration.none,
          ),
    );
  }

  /// 获取Material组件的透明样式（去掉黄色下划线）
  static Widget getMaterialWrapper({
    required Widget child,
    Color? color,
  }) {
    return Material(
      type: MaterialType.transparency, // 使用透明类型避免黄色下划线
      color: color ?? Colors.transparent,
      child: child,
    );
  }

  /// 获取纯净卡片样式（去掉elevation和边框）
  static BoxDecoration getCleanCardDecoration({
    Color? backgroundColor,
    BorderRadius? borderRadius,
    BuildContext? context,
  }) {
    Color defaultColor = white;
    if (context != null) {
      defaultColor = getSurfaceColor(context);
    }
    
    return BoxDecoration(
      color: backgroundColor ?? defaultColor,
      borderRadius: borderRadius ?? BorderRadius.circular(0),
    );
  }

  /// 获取文字样式确保垂直对齐
  static TextStyle getAlignedTextStyle({
    required TextStyle baseStyle,
    double? height,
  }) {
    return baseStyle.copyWith(
      height: height ?? 1.0,
      textBaseline: TextBaseline.alphabetic,
    );
  }

  /// 获取一致的文字颜色
  static Color getTextColor(BuildContext context, {bool isPrimary = true}) {
    final p = _getPalette(context);
    return isPrimary ? p.textPrimary : p.textSecondary;
  }

  /// 获取次要文字颜色
  static Color getSecondaryTextColor(BuildContext context) {
    final p = _getPalette(context);
    return p.textSecondary;
  }

  /// 获取卡片背景颜色
  static Color getCardColor(BuildContext context) {
    final p = _getPalette(context);
    return p.card;
  }

  /// 获取边框颜色
  static Color getBorderColor(BuildContext context) {
    final p = _getPalette(context);
    return p.border;
  }

  /// 获取次要边框颜色
  static Color getSecondaryBorderColor(BuildContext context) {
    final p = _getPalette(context);
    return p.borderSecondary;
  }

  /// 获取阴影颜色
  static Color getShadowColor(BuildContext context, {double opacity = 0.1}) {
    final isDark = WebTheme.isDarkMode(context);
    return isDark ? black.withOpacity(opacity * 2) : grey200.withOpacity(opacity);
  }

  /// 获取空状态背景颜色
  static Color getEmptyStateColor(BuildContext context) {
    final p = _getPalette(context);
    return p.emptyState;
  }
} 