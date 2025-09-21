import 'dart:async';
import 'package:ainoval/models/model_info.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:dio/dio.dart';

import 'adapter_base.dart';

/// OpenAI 兼容/反代/聚合平台适配器
/// 规则：
/// - GET {base}/v1/models （部分平台可能是 /openai/v1/models 或透传到上游）
/// - 使用 Bearer {apiKey}，必要时追加自定义头
class OpenAICompatibleAdapter implements ModelListingAdapterBase {
  Future<List<ModelInfo>> listModels({
    required Dio dio,
    required String provider,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    if (apiEndpoint == null || apiEndpoint.isEmpty) {
      throw Exception('OpenAI兼容直连需要提供 apiEndpoint');
    }

    final base = _normalizeBase(apiEndpoint);
    final url = _resolveModelsUrl(base);

    final headers = <String, String>{};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    try {
      final resp = await dio.get(url, options: Options(headers: headers));
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
      AppLogger.e('OpenAICompatibleAdapter', '请求 $url 失败', e, s);
      rethrow;
    }
  }

  String _normalizeBase(String endpoint) {
    var e = endpoint.trim();
    if (e.endsWith('/')) e = e.substring(0, e.length - 1);
    // 常见反代会要求 /openai/v1，但 models 通常走 /v1/models，保持 /v1 前缀
    if (e.endsWith('/openai/v1')) {
      return e.substring(0, e.length - '/openai/v1'.length);
    }
    return e;
  }

  String _resolveModelsUrl(String base) {
    // 常见平台特化
    if (base.contains('openrouter.ai')) {
      return 'https://openrouter.ai/api/v1/models';
    }
    if (base.contains('api.groq.com')) {
      return 'https://api.groq.com/openai/v1/models';
    }
    if (base.contains('api.together.xyz')) {
      return 'https://api.together.xyz/api/models';
    }
    // 默认 OpenAI 兼容
    return '$base/v1/models';
  }

  List<dynamic> _extractModelsArray(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['data'] is List) return data['data'] as List;
      if (data['models'] is List) return data['models'] as List;
    }
    if (data is List) return data;
    return const [];
  }
}


