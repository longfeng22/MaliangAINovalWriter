import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service/base/api_client.dart';
import '../../utils/web_theme.dart';
import '../../utils/date_time_parser.dart';

/// AI拆书任务管理页面
class KnowledgeExtractionTaskManagementPage extends StatefulWidget {
  const KnowledgeExtractionTaskManagementPage({Key? key}) : super(key: key);

  @override
  State<KnowledgeExtractionTaskManagementPage> createState() =>
      _KnowledgeExtractionTaskManagementPageState();
}

class _KnowledgeExtractionTaskManagementPageState
    extends State<KnowledgeExtractionTaskManagementPage> {
  final ApiClient _apiClient = ApiClient();
  
  List<Map<String, dynamic>> _tasks = [];
  Map<String, dynamic>? _statistics;
  bool _loading = false;
  String? _selectedStatus;
  int _currentPage = 0;
  final int _pageSize = 20;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadStatistics();
  }

  /// 加载任务列表
  Future<void> _loadTasks() async {
    setState(() => _loading = true);

      try {
      String url = '/knowledge-extraction-tasks?page=$_currentPage&size=$_pageSize';
      if (_selectedStatus != null) {
        url += '&status=$_selectedStatus';
      }
      
      final response = await _apiClient.get(url);

      // ✅ ApiResponse 使用 success 字段，而不是 code
      if (response['success'] == true) {
        final data = response['data'];
        print('📋 加载任务列表成功: data=$data');
        print('📋 tasks字段: ${data['tasks']}');
        print('📋 tasks类型: ${data['tasks'].runtimeType}');
        print('📋 tasks数量: ${data['tasks']?.length}');
        
        setState(() {
          _tasks = List<Map<String, dynamic>>.from(data['tasks'] ?? []);
          _totalPages = data['totalPages'] ?? 0;
          print('📋 setState后_tasks数量: ${_tasks.length}');
        });
      } else {
        print('❌ 加载任务列表失败: success=${response['success']}, message=${response['message']}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载任务列表失败: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 加载统计信息
  Future<void> _loadStatistics() async {
    try {
      final response = await _apiClient.get(
        '/knowledge-extraction-tasks/statistics',
      );

      // ✅ ApiResponse 使用 success 字段，而不是 code
      if (response['success'] == true) {
        setState(() {
          _statistics = response['data'];
        });
      }
    } catch (e) {
      print('加载统计信息失败: $e');
    }
  }

  /// 重试任务
  Future<void> _retryTask(String taskId) async {
    try {
      final response = await _apiClient.post(
        '/knowledge-extraction-tasks/$taskId/retry',
      );

      // ✅ ApiResponse 使用 success 字段，而不是 code
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已重新提交')),
        );
        _loadTasks();
        _loadStatistics();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试失败: ${response['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重试失败: $e')),
      );
    }
  }

  /// 查看任务详情
  Future<void> _showTaskDetail(String taskId) async {
    try {
      final response = await _apiClient.get(
        '/knowledge-extraction-tasks/$taskId',
      );

      // ✅ ApiResponse 使用 success 字段，而不是 code
      if (response['success'] == true) {
        final task = response['data'];
        showDialog(
          context: context,
          builder: (context) => TaskDetailDialog(
            task: task,
            onRetry: () => _retryTask(taskId),
            onRetrySubTask: (subTaskId) => _retrySubTask(taskId, subTaskId),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载任务详情失败: $e')),
      );
    }
  }

  /// 重试子任务
  Future<void> _retrySubTask(String taskId, String subTaskId) async {
    try {
      final response = await _apiClient.post(
        '/knowledge-extraction-tasks/$taskId/sub-tasks/$subTaskId/retry',
      );

      // ✅ ApiResponse 使用 success 字段，而不是 code
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('子任务已重新提交')),
        );
        Navigator.pop(context); // 关闭详情对话框
        _loadTasks();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试失败: ${response['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重试失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI拆书任务管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadTasks();
              _loadStatistics();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计卡片
          if (_statistics != null) _buildStatisticsCard(),
          
          // 筛选器
          _buildFilterBar(),
          
          // 任务列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildTaskList(),
          ),
          
          // 分页控件
          if (_totalPages > 1) _buildPagination(),
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatisticsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('总计', _statistics!['total'], Colors.blue),
          _buildStatItem('完成', _statistics!['completed'], Colors.green),
          _buildStatItem('失败', _statistics!['failed'], Colors.red),
          _buildStatItem('运行中', _statistics!['running'], Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int? value, Color color) {
    return Column(
      children: [
        Text(
          '${value ?? 0}',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('状态筛选：'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String?>(
              value: _selectedStatus,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: 'QUEUED', child: Text('排队中')),
                DropdownMenuItem(value: 'EXTRACTING', child: Text('提取中')),
                DropdownMenuItem(value: 'COMPLETED', child: Text('已完成')),
                DropdownMenuItem(value: 'FAILED', child: Text('失败')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedStatus = value;
                  _currentPage = 0;
                });
                _loadTasks();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建任务列表
  Widget _buildTaskList() {
    print('🎨 _buildTaskList被调用: _tasks.length=${_tasks.length}, _tasks=$_tasks');
    
    if (_tasks.isEmpty) {
      print('⚠️ _tasks为空，显示"暂无任务"');
      return const Center(child: Text('暂无任务'));
    }

    print('✅ 正在渲染${_tasks.length}个任务');
    return ListView.builder(
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        print('📝 渲染任务[$index]: id=${task['id']}, title=${task['novelTitle']}');
        return _buildTaskCard(task);
      },
    );
  }

  /// ✨ 构建任务卡片（现代化设计）
  Widget _buildTaskCard(Map<String, dynamic> task) {
    final status = task['status'] as String;
    final color = _getStatusColor(status);
    final progress = task['progress'] as int? ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showTaskDetail(task['id']),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getTaskStatusIcon(status),
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task['novelTitle'] ?? '未知小说',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '作者：${task['novelAuthor'] ?? '未知'}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _getStatusText(status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 进度条
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '当前步骤：${_getStatusText(task['currentStep'] ?? '未知')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$progress%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 底部信息行
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '创建：${_formatDateTime(task['createdAt'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.update, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '更新：${_formatDateTime(task['updatedAt'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const Spacer(),
                    // 重试按钮
                    if (status == 'FAILED' && (task['retryCount'] ?? 0) < 3)
                      ElevatedButton.icon(
                        onPressed: () => _retryTask(task['id']),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重试', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✨ 获取任务状态图标
  IconData _getTaskStatusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      case 'FAILED':
        return Icons.error_rounded;
      case 'EXTRACTING':
        return Icons.sync_rounded;
      case 'QUEUED':
        return Icons.schedule_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  /// 构建分页控件
  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () {
                    setState(() => _currentPage--);
                    _loadTasks();
                  }
                : null,
          ),
          Text('${_currentPage + 1} / $_totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _totalPages - 1
                ? () {
                    setState(() => _currentPage++);
                    _loadTasks();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green;
      case 'FAILED':
        return Colors.red;
      case 'EXTRACTING':
        return Colors.orange;
      case 'QUEUED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'QUEUED':
        return '排队中';
      case 'INITIALIZING':
        return '初始化';
      case 'DOWNLOADING':
        return '下载中';
      case 'EXTRACTING':
        return '提取中';
      case 'AGGREGATING':
        return '聚合中';
      case 'COMPLETED':
        return '已完成';
      case 'FAILED':
        return '失败';
      default:
        return status;
    }
  }

  String _formatDateTime(dynamic dateTimeValue) {
    if (dateTimeValue == null) return '未知';
    try {
      // ✅ 使用标准的日期解析函数，支持 LocalDateTime 数组格式
      final dateTime = parseBackendDateTime(dateTimeValue);
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    } catch (e) {
      print('⚠️ 日期解析失败: $dateTimeValue, error: $e');
      return '未知';
    }
  }
}

/// 任务详情对话框
class TaskDetailDialog extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onRetry;
  final Function(String) onRetrySubTask;

  const TaskDetailDialog({
    Key? key,
    required this.task,
    required this.onRetry,
    required this.onRetrySubTask,
  }) : super(key: key);

  /// ✅ 格式化日期时间（支持 LocalDateTime 数组格式）
  String _formatDateTime(dynamic dateTimeValue) {
    if (dateTimeValue == null) return '-';
    try {
      final dateTime = parseBackendDateTime(dateTimeValue);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
    } catch (e) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subTasks = task['subTasks'] as List? ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = task['status'] as String;
    final statusColor = _getStatusColor(status);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 700,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✨ 现代化标题栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    statusColor.withOpacity(0.1),
                    statusColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: statusColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['novelTitle'] ?? '任务详情',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusText(status),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${task['progress'] ?? 0}%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            
            // ✨ 现代化内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 📊 关键指标卡片
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            context,
                            Icons.timer_outlined,
                            '耗时',
                            task['durationMs'] != null
                                ? '${(task['durationMs'] / 1000).toStringAsFixed(1)}s'
                                : '-',
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            context,
                            Icons.description_outlined,
                            '生成设定',
                            task['totalSettings']?.toString() ?? '-',
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            context,
                            Icons.token_outlined,
                            'Token',
                            task['totalTokens']?.toString() ?? '-',
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // 📝 详细信息区域
                    _buildSectionTitle(context, '任务信息'),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      context,
                      [
                        _buildInfoRow('任务ID', task['id']),
                        _buildInfoRow('当前步骤', task['currentStep']),
                        _buildInfoRow('开始时间', _formatDateTime(task['startTime'])),
                        _buildInfoRow('结束时间', _formatDateTime(task['endTime'])),
                        if (task['knowledgeBaseId'] != null)
                          _buildInfoRow('知识库ID', task['knowledgeBaseId']),
                      ],
                    ),
                    
                    // ⚠️ 错误信息
                    if (task['errorMessage'] != null) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle(context, '错误信息', color: Colors.red),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                task['errorMessage'],
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // 📋 子任务列表
                    if (subTasks.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          _buildSectionTitle(context, '子任务列表'),
                          const Spacer(),
                          Text(
                            '${subTasks.length} 个子任务',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...subTasks.map((subTask) => _buildSubTaskCard(
                            context,
                            subTask,
                          )),
                    ],
                  ],
                ),
              ),
            ),
            
            // ✨ 现代化底部操作栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (task['status'] == 'FAILED')
                    ElevatedButton.icon(
                      onPressed: () {
                        onRetry();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试任务'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✨ 构建指标卡片
  Widget _buildMetricCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 构建章节标题
  Widget _buildSectionTitle(BuildContext context, String title, {Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: color ?? (isDark ? Colors.white : Colors.black87),
      ),
    );
  }

  /// ✨ 构建信息卡片
  Widget _buildInfoCard(BuildContext context, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// ✨ 构建信息行
  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label：',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 获取状态图标
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      case 'FAILED':
        return Icons.error_rounded;
      case 'EXTRACTING':
        return Icons.sync_rounded;
      case 'QUEUED':
        return Icons.schedule_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  /// ✨ 构建子任务卡片（现代化设计）
  Widget _buildSubTaskCard(BuildContext context, Map<String, dynamic> subTask) {
    final status = subTask['status'] as String;
    final color = _getSubTaskStatusColor(status);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = subTask['progress'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getSubTaskStatusIcon(status),
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subTask['groupName'] ?? '未知组',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '提取类型：${(subTask['extractionTypes'] as List?)?.join(', ') ?? '未知'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getSubTaskStatusText(status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status == 'FAILED') ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => onRetrySubTask(subTask['subTaskId']),
                  tooltip: '重试子任务',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // 进度条
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '进度',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ],
          ),
          // 错误信息
          if (subTask['errorMessage'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subTask['errorMessage'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 其他统计信息
          if (subTask['extractedCount'] != null || subTask['tokensUsed'] != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (subTask['extractedCount'] != null) ...[
                  Icon(Icons.description_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${subTask['extractedCount']} 个设定',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                ],
                if (subTask['tokensUsed'] != null) ...[
                  Icon(Icons.token_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${subTask['tokensUsed']} tokens',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ✨ 获取子任务状态图标
  IconData _getSubTaskStatusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      case 'FAILED':
        return Icons.error_rounded;
      case 'RUNNING':
        return Icons.sync_rounded;
      case 'PENDING':
        return Icons.schedule_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  /// ✨ 获取状态颜色
  Color _getStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green;
      case 'FAILED':
        return Colors.red;
      case 'EXTRACTING':
        return Colors.orange;
      case 'QUEUED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// ✨ 获取状态文本
  String _getStatusText(String status) {
    switch (status) {
      case 'QUEUED':
        return '排队中';
      case 'INITIALIZING':
        return '初始化';
      case 'DOWNLOADING':
        return '下载中';
      case 'EXTRACTING':
        return '提取中';
      case 'AGGREGATING':
        return '聚合中';
      case 'COMPLETED':
        return '已完成';
      case 'FAILED':
        return '失败';
      default:
        return status;
    }
  }

  Color _getSubTaskStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green;
      case 'FAILED':
        return Colors.red;
      case 'RUNNING':
        return Colors.orange;
      case 'PENDING':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getSubTaskStatusText(String status) {
    switch (status) {
      case 'PENDING':
        return '待执行';
      case 'RUNNING':
        return '执行中';
      case 'COMPLETED':
        return '已完成';
      case 'FAILED':
        return '失败';
      default:
        return status;
    }
  }
}

