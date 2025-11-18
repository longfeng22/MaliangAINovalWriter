import 'package:flutter/material.dart';
import 'package:ainoval/models/editor_settings.dart';
// import 'package:ainoval/widgets/common/settings_widgets.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 编辑器设置面板 - 紧凑版
/// 提供完整的编辑器配置选项，优化为一页显示
class EditorSettingsPanel extends StatefulWidget {
  const EditorSettingsPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onSave,
    this.onReset,
  });

  final EditorSettings settings;
  final ValueChanged<EditorSettings> onSettingsChanged;
  final VoidCallback? onSave;
  final VoidCallback? onReset;

  @override
  State<EditorSettingsPanel> createState() => _EditorSettingsPanelState();
}

class _EditorSettingsPanelState extends State<EditorSettingsPanel> {
  late EditorSettings _currentSettings;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  Widget _buildLeftSettingsColumn() {
    return Column(
      children: [
        _buildCompactCard(
          title: '字体设置',
          icon: Icons.text_fields,
          children: [
            _buildCompactSlider(
              '字体大小',
              _currentSettings.fontSize,
              12, 32, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(fontSize: value)),
            ),
            _buildCompactDropdown(
              '字体',
              _currentSettings.fontFamily,
              EditorSettings.availableFontFamilies,
              (value) => _updateSettings(_currentSettings.copyWith(fontFamily: value)),
              itemBuilder: (font) {
                switch (font) {
                  case 'Noto Sans SC': return 'Noto Sans SC（思源黑体）- 推荐';
                  case 'Roboto': return 'Roboto（英文字体）';
                  case 'Roboto Condensed': return 'Roboto Condensed（紧凑版）';
                  case 'Roboto SemiCondensed': return 'Roboto SemiCondensed（半紧凑版）';
                  case 'serif': return '衬线字体（中文推荐）';
                  case 'sans-serif': return '无衬线字体（中文推荐）';
                  case 'monospace': return '等宽字体（代码风格）';
                  case 'PingFang SC': return 'PingFang SC（苹方）';
                  case 'Microsoft YaHei': return 'Microsoft YaHei（微软雅黑）';
                  case 'SimHei': return 'SimHei（黑体）';
                  case 'SimSun': return 'SimSun（宋体）';
                  case 'Helvetica': return 'Helvetica（Mac系统）';
                  case 'Times New Roman': return 'Times New Roman（衬线）';
                  case 'Courier New': return 'Courier New（等宽）';
                  case 'Georgia': return 'Georgia（衬线）';
                  case 'Verdana': return 'Verdana（无衬线）';
                  case 'Arial': return 'Arial（无衬线）';
                  default: return font;
                }
              },
            ),
            _buildCompactDropdown(
              '字体粗细',
              _currentSettings.fontWeight,
              EditorSettings.availableFontWeights,
              (value) => _updateSettings(_currentSettings.copyWith(fontWeight: value)),
              itemBuilder: (weight) {
                switch (weight) {
                  case FontWeight.w300: return '细体 (300)';
                  case FontWeight.w400: return '正常 (400)';
                  case FontWeight.w500: return '中等 (500)';
                  case FontWeight.w600: return '半粗 (600)';
                  case FontWeight.w700: return '粗体 (700)';
                  default: return '正常 (400)';
                }
              },
            ),
            _buildCompactSlider(
              '行间距',
              _currentSettings.lineSpacing,
              1.0, 3.0, '倍',
              (value) => _updateSettings(_currentSettings.copyWith(lineSpacing: value)),
              formatValue: (value) => '${value.toStringAsFixed(1)}x',
            ),
            _buildCompactSlider(
              '字符间距',
              _currentSettings.letterSpacing,
              -1.0, 2.0, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(letterSpacing: value)),
              formatValue: (value) => value == 0
                  ? '标准'
                  : (value > 0 ? '+${value.toStringAsFixed(1)}px' : '${value.toStringAsFixed(1)}px'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCompactCard(
          title: '编辑器行为',
          icon: Icons.settings,
          children: [
            _buildCompactSwitch('自动保存', _currentSettings.autoSaveEnabled,
              (value) => _updateSettings(_currentSettings.copyWith(autoSaveEnabled: value))),
            if (_currentSettings.autoSaveEnabled)
              _buildCompactSlider(
                '保存间隔',
                _currentSettings.autoSaveIntervalMinutes.toDouble(),
                1, 15, '分钟',
                (value) => _updateSettings(_currentSettings.copyWith(autoSaveIntervalMinutes: value.round())),
                formatValue: (value) => '${value.toInt()}分钟',
              ),
            _buildCompactSwitch('拼写检查', _currentSettings.spellCheckEnabled,
              (value) => _updateSettings(_currentSettings.copyWith(spellCheckEnabled: value))),
            _buildCompactSwitch('显示字数', _currentSettings.showWordCount,
              (value) => _updateSettings(_currentSettings.copyWith(showWordCount: value))),
            _buildCompactSwitch('显示行号', _currentSettings.showLineNumbers,
              (value) => _updateSettings(_currentSettings.copyWith(showLineNumbers: value))),
            _buildCompactSwitch('高亮当前行', _currentSettings.highlightActiveLine,
              (value) => _updateSettings(_currentSettings.copyWith(highlightActiveLine: value))),
            _buildCompactSwitch('Vim模式', _currentSettings.enableVimMode,
              (value) => _updateSettings(_currentSettings.copyWith(enableVimMode: value))),
          ],
        ),
        const SizedBox(height: 10),
        _buildCompactCard(
          title: '导出设置',
          icon: Icons.download,
          children: [
            _buildCompactDropdown(
              '默认导出格式',
              _currentSettings.defaultExportFormat,
              EditorSettings.availableExportFormats,
              (value) => _updateSettings(_currentSettings.copyWith(defaultExportFormat: value)),
              itemBuilder: (format) {
                switch (format) {
                  case 'markdown': return 'Markdown (.md)';
                  case 'docx': return 'Word文档 (.docx)';
                  case 'pdf': return 'PDF文档 (.pdf)';
                  case 'txt': return '纯文本 (.txt)';
                  case 'html': return 'HTML文档 (.html)';
                  default: return format.toUpperCase();
                }
              },
            ),
            _buildCompactSwitch('包含元数据', _currentSettings.includeMetadata,
              (value) => _updateSettings(_currentSettings.copyWith(includeMetadata: value))),
          ],
        ),
      ],
    );
  }

  Widget _buildRightSettingsColumn() {
    return Column(
      children: [
        _buildCompactCard(
          title: '布局间距',
          icon: Icons.format_align_center,
          children: [
            _buildCompactSlider(
              '水平边距',
              _currentSettings.paddingHorizontal,
              8, 48, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(paddingHorizontal: value)),
            ),
            _buildCompactSlider(
              '垂直边距',
              _currentSettings.paddingVertical,
              8, 32, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(paddingVertical: value)),
            ),
            _buildCompactSlider(
              '段落间距',
              _currentSettings.paragraphSpacing,
              4, 24, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(paragraphSpacing: value)),
            ),
            _buildCompactSlider(
              '缩进大小',
              _currentSettings.indentSize,
              16, 64, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(indentSize: value)),
            ),
            _buildCompactSlider(
              '最大行宽',
              _currentSettings.maxLineWidth,
              400, 1500, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(maxLineWidth: value)),
            ),
            _buildCompactSlider(
              '最小编辑器高度',
              _currentSettings.minEditorHeight,
              1200, 3000, '像素',
              (value) => _updateSettings(_currentSettings.copyWith(minEditorHeight: value)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCompactCard(
          title: '视觉效果',
          icon: Icons.visibility,
          children: [
            _buildCompactSwitch('暗色模式', _currentSettings.darkModeEnabled,
              (value) => _updateSettings(_currentSettings.copyWith(darkModeEnabled: value))),
            _buildCompactSwitch('平滑滚动', _currentSettings.smoothScrolling,
              (value) => _updateSettings(_currentSettings.copyWith(smoothScrolling: value))),
            _buildCompactSwitch('淡入动画', _currentSettings.fadeInAnimation,
              (value) => _updateSettings(_currentSettings.copyWith(fadeInAnimation: value))),
            _buildCompactSwitch('打字机模式', _currentSettings.useTypewriterMode,
              (value) => _updateSettings(_currentSettings.copyWith(useTypewriterMode: value))),
            _buildCompactSwitch('显示小地图', _currentSettings.showMiniMap,
              (value) => _updateSettings(_currentSettings.copyWith(showMiniMap: value))),
            _buildCompactSlider(
              '光标闪烁速度',
              _currentSettings.cursorBlinkRate,
              0.5, 3.0, '秒',
              (value) => _updateSettings(_currentSettings.copyWith(cursorBlinkRate: value)),
              formatValue: (value) => '${value.toStringAsFixed(1)}s',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCompactCard(
          title: '选择和光标',
          icon: Icons.colorize,
          children: [
            _buildColorPicker(
              '选择高亮颜色',
              Color(_currentSettings.selectionHighlightColor),
              (color) => _updateSettings(_currentSettings.copyWith(selectionHighlightColor: color.value)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(EditorSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🚀 修复：只有当外部设置真正改变且不是用户操作导致的时，才重置状态
    if (oldWidget.settings != widget.settings) {
      // 如果当前设置与新的widget设置相同，说明设置已被外部保存
      if (_currentSettings == widget.settings) {
        setState(() {
          _hasUnsavedChanges = false;
        });
      } else {
        // 如果不同，更新基础设置但保持未保存状态
      setState(() {
        _currentSettings = widget.settings;
        _hasUnsavedChanges = false;
      });
      }
    }
  }

  void _updateSettings(EditorSettings newSettings) {
    setState(() {
      _currentSettings = newSettings;
      // 🚀 修复保存按钮逻辑：先设置未保存状态，再调用回调
      _hasUnsavedChanges = true;
    });
    // 通知父组件设置已更改（用于实时预览），但不影响保存状态
    widget.onSettingsChanged(newSettings);
  }

    Future<void> _handleSave() async {
    if (_isSaving) return; // 🚀 简化：只检查是否正在保存
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // 🚀 实际调用保存回调
    widget.onSave?.call();
      
      // 等待一小段时间确保保存操作完成
      await Future.delayed(const Duration(milliseconds: 300));
      
      setState(() {
        _hasUnsavedChanges = false;
      });
      
      // 显示保存成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('编辑器设置已保存'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _handleReset() {
    setState(() {
      _currentSettings = const EditorSettings();
      _hasUnsavedChanges = true;
    });
    widget.onSettingsChanged(_currentSettings);
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 固定顶部：标题和操作按钮
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.getBackgroundColor(context),
            border: Border(
              bottom: BorderSide(color: WebTheme.grey200, width: 1),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行
              Row(
                children: [
                  Icon(Icons.edit_note, size: 24, color: WebTheme.getTextColor(context)),
                  const SizedBox(width: 8),
              Text(
                '编辑器设置',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: WebTheme.getTextColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // 保存状态指示
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_hasUnsavedChanges
                              ? WebTheme.getPrimaryColor(context)
                              : WebTheme.getSecondaryTextColor(context))
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_hasUnsavedChanges
                                ? WebTheme.getPrimaryColor(context)
                                : WebTheme.getSecondaryTextColor(context))
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasUnsavedChanges ? Icons.settings : Icons.check_circle,
                          size: 12,
                          color: _hasUnsavedChanges
                              ? WebTheme.getPrimaryColor(context)
                              : WebTheme.getSecondaryTextColor(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _hasUnsavedChanges ? '可保存' : '已保存',
                          style: TextStyle(
                            fontSize: 12,
                            color: _hasUnsavedChanges
                                ? WebTheme.getPrimaryColor(context)
                                : WebTheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
              // 操作按钮行
              Row(
                children: [
          Text(
                    '自定义编辑器外观和行为',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: WebTheme.getSecondaryTextColor(context),
                    ),
                  ),
                  const Spacer(),
                  // 重置按钮
                  TextButton.icon(
                    onPressed: _handleReset,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重置'),
                    style: TextButton.styleFrom(
                      foregroundColor: WebTheme.getSecondaryTextColor(context),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 保存按钮 - 🚀 修改为一直可点击
                  ElevatedButton.icon(
                    onPressed: !_isSaving ? _handleSave : null,
                    icon: _isSaving 
                        ? const SizedBox(
                            width: 16, 
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save, size: 16),
                    label: Text(_isSaving ? '保存中...' : '保存设置'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WebTheme.getPrimaryColor(context),
                      foregroundColor: WebTheme.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // 可滚动的设置内容
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isNarrow = constraints.maxWidth < 860;
                if (isNarrow) {
                  return Column(
                    children: [
                      _buildLeftSettingsColumn(),
                      const SizedBox(height: 16),
                      _buildRightSettingsColumn(),
                      const SizedBox(height: 16),
                      _buildPreviewCard(),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildLeftSettingsColumn()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildRightSettingsColumn()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildPreviewCard(),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WebTheme.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片标题 - 🚀 减少内边距
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: WebTheme.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: WebTheme.getTextColor(context)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          // 卡片内容 - 🚀 减少内边距
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    ValueChanged<double> onChanged, {
    String Function(double)? formatValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                formatValue?.call(value) ?? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}$unit',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 26,
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: ((max - min) * (unit == '倍' ? 10 : 1)).round(),
              onChanged: onChanged,
              activeColor: WebTheme.getPrimaryColor(context),
              inactiveColor: WebTheme.grey300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center, // 🚀 对齐优化
        children: [
          Expanded( // 🚀 让文字可以自动换行
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8), // 🚀 添加间距
          // 🚀 优化开关大小，与文字高度匹配
          Transform.scale(
            scale: 0.8, // 缩小开关
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: WebTheme.getPrimaryColor(context),
              inactiveThumbColor: WebTheme.grey400,
              inactiveTrackColor: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDropdown<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    String Function(T)? itemBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 30,
            child: DropdownButtonFormField<T>(
              value: value,
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemBuilder?.call(item) ?? item.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: WebTheme.grey300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: WebTheme.grey300),
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// 🚀 构建颜色选择器
  Widget _buildColorPicker(
    String label,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            onTap: () => _showColorPicker(currentColor, onColorChanged),
            child: Container(
              height: 30,
              width: double.infinity,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: WebTheme.grey300),
              ),
              child: Row(
              children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: currentColor,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: WebTheme.getSurfaceColor(context),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                    child: Text(
                      '#${currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示颜色选择对话框
  void _showColorPicker(Color currentColor, ValueChanged<Color> onColorChanged) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
              children: [
              Colors.red,
              Colors.pink,
              Colors.purple,
              Colors.deepPurple,
              Colors.indigo,
              Colors.blue,
              Colors.lightBlue,
              Colors.cyan,
              Colors.teal,
              Colors.green,
              Colors.lightGreen,
              Colors.lime,
              Colors.yellow,
              Colors.amber,
              Colors.orange,
              Colors.deepOrange,
              Colors.brown,
              Colors.grey,
              Colors.blueGrey,
              Colors.black,
            ].map((color) => GestureDetector(
              onTap: () {
                onColorChanged(color);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: currentColor == color ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WebTheme.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WebTheme.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.preview, size: 18, color: WebTheme.getTextColor(context)),
                const SizedBox(width: 8),
                Text(
                  '预览效果',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 800),
            padding: EdgeInsets.symmetric(
              horizontal: _currentSettings.paddingHorizontal,
              vertical: _currentSettings.paddingVertical,
            ),
            child: Text(
              '这是预览文本，展示当前字体设置的效果。您可以看到字体大小、行间距、字体样式等设置的实际显示效果。',
              style: TextStyle(
                fontFamily: _currentSettings.fontFamily,
                fontSize: _currentSettings.fontSize,
                fontWeight: _currentSettings.fontWeight,
                height: _currentSettings.lineSpacing,
                letterSpacing: _currentSettings.letterSpacing,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 