/// LLM可观测性相关数据模型
/// 用于管理后台查看和分析大模型调用日志

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import '../../utils/date_time_parser.dart';

part 'llm_observability_models.g.dart';

/// 自定义时间戳转换器
class TimestampConverter implements JsonConverter<DateTime, dynamic> {
  const TimestampConverter();

  @override
  DateTime fromJson(dynamic timestamp) {
    return parseBackendDateTime(timestamp);
  }

  @override
  dynamic toJson(DateTime timestamp) {
    return timestamp.toIso8601String();
  }
}

/// LLM调用日志
@JsonSerializable()
class LLMTrace extends Equatable {
  final String id;
  final String traceId;
  final String provider;
  final String model;
  final String? userId;
  final String? sessionId;
  final String? businessType; // ✅ 业务类型（用于分类和过滤）
  @JsonKey(name: 'createdAt')
  @TimestampConverter()
  final DateTime timestamp;
  
  // 请求信息
  final LLMRequest request;
  
  // 响应信息
  final LLMResponse? response;
  
  // 性能指标
  final LLMPerformanceMetrics? performance;
  
  // 错误信息
  final LLMError? error;
  
  // 工具调用
  final List<LLMToolCall>? toolCalls;
  
  // 元数据
  final Map<String, dynamic>? metadata;
  
  // 状态
  @JsonKey(defaultValue: LLMTraceStatus.pending)
  final LLMTraceStatus status;
  @JsonKey(defaultValue: false)
  final bool isStreaming;

  const LLMTrace({
    required this.id,
    required this.traceId,
    required this.provider,
    required this.model,
    this.userId,
    this.sessionId,
    this.businessType,
    required this.timestamp,
    required this.request,
    this.response,
    this.performance,
    this.error,
    this.toolCalls,
    this.metadata,
    this.status = LLMTraceStatus.pending,
    this.isStreaming = false,
  });

  factory LLMTrace.fromJson(Map<String, dynamic> json) => _$LLMTraceFromJson(json);
  Map<String, dynamic> toJson() => _$LLMTraceToJson(this);
  
  @override
  List<Object?> get props => [id, traceId, provider, model, userId, sessionId, businessType, timestamp, request, response, performance, error, toolCalls, metadata, status, isStreaming];
}

/// LLM请求信息
@JsonSerializable()
class LLMRequest extends Equatable {
  final List<LLMMessage>? messages;
  
  // 模型参数
  final double? temperature;
  final double? topP;
  final int? topK;
  final int? maxTokens;
  final int? seed;
  
  // 工具调用
  final List<LLMTool>? tools;
  final String? toolChoice;
  
  // 格式设置
  final String? responseFormat;
  
  // 其他参数
  final Map<String, dynamic>? additionalParameters;

  const LLMRequest({
    this.messages,
    this.temperature,
    this.topP,
    this.topK,
    this.maxTokens,
    this.seed,
    this.tools,
    this.toolChoice,
    this.responseFormat,
    this.additionalParameters,
  });

  factory LLMRequest.fromJson(Map<String, dynamic> json) => _$LLMRequestFromJson(json);
  Map<String, dynamic> toJson() => _$LLMRequestToJson(this);
  
  @override
  List<Object?> get props => [messages, temperature, topP, topK, maxTokens, seed, tools, toolChoice, responseFormat, additionalParameters];
}

/// LLM响应信息
@JsonSerializable()
class LLMResponse extends Equatable {
  final String? id;
  final String? content;
  
  // Token使用情况
  final LLMTokenUsage? tokenUsage;
  
  // 完成原因
  final String? finishReason;
  
  // 工具调用结果
  final List<LLMToolCallResult>? toolCallResults;
  
  // 元数据
  final Map<String, dynamic>? metadata;
  
  // 流式数据
  final List<String>? streamChunks;

  const LLMResponse({
    this.id,
    this.content,
    this.tokenUsage,
    this.finishReason,
    this.toolCallResults,
    this.metadata,
    this.streamChunks,
  });

  factory LLMResponse.fromJson(Map<String, dynamic> json) => _$LLMResponseFromJson(json);
  Map<String, dynamic> toJson() => _$LLMResponseToJson(this);
  
  @override
  List<Object?> get props => [id, content, tokenUsage, finishReason, toolCallResults, metadata, streamChunks];
}

/// LLM消息
@JsonSerializable()
class LLMMessage extends Equatable {
  final String role;
  final String? content;
  final String? name;
  final Map<String, dynamic>? metadata;

  const LLMMessage({
    required this.role,
    this.content,
    this.name,
    this.metadata,
  });

  factory LLMMessage.fromJson(Map<String, dynamic> json) => _$LLMMessageFromJson(json);
  Map<String, dynamic> toJson() => _$LLMMessageToJson(this);
  
  @override
  List<Object?> get props => [role, content, name, metadata];
}

/// LLM工具定义
@JsonSerializable()
class LLMTool extends Equatable {
  final String name;
  final String? description;
  final Map<String, dynamic>? parameters;

  const LLMTool({
    required this.name,
    this.description,
    this.parameters,
  });

  factory LLMTool.fromJson(Map<String, dynamic> json) => _$LLMToolFromJson(json);
  Map<String, dynamic> toJson() => _$LLMToolToJson(this);
  
  @override
  List<Object?> get props => [name, description, parameters];
}

/// LLM工具调用
@JsonSerializable()
class LLMToolCall extends Equatable {
  final String id;
  final String name;
  final Map<String, dynamic>? arguments;
  final DateTime? timestamp;

  const LLMToolCall({
    required this.id,
    required this.name,
    this.arguments,
    this.timestamp,
  });

  factory LLMToolCall.fromJson(Map<String, dynamic> json) => _$LLMToolCallFromJson(json);
  Map<String, dynamic> toJson() => _$LLMToolCallToJson(this);
  
  @override
  List<Object?> get props => [id, name, arguments, timestamp];
}

/// LLM工具调用结果
@JsonSerializable()
class LLMToolCallResult extends Equatable {
  final String toolCallId;
  final String? result;
  final LLMError? error;

  const LLMToolCallResult({
    required this.toolCallId,
    this.result,
    this.error,
  });

  factory LLMToolCallResult.fromJson(Map<String, dynamic> json) => _$LLMToolCallResultFromJson(json);
  Map<String, dynamic> toJson() => _$LLMToolCallResultToJson(this);
  
  @override
  List<Object?> get props => [toolCallId, result, error];
}

/// Token使用情况
@JsonSerializable()
class LLMTokenUsage extends Equatable {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  
  // 详细分解
  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedTokens;

  const LLMTokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedTokens,
  });

  factory LLMTokenUsage.fromJson(Map<String, dynamic> json) => _$LLMTokenUsageFromJson(json);
  Map<String, dynamic> toJson() => _$LLMTokenUsageToJson(this);
  
  @override
  List<Object?> get props => [promptTokens, completionTokens, totalTokens, inputTokens, outputTokens, reasoningTokens, cachedTokens];
}

/// 性能指标
@JsonSerializable()
class LLMPerformanceMetrics extends Equatable {
  final int? requestLatencyMs;
  final int? firstTokenLatencyMs;
  final int? totalDurationMs;
  
  // 吞吐量
  final double? tokensPerSecond;
  final double? charactersPerSecond;
  
  // 队列时间
  final int? queueTimeMs;
  final int? processingTimeMs;

  const LLMPerformanceMetrics({
    this.requestLatencyMs,
    this.firstTokenLatencyMs,
    this.totalDurationMs,
    this.tokensPerSecond,
    this.charactersPerSecond,
    this.queueTimeMs,
    this.processingTimeMs,
  });

  factory LLMPerformanceMetrics.fromJson(Map<String, dynamic> json) => _$LLMPerformanceMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$LLMPerformanceMetricsToJson(this);
  
  @override
  List<Object?> get props => [requestLatencyMs, firstTokenLatencyMs, totalDurationMs, tokensPerSecond, charactersPerSecond, queueTimeMs, processingTimeMs];
}

/// 错误信息
@JsonSerializable()
class LLMError extends Equatable {
  final String? type;
  final String? message;
  final String? code;
  final String? stackTrace;
  final Map<String, dynamic>? details;

  const LLMError({
    this.type,
    this.message,
    this.code,
    this.stackTrace,
    this.details,
  });

  factory LLMError.fromJson(Map<String, dynamic> json) => _$LLMErrorFromJson(json);
  Map<String, dynamic> toJson() => _$LLMErrorToJson(this);
  
  @override
  List<Object?> get props => [type, message, code, stackTrace, details];
}

/// LLM调用状态
enum LLMTraceStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('success')
  success,
  @JsonValue('error')
  error,
  @JsonValue('timeout')
  timeout,
  @JsonValue('cancelled')
  cancelled,
}

/// 统计信息基类
@JsonSerializable()
class LLMStatistics extends Equatable {
  final int totalCalls;
  final int successfulCalls;
  final int failedCalls;
  final double successRate;
  final double averageLatency;
  final int totalTokens;
  
  // 时间范围
  final DateTime? startTime;
  final DateTime? endTime;
  
  // 详细统计
  final Map<String, dynamic>? details;

  const LLMStatistics({
    required this.totalCalls,
    required this.successfulCalls,
    required this.failedCalls,
    required this.successRate,
    required this.averageLatency,
    required this.totalTokens,
    this.startTime,
    this.endTime,
    this.details,
  });

  factory LLMStatistics.fromJson(Map<String, dynamic> json) => _$LLMStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$LLMStatisticsToJson(this);
  
  @override
  List<Object?> get props => [totalCalls, successfulCalls, failedCalls, successRate, averageLatency, totalTokens, startTime, endTime, details];
}

/// 提供商统计
@JsonSerializable()
class ProviderStatistics extends Equatable {
  final String provider;
  final LLMStatistics statistics;
  final List<ModelStatistics> models;

  const ProviderStatistics({
    required this.provider,
    required this.statistics,
    required this.models,
  });

  factory ProviderStatistics.fromJson(Map<String, dynamic> json) => _$ProviderStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$ProviderStatisticsToJson(this);
  
  @override
  List<Object?> get props => [provider, statistics, models];
}

/// 模型统计
@JsonSerializable()
class ModelStatistics extends Equatable {
  final String modelName;
  final String provider;
  final LLMStatistics statistics;

  const ModelStatistics({
    required this.modelName,
    required this.provider,
    required this.statistics,
  });

  factory ModelStatistics.fromJson(Map<String, dynamic> json) => _$ModelStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$ModelStatisticsToJson(this);
  
  @override
  List<Object?> get props => [modelName, provider, statistics];
}

/// 用户统计
@JsonSerializable()
class UserStatistics extends Equatable {
  final String userId;
  final String? username;
  final LLMStatistics statistics;
  final List<String> topModels;
  final List<String> topProviders;

  const UserStatistics({
    required this.userId,
    this.username,
    required this.statistics,
    required this.topModels,
    required this.topProviders,
  });

  factory UserStatistics.fromJson(Map<String, dynamic> json) => _$UserStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$UserStatisticsToJson(this);
  
  @override
  List<Object?> get props => [userId, username, statistics, topModels, topProviders];
}

/// 错误统计
@JsonSerializable()
class ErrorStatistics extends Equatable {
  final String errorType;
  final int count;
  final double percentage;
  final List<String> topErrorMessages;
  final List<String> affectedModels;

  const ErrorStatistics({
    required this.errorType,
    required this.count,
    required this.percentage,
    required this.topErrorMessages,
    required this.affectedModels,
  });

  factory ErrorStatistics.fromJson(Map<String, dynamic> json) => _$ErrorStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$ErrorStatisticsToJson(this);
  
  @override
  List<Object?> get props => [errorType, count, percentage, topErrorMessages, affectedModels];
}

/// 性能统计
@JsonSerializable()
class PerformanceStatistics extends Equatable {
  final double averageLatency;
  final double medianLatency;
  final double p95Latency;
  final double p99Latency;
  final double averageThroughput;
  
  // 按时间分组的统计
  final List<TimeBasedMetric> latencyTrends;
  final List<TimeBasedMetric> throughputTrends;

  const PerformanceStatistics({
    required this.averageLatency,
    required this.medianLatency,
    required this.p95Latency,
    required this.p99Latency,
    required this.averageThroughput,
    required this.latencyTrends,
    required this.throughputTrends,
  });

  factory PerformanceStatistics.fromJson(Map<String, dynamic> json) => _$PerformanceStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$PerformanceStatisticsToJson(this);
  
  @override
  List<Object?> get props => [averageLatency, medianLatency, p95Latency, p99Latency, averageThroughput, latencyTrends, throughputTrends];
}

/// 基于时间的指标
@JsonSerializable()
class TimeBasedMetric extends Equatable {
  final DateTime timestamp;
  final double value;
  final String? label;

  const TimeBasedMetric({
    required this.timestamp,
    required this.value,
    this.label,
  });

  factory TimeBasedMetric.fromJson(Map<String, dynamic> json) => _$TimeBasedMetricFromJson(json);
  Map<String, dynamic> toJson() => _$TimeBasedMetricToJson(this);
  
  @override
  List<Object?> get props => [timestamp, value, label];
}

/// 系统健康状态
@JsonSerializable()
class SystemHealthStatus extends Equatable {
  @JsonKey(defaultValue: HealthStatus.healthy)
  final HealthStatus status;
  final Map<String, ComponentHealth> components;
  final String? message;
  final DateTime? lastChecked;

  const SystemHealthStatus({
    this.status = HealthStatus.healthy,
    required this.components,
    this.message,
    this.lastChecked,
  });

  factory SystemHealthStatus.fromJson(Map<String, dynamic> json) => _$SystemHealthStatusFromJson(json);
  Map<String, dynamic> toJson() => _$SystemHealthStatusToJson(this);
  
  @override
  List<Object?> get props => [status, components, message, lastChecked];
}

/// 组件健康状态
@JsonSerializable()
class ComponentHealth extends Equatable {
  @JsonKey(defaultValue: HealthStatus.healthy)
  final HealthStatus status;
  final String? message;
  final Map<String, dynamic>? metrics;

  const ComponentHealth({
    this.status = HealthStatus.healthy,
    this.message,
    this.metrics,
  });

  factory ComponentHealth.fromJson(Map<String, dynamic> json) => _$ComponentHealthFromJson(json);
  Map<String, dynamic> toJson() => _$ComponentHealthToJson(this);
  
  @override
  List<Object?> get props => [status, message, metrics];
}

/// 健康状态枚举
enum HealthStatus {
  @JsonValue('healthy')
  healthy,
  @JsonValue('degraded')
  degraded,
  @JsonValue('unhealthy')
  unhealthy,
  @JsonValue('unknown')
  unknown,
}

/// LLM日志搜索条件
@JsonSerializable()
class LLMTraceSearchCriteria extends Equatable {
  final String? userId;
  final String? provider;
  final String? model;
  final String? sessionId;
  final bool? hasError;
  final LLMTraceStatus? status;
  final DateTime? startTime;
  final DateTime? endTime;
  
  // 分页
  @JsonKey(defaultValue: 0)
  final int page;
  @JsonKey(defaultValue: 20)
  final int size;
  @JsonKey(defaultValue: 'timestamp')
  final String sortBy;
  @JsonKey(defaultValue: 'desc')
  final String sortDir;

  const LLMTraceSearchCriteria({
    this.userId,
    this.provider,
    this.model,
    this.sessionId,
    this.hasError,
    this.status,
    this.startTime,
    this.endTime,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'timestamp',
    this.sortDir = 'desc',
  });

  factory LLMTraceSearchCriteria.fromJson(Map<String, dynamic> json) => _$LLMTraceSearchCriteriaFromJson(json);
  Map<String, dynamic> toJson() => _$LLMTraceSearchCriteriaToJson(this);
  
  @override
  List<Object?> get props => [userId, provider, model, sessionId, hasError, status, startTime, endTime, page, size, sortBy, sortDir];
}

/// API响应包装类
@JsonSerializable(genericArgumentFactories: true)
class ApiResponse<T> extends Equatable {
  final bool success;
  final String? message;
  final T? data;
  final String? error;

  const ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.error,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(Object? json) fromJsonT) => 
      _$ApiResponseFromJson(json, fromJsonT);
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) => 
      _$ApiResponseToJson(this, toJsonT);
  
  @override
  List<Object?> get props => [success, message, data, error];
}

/// 分页响应
@JsonSerializable(genericArgumentFactories: true)
class PagedResponse<T> extends Equatable {
  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  @JsonKey(defaultValue: false)
  final bool first;
  @JsonKey(defaultValue: false)
  final bool last;

  const PagedResponse({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    this.first = false,
    this.last = false,
  });

  factory PagedResponse.fromJson(Map<String, dynamic> json, T Function(Object? json) fromJsonT) => 
      _$PagedResponseFromJson(json, fromJsonT);
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) => 
      _$PagedResponseToJson(this, toJsonT);
  
  @override
  List<Object?> get props => [content, page, size, totalElements, totalPages, first, last];
}

/// 游标分页响应
@JsonSerializable(genericArgumentFactories: true)
class CursorPageResponse<T> extends Equatable {
  final List<T> items;
  final String? nextCursor;
  @JsonKey(defaultValue: false)
  final bool hasMore;

  const CursorPageResponse({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  factory CursorPageResponse.fromJson(Map<String, dynamic> json, T Function(Object? json) fromJsonT) =>
      _$CursorPageResponseFromJson(json, fromJsonT);
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) =>
      _$CursorPageResponseToJson(this, toJsonT);

  @override
  List<Object?> get props => [items, nextCursor, hasMore];
}