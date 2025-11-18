import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ainoval/services/tab_coordination_service.dart';

/// 跨标签页协调调试面板
/// 
/// 用于测试和调试跨标签页协调功能
/// 在开发模式下可以添加到应用的某个角落显示状态
class TabCoordinationDebugPanel extends StatefulWidget {
  const TabCoordinationDebugPanel({super.key});

  @override
  State<TabCoordinationDebugPanel> createState() => _TabCoordinationDebugPanelState();
}

class _TabCoordinationDebugPanelState extends State<TabCoordinationDebugPanel> {
  bool _isExpanded = false;
  bool _isLeader = false;
  String _tabId = '';
  String? _leaderTabId;
  int _receivedEventsCount = 0;
  String _lastEventType = '-';
  
  @override
  void initState() {
    super.initState();
    
    if (kIsWeb && TabCoordinationService().initialized) {
      final service = TabCoordinationService();
      _isLeader = service.isLeader;
      _tabId = service.tabId;
      _leaderTabId = service.leaderTabId;
      
      // 监听角色变更
      service.onLeadershipChanged = (isLeader) {
        if (mounted) {
          setState(() {
            _isLeader = isLeader;
            _leaderTabId = service.leaderTabId;
          });
        }
      };
      
      // 监听转发的事件（从属标签页）
      service.sseEventStream.listen((event) {
        if (mounted) {
          setState(() {
            _receivedEventsCount++;
            _lastEventType = event['type']?.toString() ?? 'unknown';
          });
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !TabCoordinationService().initialized) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: _isExpanded ? 300 : 150,
            minWidth: 150,
          ),
          decoration: BoxDecoration(
            color: _isLeader ? Colors.blue.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isLeader ? Colors.blue : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isLeader ? Colors.blue : Colors.grey,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isLeader ? Icons.star : Icons.tab,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isLeader ? '主标签页' : '从属标签页',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              
              // 详细信息（展开时显示）
              if (_isExpanded) ...[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('标签页ID', _tabId.substring(0, 8)),
                      const SizedBox(height: 4),
                      _buildInfoRow('主标签页', _leaderTabId?.substring(0, 8) ?? '-'),
                      const SizedBox(height: 4),
                      _buildInfoRow('角色', _isLeader ? '主（建立SSE）' : '从（监听转发）'),
                      const SizedBox(height: 4),
                      if (!_isLeader) ...[
                        _buildInfoRow('收到事件', '$_receivedEventsCount 个'),
                        const SizedBox(height: 4),
                        _buildInfoRow('最新事件', _lastEventType),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatusIndicator(
                              '心跳',
                              _isLeader ? '发送中' : '接收中',
                              Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatusIndicator(
                              'SSE',
                              _isLeader ? '已连接' : '未连接',
                              _isLeader ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatusIndicator(String label, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

