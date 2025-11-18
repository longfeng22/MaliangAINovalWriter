import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/services/api_service/repositories/prompt_repository.dart';
import 'package:ainoval/services/api_service/repositories/prompt_market_repository.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/utils/logger.dart';
import 'prompt_new_event.dart';
import 'prompt_new_state.dart';

/// 提示词管理BLoC
class PromptNewBloc extends Bloc<PromptNewEvent, PromptNewState> {
  PromptNewBloc({
    required PromptRepository promptRepository,
  })  : _promptRepository = promptRepository,
        super(const PromptNewState()) {
    on<LoadAllPromptPackages>(_onLoadAllPromptPackages);
    on<SelectPrompt>(_onSelectPrompt);
    on<CreateNewPrompt>(_onCreateNewPrompt);
    on<UpdatePromptDetails>(_onUpdatePromptDetails);
    on<CopyPromptTemplate>(_onCopyPromptTemplate);
    on<ToggleFavoriteStatus>(_onToggleFavoriteStatus);
    on<SubmitForReview>(_onSubmitForReview);
    on<SetDefaultTemplate>(_onSetDefaultTemplate);
    on<DeletePrompt>(_onDeletePrompt);
    on<SearchPrompts>(_onSearchPrompts);
    on<ClearSearch>(_onClearSearch);
    on<ToggleViewMode>(_onToggleViewMode);
    on<RefreshPromptData>(_onRefreshPromptData);
  }

  final PromptRepository _promptRepository;
  PromptRepository get promptRepository => _promptRepository;
  static const String _tag = 'PromptNewBloc';

  /// 将EnhancedUserPromptTemplate转换为UserPromptInfo的辅助函数
  UserPromptInfo _convertToUserPromptInfo(EnhancedUserPromptTemplate template) {
    return UserPromptInfo(
      id: template.id,
      name: template.name,
      description: template.description,
      featureType: template.featureType,
      systemPrompt: template.systemPrompt,
      userPrompt: template.userPrompt,
      tags: template.tags,
      categories: template.categories,
      isFavorite: template.isFavorite,
      isDefault: template.isDefault,
      isPublic: template.isPublic,
      shareCode: template.shareCode,
      isVerified: template.isVerified,
      usageCount: template.usageCount,
      favoriteCount: template.favoriteCount ?? 0,
      rating: template.rating,
      authorId: template.userId, // 使用userId作为authorId
      createdAt: template.createdAt,
      lastUsedAt: template.lastUsedAt,
      updatedAt: template.updatedAt,
      reviewStatus: template.reviewStatus, // 🆕 添加审核状态字段
      hidePrompts: template.hidePrompts, // 🆕 添加隐藏提示词字段
      settingGenerationConfig: template.settingGenerationConfig, // 🆕 添加设定生成配置字段
    );
  }

  /// 加载所有提示词包
  Future<void> _onLoadAllPromptPackages(
    LoadAllPromptPackages event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      emit(state.copyWith(status: PromptNewStatus.loading));
      AppLogger.i(_tag, '开始加载所有提示词包');

      // 使用批量获取API
      final promptPackages = await _promptRepository.getBatchPromptPackages(
        includePublic: true,
      );

      AppLogger.i(_tag, '成功加载提示词包，功能类型数量: ${promptPackages.length}');

      emit(state.copyWith(
        status: PromptNewStatus.success,
        promptPackages: promptPackages,
        errorMessage: null,
      ));
    } catch (error) {
      AppLogger.e(_tag, '加载提示词包失败', error);
      emit(state.copyWith(
        status: PromptNewStatus.failure,
        errorMessage: '加载提示词包失败: ${error.toString()}',
      ));
    }
  }

  /// 选择提示词
  Future<void> _onSelectPrompt(
    SelectPrompt event,
    Emitter<PromptNewState> emit,
  ) async {
    AppLogger.i(_tag, '选择提示词: ${event.promptId}, 功能类型: ${event.featureType}');

    emit(state.copyWith(
      selectedPromptId: event.promptId,
      selectedFeatureType: event.featureType,
      viewMode: PromptViewMode.detail,
    ));
  }

  /// 创建新提示词
  Future<void> _onCreateNewPrompt(
    CreateNewPrompt event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      emit(state.copyWith(isCreating: true));
      AppLogger.i(_tag, '开始创建新提示词，功能类型: ${event.featureType}');

      // 创建新提示词模板
      final request = CreatePromptTemplateRequest(
        name: '新提示词模板 ${DateTime.now().millisecondsSinceEpoch}',
        description: '用户创建的提示词模板',
        featureType: event.featureType,
        systemPrompt: '',
        userPrompt: '',
        tags: [],
        categories: [],
      );

      final newTemplate = await _promptRepository.createEnhancedPromptTemplate(request);
      AppLogger.i(_tag, '成功创建新提示词模板: ${newTemplate.id}');

      // 直接在本地状态添加新模板，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      final package = updatedPackages[event.featureType];
      
      if (package != null) {
        // 将EnhancedUserPromptTemplate转换为UserPromptInfo
        final newUserPrompt = _convertToUserPromptInfo(newTemplate);

        // 创建新的用户提示词列表
        final updatedUserPrompts = List<UserPromptInfo>.from(package.userPrompts);
        updatedUserPrompts.add(newUserPrompt);

        // 更新package
        updatedPackages[event.featureType] = PromptPackage(
          featureType: package.featureType,
          systemPrompt: package.systemPrompt,
          userPrompts: updatedUserPrompts,
          publicPrompts: package.publicPrompts,
          recentlyUsed: package.recentlyUsed,
          supportedPlaceholders: package.supportedPlaceholders,
          placeholderDescriptions: package.placeholderDescriptions,
          lastUpdated: DateTime.now(),
        );

        // 发出新状态，选择新创建的提示词
        emit(state.copyWith(
          isCreating: false,
          promptPackages: updatedPackages,
          selectedPromptId: newTemplate.id,
          selectedFeatureType: event.featureType,
          viewMode: PromptViewMode.detail,
          errorMessage: null,
        ));

        AppLogger.i(_tag, '本地状态已更新，新模板已添加到列表并选中');
      } else {
        AppLogger.w(_tag, '无法找到功能类型包: ${event.featureType}');
        emit(state.copyWith(isCreating: false));
      }
    } catch (error) {
      AppLogger.e(_tag, '创建新提示词失败', error);
      emit(state.copyWith(
        isCreating: false,
        errorMessage: '创建新提示词失败: ${error.toString()}',
      ));
    }
  }

  /// 更新提示词详情
  Future<void> _onUpdatePromptDetails(
    UpdatePromptDetails event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      emit(state.copyWith(isUpdating: true));
      AppLogger.i(_tag, '开始更新提示词详情: ${event.promptId}');

      final updatedTemplate = await _promptRepository.updateEnhancedPromptTemplate(
        event.promptId,
        event.request,
      );

      AppLogger.i(_tag, '成功更新提示词详情: ${event.promptId}');

      // 直接在本地状态更新提示词详情，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      bool updated = false;

      for (final entry in updatedPackages.entries) {
        final package = entry.value;
        final updatedUserPrompts = package.userPrompts.map((prompt) {
          if (prompt.id == event.promptId) {
            updated = true;
            return _convertToUserPromptInfo(updatedTemplate);
          }
          return prompt;
        }).toList();

        if (updated) {
          updatedPackages[entry.key] = PromptPackage(
            featureType: package.featureType,
            systemPrompt: package.systemPrompt,
            userPrompts: updatedUserPrompts,
            publicPrompts: package.publicPrompts,
            recentlyUsed: package.recentlyUsed,
            supportedPlaceholders: package.supportedPlaceholders,
            placeholderDescriptions: package.placeholderDescriptions,
            lastUpdated: DateTime.now(),
          );
          break;
        }
      }

      if (updated) {
        emit(state.copyWith(
          isUpdating: false,
          promptPackages: updatedPackages,
          errorMessage: null,
        ));
        AppLogger.i(_tag, '本地状态已更新，提示词详情已更新');
      } else {
        AppLogger.w(_tag, '未找到需要更新的提示词: ${event.promptId}');
        emit(state.copyWith(isUpdating: false));
      }
    } catch (error) {
      AppLogger.e(_tag, '更新提示词详情失败', error);
      emit(state.copyWith(
        isUpdating: false,
        errorMessage: '更新提示词详情失败: ${error.toString()}',
      ));
    }
  }

  /// 复制提示词模板
  Future<void> _onCopyPromptTemplate(
    CopyPromptTemplate event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '开始复制提示词模板: ${event.templateId}');

      final copiedTemplate = await _promptRepository.copyPublicEnhancedTemplate(
        event.templateId,
      );

      AppLogger.i(_tag, '成功复制提示词模板: ${copiedTemplate.id}');

      // 直接在本地状态添加新模板，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      final package = updatedPackages[copiedTemplate.featureType];
      
      if (package != null) {
        // 将EnhancedUserPromptTemplate转换为UserPromptInfo
        final newUserPrompt = _convertToUserPromptInfo(copiedTemplate);

        // 创建新的用户提示词列表
        final updatedUserPrompts = List<UserPromptInfo>.from(package.userPrompts);
        updatedUserPrompts.add(newUserPrompt);

        // 更新package
        updatedPackages[copiedTemplate.featureType] = PromptPackage(
          featureType: package.featureType,
          systemPrompt: package.systemPrompt,
          userPrompts: updatedUserPrompts,
          publicPrompts: package.publicPrompts,
          recentlyUsed: package.recentlyUsed,
          supportedPlaceholders: package.supportedPlaceholders,
          placeholderDescriptions: package.placeholderDescriptions,
          lastUpdated: DateTime.now(),
        );

        // 发出新状态
        emit(state.copyWith(
          promptPackages: updatedPackages,
          selectedPromptId: copiedTemplate.id,
          selectedFeatureType: copiedTemplate.featureType,
          errorMessage: null,
        ));

        AppLogger.i(_tag, '本地状态已更新，新模板已添加到列表');
      } else {
        AppLogger.w(_tag, '无法找到功能类型包: ${copiedTemplate.featureType}');
        // 如果找不到对应的包，则fallback到刷新数据
        add(const RefreshPromptData());
        add(SelectPrompt(
          promptId: copiedTemplate.id,
          featureType: copiedTemplate.featureType,
        ));
      }
    } catch (error) {
      AppLogger.e(_tag, '复制提示词模板失败', error);
      emit(state.copyWith(
        errorMessage: '复制提示词模板失败: ${error.toString()}',
      ));
    }
  }

  /// 切换收藏状态
  Future<void> _onToggleFavoriteStatus(
    ToggleFavoriteStatus event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '切换收藏状态: ${event.promptId}, 收藏: ${event.isFavorite}');

      if (event.isFavorite) {
        await _promptRepository.favoriteEnhancedTemplate(event.promptId);
      } else {
        await _promptRepository.unfavoriteEnhancedTemplate(event.promptId);
      }

      // 直接在本地状态更新收藏状态，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      bool updated = false;

      for (final entry in updatedPackages.entries) {
        final package = entry.value;
        final updatedUserPrompts = package.userPrompts.map((prompt) {
          if (prompt.id == event.promptId) {
            updated = true;
            return prompt.copyWith(
              isFavorite: event.isFavorite,
              updatedAt: DateTime.now(),
            );
          }
          return prompt;
        }).toList();

        if (updated) {
          updatedPackages[entry.key] = PromptPackage(
            featureType: package.featureType,
            systemPrompt: package.systemPrompt,
            userPrompts: updatedUserPrompts,
            publicPrompts: package.publicPrompts,
            recentlyUsed: package.recentlyUsed,
            supportedPlaceholders: package.supportedPlaceholders,
            placeholderDescriptions: package.placeholderDescriptions,
            lastUpdated: DateTime.now(),
          );
          break;
        }
      }

      if (updated) {
        emit(state.copyWith(
          promptPackages: updatedPackages,
          errorMessage: null,
        ));
        AppLogger.i(_tag, '本地状态已更新，收藏状态已切换');
      } else {
        AppLogger.w(_tag, '未找到需要更新的提示词: ${event.promptId}');
        // 如果找不到对应的提示词，则fallback到刷新数据
        add(const RefreshPromptData());
      }
    } catch (error) {
      AppLogger.e(_tag, '切换收藏状态失败', error);
      emit(state.copyWith(
        errorMessage: '切换收藏状态失败: ${error.toString()}',
      ));
    }
  }

  /// 提交审核
  Future<void> _onSubmitForReview(
    SubmitForReview event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '📤 收到提交审核事件: promptId=${event.promptId}, hidePrompts=${event.hidePrompts}');

      // 调用市场服务提交审核，传递 hidePrompts 参数
      final marketRepo = PromptMarketRepository(ApiClient());
      AppLogger.i(_tag, '📞 调用 shareTemplate API: promptId=${event.promptId}, hidePrompts=${event.hidePrompts}');
      await marketRepo.shareTemplate(event.promptId, hidePrompts: event.hidePrompts);

      // 🎯 直接在本地状态更新审核状态为 PENDING，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      bool updated = false;

      for (final entry in updatedPackages.entries) {
        final package = entry.value;
        final updatedUserPrompts = package.userPrompts.map((prompt) {
          if (prompt.id == event.promptId) {
            updated = true;
            return prompt.copyWith(
              reviewStatus: 'PENDING',  // 🔥 立即更新为审核中
              hidePrompts: event.hidePrompts,  // 🔥 更新隐藏提示词状态
              updatedAt: DateTime.now(),
            );
          }
          return prompt;
        }).toList();

        if (updated) {
          updatedPackages[entry.key] = PromptPackage(
            featureType: package.featureType,
            systemPrompt: package.systemPrompt,
            userPrompts: updatedUserPrompts,
            publicPrompts: package.publicPrompts,
            recentlyUsed: package.recentlyUsed,
            supportedPlaceholders: package.supportedPlaceholders,
            placeholderDescriptions: package.placeholderDescriptions,
            lastUpdated: DateTime.now(),
          );
          break;
        }
      }

      if (updated) {
        emit(state.copyWith(
          promptPackages: updatedPackages,
          errorMessage: null,
        ));
        AppLogger.i(_tag, '✅ 本地状态已更新，审核状态已设为 PENDING');
      } else {
        AppLogger.w(_tag, '未找到需要更新的提示词: ${event.promptId}');
        // 如果找不到对应的提示词，则fallback到刷新数据
        add(const RefreshPromptData());
      }
    } catch (error) {
      AppLogger.e(_tag, '提交审核失败', error);
      emit(state.copyWith(
        errorMessage: '提交审核失败: ${error.toString()}',
      ));
      rethrow; // 重新抛出以便UI层显示错误
    }
  }

  /// 删除提示词
  Future<void> _onDeletePrompt(
    DeletePrompt event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '开始删除提示词: ${event.promptId}');

      await _promptRepository.deleteEnhancedPromptTemplate(event.promptId);

      AppLogger.i(_tag, '成功删除提示词: ${event.promptId}');

      // 直接在本地状态删除提示词，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      bool deleted = false;

      for (final entry in updatedPackages.entries) {
        final package = entry.value;
        final originalLength = package.userPrompts.length;
        final updatedUserPrompts = package.userPrompts
            .where((prompt) => prompt.id != event.promptId)
            .toList();

        if (updatedUserPrompts.length < originalLength) {
          deleted = true;
          updatedPackages[entry.key] = PromptPackage(
            featureType: package.featureType,
            systemPrompt: package.systemPrompt,
            userPrompts: updatedUserPrompts,
            publicPrompts: package.publicPrompts,
            recentlyUsed: package.recentlyUsed,
            supportedPlaceholders: package.supportedPlaceholders,
            placeholderDescriptions: package.placeholderDescriptions,
            lastUpdated: DateTime.now(),
          );
          break;
        }
      }

      // 更新状态
      final newState = state.copyWith(
        promptPackages: updatedPackages,
        errorMessage: null,
      );

      // 如果删除的是当前选中的提示词，清除选择
      final finalState = state.selectedPromptId == event.promptId 
          ? newState.clearSelection() 
          : newState;

      emit(finalState);

      if (deleted) {
        AppLogger.i(_tag, '本地状态已更新，提示词已从列表中删除');
      } else {
        AppLogger.w(_tag, '未找到需要删除的提示词: ${event.promptId}');
      }
    } catch (error) {
      AppLogger.e(_tag, '删除提示词失败', error);
      emit(state.copyWith(
        errorMessage: '删除提示词失败: ${error.toString()}',
      ));
    }
  }

  /// 搜索提示词
  Future<void> _onSearchPrompts(
    SearchPrompts event,
    Emitter<PromptNewState> emit,
  ) async {
    AppLogger.i(_tag, '搜索提示词: ${event.query}');

    final filteredPrompts = <AIFeatureType, List<UserPromptInfo>>{};

    if (event.query.isEmpty) {
      // 如果搜索查询为空，清空过滤结果，让UI使用正常的分组逻辑
      emit(state.copyWith(
        searchQuery: '',
        filteredPrompts: {},
      ));
      return;
    }

    // 过滤提示词
    final query = event.query.toLowerCase();
    for (final entry in state.promptPackages.entries) {
      final featureType = entry.key;
      final package = entry.value;
      
      final allPrompts = <UserPromptInfo>[];
      
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
        );
        allPrompts.add(publicPromptAsUser);
      }
      
      // 过滤匹配的提示词
      final filtered = allPrompts.where((prompt) {
        return prompt.name.toLowerCase().contains(query) ||
            prompt.description?.toLowerCase().contains(query) == true ||
            prompt.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();

      if (filtered.isNotEmpty) {
        filteredPrompts[featureType] = filtered;
      }
    }

    emit(state.copyWith(
      searchQuery: event.query,
      filteredPrompts: filteredPrompts,
    ));
  }

  /// 清除搜索
  Future<void> _onClearSearch(
    ClearSearch event,
    Emitter<PromptNewState> emit,
  ) async {
    AppLogger.i(_tag, '清除搜索');

    emit(state.copyWith(
      searchQuery: '',
      filteredPrompts: {},
    ));
  }

  /// 切换视图模式
  Future<void> _onToggleViewMode(
    ToggleViewMode event,
    Emitter<PromptNewState> emit,
  ) async {
    final newMode = state.viewMode == PromptViewMode.list
        ? PromptViewMode.detail
        : PromptViewMode.list;

    AppLogger.i(_tag, '切换视图模式: ${state.viewMode} -> $newMode');

    emit(state.copyWith(viewMode: newMode));
  }

  /// 刷新提示词数据
  Future<void> _onRefreshPromptData(
    RefreshPromptData event,
    Emitter<PromptNewState> emit,
  ) async {
    // 重新加载数据，但不显示加载状态
    try {
      AppLogger.i(_tag, '刷新提示词数据');

      final promptPackages = await _promptRepository.getBatchPromptPackages(
        includePublic: true,
      );

      emit(state.copyWith(
        promptPackages: promptPackages,
        errorMessage: null,
      ));

      AppLogger.i(_tag, '提示词数据刷新完成');
    } catch (error) {
      AppLogger.e(_tag, '刷新提示词数据失败', error);
      emit(state.copyWith(
        errorMessage: '刷新数据失败: ${error.toString()}',
      ));
    }
  }

  /// 设置默认模板
  Future<void> _onSetDefaultTemplate(
    SetDefaultTemplate event,
    Emitter<PromptNewState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '设置默认模板: ${event.promptId}, 功能类型: ${event.featureType}');

      await _promptRepository.setDefaultEnhancedTemplate(event.promptId);

      AppLogger.i(_tag, '成功设置默认模板: ${event.promptId}');

      // 直接在本地状态更新默认状态，无需重新请求所有数据
      final updatedPackages = Map<AIFeatureType, PromptPackage>.from(state.promptPackages);
      bool updated = false;

      final package = updatedPackages[event.featureType];
      if (package != null) {
        // 先清除该功能类型下所有模板的默认状态
        final updatedUserPrompts = package.userPrompts.map((prompt) {
          return prompt.copyWith(
            isDefault: prompt.id == event.promptId, // 只有目标模板设为默认
          );
        }).toList();

        updated = true;
        updatedPackages[event.featureType] = PromptPackage(
          featureType: package.featureType,
          systemPrompt: package.systemPrompt,
          userPrompts: updatedUserPrompts,
          publicPrompts: package.publicPrompts,
          recentlyUsed: package.recentlyUsed,
          supportedPlaceholders: package.supportedPlaceholders,
          placeholderDescriptions: package.placeholderDescriptions,
          lastUpdated: DateTime.now(),
        );
      }

      if (updated) {
        emit(state.copyWith(
          promptPackages: updatedPackages,
          errorMessage: null,
        ));
        AppLogger.i(_tag, '本地状态已更新，默认模板状态已设置');
      } else {
        AppLogger.w(_tag, '未找到需要更新的功能类型包: ${event.featureType}');
        // 如果找不到对应的包，则fallback到刷新数据
        add(const RefreshPromptData());
      }
    } catch (error) {
      AppLogger.e(_tag, '设置默认模板失败', error);
      emit(state.copyWith(
        errorMessage: '设置默认模板失败: ${error.toString()}',
      ));
    }
  }
} 