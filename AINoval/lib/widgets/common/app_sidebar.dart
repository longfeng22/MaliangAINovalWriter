import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';

class AppSidebar extends StatefulWidget {
  final bool isExpanded;
  final Function(bool)? onExpandedChanged;
  final Function(String)? onNavigate; // 添加导航回调
  final String? currentRoute; // 可选的当前路由高亮
  final bool isAuthed; // 是否已登录
  final VoidCallback? onRequireAuth; // 触发登录

  const AppSidebar({
    Key? key,
    this.isExpanded = true,
    this.onExpandedChanged,
    this.onNavigate,
    this.currentRoute,
    this.isAuthed = true,
    this.onRequireAuth,
  }) : super(key: key);

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _widthAnimation = Tween<double>(
      begin: 60,
      end: 240,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
      widget.onExpandedChanged?.call(_isExpanded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        return Container(
          width: _widthAnimation.value,
          height: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? WebTheme.darkGrey100 : WebTheme.grey50,
            border: Border(
              right: BorderSide(
                color: WebTheme.getBorderColor(context),
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: WebTheme.getBorderColor(context),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.menu_book,
                      size: 24,
                      color: WebTheme.getPrimaryColor(context),
                    ),
                    if (_isExpanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AI小说创作',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WebTheme.getTextColor(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Navigation Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _buildNavItem(
                      context,
                      icon: Icons.home,
                      label: '首页',
                      isSelected: widget.currentRoute == 'home',
                      onTap: () => widget.onNavigate?.call('home'),
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.settings_applications,
                      label: '我的设定',
                      isSelected: widget.currentRoute == 'settings',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('settings');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.book,
                      label: '我的小说',
                      isSelected: widget.currentRoute == 'novels',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('novels');
                      },
                    ),
                    // 提示词市场入口
                    _buildNavItem(
                      context,
                      icon: Icons.storefront,
                      label: '提示词市场',
                      isSelected: widget.currentRoute == 'prompt_market',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('prompt_market');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.auto_awesome,
                      label: '提示词与预设',
                      isSelected: widget.currentRoute == 'unified_management',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('unified_management');
                      },
                    ),

                    // 知识库分组
                    if (_isExpanded) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          '知识库',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ),
                    ],
                    
                    _buildNavItem(
                      context,
                      icon: Icons.menu_book_outlined,
                      label: 'AI拆书',
                      isSelected: widget.currentRoute == 'fanqie_search',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('fanqie_search');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.public,
                      label: '公共知识库',
                      isSelected: widget.currentRoute == 'public_knowledge_bases',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('public_knowledge_bases');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.folder,
                      label: '我的知识库',
                      isSelected: widget.currentRoute == 'my_knowledge_bases',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('my_knowledge_bases');
                      },
                    ),

                    // _buildNavItem(
                    //   context,
                    //   icon: Icons.edit,
                    //   label: '创作中心',
                    //   onTap: () {
                    //     if (!widget.isAuthed) {
                    //       widget.onRequireAuth?.call();
                    //       return;
                    //     }
                    //   },
                    // ),
                    // _buildNavItem(
                    //   context,
                    //   icon: Icons.auto_awesome,
                    //   label: 'AI助手',
                    //   onTap: () {
                    //     if (!widget.isAuthed) {
                    //       widget.onRequireAuth?.call();
                    //       return;
                    //     }
                    //   },
                    // ),
                    // _buildNavItem(
                    //   context,
                    //   icon: Icons.group,
                    //   label: '社区',
                    //   onTap: () {
                    //     if (!widget.isAuthed) {
                    //       widget.onRequireAuth?.call();
                    //       return;
                    //     }
                    //   },
                    // ),
                    _buildNavItem(
                      context,
                      icon: Icons.analytics,
                      label: '数据分析',
                      isSelected: widget.currentRoute == 'analytics',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('analytics');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.workspace_premium,
                      label: '我的订阅',
                      isSelected: widget.currentRoute == 'my_subscription',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('my_subscription');
                      },
                    ),
                    const Divider(height: 32),
                    _buildNavItem(
                      context,
                      icon: Icons.settings,
                      label: '设置',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                        widget.onNavigate?.call('account_settings');
                      },
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.help_outline,
                      label: '帮助',
                      onTap: () {
                        if (!widget.isAuthed) {
                          widget.onRequireAuth?.call();
                          return;
                        }
                      },
                    ),
                  ],
                ),
              ),
              // Toggle Button
              Container(
                height: 48,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: WebTheme.getBorderColor(context),
                      width: 1,
                    ),
                  ),
                ),
                child: InkWell(
                  onTap: _toggleSidebar,
                  child: Center(
                    child: Icon(
                      _isExpanded ? Icons.chevron_left : Icons.chevron_right,
                      size: 20,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final isDark = WebTheme.isDarkMode(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isExpanded ? 16 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isSelected
                ? (isDark ? WebTheme.darkGrey200 : WebTheme.grey200)
                : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                    ? WebTheme.getPrimaryColor(context)
                    : WebTheme.getSecondaryTextColor(context),
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected
                          ? WebTheme.getTextColor(context)
                          : WebTheme.getSecondaryTextColor(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 游客模式在展开时显示小提示“需登录”
                  // 访客提示徽标已移除，保持简洁
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}