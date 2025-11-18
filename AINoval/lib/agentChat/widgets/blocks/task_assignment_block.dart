/// 任务分配块组件
/// Task assignment block widget

import 'package:flutter/material.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../config/constants.dart';
import '../../utils/responsive_utils.dart';
import '../../i18n/translations.dart';

/// 任务分配块Widget
/// Task assignment block widget
/// 
/// 主管智能体的任务分析和分配，支持并行/串行模式
/// Supervisor agent's task analysis and assignment with parallel/sequential modes
class TaskAssignmentBlockWidget extends StatelessWidget {
  final TaskAssignmentBlock block;
  final bool isDark;
  final Translations translations;
  
  const TaskAssignmentBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    final baseColor = AgentChatThemeConfig.getColor(
      AgentChatThemeConfig.lightPrimary,
      AgentChatThemeConfig.darkPrimary,
      isDark,
    );
    final hslColor = HSLColor.fromColor(baseColor);
    final supervisorColor = hslColor.withLightness(0.5).toColor();
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing2,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            supervisorColor.withOpacity(0.1),
            supervisorColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
        border: Border.all(
          color: supervisorColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          _buildHeader(context, supervisorColor, isCompact),
          
          // 分析文本
          _buildAnalysis(context, isCompact),
          
          // 任务分配列表
          _buildAssignments(context, supervisorColor, isCompact),
        ],
      ),
    );
  }
  
  /// 构建头部
  Widget _buildHeader(BuildContext context, Color color, bool isCompact) {
    return Container(
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ResponsiveUtils.getBorderRadius(context) - 2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_rounded,
            size: isCompact ? 20 : 24,
            color: color,
          ),
          SizedBox(width: AgentChatThemeConfig.spacing2),
          Expanded(
            child: Text(
              translations.taskAssignment,
              style: TextStyle(
                fontSize: isCompact ? 14 : 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          // 模式标签
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AgentChatThemeConfig.spacing2,
              vertical: AgentChatThemeConfig.spacing,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(
                ResponsiveUtils.getBorderRadius(context) * 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  block.mode == TaskAssignmentMode.parallel
                      ? Icons.call_split
                      : Icons.list,
                  size: 12,
                  color: color,
                ),
                SizedBox(width: 4),
                Text(
                  block.mode == TaskAssignmentMode.parallel
                      ? translations.parallelMode
                      : translations.sequentialMode,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    fontWeight: FontWeight.w600,
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
  
  /// 构建分析文本
  Widget _buildAnalysis(BuildContext context, bool isCompact) {
    return Padding(
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      child: Text(
        block.analysis,
        style: TextStyle(
          fontSize: isCompact ? 13 : 14,
          height: 1.5,
          color: AgentChatThemeConfig.getColor(
            AgentChatThemeConfig.lightCardForeground,
            AgentChatThemeConfig.darkCardForeground,
            isDark,
          ),
        ),
      ),
    );
  }
  
  /// 构建任务分配列表
  Widget _buildAssignments(BuildContext context, Color color, bool isCompact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        0,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      child: Column(
        children: block.assignments.asMap().entries.map((entry) {
          final index = entry.key;
          final assignment = entry.value;
          final isLast = index == block.assignments.length - 1;
          return _buildAssignmentItem(
            context,
            assignment,
            index + 1,
            color,
            isLast,
            isCompact,
          );
        }).toList(),
      ),
    );
  }
  
  /// 构建单个任务分配项
  Widget _buildAssignmentItem(
    BuildContext context,
    TaskAssignment assignment,
    int number,
    Color color,
    bool isLast,
    bool isCompact,
  ) {
    return Container(
      margin: EdgeInsets.only(
        bottom: isLast ? 0 : AgentChatThemeConfig.spacing2,
      ),
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing2 : AgentChatThemeConfig.spacing3,
      ),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightCard,
          AgentChatThemeConfig.darkCard,
          isDark,
        ),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context) * 0.5,
        ),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号
          Container(
            width: isCompact ? 24 : 28,
            height: isCompact ? 24 : 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: isCompact ? 12 : 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          
          SizedBox(width: AgentChatThemeConfig.spacing2),
          
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 智能体名称
                Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: isCompact ? 14 : 16,
                      color: color,
                    ),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        assignment.agentName,
                        style: TextStyle(
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: AgentChatThemeConfig.spacing),
                
                // 任务描述
                Text(
                  assignment.task,
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    height: 1.4,
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightCardForeground,
                      AgentChatThemeConfig.darkCardForeground,
                      isDark,
                    ),
                  ),
                ),
                
                SizedBox(height: AgentChatThemeConfig.spacing),
                
                // 分配原因
                Container(
                  padding: EdgeInsets.all(AgentChatThemeConfig.spacing),
                  decoration: BoxDecoration(
                    color: AgentChatThemeConfig.getColor(
                      AgentChatThemeConfig.lightMuted,
                      AgentChatThemeConfig.darkMuted,
                      isDark,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: AgentChatThemeConfig.getColor(
                          AgentChatThemeConfig.lightMutedForeground,
                          AgentChatThemeConfig.darkMutedForeground,
                          isDark,
                        ),
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          assignment.reason,
                          style: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            height: 1.3,
                            color: AgentChatThemeConfig.getColor(
                              AgentChatThemeConfig.lightMutedForeground,
                              AgentChatThemeConfig.darkMutedForeground,
                              isDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




