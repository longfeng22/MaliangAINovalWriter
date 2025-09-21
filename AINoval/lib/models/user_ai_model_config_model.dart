import 'package:meta/meta.dart'; // For @immutable
import '../utils/date_time_parser.dart'; // Import the parser
import 'package:equatable/equatable.dart'; // Import Equatable for Equatable mixin

/// 用户 AI 模型配置模型 (对应后端的 UserAIModelConfigResponse)
@immutable // Good practice for value objects
class UserAIModelConfigModel extends Equatable {
  final String id;
  final String userId;
  final String provider;
  final String modelName;
  final String alias;
  final String apiEndpoint;
  final bool isValidated;
  final bool isDefault;
  final bool isToolDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? apiKey; // 添加apiKey字段，存储解密后的API密钥
  // --- Enriched fields from backend ---
  final double? inputPricePerThousandTokens;
  final double? outputPricePerThousandTokens;
  final double? unifiedPricePerThousandTokens;
  final int? maxContextTokens;
  final String? modelDescription;
  final Map<String, dynamic>? properties;

  /// 获取模型名称，用于显示
  String get name => (alias.isNotEmpty && alias != modelName) ? alias : modelName;

  const UserAIModelConfigModel({
    required this.id,
    required this.userId,
    required this.provider,
    required this.modelName,
    required this.alias,
    required this.apiEndpoint,
    required this.isValidated,
    required this.isDefault,
    required this.isToolDefault,
    required this.createdAt,
    required this.updatedAt,
    this.apiKey, // 添加apiKey字段，可为空
    this.inputPricePerThousandTokens,
    this.outputPricePerThousandTokens,
    this.unifiedPricePerThousandTokens,
    this.maxContextTokens,
    this.modelDescription,
    this.properties,
  });

  // 空实例，用于默认值
  factory UserAIModelConfigModel.empty() {
    return UserAIModelConfigModel(
      id: '',
      userId: '',
      provider: '',
      modelName: '',
      alias: '',
      apiEndpoint: '',
      isValidated: false,
      isDefault: false,
      isToolDefault: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      apiKey: null, // 默认为null
    );
  }

  // 从JSON转换方法
  factory UserAIModelConfigModel.fromJson(Map<String, dynamic> json) {
    // Helper to safely get string, providing a default if null or wrong type
    String safeString(String key, [String defaultValue = '']) {
      return json[key] is String ? json[key] as String : defaultValue;
    }

    // Helper to safely get bool, providing a default if null or wrong type
    bool safeBool(String key, [bool defaultValue = false]) {
      return json[key] is bool ? json[key] as bool : defaultValue;
    }

    return UserAIModelConfigModel(
      id: safeString('id'), // Assuming 'id' is the key from backend
      userId: safeString('userId'),
      provider: safeString('provider'),
      modelName: safeString('modelName'),
      alias: safeString('alias'), // 使用safeString确保null安全
      apiEndpoint: safeString('apiEndpoint'), // 修复：使用safeString处理可能为null的apiEndpoint
      isValidated: safeBool('isValidated'),
      isDefault: safeBool('isDefault'),
      isToolDefault: safeBool('isToolDefault'),
      createdAt: parseBackendDateTime(json['createdAt']), // Use the parser
      updatedAt: parseBackendDateTime(json['updatedAt']), // Use the parser
      apiKey: json['apiKey'] as String?, // 添加API密钥，可为空
      inputPricePerThousandTokens: _toDouble(json['inputPricePerThousandTokens']) ?? _toDouble(_fromPricing(json, 'input')),
      outputPricePerThousandTokens: _toDouble(json['outputPricePerThousandTokens']) ?? _toDouble(_fromPricing(json, 'output')),
      unifiedPricePerThousandTokens: _toDouble(json['unifiedPricePerThousandTokens']) ?? _toDouble(_fromPricing(json, 'unified')),
      maxContextTokens: json['maxContextTokens'] is int ? json['maxContextTokens'] as int : null,
      modelDescription: json['description'] as String? ?? json['modelDescription'] as String?,
      properties: json['properties'] is Map<String, dynamic> ? json['properties'] as Map<String, dynamic> : null,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static dynamic _fromPricing(Map<String, dynamic> json, String key) {
    final p = json['pricing'];
    if (p is Map<String, dynamic>) return p[key];
    return null;
  }

  // 转换为JSON方法
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'provider': provider,
      'modelName': modelName,
      'alias': alias,
      'apiEndpoint': apiEndpoint,
      'isValidated': isValidated,
      'isDefault': isDefault,
      'isToolDefault': isToolDefault,
      'createdAt': createdAt.toIso8601String(), // Standard format for JSON
      'updatedAt': updatedAt.toIso8601String(), // Standard format for JSON
      'apiKey': apiKey, // 包含API密钥
      'inputPricePerThousandTokens': inputPricePerThousandTokens,
      'outputPricePerThousandTokens': outputPricePerThousandTokens,
      'unifiedPricePerThousandTokens': unifiedPricePerThousandTokens,
      'maxContextTokens': maxContextTokens,
      'description': modelDescription,
      if (properties != null) 'properties': properties,
    };
  }

  // 复制方法
  UserAIModelConfigModel copyWith({
    String? id,
    String? userId,
    String? provider,
    String? modelName,
    String? alias,
    String? apiEndpoint,
    bool? isValidated,
    bool? isDefault,
    bool? isToolDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? apiKey, // 添加apiKey参数
    double? inputPricePerThousandTokens,
    double? outputPricePerThousandTokens,
    double? unifiedPricePerThousandTokens,
    int? maxContextTokens,
    String? modelDescription,
    Map<String, dynamic>? properties,
  }) {
    return UserAIModelConfigModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      provider: provider ?? this.provider,
      modelName: modelName ?? this.modelName,
      alias: alias ?? this.alias,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      isValidated: isValidated ?? this.isValidated,
      isDefault: isDefault ?? this.isDefault,
      isToolDefault: isToolDefault ?? this.isToolDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      apiKey: apiKey ?? this.apiKey, // 复制apiKey
      inputPricePerThousandTokens: inputPricePerThousandTokens ?? this.inputPricePerThousandTokens,
      outputPricePerThousandTokens: outputPricePerThousandTokens ?? this.outputPricePerThousandTokens,
      unifiedPricePerThousandTokens: unifiedPricePerThousandTokens ?? this.unifiedPricePerThousandTokens,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      modelDescription: modelDescription ?? this.modelDescription,
      properties: properties ?? this.properties,
    );
  }

  // --- Value Equality ---

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserAIModelConfigModel &&
        other.id == id &&
        other.userId == userId &&
        other.provider == provider &&
        other.modelName == modelName &&
        other.alias == alias &&
        other.apiEndpoint == apiEndpoint &&
        other.isValidated == isValidated &&
        other.isDefault == isDefault &&
        other.isToolDefault == isToolDefault &&
        other.createdAt == createdAt &&
        other.apiKey == apiKey && // 比较apiKey
        other.updatedAt == updatedAt &&
        other.inputPricePerThousandTokens == inputPricePerThousandTokens &&
        other.outputPricePerThousandTokens == outputPricePerThousandTokens &&
        other.unifiedPricePerThousandTokens == unifiedPricePerThousandTokens &&
        other.maxContextTokens == maxContextTokens &&
        other.modelDescription == modelDescription &&
        _mapEquals(other.properties, properties);
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        provider.hashCode ^
        modelName.hashCode ^
        alias.hashCode ^
        apiEndpoint.hashCode ^
        isValidated.hashCode ^
        isDefault.hashCode ^
        isToolDefault.hashCode ^
        createdAt.hashCode ^
        apiKey.hashCode ^ // 计算apiKey的哈希值
        updatedAt.hashCode ^
        (inputPricePerThousandTokens?.hashCode ?? 0) ^
        (outputPricePerThousandTokens?.hashCode ?? 0) ^
        (unifiedPricePerThousandTokens?.hashCode ?? 0) ^
        (maxContextTokens?.hashCode ?? 0) ^
        (modelDescription?.hashCode ?? 0) ^
        _mapHash(properties);
  }

  @override
  String toString() {
    return 'UserAIModelConfigModel(id: $id, userId: $userId, provider: $provider, modelName: $modelName, alias: $alias, apiEndpoint: $apiEndpoint, isValidated: $isValidated, isDefault: $isDefault, createdAt: $createdAt, updatedAt: $updatedAt, apiKey: ${apiKey != null ? '******' : 'null'})'; // 不显示完整apiKey
  }

  @override
  List<Object?> get props => [id, userId, provider, modelName, alias, apiEndpoint, isValidated, isDefault, isToolDefault, createdAt, updatedAt, apiKey, inputPricePerThousandTokens, outputPricePerThousandTokens, unifiedPricePerThousandTokens, maxContextTokens, modelDescription, properties]; // 添加扩展字段

  static bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  static int _mapHash(Map<String, dynamic>? m) {
    if (m == null) return 0;
    int h = 0;
    m.forEach((k, v) { h = h ^ k.hashCode ^ (v?.hashCode ?? 0); });
    return h;
  }
}
