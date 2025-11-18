import '../utils/date_time_parser.dart';


/// AI功能类型枚举
enum AIFeatureType {
  /// 场景生成摘要
  sceneToSummary,
  
  /// 摘要生成场景
  summaryToScene,
  
  /// 文本扩写功能
  textExpansion,
  
  /// 文本重构功能
  textRefactor,
  
  /// 文本缩写功能
  textSummary,
  
  /// AI聊天对话功能
  aiChat,
  
  /// 小说内容生成功能
  novelGeneration,
  
  /// 专业续写小说功能
  professionalFictionContinuation,
  
  /// 场景节拍生成功能
  sceneBeatGeneration,
  
  /// 写作编排（大纲/章节/组合）
  novelCompose,
  
  /// 设定树生成功能
  settingTreeGeneration,
  
  /// 设定生成工具调用阶段
  settingGenerationTool,
  
  /// 故事剧情续写（总结当前剧情并生成下一个大纲）
  storyPlotContinuation,
  
  /// 知识库拆书 - 设定提取
  knowledgeExtractionSetting,
  
  /// 知识库拆书 - 章节大纲生成
  knowledgeExtractionOutline
}

/// 提示词类型枚举
enum PromptType {
  /// 摘要提示词
  summary,
  
  /// 风格提示词
  style
}

/// 提示词优化风格
enum OptimizationStyle {
  /// 专业风格
  professional,
  
  /// 创意风格
  creative,
  
  /// 简洁风格
  concise
}

/// 提示词模板类型
enum TemplateType {
  /// 公共模板
  public,
  
  /// 私有模板
  private
}

/// 提示词项
class PromptItem {
  final String id;
  final String title;
  final String content;
  final PromptType type;
  
  PromptItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
  });
  
  factory PromptItem.fromJson(Map<String, dynamic> json) {
    return PromptItem(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      type: PromptType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => PromptType.summary,
      ),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type.toString().split('.').last,
    };
  }
}

/// 提示词数据模型
class PromptData {
  /// 用户自定义提示词
  final String userPrompt;
  
  /// 系统默认提示词
  final String defaultPrompt;
  
  /// 是否为用户自定义
  final bool isCustomized;
  
  /// 提示词项列表
  final List<PromptItem> promptItems;

  PromptData({
    required this.userPrompt,
    required this.defaultPrompt,
    required this.isCustomized,
    this.promptItems = const [],
  });
  
  /// 获取当前生效的提示词（如果自定义则返回用户提示词，否则返回默认提示词）
  String get activePrompt => isCustomized ? userPrompt : defaultPrompt;
  
  /// 获取摘要类型的提示词列表
  List<PromptItem> get summaryPrompts => 
      promptItems.where((item) => item.type == PromptType.summary).toList();
      
  /// 获取风格类型的提示词列表
  List<PromptItem> get stylePrompts => 
      promptItems.where((item) => item.type == PromptType.style).toList();
}

/// 提示词模板模型
class PromptTemplate {
  /// 模板ID
  final String id;
  
  /// 模板名称
  final String name;
  
  /// 模板内容
  final String content;
  
  /// 功能类型
  final AIFeatureType featureType;
  
  /// 是否为公共模板
  final bool isPublic;
  
  /// 作者ID（公共模板可为null或系统ID）
  final String? authorId;
  
  /// 源模板ID（如果是从公共模板复制的）
  final String? sourceTemplateId;
  
  /// 是否为官方验证模板
  final bool isVerified;
  
  /// 用户是否收藏（仅对私有模板有效）
  final bool isFavorite;
  
  /// 是否为默认模板
  final bool isDefault;
  
  /// 创建时间
  final DateTime createdAt;
  
  /// 更新时间
  final DateTime updatedAt;
  
  /// 模板描述
  final String? description;
  
  /// 模板标签
  final List<String>? templateTags;
  
  /// 作者名称
  final String? authorName;
  
  /// 使用次数
  final int? useCount;
  
  /// 平均评分
  final double? averageRating;
  
  /// 评分次数
  final int? ratingCount;
  
  /// AI功能类型（别名，保持向后兼容）
  AIFeatureType? get aiFeatureType => featureType;

  PromptTemplate({
    required this.id,
    required this.name,
    required this.content,
    required this.featureType,
    required this.isPublic,
    this.authorId,
    this.sourceTemplateId,
    this.isVerified = false,
    this.isFavorite = false,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.templateTags,
    this.authorName,
    this.useCount,
    this.averageRating,
    this.ratingCount,
  });
  
  /// 创建私有模板
  factory PromptTemplate.createPrivate({
    required String id,
    required String name,
    required String content,
    required AIFeatureType featureType,
    required String authorId,
    String? sourceTemplateId,
    bool isFavorite = false,
  }) {
    final now = DateTime.now();
    return PromptTemplate(
      id: id,
      name: name,
      content: content,
      featureType: featureType,
      isPublic: false,
      authorId: authorId,
      sourceTemplateId: sourceTemplateId,
      isVerified: false,
      isFavorite: isFavorite,
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      description: null,
      templateTags: null,
      authorName: null,
      useCount: 0,
      averageRating: null,
      ratingCount: 0,
    );
  }
  
  /// 从公共模板复制创建私有模板
  factory PromptTemplate.copyFromPublic({
    required PromptTemplate publicTemplate,
    required String newId,
    required String authorId,
    String? newName,
  }) {
    final now = DateTime.now();
    return PromptTemplate(
      id: newId,
      name: newName ?? '${publicTemplate.name} (复制)',
      content: publicTemplate.content,
      featureType: publicTemplate.featureType,
      isPublic: false,
      authorId: authorId,
      sourceTemplateId: publicTemplate.id,
      isVerified: false,
      isFavorite: false,
      isDefault: false,
      createdAt: now,
      updatedAt: now,
      description: null,
      templateTags: null,
      authorName: null,
      useCount: 0,
      averageRating: null,
      ratingCount: 0,
    );
  }
  
  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      featureType: _parseFeatureType(json['featureType']),
      isPublic: json['isPublic'] as bool? ?? false,
      authorId: (json['authorId'])?.toString(),
      sourceTemplateId: (json['sourceTemplateId'])?.toString(),
      isVerified: json['isVerified'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: parseBackendDateTime(json['createdAt']),
      updatedAt: parseBackendDateTime(json['updatedAt']),
      description: json['description']?.toString(),
      templateTags: (json['templateTags'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      authorName: json['authorName']?.toString(),
      useCount: (json['useCount'] as num?)?.toInt(),
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      ratingCount: (json['ratingCount'] as num?)?.toInt(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'featureType': _featureTypeToString(featureType),
      'isPublic': isPublic,
      'authorId': authorId,
      'sourceTemplateId': sourceTemplateId,
      'isVerified': isVerified,
      'isFavorite': isFavorite,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'description': description,
      'templateTags': templateTags,
      'authorName': authorName,
      'useCount': useCount,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
    };
  }
  
  /// 克隆并更新模板
  PromptTemplate copyWith({
    String? id,
    String? name,
    String? content,
    AIFeatureType? featureType,
    bool? isPublic,
    String? authorId,
    String? sourceTemplateId,
    bool? isVerified,
    bool? isFavorite,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    List<String>? templateTags,
    String? authorName,
    int? useCount,
    double? averageRating,
    int? ratingCount,
  }) {
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      featureType: featureType ?? this.featureType,
      isPublic: isPublic ?? this.isPublic,
      authorId: authorId ?? this.authorId,
      sourceTemplateId: sourceTemplateId ?? this.sourceTemplateId,
      isVerified: isVerified ?? this.isVerified,
      isFavorite: isFavorite ?? this.isFavorite,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      templateTags: templateTags ?? this.templateTags,
      authorName: authorName ?? this.authorName,
      useCount: useCount ?? this.useCount,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
    );
  }
  
  /// 标记为收藏
  PromptTemplate toggleFavorite() {
    return copyWith(isFavorite: !isFavorite, updatedAt: DateTime.now());
  }
  
  /// 判断模板是否可编辑（只有私有模板可编辑）
  bool get isEditable => !isPublic;
  
  /// 从字符串解析功能类型
  static AIFeatureType _parseFeatureType(dynamic featureTypeValue) {
    final featureTypeStr = featureTypeValue?.toString() ?? '';
    switch (featureTypeStr) {
      case 'SCENE_TO_SUMMARY':
        return AIFeatureType.sceneToSummary;
      case 'SUMMARY_TO_SCENE':
        return AIFeatureType.summaryToScene;
      case 'TEXT_EXPANSION':
        return AIFeatureType.textExpansion;
      case 'TEXT_REFACTOR':
        return AIFeatureType.textRefactor;
      case 'TEXT_SUMMARY':
        return AIFeatureType.textSummary;
      case 'AI_CHAT':
        return AIFeatureType.aiChat;
      case 'NOVEL_GENERATION':
        return AIFeatureType.novelGeneration;
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return AIFeatureType.professionalFictionContinuation;
      case 'SCENE_BEAT_GENERATION':
        return AIFeatureType.sceneBeatGeneration;
      case 'NOVEL_COMPOSE':
        return AIFeatureType.novelCompose;
      case 'SETTING_TREE_GENERATION':
        return AIFeatureType.settingTreeGeneration;
      case 'STORY_PLOT_CONTINUATION':
        return AIFeatureType.storyPlotContinuation;
      default:
        // 尝试直接匹配枚举的名称
        try {
          return AIFeatureType.values.firstWhere(
            (t) => t.toString().split('.').last.toUpperCase() == featureTypeStr.toUpperCase(),
          );
        } catch (_) {
          return AIFeatureType.textExpansion; // 默认值
        }
    }
  }
  
  /// 将功能类型转换为字符串
  static String _featureTypeToString(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return 'SCENE_TO_SUMMARY';
      case AIFeatureType.summaryToScene:
        return 'SUMMARY_TO_SCENE';
      case AIFeatureType.textExpansion:
        return 'TEXT_EXPANSION';
      case AIFeatureType.textRefactor:
        return 'TEXT_REFACTOR';
      case AIFeatureType.textSummary:
        return 'TEXT_SUMMARY';
      case AIFeatureType.aiChat:
        return 'AI_CHAT';
      case AIFeatureType.novelGeneration:
        return 'NOVEL_GENERATION';
      case AIFeatureType.professionalFictionContinuation:
        return 'PROFESSIONAL_FICTION_CONTINUATION';
      case AIFeatureType.sceneBeatGeneration:
        return 'SCENE_BEAT_GENERATION';
      case AIFeatureType.novelCompose:
        return 'NOVEL_COMPOSE';
      case AIFeatureType.settingTreeGeneration:
        return 'SETTING_TREE_GENERATION';
      case AIFeatureType.settingGenerationTool:
        return 'SETTING_GENERATION_TOOL';
      case AIFeatureType.storyPlotContinuation:
        return 'STORY_PLOT_CONTINUATION';
      case AIFeatureType.knowledgeExtractionSetting:
        return 'KNOWLEDGE_EXTRACTION_SETTING';
      case AIFeatureType.knowledgeExtractionOutline:
        return 'KNOWLEDGE_EXTRACTION_OUTLINE';
    }
  }
}

/// 用户提示词模板DTO
class UserPromptTemplateDto {
  /// 功能类型
  final AIFeatureType featureType;
  
  /// 提示词文本
  final String promptText;

  UserPromptTemplateDto({
    required this.featureType,
    required this.promptText,
  });

  factory UserPromptTemplateDto.fromJson(Map<String, dynamic> json) {
    String featureTypeStr = json['featureType'] as String;
    AIFeatureType type;
    
    // 根据字符串解析枚举
    switch (featureTypeStr) {
      case 'SCENE_TO_SUMMARY':
        type = AIFeatureType.sceneToSummary;
        break;
      case 'SUMMARY_TO_SCENE':
        type = AIFeatureType.summaryToScene;
        break;
      case 'TEXT_EXPANSION':
        type = AIFeatureType.textExpansion;
        break;
      case 'TEXT_REFACTOR':
        type = AIFeatureType.textRefactor;
        break;
      case 'TEXT_SUMMARY':
        type = AIFeatureType.textSummary;
        break;
      case 'AI_CHAT':
        type = AIFeatureType.aiChat;
        break;
      case 'NOVEL_GENERATION':
        type = AIFeatureType.novelGeneration;
        break;
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        type = AIFeatureType.professionalFictionContinuation;
        break;
      case 'SCENE_BEAT_GENERATION':
        type = AIFeatureType.sceneBeatGeneration;
        break;
      case 'NOVEL_COMPOSE':
        type = AIFeatureType.novelCompose;
        break;
      case 'SETTING_TREE_GENERATION':
        type = AIFeatureType.settingTreeGeneration;
        break;
      case 'SETTING_GENERATION_TOOL':
        type = AIFeatureType.settingGenerationTool;
        break;
      case 'STORY_PLOT_CONTINUATION':
        type = AIFeatureType.storyPlotContinuation;
        break;
      case 'KNOWLEDGE_EXTRACTION_SETTING':
        type = AIFeatureType.knowledgeExtractionSetting;
        break;
      case 'KNOWLEDGE_EXTRACTION_OUTLINE':
        type = AIFeatureType.knowledgeExtractionOutline;
        break;
      default:
        // 尝试直接匹配枚举的名称
        try {
          type = AIFeatureType.values.firstWhere(
            (t) => t.toString().split('.').last.toUpperCase() == featureTypeStr.toUpperCase()
          );
        } catch (e) {
          throw ArgumentError('未知的功能类型: $featureTypeStr');
        }
    }
    
    return UserPromptTemplateDto(
      featureType: type,
      promptText: json['promptText'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    String featureTypeStr;
    
    // 将枚举转换为字符串
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        featureTypeStr = 'SCENE_TO_SUMMARY';
        break;
      case AIFeatureType.summaryToScene:
        featureTypeStr = 'SUMMARY_TO_SCENE';
        break;
      case AIFeatureType.textExpansion:
        featureTypeStr = 'TEXT_EXPANSION';
        break;
      case AIFeatureType.textRefactor:
        featureTypeStr = 'TEXT_REFACTOR';
        break;
      case AIFeatureType.textSummary:
        featureTypeStr = 'TEXT_SUMMARY';
        break;
      case AIFeatureType.aiChat:
        featureTypeStr = 'AI_CHAT';
        break;
      case AIFeatureType.novelGeneration:
        featureTypeStr = 'NOVEL_GENERATION';
        break;
      case AIFeatureType.professionalFictionContinuation:
        featureTypeStr = 'PROFESSIONAL_FICTION_CONTINUATION';
        break;
      case AIFeatureType.sceneBeatGeneration:
        featureTypeStr = 'SCENE_BEAT_GENERATION';
        break;
      case AIFeatureType.novelCompose:
        featureTypeStr = 'NOVEL_COMPOSE';
        break;
      case AIFeatureType.settingTreeGeneration:
        featureTypeStr = 'SETTING_TREE_GENERATION';
        break;
      case AIFeatureType.settingGenerationTool:
        featureTypeStr = 'SETTING_GENERATION_TOOL';
        break;
      case AIFeatureType.storyPlotContinuation:
        featureTypeStr = 'STORY_PLOT_CONTINUATION';
        break;
      case AIFeatureType.knowledgeExtractionSetting:
        featureTypeStr = 'KNOWLEDGE_EXTRACTION_SETTING';
        break;
      case AIFeatureType.knowledgeExtractionOutline:
        featureTypeStr = 'KNOWLEDGE_EXTRACTION_OUTLINE';
        break;
    }
    
    return {
      'featureType': featureTypeStr,
      'promptText': promptText,
    };
  }
}

/// 更新提示词请求DTO
class UpdatePromptRequest {
  /// 提示词文本
  final String promptText;

  UpdatePromptRequest({
    required this.promptText,
  });

  factory UpdatePromptRequest.fromJson(Map<String, dynamic> json) {
    return UpdatePromptRequest(
      promptText: json['promptText'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'promptText': promptText,
    };
  }
}

/// 优化提示词请求
class OptimizePromptRequest {
  final String content;
  final OptimizationStyle style;
  final double preserveRatio; // 0.0-1.0 保留原文比例
  
  OptimizePromptRequest({
    required this.content,
    required this.style,
    this.preserveRatio = 0.5,
  });
  
  factory OptimizePromptRequest.fromJson(Map<String, dynamic> json) {
    return OptimizePromptRequest(
      content: json['content'] as String,
      style: _parseOptimizationStyle(json['style'] as String),
      preserveRatio: json['preserveRatio'] as double? ?? 0.5,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'style': _optimizationStyleToString(style),
      'preserveRatio': preserveRatio,
    };
  }
}

/// 解析优化风格
OptimizationStyle _parseOptimizationStyle(String value) {
  return OptimizationStyle.values.firstWhere(
    (e) => e.toString().split('.').last == value,
    orElse: () => OptimizationStyle.professional,
  );
}

/// 优化风格转字符串
String _optimizationStyleToString(OptimizationStyle style) {
  return style.toString().split('.').last;
}

/// 优化区块
class OptimizationSection {
  final String title;
  final String content;
  final String? original;
  final String type;
  
  OptimizationSection({
    required this.title,
    required this.content,
    this.original,
    required this.type,
  });
  
  /// 是否为未更改的区块
  bool get isUnchanged => type == 'unchanged';
  
  /// 是否为修改过的区块
  bool get isModified => type == 'modified';
  
  factory OptimizationSection.fromJson(Map<String, dynamic> json) {
    return OptimizationSection(
      title: json['title'] as String,
      content: json['content'] as String,
      original: json['original'] as String?,
      type: json['type'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'original': original,
      'type': type,
    };
  }
}

/// 优化统计数据
class OptimizationStatistics {
  final int originalTokens;
  final int optimizedTokens;
  final int originalLength;
  final int optimizedLength;
  final double efficiency;
  
  // 兼容旧版API的属性
  int get originalWordCount => originalLength;
  int get optimizedWordCount => optimizedLength;
  double get changeRatio => efficiency;
  
  OptimizationStatistics({
    required this.originalTokens,
    required this.optimizedTokens,
    required this.originalLength,
    required this.optimizedLength,
    required this.efficiency,
  });
  
  factory OptimizationStatistics.fromJson(Map<String, dynamic> json) {
    return OptimizationStatistics(
      originalTokens: json['originalTokens'] as int,
      optimizedTokens: json['optimizedTokens'] as int,
      originalLength: json['originalLength'] as int,
      optimizedLength: json['optimizedLength'] as int,
      efficiency: json['efficiency'] as double,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'originalTokens': originalTokens,
      'optimizedTokens': optimizedTokens,
      'originalLength': originalLength,
      'optimizedLength': optimizedLength,
      'efficiency': efficiency,
    };
  }
}

/// 优化结果
class OptimizationResult {
  final String optimizedContent;
  final List<OptimizationSection> sections;
  final OptimizationStatistics statistics;
  
  OptimizationResult({
    required this.optimizedContent,
    required this.sections,
    required this.statistics,
  });
  
  factory OptimizationResult.fromJson(Map<String, dynamic> json) {
    return OptimizationResult(
      optimizedContent: json['optimizedContent'] as String,
      sections: (json['sections'] as List)
          .map((e) => OptimizationSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      statistics: OptimizationStatistics.fromJson(
          json['statistics'] as Map<String, dynamic>),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'optimizedContent': optimizedContent,
      'sections': sections.map((e) => e.toJson()).toList(),
      'statistics': statistics.toJson(),
    };
  }
}

// 字符串构建器类
class StringBuilder {
  final StringBuffer _buffer = StringBuffer();
  
  void append(String str) {
    _buffer.write(str);
  }
  
  void appendLine(String str) {
    _buffer.writeln(str);
  }
  
  @override
  String toString() {
    return _buffer.toString();
  }
  
  void clear() {
    _buffer.clear();
  }
  
  int get length => _buffer.length;
  
  bool get isEmpty => _buffer.isEmpty;
  
  bool get isNotEmpty => _buffer.isNotEmpty;
}

// ====================== 统一提示词聚合相关模型 ======================

/// 系统提示词信息
class SystemPromptInfo {
  final String defaultSystemPrompt;
  final String defaultUserPrompt;
  final String? userCustomSystemPrompt;
  final bool hasUserCustom;

  const SystemPromptInfo({
    required this.defaultSystemPrompt,
    required this.defaultUserPrompt,
    this.userCustomSystemPrompt,
    required this.hasUserCustom,
  });

  /// 获取生效的系统提示词
  String get effectivePrompt => hasUserCustom && userCustomSystemPrompt != null 
      ? userCustomSystemPrompt! 
      : defaultSystemPrompt;

  factory SystemPromptInfo.fromJson(Map<String, dynamic> json) {
    return SystemPromptInfo(
      defaultSystemPrompt: json['defaultSystemPrompt'] as String? ?? '',
      defaultUserPrompt: json['defaultUserPrompt'] as String? ?? '请在此处输入您的具体需求和内容...',
      userCustomSystemPrompt: json['userCustomSystemPrompt'] as String?,
      hasUserCustom: json['hasUserCustom'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultSystemPrompt': defaultSystemPrompt,
      'defaultUserPrompt': defaultUserPrompt,
      'userCustomSystemPrompt': userCustomSystemPrompt,
      'hasUserCustom': hasUserCustom,
    };
  }
}

/// 用户提示词信息
class UserPromptInfo {
  final String id;
  final String name;
  final String? description;
  final AIFeatureType featureType;
  final String? systemPrompt;
  final String userPrompt;
  final List<String> tags;
  final List<String> categories;
  final bool isFavorite;
  final bool isDefault;
  final bool isPublic;
  final String? shareCode;
  final bool isVerified;
  final int usageCount;
  final int favoriteCount;
  final double rating;
  final String? authorId;
  final int? version;
  final String? language;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime updatedAt;
  final String? reviewStatus; // 审核状态: DRAFT, PENDING, APPROVED, REJECTED
  final bool hidePrompts; // 🆕 是否隐藏提示词（隐私保护）
  final SettingGenerationConfig? settingGenerationConfig; // 🆕 设定生成配置（仅SETTING_TREE_GENERATION类型使用）

  const UserPromptInfo({
    required this.id,
    required this.name,
    this.description,
    required this.featureType,
    this.systemPrompt,
    required this.userPrompt,
    this.tags = const [],
    this.categories = const [],
    this.isFavorite = false,
    this.isDefault = false,
    this.isPublic = false,
    this.shareCode,
    this.isVerified = false,
    this.usageCount = 0,
    this.favoriteCount = 0,
    this.rating = 0.0,
    this.authorId,
    this.version = 1,
    this.language = 'zh',
    required this.createdAt,
    this.lastUsedAt,
    required this.updatedAt,
    this.reviewStatus,
    this.hidePrompts = false, // 🆕 默认不隐藏
    this.settingGenerationConfig, // 🆕 设定生成配置
  });

  factory UserPromptInfo.fromJson(Map<String, dynamic> json) {
    return UserPromptInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      featureType: PromptTemplate._parseFeatureType(json['featureType'] as String),
      systemPrompt: json['systemPrompt'] as String?,
      userPrompt: json['userPrompt'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      categories: (json['categories'] as List<dynamic>?)?.cast<String>() ?? [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDefault: (json['isDefault'] ??
                  json['is_default'] ??
                  json['default'] ??
                  json['isDefaultTemplate']) as bool? ?? false,
      isPublic: json['isPublic'] as bool? ?? false,
      shareCode: json['shareCode'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      favoriteCount: (json['favoriteCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      authorId: json['authorId'] as String?,
      version: (json['version'] as num?)?.toInt(),
      language: json['language'] as String?,
      createdAt: json['createdAt'] != null 
          ? parseBackendDateTime(json['createdAt'])
          : DateTime.now(), // 提供默认值
      lastUsedAt: json['lastUsedAt'] != null 
          ? parseBackendDateTime(json['lastUsedAt'])
          : null,
      updatedAt: json['updatedAt'] != null 
          ? parseBackendDateTime(json['updatedAt'])
          : DateTime.now(), // 提供默认值
      reviewStatus: json['reviewStatus'] as String?,
      hidePrompts: json['hidePrompts'] as bool? ?? false, // 🆕 解析hidePrompts字段
      settingGenerationConfig: json['settingGenerationConfig'] != null
          ? SettingGenerationConfig.fromJson(json['settingGenerationConfig'] as Map<String, dynamic>)
          : null, // 🆕 解析设定生成配置
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'tags': tags,
      'categories': categories,
      'isFavorite': isFavorite,
      'isDefault': isDefault,
      'isPublic': isPublic,
      'shareCode': shareCode,
      'isVerified': isVerified,
      'usageCount': usageCount,
      'favoriteCount': favoriteCount,
      'rating': rating,
      'authorId': authorId,
      'version': version,
      'language': language,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'reviewStatus': reviewStatus,
      'hidePrompts': hidePrompts,
      'settingGenerationConfig': settingGenerationConfig?.toJson(),
    };
  }

  /// 复制对象并修改指定字段
  UserPromptInfo copyWith({
    String? id,
    String? name,
    String? description,
    AIFeatureType? featureType,
    String? systemPrompt,
    String? userPrompt,
    List<String>? tags,
    List<String>? categories,
    bool? isFavorite,
    bool? isDefault,
    bool? isPublic,
    String? shareCode,
    bool? isVerified,
    int? usageCount,
    int? favoriteCount,
    double? rating,
    String? authorId,
    int? version,
    String? language,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? updatedAt,
    String? reviewStatus,
    bool? hidePrompts, // 🆕 添加hidePrompts参数
    SettingGenerationConfig? settingGenerationConfig, // 🆕 添加settingGenerationConfig参数
  }) {
    return UserPromptInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      featureType: featureType ?? this.featureType,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPrompt: userPrompt ?? this.userPrompt,
      tags: tags ?? this.tags,
      categories: categories ?? this.categories,
      isFavorite: isFavorite ?? this.isFavorite,
      isDefault: isDefault ?? this.isDefault,
      isPublic: isPublic ?? this.isPublic,
      shareCode: shareCode ?? this.shareCode,
      isVerified: isVerified ?? this.isVerified,
      usageCount: usageCount ?? this.usageCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      rating: rating ?? this.rating,
      authorId: authorId ?? this.authorId,
      version: version ?? this.version,
      language: language ?? this.language,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      hidePrompts: hidePrompts ?? this.hidePrompts, // 🆕 支持hidePrompts字段
      settingGenerationConfig: settingGenerationConfig ?? this.settingGenerationConfig, // 🆕 支持settingGenerationConfig字段
    );
  }
}

/// 公开提示词信息
class PublicPromptInfo {
  final String id;
  final String name;
  final String? description;
  final String? authorName;
  final AIFeatureType featureType;
  final String systemPrompt;
  final String userPrompt;
  final List<String> tags;
  final List<String> categories;
  final double? rating;
  final int usageCount;
  final int favoriteCount;
  final String? shareCode;
  final bool isVerified;
  final String? language;
  final int? version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final bool hidePrompts; // 🆕 是否隐藏提示词（隐私保护）
  final SettingGenerationConfig? settingGenerationConfig; // 🆕 设定生成配置（仅SETTING_TREE_GENERATION类型使用）

  const PublicPromptInfo({
    required this.id,
    required this.name,
    this.description,
    this.authorName,
    required this.featureType,
    required this.systemPrompt,
    required this.userPrompt,
    this.tags = const [],
    this.categories = const [],
    this.rating,
    this.usageCount = 0,
    this.favoriteCount = 0,
    this.shareCode,
    this.isVerified = false,
    this.language,
    this.version,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.hidePrompts = false, // 🆕 是否隐藏提示词
    this.settingGenerationConfig, // 🆕 设定生成配置
  });

  factory PublicPromptInfo.fromJson(Map<String, dynamic> json) {
    return PublicPromptInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      authorName: json['authorName'] as String?,
      featureType: PromptTemplate._parseFeatureType(json['featureType'] as String),
      systemPrompt: json['systemPrompt'] as String? ?? '',
      userPrompt: json['userPrompt'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      categories: (json['categories'] as List<dynamic>?)?.cast<String>() ?? [],
      rating: (json['rating'] as num?)?.toDouble(),
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      favoriteCount: (json['favoriteCount'] as num?)?.toInt() ?? 0,
      shareCode: json['shareCode'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      language: json['language'] as String?,
      version: (json['version'] as num?)?.toInt(),
      createdAt: json['createdAt'] != null 
          ? parseBackendDateTime(json['createdAt'])
          : DateTime.now(), // 提供默认值
      updatedAt: json['updatedAt'] != null 
          ? parseBackendDateTime(json['updatedAt'])
          : DateTime.now(), // 提供默认值
      lastUsedAt: json['lastUsedAt'] != null 
          ? parseBackendDateTime(json['lastUsedAt'])
          : null,
      hidePrompts: json['hidePrompts'] as bool? ?? false, // 🆕 解析hidePrompts字段
      settingGenerationConfig: json['settingGenerationConfig'] != null
          ? SettingGenerationConfig.fromJson(json['settingGenerationConfig'] as Map<String, dynamic>)
          : null, // 🆕 解析设定生成配置
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'authorName': authorName,
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'tags': tags,
      'categories': categories,
      'rating': rating,
      'usageCount': usageCount,
      'favoriteCount': favoriteCount,
      'shareCode': shareCode,
      'isVerified': isVerified,
      'language': language,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'hidePrompts': hidePrompts, // 🆕 序列化hidePrompts字段
      'settingGenerationConfig': settingGenerationConfig?.toJson(), // 🆕 序列化设定生成配置
    };
  }
}

/// 最近使用的提示词信息
class RecentPromptInfo {
  final String id;
  final String name;
  final String? description;
  final AIFeatureType featureType;
  final List<String> tags;
  final bool isDefault;
  final bool isFavorite;
  final double rating;
  final DateTime lastUsedAt;
  final int usageCount;

  const RecentPromptInfo({
    required this.id,
    required this.name,
    this.description,
    required this.featureType,
    this.tags = const [],
    this.isDefault = false,
    this.isFavorite = false,
    this.rating = 0.0,
    required this.lastUsedAt,
    this.usageCount = 0,
  });

  factory RecentPromptInfo.fromJson(Map<String, dynamic> json) {
    return RecentPromptInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      featureType: PromptTemplate._parseFeatureType(json['featureType'] as String),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      isDefault: json['isDefault'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      lastUsedAt: json['lastUsedAt'] != null 
          ? parseBackendDateTime(json['lastUsedAt'])
          : DateTime.now(), // 提供默认值
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'tags': tags,
      'isDefault': isDefault,
      'isFavorite': isFavorite,
      'rating': rating,
      'lastUsedAt': lastUsedAt.toIso8601String(),
      'usageCount': usageCount,
    };
  }
}

/// 完整的提示词包
class PromptPackage {
  final AIFeatureType featureType;
  final SystemPromptInfo systemPrompt;
  final List<UserPromptInfo> userPrompts;
  final List<PublicPromptInfo> publicPrompts;
  final List<RecentPromptInfo> recentlyUsed;
  final Set<String> supportedPlaceholders;
  final Map<String, String> placeholderDescriptions;
  final DateTime lastUpdated;

  const PromptPackage({
    required this.featureType,
    required this.systemPrompt,
    this.userPrompts = const [],
    this.publicPrompts = const [],
    this.recentlyUsed = const [],
    this.supportedPlaceholders = const {},
    this.placeholderDescriptions = const {},
    required this.lastUpdated,
  });

  factory PromptPackage.fromJson(Map<String, dynamic> json) {
    return PromptPackage(
      featureType: PromptTemplate._parseFeatureType(json['featureType'] as String),
      systemPrompt: SystemPromptInfo.fromJson(json['systemPrompt'] as Map<String, dynamic>),
      userPrompts: (json['userPrompts'] as List<dynamic>?)
          ?.map((e) => UserPromptInfo.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      publicPrompts: (json['publicPrompts'] as List<dynamic>?)
          ?.map((e) => PublicPromptInfo.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      recentlyUsed: (json['recentlyUsed'] as List<dynamic>?)
          ?.map((e) => RecentPromptInfo.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      supportedPlaceholders: (json['supportedPlaceholders'] as List<dynamic>?)
          ?.cast<String>().toSet() ?? {},
      placeholderDescriptions: (json['placeholderDescriptions'] as Map<String, dynamic>?)
          ?.cast<String, String>() ?? {},
      lastUpdated: json['lastUpdated'] != null 
          ? parseBackendDateTime(json['lastUpdated'])
          : DateTime.now(), // 提供默认值
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'systemPrompt': systemPrompt.toJson(),
      'userPrompts': userPrompts.map((e) => e.toJson()).toList(),
      'publicPrompts': publicPrompts.map((e) => e.toJson()).toList(),
      'recentlyUsed': recentlyUsed.map((e) => e.toJson()).toList(),
      'supportedPlaceholders': supportedPlaceholders.toList(),
      'placeholderDescriptions': placeholderDescriptions,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

/// 用户提示词概览
class UserPromptOverview {
  final String userId;
  final Map<AIFeatureType, int> promptCountsByFeature;
  final List<RecentPromptInfo> globalRecentlyUsed;
  final List<UserPromptInfo> favoritePrompts;
  final Set<String> allTags;
  final int totalUsageCount;
  final DateTime? lastActiveAt;

  const UserPromptOverview({
    required this.userId,
    this.promptCountsByFeature = const {},
    this.globalRecentlyUsed = const [],
    this.favoritePrompts = const [],
    this.allTags = const {},
    this.totalUsageCount = 0,
    this.lastActiveAt,
  });

  factory UserPromptOverview.fromJson(Map<String, dynamic> json) {
    final promptCountsJson = json['promptCountsByFeature'] as Map<String, dynamic>?;
    final promptCountsByFeature = <AIFeatureType, int>{};
    
    if (promptCountsJson != null) {
      for (final entry in promptCountsJson.entries) {
        try {
          final featureType = PromptTemplate._parseFeatureType(entry.key);
          promptCountsByFeature[featureType] = (entry.value as num).toInt();
        } catch (e) {
          // 忽略无法解析的功能类型
        }
      }
    }

    return UserPromptOverview(
      userId: json['userId'] as String,
      promptCountsByFeature: promptCountsByFeature,
      globalRecentlyUsed: (json['globalRecentlyUsed'] as List<dynamic>?)
          ?.map((e) => RecentPromptInfo.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      favoritePrompts: (json['favoritePrompts'] as List<dynamic>?)
          ?.map((e) => UserPromptInfo.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      allTags: (json['allTags'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      totalUsageCount: (json['totalUsageCount'] as num?)?.toInt() ?? 0,
      lastActiveAt: json['lastActiveAt'] != null 
          ? parseBackendDateTime(json['lastActiveAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final promptCountsJson = <String, int>{};
    for (final entry in promptCountsByFeature.entries) {
      promptCountsJson[PromptTemplate._featureTypeToString(entry.key)] = entry.value;
    }

    return {
      'userId': userId,
      'promptCountsByFeature': promptCountsJson,
      'globalRecentlyUsed': globalRecentlyUsed.map((e) => e.toJson()).toList(),
      'favoritePrompts': favoritePrompts.map((e) => e.toJson()).toList(),
      'allTags': allTags.toList(),
      'totalUsageCount': totalUsageCount,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
    };
  }
}

/// 缓存预热结果
class CacheWarmupResult {
  final bool success;
  final int duration; // 毫秒
  final int warmedFeatures;
  final int warmedPrompts;
  final String? errorMessage;

  const CacheWarmupResult({
    required this.success,
    this.duration = 0,
    this.warmedFeatures = 0,
    this.warmedPrompts = 0,
    this.errorMessage,
  });

  factory CacheWarmupResult.fromJson(Map<String, dynamic> json) {
    return CacheWarmupResult(
      success: json['success'] as bool? ?? false,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      warmedFeatures: (json['warmedFeatures'] as num?)?.toInt() ?? 0,
      warmedPrompts: (json['warmedPrompts'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'duration': duration,
      'warmedFeatures': warmedFeatures,
      'warmedPrompts': warmedPrompts,
      'errorMessage': errorMessage,
    };
  }
}

/// 聚合缓存统计
class AggregationCacheStats {
  final Map<String, int> cacheHitCounts;
  final Map<String, int> cacheMissCounts;
  final Map<String, double> cacheHitRates;
  final int totalCacheSize;
  final DateTime? lastClearTime;

  const AggregationCacheStats({
    this.cacheHitCounts = const {},
    this.cacheMissCounts = const {},
    this.cacheHitRates = const {},
    this.totalCacheSize = 0,
    this.lastClearTime,
  });

  factory AggregationCacheStats.fromJson(Map<String, dynamic> json) {
    return AggregationCacheStats(
      cacheHitCounts: (json['cacheHitCounts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
      cacheMissCounts: (json['cacheMissCounts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
      cacheHitRates: (json['cacheHitRates'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
      totalCacheSize: (json['totalCacheSize'] as num?)?.toInt() ?? 0,
      lastClearTime: json['lastClearTime'] != null 
          ? parseBackendDateTime(json['lastClearTime'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cacheHitCounts': cacheHitCounts,
      'cacheMissCounts': cacheMissCounts,
      'cacheHitRates': cacheHitRates,
      'totalCacheSize': totalCacheSize,
      'lastClearTime': lastClearTime?.toIso8601String(),
    };
  }
}

/// 占位符性能统计
class PlaceholderPerformanceStats {
  final int totalResolveCount;
  final int parallelResolveCount;
  final double averageResolveTime; // 毫秒
  final Map<String, int> placeholderUsageCounts;
  final Map<String, double> placeholderResolveTimes;

  const PlaceholderPerformanceStats({
    this.totalResolveCount = 0,
    this.parallelResolveCount = 0,
    this.averageResolveTime = 0.0,
    this.placeholderUsageCounts = const {},
    this.placeholderResolveTimes = const {},
  });

  factory PlaceholderPerformanceStats.fromJson(Map<String, dynamic> json) {
    return PlaceholderPerformanceStats(
      totalResolveCount: (json['totalResolveCount'] as num?)?.toInt() ?? 0,
      parallelResolveCount: (json['parallelResolveCount'] as num?)?.toInt() ?? 0,
      averageResolveTime: (json['averageResolveTime'] as num?)?.toDouble() ?? 0.0,
      placeholderUsageCounts: (json['placeholderUsageCounts'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
      placeholderResolveTimes: (json['placeholderResolveTimes'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalResolveCount': totalResolveCount,
      'parallelResolveCount': parallelResolveCount,
      'averageResolveTime': averageResolveTime,
      'placeholderUsageCounts': placeholderUsageCounts,
      'placeholderResolveTimes': placeholderResolveTimes,
    };
  }
}

/// 系统健康状态
class SystemHealthStatus {
  final String status;
  final int timestamp;
  final String service;
  final String version;

  const SystemHealthStatus({
    required this.status,
    required this.timestamp,
    required this.service,
    required this.version,
  });

  /// 检查系统是否健康
  bool get isHealthy => status.toLowerCase() == 'up';

  factory SystemHealthStatus.fromJson(Map<String, dynamic> json) {
    return SystemHealthStatus(
      status: json['status'] as String? ?? 'UNKNOWN',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      service: json['service'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp,
      'service': service,
      'version': version,
    };
  }
}

// ====================== 增强用户提示词模板相关模型 ======================

/// 增强用户提示词模板
class EnhancedUserPromptTemplate {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final AIFeatureType featureType;
  final String systemPrompt;
  final String userPrompt;
  final List<String> tags;
  final List<String> categories;
  final bool isPublic;
  final String? shareCode;
  final bool isFavorite;
  final bool isDefault;
  final int usageCount;
  final double rating;
  final int ratingCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final bool isVerified;
  final String? authorId;
  final int? version;
  final String? language;
  final int? favoriteCount;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? reviewComment;
  final String? reviewStatus; // 🆕 审核状态: DRAFT, PENDING, APPROVED, REJECTED
  final bool hidePrompts; // 🆕 是否隐藏提示词（隐私保护）
  final SettingGenerationConfig? settingGenerationConfig; // 🆕 设定生成配置（仅SETTING_TREE_GENERATION类型使用）

  const EnhancedUserPromptTemplate({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.featureType,
    required this.systemPrompt,
    required this.userPrompt,
    this.tags = const [],
    this.categories = const [],
    this.isPublic = false,
    this.shareCode,
    this.isFavorite = false,
    this.isDefault = false,
    this.usageCount = 0,
    this.rating = 0.0,
    this.ratingCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.isVerified = false,
    this.authorId,
    this.version,
    this.language,
    this.favoriteCount,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewComment,
    this.reviewStatus, // 🆕 审核状态
    this.hidePrompts = false, // 🆕 是否隐藏提示词
    this.settingGenerationConfig, // 🆕 设定生成配置
  });

  factory EnhancedUserPromptTemplate.fromJson(Map<String, dynamic> json) {
    return EnhancedUserPromptTemplate(
      id: (json['id'] ?? '') as String,
      userId: (json['userId'] as String?) ?? (json['authorId'] as String?) ?? '',
      name: json['name'] as String,
      description: json['description'] as String?,
      featureType: PromptTemplate._parseFeatureType(json['featureType'] as String? ?? 'TEXT_EXPANSION'),
      systemPrompt: json['systemPrompt'] as String? ?? '',
      userPrompt: json['userPrompt'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      categories: (json['categories'] as List<dynamic>?)?.cast<String>() ?? [],
      isPublic: json['isPublic'] as bool? ?? false,
      shareCode: json['shareCode'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDefault: (json['isDefault'] ??
                  json['is_default'] ??
                  json['default'] ??
                  json['isDefaultTemplate']) as bool? ?? false,
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null 
          ? parseBackendDateTime(json['createdAt'])
          : DateTime.now(), // 提供默认值
      updatedAt: json['updatedAt'] != null 
          ? parseBackendDateTime(json['updatedAt'])
          : DateTime.now(), // 提供默认值
      lastUsedAt: json['lastUsedAt'] != null 
          ? parseBackendDateTime(json['lastUsedAt'])
          : null,
      isVerified: json['isVerified'] as bool? ?? false,
      authorId: json['authorId'] as String?,
      version: (json['version'] as num?)?.toInt(),
      language: json['language'] as String?,
      favoriteCount: (json['favoriteCount'] as num?)?.toInt(),
      reviewedAt: json['reviewedAt'] != null 
          ? parseBackendDateTime(json['reviewedAt'])
          : null,
      reviewedBy: json['reviewedBy'] as String?,
      reviewComment: json['reviewComment'] as String?,
      reviewStatus: json['reviewStatus'] as String?, // 🆕 解析reviewStatus字段
      hidePrompts: json['hidePrompts'] as bool? ?? false, // 🆕 解析hidePrompts字段
      settingGenerationConfig: json['settingGenerationConfig'] != null
          ? SettingGenerationConfig.fromJson(json['settingGenerationConfig'] as Map<String, dynamic>)
          : null, // 🆕 解析设定生成配置
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'description': description,
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'tags': tags,
      'categories': categories,
      'isPublic': isPublic,
      'shareCode': shareCode,
      'isFavorite': isFavorite,
      'isDefault': isDefault,
      'usageCount': usageCount,
      'rating': rating,
      'ratingCount': ratingCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'isVerified': isVerified,
      'authorId': authorId,
      'version': version,
      'language': language,
      'favoriteCount': favoriteCount,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'reviewedBy': reviewedBy,
      'reviewComment': reviewComment,
      'reviewStatus': reviewStatus, // 🆕 序列化reviewStatus字段
      'hidePrompts': hidePrompts, // 🆕 序列化hidePrompts字段
      'settingGenerationConfig': settingGenerationConfig?.toJson(), // 🆕 序列化设定生成配置
    };
  }

  /// 复制模板并修改指定字段
  EnhancedUserPromptTemplate copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    AIFeatureType? featureType,
    String? systemPrompt,
    String? userPrompt,
    List<String>? tags,
    List<String>? categories,
    bool? isPublic,
    String? shareCode,
    bool? isFavorite,
    bool? isDefault,
    int? usageCount,
    double? rating,
    int? ratingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool? isVerified,
    String? authorId,
    int? version,
    String? language,
    int? favoriteCount,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewComment,
    String? reviewStatus, // 🆕 添加reviewStatus参数
    bool? hidePrompts, // 🆕 添加hidePrompts参数
    SettingGenerationConfig? settingGenerationConfig, // 🆕 添加settingGenerationConfig参数
  }) {
    return EnhancedUserPromptTemplate(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      featureType: featureType ?? this.featureType,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPrompt: userPrompt ?? this.userPrompt,
      tags: tags ?? this.tags,
      categories: categories ?? this.categories,
      isPublic: isPublic ?? this.isPublic,
      shareCode: shareCode ?? this.shareCode,
      isFavorite: isFavorite ?? this.isFavorite,
      isDefault: isDefault ?? this.isDefault,
      usageCount: usageCount ?? this.usageCount,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isVerified: isVerified ?? this.isVerified,
      authorId: authorId ?? this.authorId,
      version: version ?? this.version,
      language: language ?? this.language,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewComment: reviewComment ?? this.reviewComment,
      reviewStatus: reviewStatus ?? this.reviewStatus, // 🆕 支持reviewStatus字段
      hidePrompts: hidePrompts ?? this.hidePrompts, // 🆕 支持hidePrompts字段
      settingGenerationConfig: settingGenerationConfig ?? this.settingGenerationConfig, // 🆕 支持settingGenerationConfig字段
    );
  }
}

/// 创建提示词模板请求
class CreatePromptTemplateRequest {
  final String name;
  final String? description;
  final AIFeatureType featureType;
  final String systemPrompt;
  final String userPrompt;
  final List<String> tags;
  final List<String> categories;

  const CreatePromptTemplateRequest({
    required this.name,
    this.description,
    required this.featureType,
    required this.systemPrompt,
    required this.userPrompt,
    this.tags = const [],
    this.categories = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'featureType': PromptTemplate._featureTypeToString(featureType),
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'tags': tags,
      'categories': categories,
    };
  }
}

/// 更新提示词模板请求
class UpdatePromptTemplateRequest {
  final String? name;
  final String? description;
  final String? systemPrompt;
  final String? userPrompt;
  final List<String>? tags;
  final List<String>? categories;

  const UpdatePromptTemplateRequest({
    this.name,
    this.description,
    this.systemPrompt,
    this.userPrompt,
    this.tags,
    this.categories,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    
    if (name != null) json['name'] = name;
    if (description != null) json['description'] = description;
    if (systemPrompt != null) json['systemPrompt'] = systemPrompt;
    if (userPrompt != null) json['userPrompt'] = userPrompt;
    if (tags != null) json['tags'] = tags;
    if (categories != null) json['categories'] = categories;
    
    return json;
  }
}

/// 发布模板请求
class PublishTemplateRequest {
  final String? shareCode;

  const PublishTemplateRequest({this.shareCode});

  Map<String, dynamic> toJson() {
    return {
      'shareCode': shareCode,
    };
  }
}

/// AI功能类型枚举扩展
extension AIFeatureTypeExtension on AIFeatureType {
  /// 转换为API字符串格式
  String toApiString() {
    switch (this) {
      case AIFeatureType.sceneToSummary:
        return 'SCENE_TO_SUMMARY';
      case AIFeatureType.summaryToScene:
        return 'SUMMARY_TO_SCENE';
      case AIFeatureType.textExpansion:
        return 'TEXT_EXPANSION';
      case AIFeatureType.textRefactor:
        return 'TEXT_REFACTOR';
      case AIFeatureType.textSummary:
        return 'TEXT_SUMMARY';
      case AIFeatureType.aiChat:
        return 'AI_CHAT';
      case AIFeatureType.novelGeneration:
        return 'NOVEL_GENERATION';
      case AIFeatureType.professionalFictionContinuation:
        return 'PROFESSIONAL_FICTION_CONTINUATION';
      case AIFeatureType.sceneBeatGeneration:
        return 'SCENE_BEAT_GENERATION';
      case AIFeatureType.novelCompose:
        return 'NOVEL_COMPOSE';
      case AIFeatureType.settingTreeGeneration:
        return 'SETTING_TREE_GENERATION';
      case AIFeatureType.settingGenerationTool:
        return 'SETTING_GENERATION_TOOL';
      case AIFeatureType.storyPlotContinuation:
        return 'STORY_PLOT_CONTINUATION';
      case AIFeatureType.knowledgeExtractionSetting:
        return 'KNOWLEDGE_EXTRACTION_SETTING';
      case AIFeatureType.knowledgeExtractionOutline:
        return 'KNOWLEDGE_EXTRACTION_OUTLINE';
    }
  }

  /// 获取显示名称
  String get displayName {
    switch (this) {
      case AIFeatureType.sceneToSummary:
        return '场景摘要';
      case AIFeatureType.summaryToScene:
        return '摘要扩写';
      case AIFeatureType.textExpansion:
        return '文本扩写';
      case AIFeatureType.textRefactor:
        return '文本重构';
      case AIFeatureType.textSummary:
        return '文本总结';
      case AIFeatureType.aiChat:
        return 'AI聊天';
      case AIFeatureType.novelGeneration:
        return '小说生成';
      case AIFeatureType.professionalFictionContinuation:
        return '专业续写';
      case AIFeatureType.sceneBeatGeneration:
        return '场景节拍生成';
      case AIFeatureType.novelCompose:
        return '设定编排';
      case AIFeatureType.settingTreeGeneration:
        return '设定树生成';
      case AIFeatureType.settingGenerationTool:
        return '设定生成工具调用';
      case AIFeatureType.storyPlotContinuation:
        return '剧情续写';
      case AIFeatureType.knowledgeExtractionSetting:
        return '知识库拆书-设定';
      case AIFeatureType.knowledgeExtractionOutline:
        return '知识库拆书-大纲';
    }
  }

  /// 获取英文显示名称
  String get englishName {
    switch (this) {
      case AIFeatureType.sceneToSummary:
        return 'Scene Beat Completions';
      case AIFeatureType.summaryToScene:
        return 'Summary Expansions';
      case AIFeatureType.textExpansion:
        return 'Text Expansion';
      case AIFeatureType.textRefactor:
        return 'Text Refactor';
      case AIFeatureType.textSummary:
        return 'Text Summary';
      case AIFeatureType.aiChat:
        return 'AI Chat';
      case AIFeatureType.novelGeneration:
        return 'Novel Generation';
      case AIFeatureType.professionalFictionContinuation:
        return 'Professional Fiction Continuation';
      case AIFeatureType.sceneBeatGeneration:
        return 'Scene Beat Generation';
      case AIFeatureType.novelCompose:
        return 'Novel Compose';
      case AIFeatureType.settingTreeGeneration:
        return 'Setting Tree Generation';
      case AIFeatureType.settingGenerationTool:
        return 'Setting Generation Tool';
      case AIFeatureType.storyPlotContinuation:
        return 'Story Plot Continuation';
      case AIFeatureType.knowledgeExtractionSetting:
        return 'Knowledge Extraction Setting';
      case AIFeatureType.knowledgeExtractionOutline:
        return 'Knowledge Extraction Outline';
    }
  }
}

/// AIFeatureType工具类
class AIFeatureTypeHelper {
  /// 从API字符串解析枚举
  static AIFeatureType fromApiString(String apiString) {
    switch (apiString) {
      case 'SCENE_TO_SUMMARY':
        return AIFeatureType.sceneToSummary;
      case 'SUMMARY_TO_SCENE':
        return AIFeatureType.summaryToScene;
      case 'TEXT_EXPANSION':
        return AIFeatureType.textExpansion;
      case 'TEXT_REFACTOR':
        return AIFeatureType.textRefactor;
      case 'TEXT_SUMMARY':
        return AIFeatureType.textSummary;
      case 'AI_CHAT':
        return AIFeatureType.aiChat;
      case 'NOVEL_GENERATION':
        return AIFeatureType.novelGeneration;
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return AIFeatureType.professionalFictionContinuation;
      case 'SCENE_BEAT_GENERATION':
        return AIFeatureType.sceneBeatGeneration;
      case 'NOVEL_COMPOSE':
        return AIFeatureType.novelCompose;
      case 'SETTING_TREE_GENERATION':
        return AIFeatureType.settingTreeGeneration;
      case 'SETTING_GENERATION_TOOL':
        return AIFeatureType.settingGenerationTool;
      case 'STORY_PLOT_CONTINUATION':
        return AIFeatureType.storyPlotContinuation;
      case 'KNOWLEDGE_EXTRACTION_SETTING':
        return AIFeatureType.knowledgeExtractionSetting;
      case 'KNOWLEDGE_EXTRACTION_OUTLINE':
        return AIFeatureType.knowledgeExtractionOutline;
      default:
        // 尝试直接匹配枚举的名称
        try {
          return AIFeatureType.values.firstWhere(
            (t) => t.toString().split('.').last.toUpperCase() == apiString.toUpperCase()
          );
        } catch (e) {
          throw ArgumentError('未知的功能类型: $apiString');
        }
    }
  }

  /// 批量转换枚举列表为字符串列表
  static List<String> toApiStringList(Iterable<AIFeatureType> features) {
    return features.map((f) => f.toApiString()).toList();
  }

  /// 批量从字符串列表解析枚举列表
  static List<AIFeatureType> fromApiStringList(Iterable<String> apiStrings) {
    return apiStrings.map((s) => fromApiString(s)).toList();
  }

  /// 获取所有功能类型
  static List<AIFeatureType> get allFeatures => AIFeatureType.values;

  /// 获取功能类型的API路径格式
  static String toPathString(AIFeatureType featureType) {
    return featureType.toString().split('.').last;
  }
}

// ====================== 设定生成配置相关模型 ======================

/// 设定生成配置
/// 对应后端 SettingGenerationConfig
class SettingGenerationConfig {
  final String? strategyName;
  final String? description;
  final List<NodeTemplateConfig> nodeTemplates;
  final GenerationRules? rules;
  final int expectedRootNodes;
  final int maxDepth;
  final String? version;
  final String? baseStrategyId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int usageCount;
  final bool isSystemStrategy;

  const SettingGenerationConfig({
    this.strategyName,
    this.description,
    this.nodeTemplates = const [],
    this.rules,
    this.expectedRootNodes = -1,
    this.maxDepth = 5,
    this.version,
    this.baseStrategyId,
    this.createdAt,
    this.updatedAt,
    this.usageCount = 0,
    this.isSystemStrategy = false,
  });

  factory SettingGenerationConfig.fromJson(Map<String, dynamic> json) {
    return SettingGenerationConfig(
      strategyName: json['strategyName'] as String?,
      description: json['description'] as String?,
      nodeTemplates: (json['nodeTemplates'] as List<dynamic>?)
          ?.map((e) => NodeTemplateConfig.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      rules: json['rules'] != null
          ? GenerationRules.fromJson(json['rules'] as Map<String, dynamic>)
          : null,
      expectedRootNodes: (json['expectedRootNodes'] as num?)?.toInt() ?? -1,
      maxDepth: (json['maxDepth'] as num?)?.toInt() ?? 5,
      version: json['version'] as String?,
      baseStrategyId: json['baseStrategyId'] as String?,
      createdAt: json['createdAt'] != null
          ? parseBackendDateTime(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? parseBackendDateTime(json['updatedAt'])
          : null,
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      isSystemStrategy: json['isSystemStrategy'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'strategyName': strategyName,
      'description': description,
      'nodeTemplates': nodeTemplates.map((e) => e.toJson()).toList(),
      'rules': rules?.toJson(),
      'expectedRootNodes': expectedRootNodes,
      'maxDepth': maxDepth,
      'version': version,
      'baseStrategyId': baseStrategyId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'usageCount': usageCount,
      'isSystemStrategy': isSystemStrategy,
    };
  }
}

/// 节点模板配置
class NodeTemplateConfig {
  final String nodeType;
  final String? displayName;
  final String? description;
  final int priority;
  final int minCount;
  final int maxCount;
  final List<String> allowedParentTypes;
  final List<String> allowedChildTypes;

  const NodeTemplateConfig({
    required this.nodeType,
    this.displayName,
    this.description,
    this.priority = 0,
    this.minCount = 0,
    this.maxCount = -1,
    this.allowedParentTypes = const [],
    this.allowedChildTypes = const [],
  });

  factory NodeTemplateConfig.fromJson(Map<String, dynamic> json) {
    return NodeTemplateConfig(
      nodeType: json['nodeType'] as String,
      displayName: json['displayName'] as String?,
      description: json['description'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      minCount: (json['minCount'] as num?)?.toInt() ?? 0,
      maxCount: (json['maxCount'] as num?)?.toInt() ?? -1,
      allowedParentTypes: (json['allowedParentTypes'] as List<dynamic>?)?.cast<String>() ?? [],
      allowedChildTypes: (json['allowedChildTypes'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeType': nodeType,
      'displayName': displayName,
      'description': description,
      'priority': priority,
      'minCount': minCount,
      'maxCount': maxCount,
      'allowedParentTypes': allowedParentTypes,
      'allowedChildTypes': allowedChildTypes,
    };
  }
}

/// 生成规则配置
class GenerationRules {
  final int preferredBatchSize;
  final int maxBatchSize;
  final int minDescriptionLength;
  final int maxDescriptionLength;
  final bool requireInterConnections;
  final bool allowDynamicStructure;

  const GenerationRules({
    this.preferredBatchSize = 20,
    this.maxBatchSize = 200,
    this.minDescriptionLength = 50,
    this.maxDescriptionLength = 500,
    this.requireInterConnections = true,
    this.allowDynamicStructure = true,
  });

  factory GenerationRules.fromJson(Map<String, dynamic> json) {
    return GenerationRules(
      preferredBatchSize: (json['preferredBatchSize'] as num?)?.toInt() ?? 20,
      maxBatchSize: (json['maxBatchSize'] as num?)?.toInt() ?? 200,
      minDescriptionLength: (json['minDescriptionLength'] as num?)?.toInt() ?? 50,
      maxDescriptionLength: (json['maxDescriptionLength'] as num?)?.toInt() ?? 500,
      requireInterConnections: json['requireInterConnections'] as bool? ?? true,
      allowDynamicStructure: json['allowDynamicStructure'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'preferredBatchSize': preferredBatchSize,
      'maxBatchSize': maxBatchSize,
      'minDescriptionLength': minDescriptionLength,
      'maxDescriptionLength': maxDescriptionLength,
      'requireInterConnections': requireInterConnections,
      'allowDynamicStructure': allowDynamicStructure,
    };
  }
} 