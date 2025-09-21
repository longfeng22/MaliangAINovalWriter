import 'dart:async';
import 'package:ainoval/models/model_info.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:dio/dio.dart';

import 'adapters/adapter_base.dart';
import 'adapters/openai_compatible_adapter.dart';
import 'adapters/lmstudio_adapter.dart';
import 'adapters/ollama_adapter.dart';

/// 前端直连获取模型列表的统一入口
/// - 根据 provider / apiEndpoint 选择正确的适配器
/// - 失败时抛出异常，由上层决定是否回退到后端
class ModelListingService {
  ModelListingService._();

  static final ModelListingService _instance = ModelListingService._();
  factory ModelListingService() => _instance;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
    ),
  );

  // 简单的3分钟内存缓存：key=provider|endpoint|hasKey
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 3);

  Future<List<ModelInfo>> listModelsDirect({
    required String provider,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    final cacheKey = _buildCacheKey(provider, apiEndpoint, apiKey);
    final now = DateTime.now();
    final cached = _cache[cacheKey];
    if (cached != null && now.difference(cached.timestamp) < _cacheTtl) {
      AppLogger.i('ModelListingService', '使用直连缓存: $cacheKey');
      return cached.models;
    }

    final adapter = _selectAdapter(provider: provider, apiEndpoint: apiEndpoint);
    AppLogger.i('ModelListingService', '直连获取模型: provider=$provider, endpoint=$apiEndpoint, adapter=${adapter.runtimeType}');

    try {
      final models = await adapter.listModels(
        dio: _dio,
        provider: provider,
        apiKey: apiKey,
        apiEndpoint: apiEndpoint,
      );
      _cache[cacheKey] = _CacheEntry(models: models, timestamp: DateTime.now());
      return models;
    } catch (e, s) {
      AppLogger.e('ModelListingService', '直连获取模型失败: provider=$provider, endpoint=$apiEndpoint', e, s);
      rethrow;
    }
  }

  String _buildCacheKey(String provider, String? apiEndpoint, String? apiKey) {
    final hasKey = (apiKey != null && apiKey.isNotEmpty) ? '1' : '0';
    return [provider.trim().toLowerCase(), (apiEndpoint ?? '').trim().toLowerCase(), hasKey].join('|');
  }

  ModelListingAdapterBase _selectAdapter({required String provider, String? apiEndpoint}) {
    final p = provider.toLowerCase().trim();
    final host = (apiEndpoint ?? '').toLowerCase();

    // 本地/私有部署优先
    if (host.contains('127.0.0.1:1234') || host.contains('localhost:1234') || p == 'lmstudio') {
      return LmStudioAdapter();
    }
    if (host.contains('127.0.0.1:11434') || host.contains('localhost:11434') || p == 'ollama') {
      return OllamaAdapter();
    }

    // 常见OpenAI兼容聚合/反代平台
    if (p == 'openai' ||
        p == 'openrouter' ||
        p == 'groq' ||
        p == 'together' ||
        p == 'deepseek' ||
        p == 'siliconcloud' ||
        p == 'siliconflow' ||
        p == 'ppio' ||
        p == 'perplexity' ||
        p == 'xai' || p == 'grok' ||
        host.contains('openrouter.ai') ||
        host.contains('api.groq.com') ||
        host.contains('api.together.xyz') ||
        host.contains('api.deepseek.com') ||
        host.contains('silicon') ||
        host.contains('ppinfra') || host.contains('ppio')) {
      return OpenAICompatibleAdapter();
    }

    // 默认回退：按OpenAI兼容
    return OpenAICompatibleAdapter();
  }
}

class _CacheEntry {
  _CacheEntry({required this.models, required this.timestamp});
  final List<ModelInfo> models;
  final DateTime timestamp;
}

/// 适配器协议见 ModelListingAdapterBase


