import 'dart:async';
import '../../../models/user_ai_model_config_model.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart'; // 导入以获取ModelListingCapability枚举
import 'package:ainoval/models/model_info.dart'; // Import ModelInfo

/// 用户 AI 模型配置仓库接口定义
abstract interface class UserAIModelConfigRepository {
  /// 获取系统支持的所有AI提供商
  Future<List<String>> listAvailableProviders();

  /// 获取指定提供商支持的模型列表 (现在返回详细信息)
  Future<List<ModelInfo>> listModelsForProvider(String provider);

  /// 添加新的用户AI模型配置
  Future<UserAIModelConfigModel> addConfiguration({
    required String userId,
    required String provider,
    required String modelName,
    String? alias,
    required String apiKey,
    String? apiEndpoint,
  });

  /// 列出用户所有的AI模型配置，包含解密后的API密钥
  /// [validatedOnly] 为 true 时，只返回已验证的配置
  Future<List<UserAIModelConfigModel>> listConfigurations({
    required String userId,
    bool? validatedOnly,
  });

  /// 获取指定ID的用户AI模型配置
  Future<UserAIModelConfigModel> getConfigurationById({
    required String userId,
    required String configId,
  });

  /// 更新指定ID的用户AI模型配置
  /// [alias], [apiKey], [apiEndpoint] 可选，只传递需要更新的字段
  Future<UserAIModelConfigModel> updateConfiguration({
    required String userId,
    required String configId,
    String? alias,
    String? apiKey,
    String? apiEndpoint,
  });

  /// 删除指定ID的用户AI模型配置
  Future<void> deleteConfiguration({
    required String userId,
    required String configId,
  });

  /// 手动触发指定配置的API Key验证
  Future<UserAIModelConfigModel> validateConfiguration({
    required String userId,
    required String configId,
  });

  /// 设置指定配置为用户的默认模型
  Future<UserAIModelConfigModel> setDefaultConfiguration({
    required String userId,
    required String configId,
  });

  /// 设置指定配置为用户的工具调用默认模型
  Future<UserAIModelConfigModel> setToolDefaultConfiguration({
    required String userId,
    required String configId,
  });

  /// 获取提供商的模型列表能力
  Future<ModelListingCapability> getProviderCapability(String providerName);
  
  /// 使用API密钥获取指定提供商的模型列表 (现在返回详细信息)
  Future<List<ModelInfo>> listModelsWithApiKey({
    required String provider, 
    required String apiKey, 
    String? apiEndpoint
  });

  /// 测试指定提供商 API Key 是否有效（不拉取模型列表）
  Future<bool> testApiKey({
    required String provider,
    required String apiKey,
    String? apiEndpoint,
    String? modelName, // 新增：可选的模型名称参数
  });
} 