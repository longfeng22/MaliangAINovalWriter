import 'package:ainoval/models/novel_setting_item.dart';

abstract class NovelAIRepository {
  Future<List<NovelSettingItem>> generateNovelSettings({
    required String novelId,
    required String startChapterId,
    String? endChapterId,
    required List<String> settingTypes,
    required int maxSettingsPerType,
    required String additionalInstructions,
    required String modelConfigId, // 模型配置ID，后端自己查询已有设定
  });
} 