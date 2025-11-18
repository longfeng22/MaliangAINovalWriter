import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/novel_summary.dart';
import 'package:ainoval/services/api_service/repositories/novel_snippet_repository.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/loading_indicator.dart';
import 'package:ainoval/widgets/common/empty_state_placeholder.dart';
import 'package:ainoval/widgets/common/search_action_bar.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'dart:async';
// 🎯 拖放功能
import 'package:ainoval/models/context_drag_data.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/widgets/common/draggable_context_item.dart';

/// 片段列表标签页
class SnippetListTab extends StatefulWidget {
  final NovelSummary novel;
  final Function(NovelSnippet)? onSnippetTap;
  final Function(VoidCallback)? onRefreshCallbackChanged;
  final Function(Function(NovelSnippet))? onAddSnippetCallbackChanged;
  final Function(Function(NovelSnippet))? onUpdateSnippetCallbackChanged;
  final Function(Function(String))? onRemoveSnippetCallbackChanged;

  const SnippetListTab({
    super.key,
    required this.novel,
    this.onSnippetTap,
    this.onRefreshCallbackChanged,
    this.onAddSnippetCallbackChanged,
    this.onUpdateSnippetCallbackChanged,
    this.onRemoveSnippetCallbackChanged,
  });

  @override
  State<SnippetListTab> createState() => _SnippetListTabState();
}

class _SnippetListTabState extends State<SnippetListTab> 
    with AutomaticKeepAliveClientMixin<SnippetListTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  List<NovelSnippet> _snippets = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String _searchText = '';
  
  late NovelSnippetRepository _snippetRepository;
  // 事件订阅
  StreamSubscription<SnippetCreatedEvent>? _snippetCreatedSubscription;

  @override
  bool get wantKeepAlive => true; // 🚀 保持页面存活状态

  @override
  void initState() {
    super.initState();
    _snippetRepository = context.read<NovelSnippetRepository>();
    _scrollController.addListener(_onScroll);
    _loadSnippets();
    
    // 通知父组件各种回调方法
    widget.onRefreshCallbackChanged?.call(refreshSnippets);
    widget.onAddSnippetCallbackChanged?.call(addSnippet);
    widget.onUpdateSnippetCallbackChanged?.call(updateSnippet);
    widget.onRemoveSnippetCallbackChanged?.call(removeSnippet);
    // 订阅片段创建事件
    _snippetCreatedSubscription = EventBus.instance
        .on<SnippetCreatedEvent>()
        .listen((event) {
      if (event.snippet.novelId == widget.novel.id) {
        addSnippet(event.snippet);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _snippetCreatedSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (!_isLoading && _hasMore) {
        _loadMoreSnippets();
      }
    }
  }

  Future<void> _loadSnippets() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _snippets.clear();
    });

    try {
      late SnippetPageResult<NovelSnippet> result;
      
      if (_searchText.isNotEmpty) {
        result = await _snippetRepository.searchSnippets(
          widget.novel.id,
          _searchText,
          page: _currentPage,
          size: 20,
        );
      } else {
        result = await _snippetRepository.getSnippetsByNovelId(
          widget.novel.id,
          page: _currentPage,
          size: 20,
        );
      }

      setState(() {
        _snippets = result.content;
        _hasMore = result.hasNext;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.e('SnippetListTab', '加载片段失败', e);
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载片段失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreSnippets() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      late SnippetPageResult<NovelSnippet> result;
      
      if (_searchText.isNotEmpty) {
        result = await _snippetRepository.searchSnippets(
          widget.novel.id,
          _searchText,
          page: _currentPage + 1,
          size: 20,
        );
      } else {
        result = await _snippetRepository.getSnippetsByNovelId(
          widget.novel.id,
          page: _currentPage + 1,
          size: 20,
        );
      }

      setState(() {
        _snippets.addAll(result.content);
        _hasMore = result.hasNext;
        _currentPage++;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.e('SnippetListTab', '加载更多片段失败', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    if (_searchText != value) {
      _searchText = value;
      _loadSnippets();
    }
  }

  /// 刷新片段列表（公共方法）
  void refreshSnippets() {
    _loadSnippets();
  }

  /// 添加新片段到列表顶部（公共方法）
  void addSnippet(NovelSnippet snippet) {
    setState(() {
      // 避免重复添加
      _snippets.removeWhere((s) => s.id == snippet.id);
      _snippets.insert(0, snippet); // 添加到列表顶部
    });
  }

  /// 更新现有片段（公共方法）
  void updateSnippet(NovelSnippet updatedSnippet) {
    setState(() {
      final index = _snippets.indexWhere((s) => s.id == updatedSnippet.id);
      if (index != -1) {
        _snippets[index] = updatedSnippet;
      }
    });
  }

  /// 删除片段（公共方法）
  void removeSnippet(String snippetId) {
    setState(() {
      _snippets.removeWhere((s) => s.id == snippetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🚀 必须调用父类的build方法
    final isDark = WebTheme.isDarkMode(context);
    
    return Container(
      color: WebTheme.getBackgroundColor(context), // 🚀 修复：使用背景色而不是表面色
      child: Column(
      children: [
        // 搜索和操作栏
        SearchActionBar(
          searchController: _searchController,
          searchHint: '搜索片段...',
          newButtonText: '创建片段',
          onSearchChanged: _onSearchChanged,
          onFilterPressed: _showFilterDialog,
          onNewPressed: _showCreateSnippetDialog,
          onSettingsPressed: _showSnippetSettings,
          showFilterButton: true,
          showNewButton: true,
          showSettingsButton: true,
        ),
        
        // 片段统计信息
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '共 ${_snippets.length} 个片段',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
                ),
              ),
            ],
          ),
        ),
        
        // 片段列表
        Expanded(
          child: _buildSnippetList(),
        ),
      ],
      ),
    );
  }

  Widget _buildSnippetList() {
    if (_isLoading && _snippets.isEmpty) {
      return const Center(
        child: LoadingIndicator(
          message: '正在加载片段...',
          size: 32,
        ),
      );
    }

    if (_snippets.isEmpty) {
      return EmptyStatePlaceholder(
        icon: Icons.bookmark_border,
        title: '暂无片段',
        message: _searchText.isNotEmpty ? '未找到匹配的片段' : '还没有创建任何片段\n点击上方"创建片段"按钮创建第一个片段',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _snippets.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _snippets.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: LoadingIndicator(size: 24),
            ),
          );
        }

        final snippet = _snippets[index];
        return _buildSnippetItem(snippet);
      },
    );
  }

  Widget _buildSnippetItem(NovelSnippet snippet) {
    final isDark = WebTheme.isDarkMode(context);
    
    // 构建片段卡片UI
    final snippetCard = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
        border: Border.all(
          color: isDark ? WebTheme.darkGrey200 : WebTheme.grey200,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => widget.onSnippetTap?.call(snippet),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snippet.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? WebTheme.darkGrey900 : WebTheme.grey900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (snippet.isFavorite)
                    Icon(
                      Icons.star,
                      size: 16,
                      color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey600 : WebTheme.grey600,
                    ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 内容预览
              Text(
                snippet.content,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey600,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 12),
              
              // 元数据
              Row(
                children: [
                  Icon(
                    Icons.text_fields,
                    size: 12,
                    color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${snippet.metadata.wordCount}字',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(snippet.updatedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                    ),
                  ),
                  if (snippet.tags?.isNotEmpty == true) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.local_offer,
                      size: 12,
                      color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      snippet.tags!.first,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? WebTheme.darkGrey500 : WebTheme.grey500,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    // 🎯 包装为可拖动的上下文项
    if (snippet.id.isNotEmpty) {
      final dragData = ContextDragData(
        id: 'snippet_${snippet.id}',
        type: ContextSelectionType.snippets,
        title: snippet.title.isNotEmpty ? snippet.title : 'Unnamed Snippet',
        subtitle: snippet.content.length > 50 
            ? '${snippet.content.substring(0, 50)}...' 
            : snippet.content,
        metadata: {
          'snippetId': snippet.id,
          'wordCount': snippet.metadata.wordCount,
          'isFavorite': snippet.isFavorite,
        },
      );
      
      return DraggableContextItem(
        data: dragData,
        enableDrag: true,
        onDragStarted: () {
          AppLogger.d('SnippetListTab', '🎯 开始拖动片段: ${snippet.title}');
        },
        child: snippetCard,
      );
    }
    
    return snippetCard;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _showCreateSnippetDialog() {
    // 创建一个新的空片段用于创建模式
    final newSnippet = NovelSnippet(
      id: '', // 空ID表示创建模式
      userId: '',
      novelId: widget.novel.id,
      title: '',
      content: '',
      metadata: const SnippetMetadata(
        wordCount: 0,
        characterCount: 0,
        viewCount: 0,
        sortWeight: 0,
      ),
      isFavorite: false,
      status: 'draft',
      version: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 使用FloatingSnippetEditor显示表单
    widget.onSnippetTap?.call(newSnippet);
  }

  void _showFilterDialog() {
    // TODO: 实现过滤器对话框
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('过滤器功能待实现')),
    );
  }

  void _showSnippetSettings() {
    // TODO: 实现片段设置
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('片段设置功能待实现')),
    );
  }
} 