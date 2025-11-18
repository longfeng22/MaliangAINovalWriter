/// 对话标签栏组件
/// Conversation tabs component

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../config/theme_config.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';
import 'time_travel.dart';

/// 对话标签栏Widget
class ConversationTabs extends StatelessWidget {
  final List<Conversation> conversations;
  final String activeId;
  final Function(String id) onTabClick;
  final Function(String id) onTabClose;
  final VoidCallback onNewChat;
  final List<Snapshot> snapshots;
  final String currentSnapshotId;
  final Function(String snapshotId) onRestore;
  final VoidCallback? onOpenAgentManager;
  final Translations translations;
  
  const ConversationTabs({
    super.key,
    required this.conversations,
    required this.activeId,
    required this.onTabClick,
    required this.onTabClose,
    required this.onNewChat,
    required this.snapshots,
    required this.currentSnapshotId,
    required this.onRestore,
    this.onOpenAgentManager,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Container(
      height: isCompact ? 48 : 56,
      padding: EdgeInsets.symmetric(horizontal: ResponsiveUtils.getSpacing(context)),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.lightBackground.toColor().withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: AgentChatThemeConfig.lightBorder.toColor()),
        ),
      ),
      child: Row(
        children: [
          // 对话标签列表
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: conversations.length,
              separatorBuilder: (context, index) => SizedBox(width: AgentChatThemeConfig.spacing2),
              itemBuilder: (context, index) {
                final conv = conversations[index];
                final isActive = conv.id == activeId;
                
                return GestureDetector(
                  onTap: () => onTabClick(conv.id),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? AgentChatThemeConfig.spacing2 : AgentChatThemeConfig.spacing3,
                      vertical: AgentChatThemeConfig.spacing,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AgentChatThemeConfig.lightAccent.toColor()
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        ResponsiveUtils.getBorderRadius(context) * 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          conv.title,
                          style: TextStyle(
                            fontSize: isCompact ? 12 : 13,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (conversations.length > 1) ...[
                          SizedBox(width: AgentChatThemeConfig.spacing),
                          GestureDetector(
                            onTap: () => onTabClose(conv.id),
                            child: Icon(Icons.close, size: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // 操作按钮
          Row(
            children: [
              if (snapshots.length > 1)
                TimeTravel(
                  snapshots: snapshots,
                  currentSnapshotId: currentSnapshotId,
                  onRestore: onRestore,
                  translations: translations,
                ),
              SizedBox(width: AgentChatThemeConfig.spacing),
              if (onOpenAgentManager != null)
                IconButton(
                  icon: Icon(Icons.settings, size: isCompact ? 18 : 20),
                  tooltip: translations.agentManagement,
                  onPressed: onOpenAgentManager,
                ),
              SizedBox(width: AgentChatThemeConfig.spacing),
              IconButton(
                icon: Icon(Icons.add, size: isCompact ? 18 : 20),
                tooltip: translations.newChat,
                onPressed: onNewChat,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
