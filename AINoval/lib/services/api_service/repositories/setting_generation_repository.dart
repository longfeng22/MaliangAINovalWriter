import '../../../models/setting_generation_session.dart';
import '../../../models/setting_generation_event.dart';
import '../../../models/strategy_template_info.dart';
import '../../../models/save_result.dart';
import '../../../models/ai_request_models.dart';

/// 设定生成仓库接口
/// 
/// 核心功能说明：
/// 1. 设定生成流程管理：支持AI生成和修改设定节点
/// 2. 用户维度历史记录管理：不再依赖特定小说，支持跨小说使用
/// 3. 编辑会话管理：支持从小说设定或历史记录创建编辑会话
/// 4. 历史记录操作：复制、删除、恢复等完整的历史记录管理功能
abstract class SettingGenerationRepository {
  /// 获取可用的生成策略模板
  Future<List<StrategyTemplateInfo>> getAvailableStrategies();

  /// 启动设定生成
  Stream<SettingGenerationEvent> startGeneration({
    required String sessionId,  // 🔧 前端生成的sessionId
    required String initialPrompt,
    required String promptTemplateId,
    String? novelId,
    required String modelConfigId,
    String? userId,
    bool? usePublicTextModel,
    String? textPhasePublicProvider,
    String? textPhasePublicModelId,
    // 📚 知识库集成参数
    String? knowledgeBaseMode,
    List<String>? knowledgeBaseIds,
    Map<String, List<String>>? knowledgeBaseCategories,
    // 📚 混合模式专用参数
    List<String>? reuseKnowledgeBaseIds,
    List<String>? referenceKnowledgeBaseIds,
    // 🔧 结构化输出循环模式参数
    bool? useStructuredOutput,
    int? structuredIterations,
  });

  /// 从小说设定创建编辑会话
  /// 
  /// 支持用户选择编辑模式：
  /// - createNewSnapshot = true：创建新的设定快照
  /// - createNewSnapshot = false：编辑上次的设定
  Future<Map<String, dynamic>> startSessionFromNovel({
    required String novelId,
    required String editReason,
    required String modelConfigId,
    required bool createNewSnapshot,
  });

  /// 强制关闭所有与设定生成相关的SSE连接（用于彻底停止自动重连）
  Future<void> forceCloseAllSSE();

  /// 修改设定节点
  Stream<SettingGenerationEvent> updateNode({
    required String sessionId,
    required String nodeId,
    required String modificationPrompt,
    required String modelConfigId,
    String scope = 'self',
    bool? isPublicModel,
    String? publicModelConfigId,
  });

  /// 基于会话整体调整生成
  Stream<SettingGenerationEvent> adjustSession({
    required String sessionId,
    required String adjustmentPrompt,
    required String modelConfigId,
    String? promptTemplateId,
  });

  /// 直接更新节点内容
  Future<String> updateNodeContent({
    required String sessionId,
    required String nodeId,
    required String newContent,
  });

  /// 删除节点及其所有子节点
  Future<Map<String, dynamic>> deleteNode({
    required String sessionId,
    required String nodeId,
  });

  /// 保存生成的设定
  /// 
  /// [novelId] 为 null 时表示保存为独立快照（不关联任何小说）
  /// 返回包含根设定ID列表和历史记录ID的完整结果
  Future<SaveResult> saveGeneratedSettings({
    required String sessionId,
    String? novelId,
    bool updateExisting = false,
    String? targetHistoryId,
  });

  /// 获取会话状态
  Future<Map<String, dynamic>> getSessionStatus({
    required String sessionId,
  });


  /// 加载历史记录详情（包含完整节点数据）
  Future<Map<String, dynamic>> loadHistoryDetail({
    required String historyId,
  });

  /// 取消生成会话
  Future<void> cancelSession({
    required String sessionId,
  });

  // ==================== NOVEL_COMPOSE 流式写作编排 ====================
  /// 基于设定/提示词的写作编排（大纲/章节/组合）流式生成
  /// 统一走通用AI通道（/ai/universal/stream），传入 AIRequestType.NOVEL_COMPOSE
  Stream<UniversalAIResponse> composeStream({
    required UniversalAIRequest request,
  });

  /// 建议：前端在开始黄金三章前，先创建一个草稿小说并将 novelId 放入 request
  /// 以便后端在大纲/章节保存后直接绑定会话

  /// 开始写作：确保novelId并保存当前会话设定
  Future<String?> startWriting({required String? sessionId, String? novelId, String? historyId});

  // ==================== 历史记录管理 ====================

  /// 获取用户的历史记录列表
  /// 
  /// 使用用户维度管理，支持按小说过滤
  Future<List<Map<String, dynamic>>> getUserHistories({
    String? novelId,
    int page = 0,
    int size = 20,
  });

  /// 获取历史记录详情
  Future<Map<String, dynamic>?> getHistoryDetails({
    required String historyId,
  });

  /// 从历史记录创建编辑会话（增强版）
  Future<Map<String, dynamic>> createEditSessionFromHistory({
    required String historyId,
    required String editReason,
    required String modelConfigId,
  });

  /// 复制历史记录
  Future<Map<String, dynamic>> copyHistory({
    required String historyId,
    required String copyReason,
  });

  /// 恢复历史记录到小说中
  Future<Map<String, dynamic>> restoreHistoryToNovel({
    required String historyId,
    required String novelId,
  });

  /// 删除历史记录
  Future<void> deleteHistory({
    required String historyId,
  });

  /// 批量删除历史记录
  Future<Map<String, dynamic>> batchDeleteHistories({
    required List<String> historyIds,
  });

  /// 统计历史记录数量
  Future<int> countUserHistories({
    String? novelId,
  });

  /// 获取节点历史记录
  Future<List<Map<String, dynamic>>> getNodeHistories({
    required String historyId,
    required String nodeId,
    int page = 0,
    int size = 10,
  });

  // ==================== 策略管理接口 ====================

  /// 创建用户自定义策略
  Future<Map<String, dynamic>> createCustomStrategy({
    required String name,
    required String description,
    required String systemPrompt,
    required String userPrompt,
    required List<Map<String, dynamic>> nodeTemplates,
    required int expectedRootNodes,
    required int maxDepth,
    String? baseStrategyId,
    bool? hidePrompts,
  });

  /// 基于现有策略创建新策略
  Future<Map<String, dynamic>> createStrategyFromBase({
    required String baseTemplateId,
    required String name,
    required String description,
    String? systemPrompt,
    String? userPrompt,
    required Map<String, dynamic> modifications,
  });

  /// 获取用户的策略列表
  Future<List<Map<String, dynamic>>> getUserStrategies({
    int page = 0,
    int size = 20,
  });

  /// 获取公开策略列表
  Future<List<Map<String, dynamic>>> getPublicStrategies({
    String? category,
    int page = 0,
    int size = 20,
  });

  /// 获取策略详情
  Future<Map<String, dynamic>?> getStrategyDetail({
    required String strategyId,
  });

  /// 更新策略
  Future<Map<String, dynamic>> updateStrategy({
    required String strategyId,
    required String name,
    required String description,
    String? systemPrompt,
    String? userPrompt,
    List<Map<String, dynamic>>? nodeTemplates,
    int? expectedRootNodes,
    int? maxDepth,
  });

  /// 删除策略
  Future<void> deleteStrategy({
    required String strategyId,
  });
  
  /// 点赞策略
  Future<Map<String, dynamic>> likeStrategy({
    required String strategyId,
  });
  
  /// 收藏策略
  Future<Map<String, dynamic>> favoriteStrategy({
    required String strategyId,
  });

  /// 提交策略审核
  Future<void> submitStrategyForReview({
    required String strategyId,
  });

  /// 获取待审核策略列表（管理员接口）
  Future<List<Map<String, dynamic>>> getPendingStrategies({
    int page = 0,
    int size = 20,
  });

  /// 审核策略（管理员接口）
  Future<void> reviewStrategy({
    required String strategyId,
    required String decision,
    String? comment,
    List<String>? rejectionReasons,
    List<String>? improvementSuggestions,
  });

  // ==================== 工具方法 ====================

  /// 检查会话是否已关联历史记录
  bool isSessionLinkedToHistory(SettingGenerationSession session) {
    return session.historyId != null && session.historyId!.isNotEmpty;
  }
}
