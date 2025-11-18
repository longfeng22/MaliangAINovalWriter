/// 引用模型
/// Reference model

import 'package:equatable/equatable.dart';
import '../config/constants.dart';

/// 引用模型
/// Reference model
class Reference extends Equatable {
  final String id;
  final String type;    // 'setting' | 'chapter' | 'outline' | 'fragment'
  final int number;
  final String title;
  
  const Reference({
    required this.id,
    required this.type,
    required this.number,
    required this.title,
  });
  
  @override
  List<Object?> get props => [id, type, number, title];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'number': number,
    'title': title,
  };
  
  factory Reference.fromJson(Map<String, dynamic> json) => Reference(
    id: json['id'] as String,
    type: json['type'] as String,
    number: json['number'] as int,
    title: json['title'] as String,
  );
  
  Reference copyWith({
    String? id,
    String? type,
    int? number,
    String? title,
  }) => Reference(
    id: id ?? this.id,
    type: type ?? this.type,
    number: number ?? this.number,
    title: title ?? this.title,
  );
  
  /// 是否是设定引用
  bool get isSetting => type == CitationType.setting;
  
  /// 是否是章节引用
  bool get isChapter => type == CitationType.chapter;
  
  /// 是否是大纲引用
  bool get isOutline => type == CitationType.outline;
  
  /// 是否是片段引用
  bool get isFragment => type == CitationType.fragment;
  
  /// 显示文本
  String get displayText {
    String typeText;
    switch (type) {
      case CitationType.setting:
        typeText = '设定';
        break;
      case CitationType.chapter:
        typeText = '章节';
        break;
      case CitationType.outline:
        typeText = '大纲';
        break;
      case CitationType.fragment:
        typeText = '片段';
        break;
      default:
        typeText = type;
    }
    return '$typeText $number: $title';
  }
}





