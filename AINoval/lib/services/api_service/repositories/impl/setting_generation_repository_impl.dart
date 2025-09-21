import 'dart:async';
import '../../../../config/app_config.dart';
import '../../../../models/setting_generation_session.dart';
import '../../../../models/setting_generation_event.dart';
import '../../../../models/strategy_template_info.dart';
import '../../../../models/save_result.dart';
import '../../base/api_client.dart';
import '../../base/sse_client.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' as flutter_sse;
import '../../../../models/ai_request_models.dart';
import '../setting_generation_repository.dart';
import '../../../../utils/logger.dart';
import '../../../../utils/date_time_parser.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';

/// 设定生成仓库实现
/// 
/// 核心业务说明：
/// 1. 设定生成流程：
///    - 用户输入提示词 -> AI生成设定结构 -> 用户可修改节点 -> 保存到小说设定 -> 自动创建历史记录
/// 
/// 2. 历史记录管理：
///    - 历史记录是按用户维度管理的，不依赖于特定小说
///    - 每个历史记录包含一个小说设定的完整快照
///    - 支持跨小说查看和管理用户的所有历史记录
/// 
/// 3. 编辑模式选择：
///    - 创建新快照：基于当前小说的最新设定状态创建新的历史记录
///    - 编辑上次设定：使用用户在该小说的最新历史记录进行编辑
/// 
/// 4. 会话管理：
///    - 每个编辑操作都基于会话进行
///    - 会话支持实时的SSE事件流，提供生成进度反馈
///    - 会话可以被取消、查询状态等
/// 
/// 5. 跨小说功能：
///    - 历史记录可以恢复到不同的小说中
///    - 支持设定模板的复用和应用
class SettingGenerationRepositoryImpl implements SettingGenerationRepository {
  final ApiClient _apiClient;
  final SseClient _sseClient;
  // 移除未使用字段，防止linter警告
  final String _tag = 'SettingGenerationRepository';

  SettingGenerationRepositoryImpl({
    required ApiClient apiClient,
    required SseClient sseClient,
  })  : _apiClient = apiClient,
        _sseClient = sseClient;

  @override
  Future<List<StrategyTemplateInfo>> getAvailableStrategies() async {
    try {
      AppLogger.info(_tag, '获取可用的生成策略模板');
      
      final result = await _apiClient.get('/setting-generation/strategies');
      
      // 期望后端返回: { success: true, data: List<StrategyTemplateInfo> }
      if (result is Map<String, dynamic> && result['success'] == true) {
        final strategiesData = result['data'] as List<dynamic>;
        return strategiesData
            .map((json) => StrategyTemplateInfo.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      
      AppLogger.w(_tag, '策略API响应格式不正确: $result');
      throw Exception('获取策略模板失败');
    } catch (e) {
      AppLogger.error(_tag, '获取可用策略模板失败', e);
      rethrow;
    }
  }

  // ==================== NOVEL_COMPOSE 流式写作编排 ====================
  @override
  Stream<UniversalAIResponse> composeStream({
    required UniversalAIRequest request,
  }) {
    // 强制走写作编排专用控制器
    return _sseClient.streamEvents<UniversalAIResponse>(
      path: '/compose/stream',
      parser: (json) => UniversalAIResponse.fromJson(json),
      eventName: 'message',
      method: SSERequestType.POST,
      body: _toComposeApiJson(request),
      timeout: const Duration(minutes: 5),
    );
  }

  Map<String, dynamic> _toComposeApiJson(UniversalAIRequest request) {
    final json = request.toApiJson();
    // SettingComposeController 接口使用 UniversalAIRequestDto，字段命名保持一致
    // 确保 settingSessionId 在顶层（后端Dto已有该字段）
    if (request.settingSessionId != null) {
      json['settingSessionId'] = request.settingSessionId;
    }
    // Compose 专用：确保 requestType=NOVEL_COMPOSE
    json['requestType'] = AIRequestType.novelCompose.value;
    return json;
  }

  // ==================== 开始写作：确保novelId并保存会话设定 ====================
  Future<String?> startWriting({required String? sessionId, String? novelId, String? historyId}) async {
    try {
      final body = <String, String>{};
      if (sessionId != null) body['sessionId'] = sessionId;
      if (novelId != null) body['novelId'] = novelId;
      if (historyId != null) body['historyId'] = historyId;
      final result = await _apiClient.post('/setting-generation/start-writing', data: body);
      AppLogger.info(_tag, 'startWriting 响应类型: ${result.runtimeType} 内容: $result');
      if (result is Map<String, dynamic> && result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        final id = data != null ? data['novelId'] as String? : null;
        AppLogger.info(_tag, 'startWriting 解析 novelId: $id');
        if (id != null && id.isNotEmpty) return id;
      }
      AppLogger.w(_tag, 'startWriting 未解析到 novelId，返回结果: $result');
      return null;
    } catch (e) {
      AppLogger.error(_tag, '开始写作失败', e);
      return null;
    }
  }
  


  /// 启动新的设定生成
  /// 
  /// 使用场景：用户从小说列表页面发起提示词生成设定请求
  /// 
  /// 业务流程：
  /// 1. 验证和处理用户输入参数
  /// 2. 构建请求体，包含用户ID、提示词、策略模板ID等
  /// 3. 建立SSE连接，实时接收生成事件
  /// 4. 生成完成后会自动创建历史记录
  @override
  Stream<SettingGenerationEvent> startGeneration({
    required String initialPrompt,
    required String promptTemplateId,
    String? novelId,
    required String modelConfigId,
    String? userId,
    bool? usePublicTextModel,
    String? textPhasePublicProvider,
    String? textPhasePublicModelId,
  }) {
    try {
      AppLogger.info(_tag, '启动设定生成: promptTemplateId=$promptTemplateId');
      
      final requestBody = {
        'initialPrompt': initialPrompt,
        'promptTemplateId': promptTemplateId,
        'modelConfigId': modelConfigId,
        // 启用后端新流程：文本优先的混合模式
        'mode': 'hybrid_text_first',
        // 可选：阶段一文本结束标记（后端也有默认值）
        'textEndSentinel': '<<END_OF_SETTINGS>>',
        if (novelId != null) 'novelId': novelId,
        if (userId != null) 'userId': userId,
        if (usePublicTextModel == true) 'usePublicTextModel': true,
        if (textPhasePublicProvider != null) 'textPhasePublicProvider': textPhasePublicProvider,
        if (textPhasePublicModelId != null) 'textPhasePublicModelId': textPhasePublicModelId,
      };

      // 如果没有传入userId，尝试从AppConfig获取
      if (requestBody['userId'] == null) {
        final currentUserId = AppConfig.userId;
        if (currentUserId != null && currentUserId.isNotEmpty) {
          requestBody['userId'] = currentUserId;
          AppLogger.i(_tag, '从AppConfig获取用户ID: $currentUserId');
        }
      }

      return _sseClient.streamEvents<SettingGenerationEvent>(
        path: '/setting-generation/start',
        parser: (json) => SettingGenerationEvent.fromJson(json),
        eventName: null,
        method: SSERequestType.POST,
        body: requestBody,
        timeout: const Duration(minutes: 5), // 延长到5分钟
      );
    } catch (e) {
      AppLogger.error(_tag, '启动设定生成失败', e);
      // 提供用户友好的错误信息
      String userFriendlyMessage = _getUserFriendlyErrorMessage(e);
      return Stream.error(Exception(userFriendlyMessage));
    }
  }

  @override
  Future<void> forceCloseAllSSE() async {
    try {
      await _sseClient.cancelAllConnections();
      // 同时调用底层全局取消，确保插件不再自动重连
      try {
        flutter_sse.SSEClient.unsubscribeFromSSE();
      } catch (_) {}
    } catch (e) {
      AppLogger.error(_tag, '强制关闭所有SSE连接失败', e);
    }
  }

  /// 从小说设定创建编辑会话
  /// 
  /// 核心功能：支持用户选择编辑模式
  /// 
  /// 编辑模式说明：
  /// - createNewSnapshot = true：创建新的设定快照，基于当前小说的最新设定状态
  /// - createNewSnapshot = false：编辑上次的设定，使用用户在该小说的最新历史记录
  /// 
  /// 业务流程：
  /// 1. 用户进入小说设定生成页面
  /// 2. 前端调用此方法创建编辑会话
  /// 3. 后端根据用户选择决定是创建新快照还是使用现有历史记录
  /// 4. 返回会话信息，包含是否基于现有历史记录的标识
  /// 
  /// 返回信息：
  /// - sessionId：会话ID，用于后续的编辑操作
  /// - hasExistingHistory：是否基于现有历史记录创建
  /// - snapshotMode：快照模式（new/existing/auto_new）
  Future<Map<String, dynamic>> startSessionFromNovel({
    required String novelId,
    required String editReason,
    required String modelConfigId,
    required bool createNewSnapshot,
  }) async {
    try {
      AppLogger.info(_tag, '从小说设定创建编辑会话: novelId=$novelId, createNewSnapshot=$createNewSnapshot');
      
      final requestBody = {
        'editReason': editReason,
        'modelConfigId': modelConfigId,
        'createNewSnapshot': createNewSnapshot,
      };

      final result = await _apiClient.post(
        '/setting-generation/novel/$novelId/edit-session',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '编辑会话创建成功');
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '创建编辑会话失败', e);
      rethrow;
    }
  }

  /// 修改设定节点
  /// 
  /// 使用场景：用户在编辑过程中需要修改某个设定节点的内容
  /// 
  /// 业务流程：
  /// 1. 用户选中需要修改的节点
  /// 2. 提供修改提示词说明修改需求
  /// 3. 通过SSE实时接收AI修改过程的事件
  /// 4. 修改完成后更新会话中的节点数据
  @override
  Stream<SettingGenerationEvent> updateNode({
    required String sessionId,
    required String nodeId,
    required String modificationPrompt,
    required String modelConfigId,
    String scope = 'self',
    bool? isPublicModel,
    String? publicModelConfigId,
  }) {
    try {
      AppLogger.info(_tag, '修改设定节点: $nodeId');
      
      final requestBody = {
        'nodeId': nodeId,
        'modificationPrompt': modificationPrompt,
        'modelConfigId': modelConfigId,
        'scope': scope,
        if (isPublicModel == true) 'publicModel': true,
        if (publicModelConfigId != null) 'publicModelConfigId': publicModelConfigId,
      };

      return _sseClient.streamEvents<SettingGenerationEvent>(
        path: '/setting-generation/$sessionId/update-node',
        parser: (json) => SettingGenerationEvent.fromJson(json),
        eventName: null,
        method: SSERequestType.POST,
        body: requestBody,
        timeout: const Duration(minutes: 5), // 延长到5分钟
      );
    } catch (e) {
      AppLogger.error(_tag, '修改设定节点失败', e);
      return Stream.error(e);
    }
  }

  /// 基于会话整体调整生成
  @override
  Stream<SettingGenerationEvent> adjustSession({
    required String sessionId,
    required String adjustmentPrompt,
    required String modelConfigId,
    String? promptTemplateId,
  }) {
    try {
      AppLogger.info(_tag, '会话整体调整生成: $sessionId');

      // 提示词增强：向AI说明保持层级结构/关系引用，不包含UUID等无意义ID
      final enhancedPrompt =
          '请在不破坏现有层级结构与父子关联的前提下对设定进行整体调整。' 
          '保留节点的层级与关系引用（使用名称/路径表达），避免包含任何UUID或无意义的内部ID，以节省令牌。' 
          '调整说明：\n$adjustmentPrompt';

      final requestBody = {
        'adjustmentPrompt': enhancedPrompt,
        'modelConfigId': modelConfigId,
        if (promptTemplateId != null) 'promptTemplateId': promptTemplateId,
      };

      return _sseClient.streamEvents<SettingGenerationEvent>(
        path: '/setting-generation/$sessionId/adjust',
        parser: (json) => SettingGenerationEvent.fromJson(json),
        eventName: null,
        method: SSERequestType.POST,
        body: requestBody,
        timeout: const Duration(minutes: 5),
      );
    } catch (e) {
      AppLogger.error(_tag, '会话整体调整生成失败', e);
      return Stream.error(e);
    }
  }

  /// 直接更新节点内容
  /// 
  /// 使用场景：用户直接编辑节点内容，不通过AI重新生成
  /// 
  /// 与updateNode的区别：
  /// - updateNode：通过AI重新生成节点内容
  /// - updateNodeContent：直接替换节点内容，不经过AI处理
  @override
  Future<String> updateNodeContent({
    required String sessionId,
    required String nodeId,
    required String newContent,
  }) async {
    try {
      AppLogger.info(_tag, '直接更新节点内容: $nodeId');
      
      final requestBody = {
        'nodeId': nodeId,
        'newContent': newContent,
      };

      final result = await _apiClient.post(
        '/setting-generation/$sessionId/update-content',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '节点内容更新成功: $nodeId');
      return result['message'] ?? '节点内容已更新';
    } catch (e) {
      AppLogger.error(_tag, '更新节点内容失败', e);
      rethrow;
    }
  }

  /// 保存生成的设定
  /// 
  /// 业务流程：
  /// 1. 将会话中的设定保存到指定小说的数据库中（如果提供了novelId）
  /// 2. 如果novelId为null，保存为独立快照（不关联任何小说）
  /// 3. 自动创建历史记录快照
  /// 4. 返回包含根设定ID列表和历史记录ID的完整结果
  /// 
  /// 注意：保存完成后会话将被标记为已保存状态
  @override
  Future<SaveResult> saveGeneratedSettings({
    required String sessionId,
    String? novelId,
    bool updateExisting = false,
    String? targetHistoryId,
  }) async {
    try {
      AppLogger.info(_tag, '保存生成的设定: $sessionId, novelId=$novelId, updateExisting=$updateExisting');
      
      final requestBody = <String, dynamic>{};
      if (novelId != null && novelId.isNotEmpty) {
        requestBody['novelId'] = novelId;
      }
      if (updateExisting) {
        requestBody['updateExisting'] = updateExisting;
        if (targetHistoryId != null) {
          requestBody['targetHistoryId'] = targetHistoryId;
        }
      }

      final result = await _apiClient.post(
        '/setting-generation/$sessionId/save',
        data: requestBody,
      );
      // 后端可能返回包裹结构 { success, data: { rootSettingIds, historyId } }
      Map<String, dynamic> resultMap = (result is Map<String, dynamic>) ? result : <String, dynamic>{};
      final Map<String, dynamic> payload = (resultMap['data'] is Map<String, dynamic>)
          ? (resultMap['data'] as Map<String, dynamic>)
          : resultMap;

      String message;
      if (updateExisting) {
        message = '历史记录已成功更新';
      } else {
        message = (novelId != null) ? '设定保存成功，历史记录已自动创建' : '独立快照保存成功';
      }
      AppLogger.info(_tag, message);

      return SaveResult.fromJson(payload);
    } catch (e) {
      AppLogger.error(_tag, '保存生成设定失败', e);
      String userFriendlyMessage = _getUserFriendlyErrorMessage(e);
      throw Exception(userFriendlyMessage);
    }
  }

  /// 获取会话状态
  /// 
  /// 返回会话的详细状态信息，包括：
  /// - 当前状态（初始化、生成中、已完成等）
  /// - 进度百分比
  /// - 当前步骤描述
  /// - 总步骤数
  /// - 错误信息（如果有）
  Future<Map<String, dynamic>> getSessionStatus({
    required String sessionId,
  }) async {
    try {
      AppLogger.info(_tag, '获取会话状态: $sessionId');
      
      final result = await _apiClient.get('/setting-generation/$sessionId/status');
      
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '获取会话状态失败', e);
      rethrow;
    }
  }


  /// 加载历史记录详情（包含完整节点数据）
  @override
  Future<Map<String, dynamic>> loadHistoryDetail({
    required String historyId,
  }) async {
    try {
      AppLogger.info(_tag, '加载历史记录详情: $historyId');

      final result = await _apiClient.get('/setting-histories/$historyId');
      
      // 期望后端返回: { success: true, data: { history: {...}, rootNodes: [...] } }
      if (result is Map<String, dynamic> && result['success'] == true) {
        return result['data'] as Map<String, dynamic>;
      }
      
      throw Exception('加载历史记录详情失败');
    } catch (e) {
      AppLogger.error(_tag, '获取历史记录详情失败', e);
      rethrow;
    }
  }

  /// 取消生成会话
  /// 
  /// 使用场景：用户需要中断正在进行的设定生成过程
  /// 
  /// 业务流程：
  /// 1. 发送取消请求到后端
  /// 2. 后端停止AI生成过程
  /// 3. 会话状态更新为已取消
  /// 4. 清理相关资源
  Future<void> cancelSession({
    required String sessionId,
  }) async {
    try {
      AppLogger.info(_tag, '取消生成会话: $sessionId');
      
      await _apiClient.post('/setting-generation/$sessionId/cancel');
      
      AppLogger.info(_tag, '会话取消成功');
    } catch (e) {
      AppLogger.error(_tag, '取消会话失败', e);
      rethrow;
    }
  }

  // ==================== 历史记录管理 ====================

  /// 获取用户的历史记录列表
  /// 
  /// 重要变更：历史记录管理已从小说维度改为用户维度
  /// 
  /// 新的业务逻辑：
  /// - 按用户ID查询所有历史记录
  /// - 支持通过novelId参数过滤特定小说的历史记录
  /// - 支持分页查询，提高大数据量场景下的性能
  /// - 按创建时间倒序返回，最新记录在前
  /// 
  /// 使用场景：
  /// 1. 历史记录列表页面：novelId为null，显示用户所有历史记录
  /// 2. 小说设定页面：novelId有值，只显示该小说相关的历史记录
  Future<List<Map<String, dynamic>>> getUserHistories({
    String? novelId,
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.info(_tag, '获取用户历史记录: novelId=$novelId, page=$page, size=$size');
      
      // 构建查询参数
      final queryParams = <String, String>{
        'page': page.toString(),
        'size': size.toString(),
      };
      
      // 如果指定了小说ID，添加过滤参数
      if (novelId != null && novelId.isNotEmpty) {
        queryParams['novelId'] = novelId;
      }
      
      // 构建查询字符串
      final queryString = queryParams.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      
      final result = await _apiClient.get('/setting-histories?$queryString');
      
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      } else if (result is Map<String, dynamic> && result['data'] is List) {
        final List<dynamic> histories = result['data'];
        return histories.cast<Map<String, dynamic>>();
      }
      
      AppLogger.w(_tag, '历史记录响应格式不正确: $result');
      return [];
    } catch (e) {
      AppLogger.error(_tag, '获取用户历史记录失败', e);
      return [];
    }
  }

  /// 获取历史记录详情
  /// 
  /// 返回指定历史记录的完整信息，包括：
  /// - 历史记录基本信息
  /// - 包含的所有设定条目数据
  /// - 设定的树形结构关系
  Future<Map<String, dynamic>?> getHistoryDetails({
    required String historyId,
  }) async {
    try {
      AppLogger.info(_tag, '获取历史记录详情: $historyId');
      
      final result = await _apiClient.get('/setting-histories/$historyId');
      
      return result as Map<String, dynamic>?;
    } catch (e) {
      AppLogger.error(_tag, '获取历史记录详情失败', e);
      return null;
    }
  }

  /// 从历史记录创建编辑会话（增强版）
  /// 
  /// 使用场景：用户选择基于某个历史记录进行编辑
  /// 
  /// 业务流程：
  /// 1. 用户在历史记录列表中选择要编辑的记录
  /// 2. 系统基于历史记录中的设定数据创建新的编辑会话
  /// 3. 用户可以在新会话中进行修改和生成操作
  /// 4. 会话标记为基于现有历史记录创建
  Future<Map<String, dynamic>> createEditSessionFromHistory({
    required String historyId,
    required String editReason,
    required String modelConfigId,
  }) async {
    try {
      AppLogger.info(_tag, '从历史记录创建编辑会话: historyId=$historyId');
      
      final requestBody = {
        'editReason': editReason,
        'modelConfigId': modelConfigId,
      };

      final result = await _apiClient.post(
        '/setting-histories/$historyId/edit',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '从历史记录创建会话成功');
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '从历史记录创建会话失败', e);
      rethrow;
    }
  }

  /// 复制历史记录
  /// 
  /// 使用场景：用户希望创建现有历史记录的副本
  /// 
  /// 业务逻辑：
  /// - 创建历史记录的完整副本
  /// - 引用相同的设定条目（不重复创建设定数据）
  /// - 新历史记录有独立的ID和创建时间
  /// - 标记复制来源和原因
  Future<Map<String, dynamic>> copyHistory({
    required String historyId,
    required String copyReason,
  }) async {
    try {
      AppLogger.info(_tag, '复制历史记录: $historyId');
      
      final requestBody = {
        'copyReason': copyReason,
      };

      final result = await _apiClient.post(
        '/setting-histories/$historyId/copy',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '历史记录复制成功');
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '复制历史记录失败', e);
      rethrow;
    }
  }

  /// 恢复历史记录到小说中
  /// 
  /// 核心功能：支持跨小说恢复设定
  /// 
  /// 使用场景：
  /// 1. 将历史版本的设定恢复到当前小说
  /// 2. 将一个小说的设定应用到另一个小说
  /// 3. 设定模板的复用和应用
  /// 
  /// 业务流程：
  /// 1. 获取历史记录中的所有设定条目
  /// 2. 为每个设定条目创建新副本
  /// 3. 更新设定条目的小说ID为目标小说
  /// 4. 保存所有新设定条目到数据库
  /// 5. 返回新创建的设定条目ID列表
  Future<Map<String, dynamic>> restoreHistoryToNovel({
    required String historyId,
    required String novelId,
  }) async {
    try {
      AppLogger.info(_tag, '恢复历史记录到小说: historyId=$historyId, novelId=$novelId');
      
      final requestBody = {
        'novelId': novelId,
      };

      final result = await _apiClient.post(
        '/setting-histories/$historyId/restore',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '历史记录恢复成功');
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '恢复历史记录失败', e);
      rethrow;
    }
  }

  /// 删除历史记录
  /// 
  /// 安全特性：
  /// - 只能删除属于当前用户的历史记录
  /// - 删除时会同时清理相关的节点历史记录
  /// - 删除操作不可恢复，需要用户确认
  Future<void> deleteHistory({
    required String historyId,
  }) async {
    try {
      AppLogger.info(_tag, '删除历史记录: $historyId');
      
      await _apiClient.delete('/setting-histories/$historyId');
      
      AppLogger.info(_tag, '历史记录删除成功');
    } catch (e) {
      AppLogger.error(_tag, '删除历史记录失败', e);
      rethrow;
    }
  }

  /// 批量删除历史记录
  /// 
  /// 使用场景：用户需要清理多个不需要的历史记录
  /// 
  /// 特性：
  /// - 支持同时删除多个历史记录
  /// - 容错处理：单个删除失败不影响其他记录
  /// - 返回实际删除成功的数量
  /// - 权限验证：只能删除属于当前用户的记录
  Future<Map<String, dynamic>> batchDeleteHistories({
    required List<String> historyIds,
  }) async {
    try {
      AppLogger.info(_tag, '批量删除历史记录: ${historyIds.length}个');
      
      final requestBody = {
        'historyIds': historyIds,
      };

      final result = await _apiClient.delete(
        '/setting-histories/batch',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '批量删除历史记录成功');
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(_tag, '批量删除历史记录失败', e);
      rethrow;
    }
  }

  /// 统计历史记录数量
  /// 
  /// 支持按小说过滤统计，用于：
  /// - 显示用户的总历史记录数
  /// - 显示特定小说的历史记录数
  /// - 分页计算和UI显示
  Future<int> countUserHistories({
    String? novelId,
  }) async {
    try {
      AppLogger.info(_tag, '统计用户历史记录数量: novelId=$novelId');
      
      final queryParams = <String, String>{};
      if (novelId != null && novelId.isNotEmpty) {
        queryParams['novelId'] = novelId;
      }
      
      final queryString = queryParams.isNotEmpty 
          ? '?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}'
          : '';
      
      final result = await _apiClient.get('/setting-histories/count$queryString');
      
      if (result is Map<String, dynamic> && result['data'] is int) {
        return result['data'] as int;
      }
      
      return 0;
    } catch (e) {
      AppLogger.error(_tag, '统计历史记录数量失败', e);
      return 0;
    }
  }

  /// 获取节点历史记录
  /// 
  /// 用途：查看单个设定节点的完整变更历史
  /// 
  /// 返回信息：
  /// - 节点的每次变更记录
  /// - 变更前后的内容对比
  /// - 变更操作类型和时间
  /// - 变更描述和版本号
  Future<List<Map<String, dynamic>>> getNodeHistories({
    required String historyId,
    required String nodeId,
    int page = 0,
    int size = 10,
  }) async {
    try {
      AppLogger.info(_tag, '获取节点历史记录: historyId=$historyId, nodeId=$nodeId');
      
      final result = await _apiClient.get(
        '/setting-histories/$historyId/nodes/$nodeId/history?page=$page&size=$size'
      );
      
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      AppLogger.error(_tag, '获取节点历史记录失败', e);
      return [];
    }
  }
  
  /// 获取用户友好的错误信息
  /// 
  /// 将技术性错误信息转换为用户可理解的提示
  /// 帮助用户了解问题原因和解决方案
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('unknown strategy')) {
      return '您选择的生成策略暂时不可用，请刷新页面后重新选择';
    } else if (errorString.contains('text_stage_empty') || errorString.contains('start_failed')) {
      return '当前模型调用异常，请更换模型或稍后重试';
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      return '网络连接失败，请检查网络连接后重试';
    } else if (errorString.contains('timeout')) {
      return '请求超时，请稍后重试';
    } else if (errorString.contains('unauthorized')) {
      return '您的登录状态已过期，请重新登录';
    } else if (errorString.contains('model') || errorString.contains('config')) {
      return 'AI模型配置错误，请检查您的模型设置';
    } else if (errorString.contains('rate limit') || errorString.contains('quota')) {
      return 'AI服务调用频繁，请稍后再试';
    } else {
      return '服务器内部错误，请稍后重试';
    }
  }

  // ==================== 策略管理方法实现 ====================

  /// 创建用户自定义策略
  @override
  Future<Map<String, dynamic>> createCustomStrategy({
    required String name,
    required String description,
    required String systemPrompt,
    required String userPrompt,
    required List<Map<String, dynamic>> nodeTemplates,
    required int expectedRootNodes,
    required int maxDepth,
    String? baseStrategyId,
  }) async {
    try {
      AppLogger.info(_tag, '创建用户自定义策略: $name');
      
      final requestBody = {
        'name': name,
        'description': description,
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        'nodeTemplates': nodeTemplates,
        'expectedRootNodes': expectedRootNodes,
        'maxDepth': maxDepth,
        if (baseStrategyId != null) 'baseStrategyId': baseStrategyId,
      };

      final result = await _apiClient.post(
        '/setting-generation/strategies/custom',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '自定义策略创建成功');
      return parseStrategyResponseTimestamps(result as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error(_tag, '创建自定义策略失败', e);
      rethrow;
    }
  }

  /// 基于现有策略创建新策略
  @override
  Future<Map<String, dynamic>> createStrategyFromBase({
    required String baseTemplateId,
    required String name,
    required String description,
    String? systemPrompt,
    String? userPrompt,
    required Map<String, dynamic> modifications,
  }) async {
    try {
      AppLogger.info(_tag, '基于现有策略创建新策略: $name, 基于: $baseTemplateId');
      
      final requestBody = {
        'name': name,
        'description': description,
        'modifications': modifications,
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
        if (userPrompt != null) 'userPrompt': userPrompt,
      };

      final result = await _apiClient.post(
        '/setting-generation/strategies/from-base/$baseTemplateId',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '基于现有策略的新策略创建成功');
      return parseStrategyResponseTimestamps(result as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error(_tag, '基于现有策略创建失败', e);
      rethrow;
    }
  }

  /// 获取用户的策略列表
  @override
  Future<List<Map<String, dynamic>>> getUserStrategies({
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.info(_tag, '获取用户策略列表: page=$page, size=$size');
      
      final result = await _apiClient.get(
        '/setting-generation/strategies/my?page=$page&size=$size'
      );
      
      if (result is List) {
        return parseResponseListTimestamps(result);
      } else if (result is Map<String, dynamic> && result['data'] is List) {
        final List<dynamic> strategies = result['data'];
        return parseResponseListTimestamps(strategies);
      }
      
      AppLogger.w(_tag, '用户策略响应格式不正确');
      return [];
    } catch (e) {
      AppLogger.error(_tag, '获取用户策略列表失败', e);
      return [];
    }
  }

  /// 获取公开策略列表
  @override
  Future<List<Map<String, dynamic>>> getPublicStrategies({
    String? category,
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.info(_tag, '获取公开策略列表: category=$category, page=$page, size=$size');
      
      final queryParams = <String, String>{
        'page': page.toString(),
        'size': size.toString(),
      };
      
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      
      final queryString = queryParams.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      
      final result = await _apiClient.get(
        '/setting-generation/strategies/public?$queryString'
      );
      
      if (result is List) {
        return parseResponseListTimestamps(result);
      } else if (result is Map<String, dynamic> && result['data'] is List) {
        final List<dynamic> strategies = result['data'];
        return parseResponseListTimestamps(strategies);
      }
      
      AppLogger.w(_tag, '公开策略响应格式不正确');
      return [];
    } catch (e) {
      AppLogger.error(_tag, '获取公开策略列表失败', e);
      return [];
    }
  }

  /// 获取策略详情
  @override
  Future<Map<String, dynamic>?> getStrategyDetail({
    required String strategyId,
  }) async {
    try {
      AppLogger.info(_tag, '获取策略详情: $strategyId');
      
      final result = await _apiClient.get(
        '/setting-generation/strategies/$strategyId'
      );
      
      if (result is Map<String, dynamic>) {
        if (result['success'] == true && result['data'] != null) {
          return parseStrategyResponseTimestamps(result['data'] as Map<String, dynamic>);
        }
        return parseStrategyResponseTimestamps(result);
      }
      
      return null;
    } catch (e) {
      AppLogger.error(_tag, '获取策略详情失败', e);
      return null;
    }
  }

  /// 更新策略
  @override
  Future<Map<String, dynamic>> updateStrategy({
    required String strategyId,
    required String name,
    required String description,
    String? systemPrompt,
    String? userPrompt,
    List<Map<String, dynamic>>? nodeTemplates,
    int? expectedRootNodes,
    int? maxDepth,
  }) async {
    try {
      AppLogger.info(_tag, '更新策略: $strategyId');
      
      final requestBody = <String, dynamic>{
        'name': name,
        'description': description,
      };
      
      if (systemPrompt != null) requestBody['systemPrompt'] = systemPrompt;
      if (userPrompt != null) requestBody['userPrompt'] = userPrompt;
      if (nodeTemplates != null) requestBody['nodeTemplates'] = nodeTemplates;
      if (expectedRootNodes != null) requestBody['expectedRootNodes'] = expectedRootNodes;
      if (maxDepth != null) requestBody['maxDepth'] = maxDepth;

      final result = await _apiClient.put(
        '/setting-generation/strategies/$strategyId',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '策略更新成功');
      return parseStrategyResponseTimestamps(result as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error(_tag, '更新策略失败', e);
      rethrow;
    }
  }

  /// 删除策略
  @override
  Future<void> deleteStrategy({
    required String strategyId,
  }) async {
    try {
      AppLogger.info(_tag, '删除策略: $strategyId');
      
      await _apiClient.delete('/setting-generation/strategies/$strategyId');
      
      AppLogger.info(_tag, '策略删除成功');
    } catch (e) {
      AppLogger.error(_tag, '删除策略失败', e);
      rethrow;
    }
  }

  /// 提交策略审核
  @override
  Future<void> submitStrategyForReview({
    required String strategyId,
  }) async {
    try {
      AppLogger.info(_tag, '提交策略审核: $strategyId');
      
      await _apiClient.post('/setting-generation/strategies/$strategyId/submit-review');
      
      AppLogger.info(_tag, '策略已提交审核');
    } catch (e) {
      AppLogger.error(_tag, '提交策略审核失败', e);
      rethrow;
    }
  }

  /// 获取待审核策略列表（管理员接口）
  @override
  Future<List<Map<String, dynamic>>> getPendingStrategies({
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.info(_tag, '获取待审核策略列表: page=$page, size=$size');
      
      final result = await _apiClient.get(
        '/setting-generation/admin/strategies/pending?page=$page&size=$size'
      );
      
      if (result is List) {
        return parseResponseListTimestamps(result);
      } else if (result is Map<String, dynamic> && result['data'] is List) {
        final List<dynamic> strategies = result['data'];
        return parseResponseListTimestamps(strategies);
      }
      
      AppLogger.w(_tag, '待审核策略响应格式不正确');
      return [];
    } catch (e) {
      AppLogger.error(_tag, '获取待审核策略列表失败', e);
      return [];
    }
  }

  /// 审核策略（管理员接口）
  @override
  Future<void> reviewStrategy({
    required String strategyId,
    required String decision,
    String? comment,
    List<String>? rejectionReasons,
    List<String>? improvementSuggestions,
  }) async {
    try {
      AppLogger.info(_tag, '审核策略: $strategyId, 决定: $decision');
      
      final requestBody = <String, dynamic>{
        'decision': decision,
      };
      
      if (comment != null) requestBody['comment'] = comment;
      if (rejectionReasons != null) requestBody['rejectionReasons'] = rejectionReasons;
      if (improvementSuggestions != null) requestBody['improvementSuggestions'] = improvementSuggestions;

      await _apiClient.post(
        '/setting-generation/admin/strategies/$strategyId/review',
        data: requestBody,
      );
      
      AppLogger.info(_tag, '策略审核完成');
    } catch (e) {
      AppLogger.error(_tag, '审核策略失败', e);
      rethrow;
    }
  }

  // ==================== 工具方法 ====================

  @override
  bool isSessionLinkedToHistory(SettingGenerationSession session) {
    return session.historyId != null && session.historyId!.isNotEmpty;
  }
}
