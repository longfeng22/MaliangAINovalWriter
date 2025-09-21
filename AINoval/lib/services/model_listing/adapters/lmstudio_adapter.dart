import 'dart:async';
import 'package:ainoval/models/model_info.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:dio/dio.dart';

import 'adapter_base.dart';

/// LM Studio 适配器
/// - 默认本地地址 http://127.0.0.1:1234
/// - GET /v1/models
class LmStudioAdapter implements ModelListingAdapterBase {
  Future<List<ModelInfo>> listModels({
    required Dio dio,
    required String provider,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    final base = (apiEndpoint == null || apiEndpoint.isEmpty)
        ? 'http://127.0.0.1:1234'
        : _stripTrailingSlash(apiEndpoint);
    final url = '$base/v1/models';
    try {
      final resp = await dio.get(url);
      final data = resp.data;
      final List<dynamic> modelsRaw = _extractModelsArray(data);
      final List<ModelInfo> result = [];
      for (final item in modelsRaw) {
        if (item is Map<String, dynamic>) {
          final id = (item['id'] as String? ?? '').trim();
          if (id.isEmpty) continue;
          final name = (item['display_name'] as String?) ?? (item['name'] as String?) ?? id;
          final desc = (item['description'] as String?) ?? '';
          result.add(ModelInfo(id: id, name: name, provider: provider, description: desc));
        }
      }
      return result;
    } catch (e, s) {
      AppLogger.e('LmStudioAdapter', '请求 $url 失败', e, s);
      rethrow;
    }
  }

  String _stripTrailingSlash(String v) => v.endsWith('/') ? v.substring(0, v.length - 1) : v;

  List<dynamic> _extractModelsArray(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['data'] is List) return data['data'] as List;
      if (data['models'] is List) return data['models'] as List;
    }
    if (data is List) return data;
    return const [];
  }
}


