import 'dart:async';
import 'dart:convert';

import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/base/api_exception.dart';

import 'package:ainoval/services/local_storage_service.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 数据同步服务
///
/// 负责在本地数据和远程API之间同步数据，支持离线模式和冲突解决
class SyncService {
  SyncService({
    required this.apiService,
    required this.localStorageService,
  });

  final ApiClient apiService;
  final LocalStorageService localStorageService;

  // 同步状态流
  final _syncStateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _syncStateController.stream;

  // 当前同步状态
  SyncState _currentState = SyncState.idle();
  SyncState get currentState => _currentState;

  // 网络连接监听器
  StreamSubscription? _connectivitySubscription;

  // 自动同步定时器
  Timer? _autoSyncTimer;
  
  // 服务是否已关闭
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  /// 初始化同步服务
  Future<void> init() async {
    AppLogger.i('SyncService', '初始化同步服务');

    // 监听网络连接状态
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      final isOnline = result != ConnectivityResult.none;
      AppLogger.d('SyncService', '网络连接状态变化: ${isOnline ? "在线" : "离线"}');
      _handleConnectivityChange(isOnline);
    });

    // 检查当前网络状态
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult != ConnectivityResult.none;
    AppLogger.d('SyncService', '当前网络状态: ${isOnline ? "在线" : "离线"}');
    _updateSyncState(isOnline: isOnline);

    // 设置自动同步定时器
    _setupAutoSync();
  }

  /// 设置自动同步
  void _setupAutoSync() {
    AppLogger.i('SyncService', '设置自动同步定时器，每10分钟同步一次');
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (_currentState.isOnline) {
        // 检查当前小说ID是否设置
        final currentNovelId = await localStorageService.getCurrentNovelId();
        if (currentNovelId == null) {
          AppLogger.w('SyncService', '自动同步触发，但无当前小说ID，跳过');
          return;
        }

        // 仅在存在待同步项时触发同步
        final hasPending = await _hasAnyPendingSyncForCurrentNovel(currentNovelId);
        if (!hasPending) {
          AppLogger.i('SyncService', '自动同步触发，但无待同步内容，跳过');
          return;
        }

        AppLogger.d('SyncService', '自动同步触发，当前小说ID: $currentNovelId，存在待同步内容，开始同步');
        syncAll();
      }
    });
  }

  /// 处理网络连接变化
  void _handleConnectivityChange(bool isOnline) {
    // Store the previous online state before updating
    final wasOffline = !_currentState.isOnline;
    _updateSyncState(isOnline: isOnline);

    // Trigger sync only when coming back online
    if (isOnline && wasOffline) {
      // 检查当前小说ID是否设置后再同步
      localStorageService.getCurrentNovelId().then((currentNovelId) async {
        if (currentNovelId != null) {
          final hasPending = await _hasAnyPendingSyncForCurrentNovel(currentNovelId);
          if (hasPending) {
            AppLogger.i('SyncService', '网络恢复，检测到待同步内容，开始同步。当前小说ID: $currentNovelId');
            syncAll(); // syncAll will now also handle pending messages
          } else {
            AppLogger.i('SyncService', '网络恢复，但无待同步内容，跳过同步');
          }
        } else {
          AppLogger.w('SyncService', '网络恢复，但无当前小说ID，不执行自动同步');
        }
      });
    }
  }

  /// 检查当前小说是否存在任何待同步项（小说/场景/编辑器/聊天会话/待发送消息）
  Future<bool> _hasAnyPendingSyncForCurrentNovel(String currentNovelId) async {
    try {
      // novel 级同步
      final novelSyncList = await localStorageService.getSyncList('novel');
      if (novelSyncList.contains(currentNovelId)) return true;

      // scene 级同步（键格式: novelId_actId_chapterId_sceneId）
      final sceneSyncList = await localStorageService.getSyncList('scene');
      final hasScenePending = sceneSyncList.any((sceneKey) {
        final parts = sceneKey.split('_');
        return parts.length == 4 && parts[0] == currentNovelId;
      });
      if (hasScenePending) return true;

      // editor 级同步（键格式: novelId_chapterId 或兼容旧格式）
      final editorSyncList = await localStorageService.getSyncList('editor');
      final hasEditorPending = editorSyncList.any((contentKey) {
        final parts = contentKey.split('_');
        return parts.isNotEmpty && parts[0] == currentNovelId;
      });
      if (hasEditorPending) return true;

      // 聊天会话元数据（需要过滤 novelId）
      final chatSessionsToSync = await localStorageService.getSessionsToSync();
      final hasChatPending = chatSessionsToSync.any((session) {
        final metadata = (session as dynamic).metadata as Map<String, dynamic>?;
        return metadata != null && metadata['novelId'] == currentNovelId;
      });
      if (hasChatPending) return true;

      // 待发送消息（过滤 novelId）
      final pendingMessages = await localStorageService.getPendingMessages();
      final hasPendingMessages = pendingMessages.any((msg) {
        final metadata = msg['metadata'] as Map<String, dynamic>?;
        return metadata != null && metadata['novelId'] == currentNovelId;
      });
      if (hasPendingMessages) return true;

      return false;
    } catch (e, st) {
      AppLogger.e('SyncService', '检测待同步项时出错', e, st);
      // 出错时保守起见返回 true，避免错过同步
      return true;
    }
  }

  /// 更新同步状态
  void _updateSyncState({
    bool? isOnline,
    bool? isSyncing,
    String? error,
    double? progress,
  }) {
    // 如果服务已关闭，则不更新状态
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，忽略状态更新');
      return;
    }
    
    _currentState = SyncState(
      isOnline: isOnline ?? _currentState.isOnline,
      isSyncing: isSyncing ?? _currentState.isSyncing,
      error: error,
      progress: progress ?? _currentState.progress,
    );

    _syncStateController.add(_currentState);
    AppLogger.v('SyncService', '同步状态更新: $_currentState');
  }

  /// 同步所有数据
  Future<bool> syncAll() async {
    // 如果服务已关闭，直接返回
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，无法执行同步');
      return false;
    }
    
    if (_currentState.isSyncing) {
      AppLogger.w('SyncService', '同步已在进行中，跳过本次同步');
      return false;
    }

    if (!_currentState.isOnline) {
      AppLogger.w('SyncService', '无网络连接，无法同步');
      _updateSyncState(error: '无网络连接，无法同步');
      return false;
    }

    try {
      AppLogger.i('SyncService', '开始全量数据同步');
      _updateSyncState(
          isSyncing: true, progress: 0.0, error: null); // Clear previous error

      // --- Sync Pending Messages First ---
      AppLogger.d('SyncService', '开始同步待发送消息');
      await _syncPendingMessages();
      _updateSyncState(progress: 0.1); // Adjust progress steps

      // --- Sync other data types ---
      AppLogger.d('SyncService', '开始同步小说数据');
      await _syncNovels();
      _updateSyncState(progress: 0.3);

      AppLogger.d('SyncService', '开始同步场景内容');
      await _syncScenes();
      _updateSyncState(progress: 0.5);

      AppLogger.d('SyncService', '开始同步编辑器内容');
      await _syncEditorContents();
      _updateSyncState(progress: 0.7);

      // Sync Chat Session METADATA (title, etc.)
      AppLogger.d('SyncService', '开始同步聊天会话元数据');
      await _syncChatSessions(); // This now only syncs metadata
      _updateSyncState(progress: 0.9); // Example progress

      // --- Final step, maybe sync user profile or other settings ---
      _updateSyncState(progress: 1.0); // Example finish

      AppLogger.i('SyncService', '全量数据同步完成');
      _updateSyncState(isSyncing: false, error: null); // Clear error on success
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('SyncService', '同步失败', e, stackTrace);
      // Preserve isOnline state, set error
      _updateSyncState(isSyncing: false, error: '同步失败: $e');
      return false;
    }
  }

  /// 同步小说数据
  Future<void> _syncNovels() async {
    try {
      // 获取当前正在编辑的小说ID
      final currentNovelId = await localStorageService.getCurrentNovelId();
      if (currentNovelId == null) {
        AppLogger.w('SyncService', '无当前小说ID，跳过小说同步');
        return;
      }

      final syncList = await localStorageService.getSyncList('novel');
      AppLogger.d('SyncService', '需要同步的小说数量: ${syncList.length}');

      // 筛选出当前小说
      final novelIdsToSync = syncList.where((novelId) => novelId == currentNovelId).toList();
      AppLogger.d('SyncService', '当前小说需要同步: ${novelIdsToSync.length} (当前小说ID: $currentNovelId)');
      
      if (novelIdsToSync.isEmpty) {
        AppLogger.i('SyncService', '当前小说不需要同步，跳过');
        return;
      }

      for (final novelId in novelIdsToSync) {
        final localNovel = await localStorageService.getNovel(novelId);
        if (localNovel == null) {
          AppLogger.w('SyncService', '本地小说不存在: $novelId');
          continue;
        }

        AppLogger.i('SyncService', '同步小说: ${localNovel.title}($novelId)');
        
        // 构建后端所需的小说数据结构
        final backendNovelJson = {
          'id': localNovel.id,
          'title': localNovel.title,
          'coverImage': localNovel.coverUrl,
          // 确保包含作者信息
          'author': localNovel.author?.toJson() ??
              {
                'id': AppConfig.userId ?? '',
                'username': AppConfig.username ?? 'user'
              },
          'lastEditedChapterId': localNovel.lastEditedChapterId,
          'createdAt': localNovel.createdAt.toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'structure': {
            'acts': localNovel.acts
                .map((act) => {
                      'id': act.id,
                      'title': act.title,
                      'order': act.order,
                      'chapters': act.chapters
                          .map((chapter) => {
                                'id': chapter.id,
                                'title': chapter.title,
                                'order': chapter.order,
                                // 注意：章节中只需包含ID，场景内容通过scenesByChapter单独提供
                                'sceneIds': chapter.scenes.map((scene) => scene.id).toList(),
                              })
                          .toList(),
                    })
                .toList(),
          },
        };

        // 仅同步小说元数据/结构，避免一次性上传场景大包
        await apiService.updateNovel(backendNovelJson);

        await localStorageService.clearSyncFlagByType('novel', novelId);
        AppLogger.d('SyncService', '小说同步完成: $novelId');
      }
    } catch (e, stackTrace) {
      AppLogger.e('SyncService', '同步小说数据失败', e, stackTrace);
      throw SyncException('同步小说数据失败: $e');
    }
  }

  /// 同步场景内容
  Future<void> _syncScenes() async {
    try {
      // 获取当前正在编辑的小说ID
      final currentNovelId = await localStorageService.getCurrentNovelId();
      if (currentNovelId == null) {
        AppLogger.w('SyncService', '无当前小说ID，跳过场景同步');
        return;
      }

      final syncList = await localStorageService.getSyncList('scene');
      AppLogger.d('SyncService', '需要同步的场景数量: ${syncList.length}');

      // 按章节分组：key = novelId_actId_chapterId, value = List<sceneKey>
      final Map<String, List<String>> chapterGroups = {};
      for (final sceneKey in syncList) {
        final parts = sceneKey.split('_');
        if (parts.length == 4 && parts[0] == currentNovelId) {
          final chapterKey = '${parts[0]}_${parts[1]}_${parts[2]}';
          (chapterGroups[chapterKey] ??= []).add(sceneKey);
        }
      }

      if (chapterGroups.isEmpty) {
        AppLogger.i('SyncService', '当前小说没有场景需要同步，跳过');
        return;
      }

      const int maxScenesPerBatch = 15; // 每批最多场景数
      const int maxBatchBytes = 800 * 1024; // 每批最大字节数 ~800KB

      for (final entry in chapterGroups.entries) {
        final chapterKey = entry.key; // novelId_actId_chapterId
        final sceneKeys = entry.value;
        final parts = chapterKey.split('_');
        final novelId = parts[0];
        final actId = parts[1];
        final chapterId = parts[2];

        AppLogger.i('SyncService', '开始按章节分批同步场景: novelId=$novelId, actId=$actId, chapterId=$chapterId, 场景数=${sceneKeys.length}');

        // 准备所有场景的数据对象
        final List<Map<String, dynamic>> allScenePayloads = [];
        final Map<String, String> sceneKeyById = {};

        for (final sceneKey in sceneKeys) {
          final keyParts = sceneKey.split('_');
          final sceneId = keyParts[3];
          final localScene = await localStorageService.getSceneContent(novelId, actId, chapterId, sceneId);
          if (localScene == null) {
            AppLogger.w('SyncService', '本地场景不存在: $sceneKey');
            continue;
          }

          // 构建payload（与 /novels/upsert-chapter-scenes-batch 兼容）
          final payload = {
            'id': sceneId,
            'novelId': novelId,
            'chapterId': chapterId,
            'content': localScene.content,
            'summary': localScene.summary.content,
            'wordCount': localScene.wordCount,
            'title': (localScene.title.isNotEmpty ? localScene.title : '场景 $sceneId'),
          };
          allScenePayloads.add(payload);
          sceneKeyById[sceneId] = sceneKey;
        }

        // 根据阈值切片并发送
        List<Map<String, dynamic>> currentBatch = [];
        int batchIndex = 0;

        Future<void> flushBatch() async {
          if (currentBatch.isEmpty) return;
          final batchData = {
            'novelId': novelId,
            'chapterId': chapterId,
            'scenes': currentBatch,
          };
          final estimatedBytes = utf8.encode(jsonEncode(batchData)).length;
          AppLogger.d('SyncService', '发送批次: chapter=$chapterId, 批次索引=$batchIndex, 场景数=${currentBatch.length}, 估算体积=${estimatedBytes}B');
          try {
            await apiService.post('/novels/upsert-chapter-scenes-batch', data: batchData);
            // 清理对应的scene同步标记
            for (final s in currentBatch) {
              final sid = s['id'] as String;
              final skey = sceneKeyById[sid];
              if (skey != null) {
                await localStorageService.clearSyncFlagByType('scene', skey);
              }
            }
            AppLogger.i('SyncService', '批次同步完成: chapter=$chapterId, 批次索引=$batchIndex, 场景数=${currentBatch.length}');
          } catch (e, st) {
            AppLogger.e('SyncService', '批次同步失败: chapter=$chapterId, 批次索引=$batchIndex', e, st);
            // 失败时保留同步标记，以便下次重试
          }
          currentBatch = [];
          batchIndex += 1;
        }

        for (final scenePayload in allScenePayloads) {
          // 尝试将当前场景加入批次，若超过阈值则先发送已有批次
          final tentativeBatch = [...currentBatch, scenePayload];
          final tentativeData = {
            'novelId': novelId,
            'chapterId': chapterId,
            'scenes': tentativeBatch,
          };
          final estimatedBytes = utf8.encode(jsonEncode(tentativeData)).length;

          if (tentativeBatch.length > maxScenesPerBatch || estimatedBytes > maxBatchBytes) {
            await flushBatch();
          }
          currentBatch.add(scenePayload);
        }

        // 发送最后一批
        await flushBatch();
      }
    } catch (e, stackTrace) {
      AppLogger.e('SyncService', '同步场景内容失败', e, stackTrace);
      throw SyncException('同步场景内容失败: $e');
    }
  }

  /// 同步编辑器内容
  Future<void> _syncEditorContents() async {
    try {
      // 获取当前正在编辑的小说ID
      final currentNovelId = await localStorageService.getCurrentNovelId();
      if (currentNovelId == null) {
        AppLogger.w('SyncService', '无当前小说ID，跳过编辑器内容同步');
        return;
      }

      final syncList = await localStorageService.getSyncList('editor');
      AppLogger.d('SyncService', '需要同步的编辑器内容数量: ${syncList.length}');

      // 筛选出当前小说的编辑器内容
      final contentsToSync = syncList.where((contentKey) {
        final parts = contentKey.split('_');
        return parts.length >= 2 && parts[0] == currentNovelId;
      }).toList();

      AppLogger.d('SyncService', '当前小说的编辑器内容需要同步: ${contentsToSync.length} (当前小说ID: $currentNovelId)');
      
      if (contentsToSync.isEmpty) {
        AppLogger.i('SyncService', '当前小说没有编辑器内容需要同步，跳过');
        return;
      }

      for (final contentKey in contentsToSync) {
        final parts = contentKey.split('_');
        if (parts.length < 2) {
          AppLogger.w('SyncService', '无效的编辑器内容键格式: $contentKey');
          continue;
        }

        final novelId = parts[0];
        final chapterId = parts[1];

        final localContent =
            await localStorageService.getEditorContent(novelId, chapterId, '');
        if (localContent == null) {
          AppLogger.w('SyncService', '本地编辑器内容不存在: $contentKey');
          continue;
        }

        AppLogger.i('SyncService', '同步编辑器内容: $contentKey');
        await apiService.saveEditorContent(
            novelId, chapterId, localContent.toJson());

        await localStorageService.clearSyncFlagByType('editor', contentKey);
        AppLogger.d('SyncService', '编辑器内容同步完成: $contentKey');
      }
    } catch (e, stackTrace) {
      AppLogger.e('SyncService', '同步编辑器内容失败', e, stackTrace);
      throw SyncException('同步编辑器内容失败: $e');
    }
  }

  /// 同步聊天会话元数据 (No longer sends full message history)
  Future<void> _syncChatSessions() async {
    // This method now only syncs session metadata like title, updatedAt
    try {
      // 获取当前正在编辑的小说ID
      final currentNovelId = await localStorageService.getCurrentNovelId();
      if (currentNovelId == null) {
        AppLogger.w('SyncService', '无当前小说ID，跳过聊天会话同步');
        return;
      }

      final sessions = await localStorageService.getSessionsToSync();
      AppLogger.d('SyncService', '需要同步的聊天会话元数据数量: ${sessions.length}');

      // 筛选出当前小说的聊天会话
      // 注意：这里假设 ChatSession 模型有 novelId 属性，如果没有，需要调整过滤逻辑
      final sessionsToSync = sessions.where((session) => 
          session.metadata != null && 
          session.metadata!['novelId'] == currentNovelId).toList();
      
      AppLogger.d('SyncService', '当前小说的聊天会话需要同步: ${sessionsToSync.length} (当前小说ID: $currentNovelId)');
      
      if (sessionsToSync.isEmpty) {
        AppLogger.i('SyncService', '当前小说没有聊天会话需要同步，跳过');
        return;
      }

      // No need for userId here if updateSession API only updates metadata
      // If updateSession *requires* userId, get it once:
      // final String currentUserId = await _getCurrentUserId();

      for (final session in sessionsToSync) {
        AppLogger.i('SyncService', '同步聊天会话元数据: ${session.id}');

        // Construct updates payload - only include fields managed locally
        // that need syncing (like title if user can rename offline)
        final Map<String, dynamic> updates = {
          'title': session.title,
          // Include lastUpdatedAt from local session to inform server?
          // 'updatedAt': session.lastUpdatedAt.toIso8601String(),
          // Or maybe server handles updatedAt automatically on update?
        };

        // Only call update if there are actual updates to send
        if (updates.isNotEmpty) {
          // If updateSession requires userId, pass it: userId: currentUserId,
          await apiService.updateAiChatSession(
            userId: await _getCurrentUserId(), // Get userId if needed by API
            sessionId: session.id,
            updates: updates,
          );
        } // Else: Session might be marked for sync without local changes, skip API call?

        // REMOVED: Loop sending messages using getMessagesForSession

        await localStorageService.clearSyncFlagByType(
            'chat_session', session.id);
        AppLogger.d('SyncService', '聊天会话元数据同步完成: ${session.id}');
      }
    } catch (e, stackTrace) {
      // Don't throw - allow other sync tasks to proceed if possible
      AppLogger.e('SyncService', '同步聊天会话元数据失败', e, stackTrace);
      // Optionally update state with a non-fatal error?
      // _updateSyncState(error: '部分同步失败: 聊天会话元数据'); // Be careful not to overwrite fatal errors
    }
  }

  /// --- New Method: Sync Pending Chat Messages ---
  Future<void> _syncPendingMessages() async {
    try {
      // 如果服务已关闭，直接返回
      if (_isDisposed) {
        AppLogger.w('SyncService', '服务已关闭，无法同步待发送消息');
        return;
      }
      
      // 获取当前正在编辑的小说ID
      final currentNovelId = await localStorageService.getCurrentNovelId();
      if (currentNovelId == null) {
        AppLogger.w('SyncService', '无当前小说ID，跳过待发送消息同步');
        return;
      }

      final pendingMessages = await localStorageService.getPendingMessages();
      if (pendingMessages.isEmpty) {
        AppLogger.d('SyncService', '没有待发送的消息。');
        return;
      }

      // 筛选出当前小说的待发送消息
      final messagesToSync = pendingMessages.where((message) {
        // 检查消息元数据中是否包含小说ID
        final metadata = message['metadata'] as Map<String, dynamic>?;
        return metadata != null && metadata['novelId'] == currentNovelId;
      }).toList();

      if (messagesToSync.isEmpty) {
        AppLogger.i('SyncService', '当前小说没有待发送消息需要同步，跳过');
        return;
      }

      AppLogger.i('SyncService', '开始处理 ${messagesToSync.length} 条当前小说的待发送消息。 (当前小说ID: $currentNovelId)');
      final String currentUserId =
          await _getCurrentUserId(); // Get User ID once

      for (final messageData in messagesToSync) {
        final localId = messageData['localId'] as String?;
        final sessionId = messageData['sessionId'] as String?;
        final content = messageData['content'] as String?;
        final metadata = messageData['metadata'] as Map<String, dynamic>?;
        // Important: Use the userId stored with the message if available,
        // otherwise use currentUserId. This handles cases where sync might
        // happen after user logout/login, though ideally pending messages
        // should be cleared on logout.
        final userIdToSend = messageData['userId'] as String? ?? currentUserId;

        if (localId == null || sessionId == null || content == null) {
          AppLogger.e('SyncService', '待发送消息数据不完整，跳过: $messageData');
          // Optionally remove corrupted data
          // if (localId != null) await localStorageService.removePendingMessage(localId);
          continue;
        }

        try {
          AppLogger.d(
              'SyncService', '尝试发送消息: localId=$localId, sessionId=$sessionId');
          // Call the actual API to send the message
          await apiService.sendAiChatMessage(
            userId: userIdToSend,
            sessionId: sessionId,
            content: content,
            metadata: metadata,
          );

          // If sendMessage succeeds, remove from local pending queue
          await localStorageService.removePendingMessage(localId);
          AppLogger.i('SyncService', '成功发送并移除待发送消息: localId=$localId');

          // OPTIONAL: Add the successfully sent message to the local history cache
          // This requires constructing a proper ChatMessage object from the response
          // or assuming success and creating one locally. This is complex.
          // It might be simpler to rely on fetching history later.
        } on ApiException catch (apiError, stack) {
          // Catch specific API errors
          AppLogger.e(
              'SyncService',
              '发送待处理消息失败 (API Error $localId): ${apiError.message}',
              apiError,
              stack);
          // Decide if error is temporary or permanent.
          // For now, leave in queue and retry later.
          // If 4xx error, maybe remove from queue?
          if (apiError.statusCode >= 400 &&
              apiError.statusCode < 500 &&
              apiError.statusCode != 401 &&
              apiError.statusCode != 429) {
            AppLogger.w('SyncService',
                '接收到客户端错误 (${apiError.statusCode})，可能移除待发送消息 $localId');
            // Consider removing permanently failed message
            // await localStorageService.removePendingMessage(localId);
          }
        } catch (e, stackTrace) {
          // Catch other errors
          AppLogger.e(
              'SyncService', '发送待处理消息时发生未知错误 ($localId)', e, stackTrace);
          // Leave in queue for retry
        }
      }
      AppLogger.i('SyncService', '处理待发送消息完成。');
    } catch (e, stackTrace) {
      // Error fetching or processing the queue itself
      AppLogger.e('SyncService', '处理待发送消息队列时出错', e, stackTrace);
      // Don't throw, allow other sync tasks. Update state?
      // _updateSyncState(error: '部分同步失败: 待发送消息');
    }
  }

  /// 同步单个小说
  Future<bool> syncNovel(String novelId) async {
    // 如果服务已关闭，直接返回
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，无法同步小说');
      return false;
    }
    
    if (!_currentState.isOnline) {
      _updateSyncState(error: '无网络连接，无法同步');
      return false;
    }

    try {
      // 获取本地小说
      final localNovel = await localStorageService.getNovel(novelId);
      if (localNovel == null) return false;

      // 构建后端所需的小说数据结构
      final backendNovelJson = {
        'id': localNovel.id,
        'title': localNovel.title,
        'coverImage': localNovel.coverUrl,
        // 确保包含作者信息
        'author': localNovel.author?.toJson() ??
            {
              'id': AppConfig.userId ?? '',
              'username': AppConfig.username ?? 'user'
            },
        'lastEditedChapterId': localNovel.lastEditedChapterId,
        'createdAt': localNovel.createdAt.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'structure': {
          'acts': localNovel.acts
              .map((act) => {
                    'id': act.id,
                    'title': act.title,
                    'order': act.order,
                    'chapters': act.chapters
                        .map((chapter) => {
                              'id': chapter.id,
                              'title': chapter.title,
                              'order': chapter.order,
                              // 注意：章节中只需包含ID，场景内容通过scenesByChapter单独提供
                              'sceneIds': chapter.scenes.map((scene) => scene.id).toList(),
                            })
                        .toList(),
                  })
              .toList(),
        },
      };
      
      // 仅同步小说元数据/结构
      await apiService.updateNovel(backendNovelJson);

      // 标记为已同步
      await localStorageService.clearSyncFlagByType('novel', novelId);

      return true;
    } catch (e) {
      AppLogger.e('Services/sync_service', '同步小说失败', e);
      _updateSyncState(error: '同步小说失败: $e');
      return false;
    }
  }

  /// 同步单个场景
  Future<bool> syncScene(
      String novelId, String actId, String chapterId, String sceneId) async {
    // 如果服务已关闭，直接返回
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，无法同步场景');
      return false;
    }
    
    if (!_currentState.isOnline) {
      _updateSyncState(error: '无网络连接，无法同步');
      return false;
    }

    try {
      // 获取本地场景
      final localScene = await localStorageService.getSceneContent(
          novelId, actId, chapterId, sceneId);
      if (localScene == null) return false;

      // 上传到服务器
      final sceneData = localScene.toJson();
      await apiService.updateScene(sceneData);

      // 标记为已同步
      final sceneKey = '${novelId}_${actId}_${chapterId}_$sceneId';
      await localStorageService.clearSyncFlagByType('scene', sceneKey);

      return true;
    } catch (e) {
      AppLogger.e('Services/sync_service', '同步场景失败', e);
      _updateSyncState(error: '同步场景失败: $e');
      return false;
    }
  }

  /// 同步单个编辑器内容
  Future<bool> syncEditorContent(String novelId, String chapterId,
      String sceneId) async {
    // 如果服务已关闭，直接返回
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，无法同步编辑器内容');
      return false;
    }
    
    if (!_currentState.isOnline) {
      _updateSyncState(error: '无网络连接，无法同步');
      return false;
    }

    try {
      // 获取本地编辑器内容
      final localContent = await localStorageService.getEditorContent(
          novelId, chapterId, ''); // 传递空的 sceneId 或适配
      if (localContent == null) return false;

      // 上传到服务器
      await apiService.saveEditorContent(
          novelId, chapterId, localContent.toJson());

      // 标记为已同步
      final contentKey = '${novelId}_$chapterId'; // 调整 key
      await localStorageService.clearSyncFlagByType('editor', contentKey);

      return true;
    } catch (e) {
      AppLogger.e('Services/sync_service', '同步编辑器内容失败', e);
      _updateSyncState(error: '同步编辑器内容失败: $e');
      return false;
    }
  }

  /// 同步单个聊天会话元数据 (不再发送消息历史)
  Future<bool> syncChatSession(String sessionId) async {
    // 如果服务已关闭，直接返回
    if (_isDisposed) {
      AppLogger.w('SyncService', '服务已关闭，无法同步聊天会话');
      return false;
    }
    
    if (!_currentState.isOnline) {
      _updateSyncState(error: '无网络连接，无法同步');
      return false;
    }

    try {
      final session = await localStorageService.getChatSession(sessionId);
      if (session == null) {
        AppLogger.w('SyncService', '尝试同步单个会话元数据，但本地未找到: $sessionId');
        await localStorageService.clearSyncFlagByType(
            'chat_session', sessionId); // 清除无效标记
        return false; // 无法同步不存在的会话
      }

      // 同步元数据 (例如: title)
      final Map<String, dynamic> updates = {'title': session.title};

      if (updates.isNotEmpty) {
        await apiService.updateAiChatSession(
          userId: await _getCurrentUserId(), // 如果 API 需要，获取 userId
          sessionId: session.id,
          updates: updates,
        );
        AppLogger.d('SyncService', '单个聊天会话元数据 API 更新调用完成: $sessionId');
      } else {
        AppLogger.d('SyncService', '单个聊天会话 ${session.id} 没有需要同步的元数据更新');
      }

      // ======== 移除: 不再通过 getMessagesForSession 循环发送消息 ========

      // 清除此会话的元数据同步标记
      await localStorageService.clearSyncFlagByType('chat_session', sessionId);
      AppLogger.i('SyncService', '单个聊天会话元数据同步处理完成: $sessionId');
      return true;
    } catch (e, stackTrace) {
      // 捕获所有可能的错误
      AppLogger.e('SyncService', '同步单个聊天会话元数据失败 ($sessionId)', e, stackTrace);
      _updateSyncState(error: '同步单个聊天会话元数据失败: $e');
      // 同步失败，暂时不清除标记，留待下次重试
      return false;
    }
  }

  /// 解决冲突 (需要根据聊天数据的具体冲突场景来完善)

  /// 关闭服务，释放资源
  void dispose() {
    // 设置已关闭标志
    _isDisposed = true;
    
    // 取消网络监听和定时器
    _connectivitySubscription?.cancel();
    _autoSyncTimer?.cancel();
    
    // 关闭状态流
    if (!_syncStateController.isClosed) {
      _syncStateController.close();
    }
    
    // 清除当前小说ID，避免后续同步错误
    localStorageService.setCurrentNovelId('').then((_) {
      AppLogger.i('SyncService', '同步服务已关闭，清除当前小说ID');
    });
    
    AppLogger.i('SyncService', '同步服务已关闭');
  }

  /// 获取当前用户ID (使用 AppConfig 实现)
  Future<String> _getCurrentUserId() async {
    final userId = AppConfig.userId; // 从 AppConfig 获取用户ID
    if (userId == null || userId.isEmpty) {
      AppLogger.e('SyncService', '无法获取当前用户ID，同步操作可能失败或无法执行。');
      // 根据需求，可以抛出异常或返回占位符/空字符串
      // 如果 userId 是必需的，抛出异常更安全
      throw SyncException('无法获取当前用户ID，无法执行需要用户ID的同步操作。');
    }
    return userId;
  }

  /// 直接设置当前小说ID
  Future<void> setCurrentNovelId(String novelId) async {
    // 即使服务已关闭也允许设置，但记录警告
    if (_isDisposed) {
      AppLogger.w('SyncService', '尝试在服务已关闭状态下设置当前小说ID: $novelId');
      // 考虑到可能在关闭过程中调用此方法，仍然允许操作继续
    }
    
    await localStorageService.setCurrentNovelId(novelId);
    AppLogger.i('SyncService', '同步服务已设置当前小说ID: $novelId');
  }
}

/// 同步状态类
class SyncState {
  SyncState({
    required this.isOnline, // 网络是否连接
    required this.isSyncing, // 是否正在同步中
    this.error, // 同步错误信息，null表示无错误
    this.progress = 0.0, // 同步进度 (0.0 到 1.0)
  });

  /// 空闲状态 (默认在线)
  factory SyncState.idle({bool online = true}) {
    return SyncState(
      isOnline: online,
      isSyncing: false,
    );
  }

  /// 同步中状态
  factory SyncState.syncing({double progress = 0.0}) {
    return SyncState(
      isOnline: true, // 同步时必须在线
      isSyncing: true,
      progress: progress,
    );
  }

  /// 离线状态
  factory SyncState.offline() {
    return SyncState(
      isOnline: false,
      isSyncing: false, // 离线时不能同步
    );
  }

  /// 错误状态 (允许指定当时的网络状态)
  factory SyncState.error(String errorMessage, {bool online = true}) {
    return SyncState(
      isOnline: online, // 错误可能在线或离线时发生
      isSyncing: false, // 出错时停止同步
      error: errorMessage,
    );
  }
  final bool isOnline;
  final bool isSyncing;
  final String? error;
  final double progress;

  @override
  String toString() {
    // 提供更清晰的状态描述
    return 'SyncState(在线: $isOnline, 同步中: $isSyncing, 进度: ${progress.toStringAsFixed(2)}, 错误: ${error ?? "无"})';
  }
}

/// 同步异常类
class SyncException implements Exception {
  SyncException(this.message);
  final String message; // 异常信息

  @override
  String toString() => 'SyncException: $message';
}
