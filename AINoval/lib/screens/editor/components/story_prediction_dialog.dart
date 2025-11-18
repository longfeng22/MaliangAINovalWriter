import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/story_prediction_models.dart' as api_models;
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/config/provider_icons.dart';
import 'package:ainoval/screens/editor/components/story_prediction_results.dart';
import 'package:ainoval/screens/editor/components/merge_preview_dialog.dart';
import 'package:ainoval/services/api_service/repositories/impl/editor_repository_impl.dart';
import 'package:ainoval/services/story_prediction_service.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/form_dialog_template.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/widgets/common/radio_button_group.dart';
import 'package:ainoval/widgets/common/loading_toast.dart';
import 'package:ainoval/widgets/common/model_display_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
// 🚀 新增：导入完整的小说相关模型和助手类（参考扩写表单）
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/utils/context_selection_helper.dart';

/// 剧情推演主配置对话框
/// 
/// 功能特点：
/// - 支持多模型选择（公共模型+私有模型）
/// - 风格指令输入
/// - 生成数量控制（2-5）
/// - 高级设置入口
/// - 场景内容生成控制
class StoryPredictionDialog extends StatefulWidget {
  final String novelId;
  final novel_models.Chapter chapter;
  final VoidCallback? onCancel;
  final Function(StoryPredictionConfig)? onGenerate;
  
  // 🚀 新增：完整的小说数据（参考扩写表单）
  final novel_models.Novel? novel;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;

  const StoryPredictionDialog({
    Key? key,
    required this.novelId,
    required this.chapter,
    this.onCancel,
    this.onGenerate,
    // 🚀 新增参数
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
  }) : super(key: key);

  @override
  State<StoryPredictionDialog> createState() => _StoryPredictionDialogState();
}

class _StoryPredictionDialogState extends State<StoryPredictionDialog> {
  // 表单控制器
  final TextEditingController _styleInstructionsController = TextEditingController();
  
  // 状态变量
  List<UnifiedAIModel> _selectedModels = [];
  int _generationCount = 3; // 默认生成3个
  bool _generateSceneContent = true; // 默认开启场景内容生成
  
  // 高级设置
  StoryPredictionAdvancedConfig? _advancedConfig;
  
  // 高级设置控制器
  final TextEditingController _additionalInstructionsController = TextEditingController();
  String? _summaryPromptTemplateId;
  String? _scenePromptTemplateId;

  // 🚀 为高级设置弹窗提供本地setState，解决UI不刷新的问题
  void Function(void Function())? _advancedModalSetState;
  
  // 加载状态
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _hasStartedGeneration = false;
  
  // 🎯 新增：最小化标记和悬浮卡片overlay
  bool _isMinimizing = false;
  OverlayEntry? _floatingCardOverlay;
  
  // 表单验证状态
  String? _modelSelectionError;
  String? _styleInstructionsError;
  
  // 结果状态
  List<PredictionResult> _results = [];
  // 新建：记录新创建章节ID（"添加到下一章"后）
  String? _nowChapterId;
  // 当前用于生成的章节ID（优先使用新建的章节）
  String get _currentChapterId => _nowChapterId?.isNotEmpty == true ? _nowChapterId! : widget.chapter.id;
  // 🔥 新增：当前任务ID（用于迭代优化）
  String? _currentTaskId;

  void _updateCurrentChapterId(String newChapterId) {
    if (newChapterId.isEmpty) return;
    setState(() {
      _nowChapterId = newChapterId;
    });
    AppLogger.i('StoryPredictionDialog', '📘 当前用于生成的章节已更新: chapterId=$newChapterId');
  }
  
  // 缓存的模型信息（用于恢复选择）
  List<Map<String, dynamic>>? _cachedModelData;
  
  // 可用模型列表
  List<UnifiedAIModel> _availableModels = [];
  bool _isLoadingModels = false;
  bool _didRestoreModels = false;
  StreamSubscription? _aiConfigSub;
  StreamSubscription? _publicModelsSub;
  
  // 预设指令列表
  static const List<Map<String, dynamic>> _presetInstructions = [
    // 风格类
    {'label': '幽默风趣', 'instruction': '采用幽默风趣的写作风格，增加轻松愉快的氛围', 'category': '风格', 'color': Colors.orange},
    {'label': '悬疑紧张', 'instruction': '营造悬疑紧张的氛围，保持情节的神秘感', 'category': '风格', 'color': Colors.purple},
    {'label': '浪漫温馨', 'instruction': '突出浪漫温馨的情感表达，增强感情戏份', 'category': '风格', 'color': Colors.pink},
    {'label': '严肃正式', 'instruction': '采用严肃正式的叙述风格，保持内容的庄重性', 'category': '风格', 'color': Colors.blueGrey},
    
    // 节奏类
    {'label': '情节紧凑', 'instruction': '保持情节紧凑，快速推进故事发展', 'category': '节奏', 'color': Colors.red},
    {'label': '慢节奏展开', 'instruction': '采用慢节奏展开，细腻描绘情感和环境', 'category': '节奏', 'color': Colors.green},
    {'label': '快速推进', 'instruction': '快速推进主线剧情，减少冗余描述', 'category': '节奏', 'color': Colors.deepOrange},
    
    // 角色类
    {'label': '突出主角', 'instruction': '重点突出主角的表现和内心活动', 'category': '角色', 'color': Colors.blue},
    {'label': '多角色视角', 'instruction': '从多个角色的视角展现情节发展', 'category': '角色', 'color': Colors.cyan},
    {'label': '丰富内心独白', 'instruction': '增加角色的内心独白，展现心理变化', 'category': '角色', 'color': Colors.indigo},
    
    // 情节类
    {'label': '增加转折', 'instruction': '在适当时机增加情节转折，制造意外惊喜', 'category': '情节', 'color': Colors.deepPurple},
    {'label': '埋下伏笔', 'instruction': '巧妙埋下伏笔，为后续发展做铺垫', 'category': '情节', 'color': Colors.brown},
    {'label': '制造冲突', 'instruction': '适度制造人物或情节冲突，增强戏剧性', 'category': '情节', 'color': Colors.red},
    {'label': '温情日常', 'instruction': '加入温情的日常场景，平衡故事氛围', 'category': '情节', 'color': Colors.amber},
    
    // 描写类
    {'label': '细节丰富', 'instruction': '丰富细节描写，增强画面感和代入感', 'category': '描写', 'color': Colors.teal},
    {'label': '对话生动', 'instruction': '编写生动自然的对话，突出人物性格', 'category': '描写', 'color': Colors.lime},
    {'label': '环境描写', 'instruction': '加强环境氛围描写，烘托故事气氛', 'category': '描写', 'color': Colors.lightGreen},
    {'label': '心理描写', 'instruction': '深入刻画角色心理变化和情感波动', 'category': '描写', 'color': Colors.lightBlue},
  ];

  // 将 UI 的 ContextSelectionData 转成 API ContextSelection
  api_models.ContextSelection _buildApiContextSelection() {
    // 兜底：如果没有高级配置或上下文数据，使用默认的类型集合
    final ctxData = _advancedConfig?.contextSelection ?? _createDefaultContextData();
    // 将被选中的叶子项类型映射到 API 的类型字符串集合，并保留部分需要的 customIds
    final Set<String> typeSet = <String>{};
    final List<String> customIds = <String>[];
    for (final item in ctxData.selectedItems.values) {
      switch (item.type) {
        case ContextSelectionType.fullOutline:
          typeSet.add('full_outline');
          break;
        case ContextSelectionType.recentChaptersSummary:
          typeSet.add('recent_chapters_summary');
          break;
        case ContextSelectionType.recentChaptersContent:
          typeSet.add('recent_chapters_content');
          break;
        case ContextSelectionType.settings:
          // 通用“所有设定”统一映射为 all_settings（不传ids）
          typeSet.add('all_settings');
          break;
        case ContextSelectionType.settingGroups:
          // 若需细粒度，可选择映射为 setting_group 并附带具体id；此处保持通用
          typeSet.add('all_settings');
          break;
        case ContextSelectionType.settingsByType:
          // 同上，保持通用汇聚
          typeSet.add('all_settings');
          break;
        case ContextSelectionType.fullNovelText:
          typeSet.add('full_novel_text');
          break;
        case ContextSelectionType.novelBasicInfo:
          typeSet.add('novel_basic_info');
          break;
        case ContextSelectionType.currentSceneContent:
          typeSet.add('current_scene_content');
          break;
        case ContextSelectionType.currentSceneSummary:
          typeSet.add('current_scene_summary');
          break;
        case ContextSelectionType.currentChapterContent:
          typeSet.add('current_chapter_content');
          break;
        case ContextSelectionType.currentChapterSummaries:
          typeSet.add('current_chapter_summary');
          break;
        case ContextSelectionType.previousChaptersContent:
          typeSet.add('previous_chapters_content');
          break;
        case ContextSelectionType.previousChaptersSummary:
          typeSet.add('previous_chapters_summary');
          break;
        case ContextSelectionType.acts:
          typeSet.add('act');
          customIds.add(item.id);
          break;
        case ContextSelectionType.chapters:
          typeSet.add('chapter');
          customIds.add(item.id.replaceFirst('flat_', ''));
          break;
        case ContextSelectionType.scenes:
          typeSet.add('scene');
          customIds.add(item.id.replaceFirst('flat_', ''));
          break;
        case ContextSelectionType.snippets:
          typeSet.add('snippet');
          customIds.add(item.id.replaceFirst('snippet_', ''));
          break;
        case ContextSelectionType.contentFixedGroup:
        case ContextSelectionType.summaryFixedGroup:
          break;
        case ContextSelectionType.codexEntries:
          // 如需知识库条目，可扩展对应 Provider
          break;
        case ContextSelectionType.entriesByType:
        case ContextSelectionType.entriesByDetail:
        case ContextSelectionType.entriesByCategory:
        case ContextSelectionType.entriesByTag:
          // 暂不映射；需要时添加相应 Provider
          break;
      }
    }
    // 如果没有任何选择，使用推荐默认集：最近摘要+最近内容+全部设定
    final List<String> finalTypes = typeSet.isEmpty
        ? ['recent_chapters_summary', 'recent_chapters_content', 'all_settings']
        : typeSet.toList();
    return api_models.ContextSelection(
      types: finalTypes,
      customContextIds: customIds.isEmpty ? null : customIds,
      maxTokens: 4000,
    );
  }

  // 通用AI上下文选择（与扩写表单一致）：[{id, title, type, metadata?}]
  List<Map<String, dynamic>> _buildUniversalContextSelections() {
    final ctxData = _advancedConfig?.contextSelection ?? _createDefaultContextData();
    final List<Map<String, dynamic>> selections = [];
    for (final item in ctxData.selectedItems.values) {
      final String type = _mapItemTypeToProvider(item.type);
      if (type.isEmpty) continue;
      final String id = _normalizeUniversalId(type, item.id);
      selections.add({
        'id': id,
        'title': item.title,
        'type': type,
        if (item.metadata.isNotEmpty) 'metadata': item.metadata,
      });
    }
    // 若未选择，给默认三项
    if (selections.isEmpty) {
      selections.addAll([
        {'id': 'recent_chapters_summary_${widget.novelId}', 'title': '最近5章摘要', 'type': 'recent_chapters_summary'},
        {'id': 'recent_chapters_content_${widget.novelId}', 'title': '最近5章内容', 'type': 'recent_chapters_content'},
        {'id': 'all_settings', 'title': '全部设定', 'type': 'all_settings'},
      ]);
    }
    return selections;
  }

  String _mapItemTypeToProvider(ContextSelectionType t) {
    switch (t) {
      case ContextSelectionType.fullOutline:
        return 'full_outline';
      case ContextSelectionType.recentChaptersSummary:
        return 'recent_chapters_summary';
      case ContextSelectionType.recentChaptersContent:
        return 'recent_chapters_content';
      case ContextSelectionType.settings:
      case ContextSelectionType.settingGroups:
      case ContextSelectionType.settingsByType:
        return 'all_settings';
      case ContextSelectionType.fullNovelText:
        return 'full_novel_text';
      case ContextSelectionType.novelBasicInfo:
        return 'novel_basic_info';
      case ContextSelectionType.currentSceneContent:
        return 'current_scene_content';
      case ContextSelectionType.currentSceneSummary:
        return 'current_scene_summary';
      case ContextSelectionType.currentChapterContent:
        return 'current_chapter_content';
      case ContextSelectionType.currentChapterSummaries:
        return 'current_chapter_summary';
      case ContextSelectionType.previousChaptersContent:
        return 'previous_chapters_content';
      case ContextSelectionType.previousChaptersSummary:
        return 'previous_chapters_summary';
      case ContextSelectionType.acts:
        return 'act';
      case ContextSelectionType.chapters:
        return 'chapter';
      case ContextSelectionType.scenes:
        return 'scene';
      case ContextSelectionType.snippets:
        return 'snippet';
      default:
        return '';
    }
  }

  String _normalizeUniversalId(String type, String rawId) {
    if (type == 'chapter' || type == 'scene') {
      // 去掉扁平化前缀
      final id = rawId.startsWith('flat_') ? rawId.substring('flat_'.length) : rawId;
      return id;
    }
    if (type == 'snippet' && rawId.startsWith('snippet_')) {
      return rawId.substring('snippet_'.length);
    }
    if (type == 'all_settings' || type == 'novel_basic_info') {
      // 通用类型不需要具体ID
      return type;
    }
    return rawId;
  }

  @override
  void initState() {
    super.initState();
    // 🚀 先初始化默认上下文，便于后续应用缓存上下文选择
    _initializeDefaultConfig();
    _loadCachedPreferences();
    _loadAvailableModels();
    _subscribeModelBlocChanges();
  }

  @override
  void dispose() {
    AppLogger.i('StoryPredictionDialog', '🔴 dispose() 被调用，_isMinimizing = $_isMinimizing');
    
    _styleInstructionsController.dispose();
    _additionalInstructionsController.dispose();
    _aiConfigSub?.cancel();
    _publicModelsSub?.cancel();
    
    // 🎯 修复：只在非最小化状态下清理overlay
    // 如果是最小化，overlay需要保留在屏幕上
    if (!_isMinimizing) {
      if (_floatingCardOverlay != null) {
        AppLogger.i('StoryPredictionDialog', '🔴 非最小化状态，移除悬浮卡片');
        _floatingCardOverlay?.remove();
        _floatingCardOverlay = null;
      }
      AppLogger.i('StoryPredictionDialog', '🔴 对话框dispose - 非最小化，已清理所有资源');
    } else {
      AppLogger.i('StoryPredictionDialog', '🟢 对话框dispose - 最小化状态，保留悬浮卡片');
    }
    
    super.dispose();
  }

  /// 加载缓存的用户偏好
  void _loadCachedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String novelScope = widget.novelId;
      
      // 加载生成数量
      final cachedCount = prefs.getInt('story_prediction_generation_count');
      if (cachedCount != null && cachedCount >= 2 && cachedCount <= 5) {
        setState(() {
          _generationCount = cachedCount;
        });
      }
      
      // 加载场景内容生成开关
      final cachedSceneContent = prefs.getBool('story_prediction_generate_scene_content');
      if (cachedSceneContent != null) {
        setState(() {
          _generateSceneContent = cachedSceneContent;
        });
      }
      
      // 加载风格指令
      final cachedStyleInstructions = prefs.getString('story_prediction_style_instructions');
      if (cachedStyleInstructions != null) {
        _styleInstructionsController.text = cachedStyleInstructions;
      }
      
      // 加载模型选择信息（优先读取按小说隔离的缓存）
      final cachedModelsJson = prefs.getString('story_prediction_selected_models_' + novelScope)
        ?? prefs.getString('story_prediction_selected_models');
      if (cachedModelsJson != null) {
        try {
          final List<dynamic> modelList = jsonDecode(cachedModelsJson);
          _cachedModelData = modelList.cast<Map<String, dynamic>>();
          AppLogger.i('StoryPredictionDialog', '✅ 已加载${_cachedModelData?.length ?? 0}个缓存模型信息');
          
          // 🔥 关键修复：缓存加载完成后，立即尝试恢复模型选择
          // 如果可用模型列表已经加载完成，就立即恢复
          if (_availableModels.isNotEmpty && !_didRestoreModels) {
            AppLogger.i('StoryPredictionDialog', '🔥 缓存加载完成，立即尝试恢复模型选择');
            _tryRestoreCachedModels();
          }
        } catch (e) {
          AppLogger.w('StoryPredictionDialog', '解析缓存模型信息失败: $e');
        }
      }
      
      // 🚀 修复：加载高级设置时，确保正确更新状态（优先读取按小说隔离的缓存）
      final cachedSummaryTemplateId = prefs.getString('story_prediction_summary_prompt_template_id_' + novelScope)
        ?? prefs.getString('story_prediction_summary_prompt_template_id');
      if (cachedSummaryTemplateId != null && cachedSummaryTemplateId.isNotEmpty) {
        setState(() {
          _summaryPromptTemplateId = cachedSummaryTemplateId;
          // 同步到高级配置中
          _advancedConfig = _advancedConfig?.copyWith(
            summaryPromptTemplateId: cachedSummaryTemplateId
          );
        });
        AppLogger.i('StoryPredictionDialog', '加载缓存的剧情续写提示词模板: $cachedSummaryTemplateId');
      }
      
      final cachedSceneTemplateId = prefs.getString('story_prediction_scene_prompt_template_id_' + novelScope)
        ?? prefs.getString('story_prediction_scene_prompt_template_id');
      if (cachedSceneTemplateId != null && cachedSceneTemplateId.isNotEmpty) {
        setState(() {
          _scenePromptTemplateId = cachedSceneTemplateId;
          // 同步到高级配置中
          _advancedConfig = _advancedConfig?.copyWith(
            scenePromptTemplateId: cachedSceneTemplateId
          );
        });
        AppLogger.i('StoryPredictionDialog', '加载缓存的场景内容提示词模板: $cachedSceneTemplateId');
      }
      
      // 🚀 修复：加载缓存的上下文选择数据（优先读取按小说隔离的缓存）
      final cachedContextJson = prefs.getString('story_prediction_context_selection_' + novelScope)
        ?? prefs.getString('story_prediction_context_selection');
      if (cachedContextJson != null && cachedContextJson.isNotEmpty) {
        try {
          final contextMap = jsonDecode(cachedContextJson);
          AppLogger.i('StoryPredictionDialog', '加载缓存的上下文选择数据: ${contextMap['selectedCount'] ?? 0}个项目');
        } catch (e) {
          AppLogger.w('StoryPredictionDialog', '解析缓存上下文选择失败: $e');
        }
      }
      
      AppLogger.i('StoryPredictionDialog', '✅ 缓存偏好加载完成，包括提示词模板设置');
    } catch (e) {
      AppLogger.w('StoryPredictionDialog', '加载缓存偏好失败: $e');
    }
  }

  /// 保存用户偏好到缓存
  void _saveCachedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String novelScope = widget.novelId;
      await prefs.setInt('story_prediction_generation_count', _generationCount);
      await prefs.setBool('story_prediction_generate_scene_content', _generateSceneContent);
      await prefs.setString('story_prediction_style_instructions', _styleInstructionsController.text);
      
      // 缓存选中的模型（简化信息）
      // 🚀 修复：当当前选择为空时，不覆盖已有缓存，避免把非空选择清成空
      if (_selectedModels.isNotEmpty) {
        final modelData = _selectedModels.map((model) => {
          'id': model.id,
          'displayName': model.displayName,
          'provider': model.provider,
          'isPublic': model.isPublic,
        }).toList();
        // 全局与按小说隔离的双写
        await prefs.setString('story_prediction_selected_models', jsonEncode(modelData));
        await prefs.setString('story_prediction_selected_models_' + novelScope, jsonEncode(modelData));
      }
      
      // 🚀 修复：缓存高级设置，优先使用高级配置中的值
      final summaryTemplateId = _advancedConfig?.summaryPromptTemplateId ?? _summaryPromptTemplateId;
      if (summaryTemplateId != null && summaryTemplateId.isNotEmpty) {
        await prefs.setString('story_prediction_summary_prompt_template_id', summaryTemplateId);
        await prefs.setString('story_prediction_summary_prompt_template_id_' + novelScope, summaryTemplateId);
        AppLogger.d('StoryPredictionDialog', '保存剧情续写提示词模板ID: $summaryTemplateId');
      } else {
        await prefs.remove('story_prediction_summary_prompt_template_id');
        await prefs.remove('story_prediction_summary_prompt_template_id_' + novelScope);
      }
      
      final sceneTemplateId = _advancedConfig?.scenePromptTemplateId ?? _scenePromptTemplateId;
      if (sceneTemplateId != null && sceneTemplateId.isNotEmpty) {
        await prefs.setString('story_prediction_scene_prompt_template_id', sceneTemplateId);
        await prefs.setString('story_prediction_scene_prompt_template_id_' + novelScope, sceneTemplateId);
        AppLogger.d('StoryPredictionDialog', '保存场景内容提示词模板ID: $sceneTemplateId');
      } else {
        await prefs.remove('story_prediction_scene_prompt_template_id');
        await prefs.remove('story_prediction_scene_prompt_template_id_' + novelScope);
      }
      
      // 🚀 修复：保存上下文选择数据（仅在有选择时保存）
      if (_advancedConfig?.contextSelection != null && _advancedConfig!.contextSelection.selectedCount > 0) {
        try {
          final contextData = {
            'selectedCount': _advancedConfig!.contextSelection.selectedCount,
            'selectedIds': _advancedConfig!.contextSelection.selectedItems.keys.toList(),
          };
          await prefs.setString('story_prediction_context_selection', jsonEncode(contextData));
          await prefs.setString('story_prediction_context_selection_' + novelScope, jsonEncode(contextData));
          AppLogger.d('StoryPredictionDialog', '保存上下文选择数据: ${_advancedConfig!.contextSelection.selectedCount}个项目');
        } catch (e) {
          AppLogger.w('StoryPredictionDialog', '保存上下文选择数据失败: $e');
        }
      }

      // 不再持久化当前章节ID，保持会话级
      
      AppLogger.d('StoryPredictionDialog', '🔍 用户偏好已保存到缓存，包括${_selectedModels.length}个模型');
    } catch (e) {
      AppLogger.w('StoryPredictionDialog', '保存缓存偏好失败: $e');
    }
  }

  /// 加载可用的模型列表
  void _loadAvailableModels() {
    setState(() {
      _isLoadingModels = true;
    });

    try {
      final aiConfigState = context.read<AiConfigBloc>().state;
      final publicModelsState = context.read<PublicModelsBloc>().state;
      
      // 🚀 如果公共模型尚未加载，触发一次加载
      if (publicModelsState is PublicModelsInitial || publicModelsState is PublicModelsError) {
        try {
          context.read<PublicModelsBloc>().add(const LoadPublicModels());
        } catch (_) {}
      }

      final allModels = _combineModels(aiConfigState, publicModelsState);
      
      setState(() {
        _availableModels = allModels;
        _isLoadingModels = false;
      });
      
      // 尝试从缓存恢复模型选择
      _tryRestoreCachedModels();
      
      AppLogger.i('StoryPredictionDialog', '✅ 加载了${allModels.length}个可用模型');
    } catch (e) {
      setState(() {
        _isLoadingModels = false;
      });
      AppLogger.w('StoryPredictionDialog', '加载模型失败: $e');
    }
  }

  void _subscribeModelBlocChanges() {
    try {
      _aiConfigSub = context.read<AiConfigBloc>().stream.listen((state) {
        // 私有模型变化，刷新可用模型并尝试恢复
        _loadAvailableModels();
      });
    } catch (_) {}
    try {
      _publicModelsSub = context.read<PublicModelsBloc>().stream.listen((state) {
        // 公共模型变化，刷新可用模型并尝试恢复
        _loadAvailableModels();
      });
    } catch (_) {}
  }

  /// 合并私有模型和公共模型
  List<UnifiedAIModel> _combineModels(AiConfigState aiState, PublicModelsState publicState) {
    final List<UnifiedAIModel> allModels = [];
    
    // 添加已验证的私有模型
    final validatedConfigs = aiState.validatedConfigs;
    for (final config in validatedConfigs) {
      allModels.add(PrivateAIModel(config));
    }
    
    // 添加公共模型
    if (publicState is PublicModelsLoaded) {
      for (final publicModel in publicState.models) {
        allModels.add(PublicAIModel(publicModel));
      }
    }
    
    return allModels;
  }

  /// 尝试从缓存恢复模型选择
  void _tryRestoreCachedModels() {
    AppLogger.i('StoryPredictionDialog', '🔄 开始尝试恢复模型选择...');
    AppLogger.i('StoryPredictionDialog', '  - _didRestoreModels: $_didRestoreModels');
    AppLogger.i('StoryPredictionDialog', '  - _cachedModelData: ${_cachedModelData?.length ?? 0} 个');
    AppLogger.i('StoryPredictionDialog', '  - _availableModels: ${_availableModels.length} 个');
    
    if (_didRestoreModels) {
      AppLogger.i('StoryPredictionDialog', '⏭️ 已经恢复过了，跳过');
      return;
    }
    
    if (_cachedModelData == null || _cachedModelData!.isEmpty) {
      AppLogger.i('StoryPredictionDialog', '⚠️ 没有缓存数据，跳过恢复');
      return;
    }
    
    final List<UnifiedAIModel> restoredModels = [];
    
    for (final cachedModel in _cachedModelData!) {
      try {
        final cachedId = cachedModel['id'] as String?;
        final cachedProvider = cachedModel['provider'] as String?;
        final cachedIsPublic = cachedModel['isPublic'] as bool?;
        
        AppLogger.i('StoryPredictionDialog', '🔍 尝试匹配缓存模型: ${cachedModel['displayName']}');
        AppLogger.i('StoryPredictionDialog', '   - id: $cachedId');
        AppLogger.i('StoryPredictionDialog', '   - provider: $cachedProvider');
        AppLogger.i('StoryPredictionDialog', '   - isPublic: $cachedIsPublic');
        
        // 尝试匹配可用模型
        final matchedModel = _availableModels.firstWhere(
          (model) => model.id == cachedId && 
                     model.provider == cachedProvider && 
                     model.isPublic == cachedIsPublic,
          orElse: () => throw StateError('No matching model'),
        );
        
        restoredModels.add(matchedModel);
        AppLogger.i('StoryPredictionDialog', '   ✅ 成功恢复: ${matchedModel.displayName}');
      } catch (e) {
        AppLogger.w('StoryPredictionDialog', '   ❌ 无法恢复缓存模型: ${cachedModel['displayName']}, 错误: $e');
      }
    }
    
    if (restoredModels.isNotEmpty) {
      setState(() {
        _selectedModels = restoredModels;
      });
      _didRestoreModels = true;
      AppLogger.i('StoryPredictionDialog', '✅✅ 已恢复${restoredModels.length}个缓存模型选择');
    } else {
      AppLogger.w('StoryPredictionDialog', '⚠️ 没有成功恢复任何模型');
    }
  }

  /// 初始化默认配置
  void _initializeDefaultConfig() {
    AppLogger.i('StoryPredictionDialog', '🔧 初始化默认配置');
    // 🚀 重构：使用公共助手类初始化上下文选择数据（参考扩写表单）
    final contextData = ContextSelectionHelper.initializeContextData(
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
    );
    _advancedConfig = StoryPredictionAdvancedConfig(
      contextSelection: contextData,
    );
    AppLogger.i('StoryPredictionDialog', '✅ 默认配置初始化完成: novelId=${widget.novelId}, chapterId=${widget.chapter.id}, 上下文项目数=${contextData.selectedCount}');
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;
    final isLargeScreen = screenSize.width > 1400;
    
    // 响应式计算对话框尺寸
    final dialogWidth = isSmallScreen 
        ? screenSize.width * 0.95  // 小屏幕占95%
        : isLargeScreen
            ? screenSize.width * 0.7  // 大屏幕占70%
            : screenSize.width * 0.8; // 中屏幕占80%
            
    final dialogHeight = screenSize.height * 0.9; // 高度占90%
    
    return Dialog(
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        constraints: BoxConstraints(
          minWidth: 600,
          maxWidth: 1600,
          minHeight: 600,
          maxHeight: dialogHeight,
        ),
        decoration: BoxDecoration(
          color: WebTheme.getBackgroundColor(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: WebTheme.getShadowColor(context, opacity: 0.15),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            // 标题栏
            _buildHeader(),
            
            // 内容区域 - 使用Expanded而不是Flexible，确保占满剩余空间
            Expanded(
              child: _hasStartedGeneration 
                ? _buildResultsContent()
                : _buildMainContent(),
            ),
            
            // 按钮栏
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey300 
              : WebTheme.grey300,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories,
            color: Colors.deepPurple[700],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '剧情推演 - ${widget.chapter.title}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ),
          // 🎯 新增：缩小按钮
          IconButton(
            onPressed: _handleMinimize,
            icon: Icon(
              Icons.minimize,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            tooltip: '最小化为悬浮窗',
          ),
          IconButton(
            onPressed: _handleCancel,
            icon: Icon(
              Icons.close,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  /// 构建操作按钮栏
  Widget _buildActions() {
    // 计算是否需要显示指令输入框（结果状态下）
    final bool showInstructionInput = _hasStartedGeneration && !_isGenerating;
    
    return Container(
      padding: EdgeInsets.all(showInstructionInput ? 24 : 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey300 
              : WebTheme.grey300,
          ),
        ),
      ),
      child: showInstructionInput
          ? _buildActionsWithInstructionInput()
          : _buildNormalActions(),
    );
  }

  /// 构建普通状态的按钮栏
  Widget _buildNormalActions() {
    return Row(
      children: [
        // 高级设置按钮（仅在未开始生成时显示）
        if (!_hasStartedGeneration)
          TextButton.icon(
            onPressed: _showAdvancedSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(
              Icons.tune,
              size: 18,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            label: Text(
              '高级设置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ),
        
        const Spacer(),
        
        // 取消/关闭按钮
        OutlinedButton.icon(
          onPressed: _handleCancel,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            side: BorderSide(
              color: WebTheme.getBorderColor(context),
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            foregroundColor: WebTheme.getTextColor(context),
          ),
          icon: Icon(
            _hasStartedGeneration ? Icons.close : Icons.cancel_outlined,
            size: 18,
            color: WebTheme.getTextColor(context),
          ),
          label: Text(
            _hasStartedGeneration ? '关闭' : '取消',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
          ),
        ),
        
        const SizedBox(width: 16),
        
        // 根据状态显示不同按钮
        if (!_hasStartedGeneration)
          // 生成按钮
          ElevatedButton.icon(
            onPressed: () {
              AppLogger.i('StoryPredictionDialog', '🖱️ 生成按钮被点击, _isLoading=$_isLoading, _hasStartedGeneration=$_hasStartedGeneration');
              if (!_isLoading) {
                _handleGenerate();
              } else {
                AppLogger.w('StoryPredictionDialog', '⚠️ 按钮被禁用: _isLoading=$_isLoading');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.getTextColor(context),
              foregroundColor: WebTheme.getBackgroundColor(context),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            icon: _isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      WebTheme.getBackgroundColor(context),
                    ),
                  ),
                )
              : Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: WebTheme.getBackgroundColor(context),
                ),
            label: Text(
              '开始生成',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: WebTheme.getBackgroundColor(context),
              ),
            ),
          )
        else if (_isGenerating)
          // 生成中显示状态按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: WebTheme.getTextColor(context).withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: WebTheme.getBorderColor(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      WebTheme.getTextColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '生成中...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建带指令输入的按钮栏（结果状态）
  Widget _buildActionsWithInstructionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 指令输入区域
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '指令调整',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _styleInstructionsController,
                    maxLines: 2,
                    onChanged: (value) {
                      // 实时保存风格指令
                      _saveCachedPreferences();
                    },
                    decoration: InputDecoration(
                      hintText: '输入或修改剧情指导指令...',
                      hintStyle: TextStyle(
                        color: WebTheme.getSecondaryTextColor(context),
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: WebTheme.isDarkMode(context) 
                            ? WebTheme.darkGrey300 
                            : WebTheme.grey300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: WebTheme.isDarkMode(context) 
                            ? WebTheme.darkGrey300 
                            : WebTheme.grey300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: WebTheme.getTextColor(context),
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: WebTheme.getSurfaceColor(context),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: TextStyle(
                      color: WebTheme.getTextColor(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 20),
            
            // 右侧按钮组
            Column(
              children: [
                // 关闭按钮
                OutlinedButton.icon(
                  onPressed: _handleCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    side: BorderSide(
                      color: WebTheme.getBorderColor(context),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: WebTheme.getTextColor(context),
                  ),
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: WebTheme.getTextColor(context),
                  ),
                  label: Text(
                    '关闭',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // 按钮组
                Row(
                  children: [
                    // 返回菜单按钮
                    OutlinedButton.icon(
                      onPressed: _handleBackToMenu,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        side: BorderSide(
                          color: WebTheme.getBorderColor(context),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: WebTheme.getTextColor(context),
                      ),
                      icon: Icon(
                        Icons.arrow_back,
                        size: 16,
                        color: WebTheme.getTextColor(context),
                      ),
                      label: Text(
                        '返回菜单',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 10),
                    
                    // 继续生成按钮（如果有新章节）
                    if (_nowChapterId != null && _nowChapterId!.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _handleContinueGenerate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.play_circle_fill, size: 16, color: Colors.white),
                        label: const Text(
                          '继续生成',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    
                    if (_nowChapterId != null && _nowChapterId!.isNotEmpty)
                      const SizedBox(width: 10),
                    
                    // 重新生成按钮
                    ElevatedButton.icon(
                      onPressed: _handleRegenerate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WebTheme.getTextColor(context),
                        foregroundColor: WebTheme.getBackgroundColor(context),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(
                        Icons.refresh,
                        size: 16,
                        color: WebTheme.getBackgroundColor(context),
                      ),
                      label: Text(
                        '重新生成',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getBackgroundColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 构建主要内容
  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左栏 - 模型选择
          Expanded(
            flex: 2,
            child: _buildModelSelectionColumn(),
          ),
          
          const SizedBox(width: 32),
          
          // 右栏 - 其他参数
          Expanded(
            flex: 3,
            child: _buildParametersColumn(),
          ),
        ],
      ),
    );
  }

  /// 构建左栏 - 模型选择列
  Widget _buildModelSelectionColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和说明
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '模型选择',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _modelSelectionError != null ? Colors.red : WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择一个或多个模型来生成剧情推演',
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
              if (_selectedModels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '已选择 ${_selectedModels.length} 个模型',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
              if (_modelSelectionError != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _modelSelectionError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        const Divider(height: 1),
        
        // 模型列表
        Expanded(
          child: _isLoadingModels
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _availableModels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.model_training_outlined,
                              size: 48,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无可用模型',
                              style: TextStyle(
                                fontSize: 16,
                                color: WebTheme.getTextColor(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '请先配置AI模型',
                              style: TextStyle(
                                fontSize: 14,
                                color: WebTheme.getSecondaryTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _availableModels.length,
                      itemBuilder: (context, index) {
                        final model = _availableModels[index];
                        final isSelected = _selectedModels.any((selected) => selected.id == model.id);
                        
                        return _buildModelListItem(model, isSelected);
                      },
                    ),
        ),
      ],
    );
  }

  /// 构建右栏 - 参数选择列
  Widget _buildParametersColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 可滚动的主要内容区域
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 指令（包含预设标签）
                _buildStyleInstructionsSection(),
                
                const SizedBox(height: 32),
                
                // 生成数量
                _buildGenerationCountSection(),
                
                const SizedBox(height: 24),
                
                // 场景内容生成控制
                _buildSceneContentToggle(),
              ],
            ),
          ),
        ),
        
        // 底部固定的配置预览
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _buildConfigPreview(),
        ),
      ],
    );
  }

  /// 构建结果内容
  Widget _buildResultsContent() {
    return Column(
      children: [
        // 生成状态说明
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: _buildGenerationHeader(),
        ),
        
        // 结果展示 - 占用剩余所有空间
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: StoryPredictionResults(
              results: _results,
              isGenerating: _isGenerating,
              hasRunningTask: _isGenerating, // 🔥 传递任务运行状态
              onPreviewMerge: _handlePreviewMerge,
              onAddToNextChapter: _handleAddToNextChapter,
              onRefine: _handleRefine, // 🔥 添加继续推演回调
            ),
          ),
        ),
      ],
    );
  }

  /// 构建生成状态头部
  Widget _buildGenerationHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple[200]!),
      ),
      child: Row(
        children: [
          Icon(
            _isGenerating ? Icons.autorenew : Icons.check_circle_outline,
            color: Colors.deepPurple[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isGenerating ? '正在生成剧情推演...' : '生成完成',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple[700],
                  ),
                ),
                if (_isGenerating)
                  Text(
                    '请稍候，AI正在为您创建$_generationCount个剧情选项',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.deepPurple[600],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  /// 构建指令区域
  Widget _buildStyleInstructionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '指令',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _styleInstructionsError != null ? Colors.red : WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '描述希望的剧情推演风格和要求（选填）',
          style: TextStyle(
            fontSize: 14,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _styleInstructionsController,
          maxLines: 3,
          onChanged: (value) {
            // 实时清除错误状态
            if (_styleInstructionsError != null && value.trim().isNotEmpty) {
              setState(() {
                _styleInstructionsError = null;
              });
            }
            // 实时保存风格指令
            _saveCachedPreferences();
          },
          decoration: InputDecoration(
            hintText: '点击下方标签快速添加指令，或自定义输入...',
            hintStyle: TextStyle(
              color: WebTheme.getSecondaryTextColor(context),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _styleInstructionsError != null 
                  ? Colors.red 
                  : (WebTheme.isDarkMode(context) 
                    ? WebTheme.darkGrey300 
                    : WebTheme.grey300),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _styleInstructionsError != null 
                  ? Colors.red.withOpacity(0.5) 
                  : (WebTheme.isDarkMode(context) 
                    ? WebTheme.darkGrey300 
                    : WebTheme.grey300),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _styleInstructionsError != null 
                  ? Colors.red 
                  : WebTheme.getTextColor(context),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: WebTheme.getSurfaceColor(context),
            errorText: null, // 我们使用自定义错误显示
          ),
          style: TextStyle(
            color: WebTheme.getTextColor(context),
            fontSize: 14,
          ),
        ),
        
        // 预设指令标签
        const SizedBox(height: 16),
        _buildInstructionTags(),
        
        if (_styleInstructionsError != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _styleInstructionsError!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 构建生成数量区域
  Widget _buildGenerationCountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成数量',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '每个模型生成的剧情选项数量',
          style: TextStyle(
            fontSize: 14,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (int i = 2; i <= 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ChoiceChip(
                  label: Text('$i 个'),
                  selected: _generationCount == i,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _generationCount = i;
                        // 🚀 修复：同步更新高级配置中的生成数量
                        _advancedConfig = _advancedConfig?.copyWith() ?? StoryPredictionAdvancedConfig(
                          contextSelection: _createDefaultContextData(),
                        );
                      });
                      // 实时保存生成数量
                      _saveCachedPreferences();
                      AppLogger.i('StoryPredictionDialog', '🔄 生成数量已更新为: $i');
                    }
                  },
                  selectedColor: WebTheme.isDarkMode(context) 
                    ? Colors.deepPurple[300]?.withOpacity(0.3)
                    : Colors.deepPurple[100],
                  backgroundColor: WebTheme.isDarkMode(context)
                    ? WebTheme.darkGrey200
                    : WebTheme.grey100,
                  side: BorderSide(
                    color: _generationCount == i 
                      ? WebTheme.getTextColor(context)
                      : Colors.transparent,
                    width: 1,
                  ),
                  labelStyle: TextStyle(
                    color: _generationCount == i 
                      ? (WebTheme.isDarkMode(context) 
                        ? Colors.deepPurple[200]
                        : Colors.deepPurple[800])
                      : WebTheme.getSecondaryTextColor(context),
                    fontSize: 14,
                    fontWeight: _generationCount == i ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 构建场景内容生成控制
  Widget _buildSceneContentToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) 
            ? WebTheme.darkGrey300 
            : WebTheme.grey300,
        ),
      ),
      child: Row(
        children: [
          Switch(
            value: _generateSceneContent,
            onChanged: (value) {
              setState(() {
                _generateSceneContent = value;
              });
              // 实时保存场景内容生成开关
              _saveCachedPreferences();
            },
            activeColor: Colors.deepPurple[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '场景内容一起生成',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '生成摘要的同时生成详细的场景内容',
                  style: TextStyle(
                    fontSize: 13,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建配置预览
  Widget _buildConfigPreview() {
    if (_selectedModels.isEmpty) {
      return Container();
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) 
            ? WebTheme.darkGrey300 
            : WebTheme.grey300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '生成预览',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '将从 ${_selectedModels.length} 个模型中轮流选择，生成 $_generationCount 个选项',
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          Text(
            '总计生成 $_generationCount 个剧情推演',
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          if (_generateSceneContent)
            Text(
              '包含详细场景内容生成',
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
        ],
      ),
    );
  }


  /// 构建单个模型列表项
  Widget _buildModelListItem(UnifiedAIModel model, bool isSelected) {
    final canSelect = _selectedModels.length < 5 || isSelected; // 最多选择5个模型
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected 
          ? WebTheme.getTextColor(context).withOpacity(0.05)
          : null,
        borderRadius: BorderRadius.circular(8),
        border: isSelected 
          ? Border.all(
              color: WebTheme.getTextColor(context).withOpacity(0.2),
              width: 1,
            ) 
          : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: canSelect ? () => _toggleModelSelection(model) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // 模型提供商图标
                _buildModelIcon(model),
                
                const SizedBox(width: 12),
                
                // 模型信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              model.displayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: canSelect 
                                  ? WebTheme.getTextColor(context)
                                  : WebTheme.getSecondaryTextColor(context),
                              ),
                            ),
                          ),
                          if (model.isPublic && model is PublicAIModel && model.publicConfig.recommended == true)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '推荐',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            model.provider,
                            style: TextStyle(
                              fontSize: 12,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: model.isPublic 
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              model.isPublic ? '公共' : '私有',
                              style: TextStyle(
                                fontSize: 10,
                                color: model.isPublic ? Colors.blue[700] : Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (model.isPublic && model.creditMultiplierDisplay.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                model.creditMultiplierDisplay,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                
                // 选择框
                Checkbox(
                  value: isSelected,
                  onChanged: canSelect ? (bool? value) => _toggleModelSelection(model) : null,
                  activeColor: WebTheme.getTextColor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建模型提供商图标
  Widget _buildModelIcon(UnifiedAIModel model) {
    final isDark = WebTheme.isDarkMode(context);
    final color = ProviderIcons.getProviderColor(model.provider);
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? color.withOpacity(0.2) : color.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ProviderIcons.getProviderIcon(
          model.provider, 
          size: 20, 
          useHighQuality: true,
        ),
      ),
    );
  }

  /// 构建预设指令标签
  Widget _buildInstructionTags() {
    // 按类别分组
    final Map<String, List<Map<String, dynamic>>> groupedInstructions = {};
    for (final instruction in _presetInstructions) {
      final category = instruction['category'] as String;
      if (!groupedInstructions.containsKey(category)) {
        groupedInstructions[category] = [];
      }
      groupedInstructions[category]!.add(instruction);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '快速指令',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '点击添加常用写作指令',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        
        // 按类别展示标签
        ...groupedInstructions.entries.map((entry) {
          final category = entry.key;
          final instructions = entry.value;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类别标题
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: WebTheme.getTextColor(context).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                
                // 该类别的标签
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: instructions.map((instructionData) {
                    final label = instructionData['label'] as String;
                    final instruction = instructionData['instruction'] as String;
                    final color = instructionData['color'] as Color;
                    
                    return InkWell(
                      onTap: () => _addInstructionToField(instruction),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: color.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 14,
                              color: color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: color.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  /// 添加指令到输入框
  void _addInstructionToField(String instruction) {
    final currentText = _styleInstructionsController.text;
    String newText;
    
    if (currentText.trim().isEmpty) {
      // 如果输入框为空，直接添加指令
      newText = instruction;
    } else {
      // 如果输入框有内容，在末尾添加分号和指令
      final trimmedText = currentText.trim();
      if (trimmedText.endsWith('；') || trimmedText.endsWith(';')) {
        newText = '$trimmedText $instruction';
      } else {
        newText = '$trimmedText；$instruction';
      }
    }
    
    setState(() {
      _styleInstructionsController.text = newText;
      // 将光标移到末尾
      _styleInstructionsController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
    });
    
    // 实时保存
    _saveCachedPreferences();
    
    AppLogger.d('StoryPredictionDialog', '添加指令: $instruction');
  }

  /// 切换模型选择状态
  void _toggleModelSelection(UnifiedAIModel model) {
    setState(() {
      final isCurrentlySelected = _selectedModels.any((selected) => selected.id == model.id);
      
      if (isCurrentlySelected) {
        // 取消选择
        _selectedModels = _selectedModels.where((selected) => selected.id != model.id).toList();
        AppLogger.d('StoryPredictionDialog', '取消选择模型: ${model.displayName}');
      } else {
        // 选择模型（检查数量限制）
        if (_selectedModels.length < 5) {
          _selectedModels = [..._selectedModels, model];
          AppLogger.d('StoryPredictionDialog', '选择模型: ${model.displayName}');
        }
      }
      
      // 实时清除模型选择错误状态
      if (_modelSelectionError != null && _selectedModels.isNotEmpty) {
        _modelSelectionError = null;
      }
    });
    
    // 实时保存模型选择到缓存
    _saveCachedPreferences();
  }

  /// 安全显示消息
  void _showMessage(String message, {Color? backgroundColor, bool isError = false}) {
    // 检查widget是否仍然在树中且有有效的context
    if (!mounted || !context.mounted) return;
    
    // 使用try-catch包装，防止在widget销毁期间调用
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor ?? (isError ? Colors.red : Colors.orange),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 如果无法显示SnackBar，至少记录错误
      AppLogger.w('StoryPredictionDialog', '无法显示消息: $message, 错误: $e');
    }
  }

  /// 显示错误消息
  void _showErrorMessage(String message) {
    _showMessage(message, backgroundColor: Colors.red, isError: true);
  }

  /// 显示成功消息
  void _showSuccessMessage(String message) {
    _showMessage(message, backgroundColor: Colors.green);
  }

  // _showWarningMessage 已不再使用


  /// 显示高级设置
  void _showAdvancedSettings() {
    AppLogger.i('StoryPredictionDialog', '显示高级设置');
    
    // 检查widget是否还在widget树中，避免生命周期错误
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) {
          _advancedModalSetState = modalSetState;
          return _buildAdvancedSettingsDialog();
        },
      ),
    ).then((_) {
      // 关闭时清理引用
      _advancedModalSetState = null;
    });
  }

  /// 🚀 智能setState：如果在高级设置弹窗内，则优先使用其本地setState刷新UI
  void _setStateAdvanced(void Function() fn) {
    final setter = _advancedModalSetState;
    if (setter != null) {
      try {
        setter(fn);
        return;
      } catch (_) {}
    }
    if (mounted) setState(fn);
  }
  
  /// 构建高级设置对话框
  Widget _buildAdvancedSettingsDialog() {
    return Dialog(
      child: Container(
        width: 1200, // 扩大一倍
        constraints: const BoxConstraints(maxHeight: 900),
        decoration: BoxDecoration(
          color: WebTheme.getBackgroundColor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: WebTheme.isDarkMode(context) 
                      ? WebTheme.darkGrey300 
                      : WebTheme.grey300,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: Colors.deepPurple[700],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '剧情推演高级设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildAdvancedGenerationCountField(),
                    const SizedBox(height: 20),
                    _buildAdvancedContextSelectionField(),
                    const SizedBox(height: 20),
                    _buildSummaryPromptTemplateField(),
                    const SizedBox(height: 20),
                    _buildScenePromptTemplateField(),
                  ],
                ),
              ),
            ),
            
            // 按钮栏
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: WebTheme.isDarkMode(context) 
                      ? WebTheme.darkGrey300 
                      : WebTheme.grey300,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleSaveAdvancedSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建高级生成数量字段
  Widget _buildAdvancedGenerationCountField() {
    return FormFieldFactory.createLengthField<int>(
      title: '生成数量',
      description: '设置每次生成的剧情推演数量',
      options: [
        RadioOption(value: 2, label: '2个剧情推演'),
        RadioOption(value: 3, label: '3个剧情推演'),
        RadioOption(value: 4, label: '4个剧情推演'),
        RadioOption(value: 5, label: '5个剧情推演'),
      ],
      value: _generationCount,
      onChanged: (value) {
        if (value != null) {
          _setStateAdvanced(() {
            _generationCount = value;
            // 🚀 修复：同步更新高级配置
            _advancedConfig = _advancedConfig?.copyWith() ?? StoryPredictionAdvancedConfig(
              contextSelection: _createDefaultContextData(),
            );
          });
          // 实时保存生成数量
          _saveCachedPreferences();
          AppLogger.i('StoryPredictionDialog', '🔄 高级设置中生成数量已更新为: $value');
        }
      },
    );
  }

  /// 构建高级上下文选择字段
  Widget _buildAdvancedContextSelectionField() {
    final data = _ensureContextSelectionData();
    return FormFieldFactory.createContextSelectionField(
      title: '上下文选择',
      description: '选择要包含在剧情推演中的上下文信息',
      contextData: data,
      onSelectionChanged: (newContextData) {
        _setStateAdvanced(() {
          _advancedConfig = _advancedConfig?.copyWith(
            contextSelection: newContextData,
          ) ?? StoryPredictionAdvancedConfig(
            contextSelection: newContextData,
          );
        });
        // 实时保存上下文选择
        _saveCachedPreferences();
      },
    );
  }

  /// 确保上下文组件使用通用数据源
  ContextSelectionData _ensureContextSelectionData() {
    final current = _advancedConfig?.contextSelection;
    if (current == null) {
      final contextData = _createDefaultContextData();
      _advancedConfig = _advancedConfig?.copyWith(contextSelection: contextData) ?? StoryPredictionAdvancedConfig(contextSelection: contextData);
      return contextData;
    }
    final hasAny = current.availableItems.isNotEmpty || current.selectedItems.isNotEmpty;
    if (!hasAny) {
      final contextData = _createDefaultContextData();
      _advancedConfig = _advancedConfig?.copyWith(contextSelection: contextData) ?? StoryPredictionAdvancedConfig(contextSelection: contextData);
      return contextData;
    }
    return current;
  }

  // 附加指令字段取消（需求变更）

  /// 构建剧情续写提示词模板字段
  Widget _buildSummaryPromptTemplateField() {
    // 🚀 修复：确保从高级配置中获取当前选择的模板ID
    final currentTemplateId = _advancedConfig?.summaryPromptTemplateId ?? _summaryPromptTemplateId;
    
    return FormFieldFactory.createPromptTemplateSelectionField(
      title: '剧情续写提示词模板',
      description: '选择用于分析当前剧情并生成后续发展大纲的提示词模板',
      selectedTemplateId: currentTemplateId,
      aiFeatureType: AIFeatureType.storyPlotContinuation.name,
      onTemplateSelected: (templateId) {
        _setStateAdvanced(() {
          _summaryPromptTemplateId = templateId;
          // 🚀 修复：同步更新到高级配置中
          _advancedConfig = _advancedConfig?.copyWith(
            summaryPromptTemplateId: templateId,
          ) ?? StoryPredictionAdvancedConfig(
            contextSelection: _createDefaultContextData(),
            summaryPromptTemplateId: templateId,
          );
        });
        // 实时保存提示词模板选择
        _saveCachedPreferences();
        AppLogger.i('StoryPredictionDialog', '🔄 剧情续写提示词模板已更新为: $templateId');
      },
      onReset: () {
        _setStateAdvanced(() {
          _summaryPromptTemplateId = null;
          _advancedConfig = _advancedConfig?.copyWith(
            summaryPromptTemplateId: null,
          );
        });
        _saveCachedPreferences();
        AppLogger.i('StoryPredictionDialog', '🔄 剧情续写提示词模板已重置');
      },
    );
  }

  /// 构建场景内容提示词模板字段
  Widget _buildScenePromptTemplateField() {
    // 🚀 修复：确保从高级配置中获取当前选择的模板ID
    final currentTemplateId = _advancedConfig?.scenePromptTemplateId ?? _scenePromptTemplateId;
    
    return FormFieldFactory.createPromptTemplateSelectionField(
      title: '场景内容生成提示词模板',
      description: '选择用于生成详细场景内容的提示词模板',
      selectedTemplateId: currentTemplateId,
      aiFeatureType: AIFeatureType.summaryToScene.name,
      onTemplateSelected: (templateId) {
        _setStateAdvanced(() {
          _scenePromptTemplateId = templateId;
          // 🚀 修复：同步更新到高级配置中
          _advancedConfig = _advancedConfig?.copyWith(
            scenePromptTemplateId: templateId,
          ) ?? StoryPredictionAdvancedConfig(
            contextSelection: _createDefaultContextData(),
            scenePromptTemplateId: templateId,
          );
        });
        // 实时保存提示词模板选择
        _saveCachedPreferences();
        AppLogger.i('StoryPredictionDialog', '🔄 场景内容提示词模板已更新为: $templateId');
      },
      onReset: () {
        _setStateAdvanced(() {
          _scenePromptTemplateId = null;
          _advancedConfig = _advancedConfig?.copyWith(
            scenePromptTemplateId: null,
          );
        });
        _saveCachedPreferences();
        AppLogger.i('StoryPredictionDialog', '🔄 场景内容提示词模板已重置');
      },
    );
  }

  /// 处理保存高级设置
  void _handleSaveAdvancedSettings() {
    // 🚀 修复：确保提示词模板ID正确更新到高级配置和状态中
    setState(() {
      _advancedConfig = StoryPredictionAdvancedConfig(
        contextSelection: _advancedConfig?.contextSelection ?? _createDefaultContextData(),
        additionalInstructions: _additionalInstructionsController.text.isNotEmpty 
          ? _additionalInstructionsController.text 
          : null,
        summaryPromptTemplateId: _summaryPromptTemplateId,
        scenePromptTemplateId: _scenePromptTemplateId,
      );
    });
    
    // 保存高级配置到缓存
    _saveCachedPreferences();
    
    Navigator.of(context).pop();
    
    // 🚀 修复：显示更详细的保存信息
    String savedInfo = '高级设置已保存';
    if (_summaryPromptTemplateId != null) {
      savedInfo += '，包括剧情续写提示词模板';
    }
    if (_scenePromptTemplateId != null) {
      savedInfo += '，包括场景内容提示词模板';
    }
    _showSuccessMessage(savedInfo);
    
    AppLogger.i('StoryPredictionDialog', '✅ 高级设置保存完成: summaryTemplate=$_summaryPromptTemplateId, sceneTemplate=$_scenePromptTemplateId');
  }

  /// 创建默认上下文数据
  ContextSelectionData _createDefaultContextData() {
    // 🚀 重构：使用公共助手类创建默认上下文数据（参考扩写表单）
    return ContextSelectionHelper.initializeContextData(
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
    );
  }

  /// 处理生成请求
  void _handleGenerate() {
    AppLogger.i('StoryPredictionDialog', '🚀 _handleGenerate 方法被调用');
    
    // 验证配置并更新UI状态
    AppLogger.i('StoryPredictionDialog', '📊 验证配置: selectedModels=${_selectedModels.length}, styleInstructions="${_styleInstructionsController.text.trim()}"');
    
    bool hasErrors = false;
    
    // 清除之前的错误状态
    setState(() {
      _modelSelectionError = null;
      _styleInstructionsError = null;
    });
    
    // 验证模型选择
    if (_selectedModels.isEmpty) {
      AppLogger.w('StoryPredictionDialog', '❌ 验证失败: 没有选择模型');
      setState(() {
        _modelSelectionError = '请先选择至少一个AI模型';
      });
      hasErrors = true;
    }

    // 风格指令验证 - 已取消非空限制
    // if (_styleInstructionsController.text.trim().isEmpty) {
    //   AppLogger.w('StoryPredictionDialog', '❌ 验证失败: 没有输入风格指令');
    //   setState(() {
    //     _styleInstructionsError = '请输入风格指令';
    //   });
    //   hasErrors = true;
    // }
    
    // 如果有验证错误，不继续执行
    if (hasErrors) {
      AppLogger.w('StoryPredictionDialog', '❌ 验证失败，停止生成流程');
      return;
    }
    
    AppLogger.i('StoryPredictionDialog', '✅ 验证通过，开始生成流程');

    setState(() {
      _isLoading = true;
      _hasStartedGeneration = true;
      _isGenerating = true;
    });

    // 保存用户偏好到缓存
    _saveCachedPreferences();

    final config = api_models.StoryPredictionConfig(
      selectedModels: _selectedModels,
      styleInstructions: _styleInstructionsController.text,
      generationCount: _generationCount,
      generateSceneContent: _generateSceneContent,
      additionalInstructions: null, // 附加指令取消
      summaryPromptTemplateId: _advancedConfig?.summaryPromptTemplateId,
      scenePromptTemplateId: _advancedConfig?.scenePromptTemplateId,
    );

    AppLogger.i('StoryPredictionDialog', '开始生成剧情推演: selectedModels=${_selectedModels.length}, generationCount=$_generationCount');
    
    // 启动真实生成流程 
    _startRealGeneration(config);
    
    // 同时启动一个模拟流程作为备用测试
    AppLogger.i('StoryPredictionDialog', '🧪 启动模拟流程作为测试');
  }

  /// 启动真实生成流程
  void _startRealGeneration(api_models.StoryPredictionConfig config) async {
    AppLogger.i('StoryPredictionDialog', '🎯 _startRealGeneration 开始执行');
    try {
      // 创建API请求
      AppLogger.i('StoryPredictionDialog', '📝 创建API请求: chapterId=${_currentChapterId}');
      final request = api_models.StoryPredictionRequest(
        chapterId: _currentChapterId,
        modelConfigs: config.selectedModels.map((model) => api_models.ModelConfig(
          type: model.isPublic ? 'PUBLIC' : 'PRIVATE',
          configId: model.id,
        )).toList(),
        generationCount: config.generationCount,
        styleInstructions: config.styleInstructions,
        contextSelection: _buildApiContextSelection(),
        contextSelections: _buildUniversalContextSelections(),
        additionalInstructions: config.additionalInstructions,
        summaryPromptTemplateId: config.summaryPromptTemplateId,
        scenePromptTemplateId: config.scenePromptTemplateId,
        generateSceneContent: config.generateSceneContent,
      );
      AppLogger.i('StoryPredictionDialog', '✅ API请求创建成功');

      // 获取服务实例
      AppLogger.i('StoryPredictionDialog', '🔧 获取服务实例');
      final apiClient = context.read<ApiClient>();
      final storyPredictionService = StoryPredictionService(apiClient);
      AppLogger.i('StoryPredictionDialog', '✅ 服务实例创建完成');

      // 创建任务
      AppLogger.i('StoryPredictionDialog', '📤 发送任务创建请求: novelId=${widget.novelId}');
      final response = await storyPredictionService.createStoryPredictionTask(
        widget.novelId,
        request,
      );

      AppLogger.i('StoryPredictionDialog', '✅ 任务创建成功: taskId=${response.taskId}');

      // 🔥 保存当前任务ID（用于迭代优化）
      _currentTaskId = response.taskId;

      // 立即创建生成状态的占位结果
      _initializeGeneratingResults();

      // 开始监听任务进度
      AppLogger.i('StoryPredictionDialog', '👂 开始监听任务进度');
      _subscribeToTaskProgress(storyPredictionService, response.taskId);

    } catch (e, stackTrace) {
      AppLogger.e('StoryPredictionDialog', '启动生成失败', e);
      AppLogger.e('StoryPredictionDialog', '错误堆栈', stackTrace);
      
        setState(() {
          _isLoading = false;
          _isGenerating = false;
        });

        _showErrorMessage('启动生成失败: ${e.toString()}');
    }
  }

  /// 监听任务进度
  void _subscribeToTaskProgress(StoryPredictionService service, String taskId) {
    service.subscribeToTaskProgress(widget.novelId, taskId).listen(
      (event) {
        AppLogger.d('StoryPredictionDialog', '收到任务事件: type=${event.type}, status=${event.status}');
        
        // 更新UI状态
        if (!mounted) return;
        
        setState(() {
          _isLoading = false;
          
          // 解析进度数据
          if (event.progress != null) {
            final apiResults = service.parsePredictionResults(event.progress);
            if (apiResults.isNotEmpty) {
              // 转换为本地PredictionResult类型
              final updatedResults = apiResults.map((apiResult) {
                // 🔥 查找是否有对应的占位卡片，保留其 sourceTaskId
                final existingResult = _results.firstWhere(
                  (r) => r.id == apiResult.id,
                  orElse: () => PredictionResult(
                    id: apiResult.id,
                    modelName: '',
                    summary: '',
                    status: PredictionStatus.pending,
                    createdAt: DateTime.now(),
                  ),
                );
                
                return PredictionResult(
                  id: apiResult.id,
                  modelName: apiResult.modelName,
                  summary: apiResult.summary,
                  sceneContent: apiResult.sceneContent,
                  status: _convertStatus(apiResult.status),
                  sceneStatus: _convertStatus(apiResult.sceneStatus),
                  createdAt: apiResult.createdAt,
                  error: apiResult.error,
                  sourceTaskId: existingResult.sourceTaskId ?? event.taskId,
                  refinementInstructions: existingResult.refinementInstructions, // 🔥 保留迭代需求
                );
              }).toList();
              
              // 更新结果，保持生成状态的占位结果数量
              _results = _mergeResults(updatedResults);
            }
          }
          
          // 检查是否完成（同时兼容全局SSE事件类型与状态字段）
          final String typeLower = (event.type).toLowerCase();
          final String statusUpper = (event.status).toUpperCase();
          final bool isCompletedType = typeLower == 'task_completed' || typeLower == 'task_failed';
          final bool isTerminalStatus = statusUpper == 'COMPLETED' || statusUpper == 'FAILED' || statusUpper == 'CANCELLED' || statusUpper == 'DEAD_LETTER' || statusUpper == 'COMPLETED_WITH_ERRORS';
          if (isCompletedType || isTerminalStatus) {
            _isGenerating = false;
            if (typeLower == 'task_failed' || statusUpper == 'FAILED') {
              _showErrorMessage('生成失败: ${event.error ?? '未知错误'}');
            }
          }
        });
      },
      onError: (error) {
        AppLogger.e('StoryPredictionDialog', '监听任务进度出错', error);
        
        if (!mounted) return;
        
        setState(() {
          _isLoading = false;
          _isGenerating = false;
        });
        
        _showErrorMessage('监听进度失败: ${error.toString()}');
      },
    );
  }

  /// 初始化生成状态的占位结果
  void _initializeGeneratingResults() {
    setState(() {
      _results = List.generate(_generationCount, (index) => 
        PredictionResult(
          id: 'generating_$index',
          modelName: _selectedModels.isNotEmpty ? _selectedModels[index % _selectedModels.length].displayName : '未知模型',
          summary: '',
          sceneContent: null,
          status: PredictionStatus.generating,
          sceneStatus: PredictionStatus.pending,
          createdAt: DateTime.now(),
          error: null,
        )
      );
    });
  }

  /// 合并API结果与现有结果
  List<PredictionResult> _mergeResults(List<PredictionResult> apiResults) {
    final merged = List<PredictionResult>.from(_results);
    
    // 🔥 检查是否有迭代优化的占位卡片（ID为taskId，状态为generating）
    final placeholderIndex = merged.indexWhere((r) => 
      r.id == _currentTaskId && r.status == PredictionStatus.generating
    );
    
    if (placeholderIndex >= 0) {
      // 🔥 找到占位卡片，保留其 refinementInstructions，然后删除
      final placeholder = merged[placeholderIndex];
      merged.removeAt(placeholderIndex);
      
      // 🔥 追加新结果时，保留 refinementInstructions
      final resultsWithInstructions = apiResults.map((result) => result.copyWith(
        refinementInstructions: placeholder.refinementInstructions,
      )).toList();
      
      merged.addAll(resultsWithInstructions);
      AppLogger.i('StoryPredictionDialog', '🔄 迭代优化结果已追加，当前共${merged.length}个结果');
    } else {
      // 原有逻辑：用API结果更新对应的占位结果
      for (int i = 0; i < apiResults.length && i < merged.length; i++) {
        // 🔥 保留原有卡片的 refinementInstructions
        final existingInstructions = merged[i].refinementInstructions;
        merged[i] = apiResults[i].copyWith(
          refinementInstructions: existingInstructions,
        );
      }
      
      // 如果API结果比预期多，添加额外的结果
      if (apiResults.length > merged.length) {
        merged.addAll(apiResults.skip(merged.length));
      }
    }
    
    return merged;
  }

  /// 转换API状态为本地状态
  PredictionStatus _convertStatus(api_models.PredictionStatus apiStatus) {
    switch (apiStatus) {
      case api_models.PredictionStatus.pending:
        return PredictionStatus.pending;
      case api_models.PredictionStatus.generating:
        return PredictionStatus.generating;
      case api_models.PredictionStatus.completed:
        return PredictionStatus.completed;
      case api_models.PredictionStatus.failed:
        return PredictionStatus.failed;
      case api_models.PredictionStatus.skipped:
        return PredictionStatus.skipped; // 正确映射为skipped
    }
  }



  // 旧的应用/修改逻辑已废弃，改为 预览合并/添加到下一章

  /// 处理预览合并：复用 AI 任务中心的合并预览视图
  void _handlePreviewMerge(PredictionResult result) {
    final event = {
      'taskType': 'STORY_PREDICTION_SINGLE',
      'taskId': 'local-preview-${result.id}',
      'novelId': widget.novelId,
      'result': {
        'generatedSummary': result.summary,
        'generatedContent': result.sceneContent,
      },
    };
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: MergePreviewDialog(event: event),
      ),
    ).then((value) {
      if (value is Map && value['newChapterId'] is String && (value['newChapterId'] as String).isNotEmpty) {
        _updateCurrentChapterId(value['newChapterId'] as String);
      }
    });
  }

  /// 处理"添加到下一章"：按"作为新章节插入（末尾）"逻辑合并，并记录 nowChapterId
  Future<void> _handleAddToNextChapter(PredictionResult result) async {
    // 显示加载中提示
    final loadingController = LoadingToast.show(context, message: '正在添加到下一章...');
    
    try {
      final api = context.read<ApiClient>();
      final repo = EditorRepositoryImpl(apiClient: api);

      // 选择"最后一个章节之后"作为目标：找出最后一个卷与末尾章节
      final novel = await repo.getNovel(widget.novelId);
      if (novel == null || novel.acts.isEmpty) {
        loadingController.error('无法加载小说结构');
        return;
      }
      final lastAct = novel.acts.last;

      // 创建新章节 + 初始场景，内容来自当前结果
      // 若当前对话上下文有"当前章节ID"，则插入到该章节之后
      final String currentChapterId = _currentChapterId; // 当前章节上下文（保证非空）
      // 计算插入所用的 actId：优先使用当前章节所在卷，否则回退到最后一个卷
      String actIdForInsert = lastAct.id;
      for (final act in novel.acts) {
        final hasChapter = act.chapters.any((c) => c.id == currentChapterId);
        if (hasChapter) {
          actIdForInsert = act.id;
          break;
        }
      }
      final resp = await repo.addChapterWithScene(
        widget.novelId,
        actIdForInsert,
        'AI生成章节',
        'AI生成场景',
        sceneSummary: result.summary,
        sceneContent: result.sceneContent,
        insertAfterChapterId: currentChapterId,
      );

      final String? newChapterId = resp['chapterId']?.toString();
      if (newChapterId == null || newChapterId.isEmpty) {
        loadingController.error('创建新章节失败');
        return;
      }

      _updateCurrentChapterId(newChapterId);

      // 切换到成功状态
      loadingController.success('已成功添加到新章节');
    } catch (e) {
      loadingController.error('添加到下一章失败: $e');
    }
  }

  /// 🔥 处理迭代优化：基于选定结果继续推演
  Future<void> _handleRefine(PredictionResult selectedResult) async {
    // 弹出输入对话框（带模型选择）
    final result = await _showRefinementInputDialog(selectedResult);
    
    if (result == null) {
      return; // 用户取消
    }
    
    final refinementInstructions = result['instructions'] as String?;
    final selectedModel = result['model'] as UnifiedAIModel?;
    
    if (refinementInstructions == null || refinementInstructions.trim().isEmpty) {
      return; // 没有输入修改意见
    }
    
    // 显示加载提示
    final loadingController = LoadingToast.show(context, message: '正在创建迭代优化任务...');
    
    try {
      final service = StoryPredictionService(context.read<ApiClient>());
      
      // 确定使用的模型：用户选择的模型 > 当前配置的第一个模型
      final List<UnifiedAIModel> modelsToUse = selectedModel != null 
          ? [selectedModel] 
          : (_selectedModels.isNotEmpty ? [_selectedModels.first] : []);
      
      if (modelsToUse.isEmpty) {
        loadingController.error('请先选择AI模型');
        return;
      }
      
      AppLogger.i('StoryPredictionDialog', '🔄 迭代优化使用模型: ${modelsToUse.first.displayName}');
      
      // 构建迭代优化请求
      final request = api_models.RefineStoryPredictionRequest.fromConfig(
        originalTaskId: selectedResult.sourceTaskId ?? _currentTaskId ?? '', // 🔥 使用卡片的来源任务ID
        basePredictionId: selectedResult.id,
        refinementInstructions: refinementInstructions,
        newModels: modelsToUse, // 🔥 使用选择的单个模型
        generationCount: 1, // 🔥 只生成1个结果
        contextSelection: null, // 继承原任务配置
        generateSceneContent: _generateSceneContent,
        styleInstructions: _styleInstructionsController.text.trim().isNotEmpty 
            ? _styleInstructionsController.text.trim() 
            : null,
        additionalInstructions: _additionalInstructionsController.text.trim().isNotEmpty
            ? _additionalInstructionsController.text.trim()
            : null,
      );
      
      // 调用API
      final response = await service.refineStoryPrediction(widget.novelId, request);
      
      loadingController.success('迭代优化任务已创建');
      
      // 🔥 不清空现有结果，而是标记正在生成新的迭代结果
      setState(() {
        // 添加一个占位的"生成中"卡片
        _results.add(PredictionResult(
          id: response.taskId, // 临时使用taskId作为ID
          modelName: modelsToUse.first.displayName,
          summary: '正在基于您的修改意见生成新的推演...',
          status: PredictionStatus.generating,
          sceneStatus: PredictionStatus.pending,
          createdAt: DateTime.now(),
          sourceTaskId: response.taskId, // 🔥 新任务的sourceTaskId就是它自己
          refinementInstructions: refinementInstructions, // 🔥 保存优化需求
        ));
        _isGenerating = true;
        _currentTaskId = response.taskId;
      });
      
      // 监听新任务进度
      _subscribeToTaskProgress(service, response.taskId);
      
    } catch (e, stackTrace) {
      AppLogger.e('StoryPredictionDialog', '创建迭代优化任务失败', e);
      AppLogger.e('StoryPredictionDialog', '错误堆栈', stackTrace);
      loadingController.error('创建迭代优化任务失败: $e');
    }
  }
  
  /// 🔥 显示修改意见输入对话框（带模型选择）
  Future<Map<String, dynamic>?> _showRefinementInputDialog(PredictionResult selectedResult) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    UnifiedAIModel? selectedModel; // 用户选择的模型
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: WebTheme.getBackgroundColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.auto_fix_high,
                color: Colors.deepPurple[700],
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '基于此结果继续推演',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // 显示选中的结果摘要
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepPurple[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 16,
                            color: Colors.deepPurple[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '选中的结果（使用${selectedResult.modelName}生成）',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        selectedResult.summary,
                        style: TextStyle(
                          fontSize: 13,
                          color: WebTheme.getTextColor(context),
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 🔥 模型选择器
                Text(
                  '选择用于迭代的AI模型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                ModelDisplaySelector(
                  selectedModel: selectedModel,
                  onModelSelected: (model) {
                    setState(() {
                      selectedModel = model;
                    });
                  },
                  placeholder: '选择AI模型（默认使用当前配置）',
                  size: ModelDisplaySize.medium,
                  showIcon: true,
                  showTags: false,
                  showSettingsButton: false,
                  height: 48,
                ),
                
                const SizedBox(height: 16),
                
                // 修改意见输入
                Text(
                  '请输入您的修改意见',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: '例如：希望主角更加勇敢，情节更跌宕起伏，增加一些悬疑元素...',
                    hintStyle: TextStyle(
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: WebTheme.getBorderColor(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.deepPurple[600]!,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: WebTheme.isDarkMode(context)
                        ? Colors.grey[800]
                        : Colors.grey[50],
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: WebTheme.getTextColor(context),
                    height: 1.5,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入修改意见';
                    }
                    if (value.trim().length < 10) {
                      return '修改意见至少需要10个字符';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 8),
                
                // 提示信息
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AI将基于您选择的结果和修改意见，生成新的推演方案',
                        style: TextStyle(
                          fontSize: 12,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              '取消',
              style: TextStyle(
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                // 返回修改意见和选择的模型
                Navigator.of(context).pop({
                  'instructions': controller.text.trim(),
                  'model': selectedModel,
                });
              }
            },
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('开始优化'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  /// 继续生成：当 nowChapterId 存在时，以新章节为 chapterId 再次生成
  void _handleContinueGenerate() {
    if (_nowChapterId == null || _nowChapterId!.isEmpty) return;
    _handleRegenerate();
  }

  /// 处理返回菜单
  void _handleBackToMenu() {
    AppLogger.i('StoryPredictionDialog', '返回菜单，保持用户配置');
    
    setState(() {
      _hasStartedGeneration = false;
      _isGenerating = false;
      _isLoading = false;
      _results.clear();
      // 注意：不重置用户的选择配置，保持_selectedModels等状态
    });
  }

  /// 处理重新生成
  void _handleRegenerate() {
    AppLogger.i('StoryPredictionDialog', '重新生成剧情推演');
    
    setState(() {
      _hasStartedGeneration = false;
      _isGenerating = false;
      _isLoading = false;
      _results.clear();
    });

    // 使用当前配置重新发起生成
    final config = api_models.StoryPredictionConfig(
      selectedModels: _selectedModels,
      styleInstructions: _styleInstructionsController.text,
      generationCount: _generationCount,
      generateSceneContent: _generateSceneContent,
      additionalInstructions: null, // 附加指令取消
      summaryPromptTemplateId: _advancedConfig?.summaryPromptTemplateId,
      scenePromptTemplateId: _advancedConfig?.scenePromptTemplateId,
    );

    setState(() {
      _isLoading = true;
      _hasStartedGeneration = true;
      _isGenerating = true;
    });
    
    // 保存用户偏好到缓存
    _saveCachedPreferences();
    
    _startRealGeneration(config);
  }

  /// 处理取消
  void _handleCancel() {
    _floatingCardOverlay?.remove();
    _floatingCardOverlay = null;
    widget.onCancel?.call();
    Navigator.of(context).pop();
  }

  /// 🎯 处理最小化
  void _handleMinimize() {
    AppLogger.i('StoryPredictionDialog', '🎯 开始最小化...');
    
    // 🔥 标记为最小化状态（防止dispose时移除overlay）
    setState(() {
      _isMinimizing = true;
    });
    AppLogger.i('StoryPredictionDialog', '✅ 已设置 _isMinimizing = true');
    
    // 先获取当前的overlay，再关闭对话框
    final overlay = Overlay.of(context);
    AppLogger.i('StoryPredictionDialog', '✅ 已获取overlay');
    
    // 移除旧的overlay（如果存在）
    _floatingCardOverlay?.remove();
    
    // 创建独立的悬浮卡片widget（不依赖对话框状态）
    final floatingCard = _FloatingPredictionCard(
      chapterTitle: widget.chapter.title,
      onRestore: () {
        // 移除悬浮卡片
        AppLogger.i('StoryPredictionDialog', '🔄 点击展开，准备恢复对话框');
        _floatingCardOverlay?.remove();
        _floatingCardOverlay = null;
        
        // 重新显示对话框
        showDialog(
          context: overlay.context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return StoryPredictionDialog(
              novelId: widget.novelId,
              chapter: widget.chapter,
              onCancel: widget.onCancel,
              onGenerate: widget.onGenerate,
              novel: widget.novel,
              settings: widget.settings,
              settingGroups: widget.settingGroups,
              snippets: widget.snippets,
            );
          },
        );
        AppLogger.i('StoryPredictionDialog', '✅ 对话框已恢复');
      },
      onClose: () {
        // 移除悬浮卡片并关闭
        AppLogger.i('StoryPredictionDialog', '❌ 点击关闭，移除悬浮卡片');
        _floatingCardOverlay?.remove();
        _floatingCardOverlay = null;
        widget.onCancel?.call();
      },
    );
    
    // 创建overlay entry
    _floatingCardOverlay = OverlayEntry(
      builder: (context) => floatingCard,
    );
    AppLogger.i('StoryPredictionDialog', '✅ 已创建悬浮卡片OverlayEntry');
    
    // 先插入overlay，再关闭对话框
    overlay.insert(_floatingCardOverlay!);
    AppLogger.i('StoryPredictionDialog', '✅ 悬浮卡片已插入overlay');
    
    // 延迟一点再关闭对话框，确保overlay已经渲染
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Navigator.of(context).pop();
        AppLogger.i('StoryPredictionDialog', '✅ 对话框已关闭');
      }
    });
  }

  // _createDemoModel 已不再使用
  // 旧的 _buildFloatingCard 和 _handleRestore 方法已移除，
  // 使用独立的 _FloatingPredictionCard widget 替代
}

/// 🎯 独立的悬浮卡片 Widget
class _FloatingPredictionCard extends StatefulWidget {
  final String chapterTitle;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  const _FloatingPredictionCard({
    required this.chapterTitle,
    required this.onRestore,
    required this.onClose,
  });

  @override
  State<_FloatingPredictionCard> createState() => _FloatingPredictionCardState();
}

class _FloatingPredictionCardState extends State<_FloatingPredictionCard> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.getBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.deepPurple.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Icon(
                    Icons.auto_stories,
                    color: Colors.deepPurple[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '剧情推演',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ),
                  // 展开按钮
                  IconButton(
                    onPressed: widget.onRestore,
                    icon: Icon(
                      Icons.open_in_full,
                      size: 18,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    tooltip: '展开',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  // 关闭按钮
                  IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    tooltip: '关闭',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // 章节信息
              Text(
                widget.chapterTitle,
                style: TextStyle(
                  fontSize: 12,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 12),
              
              // 点击展开提示
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '点击展开图标恢复窗口',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.deepPurple[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 剧情推演配置类
class StoryPredictionConfig {
  final List<UnifiedAIModel> selectedModels;
  final int generationCount;
  final String styleInstructions;
  final bool generateSceneContent;
  final StoryPredictionAdvancedConfig advancedConfig;

  StoryPredictionConfig({
    required this.selectedModels,
    required this.generationCount,
    required this.styleInstructions,
    required this.generateSceneContent,
    required this.advancedConfig,
  });

  @override
  String toString() {
    return 'StoryPredictionConfig(models: ${selectedModels.length}, count: $generationCount, sceneContent: $generateSceneContent)';
  }

}

/// 🚀 新增：显示剧情推演对话框的便捷函数（参考扩写表单）
void showStoryPredictionDialog(
  BuildContext context, {
  required String novelId,
  required novel_models.Chapter chapter,
  VoidCallback? onCancel,
  Function(StoryPredictionConfig)? onGenerate,
  // 🚀 新增：完整的小说数据参数（必须传递）
  required novel_models.Novel? novel,
  required List<NovelSettingItem> settings,
  required List<SettingGroup> settingGroups,
  required List<NovelSnippet> snippets,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StoryPredictionDialog(
        novelId: novelId,
        chapter: chapter,
        onCancel: onCancel,
        onGenerate: onGenerate,
        novel: novel,
        settings: settings,
        settingGroups: settingGroups,
        snippets: snippets,
      );
    },
  );
}

/// 高级配置类
class StoryPredictionAdvancedConfig {
  final ContextSelectionData contextSelection;
  final String? additionalInstructions;
  final String? summaryPromptTemplateId; // 剧情续写提示词模板ID
  final String? scenePromptTemplateId; // 场景内容生成提示词模板ID

  StoryPredictionAdvancedConfig({
    required this.contextSelection,
    this.additionalInstructions,
    this.summaryPromptTemplateId,
    this.scenePromptTemplateId,
  });

  /// 创建默认配置
  static StoryPredictionAdvancedConfig defaultConfig() {
    // TODO: 从系统设置中加载默认上下文选择
    final defaultContext = ContextSelectionData(
      novelId: '',
      availableItems: [],
      flatItems: {},
    );

    return StoryPredictionAdvancedConfig(
      contextSelection: defaultContext,
    );
  }

  /// 复制配置并修改指定属性
  StoryPredictionAdvancedConfig copyWith({
    ContextSelectionData? contextSelection,
    String? additionalInstructions,
    String? summaryPromptTemplateId,
    String? scenePromptTemplateId,
  }) {
    return StoryPredictionAdvancedConfig(
      contextSelection: contextSelection ?? this.contextSelection,
      additionalInstructions: additionalInstructions ?? this.additionalInstructions,
      summaryPromptTemplateId: summaryPromptTemplateId ?? this.summaryPromptTemplateId,
      scenePromptTemplateId: scenePromptTemplateId ?? this.scenePromptTemplateId,
    );
  }

}
