/// 文本块组件
/// Text block widget

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../utils/responsive_utils.dart';

/// 文本块Widget
/// Text block widget
/// 
/// 支持Markdown格式、响应式文字大小
/// Supports Markdown format and responsive text size
class TextBlockWidget extends StatelessWidget {
  final TextBlock block;
  final bool isDark;
  
  const TextBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    
    // 响应式字体大小
    final fontSize = ResponsiveUtils.getFontSize(
      context,
      mobile: 14.0,
      tablet: 15.0,
      desktop: 16.0,
    );
    
    // 响应式行高
    final lineHeight = screenType == ScreenType.mobile ? 1.5 : 1.6;
    
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing,
      ),
      child: _buildContent(context, fontSize, lineHeight),
    );
  }
  
  Widget _buildContent(BuildContext context, double fontSize, double lineHeight) {
    // 检查是否包含Markdown语法
    if (_hasMarkdownSyntax(block.content)) {
      return _buildMarkdown(context, fontSize, lineHeight);
    } else {
      return _buildPlainText(context, fontSize, lineHeight);
    }
  }
  
  /// 构建Markdown内容
  Widget _buildMarkdown(BuildContext context, double fontSize, double lineHeight) {
    return MarkdownBody(
      data: block.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontSize: fontSize,
          height: lineHeight,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightForeground,
            AgentChatThemeConfig.darkForeground,
            isDark,
          ),
        ),
        code: TextStyle(
          fontFamily: AgentChatThemeConfig.fontMono,
          fontSize: fontSize * 0.9,
          backgroundColor: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightMuted,
            AgentChatThemeConfig.darkMuted,
            isDark,
          ),
        ),
        codeblockDecoration: BoxDecoration(
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightMuted,
            AgentChatThemeConfig.darkMuted,
            isDark,
          ),
          borderRadius: BorderRadius.circular(
            ResponsiveUtils.getBorderRadius(context) * 0.5,
          ),
        ),
        blockquote: TextStyle(
          fontSize: fontSize,
          height: lineHeight,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightMutedForeground,
            AgentChatThemeConfig.darkMutedForeground,
            isDark,
          ),
          fontStyle: FontStyle.italic,
        ),
        h1: TextStyle(
          fontSize: fontSize * 1.8,
          fontWeight: FontWeight.bold,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightForeground,
            AgentChatThemeConfig.darkForeground,
            isDark,
          ),
        ),
        h2: TextStyle(
          fontSize: fontSize * 1.5,
          fontWeight: FontWeight.bold,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightForeground,
            AgentChatThemeConfig.darkForeground,
            isDark,
          ),
        ),
        h3: TextStyle(
          fontSize: fontSize * 1.3,
          fontWeight: FontWeight.w600,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightForeground,
            AgentChatThemeConfig.darkForeground,
            isDark,
          ),
        ),
        listBullet: TextStyle(
          fontSize: fontSize,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightPrimary,
            AgentChatThemeConfig.darkPrimary,
            isDark,
          ),
        ),
        a: TextStyle(
          fontSize: fontSize,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightPrimary,
            AgentChatThemeConfig.darkPrimary,
            isDark,
          ),
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
  
  /// 构建纯文本内容
  Widget _buildPlainText(BuildContext context, double fontSize, double lineHeight) {
    return SelectableText(
      block.content,
      style: TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightForeground,
          AgentChatThemeConfig.darkForeground,
          isDark,
        ),
      ),
    );
  }
  
  /// 检查是否包含Markdown语法
  /// Check if contains Markdown syntax
  bool _hasMarkdownSyntax(String text) {
    // 常见Markdown语法检测
    final markdownPatterns = [
      RegExp(r'^\#{1,6}\s'), // 标题 # ## ###
      RegExp(r'\*\*.+\*\*'), // 加粗 **text**
      RegExp(r'\*.+\*'), // 斜体 *text*
      RegExp(r'\[.+\]\(.+\)'), // 链接 [text](url)
      RegExp(r'^[\*\-\+]\s'), // 列表 * - +
      RegExp(r'^\d+\.\s'), // 有序列表 1. 2.
      RegExp(r'```'), // 代码块 ```
      RegExp(r'`[^`]+`'), // 行内代码 `code`
      RegExp(r'^>\s'), // 引用 >
    ];
    
    return markdownPatterns.any((pattern) => pattern.hasMatch(text));
  }
}





