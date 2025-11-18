import 'package:equatable/equatable.dart';

abstract class SettingGenerationBlocEvent extends Equatable {
  const SettingGenerationBlocEvent();

  @override
  List<Object?> get props => [];
}

/// 加载可用策略
class LoadStrategiesEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final String? userId;

  const LoadStrategiesEvent({
    this.novelId,
    this.userId,
  });

  @override
  List<Object?> get props => [novelId, userId];
}

/// 加载历史记录
class LoadHistoriesEvent extends SettingGenerationBlocEvent {
  final String novelId;
  final String userId;
  final int page;
  final int size;

  const LoadHistoriesEvent({
    required this.novelId,
    required this.userId,
    this.page = 0,
    this.size = 20,
  });

  @override
  List<Object?> get props => [novelId, userId, page, size];
}

/// 从小说设定创建编辑会话
class StartSessionFromNovelEvent extends SettingGenerationBlocEvent {
  final String novelId;
  final String editReason;
  final String modelConfigId;
  final bool createNewSnapshot;

  const StartSessionFromNovelEvent({
    required this.novelId,
    required this.editReason,
    required this.modelConfigId,
    required this.createNewSnapshot,
  });

  @override
  List<Object?> get props => [novelId, editReason, modelConfigId, createNewSnapshot];
}

/// 开始生成设定
class StartGenerationEvent extends SettingGenerationBlocEvent {
  final String initialPrompt;
  final String promptTemplateId;
  final String? novelId;
  final String modelConfigId;
  final String? userId;
  // 文本阶段公共模型透传（仅记录，不改变文本阶段默认使用私有模型）
  final bool? usePublicTextModel;
  final String? textPhasePublicProvider;
  final String? textPhasePublicModelId;
  // 📚 知识库集成模式
  final String? knowledgeBaseMode;  // 'NONE', 'REUSE', 'IMITATION', 'HYBRID'
  // 📚 知识库ID列表（用于REUSE和IMITATION模式）
  final List<String>? knowledgeBaseIds;
  // 📚 知识库分类列表（JSON格式，每个知识库对应一个分类列表）
  final Map<String, List<String>>? knowledgeBaseCategories;
  // 📚 混合模式专用：用于复用的知识库ID列表
  final List<String>? reuseKnowledgeBaseIds;
  // 📚 混合模式专用：用于参考的知识库ID列表
  final List<String>? referenceKnowledgeBaseIds;
  // 🔧 结构化输出循环模式：是否使用结构化输出（直接输出JSON，不使用工具调用）
  final bool? useStructuredOutput;
  // 🔧 结构化输出循环模式：最大迭代次数（默认3次）
  final int? structuredIterations;

  const StartGenerationEvent({
    required this.initialPrompt,
    required this.promptTemplateId,
    this.novelId,
    required this.modelConfigId,
    this.userId,
    this.usePublicTextModel,
    this.textPhasePublicProvider,
    this.textPhasePublicModelId,
    this.knowledgeBaseMode,
    this.knowledgeBaseIds,
    this.knowledgeBaseCategories,
    this.reuseKnowledgeBaseIds,
    this.referenceKnowledgeBaseIds,
    this.useStructuredOutput,
    this.structuredIterations,
  });

  @override
  List<Object?> get props => [
        initialPrompt,
        promptTemplateId,
        novelId,
        modelConfigId,
        userId,
        usePublicTextModel,
        textPhasePublicProvider,
        textPhasePublicModelId,
        knowledgeBaseMode,
        knowledgeBaseIds,
        knowledgeBaseCategories,
        reuseKnowledgeBaseIds,
        referenceKnowledgeBaseIds,
        useStructuredOutput,
        structuredIterations,
      ];
}

/// 基于当前会话进行整体调整生成
class AdjustGenerationEvent extends SettingGenerationBlocEvent {
  final String sessionId;
  final String adjustmentPrompt;
  final String modelConfigId;
  final String? promptTemplateId;

  const AdjustGenerationEvent({
    required this.sessionId,
    required this.adjustmentPrompt,
    required this.modelConfigId,
    this.promptTemplateId,
  });

  @override
  List<Object?> get props => [sessionId, adjustmentPrompt, modelConfigId, promptTemplateId];
}

/// 修改节点
class UpdateNodeEvent extends SettingGenerationBlocEvent {
  final String nodeId;
  final String modificationPrompt;
  final String modelConfigId;
  final String scope; // 'self' | 'self_and_children' | 'children_only'
  final bool? isPublicModel;
  final String? publicModelConfigId;

  const UpdateNodeEvent({
    required this.nodeId,
    required this.modificationPrompt,
    required this.modelConfigId,
    this.scope = 'self',
    this.isPublicModel,
    this.publicModelConfigId,
  });

  @override
  List<Object?> get props => [
        nodeId,
        modificationPrompt,
        modelConfigId,
        scope,
        isPublicModel,
        publicModelConfigId,
      ];
}

/// 选择节点
class SelectNodeEvent extends SettingGenerationBlocEvent {
  final String? nodeId;

  const SelectNodeEvent(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// 切换视图模式
class ToggleViewModeEvent extends SettingGenerationBlocEvent {
  final String viewMode; // 'compact' | 'detailed'

  const ToggleViewModeEvent(this.viewMode);

  @override
  List<Object?> get props => [viewMode];
}

/// 应用待处理的更改
class ApplyPendingChangesEvent extends SettingGenerationBlocEvent {
  const ApplyPendingChangesEvent();
}

/// 取消待处理的更改
class CancelPendingChangesEvent extends SettingGenerationBlocEvent {
  const CancelPendingChangesEvent();
}

/// 撤销节点更改
class UndoNodeChangeEvent extends SettingGenerationBlocEvent {
  final String nodeId;

  const UndoNodeChangeEvent(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// 保存生成的设定
class SaveGeneratedSettingsEvent extends SettingGenerationBlocEvent {
  final String? novelId; // 改为可空，支持独立快照
  final bool updateExisting; // 是否更新现有历史记录
  final String? targetHistoryId; // 目标历史记录ID

  const SaveGeneratedSettingsEvent(
    this.novelId, {
    this.updateExisting = false,
    this.targetHistoryId,
  });

  @override
  List<Object?> get props => [novelId, updateExisting, targetHistoryId];
}

/// 创建新会话
class CreateNewSessionEvent extends SettingGenerationBlocEvent {
  const CreateNewSessionEvent();
}

/// 选择会话
class SelectSessionEvent extends SettingGenerationBlocEvent {
  final String sessionId;
  final bool isHistorySession;

  const SelectSessionEvent(
    this.sessionId, {
    this.isHistorySession = false,
  });

  @override
  List<Object?> get props => [sessionId, isHistorySession];
}

/// 从历史记录创建编辑会话
class CreateSessionFromHistoryEvent extends SettingGenerationBlocEvent {
  final String historyId;
  final String userId;
  final String editReason;
  final String modelConfigId;

  const CreateSessionFromHistoryEvent({
    required this.historyId,
    required this.userId,
    this.editReason = '从历史记录编辑',
    required this.modelConfigId,
  });

  @override
  List<Object?> get props => [historyId, userId, editReason, modelConfigId];
}

/// 更新调整提示词
class UpdateAdjustmentPromptEvent extends SettingGenerationBlocEvent {
  final String prompt;

  const UpdateAdjustmentPromptEvent(this.prompt);

  @override
  List<Object?> get props => [prompt];
}

/// 重置状态事件
class ResetEvent extends SettingGenerationBlocEvent {
  const ResetEvent();
}

/// 重试事件（从错误状态恢复）
class RetryEvent extends SettingGenerationBlocEvent {
  const RetryEvent();
}

/// 开始渲染节点事件
class StartNodeRenderEvent extends SettingGenerationBlocEvent {
  final String nodeId;
  
  const StartNodeRenderEvent(this.nodeId);
  
  @override
  List<Object?> get props => [nodeId];
}

/// 完成节点渲染事件
class CompleteNodeRenderEvent extends SettingGenerationBlocEvent {
  final String nodeId;
  
  const CompleteNodeRenderEvent(this.nodeId);
  
  @override
  List<Object?> get props => [nodeId];
}

/// 处理渲染队列事件
class ProcessRenderQueueEvent extends SettingGenerationBlocEvent {
  const ProcessRenderQueueEvent();
  
  @override
  List<Object?> get props => [];
}

/// 更新节点内容事件
class UpdateNodeContentEvent extends SettingGenerationBlocEvent {
  final String nodeId;
  final String content;

  const UpdateNodeContentEvent({
    required this.nodeId,
    required this.content,
  });

  @override
  List<Object?> get props => [nodeId, content];
}

/// 获取会话状态事件
class GetSessionStatusEvent extends SettingGenerationBlocEvent {
  final String sessionId;

  const GetSessionStatusEvent(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

/// 取消会话事件
class CancelSessionEvent extends SettingGenerationBlocEvent {
  final String sessionId;

  const CancelSessionEvent(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

// ==================== NOVEL_COMPOSE 事件族 ====================

/// 启动：只生成大纲
class StartComposeOutlineEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final String userId;
  final String modelConfigId;
  final bool? isPublicModel;
  final String? publicModelConfigId;
  final String? settingSessionId; // 方案A：后端拉取会话转换
  final Map<String, dynamic>? contextSelections; // 直接透传已选上下文（可选）
  final String? prompt; // 自由提示词
  final String? instructions; // 生成指令
  final int chapterCount; // 按章大纲数量（支持黄金三章=3）
  final Map<String, dynamic> parameters; // 其他采样/模式参数

  const StartComposeOutlineEvent({
    required this.userId,
    required this.modelConfigId,
    this.isPublicModel,
    this.publicModelConfigId,
    this.novelId,
    this.settingSessionId,
    this.contextSelections,
    this.prompt,
    this.instructions,
    this.chapterCount = 3,
    this.parameters = const {},
  });
}

/// 启动：直接生成章节（黄金三章或指定N章）
class StartComposeChaptersEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final String userId;
  final String modelConfigId;
  final bool? isPublicModel;
  final String? publicModelConfigId;
  final String? settingSessionId;
  final Map<String, dynamic>? contextSelections;
  final String? prompt;
  final String? instructions;
  final int chapterCount; // 生成章节数
  final Map<String, dynamic> parameters;

  const StartComposeChaptersEvent({
    required this.userId,
    required this.modelConfigId,
    this.isPublicModel,
    this.publicModelConfigId,
    this.novelId,
    this.settingSessionId,
    this.contextSelections,
    this.prompt,
    this.instructions,
    this.chapterCount = 3,
    this.parameters = const {},
  });
}

/// 启动：先大纲后章节（outline_plus_chapters）
class StartComposeBundleEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final String userId;
  final String modelConfigId;
  final bool? isPublicModel;
  final String? publicModelConfigId;
  final String? settingSessionId;
  final Map<String, dynamic>? contextSelections;
  final String? prompt;
  final String? instructions;
  final int chapterCount; // 需要的大纲/章节数量
  final Map<String, dynamic> parameters;

  const StartComposeBundleEvent({
    required this.userId,
    required this.modelConfigId,
    this.isPublicModel,
    this.publicModelConfigId,
    this.novelId,
    this.settingSessionId,
    this.contextSelections,
    this.prompt,
    this.instructions,
    this.chapterCount = 3,
    this.parameters = const {},
  });
}

/// 微调：针对已生成的大纲或章节进行整体或定向调整
class RefineComposeEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final String userId;
  final String modelConfigId;
  final String? settingSessionId;
  final Map<String, dynamic>? contextSelections;
  final String? instructions; // 具体微调指令
  final Map<String, dynamic> parameters; // 可包含 chapterIndex、outlineText 等

  const RefineComposeEvent({
    required this.userId,
    required this.modelConfigId,
    this.novelId,
    this.settingSessionId,
    this.contextSelections,
    this.instructions,
    this.parameters = const {},
  });
}

/// 取消写作编排流
class CancelComposeEvent extends SettingGenerationBlocEvent {
  final String connectionId; // SSE连接ID或业务自定义ID
  const CancelComposeEvent(this.connectionId);
  @override
  List<Object?> get props => [connectionId];
}

/// 获取用户历史记录事件
class GetUserHistoriesEvent extends SettingGenerationBlocEvent {
  final String? novelId;
  final int page;
  final int size;

  const GetUserHistoriesEvent({
    this.novelId,
    this.page = 0,
    this.size = 20,
  });

  @override
  List<Object?> get props => [novelId, page, size];
}

/// 删除历史记录事件
class DeleteHistoryEvent extends SettingGenerationBlocEvent {
  final String historyId;

  const DeleteHistoryEvent(this.historyId);

  @override
  List<Object?> get props => [historyId];
}

/// 批量删除历史记录事件
class BatchDeleteHistoriesEvent extends SettingGenerationBlocEvent {
  final List<String> historyIds;

  const BatchDeleteHistoriesEvent(this.historyIds);

  @override
  List<Object?> get props => [historyIds];
}

/// 复制历史记录事件
class CopyHistoryEvent extends SettingGenerationBlocEvent {
  final String historyId;
  final String copyReason;

  const CopyHistoryEvent({
    required this.historyId,
    required this.copyReason,
  });

  @override
  List<Object?> get props => [historyId, copyReason];
}

/// 恢复历史记录到小说事件
class RestoreHistoryToNovelEvent extends SettingGenerationBlocEvent {
  final String historyId;
  final String novelId;

  const RestoreHistoryToNovelEvent({
    required this.historyId,
    required this.novelId,
  });

  @override
  List<Object?> get props => [historyId, novelId];
}

/// 手动添加子节点事件
class AddChildNodeEvent extends SettingGenerationBlocEvent {
  final String parentNodeId;
  final String title;
  final String content;
  final String type;
  final String? novelId;

  const AddChildNodeEvent({
    required this.parentNodeId,
    required this.title,
    required this.content,
    required this.type,
    this.novelId,
  });

  @override
  List<Object?> get props => [parentNodeId, title, content, type, novelId];
}

/// 删除节点事件
class DeleteNodeEvent extends SettingGenerationBlocEvent {
  final String nodeId;

  const DeleteNodeEvent({
    required this.nodeId,
  });

  @override
  List<Object?> get props => [nodeId];
}
