# Agent Chat - Flutter版本

## 📦 项目概述

这是从TypeScript/React迁移到Flutter的Agent Chat组件，完整保留了原有的所有功能，包括：

- ✅ 基于块的消息架构（TextBlock, ToolBlock, ThinkingBlock等）
- ✅ 流式显示响应
- ✅ 双重工具类型（查看/CRUD）
- ✅ 深度思考模式
- ✅ 人类在环（Human-in-the-Loop）
- ✅ 时间旅行（Time Travel）
- ✅ 多智能体协作
- ✅ 国际化支持（中英文）
- ✅ 响应式设计（手机/平板/桌面）
- ✅ 深色主题支持

## 🗂️ 目录结构

```
lib/agentChat/
├── config/                    # 配置文件
│   ├── theme_config.dart      # 主题配置（36+颜色变量）
│   └── constants.dart         # 常量定义
├── i18n/                      # 国际化
│   ├── translations.dart      # 翻译文件（100+翻译）
│   └── locale_provider.dart   # 语言切换Provider
├── models/                    # 数据模型
│   ├── message_block.dart     # 消息块模型
│   ├── message.dart           # 消息模型
│   ├── agent.dart             # 智能体模型
│   ├── snapshot.dart          # 快照模型
│   ├── reference.dart         # 引用模型
│   ├── conversation.dart      # 对话模型
│   └── models.dart            # 统一导出
├── widgets/                   # UI组件
│   ├── blocks/                # 消息块组件
│   │   ├── text_block.dart
│   │   ├── citation_block.dart
│   │   ├── thinking_block.dart
│   │   ├── tool_block.dart
│   │   ├── approval_block.dart
│   │   ├── task_assignment_block.dart
│   │   └── blocks.dart
│   ├── chat_message.dart      # 聊天消息组件
│   ├── chat_input.dart        # 输入框组件
│   ├── chat_area.dart         # 聊天区域组件
│   ├── reference_bar.dart     # 引用栏组件
│   ├── conversation_tabs.dart # 对话标签组件
│   ├── time_travel.dart       # 时间旅行组件
│   ├── agent_card.dart        # 智能体卡片组件
│   ├── create_agent_dialog.dart # 创建智能体对话框
│   ├── agent_manager.dart     # 智能体管理器
│   └── tool_summary.dart      # 工具摘要组件
├── providers/                 # 状态管理
│   ├── chat_provider.dart     # 聊天Provider
│   └── agent_provider.dart    # 智能体Provider
├── services/                  # 业务服务
│   └── chat_service.dart      # 聊天服务（模拟流式响应）
├── screens/                   # 页面
│   └── agent_chat_screen.dart # 主页面
├── utils/                     # 工具类
│   ├── responsive_utils.dart  # 响应式工具
│   └── animation_utils.dart   # 动画工具
├── main.dart                  # 独立启动入口
├── README.md                  # 本文档
├── MIGRATION_PLAN.md          # 迁移计划
└── PROGRESS.md                # 迁移进度
```

## 🚀 快速启动

### 独立运行

```bash
cd H:\GitHub\AINovalWriter\AINoval
flutter run -d windows -t lib/agentChat/main.dart
```

### 集成到现有应用

```dart
import 'package:AINoval/agentChat/screens/agent_chat_screen.dart';

// 在你的路由或页面中使用
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => AgentChatScreen()),
);
```

## 🎨 主题配置

所有主题颜色都集中在 `config/theme_config.dart` 中，方便统一修改：

```dart
// 示例：修改主题色
class AgentChatThemeConfig {
  // 主色调
  static const ColorToken lightPrimary = ColorToken(262, 83, 58);  // 紫色
  static const ColorToken darkPrimary = ColorToken(263, 70, 70);
  
  // 用户消息背景
  static const ColorToken userMessageBg = ColorToken(262, 83, 98);
  
  // AI消息背景
  static const ColorToken aiMessageBg = ColorToken(0, 0, 99);
  
  // ... 36+个颜色配置
}
```

## 🌍 国际化

支持中英文切换，翻译文件在 `i18n/translations.dart`：

```dart
// 切换语言
final localeProvider = Provider.of<LocaleProvider>(context);
localeProvider.setLocale('en'); // 切换到英文
localeProvider.setLocale('zh'); // 切换到中文
```

## 📱 响应式支持

自动适配手机、平板、桌面三种屏幕尺寸：

- **手机**（<640px）：单列布局，紧凑间距
- **平板**（640-1024px）：中等布局
- **桌面**（>1024px）：宽松布局，完整功能

## 🧪 测试

### 运行测试

```bash
flutter test lib/agentChat/
```

### 手动测试清单

- [ ] 发送文本消息
- [ ] 查看流式响应
- [ ] 测试工具调用
- [ ] 测试深度思考模式
- [ ] 测试工具批准/拒绝
- [ ] 测试时间旅行功能
- [ ] 切换智能体
- [ ] 切换协作模式
- [ ] 创建/编辑/删除智能体
- [ ] 切换语言
- [ ] 测试响应式布局

## 📋 核心功能

### 1. 消息块架构

支持6种消息块类型：

- **TextBlock**: 纯文本/Markdown内容
- **CitationBlock**: 引用块（设定/章节/大纲/片段）
- **ThinkingBlock**: AI思考过程
- **ToolBlock**: 工具调用（查看/CRUD）
- **ToolApprovalBlock**: 工具批准请求
- **TaskAssignmentBlock**: 任务分配（多智能体）

### 2. 流式响应

模拟真实的流式输出，逐步显示：

1. 初始文本
2. 工具调用（运行中→完成）
3. 思考步骤（逐步展开）
4. 批准请求
5. 最终结果

### 3. 智能体管理

- **预设智能体**：默认智能体、对话智能体、MCP智能体
- **自定义智能体**：创建/编辑/删除
- **工具配置**：内置工具、MCP工具
- **协作模式**：作者模式、团队模式

### 4. 时间旅行

- **自动快照**：每次重要操作自动创建
- **手动快照**：用户手动创建检查点
- **一键回退**：快速恢复到任何历史状态

## 🎯 关键差异（与原TS版本）

### 相同点

✅ 完全相同的UI设计和交互逻辑
✅ 完全相同的消息块架构
✅ 完全相同的功能特性

### 差异点

| 特性 | TypeScript/React | Flutter |
|------|-----------------|---------|
| 状态管理 | Zustand | Provider |
| 路由 | Wouter | Navigator |
| UI库 | Shadcn/Radix UI | Material/Custom Widgets |
| 图标 | Lucide React | Icons/Custom |
| Markdown | react-markdown | flutter_markdown |
| 数据持久化 | localStorage | SharedPreferences |

## 🔧 依赖项

项目使用的主要依赖：

- `provider`: 状态管理
- `flutter_markdown`: Markdown渲染
- `shared_preferences`: 本地存储
- `intl`: 国际化

## 📖 API文档

### ChatProvider

```dart
class ChatProvider with ChangeNotifier {
  // 对话管理
  void createConversation();
  void switchConversation(String id);
  void closeConversation(String id);
  
  // 消息操作
  void addMessage(Message message);
  void updateMessage(String id, Message message);
  void rollbackMessage(String id);
  void editMessage(String id, String content);
  
  // 快照管理
  String createSnapshot(String label, String desc, String type);
  void restoreSnapshot(String snapshotId);
  
  // 引用管理
  void addReference(Reference ref);
  void removeReference(String id);
}
```

### AgentProvider

```dart
class AgentProvider with ChangeNotifier {
  // 智能体管理
  void createAgent(Agent agent);
  void updateAgent(String id, Agent agent);
  void deleteAgent(String id);
  void selectAgent(String id);
  
  // 协作模式
  void setCollaborationMode(String mode);
}
```

### ChatService

```dart
class ChatService {
  // 生成流式响应
  Stream<Message> generateResponse({
    required String messageId,
    required Agent agent,
    required String userMessage,
    bool deepThinking = false,
    bool requireApproval = true,
  });
  
  // 完成工具执行
  Message completeToolExecution(Message message, Agent agent);
}
```

## 🐛 已知问题

- [ ] 暂无

## 🚧 待优化

- [ ] 添加单元测试
- [ ] 添加集成测试
- [ ] 优化动画性能
- [ ] 添加错误边界
- [ ] 添加离线支持

## 📝 更新日志

### v1.0.0 (2024-10-16)

- ✅ 完成从TypeScript/React到Flutter的完整迁移
- ✅ 实现所有核心功能
- ✅ 支持中英文国际化
- ✅ 支持响应式布局
- ✅ 支持独立启动

## 👥 贡献

欢迎提交Issue和Pull Request！

## 📄 许可证

MIT License




