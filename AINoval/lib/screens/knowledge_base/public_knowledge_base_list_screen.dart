/// 公共知识库列表页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/screens/knowledge_base/widgets/knowledge_base_card.dart';
import 'package:ainoval/screens/knowledge_base/knowledge_base_detail_screen.dart';

/// 公共知识库列表页面
/// 
/// 淘宝式布局：
/// - 顶部搜索栏
/// - 标签筛选 + 排序
/// - 网格/列表展示知识库卡片
class PublicKnowledgeBaseListScreen extends StatefulWidget {
  const PublicKnowledgeBaseListScreen({Key? key}) : super(key: key);

  @override
  State<PublicKnowledgeBaseListScreen> createState() => _PublicKnowledgeBaseListScreenState();
}

class _PublicKnowledgeBaseListScreenState extends State<PublicKnowledgeBaseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 筛选和排序参数
  String? _keyword;
  List<String> _selectedTags = [];
  String? _completionStatus;
  String _sortBy = 'likeCount';
  String _sortOrder = 'desc';
  int _currentPage = 0;
  
  // 响应式分页：根据屏幕尺寸和网格列数动态计算每页显示数量
  int _getPageSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = _getGridCrossAxisCount(context);
    
    // 目标：每页显示大约4-6行
    const targetRows = 5;
    int pageSize = crossAxisCount * targetRows;
    
    // 根据屏幕大小调整
    if (width > 2560) {
      // 4K屏：6列 × 6行 = 36
      pageSize = crossAxisCount * 6;
    } else if (width > 1920) {
      // 2K屏：5列 × 5行 = 25
      pageSize = crossAxisCount * 5;
    } else if (width > 1440) {
      // 大屏：4列 × 5行 = 20
      pageSize = crossAxisCount * 5;
    } else if (width > 1200) {
      // 中屏：3列 × 5行 = 15
      pageSize = crossAxisCount * 5;
    } else if (width > 800) {
      // 小屏：2列 × 6行 = 12
      pageSize = crossAxisCount * 6;
    } else {
      // 移动端：1列 × 10行 = 10
      pageSize = 10;
    }
    
    // 限制范围：最小10，最大50
    return pageSize.clamp(10, 50);
  }
  
  // 布局模式: grid or list
  String _viewMode = 'grid';
  
  // 缓存当前列表响应，避免状态切换时丢失数据
  KnowledgeBaseListResponse? _cachedResponse;
  
  // 标记是否已经加载过数据
  bool _isInitialLoadDone = false;
  
  @override
  void initState() {
    super.initState();
    
    // 监听滚动，实现加载更多
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 只在第一次加载数据
    if (!_isInitialLoadDone) {
      _isInitialLoadDone = true;
      _loadData();
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    context.read<KnowledgeBaseBloc>().add(
      LoadPublicKnowledgeBases(
        keyword: _keyword,
        tags: _selectedTags.isEmpty ? null : _selectedTags,
        completionStatus: _completionStatus,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        page: _currentPage,
        size: _getPageSize(context),
      ),
    );
  }

  // 计算总页数
  int _getTotalPages() {
    if (_cachedResponse == null || _cachedResponse!.totalCount == 0) {
      return 1;
    }
    return (_cachedResponse!.totalCount / _getPageSize(context)).ceil();
  }

  // 上一页
  void _goToPreviousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
      _loadData();
    }
  }

  // 下一页
  void _goToNextPage() {
    final totalPages = _getTotalPages();
    if (_currentPage < totalPages - 1) {
      setState(() {
        _currentPage++;
      });
      _loadData();
    }
  }

  void _onScroll() {
    // 移除滚动加载逻辑，使用分页按钮
  }

  void _handleSearch() {
    setState(() {
      _keyword = _searchController.text.trim().isEmpty 
          ? null 
          : _searchController.text.trim();
      _currentPage = 0;
    });
    _loadData();
  }

  void _handleSortChange(String sortBy, String sortOrder) {
    setState(() {
      _sortBy = sortBy;
      _sortOrder = sortOrder;
      _currentPage = 0;
    });
    _loadData();
  }

  void _handleStatusFilter(String? status) {
    setState(() {
      _completionStatus = status;
      _currentPage = 0;
    });
    _loadData();
  }

  void _handleTagToggle(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
      _currentPage = 0;
    });
    _loadData();
  }

  void _navigateToDetail(KnowledgeBaseCard card) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KnowledgeBaseDetailScreen(
          knowledgeBaseId: card.id,
        ),
      ),
    );
    
    // 返回后可以选择刷新列表
    // _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 页面标题和视图切换
        _buildPageHeader(),
        
        const SizedBox(height: 24),
        
        // 搜索栏
        _buildSearchBar(),
        
        const SizedBox(height: 16),
        
        // 筛选和排序栏
        _buildFilterBar(),
        
        // 标签筛选（可选）
        if (_selectedTags.isNotEmpty || _completionStatus != null) ...[
          const SizedBox(height: 12),
          _buildActiveFilters(),
        ],
        
        const SizedBox(height: 16),
        
        // 内容区域
        Expanded(
          child: BlocBuilder<KnowledgeBaseBloc, KnowledgeBaseState>(
            builder: (context, state) {
              if (state is KnowledgeBaseLoading) {
                // 加载中，如果有缓存数据，显示缓存的列表，否则显示加载状态
                if (_cachedResponse != null) {
                  return _buildContentList(_cachedResponse!);
                }
                return _buildLoadingState();
              } else if (state is KnowledgeBaseListLoaded && state.isPublicList) {
                // 更新缓存
                _cachedResponse = state.response;
                return _buildContentList(state.response);
              } else if (state is KnowledgeBaseError) {
                // 错误状态，如果有缓存数据仍然显示
                if (_cachedResponse != null) {
                  return _buildContentList(_cachedResponse!);
                }
                return _buildErrorState(state.message);
              } else if (_cachedResponse != null) {
                // 其他状态（如OperationSuccess等），显示缓存的列表
                return _buildContentList(_cachedResponse!);
              }
              
              return _buildEmptyState();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  WebTheme.getPrimaryColor(context),
                  WebTheme.getPrimaryColor(context).withOpacity(0.5),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '公共知识库',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '探索社区共享的优质小说知识库',
                  style: TextStyle(
                    fontSize: 14,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          // 视图切换按钮
          Container(
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: WebTheme.getBorderColor(context).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _buildViewModeButton(
                  icon: Icons.grid_view,
                  isSelected: _viewMode == 'grid',
                  onTap: () => setState(() => _viewMode = 'grid'),
                  tooltip: '网格视图',
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: WebTheme.getBorderColor(context).withOpacity(0.3),
                ),
                _buildViewModeButton(
                  icon: Icons.view_list,
                  isSelected: _viewMode == 'list',
                  onTap: () => setState(() => _viewMode = 'list'),
                  tooltip: '列表视图',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isSelected
            ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 20,
              color: isSelected
                  ? WebTheme.getPrimaryColor(context)
                  : WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border.all(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: isSmallScreen
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 搜索框和按钮
                Row(
                  children: [
                    // 搜索框 - 自适应宽度
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: WebTheme.getBackgroundColor(context),
                          border: Border.all(
                            color: WebTheme.getBorderColor(context),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Icon(
                              Icons.search,
                              size: 18,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: WebTheme.getTextColor(context),
                                ),
                                decoration: InputDecoration(
                                  hintText: '搜索知识库名称、作者...',
                                  hintStyle: TextStyle(
                                    color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _handleSearch(),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 搜索按钮
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: WebTheme.getPrimaryColor(context),
                        border: Border.all(
                          color: WebTheme.getPrimaryColor(context),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleSearch,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.search,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '搜索',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 统计信息（小屏幕移到下方）
                BlocBuilder<KnowledgeBaseBloc, KnowledgeBaseState>(
                  builder: (context, state) {
                    final totalCount = _cachedResponse?.totalCount ?? 0;
                    return Text(
                      '共找到 $totalCount 个知识库',
                      style: TextStyle(
                        fontSize: 13,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    );
                  },
                ),
              ],
            )
          : Row(
              children: [
                // 搜索框 - 响应式宽度
                Flexible(
                  flex: 3,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 300,
                      maxWidth: 500,
                    ),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: WebTheme.getBackgroundColor(context),
                        border: Border.all(
                          color: WebTheme.getBorderColor(context),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            Icons.search,
                            size: 18,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                fontSize: 14,
                                color: WebTheme.getTextColor(context),
                              ),
                              decoration: InputDecoration(
                                hintText: '搜索知识库名称、作者...',
                                hintStyle: TextStyle(
                                  color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _handleSearch(),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 搜索按钮
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: WebTheme.getPrimaryColor(context),
                    border: Border.all(
                      color: WebTheme.getPrimaryColor(context),
                      width: 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _handleSearch,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '搜索',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // 右侧统计信息
                BlocBuilder<KnowledgeBaseBloc, KnowledgeBaseState>(
                  builder: (context, state) {
                    final totalCount = _cachedResponse?.totalCount ?? 0;
                    return Text(
                      '共找到 $totalCount 个知识库',
                      style: TextStyle(
                        fontSize: 13,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 排序选择
          _buildSortDropdown(),
          
          const Spacer(),
          
          // 状态筛选
          _buildStatusFilter(),
        ],
      ),
    );
  }

  Widget _buildSortDropdown() {
    return PopupMenuButton<Map<String, String>>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort,
              size: 18,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              _getSortLabel(),
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: {'sortBy': 'likeCount', 'sortOrder': 'desc'},
          child: Text('按点赞数'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'referenceCount', 'sortOrder': 'desc'},
          child: Text('按引用数'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'importTime', 'sortOrder': 'desc'},
          child: Text('按时间（最新）'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'importTime', 'sortOrder': 'asc'},
          child: Text('按时间（最早）'),
        ),
      ],
      onSelected: (value) {
        _handleSortChange(value['sortBy']!, value['sortOrder']!);
      },
    );
  }

  String _getSortLabel() {
    if (_sortBy == 'likeCount') return '点赞数';
    if (_sortBy == 'referenceCount') return '引用数';
    if (_sortBy == 'importTime' && _sortOrder == 'desc') return '最新';
    if (_sortBy == 'importTime' && _sortOrder == 'asc') return '最早';
    return '排序';
  }

  Widget _buildStatusFilter() {
    return PopupMenuButton<String?>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: _completionStatus != null 
                ? WebTheme.getPrimaryColor(context)
                : WebTheme.getBorderColor(context),
            width: 1,
          ),
          color: _completionStatus != null
              ? WebTheme.getPrimaryColor(context).withOpacity(0.1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 18,
              color: _completionStatus != null
                  ? WebTheme.getPrimaryColor(context)
                  : WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              _completionStatus != null ? _getStatusLabel(_completionStatus!) : '状态',
              style: TextStyle(
                fontSize: 13,
                color: _completionStatus != null
                    ? WebTheme.getPrimaryColor(context)
                    : WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: _completionStatus != null
                  ? WebTheme.getPrimaryColor(context)
                  : WebTheme.getSecondaryTextColor(context),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: null,
          child: Text('全部状态'),
        ),
        const PopupMenuItem(
          value: 'COMPLETED',
          child: Text('已完结'),
        ),
        const PopupMenuItem(
          value: 'ONGOING',
          child: Text('连载中'),
        ),
        const PopupMenuItem(
          value: 'PAUSED',
          child: Text('暂停中'),
        ),
      ],
      onSelected: _handleStatusFilter,
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'COMPLETED':
        return '已完结';
      case 'ONGOING':
        return '连载中';
      case 'PAUSED':
        return '暂停中';
      default:
        return '状态';
    }
  }

  Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_completionStatus != null)
            _buildFilterChip(
              label: _getStatusLabel(_completionStatus!),
              onRemove: () => _handleStatusFilter(null),
            ),
          ..._selectedTags.map((tag) => _buildFilterChip(
                label: tag,
                onRemove: () => _handleTagToggle(tag),
              )),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onRemove}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getPrimaryColor(context),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: Icon(
                Icons.close,
                size: 16,
                color: WebTheme.getPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildContentList(KnowledgeBaseListResponse response) {
    if (response.items.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        Expanded(
          child: _viewMode == 'grid' 
              ? _buildGridView(response.items) 
              : _buildListView(response.items),
        ),
        // 分页控件
        _buildPagination(),
      ],
    );
  }

  Widget _buildGridView(List<KnowledgeBaseCard> items) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16), // 适中的外边距
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getGridCrossAxisCount(context),
        crossAxisSpacing: 16, // 增加列间距
        mainAxisSpacing: 16, // 增加行间距
        childAspectRatio: 2.52, // 328px/130px的比例
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return KnowledgeBaseCardWidget(
          card: items[index],
          onTap: () => _navigateToDetail(items[index]),
        );
      },
    );
  }

  Widget _buildListView(List<KnowledgeBaseCard> items) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return KnowledgeBaseCardWidget(
          card: items[index],
          onTap: () => _navigateToDetail(items[index]),
          isListMode: true,
        );
      },
    );
  }

  // 为横向卡片专门的列数计算
  int _getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 2560) return 6; // 4K及以上屏幕显示6列
    if (width > 1920) return 5; // 2K屏幕显示5列
    if (width > 1440) return 4; // 大屏显示4列
    if (width > 1200) return 3; // 中屏显示3列
    if (width > 800) return 2; // 小屏显示2列
    return 1; // 最小屏显示1列
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books,
            size: 64,
            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无知识库',
            style: TextStyle(
              fontSize: 16,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快去拆书创建第一个知识库吧！',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[300],
          ),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 16,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建分页控件
  Widget _buildPagination() {
    final totalPages = _getTotalPages();
    final totalCount = _cachedResponse?.totalCount ?? 0;
    final pageSize = _getPageSize(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          top: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧信息
          Text(
            '共 $totalCount 个知识库，每页 $pageSize 个',
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          // 中间分页按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 上一页按钮
              IconButton(
                icon: const Icon(Icons.chevron_left),
                iconSize: 20,
                color: _currentPage > 0
                    ? WebTheme.getTextColor(context)
                    : WebTheme.getSecondaryTextColor(context).withOpacity(0.3),
                onPressed: _currentPage > 0 ? _goToPreviousPage : null,
                tooltip: '上一页',
              ),
              const SizedBox(width: 8),
              // 页码显示
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: WebTheme.getBackgroundColor(context),
                  border: Border.all(
                    color: WebTheme.getBorderColor(context),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${_currentPage + 1} / $totalPages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 下一页按钮
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                color: _currentPage < totalPages - 1
                    ? WebTheme.getTextColor(context)
                    : WebTheme.getSecondaryTextColor(context).withOpacity(0.3),
                onPressed: _currentPage < totalPages - 1 ? _goToNextPage : null,
                tooltip: '下一页',
              ),
            ],
          ),
          // 右侧占位，保持对称
          SizedBox(
            width: 200,
            child: Text(
              '显示 ${_currentPage * pageSize + 1}-${(_currentPage + 1) * pageSize > totalCount ? totalCount : (_currentPage + 1) * pageSize}',
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

