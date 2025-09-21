import 'dart:async';

import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/model_info.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
// Api Exception 可能仍然需要，用于类型检查或如果 repository 层需要抛出特定类型的异常
// 但 ApiExceptionHelper 不需要了
import 'package:ainoval/services/api_service/repositories/user_ai_model_config_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart'; // 添加枚举导入

/// 用户 AI 模型配置仓库实现
class UserAIModelConfigRepositoryImpl implements UserAIModelConfigRepository {
  UserAIModelConfigRepositoryImpl({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<List<String>> listAvailableProviders() async {
    AppLogger.i('UserAIModelConfigRepoImpl', '获取可用提供商');
    try {
      final providers = await apiClient.listAIProviders();
      AppLogger.i(
          'UserAIModelConfigRepoImpl', '获取可用提供商成功: count=${providers.length}');
      return providers;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl', '获取可用提供商失败', e, stackTrace);
      // 直接重新抛出，ApiClient 会处理 DioException 转换
      rethrow;
    }
  }

  @override
  Future<List<ModelInfo>> listModelsForProvider(String provider) async {
    AppLogger.i('UserAIModelConfigRepoImpl', '获取提供商 $provider 模型信息');
    try {
      final models = await apiClient.listAIModelsForProvider(provider: provider);
      AppLogger.i('UserAIModelConfigRepoImpl',
          '获取提供商 $provider 模型信息成功: count=${models.length}');
      return models;
    } catch (e, stackTrace) {
      AppLogger.e(
          'UserAIModelConfigRepoImpl', '获取提供商 $provider 模型信息失败', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<UserAIModelConfigModel> addConfiguration({
    required String userId,
    required String provider,
    required String modelName,
    String? alias,
    required String apiKey,
    String? apiEndpoint,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '添加配置: userId=$userId'); // Mask apiKey in logs
    try {
      final config = await apiClient.addAIConfiguration(
        userId: userId,
        provider: provider,
        modelName: modelName,
        alias: alias,
        apiKey: apiKey,
        apiEndpoint: apiEndpoint,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '添加配置成功: userId=$userId, configId=${config.id}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e(
          'UserAIModelConfigRepoImpl', '添加配置失败: userId=$userId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<List<UserAIModelConfigModel>> listConfigurations({
    required String userId,
    bool? validatedOnly,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '列出配置(富信息): userId=$userId, validatedOnly=$validatedOnly');
    try {
      // 优先使用富信息接口（包含价格与标签，不返回解密API Key）
      final configs = await apiClient.listAIConfigurationsEnriched(
          userId: userId, validatedOnly: validatedOnly);
      AppLogger.i('UserAIModelConfigRepoImpl',
          '列出配置(富信息)成功: userId=$userId, count=${configs.length}');
      return configs;
    } catch (e, stackTrace) {
      AppLogger.e(
          'UserAIModelConfigRepoImpl', '列出配置(富信息)失败，降级到旧接口: userId=$userId', e, stackTrace);
      // 回退到旧接口（含解密API Key），避免前端无数据
      try {
        final fallback = await apiClient.listAIConfigurationsWithDecryptedKeys(
          userId: userId,
          validatedOnly: validatedOnly,
        );
        return fallback;
      } catch (e2, st2) {
        AppLogger.e('UserAIModelConfigRepoImpl', '旧接口回退也失败: userId=$userId', e2, st2);
        rethrow;
      }
    }
  }

  @override
  Future<UserAIModelConfigModel> getConfigurationById({
    required String userId,
    required String configId,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '获取配置: userId=$userId, configId=$configId');
    try {
      final config = await apiClient.getAIConfigurationById(
        userId: userId,
        configId: configId,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '获取配置成功: userId=$userId, configId=${config.id}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '获取配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<UserAIModelConfigModel> updateConfiguration({
    required String userId,
    required String configId,
    String? alias,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    if (alias == null && apiKey == null && apiEndpoint == null) {
      AppLogger.w('UserAIModelConfigRepoImpl',
          '更新配置调用，但没有提供要更新的字段: userId=$userId, configId=$configId');
      AppLogger.i('UserAIModelConfigRepoImpl', '无有效更新字段，尝试获取当前配置');
      // 注意：这里的 getConfigurationById 本身也可能抛出异常
      return getConfigurationById(userId: userId, configId: configId);
    }

    AppLogger.i('UserAIModelConfigRepoImpl',
        '更新配置: userId=$userId, configId=$configId'); // Mask apiKey
    try {
      final config = await apiClient.updateAIConfiguration(
        userId: userId,
        configId: configId,
        alias: alias,
        apiKey: apiKey,
        apiEndpoint: apiEndpoint,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '更新配置成功: userId=$userId, configId=${config.id}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '更新配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<void> deleteConfiguration({
    required String userId,
    required String configId,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '删除配置: userId=$userId, configId=$configId');
    try {
      await apiClient.deleteAIConfiguration(userId: userId, configId: configId);
      AppLogger.i('UserAIModelConfigRepoImpl',
          '删除配置成功: userId=$userId, configId=$configId');
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '删除配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<UserAIModelConfigModel> validateConfiguration({
    required String userId,
    required String configId,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '验证配置: userId=$userId, configId=$configId');
    try {
      final config = await apiClient.validateAIConfiguration(
        userId: userId,
        configId: configId,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '验证配置成功: userId=$userId, configId=${config.id}, isValidated=${config.isValidated}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '验证配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<UserAIModelConfigModel> setDefaultConfiguration({
    required String userId,
    required String configId,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '设置默认配置: userId=$userId, configId=$configId');
    try {
      final config = await apiClient.setDefaultAIConfiguration(
        userId: userId,
        configId: configId,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '设置默认配置成功: userId=$userId, configId=${config.id}, isDefault=${config.isDefault}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '设置默认配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<ModelListingCapability> getProviderCapability(String providerName) async {
    AppLogger.i('UserAIModelConfigRepoImpl', '获取提供商 $providerName 的模型列表能力');
    try {
      final capabilityString = await apiClient.getProviderCapability(providerName);
      AppLogger.i('UserAIModelConfigRepoImpl', '获取提供商 $providerName 的模型列表能力成功: $capabilityString');
      // 清理字符串，去除可能的前后引号
      var cleanCapabilityString = capabilityString;
      if (cleanCapabilityString.startsWith('"') && cleanCapabilityString.endsWith('"')) {
        cleanCapabilityString = cleanCapabilityString.substring(1, cleanCapabilityString.length - 1);
      }

      ModelListingCapability capability;
      // 使用清理后的字符串进行比较
      switch (cleanCapabilityString) { 
        case 'NO_LISTING':
          capability = ModelListingCapability.noListing;
          break;
        case 'LISTING_WITHOUT_KEY': 
          capability = ModelListingCapability.listingWithoutKey;
          break;
        case 'LISTING_WITH_KEY':
          capability = ModelListingCapability.listingWithKey;
          break;
        default: 
          AppLogger.w('UserAIModelConfigRepoImpl', '未知的提供商能力字符串: $capabilityString, 使用默认 noListing');
          capability = ModelListingCapability.noListing; 
      }
      AppLogger.i('UserAIModelConfigRepoImpl', '获取提供商 $providerName 的模型列表能力成功: $capability');
      return capability;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl', '获取提供商 $providerName 的模型列表能力失败', e, stackTrace);
      // 如果出错，默认为最安全的能力类型
      AppLogger.w('UserAIModelConfigRepoImpl', '使用默认能力类型 noListing');
      return ModelListingCapability.noListing;
    }
  }
  
  @override
  Future<List<ModelInfo>> listModelsWithApiKey({
    required String provider,
    required String apiKey,
    String? apiEndpoint,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl', '使用API密钥获取提供商 $provider 的模型信息列表');
    try {
      final models = await apiClient.listAIModelsWithApiKey(
        provider: provider,
        apiKey: apiKey,
        apiEndpoint: apiEndpoint,
      );
      AppLogger.i('UserAIModelConfigRepoImpl', 
          '使用API密钥获取提供商 $provider 的模型信息列表成功: count=${models.length}');
      return models;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl', '使用API密钥获取提供商 $provider 的模型信息列表失败', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<UserAIModelConfigModel> setToolDefaultConfiguration({
    required String userId,
    required String configId,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl',
        '设置工具默认配置: userId=$userId, configId=$configId');
    try {
      final config = await apiClient.setToolDefaultAIConfiguration(
        userId: userId,
        configId: configId,
      );
      AppLogger.i('UserAIModelConfigRepoImpl',
          '设置工具默认配置成功: userId=$userId, configId=${config.id}, isToolDefault=${config.isToolDefault}');
      return config;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl',
          '设置工具默认配置失败: userId=$userId, configId=$configId', e, stackTrace);
      // 直接重新抛出
      rethrow;
    }
  }

  @override
  Future<bool> testApiKey({
    required String provider,
    required String apiKey,
    String? apiEndpoint,
    String? modelName,
  }) async {
    AppLogger.i('UserAIModelConfigRepoImpl', '测试API密钥: provider=$provider${modelName != null ? ", model=$modelName" : ""}');
    try {
      final ok = await apiClient.testProviderApiKey(
        provider: provider,
        apiKey: apiKey,
        apiEndpoint: apiEndpoint,
        modelName: modelName, // 传递模型名称
      );
      AppLogger.i('UserAIModelConfigRepoImpl', '测试API密钥完成: provider=$provider${modelName != null ? ", model=$modelName" : ""}, result=$ok');
      return ok;
    } catch (e, stackTrace) {
      AppLogger.e('UserAIModelConfigRepoImpl', '测试API密钥失败: provider=$provider${modelName != null ? ", model=$modelName" : ""}', e, stackTrace);
      rethrow;
    }
  }
}
