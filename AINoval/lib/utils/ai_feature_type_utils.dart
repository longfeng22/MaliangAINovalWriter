import '../models/prompt_models.dart';

/// AIFeatureType工具类
/// 提供功能类型的中文名称、图标、描述等辅助功能
class AIFeatureTypeUtils {
  /// 获取功能类型的中文名称
  static String getChineseName(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.sceneToSummary:
        return '场景生成摘要';
      case AIFeatureType.summaryToScene:
        return '摘要生成场景';
      case AIFeatureType.textExpansion:
        return '文本扩写';
      case AIFeatureType.textRefactor:
        return '文本重构';
      case AIFeatureType.textSummary:
        return '文本缩写';
      case AIFeatureType.aiChat:
        return 'AI聊天';
      case AIFeatureType.novelGeneration:
        return '小说生成';
      case AIFeatureType.professionalFictionContinuation:
        return '专业续写';
      case AIFeatureType.sceneBeatGeneration:
        return '场景节拍';
      case AIFeatureType.novelCompose:
        return '小说编排';
      case AIFeatureType.settingTreeGeneration:
        return '设定树生成';
      case AIFeatureType.settingGenerationTool:
        return '设定生成工具';
      case AIFeatureType.storyPlotContinuation:
        return '剧情续写';
      case AIFeatureType.knowledgeExtractionSetting:
        return '设定提取';
      case AIFeatureType.knowledgeExtractionOutline:
        return '大纲生成';
    }
  }

  /// 获取功能类型的简短名称（用于tab显示）
  static String getShortName(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.sceneToSummary:
        return '场景摘要';
      case AIFeatureType.summaryToScene:
        return '摘要场景';
      case AIFeatureType.textExpansion:
        return '扩写';
      case AIFeatureType.textRefactor:
        return '重构';
      case AIFeatureType.textSummary:
        return '缩写';
      case AIFeatureType.aiChat:
        return '聊天';
      case AIFeatureType.novelGeneration:
        return '生成';
      case AIFeatureType.professionalFictionContinuation:
        return '续写';
      case AIFeatureType.sceneBeatGeneration:
        return '节拍';
      case AIFeatureType.novelCompose:
        return '编排';
      case AIFeatureType.settingTreeGeneration:
        return '设定';
      case AIFeatureType.settingGenerationTool:
        return '工具';
      case AIFeatureType.storyPlotContinuation:
        return '剧情';
      case AIFeatureType.knowledgeExtractionSetting:
        return '提取';
      case AIFeatureType.knowledgeExtractionOutline:
        return '大纲';
    }
  }

  /// 获取功能类型的详细描述
  static String getDescription(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.sceneToSummary:
        return '将场景内容生成简洁的摘要';
      case AIFeatureType.summaryToScene:
        return '根据摘要扩展成完整场景';
      case AIFeatureType.textExpansion:
        return '扩充文本内容，增加细节描写';
      case AIFeatureType.textRefactor:
        return '重构文本结构和表达方式';
      case AIFeatureType.textSummary:
        return '压缩文本，提取核心内容';
      case AIFeatureType.aiChat:
        return '智能对话助手';
      case AIFeatureType.novelGeneration:
        return '生成小说内容';
      case AIFeatureType.professionalFictionContinuation:
        return '专业的小说续写功能';
      case AIFeatureType.sceneBeatGeneration:
        return '生成场景节拍规划';
      case AIFeatureType.novelCompose:
        return '小说章节和大纲编排';
      case AIFeatureType.settingTreeGeneration:
        return 'AI辅助生成结构化小说设定';
      case AIFeatureType.settingGenerationTool:
        return '设定生成工具调用';
      case AIFeatureType.storyPlotContinuation:
        return '智能故事剧情续写';
      case AIFeatureType.knowledgeExtractionSetting:
        return '从知识库提取设定信息';
      case AIFeatureType.knowledgeExtractionOutline:
        return '从知识库生成章节大纲';
    }
  }

  /// 获取功能类型的图标（使用Material Icons）
  static String getIconName(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.sceneToSummary:
        return 'summarize';
      case AIFeatureType.summaryToScene:
        return 'expand_more';
      case AIFeatureType.textExpansion:
        return 'expand';
      case AIFeatureType.textRefactor:
        return 'auto_fix_high';
      case AIFeatureType.textSummary:
        return 'compress';
      case AIFeatureType.aiChat:
        return 'chat';
      case AIFeatureType.novelGeneration:
        return 'auto_stories';
      case AIFeatureType.professionalFictionContinuation:
        return 'edit_note';
      case AIFeatureType.sceneBeatGeneration:
        return 'music_note';
      case AIFeatureType.novelCompose:
        return 'library_books';
      case AIFeatureType.settingTreeGeneration:
        return 'account_tree';
      case AIFeatureType.settingGenerationTool:
        return 'build';
      case AIFeatureType.storyPlotContinuation:
        return 'timeline';
      case AIFeatureType.knowledgeExtractionSetting:
        return 'category';
      case AIFeatureType.knowledgeExtractionOutline:
        return 'format_list_numbered';
    }
  }

  /// 获取功能类型的颜色（返回颜色值）
  static int getColor(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.sceneToSummary:
        return 0xFF4CAF50; // Green
      case AIFeatureType.summaryToScene:
        return 0xFF8BC34A; // Light Green
      case AIFeatureType.textExpansion:
        return 0xFF2196F3; // Blue
      case AIFeatureType.textRefactor:
        return 0xFF03A9F4; // Light Blue
      case AIFeatureType.textSummary:
        return 0xFF00BCD4; // Cyan
      case AIFeatureType.aiChat:
        return 0xFF9C27B0; // Purple
      case AIFeatureType.novelGeneration:
        return 0xFFE91E63; // Pink
      case AIFeatureType.professionalFictionContinuation:
        return 0xFFF44336; // Red
      case AIFeatureType.sceneBeatGeneration:
        return 0xFFFF9800; // Orange
      case AIFeatureType.novelCompose:
        return 0xFFFF5722; // Deep Orange
      case AIFeatureType.settingTreeGeneration:
        return 0xFF795548; // Brown
      case AIFeatureType.settingGenerationTool:
        return 0xFF607D8B; // Blue Grey
      case AIFeatureType.storyPlotContinuation:
        return 0xFF673AB7; // Deep Purple
      case AIFeatureType.knowledgeExtractionSetting:
        return 0xFF3F51B5; // Indigo
      case AIFeatureType.knowledgeExtractionOutline:
        return 0xFF009688; // Teal
    }
  }

  /// 获取所有可用于提示词市场的功能类型
  /// 排除内部工具类型
  static List<AIFeatureType> getMarketAvailableTypes() {
    return AIFeatureType.values.where((type) {
      // 排除内部工具类型
      return type != AIFeatureType.settingGenerationTool;
    }).toList();
  }

  /// 获取功能类型的优先级排序
  /// 数字越小优先级越高
  static int getPriority(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.settingTreeGeneration:
        return 1; // 最高优先级
      case AIFeatureType.professionalFictionContinuation:
        return 2;
      case AIFeatureType.novelCompose:
        return 3;
      case AIFeatureType.sceneBeatGeneration:
        return 4;
      case AIFeatureType.storyPlotContinuation:
        return 5;
      case AIFeatureType.textExpansion:
        return 6;
      case AIFeatureType.textRefactor:
        return 7;
      case AIFeatureType.textSummary:
        return 8;
      case AIFeatureType.sceneToSummary:
        return 9;
      case AIFeatureType.summaryToScene:
        return 10;
      case AIFeatureType.aiChat:
        return 11;
      case AIFeatureType.novelGeneration:
        return 12;
      case AIFeatureType.knowledgeExtractionSetting:
        return 13;
      case AIFeatureType.knowledgeExtractionOutline:
        return 14;
      case AIFeatureType.settingGenerationTool:
        return 99; // 最低优先级（不显示）
    }
  }

  /// 对功能类型列表按优先级排序
  static List<AIFeatureType> sortByPriority(List<AIFeatureType> types) {
    final list = List<AIFeatureType>.from(types);
    list.sort((a, b) => getPriority(a).compareTo(getPriority(b)));
    return list;
  }

  /// 获取功能类型的引用积分说明
  /// 需要与后端PromptMarketRewardConfig保持一致
  static String getRewardPointsDescription(AIFeatureType type) {
    final points = getRewardPoints(type);
    if (points == 0) {
      return '不奖励积分';
    } else if (points == 1) {
      return '引用奖励 1 积分';
    } else {
      return '引用奖励 $points 积分';
    }
  }

  /// 获取功能类型的引用积分数值
  /// 需要与后端PromptMarketRewardConfig保持一致
  static int getRewardPoints(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.settingTreeGeneration:
        return 3; // 高价值功能
      case AIFeatureType.professionalFictionContinuation:
        return 3; // 高价值功能
      case AIFeatureType.novelCompose:
        return 2; // 中价值功能
      case AIFeatureType.sceneBeatGeneration:
        return 2; // 中价值功能
      case AIFeatureType.storyPlotContinuation:
        return 2; // 中价值功能
      case AIFeatureType.knowledgeExtractionSetting:
        return 2; // 中价值功能
      case AIFeatureType.knowledgeExtractionOutline:
        return 2; // 中价值功能
      case AIFeatureType.textExpansion:
        return 1; // 基础功能
      case AIFeatureType.textRefactor:
        return 1; // 基础功能
      case AIFeatureType.textSummary:
        return 1; // 基础功能
      case AIFeatureType.sceneToSummary:
        return 1; // 基础功能
      case AIFeatureType.summaryToScene:
        return 1; // 基础功能
      case AIFeatureType.aiChat:
        return 1; // 基础功能
      case AIFeatureType.novelGeneration:
        return 1; // 基础功能
      case AIFeatureType.settingGenerationTool:
        return 0; // 内部功能，不奖励
    }
  }

  /// 获取积分等级标签
  static String getRewardLevelLabel(AIFeatureType type) {
    final points = getRewardPoints(type);
    if (points >= 3) {
      return '高价值';
    } else if (points >= 2) {
      return '中价值';
    } else if (points >= 1) {
      return '基础';
    } else {
      return '';
    }
  }

  /// 获取积分等级颜色
  static int getRewardLevelColor(AIFeatureType type) {
    final points = getRewardPoints(type);
    if (points >= 3) {
      return 0xFFFF6B6B; // 红色 - 高价值
    } else if (points >= 2) {
      return 0xFFFFBE0B; // 黄色 - 中价值
    } else if (points >= 1) {
      return 0xFF4ECDC4; // 青色 - 基础
    } else {
      return 0xFF95A5A6; // 灰色 - 无积分
    }
  }
}


