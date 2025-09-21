import 'dart:async';
import 'dart:convert';

import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/services/api_service/base/api_exception.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' as flutter_sse;

/// A client specifically designed for handling Server-Sent Events (SSE).
///
/// Encapsulates connection details, authentication, and event parsing logic,
/// using the 'flutter_client_sse' package.
class _RetryState {
  int errorCount;
  DateTime firstErrorAt;
  _RetryState({required this.errorCount, required this.firstErrorAt});
}

class SseClient {

  // --------------- Singleton Pattern (Optional but common) ---------------
  // Private constructor
  SseClient._internal() : _baseUrl = AppConfig.apiBaseUrl;

  // Factory constructor to return the instance
  factory SseClient() {
    return _instance;
  }
  final String _tag = 'SseClient';
  final String _baseUrl;
  
  // 存储活跃连接，以便于管理
  final Map<String, StreamSubscription> _activeConnections = {};
  final Map<String, _RetryState> _retryStates = {};

  // Static instance
  static final SseClient _instance = SseClient._internal();
  // --------------- End Singleton Pattern ---------------

  // Or a simple public constructor if singleton is not desired:
  // SseClient() : _baseUrl = AppConfig.apiBaseUrl;


  /// Connects to an SSE endpoint and streams parsed events of type [T].
  ///
  /// Handles base URL construction, authentication, and event parsing using flutter_client_sse.
  ///
  /// - [path]: The relative path to the SSE endpoint (e.g., '/novels/import/jobId/status').
  /// - [parser]: A function that takes a JSON map and returns an object of type [T].
  /// - [eventName]: (Optional) The specific SSE event name to listen for. Defaults to 'message'.
  /// - [queryParams]: (Optional) Query parameters to add to the URL.
  /// - [method]: The HTTP method (defaults to GET).
  /// - [body]: The request body for POST requests.
  /// - [connectionId]: Optional. An identifier for this connection. If not provided, a random ID will be generated.
  /// - [timeout]: Optional. Timeout duration for the stream. If not provided, no timeout is applied.
  Stream<T> streamEvents<T>({
    required String path,
    required T Function(Map<String, dynamic>) parser,
    String? eventName = 'message', // Default event name to filter
    Map<String, String>? queryParams,
    SSERequestType method = SSERequestType.GET, // Default to GET
    Map<String, dynamic>? body, // For POST requests
    String? connectionId,
    Duration? timeout,
  }) {
    final controller = StreamController<T>();
    final cid = connectionId ?? 'conn_${DateTime.now().millisecondsSinceEpoch}_${_activeConnections.length}';

    try {
      // 1. Prepare URL
      final fullPath = path.startsWith('/') ? path : '/$path';
      final uri = Uri.parse('$_baseUrl$fullPath');
      final urlWithParams = queryParams != null ? uri.replace(queryParameters: queryParams) : uri;
      final urlString = urlWithParams.toString(); // flutter_client_sse uses String URL
      AppLogger.i(_tag, '[SSE] Connecting via ${method.name} to endpoint: $urlString');
      // 针对设定生成等POST流，若发生错误/完成，需全局取消以阻止插件自动重连
      final bool shouldGlobalUnsubscribe = method == SSERequestType.POST && fullPath.contains('/setting-generation');
      final String retryKey = '${method.name}:$fullPath';
      // 冷却窗口：1分钟内达到阈值则熔断
      const int maxRetries = 3;
      const Duration retryWindow = Duration(minutes: 1);
      void _resetRetryIfWindowPassed() {
        final existing = _retryStates[retryKey];
        if (existing != null) {
          if (DateTime.now().difference(existing.firstErrorAt) > retryWindow) {
            _retryStates.remove(retryKey);
          }
        }
      }
      _resetRetryIfWindowPassed();

      // 2. Prepare Headers & Authentication
      final authToken = AppConfig.authToken;
      
      final headers = {
        // Accept and Cache-Control might be added automatically by the package,
        // but explicitly adding them is safer.
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        // Add content-type if needed for POST
        if (method == SSERequestType.POST && body != null)
           'Content-Type': 'application/json',
      };
      
      // 🔧 修复：在开发环境中允许无token连接，生产环境中仍要求token
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
        AppLogger.d(_tag, '[SSE] Added Authorization header');
      } else if (AppConfig.environment == Environment.production) {
        AppLogger.e(_tag, '[SSE] Auth token is null in production environment');
        throw ApiException(401, 'Authentication token is missing');
      } else {
        AppLogger.w(_tag, '[SSE] Warning: No auth token in development environment, proceeding without Authorization header');
      }
      
      // 🔧 新增：添加用户ID头部（与API客户端保持一致）
      final userId = AppConfig.userId;
      if (userId != null) {
        headers['X-User-Id'] = userId;
        AppLogger.d(_tag, '[SSE] Added X-User-Id header: $userId');
      } else {
        AppLogger.w(_tag, '[SSE] Warning: X-User-Id header not set (userId is null)');
      }
      
      AppLogger.d(_tag, '[SSE] Headers: $headers');
      if (body != null) {
         AppLogger.d(_tag, '[SSE] Body: $body');
      }


      // 3. Subscribe using flutter_client_sse
      // This method directly returns the stream subscription management is handled internally.
      // We listen to it and push data/errors into our controller.
      late StreamSubscription sseSubscription; // 预声明变量
      sseSubscription = SSEClient.subscribeToSSE(
        method: method,
        url: urlString,
        header: headers,
        body: body,
      ).listen(
        (event) {
          AppLogger.v(_tag, '[SSE] Raw Event: ID=${event.id}, Event=${event.event}, DataLen=${event.data?.length ?? 0}');
          //TODO调试
          //AppLogger.v(_tag, '[SSE] Raw Event: ID=${event.id}, Event=${event.event}, Data=${event.data}');

          // 处理心跳消息
          if (event.id != null && event.id!.startsWith('heartbeat-')) {
            //AppLogger.v(_tag, '[SSE] 收到心跳消息: ${event.id}');
            return; // 跳过心跳处理
          }

          // Determine event name (treat null/empty as 'message')
          final currentEventName = (event.event == null || event.event!.isEmpty) ? 'message' : event.event;

          // 处理complete事件 - 这是流式生成结束的标志
          if (currentEventName == 'complete') {
            AppLogger.i(_tag, '[SSE] 收到complete事件，表示流式生成已完成');
            // 🚀 修复：发送结束信号给下游，而不是直接关闭
            try {
              final json = jsonDecode(event.data ?? '{}');
              if (json is Map<String, dynamic> && json.containsKey('data') && json['data'] == '[DONE]') {
                AppLogger.i(_tag, '[SSE] 收到[DONE]标记，发送结束信号给下游');
                
                // 🚀 发送一个带有finishReason的结束信号
                final endSignal = {
                  'id': 'stream_end_${DateTime.now().millisecondsSinceEpoch}',
                  'content': '',
                  'finishReason': 'stop',
                  'isComplete': true,
                };
                
                final parsedEndSignal = parser(endSignal);
                if (!controller.isClosed) {
                  controller.add(parsedEndSignal);
                  // 🚀 修复：不再主动取消底层连接，避免插件层自动重连
                  // try { sseSubscription.cancel(); } catch (_) {}
                  // _activeConnections.remove(cid);
                  // if (shouldGlobalUnsubscribe) {
                  //   try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
                  // }
                  // 延迟关闭，确保下游能收到结束信号
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (!controller.isClosed) {
                      controller.close();
                    }
                  });
                }
                return;
              }
            } catch (e) {
              AppLogger.e(_tag, '[SSE] 解析complete事件数据失败', e);
            }
            
            // 🚀 如果解析失败，也要发送结束信号
            try {
              final endSignal = {
                'id': 'stream_end_${DateTime.now().millisecondsSinceEpoch}',
                'content': '',
                'finishReason': 'stop',
                'isComplete': true,
              };
              
              final parsedEndSignal = parser(endSignal);
              if (!controller.isClosed) {
                controller.add(parsedEndSignal);
                // 🚀 修复：不再主动取消底层连接，避免插件层自动重连
                // try { sseSubscription.cancel(); } catch (_) {}
                // _activeConnections.remove(cid);
                // if (shouldGlobalUnsubscribe) {
                //   try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
                // }
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (!controller.isClosed) {
                    controller.close();
                  }
                });
              }
            } catch (parseError) {
              AppLogger.e(_tag, '[SSE] 发送结束信号失败', parseError);
              if (!controller.isClosed) {
                controller.close();
              }
            }
            return; // 无论如何都跳过complete事件的后续处理
          }

          // Filter by expected event name
          if (eventName != null && currentEventName != eventName) {
            //AppLogger.v(_tag, '[SSE] Skipping event name: $currentEventName (Expected: $eventName)');
            return; // Skip this event
          }

          final data = event.data;
          if (data == null || data.isEmpty || data == '[DONE]') {
             //AppLogger.v(_tag, '[SSE] Skipping empty or [DONE] data.');
            return; // Skip this event
          }

          // 检查特殊结束标记 "}"
          if (data == '}' || data.trim() == '}') {
            AppLogger.i(_tag, '[SSE] 检测到特殊结束标记 "}"，关闭流');
            try { sseSubscription.cancel(); } catch (_) {}
            _activeConnections.remove(cid);
            if (shouldGlobalUnsubscribe) {
              try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
            }
            if (!controller.isClosed) {
              controller.close();
            }
            return;
          }

          // Parse data
          try {
            final json = jsonDecode(data);
            if (json is Map<String, dynamic>) {
              AppLogger.v(_tag, '[SSE] JSON Map keys: ${json.keys.join(',')}');
              // 检查JSON对象中是否包含特殊结束标记
              if (json['content'] == '}' || 
                  (json['finishReason'] != null && json['finishReason'].toString().isNotEmpty)) {
                AppLogger.i(_tag, '[SSE] 检测到JSON中的结束标记: content="${json['content']}", finishReason=${json['finishReason']}');
                try { sseSubscription.cancel(); } catch (_) {}
                _activeConnections.remove(cid);
                if (shouldGlobalUnsubscribe) {
                  try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
                }
                if (!controller.isClosed) {
                  controller.close();
                }
                return;
              }
              
              final parsedData = parser(json);
              //AppLogger.v(_tag, '[SSE] Parsed data for event \'$currentEventName\': $parsedData');
              if (!controller.isClosed) {
                controller.add(parsedData); // Add parsed data to our stream
              }
            } else {
              AppLogger.w(_tag, '[SSE] Event data is not a JSON object: $data');
            }
          } catch (e, stack) {
            AppLogger.e(_tag, '[SSE] Failed to parse JSON data: $data', e, stack);
             if (!controller.isClosed) {
                // 🚀 修复：保持原始异常类型，特别是 InsufficientCreditsException
                if (e is InsufficientCreditsException) {
                  AppLogger.w(_tag, '[SSE] 保持积分不足异常类型不变');
                  controller.addError(e, stack);
                } else {
                  // Report parsing errors through the stream
                  controller.addError(ApiException(-1, 'Failed to parse SSE data: $e'), stack);
                }
             }
          }
        },
        onError: (error, stackTrace) {
          AppLogger.e(_tag, '[SSE] Stream error received', error, stackTrace);
          
          // 🔧 新增：检查是否为不可恢复的网络错误 & 对 POST 端点设置最多重试3次
          final bool isPostMethod = method == SSERequestType.POST;
          bool shouldStopRetry;
          if (isPostMethod && shouldGlobalUnsubscribe) {
            // ✅ 设定生成类POST流属于一次性短流，收到错误（包括 AbortError）后不应重连
            shouldStopRetry = true;
          } else {
            shouldStopRetry = _shouldStopRetryOnError(error);
          }
          if (shouldStopRetry) {
            AppLogger.w(_tag, '[SSE] 检测到不可恢复的网络错误，停止重试: $error');
            // 取消订阅以停止自动重试
            sseSubscription.cancel();
            if (shouldGlobalUnsubscribe) {
              try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
            }
          }
          
          if (!controller.isClosed) {
            // Convert to ApiException for consistency
            controller.addError(ApiException(-1, 'SSE stream error: $error'), stackTrace);
            // 仅在停止重试时才关闭下游，允许在窗口内继续尝试
            if (shouldStopRetry) {
              controller.close();
            }
          }
          // 移除连接
          _activeConnections.remove(cid);
        },
        onDone: () {
          AppLogger.i(_tag, '[SSE] Stream finished (onDone received).');
          if (!controller.isClosed) {
            controller.close(); // Close controller when the source stream is done
          }
          // 移除连接
          _activeConnections.remove(cid);
        },
      );

      // 保存此连接以便于后续管理
      _activeConnections[cid] = sseSubscription;
      AppLogger.i(_tag, '[SSE] Connection $cid has been registered. Active connections: ${_activeConnections.length}');

      // Handle cancellation of the downstream listener
      controller.onCancel = () {
         AppLogger.i(_tag, '[SSE] Downstream listener cancelled. Cancelling SSE subscription for connection $cid.');
         sseSubscription.cancel();
         // 移除连接
         _activeConnections.remove(cid);
         if (shouldGlobalUnsubscribe) {
           try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
         }
         // Ensure controller is closed if not already
         if (!controller.isClosed) {
            controller.close();
         }
      };

    } catch (e, stack) {
      // Catch synchronous errors during setup (e.g., URI parsing, initial auth check)
      AppLogger.e(_tag, '[SSE] Setup Error', e, stack);
      controller.addError(
          e is ApiException ? e : ApiException(-1, 'SSE setup failed: $e'), stack);
      controller.close();
    }

    // 应用超时（如果指定）
    if (timeout != null) {
      return controller.stream.timeout(
        timeout,
        onTimeout: (sink) {
          AppLogger.w(_tag, '[SSE] Stream timeout after ${timeout.inSeconds} seconds for connection $cid');
          // 主动取消SSE连接
          cancelConnection(cid);
          // 发送超时错误
          sink.addError(
            ApiException(-1, 'SSE stream timeout after ${timeout.inSeconds} seconds'),
            StackTrace.current,
          );
          sink.close();
        },
      );
    } else {
      return controller.stream;
    }
  }

  /// 取消特定连接
  /// 
  /// - [connectionId]: The ID of the connection to cancel
  /// - 返回: True if connection was found and cancelled, false otherwise
  Future<bool> cancelConnection(String connectionId) async {
    final connection = _activeConnections[connectionId];
    if (connection != null) {
      AppLogger.i(_tag, '[SSE] Manually cancelling connection $connectionId');
      await connection.cancel();
      _activeConnections.remove(connectionId);
      return true;
    }
    AppLogger.w(_tag, '[SSE] Connection $connectionId not found or already closed');
    return false;
  }
  
  /// 取消所有活跃连接
  Future<void> cancelAllConnections() async {
    AppLogger.i(_tag, '[SSE] Cancelling all active connections (count: ${_activeConnections.length})');
    
    // 创建一个连接ID列表，以避免在迭代过程中修改集合
    final connectionIds = _activeConnections.keys.toList();
    
    for (final id in connectionIds) {
      try {
        final connection = _activeConnections[id];
        if (connection != null) {
          await connection.cancel();
          _activeConnections.remove(id);
          AppLogger.d(_tag, '[SSE] Cancelled connection $id');
        }
      } catch (e) {
        AppLogger.e(_tag, '[SSE] Error cancelling connection $id', e);
      }
    }
    
    AppLogger.i(_tag, '[SSE] All connections cancelled. Remaining: ${_activeConnections.length}');
  }
  
  /// 获取活跃连接数
  int get activeConnectionCount => _activeConnections.length;
  
  /// 检查是否应该因为特定错误而停止重试
  /// 
  /// 规则：
  /// - POST 方法：一律不重试（避免 /start 在后端重启后被重复触发）
  /// - ClientException: Failed to fetch - 服务器不可达，停止重试
  /// - ClientException: network error - 也停止重试（后端重启期间常见，避免刷屏与重复日志）
  /// - 连接拒绝/重置/关闭、502/503/404：停止重试
  /// - 其他错误类型继续重试
  bool _shouldStopRetryOnError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // 检查特定的错误模式
    if (errorString.contains('clientexception') && errorString.contains('failed to fetch')) {
      AppLogger.i(_tag, '[SSE] 检测到 "Failed to fetch" 错误，判定为服务器不可达');
      return true;
    }
    
    if (errorString.contains('clientexception') && errorString.contains('network error')) {
      AppLogger.i(_tag, '[SSE] 检测到通用network error，停止重试以避免后端重启期间重复请求');
      return true;
    }
    
    // ✅ 将 AbortError 视为期望的终止（例如收到 complete 后主动取消底层连接）
    if (errorString.contains('aborterror') || errorString.contains('body stream buffer was aborted')) {
      AppLogger.i(_tag, '[SSE] 检测到 AbortError/BodyStreamBuffer aborted，停止重试');
      return true;
    }

    // 检查连接被拒绝的错误
    if (errorString.contains('connection refused') || 
        errorString.contains('connection reset') ||
        errorString.contains('connection closed')) {
      AppLogger.i(_tag, '[SSE] 检测到连接被拒绝/重置/关闭，判定为服务器不可达');
      return true;
    }
    
    // 检查 HTTP 404、503 等明确的服务错误
    if (errorString.contains('404') || errorString.contains('503') || errorString.contains('502')) {
      AppLogger.i(_tag, '[SSE] 检测到 HTTP 服务错误，判定为服务器不可达');
      return true;
    }
    
    // 其他错误继续重试（如临时网络波动）
    AppLogger.d(_tag, '[SSE] 错误类型允许重试: $error');
    return false;
  }
}
