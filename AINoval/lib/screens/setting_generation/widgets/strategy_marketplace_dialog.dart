import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service/repositories/setting_generation_repository.dart';
import '../../../utils/logger.dart';
import '../../../widgets/common/top_toast.dart';
import 'strategy_marketplace_card.dart';
import 'create_custom_strategy_dialog.dart';
import 'strategy_detail_dialog.dart';

/// 策略市场对话框（窗口模式）
/// 现代化的对话框设计，自适应屏幕大小
class StrategyMarketplaceDialog extends StatefulWidget {
  const StrategyMarketplaceDialog({super.key});

  @override
  State<StrategyMarketplaceDialog> createState() => _StrategyMarketplaceDialogState();
}

class _StrategyMarketplaceDialogState extends State<StrategyMarketplaceDialog> with SingleTickerProviderStateMixin {
  static const String _tag = 'StrategyMarketplaceDialog';
  
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
          strategies.sort((a, b) => (b['likeCount'] as int? ?? 0).compareTo(a['likeCount'] as int? ?? 0));
          break;
        case 1: // 最新策略
          strategies = await _repository.getPublicStrategies();
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

  // 🆕 复制策略为我的策略 - 弹出编辑对话框
  Future<void> _copyStrategy(Map<String, dynamic> strategy) async {
    try {
      // 如果策略隐藏了提示词或提示词为空，需要先获取完整数据
      Map<String, dynamic> fullStrategy = strategy;
      final hidePrompts = strategy['hidePrompts'] as bool? ?? false;
      final hasEmptyPrompts = (strategy['systemPrompt'] == null || 
                               strategy['systemPrompt'] == '') ||
                              (strategy['userPrompt'] == null || 
                               strategy['userPrompt'] == '');
      
      if (hidePrompts || hasEmptyPrompts) {
        AppLogger.info(_tag, '策略提示词为空或隐藏，尝试获取完整策略数据');
        final detail = await _repository.getStrategyDetail(strategyId: strategy['id']);
        if (detail != null) {
          fullStrategy = detail;
          AppLogger.info(_tag, '成功获取完整策略数据: systemPrompt length=${detail['systemPrompt']?.length ?? 0}');
        } else {
          // 如果无法获取详情（可能是隐私保护），提示用户
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Text(
                      '该策略已设置隐私保护，无法复制提示词内容',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFFFF9500), // iOS橙色
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }
      }
      
      // 准备复制的策略数据，添加"(副本)"后缀，并移除ID（标记为新策略）
      final copiedStrategy = Map<String, dynamic>.from(fullStrategy);
      copiedStrategy['name'] = '${fullStrategy['name']} (副本)';
      copiedStrategy.remove('id'); // 移除ID，表示这是一个新策略
      
      // 弹出编辑对话框让用户编辑
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CreateCustomStrategyDialog(strategy: copiedStrategy),
      );
      
      // 如果用户保存了，刷新列表并切换到"我的"标签页
      if (result == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                const Text(
                  '策略已复制到"我的策略"',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF34C759), // iOS绿色
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
          );
        }
        
        // 切换到"我的"标签页并刷新
        _tabController.animateTo(2);
        await _loadStrategies();
      }
    } catch (e) {
      AppLogger.error(_tag, '复制策略失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '复制失败: $e',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFFF3B30), // iOS红色
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    // 自适应对话框大小
    final dialogWidth = screenSize.width < 600 ? screenSize.width * 0.95 : 
                       screenSize.width < 1200 ? screenSize.width * 0.8 : 
                       screenSize.width * 0.7;
    final dialogHeight = screenSize.height * 0.85;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14), // iOS风格圆角
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.5 : 0.15),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // iOS风格图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFFFF9500), const Color(0xFFFF6B00)]
                  : [const Color(0xFFFF9F0A), const Color(0xFFFF7A00)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFFFF9500) : const Color(0xFFFF9F0A)).withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.store_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '策略市场',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '发现并使用社区分享的优质策略',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          // iOS风格关闭按钮
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.close,
                size: 18,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
        indicatorWeight: 2,
        labelColor: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
        unselectedLabelColor: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: -0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          letterSpacing: -0.2,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.local_fire_department_rounded, size: 20), text: '热门'),
          Tab(icon: Icon(Icons.new_releases_rounded, size: 20), text: '最新'),
          Tab(icon: Icon(Icons.person_rounded, size: 20), text: '我的'),
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

    return Column(
      children: [
        // 💡 积分奖励提示横幅
        if (_tabController.index != 2) // 不在"我的"标签页时显示
          _buildPointsBanner(theme),
        
        // 工具栏 - iOS风格
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            border: Border(
              bottom: BorderSide(
                color: theme.brightness == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${_strategies.length} 个策略',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_tabController.index == 2) // 我的策略时显示创建按钮
                GestureDetector(
                  onTap: _createStrategy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: (theme.brightness == Brightness.dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          '创建策略',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        // 策略列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadStrategies,
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                mainAxisExtent: 300,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
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
                  // 🆕 点击卡片查看详情
                  onTap: () => _showStrategyDetail(_strategies[index]),
                  // 🆕 我的策略管理功能
                  onEdit: isMyStrategy ? () => _editStrategy(_strategies[index]) : null,
                  onDelete: isMyStrategy ? () => _deleteStrategy(_strategies[index]) : null,
                  onShare: isMyStrategy ? () => _shareStrategy(_strategies[index]) : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 积分奖励提示横幅
  Widget _buildPointsBanner(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9500).withOpacity(isDark ? 0.2 : 0.15),
            const Color(0xFFFF6B00).withOpacity(isDark ? 0.15 : 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9500).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9500).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 图标
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9500).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.stars_rounded,
              size: 22,
              color: Color(0xFFFF9500),
            ),
          ),
          const SizedBox(width: 14),
          // 文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💰 积分奖励计划',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF9500),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '每次他人使用你的模版，你获得一积分哦',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFFE5E5E7) : const Color(0xFF1C1C1E),
                    letterSpacing: -0.1,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          // 箭头
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: const Color(0xFFFF9500),
            ),
          ),
        ],
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
        subtitle = '点击右上角的 "创建策略" 按钮';
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
      _loadStrategies();
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
      _loadStrategies();
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
    Navigator.of(context).pop(strategy);
  }

  // 🆕 显示策略详情
  Future<void> _showStrategyDetail(Map<String, dynamic> strategy) async {
    await showDialog(
      context: context,
      builder: (context) => StrategyDetailDialog(
        strategyId: strategy['id'],
        strategyName: strategy['name'] ?? '未命名策略',
      ),
    );
  }
}

