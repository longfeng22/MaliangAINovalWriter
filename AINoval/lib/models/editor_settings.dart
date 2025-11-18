import 'package:flutter/material.dart';

/// 编辑器设置模型
/// 包含编辑器的所有可定制化选项
class EditorSettings {
  const EditorSettings({
    // 字体相关设置 - 优化1080p显示
    this.fontSize = 14.0, // 从16.0降低到14.0，适配1080p屏幕
    this.fontFamily = 'Noto Sans SC', // 🚀 默认中文友好字体，避免首帧方块/乱码
    this.fontWeight = FontWeight.normal,
    this.lineSpacing = 1.4, // 从1.5降低到1.4，减少行间距
    this.letterSpacing = 0.0, // 🚀 中文写作建议稍微调整字符间距
    
    // 间距和布局设置
    this.paddingHorizontal = 16.0,
    this.paddingVertical = 12.0,
    this.paragraphSpacing = 8.0,
    this.indentSize = 32.0,
    
    // 编辑器行为设置
    this.autoSaveEnabled = true,
    this.autoSaveIntervalMinutes = 5,
    this.spellCheckEnabled = true,
    this.showWordCount = true,
    this.showLineNumbers = false,
    this.highlightActiveLine = true,
    
    // 主题和外观设置
    this.darkModeEnabled = false,
    this.showMiniMap = false,
    this.smoothScrolling = true,
    this.fadeInAnimation = true,

    // 主题变体
    this.themeVariant = 'monochrome',
    
    // 编辑器宽度和高度设置
    this.maxLineWidth = 1500.0,
    this.minEditorHeight = 1200.0,
    this.useTypewriterMode = false,
    
    // 文本选择和光标设置
    this.cursorBlinkRate = 1.0,
    this.selectionHighlightColor = 0xFF2196F3,
    this.enableVimMode = false,
    
    // 导出和打印设置
    this.defaultExportFormat = 'markdown',
    this.includeMetadata = true,
  });

  // 字体相关设置
  final double fontSize;
  final String fontFamily;
  final FontWeight fontWeight;
  final double lineSpacing;
  final double letterSpacing;
  
  // 间距和布局设置
  final double paddingHorizontal;
  final double paddingVertical;
  final double paragraphSpacing;
  final double indentSize;
  
  // 编辑器行为设置
  final bool autoSaveEnabled;
  final int autoSaveIntervalMinutes;
  final bool spellCheckEnabled;
  final bool showWordCount;
  final bool showLineNumbers;
  final bool highlightActiveLine;
  
  // 主题和外观设置
  final bool darkModeEnabled;
  final bool showMiniMap;
  final bool smoothScrolling;
  final bool fadeInAnimation;
  // 主题变体
  final String themeVariant;
  
  // 编辑器宽度和高度设置
  final double maxLineWidth;
  final double minEditorHeight;
  final bool useTypewriterMode;
  
  // 文本选择和光标设置
  final double cursorBlinkRate;
  final int selectionHighlightColor;
  final bool enableVimMode;
  
  // 导出和打印设置
  final String defaultExportFormat;
  final bool includeMetadata;

  /// 复制并修改设置
  EditorSettings copyWith({
    double? fontSize,
    String? fontFamily,
    FontWeight? fontWeight,
    double? lineSpacing,
    double? letterSpacing,
    double? paddingHorizontal,
    double? paddingVertical,
    double? paragraphSpacing,
    double? indentSize,
    bool? autoSaveEnabled,
    int? autoSaveIntervalMinutes,
    bool? spellCheckEnabled,
    bool? showWordCount,
    bool? showLineNumbers,
    bool? highlightActiveLine,
    bool? darkModeEnabled,
    bool? showMiniMap,
    bool? smoothScrolling,
    bool? fadeInAnimation,
    String? themeVariant,
    double? maxLineWidth,
    double? minEditorHeight,
    bool? useTypewriterMode,
    double? cursorBlinkRate,
    int? selectionHighlightColor,
    bool? enableVimMode,
    String? defaultExportFormat,
    bool? includeMetadata,
  }) {
    return EditorSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paddingHorizontal: paddingHorizontal ?? this.paddingHorizontal,
      paddingVertical: paddingVertical ?? this.paddingVertical,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      indentSize: indentSize ?? this.indentSize,
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      autoSaveIntervalMinutes: autoSaveIntervalMinutes ?? this.autoSaveIntervalMinutes,
      spellCheckEnabled: spellCheckEnabled ?? this.spellCheckEnabled,
      showWordCount: showWordCount ?? this.showWordCount,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      highlightActiveLine: highlightActiveLine ?? this.highlightActiveLine,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      showMiniMap: showMiniMap ?? this.showMiniMap,
      smoothScrolling: smoothScrolling ?? this.smoothScrolling,
      fadeInAnimation: fadeInAnimation ?? this.fadeInAnimation,
      themeVariant: themeVariant ?? this.themeVariant,
      maxLineWidth: maxLineWidth ?? this.maxLineWidth,
      minEditorHeight: minEditorHeight ?? this.minEditorHeight,
      useTypewriterMode: useTypewriterMode ?? this.useTypewriterMode,
      cursorBlinkRate: cursorBlinkRate ?? this.cursorBlinkRate,
      selectionHighlightColor: selectionHighlightColor ?? this.selectionHighlightColor,
      enableVimMode: enableVimMode ?? this.enableVimMode,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      includeMetadata: includeMetadata ?? this.includeMetadata,
    );
  }

  /// 转换为Map（用于持久化存储）
  Map<String, dynamic> toMap() {
    return {
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight.index,
      'lineSpacing': lineSpacing,
      'letterSpacing': letterSpacing,
      'paddingHorizontal': paddingHorizontal,
      'paddingVertical': paddingVertical,
      'paragraphSpacing': paragraphSpacing,
      'indentSize': indentSize,
      'autoSaveEnabled': autoSaveEnabled,
      'autoSaveIntervalMinutes': autoSaveIntervalMinutes,
      'spellCheckEnabled': spellCheckEnabled,
      'showWordCount': showWordCount,
      'showLineNumbers': showLineNumbers,
      'highlightActiveLine': highlightActiveLine,
      'darkModeEnabled': darkModeEnabled,
      'showMiniMap': showMiniMap,
      'smoothScrolling': smoothScrolling,
      'fadeInAnimation': fadeInAnimation,
      'themeVariant': themeVariant,
      'maxLineWidth': maxLineWidth,
      'minEditorHeight': minEditorHeight,
      'useTypewriterMode': useTypewriterMode,
      'cursorBlinkRate': cursorBlinkRate,
      'selectionHighlightColor': selectionHighlightColor,
      'enableVimMode': enableVimMode,
      'defaultExportFormat': defaultExportFormat,
      'includeMetadata': includeMetadata,
    };
  }

  /// 从Map创建（用于持久化恢复）
  factory EditorSettings.fromMap(Map<String, dynamic> map) {
    // 🚀 修复：安全地转换fontWeight，处理String和int类型
    int fontWeightIndex = 3; // 默认值 FontWeight.normal
    if (map['fontWeight'] != null) {
      if (map['fontWeight'] is int) {
        fontWeightIndex = map['fontWeight'];
      } else if (map['fontWeight'] is String) {
        fontWeightIndex = int.tryParse(map['fontWeight']) ?? 3;
      }
    }
    
    // 🚀 修复：安全地转换selectionHighlightColor，处理String和int类型
    int selectionColor = 0xFF2196F3; // 默认蓝色
    if (map['selectionHighlightColor'] != null) {
      if (map['selectionHighlightColor'] is int) {
        selectionColor = map['selectionHighlightColor'];
      } else if (map['selectionHighlightColor'] is String) {
        selectionColor = int.tryParse(map['selectionHighlightColor']) ?? 0xFF2196F3;
      }
    }
    
    // 🚀 修复：安全地转换autoSaveIntervalMinutes，处理String和int类型
    int autoSaveInterval = 5; // 默认值
    if (map['autoSaveIntervalMinutes'] != null) {
      if (map['autoSaveIntervalMinutes'] is int) {
        autoSaveInterval = map['autoSaveIntervalMinutes'];
      } else if (map['autoSaveIntervalMinutes'] is String) {
        autoSaveInterval = int.tryParse(map['autoSaveIntervalMinutes']) ?? 5;
      }
    }
    
    return EditorSettings(
      fontSize: map['fontSize']?.toDouble() ?? 16.0,
      fontFamily: map['fontFamily'] ?? 'Noto Sans SC',
      fontWeight: FontWeight.values[fontWeightIndex.clamp(0, FontWeight.values.length - 1)],
      lineSpacing: map['lineSpacing']?.toDouble() ?? 1.5,
      letterSpacing: map['letterSpacing']?.toDouble() ?? 0.0,
      paddingHorizontal: map['paddingHorizontal']?.toDouble() ?? 16.0,
      paddingVertical: map['paddingVertical']?.toDouble() ?? 12.0,
      paragraphSpacing: map['paragraphSpacing']?.toDouble() ?? 8.0,
      indentSize: map['indentSize']?.toDouble() ?? 32.0,
      autoSaveEnabled: map['autoSaveEnabled'] ?? true,
      autoSaveIntervalMinutes: autoSaveInterval,
      spellCheckEnabled: map['spellCheckEnabled'] ?? true,
      showWordCount: map['showWordCount'] ?? true,
      showLineNumbers: map['showLineNumbers'] ?? false,
      highlightActiveLine: map['highlightActiveLine'] ?? true,
      darkModeEnabled: map['darkModeEnabled'] ?? false,
      showMiniMap: map['showMiniMap'] ?? false,
      smoothScrolling: map['smoothScrolling'] ?? true,
      fadeInAnimation: map['fadeInAnimation'] ?? true,
      themeVariant: (map['themeVariant'] as String?) ?? 'monochrome',
      maxLineWidth: map['maxLineWidth']?.toDouble() ?? 1500.0,
      minEditorHeight: map['minEditorHeight']?.toDouble() ?? 1200.0,
      useTypewriterMode: map['useTypewriterMode'] ?? false,
      cursorBlinkRate: map['cursorBlinkRate']?.toDouble() ?? 1.0,
      selectionHighlightColor: selectionColor,
      enableVimMode: map['enableVimMode'] ?? false,
      defaultExportFormat: map['defaultExportFormat'] ?? 'markdown',
      includeMetadata: map['includeMetadata'] ?? true,
    );
  }

  /// 获取可用的字体列表
  static List<String> get availableFontFamilies => [
    // 本地字体 - 已在pubspec.yaml中声明
    'Noto Sans SC', // Google Noto 简体中文字体（默认）
    'Roboto', // Google Roboto英文字体
    'Roboto Condensed', // Roboto紧凑版
    'Roboto SemiCondensed', // Roboto半紧凑版
    
    // 系统字体
    'serif', // 中文友好的衬线字体
    'sans-serif', // 中文友好的无衬线字体
    'monospace', // 等宽字体
    
    // 平台相关字体（作为回退选项）
    'PingFang SC', // 苹果中文字体
    'Microsoft YaHei', // 微软雅黑
    'SimHei', // 黑体
    'SimSun', // 宋体
    'Helvetica', // macOS/iOS
    'Times New Roman', // Windows
    'Courier New', // 跨平台等宽
    'Georgia', // 跨平台衬线
    'Verdana', // 跨平台无衬线
    'Arial', // 跨平台无衬线
  ];

  /// 获取可用的字体粗细选项
  static List<FontWeight> get availableFontWeights => [
    FontWeight.w300,
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
  ];

  /// 获取可用的导出格式
  static List<String> get availableExportFormats => [
    'markdown',
    'docx',
    'pdf',
    'txt',
    'html',
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is EditorSettings &&
        other.fontSize == fontSize &&
        other.fontFamily == fontFamily &&
        other.fontWeight == fontWeight &&
        other.lineSpacing == lineSpacing &&
        other.letterSpacing == letterSpacing &&
        other.paddingHorizontal == paddingHorizontal &&
        other.paddingVertical == paddingVertical &&
        other.paragraphSpacing == paragraphSpacing &&
        other.indentSize == indentSize &&
        other.autoSaveEnabled == autoSaveEnabled &&
        other.autoSaveIntervalMinutes == autoSaveIntervalMinutes &&
        other.spellCheckEnabled == spellCheckEnabled &&
        other.showWordCount == showWordCount &&
        other.showLineNumbers == showLineNumbers &&
        other.highlightActiveLine == highlightActiveLine &&
        other.darkModeEnabled == darkModeEnabled &&
        other.showMiniMap == showMiniMap &&
        other.smoothScrolling == smoothScrolling &&
        other.fadeInAnimation == fadeInAnimation &&
        other.themeVariant == themeVariant &&
        other.maxLineWidth == maxLineWidth &&
        other.minEditorHeight == minEditorHeight &&
        other.useTypewriterMode == useTypewriterMode &&
        other.cursorBlinkRate == cursorBlinkRate &&
        other.selectionHighlightColor == selectionHighlightColor &&
        other.enableVimMode == enableVimMode &&
        other.defaultExportFormat == defaultExportFormat &&
        other.includeMetadata == includeMetadata;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      fontSize,
      fontFamily,
      fontWeight,
      lineSpacing,
      letterSpacing,
      paddingHorizontal,
      paddingVertical,
      paragraphSpacing,
      indentSize,
      autoSaveEnabled,
      autoSaveIntervalMinutes,
      spellCheckEnabled,
      showWordCount,
      showLineNumbers,
      highlightActiveLine,
      darkModeEnabled,
      showMiniMap,
      smoothScrolling,
      fadeInAnimation,
      themeVariant,
      maxLineWidth,
      minEditorHeight,
      useTypewriterMode,
      cursorBlinkRate,
      selectionHighlightColor,
      enableVimMode,
      defaultExportFormat,
      includeMetadata,
    ]);
  }

  /// 🚀 新增：转换为JSON（用于API调用）
  Map<String, dynamic> toJson() {
    return toMap();
  }

  /// 🚀 新增：从JSON创建（用于API响应）
  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    return EditorSettings.fromMap(json);
  }
} 