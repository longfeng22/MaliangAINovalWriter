import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/editor/editor_bloc.dart' as editor_bloc;
import 'package:ainoval/blocs/sidebar/sidebar_bloc.dart' as sidebar_bloc;
import 'package:ainoval/models/novel_structure.dart' as novel_models;
import 'package:ainoval/services/local_storage_service.dart';

import 'package:ainoval/services/novel_file_service.dart';
import 'package:ainoval/services/web_file_service.dart';
import 'package:ainoval/utils/web_theme.dart';

/// Web编辑器导出对话框
class ExportDialog extends StatefulWidget {
  final String novelId;
  final String novelTitle;
  final novel_models.Novel? cachedNovel;

  const ExportDialog({
    super.key,
    required this.novelId,
    required this.novelTitle,
    this.cachedNovel,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isExporting = false;
  NovelExportFormat _selectedFormat = NovelExportFormat.txt;
  bool _exportAll = false;

  // 常用的导出尺寸常量 [[memory:3775590]]
  static const double _dialogWidth = 480.0;
  static const double _dialogMaxHeight = 600.0;
  static const double _buttonHeight = 48.0;
  static const double _spacing = 16.0;
  static const double _smallSpacing = 8.0;

  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: _dialogWidth,
        constraints: const BoxConstraints(maxHeight: _dialogMaxHeight),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题区域
            Row(
              children: [
                Icon(
                  Icons.download_outlined,
                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                  size: 24,
                ),
                const SizedBox(width: _smallSpacing),
                Expanded(
                  child: Text(
                    '导出小说',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1F2937),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            
            const SizedBox(height: _spacing),
            
            // 小说信息
            Container(
              padding: const EdgeInsets.all(_spacing),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.book_outlined,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                    size: 20,
                  ),
                  const SizedBox(width: _smallSpacing),
                  Expanded(
                    child: Text(
                      widget.novelTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: _spacing),
            
            // 导出选项
            Text(
              '导出选项',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1F2937),
              ),
            ),
            
            const SizedBox(height: _smallSpacing),
            
            // 导出所有格式开关
            Container(
              padding: const EdgeInsets.symmetric(horizontal: _spacing, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '导出所有格式',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF374151),
                      ),
                    ),
                  ),
                  Switch(
                    value: _exportAll,
                    onChanged: _isExporting ? null : (value) {
                      setState(() {
                        _exportAll = value;
                      });
                    },
                    activeColor: const Color(0xFF3B82F6),
                  ),
                ],
              ),
            ),
            
            if (!_exportAll) ...[
              const SizedBox(height: _spacing),
              
              // 格式选择
              Text(
                '选择格式',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF374151),
                ),
              ),
              
              const SizedBox(height: _smallSpacing),
              
              // 格式选项
              Column(
                children: NovelExportFormat.values.map((format) {
                  return RadioListTile<NovelExportFormat>(
                    value: format,
                    groupValue: _selectedFormat,
                    onChanged: _isExporting ? null : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedFormat = value;
                        });
                      }
                    },
                    title: Text(
                      _getFormatDisplayName(format),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white.withOpacity(0.87) : const Color(0xFF374151),
                      ),
                    ),
                    subtitle: Text(
                      _getFormatDescription(format),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                      ),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF3B82F6),
                  );
                }).toList(),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // 按钮区域
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : const Color(0xFF6B7280),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF404040) : const Color(0xFFD1D5DB),
                      ),
                      minimumSize: const Size(0, _buttonHeight),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: _spacing),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isExporting ? null : _startExport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, _buttonHeight),
                      disabledBackgroundColor: isDark ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
                    ),
                    child: _isExporting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: _smallSpacing),
                              Text('导出中...'),
                            ],
                          )
                        : Text(_exportAll ? '导出所有格式' : '开始导出'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getFormatDisplayName(NovelExportFormat format) {
    switch (format) {
      case NovelExportFormat.txt:
        return 'TXT 文本文件';
      case NovelExportFormat.markdown:
        return 'Markdown 格式';
      case NovelExportFormat.json:
        return 'JSON 数据文件';
    }
  }

  String _getFormatDescription(NovelExportFormat format) {
    switch (format) {
      case NovelExportFormat.txt:
        return '纯文本格式，包含标题和章节结构';
      case NovelExportFormat.markdown:
        return '支持格式化的Markdown文件';
      case NovelExportFormat.json:
        return '包含完整元数据和结构信息的JSON文件';
    }
  }

  Future<void> _startExport() async {
    setState(() {
      _isExporting = true;
    });

    try {
      if (_exportAll) {
        await _exportAllFormats();
      } else {
        await _exportSingleFormat();
      }
      
      // 导出成功，关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
        _showSuccessMessage();
      }
    } catch (e) {
      if (mounted) {
        _showErrorMessage(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportSingleFormat() async {
    if (kIsWeb) {
      // Web平台使用WebFileService
      final webFileService = context.read<WebFileService>();
      // 读取前端缓存小说（优先LocalStorageService，其次外部传入，再次Editor/Sidebar状态）
      final novel_models.Novel? cachedNovel = await _getCachedNovelAsync(context);
      if (cachedNovel == null) {
        throw Exception('当前编辑器内容未加载完成，请稍后再试');
      }
      await webFileService.exportNovelToWebDownload(
        widget.novelId,
        format: _selectedFormat,
        cachedNovel: cachedNovel,
      );
    } else {
      // 移动端使用NovelFileService
      final novelFileService = context.read<NovelFileService>();
      await novelFileService.exportNovelToFile(
        widget.novelId,
        format: _selectedFormat,
      );
    }
  }

  Future<void> _exportAllFormats() async {
    if (kIsWeb) {
      // Web平台使用WebFileService
      final webFileService = context.read<WebFileService>();
      final novel_models.Novel? cachedNovel = await _getCachedNovelAsync(context);
      if (cachedNovel == null) {
        throw Exception('当前编辑器内容未加载完成，请稍后再试');
      }
      await webFileService.exportNovelMultipleFormatsWeb(
        widget.novelId,
        cachedNovel: cachedNovel,
      );
    } else {
      // 移动端使用NovelFileService
      final novelFileService = context.read<NovelFileService>();
      await novelFileService.exportNovelMultipleFormats(widget.novelId);
    }
  }

  // 优先 LocalStorageService（本地持久缓存）→ 外部传入 → EditorBloc → SidebarBloc
  Future<novel_models.Novel?> _getCachedNovelAsync(BuildContext context) async {
    try {
      final local = context.read<LocalStorageService>();
      final localNovel = await local.getNovel(widget.novelId);
      if (localNovel != null) return localNovel;
    } catch (_) {}
    if (widget.cachedNovel != null) return widget.cachedNovel;
    try {
      final s = context.read<editor_bloc.EditorBloc>().state;
      if (s is editor_bloc.EditorLoaded) return s.novel;
    } catch (_) {}
    try {
      final s2 = context.read<sidebar_bloc.SidebarBloc>().state;
      if (s2 is sidebar_bloc.SidebarLoaded) return s2.novelStructure;
    } catch (_) {}
    return null;
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_exportAll ? '所有格式导出成功！' : '导出成功！'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('导出失败：$message'),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
