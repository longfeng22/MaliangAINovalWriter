/// 知识库状态
library;

import 'package:equatable/equatable.dart';
import 'package:ainoval/models/knowledge_base_models.dart';

abstract class KnowledgeBaseState extends Equatable {
  const KnowledgeBaseState();

  @override
  List<Object?> get props => [];
}

/// 初始状态
class KnowledgeBaseInitial extends KnowledgeBaseState {
  const KnowledgeBaseInitial();
}

/// 加载中状态
class KnowledgeBaseLoading extends KnowledgeBaseState {
  const KnowledgeBaseLoading();
}

/// 番茄小说搜索结果加载完成
class FanqieSearchLoaded extends KnowledgeBaseState {
  final List<FanqieNovelInfo> novels;
  final String searchQuery;

  const FanqieSearchLoaded({
    required this.novels,
    required this.searchQuery,
  });

  @override
  List<Object?> get props => [novels, searchQuery];
}

/// 番茄小说详情加载完成
class FanqieNovelDetailLoaded extends KnowledgeBaseState {
  final FanqieNovelInfo novelDetail;
  final KnowledgeBaseCacheStatusResponse? cacheStatus;

  const FanqieNovelDetailLoaded({
    required this.novelDetail,
    this.cacheStatus,
  });

  @override
  List<Object?> get props => [novelDetail, cacheStatus];
}

/// 缓存状态检查完成
class CacheStatusChecked extends KnowledgeBaseState {
  final KnowledgeBaseCacheStatusResponse cacheStatus;

  const CacheStatusChecked(this.cacheStatus);

  @override
  List<Object?> get props => [cacheStatus];
}

/// 知识库列表加载完成
class KnowledgeBaseListLoaded extends KnowledgeBaseState {
  final KnowledgeBaseListResponse response;
  final bool isPublicList;  // true: 公共知识库, false: 我的知识库

  const KnowledgeBaseListLoaded({
    required this.response,
    required this.isPublicList,
  });

  @override
  List<Object?> get props => [response, isPublicList];
}

/// 知识库详情加载完成
class KnowledgeBaseDetailLoaded extends KnowledgeBaseState {
  final NovelKnowledgeBase knowledgeBase;
  final bool isLiked;

  const KnowledgeBaseDetailLoaded({
    required this.knowledgeBase,
    required this.isLiked,
  });

  KnowledgeBaseDetailLoaded copyWith({
    NovelKnowledgeBase? knowledgeBase,
    bool? isLiked,
  }) {
    return KnowledgeBaseDetailLoaded(
      knowledgeBase: knowledgeBase ?? this.knowledgeBase,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  @override
  List<Object?> get props => [knowledgeBase, isLiked];
}

/// 提取任务创建成功
class ExtractionTaskCreated extends KnowledgeBaseState {
  final KnowledgeExtractionTaskResponse taskResponse;

  const ExtractionTaskCreated(this.taskResponse);

  @override
  List<Object?> get props => [taskResponse];
}

/// 提取任务状态更新
class ExtractionTaskStatusUpdated extends KnowledgeBaseState {
  final KnowledgeExtractionTaskResponse taskResponse;

  const ExtractionTaskStatusUpdated(this.taskResponse);

  @override
  List<Object?> get props => [taskResponse];
}

/// 操作成功状态（点赞、添加到小说等）
class KnowledgeBaseOperationSuccess extends KnowledgeBaseState {
  final String message;
  final Map<String, dynamic>? data;

  const KnowledgeBaseOperationSuccess({
    required this.message,
    this.data,
  });

  @override
  List<Object?> get props => [message, data];
}

/// 错误状态
class KnowledgeBaseError extends KnowledgeBaseState {
  final String message;
  final Object? error;

  const KnowledgeBaseError({
    required this.message,
    this.error,
  });

  @override
  List<Object?> get props => [message, error];
}

