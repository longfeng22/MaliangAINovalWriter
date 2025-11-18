import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service/repositories/setting_generation_repository.dart';
import '../../utils/logger.dart';
import '../../widgets/common/top_toast.dart';
import 'widgets/strategy_marketplace_card.dart';
import 'widgets/create_custom_strategy_dialog.dart';

/// 策略市场页面
/// 社区驱动的策略分享和发现中心
class StrategyMarketplaceScreen extends StatefulWidget {
  const StrategyMarketplaceScreen({super.key});

  @override
  State<StrategyMarketplaceScreen> createState() => _StrategyMarketplaceScreenState();
}

class _StrategyMarketplaceScreenState extends State<StrategyMarketplaceScreen> with SingleTickerProviderStateMixin {
  static const String _tag = 'StrategyMarketplaceScreen';
  
  late final SettingGenerationRepository _repository;
  
  late TabController _tabController;
  List<Map<String, dynamic>> _strategies = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SettingGenerationRepository>();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadStrategies();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _loadStrategies();
    }
  }

  Future<void> _loadStrategies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      List<Map<String, dynamic>> strategies;
      
      switch (_tabController.index) {
        case 0: // 热门策略
          strategies = await _repository.getPublicStrategies();
          // 按点赞数排序
          strategies.sort((a, b) => (b['likeCount'] as int? ?? 0).compareTo(a['likeCount'] as int? ?? 0));
          break;
        case 1: // 最新策略
          strategies = await _repository.getPublicStrategies();
          // 按创建时间排序
          strategies.sort((a, b) {
            // createdAt 已经被 parseResponseListTimestamps 转换为 DateTime
            final aTime = a['createdAt'] is DateTime 
              ? a['createdAt'] as DateTime 
              : (a['createdAt'] is String ? DateTime.tryParse(a['createdAt']) : null);
            final bTime = b['createdAt'] is DateTime 
              ? b['createdAt'] as DateTime 
              : (b['createdAt'] is String ? DateTime.tryParse(b['createdAt']) : null);
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
          break;
        case 2: // 我的策略
          strategies = await _repository.getUserStrategies();
          break;
        default:
          strategies = [];
      }
      
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

  /// 编辑策略
  Future<void> _editStrategy(Map<String, dynamic> strategy) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CreateCustomStrategyDialog(strategy: strategy),
    );

    if (result == true) {
      _loadStrategies();
    }
  }

  /// 删除策略
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
          TopToast.success(context, '策略已删除');
        }
        _loadStrategies();
      } catch (e) {
        AppLogger.error(_tag, '删除策略失败', e);
        if (mounted) {
          TopToast.error(context, '删除失败: $e');
        }
      }
    }
  }

  /// 分享策略 - 提交审核
  Future<void> _shareStrategy(Map<String, dynamic> strategy) async {
    try {
      await _repository.submitStrategyForReview(strategyId: strategy['id']);
      if (mounted) {
        TopToast.success(context, '已提交审核，审核通过后将在策略市场公开分享');
      }
      // 刷新列表以更新状态，显示"审核中"标签
      _loadStrategies();
    } catch (e) {
      AppLogger.error(_tag, '提交审核失败', e);
      if (mounted) {
        TopToast.error(context, '提交失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Column(
          children: [
            _buildHeader(theme),
            _buildTabBar(theme),
            Expanded(
              child: _buildBody(theme),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createStrategy,
        icon: const Icon(Icons.add),
        label: const Text('创建策略'),
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.1),
            theme.colorScheme.secondary.withOpacity(0.1),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '策略市场',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '发现并使用社区分享的优质设定生成策略',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 统计卡片
          Row(
            children: [
              _buildStatCard(theme, Icons.public, '公开策略', _strategies.length.toString()),
              const SizedBox(width: 12),
              _buildStatCard(theme, Icons.people, '社区贡献者', '126'),
              const SizedBox(width: 12),
              _buildStatCard(theme, Icons.favorite, '累计点赞', '2.4K'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: theme.colorScheme.primary,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        tabs: const [
          Tab(icon: Icon(Icons.whatshot), text: '热门'),
          Tab(icon: Icon(Icons.new_releases), text: '最新'),
          Tab(icon: Icon(Icons.person), text: '我的'),
        ],
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
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: _loadStrategies,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisExtent: 280,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _strategies.length,
              itemBuilder: (context, index) {
                final isMyStrategy = _tabController.index == 2;
                final hidePrompts = _strategies[index]['hidePrompts'] as bool? ?? false;
                
                return StrategyMarketplaceCard(
                  strategy: _strategies[index],
                  isMyStrategy: isMyStrategy,
                  onLike: isMyStrategy ? null : () => _handleLike(_strategies[index]),
                  onFavorite: isMyStrategy ? null : () => _handleFavorite(_strategies[index]),
                  onUse: () => _handleUse(_strategies[index]),
                  // 🔒 只有公开策略 且 未隐藏提示词 才显示复制按钮
                  onCopy: (isMyStrategy || hidePrompts) ? null : () => _copyStrategy(_strategies[index]),
                  // 🆕 我的策略管理功能
                  onEdit: isMyStrategy ? () => _editStrategy(_strategies[index]) : null,
                  onDelete: isMyStrategy ? () => _deleteStrategy(_strategies[index]) : null,
                  onShare: isMyStrategy ? () => _shareStrategy(_strategies[index]) : null,
                );
              },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    String title, subtitle;
    IconData icon;
    
    switch (_tabController.index) {
      case 0:
        icon = Icons.public_off;
        title = '暂无热门策略';
        subtitle = '快来创建第一个策略吧！';
        break;
      case 1:
        icon = Icons.new_releases_outlined;
        title = '暂无最新策略';
        subtitle = '快来创建第一个策略吧！';
        break;
      case 2:
        icon = Icons.create_new_folder_outlined;
        title = '还没有创建任何策略';
        subtitle = '点击右下角的 "+" 按钮创建您的第一个策略';
        break;
      default:
        icon = Icons.sentiment_neutral;
        title = '暂无内容';
        subtitle = '';
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLike(Map<String, dynamic> strategy) async {
    try {
      await _repository.likeStrategy(strategyId: strategy['id']);
      _loadStrategies(); // 刷新列表
    } catch (e) {
      AppLogger.error(_tag, '点赞失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _handleFavorite(Map<String, dynamic> strategy) async {
    try {
      await _repository.favoriteStrategy(strategyId: strategy['id']);
      _loadStrategies(); // 刷新列表
    } catch (e) {
      AppLogger.error(_tag, '收藏失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _handleUse(Map<String, dynamic> strategy) {
    // 返回选中的策略给调用页面
    Navigator.of(context).pop(strategy);
  }
  
  // 🆕 复制策略为我的策略
  Future<void> _copyStrategy(Map<String, dynamic> strategy) async {
    try {
      // 创建一个复制的策略
      await _repository.createCustomStrategy(
        name: '${strategy['name']} (副本)',
        description: strategy['description'] ?? '',
        systemPrompt: strategy['systemPrompt'] ?? '',
        userPrompt: strategy['userPrompt'] ?? '',
        nodeTemplates: (strategy['nodeTemplates'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        expectedRootNodes: strategy['expectedRootNodes'] as int? ?? 8,
        maxDepth: strategy['maxDepth'] as int? ?? 3,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('策略已复制到"我的策略"')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // 切换到"我的"标签页
      _tabController.animateTo(2);
    } catch (e) {
      AppLogger.error(_tag, '复制策略失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('复制失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

