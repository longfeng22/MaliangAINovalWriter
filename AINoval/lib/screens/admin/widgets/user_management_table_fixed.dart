import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../models/admin/admin_models.dart';
import '../../../blocs/admin/admin_bloc.dart';
import 'credit_operation_dialog.dart';
import 'user_edit_dialog.dart';

class UserManagementTable extends StatelessWidget {
  final List<AdminUser> users;

  const UserManagementTable({
    super.key,
    required this.users,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark 
                ? Colors.white.withOpacity(0.05) 
                : theme.colorScheme.primary.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark 
                    ? Colors.white.withOpacity(0.1) 
                    : theme.colorScheme.primary.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.table_chart_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '用户数据表',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '当前显示 ${users.length} 条用户记录',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // 快捷操作
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF374151) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        ),
                        onPressed: () => context.read<AdminBloc>().add(LoadUsers()),
                        tooltip: '刷新数据',
                        visualDensity: VisualDensity.compact,
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.download_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        ),
                        onPressed: () {
                          // TODO: 实现导出功能
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('导出功能开发中...')),
                          );
                        },
                        tooltip: '导出数据',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 数据表格 - 使用自适应布局
          Expanded(
            child: users.isNotEmpty 
              ? _buildDataTable(context, theme, isDark)
              : _buildEmptyState(context, theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFBFCFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: theme.copyWith(
                  dataTableTheme: DataTableThemeData(
                    headingRowColor: MaterialStateProperty.all(
                      isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    ),
                    dataRowColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.hovered)) {
                        return isDark 
                          ? Colors.white.withOpacity(0.05)
                          : theme.colorScheme.primary.withOpacity(0.03);
                      }
                      return Colors.transparent;
                    }),
                    headingTextStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF374151),
                      letterSpacing: 0.5,
                    ),
                    dataTextStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                    dividerThickness: 0.5,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 100,
                  ),
                  child: DataTable(
                    columnSpacing: 24,
                    dataRowMinHeight: 60,
                    dataRowMaxHeight: 80,
                    headingRowHeight: 60,
                    border: TableBorder.all(
                      color: Colors.transparent,
                      width: 0,
                    ),
                    columns: _buildColumns(isDark),
                    rows: users.map((user) => DataRow(
                      cells: [
                        DataCell(_buildUserCell(context, user)),
                        DataCell(SelectableText(
                          user.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                        DataCell(_buildStatusChip(context, user.accountStatus)),
                        DataCell(_buildCreditsCell(context, theme, user)),
                        DataCell(_buildRolesCell(context, user)),
                        DataCell(Text(
                          user.createdAt.toString().substring(0, 10),
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                        DataCell(_buildActionButtons(context, user)),
                      ],
                    )).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFBFCFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : const Color(0xFF64748B)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无用户数据',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前筛选条件下没有找到用户记录',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.8),
                    theme.colorScheme.primary,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.read<AdminBloc>().add(LoadUsers()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '刷新数据',
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
      ),
    );
  }

  List<DataColumn> _buildColumns(bool isDark) {
    return [
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('用户名'),
            ],
          ),
        ),
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.email_outlined,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('邮箱'),
            ],
          ),
        ),
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.traffic_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('状态'),
            ],
          ),
        ),
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('积分'),
            ],
          ),
        ),
        numeric: true,
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('角色'),
            ],
          ),
        ),
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('创建时间'),
            ],
          ),
        ),
      ),
      DataColumn(
        label: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.settings_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              const Text('操作'),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildUserCell(BuildContext context, AdminUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          user.username,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        if (user.displayName != null && user.displayName!.isNotEmpty)
          Text(
            user.displayName!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
            ),
          ),
      ],
    );
  }

  Widget _buildCreditsCell(BuildContext context, ThemeData theme, AdminUser user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.15),
            theme.colorScheme.primary.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            _formatCredits(user.credits),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolesCell(BuildContext context, AdminUser user) {
    return SizedBox(
      width: 100,
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: user.roles.take(2).map((role) => Chip(
          label: Text(
            role,
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        )).toList(),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    Color backgroundColor;
    Color textColor;
    Color borderColor;
    IconData icon;
    String label;

    switch (status) {
      case 'ACTIVE':
        backgroundColor = const Color(0xFF10B981).withOpacity(0.1);
        textColor = const Color(0xFF059669);
        borderColor = const Color(0xFF10B981).withOpacity(0.2);
        icon = Icons.check_circle_rounded;
        label = '活跃';
        break;
      case 'SUSPENDED':
        backgroundColor = const Color(0xFFF59E0B).withOpacity(0.1);
        textColor = const Color(0xFFD97706);
        borderColor = const Color(0xFFF59E0B).withOpacity(0.2);
        icon = Icons.pause_circle_rounded;
        label = '暂停';
        break;
      case 'DISABLED':
        backgroundColor = const Color(0xFFEF4444).withOpacity(0.1);
        textColor = const Color(0xFFDC2626);
        borderColor = const Color(0xFFEF4444).withOpacity(0.2);
        icon = Icons.cancel_rounded;
        label = '禁用';
        break;
      case 'PENDING_VERIFICATION':
        backgroundColor = const Color(0xFF3B82F6).withOpacity(0.1);
        textColor = const Color(0xFF2563EB);
        borderColor = const Color(0xFF3B82F6).withOpacity(0.2);
        icon = Icons.schedule_rounded;
        label = '待验证';
        break;
      default:
        backgroundColor = const Color(0xFF6B7280).withOpacity(0.1);
        textColor = const Color(0xFF4B5563);
        borderColor = const Color(0xFF6B7280).withOpacity(0.2);
        icon = Icons.help_rounded;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: textColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCredits(int credits) {
    if (credits >= 1000000) {
      return '${(credits / 1000000).toStringAsFixed(1)}M';
    } else if (credits >= 1000) {
      return '${(credits / 1000).toStringAsFixed(1)}K';
    } else {
      return credits.toString();
    }
  }

  Widget _buildActionButtons(BuildContext context, AdminUser user) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 编辑用户信息
        _buildActionButton(
          context: context,
          icon: Icons.edit_rounded,
          tooltip: '编辑用户信息',
          color: const Color(0xFF6366F1),
          isDark: isDark,
          onTap: () => _showEditUserDialog(context, user),
        ),
        const SizedBox(width: 6),
        // 添加积分
        _buildActionButton(
          context: context,
          icon: Icons.add_circle_rounded,
          tooltip: '添加积分',
          color: const Color(0xFF10B981),
          isDark: isDark,
          onTap: () => _showCreditDialog(context, user, true),
        ),
        const SizedBox(width: 6),
        // 扣减积分
        _buildActionButton(
          context: context,
          icon: Icons.remove_circle_rounded,
          tooltip: '扣减积分',
          color: const Color(0xFFEF4444),
          isDark: isDark,
          onTap: () => _showCreditDialog(context, user, false),
        ),
        const SizedBox(width: 6),
        // 更多操作
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
            ),
          ),
          child: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
            onSelected: (value) => _handleMenuAction(context, user, value),
            tooltip: '更多操作',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_status',
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    const Text('切换状态'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reset_password',
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_reset_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    const Text('重置密码'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'assign_role',
                child: Row(
                  children: [
                    Icon(
                      Icons.security_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    const Text('分配角色'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'view_details',
                child: Row(
                  children: [
                    Icon(
                      Icons.info_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    const Text('查看详情'),
                  ],
                ),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: isDark ? const Color(0xFF374151) : Colors.white,
            elevation: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Icon(
            icon,
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, AdminUser user) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => UserEditDialog(user: user),
    );

    if (result != null && context.mounted) {
      context.read<AdminBloc>().add(UpdateUserInfo(
        userId: user.id,
        email: result['email'],
        displayName: result['displayName'],
        accountStatus: result['accountStatus'],
      ));
    }
  }

  void _showCreditDialog(BuildContext context, AdminUser user, bool isAdd) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreditOperationDialog(user: user, isAdd: isAdd),
    );

    if (result != null && context.mounted) {
      final amount = result['amount'] as int;
      final reason = result['reason'] as String;
      
      if (isAdd) {
        context.read<AdminBloc>().add(AddCreditsToUser(
          userId: user.id,
          amount: amount,
          reason: reason,
        ));
      } else {
        context.read<AdminBloc>().add(DeductCreditsFromUser(
          userId: user.id,
          amount: amount,
          reason: reason,
        ));
      }

      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isAdd ? "添加" : "扣减"}积分操作已提交'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleMenuAction(BuildContext context, AdminUser user, String action) {
    switch (action) {
      case 'toggle_status':
        final newStatus = user.accountStatus == 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE';
        context.read<AdminBloc>().add(UpdateUserStatus(
          userId: user.id,
          status: newStatus,
        ));
        break;
      case 'reset_password':
        _showResetPasswordDialog(context, user);
        break;
      case 'assign_role':
        _showAssignRoleDialog(context, user);
        break;
      case 'view_details':
        _showUserDetailsDialog(context, user);
        break;
    }
  }

  void _showResetPasswordDialog(BuildContext context, AdminUser user) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ResetPasswordDialog(user: user),
    );

    if (result != null && context.mounted) {
      try {
        final useDefault = result['useDefault'] as bool? ?? false;
        final newPassword = result['newPassword'] as String?;
        
        context.read<AdminBloc>().add(ResetUserPassword(
          userId: user.id,
          newPassword: useDefault ? null : newPassword,
        ));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('正在重置 ${user.username} 的密码...'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('重置密码失败: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showAssignRoleDialog(BuildContext context, AdminUser user) {
    // TODO: 实现角色分配对话框
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('角色分配功能开发中...')),
    );
  }

  void _showUserDetailsDialog(BuildContext context, AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('用户详情 - ${user.username}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('用户ID', user.id),
              _buildDetailRow('用户名', user.username),
              _buildDetailRow('邮箱', user.email),
              _buildDetailRow('显示名称', user.displayName ?? '-'),
              _buildDetailRow('账户状态', user.accountStatus),
              _buildDetailRow('积分余额', user.credits.toString()),
              _buildDetailRow('角色', user.roles.join(', ')),
              _buildDetailRow('创建时间', user.createdAt.toString()),
              _buildDetailRow('更新时间', user.updatedAt?.toString() ?? '-'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
} 

class _ResetPasswordDialog extends StatefulWidget {
  final AdminUser user;

  const _ResetPasswordDialog({required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _useDefault = true;
  final TextEditingController _newPasswordController = TextEditingController();

  @override
  void dispose() {
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.lock_reset_rounded,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 8),
          const Text('重置密码'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 用户信息卡片
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.username,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'ID: ${widget.user.id}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // 密码选项
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text('使用默认密码'),
                  subtitle: Text(
                    '将使用系统默认密码：123456',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                  value: _useDefault,
                  onChanged: (v) => setState(() => _useDefault = v),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                ),
              ),
              
              const SizedBox(height: 16),
              if (!_useDefault) ...[
                Text(
                  '自定义密码',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '新密码',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    hintText: '请输入至少6位的新密码',
                    helperText: '密码长度至少6位',
                  ),
                  validator: (v) {
                    if (!_useDefault) {
                      if (v == null || v.trim().isEmpty) return '请输入新密码或选择使用默认密码';
                      if (v.trim().length < 6) return '密码长度至少6位';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: const Text('确认重置'),
        ),
      ],
    );
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop({
      'useDefault': _useDefault,
      'newPassword': _useDefault ? null : _newPasswordController.text.trim(),
    });
  }
}
