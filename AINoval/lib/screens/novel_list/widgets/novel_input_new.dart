import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/widgets/common/animated_container_widget.dart';
import 'package:ainoval/widgets/common/model_display_selector.dart';
import 'package:ainoval/models/unified_ai_model.dart';

import 'package:ainoval/models/strategy_template_info.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/screens/settings/settings_panel.dart';
import 'package:ainoval/screens/editor/managers/editor_state_manager.dart';
import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_bloc.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_event.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_state.dart';
import '../../setting_generation/novel_settings_generator_screen.dart';
// 📚 知识库集成
import 'package:ainoval/models/knowledge_base_integration_mode.dart';
import 'package:ainoval/screens/setting_generation/widgets/knowledge_base_setting_selector.dart';
// 🏪 策略市场
import 'enhanced_strategy_selector.dart';

class NovelInputNew extends StatefulWidget {
  final String prompt;
  final Function(String) onPromptChanged;
  final UnifiedAIModel? selectedModel;
  final Function(UnifiedAIModel?)? onModelSelected;

  const NovelInputNew({
    Key? key,
    required this.prompt,
    required this.onPromptChanged,
    this.selectedModel,
    this.onModelSelected,
  }) : super(key: key);

  @override
  State<NovelInputNew> createState() => _NovelInputNewState();
}

class _NovelInputNewState extends State<NovelInputNew> with TickerProviderStateMixin {
  late TextEditingController _controller;
  bool _isGenerating = false;
  bool _isPolishing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _selectedStrategy = ''; // 默认为空，将从后端获取策略列表后设置
  bool _suppressControllerListener = false; // 避免程序化同步时反向通知父组件
  
  // 📚 知识库集成状态
  KnowledgeBaseIntegrationMode _knowledgeBaseMode = KnowledgeBaseIntegrationMode.none;
  List<SelectedKnowledgeBaseItem> _selectedKnowledgeBases = []; // 用于复用/仿写模式
  List<SelectedKnowledgeBaseItem> _selectedReferenceKnowledgeBases = []; // 用于混合模式的参考

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.prompt);
    _controller.addListener(() {
      if (_suppressControllerListener) return;
      widget.onPromptChanged(_controller.text);
    });

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // 首帧后启动心跳动画，避免在构建期/重启切换期驱动渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });

    // 初始化时加载可用策略（仅已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final String? userId = AppConfig.userId; // 未登录为 null
      if (userId != null && userId.isNotEmpty) {
        context.read<SettingGenerationBloc>().add(const LoadStrategiesEvent());
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!mounted) return;
    // 热重载/重启后，停止并在下一帧重启动画，避免在已释放的视图上渲染
    _pulseController.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });
  }

  @override
  void didUpdateWidget(NovelInputNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prompt != oldWidget.prompt && widget.prompt != _controller.text) {
      _suppressControllerListener = true;
      _controller.value = TextEditingValue(
        text: widget.prompt,
        selection: TextSelection.collapsed(offset: widget.prompt.length),
      );
      _suppressControllerListener = false;
    }
  }

  @override
  void dispose() {
    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // Future<void> _handleGenerate() async {
  //   if (_controller.text.trim().isEmpty) return;
  //   
  //   setState(() {
  //     _isGenerating = true;
  //   });

  //   // 模拟生成过程
  //   await Future.delayed(const Duration(seconds: 2));

  //   setState(() {
  //     _isGenerating = false;
  //   });
  // }

  // Future<void> _handlePolish() async {
  //   if (_controller.text.trim().isEmpty) return;
  //   
  //   setState(() {
  //     _isPolishing = true;
  //   });

  //   // 模拟AI润色过程
  //   await Future.delayed(const Duration(milliseconds: 1500));
  //   
  //   final polishedPrompt = '经过AI润色：${_controller.text}。增加更多细节描述，包含丰富的情感色彩和生动的场景描写，让故事更加引人入胜。';
  //   _controller.text = polishedPrompt;
  //   
  //   setState(() {
  //     _isPolishing = false;
  //   });
  // }

  Future<void> _handleGenerateSettings() async {
    
    // 📚 复用模式允许空提示词，其他模式需要提示词
    final needsPrompt = _knowledgeBaseMode != KnowledgeBaseIntegrationMode.reuse;
    if (needsPrompt && _controller.text.trim().isEmpty) {
      print('🔥 [DEBUG] 被拦截：需要提示词但提示词为空');
      return;
    }
    
    if (widget.selectedModel == null) {
      print('🔥 [DEBUG] 被拦截：未选择模型');
      return;
    }

    // 检查登录状态
    final String? userId = AppConfig.userId;
    if (userId == null || userId.isEmpty) {
      print('🔥 [DEBUG] 被拦截：未登录');
      // 未登录，提示用户登录
      _showLoginRequiredDialog();
      return;
    }

    print('🔥 [DEBUG] 执行工具模型检查');
    final ok = await _precheckToolModelAndMaybePrompt();
    if (!ok) {
      print('🔥 [DEBUG] 被拦截：工具模型检查未通过');
      return;
    }

    print('🔥 [DEBUG] 打开设定生成器对话框');
    // 打开设定生成器对话框，并传递选择的策略和知识库参数
    _showSettingGeneratorDialog(context);
  }

  /// 轻量前置检查：当没有可用公共模型或缺少 jsonify/jsonIf 标签，且用户也未设置“工具调用默认”时，提示去设置。
  /// 返回 true 表示继续生成，false 表示用户选择了取消或去设置。
  Future<bool> _precheckToolModelAndMaybePrompt() async {
    // 用户已设置工具默认且已验证 → 直接通过
    final aiState = context.read<AiConfigBloc>().state;
    final hasToolDefault = aiState.configs.any((c) => c.isToolDefault && c.isValidated);
    if (hasToolDefault) return true;

    // 公共模型检查（仅在已加载时判断，避免阻塞）
    final publicBloc = context.read<PublicModelsBloc>();
    final publicState = publicBloc.state;
    bool needPrompt = false;
    if (publicState is PublicModelsLoaded) {
      final models = publicState.models;
      final tagsNeedles = {'jsonify', 'jsonif', 'json-if', 'json_if'};
      final hasJsonifyTag = models.any((m) => (m.tags ?? const <String>[]) 
          .map((t) => t.toLowerCase())
          .any((t) => tagsNeedles.contains(t)));
      final noPublic = models.isEmpty;
      needPrompt = noPublic || !hasJsonifyTag;
    } else {
      // 轻量：若未加载，不做拦截
      needPrompt = false;
    }

    if (!needPrompt) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请配置工具调用模型'),
        content: const Text('未检测到可用的公共工具模型或缺少 jsonify 标签。建议先在“模型服务管理”中设置一个工具调用默认模型（成本低、速度快），例如：Gemini 2.0 Flash。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(false);
              final userId = AppConfig.userId ?? '';
              await showDialog(
                context: context,
                barrierDismissible: true,
                builder: (dialogContext) => Dialog(
                  insetPadding: const EdgeInsets.all(16),
                  backgroundColor: Colors.transparent,
                  child: SettingsPanel(
                    stateManager: EditorStateManager(),
                    userId: userId,
                    onClose: () => Navigator.of(dialogContext).pop(),
                    editorSettings: const EditorSettings(),
                    onEditorSettingsChanged: (_) {},
                    initialCategoryIndex: 0, // 聚焦“模型服务”
                  ),
                ),
              );
            },
            child: const Text('去设置'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续生成'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要登录'),
        content: const Text('使用"我的设定"功能需要先登录账号'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: 触发登录流程，这里可以根据应用的登录方式来实现
              // 例如：可以导航到登录页面或者显示登录对话框
            },
            child: const Text('立即登录'),
          ),
        ],
      ),
    );
  }

  void _showSettingGeneratorDialog(BuildContext context) {
    print('🔥 [DEBUG] 模式: ${_knowledgeBaseMode.displayName}');
    print('🔥 [DEBUG] 复用列表数量: ${_selectedKnowledgeBases.length}');
    print('🔥 [DEBUG] 参考列表数量: ${_selectedReferenceKnowledgeBases.length}');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SettingGeneratorDialog(
        initialPrompt: _controller.text.trim(),
        selectedModel: widget.selectedModel,
        selectedStrategy: _selectedStrategy,
        // 📚 传递知识库参数
        knowledgeBaseMode: _knowledgeBaseMode,
        selectedKnowledgeBases: _selectedKnowledgeBases,
        selectedReferenceKnowledgeBases: _selectedReferenceKnowledgeBases,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    
    return AnimatedContainerWidget(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                // Icon with animation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                WebTheme.getPrimaryColor(context).withOpacity(0.3 * _pulseAnimation.value),
                                WebTheme.getSecondaryColor(context).withOpacity(0.2 * _pulseAnimation.value),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            WebTheme.getPrimaryColor(context),
                            WebTheme.getSecondaryColor(context),
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 32,
                        color: WebTheme.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'AI小说设定助手',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        foreground: Paint()
                          ..shader = LinearGradient(
                            colors: [
                              WebTheme.getPrimaryColor(context),
                              WebTheme.getPrimaryColor(context).withOpacity(0.8),
                              WebTheme.getSecondaryColor(context),
                            ],
                          ).createShader(const Rect.fromLTWH(0, 0, 400, 70)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Subtitle
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: WebTheme.getPrimaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '设定生成，黄金三章',
                      style: TextStyle(
                        fontSize: 18,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: WebTheme.getPrimaryColor(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Description
                Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Text(
                    '输入您的创意想法，或者选择下方的分类标签，让AI为您创作精彩的小说设定和开篇黄金三章',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Input Area
          Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Stack(
              children: [
                // Background blur effect
                Container(
                  margin: const EdgeInsets.all(8),
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        WebTheme.getPrimaryColor(context).withOpacity(0.1),
                        WebTheme.getSecondaryColor(context).withOpacity(0.05),
                      ],
                    ),
                  ),
                ),
                // Text Field
                Container(
                  decoration: BoxDecoration(
                    color: WebTheme.getSurfaceColor(context).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: WebTheme.getBorderColor(context),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: WebTheme.getShadowColor(context, opacity: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _controller,
                        // 📚 复用模式下不可输入
                        enabled: _knowledgeBaseMode != KnowledgeBaseIntegrationMode.reuse,
                        readOnly: _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse,
                        maxLines: 8,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                              ? WebTheme.getSecondaryTextColor(context)
                              : WebTheme.getTextColor(context),
                        ),
                        decoration: InputDecoration(
                          hintText: _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                              ? '复用模式下无需输入提示词，请在下方选择知识库小说'
                              : (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.imitation ||
                                 _knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid)
                                  ? '请详细描述生成需求，选中的知识库设定将作为参考加入提示词...'
                                  : '请输入您的小说创意想法，例如：一个现代都市的年轻程序员意外获得了穿越时空的能力...',
                          hintStyle: TextStyle(
                            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(24),
                        ),
                      ),
                      // Bottom Actions - 🎨 优化为两行布局
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: WebTheme.getEmptyStateColor(context).withOpacity(0.5),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          children: [
                            // 🎨 第一行：核心配置（模型 + 策略 + 生成按钮）
                            Row(
                              children: [
                                // 模型选择器
                                Expanded(
                                  flex: 3,
                                  child: ModelDisplaySelector(
                                    selectedModel: widget.selectedModel,
                                    onModelSelected: widget.onModelSelected,
                                    size: ModelDisplaySize.small,
                                    height: 48,
                                    showIcon: true,
                                    showTags: true,
                                    showSettingsButton: true,
                                    placeholder: '选择AI模型',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                
                                // 策略选择器（带市场按钮）
                                Expanded(
                                  flex: 3,
                                  child: _buildStrategySelector(),
                                ),
                                
                                // 中间留空
                                const Expanded(
                                  flex: 2,
                                  child: SizedBox(),
                                ),
                                
                                // 生成设定按钮
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      onPressed: _shouldEnableGenerateButton()
                                        ? () async { await _handleGenerateSettings(); }
                                        : null,
                                      icon: Icon(
                                        _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                                            ? Icons.file_copy
                                            : Icons.psychology,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse
                                            ? '开始设定复用'
                                            : '生成设定',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        side: BorderSide(
                                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // 🎨 第二行：知识库配置
                            Row(
                              children: [
                                // 知识库模式选择器
                                Expanded(
                                  flex: 3,
                                  child: _buildKnowledgeBaseModeSelector(),
                                ),
                                
                                const SizedBox(width: 12),
                                
                                // 知识库引用提示（精简版，只显示图标+文字）
                                Tooltip(
                                  message: '💡 使用知识库功能\n可以复用或参考已有小说的设定\n提升生成质量和一致性',
                                  preferBelow: false,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: WebTheme.getPrimaryColor(context),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                  child: Container(
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: WebTheme.getPrimaryColor(context),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '知识库说明',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: WebTheme.getPrimaryColor(context),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                
                                // 右侧留空保持对齐
                                const Expanded(
                                  flex: 5,
                                  child: SizedBox(),
                                ),
                              ],
                            ),
                            // // Polish Button
                            // Flexible(
                            //   child: OutlinedButton.icon(
                            //     onPressed: _controller.text.trim().isEmpty || _isPolishing || _isGenerating
                            //       ? null
                            //       : _handlePolish,
                            //     icon: _isPolishing
                            //       ? SizedBox(
                            //           width: 16,
                            //           height: 16,
                            //           child: CircularProgressIndicator(
                            //             strokeWidth: 2,
                            //             valueColor: AlwaysStoppedAnimation<Color>(
                            //               WebTheme.getPrimaryColor(context),
                            //             ),
                            //           ),
                            //         )
                            //       : const Icon(Icons.auto_fix_high, size: 18),
                            //     label: Text(_isPolishing ? 'AI润色中...' : 'AI润色'),
                            //     style: OutlinedButton.styleFrom(
                            //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            //       side: BorderSide(
                            //         color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                            //         width: 1.5,
                            //       ),
                            //     ),
                            //   ),
                            // ),
                            // // Generate Button
                            // Flexible(
                            //   child: ElevatedButton.icon(
                            //     onPressed: _controller.text.trim().isEmpty || _isGenerating || _isPolishing
                            //       ? null
                            //       : _handleGenerate,
                            //     icon: _isGenerating
                            //       ? SizedBox(
                            //           width: 18,
                            //           height: 18,
                            //           child: CircularProgressIndicator(
                            //             strokeWidth: 2,
                            //             valueColor: AlwaysStoppedAnimation<Color>(
                            //               WebTheme.white,
                            //             ),
                            //           ),
                            //         )
                            //       : const Icon(Icons.send, size: 18),
                            //     label: Text(_isGenerating ? 'AI正在创作中...' : '开始创作'),
                            //     style: ElevatedButton.styleFrom(
                            //       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            //       backgroundColor: WebTheme.getPrimaryColor(context),
                            //       foregroundColor: WebTheme.white,
                            //       elevation: 0,
                            //       shape: RoundedRectangleBorder(
                            //         borderRadius: BorderRadius.circular(8),
                            //       ),
                            //     ),
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 📚 知识库选择器区域 - 根据模式显示
          if (_knowledgeBaseMode != KnowledgeBaseIntegrationMode.none) ...[
            const SizedBox(height: 24),
            Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: WebTheme.getSurfaceColor(context).withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: WebTheme.getBorderColor(context),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📚 混合模式显示两个选择器
                  if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) ...[
                    Text(
                      '复用知识库设定',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
                        border: Border.all(
                          color: WebTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: WebTheme.getPrimaryColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '这些设定将被直接复用（不经过AI）',
                              style: TextStyle(
                                fontSize: 12,
                                color: WebTheme.getTextColor(context),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    KnowledgeBaseSettingSelector(
                      selectedItems: _selectedKnowledgeBases,
                      onSelectionChanged: (items) {
                        setState(() {
                          _selectedKnowledgeBases = items;
                        });
                      },
                      multipleSelection: true,
                      hintText: '搜索要复用的知识库小说（支持多选）...',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '参考知识库设定',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WebTheme.getSecondaryColor(context).withOpacity(0.05),
                        border: Border.all(
                          color: WebTheme.getSecondaryColor(context).withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: WebTheme.getSecondaryColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '这些设定将加入提示词，作为AI参考',
                              style: TextStyle(
                                fontSize: 12,
                                color: WebTheme.getTextColor(context),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    KnowledgeBaseSettingSelector(
                      selectedItems: _selectedReferenceKnowledgeBases,
                      onSelectionChanged: (items) {
                        setState(() {
                          _selectedReferenceKnowledgeBases = items;
                        });
                      },
                      multipleSelection: true,
                      hintText: '搜索参考的知识库小说（支持多选）...',
                    ),
                  ] else ...[
                    // 📚 其他模式显示单个选择器
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
                        border: Border.all(
                          color: WebTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: WebTheme.getPrimaryColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _knowledgeBaseMode.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: WebTheme.getTextColor(context),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    KnowledgeBaseSettingSelector(
                      selectedItems: _selectedKnowledgeBases,
                      onSelectionChanged: (items) {
                        setState(() {
                          _selectedKnowledgeBases = items;
                        });
                      },
                      multipleSelection: true,
                      hintText: '搜索知识库小说（支持多选）...',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 📚 构建知识库模式选择器（下拉框）
  Widget _buildKnowledgeBaseModeSelector() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WebTheme.getBorderColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<KnowledgeBaseIntegrationMode>(
          value: _knowledgeBaseMode,
          isExpanded: true,
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getTextColor(context),
          ),
          dropdownColor: WebTheme.getSurfaceColor(context),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          items: KnowledgeBaseIntegrationMode.values.map((mode) {
            return DropdownMenuItem(
              value: mode,
              child: Tooltip(
                message: mode.description,
                child: Text(
                  mode.displayName,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _knowledgeBaseMode = value;
                // 清空所有选择
                _selectedKnowledgeBases = [];
                _selectedReferenceKnowledgeBases = [];
              });
            }
          },
        ),
      ),
    );
  }

  /// 📚 判断生成按钮是否应该启用
  bool _shouldEnableGenerateButton() {
    final result = _calculateShouldEnable();
    print('🔥 [DEBUG] _shouldEnableGenerateButton() = $result');
    print('🔥 [DEBUG] - _isGenerating: $_isGenerating');
    print('🔥 [DEBUG] - _isPolishing: $_isPolishing');
    print('🔥 [DEBUG] - selectedModel: ${widget.selectedModel != null}');
    print('🔥 [DEBUG] - knowledgeBaseMode: ${_knowledgeBaseMode.displayName}');
    print('🔥 [DEBUG] - selectedKnowledgeBases: ${_selectedKnowledgeBases.length}');
    print('🔥 [DEBUG] - prompt: "${_controller.text}"');
    return result;
  }
  
  bool _calculateShouldEnable() {
    print('🔥 [DEBUG] ========== 检查按钮启用条件 ==========');
    print('🔥 [DEBUG] _isGenerating: $_isGenerating');
    print('🔥 [DEBUG] _isPolishing: $_isPolishing');
    print('🔥 [DEBUG] widget.selectedModel: ${widget.selectedModel != null}');
    
    if (_isGenerating || _isPolishing || widget.selectedModel == null) {
      print('🔥 [DEBUG] ❌ 基础条件不满足');
      return false;
    }

    // 复用模式：只需要选择知识库
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.reuse) {
      final result = _selectedKnowledgeBases.isNotEmpty;
      print('🔥 [DEBUG] 复用模式: _selectedKnowledgeBases.length = ${_selectedKnowledgeBases.length}');
      print('🔥 [DEBUG] 复用模式结果: $result');
      return result;
    }

    // 无知识库模式：需要输入提示词
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.none) {
      final result = _controller.text.trim().isNotEmpty;
      print('🔥 [DEBUG] 无知识库模式: prompt.length = ${_controller.text.trim().length}');
      print('🔥 [DEBUG] 无知识库模式结果: $result');
      return result;
    }

    // 仿写模式：需要提示词和知识库
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.imitation) {
      final hasPrompt = _controller.text.trim().isNotEmpty;
      final hasKB = _selectedKnowledgeBases.isNotEmpty;
      print('🔥 [DEBUG] 仿写模式: hasPrompt = $hasPrompt, prompt.length = ${_controller.text.trim().length}');
      print('🔥 [DEBUG] 仿写模式: hasKB = $hasKB, _selectedKnowledgeBases.length = ${_selectedKnowledgeBases.length}');
      final result = hasPrompt && hasKB;
      print('🔥 [DEBUG] 仿写模式结果: $result');
      return result;
    }

    // 混合模式：需要提示词，至少一个知识库列表有内容
    if (_knowledgeBaseMode == KnowledgeBaseIntegrationMode.hybrid) {
      final hasPrompt = _controller.text.trim().isNotEmpty;
      final hasReuseKB = _selectedKnowledgeBases.isNotEmpty;
      final hasRefKB = _selectedReferenceKnowledgeBases.isNotEmpty;
      print('🔥 [DEBUG] 混合模式: hasPrompt = $hasPrompt, prompt.length = ${_controller.text.trim().length}');
      print('🔥 [DEBUG] 混合模式: hasReuseKB = $hasReuseKB, _selectedKnowledgeBases.length = ${_selectedKnowledgeBases.length}');
      print('🔥 [DEBUG] 混合模式: hasRefKB = $hasRefKB, _selectedReferenceKnowledgeBases.length = ${_selectedReferenceKnowledgeBases.length}');
      final result = hasPrompt && (hasReuseKB || hasRefKB);
      print('🔥 [DEBUG] 混合模式结果: $result');
      return result;
    }

    print('🔥 [DEBUG] ❌ 未知模式');
    return false;
  }

  /// 构建策略选择器
  Widget _buildStrategySelector() {
    return BlocBuilder<SettingGenerationBloc, SettingGenerationState>(
      builder: (context, state) {
        List<StrategyTemplateInfo> strategies = [];
        bool isLoading = false;
        
        if (state is SettingGenerationInitial) {
          isLoading = true;
        } else if (state is SettingGenerationReady) {
          strategies = state.strategies;
        } else if (state is SettingGenerationInProgress) {
          strategies = state.strategies;
        } else if (state is SettingGenerationCompleted) {
          strategies = state.strategies;
        }

        // 如果策略为空，显示加载状态而不是使用硬编码默认值
        if (strategies.isEmpty && !isLoading) {
          isLoading = true;
        }
        
        // 智能选择当前策略：优先选择"番茄小说/网文/tomato"，否则回退到"九线法"，再否则选第一个
        if (strategies.isNotEmpty && (_selectedStrategy.isEmpty || !strategies.any((s) => s.promptTemplateId == _selectedStrategy))) {
          // 1) 优先匹配番茄网文策略
          final tomatoStrategy = strategies.where((s) =>
            s.name.contains('番茄') ||
            s.name.contains('网文') ||
            s.name.toLowerCase().contains('tomato')
          ).toList();

          if (tomatoStrategy.isNotEmpty) {
            _selectedStrategy = tomatoStrategy.first.promptTemplateId;
          } else {
            // 2) 次选：九线法
            final nineLineStrategy = strategies.where((s) =>
              s.name.contains('九线法') ||
              s.name.contains('nine-line') ||
              s.name.toLowerCase().contains('nine')
            ).toList();

            if (nineLineStrategy.isNotEmpty) {
              _selectedStrategy = nineLineStrategy.first.promptTemplateId;
            } else {
              // 3) 兜底：第一个
              _selectedStrategy = strategies.first.promptTemplateId;
            }
          }
        }

        // 🆕 使用增强的策略选择器（包含市场入口）
        return EnhancedStrategySelector(
          strategies: strategies,
          selectedStrategy: _selectedStrategy,
          isLoading: isLoading,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedStrategy = value;
              });
              // 记录用户的选择以便调试
              print('用户选择策略: $value');
            }
          },
        );
      },
    );
  }
}

/// 设定生成器对话框包装器
class _SettingGeneratorDialog extends StatelessWidget {
  final String initialPrompt;
  final UnifiedAIModel? selectedModel;
  final String selectedStrategy;
  // 📚 知识库集成参数
  final KnowledgeBaseIntegrationMode knowledgeBaseMode;
  final List<SelectedKnowledgeBaseItem> selectedKnowledgeBases;
  final List<SelectedKnowledgeBaseItem> selectedReferenceKnowledgeBases;

  const _SettingGeneratorDialog({
    required this.initialPrompt,
    this.selectedModel,
    required this.selectedStrategy,
    this.knowledgeBaseMode = KnowledgeBaseIntegrationMode.none,
    this.selectedKnowledgeBases = const [],
    this.selectedReferenceKnowledgeBases = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            // Setting generator content
            Expanded(
              child: NovelSettingsGeneratorScreen(
                initialPrompt: initialPrompt,
                selectedModel: selectedModel,
                selectedStrategy: selectedStrategy,
                autoStart: true, // 自动开始生成
                // 📚 传递知识库参数
                initialKnowledgeBaseMode: knowledgeBaseMode,
                initialSelectedKnowledgeBases: selectedKnowledgeBases,
                initialReferenceKnowledgeBases: selectedReferenceKnowledgeBases,
              ),
            ),
          ],
        ),
      ),
    );
  }
}