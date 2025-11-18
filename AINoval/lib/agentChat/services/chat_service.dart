/// 聊天服务
/// Chat service
/// 
/// 模拟流式响应、工具调用、思考过程等

import 'dart:async';
import '../models/models.dart';
import '../config/constants.dart';

/// 聊天服务
/// Chat service
class ChatService {
  /// 模拟流式生成响应
  /// Simulate streaming response
  Stream<Message> generateResponse({
    required String messageId,
    required Agent agent,
    required String userMessage,
    bool deepThinking = false,
    bool requireApproval = true,
  }) async* {
    // 初始空消息
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [],
    );
    
    // 根据不同智能体生成不同回答
    if (agent.id == PresetAgentId.chatAgent) {
      // 对话智能体：仅文本
      yield* _generateChatAgentResponse(messageId, agent, userMessage);
    } else if (agent.id == PresetAgentId.mcpAgent) {
      // MCP智能体：增强功能
      yield* _generateMCPAgentResponse(messageId, agent, userMessage, deepThinking, requireApproval);
    } else {
      // 默认智能体：标准创作
      yield* _generateDefaultAgentResponse(messageId, agent, userMessage, deepThinking, requireApproval);
    }
  }
  
  /// 对话智能体响应
  Stream<Message> _generateChatAgentResponse(String messageId, Agent agent, String userMessage) async* {
    await Future.delayed(Duration(milliseconds: 500));
    
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: '很高兴与您交流！关于"$userMessage"，让我分享一些想法...'),
      ],
      timestamp: _getTimestamp(),
    );
    
    await Future.delayed(Duration(milliseconds: 800));
    
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: '很高兴与您交流！关于"$userMessage"，让我分享一些想法...'),
        TextBlock(content: '作为对话助手，我专注于与您讨论创作思路、探讨故事情节，但不能直接修改您的作品。'),
      ],
      timestamp: _getTimestamp(),
    );
  }
  
  /// 默认智能体响应
  Stream<Message> _generateDefaultAgentResponse(
    String messageId,
    Agent agent,
    String userMessage,
    bool deepThinking,
    bool requireApproval,
  ) async* {
    // 文本
    await Future.delayed(Duration(milliseconds: 500));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
      ],
    );
    
    // 工具调用
    await Future.delayed(Duration(milliseconds: 600));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
        ToolBlock(
          toolType: ToolType.view,
          toolName: '角色查询',
          status: ToolStatus.running,
        ),
      ],
    );
    
    await Future.delayed(Duration(milliseconds: 500));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
        ToolBlock(
          toolType: ToolType.view,
          toolName: '角色查询',
          status: ToolStatus.complete,
          duration: '0.3s',
        ),
      ],
    );
    
    // 思考过程
    await Future.delayed(Duration(milliseconds: 700));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
        ToolBlock(
          toolType: ToolType.view,
          toolName: '角色查询',
          status: ToolStatus.complete,
          duration: '0.3s',
        ),
        ThinkingBlock(
          steps: [
            ThinkingStep(
              id: 't1',
              type: ThinkingStepType.plan,
              title: '分析角色信息',
              status: ThinkingStepStatus.thinking,
            ),
          ],
          isExpanded: true,
        ),
      ],
    );
    
    await Future.delayed(Duration(milliseconds: 1500));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
        ToolBlock(
          toolType: ToolType.view,
          toolName: '角色查询',
          status: ToolStatus.complete,
          duration: '0.3s',
        ),
        ThinkingBlock(
          steps: [
            ThinkingStep(id: 't1', type: ThinkingStepType.plan, title: '分析角色信息', status: ThinkingStepStatus.complete),
            ThinkingStep(id: 't2', type: ThinkingStepType.thought, title: '确定修改方向', status: ThinkingStepStatus.complete),
            ThinkingStep(id: 't3', type: ThinkingStepType.observation, title: '整合设定要素', status: ThinkingStepStatus.complete),
          ],
          isExpanded: false,
        ),
      ],
    );
    
    // 批准块或完成
    await Future.delayed(Duration(milliseconds: 500));
    if (requireApproval) {
      yield Message(
        id: messageId,
        role: MessageRole.assistant,
        agentId: agent.id,
        agentName: agent.name,
        blocks: [
          TextBlock(content: deepThinking ? '启用深度思考模式...' : '我现在要了解相关设定信息。'),
          ToolBlock(toolType: ToolType.view, toolName: '角色查询', status: ToolStatus.complete, duration: '0.3s'),
          ThinkingBlock(
            steps: [
              ThinkingStep(id: 't1', type: ThinkingStepType.plan, title: '分析角色信息', status: ThinkingStepStatus.complete),
              ThinkingStep(id: 't2', type: ThinkingStepType.thought, title: '确定修改方向', status: ThinkingStepStatus.complete),
              ThinkingStep(id: 't3', type: ThinkingStepType.observation, title: '整合设定要素', status: ThinkingStepStatus.complete),
            ],
            isExpanded: false,
          ),
          TextBlock(content: '我准备修改角色设定，请您批准后执行。'),
          ToolApprovalBlock(
            toolName: '设定管理',
            operation: OperationType.update,
            description: '将更新张明的角色设定，添加背景故事和性格深度',
            details: ToolDetails(
              title: '角色设定：张明（待更新）',
              content: '【基本信息】\n姓名：张明\n年龄：25岁\n职业：后端程序员',
            ),
          ),
        ],
        timestamp: _getTimestamp(),
      );
    }
  }
  
  /// MCP智能体响应
  Stream<Message> _generateMCPAgentResponse(
    String messageId,
    Agent agent,
    String userMessage,
    bool deepThinking,
    bool requireApproval,
  ) async* {
    // 类似默认智能体，但包含MCP工具
    await Future.delayed(Duration(milliseconds: 500));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: '让我先查询相关设定信息，并使用网络搜索获取灵感。'),
        ToolBlock(toolType: ToolType.view, toolName: '角色查询', status: ToolStatus.running),
      ],
    );
    
    await Future.delayed(Duration(milliseconds: 800));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: '让我先查询相关设定信息，并使用网络搜索获取灵感。'),
        ToolBlock(toolType: ToolType.view, toolName: '角色查询', status: ToolStatus.complete, duration: '0.3s'),
        ToolBlock(toolType: ToolType.view, toolName: 'MCP-网络搜索', status: ToolStatus.running),
      ],
    );
    
    await Future.delayed(Duration(milliseconds: 1200));
    yield Message(
      id: messageId,
      role: MessageRole.assistant,
      agentId: agent.id,
      agentName: agent.name,
      blocks: [
        TextBlock(content: '让我先查询相关设定信息，并使用网络搜索获取灵感。'),
        ToolBlock(toolType: ToolType.view, toolName: '角色查询', status: ToolStatus.complete, duration: '0.3s'),
        ToolBlock(toolType: ToolType.view, toolName: 'MCP-网络搜索', status: ToolStatus.complete, duration: '1.2s'),
      ],
      toolSummary: [
        ToolSummaryItem(toolName: '角色查询', toolType: ToolType.view, viewCount: 1),
        ToolSummaryItem(toolName: 'MCP-网络搜索', toolType: ToolType.view, viewCount: 1),
      ],
      timestamp: _getTimestamp(),
    );
  }
  
  /// 完成工具执行
  Message completeToolExecution(Message message, Agent agent) {
    final newBlocks = message.blocks.where((b) => b.type != BlockType.approval).toList();
    
    newBlocks.add(ToolBlock(
      toolType: ToolType.crud,
      toolName: '设定管理',
      operation: OperationType.update,
      status: ToolStatus.complete,
      duration: '0.5s',
      details: ToolDetails(
        title: '角色设定：张明（已更新）',
        content: '【基本信息】\n姓名：张明\n年龄：25岁\n职业：后端程序员\n\n【性格特点】\n- 理性谨慎',
      ),
      applied: false,
      isExpanded: false,
    ));
    
    newBlocks.add(CitationBlock(
      citations: [
        Citation(type: CitationType.setting, number: 1, preview: '主角设定：张明'),
        Citation(type: CitationType.chapter, number: 3, preview: '第三章：地下室对峙'),
      ],
    ));
    
    newBlocks.add(TextBlock(content: '设定已更新完成。'));
    
    return message.copyWith(
      blocks: newBlocks,
      toolSummary: [
        ToolSummaryItem(toolName: '角色查询', toolType: ToolType.view, viewCount: 1),
        ToolSummaryItem(toolName: '设定管理', toolType: ToolType.crud, updated: 1),
      ],
      timestamp: _getTimestamp(),
    );
  }
  
  String _getTimestamp() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }
}




