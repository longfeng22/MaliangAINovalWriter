import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// 日志级别
enum LogLevel {
  verbose, // 详细信息
  debug, // 调试信息
  info, // 普通信息
  warning, // 警告信息
  error, // 错误信息
  wtf // 严重错误
}

/// 应用程序日志管理类
class AppLogger {
  static bool _initialized = false;
  static final Map<String, Logger> _loggers = {};

  // 日志级别与Logging包级别的映射
  static final Map<LogLevel, Level> _levelMap = {
    LogLevel.verbose: Level.FINEST,
    LogLevel.debug: Level.FINE,
    LogLevel.info: Level.INFO,
    LogLevel.warning: Level.WARNING,
    LogLevel.error: Level.SEVERE,
    LogLevel.wtf: Level.SHOUT,
  };

  /// 初始化日志系统
  static void init() {
    if (_initialized) return;

    hierarchicalLoggingEnabled = true;

    // 根据编译时定义的LOG_LEVEL或调试模式来设置日志级别
    Logger.root.level = _getProductionLogLevel();

    // 配置日志监听器
    Logger.root.onRecord.listen((record) {
      // 根据当前设置的根级别进行过滤，避免输出低于设定级别的日志
      if (record.level < Logger.root.level) {
        return;
      }

      final lvlColor = _getLogLevelColor(record.level);
      const resetColor = '\x1B[0m'; // ANSI 重置颜色代码
      final emoji = _getLogEmoji(record.level);
      final timestamp = DateTime.now().toString().substring(0, 19);
      // 格式: 时间戳 [级别] [模块名] Emoji 日志内容
      final messageHeader =
          '$lvlColor$timestamp [${record.level.name}] [${record.loggerName}] $emoji $resetColor';
      final messageBody = '$lvlColor${record.message}$resetColor';

      final String logMessage;

      if (record.error != null) {
        // 添加错误详情和格式化的堆栈信息
        final errorString = '$lvlColor错误: ${record.error}$resetColor';
        // StackTrace 过滤：只显示应用相关的堆栈，限制行数
        final stackTraceString = _formatStackTrace(record.stackTrace,
            filterAppCode: true, maxLines: 15);
        logMessage =
            '$messageHeader $messageBody\n$errorString${stackTraceString.isNotEmpty ? '\n$lvlColor堆栈:$resetColor\n$stackTraceString' : ''}';
      } else {
        logMessage = '$messageHeader $messageBody';
      }

      // 使用 print 输出，以便颜色代码生效
      // 在 release 版本中，由于 Logger.root.level 的限制，低于 INFO 的日志不会走到这里
      print(logMessage);
    });

    _initialized = true;
  }

  /// 获取指定模块的日志记录器
  static Logger getLogger(String name) {
    if (!_initialized) init();

    return _loggers.putIfAbsent(name, () {
      final logger = Logger(name);
      logger.level = Logger.root.level;
      return logger;
    });
  }

  /// 记录详细日志
  static void v(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.verbose, message, error, stackTrace);
  }

  /// 记录调试日志
  static void d(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.debug, message, error, stackTrace);
  }

  /// 记录信息日志
  static void i(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.info, message, error, stackTrace);
  }

  /// 记录警告日志
  static void w(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.warning, message, error, stackTrace);
  }

  /// 记录错误日志
  static void e(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.error, message, error, stackTrace);
  }

  /// 记录严重错误日志
  static void wtf(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.wtf, message, error, stackTrace);
  }

  // 为了向后兼容，添加简化的方法名
  /// 记录信息日志（简化版）
  static void info(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.info, message, error, stackTrace);
  }

  /// 记录错误日志（简化版）
  static void error(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.error, message, error, stackTrace);
  }

  /// 获取生产环境日志级别
  static Level _getProductionLogLevel() {
    // 调试模式显示所有日志
    if (kDebugMode) {
      return Level.ALL;
    }
    
    // 检查编译时定义的LOG_LEVEL
    const String logLevelEnv = String.fromEnvironment('LOG_LEVEL', defaultValue: '');
    
    switch (logLevelEnv.toUpperCase()) {
      case 'VERBOSE':
        return Level.ALL;
      case 'DEBUG':
        return Level.FINE;
      case 'INFO':
        return Level.INFO;
      case 'WARN':
      case 'WARNING':
        return Level.WARNING;
      case 'ERROR':
        return Level.SEVERE;
      case 'OFF':
        return Level.OFF;
      case '':
      default:
        // 默认生产环境使用INFO级别
        return Level.INFO;
    }
  }

  /// 内部日志记录方法
  static void _log(String tag, LogLevel level, String message,
      [Object? error, StackTrace? stackTrace]) {
    final logger = getLogger(tag);
    final logLevel = _levelMap[level]!;

    logger.log(logLevel, message, error, stackTrace);
  }

  /// 获取日志级别对应的emoji
  static String _getLogEmoji(Level level) {
    if (level == Level.FINEST || level == Level.FINER || level == Level.FINE) {
      return '🔍'; // 调试
    }
    if (level == Level.CONFIG || level == Level.INFO) return '📘'; // 信息
    if (level == Level.WARNING) return '⚠️'; // 警告
    if (level == Level.SEVERE) return '❌'; // 错误
    if (level == Level.SHOUT) return '💥'; // 严重错误
    return '📝'; // 默认
  }

  /// 获取日志级别对应的ANSI颜色代码
  static String _getLogLevelColor(Level level) {
    if (level == Level.FINEST || level == Level.FINER || level == Level.FINE) {
      return '\x1B[90m'; // 灰色 (Verbose/Debug)
    }
    if (level == Level.CONFIG || level == Level.INFO) {
      return '\x1B[34m'; // 蓝色 (Info/Config)
    }
    if (level == Level.WARNING) return '\x1B[33m'; // 黄色 (Warning)
    if (level == Level.SEVERE) return '\x1B[31m'; // 红色 (Error)
    if (level == Level.SHOUT) return '\x1B[35;41m'; // 紫色 + 红色背景 (WTF/Shout)
    return '\x1B[0m'; // 默认 (重置)
  }

  /// 格式化并过滤堆栈信息
  static String _formatStackTrace(StackTrace? stackTrace,
      {int maxLines = 10, bool filterAppCode = true}) {
    if (stackTrace == null) return '';

    final lines = stackTrace.toString().split('\n');
    final formattedLines = <String>[];
    const appPackagePrefix = 'package:ainoval/'; // 修改为你的应用包名
    const flutterPackagePrefix = 'package:flutter/';
    const dartPrefix = 'dart:';

    int linesAdded = 0;
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      bool isAppCode = trimmedLine.contains(appPackagePrefix);
      bool isFrameworkCode = trimmedLine.contains(flutterPackagePrefix) ||
          trimmedLine.startsWith(dartPrefix);

      // 如果开启过滤，只保留应用代码；否则不过滤
      // 同时，排除纯dart:前缀和flutter框架内部调用（除非没有应用代码帧时酌情显示）
      if (!filterAppCode ||
          isAppCode ||
          (!isFrameworkCode && !trimmedLine.startsWith('#'))) {
        // 也包含一些非 package 的项目内部调用格式
        // 尝试保持可点击的格式
        // IDE 通常能识别类似 'package:my_app/my_file.dart:123:45' 的格式
        formattedLines.add('  $trimmedLine'); // 添加缩进
        linesAdded++;
        if (linesAdded >= maxLines) break; // 限制最大行数
      }
    }

    // 如果过滤后为空（可能错误发生在框架深处），则显示原始堆栈的前几行
    if (formattedLines.isEmpty && lines.isNotEmpty) {
      formattedLines.addAll(lines
          .take(maxLines)
          .map((l) => '  ${l.trim()}')
          .where((l) => l.length > 2));
    }

    return formattedLines.join('\n');
  }
}
