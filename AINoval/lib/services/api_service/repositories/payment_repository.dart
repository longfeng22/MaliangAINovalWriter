import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/utils/logger.dart';

enum PayChannel { wechat, alipay }

class PaymentOrderDto {
  final String id;
  final String outTradeNo;
  final String planId;
  final String paymentUrl;
  final String status;
  PaymentOrderDto({
    required this.id,
    required this.outTradeNo,
    required this.planId,
    required this.paymentUrl,
    required this.status,
  });

  factory PaymentOrderDto.fromJson(Map<String, dynamic> json) => PaymentOrderDto(
        id: json['id'] ?? '',
        outTradeNo: json['outTradeNo'] ?? '',
        planId: json['planId'] ?? '',
        paymentUrl: json['paymentUrl'] ?? '',
        status: json['status']?.toString() ?? '',
      );
}

class PaymentRepository {
  final ApiClient _apiClient;
  final String _tag = 'PaymentRepository';

  PaymentRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<PaymentOrderDto> createPayment({
    required String planId,
    required PayChannel channel,
    String? returnUrl,
  }) async {
    try {
      final body = {
        'planId': planId,
        'channel': channel.name.toUpperCase(),
        'returnUrl': returnUrl ?? 'http://localhost:18080/api/v1/payments/return/ALIPAY',
      };
      
      final res = await _apiClient.post('/payments/subscription/create', data: body);
      
      // 后端返回格式: { success: true, data: {...}, message: "success" }
      if (res is Map<String, dynamic> && res['success'] == true && res['data'] is Map<String, dynamic>) {
        return PaymentOrderDto.fromJson(res['data'] as Map<String, dynamic>);
      }
      
      // 处理错误情况
      final errorMsg = res is Map<String, dynamic> ? (res['message'] ?? '创建支付订单失败') : '创建支付订单失败';
      throw Exception(errorMsg);
    } catch (e) {
      AppLogger.e(_tag, '创建支付订单失败', e);
      rethrow;
    }
  }

  Future<PaymentOrderDto> createCreditPackPayment({
    required String planId,
    required PayChannel channel,
    String? returnUrl,
  }) async {
    try {
      final body = {
        'planId': planId,
        'channel': channel.name.toUpperCase(),
        'returnUrl': returnUrl ?? 'http://localhost:18080/api/v1/payments/return/ALIPAY',
      };
      
      final res = await _apiClient.post('/payments/credit-pack/create', data: body);
      
      // 后端返回格式: { success: true, data: {...}, message: "success" }
      if (res is Map<String, dynamic> && res['success'] == true && res['data'] is Map<String, dynamic>) {
        return PaymentOrderDto.fromJson(res['data'] as Map<String, dynamic>);
      }
      
      // 处理错误情况
      final errorMsg = res is Map<String, dynamic> ? (res['message'] ?? '创建积分包支付订单失败') : '创建积分包支付订单失败';
      throw Exception(errorMsg);
    } catch (e) {
      AppLogger.e(_tag, '创建积分包支付订单失败', e);
      rethrow;
    }
  }

  Future<List<PaymentOrderDto>> myOrders() async {
    try {
      final res = await _apiClient.get('/payments/orders');
      
      // 后端返回格式: { success: true, data: [...], message: "success" }
      if (res is Map<String, dynamic> && res['success'] == true && res['data'] is List) {
        return (res['data'] as List)
            .map((e) => PaymentOrderDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      
      return [];
    } catch (e) {
      AppLogger.e(_tag, '获取我的订单失败', e);
      return [];
    }
  }
  
  /// 查询订单状态
  Future<PaymentOrderDto?> getOrderStatus(String outTradeNo) async {
    try {
      final res = await _apiClient.get('/payments/order/$outTradeNo');
      
      if (res is Map<String, dynamic> && res['success'] == true && res['data'] is Map<String, dynamic>) {
        return PaymentOrderDto.fromJson(res['data'] as Map<String, dynamic>);
      }
      
      return null;
    } catch (e) {
      AppLogger.e(_tag, '查询订单状态失败', e);
      return null;
    }
  }
  
  /// 同步订单状态（从支付宝查询）
  Future<PaymentOrderDto?> syncOrderStatus(String outTradeNo) async {
    try {
      final res = await _apiClient.post('/payments/order/$outTradeNo/sync');
      
      if (res is Map<String, dynamic> && res['success'] == true && res['data'] is Map<String, dynamic>) {
        return PaymentOrderDto.fromJson(res['data'] as Map<String, dynamic>);
      }
      
      return null;
    } catch (e) {
      AppLogger.e(_tag, '同步订单状态失败', e);
      return null;
    }
  }
}


