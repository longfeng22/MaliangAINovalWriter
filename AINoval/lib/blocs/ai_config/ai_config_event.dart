part of 'ai_config_bloc.dart';

abstract class AiConfigEvent extends Equatable {
  const AiConfigEvent();

  @override
  List<Object?> get props => [];
}

/// 加载所有配置
class LoadAiConfigs extends AiConfigEvent {
  // 实际应用中应从认证状态获取
  final String userId;
  const LoadAiConfigs({required this.userId});
  @override
  List<Object?> get props => [userId];
}

/// 加载可用提供商
class LoadAvailableProviders extends AiConfigEvent {
  const LoadAvailableProviders();
}

/// 加载指定提供商的模型
class LoadModelsForProvider extends AiConfigEvent {
  final String provider;
  const LoadModelsForProvider({required this.provider});
  @override
  List<Object?> get props => [provider];
}

/// 添加配置
class AddAiConfig extends AiConfigEvent {
  final String userId;
  final String provider;
  final String modelName;
  final String apiKey;
  final String? alias;
  final String? apiEndpoint;

  const AddAiConfig({
    required this.userId,
    required this.provider,
    required this.modelName,
    required this.apiKey,
    this.alias,
    this.apiEndpoint,
  });

  @override
  List<Object?> get props => [userId, provider, modelName, apiKey, alias, apiEndpoint];
}

/// 更新配置
class UpdateAiConfig extends AiConfigEvent {
  final String userId;
  final String configId;
  final String? alias;
  final String? apiKey;
  final String? apiEndpoint;

  const UpdateAiConfig({
    required this.userId,
    required this.configId,
    this.alias,
    this.apiKey,
    this.apiEndpoint,
  });

  @override
  List<Object?> get props => [userId, configId, alias, apiKey, apiEndpoint];
}

/// 删除配置
class DeleteAiConfig extends AiConfigEvent {
  final String userId;
  final String configId;
  const DeleteAiConfig({required this.userId, required this.configId});
  @override
  List<Object?> get props => [userId, configId];
}

/// 验证配置
class ValidateAiConfig extends AiConfigEvent {
  final String userId;
  final String configId;
  const ValidateAiConfig({required this.userId, required this.configId});
  @override
  List<Object?> get props => [userId, configId];
}

/// 设置默认配置
class SetDefaultAiConfig extends AiConfigEvent {
  final String userId;
  final String configId;
  const SetDefaultAiConfig({required this.userId, required this.configId});
  @override
  List<Object?> get props => [userId, configId];
}

/// 设置工具调用默认配置
class SetToolDefaultAiConfig extends AiConfigEvent {
  final String userId;
  final String configId;
  const SetToolDefaultAiConfig({required this.userId, required this.configId});
  @override
  List<Object?> get props => [userId, configId];
}

/// 清除提供商/模型列表(例如，关闭对话框时)
class ClearProviderModels extends AiConfigEvent {
  const ClearProviderModels();
}

/// 获取提供商默认配置
class GetProviderDefaultConfig extends AiConfigEvent {
  final String provider;
  const GetProviderDefaultConfig({required this.provider});
  @override
  List<Object?> get props => [provider];
}

/// 加载指定配置的API密钥
class LoadApiKeyForConfig extends AiConfigEvent {
  final String configId;
  final ValueGetter<void> onApiKeyLoaded; // Callback to return the key

  const LoadApiKeyForConfig({required this.configId, required this.onApiKeyLoaded});

  @override
  List<Object?> get props => [configId];
}

// --- New Events for Dynamic Loading & Validation ---

// Event to fetch the capability of a specific provider
class LoadProviderCapability extends AiConfigEvent {
  final String providerName;
  const LoadProviderCapability({required this.providerName});
  @override
  List<Object?> get props => [providerName];
}

// Event to test the API key for a specific provider
class TestApiKey extends AiConfigEvent {
  final String providerName;
  final String apiKey;
  final String? apiEndpoint;
  final String? modelName; // 新增：可选的模型名称，用于精确验证

  const TestApiKey({
    required this.providerName,
    required this.apiKey,
    this.apiEndpoint,
    this.modelName,
  });

  @override
  List<Object?> get props => [providerName, apiKey, apiEndpoint, modelName];
}

/// 直连获取模型（绕过后端）
class LoadModelsDirect extends AiConfigEvent {
  final String providerName;
  final String? apiKey;
  final String? apiEndpoint;

  const LoadModelsDirect({required this.providerName, this.apiKey, this.apiEndpoint});

  @override
  List<Object?> get props => [providerName, apiKey, apiEndpoint];
}

/// 清除API密钥测试错误状态
class ClearApiKeyTestError extends AiConfigEvent {
  const ClearApiKeyTestError();
}

/// 清除模型列表缓存
class ClearModelsCache extends AiConfigEvent {
  final String? provider; // 如果为null则清除所有缓存
  const ClearModelsCache({this.provider});
  @override
  List<Object?> get props => [provider];
}

/// 添加自定义模型并立即验证
class AddCustomModelAndValidate extends AiConfigEvent {
  final String userId;
  final String provider;
  final String modelName;
  final String apiKey;
  final String? alias;
  final String? apiEndpoint;

  const AddCustomModelAndValidate({
    required this.userId,
    required this.provider,
    required this.modelName,
    required this.apiKey,
    this.alias,
    this.apiEndpoint,
  });

  @override
  List<Object?> get props => [userId, provider, modelName, apiKey, alias, apiEndpoint];
}

/// 重置AI配置状态与缓存（用于登出/切换账号）
class ResetAiConfigs extends AiConfigEvent {
  const ResetAiConfigs();
}