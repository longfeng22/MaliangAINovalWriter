import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/api_service/repositories/novel_ai_repository.dart';
import 'package:ainoval/utils/logger.dart';

class NovelAIRepositoryImpl implements NovelAIRepository {
  final ApiClient apiClient;

  NovelAIRepositoryImpl({required this.apiClient});

  @override
  Future<List<NovelSettingItem>> generateNovelSettings({
    required String novelId,
    required String startChapterId,
    String? endChapterId,
    required List<String> settingTypes,
    required int maxSettingsPerType,
    required String additionalInstructions,
    required String modelConfigId,
  }) async {
    AppLogger.i('NovelAIRepoImpl', 'Generating settings for novel $novelId with modelConfigId $modelConfigId');
    try {
      // 后端会自己查询novelId对应的已有设定，前端不需要传递
      final response = await apiClient.post(
        // Make sure the path matches your backend routing exactly
        '/novels/$novelId/ai/generate-settings', 
        data: {
          'startChapterId': startChapterId,
          if (endChapterId != null && endChapterId.isNotEmpty) 'endChapterId': endChapterId,
          'settingTypes': settingTypes,
          'maxSettingsPerType': maxSettingsPerType,
          'additionalInstructions': additionalInstructions,
          'modelConfigId': modelConfigId, // 模型配置ID
        },
      );

      if (response is List) {
        final items = response
            .map((json) => NovelSettingItem.fromJson(json as Map<String, dynamic>))
            .toList();
        AppLogger.i('NovelAIRepoImpl', 'Successfully generated ${items.length} setting items.');
        return items;
      } else if (response is Map<String, dynamic> && response.containsKey('error')) {
        // Handle structured error from backend if any
        AppLogger.e('NovelAIRepoImpl', 'Error from backend: ${response['message']}');
        throw Exception('Failed to generate settings: ${response['message']}');
      } else {
        AppLogger.e('NovelAIRepoImpl', 'Unexpected response format for generateNovelSettings: $response');
        throw Exception('Failed to parse generated settings: Unexpected response format');
      }
    } catch (e, stackTrace) {
      AppLogger.e('NovelAIRepoImpl', 'Failed to generate novel settings via API', e, stackTrace);
      // Rethrow a more specific error or a generic one
      throw Exception('API call failed for generating settings: ${e.toString()}');
    }
  }
} 