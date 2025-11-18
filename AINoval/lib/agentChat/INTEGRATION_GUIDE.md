# Agent Chat 集成指南
# Agent Chat Integration Guide

## 📦 快速集成 Quick Integration

### 1. 添加依赖 Add Dependencies

确保在 `pubspec.yaml` 中已包含以下依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.1
  flutter_markdown: ^0.6.18
  shared_preferences: ^2.2.2
  intl: ^0.18.1
```

### 2. 导入组件 Import Component

```dart
import 'package:AINoval/agentChat/screens/agent_chat_screen.dart';
import 'package:AINoval/agentChat/providers/chat_provider.dart';
import 'package:AINoval/agentChat/providers/agent_provider.dart';
import 'package:AINoval/agentChat/i18n/locale_provider.dart';
```

### 3. 配置Provider Setup Providers

在你的应用根组件中添加Providers：

```dart
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 其他providers...
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
      ],
      child: MaterialApp(
        // 你的应用配置...
      ),
    );
  }
}
```

### 4. 导航到聊天页面 Navigate to Chat Screen

```dart
// 方式1: 直接导航
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => AgentChatScreen()),
);

// 方式2: 命名路由
MaterialApp(
  routes: {
    '/chat': (context) => AgentChatScreen(),
  },
);

Navigator.pushNamed(context, '/chat');
```

## 🎨 自定义主题 Customize Theme

### 修改颜色配置 Modify Colors

编辑 `lib/agentChat/config/theme_config.dart`：

```dart
class AgentChatThemeConfig {
  // 修改主色调
  static const ColorToken lightPrimary = ColorToken(262, 83, 58);  // 紫色
  static const ColorToken darkPrimary = ColorToken(263, 70, 70);
  
  // 修改用户消息背景
  static const ColorToken userMessageBg = ColorToken(262, 83, 98);
  
  // 修改AI消息背景
  static const ColorToken aiMessageBg = ColorToken(0, 0, 99);
  
  // ... 36+个颜色配置
}
```

### 应用自定义主题 Apply Custom Theme

```dart
MaterialApp(
  theme: AgentChatThemeConfig.light,
  darkTheme: AgentChatThemeConfig.dark,
  themeMode: ThemeMode.system, // 或 ThemeMode.light / ThemeMode.dark
)
```

## 🌍 配置国际化 Configure i18n

### 切换语言 Switch Language

```dart
final localeProvider = Provider.of<LocaleProvider>(context);

// 切换到中文
localeProvider.setLocale('zh');

// 切换到英文
localeProvider.setLocale('en');

// 获取当前语言
String currentLang = localeProvider.currentLocale;
```

### 添加新语言 Add New Language

1. 编辑 `lib/agentChat/i18n/translations.dart`：

```dart
class AppTranslations {
  static final Map<String, String> ja = {
    'send': '送信',
    'cancel': 'キャンセル',
    // 添加所有翻译...
  };
}
```

2. 在 `LocaleProvider` 中添加支持：

```dart
static const supportedLocales = ['zh', 'en', 'ja'];
```

## 🔌 后端集成 Backend Integration

### 替换模拟服务 Replace Mock Service

创建真实的ChatService实现：

```dart
class RealChatService extends ChatService {
  final Dio _dio = Dio();
  
  @override
  Stream<Message> generateResponse({
    required String messageId,
    required Agent agent,
    required String userMessage,
    bool deepThinking = false,
    bool requireApproval = true,
  }) async* {
    // 调用真实API
    final response = await _dio.post(
      'https://your-api.com/chat',
      data: {
        'message': userMessage,
        'agentId': agent.id,
        'deepThinking': deepThinking,
      },
    );
    
    // 解析SSE流式响应
    // yield Message.fromJson(chunk);
  }
}
```

### 在主页面中使用 Use in Main Screen

```dart
class _AgentChatScreenState extends State<AgentChatScreen> {
  final ChatService _chatService = RealChatService(); // 使用真实服务
  
  // ...
}
```

## 🎯 自定义智能体 Custom Agents

### 添加预设智能体 Add Preset Agents

编辑 `lib/agentChat/providers/agent_provider.dart`：

```dart
void initialize(Translations translations) {
  _agents = [
    Agent(
      id: 'custom-writer',
      name: '创意写手',
      description: '专注于创意内容生成',
      systemPrompt: '你是一个富有创意的写手...',
      toolCategories: [ToolCategory.builtIn],
      builtInTools: ['character-query', 'setting-management'],
      mcpTools: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
    // 其他预设智能体...
  ];
}
```

## 📊 数据持久化 Data Persistence

### 保存对话历史 Save Conversation History

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ChatPersistence {
  static Future<void> saveConversations(List<Conversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final json = conversations.map((c) => c.toJson()).toList();
    await prefs.setString('conversations', jsonEncode(json));
  }
  
  static Future<List<Conversation>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('conversations');
    if (jsonStr == null) return [];
    
    final List<dynamic> json = jsonDecode(jsonStr);
    return json.map((j) => Conversation.fromJson(j)).toList();
  }
}
```

### 在Provider中使用 Use in Provider

```dart
class ChatProvider with ChangeNotifier {
  Future<void> initialize() async {
    // 加载历史对话
    _conversations = await ChatPersistence.loadConversations();
    if (_conversations.isEmpty) {
      // 创建默认对话...
    }
    notifyListeners();
  }
  
  void addMessage(Message message) {
    // 添加消息...
    // 保存到本地
    ChatPersistence.saveConversations(_conversations);
    notifyListeners();
  }
}
```

## 🧩 扩展功能 Extended Features

### 添加自定义消息块 Add Custom Message Block

1. 定义新的块类型：

```dart
class ImageBlock extends MessageBlock {
  final String imageUrl;
  final String? caption;
  
  ImageBlock({
    required this.imageUrl,
    this.caption,
  }) : super(type: 'image');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'imageUrl': imageUrl,
    'caption': caption,
  };
  
  factory ImageBlock.fromJson(Map<String, dynamic> json) => ImageBlock(
    imageUrl: json['imageUrl'],
    caption: json['caption'],
  );
}
```

2. 创建对应的Widget：

```dart
class ImageBlockWidget extends StatelessWidget {
  final ImageBlock block;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.network(block.imageUrl),
        if (block.caption != null)
          Text(block.caption!),
      ],
    );
  }
}
```

3. 在ChatMessage中注册：

```dart
Widget _renderBlock(MessageBlock block) {
  switch (block.type) {
    case 'image':
      return ImageBlockWidget(block: block as ImageBlock);
    // 其他块类型...
  }
}
```

## 🔒 安全性 Security

### API密钥管理 API Key Management

```dart
class SecureConfig {
  static const apiKey = String.fromEnvironment('API_KEY');
  static const apiEndpoint = String.fromEnvironment('API_ENDPOINT');
}

// 运行时传入：
// flutter run --dart-define=API_KEY=your_key
```

### 输入验证 Input Validation

```dart
String sanitizeInput(String input) {
  // 移除危险字符
  return input
    .replaceAll(RegExp(r'<script>'), '')
    .replaceAll(RegExp(r'<iframe>'), '')
    .trim();
}
```

## 📈 性能优化 Performance Optimization

### 消息虚拟化 Message Virtualization

对于大量消息，使用虚拟滚动：

```dart
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

ListView.builder(
  itemCount: messages.length,
  itemBuilder: (context, index) {
    // 只渲染可见的消息
    return ChatMessageWidget(message: messages[index]);
  },
)
```

### 图片懒加载 Lazy Load Images

```dart
import 'package:cached_network_image/cached_network_image.dart';

CachedNetworkImage(
  imageUrl: imageUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
)
```

## 🐛 调试模式 Debug Mode

### 启用日志 Enable Logging

```dart
class DebugConfig {
  static const bool enableLogs = true;
  
  static void log(String message) {
    if (enableLogs) {
      print('[AgentChat] $message');
    }
  }
}

// 使用
DebugConfig.log('Message sent: $messageId');
```

## 📱 平台适配 Platform Adaptation

### Web平台 Web Platform

```dart
import 'package:flutter/foundation.dart';

if (kIsWeb) {
  // Web特定逻辑
  // 例如：禁用某些手势
}
```

### 移动平台 Mobile Platform

```dart
import 'dart:io';

if (Platform.isAndroid || Platform.isIOS) {
  // 移动端特定逻辑
  // 例如：启用触觉反馈
}
```

## 🎓 最佳实践 Best Practices

1. **状态管理**: 使用Provider进行全局状态管理
2. **错误处理**: 在所有异步操作中添加try-catch
3. **性能监控**: 使用Flutter DevTools监控性能
4. **代码复用**: 提取公共组件和工具函数
5. **类型安全**: 充分利用Dart的类型系统
6. **文档注释**: 为公共API添加文档注释
7. **测试覆盖**: 为核心功能编写单元测试

## 📞 技术支持 Technical Support

如有问题，请查看：

- [README.md](./README.md) - 完整文档
- [TEST_CHECKLIST.md](./TEST_CHECKLIST.md) - 测试清单
- [MIGRATION_PLAN.md](./MIGRATION_PLAN.md) - 迁移计划

---

**更新日期**: 2024-10-16




