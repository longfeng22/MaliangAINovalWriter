import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/novel_import/novel_import_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';
import 'package:ainoval/services/api_service/repositories/impl/novel_repository_impl.dart';
import 'package:ainoval/widgets/common/model_display_selector.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/credit_confirmation_dialog.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/config/app_config.dart';

/// 知识库拆书导入对话框
/// 复用小说导入的文件上传和预览功能，但最终调用拆书API
class KnowledgeExtractionImportDialog extends StatefulWidget {
  const KnowledgeExtractionImportDialog({super.key});

  @override
  State<KnowledgeExtractionImportDialog> createState() =>
      _KnowledgeExtractionImportDialogState();
}

class _KnowledgeExtractionImportDialogState
    extends State<KnowledgeExtractionImportDialog> {
  late final NovelImportBloc _importBloc;
  StreamSubscription<NovelImportState>? _importSubscription;
  bool _hasDispatchedPreview = false;

  // 配置选项
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  UnifiedAIModel? _selectedModel;

  // 拆书类型选择 - 完全对应后端KnowledgeExtractionType枚举
  final Map<String, bool> _extractionTypes = {
    // 文风叙事组
    'NARRATIVE_STYLE': true,
    'WRITING_STYLE': true,
    'WORD_USAGE': true,
    // 情节设计组
    'CORE_CONFLICT': true,
    'SUSPENSE_DESIGN': true,
    'STORY_PACING': true,
    // 人物塑造组
    'CHARACTER_BUILDING': true,
    // 小说特点组
    'WORLDVIEW': true,
    'GOLDEN_FINGER': true,
    // 读者情绪组
    'RESONANCE': true,
    'PLEASURE_POINT': true,
    'EXCITEMENT_POINT': true,
    // 热梗搞笑点组
    'HOT_MEMES': true,
    'FUNNY_POINTS': true,
    // 章节大纲
    'CHAPTER_OUTLINE': false, // 默认不选中，因为章节大纲生成时间较长
  };

  final Map<String, String> _extractionTypeNames = {
    // 文风叙事组
    'NARRATIVE_STYLE': '叙事方式',
    'WRITING_STYLE': '文风',
    'WORD_USAGE': '用词特点',
    // 情节设计组
    'CORE_CONFLICT': '核心冲突',
    'SUSPENSE_DESIGN': '悬念设计',
    'STORY_PACING': '故事节奏',
    // 人物塑造组
    'CHARACTER_BUILDING': '人物塑造',
    // 小说特点组
    'WORLDVIEW': '世界观',
    'GOLDEN_FINGER': '金手指',
    // 读者情绪组
    'RESONANCE': '共鸣',
    'PLEASURE_POINT': '爽点',
    'EXCITEMENT_POINT': '嗨点',
    // 热梗搞笑点组
    'HOT_MEMES': '热梗',
    'FUNNY_POINTS': '搞笑点',
    // 章节大纲
    'CHAPTER_OUTLINE': '章节大纲',
  };

  final Map<String, String> _extractionTypeGroups = {
    // 文风叙事组
    'NARRATIVE_STYLE': '文风叙事',
    'WRITING_STYLE': '文风叙事',
    'WORD_USAGE': '文风叙事',
    // 情节设计组
    'CORE_CONFLICT': '情节设计',
    'SUSPENSE_DESIGN': '情节设计',
    'STORY_PACING': '情节设计',
    // 人物塑造组
    'CHARACTER_BUILDING': '人物塑造',
    // 小说特点组
    'WORLDVIEW': '小说特点',
    'GOLDEN_FINGER': '小说特点',
    // 读者情绪组
    'RESONANCE': '读者情绪',
    'PLEASURE_POINT': '读者情绪',
    'EXCITEMENT_POINT': '读者情绪',
    // 热梗搞笑点组
    'HOT_MEMES': '热梗搞笑',
    'FUNNY_POINTS': '热梗搞笑',
    // 章节大纲
    'CHAPTER_OUTLINE': '章节大纲',
  };

  // 自定义提取类型
  final TextEditingController _customTypeController = TextEditingController();
  final List<String> _customTypes = [];

  // 章节限制选择
  int? _chapterLimit; // null表示整本，否则为章节数量

  @override
  void initState() {
    super.initState();
    _importBloc = context.read<NovelImportBloc>();

    // 检查状态并在需要时重置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _importBloc.state;
      if (state is NovelImportSuccess || state is NovelImportFailure) {
        _importBloc.add(ResetImportState());
      }
    });

    // 文件上传完成后自动触发预览（不启用AI摘要，因为只用于获取章节内容）
    _importSubscription = _importBloc.stream.listen((state) {
      if (state is NovelImportFileUploaded) {
        if (_hasDispatchedPreview) return;
        _hasDispatchedPreview = true;
        _importBloc.add(GetImportPreview(
          previewSessionId: state.previewSessionId,
          fileName: state.fileName,
          enableSmartContext: false, // 拆书不需要智能上下文
          enableAISummary: false, // 拆书不需要AI摘要
          aiConfigId: null,
        ));
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _customTypeController.dispose();
    _importSubscription?.cancel();

    // ⚠️ 不在这里清理预览会话！
    // 因为如果用户点击了开始拆书，后端还需要从预览会话中读取内容
    // 后端会在成功获取内容后自动清理预览会话
    // 只有在用户取消（没有开始拆书）时才需要清理
    // 但由于无法区分是取消还是开始拆书后关闭，所以统一不清理
    // 后端会在一定时间后自动清理过期的预览会话

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<NovelImportBloc, NovelImportState>(
      listener: (context, state) {
        // 不需要监听导入成功，因为我们不使用导入功能
      },
      builder: (context, state) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 900, // 增加宽度以适应更多内容
            constraints: const BoxConstraints(
              maxHeight: 800, // 增加高度以显示更多章节
              minHeight: 400,
            ),
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey100 : WebTheme.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _buildHeader(context, state, isDark),
                Expanded(
                  child: _buildContent(context, state, isDark),
                ),
                _buildFooter(context, state, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建头部（复用导入对话框的样式）
  Widget _buildHeader(
      BuildContext context, NovelImportState state, bool isDark) {
    final step = _getCurrentStep(state);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories,
                size: 20,
                color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
              ),
              const SizedBox(width: 8),
              Text(
                '导入小说进行拆书',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
                ),
              ),
              const Spacer(),
              if (state is! NovelImportInProgress)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStepIndicator(step, isDark),
        ],
      ),
    );
  }

  /// 步骤指示器
  Widget _buildStepIndicator(int currentStep, bool isDark) {
    final steps = ['配置选项', '预览确认', '开始拆书'];

    return Row(
      children: [
        for (int i = 1; i <= 3; i++) ...[
          _buildStepItem(i, currentStep, steps[i - 1], isDark),
          if (i < 3) _buildStepConnector(i < currentStep, isDark),
        ],
      ],
    );
  }

  Widget _buildStepItem(int step, int currentStep, String label, bool isDark) {
    final isCompleted = step < currentStep;
    final isCurrent = step == currentStep;

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted || isCurrent
                ? (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                : Colors.transparent,
            border: Border.all(
              color: isCompleted || isCurrent
                  ? (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                  : (isDark ? WebTheme.darkGrey400 : WebTheme.grey400),
              width: 1.5,
            ),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 12, color: WebTheme.white)
                : Text(
                    step.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCurrent
                          ? WebTheme.white
                          : (isDark
                              ? WebTheme.darkGrey500
                              : WebTheme.grey500),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isCurrent
                ? (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                : (isDark ? WebTheme.darkGrey500 : WebTheme.grey500),
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(bool isCompleted, bool isDark) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 15, left: 6, right: 6),
        color: isCompleted
            ? (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
            : (isDark ? WebTheme.darkGrey300 : WebTheme.grey300),
      ),
    );
  }

  /// 构建内容区域
  Widget _buildContent(
      BuildContext context, NovelImportState state, bool isDark) {
    if (state is NovelImportInitial) {
      return _buildConfigurationStep(context, isDark);
    } else if (state is NovelImportUploading ||
        state is NovelImportLoadingPreview) {
      return _buildLoadingStep(context, state, isDark);
    } else if (state is NovelImportPreviewReady) {
      return _buildPreviewStep(context, state, isDark);
    } else if (state is NovelImportFailure) {
      return _buildErrorStep(context, state, isDark);
    }

    return _buildConfigurationStep(context, isDark);
  }

  /// 步骤1：配置选项
  Widget _buildConfigurationStep(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16,
                    color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '上传您的小说文件（支持TXT格式），系统将自动识别章节并使用AI提取写作特征和知识。建议上传前3-5章，约2-5万字。',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 小说简介（可选）
          _buildFormField(
            label: '小说简介',
            required: false,
            child: TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '请简单介绍小说内容（可选，帮助AI更好理解）',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 选择拆书模型
          _buildFormField(
            label: '选择拆书模型',
            required: true,
            child: ModelDisplaySelector(
              selectedModel: _selectedModel,
              onModelSelected: (model) {
                setState(() {
                  _selectedModel = model;
                });
              },
              size: ModelDisplaySize.medium,
              height: 48,
              showIcon: true,
              showTags: true,
              showSettingsButton: false,
              placeholder: '选择AI模型',
            ),
          ),

          // ✅ 公共模型拆书警告提示
          if (_selectedModel != null && _selectedModel!.isPublic) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '拆书功能消耗积分较多，根据内容长度预计消耗 ${_estimateTokens()} tokens × 3 倍',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 提取类型选择
          _buildFormField(
            label: '选择提取类型',
            required: false,
            child: _buildExtractionTypesSelector(isDark),
          ),

          const SizedBox(height: 16),

          // 自定义提取类型
          _buildFormField(
            label: '自定义提取类型（可选）',
            required: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark ? WebTheme.darkGrey700 : WebTheme.grey300,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: TextField(
                          controller: _customTypeController,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '输入自定义提取内容，如：背景音乐风格',
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final text = _customTypeController.text.trim();
                        if (text.isNotEmpty && !_customTypes.contains(text)) {
                          setState(() {
                            _customTypes.add(text);
                            _customTypeController.clear();
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: const Size(60, 32),
                      ),
                      child: const Text('添加', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (_customTypes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _customTypes.map((type) {
                      return Chip(
                        label: Text(type, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() {
                            _customTypes.remove(type);
                          });
                        },
                        backgroundColor: (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                            .withOpacity(0.1),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '自定义类型会以CUSTOM标识传递给后端处理',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建章节限制选择器
  Widget _buildChapterLimitSelector(NovelImportPreviewReady state, bool isDark) {
    final totalChapters = state.previewResponse.totalChapterCount;
    final totalWords = state.previewResponse.totalWordCount;
    
    // 计算实际使用的章节数和字数
    final int effectiveChapters = _chapterLimit ?? totalChapters;
    final double ratio = effectiveChapters / totalChapters;
    final int estimatedWords = (totalWords * ratio).round();
    
    // 判断是否超过3万字
    final bool exceedsLimit = estimatedWords > 30000;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 章节选择按钮组
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 前10章
            if (totalChapters >= 10)
              ChoiceChip(
                label: const Text('前10章', style: TextStyle(fontSize: 12)),
                selected: _chapterLimit == 10,
                onSelected: (selected) {
                  setState(() {
                    _chapterLimit = selected ? 10 : null;
                  });
                },
                selectedColor: (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                    .withOpacity(0.2),
              ),
            // 前20章
            if (totalChapters >= 20)
              ChoiceChip(
                label: const Text('前20章', style: TextStyle(fontSize: 12)),
                selected: _chapterLimit == 20,
                onSelected: (selected) {
                  setState(() {
                    _chapterLimit = selected ? 20 : null;
                  });
                },
                selectedColor: (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                    .withOpacity(0.2),
              ),
            // 前30章
            if (totalChapters >= 30)
              ChoiceChip(
                label: const Text('前30章', style: TextStyle(fontSize: 12)),
                selected: _chapterLimit == 30,
                onSelected: (selected) {
                  setState(() {
                    _chapterLimit = selected ? 30 : null;
                  });
                },
                selectedColor: (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                    .withOpacity(0.2),
              ),
            // 整本
            ChoiceChip(
              label: const Text('整本', style: TextStyle(fontSize: 12)),
              selected: _chapterLimit == null,
              onSelected: (selected) {
                setState(() {
                  _chapterLimit = selected ? null : 10;
                });
              },
              selectedColor: (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                  .withOpacity(0.2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 字数统计和提示
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: exceedsLimit 
                ? Colors.orange.withOpacity(0.1)
                : (isDark ? WebTheme.darkGrey200 : WebTheme.grey100),
            border: Border.all(
              color: exceedsLimit 
                  ? Colors.orange.withOpacity(0.3)
                  : (isDark ? WebTheme.darkGrey300 : WebTheme.grey300),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                exceedsLimit ? Icons.warning_amber : Icons.info_outline,
                size: 14,
                color: exceedsLimit 
                    ? Colors.orange 
                    : (isDark ? WebTheme.darkGrey700 : WebTheme.grey700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '预计拆书范围：$effectiveChapters章，约${(estimatedWords / 10000).toStringAsFixed(1)}万字${exceedsLimit ? '（建议不超过3万字以获得更好的提取效果）' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: exceedsLimit 
                        ? Colors.orange 
                        : (isDark ? WebTheme.darkGrey700 : WebTheme.grey700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建提取类型选择器（按组显示）
  Widget _buildExtractionTypesSelector(bool isDark) {
    // 按组分类
    final Map<String, List<String>> groupedTypes = {};
    for (final type in _extractionTypes.keys) {
      final group = _extractionTypeGroups[type]!;
      if (!groupedTypes.containsKey(group)) {
        groupedTypes[group] = [];
      }
      groupedTypes[group]!.add(type);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...groupedTypes.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.value.map((type) {
                  return FilterChip(
                    label: Text(_extractionTypeNames[type]!,
                        style: const TextStyle(fontSize: 12)),
                    selected: _extractionTypes[type]!,
                    onSelected: (selected) {
                      setState(() {
                        _extractionTypes[type] = selected;
                      });
                    },
                    selectedColor:
                        (isDark ? WebTheme.darkGrey800 : WebTheme.grey800)
                            .withOpacity(0.2),
                    checkmarkColor:
                        isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
                  );
                }).toList(),
              ),
            ],
          );
        }),
        const SizedBox(height: 8),
        Text(
          '默认已选中主要类型，您可以根据需要调整选择',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required bool required,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 2),
              Text(
                '*',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  /// 加载步骤
  Widget _buildLoadingStep(
      BuildContext context, NovelImportState state, bool isDark) {
    String message = '正在处理...';
    if (state is NovelImportUploading) {
      message = state.message;
    } else if (state is NovelImportLoadingPreview) {
      message = state.message;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤2：预览确认（显示章节列表和总字数）
  Widget _buildPreviewStep(
      BuildContext context, NovelImportPreviewReady state, bool isDark) {
    // 自动填充标题
    if (_titleController.text.isEmpty) {
      _titleController.text = state.previewResponse.detectedTitle;
    }

    // 计算总内容
    final totalChapters = state.previewResponse.totalChapterCount;
    final totalWords = state.previewResponse.totalWordCount;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 检测信息
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '检测到的信息',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '标题：${state.previewResponse.detectedTitle}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '章节数：$totalChapters',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '总字数：$totalWords',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? WebTheme.darkGrey700 : WebTheme.grey700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 标题编辑
          _buildFormField(
            label: '小说标题',
            required: true,
            child: TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '请输入小说标题',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                isDense: true,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 章节限制选择
          _buildFormField(
            label: '拆书范围',
            required: true,
            child: _buildChapterLimitSelector(state, isDark),
          ),

          const SizedBox(height: 16),

          // 章节列表标题
          Text(
            '章节列表预览',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            ),
          ),

          const SizedBox(height: 8),

          // 章节列表（只读，显示所有章节）
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.separated(
                itemCount: state.previewResponse.chapterPreviews.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                ),
                itemBuilder: (context, index) {
                  final chapter = state.previewResponse.chapterPreviews[index];

                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (isDark
                                ? WebTheme.darkGrey800
                                : WebTheme.grey800)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
                      ),
                    ),
                    subtitle: Text(
                      '${chapter.wordCount} 字 · ${chapter.contentPreview.length > 50 ? chapter.contentPreview.substring(0, 50) : chapter.contentPreview}...',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 提示信息
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '拆书过程将分析所有章节内容，预计需要几分钟时间',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 错误步骤
  Widget _buildErrorStep(
      BuildContext context, NovelImportFailure state, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.errorContainer,
            ),
            child: Icon(
              Icons.error,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '文件解析失败',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部按钮
  Widget _buildFooter(
      BuildContext context, NovelImportState state, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _buildFooterButtons(context, state, isDark),
      ),
    );
  }

  List<Widget> _buildFooterButtons(
      BuildContext context, NovelImportState state, bool isDark) {
    if (state is NovelImportInitial) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(
              color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _canUpload() ? () => _uploadFile() : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            foregroundColor: WebTheme.white,
          ),
          icon: const Icon(Icons.upload_file),
          label: const Text('上传文件'),
        ),
      ];
    } else if (state is NovelImportPreviewReady) {
      return [
        TextButton(
          onPressed: () {
            _importBloc.add(ResetImportState());
          },
          child: Text(
            '重新上传',
            style: TextStyle(
              color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _startExtraction(state),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            foregroundColor: WebTheme.white,
          ),
          icon: const Icon(Icons.auto_stories),
          label: const Text('开始拆书'),
        ),
      ];
    } else if (state is NovelImportFailure) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '关闭',
            style: TextStyle(
              color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {
            _importBloc.add(ResetImportState());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? WebTheme.darkGrey800 : WebTheme.grey800,
            foregroundColor: WebTheme.white,
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ];
    }

    return [];
  }

  bool _canUpload() {
    return _selectedModel != null;
  }

  void _uploadFile() {
    _hasDispatchedPreview = false;
    _importBloc.add(UploadFileForPreview());
  }

  /// 预估Token数量（用于警告提示，输入token = 字数）
  String _estimateTokens() {
    try {
      final importState = _importBloc.state;
      if (importState is! NovelImportPreviewReady) {
        return '未知';
      }
      
      final totalChapters = importState.previewResponse.totalChapterCount;
      final totalWords = importState.previewResponse.totalWordCount;
      final effectiveChapters = _chapterLimit ?? totalChapters;
      final ratio = effectiveChapters / totalChapters;
      final estimatedWords = (totalWords * ratio).round();
      
      // ✅ 输入token = 字数（不做倍率换算）
      return estimatedWords > 10000 
          ? '${(estimatedWords / 1000).toStringAsFixed(1)}K' 
          : estimatedWords.toString();
    } catch (e) {
      return '未知';
    }
  }

  /// 开始拆书（先弹出积分确认对话框）
  Future<void> _startExtraction(NovelImportPreviewReady state) async {
    if (_titleController.text.trim().isEmpty) {
      TopToast.error(context, '请输入小说标题');
      return;
    }

    if (_selectedModel == null) {
      TopToast.error(context, '请选择拆书模型');
      return;
    }

    // 获取选中的提取类型
    final selectedTypes = _extractionTypes.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    // 添加自定义类型（每个自定义类型都以CUSTOM标识）
    final List<String> allTypes = [...selectedTypes];
    if (_customTypes.isNotEmpty) {
      // 后端会识别CUSTOM类型，并从描述中读取实际的自定义内容
      allTypes.add('CUSTOM');
    }

    if (allTypes.isEmpty) {
      TopToast.error(context, '请至少选择一个提取类型或添加自定义类型');
      return;
    }

    // ✅ 如果使用公共模型，先弹出积分确认对话框
    if (_selectedModel!.isPublic) {
      final userId = AppConfig.userId;
      if (userId == null || userId.isEmpty) {
        TopToast.error(context, '请先登录');
        return;
      }

      // 计算预估token（输入token = 拆书范围的总字数）
      final totalChapters = state.previewResponse.totalChapterCount;
      final totalWords = state.previewResponse.totalWordCount;
      final effectiveChapters = _chapterLimit ?? totalChapters;
      final ratio = effectiveChapters / totalChapters;
      final estimatedWords = (totalWords * ratio).round();
      
      // ✅ 输入token = 字数（不做倍率换算）
      final estimatedInputTokens = estimatedWords;
      // ✅ 输出token = 字数 × 3（拆书输出较多）
      final estimatedOutputTokens = estimatedWords * 3;
      
      // 构造积分预估请求
      final request = UniversalAIRequest(
        requestType: AIRequestType.knowledgeExtractionSetting,
        userId: userId,
        modelConfig: UserAIModelConfigModel(
          id: _selectedModel!.id,
          userId: userId,
          provider: _selectedModel!.provider,
          modelName: _selectedModel!.modelId,
          alias: _selectedModel!.displayName,
          apiKey: '', // 公共模型不需要apiKey
          apiEndpoint: '',
          isValidated: true,
          isDefault: false,
          isToolDefault: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        parameters: {
          'estimatedInputTokens': estimatedInputTokens,
          'estimatedOutputTokens': estimatedOutputTokens,
          'modelConfigId': _selectedModel!.id,
          'isPublicModel': true,
        },
        metadata: {
          'isPublicModel': true,
          'publicModelConfigId': _selectedModel!.id,
        },
      );

      // 弹出积分确认对话框
      final confirmed = await showCreditConfirmationDialog(
        context: context,
        modelName: _selectedModel!.displayName,
        featureName: '知识库拆书',
        request: request,
      );

      if (!confirmed) {
        return; // 用户取消
      }
    }

    // 调用拆书API
    if (!mounted) return;
    context.read<KnowledgeBaseBloc>().add(
          ExtractFromPreviewSession(
            previewSessionId: state.previewResponse.previewSessionId,
            title: _titleController.text.trim(),
            description: _buildDescriptionWithCustomTypes(),
            extractionTypes: allTypes,
            modelConfigId: _selectedModel!.id,
            modelType: _selectedModel!.isPublic ? 'public' : 'user',
            chapterLimit: _chapterLimit, // 传递章节限制
          ),
        );

    // 关闭对话框
    if (!mounted) return;
    Navigator.of(context).pop();

    // 显示提示
    TopToast.success(context, '拆书任务已创建，正在后台执行');
  }

  /// 构建包含自定义类型的描述
  String? _buildDescriptionWithCustomTypes() {
    final userDesc = _descriptionController.text.trim();
    if (_customTypes.isEmpty) {
      return userDesc.isEmpty ? null : userDesc;
    }

    final customSection = '\n\n【自定义提取类型】\n${_customTypes.join('、')}';
    return userDesc.isEmpty ? customSection.trim() : userDesc + customSection;
  }

  int _getCurrentStep(NovelImportState state) {
    if (state is NovelImportInitial ||
        state is NovelImportUploading ||
        state is NovelImportFileUploaded ||
        state is NovelImportLoadingPreview) {
      return 1;
    } else if (state is NovelImportPreviewReady) {
      return 2;
    } else {
      return 3;
    }
  }
}

/// 显示拆书导入对话框
void showKnowledgeExtractionImportDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // 获取必要的Bloc
      final knowledgeBaseBloc = context.read<KnowledgeBaseBloc>();
      final universalAIBloc = context.read<UniversalAIBloc>();
      final creditBloc = context.read<CreditBloc>();
      
      // 创建NovelRepository单例实例
      final novelRepository = NovelRepositoryImpl();

      return MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => NovelImportBloc(novelRepository: novelRepository),
          ),
          BlocProvider.value(value: knowledgeBaseBloc),
          BlocProvider.value(value: universalAIBloc),
          BlocProvider.value(value: creditBloc),
        ],
        child: const KnowledgeExtractionImportDialog(),
      );
    },
  );
}

