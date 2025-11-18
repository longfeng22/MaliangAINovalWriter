import 'package:ainoval/models/unified_ai_model.dart';

/// 剧情推演配置模型
class StoryPredictionConfig {
  final List<UnifiedAIModel> selectedModels;
  final String styleInstructions;
  final int generationCount;
  final bool generateSceneContent;
  final String? additionalInstructions;
  final List<String> contextTypes;
  final String? summaryPromptTemplateId; // 剧情续写提示词模板ID（用于总结当前剧情并生成下一个大纲）
  final String? scenePromptTemplateId;

  const StoryPredictionConfig({
    required this.selectedModels,
    required this.styleInstructions,
    required this.generationCount,
    this.generateSceneContent = true,
    this.additionalInstructions,
    this.contextTypes = const ['RECENT_CHAPTERS_SUMMARY', 'RECENT_CHAPTERS_CONTENT', 'ALL_SETTINGS'],
    this.summaryPromptTemplateId,
    this.scenePromptTemplateId,
  });

  Map<String, dynamic> toJson() {
    return {
      'selectedModels': selectedModels.map((model) => {
        'type': model.isPublic ? 'PUBLIC' : 'PRIVATE',
        'configId': model.id,
        'displayName': model.displayName,
        'provider': model.provider,
      }).toList(),
      'styleInstructions': styleInstructions,
      'generationCount': generationCount,
      'generateSceneContent': generateSceneContent,
      'additionalInstructions': additionalInstructions,
      'contextTypes': contextTypes,
      'summaryPromptTemplateId': summaryPromptTemplateId,
      'scenePromptTemplateId': scenePromptTemplateId,
    };
  }

  StoryPredictionConfig copyWith({
    List<UnifiedAIModel>? selectedModels,
    String? styleInstructions,
    int? generationCount,
    bool? generateSceneContent,
    String? additionalInstructions,
    List<String>? contextTypes,
    String? summaryPromptTemplateId,
    String? scenePromptTemplateId,
  }) {
    return StoryPredictionConfig(
      selectedModels: selectedModels ?? this.selectedModels,
      styleInstructions: styleInstructions ?? this.styleInstructions,
      generationCount: generationCount ?? this.generationCount,
      generateSceneContent: generateSceneContent ?? this.generateSceneContent,
      additionalInstructions: additionalInstructions ?? this.additionalInstructions,
      contextTypes: contextTypes ?? this.contextTypes,
      summaryPromptTemplateId: summaryPromptTemplateId ?? this.summaryPromptTemplateId,
      scenePromptTemplateId: scenePromptTemplateId ?? this.scenePromptTemplateId,
    );
  }
}

/// 剧情推演API请求模型
class StoryPredictionRequest {
  final String chapterId;
  final List<ModelConfig> modelConfigs;
  final int generationCount;
  final String styleInstructions;
  final ContextSelection contextSelection;
  // 为对齐通用AI请求，补充可选的 contextSelections 数组（后端可忽略未知字段）
  final List<Map<String, dynamic>>? contextSelections;
  final String? additionalInstructions;
  final String? summaryPromptTemplateId; // 剧情续写提示词模板ID（用于总结当前剧情并生成下一个大纲）
  final String? scenePromptTemplateId; // 场景内容生成提示词模板ID
  final bool generateSceneContent;

  const StoryPredictionRequest({
    required this.chapterId,
    required this.modelConfigs,
    required this.generationCount,
    required this.styleInstructions,
    required this.contextSelection,
    this.contextSelections,
    this.additionalInstructions,
    this.summaryPromptTemplateId,
    this.scenePromptTemplateId,
    required this.generateSceneContent,
  });

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'modelConfigs': modelConfigs.map((config) => config.toJson()).toList(),
      'generationCount': generationCount,
      'styleInstructions': styleInstructions,
      'contextSelection': contextSelection.toJson(),
      if (contextSelections != null) 'contextSelections': contextSelections,
      'additionalInstructions': additionalInstructions,
      'summaryPromptTemplateId': summaryPromptTemplateId,
      'scenePromptTemplateId': scenePromptTemplateId,
      'generateSceneContent': generateSceneContent,
    };
  }

  factory StoryPredictionRequest.fromConfig(
    String chapterId,
    StoryPredictionConfig config,
  ) {
    return StoryPredictionRequest(
      chapterId: chapterId,
      modelConfigs: config.selectedModels.map((model) => ModelConfig(
        type: model.isPublic ? 'PUBLIC' : 'PRIVATE',
        configId: model.id,
      )).toList(),
      generationCount: config.generationCount,
      styleInstructions: config.styleInstructions,
      contextSelection: ContextSelection(
        types: config.contextTypes,
        maxTokens: 4000, // 默认值
      ),
      additionalInstructions: config.additionalInstructions,
      summaryPromptTemplateId: config.summaryPromptTemplateId,
      scenePromptTemplateId: config.scenePromptTemplateId,
      generateSceneContent: config.generateSceneContent,
    );
  }
}

/// 模型配置
class ModelConfig {
  final String type; // "PUBLIC" or "PRIVATE"
  final String configId;

  const ModelConfig({
    required this.type,
    required this.configId,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'configId': configId,
    };
  }

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      type: json['type'],
      configId: json['configId'],
    );
  }
}

/// 上下文选择配置
class ContextSelection {
  final List<String> types;
  final List<String>? customContextIds;
  final int? maxTokens;

  const ContextSelection({
    required this.types,
    this.customContextIds,
    this.maxTokens,
  });

  Map<String, dynamic> toJson() {
    return {
      'types': types,
      'customContextIds': customContextIds,
      'maxTokens': maxTokens,
    };
  }

  factory ContextSelection.fromJson(Map<String, dynamic> json) {
    return ContextSelection(
      types: List<String>.from(json['types']),
      customContextIds: json['customContextIds'] != null 
        ? List<String>.from(json['customContextIds']) 
        : null,
      maxTokens: json['maxTokens'],
    );
  }
}

/// 剧情推演响应模型
class StoryPredictionResponse {
  final String taskId;
  final String status;
  final String message;

  const StoryPredictionResponse({
    required this.taskId,
    required this.status,
    required this.message,
  });

  factory StoryPredictionResponse.fromJson(Map<String, dynamic> json) {
    return StoryPredictionResponse(
      taskId: json['taskId'],
      status: json['status'],
      message: json['message'],
    );
  }
}

/// 任务状态响应模型
class TaskStatusResponse {
  final String taskId;
  final String status;
  final Object? progress;
  final Object? result;
  final String? error;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskStatusResponse({
    required this.taskId,
    required this.status,
    this.progress,
    this.result,
    this.error,
    this.createdAt,
    this.updatedAt,
  });

  factory TaskStatusResponse.fromJson(Map<String, dynamic> json) {
    return TaskStatusResponse(
      taskId: json['taskId'] is String ? json['taskId'] : json['taskId'].toString(),
      status: json['status'] is String ? json['status'] : json['status'].toString(),
      progress: json['progress'],
      result: json['result'],
      error: json['error'] is String ? json['error'] : json['error']?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// 安全解析DateTime
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

/// 单个剧情推演结果
class PredictionResult {
  final String id;
  final String modelName;
  final String summary;
  final String? sceneContent;
  final PredictionStatus status;
  final PredictionStatus sceneStatus;
  final DateTime createdAt;
  final String? error;

  const PredictionResult({
    required this.id,
    required this.modelName,
    required this.summary,
    this.sceneContent,
    required this.status,
    required this.sceneStatus,
    required this.createdAt,
    this.error,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      id: json['id'],
      modelName: json['modelName'],
      summary: json['summary'],
      sceneContent: json['sceneContent'],
      status: PredictionStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => PredictionStatus.pending,
      ),
      sceneStatus: PredictionStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['sceneStatus'],
        orElse: () => PredictionStatus.pending,
      ),
      createdAt: DateTime.parse(json['createdAt']),
      error: json['error'],
    );
  }

  PredictionResult copyWith({
    String? id,
    String? modelName,
    String? summary,
    String? sceneContent,
    PredictionStatus? status,
    PredictionStatus? sceneStatus,
    DateTime? createdAt,
    String? error,
  }) {
    return PredictionResult(
      id: id ?? this.id,
      modelName: modelName ?? this.modelName,
      summary: summary ?? this.summary,
      sceneContent: sceneContent ?? this.sceneContent,
      status: status ?? this.status,
      sceneStatus: sceneStatus ?? this.sceneStatus,
      createdAt: createdAt ?? this.createdAt,
      error: error ?? this.error,
    );
  }
}

/// 推演状态枚举
enum PredictionStatus {
  pending,      // 等待中
  generating,   // 生成中
  completed,    // 已完成
  failed,       // 失败
  skipped,      // 跳过
}

/// SSE事件模型
class StoryPredictionEvent {
  final String type;
  final String taskId;
  final String status;
  final Object? progress;
  final Object? result;
  final String? error;

  const StoryPredictionEvent({
    required this.type,
    required this.taskId,
    required this.status,
    this.progress,
    this.result,
    this.error,
  });

  factory StoryPredictionEvent.fromJson(Map<String, dynamic> json) {
    return StoryPredictionEvent(
      type: json['type'],
      taskId: json['taskId'],
      status: json['status'],
      progress: json['progress'],
      result: json['result'],
      error: json['error'],
    );
  }
}

/// 迭代优化请求模型
/// 
/// 功能说明：
/// 用户在生成多个推演结果后，可以选择一个最满意的结果，
/// 提出修改意见，基于选定的结果继续推演，支持切换模型。
class RefineStoryPredictionRequest {
  /// 原始任务ID
  final String originalTaskId;
  
  /// 基于的预测结果ID（用户选择的那个）
  final String basePredictionId;
  
  /// 用户的修改意见
  final String refinementInstructions;
  
  /// 新的模型配置（支持切换模型）
  final List<ModelConfig> modelConfigs;
  
  /// 每个模型生成的数量
  final int generationCount;
  
  /// 继承的上下文配置（可选）
  final ContextSelection? contextSelection;
  
  /// 是否生成场景内容
  final bool generateSceneContent;
  
  /// 风格指令（可选）
  final String? styleInstructions;
  
  /// 额外指令（可选）
  final String? additionalInstructions;
  
  /// 摘要生成提示词模板ID（可选）
  final String? summaryPromptTemplateId;
  
  /// 场景生成提示词模板ID（可选）
  final String? scenePromptTemplateId;

  const RefineStoryPredictionRequest({
    required this.originalTaskId,
    required this.basePredictionId,
    required this.refinementInstructions,
    required this.modelConfigs,
    this.generationCount = 1,
    this.contextSelection,
    this.generateSceneContent = true,
    this.styleInstructions,
    this.additionalInstructions,
    this.summaryPromptTemplateId,
    this.scenePromptTemplateId,
  });

  Map<String, dynamic> toJson() {
    return {
      'originalTaskId': originalTaskId,
      'basePredictionId': basePredictionId,
      'refinementInstructions': refinementInstructions,
      'modelConfigs': modelConfigs.map((config) => config.toJson()).toList(),
      'generationCount': generationCount,
      if (contextSelection != null) 'contextSelection': contextSelection!.toJson(),
      'generateSceneContent': generateSceneContent,
      if (styleInstructions != null) 'styleInstructions': styleInstructions,
      if (additionalInstructions != null) 'additionalInstructions': additionalInstructions,
      if (summaryPromptTemplateId != null) 'summaryPromptTemplateId': summaryPromptTemplateId,
      if (scenePromptTemplateId != null) 'scenePromptTemplateId': scenePromptTemplateId,
    };
  }

  /// 从现有配置和选择的结果创建迭代优化请求
  factory RefineStoryPredictionRequest.fromConfig({
    required String originalTaskId,
    required String basePredictionId,
    required String refinementInstructions,
    required List<UnifiedAIModel> newModels,
    int generationCount = 1,
    ContextSelection? contextSelection,
    bool generateSceneContent = true,
    String? styleInstructions,
    String? additionalInstructions,
    String? summaryPromptTemplateId,
    String? scenePromptTemplateId,
  }) {
    return RefineStoryPredictionRequest(
      originalTaskId: originalTaskId,
      basePredictionId: basePredictionId,
      refinementInstructions: refinementInstructions,
      modelConfigs: newModels.map((model) => ModelConfig(
        type: model.isPublic ? 'PUBLIC' : 'PRIVATE',
        configId: model.id,
      )).toList(),
      generationCount: generationCount,
      contextSelection: contextSelection,
      generateSceneContent: generateSceneContent,
      styleInstructions: styleInstructions,
      additionalInstructions: additionalInstructions,
      summaryPromptTemplateId: summaryPromptTemplateId,
      scenePromptTemplateId: scenePromptTemplateId,
    );
  }
}