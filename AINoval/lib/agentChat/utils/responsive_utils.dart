/// 响应式工具类
/// Responsive utility class

import 'package:flutter/material.dart';
import '../config/theme_config.dart';

/// 响应式工具
/// Responsive utility
class ResponsiveUtils {
  /// 判断是否是移动端
  /// Check if mobile (<640px)
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width <= AgentChatThemeConfig.mobileMaxWidth;
  }
  
  /// 判断是否是平板
  /// Check if tablet (640-1024px)
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width > AgentChatThemeConfig.mobileMaxWidth && 
           width <= AgentChatThemeConfig.tabletMaxWidth;
  }
  
  /// 判断是否是桌面
  /// Check if desktop (>1024px)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= AgentChatThemeConfig.desktopMinWidth;
  }
  
  /// 获取屏幕类型
  /// Get screen type
  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width <= AgentChatThemeConfig.mobileMaxWidth) {
      return ScreenType.mobile;
    } else if (width <= AgentChatThemeConfig.tabletMaxWidth) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }
  
  /// 根据屏幕类型返回值
  /// Return value based on screen type
  static T valueByScreenType<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final type = getScreenType(context);
    
    switch (type) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet ?? mobile;
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }
  
  /// 获取响应式间距
  /// Get responsive spacing
  static double getSpacing(
    BuildContext context, {
    double mobile = AgentChatThemeConfig.spacing2,
    double? tablet,
    double? desktop,
  }) {
    return valueByScreenType(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
  
  /// 获取响应式字体大小
  /// Get responsive font size
  static double getFontSize(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    return valueByScreenType(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
  
  /// 获取响应式图标大小
  /// Get responsive icon size
  static double getIconSize(
    BuildContext context, {
    double mobile = 20,
    double? tablet,
    double? desktop,
  }) {
    return valueByScreenType(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
  
  /// 获取响应式按钮高度
  /// Get responsive button height
  static double getButtonHeight(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 36.0,
      tablet: 40.0,
      desktop: 44.0,
    );
  }
  
  /// 获取响应式按钮最小宽度
  /// Get responsive button min width
  static double getButtonMinWidth(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 64.0,
      tablet: 80.0,
      desktop: 96.0,
    );
  }
  
  /// 获取响应式输入框最大行数
  /// Get responsive input max lines
  static int getInputMaxLines(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 3,
      tablet: 4,
      desktop: 5,
    );
  }
  
  /// 获取响应式侧边栏宽度
  /// Get responsive sidebar width
  static double getSidebarWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (isMobile(context)) {
      return screenWidth; // 移动端全屏
    } else if (isTablet(context)) {
      return screenWidth * 0.7; // 平板70%
    } else {
      return 500; // 桌面固定500px（可调整）
    }
  }
  
  /// 获取响应式圆角
  /// Get responsive border radius
  static double getBorderRadius(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 12.0,
      tablet: 14.0,
      desktop: 16.0,
    );
  }
  
  /// 获取响应式头像尺寸
  /// Get responsive avatar size
  static double getAvatarSize(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 28.0,
      tablet: 32.0,
      desktop: 36.0,
    );
  }
  
  /// 获取响应式消息内边距
  /// Get responsive message padding
  static EdgeInsets getMessagePadding(BuildContext context) {
    final spacing = getSpacing(context);
    return EdgeInsets.all(spacing);
  }
  
  /// 获取响应式卡片内边距
  /// Get responsive card padding
  static EdgeInsets getCardPadding(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: const EdgeInsets.all(12),
      tablet: const EdgeInsets.all(16),
      desktop: const EdgeInsets.all(20),
    );
  }
  
  /// 判断是否应该使用紧凑布局
  /// Check if should use compact layout
  static bool shouldUseCompactLayout(BuildContext context) {
    return isMobile(context);
  }
  
  /// 判断是否应该显示详细信息
  /// Check if should show details
  static bool shouldShowDetails(BuildContext context) {
    return isDesktop(context);
  }
  
  /// 获取最大内容宽度
  /// Get max content width
  static double getMaxContentWidth(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: double.infinity,
      tablet: 720.0,
      desktop: 960.0,
    );
  }
  
  /// 获取网格列数
  /// Get grid column count
  static int getGridColumnCount(BuildContext context) {
    return valueByScreenType(
      context,
      mobile: 1,
      tablet: 2,
      desktop: 3,
    );
  }
  
  /// 获取响应式文本样式
  /// Get responsive text style
  static TextStyle getTextStyle(
    BuildContext context, {
    required double mobileFontSize,
    double? tabletFontSize,
    double? desktopFontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    final fontSize = valueByScreenType(
      context,
      mobile: mobileFontSize,
      tablet: tabletFontSize,
      desktop: desktopFontSize,
    );
    
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }
  
  /// 根据内容长度决定是否换行
  /// Decide whether to wrap based on content length
  static bool shouldWrap(BuildContext context, int itemCount) {
    if (isMobile(context)) {
      return itemCount > 2;
    } else if (isTablet(context)) {
      return itemCount > 4;
    } else {
      return itemCount > 6;
    }
  }
}

/// 响应式Builder
/// Responsive builder widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenType screenType) builder;
  
  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    return builder(context, screenType);
  }
}

/// 响应式可见性Widget
/// Responsive visibility widget
class ResponsiveVisibility extends StatelessWidget {
  final Widget child;
  final bool visibleOnMobile;
  final bool visibleOnTablet;
  final bool visibleOnDesktop;
  
  const ResponsiveVisibility({
    super.key,
    required this.child,
    this.visibleOnMobile = true,
    this.visibleOnTablet = true,
    this.visibleOnDesktop = true,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    
    bool isVisible;
    switch (screenType) {
      case ScreenType.mobile:
        isVisible = visibleOnMobile;
        break;
      case ScreenType.tablet:
        isVisible = visibleOnTablet;
        break;
      case ScreenType.desktop:
        isVisible = visibleOnDesktop;
        break;
    }
    
    return Visibility(
      visible: isVisible,
      child: child,
    );
  }
}




