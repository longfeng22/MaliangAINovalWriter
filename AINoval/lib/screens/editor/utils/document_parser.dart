/**
 * 文档解析工具类
 * 
 * 用于解析和处理文本内容，将其转换为可编辑的Quill文档格式。
 * 提供两种解析方法：安全解析（在UI线程使用）和隔离解析（在计算隔离中使用）。
 */
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:ainoval/utils/logger.dart';

/// 优化的文档解析器
/// 
/// 包含以下优化特性：
/// 1. LRU缓存机制 - 避免重复解析
/// 2. 解析队列和优先级控制 - 减少并发竞争
/// 3. 批量解析 - 提高吞吐量
/// 4. 智能预解析 - 提前准备常用内容
/// 5. 解析结果压缩 - 减少内存占用
class DocumentParser {
  static final DocumentParser _instance = DocumentParser._internal();
  factory DocumentParser() => _instance;
  DocumentParser._internal();

  // LRU缓存配置
  static const int _maxCacheSize = 50; // 从50
  static const int _maxCacheMemoryMB = 200; // 从100MB增加到200MB
  
  // 解析队列配置
  static const int _maxConcurrentParsing = 5; // 从3增加到5个并发解析
  
  // 缓存存储
  final Map<String, _CachedDocument> _documentCache = {};
  final List<String> _cacheAccessOrder = []; // LRU访问顺序
  
  // 解析队列
  final List<_ParseRequest> _parseQueue = [];
  int _currentParsingCount = 0;
  
  // 统计信息
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalParseTime = 0;
  int _totalParseCount = 0;

  /// 解析文档（带缓存和优先级）
  static Future<Document> parseDocumentOptimized(
    String content, {
    int priority = 5, // 优先级 1-10，10最高
    String? cacheKey,
    bool useCache = true,
  }) async {
    return DocumentParser()._parseWithCache(
      content, 
      priority: priority, 
      cacheKey: cacheKey,
      useCache: useCache,
    );
  }

  /// 原始解析方法（保持兼容性）
  static Future<Document> parseDocumentInIsolate(String content) async {
    return DocumentParser()._parseWithCache(content, priority: 5);
  }

  /// 安全解析文档（用于UI线程，兼容性方法）
  static Future<Document> parseDocumentSafely(String content) async {
    return DocumentParser()._parseWithCache(content, priority: 5, useCache: true);
  }

  /// 同步解析文档（用于控制器初始化）
  /// 
  /// 这个方法用于需要立即返回Document的场景，如QuillController初始化
  /// 使用简化解析逻辑，避免异步操作
  static Document parseDocumentSync(String content) {
    return DocumentParser()._parseDocumentSimple(content);
  }

  /// 批量解析文档
  static Future<List<Document>> parseBatchDocuments(
    List<String> contents, {
    int priority = 5,
    List<String>? cacheKeys,
  }) async {
    return DocumentParser()._parseBatch(contents, priority: priority, cacheKeys: cacheKeys);
  }

  /// 预加载文档到缓存（增强版）
  static Future<void> preloadDocuments(
    List<String> contents, {
    List<String>? cacheKeys,
    int maxPreloadConcurrency = 2, // 限制预加载并发数，避免影响正常解析
  }) async {
    final parser = DocumentParser();
    final futures = <Future<void>>[];
    
    for (int i = 0; i < contents.length; i++) {
      final content = contents[i];
      final cacheKey = cacheKeys != null && i < cacheKeys.length 
          ? cacheKeys[i] 
          : parser._generateCacheKey(content);
      
      // 检查是否已缓存
      if (!parser._documentCache.containsKey(cacheKey)) {
        // 创建预加载Future
        final preloadFuture = parser._parseWithCache(
          content, 
          priority: 1, // 最低优先级后台解析
          cacheKey: cacheKey, 
          useCache: true
        ).then((_) {
          AppLogger.d('DocumentParser', '预加载完成: $cacheKey');
        }).catchError((e) {
          AppLogger.w('DocumentParser', '预加载失败: $cacheKey, $e');
        });
        
        futures.add(preloadFuture);
        
        // 控制并发数量，每批处理maxPreloadConcurrency个
        if (futures.length >= maxPreloadConcurrency) {
          await Future.wait(futures);
          futures.clear();
          // 短暂延迟，避免阻塞主线程
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
    }
    
    // 处理剩余的预加载任务
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    AppLogger.i('DocumentParser', '批量预加载完成，处理了${contents.length}个文档');
  }

  /// 清理缓存
  static void clearCache() {
    final parser = DocumentParser();
    parser._documentCache.clear();
    parser._cacheAccessOrder.clear();
    parser._cacheHits = 0;
    parser._cacheMisses = 0;
    parser._totalParseTime = 0;
    parser._totalParseCount = 0;
    AppLogger.i('DocumentParser', '缓存已清理');
  }

  /// 获取缓存统计信息
  static Map<String, dynamic> getCacheStats() {
    final parser = DocumentParser();
    final cacheSize = parser._documentCache.length;
    final memoryUsageMB = parser._calculateCacheMemoryUsage() / 1024 / 1024;
    final hitRate = parser._cacheHits + parser._cacheMisses > 0 
        ? (parser._cacheHits / (parser._cacheHits + parser._cacheMisses) * 100).toStringAsFixed(1) + '%'
        : '0.0%';
    final avgParseTimeMs = parser._totalParseCount > 0 
        ? (parser._totalParseTime / parser._totalParseCount).toStringAsFixed(1)
        : '0.0';
    
    return {
      'cacheSize': cacheSize,
      'memoryUsageMB': memoryUsageMB.toStringAsFixed(2),
      'hitRate': hitRate,
      'avgParseTimeMs': avgParseTimeMs,
      'queueLength': parser._parseQueue.length,
      'currentParsing': parser._currentParsingCount,
      'totalHits': parser._cacheHits,
      'totalMisses': parser._cacheMisses,
      'totalParseCount': parser._totalParseCount,
      'maxCacheSize': _maxCacheSize,
      'maxMemoryMB': _maxCacheMemoryMB,
    };
  }

  /// 核心解析方法（带缓存）
  Future<Document> _parseWithCache(
    String content, {
    int priority = 5,
    String? cacheKey,
    bool useCache = true,
  }) async {
    final key = cacheKey ?? _generateCacheKey(content);
    
    // 🚀 快速路径：空内容直接返回
    if (content.isEmpty) {
      AppLogger.d('DocumentParser', '快速路径：空内容 $key');
      return Document.fromJson([{'insert': '\n'}]);
    }
    
    // 尝试从缓存获取（返回副本，避免共享可变Document导致污染）
    if (useCache && _documentCache.containsKey(key)) {
      _updateCacheAccess(key);
      _cacheHits++;
      AppLogger.d('DocumentParser', '缓存命中: $key');
      final cached = _documentCache[key]!;
      // 返回一个新的Document实例副本
      return Document.fromJson(cached.document.toDelta().toJson());
    }

    _cacheMisses++;
    
    // 🚀 快速路径：内容过大时使用简化解析
    if (content.length > 100000) { // 大于100KB使用简化解析
      AppLogger.w('DocumentParser', '内容过大($content.length字符)，使用简化解析: $key');
      try {
        final simpleDocument = _parseDocumentSimple(content);
        if (useCache) {
          _storeInCache(key, simpleDocument, content.length);
        }
        // 返回副本
        return Document.fromJson(simpleDocument.toDelta().toJson());
      } catch (e) {
        AppLogger.e('DocumentParser', '简化解析失败: $key', e);
        return Document.fromJson([{'insert': '内容过大，解析失败\n'}]);
      }
    }
    
    // 🚀 快速路径：如果是纯文本且不太长，直接解析
    if (content.length < 1000 && !content.trim().startsWith('[') && !content.trim().startsWith('{')) {
      AppLogger.d('DocumentParser', '快速路径：纯文本解析 $key');
      final quickDocument = Document.fromJson([{'insert': '$content\n'}]);
      if (useCache) {
        _storeInCache(key, quickDocument, content.length);
      }
      // 返回副本
      return Document.fromJson(quickDocument.toDelta().toJson());
    }
    
    // 创建解析请求
    final completer = Completer<Document>();
    final request = _ParseRequest(
      content: content,
      cacheKey: key,
      priority: priority,
      completer: completer,
      useCache: useCache,
    );

    _parseQueue.add(request);
    _parseQueue.sort((a, b) => b.priority.compareTo(a.priority)); // 按优先级排序
    
    _processParseQueue();
    
    return completer.future;
  }

  /// 批量解析
  Future<List<Document>> _parseBatch(
    List<String> contents, {
    int priority = 5,
    List<String>? cacheKeys,
  }) async {
    final futures = <Future<Document>>[];
    
    for (int i = 0; i < contents.length; i++) {
      final cacheKey = cacheKeys != null && i < cacheKeys.length ? cacheKeys[i] : null;
      futures.add(_parseWithCache(contents[i], priority: priority, cacheKey: cacheKey));
    }
    
    return Future.wait(futures);
  }

  /// 处理解析队列
  void _processParseQueue() {
    while (_parseQueue.isNotEmpty && _currentParsingCount < _maxConcurrentParsing) {
      final request = _parseQueue.removeAt(0);
      _currentParsingCount++;
      
      _executeParseRequest(request);
    }
  }

  /// 执行解析请求
  void _executeParseRequest(_ParseRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // 🚀 预估解析时间，如果内容过大直接使用简化解析
      if (request.content.length > 50000) {
        AppLogger.w('DocumentParser', '内容较大(${request.content.length}字符)，使用简化解析: ${request.cacheKey}');
        final document = _parseDocumentSimple(request.content);
        
        stopwatch.stop();
        final parseTime = stopwatch.elapsedMilliseconds;
        _totalParseTime += parseTime;
        _totalParseCount++;
        
        if (request.useCache) {
          _storeInCache(request.cacheKey, document, request.content.length);
        }
        
        AppLogger.d('DocumentParser', '简化解析完成: ${request.cacheKey}, 耗时: ${parseTime}ms');
        request.completer.complete(document);
        return;
      }
      
      // 正常解析流程
      final document = await _parseInIsolateWithTimeout(request.content);
      
      stopwatch.stop();
      final parseTime = stopwatch.elapsedMilliseconds;
      _totalParseTime += parseTime;
      _totalParseCount++;
      
      // 🚨 性能监控：如果解析时间过长，记录警告
      if (parseTime > 1000) {
        AppLogger.w('DocumentParser', '⚠️ 解析时间过长: ${request.cacheKey}, 耗时: ${parseTime}ms, 内容长度: ${request.content.length}');
      }
      
      // 存储到缓存
      if (request.useCache) {
        _storeInCache(request.cacheKey, document, request.content.length);
      }
      
      AppLogger.d('DocumentParser', '解析完成: ${request.cacheKey}, 耗时: ${parseTime}ms');
      // 返回副本
      request.completer.complete(Document.fromJson(document.toDelta().toJson()));
      
    } catch (e, stackTrace) {
      stopwatch.stop();
      AppLogger.e('DocumentParser', '解析失败: ${request.cacheKey}', e, stackTrace);
      
      // 🚀 解析失败时使用简化解析作为备用方案
      try {
        AppLogger.i('DocumentParser', '尝试简化解析备用方案: ${request.cacheKey}');
        final fallbackDocument = _parseDocumentSimple(request.content);
        
        if (request.useCache) {
          _storeInCache(request.cacheKey, fallbackDocument, request.content.length);
        }
        
        // 返回副本
        request.completer.complete(Document.fromJson(fallbackDocument.toDelta().toJson()));
        AppLogger.i('DocumentParser', '简化解析备用方案成功: ${request.cacheKey}');
      } catch (fallbackError) {
        // 最后的备用方案：创建错误文档
        final errorDocument = Document.fromJson([
          {'insert': '⚠️ 文档解析失败\n内容加载出现问题，请刷新重试。\n\n原始内容预览：\n'},
          {'insert': request.content.length > 200 ? '${request.content.substring(0, 200)}...\n' : '${request.content}\n'},
        ]);
        
        request.completer.complete(errorDocument);
        AppLogger.e('DocumentParser', '所有解析方案都失败: ${request.cacheKey}', fallbackError);
      }
    } finally {
      _currentParsingCount--;
      _processParseQueue(); // 处理队列中的下一个请求
    }
  }

  /// 在隔离中解析（带超时）
  Future<Document> _parseInIsolateWithTimeout(String content) async {
    // 🚀 根据内容大小动态调整超时时间
    Duration timeout;
    if (content.length < 1000) {
      timeout = const Duration(seconds: 2); // 小内容2秒超时
    } else if (content.length < 10000) {
      timeout = const Duration(seconds: 4); // 中等内容4秒超时
    } else {
      timeout = const Duration(seconds: 6); // 大内容6秒超时，不再使用8秒
    }
    
    return compute(_isolateParseFunction, content).timeout(
      timeout,
      onTimeout: () {
        AppLogger.w('DocumentParser', '解析超时(${timeout.inSeconds}秒)，使用简化解析，内容长度: ${content.length}');
        return _parseDocumentSimple(content);
      },
    );
  }

  /// 生成缓存键
  String _generateCacheKey(String content) {
    // 使用内容长度和特征字符生成更稳定的缓存键
    final length = content.length;
    if (length == 0) return 'doc_empty_0';
    
    // 🚀 修复：使用更准确的哈希算法，避免缓存冲突
    // 对于短内容(< 1000字符)，使用完整内容的哈希确保唯一性
    if (length < 1000) {
      // 使用简单的字符串哈希，确保内容完全相同才有相同的缓存键
      int hash = 0;
      for (int i = 0; i < length; i++) {
        hash = (hash * 31 + content.codeUnitAt(i)) & 0x7FFFFFFF;
      }
      return 'doc_${length}_${hash}_full';
    }
    
    // 对于长内容，使用采样方式减少计算开销
    // 但增加采样点数量以减少冲突
    final samples = <int>[];
    
    // 采样更多的特征位置
    samples.add(content.codeUnitAt(0));
    samples.add(content.codeUnitAt(length - 1));
    
    // 按照固定间隔采样，确保不同内容有不同的特征
    final sampleInterval = (length / 16).ceil();
    for (int i = sampleInterval; i < length - 1; i += sampleInterval) {
      samples.add(content.codeUnitAt(i));
      // 限制采样点数量避免过多计算
      if (samples.length >= 20) break;
    }
    
    // 生成基于所有采样点的哈希
    int stableHash = length;
    for (final sample in samples) {
      stableHash = (stableHash * 31 + sample) & 0x7FFFFFFF;
    }
    
    return 'doc_${length}_${stableHash}_sampled';
  }

  /// 存储到缓存
  void _storeInCache(String key, Document document, int contentSize) {
    // 检查缓存大小限制
    _enforceCacheLimits();
    
    // 存储副本，避免外部修改污染缓存
    final cachedDoc = _CachedDocument(
      document: Document.fromJson(document.toDelta().toJson()),
      contentSize: contentSize,
      accessTime: DateTime.now(),
    );
    
    _documentCache[key] = cachedDoc;
    _updateCacheAccess(key);
  }

  /// 更新缓存访问顺序
  void _updateCacheAccess(String key) {
    _cacheAccessOrder.remove(key);
    _cacheAccessOrder.add(key); // 移到最后（最近访问）
    
    if (_documentCache.containsKey(key)) {
      _documentCache[key]!.accessTime = DateTime.now();
    }
  }

  /// 强制执行缓存限制
  void _enforceCacheLimits() {
    // 检查数量限制
    while (_documentCache.length >= _maxCacheSize && _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _documentCache.remove(oldestKey);
    }
    
    // 检查内存限制
    while (_calculateCacheMemoryUsage() > _maxCacheMemoryMB * 1024 * 1024 && _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _documentCache.remove(oldestKey);
    }
  }

  /// 计算缓存内存使用量
  int _calculateCacheMemoryUsage() {
    return _documentCache.values.fold(0, (sum, doc) => sum + doc.contentSize);
  }

  /// 简化解析方法 - 用于大内容或解析失败的备用方案
  Document _parseDocumentSimple(String content) {
    try {
      // 🚀 快速检查：如果是空内容
      if (content.trim().isEmpty) {
        return Document.fromJson([{'insert': '\n'}]);
      }
      
      // 🚀 快速检查：如果明显是纯文本
      final trimmedContent = content.trim();
      if (!trimmedContent.startsWith('[') && !trimmedContent.startsWith('{')) {
        // 处理纯文本，保留换行
        final lines = content.split('\n');
        final ops = <Map<String, dynamic>>[];
        
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].isNotEmpty) {
            ops.add({'insert': lines[i]});
          }
          if (i < lines.length - 1 || content.endsWith('\n')) {
            ops.add({'insert': '\n'});
          }
        }
        
        if (ops.isEmpty) {
          ops.add({'insert': '\n'});
        }
        
        return Document.fromJson(ops);
      }
      
      // 🚀 尝试快速JSON解析
      try {
        final jsonData = jsonDecode(content);
        
        if (jsonData is List) {
          // 验证是否是有效的Quill操作数组
          bool isValidOps = true;
          bool hasStyleAttributes = false;
          
          for (final op in jsonData) {
            if (op is! Map || !op.containsKey('insert')) {
              isValidOps = false;
              break;
            }
            // 检查是否有样式属性
            if (op.containsKey('attributes')) {
              hasStyleAttributes = true;
              final attributes = op['attributes'] as Map<String, dynamic>?;
              if (attributes != null) {
                AppLogger.d('DocumentParser/_parseDocumentSimple', 
                    '🎨 发现样式属性: ${attributes.keys.join(', ')}');
                    
                if (attributes.containsKey('color')) {
                  AppLogger.d('DocumentParser/_parseDocumentSimple', 
                      '🎨 文字颜色: ${attributes['color']}');
                }
                if (attributes.containsKey('background')) {
                  AppLogger.d('DocumentParser/_parseDocumentSimple', 
                      '🎨 背景颜色: ${attributes['background']}');
                }
              }
            }
          }
          
          if (hasStyleAttributes) {
            AppLogger.i('DocumentParser/_parseDocumentSimple', 
                '🎨 简化解析包含样式属性的内容，操作数量: ${jsonData.length}');
          }
          
          if (isValidOps) {
            return Document.fromJson(jsonData);
          }
        } else if (jsonData is Map && jsonData.containsKey('ops')) {
          final ops = jsonData['ops'];
          if (ops is List) {
            // 检查ops中的样式属性
            bool hasStyleAttributes = false;
            for (final op in ops) {
              if (op is Map && op.containsKey('attributes')) {
                hasStyleAttributes = true;
                final attributes = op['attributes'] as Map<String, dynamic>?;
                if (attributes != null) {
                  AppLogger.d('DocumentParser/_parseDocumentSimple', 
                      '🎨 ops中发现样式属性: ${attributes.keys.join(', ')}');
                }
              }
            }
            
            if (hasStyleAttributes) {
              AppLogger.i('DocumentParser/_parseDocumentSimple', 
                  '🎨 简化解析ops格式包含样式属性的内容，操作数量: ${ops.length}');
            }
            
            return Document.fromJson(ops);
          }
        }
        
        // 如果JSON格式不正确，当作文本处理
        return Document.fromJson([
          {'insert': '⚠️ 内容格式异常，显示原始内容：\n'},
          {'insert': content.length > 1000 ? '${content.substring(0, 1000)}...\n' : '$content\n'}
        ]);
        
      } catch (jsonError) {
        // JSON解析失败，当作纯文本处理
        AppLogger.d('DocumentParser', '简化解析：JSON解析失败，当作纯文本处理');
        return Document.fromJson([
          {'insert': content.length > 10000 ? '${content.substring(0, 10000)}...\n' : '$content\n'}
        ]);
      }
      
    } catch (e) {
      AppLogger.w('DocumentParser', '简化解析也失败，使用最基础的文档', e);
      return Document.fromJson([
        {'insert': '⚠️ 内容解析失败\n'},
        {'insert': '内容长度: ${content.length} 字符\n'},
        {'insert': '请联系技术支持\n'}
      ]);
    }
  }


  /// 检查缓存健康状况
  static Map<String, dynamic> checkCacheHealth() {
    final parser = DocumentParser();
    final stats = getCacheStats();
    final issues = <String>[];
    
    // 检查缓存命中率
    final hitRateNum = parser._cacheHits + parser._cacheMisses > 0 
        ? (parser._cacheHits / (parser._cacheHits + parser._cacheMisses) * 100)
        : 0.0;
    
    if (hitRateNum < 30) {
      issues.add('缓存命中率过低 (${hitRateNum.toStringAsFixed(1)}%)');
    }
    
    // 检查平均解析时间
    final avgParseTime = parser._totalParseCount > 0 
        ? (parser._totalParseTime / parser._totalParseCount)
        : 0.0;
    
    if (avgParseTime > 500) {
      issues.add('平均解析时间过长 (${avgParseTime.toStringAsFixed(1)}ms)');
    }
    
    // 检查队列长度
    if (parser._parseQueue.length > 10) {
      issues.add('解析队列过长 (${parser._parseQueue.length})');
    }
    
    return {
      'isHealthy': issues.isEmpty,
      'issues': issues,
      'stats': stats,
      'recommendations': _generateRecommendations(issues),
    };
  }

  /// 生成优化建议
  static List<String> _generateRecommendations(List<String> issues) {
    final recommendations = <String>[];
    
    if (issues.any((issue) => issue.contains('缓存命中率'))) {
      recommendations.add('增加预加载范围');
      recommendations.add('检查缓存键生成逻辑');
      recommendations.add('考虑增加缓存大小');
    }
    
    if (issues.any((issue) => issue.contains('解析时间'))) {
      recommendations.add('检查内容复杂度');
      recommendations.add('考虑内容预处理');
      recommendations.add('增加并发解析数量');
    }
    
    if (issues.any((issue) => issue.contains('队列'))) {
      recommendations.add('减少同时触发的解析请求');
      recommendations.add('提高高优先级任务处理速度');
      recommendations.add('检查是否有解析死锁');
    }
    
    return recommendations;
  }

  /// 智能缓存预热 - 新增功能
  static Future<void> warmupCache({
    List<String>? priorityContents,
    int warmupSize = 10,
  }) async {
    
    AppLogger.i('DocumentParser', '开始缓存预热...');
    
    // 预热常见的文档格式
    final commonFormats = [
      '[{"insert":"\\n"}]', // 空文档
      '[{"insert":"测试文本\\n"}]', // 简单文本
      '[{"insert":"测试文本\\n","attributes":{"bold":true}}]', // 带格式文本
      '简单纯文本内容', // 纯文本
      '{"insert":"旧格式文档\\n"}', // 旧格式
    ];
    
    // 预热优先内容
    if (priorityContents != null) {
      await preloadDocuments(
        priorityContents.take(warmupSize).toList(),
        maxPreloadConcurrency: 3,
      );
    }
    
    // 预热常见格式
    await preloadDocuments(
      commonFormats,
      cacheKeys: List.generate(commonFormats.length, (i) => 'warmup_format_$i'),
      maxPreloadConcurrency: 2,
    );
    
    AppLogger.i('DocumentParser', '缓存预热完成');
  }
}

/// 隔离中的解析函数
Document _isolateParseFunction(String content) {
  try {
    if (content.isEmpty) {
      return Document.fromJson([{'insert': '\n'}]);
    }
    
    // 优化的JSON解析
    if (content.trim().startsWith('[') || content.trim().startsWith('{')) {
      final jsonData = jsonDecode(content);
      List<Map<String, dynamic>> ops;
      
      if (jsonData is List) {
        ops = jsonData.cast<Map<String, dynamic>>();
      } else if (jsonData is Map && jsonData.containsKey('ops')) {
        // 处理 {"ops": [...]} 格式
        ops = (jsonData['ops'] as List).cast<Map<String, dynamic>>();
      } else if (jsonData is Map) {
        ops = [jsonData.cast<String, dynamic>()];
      } else {
        // 转换为纯文本处理
        return Document.fromJson([{'insert': '$content\n'}]);
      }
      
      // 🚀 新增：检查和记录样式属性
      bool hasStyleAttributes = false;
      for (final op in ops) {
        if (op.containsKey('attributes')) {
          hasStyleAttributes = true;
          final attributes = op['attributes'] as Map<String, dynamic>?;
          if (attributes != null) {
            // 记录发现的样式属性
            AppLogger.d('DocumentParser/_isolateParseFunction', 
                '🎨 发现样式属性: ${attributes.keys.join(', ')}');
            
            // 特别记录颜色属性
            if (attributes.containsKey('color')) {
              AppLogger.d('DocumentParser/_isolateParseFunction', 
                  '🎨 文字颜色: ${attributes['color']}');
            }
            if (attributes.containsKey('background')) {
              AppLogger.d('DocumentParser/_isolateParseFunction', 
                  '🎨 背景颜色: ${attributes['background']}');
            }
          }
        }
      }
      
      if (hasStyleAttributes) {
        AppLogger.i('DocumentParser/_isolateParseFunction', 
            '🎨 解析包含样式属性的内容，操作数量: ${ops.length}');
      }
      
      // 确保最后一个操作以换行符结尾
      if (ops.isNotEmpty) {
        final lastOp = ops.last;
        if (lastOp.containsKey('insert')) {
          final insertText = lastOp['insert'].toString();
          if (!insertText.endsWith('\n')) {
            // 如果最后一个insert不以换行符结尾，添加一个新的换行符操作
            ops.add({'insert': '\n'});
          }
        } else {
          // 如果最后一个操作不包含insert，添加换行符
          ops.add({'insert': '\n'});
        }
      } else {
        // 如果ops为空，添加一个换行符
        ops = [{'insert': '\n'}];
      }
      
      return Document.fromJson(ops);
    }
    
    // 处理普通文本
    return Document.fromJson([{'insert': '$content\n'}]);
    
  } catch (e) {
    // 解析失败时的备用方案 - 增强错误信息
    AppLogger.e('DocumentParser/_isolateParseFunction', 
        '解析失败，内容长度: ${content.length}, 错误: $e');
    
    return Document.fromJson([
      {'insert': '解析错误: ${e.toString()}\n'},
      {'insert': content.length > 200 ? '${content.substring(0, 200)}...\n' : '$content\n'},
    ]);
  }
}

/// 缓存的文档数据
class _CachedDocument {
  final Document document;
  final int contentSize;
  DateTime accessTime;

  _CachedDocument({
    required this.document,
    required this.contentSize,
    required this.accessTime,
  });
}

/// 解析请求
class _ParseRequest {
  final String content;
  final String cacheKey;
  final int priority;
  final Completer<Document> completer;
  final bool useCache;

  _ParseRequest({
    required this.content,
    required this.cacheKey,
    required this.priority,
    required this.completer,
    required this.useCache,
  });
} 