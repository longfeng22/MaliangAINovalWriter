import 'dart:async';
import '../../models/compose_preview.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../config/app_config.dart';
import '../../models/setting_generation_session.dart';
import '../../models/setting_node.dart';
import '../../models/setting_type.dart';
import '../../models/setting_generation_event.dart' as event_model;
import '../../models/strategy_template_info.dart';
import '../../services/api_service/repositories/setting_generation_repository.dart';
import '../../services/api_service/base/api_exception.dart';
import '../../models/ai_request_models.dart';
import '../../utils/logger.dart';
import '../../utils/setting_node_utils.dart';
import 'setting_generation_event.dart';
import 'setting_generation_state.dart';

/// 设定生成BLoC
/// 
/// 核心业务逻辑：
/// 1. 支持用户维度的历史记录管理，不再依赖特定小说
/// 2. 提供两种编辑模式：创建新快照 vs 编辑上次设定
/// 3. 支持从历史记录创建编辑会话
/// 4. 实现流式节点渲染，提供良好的用户体验
/// 5. 支持跨小说的设定复用和恢复
class SettingGenerationBloc extends Bloc<SettingGenerationBlocEvent, SettingGenerationState> {
  final SettingGenerationRepository _repository;
  final String _tag = 'SettingGenerationBloc';
  
  StreamSubscription? _generationStreamSubscription;
  StreamSubscription? _updateStreamSubscription;
  StreamSubscription? _composeStreamSubscription; // 新增：写作编排流
  Timer? _highlightRemovalTimer;
  Timer? _renderProcessTimer; // 新增：用于处理渲染队列的定时器
  Timer? _timeoutTimer; // 新增：用于处理业务超时的定时器（基于最后活动时间的滑动窗口）
  DateTime? _lastActivityAt; // 新增：记录最后一次收到生成/进度事件的时间
  final Duration _timeoutDuration = const Duration(minutes: 5); // 统一超时时长（调整为5分钟）

  SettingGenerationBloc({
    required SettingGenerationRepository repository,
  })  : _repository = repository,
        super(const SettingGenerationInitial()) {
    on<LoadStrategiesEvent>(_onLoadStrategies);
    on<LoadHistoriesEvent>(_onLoadHistories);
    on<StartSessionFromNovelEvent>(_onStartSessionFromNovel);
    on<StartGenerationEvent>(_onStartGeneration);
    on<AdjustGenerationEvent>(_onAdjustGeneration);
    on<UpdateNodeEvent>(_onUpdateNode);
    on<SelectNodeEvent>(_onSelectNode);
    on<ToggleViewModeEvent>(_onToggleViewMode);
    on<ApplyPendingChangesEvent>(_onApplyPendingChanges);
    on<CancelPendingChangesEvent>(_onCancelPendingChanges);
    on<UndoNodeChangeEvent>(_onUndoNodeChange);
    on<SaveGeneratedSettingsEvent>(_onSaveGeneratedSettings);
    on<CreateNewSessionEvent>(_onCreateNewSession);
    on<SelectSessionEvent>(_onSelectSession);
    on<CreateSessionFromHistoryEvent>(_onLoadHistoryDetail);
    on<UpdateAdjustmentPromptEvent>(_onUpdateAdjustmentPrompt);
    on<GetSessionStatusEvent>(_onGetSessionStatus);
    on<CancelSessionEvent>(_onCancelSession);
    on<GetUserHistoriesEvent>(_onGetUserHistories);
    on<DeleteHistoryEvent>(_onDeleteHistory);
    on<BatchDeleteHistoriesEvent>(_onBatchDeleteHistories);
    on<CopyHistoryEvent>(_onCopyHistory);
    on<RestoreHistoryToNovelEvent>(_onRestoreHistoryToNovel);
    on<ResetEvent>(_onReset);
    on<RetryEvent>(_onRetry);
    // NOVEL_COMPOSE 事件族
    on<StartComposeOutlineEvent>(_onStartComposeOutline);
    on<StartComposeChaptersEvent>(_onStartComposeChapters);
    on<StartComposeBundleEvent>(_onStartComposeBundle);
    on<RefineComposeEvent>(_onRefineCompose);
    on<CancelComposeEvent>(_onCancelCompose);
    on<_HandleGenerationEventInternal>(_onHandleGenerationEvent);
    on<_HandleGenerationErrorInternal>(_onHandleGenerationError);
    on<_HandleGenerationCompleteInternal>(_onHandleGenerationComplete);
    on<_ProcessPendingNodes>(_onProcessPendingNodes);
    on<_TimeoutCheckInternal>(_onTimeoutCheckInternal);
    
    // 新增：渲染相关事件处理器
    on<StartNodeRenderEvent>(_onStartNodeRender);
    on<CompleteNodeRenderEvent>(_onCompleteNodeRender);
    on<ProcessRenderQueueEvent>(_onProcessRenderQueue);
    
    // 新增：内容更新事件处理器
    on<UpdateNodeContentEvent>(_onUpdateNodeContent);
    
    // 新增：手动添加子节点事件处理器
    on<AddChildNodeEvent>(_onAddChildNode);
    
    // 新增：删除节点事件处理器
    on<DeleteNodeEvent>(_onDeleteNode);
    
    // 移除：不再需要的复杂保存节点设定逻辑
    // on<SaveNodeSettingEvent>(_onSaveNodeSetting);
    // on<ConfirmCreateHistoryAndSaveNodeEvent>(_onConfirmCreateHistoryAndSaveNode);
  }

  @override
  Future<void> close() {
    _generationStreamSubscription?.cancel();
    _updateStreamSubscription?.cancel();
    _composeStreamSubscription?.cancel();
    _highlightRemovalTimer?.cancel();
    _renderProcessTimer?.cancel(); // 新增：清理渲染处理定时器
    _timeoutTimer?.cancel(); // 新增：清理超时定时器
    return super.close();
  }

  // ============== 超时相关工具方法（按最后活动时间计算） ==============
  void _resetInactivityTimeout() {
    // 每次重置都会取消旧定时器并设置新定时器，触发时仅派发内部事件
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeoutDuration, () {
      add(const _TimeoutCheckInternal());
    });
  }

  // ==================== NOVEL_COMPOSE 处理器 ====================
  // ===== 写作编排（黄金三章等）UI预览数据通道 =====
  final _composePreviewController = StreamController<List<ComposeChapterPreview>>.broadcast();
  final _composeGeneratingController = StreamController<bool>.broadcast();
  // 新增：写作可开始状态（绑定完成后置为可用）
  final _composeReadyController = StreamController<ComposeReadyInfo>.broadcast();
  String _composeMode = '';
  int _composeExpectedChapters = 0;
  final StringBuffer _composeBuffer = StringBuffer();
  List<ComposeChapterPreview> _composePreview = [];

  Stream<List<ComposeChapterPreview>> get composePreviewStream => _composePreviewController.stream;
  Stream<bool> get composeGeneratingStream => _composeGeneratingController.stream;
  Stream<ComposeReadyInfo> get composeReadyStream => _composeReadyController.stream;

  void _resetComposePreview(String mode, int chapterCount) {
    _composeMode = mode;
    _composeExpectedChapters = chapterCount;
    _composeBuffer.clear();
    _composePreview = List.generate(chapterCount, (i) => ComposeChapterPreview(index: i + 1));
    _composePreviewController.add(List.unmodifiable(_composePreview));
  }

  void _publishComposeGenerating(bool v) {
    _composeGeneratingController.add(v);
  }

  void _handleComposeChunk(UniversalAIResponse resp) {
    // 完成信号（仅以finishReason为准，避免将仅含metadata的分片误判为完成）
    if (resp.finishReason != null && resp.finishReason!.isNotEmpty) {
      _publishComposeGenerating(false);
      return;
    }

    // 新增：处理后端发来的绑定信号（保存完成后将 novelId 与 session 绑定）
    try {
      if (resp.metadata.containsKey('composeBind')) {
        final dynamic bind = resp.metadata['composeBind'];
        String sessionId = '';
        String novelId = '';
        if (bind is Map) {
          sessionId = (bind['sessionId'] ?? '').toString();
          novelId = (bind['novelId'] ?? '').toString();
          if (sessionId.isNotEmpty && novelId.isNotEmpty) {
            _updateSessionNovelId(sessionId, novelId);
          }
        }
        // 推送可开始状态（若有）
        bool? ready;
        String reason = '';
        if (resp.metadata.containsKey('composeReady')) {
          final r = resp.metadata['composeReady'];
          ready = (r is bool) ? r : (r is String ? (r.toLowerCase() == 'true') : null);
        }
        if (resp.metadata.containsKey('composeReadyReason')) {
          reason = (resp.metadata['composeReadyReason'] ?? '').toString();
        }
        try {
          AppLogger.i(_tag, 'ComposeBind: sessionId=' + sessionId + ', novelId=' + novelId + ', ready=' + ((ready == null) ? 'null' : ready.toString()) + ', reason=' + (reason.isEmpty ? 'none' : reason));
        } catch (_) {}
        if (ready != null) {
          _composeReadyController.add(ComposeReadyInfo(
            ready: ready,
            reason: reason,
            novelId: novelId,
            sessionId: sessionId,
          ));
        }
      }
    } catch (_) {}

    // 优先：后端提供的结构化大纲（metadata.composeOutlines）
    try {
      if (resp.metadata.containsKey('composeOutlines') && resp.metadata['composeOutlines'] is List) {
        final List<dynamic> arr = resp.metadata['composeOutlines'] as List<dynamic>;
        final previews = <ComposeChapterPreview>[];
        for (final item in arr) {
          if (item is Map) {
            final idx = (item['index'] is int) ? item['index'] as int : int.tryParse('${item['index']}') ?? (previews.length + 1);
            final title = (item['title'] ?? '').toString();
            final summary = (item['summary'] ?? '').toString();
            previews.add(ComposeChapterPreview(index: idx, title: title, outline: summary));
          }
        }
        if (previews.isNotEmpty) {
          // 保持原有模式（outline_plus_chapters/chapters），仅更新章节预计数量与预览内容
          _composeExpectedChapters = previews.length;
          _composePreview = previews;
          _composePreviewController.add(List.unmodifiable(_composePreview));
          return; // 已消费此分片
        }
      }
    } catch (_) {}

    if (resp.content.isEmpty) return;
    _composeBuffer.write(resp.content);

    //调试日志：分片与模式
    // try {
    //   AppLogger.d(_tag, '[Compose] chunk received, mode=$_composeMode, chunkLen=${resp.content.length}, bufferLen=${_composeBuffer.length}');
    // } catch (_) {}

    final buffer = _composeBuffer.toString();
    if (_composeMode == 'outline') {
      _composePreview = _parseOutlineToPreview(buffer, _composeExpectedChapters);
      _composePreviewController.add(List.unmodifiable(_composePreview));
    } else {
      // 仅当出现章节标签时再解析，避免用纯大纲文本覆盖已通过metadata构建的预览
      final hasChapterTags = RegExp(r"\[CHAPTER_\d+_(?:OUTLINE|CONTENT)\]").hasMatch(buffer);
      if (hasChapterTags) {
        _composePreview = _parseChaptersToPreview(buffer, _composeExpectedChapters);
        _composePreviewController.add(List.unmodifiable(_composePreview));
      }
    }

    // 调试日志：解析后预览摘要
    // try {
    //   final first = _composePreview.isNotEmpty ? _composePreview.first : null;
    //   AppLogger.d(_tag, '[Compose] preview updated: count=${_composePreview.length}, firstTitle=${first?.title}, firstOutlineLen=${first?.outline.length ?? 0}, firstContentLen=${first?.content.length ?? 0}');
    // } catch (_) {}
  }

  List<ComposeChapterPreview> _parseOutlineToPreview(String text, int expected) {
    final List<ComposeChapterPreview> list = List.generate(expected, (i) => ComposeChapterPreview(index: i + 1));

    // 块级解析：一个 [OUTLINE_ITEM ...] 开始，直到下一个 [OUTLINE_ITEM ...] 之前的所有内容归为同一大纲块
    final tag = RegExp(r"\[OUTLINE_ITEM[^\]]*\]");
    final tags = tag.allMatches(text).toList();

    // 将标签前的前导内容并入第1项，避免丢失模型在第一个标签前输出的文字
    if (tags.isNotEmpty && tags.first.start > 0 && expected > 0) {
      final prefix = text.substring(0, tags.first.start).trim();
      if (prefix.isNotEmpty) {
        final mergedTitle = _extractTitle(prefix);
        list[0] = list[0].copyWith(title: mergedTitle, outline: prefix);
      }
    }

    int filled = 0;
    for (int t = 0; t < tags.length && filled < expected; t++) {
      final start = tags[t].start;
      final end = (t + 1 < tags.length) ? tags[t + 1].start : text.length;
      String block = text.substring(start, end).trim();
      if (block.isEmpty) continue;

      // 移除块内首个 [OUTLINE_ITEM ...] 标签，仅保留正文
      block = block.replaceFirst(tag, '').trim();

      final title = _extractTitle(block);
      list[filled] = list[filled].copyWith(title: title, outline: block);
      filled++;
    }

    // 回退：若未匹配到任何带标记的大纲，则按空行分段
    if (filled == 0) {
      final blocks = text.split(RegExp(r"\n\n+"));
      for (final b in blocks) {
        final t = b.trim();
        if (t.isEmpty) continue;
        if (filled >= expected) break;
        list[filled] = list[filled].copyWith(title: _extractTitle(t), outline: t);
        filled++;
      }
    }

    return list;
  }

  List<ComposeChapterPreview> _parseChaptersToPreview(String text, int expected) {
    final List<ComposeChapterPreview> list = List.generate(expected, (i) => ComposeChapterPreview(index: i + 1));
    final outlineTag = RegExp(r"\[CHAPTER_(\d+)_OUTLINE\]");
    final contentTag = RegExp(r"\[CHAPTER_(\d+)_CONTENT\]");

    // 找到所有标签位置（兼容 OUTLINE_ITEM）
    final tagPattern = RegExp(r"\[(?:\s*OUTLINE\s*_ITEM[^\]]+|CHAPTER_\d+_OUTLINE|CHAPTER_\d+_CONTENT)\]");
    final tags = tagPattern.allMatches(text).toList();

    // 前置无标签片段并入第1章大纲，避免丢失信息
    if (tags.isNotEmpty && tags.first.start > 0 && expected > 0) {
      final prefix = text.substring(0, tags.first.start).trim();
      if (prefix.isNotEmpty) {
        final old = list[0];
        final mergedOutline = (old.outline.isEmpty ? '' : old.outline + "\n") + prefix;
        list[0] = old.copyWith(outline: mergedOutline);
      }
    }

    for (int t = 0; t < tags.length; t++) {
      final match = tags[t];
      final tagText = text.substring(match.start, match.end);
      final start = match.end;
      final end = (t + 1 < tags.length) ? tags[t + 1].start : text.length;
      final segment = text.substring(start, end).trim();

      final outlineM = outlineTag.firstMatch(tagText);
      final contentM = contentTag.firstMatch(tagText);
      if (outlineM != null) {
        final idx = int.tryParse(outlineM.group(1) ?? '') ?? 0;
        if (idx >= 1 && idx <= expected) {
          final old = list[idx - 1];
          list[idx - 1] = old.copyWith(title: _extractTitle(segment), outline: segment);
        }
        continue;
      }
      if (contentM != null) {
        final idx = int.tryParse(contentM.group(1) ?? '') ?? 0;
        if (idx >= 1 && idx <= expected) {
          final old = list[idx - 1];
          list[idx - 1] = old.copyWith(content: segment);
        }
        continue;
      }

      // 兼容：当仍输出 [OUTLINE_ITEM ...] 时，按顺序或 index= 提示填充
      if (RegExp(r"OUTLINE\s*_ITEM", caseSensitive: false).hasMatch(tagText)) {
        int? idx;
        final m = RegExp(r"index\s*=\s*(\d+)", caseSensitive: false).firstMatch(tagText);
        if (m != null) idx = int.tryParse(m.group(1) ?? '');
        if (idx != null && idx >= 1 && idx <= expected) {
          final old = list[idx - 1];
          final title = _extractTitle(segment);
          list[idx - 1] = old.copyWith(title: title, outline: segment);
        } else {
          for (int i = 0; i < expected; i++) {
            if (list[i].outline.isEmpty) {
              final old = list[i];
              final title = _extractTitle(segment);
              list[i] = old.copyWith(title: title, outline: segment);
              break;
            }
          }
        }
      }
    }
    return list;
  }

  String _extractTitle(String text) {
    // 简易提取：匹配 "标题：xxx" 或第一行前20字
    final m = RegExp(r"标题[:：]\s*([^\n]{2,40})").firstMatch(text);
    if (m != null) return m.group(1)!.trim();
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 20 ? firstLine.substring(0, 20) : firstLine;
  }
  void _onStartComposeOutline(
    StartComposeOutlineEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    final composeParams = {
      'mode': 'outline',
      'chapterCount': event.chapterCount,
      ...event.parameters,
    };
    _resetComposePreview('outline', event.chapterCount);
    _publishComposeGenerating(true);
    _startComposeCommon(
      emit: emit,
      userId: event.userId,
      novelId: event.novelId,
      modelConfigId: event.modelConfigId,
      prompt: event.prompt,
      instructions: event.instructions,
      settingSessionId: event.settingSessionId,
      rawContextSelections: event.contextSelections,
      parameters: composeParams,
      startOperationText: '正在生成大纲...',
      isPublicModel: event.isPublicModel,
      publicModelConfigId: event.publicModelConfigId,
    );
  }

  void _onStartComposeChapters(
    StartComposeChaptersEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    final composeParams = {
      'mode': 'chapters',
      'chapterCount': event.chapterCount,
      ...event.parameters,
    };
    _resetComposePreview('chapters', event.chapterCount);
    _publishComposeGenerating(true);
    _startComposeCommon(
      emit: emit,
      userId: event.userId,
      novelId: event.novelId,
      modelConfigId: event.modelConfigId,
      prompt: event.prompt,
      instructions: event.instructions,
      settingSessionId: event.settingSessionId,
      rawContextSelections: event.contextSelections,
      parameters: composeParams,
      startOperationText: '正在生成章节...',
      isPublicModel: event.isPublicModel,
      publicModelConfigId: event.publicModelConfigId,
    );
  }

  void _onStartComposeBundle(
    StartComposeBundleEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    final composeParams = {
      'mode': 'outline_plus_chapters',
      'chapterCount': event.chapterCount,
      ...event.parameters,
    };
    _resetComposePreview('outline_plus_chapters', event.chapterCount);
    _publishComposeGenerating(true);
    _startComposeCommon(
      emit: emit,
      userId: event.userId,
      novelId: event.novelId,
      modelConfigId: event.modelConfigId,
      prompt: event.prompt,
      instructions: event.instructions,
      settingSessionId: event.settingSessionId,
      rawContextSelections: event.contextSelections,
      parameters: composeParams,
      startOperationText: '正在生成大纲与章节...',
      isPublicModel: event.isPublicModel,
      publicModelConfigId: event.publicModelConfigId,
    );
  }

  void _onRefineCompose(
    RefineComposeEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    final composeParams = {
      ...event.parameters,
    };
    _startComposeCommon(
      emit: emit,
      userId: event.userId,
      novelId: event.novelId,
      modelConfigId: event.modelConfigId,
      prompt: null,
      instructions: event.instructions,
      settingSessionId: event.settingSessionId,
      rawContextSelections: event.contextSelections,
      parameters: composeParams,
      startOperationText: '正在根据指令微调...',
    );
  }

  void _onCancelCompose(
    CancelComposeEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    _composeStreamSubscription?.cancel();
    if (state is SettingGenerationInProgress) {
      final s = state as SettingGenerationInProgress;
      emit(s.copyWith(
        isGenerating: false,
        currentOperation: '已取消写作编排',
      ));
    }
  }

  // 新增：在本地会话列表中把 novelId 绑定到指定 sessionId
  void _updateSessionNovelId(String sessionId, String novelId) {
    try {
      if (novelId.isEmpty || sessionId.isEmpty) return;

      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        // 仅当目标session是当前活跃会话时更新
        if (currentState.activeSessionId == sessionId) {
          final updatedActive = currentState.activeSession.copyWith(novelId: novelId);
          final updatedSessions = currentState.sessions.map((s) => s.sessionId == sessionId ? updatedActive : s).toList();
          emit(currentState.copyWith(activeSession: updatedActive, sessions: updatedSessions));
        }
        return;
      }
      if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        if (currentState.activeSessionId == sessionId) {
          final updatedActive = currentState.activeSession.copyWith(novelId: novelId);
          final updatedSessions = currentState.sessions.map((s) => s.sessionId == sessionId ? updatedActive : s).toList();
          emit(currentState.copyWith(activeSession: updatedActive, sessions: updatedSessions));
        }
        return;
      }
    } catch (_) {}
  }

  void _startComposeCommon({
    required Emitter<SettingGenerationState> emit,
    required String userId,
    String? novelId,
    required String modelConfigId,
    String? prompt,
    String? instructions,
    String? settingSessionId,
    Map<String, dynamic>? rawContextSelections,
    required Map<String, dynamic> parameters,
    required String startOperationText,
    bool? isPublicModel,
    String? publicModelConfigId,
  }) {
    // 不触发设定树状态切换，避免 UI 刷新
    _markActivityAndResetTimeout();

    // 若未传入，尽力从当前状态补齐 novelId / settingSessionId
    String? effectiveNovelId = novelId;
    String? effectiveSessionId = settingSessionId;
    if (effectiveSessionId == null) {
      if (state is SettingGenerationInProgress) {
        effectiveSessionId = (state as SettingGenerationInProgress).activeSessionId;
        effectiveNovelId ??= (state as SettingGenerationInProgress).activeSession.novelId;
      } else if (state is SettingGenerationReady) {
        final s = state as SettingGenerationReady;
        effectiveSessionId = s.activeSessionId;
      } else if (state is SettingGenerationCompleted) {
        final s = state as SettingGenerationCompleted;
        effectiveSessionId = s.activeSessionId;
        effectiveNovelId ??= s.activeSession.novelId;
      }
    }

    // 组装通用请求（在BLoC层完成参数拼接）
    final requestJson = <String, dynamic>{
      'requestType': AIRequestType.novelCompose.value,
      'userId': userId,
      if (effectiveNovelId != null) 'novelId': effectiveNovelId,
      if (effectiveSessionId != null) 'settingSessionId': effectiveSessionId,
      if (prompt != null) 'prompt': prompt,
      if (instructions != null) 'instructions': instructions,
      'parameters': parameters,
      'metadata': {
        'modelConfigId': modelConfigId,
        if (isPublicModel == true) 'isPublicModel': true,
        if (publicModelConfigId != null) 'publicModelConfigId': publicModelConfigId,
      },
      if (rawContextSelections != null) 'contextSelections': rawContextSelections['contextSelections'],
      if (rawContextSelections != null && rawContextSelections['enableSmartContext'] != null)
        'enableSmartContext': rawContextSelections['enableSmartContext'],
    };

    // 调试：关键元数据
    try {
      AppLogger.d(_tag, '[Compose] building request: modelConfigId=$modelConfigId, novelId=' +
          (effectiveNovelId ?? 'null') + ', settingSessionId=' + (effectiveSessionId ?? 'null'));
    } catch (_) {}

    final request = UniversalAIRequest.fromJson(requestJson);

    _composeStreamSubscription?.cancel();
    _composeStreamSubscription = _repository.composeStream(request: request).listen(
      (resp) {
        // 不更新设定树状态，由结果预览模块单独消费内容
        _markActivityAndResetTimeout();
        // 将分片推入UI预览解析
        try {
          _handleComposeChunk(resp);
        } catch (_) {}
      },
      onError: (error, stackTrace) {
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        add(_HandleGenerationErrorInternal(error, stackTrace));
      },
      onDone: () {
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        add(const _HandleGenerationCompleteInternal());
        _publishComposeGenerating(false);
      },
    );
  }

  void _markActivityAndResetTimeout() {
    _lastActivityAt = DateTime.now();
    _resetInactivityTimeout();
  }

  /// 加载可用策略
  /// 
  /// 支持同时加载历史记录（如果提供了相关参数）
  Future<void> _onLoadStrategies(
    LoadStrategiesEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    // 检查是否已经加载了策略，避免重复加载
    if (state is SettingGenerationReady ||
        state is SettingGenerationInProgress ||
        state is SettingGenerationCompleted) {
      AppLogger.i(_tag, '策略已加载，跳过重复加载');
      return;
    }
    
    // 未登录时：加载公开策略；已登录：加载可用策略+历史
    try {
      final String? uid = AppConfig.userId;
      emit(const SettingGenerationLoading(message: '正在加载生成策略...'));
      
      late final List<StrategyTemplateInfo> strategies;
      if (uid == null || uid.isEmpty) {
        final publicList = await _repository.getPublicStrategies();
        strategies = publicList
            .map((e) => StrategyTemplateInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        // 合并：公开策略 + 用户自己的策略，去重按 promptTemplateId
        final publicList = await _repository.getPublicStrategies();
        final myList = await _repository.getUserStrategies();
        final merged = <String, StrategyTemplateInfo>{};
        for (final e in publicList) {
          final item = StrategyTemplateInfo.fromJson(e as Map<String, dynamic>);
          merged[item.promptTemplateId] = item;
        }
        for (final e in myList) {
          final item = StrategyTemplateInfo.fromJson(e as Map<String, dynamic>);
          merged[item.promptTemplateId] = item;
        }
        strategies = merged.values.toList();
      }
      
      // 游客模式下不拉取历史记录；仅已登录且有 userId 时加载
      List<Map<String, dynamic>> histories = [];
      final String? currentUserId = AppConfig.userId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          AppLogger.i(_tag, '加载当前用户历史记录, novelId=${event.novelId}');
          histories = await _repository.getUserHistories(novelId: event.novelId);
          AppLogger.i(_tag, '成功加载${histories.length}条历史记录');
        } catch (e) {
          AppLogger.error(_tag, '加载历史记录失败，但继续执行', e);
          // 历史记录加载失败不影响策略加载
        }
      } else {
        AppLogger.i(_tag, '未登录，跳过加载历史记录');
      }
      
      // 转换历史记录为Session对象（为了兼容现有逻辑）
      final sessions = histories.map((history) {
        return SettingGenerationSession.fromJson(history);
      }).toList();
      
      emit(SettingGenerationReady(
        strategies: strategies,
        sessions: sessions,
      ));
      // 若已登录但 sessions 为空，尝试主动加载一次历史记录列表
      final String? uid2 = AppConfig.userId;
      if ((uid2 != null && uid2.isNotEmpty) && sessions.isEmpty) {
        add(const GetUserHistoriesEvent());
      }
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '加载策略失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '加载生成策略失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// 加载历史记录
  /// 
  /// 使用用户维度的历史记录管理
  Future<void> _onLoadHistories(
    LoadHistoriesEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    if (state is! SettingGenerationReady) {
      AppLogger.w(_tag, '当前状态不支持加载历史记录: ${state.runtimeType}');
      return;
    }

    try {
      AppLogger.i(_tag, '加载历史记录: novelId=${event.novelId}, userId=${event.userId}');
      
      final currentState = state as SettingGenerationReady;
      
      emit(const SettingGenerationLoading(message: '正在加载历史记录...'));
      
      // 使用新的用户维度历史记录API
      final histories = await _repository.getUserHistories(
        novelId: event.novelId,
        page: event.page,
        size: event.size,
      );
      
      // 转换为Session对象
      final sessions = histories.map((history) {
        return SettingGenerationSession.fromJson(history);
      }).toList();
      
      emit(currentState.copyWith(
        sessions: sessions,
      ));
      
      AppLogger.i(_tag, '成功加载${sessions.length}条历史记录');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '加载历史记录失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '加载历史记录失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// 从小说设定创建编辑会话
  /// 
  /// 支持用户选择创建新快照或编辑上次设定
  Future<void> _onStartSessionFromNovel(
    StartSessionFromNovelEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '从小说设定创建编辑会话: ${event.novelId}, createNewSnapshot: ${event.createNewSnapshot}');
      
      emit(const SettingGenerationLoading(message: '正在创建编辑会话...'));
      
      final result = await _repository.startSessionFromNovel(
        novelId: event.novelId,
        editReason: event.editReason,
        modelConfigId: event.modelConfigId,
        createNewSnapshot: event.createNewSnapshot,
      );
      
      // 解析返回结果
      final sessionId = result['sessionId'] as String;
      final hasExistingHistory = result['hasExistingHistory'] as bool? ?? false;
      final snapshotMode = result['snapshotMode'] as String? ?? 'new';
      
      // 获取当前策略和会话列表
      final currentState = state;
      List<StrategyTemplateInfo> strategies = [];
      List<SettingGenerationSession> sessions = [];
      
      if (currentState is SettingGenerationReady) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      }
      
      // 创建会话对象
      final session = SettingGenerationSession(
        sessionId: sessionId,
        userId: AppConfig.userId ?? 'current_user',
        novelId: event.novelId,
        initialPrompt: event.editReason,
        strategy: '编辑模式',
        modelConfigId: event.modelConfigId,
        status: SessionStatus.completed, // 编辑会话直接为完成状态
        createdAt: DateTime.now(),
        rootNodes: [], // 节点数据将从后端获取
      );
      
      final updatedSessions = [session, ...sessions];
      
      emit(SettingGenerationCompleted(
        strategies: strategies,
        sessions: updatedSessions,
        activeSessionId: sessionId,
        activeSession: session,
        message: hasExistingHistory ? '已加载上次设定进行编辑' : '已创建新的设定快照',
        // 🔧 关键修复：确保所有节点都可见
        renderedNodeIds: _collectAllNodeIds(session.rootNodes).toSet(),
      ));
      
      AppLogger.i(_tag, '编辑会话创建成功: $sessionId, 快照模式: $snapshotMode');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '创建编辑会话失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '创建编辑会话失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// 开始生成
  Future<void> _onStartGeneration(
    StartGenerationEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      // 🔧 新增：检查和设置测试用户ID（仅用于开发环境）
      if (AppConfig.userId == null || AppConfig.userId!.isEmpty) {
        const testUserId = 'test_user_67d67d6833335f5166782e6f'; // 使用固定的测试用户ID
        AppConfig.setUserId(testUserId);
        AppLogger.w(_tag, '⚠️ 设置测试用户ID: $testUserId（仅用于开发环境）');
      }
      
      // 🔧 修复：允许从错误状态重试
      if (state is! SettingGenerationReady &&
          state is! SettingGenerationCompleted &&
          state is! SettingGenerationInProgress &&
          state is! SettingGenerationError) {
        emit(const SettingGenerationError(
          message: '系统未初始化完成，请稍后再试',
          isRecoverable: true,
        ));
        return;
      }

      // 🔧 新增：如果当前是错误状态，先重置为准备状态
      if (state is SettingGenerationError) {
        AppLogger.w(_tag, '🔄 从错误状态重试生成，先重置状态');
        emit(const SettingGenerationLoading(message: '正在重置状态...'));
        
        // 获取策略数据（如果有的话）
        try {
          final strategies = await _repository.getAvailableStrategies();
          emit(SettingGenerationReady(
            strategies: strategies,
            sessions: [],
          ));
        } catch (e) {
          AppLogger.error(_tag, '重置状态失败', e);
          emit(SettingGenerationError(
            message: '重置失败，请刷新页面重试：${e.toString()}',
            error: e,
            isRecoverable: false,
          ));
          return;
        }
      }

      final currentState = state;
      List<StrategyTemplateInfo> strategies = [];
      List<SettingGenerationSession> sessions = [];
      
      if (currentState is SettingGenerationReady) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationInProgress) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationCompleted) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationError) {
        // 从错误状态恢复，仅保留会话列表
        sessions = currentState.sessions;
      }

      // 🔧 修复：使用UUID生成sessionId（与后端保持一致）
      final sessionId = const Uuid().v4();
      final newSession = SettingGenerationSession(
        sessionId: sessionId,
        userId: event.userId ?? AppConfig.userId ?? 'default_user',
        novelId: event.novelId,
        initialPrompt: event.initialPrompt,
        strategy: event.promptTemplateId,
        modelConfigId: event.modelConfigId,
        status: SessionStatus.initializing,
        createdAt: DateTime.now(),
      );

      final updatedSessions = [newSession, ...sessions];

      emit(SettingGenerationInProgress(
        strategies: strategies,
        sessions: updatedSessions,
        activeSessionId: sessionId,
        activeSession: newSession,
        isGenerating: true,
        currentOperation: '正在初始化生成会话...',
      ));

      // 启动真实的生成流
      AppLogger.i(_tag, '🚀 启动生成流程');
      
      // 启动/重置基于最后活动时间的超时定时器
      _markActivityAndResetTimeout();
      
      // 监听生成流
      _generationStreamSubscription?.cancel();
      _generationStreamSubscription = _repository.startGeneration(
        sessionId: sessionId,  // 🔧 传递前端生成的sessionId
        initialPrompt: event.initialPrompt,
        promptTemplateId: event.promptTemplateId,
        novelId: event.novelId,
        modelConfigId: event.modelConfigId,
        userId: event.userId,
        usePublicTextModel: event.usePublicTextModel,
        textPhasePublicProvider: event.textPhasePublicProvider,
        textPhasePublicModelId: event.textPhasePublicModelId,
        // 📚 知识库集成参数
        knowledgeBaseMode: event.knowledgeBaseMode,
        knowledgeBaseIds: event.knowledgeBaseIds,
        knowledgeBaseCategories: event.knowledgeBaseCategories,
        // 📚 混合模式专用参数
        reuseKnowledgeBaseIds: event.reuseKnowledgeBaseIds,
        referenceKnowledgeBaseIds: event.referenceKnowledgeBaseIds,
        // 🔧 结构化输出循环模式参数
        useStructuredOutput: event.useStructuredOutput,
        structuredIterations: event.structuredIterations,
      ).listen(
        (generationEvent) {
          add(_HandleGenerationEventInternal(generationEvent));
        },
        onError: (error, stackTrace) {
          AppLogger.error(_tag, '生成流错误', error, stackTrace);
          // 取消超时定时器
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          String userFriendlyMessage = _getUserFriendlyErrorMessage(error);
          add(_HandleGenerationErrorInternal(error, stackTrace, userFriendlyMessage));
        },
        onDone: () {
          AppLogger.info(_tag, '生成流完成');
          // 取消超时定时器
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          add(const _HandleGenerationCompleteInternal());
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '开始生成失败', e, stackTrace);
      String userFriendlyMessage = _getUserFriendlyErrorMessage(e);
      emit(SettingGenerationError(
        message: userFriendlyMessage,
        error: e,
        stackTrace: stackTrace,
        isRecoverable: _isRecoverableError(e),
      ));
    }
  }

  /// 基于当前会话的整体调整生成
  Future<void> _onAdjustGeneration(
    AdjustGenerationEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      // 仅允许在有会话的状态下调整
      if (state is! SettingGenerationInProgress && state is! SettingGenerationCompleted) {
        emit(const SettingGenerationError(
          message: '当前没有可调整的会话，请先生成或加载历史记录',
        ));
        return;
      }

      // 取现有策略/会话用于维持UI
      List<StrategyTemplateInfo> strategies = [];
      List<SettingGenerationSession> sessions = [];
      String activeSessionId = '';
      SettingGenerationSession? activeSession;

      if (state is SettingGenerationInProgress) {
        final s = state as SettingGenerationInProgress;
        strategies = s.strategies;
        sessions = s.sessions;
        activeSessionId = s.activeSessionId;
        activeSession = s.activeSession;
      } else if (state is SettingGenerationCompleted) {
        final s = state as SettingGenerationCompleted;
        strategies = s.strategies;
        sessions = s.sessions;
        activeSessionId = s.activeSessionId;
        activeSession = s.activeSession;
      }

      // 校验 session 一致
      if (activeSessionId.isEmpty || activeSession == null || activeSessionId != event.sessionId) {
        AppLogger.w(_tag, 'AdjustGenerationEvent 的 sessionId 与当前会话不一致，使用事件给定的sessionId继续');
        activeSessionId = event.sessionId;
      }

      // 进入进行中状态，展示生成中提示
      emit(SettingGenerationInProgress(
        strategies: strategies,
        sessions: sessions,
        activeSessionId: activeSessionId,
        activeSession: activeSession ?? sessions.firstWhere((s) => s.sessionId == activeSessionId, orElse: () => sessions.first),
        isGenerating: true,
        currentOperation: '正在基于当前会话整体调整...',
        adjustmentPrompt: event.adjustmentPrompt,
      ));

      // 启动/重置超时
      _markActivityAndResetTimeout();

      // 打开 SSE 流
      _generationStreamSubscription?.cancel();
      _generationStreamSubscription = _repository.adjustSession(
        sessionId: activeSessionId,
        adjustmentPrompt: event.adjustmentPrompt,
        modelConfigId: event.modelConfigId,
        promptTemplateId: event.promptTemplateId ?? activeSession?.metadata['promptTemplateId'],
      ).listen(
        (generationEvent) {
          add(_HandleGenerationEventInternal(generationEvent));
        },
        onError: (error, stackTrace) {
          AppLogger.error(_tag, '调整生成流错误', error, stackTrace);
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          add(_HandleGenerationErrorInternal(error, stackTrace));
        },
        onDone: () {
          AppLogger.info(_tag, '调整生成流完成');
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          add(const _HandleGenerationCompleteInternal());
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '调整生成失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '调整生成失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        isRecoverable: true,
        sessions: _getCurrentSessions(),
      ));
    }
  }

  /// 更新节点
  Future<void> _onUpdateNode(
    UpdateNodeEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    // 🔧 修复：支持从多种状态开始节点修改
    String? sessionId;
    SettingGenerationSession? activeSession;
    List<StrategyTemplateInfo> strategies = [];
    List<SettingGenerationSession> sessions = [];
          String? selectedNodeId;
    String viewMode = 'compact';
    String adjustmentPrompt = '';
    Map<String, SettingNode> pendingChanges = {};
    Set<String> highlightedNodeIds = {};
    Map<String, List<SettingNode>> editHistory = {};
    List<event_model.SettingGenerationEvent> events = [];
    Map<String, NodeRenderInfo> nodeRenderStates = {};
    Set<String> renderedNodeIds = {};
    
    if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      sessionId = currentState.activeSessionId;
      activeSession = currentState.activeSession;
      strategies = currentState.strategies;
      sessions = currentState.sessions;
      selectedNodeId = currentState.selectedNodeId;
      viewMode = currentState.viewMode;
      adjustmentPrompt = currentState.adjustmentPrompt;
      pendingChanges = currentState.pendingChanges;
      highlightedNodeIds = currentState.highlightedNodeIds;
      editHistory = currentState.editHistory;
      events = currentState.events;
      nodeRenderStates = currentState.nodeRenderStates;
      renderedNodeIds = currentState.renderedNodeIds;
    } else if (state is SettingGenerationCompleted) {
      final currentState = state as SettingGenerationCompleted;
      // 🔧 修正：节点修改必须使用真实 sessionId（不要传 historyId）
      sessionId = currentState.activeSession.sessionId;
      activeSession = currentState.activeSession;
      strategies = currentState.strategies;
      sessions = currentState.sessions;
      selectedNodeId = currentState.selectedNodeId;
      viewMode = currentState.viewMode;
      adjustmentPrompt = currentState.adjustmentPrompt;
      pendingChanges = currentState.pendingChanges;
      highlightedNodeIds = currentState.highlightedNodeIds;
      editHistory = currentState.editHistory;
      events = currentState.events;
      nodeRenderStates = currentState.nodeRenderStates;
      renderedNodeIds = currentState.renderedNodeIds;
    } else if (state is SettingGenerationNodeUpdating) {
      final currentState = state as SettingGenerationNodeUpdating;
      sessionId = currentState.activeSessionId;
      activeSession = currentState.activeSession;
      strategies = currentState.strategies;
      sessions = currentState.sessions;
      selectedNodeId = currentState.selectedNodeId;
      viewMode = currentState.viewMode;
      adjustmentPrompt = currentState.adjustmentPrompt;
      pendingChanges = currentState.pendingChanges;
      highlightedNodeIds = currentState.highlightedNodeIds;
      editHistory = currentState.editHistory;
      events = currentState.events;
      nodeRenderStates = currentState.nodeRenderStates;
      renderedNodeIds = currentState.renderedNodeIds;
    } else {
      emit(const SettingGenerationError(message: '当前状态不支持节点修改'));
      return;
    }


    
    // 🔧 校验会话ID与会话对象
    if (sessionId == null || sessionId.isEmpty) {
      AppLogger.e(_tag, '❌ 无有效的会话ID，无法进行节点修改（state=${state.runtimeType}）');
      emit(SettingGenerationError(
        message: '没有有效的会话，无法修改节点',
        sessions: sessions,
        activeSessionId: null,
      ));
      return;
    }
    if (activeSession == null) {
      AppLogger.e(_tag, '❌ 无有效会话对象，无法进行节点修改');
      emit(SettingGenerationError(
        message: '会话无效，无法修改节点',
        sessions: sessions,
        activeSessionId: sessionId,
      ));
      return;
    }

    try {
      AppLogger.i(_tag, '🔧 开始节点修改 - sessionId: $sessionId, nodeId: ${event.nodeId}');
      
      // 🔧 修复：使用新的SettingGenerationNodeUpdating状态，避免整个设定树重新渲染
      emit(SettingGenerationNodeUpdating(
        strategies: strategies,
        sessions: sessions,
        activeSessionId: sessionId!,
        activeSession: activeSession!,
        selectedNodeId: selectedNodeId,
        viewMode: viewMode,
        adjustmentPrompt: adjustmentPrompt,
        pendingChanges: pendingChanges,
        highlightedNodeIds: highlightedNodeIds,
        editHistory: editHistory,
        events: events,
        updatingNodeId: event.nodeId,
        modificationPrompt: event.modificationPrompt,
        scope: event.scope,
        isUpdating: true,
        message: '正在根据提示修改节点内容，请稍候...',
        nodeRenderStates: nodeRenderStates,
        renderedNodeIds: renderedNodeIds,
      ));

      // 启动/重置基于最后活动时间的超时定时器
      _markActivityAndResetTimeout();

      _updateStreamSubscription?.cancel();
      _updateStreamSubscription = _repository.updateNode(
        sessionId: sessionId!,
        nodeId: event.nodeId,
        modificationPrompt: event.modificationPrompt,
        modelConfigId: event.modelConfigId,
        scope: event.scope,
        isPublicModel: event.isPublicModel,
        publicModelConfigId: event.publicModelConfigId,
      ).listen(
        (generationEvent) {
          AppLogger.i(_tag, '📡 收到节点修改事件: ${generationEvent.eventType}');
          add(_HandleGenerationEventInternal(generationEvent));
        },
        onError: (error, stackTrace) {
          AppLogger.error(_tag, '更新节点流错误', error, stackTrace);
          // 取消超时定时器
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          // NodeUpdating阶段：不进入错误态，直接结束，保持原态（Toast 交给外层 Screen 监听错误状态触发）
          add(_HandleGenerationCompleteInternal());
        },
        onDone: () {
          AppLogger.info(_tag, '更新节点流完成');
          // 取消超时定时器
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          add(const _HandleGenerationCompleteInternal());
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '更新节点失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '更新节点失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        sessions: sessions,
        activeSessionId: sessionId,
      ));
    }
  }

  /// 更新节点内容
  /// 直接调用后端API更新节点内容
  void _onUpdateNodeContent(
    UpdateNodeContentEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      // 获取当前会话ID
      String? sessionId;
      
      if (state is SettingGenerationInProgress) {
        sessionId = (state as SettingGenerationInProgress).activeSessionId;
      } else if (state is SettingGenerationCompleted) {
        sessionId = (state as SettingGenerationCompleted).activeSession.sessionId;
      } else {
        // 修改：当没有活跃会话时，静默忽略而不是报错
        AppLogger.info(_tag, '没有活跃会话，忽略节点内容更新: ${event.nodeId}');
        return;
      }
      
      // 🔧 新增：调试日志
      final currentUserId = AppConfig.userId;
      AppLogger.i(_tag, '🔧 准备更新节点内容: sessionId=$sessionId, nodeId=${event.nodeId}, userId=$currentUserId');
      

      
      // 先在本地更新UI状态
      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        final updatedNodes = _updateNodeContentInTree(
          currentState.activeSession.rootNodes,
          event.nodeId,
          event.content,
        );
        
        final updatedSession = currentState.activeSession.copyWith(
          rootNodes: updatedNodes,
        );
        
        emit(currentState.copyWith(
          activeSession: updatedSession,
        ));
      } else if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        final updatedNodes = _updateNodeContentInTree(
          currentState.activeSession.rootNodes,
          event.nodeId,
          event.content,
        );
        
        final updatedSession = currentState.activeSession.copyWith(
          rootNodes: updatedNodes,
        );
        
        emit(currentState.copyWith(
          activeSession: updatedSession,
        ));
      }
      
      // 异步调用后端API保存更改
      // 🔧 新增：API调用前日志
      AppLogger.i(_tag, '🚀 开始调用后端API更新节点内容: sessionId=$sessionId, nodeId=${event.nodeId}');
      
      try {
        await _repository.updateNodeContent(
          sessionId: sessionId,
          nodeId: event.nodeId,
          newContent: event.content,
        );
        
        // 🔧 新增：API调用成功日志
        AppLogger.i(_tag, '✅ 后端API调用成功: sessionId=$sessionId, nodeId=${event.nodeId}');
      } catch (e, stackTrace) {
        // 🔧 增强：错误日志
        AppLogger.error(_tag, '❌ 后端API调用失败: sessionId=$sessionId, nodeId=${event.nodeId}, error=${e.toString()}', e, stackTrace);
        
        // 可选：发送错误状态给UI
        emit(SettingGenerationError(
          message: '保存节点内容失败：${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ));
      }
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '更新节点内容失败', e, stackTrace);
      // 修改：不再因为更新节点内容失败而发出错误状态，避免影响用户体验
      AppLogger.info(_tag, '节点内容更新失败，但不影响UI状态');
    }
  }

  /// 手动添加子节点
  void _onAddChildNode(
    AddChildNodeEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    AppLogger.i(_tag, '🔧 开始添加子节点: 父节点=${event.parentNodeId}, 标题=${event.title}');

    try {
      // 1. 检查当前状态是否支持添加子节点
      if (state is! SettingGenerationCompleted && state is! SettingGenerationInProgress) {
        AppLogger.w(_tag, '❌ 当前状态不支持添加子节点: ${state.runtimeType}');
        return;
      }

      // 2. 获取当前活跃会话
      SettingGenerationSession? activeSession;
      if (state is SettingGenerationCompleted) {
        activeSession = (state as SettingGenerationCompleted).activeSession;
      } else if (state is SettingGenerationInProgress) {
        activeSession = (state as SettingGenerationInProgress).activeSession;
      }

      if (activeSession == null) {
        AppLogger.w(_tag, '❌ 没有活跃会话，无法添加子节点');
        return;
      }

      // 3. 查找父节点
      final parentNode = SettingNodeUtils.findNodeInTree(activeSession.rootNodes, event.parentNodeId);
      if (parentNode == null) {
        AppLogger.w(_tag, '❌ 找不到父节点: ${event.parentNodeId}');
        return;
      }

      // 4. 创建新的子节点
      final childNode = SettingNode(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // 临时ID
        parentId: event.parentNodeId,
        name: event.title,
        type: SettingType.fromValue(event.type),
        description: event.content,
        generationStatus: GenerationStatus.completed,
      );

      // 5. 更新父节点，添加子节点
      final updatedRootNodes = _addChildNodeToTree(activeSession.rootNodes, event.parentNodeId, childNode);

      // 6. 更新会话
      final updatedSession = activeSession.copyWith(rootNodes: updatedRootNodes);

      // 7. 更新状态
      if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        emit(currentState.copyWith(
          activeSession: updatedSession,
          renderedNodeIds: {...currentState.renderedNodeIds, childNode.id},
        ));
      } else if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        emit(currentState.copyWith(
          activeSession: updatedSession,
          renderedNodeIds: {...currentState.renderedNodeIds, childNode.id},
        ));
      }

      AppLogger.i(_tag, '✅ 成功添加子节点: ${event.title}');

    } catch (e, stackTrace) {
      AppLogger.e(_tag, '❌ 添加子节点失败: $e', stackTrace);
    }
  }

  /// 在节点树中添加子节点
  List<SettingNode> _addChildNodeToTree(List<SettingNode> rootNodes, String parentId, SettingNode childNode) {
    return rootNodes.map((node) {
      if (node.id == parentId) {
        // 找到父节点，添加子节点
        final existingChildren = node.children ?? [];
        return node.copyWith(
          children: [...existingChildren, childNode],
        );
      } else if (node.children != null && node.children!.isNotEmpty) {
        // 递归搜索子节点
        final updatedChildren = _addChildNodeToTree(node.children!, parentId, childNode);
        return node.copyWith(children: updatedChildren);
      }
      return node;
    }).toList();
  }

  /// 删除节点及其所有子节点
  void _onDeleteNode(
    DeleteNodeEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    AppLogger.i(_tag, '🗑️ 开始删除节点: ${event.nodeId}');

    try {
      // 1. 检查当前状态是否支持删除节点
      if (state is! SettingGenerationCompleted && state is! SettingGenerationInProgress) {
        AppLogger.w(_tag, '❌ 当前状态不支持删除节点: ${state.runtimeType}');
        return;
      }

      // 2. 获取当前活跃会话
      SettingGenerationSession? activeSession;
      String? sessionId;
      if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        activeSession = currentState.activeSession;
        sessionId = currentState.activeSessionId;
      } else if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        activeSession = currentState.activeSession;
        sessionId = currentState.activeSessionId;
      }

      if (activeSession == null || sessionId == null) {
        AppLogger.w(_tag, '❌ 没有活跃会话，无法删除节点');
        return;
      }

      // 3. 查找要删除的节点
      final nodeToDelete = SettingNodeUtils.findNodeInTree(activeSession.rootNodes, event.nodeId);
      if (nodeToDelete == null) {
        AppLogger.w(_tag, '❌ 找不到要删除的节点: ${event.nodeId}');
        return;
      }

      // 4. 先调用后端API删除节点
      AppLogger.i(_tag, '🚀 调用后端API删除节点: ${event.nodeId}');
      final deleteResult = await _repository.deleteNode(
        sessionId: sessionId,
        nodeId: event.nodeId,
      );

      final deletedNodeIds = (deleteResult['deletedNodeIds'] as List<dynamic>?)
          ?.map((id) => id.toString())
          .toList() ?? [];

      AppLogger.i(_tag, '✅ 后端删除成功，共删除 ${deletedNodeIds.length} 个节点');

      // 5. 从本地节点树中删除节点
      final updatedRootNodes = _removeNodeFromTree(activeSession.rootNodes, event.nodeId);

      // 6. 更新会话
      final updatedSession = activeSession.copyWith(rootNodes: updatedRootNodes);

      // 7. 更新渲染状态，移除已删除节点的渲染信息
      final Set<String> updatedRenderedNodeIds;
      final Map<String, NodeRenderInfo> updatedNodeRenderStates;

      if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        updatedRenderedNodeIds = currentState.renderedNodeIds.where((id) => !deletedNodeIds.contains(id)).toSet();
        updatedNodeRenderStates = Map.from(currentState.nodeRenderStates)
          ..removeWhere((key, value) => deletedNodeIds.contains(key));
      } else {
        final currentState = state as SettingGenerationInProgress;
        updatedRenderedNodeIds = currentState.renderedNodeIds.where((id) => !deletedNodeIds.contains(id)).toSet();
        updatedNodeRenderStates = Map.from(currentState.nodeRenderStates)
          ..removeWhere((key, value) => deletedNodeIds.contains(key));
      }

      // 8. 更新状态
      if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        emit(currentState.copyWith(
          activeSession: updatedSession,
          renderedNodeIds: updatedRenderedNodeIds,
          nodeRenderStates: updatedNodeRenderStates,
          selectedNodeId: currentState.selectedNodeId == event.nodeId ? null : currentState.selectedNodeId,
          message: '已删除节点及其 ${deletedNodeIds.length - 1} 个子节点',
        ));
      } else if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        emit(currentState.copyWith(
          activeSession: updatedSession,
          renderedNodeIds: updatedRenderedNodeIds,
          nodeRenderStates: updatedNodeRenderStates,
          selectedNodeId: currentState.selectedNodeId == event.nodeId ? null : currentState.selectedNodeId,
          stickyWarning: '已删除节点及其 ${deletedNodeIds.length - 1} 个子节点',
        ));
      }

      AppLogger.i(_tag, '✅ 成功删除节点: ${event.nodeId}');

    } catch (e, stackTrace) {
      AppLogger.e(_tag, '❌ 删除节点失败: $e', stackTrace);
      emit(SettingGenerationError(
        message: '删除节点失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// 从节点树中删除指定节点
  List<SettingNode> _removeNodeFromTree(List<SettingNode> rootNodes, String nodeId) {
    final result = <SettingNode>[];
    for (final node in rootNodes) {
      // 如果是要删除的节点，跳过
      if (node.id == nodeId) {
        continue;
      }
      // 如果有子节点，递归删除
      if (node.children != null && node.children!.isNotEmpty) {
        final updatedChildren = _removeNodeFromTree(node.children!, nodeId);
        result.add(node.copyWith(children: updatedChildren));
      } else {
        result.add(node);
      }
    }
    return result;
  }

  Timer? _pendingNodesTimer;

  void _debounceProcessPendingNodes() {
    _pendingNodesTimer?.cancel();
    // 🔧 减少延迟时间，更快处理节点
    _pendingNodesTimer = Timer(const Duration(milliseconds: 50), () {
      if (!isClosed) {
        add(const _ProcessPendingNodes());
      }
    });
  }

  /// 🚀 新增：智能拓扑排序，立即处理可渲染的节点
  void _processNodesImmediately(
    List<event_model.NodeCreatedEvent> newNodes,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    final existingNodes = currentState.activeSession.rootNodes;
    
    // 找出可以立即渲染的节点（没有父节点或父节点已存在）
    final immediatelyRenderableNodes = <event_model.NodeCreatedEvent>[];
    final needsWaitingNodes = <event_model.NodeCreatedEvent>[];
    
    for (final nodeEvent in newNodes) {
      final node = nodeEvent.node;
      final parentId = node.parentId;
      
      if (parentId == null) {
        // 根节点，可以立即渲染
        AppLogger.i(_tag, '⚡ 立即处理根节点: ${node.name}');
        immediatelyRenderableNodes.add(nodeEvent);
      } else {
        // 检查父节点是否已存在
        final parentExists = SettingNodeUtils.findNodeInTree(existingNodes, parentId) != null;
        if (parentExists) {
          AppLogger.i(_tag, '⚡ 父节点已存在，立即处理: ${node.name}');
          immediatelyRenderableNodes.add(nodeEvent);
        } else {
          AppLogger.i(_tag, '⏳ 父节点不存在，暂存等待: ${node.name}');
          needsWaitingNodes.add(nodeEvent);
        }
      }
    }
    
    // 立即处理可渲染的节点
    if (immediatelyRenderableNodes.isNotEmpty) {
      _insertNodesAndTriggerRender(immediatelyRenderableNodes, emit);
    }
    
    // 将需要等待的节点加入暂存队列
    if (needsWaitingNodes.isNotEmpty) {
      final updatedPendingNodes = List<event_model.NodeCreatedEvent>.from(currentState.pendingNodes)
        ..addAll(needsWaitingNodes);
      
      emit(currentState.copyWith(pendingNodes: updatedPendingNodes));
      
      // 对暂存节点使用短延迟处理
      _debounceProcessPendingNodes();
    }
  }

  /// 插入节点并触发渲染
  void _insertNodesAndTriggerRender(
    List<event_model.NodeCreatedEvent> nodeEvents,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    var currentNodes = currentState.activeSession.rootNodes;
    var updatedRenderQueue = List<String>.from(currentState.renderQueue);
    var updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
    
    // 使用改进的拓扑排序
    final sortedEvents = _improvedTopologicalSort(nodeEvents, currentNodes);
    
    AppLogger.i(_tag, '🎯 立即插入 ${sortedEvents.length} 个节点');
    
    // 批量插入节点
    for (final nodeEvent in sortedEvents) {
      currentNodes = _insertNodeIntoTree(
        currentNodes,
        nodeEvent.node,
        nodeEvent.parentPath,
      );
      
      updatedRenderQueue.add(nodeEvent.node.id);
      updatedNodeRenderStates[nodeEvent.node.id] = NodeRenderInfo(
        nodeId: nodeEvent.node.id,
        state: NodeRenderState.pending,
      );
    }
    
    final updatedSession = currentState.activeSession.copyWith(rootNodes: currentNodes);
    final updatedSessions = currentState.sessions.map((session) {
      return session.sessionId == currentState.activeSessionId ? updatedSession : session;
    }).toList();
    
    emit(currentState.copyWith(
      sessions: updatedSessions,
      activeSession: updatedSession,
      renderQueue: updatedRenderQueue,
      nodeRenderStates: updatedNodeRenderStates,
      // 统一文案，避免与后续显示重复
      currentOperation: '已处理 ${sortedEvents.length} 个新节点',
    ));
    
    // 立即触发渲染队列处理
    add(const ProcessRenderQueueEvent());
  }

  /// 在设定节点树中更新指定节点的内容
  List<SettingNode> _updateNodeContentInTree(
    List<SettingNode> nodes,
    String nodeId,
    String newContent,
  ) {
    return nodes.map((node) {
      if (node.id == nodeId) {
        return node.copyWith(description: newContent);
      } else if (node.children != null && node.children!.isNotEmpty) {
        return node.copyWith(
          children: _updateNodeContentInTree(node.children!, nodeId, newContent),
        );
      } else {
        return node;
      }
    }).toList();
  }

  /// 选择节点
  void _onSelectNode(
    SelectNodeEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(selectedNodeId: event.nodeId));
    } else if (state is SettingGenerationCompleted) {
      final currentState = state as SettingGenerationCompleted;
      emit(currentState.copyWith(selectedNodeId: event.nodeId));
    }
  }

  /// 切换视图模式
  void _onToggleViewMode(
    ToggleViewModeEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is SettingGenerationReady) {
      final currentState = state as SettingGenerationReady;
      emit(currentState.copyWith(viewMode: event.viewMode));
    } else if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(viewMode: event.viewMode));
    } else if (state is SettingGenerationCompleted) {
      final currentState = state as SettingGenerationCompleted;
      emit(currentState.copyWith(viewMode: event.viewMode));
    }
  }

  /// 应用待处理的更改
  void _onApplyPendingChanges(
    ApplyPendingChangesEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    if (currentState.pendingChanges.isEmpty) return;

    // 更新会话中的节点数据
    final updatedNodes = _applyChangesToNodes(
      currentState.activeSession.rootNodes,
      currentState.pendingChanges,
    );

    // 更新编辑历史
    final newHistory = Map<String, List<SettingNode>>.from(currentState.editHistory);
    for (final entry in currentState.pendingChanges.entries) {
      final nodeId = entry.key;
      final originalNode = SettingNodeUtils.findNodeInTree(currentState.activeSession.rootNodes, nodeId);
      if (originalNode != null) {
        newHistory[nodeId] = [...(newHistory[nodeId] ?? []), originalNode];
      }
    }

    final updatedSession = currentState.activeSession.copyWith(
      rootNodes: updatedNodes,
    );

    final updatedSessions = currentState.sessions.map((session) {
      return session.sessionId == currentState.activeSessionId ? updatedSession : session;
    }).toList();

    emit(currentState.copyWith(
      sessions: updatedSessions,
      activeSession: updatedSession,
      pendingChanges: {},
      highlightedNodeIds: {},
      editHistory: newHistory,
    ));
  }

  /// 取消待处理的更改
  void _onCancelPendingChanges(
    CancelPendingChangesEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(
        pendingChanges: {},
        highlightedNodeIds: {},
      ));
    }
  }

  /// 撤销节点更改
  void _onUndoNodeChange(
    UndoNodeChangeEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    final nodeHistory = currentState.editHistory[event.nodeId];
    if (nodeHistory == null || nodeHistory.isEmpty) return;

    final previousState = nodeHistory.last;
    final updatedNodes = _updateNodeInTree(
      currentState.activeSession.rootNodes,
      event.nodeId,
      previousState,
    );

    final newHistory = Map<String, List<SettingNode>>.from(currentState.editHistory);
    newHistory[event.nodeId] = nodeHistory.sublist(0, nodeHistory.length - 1);

    final updatedSession = currentState.activeSession.copyWith(
      rootNodes: updatedNodes,
    );

    final updatedSessions = currentState.sessions.map((session) {
      return session.sessionId == currentState.activeSessionId ? updatedSession : session;
    }).toList();

    emit(currentState.copyWith(
      sessions: updatedSessions,
      activeSession: updatedSession,
      editHistory: newHistory,
    ));
  }

  /// 保存生成的设定
  Future<void> _onSaveGeneratedSettings(
    SaveGeneratedSettingsEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    if (state is! SettingGenerationInProgress && state is! SettingGenerationCompleted) {
      emit(const SettingGenerationError(message: '没有可保存的设定'));
      return;
    }

    try {
      // 取消生成流，防止 SSE 连接在错误时无限重试
      _generationStreamSubscription?.cancel();
      
      String sessionId;
      if (state is SettingGenerationInProgress) {
        sessionId = (state as SettingGenerationInProgress).activeSessionId;
      } else {
        sessionId = (state as SettingGenerationCompleted).activeSessionId;
      }

      // 调用新的统一保存方法，返回SaveResult
      final saveResult = await _repository.saveGeneratedSettings(
        sessionId: sessionId,
        novelId: event.novelId,
        updateExisting: event.updateExisting,
        targetHistoryId: event.targetHistoryId,
      );

      // 从SaveResult中获取historyId
      final String? historyId = saveResult.historyId;
      final String successMessage = _getSuccessMessage(event.novelId, event.updateExisting);

      // 更新会话状态；仅当创建独立快照（非更新现有历史）时插入并切换到新快照
      final bool isStandaloneSnapshot = event.novelId == null && !event.updateExisting;
      _updateSessionAfterSave(
        emit,
        historyId,
        successMessage,
        switchToNewHistory: isStandaloneSnapshot,
      );
      
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '保存设定失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '保存设定失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        isRecoverable: true,
      ));
        }
  }

  /// 处理生成超时
  Future<void> _handleGenerationTimeout(Emitter<SettingGenerationState> emit) async {
    try {
      // 取消 SSE 连接
      _generationStreamSubscription?.cancel();
      _generationStreamSubscription = null;
      
      // 如果有活跃会话，尝试取消后端任务
      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        try {
          await _repository.cancelSession(sessionId: currentState.activeSessionId);
          AppLogger.i(_tag, '✅ 成功取消后端生成任务: ${currentState.activeSessionId}');
        } catch (e) {
          AppLogger.w(_tag, '⚠️ 取消后端任务失败，但继续处理超时: $e');
        }
      }
      
      // 改为软提示：不切换到错误页，保持 InProgress 状态，提示并停止生成
      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        emit(currentState.copyWith(
          isGenerating: false,
          currentOperation: '生成任务超时（5分钟），已自动取消。',
        ));
      } else {
        // 其他状态下，尽量不打断，仅作为可恢复错误
        emit(SettingGenerationError(
          message: '生成任务超时（5分钟），已自动取消。请稍后重试。',
          error: TimeoutException('生成任务超时', const Duration(minutes: 5)),
          stackTrace: StackTrace.current,
          isRecoverable: true,
          sessions: _getCurrentSessions(),
        ));
      }
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '处理超时时发生错误', e, stackTrace);
      emit(SettingGenerationError(
        message: '生成任务超时并处理失败，请重试。',
        error: e,
        stackTrace: stackTrace,
        isRecoverable: true,
        sessions: _getCurrentSessions(),
      ));
    }
  }

  /// 基于最后活动时间的超时检查（由定时器派发，不在回调中直接 emit）
  Future<void> _onTimeoutCheckInternal(
    _TimeoutCheckInternal event,
    Emitter<SettingGenerationState> emit,
  ) async {
    if (!(state is SettingGenerationInProgress || state is SettingGenerationNodeUpdating)) {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime last = _lastActivityAt ?? now;
    final bool isTimedOut = now.difference(last) >= _timeoutDuration;

    if (isTimedOut) {
      AppLogger.w(_tag, '⏰ 生成业务超时（基于最后活动时间 ${_timeoutDuration.inSeconds}s）');
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      if (emit.isDone) {
        AppLogger.w(_tag, 'emit已完成，跳过超时处理');
        return;
      }
      await _handleGenerationTimeout(emit);
    } else {
      // 未超时则继续观察
      _resetInactivityTimeout();
    }
  }

  /// 获取当前会话列表的辅助方法
  List<SettingGenerationSession> _getCurrentSessions() {
    if (state is SettingGenerationInProgress) {
      return (state as SettingGenerationInProgress).sessions;
    } else if (state is SettingGenerationCompleted) {
      return (state as SettingGenerationCompleted).sessions;
    } else if (state is SettingGenerationError) {
      return (state as SettingGenerationError).sessions;
    }
    return [];
  }
  
  /// 🔧 新增：获取当前composeReady状态的辅助方法
  ComposeReadyInfo? _getCurrentComposeReady() {
    if (state is SettingGenerationReady) {
      return (state as SettingGenerationReady).composeReady;
    } else if (state is SettingGenerationInProgress) {
      return (state as SettingGenerationInProgress).composeReady;
    } else if (state is SettingGenerationCompleted) {
      return (state as SettingGenerationCompleted).composeReady;
    } else if (state is SettingGenerationNodeUpdating) {
      return (state as SettingGenerationNodeUpdating).composeReady;
    } else if (state is SettingGenerationError) {
      return (state as SettingGenerationError).composeReady;
    }
    return null;
  }
  
  /// 获取保存成功消息
  String _getSuccessMessage(String? novelId, bool updateExisting) {
    if (updateExisting) {
      return '历史记录已成功更新';
    }
    if (novelId == null) {
      return '设定已成功保存为独立快照';
    }
    return '设定已成功保存到小说中';
  }

  /// 保存后更新会话状态
  void _updateSessionAfterSave(
    Emitter<SettingGenerationState> emit,
    String? historyId,
    String message, {
    bool switchToNewHistory = false,
  }) {
    if (state is SettingGenerationInProgress) {
      final s = state as SettingGenerationInProgress;
      final updatedActive = s.activeSession.copyWith(
        status: SessionStatus.saved,
        // ✅ 不再覆盖 sessionId，保持真实会话ID
        historyId: historyId,
      );
      List<SettingGenerationSession> updatedSessions = s.sessions.map((sess) {
        return sess.sessionId == s.activeSessionId ? updatedActive : sess;
      }).toList();

      // 独立快照：在历史列表中插入新快照并高亮切换
      if (switchToNewHistory && historyId != null && historyId.isNotEmpty) {
        final placeholder = SettingGenerationSession(
          sessionId: historyId,
          userId: updatedActive.userId,
          novelId: null,
          initialPrompt: updatedActive.initialPrompt,
          strategy: updatedActive.strategy,
          modelConfigId: updatedActive.modelConfigId,
          status: SessionStatus.saved,
          rootNodes: const [],
          allNodes: const {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          errorMessage: null,
          metadata: updatedActive.metadata,
          historyId: historyId,
        );
        updatedSessions = [placeholder, ...updatedSessions];

        emit(SettingGenerationCompleted(
          strategies: s.strategies,
          sessions: updatedSessions,
          activeSessionId: placeholder.sessionId,
          activeSession: placeholder,
          selectedNodeId: s.selectedNodeId,
          viewMode: s.viewMode,
          adjustmentPrompt: s.adjustmentPrompt,
          pendingChanges: s.pendingChanges,
          highlightedNodeIds: s.highlightedNodeIds,
          editHistory: s.editHistory,
          events: s.events,
          message: message,
          nodeRenderStates: s.nodeRenderStates,
          renderedNodeIds: s.renderedNodeIds,
        ));

        // 异步加载新快照的完整数据
        add(CreateSessionFromHistoryEvent(
          historyId: historyId,
          userId: updatedActive.userId,
          editReason: '保存后查看历史',
          modelConfigId: updatedActive.modelConfigId ?? 'default',
        ));
      } else {
        emit(SettingGenerationCompleted(
          strategies: s.strategies,
          sessions: updatedSessions,
          activeSessionId: updatedActive.sessionId,
          activeSession: updatedActive,
          selectedNodeId: s.selectedNodeId,
          viewMode: s.viewMode,
          adjustmentPrompt: s.adjustmentPrompt,
          pendingChanges: s.pendingChanges,
          highlightedNodeIds: s.highlightedNodeIds,
          editHistory: s.editHistory,
          events: s.events,
          message: message,
          nodeRenderStates: s.nodeRenderStates,
          renderedNodeIds: s.renderedNodeIds,
        ));
      }
    } else if (state is SettingGenerationCompleted) {
      final s = state as SettingGenerationCompleted;
      final updatedActive = s.activeSession.copyWith(
        status: SessionStatus.saved,
        // ✅ 不再覆盖 sessionId，保持真实会话ID
        historyId: historyId,
      );
      List<SettingGenerationSession> updatedSessions = s.sessions.map((sess) {
        return sess.sessionId == s.activeSessionId ? updatedActive : sess;
      }).toList();

      if (switchToNewHistory && historyId != null && historyId.isNotEmpty) {
        final placeholder = SettingGenerationSession(
          sessionId: historyId,
          userId: updatedActive.userId,
          novelId: null,
          initialPrompt: updatedActive.initialPrompt,
          strategy: updatedActive.strategy,
          modelConfigId: updatedActive.modelConfigId,
          status: SessionStatus.saved,
          rootNodes: const [],
          allNodes: const {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          errorMessage: null,
          metadata: updatedActive.metadata,
          historyId: historyId,
        );
        updatedSessions = [placeholder, ...updatedSessions];

        emit(s.copyWith(
          sessions: updatedSessions,
          activeSession: placeholder,
          activeSessionId: placeholder.sessionId,
          message: message,
        ));

        add(CreateSessionFromHistoryEvent(
          historyId: historyId,
          userId: updatedActive.userId,
          editReason: '保存后查看历史',
          modelConfigId: updatedActive.modelConfigId ?? 'default',
        ));
      } else {
        emit(s.copyWith(
          sessions: updatedSessions,
          activeSession: updatedActive,
          activeSessionId: updatedActive.sessionId,
          message: message,
        ));
      }
    }
  }

  /// 创建新会话（在 Ready / Error 状态下均可触发）
  Future<void> _onCreateNewSession(
    CreateNewSessionEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    // 1. Ready 状态：直接创建占位会话并设为激活
    if (state is SettingGenerationReady) {
      final currentState = state as SettingGenerationReady;

      final placeholderSession = SettingGenerationSession(
        sessionId: 'new_${DateTime.now().millisecondsSinceEpoch}',
        userId: AppConfig.userId ?? 'current_user',
        novelId: null,
        initialPrompt: '',
        strategy: '九线法',
        status: SessionStatus.initializing,
        createdAt: DateTime.now(),
        rootNodes: const [],
      );

      emit(currentState.copyWith(
        sessions: [placeholderSession, ...currentState.sessions],
        activeSessionId: placeholderSession.sessionId,
        adjustmentPrompt: '',
      ));
      return;
    }

    // 2. Error 状态：尝试快速恢复到 Ready 状态，保留历史记录
    if (state is SettingGenerationError) {
      final errorState = state as SettingGenerationError;

      // 显示轻量级的加载提示，避免整页闪烁
      emit(const SettingGenerationLoading(message: '正在重新初始化...'));

      // 尝试重新获取策略；若失败则使用默认策略占位
      List<StrategyTemplateInfo> strategies = [];
      try {
        strategies = await _repository.getAvailableStrategies();
        if (strategies.isEmpty) {
          throw Exception('策略列表为空');
        }
      } catch (e) {
        // 策略加载失败时直接抛出异常
        AppLogger.error(_tag, '加载策略失败', e);
        throw Exception('无法加载策略模板');
      }

      // 切换到 Ready 状态，清空当前激活会话但保留历史列表
      emit(SettingGenerationReady(
        strategies: strategies,
        sessions: errorState.sessions,
        activeSessionId: null,
      ));
    }
  }

  /// 选择会话
  void _onSelectSession(
    SelectSessionEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    AppLogger.i(_tag, '选择会话: ' + event.sessionId + ', isHistory: ' + event.isHistorySession.toString());
    
    if (state is SettingGenerationReady) {
      final currentState = state as SettingGenerationReady;
      final sessions = currentState.sessions;
      if (sessions.isEmpty) {
        emit(currentState.copyWith(
          activeSessionId: null,
          viewMode: 'compact',
          adjustmentPrompt: '',
        ));
        return;
      }
      final session = sessions.firstWhere(
        (s) => s.sessionId == event.sessionId,
        orElse: () => sessions.first,
      );
      // 切换会话时清空 novelId
      final cleared = session.copyWith(novelId: '');
      emit(currentState.copyWith(
        activeSessionId: cleared.sessionId,
        viewMode: 'compact',
        adjustmentPrompt: '',
      ));
      
      // 如果选择的是历史会话，需要切换到对应的状态
      if (event.isHistorySession && session.status == SessionStatus.saved) {
        // 🔧 新增：为历史会话设置默认的composeReady状态
        final defaultComposeReady = ComposeReadyInfo(
          ready: true,
          reason: '历史会话已选择，可以开始创作',
          novelId: cleared.novelId ?? '',
          sessionId: cleared.sessionId,
        );
        
        emit(SettingGenerationCompleted(
          strategies: currentState.strategies,
          sessions: currentState.sessions,
          activeSessionId: cleared.sessionId,
          activeSession: cleared,
          message: '已切换到历史会话',
          // 🔧 关键修复：确保所有节点都可见
          renderedNodeIds: _collectAllNodeIds(cleared.rootNodes).toSet(),
          // 🔧 新增：设置默认的composeReady状态
          composeReady: defaultComposeReady,
        ));
      }
      return;
    }

    if (state is SettingGenerationInProgress) {
      final s = state as SettingGenerationInProgress;
      final session = s.sessions.firstWhere((ss) => ss.sessionId == event.sessionId,
          orElse: () => s.sessions.isNotEmpty ? s.sessions.first : s.activeSession);
      final cleared = session.copyWith(novelId: '');
      emit(s.copyWith(
        activeSessionId: cleared.sessionId,
        activeSession: cleared,
        renderedNodeIds: _collectAllNodeIds(cleared.rootNodes).toSet(),
        selectedNodeId: null,
        viewMode: 'compact',
        adjustmentPrompt: '',
      ));
      // 如果被选中的会话已经生成完成或已保存，则直接切换到 Completed 状态，避免动画
      if (session.status == SessionStatus.completed || session.status == SessionStatus.saved) {
        // 🔧 新增：为完成/保存的会话设置默认的composeReady状态
        final defaultComposeReady = ComposeReadyInfo(
          ready: true,
          reason: '会话已完成，可以开始创作',
          novelId: cleared.novelId ?? '',
          sessionId: cleared.sessionId,
        );
        
        emit(SettingGenerationCompleted(
          strategies: s.strategies,
          sessions: s.sessions,
          activeSessionId: cleared.sessionId,
          activeSession: cleared,
          message: '已切换到完成会话',
          // 🔧 关键修复：确保所有节点都可见
          renderedNodeIds: _collectAllNodeIds(cleared.rootNodes).toSet(),
          // 🔧 新增：设置默认的composeReady状态
          composeReady: defaultComposeReady,
        ));
      }
      return;
    }

    if (state is SettingGenerationCompleted) {
      final s = state as SettingGenerationCompleted;
      final session = s.sessions.firstWhere((ss) => ss.sessionId == event.sessionId,
          orElse: () => s.sessions.isNotEmpty ? s.sessions.first : s.activeSession);
      final cleared = session.copyWith(novelId: '');
      
      // 🔧 新增：确保composeReady状态正确传递
      ComposeReadyInfo? composeReady = s.composeReady;
      if (composeReady == null) {
        // 如果当前状态没有composeReady，为会话创建默认状态
        composeReady = ComposeReadyInfo(
          ready: true,
          reason: '会话已切换，可以开始创作',
          novelId: cleared.novelId ?? '',
          sessionId: cleared.sessionId,
        );
      }
      
      emit(s.copyWith(
        activeSessionId: cleared.sessionId,
        activeSession: cleared,
        selectedNodeId: null,
        viewMode: 'compact',
        adjustmentPrompt: '',
        // 🔧 关键修复：确保所有节点都可见
        renderedNodeIds: _collectAllNodeIds(cleared.rootNodes).toSet(),
        // 🔧 新增：保持或设置composeReady状态
        composeReady: composeReady,
      ));
      return;
    }

    if (state is SettingGenerationError) {
      _handleSelectSessionFromError(event, emit);
    }
  }

  /// 🔧 新增：处理从错误状态选择会话的逻辑
  Future<void> _handleSelectSessionFromError(
    SelectSessionEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      final currentState = state as SettingGenerationError;
      
      AppLogger.i(_tag, '🔄 从错误状态选择会话，尝试恢复: ${event.sessionId}');
      
      // 查找对应的会话
      final session = currentState.sessions.firstWhere(
        (s) => s.sessionId == event.sessionId,
        orElse: () => throw Exception('会话未找到: ${event.sessionId}'),
      );
      
      // 先显示加载状态
      emit(const SettingGenerationLoading(message: '正在加载历史记录...'));
      
      // 🔧 关键修复：尝试重新加载策略数据，确保UI有完整的数据支持
      List<StrategyTemplateInfo> strategies = [];
      try {
        strategies = await _repository.getAvailableStrategies();
        AppLogger.i(_tag, '✅ 成功重新加载策略数据: ${strategies.length}个策略');
      } catch (e) {
        AppLogger.w(_tag, '重新加载策略失败', e);
        strategies = [];
      }
      
      // 🔧 修复：确保所有必要的状态字段都被正确初始化
      // 🔧 新增：为从错误状态恢复的会话设置默认的composeReady状态
      final defaultComposeReady = ComposeReadyInfo(
        ready: true,
        reason: '会话已恢复，可以开始创作',
        novelId: session.novelId ?? '',
        sessionId: session.sessionId,
      );
      
      emit(SettingGenerationCompleted(
        strategies: strategies, // 使用重新加载的策略数据而不是空数组
        sessions: currentState.sessions,
        activeSessionId: event.sessionId,
        activeSession: session,
        message: '已加载历史设定',
        // 🔧 关键修复：历史记录已完成，所有节点应该显示
        nodeRenderStates: const {},
        renderedNodeIds: _collectAllNodeIds(session.rootNodes).toSet(),
        selectedNodeId: null,
        viewMode: 'compact',
        adjustmentPrompt: '',
        pendingChanges: const {},
        highlightedNodeIds: const {},
        editHistory: const {},
        events: const [],
        // 🔧 新增：设置默认的composeReady状态
        composeReady: defaultComposeReady,
      ));
      
      AppLogger.i(_tag, '✅ 成功从错误状态恢复并加载历史记录: ${session.sessionId}');
      
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '❌ 从错误状态选择会话失败', e, stackTrace);
      
      // 如果恢复失败，保持在错误状态，但更新错误信息
      emit(SettingGenerationError(
        message: '加载历史记录失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        isRecoverable: true,
        sessions: (state as SettingGenerationError).sessions,
        // 🔧 新增：保留当前composeReady状态
        composeReady: _getCurrentComposeReady(),
        activeSessionId: event.sessionId,
      ));
    }
  }

  /// 加载历史设定详情
  Future<void> _onLoadHistoryDetail(
    CreateSessionFromHistoryEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    // 👉 在加载新的历史记录之前，确保取消任何仍在进行的流式生成或节点更新连接，
    //    以防止 EventSource 在后台继续自动重连，导致不断重试 /setting-generation/start
    _generationStreamSubscription?.cancel();
    _generationStreamSubscription = null;
    _updateStreamSubscription?.cancel();
    _updateStreamSubscription = null;

    try {
      AppLogger.i(_tag, '加载历史设定详情: historyId=${event.historyId}');
      
      // 解析当前状态用于保留策略和会话列表
      final currentState = state;
      List<StrategyTemplateInfo> strategies = [];
      List<SettingGenerationSession> sessions = [];
      
      if (currentState is SettingGenerationReady) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationInProgress) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationCompleted) {
        strategies = currentState.strategies;
        sessions = currentState.sessions;
      } else if (currentState is SettingGenerationError) {
        sessions = currentState.sessions;
        // 从错误状态加载历史时，重新加载策略数据
        try {
          strategies = await _repository.getAvailableStrategies();
          AppLogger.i(_tag, '重新加载策略数据: ${strategies.length}个策略');
        } catch (e) {
          AppLogger.w(_tag, '加载策略失败', e);
          strategies = [];
        }
      }

      // 加载历史记录详情
      final historyDetail = await _repository.loadHistoryDetail(historyId: event.historyId);
      
      // 后端返回格式: { history: {...}, rootNodes: [...] }
      final historyJson = historyDetail['history'] as Map<String, dynamic>;
      final rootNodesJson = historyDetail['rootNodes'] as List;
      
      // 组合成一个完整的session对象
      historyJson['rootNodes'] = rootNodesJson;
      historyJson['sessionId'] = event.historyId;
      
      // 处理 modelConfigId 为 null 的情况
      if (historyJson['modelConfigId'] == null) {
        historyJson['modelConfigId'] = event.modelConfigId;
      }
      
      final session0 = SettingGenerationSession.fromJson(historyJson);
      // 切换/加载历史后，前端会话不应继承任何 novelId
      final session = session0.copyWith(novelId: '');
      AppLogger.i(_tag, '会话对象创建完成 - 节点数: ${session.rootNodes.length}');

      // 更新或添加到会话列表（保持原有位置，不将选中的历史记录移到第一位）
      List<SettingGenerationSession> updatedSessions;
      final existingIndex = sessions.indexWhere((s) => s.sessionId == session.sessionId);
      if (existingIndex >= 0) {
        updatedSessions = List.of(sessions);
        updatedSessions[existingIndex] = session;
      } else {
        updatedSessions = List.of(sessions)..add(session);
      }

      // 🔧 修复：确保所有字段都被正确初始化
      // 🔧 新增：为历史记录设置默认的composeReady状态，允许开始创作
      final defaultComposeReady = ComposeReadyInfo(
        ready: true,
        reason: '历史记录已加载，可以开始创作',
        novelId: session.novelId ?? '',
        sessionId: session.sessionId,
      );
      
      // 根据编辑原因决定emit的状态类型
      if (event.editReason.contains('修改') || event.editReason.contains('编辑')) {
        // 编辑模式：emit SettingGenerationInProgress状态，支持节点修改
        emit(SettingGenerationInProgress(
          strategies: strategies,
          sessions: updatedSessions,
          activeSessionId: session.sessionId,
          activeSession: session,
          currentOperation: '已进入编辑模式',
          isGenerating: false,
          // 渲染相关字段
          nodeRenderStates: const {},
          renderedNodeIds: const {},
          selectedNodeId: null,
          viewMode: 'compact',
          adjustmentPrompt: '',
          pendingChanges: const {},
          highlightedNodeIds: const {},
          editHistory: const {},
          events: const [],
          renderQueue: const [],
          // 🔧 新增：设置默认的composeReady状态
          composeReady: defaultComposeReady,
        ));
        AppLogger.i(_tag, '✅ 进入编辑模式: ${session.sessionId}, 节点数: ${session.rootNodes.length}');
      } else {
        // 查看模式：emit SettingGenerationCompleted状态
        emit(SettingGenerationCompleted(
          strategies: strategies,
          sessions: updatedSessions,
          activeSessionId: session.sessionId,
          activeSession: session,
          message: '已加载历史设定',
          // 🔧 关键修复：历史记录查看模式，所有节点应该显示
          nodeRenderStates: const {},
          renderedNodeIds: _collectAllNodeIds(session.rootNodes).toSet(),
          selectedNodeId: null,
          viewMode: 'compact',
          adjustmentPrompt: '',
          pendingChanges: const {},
          highlightedNodeIds: const {},
          editHistory: const {},
          events: const [],
          // 🔧 新增：设置默认的composeReady状态
          composeReady: defaultComposeReady,
        ));
        AppLogger.i(_tag, '✅ 查看模式: ${session.sessionId}, 节点数: ${session.rootNodes.length}');
      }
      
      AppLogger.i(_tag, '成功加载历史设定: ${session.sessionId}, 节点数: ${session.rootNodes.length}');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '加载历史设定失败', e, stackTrace);
      
      // 保留会话列表，避免错误时丢失历史记录
      List<SettingGenerationSession> sessions = [];
      if (state is SettingGenerationReady) {
        sessions = (state as SettingGenerationReady).sessions;
      } else if (state is SettingGenerationInProgress) {
        sessions = (state as SettingGenerationInProgress).sessions;
      } else if (state is SettingGenerationCompleted) {
        sessions = (state as SettingGenerationCompleted).sessions;
      } else if (state is SettingGenerationError) {
        sessions = (state as SettingGenerationError).sessions;
      }
      
      emit(SettingGenerationError(
        message: '加载历史设定失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        sessions: sessions,
        // 🔧 新增：保留当前状态的composeReady
        composeReady: _getCurrentComposeReady(),
      ));
    }
  }

  /// 获取会话状态
  Future<void> _onGetSessionStatus(
    GetSessionStatusEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      final statusResult = await _repository.getSessionStatus(
        sessionId: event.sessionId,
      );
      
      // 根据状态更新相应的UI
      AppLogger.i(_tag, '会话状态: $statusResult');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '获取会话状态失败', e, stackTrace);
    }
  }

  /// 取消会话
  Future<void> _onCancelSession(
    CancelSessionEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      await _repository.cancelSession(sessionId: event.sessionId);
      
      // 更新UI状态
      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        if (currentState.activeSessionId == event.sessionId) {
          emit(currentState.copyWith(
            isGenerating: false,
            currentOperation: null,
          ));
        }
      }
      
      AppLogger.i(_tag, '会话已取消: ${event.sessionId}');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '取消会话失败', e, stackTrace);
    }
  }

  /// 获取用户历史记录
  Future<void> _onGetUserHistories(
    GetUserHistoriesEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      final histories = await _repository.getUserHistories(
        novelId: event.novelId,
        page: event.page,
        size: event.size,
      );
      
      // 转换为Session对象并更新状态
      final sessions = histories.map((history) {
        return SettingGenerationSession.fromJson(history);
      }).toList();
      
      // 根据当前状态更新
      if (state is SettingGenerationReady) {
        final currentState = state as SettingGenerationReady;
        emit(currentState.copyWith(sessions: sessions));
      }
      
      AppLogger.i(_tag, '成功获取${sessions.length}条用户历史记录');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '获取用户历史记录失败', e, stackTrace);
    }
  }

  /// 删除历史记录
  Future<void> _onDeleteHistory(
    DeleteHistoryEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      await _repository.deleteHistory(historyId: event.historyId);
      
      // 从当前会话列表中移除
      if (state is SettingGenerationReady) {
        final currentState = state as SettingGenerationReady;
        final updatedSessions = currentState.sessions
            .where((session) => session.sessionId != event.historyId)
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      } else if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        final updatedSessions = currentState.sessions
            .where((session) => session.sessionId != event.historyId)
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      } else if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        final updatedSessions = currentState.sessions
            .where((session) => session.sessionId != event.historyId)
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      }
      
      AppLogger.i(_tag, '历史记录已删除: ${event.historyId}');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '删除历史记录失败', e, stackTrace);
    }
  }

  /// 批量删除历史记录
  Future<void> _onBatchDeleteHistories(
    BatchDeleteHistoriesEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '开始批量删除历史记录: ${event.historyIds.length}条');
      
      final result = await _repository.batchDeleteHistories(
        historyIds: event.historyIds,
      );
      
      final deletedCount = result['data']['deletedCount'] as int;
      AppLogger.i(_tag, '批量删除成功: ${deletedCount}条');
      
      // 从当前会话列表中移除已删除的记录
      final deletedIds = event.historyIds.toSet();
      
      if (state is SettingGenerationReady) {
        final currentState = state as SettingGenerationReady;
        final updatedSessions = currentState.sessions
            .where((session) => !deletedIds.contains(session.sessionId))
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      } else if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        final updatedSessions = currentState.sessions
            .where((session) => !deletedIds.contains(session.sessionId))
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      } else if (state is SettingGenerationCompleted) {
        final currentState = state as SettingGenerationCompleted;
        final updatedSessions = currentState.sessions
            .where((session) => !deletedIds.contains(session.sessionId))
            .toList();
        emit(currentState.copyWith(sessions: updatedSessions));
      }
      
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '批量删除历史记录失败', e, stackTrace);
    }
  }

  /// 复制历史记录
  Future<void> _onCopyHistory(
    CopyHistoryEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      final result = await _repository.copyHistory(
        historyId: event.historyId,
        copyReason: event.copyReason,
      );
      
      // 创建新的会话对象并添加到列表
      final newSession = SettingGenerationSession.fromJson(result);
      
      if (state is SettingGenerationReady) {
        final currentState = state as SettingGenerationReady;
        final updatedSessions = [newSession, ...currentState.sessions];
        emit(currentState.copyWith(sessions: updatedSessions));
      }
      
      AppLogger.i(_tag, '历史记录复制成功');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '复制历史记录失败', e, stackTrace);
    }
  }

  /// 恢复历史记录到小说
  Future<void> _onRestoreHistoryToNovel(
    RestoreHistoryToNovelEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      emit(const SettingGenerationLoading(message: '正在恢复历史记录...'));
      
      final result = await _repository.restoreHistoryToNovel(
        historyId: event.historyId,
        novelId: event.novelId,
      );
      
      final restoredSettingIds = result['restoredSettingIds'] as List<dynamic>;
      
      emit(SettingGenerationSaved(
        savedSettingIds: restoredSettingIds.cast<String>(),
        message: '历史记录已成功恢复到小说中',
      ));
      
      AppLogger.i(_tag, '历史记录恢复成功，恢复了${restoredSettingIds.length}个设定');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '恢复历史记录失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '恢复历史记录失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// 更新调整提示词
  void _onUpdateAdjustmentPrompt(
    UpdateAdjustmentPromptEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is SettingGenerationReady) {
      final currentState = state as SettingGenerationReady;
      emit(currentState.copyWith(adjustmentPrompt: event.prompt));
    } else if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(adjustmentPrompt: event.prompt));
    } else if (state is SettingGenerationCompleted) {
      final currentState = state as SettingGenerationCompleted;
      emit(currentState.copyWith(adjustmentPrompt: event.prompt));
    }
  }

  /// 重置状态
  void _onReset(
    ResetEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    _generationStreamSubscription?.cancel();
    _updateStreamSubscription?.cancel();
    emit(const SettingGenerationInitial());
  }

  /// 重试事件处理（从错误状态恢复）
  Future<void> _onRetry(
    RetryEvent event,
    Emitter<SettingGenerationState> emit,
  ) async {
    try {
      AppLogger.i(_tag, '🔄 用户请求重试，重新加载策略');
      
      // 取消任何正在进行的流订阅
      _generationStreamSubscription?.cancel();
      _updateStreamSubscription?.cancel();
      
      emit(const SettingGenerationLoading(message: '正在重新初始化...'));
      
      // 重新加载策略
      final strategies = await _repository.getAvailableStrategies();
      
      emit(SettingGenerationReady(
        strategies: strategies,
        sessions: [],
      ));
      
      AppLogger.i(_tag, '✅ 重试成功，系统已重新初始化');
    } catch (e, stackTrace) {
      AppLogger.error(_tag, '重试失败', e, stackTrace);
      emit(SettingGenerationError(
        message: '重试失败：${e.toString()}',
        error: e,
        stackTrace: stackTrace,
        isRecoverable: true,
      ));
    }
  }

  // ==================== 内部事件处理器 ==================== 

  /// 处理生成事件
  void _onHandleGenerationEvent(
    _HandleGenerationEventInternal event,
    Emitter<SettingGenerationState> emit,
  ) {
    // 收到任何后端生成事件都视为"活动"，仅在生成/更新中才刷新超时计时
    if (state is SettingGenerationInProgress || state is SettingGenerationNodeUpdating) {
      _markActivityAndResetTimeout();
    }
    // 🔧 修复：支持SettingGenerationNodeUpdating状态
    if (state is! SettingGenerationInProgress && state is! SettingGenerationNodeUpdating) return;
    
    final generationEvent = event.event;
    AppLogger.info(_tag, '收到生成事件: ${generationEvent.eventType}');

    // 🔧 新增：针对SettingGenerationNodeUpdating状态的特殊处理
    if (state is SettingGenerationNodeUpdating) {
      final currentState = state as SettingGenerationNodeUpdating;
      final updatedEvents = [...currentState.events, generationEvent];

      // 🔧 移除：在新的非删除式修改方案中，不再处理NodeDeletedEvent
      // if (generationEvent is event_model.NodeDeletedEvent) { ... }
      
      if (generationEvent is event_model.NodeCreatedEvent) {
        AppLogger.i(_tag, '➕ 节点创建事件 (NodeUpdating): ${generationEvent.node.name}');
        final updatedNodes = _insertNodeIntoTree(
          currentState.activeSession.rootNodes,
          generationEvent.node,
          generationEvent.parentPath,
        );
        final updatedSession = currentState.activeSession.copyWith(rootNodes: updatedNodes);
        final updatedSessions = currentState.sessions.map((s) => s.sessionId == currentState.activeSessionId ? updatedSession : s).toList();

        // 🔧 关键修复：将新创建的节点ID添加到renderedNodeIds中，使其立即可见
        final updatedRenderedNodeIds = Set<String>.from(currentState.renderedNodeIds)
          ..add(generationEvent.node.id);
        
        // 🔧 添加新节点的渲染状态为已渲染
        final updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
        updatedNodeRenderStates[generationEvent.node.id] = NodeRenderInfo(
          nodeId: generationEvent.node.id,
          state: NodeRenderState.rendered,
        );

        AppLogger.i(_tag, '🔄 创建节点后 - 已渲染节点数: ${updatedRenderedNodeIds.length}');

        emit(currentState.copyWith(
          sessions: updatedSessions,
          activeSession: updatedSession,
          events: updatedEvents,
          message: '已创建节点: ${generationEvent.node.name}',
          selectedNodeId: generationEvent.node.id,
          renderedNodeIds: updatedRenderedNodeIds,
          nodeRenderStates: updatedNodeRenderStates,
        ));
        return;
      }
      
      if (generationEvent is event_model.NodeUpdatedEvent) {
        // 🔧 关键：只更新特定节点，不触发整个树的重新渲染
        AppLogger.i(_tag, '📝 节点修改完成: ${generationEvent.node.name} (ID: ${generationEvent.node.id})');
        
        final updatedNodes = _updateNodeInTree(
          currentState.activeSession.rootNodes,
          generationEvent.node.id,
          generationEvent.node,
        );
        final updatedSession = currentState.activeSession.copyWith(rootNodes: updatedNodes);
        final updatedSessions = currentState.sessions.map((session) {
          return session.sessionId == currentState.activeSessionId ? updatedSession : session;
        }).toList();
        
        // 🔧 返回到Completed状态，表示节点修改完成
        emit(SettingGenerationCompleted(
          strategies: currentState.strategies,
          sessions: updatedSessions,
          activeSessionId: currentState.activeSessionId,
          activeSession: updatedSession,
          selectedNodeId: currentState.selectedNodeId,
          viewMode: currentState.viewMode,
          adjustmentPrompt: currentState.adjustmentPrompt,
          pendingChanges: currentState.pendingChanges,
          highlightedNodeIds: const {},
          editHistory: currentState.editHistory,
          events: [...currentState.events, generationEvent],
          message: '节点 "${generationEvent.node.name}" 修改完成',
          nodeRenderStates: currentState.nodeRenderStates,
          renderedNodeIds: currentState.renderedNodeIds,
        ));
        return;
      } else if (generationEvent is event_model.GenerationProgressEvent) {
        // 只更新进度消息，保持在NodeUpdating状态
        emit(currentState.copyWith(
          message: generationEvent.message,
          events: [...currentState.events, generationEvent],
        ));
        return;
      } else if (generationEvent is event_model.GenerationErrorEvent) {
        // 节点修改失败：不进入错误态，保持原态并结束NodeUpdating
        emit(currentState.copyWith(
          message: '节点修改失败：${generationEvent.errorMessage}',
          events: updatedEvents,
          // 结束更新中标记
          // ignore: invalid_use_of_visible_for_testing_member
          isUpdating: false,
        ));
        return;
      } else if (generationEvent is event_model.GenerationCompletedEvent) {
        // 后端现在会在完成时自然结束SSE流（takeUntil + sink.complete），不主动取消以避免插件触发 AbortError → 自动重连
        
        // 修改流程完成，返回到Completed状态
        emit(SettingGenerationCompleted(
          strategies: currentState.strategies,
          sessions: currentState.sessions,
          activeSessionId: currentState.activeSessionId,
          activeSession: currentState.activeSession,
          selectedNodeId: currentState.selectedNodeId,
          viewMode: currentState.viewMode,
          adjustmentPrompt: currentState.adjustmentPrompt,
          pendingChanges: currentState.pendingChanges,
          highlightedNodeIds: const {},
          editHistory: currentState.editHistory,
          events: [...currentState.events, generationEvent],
          message: generationEvent.message,
          nodeRenderStates: currentState.nodeRenderStates,
          renderedNodeIds: currentState.renderedNodeIds,
        ));
        return;
      }
      
      // 其他事件在NodeUpdating状态下忽略或简单更新
      emit(currentState.copyWith(
        events: [...currentState.events, generationEvent],
      ));
      return;
    }
    
    // 原有的SettingGenerationInProgress状态处理逻辑
    final currentState = state as SettingGenerationInProgress;
    final updatedEvents = [...currentState.events, generationEvent];
    
    // 🔧 移除：在新的非删除式修改方案中，不再处理NodeDeletedEvent
    // if (generationEvent is event_model.NodeDeletedEvent) { ... }

    if (generationEvent is event_model.SessionStartedEvent) {
      // 🔧 由于前端现在使用UUID生成sessionId并传给后端，不再需要更新sessionId
      AppLogger.i(_tag, '✅ SessionStartedEvent - sessionId: ${generationEvent.sessionId}');
      
      emit(currentState.copyWith(
        events: updatedEvents,
        currentOperation: '会话已启动，正在生成设定...',
      ));
    } else     if (generationEvent is event_model.NodeCreatedEvent) {
      // 🚀 改进：智能立即处理，只有真正需要等待的节点才暂存
      AppLogger.i(_tag, '⚡ 智能处理节点: ${generationEvent.node.name}');
      
      // 使用智能处理逻辑
      _processNodesImmediately([generationEvent], emit);
      
    } else if (generationEvent is event_model.NodeUpdatedEvent) {
      final updatedNodes = _updateNodeInTree(
        currentState.activeSession.rootNodes,
        generationEvent.node.id,
        generationEvent.node,
      );
      final updatedSession = currentState.activeSession.copyWith(rootNodes: updatedNodes);
      final updatedSessions = currentState.sessions.map((session) {
        return session.sessionId == currentState.activeSessionId ? updatedSession : session;
      }).toList();
      
      emit(currentState.copyWith(
        sessions: updatedSessions,
        activeSession: updatedSession,
        events: updatedEvents,
        currentOperation: '已更新节点: ${generationEvent.node.name}',
      ));
    } else if (generationEvent is event_model.GenerationProgressEvent) {
      // 只更新操作消息，避免频繁更新events数组
      if (currentState.currentOperation != generationEvent.message) {
        emit(currentState.copyWith(
          currentOperation: generationEvent.message,
        ));
      }
    } else if (generationEvent is event_model.GenerationCompletedEvent) {
      // 🔧 关键修复：在完成前，强制处理所有暂存的节点
      if (currentState.pendingNodes.isNotEmpty) {
        // 后端会自然结束SSE，避免主动取消导致 AbortError
        AppLogger.i(_tag, '⚡️ 完成信号收到，强制处理 ${currentState.pendingNodes.length} 个暂存节点');
        
        // 🚀 改进：使用智能处理替代原有的批量处理
        final allPendingNodes = List<event_model.NodeCreatedEvent>.from(currentState.pendingNodes);
        _processNodesImmediately(allPendingNodes, emit);
        
        // 等待一小段时间确保所有节点都被处理
        Timer(const Duration(milliseconds: 100), () {
          if (!isClosed) {
            add(const ProcessRenderQueueEvent());
          }
        });
        
        // 重新获取最新的状态
        final latestState = state as SettingGenerationInProgress;
        
        // 使用最新的状态继续完成流程
        final updatedSession = latestState.activeSession.copyWith(status: SessionStatus.completed);
        final updatedSessions = latestState.sessions.map((session) {
          return session.sessionId == latestState.activeSessionId ? updatedSession : session;
        }).toList();
        
        // 🔧 关键修复：将所有正在渲染的节点标记为已渲染，避免状态转换时丢失
        final renderingNodeIds = latestState.nodeRenderStates.entries
            .where((entry) => entry.value.state == NodeRenderState.rendering)
            .map((entry) => entry.key)
            .toSet();
        
        final finalRenderedNodeIds = Set<String>.from(latestState.renderedNodeIds)
          ..addAll(renderingNodeIds);
          
        AppLogger.i(_tag, '🔧 完成时强制标记正在渲染的节点为已渲染: ${renderingNodeIds.length}个, 总已渲染: ${finalRenderedNodeIds.length}');

        emit(SettingGenerationCompleted(
          strategies: latestState.strategies,
          sessions: updatedSessions,
          activeSessionId: latestState.activeSessionId,
          activeSession: updatedSession,
          message: generationEvent.message,
          // 🔧 关键修复：使用包含正在渲染节点的完整集合
          nodeRenderStates: latestState.nodeRenderStates,
          renderedNodeIds: finalRenderedNodeIds,
        ));

      } else {
        // 正常完成流程：先 flush 所有待处理节点，再触发渲染队列，然后统一收尾

        // 1) Flush pendingNodes（如有）
        if (currentState.pendingNodes.isNotEmpty) {
          AppLogger.i(_tag, '⚡️ 正常完成前先处理 ${currentState.pendingNodes.length} 个暂存节点');
          final allPendingNodes = List<event_model.NodeCreatedEvent>.from(currentState.pendingNodes);
          _processNodesImmediately(allPendingNodes, emit);
          // 触发一次渲染队列处理
          Timer(const Duration(milliseconds: 50), () {
            if (!isClosed) {
              add(const ProcessRenderQueueEvent());
            }
          });
        }

        // 2) 统一把 pending/queued/rendering 的节点标记为已渲染，并确保插入到树
        final latest = state as SettingGenerationInProgress; // flush 后取最新
        final updatedSession = latest.activeSession.copyWith(status: SessionStatus.completed);
        final updatedSessions = latest.sessions.map((session) {
          return session.sessionId == latest.activeSessionId ? updatedSession : session;
        }).toList();

        // 收集需要标记完成的节点ID（非已渲染）
        final toFinalizeIds = latest.nodeRenderStates.entries
            .where((e) => e.value.state == NodeRenderState.pending ||
                           e.value.state == NodeRenderState.rendering)
            .map((e) => e.key)
            .where((id) => !latest.renderedNodeIds.contains(id))
            .toSet();

        // 将这些节点加入 rendered 集合
        final finalRenderedNodeIds = Set<String>.from(latest.renderedNodeIds)..addAll(toFinalizeIds);

        AppLogger.i(_tag, '🔧 正常完成：补标记未完成节点为已渲染: ${toFinalizeIds.length} 个, 总已渲染: ${finalRenderedNodeIds.length}');

        emit(SettingGenerationCompleted(
          strategies: latest.strategies,
          sessions: updatedSessions,
          activeSessionId: latest.activeSessionId,
          activeSession: updatedSession,
          selectedNodeId: latest.selectedNodeId,
          viewMode: latest.viewMode,
          adjustmentPrompt: latest.adjustmentPrompt,
          pendingChanges: latest.pendingChanges,
          highlightedNodeIds: const {},
          editHistory: latest.editHistory,
          events: updatedEvents,
          message: generationEvent.message,
          nodeRenderStates: latest.nodeRenderStates,
          renderedNodeIds: finalRenderedNodeIds,
        ));
      }
    } else if (generationEvent is event_model.GenerationErrorEvent) {
      // 保留当前 UI，不切换到 Error 状态，只停止生成并记录错误
      emit(currentState.copyWith(
        isGenerating: false,
        currentOperation: null,
        events: updatedEvents,
      ));
      return;
    }
  }

  /// 处理生成错误
  void _onHandleGenerationError(
    _HandleGenerationErrorInternal event,
    Emitter<SettingGenerationState> emit,
  ) {
    String message = event.userFriendlyMessage ?? _getUserFriendlyErrorMessage(event.error);
    // 🔧 新增：发生错误时立即取消生成流，避免SSE自动重连导致无限重试
    _generationStreamSubscription?.cancel();

    // 优先处理超时：不切换到错误页，保留当前设定树，仅在顶部显示状态
    final errorString = event.error.toString().toLowerCase();
    final isTimeout = errorString.contains('timeout');

    if (isTimeout) {
      if (state is SettingGenerationInProgress) {
        final currentState = state as SettingGenerationInProgress;
        emit(currentState.copyWith(
          isGenerating: false,
          currentOperation: '请求超时，连接已断开。已保留当前设定内容，可稍后重试',
        ));
        return;
      }
      if (state is SettingGenerationCompleted) {
        // Completed 状态无 currentOperation 字段，仅提示即可，不改变状态
        return;
      }
      if (state is SettingGenerationReady) {
        final currentState = state as SettingGenerationReady;
        emit(currentState.copyWith(
          // Ready 状态下，仅提示，不破坏会话与策略
        ));
        return;
      }
    }

    List<SettingGenerationSession> sessions = [];
    String? activeSessionId;

    if (state is SettingGenerationReady) {
      sessions = (state as SettingGenerationReady).sessions;
      activeSessionId = (state as SettingGenerationReady).activeSessionId;
      // 🔧 Ready 状态下也确保停止生成标志
      emit((state as SettingGenerationReady).copyWith());
    } else if (state is SettingGenerationInProgress) {
      sessions = (state as SettingGenerationInProgress).sessions;
      activeSessionId = (state as SettingGenerationInProgress).activeSessionId;
      // 🔧 确保停止生成并清空进度文案
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(
        isGenerating: false,
        currentOperation: null,
      ));
    } else if (state is SettingGenerationCompleted) {
      sessions = (state as SettingGenerationCompleted).sessions;
      activeSessionId = (state as SettingGenerationCompleted).activeSessionId;
    }

    // 在 NodeUpdating 期间，保持原态并弹Toast，不进入错误态
    if (state is SettingGenerationNodeUpdating) {
      add(const _HandleGenerationCompleteInternal());
      return;
    }

    emit(SettingGenerationError(
      message: message,
      error: event.error,
      stackTrace: event.stackTrace,
      isRecoverable: _isRecoverableError(event.error),
      sessions: sessions,
      activeSessionId: activeSessionId,
    ));
  }

  /// 处理生成完成
  void _onHandleGenerationComplete(
    _HandleGenerationCompleteInternal event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      emit(currentState.copyWith(
        isGenerating: false,
        currentOperation: null,
      ));
    } else if (state is SettingGenerationNodeUpdating) {
      // 🔧 兼容：当后端未显式发送完成事件但流已结束时，将节点修改状态回落为 Completed
      final s = state as SettingGenerationNodeUpdating;
      emit(SettingGenerationCompleted(
        strategies: s.strategies,
        sessions: s.sessions,
        activeSessionId: s.activeSessionId,
        activeSession: s.activeSession,
        selectedNodeId: s.selectedNodeId,
        viewMode: s.viewMode,
        adjustmentPrompt: s.adjustmentPrompt,
        pendingChanges: s.pendingChanges,
        highlightedNodeIds: s.highlightedNodeIds,
        editHistory: s.editHistory,
        events: s.events,
        message: s.message.isNotEmpty ? s.message : '节点修改完成',
        nodeRenderStates: s.nodeRenderStates,
        renderedNodeIds: s.renderedNodeIds,
      ));
    }
  }

  /// 🚀 改进的渲染队列处理
  void _onProcessRenderQueue(
    ProcessRenderQueueEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    
    // 🚀 实时计算可渲染节点，不依赖过时的renderableNodeIds
    final renderableNodeIds = _calculateRenderableNodesEfficiently(
      currentState.activeSession.rootNodes,
      currentState.renderQueue,
      currentState.renderedNodeIds,
      currentState.nodeRenderStates,
    );
    
    AppLogger.i(_tag, '🚀 实时计算渲染队列，可渲染节点: ${renderableNodeIds.length}');
    
    // 过滤掉已经在渲染中或已渲染的节点
    final nodesToRender = renderableNodeIds.where((nodeId) {
      final renderInfo = currentState.nodeRenderStates[nodeId];
      final isAlreadyProcessing = renderInfo?.state == NodeRenderState.rendering;
      final isAlreadyRendered = currentState.renderedNodeIds.contains(nodeId);
      return !isAlreadyProcessing && !isAlreadyRendered;
    }).toList();
    
    if (nodesToRender.isEmpty) {
      AppLogger.i(_tag, '📝 没有新的节点需要渲染');
      return;
    }
    
    // 🔧 关键修复：按父节点分组，避免同一父节点的子节点同时渲染
    final nodesByParent = <String?, List<String>>{};
    for (final nodeId in nodesToRender) {
      final node = SettingNodeUtils.findNodeInTree(currentState.activeSession.rootNodes, nodeId);
      if (node != null) {
        final parentNode = SettingNodeUtils.findParentNodeInTree(currentState.activeSession.rootNodes, nodeId);
        final parentKey = parentNode?.id ?? 'root';
        nodesByParent.putIfAbsent(parentKey, () => []).add(nodeId);
      }
    }
    
    AppLogger.i(_tag, '🚀 按父节点分组: ${nodesByParent.length}个父节点组');
    
    // 🔧 交错渲染策略：每个父节点组只渲染第一个子节点，其余延迟处理
    final immediateNodes = <String>[];
    final delayedNodes = <String>[];
    
    for (final entry in nodesByParent.entries) {
      final parentKey = entry.key;
      final childNodes = entry.value;
      
      if (childNodes.isNotEmpty) {
        // 每个父节点组立即渲染第一个子节点
        immediateNodes.add(childNodes.first);
        AppLogger.i(_tag, '⚡ 立即渲染: ${childNodes.first} (父节点: $parentKey)');
        
        // 其余子节点延迟渲染
        if (childNodes.length > 1) {
          delayedNodes.addAll(childNodes.skip(1));
          AppLogger.i(_tag, '⏰ 延迟渲染: ${childNodes.skip(1).join(', ')} (父节点: $parentKey)');
        }
      }
    }
    
    // 🔧 批量更新立即渲染的节点状态
    if (immediateNodes.isNotEmpty) {
      final updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
      final updatedRenderQueue = currentState.renderQueue.where((id) => !immediateNodes.contains(id)).toList();
      final updatedHighlightedNodeIds = Set<String>.from(currentState.highlightedNodeIds);
      
      // 为立即渲染的节点设置渲染状态
      for (final nodeId in immediateNodes) {
        updatedNodeRenderStates[nodeId] = NodeRenderInfo(
          nodeId: nodeId,
          state: NodeRenderState.rendering,
          renderStartTime: DateTime.now(),
        );
        updatedHighlightedNodeIds.add(nodeId);
        
        AppLogger.i(_tag, '▶️ 开始渲染节点: $nodeId');
        
        // 🔧 设置完成渲染的定时器
        Timer(const Duration(milliseconds: 800), () {
          if (!isClosed) {
            AppLogger.i(_tag, '⏰ 触发节点渲染完成事件: $nodeId');
            add(CompleteNodeRenderEvent(nodeId));
          } else {
            AppLogger.w(_tag, '⚠️ BLoC已关闭，跳过节点渲染完成: $nodeId');
          }
        });
      }
      
      emit(currentState.copyWith(
        nodeRenderStates: updatedNodeRenderStates,
        renderQueue: updatedRenderQueue,
        highlightedNodeIds: updatedHighlightedNodeIds,
      ));
    }
    
    // 🔧 延迟处理其余节点，避免同一帧内多次状态变化
    if (delayedNodes.isNotEmpty) {
      Timer(const Duration(milliseconds: 200), () {
        if (!isClosed && state is SettingGenerationInProgress) {
          // 直接触发队列处理事件，让渲染队列自然处理延迟节点
          add(const ProcessRenderQueueEvent());
        }
      });
    }
  }

  // 🔧 修复：简化开始渲染节点的逻辑
  void _onStartNodeRender(
    StartNodeRenderEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    if (state is! SettingGenerationInProgress) return;
    
    final currentState = state as SettingGenerationInProgress;
    final nodeId = event.nodeId;
    
    // 🔧 修复：检查节点是否已经在处理中，避免重复处理
    final renderInfo = currentState.nodeRenderStates[nodeId];
    if (renderInfo?.state == NodeRenderState.rendering || 
        currentState.renderedNodeIds.contains(nodeId)) {
      AppLogger.w(_tag, '⚠️ 节点已在处理中，跳过: $nodeId');
      return;
    }
    
    // 更新节点渲染状态为正在渲染
    final updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
    updatedNodeRenderStates[nodeId] = NodeRenderInfo(
      nodeId: nodeId,
      state: NodeRenderState.rendering,
      renderStartTime: DateTime.now(),
    );
    
    // 从渲染队列中移除
    final updatedRenderQueue = currentState.renderQueue.where((id) => id != nodeId).toList();
    
    // 添加到高亮列表
    final updatedHighlightedNodeIds = Set<String>.from(currentState.highlightedNodeIds)..add(nodeId);
    
    emit(currentState.copyWith(
      nodeRenderStates: updatedNodeRenderStates,
      renderQueue: updatedRenderQueue,
      highlightedNodeIds: updatedHighlightedNodeIds,
    ));
    
    AppLogger.i(_tag, '▶️ 开始渲染节点: $nodeId');
    
    // 设置定时器自动完成渲染（模拟动画时间）
    Timer(const Duration(milliseconds: 800), () {
      if (!isClosed) {
        AppLogger.i(_tag, '⏰ 触发节点渲染完成事件: $nodeId');
        add(CompleteNodeRenderEvent(nodeId));
      } else {
        AppLogger.w(_tag, '⚠️ BLoC已关闭，跳过节点渲染完成: $nodeId');
      }
    });
  }

  // 🔧 修复：完成节点渲染，支持多种状态
  void _onCompleteNodeRender(
    CompleteNodeRenderEvent event,
    Emitter<SettingGenerationState> emit,
  ) {
    AppLogger.i(_tag, '🔄 处理节点渲染完成事件: ${event.nodeId}');
    final nodeId = event.nodeId;
    
    // 🔧 关键修复：支持SettingGenerationInProgress和SettingGenerationCompleted两种状态
    if (state is SettingGenerationInProgress) {
      final currentState = state as SettingGenerationInProgress;
      _completeNodeRenderInProgress(currentState, nodeId, emit);
    } else if (state is SettingGenerationCompleted) {
      final currentState = state as SettingGenerationCompleted;
      _completeNodeRenderInCompleted(currentState, nodeId, emit);
    } else {
      AppLogger.w(_tag, '⚠️ 状态不支持渲染完成: ${event.nodeId} (当前状态: ${state.runtimeType})');
    }
  }

  /// 在InProgress状态下完成节点渲染
  void _completeNodeRenderInProgress(
    SettingGenerationInProgress currentState,
    String nodeId,
    Emitter<SettingGenerationState> emit,
  ) {
    
    // 🔧 修复：检查节点是否已经完成渲染，避免重复处理
    if (currentState.renderedNodeIds.contains(nodeId)) {
      AppLogger.w(_tag, '⚠️ 节点已完成渲染，跳过: $nodeId');
      return;
    }
    
    // 更新节点渲染状态为已渲染
    final updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
    updatedNodeRenderStates[nodeId] = NodeRenderInfo(
      nodeId: nodeId,
      state: NodeRenderState.rendered,
      renderStartTime: updatedNodeRenderStates[nodeId]?.renderStartTime,
      renderDuration: updatedNodeRenderStates[nodeId]?.renderStartTime != null 
          ? DateTime.now().difference(updatedNodeRenderStates[nodeId]!.renderStartTime!)
          : null,
    );
    
    // 添加到已渲染节点集合
    final beforeCount = currentState.renderedNodeIds.length;
    final updatedRenderedNodeIds = Set<String>.from(currentState.renderedNodeIds)..add(nodeId);
    final afterCount = updatedRenderedNodeIds.length;
    
    AppLogger.i(_tag, '📊 更新已渲染节点集合: $nodeId (${beforeCount} -> ${afterCount})');
    
    // 从高亮列表中移除
    final updatedHighlightedNodeIds = Set<String>.from(currentState.highlightedNodeIds)..remove(nodeId);
    
    emit(currentState.copyWith(
      nodeRenderStates: updatedNodeRenderStates,
      renderedNodeIds: updatedRenderedNodeIds,
      highlightedNodeIds: updatedHighlightedNodeIds,
    ));
    
    AppLogger.i(_tag, '✅ 完成渲染节点: $nodeId, 总已渲染: ${afterCount}');
    
    // 🔧 修复：使用更长的延迟处理，确保UI稳定后再处理下一批
    Timer(const Duration(milliseconds: 300), () {
      if (!isClosed && state is SettingGenerationInProgress) {
        final current = state as SettingGenerationInProgress;
        // 只有当还有队列中的节点时才继续处理
        if (current.renderQueue.isNotEmpty) {
          add(const ProcessRenderQueueEvent());
        }
      }
    });
  }

  /// 在Completed状态下完成节点渲染
  void _completeNodeRenderInCompleted(
    SettingGenerationCompleted currentState,
    String nodeId,
    Emitter<SettingGenerationState> emit,
  ) {
    AppLogger.i(_tag, '🔄 在Completed状态下处理节点渲染完成: $nodeId');
    
    // 🔧 检查节点是否已经完成渲染
    if (currentState.renderedNodeIds.contains(nodeId)) {
      AppLogger.w(_tag, '⚠️ 节点已完成渲染，跳过: $nodeId');
      return;
    }
    
    // 🔧 关键修复：在Completed状态下也要更新renderedNodeIds
    final beforeCount = currentState.renderedNodeIds.length;
    final updatedRenderedNodeIds = Set<String>.from(currentState.renderedNodeIds)..add(nodeId);
    final afterCount = updatedRenderedNodeIds.length;
    
    AppLogger.i(_tag, '📊 Completed状态下更新已渲染节点集合: $nodeId (${beforeCount} -> ${afterCount})');
    
    // 更新节点渲染状态
    final updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);
    updatedNodeRenderStates[nodeId] = NodeRenderInfo(
      nodeId: nodeId,
      state: NodeRenderState.rendered,
      renderStartTime: updatedNodeRenderStates[nodeId]?.renderStartTime,
      renderDuration: updatedNodeRenderStates[nodeId]?.renderStartTime != null 
          ? DateTime.now().difference(updatedNodeRenderStates[nodeId]!.renderStartTime!)
          : null,
    );
    
    // 🔧 发出更新后的Completed状态
    emit(SettingGenerationCompleted(
      strategies: currentState.strategies,
      sessions: currentState.sessions,
      activeSessionId: currentState.activeSessionId,
      activeSession: currentState.activeSession,
      selectedNodeId: currentState.selectedNodeId,
      viewMode: currentState.viewMode,
      adjustmentPrompt: currentState.adjustmentPrompt,
      pendingChanges: currentState.pendingChanges,
      highlightedNodeIds: currentState.highlightedNodeIds,
      editHistory: currentState.editHistory,
      events: currentState.events,
      message: currentState.message,
      nodeRenderStates: updatedNodeRenderStates,
      renderedNodeIds: updatedRenderedNodeIds,
    ));
    
    AppLogger.i(_tag, '✅ Completed状态下完成渲染节点: $nodeId, 总已渲染: ${afterCount}');
  }

  // 工具方法
  
  // 🔧 移除：_removeNodesFromTree函数不再使用（非删除式修改方案）
  
  /// 将新节点插入到树中的正确位置（支持层级结构）
  List<SettingNode> _insertNodeIntoTree(
    List<SettingNode> nodes,
    SettingNode newNode,
    String? parentPath,
  ) {
    // 如果没有父路径，添加到根级别
    if (parentPath == null || parentPath.isEmpty) {
      AppLogger.i(_tag, '🌳 ${newNode.name} -> 根节点');
      return [...nodes, newNode];
    }
    
    // 处理路径：移除开头的/，然后split
    String cleanPath = parentPath.startsWith('/') ? parentPath.substring(1) : parentPath;
    if (cleanPath.isEmpty) {
      AppLogger.i(_tag, '🌳 ${newNode.name} -> 根节点');
      return [...nodes, newNode];
    }
    
    final pathSegments = cleanPath.split('/').where((segment) => segment.isNotEmpty).toList();
    AppLogger.i(_tag, '🌳 ${newNode.name} -> ${pathSegments.join('/')}');
    
    // 根据父路径查找正确的插入位置
    final result = _insertNodeAtPath(nodes, newNode, pathSegments);
    
    return result;
  }
  
  /// 递归插入节点到指定路径
  List<SettingNode> _insertNodeAtPath(
    List<SettingNode> nodes,
    SettingNode newNode,
    List<String> pathSegments,
  ) {
    if (pathSegments.isEmpty) {
      // 🔧 性能优化：若已存在同 id 节点，直接替换而非重复插入
      final existingIndex = nodes.indexWhere((n) => n.id == newNode.id);
      if (existingIndex != -1) {
        final replaced = [...nodes];
        replaced[existingIndex] = newNode;
        return replaced;
      }
      return [...nodes, newNode];
    }
    
    final targetName = pathSegments.first;
    final remainingPath = pathSegments.skip(1).toList();
    
    // 先尝试按ID查找，如果找不到则按名称查找
    SettingNode? targetNode;
    int targetIndex = -1;
    
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.id == targetName || node.name == targetName) {
        targetNode = node;
        targetIndex = i;
        break;
      }
    }
    
    // 如果找不到父节点，创建一个占位父节点
    if (targetNode == null) {
      AppLogger.w(_tag, '🌳 创建占位父节点: $targetName');
      final placeholderParent = SettingNode(
        id: 'placeholder_${targetName}_${DateTime.now().millisecondsSinceEpoch}',
        name: targetName,
        type: SettingType.lore, // 默认类型
        description: '占位节点，等待后续更新',
        generationStatus: GenerationStatus.pending,
        children: [],
      );
      
      // 将占位父节点添加到当前级别
      final updatedNodes = [...nodes, placeholderParent];
      targetNode = placeholderParent;
      targetIndex = updatedNodes.length - 1;
      
      // 继续处理剩余路径
      if (remainingPath.isEmpty) {
        // 这是目标父节点，添加子节点
        final currentChildren = targetNode.children ?? [];
        // 去重：如果子节点已存在则替换
        int existingChildIndex = currentChildren.indexWhere((c) => c.id == newNode.id);
        List<SettingNode> updatedChildren;
        if (existingChildIndex != -1) {
          updatedChildren = [...currentChildren];
          updatedChildren[existingChildIndex] = newNode;
        } else {
          updatedChildren = [...currentChildren, newNode];
        }
        final updatedNode = targetNode.copyWith(children: updatedChildren);
        
        // 替换原节点
        final finalNodes = [...updatedNodes];
        finalNodes[targetIndex] = updatedNode;
        
        return finalNodes;
      } else {
        // 继续向下递归
        final updatedChildren = _insertNodeAtPath(
          targetNode.children ?? [],
          newNode,
          remainingPath,
        );
        final updatedNode = targetNode.copyWith(children: updatedChildren);
        
        // 替换原节点
        final finalNodes = [...updatedNodes];
        finalNodes[targetIndex] = updatedNode;
        
        return finalNodes;
      }
    }
    
    if (remainingPath.isEmpty) {
      // 这是目标父节点，添加子节点
      final currentChildren = targetNode.children ?? [];
      // 去重：如果子节点已存在则替换
      int existingChildIndex = currentChildren.indexWhere((c) => c.id == newNode.id);
      List<SettingNode> updatedChildren;
      if (existingChildIndex != -1) {
        updatedChildren = [...currentChildren];
        updatedChildren[existingChildIndex] = newNode;
      } else {
        updatedChildren = [...currentChildren, newNode];
      }
      final updatedNode = targetNode.copyWith(children: updatedChildren);
      
      // 替换原节点
      final updatedNodes = [...nodes];
      updatedNodes[targetIndex] = updatedNode;
      
      return updatedNodes;
    } else {
      // 继续向下递归
      final updatedChildren = _insertNodeAtPath(
        targetNode.children ?? [],
        newNode,
        remainingPath,
      );
      final updatedNode = targetNode.copyWith(children: updatedChildren);
      
      // 替换原节点
      final updatedNodes = [...nodes];
      updatedNodes[targetIndex] = updatedNode;
      
      return updatedNodes;
    }
  }
  
  /// 更新节点树中的节点
  List<SettingNode> _updateNodeInTree(
    List<SettingNode> nodes,
    String nodeId,
    SettingNode updatedNode,
  ) {
    return nodes.map((node) {
      if (node.id == nodeId) {
        return updatedNode;
      }
      if (node.children != null) {
        return node.copyWith(
          children: _updateNodeInTree(node.children!, nodeId, updatedNode),
        );
      }
      return node;
    }).toList();
  }

  /// 应用更改到节点树
  List<SettingNode> _applyChangesToNodes(
    List<SettingNode> nodes,
    Map<String, SettingNode> changes,
  ) {
    return nodes.map((node) {
      final updatedNode = changes[node.id] ?? node;
      if (node.children != null) {
        return updatedNode.copyWith(
          children: _applyChangesToNodes(node.children!, changes),
        );
      }
      return updatedNode;
    }).toList();
  }
  
  /// 获取用户友好的错误信息
  String _getUserFriendlyErrorMessage(dynamic error) {
    // 🚀 优先检查具体的异常类型
    if (error is InsufficientCreditsException) {
      return error.message;
    }
    
    final errorString = error.toString().toLowerCase();
    
    // 🚀 检查积分不足相关的关键词
    if (errorString.contains('积分不足') || 
        errorString.contains('积分余额不足') ||
        errorString.contains('payment required') ||
        errorString.contains('402')) {
      // 尝试提取更详细的信息
      if (errorString.contains('需要') && errorString.contains('积分')) {
        return error.toString(); // 保持原始详细信息
      }
      return '积分余额不足，请充值后继续使用';
    } else if (errorString.contains('unknown strategy')) {
      return '选择的生成策略不可用，请刷新页面后重试';
    } else if (errorString.contains('text_stage_empty') || errorString.contains('start_failed')) {
      // 明确提示当前模型调用异常
      return '当前模型调用异常，请更换模型或稍后重试';
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      return '网络连接失败，请检查网络后重试';
    } else if (errorString.contains('timeout')) {
      return '请求超时，请稍后重试';
    } else if (errorString.contains('unauthorized') || errorString.contains('forbidden')) {
      return '没有权限执行该操作，请检查登录状态';
    } else if (errorString.contains('model') || errorString.contains('config')) {
      return 'AI模型配置错误，请检查模型设置';
    } else if (errorString.contains('rate limit') || errorString.contains('quota')) {
      return 'AI服务调用频繁，请稍后再试';
    } else {
      return '生成过程中出现错误，请稍后重试';
    }
  }
  
  /// 判断错误是否可恢复
  bool _isRecoverableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // 不可恢复的错误
    if (errorString.contains('unauthorized') || 
        errorString.contains('forbidden') ||
        errorString.contains('invalid model') ||
        errorString.contains('configuration error')) {
      return false;
    }
    
    // 其他错误都认为可恢复
    return true;
  }

  Future<void> _onProcessPendingNodes(
    _ProcessPendingNodes event,
    Emitter<SettingGenerationState> emit,
  ) async {
    if (state is! SettingGenerationInProgress) return;

    final currentState = state as SettingGenerationInProgress;
    if (currentState.pendingNodes.isEmpty) return;

    AppLogger.i(_tag, '🔄 处理暂存的 ${currentState.pendingNodes.length} 个节点');

    var currentNodes = currentState.activeSession.rootNodes;
    var updatedRenderQueue = List<String>.from(currentState.renderQueue);
    var updatedNodeRenderStates = Map<String, NodeRenderInfo>.from(currentState.nodeRenderStates);

    // 1. 拓扑排序
    final sortedEvents = _topologicallySortNodes(currentState.pendingNodes);

    // 2. 批量插入
    for (final nodeEvent in sortedEvents) {
      currentNodes = _insertNodeIntoTree(
        currentNodes,
        nodeEvent.node,
        nodeEvent.parentPath,
      );
      
      updatedRenderQueue.add(nodeEvent.node.id);
      updatedNodeRenderStates[nodeEvent.node.id] = NodeRenderInfo(
        nodeId: nodeEvent.node.id,
        state: NodeRenderState.pending,
      );
    }

    final updatedSession = currentState.activeSession.copyWith(rootNodes: currentNodes);
    final updatedSessions = currentState.sessions.map((session) {
      return session.sessionId == currentState.activeSessionId ? updatedSession : session;
    }).toList();

    emit(currentState.copyWith(
      sessions: updatedSessions,
      activeSession: updatedSession,
      pendingNodes: [], // Clear pending nodes
      renderQueue: updatedRenderQueue,
      nodeRenderStates: updatedNodeRenderStates,
      currentOperation: '已处理 ${sortedEvents.length} 个新节点',
    ));

    // 触发渲染队列处理
    add(const ProcessRenderQueueEvent());
  }

  /// 🚀 改进的拓扑排序算法，支持增量处理和已存在的节点
  List<event_model.NodeCreatedEvent> _improvedTopologicalSort(
    List<event_model.NodeCreatedEvent> events, 
    List<SettingNode> existingNodes,
  ) {
    if (events.isEmpty) return [];

    final nodes = events.map((e) => e.node).toList();
    final nodeMap = {for (var node in nodes) node.id: node};
    final eventMap = {for (var e in events) e.node.id: e};
    
    // 构建已存在节点的ID集合
    final existingNodeIds = _collectAllNodeIds(existingNodes).toSet();
    
    AppLogger.i(_tag, '🔄 拓扑排序 - 新节点: ${nodes.length}, 已存在: ${existingNodeIds.length}');

    // 计算入度，考虑已存在的节点
    final inDegree = {for (var node in nodes) node.id: 0};
    final graph = {for (var node in nodes) node.id: <String>[]};

    // 构建依赖图
    for (final node in nodes) {
      final parentId = node.parentId;
      
      if (parentId != null) {
        if (nodeMap.containsKey(parentId)) {
          // 父节点在当前批次中
          graph[parentId]!.add(node.id);
          inDegree[node.id] = (inDegree[node.id] ?? 0) + 1;
          AppLogger.i(_tag, '📊 依赖关系: ${node.name} <- ${nodeMap[parentId]!.name}');
        } else if (existingNodeIds.contains(parentId)) {
          // 父节点已存在，无需等待
          AppLogger.i(_tag, '✅ 父节点已存在: ${node.name}');
          // 入度保持为0，可以立即处理
        } else {
          // 父节点既不在当前批次，也不存在，设置高入度等待
          inDegree[node.id] = 999;
          AppLogger.w(_tag, '❌ 父节点不存在: ${node.name} (需要: $parentId)');
        }
      }
    }

    // Kahn算法进行拓扑排序
    final queue = inDegree.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList();
    
    final sortedIds = <String>[];
    final processedIds = <String>{};
    
    AppLogger.i(_tag, '🚀 开始排序，初始可处理: ${queue.length} 个节点');
    
    while (queue.isNotEmpty) {
      final nodeId = queue.removeAt(0);
      
      if (processedIds.contains(nodeId)) {
        continue; // 避免重复处理
      }
      
      sortedIds.add(nodeId);
      processedIds.add(nodeId);
      
      final nodeName = nodeMap[nodeId]?.name ?? nodeId;
      AppLogger.i(_tag, '✅ 排序节点: $nodeName');

      // 更新依赖此节点的其他节点
      if (graph.containsKey(nodeId)) {
        for (final neighborId in graph[nodeId]!) {
          if (!processedIds.contains(neighborId)) {
            inDegree[neighborId] = (inDegree[neighborId] ?? 0) - 1;
            if (inDegree[neighborId] == 0) {
              queue.add(neighborId);
              AppLogger.i(_tag, '➡️ 解锁节点: ${nodeMap[neighborId]?.name ?? neighborId}');
            }
          }
        }
      }
    }

    // 返回排序后的事件，过滤掉无法排序的节点
    final sortedEvents = sortedIds
        .map((id) => eventMap[id])
        .where((e) => e != null)
        .cast<event_model.NodeCreatedEvent>()
        .toList();
        
    // 检查是否有无法排序的节点（循环依赖或缺少父节点）
    final missedNodes = nodes.where((node) => !processedIds.contains(node.id)).toList();
    if (missedNodes.isNotEmpty) {
      AppLogger.w(_tag, '⚠️ 无法排序的节点: ${missedNodes.map((n) => n.name).join(', ')}');
    }

    AppLogger.i(_tag, '🎯 排序完成: ${sortedEvents.length}/${nodes.length} 个节点');
    return sortedEvents;
  }

  /// 收集所有节点的ID（包括子节点）
  List<String> _collectAllNodeIds(List<SettingNode> nodes) {
    final ids = <String>[];
    for (final node in nodes) {
      ids.add(node.id);
      if (node.children != null) {
        ids.addAll(_collectAllNodeIds(node.children!));
      }
    }
    return ids;
  }

  /// 🚀 高效计算可渲染节点
  List<String> _calculateRenderableNodesEfficiently(
    List<SettingNode> rootNodes,
    List<String> renderQueue,
    Set<String> renderedNodeIds,
    Map<String, NodeRenderInfo> nodeRenderStates,
  ) {
    final List<String> renderable = [];
    
    AppLogger.i(_tag, '🔍 快速检查 ${renderQueue.length} 个待渲染节点，已渲染: ${renderedNodeIds.length}');
    
    for (final nodeId in renderQueue) {
      // 跳过已渲染或正在渲染的节点
      if (renderedNodeIds.contains(nodeId)) {
        continue;
      }
      
      final renderInfo = nodeRenderStates[nodeId];
      if (renderInfo?.state == NodeRenderState.rendering) {
        continue;
      }
      
      final node = SettingNodeUtils.findNodeInTree(rootNodes, nodeId);
      if (node == null) {
        AppLogger.w(_tag, '❌ 渲染队列中的节点不存在: $nodeId');
        continue;
      }
      
      // 检查依赖关系
      final parentNode = SettingNodeUtils.findParentNodeInTree(rootNodes, nodeId);
      
      if (parentNode == null) {
        // 根节点，可以渲染
        AppLogger.i(_tag, '✅ 根节点可渲染: ${node.name}');
        renderable.add(nodeId);
      } else if (renderedNodeIds.contains(parentNode.id)) {
        // 父节点已渲染，子节点可以渲染
        AppLogger.i(_tag, '✅ 父节点已渲染，可渲染: ${node.name}');
        renderable.add(nodeId);
      } else {
        AppLogger.i(_tag, '⏳ 等待父节点: ${node.name} <- ${parentNode.name}');
      }
    }
    
    AppLogger.i(_tag, '🎯 高效计算完成: ${renderable.length} 个节点可立即渲染');
    return renderable;
  }

  /// 🔧 保留原有的拓扑排序方法作为备用
  List<event_model.NodeCreatedEvent> _topologicallySortNodes(List<event_model.NodeCreatedEvent> events) {
    final nodes = events.map((e) => e.node).toList();
    final nodeMap = {for (var node in nodes) node.id: node};
    final inDegree = {for (var node in nodes) node.id: 0};
    final graph = {for (var node in nodes) node.id: <String>[]};

    for (final node in nodes) {
      // 修正：使用node.parentId而不是从parentPath解析
      final parentId = node.parentId;
      if (parentId != null && nodeMap.containsKey(parentId)) {
        graph[parentId]!.add(node.id);
        inDegree[node.id] = (inDegree[node.id] ?? 0) + 1;
      }
    }

    final queue = inDegree.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList();
    
    final sortedIds = <String>[];
    while (queue.isNotEmpty) {
      final nodeId = queue.removeAt(0);
      sortedIds.add(nodeId);

      if (graph.containsKey(nodeId)) {
        for (final neighborId in graph[nodeId]!) {
          inDegree[neighborId] = (inDegree[neighborId] ?? 0) - 1;
          if (inDegree[neighborId] == 0) {
            queue.add(neighborId);
          }
        }
      }
    }

    final eventMap = {for (var e in events) e.node.id: e};
    // 过滤掉可能因父节点不在当前批次而无法排序的节点
    return sortedIds.map((id) => eventMap[id]).where((e) => e != null).cast<event_model.NodeCreatedEvent>().toList();
  }
}

// 内部事件类

/// 处理生成事件
class _HandleGenerationEventInternal extends SettingGenerationBlocEvent {
  final event_model.SettingGenerationEvent event;

  const _HandleGenerationEventInternal(this.event);

  @override
  List<Object?> get props => [event];
}

/// 处理生成错误
class _HandleGenerationErrorInternal extends SettingGenerationBlocEvent {
  final dynamic error;
  final StackTrace? stackTrace;
  final String? userFriendlyMessage;

  const _HandleGenerationErrorInternal(this.error, this.stackTrace, [this.userFriendlyMessage]);

  @override
  List<Object?> get props => [error, stackTrace, userFriendlyMessage];
}

/// 处理生成完成
class _HandleGenerationCompleteInternal extends SettingGenerationBlocEvent {
  const _HandleGenerationCompleteInternal();
}

class _ProcessPendingNodes extends SettingGenerationBlocEvent {
  const _ProcessPendingNodes();
}

/// 定时器触发的超时检查内部事件
class _TimeoutCheckInternal extends SettingGenerationBlocEvent {
  const _TimeoutCheckInternal();
}
