import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/widgets/common/index.dart';
import 'package:ainoval/widgets/common/unified_ai_model_dropdown.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/widgets/common/credit_confirmation_dialog.dart';
import 'package:ainoval/utils/context_selection_helper.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_bloc.dart';
import 'package:ainoval/blocs/setting_generation/setting_generation_event.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/models/compose_preview.dart';
import 'dart:async';

import 'package:ainoval/widgets/common/compose/chapter_count_field.dart';
import 'package:ainoval/widgets/common/compose/chapter_length_field.dart';
import 'package:ainoval/widgets/common/compose/include_depth_field.dart';

class GoldenThreeChaptersDialog extends StatefulWidget {
  const GoldenThreeChaptersDialog({
    super.key,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.initialSelectedUnifiedModel,
    this.settingSessionId,
    this.onStarted,
  });

  final Novel? novel;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;
  final UnifiedAIModel? initialSelectedUnifiedModel;
  final String? settingSessionId;
  final VoidCallback? onStarted; // 新增：开始生成回调

  @override
  State<GoldenThreeChaptersDialog> createState() => _GoldenThreeChaptersDialogState();
}

class _GoldenThreeChaptersDialogState extends State<GoldenThreeChaptersDialog> {
  // 基础
  final TextEditingController _instructionsController = TextEditingController();
  UnifiedAIModel? _selectedModel;
  final GlobalKey _modelSelectorKey = GlobalKey();

  // 上下文
  late ContextSelectionData _contextSelectionData;
  bool _enableSmartContext = true;
  bool _associateSettingTree = true; // 是否把当前设定Session关联为小说设定
  bool _includeWholeSettingTree = true; // 是否将整个设定树纳入上下文

  // 章节参数
  String _mode = 'outline_plus_chapters'; // outline | chapters | outline_plus_chapters
  int _chapterCount = 3;
  String _includeDepth = 'full'; // 默认全文
  String? _lengthPreset = 'long'; // 默认长
  String _customLength = '';
  double _temperature = 0.7;
  double _topP = 0.9;
  String? _promptTemplateId;
  String? _s2sTemplateId; // 仅"先大纲后章节"使用的 SUMMARY_TO_SCENE 模板ID

  OverlayEntry? _tempOverlay;
  bool _previewRequested = false;

  // 写作就绪（由后端发出的 composeReady 信号控制）
  ComposeReadyInfo? _composeReady;
  StreamSubscription<ComposeReadyInfo>? _composeReadySub;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.initialSelectedUnifiedModel;
    _contextSelectionData = ContextSelectionHelper.initializeContextData(
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
    );

    // 订阅后端就绪信号，仅当当前对话所对应的 sessionId 匹配时更新
    try {
      final bloc = context.read<SettingGenerationBloc>();
      _composeReadySub = bloc.composeReadyStream.listen((info) {
        if (widget.settingSessionId != null && (widget.settingSessionId!.isNotEmpty)) {
          if (info.sessionId != widget.settingSessionId) return;
        }
        if (mounted) {
          setState(() => _composeReady = info);
        } else {
          _composeReady = info;
        }
      });
    } catch (_) {}
  }

  int _mapLengthToWordCount(String? preset, String custom) {
    // 字数映射：短中长分别对应1000、2000、3000字
    if (preset == 'short') return 1000;
    if (preset == 'medium') return 2000;
    if (preset == 'long') return 3000;
    // 自定义数字（若用户直接输入数字）
    final n = int.tryParse(custom.trim());
    if (n != null && n > 0) return n;
    // 默认
    return 3000;
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('生成模式', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('只生成大纲'),
              selected: _mode == 'outline',
              onSelected: (_) => setState(() => _mode = 'outline'),
            ),
            ChoiceChip(
              label: const Text('直接生成章节（暂时禁用）'),
              selected: _mode == 'chapters',
              onSelected: null, // 禁用该选项
            ),
            ChoiceChip(
              label: const Text('先大纲后章节'),
              selected: _mode == 'outline_plus_chapters',
              onSelected: (_) => setState(() => _mode = 'outline_plus_chapters'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _mode == 'outline'
              ? '只输出分章节大纲（不生成正文）'
              : _mode == 'outline_plus_chapters'
                  ? '先输出大纲，再按大纲逐章生成正文'
                  : '直接生成章节概要与正文（当前不可用）',
          style: Theme.of(context).textTheme.bodySmall,
        )
      ],
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _tempOverlay?.remove();
    _composeReadySub?.cancel();
    super.dispose();
  }

  bool _canStartWriting() {
    final info = _composeReady;
    if (info == null) return false; // 默认为不可用，直到收到服务器就绪信号
    if (widget.settingSessionId != null && (widget.settingSessionId!.isNotEmpty)) {
      if (info.sessionId != widget.settingSessionId) return false;
    }
    return info.ready;
  }

  String _notReadyReasonText() {
    final r = (_composeReady?.reason ?? '').trim();
    switch (r) {
      case 'no_session':
        return '未绑定会话（等待会话建立或绑定完成）';
      case 'no_novelId':
        return '未提供小说ID（请确保 novelId 已在请求中传递）';
      case 'ok':
        return '';
      default:
        return '内容保存/绑定进行中，请稍候';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialogTemplate(
      title: '生成黄金三章',
      tabs: const [
        TabItem(id: 'tweak', label: '调整', icon: Icons.edit)
      ],
      tabContents: [
        _buildTweakTab(context),
      ],
      showPresets: true,
      usePresetDropdown: true,
      presetFeatureType: AIRequestType.novelCompose.value,
      novelId: widget.novel?.id,
      showModelSelector: true,
      modelSelectorData: _selectedModel != null
          ? ModelSelectorData(modelName: _selectedModel!.displayName, maxOutput: '~12000 words', isModerated: true)
          : const ModelSelectorData(modelName: '选择模型'),
      onModelSelectorTap: _showModelSelectorDropdown,
      modelSelectorKey: _modelSelectorKey,
      primaryActionLabel: '开始生成',
      onPrimaryAction: _handleGenerate,
      onClose: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildTweakTab(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormFieldFactory.createMultiSelectInstructionsWithPresetsField(
            controller: _instructionsController,
            presets: const [],
            title: '生成指令',
            description: '说明黄金三章的风格、节奏、冲突等',
            placeholder: '例如：家庭悬疑氛围、快节奏、强和弦结尾',
          ),
          const SizedBox(height: 16),
          // 生成模式选择
          _buildModeSelector(),
          const SizedBox(height: 16),
          ChapterCountField(value: _chapterCount, onChanged: (v) => setState(() => _chapterCount = v)),
          const SizedBox(height: 16),
          ChapterLengthField(
            preset: _lengthPreset,
            customLength: _customLength,
            onPresetChanged: (v) => setState(() { _lengthPreset = v; _customLength = ''; }),
            onCustomChanged: (v) => setState(() { _lengthPreset = null; _customLength = v; }),
          ),
          const SizedBox(height: 16),
          IncludeDepthField(value: _includeDepth, onChanged: (v) => setState(() => _includeDepth = v)),
          const SizedBox(height: 16),
          SmartContextToggle(
            value: _associateSettingTree,
            onChanged: (v) => setState(() => _associateSettingTree = v),
            title: '关联设定树到小说',
            description: '首次生成时将当前设定Session转换为小说设定并与小说关联',
          ),
          const SizedBox(height: 12),
          SmartContextToggle(
            value: _includeWholeSettingTree,
            onChanged: (v) => setState(() => _includeWholeSettingTree = v),
            title: '上下文包含整个设定树',
            description: '将当前设定Session的全部节点作为上下文（配合上方“上下文深度”使用）',
          ),
          const SizedBox(height: 16),
          FormFieldFactory.createContextSelectionField(
            contextData: _contextSelectionData,
            onSelectionChanged: (d) => setState(() => _contextSelectionData = d),
            title: '附加上下文',
            description: '设定/片段等信息作为生成上下文',
            initialChapterId: null,
            initialSceneId: null,
          ),
          const SizedBox(height: 16),
          FormFieldFactory.createPromptTemplateSelectionField(
            selectedTemplateId: _promptTemplateId,
            onTemplateSelected: (id) => setState(() => _promptTemplateId = id),
            aiFeatureType: AIRequestType.novelCompose.value,
            title: '提示词模板（可选）',
            description: '选择一个模板作为生成基准',
          ),
          if (_mode == 'outline_plus_chapters') ...[
            const SizedBox(height: 12),
            // 复用公共“关联提示词组件”，指定 SUMMARY_TO_SCENE 类型
            FormFieldFactory.createPromptTemplateSelectionField(
              selectedTemplateId: _s2sTemplateId,
              onTemplateSelected: (id) => setState(() => _s2sTemplateId = id),
              aiFeatureType: 'SUMMARY_TO_SCENE',
              title: '章节正文模板（摘要转场景）',
              description: '仅先大纲后章节时生效，用于生成每章正文',
            ),
          ],
          const SizedBox(height: 16),
          FormFieldFactory.createTemperatureSliderField(
            context: context,
            value: _temperature,
            onChanged: (v) => setState(() => _temperature = v),
            onReset: () => setState(() => _temperature = 0.7),
          ),
          const SizedBox(height: 12),
          FormFieldFactory.createTopPSliderField(
            context: context,
            value: _topP,
            onChanged: (v) => setState(() => _topP = v),
            onReset: () => setState(() => _topP = 0.9),
          ),
        ],
      ),
    );
  }


  void _showModelSelectorDropdown() {
    if (_tempOverlay != null) return;
    final box = (_modelSelectorKey.currentContext?.findRenderObject() as RenderBox?);
    final rect = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromLTWH(0, 0, 200, 40);
    _tempOverlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: rect,
      selectedModel: _selectedModel,
      onModelSelected: (m) => setState(() => _selectedModel = m),
      showSettingsButton: true,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      onClose: () => _tempOverlay = null,
    );
  }

  UniversalAIRequest? _buildPreviewRequest() {
    if (_selectedModel == null) return null;
    final model = _selectedModel!;
    final modelConfig = model.isPublic
        ? createPublicModelConfig(model)
        : (model as PrivateAIModel).userConfig;

    final meta = <String, dynamic>{
      'modelConfigId': model.id,
    };
    if (model.isPublic) {
      meta['isPublicModel'] = true;
      meta['publicModelConfigId'] = model.id;
      meta['publicModelId'] = model.id;
    }

    return UniversalAIRequest(
      requestType: AIRequestType.novelCompose,
      userId: AppConfig.userId ?? 'unknown',
      novelId: widget.novel?.id,
      settingSessionId: widget.settingSessionId,
      modelConfig: modelConfig,
      instructions: _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
      contextSelections: _contextSelectionData,
      enableSmartContext: _enableSmartContext,
      parameters: {
        'mode': _mode,
        'chapterCount': _chapterCount,
        'length': _mapLengthToWordCount(_lengthPreset, _customLength).toString(),
        'include': _includeDepth,
        'includeWholeSettingTree': _includeWholeSettingTree,
        'temperature': _temperature,
        'topP': _topP,
        'promptTemplateId': _promptTemplateId,
        'enableSmartContext': _enableSmartContext,
        'maxTokens': 100000,
        if (_mode == 'outline_plus_chapters' && _s2sTemplateId != null)
          's2sTemplateId': _s2sTemplateId,
      },
      metadata: meta,
    );
  }

  void _handleGenerate() async {
    try {
      if (_selectedModel == null) {
        TopToast.error(context, '请选择AI模型');
        return;
      }

      final model = _selectedModel!;
      AppLogger.i('GoldenThreeChaptersDialog', '🔍 开始生成检查: 模型=${model.displayName}, isPublic=${model.isPublic}, id=${model.id}');
      
      // 🚀 修复：公共模型需要积分确认
      if (model.isPublic) {
        AppLogger.i('GoldenThreeChaptersDialog', '🚀 检测到公共模型，显示积分确认对话框');
        final shouldContinue = await _showCreditConfirmation();
        AppLogger.i('GoldenThreeChaptersDialog', '📋 积分确认结果: shouldContinue=$shouldContinue');
        if (!shouldContinue) {
          AppLogger.i('GoldenThreeChaptersDialog', '❌ 用户取消了积分确认，停止生成');
          return; // 用户取消了操作
        }
        AppLogger.i('GoldenThreeChaptersDialog', '✅ 积分确认通过，继续生成');
      } else {
        AppLogger.i('GoldenThreeChaptersDialog', '🔧 私有模型，跳过积分确认');
      }

      // 派发到 BLoC（由 BLoC 统一组装 UniversalAIRequest 并流式生成）
      // UI切换到结果预览
      widget.onStarted?.call();
      final commonContextSelections = {
        'contextSelections': _contextSelectionData.selectedItems.values
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'type': e.type.value,
                  'metadata': e.metadata,
                  'parentId': e.parentId,
                })
            .toList(),
        'enableSmartContext': _enableSmartContext,
      };

      final commonParams = {
        'length': _mapLengthToWordCount(_lengthPreset, _customLength).toString(), // 传递字数
        'include': _includeDepth,
        'includeWholeSettingTree': _includeWholeSettingTree,
        'temperature': _temperature,
        'topP': _topP,
        'promptTemplateId': _promptTemplateId,
        'enableSmartContext': _enableSmartContext,
        // maxTokens固定为100000，不再与长度绑定
        'maxTokens': 100000,
      };

      switch (_mode) {
        case 'outline':
          context.read<SettingGenerationBloc>().add(StartComposeOutlineEvent(
                userId: AppConfig.userId ?? 'unknown',
                modelConfigId: model.id,
                isPublicModel: model.isPublic,
                publicModelConfigId: model.isPublic ? model.id : null,
                novelId: widget.novel?.id,
                settingSessionId: _associateSettingTree ? widget.settingSessionId : null,
                contextSelections: commonContextSelections,
                instructions: _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
                chapterCount: _chapterCount,
                parameters: commonParams,
              ));
          break;
        case 'outline_plus_chapters':
          final bundleParams = {
            ...commonParams,
            if (_s2sTemplateId != null) 's2sTemplateId': _s2sTemplateId,
          };
          context.read<SettingGenerationBloc>().add(StartComposeBundleEvent(
                userId: AppConfig.userId ?? 'unknown',
                modelConfigId: model.id,
                isPublicModel: model.isPublic,
                publicModelConfigId: model.isPublic ? model.id : null,
                novelId: widget.novel?.id,
                settingSessionId: _associateSettingTree ? widget.settingSessionId : null,
                contextSelections: commonContextSelections,
                instructions: _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
                chapterCount: _chapterCount,
                parameters: bundleParams,
              ));
          break;
        case 'chapters':
        default:
          context.read<SettingGenerationBloc>().add(StartComposeChaptersEvent(
                userId: AppConfig.userId ?? 'unknown',
                modelConfigId: model.id,
                isPublicModel: model.isPublic,
                publicModelConfigId: model.isPublic ? model.id : null,
                novelId: widget.novel?.id,
                settingSessionId: _associateSettingTree ? widget.settingSessionId : null,
                contextSelections: commonContextSelections,
                instructions: _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
                chapterCount: _chapterCount,
                parameters: commonParams,
              ));
      }

      Navigator.of(context).pop();
      TopToast.success(context, '已开始生成黄金三章');
    } catch (e, st) {
      AppLogger.e('GoldenThreeChaptersDialog', '启动生成失败', e, st);
      TopToast.error(context, '启动生成失败：$e');
    }
  }

  // 🚀 使用公共积分确认对话框
  Future<bool> _showCreditConfirmation() async {
    AppLogger.i('GoldenThreeChaptersDialog', '🔧 进入积分确认方法');
    try {
      // 构建预估请求
      AppLogger.i('GoldenThreeChaptersDialog', '🔧 构建预估请求...');
      final estimationRequest = _buildPreviewRequest();
      if (estimationRequest == null) {
        AppLogger.e('GoldenThreeChaptersDialog', '❌ 无法构建预估请求');
        TopToast.error(context, '无法构建预估请求');
        return false;
      }
      AppLogger.i('GoldenThreeChaptersDialog', '✅ 预估请求构建成功');

      // 使用公共积分确认对话框
      AppLogger.i('GoldenThreeChaptersDialog', '🔧 显示积分确认对话框...');
      final result = await showCreditConfirmationDialog(
        context: context,
        modelName: _selectedModel!.displayName,
        featureName: '黄金三章生成',
        request: estimationRequest,
      );
      
      AppLogger.i('GoldenThreeChaptersDialog', '📋 对话框返回结果: $result');
      return result;

    } catch (e) {
      AppLogger.e('GoldenThreeChaptersDialog', '❌ 积分预估失败', e);
      TopToast.error(context, '积分预估失败: $e');
      return false;
    }
  }

  // 为公共模型创建临时配置
  UserAIModelConfigModel createPublicModelConfig(UnifiedAIModel model) {
    final public = (model as PublicAIModel).publicConfig;
    return UserAIModelConfigModel.fromJson({
      'id': public.id,
      'userId': AppConfig.userId ?? 'unknown',
      'alias': public.displayName,
      'modelName': public.modelId,
      'provider': public.provider,
      'apiEndpoint': '',
      'isDefault': false,
      'isValidated': true,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}


void showGoldenThreeChaptersDialog(
  BuildContext context, {
  Novel? novel,
  List<NovelSettingItem> settings = const [],
  List<SettingGroup> settingGroups = const [],
  List<NovelSnippet> snippets = const [],
  UnifiedAIModel? initialSelectedUnifiedModel,
  String? settingSessionId,
  VoidCallback? onStarted,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<AiConfigBloc>()),
        BlocProvider.value(value: context.read<UniversalAIBloc>()),
      ],
      child: GoldenThreeChaptersDialog(
        novel: novel,
        settings: settings,
        settingGroups: settingGroups,
        snippets: snippets,
        initialSelectedUnifiedModel: initialSelectedUnifiedModel,
        settingSessionId: settingSessionId,
        onStarted: onStarted,
      ),
    ),
  );
}


