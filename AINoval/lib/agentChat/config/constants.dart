/// Agent Chat 常量配置
/// Constants configuration for Agent Chat

/// 消息角色
/// Message roles
class MessageRole {
  static const String user = 'user';
  static const String assistant = 'assistant';
  static const String supervisor = 'supervisor';
}

/// 消息块类型
/// Message block types
class BlockType {
  static const String text = 'text';
  static const String tool = 'tool';
  static const String thinking = 'thinking';
  static const String citation = 'citation';
  static const String approval = 'approval';
  static const String taskAssignment = 'task-assignment';
}

/// 工具类型
/// Tool types
class ToolType {
  static const String view = 'view';      // 查看类工具
  static const String crud = 'crud';      // CRUD类工具
}

/// CRUD操作类型
/// CRUD operation types
class OperationType {
  static const String create = 'create';
  static const String update = 'update';
  static const String delete = 'delete';
  static const String view = 'view';
}

/// 工具状态
/// Tool status
class ToolStatus {
  static const String running = 'running';
  static const String complete = 'complete';
}

/// 思考步骤类型
/// Thinking step types
class ThinkingStepType {
  static const String plan = 'plan';              // 计划
  static const String thought = 'thought';        // 思考
  static const String observation = 'observation'; // 观察
}

/// 思考步骤状态
/// Thinking step status
class ThinkingStepStatus {
  static const String thinking = 'thinking';
  static const String complete = 'complete';
}

/// 引用类型
/// Citation types
class CitationType {
  static const String setting = 'setting';    // 设定
  static const String chapter = 'chapter';    // 章节
  static const String outline = 'outline';    // 大纲
  static const String fragment = 'fragment';  // 片段
}

/// 快照类型
/// Snapshot types
class SnapshotType {
  static const String message = 'message';
  static const String tool = 'tool';
  static const String approval = 'approval';
  static const String system = 'system';
}

/// 协作模式
/// Collaboration modes
class CollaborationMode {
  static const String team = 'team';      // 团队模式（多智能体）
  static const String author = 'author';  // 作者模式（单智能体）
}

/// 任务分配模式
/// Task assignment modes
class TaskAssignmentMode {
  static const String parallel = 'parallel';      // 并行
  static const String sequential = 'sequential';  // 串行
}

/// 工具类别
/// Tool categories
class ToolCategory {
  static const String builtIn = 'built-in';  // 内置工具
  static const String mcp = 'mcp';           // MCP工具
}

/// 预设智能体ID
/// Preset agent IDs
class PresetAgentId {
  static const String defaultAgent = 'default';
  static const String chatAgent = 'chat';
  static const String mcpAgent = 'mcp';
}

/// 输入框配置
/// Input configuration
class InputConfig {
  /// 最大行数
  static const int maxLines = 5;
  
  /// 最小行数
  static const int minLines = 1;
  
  /// 最大字符数
  static const int maxCharacters = 5000;
}

/// 对话配置
/// Conversation configuration
class ConversationConfig {
  /// 默认标题
  static const String defaultTitle = '新对话';
  
  /// 最大快照数量
  static const int maxSnapshots = 100;
  
  /// 最大消息数量
  static const int maxMessages = 1000;
}

/// 侧边栏配置
/// Sidebar configuration
class SidebarConfig {
  /// 默认宽度
  static const double defaultWidth = 500;
  
  /// 最小宽度
  static const double minWidth = 300;
  
  /// 最大宽度偏移（相对窗口宽度）
  static const double maxWidthOffset = 100;
}

/// 动画配置
/// Animation configuration
class AnimationConfig {
  /// 快速动画时长（毫秒）
  static const int fast = 150;
  
  /// 正常动画时长（毫秒）
  static const int normal = 200;
  
  /// 慢速动画时长（毫秒）
  static const int slow = 300;
  
  /// 思考动画时长（毫秒）
  static const int thinking = 1500;
}

/// 头像配置
/// Avatar configuration
class AvatarConfig {
  /// 用户头像颜色
  static const int userAvatarColor = 0xFF3B82F6; // blue
  
  /// AI头像颜色
  static const int aiAvatarColor = 0xFF8B5CF6; // purple
  
  /// Supervisor头像颜色
  static const int supervisorAvatarColor = 0xFFEF4444; // red
  
  /// 头像尺寸
  static const double size = 32.0;
  
  /// 用户头像图标
  static const String userIcon = '👤';
  
  /// AI头像图标
  static const String aiIcon = '🤖';
  
  /// Supervisor头像图标
  static const String supervisorIcon = '👔';
}

/// 存储Key
/// Storage keys
class StorageKeys {
  /// 语言设置
  static const String locale = 'agent_chat_locale';
  
  /// 主题模式
  static const String themeMode = 'agent_chat_theme_mode';
  
  /// 侧边栏宽度
  static const String sidebarWidth = 'agent_chat_sidebar_width';
  
  /// 对话历史
  static const String conversations = 'agent_chat_conversations';
  
  /// 智能体列表
  static const String agents = 'agent_chat_agents';
  
  /// 活动智能体ID
  static const String activeAgentId = 'agent_chat_active_agent_id';
  
  /// 协作模式
  static const String collaborationMode = 'agent_chat_collaboration_mode';
}

/// API配置（如果需要实际对接后端）
/// API configuration (if backend integration is needed)
class ApiConfig {
  /// 基础URL
  static const String baseUrl = 'http://localhost:3000';
  
  /// 聊天端点
  static const String chatEndpoint = '/api/chat';
  
  /// 智能体端点
  static const String agentEndpoint = '/api/agents';
  
  /// 超时时长（秒）
  static const int timeout = 30;
}

/// 测试数据标识
/// Test data flags
class TestData {
  /// 是否使用Mock数据
  static const bool useMockData = true;
  
  /// Mock响应延迟（毫秒）
  static const int mockDelay = 500;
}





