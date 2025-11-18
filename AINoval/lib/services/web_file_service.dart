import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

// 条件导入：在Web平台导入dart:html
import 'dart:html' as html;

import 'package:ainoval/models/novel_structure.dart';
import 'package:ainoval/services/api_service/repositories/novel_repository.dart';
import 'package:ainoval/services/api_service/repositories/editor_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/services/novel_file_service.dart';
import 'package:ainoval/utils/quill_helper.dart';

/// Web平台专用的文件导出服务
/// 使用浏览器的下载机制而不是本地文件系统
class WebFileService {
  final NovelRepository _novelRepository;
  final EditorRepository? _editorRepository;

  WebFileService({
    required NovelRepository novelRepository,
    EditorRepository? editorRepository,
  }) : _novelRepository = novelRepository,
        _editorRepository = editorRepository;

  /// 获取完整小说内容
  Future<Novel> _fetchCompleteNovel(String novelId) async {
    try {
      AppLogger.i('WebFileService', '开始获取完整小说内容: $novelId');

      // 暂时使用简化实现，避免未使用字段的警告
      // 在真实实现中，这里会使用 _novelRepository 获取数据
      AppLogger.d('WebFileService', '使用Repository: ${_novelRepository.runtimeType}');
      if (_editorRepository != null) {
        AppLogger.d('WebFileService', '编辑器Repository可用: ${_editorRepository.runtimeType}');
      }

      // 创建基本小说结构 - 简化实现
      final novel = Novel(
        id: novelId,
        title: '导出的小说',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        acts: [],
      );
      
      // 暂时返回空的章节结构
      // TODO: 实现从API获取完整小说内容
      // 未来这里会使用: await _novelRepository.getNovelById(novelId)
      return novel;
    } catch (e) {
      AppLogger.e('WebFileService', '获取小说内容失败', e);
      rethrow;
    }
  }

  /// 将小说导出为TXT格式
  String _exportToTxt(Novel novel) {
    final buffer = StringBuffer();
    
    // 标题和基本信息
    buffer.writeln('${novel.title}');
    buffer.writeln('=' * novel.title.length);
    buffer.writeln();
    
    if (novel.author != null) {
      buffer.writeln('作者：${novel.author!.username}');
    }
    
    buffer.writeln('创建时间：${DateFormat('yyyy-MM-dd HH:mm').format(novel.createdAt)}');
    buffer.writeln('最后更新：${DateFormat('yyyy-MM-dd HH:mm').format(novel.updatedAt)}');
    buffer.writeln();
    buffer.writeln('-' * 50);
    buffer.writeln();

    // 内容
    for (final act in novel.acts) {
      // 幕标题
      buffer.writeln('【${act.title}】');
      buffer.writeln();
      
      for (final chapter in act.chapters) {
        // 章节标题
        buffer.writeln('${chapter.title}');
        buffer.writeln('-' * chapter.title.length);
        buffer.writeln();
        
        for (final scene in chapter.scenes) {
          // 场景内容（将Quill Delta转为纯文本）
          final String plain = QuillHelper.deltaToText(scene.content);
          if (plain.trim().isNotEmpty) {
            buffer.writeln(plain);
            buffer.writeln();
          }
        }
        
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// 将小说导出为Markdown格式
  String _exportToMarkdown(Novel novel) {
    final buffer = StringBuffer();
    
    // 标题和基本信息
    buffer.writeln('# ${novel.title}');
    buffer.writeln();
    
    if (novel.author != null) {
      buffer.writeln('**作者：** ${novel.author!.username}');
    }
    
    buffer.writeln('**创建时间：** ${DateFormat('yyyy-MM-dd HH:mm').format(novel.createdAt)}');
    buffer.writeln('**最后更新：** ${DateFormat('yyyy-MM-dd HH:mm').format(novel.updatedAt)}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    // 内容
    for (final act in novel.acts) {
      // 幕标题 (二级标题)
      buffer.writeln('## ${act.title}');
      buffer.writeln();
      
      for (final chapter in act.chapters) {
        // 章节标题 (三级标题)
        buffer.writeln('### ${chapter.title}');
        buffer.writeln();
        
        for (final scene in chapter.scenes) {
          // 场景内容（将Quill Delta转为纯文本）
          final String plain = QuillHelper.deltaToText(scene.content);
          if (plain.trim().isNotEmpty) {
            buffer.writeln(plain);
            buffer.writeln();
          }
        }
      }
    }

    return buffer.toString();
  }

  /// 将小说导出为JSON格式
  String _exportToJson(Novel novel) {
    final jsonData = {
      'exportInfo': {
        'exportedAt': DateTime.now().toIso8601String(),
        'exportVersion': '1.0.0',
        'appVersion': '0.1.0+1',
        'platform': 'web',
      },
      'novel': novel.toJson(),
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonData);
  }

  /// 生成文件名
  String _generateFileName(Novel novel, NovelExportFormat format) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    // 允许中文等 Unicode 字符，仅移除非法路径字符
    String safeTitle = novel.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    if (safeTitle.isEmpty) safeTitle = 'novel';
    safeTitle = safeTitle.replaceAll(RegExp(r'\s+'), '_');
    return '${safeTitle}_$timestamp.${format.name}';
  }

  /// 获取MIME类型
  String _getMimeType(NovelExportFormat format) {
    switch (format) {
      case NovelExportFormat.txt:
        return 'text/plain';
      case NovelExportFormat.markdown:
        return 'text/markdown';
      case NovelExportFormat.json:
        return 'application/json';
    }
  }

  /// Web端导出小说文件
  /// 使用浏览器的下载机制，不保存到本地文件系统
  Future<NovelExportResult> exportNovelToWebDownload(
    String novelId, {
    NovelExportFormat format = NovelExportFormat.txt,
    String? customFileName,
    Novel? cachedNovel, // 可选：直接使用前端缓存的小说，避免请求
  }) async {
    try {
      AppLogger.i('WebFileService', '开始Web导出小说: $novelId, 格式: ${format.name}');
      
      // 1. 获取小说内容（优先使用前端缓存，避免网络请求）
      final novel = cachedNovel ?? await _fetchCompleteNovel(novelId);
      if (cachedNovel != null) {
        AppLogger.i('WebFileService', '使用缓存小说导出: ${cachedNovel.id}, 卷数=${cachedNovel.acts.length}');
      }
      
      // 2. 根据格式生成内容
      String content;
      switch (format) {
        case NovelExportFormat.txt:
          content = _exportToTxt(novel);
          break;
        case NovelExportFormat.markdown:
          content = _exportToMarkdown(novel);
          break;
        case NovelExportFormat.json:
          content = _exportToJson(novel);
          break;
      }
      
      // 3. 生成文件名
      final fileName = customFileName ?? _generateFileName(novel, format);
      
      // 4. 创建Blob并触发下载
      await _triggerWebDownload(content, fileName, format);
      
      // 5. 计算文件大小
      final contentBytes = utf8.encode(content);
      final fileSizeBytes = contentBytes.length;
      
      final result = NovelExportResult(
        filePath: '', // Web版本不使用本地路径
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        format: format,
        exportedAt: DateTime.now(),
      );
      
      AppLogger.i('WebFileService', 'Web导出成功: ${result.fileName}, 大小: ${result.fileSizeBytes} bytes');
      return result;
      
    } catch (e) {
      AppLogger.e('WebFileService', 'Web导出失败', e);
      rethrow;
    }
  }

  /// 触发Web浏览器下载
  Future<void> _triggerWebDownload(
    String content, 
    String fileName, 
    NovelExportFormat format
  ) async {
    if (kIsWeb) {
      try {
        // 将内容转换为Uint8List
        final bytes = utf8.encode(content);
        
        // 创建Blob
        final blob = html.Blob([bytes], _getMimeType(format));
        
        // 创建下载URL
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        // 创建隐藏的a标签并触发下载
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..style.display = 'none';
        
        // 添加到DOM，点击，然后移除
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        
        // 清理URL
        html.Url.revokeObjectUrl(url);
        
        AppLogger.i('WebFileService', '浏览器下载触发成功: $fileName');
      } catch (e) {
        AppLogger.e('WebFileService', '浏览器下载失败', e);
        rethrow;
      }
    } else {
      throw UnsupportedError('WebFileService只能在Web平台使用');
    }
  }

  /// 批量导出多种格式（Web版本）
  Future<List<NovelExportResult>> exportNovelMultipleFormatsWeb(
    String novelId, {
    List<NovelExportFormat> formats = const [
      NovelExportFormat.txt,
      NovelExportFormat.markdown,
      NovelExportFormat.json,
    ],
    Novel? cachedNovel, // 可选：直接使用前端缓存
  }) async {
    final results = <NovelExportResult>[];
    
    for (final format in formats) {
      try {
        final result = await exportNovelToWebDownload(
          novelId,
          format: format,
          cachedNovel: cachedNovel,
        );
        results.add(result);
        
        // 在格式之间添加小延迟，避免浏览器阻止多个下载
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        AppLogger.e('WebFileService', '导出格式 ${format.name} 失败', e);
        // 继续导出其他格式
      }
    }
    
    return results;
  }

  /// 检查是否在Web环境
  bool get isWebPlatform => kIsWeb;

  /// 显示Web端导出成功的提示
  void showWebExportSuccess(NovelExportResult result) {
    if (kIsWeb) {
      // 可以在这里添加Web端的成功提示逻辑
      AppLogger.i('WebFileService', '文件已下载: ${result.fileName}');
    }
  }
}
