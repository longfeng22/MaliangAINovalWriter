import '../../../../models/admin/admin_models.dart';
import '../../../../models/admin/llm_observability_models.dart' show PagedResponse;
import '../../../../models/admin/admin_auth_models.dart';
import '../../../../models/public_model_config.dart';
import '../../../../models/preset_models.dart';
import '../../../../models/prompt_models.dart';
import '../../../../models/model_pricing.dart';
import '../../base/api_client.dart';
import '../../base/api_exception.dart';
import '../../../../utils/logger.dart';
import 'package:dio/dio.dart' show Options;

class AdminRepositoryImpl {
  final ApiClient _apiClient;
  final String _tag = 'AdminRepository';

  AdminRepositoryImpl({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// 管理员登录
  Future<AdminAuthResponse> adminLogin(String username, String password) async {
    try {
      AppLogger.d(_tag, '管理员登录请求: username=$username');
      
      final request = AdminAuthRequest(username: username, password: password);
      final response = await _apiClient.post('/admin/auth/login', data: request.toJson());
      
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminAuthResponse.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminAuthResponse.fromJson(response);
      } else {
        throw ApiException(-1, '登录响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '管理员登录失败', e);
      rethrow;
    }
  }

  Future<AdminDashboardStats> getDashboardStats() async {
    try {
      AppLogger.d(_tag, '获取管理员仪表板统计数据');
      // 仪表盘数据查询较为复杂，需要更长的超时时间
      final response = await _apiClient.get(
        '/admin/dashboard/stats',
        options: Options(
          receiveTimeout: const Duration(minutes: 2), // 设置2分钟超时
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminDashboardStats.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminDashboardStats.fromJson(response);
      } else {
        throw ApiException(-1, '仪表板统计数据格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '获取管理员仪表板统计数据失败', e);
      rethrow;
    }
  }

  Future<List<AdminUser>> getUsers({
    int page = 0,
    int size = 20,
    String? search,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取用户列表: page=$page, size=$size, search=$search');
      
      String path = '/admin/users?page=$page&size=$size';
      if (search != null && search.isNotEmpty) {
        path += '&search=${Uri.encodeComponent(search)}';
      }
      
      final response = await _apiClient.get(path);
      
      // 添加详细的响应调试日志
      AppLogger.d(_tag, '📡 原始响应类型: ${response.runtimeType}');
      AppLogger.d(_tag, '📡 原始响应内容: $response');
      
      // 改进响应数据解析逻辑
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        AppLogger.d(_tag, '📄 响应是Map，包含的键: ${response.keys.toList()}');
        if (response.containsKey('data')) {
          rawData = response['data'];
          AppLogger.d(_tag, '📄 data字段类型: ${rawData.runtimeType}');
          AppLogger.d(_tag, '📄 data字段内容: $rawData');
        } else if (response.containsKey('success') && response['success'] == true) {
          // 处理 ApiResponse 结构
          rawData = response['data'] ?? response;
          AppLogger.d(_tag, '📄 success结构，提取的数据类型: ${rawData.runtimeType}');
        } else {
          rawData = response;
          AppLogger.d(_tag, '📄 直接使用整个response');
        }
      } else {
        rawData = response;
        AppLogger.d(_tag, '📄 响应不是Map，直接使用');
      }
      
      // 检查数据类型并转换为List
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
        AppLogger.d(_tag, '✅ 成功获得List，长度: ${data.length}');
      } else if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '📄 rawData是Map，包含的键: ${rawData.keys.toList()}');
        // 如果是Map，可能包含列表数据或者是单个对象
        if (rawData.containsKey('content')) {
          // 处理分页响应
          data = (rawData['content'] as List?) ?? [];
          AppLogger.d(_tag, '✅ 从content字段获得List，长度: ${data.length}');
        } else {
          AppLogger.e(_tag, '❌ Map中没有找到content字段，无法提取List数据');
          throw ApiException(-1, '用户列表数据格式错误: 期望List但收到Map，无content字段');
        }
      } else {
        AppLogger.e(_tag, '❌ 无法识别的数据类型: ${rawData.runtimeType}');
        throw ApiException(-1, '用户列表数据格式错误: 未知的数据类型 ${rawData.runtimeType}');
      }
      
      AppLogger.d(_tag, '✅ 获取用户列表成功: count=${data.length}');
      return data.map((json) => AdminUser.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取用户列表失败', e);
      rethrow;
    }
  }

  // 新增：分页+筛选+排序获取用户列表
  Future<PagedResponse<AdminUser>> getUsersPaged({
    int page = 0,
    int size = 20,
    String? keyword,
    String? status,
    int? minCredits,
    DateTime? createdStart,
    DateTime? createdEnd,
    DateTime? lastLoginStart,
    DateTime? lastLoginEnd,
    String sortBy = 'createdAt',
    String sortDir = 'desc',
  }) async {
    try {
      AppLogger.d(_tag, '🔍 分页获取用户: page=$page, size=$size, keyword=$keyword, status=$status, sort=$sortBy $sortDir');

      final params = <String, dynamic>{
        'page': page,
        'size': size,
        'sortBy': sortBy,
        'sortDir': sortDir,
      };
      if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (minCredits != null) params['minCredits'] = minCredits;
      if (createdStart != null) params['createdStart'] = createdStart.toIso8601String();
      if (createdEnd != null) params['createdEnd'] = createdEnd.toIso8601String();
      if (lastLoginStart != null) params['lastLoginStart'] = lastLoginStart.toIso8601String();
      if (lastLoginEnd != null) params['lastLoginEnd'] = lastLoginEnd.toIso8601String();

      final response = await _apiClient.getWithParams('/admin/users/page', queryParameters: params);

      dynamic raw;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        raw = response['data'];
      } else {
        raw = response;
      }

      if (raw is Map<String, dynamic>) {
        final paged = PagedResponse.fromJson(raw, (json) => AdminUser.fromJson(json as Map<String, dynamic>));
        AppLogger.d(_tag, '✅ 分页获取用户成功: page=${paged.page}, size=${paged.size}, total=${paged.totalElements}');
        return paged;
      }

      throw ApiException(-1, '用户分页数据格式错误');
    } catch (e) {
      AppLogger.e(_tag, '❌ 分页获取用户失败', e);
      rethrow;
    }
  }

  Future<List<AdminRole>> getRoles() async {
    try {
      AppLogger.d(_tag, '🔍 获取角色列表');
      final response = await _apiClient.get('/admin/roles');
      
      // 添加详细的响应调试日志
      AppLogger.d(_tag, '📡 角色列表原始响应类型: ${response.runtimeType}');
      AppLogger.d(_tag, '📡 角色列表原始响应内容: $response');
      
      // 改进响应数据解析逻辑
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        AppLogger.d(_tag, '📄 角色响应是Map，包含的键: ${response.keys.toList()}');
        if (response.containsKey('data')) {
          rawData = response['data'];
          AppLogger.d(_tag, '📄 角色data字段类型: ${rawData.runtimeType}');
          AppLogger.d(_tag, '📄 角色data字段内容: $rawData');
        } else if (response.containsKey('success') && response['success'] == true) {
          // 处理 ApiResponse 结构
          rawData = response['data'] ?? response;
          AppLogger.d(_tag, '📄 角色success结构，提取的数据类型: ${rawData.runtimeType}');
        } else {
          rawData = response;
          AppLogger.d(_tag, '📄 角色直接使用整个response');
        }
      } else {
        rawData = response;
        AppLogger.d(_tag, '📄 角色响应不是Map，直接使用');
      }
      
      // 检查数据类型并转换为List
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
        AppLogger.d(_tag, '✅ 角色成功获得List，长度: ${data.length}');
      } else if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '📄 角色rawData是Map，包含的键: ${rawData.keys.toList()}');
        // 如果是Map，可能包含列表数据或者是单个对象
        if (rawData.containsKey('content')) {
          // 处理分页响应
          data = (rawData['content'] as List?) ?? [];
          AppLogger.d(_tag, '✅ 角色从content字段获得List，长度: ${data.length}');
        } else {
          AppLogger.e(_tag, '❌ 角色Map中没有找到content字段，无法提取List数据');
          throw ApiException(-1, '角色列表数据格式错误: 期望List但收到Map，无content字段');
        }
      } else {
        AppLogger.e(_tag, '❌ 角色无法识别的数据类型: ${rawData.runtimeType}');
        throw ApiException(-1, '角色列表数据格式错误: 未知的数据类型 ${rawData.runtimeType}');
      }
      
      AppLogger.d(_tag, '✅ 获取角色列表成功: count=${data.length}');
      return data.map((json) => AdminRole.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取角色列表失败', e);
      rethrow;
    }
  }

  Future<List<AdminModelConfig>> getModelConfigs() async {
    try {
      AppLogger.d(_tag, '🔍 获取模型配置列表');
      final response = await _apiClient.get('/admin/model-configs');
      
      // 改进响应数据解析逻辑
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          // 处理 ApiResponse 结构
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      // 检查数据类型并转换为List
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
      } else if (rawData is Map<String, dynamic>) {
        // 如果是Map，可能包含列表数据或者是单个对象
        if (rawData.containsKey('content')) {
          // 处理分页响应
          data = (rawData['content'] as List?) ?? [];
        } else {
          throw ApiException(-1, '模型配置列表数据格式错误: 期望List但收到Map');
        }
      } else {
        throw ApiException(-1, '模型配置列表数据格式错误: 未知的数据类型');
      }
      
      AppLogger.d(_tag, '✅ 获取模型配置列表成功: count=${data.length}');
      return data.map((json) => AdminModelConfig.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取模型配置列表失败', e);
      rethrow;
    }
  }

  Future<List<AdminSystemConfig>> getSystemConfigs() async {
    try {
      AppLogger.d(_tag, '🔍 获取系统配置列表');
      final response = await _apiClient.get('/admin/system-configs');
      
      // 改进响应数据解析逻辑
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          // 处理 ApiResponse 结构
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      // 检查数据类型并转换为List
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
      } else if (rawData is Map<String, dynamic>) {
        // 如果是Map，可能包含列表数据或者是单个对象
        if (rawData.containsKey('content')) {
          // 处理分页响应
          data = (rawData['content'] as List?) ?? [];
        } else {
          throw ApiException(-1, '系统配置列表数据格式错误: 期望List但收到Map');
        }
      } else {
        throw ApiException(-1, '系统配置列表数据格式错误: 未知的数据类型');
      }
      
      AppLogger.d(_tag, '✅ 获取系统配置列表成功: count=${data.length}');
      return data.map((json) => AdminSystemConfig.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取系统配置列表失败', e);
      rethrow;
    }
  }

  Future<void> updateUserStatus(String userId, String status) async {
    try {
      AppLogger.d(_tag, '更新用户状态: userId=$userId, status=$status');
      await _apiClient.patch('/admin/users/$userId/status', data: {'status': status});
    } catch (e) {
      AppLogger.e(_tag, '更新用户状态失败', e);
      rethrow;
    }
  }

  Future<AdminRole> createRole(AdminRole role) async {
    try {
      AppLogger.d(_tag, '创建角色: ${role.roleName}');
      final response = await _apiClient.post('/admin/roles', data: role.toJson());
      
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminRole.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminRole.fromJson(response);
      } else {
        throw ApiException(-1, '创建角色响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '创建角色失败', e);
      rethrow;
    }
  }

  Future<AdminRole> updateRole(String roleId, AdminRole role) async {
    try {
      AppLogger.d(_tag, '更新角色: roleId=$roleId');
      final response = await _apiClient.put('/admin/roles/$roleId', data: role.toJson());
      
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminRole.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminRole.fromJson(response);
      } else {
        throw ApiException(-1, '更新角色响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '更新角色失败', e);
      rethrow;
    }
  }

  Future<AdminModelConfig> updateModelConfig(
      String configId, AdminModelConfig config) async {
    try {
      AppLogger.d(_tag, '更新模型配置: configId=$configId');
      final response = await _apiClient.put('/admin/model-configs/$configId', data: config.toJson());
      
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminModelConfig.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminModelConfig.fromJson(response);
      } else {
        throw ApiException(-1, '更新模型配置响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '更新模型配置失败', e);
      rethrow;
    }
  }

  Future<void> updateSystemConfig(String configKey, String value) async {
    try {
      AppLogger.d(_tag, '更新系统配置: configKey=$configKey');
      await _apiClient.patch('/admin/system-configs/$configKey/value', data: {'value': value});
    } catch (e) {
      AppLogger.e(_tag, '更新系统配置失败', e);
      rethrow;
    }
  }

  Future<void> addCreditsToUser(String userId, int amount, String reason) async {
    try {
      AppLogger.d(_tag, '为用户添加积分: userId=$userId, amount=$amount');
      await _apiClient.post('/admin/users/$userId/credits', data: {
        'amount': amount,
        'reason': reason,
      });
    } catch (e) {
      AppLogger.e(_tag, '为用户添加积分失败', e);
      rethrow;
    }
  }

  Future<void> resetUserPassword(String userId, {String? newPassword, bool useDefault = false}) async {
    try {
      AppLogger.d(_tag, '重置用户密码: userId=$userId, useDefault=$useDefault');
      final Map<String, dynamic> body = {};
      if (newPassword != null && newPassword.trim().isNotEmpty) {
        body['newPassword'] = newPassword.trim();
      } else {
        body['useDefault'] = true;
      }
      await _apiClient.post('/admin/users/$userId/reset-password', data: body);
    } catch (e) {
      AppLogger.e(_tag, '重置用户密码失败', e);
      rethrow;
    }
  }

  Future<void> deductCreditsFromUser(String userId, int amount, String reason) async {
    try {
      AppLogger.d(_tag, '扣减用户积分: userId=$userId, amount=$amount');
      await _apiClient.delete('/admin/users/$userId/credits', data: {
        'amount': amount,
        'reason': reason,
      });
    } catch (e) {
      AppLogger.e(_tag, '扣减用户积分失败', e);
      rethrow;
    }
  }

  Future<AdminUser> updateUserInfo(String userId, {
    String? email,
    String? displayName,
    String? accountStatus,
  }) async {
    try {
      AppLogger.d(_tag, '更新用户信息: userId=$userId');
      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (displayName != null) data['displayName'] = displayName;
      if (accountStatus != null) data['accountStatus'] = accountStatus;
      
      final response = await _apiClient.put('/admin/users/$userId', data: data);
      
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        return AdminUser.fromJson(response['data']);
      } else if (response is Map<String, dynamic>) {
        return AdminUser.fromJson(response);
      } else {
        throw ApiException(-1, '更新用户信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '更新用户信息失败', e);
      rethrow;
    }
  }

  Future<void> assignRoleToUser(String userId, String roleId) async {
    try {
      AppLogger.d(_tag, '为用户分配角色: userId=$userId, roleId=$roleId');
      await _apiClient.post('/admin/users/$userId/roles', data: {'roleId': roleId});
    } catch (e) {
      AppLogger.e(_tag, '为用户分配角色失败', e);
      rethrow;
    }
  }

  /// 强制用户下线：tokenVersion +1
  Future<void> bumpUserTokenVersion(String userId) async {
    try {
      AppLogger.d(_tag, '🔒 强制用户下线: userId=$userId (tokenVersion+1)');
      await _apiClient.post('/admin/users/$userId/token-version/bump');
    } catch (e) {
      AppLogger.e(_tag, '强制用户下线失败', e);
      rethrow;
    }
  }

  // ========== 公共模型配置管理方法 ==========

  /// 获取公共模型配置详细信息列表
  Future<List<PublicModelConfigDetails>> getPublicModelConfigDetails() async {
    try {
      AppLogger.d(_tag, '🔍 获取公共模型配置详细信息列表');
      final response = await _apiClient.get('/admin/model-configs');
      
      AppLogger.d(_tag, '📡 响应类型: ${response.runtimeType}');
      if (response is Map<String, dynamic>) {
        AppLogger.d(_tag, '📡 响应键: ${response.keys.toList()}');
      }
      
      // 改进响应数据解析逻辑
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      AppLogger.d(_tag, '📡 原始数据类型: ${rawData.runtimeType}');
      
      // 检查数据类型并转换为List
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
      } else if (rawData is Map<String, dynamic>) {
        if (rawData.containsKey('content')) {
          data = (rawData['content'] as List?) ?? [];
        } else {
          throw ApiException(-1, '公共模型配置详细信息数据格式错误: 期望List但收到Map');
        }
      } else {
        throw ApiException(-1, '公共模型配置详细信息数据格式错误: 未知的数据类型');
      }
      
      AppLogger.d(_tag, '📡 数据列表长度: ${data.length}');
      
      // 逐个解析配置，捕获单个配置的解析错误
      final List<PublicModelConfigDetails> configs = [];
      for (int i = 0; i < data.length; i++) {
        try {
          final json = data[i] as Map<String, dynamic>;
          
          // 调试时间字段
          if (json.containsKey('createdAt')) {
            AppLogger.d(_tag, '🕒 配置 $i createdAt 类型: ${json['createdAt'].runtimeType}, 值: ${json['createdAt']}');
          }
          if (json.containsKey('updatedAt')) {
            AppLogger.d(_tag, '🕒 配置 $i updatedAt 类型: ${json['updatedAt'].runtimeType}, 值: ${json['updatedAt']}');
          }
          
          // 检查 API Key 状态中的时间字段
          if (json.containsKey('apiKeyStatuses') && json['apiKeyStatuses'] is List) {
            final apiKeyStatuses = json['apiKeyStatuses'] as List;
            for (int j = 0; j < apiKeyStatuses.length && j < 2; j++) {
              final keyStatus = apiKeyStatuses[j] as Map<String, dynamic>;
              if (keyStatus.containsKey('lastValidatedAt')) {
                AppLogger.d(_tag, '🔑 配置 $i API Key $j lastValidatedAt 类型: ${keyStatus['lastValidatedAt'].runtimeType}, 值: ${keyStatus['lastValidatedAt']}');
              }
            }
          }
          
          final config = PublicModelConfigDetails.fromJson(json);
          configs.add(config);
          AppLogger.d(_tag, '✅ 成功解析配置 $i: ${config.provider}/${config.modelId}');
        } catch (e, stackTrace) {
          AppLogger.e(_tag, '❌ 解析配置 $i 失败', e);
          AppLogger.e(_tag, '❌ 配置 $i JSON: ${data[i]}', stackTrace);
          // 继续处理其他配置，不中断整个过程
        }
      }
      
      AppLogger.d(_tag, '✅ 获取公共模型配置详细信息成功: 总共 ${data.length} 个，成功解析 ${configs.length} 个');
      return configs;
    } catch (e, stackTrace) {
      AppLogger.e(_tag, '❌ 获取公共模型配置详细信息失败', e);
      AppLogger.e(_tag, '❌ 错误堆栈', stackTrace);
      rethrow;
    }
  }

  /// 验证指定的公共模型配置
  Future<PublicModelConfigDetails> validatePublicModelConfig(String configId) async {
    try {
      AppLogger.d(_tag, '🔍 验证公共模型配置: configId=$configId');
      final response = await _apiClient.post('/admin/model-configs/$configId/validate');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 验证公共模型配置成功: configId=$configId');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '验证公共模型配置响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 验证公共模型配置失败', e);
      rethrow;
    }
  }

  /// 验证指定配置并返回包含API Keys的详细信息（便于展示每个Key的验证结果）
  Future<PublicModelConfigWithKeys> validatePublicModelConfigAndFetchWithKeys(String configId) async {
    // 先触发验证
    await validatePublicModelConfig(configId);
    // 再获取包含Key明细的配置
    return getPublicModelConfigById(configId);
  }

  /// 切换公共模型配置的启用状态
  Future<PublicModelConfigDetails> togglePublicModelConfigStatus(String configId, bool enabled) async {
    try {
      AppLogger.d(_tag, '🔄 切换公共模型配置状态: configId=$configId, enabled=$enabled');
      final response = await _apiClient.patch('/admin/model-configs/$configId/status', data: {'enabled': enabled});
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 切换公共模型配置状态成功: configId=$configId');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '切换公共模型配置状态响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 切换公共模型配置状态失败', e);
      rethrow;
    }
  }

  /// 获取单个公共模型配置详细信息（包含API Keys）
  Future<PublicModelConfigWithKeys> getPublicModelConfigById(String configId) async {
    try {
      AppLogger.d(_tag, '🔍 获取公共模型配置详细信息（包含API Keys）: configId=$configId');
      final response = await _apiClient.get('/admin/model-configs/$configId/with-keys');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取公共模型配置详细信息（包含API Keys）成功: configId=$configId');
        return PublicModelConfigWithKeys.fromJson(rawData);
      } else {
        throw ApiException(-1, '获取公共模型配置详细信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取公共模型配置详细信息失败', e);
      rethrow;
    }
  }

  /// 删除公共模型配置
  Future<void> deletePublicModelConfig(String configId) async {
    try {
      AppLogger.d(_tag, '🗑️ 删除公共模型配置: configId=$configId');
      await _apiClient.delete('/admin/model-configs/$configId');
      AppLogger.d(_tag, '✅ 删除公共模型配置成功: configId=$configId');
    } catch (e) {
      AppLogger.e(_tag, '❌ 删除公共模型配置失败', e);
      rethrow;
    }
  }

  /// 创建公共模型配置
  Future<PublicModelConfigDetails> createPublicModelConfig(PublicModelConfigRequest request, {bool validate = false}) async {
    try {
      AppLogger.d(_tag, '🆕 创建公共模型配置: provider=${request.provider}, modelId=${request.modelId}, validate=$validate');
      
      String endpoint = '/admin/model-configs';
      if (validate) {
        endpoint += '?validate=true';
      }
      
      final response = await _apiClient.post(endpoint, data: request.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 创建公共模型配置成功');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '创建公共模型配置响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 创建公共模型配置失败', e);
      rethrow;
    }
  }

  /// 更新公共模型配置
  Future<PublicModelConfigDetails> updatePublicModelConfig(String configId, PublicModelConfigRequest request, {bool validate = false}) async {
    try {
      AppLogger.d(_tag, '🔄 更新公共模型配置: configId=$configId, validate=$validate');
      
      String endpoint = '/admin/model-configs/$configId';
      if (validate) {
        endpoint += '?validate=true';
      }
      
      final response = await _apiClient.put(endpoint, data: request.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 更新公共模型配置成功: configId=$configId');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '更新公共模型配置响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 更新公共模型配置失败', e);
      rethrow;
    }
  }

  /// 为公共模型配置添加API Key
  Future<PublicModelConfigDetails> addApiKeyToPublicModelConfig(String configId, String apiKey, String? note) async {
    try {
      AppLogger.d(_tag, '🔑 为公共模型配置添加API Key: configId=$configId');
      final response = await _apiClient.post('/admin/model-configs/$configId/api-keys', data: {
        'apiKey': apiKey,
        'note': note,
      });
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 添加API Key成功: configId=$configId');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '添加API Key响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 添加API Key失败', e);
      rethrow;
    }
  }

  /// 从公共模型配置移除API Key
  Future<PublicModelConfigDetails> removeApiKeyFromPublicModelConfig(String configId, String apiKey) async {
    try {
      AppLogger.d(_tag, '🔑 从公共模型配置移除API Key: configId=$configId');
      final response = await _apiClient.delete('/admin/model-configs/$configId/api-keys', data: {
        'apiKey': apiKey,
      });
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 移除API Key成功: configId=$configId');
        return PublicModelConfigDetails.fromJson(rawData);
      } else {
        throw ApiException(-1, '移除API Key响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 移除API Key失败', e);
      rethrow;
    }
  }

  /// 获取可用的AI提供商列表
  Future<List<String>> getAvailableProviders() async {
    try {
      AppLogger.d(_tag, '🔍 获取可用的AI提供商列表');
      final response = await _apiClient.get('/admin/providers');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 获取可用的AI提供商列表成功: count=${rawData.length}');
        return rawData.cast<String>();
      } else {
        throw ApiException(-1, '获取可用的AI提供商列表响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取可用的AI提供商列表失败', e);
      rethrow;
    }
  }

  /// 获取指定提供商的模型信息
  Future<List<Map<String, dynamic>>> getModelsForProvider(String provider) async {
    try {
      AppLogger.d(_tag, '🔍 获取提供商模型信息: provider=$provider');
      final response = await _apiClient.get('/admin/providers/$provider/models');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 获取提供商模型信息成功: provider=$provider, count=${rawData.length}');
        return rawData.cast<Map<String, dynamic>>();
      } else {
        throw ApiException(-1, '获取提供商模型信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取提供商模型信息失败', e);
      rethrow;
    }
  }

  /// 使用API Key获取指定提供商的模型信息
  Future<List<Map<String, dynamic>>> getModelsForProviderWithApiKey(String provider, String apiKey, String? apiEndpoint) async {
    try {
      AppLogger.d(_tag, '🔍 使用API Key获取提供商模型信息: provider=$provider');
      final response = await _apiClient.post('/admin/providers/$provider/models', data: {
        'apiKey': apiKey,
        'apiEndpoint': apiEndpoint,
      });
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 使用API Key获取提供商模型信息成功: provider=$provider, count=${rawData.length}');
        return rawData.cast<Map<String, dynamic>>();
      } else {
        throw ApiException(-1, '使用API Key获取提供商模型信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 使用API Key获取提供商模型信息失败', e);
      rethrow;
    }
  }

  // ========== 系统预设管理方法 ==========

  /// 获取系统预设列表
  Future<List<AIPromptPreset>> getSystemPresets({String? featureType}) async {
    try {
      AppLogger.d(_tag, '🔍 获取系统预设列表: featureType=$featureType');
      
      String endpoint = '/admin/prompt-presets';
      if (featureType != null && featureType.isNotEmpty) {
        endpoint += '?featureType=$featureType';
      }
      
      final response = await _apiClient.get(endpoint);
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      List<dynamic> data;
      if (rawData is List) {
        data = rawData;
      } else if (rawData is Map<String, dynamic>) {
        if (rawData.containsKey('content')) {
          data = (rawData['content'] as List?) ?? [];
        } else {
          throw ApiException(-1, '系统预设列表数据格式错误: 期望List但收到Map');
        }
      } else {
        throw ApiException(-1, '系统预设列表数据格式错误: 未知的数据类型');
      }
      
      AppLogger.d(_tag, '✅ 获取系统预设列表成功: count=${data.length}');
      return data.map((json) => AIPromptPreset.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取系统预设列表失败', e);
      rethrow;
    }
  }

  /// 创建系统预设
  Future<AIPromptPreset> createSystemPreset(AIPromptPreset preset) async {
    try {
      AppLogger.d(_tag, '🆕 创建系统预设: ${preset.presetName}');
      final response = await _apiClient.post('/admin/prompt-presets', data: preset.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 创建系统预设成功: ${preset.presetName}');
        return AIPromptPreset.fromJson(rawData);
      } else {
        throw ApiException(-1, '创建系统预设响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 创建系统预设失败', e);
      rethrow;
    }
  }

  /// 更新系统预设
  Future<AIPromptPreset> updateSystemPreset(AIPromptPreset preset) async {
    try {
      AppLogger.d(_tag, '🔄 更新系统预设: ${preset.presetId}');
      final response = await _apiClient.put('/admin/prompt-presets/${preset.presetId}', data: preset.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 更新系统预设成功: ${preset.presetId}');
        return AIPromptPreset.fromJson(rawData);
      } else {
        throw ApiException(-1, '更新系统预设响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 更新系统预设失败', e);
      rethrow;
    }
  }

  /// 删除系统预设
  Future<void> deleteSystemPreset(String presetId) async {
    try {
      AppLogger.d(_tag, '🗑️ 删除系统预设: $presetId');
      await _apiClient.delete('/admin/prompt-presets/$presetId');
      AppLogger.d(_tag, '✅ 删除系统预设成功: $presetId');
    } catch (e) {
      AppLogger.e(_tag, '❌ 删除系统预设失败', e);
      rethrow;
    }
  }

  /// 切换系统预设快捷访问状态
  Future<AIPromptPreset> toggleSystemPresetQuickAccess(String presetId) async {
    try {
      AppLogger.d(_tag, '🔄 切换系统预设快捷访问状态: $presetId');
      final response = await _apiClient.post('/admin/prompt-presets/$presetId/toggle-quick-access');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 切换系统预设快捷访问状态成功: $presetId');
        return AIPromptPreset.fromJson(rawData);
      } else {
        throw ApiException(-1, '切换快捷访问状态响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 切换系统预设快捷访问状态失败', e);
      rethrow;
    }
  }

  /// 批量更新系统预设可见性
  Future<List<AIPromptPreset>> batchUpdateSystemPresetsVisibility(List<String> presetIds, bool showInQuickAccess) async {
    try {
      AppLogger.d(_tag, '🔄 批量更新系统预设可见性: count=${presetIds.length}, visible=$showInQuickAccess');
      final response = await _apiClient.patch('/admin/prompt-presets/batch-visibility', data: {
        'presetIds': presetIds,
        'showInQuickAccess': showInQuickAccess,
      });
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 批量更新系统预设可见性成功: count=${rawData.length}');
        return rawData.map((json) => AIPromptPreset.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw ApiException(-1, '批量更新可见性响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 批量更新系统预设可见性失败', e);
      rethrow;
    }
  }

  /// 获取系统预设统计信息
  Future<Map<String, dynamic>> getSystemPresetsStatistics() async {
    try {
      AppLogger.d(_tag, '📊 获取系统预设统计信息');
      final response = await _apiClient.get('/admin/prompt-presets/statistics');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取系统预设统计信息成功');
        return rawData;
      } else {
        throw ApiException(-1, '获取统计信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取系统预设统计信息失败', e);
      rethrow;
    }
  }

  /// 获取系统预设详情
  Future<Map<String, dynamic>> getSystemPresetDetails(String presetId) async {
    try {
      AppLogger.d(_tag, '📊 获取系统预设详情: $presetId');
      final response = await _apiClient.get('/admin/prompt-presets/$presetId/details');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取系统预设详情成功: $presetId');
        return rawData;
      } else {
        throw ApiException(-1, '获取预设详情响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取系统预设详情失败', e);
      rethrow;
    }
  }

  /// 导出系统预设
  Future<List<AIPromptPreset>> exportSystemPresets(List<String> presetIds) async {
    try {
      AppLogger.d(_tag, '📤 导出系统预设: count=${presetIds.length}');
      final response = await _apiClient.post('/admin/prompt-presets/export', data: {
        'presetIds': presetIds,
      });
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 导出系统预设成功: count=${rawData.length}');
        return rawData.map((json) => AIPromptPreset.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw ApiException(-1, '导出预设响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 导出系统预设失败', e);
      rethrow;
    }
  }

  /// 导入系统预设
  Future<List<AIPromptPreset>> importSystemPresets(List<AIPromptPreset> presets) async {
    try {
      AppLogger.d(_tag, '📥 导入系统预设: count=${presets.length}');
      final response = await _apiClient.post('/admin/prompt-presets/import', 
        data: presets.map((preset) => preset.toJson()).toList());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 导入系统预设成功: count=${rawData.length}');
        return rawData.map((json) => AIPromptPreset.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw ApiException(-1, '导入预设响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 导入系统预设失败', e);
      rethrow;
    }
  }

  // ========== 公共模板管理方法 ==========

  /// 获取公共模板列表
  Future<List<PromptTemplate>> getPublicTemplates({
    String? search,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取公共模板列表: search=$search');
      
      String path = '/admin/prompt-templates/public';
      if (search != null && search.isNotEmpty) {
        path += '?search=${Uri.encodeComponent(search)}';
      }
      
      final response = await _apiClient.get(path);
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 获取公共模板列表成功: count=${rawData.length}');
        return rawData.map((json) => PromptTemplate.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw ApiException(-1, '公共模板列表响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取公共模板列表失败', e);
      rethrow;
    }
  }

  /// 创建官方模板
  Future<PromptTemplate> createOfficialTemplate(PromptTemplate template) async {
    try {
      AppLogger.d(_tag, '🆕 创建官方模板: ${template.name}');
      final response = await _apiClient.post('/admin/prompt-templates/official', 
        data: template.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 创建官方模板成功: ${template.name}');
        return PromptTemplate.fromJson(rawData);
      } else {
        throw ApiException(-1, '创建官方模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 创建官方模板失败', e);
      rethrow;
    }
  }

  /// 审核模板
  Future<void> reviewTemplate(
    String templateId, {
    required bool approved,
    String? comment,
    bool requestChanges = false,
  }) async {
    try {
      AppLogger.d(_tag, '📝 审核模板: templateId=$templateId, approved=$approved');
      await _apiClient.post('/admin/prompt-templates/$templateId/review', data: {
        'approved': approved,
        'comment': comment,
        'requestChanges': requestChanges,
      });
      AppLogger.d(_tag, '✅ 审核模板成功');
    } catch (e) {
      AppLogger.e(_tag, '❌ 审核模板失败', e);
      rethrow;
    }
  }

  /// 发布模板
  Future<void> publishTemplate(String templateId) async {
    try {
      AppLogger.d(_tag, '🚀 发布模板: templateId=$templateId');
      await _apiClient.post('/admin/prompt-templates/$templateId/publish');
      AppLogger.d(_tag, '✅ 发布模板成功');
    } catch (e) {
      AppLogger.e(_tag, '❌ 发布模板失败', e);
      rethrow;
    }
  }

  /// 设置模板认证状态
  Future<void> setTemplateVerified(String templateId, bool verified) async {
    try {
      AppLogger.d(_tag, '🔰 设置模板认证状态: templateId=$templateId, verified=$verified');
      await _apiClient.post('/admin/prompt-templates/$templateId/verify', data: {
        'verified': verified,
      });
      AppLogger.d(_tag, '✅ 设置模板认证状态成功');
    } catch (e) {
      AppLogger.e(_tag, '❌ 设置模板认证状态失败', e);
      rethrow;
    }
  }

  /// 删除模板
  Future<void> deleteTemplate(String templateId) async {
    try {
      AppLogger.d(_tag, '🗑️ 删除模板: templateId=$templateId');
      await _apiClient.delete('/admin/prompt-templates/$templateId');
      AppLogger.d(_tag, '✅ 删除模板成功');
    } catch (e) {
      AppLogger.e(_tag, '❌ 删除模板失败', e);
      rethrow;
    }
  }

  /// 获取模板统计数据
  Future<Map<String, dynamic>> getTemplateStatistics() async {
    try {
      AppLogger.d(_tag, '📊 获取模板统计数据');
      final response = await _apiClient.get('/admin/prompt-templates/statistics');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取模板统计数据成功');
        return rawData;
      } else {
        throw ApiException(-1, '模板统计数据响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取模板统计数据失败', e);
      rethrow;
    }
  }

  // ==================== 增强模板管理API ====================

  /// 获取所有公共增强模板
  Future<List<EnhancedUserPromptTemplate>> getAllPublicEnhancedTemplates({
    String? featureType,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取所有公共增强模板: featureType=$featureType');
      
      String path = '/admin/prompt-templates/public';
      if (featureType != null) {
        path += '?featureType=$featureType';
      }
      
      final response = await _apiClient.get(path);
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取公共增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '公共增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取公共增强模板失败', e);
      rethrow;
    }
  }

  /// 获取已验证增强模板
  Future<List<EnhancedUserPromptTemplate>> getVerifiedEnhancedTemplates() async {
    try {
      AppLogger.d(_tag, '🔍 获取已验证增强模板');
      
      final response = await _apiClient.get('/admin/prompt-templates/verified');
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取已验证增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '已验证增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取已验证增强模板失败', e);
      rethrow;
    }
  }

  /// 获取待审核增强模板
  Future<List<EnhancedUserPromptTemplate>> getPendingEnhancedTemplates() async {
    try {
      AppLogger.d(_tag, '🔍 获取待审核增强模板');
      
      final response = await _apiClient.get('/admin/prompt-templates/pending');
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取待审核增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '待审核增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取待审核增强模板失败', e);
      rethrow;
    }
  }

  /// 获取热门增强模板
  Future<List<EnhancedUserPromptTemplate>> getPopularEnhancedTemplates({
    String? featureType,
    int limit = 10,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取热门增强模板: featureType=$featureType, limit=$limit');
      
      String path = '/admin/prompt-templates/popular?limit=$limit';
      if (featureType != null) {
        path += '&featureType=$featureType';
      }
      
      final response = await _apiClient.get(path);
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取热门增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '热门增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取热门增强模板失败', e);
      rethrow;
    }
  }

  /// 获取最新增强模板
  Future<List<EnhancedUserPromptTemplate>> getLatestEnhancedTemplates({
    String? featureType,
    int limit = 10,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取最新增强模板: featureType=$featureType, limit=$limit');
      
      String path = '/admin/prompt-templates/latest?limit=$limit';
      if (featureType != null) {
        path += '&featureType=$featureType';
      }
      
      final response = await _apiClient.get(path);
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取最新增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '最新增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取最新增强模板失败', e);
      rethrow;
    }
  }

  /// 搜索公共增强模板
  Future<List<EnhancedUserPromptTemplate>> searchEnhancedTemplates({
    String? keyword,
    String? featureType,
    bool? verified,
    int page = 0,
    int size = 20,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 搜索增强模板: keyword=$keyword, featureType=$featureType, verified=$verified, page=$page, size=$size');
      
      final queryParams = <String, String>{
        'page': page.toString(),
        'size': size.toString(),
      };
      
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }
      if (featureType != null && featureType.isNotEmpty) {
        queryParams['featureType'] = featureType;
      }
      if (verified != null) {
        queryParams['verified'] = verified.toString();
      }
      
      final queryString = queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
      final path = '/admin/prompt-templates/search?$queryString';
      
      final response = await _apiClient.get(path);
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 搜索增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '搜索增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 搜索增强模板失败', e);
      rethrow;
    }
  }

  /// 创建官方增强模板
  Future<EnhancedUserPromptTemplate> createOfficialEnhancedTemplate(
    EnhancedUserPromptTemplate template,
  ) async {
    try {
      AppLogger.d(_tag, '📝 创建官方增强模板: ${template.name}');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/official',
        data: template.toJson(),
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 创建官方增强模板成功');
        return EnhancedUserPromptTemplate.fromJson(responseData);
      } else {
        throw ApiException(-1, '创建官方增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 创建官方增强模板失败', e);
      rethrow;
    }
  }

  /// 更新增强模板
  Future<EnhancedUserPromptTemplate> updateEnhancedTemplate(
    String templateId,
    EnhancedUserPromptTemplate template,
  ) async {
    try {
      AppLogger.d(_tag, '📝 更新增强模板: $templateId');
      
      final response = await _apiClient.put(
        '/admin/prompt-templates/$templateId',
        data: template.toJson(),
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 更新增强模板成功');
        return EnhancedUserPromptTemplate.fromJson(responseData);
      } else {
        throw ApiException(-1, '更新增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 更新增强模板失败', e);
      rethrow;
    }
  }

  /// 删除增强模板
  Future<void> deleteEnhancedTemplate(String templateId) async {
    try {
      AppLogger.d(_tag, '🗑️ 删除增强模板: $templateId');
      
      await _apiClient.delete('/admin/prompt-templates/$templateId');
      
      AppLogger.d(_tag, '✅ 删除增强模板成功');
    } catch (e) {
      AppLogger.e(_tag, '❌ 删除增强模板失败', e);
      rethrow;
    }
  }

  /// 审核增强模板
  Future<EnhancedUserPromptTemplate> reviewEnhancedTemplate(
    String templateId,
    bool approved,
    String? reviewComment,
  ) async {
    try {
      AppLogger.d(_tag, '📋 审核增强模板: $templateId, approved=$approved');
      
      String path = '/admin/prompt-templates/$templateId/review?approved=$approved';
      if (reviewComment != null && reviewComment.isNotEmpty) {
        path += '&reviewComment=${Uri.encodeQueryComponent(reviewComment)}';
      }
      
      final response = await _apiClient.post(path);
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 审核增强模板成功');
        return EnhancedUserPromptTemplate.fromJson(responseData);
      } else {
        throw ApiException(-1, '审核增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 审核增强模板失败', e);
      rethrow;
    }
  }

  /// 获取所有用户模板（包括私有和公共）
  Future<List<EnhancedUserPromptTemplate>> getAllUserEnhancedTemplates({
    int page = 0,
    int size = 20,
    String? search,
  }) async {
    try {
      AppLogger.d(_tag, '🔍 获取所有用户增强模板: page=$page, size=$size, search=$search');
      
      String path = '/admin/prompt-templates/all-user?page=$page&size=$size';
      if (search != null && search.isNotEmpty) {
        path += '&search=${Uri.encodeQueryComponent(search)}';
      }
      
      final response = await _apiClient.get(path);
      
      if (response is List) {
        AppLogger.d(_tag, '✅ 获取所有用户增强模板成功: ${response.length} 个');
        return response.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '用户增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取所有用户增强模板失败', e);
      rethrow;
    }
  }

  /// 设置增强模板验证状态
  Future<EnhancedUserPromptTemplate> setEnhancedTemplateVerified(
    String templateId,
    bool verified,
  ) async {
    try {
      AppLogger.d(_tag, '✅ 设置增强模板验证状态: $templateId, verified=$verified');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/$templateId/verify?verified=$verified',
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 设置增强模板验证状态成功');
        return EnhancedUserPromptTemplate.fromJson(responseData);
      } else {
        throw ApiException(-1, '设置增强模板验证状态响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 设置增强模板验证状态失败', e);
      rethrow;
    }
  }

  /// 发布/取消发布增强模板
  Future<EnhancedUserPromptTemplate> toggleEnhancedTemplatePublish(
    String templateId,
    bool publish,
  ) async {
    try {
      AppLogger.d(_tag, '🌐 ${publish ? "发布" : "取消发布"}增强模板: $templateId');
      
      final endpoint = publish ? 'publish' : 'unpublish';
      final response = await _apiClient.post('/admin/prompt-templates/$templateId/$endpoint');
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ ${publish ? "发布" : "取消发布"}增强模板成功');
        return EnhancedUserPromptTemplate.fromJson(responseData);
      } else {
        throw ApiException(-1, '${publish ? "发布" : "取消发布"}增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ ${publish ? "发布" : "取消发布"}增强模板失败', e);
      rethrow;
    }
  }

  /// 批量审核增强模板
  Future<Map<String, Object>> batchReviewEnhancedTemplates(
    List<String> templateIds,
    bool approved,
  ) async {
    try {
      AppLogger.d(_tag, '📋 批量审核增强模板: ${templateIds.length} 个, approved=$approved');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/batch/review?approved=$approved',
        data: templateIds,
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 批量审核增强模板成功');
        return Map<String, Object>.from(responseData);
      } else {
        throw ApiException(-1, '批量审核增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 批量审核增强模板失败', e);
      rethrow;
    }
  }

  /// 批量设置增强模板验证状态
  Future<Map<String, Object>> batchSetEnhancedTemplatesVerified(
    List<String> templateIds,
    bool verified,
  ) async {
    try {
      AppLogger.d(_tag, '✅ 批量设置增强模板验证状态: ${templateIds.length} 个, verified=$verified');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/batch/verify?verified=$verified',
        data: templateIds,
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 批量设置增强模板验证状态成功');
        return Map<String, Object>.from(responseData);
      } else {
        throw ApiException(-1, '批量设置增强模板验证状态响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 批量设置增强模板验证状态失败', e);
      rethrow;
    }
  }

  /// 批量发布增强模板
  Future<Map<String, Object>> batchPublishEnhancedTemplates(
    List<String> templateIds,
    bool publish,
  ) async {
    try {
      AppLogger.d(_tag, '🌐 批量${publish ? "发布" : "取消发布"}增强模板: ${templateIds.length} 个');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/batch/publish?publish=$publish',
        data: templateIds,
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 批量${publish ? "发布" : "取消发布"}增强模板成功');
        return Map<String, Object>.from(responseData);
      } else {
        throw ApiException(-1, '批量${publish ? "发布" : "取消发布"}增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 批量${publish ? "发布" : "取消发布"}增强模板失败', e);
      rethrow;
    }
  }

  /// 获取增强模板统计信息
  Future<Map<String, Object>> getEnhancedTemplatesStatistics() async {
    try {
      AppLogger.d(_tag, '📊 获取增强模板统计信息');
      
      final response = await _apiClient.get('/admin/prompt-templates/statistics/system');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取增强模板统计信息成功');
        return Map<String, Object>.from(rawData);
      } else {
        throw ApiException(-1, '增强模板统计信息响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取增强模板统计信息失败', e);
      rethrow;
    }
  }

  /// 获取增强模板详情统计
  Future<Map<String, Object>> getEnhancedTemplateStatistics(String templateId) async {
    try {
      AppLogger.d(_tag, '📊 获取增强模板详情统计: $templateId');
      
      final response = await _apiClient.get('/admin/prompt-templates/$templateId/statistics');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 获取增强模板详情统计成功');
        return Map<String, Object>.from(rawData);
      } else {
        throw ApiException(-1, '增强模板详情统计响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取增强模板详情统计失败', e);
      rethrow;
    }
  }

  /// 导出增强模板
  Future<List<EnhancedUserPromptTemplate>> exportEnhancedTemplates(
    List<String> templateIds,
  ) async {
    try {
      AppLogger.d(_tag, '📤 导出增强模板: ${templateIds.length} 个');
      
      final response = await _apiClient.post(
        '/admin/prompt-templates/export',
        data: templateIds.isEmpty ? null : templateIds,
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is List) {
        AppLogger.d(_tag, '✅ 导出增强模板成功: ${responseData.length} 个');
        return responseData.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '导出增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 导出增强模板失败', e);
      rethrow;
    }
  }

  /// 导入增强模板
  Future<List<EnhancedUserPromptTemplate>> importEnhancedTemplates(
    List<EnhancedUserPromptTemplate> templates,
  ) async {
    try {
      AppLogger.d(_tag, '📤 导入增强模板: ${templates.length} 个');
      
      final templateJsons = templates.map((template) => template.toJson()).toList();
      final response = await _apiClient.post(
        '/admin/prompt-templates/import',
        data: templateJsons,
      );
      
      dynamic responseData = response;
      if (response is Map<String, dynamic> && response.containsKey('data')) {
        responseData = response['data'];
      }
      
      if (responseData is List) {
        AppLogger.d(_tag, '✅ 导入增强模板成功: ${responseData.length} 个');
        return responseData.map((json) => EnhancedUserPromptTemplate.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '导入增强模板响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 导入增强模板失败', e);
      rethrow;
    }
  }

  // ========== 模型定价管理方法 ==========

  /// 检查模型定价是否存在
  Future<PricingCheckResult> checkModelPricing(String provider, String modelId) async {
    try {
      AppLogger.d(_tag, '🔍 检查模型定价: provider=$provider, modelId=$modelId');
      
      final response = await _apiClient.get('/pricing/check/$provider/$modelId');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 检查模型定价成功: provider=$provider, modelId=$modelId');
        return PricingCheckResult.fromJson(rawData);
      } else {
        throw ApiException(-1, '检查模型定价响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 检查模型定价失败', e);
      rethrow;
    }
  }

  /// 获取所有模型定价信息
  Future<List<ModelPricing>> getAllModelPricing() async {
    try {
      AppLogger.d(_tag, '📋 获取所有模型定价');
      
      final response = await _apiClient.get('/pricing');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 获取所有模型定价成功: count=${rawData.length}');
        return rawData.map((json) => ModelPricing.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '获取所有模型定价响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取所有模型定价失败', e);
      rethrow;
    }
  }

  /// 根据提供商获取模型定价
  Future<List<ModelPricing>> getModelPricingByProvider(String provider) async {
    try {
      AppLogger.d(_tag, '📋 获取提供商模型定价: provider=$provider');
      
      final response = await _apiClient.get('/pricing/provider/$provider');
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is List) {
        AppLogger.d(_tag, '✅ 获取提供商模型定价成功: provider=$provider, count=${rawData.length}');
        return rawData.map((json) => ModelPricing.fromJson(json)).toList();
      } else {
        throw ApiException(-1, '获取提供商模型定价响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 获取提供商模型定价失败', e);
      rethrow;
    }
  }

  /// 创建模型定价
  Future<ModelPricing> createModelPricing(CreatePricingRequest request) async {
    try {
      AppLogger.d(_tag, '➕ 创建模型定价: provider=${request.provider}, modelId=${request.modelId}');
      
      final response = await _apiClient.post('/pricing/create-for-model', data: request.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 创建模型定价成功: provider=${request.provider}, modelId=${request.modelId}');
        return ModelPricing.fromJson(rawData);
      } else {
        throw ApiException(-1, '创建模型定价响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 创建模型定价失败', e);
      rethrow;
    }
  }

  /// 更新模型定价
  Future<ModelPricing> updateModelPricing(ModelPricing pricing) async {
    try {
      AppLogger.d(_tag, '🔄 更新模型定价: provider=${pricing.provider}, modelId=${pricing.modelId}');
      
      final response = await _apiClient.put('/pricing', data: pricing.toJson());
      
      dynamic rawData;
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          rawData = response['data'];
        } else if (response.containsKey('success') && response['success'] == true) {
          rawData = response['data'] ?? response;
        } else {
          rawData = response;
        }
      } else {
        rawData = response;
      }
      
      if (rawData is Map<String, dynamic>) {
        AppLogger.d(_tag, '✅ 更新模型定价成功: provider=${pricing.provider}, modelId=${pricing.modelId}');
        return ModelPricing.fromJson(rawData);
      } else {
        throw ApiException(-1, '更新模型定价响应格式错误');
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 更新模型定价失败', e);
      rethrow;
    }
  }

  /// 删除模型定价
  Future<void> deleteModelPricing(String provider, String modelId) async {
    try {
      AppLogger.d(_tag, '🗑️ 删除模型定价: provider=$provider, modelId=$modelId');
      
      await _apiClient.delete('/pricing/provider/$provider/model/$modelId');
      
      AppLogger.d(_tag, '✅ 删除模型定价成功: provider=$provider, modelId=$modelId');
    } catch (e) {
      AppLogger.e(_tag, '❌ 删除模型定价失败', e);
      rethrow;
    }
  }
}