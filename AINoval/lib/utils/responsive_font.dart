/// 响应式字体大小工具类
library;

import 'package:flutter/material.dart';

class ResponsiveFontSize {
  // 基于屏幕宽度的动态字体大小计算
  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    
    // 定义基准宽度（1920px为标准桌面分辨率）
    const baseWidth = 1920.0;
    
    // 计算缩放比例
    double scaleFactor = width / baseWidth;
    
    // 限制缩放范围：
    // - 最小0.7倍（小屏幕不会太小）
    // - 最大1.3倍（大屏幕不会太大）
    scaleFactor = scaleFactor.clamp(0.7, 1.3);
    
    return baseSize * scaleFactor;
  }
  
  // 分段式响应字体大小
  static double getSegmentedFontSize(BuildContext context, {
    required double mobile,    // < 800px
    required double tablet,    // 800-1440px
    required double desktop,   // 1440-2560px
    required double ultra,     // > 2560px
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < 800) {
      return mobile;
    } else if (width < 1440) {
      return tablet;
    } else if (width < 2560) {
      return desktop;
    } else {
      return ultra;
    }
  }
  
  // 预定义的响应式字体大小（使用比例缩放）
  
  /// 超大标题（如页面主标题）
  static double extraLarge(BuildContext context) => getResponsiveFontSize(context, 32);
  
  /// 大标题
  static double large(BuildContext context) => getResponsiveFontSize(context, 28);
  
  /// 标题
  static double title(BuildContext context) => getResponsiveFontSize(context, 24);
  
  /// 副标题
  static double subtitle(BuildContext context) => getResponsiveFontSize(context, 20);
  
  /// 标题2
  static double heading(BuildContext context) => getResponsiveFontSize(context, 18);
  
  /// 正文
  static double body(BuildContext context) => getResponsiveFontSize(context, 16);
  
  /// 小正文
  static double bodySmall(BuildContext context) => getResponsiveFontSize(context, 14);
  
  /// 说明文字
  static double caption(BuildContext context) => getResponsiveFontSize(context, 12);
  
  /// 小说明文字
  static double captionSmall(BuildContext context) => getResponsiveFontSize(context, 11);
  
  // 预定义的分段式字体大小
  
  /// 页面标题（分段式）
  static double pageTitle(BuildContext context) => getSegmentedFontSize(
    context,
    mobile: 20,
    tablet: 24,
    desktop: 28,
    ultra: 32,
  );
  
  /// 卡片标题（分段式）
  static double cardTitle(BuildContext context) => getSegmentedFontSize(
    context,
    mobile: 14,
    tablet: 15,
    desktop: 16,
    ultra: 18,
  );
  
  /// 按钮文字（分段式）
  static double button(BuildContext context) => getSegmentedFontSize(
    context,
    mobile: 13,
    tablet: 14,
    desktop: 14,
    ultra: 15,
  );
  
  /// 输入框文字（分段式）
  static double input(BuildContext context) => getSegmentedFontSize(
    context,
    mobile: 13,
    tablet: 14,
    desktop: 14,
    ultra: 15,
  );
}

/// 响应式间距工具类
class ResponsiveSpacing {
  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    const baseWidth = 1920.0;
    double scaleFactor = (width / baseWidth).clamp(0.7, 1.3);
    return baseSpacing * scaleFactor;
  }
  
  /// 超小间距
  static double xxs(BuildContext context) => getResponsiveSpacing(context, 4);
  
  /// 小间距
  static double xs(BuildContext context) => getResponsiveSpacing(context, 8);
  
  /// 小间距
  static double sm(BuildContext context) => getResponsiveSpacing(context, 12);
  
  /// 中等间距
  static double md(BuildContext context) => getResponsiveSpacing(context, 16);
  
  /// 大间距
  static double lg(BuildContext context) => getResponsiveSpacing(context, 24);
  
  /// 超大间距
  static double xl(BuildContext context) => getResponsiveSpacing(context, 32);
  
  /// 巨大间距
  static double xxl(BuildContext context) => getResponsiveSpacing(context, 48);
}

/// 响应式图标大小工具类
class ResponsiveIconSize {
  static double getResponsiveIconSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    const baseWidth = 1920.0;
    double scaleFactor = (width / baseWidth).clamp(0.7, 1.3);
    return baseSize * scaleFactor;
  }
  
  /// 小图标
  static double small(BuildContext context) => getResponsiveIconSize(context, 16);
  
  /// 中等图标
  static double medium(BuildContext context) => getResponsiveIconSize(context, 20);
  
  /// 大图标
  static double large(BuildContext context) => getResponsiveIconSize(context, 24);
  
  /// 超大图标
  static double extraLarge(BuildContext context) => getResponsiveIconSize(context, 32);
}

