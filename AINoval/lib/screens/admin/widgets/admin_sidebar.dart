import 'package:flutter/material.dart';

import '../../../utils/web_theme.dart';
import '../../../widgets/common/permission_guard.dart';
import '../../../services/permission_service.dart';

class AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          right: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  size: 48,
                  color: WebTheme.getTextColor(context),
                ),
                const SizedBox(height: 12),
                Text(
                  'AI小说助手',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '管理后台',
                  style: TextStyle(
                    fontSize: 14,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Divider(
            color: WebTheme.getBorderColor(context),
            height: 1,
          ),
          // 菜单项
          Expanded(
            child: ListView(
              children: [
                PermissionGuard.permission(
                  PermissionService.STATISTICS_VIEW,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.dashboard,
                    title: '仪表板',
                    index: 0,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.STATISTICS_VIEW,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.visibility,
                    title: 'LLM可观测性',
                    index: 1,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.USER_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.people,
                    title: '用户管理',
                    index: 2,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.USER_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.security,
                    title: '角色管理',
                    index: 3,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.SUBSCRIPTION_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.subscriptions,
                    title: '订阅管理',
                    index: 4,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.MODEL_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.cloud,
                    title: '公共模型',
                    index: 5,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.PRESET_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.smart_button,
                    title: '系统预设',
                    index: 6,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.TEMPLATE_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.article,
                    title: '公共模板',
                    index: 7,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.SYSTEM_CONFIG,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.settings,
                    title: '系统配置',
                    index: 8,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.TEMPLATE_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.auto_awesome,
                    title: '增强模板',
                    index: 9,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.SYSTEM_CONFIG,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.receipt_long,
                    title: '计费审计',
                    index: 10,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.MODEL_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.attach_money,
                    title: '模型定价',
                    index: 11,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.STATISTICS_VIEW,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.auto_stories,
                    title: 'AI拆书任务',
                    index: 12,
                  ),
                ),
                PermissionGuard.permission(
                  PermissionService.TEMPLATE_MANAGEMENT,
                  child: _buildMenuItem(
                    context,
                    icon: Icons.fact_check_rounded,
                    title: '内容审核',
                    index: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int index,
  }) {
    final isSelected = selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? WebTheme.getTextColor(context)
              : WebTheme.getSecondaryTextColor(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? WebTheme.getTextColor(context)
                : WebTheme.getSecondaryTextColor(context),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedTileColor: WebTheme.getTextColor(context).withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: () => onItemSelected(index),
      ),
    );
  }
} 