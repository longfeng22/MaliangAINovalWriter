/// 智能体状态管理Provider
/// Agent state management provider

import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../config/constants.dart';
import '../i18n/translations.dart';

/// 智能体Provider
/// Agent provider
class AgentProvider with ChangeNotifier {
  List<Agent> _agents = [];
  String _activeAgentId = 'default';
  String _collaborationMode = CollaborationMode.author;
  
  // Getters
  List<Agent> get agents => _agents;
  String get activeAgentId => _activeAgentId;
  String get collaborationMode => _collaborationMode;
  
  Agent? get activeAgent {
    return _agents.firstWhere(
      (a) => a.id == _activeAgentId,
      orElse: () => _agents.isNotEmpty ? _agents.first : _getDefaultAgent(),
    );
  }
  
  bool get isTeamMode => _collaborationMode == CollaborationMode.team;
  bool get isAuthorMode => _collaborationMode == CollaborationMode.author;
  
  /// 初始化预设智能体
  void initialize(Translations translations) {
    _agents = [
      Agent(
        id: PresetAgentId.defaultAgent,
        name: translations.defaultAgent,
        description: translations.defaultAgentDesc,
        systemPrompt: '你是一个小说创作助手，具备完整的创作和修改功能。',
        toolCategories: [ToolCategory.builtIn],
        builtInTools: ['character-query', 'setting-management', 'chapter-management', 'outline-management'],
        mcpTools: [],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      Agent(
        id: PresetAgentId.chatAgent,
        name: translations.chatAgent,
        description: translations.chatAgentDesc,
        systemPrompt: '你是一个友好的对话助手，专注于与用户交流和讨论。',
        toolCategories: [],
        builtInTools: [],
        mcpTools: [],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      Agent(
        id: PresetAgentId.mcpAgent,
        name: translations.mcpAgent,
        description: translations.mcpAgentDesc,
        systemPrompt: '你是一个增强型创作助手，除了基本功能外，还可以调用MCP工具进行网络搜索和文件操作。',
        toolCategories: [ToolCategory.builtIn, ToolCategory.mcp],
        builtInTools: ['character-query', 'setting-management'],
        mcpTools: ['web-search', 'file-system'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _activeAgentId = PresetAgentId.defaultAgent;
    notifyListeners();
  }
  
  /// 创建智能体
  void createAgent(Agent agent) {
    _agents.add(agent);
    notifyListeners();
  }
  
  /// 更新智能体
  void updateAgent(String agentId, Agent updatedAgent) {
    _agents = _agents.map((agent) {
      if (agent.id == agentId) {
        return updatedAgent.copyWith(
          id: agentId,
          createdAt: agent.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return agent;
    }).toList();
    notifyListeners();
  }
  
  /// 删除智能体
  void deleteAgent(String agentId) {
    _agents.removeWhere((a) => a.id == agentId);
    if (_activeAgentId == agentId && _agents.isNotEmpty) {
      _activeAgentId = _agents.first.id;
    }
    notifyListeners();
  }
  
  /// 切换智能体
  void selectAgent(String agentId) {
    _activeAgentId = agentId;
    notifyListeners();
  }
  
  /// 切换协作模式
  void setCollaborationMode(String mode) {
    _collaborationMode = mode;
    notifyListeners();
  }
  
  /// 获取默认智能体
  Agent _getDefaultAgent() {
    return Agent(
      id: 'default',
      name: '默认智能体',
      systemPrompt: '你是一个AI助手',
      toolCategories: [],
      builtInTools: [],
      mcpTools: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}




