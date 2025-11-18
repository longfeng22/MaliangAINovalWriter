// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_observability_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LLMTrace _$LLMTraceFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMTrace',
      json,
      ($checkedConvert) {
        final val = LLMTrace(
          id: $checkedConvert('id', (v) => v as String),
          traceId: $checkedConvert('traceId', (v) => v as String),
          provider: $checkedConvert('provider', (v) => v as String),
          model: $checkedConvert('model', (v) => v as String),
          userId: $checkedConvert('userId', (v) => v as String?),
          sessionId: $checkedConvert('sessionId', (v) => v as String?),
          businessType: $checkedConvert('businessType', (v) => v as String?),
          timestamp: $checkedConvert(
              'createdAt', (v) => const TimestampConverter().fromJson(v)),
          request: $checkedConvert(
              'request', (v) => LLMRequest.fromJson(v as Map<String, dynamic>)),
          response: $checkedConvert(
              'response',
              (v) => v == null
                  ? null
                  : LLMResponse.fromJson(v as Map<String, dynamic>)),
          performance: $checkedConvert(
              'performance',
              (v) => v == null
                  ? null
                  : LLMPerformanceMetrics.fromJson(v as Map<String, dynamic>)),
          error: $checkedConvert(
              'error',
              (v) => v == null
                  ? null
                  : LLMError.fromJson(v as Map<String, dynamic>)),
          toolCalls: $checkedConvert(
              'toolCalls',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => LLMToolCall.fromJson(e as Map<String, dynamic>))
                  .toList()),
          metadata:
              $checkedConvert('metadata', (v) => v as Map<String, dynamic>?),
          status: $checkedConvert(
              'status',
              (v) =>
                  $enumDecodeNullable(_$LLMTraceStatusEnumMap, v) ??
                  LLMTraceStatus.pending),
          isStreaming:
              $checkedConvert('isStreaming', (v) => v as bool? ?? false),
        );
        return val;
      },
      fieldKeyMap: const {'timestamp': 'createdAt'},
    );

Map<String, dynamic> _$LLMTraceToJson(LLMTrace instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'traceId': instance.traceId,
    'provider': instance.provider,
    'model': instance.model,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('userId', instance.userId);
  writeNotNull('sessionId', instance.sessionId);
  writeNotNull('businessType', instance.businessType);
  writeNotNull(
      'createdAt', const TimestampConverter().toJson(instance.timestamp));
  val['request'] = instance.request.toJson();
  writeNotNull('response', instance.response?.toJson());
  writeNotNull('performance', instance.performance?.toJson());
  writeNotNull('error', instance.error?.toJson());
  writeNotNull(
      'toolCalls', instance.toolCalls?.map((e) => e.toJson()).toList());
  writeNotNull('metadata', instance.metadata);
  val['status'] = _$LLMTraceStatusEnumMap[instance.status]!;
  val['isStreaming'] = instance.isStreaming;
  return val;
}

const _$LLMTraceStatusEnumMap = {
  LLMTraceStatus.pending: 'pending',
  LLMTraceStatus.success: 'success',
  LLMTraceStatus.error: 'error',
  LLMTraceStatus.timeout: 'timeout',
  LLMTraceStatus.cancelled: 'cancelled',
};

LLMRequest _$LLMRequestFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMRequest',
      json,
      ($checkedConvert) {
        final val = LLMRequest(
          messages: $checkedConvert(
              'messages',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => LLMMessage.fromJson(e as Map<String, dynamic>))
                  .toList()),
          temperature:
              $checkedConvert('temperature', (v) => (v as num?)?.toDouble()),
          topP: $checkedConvert('topP', (v) => (v as num?)?.toDouble()),
          topK: $checkedConvert('topK', (v) => (v as num?)?.toInt()),
          maxTokens: $checkedConvert('maxTokens', (v) => (v as num?)?.toInt()),
          seed: $checkedConvert('seed', (v) => (v as num?)?.toInt()),
          tools: $checkedConvert(
              'tools',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => LLMTool.fromJson(e as Map<String, dynamic>))
                  .toList()),
          toolChoice: $checkedConvert('toolChoice', (v) => v as String?),
          responseFormat:
              $checkedConvert('responseFormat', (v) => v as String?),
          additionalParameters: $checkedConvert(
              'additionalParameters', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMRequestToJson(LLMRequest instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('messages', instance.messages?.map((e) => e.toJson()).toList());
  writeNotNull('temperature', instance.temperature);
  writeNotNull('topP', instance.topP);
  writeNotNull('topK', instance.topK);
  writeNotNull('maxTokens', instance.maxTokens);
  writeNotNull('seed', instance.seed);
  writeNotNull('tools', instance.tools?.map((e) => e.toJson()).toList());
  writeNotNull('toolChoice', instance.toolChoice);
  writeNotNull('responseFormat', instance.responseFormat);
  writeNotNull('additionalParameters', instance.additionalParameters);
  return val;
}

LLMResponse _$LLMResponseFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMResponse',
      json,
      ($checkedConvert) {
        final val = LLMResponse(
          id: $checkedConvert('id', (v) => v as String?),
          content: $checkedConvert('content', (v) => v as String?),
          tokenUsage: $checkedConvert(
              'tokenUsage',
              (v) => v == null
                  ? null
                  : LLMTokenUsage.fromJson(v as Map<String, dynamic>)),
          finishReason: $checkedConvert('finishReason', (v) => v as String?),
          toolCallResults: $checkedConvert(
              'toolCallResults',
              (v) => (v as List<dynamic>?)
                  ?.map((e) =>
                      LLMToolCallResult.fromJson(e as Map<String, dynamic>))
                  .toList()),
          metadata:
              $checkedConvert('metadata', (v) => v as Map<String, dynamic>?),
          streamChunks: $checkedConvert('streamChunks',
              (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMResponseToJson(LLMResponse instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('id', instance.id);
  writeNotNull('content', instance.content);
  writeNotNull('tokenUsage', instance.tokenUsage?.toJson());
  writeNotNull('finishReason', instance.finishReason);
  writeNotNull('toolCallResults',
      instance.toolCallResults?.map((e) => e.toJson()).toList());
  writeNotNull('metadata', instance.metadata);
  writeNotNull('streamChunks', instance.streamChunks);
  return val;
}

LLMMessage _$LLMMessageFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMMessage',
      json,
      ($checkedConvert) {
        final val = LLMMessage(
          role: $checkedConvert('role', (v) => v as String),
          content: $checkedConvert('content', (v) => v as String?),
          name: $checkedConvert('name', (v) => v as String?),
          metadata:
              $checkedConvert('metadata', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMMessageToJson(LLMMessage instance) {
  final val = <String, dynamic>{
    'role': instance.role,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('content', instance.content);
  writeNotNull('name', instance.name);
  writeNotNull('metadata', instance.metadata);
  return val;
}

LLMTool _$LLMToolFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMTool',
      json,
      ($checkedConvert) {
        final val = LLMTool(
          name: $checkedConvert('name', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String?),
          parameters:
              $checkedConvert('parameters', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMToolToJson(LLMTool instance) {
  final val = <String, dynamic>{
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  writeNotNull('parameters', instance.parameters);
  return val;
}

LLMToolCall _$LLMToolCallFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMToolCall',
      json,
      ($checkedConvert) {
        final val = LLMToolCall(
          id: $checkedConvert('id', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String),
          arguments:
              $checkedConvert('arguments', (v) => v as Map<String, dynamic>?),
          timestamp: $checkedConvert('timestamp',
              (v) => v == null ? null : DateTime.parse(v as String)),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMToolCallToJson(LLMToolCall instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('arguments', instance.arguments);
  writeNotNull('timestamp', instance.timestamp?.toIso8601String());
  return val;
}

LLMToolCallResult _$LLMToolCallResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'LLMToolCallResult',
      json,
      ($checkedConvert) {
        final val = LLMToolCallResult(
          toolCallId: $checkedConvert('toolCallId', (v) => v as String),
          result: $checkedConvert('result', (v) => v as String?),
          error: $checkedConvert(
              'error',
              (v) => v == null
                  ? null
                  : LLMError.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMToolCallResultToJson(LLMToolCallResult instance) {
  final val = <String, dynamic>{
    'toolCallId': instance.toolCallId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('result', instance.result);
  writeNotNull('error', instance.error?.toJson());
  return val;
}

LLMTokenUsage _$LLMTokenUsageFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'LLMTokenUsage',
      json,
      ($checkedConvert) {
        final val = LLMTokenUsage(
          promptTokens:
              $checkedConvert('promptTokens', (v) => (v as num?)?.toInt()),
          completionTokens:
              $checkedConvert('completionTokens', (v) => (v as num?)?.toInt()),
          totalTokens:
              $checkedConvert('totalTokens', (v) => (v as num?)?.toInt()),
          inputTokens:
              $checkedConvert('inputTokens', (v) => (v as num?)?.toInt()),
          outputTokens:
              $checkedConvert('outputTokens', (v) => (v as num?)?.toInt()),
          reasoningTokens:
              $checkedConvert('reasoningTokens', (v) => (v as num?)?.toInt()),
          cachedTokens:
              $checkedConvert('cachedTokens', (v) => (v as num?)?.toInt()),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMTokenUsageToJson(LLMTokenUsage instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('promptTokens', instance.promptTokens);
  writeNotNull('completionTokens', instance.completionTokens);
  writeNotNull('totalTokens', instance.totalTokens);
  writeNotNull('inputTokens', instance.inputTokens);
  writeNotNull('outputTokens', instance.outputTokens);
  writeNotNull('reasoningTokens', instance.reasoningTokens);
  writeNotNull('cachedTokens', instance.cachedTokens);
  return val;
}

LLMPerformanceMetrics _$LLMPerformanceMetricsFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'LLMPerformanceMetrics',
      json,
      ($checkedConvert) {
        final val = LLMPerformanceMetrics(
          requestLatencyMs:
              $checkedConvert('requestLatencyMs', (v) => (v as num?)?.toInt()),
          firstTokenLatencyMs: $checkedConvert(
              'firstTokenLatencyMs', (v) => (v as num?)?.toInt()),
          totalDurationMs:
              $checkedConvert('totalDurationMs', (v) => (v as num?)?.toInt()),
          tokensPerSecond: $checkedConvert(
              'tokensPerSecond', (v) => (v as num?)?.toDouble()),
          charactersPerSecond: $checkedConvert(
              'charactersPerSecond', (v) => (v as num?)?.toDouble()),
          queueTimeMs:
              $checkedConvert('queueTimeMs', (v) => (v as num?)?.toInt()),
          processingTimeMs:
              $checkedConvert('processingTimeMs', (v) => (v as num?)?.toInt()),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMPerformanceMetricsToJson(
    LLMPerformanceMetrics instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('requestLatencyMs', instance.requestLatencyMs);
  writeNotNull('firstTokenLatencyMs', instance.firstTokenLatencyMs);
  writeNotNull('totalDurationMs', instance.totalDurationMs);
  writeNotNull('tokensPerSecond', instance.tokensPerSecond);
  writeNotNull('charactersPerSecond', instance.charactersPerSecond);
  writeNotNull('queueTimeMs', instance.queueTimeMs);
  writeNotNull('processingTimeMs', instance.processingTimeMs);
  return val;
}

LLMError _$LLMErrorFromJson(Map<String, dynamic> json) => $checkedCreate(
      'LLMError',
      json,
      ($checkedConvert) {
        final val = LLMError(
          type: $checkedConvert('type', (v) => v as String?),
          message: $checkedConvert('message', (v) => v as String?),
          code: $checkedConvert('code', (v) => v as String?),
          stackTrace: $checkedConvert('stackTrace', (v) => v as String?),
          details:
              $checkedConvert('details', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMErrorToJson(LLMError instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('type', instance.type);
  writeNotNull('message', instance.message);
  writeNotNull('code', instance.code);
  writeNotNull('stackTrace', instance.stackTrace);
  writeNotNull('details', instance.details);
  return val;
}

LLMStatistics _$LLMStatisticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'LLMStatistics',
      json,
      ($checkedConvert) {
        final val = LLMStatistics(
          totalCalls: $checkedConvert('totalCalls', (v) => (v as num).toInt()),
          successfulCalls:
              $checkedConvert('successfulCalls', (v) => (v as num).toInt()),
          failedCalls:
              $checkedConvert('failedCalls', (v) => (v as num).toInt()),
          successRate:
              $checkedConvert('successRate', (v) => (v as num).toDouble()),
          averageLatency:
              $checkedConvert('averageLatency', (v) => (v as num).toDouble()),
          totalTokens:
              $checkedConvert('totalTokens', (v) => (v as num).toInt()),
          startTime: $checkedConvert('startTime',
              (v) => v == null ? null : DateTime.parse(v as String)),
          endTime: $checkedConvert(
              'endTime', (v) => v == null ? null : DateTime.parse(v as String)),
          details:
              $checkedConvert('details', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMStatisticsToJson(LLMStatistics instance) {
  final val = <String, dynamic>{
    'totalCalls': instance.totalCalls,
    'successfulCalls': instance.successfulCalls,
    'failedCalls': instance.failedCalls,
    'successRate': instance.successRate,
    'averageLatency': instance.averageLatency,
    'totalTokens': instance.totalTokens,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('startTime', instance.startTime?.toIso8601String());
  writeNotNull('endTime', instance.endTime?.toIso8601String());
  writeNotNull('details', instance.details);
  return val;
}

ProviderStatistics _$ProviderStatisticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ProviderStatistics',
      json,
      ($checkedConvert) {
        final val = ProviderStatistics(
          provider: $checkedConvert('provider', (v) => v as String),
          statistics: $checkedConvert('statistics',
              (v) => LLMStatistics.fromJson(v as Map<String, dynamic>)),
          models: $checkedConvert(
              'models',
              (v) => (v as List<dynamic>)
                  .map((e) =>
                      ModelStatistics.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$ProviderStatisticsToJson(ProviderStatistics instance) =>
    <String, dynamic>{
      'provider': instance.provider,
      'statistics': instance.statistics.toJson(),
      'models': instance.models.map((e) => e.toJson()).toList(),
    };

ModelStatistics _$ModelStatisticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ModelStatistics',
      json,
      ($checkedConvert) {
        final val = ModelStatistics(
          modelName: $checkedConvert('modelName', (v) => v as String),
          provider: $checkedConvert('provider', (v) => v as String),
          statistics: $checkedConvert('statistics',
              (v) => LLMStatistics.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$ModelStatisticsToJson(ModelStatistics instance) =>
    <String, dynamic>{
      'modelName': instance.modelName,
      'provider': instance.provider,
      'statistics': instance.statistics.toJson(),
    };

UserStatistics _$UserStatisticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'UserStatistics',
      json,
      ($checkedConvert) {
        final val = UserStatistics(
          userId: $checkedConvert('userId', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String?),
          statistics: $checkedConvert('statistics',
              (v) => LLMStatistics.fromJson(v as Map<String, dynamic>)),
          topModels: $checkedConvert('topModels',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          topProviders: $checkedConvert('topProviders',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$UserStatisticsToJson(UserStatistics instance) {
  final val = <String, dynamic>{
    'userId': instance.userId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('username', instance.username);
  val['statistics'] = instance.statistics.toJson();
  val['topModels'] = instance.topModels;
  val['topProviders'] = instance.topProviders;
  return val;
}

ErrorStatistics _$ErrorStatisticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ErrorStatistics',
      json,
      ($checkedConvert) {
        final val = ErrorStatistics(
          errorType: $checkedConvert('errorType', (v) => v as String),
          count: $checkedConvert('count', (v) => (v as num).toInt()),
          percentage:
              $checkedConvert('percentage', (v) => (v as num).toDouble()),
          topErrorMessages: $checkedConvert('topErrorMessages',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          affectedModels: $checkedConvert('affectedModels',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$ErrorStatisticsToJson(ErrorStatistics instance) =>
    <String, dynamic>{
      'errorType': instance.errorType,
      'count': instance.count,
      'percentage': instance.percentage,
      'topErrorMessages': instance.topErrorMessages,
      'affectedModels': instance.affectedModels,
    };

PerformanceStatistics _$PerformanceStatisticsFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'PerformanceStatistics',
      json,
      ($checkedConvert) {
        final val = PerformanceStatistics(
          averageLatency:
              $checkedConvert('averageLatency', (v) => (v as num).toDouble()),
          medianLatency:
              $checkedConvert('medianLatency', (v) => (v as num).toDouble()),
          p95Latency:
              $checkedConvert('p95Latency', (v) => (v as num).toDouble()),
          p99Latency:
              $checkedConvert('p99Latency', (v) => (v as num).toDouble()),
          averageThroughput: $checkedConvert(
              'averageThroughput', (v) => (v as num).toDouble()),
          latencyTrends: $checkedConvert(
              'latencyTrends',
              (v) => (v as List<dynamic>)
                  .map((e) =>
                      TimeBasedMetric.fromJson(e as Map<String, dynamic>))
                  .toList()),
          throughputTrends: $checkedConvert(
              'throughputTrends',
              (v) => (v as List<dynamic>)
                  .map((e) =>
                      TimeBasedMetric.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$PerformanceStatisticsToJson(
        PerformanceStatistics instance) =>
    <String, dynamic>{
      'averageLatency': instance.averageLatency,
      'medianLatency': instance.medianLatency,
      'p95Latency': instance.p95Latency,
      'p99Latency': instance.p99Latency,
      'averageThroughput': instance.averageThroughput,
      'latencyTrends': instance.latencyTrends.map((e) => e.toJson()).toList(),
      'throughputTrends':
          instance.throughputTrends.map((e) => e.toJson()).toList(),
    };

TimeBasedMetric _$TimeBasedMetricFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'TimeBasedMetric',
      json,
      ($checkedConvert) {
        final val = TimeBasedMetric(
          timestamp:
              $checkedConvert('timestamp', (v) => DateTime.parse(v as String)),
          value: $checkedConvert('value', (v) => (v as num).toDouble()),
          label: $checkedConvert('label', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$TimeBasedMetricToJson(TimeBasedMetric instance) {
  final val = <String, dynamic>{
    'timestamp': instance.timestamp.toIso8601String(),
    'value': instance.value,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('label', instance.label);
  return val;
}

SystemHealthStatus _$SystemHealthStatusFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'SystemHealthStatus',
      json,
      ($checkedConvert) {
        final val = SystemHealthStatus(
          status: $checkedConvert(
              'status',
              (v) =>
                  $enumDecodeNullable(_$HealthStatusEnumMap, v) ??
                  HealthStatus.healthy),
          components: $checkedConvert(
              'components',
              (v) => (v as Map<String, dynamic>).map(
                    (k, e) => MapEntry(
                        k, ComponentHealth.fromJson(e as Map<String, dynamic>)),
                  )),
          message: $checkedConvert('message', (v) => v as String?),
          lastChecked: $checkedConvert('lastChecked',
              (v) => v == null ? null : DateTime.parse(v as String)),
        );
        return val;
      },
    );

Map<String, dynamic> _$SystemHealthStatusToJson(SystemHealthStatus instance) {
  final val = <String, dynamic>{
    'status': _$HealthStatusEnumMap[instance.status]!,
    'components': instance.components.map((k, e) => MapEntry(k, e.toJson())),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message', instance.message);
  writeNotNull('lastChecked', instance.lastChecked?.toIso8601String());
  return val;
}

const _$HealthStatusEnumMap = {
  HealthStatus.healthy: 'healthy',
  HealthStatus.degraded: 'degraded',
  HealthStatus.unhealthy: 'unhealthy',
  HealthStatus.unknown: 'unknown',
};

ComponentHealth _$ComponentHealthFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ComponentHealth',
      json,
      ($checkedConvert) {
        final val = ComponentHealth(
          status: $checkedConvert(
              'status',
              (v) =>
                  $enumDecodeNullable(_$HealthStatusEnumMap, v) ??
                  HealthStatus.healthy),
          message: $checkedConvert('message', (v) => v as String?),
          metrics:
              $checkedConvert('metrics', (v) => v as Map<String, dynamic>?),
        );
        return val;
      },
    );

Map<String, dynamic> _$ComponentHealthToJson(ComponentHealth instance) {
  final val = <String, dynamic>{
    'status': _$HealthStatusEnumMap[instance.status]!,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message', instance.message);
  writeNotNull('metrics', instance.metrics);
  return val;
}

LLMTraceSearchCriteria _$LLMTraceSearchCriteriaFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'LLMTraceSearchCriteria',
      json,
      ($checkedConvert) {
        final val = LLMTraceSearchCriteria(
          userId: $checkedConvert('userId', (v) => v as String?),
          provider: $checkedConvert('provider', (v) => v as String?),
          model: $checkedConvert('model', (v) => v as String?),
          sessionId: $checkedConvert('sessionId', (v) => v as String?),
          hasError: $checkedConvert('hasError', (v) => v as bool?),
          status: $checkedConvert(
              'status', (v) => $enumDecodeNullable(_$LLMTraceStatusEnumMap, v)),
          startTime: $checkedConvert('startTime',
              (v) => v == null ? null : DateTime.parse(v as String)),
          endTime: $checkedConvert(
              'endTime', (v) => v == null ? null : DateTime.parse(v as String)),
          page: $checkedConvert('page', (v) => (v as num?)?.toInt() ?? 0),
          size: $checkedConvert('size', (v) => (v as num?)?.toInt() ?? 20),
          sortBy: $checkedConvert('sortBy', (v) => v as String? ?? 'timestamp'),
          sortDir: $checkedConvert('sortDir', (v) => v as String? ?? 'desc'),
        );
        return val;
      },
    );

Map<String, dynamic> _$LLMTraceSearchCriteriaToJson(
    LLMTraceSearchCriteria instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('userId', instance.userId);
  writeNotNull('provider', instance.provider);
  writeNotNull('model', instance.model);
  writeNotNull('sessionId', instance.sessionId);
  writeNotNull('hasError', instance.hasError);
  writeNotNull('status', _$LLMTraceStatusEnumMap[instance.status]);
  writeNotNull('startTime', instance.startTime?.toIso8601String());
  writeNotNull('endTime', instance.endTime?.toIso8601String());
  val['page'] = instance.page;
  val['size'] = instance.size;
  val['sortBy'] = instance.sortBy;
  val['sortDir'] = instance.sortDir;
  return val;
}

ApiResponse<T> _$ApiResponseFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) =>
    $checkedCreate(
      'ApiResponse',
      json,
      ($checkedConvert) {
        final val = ApiResponse<T>(
          success: $checkedConvert('success', (v) => v as bool),
          message: $checkedConvert('message', (v) => v as String?),
          data: $checkedConvert(
              'data', (v) => _$nullableGenericFromJson(v, fromJsonT)),
          error: $checkedConvert('error', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$ApiResponseToJson<T>(
  ApiResponse<T> instance,
  Object? Function(T value) toJsonT,
) {
  final val = <String, dynamic>{
    'success': instance.success,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message', instance.message);
  writeNotNull('data', _$nullableGenericToJson(instance.data, toJsonT));
  writeNotNull('error', instance.error);
  return val;
}

T? _$nullableGenericFromJson<T>(
  Object? input,
  T Function(Object? json) fromJson,
) =>
    input == null ? null : fromJson(input);

Object? _$nullableGenericToJson<T>(
  T? input,
  Object? Function(T value) toJson,
) =>
    input == null ? null : toJson(input);

PagedResponse<T> _$PagedResponseFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) =>
    $checkedCreate(
      'PagedResponse',
      json,
      ($checkedConvert) {
        final val = PagedResponse<T>(
          content: $checkedConvert(
              'content', (v) => (v as List<dynamic>).map(fromJsonT).toList()),
          page: $checkedConvert('page', (v) => (v as num).toInt()),
          size: $checkedConvert('size', (v) => (v as num).toInt()),
          totalElements:
              $checkedConvert('totalElements', (v) => (v as num).toInt()),
          totalPages: $checkedConvert('totalPages', (v) => (v as num).toInt()),
          first: $checkedConvert('first', (v) => v as bool? ?? false),
          last: $checkedConvert('last', (v) => v as bool? ?? false),
        );
        return val;
      },
    );

Map<String, dynamic> _$PagedResponseToJson<T>(
  PagedResponse<T> instance,
  Object? Function(T value) toJsonT,
) =>
    <String, dynamic>{
      'content': instance.content.map(toJsonT).toList(),
      'page': instance.page,
      'size': instance.size,
      'totalElements': instance.totalElements,
      'totalPages': instance.totalPages,
      'first': instance.first,
      'last': instance.last,
    };

CursorPageResponse<T> _$CursorPageResponseFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) =>
    $checkedCreate(
      'CursorPageResponse',
      json,
      ($checkedConvert) {
        final val = CursorPageResponse<T>(
          items: $checkedConvert(
              'items', (v) => (v as List<dynamic>).map(fromJsonT).toList()),
          nextCursor: $checkedConvert('nextCursor', (v) => v as String?),
          hasMore: $checkedConvert('hasMore', (v) => v as bool? ?? false),
        );
        return val;
      },
    );

Map<String, dynamic> _$CursorPageResponseToJson<T>(
  CursorPageResponse<T> instance,
  Object? Function(T value) toJsonT,
) {
  final val = <String, dynamic>{
    'items': instance.items.map(toJsonT).toList(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('nextCursor', instance.nextCursor);
  val['hasMore'] = instance.hasMore;
  return val;
}
