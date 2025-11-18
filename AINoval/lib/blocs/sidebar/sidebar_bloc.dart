import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:ainoval/models/novel_structure.dart'; // Novel 模型
import 'package:ainoval/services/api_service/repositories/editor_repository.dart'; // 引入 Repository
import 'package:ainoval/utils/logger.dart';

part 'sidebar_event.dart';
part 'sidebar_state.dart';

class SidebarBloc extends Bloc<SidebarEvent, SidebarState> {
  final EditorRepository _editorRepository; // 依赖注入 EditorRepository

  SidebarBloc({required EditorRepository editorRepository})
      : _editorRepository = editorRepository,
        super(SidebarInitial()) {
    on<LoadNovelStructure>(_onLoadNovelStructure);
    on<ApplyIncrementalStructureUpdate>(_onApplyIncrementalStructureUpdate);
  }

  Future<void> _onLoadNovelStructure(
      LoadNovelStructure event, Emitter<SidebarState> emit) async {
    emit(SidebarLoading());
    try {
      AppLogger.i('SidebarBloc', '开始加载小说结构和场景摘要: ${event.novelId}');
      
      // 使用专门的API获取包含场景摘要的小说结构
      final novelWithSummaries = await _editorRepository.getNovelWithSceneSummaries(event.novelId, readOnly: true);
      
      if (novelWithSummaries != null) {
        AppLogger.i('SidebarBloc', '成功加载小说结构和场景摘要');
        
        // 记录每个章节的摘要信息，用于调试
        int chaptersWithScene = 0;
        int totalScenes = 0;
        for (final act in novelWithSummaries.acts) {
          for (final chapter in act.chapters) {
            if (chapter.scenes.isNotEmpty) {
              chaptersWithScene++;
              totalScenes += chapter.scenes.length;
            }
          }
        }
        
        AppLogger.i('SidebarBloc', '小说结构信息: 共${novelWithSummaries.acts.length}卷, '
            '${chaptersWithScene}章含有场景, 总计${totalScenes}个场景');
            
        emit(SidebarLoaded(novelStructure: novelWithSummaries));
      } else {
        AppLogger.e('SidebarBloc', '加载小说结构和场景摘要失败: 返回null');
        emit(const SidebarError(message: '无法加载小说结构'));
      }
    } catch (e) {
      AppLogger.e('SidebarBloc', '加载小说结构和场景摘要失败', e);
      emit(SidebarError(message: '加载小说结构失败: ${e.toString()}'));
    }
  }

  // 增量应用：本地合并新增章节/场景，避免全量再拉
  Future<void> _onApplyIncrementalStructureUpdate(
      ApplyIncrementalStructureUpdate event, Emitter<SidebarState> emit) async {
    final current = state;
    if (current is! SidebarLoaded) return;
    try {
      final novel = current.novelStructure;
      if (event.chapterId != null && event.sceneId == null) {
        // 仅新增章节：在指定act下添加一个空章节占位
        final acts = novel.acts.map((act) {
          if (act.id == event.actId) {
            final newChapter = Chapter(
              id: event.chapterId!,
              title: event.chapterTitle ?? '新章节',
              order: act.chapters.length + 1,
              scenes: const [],
              sceneIds: const [],
            );
            return act.copyWith(chapters: [...act.chapters, newChapter]);
          }
          return act;
        }).toList();
        emit(SidebarLoaded(novelStructure: novel.copyWith(acts: acts)));
        return;
      }

      if (event.chapterId != null && event.sceneId != null) {
        // 新增场景：向已有章节的sceneIds追加或创建空场景占位
        final acts = novel.acts.map((act) {
          final chapters = act.chapters.map((chapter) {
            if (chapter.id == event.chapterId) {
              final updatedIds = [...chapter.sceneIds, event.sceneId!];
              return chapter.copyWith(sceneIds: updatedIds);
            }
            return chapter;
          }).toList();
          return act.copyWith(chapters: chapters);
        }).toList();
        emit(SidebarLoaded(novelStructure: novel.copyWith(acts: acts)));
      }
    } catch (e) {
      AppLogger.e('SidebarBloc', '增量应用结构更新失败', e);
    }
  }
} 