/// 管理后台仪表板
/// 包含所有管理功能的导航

import 'package:flutter/material.dart';
import '../../utils/web_theme.dart';
import 'widgets/admin_sidebar.dart';
import 'llm_observability_screen.dart';
import 'public_model_management_screen.dart';
import 'system_presets_management_screen.dart';
import 'public_templates_management_screen.dart';
import 'enhanced_templates_management_screen.dart';
import 'user_management_screen.dart';
import 'role_management_screen.dart';
import 'subscription_management_screen.dart';
import 'billing_audit_screen.dart';
import 'model_pricing_management_screen.dart';
import '../knowledge_base/knowledge_extraction_task_management_page.dart';
import 'content_review_screen.dart';
import 'package:get_it/get_it.dart';
import 'package:ainoval/services/api_service/repositories/impl/admin/llm_observability_repository_impl.dart';
import 'package:ainoval/widgets/analytics/analytics_card.dart';
import 'package:ainoval/widgets/analytics/model_usage_chart.dart';
import 'package:ainoval/widgets/analytics/user_activity_chart.dart';
import 'package:ainoval/models/analytics_data.dart';
import 'package:ainoval/models/admin/llm_observability_models.dart';
import 'package:ainoval/services/api_service/repositories/impl/admin_repository_impl.dart';
import 'package:ainoval/models/admin/admin_models.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const AdminOverviewScreen(), // 0: 仪表板
    const LLMObservabilityScreen(), // 1: LLM可观测性
    const UserManagementScreen(), // 2: 用户管理（替换占位页）
    const RoleManagementScreen(), // 3: 角色管理（替换占位页）
    const SubscriptionManagementScreen(), // 4: 订阅管理（替换占位页）
    const PublicModelManagementScreen(), // 5: 公共模型
    const SystemPresetsManagementScreen(), // 6: 系统预设
    const PublicTemplatesManagementScreen(), // 7: 公共模板
    const AdminSystemSettingsScreen(), // 8: 系统配置
    const EnhancedTemplatesManagementScreen(), // 9: 增强模板
    const BillingAuditScreen(), // 10: 计费审计
    const ModelPricingManagementScreen(), // 11: 模型定价管理
    const KnowledgeExtractionTaskManagementPage(), // 12: AI拆书任务管理
    const ContentReviewScreen(), // 13: 内容审核
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      body: Row(
        children: [
          AdminSidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: WebTheme.getBorderColor(context),
          ),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}

// AdminNavigationItem 类已移除，现在使用 AdminSidebar 统一管理导航

/// 管理后台概览页面
class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  late LLMObservabilityRepositoryImpl _repository;
  late AdminRepositoryImpl _adminRepository;
  bool _loading = true;
  String? _error;

  Map<String, dynamic> _overview = const {};
  List<ModelUsageData> _modelUsage = const [];
  AdminDashboardStats? _dashboardStats;

  @override
  void initState() {
    super.initState();
    _repository = GetIt.instance<LLMObservabilityRepositoryImpl>();
    _adminRepository = AdminRepositoryImpl();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.getOverviewStatistics(),
        _repository.getModelStatistics(),
        _adminRepository.getDashboardStats(),
      ]);

      final overview = results[0] as Map<String, dynamic>;
      final modelStats = results[1] as List<ModelStatistics>;
      final dashboardStats = results[2] as AdminDashboardStats;

      setState(() {
        _overview = overview;
        _modelUsage = _buildModelUsageFromStats(modelStats);
        _dashboardStats = dashboardStats;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<ModelUsageData> _buildModelUsageFromStats(List<ModelStatistics> stats) {
    if (stats.isEmpty) return const [];
    // 优先使用 Token 占比，没有则按调用次数占比
    int totalTokens = 0;
    for (final s in stats) {
      totalTokens += s.statistics.totalTokens;
    }

    final bool useTokens = totalTokens > 0;
    final int totalBase = useTokens
        ? totalTokens
        : stats.fold<int>(0, (acc, s) => acc + s.statistics.totalCalls);

    if (totalBase == 0) return const [];

    final List<ModelUsageData> result = [];
    const palette = ['#3B82F6', '#8B5CF6', '#10B981', '#F59E0B', '#EF4444', '#06B6D4'];
    for (int i = 0; i < stats.length; i++) {
      final s = stats[i];
      final int base = useTokens ? s.statistics.totalTokens : s.statistics.totalCalls;
      final int pct = ((base / totalBase) * 100).round();
      result.add(ModelUsageData(
        modelName: s.modelName,
        percentage: pct,
        totalTokens: useTokens ? base : s.statistics.totalTokens,
        color: palette[i % palette.length],
      ));
    }
    // 只取前8个，避免图例过长
    result.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    return result.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '管理后台仪表板',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _error != null
                ? Center(child: Text('加载失败: $_error'))
                : (_loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶部概览统计
                            _buildOverviewStatsRow(context),
                            const SizedBox(height: 16),
                            
                            // 用户相关统计
                            if (_dashboardStats != null) ...[
                              _buildUserStatsRow(context),
                              const SizedBox(height: 16),
                            ],
                            
                            // 用户活动趋势图表
                            if (_dashboardStats != null) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: AnalyticsCard(
                                      title: '用户活动趋势',
                                      value: '',
                                      child: UserActivityChart(
                                        loginData: _dashboardStats!.dailyLoginData,
                                        registrationData: _dashboardStats!.dailyRegistrationData,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: AnalyticsCard(
                                      title: '模型占比',
                                      value: '',
                                      child: ModelUsageChart(
                                        data: _modelUsage,
                                        viewMode: AnalyticsViewMode.daily,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              AnalyticsCard(
                                title: '模型占比',
                                value: '',
                                child: ModelUsageChart(
                                  data: _modelUsage,
                                  viewMode: AnalyticsViewMode.daily,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // 用户创作统计和活动列表
                            if (_dashboardStats != null) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildUserNovelStats(context),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildRecentActivities(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      )),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewStatsRow(BuildContext context) {
    final totalCalls = (_overview['totalCalls'] ?? 0).toString();
    final successfulCalls = (_overview['successfulCalls'] ?? 0).toString();
    final failedCalls = (_overview['failedCalls'] ?? 0).toString();
    final successRate = ((_overview['successRate'] ?? 0.0) as num).toDouble();

    return Row(
      children: [
        Expanded(
          child: AnalyticsOverviewCard(
            title: '总调用次数',
            value: totalCalls,
            icon: Icons.analytics,
            subtitle: '统计范围内的模型调用总数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '成功次数',
            value: successfulCalls,
            icon: Icons.check_circle,
            subtitle: '无错误完成的调用次数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '失败次数',
            value: failedCalls,
            icon: Icons.error_outline,
            subtitle: '发生错误的调用次数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '成功率',
            value: '${successRate.toStringAsFixed(1)}%',
            icon: Icons.percent,
            subtitle: '成功调用占比',
          ),
        ),
      ],
    );
  }

  Widget _buildUserStatsRow(BuildContext context) {
    if (_dashboardStats == null) return const SizedBox.shrink();
    
    return Row(
      children: [
        Expanded(
          child: AnalyticsOverviewCard(
            title: '总用户数',
            value: _dashboardStats!.totalUsers.toString(),
            icon: Icons.people,
            subtitle: '系统注册用户总数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '活跃用户',
            value: _dashboardStats!.activeUsers.toString(),
            icon: Icons.person_add,
            subtitle: '最近30天登录的用户',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '今日登录',
            value: _dashboardStats!.loginsToday.toString(),
            icon: Icons.login,
            subtitle: '今日登录用户数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '今日注册',
            value: _dashboardStats!.newUsersToday.toString(),
            icon: Icons.person_add_alt_1,
            subtitle: '今日新注册用户数',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnalyticsOverviewCard(
            title: '创作小说',
            value: _dashboardStats!.totalNovels.toString(),
            icon: Icons.book,
            subtitle: '用户创作的小说总数',
          ),
        ),
      ],
    );
  }

  Widget _buildUserNovelStats(BuildContext context) {
    if (_dashboardStats == null || _dashboardStats!.userNovelStats.isEmpty) {
      return Card(
        color: WebTheme.getCardColor(context),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              '暂无用户创作统计',
              style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
            ),
          ),
        ),
      );
    }

    return Card(
      color: WebTheme.getCardColor(context),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.leaderboard,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '用户创作排行榜（Top 10）',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._dashboardStats!.userNovelStats.asMap().entries.map((entry) {
              final index = entry.key;
              final stats = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WebTheme.getBackgroundColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: WebTheme.getBorderColor(context).withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _getRankColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                stats.displayName ?? stats.username,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: WebTheme.getTextColor(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ID: ${stats.userId}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: WebTheme.getSecondaryTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '最后创作: ${DateFormat('yyyy-MM-dd HH:mm').format(stats.lastCreatedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${stats.novelCount} 部',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivities(BuildContext context) {
    if (_dashboardStats == null || _dashboardStats!.recentActivities.isEmpty) {
      return Card(
        color: WebTheme.getCardColor(context),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              '暂无最近活动',
              style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
            ),
          ),
        ),
      );
    }

    return Card(
      color: WebTheme.getCardColor(context),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '最近活动',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._dashboardStats!.recentActivities.map((activity) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WebTheme.getBackgroundColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: WebTheme.getBorderColor(context).withOpacity(0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getActivityIcon(activity.action),
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          activity.action,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: WebTheme.getTextColor(context),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTimeAgo(activity.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          activity.userName,
                          style: TextStyle(
                            fontSize: 13,
                            color: WebTheme.getTextColor(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ID: ${activity.userId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activity.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFD700); // 金色
      case 1:
        return const Color(0xFFC0C0C0); // 银色
      case 2:
        return const Color(0xFFCD7F32); // 铜色
      default:
        return Colors.grey;
    }
  }

  IconData _getActivityIcon(String action) {
    switch (action) {
      case '用户注册':
        return Icons.person_add;
      case '小说创建':
        return Icons.book;
      case 'AI对话':
        return Icons.chat;
      default:
        return Icons.circle;
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}

class OverviewCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? count;

  const OverviewCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: WebTheme.getCardColor(context),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: WebTheme.getTextColor(context),
                ),
                const Spacer(),
                if (count != null)
                  Text(
                    count!,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 占位页面 - 用户管理
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '用户管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              '用户管理页面',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此功能正在开发中...',
              style: TextStyle(
                fontSize: 16,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 占位页面 - 角色管理
class AdminRolesScreen extends StatelessWidget {
  const AdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '角色管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.security_outlined,
              size: 64,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              '角色管理页面',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此功能正在开发中...',
              style: TextStyle(
                fontSize: 16,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 占位页面 - 订阅管理
class AdminSubscriptionScreen extends StatelessWidget {
  const AdminSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '订阅管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              '订阅管理页面',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此功能正在开发中...',
              style: TextStyle(
                fontSize: 16,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 占位页面 - 系统设置
class AdminSystemSettingsScreen extends StatefulWidget {
  const AdminSystemSettingsScreen({super.key});

  @override
  State<AdminSystemSettingsScreen> createState() => _AdminSystemSettingsScreenState();
}

class _AdminSystemSettingsScreenState extends State<AdminSystemSettingsScreen> {
  final _sinceTimeCtrl = TextEditingController();
  final _sinceHoursCtrl = TextEditingController();
  final _repo = AdminRepositoryImpl();
  bool _loading = false;
  String? _error;
  List<AdminSystemConfig> _configs = const [];

  static const String kSinceTime = 'BILLING_PROCESS_SINCE_TIME';
  static const String kSinceHours = 'BILLING_PROCESS_SINCE_HOURS';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _repo.getSystemConfigs();
      setState(() {
        _configs = list;
        _sinceTimeCtrl.text = _getValue(kSinceTime) ?? '';
        _sinceHoursCtrl.text = _getValue(kSinceHours) ?? '';
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String? _getValue(String key) {
    for (final c in _configs) {
      if (c.configKey == key) return c.configValue;
    }
    return null;
  }

  Future<void> _saveSinceTime() async {
    final v = _sinceTimeCtrl.text.trim();
    setState(() { _loading = true; _error = null; });
    try {
      await _repo.updateSystemConfig(kSinceTime, v);
      await _load();
      if (mounted) _showSnack('已保存开始时间');
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _clearSinceTime() async {
    _sinceTimeCtrl.clear();
    await _saveSinceTime();
  }

  Future<void> _saveSinceHours() async {
    final v = _sinceHoursCtrl.text.trim();
    if (v.isNotEmpty && int.tryParse(v) == null) {
      _showSnack('请输入有效的整数小时数');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _repo.updateSystemConfig(kSinceHours, v);
      await _load();
      if (mounted) _showSnack('已保存最近N小时');
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _clearSinceHours() async {
    _sinceHoursCtrl.clear();
    await _saveSinceHours();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text('系统配置', style: TextStyle(color: WebTheme.getTextColor(context))),
        elevation: 0,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('加载失败: $_error', style: TextStyle(color: Colors.red[300])),
                        ),
                      _buildBillingWindowCard(context),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBillingWindowCard(BuildContext context) {
    return Card(
      color: WebTheme.getCardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('计费处理窗口', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: WebTheme.getTextColor(context))),
            const SizedBox(height: 12),
            Text(
              '优先使用“开始时间(ISO-8601)”；否则使用“最近N小时”。两项都为空表示不限范围。',
              style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sinceTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: '开始时间(ISO-8601)',
                      hintText: '例如: 2025-09-17T00:00:00',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: _saveSinceTime, icon: const Icon(Icons.save), label: const Text('保存')),
                const SizedBox(width: 8),
                TextButton(onPressed: _clearSinceTime, child: const Text('清空')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _sinceHoursCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '最近N小时',
                      hintText: '整数，例如: 24',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: _saveSinceHours, icon: const Icon(Icons.save), label: const Text('保存')),
                const SizedBox(width: 8),
                TextButton(onPressed: _clearSinceHours, child: const Text('清空')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}