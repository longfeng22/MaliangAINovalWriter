/// 通用审核Repository接口
/// 统一管理各类内容的审核功能

import '../../../../models/admin/review_models.dart';

abstract class ReviewRepository {
  /// 获取待审核项列表
  Future<List<ReviewItem>> getPendingReviewItems({
    ReviewItemType? type,
    int page = 0,
    int size = 20,
    String? sortBy,
    String? sortDir,
  });

  /// 获取所有审核项列表（支持筛选）
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
  });

  /// 获取审核项详情
  Future<ReviewItem> getReviewItemDetail({
    required String itemId,
    required ReviewItemType type,
  });

  /// 审核项目（通过或拒绝）
  Future<void> reviewItem({
    required String itemId,
    required ReviewItemType type,
    required ReviewDecision decision,
  });

  /// 批量审核
  Future<void> batchReview({
    required List<String> itemIds,
    required ReviewItemType type,
    required ReviewDecision decision,
  });

  /// 获取审核统计信息
  Future<Map<String, dynamic>> getReviewStatistics({
    ReviewItemType? type,
    DateTime? startDate,
    DateTime? endDate,
  });
}






