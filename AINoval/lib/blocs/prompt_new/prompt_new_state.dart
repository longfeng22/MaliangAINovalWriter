import 'package:ainoval/models/prompt_models.dart';
import 'package:equatable/equatable.dart';

/// 提示词视图模式
enum PromptViewMode {
  list,
  detail,
}

/// 提示词状态枚举
enum PromptNewStatus {
  initial,
  loading,
  success,
  failure,
}

/// 提示词管理状态
class PromptNewState extends Equatable {
  const PromptNewState({
    this.status = PromptNewStatus.initial,
    this.promptPackages = const {},
    this.selectedPromptId,
    this.selectedFeatureType,
    this.viewMode = PromptViewMode.list,
    this.searchQuery = '',
    this.filteredPrompts = const {},
    this.errorMessage,
    this.isCreating = false,
    this.isUpdating = false,
  });

  /// 加载状态
  final PromptNewStatus status;

  /// 提示词包数据
  final Map<AIFeatureType, PromptPackage> promptPackages;

  /// 当前选中的提示词ID
  final String? selectedPromptId;

  /// 当前选中的功能类型
  final AIFeatureType? selectedFeatureType;

  /// 视图模式
  final PromptViewMode viewMode;

  /// 搜索查询
  final String searchQuery;

  /// 过滤后的提示词
  final Map<AIFeatureType, List<UserPromptInfo>> filteredPrompts;

  /// 错误信息
  final String? errorMessage;

  /// 是否正在创建
  final bool isCreating;

  /// 是否正在更新
  final bool isUpdating;

  /// 获取当前选中的提示词
  UserPromptInfo? get selectedPrompt {
    if (selectedPromptId == null || selectedFeatureType == null) return null;
    
    final package = promptPackages[selectedFeatureType];
    if (package == null) return null;
    
    // 获取包含所有类型提示词的完整列表（与列表视图逻辑一致）
    final allPrompts = _getAllPromptsForFeatureType(selectedFeatureType!, package);
    
    try {
      return allPrompts.firstWhere(
        (prompt) => prompt.id == selectedPromptId,
      );
    } catch (e) {
      // 如果找不到选中的提示词，返回第一个可用的提示词
      return allPrompts.isNotEmpty ? allPrompts.first : null;
    }
  }

  /// 获取指定功能类型的所有提示词（系统默认 + 用户自定义 + 公开模板）
  List<UserPromptInfo> _getAllPromptsForFeatureType(AIFeatureType featureType, PromptPackage package) {
    final allPrompts = <UserPromptInfo>[];
    
    // 检查是否有用户默认模板
    final hasUserDefault = package.userPrompts.any((prompt) => prompt.isDefault);
    
    // 1. 添加系统默认提示词
    if (package.systemPrompt.defaultSystemPrompt.isNotEmpty) {
      final systemPromptAsUser = UserPromptInfo(
        id: 'system_default_${featureType.toString()}',
        name: '系统默认模板',
        description: '系统提供的默认提示词模板',
        featureType: featureType,
        systemPrompt: package.systemPrompt.effectivePrompt,
        userPrompt: package.systemPrompt.defaultUserPrompt,
        tags: const ['系统默认'],
        isDefault: !hasUserDefault, // 当没有用户默认模板时，系统默认模板显示为默认
        authorId: 'system',
        createdAt: package.lastUpdated,
        updatedAt: package.lastUpdated,
      );
      allPrompts.add(systemPromptAsUser);
    }
    
    // 2. 添加用户自定义提示词
    allPrompts.addAll(package.userPrompts);
    
    // 3. 添加公开提示词
    for (final publicPrompt in package.publicPrompts) {
      final publicPromptAsUser = UserPromptInfo(
        id: 'public_${publicPrompt.id}',
        name: '${publicPrompt.name} ${publicPrompt.isVerified ? '✓' : ''}',
        description: '${publicPrompt.description ?? ''} (作者: ${publicPrompt.authorName ?? '匿名'})',
        featureType: featureType,
        systemPrompt: publicPrompt.systemPrompt,
        userPrompt: publicPrompt.userPrompt,
        tags: const ['公开模板'],
        categories: publicPrompt.categories,
        isPublic: true,
        shareCode: publicPrompt.shareCode,
        isVerified: publicPrompt.isVerified,
        usageCount: publicPrompt.usageCount.toInt(),
        favoriteCount: publicPrompt.favoriteCount.toInt(),
        rating: publicPrompt.rating ?? 0.0,
        authorId: publicPrompt.authorName,
        version: publicPrompt.version,
        language: publicPrompt.language,
        createdAt: publicPrompt.createdAt,
        lastUsedAt: publicPrompt.lastUsedAt,
        updatedAt: publicPrompt.updatedAt,
        hidePrompts: publicPrompt.hidePrompts,
        settingGenerationConfig: publicPrompt.settingGenerationConfig, // 🆕 传递设定生成配置
      );
      allPrompts.add(publicPromptAsUser);
    }
    
    return allPrompts;
  }

  /// 获取所有提示词的扁平列表（包含系统默认、用户自定义和公开模板）
  List<UserPromptInfo> get allUserPrompts {
    final allPrompts = <UserPromptInfo>[];
    for (final entry in promptPackages.entries) {
      allPrompts.addAll(_getAllPromptsForFeatureType(entry.key, entry.value));
    }
    return allPrompts;
  }

  /// 获取所有公开提示词的扁平列表
  List<PublicPromptInfo> get allPublicPrompts {
    final allPrompts = <PublicPromptInfo>[];
    for (final package in promptPackages.values) {
      allPrompts.addAll(package.publicPrompts);
    }
    return allPrompts;
  }

  /// 检查是否有数据
  bool get hasData => promptPackages.isNotEmpty;

  /// 检查是否正在加载
  bool get isLoading => status == PromptNewStatus.loading;

  /// 检查是否加载成功
  bool get isSuccess => status == PromptNewStatus.success;

  /// 检查是否有错误
  bool get hasError => status == PromptNewStatus.failure;

  /// 获取指定功能类型的用户提示词
  List<UserPromptInfo> getUserPrompts(AIFeatureType featureType) {
    return promptPackages[featureType]?.userPrompts ?? [];
  }

  /// 获取指定功能类型的公开提示词
  List<PublicPromptInfo> getPublicPrompts(AIFeatureType featureType) {
    return promptPackages[featureType]?.publicPrompts ?? [];
  }

  /// 获取指定功能类型的系统提示词信息
  SystemPromptInfo? getSystemPromptInfo(AIFeatureType featureType) {
    return promptPackages[featureType]?.systemPrompt;
  }

  /// 复制状态
  PromptNewState copyWith({
    PromptNewStatus? status,
    Map<AIFeatureType, PromptPackage>? promptPackages,
    String? selectedPromptId,
    AIFeatureType? selectedFeatureType,
    PromptViewMode? viewMode,
    String? searchQuery,
    Map<AIFeatureType, List<UserPromptInfo>>? filteredPrompts,
    String? errorMessage,
    bool? isCreating,
    bool? isUpdating,
  }) {
    return PromptNewState(
      status: status ?? this.status,
      promptPackages: promptPackages ?? this.promptPackages,
      selectedPromptId: selectedPromptId ?? this.selectedPromptId,
      selectedFeatureType: selectedFeatureType ?? this.selectedFeatureType,
      viewMode: viewMode ?? this.viewMode,
      searchQuery: searchQuery ?? this.searchQuery,
      filteredPrompts: filteredPrompts ?? this.filteredPrompts,
      errorMessage: errorMessage,
      isCreating: isCreating ?? this.isCreating,
      isUpdating: isUpdating ?? this.isUpdating,
    );
  }

  /// 清除选择状态
  PromptNewState clearSelection() {
    return copyWith(
      selectedPromptId: null,
      selectedFeatureType: null,
      viewMode: PromptViewMode.list,
    );
  }

  /// 清除错误状态
  PromptNewState clearError() {
    return copyWith(
      errorMessage: null,
    );
  }

  @override
  List<Object?> get props => [
        status,
        promptPackages,
        selectedPromptId,
        selectedFeatureType,
        viewMode,
        searchQuery,
        filteredPrompts,
        errorMessage,
        isCreating,
        isUpdating,
      ];
} 