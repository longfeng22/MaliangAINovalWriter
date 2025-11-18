/// 通用审核数据模型
/// 支持多种类型的内容审核（策略、增强提示词等）

import 'package:flutter/foundation.dart';
import '../../utils/date_time_parser.dart';

/// 审核项类型枚举
enum ReviewItemType {
  strategy('STRATEGY', '策略'),
  enhancedTemplate('ENHANCED_TEMPLATE', '增强提示词'),
  publicTemplate('PUBLIC_TEMPLATE', '公共模板'),
  userContent('USER_CONTENT', '用户内容');

  final String value;
  final String displayName;

  const ReviewItemType(this.value, this.displayName);

  static ReviewItemType fromValue(String value) {
    return ReviewItemType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReviewItemType.userContent,
    );
  }
}

/// 审核状态枚举
enum ReviewStatus {
  pending('PENDING', '待审核', '⏳'),
  approved('APPROVED', '已通过', '✅'),
  rejected('REJECTED', '已拒绝', '❌'),
  draft('DRAFT', '草稿', '📝');

  final String value;
  final String displayName;
  final String emoji;

  const ReviewStatus(this.value, this.displayName, this.emoji);

  static ReviewStatus fromValue(String? value) {
    if (value == null) return ReviewStatus.draft;
    return ReviewStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReviewStatus.draft,
    );
  }
}

/// 通用审核项模型
@immutable
class ReviewItem {
  final String id;
  final ReviewItemType type;
  final String? featureType; // AI功能类型（SETTING_TREE_GENERATION等）
  final String title;
  final String description;
  final ReviewStatus status;
  final String? authorId;
  final String? authorName;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewerId;
  final String? reviewerName;
  final String? reviewComment;
  final List<String>? rejectionReasons;
  final List<String>? improvementSuggestions;
  final Map<String, dynamic> metadata; // 额外的类型特定数据

  const ReviewItem({
    required this.id,
    required this.type,
    this.featureType,
    required this.title,
    required this.description,
    required this.status,
    this.authorId,
    this.authorName,
    required this.createdAt,
    this.submittedAt,
    this.reviewedAt,
    this.reviewerId,
    this.reviewerName,
    this.reviewComment,
    this.rejectionReasons,
    this.improvementSuggestions,
    this.metadata = const {},
  });

  /// 从JSON创建
  factory ReviewItem.fromJson(Map<String, dynamic> json, ReviewItemType type) {
    return ReviewItem(
      id: json['id'] as String,
      type: type,
      featureType: json['featureType'] as String?,
      title: json['name'] ?? json['title'] ?? '未命名',
      description: json['description'] ?? '',
      status: ReviewStatus.fromValue(json['status'] ?? json['reviewStatus'] as String?),
      authorId: json['authorId'] as String?,
      authorName: json['authorName'] as String?,
      // 使用公共函数解析时间，支持多种格式
      createdAt: parseBackendDateTime(json['createdAt']),
      submittedAt: parseBackendDateTimeSafely(json['submittedAt']),
      reviewedAt: parseBackendDateTimeSafely(json['reviewedAt']),
      reviewerId: json['reviewerId'] as String?,
      reviewerName: json['reviewerName'] as String?,
      reviewComment: json['reviewComment'] as String?,
      rejectionReasons: (json['rejectionReasons'] as List?)?.cast<String>(),
      improvementSuggestions: (json['improvementSuggestions'] as List?)?.cast<String>(),
      metadata: Map<String, dynamic>.from(json),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'featureType': featureType,
      'name': title,
      'description': description,
      'reviewStatus': status.value,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': createdAt.toIso8601String(),
      'submittedAt': submittedAt?.toIso8601String(),
      'reviewedAt': reviewedAt?.toIso8601String(),
      'reviewerId': reviewerId,
      'reviewerName': reviewerName,
      'reviewComment': reviewComment,
      'rejectionReasons': rejectionReasons,
      'improvementSuggestions': improvementSuggestions,
      ...metadata,
    };
  }
  
  /// 获取功能类型显示名称
  String get featureTypeDisplay {
    if (featureType == null) return '未知';
    
    switch (featureType) {
      case 'SETTING_TREE_GENERATION':
        return '设定生成';
      case 'REWRITE':
        return '重写';
      case 'EXPANSION':
        return '扩写';
      case 'SUMMARIZE':
        return '总结';
      case 'CHAT':
        return '对话';
      case 'CONTINUE_WRITING':
        return '续写';
      default:
        return featureType!;
    }
  }
  
  // 🆕 审核必需字段（从 metadata 中获取）
  
  /// 系统提示词
  String? get systemPrompt => metadata['systemPrompt'] as String?;
  
  /// 用户提示词
  String? get userPrompt => metadata['userPrompt'] as String?;
  
  /// 标签
  List<String>? get tags => (metadata['tags'] as List?)?.cast<String>();
  
  /// 分类
  List<String>? get categories => (metadata['categories'] as List?)?.cast<String>();
  
  /// 是否隐藏提示词
  bool? get hidePrompts => metadata['hidePrompts'] as bool?;
  
  /// 策略配置（如果是策略类型）
  Map<String, dynamic>? get settingGenerationConfig => 
      metadata['settingGenerationConfig'] as Map<String, dynamic>?;
  
  /// 使用次数
  int? get usageCount => metadata['usageCount'] as int?;
  
  /// 收藏次数
  int? get favoriteCount => metadata['favoriteCount'] as int?;
  
  /// 评分
  double? get rating {
    final r = metadata['rating'];
    if (r == null) return null;
    if (r is double) return r;
    if (r is int) return r.toDouble();
    return null;
  }

  ReviewItem copyWith({
    String? id,
    ReviewItemType? type,
    String? featureType,
    String? title,
    String? description,
    ReviewStatus? status,
    String? authorId,
    String? authorName,
    DateTime? createdAt,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewerId,
    String? reviewerName,
    String? reviewComment,
    List<String>? rejectionReasons,
    List<String>? improvementSuggestions,
    Map<String, dynamic>? metadata,
  }) {
    return ReviewItem(
      id: id ?? this.id,
      type: type ?? this.type,
      featureType: featureType ?? this.featureType,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewerId: reviewerId ?? this.reviewerId,
      reviewerName: reviewerName ?? this.reviewerName,
      reviewComment: reviewComment ?? this.reviewComment,
      rejectionReasons: rejectionReasons ?? this.rejectionReasons,
      improvementSuggestions: improvementSuggestions ?? this.improvementSuggestions,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// 审核决策常量
class ReviewDecisionConstants {
  /// 审核通过
  static const String approved = 'APPROVED';
  
  /// 审核拒绝
  static const String rejected = 'REJECTED';
  
  ReviewDecisionConstants._(); // 私有构造函数，防止实例化
}

/// 审核状态常量（字符串值）
class ReviewStatusConstants {
  /// 待审核
  static const String pending = 'PENDING';
  
  /// 已通过
  static const String approved = 'APPROVED';
  
  /// 已拒绝
  static const String rejected = 'REJECTED';
  
  /// 草稿
  static const String draft = 'DRAFT';
  
  ReviewStatusConstants._(); // 私有构造函数，防止实例化
}

/// 审核决策
class ReviewDecision {
  final String decision; // APPROVED 或 REJECTED
  final String? comment;
  final List<String>? rejectionReasons;
  final List<String>? improvementSuggestions;

  const ReviewDecision({
    required this.decision,
    this.comment,
    this.rejectionReasons,
    this.improvementSuggestions,
  });

  Map<String, dynamic> toJson() {
    return {
      'decision': decision,
      if (comment != null) 'comment': comment,
      if (rejectionReasons != null) 'rejectionReasons': rejectionReasons,
      if (improvementSuggestions != null) 'improvementSuggestions': improvementSuggestions,
    };
  }
}

/// 审核筛选条件
class ReviewFilter {
  final ReviewItemType? type;
  final ReviewStatus? status;
  final String? authorId;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? keyword;

  const ReviewFilter({
    this.type,
    this.status,
    this.authorId,
    this.startDate,
    this.endDate,
    this.keyword,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (type != null) params['type'] = type!.value;
    if (status != null) params['status'] = status!.value;
    if (authorId != null) params['authorId'] = authorId;
    if (startDate != null) params['startDate'] = startDate!.toIso8601String();
    if (endDate != null) params['endDate'] = endDate!.toIso8601String();
    if (keyword != null && keyword!.isNotEmpty) params['keyword'] = keyword;
    return params;
  }
}

