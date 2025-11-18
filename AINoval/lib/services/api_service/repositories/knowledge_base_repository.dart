/// 知识库仓库服务
library;

import 'package:ainoval/models/knowledge_base_models.dart';

/// 知识库仓库接口
abstract class KnowledgeBaseRepository {
  /// 搜索番茄小说
  Future<List<FanqieNovelInfo>> searchFanqieNovels(String query);
  
  /// 获取番茄小说详情
  Future<FanqieNovelInfo> getFanqieNovelDetail(String novelId);
  
  /// 检查番茄小说缓存状态
  Future<KnowledgeBaseCacheStatusResponse> checkCacheStatus(String fanqieNovelId);
  
  /// 从番茄小说提取知识库（自动使用"chaishu"公共模型）
  Future<KnowledgeExtractionTaskResponse> extractFromFanqieNovel({
    required String fanqieNovelId,
    List<String>? extractionTypes,
  });
  
  /// 从用户文本提取知识库
  Future<KnowledgeExtractionTaskResponse> extractFromText({
    required String title,
    required String content,
    String? description,
    required List<String> extractionTypes,
    required String modelConfigId,
    required String modelType,
  });
  
  /// 从预览会话提取知识库
  Future<KnowledgeExtractionTaskResponse> extractFromPreviewSession({
    required String previewSessionId,
    required String title,
    String? description,
    required List<String> extractionTypes,
    required String modelConfigId,
    required String modelType,
    int? chapterLimit, // null表示整本，否则为前N章
  });
  
  /// 获取拆书任务状态
  Future<KnowledgeExtractionTaskResponse> getExtractionTaskStatus(String taskId);
  
  /// 查询公共知识库列表
  Future<KnowledgeBaseListResponse> queryPublicKnowledgeBases({
    String? keyword,
    List<String>? tags,
    String? completionStatus,
    String sortBy = 'likeCount',
    String sortOrder = 'desc',
    int page = 0,
    int size = 20,
  });
  
  /// 查询我的知识库列表
  Future<KnowledgeBaseListResponse> queryMyKnowledgeBases({
    String? keyword,
    String? sourceType, // null=全部, 'user_imported'=用户导入, 'fanqie_novel'=番茄小说
    String sortBy = 'importTime',
    String sortOrder = 'desc',
    int page = 0,
    int size = 20,
  });
  
  /// 获取知识库详情
  Future<NovelKnowledgeBase> getKnowledgeBaseDetail(String knowledgeBaseId);
  
  /// 切换点赞
  Future<Map<String, dynamic>> toggleLike(String knowledgeBaseId);
  
  /// 切换知识库公开状态
  Future<Map<String, dynamic>> togglePublic(String knowledgeBaseId);
  
  /// 将知识库添加到我的小说
  Future<Map<String, dynamic>> addToNovel(String knowledgeBaseId, String novelId);
  
  /// 添加到我的知识库
  Future<Map<String, dynamic>> addToMyKnowledgeBase(String knowledgeBaseId);
  
  /// 从我的知识库删除
  Future<Map<String, dynamic>> removeFromMyKnowledgeBase(String knowledgeBaseId);
  
  /// 检查是否在我的知识库中
  Future<bool> isInMyKnowledgeBase(String knowledgeBaseId);
}

