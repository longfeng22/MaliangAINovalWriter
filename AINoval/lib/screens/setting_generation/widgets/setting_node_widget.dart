import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import '../../../models/setting_node.dart';
import '../../../blocs/setting_generation/setting_generation_state.dart'; // 导入渲染状态

/// 设定节点组件
class SettingNodeWidget extends StatefulWidget {
  final SettingNode node;
  final String? selectedNodeId;
  final String viewMode;
  final int level;
  final Function(String nodeId) onTap;
  
  // 渲染状态参数
  final Set<String> renderedNodeIds;
  final Map<String, NodeRenderInfo> nodeRenderStates;
  // 是否渲染子节点（用于流式列表避免重复渲染）
  final bool renderChildren;

  const SettingNodeWidget({
    Key? key,
    required this.node,
    this.selectedNodeId,
    required this.viewMode,
    required this.level,
    required this.onTap,
    this.renderedNodeIds = const {},
    this.nodeRenderStates = const {},
    this.renderChildren = true,
  }) : super(key: key);

  @override
  State<SettingNodeWidget> createState() => _SettingNodeWidgetState();
}

class _SettingNodeWidgetState extends State<SettingNodeWidget>
    with TickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _renderingController; // 渲染动画控制器
  late Animation<double> _renderingAnimation;

  @override
  void initState() {
    super.initState();
    
    // 渲染动画控制器
    _renderingController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _renderingAnimation = CurvedAnimation(
      parent: _renderingController,
      curve: Curves.easeOutBack,
    );
    
    // 检查初始渲染状态
    _checkRenderingState();
  }

  @override
  void dispose() {
    _renderingController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SettingNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检查渲染状态变化
    _checkRenderingState();
  }
  
  /// 检查并处理渲染状态变化
  void _checkRenderingState() {
    final renderInfo = widget.nodeRenderStates[widget.node.id];
    
    if (renderInfo?.state == NodeRenderState.rendering) {
      // 开始渲染动画
      _renderingController.forward();
    } else if (renderInfo?.state == NodeRenderState.rendered) {
      // 确保渲染动画完成
      _renderingController.value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔧 关键修复：始终返回相同的widget结构，用Opacity控制可见性
    return _buildAlwaysStableWidget();
  }

  /// 🔧 核心修复：构建绝对稳定的widget，永远不改变结构
  Widget _buildAlwaysStableWidget() {
    final renderInfo = widget.nodeRenderStates[widget.node.id];
    final isRendering = renderInfo?.state == NodeRenderState.rendering;
    final isRendered = widget.renderedNodeIds.contains(widget.node.id);
    
    // 🔧 关键：确定最终可见性，但不改变widget树结构
    final shouldShow = isRendered || isRendering;
    final opacity = shouldShow ? 1.0 : 0.0;
    
    // 🔧 绝对稳定的widget结构：始终存在，只改变可见性
    Widget nodeContent = Column(
      key: ValueKey('stable_node_${widget.node.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNodeHeader(),
        // 🔧 子节点容器：始终存在，只改变内容可见性
        if (widget.renderChildren && widget.node.children != null && widget.node.children!.isNotEmpty)
          _buildStableChildrenContainer(),
      ],
    );

    // 🔧 使用Opacity + IgnorePointer确保不可见时完全不可交互
    Widget result = Opacity(
      opacity: opacity,
      child: IgnorePointer(
        ignoring: !shouldShow,
        child: nodeContent,
      ),
    );

    // 🔧 只有在渲染中时才应用动画效果
    if (isRendering) {
      result = AnimatedBuilder(
        animation: _renderingAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.95 + (_renderingAnimation.value * 0.05),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withOpacity(0.15 * _renderingAnimation.value),
                    blurRadius: 4 * _renderingAnimation.value,
                    spreadRadius: 1 * _renderingAnimation.value,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: result,
      );
    }

    return result;
  }
  
  /// 🔧 构建稳定的子节点容器：始终分配所有空间
  Widget _buildStableChildrenContainer() {
    // 使用 AnimatedSize + ClipRect 避免从 null 到 0 的高度动画在 Web 上导致异常
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topLeft,
        curve: Curves.easeInOut,
        child: _isExpanded
            ? Container(
                padding: const EdgeInsets.only(top: 4),
                child: _buildAbsolutelyStableChildrenList(),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
  
  /// 🔧 终极修复：构建绝对稳定的子节点列表
  Widget _buildAbsolutelyStableChildrenList() {
    if (widget.node.children == null || widget.node.children!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 🔧 终极方案：为所有子节点预分配固定空间，每个子节点自己控制可见性
    // 这确保Column的children数量和类型永远不变
    return Column(
      key: ValueKey('stable_children_${widget.node.id}'),
      mainAxisSize: MainAxisSize.min,
      children: widget.node.children!.map((child) {
        return Container(
          key: ValueKey('stable_child_container_${child.id}'),
          margin: const EdgeInsets.only(bottom: 4),
          child: SettingNodeWidget(
            key: ValueKey('stable_child_widget_${child.id}'),
            node: child,
            selectedNodeId: widget.selectedNodeId,
            viewMode: widget.viewMode,
            level: widget.level + 1,
            onTap: widget.onTap,
            renderedNodeIds: widget.renderedNodeIds,
            nodeRenderStates: widget.nodeRenderStates,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNodeHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final renderInfo = widget.nodeRenderStates[widget.node.id];
    final isRendering = renderInfo?.state == NodeRenderState.rendering;
    
    // 只有当前节点被选中时才显示选中状态，子节点不继承
    final isCurrentNodeSelected = widget.selectedNodeId == widget.node.id;
    
    // 根据Node.js版本的 paddingLeft: `${level * 1.5 + 0.5}rem`
    final leftPadding = widget.level * 24.0 + 8.0; // 1rem = 16px, 1.5rem = 24px
    
    return InkWell(
      onTap: () => widget.onTap(widget.node.id),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: leftPadding,
          right: 8,
          top: widget.viewMode == 'compact' ? 8 : 12,
          bottom: widget.viewMode == 'compact' ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          border: isCurrentNodeSelected
              ? Border.all(
                  color: const Color(0xFF6366F1), // indigo-500
                  width: 2,
                )
              : isRendering
                  ? Border.all(
                      color: const Color(0xFF3B82F6), // blue-500
                      width: 1,
                    )
                  : null,
        ),
        child: Row(
          crossAxisAlignment: widget.viewMode == 'compact' 
              ? CrossAxisAlignment.center 
              : CrossAxisAlignment.start,
          children: [
            // Rendering indicator
            if (isRendering)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8, top: 2),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF3B82F6), // blue-500
                  ),
                ),
              ),
            // Expand/collapse icon
            InkWell(
              onTap: _toggleExpanded,
              child: Container(
                width: 16,
                height: 16,
                margin: EdgeInsets.only(
                  right: 8,
                  top: widget.viewMode == 'detailed' ? 4 : 0,
                ),
                child: (widget.renderChildren && widget.node.children != null && widget.node.children!.isNotEmpty)
                    ? AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: const Color(0xFF6B7280), // gray-500
                        ),
                      )
                    : Icon(
                        Icons.description,
                        size: 16,
                        color: isDark 
                            ? const Color(0xFF4B5563) // gray-600 dark
                            : const Color(0xFF9CA3AF), // gray-400
                      ),
              ),
            ),
            // Node content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 状态图标（小）
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildStatusIcon(),
                      ),
                      Expanded(
                        child: Text(
                          widget.node.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isCurrentNodeSelected
                                ? const Color(0xFF6366F1) // indigo-500
                                : isRendering 
                                    ? const Color(0xFF3B82F6) // blue-500
                                    : (isDark 
                                        ? const Color(0xFFF9FAFB) 
                                        : const Color(0xFF111827)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildTypeChip(),
                      if (isRendering)
                        Text(
                          '生成中...',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF3B82F6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  if (widget.viewMode == 'detailed' && widget.node.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        widget.node.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark 
                              ? const Color(0xFF9CA3AF) // gray-400 dark
                              : const Color(0xFF6B7280), // gray-500
                          height: 1.5,
                        ),
                        maxLines: 20,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    // 移除“待处理”状态下的时钟图标
    if (widget.node.generationStatus == GenerationStatus.pending) {
      return const SizedBox.shrink();
    }

    IconData icon;
    Color color;

    switch (widget.node.generationStatus) {
      case GenerationStatus.generating:
        icon = Icons.autorenew;
        color = Colors.blue;
        break;
      case GenerationStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case GenerationStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case GenerationStatus.modified:
        icon = Icons.edit;
        color = Colors.purple;
        break;
      case GenerationStatus.pending:
        // 已在上方提前返回
        icon = Icons.check_circle; // 占位，不会被使用
        color = Colors.transparent;
        break;
    }

    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }

  Widget _buildTypeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        widget.node.type.displayName,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: WebTheme.getPrimaryColor(context),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (widget.selectedNodeId == widget.node.id) {
      return isDark 
          ? const Color(0xFF1E1B4B) // indigo-900/50 dark
          : const Color(0xFFE0E7FF); // indigo-100
    } else {
      return Colors.transparent;
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }
}
