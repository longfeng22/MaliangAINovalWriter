import 'package:flutter/material.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/models/admin/review_models.dart';

/// 分享模板对话框
/// 通用的分享对话框组件，复用策略市场的设计
class ShareTemplateDialog extends StatefulWidget {
  
  final String templateId;
  final String templateName;
  final String? description;
  final AIFeatureType featureType;
  final bool isPublic;
  final String? reviewStatus;
  final int? usageCount;
  final int? rewardPoints; // 引用奖励积分
  final bool? hidePrompts; // 是否隐藏提示词
  final bool hasSettingGenerationConfig; // 🆕 是否包含设定生成配置
  final Function(bool hidePrompts) onSubmitReview; // 修改为传递hidePrompts参数

  const ShareTemplateDialog({
    super.key,
    required this.templateId,
    required this.templateName,
    this.description,
    required this.featureType,
    required this.isPublic,
    this.reviewStatus,
    this.usageCount,
    this.rewardPoints,
    this.hidePrompts,
    this.hasSettingGenerationConfig = false, // 🆕 默认无配置
    required this.onSubmitReview,
  });

  @override
  State<ShareTemplateDialog> createState() => _ShareTemplateDialogState();
}

class _ShareTemplateDialogState extends State<ShareTemplateDialog> {
  late bool _hidePrompts;

  @override
  void initState() {
    super.initState();
    _hidePrompts = widget.hidePrompts ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveReviewStatus = widget.reviewStatus ?? 'DRAFT';
    final effectiveUsageCount = widget.usageCount ?? 0;
    final effectiveRewardPoints = widget.rewardPoints ?? 1;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头部
              _buildHeader(theme, isDark),
              
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 模板名称
                    Text(
                      widget.templateName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    
                    if (widget.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // 状态卡片
                    _buildStatusCard(theme, isDark, effectiveReviewStatus),
                    
                    const SizedBox(height: 16),
                    
                    // 🆕 隐藏提示词选项（仅在草稿和被拒绝状态显示）
                    if (effectiveReviewStatus == 'DRAFT' || effectiveReviewStatus == 'REJECTED') ...[
                      _buildHidePromptsOption(theme, isDark),
                      const SizedBox(height: 16),
                    ],
                    
                    // 积分提示
                    if (widget.isPublic) ...[
                      _buildPointsTip(theme, isDark, effectiveUsageCount, effectiveRewardPoints),
                      const SizedBox(height: 16),
                    ],
                    
                    // 说明文字
                    _buildDescription(theme, isDark, effectiveReviewStatus, effectiveRewardPoints),
                    
                    const SizedBox(height: 20),
                    
                    // 按钮
                    _buildButtons(context, theme, isDark, effectiveReviewStatus),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
              : [const Color(0xFF5856D6), const Color(0xFF4947CC)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.share_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '分享设置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark, String status) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusDescription;

    switch (status) {
      case ReviewStatusConstants.draft:
        statusColor = const Color(0xFF8E8E93);
        statusIcon = Icons.edit_note_rounded;
        statusText = '草稿';
        statusDescription = '模板尚未提交审核';
        break;
      case ReviewStatusConstants.pending:
        statusColor = const Color(0xFFFF9500);
        statusIcon = Icons.schedule_rounded;
        statusText = '审核中';
        statusDescription = '模板正在审核中，请耐心等待';
        break;
      case ReviewStatusConstants.approved:
        statusColor = const Color(0xFF34C759);
        statusIcon = Icons.check_circle_rounded;
        statusText = '已通过';
        statusDescription = '模板已在市场公开展示';
        break;
      case ReviewStatusConstants.rejected:
        statusColor = const Color(0xFFFF3B30);
        statusIcon = Icons.cancel_rounded;
        statusText = '未通过';
        statusDescription = '模板未通过审核，请修改后重新提交';
        break;
      default:
        statusColor = const Color(0xFF8E8E93);
        statusIcon = Icons.help_rounded;
        statusText = '未知';
        statusDescription = '状态未知';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusDescription,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsTip(ThemeData theme, bool isDark, int usageCount, int points) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFFFF9500).withOpacity(0.2), const Color(0xFFFF9500).withOpacity(0.1)]
              : [const Color(0xFFFFCC00).withOpacity(0.3), const Color(0xFFFFCC00).withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF9500).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.stars_rounded,
              color: Color(0xFFFF9500),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '积分奖励',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '已获得 ${usageCount * points} 积分（$usageCount 次引用 × $points 积分）',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHidePromptsOption(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF5856D6).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _hidePrompts ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: const Color(0xFF5856D6),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '隐藏提示词',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '开启后，其他用户可以使用您的模板但无法查看提示词内容',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _hidePrompts,
            onChanged: (value) {
              setState(() {
                _hidePrompts = value;
              });
            },
            activeColor: const Color(0xFF34C759),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ThemeData theme, bool isDark, String status, int points) {
    String text;
    if (status == 'DRAFT') {
      text = '提交审核后，您的模板将在审核通过后公开展示在提示词市场中。他人每引用一次，您将获得 $points 积分奖励。';
    } else if (status == 'PENDING') {
      text = '您的模板正在审核中，审核通过后将自动在提示词市场公开展示。他人每引用一次，您将获得 $points 积分奖励。';
    } else if (status == 'APPROVED') {
      text = '您的模板已在提示词市场公开展示。他人每引用一次，您将获得 $points 积分奖励。';
    } else {
      text = '您的模板未通过审核，请根据审核意见修改后重新提交。';
    }
    
    // 🆕 如果是设定生成策略，添加配置说明
    if (widget.hasSettingGenerationConfig && 
        widget.featureType == AIFeatureType.settingTreeGeneration) {
      text += '\n\n🔧 此策略包含完整的设定生成配置，他人复制后可直接使用所有配置参数。';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF007AFF).withOpacity(0.1) 
            : const Color(0xFF007AFF).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF007AFF).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: const Color(0xFF007AFF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF1C1C1E),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme, bool isDark, String status) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: status == 'DRAFT' || status == 'REJECTED' 
                  ? () {
                      // 🐛 调试日志：确认对话框传递的值
                      debugPrint('📋 ShareTemplateDialog: 提交审核 hidePrompts=$_hidePrompts');
                      widget.onSubmitReview(_hidePrompts);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                disabledBackgroundColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                status == 'DRAFT' || status == 'REJECTED' ? '提交审核' : 
                status == 'PENDING' ? '审核中' : '已通过',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: status == 'DRAFT' || status == 'REJECTED' 
                      ? Colors.white 
                      : (isDark ? Colors.grey[600] : Colors.grey[400]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

