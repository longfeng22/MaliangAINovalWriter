/// 知识库详情页面
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/models/knowledge_base_models.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/utils/event_bus.dart';
import 'package:ainoval/screens/knowledge_base/widgets/setting_card_widget.dart';

/// 知识库详情页面
/// 
/// 支持两种模式：
/// 1. 已拆书模式：显示知识库内容，左右分栏布局
/// 2. 未拆书模式：显示拆书提示和小说信息
class KnowledgeBaseDetailScreen extends StatefulWidget {
  final String? knowledgeBaseId;  // 知识库ID（已拆书时使用）
  final FanqieNovelInfo? novel;   // 番茄小说信息（未拆书时使用）

  const KnowledgeBaseDetailScreen({
    Key? key,
    this.knowledgeBaseId,
    this.novel,
  }) : super(key: key);

  // 从知识库ID创建
  const KnowledgeBaseDetailScreen.fromKnowledgeBase({
    Key? key,
    required String knowledgeBaseId,
  }) : this(key: key, knowledgeBaseId: knowledgeBaseId, novel: null);

  // 从番茄小说创建
  const KnowledgeBaseDetailScreen.fromNovel({
    Key? key,
    required FanqieNovelInfo novel,
  }) : this(key: key, knowledgeBaseId: null, novel: novel);

  @override
  State<KnowledgeBaseDetailScreen> createState() => _KnowledgeBaseDetailScreenState();
}

class _KnowledgeBaseDetailScreenState extends State<KnowledgeBaseDetailScreen> 
    with SingleTickerProviderStateMixin {
  
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  
  // 拆书相关状态
  String? _currentTaskId; // 当前拆书任务ID
  bool _isExtracting = false; // 是否正在拆书
  StreamSubscription? _taskEventSub;
  
  // 缓存状态
  KnowledgeBaseCacheStatusResponse? _cacheStatus;
  
  // 我的知识库状态
  bool _isInMyKnowledgeBase = false;
  bool _isCheckingStatus = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    
    // 延迟执行，等待context可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.knowledgeBaseId != null) {
        // 已有知识库ID，直接加载知识库详情
        context.read<KnowledgeBaseBloc>().add(
          LoadKnowledgeBaseDetail(widget.knowledgeBaseId!),
        );
        
        // 检查是否在我的知识库中
        _checkIsInMyKnowledgeBase();
      } else if (widget.novel != null) {
        // 番茄小说模式，检查缓存状态
        context.read<KnowledgeBaseBloc>().add(
          CheckCacheStatus(widget.novel!.novelId),
        );
        
        // 监听拆书任务事件
        _setupTaskEventListener();
      }
    });
  }

  void _setupTaskEventListener() {
    _taskEventSub = EventBus.instance.on<TaskEventReceived>().listen((evt) {
      final ev = evt.event;
      final taskId = (ev['taskId'] ?? '').toString();
      final taskType = (ev['taskType'] ?? '').toString();
      final type = (ev['type'] ?? '').toString();
      
      // 只处理当前任务的事件
      if (taskId != _currentTaskId || taskType != 'KNOWLEDGE_EXTRACTION_FANQIE') {
        return;
      }
      
      AppLogger.i('KnowledgeBaseDetailScreen', '收到拆书任务事件: type=$type, taskId=$taskId');
      
      // 任务完成
      if (type == 'TASK_COMPLETED') {
        if (mounted) {
          setState(() {
            _isExtracting = false;
            _currentTaskId = null;
          });
          
          _showGlobalToast('《${widget.novel!.title}》拆书完成！');
          
          // 重新检查缓存状态
          context.read<KnowledgeBaseBloc>().add(CheckCacheStatus(widget.novel!.novelId));
        }
      }
      // 任务失败
      else if (type == 'TASK_FAILED') {
        if (mounted) {
          setState(() {
            _isExtracting = false;
            _currentTaskId = null;
          });
          
          final error = (ev['error'] ?? '未知错误').toString();
          _showGlobalToast('拆书失败: $error', isError: true);
        }
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _taskEventSub?.cancel();
    super.dispose();
  }

  void _handleLike() {
    if (widget.knowledgeBaseId != null) {
      context.read<KnowledgeBaseBloc>().add(
        ToggleKnowledgeBaseLike(widget.knowledgeBaseId!),
      );
    }
  }


  void _startExtraction() {
    if (widget.novel == null) return;
    
    context.read<KnowledgeBaseBloc>().add(
      ExtractFromFanqieNovel(
        fanqieNovelId: widget.novel!.novelId,
        extractionTypes: null, // 提取全部类型
      ),
    );
  }

  /// 显示全局Toast通知
  void _showGlobalToast(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isError 
                  ? Colors.red.shade50 
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isError 
                    ? Colors.red.shade200 
                    : Colors.green.shade200,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: isError ? Colors.red : Colors.green,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isError ? Colors.red.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // 3秒后自动移除
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 判断屏幕宽度，决定布局方式
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 900;

    return Scaffold(
      backgroundColor: WebTheme.getBackgroundColor(context),
      appBar: AppBar(
        title: Text(_getPageTitle()),
        backgroundColor: WebTheme.getSurfaceColor(context),
        elevation: 1,
      ),
      body: BlocConsumer<KnowledgeBaseBloc, KnowledgeBaseState>(
        listener: (context, state) {
          if (state is ExtractionTaskCreated) {
            // 开始拆书任务
            setState(() {
              _isExtracting = true;
              _currentTaskId = state.taskResponse.taskId;
            });
            
            // 只显示Toast提示，不弹出单独页面
            _showGlobalToast('已开始拆书《${widget.novel!.title}》，请稍候...');
          } else if (state is CacheStatusChecked) {
            // 缓存状态检查完成
            setState(() {
              _cacheStatus = state.cacheStatus;
            });
            
            if (state.cacheStatus.cached && state.cacheStatus.knowledgeBaseId != null) {
              // 已缓存，加载知识库详情
              context.read<KnowledgeBaseBloc>().add(
                LoadKnowledgeBaseDetail(state.cacheStatus.knowledgeBaseId!),
              );
            }
          } else if (state is KnowledgeBaseOperationSuccess) {
            // 操作成功（添加/删除知识库等）
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
            
            // 如果有知识库ID，重新加载详情以更新状态
            if (widget.knowledgeBaseId != null) {
              context.read<KnowledgeBaseBloc>().add(
                LoadKnowledgeBaseDetail(widget.knowledgeBaseId!),
              );
              // 重新检查是否在我的知识库中
              _checkIsInMyKnowledgeBase();
            }
          } else if (state is KnowledgeBaseError) {
            // 操作失败
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is KnowledgeBaseLoading && !_isExtracting) {
            return _buildLoadingState();
          } else if (state is KnowledgeBaseDetailLoaded) {
            // 统一显示知识库内容（已拆书状态）
            return isLargeScreen
                ? _buildLargeScreenLayout(state)
                : _buildSmallScreenLayout(state);
          } else if (state is KnowledgeBaseError && !_isExtracting) {
            return _buildErrorState(state.message);
          } else if (widget.novel != null && _cacheStatus != null && !_cacheStatus!.cached) {
            // 番茄小说模式且未拆书，创建临时知识库对象统一展示
            final tempKnowledgeBase = _createTempKnowledgeBase();
            final tempState = KnowledgeBaseDetailLoaded(
              knowledgeBase: tempKnowledgeBase, 
              isLiked: false,
            );
            
            return isLargeScreen
                ? _buildLargeScreenLayout(tempState)
                : _buildSmallScreenLayout(tempState);
          }
          
          return _buildLoadingState();
        },
      ),
    );
  }

  String _getPageTitle() {
    if (widget.novel != null) {
      return _cacheStatus?.cached == true ? '知识库详情' : '小说详情';
    }
    return '知识库详情';
  }

  /// 为未拆书的番茄小说创建临时知识库对象
  NovelKnowledgeBase _createTempKnowledgeBase() {
    final novel = widget.novel!;
    return NovelKnowledgeBase(
      id: 'temp_${novel.novelId}',
      fanqieNovelId: novel.novelId,
      title: novel.title,
      description: novel.description ?? '',
      author: novel.author,
      coverImageUrl: novel.coverImageUrl,
      isUserImported: false,
      completionStatus: novel.completionStatus,
      tags: novel.category != null ? [novel.category!] : null,
      
      // 空的设定列表，在右侧面板中根据是否拆书完成显示不同内容
      narrativeStyleSettings: [],
      characterPlotSettings: [],
      novelFeatureSettings: [],
      readerEmotionSettings: [],
      hotMemesSettings: [],
      customSettings: [],
      chapterOutlines: [], // 空章节列表，拆书完成后才有
      
      outlineNovelId: null,
      status: CacheStatus.pending,
      cacheSuccess: false,
      cacheFailureReason: null,
      cacheTime: null,
      referenceCount: 0,
      viewCount: 0,
      likeCount: 0,
      likedUserIds: null,
      isPublic: false,
      firstImportUserId: 'temp_user', // 临时用户ID
      firstImportTime: null,
      extractionTaskId: null,
      modelConfigId: null,
      modelType: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }


  /// 状态标签
  Widget _buildStatusChip(NovelCompletionStatus status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color,
          width: 0.5,
        ),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none, // 修复下划线问题
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

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
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
            onPressed: () {
              if (widget.knowledgeBaseId != null) {
                context.read<KnowledgeBaseBloc>().add(
                  LoadKnowledgeBaseDetail(widget.knowledgeBaseId!),
                );
              } else if (widget.novel != null) {
                context.read<KnowledgeBaseBloc>().add(
                  CheckCacheStatus(widget.novel!.novelId),
                );
              }
            },
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 大屏布局（左右分栏）
  Widget _buildLargeScreenLayout(KnowledgeBaseDetailLoaded state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：小说信息（30%）
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.3,
          child: _buildLeftPanel(state.knowledgeBase, state.isLiked),
        ),
        
        // 分隔线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: WebTheme.getBorderColor(context),
        ),
        
        // 右侧：Tab + 内容（70%）
        Expanded(
          child: _buildRightPanel(state.knowledgeBase),
        ),
      ],
    );
  }

  /// 小屏布局（上下滚动）
  Widget _buildSmallScreenLayout(KnowledgeBaseDetailLoaded state) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildLeftPanel(state.knowledgeBase, state.isLiked),
          const Divider(height: 1),
          _buildRightPanel(state.knowledgeBase),
        ],
      ),
    );
  }

  /// 左侧面板：小说信息
  Widget _buildLeftPanel(NovelKnowledgeBase knowledgeBase, bool isLiked) {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部：封面和基本信息并排布局
            _buildTopSection(knowledgeBase),
            
            const SizedBox(height: 20),
            
            // 操作按钮（只在已拆书时显示）
            if (_isKnowledgeBaseExtracted(knowledgeBase)) ...[
              _buildActionButtons(knowledgeBase, isLiked),
              const SizedBox(height: 12),
              // 分享按钮（仅所有者可见）
              _buildShareButton(knowledgeBase),
              const SizedBox(height: 20),
            ],
            
            // 简介
            if (knowledgeBase.description.isNotEmpty) ...[
              _buildSectionTitle('简介'),
              const SizedBox(height: 8),
              Text(
                knowledgeBase.description,
                style: TextStyle(
                  fontSize: 13,
                  color: WebTheme.getSecondaryTextColor(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // 标签
            if (knowledgeBase.tags != null && knowledgeBase.tags!.isNotEmpty) ...[
              _buildSectionTitle('标签'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: knowledgeBase.tags!.map((tag) => _buildTag(tag)).toList(),
              ),
              const SizedBox(height: 20),
            ],
            
            // 章节列表
            _buildLeftPanelChapterList(knowledgeBase),
            
            const SizedBox(height: 20),
            
            // 统计信息卡片
            _buildStatistics(knowledgeBase),
          ],
        ),
      ),
    );
  }

  /// 顶部区域：封面和信息并排布局
  Widget _buildTopSection(NovelKnowledgeBase knowledgeBase) {
    const double coverHeight = 160.0; // 黄金比例高度
    const double coverWidth = coverHeight * 0.618; // 黄金比例宽度
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面图片 - 黄金比例
        Container(
          width: coverWidth,
          height: coverHeight,
          decoration: BoxDecoration(
            color: WebTheme.getBorderColor(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: WebTheme.getBorderColor(context),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: knowledgeBase.coverImageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    knowledgeBase.coverImageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.library_books,
                        color: WebTheme.getSecondaryTextColor(context),
                        size: 40,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.library_books,
                    color: WebTheme.getSecondaryTextColor(context),
                    size: 40,
                  ),
                ),
        ),
        
        const SizedBox(width: 16),
        
        // 右侧信息区域
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                knowledgeBase.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: WebTheme.getTextColor(context),
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // 作者
              if (knowledgeBase.author != null)
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: WebTheme.getSecondaryTextColor(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      knowledgeBase.author!,
                      style: TextStyle(
                        fontSize: 13,
                        color: WebTheme.getSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 12),
              
              // 状态和标签
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (knowledgeBase.completionStatus != null)
                    _buildStatusChip(knowledgeBase.completionStatus!),
                  if (knowledgeBase.tags != null && knowledgeBase.tags!.isNotEmpty)
                    ...knowledgeBase.tags!.take(3).map((tag) => _buildSmallTag(tag)),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 关键数据
              Row(
                children: [
                  _buildInfoItem(Icons.favorite_outline, '${knowledgeBase.likeCount}'),
                  const SizedBox(width: 16),
                  _buildInfoItem(Icons.visibility_outlined, '${knowledgeBase.viewCount}'),
                  const SizedBox(width: 16),
                  _buildInfoItem(Icons.bookmark_outline, '${knowledgeBase.referenceCount}'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 信息项
  Widget _buildInfoItem(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: WebTheme.getSecondaryTextColor(context),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 小标签
  Widget _buildSmallTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: WebTheme.getPrimaryColor(context),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 左栏章节列表
  Widget _buildLeftPanelChapterList(NovelKnowledgeBase knowledgeBase) {
    final outlines = knowledgeBase.chapterOutlines;
    final hasChapters = outlines != null && outlines.isNotEmpty;
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.list_alt,
                  size: 18,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '目录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const Spacer(),
                if (hasChapters)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '共${outlines.length}章',
                      style: TextStyle(
                        fontSize: 12,
                        color: WebTheme.getPrimaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 内容区域
          hasChapters 
            ? _buildChapterListContent(outlines)
            : _buildChapterListPlaceholder(),
        ],
      ),
    );
  }

  /// 章节列表内容
  Widget _buildChapterListContent(List<ChapterOutlineDto>? outlines) {
    if (outlines == null || outlines.isEmpty) {
      return _buildChapterListPlaceholder();
    }
    // 最多显示10章，如果超过则显示"查看更多"
    final displayOutlines = outlines.take(10).toList();
    final hasMore = outlines.length > 10;
    
    return Column(
      children: [
        ...displayOutlines.map((outline) => _buildLeftPanelChapterItem(outline)),
        if (hasMore)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: WebTheme.getBorderColor(context).withOpacity(0.5),
                  width: 1,
                ),
              ),
            ),
            child: Center(
              child: Text(
                '还有${outlines.length - 10}章，点击右侧章节大纲查看全部',
                style: TextStyle(
                  fontSize: 12,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 左栏章节项目
  Widget _buildLeftPanelChapterItem(ChapterOutlineDto outline) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: WebTheme.getBorderColor(context).withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: InkWell(
        onTap: () {
          // TODO: 跳转到章节详情
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 章节序号
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${outline.order}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: WebTheme.getPrimaryColor(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // 章节标题
              Expanded(
                child: Text(
                  outline.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: WebTheme.getTextColor(context),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 章节列表占位符
  Widget _buildChapterListPlaceholder() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.info_outline,
              size: 32,
              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
            ),
            const SizedBox(height: 12),
            Text(
              '拆书后将显示章节目录',
              style: TextStyle(
                fontSize: 14,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildStatistics(NovelKnowledgeBase knowledgeBase) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        border: Border.all(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(Icons.favorite, '${knowledgeBase.likeCount}', '点赞'),
          _buildStatItem(Icons.bookmark, '${knowledgeBase.referenceCount}', '引用'),
          _buildStatItem(Icons.visibility, '${knowledgeBase.viewCount}', '查看'),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: WebTheme.getPrimaryColor(context),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
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

  Widget _buildActionButtons(NovelKnowledgeBase knowledgeBase, bool isLiked) {
    // 使用状态变量判断是否在我的知识库中
    final isInMyKnowledgeBase = _isInMyKnowledgeBase;
    
    return Row(
      children: [
        // 点赞按钮
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _handleLike,
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              size: 18,
            ),
            label: Text(
              isLiked ? '已点赞' : '点赞',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // 添加/删除知识库按钮
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isInMyKnowledgeBase 
                ? () => _handleRemoveFromKnowledgeBase(knowledgeBase)
                : () => _handleAddToKnowledgeBase(knowledgeBase),
            icon: Icon(
              isInMyKnowledgeBase ? Icons.delete_outline : Icons.add_circle_outline,
              size: 18,
            ),
            label: Text(
              isInMyKnowledgeBase ? '从我的知识库删除' : '添加到我的知识库',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: isInMyKnowledgeBase ? Colors.red : Colors.black87,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShareButton(NovelKnowledgeBase knowledgeBase) {
    // 只有用户导入的知识库且是所有者才显示分享按钮
    if (!knowledgeBase.isUserImported) {
      return const SizedBox.shrink();
    }

    final isPublic = knowledgeBase.isPublic;
    final icon = isPublic ? Icons.lock_outline : Icons.share_outlined;
    final label = isPublic ? '设为私密' : '分享到公共知识库';
    final color = isPublic ? Colors.orange : Colors.green;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _handleTogglePublic(knowledgeBase),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  void _handleTogglePublic(NovelKnowledgeBase knowledgeBase) {
    context.read<KnowledgeBaseBloc>().add(
      ToggleKnowledgeBasePublic(knowledgeBase.id),
    );
  }

  /// 检查是否在我的知识库中
  Future<void> _checkIsInMyKnowledgeBase() async {
    if (widget.knowledgeBaseId == null || _isCheckingStatus) {
      return;
    }
    
    setState(() {
      _isCheckingStatus = true;
    });
    
    try {
      final repository = context.read<KnowledgeBaseBloc>().repository;
      final isIn = await repository.isInMyKnowledgeBase(widget.knowledgeBaseId!);
      
      if (mounted) {
        setState(() {
          _isInMyKnowledgeBase = isIn;
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      AppLogger.e('KnowledgeBaseDetailScreen', '检查知识库状态失败', e);
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
    }
  }

  void _handleAddToKnowledgeBase(NovelKnowledgeBase knowledgeBase) {
    // 添加到知识库
    context.read<KnowledgeBaseBloc>().add(
      AddToMyKnowledgeBase(knowledgeBase.id),
    );
  }
  
  void _handleRemoveFromKnowledgeBase(NovelKnowledgeBase knowledgeBase) {
    // 从知识库删除
    context.read<KnowledgeBaseBloc>().add(
      RemoveFromMyKnowledgeBase(knowledgeBase.id),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: WebTheme.getTextColor(context),
      ),
    );
  }

  Widget _buildTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 12,
          color: WebTheme.getPrimaryColor(context),
        ),
      ),
    );
  }


  /// 右侧面板：Tab + 内容
  Widget _buildRightPanel(NovelKnowledgeBase knowledgeBase) {
    // 检查是否已拆书完成（通过检查是否有设定数据）
    final isExtracted = _isKnowledgeBaseExtracted(knowledgeBase);
    
    return Container(
      color: WebTheme.getBackgroundColor(context),
      child: isExtracted
          ? Row(
              children: [
                // 竖向Tab导航
                _buildVerticalTabs(),
                
                // 内容区域
                Expanded(
                  child: _buildTabContent(knowledgeBase),
                ),
              ],
            )
          : _buildExtractionPromptContent(),
    );
  }

  /// 判断知识库是否已拆书完成
  bool _isKnowledgeBaseExtracted(NovelKnowledgeBase knowledgeBase) {
    // 检查各类设定是否有数据
    return ((knowledgeBase.narrativeStyleSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.characterPlotSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.novelFeatureSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.readerEmotionSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.hotMemesSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.customSettings?.isNotEmpty ?? false) ||
        (knowledgeBase.chapterOutlines?.isNotEmpty ?? false));
  }

  /// 拆书提示内容（右侧面板）
  Widget _buildExtractionPromptContent() {
    if (_isExtracting) {
      // 拆书进行中状态
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              '正在拆书《${widget.novel!.title}》',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '正在分析小说内容，提取知识库信息...',
              style: TextStyle(
                fontSize: 16,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: WebTheme.getPrimaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '预计需要5-20分钟，请稍候...',
                    style: TextStyle(
                      fontSize: 14,
                      color: WebTheme.getPrimaryColor(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // 未拆书状态，显示拆书提示
      return Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.psychology,
                  size: 64,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
                const SizedBox(height: 24),
                Text(
                  '请先拆书',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '拆书后，这里将显示小说的知识库内容\n包括人物设定、剧情分析、写作风格等',
                  style: TextStyle(
                    fontSize: 16,
                    color: WebTheme.getSecondaryTextColor(context),
                    height: 1.6,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: WebTheme.getPrimaryColor(context).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: WebTheme.getPrimaryColor(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '拆书功能包括',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: WebTheme.getTextColor(context),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem('🎭', '人物设定分析'),
                      _buildFeatureItem('📝', '叙事风格提取'),
                      _buildFeatureItem('🎪', '情节结构解析'),
                      _buildFeatureItem('💎', '特色元素总结'),
                      _buildFeatureItem('😄', '热梗搞笑点'),
                      _buildFeatureItem('📖', '章节大纲生成'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _startExtraction,
                    icon: const Icon(Icons.play_arrow, size: 24),
                    label: const Text(
                      '开始拆书',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WebTheme.getPrimaryColor(context),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
  }

  Widget _buildFeatureItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getTextColor(context),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  /// 竖向Tab导航
  Widget _buildVerticalTabs() {
    final tabs = [
      {'icon': Icons.auto_stories, 'label': '文风\n叙事'},
      {'icon': Icons.library_books, 'label': '情节\n设计'},  // ✅ 新增：情节设计
      {'icon': Icons.person, 'label': '人物\n塑造'},  // ✅ 修改：人物塑造
      {'icon': Icons.public, 'label': '小说\n特点'},
      {'icon': Icons.favorite, 'label': '读者\n情绪'},
      {'icon': Icons.emoji_emotions, 'label': '热梗\n搞笑'},
      {'icon': Icons.edit, 'label': '自定义'},
      {'icon': Icons.list_alt, 'label': '章节\n大纲'},
    ];

    return Container(
      width: 80,
      color: WebTheme.getSurfaceColor(context),
      child: Column(
        children: List.generate(tabs.length, (index) {
          final tab = tabs[index];
          final isSelected = _tabController.index == index;
          
          return InkWell(
            onTap: () {
              setState(() {
                _tabController.animateTo(index);
              });
            },
            child: Container(
              width: double.infinity, // 确保容器占满整个Tab宽度
              height: 80,
              decoration: BoxDecoration(
                color: isSelected
                    ? WebTheme.getPrimaryColor(context).withOpacity(0.2) // 进一步增加透明度
                    : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ), // 添加右侧圆角
                border: Border(
                  left: BorderSide(
                    color: isSelected 
                        ? WebTheme.getPrimaryColor(context)
                        : Colors.transparent,
                    width: 4, // 增加左侧边框宽度
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tab['icon'] as IconData,
                    size: 24,
                    color: isSelected
                        ? WebTheme.getPrimaryColor(context)
                        : WebTheme.getSecondaryTextColor(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab['label'] as String,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? WebTheme.getPrimaryColor(context)
                          : WebTheme.getSecondaryTextColor(context),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Tab内容区域
  Widget _buildTabContent(NovelKnowledgeBase knowledgeBase) {
    // 从characterPlotSettings中分离情节设计和人物塑造
    final plotSettings = _filterPlotSettings(knowledgeBase.characterPlotSettings);
    final characterSettings = _filterCharacterSettings(knowledgeBase.characterPlotSettings);
    
    return TabBarView(
      controller: _tabController,
      children: [
        _buildSettingsList(knowledgeBase.narrativeStyleSettings, '文风叙事'),
        _buildSettingsList(plotSettings, '情节设计'),  // ✅ 情节设计独立Tab
        _buildSettingsList(characterSettings, '人物塑造'),  // ✅ 人物塑造独立Tab
        _buildSettingsList(knowledgeBase.novelFeatureSettings, '小说特点'),
        _buildSettingsList(knowledgeBase.readerEmotionSettings, '读者情绪'),
        _buildSettingsList(knowledgeBase.hotMemesSettings, '热梗搞笑点'),
        _buildSettingsList(knowledgeBase.customSettings, '用户自定义'),
        _buildChapterOutlines(knowledgeBase),
      ],
    );
  }
  
  /// 筛选情节设计类设定
  List<NovelSettingItem>? _filterPlotSettings(List<NovelSettingItem>? settings) {
    if (settings == null) return null;
    return settings.where((s) => 
      s.type == 'CORE_CONFLICT_SETTING' || 
      s.type == 'SUSPENSE_ELEMENT' || 
      s.type == 'PACING' ||
      s.type == 'PLOT_DEVICE'  // 兼容旧数据
    ).toList();
  }
  
  /// 筛选人物塑造类设定
  List<NovelSettingItem>? _filterCharacterSettings(List<NovelSettingItem>? settings) {
    if (settings == null) return null;
    return settings.where((s) => 
      s.type == 'CHARACTER'
    ).toList();
  }

  /// 设定列表
  Widget _buildSettingsList(List<NovelSettingItem>? settings, String title) {
    if (settings == null || settings.isEmpty) {
      return _buildEmptyContent(title);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: settings.length,
      itemBuilder: (context, index) {
        return SettingCardWidget(
          setting: settings[index],
          onCopy: () => _handleCopySetting(settings[index]),
        );
      },
    );
  }

  /// 章节大纲
  Widget _buildChapterOutlines(NovelKnowledgeBase knowledgeBase) {
    final outlines = knowledgeBase.chapterOutlines;
    
    if (outlines == null || outlines.isEmpty) {
      return _buildEmptyContent('章节大纲');
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: outlines.length,
      itemBuilder: (context, index) {
        final outline = outlines[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[850]
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[700]!
                  : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              // TODO: 跳转到章节详情或编辑页面
              AppLogger.i('KnowledgeBaseDetailScreen', '点击章节: ${outline.title}');
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 章节序号
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            '${outline.order}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 章节标题
                      Expanded(
                        child: Text(
                          outline.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WebTheme.getTextColor(context),
                          ),
                        ),
                      ),
                      // 复制按钮
                      IconButton(
                        icon: Icon(
                          Icons.copy,
                          size: 18,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                        tooltip: '复制大纲',
                        onPressed: () {
                          // TODO: 实现复制功能
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制章节大纲'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (outline.summary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      outline.summary,
                      style: TextStyle(
                        fontSize: 14,
                        color: WebTheme.getSecondaryTextColor(context),
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyContent(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无$title数据',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCopySetting(NovelSettingItem setting) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制设定: ${setting.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
