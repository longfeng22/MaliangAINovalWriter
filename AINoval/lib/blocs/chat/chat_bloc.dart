import 'dart:async';

import 'package:ainoval/services/api_service/repositories/chat_repository.dart';
import 'package:ainoval/services/api_service/repositories/impl/chat_repository_impl.dart';
import 'package:ainoval/services/api_service/repositories/novel_setting_repository.dart';
import 'package:ainoval/services/api_service/repositories/novel_snippet_repository.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../models/chat_models.dart';
import '../../models/user_ai_model_config_model.dart';
import '../../services/auth_service.dart';
import '../../utils/logger.dart';
import '../ai_config/ai_config_bloc.dart';
import '../public_models/public_models_bloc.dart';
import 'chat_event.dart';
import 'chat_state.dart';
import '../../models/ai_request_models.dart';
import '../../models/context_selection_models.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required this.repository,
    required this.authService,
    required AiConfigBloc aiConfigBloc,
    required PublicModelsBloc publicModelsBloc,
    required this.settingRepository,
    required this.snippetRepository,
  })  : _userId = AppConfig.userId ?? '',
        _aiConfigBloc = aiConfigBloc,
        _publicModelsBloc = publicModelsBloc,
        super(ChatInitial()) {
    _aiConfigSubscription = _aiConfigBloc.stream.listen((aiState) {
      final currentState = state;
      if (currentState is ChatSessionActive) {
        // Find the currently selected model in the new list of configs
        final newSelectedModel = aiState.configs.firstWhereOrNull(
          (config) => config.id == currentState.session.selectedModelConfigId,
        ) ?? aiState.defaultConfig; // Fallback to new default

        if (newSelectedModel != null && newSelectedModel != currentState.selectedModel) {
          add(UpdateChatModel(
            sessionId: currentState.session.id,
            modelConfigId: newSelectedModel.id,
          ));
        }
      }
    });
    AppLogger.i('ChatBloc',
        'Constructor called. Instance hash: ${identityHashCode(this)}');
    on<LoadChatSessions>(_onLoadChatSessions, transformer: restartable());
    on<CreateChatSession>(_onCreateChatSession);
    on<SelectChatSession>(_onSelectChatSession);
    on<SendMessage>(_onSendMessage); // 🚀 临时移除sequential转换器进行调试
    on<LoadMoreMessages>(_onLoadMoreMessages);
    on<UpdateChatTitle>(_onUpdateChatTitle);
    on<ExecuteAction>(_onExecuteAction);
    on<DeleteChatSession>(_onDeleteChatSession);
    on<CancelOngoingRequest>(_onCancelRequest);
    on<UpdateChatContext>(_onUpdateChatContext);
    on<UpdateChatModel>(_onUpdateChatModel);
    on<LoadContextData>(_onLoadContextData);
    on<CacheSettingsData>(_onCacheSettingsData);
    on<CacheSnippetsData>(_onCacheSnippetsData);
    on<UpdateChatConfiguration>(_onUpdateChatConfiguration);
  }
  final ChatRepository repository;
  final AuthService authService;
  final NovelSettingRepository settingRepository;
  final NovelSnippetRepository snippetRepository;
  final String _userId;
  final AiConfigBloc _aiConfigBloc;
  final PublicModelsBloc _publicModelsBloc;

  // 🚀 修改为两层映射：novelId -> sessionId -> config
  final Map<String, Map<String, UniversalAIRequest>> _sessionConfigs = {};

  // 用于跟踪活动的流订阅，以便可以取消它们
  // StreamSubscription? _sessionsSubscription;
  // StreamSubscription? _messagesSubscription;
  // 用于取消正在进行的消息生成请求
  StreamSubscription? _sendMessageSubscription;
  StreamSubscription? _aiConfigSubscription;
  // 标记用户是否请求取消，用于在流式处理过程中提前退出
  bool _cancelRequested = false;
  
  // 临时存储上下文数据，用于在非活动状态时保存加载的数据
  List<dynamic> _tempCachedSettings = [];
  List<dynamic> _tempCachedSettingGroups = [];
  List<dynamic> _tempCachedSnippets = [];

  @override
  Future<void> close() {
    AppLogger.w('ChatBloc',
        'close() method called! Disposing ChatBloc and cancelling subscriptions. Instance hash: ${identityHashCode(this)}');
    // _sessionsSubscription?.cancel();
    // _messagesSubscription?.cancel();
    _sendMessageSubscription?.cancel();
    _aiConfigSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadChatSessions(
      LoadChatSessions event, Emitter<ChatState> emit) async {
    AppLogger.i('ChatBloc',
        '[Event Start] _onLoadChatSessions for novel ${event.novelId}');
    emit(ChatSessionsLoading());

    final List<ChatSession> sessions = []; // 不再需要局部变量
    try {
      // 🚀 传递novelId给repository
      final stream = repository.fetchUserSessions(_userId, novelId: event.novelId);
      // 使用 await emit.forEach 处理流
      await emit.forEach<ChatSession>(
        stream,
        onData: (session) {
          sessions.add(session);
          // 返回当前状态，直到流结束
          emit(ChatSessionsLoading());
          return ChatSessionsLoaded(sessions: List.of(sessions));
          //return state; // 保持 Loading 状态直到完成
        },
        onError: (error, stackTrace) {
          AppLogger.e('ChatBloc', '_onLoadChatSessions stream error', error,
              stackTrace);
          // 在 onError 中直接返回错误状态
          final errorMessage =
              '加载会话列表失败: ${ApiExceptionHelper.fromException(error, "加载会话流出错").message}';
          return ChatSessionsLoaded(sessions: sessions, error: errorMessage);
        },
      );

      AppLogger.i('ChatBloc',
          '[Stream Complete] _onLoadChatSessions collected ${sessions.length} sessions.');

      // 检查 BLoC 是否关闭
      if (!isClosed && !emit.isDone) {
        emit(ChatSessionsLoaded(sessions: sessions));
      } else {
        AppLogger.w('ChatBloc',
            '[Emit Check] BLoC/Emitter closed before emitting final ChatSessionsLoaded.');
      }
      // ---------- 修改结束 ----------
    } catch (e, stackTrace) {
      AppLogger.e(
          'ChatBloc',
          'Failed to load chat sessions (stream error or other)',
          e,
          stackTrace);
      // 检查 BLoC 是否关闭
      if (!isClosed && !emit.isDone) {
        final errorMessage =
            '加载会话列表时发生错误: ${ApiExceptionHelper.fromException(e, "加载会话列表出错").message}';
        // 错误发生时，我们没有部分列表，所以 sessions 参数为空
        emit(ChatSessionsLoaded(
            sessions: const [], error: errorMessage)); // 返回空列表和错误
      }
    } finally {
      // 修改 finally 中的日志级别
      AppLogger.i('ChatBloc',
          '[Event End] _onLoadChatSessions complete.'); // 使用 INFO 级别
    }
  }

  Future<void> _onCreateChatSession(
      CreateChatSession event, Emitter<ChatState> emit) async {
    AppLogger.d('ChatBloc', '[Event Start] _onCreateChatSession');
    if (isClosed) {
      AppLogger.e('ChatBloc', 'Event started but BLoC closed.');
      return;
    }
    try {
      final newSession = await repository.createSession(
        userId: _userId,
        novelId: event.novelId,
        metadata: {
          'title': event.title,
          if (event.chapterId != null) 'chapterId': event.chapterId
        },
      );

      // 优化：如果当前是列表状态，直接更新；否则重新加载
      if (state is ChatSessionsLoaded) {
        final currentState = state as ChatSessionsLoaded;
        final updatedSessions = List<ChatSession>.from(currentState.sessions)
          ..add(newSession);
        // 更新列表，并清除可能存在的错误
        emit(
            currentState.copyWith(sessions: updatedSessions, clearError: true));
        AppLogger.d('ChatBloc', '_onCreateChatSession updated existing list.');
        // 创建后立即选中
        add(SelectChatSession(sessionId: newSession.id, novelId: event.novelId));
      } else {
        // 如果不是列表状态（例如初始状态、错误状态或活动会话状态），触发重新加载
        AppLogger.d(
            'ChatBloc', '_onCreateChatSession triggering LoadChatSessions.');
        add(LoadChatSessions(novelId: event.novelId));
        // 在重新加载后，UI 将自然地显示新会话
        // 如果需要加载后自动选中，需要在 LoadChatSessions 成功后处理
      }

      AppLogger.d('ChatBloc', '[Event End] _onCreateChatSession successful.');
    } catch (e, stackTrace) {
      AppLogger.e('ChatBloc', '[Event Error] _onCreateChatSession failed.', e,
          stackTrace);
      if (!isClosed && !emit.isDone) {
        final errorMessage =
            '创建聊天会话失败: ${ApiExceptionHelper.fromException(e, "创建会话出错").message}';
        // 尝试在当前状态上显示错误
        if (state is ChatSessionsLoaded) {
          emit((state as ChatSessionsLoaded)
              .copyWith(error: errorMessage, clearError: false));
        } else if (state is ChatSessionActive) {
          emit((state as ChatSessionActive)
              .copyWith(error: errorMessage, clearError: false));
        } else {
          emit(ChatError(message: errorMessage));
        }
      }
    }
  }

  Future<void> _onSelectChatSession(
      SelectChatSession event, Emitter<ChatState> emit) async {
    AppLogger.d('ChatBloc',
        '[Event Start] _onSelectChatSession for session ${event.sessionId}');
    if (isClosed) {
      AppLogger.e('ChatBloc', 'Event started but BLoC closed.');
      return;
    }

    // 取消之前的消息订阅和生成请求
    // await _messagesSubscription?.cancel(); // 由 emit.forEach 管理，无需手动取消
    await _sendMessageSubscription?.cancel();
    _sendMessageSubscription = null;

    emit(ChatSessionLoading());
    AppLogger.d('ChatBloc', '_onSelectChatSession emitted ChatSessionLoading');

    try {
      // 1. 获取会话详情 - 🚀 传递novelId参数
      final session = await repository.getSession(_userId, event.sessionId, 
          novelId: event.novelId);
      // 2. 创建默认上下文
      final context = ChatContext(
        novelId: session.novelId ?? event.novelId ?? '',
        chapterId: session.metadata?['chapterId'] as String?,
        relevantItems: const [],
      );
      // 3. 解析选中的模型
      UserAIModelConfigModel? selectedModel;
      final aiState = _aiConfigBloc.state;

      if (aiState.configs.isNotEmpty) {
        if (session.selectedModelConfigId != null) {
          selectedModel = aiState.configs.firstWhereOrNull(
            (config) => config.id == session.selectedModelConfigId,
          );
        }
        selectedModel ??= aiState.defaultConfig;
      } else {
        AppLogger.w('ChatBloc',
            '_onSelectChatSession: AiConfigBloc state does not have configs loaded. Will trigger loading.');
        // 🚀 如果配置未加载，触发加载
        _aiConfigBloc.add(LoadAiConfigs(userId: _userId));
      }

      // 🚀 新增：如果没有可用的私有模型，自动回退到公共模型，避免强制配置私有模型
      if (selectedModel == null) {
        final publicState = _publicModelsBloc.state;
        if (publicState is PublicModelsLoaded && publicState.models.isNotEmpty) {
          // 优先选择 gemini-2.0，其次选择包含 gemini/Google 的模型，否则取优先级最高或第一个
          var target = publicState.models.firstWhereOrNull(
              (m) => m.modelId.toLowerCase() == 'gemini-2.0');
          if (target == null) {
            final candidates = publicState.models.where((m) {
              final p = m.provider.toLowerCase();
              final id = m.modelId.toLowerCase();
              return p.contains('gemini') || p.contains('google') || id.contains('gemini');
            }).toList();
            if (candidates.isNotEmpty) {
              candidates.sort((a, b) => (b.priority ?? 0).compareTo(a.priority ?? 0));
              target = candidates.first;
            }
          }
          target ??= publicState.models.first;

          // 将公共模型映射为临时的用户模型配置（不拼接public_前缀）
          if (target != null) {
            selectedModel = UserAIModelConfigModel.fromJson({
              'id': target.id, // 直接使用公共模型ID，不拼接前缀
              'userId': _userId,
              'alias': target.displayName,
              'modelName': target.modelId,
              'provider': target.provider,
              'apiEndpoint': '',
              'isDefault': false,
              'isValidated': true,
              'createdAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            });
            AppLogger.i('ChatBloc', '未找到私有模型，自动选择公共模型: ${target.displayName} (${target.provider}/${target.modelId})');
          }
        }
      }

      // 4. 🚀 获取或创建会话的AI配置 - 使用两层映射
      UniversalAIRequest chatConfig;
      final novelId = session.novelId ?? event.novelId;
      
      // 首先检查内存中是否已有配置
      if (_sessionConfigs[novelId]?.containsKey(event.sessionId) == true) {
        chatConfig = _sessionConfigs[novelId]![event.sessionId]!;
        AppLogger.i('ChatBloc', '使用内存中的会话配置: novelId=$novelId, sessionId=${event.sessionId}');
      } else {
        // 🚀 从Repository缓存中获取配置（已在getSession时缓存）
        final cachedConfig = ChatRepositoryImpl.getCachedSessionConfig(event.sessionId, novelId: novelId);
        
        if (cachedConfig != null) {
          AppLogger.i('ChatBloc', '从Repository缓存获取会话AI配置成功: novelId=$novelId, sessionId=${event.sessionId}, requestType=${cachedConfig.requestType.value}');
          chatConfig = cachedConfig;
        } else {
          AppLogger.i('ChatBloc', '缓存中无会话AI配置，创建默认配置: novelId=$novelId, sessionId=${event.sessionId}');
          chatConfig = _createDefaultChatConfig(session);
        }
      }
      
      // 🚀 确保配置中包含当前选择的模型（无论是从缓存获取还是新创建的）
      if (selectedModel != null) {
        // 如为公共模型，补充必要的元数据，确保后端走公共模型计费与路由
        Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(chatConfig.metadata);
        final String selId = selectedModel.id;
        
        // 🚀 通过 PublicModelsBloc 检查是否是公共模型（不再依赖前缀判断）
        bool isPublicModel = false;
        final publicState = _publicModelsBloc.state;
        if (publicState is PublicModelsLoaded) {
          isPublicModel = publicState.models.any((m) => m.id == selId);
        }
        
        if (isPublicModel) {
          updatedMeta['isPublicModel'] = true;
          updatedMeta['publicModelId'] = selId;
          updatedMeta['publicModelConfigId'] = selId;
        } else {
          updatedMeta['isPublicModel'] = false;
          updatedMeta.remove('publicModelId');
          updatedMeta.remove('publicModelConfigId');
        }
        chatConfig = chatConfig.copyWith(
          modelConfig: selectedModel,
          metadata: updatedMeta,
        );
        AppLogger.i('ChatBloc', '已将选择的模型设置到会话配置: modelId=${selectedModel.id}, modelName=${selectedModel.modelName}, isPublic=$isPublicModel');
      }
      
      // 将配置存储到两层映射中（无论是从缓存获取还是新创建的）
      if (novelId != null) {
        _sessionConfigs[novelId] ??= {};
        _sessionConfigs[novelId]![event.sessionId] = chatConfig;
        AppLogger.i('ChatBloc', '会话配置已存储到内存映射: novelId=$novelId, sessionId=${event.sessionId}');
      }
      
      // 🚀 添加调试日志，确认配置内容
      AppLogger.d('ChatBloc', '配置详情: contextSelections=${chatConfig.contextSelections != null ? "存在(${chatConfig.contextSelections!.availableItems.length}项)" : "不存在"}, requestType=${chatConfig.requestType.value}');

      // 6. 发出初始 Activity 状态，标记正在加载历史
      emit(ChatSessionActive(
        session: session,
        context: context,
        selectedModel: selectedModel,
        messages: const [], // 初始空列表
        isGenerating: false,
        isLoadingHistory: true, // 标记正在加载历史
        cachedSettings: _tempCachedSettings, // 应用临时保存的设定数据
        cachedSettingGroups: _tempCachedSettingGroups, // 应用临时保存的设定组数据
        cachedSnippets: _tempCachedSnippets, // 应用临时保存的片段数据
        
      ));
      AppLogger.d('ChatBloc',
          '_onSelectChatSession emitted initial ChatSessionActive (loading history)');

      // 5. 使用 await emit.forEach 加载消息历史 - 🚀 传递novelId参数
      final List<ChatMessage> messages = []; // 本地列表用于收集消息
      final messageStream =
          repository.getMessageHistory(_userId, event.sessionId, novelId: novelId);

      AppLogger.d('ChatBloc',
          '_onSelectChatSession starting message history processing...');
      try {
        // Wrap emit.forEach in try-catch for stream-specific errors
        await emit.forEach<ChatMessage>(
          messageStream,
          onData: (message) {
            messages.add(message); // 先收集到本地列表
            // 在加载过程中可以不更新 UI，或者只更新 loading 状态
            return state; // 保持当前状态或 Loading 状态
          },
          onError: (error, stackTrace) {
            AppLogger.e('ChatBloc', 'Error loading message history stream',
                error, stackTrace);
            final currentState = state;
            final errorMessage =
                '加载消息历史失败: ${_formatApiError(error, "加载历史出错")}';
            if (currentState is ChatSessionActive &&
                currentState.session.id == event.sessionId) {
              if (!isClosed && !emit.isDone) {
                return currentState.copyWith(
                  isLoadingHistory: false,
                  error: errorMessage,
                  clearError: false,
                );
              }
            }
            if (!isClosed && !emit.isDone) {
              return ChatError(message: errorMessage);
            }
            return state;
          },
        );

        // ---- emit.forEach 成功完成 ----
        AppLogger.i('ChatBloc',
            '[Callback] _onSelectChatSession message history stream onDone. Collected ${messages.length} messages.');

        // ----------- 添加排序逻辑 -----------
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        AppLogger.d('ChatBloc', 'Messages sorted by timestamp ASC.');
        // ---------------------------------

        // 再次检查 BLoC 和 emitter 状态，并确认当前会话仍然是目标会话
        final finalState = state;
        if (!isClosed &&
            !emit.isDone &&
            finalState is ChatSessionActive &&
            finalState.session.id == event.sessionId) {
          emit(finalState.copyWith(
            messages: messages, // <--- 使用排序后的列表
            isLoadingHistory: false, // 标记历史加载完成
            clearError: true,
          ));
          AppLogger.d('ChatBloc',
              '[History onDone Check] PASSED. Emitted final sorted history.');
        } else {
          AppLogger.w('ChatBloc',
              '[History onDone Check] State changed, BLoC/Emitter closed, or state type mismatch. Ignoring emit.');
        }
      } catch (e, stackTrace) {
        // Catch potential errors from the stream itself or sorting
        AppLogger.e(
            'ChatBloc',
            'Error during message history processing or sorting',
            e,
            stackTrace);
        if (!isClosed && !emit.isDone) {
          final errorMessage = '处理消息历史时出错: ${_formatApiError(e, "处理历史出错")}';
          final currentState = state;
          if (currentState is ChatSessionActive &&
              currentState.session.id == event.sessionId) {
            emit(currentState.copyWith(
                isLoadingHistory: false,
                error: errorMessage,
                clearError: false));
          } else {
            emit(ChatError(message: errorMessage));
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e(
          'ChatBloc',
          '[Event Error] _onSelectChatSession (initial get failed).',
          e,
          stackTrace);
      if (!isClosed && !emit.isDone) {
        final errorMessage = '加载会话失败: ${_formatApiError(e, "加载会话信息出错")}';
        emit(ChatError(message: errorMessage));
      }
    }
    AppLogger.d(
        'ChatBloc', '[Event End Setup] _onSelectChatSession setup complete.');
  }

  Future<void> _onSendMessage(
      SendMessage event, Emitter<ChatState> emit) async {
    AppLogger.i('ChatBloc', '🚀🚀🚀 收到发送消息事件: ${event.content}, BLoC实例: ${identityHashCode(this)}, isClosed: $isClosed');
    
    // 新的发送开始前清除任何残留的取消标志
    _cancelRequested = false;

    if (state is ChatSessionActive) {
      final currentState = state as ChatSessionActive;
      
      // 🚀 添加状态检查，确保不在生成中才能发送新消息
      if (currentState.isGenerating) {
        AppLogger.w('ChatBloc', '正在生成中，忽略新消息发送请求');
        return;
      }

      AppLogger.i('ChatBloc', '开始发送消息到会话: ${currentState.session.id}');
      
      // 🚀 检查是否是第一条消息，如果是则立即更新前端标题
      final isFirstMessage = currentState.messages.where((msg) => msg.role == MessageRole.user).isEmpty;
      if (isFirstMessage) {
        String newTitle;
        if (event.content.length > 10) {
          // 取前10个字符作为标题
          newTitle = event.content.substring(0, 10);
          // 如果截断处不是完整字符，找到最后一个空格位置
          int lastSpace = newTitle.lastIndexOf(' ');
          if (lastSpace > 5) { // 确保至少有5个字符
            newTitle = newTitle.substring(0, lastSpace);
          }
          newTitle = newTitle + "...";
        } else {
          newTitle = event.content;
        }
        
        // 移除换行符和多余的空格
        newTitle = newTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // 如果标题为空，使用默认格式
        if (newTitle.isEmpty) {
          newTitle = "聊天会话 ${DateTime.now().toString().substring(5, 16)}";
        }
        
        AppLogger.i('ChatBloc', '第一条消息，立即更新前端标题: $newTitle');
        
        // 立即更新前端会话标题（不等待后端响应）
        final updatedSession = currentState.session.copyWith(
          title: newTitle,
          lastUpdatedAt: DateTime.now(),
        );
        
        // 先更新状态以显示新标题
        emit(currentState.copyWith(session: updatedSession));
      }
      
      // 🚀 检查并确保会话配置存在
      final novelId = currentState.session.novelId;
      if (novelId != null && _sessionConfigs[novelId]?.containsKey(currentState.session.id) != true) {
        AppLogger.w('ChatBloc', '会话配置不存在，创建默认配置: novelId=$novelId, sessionId=${currentState.session.id}');
        final defaultConfig = _createDefaultChatConfig(currentState.session);
        if (currentState.selectedModel != null) {
          _sessionConfigs[novelId] ??= {};
          _sessionConfigs[novelId]![currentState.session.id] = defaultConfig.copyWith(modelConfig: currentState.selectedModel);
        } else {
          _sessionConfigs[novelId] ??= {};
          _sessionConfigs[novelId]![currentState.session.id] = defaultConfig;
        }
        AppLogger.i('ChatBloc', '已为会话创建默认配置: novelId=$novelId, sessionId=${currentState.session.id}');
      }

      final userMessage = ChatMessage(
        sender: MessageSender.user,
        id: const Uuid().v4(),
        sessionId: currentState.session.id,
        role: MessageRole.user,
        content: event.content,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );

      ChatMessage? placeholderMessage;

      try {
        placeholderMessage = ChatMessage(
          sender: MessageSender.ai,
          id: const Uuid().v4(),
          sessionId: currentState.session.id,
          role: MessageRole.assistant,
          content: '',
          timestamp: DateTime.now(),
          status: MessageStatus.pending,
        );

        AppLogger.i('ChatBloc', '创建占位符消息: ${placeholderMessage.id}');

        // 在发起请求前，先更新UI，添加用户消息和占位符
        emit(currentState.copyWith(
          messages: [...currentState.messages, userMessage, placeholderMessage],
          isGenerating: true,
          error: null, // 清除之前的错误（如果有）
        ));

        AppLogger.i('ChatBloc', '准备调用_handleStreamedResponse');
        
        // 🚀 使用当前的聊天配置发起流式请求
        UniversalAIRequest? chatConfig;
        if (novelId != null) {
          chatConfig = _sessionConfigs[novelId]?[currentState.session.id];
        }
        await _handleStreamedResponse(
            emit, placeholderMessage.id, event.content, chatConfig);
      } catch (e, stackTrace) {
        AppLogger.e('ChatBloc', '发送消息失败 (在调用 _handleStreamedResponse 之前或期间出错)',
            e, stackTrace);
        // 确保在错误发生时也能更新状态
        if (state is ChatSessionActive) {
          final errorState = state as ChatSessionActive;
          final errorMessages = List<ChatMessage>.from(errorState.messages);

          // 如果 placeholder 存在于列表中，标记为错误
          if (placeholderMessage != null) {
            final errorIndex = errorMessages
                .indexWhere((msg) => msg.id == placeholderMessage!.id);
            if (errorIndex != -1) {
              errorMessages[errorIndex] = errorMessages[errorIndex].copyWith(
                content:
                    '生成回复时出错: ${ApiExceptionHelper.fromException(e, "发送消息失败").message}', // 使用辅助方法
                status: MessageStatus.error,
              );
              emit(errorState.copyWith(
                messages: errorMessages,
                isGenerating: false, // 即使出错也要停止生成状态
                error: ApiExceptionHelper.fromException(e, '发送消息失败')
                    .message, // 使用辅助方法
              ));
            } else {
              // 如果 placeholder 不在列表里（理论上不应该发生，除非状态更新逻辑有问题）
              AppLogger.w(
                  'ChatBloc', '未找到ID为 ${placeholderMessage.id} 的占位符消息标记错误');
              emit(errorState.copyWith(
                isGenerating: false,
              ));
            }
          } else {
            // 如果 placeholder 尚未创建就出错
            emit(errorState.copyWith(
              isGenerating: false,
              error: ApiExceptionHelper.fromException(e, '发送消息失败')
                  .message, // 使用辅助方法
            ));
          }
        }
      }
    } else {
      // 🚀 添加明确的日志，说明为什么消息发送被忽略
      AppLogger.w('ChatBloc', '发送消息被忽略，当前状态不是ChatSessionActive: ${state.runtimeType}');
      if (state is ChatSessionsLoaded) {
        AppLogger.i('ChatBloc', '当前在会话列表状态，需要先选择一个会话');
      } else if (state is ChatSessionLoading) {
        AppLogger.i('ChatBloc', '会话正在加载中，请等待加载完成');
      } else if (state is ChatError) {
        AppLogger.i('ChatBloc', '当前处于错误状态，无法发送消息');
      }
    }
  }

  Future<void> _onLoadMoreMessages(
      LoadMoreMessages event, Emitter<ChatState> emit) async {
    // TODO: 实现加载更多历史消息的逻辑
    // 需要修改 repository.getMessageHistory 以支持分页或 "before" 参数
    // 然后将获取到的旧消息插入到当前消息列表的前面
    AppLogger.w('ChatBloc', '_onLoadMoreMessages 尚未实现');
  }

  Future<void> _onUpdateChatTitle(
      UpdateChatTitle event, Emitter<ChatState> emit) async {
    if (state is ChatSessionActive) {
      final currentState = state as ChatSessionActive;

      try {
        final updatedSession = await repository.updateSession(
          userId: _userId,
          sessionId: currentState.session.id,
          updates: {'title': event.newTitle},
          novelId: currentState.session.novelId,
        );

        emit(currentState.copyWith(
          session: updatedSession,
        ));
      } catch (e) {
        emit(currentState.copyWith(
          error: '更新标题失败: ${e.toString()}',
        ));
      }
    }
  }

  Future<void> _onExecuteAction(
      ExecuteAction event, Emitter<ChatState> emit) async {
    if (state is ChatSessionActive) {
      final currentState = state as ChatSessionActive;

      try {
        // 根据操作类型执行不同的动作
        switch (event.action.type) {
          case ActionType.applyToEditor:
            // 应用到编辑器的逻辑
            // 这部分需要与编辑器模块交互，在第二周迭代中可以先简单实现
            break;
          case ActionType.createCharacter:
            // 创建角色的逻辑
            break;
          case ActionType.createLocation:
            // 创建地点的逻辑
            break;
          case ActionType.generatePlot:
            // 生成情节的逻辑
            break;
          case ActionType.expandScene:
            // 扩展场景的逻辑
            break;
          case ActionType.createChapter:
            // 创建章节的逻辑
            break;
          case ActionType.analyzeSentiment:
            // 分析情感的逻辑
            break;
          case ActionType.fixGrammar:
            // 修复语法的逻辑
            break;
        }
      } catch (e) {
        emit(currentState.copyWith(
          error: '执行操作失败: ${e.toString()}',
        ));
      }
    }
  }

  Future<void> _onDeleteChatSession(
      DeleteChatSession event, Emitter<ChatState> emit) async {
    List<ChatSession>? previousSessions;
    if (state is ChatSessionsLoaded) {
      previousSessions = (state as ChatSessionsLoaded).sessions;
    } else if (state is ChatSessionActive) {
      // 如果从活动会话删除，我们可能没有完整的列表状态，但可以尝试保留
      // 这里简化处理，不保留列表
    }

    try {
      // 🚀 获取会话的novelId来删除配置缓存
      String? novelId;
      if (state is ChatSessionActive) {
        final currentState = state as ChatSessionActive;
        if (currentState.session.id == event.sessionId) {
          novelId = currentState.session.novelId;
        }
      }
      
      await repository.deleteSession(_userId, event.sessionId, novelId: novelId);
      
      // 清除本地配置缓存
      if (novelId != null) {
        _sessionConfigs[novelId]?.remove(event.sessionId);
        if (_sessionConfigs[novelId]?.isEmpty == true) {
          _sessionConfigs.remove(novelId);
        }
      }

      // 从状态中移除会话
      if (previousSessions != null) {
        final updatedSessions = previousSessions
            .where((session) => session.id != event.sessionId)
            .toList();
        emit(ChatSessionsLoaded(sessions: updatedSessions));
      } else {
        // 如果之前不是列表状态，或当前活动会话被删除，回到初始状态
        // 让UI决定是否需要重新加载列表
        emit(ChatInitial());
      }
    } catch (e, stackTrace) {
      // 添加 stackTrace
      AppLogger.e('ChatBloc', '删除会话失败', e, stackTrace);
      // 无法在 ChatSessionsLoaded 添加错误，改为发出 ChatError
      // 保留之前的状态可能导致UI不一致
      final errorMessage =
          '删除会话失败: ${ApiExceptionHelper.fromException(e, "删除会话出错").message}';
      // 尝试在当前状态显示错误，如果不行就发 ChatError
      if (state is ChatSessionsLoaded) {
        // 现在可以使用 copyWith 来在 ChatSessionsLoaded 状态下显示错误
        final currentState = state as ChatSessionsLoaded;
        // 在保留现有列表的同时添加错误消息
        emit(currentState.copyWith(error: errorMessage));
      } else if (state is ChatSessionActive) {
        emit((state as ChatSessionActive).copyWith(error: errorMessage));
      } else {
        // 如果是其他状态，发出全局错误
        emit(ChatError(message: errorMessage));
      }
    }
  }

  Future<void> _onCancelRequest(
      CancelOngoingRequest event, Emitter<ChatState> emit) async {
    AppLogger.w('ChatBloc', '收到取消请求，开始清理资源');
    
    // 取消正在进行的流式订阅
    await _sendMessageSubscription?.cancel();
    _sendMessageSubscription = null;

    // 设置取消标志，供 _handleStreamedResponse 检测
    _cancelRequested = true;

    // 确保无论当前状态如何都重置isGenerating
    if (state is ChatSessionActive) {
      final currentState = state as ChatSessionActive;
      AppLogger.w('ChatBloc', '取消请求 - 更新UI状态，确保停止生成状态');

      final latestMessages = List<ChatMessage>.from(currentState.messages);
      final lastPendingIndex = latestMessages.lastIndexWhere((msg) =>
              msg.role == MessageRole.assistant &&
              (msg.status == MessageStatus.pending ||
                  msg.status == MessageStatus.streaming) // 包含 streaming 状态
          );

      if (lastPendingIndex != -1) {
        latestMessages[lastPendingIndex] = latestMessages[lastPendingIndex]
            .copyWith(
          // 保留已生成的内容，不再追加“已取消”标签
          status: MessageStatus.sent, // 将状态从 streaming/pending 置为 sent，表示已结束
        );
      } else {
        // 未找到仍在生成的消息，可能已经结束
        AppLogger.w('ChatBloc', '未找到待取消的streaming/pending消息，可能已结束');
      }
      
      // 🚀 关键修复：无论是否有正在进行的生成，都确保isGenerating设为false，清除错误状态
      emit(currentState.copyWith(
        messages: latestMessages,
        isGenerating: false,
        error: null,
        clearError: true,
      ));
      
      AppLogger.i('ChatBloc', '取消完成，isGenerating已设为false，应该可以发送新消息');
    } else {
      AppLogger.w('ChatBloc', '取消请求时状态不是ChatSessionActive: ${state.runtimeType}');
    }
  }

  Future<void> _onUpdateChatContext(
      UpdateChatContext event, Emitter<ChatState> emit) async {
    if (state is ChatSessionActive) {
      final currentState = state as ChatSessionActive;

      emit(currentState.copyWith(
        context: event.context,
      ));
    }
  }

  // 修改：处理流式响应的辅助方法，接收 placeholderId 和 chatConfig
  // 使用 await emit.forEach 重构
  Future<void> _handleStreamedResponse(
      Emitter<ChatState> emit, String placeholderId, String userContent, UniversalAIRequest? chatConfig) async {
    AppLogger.i('ChatBloc', '_handleStreamedResponse开始执行，placeholderId: $placeholderId');
    
    // --- Initial state check ---
    if (state is! ChatSessionActive) {
      AppLogger.e('ChatBloc',
          '_handleStreamedResponse called while not in ChatSessionActive state');
      // Cannot proceed without active state, emit error if possible
      // Emitter might be closed here already if called incorrectly, so check
      if (!emit.isDone) {
        try {
          emit(const ChatError(message: '内部错误: 无法在非活动会话中处理流'));
        } catch (e) {
          AppLogger.e('ChatBloc', 'Failed to emit error state', e);
        }
      }
      return;
    }
    // Capture initial state specifics
    final initialState = state as ChatSessionActive;
    final currentSessionId = initialState.session.id;
    const initialRole = MessageRole.assistant;

    AppLogger.i('ChatBloc', '当前会话ID: $currentSessionId, 用户消息: $userContent');

    if (_cancelRequested) {
      _cancelRequested = false;
      AppLogger.w('ChatBloc', '_handleStreamedResponse detected residual cancel flag, aborting');
      if (!emit.isDone && state is ChatSessionActive) {
        emit((state as ChatSessionActive).copyWith(isGenerating: false));
      }
      return;
    }

    StringBuffer contentBuffer = StringBuffer();

    try {
      // 🚀 构建用于发送的配置，将用户消息内容填充到 prompt 字段
      UniversalAIRequest? configToSend;
      if (chatConfig != null) {
        // 🚀 优先使用 chatConfig 中的模型（已通过 _onUpdateChatModel 更新）
        // 只有当 chatConfig 中没有模型时才使用 initialState.selectedModel 作为回退
        final modelToUse = chatConfig.modelConfig ?? initialState.selectedModel;
        configToSend = chatConfig.copyWith(
          prompt: userContent, // 将当前用户输入填充到prompt字段
          modelConfig: modelToUse, // 使用配置中的模型或当前选中的模型
        );
        AppLogger.i('ChatBloc', '使用聊天配置: ${configToSend.requestType.value}, 模型: ${modelToUse?.id} (${modelToUse?.modelName})');
      } else {
        AppLogger.i('ChatBloc', '没有聊天配置，使用默认设置');
      }

      AppLogger.i('ChatBloc', '开始调用repository.streamMessage');
      
      final stream = repository.streamMessage(
        userId: _userId,
        sessionId: currentSessionId,
        content: userContent,
        config: configToSend, // 🚀 传递完整的配置
        novelId: initialState.session.novelId, // 🚀 修复：添加缺失的novelId参数
        // Pass configId if needed:
        // configId: initialState.selectedModel?.id,
      );
      
      AppLogger.i('ChatBloc', 'streamMessage调用完成，开始监听流数据');

                // --- Use await emit.forEach ---
      await emit.forEach<ChatMessage>(
        stream,
        onData: (chunk) {
          // --- Per-chunk state validation ---
          // Get the absolute latest state *inside* onData
          final currentState = state;
          // Check if state is still valid *for this operation*
          if (currentState is! ChatSessionActive ||
              currentState.session.id != currentSessionId) {
            AppLogger.w('ChatBloc',
                'emit.forEach onData: State changed during stream processing. Stopping.');
            // Throwing an error here will exit emit.forEach and go to the outer catch block
            throw StateError('Chat session changed during streaming');
          }
          // --- State is valid, proceed ---

          // 🚀 如果途中收到取消请求，停止生成并更新状态
          if (_cancelRequested) {
            AppLogger.w('ChatBloc', 'onData检测到取消请求，停止流式生成并终止流处理');
            
            // 将当前streaming消息标记为已发送
            final latestMessages = List<ChatMessage>.from(currentState.messages);
            final aiMessageIndex = latestMessages.indexWhere((msg) => msg.id == placeholderId);
            
            if (aiMessageIndex != -1) {
              if (contentBuffer.toString().isNotEmpty) {
                latestMessages[aiMessageIndex] = ChatMessage(
                  sender: MessageSender.ai,
                  id: placeholderId,
                  role: initialRole,
                  content: contentBuffer.toString(), // 保留已生成的内容
                  timestamp: DateTime.now(),
                  status: MessageStatus.sent, // 标记为已发送（已停止）
                  sessionId: currentSessionId,
                  userId: _userId,
                  novelId: currentState.session.novelId,
                  metadata: latestMessages[aiMessageIndex].metadata,
                  actions: latestMessages[aiMessageIndex].actions,
                );
              }
              
              // 先emit停止生成的状态
              if (!emit.isDone) {
                emit(currentState.copyWith(
                  messages: latestMessages,
                  isGenerating: false, // 🚀 关键：停止生成状态
                  clearError: true,
                ));
              }
            }
            
            // 重置取消标志并抛出异常终止流处理
            _cancelRequested = false;
            AppLogger.i('ChatBloc', '已取消生成，抛出CancelledException终止流');
            throw Exception('User cancelled streaming');
          }

          // 🚀 如果收到的是完整消息（DELIVERED状态），直接处理为最终消息
          if (chunk.status == MessageStatus.sent || chunk.status == MessageStatus.delivered) {
            AppLogger.i('ChatBloc', '收到完整消息，直接设置为最终状态: messageId=${chunk.id}, status=${chunk.status}');
            
            final latestMessages = List<ChatMessage>.from(currentState.messages);
            final aiMessageIndex = latestMessages.indexWhere((msg) => msg.id == placeholderId);

            if (aiMessageIndex != -1) {
              final finalMessage = ChatMessage(
                sender: MessageSender.ai,
                id: placeholderId, // Keep placeholder ID
                role: initialRole,
                content: chunk.content, // Use complete content from backend
                timestamp: chunk.timestamp ?? DateTime.now(),
                status: MessageStatus.sent, // Final status
                sessionId: currentSessionId,
                userId: _userId,
                novelId: currentState.session.novelId,
                metadata: chunk.metadata ?? latestMessages[aiMessageIndex].metadata,
                actions: chunk.actions ?? latestMessages[aiMessageIndex].actions,
              );
              latestMessages[aiMessageIndex] = finalMessage;

              // 🚀 第一条消息的标题已在前端立即更新，无需检查后端标题
              ChatSession updatedSession = currentState.session;

              // 🚀 对于完整消息，设置isGenerating为false
              return currentState.copyWith(
                messages: latestMessages,
                session: updatedSession,
                isGenerating: false, // Generation complete
                clearError: true,
              );
            } else {
              AppLogger.w('ChatBloc', '_handleStreamedResponse: 未找到ID为 $placeholderId 的占位符进行最终更新');
              throw StateError('Placeholder message lost during streaming');
            }
          } else {
            // 🚀 处理流式块 - 累积内容并更新UI以触发打字机效果
            contentBuffer.write(chunk.content);
            //AppLogger.v('ChatBloc', '累积流式内容: ${chunk.content}, 当前总长度: ${contentBuffer.length}');

            final latestMessages = List<ChatMessage>.from(currentState.messages);
            final aiMessageIndex = latestMessages.indexWhere((msg) => msg.id == placeholderId);

            if (aiMessageIndex != -1) {
              final updatedStreamingMessage = ChatMessage(
                sender: MessageSender.ai,
                id: placeholderId, // Keep placeholder ID
                role: initialRole,
                content: contentBuffer.toString(), // 🚀 使用累积的内容
                timestamp: DateTime.now(),
                status: MessageStatus.streaming, // 🚀 保持streaming状态以触发打字机效果
                sessionId: currentSessionId,
                userId: _userId,
                novelId: currentState.session.novelId,
                metadata: chunk.metadata ?? latestMessages[aiMessageIndex].metadata,
                actions: chunk.actions ?? latestMessages[aiMessageIndex].actions,
              );
              latestMessages[aiMessageIndex] = updatedStreamingMessage;

              // Return the *new state* to be emitted by forEach
              return currentState.copyWith(
                messages: latestMessages,
                isGenerating: true, // Still generating
              );
            } else {
              AppLogger.w('ChatBloc', '_handleStreamedResponse: 未找到ID为 $placeholderId 的占位符进行流式更新');
              // Cannot continue if placeholder lost, throw error to exit
              throw StateError('Placeholder message lost during streaming');
            }
          }
        },
        onError: (error, stackTrace) {
          // This onError is for the *stream itself* having an error
          AppLogger.e(
              'ChatBloc', 'Stream error in emit.forEach', error, stackTrace);
          final currentState = state; // Get state at the time of error
          // 忽略用户主动取消抛出的 CancelledByUser 错误
          if (error is StateError && error.message == 'CancelledByUser') {
            AppLogger.i('ChatBloc', '流被用户取消，忽略错误处理');
            return state;
          }
          final errorMessage = ApiExceptionHelper.fromException(error, '流处理失败').message;
          if (currentState is ChatSessionActive &&
              currentState.session.id == currentSessionId) {
            // Return the error state to be emitted by forEach
            return currentState.copyWith(
              messages: _markPlaceholderAsError(currentState.messages,
                  placeholderId, contentBuffer.toString(), errorMessage),
              isGenerating: false,
              error: errorMessage,
              clearError: false,
            );
          }
          // If state changed before stream error, return a generic error state
          return ChatError(message: errorMessage);
        },
      );

      // ---- Stream finished successfully (await emit.forEach completed without error) ----
      // Get final state AFTER the loop finishes
      final finalState = state;
      if (finalState is ChatSessionActive &&
          finalState.session.id == currentSessionId) {
        final latestMessages = List<ChatMessage>.from(finalState.messages);
        final aiMessageIndex =
            latestMessages.indexWhere((msg) => msg.id == placeholderId);

        if (aiMessageIndex != -1) {
          final finalMessage = ChatMessage(
            sender: MessageSender.ai,
            id: placeholderId, // Keep placeholder ID
            role: initialRole,
            content: contentBuffer.toString(), // Final content
            timestamp: DateTime.now(), // Final timestamp
            status: MessageStatus.sent, // Final status: sent
            sessionId: currentSessionId,
            userId: _userId,
            novelId: finalState.session.novelId,
            // Use latest known metadata/actions before finalizing
            metadata: latestMessages[aiMessageIndex].metadata,
            actions: latestMessages[aiMessageIndex].actions,
          );
          latestMessages[aiMessageIndex] = finalMessage;

          // 🚀 第一条消息的标题已在前端立即更新，无需再次检查后端标题

          // Emit the final state explicitly after the loop
          emit(finalState.copyWith(
            messages: latestMessages,
            isGenerating: false, // Generation complete
            clearError:
                true, // Clear any previous non-fatal errors shown during streaming
          ));
        } else {
          AppLogger.w('ChatBloc',
              '_handleStreamedResponse (onDone): 未找到ID为 $placeholderId 进行最终更新');
          if (finalState.isGenerating) {
            emit(finalState.copyWith(
                isGenerating: false)); // Ensure generating stops
          }
        }
      } else {
        AppLogger.w('ChatBloc',
            'Stream completed, but state changed or invalid. Final update skipped.');
        // If the state changed BUT we were generating, make sure to stop it
        if (state is ChatSessionActive &&
            (state as ChatSessionActive).isGenerating) {
          emit((state as ChatSessionActive).copyWith(isGenerating: false));
        } else if (state is! ChatSessionActive) {
          // This case is tricky, maybe emit ChatError or just log
          AppLogger.e('ChatBloc',
              'Stream completed, state is not Active, but maybe was generating? State: ${state.runtimeType}');
        }
      }
    } catch (error, stackTrace) {
      // Catches errors from:
      // - Initial repository.streamMessage call
      // - Errors re-thrown from the stream's `onError` that emit.forEach catches
      // - The StateErrors thrown in `onData` if state changes or placeholder is lost
      // - 🚀 User cancellation exceptions
      
      // 🚀 检查是否为用户取消操作
      final isCancellation = error.toString().contains('User cancelled streaming');
      
      if (isCancellation) {
        AppLogger.i('ChatBloc', '流处理因用户取消而终止（正常）');
        // 用户取消不是错误，不需要emit错误状态
        // 状态已经在onData中更新为isGenerating=false
        return;
      }
      
      AppLogger.e(
          'ChatBloc',
          'Error during _handleStreamedResponse processing loop',
          error,
          stackTrace);
      // Check emitter status *before* attempting to emit
      if (!emit.isDone) {
        final currentState = state; // Get state at the time of catch
        final errorMessage = (error is StateError)
            ? '内部错误: ${error.message}' // Keep StateError messages distinct
            : ApiExceptionHelper.fromException(error, '处理流响应失败').message;

        if (currentState is ChatSessionActive &&
            currentState.session.id == currentSessionId) {
          // Attempt to emit the error state for the correct session
          emit(currentState.copyWith(
            messages: _markPlaceholderAsError(currentState.messages,
                placeholderId, contentBuffer.toString(), errorMessage),
            isGenerating: false, // Stop generation on error
            error: errorMessage,
            clearError: false,
          ));
        } else {
          // If state changed before catch, emit generic error
          AppLogger.w('ChatBloc',
              'Caught error, but state changed. Emitting generic ChatError.');
          emit(ChatError(message: errorMessage));
        }
      } else {
        AppLogger.w('ChatBloc',
            'Caught error, but emitter is done. Cannot emit error state.');
      }
    } finally {
      // No explicit subscription cleanup needed with emit.forEach
      AppLogger.d('ChatBloc',
          '_handleStreamedResponse finished processing for placeholder $placeholderId');
      // Ensure `isGenerating` is false if the process ends unexpectedly without explicit state update
      // This is a safety net.
      if (state is ChatSessionActive &&
          (state as ChatSessionActive).isGenerating &&
          (state as ChatSessionActive).session.id == currentSessionId) {
        AppLogger.w('ChatBloc',
            '_handleStreamedResponse finally: State still shows isGenerating. Forcing to false.');
        if (!emit.isDone) {
          emit((state as ChatSessionActive).copyWith(isGenerating: false));
        }
      }
      // 流处理结束后重置取消标志
      _cancelRequested = false;
    }
  }

  // 辅助方法: 将占位符消息标记为错误 (确保使用 MessageStatus.error)
  List<ChatMessage> _markPlaceholderAsError(List<ChatMessage> messages,
      String placeholderId, String bufferedContent, String errorMessage) {
    final listCopy = List<ChatMessage>.from(messages);
    final errorIndex = listCopy.indexWhere((msg) => msg.id == placeholderId);
    if (errorIndex != -1) {
      final existingMessage = listCopy[errorIndex];
      listCopy[errorIndex] = existingMessage.copyWith(
        content: bufferedContent.isNotEmpty
            ? '$bufferedContent\n\n[错误: $errorMessage]'
            : '[错误: $errorMessage]',
        status: MessageStatus.error, // Mark as error
        timestamp: DateTime.now(), // Update timestamp
      );
    } else {
      AppLogger.w('ChatBloc',
          '_markPlaceholderAsError: 未找到ID为 $placeholderId 的占位符标记错误');
    }
    return listCopy;
  }

  Future<void> _onUpdateChatModel(
      UpdateChatModel event, Emitter<ChatState> emit) async {
    final currentState = state;
    if (currentState is ChatSessionActive &&
        currentState.session.id == event.sessionId) {
      UserAIModelConfigModel? newSelectedModel;
      final aiState = _aiConfigBloc.state;

      // 1. 先在 AiConfigBloc 中查找私有模型
      if (aiState.configs.isNotEmpty) {
        newSelectedModel = aiState.configs.firstWhereOrNull(
          (config) => config.id == event.modelConfigId,
        );
      }

      // 2. 如果在私有模型中没找到，检查是否是公共模型
      if (newSelectedModel == null) {
        // 🚀 尝试从PublicModelsBloc中查找公共模型
        final publicState = _publicModelsBloc.state;
        
        if (publicState is PublicModelsLoaded) {
          // 检查是否是public_前缀的ID（临时配置ID）或直接的公共模型ID
          String targetPublicModelId = event.modelConfigId;
          if (targetPublicModelId.startsWith('public_')) {
            targetPublicModelId = targetPublicModelId.substring('public_'.length);
          }
          
          final publicModel = publicState.models.firstWhereOrNull(
            (model) => model.id == targetPublicModelId,
          );
          
          if (publicModel != null) {
            // 🚀 为公共模型创建临时的UserAIModelConfigModel（不拼接public_前缀）
            newSelectedModel = UserAIModelConfigModel.fromJson({
              'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
              'userId': _userId,
              'alias': publicModel.displayName,
              'modelName': publicModel.modelId,
              'provider': publicModel.provider,
              'apiEndpoint': '', // 公共模型没有单独的apiEndpoint
              'isDefault': false,
              'isValidated': true,
              'createdAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            });
            
            AppLogger.i('ChatBloc',
                '_onUpdateChatModel: 找到公共模型并创建临时配置 - publicModelId: ${publicModel.id}, displayName: ${publicModel.displayName}');
          }
        }
      }

      if (newSelectedModel == null) {
        // 添加日志记录找不到模型的具体ID
        AppLogger.w('ChatBloc',
            '_onUpdateChatModel: Model config with ID ${event.modelConfigId} not found in both AiConfigBloc and PublicModelsBloc.');
        // --- 添加这行日志来查看当前状态 ---
        AppLogger.d('ChatBloc',
            'Current AiConfigState: Status=${aiState.status}, Config IDs=[${aiState.configs.map((c) => c.id).join(', ')}], DefaultConfig ID=${aiState.defaultConfig?.id}');
        
        final publicState = _publicModelsBloc.state;
        if (publicState is PublicModelsLoaded) {
          AppLogger.d('ChatBloc',
              'Current PublicModelsState: Public Model IDs=[${publicState.models.map((m) => m.id).join(', ')}]');
        } else {
          AppLogger.d('ChatBloc', 'PublicModelsState: ${publicState.runtimeType}');
        }
        // --------------------------------------------------
        emit(currentState.copyWith(error: '选择的模型配置未找到或未加载', clearError: false));
        return;
      }

      // 🚀 仅更新前端状态和内存配置，不立即发送后端请求
      // 模型配置会在下次发送消息时通过 config 参数传递给后端
      
      // 1. Update the session object in the state (仅本地状态)
      final updatedSession = currentState.session.copyWith(
        selectedModelConfigId: event.modelConfigId,
        lastUpdatedAt: DateTime.now(),
      );

      // 2. 🚀 更新会话配置中的模型信息和元数据
      final novelId = currentState.session.novelId;
      if (novelId != null) {
        final currentConfig = _sessionConfigs[novelId]?[event.sessionId];
        if (currentConfig != null) {
          // 更新模型配置
          Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(currentConfig.metadata);
          final String selId = newSelectedModel.id;
          
          // 🚀 通过 PublicModelsBloc 检查是否是公共模型
          bool isPublicModel = false;
          final publicState = _publicModelsBloc.state;
          if (publicState is PublicModelsLoaded) {
            isPublicModel = publicState.models.any((m) => m.id == selId);
          }
          
          // 更新元数据中的公共模型标记
          if (isPublicModel) {
            updatedMeta['isPublicModel'] = true;
            updatedMeta['publicModelId'] = selId;
            updatedMeta['publicModelConfigId'] = selId;
          } else {
            updatedMeta['isPublicModel'] = false;
            updatedMeta.remove('publicModelId');
            updatedMeta.remove('publicModelConfigId');
          }
          
          final updatedConfig = currentConfig.copyWith(
            modelConfig: newSelectedModel,
            metadata: updatedMeta,
          );
          _sessionConfigs[novelId] ??= {};
          _sessionConfigs[novelId]![event.sessionId] = updatedConfig;
          AppLogger.i('ChatBloc', '已更新会话配置中的模型和元数据: novelId=$novelId, sessionId=${event.sessionId}, modelId=${newSelectedModel.id}, isPublic=$isPublicModel');
        } else {
          // 如果配置不存在，创建一个新的默认配置
          AppLogger.w('ChatBloc', '会话配置不存在，创建新配置并设置模型: novelId=$novelId, sessionId=${event.sessionId}');
          final defaultConfig = _createDefaultChatConfig(currentState.session);
          
          // 设置模型和元数据
          Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(defaultConfig.metadata);
          final String selId = newSelectedModel.id;
          
          // 检查是否是公共模型
          bool isPublicModel = false;
          final publicState = _publicModelsBloc.state;
          if (publicState is PublicModelsLoaded) {
            isPublicModel = publicState.models.any((m) => m.id == selId);
          }
          
          if (isPublicModel) {
            updatedMeta['isPublicModel'] = true;
            updatedMeta['publicModelId'] = selId;
            updatedMeta['publicModelConfigId'] = selId;
          } else {
            updatedMeta['isPublicModel'] = false;
          }
          
          final configWithModel = defaultConfig.copyWith(
            modelConfig: newSelectedModel,
            metadata: updatedMeta,
          );
          _sessionConfigs[novelId] ??= {};
          _sessionConfigs[novelId]![event.sessionId] = configWithModel;
          AppLogger.i('ChatBloc', '已创建新配置并设置模型: novelId=$novelId, sessionId=${event.sessionId}, modelId=${newSelectedModel.id}, isPublic=$isPublicModel');
        }
      }

      // 3. Emit the new state with updated session and selectedModel
      emit(currentState.copyWith(
        session: updatedSession,
        selectedModel: newSelectedModel,
        clearError: true,
        configUpdateTimestamp: DateTime.now(), // 🚀 触发UI重建
      ));
      AppLogger.i('ChatBloc',
          '_onUpdateChatModel successful for session ${event.sessionId}, new model ${event.modelConfigId} (本地更新，不发送后端请求)');

    } else {
      AppLogger.w('ChatBloc',
          '_onUpdateChatModel called with non-matching state or session ID.');
    }
  }

  // 添加一个辅助方法来格式化错误（如果 ApiExceptionHelper 不可用）
  String _formatApiError(Object error, [String defaultPrefix = '操作失败']) {
    return '$defaultPrefix: ${error.toString()}';
  }

  /// 加载上下文数据（设定和片段）
  Future<void> _onLoadContextData(
    LoadContextData event, 
    Emitter<ChatState> emit
  ) async {
    try {
      AppLogger.i('ChatBloc', '开始加载上下文数据，当前状态: ${state.runtimeType}');
      
      // 并行加载设定和片段数据
      final futures = await Future.wait([
        _loadSettingsData(event.novelId),
        _loadSnippetsData(event.novelId),
      ]);
      
      final settingsData = futures[0] as Map<String, dynamic>;
      final snippetsData = futures[1] as List<NovelSnippet>;
      
      AppLogger.i('ChatBloc', '上下文数据加载完成: ${settingsData['settings'].length} 设定, ${settingsData['groups'].length} 组, ${snippetsData.length} 片段');
      
      // 如果当前状态是ChatSessionActive，更新缓存数据
      final currentState = state;
      if (currentState is ChatSessionActive) {
        emit(currentState.copyWith(
          cachedSettings: settingsData['settings'],
          cachedSettingGroups: settingsData['groups'],
          cachedSnippets: snippetsData,
          isLoadingContextData: false,
        ));
      } else {
        // 如果不是活动状态，将数据保存到临时变量中
        _tempCachedSettings = settingsData['settings'];
        _tempCachedSettingGroups = settingsData['groups'];
        _tempCachedSnippets = snippetsData;
        AppLogger.i('ChatBloc', '当前状态非ChatSessionActive，上下文数据已保存到临时变量');
      }
    } catch (e, stackTrace) {
      AppLogger.e('ChatBloc', '加载上下文数据失败', e, stackTrace);
      
      final currentState = state;
      if (currentState is ChatSessionActive) {
        emit(currentState.copyWith(
          isLoadingContextData: false,
          error: '加载上下文数据失败: ${e.toString()}',
        ));
      }
    }
  }

  /// 缓存设定数据
  Future<void> _onCacheSettingsData(
    CacheSettingsData event,
    Emitter<ChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is ChatSessionActive) {
      emit(currentState.copyWith(
        cachedSettings: event.settings,
        cachedSettingGroups: event.settingGroups,
      ));
    }
  }

  /// 缓存片段数据
  Future<void> _onCacheSnippetsData(
    CacheSnippetsData event,
    Emitter<ChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is ChatSessionActive) {
      emit(currentState.copyWith(
        cachedSnippets: event.snippets,
      ));
    }
  }

  /// 加载设定数据
  Future<Map<String, dynamic>> _loadSettingsData(String novelId) async {
    try {
      final futures = await Future.wait([
        settingRepository.getNovelSettingItems(
          novelId: novelId,
          page: 0,
          size: 100, // 限制数量避免过多数据
          sortBy: 'createdAt',
          sortDirection: 'desc',
        ),
        settingRepository.getNovelSettingGroups(novelId: novelId),
      ]);
      
      return {
        'settings': futures[0] as List<NovelSettingItem>,
        'groups': futures[1] as List<SettingGroup>,
      };
    } catch (e) {
      AppLogger.e('ChatBloc', '加载设定数据失败', e);
      return {
        'settings': <NovelSettingItem>[],
        'groups': <SettingGroup>[],
      };
    }
  }

  /// 加载片段数据
  Future<List<NovelSnippet>> _loadSnippetsData(String novelId) async {
    try {
      final result = await snippetRepository.getSnippetsByNovelId(
        novelId,
        page: 0,
        size: 50, // 限制数量避免过多数据
      );
      return result.content;
    } catch (e) {
      AppLogger.e('ChatBloc', '加载片段数据失败', e);
      return <NovelSnippet>[];
    }
  }

  /// 🚀 更新聊天配置
  Future<void> _onUpdateChatConfiguration(
      UpdateChatConfiguration event, Emitter<ChatState> emit) async {
    AppLogger.d('ChatBloc',
        '[Event Start] _onUpdateChatConfiguration for session ${event.sessionId}');
    
    final currentState = state;
    if (currentState is ChatSessionActive &&
        currentState.session.id == event.sessionId) {
      
              try {
          // 🚀 更新内存映射中的配置
          final novelId = currentState.session.novelId ?? event.config.novelId;
          if (novelId != null) {
            _sessionConfigs[novelId] ??= {};
            _sessionConfigs[novelId]![event.sessionId] = event.config;
          
          // 🚀 同时更新Repository缓存中的配置
          ChatRepositoryImpl.cacheSessionConfig(event.sessionId, event.config, novelId: novelId);
          
          // 配置已更新到内存映射，发出状态变更通知UI重建
          emit(currentState.copyWith(
            clearError: true,
            configUpdateTimestamp: DateTime.now(), // 🚀 添加时间戳确保状态变化
          ));
          
          AppLogger.i('ChatBloc',
              '_onUpdateChatConfiguration successful for session ${event.sessionId}');
          AppLogger.d('ChatBloc', 
              'Updated config - Instructions: ${event.config.instructions?.isNotEmpty == true ? "有" : "无"}, '
              'Context selections: ${event.config.contextSelections?.selectedCount ?? 0}, '
              'Smart context: ${event.config.enableSmartContext}');
        } else {
          AppLogger.w('ChatBloc', '无法更新配置：缺少novelId信息');
          emit(currentState.copyWith(
            error: '更新聊天配置失败: 缺少小说ID信息',
            clearError: false,
          ));
        }
            
      } catch (e, stackTrace) {
        AppLogger.e('ChatBloc',
            '_onUpdateChatConfiguration failed', e, stackTrace);
        emit(currentState.copyWith(
          error: '更新聊天配置失败: ${_formatApiError(e, "更新配置失败")}',
          clearError: false,
        ));
      }
    } else {
      AppLogger.w('ChatBloc',
          '_onUpdateChatConfiguration called with non-matching state or session ID. '
          'Current state: ${currentState.runtimeType}, '
          'Current session: ${currentState is ChatSessionActive ? currentState.session.id : "N/A"}, '
          'Target session: ${event.sessionId}');
    }
  }

  /// 🚀 获取会话配置（添加novelId校验）
  UniversalAIRequest? getSessionConfig(String sessionId, String novelId) {
    final config = _sessionConfigs[novelId]?[sessionId];
    
    // 🚀 新增：检查配置是否属于当前小说
    if (config != null && config.novelId != null && config.novelId != novelId) {
      AppLogger.w('ChatBloc', '🚨 getSessionConfig($sessionId): 配置存在但不属于当前小说(配置小说ID: ${config.novelId}, 请求小说ID: $novelId)');
      return null;
    }
    
    AppLogger.d('ChatBloc', '🔍 getSessionConfig($sessionId, $novelId): 配置${config != null ? "存在且匹配" : "不存在"}, contextSelections=${config?.contextSelections != null ? "存在(可用${config!.contextSelections!.availableItems.length}项,已选${config.contextSelections!.selectedCount}项)" : "不存在"}');
    return config;
  }

  /// 🚀 构建上下文选择数据
  ContextSelectionData? _buildContextSelectionData(ChatSession session) {
    if (session.novelId == null) return null;
    
    // 从EditorBloc获取Novel数据
    final editorState = _aiConfigBloc.state; // 这里需要访问EditorBloc，但我们没有直接引用
    // 暂时先不创建，让UI层根据state中的缓存数据来构建。
    // 这样可以避免一个空的ContextSelectionData覆盖掉由UI异步构建的真实数据。
    return null;
    /*
    return ContextSelectionData(
      novelId: session.novelId,
      availableItems: [],
      flatItems: {},
    );
    */
  }

  /// 🚀 创建默认的聊天配置
  UniversalAIRequest _createDefaultChatConfig(ChatSession session) {
    // 构建上下文选择数据
    final contextSelectionData = _buildContextSelectionData(session);
    
    return UniversalAIRequest(
      requestType: AIRequestType.chat,
      userId: _userId,
      sessionId: session.id,
      novelId: session.novelId,
      modelConfig: null, // 将在后续根据selectedModel更新
      prompt: null, // 将在发送消息时填充
      instructions: null, // 默认无额外指令
      selectedText: null, // 聊天不涉及选中文本
      contextSelections: contextSelectionData,
      enableSmartContext: true, // 默认启用智能上下文
      parameters: {
        'temperature': 0.7,
        'maxTokens': 4000,
        'memoryCutoff': 14, // 默认记忆截断
      },
      metadata: {
        'action': 'chat',
        'source': 'session_init',
        'sessionId': session.id,
      },
    );
  }

  /// 🚀 检查并更新会话标题
  void _checkAndUpdateSessionTitle(String sessionId) {
    // 异步执行，不阻塞主流程
    Timer(const Duration(milliseconds: 500), () async {
      try {
        AppLogger.i('ChatBloc', '异步检查会话标题更新: sessionId=$sessionId');
        // 🚀 这里需要从当前状态获取novelId
        String? novelId;
        if (state is ChatSessionActive) {
          final currentState = state as ChatSessionActive;
          if (currentState.session.id == sessionId) {
            novelId = currentState.session.novelId;
          }
        }
        final updatedSession = await repository.getSession(_userId, sessionId, novelId: novelId);
        
        if (state is ChatSessionActive) {
          final currentState = state as ChatSessionActive;
          if (currentState.session.id == sessionId && 
              currentState.session.title != updatedSession.title) {
            AppLogger.i('ChatBloc', '会话标题已更新: ${currentState.session.title} -> ${updatedSession.title}');
            add(UpdateChatTitle(newTitle: updatedSession.title));
          }
        }
      } catch (e) {
        AppLogger.w('ChatBloc', '检查会话标题更新失败: $e');
      }
    });
  }
}
