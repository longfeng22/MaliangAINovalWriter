import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import '../../utils/date_time_parser.dart';

part 'admin_models.g.dart';

@JsonSerializable()
class AdminDashboardStats extends Equatable {
  final int totalUsers;
  final int activeUsers;
  final int totalNovels;
  final int aiRequestsToday;
  final double creditsConsumed;
  final List<ChartData> userGrowthData;
  final List<ChartData> requestsData;
  final List<ActivityItem> recentActivities;
  final List<ChartData> dailyLoginData;
  final List<ChartData> dailyRegistrationData;
  final List<UserNovelStats> userNovelStats;
  final int newUsersToday;
  final int loginsToday;

  const AdminDashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.totalNovels,
    required this.aiRequestsToday,
    required this.creditsConsumed,
    required this.userGrowthData,
    required this.requestsData,
    required this.recentActivities,
    required this.dailyLoginData,
    required this.dailyRegistrationData,
    required this.userNovelStats,
    required this.newUsersToday,
    required this.loginsToday,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) =>
      _$AdminDashboardStatsFromJson(json);

  Map<String, dynamic> toJson() => _$AdminDashboardStatsToJson(this);

  @override
  List<Object> get props => [
        totalUsers,
        activeUsers,
        totalNovels,
        aiRequestsToday,
        creditsConsumed,
        userGrowthData,
        requestsData,
        recentActivities,
        dailyLoginData,
        dailyRegistrationData,
        userNovelStats,
        newUsersToday,
        loginsToday,
      ];
}

@JsonSerializable()
class ChartData extends Equatable {
  final String label;
  final double value;
  final DateTime date;

  const ChartData({
    required this.label,
    required this.value,
    required this.date,
  });


  factory ChartData.fromJson(Map<String, dynamic> json) {
    return ChartData(
      label: json['label'] as String,
      value: (json['value'] as num).toDouble(),
      date: parseBackendDateTime(json['date']),
    );
  }

  Map<String, dynamic> toJson() => _$ChartDataToJson(this);

  @override
  List<Object> get props => [label, value, date];
}

@JsonSerializable()
class ActivityItem extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String action;
  final String description;
  final DateTime timestamp;
  final String? metadata;

  const ActivityItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    required this.description,
    required this.timestamp,
    this.metadata,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      action: json['action'] as String,
      description: json['description'] as String,
      timestamp: parseBackendDateTime(json['timestamp']),
      metadata: json['metadata'] as String?,
    );
  }

  Map<String, dynamic> toJson() => _$ActivityItemToJson(this);

  @override
  List<Object?> get props => [
        id,
        userId,
        userName,
        action,
        description,
        timestamp,
        metadata,
      ];
}

@JsonSerializable()
class AdminUser extends Equatable {
  final String id;
  final String username;
  final String email; // 后端可能返回 null，这里统一转换为空串
  final String? displayName;
  final String accountStatus;
  final int credits;
  final List<String> roles;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AdminUser({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    required this.accountStatus,
    required this.credits,
    required this.roles,
    required this.createdAt,
    this.updatedAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String,
      username: json['username'] as String,
      email: (json['email'] as String?) ?? '',
      displayName: json['displayName'] as String?,
      accountStatus: json['accountStatus']?.toString() ?? 'ACTIVE',
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      roles: (json['roles'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: parseBackendDateTime(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? parseBackendDateTime(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => _$AdminUserToJson(this);

  @override
  List<Object?> get props => [
        id,
        username,
        email,
        displayName,
        accountStatus,
        credits,
        roles,
        createdAt,
        updatedAt,
      ];
}

@JsonSerializable()
class AdminRole extends Equatable {
  final String? id;
  final String roleName;
  final String displayName;
  final String? description;
  final List<String> permissions;
  final bool enabled;
  final int priority;

  const AdminRole({
    this.id,
    required this.roleName,
    required this.displayName,
    this.description,
    required this.permissions,
    required this.enabled,
    required this.priority,
  });

  factory AdminRole.fromJson(Map<String, dynamic> json) =>
      _$AdminRoleFromJson(json);

  Map<String, dynamic> toJson() => _$AdminRoleToJson(this);

  @override
  List<Object?> get props => [
        id,
        roleName,
        displayName,
        description,
        permissions,
        enabled,
        priority,
      ];
}

@JsonSerializable()
class AdminModelConfig extends Equatable {
  final String? id;
  final String provider;
  final String modelId;
  final String? displayName;
  final bool enabled;
  final List<String> enabledForFeatures;
  final double creditRateMultiplier;
  final int maxConcurrentRequests;
  final int dailyRequestLimit;
  final String? description;

  const AdminModelConfig({
    this.id,
    required this.provider,
    required this.modelId,
    this.displayName,
    required this.enabled,
    required this.enabledForFeatures,
    required this.creditRateMultiplier,
    required this.maxConcurrentRequests,
    required this.dailyRequestLimit,
    this.description,
  });

  factory AdminModelConfig.fromJson(Map<String, dynamic> json) =>
      _$AdminModelConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AdminModelConfigToJson(this);

  @override
  List<Object?> get props => [
        id,
        provider,
        modelId,
        displayName,
        enabled,
        enabledForFeatures,
        creditRateMultiplier,
        maxConcurrentRequests,
        dailyRequestLimit,
        description,
      ];
}

@JsonSerializable()
class AdminSystemConfig extends Equatable {
  final String id;
  final String configKey;
  final String configValue;
  final String? description;
  final String configType;
  final String? configGroup;
  final bool enabled;
  final bool readOnly;

  const AdminSystemConfig({
    required this.id,
    required this.configKey,
    required this.configValue,
    this.description,
    required this.configType,
    this.configGroup,
    required this.enabled,
    required this.readOnly,
  });

  factory AdminSystemConfig.fromJson(Map<String, dynamic> json) =>
      _$AdminSystemConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AdminSystemConfigToJson(this);

  @override
  List<Object?> get props => [
        id,
        configKey,
        configValue,
        description,
        configType,
        configGroup,
        enabled,
        readOnly,
      ];
}

@JsonSerializable()
class UserNovelStats extends Equatable {
  final String userId;
  final String username;
  final String? displayName;
  final int novelCount;
  final DateTime lastCreatedAt;

  const UserNovelStats({
    required this.userId,
    required this.username,
    this.displayName,
    required this.novelCount,
    required this.lastCreatedAt,
  });

  factory UserNovelStats.fromJson(Map<String, dynamic> json) {
    return UserNovelStats(
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String?,
      novelCount: (json['novelCount'] as num).toInt(),
      lastCreatedAt: parseBackendDateTime(json['lastCreatedAt']),
    );
  }

  Map<String, dynamic> toJson() => _$UserNovelStatsToJson(this);

  @override
  List<Object?> get props => [
        userId,
        username,
        displayName,
        novelCount,
        lastCreatedAt,
      ];
}