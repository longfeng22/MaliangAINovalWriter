import 'package:flutter/material.dart';
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/utils/logger.dart';

/// 编辑器项目类型枚举
enum EditorItemType {
  actHeader,
  chapterHeader, 
  scene,
  addSceneButton,
  addChapterButton,
  addActButton,
  actFooter,
  storyPredictionButton,
}

/// 编辑器项目数据类
class EditorItem {
  final EditorItemType type;
  final String id;
  final novel_models.Act? act;
  final novel_models.Chapter? chapter;
  final novel_models.Scene? scene;
  final int? actIndex;
  final int? chapterIndex;
  final int? sceneIndex;
  final bool isLastInChapter;
  final bool isLastInAct;
  final bool isLastInNovel;

  EditorItem({
    required this.type,
    required this.id,
    this.act,
    this.chapter,
    this.scene,
    this.actIndex,
    this.chapterIndex,
    this.sceneIndex,
    this.isLastInChapter = false,
    this.isLastInAct = false,
    this.isLastInNovel = false,
  });
}

/// Center Anchor List Builder
/// 支持从指定章节开始向上下构建ListView的构建器
class CenterAnchorListBuilder {
  final novel_models.Novel novel;
  final String? anchorChapterId; // 锚点章节ID
  final bool isImmersiveMode;
  final String? immersiveChapterId;
  
  // 🚀 新增：锚点有效性标志
  bool _isAnchorValid = true;

  CenterAnchorListBuilder({
    required this.novel,
    this.anchorChapterId,
    this.isImmersiveMode = false,
    this.immersiveChapterId,
  }) {
    // 🚀 新增：构造时验证锚点有效性
    _validateAnchor();
  }
  
  /// 🚀 新增：验证锚点是否有效
  void _validateAnchor() {
    _isAnchorValid = true; // 重置标志
    
    // 如果没有锚点章节，标记为有效（将使用传统模式）
    if (anchorChapterId == null) {
      return;
    }
    
    // 如果小说为空，锚点无效
    if (novel.acts.isEmpty) {
      AppLogger.w('CenterAnchorListBuilder', '小说为空，锚点无效');
      _isAnchorValid = false;
      return;
    }
    
    // 预验证锚点章节是否存在
    bool found = false;
    for (final act in novel.acts) {
      for (final chapter in act.chapters) {
        if (chapter.id == anchorChapterId) {
          found = true;
          break;
        }
      }
      if (found) break;
    }
    
    if (!found) {
      AppLogger.w('CenterAnchorListBuilder', '锚点章节 $anchorChapterId 不存在');
      _isAnchorValid = false;
    }
  }

  /// 构建center anchor模式的slivers
  List<Widget> buildCenterAnchoredSlivers({
    required Widget Function(EditorItem) itemBuilder,
  }) {
    if (isImmersiveMode && immersiveChapterId != null) {
      // 沉浸模式：构建单章内容，保持原有逻辑
      AppLogger.i('CenterAnchorListBuilder', '使用沉浸模式构建，不使用center anchor');
      return _buildImmersiveModeSliver(itemBuilder);
    }

    if (anchorChapterId == null) {
      // 没有锚点：使用传统模式从头构建
      AppLogger.i('CenterAnchorListBuilder', '无锚点章节，使用传统模式构建');
      return _buildTraditionalSlivers(itemBuilder);
    }

    // 🚀 核心功能：从锚点章节开始上下构建
    AppLogger.i('CenterAnchorListBuilder', '使用center anchor模式构建，锚点章节: $anchorChapterId');
    return _buildCenterAnchoredSlivers(itemBuilder);
  }

  /// 🚀 核心方法：构建从锚点章节开始的center-anchored slivers
  List<Widget> _buildCenterAnchoredSlivers(Widget Function(EditorItem) itemBuilder) {
    AppLogger.i('CenterAnchorListBuilder', '构建center-anchored slivers，锚点章节: $anchorChapterId');

    final slivers = <Widget>[];
    
    // 查找锚点章节的位置
    final anchorInfo = _findAnchorChapterInfo();
    if (anchorInfo == null) {
      AppLogger.w('CenterAnchorListBuilder', '未找到锚点章节 $anchorChapterId，回退到传统模式');
      // 🚀 关键修复：当找不到锚点章节时，确保center key也无效
      _invalidateAnchor();
      return _buildTraditionalSlivers(itemBuilder);
    }

    final anchorKey = ValueKey('center_anchor_$anchorChapterId');

    // 1. 构建锚点章节之前的内容（反向）
    final beforeItems = _buildItemsBefore(anchorInfo);
    
    // 🚀 关键修复：确保center anchor前面总是有至少一个sliver
    // Flutter要求center widget不能是第一个sliver
    if (beforeItems.isNotEmpty) {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final reversedIndex = beforeItems.length - 1 - index;
              return itemBuilder(beforeItems[reversedIndex]);
            },
            childCount: beforeItems.length,
          ),
        ),
      );
    } else {
      // 🚀 添加一个空的占位sliver，确保center anchor不是第一个
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox.shrink(), // 不可见的占位widget
        ),
      );
    }

    // 2. 锚点章节组（包括可能的Act标题 + center anchor章节标题）
    final anchorItems = <EditorItem>[];
    final targetActIndex = anchorInfo['actIndex'] as int;
    final targetChapterIndex = anchorInfo['chapterIndex'] as int;
    final targetAct = anchorInfo['act'] as novel_models.Act;
    final targetChapter = anchorInfo['chapter'] as novel_models.Chapter;
    
    // 🚀 关键修复：如果锚点章节是Act的第一章，需要包含Act标题
    if (targetChapterIndex == 0) {
      anchorItems.add(EditorItem(
        type: EditorItemType.actHeader,
        id: 'act_header_${targetAct.id}',
        act: targetAct,
        actIndex: targetActIndex + 1,
      ));
    }
    
    // 锚点章节标题 - 总是添加，确保anchorItems不为空
    anchorItems.add(_buildChapterItem(targetAct, targetChapter, targetActIndex, targetChapterIndex));
    
    // 🚀 关键修复：center key必须直接设置在sliver上，且这个sliver必须存在
    // anchorItems至少包含章节标题，所以这个sliver总是存在的
    slivers.add(
      SliverList(
        key: anchorKey, // center key设置在sliver上，不是内部widget
        delegate: SliverChildBuilderDelegate(
          (context, index) => itemBuilder(anchorItems[index]),
          childCount: anchorItems.length,
        ),
      ),
    );

    // 3. 锚点章节的场景
    final anchorChapterScenes = _buildChapterScenes(
      targetAct,
      targetChapter,
      targetActIndex,
      targetChapterIndex,
    );

    if (anchorChapterScenes.isNotEmpty) {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => itemBuilder(anchorChapterScenes[index]),
            childCount: anchorChapterScenes.length,
          ),
        ),
      );
    }

    // 4. 构建锚点章节之后的内容
    final afterItems = _buildItemsAfter(anchorInfo);
    if (afterItems.isNotEmpty) {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => itemBuilder(afterItems[index]),
            childCount: afterItems.length,
          ),
        ),
      );
    }

    AppLogger.i('CenterAnchorListBuilder', 
        '构建完成: ${beforeItems.length}个前置项 + 1个锚点 + ${anchorChapterScenes.length}个场景 + ${afterItems.length}个后续项');
    
    // 🚀 关键调试：验证center key的存在
    final centerKey = ValueKey('center_anchor_$anchorChapterId');
    final hasMatchingSliver = slivers.any((sliver) => sliver.key == centerKey);
    AppLogger.i('CenterAnchorListBuilder', 
        'Center key验证 - key:$centerKey, 找到匹配sliver:$hasMatchingSliver, 总sliver数:${slivers.length}');

    return slivers;
  }

  /// 获取center anchor key
  Key? getCenterAnchorKey() {
    // 🚀 关键修复：只有在普通模式且有锚点章节且锚点有效时才返回center key
    if (!isImmersiveMode && anchorChapterId != null && _isAnchorValid) {
      final key = ValueKey('center_anchor_$anchorChapterId');
      AppLogger.i('CenterAnchorListBuilder', '返回center anchor key: $key');
      return key;
    }
    // 沉浸模式或无锚点或锚点无效时返回null，不使用center anchor
    AppLogger.i('CenterAnchorListBuilder', '不使用center anchor - 沉浸模式:$isImmersiveMode, 锚点:$anchorChapterId, 有效:$_isAnchorValid');
    return null;
  }
  
  /// 🚀 新增：使锚点失效
  void _invalidateAnchor() {
    _isAnchorValid = false;
    AppLogger.w('CenterAnchorListBuilder', '锚点已失效，将不使用center anchor');
  }

  /// 查找锚点章节信息
  Map<String, dynamic>? _findAnchorChapterInfo() {
    for (int actIndex = 0; actIndex < novel.acts.length; actIndex++) {
      final act = novel.acts[actIndex];
      for (int chapterIndex = 0; chapterIndex < act.chapters.length; chapterIndex++) {
        final chapter = act.chapters[chapterIndex];
        if (chapter.id == anchorChapterId) {
          return {
            'act': act,
            'chapter': chapter,
            'actIndex': actIndex,
            'chapterIndex': chapterIndex,
          };
        }
      }
    }
    return null;
  }

  /// 构建锚点章节之前的所有内容
  List<EditorItem> _buildItemsBefore(Map<String, dynamic> anchorInfo) {
    final items = <EditorItem>[];
    final targetActIndex = anchorInfo['actIndex'] as int;
    final targetChapterIndex = anchorInfo['chapterIndex'] as int;

    // 构建目标Act之前的所有Acts
    for (int actIndex = 0; actIndex < targetActIndex; actIndex++) {
      final act = novel.acts[actIndex];
      final actItems = _buildCompleteActItems(act, actIndex);
      items.addAll(actItems);
    }

    // 构建目标Act中目标Chapter之前的内容
    if (targetChapterIndex > 0) {
      final targetAct = anchorInfo['act'] as novel_models.Act;
      
      // Act标题
      items.add(EditorItem(
        type: EditorItemType.actHeader,
        id: 'act_header_${targetAct.id}',
        act: targetAct,
        actIndex: targetActIndex + 1,
      ));

      // 目标章节之前的章节
      for (int chapterIndex = 0; chapterIndex < targetChapterIndex; chapterIndex++) {
        final chapter = targetAct.chapters[chapterIndex];
        final chapterItems = _buildCompleteChapterItems(targetAct, chapter, targetActIndex, chapterIndex);
        items.addAll(chapterItems);
      }
    }

    return items;
  }

  /// 构建锚点章节之后的所有内容
  List<EditorItem> _buildItemsAfter(Map<String, dynamic> anchorInfo) {
    final items = <EditorItem>[];
    final targetActIndex = anchorInfo['actIndex'] as int;
    final targetChapterIndex = anchorInfo['chapterIndex'] as int;
    final targetAct = anchorInfo['act'] as novel_models.Act;

    // 构建目标Act中目标Chapter之后的章节
    for (int chapterIndex = targetChapterIndex + 1; chapterIndex < targetAct.chapters.length; chapterIndex++) {
      final chapter = targetAct.chapters[chapterIndex];
      final chapterItems = _buildCompleteChapterItems(targetAct, chapter, targetActIndex, chapterIndex);
      items.addAll(chapterItems);
    }

    // 🚀 修改：无论锚点是否是最后一章，始终在当前卷末尾提供“添加章节”按钮
    items.add(EditorItem(
      type: EditorItemType.addChapterButton,
      id: 'add_chapter_after_${anchorChapterId}',
      act: targetAct,
      actIndex: targetActIndex + 1,
      isLastInAct: true,
      isLastInNovel: targetActIndex == novel.acts.length - 1,
    ));

    // 构建目标Act之后的所有Acts
    for (int actIndex = targetActIndex + 1; actIndex < novel.acts.length; actIndex++) {
      final act = novel.acts[actIndex];
      final actItems = _buildCompleteActItems(act, actIndex);
      items.addAll(actItems);
    }

    // 如果是最后一个Act，添加"添加Act"按钮
    if (targetActIndex == novel.acts.length - 1) {
      items.add(EditorItem(
        type: EditorItemType.addActButton,
        id: 'add_act_after_${targetAct.id}',
        act: targetAct,
        actIndex: targetActIndex + 1,
        isLastInAct: true,
        isLastInNovel: true,
      ));
    }

    return items;
  }

  /// 构建章节标题项
  EditorItem _buildChapterItem(novel_models.Act act, novel_models.Chapter chapter, int actIndex, int chapterIndex) {
    return EditorItem(
      type: EditorItemType.chapterHeader,
      id: 'chapter_header_${chapter.id}',
      act: act,
      chapter: chapter,
      actIndex: actIndex + 1,
      chapterIndex: chapterIndex + 1,
    );
  }

  /// 构建章节的所有场景和按钮
  List<EditorItem> _buildChapterScenes(novel_models.Act act, novel_models.Chapter chapter, int actIndex, int chapterIndex) {
    final items = <EditorItem>[];

    if (chapter.scenes.isEmpty) {
      // 空章节：添加剧情推演按钮和"添加场景"按钮
      items.add(EditorItem(
        type: EditorItemType.storyPredictionButton,
        id: 'story_prediction_${chapter.id}',
        act: act,
        chapter: chapter,
        actIndex: actIndex + 1,
        chapterIndex: chapterIndex + 1,
        isLastInChapter: true,
        isLastInAct: chapterIndex == act.chapters.length - 1,
        isLastInNovel: actIndex == novel.acts.length - 1 && chapterIndex == act.chapters.length - 1,
      ));
      
      items.add(EditorItem(
        type: EditorItemType.addSceneButton,
        id: 'add_scene_${chapter.id}',
        act: act,
        chapter: chapter,
        actIndex: actIndex + 1,
        chapterIndex: chapterIndex + 1,
        isLastInChapter: true,
        isLastInAct: chapterIndex == act.chapters.length - 1,
        isLastInNovel: actIndex == novel.acts.length - 1 && chapterIndex == act.chapters.length - 1,
      ));
    } else {
      // 有场景：构建所有场景
      for (int sceneIndex = 0; sceneIndex < chapter.scenes.length; sceneIndex++) {
        final scene = chapter.scenes[sceneIndex];
        final isLastScene = sceneIndex == chapter.scenes.length - 1;
        
        items.add(EditorItem(
          type: EditorItemType.scene,
          id: 'scene_${scene.id}',
          act: act,
          chapter: chapter,
          scene: scene,
          actIndex: actIndex + 1,
          chapterIndex: chapterIndex + 1,
          sceneIndex: sceneIndex + 1,
          isLastInChapter: isLastScene,
          isLastInAct: chapterIndex == act.chapters.length - 1 && isLastScene,
          isLastInNovel: actIndex == novel.acts.length - 1 && chapterIndex == act.chapters.length - 1 && isLastScene,
        ));
        
        // 在最后一个场景后添加剧情推演按钮和"添加场景"按钮
        if (isLastScene) {
          // 添加剧情推演按钮
          items.add(EditorItem(
            type: EditorItemType.storyPredictionButton,
            id: 'story_prediction_${chapter.id}',
            act: act,
            chapter: chapter,
            actIndex: actIndex + 1,
            chapterIndex: chapterIndex + 1,
            isLastInChapter: true,
            isLastInAct: chapterIndex == act.chapters.length - 1,
            isLastInNovel: actIndex == novel.acts.length - 1 && chapterIndex == act.chapters.length - 1,
          ));
          
          // 添加"添加场景"按钮
          items.add(EditorItem(
            type: EditorItemType.addSceneButton,
            id: 'add_scene_after_${scene.id}',
            act: act,
            chapter: chapter,
            actIndex: actIndex + 1,
            chapterIndex: chapterIndex + 1,
            isLastInChapter: true,
            isLastInAct: chapterIndex == act.chapters.length - 1,
            isLastInNovel: actIndex == novel.acts.length - 1 && chapterIndex == act.chapters.length - 1,
          ));
        }
      }
    }

    return items;
  }

  /// 构建完整的Act项目（包括Act标题、所有章节、按钮）
  List<EditorItem> _buildCompleteActItems(novel_models.Act act, int actIndex) {
    final items = <EditorItem>[];
    final isLastAct = actIndex == novel.acts.length - 1;
    
    // Act标题
    items.add(EditorItem(
      type: EditorItemType.actHeader,
      id: 'act_header_${act.id}',
      act: act,
      actIndex: actIndex + 1,
    ));
    
    // 章节
    if (act.chapters.isEmpty) {
      items.add(EditorItem(
        type: EditorItemType.addChapterButton,
        id: 'add_chapter_${act.id}',
        act: act,
        actIndex: actIndex + 1,
        isLastInAct: true,
        isLastInNovel: isLastAct,
      ));
    } else {
      for (int chapterIndex = 0; chapterIndex < act.chapters.length; chapterIndex++) {
        final chapter = act.chapters[chapterIndex];
        final chapterItems = _buildCompleteChapterItems(act, chapter, actIndex, chapterIndex);
        items.addAll(chapterItems);
      }
      
      // 最后一章后的"添加章节"按钮
      items.add(EditorItem(
        type: EditorItemType.addChapterButton,
        id: 'add_chapter_after_${act.chapters.last.id}',
        act: act,
        actIndex: actIndex + 1,
        isLastInAct: true,
        isLastInNovel: isLastAct,
      ));
    }
    
    return items;
  }

  /// 构建完整的Chapter项目（包括章节标题、所有场景、按钮）
  List<EditorItem> _buildCompleteChapterItems(novel_models.Act act, novel_models.Chapter chapter, int actIndex, int chapterIndex) {
    final items = <EditorItem>[];
    
    // 章节标题
    items.add(_buildChapterItem(act, chapter, actIndex, chapterIndex));
    
    // 章节场景
    final sceneItems = _buildChapterScenes(act, chapter, actIndex, chapterIndex);
    items.addAll(sceneItems);
    
    return items;
  }

  /// 构建沉浸模式的sliver
  List<Widget> _buildImmersiveModeSliver(Widget Function(EditorItem) itemBuilder) {
    AppLogger.i('CenterAnchorListBuilder', '沉浸模式：构建单章内容 - $immersiveChapterId');
    
    // 查找目标章节
    novel_models.Chapter? targetChapter;
    novel_models.Act? parentAct;
    int actIndex = -1;
    int chapterIndex = -1;
    
    outerLoop: for (int aIndex = 0; aIndex < novel.acts.length; aIndex++) {
      final act = novel.acts[aIndex];
      for (int cIndex = 0; cIndex < act.chapters.length; cIndex++) {
        final chapter = act.chapters[cIndex];
        if (chapter.id == immersiveChapterId) {
          targetChapter = chapter;
          parentAct = act;
          actIndex = aIndex;
          chapterIndex = cIndex;
          break outerLoop;
        }
      }
    }
    
    if (targetChapter == null || parentAct == null) {
      AppLogger.w('CenterAnchorListBuilder', '沉浸模式：未找到目标章节 $immersiveChapterId');
      return [];
    }
    
    // 构建单章内容项目
    final items = _buildCompleteChapterItems(parentAct, targetChapter, actIndex, chapterIndex);
    
    // 🚀 新增：在沉浸模式下也提供“添加章节”按钮（出现在当前卷内容之后）
    items.add(EditorItem(
      type: EditorItemType.addChapterButton,
      id: 'add_chapter_after_${targetChapter.id}',
      act: parentAct,
      actIndex: actIndex + 1,
    ));
    
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => itemBuilder(items[index]),
          childCount: items.length,
        ),
      ),
    ];
  }

  /// 构建传统模式的slivers
  List<Widget> _buildTraditionalSlivers(Widget Function(EditorItem) itemBuilder) {
    AppLogger.i('CenterAnchorListBuilder', '传统模式：从头构建完整内容');
    
    final items = <EditorItem>[];
    
    for (int actIndex = 0; actIndex < novel.acts.length; actIndex++) {
      final act = novel.acts[actIndex];
      final actItems = _buildCompleteActItems(act, actIndex);
      items.addAll(actItems);
    }
    
    // 最后添加"添加Act"按钮
    if (novel.acts.isNotEmpty) {
      final lastAct = novel.acts.last;
      items.add(EditorItem(
        type: EditorItemType.addActButton,
        id: 'add_act_after_${lastAct.id}',
        act: lastAct,
        actIndex: novel.acts.length,
        isLastInAct: true,
        isLastInNovel: true,
      ));
    }
    
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => itemBuilder(items[index]),
          childCount: items.length,
        ),
      ),
    ];
  }
}