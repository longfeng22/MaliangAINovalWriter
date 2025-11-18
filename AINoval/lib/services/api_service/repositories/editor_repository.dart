import 'dart:async';
import 'package:ainoval/models/editor_content.dart';
import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/models/chapters_for_preload_dto.dart';
import 'package:ainoval/services/local_storage_service.dart';

/// 编辑器仓库接口
///
/// 定义与编辑器相关的所有API操作
abstract class EditorRepository {
  /// 获取本地存储服务
  LocalStorageService getLocalStorageService();

  /// 获取小说
  Future<Novel?> getNovel(String novelId);

  /// 获取小说详情（分页加载场景）
  /// 基于上次编辑章节为中心，获取前后指定数量的章节及其场景内容
  Future<Novel?> getNovelWithPaginatedScenes(String novelId, String lastEditedChapterId, {int chaptersLimit = 5});

  /// 获取小说详情（一次性加载所有场景）
  /// 一次性获取小说的所有章节及其场景内容
  Future<Novel?> getNovelWithAllScenes(String novelId);

  /// 加载更多章节场景
  /// 根据方向（向上或向下）加载更多章节的场景内容
  Future<Map<String, List<Scene>>> loadMoreScenes(String novelId, String? actId, String fromChapterId, String direction, {int chaptersLimit = 5});

  /// 保存小说数据
  Future<bool> saveNovel(Novel novel);

  /// 获取场景内容
  Future<Scene?> getSceneContent(
      String novelId, String actId, String chapterId, String sceneId);

  /// 保存场景内容
  Future<Scene> saveSceneContent(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
    String content,
    String wordCount,
    Summary summary,
    {bool localOnly = false}
  );

  /// 保存摘要
  Future<Summary> saveSummary(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
    String content,
  );

  /// 获取编辑器内容
  Future<EditorContent> getEditorContent(
      String novelId, String chapterId, String sceneId);

  /// 保存编辑器内容
  Future<void> saveEditorContent(EditorContent content);

  /// 获取编辑器设置
  Future<Map<String, dynamic>> getEditorSettings();

  /// 保存编辑器设置
  Future<void> saveEditorSettings(Map<String, dynamic> settings);

  /// 获取修订历史
  Future<List<Revision>> getRevisionHistory(String novelId, String chapterId);

  /// 创建修订版本
  Future<Revision> createRevision(
      String novelId, String chapterId, Revision revision);

  /// 应用修订版本
  Future<void> applyRevision(
      String novelId, String chapterId, String revisionId);
      
  /// 更新小说元数据
  Future<void> updateNovelMetadata({
    required String novelId,
    required String title,
    String? author,
    String? series,
  });
  
  /// 获取封面上传凭证
  Future<Map<String, dynamic>> getCoverUploadCredential({
    required String novelId,
    required String fileName,
  });
  
  /// 更新小说封面
  Future<void> updateNovelCover({
    required String novelId,
    required String coverUrl,
  });
  
  /// 归档小说
  Future<void> archiveNovel({
    required String novelId,
  });
  
  /// 删除小说
  Future<void> deleteNovel({
    required String novelId,
  });
  
  /// 为指定场景生成摘要
  Future<String> summarizeScene(String sceneId, {String? additionalInstructions});
  
  /// 根据摘要生成场景内容（流式）
  Stream<String> generateSceneFromSummaryStream(
    String novelId, 
    String summary, 
    {String? chapterId, String? additionalInstructions}
  );
  
  /// 根据摘要生成场景内容（非流式）
  Future<String> generateSceneFromSummary(
    String novelId, 
    String summary, 
    {String? chapterId, String? additionalInstructions}
  );

  /// 获取小说详情，包含场景摘要（适用于Plan视图）
  Future<Novel?> getNovelWithSceneSummaries(String novelId, {bool readOnly = false});

  /// 提交自动续写任务
  /// 
  /// [novelId] 小说ID
  /// [numberOfChapters] 续写章节数
  /// [aiConfigIdSummary] 摘要模型配置ID
  /// [aiConfigIdContent] 内容模型配置ID
  /// [startContextMode] 上下文模式，可选值: AUTO, LAST_N_CHAPTERS, CUSTOM
  /// [contextChapterCount] 上下文章节数，仅当startContextMode为LAST_N_CHAPTERS时有效
  /// [customContext] 自定义上下文，仅当startContextMode为CUSTOM时有效
  /// [writingStyle] 写作风格提示，可选
  /// [summaryPublicModelConfigId] 摘要阶段公共模型配置ID（可选）
  /// [contentPublicModelConfigId] 内容阶段公共模型配置ID（可选）
  /// 
  /// 返回提交的任务ID
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
  });

  /// 删除场景
  Future<bool> deleteScene(
    String novelId,
    String actId,
    String chapterId,
    String sceneId,
  );

  /// 添加场景
  Future<Scene?> addScene(
    String novelId,
    String actId,
    String chapterId,
    Scene scene,
  );

  /// 删除章节
  Future<Novel?> deleteChapter(
    String novelId,
    String actId,
    String chapterId,
  );

  /// 将后端返回的带场景摘要的小说数据转换为前端模型

  /// 更新小说最后编辑的章节ID（细粒度更新）
  Future<bool> updateLastEditedChapterId(String novelId, String chapterId);

  /// 批量更新小说字数统计（细粒度更新）
  Future<bool> updateNovelWordCounts(String novelId, Map<String, int> sceneWordCounts);

  /// 智能同步小说（根据变更类型选择最优同步策略）
  Future<bool> smartSyncNovel(Novel novel, {Set<String>? changedComponents});

  /// 仅更新小说结构（不包含场景内容）
  Future<bool> updateNovelStructure(Novel novel);

  /// 批量保存场景内容（优化网络请求数量）
  Future<bool> batchSaveSceneContents(
    String novelId,
    List<Map<String, dynamic>> sceneUpdates
  );
  
  /// 细粒度添加卷 - 只提供必要信息
  Future<Act> addActFine(String novelId, String title, {String? description});
  
  /// 细粒度添加章节 - 只提供必要信息
  Future<Chapter> addChapterFine(String novelId, String actId, String title, {String? description});
  
  /// 原子化添加章节和场景 - 在一个事务中同时创建章节和场景，避免数据不一致
  Future<Map<String, dynamic>> addChapterWithScene(String novelId, String actId, 
      String chapterTitle, String sceneTitle, {String? sceneSummary, String? sceneContent, String? insertAfterChapterId});
  
  /// 细粒度添加场景 - 只提供必要信息
  Future<Scene> addSceneFine(String novelId, String chapterId, String title, {String? summary, String? content, int? position});
  
  /// 细粒度批量添加场景 - 一次添加多个场景到同一章节
  Future<List<Scene>> addScenesBatchFine(String novelId, String chapterId, List<Map<String, dynamic>> scenes);
  
  /// 细粒度删除卷 - 只提供ID
  Future<bool> deleteActFine(String novelId, String actId);
  
  /// 细粒度删除章节 - 只提供ID
  Future<bool> deleteChapterFine(String novelId, String actId, String chapterId);
  
  /// 细粒度删除场景 - 只提供ID
  Future<bool> deleteSceneFine(String sceneId);
  
  /// 获取指定章节后面的章节列表（用于预加载）
  /// 
  /// [novelId] 小说ID
  /// [currentChapterId] 当前章节ID
  /// [chaptersLimit] 要获取的章节数量限制
  /// [includeCurrentChapter] 是否包含当前章节
  /// 
  /// 返回包含章节列表和场景数据的ChaptersForPreloadDto
  Future<ChaptersForPreloadDto?> fetchChaptersForPreload(
    String novelId,
    String currentChapterId, {
    int chaptersLimit = 3,
    bool includeCurrentChapter = false,
  });
}
