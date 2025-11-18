import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service/repositories/setting_generation_repository.dart';
import '../../utils/logger.dart';
import '../../models/admin/review_models.dart';
import 'widgets/create_custom_strategy_dialog.dart';

/// 我的策略管理页面
class CustomStrategyManagementScreen extends StatefulWidget {
  const CustomStrategyManagementScreen({super.key});

  @override
  State<CustomStrategyManagementScreen> createState() => _CustomStrategyManagementScreenState();
}

class _CustomStrategyManagementScreenState extends State<CustomStrategyManagementScreen> {
  static const String _tag = 'CustomStrategyManagementScreen';
  
  late final SettingGenerationRepository _repository;
  
  List<Map<String, dynamic>> _strategies = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SettingGenerationRepository>();
    _loadStrategies();
  }

  Future<void> _loadStrategies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final strategies = await _repository.getUserStrategies();
      setState(() {
        _strategies = strategies;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error(_tag, '加载策略失败', e);
      setState(() {
        _errorMessage = '加载策略失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createStrategy() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateCustomStrategyDialog(),
    );

    if (result == true) {
      _loadStrategies();
    }
  }

  Future<void> _editStrategy(Map<String, dynamic> strategy) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CreateCustomStrategyDialog(strategy: strategy),
    );

    if (result == true) {
      _loadStrategies();
    }
  }

  Future<void> _deleteStrategy(Map<String, dynamic> strategy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除策略'),
        content: Text('确定要删除策略"${strategy['name']}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repository.deleteStrategy(strategyId: strategy['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('策略已删除')),
          );
        }
        _loadStrategies();
      } catch (e) {
        AppLogger.error(_tag, '删除策略失败', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  /// 分享策略对话框
  Future<void> _showShareDialog(Map<String, dynamic> strategy) async {
    final isPublic = strategy['isPublic'] as bool? ?? false;
    final reviewStatus = strategy['reviewStatus'] as String? ?? 'DRAFT';
    
    await showDialog(
      context: context,
      builder: (context) => _ShareStrategyDialog(
        strategy: strategy,
        isPublic: isPublic,
        reviewStatus: reviewStatus,
        onSubmitReview: () async {
          Navigator.of(context).pop();
          await _submitForReview(strategy);
        },
      ),
    );
  }
  
  /// 提交审核
  Future<void> _submitForReview(Map<String, dynamic> strategy) async {
    try {
      await _repository.submitStrategyForReview(strategyId: strategy['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 已提交审核，审核通过后将在策略市场公开分享'),
            backgroundColor: Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadStrategies();
    } catch (e) {
      AppLogger.error(_tag, '提交审核失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 提交失败: $e'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的策略'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStrategies,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createStrategy,
        icon: const Icon(Icons.add),
        label: const Text('创建策略'),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStrategies,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_strategies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有创建任何策略',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角的 "+" 按钮创建您的第一个策略',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _strategies.length,
      itemBuilder: (context, index) {
        return _buildStrategyCard(theme, _strategies[index]);
      },
    );
  }

  Widget _buildStrategyCard(ThemeData theme, Map<String, dynamic> strategy) {
    final name = strategy['name'] as String? ?? '未命名';
    final description = strategy['description'] as String? ?? '';
    final isPublic = strategy['isPublic'] as bool? ?? false;
    final hidePrompts = strategy['hidePrompts'] as bool? ?? false;
    final likeCount = strategy['likeCount'] as int? ?? 0;
    final favoriteCount = strategy['favoriteCount'] as int? ?? 0;
    final usageCount = strategy['usageCount'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hidePrompts)
                  Tooltip(
                    message: '提示词已隐藏',
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                const SizedBox(width: 8),
                if (isPublic)
                  Chip(
                    label: const Text('公开', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.green.withOpacity(0.1),
                    side: BorderSide(color: Colors.green.withOpacity(0.3)),
                  )
                else
                  Chip(
                    label: const Text('私密', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.orange.withOpacity(0.1),
                    side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                  ),
              ],
            ),
            
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                _buildStat(theme, Icons.favorite_border, likeCount.toString()),
                const SizedBox(width: 16),
                _buildStat(theme, Icons.bookmark_border, favoriteCount.toString()),
                const SizedBox(width: 16),
                _buildStat(theme, Icons.play_circle_outline, usageCount.toString()),
                
                const Spacer(),
                
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editStrategy(strategy),
                  tooltip: '编辑',
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  onPressed: () => _showShareDialog(strategy),
                  tooltip: '分享设置',
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteStrategy(strategy),
                  tooltip: '删除',
                  iconSize: 20,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(ThemeData theme, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 分享策略对话框
class _ShareStrategyDialog extends StatelessWidget {
  final Map<String, dynamic> strategy;
  final bool isPublic;
  final String reviewStatus;
  final VoidCallback onSubmitReview;

  const _ShareStrategyDialog({
    required this.strategy,
    required this.isPublic,
    required this.reviewStatus,
    required this.onSubmitReview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final usageCount = strategy['usageCount'] as int? ?? 0;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头部
              _buildHeader(theme, isDark),
              
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 策略名称
                    Text(
                      strategy['name'] as String? ?? '未命名',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 状态卡片
                    _buildStatusCard(theme, isDark),
                    
                    const SizedBox(height: 16),
                    
                    // 积分提示
                    if (isPublic) ...[
                      _buildPointsTip(theme, isDark, usageCount),
                      const SizedBox(height: 16),
                    ],
                    
                    // 说明文字
                    _buildDescription(theme, isDark),
                    
                    const SizedBox(height: 20),
                    
                    // 按钮
                    _buildButtons(context, theme, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
              : [const Color(0xFF5856D6), const Color(0xFF4947CC)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.share_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '分享设置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusDescription;

    switch (reviewStatus) {
      case ReviewStatusConstants.draft:
        statusColor = const Color(0xFF8E8E93);
        statusIcon = Icons.edit_note_rounded;
        statusText = '草稿';
        statusDescription = '策略尚未提交审核';
        break;
      case ReviewStatusConstants.pending:
        statusColor = const Color(0xFFFF9500);
        statusIcon = Icons.hourglass_empty_rounded;
        statusText = '待审核';
        statusDescription = '策略正在审核中，请耐心等待';
        break;
      case ReviewStatusConstants.approved:
        statusColor = const Color(0xFF34C759);
        statusIcon = Icons.check_circle_rounded;
        statusText = '已通过';
        statusDescription = '策略已在市场公开分享';
        break;
      case ReviewStatusConstants.rejected:
        statusColor = const Color(0xFFFF3B30);
        statusIcon = Icons.cancel_rounded;
        statusText = '未通过';
        statusDescription = '策略审核未通过，请修改后重新提交';
        break;
      default:
        statusColor = const Color(0xFF8E8E93);
        statusIcon = Icons.help_outline_rounded;
        statusText = '未知';
        statusDescription = '未知状态';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            size: 28,
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsTip(ThemeData theme, bool isDark, int usageCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9500).withOpacity(0.1),
            const Color(0xFFFF6B00).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF9500).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.stars_rounded,
              size: 20,
              color: Color(0xFFFF9500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已获得积分奖励',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '您的策略已被使用 $usageCount 次，获得 $usageCount 积分',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ThemeData theme, bool isDark) {
    String description;
    
    if (reviewStatus == 'DRAFT') {
      description = '💡 提交审核后，您的策略将在审核通过后公开分享到策略市场。\n\n'
                   '✨ 每次其他用户使用您的策略，您都会获得 1 积分奖励！';
    } else if (reviewStatus == 'PENDING') {
      description = '⏳ 您的策略正在审核中，审核通过后将自动公开到策略市场。\n\n'
                   '通常审核会在 1-3 个工作日内完成。';
    } else if (reviewStatus == 'APPROVED') {
      description = '🎉 恭喜！您的策略已成功分享到策略市场。\n\n'
                   '✨ 每次有用户使用您的策略，您都会自动获得 1 积分奖励！';
    } else {
      description = '❌ 您的策略审核未通过。\n\n'
                   '请根据审核意见修改策略后重新提交。';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme, bool isDark) {
    if (reviewStatus == 'DRAFT' || reviewStatus == 'REJECTED') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onSubmitReview,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            '提交审核',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            '关闭',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
        ),
      );
    }
  }
}
