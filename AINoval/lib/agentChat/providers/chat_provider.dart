/// 聊天状态管理Provider
/// Chat state management provider

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../config/constants.dart';

/// 聊天Provider
/// Chat provider
class ChatProvider with ChangeNotifier {
  List<Conversation> _conversations = [];
  String _activeConversationId = '';
  String _currentSnapshotId = '';
  List<Reference> _references = [];
  
  // Getters
  List<Conversation> get conversations => _conversations;
  String get activeConversationId => _activeConversationId;
  String get currentSnapshotId => _currentSnapshotId;
  List<Reference> get references => _references;
  
  Conversation? get activeConversation {
    return _conversations.firstWhere(
      (c) => c.id == _activeConversationId,
      orElse: () => _conversations.isNotEmpty ? _conversations.first : 
        Conversation(
          id: 'empty',
          title: '空对话',
          messages: [],
          snapshots: [],
        ),
    );
  }
  
  /// 初始化
  void initialize() {
    final initId = DateTime.now().millisecondsSinceEpoch.toString();
    _conversations = [
      Conversation(
        id: initId,
        title: '第一章创作',
        messages: [],
        snapshots: [
          Snapshot(
            id: 'init-$initId',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            label: '对话开始',
            description: '初始化对话',
            type: SnapshotType.system,
          ),
        ],
      ),
    ];
    _activeConversationId = initId;
    _currentSnapshotId = 'init-$initId';
    
    // 初始引用
    _references = [
      Reference(id: 'ref-1', type: CitationType.setting, number: 1, title: '主角设定：张明'),
      Reference(id: 'ref-2', type: CitationType.chapter, number: 3, title: '第三章：地下室对峙'),
    ];
    
    notifyListeners();
  }
  
  /// 新建对话
  void createConversation() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final conversation = Conversation(
      id: id,
      title: '新对话 ${_conversations.length + 1}',
      messages: [],
      snapshots: [
        Snapshot(
          id: 'init-$id',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          label: '对话开始',
          description: '初始化对话',
          type: SnapshotType.system,
        ),
      ],
    );
    _conversations.add(conversation);
    _activeConversationId = id;
    _currentSnapshotId = 'init-$id';
    notifyListeners();
  }
  
  /// 切换对话
  void switchConversation(String conversationId) {
    _activeConversationId = conversationId;
    final conversation = activeConversation;
    if (conversation != null && conversation.snapshots.isNotEmpty) {
      _currentSnapshotId = conversation.snapshots.last.id;
    }
    notifyListeners();
  }
  
  /// 关闭对话
  void closeConversation(String conversationId) {
    if (_conversations.length <= 1) return;
    
    _conversations.removeWhere((c) => c.id == conversationId);
    if (_activeConversationId == conversationId) {
      _activeConversationId = _conversations.first.id;
      _currentSnapshotId = _conversations.first.snapshots.last.id;
    }
    notifyListeners();
  }
  
  /// 添加消息
  void addMessage(Message message) {
    _conversations = _conversations.map((conv) {
      if (conv.id == _activeConversationId) {
        return conv.copyWith(
          messages: [...conv.messages, message],
        );
      }
      return conv;
    }).toList();
    notifyListeners();
  }
  
  /// 更新消息
  void updateMessage(String messageId, Message updatedMessage) {
    _conversations = _conversations.map((conv) {
      if (conv.id == _activeConversationId) {
        return conv.copyWith(
          messages: conv.messages.map((m) => m.id == messageId ? updatedMessage : m).toList(),
        );
      }
      return conv;
    }).toList();
    notifyListeners();
  }
  
  /// 创建快照
  String createSnapshot(String label, String description, String type) {
    final snapshotId = 'snapshot-${DateTime.now().millisecondsSinceEpoch}';
    _conversations = _conversations.map((conv) {
      if (conv.id == _activeConversationId) {
        return conv.copyWith(
          snapshots: [
            ...conv.snapshots,
            Snapshot(
              id: snapshotId,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              label: label,
              description: description,
              type: type,
            ),
          ],
        );
      }
      return conv;
    }).toList();
    _currentSnapshotId = snapshotId;
    notifyListeners();
    return snapshotId;
  }
  
  /// 回退到快照
  void restoreSnapshot(String snapshotId) {
    _conversations = _conversations.map((conv) {
      if (conv.id == _activeConversationId) {
        return conv.rollbackToSnapshot(snapshotId);
      }
      return conv;
    }).toList();
    _currentSnapshotId = snapshotId;
    notifyListeners();
  }
  
  /// 添加引用
  void addReference(Reference reference) {
    _references.add(reference);
    notifyListeners();
  }
  
  /// 删除引用
  void removeReference(String referenceId) {
    _references.removeWhere((r) => r.id == referenceId);
    notifyListeners();
  }
  
  /// 回退消息（删除该消息及之后的所有消息）
  void rollbackMessage(String messageId) {
    _conversations = _conversations.map((conv) {
      if (conv.id == _activeConversationId) {
        final messageIndex = conv.messages.indexWhere((m) => m.id == messageId);
        if (messageIndex == -1) return conv;
        
        final newMessages = conv.messages.sublist(0, messageIndex);
        final snapshotIndex = (messageIndex * 2).clamp(0, conv.snapshots.length - 1);
        final newSnapshots = conv.snapshots.sublist(0, snapshotIndex + 1);
        
        return conv.copyWith(
          messages: newMessages,
          snapshots: newSnapshots,
        );
      }
      return conv;
    }).toList();
    
    final conversation = activeConversation;
    if (conversation != null && conversation.snapshots.isNotEmpty) {
      _currentSnapshotId = conversation.snapshots.last.id;
    }
    notifyListeners();
  }
  
  /// 编辑消息
  void editMessage(String messageId, String newContent) {
    // 先回退到该消息之前
    rollbackMessage(messageId);
    notifyListeners();
  }
}




