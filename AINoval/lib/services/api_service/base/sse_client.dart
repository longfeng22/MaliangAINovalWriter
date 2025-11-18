import 'dart:async';
import 'dart:convert';

import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/services/api_service/base/api_exception.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' as flutter_sse;

// 前向声明，避免循环依赖
// ignore: implementation_imports
import 'package:ainoval/services/auth_service.dart' show AuthService;

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
  
  // AuthService实例（用于处理401错误）
  AuthService? _authService;
  
  // 存储活跃连接，以便于管理
  final Map<String, StreamSubscription> _activeConnections = {};
  final Map<String, _RetryState> _retryStates = {};
  // 全局挂起开关：挂起时任何新建流都直接返回已关闭的流，阻断底层插件重连
  bool _suspended = false;
  
  // 🔧 特殊连接互斥锁：对于/api/tasks/events，同一时间只允许一个连接
  static const String _taskEventsPath = '/api/tasks/events';
  StreamSubscription? _taskEventsConnection;

  // Static instance
  static final SseClient _instance = SseClient._internal();
  // --------------- End Singleton Pattern ---------------

  // Or a simple public constructor if singleton is not desired:
  // SseClient() : _baseUrl = AppConfig.apiBaseUrl;

  /// 设置AuthService实例（用于处理401错误）
  void setAuthService(AuthService authService) {
    _authService = authService;
  }

  /// 挂起所有SSE：阻止后续新建连接
  void suspendAll() {
    if (!_suspended) {
      _suspended = true;
      AppLogger.w(_tag, '[SSE] 全局挂起：将阻断所有新建SSE连接');
    }
  }

  /// 恢复SSE：允许新建连接
  void resumeAll() {
    if (_suspended) {
      _suspended = false;
      AppLogger.i(_tag, '[SSE] 全局恢复：允许新建SSE连接');
    }
  }

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
  }) async* {
    // 挂起状态：直接返回一个已关闭的流，彻底阻断底层 subscribeToSSE
    if (_suspended) {
      AppLogger.w(_tag, '[SSE] 已挂起：拒绝连接 path=$path');
      final controller = StreamController<T>();
      // 立即关闭
      scheduleMicrotask(() => controller.close());
      yield* controller.stream;
      return;
    }
    final controller = StreamController<T>();
    final cid = connectionId ?? 'conn_${DateTime.now().millisecondsSinceEpoch}_${_activeConnections.length}';

    try {
      // 在建立SSE前确保access token足够新鲜（仅GET任务事件或需要认证的流）
      if (method == SSERequestType.GET && path.contains('/api/tasks/events')) {
        try {
          if (_authService != null) {
            final ok = await _authService!.ensureAccessTokenFresh(minValidity: const Duration(seconds: 60));
            if (!ok) {
              AppLogger.w(_tag, '[SSE] 预刷新token失败，拒绝建立SSE');
              // 直接抛出，交由上层处理（通常会触发登出）
              throw ApiException(401, 'Token过期或刷新失败');
            }
          }
        } catch (e) {
          AppLogger.w(_tag, '[SSE] 建连前刷新检查失败: $e');
          throw ApiException(401, 'Token过期或刷新失败');
        }
      }
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
      // 注意：重试计数逻辑已通过 _retryStates 管理，删除未使用的局部阈值变量
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
      
      // 🔧 修复：统一要求token（包括开发环境）；/api/tasks/events 无token直接拒绝，避免未认证建连
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
        AppLogger.d(_tag, '[SSE] Added Authorization header');
      } else {
        // 仅当是非任务事件流，且明确允许匿名（当前无此场景）才可放行
        if (fullPath == '/api/tasks/events') {
          AppLogger.e(_tag, '[SSE] Auth token is null for /api/tasks/events');
          throw ApiException(401, 'Authentication token is missing');
        } else if (method == SSERequestType.POST && body != null) {
          // 其他SSE端点如有匿名需求可在此特判；默认也拒绝
          AppLogger.e(_tag, '[SSE] Auth token is null for SSE endpoint: $fullPath');
          throw ApiException(401, 'Authentication token is missing');
        } else {
          AppLogger.e(_tag, '[SSE] Auth token is null');
          throw ApiException(401, 'Authentication token is missing');
        }
      }
      
      // 🔧 新增：添加用户ID头部（与API客户端保持一致）
      final userId = AppConfig.userId;
      if (userId != null) {
        headers['X-User-Id'] = userId;
        AppLogger.d(_tag, '[SSE] Added X-User-Id header: $userId');
      } else {
        AppLogger.w(_tag, '[SSE] Warning: X-User-Id header not set (userId is null)');
      }
      
      // 🔧 新增：添加客户端版本号（用于版本检查和强制刷新）
      headers['X-Client-Version'] = AppConfig.clientVersion;
      AppLogger.d(_tag, '[SSE] Added X-Client-Version header: ${AppConfig.clientVersion}');
      
      AppLogger.d(_tag, '[SSE] Headers: $headers');
      if (body != null) {
         AppLogger.d(_tag, '[SSE] Body: $body');
      }


      // 3. Subscribe using flutter_client_sse
      // 🔧 对于/api/tasks/events，强制单一连接（连接互斥）
      if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
        // 如果已有活跃连接，先取消
        if (_taskEventsConnection != null) {
          AppLogger.w(_tag, '[SSE] 检测到已存在的任务事件连接，先取消旧连接');
          try {
            _taskEventsConnection!.cancel();
          } catch (_) {}
          _taskEventsConnection = null;
        }
        
        // 全局取消避免旧EventSource残留
        try {
          AppLogger.i(_tag, '[SSE] Pre-unsubscribe before connecting to /api/tasks/events');
          flutter_sse.SSEClient.unsubscribeFromSSE();
        } catch (_) {}
        
        // 等待一小段时间确保旧连接完全关闭
        await Future.delayed(const Duration(milliseconds: 100));
      }
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
                
                // 双保险：如果是任务事件SSE，收到complete时主动挂起并请求登出，避免旧token继续操作
                if (fullPath == _taskEventsPath && _authService != null) {
                  try {
                    suspendAll();
                    // fire-and-forget 登出
                    _authService!.logout().catchError((e) {
                      AppLogger.w(_tag, '[SSE] 收到complete后自动登出失败', e);
                    });
                  } catch (_) {}
                }

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
              
              // 错误JSON短路：包含 code + message 即视为错误事件，不再进入 parser
              if (json.containsKey('code') && json.containsKey('message')) {
                final code = (json['code']?.toString() ?? '').toUpperCase();
                final msg = json['message']?.toString() ?? 'Unknown error';
                if (code == 'PAYMENT_REQUIRED' || msg.contains('积分余额不足')) {
                  controller.addError(InsufficientCreditsException(msg));
                } else {
                  controller.addError(ApiException(-1, msg));
                }
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
                if (e is InsufficientCreditsException || e is ApiException) {
                  AppLogger.w(_tag, '[SSE] 保留原始异常类型: ${e.runtimeType}');
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
          
          // 🚀 重要修复：检查并处理HTTP 402积分不足错误
          final errorString = error.toString();
          ApiException? processedError;
          
          // ✅ 新增：401 未授权（登录失效）处理——立即停止重连并触发全局停止监听
          final lower = errorString.toLowerCase();
          final bool isUnauthorized = errorString.contains('401') ||
              lower.contains('unauthorized') ||
              lower.contains('authentication token is missing');
          if (isUnauthorized) {
            AppLogger.w(_tag, '[SSE] 检测到 401 未授权，停止重试并请求用户重新登录');
            try { sseSubscription.cancel(); } catch (_) {}
            try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
            _activeConnections.remove(cid);
            
            // 🔧 关键修复：调用AuthService的logout，清除认证状态并触发跳转登录页
            if (_authService != null) {
              AppLogger.i(_tag, '[SSE] 执行自动登出以清除过期令牌');
              // 使用fire-and-forget模式调用logout，不阻塞错误处理流程
              _authService!.logout().catchError((e) {
                AppLogger.e(_tag, '[SSE] 自动登出失败', e);
              });
            } else {
              AppLogger.w(_tag, '[SSE] AuthService未设置，无法自动登出');
            }
            
            // 通知上游：登录失效
            if (!controller.isClosed) {
              controller.addError(ApiException(401, '登录已过期，请重新登录'), stackTrace);
              controller.close();
            }
            // 广播：停止全局任务事件监听，避免重复连接风暴
            try { EventBus.instance.fire(const StopTaskEventsListening()); } catch (_) {}
            return;
          }
          
          // 检查是否是积分不足异常（HTTP 402 Payment Required）
          if (errorString.contains('402') || errorString.toLowerCase().contains('payment required')) {
            AppLogger.w(_tag, '[SSE] 检测到积分不足错误 (HTTP 402)');
            // 尝试从错误消息中提取积分信息
            final match = RegExp(r'需要 (\d+) 积分，当前余额 (\d+) 积分').firstMatch(errorString);
            if (match != null) {
              final requiredCredits = int.tryParse(match.group(1) ?? '');
              // 提取当前余额但暂不使用；为避免未使用警告，仅用于丰富提示
              final currentCredits = int.tryParse(match.group(2) ?? '');
              if (currentCredits != null) {
                AppLogger.d(_tag, '[SSE] Parsed current credits from error: $currentCredits');
              }
              final message = '积分余额不足，需要 ${match.group(1)} 积分，当前余额 ${match.group(2)} 积分';
              processedError = InsufficientCreditsException(message, requiredCredits);
            } else {
              // 通用积分不足异常
              processedError = InsufficientCreditsException('积分余额不足，请充值后继续使用');
            }
          }
          
          // 🔧 新增：检查是否为不可恢复的网络错误 & 对 POST 端点设置最多重试3次
          final bool isPostMethod = method == SSERequestType.POST;
          bool shouldStopRetry;
          if (isPostMethod && shouldGlobalUnsubscribe) {
            // ✅ 设定生成类POST流属于一次性短流，收到错误（包括 AbortError）后不应重连
            shouldStopRetry = true;
          } else {
            shouldStopRetry = _shouldStopRetryOnError(error);
          }
          
          // 🚀 积分不足错误也应该停止重试
          if (processedError is InsufficientCreditsException) {
            shouldStopRetry = true;
            AppLogger.w(_tag, '[SSE] 积分不足错误，停止重试');
          }
          
          // 🔧 关键修复：对于/api/tasks/events，任何错误都不应该自动重连！
          // 因为会导致无限重连风暴，应该由上层逻辑（如BLoC）决定何时重连
          if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
            shouldStopRetry = true;
            AppLogger.w(_tag, '[SSE] /api/tasks/events连接发生错误，禁止自动重连: $error');
          }
          
          if (shouldStopRetry) {
            AppLogger.w(_tag, '[SSE] 检测到不可恢复的网络错误，停止重试: $error');
            // 取消订阅以停止自动重试
            sseSubscription.cancel();
            if (shouldGlobalUnsubscribe) {
              try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
            }
            // 🔧 对于任务事件连接，调用全局取消避免自动重连
            if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
              try { 
                flutter_sse.SSEClient.unsubscribeFromSSE();
                _taskEventsConnection = null;
                AppLogger.i(_tag, '[SSE] 已调用全局取消，阻止/api/tasks/events自动重连');
              } catch (_) {}
            }
          }
          
          if (!controller.isClosed) {
            // 🚀 修复：使用处理后的异常或创建通用异常
            final finalError = processedError ?? ApiException(-1, 'SSE stream error: $error');
            controller.addError(finalError, stackTrace);
            // 仅在停止重试时才关闭下游，允许在窗口内继续尝试
            if (shouldStopRetry) {
              controller.close();
            }
          }
          // 移除连接
          _activeConnections.remove(cid);
          // 🔧 清理任务事件连接引用
          if (method == SSERequestType.GET && fullPath == _taskEventsPath && _taskEventsConnection == sseSubscription) {
            _taskEventsConnection = null;
          }
        },
        onDone: () {
          AppLogger.i(_tag, '[SSE] Stream finished (onDone received).');
          // 移除连接
          _activeConnections.remove(cid);
          // 🔧 对于任务事件连接，调用全局取消避免自动重连
          if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
            try { 
              flutter_sse.SSEClient.unsubscribeFromSSE();
              _taskEventsConnection = null;
              AppLogger.i(_tag, '[SSE] /api/tasks/events连接正常关闭，已调用全局取消');
            } catch (_) {}
          }
          if (!controller.isClosed) {
            controller.close(); // Close controller when the source stream is done
          }
        },
      );

      // 保存此连接以便于后续管理
      _activeConnections[cid] = sseSubscription;
      
      // 🔧 如果是任务事件连接，记录到专用字段
      if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
        _taskEventsConnection = sseSubscription;
        AppLogger.i(_tag, '[SSE] 任务事件连接已建立并注册为唯一连接');
      }
      
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
         // 🔧 对于任务事件连接，调用全局取消避免自动重连
         if (method == SSERequestType.GET && fullPath == _taskEventsPath) {
           try { 
             flutter_sse.SSEClient.unsubscribeFromSSE();
             _taskEventsConnection = null;
             AppLogger.i(_tag, '[SSE] /api/tasks/events下游取消，已调用全局取消');
           } catch (_) {}
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
    final stream = timeout != null 
      ? controller.stream.timeout(
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
        )
      : controller.stream;
    
    // 使用 yield* 转发流
    yield* stream;
  }

  /// 取消特定连接
  /// 
  /// - [connectionId]: The ID of the connection to cancel
  /// - 返回: True if connection was found and cancelled, false otherwise
  Future<bool> cancelConnection(String connectionId) async {
    final connection = _activeConnections[connectionId];
    if (connection != null) {
      AppLogger.i(_tag, '[SSE] Manually cancelling connection $connectionId');
      // 双重 unsubscribe 防抖：先全局取消 → 延时 → 再次取消
      try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 180));
      try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
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
    // 双重 unsubscribe 防抖：先全局取消 → 延时 → 再次取消
    try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 180));
    try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}

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
  
  /// 🔧 调试方法：获取所有活跃连接的详情
  /// 仅用于开发环境调试
  Map<String, String> getActiveConnectionsDebugInfo() {
    final info = <String, String>{};
    for (final entry in _activeConnections.entries) {
      final connectionId = entry.key;
      // 尝试推断连接类型
      String connectionType = '未知类型';
      if (connectionId.contains('task')) {
        connectionType = '任务事件连接';
      } else if (connectionId.contains('setting')) {
        connectionType = '设定生成连接';
      } else if (connectionId.contains('import')) {
        connectionType = '导入连接';
      }
      info[connectionId] = connectionType;
    }
    return info;
  }
  
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
