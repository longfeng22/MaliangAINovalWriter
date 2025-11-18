import '../utils/date_time_parser.dart';

/// 策略响应模型
/// 统一处理策略管理API返回的数据结构
class StrategyResponse {
  final String id;
  final String name;
  final String description;
  final String? authorId;
  final String? authorName;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int usageCount;
  final int expectedRootNodes;
  final int maxDepth;
  final String reviewStatus;
  final List<String> categories;
  final List<String> tags;
  final int difficultyLevel;
  final String? systemPrompt;
  final String? userPrompt;
  final List<Map<String, dynamic>>? nodeTemplates;

  const StrategyResponse({
    required this.id,
    required this.name,
    required this.description,
    this.authorId,
    this.authorName,
    required this.isPublic,
    required this.createdAt,
    this.updatedAt,
    required this.usageCount,
    required this.expectedRootNodes,
    required this.maxDepth,
    required this.reviewStatus,
    this.categories = const [],
    this.tags = const [],
    required this.difficultyLevel,
    this.systemPrompt,
    this.userPrompt,
    this.nodeTemplates,
  });

  factory StrategyResponse.fromJson(Map<String, dynamic> json) {
    return StrategyResponse(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名策略',
      description: json['description'] as String? ?? '',
      authorId: json['authorId'] as String?,
      authorName: json['authorName'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      createdAt: parseBackendDateTime(json['createdAt']),
      updatedAt: parseBackendDateTimeSafely(json['updatedAt']),
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      expectedRootNodes: (json['expectedRootNodes'] as num?)?.toInt() ?? 8,
      maxDepth: (json['maxDepth'] as num?)?.toInt() ?? 3,
      reviewStatus: json['reviewStatus'] as String? ?? 'DRAFT',
      categories: (json['categories'] as List?)?.map((e) => e.toString()).toList() ?? [],
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      difficultyLevel: (json['difficultyLevel'] as num?)?.toInt() ?? 3,
      systemPrompt: json['systemPrompt'] as String?,
      userPrompt: json['userPrompt'] as String?,
      nodeTemplates: json['nodeTemplates'] != null 
          ? List<Map<String, dynamic>>.from(json['nodeTemplates'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'authorId': authorId,
    'authorName': authorName,
    'isPublic': isPublic,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'usageCount': usageCount,
    'expectedRootNodes': expectedRootNodes,
    'maxDepth': maxDepth,
    'reviewStatus': reviewStatus,
    'categories': categories,
    'tags': tags,
    'difficultyLevel': difficultyLevel,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (userPrompt != null) 'userPrompt': userPrompt,
    if (nodeTemplates != null) 'nodeTemplates': nodeTemplates,
  };

  /// 判断是否为系统预设策略
  bool get isSystemStrategy => authorId == null || authorId!.isEmpty;

  /// 判断是否可以编辑（只有自己创建的策略才能编辑）
  bool canEdit(String? currentUserId) {
    return !isSystemStrategy && authorId == currentUserId;
  }

  /// 判断是否可以删除
  bool canDelete(String? currentUserId) {
    return canEdit(currentUserId);
  }

  /// 获取策略状态的本地化文本
  String get localizedReviewStatus {
    switch (reviewStatus) {
      case 'DRAFT':
        return '草稿';
      case 'PENDING':
        return '待审核';
      case 'APPROVED':
        return '已通过';
      case 'REJECTED':
        return '已拒绝';
      default:
        return reviewStatus;
    }
  }

  /// 判断策略是否可以提交审核
  bool get canSubmitForReview {
    return reviewStatus == 'DRAFT' || reviewStatus == 'REJECTED';
  }

  /// 判断策略是否正在审核中
  bool get isPendingReview {
    return reviewStatus == 'PENDING';
  }

  /// 判断策略是否已通过审核
  bool get isApproved {
    return reviewStatus == 'APPROVED';
  }

  StrategyResponse copyWith({
    String? id,
    String? name,
    String? description,
    String? authorId,
    String? authorName,
    bool? isPublic,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? usageCount,
    int? expectedRootNodes,
    int? maxDepth,
    String? reviewStatus,
    List<String>? categories,
    List<String>? tags,
    int? difficultyLevel,
    String? systemPrompt,
    String? userPrompt,
    List<Map<String, dynamic>>? nodeTemplates,
  }) {
    return StrategyResponse(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usageCount: usageCount ?? this.usageCount,
      expectedRootNodes: expectedRootNodes ?? this.expectedRootNodes,
      maxDepth: maxDepth ?? this.maxDepth,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPrompt: userPrompt ?? this.userPrompt,
      nodeTemplates: nodeTemplates ?? this.nodeTemplates,
    );
  }
}

/// 节点模板配置模型
class NodeTemplateConfig {
  final String id;
  final String name;
  final String type;
  final String description;
  final int minChildren;
  final int maxChildren;
  final int minDescriptionLength;
  final int maxDescriptionLength;
  final bool isRootTemplate;
  final int priority;
  final String? generationHint;
  final List<String> tags;

  const NodeTemplateConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    this.minChildren = 0,
    this.maxChildren = -1,
    this.minDescriptionLength = 50,
    this.maxDescriptionLength = 500,
    this.isRootTemplate = false,
    this.priority = 0,
    this.generationHint,
    this.tags = const [],
  });

  factory NodeTemplateConfig.fromJson(Map<String, dynamic> json) {
    return NodeTemplateConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      minChildren: (json['minChildren'] as num?)?.toInt() ?? 0,
      maxChildren: (json['maxChildren'] as num?)?.toInt() ?? -1,
      minDescriptionLength: (json['minDescriptionLength'] as num?)?.toInt() ?? 50,
      maxDescriptionLength: (json['maxDescriptionLength'] as num?)?.toInt() ?? 500,
      isRootTemplate: json['isRootTemplate'] as bool? ?? false,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      generationHint: json['generationHint'] as String?,
      tags: List<String>.from(json['tags'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'description': description,
    'minChildren': minChildren,
    'maxChildren': maxChildren,
    'minDescriptionLength': minDescriptionLength,
    'maxDescriptionLength': maxDescriptionLength,
    'isRootTemplate': isRootTemplate,
    'priority': priority,
    if (generationHint != null) 'generationHint': generationHint,
    'tags': tags,
  };
}