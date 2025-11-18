import 'package:ainoval/models/prompt_models.dart';
import 'package:equatable/equatable.dart';

/// 提示词管理事件基类
abstract class PromptNewEvent extends Equatable {
  const PromptNewEvent();

  @override
  List<Object?> get props => [];
}

/// 加载所有提示词包
class LoadAllPromptPackages extends PromptNewEvent {
  const LoadAllPromptPackages();
}

/// 选择提示词
class SelectPrompt extends PromptNewEvent {
  final String promptId;
  final AIFeatureType featureType;

  const SelectPrompt({
    required this.promptId,
    required this.featureType,
  });

  @override
  List<Object?> get props => [promptId, featureType];
}

/// 创建新提示词
class CreateNewPrompt extends PromptNewEvent {
  final AIFeatureType featureType;

  const CreateNewPrompt({
    required this.featureType,
  });

  @override
  List<Object?> get props => [featureType];
}

/// 更新提示词详情
class UpdatePromptDetails extends PromptNewEvent {
  final String promptId;
  final UpdatePromptTemplateRequest request;

  const UpdatePromptDetails({
    required this.promptId,
    required this.request,
  });

  @override
  List<Object?> get props => [promptId, request];
}

/// 复制提示词模板
class CopyPromptTemplate extends PromptNewEvent {
  final String templateId;

  const CopyPromptTemplate({
    required this.templateId,
  });

  @override
  List<Object?> get props => [templateId];
}

/// 切换收藏状态
class ToggleFavoriteStatus extends PromptNewEvent {
  final String promptId;
  final bool isFavorite;

  const ToggleFavoriteStatus({
    required this.promptId,
    required this.isFavorite,
  });

  @override
  List<Object?> get props => [promptId, isFavorite];
}

/// 提交审核
class SubmitForReview extends PromptNewEvent {
  final String promptId;
  final bool hidePrompts;

  const SubmitForReview({
    required this.promptId,
    this.hidePrompts = false,
  });

  @override
  List<Object?> get props => [promptId, hidePrompts];
}

/// 设置默认提示词模板
class SetDefaultTemplate extends PromptNewEvent {
  final String promptId;
  final AIFeatureType featureType;

  const SetDefaultTemplate({
    required this.promptId,
    required this.featureType,
  });

  @override
  List<Object?> get props => [promptId, featureType];
}

/// 删除提示词
class DeletePrompt extends PromptNewEvent {
  final String promptId;

  const DeletePrompt({
    required this.promptId,
  });

  @override
  List<Object?> get props => [promptId];
}

/// 搜索提示词
class SearchPrompts extends PromptNewEvent {
  final String query;

  const SearchPrompts({
    required this.query,
  });

  @override
  List<Object?> get props => [query];
}

/// 清除搜索
class ClearSearch extends PromptNewEvent {
  const ClearSearch();
}

/// 切换视图模式
class ToggleViewMode extends PromptNewEvent {
  const ToggleViewMode();
}

/// 刷新提示词数据
class RefreshPromptData extends PromptNewEvent {
  const RefreshPromptData();
} 