import 'dart:async';
import 'package:ainoval/models/model_info.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:dio/dio.dart';

import 'adapter_base.dart';

/// Ollama 适配器
/// - 默认本地地址 http://127.0.0.1:11434
/// - GET /api/tags
class OllamaAdapter implements ModelListingAdapterBase {
  Future<List<ModelInfo>> listModels({
    required Dio dio,
    required String provider,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    final base = (apiEndpoint == null || apiEndpoint.isEmpty)
        ? 'http://127.0.0.1:11434'
        : _stripTrailingSlash(apiEndpoint);
    final url = '$base/api/tags';
    try {
      final resp = await dio.get(url);
      final data = resp.data;
      final List<dynamic> modelsRaw = _extractTagsArray(data);
      final List<ModelInfo> result = [];
      for (final item in modelsRaw) {
        if (item is Map<String, dynamic>) {
          final id = (item['model'] as String? ?? item['name'] as String? ?? '').trim();
          if (id.isEmpty) continue;
          final name = id;
          result.add(ModelInfo(id: id, name: name, provider: provider, description: ''));
        }
      }
      return result;
    } catch (e, s) {
      AppLogger.e('OllamaAdapter', '请求 $url 失败', e, s);
      rethrow;
    }
  }

  String _stripTrailingSlash(String v) => v.endsWith('/') ? v.substring(0, v.length - 1) : v;

  List<dynamic> _extractTagsArray(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['models'] is List) return data['models'] as List; // 某些版本
      if (data['tags'] is List) return data['tags'] as List;     // 旧版本
    }
    if (data is List) return data;
    return const [];
  }
}


