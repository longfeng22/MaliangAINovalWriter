/// 知识库仓库实现
library;

import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/knowledge_base_repository.dart';
import 'package:ainoval/utils/logger.dart';

class KnowledgeBaseRepositoryImpl implements KnowledgeBaseRepository {
  final ApiClient _apiClient;

  KnowledgeBaseRepositoryImpl(this._apiClient);

  @override
  Future<List<FanqieNovelInfo>> searchFanqieNovels(String query) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '搜索番茄小说: $query');
      
      final response = await _apiClient.getWithParams(
        '/knowledge-bases/fanqie/search',
        queryParameters: {'query': query},
      );

      final List<dynamic> novels = response['novels'] as List<dynamic>;
      return novels
          .map((json) => FanqieNovelInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '搜索番茄小说失败', e);
      rethrow;
    }
  }

  @override
  Future<FanqieNovelInfo> getFanqieNovelDetail(String novelId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '获取番茄小说详情: $novelId');
      
      final response = await _apiClient.get('/knowledge-bases/fanqie/$novelId');
      return FanqieNovelInfo.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '获取番茄小说详情失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeBaseCacheStatusResponse> checkCacheStatus(
      String fanqieNovelId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '检查缓存状态: $fanqieNovelId');
      
      final response = await _apiClient.get(
        '/knowledge-bases/fanqie/$fanqieNovelId/cache-status',
      );
      
      return KnowledgeBaseCacheStatusResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '检查缓存状态失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeExtractionTaskResponse> extractFromFanqieNovel({
    required String fanqieNovelId,
    List<String>? extractionTypes,
  }) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '从番茄小说提取知识库: $fanqieNovelId');
      
      final response = await _apiClient.post(
        '/knowledge-bases/extract/fanqie',
        data: {
          'fanqieNovelId': fanqieNovelId,
          if (extractionTypes != null) 'extractionTypes': extractionTypes,
        },
      );
      
      return KnowledgeExtractionTaskResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '提取知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeExtractionTaskResponse> extractFromText({
    required String title,
    required String content,
    String? description,
    required List<String> extractionTypes,
    required String modelConfigId,
    required String modelType,
  }) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '从用户文本提取知识库: $title');
      
      final response = await _apiClient.post(
        '/knowledge-bases/extract/text',
        data: {
          'title': title,
          'content': content,
          'description': description,
          'extractionTypes': extractionTypes,
          'modelConfigId': modelConfigId,
          'modelType': modelType,
        },
      );
      
      return KnowledgeExtractionTaskResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '提取知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeExtractionTaskResponse> extractFromPreviewSession({
    required String previewSessionId,
    required String title,
    String? description,
    required List<String> extractionTypes,
    required String modelConfigId,
    required String modelType,
    int? chapterLimit,
  }) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '从预览会话提取知识库: previewSessionId=$previewSessionId, title=$title, chapterLimit=$chapterLimit');
      
      final data = {
        'previewSessionId': previewSessionId,
        'title': title,
        'description': description,
        'extractionTypes': extractionTypes,
        'modelConfigId': modelConfigId,
        'modelType': modelType,
      };
      
      // 只有在有章节限制时才添加该字段
      if (chapterLimit != null) {
        data['chapterLimit'] = chapterLimit;
      }
      
      final response = await _apiClient.post(
        '/knowledge-bases/extract/from-preview',
        data: data,
      );
      
      return KnowledgeExtractionTaskResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '从预览会话提取知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeExtractionTaskResponse> getExtractionTaskStatus(
      String taskId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '获取任务状态: $taskId');
      
      final response = await _apiClient.get(
        '/knowledge-bases/extraction-task/$taskId',
      );
      
      return KnowledgeExtractionTaskResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '获取任务状态失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeBaseListResponse> queryPublicKnowledgeBases({
    String? keyword,
    List<String>? tags,
    String? completionStatus,
    String sortBy = 'likeCount',
    String sortOrder = 'desc',
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '查询公共知识库: page=$page');
      
      final queryParams = <String, dynamic>{
        'sortBy': sortBy,
        'sortOrder': sortOrder,
        'page': page,
        'size': size,
      };
      
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }
      if (tags != null && tags.isNotEmpty) {
        queryParams['tags'] = tags;
      }
      if (completionStatus != null && completionStatus.isNotEmpty) {
        queryParams['completionStatus'] = completionStatus;
      }
      
      final response = await _apiClient.getWithParams(
        '/knowledge-bases/public',
        queryParameters: queryParams,
      );
      
      return KnowledgeBaseListResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '查询公共知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<KnowledgeBaseListResponse> queryMyKnowledgeBases({
    String? keyword,
    String? sourceType,
    String sortBy = 'importTime',
    String sortOrder = 'desc',
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '查询我的知识库: page=$page, sourceType=$sourceType');
      
      final queryParams = <String, dynamic>{
        'sortBy': sortBy,
        'sortOrder': sortOrder,
        'page': page,
        'size': size,
      };
      
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }
      
      if (sourceType != null && sourceType.isNotEmpty) {
        queryParams['sourceType'] = sourceType;
      }
      
      final response = await _apiClient.getWithParams(
        '/knowledge-bases/my',
        queryParameters: queryParams,
      );
      
      return KnowledgeBaseListResponse.fromJson(
          response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '查询我的知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<NovelKnowledgeBase> getKnowledgeBaseDetail(
      String knowledgeBaseId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '获取知识库详情: $knowledgeBaseId');
      
      final response = await _apiClient.get(
        '/knowledge-bases/$knowledgeBaseId/detail', // ✅ 添加 /detail 后缀
      );
      
      return NovelKnowledgeBase.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '获取知识库详情失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> toggleLike(String knowledgeBaseId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '切换点赞: $knowledgeBaseId');
      
      final response = await _apiClient.post(
        '/knowledge-bases/$knowledgeBaseId/like',
        data: {},
      );
      
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '切换点赞失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> togglePublic(String knowledgeBaseId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '切换公开状态: $knowledgeBaseId');
      
      final response = await _apiClient.post(
        '/knowledge-bases/$knowledgeBaseId/toggle-public',
        data: {},
      );
      
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '切换公开状态失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> addToNovel(
      String knowledgeBaseId, String novelId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '添加到小说: $knowledgeBaseId -> $novelId');
      
      final response = await _apiClient.post(
        '/knowledge-bases/$knowledgeBaseId/add-to-novel',
        data: {'novelId': novelId},
      );
      
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '添加到小说失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> addToMyKnowledgeBase(String knowledgeBaseId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '添加到我的知识库: $knowledgeBaseId');
      
      final response = await _apiClient.post(
        '/knowledge-bases/$knowledgeBaseId/add-to-my',
        data: {},
      );
      
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '添加到我的知识库失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> removeFromMyKnowledgeBase(String knowledgeBaseId) async {
    try {
      AppLogger.i('KnowledgeBaseRepository', '从我的知识库删除: $knowledgeBaseId');
      
      final response = await _apiClient.delete(
        '/knowledge-bases/$knowledgeBaseId/remove-from-my',
      );
      
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '从我的知识库删除失败', e);
      rethrow;
    }
  }

  @override
  Future<bool> isInMyKnowledgeBase(String knowledgeBaseId) async {
    try {
      AppLogger.d('KnowledgeBaseRepository', '检查是否在我的知识库中: $knowledgeBaseId');
      
      final response = await _apiClient.get(
        '/knowledge-bases/$knowledgeBaseId/is-in-my',
      );
      
      return (response as Map<String, dynamic>)['isInMyKnowledgeBase'] as bool? ?? false;
    } catch (e) {
      AppLogger.e('KnowledgeBaseRepository', '检查是否在我的知识库中失败', e);
      rethrow;
    }
  }
}

