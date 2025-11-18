import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/setting_reference_processor.dart';

/// 🎯 简化版设定引用悬停状态管理器
/// 使用TextStyle.backgroundColor实现悬停效果，比复杂的位置计算更简单高效
class SettingReferenceHoverManager extends ChangeNotifier {
  static final SettingReferenceHoverManager _instance = SettingReferenceHoverManager._internal();
  factory SettingReferenceHoverManager() => _instance;
  SettingReferenceHoverManager._internal();

  String? _hoveredSettingId;
  String? get hoveredSettingId => _hoveredSettingId;

  /// 设置悬停的设定引用ID
  void setHoveredSetting(String? settingId) {
    if (_hoveredSettingId != settingId) {
      _hoveredSettingId = settingId;
      notifyListeners();
      AppLogger.d('SettingReferenceHoverManager', 
          _hoveredSettingId != null 
              ? '🖱️ 设定引用悬停开始: $_hoveredSettingId' 
              : '🖱️ 设定引用悬停结束');
    }
  }

  /// 清除悬停状态
  void clearHover() {
    setHoveredSetting(null);
  }
}

/// 设定引用交互混入 - 为 SceneEditor 提供设定引用交互功能
mixin SettingReferenceInteractionMixin {
  /// 🎯 获取支持悬停效果的设定引用样式构建器
  /// 这是最核心的方法，直接在customStyleBuilder中处理悬停效果
  static TextStyle Function(Attribute) getCustomStyleBuilderWithHover({
    required String? hoveredSettingId,
  }) {
    return (Attribute attribute) {
      // 处理设定引用的样式标记
      if (attribute.key == SettingReferenceProcessor.settingStyleAttr && 
          attribute.value == 'reference') {
        
        // 🎯 关键：使用TextStyle.backgroundColor实现悬停效果（常驻浅橙，悬停加深）
        return const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Colors.black, // 🎯 改为纯黑色，提升可读性
          decorationThickness: 3.0,
          // 🎯 常驻浅橙背景（~10%不透明度）
          backgroundColor: Color.fromARGB(241, 251, 247, 0),
        ).copyWith(
          // 🎯 悬停时加深为更明显的橙色（~20%不透明度）
          backgroundColor: hoveredSettingId != null ? const Color.fromARGB(241, 251, 247, 0) : null,
        );
      }
      
      return const TextStyle();
    };
  }

  /// 获取设定引用的自定义手势识别器构建器
  static GestureRecognizer? Function(Attribute, Node) getCustomRecognizerBuilder({
    required Function(String settingId)? onSettingReferenceClicked,
    required Function(String settingId)? onSettingReferenceHovered,
    required VoidCallback? onSettingReferenceHoverEnd,
  }) {
    return (Attribute attribute, Node node) {
      
      // 检查是否是设定引用属性
      if (attribute.key == SettingReferenceProcessor.settingReferenceAttr ) {
        final settingId = attribute.value as String?;
        if (settingId != null && settingId.isNotEmpty) {
          //AppLogger.d('SettingReferenceInteraction', '🎯 创建设定引用手势识别器: $settingId');
          
          // 创建支持点击和悬停的手势识别器
          final tapRecognizer = TapGestureRecognizer()
            ..onTap = () {
              AppLogger.i('SettingReferenceInteraction', '🖱️ 设定引用被点击: $settingId');
              onSettingReferenceClicked?.call(settingId);
            };
          
          return tapRecognizer;
        }
      }
      
      return null;
    };
  }

  /// 获取设定引用的自定义样式构建器（基础版本）
  static TextStyle Function(Attribute) getCustomStyleBuilder() {
    return (Attribute attribute) {
      // 处理设定引用的样式标记
      if (attribute.key == SettingReferenceProcessor.settingStyleAttr && 
          attribute.value == 'reference') {
        return const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Colors.black, // 🎯 改为纯黑色，提升可读性
          decorationThickness: 2.0,
          // 🎯 常驻浅橙背景（~10%不透明度）
          backgroundColor: Color(0x1AFFA500),
        );
      }
      
      return const TextStyle();
    };
  }

}

/// 🎯 设定引用鼠标悬停检测器Widget
/// 使用MouseRegion包装编辑器，检测鼠标悬停并更新状态
class SettingReferenceMouseDetector extends StatefulWidget {
  final Widget child;
  final QuillController controller;
  final String? novelId;

  const SettingReferenceMouseDetector({
    Key? key,
    required this.child,
    required this.controller,
    this.novelId,
  }) : super(key: key);

  @override
  State<SettingReferenceMouseDetector> createState() => _SettingReferenceMouseDetectorState();
}

class _SettingReferenceMouseDetectorState extends State<SettingReferenceMouseDetector> {
  final _hoverManager = SettingReferenceHoverManager();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _handleMouseMove,
      onExit: (_) => _hoverManager.clearHover(),
      child: widget.child,
    );
  }

  void _handleMouseMove(PointerHoverEvent event) {
    // 🎯 这里可以实现基于鼠标位置的设定引用检测
    // 为了简化，暂时先处理基本的悬停状态
    try {
      // TODO: 实现更精确的位置检测逻辑
      // 目前先简化处理，后续可以根据需要优化
      
      // 暂时用一个简单的方式来模拟检测
      // 实际项目中可能需要更复杂的位置计算
      
      AppLogger.v('SettingReferenceMouseDetector', '🖱️ 鼠标移动: ${event.localPosition}');
      
    } catch (e) {
      AppLogger.w('SettingReferenceMouseDetector', '检测设定引用悬停失败', e);
    }
  }
}

 