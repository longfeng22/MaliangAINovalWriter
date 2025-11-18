/// 思考块组件
/// Thinking block widget

import 'package:flutter/material.dart';
import '../../models/message_block.dart';
import '../../config/theme_config.dart';
import '../../config/constants.dart';
import '../../utils/responsive_utils.dart';
import '../../utils/animation_utils.dart';
import '../../i18n/translations.dart';

/// 思考块Widget
/// Thinking block widget
/// 
/// 支持展开/折叠动画，三种步骤类型（plan/thought/observation）
/// Supports expand/collapse animation and three step types
class ThinkingBlockWidget extends StatelessWidget {
  final ThinkingBlock block;
  final bool isDark;
  final VoidCallback? onToggle;
  final Translations translations;
  
  const ThinkingBlockWidget({
    super.key,
    required this.block,
    this.isDark = false,
    this.onToggle,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    final thinkingColor = AgentChatThemeConfig.thinkingStateBg.toColor();
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: AgentChatThemeConfig.spacing2,
      ),
      decoration: BoxDecoration(
        color: thinkingColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
        border: Border.all(
          color: thinkingColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部（标题 + 展开/折叠按钮）
          _buildHeader(context, thinkingColor, isCompact),
          
          // 步骤列表（可展开/折叠）
          AnimationUtils.expandCollapse(
            isExpanded: block.isExpanded,
            child: _buildStepsList(context, isCompact),
          ),
        ],
      ),
    );
  }
  
  /// 构建头部
  Widget _buildHeader(BuildContext context, Color thinkingColor, bool isCompact) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ResponsiveUtils.getBorderRadius(context)),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        ),
        child: Row(
          children: [
            // 思考图标（脉冲动画）
            if (block.steps.any((s) => s.status == ThinkingStepStatus.thinking))
              AnimationUtils.pulsingWidget(
                child: Icon(
                  Icons.psychology,
                  size: isCompact ? 18 : 20,
                  color: thinkingColor,
                ),
              )
            else
              Icon(
                Icons.psychology,
                size: isCompact ? 18 : 20,
                color: thinkingColor,
              ),
            
            SizedBox(width: AgentChatThemeConfig.spacing2),
            
            // 标题
            Expanded(
              child: Text(
                translations.thinkingSteps(block.steps.length),
                style: TextStyle(
                  fontSize: isCompact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: thinkingColor,
                ),
              ),
            ),
            
            // 展开/折叠图标
            AnimationUtils.rotationTransition(
              rotated: block.isExpanded,
              turns: 0.5, // 180度
              child: Icon(
                Icons.keyboard_arrow_down,
                size: isCompact ? 20 : 24,
                color: thinkingColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建步骤列表
  Widget _buildStepsList(BuildContext context, bool isCompact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        0,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      child: Column(
        children: block.steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isLast = index == block.steps.length - 1;
          return _buildStepItem(context, step, isLast, isCompact);
        }).toList(),
      ),
    );
  }
  
  /// 构建单个步骤
  Widget _buildStepItem(
    BuildContext context,
    ThinkingStep step,
    bool isLast,
    bool isCompact,
  ) {
    final isThinking = step.status == ThinkingStepStatus.thinking;
    final stepColor = _getStepColor(step.type);
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : AgentChatThemeConfig.spacing3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤图标
          Container(
            margin: EdgeInsets.only(top: 2),
            child: isThinking
                ? AnimationUtils.pulsingWidget(
                    duration: const Duration(milliseconds: 1000),
                    child: _buildStepIcon(step.type, stepColor, isCompact),
                  )
                : _buildStepIcon(step.type, stepColor, isCompact),
          ),
          
          SizedBox(width: AgentChatThemeConfig.spacing2),
          
          // 步骤内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w500,
                          color: AgentChatThemeConfig.getColor(
                            AgentChatThemeConfig.lightForeground,
                            AgentChatThemeConfig.darkForeground,
                            isDark,
                          ),
                        ),
                      ),
                    ),
                    // 状态指示器
                    if (isThinking)
                      Container(
                        margin: EdgeInsets.only(left: AgentChatThemeConfig.spacing),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(stepColor),
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: EdgeInsets.only(left: AgentChatThemeConfig.spacing),
                        child: Icon(
                          Icons.check_circle,
                          size: 14,
                          color: stepColor,
                        ),
                      ),
                  ],
                ),
                
                // 详情（如果有）
                if (step.detail != null && step.detail!.isNotEmpty) ...[
                  SizedBox(height: AgentChatThemeConfig.spacing),
                  Text(
                    step.detail!,
                    style: TextStyle(
                      fontSize: isCompact ? 12 : 13,
                      color: AgentChatThemeConfig.getColor(
                        AgentChatThemeConfig.lightMutedForeground,
                        AgentChatThemeConfig.darkMutedForeground,
                        isDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建步骤图标
  Widget _buildStepIcon(String type, Color color, bool isCompact) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 4 : 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _getStepIconData(type),
        size: isCompact ? 14 : 16,
        color: color,
      ),
    );
  }
  
  /// 获取步骤类型颜色
  Color _getStepColor(String type) {
    switch (type) {
      case ThinkingStepType.plan:
        return AgentChatThemeConfig.toolViewColor.toColor();
      case ThinkingStepType.thought:
        return AgentChatThemeConfig.thinkingStateBg.toColor();
      case ThinkingStepType.observation:
        return AgentChatThemeConfig.citationOutline.toColor();
      default:
        return AgentChatThemeConfig.thinkingStateBg.toColor();
    }
  }
  
  /// 获取步骤类型图标
  IconData _getStepIconData(String type) {
    switch (type) {
      case ThinkingStepType.plan:
        return Icons.lightbulb_outline;
      case ThinkingStepType.thought:
        return Icons.psychology_outlined;
      case ThinkingStepType.observation:
        return Icons.visibility_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}





