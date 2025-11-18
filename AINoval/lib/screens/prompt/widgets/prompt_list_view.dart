import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_state.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/management_list_widgets.dart';
// import 'package:ainoval/utils/logger.dart';

/// 提示词列表视图
class PromptListView extends StatefulWidget {
  const PromptListView({
    super.key,
    required this.onPromptSelected,
  });

  final Function(String promptId, AIFeatureType featureType) onPromptSelected;

  @override
  State<PromptListView> createState() => _PromptListViewState();
}

class _PromptListViewState extends State<PromptListView> {
  // static const String _tag = 'PromptListView';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          right: BorderSide(
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部标题栏（共享）
          const ManagementListTopBar(
            title: '提示词管理',
            subtitle: 'AI 提示词模板库',
            icon: Icons.auto_awesome,
          ),
          
          // 搜索框
          _buildSearchBar(),
          
          // 分隔线
          Container(
            height: 1,
            color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
          ),
          
          // 提示词列表
          Expanded(
            child: BlocBuilder<PromptNewBloc, PromptNewState>(
              builder: (context, state) {
                if (state.isLoading) {
                  return _buildLoadingView();
                } else if (state.hasError) {
                  return _buildErrorView(state.errorMessage ?? '加载失败');
                } else if (!state.hasData) {
                  return _buildEmptyView();
                } else {
                  return _buildPromptList(state);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部标题栏已由共享组件 ManagementListTopBar 提供

  /// 构建搜索栏
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: _searchController,
        decoration: WebTheme.getBorderedInputDecoration(
          hintText: '搜索提示词...',
          context: context,
        ).copyWith(
          filled: true,
          fillColor: WebTheme.getSurfaceColor(context),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 18,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    context.read<PromptNewBloc>().add(const ClearSearch());
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: WebTheme.bodyMedium.copyWith(color: WebTheme.getTextColor(context)),
        onChanged: (query) {
          setState(() {}); // Trigger rebuild for suffix icon
          context.read<PromptNewBloc>().add(SearchPrompts(query: query));
        },
      ),
    );
  }

  /// 构建加载视图
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(WebTheme.getTextColor(context)),
          ),
          const SizedBox(height: 16),
          Text(
            '加载提示词中...',
            style: WebTheme.bodyMedium.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: WebTheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: WebTheme.bodyMedium.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context.read<PromptNewBloc>().add(const LoadAllPromptPackages());
            },
            style: WebTheme.getPrimaryButtonStyle(context),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建空视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 64,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            '没有找到提示词模板',
            style: WebTheme.headlineSmall.copyWith(
              color: WebTheme.getTextColor(context),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '请检查网络连接或稍后重试',
            style: WebTheme.bodyMedium.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 构建提示词列表
  Widget _buildPromptList(PromptNewState state) {
    final promptPackages = state.promptPackages;
    
    if (promptPackages.isEmpty) {
      return _buildEmptyView();
    }

    // 获取所有包的条目列表
    final packageEntries = promptPackages.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: packageEntries.length,
      itemBuilder: (context, index) {
        final entry = packageEntries[index];
        final featureType = entry.key;
        final package = entry.value;
        
        // 获取该功能类型的所有提示词
        final allPrompts = _getAllPromptsForFeatureType(featureType, package);
        
        return _buildFeatureTypeSection(featureType, allPrompts, state);
      },
    );
  }

  /// 获取指定功能类型的所有提示词（系统默认 + 用户自定义 + 公开模板）
  List<UserPromptInfo> _getAllPromptsForFeatureType(AIFeatureType featureType, PromptPackage package) {
    final allPrompts = <UserPromptInfo>[];
    
    // 检查是否有用户默认模板
    final hasUserDefault = package.userPrompts.any((prompt) => prompt.isDefault);
    
    // 1. 添加系统默认提示词
    if (package.systemPrompt.defaultSystemPrompt.isNotEmpty) {
      final systemPromptAsUser = UserPromptInfo(
        id: 'system_default_${featureType.toString()}',
        name: '系统默认模板',
        description: '系统提供的默认提示词模板',
        featureType: featureType,
        systemPrompt: package.systemPrompt.effectivePrompt,
        userPrompt: package.systemPrompt.defaultUserPrompt,
        tags: const ['系统默认'],
        isDefault: !hasUserDefault, // 当没有用户默认模板时，系统默认模板显示为默认
        authorId: 'system',
        createdAt: package.lastUpdated,
        updatedAt: package.lastUpdated,
      );
      allPrompts.add(systemPromptAsUser);
    }
    
    // 2. 添加用户自定义提示词
    allPrompts.addAll(package.userPrompts);
    
    // 3. 添加公开提示词
    for (final publicPrompt in package.publicPrompts) {
      final publicPromptAsUser = UserPromptInfo(
        id: 'public_${publicPrompt.id}',
        name: '${publicPrompt.name} ${publicPrompt.isVerified ? '✓' : ''}',
        description: '${publicPrompt.description ?? ''} (作者: ${publicPrompt.authorName ?? '匿名'})',
        featureType: featureType,
        systemPrompt: publicPrompt.systemPrompt,
        userPrompt: publicPrompt.userPrompt,
        tags: const ['公开模板'],
        categories: publicPrompt.categories,
        isPublic: true,
        shareCode: publicPrompt.shareCode,
        isVerified: publicPrompt.isVerified,
        usageCount: publicPrompt.usageCount.toInt(),
        favoriteCount: publicPrompt.favoriteCount.toInt(),
        rating: publicPrompt.rating ?? 0.0,
        authorId: publicPrompt.authorName,
        version: publicPrompt.version,
        language: publicPrompt.language,
        createdAt: publicPrompt.createdAt,
        lastUsedAt: publicPrompt.lastUsedAt,
        updatedAt: publicPrompt.updatedAt,
        hidePrompts: publicPrompt.hidePrompts,
        settingGenerationConfig: publicPrompt.settingGenerationConfig, // 🆕 传递设定生成配置
      );
      allPrompts.add(publicPromptAsUser);
    }
    
    return allPrompts;
  }

  /// 构建功能类型分组
  Widget _buildFeatureTypeSection(
    AIFeatureType featureType,
    List<UserPromptInfo> prompts,
    PromptNewState state,
  ) {
    final isDark = WebTheme.isDarkMode(context);
    
    return ExpansionTile(
      initiallyExpanded: true,
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: EdgeInsets.zero,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _getFeatureTypeColor(featureType).withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          _getFeatureTypeIcon(featureType),
          size: 14,
          color: _getFeatureTypeColor(featureType),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _getFeatureTypeName(featureType),
              style: WebTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          
          // 数量徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${prompts.length}',
              style: WebTheme.labelSmall.copyWith(
                color: WebTheme.getSecondaryTextColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 新建按钮
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? WebTheme.darkGrey200 : WebTheme.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  context.read<PromptNewBloc>().add(CreateNewPrompt(
                    featureType: featureType,
                  ));
                },
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 展开/折叠图标
          Icon(
            Icons.expand_more,
            size: 20,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ],
      ),
      children: prompts.map((prompt) => _buildPromptItem(prompt, featureType, state)).toList(),
    );
  }

  /// 构建提示词条目
  Widget _buildPromptItem(
    UserPromptInfo prompt,
    AIFeatureType featureType,
    PromptNewState state,
  ) {
    final isDark = WebTheme.isDarkMode(context);
    final isSelected = state.selectedPromptId == prompt.id;
    final isSystemDefault = prompt.id.startsWith('system_default_');
    final isPublicTemplate = prompt.id.startsWith('public_');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected 
            ? (isDark ? WebTheme.darkGrey200 : WebTheme.grey100)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isSelected 
            ? Border.all(
                color: isDark ? WebTheme.darkGrey400 : WebTheme.grey400, 
                width: 1
              )
            : Border.all(color: Colors.transparent, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            widget.onPromptSelected(prompt.id, featureType);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 左侧图标
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _getPromptTypeColor(isSystemDefault, isPublicTemplate).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _getPromptTypeIcon(isSystemDefault, isPublicTemplate),
                    size: 12,
                    color: _getPromptTypeColor(isSystemDefault, isPublicTemplate),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // 主要内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              prompt.name,
                              style: WebTheme.bodyMedium.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected 
                                    ? WebTheme.getTextColor(context)
                                    : WebTheme.getTextColor(context, isPrimary: false),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // 状态标签
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 默认标签
                              if (prompt.isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark 
                                        ? const Color(0xFF4A4A4A) 
                                        : const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '默认',
                                    style: WebTheme.labelSmall.copyWith(
                                      color: isDark 
                                          ? const Color(0xFFFFB74D)
                                          : const Color(0xFFE65100),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              
                              if (prompt.isDefault && prompt.isFavorite)
                                const SizedBox(width: 4),
                              
                              // 收藏图标
                              if (prompt.isFavorite)
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isDark 
                                        ? const Color(0xFF4A4A4A) 
                                        : const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Icon(
                                    Icons.star,
                                    size: 10,
                                    color: isDark 
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFFFF8F00),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      
                      if (prompt.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          prompt.description!,
                          style: WebTheme.bodySmall.copyWith(
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // 类型标签（共享）
                ManagementTypeChip(
                  type: isSystemDefault
                      ? 'System'
                      : isPublicTemplate
                          ? 'Public'
                          : 'Custom',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 类型标签由共享组件 ManagementTypeChip 提供
  
  /// 获取提示词类型图标
  IconData _getPromptTypeIcon(bool isSystemDefault, bool isPublicTemplate) {
    if (isSystemDefault) return Icons.settings;
    if (isPublicTemplate) return Icons.public;
    return Icons.person;
  }
  
  /// 获取提示词类型颜色
  Color _getPromptTypeColor(bool isSystemDefault, bool isPublicTemplate) {
    if (isSystemDefault) return const Color(0xFF1565C0); // 优雅的蓝色
    if (isPublicTemplate) return const Color(0xFF2E7D32); // 优雅的绿色
    return const Color(0xFF7B1FA2); // 优雅的紫色
  }
  
  /// 获取功能类型图标
  IconData _getFeatureTypeIcon(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return Icons.summarize;
      case AIFeatureType.summaryToScene:
        return Icons.expand_more;
      case AIFeatureType.textExpansion:
        return Icons.unfold_more;
      case AIFeatureType.textRefactor:
        return Icons.edit;
      case AIFeatureType.textSummary:
        return Icons.notes;
      case AIFeatureType.aiChat:
        return Icons.chat;
      case AIFeatureType.novelGeneration:
        return Icons.create;
      case AIFeatureType.novelCompose:
        return Icons.dashboard_customize; // 编排/组合的语义
      case AIFeatureType.professionalFictionContinuation:
        return Icons.auto_stories;
      case AIFeatureType.sceneBeatGeneration:
        return Icons.timeline;
      case AIFeatureType.settingTreeGeneration:
        return Icons.account_tree;
      case AIFeatureType.settingGenerationTool:
        return Icons.build; // 工具图标
      case AIFeatureType.storyPlotContinuation:
        return Icons.auto_fix_high;
      case AIFeatureType.knowledgeExtractionSetting:
        return Icons.import_contacts; // 知识库图标
      case AIFeatureType.knowledgeExtractionOutline:
        return Icons.list_alt; // 大纲图标
    }
  }
  
  /// 获取功能类型颜色
  Color _getFeatureTypeColor(AIFeatureType featureType) {
    switch (featureType) {
      case AIFeatureType.sceneToSummary:
        return const Color(0xFF1976D2); // 蓝色
      case AIFeatureType.summaryToScene:
        return const Color(0xFF388E3C); // 绿色
      case AIFeatureType.textExpansion:
        return const Color(0xFF7B1FA2); // 紫色
      case AIFeatureType.textRefactor:
        return const Color(0xFFE64A19); // 深橙色
      case AIFeatureType.textSummary:
        return const Color(0xFF5D4037); // 棕色
      case AIFeatureType.aiChat:
        return const Color(0xFF0288D1); // 青色
      case AIFeatureType.novelGeneration:
        return const Color(0xFFD32F2F); // 红色
      case AIFeatureType.novelCompose:
        return const Color(0xFFD32F2F); // 与生成保持一致
      case AIFeatureType.professionalFictionContinuation:
        return const Color(0xFF303F9F); // 靛蓝色
      case AIFeatureType.sceneBeatGeneration:
        return const Color(0xFF795548); // 棕色
      case AIFeatureType.settingTreeGeneration:
        return const Color(0xFF689F38); // 浅绿色
      case AIFeatureType.settingGenerationTool:
        return const Color(0xFF757575); // 灰色
      case AIFeatureType.storyPlotContinuation:
        return const Color(0xFF8E24AA); // 紫色系
      case AIFeatureType.knowledgeExtractionSetting:
        return const Color(0xFFFF6F00); // 橙色
      case AIFeatureType.knowledgeExtractionOutline:
        return const Color(0xFFF57C00); // 深橙
    }
  }

  /// 获取功能类型名称（中文）
  String _getFeatureTypeName(AIFeatureType featureType) {
    // 使用 displayName 扩展方法返回中文名称
    return featureType.displayName;
  }
} 