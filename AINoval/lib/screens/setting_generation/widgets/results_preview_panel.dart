import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'ai_shimmer_placeholder.dart';
import 'package:ainoval/utils/web_theme.dart';

class ChapterPreviewData {
  final String title;
  final String outline;
  final String content;

  const ChapterPreviewData({
    required this.title,
    required this.outline,
    required this.content,
  });

  ChapterPreviewData copyWith({String? title, String? outline, String? content}) {
    return ChapterPreviewData(
      title: title ?? this.title,
      outline: outline ?? this.outline,
      content: content ?? this.content,
    );
  }
}

class ResultsPreviewPanel extends StatefulWidget {
  final List<ChapterPreviewData> chapters;
  final bool isGenerating;
  final void Function(int index, ChapterPreviewData updated) onChapterChanged;

  const ResultsPreviewPanel({
    Key? key,
    required this.chapters,
    required this.isGenerating,
    required this.onChapterChanged,
  }) : super(key: key);

  @override
  State<ResultsPreviewPanel> createState() => _ResultsPreviewPanelState();
}

class _ResultsPreviewPanelState extends State<ResultsPreviewPanel> with TickerProviderStateMixin {
  TabController? _tabController; // 允许为空：当无章节时不创建
  List<TextEditingController> _outlineCtrls = const [];
  List<TextEditingController> _contentCtrls = const [];
  int _selectedTabIndex = 0;
  // 标签页滚动控制器 + 滚动位置持久化
  final PageStorageKey _tabsScrollKey = const PageStorageKey('results_preview_tabs_scroll');
  ScrollController _scrollController = ScrollController(); // 标签页滚动控制器

  @override
  void initState() {
    super.initState();
    // 仅当有章节时初始化控制器，避免 TabController 长度为 0 的错误
    if (widget.chapters.isNotEmpty) {
      _initControllers();
    }
  }

  @override
  void didUpdateWidget(covariant ResultsPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当从无到有或长度变化时，重建控制器
    if (oldWidget.chapters.length != widget.chapters.length) {
      _disposeControllers();
      if (widget.chapters.isNotEmpty) {
        _initControllers();
      }
      return;
    }
    // 同步内容（有章节时）
    if (widget.chapters.isNotEmpty &&
        _outlineCtrls.length == widget.chapters.length &&
        _contentCtrls.length == widget.chapters.length) {
      for (int i = 0; i < widget.chapters.length; i++) {
        _outlineCtrls[i].text = widget.chapters[i].outline;
        _contentCtrls[i].text = widget.chapters[i].content;
      }
    }
  }

  void _initControllers() {
    final tabLen = (widget.chapters.length * 2).clamp(1, 1000); // 至少为1
    _tabController = TabController(length: tabLen, vsync: this);
    _tabController!.addListener(() {
      final currentIndex = _tabController?.index ?? _selectedTabIndex;
      if (_selectedTabIndex != currentIndex) {
        setState(() {
          _selectedTabIndex = currentIndex;
        });
      }
    });
    _outlineCtrls = List.generate(widget.chapters.length, (i) => TextEditingController(text: widget.chapters[i].outline));
    _contentCtrls = List.generate(widget.chapters.length, (i) => TextEditingController(text: widget.chapters[i].content));
  }

  void _disposeControllers() {
    _tabController?.dispose();
    _tabController = null;
    for (final c in _outlineCtrls) {
      c.dispose();
    }
    for (final c in _contentCtrls) {
      c.dispose();
    }
    _outlineCtrls = const [];
    _contentCtrls = const [];
  }

  @override
  void dispose() {
    _disposeControllers();
    _scrollController.dispose(); // 释放滚动控制器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapters.isEmpty) {
      return widget.isGenerating
          ? const AIShimmerPlaceholder()
          : _buildEmptyResults(context, '暂无结果，点击右上角生成');
    }
    // 确保在首次有章节时已初始化控制器（防御性）
    if (_tabController == null) {
      _initControllers();
    }
    return Container(
      color: WebTheme.getBackgroundColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 现代化标签页头部 - 支持多章节滚动
          Container(
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context),
              border: Border(
                bottom: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标签页说明（当章节超过3个时显示）
                if (widget.chapters.length > 3)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.swipe,
                          size: 16,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '左右滑动查看所有章节',
                          style: TextStyle(
                            fontSize: 12,
                            color: WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '共 ${widget.chapters.length} 章',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: WebTheme.getPrimaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 标签页区域
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: _buildModernTabs(context),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: TabBarView(
                controller: _tabController!,
                children: _buildTabViews(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 现代化标签页设计 - 支持水平滚动和鼠标滚轮
  Widget _buildModernTabs(BuildContext context) {
    return Container(
      height: 50, // 固定高度，防止布局溢出
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent && _scrollController.hasClients) {
            // 将垂直滚动转换为水平滚动
            final double scrollDelta = pointerSignal.scrollDelta.dy;
            final double currentOffset = _scrollController.offset;
            final double maxScrollExtent = _scrollController.position.maxScrollExtent;
            
            // 只有当有内容需要滚动时才执行滚动
            if (maxScrollExtent > 0) {
              // 计算新的滚动位置，增加滚动灵敏度
              final double newOffset = (currentOffset + scrollDelta * 2.0)
                  .clamp(0.0, maxScrollExtent);
              // 使用jumpTo降低动画开销，避免掉帧
              _scrollController.jumpTo(newOffset);
            }
          }
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 8),
          physics: const ClampingScrollPhysics(), // 更贴近桌面/网页的滚动体验，减少回弹卡顿
          key: _tabsScrollKey, // 持久化滚动位置
          child: Row(
            children: _buildModernTabItems(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildModernTabItems(BuildContext context) {
    final items = <Widget>[];
    
    // 添加起始间距
    items.add(const SizedBox(width: 4));
    
    for (int i = 0; i < widget.chapters.length; i++) {
      final title = widget.chapters[i].title.isNotEmpty 
          ? widget.chapters[i].title 
          : '第${i + 1}章';
      
      // 章节标题
      items.add(_buildChapterHeader(context, i, title));
      
      // 大纲和正文标签
      items.add(const SizedBox(width: 12));
      items.add(_buildModernTabChip(context, 
        index: i * 2, 
        label: '大纲', 
        icon: Icons.format_list_bulleted,
      ));
      items.add(const SizedBox(width: 8));
      items.add(_buildModernTabChip(context, 
        index: i * 2 + 1, 
        label: '正文', 
        icon: Icons.article,
      ));
      
      // 章节分隔符 - 优化间距
      if (i < widget.chapters.length - 1) {
        items.add(Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color: WebTheme.getBorderColor(context),
        ));
      }
    }
    
    // 添加结束间距，确保最后一个标签不被截断
    items.add(const SizedBox(width: 16));
    
    return items;
  }

  Widget _buildChapterHeader(BuildContext context, int chapterIndex, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebTheme.getTextColor(context).withOpacity(0.08),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: WebTheme.getTextColor(context),
        ),
      ),
    );
  }

  Widget _buildModernTabChip(BuildContext context, {
    required int index, 
    required String label, 
    required IconData icon,
  }) {
    final bool isSelected = index == _selectedTabIndex;
    final Color textColor = WebTheme.getTextColor(context);
    final Color bgColor = WebTheme.getBackgroundColor(context);
    final Color selectedBg = textColor.withOpacity(0.12);
    
    return InkWell(
      onTap: () {
        _onTabSelected(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : bgColor,
          border: Border.all(
            color: isSelected ? textColor : WebTheme.getBorderColor(context),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: textColor.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? textColor : WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? textColor : WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 处理标签选择（不再自动滚动，保持当前位置）
  void _onTabSelected(int index) {
    setState(() {
      _selectedTabIndex = index;
      _tabController?.animateTo(index);
    });
  }
  

  List<Widget> _buildTabViews(BuildContext context) {
    final List<Widget> views = [];
    for (int i = 0; i < widget.chapters.length; i++) {
      views.add(_buildPlainEditor(context, i, isOutline: true));
      views.add(_buildPlainEditor(context, i, isOutline: false));
    }
    return views;
  }

  // 现代化编辑器设计
  Widget _buildPlainEditor(BuildContext context, int index, {required bool isOutline}) {
    final controller = isOutline ? _outlineCtrls[index] : _contentCtrls[index];
    final onChanged = (String text) {
      if (isOutline) {
        widget.onChapterChanged(index, widget.chapters[index].copyWith(outline: text));
      } else {
        widget.onChapterChanged(index, widget.chapters[index].copyWith(content: text));
      }
    };

    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        border: Border.all(
          color: WebTheme.getBorderColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 编辑器头部标识
            Row(
              children: [
                Icon(
                  isOutline ? Icons.format_list_bulleted : Icons.article,
                  size: 18,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  isOutline ? '章节大纲' : '章节正文',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const Spacer(),
                // 字数统计
                Text(
                  '${controller.text.length} 字',
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: WebTheme.getBorderColor(context),
            ),
            const SizedBox(height: 12),
            // 编辑器内容
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: isOutline 
                      ? '请输入章节大纲...\n例如：主要情节发展、关键冲突、角色动机等'
                      : '请输入章节正文...\n开始创作这一章的具体内容',
                  hintStyle: TextStyle(
                    color: WebTheme.getSecondaryTextColor(context),
                    fontSize: 14,
                    height: 1.6,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: WebTheme.getTextColor(context),
                  fontFamily: 'PingFang SC',
                ),
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: null,
                onChanged: onChanged,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResults(BuildContext context, String message) {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                ),
                child: Icon(
                  Icons.auto_stories,
                  size: 40,
                  color: WebTheme.getPrimaryColor(context),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '开始创作您的黄金三章',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getTextColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: WebTheme.getSurfaceColor(context),
                  border: Border.all(
                    color: WebTheme.getBorderColor(context),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: WebTheme.getPrimaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '生成的内容将在此处展示，支持实时编辑',
                      style: TextStyle(
                        fontSize: 12,
                        color: WebTheme.getSecondaryTextColor(context),
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
  }
}


