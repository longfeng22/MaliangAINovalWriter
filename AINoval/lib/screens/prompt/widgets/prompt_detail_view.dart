import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_state.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/models/admin/review_models.dart';
// removed duplicate import
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/screens/prompt/widgets/prompt_content_editor.dart';
import 'package:ainoval/screens/prompt/widgets/prompt_properties_editor.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/screens/setting_generation/widgets/create_custom_strategy_dialog.dart';
import 'package:ainoval/widgets/common/share_template_dialog.dart';
import 'package:ainoval/services/api_service/repositories/prompt_market_repository.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';

/// 提示词详情视图
class PromptDetailView extends StatefulWidget {
  const PromptDetailView({
    super.key,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  State<PromptDetailView> createState() => _PromptDetailViewState();
}

class _PromptDetailViewState extends State<PromptDetailView>
    with TickerProviderStateMixin {
  static const String _tag = 'PromptDetailView';
  
  late TabController _tabController;

  // 名称输入框控制器
  final TextEditingController _nameController = TextEditingController();

  // 是否处于已编辑但未保存状态
  bool _isEdited = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // final isDark = WebTheme.isDarkMode(context); // unused
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: BlocConsumer<PromptNewBloc, PromptNewState>(
        listener: (context, state) {
          // 当选中的提示词发生变化时，更新名称控制器
          if (state.selectedPrompt != null) {
            _nameController.text = state.selectedPrompt!.name;
            _isEdited = false;
          }
        },
        builder: (context, state) {
          final prompt = state.selectedPrompt;
          
          // 确保在非编辑状态下名称与当前提示词保持同步，避免首次点击时显示为空
          if (prompt != null && !_isEdited && _nameController.text != prompt.name) {
            _nameController.text = prompt.name;
          }
          
          if (prompt == null) {
            return _buildEmptyView();
          }

          return Column(
            children: [
              // 顶部标题栏
              _buildTopBar(context, prompt, state),
              
              // 标签栏
              _buildTabBar(),
              
              // 内容区域
              Expanded(
                child: Container(
                  color: WebTheme.getSurfaceColor(context),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      PromptContentEditor(prompt: prompt),
                      PromptPropertiesEditor(prompt: prompt),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建顶部标题栏
  Widget _buildTopBar(BuildContext context, UserPromptInfo prompt, PromptNewState state) {
    final isDark = WebTheme.isDarkMode(context);
    final isSystemDefault = prompt.id.startsWith('system_default_');
    final isPublicTemplate = prompt.id.startsWith('public_');
    final isReadOnly = isSystemDefault || isPublicTemplate;
    
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮（仅在窄屏幕显示）
          if (widget.onBack != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onBack,
                  child: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: isDark ? WebTheme.darkGrey600 : WebTheme.grey700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          
          // 模板标题
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: WebTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                      height: 1.2,
                    ),
                    decoration: WebTheme.getBorderlessInputDecoration(
                      hintText: '输入模板名称...',
                      context: context,
                    ),
                    cursorColor: WebTheme.getTextColor(context),
                    maxLines: 1,
                    readOnly: isReadOnly,
                    onChanged: (value) {
                      setState(() {
                        _isEdited = true;
                      });
                    },
                  ),
                ),
                
                // 🆕 审核状态标签
                if (prompt.reviewStatus == ReviewStatusConstants.pending) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFFF9500).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: const Color(0xFFFF9500),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '待审核',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFF9500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // 🆕 已通过标签
                if (prompt.reviewStatus == ReviewStatusConstants.approved) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF34C759).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: const Color(0xFF34C759),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '已公开',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF34C759),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // 🆕 未通过标签
                if (prompt.reviewStatus == ReviewStatusConstants.rejected) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFFF3B30).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cancel_rounded,
                          size: 14,
                          color: const Color(0xFFFF3B30),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '审核未通过',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFF3B30),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 操作按钮
          _buildActionButtons(context, prompt, state),
        ],
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(BuildContext context, UserPromptInfo prompt, PromptNewState state) {
    final isDark = WebTheme.isDarkMode(context);
    final isSystemDefault = prompt.id.startsWith('system_default_');
    final isPublicTemplate = prompt.id.startsWith('public_');
    final canSetDefault = !isSystemDefault && !isPublicTemplate;
    final canEdit = !isSystemDefault && !isPublicTemplate;
    
    // 🆕 优化分享按钮逻辑：
    // 1. 系统/公共模板不能分享
    // 2. 已经提交审核（PENDING）或已通过（APPROVED）的模板不能再分享
    // 3. 只有草稿（DRAFT/null）或被拒绝（REJECTED）的私有模板可以分享
    final canShare = canEdit && 
        !prompt.isPublic && 
        (prompt.reviewStatus == null || 
         prompt.reviewStatus == ReviewStatusConstants.draft || 
         prompt.reviewStatus == ReviewStatusConstants.rejected);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🆕 分享按钮（最左侧）
        if (canShare) ...[
          _buildTextButton(
            icon: Icons.share_rounded,
            label: '分享我的模版',
            tooltip: '分享我的模版，他人引用一次，你将获得积分奖励',
            onPressed: () => _showShareDialog(context, prompt),
            backgroundColor: const Color(0xFF007AFF),
            textColor: Colors.white,
            showRewardBadge: true,
          ),
          const SizedBox(width: 8),
        ],
        
        // 复制按钮
        _buildTextButton(
          icon: Icons.copy_outlined,
          label: '复制',
          tooltip: '复制模板',
          onPressed: () async {
            // 设定树提示词：走策略复制表单（创建新策略，写入SettingGenerationConfig）
            if (prompt.featureType == AIFeatureType.settingTreeGeneration) {
              final init = <String, dynamic>{
                'baseStrategyId': prompt.id, // 作为来源，避免走更新
                'name': prompt.name,
                'description': prompt.description,
                'systemPrompt': prompt.systemPrompt,
                'userPrompt': prompt.userPrompt,
                'nodeTemplates': prompt.settingGenerationConfig?.nodeTemplates ?? [],
                'expectedRootNodes': prompt.settingGenerationConfig?.expectedRootNodes ?? 8,
                'maxDepth': prompt.settingGenerationConfig?.maxDepth ?? 3,
                'hidePrompts': prompt.hidePrompts,
              };
              await showDialog<bool>(
                context: context,
                builder: (context) => CreateCustomStrategyDialog(
                  strategy: init,
                  isPromptMode: false,
                ),
              );
            } else {
              // 普通提示词：沿用增强模板复制
              context.read<PromptNewBloc>().add(CopyPromptTemplate(
                templateId: prompt.id,
              ));
            }
          },
        ),
        
        const SizedBox(width: 8),
        
        // 收藏按钮
        _buildTextButton(
          icon: prompt.isFavorite ? Icons.star : Icons.star_outline,
          label: '收藏',
          tooltip: prompt.isFavorite ? '取消收藏' : '收藏',
          onPressed: () {
            context.read<PromptNewBloc>().add(ToggleFavoriteStatus(
              promptId: prompt.id,
              isFavorite: !prompt.isFavorite,
            ));
          },
        ),
        
        if (canSetDefault) ...[
          const SizedBox(width: 8),
          // 设为默认按钮
          _buildTextButton(
            icon: prompt.isDefault ? Icons.bookmark : Icons.bookmark_outline,
            label: '默认',
            tooltip: prompt.isDefault ? '已是默认' : '设为默认',
            onPressed: prompt.isDefault
                ? null
                : () {
                    final featureType = state.selectedFeatureType;
                    if (featureType != null) {
                      context.read<PromptNewBloc>().add(SetDefaultTemplate(
                        promptId: prompt.id,
                        featureType: featureType,
                      ));
                    }
                  },
          ),
        ],
        
        if (!isSystemDefault && !isPublicTemplate) ...[
          const SizedBox(width: 8),
          // 删除按钮
          _buildTextButton(
            icon: Icons.delete_outline,
            label: '删除',
            tooltip: '删除',
            onPressed: () => _showDeleteConfirmDialog(context, prompt),
            textColor: isDark ? Colors.red[300] : Colors.red[700],
          ),
        ],
        
        // 保存按钮（系统/公共模板不显示）
        if (canEdit && (_isEdited || state.isUpdating)) ...[
          const SizedBox(width: 8),
          _buildTextButton(
            icon: state.isUpdating ? Icons.hourglass_empty : Icons.save,
            label: state.isUpdating ? '保存中...' : '保存',
            tooltip: '保存修改',
            onPressed: state.isUpdating ? null : () => _saveChanges(context, prompt),
            backgroundColor: WebTheme.grey900,
            textColor: Colors.white,
          ),
        ],
      ],
    );
  }
  
  /// 构建统一的文本按钮（图标+文字）
  Widget _buildTextButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? textColor,
    bool showRewardBadge = false,
  }) {
    final isDark = WebTheme.isDarkMode(context);
    final defaultBackgroundColor = isDark ? WebTheme.darkGrey200 : WebTheme.grey100;
    final defaultTextColor = onPressed != null 
        ? (isDark ? WebTheme.darkGrey600 : WebTheme.grey700)
        : (isDark ? WebTheme.darkGrey400 : WebTheme.grey400);
    
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: backgroundColor ?? defaultBackgroundColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: textColor ?? defaultTextColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: WebTheme.labelSmall.copyWith(
                      color: textColor ?? defaultTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// 显示分享对话框
  Future<void> _showShareDialog(BuildContext context, UserPromptInfo prompt) async {
    // 🚀 获取积分奖励信息
    int? rewardPoints;
    try {
      final marketRepo = PromptMarketRepository(ApiClient());
      final allPoints = await marketRepo.getAllRewardPoints();
      final featureTypeKey = prompt.featureType.toApiString();
      rewardPoints = allPoints[featureTypeKey];
    } catch (e) {
      AppLogger.error(_tag, '获取积分奖励信息失败: $e');
      rewardPoints = 1; // 默认1积分
    }
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => ShareTemplateDialog(
        templateId: prompt.id,
        templateName: prompt.name,
        description: prompt.description,
        featureType: prompt.featureType,
        isPublic: prompt.isPublic,
        reviewStatus: prompt.reviewStatus,
        usageCount: prompt.usageCount,
        rewardPoints: rewardPoints,
        hidePrompts: prompt.hidePrompts, // 🔥 使用模板当前的隐藏状态
        hasSettingGenerationConfig: prompt.settingGenerationConfig != null, // 🆕 是否包含设定生成配置
        onSubmitReview: (hidePrompts) async {
          Navigator.of(context).pop();
          await _submitForReview(prompt, hidePrompts);
        },
      ),
    );
  }
  
  /// 提交审核
  Future<void> _submitForReview(UserPromptInfo prompt, bool hidePrompts) async {
    try {
      AppLogger.info(_tag, '🎬 UI层收到提交请求: promptId=${prompt.id}, hidePrompts=$hidePrompts');
      
      // 🎯 使用 Bloc 事件来处理提交审核，实现乐观更新
      context.read<PromptNewBloc>().add(SubmitForReview(
        promptId: prompt.id,
        hidePrompts: hidePrompts,
      ));
      
      if (mounted) {
        final hideTip = hidePrompts ? '（已隐藏提示词）' : '';
        TopToast.success(context, '已提交审核$hideTip，审核通过后将在提示词市场公开分享');
        AppLogger.info(_tag, '✅ UI层提交审核完成');
      }
    } catch (e) {
      AppLogger.error(_tag, '❌ UI层提交审核失败: $e');
      if (mounted) {
        TopToast.error(context, '提交失败: $e');
      }
    }
  }

  /// 构建标签栏
  Widget _buildTabBar() {
    final isDark = WebTheme.isDarkMode(context);
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: WebTheme.getPrimaryColor(context),
        unselectedLabelColor: WebTheme.getSecondaryTextColor(context),
        indicatorColor: WebTheme.getPrimaryColor(context),
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('内容编辑'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('属性设置'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建空视图
  Widget _buildEmptyView() {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                borderRadius: BorderRadius.circular(60),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 48,
                color: WebTheme.getPrimaryColor(context).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '选择一个提示词模板',
              style: WebTheme.headlineSmall.copyWith(
                color: WebTheme.getTextColor(context),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                '在左侧列表中选择一个提示词模板以查看和编辑详情。\n您可以修改模板内容、设置属性、添加标签等。',
                style: WebTheme.bodyMedium.copyWith(
                  color: WebTheme.getSecondaryTextColor(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFeatureIcon(Icons.edit_outlined, '编辑内容'),
                const SizedBox(width: 24),
                _buildFeatureIcon(Icons.settings_outlined, '设置属性'),
                const SizedBox(width: 24),
                _buildFeatureIcon(Icons.label_outline, '管理标签'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建功能图标
  Widget _buildFeatureIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: WebTheme.isDarkMode(context) 
                ? WebTheme.darkGrey200.withOpacity(0.5)
                : WebTheme.grey100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            size: 20,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
      ],
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(BuildContext context, UserPromptInfo prompt) {
    // final isDark = WebTheme.isDarkMode(context); // unused
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WebTheme.getSurfaceColor(context),
        title: Text(
          '确认删除',
          style: WebTheme.titleMedium.copyWith(
            color: WebTheme.getTextColor(context),
          ),
        ),
        content: Text(
          '确定要删除提示词模板 "${prompt.name}" 吗？此操作无法撤销。',
          style: WebTheme.bodyMedium.copyWith(
            color: WebTheme.getTextColor(context, isPrimary: false),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: WebTheme.getSecondaryTextColor(context),
            ),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<PromptNewBloc>().add(DeletePrompt(
                promptId: prompt.id,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WebTheme.error,
              foregroundColor: WebTheme.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 保存更改
  void _saveChanges(BuildContext context, UserPromptInfo prompt) {
    if (_nameController.text.trim().isEmpty) {
      TopToast.warning(context, '模板名称不能为空');
      return;
    }

    final request = UpdatePromptTemplateRequest(
      name: _nameController.text.trim(),
    );

    context.read<PromptNewBloc>().add(UpdatePromptDetails(
      promptId: prompt.id,
      request: request,
    ));

    setState(() {
      _isEdited = false;
    });

    AppLogger.i(_tag, '保存提示词模板更改: ${prompt.id}');
  }
} 