/// 国际化翻译配置
/// i18n Translations configuration
/// 
/// 支持中文和英文切换，可扩展其他语言
/// Supports Chinese and English, extensible for other languages

/// 语言类型
/// Locale type
enum AgentChatLocale {
  zh, // 中文
  en, // English
}

/// 翻译类
/// Translation class
class Translations {
  final AgentChatLocale locale;
  
  const Translations(this.locale);
  
  // ==================== 通用 / Common ====================
  
  String get send => locale == AgentChatLocale.zh ? '发送' : 'Send';
  String get cancel => locale == AgentChatLocale.zh ? '取消' : 'Cancel';
  String get apply => locale == AgentChatLocale.zh ? '应用' : 'Apply';
  String get expand => locale == AgentChatLocale.zh ? '展开' : 'Expand';
  String get collapse => locale == AgentChatLocale.zh ? '收起' : 'Collapse';
  String get delete => locale == AgentChatLocale.zh ? '删除' : 'Delete';
  String get approve => locale == AgentChatLocale.zh ? '批准' : 'Approve';
  String get reject => locale == AgentChatLocale.zh ? '拒绝' : 'Reject';
  String get save => locale == AgentChatLocale.zh ? '保存' : 'Save';
  String get edit => locale == AgentChatLocale.zh ? '编辑' : 'Edit';
  String get close => locale == AgentChatLocale.zh ? '关闭' : 'Close';
  String get create => locale == AgentChatLocale.zh ? '创建' : 'Create';
  String get update => locale == AgentChatLocale.zh ? '更新' : 'Update';
  String get search => locale == AgentChatLocale.zh ? '搜索' : 'Search';
  String get back => locale == AgentChatLocale.zh ? '返回' : 'Back';
  String get confirm => locale == AgentChatLocale.zh ? '确认' : 'Confirm';
  
  // ==================== 聊天输入 / Chat Input ====================
  
  String get inputPlaceholder => locale == AgentChatLocale.zh 
      ? '输入消息...' 
      : 'Type a message...';
  
  String get inputHint => locale == AgentChatLocale.zh 
      ? 'Enter 发送，Shift+Enter 换行' 
      : 'Enter to send, Shift+Enter for new line';
  
  String get deepThinking => locale == AgentChatLocale.zh 
      ? '深度思考模式' 
      : 'Deep thinking mode';
  
  String get deepThinkingEnabled => locale == AgentChatLocale.zh 
      ? '🧠 深度思考模式已启用' 
      : '🧠 Deep thinking enabled';
  
  String get characterCount => locale == AgentChatLocale.zh ? '字符' : 'characters';
  
  // ==================== 引用栏 / Reference Bar ====================
  
  String get references => locale == AgentChatLocale.zh ? '引用：' : 'References:';
  String get removeReference => locale == AgentChatLocale.zh ? '移除引用' : 'Remove reference';
  
  // ==================== 消息状态 / Message Status ====================
  
  String get thinking => locale == AgentChatLocale.zh ? '思考中...' : 'Thinking...';
  String get thinkingProcess => locale == AgentChatLocale.zh ? '思考过程' : 'Thinking Process';
  
  String thinkingSteps(int count) => locale == AgentChatLocale.zh 
      ? '思考过程 ($count步)' 
      : 'Thinking ($count steps)';
  
  // ==================== 工具类型 / Tool Types ====================
  
  String get toolView => locale == AgentChatLocale.zh ? '查看' : 'View';
  String get toolCrud => locale == AgentChatLocale.zh ? '操作' : 'CRUD';
  
  // ==================== 工具操作 / Tool Operations ====================
  
  String get operationCreate => locale == AgentChatLocale.zh ? '创建' : 'Create';
  String get operationUpdate => locale == AgentChatLocale.zh ? '更新' : 'Update';
  String get operationDelete => locale == AgentChatLocale.zh ? '删除' : 'Delete';
  String get operationView => locale == AgentChatLocale.zh ? '查看' : 'View';
  
  // ==================== 引用类型 / Reference Types ====================
  
  String get refSetting => locale == AgentChatLocale.zh ? '设定' : 'Setting';
  String get refChapter => locale == AgentChatLocale.zh ? '章节' : 'Chapter';
  String get refOutline => locale == AgentChatLocale.zh ? '大纲' : 'Outline';
  String get refFragment => locale == AgentChatLocale.zh ? '片段' : 'Fragment';
  
  // ==================== 工具汇总 / Tool Summary ====================
  
  String get toolSummary => locale == AgentChatLocale.zh ? '工具汇总' : 'Tool Summary';
  
  String viewCount(int count) => locale == AgentChatLocale.zh 
      ? '查看 $count次' 
      : '$count view${count > 1 ? 's' : ''}';
  
  String createCount(int count) => locale == AgentChatLocale.zh 
      ? '创建 $count项' 
      : '$count created';
  
  String updateCount(int count) => locale == AgentChatLocale.zh 
      ? '更新 $count项' 
      : '$count updated';
  
  String deleteCount(int count) => locale == AgentChatLocale.zh 
      ? '删除 $count项' 
      : '$count deleted';
  
  // ==================== 对话 / Conversation ====================
  
  String get newChat => locale == AgentChatLocale.zh ? '新对话' : 'New Chat';
  String get emptyState => locale == AgentChatLocale.zh 
      ? '开始与AI对话' 
      : 'Start a conversation with AI';
  
  String get emptyStateHint => locale == AgentChatLocale.zh 
      ? '一起创作你的小说故事...' 
      : 'Let\'s create your story together...';
  
  // ==================== 思考步骤类型 / Thinking Step Types ====================
  
  String get stepPlan => locale == AgentChatLocale.zh ? '计划' : 'Plan';
  String get stepThought => locale == AgentChatLocale.zh ? '思考' : 'Thought';
  String get stepObservation => locale == AgentChatLocale.zh ? '观察' : 'Observation';
  
  // ==================== 人工参与循环 / Human-in-the-Loop ====================
  
  String get awaitingApproval => locale == AgentChatLocale.zh 
      ? '等待批准' 
      : 'Awaiting Approval';
  
  String get approveExecution => locale == AgentChatLocale.zh 
      ? '批准执行' 
      : 'Approve Execution';
  
  String get viewDetails => locale == AgentChatLocale.zh ? '查看详情' : 'View Details';
  String get hideDetails => locale == AgentChatLocale.zh ? '隐藏详情' : 'Hide Details';
  
  // ==================== 时间旅行 / Time Travel ====================
  
  String get timeTravel => locale == AgentChatLocale.zh ? '时间旅行' : 'Time Travel';
  
  String get timeTravelDesc => locale == AgentChatLocale.zh 
      ? '选择一个历史状态进行回退' 
      : 'Select a historical state to restore';
  
  String get currentState => locale == AgentChatLocale.zh ? '当前状态' : 'Current State';
  String get restore => locale == AgentChatLocale.zh ? '回退' : 'Restore';
  
  String get timeTravelHint => locale == AgentChatLocale.zh 
      ? '回退到历史状态后，之后的所有操作将被清除' 
      : 'After restoring to a historical state, all subsequent operations will be cleared';
  
  String get snapshot => locale == AgentChatLocale.zh ? '快照' : 'Snapshot';
  String get snapshotMessage => locale == AgentChatLocale.zh ? '消息' : 'Message';
  String get snapshotTool => locale == AgentChatLocale.zh ? '工具' : 'Tool';
  String get snapshotApproval => locale == AgentChatLocale.zh ? '批准' : 'Approval';
  String get snapshotSystem => locale == AgentChatLocale.zh ? '系统' : 'System';
  
  // ==================== 消息操作 / Message Actions ====================
  
  String get rollback => locale == AgentChatLocale.zh ? '回退' : 'Rollback';
  String get copyMessage => locale == AgentChatLocale.zh ? '复制' : 'Copy';
  String get messageCopied => locale == AgentChatLocale.zh ? '已复制' : 'Copied';
  String get cancelEdit => locale == AgentChatLocale.zh ? '取消' : 'Cancel';
  String get doubleClickToEdit => locale == AgentChatLocale.zh 
      ? '双击编辑' 
      : 'Double-click to edit';
  
  // ==================== 智能体管理 / Agent Management ====================
  
  String get agentManagement => locale == AgentChatLocale.zh 
      ? '智能体管理' 
      : 'Agent Management';
  
  String get agents => locale == AgentChatLocale.zh ? '智能体' : 'Agents';
  String get createAgent => locale == AgentChatLocale.zh ? '新建智能体' : 'Create Agent';
  String get editAgent => locale == AgentChatLocale.zh ? '编辑智能体' : 'Edit Agent';
  String get deleteAgent => locale == AgentChatLocale.zh ? '删除智能体' : 'Delete Agent';
  String get agentName => locale == AgentChatLocale.zh ? '智能体名称' : 'Agent Name';
  String get agentDescription => locale == AgentChatLocale.zh ? '描述' : 'Description';
  String get systemPrompt => locale == AgentChatLocale.zh ? '系统提示词' : 'System Prompt';
  String get toolCategories => locale == AgentChatLocale.zh ? '工具类别' : 'Tool Categories';
  String get builtInTools => locale == AgentChatLocale.zh ? '内置工具' : 'Built-in Tools';
  String get mcpTools => locale == AgentChatLocale.zh ? 'MCP工具' : 'MCP Tools';
  String get selectTools => locale == AgentChatLocale.zh ? '选择工具' : 'Select Tools';
  String get noToolsSelected => locale == AgentChatLocale.zh 
      ? '未选择工具' 
      : 'No tools selected';
  
  String get agentSettings => locale == AgentChatLocale.zh 
      ? '智能体设置' 
      : 'Agent Settings';
  
  String get currentAgent => locale == AgentChatLocale.zh ? '当前智能体' : 'Current Agent';
  String get switchAgent => locale == AgentChatLocale.zh ? '切换智能体' : 'Switch Agent';
  
  // ==================== 预设智能体 / Preset Agents ====================
  
  String get defaultAgent => locale == AgentChatLocale.zh 
      ? '默认智能体' 
      : 'Default Agent';
  
  String get defaultAgentDesc => locale == AgentChatLocale.zh 
      ? '具备完整的创作和修改功能' 
      : 'Full creative and modification capabilities';
  
  String get chatAgent => locale == AgentChatLocale.zh 
      ? '对话智能体' 
      : 'Chat Agent';
  
  String get chatAgentDesc => locale == AgentChatLocale.zh 
      ? '仅支持对话交流，无修改权限' 
      : 'Chat only, no modification permissions';
  
  String get mcpAgent => locale == AgentChatLocale.zh 
      ? 'MCP智能体' 
      : 'MCP Agent';
  
  String get mcpAgentDesc => locale == AgentChatLocale.zh 
      ? '默认功能 + MCP工具调用' 
      : 'Default capabilities + MCP tool calls';
  
  // ==================== 工具相关 / Tools ====================
  
  String get enableBuiltInTools => locale == AgentChatLocale.zh 
      ? '启用内置工具' 
      : 'Enable Built-in Tools';
  
  String get enableMCPTools => locale == AgentChatLocale.zh 
      ? '启用MCP工具' 
      : 'Enable MCP Tools';
  
  String toolsCount(int count) => locale == AgentChatLocale.zh 
      ? '$count个工具' 
      : '$count tools';
  
  // ==================== 多智能体协作 / Multi-Agent Collaboration ====================
  
  String get teamMode => locale == AgentChatLocale.zh ? '团队模式' : 'Team Mode';
  String get authorMode => locale == AgentChatLocale.zh ? '作者模式' : 'Author Mode';
  String get switchToTeam => locale == AgentChatLocale.zh 
      ? '切换到团队模式' 
      : 'Switch to Team Mode';
  
  String get switchToAuthor => locale == AgentChatLocale.zh 
      ? '切换到作者模式' 
      : 'Switch to Author Mode';
  
  // ==================== 侧边栏调整 / Sidebar Resize ====================
  
  String get dragToResize => locale == AgentChatLocale.zh 
      ? '拖拽调整宽度，双击全屏' 
      : 'Drag to resize, double-click for fullscreen';
  
  String get exitFullscreen => locale == AgentChatLocale.zh 
      ? '双击退出全屏' 
      : 'Double-click to exit fullscreen';
  
  // ==================== 错误提示 / Error Messages ====================
  
  String get errorOccurred => locale == AgentChatLocale.zh 
      ? '发生错误' 
      : 'An error occurred';
  
  String get networkError => locale == AgentChatLocale.zh 
      ? '网络连接失败' 
      : 'Network connection failed';
  
  String get tryAgain => locale == AgentChatLocale.zh ? '重试' : 'Try Again';
  
  String get invalidInput => locale == AgentChatLocale.zh 
      ? '输入无效' 
      : 'Invalid input';
  
  String get required => locale == AgentChatLocale.zh ? '必填' : 'Required';
  
  // ==================== 确认对话 / Confirmation Dialogs ====================
  
  String get deleteConfirm => locale == AgentChatLocale.zh 
      ? '确认删除吗？' 
      : 'Confirm delete?';
  
  String get deleteAgentConfirm => locale == AgentChatLocale.zh 
      ? '确认删除此智能体吗？' 
      : 'Confirm delete this agent?';
  
  String get deleteConversationConfirm => locale == AgentChatLocale.zh 
      ? '确认删除此对话吗？' 
      : 'Confirm delete this conversation?';
  
  String get unsavedChanges => locale == AgentChatLocale.zh 
      ? '有未保存的更改' 
      : 'Unsaved changes';
  
  String get discardChanges => locale == AgentChatLocale.zh 
      ? '放弃更改' 
      : 'Discard changes';
  
  // ==================== 任务分配 / Task Assignment ====================
  
  String get taskAssignment => locale == AgentChatLocale.zh 
      ? '任务分配' 
      : 'Task Assignment';
  
  String get parallelMode => locale == AgentChatLocale.zh ? '并行执行' : 'Parallel';
  String get sequentialMode => locale == AgentChatLocale.zh ? '串行执行' : 'Sequential';
  String get assignedAgent => locale == AgentChatLocale.zh ? '分配智能体' : 'Assigned Agent';
  String get taskDescription => locale == AgentChatLocale.zh ? '任务描述' : 'Task Description';
  String get assignmentReason => locale == AgentChatLocale.zh ? '分配原因' : 'Reason';
}

/// 默认语言
/// Default locale
const AgentChatLocale defaultLocale = AgentChatLocale.zh;

/// 获取翻译实例
/// Get translations instance
Translations getTranslations(AgentChatLocale locale) {
  return Translations(locale);
}




