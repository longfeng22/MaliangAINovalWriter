import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 剧情推演结果展示组件
/// 
/// 功能特点：
/// - 左右分栏布局：左侧摘要列表，右侧场景内容
/// - 完全暗黑主题适配
/// - 响应式设计支持
/// - 选中状态管理
/// - 可滚动内容支持
/// - 支持迭代优化：选择最满意的结果后继续推演
class StoryPredictionResults extends StatefulWidget {
  final List<PredictionResult> results;
  final Function(PredictionResult)? onPreviewMerge;
  final Function(PredictionResult)? onAddToNextChapter;
  final Function(PredictionResult)? onRefine; // 🔥 新增：继续推演回调
  final bool isGenerating;
  final bool hasRunningTask; // 🔥 新增：是否有任务仍在运行中

  const StoryPredictionResults({
    Key? key,
    required this.results,
    this.onPreviewMerge,
    this.onAddToNextChapter,
    this.onRefine, // 🔥 新增参数
    this.isGenerating = false,
    this.hasRunningTask = false, // 🔥 新增参数，默认false
  }) : super(key: key);

  @override
  State<StoryPredictionResults> createState() => _StoryPredictionResultsState();
}

class _StoryPredictionResultsState extends State<StoryPredictionResults> {
  int _selectedIndex = 0; // 当前选中的卡片索引

  @override
  void initState() {
    super.initState();
    _updateSelectedIndex();
  }

  @override
  void didUpdateWidget(StoryPredictionResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSelectedIndex();
  }

  void _updateSelectedIndex() {
    if (widget.results.isNotEmpty) {
      _selectedIndex = _selectedIndex.clamp(0, widget.results.length - 1);
    } else {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty && !widget.isGenerating) {
      return _buildEmptyState();
    }

    return Row(
      children: [
        // 左栏：摘要列表
        Expanded(
          flex: 2, // 占2/5的宽度
          child: _buildSummaryList(),
        ),
        
        // 分割线
        Container(
          width: 1,
          color: WebTheme.getBorderColor(context),
        ),
        
        // 右栏：场景内容
        Expanded(
          flex: 3, // 占3/5的宽度
          child: _buildSceneContent(),
        ),
      ],
    );
  }

  /// 构建左栏摘要列表
  Widget _buildSummaryList() {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          right: BorderSide(
            color: WebTheme.getBorderColor(context).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WebTheme.getTextColor(context).withValues(alpha: 0.03),
              border: Border(
                bottom: BorderSide(
                  color: WebTheme.getBorderColor(context).withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.format_list_bulleted,
                  size: 18,
                  color: WebTheme.getTextColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '剧情摘要',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.results.length}个结果',
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          // 摘要列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: widget.results.length + (widget.isGenerating ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= widget.results.length) {
                  // 生成中的占位卡片
                  return _buildGeneratingSummaryCard();
                }
                
                final result = widget.results[index];
                final isSelected = index == _selectedIndex;
                
                return _buildSummaryCard(result, isSelected, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建右栏场景内容
  Widget _buildSceneContent() {
    if (widget.results.isEmpty) {
      return _buildEmptySceneContent();
    }
    
    final selectedResult = widget.results[_selectedIndex];
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WebTheme.getCardColor(context),
              border: Border(
                bottom: BorderSide(
                  color: WebTheme.getBorderColor(context).withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(selectedResult.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.movie_outlined,
                    size: 18,
                    color: _getStatusColor(selectedResult.status),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '场景内容',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            selectedResult.modelName,
                            style: TextStyle(
                              fontSize: 12,
                              color: WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(selectedResult.status).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getStatusText(selectedResult.status),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _getStatusColor(selectedResult.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selectedResult.status == PredictionStatus.generating)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.deepPurple[600]!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 场景内容区域
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              child: _buildSceneContentArea(selectedResult),
            ),
          ),
          // 操作按钮
          if (selectedResult.status == PredictionStatus.completed && selectedResult.hasSceneContent)
            _buildSceneActions(selectedResult),
        ],
      ),
    );
  }

  /// 构建场景内容区域
  Widget _buildSceneContentArea(PredictionResult result) {
    // 失败状态
    if (result.status == PredictionStatus.failed) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.red[600],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '生成失败',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.red[600],
                ),
              ),
              if (result.error != null && result.error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.1),
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
                            color: Colors.red[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '错误详情',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        result.error!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                result.error?.contains('积分') == true 
                  ? '积分余额不足，请充值后重试' 
                  : '请检查网络连接或稍后重试',
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

    // 跳过状态
    if (result.status == PredictionStatus.skipped) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.skip_next_outlined,
                  size: 40,
                  color: Colors.blue[600],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '已跳过',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '该模型的内容生成已被跳过',
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
    
    // 生成中状态
    if (result.status == PredictionStatus.generating) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: WebTheme.getTextColor(context).withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple[600]!,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'AI正在生成场景内容...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '这可能需要30-90秒时间',
              style: TextStyle(
                fontSize: 14,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      );
    }
    
    // 有场景内容
    if (result.hasSceneContent) {
      return SingleChildScrollView(
        child: SelectableText(
          result.sceneContent!,
          style: TextStyle(
            fontSize: 15,
            color: WebTheme.getTextColor(context),
            height: 1.6,
            letterSpacing: 0.3,
          ),
        ),
      );
    }
    
    // 无场景内容
    return _buildNoSceneContent();
  }

  /// 构建摘要卡片
  Widget _buildSummaryCard(PredictionResult result, bool isSelected, int index) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected 
            ? WebTheme.getTextColor(context).withValues(alpha: 0.08)
            : WebTheme.getCardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
              ? WebTheme.getTextColor(context).withValues(alpha: 0.2)
              : WebTheme.getBorderColor(context),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: WebTheme.getShadowColor(context, opacity: isSelected ? 0.15 : 0.08),
              blurRadius: isSelected ? 12 : 8,
              offset: Offset(0, isSelected ? 4 : 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：模型名称和状态
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(result.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getStatusIcon(result.status),
                    size: 16,
                    color: _getStatusColor(result.status),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.modelName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WebTheme.getTextColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // 🔥 如果是迭代卡片，显示优化需求
                      if (result.refinementInstructions != null && result.refinementInstructions!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '💡 ${result.refinementInstructions}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.deepPurple[400],
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Text(
                        _getStatusText(result.status),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(result.status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (result.status == PredictionStatus.generating)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.deepPurple[600]!,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 摘要内容 - 支持内部滚动
            if (result.status != PredictionStatus.failed && result.status != PredictionStatus.skipped)
              Container(
                height: isSelected ? 300 : 150, // 选中时更高，未选中时固定高度
                child: isSelected
                  ? SingleChildScrollView(
                      child: SelectableText(
                        result.summary,
                        style: TextStyle(
                          fontSize: 14,
                          color: WebTheme.getTextColor(context),
                          height: 1.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : Text(
                      result.summary,
                      style: TextStyle(
                        fontSize: 14,
                        color: WebTheme.getTextColor(context),
                        height: 1.5,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 6, // 未选中时显示6行
                      overflow: TextOverflow.ellipsis,
                    ),
              )
            else
              // 异常状态显示信息（失败或跳过）
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.status == PredictionStatus.failed 
                    ? Colors.red.withValues(alpha: 0.05)
                    : Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.status == PredictionStatus.failed 
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.blue.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          result.status == PredictionStatus.failed 
                            ? Icons.error_outline 
                            : Icons.skip_next_outlined,
                          size: 16,
                          color: result.status == PredictionStatus.failed 
                            ? Colors.red[600] 
                            : Colors.blue[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          result.status == PredictionStatus.failed ? '生成失败' : '已跳过',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: result.status == PredictionStatus.failed 
                              ? Colors.red[600] 
                              : Colors.blue[600],
                          ),
                        ),
                      ],
                    ),
                    if (result.status == PredictionStatus.failed && result.error != null && result.error!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        result.error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (result.status == PredictionStatus.skipped) ...[
                      const SizedBox(height: 8),
                      Text(
                        '该模型的内容生成已被跳过',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            
            const SizedBox(height: 12),
            
            // 🔥 继续推演按钮（仅在成功完成的结果上显示且选中时显示）
            if (isSelected && 
                result.status == PredictionStatus.completed && 
                widget.onRefine != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Tooltip(
                  message: widget.hasRunningTask 
                    ? '请等待所有卡片生成完成后再进行迭代优化'
                    : '基于当前结果继续推演，生成更多可能性',
                  child: ElevatedButton.icon(
                    onPressed: widget.hasRunningTask 
                      ? null // 🔥 任务运行中时禁用按钮
                      : () => widget.onRefine!(result),
                    icon: Icon(
                      Icons.auto_fix_high, 
                      size: 16,
                      color: widget.hasRunningTask ? Colors.grey[400] : Colors.white,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('基于此结果继续推演'),
                        if (widget.hasRunningTask) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: Colors.grey[400],
                          ),
                        ],
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.hasRunningTask 
                        ? Colors.grey[300] 
                        : Colors.deepPurple[600],
                      foregroundColor: widget.hasRunningTask 
                        ? Colors.grey[500] 
                        : Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: widget.hasRunningTask ? 0 : 2,
                    ),
                  ),
                ),
              ),
            
            // 底部信息
            Row(
              children: [
                // 状态标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(result.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusText(result.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(result.status),
                    ),
                  ),
                ),
                
                // 场景内容标识
                if (result.hasSceneContent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '含场景',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ],
                
                const Spacer(),
                
                // 时间
                Text(
                  _formatTime(result.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 获取状态图标
  IconData _getStatusIcon(PredictionStatus status) {
    switch (status) {
      case PredictionStatus.completed:
        return Icons.check_circle_outline;
      case PredictionStatus.failed:
        return Icons.error_outline;
      case PredictionStatus.generating:
        return Icons.auto_awesome;
      case PredictionStatus.skipped:
        return Icons.skip_next_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(PredictionStatus status) {
    switch (status) {
      case PredictionStatus.completed:
        return Colors.green;
      case PredictionStatus.failed:
        return Colors.red;
      case PredictionStatus.generating:
        return Colors.orange;
      case PredictionStatus.skipped:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// 获取状态文本
  String _getStatusText(PredictionStatus status) {
    switch (status) {
      case PredictionStatus.completed:
        return '已完成';
      case PredictionStatus.failed:
        return '生成失败';
      case PredictionStatus.generating:
        return '生成中';
      case PredictionStatus.skipped:
        return '已跳过';
      default:
        return '等待中';
    }
  }

  /// 构建生成中的摘要卡片
  Widget _buildGeneratingSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：状态和进度
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI模型',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '生成中',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.deepPurple[600]!,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 生成提示内容
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: Colors.orange[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AI正在思考中...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '正在分析当前剧情并生成推演内容，预计需要30-60秒',
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 底部状态
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '生成中',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '刚刚',
                style: TextStyle(
                  fontSize: 12,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建空场景内容
  Widget _buildEmptySceneContent() {
    return Container(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: WebTheme.getCardColor(context).withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.movie_outlined,
              size: 48,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '选择左侧的剧情摘要',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '查看对应的场景内容',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建无场景内容状态
  Widget _buildNoSceneContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WebTheme.getCardColor(context).withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.movie_filter_outlined,
              size: 40,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无场景内容',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '该摘要还没有生成场景内容',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建场景操作按钮
  Widget _buildSceneActions(PredictionResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          top: BorderSide(
            color: WebTheme.getBorderColor(context).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.onPreviewMerge != null 
                ? () => widget.onPreviewMerge!(result)
                : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: WebTheme.getCardColor(context),
                foregroundColor: WebTheme.getTextColor(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: WebTheme.getBorderColor(context),
                    width: 1,
                  ),
                ),
                elevation: 0,
              ),
              icon: Icon(
                Icons.preview_outlined,
                size: 16,
                color: WebTheme.getTextColor(context),
              ),
              label: Text(
                '预览合并',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getTextColor(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.onAddToNextChapter != null 
                ? () => widget.onAddToNextChapter!(result)
                : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: WebTheme.getTextColor(context),
                foregroundColor: WebTheme.getBackgroundColor(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: Icon(
                Icons.library_add_outlined,
                size: 16,
                color: WebTheme.getBackgroundColor(context),
              ),
              label: Text(
                '添加到下一章',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getBackgroundColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化时间
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else {
      return '${dateTime.month}-${dateTime.day}';
    }
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Expanded(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: WebTheme.getBorderColor(context).withValues(alpha: 0.5),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WebTheme.getCardColor(context).withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '点击"开始生成"来创建剧情推演',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '系统将为您生成多个剧情方向供选择',
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
}

/// 剧情推演结果数据类
class PredictionResult {
  final String id;
  final String modelName;
  final String summary;
  final String? sceneContent;
  final PredictionStatus status;
  final PredictionStatus sceneStatus;
  final DateTime createdAt;
  final String? error; // 添加错误信息字段
  final String? sourceTaskId; // 🔥 这个卡片来自哪个任务
  final String? refinementInstructions; // 🔥 迭代优化需求

  PredictionResult({
    required this.id,
    required this.modelName,
    required this.summary,
    this.sceneContent,
    required this.status,
    this.sceneStatus = PredictionStatus.pending,
    required this.createdAt,
    this.error,
    this.sourceTaskId,
    this.refinementInstructions, // 🔥 新增参数
  });

  bool get hasSceneContent => sceneContent != null && sceneContent!.isNotEmpty;

  PredictionResult copyWith({
    String? summary,
    String? sceneContent,
    PredictionStatus? status,
    PredictionStatus? sceneStatus,
    String? error,
    String? sourceTaskId,
    String? refinementInstructions,
  }) {
    return PredictionResult(
      id: id,
      modelName: modelName,
      summary: summary ?? this.summary,
      sceneContent: sceneContent ?? this.sceneContent,
      status: status ?? this.status,
      sceneStatus: sceneStatus ?? this.sceneStatus,
      createdAt: createdAt,
      error: error ?? this.error,
      sourceTaskId: sourceTaskId ?? this.sourceTaskId,
      refinementInstructions: refinementInstructions ?? this.refinementInstructions, // 🔥 新增
    );
  }
}

/// 剧情推演状态枚举
enum PredictionStatus {
  pending,    // 等待中
  generating, // 生成中
  completed,  // 已完成
  failed,     // 失败
  skipped,    // 跳过
}