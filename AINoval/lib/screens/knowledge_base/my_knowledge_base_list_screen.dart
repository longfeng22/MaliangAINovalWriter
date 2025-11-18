/// 我的知识库列表页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/responsive_font.dart';
import 'package:ainoval/screens/knowledge_base/widgets/knowledge_base_card.dart';
import 'package:ainoval/screens/knowledge_base/knowledge_base_detail_screen.dart';

/// 我的知识库列表页面
class MyKnowledgeBaseListScreen extends StatefulWidget {
  const MyKnowledgeBaseListScreen({Key? key}) : super(key: key);

  @override
  State<MyKnowledgeBaseListScreen> createState() => _MyKnowledgeBaseListScreenState();
}

class _MyKnowledgeBaseListScreenState extends State<MyKnowledgeBaseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 筛选和排序参数
  String? _keyword;
  String? _sourceType; // null=全部, 'user_imported'=用户导入, 'fanqie_novel'=番茄小说
  String _sortBy = 'importTime';
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
  
  // 布局模式
  String _viewMode = 'grid';
  
  // 缓存当前列表响应
  KnowledgeBaseListResponse? _cachedResponse;
  
  // 标记是否已经加载过数据
  bool _isInitialLoadDone = false;
  
  @override
  void initState() {
    super.initState();
    
    // 监听滚动
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
      LoadMyKnowledgeBases(
        keyword: _keyword,
        sourceType: _sourceType,
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

  void _navigateToDetail(KnowledgeBaseCard card) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KnowledgeBaseDetailScreen(
          knowledgeBaseId: card.id,
        ),
      ),
    );
    
    // 返回后刷新列表（因为可能删除了）
    _loadData();
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
        
        // 排序栏
        _buildFilterBar(),
        
        const SizedBox(height: 16),
        
        // 内容区域
        Expanded(
          child: BlocBuilder<KnowledgeBaseBloc, KnowledgeBaseState>(
            builder: (context, state) {
              if (state is KnowledgeBaseLoading) {
                // 加载中，如果有缓存数据，显示缓存的列表
                if (_cachedResponse != null) {
                  return _buildContentList(_cachedResponse!);
                }
                return _buildLoadingState();
              } else if (state is KnowledgeBaseListLoaded && !state.isPublicList) {
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
                // 其他状态，显示缓存的列表
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
                  '我的知识库',
                  style: TextStyle(
                    fontSize: ResponsiveFontSize.pageTitle(context),
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: ResponsiveSpacing.xxs(context)),
                Text(
                  '管理您导入和创建的小说知识库',
                  style: TextStyle(
                    fontSize: ResponsiveFontSize.bodySmall(context),
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
                                  hintText: '搜索我的知识库...',
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
                      '共 $totalCount 个知识库',
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
                                hintText: '搜索我的知识库...',
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
                      '共 $totalCount 个知识库',
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
          // 来源筛选
          _buildSourceFilterChips(),
          
          const SizedBox(width: 16),
          
          // 排序选择
          _buildSortDropdown(),
          
          const Spacer(),
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
          value: {'sortBy': 'importTime', 'sortOrder': 'desc'},
          child: Text('按时间（最新）'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'importTime', 'sortOrder': 'asc'},
          child: Text('按时间（最早）'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'likeCount', 'sortOrder': 'desc'},
          child: Text('按点赞数'),
        ),
        const PopupMenuItem(
          value: {'sortBy': 'referenceCount', 'sortOrder': 'desc'},
          child: Text('按引用数'),
        ),
      ],
      onSelected: (value) {
        _handleSortChange(value['sortBy']!, value['sortOrder']!);
      },
    );
  }

  String _getSortLabel() {
    if (_sortBy == 'importTime' && _sortOrder == 'desc') return '最新';
    if (_sortBy == 'importTime' && _sortOrder == 'asc') return '最早';
    if (_sortBy == 'likeCount') return '点赞数';
    if (_sortBy == 'referenceCount') return '引用数';
    return '排序';
  }

  Widget _buildSourceFilterChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '来源：',
          style: TextStyle(
            fontSize: 13,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: '全部',
          isSelected: _sourceType == null,
          onTap: () {
            setState(() {
              _sourceType = null;
              _currentPage = 0;
            });
            _loadData();
          },
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: '我的导入',
          icon: Icons.upload_file,
          isSelected: _sourceType == 'user_imported',
          onTap: () {
            setState(() {
              _sourceType = 'user_imported';
              _currentPage = 0;
            });
            _loadData();
          },
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: '番茄小说',
          icon: Icons.travel_explore,
          isSelected: _sourceType == 'fanqie_novel',
          onTap: () {
            setState(() {
              _sourceType = 'fanqie_novel';
              _currentPage = 0;
            });
            _loadData();
          },
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected
          ? WebTheme.getPrimaryColor(context).withOpacity(0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? WebTheme.getPrimaryColor(context)
                  : WebTheme.getBorderColor(context),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? WebTheme.getPrimaryColor(context)
                      : WebTheme.getSecondaryTextColor(context),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? WebTheme.getPrimaryColor(context)
                      : WebTheme.getTextColor(context),
                ),
              ),
            ],
          ),
        ),
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
            '还没有知识库',
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
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: 导航到番茄小说搜索页面
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('开始拆书'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

