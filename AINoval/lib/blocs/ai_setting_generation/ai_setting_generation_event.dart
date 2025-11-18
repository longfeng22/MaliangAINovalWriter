part of 'ai_setting_generation_bloc.dart';

abstract class AISettingGenerationEvent extends Equatable {
  const AISettingGenerationEvent();

  @override
  List<Object?> get props => [];
}

class LoadInitialDataForAISettingPanel extends AISettingGenerationEvent {
  final String novelId;
  const LoadInitialDataForAISettingPanel(this.novelId);

  @override
  List<Object> get props => [novelId];
}

class GenerateSettingsRequested extends AISettingGenerationEvent {
  final String novelId;
  final String startChapterId;
  final String? endChapterId;
  final List<String> settingTypes; // Values from SettingType enum
  final int maxSettingsPerType;
  final String additionalInstructions;
  final String modelConfigId; // 模型配置ID

  const GenerateSettingsRequested({
    required this.novelId,
    required this.startChapterId,
    this.endChapterId,
    required this.settingTypes,
    required this.maxSettingsPerType,
    required this.additionalInstructions,
    required this.modelConfigId,
  });

  @override
  List<Object?> get props => [
        novelId,
        startChapterId,
        endChapterId,
        settingTypes,
        maxSettingsPerType,
        additionalInstructions,
        modelConfigId,
      ];
}

// Event for when user wants to adopt a setting (to be implemented fully later)
class AdoptGeneratedSetting extends AISettingGenerationEvent {
  final NovelSettingItem settingItem;
  final String targetGroupId; // ID of the SettingGroup to add to
  final String novelId;

  const AdoptGeneratedSetting({
    required this.settingItem,
    required this.targetGroupId,
    required this.novelId,
  });

  @override
  List<Object> get props => [settingItem, targetGroupId, novelId];
} 