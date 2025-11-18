/// 知识库设定选择器组件
library;

import 'package:flutter/material.dart';
import 'package:ainoval/models/knowledge_base_integration_mode.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/services/api_service/repositories/knowledge_base_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 知识库设定选择器组件
class KnowledgeBaseSettingSelector extends StatefulWidget {
  /// 当前选中的知识库项目
  final List<SelectedKnowledgeBaseItem> selectedItems;
  
  /// 当选择变更时的回调
  final Function(List<SelectedKnowledgeBaseItem>) onSelectionChanged;
  
  /// 是否支持多选（混合模式和仿写模式支持多选，复用模式不支持）
  final bool multipleSelection;
  
  /// 提示文本
  final String hintText;

  const KnowledgeBaseSettingSelector({
    Key? key,
    required this.selectedItems,
    required this.onSelectionChanged,
    this.multipleSelection = true,
    this.hintText = '搜索知识库小说...',
  }) : super(key: key);

  @override
  State<KnowledgeBaseSettingSelector> createState() => _KnowledgeBaseSettingSelectorState();
}

class _KnowledgeBaseSettingSelectorState extends State<KnowledgeBaseSettingSelector> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<NovelKnowledgeBase> _searchResults = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  /// 搜索知识库小说
  Future<void> _searchKnowledgeBases(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showDropdown = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _showDropdown = true;
    });
    
    try {
      final repository = context.read<KnowledgeBaseRepository>();
      final response = await repository.queryMyKnowledgeBases(
        keyword: query.trim(),
        page: 0,
        size: 10,
      );
      
      if (!mounted) return;
      
      setState(() {
        // 转换为 NovelKnowledgeBase 列表
        _searchResults = response.items.map((card) {
          // 需要通过详情API获取完整信息，这里先用卡片数据创建简化版
          return NovelKnowledgeBase(
            id: card.id,
            title: card.title,
            description: card.description,
            coverImageUrl: card.coverImageUrl,
            author: card.author,
            isUserImported: true,
            completionStatus: card.completionStatus,
            tags: card.tags,
            status: CacheStatus.completed,
            cacheSuccess: true,
            referenceCount: card.referenceCount,
            viewCount: card.viewCount,
            likeCount: card.likeCount,
            isPublic: false,
            firstImportUserId: '',
            firstImportTime: card.importTime,
          );
        }).toList();
        _isSearching = false;
      });
    } catch (e) {
      AppLogger.e('KnowledgeBaseSettingSelector', '搜索知识库失败', e);
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }
  
  /// 添加知识库项
  void _addKnowledgeBaseItem(NovelKnowledgeBase kb) {
    // 检查是否已经添加
    if (widget.selectedItems.any((item) => item.knowledgeBaseId == kb.id)) {
      return;
    }
    
    // 如果是单选模式，清空现有选择
    List<SelectedKnowledgeBaseItem> newItems = widget.multipleSelection 
        ? List.from(widget.selectedItems) 
        : [];
    
    // 添加新项，默认选中所有分类
    newItems.add(SelectedKnowledgeBaseItem(
      knowledgeBaseId: kb.id,
      novelTitle: kb.title,
      selectedCategories: KnowledgeBaseSettingCategory.getAllNonCustomCategories(),
    ));
    
    widget.onSelectionChanged(newItems);
    
    // 清空搜索
    _searchController.clear();
    setState(() {
      _showDropdown = false;
      _searchResults = [];
    });
  }
  
  /// 移除知识库项
  void _removeKnowledgeBaseItem(String knowledgeBaseId) {
    final newItems = widget.selectedItems
        .where((item) => item.knowledgeBaseId != knowledgeBaseId)
        .toList();
    widget.onSelectionChanged(newItems);
  }
  
  /// 移除某个分类标签
  void _removeCategory(String knowledgeBaseId, KnowledgeBaseSettingCategory category) {
    final newItems = widget.selectedItems.map((item) {
      if (item.knowledgeBaseId == knowledgeBaseId) {
        final newCategories = item.selectedCategories
            .where((c) => c != category)
            .toList();
        
        // 如果没有分类了，直接移除整个项目
        if (newCategories.isEmpty) {
          return null;
        }
        
        return item.copyWith(selectedCategories: newCategories);
      }
      return item;
    }).whereType<SelectedKnowledgeBaseItem>().toList();
    
    widget.onSelectionChanged(newItems);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 搜索输入框
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: WebTheme.getBorderColor(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: WebTheme.getSecondaryTextColor(context),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: WebTheme.getSecondaryTextColor(context),
                size: 20,
              ),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: TextStyle(
              color: WebTheme.getTextColor(context),
              fontSize: 14,
            ),
            onChanged: (value) {
              // 防抖搜索
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_searchController.text == value) {
                  _searchKnowledgeBases(value);
                }
              });
            },
          ),
        ),
        
        // 搜索结果下拉框
        if (_showDropdown && _searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              border: Border.all(color: WebTheme.getBorderColor(context)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final kb = _searchResults[index];
                final isSelected = widget.selectedItems
                    .any((item) => item.knowledgeBaseId == kb.id);
                
                return ListTile(
                  dense: true,
                  leading: kb.coverImageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            kb.coverImageUrl!,
                            width: 32,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 32,
                                height: 48,
                                color: WebTheme.getBorderColor(context),
                                child: Icon(
                                  Icons.book,
                                  size: 16,
                                  color: WebTheme.getSecondaryTextColor(context),
                                ),
                              );
                            },
                          ),
                        )
                      : Container(
                          width: 32,
                          height: 48,
                          decoration: BoxDecoration(
                            color: WebTheme.getBorderColor(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.book,
                            size: 16,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                  title: Text(
                    kb.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: WebTheme.getTextColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: kb.author != null
                      ? Text(
                          kb.author!,
                          style: TextStyle(
                            fontSize: 12,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: WebTheme.getPrimaryColor(context),
                          size: 20,
                        )
                      : null,
                  onTap: isSelected ? null : () => _addKnowledgeBaseItem(kb),
                );
              },
            ),
          ),
        ],
        
        // 选中的知识库项目标签栏
        if (widget.selectedItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedItems.map((item) {
              return _buildKnowledgeBaseTag(item);
            }).toList(),
          ),
        ],
      ],
    );
  }
  
  /// 构建知识库标签（包含子分类标签）
  Widget _buildKnowledgeBaseTag(SelectedKnowledgeBaseItem item) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 小说标题标签
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.book,
                size: 14,
                color: WebTheme.getPrimaryColor(context),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  item.novelTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _removeKnowledgeBaseItem(item.knowledgeBaseId),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          
          // 分类标签
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: item.selectedCategories.map((category) {
              return _buildCategoryChip(item.knowledgeBaseId, category);
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// 构建分类标签芯片
  Widget _buildCategoryChip(String knowledgeBaseId, KnowledgeBaseSettingCategory category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border.all(
          color: WebTheme.getBorderColor(context),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            category.displayName,
            style: TextStyle(
              fontSize: 11,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _removeCategory(knowledgeBaseId, category),
            child: Icon(
              Icons.close,
              size: 12,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}


