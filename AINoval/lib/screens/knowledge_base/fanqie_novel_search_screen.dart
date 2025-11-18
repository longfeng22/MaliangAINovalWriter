/// 番茄小说搜索页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/screens/knowledge_base/knowledge_base_detail_screen.dart';
import 'package:ainoval/screens/knowledge_base/widgets/knowledge_extraction_import_dialog.dart';

/// 番茄小说搜索页面
class FanqieNovelSearchScreen extends StatefulWidget {
  const FanqieNovelSearchScreen({Key? key}) : super(key: key);

  @override
  State<FanqieNovelSearchScreen> createState() => _FanqieNovelSearchScreenState();
}

class _FanqieNovelSearchScreenState extends State<FanqieNovelSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _lastQuery = '';
  List<FanqieNovelInfo>? _lastSearchResults; // 缓存搜索结果

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入小说名称')),
      );
      return;
    }
    
    if (query != _lastQuery) {
      _lastQuery = query;
      context.read<KnowledgeBaseBloc>().add(SearchFanqieNovels(query));
    }
  }

  void _navigateToDetail(FanqieNovelInfo novel) {
    // ✅ 统一使用知识库详情页面
    if (novel.cached == true && novel.knowledgeBaseId != null) {
      // 已缓存：显示知识库详情
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => KnowledgeBaseDetailScreen.fromKnowledgeBase(
            knowledgeBaseId: novel.knowledgeBaseId!,
          ),
        ),
      );
    } else {
      // 未缓存：显示小说详情和拆书提示
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => KnowledgeBaseDetailScreen.fromNovel(
            novel: novel,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 页面标题
        _buildPageHeader(),
        
        // 搜索栏
        _buildSearchSection(),
        
        // 搜索结果
        Expanded(
          child: BlocConsumer<KnowledgeBaseBloc, KnowledgeBaseState>(
            listener: (context, state) {
              // 缓存搜索结果
              if (state is FanqieSearchLoaded) {
                _lastSearchResults = state.novels;
              }
            },
            builder: (context, state) {
              // 只处理与搜索相关的状态，忽略详情页的错误
              if (state is FanqieSearchLoaded) {
                return _buildSearchResults(state.novels);
              } else if (state is KnowledgeBaseLoading) {
                // 如果有缓存结果，显示缓存结果；否则显示加载
                if (_lastSearchResults != null) {
                  return _buildSearchResults(_lastSearchResults!);
                }
                return _buildLoadingState();
              } else if (state is KnowledgeBaseError) {
                // 如果有缓存结果，显示缓存结果并用SnackBar提示错误
                if (_lastSearchResults != null) {
                  // 错误提示以SnackBar形式显示，不影响列表
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('操作失败: ${state.message}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  });
                  return _buildSearchResults(_lastSearchResults!);
                }
                // 只显示搜索错误，详情错误在详情页显示
                return _buildErrorState(state.message);
              } else if (state is FanqieNovelDetailLoaded || 
                         state is CacheStatusChecked ||
                         state is ExtractionTaskCreated ||
                         state is ExtractionTaskStatusUpdated) {
                // 详情页相关状态，保持显示搜索结果
                if (_lastSearchResults != null) {
                  return _buildSearchResults(_lastSearchResults!);
                }
              }
              
              // 初始状态或无缓存
              return _buildEmptyState();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          Text(
            'AI拆书',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '搜索番茄小说，AI智能拆解知识',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
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
                                  hintText: '请输入小说名称或作者',
                                  hintStyle: TextStyle(
                                    color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                                    fontSize: 14,
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
                        color: const Color(0xFFFF6600),
                        border: Border.all(
                          color: const Color(0xFFFF6600),
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
                // 提示信息（小屏幕移到下方）
                Text(
                  '支持搜索小说名称、作者名',
                  style: TextStyle(
                    fontSize: 13,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
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
                                hintText: '请输入小说名称或作者',
                                hintStyle: TextStyle(
                                  color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
                                  fontSize: 14,
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
                    color: const Color(0xFFFF6600),
                    border: Border.all(
                      color: const Color(0xFFFF6600),
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
                // 右侧提示信息
                Text(
                  '支持搜索小说名称、作者名',
                  style: TextStyle(
                    fontSize: 13,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    WebTheme.getPrimaryColor(context).withOpacity(0.1),
                    WebTheme.getPrimaryColor(context).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(48),
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: WebTheme.getPrimaryColor(context).withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '开始你的AI拆书之旅',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '支持两种拆书方式，灵活满足你的需求',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: WebTheme.getSecondaryTextColor(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // 两种拆书方式
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                // 番茄小说拆书
                _buildExtractionOptionCard(
                  icon: Icons.travel_explore,
                  title: '番茄小说拆书',
                  description: '搜索番茄小说库\n一键智能拆解',
                  color: const Color(0xFFFF6600),
                  buttonText: '请在左上方搜索',
                  onTap: () {
                    // 滚动到搜索框，提示用户搜索
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请在左上方搜索框输入小说名称开始搜索'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                // 导入我的小说拆书
                _buildExtractionOptionCard(
                  icon: Icons.upload_file,
                  title: '导入我的小说',
                  description: '上传本地小说文件\n创建专属知识库',
                  color: const Color(0xFF4CAF50),
                  buttonText: '开始',
                  onTap: () {
                    showKnowledgeExtractionImportDialog(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 功能说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
                border: Border.all(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: WebTheme.getPrimaryColor(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '拆书说明',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem('支持TXT、DOCX格式文件上传'),
                  _buildFeatureItem('AI智能提取文风叙事、人物情节等8大维度知识'),
                  _buildFeatureItem('可设为公开，分享你的知识库获得积分奖励'),
                  _buildFeatureItem('每获得1个点赞或引用，即可获得1积分'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    WebTheme.getPrimaryColor(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '正在搜索小说...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请稍候',
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<FanqieNovelInfo> novels) {
    if (novels.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: WebTheme.getSecondaryTextColor(context).withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                '未找到相关小说',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请尝试其他搜索关键词',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: novels.length,
      itemBuilder: (context, index) {
        final novel = novels[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: WebTheme.getSurfaceColor(context),
            border: Border.all(
              color: WebTheme.getBorderColor(context),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: () => _navigateToDetail(novel),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  Container(
                    width: 100,
                    height: 130, // 标准的100*130尺寸
                    decoration: BoxDecoration(
                      color: WebTheme.getBorderColor(context).withOpacity(0.1),
                      border: Border.all(
                        color: WebTheme.getBorderColor(context),
                        width: 1,
                      ),
                    ),
                    child: novel.coverImageUrl != null && novel.coverImageUrl!.isNotEmpty
                        ? Image.network(
                            novel.coverImageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / 
                                          loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              // 记录错误信息，帮助调试
                              print('图片加载失败: ${novel.coverImageUrl}, 错误: $error');
                              return Center(
                                child: Icon(
                                  Icons.book,
                                  color: WebTheme.getSecondaryTextColor(context),
                                  size: 40,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.book,
                              color: WebTheme.getSecondaryTextColor(context),
                              size: 40,
                            ),
                          ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 详情信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题
                        Text(
                          novel.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: WebTheme.getTextColor(context),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // 作者
                        if (novel.author != null)
                          Text(
                            '作者：${novel.author}',
                            style: TextStyle(
                              fontSize: 13,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                        
                        const SizedBox(height: 6),
                        
                        // 状态和章节数
                        Row(
                          children: [
                            if (novel.completionStatus != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(novel.completionStatus!).withOpacity(0.1),
                                  border: Border.all(
                                    color: _getStatusColor(novel.completionStatus!),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  novel.completionStatus!.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getStatusColor(novel.completionStatus!),
                                  ),
                                ),
                              ),
                            if (novel.completionStatus != null && novel.chapterCount != null)
                              const SizedBox(width: 8),
                            if (novel.chapterCount != null)
                              Text(
                                '${novel.chapterCount}章',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: WebTheme.getSecondaryTextColor(context),
                                ),
                              ),
                            const Spacer(),
                            // 已拆书标签
                            if (novel.cached == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '已拆书',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // 简介
                        if (novel.description != null && novel.description!.isNotEmpty)
                          Text(
                            novel.description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: WebTheme.getSecondaryTextColor(context),
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        
                        const SizedBox(height: 8),
                        
                        // 评分信息
                        if (novel.score != null && novel.score!.isNotEmpty)
                          Text(
                            '评分：${novel.score}',
                            style: TextStyle(
                              fontSize: 12,
                              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildErrorState(String message) {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                border: Border.all(
                  color: Colors.red.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.error_outline,
                size: 40,
                color: Colors.red.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '搜索失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                border: Border.all(
                  color: Colors.red.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 44,
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
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '重试',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
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
      ),
    ),
    );
  }

  Color _getStatusColor(NovelCompletionStatus status) {
    switch (status) {
      case NovelCompletionStatus.completed:
        return Colors.green;
      case NovelCompletionStatus.ongoing:
        return Colors.blue;
      case NovelCompletionStatus.paused:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// 构建拆书选项卡片
  Widget _buildExtractionOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 200,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                icon,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getSecondaryTextColor(context),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建功能说明列表项
  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: WebTheme.getPrimaryColor(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getSecondaryTextColor(context),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

