/// 拆书进度对话框
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_bloc.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_event.dart';
import 'package:ainoval/blocs/knowledge_base/knowledge_base_state.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/screens/knowledge_base/knowledge_base_detail_screen.dart';

/// 拆书进度对话框
class ExtractionProgressDialog extends StatefulWidget {
  final String taskId;

  const ExtractionProgressDialog({
    Key? key,
    required this.taskId,
  }) : super(key: key);

  @override
  State<ExtractionProgressDialog> createState() => _ExtractionProgressDialogState();
}

class _ExtractionProgressDialogState extends State<ExtractionProgressDialog> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // 首次立即查询
    context.read<KnowledgeBaseBloc>().add(LoadExtractionTaskStatus(widget.taskId));
    
    // 每2秒轮询一次
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      context.read<KnowledgeBaseBloc>().add(LoadExtractionTaskStatus(widget.taskId));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<KnowledgeBaseBloc, KnowledgeBaseState>(
      listener: (context, state) {
        if (state is ExtractionTaskStatusUpdated) {
          // 如果任务完成，停止轮询并导航到知识库详情
          if (state.taskResponse.status == 'COMPLETED' && 
              state.taskResponse.knowledgeBaseId != null) {
            _pollTimer?.cancel();
            Navigator.pop(context); // 关闭对话框
            // 导航到知识库详情页
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => KnowledgeBaseDetailScreen(
                  knowledgeBaseId: state.taskResponse.knowledgeBaseId!,
                ),
              ),
            );
          }
          
          // 如果任务失败，停止轮询
          if (state.taskResponse.status == 'FAILED') {
            _pollTimer?.cancel();
          }
        }
      },
      builder: (context, state) {
        if (state is ExtractionTaskStatusUpdated) {
          return _buildProgressDialog(state);
        }
        
        return _buildLoadingDialog();
      },
    );
  }

  Widget _buildLoadingDialog() {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在准备拆书任务...',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDialog(ExtractionTaskStatusUpdated state) {
    final task = state.taskResponse;
    final progress = task.progress ?? 0;
    final isCompleted = task.status == 'COMPLETED';
    final isFailed = task.status == 'FAILED';
    final isProcessing = task.status == 'PROCESSING' || task.status == 'PENDING';

    return AlertDialog(
      title: Text(
        isCompleted ? '拆书完成' : isFailed ? '拆书失败' : '拆书进行中',
        style: TextStyle(
          color: isCompleted ? Colors.green : isFailed ? Colors.red : null,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isProcessing) ...[
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 8,
              backgroundColor: WebTheme.getBorderColor(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                WebTheme.getPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$progress%',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          
          if (task.message != null)
            Text(
              task.message!,
              style: TextStyle(
                fontSize: 14,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          
          if (isCompleted) ...[
            const SizedBox(height: 16),
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              '知识库已生成完成！',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          if (isFailed) ...[
            const SizedBox(height: 16),
            Icon(
              Icons.error,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              '拆书任务失败',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          if (task.estimatedCompletionTime != null && isProcessing) ...[
            const SizedBox(height: 12),
            Text(
              '预计完成时间: ${_formatTime(task.estimatedCompletionTime!)}',
              style: TextStyle(
                fontSize: 12,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (isCompleted || isFailed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isCompleted ? '关闭' : '确定'),
          ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    
    if (diff.inMinutes < 1) {
      return '不到1分钟';
    } else if (diff.inMinutes < 60) {
      return '约${diff.inMinutes}分钟';
    } else {
      return '约${diff.inHours}小时';
    }
  }
}

