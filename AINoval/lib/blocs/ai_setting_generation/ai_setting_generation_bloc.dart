import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:ainoval/models/novel_structure.dart'; // Changed from novel_chapter.dart
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart'; // Changed from novel_chapter_repository.dart
import 'package:ainoval/services/api_service/repositories/novel_ai_repository.dart'; // New repository for AI features
import 'package:ainoval/utils/logger.dart';

part 'ai_setting_generation_event.dart';
part 'ai_setting_generation_state.dart';

class AISettingGenerationBloc extends Bloc<AISettingGenerationEvent, AISettingGenerationState> {
  final EditorRepository _editorRepository; // Changed
  final NovelAIRepository _novelAIRepository; 

  List<Chapter> _loadedChapters = []; // Changed from NovelChapter

  AISettingGenerationBloc({
    required EditorRepository editorRepository, // Changed
    required NovelAIRepository novelAIRepository,
  })  : _editorRepository = editorRepository, // Changed
        _novelAIRepository = novelAIRepository,
        super(AISettingGenerationInitial()) {
    on<LoadInitialDataForAISettingPanel>(_onLoadInitialData);
    on<GenerateSettingsRequested>(_onGenerateSettingsRequested);
    // on<AdoptGeneratedSetting>(_onAdoptGeneratedSetting); // For later
  }

  Future<void> _onLoadInitialData(
    LoadInitialDataForAISettingPanel event,
    Emitter<AISettingGenerationState> emit,
  ) async {
    emit(AISettingGenerationLoadingChapters());
    try {
      final novel = await _editorRepository.getNovelWithAllScenes(event.novelId); // Use existing method that loads all structure
      if (novel != null) {
        _loadedChapters = novel.acts.expand((act) => act.chapters).toList();
        // Sort chapters by their order, assuming Act and Chapter orders are set
        _loadedChapters.sort((a, b) {
          // Find act orders first
          final actA = novel.acts.firstWhere((act) => act.chapters.contains(a));
          final actB = novel.acts.firstWhere((act) => act.chapters.contains(b));
          if (actA.order != actB.order) {
            return actA.order.compareTo(actB.order);
          }
          return a.order.compareTo(b.order);
        });
        emit(AISettingGenerationDataLoaded(chapters: _loadedChapters, novel: novel));
      } else {
        AppLogger.e('AISettingGenerationBloc', 'Novel not found: ${event.novelId}');
        emit(AISettingGenerationFailure(error: '小说未找到', chapters: [], novel: null));
      }
    } catch (e, stackTrace) {
      AppLogger.e('AISettingGenerationBloc', 'Error loading chapters for AI Panel', e, stackTrace);
      emit(AISettingGenerationFailure(error: '加载章节列表失败: ${e.toString()}', chapters: [], novel: null));
    }
  }

  Future<void> _onGenerateSettingsRequested(
    GenerateSettingsRequested event,
    Emitter<AISettingGenerationState> emit,
  ) async {
    final currentChapters = _loadedChapters;

    emit(AISettingGenerationInProgress());
    try {
      final settings = await _novelAIRepository.generateNovelSettings(
        novelId: event.novelId,
        startChapterId: event.startChapterId,
        endChapterId: event.endChapterId,
        settingTypes: event.settingTypes,
        maxSettingsPerType: event.maxSettingsPerType,
        additionalInstructions: event.additionalInstructions,
        modelConfigId: event.modelConfigId, // 后端会自己查询已有设定
      );
      // 保持当前的Novel引用
      final currentNovel = (state is AISettingGenerationDataLoaded) ? (state as AISettingGenerationDataLoaded).novel : null;
      emit(AISettingGenerationSuccess(generatedSettings: settings, chapters: currentChapters, novel: currentNovel));
    } catch (e, stackTrace) {
      AppLogger.e('AISettingGenerationBloc', 'Error generating settings', e, stackTrace);
              final currentNovel = (state is AISettingGenerationDataLoaded) ? (state as AISettingGenerationDataLoaded).novel : null;
        emit(AISettingGenerationFailure(error: '生成设定失败: ${e.toString()}', chapters: currentChapters, novel: currentNovel));
    }
  }

  // Future<void> _onAdoptGeneratedSetting(
  //   AdoptGeneratedSetting event,
  //   Emitter<AISettingGenerationState> emit,
  // ) async {
  //   // This will interact with SettingBloc or its repository
  //   // For now, just log. Will require careful state management
  //   AppLogger.i('AISettingGenerationBloc', 'Adopting setting: ${event.settingItem.name} to group ${event.targetGroupId}');
  //   // Potentially re-emit current success state or a new state indicating adoption is in progress/done
  //   if (state is AISettingGenerationSuccess) {
  //     emit(AISettingGenerationSuccess(
  //       generatedSettings: (state as AISettingGenerationSuccess).generatedSettings.where((s) => s.id != event.settingItem.id).toList(), // Example: remove adopted item
  //       chapters: _loadedChapters,
  //     ));
  //   }
  // }
} 