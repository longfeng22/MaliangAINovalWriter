import 'package:flutter/material.dart';
import '../../../config/provider_icons.dart';

/// 模型服务卡片的数据模型
class ModelServiceData {
  final String id;
  final String name;
  final String provider;
  final String path;
  final bool verified;
  final bool isDefault;
  final String? status;
  final DateTime timestamp;
  final String? description;
  final List<String>? tags;
  final String? apiEndpoint;
  final ModelPerformance? performance;

  ModelServiceData({
    required this.id,
    required this.name,
    required this.provider,
    required this.path,
    required this.verified,
    required this.isDefault,
    this.status,
    required this.timestamp,
    this.description,
    this.tags,
    this.apiEndpoint,
    this.performance,
  });
}

/// 模型性能数据
class ModelPerformance {
  final int latency; // 毫秒
  final double throughput; // 请求/秒

  ModelPerformance({
    required this.latency,
    required this.throughput,
  });
}

/// 模型服务卡片组件
class ModelServiceCard extends StatefulWidget {
  const ModelServiceCard({
    super.key,
    required this.model,
    required this.onSetDefault,
    required this.onValidate,
    required this.onEdit,
    required this.onDelete,
  });

  final ModelServiceData model;
  final Function(String) onSetDefault;
  final Function(String) onValidate;
  final Function(String) onEdit;
  final Function(String) onDelete;

  @override
  State<ModelServiceCard> createState() => _ModelServiceCardState();
}

class _ModelServiceCardState extends State<ModelServiceCard> {
  bool _expanded = false;
  // 未使用的变量已移除

  // 获取提供商图标
  Widget _getProviderLogo(String provider) {
    return ProviderIcons.getProviderIconForContext(
      provider,
      iconSize: IconSize.medium,
    );
  }

  // 获取状态颜色（未使用，保留以备后续扩展）
  Color _getStatusColor(String status) {
    final statusLower = status.toLowerCase();
    if (statusLower.contains('error') || statusLower.contains('失败')) {
      return Theme.of(context).colorScheme.error;
    } else if (statusLower.contains('warning') || statusLower.contains('警告')) {
      return Theme.of(context).colorScheme.tertiary;
    } else {
      return Theme.of(context).colorScheme.primary;
    }
  }

  // 获取状态文本（未使用，保留以备后续扩展）
  String _getStatusText(String status) {
    return status;
  }

  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 获取性能颜色
  Color _getPerformanceColor(int latency) {
    if (latency < 100) {
      return Theme.of(context).colorScheme.secondary;
    } else if (latency < 300) {
      return Theme.of(context).colorScheme.tertiary;
    } else {
      return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.model.verified
              ? theme.colorScheme.outline.withAlpha(51)
              : theme.colorScheme.outline.withAlpha(77),
          width: widget.model.verified ? 0.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片主体内容
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：图标、名称和操作菜单
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 提供商图标
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: _getProviderLogo(widget.model.provider),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 名称和路径
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.model.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                widget.model.provider,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '•',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withAlpha(77),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    widget.model.path,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 操作菜单
                    PopupMenuButton(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: theme.colorScheme.onSurface.withAlpha(153),
                      ),
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16),
                              SizedBox(width: 8),
                              Text('编辑', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'copy_path',
                          child: Row(
                            children: [
                              Icon(Icons.copy, size: 16),
                              SizedBox(width: 8),
                              Text('复制模型路径', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        if (widget.model.apiEndpoint != null)
                          const PopupMenuItem<String>(
                            value: 'visit_api',
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new, size: 16),
                                SizedBox(width: 8),
                                Text('访问API', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                              const SizedBox(width: 8),
                              Text('删除', style: TextStyle(fontSize: 13, color: theme.colorScheme.error)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (String value) {
                        switch (value) {
                          case 'edit':
                            widget.onEdit(widget.model.id);
                            break;
                          case 'copy_path':
                            // 复制路径逻辑
                            break;
                          case 'visit_api':
                            // 访问API逻辑
                            break;
                          case 'delete':
                            widget.onDelete(widget.model.id);
                            break;
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 状态标签和时间戳
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 状态标签
                    Row(
                      children: [
                        // 验证状态
                          Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: widget.model.verified
                                  ? theme.colorScheme.secondaryContainer
                                  : theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: widget.model.verified
                                    ? theme.colorScheme.secondary.withOpacity(0.5)
                                    : theme.colorScheme.tertiary.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.model.verified
                                      ? Icons.check_circle_outline
                                      : Icons.access_time,
                                size: 12,
                                  color: widget.model.verified
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.model.verified ? '已验证' : '未验证',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                    color: widget.model.verified
                                        ? theme.colorScheme.onSecondaryContainer
                                        : theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 默认状态标签
                        if (widget.model.isDefault)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(26),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withAlpha(77),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 12,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '默认',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 工具默认状态标签
                        if ((widget.model as dynamic).isToolDefault == true)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondary.withAlpha(26),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.secondary.withAlpha(77),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.build,
                                    size: 12,
                                    color: theme.colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '工具默认',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    // 时间戳
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: theme.colorScheme.onSurface.withAlpha(128),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(widget.model.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withAlpha(128),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // 性能指标
                if (widget.model.performance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(77),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // 延迟
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '延迟',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withAlpha(153),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.bolt,
                                      size: 14,
                                      color: _getPerformanceColor(widget.model.performance!.latency),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.model.performance!.latency}ms',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _getPerformanceColor(widget.model.performance!.latency),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // 吞吐量
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '吞吐量',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withAlpha(153),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.model.performance!.throughput} 次/秒',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 展开的详情内容
                if (_expanded && widget.model.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          color: theme.colorScheme.outline.withAlpha(26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.model.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withAlpha(204),
                            height: 1.5,
                          ),
                        ),

                        // 标签
                        if (widget.model.tags != null && widget.model.tags!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: widget.model.tags!.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withAlpha(26),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withAlpha(77),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 底部操作区
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withAlpha(26),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // 查看详情按钮
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(77),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _expanded ? '收起详情' : '查看详情',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withAlpha(179),
                        ),
                      ),
                    ),
                  ),
                ),

                // 设为默认按钮（仅未验证时显示）
                Expanded(
                  child: InkWell(
                    onTap: () {
                      // 如果未验证，则执行验证逻辑
                      if (!widget.model.verified) {
                        widget.onValidate(widget.model.id);
                      } else {
                         // 如果已验证，则执行设为默认逻辑
                         if (!widget.model.isDefault) {
                          widget.onSetDefault(widget.model.id);
                         }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: theme.colorScheme.outline.withAlpha(26),
                            width: 1,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.model.verified
                           ? (widget.model.isDefault ? '默认模型' : '设为默认')
                           : '验证连接', // 未验证时显示验证
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: widget.model.verified && widget.model.isDefault
                              ? theme.colorScheme.onSurface.withAlpha(100) // 如果是默认，灰色显示
                              : theme.colorScheme.primary, // 否则高亮
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
