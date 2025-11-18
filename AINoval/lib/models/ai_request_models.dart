import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/utils/date_time_parser.dart';

/// AI请求类型枚举（与后端AIFeatureType一一对应）
enum AIRequestType {
  chat('AI_CHAT', '聊天对话'),
  expansion('TEXT_EXPANSION', '扩写文本'),
  summary('TEXT_SUMMARY', '缩写文本'),
  sceneSummary('SCENE_TO_SUMMARY', '场景摘要'),
  refactor('TEXT_REFACTOR', '重构文本'),
  generation('NOVEL_GENERATION', '内容生成'),
  sceneBeat('SCENE_BEAT_GENERATION', '场景节拍生成'),
  novelCompose('NOVEL_COMPOSE', '设定编排'),
    storyPlotContinuation('STORY_PLOT_CONTINUATION', '故事剧情续写'),
  
  // 知识库拆书
  knowledgeExtractionSetting('KNOWLEDGE_EXTRACTION_SETTING', '知识库拆书-设定提取'),
  knowledgeExtractionOutline('KNOWLEDGE_EXTRACTION_OUTLINE', '知识库拆书-章节大纲');

  const AIRequestType(this.value, this.displayName);
  
  final String value;
  final String displayName;
}

/// 通用AI请求模型
class UniversalAIRequest {
  const UniversalAIRequest({
    required this.requestType,
    required this.userId,
    this.sessionId,
    this.novelId,
    this.chapterId,
    this.sceneId,
    this.settingSessionId,
    this.modelConfig,
    this.prompt,
    this.instructions,
    this.selectedText,
    this.contextSelections,
    this.enableSmartContext = false,
    this.parameters = const {},
    this.metadata = const {},
  });

  /// 请求类型
  final AIRequestType requestType;
  
  /// 用户ID
  final String userId;
  
  /// 会话ID（聊天对话时必填）
  final String? sessionId;
  
  /// 小说ID
  final String? novelId;
  
  /// 章节ID（用于上下文提供器）
  final String? chapterId;
  
  /// 场景ID（用于上下文提供器）
  final String? sceneId;
  
  /// 设定生成会话ID（用于设定编排/写作编排场景）
  final String? settingSessionId;
  
  /// 模型配置
  final UserAIModelConfigModel? modelConfig;
  
  /// 主要提示内容（用户输入的消息或待处理的文本）
  final String? prompt;
  
  /// 指令内容（AI执行任务的具体指导）
  final String? instructions;
  
  /// 选中的文本（扩写、缩写、重构时使用）
  final String? selectedText;
  
  /// 上下文选择数据
  final ContextSelectionData? contextSelections;
  
  /// 是否启用智能上下文（RAG检索）
  final bool enableSmartContext;
  
  /// 请求参数（温度、最大token等）
  final Map<String, dynamic> parameters;
  
  /// 元数据（其他附加信息）
  final Map<String, dynamic> metadata;

  /// 复制方法
  UniversalAIRequest copyWith({
    AIRequestType? requestType,
    String? userId,
    String? sessionId,
    String? novelId,
    String? chapterId,
    String? sceneId,
    String? settingSessionId,
    UserAIModelConfigModel? modelConfig,
    String? prompt,
    String? instructions,
    String? selectedText,
    ContextSelectionData? contextSelections,
    bool? enableSmartContext,
    Map<String, dynamic>? parameters,
    Map<String, dynamic>? metadata,
  }) {
    return UniversalAIRequest(
      requestType: requestType ?? this.requestType,
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      novelId: novelId ?? this.novelId,
      chapterId: chapterId ?? this.chapterId,
      sceneId: sceneId ?? this.sceneId,
      settingSessionId: settingSessionId ?? this.settingSessionId,
      modelConfig: modelConfig ?? this.modelConfig,
      prompt: prompt ?? this.prompt,
      instructions: instructions ?? this.instructions,
      selectedText: selectedText ?? this.selectedText,
      contextSelections: contextSelections ?? this.contextSelections,
      enableSmartContext: enableSmartContext ?? this.enableSmartContext,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 转换为API请求的JSON格式
  Map<String, dynamic> toApiJson() {
    final Map<String, dynamic> json = {
      'requestType': requestType.value,
      'userId': userId,
      'enableSmartContext': enableSmartContext,
    };

    // 添加可选字段
    if (sessionId != null) json['sessionId'] = sessionId;
    if (novelId != null) json['novelId'] = novelId;
    if (chapterId != null) json['chapterId'] = chapterId;
    if (sceneId != null) json['sceneId'] = sceneId;
    if (settingSessionId != null) json['settingSessionId'] = settingSessionId;
    if (prompt != null) json['prompt'] = prompt;
    if (instructions != null) json['instructions'] = instructions;
    if (selectedText != null) json['selectedText'] = selectedText;

    // 模型配置
    if (modelConfig != null) {
      // ✅ 仅以模型选择器的ID为准，后端只根据此字段选择模型
      json['modelConfigId'] = modelConfig!.id;

      // 可选标志（不用于后端选择，仅用于统计/日志）
      final bool isPublic = metadata['isPublicModel'] == true;
      json['isPublicModel'] = isPublic;
      if (isPublic) {
        if (metadata.containsKey('publicModelConfigId') && metadata['publicModelConfigId'] != null) {
          json['publicModelConfigId'] = metadata['publicModelConfigId'];
        }
        if (metadata.containsKey('publicModelId') && metadata['publicModelId'] != null) {
          json['publicModelId'] = metadata['publicModelId'];
        }
      }
    }

    // 上下文选择
    if (contextSelections != null && contextSelections!.selectedCount > 0) {
      final contextList = contextSelections!.selectedItems.values
          .map((item) => {
                'id': item.id,
                'title': item.title,
                'type': item.type.value, // 🚀 修复：使用API值而不是displayName
                'metadata': item.metadata,
              })
          .toList();
      json['contextSelections'] = contextList;
      
      // 🚀 添加调试日志
      //print('🔧 [UniversalAIRequest.toApiJson] 添加上下文选择: ${contextList.length}个项目');
      // for (var item in contextList) {
      //   print('  - ${item['type']}:${item['id']} (${item['title']})');
      // }
    } else {
      //print('🔧 [UniversalAIRequest.toApiJson] 没有上下文选择数据');
    }

    // 请求参数
    json['parameters'] = {
      'temperature': parameters['temperature'] ?? 0.7,
      'maxTokens': parameters['maxTokens'] ?? 2000,
      'enableSmartContext': enableSmartContext, // 🚀 确保enableSmartContext也在parameters中
      ...parameters,
    };

    // 元数据
    if (metadata.isNotEmpty) {
      json['metadata'] = metadata;
    }

    return json;
  }

  /// 从JSON创建请求对象
  factory UniversalAIRequest.fromJson(Map<String, dynamic> json) {
    // 🚀 处理contextSelections字段
    ContextSelectionData? contextSelections;
    if (json['contextSelections'] != null) {
      final contextList = json['contextSelections'] as List<dynamic>;
      //print('🔧 [UniversalAIRequest.fromJson] 解析contextSelections: ${contextList.length}个项目');
      
      // 🚀 新增：检查是否需要过滤预设模板上下文
      final isPresetTemplate = json['metadata']?['isPresetTemplate'] == true || 
                               json['source'] == 'preset_template' ||
                               contextList.any((item) => item['metadata']?['isHardcoded'] == true);
      
      if (isPresetTemplate) {
        //print('🔧 [UniversalAIRequest.fromJson] 检测到预设模板，启用上下文过滤');
      }
      
      // 将已选择的项目转换为ContextSelectionItem，并标记为已选择
      final selectedItems = <String, ContextSelectionItem>{};
      final availableItems = <ContextSelectionItem>[];
      final flatItems = <String, ContextSelectionItem>{};
      
      for (var itemData in contextList) {
        final contextType = itemData['type'] as String?;
        
        // 🚀 预设模板上下文过滤：只保留硬编码的上下文类型
        if (isPresetTemplate && !_isHardcodedContextType(contextType)) {
          //print('  🚫 过滤掉非硬编码上下文: $contextType');
          continue;
        }
        
        final item = ContextSelectionItem(
          id: itemData['id'] ?? '',
          title: itemData['title'] ?? '',
          type: ContextSelectionType.values.firstWhere(
            (type) => type.value == itemData['type'],
            orElse: () => ContextSelectionType.fullNovelText,
          ),
          metadata: Map<String, dynamic>.from(itemData['metadata'] ?? {}),
          parentId: itemData['parentId'],
          selectionState: SelectionState.fullySelected, // 标记为已选择
        );
        
        selectedItems[item.id] = item;
        availableItems.add(item);
        flatItems[item.id] = item;
        
        //print('  ✅ ${item.type.displayName}:${item.id} (${item.title})');
      }
      
      // 创建ContextSelectionData，包含选择状态
      contextSelections = ContextSelectionData(
        novelId: json['novelId'] ?? '',
        selectedItems: selectedItems,
        availableItems: availableItems,
        flatItems: flatItems,
      );
      
      if (isPresetTemplate) {
        //print('🔧 [UniversalAIRequest.fromJson] 预设模板上下文过滤完成: ${contextSelections.selectedCount}个硬编码项目');
      } else {
        //print('🔧 [UniversalAIRequest.fromJson] 创建ContextSelectionData: ${contextSelections.selectedCount}个已选择项目');
      }
    }

    // 🚀 智能获取enableSmartContext：优先从顶级字段获取，回退到parameters中获取
    final Map<String, dynamic> parameters = Map<String, dynamic>.from(json['parameters'] ?? {});
    bool enableSmartContext = json['enableSmartContext'] ?? 
                             parameters['enableSmartContext'] ?? 
                             false;

    return UniversalAIRequest(
      requestType: AIRequestType.values.firstWhere(
        (type) => type.value == json['requestType'],
        orElse: () => AIRequestType.chat,
      ),
      userId: json['userId'] ?? '',
      sessionId: json['sessionId'],
      novelId: json['novelId'],
      chapterId: json['chapterId'],
      sceneId: json['sceneId'],
      settingSessionId: json['settingSessionId'],
      prompt: json['prompt'],
      instructions: json['instructions'],
      selectedText: json['selectedText'],
      contextSelections: contextSelections,
      enableSmartContext: enableSmartContext,
      parameters: parameters,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  /// 🚀 新增：判断是否为硬编码的预设模板上下文类型
  static bool _isHardcodedContextType(String? contextType) {
    if (contextType == null) return false;
    
    // 定义预设模板允许的硬编码上下文类型
    const hardcodedTypes = {
      // 核心文本上下文
      'full_novel_text',        // 全文文本
      'full_outline',           // 完整大纲
      'novel_basic_info',       // 基本信息
      
      // 前五章相关
      'recent_chapters_content', // 前五章内容
      'recent_chapters_summary', // 前五章摘要
      
      // 结构化上下文
      'settings',               // 设定
      'snippets',               // 片段
      
      // 当前上下文
      'chapters',               // 章节（当前章节）
      'scenes',                 // 场景（当前场景）
      
      // 世界观相关
      'setting_groups',         // 设定组
      'codex_entries',          // 词条
    };
    
    return hardcodedTypes.contains(contextType);
  }
}

/// AI响应模型
class UniversalAIResponse {
  const UniversalAIResponse({
    required this.id,
    required this.requestType,
    required this.content,
    this.finishReason,
    this.tokenUsage,
    this.model,
    this.createdAt,
    this.metadata = const {},
  });

  /// 响应ID
  final String id;
  
  /// 对应的请求类型
  final AIRequestType requestType;
  
  /// 生成的内容
  final String content;
  
  /// 完成原因
  final String? finishReason;
  
  /// Token使用情况
  final TokenUsage? tokenUsage;
  
  /// 使用的模型
  final String? model;
  
  /// 创建时间
  final DateTime? createdAt;
  
  /// 元数据
  final Map<String, dynamic> metadata;

  /// 从JSON创建响应对象
  factory UniversalAIResponse.fromJson(Map<String, dynamic> json) {
    return UniversalAIResponse(
      id: json['id'] ?? '',
      requestType: AIRequestType.values.firstWhere(
        (type) => type.value == json['requestType'],
        orElse: () => AIRequestType.chat,
      ),
      content: json['content'] ?? '',
      finishReason: json['finishReason'],
      tokenUsage: json['tokenUsage'] != null 
          ? TokenUsage.fromJson(json['tokenUsage'])
          : null,
      model: json['model'],
      createdAt: json['createdAt'] != null
          ? parseBackendDateTime(json['createdAt'])
          : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requestType': requestType.value,
      'content': content,
      'finishReason': finishReason,
      'tokenUsage': tokenUsage?.toJson(),
      'model': model,
      'createdAt': createdAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Token使用情况
class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  /// 从JSON创建Token使用情况
  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      promptTokens: json['promptTokens'] ?? 0,
      completionTokens: json['completionTokens'] ?? 0,
      totalTokens: json['totalTokens'] ?? 0,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'totalTokens': totalTokens,
    };
  }
}

/// 通用AI预览响应模型
class UniversalAIPreviewResponse {
  const UniversalAIPreviewResponse({
    required this.preview,
    required this.systemPrompt,
    required this.userPrompt,
    this.context,
    this.estimatedTokens,
    this.modelName,
    this.modelProvider,
    this.modelConfigId,
  });

  /// 预览内容（完整的提示词）
  final String preview;
  
  /// 系统提示词
  final String systemPrompt;
  
  /// 用户提示词
  final String userPrompt;
  
  /// 上下文信息
  final String? context;
  
  /// 估计的Token数量
  final int? estimatedTokens;
  
  /// 将要使用的模型名称
  final String? modelName;
  
  /// 将要使用的模型提供商
  final String? modelProvider;
  
  /// 模型配置ID
  final String? modelConfigId;

  /// 从JSON创建预览响应
  factory UniversalAIPreviewResponse.fromJson(Map<String, dynamic> json) {
    return UniversalAIPreviewResponse(
      preview: json['preview'] ?? '',
      systemPrompt: json['systemPrompt'] ?? '',
      userPrompt: json['userPrompt'] ?? '',
      context: json['context'],
      estimatedTokens: json['estimatedTokens'],
      modelName: json['modelName'],
      modelProvider: json['modelProvider'],
      modelConfigId: json['modelConfigId'],
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'preview': preview,
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'context': context,
      'estimatedTokens': estimatedTokens,
      'modelName': modelName,
      'modelProvider': modelProvider,
      'modelConfigId': modelConfigId,
    };
  }
  
  /// 计算系统提示词的字数
  int get systemPromptWordCount => _countWords(systemPrompt);
  
  /// 计算用户提示词的字数
  int get userPromptWordCount => _countWords(userPrompt);
  
  /// 计算上下文的字数
  int get contextWordCount => context != null ? _countWords(context!) : 0;
  
  /// 计算总字数
  int get totalWordCount => systemPromptWordCount + userPromptWordCount + contextWordCount;
  
  /// 计算字数的辅助方法
  static int _countWords(String text) {
    if (text.isEmpty) return 0;
    
    // 简单的字数计算：按空格分割英文单词，中文字符直接计数
    int wordCount = 0;
    int chineseCharCount = 0;
    
    // 分割文本按空格
    final words = text.split(RegExp(r'\s+'));
    
    for (String word in words) {
      if (word.trim().isEmpty) continue;
      
      // 计算中文字符
      for (int i = 0; i < word.length; i++) {
        final charCode = word.codeUnitAt(i);
        if (charCode >= 0x4e00 && charCode <= 0x9fff) {
          chineseCharCount++;
        }
      }
      
      // 移除中文字符后计算英文单词
      final nonChineseWord = word.replaceAll(RegExp(r'[\u4e00-\u9fff]'), '');
      if (nonChineseWord.trim().isNotEmpty) {
        wordCount++;
      }
    }
    
    // 中文字符每个算一个词，英文单词按原数量
    return wordCount + chineseCharCount;
  }
}

/// 扩展上下文选择类型枚举，添加value字段用于API传输
extension ContextSelectionTypeApi on ContextSelectionType {
  String get value {
    switch (this) {
      case ContextSelectionType.fullNovelText:
        return 'full_novel_text';
      case ContextSelectionType.fullOutline:
        return 'full_outline';
      case ContextSelectionType.novelBasicInfo:
        return 'novel_basic_info';
      case ContextSelectionType.recentChaptersContent:
        return 'recent_chapters_content';
      case ContextSelectionType.recentChaptersSummary:
        return 'recent_chapters_summary';
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
      case ContextSelectionType.contentFixedGroup:
      case ContextSelectionType.summaryFixedGroup:
        return 'group';
      case ContextSelectionType.acts:
        return 'acts';
      case ContextSelectionType.chapters:
        return 'chapters';
      case ContextSelectionType.scenes:
        return 'scenes';
      case ContextSelectionType.snippets:
        return 'snippets';
      case ContextSelectionType.settings:
        return 'settings';
      case ContextSelectionType.settingGroups:
        return 'setting_groups';
      case ContextSelectionType.settingsByType:
        return 'settings_by_type';
      case ContextSelectionType.codexEntries:
        return 'codex_entries';
      case ContextSelectionType.entriesByType:
        return 'entries_by_type';
      case ContextSelectionType.entriesByDetail:
        return 'entries_by_detail';
      case ContextSelectionType.entriesByCategory:
        return 'entries_by_category';
      case ContextSelectionType.entriesByTag:
        return 'entries_by_tag';
    }
  }
}

/// 🚀 积分预估响应模型
class CostEstimationResponse {
  const CostEstimationResponse({
    required this.estimatedCost,
    required this.success,
    this.errorMessage,
    this.estimatedInputTokens,
    this.estimatedOutputTokens,
    this.costMultiplier,
    this.modelName,
    this.modelProvider,
    this.isPublicModel = false,
    this.featureType,
  });

  /// 预估的积分成本
  final int estimatedCost;
  
  /// 是否成功
  final bool success;
  
  /// 错误信息
  final String? errorMessage;
  
  /// 预估输入Token数量
  final int? estimatedInputTokens;
  
  /// 预估输出Token数量
  final int? estimatedOutputTokens;
  
  /// 成本倍率
  final double? costMultiplier;
  
  /// 模型名称
  final String? modelName;
  
  /// 模型提供商
  final String? modelProvider;
  
  /// 是否为公共模型
  final bool isPublicModel;
  
  /// 功能类型
  final String? featureType;

  /// 从JSON创建积分预估响应
  factory CostEstimationResponse.fromJson(Map<String, dynamic> json) {
    return CostEstimationResponse(
      estimatedCost: json['estimatedCost']?.toInt() ?? 0,
      success: json['success'] ?? false,
      errorMessage: json['errorMessage'],
      estimatedInputTokens: json['estimatedInputTokens']?.toInt(),
      estimatedOutputTokens: json['estimatedOutputTokens']?.toInt(),
      costMultiplier: json['costMultiplier']?.toDouble(),
      modelName: json['modelName'],
      modelProvider: json['modelProvider'],
      isPublicModel: json['isPublicModel'] ?? false,
      featureType: json['featureType'],
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'estimatedCost': estimatedCost,
      'success': success,
      'errorMessage': errorMessage,
      'estimatedInputTokens': estimatedInputTokens,
      'estimatedOutputTokens': estimatedOutputTokens,
      'costMultiplier': costMultiplier,
      'modelName': modelName,
      'modelProvider': modelProvider,
      'isPublicModel': isPublicModel,
      'featureType': featureType,
    };
  }
} 