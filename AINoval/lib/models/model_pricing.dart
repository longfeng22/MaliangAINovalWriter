import 'package:json_annotation/json_annotation.dart';
import '../utils/date_time_parser.dart';

part 'model_pricing.g.dart';

/// 模型定价信息
@JsonSerializable()
class ModelPricing {
  /// ID
  final String? id;
  
  /// 提供商名称
  final String provider;
  
  /// 模型ID
  final String modelId;
  
  /// 模型名称
  final String? modelName;
  
  /// 输入token价格（每1000个token的美元价格）
  final double? inputPricePerThousandTokens;
  
  /// 输出token价格（每1000个token的美元价格）
  final double? outputPricePerThousandTokens;
  
  /// 统一价格（如果输入输出使用相同价格）
  final double? unifiedPricePerThousandTokens;
  
  /// 最大上下文token数
  final int? maxContextTokens;
  
  /// 是否支持流式输出
  final bool? supportsStreaming;
  
  /// 模型描述
  final String? description;
  
  /// 额外的定价信息
  final Map<String, double>? additionalPricing;
  
  /// 定价数据来源
  final String? source;
  
  /// 定价数据创建时间 - 使用自定义转换
  @JsonKey(fromJson: _parseDateTime, toJson: _dateTimeToJson)
  final DateTime? createdAt;
  
  /// 定价数据更新时间 - 使用自定义转换
  @JsonKey(fromJson: _parseDateTime, toJson: _dateTimeToJson)
  final DateTime? updatedAt;
  
  /// 定价数据版本号
  final int? version;
  
  /// 是否激活
  final bool? active;

  ModelPricing({
    this.id,
    required this.provider,
    required this.modelId,
    this.modelName,
    this.inputPricePerThousandTokens,
    this.outputPricePerThousandTokens,
    this.unifiedPricePerThousandTokens,
    this.maxContextTokens,
    this.supportsStreaming,
    this.description,
    this.additionalPricing,
    this.source,
    this.createdAt,
    this.updatedAt,
    this.version,
    this.active,
  });

  factory ModelPricing.fromJson(Map<String, dynamic> json) =>
      _$ModelPricingFromJson(json);

  Map<String, dynamic> toJson() => _$ModelPricingToJson(this);
  
  /// 自定义时间解析函数：使用date_time_parser.dart
  static DateTime? _parseDateTime(dynamic json) {
    if (json == null) return null;
    try {
      return parseBackendDateTime(json);
    } catch (e) {
      return null;
    }
  }

  /// 自定义时间序列化函数
  static String? _dateTimeToJson(DateTime? dateTime) {
    return dateTime?.toIso8601String();
  }
  
  /// 获取显示用的价格文本
  String get priceDisplayText {
    if (unifiedPricePerThousandTokens != null) {
      return '\$${unifiedPricePerThousandTokens!.toStringAsFixed(6)}/1K tokens';
    } else if (inputPricePerThousandTokens != null || outputPricePerThousandTokens != null) {
      final input = inputPricePerThousandTokens?.toStringAsFixed(6) ?? '0';
      final output = outputPricePerThousandTokens?.toStringAsFixed(6) ?? '0';
      return '输入: \$$input/1K, 输出: \$$output/1K';
    } else {
      return '暂无定价信息';
    }
  }
  
  /// 获取定价来源的显示文本
  String get sourceDisplayText {
    switch (source) {
      case 'OFFICIAL_API':
        return '官方API';
      case 'MANUAL':
        return '手动配置';
      case 'WEB_SCRAPING':
        return '网页爬取';
      case 'DEFAULT':
        return '默认配置';
      default:
        return source ?? '未知';
    }
  }
}

/// 定价检查结果
@JsonSerializable()
class PricingCheckResult {
  /// 是否存在精确匹配的定价
  final bool exists;
  
  /// 状态: "found", "fallback_available", "not_found"
  final String status;
  
  /// 消息
  final String message;
  
  /// 精确匹配的定价信息
  final ModelPricing? exactPricing;
  
  /// 备选定价信息
  final ModelPricing? fallbackPricing;
  
  /// 备选方案原因
  final String? fallbackReason;

  PricingCheckResult({
    required this.exists,
    required this.status,
    required this.message,
    this.exactPricing,
    this.fallbackPricing,
    this.fallbackReason,
  });

  factory PricingCheckResult.fromJson(Map<String, dynamic> json) =>
      _$PricingCheckResultFromJson(json);

  Map<String, dynamic> toJson() => _$PricingCheckResultToJson(this);
  
  /// 是否有可用的定价信息（精确匹配或备选方案）
  bool get hasPricing => exists || status == 'fallback_available';
  
  /// 获取可用的定价信息（优先精确匹配）
  ModelPricing? get availablePricing => exactPricing ?? fallbackPricing;
}

/// 创建定价请求
@JsonSerializable()
class CreatePricingRequest {
  /// 提供商名称
  final String provider;
  
  /// 模型ID
  final String modelId;
  
  /// 模型名称
  final String? modelName;
  
  /// 输入token价格
  final double? inputPricePerThousandTokens;
  
  /// 输出token价格
  final double? outputPricePerThousandTokens;
  
  /// 统一价格
  final double? unifiedPricePerThousandTokens;
  
  /// 最大上下文token数
  final int? maxContextTokens;
  
  /// 是否支持流式输出
  final bool? supportsStreaming;
  
  /// 描述
  final String? description;

  CreatePricingRequest({
    required this.provider,
    required this.modelId,
    this.modelName,
    this.inputPricePerThousandTokens,
    this.outputPricePerThousandTokens,
    this.unifiedPricePerThousandTokens,
    this.maxContextTokens,
    this.supportsStreaming,
    this.description,
  });

  factory CreatePricingRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePricingRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CreatePricingRequestToJson(this);
}
