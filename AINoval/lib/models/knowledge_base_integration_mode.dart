/// 知识库集成模式
library;

/// 知识库集成模式枚举
enum KnowledgeBaseIntegrationMode {
  /// 无模式 - 不使用知识库
  none('NONE', '无', '不使用知识库，正常生成设定'),
  
  /// 复用知识库设定 - 直接复制知识库中的设定
  reuse('REUSE', '复用知识库设定', '直接复用知识库中某本小说的设定，无需AI生成'),
  
  /// 设定仿写 - 使用知识库设定作为参考，让AI仿写
  imitation('IMITATION', '设定仿写', '使用知识库一个或多个小说的设定作为参考，让AI仿写生成新设定'),
  
  /// 混合模式 - 复用某些设定，同时生成新设定
  hybrid('HYBRID', '混合模式', '复用某个知识库小说的部分设定，同时让AI参考其他设定生成新内容');

  const KnowledgeBaseIntegrationMode(this.value, this.displayName, this.description);
  
  final String value;
  final String displayName;
  final String description;
  
  static KnowledgeBaseIntegrationMode fromValue(String value) {
    return KnowledgeBaseIntegrationMode.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => KnowledgeBaseIntegrationMode.none,
    );
  }
}

/// 知识库设定分类
enum KnowledgeBaseSettingCategory {
  narrativeStyle('NARRATIVE_STYLE', '叙事方式'),
  writingStyle('WRITING_STYLE', '文风'),
  wordUsage('WORD_USAGE', '用词特点'),
  coreConflict('CORE_CONFLICT', '核心冲突'),
  suspenseDesign('SUSPENSE_DESIGN', '悬念设计'),
  storyPacing('STORY_PACING', '故事节奏'),
  characterBuilding('CHARACTER_BUILDING', '人物塑造'),
  worldview('WORLDVIEW', '世界观'),
  goldenFinger('GOLDEN_FINGER', '金手指'),
  resonance('RESONANCE', '共鸣'),
  pleasurePoint('PLEASURE_POINT', '爽点'),
  excitementPoint('EXCITEMENT_POINT', '嗨点'),
  hotMemes('HOT_MEMES', '热梗'),
  funnyPoints('FUNNY_POINTS', '搞笑点'),
  custom('CUSTOM', '用户自定义'),
  chapterOutline('CHAPTER_OUTLINE', '章节大纲');

  const KnowledgeBaseSettingCategory(this.value, this.displayName);
  
  final String value;
  final String displayName;
  
  static KnowledgeBaseSettingCategory fromValue(String value) {
    return KnowledgeBaseSettingCategory.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => KnowledgeBaseSettingCategory.custom,
    );
  }
  
  /// 获取所有非自定义分类
  static List<KnowledgeBaseSettingCategory> getAllNonCustomCategories() {
    return KnowledgeBaseSettingCategory.values
        .where((c) => c != KnowledgeBaseSettingCategory.custom && c != KnowledgeBaseSettingCategory.chapterOutline)
        .toList();
  }
}

/// 选中的知识库小说项
class SelectedKnowledgeBaseItem {
  final String knowledgeBaseId;
  final String novelTitle;
  final List<KnowledgeBaseSettingCategory> selectedCategories;
  
  const SelectedKnowledgeBaseItem({
    required this.knowledgeBaseId,
    required this.novelTitle,
    required this.selectedCategories,
  });
  
  SelectedKnowledgeBaseItem copyWith({
    String? knowledgeBaseId,
    String? novelTitle,
    List<KnowledgeBaseSettingCategory>? selectedCategories,
  }) {
    return SelectedKnowledgeBaseItem(
      knowledgeBaseId: knowledgeBaseId ?? this.knowledgeBaseId,
      novelTitle: novelTitle ?? this.novelTitle,
      selectedCategories: selectedCategories ?? this.selectedCategories,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'knowledgeBaseId': knowledgeBaseId,
      'novelTitle': novelTitle,
      'selectedCategories': selectedCategories.map((c) => c.value).toList(),
    };
  }
  
  factory SelectedKnowledgeBaseItem.fromJson(Map<String, dynamic> json) {
    return SelectedKnowledgeBaseItem(
      knowledgeBaseId: json['knowledgeBaseId'] as String,
      novelTitle: json['novelTitle'] as String,
      selectedCategories: (json['selectedCategories'] as List<dynamic>)
          .map((c) => KnowledgeBaseSettingCategory.fromValue(c as String))
          .toList(),
    );
  }
}

/// 知识库集成配置
class KnowledgeBaseIntegrationConfig {
  final KnowledgeBaseIntegrationMode mode;
  final List<SelectedKnowledgeBaseItem> selectedItems;
  
  const KnowledgeBaseIntegrationConfig({
    this.mode = KnowledgeBaseIntegrationMode.none,
    this.selectedItems = const [],
  });
  
  KnowledgeBaseIntegrationConfig copyWith({
    KnowledgeBaseIntegrationMode? mode,
    List<SelectedKnowledgeBaseItem>? selectedItems,
  }) {
    return KnowledgeBaseIntegrationConfig(
      mode: mode ?? this.mode,
      selectedItems: selectedItems ?? this.selectedItems,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.value,
      'selectedItems': selectedItems.map((item) => item.toJson()).toList(),
    };
  }
  
  factory KnowledgeBaseIntegrationConfig.fromJson(Map<String, dynamic> json) {
    return KnowledgeBaseIntegrationConfig(
      mode: KnowledgeBaseIntegrationMode.fromValue(json['mode'] as String? ?? 'NONE'),
      selectedItems: (json['selectedItems'] as List<dynamic>?)
          ?.map((item) => SelectedKnowledgeBaseItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? const [],
    );
  }
}


