import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:ainoval/models/editor_settings.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/services/api_service/repositories/impl/editor_repository_impl.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/word_count_analyzer.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'editor_event.dart';
part 'editor_state.dart';

// Helper class to hold the two maps
class _ChapterMaps {
  final Map<String, int> chapterGlobalIndices;
  final Map<String, String> chapterToActMap;

  _ChapterMaps(this.chapterGlobalIndices, this.chapterToActMap);
}

// Bloc实现
class EditorBloc extends Bloc<EditorEvent, EditorState> {
  EditorBloc({
    required EditorRepositoryImpl repository,
    required this.novelId,
  })  : repository = repository,
        super(EditorInitial()) {
    on<LoadEditorContentPaginated>(_onLoadContentPaginated);
    on<LoadMoreScenes>(_onLoadMoreScenes);
    on<UpdateContent>(_onUpdateContent);
    on<SaveContent>(_onSaveContent);
    on<UpdateSceneContent>(_onUpdateSceneContent);
    on<UpdateSummary>(_onUpdateSummary);
    on<UpdateEditorSettings>(_onUpdateSettings);
    on<LoadUserEditorSettings>(_onLoadUserEditorSettings); // 🚀 新增：处理加载用户编辑器设置事件
    on<SetActiveChapter>(_onSetActiveChapter);
    on<SetActiveScene>(_onSetActiveScene);
    on<SetFocusChapter>(_onSetFocusChapter); // 添加新的事件处理
    on<AddNewScene>(_onAddNewScene);
    on<DeleteScene>(_onDeleteScene);
    on<DeleteChapter>(_onDeleteChapter);
    on<DeleteAct>(_onDeleteAct);
    on<SaveSceneContent>(_onSaveSceneContent);
    on<ForceSaveSceneContent>(_onForceSaveSceneContent); // 添加强制保存事件处理
    on<AddNewAct>(_onAddNewAct);
    on<AddNewChapter>(_onAddNewChapter);
    on<UpdateVisibleRange>(_onUpdateVisibleRange);
    on<ResetActLoadingFlags>(_onResetActLoadingFlags); // 添加新事件处理
    on<SetActLoadingFlags>(_onSetActLoadingFlags); // 添加新的事件处理器
    on<UpdateChapterTitle>(_onUpdateChapterTitle); // 添加Chapter标题更新事件处理
    on<UpdateActTitle>(_onUpdateActTitle); // 添加Act标题更新事件处理
    on<GenerateSceneFromSummaryRequested>(_onGenerateSceneFromSummaryRequested); // 添加场景生成事件处理
    on<UpdateGeneratedSceneContent>(_onUpdateGeneratedSceneContent); // 添加更新生成内容事件处理
    on<SceneGenerationCompleted>(_onSceneGenerationCompleted); // 添加生成完成事件处理
    on<SceneGenerationFailed>(_onSceneGenerationFailed); // 添加生成失败事件处理
    on<StopSceneGeneration>(_onStopSceneGeneration); // 添加停止生成事件处理
    on<SetPendingSummary>(_onSetPendingSummary); // 添加设置待处理摘要事件处理
    
    // 🚀 新增：Plan视图相关事件处理
    on<SwitchToPlanView>(_onSwitchToPlanView);
    on<SwitchToWriteView>(_onSwitchToWriteView);
    on<LoadPlanContent>(_onLoadPlanContent);
    on<MoveScene>(_onMoveScene);
    on<NavigateToSceneFromPlan>(_onNavigateToSceneFromPlan);
    on<RefreshEditorData>(_onRefreshEditorData);
    
    // 🚀 新增：沉浸模式相关事件处理
    on<SwitchToImmersiveMode>(_onSwitchToImmersiveMode);
    on<SwitchToNormalMode>(_onSwitchToNormalMode);
    on<NavigateToNextChapter>(_onNavigateToNextChapter);
    on<NavigateToPreviousChapter>(_onNavigateToPreviousChapter);
  }
  final EditorRepositoryImpl repository;
  final String novelId;
  Timer? _autoSaveTimer;
  novel_models.Novel? _novel;
  bool _isDirty = false;
  DateTime? _lastSaveTime;
  final EditorSettings _settings = const EditorSettings();
  bool? hasReachedEnd;
  bool? hasReachedStart;

  StreamSubscription<String>? _generationStreamSubscription;

  /// 待保存场景的缓冲队列
  final Map<String, Map<String, dynamic>> _pendingSaveScenes = {};
  /// 上次保存时间映射
  final Map<String, DateTime> _lastSceneSaveTime = {};
  /// 批量保存防抖计时器
  Timer? _batchSaveDebounceTimer;
  /// 批量保存间隔（改为5分钟，优先本地保存，减少后端请求）
  static const Duration _batchSaveInterval = Duration(minutes: 5);
  /// 单场景保存防抖间隔
  static const Duration _sceneSaveDebounceInterval = Duration(milliseconds: 800);

  /// 摘要更新防抖控制
  final Map<String, DateTime> _lastSummaryUpdateRequestTime = {};
  static const Duration _summaryUpdateRequestInterval = Duration(milliseconds: 800);

  /// lastEditedChapterId更新防抖控制
  Timer? _lastEditedChapterUpdateTimer;
  String? _pendingLastEditedChapterId;
  static const Duration _lastEditedChapterUpdateInterval = Duration(seconds: 3);

  // Helper method to calculate chapter maps
  _ChapterMaps _calculateChapterMaps(novel_models.Novel novel) {
    final Map<String, int> chapterGlobalIndices = {};
    final Map<String, String> chapterToActMap = {};
    int globalIndex = 0;

    for (final act in novel.acts) {
      for (final chapter in act.chapters) {
        chapterGlobalIndices[chapter.id] = globalIndex++;
        chapterToActMap[chapter.id] = act.id;
      }
    }
    return _ChapterMaps(chapterGlobalIndices, chapterToActMap);
  }

  Future<void> _onLoadContentPaginated(
      LoadEditorContentPaginated event, Emitter<EditorState> emit) async {
    emit(EditorLoading());

    try {
      // 使用getNovelWithAllScenes替代getNovelWithPaginatedScenes
      novel_models.Novel? novel = await repository.getNovelWithAllScenes(event.novelId);

      if (novel == null) {
        emit(const EditorError(message: '无法加载小说数据'));
        return;
      }
      AppLogger.i('EditorBloc/_onLoadContentPaginated', 'Loaded novel from getNovelWithAllScenes. Novel ID: ${novel.id}, Title: ${novel.title}');
      AppLogger.i('EditorBloc/_onLoadContentPaginated', 'Novel acts count: ${novel.acts.length}');
      for (int i = 0; i < novel.acts.length; i++) {
          final act = novel.acts[i];
          //AppLogger.i('EditorBloc/_onLoadContentPaginated', 'Act ${i} (${act.id}): Title: ${act.title}, Chapters count: ${act.chapters.length}');
          for (int j = 0; j < act.chapters.length; j++) {
              final chapter = act.chapters[j];
              //AppLogger.i('EditorBloc/_onLoadContentPaginated', '  Chapter ${j} (${chapter.id}): Title: ${chapter.title}, Scenes count: ${chapter.scenes.length}');
              for (int k = 0; k < chapter.scenes.length; k++) {
                  final scene = chapter.scenes[k];
                  //AppLogger.d('EditorBloc/_onLoadContentPaginated', '    Scene ${k} (${scene.id}): WordCount: ${scene.wordCount}, HasContent: ${scene.content.isNotEmpty}, Summary: ${scene.summary.content}');
              }
          }
      }

      // 从此处开始，novel 不为 null
      if (novel.acts.isEmpty) { 
        AppLogger.i('EditorBloc/_onLoadContentPaginated', '检测到小说 (${novel.id}) 没有卷，尝试自动创建第一卷。');
        try {
          // novel.id 是安全的，因为 novel 在此不为 null
          final novelWithNewAct = await repository.addNewAct(
            novel.id, 
            "第一卷", 
          );
          if (novelWithNewAct != null) {
            novel = novelWithNewAct; // novel 可能被新对象（同样不为null）赋值
            // novel.id 和 novel.acts 在此也是安全的
            AppLogger.i('EditorBloc/_onLoadContentPaginated', '成功为小说 (${novel.id}) 自动创建第一卷。新的卷数量: ${novel.acts.length}');
          } else {
            AppLogger.w('EditorBloc/_onLoadContentPaginated', '为小说 (${novel.id}) 自动创建第一卷失败，repository.addNewAct 返回 null。');
          }
        } catch (e) {
          AppLogger.e('EditorBloc/_onLoadContentPaginated', '为小说 (${novel?.id}) 自动创建第一卷时发生错误。', e);
        }
      }

      final settings = await repository.getEditorSettings();

      String? activeActId;
      // novel 在此不为 null
      String? activeChapterId = novel?.lastEditedChapterId;
      String? activeSceneId;

      if (activeChapterId != null && activeChapterId.isNotEmpty) {
        for (final act_ in novel!.acts) { 
          for (final chapter in act_.chapters) {
            if (chapter.id == activeChapterId) {
              activeActId = act_.id;
              if (chapter.scenes.isNotEmpty) {
                activeSceneId = chapter.scenes.first.id;
              }
              break;
            }
          }
          if (activeActId != null) break;
        }
      }

      if (activeActId == null && novel!.acts.isNotEmpty) {
        activeActId = novel.acts.first.id;
        if (novel.acts.first.chapters.isNotEmpty) {
          activeChapterId = novel.acts.first.chapters.first.id;
          if (novel.acts.first.chapters.first.scenes.isNotEmpty) {
            activeSceneId = novel.acts.first.chapters.first.scenes.first.id;
          }
        } else {
          activeChapterId = null;
          activeSceneId = null;
        }
      }
      
      // novel 在此不为 null，因此 novel! 是安全的
      final chapterMaps = _calculateChapterMaps(novel!);

      emit(EditorLoaded(
        novel: novel,
        settings: settings,
        activeActId: activeActId,
        activeChapterId: activeChapterId,
        activeSceneId: activeSceneId,
        isDirty: false,
        isSaving: false,
        chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
        chapterToActMap: chapterMaps.chapterToActMap, // Added
      ));
    } catch (e) {
      emit(EditorError(message: '加载小说失败: ${e.toString()}'));
    }
  }

  Future<void> _onLoadMoreScenes(
      LoadMoreScenes event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) {
      return;
    }

    // 获取当前加载状态
    final currentState = state as EditorLoaded;
    
    // 如果已经在加载中且skipIfLoading为true，则跳过
    if (currentState.isLoading && event.skipIfLoading) {
      AppLogger.d('Blocs/editor/editor_bloc', '加载请求过于频繁，已被节流');
      return;
    }

    // 增强边界检测逻辑，更严格地检查是否已到达边界
    if (event.direction == 'up') {
      if (currentState.hasReachedStart) {
        AppLogger.i('Blocs/editor/editor_bloc', '已到达内容顶部，跳过向上加载请求');
        // 再次明确设置hasReachedStart标志，以防之前的设置未生效
        emit(currentState.copyWith(
          hasReachedStart: true,
        ));
        return;
      }
    } else if (event.direction == 'down') {
      if (currentState.hasReachedEnd) {
        AppLogger.i('Blocs/editor/editor_bloc', '已到达内容底部，跳过向下加载请求');
        // 再次明确设置hasReachedEnd标志，以防之前的设置未生效
        emit(currentState.copyWith(
          hasReachedEnd: true,
        ));
        return;
      }
    }

    // 设置加载状态
    emit(currentState.copyWith(isLoading: true));

    try {
      AppLogger.i('Blocs/editor/editor_bloc', 
          '开始加载更多场景: 卷ID=${event.actId}, 章节ID=${event.fromChapterId}, 方向=${event.direction}, 章节限制=${event.chaptersLimit}, 防止焦点变化=${event.preventFocusChange}');
      
      // 添加超时处理，避免请求无响应
      final completer = Completer<Map<String, List<novel_models.Scene>>?>();
      
      // 使用Future.any同时处理正常结果和超时
      Future.delayed(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          AppLogger.w('Blocs/editor/editor_bloc', '加载请求超时，自动取消');
          completer.complete(null);
        }
      });
      
      // 尝试从本地加载
      if (event.loadFromLocalOnly) {
        AppLogger.i('Blocs/editor/editor_bloc', '尝试仅从本地加载卷 ${event.actId} 章节 ${event.fromChapterId} 的场景');
        // 实现本地加载逻辑
      } else {
        // 从API加载，使用正确的参数格式
        AppLogger.i('Blocs/editor/editor_bloc', '从API加载卷 ${event.actId} 章节 ${event.fromChapterId} 的场景 (方向=${event.direction})');
        
        // 开始API请求但不立即等待
        final futureResult = repository.loadMoreScenes(
          novelId,
          event.actId,
          event.fromChapterId,
          event.direction,
          chaptersLimit: event.chaptersLimit,
        );
        
        // 将API请求结果提交给completer
        futureResult.then((result) {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        }).catchError((e) {
          if (!completer.isCompleted) {
            AppLogger.e('Blocs/editor/editor_bloc', '加载API调用出错', e);
            completer.complete(null);
          }
        });
      }
      
      // 等待结果或超时
      final result = await completer.future;

      // 检查API返回结果
      if (result != null) {
        if (result.isNotEmpty) {
          // 获取当前状态（可能在API请求期间已经发生变化）
          final updatedState = state as EditorLoaded;

          // 合并新场景到小说结构
          final updatedNovel = _mergeNewScenes(updatedState.novel, result);
          
          // 更新活动章节ID（如果需要）
          String? newActiveChapterId = updatedState.activeChapterId;
          String? newActiveSceneId = updatedState.activeSceneId;
          String? newActiveActId = updatedState.activeActId;

          if (!event.preventFocusChange) {
            // 仅当允许改变焦点时才更新活动章节
            final firstChapterId = result.keys.first;
            final firstChapterScenes = result[firstChapterId];
            
            if (firstChapterScenes != null && firstChapterScenes.isNotEmpty) {
              newActiveChapterId = firstChapterId;
              newActiveSceneId = firstChapterScenes.first.id;
              
              // 查找活动章节所属的Act
              for (final act in updatedNovel.acts) {
                for (final chapter in act.chapters) {
                  if (chapter.id == newActiveChapterId) {
                    newActiveActId = act.id;
                    break;
                  }
                }
                if (newActiveActId != null) break;
              }
            }
          }

          // 设置加载边界标志
          bool hasReachedStart = updatedState.hasReachedStart;
          bool hasReachedEnd = updatedState.hasReachedEnd;
          
          // 根据方向和返回结果判断是否达到边界
          // 如果API返回的结果非常少（比如只有1章），可能也意味着接近边界
          if (event.direction == 'up' && result.length <= 1) {
            hasReachedStart = true;
            AppLogger.i('Blocs/editor/editor_bloc', '向上加载返回数据很少，可能已接近顶部，设置hasReachedStart=true');
          } else if (event.direction == 'down' && result.length <= 1) {
            hasReachedEnd = true;
            AppLogger.i('Blocs/editor/editor_bloc', '向下加载返回数据很少，可能已接近底部，设置hasReachedEnd=true');
          }
          
          // Calculate chapter maps for the updated novel
          final chapterMaps = _calculateChapterMaps(updatedNovel);
          
          // 发送更新后的状态
          emit(EditorLoaded(
            novel: updatedNovel,
            settings: updatedState.settings,
            activeActId: newActiveActId,
            activeChapterId: newActiveChapterId,
            activeSceneId: newActiveSceneId,
            isLoading: false,
            hasReachedStart: hasReachedStart,
            hasReachedEnd: hasReachedEnd,
            focusChapterId: updatedState.focusChapterId,
            chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
            chapterToActMap: chapterMaps.chapterToActMap, // Added
          ));
          
          AppLogger.i('Blocs/editor/editor_bloc', '加载更多场景成功，更新了 ${result.length} 个章节');
        } else {
          // API返回空结果，说明该方向没有更多内容了
          // 根据加载方向设置边界标志
          bool hasReachedStart = currentState.hasReachedStart;
          bool hasReachedEnd = currentState.hasReachedEnd;
          
          if (event.direction == 'up') {
            hasReachedStart = true;
            AppLogger.i('Blocs/editor/editor_bloc', '向上没有更多场景可加载，设置hasReachedStart=true');
          } else if (event.direction == 'down') {
            hasReachedEnd = true;
            AppLogger.i('Blocs/editor/editor_bloc', '向下没有更多场景可加载，设置hasReachedEnd=true');
          } else if (event.direction == 'center') {
            // 如果是center方向且返回为空，可能同时到达了顶部和底部
            hasReachedStart = true;
            hasReachedEnd = true;
            AppLogger.i('Blocs/editor/editor_bloc', '中心加载返回为空，设置hasReachedStart=true和hasReachedEnd=true');
          }
          
          // 发送更新状态，包含边界标志
          emit(currentState.copyWith(
            isLoading: false,
            hasReachedStart: hasReachedStart,
            hasReachedEnd: hasReachedEnd,
          ));
          
          AppLogger.i('Blocs/editor/editor_bloc', '没有更多场景可加载，API返回为空');
        }
      } else {
        // API返回null，表示请求失败或超时
        // 这种情况不应标记为已到达边界，因为可能是网络问题
        AppLogger.w('Blocs/editor/editor_bloc', '加载更多场景失败，API返回null');
        emit(currentState.copyWith(
          isLoading: false,
          errorMessage: '加载场景时出现错误，请稍后再试',
        ));
      }
    } catch (e) {
      // 处理异常
      AppLogger.e('Blocs/editor/editor_bloc', '加载更多场景出错', e);
      // 不要在出错时设置边界标志，以免误判
      emit(currentState.copyWith(
        isLoading: false,
        errorMessage: '加载场景时出现错误: ${e.toString()}',
      ));
    }
  }


  Future<void> _onUpdateContent(
      UpdateContent event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      // 更新当前活动场景的内容
      if (currentState.activeActId != null &&
          currentState.activeChapterId != null) {
        final updatedNovel = _updateNovelContent(
          currentState.novel,
          currentState.activeActId!,
          currentState.activeChapterId!,
          event.content,
        );

        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: true,
        ));
      }
    }
  }

  Future<void> _onSaveContent(
      SaveContent event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      emit(currentState.copyWith(isSaving: true));

      try {
        // 🚀 优化：首先强制处理所有待保存的场景内容
        if (_pendingSaveScenes.isNotEmpty) {
          AppLogger.i('EditorBloc', '手动保存：先处理${_pendingSaveScenes.length}个待保存场景');
          await _processBatchSaveQueue();
        }

        // 🚀 优化：只保存小说基本信息，不包含场景数据
        await repository.saveNovel(currentState.novel);
        AppLogger.i('EditorBloc', '手动保存：小说基本信息已保存');

        // 🚀 优化：确保当前活动场景也被保存（如果它不在待保存队列中）
        if (currentState.activeActId != null &&
            currentState.activeChapterId != null &&
            currentState.activeSceneId != null) {
          
          final sceneKey = '${currentState.novel.id}_${currentState.activeActId}_${currentState.activeChapterId}_${currentState.activeSceneId}';
          
          // 只有当前场景不在最近保存的列表中时才单独保存
          final lastSaveTime = _lastSceneSaveTime[sceneKey];
          final now = DateTime.now();
          if (lastSaveTime == null || now.difference(lastSaveTime) > Duration(minutes: 1)) {
            try {
              // 获取当前活动场景
              final act = currentState.novel.acts.firstWhere(
                (act) => act.id == currentState.activeActId,
              );
              final chapter = act.chapters.firstWhere(
                (chapter) => chapter.id == currentState.activeChapterId,
              );

              // 获取当前活动场景
              if (chapter.scenes.isNotEmpty) {
                // 查找当前活动场景
                final scene = chapter.scenes.firstWhere(
                  (s) => s.id == currentState.activeSceneId,
                  orElse: () => chapter.scenes.first,
                );

                // 计算字数
                final wordCount = WordCountAnalyzer.countWords(scene.content);

                // 保存场景内容（确保同步到服务器）
                await repository.saveSceneContent(
                  currentState.novel.id,
                  currentState.activeActId!,
                  currentState.activeChapterId!,
                  currentState.activeSceneId!,
                  scene.content,
                  wordCount.toString(),
                  scene.summary,
                  localOnly: false, // 🚀 确保同步到服务器
                );
                
                // 更新最后保存时间
                _lastSceneSaveTime[sceneKey] = now;
                AppLogger.i('EditorBloc', '手动保存：当前活动场景已额外保存');
              }
            } catch (e) {
              AppLogger.e('EditorBloc', '手动保存当前活动场景失败', e);
              // 不抛出异常，因为场景保存失败不应该影响整体保存流程
            }
          } else {
            AppLogger.i('EditorBloc', '手动保存：当前活动场景最近已保存，跳过');
          }
        }

        emit(currentState.copyWith(
          isDirty: false, // 🚀 修复：手动保存后应该清除dirty状态
          isSaving: false,
          lastSaveTime: DateTime.now(),
        ));
      } catch (e) {
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: e.toString(),
        ));
      }
    }
  }

  // 使用防抖动机制将场景加入批量保存队列
  void _enqueueSceneForBatchSave({
    required String novelId,
    required String actId,
    required String chapterId,
    required String sceneId,
    required String content,
    required String wordCount,
  }) {
    // 首先验证章节和场景是否仍然存在
    if (state is EditorLoaded) {
      final currentState = state as EditorLoaded;
      
      // 查找章节是否存在
      bool chapterExists = false;
      bool sceneExists = false;

      for (final act in currentState.novel.acts) {
        if (act.id == actId) {
          for (final chapter in act.chapters) {
            if (chapter.id == chapterId) {
              chapterExists = true;
              // 检查场景是否存在
              for (final scene in chapter.scenes) {
                if (scene.id == sceneId) {
                  sceneExists = true;
                  break;
                }
              }
              break;
            }
          }
          break;
        }
      }

      if (!chapterExists) {
        AppLogger.w('EditorBloc', '无法保存场景${sceneId}：章节${chapterId}已不存在，跳过保存');
        return;
      }

      if (!sceneExists) {
        AppLogger.w('EditorBloc', '无法保存场景${sceneId}：场景已不存在，跳过保存');
        return;
      }
    }

    // 生成唯一键
    final sceneKey = '${novelId}_${actId}_${chapterId}_$sceneId';
    
    // 检查时间戳节流
    final now = DateTime.now();
    final lastSaveTime = _lastSceneSaveTime[sceneKey];
    if (lastSaveTime != null && now.difference(lastSaveTime) < _sceneSaveDebounceInterval) {
      AppLogger.d('EditorBloc', '场景${sceneId}的保存请求被节流，忽略此次保存');
      
      // 更新待保存数据，但不触发新的保存计时器
      _pendingSaveScenes[sceneKey] = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
        'sceneId': sceneId,
        'id': sceneId, // 添加id字段，与repository.batchSaveSceneContents期望的格式一致
        'content': _ensureValidQuillJson(content),
        'wordCount': int.tryParse(wordCount) ?? 0, // 转换为整数
        'queuedAt': now,
      };
      return;
    }

    // 加入待保存队列
    _pendingSaveScenes[sceneKey] = {
      'novelId': novelId,
      'actId': actId,
      'chapterId': chapterId,
      'sceneId': sceneId,
      'id': sceneId, // 添加id字段，与repository.batchSaveSceneContents期望的格式一致
      'content': _ensureValidQuillJson(content),
      'wordCount': int.tryParse(wordCount) ?? 0, // 转换为整数
      'queuedAt': now,
    };
    
    AppLogger.i('EditorBloc', '将场景${sceneId}加入批量保存队列，当前队列中有${_pendingSaveScenes.length}个场景');
    
    // 取消现有计时器
    _batchSaveDebounceTimer?.cancel();
    
    // 创建新计时器
    _batchSaveDebounceTimer = Timer(_batchSaveInterval, () {
      _processBatchSaveQueue();
    });
  }
  
  // 确保内容是有效的Quill JSON格式
  String _ensureValidQuillJson(String content) {
    // 直接使用QuillHelper工具类处理内容格式
    return QuillHelper.ensureQuillFormat(content);
  }

  /// 防抖更新lastEditedChapterId
  void _updateLastEditedChapterWithDebounce(String chapterId) {
    // 如果是相同的章节ID，不需要更新
    if (_pendingLastEditedChapterId == chapterId) {
      return;
    }

    _pendingLastEditedChapterId = chapterId;
    
    // 取消现有计时器
    _lastEditedChapterUpdateTimer?.cancel();
    
    // 创建新的防抖计时器
    _lastEditedChapterUpdateTimer = Timer(_lastEditedChapterUpdateInterval, () {
      if (_pendingLastEditedChapterId != null) {
        _flushLastEditedChapterUpdate();
      }
    });
    
    AppLogger.d('EditorBloc', '设置lastEditedChapterId防抖更新: $chapterId');
  }

  /// 立即执行lastEditedChapterId更新
  Future<void> _flushLastEditedChapterUpdate() async {
    if (_pendingLastEditedChapterId == null) return;
    
    final chapterId = _pendingLastEditedChapterId!;
    _pendingLastEditedChapterId = null;
    _lastEditedChapterUpdateTimer?.cancel();
    
    try {
      await repository.updateLastEditedChapterId(novelId, chapterId);
      AppLogger.i('EditorBloc', '防抖更新lastEditedChapterId成功: $chapterId');
    } catch (e) {
      AppLogger.e('EditorBloc', '防抖更新lastEditedChapterId失败: $chapterId', e);
    }
  }

  /// 处理批量保存队列
  Future<void> _processBatchSaveQueue() async {
    if (_pendingSaveScenes.isEmpty) return;
    
    AppLogger.i('EditorBloc', '开始处理批量保存队列，共${_pendingSaveScenes.length}个场景');
    
    // 处理前再次验证章节和场景存在性
    if (state is EditorLoaded) {
      final currentState = state as EditorLoaded;
      final novel = currentState.novel;
      
      // 创建需要移除的键列表
      final keysToRemove = <String>[];
      
      // 检查每个待保存场景
      for (final entry in _pendingSaveScenes.entries) {
        final key = entry.key;
        final sceneData = entry.value;
        final String actId = sceneData['actId'] as String;
        final String chapterId = sceneData['chapterId'] as String;
        final String sceneId = sceneData['sceneId'] as String;
        
        // 查找章节和场景是否仍然存在
        bool shouldKeep = false;
        
        for (final act in novel.acts) {
      if (act.id == actId) {
            for (final chapter in act.chapters) {
          if (chapter.id == chapterId) {
                for (final scene in chapter.scenes) {
                  if (scene.id == sceneId) {
                    shouldKeep = true;
                    break;
                  }
                }
                break;
              }
            }
            break;
          }
        }
        
        if (!shouldKeep) {
          keysToRemove.add(key);
          AppLogger.i('EditorBloc', '移除不存在的场景${sceneId}（章节${chapterId}）的保存请求');
        }
      }
      
      // 移除无效条目
      for (final key in keysToRemove) {
        _pendingSaveScenes.remove(key);
      }
      
      // 如果所有条目都被移除，直接返回
      if (_pendingSaveScenes.isEmpty) {
        AppLogger.i('EditorBloc', '批量保存队列为空（所有条目已被移除），跳过保存');
        return;
      }
    }
    
    // 按小说ID分组场景
    final Map<String, List<Map<String, dynamic>>> scenesByNovel = {};
    
    _pendingSaveScenes.forEach((sceneKey, sceneData) {
      final novelId = sceneData['novelId'] as String;
      if (!scenesByNovel.containsKey(novelId)) {
        scenesByNovel[novelId] = [];
      }
      scenesByNovel[novelId]!.add(sceneData);
      
      // 更新最后保存时间
      _lastSceneSaveTime[sceneKey] = DateTime.now();
    });
    
    // 清空待保存队列
    _pendingSaveScenes.clear();
    
    // 按小说批量保存
    for (final entry in scenesByNovel.entries) {
      final novelId = entry.key;
      final scenes = entry.value;
      
      AppLogger.i('EditorBloc', '批量保存小说${novelId}的${scenes.length}个场景');
      
      try {
        // 确保每个场景对象包含所有必要字段
        final List<Map<String, dynamic>> processedScenes = scenes.map((sceneData) {
          // 确保有id字段
          if (sceneData['id'] == null && sceneData['sceneId'] != null) {
            sceneData['id'] = sceneData['sceneId'];
          }
          
          // 移除队列特定的字段
          final processedData = Map<String, dynamic>.from(sceneData);
          processedData.remove('queuedAt'); // 移除仅用于队列的时间戳
          
          // 确保wordCount是整数
          if (processedData['wordCount'] is String) {
            processedData['wordCount'] = int.tryParse(processedData['wordCount']) ?? 0;
          }
          
          return processedData;
        }).toList();
        
        final success = await _batchSaveScenes(processedScenes, novelId);
        if (success) {
          AppLogger.i('EditorBloc', '小说${novelId}的${scenes.length}个场景批量保存成功');
          
          // 🚀 修复：更新保存状态
          _lastSaveTime = DateTime.now();
          _isDirty = false;
          
          // 🚀 新增：批量保存成功后，更新lastEditedChapterId
          // 选择最后排队保存的场景所在的章节作为lastEditedChapterId
          if (scenes.isNotEmpty) {
            // 找到最后排队的场景（按queuedAt时间排序）
            final lastScene = scenes.reduce((a, b) {
              final aTime = a['queuedAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = b['queuedAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
              return aTime.isAfter(bTime) ? a : b;
            });
            
            final lastChapterId = lastScene['chapterId'] as String?;
            if (lastChapterId != null) {
              AppLogger.i('EditorBloc', '批量保存后使用防抖更新lastEditedChapterId: $lastChapterId');
              _updateLastEditedChapterWithDebounce(lastChapterId);
            }
          }
          
          // 如果当前状态是EditorLoaded，更新保存状态
          if (state is EditorLoaded) {
            final currentState = state as EditorLoaded;
            
            emit(currentState.copyWith(
              isSaving: false,
              lastSaveTime: DateTime.now(),
              isDirty: false, // 🚀 修复：批量保存成功后清除dirty状态
            ));
          }
        } else {
          AppLogger.e('EditorBloc', '小说${novelId}的场景批量保存失败');
          // 🚀 修复：保存失败时不清除dirty状态
          if (state is EditorLoaded) {
            final currentState = state as EditorLoaded;
            emit(currentState.copyWith(
              isSaving: false,
              errorMessage: '批量保存失败',
            ));
          }
        }
      } catch (e) {
        AppLogger.e('EditorBloc', '批量保存出错: $e');
        // 🚀 修复：保存出错时不清除dirty状态
        if (state is EditorLoaded) {
          final currentState = state as EditorLoaded;
          emit(currentState.copyWith(
            isSaving: false,
            errorMessage: '批量保存出错: $e',
          ));
        }
      }
    }
  }

  // 修改现有的_onUpdateSceneContent方法，使用优化的批量保存
  Future<void> _onUpdateSceneContent(
      UpdateSceneContent event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      final isMinorChange = event.isMinorChange ?? false;
      
      // 验证章节和场景是否仍然存在
      bool chapterExists = false;
      bool sceneExists = false;
      
      for (final act in currentState.novel.acts) {
        if (act.id == event.actId) {
          for (final chapter in act.chapters) {
            if (chapter.id == event.chapterId) {
              chapterExists = true;
              
              for (final scene in chapter.scenes) {
                if (scene.id == event.sceneId) {
                  sceneExists = true;
                  break;
                }
              }
              break;
            }
          }
          break;
        }
      }
      
      if (!chapterExists) {
        AppLogger.e('EditorBloc', '更新场景内容失败：找不到指定的Chapter');
        emit(currentState.copyWith(
            isSaving: false,
          errorMessage: '更新场景内容失败：找不到指定的Chapter',
        ));
        return;
      }
      
      if (!sceneExists) {
        AppLogger.e('EditorBloc', '更新场景内容失败：找不到指定的Scene');
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '更新场景内容失败：找不到指定的Scene',
        ));
        return;
      }
      
      // 记录输入的字数
      AppLogger.i('EditorBloc',
          '接收到场景内容更新 - 场景ID: ${event.sceneId}, 字数: ${event.wordCount}, 是否小改动: $isMinorChange');

      // 验证并确保内容是有效的Quill JSON格式
      final String validContent = _ensureValidQuillJson(event.content);

      // 更新指定场景的内容（现在_updateSceneContent会自动更新lastEditedChapterId）
      final updatedNovel = _updateSceneContent(
        currentState.novel,
        event.actId,
        event.chapterId,
          event.sceneId,
        validContent, // 使用验证后的内容
      );

      // 🚀 修复：判断是否需要立即更新UI状态
      final bool shouldUpdateUiState = !isMinorChange;
      
      // 🚀 简化：统一更新小说数据和dirty状态
      emit(currentState.copyWith(
        novel: updatedNovel,
        isDirty: true, // 🚀 有未保存的更改
      ));

      // 使用传递的字数或重新计算
      final wordCount = event.wordCount ??
          WordCountAnalyzer.countWords(event.content).toString();

      // 将场景加入批量保存队列
      _enqueueSceneForBatchSave(
        novelId: event.novelId,
        actId: event.actId,
        chapterId: event.chapterId,
        sceneId: event.sceneId,
        content: validContent, // 使用验证后的内容
        wordCount: wordCount,
      );
    }
  }

  Future<void> _onUpdateSummary(
      UpdateSummary event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 添加防抖控制 - 使用场景ID作为键
        final String cacheKey = event.sceneId;
        final now = DateTime.now();
        final lastRequestTime = _lastSummaryUpdateRequestTime[cacheKey];
        
        if (lastRequestTime != null && 
            now.difference(lastRequestTime) < _summaryUpdateRequestInterval) {
          AppLogger.i('Blocs/editor/editor_bloc', 
              '摘要更新请求频率过高，跳过此次请求: ${event.sceneId}');
          return;
        }
        
        // 记录本次请求时间
        _lastSummaryUpdateRequestTime[cacheKey] = now;
        
        emit(currentState.copyWith(isSaving: true));
        
        AppLogger.i('Blocs/editor/editor_bloc',
            '更新场景摘要: novelId=${event.novelId}, actId=${event.actId}, chapterId=${event.chapterId}, sceneId=${event.sceneId}');
        
        // 查找场景和对应的摘要
        novel_models.Scene? sceneToUpdate;
        for (final act in currentState.novel.acts) {
          if (act.id == event.actId) {
            for (final chapter in act.chapters) {
              if (chapter.id == event.chapterId) {
                for (final scene in chapter.scenes) {
                  if (scene.id == event.sceneId) {
                    sceneToUpdate = scene;
                    break;
                  }
                }
                break;
              }
            }
            break;
          }
        }
        
        if (sceneToUpdate == null) {
          AppLogger.e('Blocs/editor/editor_bloc',
              '找不到要更新摘要的场景: ${event.sceneId}');
          emit(currentState.copyWith(
            isSaving: false,
            errorMessage: '找不到要更新摘要的场景',
          ));
          return;
        }
        
        // 创建新的摘要对象
        final updatedSummary = novel_models.Summary(
          id: sceneToUpdate.summary.id,
          content: event.summary,
        );
        
        // 使用repository保存摘要
        final success = await repository.updateSummary(
          event.novelId,
          event.actId,
          event.chapterId,
          event.sceneId,
          event.summary,
        );
        
        if (!success) {
          throw Exception('更新摘要失败');
        }
        
        // 创建更新后的场景
        final updatedScene = sceneToUpdate.copyWith(
          summary: updatedSummary,
        );
        
        // 更新小说中的场景
        final updatedNovel = _updateNovelScene(
          currentState.novel,
          event.actId,
          event.chapterId,
          updatedScene,
        );
        
        // 保存成功后，更新状态
        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: false,
          isSaving: false,
          lastSaveTime: DateTime.now(),
        ));
        
        AppLogger.i('Blocs/editor/editor_bloc',
            '场景摘要更新成功: ${event.sceneId}');
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '更新场景摘要失败', e);
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '更新场景摘要失败: ${e.toString()}',
        ));
      }
    }
  }

  // 辅助方法：查找章节所属的Act ID
  String? _findActIdForChapter(novel_models.Novel novel, String chapterId) {
    for (final act in novel.acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == chapterId) {
          return act.id;
        }
      }
    }
    return null;
  }

  @override
  Future<void> close() async {
    // 立即执行任何待处理的lastEditedChapterId更新
    await _flushLastEditedChapterUpdate();
    
    // 取消所有计时器
    _autoSaveTimer?.cancel();
    _batchSaveDebounceTimer?.cancel();
    _lastEditedChapterUpdateTimer?.cancel();
    
    // 取消生成流订阅
    _generationStreamSubscription?.cancel();
    
    return super.close();
  }

  // 批量保存多个场景内容的辅助方法
  Future<bool> _batchSaveScenes(List<Map<String, dynamic>> sceneUpdates, String novelId) async {
    if (sceneUpdates.isEmpty) return true;
    
    try {
      // 确保每个场景都有必要的字段
      final processedUpdates = sceneUpdates.map((scene) {
        // 确保每个场景都有novelId
        final updated = Map<String, dynamic>.from(scene);
        updated['novelId'] = novelId;
        
        // 确保每个场景都有chapterId和actId
        if (updated['chapterId'] == null || updated['chapterId'].toString().isEmpty) {
          AppLogger.w('EditorBloc/_batchSaveScenes', '场景缺少chapterId: ${updated['id']}，跳过该场景');
          return null; // 返回null表示这个场景无效
        }
        
        if (updated['actId'] == null || updated['actId'].toString().isEmpty) {
          AppLogger.w('EditorBloc/_batchSaveScenes', '场景缺少actId: ${updated['id']}，跳过该场景');
          return null; // 返回null表示这个场景无效
        }
        
        return updated;
      }).where((scene) => scene != null).cast<Map<String, dynamic>>().toList();
      
      if (processedUpdates.isEmpty) {
        AppLogger.w('EditorBloc/_batchSaveScenes', '处理后没有有效场景可以保存');
        return false;
      }
      
      // 记录一下要发送的数据，便于调试
      AppLogger.i('EditorBloc/_batchSaveScenes', '批量保存${processedUpdates.length}个场景，novelId=${novelId}');
      
      final result = await repository.batchSaveSceneContents(novelId, processedUpdates);
      if (result) {
        AppLogger.i('EditorBloc/_batchSaveScenes', '批量保存场景成功: ${processedUpdates.length}个场景');
      } else {
        AppLogger.e('EditorBloc/_batchSaveScenes', '批量保存场景失败');
      }
      return result;
    } catch (e) {
      AppLogger.e('EditorBloc/_batchSaveScenes', '批量保存场景出错', e);
      return false;
    }
  }



  // 将新加载的场景合并到当前小说结构中
  novel_models.Novel _mergeNewScenes(
    novel_models.Novel novel,
    Map<String, List<novel_models.Scene>> newScenes) {
    
    // 创建当前小说acts的深拷贝，以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      // 为每个Act创建深拷贝，以便修改其中的章节
      final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
        // 检查是否有该章节的新场景
        if (newScenes.containsKey(chapter.id)) {
          // 合并新场景和现有场景
          List<novel_models.Scene> existingScenes = List.from(chapter.scenes);
          List<novel_models.Scene> scenesToAdd = List.from(newScenes[chapter.id]!);
          
          // 创建场景ID到场景的映射，用于快速查找和合并
          Map<String, novel_models.Scene> sceneMap = {};
          for (var scene in existingScenes) {
            sceneMap[scene.id] = scene;
          }
          
          // 合并场景列表，优先使用新加载的场景
          for (var scene in scenesToAdd) {
            sceneMap[scene.id] = scene;
          }
          
          // 将合并后的场景转换回列表
          // 注意：这种基于Map的合并方式不保证场景的原始顺序。
          // 如果场景顺序很重要，并且API返回的scenesToAdd是有序的，
          // 或者场景对象自身没有可用于排序的字段（如order），
          // 则可能需要更复杂的合并逻辑来保留或重建正确的顺序。
          List<novel_models.Scene> mergedScenes = sceneMap.values.toList();
          
          // 创建更新后的章节
          return chapter.copyWith(scenes: mergedScenes);
        }
        // 如果没有该章节的新场景，则返回原章节
        return chapter;
      }).toList();
      
      // 返回更新后的Act
      return act.copyWith(chapters: updatedChapters);
    }).toList();
    
    // 在返回更新后的小说之前记录一些渲染相关的日志
    AppLogger.i('EditorBloc', '合并了${newScenes.length}个章节的场景，可能需要重新渲染');
    return novel.copyWith(acts: updatedActs);
  }

  // 更新小说内容的辅助方法
  novel_models.Novel _updateNovelContent(
    novel_models.Novel novel,
    String actId,
    String chapterId,
    String content) {
    
    // 创建当前小说acts的深拷贝以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      if (act.id == actId) {
        // 更新指定Act的章节
        final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
          if (chapter.id == chapterId) {
            // 找到指定章节，更新其第一个场景的内容
            if (chapter.scenes.isNotEmpty) {
              final List<novel_models.Scene> updatedScenes = List.from(chapter.scenes);
              final novel_models.Scene firstScene = updatedScenes.first;
              
              // 更新场景内容
              updatedScenes[0] = firstScene.copyWith(
                content: content,
              );
              
              return chapter.copyWith(scenes: updatedScenes);
            }
          }
          return chapter;
        }).toList();
        
        return act.copyWith(chapters: updatedChapters);
      }
      return act;
    }).toList();
    
    // 返回更新后的小说，同时更新最后编辑章节
    return novel.copyWith(
      acts: updatedActs,
      lastEditedChapterId: chapterId,
    );
  }

  // 更新小说场景的辅助方法
  novel_models.Novel _updateNovelScene(
    novel_models.Novel novel,
    String actId,
    String chapterId,
    novel_models.Scene updatedScene) {
    
    // 创建当前小说acts的深拷贝以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      if (act.id == actId) {
        // 更新指定Act的章节
        final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
          if (chapter.id == chapterId) {
            // 找到指定章节，更新其场景
            final List<novel_models.Scene> updatedScenes = chapter.scenes.map((scene) {
              if (scene.id == updatedScene.id) {
                // 返回更新后的场景
                return updatedScene;
              }
              return scene;
            }).toList();
            
            return chapter.copyWith(scenes: updatedScenes);
          }
          return chapter;
        }).toList();
        
        return act.copyWith(chapters: updatedChapters);
      }
      return act;
    }).toList();
    
    // 返回更新后的小说，同时更新最后编辑章节
    return novel.copyWith(
      acts: updatedActs,
      lastEditedChapterId: chapterId,
    );
  }

  // 更新场景内容的辅助方法
  novel_models.Novel _updateSceneContent(
    novel_models.Novel novel,
    String actId,
    String chapterId,
    String sceneId,
    String content) {
    
    // 创建当前小说acts的深拷贝以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      if (act.id == actId) {
        // 更新指定Act的章节
        final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
          if (chapter.id == chapterId) {
            // 找到指定章节，更新其场景
            final List<novel_models.Scene> updatedScenes = chapter.scenes.map((scene) {
              if (scene.id == sceneId) {
                // 更新场景内容
                return scene.copyWith(
                  content: content,
                );
              }
              return scene;
            }).toList();
            
            return chapter.copyWith(scenes: updatedScenes);
          }
          return chapter;
        }).toList();
        
        return act.copyWith(chapters: updatedChapters);
      }
      return act;
    }).toList();
    
    // 返回更新后的小说，同时更新最后编辑章节
    return novel.copyWith(
      acts: updatedActs,
      lastEditedChapterId: chapterId,
    );
  }

  // 设置活动章节
  Future<void> _onSetActiveChapter(
      SetActiveChapter event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      // 🚀 优化：检查状态是否真的需要改变
      bool needsUpdate = false;
      String? newActiveActId = currentState.activeActId;
      String? newActiveChapterId = currentState.activeChapterId;
      String? newActiveSceneId = currentState.activeSceneId;
      
      // 检查Act是否需要更新
      if (currentState.activeActId != event.actId) {
        needsUpdate = true;
        newActiveActId = event.actId;
      }
      
      // 检查Chapter是否需要更新
      if (currentState.activeChapterId != event.chapterId) {
        needsUpdate = true;
        newActiveChapterId = event.chapterId;
        
        // 🚀 新增：章节切换时，立即执行任何待处理的lastEditedChapterId更新
        await _flushLastEditedChapterUpdate();
        
        // 只有在章节发生变化时才查找第一个场景
        String? firstSceneId;
        for (final act in currentState.novel.acts) {
          if (act.id == event.actId) {
            for (final chapter in act.chapters) {
              if (chapter.id == event.chapterId && chapter.scenes.isNotEmpty) {
                firstSceneId = chapter.scenes.first.id;
                break;
              }
            }
            break;
          }
        }
        newActiveSceneId = firstSceneId;
      }
      
      // 🚀 只有在真的需要更新时才emit新状态
      if (needsUpdate) {
        // 记录日志
        AppLogger.i('EditorBloc', '设置活动章节: ${event.actId}/${event.chapterId}, 活动场景: $newActiveSceneId');
        
        emit(currentState.copyWith(
          activeActId: newActiveActId,
          activeChapterId: newActiveChapterId,
          activeSceneId: newActiveSceneId,
          lastUpdateSilent: event.silent, // 🚀 标记是否为静默更新
        ));
      } else {
        // 状态没有变化，记录日志但不emit
        AppLogger.v('EditorBloc', '跳过设置活动章节：状态未发生变化 ${event.actId}/${event.chapterId}');
      }
    }
  }

  // 设置活动场景
  Future<void> _onSetActiveScene(
      SetActiveScene event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      // 🚀 优化：检查状态是否真的需要改变
      bool needsUpdate = false;
      
      // 检查任何一个ID是否发生变化
      if (currentState.activeActId != event.actId ||
          currentState.activeChapterId != event.chapterId ||
          currentState.activeSceneId != event.sceneId) {
        needsUpdate = true;
      }
      
      // 🚀 只有在真的需要更新时才emit新状态
      if (needsUpdate) {
        AppLogger.i('EditorBloc', '设置活动场景: ${event.actId}/${event.chapterId}/${event.sceneId}');
        
        emit(currentState.copyWith(
          activeActId: event.actId,
          activeChapterId: event.chapterId,
          activeSceneId: event.sceneId,
          lastUpdateSilent: event.silent, // 🚀 标记是否为静默更新
        ));
      } else {
        // 状态没有变化，记录日志但不emit
        AppLogger.v('EditorBloc', '跳过设置活动场景：状态未发生变化 ${event.actId}/${event.chapterId}/${event.sceneId}');
      }
    }
  }

  // 🚀 新增：加载用户编辑器设置
  Future<void> _onLoadUserEditorSettings(
      LoadUserEditorSettings event, Emitter<EditorState> emit) async {
    try {
      AppLogger.i('EditorBloc', '开始加载用户编辑器设置: userId=${event.userId}');
      
      // 🚀 修正：EditorRepositoryImpl没有getUserEditorSettings方法
      // 需要使用NovelRepositoryImpl或从其他地方获取
      // 暂时使用默认设置，并添加TODO注释
      AppLogger.w('EditorBloc', 'TODO: 需要实现从NovelRepository获取用户编辑器设置的逻辑');
      
      // 使用默认设置
      const defaultSettings = EditorSettings();
      final settingsMap = defaultSettings.toMap();
      
      AppLogger.i('EditorBloc', '使用默认编辑器设置，字体大小: ${defaultSettings.fontSize}');
      
      // 更新当前状态的设置
      final currentState = state;
      if (currentState is EditorLoaded) {
        emit(currentState.copyWith(settings: settingsMap));
      } else {
        AppLogger.d('EditorBloc', '编辑器尚未加载完成，将在加载完成后应用设置');
      }
      
    } catch (e) {
      AppLogger.e('EditorBloc', '加载用户编辑器设置失败: ${e}');
      // 加载失败时使用默认设置
      const defaultSettings = EditorSettings();
      final defaultSettingsMap = defaultSettings.toMap();
      
      final currentState = state;
      if (currentState is EditorLoaded) {
        emit(currentState.copyWith(settings: defaultSettingsMap));
      }
    }
  }

  // 更新编辑器设置
  Future<void> _onUpdateSettings(
      UpdateEditorSettings event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      emit(currentState.copyWith(
        settings: event.settings,
      ));
      
      // 保存设置到本地存储
      try {
        await repository.saveEditorSettings(event.settings);
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '保存编辑器设置失败', e);
      }
    }
  }

  // 删除Scene
  Future<void> _onDeleteScene(
      DeleteScene event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        emit(currentState.copyWith(isSaving: true));
        
        AppLogger.i('Blocs/editor/editor_bloc',
            '删除场景: novelId=${event.novelId}, actId=${event.actId}, chapterId=${event.chapterId}, sceneId=${event.sceneId}');
        
        // 查找要删除的场景
        novel_models.Scene? sceneToDelete;
        novel_models.Chapter? parentChapter;
        novel_models.Act? parentAct;
        
        for (final act in currentState.novel.acts) {
          if (act.id == event.actId) {
            parentAct = act;
            for (final chapter in act.chapters) {
              if (chapter.id == event.chapterId) {
                parentChapter = chapter;
                for (final scene in chapter.scenes) {
                  if (scene.id == event.sceneId) {
                    sceneToDelete = scene;
                    break;
                  }
                }
                break;
              }
            }
            break;
          }
        }
        
        if (sceneToDelete == null || parentChapter == null || parentAct == null) {
          AppLogger.e('Blocs/editor/editor_bloc',
              '找不到要删除的场景: ${event.sceneId}');
          emit(currentState.copyWith(
            isSaving: false,
            errorMessage: '找不到要删除的场景',
          ));
          return;
        }
        
        // 创建不包含要删除场景的新场景列表
        final updatedScenes = parentChapter.scenes
            .where((scene) => scene.id != event.sceneId)
            .toList();
        
        // 如果该章节没有更多场景，可以考虑提示用户
        final bool isLastSceneInChapter = updatedScenes.isEmpty;
        
        // 更新章节
        final updatedChapter = parentChapter.copyWith(
          scenes: updatedScenes,
        );
        
        // 更新所在Act的章节列表
        final updatedChapters = parentAct.chapters.map((chapter) {
          if (chapter.id == event.chapterId) {
            return updatedChapter;
          }
          return chapter;
        }).toList();
        
        // 更新Act
        final updatedAct = parentAct.copyWith(
          chapters: updatedChapters,
        );
        
        // 更新小说的Acts列表
        final updatedActs = currentState.novel.acts.map((act) {
          if (act.id == event.actId) {
            return updatedAct;
          }
          return act;
        }).toList();
        
        // 创建更新后的小说模型
        final updatedNovel = currentState.novel.copyWith(
          acts: updatedActs,
          updatedAt: DateTime.now(),
        );
        
        // 清除该场景的所有保存请求
        _cleanupPendingSaveForScene(event.sceneId);
        
        // 如果删除的是当前活动场景，确定下一个活动场景
        String? newActiveSceneId = currentState.activeSceneId;
        if (currentState.activeSceneId == event.sceneId) {
          if (updatedScenes.isNotEmpty) {
            // 如果章节还有其他场景，选择第一个
            newActiveSceneId = updatedScenes.first.id;
          } else {
            // 章节没有场景了，将活动场景设为null
            newActiveSceneId = null;
          }
        }
        
        // Calculate chapter maps for the updated novel
        final chapterMaps = _calculateChapterMaps(updatedNovel);

        // 在UI上标记为正在处理
        emit(currentState.copyWith(
          novel: updatedNovel,
          activeSceneId: newActiveSceneId,
          isDirty: true,
          isSaving: true,
          chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
          chapterToActMap: chapterMaps.chapterToActMap, // Added
        ));
        
        // 调用API删除场景
        final success = await repository.deleteScene(
          event.novelId,
          event.actId,
          event.chapterId,
          event.sceneId,
        );
        
        if (!success) {
          throw Exception('删除场景失败');
        }
        
        // 保存成功后，更新状态
        emit(currentState.copyWith(
          novel: updatedNovel,
          activeSceneId: newActiveSceneId,
          isDirty: false,
          isSaving: false,
          lastSaveTime: DateTime.now(),
          chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Ensure maps are consistent
          chapterToActMap: chapterMaps.chapterToActMap,       // Ensure maps are consistent
        ));
        
        // 持久化：确保删除后的小说结构写回本地缓存
        await repository.saveNovel(updatedNovel);
        
        AppLogger.i('Blocs/editor/editor_bloc',
            '场景删除成功: ${event.sceneId}');
        
        // 如果删除的是最后一个场景，提示用户考虑添加新场景
        if (isLastSceneInChapter) {
          AppLogger.i('Blocs/editor/editor_bloc',
              '章节 ${event.chapterId} 现在没有场景了');
          // 这里可以添加一些逻辑来提示用户添加场景
        }
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '删除场景失败', e);
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '删除场景失败: ${e.toString()}',
        ));
      }
    }
  }

  // 在场景删除后清理该场景的保存请求
  void _cleanupPendingSaveForScene(String sceneId) {
    final keysToRemove = <String>[];
    
    _pendingSaveScenes.forEach((key, data) {
      if (data['sceneId'] == sceneId) {
        keysToRemove.add(key);
      }
    });
    
    for (final key in keysToRemove) {
      _pendingSaveScenes.remove(key);
      AppLogger.i('EditorBloc', '已从保存队列中移除场景: ${sceneId}');
    }
  }

  Future<void> _onAddNewAct(
      AddNewAct event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 开始保存状态
        emit(currentState.copyWith(isSaving: true));
        
        AppLogger.i('EditorBloc/_onAddNewAct', '开始添加新Act: title=${event.title}');
        
        // 调用API创建新Act
        final updatedNovel = await repository.addNewAct(
          novelId,
          event.title,
        );
        
        if (updatedNovel == null) {
          AppLogger.e('EditorBloc/_onAddNewAct', '添加新Act失败，API返回null');
          emit(currentState.copyWith(
            isSaving: false,
            errorMessage: '添加新Act失败：无法获取更新后的小说数据',
          ));
          return;
        }
        
        // 检查是否成功添加了新Act
        if (updatedNovel.acts.length > currentState.novel.acts.length) {
          AppLogger.i('EditorBloc/_onAddNewAct', 
              '成功添加新Act：之前${currentState.novel.acts.length}个，现在${updatedNovel.acts.length}个');
          
          // 设置新添加的Act为活动Act
          final newAct = updatedNovel.acts.last;
          
          // Calculate chapter maps for the updated novel
          final chapterMaps = _calculateChapterMaps(updatedNovel);

          // 发出更新状态
          emit(currentState.copyWith(
            novel: updatedNovel,
            isSaving: false,
            isDirty: false,
            activeActId: newAct.id,
            // 如果新Act有章节，设置第一个章节为活动章节
            activeChapterId: newAct.chapters.isNotEmpty ? newAct.chapters.first.id : null,
            // 清除活动场景
            activeSceneId: null,
            chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
            chapterToActMap: chapterMaps.chapterToActMap, // Added
          ));
          
          AppLogger.i('EditorBloc/_onAddNewAct', '已更新UI状态，设置新Act为活动Act: ${newAct.id}');
        } else {
          AppLogger.w('EditorBloc/_onAddNewAct', 
              '添加Act可能失败：之前${currentState.novel.acts.length}个，现在${updatedNovel.acts.length}个');
          
          // Calculate chapter maps even if the addition might have issues, to reflect current state
          final chapterMaps = _calculateChapterMaps(updatedNovel);

          // 仍然更新状态以刷新UI
          emit(currentState.copyWith(
            novel: updatedNovel,
            isSaving: false,
            errorMessage: 'Act可能未成功添加，请检查网络连接',
            chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
            chapterToActMap: chapterMaps.chapterToActMap, // Added
          ));
        }
      } catch (e) {
        AppLogger.e('EditorBloc/_onAddNewAct', '添加新Act过程中发生异常', e);
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '添加新Act失败: ${e.toString()}',
        ));
      }
    }
  }

  /// 添加新章节
  Future<void> _onAddNewChapter(
      AddNewChapter event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 开始保存状态
        emit(currentState.copyWith(isSaving: true));
        
        AppLogger.i('EditorBloc/_onAddNewChapter', 
            '开始添加新Chapter: novelId=${event.novelId}, actId=${event.actId}, title=${event.title}');
        
        // 调用API创建新Chapter
        final updatedNovel = await repository.addNewChapter(
          event.novelId,
          event.actId,
          event.title,
        );
        
        if (updatedNovel == null) {
          AppLogger.e('EditorBloc/_onAddNewChapter', '添加新Chapter失败，API返回null');
          emit(currentState.copyWith(
            isSaving: false,
            errorMessage: '添加新Chapter失败：无法获取更新后的小说数据',
          ));
          return;
        }
        
        // 获取更新后Act中的新章节
        novel_models.Act? updatedAct;
        novel_models.Chapter? newChapter;
        
        for (final act in updatedNovel.acts) {
          if (act.id == event.actId) {
            updatedAct = act;
            if (act.chapters.isNotEmpty) {
              // 通常新章节会被添加到末尾
              newChapter = act.chapters.last;
            }
            break;
          }
        }
        
        if (updatedAct == null || newChapter == null) {
          AppLogger.w('EditorBloc/_onAddNewChapter', 
              '无法确定新添加的章节，使用更新后的小说数据');
          
          // Calculate chapter maps for the updated novel
          final chapterMaps = _calculateChapterMaps(updatedNovel);
          // 仍然更新状态
          emit(currentState.copyWith(
            novel: updatedNovel,
            isSaving: false,
            isDirty: false,
            chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
            chapterToActMap: chapterMaps.chapterToActMap, // Added
          ));
          return;
        }
        
        AppLogger.i('EditorBloc/_onAddNewChapter', 
            '成功添加新章节: actId=${updatedAct.id}, chapterId=${newChapter.id}');
        
        // Calculate chapter maps for the updated novel
        final chapterMaps = _calculateChapterMaps(updatedNovel);

        // 发出更新状态，并设置新章节为活动章节
        emit(currentState.copyWith(
          novel: updatedNovel,
          isSaving: false,
          isDirty: false,
          activeActId: updatedAct.id,
          activeChapterId: newChapter.id,
          focusChapterId: newChapter.id, // <--- 确保设置焦点到新章节
          // 清除活动场景，因为新章节还没有场景
          activeSceneId: null,
          chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
          chapterToActMap: chapterMaps.chapterToActMap, // Added
        ));
        
        AppLogger.i('EditorBloc/_onAddNewChapter', 
            '已更新UI状态，设置新章节为活动章节: ${newChapter.id}');
      } catch (e) {
        AppLogger.e('EditorBloc/_onAddNewChapter', '添加新章节过程中发生异常', e);
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '添加新章节失败: ${e.toString()}',
        ));
      }
    }
  }

  // 修改SaveSceneContent处理器也使用相同的JSON验证
  Future<void> _onSaveSceneContent(
      SaveSceneContent event, Emitter<EditorState> emit) async {
    AppLogger.i('EditorBloc',
        '接收到场景内容更新 - 场景ID: ${event.sceneId}, 字数: ${event.wordCount}');
    final currentState = state;
    if (currentState is EditorLoaded) {

      try {
        // 🚀 修复：立即更新状态为正在保存
        emit(currentState.copyWith(isSaving: true));

        // 找到要更新的章节和场景
        final chapter = currentState.novel.acts
            .firstWhere(
                (act) => act.id == event.actId,
                orElse: () => throw Exception('找不到指定的Act'))
            .chapters
            .firstWhere(
                (chapter) => chapter.id == event.chapterId,
                orElse: () => throw Exception('找不到指定的Chapter'));

        // 获取场景摘要（保持不变）
        final sceneSummary =
            chapter.scenes.firstWhere((s) => s.id == event.sceneId).summary;

        // 确保内容是有效的Quill JSON格式
        final String validContent = _ensureValidQuillJson(event.content);

        // 仅保存场景内容（细粒度更新）- 根据参数决定是否同步到服务器
        final updatedScene = await repository.saveSceneContent(
          event.novelId,
          event.actId,
          event.chapterId,
          event.sceneId,
          validContent, // 使用验证后的内容
          event.wordCount,
          sceneSummary,
          localOnly: event.localOnly, // 新增参数：是否仅保存到本地
        );

        // 更新小说里的场景信息
        final finalNovel = _updateNovelScene(
          currentState.novel,
          event.actId,
          event.chapterId,
          updatedScene,
        );

        // 更新最后编辑的章节ID
        var novelWithLastEdited = finalNovel;
        if (finalNovel.lastEditedChapterId != event.chapterId) {
          novelWithLastEdited = finalNovel.copyWith(
            lastEditedChapterId: event.chapterId,
          );
        }

        AppLogger.i('EditorBloc',
            '场景保存成功，更新状态 - 场景ID: ${event.sceneId}, 最终字数: ${updatedScene.wordCount}');

        // 仅当需要同步到服务器时才更新lastEditedChapterId
        if (!event.localOnly && 
            novelWithLastEdited.lastEditedChapterId != currentState.novel.lastEditedChapterId) {
          AppLogger.i('EditorBloc', '使用防抖机制更新最后编辑章节ID: ${novelWithLastEdited.lastEditedChapterId}');
          // 使用防抖机制更新，避免频繁请求
          _updateLastEditedChapterWithDebounce(novelWithLastEdited.lastEditedChapterId!);
        }

        // 🚀 修复：轻量的isDirty状态管理
        // 本地保存成功后立即清除isDirty，提供即时反馈
        // 如果是同步到服务器，则更新lastSaveTime
        emit(currentState.copyWith(
          novel: novelWithLastEdited,
          isDirty: false, // 已保存
          isSaving: false,
          lastSaveTime: DateTime.now(), // 无论是否同步到服务器都更新时间戳，便于UI显示
        ));
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '保存场景内容失败', e);
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '保存场景内容失败: ${e.toString()}',
        ));
      }
    }
  }

  // 添加新Scene
  Future<void> _onAddNewScene(
      AddNewScene event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      emit(currentState.copyWith(isSaving: true));

      try {
        AppLogger.i('EditorBloc', '添加新场景 - actId: ${event.actId}, chapterId: ${event.chapterId}');
        
        // 1. 创建新场景
        final newScene = novel_models.Scene.createDefault("scene_${DateTime.now().millisecondsSinceEpoch}");
        
        // 2. 添加场景到API
        final addedScene = await repository.addScene(
          novelId,
          event.actId,
          event.chapterId,
          newScene,
        );
        
        if (addedScene == null) {
          throw Exception('添加场景失败，API返回为空');
        }
        
        // 3. 在本地模型中找到对应章节并添加场景
        final updatedNovel = _addSceneToNovel(
          currentState.novel,
          event.actId,
          event.chapterId,
          addedScene,
        );
        
        // 4. 更新状态
        emit(currentState.copyWith(
          novel: updatedNovel,
          isSaving: false,
          isDirty: false,
          // 立即将新场景设置为活动场景
          activeActId: event.actId,
          activeChapterId: event.chapterId,
          activeSceneId: addedScene.id,
        ));
        
        // 持久化：避免后续基于旧缓存的结构操作覆盖新增场景
        await repository.saveNovel(updatedNovel);
        
        AppLogger.i('EditorBloc', '场景添加成功，ID: ${addedScene.id}');
      } catch (e) {
        AppLogger.e('EditorBloc', '添加场景失败: ${e.toString()}');
        emit(currentState.copyWith(
          isSaving: false,
          errorMessage: '添加场景失败: ${e.toString()}',
        ));
      }
    }
  }
  
  // 辅助方法：将场景添加到小说模型中
  novel_models.Novel _addSceneToNovel(
    novel_models.Novel novel,
    String actId,
    String chapterId,
    novel_models.Scene newScene,
  ) {
    // 创建当前小说acts的深拷贝以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      if (act.id == actId) {
        // 更新指定Act的章节
        final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
          if (chapter.id == chapterId) {
            // 找到指定章节，添加场景
            final List<novel_models.Scene> updatedScenes = List.from(chapter.scenes)
              ..add(newScene);
            
            return chapter.copyWith(scenes: updatedScenes);
          }
          return chapter;
        }).toList();
        
        return act.copyWith(chapters: updatedChapters);
      }
      return act;
    }).toList();
    
    // 返回更新后的小说，同时更新最后编辑章节
    return novel.copyWith(
      acts: updatedActs,
      lastEditedChapterId: chapterId,
    );
  }

  // 删除Chapter
  Future<void> _onDeleteChapter(
      DeleteChapter event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      // 保存原始小说数据，以便在失败时恢复
      final originalNovel = currentState.novel;

      // 查找章节在哪个Act中以及对应的索引
      int actIndex = -1;
      int chapterIndex = -1;
      novel_models.Act? act;

      for (int i = 0; i < originalNovel.acts.length; i++) {
        final currentAct = originalNovel.acts[i];
        if (currentAct.id == event.actId) {
          actIndex = i;
          act = currentAct;
          for (int j = 0; j < currentAct.chapters.length; j++) {
            if (currentAct.chapters[j].id == event.chapterId) {
              chapterIndex = j;
              break;
            }
          }
          break;
        }
      }

      if (actIndex == -1 || chapterIndex == -1 || act == null) {
        AppLogger.e('Blocs/editor/editor_bloc',
            '找不到要删除的章节: ${event.chapterId}');
        // 保持当前状态，但显示错误信息
        emit(currentState.copyWith(errorMessage: '找不到要删除的章节'));
        return;
      }

      // 确定删除后的下一个活动Chapter ID
      String? nextActiveChapterId;
      novel_models.Chapter? nextActiveChapter;
      if (act.chapters.length > 1) {
        // 如果删除后Act还有其他章节
        if (chapterIndex > 0) {
          // 优先选前一个章节
          nextActiveChapter = act.chapters[chapterIndex - 1];
        } else {
          // 否则选后一个章节
          nextActiveChapter = act.chapters[1];
        }
        nextActiveChapterId = nextActiveChapter.id;
      } else if (originalNovel.acts.length > 1) {
        // 如果当前Act没有其他章节了，但还有其他Act
        // 尝试选择前一个Act的最后一个章节或后一个Act的第一个章节
        int nextActIndex;
        if (actIndex > 0) {
          nextActIndex = actIndex - 1;
          final nextAct = originalNovel.acts[nextActIndex];
          if (nextAct.chapters.isNotEmpty) {
            nextActiveChapter = nextAct.chapters.last;
            nextActiveChapterId = nextActiveChapter.id;
          }
        } else if (actIndex < originalNovel.acts.length - 1) {
          nextActIndex = actIndex + 1;
          final nextAct = originalNovel.acts[nextActIndex];
          if (nextAct.chapters.isNotEmpty) {
            nextActiveChapter = nextAct.chapters.first;
            nextActiveChapterId = nextActiveChapter.id;
          }
        }
      }

      // 更新本地小说模型 (不可变方式)
      final updatedChapters = List<novel_models.Chapter>.from(act.chapters)
        ..removeAt(chapterIndex);
      final updatedAct = act.copyWith(chapters: updatedChapters);
      final updatedActs = List<novel_models.Act>.from(originalNovel.acts)
        ..[actIndex] = updatedAct;
      final updatedNovel = originalNovel.copyWith(
        acts: updatedActs,
        updatedAt: DateTime.now(),
      );

      // Calculate chapter maps for the updated novel state
      final chapterMaps = _calculateChapterMaps(updatedNovel);

      // 更新UI状态为 "正在保存"，并设置新的活动章节
      emit(currentState.copyWith(
        novel: updatedNovel, // 显示删除后的状态
        isDirty: true, // 标记为脏
        isSaving: true, // 标记正在保存
        // 更新活动章节ID
        activeChapterId: currentState.activeChapterId == event.chapterId
            ? nextActiveChapterId
            : currentState.activeChapterId,
        // 如果活动章节变了，也要更新活动Act
        activeActId: (currentState.activeChapterId == event.chapterId && nextActiveChapter != null)
            ? (nextActiveChapter != null ? _findActIdForChapter(originalNovel, nextActiveChapterId!) : currentState.activeActId)
            : currentState.activeActId,
        // 如果删除的是当前活动章节，把活动场景设为null
        activeSceneId: currentState.activeChapterId == event.chapterId
            ? null
            : currentState.activeSceneId,
        chapterGlobalIndices: chapterMaps.chapterGlobalIndices, // Added
        chapterToActMap: chapterMaps.chapterToActMap, // Added
      ));

      try {
        // 清理该章节的所有场景保存请求
        _cleanupPendingSavesForChapter(event.chapterId);
        
        // 使用细粒度方法删除章节
        final success = await repository.deleteChapterFine(
          event.novelId, 
          event.actId, 
          event.chapterId
        );
        
        if (!success) {
          throw Exception('删除章节失败');
        }

        // 保存成功后，更新状态为已保存
        emit((state as EditorLoaded).copyWith(
          isDirty: false,
          isSaving: false,
          lastSaveTime: DateTime.now(),
          // chapterGlobalIndices and chapterToActMap are already part of the state from the previous emit
        ));
        
        // 持久化：确保章节删除后的小说结构写回本地缓存
        await repository.saveNovel(updatedNovel);
        AppLogger.i('Blocs/editor/editor_bloc',
            '章节删除成功: ${event.chapterId}');
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '删除章节失败', e);
        // 删除失败，恢复原始数据
        // Recalculate maps for the original novel if rolling back
        final originalChapterMaps = _calculateChapterMaps(originalNovel);
        emit((state as EditorLoaded).copyWith(
          novel: originalNovel,
          isSaving: false,
          errorMessage: '删除章节失败: ${e.toString()}',
          activeActId: currentState.activeActId,
          activeChapterId: currentState.activeChapterId,
          activeSceneId: currentState.activeSceneId,
          chapterGlobalIndices: originalChapterMaps.chapterGlobalIndices, // Added for rollback
          chapterToActMap: originalChapterMaps.chapterToActMap, // Added for rollback
        ));
      }
    }
  }

  // 删除Act（卷）
  Future<void> _onDeleteAct(
      DeleteAct event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      final originalNovel = currentState.novel;
      try {
        // 1) 本地先行更新：移除该Act
        final updatedActs = List<novel_models.Act>.from(originalNovel.acts)
          ..removeWhere((a) => a.id == event.actId);
        final updatedNovel = originalNovel.copyWith(
          acts: updatedActs,
          updatedAt: DateTime.now(),
        );

        // 计算章节映射
        final chapterMaps = _calculateChapterMaps(updatedNovel);

        // 2) 先更新UI，标记为保存中
        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: true,
          isSaving: true,
          // 如果当前活动Act被删，重置活动指针
          activeActId: currentState.activeActId == event.actId ? (updatedActs.isNotEmpty ? updatedActs.first.id : null) : currentState.activeActId,
          activeChapterId: currentState.activeActId == event.actId ? (updatedActs.isNotEmpty && updatedActs.first.chapters.isNotEmpty ? updatedActs.first.chapters.first.id : null) : currentState.activeChapterId,
          activeSceneId: currentState.activeActId == event.actId ? null : currentState.activeSceneId,
          chapterGlobalIndices: chapterMaps.chapterGlobalIndices,
          chapterToActMap: chapterMaps.chapterToActMap,
        ));

        // 3) 调用细粒度删除API
        final success = await repository.deleteActFine(event.novelId, event.actId);
        if (!success) {
          throw Exception('删除卷失败');
        }

        // 4) 持久化并完成状态
        await repository.saveNovel(updatedNovel);
        emit((state as EditorLoaded).copyWith(
          isDirty: false,
          isSaving: false,
          lastSaveTime: DateTime.now(),
        ));
      } catch (e) {
        AppLogger.e('EditorBloc/_onDeleteAct', '删除卷失败', e);
        // 回滚
        final originalMaps = _calculateChapterMaps(originalNovel);
        emit((state as EditorLoaded).copyWith(
          novel: originalNovel,
          isSaving: false,
          errorMessage: '删除卷失败: ${e.toString()}',
          chapterGlobalIndices: originalMaps.chapterGlobalIndices,
          chapterToActMap: originalMaps.chapterToActMap,
        ));
      }
    }
  }

  // 在章节删除后清理该章节的所有场景保存请求
  void _cleanupPendingSavesForChapter(String chapterId) {
    final keysToRemove = <String>[];
    
    _pendingSaveScenes.forEach((key, data) {
      if (data['chapterId'] == chapterId) {
        keysToRemove.add(key);
      }
    });
    
    for (final key in keysToRemove) {
      _pendingSaveScenes.remove(key);
      AppLogger.i('EditorBloc', '已从保存队列中移除章节${chapterId}的场景: ${key}');
    }
    
    if (keysToRemove.isNotEmpty) {
      AppLogger.i('EditorBloc', '已清理${keysToRemove.length}个属于已删除章节${chapterId}的场景保存请求');
    }
  }

  // 实现更新可见范围的处理
  Future<void> _onUpdateVisibleRange(
      UpdateVisibleRange event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      emit(currentState.copyWith(
        visibleRange: [event.startIndex, event.endIndex],
      ));
    }
  }

  // 设置焦点章节 - 仅更新焦点，不影响活动场景
  Future<void> _onSetFocusChapter(
      SetFocusChapter event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      AppLogger.i('EditorBloc', '设置焦点章节: ${event.chapterId} (仅更新焦点，不影响活动场景)');
      
      emit(currentState.copyWith(
        focusChapterId: event.chapterId,
        // 不更新activeActId、activeChapterId和activeSceneId
      ));
    }
  }

  // 处理重置Act加载状态标志的事件
  void _onResetActLoadingFlags(ResetActLoadingFlags event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 重置边界标志
    emit(currentState.copyWith(
      hasReachedEnd: false,
      hasReachedStart: false,
    ));
    
    AppLogger.i('Blocs/editor/editor_bloc', '已重置Act加载标志: hasReachedEnd=false, hasReachedStart=false');
  }
  
  void _onSetActLoadingFlags(SetActLoadingFlags event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 只更新提供了值的标志
    bool hasReachedEnd = currentState.hasReachedEnd;
    bool hasReachedStart = currentState.hasReachedStart;
    
    if (event.hasReachedEnd != null) {
      hasReachedEnd = event.hasReachedEnd!;
    }
    
    if (event.hasReachedStart != null) {
      hasReachedStart = event.hasReachedStart!;
    }
    
    // 更新状态
    emit(currentState.copyWith(
      hasReachedEnd: hasReachedEnd,
      hasReachedStart: hasReachedStart,
    ));
    
    AppLogger.i('Blocs/editor/editor_bloc', 
        '已设置Act加载标志: hasReachedEnd=${hasReachedEnd}, hasReachedStart=${hasReachedStart}');
  }

  // 更新章节标题的事件处理方法
  Future<void> _onUpdateChapterTitle(
      UpdateChapterTitle event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 更新标题逻辑
        final acts = currentState.novel.acts.map((act) {
          if (act.id == event.actId) {
            final chapters = act.chapters.map((chapter) {
              if (chapter.id == event.chapterId) {
                return chapter.copyWith(title: event.title);
              }
              return chapter;
            }).toList();
            return act.copyWith(chapters: chapters);
          }
          return act;
        }).toList();

        final updatedNovel = currentState.novel.copyWith(acts: acts);

        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: true,
          lastUpdateSilent: true,
        ));
        
        // 本地持久化，避免随后基于旧缓存的结构操作覆盖标题变更
        await repository.saveNovel(updatedNovel);
        
        // 保存到服务器
        final success = await repository.updateChapterTitle(
          novelId,
          event.actId,
          event.chapterId,
          event.title,
        );
        
        if (!success) {
          AppLogger.e('Blocs/editor/editor_bloc', '更新Chapter标题失败');
        }
        
        // 修复：不能基于旧的 currentState 再次 emit，否则会把 updatedNovel 覆盖回旧状态
        // 使用最新的 state 作为基准仅更新 isDirty 标记
        if (state is EditorLoaded) {
          emit((state as EditorLoaded).copyWith(isDirty: false));
        }
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '更新Chapter标题失败', e);
        emit(currentState.copyWith(
          errorMessage: '更新Chapter标题失败: ${e.toString()}',
        ));
      }
    }
  }

  // 更新卷标题的事件处理方法
  Future<void> _onUpdateActTitle(
      UpdateActTitle event, Emitter<EditorState> emit) async {
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 更新标题逻辑
        final acts = currentState.novel.acts.map((act) {
          if (act.id == event.actId) {
            return act.copyWith(title: event.title);
          }
          return act;
        }).toList();

        final updatedNovel = currentState.novel.copyWith(acts: acts);

        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: true,
          lastUpdateSilent: true,
        ));
        
        // 本地持久化，避免随后基于旧缓存的结构操作覆盖标题变更
        await repository.saveNovel(updatedNovel);
        
        // 保存到服务器
        final success = await repository.updateActTitle(
          novelId,
          event.actId,
          event.title,
        );
        
        if (!success) {
          AppLogger.e('Blocs/editor/editor_bloc', '更新Act标题失败');
        }
        
        // 修复：不能基于旧的 currentState 再次 emit，否则会把 updatedNovel 覆盖回旧状态
        // 使用最新的 state 作为基准仅更新 isDirty 标记
        if (state is EditorLoaded) {
          emit((state as EditorLoaded).copyWith(isDirty: false));
        }
      } catch (e) {
        AppLogger.e('Blocs/editor/editor_bloc', '更新Act标题失败', e);
        emit(currentState.copyWith(
          errorMessage: '更新Act标题失败: ${e.toString()}',
        ));
      }
    }
  }

  // 处理GenerateSceneFromSummaryRequested事件
  Future<void> _onGenerateSceneFromSummaryRequested(
      GenerateSceneFromSummaryRequested event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 取消之前的生成订阅（如果有）
    if (_generationStreamSubscription != null) {
      await _generationStreamSubscription!.cancel();
      _generationStreamSubscription = null;
    }
    
    // 更新状态为正在生成
    emit(currentState.copyWith(
      aiSceneGenerationStatus: AIGenerationStatus.generating,
      generatedSceneContent: '',
      aiGenerationError: null,
    ));
    
    try {
      AppLogger.i('EditorBloc/_onGenerateSceneFromSummaryRequested', 
        '开始从摘要生成场景，摘要长度：${event.summary.length}, 流式生成：${event.useStreamingMode}');
      
      if (event.useStreamingMode) {
        // 流式生成模式
        final stream = await repository.generateSceneFromSummaryStream(
          event.novelId,
          event.summary,
          chapterId: event.chapterId,
          additionalInstructions: event.styleInstructions,
        );
        
        String accumulatedContent = '';
        
        _generationStreamSubscription = stream.listen(
          (chunk) {
            // 累加接收到的内容
            accumulatedContent += chunk;
            // 发送更新生成内容事件
            add(UpdateGeneratedSceneContent(accumulatedContent));
          },
          onDone: () {
            // 生成完成
            add(SceneGenerationCompleted(accumulatedContent));
            _generationStreamSubscription = null;
          },
          onError: (error) {
            // 生成出错
            AppLogger.e('EditorBloc/_onGenerateSceneFromSummaryRequested', '流式生成场景失败', error);
            add(SceneGenerationFailed(error.toString()));
            _generationStreamSubscription = null;
          },
        );
      } else {
        // 非流式生成模式
        final result = await repository.generateSceneFromSummary(
          event.novelId,
          event.summary,
          chapterId: event.chapterId,
          additionalInstructions: event.styleInstructions,
        );
        
        // 生成完成
        add(SceneGenerationCompleted(result));
      }
    } catch (e) {
      // 捕获并处理所有异常
      AppLogger.e('EditorBloc/_onGenerateSceneFromSummaryRequested', '生成场景失败', e);
      add(SceneGenerationFailed(e.toString()));
    }
  }

  // 处理更新生成内容事件
  void _onUpdateGeneratedSceneContent(
      UpdateGeneratedSceneContent event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 更新生成的内容
    emit(currentState.copyWith(
      generatedSceneContent: event.content,
    ));
  }

  // 处理生成完成事件
  void _onSceneGenerationCompleted(
      SceneGenerationCompleted event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 更新状态为生成完成
    emit(currentState.copyWith(
      aiSceneGenerationStatus: AIGenerationStatus.completed,
      generatedSceneContent: event.content,
    ));
    
    AppLogger.i('EditorBloc/_onSceneGenerationCompleted', '场景生成完成，生成内容长度：${event.content.length}');
  }

  // 处理生成失败事件
  void _onSceneGenerationFailed(
      SceneGenerationFailed event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 更新状态为生成失败
    emit(currentState.copyWith(
      aiSceneGenerationStatus: AIGenerationStatus.failed,
      aiGenerationError: event.error,
    ));
    
    AppLogger.e('EditorBloc/_onSceneGenerationFailed', '场景生成失败，错误：${event.error}');
  }

  // 处理停止生成事件
  Future<void> _onStopSceneGeneration(
      StopSceneGeneration event, Emitter<EditorState> emit) async {
    // 取消订阅
    if (_generationStreamSubscription != null) {
      await _generationStreamSubscription!.cancel();
      _generationStreamSubscription = null;
    }
    
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 更新状态为初始状态
    emit(currentState.copyWith(
      aiSceneGenerationStatus: AIGenerationStatus.initial,
    ));
    
    AppLogger.i('EditorBloc/_onStopSceneGeneration', '场景生成已取消');
  }

  // 处理设置待处理摘要事件
  void _onSetPendingSummary(
      SetPendingSummary event, Emitter<EditorState> emit) {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 设置待处理的摘要
    emit(currentState.copyWith(
      pendingSummary: event.summary,
    ));
    
    AppLogger.d('EditorBloc/_onSetPendingSummary', '已设置待处理摘要，长度：${event.summary.length}');
  }

  // 强制保存场景内容处理器 - 用于SceneEditor dispose时立即保存
  Future<void> _onForceSaveSceneContent(
      ForceSaveSceneContent event, Emitter<EditorState> emit) async {
    AppLogger.i('EditorBloc/_onForceSaveSceneContent',
        '强制保存场景内容 - 场景ID: ${event.sceneId}, 字数: ${event.wordCount ?? "自动计算"}');
    
    final currentState = state;
    if (currentState is EditorLoaded) {
      try {
        // 验证场景是否存在
        bool sceneExists = false;
        novel_models.Scene? existingScene;
        
        for (final act in currentState.novel.acts) {
          if (act.id == event.actId) {
            for (final chapter in act.chapters) {
              if (chapter.id == event.chapterId) {
                for (final scene in chapter.scenes) {
                  if (scene.id == event.sceneId) {
                    sceneExists = true;
                    existingScene = scene;
                    break;
                  }
                }
                break;
              }
            }
            break;
          }
        }
        
        if (!sceneExists || existingScene == null) {
          AppLogger.w('EditorBloc/_onForceSaveSceneContent', 
              '强制保存失败：场景不存在或已被删除 ${event.sceneId}');
          return;
        }
        
        // 计算字数（如果未提供）
        final int calculatedWordCount = event.wordCount != null 
            ? int.tryParse(event.wordCount!) ?? WordCountAnalyzer.countWords(event.content)
            : WordCountAnalyzer.countWords(event.content);
            
        // 使用提供的摘要或保持原有摘要
        final sceneSummary = event.summary != null 
            ? novel_models.Summary(
                id: '${event.sceneId}_summary',
                content: event.summary!,
              )
            : existingScene.summary;
        
        // 确保内容是有效的Quill JSON格式
        final String validContent = _ensureValidQuillJson(event.content);
        
        // 直接更新小说模型中的场景内容
        final updatedNovel = _updateSceneContentAndSummary(
          currentState.novel,
          event.actId,
          event.chapterId,
          event.sceneId,
          validContent,
          calculatedWordCount,
          sceneSummary,
        );
        
        // 立即发出更新状态，包含新的场景内容
        emit(currentState.copyWith(
          novel: updatedNovel,
          isDirty: true, // 标记为脏，因为有未保存的更改
          lastUpdateSilent: true, // 设置为静默更新，避免触发大量UI刷新
        ));
        
        // 异步保存到本地存储（不等待完成）
        _saveSceneToLocalStorageAsync(
          event.novelId,
          event.actId,
          event.chapterId,
          event.sceneId,
          validContent,
          calculatedWordCount.toString(),
          sceneSummary,
        );
        
        AppLogger.i('EditorBloc/_onForceSaveSceneContent',
            '强制保存完成 - 场景ID: ${event.sceneId}, 字数: $calculatedWordCount');
            
      } catch (e) {
        AppLogger.e('EditorBloc/_onForceSaveSceneContent', '强制保存场景内容失败', e);
        // 对于强制保存，我们不更新错误状态，避免影响UI
      }
    }
  }
  
  // 异步保存场景到本地存储
  void _saveSceneToLocalStorageAsync(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
    String content,
    String wordCount,
    novel_models.Summary summary,
  ) {
    // 使用异步方法，不阻塞主线程
    Future.microtask(() async {
      try {
        await repository.saveSceneContent(
          novelId,
          actId,
          chapterId,
          sceneId,
          content,
          wordCount,
          summary,
          localOnly: true, // 仅保存到本地
        );
        
        AppLogger.d('EditorBloc/_saveSceneToLocalStorageAsync',
            '异步本地保存完成 - 场景ID: $sceneId');
      } catch (e) {
        AppLogger.e('EditorBloc/_saveSceneToLocalStorageAsync', 
            '异步本地保存失败 - 场景ID: $sceneId', e);
      }
    });
  }
  
  // 更新场景内容和摘要的辅助方法
  novel_models.Novel _updateSceneContentAndSummary(
    novel_models.Novel novel,
    String actId,
    String chapterId,
    String sceneId,
    String content,
    int wordCount,
    novel_models.Summary summary,
  ) {
    // 创建当前小说acts的深拷贝以便修改
    final List<novel_models.Act> updatedActs = novel.acts.map((act) {
      if (act.id == actId) {
        // 更新指定Act的章节
        final List<novel_models.Chapter> updatedChapters = act.chapters.map((chapter) {
          if (chapter.id == chapterId) {
            // 找到指定章节，更新其场景
            final List<novel_models.Scene> updatedScenes = chapter.scenes.map((scene) {
              if (scene.id == sceneId) {
                // 更新场景内容、字数和摘要
                return scene.copyWith(
                  content: content,
                  wordCount: wordCount,
                  summary: summary,
                  lastEdited: DateTime.now(),
                );
              }
              return scene;
            }).toList();
            
            return chapter.copyWith(scenes: updatedScenes);
          }
          return chapter;
        }).toList();
        
        return act.copyWith(chapters: updatedChapters);
      }
      return act;
    }).toList();
    
    // 返回更新后的小说，同时更新最后编辑章节
    return novel.copyWith(
      acts: updatedActs,
      lastEditedChapterId: chapterId,
      updatedAt: DateTime.now(),
    );
  }
  
  // 🚀 新增：Plan视图事件处理方法
  
  /// 切换到Plan视图模式
  Future<void> _onSwitchToPlanView(
      SwitchToPlanView event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onSwitchToPlanView', '切换到Plan视图模式（直接使用已有数据）');
    
    // 直接设置Plan视图模式，使用已有的小说数据
    // 无需重新加载数据，因为EditorBloc已经包含了完整的小说结构
    emit(currentState.copyWith(
      isPlanViewMode: true,
      planModificationSource: null, // 清除之前的修改标记
      lastPlanModifiedTime: DateTime.now(),
    ));
    
    AppLogger.i('EditorBloc/_onSwitchToPlanView', 'Plan视图模式切换完成');
  }
  
  /// 切换到Write视图模式
  Future<void> _onSwitchToWriteView(
      SwitchToWriteView event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onSwitchToWriteView', '切换到Write视图模式');
    
    // 检查是否需要刷新编辑器数据
    bool shouldRefreshData = currentState.planViewDirty || 
                            currentState.planModificationSource != null;
    
    // 切换到Write视图模式
    emit(currentState.copyWith(
      isPlanViewMode: false,
      planViewDirty: false, // 清除Plan修改标记
    ));
    
    // 如果Plan视图有修改，触发数据刷新
    if (shouldRefreshData) {
      AppLogger.i('EditorBloc/_onSwitchToWriteView', 'Plan视图有修改，触发无感刷新');
      add(const RefreshEditorData(preserveActiveScene: true, source: 'plan_to_write'));
    }
  }
  
  /// 加载Plan内容（使用已有数据，无需API调用）
  Future<void> _onLoadPlanContent(
      LoadPlanContent event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onLoadPlanContent', '加载Plan内容（使用已有数据）');
    
    // 直接使用当前已有的小说数据，无需重新从服务器获取
    // EditorBloc已经包含了完整的小说结构和场景数据
    emit(currentState.copyWith(
      lastPlanModifiedTime: DateTime.now(),
    ));
    
    AppLogger.i('EditorBloc/_onLoadPlanContent', 'Plan内容加载完成（使用缓存数据）');
  }
  
  /// 移动场景
  Future<void> _onMoveScene(
      MoveScene event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    try {
      AppLogger.i('EditorBloc/_onMoveScene', 
          '移动场景: ${event.sourceActId}/${event.sourceChapterId}/${event.sourceSceneId} -> ${event.targetActId}/${event.targetChapterId}[${event.targetIndex}]');
      
      // 调用repository移动场景
      final updatedNovel = await repository.moveScene(
        event.novelId,
        event.sourceActId,
        event.sourceChapterId,
        event.sourceSceneId,
        event.targetActId,
        event.targetChapterId,
        event.targetIndex,
      );
      
      if (updatedNovel == null) {
        emit(currentState.copyWith(
          errorMessage: '移动场景失败',
        ));
        return;
      }
      
      // 重新计算章节映射
      final chapterMaps = _calculateChapterMaps(updatedNovel);
      
      // 更新状态，标记Plan视图已修改
      emit(currentState.copyWith(
        novel: updatedNovel,
        chapterGlobalIndices: chapterMaps.chapterGlobalIndices,
        chapterToActMap: chapterMaps.chapterToActMap,
        planViewDirty: true,
        lastPlanModifiedTime: DateTime.now(),
        planModificationSource: 'scene_move',
      ));
      
      // 持久化：确保移动后的结构与本地缓存一致
      await repository.saveNovel(updatedNovel);
      
      AppLogger.i('EditorBloc/_onMoveScene', '场景移动完成');
    } catch (e) {
      AppLogger.e('EditorBloc/_onMoveScene', '移动场景失败', e);
      emit(currentState.copyWith(
        errorMessage: '移动场景失败: ${e.toString()}',
      ));
    }
  }
  
  /// 从Plan视图跳转到指定场景
  Future<void> _onNavigateToSceneFromPlan(
      NavigateToSceneFromPlan event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onNavigateToSceneFromPlan', 
        '从Plan视图跳转到场景: ${event.actId}/${event.chapterId}/${event.sceneId}');
    
    // 1. 设置活动场景
    emit(currentState.copyWith(
      activeActId: event.actId,
      activeChapterId: event.chapterId,
      activeSceneId: event.sceneId,
      focusChapterId: event.chapterId,
    ));
    
    // 2. 加载目标场景的内容（如果还没有加载）
    add(LoadMoreScenes(
      fromChapterId: event.chapterId,
      actId: event.actId,
      direction: 'center',
      chaptersLimit: 5,
      targetChapterId: event.chapterId,
      targetSceneId: event.sceneId,
    ));
    
    // 3. 延迟切换到Write视图，确保场景加载完成
    Future.delayed(const Duration(milliseconds: 300), () {
      add(const SwitchToWriteView());
    });
  }
  
  /// 刷新编辑器数据（无感刷新）
  Future<void> _onRefreshEditorData(
      RefreshEditorData event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onRefreshEditorData', 
        '执行无感刷新，来源: ${event.source}, 保持活动场景: ${event.preserveActiveScene}');
    
    try {
      // 重新加载小说数据（使用分页/局部而非全量）
      // 以当前活动章节或 lastEditedChapterId 作为中心进行分页拉取，避免全量接口
      String? centerChapterId = currentState.activeChapterId ?? currentState.novel.lastEditedChapterId;
      if (centerChapterId == null) {
        // 兜底：取首章
        if (currentState.novel.acts.isNotEmpty && currentState.novel.acts.first.chapters.isNotEmpty) {
          centerChapterId = currentState.novel.acts.first.chapters.first.id;
        }
      }

      if (centerChapterId == null) {
        AppLogger.w('EditorBloc/_onRefreshEditorData', '无法确定分页中心章节，跳过刷新');
        return;
      }

      final novel = await repository.getNovelWithPaginatedScenes(
        novelId,
        centerChapterId,
        chaptersLimit: 5,
      );
      
      if (novel == null) {
        AppLogger.w('EditorBloc/_onRefreshEditorData', '刷新数据失败，无法加载小说');
        return;
      }
      
      // 重新计算章节映射
      final chapterMaps = _calculateChapterMaps(novel);
      
      // 保持当前活动场景（如果请求保持的话）
      String? activeActId = currentState.activeActId;
      String? activeChapterId = currentState.activeChapterId;
      String? activeSceneId = currentState.activeSceneId;
      
      if (!event.preserveActiveScene) {
        // 如果不保持活动场景，设置为第一个可用场景
        if (novel.acts.isNotEmpty && novel.acts.first.chapters.isNotEmpty && 
            novel.acts.first.chapters.first.scenes.isNotEmpty) {
          activeActId = novel.acts.first.id;
          activeChapterId = novel.acts.first.chapters.first.id;
          activeSceneId = novel.acts.first.chapters.first.scenes.first.id;
        }
      }
      
      // 更新状态，清除Plan修改标记
      emit(currentState.copyWith(
        novel: novel,
        chapterGlobalIndices: chapterMaps.chapterGlobalIndices,
        chapterToActMap: chapterMaps.chapterToActMap,
        activeActId: activeActId,
        activeChapterId: activeChapterId,
        activeSceneId: activeSceneId,
        planViewDirty: false,
        planModificationSource: null,
        lastPlanModifiedTime: DateTime.now(),
      ));
      
      AppLogger.i('EditorBloc/_onRefreshEditorData', '无感刷新完成');
    } catch (e) {
      AppLogger.e('EditorBloc/_onRefreshEditorData', '无感刷新失败', e);
      emit(currentState.copyWith(
        errorMessage: '刷新数据失败: ${e.toString()}',
      ));
    }
  }
  
  /// 🚀 新增：切换到沉浸模式
  Future<void> _onSwitchToImmersiveMode(
      SwitchToImmersiveMode event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 确定目标章节ID
    String? targetChapterId = event.chapterId ?? currentState.activeChapterId;
    
    if (targetChapterId == null) {
      AppLogger.w('EditorBloc/_onSwitchToImmersiveMode', '无法确定目标章节ID');
      return;
    }
    
    AppLogger.i('EditorBloc/_onSwitchToImmersiveMode', '切换到沉浸模式，章节: $targetChapterId');
    
    // 更新状态（不修改lastEditedChapterId，只有编辑内容时才更新）
    emit(currentState.copyWith(
      isImmersiveMode: true,
      immersiveChapterId: targetChapterId,
      activeChapterId: targetChapterId,
      // 设置该章节的第一个场景为活动场景
    ));
    
    // 如果指定的章节还没有加载，则加载它
    await _ensureChapterLoaded(targetChapterId, emit);
    
    AppLogger.i('EditorBloc/_onSwitchToImmersiveMode', '沉浸模式切换完成');
  }
  
    /// 🚀 新增：切换到普通模式
  Future<void> _onSwitchToNormalMode(
SwitchToNormalMode event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    AppLogger.i('EditorBloc/_onSwitchToNormalMode', '切换到普通模式');
    
    // 🚀 修复：保存当前沉浸章节ID，用于后续滚动定位
    final currentImmersiveChapterId = currentState.immersiveChapterId;
    
    // 更新状态，保持当前的活动章节
    emit(currentState.copyWith(
      isImmersiveMode: false,
      immersiveChapterId: null,
      // 🚀 新增：设置焦点章节为当前沉浸章节，用于滚动定位
      focusChapterId: currentImmersiveChapterId ?? currentState.activeChapterId,
    ));
    
    AppLogger.i('EditorBloc/_onSwitchToNormalMode', '普通模式切换完成，当前章节: $currentImmersiveChapterId');
  }
  
  /// 🚀 新增：章节导航到下一章（普通/沉浸模式通用）
  Future<void> _onNavigateToNextChapter(
      NavigateToNextChapter event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    final String? baseChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (baseChapterId == null) {
      AppLogger.w('EditorBloc/_onNavigateToNextChapter', '无法确定当前章节');
      return;
    }
    
    final nextChapterId = _findNextChapter(baseChapterId);
    if (nextChapterId == null) {
      AppLogger.i('EditorBloc/_onNavigateToNextChapter', '已经是最后一章');
      return;
    }
    
    AppLogger.i('EditorBloc/_onNavigateToNextChapter', '导航到下一章: $nextChapterId');
    
    if (currentState.isImmersiveMode) {
      // 沉浸模式下维持沉浸模式
      add(SwitchToImmersiveMode(chapterId: nextChapterId));
    } else {
      // 普通模式下仅更新活动章节/场景
      String? targetActId = currentState.chapterToActMap[nextChapterId] ?? _findActIdForChapter(currentState.novel, nextChapterId);
      String? firstSceneId;
      if (targetActId != null) {
        for (final act in currentState.novel.acts) {
          if (act.id == targetActId) {
            for (final chapter in act.chapters) {
              if (chapter.id == nextChapterId) {
                if (chapter.scenes.isNotEmpty) {
                  firstSceneId = chapter.scenes.first.id;
                }
                break;
              }
            }
            break;
          }
        }
      }
      emit(currentState.copyWith(
        activeActId: targetActId,
        activeChapterId: nextChapterId,
        activeSceneId: firstSceneId,
        focusChapterId: nextChapterId,
      ));
      await _ensureChapterLoaded(nextChapterId, emit);
    }
  }
  
  /// 🚀 新增：章节导航到上一章（普通/沉浸模式通用）
  Future<void> _onNavigateToPreviousChapter(
      NavigateToPreviousChapter event, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    final String? baseChapterId = currentState.isImmersiveMode
        ? currentState.immersiveChapterId
        : currentState.activeChapterId;
    if (baseChapterId == null) {
      AppLogger.w('EditorBloc/_onNavigateToPreviousChapter', '无法确定当前章节');
      return;
    }
    
    final previousChapterId = _findPreviousChapter(baseChapterId);
    if (previousChapterId == null) {
      AppLogger.i('EditorBloc/_onNavigateToPreviousChapter', '已经是第一章');
      return;
    }
    
    AppLogger.i('EditorBloc/_onNavigateToPreviousChapter', '导航到上一章: $previousChapterId');
    
    if (currentState.isImmersiveMode) {
      // 沉浸模式下维持沉浸模式
      add(SwitchToImmersiveMode(chapterId: previousChapterId));
    } else {
      // 普通模式下仅更新活动章节/场景
      String? targetActId = currentState.chapterToActMap[previousChapterId] ?? _findActIdForChapter(currentState.novel, previousChapterId);
      String? firstSceneId;
      if (targetActId != null) {
        for (final act in currentState.novel.acts) {
          if (act.id == targetActId) {
            for (final chapter in act.chapters) {
              if (chapter.id == previousChapterId) {
                if (chapter.scenes.isNotEmpty) {
                  firstSceneId = chapter.scenes.first.id;
                }
                break;
              }
            }
            break;
          }
        }
      }
      emit(currentState.copyWith(
        activeActId: targetActId,
        activeChapterId: previousChapterId,
        activeSceneId: firstSceneId,
        focusChapterId: previousChapterId,
      ));
      await _ensureChapterLoaded(previousChapterId, emit);
    }
  }
  
  /// 🚀 新增：确保指定章节已加载
  Future<void> _ensureChapterLoaded(String chapterId, Emitter<EditorState> emit) async {
    if (state is! EditorLoaded) return;
    
    final currentState = state as EditorLoaded;
    
    // 查找章节所属的卷
    String? actId;
    for (final act in currentState.novel.acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == chapterId) {
          actId = act.id;
          break;
        }
      }
      if (actId != null) break;
    }
    
    if (actId == null) {
      AppLogger.w('EditorBloc/_ensureChapterLoaded', '找不到章节 $chapterId 所属的卷');
      return;
    }
    
    // 检查章节是否已有场景内容
    bool hasScenes = false;
    for (final act in currentState.novel.acts) {
      if (act.id == actId) {
        for (final chapter in act.chapters) {
          if (chapter.id == chapterId && chapter.scenes.isNotEmpty) {
            hasScenes = true;
            break;
          }
        }
        break;
      }
    }
    
    // 如果章节还没有场景，则加载
    if (!hasScenes) {
      AppLogger.i('EditorBloc/_ensureChapterLoaded', '加载章节场景: $chapterId');
      add(LoadMoreScenes(
        fromChapterId: chapterId,
        actId: actId,
        direction: 'center',
        chaptersLimit: 1,
        preventFocusChange: false,
      ));
    }
  }
  
  /// 🚀 新增：查找下一章节
  String? _findNextChapter(String currentChapterId) {
    if (state is! EditorLoaded) return null;
    
    final currentState = state as EditorLoaded;
    bool foundCurrent = false;
    
    for (final act in currentState.novel.acts) {
      for (final chapter in act.chapters) {
        if (foundCurrent) {
          return chapter.id; // 找到下一章
        }
        if (chapter.id == currentChapterId) {
          foundCurrent = true;
        }
      }
    }
    
    return null; // 没有下一章
  }
  
  /// 🚀 新增：查找上一章节
  String? _findPreviousChapter(String currentChapterId) {
    if (state is! EditorLoaded) return null;
    
    final currentState = state as EditorLoaded;
    String? previousChapterId;
    
    for (final act in currentState.novel.acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == currentChapterId) {
          return previousChapterId; // 返回上一章
        }
        previousChapterId = chapter.id;
      }
    }
    
    return null; // 没有上一章
  }
}
