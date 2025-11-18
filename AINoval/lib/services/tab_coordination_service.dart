import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:ainoval/utils/logger.dart';
import 'package:uuid/uuid.dart';

/// 跨标签页协调服务
/// 
/// 功能：
/// 1. 选举一个"主标签页"负责建立SSE连接
/// 2. 主标签页通过BroadcastChannel向其他标签页转发SSE事件
/// 3. 主标签页关闭时，自动选举新的主标签页
/// 
/// 使用场景：
/// - 多个标签页只需要一个SSE连接
/// - 避免达到服务器连接数限制
/// - 减少网络资源消耗
class TabCoordinationService {
  static final TabCoordinationService _instance = TabCoordinationService._internal();
  factory TabCoordinationService() => _instance;
  TabCoordinationService._internal();

  static const String _tag = 'TabCoordination';
  
  // BroadcastChannel 用于标签页间通信
  html.BroadcastChannel? _channel;
  static const String _channelName = 'ainoval_tabs';
  
  // 当前标签页ID
  final String _tabId = const Uuid().v4();
  
  // 主标签页ID（从localStorage读取）
  String? _leaderTabId;
  
  // 心跳定时器
  Timer? _heartbeatTimer;
  Timer? _leaderCheckTimer;
  
  // SSE事件流控制器（供其他标签页订阅）
  final StreamController<Map<String, dynamic>> _sseEventController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // 是否已初始化
  bool _initialized = false;
  
  // 状态回调
  Function(bool isLeader)? onLeadershipChanged;
  
  // 🔧 健康状态监控
  int _heartbeatsMissed = 0; // 错过的心跳次数
  DateTime? _lastLeaderHeartbeatTime; // 上次收到主标签页心跳时间
  int _leadershipTransferCount = 0; // 主权转移次数
  
  /// 初始化跨标签页协调
  Future<void> initialize() async {
    if (_initialized) {
      AppLogger.i(_tag, '已初始化，跳过重复初始化');
      return;
    }
    
    try {
      // 1. 创建BroadcastChannel
      _channel = html.BroadcastChannel(_channelName);
      _channel!.addEventListener('message', _handleMessage);
      AppLogger.i(_tag, '✅ BroadcastChannel已创建: $_channelName, 标签页ID: $_tabId');
      
      // 2. 尝试成为主标签页
      await _tryBecomeLeader();
      
      // 3. 启动心跳（每5秒）
      _startHeartbeat();
      
      // 4. 启动主标签页检查（每10秒）
      _startLeaderCheck();
      
      // 5. 监听页面关闭事件
      html.window.addEventListener('beforeunload', _handleBeforeUnload);
      
      _initialized = true;
      AppLogger.i(_tag, '✅ 跨标签页协调服务初始化完成 [标签页ID: $_tabId, 当前角色: ${isLeader ? "主标签页" : "从属标签页"}]');
    } catch (e, st) {
      AppLogger.e(_tag, '❌ 初始化失败，将降级为独立模式（每个标签页独立建立SSE连接）', e, st);
      // 降级：如果BroadcastChannel不支持，每个标签页独立工作
      _initialized = false;
      // 🔧 尝试记录失败原因
      if (e.toString().contains('BroadcastChannel')) {
        AppLogger.w(_tag, '⚠️ 浏览器不支持BroadcastChannel API，需要Chrome 54+, Firefox 38+, Safari 15.4+');
      }
    }
  }
  
  /// 尝试成为主标签页
  Future<void> _tryBecomeLeader() async {
    final storage = html.window.localStorage;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 读取当前主标签页信息
    final leaderInfo = storage['ainoval_leader_tab'];
    
    if (leaderInfo == null) {
      // 没有主标签页，成为主标签页
      await _becomeLeader();
      return;
    }
    
    try {
      final info = jsonDecode(leaderInfo) as Map<String, dynamic>;
      final leaderId = info['tabId'] as String?;
      final lastHeartbeat = info['lastHeartbeat'] as int?;
      
      if (leaderId == null || lastHeartbeat == null) {
        await _becomeLeader();
        return;
      }
      
      // 检查主标签页是否还活着（15秒内有心跳）
      final heartbeatAge = now - lastHeartbeat;
      if (heartbeatAge > 15000) {
        AppLogger.w(_tag, '检测到主标签页超时（心跳延迟${heartbeatAge}ms > 15000ms），接管主权');
        await _becomeLeader();
        return;
      }
      
      // 主标签页正常，成为从属标签页
      _leaderTabId = leaderId;
      _lastLeaderHeartbeatTime = DateTime.fromMillisecondsSinceEpoch(lastHeartbeat);
      AppLogger.i(_tag, '当前为从属标签页 [主标签页: ${leaderId.substring(0, 8)}..., 心跳延迟: ${heartbeatAge}ms]');
      onLeadershipChanged?.call(false);
      
      // 向主标签页发送加入消息
      _broadcast({
        'type': 'tab_joined',
        'tabId': _tabId,
        'timestamp': now,
      });
    } catch (e) {
      AppLogger.e(_tag, '解析主标签页信息失败', e);
      await _becomeLeader();
    }
  }
  
  /// 成为主标签页
  Future<void> _becomeLeader() async {
    final wasLeader = isLeader;
    _leaderTabId = _tabId;
    await _updateLeaderHeartbeat();
    _heartbeatsMissed = 0;
    _lastLeaderHeartbeatTime = DateTime.now();
    
    if (!wasLeader) {
      _leadershipTransferCount++;
      AppLogger.i(_tag, '🎖️ 成为主标签页 [标签页ID: ${_tabId.substring(0, 8)}..., 主权转移次数: $_leadershipTransferCount]');
    } else {
      AppLogger.d(_tag, '维持主标签页身份');
    }
    
    onLeadershipChanged?.call(true);
    
    // 广播选举结果
    _broadcast({
      'type': 'leader_elected',
      'tabId': _tabId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  /// 更新主标签页心跳
  Future<void> _updateLeaderHeartbeat() async {
    if (!isLeader) return;
    
    final storage = html.window.localStorage;
    storage['ainoval_leader_tab'] = jsonEncode({
      'tabId': _tabId,
      'lastHeartbeat': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isLeader) {
        try {
          _updateLeaderHeartbeat();
          _broadcast({
            'type': 'heartbeat',
            'tabId': _tabId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          AppLogger.v(_tag, '💓 发送主标签页心跳');
        } catch (e) {
          AppLogger.e(_tag, '发送心跳失败', e);
        }
      }
    });
  }
  
  /// 启动主标签页检查
  void _startLeaderCheck() {
    _leaderCheckTimer?.cancel();
    _leaderCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!isLeader) {
        // 从属标签页检查主标签页是否还活着
        final storage = html.window.localStorage;
        final leaderInfo = storage['ainoval_leader_tab'];
        
        if (leaderInfo == null) {
          await _becomeLeader();
          return;
        }
        
        try {
          final info = jsonDecode(leaderInfo) as Map<String, dynamic>;
          final lastHeartbeat = info['lastHeartbeat'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          if (lastHeartbeat == null || now - lastHeartbeat > 15000) {
            _heartbeatsMissed++;
            final missedDuration = lastHeartbeat != null ? now - lastHeartbeat : 0;
            AppLogger.w(_tag, '主标签页失联（心跳延迟${missedDuration}ms，累计错过${_heartbeatsMissed}次心跳），发起选举');
            await _becomeLeader();
          } else {
            // 主标签页正常，重置错过计数
            if (_heartbeatsMissed > 0) {
              AppLogger.i(_tag, '主标签页恢复正常，重置错过计数（之前累计错过${_heartbeatsMissed}次）');
              _heartbeatsMissed = 0;
            }
          }
        } catch (e) {
          AppLogger.e(_tag, '检查主标签页失败', e);
        }
      }
    });
  }
  
  /// 处理标签页间消息
  void _handleMessage(html.Event event) {
    if (event is! html.MessageEvent) return;
    
    try {
      final data = event.data;
      if (data is! String) return;
      
      final message = jsonDecode(data) as Map<String, dynamic>;
      final type = message['type'] as String?;
      final fromTabId = message['tabId'] as String?;
      
      // 忽略自己发送的消息
      if (fromTabId == _tabId) return;
      
      switch (type) {
        case 'heartbeat':
          // 收到主标签页心跳
          if (fromTabId != null) {
            _leaderTabId = fromTabId;
            _lastLeaderHeartbeatTime = DateTime.now();
            _heartbeatsMissed = 0;
            AppLogger.v(_tag, '💓 收到主标签页心跳 [来自: ${fromTabId.substring(0, 8)}...]');
          }
          break;
          
        case 'leader_elected':
          // 新的主标签页选举成功
          if (fromTabId != null) {
            final oldLeader = _leaderTabId;
            _leaderTabId = fromTabId;
            _lastLeaderHeartbeatTime = DateTime.now();
            _heartbeatsMissed = 0;
            AppLogger.i(_tag, '收到选举通知 [新主标签页: ${fromTabId.substring(0, 8)}..., 旧主标签页: ${oldLeader?.substring(0, 8) ?? "无"}]');
            if (fromTabId != _tabId) {
              onLeadershipChanged?.call(false);
            }
          }
          break;
          
        case 'sse_event':
          // 收到SSE事件（从主标签页转发）
          if (!isLeader) {
            final eventData = message['data'] as Map<String, dynamic>?;
            if (eventData != null) {
              final eventType = eventData['type'] ?? 'UNKNOWN';
              AppLogger.v(_tag, '收到转发的SSE事件: $eventType');
              _sseEventController.add(eventData);
            } else {
              AppLogger.w(_tag, '收到空的SSE事件数据');
            }
          } else {
            AppLogger.d(_tag, '主标签页忽略自己发送的SSE事件');
          }
          break;
          
        case 'tab_joined':
          // 新标签页加入
          AppLogger.i(_tag, '新标签页加入 [标签页ID: ${fromTabId?.substring(0, 8) ?? "未知"}]');
          break;
          
        case 'leader_left':
          // 主标签页主动离开
          if (fromTabId == _leaderTabId) {
            AppLogger.w(_tag, '主标签页主动离开 [标签页ID: ${fromTabId?.substring(0, 8) ?? "未知"}]，准备发起选举');
            // 短暂延迟后发起选举，避免多个标签页同时竞选
            Future.delayed(Duration(milliseconds: 50 * (fromTabId?.hashCode.abs() ?? 0) % 200), () async {
              if (!isLeader) {
                await _tryBecomeLeader();
              }
            });
          }
          break;
          
        default:
          AppLogger.d(_tag, '收到未知类型的消息: $type');
      }
    } catch (e, st) {
      AppLogger.e(_tag, '处理跨标签页消息失败', e, st);
    }
  }
  
  /// 处理页面关闭
  void _handleBeforeUnload(html.Event event) {
    if (isLeader) {
      // 主标签页关闭，清除localStorage中的主标签页信息
      AppLogger.i(_tag, '主标签页关闭，释放主权');
      html.window.localStorage.remove('ainoval_leader_tab');
      
      // 广播主标签页离开消息
      _broadcast({
        'type': 'leader_left',
        'tabId': _tabId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }
  
  /// 广播消息到其他标签页
  void _broadcast(Map<String, dynamic> message) {
    if (_channel == null) return;
    
    try {
      _channel!.postMessage(jsonEncode(message));
    } catch (e) {
      AppLogger.e(_tag, '广播消息失败', e);
    }
  }
  
  /// 转发SSE事件到其他标签页（仅主标签页调用）
  void forwardSseEvent(Map<String, dynamic> event) {
    if (!isLeader) {
      AppLogger.w(_tag, '⚠️ 非主标签页不应调用forwardSseEvent，当前主标签页: ${_leaderTabId?.substring(0, 8) ?? "未知"}');
      return;
    }
    
    try {
      _broadcast({
        'type': 'sse_event',
        'tabId': _tabId,
        'data': event,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final eventType = event['type'] ?? 'UNKNOWN';
      AppLogger.v(_tag, '转发SSE事件: $eventType');
    } catch (e, st) {
      AppLogger.e(_tag, '转发SSE事件失败', e, st);
    }
  }
  
  /// 获取SSE事件流（供从属标签页订阅）
  Stream<Map<String, dynamic>> get sseEventStream => _sseEventController.stream;
  
  /// 当前标签页是否为主标签页
  bool get isLeader => _leaderTabId == _tabId;
  
  /// 当前标签页ID
  String get tabId => _tabId;
  
  /// 主标签页ID
  String? get leaderTabId => _leaderTabId;
  
  /// 是否已初始化
  bool get initialized => _initialized;
  
  /// 销毁服务
  void dispose() {
    try {
      _heartbeatTimer?.cancel();
      _leaderCheckTimer?.cancel();
      _channel?.close();
      if (!_sseEventController.isClosed) {
        _sseEventController.close();
      }
      html.window.removeEventListener('beforeunload', _handleBeforeUnload);
      _initialized = false;
      AppLogger.i(_tag, '跨标签页协调服务已销毁 [主权转移次数: $_leadershipTransferCount]');
    } catch (e, st) {
      AppLogger.e(_tag, '销毁服务时发生错误', e, st);
    }
  }
  
  /// 获取健康状态信息（用于调试）
  Map<String, dynamic> getHealthInfo() {
    return {
      'initialized': _initialized,
      'isLeader': isLeader,
      'tabId': _tabId.substring(0, 8),
      'leaderTabId': _leaderTabId?.substring(0, 8),
      'heartbeatsMissed': _heartbeatsMissed,
      'lastLeaderHeartbeatTime': _lastLeaderHeartbeatTime?.toIso8601String(),
      'leadershipTransferCount': _leadershipTransferCount,
    };
  }
}

