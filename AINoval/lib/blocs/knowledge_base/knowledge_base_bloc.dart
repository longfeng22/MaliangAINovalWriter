/// 知识库BLoC
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/services/api_service/repositories/knowledge_base_repository.dart';
import 'package:ainoval/utils/logger.dart';

class KnowledgeBaseBloc extends Bloc<KnowledgeBaseEvent, KnowledgeBaseState> {
  final KnowledgeBaseRepository _repository;
  
  // 暴露repository供外部使用
  KnowledgeBaseRepository get repository => _repository;

  KnowledgeBaseBloc(this._repository) : super(const KnowledgeBaseInitial()) {
    on<SearchFanqieNovels>(_onSearchFanqieNovels);
    on<LoadFanqieNovelDetail>(_onLoadFanqieNovelDetail);
    on<CheckCacheStatus>(_onCheckCacheStatus);
    on<ExtractFromFanqieNovel>(_onExtractFromFanqieNovel);
    on<ExtractFromText>(_onExtractFromText);
    on<ExtractFromPreviewSession>(_onExtractFromPreviewSession);
    on<LoadExtractionTaskStatus>(_onLoadExtractionTaskStatus);
    on<LoadPublicKnowledgeBases>(_onLoadPublicKnowledgeBases);
    on<LoadMyKnowledgeBases>(_onLoadMyKnowledgeBases);
    on<LoadKnowledgeBaseDetail>(_onLoadKnowledgeBaseDetail);
    on<ToggleKnowledgeBaseLike>(_onToggleKnowledgeBaseLike);
    on<ToggleKnowledgeBasePublic>(_onToggleKnowledgeBasePublic);
    on<AddKnowledgeBaseToNovel>(_onAddKnowledgeBaseToNovel);
    on<AddToMyKnowledgeBase>(_onAddToMyKnowledgeBase);
    on<RemoveFromMyKnowledgeBase>(_onRemoveFromMyKnowledgeBase);
    on<ClearFanqieSearchResults>(_onClearFanqieSearchResults);
    on<ClearKnowledgeBaseDetail>(_onClearKnowledgeBaseDetail);
  }

  Future<void> _onSearchFanqieNovels(
    SearchFanqieNovels event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '搜索番茄小说: ${event.query}');
      final novels = await _repository.searchFanqieNovels(event.query);
      
      emit(FanqieSearchLoaded(
        novels: novels,
        searchQuery: event.query,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '搜索番茄小说失败', e);
      emit(KnowledgeBaseError(
        message: '搜索失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onLoadFanqieNovelDetail(
    LoadFanqieNovelDetail event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '加载番茄小说详情: ${event.novelId}');
      
      // 并行加载详情和缓存状态
      final detail = await _repository.getFanqieNovelDetail(event.novelId);
      final cacheStatus = await _repository.checkCacheStatus(event.novelId);
      
      emit(FanqieNovelDetailLoaded(
        novelDetail: detail,
        cacheStatus: cacheStatus,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '加载番茄小说详情失败', e);
      emit(KnowledgeBaseError(
        message: '加载详情失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onCheckCacheStatus(
    CheckCacheStatus event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '检查缓存状态: ${event.fanqieNovelId}');
      final cacheStatus = await _repository.checkCacheStatus(event.fanqieNovelId);
      
      AppLogger.i('KnowledgeBaseBloc', '缓存状态: cached=${cacheStatus.cached}, kbId=${cacheStatus.knowledgeBaseId}');
      
      // ✅ 发出缓存状态检查完成事件
      emit(CacheStatusChecked(cacheStatus));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '检查缓存状态失败', e);
      emit(KnowledgeBaseError(
        message: '检查缓存状态失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onExtractFromFanqieNovel(
    ExtractFromFanqieNovel event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '从番茄小说提取知识库: ${event.fanqieNovelId}');
      
      final taskResponse = await _repository.extractFromFanqieNovel(
        fanqieNovelId: event.fanqieNovelId,
        extractionTypes: event.extractionTypes,
      );
      
      emit(ExtractionTaskCreated(taskResponse));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '提取知识库失败', e);
      emit(KnowledgeBaseError(
        message: '提取失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onExtractFromText(
    ExtractFromText event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '从用户文本提取知识库: ${event.title}');
      
      final taskResponse = await _repository.extractFromText(
        title: event.title,
        content: event.content,
        description: event.description,
        extractionTypes: event.extractionTypes,
        modelConfigId: event.modelConfigId,
        modelType: event.modelType,
      );
      
      emit(ExtractionTaskCreated(taskResponse));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '提取知识库失败', e);
      emit(KnowledgeBaseError(
        message: '提取失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onExtractFromPreviewSession(
    ExtractFromPreviewSession event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '从预览会话提取知识库: ${event.previewSessionId}, title=${event.title}, chapterLimit=${event.chapterLimit}');
      
      final taskResponse = await _repository.extractFromPreviewSession(
        previewSessionId: event.previewSessionId,
        title: event.title,
        description: event.description,
        extractionTypes: event.extractionTypes,
        modelConfigId: event.modelConfigId,
        modelType: event.modelType,
        chapterLimit: event.chapterLimit,
      );
      
      emit(ExtractionTaskCreated(taskResponse));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '从预览会话提取知识库失败', e);
      emit(KnowledgeBaseError(
        message: '提取失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onLoadExtractionTaskStatus(
    LoadExtractionTaskStatus event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '获取任务状态: ${event.taskId}');
      
      final taskResponse = await _repository.getExtractionTaskStatus(event.taskId);
      
      emit(ExtractionTaskStatusUpdated(taskResponse));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '获取任务状态失败', e);
      emit(KnowledgeBaseError(
        message: '获取任务状态失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onLoadPublicKnowledgeBases(
    LoadPublicKnowledgeBases event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '加载公共知识库列表: page=${event.page}');
      
      final response = await _repository.queryPublicKnowledgeBases(
        keyword: event.keyword,
        tags: event.tags,
        completionStatus: event.completionStatus,
        sortBy: event.sortBy,
        sortOrder: event.sortOrder,
        page: event.page,
        size: event.size,
      );
      
      emit(KnowledgeBaseListLoaded(
        response: response,
        isPublicList: true,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '加载公共知识库列表失败', e);
      emit(KnowledgeBaseError(
        message: '加载列表失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onLoadMyKnowledgeBases(
    LoadMyKnowledgeBases event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '加载我的知识库列表: page=${event.page}, sourceType=${event.sourceType}');
      
      final response = await _repository.queryMyKnowledgeBases(
        keyword: event.keyword,
        sourceType: event.sourceType,
        sortBy: event.sortBy,
        sortOrder: event.sortOrder,
        page: event.page,
        size: event.size,
      );
      
      emit(KnowledgeBaseListLoaded(
        response: response,
        isPublicList: false,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '加载我的知识库列表失败', e);
      emit(KnowledgeBaseError(
        message: '加载列表失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onLoadKnowledgeBaseDetail(
    LoadKnowledgeBaseDetail event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      emit(const KnowledgeBaseLoading());
      
      AppLogger.i('KnowledgeBaseBloc', '加载知识库详情: ${event.knowledgeBaseId}');
      
      final knowledgeBase = await _repository.getKnowledgeBaseDetail(event.knowledgeBaseId);
      
      // 判断当前用户是否点赞
      // TODO: 从AuthBloc获取当前用户ID
      final isLiked = false; // knowledgeBase.likedUserIds?.contains(currentUserId) ?? false;
      
      emit(KnowledgeBaseDetailLoaded(
        knowledgeBase: knowledgeBase,
        isLiked: isLiked,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '加载知识库详情失败', e);
      emit(KnowledgeBaseError(
        message: '加载详情失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onToggleKnowledgeBaseLike(
    ToggleKnowledgeBaseLike event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '切换点赞: ${event.knowledgeBaseId}');
      
      final result = await _repository.toggleLike(event.knowledgeBaseId);
      
      // 如果当前是详情页面，更新点赞状态
      if (state is KnowledgeBaseDetailLoaded) {
        final currentState = state as KnowledgeBaseDetailLoaded;
        final isLiked = result['isLiked'] as bool? ?? false;
        final likeCount = result['likeCount'] as int? ?? currentState.knowledgeBase.likeCount;
        
        AppLogger.i('KnowledgeBaseBloc', '点赞切换成功: isLiked=$isLiked, likeCount=$likeCount');
        
        // ✅ 只发出一次状态更新，保持在详情页
        emit(currentState.copyWith(
          isLiked: isLiked,
          // TODO: 需要更新 knowledgeBase 的 likeCount 字段
        ));
      }
      
      // ✅ 移除 KnowledgeBaseOperationSuccess，避免状态切换导致页面变成加载状态
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '切换点赞失败', e);
      
      // ✅ 错误时保持当前状态，只显示提示
      // 不发出 KnowledgeBaseError，避免页面显示错误页面
      AppLogger.e('KnowledgeBaseBloc', '点赞失败，但保持当前页面状态');
    }
  }

  Future<void> _onToggleKnowledgeBasePublic(
    ToggleKnowledgeBasePublic event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '切换公开状态: ${event.knowledgeBaseId}');
      
      final result = await _repository.togglePublic(event.knowledgeBaseId);
      final isPublic = result['isPublic'] as bool? ?? false;
      final message = result['message'] as String? ?? (isPublic ? '已分享到公共知识库' : '已设为私密');
      
      emit(KnowledgeBaseOperationSuccess(
        message: message,
        data: result,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '切换公开状态失败', e);
      emit(KnowledgeBaseError(
        message: '操作失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onAddKnowledgeBaseToNovel(
    AddKnowledgeBaseToNovel event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '添加到小说: ${event.knowledgeBaseId} -> ${event.novelId}');
      
      final result = await _repository.addToNovel(event.knowledgeBaseId, event.novelId);
      
      emit(KnowledgeBaseOperationSuccess(
        message: result['message'] as String? ?? '添加成功',
        data: result,
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '添加到小说失败', e);
      emit(KnowledgeBaseError(
        message: '添加失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onAddToMyKnowledgeBase(
    AddToMyKnowledgeBase event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '添加到我的知识库: ${event.knowledgeBaseId}');
      
      await _repository.addToMyKnowledgeBase(event.knowledgeBaseId);
      
      emit(KnowledgeBaseOperationSuccess(
        message: '已添加到我的知识库',
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '添加到我的知识库失败', e);
      emit(KnowledgeBaseError(
        message: '添加失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onRemoveFromMyKnowledgeBase(
    RemoveFromMyKnowledgeBase event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    try {
      AppLogger.i('KnowledgeBaseBloc', '从我的知识库删除: ${event.knowledgeBaseId}');
      
      await _repository.removeFromMyKnowledgeBase(event.knowledgeBaseId);
      
      emit(KnowledgeBaseOperationSuccess(
        message: '已从我的知识库删除',
      ));
    } catch (e) {
      AppLogger.e('KnowledgeBaseBloc', '从我的知识库删除失败', e);
      emit(KnowledgeBaseError(
        message: '删除失败: ${e.toString()}',
        error: e,
      ));
    }
  }

  Future<void> _onClearFanqieSearchResults(
    ClearFanqieSearchResults event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    emit(const KnowledgeBaseInitial());
  }

  Future<void> _onClearKnowledgeBaseDetail(
    ClearKnowledgeBaseDetail event,
    Emitter<KnowledgeBaseState> emit,
  ) async {
    emit(const KnowledgeBaseInitial());
  }
}

