import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/models/editor_content.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/novel_with_summaries_dto.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/base/api_exception.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/services/local_storage_service.dart';
import 'package:ainoval/utils/date_time_parser.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/models/api/editor_dtos.dart';
import 'package:ainoval/services/api_service/base/sse_client.dart';
import 'package:ainoval/utils/quill_helper.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'dart:async';
import 'dart:convert';
import 'package:ainoval/utils/event_bus.dart'; // Added EventBus import
// import 'package:collection/collection.dart'; // For lastOrNull (未使用)
import 'package:ainoval/models/chapters_for_preload_dto.dart';

/// 编辑器仓库实现
class EditorRepositoryImpl implements EditorRepository {
  EditorRepositoryImpl({
    ApiClient? apiClient,
    LocalStorageService? localStorageService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _localStorageService = localStorageService ?? LocalStorageService();

  final ApiClient _apiClient;
  final LocalStorageService _localStorageService;
  static const String _tag = 'EditorRepositoryImpl';

  // 添加在类属性部分
  final Map<String, DateTime> _lastSummaryUpdateTime = {};
  static const Duration _summaryUpdateDebounceInterval = Duration(milliseconds: 1000);

  /// 获取本地存储服务
  LocalStorageService getLocalStorageService() {
    return _localStorageService;
  }

  /// 获取API客户端
  ApiClient getApiClient() {
    return _apiClient;
  }

  // Helper method to publish novel structure update events
  void _publishNovelStructureUpdate(String novelId, String updateType, {String? actId, String? chapterId, String? sceneId}) {
    final Map<String, dynamic> eventData = {};
    if (actId != null) eventData['actId'] = actId;
    if (chapterId != null) eventData['chapterId'] = chapterId;
    if (sceneId != null) eventData['sceneId'] = sceneId;

    EventBus.instance.fire(NovelStructureUpdatedEvent(
      novelId: novelId,
      updateType: updateType,
      data: eventData, // Pass data as a map
    ));
    AppLogger.i(_tag, 'Published NovelStructureUpdatedEvent: novelId=$novelId, type=$updateType, data=$eventData');
  }

  /// 获取编辑器内容
  @override
  Future<EditorContent> getEditorContent(
      String novelId, String chapterId, String sceneId) async {
    try {
      final data =
          await _apiClient.getEditorContent(novelId, chapterId, sceneId);
      return EditorContent.fromJson(data);
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '获取编辑器内容失败，返回空内容',
          e);
      return EditorContent(
        id: '$novelId-$chapterId-$sceneId',
        content: '{"ops":[{"insert":"\\n"}]}',
        lastSaved: DateTime.now(),
        scenes: const {},
      );
    }
  }

  /// 保存编辑器内容
  @override
  Future<void> saveEditorContent(EditorContent content) async {
    try {
      final parts = content.id.split('-');
      if (parts.length < 2) {
        throw ApiException(-1, '无效的内容ID格式');
      }

      final novelId = parts[0];
      final chapterId = parts[1];

      // 先保存到本地
      await _localStorageService.saveEditorContent(content);
      AppLogger.i('EditorRepositoryImpl/saveEditorContent',
          '编辑器内容已保存到本地: ${content.id}');
      
      // 检查是否为当前小说
      final currentNovelId = await _localStorageService.getCurrentNovelId();
      if (currentNovelId == novelId) {
        // 标记为需要同步
        final syncKey = '${novelId}_$chapterId';
        await _localStorageService.markForSyncByType(syncKey, 'editor');
        AppLogger.i('EditorRepositoryImpl/saveEditorContent',
            '编辑器内容标记为待同步: $syncKey');

        try {
          // 上传到服务器
          await _apiClient.saveEditorContent(novelId, chapterId, content.toJson());
          AppLogger.i('EditorRepositoryImpl/saveEditorContent',
              '编辑器内容已同步到服务器: ${content.id}');

          // 清除同步标记
          await _localStorageService.clearSyncFlagByType('editor', syncKey);
          AppLogger.i('EditorRepositoryImpl/saveEditorContent',
              '编辑器内容同步标记已清除: $syncKey');
        } catch (e) {
          AppLogger.e(
              'Services/api_service/repositories/impl/editor_repository_impl',
              '保存编辑器内容到服务器失败，但已保存到本地',
              e);
        }
      } else {
        AppLogger.i(
            'EditorRepositoryImpl/saveEditorContent', 
            '编辑器内容不属于当前编辑的小说，跳过同步: ${content.id}, 当前小说ID: $currentNovelId');
      }
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '保存编辑器内容失败',
          e);
      throw ApiException(-1, '保存编辑器内容失败: $e');
    }
  }

  /// 获取修订历史
  @override
  Future<List<Revision>> getRevisionHistory(
      String novelId, String chapterId) async {
    try {
      final data = await _apiClient.getRevisionHistory(novelId, chapterId);
      if (data is List) {
        return data.map((json) => Revision.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '获取修订历史失败',
          e);
      rethrow;
    }
  }

  /// 创建修订版本
  @override
  Future<Revision> createRevision(
      String novelId, String chapterId, Revision revision) async {
    try {
      final data = await _apiClient.createRevision(
          novelId, chapterId, revision.toJson());
      return Revision.fromJson(data);
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '创建修订版本失败',
          e);
      throw ApiException(-1, '创建修订版本失败: $e');
    }
  }

  /// 应用修订版本
  @override
  Future<void> applyRevision(
      String novelId, String chapterId, String revisionId) async {
    try {
      await _apiClient.applyRevision(novelId, chapterId, revisionId);
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '应用修订版本失败',
          e);
      throw ApiException(-1, '应用修订版本失败: $e');
    }
  }

  /// 将后端NovelWithScenesDto模型转换为前端Novel模型
  Novel _convertBackendNovelWithScenesToFrontend(
      Map<String, dynamic> backendData) {
    try {
      // 提取小说基本信息
      final backendNovel = backendData['novel'];

      // 提取所有场景数据，按章节ID分组
      final Map<String, List<dynamic>> scenesByChapter =
          backendData['scenesByChapter'] != null
              ? Map<String, List<dynamic>>.from(backendData['scenesByChapter'])
              : {};

      // 提取作者信息
      Author? author;
      if (backendNovel.containsKey('author') &&
          backendNovel['author'] != null) {
        final authorData = backendNovel['author'];
        if (!authorData.containsKey('username') || authorData['username'] == null){
           authorData['username']='unknown';
        }
        if (authorData.containsKey('id') && authorData['id'] != null) {
          author = Author(
            id: authorData['id'],
            username: authorData['username'] ?? 'unknown',
          );
        }
      }

      // 提取Acts和Chapters
      List<Act> acts = [];
      if (backendNovel.containsKey('structure') &&
          backendNovel['structure'] is Map &&
          (backendNovel['structure'] as Map).containsKey('acts')) {
        acts =
            ((backendNovel['structure'] as Map)['acts'] as List).map((actData) {
          // 转换章节
          List<Chapter> chapters = [];
          if (actData.containsKey('chapters') && actData['chapters'] is List) {
            chapters = (actData['chapters'] as List).map((chapterData) {
              final chapterId = chapterData['id'];
              // 从scenesByChapter获取该章节的所有场景
              List<Scene> scenes = [];

              // 检查是否有该章节的场景数据
              if (scenesByChapter.containsKey(chapterId) &&
                  scenesByChapter[chapterId] is List) {
                scenes = (scenesByChapter[chapterId] as List).map((sceneData) {
                  // 使用_convertBackendSceneToFrontend将后端场景数据转换为前端模型
                  return _convertBackendSceneToFrontend(sceneData);
                }).toList();
              }
              return Chapter(
                id: chapterId,
                title: chapterData['title'],
                order: chapterData['order'],
                scenes: scenes,
              );
            }).toList();
          }
          return Act(
            id: actData['id'],
            title: actData['title'],
            order: actData['order'],
            chapters: chapters,
          );
        }).toList();
      }

      // 解析时间
      DateTime createdAt;
      DateTime updatedAt;

      try {
        createdAt = backendNovel.containsKey('createdAt')
            ? DateTime.parse(backendNovel['createdAt'])
            : DateTime.now();
      } catch (e) {
        createdAt = DateTime.now();
      }

      try {
        updatedAt = backendNovel.containsKey('updatedAt')
            ? DateTime.parse(backendNovel['updatedAt'])
            : DateTime.now();
      } catch (e) {
        updatedAt = DateTime.now();
      }

      // 创建Novel对象
      return Novel(
        id: backendNovel['id'],
        title: backendNovel['title'] ?? '无标题',
        coverUrl: backendNovel['coverImage'] ?? '',
        createdAt: createdAt,
        updatedAt: updatedAt,
        acts: acts,
        lastEditedChapterId: backendNovel['lastEditedChapterId'],
        author: author,
      );
    } catch (e) {
      AppLogger.e('_convertBackendNovelWithScenesToFrontend',
          '转换后端NovelWithScenesDto模型为前端Novel模型失败', e);
      rethrow;
    }
  }

  /// 获取小说详情
  @override
  Future<Novel?> getNovel(String novelId) async {
    try {
      final localNovel = await _localStorageService.getNovel(novelId);
      if (localNovel != null) {
        AppLogger.i('EditorRepositoryImpl/getNovel', '从本地存储加载小说: $novelId');
        return localNovel;
      }

      AppLogger.i(
          'EditorRepositoryImpl/getNovel', '本地未找到小说，尝试从API获取: $novelId');
      try {
        final data = await _apiClient.getNovelDetailById(novelId);

        final novel = _convertBackendNovelWithScenesToFrontend(data);

        await _localStorageService.saveNovel(novel);
        AppLogger.i(
            'EditorRepositoryImpl/getNovel', '从API获取小说成功并保存到本地: $novelId');

        return novel;
      } catch (e) {
        AppLogger.e(
            'Services/api_service/repositories/impl/editor_repository_impl/getNovel',
            '从API获取小说失败，本地也无缓存',
            e);
        return null;
      }
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl/getNovel',
          '获取小说时发生未知错误',
          e);
      return null;
    }
  }

  /// 获取小说详情（分页加载场景）
  /// 基于上次编辑章节为中心，获取前后指定数量的章节及其场景内容
  @override
  Future<Novel?> getNovelWithPaginatedScenes(String novelId, String lastEditedChapterId, {int chaptersLimit = 5}) async {
    try {
      AppLogger.i(
          'EditorRepositoryImpl/getNovelWithPaginatedScenes', 
          '从API获取小说(分页): novelId=$novelId, lastChapter=$lastEditedChapterId, limit=$chaptersLimit');
      
      // 使用新的分页API获取数据
      final data = await _apiClient.getNovelWithPaginatedScenes(
        novelId, 
        lastEditedChapterId,
        chaptersLimit: chaptersLimit
      );

      // 转换数据格式
      final novel = _convertBackendNovelWithScenesToFrontend(data);
      
      // 将小说基本信息保存到本地（不包含场景内容）
      await _localStorageService.saveNovel(novel);
      
      // // 将场景内容分别保存到本地
      // for (final act in novel.acts) {
      //   for (final chapter in act.chapters) {
      //     for (final scene in chapter.scenes) {
      //       await _localStorageService.saveSceneContent(
      //         novelId, 
      //         act.id, 
      //         chapter.id, 
      //         scene.id, 
      //         scene
      //       );
      //     }
      //   }
      // }
      
      AppLogger.i(
          'EditorRepositoryImpl/getNovelWithPaginatedScenes', 
          '从API获取小说(分页)成功: $novelId, 返回章节数: ${novel.acts.fold(0, (sum, act) => sum + act.chapters.length)}');
      return novel;
    } catch (e) {
      AppLogger.e(
          'EditorRepositoryImpl/getNovelWithPaginatedScenes',
          '从API获取小说(分页)失败',
          e);
          
      // 如果分页加载失败，尝试回退到本地存储
      try {
        final localNovel = await _localStorageService.getNovel(novelId);
        if (localNovel != null) {
          AppLogger.i('EditorRepositoryImpl/getNovelWithPaginatedScenes', 
              '分页加载失败，回退到本地存储小说: $novelId');
          return localNovel;
        }
      } catch (localError) {
        AppLogger.e(
            'EditorRepositoryImpl/getNovelWithPaginatedScenes',
            '本地存储回退也失败',
            localError);
      }
      return null;
    }
  }

  /// 加载更多章节场景
  /// 根据方向（向上或向下）加载更多章节的场景内容
  @override
  Future<Map<String, List<Scene>>> loadMoreScenes(String novelId, String? actId, String fromChapterId, String direction, {int chaptersLimit = 5}) async {
    try {
      AppLogger.i(
          'EditorRepositoryImpl/loadMoreScenes', 
          '加载更多场景: novelId=$novelId, actId=$actId, fromChapter=$fromChapterId, direction=$direction, limit=$chaptersLimit');
      
      // 调用API加载更多场景
      final data = await _apiClient.loadMoreScenes(
        novelId,
        actId ?? '', // 如果actId为null，传空字符串
        fromChapterId, 
        direction,
        chaptersLimit: chaptersLimit
      );
      
      // 转换数据格式 - data是Map<String, List<Map<String, dynamic>>>
      final Map<String, List<Scene>> result = {};
      
      if (data is Map) {
        data.forEach((chapterId, scenes) {
          if (scenes is List) {
            result[chapterId] = scenes
                .map((sceneData) => _convertBackendSceneToFrontend(sceneData))
                .toList();
                
            // 对每个场景保存到本地存储
            // 注意：这里我们需要知道actId，但API可能没有返回，需要从之前的数据中查找
            _saveScenesToLocalStorage(novelId, chapterId, result[chapterId]!);
          }
        });
      }
      
      AppLogger.i(
          'EditorRepositoryImpl/loadMoreScenes', 
          '加载更多场景成功: $novelId, 返回章节数: ${result.length}');
      return result;
    } catch (e) {
      AppLogger.e(
          'EditorRepositoryImpl/loadMoreScenes',
          '加载更多场景失败',
          e);
      // 返回空映射表示加载失败
      return {};
    }
  }
  
  /// 辅助方法：将场景保存到本地存储
  Future<void> _saveScenesToLocalStorage(String novelId, String chapterId, List<Scene> scenes) async {
    try {
      // 获取当前小说结构以找到正确的actId
      final novel = await _localStorageService.getNovel(novelId);
      if (novel == null) {
        AppLogger.w('EditorRepositoryImpl/_saveScenesToLocalStorage', 
            '无法保存场景到本地，小说结构不存在: $novelId');
        return;
      }
      
      // 查找chapter对应的act
      String? actId;
      for (final act in novel.acts) {
        for (final chapter in act.chapters) {
          if (chapter.id == chapterId) {
            actId = act.id;
            break;
          }
        }
        if (actId != null) break;
      }
      
      if (actId == null) {
        AppLogger.w('EditorRepositoryImpl/_saveScenesToLocalStorage', 
            '无法保存场景到本地，找不到章节对应的act: $chapterId');
        return;
      }
      
      // 保存每个场景
      for (final scene in scenes) {
        await _localStorageService.saveSceneContent(
          novelId, 
          actId, 
          chapterId, 
          scene.id, 
          scene
        );
        AppLogger.v('EditorRepositoryImpl/_saveScenesToLocalStorage', 
            '场景保存到本地: ${scene.id}');
      }
      
      AppLogger.i('EditorRepositoryImpl/_saveScenesToLocalStorage', 
          '成功保存 ${scenes.length} 个场景到本地，章节: $chapterId');
    } catch (e) {
      AppLogger.e(
          'EditorRepositoryImpl/_saveScenesToLocalStorage',
          '保存场景到本地失败',
          e);
    }
  }

  /// 将前端Novel模型转换为后端API所需的JSON格式
  Map<String, dynamic> _convertFrontendNovelToBackendJson(Novel novel) {
    return {
      'id': novel.id,
      'title': novel.title,
      'coverImage': novel.coverUrl,
      'createdAt': novel.createdAt.toIso8601String(),
      'updatedAt': novel.updatedAt.toIso8601String(),
      'lastEditedChapterId': novel.lastEditedChapterId,
      'author': novel.author?.toJson() ??
          {
            'id': AppConfig.userId ?? 'unknown',
            'username': AppConfig.username ?? 'user',
          },
      'structure': {
        'acts': novel.acts
            .map((act) => {
                  'id': act.id,
                  'title': act.title,
                  'order': act.order,
                  'chapters': act.chapters
                      .map((chapter) => {
                            'id': chapter.id,
                            'title': chapter.title,
                            'order': chapter.order,
                            'sceneIds': chapter.scenes
                                .map((scene) => scene.id)
                                .toList(),
                          })
                      .toList(),
                })
            .toList(),
      },
      'metadata': {
        'wordCount': novel.wordCount,
        'readTime': (novel.wordCount / 200).ceil(),
        'lastEditedAt': novel.updatedAt.toIso8601String(),
        'version': 1, // 版本号可能需要更复杂的逻辑
        'contributors': [AppConfig.username ?? 'user'],
      },
      'status': 'draft', // 状态可能需要根据实际情况设置
    };
  }

  /// 保存小说数据
  @override
  Future<bool> saveNovel(Novel novel) async {
    bool localSaveSuccess = false; // 保留占位，便于未来扩展（例如统计保存结果）
    try {
      await _localStorageService.saveNovel(novel);
      localSaveSuccess = true;
      AppLogger.i('EditorRepositoryImpl/saveNovel', '小说已保存到本地: ${novel.id}');

      // 检查是否为当前小说，只同步当前小说
      final currentNovelId = await _localStorageService.getCurrentNovelId();
      if (currentNovelId == novel.id) {
        await _localStorageService.markForSyncByType(novel.id, 'novel');
        AppLogger.i('EditorRepositoryImpl/saveNovel', '小说标记为待同步: ${novel.id}');
      } else {
        AppLogger.i('EditorRepositoryImpl/saveNovel', '小说不是当前编辑的小说，跳过同步标记: ${novel.id}, 当前小说ID: $currentNovelId');
      }

      try {
        // 只有当前小说才实时同步到服务器
        if (currentNovelId == novel.id) {
          // 🚀 优化：只发送小说基本信息，不包含场景数据，避免载荷过大
          final Map<String, dynamic> backendNovelJson =
              _convertFrontendNovelToBackendJson(novel);

          await _apiClient.updateNovel(backendNovelJson);
          AppLogger.i('EditorRepositoryImpl/saveNovel', '小说基本信息已同步到服务器: ${novel.id}');
          _publishNovelStructureUpdate(novel.id, 'NOVEL_STRUCTURE_SAVED'); // Publish event
        }

        return true;
      } catch (e) {
        AppLogger.e(
            'Services/api_service/repositories/impl/editor_repository_impl',
            '保存小说到服务器失败，但已保存到本地',
            e);
        return true;
      }
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '保存小说到本地存储失败',
          e);
      return false;
    }
  }

  /// 将前端Scene模型转换为后端API所需的JSON格式 (用于upsert)
  Map<String, dynamic> _convertFrontendSceneToBackendJson(
      Scene scene, String novelId, String chapterId) {
    // 确保content是字符串格式
    String contentStr = scene.content;
    
    // 如果内容为空，提供默认的空内容
    if (contentStr.isEmpty) {
      contentStr = '{"ops":[{"insert":"\\n"}]}';
    }
    
    // 确保content是有效的JSON，如果已经是字符串则不需要操作
    // 如果是对象，则转换为JSON字符串
    try {
      // 尝试解析以验证是JSON字符串
      jsonDecode(contentStr);
    } catch (e) {
      // 如果不是JSON字符串（可能是对象被错误存储），记录并纠正
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '场景内容不是有效JSON字符串，尝试修正',
          e);
      contentStr = '{"ops":[{"insert":"\\n"}]}';
    }
    
    return {
      'id': scene.id,
      'novelId': novelId,
      'chapterId': chapterId,
      'content': contentStr,
      'summary': scene.summary.content,
      'updatedAt': scene.lastEdited.toIso8601String(),
      'version': scene.version,
      'title': scene.title.isNotEmpty ? scene.title : '场景 ${scene.id}',
      'sequence': 0,
      'sceneType': 'NORMAL',
      'history': scene.history
          .map((entry) => {
                'content': entry.content,
                'updatedAt': entry.updatedAt.toIso8601String(),
                'updatedBy': entry.updatedBy,
                'reason': entry.reason,
              })
          .toList(),
    };
  }

  /// 将后端Scene模型转换为前端Scene模型
  Scene _convertBackendSceneToFrontend(Map<String, dynamic> backendScene) {
    // 后端Scene模型中summary是字符串，需要转换为Summary对象
    final Summary summary = Summary(
      id: '${backendScene['id']}_summary',
      content: backendScene['summary'] ?? '',
    );

    // 解析历史记录
    List<HistoryEntry> history = [];
    if (backendScene.containsKey('history') &&
        backendScene['history'] is List) {
      history = (backendScene['history'] as List)
          .map((historyEntryData) {
            // 使用新的工具函数解析 updatedAt
            final DateTime entryUpdatedAt =
                parseBackendDateTime(historyEntryData['updatedAt']);

            return HistoryEntry(
              content: historyEntryData['content']?.toString() ?? '',
              updatedAt: entryUpdatedAt,
              updatedBy: historyEntryData['updatedBy']?.toString() ?? 'unknown',
              reason: historyEntryData['reason']?.toString() ?? '',
            );
          })
          .whereType<HistoryEntry>()
          .toList();
    }

    // 使用新的工具函数解析 Scene 的 lastEdited
    final DateTime lastEdited = parseBackendDateTime(backendScene['updatedAt']);

    // 创建Scene对象
    return Scene(
      id: backendScene['id'],
      content: backendScene['content'] ?? '',
      wordCount: backendScene['wordCount'] ?? 0,
      summary: summary,
      lastEdited: lastEdited,
      version: backendScene['version'] ?? 1,
      history: history,
    );
  }

  /// 获取场景内容
  @override
  Future<Scene?> getSceneContent(
      String novelId, String actId, String chapterId, String sceneId) async {
    final sceneKey = '${novelId}_${actId}_${chapterId}_$sceneId';
    try {
      final localScene = await _localStorageService.getSceneContent(
          novelId, actId, chapterId, sceneId);

      if (localScene != null) {
        AppLogger.i(
            'EditorRepositoryImpl/getSceneContent', '从本地存储加载场景: $sceneKey');
        return localScene;
      }

      AppLogger.i('EditorRepositoryImpl/getSceneContent',
          '本地未找到场景，尝试从API获取: $sceneKey');
      final data = await _apiClient.getSceneById(novelId, chapterId, sceneId);

      final scene = _convertBackendSceneToFrontend(data);

      await _localStorageService.saveSceneContent(
          novelId, actId, chapterId, sceneId, scene);
      AppLogger.i('EditorRepositoryImpl/getSceneContent',
          '从API获取场景成功并保存到本地: $sceneKey');

      return scene;
    } catch (e) {
      AppLogger.e(
          'Services/api_service/repositories/impl/editor_repository_impl',
          '获取场景内容失败，本地也无缓存',
          e);
      if (e is ApiException && e.statusCode == 404) {
        AppLogger.w('EditorRepositoryImpl/getSceneContent',
            '场景 $sceneKey 在服务器上未找到，返回默认空场景');
        return Scene.createDefault(sceneId);
      }
      return null;
    }
  }

  /// 构建场景的唯一键
  String _getSceneKey(String novelId, String actId, String chapterId, String sceneId) {
    return '${novelId}_${actId}_${chapterId}_$sceneId';
  }

  /// 保存场景内容
  @override
  Future<Scene> saveSceneContent(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
    String content,
    String wordCount,
    Summary summary,
    {bool localOnly = false}
  ) async {
    try {
      final sceneKey = _getSceneKey(novelId, actId, chapterId, sceneId);
      AppLogger.i('EditorRepositoryImpl/saveSceneContent', '正在保存场景内容: $sceneKey');
      
      // 确保内容是有效的格式
      String processedContent = content;
      try {
        // 检查是否纯文本，如果是则转换为Quill格式
        if (!content.startsWith('[') && !content.startsWith('{')) {
          processedContent = QuillHelper.convertPlainTextToQuillDelta(content);
        } else {
          // 使用QuillHelper确保标准格式
          processedContent = QuillHelper.ensureQuillFormat(content);
        }
      } catch (e) {
        AppLogger.e('EditorRepositoryImpl/saveSceneContent', '格式化内容失败，使用原始内容', e);
      }
      
      // 创建Scene对象
      final scene = Scene(
        id: sceneId,
        content: processedContent,
        wordCount: int.tryParse(wordCount) ?? 0,
        summary: summary,
        lastEdited: DateTime.now(),
        version: 1,
        history: [],
      );
      
      // 保存到本地存储
      await _localStorageService.saveSceneContent(
        novelId, 
        actId, 
        chapterId,
        sceneId,
        scene
      );
      
      AppLogger.i('EditorRepositoryImpl/saveSceneContent', '场景内容已保存到本地: $sceneKey');
      
      // 如果只保存到本地，则直接返回
      if (localOnly) {
        AppLogger.i('EditorRepositoryImpl/saveSceneContent', '跳过服务器同步（localOnly=true）: $sceneKey');
        return scene;
      }
      
      // 否则也同步到服务器
      try {
        // 标记需要同步到服务器
        await _localStorageService.markForSyncByType(sceneKey, 'scene');
        AppLogger.i('EditorRepositoryImpl/saveSceneContent', '场景标记为待同步: $sceneKey');
        
        // 准备完整的场景数据
        final now = DateTime.now().toIso8601String();
        final sceneData = {
          'id': sceneId,
          'novelId': novelId,
          'chapterId': chapterId,
          'title': '场景内容', // 简单的默认标题
          'content': processedContent,
          'summary': summary.content,
          'wordCount': scene.wordCount,
          'sequence': 1, // 默认序列号
          'version': scene.version, // 使用当前版本号
          'createdAt': now,
          'updatedAt': now,
        };
        
        AppLogger.i('EditorRepositoryImpl/saveSceneContent', '发送到服务器的场景数据: content长度=${processedContent.length}, summary长度=${summary.content.length}');
        
        // 调用API更新场景
        final response = await _apiClient.post('/scenes/upsert', data: sceneData);
        
        if (response != null) {
          // 同步成功，清除同步标记
          await _localStorageService.clearSyncFlagByType('scene', sceneKey);
          AppLogger.i('EditorRepositoryImpl/saveSceneContent', '场景已同步到服务器: $sceneKey');
          
          // 更新字数统计
          await _updateNovelWordCount(novelId);
          
          // 如果响应中有场景数据和字数，更新Scene对象
          Scene updatedScene = scene;
          if (response is Map && response.containsKey('wordCount')) {
            int wordCount = response['wordCount'] as int? ?? 0;
            updatedScene = scene.copyWith(wordCount: wordCount);
          }
          
          AppLogger.i('EditorRepositoryImpl/saveSceneContent', '保存完成 - 当前场景字数为: ${updatedScene.wordCount}, 场景ID: $sceneId');
          return updatedScene;
        } else {
          AppLogger.e('EditorRepositoryImpl/saveSceneContent', '同步场景到服务器失败: $sceneKey');
          return scene;
        }
      } catch (e) {
        AppLogger.e('EditorRepositoryImpl/saveSceneContent', '同步场景到服务器时出错', e);
        // 本地存储已成功，但服务器同步失败
        // 保留同步标记，以便之后再次尝试
        return scene;
      }
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/saveSceneContent', '保存场景内容时出错', e);
      // 创建并返回默认场景
      return Scene(
        id: sceneId,
        content: content,
        wordCount: int.tryParse(wordCount) ?? 0,
        summary: summary,
        lastEdited: DateTime.now(),
        version: 1,
        history: [],
      );
    }
  }

  // 更新小说中特定场景的字数统计
  Future<void> _updateNovelWordCount(String novelId) async {
    try {
      final novel = await getNovel(novelId);
      if (novel == null) {
        AppLogger.w(
            'EditorRepositoryImpl/_updateNovelWordCount',
            '无法更新字数统计：小说 $novelId 未找到');
        return;
      }

      // 更新本地小说缓存
      await _localStorageService.saveNovel(novel);
    } catch (e) {
      AppLogger.e(
          'EditorRepositoryImpl/_updateNovelWordCount', '更新小说字数统计失败', e);
    }
  }

  /// 保存摘要
  @override
  Future<Summary> saveSummary(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
    String summaryContent,
  ) async {
    try {
      // 统一调用updateSummary方法
      final success = await updateSummary(
        novelId, actId, chapterId, sceneId, summaryContent
      );
      
      // 创建并返回摘要对象
      final summary = Summary(
        id: '${sceneId}_summary',
        content: summaryContent,
      );
      
      if (!success) {
        AppLogger.w('EditorRepository/saveSummary', '通过updateSummary保存摘要失败');
      }
      
      return summary;
    } catch (e) {
      AppLogger.e('EditorRepository/saveSummary', '保存摘要失败', e);
      // 创建一个基本摘要对象返回
      return Summary(
        id: '${sceneId}_summary',
        content: summaryContent,
      );
    }
  }

  /// 添加新的场景
  @override
  Future<Scene?> addScene(
    String novelId,
    String actId,
    String chapterId,
    Scene scene,
  ) async {
    try {
      // 设置场景基本信息 - 使用QuillHelper确保格式正确
      final String content = QuillHelper.ensureQuillFormat(scene.content ?? '');
      
      final sceneData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
        'title': scene.title ?? "新场景",
        'summary': scene.summary != null ? scene.summary.content : "", // 确保是字符串
        'content': content, // 使用处理后的内容
      };
      
      AppLogger.i('EditorRepository/addScene', '添加场景请求数据: ${sceneData.toString()}');
      
      // 调用API添加场景 - 使用细粒度接口
      final response = await _apiClient.post('/scenes/add-scene-fine', data: sceneData);
      
      // 细粒度接口直接返回Scene对象
      if (response != null && response.containsKey('id')) {
        final newScene = Scene.fromJson(response);
        _publishNovelStructureUpdate(novelId, 'SCENE_ADDED', chapterId: chapterId, sceneId: newScene.id);
        return newScene;
      }
      
      // 如果无法从响应中提取场景，创建一个基本场景
      AppLogger.w('EditorRepository/addScene', '无法从响应中提取场景，创建默认场景');
      return Scene(
        id: scene.id,
        content: QuillHelper.standardEmptyDelta, // 使用标准空内容格式
        wordCount: 0,
        summary: Summary(
          id: '${scene.id}_summary',
          content: scene.summary?.content ?? '',
        ),
        lastEdited: DateTime.now(),
        version: 1,
        history: [],
      );
    } catch (e) {
      AppLogger.e('EditorRepository/addScene', '添加场景失败', e);
      return null;
    }
  }

  /// 使用细粒度API添加场景
  @override
  Future<Scene> addSceneFine(
    String novelId,
    String chapterId,
    String title,
    {String? summary, String? content, int? position}
  ) async {
    try {
      final requestData = {
        'novelId': novelId,
        'chapterId': chapterId,
        'title': title,
        'summary': summary ?? '',
        'position': position,
      };
      
      // 如果提供了内容，添加到请求数据中
      if (content != null && content.isNotEmpty) {
        requestData['content'] = content;
      }

      final response = await _apiClient.post('/scenes/add-scene-fine', data: requestData);
      
      if (response != null && response.containsKey('id')) {
        // 细粒度接口直接返回Scene对象
        final newScene = Scene.fromJson(response);
        _publishNovelStructureUpdate(novelId, 'SCENE_ADDED', chapterId: chapterId, sceneId: newScene.id); // Publish event
        return newScene;
      }
      
      // 创建默认场景
      AppLogger.w('EditorRepository/addSceneFine', '无法从响应中提取场景，创建默认场景');
      final sceneId = "scene_${DateTime.now().millisecondsSinceEpoch}";
      final defaultScene = Scene(
        id: sceneId,
        content: QuillHelper.standardEmptyDelta, // 使用标准空内容格式
        wordCount: 0,
        summary: Summary(
          id: '${sceneId}_summary',
          content: summary ?? '',
        ),
        lastEdited: DateTime.now(),
        version: 1,
        history: [],
      );
      _publishNovelStructureUpdate(novelId, 'SCENE_ADDED', chapterId: chapterId, sceneId: defaultScene.id); // Publish event, ensured chapterId is available
      return defaultScene;
    } catch (e) {
      AppLogger.e('EditorRepository/addSceneFine', '添加场景失败', e);
      throw ApiException(-1, '添加场景失败: $e');
    }
  }

  /// 使用细粒度API添加Act
  @override
  Future<Act> addActFine(String novelId, String title, {String? description}) async {
    try {
      final requestData = {
        'novelId': novelId,
        'title': title,
        'description': description ?? '',
      };

      final response = await _apiClient.post('/novels/add-act-fine', data: requestData);
      
      if (response is Map<String, dynamic>) {
        final actJson = response['act'] ?? response;
        final String? id = actJson['id'] as String?;
        if (id == null || id.isEmpty) {
          throw ApiException(-1, '添加Act失败：服务端未返回有效ID');
        }
        return Act(
          id: id,
          title: actJson['title'] ?? title,
          order: actJson['order'] ?? 0,
          chapters: [],
        );
      }
      throw ApiException(-1, '添加Act失败：响应格式不正确');
    } catch (e) {
      AppLogger.e('EditorRepository/addActFine', '添加Act失败', e);
      throw ApiException(-1, '添加Act失败: $e');
    }
  }

  /// 使用细粒度API添加Chapter
  @override
  Future<Chapter> addChapterFine(String novelId, String actId, String title, {String? description}) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'title': title,
        'description': description ?? '',
      };

      final response = await _apiClient.post('/novels/add-chapter-fine', data: requestData);
      
      if (response != null && response.containsKey('chapter')) {
        final chapterJson = response['chapter'];
        final newChapter = Chapter(
          id: chapterJson['id'] ?? 'chapter_${DateTime.now().millisecondsSinceEpoch}',
          title: chapterJson['title'] ?? title,
          order: chapterJson['order'] ?? 0,
          scenes: [],
        );
        // Event for CHAPTER_ADDED will be published by addNewChapter after fetching the full novel structure
        return newChapter;
      }
      
      // 如果API没有返回新的Chapter，创建一个本地Chapter
      final chapterId = 'chapter_${DateTime.now().millisecondsSinceEpoch}';
      return Chapter(
        id: chapterId,
        title: title,
        order: 0,
        scenes: [],
      );
    } catch (e) {
      AppLogger.e('EditorRepository/addChapterFine', '添加Chapter失败', e);
      throw ApiException(-1, '添加Chapter失败: $e');
    }
  }

  /// 原子化添加章节和场景 - 在一个事务中同时创建章节和场景，避免数据不一致
  @override
  Future<Map<String, dynamic>> addChapterWithScene(String novelId, String actId, 
      String chapterTitle, String sceneTitle, {String? sceneSummary, String? sceneContent, String? insertAfterChapterId}) async {
    try {
      final response = await _apiClient.addChapterWithScene(
        novelId, actId, chapterTitle, sceneTitle,
        sceneSummary: sceneSummary, sceneContent: sceneContent, insertAfterChapterId: insertAfterChapterId);
      
      // 发布结构更新事件（合并为一次，附带必要数据，供前端本地增量合并）
      final String? chapterId = response['chapterId']?.toString();
      final String? sceneId = response['sceneId']?.toString();
      final String? actIdResolved = await _getActIdForChapter(novelId, chapterId ?? '');
      if (chapterId != null) {
        _publishNovelStructureUpdate(
          novelId,
          'CHAPTER_ADDED',
          actId: actIdResolved,
          chapterId: chapterId,
        );
      }
      if (chapterId != null && sceneId != null) {
        _publishNovelStructureUpdate(
          novelId,
          'SCENE_ADDED',
          actId: actIdResolved,
          chapterId: chapterId,
          sceneId: sceneId,
        );
      }
      
      AppLogger.i('EditorRepository/addChapterWithScene', 
          '原子化创建章节和场景成功: chapterId=${response['chapterId']}, sceneId=${response['sceneId']}');
      
      return response;
    } catch (e) {
      AppLogger.e('EditorRepository/addChapterWithScene', '原子化添加章节和场景失败', e);
      throw ApiException(-1, '原子化添加章节和场景失败: $e');
    }
  }

  /// 使用细粒度API更新Act标题
  @override
  Future<bool> updateActTitle(String novelId, String actId, String title) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'title': title,
      };

      await _apiClient.post('/novels/update-act-title', data: requestData);
      _publishNovelStructureUpdate(novelId, 'ACT_TITLE_UPDATED', actId: actId); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateActTitle', '更新Act标题失败', e);
      return false;
    }
  }

  /// 使用细粒度API更新Chapter标题
  @override
  Future<bool> updateChapterTitle(String novelId, String actId, String chapterId, String title) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
        'title': title,
      };

      await _apiClient.post('/novels/update-chapter-title', data: requestData);
      _publishNovelStructureUpdate(novelId, 'CHAPTER_TITLE_UPDATED', actId: actId, chapterId: chapterId); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateChapterTitle', '更新Chapter标题失败', e);
      return false;
    }
  }

  /// 使用细粒度API更新场景摘要
  @override
  Future<bool> updateSummary(String novelId, String actId, String chapterId, String sceneId, String summary) async {
    try {
      // 防抖控制，避免短时间内多次触发
      final String cacheKey = '${novelId}_${actId}_${chapterId}_${sceneId}_summary';
      final now = DateTime.now();
      final lastUpdate = _lastSummaryUpdateTime[cacheKey];
      if (lastUpdate != null && now.difference(lastUpdate) < _summaryUpdateDebounceInterval) {
        AppLogger.i('EditorRepository/updateSummary', '摘要更新请求被节流，跳过此次更新');
        return true; // 跳过但返回成功
      }
      _lastSummaryUpdateTime[cacheKey] = now;

      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
        'sceneId': sceneId,
        'summary': summary,
      };

      await _apiClient.post('/novels/update-scene-summary', data: requestData);
      
      // 更新本地缓存 - 尽量不重复读取
      try {
        // 创建新的摘要对象
        final Summary summaryObj = Summary(
          id: '${sceneId}_summary',
          content: summary,
        );
        
        // 尝试获取现有场景的参考信息，避免重新读取全部内容
        final existingScene = await _localStorageService.getSceneContent(
          novelId, actId, chapterId, sceneId);
          
        // 创建更新后的场景对象
        if (existingScene != null) {
          final updatedScene = existingScene.copyWith(
            summary: summaryObj,
          );
          await _localStorageService.saveSceneContent(
            novelId, actId, chapterId, sceneId, updatedScene
          );
          AppLogger.i('EditorRepository/updateSummary', '场景摘要已更新到本地存储');
        }
      } catch (e) {
        AppLogger.e('EditorRepository/updateSummary', '更新本地摘要缓存失败', e);
      }
      
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateSummary', '更新场景摘要失败', e);
      return false;
    }
  }

  /// 使用细粒度API删除场景
  @override
  Future<bool> deleteScene(String novelId, String actId, String chapterId, String sceneId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
        'sceneId': sceneId,
      };

      await _apiClient.post('/novels/delete-scene', data: requestData);
      _publishNovelStructureUpdate(novelId, 'SCENE_DELETED', actId: actId, chapterId: chapterId, sceneId: sceneId); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/deleteScene', '删除场景失败', e);
      return false;
    }
  }

  /// 使用细粒度API删除章节
  @override
  Future<bool> deleteChapterFine(String novelId, String actId, String chapterId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
      };

      await _apiClient.post('/novels/delete-chapter-fine', data: requestData);
      _publishNovelStructureUpdate(novelId, 'CHAPTER_DELETED', actId: actId, chapterId: chapterId); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/deleteChapterFine', '删除章节失败', e);
      return false;
    }
  }
  
  /// 细粒度删除卷 - 只提供ID
  @override
  Future<bool> deleteActFine(String novelId, String actId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
      };
      
      await _apiClient.post('/novels/act/delete', data: requestData);
      _publishNovelStructureUpdate(novelId, 'ACT_DELETED', actId: actId); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/deleteActFine', '删除卷失败', e);
      return false;
    }
  }
  
  /// 删除章节
  @override
  Future<Novel?> deleteChapter(String novelId, String actId, String chapterId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'actId': actId,
        'chapterId': chapterId,
      };
      
      final response = await _apiClient.post('/novels/chapter/delete', data: requestData);
      
      if (response != null) {
        return _convertBackendNovelWithScenesToFrontend(response);
      }
      
      return null;
    } catch (e) {
      AppLogger.e('EditorRepository/deleteChapter', '删除章节失败', e);
      return null;
    }
  }
  
  /// 细粒度删除场景 - 只提供ID
  @override
  Future<bool> deleteSceneFine(String sceneId) async {
    try {
      await _apiClient.post('/novels/scene/delete-by-id', data: {'sceneId': sceneId});
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/deleteSceneFine', '删除场景失败', e);
      return false;
    }
  }
  
  /// 更新小说元数据
  @override
  Future<void> updateNovelMetadata({
    required String novelId,
    required String title,
    String? author,
    String? series,
  }) async {
    try {
      final requestData = {
        'title': title,
        if (author != null) 'author': author,
        if (series != null) 'seriesName': series,
      };
      
      await _apiClient.post('/novels/$novelId/metadata', data: requestData);
    } catch (e) {
      AppLogger.e('EditorRepository/updateNovelMetadata', '更新小说元数据失败', e);
      throw ApiException(-1, '更新小说元数据失败: $e');
    }
  }
  
  /// 获取封面上传凭证
  @override
  Future<Map<String, dynamic>> getCoverUploadCredential({
    required String novelId,
    required String fileName,
  }) async {
    try {
      final response = await _apiClient.post('/novels/$novelId/cover-upload-credential', 
        data: {'fileName': fileName});
      
      return response;
    } catch (e) {
      AppLogger.e('EditorRepository/getCoverUploadCredential', '获取封面上传凭证失败', e);
      throw ApiException(-1, '获取封面上传凭证失败: $e');
    }
  }
  
  /// 更新小说封面
  @override
  Future<void> updateNovelCover({
    required String novelId,
    required String coverUrl,
  }) async {
    try {
      await _apiClient.post('/novels/$novelId/cover', 
        data: {'coverUrl': coverUrl});
    } catch (e) {
      AppLogger.e('EditorRepository/updateNovelCover', '更新小说封面失败', e);
      throw ApiException(-1, '更新小说封面失败: $e');
    }
  }
  
  /// 删除小说
  @override
  Future<void> deleteNovel({
    required String novelId,
  }) async {
    try {
      await _apiClient.delete('/novels/$novelId');
    } catch (e) {
      AppLogger.e('EditorRepository/deleteNovel', '删除小说失败', e);
      throw ApiException(-1, '删除小说失败: $e');
    }
  }
  
  /// 为指定场景生成摘要
  @override
  Future<String> summarizeScene(String sceneId, {String? additionalInstructions}) async {
    try {
      final response = await _apiClient.post('/ai/summarize-scene', 
        data: {
          'sceneId': sceneId,
          'additionalInstructions': additionalInstructions
        });
      
      if (response != null && response.containsKey('summary')) {
        return response['summary'];
      }
      
      return '';
    } catch (e) {
      AppLogger.e('EditorRepository/summarizeScene', '生成场景摘要失败', e);
      throw ApiException(-1, '生成场景摘要失败: $e');
    }
  }
  
  /// 根据摘要生成场景内容（流式）
   @override
  Stream<String> generateSceneFromSummaryStream(
    String novelId, 
    String summary, 
    {String? chapterId, String? additionalInstructions}
  ) {
    try {
      final request = GenerateSceneFromSummaryRequest(
        summary: summary,
        chapterId: chapterId,
        additionalInstructions: additionalInstructions,
      );
      
      AppLogger.i(_tag, '开始流式生成场景内容，小说ID: $novelId, 摘要长度: ${summary.length}');
      
      return SseClient().streamEvents<String>(
        path: '/novels/$novelId/scenes/generate-from-summary',
        method: SSERequestType.POST,
        body: request.toJson(),
        parser: (json) {
          // 增强解析器的错误处理
          if (json.containsKey('error')) {
            AppLogger.e(_tag, '服务器返回错误: ${json['error']}');
            throw ApiException(-1, '服务器返回错误: ${json['error']}');
          }
          
          if (!json.containsKey('data')) {
            AppLogger.w(_tag, '服务器响应中缺少data字段: $json');
            return ''; // 返回空字符串而不是抛出异常
          }
          
          final data = json['data'];
          if (data == null) {
            AppLogger.w(_tag, '服务器响应中data字段为null');
            return '';
          }
          
          if (data is! String) {
            AppLogger.w(_tag, '服务器响应中data字段不是字符串类型: $data');
            return data.toString();
          }
          
          if (data == '[DONE]') {
            AppLogger.i(_tag, '收到流式生成完成标记: [DONE]');
            return '';
          }
          
          return data;
        },
        connectionId: 'scene_gen_${DateTime.now().millisecondsSinceEpoch}',
      ).where((chunk) => chunk.isNotEmpty); // 过滤掉空字符串
    } catch (e) {
      AppLogger.e(_tag, '流式生成场景内容失败，小说ID: $novelId', e);
      return Stream.error(Exception('流式生成场景内容失败: ${e.toString()}'));
    }
  }
  
  @override
  Future<String> generateSceneFromSummary(
    String novelId, 
    String summary, 
    {String? chapterId, String? additionalInstructions}
  ) async {
    try {
      final request = GenerateSceneFromSummaryRequest(
        summary: summary,
        chapterId: chapterId,
        additionalInstructions: additionalInstructions,
      );
      
      final response = await _apiClient.post(
        '/novels/$novelId/scenes/generate-from-summary-sync',
        data: request.toJson(),
      );
      
      final sceneResponse = GenerateSceneFromSummaryResponse.fromJson(response);
      return sceneResponse.content;
    } catch (e) {
      AppLogger.e(_tag, '生成场景内容失败，小说ID: $novelId', e);
      throw Exception('生成场景内容失败: ${e.toString()}');
    }
  }


  
  /// 提交自动续写任务
  @override
  Future<String> submitContinueWritingTask({
    required String novelId,
    required int numberOfChapters,
    required String aiConfigIdSummary,
    required String aiConfigIdContent,
    required String startContextMode,
    int? contextChapterCount,
    String? customContext,
    String? writingStyle,
    bool? requiresReview,
    bool? persistChanges,
    String? summaryPromptTemplateId,
    String? contentPromptTemplateId,
    String? summaryPublicModelConfigId,
    String? contentPublicModelConfigId,
  }) async {
    try {
      final requestData = {
        'novelId': novelId,
        'numberOfChapters': numberOfChapters,
        'aiConfigIdSummary': aiConfigIdSummary,
        'aiConfigIdContent': aiConfigIdContent,
        'startContextMode': startContextMode,
        'contextChapterCount': contextChapterCount,
        'customContext': customContext,
        'writingStyle': writingStyle,
        // 由表单明确传入（默认：评审=true时通常不持久化，二者可独立配置）
        'requiresReview': requiresReview ?? false,
        'persistChanges': persistChanges ?? false,
        // 可选：提示词模板（摘要/内容）
        'summaryPromptTemplateId': summaryPromptTemplateId,
        'contentPromptTemplateId': contentPromptTemplateId,
        // 公共模型配置ID（可选）
        'summaryPublicModelConfigId': summaryPublicModelConfigId,
        'contentPublicModelConfigId': contentPublicModelConfigId,
      };
      
      // 后端控制器: TaskContinueWritingController => baseUrl(/api/v1) + /api/tasks/continue-writing
      final response = await _apiClient.post('/api/tasks/continue-writing', data: requestData);
      
      if (response != null && response.containsKey('taskId')) {
        return response['taskId'];
      }
      
      throw ApiException(-1, '提交续写任务失败：无效的响应');
    } catch (e) {
      AppLogger.e('EditorRepository/submitContinueWritingTask', '提交续写任务失败', e);
      throw ApiException(-1, '提交续写任务失败: $e');
    }
  }
  
  /// 批量更新小说字数统计（细粒度更新）
  @override
  Future<bool> updateNovelWordCounts(String novelId, Map<String, int> sceneWordCounts) async {
    try {
      final requestData = {
        'novelId': novelId,
        'wordCounts': sceneWordCounts,
      };
      
      await _apiClient.post('/novels/$novelId/update-word-counts', data: requestData);
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateNovelWordCounts', '更新小说字数统计失败', e);
      return false;
    }
  }
  
  /// 仅更新小说结构（不包含场景内容）
  @override
  Future<bool> updateNovelStructure(Novel novel) async {
    try {
      final structureJson = {
        'id': novel.id,
        'structure': {
          'acts': novel.acts.map((act) => {
            'id': act.id,
            'title': act.title,
            'order': act.order,
            'chapters': act.chapters.map((chapter) => {
              'id': chapter.id,
              'title': chapter.title,
              'order': chapter.order,
              'sceneIds': chapter.scenes.map((scene) => scene.id).toList(),
            }).toList(),
          }).toList(),
        },
      };
      
      await _apiClient.post('/novels/${novel.id}/update-structure', data: structureJson);
      _publishNovelStructureUpdate(novel.id, 'NOVEL_STRUCTURE_BULK_UPDATED'); // Publish event
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateNovelStructure', '更新小说结构失败', e);
      return false;
    }
  }

  /// 添加新的Act
  Future<Novel?> addNewAct(String novelId, String title) async {
    try {
      AppLogger.i('EditorRepositoryImpl/addNewAct', '开始添加新Act: novelId=$novelId, title=$title');

      // 1) 细粒度创建卷（只改结构）
      final Act newAct = await addActFine(novelId, title)
          .timeout(const Duration(seconds: 15));
      AppLogger.i('EditorRepositoryImpl/addNewAct', '细粒度创建新Act完成: id=${newAct.id}');

      // 2) 优先本地增量更新，避免清缓存导致未同步内容丢失
      Novel? localNovel;
      try {
        localNovel = await _localStorageService.getNovel(novelId);
      } catch (e) {
        AppLogger.w('EditorRepositoryImpl/addNewAct', '读取本地 Novel 缓存失败，稍后将回退到远程拉取', e);
      }

      if (localNovel != null) {
        final List<Act> updatedActs = List<Act>.from(localNovel.acts)
          ..add(newAct);

        final updatedNovel = localNovel.copyWith(
          acts: updatedActs,
          updatedAt: DateTime.now(),
        );

        // 仅保存到本地，保持未同步内容安全
        await _localStorageService.saveNovel(updatedNovel);

        // 发布结构更新事件
        _publishNovelStructureUpdate(novelId, 'ACT_ADDED', actId: newAct.id);

        return updatedNovel;
      }

      // 3) 本地不存在时，再回退到远程拉取（首次加载等场景）
      AppLogger.i('EditorRepositoryImpl/addNewAct', '本地缓存不存在，回退到远程拉取最新 Novel');
      final remoteNovel = await getNovelWithAllScenes(novelId)
          .timeout(const Duration(seconds: 20));

      if (remoteNovel != null) {
        await _localStorageService.saveNovel(remoteNovel);
        _publishNovelStructureUpdate(novelId, 'ACT_ADDED', actId: newAct.id);
      } else {
        AppLogger.e('EditorRepositoryImpl/addNewAct', '远程拉取 Novel 失败，返回 null');
      }

      return remoteNovel;
    } on TimeoutException catch (_) {
      AppLogger.e('EditorRepositoryImpl/addNewAct', '创建卷接口请求超时');
      return null;
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/addNewAct', '添加新Act失败', e);
      return null;
    }
  }

  /// 添加新的Chapter
  Future<Novel?> addNewChapter(String novelId, String actId, String title) async {
    try {
      AppLogger.i('EditorRepositoryImpl/addNewChapter',
          '开始添加新Chapter: novelId=$novelId, actId=$actId, title=$title');

      // 1. 先调用细粒度接口创建章节，并添加 15 秒超时，避免长时间卡住 UI
      final newChapter = await addChapterFine(novelId, actId, title)
          .timeout(const Duration(seconds: 15));
      AppLogger.i('EditorRepositoryImpl/addNewChapter', '细粒度创建新Chapter完成');

      // 2. 尝试读取本地缓存的 Novel
      Novel? localNovel;
      try {
        localNovel = await _localStorageService.getNovel(novelId);
      } catch (e) {
        AppLogger.w('EditorRepositoryImpl/addNewChapter',
            '读取本地 Novel 缓存失败，稍后将回退到远程拉取', e);
      }

      if (localNovel != null) {
        // 在本地模型中插入新章节
        final List<Act> updatedActs = localNovel.acts.map((act) {
          if (act.id == actId) {
            final List<Chapter> updatedChapters = List<Chapter>.from(act.chapters)
              ..add(newChapter);
            return act.copyWith(chapters: updatedChapters);
          }
          return act;
        }).toList();

        final updatedNovel = localNovel.copyWith(
          acts: updatedActs,
          lastEditedChapterId: newChapter.id,
          updatedAt: DateTime.now(),
        );

        // 保存回本地
        await _localStorageService.saveNovel(updatedNovel);

        _publishNovelStructureUpdate(novelId, 'CHAPTER_ADDED',
            actId: actId, chapterId: newChapter.id);

        return updatedNovel;
      }

      // 3. 如果本地没有 Novel 数据，仍然回退到远程拉取（兼容首次加载场景）
      AppLogger.i('EditorRepositoryImpl/addNewChapter',
          '本地缓存不存在，回退到远程拉取最新 Novel');

      final remoteNovel = await getNovelWithAllScenes(novelId)
          .timeout(const Duration(seconds: 20));

      if (remoteNovel != null) {
        await _localStorageService.saveNovel(remoteNovel);
        _publishNovelStructureUpdate(novelId, 'CHAPTER_ADDED',
            actId: actId, chapterId: newChapter.id);
      } else {
        AppLogger.e('EditorRepositoryImpl/addNewChapter',
            '远程拉取 Novel 失败，返回 null');
      }

      return remoteNovel;
    } on TimeoutException catch (_) {
      AppLogger.e('EditorRepositoryImpl/addNewChapter', '创建章节接口请求超时');
      return null;
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/addNewChapter', '添加新Chapter失败', e);
      return null;
    }
  }
  /// 使用细粒度API移动场景
  @override
  Future<Novel?> moveScene(
      String novelId,
      String sourceActId,
      String sourceChapterId,
      String sourceSceneId,
      String targetActId,
      String targetChapterId,
      int targetIndex) async {
    try {
      final requestData = {
        'novelId': novelId,
        'sourceActId': sourceActId,
        'sourceChapterId': sourceChapterId,
        'sourceSceneId': sourceSceneId,
        'targetActId': targetActId,
        'targetChapterId': targetChapterId,
        'targetIndex': targetIndex,
      };

      final response = await _apiClient.post('/novels/scenes/move', data: requestData);
      
      if (response != null) {
        // 返回的应该是更新后的小说结构
        final updatedNovel = _convertBackendNovelWithScenesToFrontend(response);
        _publishNovelStructureUpdate(novelId, 'SCENE_MOVED_OR_STRUCTURE_CHANGED', actId: targetActId, chapterId: targetChapterId, sceneId: sourceSceneId ); // Publish event
        return updatedNovel;
      }
      
      return null;
    } catch (e) {
      AppLogger.e('EditorRepository/moveScene', '移动场景失败', e);
      return null;
    }
  }

  /// 批量保存场景内容
  @override
  Future<bool> batchSaveSceneContents(
      String novelId, List<Map<String, dynamic>> sceneUpdates) async {
    try {  
      AppLogger.i('EditorRepositoryImpl/batchSaveSceneContents', '批量保存场景: ${sceneUpdates.length}个场景');
      
      // 转换为Scene对象列表
      List<Scene> processedScenes = [];
      for (final sceneData in sceneUpdates) {
        try {
          // 确保必要字段存在并有值
          final String sceneId = sceneData['id'] as String? ?? sceneData['sceneId'] as String? ?? '';
          final String content = sceneData['content'] as String? ?? '';
          final String? title = sceneData['title'] as String?;
          final String? summaryContent = sceneData['summary'] as String?;
          final String actId = sceneData['actId'] as String? ?? '';
          final String chapterId = sceneData['chapterId'] as String? ?? '';
          
          // 验证必需字段
          if (sceneId.isEmpty || chapterId.isEmpty || actId.isEmpty) {
            AppLogger.w('EditorRepositoryImpl/batchSaveSceneContents', 
                '场景数据缺少必要字段: sceneId=$sceneId, chapterId=$chapterId, actId=$actId');
            continue; // 跳过不完整的数据
          }
          
          final int wordCount = sceneData['wordCount'] is int 
              ? sceneData['wordCount'] as int 
              : int.tryParse(sceneData['wordCount']?.toString() ?? '0') ?? 0;
          
          // 创建摘要对象
          final summary = Summary(
            id: '', // 通常摘要ID会自动生成
            content: summaryContent ?? ''
          );
          
          // 创建场景对象
          final scene = Scene(
            id: sceneId,
            title: title ?? '',
            content: content,
            actId: actId,
            chapterId: chapterId,
            wordCount: wordCount,
            summary: summary,
            lastEdited: DateTime.now(),
            version: 1,
            history: [],
          );
          
          processedScenes.add(scene);
        } catch (e) {
          AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '处理场景数据失败', e);
        }
      }
      
      // 如果没有有效场景，返回失败
      if (processedScenes.isEmpty) {
        AppLogger.w('EditorRepositoryImpl/batchSaveSceneContents', '没有有效场景可以保存');
        return false;
      }
      
      // 批量保存到本地存储
      for (final scene in processedScenes) {
        try {
          await _saveSceneToLocalStorage(novelId, scene);
        } catch (e) {
          AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '保存场景到本地失败: ${scene.id}', e);
        }
      }
      
      // 批量同步到服务器
      try {
        // 确保数据结构符合后端期望
        // 获取第一个场景的章节ID，确保所有场景属于同一章节
        final String chapterId = processedScenes.first.chapterId ?? '';
        if (chapterId.isEmpty) {
          AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '无法确定章节ID，无法批量保存');
          return false;
        }
        
        // 使用ChapterScenesDto格式的数据结构
        final batchData = {
          'novelId': novelId,
          'chapterId': chapterId,
          'scenes': processedScenes.map((scene) => {
            'id': scene.id,
            'novelId': novelId,
            'chapterId': chapterId,
            'content': scene.content,
            'summary': scene.summary?.content,
            'wordCount': scene.wordCount,
            'title': scene.title,
          }).toList(),
        };
        
        // 验证数据
        AppLogger.d('EditorRepositoryImpl/batchSaveSceneContents', 
            '发送批量场景数据: novelId=${novelId}, chapterId=${chapterId}, 场景数=${processedScenes.length}');
        
        // 打印第一个场景的数据用于调试
        if (processedScenes.isNotEmpty) {
          AppLogger.d('EditorRepositoryImpl/batchSaveSceneContents', 
              '样本场景数据: id=${processedScenes.first.id}, chapterId=${processedScenes.first.chapterId}');
        }
        
        // 使用正确的端点
        final response = await _apiClient.post('/novels/upsert-chapter-scenes-batch', data: batchData);
        
        if (response != null) {
          AppLogger.i('EditorRepositoryImpl/batchSaveSceneContents', '批量场景内容已同步到服务器');
          return true;
        } else {
          AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '批量同步场景到服务器失败');
          return false;
        }
      } catch (e) {
        AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '批量同步场景到服务器时出错', e);
        return false;
      }
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/batchSaveSceneContents', '批量保存场景内容失败', e);
      return false;
    }
  }

  /// 保存单个场景到本地存储
  Future<void> _saveSceneToLocalStorage(String novelId, Scene scene) async {
    try {
      // 验证小说ID
      if (novelId.isEmpty) {
        AppLogger.e('EditorRepositoryImpl/_saveSceneToLocalStorage', '小说ID为空');
        return;
      }
      
      // 验证场景ID和章节ID
      final String sceneId = scene.id ?? '';
      final String chapterId = scene.chapterId ?? '';
      final String actId = scene.actId ?? '';
      
      if (sceneId.isEmpty || chapterId.isEmpty || actId.isEmpty) {
        AppLogger.e('EditorRepositoryImpl/_saveSceneToLocalStorage', 
            '场景缺少必要信息: chapterId=$chapterId, sceneId=$sceneId, actId=$actId');
        return;
      }
      
      AppLogger.v('EditorRepositoryImpl/_saveSceneToLocalStorage', 
          '场景保存到本地: $sceneId');
      
      await _localStorageService.saveSceneContent(
        novelId,
        actId,
        chapterId,
        sceneId,
        scene
      );
      
      AppLogger.i('EditorRepositoryImpl/_saveSceneToLocalStorage', 
          '场景已保存到本地: $sceneId');
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/_saveSceneToLocalStorage', 
          '保存场景到本地失败', e);
      // 捕获异常但不再抛出，避免中断批量保存流程
    }
  }

  /// 查找章节所属的Act ID
  Future<String?> _getActIdForChapter(String novelId, String chapterId) async {
    try {
      final novel = await getNovel(novelId);
      if (novel == null) return null;
      
      for (final act in novel.acts) {
        for (final chapter in act.chapters) {
          if (chapter.id == chapterId) {
            return act.id;
          }
        }
      }
      
      return null;
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/_getActIdForChapter', '查找章节对应Act失败', e);
      return null;
    }
  }

  /// 获取小说（带场景摘要）
  @override
  Future<Novel?> getNovelWithSceneSummaries(String novelId, {bool readOnly = false}) async {
    try {
      AppLogger.i('EditorRepository/getNovelWithSceneSummaries', '正在获取带场景摘要的小说结构: $novelId, readOnly: $readOnly');
      
      // 调用API获取带场景摘要的小说数据
      final data = await _apiClient.post('/novels/get-with-scene-summaries', data: {'id': novelId});
      
      if (data != null) {
        try {
          AppLogger.i('EditorRepository/getNovelWithSceneSummaries', '成功获取服务器数据，开始解析');
          
          // 在解析前记录数据结构摘要，帮助调试
          if (data is Map) {
            final keys = data.keys.toList();
            AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                '服务器返回数据包含以下字段: $keys');
                
            // 检查novel字段结构
            if (data.containsKey('novel') && data['novel'] is Map) {
              final novelData = data['novel'] as Map;
              final novelKeys = novelData.keys.toList();
              AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                  'novel字段包含以下子字段: $novelKeys');
                  
              // 特别检查structure字段和acts字段
              if (novelData.containsKey('structure')) {
                if (novelData['structure'] is Map) {
                  final structureData = novelData['structure'] as Map;
                  AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                      'structure字段包含以下子字段: ${structureData.keys.toList()}');
                      
                  if (structureData.containsKey('acts')) {
                    final actsData = structureData['acts'];
                    final actsType = actsData.runtimeType.toString();
                    final actsLength = actsData is List ? actsData.length : 'non-list';
                    AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                        'acts字段类型: $actsType, 长度: $actsLength');
                  } else {
                    AppLogger.w('EditorRepository/getNovelWithSceneSummaries', 
                        'structure字段中缺少acts字段');
                  }
                } else {
                  AppLogger.w('EditorRepository/getNovelWithSceneSummaries', 
                      'structure字段不是Map类型: ${novelData['structure'].runtimeType}');
                }
              } else {
                AppLogger.w('EditorRepository/getNovelWithSceneSummaries', 
                    'novel字段中缺少structure字段');
              }
            }
            
            // 检查sceneSummariesByChapter字段
            if (data.containsKey('sceneSummariesByChapter')) {
              final summariesData = data['sceneSummariesByChapter'];
              final summariesType = summariesData.runtimeType.toString();
              AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                  'sceneSummariesByChapter字段类型: $summariesType');
                  
              if (summariesData is Map) {
                final chapterIds = summariesData.keys.toList();
                AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                    'sceneSummariesByChapter包含 ${chapterIds.length} 个章节ID');
                    
                // 检查第一个章节的场景摘要结构
                if (chapterIds.isNotEmpty) {
                  final firstChapterScenes = summariesData[chapterIds.first];
                  AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
                      '第一个章节 ${chapterIds.first} 的场景摘要类型: ${firstChapterScenes.runtimeType}');
                }
              }
            } else {
              AppLogger.w('EditorRepository/getNovelWithSceneSummaries', 
                  '服务器返回数据中缺少sceneSummariesByChapter字段');
            }
          }
          
          // 使用新的DTO模型处理返回数据
          final novelWithSummaries = NovelWithSummariesDto.fromJson(data);
          
          // 将场景摘要合并到小说模型中
          final novelWithMergedSummaries = novelWithSummaries.mergeSceneSummariesToNovel();
          
          AppLogger.i('EditorRepository/getNovelWithSceneSummaries', 
              '成功获取小说结构和场景摘要，共有${novelWithSummaries.novel.acts.length}个卷，${novelWithSummaries.sceneSummariesByChapter.length}个章节包含摘要');
              
          // 缓存处理后的小说模型到本地存储 - 仅当不是只读时
          if (!readOnly) {
            await _localStorageService.saveNovel(novelWithMergedSummaries);
          }
          
          return novelWithMergedSummaries;
        } catch (e) {
          AppLogger.e('EditorRepository/getNovelWithSceneSummaries', '解析小说摘要数据失败', e);
          
          // 解析失败时尝试使用原来的方法
          try {
            AppLogger.i('EditorRepository/getNovelWithSceneSummaries', '尝试使用后备转换方法');
            final novel = _convertBackendNovelWithScenesToFrontend(data);
            
            // 保存到本地存储 - 仅当不是只读时
            if (!readOnly) {
              await _localStorageService.saveNovel(novel);
            }
            
            return novel;
          } catch (backupError) {
            AppLogger.e('EditorRepository/getNovelWithSceneSummaries', '后备转换方法也失败', backupError);
            // 如果后备方法也失败，尝试从本地获取
            AppLogger.i('EditorRepository/getNovelWithSceneSummaries', '尝试从本地存储获取小说数据');
            return await getNovel(novelId); // getNovel might also save, consider its readOnly needs
          }
        }
      }
      
      AppLogger.w('EditorRepository/getNovelWithSceneSummaries', '服务器返回空数据');
      // 从本地存储获取
      return await getNovel(novelId); // getNovel might also save
    } catch (e) {
      AppLogger.e('EditorRepository/getNovelWithSceneSummaries', '获取小说带摘要失败', e);
      // 尝试从本地获取
      AppLogger.i('EditorRepository/getNovelWithSceneSummaries', '尝试从本地存储获取小说数据');
      return await getNovel(novelId); // getNovel might also save
    }
  }

  /// 使用细粒度API添加新场景
  @override
  Future<Novel?> addNewScene(String novelId, String actId, String chapterId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'chapterId': chapterId,
        'title': '新场景',
        'summary': '',
      };

      final response = await _apiClient.post('/scenes/add-scene-fine', data: requestData);
      
      if (response != null && response.containsKey('id')) {
        // 细粒度接口返回的是单个场景，需要重新获取完整小说结构
        final newScene = Scene.fromJson(response);
        _publishNovelStructureUpdate(novelId, 'SCENE_ADDED', actId: actId, chapterId: chapterId, sceneId: newScene.id);
        
        // 重新获取完整的小说结构
        return await getNovel(novelId);
      }
      
      return null;
    } catch (e) {
      AppLogger.e('EditorRepository/addNewScene', '添加新场景失败', e);
      return null;
    }
  }

  /// 智能同步小说
  @override
  Future<bool> smartSyncNovel(Novel novel, {Set<String>? changedComponents}) async {
    try {
      // 如果没有指定变更组件，则发送完整小说数据
      if (changedComponents == null || changedComponents.isEmpty) {
        final backendNovelJson = _convertFrontendNovelToBackendJson(novel);
        await _apiClient.updateNovel(backendNovelJson);
        _publishNovelStructureUpdate(novel.id, 'NOVEL_SMART_SYNCED_FULL'); // Publish event
        return true;
      }
      
      // 根据变更组件选择性同步
      bool structurePotentiallyChanged = false;
      if (changedComponents.contains('metadata')) {
        // 仅同步元数据（标题/作者/系列）
        final metadataJson = {
          'title': novel.title,
          if (novel.author?.username != null && novel.author!.username.isNotEmpty)
            'author': novel.author!.username,
          // seriesName 不在 Novel 模型中，若需要由上层传入
        };
        await _apiClient.post('/novels/${novel.id}/metadata', data: metadataJson);
      }
      
      if (changedComponents.contains('lastEditedChapterId') && novel.lastEditedChapterId != null) {
        // 仅同步最后编辑章节
        await updateLastEditedChapterId(novel.id, novel.lastEditedChapterId!);
      }
      
      if (changedComponents.contains('actTitles') || changedComponents.contains('chapterTitles')) {
        // 同步结构（不包括场景内容）
        final structureJson = {
          'id': novel.id,
          'structure': {
            'acts': novel.acts.map((act) => {
              'id': act.id,
              'title': act.title,
              'order': act.order,
              'chapters': act.chapters.map((chapter) => {
                'id': chapter.id,
                'title': chapter.title,
                'order': chapter.order,
                'sceneIds': chapter.scenes.map((scene) => scene.id).toList(),
              }).toList(),
            }).toList(),
          },
        };
        await _apiClient.post('/novels/${novel.id}/update-structure', data: structureJson);
        structurePotentiallyChanged = true;
      }

      if (structurePotentiallyChanged) {
         _publishNovelStructureUpdate(novel.id, 'NOVEL_SMART_SYNCED_PARTIAL'); // Publish event
      }
      
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/smartSyncNovel', '智能同步小说失败', e);
      return false;
    }
  }

  /// 更新最后编辑章节ID
  @override
  Future<bool> updateLastEditedChapterId(String novelId, String chapterId) async {
    try {
      final requestData = {
        'novelId': novelId,
        'chapterId': chapterId,
      };

      await _apiClient.post('/novels/update-last-edited-chapter', data: requestData);
      return true;
    } catch (e) {
      AppLogger.e('EditorRepository/updateLastEditedChapterId', '更新最后编辑章节ID失败', e);
      return false;
    }
  }

  /// 获取编辑器设置
  @override
  Future<Map<String, dynamic>> getEditorSettings() async {
    try {
      final settings = await _localStorageService.getEditorSettings();
      if (settings != null) {
        return settings;
      }
      // 返回默认设置
      return {
        'fontSize': 16.0,
        'fontFamily': 'Serif',
        'lineSpacing': 1.5,
        'spellCheckEnabled': true,
        'autoSaveEnabled': true,
        'autoSaveIntervalMinutes': 2,
        'darkModeEnabled': false,
      };
    } catch (e) {
      AppLogger.e('EditorRepository/getEditorSettings', '获取编辑器设置失败', e);
      // 返回默认设置
      return {
        'fontSize': 16.0,
        'fontFamily': 'Serif',
        'lineSpacing': 1.5,
        'spellCheckEnabled': true,
        'autoSaveEnabled': true,
        'autoSaveIntervalMinutes': 2,
        'darkModeEnabled': false,
      };
    }
  }

  /// 保存编辑器设置
  @override
  Future<void> saveEditorSettings(Map<String, dynamic> settings) async {
    try {
      // 直接保存Map到本地存储
      await _localStorageService.saveEditorSettings(settings);
    } catch (e) {
      AppLogger.e('EditorRepository/saveEditorSettings', '保存编辑器设置失败', e);
      throw ApiException(-1, '保存编辑器设置失败: $e');
    }
  }

  /// 从本地获取章节的场景
  @override
  Future<List<Scene>> getLocalScenesForChapter(String novelId, String actId, String chapterId) async {
    try {
      // 从本地存储中查找该章节的所有场景
      final result = <Scene>[];
      
      // 先获取小说信息，查找章节中存储的场景ID
      final novel = await _localStorageService.getNovel(novelId);
      if (novel == null) {
        return result;
      }
      
      // 找到对应的章节
      Chapter? targetChapter;
      for (final act in novel.acts) {
        if (act.id == actId) {
          for (final chapter in act.chapters) {
            if (chapter.id == chapterId) {
              targetChapter = chapter;
              break;
            }
          }
          if (targetChapter != null) break;
        }
      }
      
      if (targetChapter == null) {
        return result;
      }
      
      // 如果章节已有场景，直接返回
      if (targetChapter.scenes.isNotEmpty) {
        return targetChapter.scenes;
      }
      
      // 如果章节没有场景，由于没有getSceneIdsForChapter方法
      // 我们直接返回空列表
      return result;
    } catch (e) {
      AppLogger.e('EditorRepository/getLocalScenesForChapter', '从本地获取章节场景失败', e);
      return [];
    }
  }
  
  /// 细粒度批量添加场景 - 一次添加多个场景到同一章节
  @override
  Future<List<Scene>> addScenesBatchFine(String novelId, String chapterId, List<Map<String, dynamic>> scenes) async {
    try {
      final requestData = {
        'novelId': novelId,
        'chapterId': chapterId,
        'scenes': scenes,
      };
      
      final response = await _apiClient.post('/novels/upsert-chapter-scenes-batch', data: requestData);
      
      if (response != null && response is List) {
        return response.map((sceneJson) => Scene.fromJson(sceneJson)).toList();
      }
      
      // 如果API没有返回新场景，创建本地场景
      return scenes.map((sceneData) {
        final sceneId = 'scene_${DateTime.now().millisecondsSinceEpoch}_${scenes.indexOf(sceneData)}';
        return Scene(
          id: sceneId,
          content: QuillHelper.standardEmptyDelta,
          wordCount: 0,
          summary: Summary(
            id: '${sceneId}_summary',
            content: sceneData['summary'] ?? '',
          ),
          lastEdited: DateTime.now(),
          version: 1,
          history: [],
        );
      }).toList();
    } catch (e) {
      AppLogger.e('EditorRepository/addScenesBatchFine', '批量添加场景失败', e);
      throw ApiException(-1, '批量添加场景失败: $e');
    }
  }
  
  /// 归档小说
  @override
  Future<void> archiveNovel({required String novelId}) async {
    try {
      await _apiClient.post('/novels/archive', data: {'novelId': novelId});
    } catch (e) {
      AppLogger.e('EditorRepository/archiveNovel', '归档小说失败', e);
      throw ApiException(-1, '归档小说失败: $e');
    }
  }

  /// 获取小说详情（一次性加载所有场景）
  @override
  Future<Novel?> getNovelWithAllScenes(String novelId) async {
    try {
      AppLogger.i(
          'EditorRepositoryImpl/getNovelWithAllScenes', 
          '从API获取小说(全部场景): novelId=$novelId');
      
      // 使用新的API获取全部数据
      final data = await _apiClient.getNovelWithAllScenes(novelId);
      
      // 检查数据是否为空
      if (data == null) {
        AppLogger.e(
            'EditorRepositoryImpl/getNovelWithAllScenes',
            '从API获取小说(全部场景)失败: 返回空数据');
        return null;
      }

      // 转换数据格式
      final novel = _convertBackendNovelWithScenesToFrontend(data);
      
      // 将小说基本信息保存到本地（包含场景内容）
      await _localStorageService.saveNovel(novel);
      
      // // 将场景内容分别保存到本地
      // for (final act in novel.acts) {
      //   for (final chapter in act.chapters) {
      //     for (final scene in chapter.scenes) {
      //       await _localStorageService.saveSceneContent(
      //         novelId, 
      //         act.id, 
      //         chapter.id, 
      //         scene.id, 
      //         scene
      //       );
      //     }
      //   }
      // }
      
      AppLogger.i(
          'EditorRepositoryImpl/getNovelWithAllScenes', 
          '从API获取小说(全部场景)成功: $novelId, 返回章节数: ${novel.acts.fold(0, (sum, act) => sum + act.chapters.length)}');
      return novel;
    } catch (e) {
      AppLogger.e(
          'EditorRepositoryImpl/getNovelWithAllScenes',
          '从API获取小说(全部场景)失败',
          e);
          
      // 如果获取失败，尝试回退到本地存储
      try {
        final localNovel = await _localStorageService.getNovel(novelId);
        if (localNovel != null) {
          AppLogger.i('EditorRepositoryImpl/getNovelWithAllScenes', 
              '获取失败，回退到本地存储小说: $novelId');
          return localNovel;
        }
      } catch (localError) {
        AppLogger.e(
            'EditorRepositoryImpl/getNovelWithAllScenes',
            '本地存储回退也失败',
            localError);
      }
      return null;
    }
  }
  
  /// 获取指定章节后面的章节列表（用于预加载）
  @override
  Future<ChaptersForPreloadDto?> fetchChaptersForPreload(
    String novelId,
    String currentChapterId, {
    int chaptersLimit = 3,
    bool includeCurrentChapter = false,
  }) async {
    try {
      AppLogger.i('EditorRepositoryImpl/fetchChaptersForPreload',
          '获取章节列表用于预加载: novelId=$novelId, currentChapterId=$currentChapterId, chaptersLimit=$chaptersLimit, includeCurrentChapter=$includeCurrentChapter');

      // 调用后端API
      final requestData = {
        'novelId': novelId,
        'currentChapterId': currentChapterId,
        'chaptersLimit': chaptersLimit,
        'includeCurrentChapter': includeCurrentChapter,
      };

      final data = await _apiClient.post('/novels/get-chapters-for-preload', data: requestData);

      if (data == null) {
        AppLogger.w('EditorRepositoryImpl/fetchChaptersForPreload', '后端返回空数据');
        return null;
      }

      // 将后端返回的数据转换为DTO
      final dto = ChaptersForPreloadDto.fromJson(data);

      AppLogger.i('EditorRepositoryImpl/fetchChaptersForPreload',
          '成功获取章节列表用于预加载: novelId=$novelId, 章节数=${dto.chapterCount}, 场景章节数=${dto.scenesByChapter.keys.length}');

      return dto;
    } catch (e) {
      AppLogger.e('EditorRepositoryImpl/fetchChaptersForPreload',
          '获取章节列表用于预加载失败', e);
      return null;
    }
  }
}
