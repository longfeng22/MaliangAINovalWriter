/// 知识库相关的数据模型
library;

import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/utils/date_time_parser.dart';

/// 小说知识库模型
class NovelKnowledgeBase {
  final String id;
  final String? fanqieNovelId;
  final String title;
  final String description;
  final String? coverImageUrl;
  final String? author;
  final bool isUserImported;
  final NovelCompletionStatus? completionStatus;
  final List<String>? tags;
  
  // 知识库内容
  final List<NovelSettingItem>? narrativeStyleSettings;
  final List<NovelSettingItem>? characterPlotSettings;
  final List<NovelSettingItem>? novelFeatureSettings;
  final List<NovelSettingItem>? hotMemesSettings;
  final List<NovelSettingItem>? customSettings;
  final List<NovelSettingItem>? readerEmotionSettings;
  
  // 章节大纲
  final List<ChapterOutlineDto>? chapterOutlines;
  
  // 章节大纲外键引用
  final String? outlineNovelId;
  
  // 统计和状态
  final CacheStatus status;
  final bool cacheSuccess;
  final String? cacheFailureReason;
  final DateTime? cacheTime;
  final int referenceCount;
  final int viewCount;
  final int likeCount;
  final List<String>? likedUserIds;
  final bool isPublic;
  final String firstImportUserId;
  final DateTime? firstImportTime;
  final String? extractionTaskId;
  final String? modelConfigId;
  final String? modelType;
  
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NovelKnowledgeBase({
    required this.id,
    this.fanqieNovelId,
    required this.title,
    required this.description,
    this.coverImageUrl,
    this.author,
    this.isUserImported = false,
    this.completionStatus,
    this.tags,
    this.narrativeStyleSettings,
    this.characterPlotSettings,
    this.novelFeatureSettings,
    this.hotMemesSettings,
    this.customSettings,
    this.readerEmotionSettings,
    this.chapterOutlines,
    this.outlineNovelId,
    this.status = CacheStatus.pending,
    this.cacheSuccess = false,
    this.cacheFailureReason,
    this.cacheTime,
    this.referenceCount = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.likedUserIds,
    this.isPublic = false,
    required this.firstImportUserId,
    this.firstImportTime,
    this.extractionTaskId,
    this.modelConfigId,
    this.modelType,
    this.createdAt,
    this.updatedAt,
  });

  factory NovelKnowledgeBase.fromJson(Map<String, dynamic> json) {
    return NovelKnowledgeBase(
      id: json['id'] as String,
      fanqieNovelId: json['fanqieNovelId'] as String?,
      title: json['title'] as String? ?? '未命名知识库', // ✅ 安全处理null
      description: json['description'] as String? ?? '',
      coverImageUrl: json['coverImageUrl'] as String?,
      author: json['author'] as String?,
      isUserImported: json['isUserImported'] as bool? ?? false,
      completionStatus: json['completionStatus'] != null
          ? NovelCompletionStatusExtension.fromString(json['completionStatus'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      narrativeStyleSettings: (json['narrativeStyleSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      characterPlotSettings: (json['characterPlotSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      novelFeatureSettings: (json['novelFeatureSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      hotMemesSettings: (json['hotMemesSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      customSettings: (json['customSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      readerEmotionSettings: (json['readerEmotionSettings'] as List<dynamic>?)
          ?.map((e) => NovelSettingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      chapterOutlines: (json['chapterOutlines'] as List<dynamic>?)
          ?.map((e) => ChapterOutlineDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      outlineNovelId: json['outlineNovelId'] as String?,
      status: CacheStatusExtension.fromString(json['status'] as String? ?? 'PENDING'),
      cacheSuccess: json['cacheSuccess'] as bool? ?? false,
      cacheFailureReason: json['cacheFailureReason'] as String?,
      cacheTime: parseBackendDateTimeSafely(json['cacheTime']),
      referenceCount: json['referenceCount'] as int? ?? 0,
      viewCount: json['viewCount'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? 0,
      likedUserIds: (json['likedUserIds'] as List<dynamic>?)?.map((e) => e as String).toList(),
      isPublic: json['isPublic'] as bool? ?? false,
      firstImportUserId: json['firstImportUserId'] as String? ?? '', // ✅ 安全处理null
      firstImportTime: parseBackendDateTimeSafely(json['firstImportTime']),
      extractionTaskId: json['extractionTaskId'] as String?,
      modelConfigId: json['modelConfigId'] as String?,
      modelType: json['modelType'] as String?,
      createdAt: parseBackendDateTimeSafely(json['createdAt']),
      updatedAt: parseBackendDateTimeSafely(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fanqieNovelId': fanqieNovelId,
      'title': title,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'author': author,
      'isUserImported': isUserImported,
      'completionStatus': completionStatus?.value,
      'tags': tags,
      'narrativeStyleSettings': narrativeStyleSettings?.map((e) => e.toJson()).toList(),
      'characterPlotSettings': characterPlotSettings?.map((e) => e.toJson()).toList(),
      'novelFeatureSettings': novelFeatureSettings?.map((e) => e.toJson()).toList(),
      'hotMemesSettings': hotMemesSettings?.map((e) => e.toJson()).toList(),
      'customSettings': customSettings?.map((e) => e.toJson()).toList(),
      'readerEmotionSettings': readerEmotionSettings?.map((e) => e.toJson()).toList(),
      'chapterOutlines': chapterOutlines?.map((e) => e.toJson()).toList(),
      'outlineNovelId': outlineNovelId,
      'status': status.value,
      'cacheSuccess': cacheSuccess,
      'cacheFailureReason': cacheFailureReason,
      'cacheTime': cacheTime?.toIso8601String(),
      'referenceCount': referenceCount,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'likedUserIds': likedUserIds,
      'isPublic': isPublic,
      'firstImportUserId': firstImportUserId,
      'firstImportTime': firstImportTime?.toIso8601String(),
      'extractionTaskId': extractionTaskId,
      'modelConfigId': modelConfigId,
      'modelType': modelType,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

/// 小说完结状态枚举
enum NovelCompletionStatus {
  ongoing('ONGOING', '连载中'),
  completed('COMPLETED', '已完结'),
  paused('PAUSED', '暂停中'),
  unknown('UNKNOWN', '未知');

  final String value;
  final String displayName;

  const NovelCompletionStatus(this.value, this.displayName);
}

extension NovelCompletionStatusExtension on NovelCompletionStatus {
  static NovelCompletionStatus fromString(String value) {
    return NovelCompletionStatus.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => NovelCompletionStatus.unknown,
    );
  }
}

/// 缓存状态枚举
enum CacheStatus {
  pending('PENDING', '待处理'),
  processing('PROCESSING', '处理中'),
  completed('COMPLETED', '已完成'),
  failed('FAILED', '失败'),
  partial('PARTIAL', '部分完成');

  final String value;
  final String displayName;

  const CacheStatus(this.value, this.displayName);
}

extension CacheStatusExtension on CacheStatus {
  static CacheStatus fromString(String value) {
    return CacheStatus.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => CacheStatus.pending,
    );
  }
}

/// 番茄小说信息模型
class FanqieNovelInfo {
  final String novelId;
  final String title;
  final String? author;
  final String? description;
  final String? coverImageUrl;
  final String? category;
  final String? score;
  final NovelCompletionStatus? completionStatus;
  final List<String>? tags;
  final int? chapterCount;
  final bool? cached; // ✅ 是否已在知识库中缓存
  final String? knowledgeBaseId; // ✅ 知识库ID

  const FanqieNovelInfo({
    required this.novelId,
    required this.title,
    this.author,
    this.description,
    this.coverImageUrl,
    this.category,
    this.score,
    this.completionStatus,
    this.tags,
    this.chapterCount,
    this.cached,
    this.knowledgeBaseId,
  });

  factory FanqieNovelInfo.fromJson(Map<String, dynamic> json) {
    return FanqieNovelInfo(
      novelId: json['novelId'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      category: json['category'] as String?,
      score: json['score'] as String?,
      completionStatus: json['completionStatus'] != null
          ? NovelCompletionStatusExtension.fromString(json['completionStatus'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      chapterCount: json['chapterCount'] as int?,
      cached: json['cached'] as bool?,
      knowledgeBaseId: json['knowledgeBaseId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'novelId': novelId,
      'title': title,
      'author': author,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'category': category,
      'score': score,
      'completionStatus': completionStatus?.value,
      'tags': tags,
      'chapterCount': chapterCount,
      'cached': cached,
      'knowledgeBaseId': knowledgeBaseId,
    };
  }
}

/// 番茄小说章节信息
class FanqieChapterInfo {
  final String chapterId;
  final String title;
  final int order;

  const FanqieChapterInfo({
    required this.chapterId,
    required this.title,
    required this.order,
  });

  factory FanqieChapterInfo.fromJson(Map<String, dynamic> json) {
    return FanqieChapterInfo(
      chapterId: json['chapterId'] as String,
      title: json['title'] as String,
      order: json['order'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'title': title,
      'order': order,
    };
  }
}

/// 知识库卡片模型（用于列表显示）
class KnowledgeBaseCard {
  final String id;
  final String title;
  final String description;
  final String? coverImageUrl;
  final String? author;
  final List<String>? tags;
  final int likeCount;
  final int referenceCount;
  final int viewCount;
  final DateTime? importTime;
  final NovelCompletionStatus? completionStatus;
  final bool isUserImported; // 是否为用户导入
  final String? fanqieNovelId; // 番茄小说ID

  const KnowledgeBaseCard({
    required this.id,
    required this.title,
    required this.description,
    this.coverImageUrl,
    this.author,
    this.tags,
    required this.likeCount,
    required this.referenceCount,
    required this.viewCount,
    this.importTime,
    this.completionStatus,
    this.isUserImported = false,
    this.fanqieNovelId,
  });

  factory KnowledgeBaseCard.fromJson(Map<String, dynamic> json) {
    return KnowledgeBaseCard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '未命名知识库',  // ✅ 提供默认值
      description: json['description'] as String? ?? '',  // ✅ 提供默认值
      coverImageUrl: json['coverImageUrl'] as String?,
      author: json['author'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      likeCount: json['likeCount'] as int? ?? 0,
      referenceCount: json['referenceCount'] as int? ?? 0,
      viewCount: json['viewCount'] as int? ?? 0,
      importTime: parseBackendDateTimeSafely(json['importTime']),
      completionStatus: json['completionStatus'] != null
          ? NovelCompletionStatusExtension.fromString(json['completionStatus'] as String)
          : null,
      isUserImported: json['isUserImported'] as bool? ?? false,
      fanqieNovelId: json['fanqieNovelId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'author': author,
      'tags': tags,
      'likeCount': likeCount,
      'referenceCount': referenceCount,
      'viewCount': viewCount,
      'importTime': importTime?.toIso8601String(),
      'completionStatus': completionStatus?.value,
      'isUserImported': isUserImported,
      'fanqieNovelId': fanqieNovelId,
    };
  }
}

/// 知识库列表响应
class KnowledgeBaseListResponse {
  final List<KnowledgeBaseCard> items;
  final int totalCount;
  final int page;
  final int size;

  const KnowledgeBaseListResponse({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.size,
  });

  factory KnowledgeBaseListResponse.fromJson(Map<String, dynamic> json) {
    return KnowledgeBaseListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => KnowledgeBaseCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: json['totalCount'] as int,
      page: json['page'] as int,
      size: json['size'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'totalCount': totalCount,
      'page': page,
      'size': size,
    };
  }
}

/// 知识提取任务响应
class KnowledgeExtractionTaskResponse {
  final String taskId;
  final String status;
  final String? knowledgeBaseId;
  final int? progress;
  final String? message;
  final DateTime? startTime;
  final DateTime? estimatedCompletionTime;

  const KnowledgeExtractionTaskResponse({
    required this.taskId,
    required this.status,
    this.knowledgeBaseId,
    this.progress,
    this.message,
    this.startTime,
    this.estimatedCompletionTime,
  });

  factory KnowledgeExtractionTaskResponse.fromJson(Map<String, dynamic> json) {
    return KnowledgeExtractionTaskResponse(
      taskId: json['taskId'] as String,
      status: json['status'] as String,
      knowledgeBaseId: json['knowledgeBaseId'] as String?,
      progress: json['progress'] as int?,
      message: json['message'] as String?,
      startTime: parseBackendDateTimeSafely(json['startTime']),
      estimatedCompletionTime: parseBackendDateTimeSafely(json['estimatedCompletionTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'status': status,
      'knowledgeBaseId': knowledgeBaseId,
      'progress': progress,
      'message': message,
      'startTime': startTime?.toIso8601String(),
      'estimatedCompletionTime': estimatedCompletionTime?.toIso8601String(),
    };
  }
}

/// 知识库缓存状态响应
class KnowledgeBaseCacheStatusResponse {
  final bool cached;
  final String? knowledgeBaseId;
  final String? status;
  final DateTime? cacheTime;

  const KnowledgeBaseCacheStatusResponse({
    required this.cached,
    this.knowledgeBaseId,
    this.status,
    this.cacheTime,
  });

  factory KnowledgeBaseCacheStatusResponse.fromJson(Map<String, dynamic> json) {
    return KnowledgeBaseCacheStatusResponse(
      cached: json['cached'] as bool,
      knowledgeBaseId: json['knowledgeBaseId'] as String?,
      status: json['status'] as String?,
      cacheTime: parseBackendDateTimeSafely(json['cacheTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cached': cached,
      'knowledgeBaseId': knowledgeBaseId,
      'status': status,
      'cacheTime': cacheTime?.toIso8601String(),
    };
  }
}

/// 章节大纲DTO
class ChapterOutlineDto {
  final String chapterId;
  final String title;
  final String summary;
  final int order;

  const ChapterOutlineDto({
    required this.chapterId,
    required this.title,
    required this.summary,
    required this.order,
  });

  factory ChapterOutlineDto.fromJson(Map<String, dynamic> json) {
    return ChapterOutlineDto(
      chapterId: json['chapterId'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      order: json['order'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'title': title,
      'summary': summary,
      'order': order,
    };
  }
}

/// 知识提取类型枚举
enum KnowledgeExtractionType {
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

  final String value;
  final String displayName;

  const KnowledgeExtractionType(this.value, this.displayName);
}

extension KnowledgeExtractionTypeExtension on KnowledgeExtractionType {
  static KnowledgeExtractionType fromString(String value) {
    return KnowledgeExtractionType.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => KnowledgeExtractionType.custom,
    );
  }
  
  static List<KnowledgeExtractionType> getDefaultTypes() {
    return [
      KnowledgeExtractionType.narrativeStyle,
      KnowledgeExtractionType.writingStyle,
      KnowledgeExtractionType.wordUsage,
      KnowledgeExtractionType.coreConflict,
      KnowledgeExtractionType.suspenseDesign,
      KnowledgeExtractionType.storyPacing,
      KnowledgeExtractionType.characterBuilding,
      KnowledgeExtractionType.worldview,
      KnowledgeExtractionType.goldenFinger,
      KnowledgeExtractionType.resonance,
      KnowledgeExtractionType.pleasurePoint,
      KnowledgeExtractionType.excitementPoint,
      KnowledgeExtractionType.hotMemes,
      KnowledgeExtractionType.funnyPoints,
    ];
  }
}

