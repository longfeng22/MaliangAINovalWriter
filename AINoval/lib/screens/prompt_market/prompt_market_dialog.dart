import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../models/prompt_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/api_service/base/api_client.dart' show ApiClient;
import '../../services/api_service/repositories/prompt_market_repository.dart';
import '../../utils/logger.dart';
import '../../utils/ai_feature_type_utils.dart';
import '../../widgets/common/top_toast.dart';
import '../../utils/event_bus.dart';
import 'widgets/prompt_template_card.dart';
import 'widgets/prompt_template_detail_dialog.dart';
import '../setting_generation/widgets/create_custom_strategy_dialog.dart';
import '../../services/api_service/repositories/setting_generation_repository.dart';

/// 提示词市场对话框
/// 苹果风格设计，支持所有AIFeatureType的tab切换
class PromptMarketDialog extends StatefulWidget {
  /// 初始选中的功能类型
  final AIFeatureType? initialFeatureType;
  
  const PromptMarketDialog({
    super.key,
    this.initialFeatureType,
  });

  @override
  State<PromptMarketDialog> createState() => _PromptMarketDialogState();
}

class _PromptMarketDialogState extends State<PromptMarketDialog> {
  static const String _tag = 'PromptMarketDialog';
  
  late final PromptMarketRepository _repository;
  late List<AIFeatureType> _availableTypes;
  late int _selectedTabIndex;
  
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _sortBy = 'popular'; // latest, popular, mostUsed, rating
  bool _showMyTemplates = false; // 是否显示我的提示词

  @override
  void initState() {
    super.initState();
    _repository = PromptMarketRepository(context.read<ApiClient>());
    
    // 获取所有可用的功能类型并排序
    _availableTypes = AIFeatureTypeUtils.sortByPriority(
      AIFeatureTypeUtils.getMarketAvailableTypes()
    );
    
    // 确定初始选中的tab
    if (widget.initialFeatureType != null && 
        _availableTypes.contains(widget.initialFeatureType)) {
      _selectedTabIndex = _availableTypes.indexOf(widget.initialFeatureType!);
    } else {
      _selectedTabIndex = 0; // 默认选中第一个
    }
    
    _loadTemplates();
  }

  void _showTemplateDetail(Map<String, dynamic> template) async {
    try {
      // 隐私保护：作者隐藏提示词时，不允许查看详情
      final hidePrompts = template['hidePrompts'] as bool? ?? false;
      final sys = (template['systemPrompt'] as String?) ?? '';
      final usr = (template['userPrompt'] as String?) ?? '';
      final isContentHidden = hidePrompts || (sys.isEmpty && usr.isEmpty);
      if (isContentHidden) {
        if (mounted) {
          TopToast.info(context, '作者隐藏提示词，无法查看详情');
        }
        return;
      }

      // 若数据不足，可按需拉取详情；这里直接用已加载字段组装模型
      final model = EnhancedUserPromptTemplate(
        id: template['id'] as String,
        userId: (template['userId'] as String?) ?? (template['authorId'] as String?) ?? '',
        name: (template['name'] as String?) ?? '未命名',
        description: template['description'] as String?,
        featureType: AIFeatureTypeHelper.fromApiString((template['featureType'] as String?) ?? 'TEXT_EXPANSION'),
        systemPrompt: (template['systemPrompt'] as String?) ?? '',
        userPrompt: (template['userPrompt'] as String?) ?? '',
        tags: (template['tags'] as List?)?.cast<String>() ?? const [],
        categories: (template['categories'] as List?)?.cast<String>() ?? const [],
        isPublic: template['isPublic'] as bool? ?? false,
        shareCode: template['shareCode'] as String?,
        isFavorite: template['isFavorite'] as bool? ?? false,
        isDefault: template['isDefault'] as bool? ?? false,
        usageCount: (template['usageCount'] as num?)?.toInt() ?? 0,
        rating: (template['rating'] as num?)?.toDouble() ?? 0.0,
        ratingCount: (template['ratingCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastUsedAt: null,
        isVerified: template['isVerified'] as bool? ?? false,
        authorId: template['authorId'] as String?,
        version: (template['version'] as num?)?.toInt(),
        language: template['language'] as String?,
        favoriteCount: (template['favoriteCount'] as num?)?.toInt(),
        reviewedAt: null,
        reviewedBy: null,
        reviewComment: template['reviewComment'] as String?,
        reviewStatus: template['reviewStatus'] as String?,
        hidePrompts: template['hidePrompts'] as bool? ?? false,
      );

      await showDialog(
        context: context,
        builder: (context) => PromptTemplateDetailDialog(template: model),
      );
    } catch (e) {
      AppLogger.error(_tag, '打开模板详情失败', e);
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final featureType = _availableTypes[_selectedTabIndex];
      AppLogger.info(_tag, '加载提示词模板: featureType=$featureType, sortBy=$_sortBy, showMyTemplates=$_showMyTemplates');
      
      List<Map<String, dynamic>> templates;
      
      if (_showMyTemplates) {
        // 加载用户自己的提示词
        templates = await _repository.getUserTemplates(
          featureType: featureType,
        );
      } else {
        // 加载公共提示词
        templates = await _repository.getPublicTemplates(
          featureType: featureType,
          page: 0,
          size: 50,
          sortBy: _sortBy,
        );
      }
      
      setState(() {
        _templates = templates;
        _isLoading = false;
      });
      
      AppLogger.info(_tag, '✅ 加载完成: ${templates.length} 个模板');
    } catch (e) {
      AppLogger.error(_tag, '加载失败', e);
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLike(Map<String, dynamic> template) async {
    try {
      final result = await _repository.toggleLike(template['id']);
      setState(() {
        template['isLiked'] = result['isLiked'];
        template['likeCount'] = result['likeCount'];
      });
      
      if (mounted) {
        TopToast.success(
          context, 
          result['isLiked'] == true ? '已点赞' : '已取消点赞'
        );
      }
    } catch (e) {
      AppLogger.error(_tag, '点赞操作失败', e);
      if (mounted) {
        TopToast.error(context, '操作失败: $e');
      }
    }
  }

  Future<void> _handleFavorite(Map<String, dynamic> template) async {
    try {
      final result = await _repository.toggleFavorite(template['id']);
      setState(() {
        template['isFavorite'] = result['isFavorite'];
        template['favoriteCount'] = result['favoriteCount'];
      });
      
      if (mounted) {
        TopToast.success(
          context, 
          result['isFavorite'] == true ? '已收藏' : '已取消收藏'
        );
      }
    } catch (e) {
      AppLogger.error(_tag, '收藏操作失败', e);
      if (mounted) {
        TopToast.error(context, '操作失败: $e');
      }
    }
  }

  void _handleUse(Map<String, dynamic> template) {
    // 显示成功提示
    if (mounted) {
      TopToast.success(context, '已选择提示词: ${template['name'] ?? '未命名'}');
    }
    
    // 关闭对话框并返回选中的模板
    if (mounted) {
      Navigator.of(context).pop(template);
    }
  }

  // 🆕 复制公开且未隐藏提示词的模板
  Future<void> _handleCopy(Map<String, dynamic> template) async {
    try {
      final isPublic = template['isPublic'] as bool? ?? false;
      final hidePrompts = template['hidePrompts'] as bool? ?? false;
      final sys = (template['systemPrompt'] as String?) ?? '';
      final usr = (template['userPrompt'] as String?) ?? '';
      if (!isPublic || hidePrompts) {
        if (mounted) {
          TopToast.info(context, '该模板不可复制');
        }
        return;
      }
      if (sys.isEmpty && usr.isEmpty) {
        if (mounted) {
          TopToast.info(context, '作者隐藏提示词，无法复制');
        }
        return;
      }

      // 统一使用通用复制表单：策略显示完整表单，提示词仅显示名称/描述
      final featureType = AIFeatureTypeHelper.fromApiString(
        (template['featureType'] as String?) ?? 'TEXT_EXPANSION',
      );
      final isStrategy = featureType == AIFeatureType.settingTreeGeneration;
      
      // 如果是策略，优先拉取完整详情以确保包含节点/深度等配置
      Map<String, dynamic> init;
      if (isStrategy) {
        Map<String, dynamic>? detail;
        try {
          final repo = context.read<SettingGenerationRepository>();
          detail = await repo.getStrategyDetail(strategyId: template['id'] as String);
        } catch (_) {}
        init = <String, dynamic>{
          // 不传 id，避免走更新流程；通过 baseStrategyId 标识来源
          'baseStrategyId': template['id'],
          'name': (detail != null ? detail['name'] : template['name']) ?? '未命名',
          'description': (detail != null ? detail['description'] : template['description']),
          'systemPrompt': (detail != null ? (detail['systemPrompt'] as String?) : sys) ?? '',
          'userPrompt': (detail != null ? (detail['userPrompt'] as String?) : usr) ?? '',
          'nodeTemplates': (detail != null ? (detail['nodeTemplates'] as List?) : template['nodeTemplates'] as List?) ?? [],
          'expectedRootNodes': (detail != null ? detail['expectedRootNodes'] : template['expectedRootNodes']) ?? 8,
          'maxDepth': (detail != null ? detail['maxDepth'] : template['maxDepth']) ?? 3,
          'hidePrompts': hidePrompts,
        };
      } else {
        init = <String, dynamic>{
          'id': template['id'],
          'name': template['name'],
          'description': template['description'],
          'systemPrompt': sys,
          'userPrompt': usr,
          'hidePrompts': hidePrompts,
        };
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CreateCustomStrategyDialog(
          strategy: init,
          isPromptMode: !isStrategy,
        ),
      );
      if (result == true && mounted) {
        TopToast.success(context, isStrategy ? '策略复制成功' : '模板复制成功');
      }
    } catch (e) {
      AppLogger.error(_tag, '复制模板失败', e);
      if (mounted) {
        TopToast.error(context, '复制失败: $e');
      }
    }
  }

  // 🆕 编辑我的提示词模板
  Future<void> _handleEdit(Map<String, dynamic> template) async {
    try {
      final featureType = AIFeatureTypeHelper.fromApiString(
        (template['featureType'] as String?) ?? 'TEXT_EXPANSION',
      );
      final isStrategy = featureType == AIFeatureType.settingTreeGeneration;
      
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CreateCustomStrategyDialog(
          strategy: template,
          isPromptMode: !isStrategy,
        ),
      );
      
      if (result == true) {
        _loadTemplates();
        if (mounted) {
          TopToast.success(context, '模板更新成功');
        }
      }
    } catch (e) {
      AppLogger.error(_tag, '编辑模板失败', e);
      if (mounted) {
        TopToast.error(context, '编辑失败: $e');
      }
    }
  }

  // 🆕 删除我的提示词模板
  Future<void> _handleDelete(Map<String, dynamic> template) async {
    try {
      // 确认删除
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('删除模板'),
          content: Text('确定要删除模板"${template['name']}"吗？此操作不可撤销。'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      
      if (confirmed == true) {
        await _repository.deleteTemplate(template['id']);
        _loadTemplates();
        if (mounted) {
          TopToast.success(context, '模板已删除');
        }
      }
    } catch (e) {
      AppLogger.error(_tag, '删除模板失败', e);
      if (mounted) {
        TopToast.error(context, '删除失败: $e');
      }
    }
  }

  // 🆕 分享我的提示词模板（提交审核）
  Future<void> _handleShare(Map<String, dynamic> template) async {
    try {
      // 询问是否隐藏提示词
      final hidePrompts = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('分享模板'),
          content: const Text('分享到提示词市场后，其他用户可以查看和使用你的模板。\n\n是否隐藏提示词内容？'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('公开提示词'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('隐藏提示词'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      
      if (hidePrompts != null) {
        await _repository.shareTemplate(template['id'], hidePrompts: hidePrompts);
        if (mounted) {
          TopToast.success(context, '已提交审核，审核通过后将在提示词市场公开分享');
        }
        _loadTemplates();
      }
    } catch (e) {
      AppLogger.error(_tag, '分享模板失败', e);
      if (mounted) {
        TopToast.error(context, '分享失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.9).clamp(800.0, 1400.0);
    final dialogHeight = (screenSize.height * 0.85).clamp(600.0, 900.0);
    
    return Dialog(
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: CupertinoColors.systemBackground.resolveFrom(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildSortBar(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.sparkles,
            size: 28,
            color: CupertinoColors.systemBlue,
          ),
          const SizedBox(width: 12),
          const Text(
            '提示词市场',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 28,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _availableTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _availableTypes[index];
          final isSelected = index == _selectedTabIndex;
          
          return _buildTab(
            type: type,
            isSelected: isSelected,
            onTap: () {
              setState(() {
                _selectedTabIndex = index;
              });
              _loadTemplates();
            },
          );
        },
      ),
    );
  }

  Widget _buildTab({
    required AIFeatureType type,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = Color(AIFeatureTypeUtils.getColor(type));
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : CupertinoColors.separator.resolveFrom(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              AIFeatureTypeUtils.getShortName(type),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? color
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
      ),
      child: Row(
        children: [
          // 排序按钮组（仅在公共提示词模式下显示）
          if (!_showMyTemplates) ...[
            _buildSortButton('popular', '最受欢迎', CupertinoIcons.heart_fill),
            const SizedBox(width: 8),
            _buildSortButton('latest', '最新', CupertinoIcons.time),
            const SizedBox(width: 8),
            _buildSortButton('mostUsed', '最多使用', CupertinoIcons.chart_bar_fill),
            const SizedBox(width: 8),
            _buildSortButton('rating', '最高评分', CupertinoIcons.star_fill),
            const SizedBox(width: 8),
          ] else ...[
            // 我的提示词模式下显示提示文字
            Text(
              '我的提示词',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ],
          const Spacer(),
          // "我的提示词"按钮
          _buildMyTemplatesButton(),
        ],
      ),
    );
  }

  // 🆕 我的提示词按钮
  Widget _buildMyTemplatesButton() {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minSize: 0,
      onPressed: () {
        setState(() {
          _showMyTemplates = !_showMyTemplates;
          // 切换模式时，重置排序方式为默认
          if (!_showMyTemplates) {
            _sortBy = 'popular';
          }
        });
        _loadTemplates();
      },
      color: _showMyTemplates ? CupertinoColors.systemBlue : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showMyTemplates ? CupertinoIcons.person_fill : CupertinoIcons.person,
            size: 16,
            color: _showMyTemplates 
                ? CupertinoColors.white 
                : CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          const SizedBox(width: 6),
          Text(
            _showMyTemplates ? '公共提示词' : '我的提示词',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _showMyTemplates 
                  ? CupertinoColors.white 
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton(String sortBy, String label, IconData icon) {
    final isSelected = _sortBy == sortBy;
    
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minSize: 0,
      onPressed: () {
        setState(() {
          _sortBy = sortBy;
        });
        _loadTemplates();
      },
      color: isSelected ? CupertinoColors.systemBlue : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected 
                ? CupertinoColors.white 
                : CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected 
                  ? CupertinoColors.white 
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 16),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemRed,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 16,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: _loadTemplates,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.tray,
              size: 64,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无${AIFeatureTypeUtils.getShortName(_availableTypes[_selectedTabIndex])}类型的提示词模板',
              style: const TextStyle(
                fontSize: 16,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ],
        ),
      );
    }

    // 🎯 使用 CustomScrollView 实现固定横幅和滚动列表
    return CustomScrollView(
      slivers: [
        // 💰 固定的积分奖励公告横幅（仅在公共提示词模式下显示）
        if (!_showMyTemplates)
          SliverToBoxAdapter(
            child: _buildPointsBanner(),
          ),
        
        // 模板列表
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 320,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final tpl = _templates[index];
                return PromptTemplateCard(
                  template: tpl,
                  currentFeatureType: widget.initialFeatureType,
                  isMyTemplate: _showMyTemplates,
                  // 公共提示词模式的回调
                  onLike: _showMyTemplates ? null : () => _handleLike(tpl),
                  onFavorite: _showMyTemplates ? null : () => _handleFavorite(tpl),
                  onCopy: _showMyTemplates ? null : () => _handleCopy(tpl),
                  // 我的提示词模式的回调
                  onEdit: _showMyTemplates ? () => _handleEdit(tpl) : null,
                  onDelete: _showMyTemplates ? () => _handleDelete(tpl) : null,
                  onShare: _showMyTemplates ? () => _handleShare(tpl) : null,
                  // 通用回调
                  onUse: () => _handleUse(tpl),
                  onTap: () => _showTemplateDetail(tpl),
                );
              },
              childCount: _templates.length,
            ),
          ),
        ),
      ],
    );
  }

  /// 💰 积分奖励公告横幅
  Widget _buildPointsBanner() {
    final isDark = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    ).value == 0xFFFFFFFF;
    
    final currentType = _availableTypes[_selectedTabIndex];
    final rewardPoints = AIFeatureTypeUtils.getRewardPoints(currentType);
    
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CupertinoColors.systemOrange.withOpacity(isDark ? 0.2 : 0.15),
            CupertinoColors.systemOrange.withOpacity(isDark ? 0.15 : 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoColors.systemOrange.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemOrange.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 🌟 图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CupertinoColors.systemOrange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.star_fill,
              size: 18,
              color: CupertinoColors.systemOrange,
            ),
          ),
          const SizedBox(width: 12),
          
          // 📝 文字说明
          Expanded(
            child: Text(
              rewardPoints > 0
                  ? '💰 分享提示词，每次被引用可获得 $rewardPoints 积分'
                  : '💰 分享提示词，帮助更多创作者',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark 
                    ? CupertinoColors.white.withOpacity(0.9)
                    : CupertinoColors.black.withOpacity(0.8),
                height: 1.3,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 🚀 分享按钮
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: CupertinoColors.systemOrange,
            borderRadius: BorderRadius.circular(10),
            minSize: 0,
            onPressed: () {
              // 通过事件总线通知外层切换左侧路由
              try { EventBus.instance.fire(const NavigateToUnifiedManagement()); } catch (_) {}
              // 关闭当前对话框
              Navigator.of(context).pop();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  CupertinoIcons.square_arrow_up,
                  size: 14,
                  color: CupertinoColors.white,
                ),
                SizedBox(width: 4),
                Text(
                  '分享',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 已改由事件总线处理导航
}

