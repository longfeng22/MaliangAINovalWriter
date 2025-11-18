/// 通用审核Repository实现
/// 整合策略、增强提示词等多种类型的审核

import '../../../../models/admin/review_models.dart';
import '../../../../utils/logger.dart';
import '../../../../utils/date_time_parser.dart';
import '../../base/api_client.dart';
import '../../base/api_exception.dart';
import '../setting_generation_repository.dart';
import '../impl/admin_repository_impl.dart';
import 'review_repository.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  static const String _tag = 'ReviewRepository';

  final ApiClient _apiClient;
  final SettingGenerationRepository _strategyRepo;
  final AdminRepositoryImpl _adminRepo;

  ReviewRepositoryImpl({
    required ApiClient apiClient,
    required SettingGenerationRepository strategyRepo,
    required AdminRepositoryImpl adminRepo,
  })  : _apiClient = apiClient,
        _strategyRepo = strategyRepo,
        _adminRepo = adminRepo;

  @override
  Future<List<ReviewItem>> getPendingReviewItems({
    ReviewItemType? type,
    int page = 0,
    int size = 20,
    String? sortBy,
    String? sortDir,
  }) async {
    try {
      AppLogger.info(_tag, '获取待审核项列表: type=$type, page=$page, size=$size');

      final items = <ReviewItem>[];

      // 根据类型获取不同的待审核项
      if (type == null || type == ReviewItemType.strategy) {
        final strategies = await _strategyRepo.getPendingStrategies(
          page: page,
          size: size,
        );
        items.addAll(strategies.map((s) => ReviewItem.fromJson(s, ReviewItemType.strategy)));
      }

      if (type == null || type == ReviewItemType.enhancedTemplate) {
        final templates = await _adminRepo.getPendingEnhancedTemplates();
        items.addAll(templates.map((t) => ReviewItem.fromJson(t.toJson(), ReviewItemType.enhancedTemplate)));
      }

      // TODO: 添加其他类型的审核项

      AppLogger.info(_tag, '获取待审核项成功: ${items.length} 项');
      return items;
    } catch (e) {
      AppLogger.error(_tag, '获取待审核项失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getReviewItems({
    ReviewItemType? type,
    ReviewStatus? status,
    String? featureType,
    String? keyword,
    DateTime? startDate,
    DateTime? endDate,
    int page = 0,
    int size = 20,
    String? sortBy,
    String? sortDir,
  }) async {
    try {
      AppLogger.info(_tag, '获取审核项列表: type=$type, status=$status, featureType=$featureType, page=$page');

      // 构建查询参数
      final params = <String, dynamic>{
        'page': page,
        'size': size,
      };
      if (type != null) params['type'] = type.value;
      if (status != null) params['status'] = status.value;
      if (featureType != null && featureType.isNotEmpty) params['featureType'] = featureType;
      if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
      if (startDate != null) params['startDate'] = startDate.toIso8601String();
      if (endDate != null) params['endDate'] = endDate.toIso8601String();
      if (sortBy != null) params['sortBy'] = sortBy;
      if (sortDir != null) params['sortDir'] = sortDir;

      // 调用统一审核接口
      final result = await _apiClient.getWithParams(
        '/admin/reviews',
        queryParameters: params,
      );

      if (result is Map<String, dynamic>) {
        // ApiResponse 结构: { success, data: { data: [], totalElements, ... } }
        final responseData = result['data'];
        
        if (responseData is Map<String, dynamic>) {
          // 从嵌套的 data 中获取实际的列表
          final dataList = responseData['data'] as List? ?? [];
          // 使用公共函数批量解析时间字段
          final parsedData = parseResponseListTimestamps(dataList);
          final items = parsedData.map((item) {
            final itemType = ReviewItemType.fromValue(item['type'] as String? ?? 'USER_CONTENT');
            return ReviewItem.fromJson(item, itemType);
          }).toList();

          return {
            'items': items,
            'totalElements': responseData['totalElements'] ?? items.length,
            'totalPages': responseData['totalPages'] ?? 1,
            'currentPage': responseData['currentPage'] ?? page,
            'pageSize': responseData['pageSize'] ?? size,
          };
        } else if (responseData is List) {
          // 兼容直接返回列表的情况
          final parsedData = parseResponseListTimestamps(responseData);
          final items = parsedData.map((item) {
            final itemType = ReviewItemType.fromValue(item['type'] as String? ?? 'USER_CONTENT');
            return ReviewItem.fromJson(item, itemType);
          }).toList();

          return {
            'items': items,
            'totalElements': items.length,
            'totalPages': 1,
            'currentPage': page,
            'pageSize': size,
          };
        }
      }

      throw ApiException(-1, '审核项列表响应格式错误');
    } catch (e) {
      AppLogger.error(_tag, '获取审核项列表失败', e);
      rethrow;
    }
  }

  @override
  Future<ReviewItem> getReviewItemDetail({
    required String itemId,
    required ReviewItemType type,
  }) async {
    try {
      AppLogger.info(_tag, '获取审核项详情: id=$itemId, type=$type');

      // 调用统一审核接口
      final result = await _apiClient.getWithParams(
        '/admin/reviews/$itemId',
        queryParameters: {'type': type.value},
      );

      Map<String, dynamic> data;
      
      if (result is Map<String, dynamic>) {
        // ApiResponse 结构: { success, data: { id, type, title, ... } }
        final responseData = result['data'];
        
        if (responseData is Map<String, dynamic>) {
          data = responseData;
        } else {
          // 兼容直接返回数据的情况
          data = result;
        }
      } else {
        throw ApiException(-1, '审核项详情响应格式错误');
      }

      return ReviewItem.fromJson(data, type);
    } catch (e) {
      AppLogger.error(_tag, '获取审核项详情失败', e);
      rethrow;
    }
  }

  @override
  Future<void> reviewItem({
    required String itemId,
    required ReviewItemType type,
    required ReviewDecision decision,
  }) async {
    try {
      AppLogger.info(_tag, '审核项目: id=$itemId, type=$type, decision=${decision.decision}');

      // 调用统一审核接口
      await _apiClient.post(
        '/admin/reviews/$itemId/review?type=${type.value}',
        data: decision.toJson(),
      );

      AppLogger.info(_tag, '审核完成');
    } catch (e) {
      AppLogger.error(_tag, '审核失败', e);
      rethrow;
    }
  }

  @override
  Future<void> batchReview({
    required List<String> itemIds,
    required ReviewItemType type,
    required ReviewDecision decision,
  }) async {
    try {
      AppLogger.info(_tag, '批量审核: count=${itemIds.length}, type=$type');

      final requestData = {
        'itemIds': itemIds,
        'type': type.value,
        ...decision.toJson(),
      };

      await _apiClient.post(
        '/admin/reviews/batch',
        data: requestData,
      );

      AppLogger.info(_tag, '批量审核完成');
    } catch (e) {
      AppLogger.error(_tag, '批量审核失败', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getReviewStatistics({
    ReviewItemType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      AppLogger.info(_tag, '获取审核统计: type=$type');

      final params = <String, dynamic>{};
      if (type != null) params['type'] = type.value;
      if (startDate != null) params['startDate'] = startDate.toIso8601String();
      if (endDate != null) params['endDate'] = endDate.toIso8601String();

      final result = await _apiClient.getWithParams(
        '/admin/reviews/statistics',
        queryParameters: params,
      );

      if (result is Map<String, dynamic>) {
        // ApiResponse 结构: { success, data: { totalPending, ... } }
        final responseData = result['data'];
        
        if (responseData is Map<String, dynamic>) {
          return responseData;
        }
        
        // 兼容直接返回统计数据的情况
        return result;
      }

      return {
        'totalPending': 0,
        'totalApproved': 0,
        'totalRejected': 0,
      };
    } catch (e) {
      AppLogger.error(_tag, '获取审核统计失败', e);
      return {
        'totalPending': 0,
        'totalApproved': 0,
        'totalRejected': 0,
      };
    }
  }
}

