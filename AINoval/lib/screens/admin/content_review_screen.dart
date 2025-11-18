/// 内容审核管理页面
/// 统一审核策略、增强提示词等多种类型的内容

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/admin/review_models.dart';
import '../../services/api_service/repositories/admin/review_repository.dart';
import '../../utils/logger.dart';
import 'widgets/review_item_card.dart';
import 'widgets/review_detail_dialog.dart';

class ContentReviewScreen extends StatefulWidget {
  const ContentReviewScreen({super.key});

  @override
  State<ContentReviewScreen> createState() => _ContentReviewScreenState();
}

class _ContentReviewScreenState extends State<ContentReviewScreen> {
  static const String _tag = 'ContentReviewScreen';

  // 筛选条件
  ReviewItemType? _selectedType;
  ReviewStatus? _selectedStatus = ReviewStatus.pending; // 默认显示待审核
  String? _selectedFeatureType; // AI功能类型筛选
  final TextEditingController _keywordController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  // 排序和分页
  String _sortBy = 'submittedAt';
  String _sortDir = 'desc';
  int _page = 0;
  int _size = 20;

  // 数据
  List<ReviewItem> _items = [];
  int _totalElements = 0;
  int _totalPages = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // 统计数据
  Map<String, dynamic> _statistics = {};

  // 批量选择
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadStatistics();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<ReviewRepository>();
      final result = await repository.getReviewItems(
        type: _selectedType,
        status: _selectedStatus,
        featureType: _selectedFeatureType,
        keyword: _keywordController.text.isEmpty ? null : _keywordController.text,
        startDate: _startDate,
        endDate: _endDate,
        page: _page,
        size: _size,
        sortBy: _sortBy,
        sortDir: _sortDir,
      );

      setState(() {
        _items = result['items'] as List<ReviewItem>;
        _totalElements = result['totalElements'] as int;
        _totalPages = result['totalPages'] as int;
        _isLoading = false;
      });

      _selectedIds.clear();
    } catch (e) {
      AppLogger.error(_tag, '加载审核数据失败', e);
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final repository = context.read<ReviewRepository>();
      final stats = await repository.getReviewStatistics(
        type: _selectedType,
        startDate: _startDate,
        endDate: _endDate,
      );
      setState(() {
        _statistics = stats;
      });
    } catch (e) {
      AppLogger.error(_tag, '加载统计数据失败', e);
    }
  }

  Future<void> _showReviewDialog(ReviewItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ReviewDetailDialog(item: item),
    );

    if (result == true) {
      _loadData();
      _loadStatistics();
    }
  }

  Future<void> _batchReview(String decision) async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一项')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(decision == 'APPROVE' ? '批量通过' : '批量拒绝'),
        content: Text('确定要${decision == 'APPROVE' ? '通过' : '拒绝'}选中的 ${_selectedIds.length} 项吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: decision == 'APPROVE' ? Colors.green : Colors.red,
            ),
            child: Text(decision == 'APPROVE' ? '通过' : '拒绝'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repository = context.read<ReviewRepository>();
      await repository.batchReview(
        itemIds: _selectedIds.toList(),
        type: _selectedType ?? ReviewItemType.userContent,
        decision: ReviewDecision(decision: decision),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批量${decision == 'APPROVE' ? '通过' : '拒绝'}成功'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadData();
      _loadStatistics();
    } catch (e) {
      AppLogger.error(_tag, '批量审核失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批量审核失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0B) : const Color(0xFFF8FAFC),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 页面标题和统计
                _buildHeader(theme, isDark),
                const SizedBox(height: 24),

                // 筛选工具栏
                _buildToolbar(theme, isDark),
                const SizedBox(height: 24),

                // 批量操作栏
                if (_selectedIds.isNotEmpty) _buildBatchActions(theme, isDark),
                if (_selectedIds.isNotEmpty) const SizedBox(height: 16),

                // 审核项列表
                Expanded(
                  child: _buildContent(theme, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    final pendingCount = _statistics['totalPending'] ?? 0;
    final approvedCount = _statistics['totalApproved'] ?? 0;
    final rejectedCount = _statistics['totalRejected'] ?? 0;

    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.fact_check_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '内容审核',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '统一管理策略、增强提示词等内容的审核',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // 统计卡片
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  theme, isDark,
                  icon: Icons.pending_actions,
                  label: '待审核',
                  value: pendingCount.toString(),
                  color: const Color(0xFFFF9500),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  theme, isDark,
                  icon: Icons.check_circle,
                  label: '已通过',
                  value: approvedCount.toString(),
                  color: const Color(0xFF34C759),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  theme, isDark,
                  icon: Icons.cancel,
                  label: '已拒绝',
                  value: rejectedCount.toString(),
                  color: const Color(0xFFFF3B30),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  theme, isDark,
                  icon: Icons.article,
                  label: '总计',
                  value: _totalElements.toString(),
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, bool isDark, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
      ),
      child: Column(
        children: [
          // 第一行：类型、状态、功能类型筛选
          Row(
            children: [
              // 类型筛选
              Expanded(
                child: _buildDropdown(
                  value: _selectedType?.value,
                  hint: '全部类型',
                  icon: Icons.category_rounded,
                  items: [
                    {'value': null, 'label': '全部类型'},
                    ...ReviewItemType.values.map((t) => {
                      'value': t.value,
                      'label': t.displayName,
                    }),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedType = v == null ? null : ReviewItemType.fromValue(v);
                      _page = 0;
                    });
                    _loadData();
                    _loadStatistics();
                  },
                  theme: theme,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 16),
              
              // 状态筛选
              Expanded(
                child: _buildDropdown(
                  value: _selectedStatus?.value,
                  hint: '全部状态',
                  icon: Icons.filter_list_rounded,
                  items: [
                    {'value': null, 'label': '全部状态'},
                    ...ReviewStatus.values.map((s) => {
                      'value': s.value,
                      'label': '${s.emoji} ${s.displayName}',
                    }),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedStatus = v == null ? null : ReviewStatus.fromValue(v);
                      _page = 0;
                    });
                    _loadData();
                  },
                  theme: theme,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 16),
              
              // AI功能类型筛选
              Expanded(
                child: _buildDropdown(
                  value: _selectedFeatureType,
                  hint: '全部功能',
                  icon: Icons.functions_rounded,
                  items: [
                    {'value': null, 'label': '全部功能'},
                    {'value': 'SETTING_TREE_GENERATION', 'label': '📚 设定生成'},
                    {'value': 'REWRITE', 'label': '✏️ 重写'},
                    {'value': 'EXPANSION', 'label': '📝 扩写'},
                    {'value': 'SUMMARIZE', 'label': '📋 总结'},
                    {'value': 'CHAT', 'label': '💬 对话'},
                    {'value': 'CONTINUE_WRITING', 'label': '✍️ 续写'},
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedFeatureType = v;
                      _page = 0;
                    });
                    _loadData();
                  },
                  theme: theme,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 16),
              
              // 关键词搜索
              Expanded(
                flex: 3,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
                    ),
                  ),
                  child: TextField(
                    controller: _keywordController,
                    decoration: InputDecoration(
                      hintText: '搜索标题、描述或作者...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        size: 20,
                      ),
                      suffixIcon: _keywordController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              size: 18,
                            ),
                            onPressed: () {
                              _keywordController.clear();
                              _page = 0;
                              _loadData();
                            },
                          )
                        : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) {
                      _page = 0;
                      _loadData();
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // 查询按钮
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _page = 0;
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.search_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            '查询',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 第二行：排序和刷新
          Row(
            children: [
              Icon(
                Icons.sort_rounded,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '排序：',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              
              _buildDropdown(
                value: _sortBy,
                hint: '排序字段',
                items: const [
                  {'value': 'submittedAt', 'label': '提交时间'},
                  {'value': 'createdAt', 'label': '创建时间'},
                  {'value': 'reviewedAt', 'label': '审核时间'},
                ],
                onChanged: (v) {
                  setState(() { _sortBy = v ?? 'submittedAt'; });
                  _loadData();
                },
                theme: theme,
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              
              _buildDropdown(
                value: _sortDir,
                hint: '排序方向',
                items: const [
                  {'value': 'desc', 'label': '↓ 降序'},
                  {'value': 'asc', 'label': '↑ 升序'},
                ],
                onChanged: (v) {
                  setState(() { _sortDir = v ?? 'desc'; });
                  _loadData();
                },
                theme: theme,
                isDark: isDark,
              ),
              const Spacer(),
              
              // 刷新按钮
              _buildActionButton(
                theme: theme,
                isDark: isDark,
                icon: Icons.refresh_rounded,
                label: '刷新',
                onTap: () {
                  _page = 0;
                  _loadData();
                  _loadStatistics();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActions(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_box_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            '已选择 ${_selectedIds.length} 项',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          
          ElevatedButton.icon(
            onPressed: () => _batchReview('APPROVE'),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('批量通过'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34C759),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          
          ElevatedButton.icon(
            onPressed: () => _batchReview('REJECT'),
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('批量拒绝'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          
          TextButton.icon(
            onPressed: () => setState(() => _selectedIds.clear()),
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('清空选择'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage!, 
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无审核项',
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 审核项列表
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final isSelected = _selectedIds.contains(item.id);
              
              return ReviewItemCard(
                item: item,
                isSelected: isSelected,
                onTap: () => _showReviewDialog(item),
                onSelectChanged: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedIds.add(item.id);
                    } else {
                      _selectedIds.remove(item.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 分页器
        _buildPaginator(theme, isDark),
      ],
    );
  }

  Widget _buildPaginator(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 统计信息
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '共 $_totalElements 条记录',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '第 ${_page + 1} 页，共 $_totalPages 页',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          // 分页控件
          Row(
            children: [
              // 每页大小
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF374151) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _size,
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('10/页')),
                      DropdownMenuItem(value: 20, child: Text('20/页')),
                      DropdownMenuItem(value: 50, child: Text('50/页')),
                      DropdownMenuItem(value: 100, child: Text('100/页')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _size = v ?? 20;
                        _page = 0;
                      });
                      _loadData();
                    },
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 8,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // 上一页
              _buildPaginationButton(
                context: context,
                icon: Icons.chevron_left_rounded,
                tooltip: '上一页',
                onTap: _page > 0 ? () {
                  setState(() { _page = _page - 1; });
                  _loadData();
                } : null,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              
              // 页码
              Container(
                width: 80,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Center(
                  child: Text(
                    '${_page + 1}',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // 下一页
              _buildPaginationButton(
                context: context,
                icon: Icons.chevron_right_rounded,
                tooltip: '下一页',
                onTap: (_page + 1) < _totalPages ? () {
                  setState(() { _page = _page + 1; });
                  _loadData();
                } : null,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    IconData? icon,
    required List<Map<String, dynamic>> items,
    required void Function(String?) onChanged,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                const SizedBox(width: 6),
              ],
              Text(
                hint,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item['value'] as String?,
              child: Text(
                item['label'] as String,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
          dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 8,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    final isEnabled = onTap != null;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isEnabled
          ? (isDark ? const Color(0xFF374151) : const Color(0xFFF8FAFC))
          : (isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnabled
            ? (isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0))
            : (isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: isEnabled
                ? (isDark ? Colors.white70 : const Color(0xFF64748B))
                : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ),
    );
  }
}

