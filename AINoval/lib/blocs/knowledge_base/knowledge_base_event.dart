/// 知识库事件
library;

import 'package:equatable/equatable.dart';

abstract class KnowledgeBaseEvent extends Equatable {
  const KnowledgeBaseEvent();

  @override
  List<Object?> get props => [];
}

/// 搜索番茄小说
class SearchFanqieNovels extends KnowledgeBaseEvent {
  final String query;

  const SearchFanqieNovels(this.query);

  @override
  List<Object?> get props => [query];
}

/// 获取番茄小说详情
class LoadFanqieNovelDetail extends KnowledgeBaseEvent {
  final String novelId;

  const LoadFanqieNovelDetail(this.novelId);

  @override
  List<Object?> get props => [novelId];
}

/// 检查缓存状态
class CheckCacheStatus extends KnowledgeBaseEvent {
  final String fanqieNovelId;

  const CheckCacheStatus(this.fanqieNovelId);

  @override
  List<Object?> get props => [fanqieNovelId];
}

/// 从番茄小说提取知识库（自动使用"chaishu"公共模型，无需指定）
class ExtractFromFanqieNovel extends KnowledgeBaseEvent {
  final String fanqieNovelId;
  final List<String>? extractionTypes;

  const ExtractFromFanqieNovel({
    required this.fanqieNovelId,
    this.extractionTypes,
  });

  @override
  List<Object?> get props => [fanqieNovelId, extractionTypes];
}

/// 从用户文本提取知识库
class ExtractFromText extends KnowledgeBaseEvent {
  final String title;
  final String content;
  final String? description;
  final List<String> extractionTypes;
  final String modelConfigId;
  final String modelType;

  const ExtractFromText({
    required this.title,
    required this.content,
    this.description,
    required this.extractionTypes,
    required this.modelConfigId,
    required this.modelType,
  });

  @override
  List<Object?> get props => [title, content, description, extractionTypes, modelConfigId, modelType];
}

/// 从预览会话提取知识库
class ExtractFromPreviewSession extends KnowledgeBaseEvent {
  final String previewSessionId;
  final String title;
  final String? description;
  final List<String> extractionTypes;
  final String modelConfigId;
  final String modelType;
  final int? chapterLimit; // null表示整本，否则为前N章

  const ExtractFromPreviewSession({
    required this.previewSessionId,
    required this.title,
    this.description,
    required this.extractionTypes,
    required this.modelConfigId,
    required this.modelType,
    this.chapterLimit,
  });

  @override
  List<Object?> get props => [previewSessionId, title, description, extractionTypes, modelConfigId, modelType, chapterLimit];
}

/// 获取拆书任务状态
class LoadExtractionTaskStatus extends KnowledgeBaseEvent {
  final String taskId;

  const LoadExtractionTaskStatus(this.taskId);

  @override
  List<Object?> get props => [taskId];
}

/// 查询公共知识库列表
class LoadPublicKnowledgeBases extends KnowledgeBaseEvent {
  final String? keyword;
  final List<String>? tags;
  final String? completionStatus;
  final String sortBy;
  final String sortOrder;
  final int page;
  final int size;

  const LoadPublicKnowledgeBases({
    this.keyword,
    this.tags,
    this.completionStatus,
    this.sortBy = 'likeCount',
    this.sortOrder = 'desc',
    this.page = 0,
    this.size = 20,
  });

  @override
  List<Object?> get props => [keyword, tags, completionStatus, sortBy, sortOrder, page, size];
}

/// 查询我的知识库列表
class LoadMyKnowledgeBases extends KnowledgeBaseEvent {
  final String? keyword;
  final String? sourceType; // null=全部, 'user_imported'=用户导入, 'fanqie_novel'=番茄小说
  final String sortBy;
  final String sortOrder;
  final int page;
  final int size;

  const LoadMyKnowledgeBases({
    this.keyword,
    this.sourceType,
    this.sortBy = 'importTime',
    this.sortOrder = 'desc',
    this.page = 0,
    this.size = 20,
  });

  @override
  List<Object?> get props => [keyword, sourceType, sortBy, sortOrder, page, size];
}

/// 获取知识库详情
class LoadKnowledgeBaseDetail extends KnowledgeBaseEvent {
  final String knowledgeBaseId;

  const LoadKnowledgeBaseDetail(this.knowledgeBaseId);

  @override
  List<Object?> get props => [knowledgeBaseId];
}

/// 切换点赞
class ToggleKnowledgeBaseLike extends KnowledgeBaseEvent {
  final String knowledgeBaseId;

  const ToggleKnowledgeBaseLike(this.knowledgeBaseId);

  @override
  List<Object?> get props => [knowledgeBaseId];
}

/// 切换知识库公开状态
class ToggleKnowledgeBasePublic extends KnowledgeBaseEvent {
  final String knowledgeBaseId;

  const ToggleKnowledgeBasePublic(this.knowledgeBaseId);

  @override
  List<Object?> get props => [knowledgeBaseId];
}

/// 添加到小说
class AddKnowledgeBaseToNovel extends KnowledgeBaseEvent {
  final String knowledgeBaseId;
  final String novelId;

  const AddKnowledgeBaseToNovel({
    required this.knowledgeBaseId,
    required this.novelId,
  });

  @override
  List<Object?> get props => [knowledgeBaseId, novelId];
}

/// 添加到我的知识库
class AddToMyKnowledgeBase extends KnowledgeBaseEvent {
  final String knowledgeBaseId;

  const AddToMyKnowledgeBase(this.knowledgeBaseId);

  @override
  List<Object?> get props => [knowledgeBaseId];
}

/// 从我的知识库删除
class RemoveFromMyKnowledgeBase extends KnowledgeBaseEvent {
  final String knowledgeBaseId;

  const RemoveFromMyKnowledgeBase(this.knowledgeBaseId);

  @override
  List<Object?> get props => [knowledgeBaseId];
}

/// 清除搜索结果
class ClearFanqieSearchResults extends KnowledgeBaseEvent {
  const ClearFanqieSearchResults();
}

/// 清除知识库详情
class ClearKnowledgeBaseDetail extends KnowledgeBaseEvent {
  const ClearKnowledgeBaseDetail();
}

