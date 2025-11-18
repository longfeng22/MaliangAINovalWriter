// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminDashboardStats _$AdminDashboardStatsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminDashboardStats',
      json,
      ($checkedConvert) {
        final val = AdminDashboardStats(
          totalUsers: $checkedConvert('totalUsers', (v) => (v as num).toInt()),
          activeUsers:
              $checkedConvert('activeUsers', (v) => (v as num).toInt()),
          totalNovels:
              $checkedConvert('totalNovels', (v) => (v as num).toInt()),
          aiRequestsToday:
              $checkedConvert('aiRequestsToday', (v) => (v as num).toInt()),
          creditsConsumed:
              $checkedConvert('creditsConsumed', (v) => (v as num).toDouble()),
          userGrowthData: $checkedConvert(
              'userGrowthData',
              (v) => (v as List<dynamic>)
                  .map((e) => ChartData.fromJson(e as Map<String, dynamic>))
                  .toList()),
          requestsData: $checkedConvert(
              'requestsData',
              (v) => (v as List<dynamic>)
                  .map((e) => ChartData.fromJson(e as Map<String, dynamic>))
                  .toList()),
          recentActivities: $checkedConvert(
              'recentActivities',
              (v) => (v as List<dynamic>)
                  .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
                  .toList()),
          dailyLoginData: $checkedConvert(
              'dailyLoginData',
              (v) => (v as List<dynamic>)
                  .map((e) => ChartData.fromJson(e as Map<String, dynamic>))
                  .toList()),
          dailyRegistrationData: $checkedConvert(
              'dailyRegistrationData',
              (v) => (v as List<dynamic>)
                  .map((e) => ChartData.fromJson(e as Map<String, dynamic>))
                  .toList()),
          userNovelStats: $checkedConvert(
              'userNovelStats',
              (v) => (v as List<dynamic>)
                  .map(
                      (e) => UserNovelStats.fromJson(e as Map<String, dynamic>))
                  .toList()),
          newUsersToday:
              $checkedConvert('newUsersToday', (v) => (v as num).toInt()),
          loginsToday:
              $checkedConvert('loginsToday', (v) => (v as num).toInt()),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminDashboardStatsToJson(
        AdminDashboardStats instance) =>
    <String, dynamic>{
      'totalUsers': instance.totalUsers,
      'activeUsers': instance.activeUsers,
      'totalNovels': instance.totalNovels,
      'aiRequestsToday': instance.aiRequestsToday,
      'creditsConsumed': instance.creditsConsumed,
      'userGrowthData': instance.userGrowthData.map((e) => e.toJson()).toList(),
      'requestsData': instance.requestsData.map((e) => e.toJson()).toList(),
      'recentActivities':
          instance.recentActivities.map((e) => e.toJson()).toList(),
      'dailyLoginData': instance.dailyLoginData.map((e) => e.toJson()).toList(),
      'dailyRegistrationData':
          instance.dailyRegistrationData.map((e) => e.toJson()).toList(),
      'userNovelStats': instance.userNovelStats.map((e) => e.toJson()).toList(),
      'newUsersToday': instance.newUsersToday,
      'loginsToday': instance.loginsToday,
    };

ChartData _$ChartDataFromJson(Map<String, dynamic> json) => $checkedCreate(
      'ChartData',
      json,
      ($checkedConvert) {
        final val = ChartData(
          label: $checkedConvert('label', (v) => v as String),
          value: $checkedConvert('value', (v) => (v as num).toDouble()),
          date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
        );
        return val;
      },
    );

Map<String, dynamic> _$ChartDataToJson(ChartData instance) => <String, dynamic>{
      'label': instance.label,
      'value': instance.value,
      'date': instance.date.toIso8601String(),
    };

ActivityItem _$ActivityItemFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ActivityItem',
      json,
      ($checkedConvert) {
        final val = ActivityItem(
          id: $checkedConvert('id', (v) => v as String),
          userId: $checkedConvert('userId', (v) => v as String),
          userName: $checkedConvert('userName', (v) => v as String),
          action: $checkedConvert('action', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String),
          timestamp:
              $checkedConvert('timestamp', (v) => DateTime.parse(v as String)),
          metadata: $checkedConvert('metadata', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$ActivityItemToJson(ActivityItem instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'userId': instance.userId,
    'userName': instance.userName,
    'action': instance.action,
    'description': instance.description,
    'timestamp': instance.timestamp.toIso8601String(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('metadata', instance.metadata);
  return val;
}

AdminUser _$AdminUserFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AdminUser',
      json,
      ($checkedConvert) {
        final val = AdminUser(
          id: $checkedConvert('id', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
          email: $checkedConvert('email', (v) => v as String),
          displayName: $checkedConvert('displayName', (v) => v as String?),
          accountStatus: $checkedConvert('accountStatus', (v) => v as String),
          credits: $checkedConvert('credits', (v) => (v as num).toInt()),
          roles: $checkedConvert('roles',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          createdAt:
              $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
          updatedAt: $checkedConvert('updatedAt',
              (v) => v == null ? null : DateTime.parse(v as String)),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminUserToJson(AdminUser instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'username': instance.username,
    'email': instance.email,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('displayName', instance.displayName);
  val['accountStatus'] = instance.accountStatus;
  val['credits'] = instance.credits;
  val['roles'] = instance.roles;
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  return val;
}

AdminRole _$AdminRoleFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AdminRole',
      json,
      ($checkedConvert) {
        final val = AdminRole(
          id: $checkedConvert('id', (v) => v as String?),
          roleName: $checkedConvert('roleName', (v) => v as String),
          displayName: $checkedConvert('displayName', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String?),
          permissions: $checkedConvert('permissions',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          enabled: $checkedConvert('enabled', (v) => v as bool),
          priority: $checkedConvert('priority', (v) => (v as num).toInt()),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminRoleToJson(AdminRole instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('id', instance.id);
  val['roleName'] = instance.roleName;
  val['displayName'] = instance.displayName;
  writeNotNull('description', instance.description);
  val['permissions'] = instance.permissions;
  val['enabled'] = instance.enabled;
  val['priority'] = instance.priority;
  return val;
}

AdminModelConfig _$AdminModelConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminModelConfig',
      json,
      ($checkedConvert) {
        final val = AdminModelConfig(
          id: $checkedConvert('id', (v) => v as String?),
          provider: $checkedConvert('provider', (v) => v as String),
          modelId: $checkedConvert('modelId', (v) => v as String),
          displayName: $checkedConvert('displayName', (v) => v as String?),
          enabled: $checkedConvert('enabled', (v) => v as bool),
          enabledForFeatures: $checkedConvert('enabledForFeatures',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          creditRateMultiplier: $checkedConvert(
              'creditRateMultiplier', (v) => (v as num).toDouble()),
          maxConcurrentRequests: $checkedConvert(
              'maxConcurrentRequests', (v) => (v as num).toInt()),
          dailyRequestLimit:
              $checkedConvert('dailyRequestLimit', (v) => (v as num).toInt()),
          description: $checkedConvert('description', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminModelConfigToJson(AdminModelConfig instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('id', instance.id);
  val['provider'] = instance.provider;
  val['modelId'] = instance.modelId;
  writeNotNull('displayName', instance.displayName);
  val['enabled'] = instance.enabled;
  val['enabledForFeatures'] = instance.enabledForFeatures;
  val['creditRateMultiplier'] = instance.creditRateMultiplier;
  val['maxConcurrentRequests'] = instance.maxConcurrentRequests;
  val['dailyRequestLimit'] = instance.dailyRequestLimit;
  writeNotNull('description', instance.description);
  return val;
}

AdminSystemConfig _$AdminSystemConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminSystemConfig',
      json,
      ($checkedConvert) {
        final val = AdminSystemConfig(
          id: $checkedConvert('id', (v) => v as String),
          configKey: $checkedConvert('configKey', (v) => v as String),
          configValue: $checkedConvert('configValue', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String?),
          configType: $checkedConvert('configType', (v) => v as String),
          configGroup: $checkedConvert('configGroup', (v) => v as String?),
          enabled: $checkedConvert('enabled', (v) => v as bool),
          readOnly: $checkedConvert('readOnly', (v) => v as bool),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminSystemConfigToJson(AdminSystemConfig instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'configKey': instance.configKey,
    'configValue': instance.configValue,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  val['configType'] = instance.configType;
  writeNotNull('configGroup', instance.configGroup);
  val['enabled'] = instance.enabled;
  val['readOnly'] = instance.readOnly;
  return val;
}

UserNovelStats _$UserNovelStatsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'UserNovelStats',
      json,
      ($checkedConvert) {
        final val = UserNovelStats(
          userId: $checkedConvert('userId', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
          displayName: $checkedConvert('displayName', (v) => v as String?),
          novelCount: $checkedConvert('novelCount', (v) => (v as num).toInt()),
          lastCreatedAt: $checkedConvert(
              'lastCreatedAt', (v) => DateTime.parse(v as String)),
        );
        return val;
      },
    );

Map<String, dynamic> _$UserNovelStatsToJson(UserNovelStats instance) {
  final val = <String, dynamic>{
    'userId': instance.userId,
    'username': instance.username,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('displayName', instance.displayName);
  val['novelCount'] = instance.novelCount;
  val['lastCreatedAt'] = instance.lastCreatedAt.toIso8601String();
  return val;
}
