/// 时间旅行组件
/// Time travel component

import 'package:flutter/material.dart';
import '../models/snapshot.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 时间旅行Widget
class TimeTravel extends StatelessWidget {
  final List<Snapshot> snapshots;
  final String currentSnapshotId;
  final Function(String snapshotId) onRestore;
  final Translations translations;
  
  const TimeTravel({
    super.key,
    required this.snapshots,
    required this.currentSnapshotId,
    required this.onRestore,
    required this.translations,
  });
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.history, size: 20),
      tooltip: translations.timeTravel,
      onPressed: () => _showTimeTravelDialog(context),
    );
  }
  
  void _showTimeTravelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.all(AgentChatThemeConfig.spacing3),
                  itemCount: snapshots.length,
                  itemBuilder: (context, index) => _buildSnapshotItem(context, snapshots[index], index),
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AgentChatThemeConfig.spacing4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AgentChatThemeConfig.lightBorder.toColor()),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history, color: AgentChatThemeConfig.lightPrimary.toColor()),
          SizedBox(width: AgentChatThemeConfig.spacing2),
          Expanded(
            child: Text(
              translations.timeTravel,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSnapshotItem(BuildContext context, Snapshot snapshot, int index) {
    final isCurrent = snapshot.id == currentSnapshotId;
    final date = DateTime.fromMillisecondsSinceEpoch(snapshot.timestamp);
    final timeStr = '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    
    return Container(
      margin: EdgeInsets.only(bottom: AgentChatThemeConfig.spacing3),
      padding: EdgeInsets.all(AgentChatThemeConfig.spacing3),
      decoration: BoxDecoration(
        color: isCurrent
            ? AgentChatThemeConfig.lightPrimary.toColor().withOpacity(0.05)
            : AgentChatThemeConfig.lightCard.toColor(),
        border: Border.all(
          color: isCurrent
              ? AgentChatThemeConfig.lightPrimary.toColor()
              : AgentChatThemeConfig.lightBorder.toColor(),
        ),
        borderRadius: BorderRadius.circular(ResponsiveUtils.getBorderRadius(context)),
      ),
      child: Row(
        children: [
          // 状态指示器
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCurrent
                  ? AgentChatThemeConfig.lightPrimary.toColor()
                  : AgentChatThemeConfig.lightMuted.toColor(),
              shape: BoxShape.circle,
            ),
            child: isCurrent
                ? Icon(Icons.chevron_right, size: 16, color: Colors.white)
                : Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AgentChatThemeConfig.lightForeground.toColor().withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          SizedBox(width: AgentChatThemeConfig.spacing3),
          
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildTypeBadge(snapshot.type),
                    SizedBox(width: AgentChatThemeConfig.spacing2),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AgentChatThemeConfig.lightMutedForeground.toColor(),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AgentChatThemeConfig.spacing),
                Text(
                  snapshot.label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (snapshot.description != null) ...[
                  SizedBox(height: AgentChatThemeConfig.spacing / 2),
                  Text(
                    snapshot.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AgentChatThemeConfig.lightMutedForeground.toColor(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // 回退按钮
          if (!isCurrent)
            ElevatedButton.icon(
              onPressed: () {
                onRestore(snapshot.id);
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.restore, size: 16),
              label: Text(translations.restore, style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgentChatThemeConfig.lightPrimary.toColor().withOpacity(0.1),
                foregroundColor: AgentChatThemeConfig.lightPrimary.toColor(),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildTypeBadge(String type) {
    Color color;
    String label;
    
    if (type == SnapshotType.message) {
      color = Colors.blue;
      label = '消息';
    } else if (type == SnapshotType.tool) {
      color = Colors.green;
      label = '工具';
    } else if (type == SnapshotType.approval) {
      color = Colors.amber;
      label = '批准';
    } else if (type == SnapshotType.system) {
      color = Colors.purple;
      label = '系统';
    } else {
      color = Colors.grey;
      label = '未知';
    }
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AgentChatThemeConfig.spacing,
        vertical: AgentChatThemeConfig.spacing / 2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
  
  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AgentChatThemeConfig.spacing4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AgentChatThemeConfig.lightBorder.toColor()),
        ),
      ),
      child: Text(
        '💡 ${translations.timeTravelHint}',
        style: TextStyle(
          fontSize: 12,
          color: AgentChatThemeConfig.lightMutedForeground.toColor(),
        ),
      ),
    );
  }
}
