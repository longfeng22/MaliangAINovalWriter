/// 策略模板信息
/// 
/// 对应后端 ISettingGenerationService.StrategyTemplateInfo DTO
/// 
/// 用于替代旧的 StrategyInfo，与新的后端API完全对齐
class StrategyTemplateInfo {
  /// 策略模板ID（promptTemplateId）
  final String promptTemplateId;
  
  /// 策略名称
  final String name;
  
  /// 策略描述
  final String description;
  
  /// 分类列表
  final List<String> categories;
  
  /// 标签列表
  final List<String> tags;
  
  /// 预期根节点数量
  final int? expectedRootNodes;
  
  /// 最大深度
  final int? maxDepth;
  
  /// 难度等级
  final int? difficultyLevel;
  
  /// 是否启用
  final bool enabled;

  const StrategyTemplateInfo({
    required this.promptTemplateId,
    required this.name,
    required this.description,
    this.categories = const [],
    this.tags = const [],
    this.expectedRootNodes,
    this.maxDepth,
    this.difficultyLevel,
    this.enabled = true,
  });

  factory StrategyTemplateInfo.fromJson(Map<String, dynamic> json) {
    // 安全解析：兼容后端返回的可空/不同命名/不同类型（string/number）
    final dynamic idRaw = json['promptTemplateId'] ?? json['templateId'] ?? json['id'];
    final String id = (idRaw == null) ? '' : idRaw.toString();

    final String name = (json['name'] ?? json['strategyName'] ?? '未命名').toString();
    final String description = (json['description'] ?? '').toString();

    List<String> _toStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
      return const [];
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return StrategyTemplateInfo(
      promptTemplateId: id,
      name: name,
      description: description,
      categories: _toStringList(json['categories']),
      tags: _toStringList(json['tags']),
      expectedRootNodes: _toInt(json['expectedRootNodes']),
      maxDepth: _toInt(json['maxDepth']),
      difficultyLevel: _toInt(json['difficultyLevel']),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'promptTemplateId': promptTemplateId,
    'name': name,
    'description': description,
    'categories': categories,
    'tags': tags,
    if (expectedRootNodes != null) 'expectedRootNodes': expectedRootNodes,
    if (maxDepth != null) 'maxDepth': maxDepth,
    if (difficultyLevel != null) 'difficultyLevel': difficultyLevel,
    'enabled': enabled,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrategyTemplateInfo &&
        other.promptTemplateId == promptTemplateId &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => promptTemplateId.hashCode ^ name.hashCode ^ description.hashCode;

  @override
  String toString() => 'StrategyTemplateInfo(promptTemplateId: $promptTemplateId, name: $name)';
}