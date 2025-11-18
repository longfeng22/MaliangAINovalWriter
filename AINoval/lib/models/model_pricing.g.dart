// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_pricing.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelPricing _$ModelPricingFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ModelPricing',
      json,
      ($checkedConvert) {
        final val = ModelPricing(
          id: $checkedConvert('id', (v) => v as String?),
          provider: $checkedConvert('provider', (v) => v as String),
          modelId: $checkedConvert('modelId', (v) => v as String),
          modelName: $checkedConvert('modelName', (v) => v as String?),
          inputPricePerThousandTokens: $checkedConvert(
              'inputPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          outputPricePerThousandTokens: $checkedConvert(
              'outputPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          unifiedPricePerThousandTokens: $checkedConvert(
              'unifiedPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          maxContextTokens:
              $checkedConvert('maxContextTokens', (v) => (v as num?)?.toInt()),
          supportsStreaming:
              $checkedConvert('supportsStreaming', (v) => v as bool?),
          description: $checkedConvert('description', (v) => v as String?),
          additionalPricing: $checkedConvert(
              'additionalPricing',
              (v) => (v as Map<String, dynamic>?)?.map(
                    (k, e) => MapEntry(k, (e as num).toDouble()),
                  )),
          source: $checkedConvert('source', (v) => v as String?),
          createdAt: $checkedConvert(
              'createdAt', (v) => ModelPricing._parseDateTime(v)),
          updatedAt: $checkedConvert(
              'updatedAt', (v) => ModelPricing._parseDateTime(v)),
          version: $checkedConvert('version', (v) => (v as num?)?.toInt()),
          active: $checkedConvert('active', (v) => v as bool?),
        );
        return val;
      },
    );

Map<String, dynamic> _$ModelPricingToJson(ModelPricing instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('id', instance.id);
  val['provider'] = instance.provider;
  val['modelId'] = instance.modelId;
  writeNotNull('modelName', instance.modelName);
  writeNotNull(
      'inputPricePerThousandTokens', instance.inputPricePerThousandTokens);
  writeNotNull(
      'outputPricePerThousandTokens', instance.outputPricePerThousandTokens);
  writeNotNull(
      'unifiedPricePerThousandTokens', instance.unifiedPricePerThousandTokens);
  writeNotNull('maxContextTokens', instance.maxContextTokens);
  writeNotNull('supportsStreaming', instance.supportsStreaming);
  writeNotNull('description', instance.description);
  writeNotNull('additionalPricing', instance.additionalPricing);
  writeNotNull('source', instance.source);
  writeNotNull('createdAt', ModelPricing._dateTimeToJson(instance.createdAt));
  writeNotNull('updatedAt', ModelPricing._dateTimeToJson(instance.updatedAt));
  writeNotNull('version', instance.version);
  writeNotNull('active', instance.active);
  return val;
}

PricingCheckResult _$PricingCheckResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PricingCheckResult',
      json,
      ($checkedConvert) {
        final val = PricingCheckResult(
          exists: $checkedConvert('exists', (v) => v as bool),
          status: $checkedConvert('status', (v) => v as String),
          message: $checkedConvert('message', (v) => v as String),
          exactPricing: $checkedConvert(
              'exactPricing',
              (v) => v == null
                  ? null
                  : ModelPricing.fromJson(v as Map<String, dynamic>)),
          fallbackPricing: $checkedConvert(
              'fallbackPricing',
              (v) => v == null
                  ? null
                  : ModelPricing.fromJson(v as Map<String, dynamic>)),
          fallbackReason:
              $checkedConvert('fallbackReason', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$PricingCheckResultToJson(PricingCheckResult instance) {
  final val = <String, dynamic>{
    'exists': instance.exists,
    'status': instance.status,
    'message': instance.message,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('exactPricing', instance.exactPricing?.toJson());
  writeNotNull('fallbackPricing', instance.fallbackPricing?.toJson());
  writeNotNull('fallbackReason', instance.fallbackReason);
  return val;
}

CreatePricingRequest _$CreatePricingRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePricingRequest',
      json,
      ($checkedConvert) {
        final val = CreatePricingRequest(
          provider: $checkedConvert('provider', (v) => v as String),
          modelId: $checkedConvert('modelId', (v) => v as String),
          modelName: $checkedConvert('modelName', (v) => v as String?),
          inputPricePerThousandTokens: $checkedConvert(
              'inputPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          outputPricePerThousandTokens: $checkedConvert(
              'outputPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          unifiedPricePerThousandTokens: $checkedConvert(
              'unifiedPricePerThousandTokens', (v) => (v as num?)?.toDouble()),
          maxContextTokens:
              $checkedConvert('maxContextTokens', (v) => (v as num?)?.toInt()),
          supportsStreaming:
              $checkedConvert('supportsStreaming', (v) => v as bool?),
          description: $checkedConvert('description', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreatePricingRequestToJson(
    CreatePricingRequest instance) {
  final val = <String, dynamic>{
    'provider': instance.provider,
    'modelId': instance.modelId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('modelName', instance.modelName);
  writeNotNull(
      'inputPricePerThousandTokens', instance.inputPricePerThousandTokens);
  writeNotNull(
      'outputPricePerThousandTokens', instance.outputPricePerThousandTokens);
  writeNotNull(
      'unifiedPricePerThousandTokens', instance.unifiedPricePerThousandTokens);
  writeNotNull('maxContextTokens', instance.maxContextTokens);
  writeNotNull('supportsStreaming', instance.supportsStreaming);
  writeNotNull('description', instance.description);
  return val;
}
