/// 智能体卡片组件
/// Agent card widget

import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../config/theme_config.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 智能体卡片Widget
/// Agent card widget
/// 
/// 显示智能体信息、工具数量、编辑/删除按钮、活动状态
/// Display agent info, tool count, edit/delete buttons, active state
class AgentCard extends StatefulWidget {
  final Agent agent;
  final bool isActive;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDark;
  final Translations translations;
  
  const AgentCard({
    super.key,
    required this.agent,
    this.isActive = false,
    this.onSelect,
    this.onEdit,
    this.onDelete,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(
            isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AgentChatThemeConfig.getColor(
                    AgentChatThemeConfig.lightPrimary,
                    AgentChatThemeConfig.darkPrimary,
                    widget.isDark,
                  ).withOpacity(0.1)
                : _isHovered
                    ? AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightMuted,
                        AgentChatThemeConfig.darkMuted,
                        widget.isDark,
                      )
                    : AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightCard,
                        AgentChatThemeConfig.darkCard,
                        widget.isDark,
                      ),
            borderRadius: BorderRadius.circular(
              ResponsiveUtils.getBorderRadius(context),
            ),
            border: Border.all(
              color: widget.isActive
                  ? AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightPrimary,
                      AgentChatThemeConfig.darkPrimary,
                      widget.isDark,
                    )
                  : AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightBorder,
                      AgentChatThemeConfig.darkBorder,
                      widget.isDark,
                    ),
              width: widget.isActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部
              Row(
                children: [
                  // 图标
                  Container(
                    padding: EdgeInsets.all(isCompact ? 8 : 10),
                    decoration: BoxDecoration(
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightPrimary,
                        AgentChatThemeConfig.darkPrimary,
                        widget.isDark,
                      ).withOpacity(widget.isActive ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(
                        ResponsiveUtils.getBorderRadius(context) * 0.5,
                      ),
                    ),
                    child: Icon(
                      Icons.smart_toy,
                      size: isCompact ? 20 : 24,
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightPrimary,
                        AgentChatThemeConfig.darkPrimary,
                        widget.isDark,
                      ),
                    ),
                  ),
                  
                  SizedBox(width: AgentChatThemeConfig.spacing2),
                  
                  // 名称和活动状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.agent.name,
                          style: TextStyle(
                            fontSize: isCompact ? 15 : 16,
                            fontWeight: FontWeight.w600,
                            color: AgentChatThemeConfig.getColor(
                              AgentChatThemeConfig.lightForeground,
                              AgentChatThemeConfig.darkForeground,
                              widget.isDark,
                            ),
                          ),
                        ),
                        if (widget.isActive) ...[
                          SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: AgentChatThemeConfig.getColor(
                                  AgentChatThemeConfig.lightPrimary,
                                  AgentChatThemeConfig.darkPrimary,
                                  widget.isDark,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                widget.translations.currentAgent,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AgentChatThemeConfig.getColor(
                                    AgentChatThemeConfig.lightPrimary,
                                    AgentChatThemeConfig.darkPrimary,
                                    widget.isDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // 操作按钮（悬停显示）
                  if (_isHovered && !isCompact) ...[
                    if (widget.onEdit != null)
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18),
                        onPressed: widget.onEdit,
                        tooltip: widget.translations.editAgent,
                        padding: EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    if (widget.onDelete != null)
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18),
                        onPressed: widget.onDelete,
                        tooltip: widget.translations.deleteAgent,
                        padding: EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ],
              ),
              
              // 描述
              if (widget.agent.description != null && 
                  widget.agent.description!.isNotEmpty) ...[
                SizedBox(height: AgentChatThemeConfig.spacing2),
                Text(
                  widget.agent.description!,
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    height: 1.4,
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightMutedForeground,
                      AgentChatThemeConfig.darkMutedForeground,
                      widget.isDark,
                    ),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              // 工具信息
              if (widget.agent.totalTools > 0) ...[
                SizedBox(height: AgentChatThemeConfig.spacing2),
                Wrap(
                  spacing: AgentChatThemeConfig.spacing,
                  runSpacing: AgentChatThemeConfig.spacing,
                  children: [
                    if (widget.agent.hasBuiltInTools)
                      _ToolChip(
                        icon: Icons.build_outlined,
                        label: widget.translations.builtInTools,
                        count: widget.agent.builtInTools.length,
                        isDark: widget.isDark,
                        isCompact: isCompact,
                      ),
                    if (widget.agent.hasMCPTools)
                      _ToolChip(
                        icon: Icons.extension_outlined,
                        label: widget.translations.mcpTools,
                        count: widget.agent.mcpTools.length,
                        isDark: widget.isDark,
                        isCompact: isCompact,
                      ),
                  ],
                ),
              ] else ...[
                SizedBox(height: AgentChatThemeConfig.spacing2),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightMuted,
                      AgentChatThemeConfig.darkMuted,
                      widget.isDark,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.translations.chatAgentDesc,
                    style: TextStyle(
                      fontSize: 11,
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightMutedForeground,
                        AgentChatThemeConfig.darkMutedForeground,
                        widget.isDark,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 工具芯片Widget
class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool isDark;
  final bool isCompact;
  
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.isDark,
    required this.isCompact,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightAccent,
          AgentChatThemeConfig.darkAccent,
          isDark,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isCompact ? 12 : 14,
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightAccentForeground,
              AgentChatThemeConfig.darkAccentForeground,
              isDark,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: isCompact ? 10 : 11,
              fontWeight: FontWeight.w500,
              color: AgentChatThemeConfig.getColor(
                AgentChatThemeConfig.lightAccentForeground,
                AgentChatThemeConfig.darkAccentForeground,
                isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}





