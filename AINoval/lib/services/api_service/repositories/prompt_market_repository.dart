import '../../../models/prompt_models.dart';
import '../../../utils/logger.dart';
import '../base/api_client.dart' show ApiClient;

/// 提示词市场Repository
/// 提供提示词模板的市场化功能API
class PromptMarketRepository {
  static const String _tag = 'PromptMarketRepository';
  
  final ApiClient _apiClient;

  PromptMarketRepository(this._apiClient);

  /// 获取公开提示词模板列表
  /// 
  /// [featureType] 功能类型，为空则返回所有类型
  /// [page] 页码
  /// [size] 每页数量
  /// [sortBy] 排序方式：latest(最新), popular(最受欢迎), mostUsed(最多使用), rating(评分)
  Future<List<Map<String, dynamic>>> getPublicTemplates({
    AIFeatureType? featureType,
    int page = 0,
    int size = 20,
    String sortBy = 'popular',
  }) async {
    try {
      AppLogger.info(_tag, '获取公开提示词模板: featureType=$featureType, page=$page, size=$size, sortBy=$sortBy');
      
      final queryParams = {
        'page': page,
        'size': size,
        'sortBy': sortBy,
      };
      
      if (featureType != null) {
        queryParams['featureType'] = featureType.toApiString();
      }
      
      final response = await _apiClient.getWithParams(
        '/prompt-market/templates',
        queryParameters: queryParams,
      );
      
      final data = response['data'] as List;
      AppLogger.info(_tag, '✅ 获取到 ${data.length} 个公开模板');
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error(_tag, '获取公开模板异常: $e');
      rethrow;
    }
  }

  /// 搜索公开提示词模板
  /// 
  /// [keyword] 搜索关键词
  /// [featureType] 功能类型
  /// [page] 页码
  /// [size] 每页数量
  Future<List<Map<String, dynamic>>> searchTemplates({
    required String keyword,
    AIFeatureType? featureType,
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.info(_tag, '搜索公开模板: keyword=$keyword, featureType=$featureType');
      
      final queryParams = {
        'keyword': keyword,
        'page': page,
        'size': size,
      };
      
      if (featureType != null) {
        queryParams['featureType'] = featureType.toApiString();
      }
      
      final response = await _apiClient.getWithParams(
        '/prompt-market/templates/search',
        queryParameters: queryParams,
      );
      
      final data = response['data'] as List;
      AppLogger.info(_tag, '✅ 搜索到 ${data.length} 个模板');
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error(_tag, '搜索异常: $e');
      rethrow;
    }
  }

  /// 点赞/取消点赞模板
  /// 
  /// [templateId] 模板ID
  /// 返回: {isLiked: bool, likeCount: int}
  Future<Map<String, dynamic>> toggleLike(String templateId) async {
    try {
      AppLogger.info(_tag, '切换点赞状态: templateId=$templateId');
      
      final response = await _apiClient.post(
        '/prompt-market/templates/$templateId/like',
      );
      
      final data = response['data'] as Map<String, dynamic>;
      AppLogger.info(_tag, '✅ 点赞状态切换成功: isLiked=${data['isLiked']}, likeCount=${data['likeCount']}');
      return data;
    } catch (e) {
      AppLogger.error(_tag, '点赞操作异常: $e');
      rethrow;
    }
  }

  /// 收藏/取消收藏模板
  /// 
  /// [templateId] 模板ID
  /// 返回: {isFavorite: bool, favoriteCount: int}
  Future<Map<String, dynamic>> toggleFavorite(String templateId) async {
    try {
      AppLogger.info(_tag, '切换收藏状态: templateId=$templateId');
      
      final response = await _apiClient.post(
        '/prompt-market/templates/$templateId/favorite',
      );
      
      final data = response['data'] as Map<String, dynamic>;
      AppLogger.info(_tag, '✅ 收藏状态切换成功: isFavorite=${data['isFavorite']}, favoriteCount=${data['favoriteCount']}');
      return data;
    } catch (e) {
      AppLogger.error(_tag, '收藏操作异常: $e');
      rethrow;
    }
  }

  /// 分享模板（提交审核）
  /// 
  /// [templateId] 模板ID
  Future<void> shareTemplate(String templateId, {bool? hidePrompts}) async {
    try {
      AppLogger.info(_tag, '🚀 准备分享模板: templateId=$templateId, hidePrompts=$hidePrompts');
      
      final requestData = hidePrompts != null ? {'hidePrompts': hidePrompts} : null;
      AppLogger.info(_tag, '📦 请求数据: $requestData');
      
      await _apiClient.post(
        '/prompt-market/templates/$templateId/share',
        data: requestData,
      );
      
      AppLogger.info(_tag, '✅ 模板分享成功');
    } catch (e) {
      AppLogger.error(_tag, '❌ 分享异常: $e');
      rethrow;
    }
  }

  /// 设置提示词隐藏状态
  /// 
  /// [templateId] 模板ID
  /// [hide] 是否隐藏
  Future<Map<String, dynamic>> setHidePrompts(String templateId, bool hide) async {
    try {
      AppLogger.info(_tag, '设置提示词隐藏: templateId=$templateId, hide=$hide');
      
      final response = await _apiClient.post(
        '/prompt-market/templates/$templateId/hide-prompts',
        data: {'hide': hide},
      );
      
      final data = response['data'] as Map<String, dynamic>;
      AppLogger.info(_tag, '✅ 提示词隐藏状态设置成功: hidePrompts=${data['hidePrompts']}');
      return data;
    } catch (e) {
      AppLogger.error(_tag, '设置异常: $e');
      rethrow;
    }
  }

  /// 记录模板使用并奖励积分
  /// 
  /// [templateId] 模板ID
  Future<void> recordUsage(String templateId) async {
    try {
      AppLogger.info(_tag, '记录模板使用: templateId=$templateId');
      
      await _apiClient.post(
        '/prompt-market/templates/$templateId/use',
      );
      
      AppLogger.info(_tag, '✅ 使用记录成功');
    } catch (e) {
      AppLogger.w(_tag, '使用记录异常: $e');
      // 不抛出异常
    }
  }

  /// 获取模板的积分奖励信息
  /// 
  /// [templateId] 模板ID
  /// 返回: {points: int, description: string, featureType: string}
  Future<Map<String, dynamic>> getRewardInfo(String templateId) async {
    try {
      AppLogger.info(_tag, '获取积分奖励信息: templateId=$templateId');
      
      final response = await _apiClient.get(
        '/prompt-market/templates/$templateId/reward-info',
      );
      
      final data = response['data'] as Map<String, dynamic>;
      AppLogger.info(_tag, '✅ 积分信息: points=${data['points']}, description=${data['description']}');
      return data;
    } catch (e) {
      AppLogger.error(_tag, '获取积分信息异常: $e');
      rethrow;
    }
  }

  /// 获取所有功能类型的积分配置
  /// 
  /// 返回: Map<AIFeatureType的字符串, 积分值>
  Future<Map<String, int>> getAllRewardPoints() async {
    try {
      AppLogger.info(_tag, '获取所有功能类型的积分配置');
      
      final response = await _apiClient.get(
        '/prompt-market/reward-points',
      );
      
      final data = response['data'] as Map<String, dynamic>;
      final result = <String, int>{};
      data.forEach((key, value) {
        result[key] = (value as num).toInt();
      });
      AppLogger.info(_tag, '✅ 返回 ${result.length} 个功能类型的积分配置');
      return result;
    } catch (e) {
      AppLogger.error(_tag, '获取积分配置异常: $e');
      rethrow;
    }
  }

  /// 获取市场统计信息
  /// 
  /// 返回: 市场统计数据
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      AppLogger.info(_tag, '获取市场统计信息');
      
      final response = await _apiClient.get(
        '/prompt-market/statistics',
      );
      
      final data = response['data'] as Map<String, dynamic>;
      AppLogger.info(_tag, '✅ 市场统计: totalTemplates=${data['totalTemplates']}, totalAuthors=${data['totalAuthors']}');
      return data;
    } catch (e) {
      AppLogger.error(_tag, '获取统计信息异常: $e');
      rethrow;
    }
  }

  /// 获取用户自己的提示词模板列表
  /// 
  /// [featureType] 功能类型，为空则返回所有类型
  Future<List<Map<String, dynamic>>> getUserTemplates({
    AIFeatureType? featureType,
  }) async {
    try {
      AppLogger.info(_tag, '获取用户提示词模板: featureType=$featureType');
      
      final queryParams = <String, dynamic>{};
      if (featureType != null) {
        queryParams['featureType'] = featureType.toApiString();
      }
      
      final response = await _apiClient.getWithParams(
        '/prompt-templates',
        queryParameters: queryParams,
      );
      
      // 根据返回格式解析数据
      List<dynamic> data;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        data = response['data'] as List;
      } else if (response is List) {
        data = response;
      } else {
        throw Exception('响应格式错误');
      }
      
      AppLogger.info(_tag, '✅ 获取到 ${data.length} 个用户模板');
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error(_tag, '获取用户模板异常: $e');
      rethrow;
    }
  }

  /// 删除用户的提示词模板
  /// 
  /// [templateId] 模板ID
  Future<void> deleteTemplate(String templateId) async {
    try {
      AppLogger.info(_tag, '删除提示词模板: templateId=$templateId');
      
      await _apiClient.delete(
        '/prompt-templates/$templateId',
      );
      
      AppLogger.info(_tag, '✅ 删除模板成功');
    } catch (e) {
      AppLogger.error(_tag, '删除模板异常: $e');
      rethrow;
    }
  }
}

