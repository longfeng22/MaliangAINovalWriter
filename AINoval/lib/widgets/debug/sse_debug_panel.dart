import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/services/api_service/base/sse_client.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' as flutter_sse;
import 'package:ainoval/services/auth_service.dart' as auth_service;
import 'package:dio/dio.dart';

/// SSE调试面板
/// 
/// 仅在开发环境可用，用于：
/// 1. 列出当前所有SSE连接
/// 2. 手动关闭特定连接或全部连接（含底层全局unsubscribe）
/// 3. 模拟JWT过期/失效（两种方式：保持连接/先断开再修改）
/// 4. 清除JWT并触发登出（调用后端logout，清理多层缓存）
/// 5. 打印相关操作日志
class SseDebugPanel extends StatefulWidget {
  const SseDebugPanel({Key? key}) : super(key: key);

  @override
  State<SseDebugPanel> createState() => _SseDebugPanelState();
}

class _SseDebugPanelState extends State<SseDebugPanel> {
  final List<String> _logs = [];
  final SseClient _sseClient = SseClient();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addLog('🔧 SSE调试面板已启动');
    _addLog('📊 当前环境: ${AppConfig.environment}');
    _addLog('🔐 当前用户ID: ${AppConfig.userId ?? "未登录"}');
  }

  /// 管理操作：当前用户 tokenVersion +1
  Future<void> _bumpCurrentUserTokenVersion() async {
    final userId = AppConfig.userId;
    if (userId == null || userId.isEmpty) {
      _addLog('⚠️ 未登录，无法执行版本+1');
      return;
    }
    try {
      setState(() { _isLoading = true; });
      _addLog('🛑 请求将当前用户($userId) tokenVersion +1 ...');
      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final token = AppConfig.authToken;
      if (token != null) dio.options.headers['Authorization'] = 'Bearer $token';
      dio.options.headers['X-User-Id'] = userId;
      final resp = await dio.post('/admin/users/$userId/token-version/bump');
      _addLog('✅ 已请求版本+1，响应: ${resp.statusCode}');
      _addLog('ℹ️ 等待SSE按照版本变更收到complete并断开');
    } catch (e) {
      _addLog('❌ 版本+1请求失败: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _addLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 300) {
        _logs.removeLast();
      }
    });
    AppLogger.i('SseDebugPanel', message);
  }

  Map<String, dynamic> _getActiveConnections() {
    try {
      final connections = _sseClient.getActiveConnectionsDebugInfo();
      final count = _sseClient.activeConnectionCount;
      return { 'count': count, 'connections': connections };
    } catch (e) {
      _addLog('❌ 获取连接列表失败: $e');
      return { 'count': 0, 'connections': <String, String>{} };
    }
  }

  Future<void> _closeConnection(String connectionId) async {
    try {
      _addLog('🔌 正在关闭连接: $connectionId');
      setState(() { _isLoading = true; });
      final success = await _sseClient.cancelConnection(connectionId);
      if (success) {
        _addLog('✅ 成功关闭连接: $connectionId');
      } else {
        _addLog('⚠️ 连接不存在或已关闭: $connectionId');
      }
    } catch (e) {
      _addLog('❌ 关闭连接失败: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _closeAllConnections() async {
    try {
      _addLog('🔌 正在关闭所有连接（含全局unsubscribe）...');
      setState(() { _isLoading = true; });
      await _sseClient.cancelAllConnections();
      try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
      _addLog('✅ 已关闭所有连接并调用全局unsubscribe');
    } catch (e) {
      _addLog('❌ 关闭所有连接失败: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _invalidateJWT({required bool disconnectFirst}) async {
    try {
      _addLog('🔐 正在使JWT失效（${disconnectFirst ? '先断开SSE' : '保持现有SSE'}）...');
      setState(() { _isLoading = true; });

      final currentToken = AppConfig.authToken;
      if (currentToken == null) {
        _addLog('⚠️ 当前没有JWT token');
        return;
      }

      if (disconnectFirst) {
        await _sseClient.cancelAllConnections();
        try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
        _addLog('✅ 已先行断开所有SSE连接');
      } else {
        _addLog('ℹ️ 按要求保留现有SSE连接，不做断开');
      }

      final invalidToken = '${currentToken}INVALID';
      AppConfig.setAuthToken(invalidToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', invalidToken);

      _addLog('✅ JWT已修改为无效token');
      _addLog('📋 无效JWT前20位: ${invalidToken.substring(0, 20)}...');
      _addLog('💡 观察SSE行为：若保持连接，将继续收到既有心跳；若发生重连，后端应返回401');
    } catch (e) {
      _addLog('❌ 修改JWT失败: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _clearJWTAndLogout() async {
    try {
      _addLog('🔄 正在清除JWT并执行登出（含全局SSE关闭）...');
      setState(() { _isLoading = true; });

      // 1) 关闭所有SSE（含全局unsubscribe）
      await _sseClient.cancelAllConnections();
      try { flutter_sse.SSEClient.unsubscribeFromSSE(); } catch (_) {}
      _addLog('✅ 已关闭所有SSE连接');

      // 2) 调用后端登出并清理本地多层缓存
      try {
        final svc = context.read<auth_service.AuthService>();
        await svc.logout();
        _addLog('✅ 已调用后端登出并清理本地缓存（token/refresh/userId/username）');
      } catch (e) {
        _addLog('⚠️ 调用后端登出失败，继续清理本地状态: $e');
        // 兜底：本地清理
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');
        await prefs.remove('user_id');
        await prefs.remove('username');
        AppConfig.clearUserState();
        _addLog('✅ 本地缓存已兜底清理');
      }

      _addLog('⚠️ 请确认界面是否弹出登录或切回未登录态（若未响应，属于系统逻辑需后续排查）');
    } catch (e) {
      _addLog('❌ 清除JWT/登出失败: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _clearLogs() {
    setState(() { _logs.clear(); });
    _addLog('🧹 日志已清空');
  }

  Future<void> _copyLogsToClipboard() async {
    try {
      final logsText = _logs.reversed.join('\n');
      await Clipboard.setData(ClipboardData(text: logsText));
      _addLog('📋 日志已复制到剪贴板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已复制到剪贴板'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      _addLog('❌ 复制日志失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = _getActiveConnections();
    final connectionCount = connections['count'] as int;
    final connectionMap = connections['connections'] as Map<String, String>;

    return Dialog(
      backgroundColor: Colors.grey[900],
      child: Container(
        width: 860,
        height: 640,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔧 SSE连接调试面板',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📊 当前状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[300])),
                  const SizedBox(height: 8),
                  Text('活跃连接数: $connectionCount', style: const TextStyle(color: Colors.white70)),
                  Text('用户ID: ${AppConfig.userId ?? "未登录"}', style: const TextStyle(color: Colors.white70)),
                  Text('JWT状态: ${AppConfig.authToken != null ? "已设置" : "未设置"}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新连接列表'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _closeAllConnections,
                  icon: const Icon(Icons.close_fullscreen),
                  label: const Text('关闭所有连接'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _invalidateJWT(disconnectFirst: false),
                  icon: const Icon(Icons.warning_amber),
                  label: const Text('使JWT失效(保持SSE)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _invalidateJWT(disconnectFirst: true),
                  icon: const Icon(Icons.warning),
                  label: const Text('使JWT失效(先断再改)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _clearJWTAndLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('清除JWT并登出'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _clearLogs,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('清空日志'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _copyLogsToClipboard,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制日志'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[700]),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _bumpCurrentUserTokenVersion,
                  icon: const Icon(Icons.no_accounts),
                  label: const Text('让当前用户下线(版本+1)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (connectionCount > 0) ...[
              Text('🔌 活跃连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[300])),
              const SizedBox(height: 8),
              Container(
                height: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
                child: ListView(
                  children: connectionMap.entries.map((entry) {
                    return ListTile(
                      dense: true,
                      title: Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                      subtitle: Text(entry.value, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red, size: 16),
                        onPressed: () => _closeConnection(entry.key),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📝 操作日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[300])),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final line = _logs[index];
                          Color? color;
                          if (line.contains('❌')) color = Colors.red[300];
                          else if (line.contains('⚠️')) color = Colors.orange[300];
                          else if (line.contains('✅')) color = Colors.green[300];
                          else color = Colors.white70;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(line, style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace')),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


