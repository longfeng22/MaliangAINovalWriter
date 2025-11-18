/// 审核详情对话框
/// 显示审核项的完整信息并提供审核操作

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/admin/review_models.dart';
import '../../../services/api_service/repositories/admin/review_repository.dart';
import '../../../utils/logger.dart';
import '../../../utils/date_formatter.dart';

class ReviewDetailDialog extends StatefulWidget {
  final ReviewItem item;

  const ReviewDetailDialog({
    super.key,
    required this.item,
  });

  @override
  State<ReviewDetailDialog> createState() => _ReviewDetailDialogState();
}

class _ReviewDetailDialogState extends State<ReviewDetailDialog> {
  static const String _tag = 'ReviewDetailDialog';

  final TextEditingController _commentController = TextEditingController();
  final List<String> _selectedRejectionReasons = [];
  final List<String> _improvementSuggestions = [];

  // 预设的拒绝理由
  static const List<String> _rejectionReasonOptions = [
    '内容不符合规范',
    '质量不达标',
    '存在违规内容',
    '信息不完整',
    '描述不清晰',
    '重复提交',
  ];

  // 预设的改进建议
  static const List<String> _improvementSuggestionOptions = [
    '请补充完整的描述信息',
    '请优化提示词质量',
    '请移除违规内容',
    '请参考官方示例进行修改',
    '请使用更专业的表述',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview(String decision) async {
    try {
      final repository = context.read<ReviewRepository>();
      
      await repository.reviewItem(
        itemId: widget.item.id,
        type: widget.item.type,
        decision: ReviewDecision(
          decision: decision,
          comment: _commentController.text.isEmpty ? null : _commentController.text,
          rejectionReasons: decision == ReviewDecisionConstants.rejected && _selectedRejectionReasons.isNotEmpty
            ? _selectedRejectionReasons
            : null,
          improvementSuggestions: decision == ReviewDecisionConstants.rejected && _improvementSuggestions.isNotEmpty
            ? _improvementSuggestions
            : null,
        ),
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decision == ReviewDecisionConstants.approved ? '✅ 审核通过' : '❌ 审核拒绝'),
            backgroundColor: decision == ReviewDecisionConstants.approved 
              ? const Color(0xFF34C759) 
              : const Color(0xFFFF3B30),
          ),
        );
      }
    } catch (e) {
      AppLogger.error(_tag, '审核失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('审核失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPending = widget.item.status == ReviewStatus.pending;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // 头部
              _buildHeader(theme, isDark),
              
              // 内容
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基本信息
                      _buildInfoSection(theme, isDark),
                      const SizedBox(height: 24),

                      // 详细内容
                      _buildContentSection(theme, isDark),
                      const SizedBox(height: 24),

                      // 审核操作（仅待审核状态显示）
                      if (isPending) ...[
                        _buildReviewSection(theme, isDark),
                        const SizedBox(height: 24),
                      ],

                      // 历史审核记录
                      if (widget.item.reviewedAt != null)
                        _buildHistorySection(theme, isDark),
                    ],
                  ),
                ),
              ),

              // 底部操作按钮
              _buildFooter(theme, isDark, isPending),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.fact_check_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '审核详情',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.item.type.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.item.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
              _buildStatusBadge(widget.item.status),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildInfoRow(Icons.person_outline, '作者', widget.item.authorName ?? '未知', isDark),
          _buildInfoRow(Icons.access_time, '创建时间', _formatDateTime(widget.item.createdAt), isDark),
          if (widget.item.submittedAt != null)
            _buildInfoRow(Icons.upload, '提交时间', _formatDateTime(widget.item.submittedAt!), isDark),
          if (widget.item.reviewedAt != null)
            _buildInfoRow(Icons.check_circle, '审核时间', _formatDateTime(widget.item.reviewedAt!), isDark),
          if (widget.item.reviewerName != null)
            _buildInfoRow(Icons.admin_panel_settings, '审核人', widget.item.reviewerName!, isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '内容详情',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        
        // 描述
        if (widget.item.description.isNotEmpty) ...[
          _buildContentItem(
            theme: theme,
            isDark: isDark,
            label: '描述',
            content: widget.item.description,
            icon: Icons.description_outlined,
          ),
          const SizedBox(height: 12),
        ],
        
        // 🆕 系统提示词
        if (widget.item.systemPrompt != null && widget.item.systemPrompt!.isNotEmpty) ...[
          _buildContentItem(
            theme: theme,
            isDark: isDark,
            label: '系统提示词',
            content: widget.item.systemPrompt!,
            icon: Icons.settings_suggest_outlined,
            color: const Color(0xFF5856D6),
          ),
          const SizedBox(height: 12),
        ],
        
        // 🆕 用户提示词
        if (widget.item.userPrompt != null && widget.item.userPrompt!.isNotEmpty) ...[
          _buildContentItem(
            theme: theme,
            isDark: isDark,
            label: '用户提示词',
            content: widget.item.userPrompt!,
            icon: Icons.chat_bubble_outline,
            color: const Color(0xFF34C759),
          ),
          const SizedBox(height: 12),
        ],
        
        // 🆕 是否隐藏提示词配置
        if (widget.item.hidePrompts != null) ...[
          _buildHidePromptsSection(theme, isDark),
          const SizedBox(height: 12),
        ],
        
        // 🆕 标签
        if (widget.item.tags != null && widget.item.tags!.isNotEmpty) ...[
          _buildTagsSection(theme, isDark),
          const SizedBox(height: 12),
        ],
        
        // 🆕 分类
        if (widget.item.categories != null && widget.item.categories!.isNotEmpty) ...[
          _buildCategoriesSection(theme, isDark),
          const SizedBox(height: 12),
        ],
        
        // 🆕 统计信息
        _buildStatisticsSection(theme, isDark),
      ],
    );
  }
  
  /// 🆕 构建内容项
  Widget _buildContentItem({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required String content,
    required IconData icon,
    Color? color,
  }) {
    final itemColor = color ?? (isDark ? Colors.blue : const Color(0xFF0A84FF));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: itemColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: itemColor.withOpacity(0.3),
            ),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
  
  /// 🆕 构建标签区域
  Widget _buildTagsSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.label_outline, size: 18, color: const Color(0xFFFF9500)),
            const SizedBox(width: 8),
            Text(
              '标签',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.item.tags!.map((tag) => Chip(
            label: Text(
              tag,
              style: TextStyle(fontSize: 12),
            ),
            backgroundColor: const Color(0xFFFF9500).withOpacity(0.1),
            side: BorderSide(color: const Color(0xFFFF9500).withOpacity(0.3)),
          )).toList(),
        ),
      ],
    );
  }
  
  /// 🆕 构建分类区域
  Widget _buildCategoriesSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.category_outlined, size: 18, color: const Color(0xFF5E5CE6)),
            const SizedBox(width: 8),
            Text(
              '分类',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.item.categories!.map((category) => Chip(
            label: Text(
              category,
              style: TextStyle(fontSize: 12),
            ),
            backgroundColor: const Color(0xFF5E5CE6).withOpacity(0.1),
            side: BorderSide(color: const Color(0xFF5E5CE6).withOpacity(0.3)),
          )).toList(),
        ),
      ],
    );
  }
  
  /// 🆕 构建统计信息区域
  Widget _buildStatisticsSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              icon: Icons.remove_red_eye_outlined,
              label: '使用次数',
              value: '${widget.item.usageCount ?? 0}',
              color: const Color(0xFF0A84FF),
              isDark: isDark,
            ),
          ),
          Expanded(
            child: _buildStatItem(
              icon: Icons.favorite_outline,
              label: '收藏数',
              value: '${widget.item.favoriteCount ?? 0}',
              color: const Color(0xFFFF3B30),
              isDark: isDark,
            ),
          ),
          if (widget.item.rating != null)
            Expanded(
              child: _buildStatItem(
                icon: Icons.star_outline,
                label: '评分',
                value: widget.item.rating!.toStringAsFixed(1),
                color: const Color(0xFFFF9500),
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }
  
  /// 🆕 构建统计项
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
  
  /// 🆕 构建隐藏提示词配置区域
  Widget _buildHidePromptsSection(ThemeData theme, bool isDark) {
    final hidePrompts = widget.item.hidePrompts ?? false;
    final color = hidePrompts ? const Color(0xFFFF3B30) : const Color(0xFF34C759);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              hidePrompts ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提示词可见性',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hidePrompts ? '用户不可见提示词内容' : '用户可见提示词内容',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              hidePrompts ? '已隐藏' : '可见',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '审核操作',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        
        // 审核意见
        TextField(
          controller: _commentController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '请输入审核意见（选填）',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        
        // 拒绝理由（仅拒绝时显示）
        ExpansionTile(
          title: Text(
            '拒绝理由（可选）',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rejectionReasonOptions.map((reason) {
                final isSelected = _selectedRejectionReasons.contains(reason);
                return FilterChip(
                  label: Text(reason),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedRejectionReasons.add(reason);
                      } else {
                        _selectedRejectionReasons.remove(reason);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
        
        // 改进建议（仅拒绝时显示）
        ExpansionTile(
          title: Text(
            '改进建议（可选）',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _improvementSuggestionOptions.map((suggestion) {
                final isSelected = _improvementSuggestions.contains(suggestion);
                return FilterChip(
                  label: Text(suggestion),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _improvementSuggestions.add(suggestion);
                      } else {
                        _improvementSuggestions.remove(suggestion);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistorySection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '审核记录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.item.reviewComment != null) ...[
                Text(
                  '审核意见：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.item.reviewComment!,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ),
              ],
              if (widget.item.rejectionReasons != null && widget.item.rejectionReasons!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '拒绝理由：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.item.rejectionReasons!.map((reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: const Color(0xFFFF3B30)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              if (widget.item.improvementSuggestions != null && widget.item.improvementSuggestions!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '改进建议：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.item.improvementSuggestions!.map((suggestion) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: const Color(0xFFFF9500)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          suggestion,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, bool isDark, bool isPending) {
    if (!isPending) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
            ),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
              foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '关闭',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _submitReview(ReviewDecisionConstants.rejected),
              icon: const Icon(Icons.cancel, size: 20),
              label: const Text(
                '拒绝',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _submitReview(ReviewDecisionConstants.approved),
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text(
                '通过',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF34C759),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ReviewStatus status) {
    Color color;
    switch (status) {
      case ReviewStatus.pending:
        color = const Color(0xFFFF9500);
        break;
      case ReviewStatus.approved:
        color = const Color(0xFF34C759);
        break;
      case ReviewStatus.rejected:
        color = const Color(0xFFFF3B30);
        break;
      case ReviewStatus.draft:
        color = const Color(0xFF8E8E93);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.emoji,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    // 使用公共的时间格式化函数
    return DateFormatter.formatFull(date);
  }
}

