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
    if (_controller.text.trim().isEmpty || widget.selectedModel == null) return;

    // 检查登录状态
    final String? userId = AppConfig.userId;
    if (userId == null || userId.isEmpty) {
      // 未登录，提示用户登录
      _showLoginRequiredDialog();
      return;
    }

    final ok = await _precheckToolModelAndMaybePrompt();
    if (!ok) return;

    // 打开设定生成器对话框，并传递选择的策略
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SettingGeneratorDialog(
        initialPrompt: _controller.text.trim(),
        selectedModel: widget.selectedModel,
        selectedStrategy: _selectedStrategy,
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
                        maxLines: 8,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: WebTheme.getTextColor(context),
                        ),
                        decoration: InputDecoration(
                          hintText: '请输入您的小说创意想法，例如：一个现代都市的年轻程序员意外获得了穿越时空的能力...',
                          hintStyle: TextStyle(
                            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(24),
                        ),
                      ),
                      // Bottom Actions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: WebTheme.getEmptyStateColor(context).withOpacity(0.5),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            // 左侧区域：模型选择器 + 策略选择器 (占4份)
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  // Model Selection Button
                                  Expanded(
                                    flex: 2,
                                    child: ModelDisplaySelector(
                                      selectedModel: widget.selectedModel,
                                      onModelSelected: widget.onModelSelected,
                                      size: ModelDisplaySize.small,
                                      height: 48, // 增加一半高度保持一致
                                      showIcon: true,
                                      showTags: true,
                                      showSettingsButton: true,
                                      placeholder: '选择AI模型',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Strategy Selection Dropdown
                                  Expanded(
                                    flex: 1,
                                    child: _buildStrategySelector(),
                                  ),
                                ],
                              ),
                            ),
                            // 中间留空区域 (占3份)
                            const Expanded(
                              flex: 3,
                              child: SizedBox(),
                            ),
                            // 右侧区域：生成设定按钮 (占2份)
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 48, // 确保按钮高度与其他组件一致
                                child: OutlinedButton.icon(
                                  onPressed: _controller.text.trim().isEmpty || 
                                           widget.selectedModel == null || 
                                           _isGenerating || 
                                           _isPolishing
                                    ? null
                                    : () async { await _handleGenerateSettings(); },
                                  icon: const Icon(Icons.psychology, size: 18),
                                  label: const Text('生成设定'),
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
        ],
      ),
    );
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
        
        // 智能选择当前策略：优先选择“番茄小说/网文/tomato”，否则回退到“九线法”，再否则选第一个
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

        return Container(
          height: 48, // 增加一半高度 (32 * 1.5)
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context).withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: WebTheme.getBorderColor(context).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        WebTheme.getPrimaryColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '加载中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                ],
              )
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedStrategy.isEmpty ? null : _selectedStrategy,
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
                  items: strategies.map((strategy) {
                    return DropdownMenuItem(
                      value: strategy.promptTemplateId,
                      child: Tooltip(
                        message: strategy.description,
                        child: Text(
                          strategy.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStrategy = value;
                      });
                      // 记录用户的选择以便调试
                      print('用户选择策略: $value');
                    }
                  },
                ),
              ),
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

  const _SettingGeneratorDialog({
    required this.initialPrompt,
    this.selectedModel,
    required this.selectedStrategy,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}