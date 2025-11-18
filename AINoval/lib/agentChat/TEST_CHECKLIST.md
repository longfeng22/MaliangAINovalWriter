# Agent Chat 测试清单
# Agent Chat Test Checklist

## ✅ 基础功能测试 Basic Functions

### 消息发送 Message Sending
- [ ] 发送纯文本消息
- [ ] 发送多行消息
- [ ] 发送空消息（应被拒绝）
- [ ] Enter发送，Shift+Enter换行
- [ ] 发送后输入框自动清空
- [ ] 消息自动滚动到底部

### 流式响应 Streaming Response
- [ ] 文本逐步显示
- [ ] 工具调用状态变化（运行中→完成）
- [ ] 思考步骤逐步展开
- [ ] 批准块正确显示
- [ ] 引用块正确显示
- [ ] 工具摘要正确汇总

### 智能体切换 Agent Switching
- [ ] 默认智能体（完整工具）
- [ ] 对话智能体（仅文本）
- [ ] MCP智能体（增强工具）
- [ ] 切换智能体后消息正确显示

## ✅ 高级功能测试 Advanced Features

### 深度思考模式 Deep Thinking
- [ ] 启用深度思考
- [ ] 禁用深度思考
- [ ] 深度思考状态正确提示
- [ ] 深度思考影响响应内容

### 工具交互 Tool Interaction
- [ ] 查看工具正确显示
- [ ] CRUD工具正确显示（创建/更新/删除）
- [ ] 工具展开/折叠
- [ ] 工具应用功能
- [ ] 工具取消功能
- [ ] 工具持续时间显示

### 人类在环 Human-in-the-Loop
- [ ] 批准请求正确显示
- [ ] 点击"批准"按钮
- [ ] 点击"拒绝"按钮
- [ ] 批准后工具执行
- [ ] 拒绝后取消操作

### 时间旅行 Time Travel
- [ ] 快照自动创建
- [ ] 快照列表显示
- [ ] 当前快照高亮
- [ ] 回退到历史快照
- [ ] 回退后消息正确恢复
- [ ] 回退后后续快照被清除

### 消息操作 Message Actions
- [ ] 消息回退（Rollback）
- [ ] 消息编辑（Edit）
- [ ] 消息复制（Copy）
- [ ] 操作菜单显示/隐藏

## ✅ 对话管理 Conversation Management

### 多对话标签 Multiple Conversations
- [ ] 新建对话
- [ ] 切换对话
- [ ] 关闭对话（保留至少一个）
- [ ] 对话标题显示
- [ ] 横向滚动标签栏

### 引用系统 Reference System
- [ ] 添加引用
- [ ] 显示引用列表
- [ ] 删除引用
- [ ] 引用类型正确显示（设定/章节/大纲/片段）
- [ ] 引用数字正确显示

## ✅ 智能体管理 Agent Management

### 预设智能体 Preset Agents
- [ ] 默认智能体预设
- [ ] 对话智能体预设
- [ ] MCP智能体预设

### 自定义智能体 Custom Agents
- [ ] 创建智能体
- [ ] 编辑智能体
- [ ] 删除智能体
- [ ] 智能体卡片显示
- [ ] 智能体选择

### 工具配置 Tool Configuration
- [ ] 内置工具选择
- [ ] MCP工具选择
- [ ] 工具类别切换
- [ ] 工具保存到智能体

### 协作模式 Collaboration Mode
- [ ] 作者模式
- [ ] 团队模式
- [ ] 模式切换
- [ ] 模式状态显示

## ✅ 国际化 Internationalization

### 语言切换 Language Switching
- [ ] 中文界面
- [ ] 英文界面
- [ ] 语言切换后所有文本更新
- [ ] 语言设置持久化

### 翻译完整性 Translation Coverage
- [ ] 所有UI文本已翻译
- [ ] 错误提示已翻译
- [ ] 工具提示已翻译
- [ ] 占位符已翻译

## ✅ 响应式设计 Responsive Design

### 手机端 Mobile (<640px)
- [ ] 布局紧凑
- [ ] 按钮尺寸适中
- [ ] 文字大小可读
- [ ] 输入框高度合适
- [ ] 滚动流畅

### 平板端 Tablet (640-1024px)
- [ ] 布局中等
- [ ] 组件间距合适
- [ ] 侧边栏宽度合适

### 桌面端 Desktop (>1024px)
- [ ] 布局宽松
- [ ] 侧边栏可调整宽度
- [ ] 双击分隔条全屏
- [ ] 拖拽调整宽度

## ✅ 主题样式 Theme & Styling

### 颜色系统 Color System
- [ ] 主色调正确应用
- [ ] 用户消息背景色
- [ ] AI消息背景色
- [ ] 边框颜色
- [ ] 工具颜色（查看/创建/更新/删除）
- [ ] 引用类型颜色
- [ ] 思考步骤颜色

### 深色模式 Dark Mode
- [ ] 浅色主题
- [ ] 深色主题
- [ ] 主题切换
- [ ] 所有组件支持深色模式

## ✅ 性能测试 Performance

### 渲染性能 Rendering
- [ ] 首次加载速度
- [ ] 消息渲染流畅
- [ ] 滚动性能
- [ ] 大量消息不卡顿（100+条）

### 内存管理 Memory
- [ ] 无明显内存泄漏
- [ ] 长时间运行稳定
- [ ] 组件销毁正确

## ✅ 边界情况 Edge Cases

### 数据边界 Data Boundaries
- [ ] 空对话
- [ ] 空消息列表
- [ ] 空智能体列表
- [ ] 空工具列表
- [ ] 超长消息显示
- [ ] 超长工具名称

### 错误处理 Error Handling
- [ ] 网络错误提示
- [ ] 无效输入提示
- [ ] 操作失败提示
- [ ] 错误边界捕获

## ✅ 可访问性 Accessibility

### 键盘导航 Keyboard Navigation
- [ ] Tab键导航
- [ ] Enter发送消息
- [ ] Esc关闭对话框
- [ ] 快捷键提示

### 屏幕阅读器 Screen Reader
- [ ] 按钮有aria-label
- [ ] 输入框有placeholder
- [ ] 状态有语音提示

## 测试统计 Test Statistics

- **总测试项**: 120+
- **核心功能**: 40+
- **高级功能**: 30+
- **边界情况**: 20+
- **性能/可访问性**: 30+

## 测试环境 Test Environments

- [ ] Windows (Flutter Desktop)
- [ ] macOS (Flutter Desktop)
- [ ] Web (Chrome)
- [ ] Web (Firefox)
- [ ] Web (Safari)
- [ ] Android
- [ ] iOS

## 已知问题 Known Issues

无

## 测试通过率 Pass Rate

- **目标**: 95%+
- **当前**: _待测试_

---

**最后更新**: 2024-10-16
**测试人员**: _待指定_




