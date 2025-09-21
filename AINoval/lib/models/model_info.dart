import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Represents detailed information about an AI model provided by the backend.
@immutable
class ModelInfo extends Equatable {
  final String id; // Usually the unique model identifier (e.g., "gpt-4o")
  final String name; // User-friendly name (might be the same as id or different)
  final String provider;
  final String? description;
  final int? maxTokens;
  // Pricing (per 1K tokens)
  final double? inputPricePerThousandTokens;
  final double? outputPricePerThousandTokens;
  // Additional properties/tags from backend (capability detector)
  final Map<String, dynamic>? properties;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    this.description,
    this.maxTokens,
    this.inputPricePerThousandTokens,
    this.outputPricePerThousandTokens,
    this.properties,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    double? _parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) {
        final s = v.trim();
        return double.tryParse(s);
      }
      return null;
    }

    double? inputPrice;
    double? outputPrice;

    // 兼容两种结构：pricing.{input,output} 或 顶层 inputPricePerThousandTokens/outputPricePerThousandTokens
    final pricing = json['pricing'];
    if (pricing is Map<String, dynamic>) {
      inputPrice = _parseNum(pricing['input']);
      outputPrice = _parseNum(pricing['output']);
    }
    inputPrice ??= _parseNum(json['inputPricePerThousandTokens']);
    outputPrice ??= _parseNum(json['outputPricePerThousandTokens']);

    Map<String, dynamic>? props;
    // 常见字段名：properties / additionalProperties / extra / meta
    for (final key in const ['properties', 'additionalProperties', 'extra', 'meta']) {
      final v = json[key];
      if (v is Map<String, dynamic>) {
        props = v;
        break;
      }
    }

    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '', // Fallback name to id
      provider: json['provider'] as String? ?? '',
      description: json['description'] as String?,
      maxTokens: json['maxTokens'] as int?,
      inputPricePerThousandTokens: inputPrice,
      outputPricePerThousandTokens: outputPrice,
      properties: props,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'description': description,
      'maxTokens': maxTokens,
      'inputPricePerThousandTokens': inputPricePerThousandTokens,
      'outputPricePerThousandTokens': outputPricePerThousandTokens,
      if (properties != null) 'properties': properties,
    };
  }

  @override
  List<Object?> get props => [id, name, provider, description, maxTokens, inputPricePerThousandTokens, outputPricePerThousandTokens, properties];

  // Helper: 获取标签（从 properties.tags）
  List<String> get tags {
    final p = properties;
    if (p == null) return const [];
    final t = p['tags'];
    if (t is List) {
      return t.whereType<String>().toList();
    }
    return const [];
  }

  // Helper: 布尔字符串/布尔兼容解析
  static bool _isTrue(dynamic v) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  bool get supportsPromptCaching => _isTrue(properties?['supports_prompt_caching']);
  bool get tieredPricing => _isTrue(properties?['tiered_pricing']);
} 