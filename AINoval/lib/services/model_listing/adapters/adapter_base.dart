import 'package:ainoval/models/model_info.dart';
import 'package:dio/dio.dart';

abstract class ModelListingAdapterBase {
  Future<List<ModelInfo>> listModels({
    required Dio dio,
    required String provider,
    String? apiKey,
    String? apiEndpoint,
  });
}



