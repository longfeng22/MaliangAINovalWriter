import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/admin/admin_bloc.dart';
import '../../utils/web_theme.dart';
import 'widgets/user_management_table.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // 筛选/分页状态
  final TextEditingController _keywordController = TextEditingController();
  String? _status;
  String _sortBy = 'createdAt';
  String _sortDir = 'desc';
  int _page = 0;
  int _size = 20;

  @override
  void initState() {
    super.initState();
    // 加载用户数据
    _dispatchLoad();
  }

  void _dispatchLoad() {
    context.read<AdminBloc>().add(LoadUsers(
      page: _page,
      size: _size,
      search: _keywordController.text.isEmpty ? null : _keywordController.text,
      status: _status,
      sortBy: _sortBy,
      sortDir: _sortDir,
    ));
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
            // 页面标题
            Container(
              margin: const EdgeInsets.only(bottom: 32),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.people_rounded,
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
                          '用户管理',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '管理系统用户信息，支持筛选、排序和批量操作',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 筛选与工具栏
            _buildToolbar(context),
            const SizedBox(height: 24),
            // 内容区域
            Expanded(
              child: BlocBuilder<AdminBloc, AdminState>(
                builder: (context, state) {
                  if (state is AdminLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          WebTheme.getTextColor(context),
                        ),
                      ),
                    );
                  } else if (state is AdminError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '加载失败：${state.message}',
                            style: TextStyle(
                              color: WebTheme.getTextColor(context),
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.read<AdminBloc>().add(LoadUsers());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WebTheme.getTextColor(context),
                              foregroundColor: WebTheme.getBackgroundColor(context),
                            ),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  } else if (state is UsersPageLoaded) {
                    return Column(
                      children: [
                        Expanded(child: UserManagementTable(users: state.users)),
                        const SizedBox(height: 8),
                        _buildPaginator(context, state.page, state.size, state.totalElements, state.totalPages),
                      ],
                    );
                  } else {
                    // 初始状态或其他状态，显示空状态
                    return Center(
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
                            '暂无用户数据',
                            style: TextStyle(
                              color: WebTheme.getSecondaryTextColor(context),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.read<AdminBloc>().add(LoadUsers());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WebTheme.getTextColor(context),
                              foregroundColor: WebTheme.getBackgroundColor(context),
                            ),
                            child: const Text('加载用户'),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
        border: isDark 
          ? Border.all(color: Colors.white.withOpacity(0.1))
          : null,
      ),
      child: Column(
        children: [
          // 第一行：搜索和快捷筛选
          Row(
            children: [
              // 搜索框
              Expanded(
                flex: 2,
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
                      hintText: '搜索用户名、邮箱或手机号...',
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
                              _dispatchLoad();
                            },
                          )
                        : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) { _page = 0; _dispatchLoad(); },
                    onChanged: (_) => setState(() {}), // 为了显示/隐藏清除按钮
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 状态筛选
              _buildModernDropdown(
                value: _status,
                hint: '全部状态',
                icon: Icons.filter_list_rounded,
                items: const [
                  {'value': 'ACTIVE', 'label': '🟢 活跃'},
                  {'value': 'SUSPENDED', 'label': '🟡 暂停'},
                  {'value': 'DISABLED', 'label': '🔴 禁用'},
                  {'value': 'PENDING_VERIFICATION', 'label': '🔵 待验证'},
                ],
                onChanged: (v) {
                  setState(() { _status = v; _page = 0; });
                  _dispatchLoad();
                },
                context: context,
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
                    onTap: () { _page = 0; _dispatchLoad(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
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
          // 第二行：排序选项
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
              // 排序字段
              _buildModernDropdown(
                value: _sortBy,
                hint: '排序字段',
                items: const [
                  {'value': 'createdAt', 'label': '创建时间'},
                  {'value': 'updatedAt', 'label': '更新时间'},
                  {'value': 'lastLoginAt', 'label': '最后登录'},
                  {'value': 'credits', 'label': '积分'},
                  {'value': 'username', 'label': '用户名'},
                  {'value': 'email', 'label': '邮箱'},
                ],
                onChanged: (v) {
                  setState(() { _sortBy = v ?? 'createdAt'; });
                  _dispatchLoad();
                },
                context: context,
              ),
              const SizedBox(width: 12),
              // 排序方向
              _buildModernDropdown(
                value: _sortDir,
                hint: '排序方向',
                items: const [
                  {'value': 'desc', 'label': '↓ 降序'},
                  {'value': 'asc', 'label': '↑ 升序'},
                ],
                onChanged: (v) {
                  setState(() { _sortDir = v ?? 'desc'; });
                  _dispatchLoad();
                },
                context: context,
              ),
              const Spacer(),
              // 刷新按钮
              Container(
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
                    onTap: () { _page = 0; _dispatchLoad(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '刷新',
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernDropdown({
    required String? value,
    required String hint,
    IconData? icon,
    required List<Map<String, String>> items,
    required void Function(String?) onChanged,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
          items: [
            if (value != null)
              DropdownMenuItem(
                value: null,
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ...items.map((item) => DropdownMenuItem(
              value: item['value'],
              child: Text(
                item['label']!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            )),
          ],
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

  Widget _buildPaginator(BuildContext context, int page, int size, int totalElements, int totalPages) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
        border: isDark 
          ? Border.all(color: Colors.white.withOpacity(0.1))
          : null,
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
                  '共 $totalElements 条记录',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '第 ${page + 1} 页，共 $totalPages 页',
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
                      _dispatchLoad(); 
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
                onTap: page > 0 ? () { 
                  setState(() { _page = page - 1; }); 
                  _dispatchLoad(); 
                } : null,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              // 页码输入
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
                    '${page + 1}',
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
                onTap: (page + 1) < totalPages ? () { 
                  setState(() { _page = page + 1; }); 
                  _dispatchLoad(); 
                } : null,
                isDark: isDark,
              ),
            ],
          ),
        ],
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