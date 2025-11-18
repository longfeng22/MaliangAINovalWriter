/// 任务类型和状态的中文翻译映射工具类
class TaskTranslation {
  /// 私有构造函数，防止实例化
  TaskTranslation._();

  /// 任务类型的中文映射
  static const Map<String, String> _taskTypeMap = {
    // 生成类任务（与后端TaskType保持一致）
    'CONTINUE_WRITING_CONTENT': '自动续写',
    'GENERATE_SINGLE_CHAPTER': '章节生成',
    'GENERATE_SINGLE_SUMMARY': '摘要生成',
    'GENERATE_SCENE': '场景生成',
    'GENERATE_SUMMARY': '生成摘要',
    
    // 批量任务
    'BATCH_GENERATE_SUMMARY': '批量生成摘要',
    'BATCH_GENERATE_SCENE': '批量生成场景',
    
    // AI功能类任务
    'SCENE_TO_SUMMARY': '场景生成摘要',
    'SUMMARY_TO_SCENE': '摘要生成场景',
    'TEXT_EXPANSION': '文本扩写',
    'TEXT_REFACTOR': '文本重构',
    'TEXT_SUMMARY': '文本摘要',
    'AI_CHAT': 'AI对话',
    'NOVEL_GENERATION': '小说生成',
    'PROFESSIONAL_FICTION_CONTINUATION': '专业小说续写',
    'SCENE_BEAT_GENERATION': '场景节拍生成',
    'NOVEL_COMPOSE': '小说编排',
    'SETTING_TREE_GENERATION': '设定树生成',
    'STORY_PREDICTION': '剧情推演',
    'STORY_PREDICTION_SINGLE': '剧情预测',
    
    // 小说结构相关
    'CREATE_NOVEL_STRUCTURE': '创建小说结构',
    'ANALYZE_NOVEL_STRUCTURE': '分析小说结构',
    'OPTIMIZE_PLOT': '剧情优化',
    
    // 设定生成相关
    'GENERATE_CHARACTER': '角色生成',
    'GENERATE_LOCATION': '地点生成',
    'GENERATE_WORLD_BUILDING': '世界观构建',
    'GENERATE_SETTING': '设定生成',
    
    // 系统任务
    'EXPORT_NOVEL': '导出小说',
    'IMPORT_NOVEL': '导入小说',
    'BACKUP_DATA': '数据备份',
    'RESTORE_DATA': '数据恢复',
    
    // 知识提取（拆书）任务
    'KNOWLEDGE_EXTRACTION_FANQIE': '番茄小说拆书',
    'KNOWLEDGE_EXTRACTION_TEXT': '文本拆书',
    'KNOWLEDGE_EXTRACTION_GROUP': '知识提取组',
  };

  /// 任务事件类型和状态的中文映射
  static const Map<String, String> _taskStatusMap = {
    // SSE事件类型（前端接收到的type字段）
    'TASK_SUBMITTED': '任务已提交',
    'TASK_STARTED': '任务启动',
    'TASK_PROGRESS': '进行中',
    'TASK_COMPLETED': '已完成',
    'TASK_FAILED': '执行失败',
    'HEARTBEAT': '心跳',
    
    // 后端TaskStatus枚举
    'QUEUED': '队列中',
    'RUNNING': '执行中',
    'COMPLETED': '已完成',
    'FAILED': '执行失败',
    'CANCELLED': '已取消',
    'RETRYING': '重试中',
    'DEAD_LETTER': '失效',
    'COMPLETED_WITH_ERRORS': '部分完成',
    
    // 兼容旧状态
    'PENDING': '等待中',
    'TASK_CANCELLED': '已取消',
    'TASK_TIMEOUT': '超时',
    'TASK_PAUSED': '已暂停',
    
    // 详细进度状态（来自progress字段）
    'PREPARING': '准备中',
    'PROCESSING': '处理中',
    'VALIDATING': '验证中',
    'FINALIZING': '完成中',
    'STARTING': '启动中',
    'FINISHED': '已结束',
    'RECOVERING': '恢复中',
    
    // 续写任务特有状态
    'GENERATING_SUMMARIES': '生成摘要中',
    'WAITING_FOR_REVIEW': '等待评审',
    'GENERATING_CONTENT': '生成内容中',
    'GENERATING_OUTLINE': '生成大纲',
    'GENERATING_SUMMARY': '生成摘要',
    'SUMMARY_GENERATED_AND_CHAPTER_CREATED': '摘要已生成，章节已创建',
    'CONTENT_GENERATED': '内容已生成',
    'CONTENT_PERSISTED': '内容已保存',
    
    // 动态步骤状态（包含章节编号的状态）
    'PROCESSING_CHAPTER_': '处理章节',
    'COMPLETED_CHAPTER_': '完成章节',
    'FAILED_CHAPTER_': '章节失败',
    'GENERATING_SUMMARY_': '生成摘要',
    'GENERATING_CONTENT_': '生成内容',
    
    // 评审相关状态
    'PENDING_REVIEW': '待评审',
    'REVIEWING': '评审中',
    'REVIEW_COMPLETED': '评审完成',
    'REVIEW_REJECTED': '评审被拒',
    
    // 错误状态
    'VALIDATION_ERROR': '验证错误',
    'GENERATION_ERROR': '生成错误',
    'SAVE_ERROR': '保存错误',
    'NETWORK_ERROR': '网络错误',
    'AI_SERVICE_ERROR': 'AI服务错误',
  };

  /// 获取任务类型的中文名称
  static String getTaskTypeName(String? taskType) {
    if (taskType == null || taskType.isEmpty) return '未知任务';
    return _taskTypeMap[taskType.toUpperCase()] ?? taskType;
  }

  /// 获取任务状态的中文名称
  static String getTaskStatusName(String? status) {
    if (status == null || status.isEmpty) return '未知状态';
    final upperStatus = status.toUpperCase();
    
    // 直接查找映射
    String? result = _taskStatusMap[upperStatus];
    if (result != null) return result;
    
    // 处理动态状态（包含章节编号的状态）
    for (final prefix in ['PROCESSING_CHAPTER_', 'COMPLETED_CHAPTER_', 'FAILED_CHAPTER_', 'GENERATING_SUMMARY_', 'GENERATING_CONTENT_']) {
      if (upperStatus.startsWith(prefix)) {
        final baseName = _taskStatusMap[prefix] ?? prefix.replaceAll('_', '');
        final chapterNum = upperStatus.substring(prefix.length);
        return '$baseName $chapterNum';
      }
    }
    
    // 兜底：返回原始状态
    return status;
  }

  /// 获取智能任务状态（优先从progress获取详细状态，再从事件类型获取）
  static String getSmartTaskStatus(Map<String, dynamic> taskEvent) {
    // 0. 若事件类型已是终态，优先返回终态，避免被陈旧的 progress 覆盖
    final eventType = taskEvent['type']?.toString();
    const terminalTypes = {
      'TASK_COMPLETED', 'TASK_FAILED', 'TASK_CANCELLED', 'TASK_DEAD_LETTER', 'TASK_COMPLETED_WITH_ERRORS'
    };
    if (eventType != null && terminalTypes.contains(eventType)) {
      return getTaskStatusName(eventType);
    }

    // 1. 尝试从progress.currentStep获取详细状态
    final progress = taskEvent['progress'];
    if (progress is Map<String, dynamic>) {
      final currentStep = progress['currentStep']?.toString();
      if (currentStep != null && currentStep.isNotEmpty && currentStep != 'null') {
        return getTaskStatusName(currentStep);
      }
    }
    
    // 2. 使用事件类型作为状态
    return getTaskStatusName(eventType);
  }

  /// 获取任务状态的颜色
  static String getTaskStatusColor(String? status) {
    if (status == null || status.isEmpty) return 'grey';
    final upperStatus = status.toUpperCase();
    
    // 成功状态
    if (upperStatus == 'TASK_COMPLETED' || 
        upperStatus == 'COMPLETED' ||
        upperStatus == 'REVIEW_COMPLETED' ||
        upperStatus == 'FINISHED' ||
        upperStatus == 'CONTENT_PERSISTED' ||
        upperStatus.startsWith('COMPLETED_CHAPTER_')) {
      return 'success';
    }
    
    // 失败状态
    if (upperStatus == 'TASK_FAILED' || 
        upperStatus == 'FAILED' ||
        upperStatus == 'TASK_CANCELLED' ||
        upperStatus == 'CANCELLED' ||
        upperStatus == 'TASK_TIMEOUT' ||
        upperStatus == 'DEAD_LETTER' ||
        upperStatus.contains('ERROR') ||
        upperStatus == 'REVIEW_REJECTED' ||
        upperStatus.startsWith('FAILED_CHAPTER_')) {
      return 'error';
    }
    
    // 进行中状态
    if (upperStatus == 'TASK_STARTED' ||
        upperStatus == 'RUNNING' ||
        upperStatus == 'TASK_PROGRESS' ||
        upperStatus == 'RETRYING' ||
        upperStatus == 'PREPARING' ||
        upperStatus == 'PROCESSING' ||
        upperStatus == 'VALIDATING' ||
        upperStatus == 'FINALIZING' ||
        upperStatus == 'STARTING' ||
        upperStatus.startsWith('GENERATING_') ||
        upperStatus == 'REVIEWING' ||
        upperStatus.startsWith('PROCESSING_CHAPTER_')) {
      return 'primary';
    }
    
    // 等待状态
    if (upperStatus == 'PENDING' ||
        upperStatus == 'QUEUED' ||
        upperStatus == 'TASK_SUBMITTED' ||
        upperStatus == 'TASK_PAUSED' ||
        upperStatus == 'PENDING_REVIEW' ||
        upperStatus == 'WAITING_FOR_REVIEW') {
      return 'warning';
    }
    
    // 部分完成状态
    if (upperStatus == 'COMPLETED_WITH_ERRORS') {
      return 'warning';
    }
    
    // 默认状态
    return 'secondary';
  }

  /// 判断任务是否完成
  static bool isTaskCompleted(String? status) {
    if (status == null || status.isEmpty) return false;
    final upperStatus = status.toUpperCase();
    return upperStatus == 'TASK_COMPLETED' || 
           upperStatus == 'COMPLETED' ||
           upperStatus == 'FINISHED' ||
           upperStatus == 'CONTENT_PERSISTED' ||
           upperStatus.startsWith('COMPLETED_CHAPTER_');
  }

  /// 判断任务是否失败
  static bool isTaskFailed(String? status) {
    if (status == null || status.isEmpty) return false;
    final upperStatus = status.toUpperCase();
    return upperStatus == 'TASK_FAILED' || 
           upperStatus == 'FAILED' ||
           upperStatus == 'TASK_CANCELLED' ||
           upperStatus == 'CANCELLED' ||
           upperStatus == 'TASK_TIMEOUT' ||
           upperStatus == 'DEAD_LETTER' ||
           upperStatus.contains('ERROR') ||
           upperStatus.startsWith('FAILED_CHAPTER_');
  }

  /// 判断任务是否正在运行
  static bool isTaskRunning(String? status) {
    if (status == null || status.isEmpty) return false;
    final upperStatus = status.toUpperCase();
    return upperStatus == 'TASK_STARTED' || 
           upperStatus == 'RUNNING' ||
           upperStatus == 'TASK_PROGRESS' ||
           upperStatus == 'RETRYING' ||
           upperStatus == 'PREPARING' ||
           upperStatus == 'PROCESSING' ||
           upperStatus == 'VALIDATING' ||
           upperStatus == 'FINALIZING' ||
           upperStatus == 'STARTING' ||
           upperStatus.startsWith('GENERATING_') ||
           upperStatus == 'REVIEWING' ||
           upperStatus.startsWith('PROCESSING_CHAPTER_');
  }
  
  /// 判断任务是否等待中
  static bool isTaskPending(String? status) {
    if (status == null || status.isEmpty) return false;
    final upperStatus = status.toUpperCase();
    return upperStatus == 'PENDING' ||
           upperStatus == 'QUEUED' ||
           upperStatus == 'TASK_SUBMITTED' ||
           upperStatus == 'PENDING_REVIEW' ||
           upperStatus == 'WAITING_FOR_REVIEW';
  }

  /// 获取任务优先级显示文本
  static String getPriorityText(String? priority) {
    if (priority == null || priority.isEmpty) return '普通';
    switch (priority.toUpperCase()) {
      case 'HIGH':
      case 'URGENT':
        return '高优先级';
      case 'MEDIUM':
      case 'NORMAL':
        return '普通';
      case 'LOW':
        return '低优先级';
      default:
        return priority;
    }
  }

  /// 获取任务执行时长的友好显示
  static String getExecutionDuration(DateTime? startTime, DateTime? endTime) {
    if (startTime == null) return '未知';
    
    final endDateTime = endTime ?? DateTime.now();
    final duration = endDateTime.difference(startTime);
    
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}秒';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}分钟';
    } else if (duration.inDays < 1) {
      return '${duration.inHours}小时${duration.inMinutes % 60}分钟';
    } else {
      return '${duration.inDays}天${duration.inHours % 24}小时';
    }
  }

  /// 调试方法：打印任务事件的详细信息
  /// 注意：使用 kDebugMode 来控制，避免生产环境输出调试信息
  static void debugTaskEvent(Map<String, dynamic> taskEvent, [String? context]) {
    // 只在调试模式下输出，避免生产环境控制台日志
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      print('=== TaskEvent Debug ${context ?? ''} ===');
      print('Keys: ${taskEvent.keys.toList()}');
      print('type: ${taskEvent['type']}');
      print('taskType: ${taskEvent['taskType']}');
      print('taskId: ${taskEvent['taskId']}');
      print('parentTaskId: ${taskEvent['parentTaskId']}');
      if (taskEvent.containsKey('progress')) {
        final progress = taskEvent['progress'];
        print('progress type: ${progress.runtimeType}');
        if (progress is Map<String, dynamic>) {
          print('progress keys: ${progress.keys.toList()}');
          print('currentStep: ${progress['currentStep']}');
        } else {
          print('progress value: $progress');
        }
      }
      print('Parsed status: ${getSmartTaskStatus(taskEvent)}');
      print('Status color: ${getTaskStatusColor(getSmartTaskStatus(taskEvent))}');
      print('================');
    }
  }
}
