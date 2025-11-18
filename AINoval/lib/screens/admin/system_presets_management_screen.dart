import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../../models/preset_models.dart';
import '../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../utils/logger.dart';
import '../../utils/web_theme.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/loading_indicator.dart';
import 'widgets/add_system_preset_dialog.dart';
import 'widgets/edit_system_preset_dialog.dart';
import 'widgets/system_preset_card.dart';
import 'package:flutter/services.dart';

/// 系统预设管理页面
/// 提供完整的系统AI预设管理功能，包括：
/// - 按功能类型分组显示系统预设
/// - 添加/编辑/删除系统预设
/// - 预设可见性管理
/// - 批量操作功能
/// - 使用统计查看
class SystemPresetsManagementScreen extends StatefulWidget {
  const SystemPresetsManagementScreen({Key? key}) : super(key: key);

  @override
  State<SystemPresetsManagementScreen> createState() => _SystemPresetsManagementScreenState();
}

/// 系统预设管理内容主体，可以在不同布局中复用
class SystemPresetsManagementBody extends StatefulWidget {
  const SystemPresetsManagementBody({Key? key}) : super(key: key);

  @override
  State<SystemPresetsManagementBody> createState() => _SystemPresetsManagementBodyState();
}

class _SystemPresetsManagementScreenState extends State<SystemPresetsManagementScreen> {
  final GlobalKey<_SystemPresetsManagementBodyState> _bodyKey = GlobalKey<_SystemPresetsManagementBodyState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '系统预设管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        actions: [
          IconButton(
            onPressed: () => _bodyKey.currentState?._refreshData(),
            icon: Icon(Icons.refresh, color: WebTheme.getTextColor(context)),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: () => _bodyKey.currentState?._showStatistics(),
            icon: Icon(Icons.analytics, color: WebTheme.getTextColor(context)),
            tooltip: '统计信息',
          ),
          IconButton(
            onPressed: () => _showAddPresetDialog(context),
            icon: Icon(Icons.add, color: WebTheme.getTextColor(context)),
            tooltip: '添加系统预设',
          ),
        ],
      ),
      backgroundColor: WebTheme.getBackgroundColor(context),
      body: SystemPresetsManagementBody(key: _bodyKey),
    );
  }

  void _showAddPresetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddSystemPresetDialog(
        onSuccess: () => _bodyKey.currentState?._refreshData(),
      ),
    );
  }
}

class _SystemPresetsManagementBodyState extends State<SystemPresetsManagementBody> {
  List<AIPromptPreset> _systemPresets = [];
  Map<String, List<AIPromptPreset>> _presetsByFeatureType = {};
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;
  String? _error;
  String _selectedFeatureType = 'ALL';
  List<String> _selectedPresets = [];
  bool _batchMode = false;

  final AdminRepositoryImpl _adminRepository = AdminRepositoryImpl();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadSystemPresets(),
        _loadStatistics(),
      ]);
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '加载系统预设数据失败', e);
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSystemPresets() async {
    try {
      final presets = await _adminRepository.getSystemPresets(
        featureType: _selectedFeatureType == 'ALL' ? null : _selectedFeatureType,
      );
      
      setState(() {
        _systemPresets = presets;
        _presetsByFeatureType = _groupPresetsByFeatureType(presets);
      });
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '加载系统预设失败', e);
      rethrow;
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final stats = await _adminRepository.getSystemPresetsStatistics();
      setState(() {
        _statistics = stats;
      });
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '加载统计信息失败', e);
      // 统计信息加载失败不影响主要功能
    }
  }

  Map<String, List<AIPromptPreset>> _groupPresetsByFeatureType(List<AIPromptPreset> presets) {
    return groupBy(presets, (preset) => preset.aiFeatureType);
  }

  void _refreshData() {
    _loadData();
  }

  void _showStatistics() {
    showDialog(
      context: context,
      builder: (context) => _StatisticsDialog(statistics: _statistics),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_error != null) {
      return ErrorView(
        error: _error!,
        onRetry: _refreshData,
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Column(
          children: [
            _buildToolbar(),
            _buildFilterTabs(),
            Expanded(
              child: _buildPresetsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_batchMode) ...[
            Expanded(
              child: Text(
                '已选择 ${_selectedPresets.length} 个预设',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: _selectedPresets.isNotEmpty ? () => _batchToggleVisibility(true) : null,
              icon: const Icon(Icons.visibility),
              tooltip: '批量显示在快捷访问',
            ),
            IconButton(
              onPressed: _selectedPresets.isNotEmpty ? () => _batchToggleVisibility(false) : null,
              icon: const Icon(Icons.visibility_off),
              tooltip: '批量隐藏快捷访问',
            ),
            IconButton(
              onPressed: _selectedPresets.isNotEmpty ? _batchExport : null,
              icon: const Icon(Icons.file_download),
              tooltip: '导出选中预设',
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _batchMode = false;
                  _selectedPresets.clear();
                });
              },
              icon: const Icon(Icons.close),
              tooltip: '退出批量模式',
            ),
          ] else ...[
            Expanded(
              child: Text(
                '系统预设总数: ${_systemPresets.length}',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: _importPresets,
              icon: const Icon(Icons.file_upload),
              tooltip: '导入预设',
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _batchMode = true;
                });
              },
              icon: const Icon(Icons.checklist),
              tooltip: '批量操作',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final featureTypes = ['ALL', ..._presetsByFeatureType.keys.toList()..sort()];
    
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: featureTypes.length,
        itemBuilder: (context, index) {
          final featureType = featureTypes[index];
          final isSelected = _selectedFeatureType == featureType;
          final count = featureType == 'ALL' 
              ? _systemPresets.length 
              : _presetsByFeatureType[featureType]?.length ?? 0;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text('${_getFeatureTypeDisplayName(featureType)} ($count)'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedFeatureType = featureType;
                  });
                  _loadSystemPresets();
                }
              },
            ),
          );
        },
      ),
    );
  }

  /// 获取功能类型的中文显示名称
  String _getFeatureTypeDisplayName(String featureType) {
    switch (featureType) {
      case 'ALL':
        return '全部';
      case 'AI_CHAT':
        return 'AI聊天';
      case 'TEXT_EXPANSION':
        return '文本扩写';
      case 'TEXT_REFACTOR':
        return '文本重构';
      case 'TEXT_SUMMARY':
        return '文本总结';
      case 'SCENE_TO_SUMMARY':
        return '场景摘要';
      case 'SUMMARY_TO_SCENE':
        return '摘要扩写';
      case 'NOVEL_GENERATION':
        return '小说生成';
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return '专业续写';
      case 'SCENE_BEAT_GENERATION':
        return '场景节拍生成';
      case 'NOVEL_COMPOSE':
        return '设定编排';
      case 'SETTING_TREE_GENERATION':
        return '设定树生成';
      case 'SETTING_GENERATION_TOOL':
        return '设定生成工具调用';
      case 'STORY_PLOT_CONTINUATION':
        return '剧情续写';
      case 'KNOWLEDGE_EXTRACTION_SETTING':
        return '知识库拆书-设定';
      case 'KNOWLEDGE_EXTRACTION_OUTLINE':
        return '知识库拆书-大纲';
      default:
        return featureType; // 未知类型直接返回原值
    }
  }

  Widget _buildPresetsList() {
    if (_systemPresets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_button_outlined,
              size: 64,
              color: WebTheme.getTextColor(context).withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无系统预设',
              style: TextStyle(
                color: WebTheme.getTextColor(context).withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角的加号创建第一个系统预设',
              style: TextStyle(
                color: WebTheme.getTextColor(context).withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final displayPresets = _selectedFeatureType == 'ALL' 
        ? _systemPresets
        : _presetsByFeatureType[_selectedFeatureType] ?? [];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: displayPresets.length,
      itemBuilder: (context, index) {
        final preset = displayPresets[index];
        return SystemPresetCard(
          preset: preset,
          isSelected: _selectedPresets.contains(preset.presetId),
          batchMode: _batchMode,
          onTap: () => _handlePresetTap(preset),
          onEdit: () => _editPreset(preset),
          onDelete: () => _deletePreset(preset),
          onToggleVisibility: () => _togglePresetVisibility(preset),
          onViewStats: () => _viewPresetStats(preset),
          onViewDetails: () => _viewPresetDetails(preset),
          onSelectionChanged: (selected) {
            setState(() {
              if (selected) {
                _selectedPresets.add(preset.presetId);
              } else {
                _selectedPresets.remove(preset.presetId);
              }
            });
          },
        );
      },
    );
  }

  void _viewPresetDetails(AIPromptPreset preset) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('预设内容 - ${preset.presetName ?? ''}'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPromptPreviewSection('系统提示词 (System Prompt)', preset.systemPrompt),
                  const SizedBox(height: 16),
                  _buildPromptPreviewSection('用户提示词 (User Prompt)', preset.userPrompt.isNotEmpty ? preset.userPrompt : '(未设置)'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPromptPreviewSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.code, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (content.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板')),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: SelectableText(
            content.isNotEmpty ? content : '(空)',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  void _handlePresetTap(AIPromptPreset preset) {
    if (_batchMode) {
      final isSelected = _selectedPresets.contains(preset.presetId);
      setState(() {
        if (isSelected) {
          _selectedPresets.remove(preset.presetId);
        } else {
          _selectedPresets.add(preset.presetId);
        }
      });
    } else {
      _editPreset(preset);
    }
  }

  void _editPreset(AIPromptPreset preset) {
    showDialog(
      context: context,
      builder: (context) => EditSystemPresetDialog(
        preset: preset,
        onSuccess: _refreshData,
      ),
    );
  }

  Future<void> _deletePreset(AIPromptPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除系统预设 "${preset.presetName}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminRepository.deleteSystemPreset(preset.presetId);
        _refreshData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('系统预设 "${preset.presetName}" 已删除')),
          );
        }
      } catch (e) {
        AppLogger.e('SystemPresetsManagement', '删除系统预设失败', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _togglePresetVisibility(AIPromptPreset preset) async {
    try {
      await _adminRepository.toggleSystemPresetQuickAccess(preset.presetId);
      _refreshData();
      
      if (mounted) {
        final status = !preset.showInQuickAccess ? '显示在快捷访问' : '隐藏快捷访问';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('预设 "${preset.presetName}" 已$status')),
        );
      }
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '切换预设可见性失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _viewPresetStats(AIPromptPreset preset) {
    showDialog(
      context: context,
      builder: (context) => _PresetStatsDialog(presetId: preset.presetId),
    );
  }

  Future<void> _batchToggleVisibility(bool visible) async {
    try {
      await _adminRepository.batchUpdateSystemPresetsVisibility(_selectedPresets, visible);
      _refreshData();
      
      if (mounted) {
        final action = visible ? '显示在快捷访问' : '隐藏快捷访问';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 ${_selectedPresets.length} 个预设$action')),
        );
      }
      
      setState(() {
        _selectedPresets.clear();
        _batchMode = false;
      });
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '批量更新可见性失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量操作失败: $e')),
        );
      }
    }
  }

  Future<void> _batchExport() async {
    try {
      final presets = await _adminRepository.exportSystemPresets(_selectedPresets);
      // TODO: 实现文件导出功能
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${presets.length} 个系统预设')),
        );
      }
    } catch (e) {
      AppLogger.e('SystemPresetsManagement', '导出预设失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _importPresets() async {
    // TODO: 实现预设导入功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入功能开发中...')),
    );
  }
}

/// 统计信息对话框
class _StatisticsDialog extends StatelessWidget {
  final Map<String, dynamic> statistics;

  const _StatisticsDialog({required this.statistics});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('系统预设统计'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatItem('总预设数', statistics['totalSystemPresets']?.toString() ?? '0'),
            _buildStatItem('快捷访问预设', statistics['quickAccessCount']?.toString() ?? '0'),
            _buildStatItem('总使用次数', statistics['totalUsage']?.toString() ?? '0'),
            
            const SizedBox(height: 16),
            const Text('按功能类型分布:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            if (statistics['byFeatureType'] is Map<String, dynamic>)
              ...(statistics['byFeatureType'] as Map<String, dynamic>).entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text(entry.value.toString()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

/// 预设统计对话框
class _PresetStatsDialog extends StatefulWidget {
  final String presetId;

  const _PresetStatsDialog({required this.presetId});

  @override
  State<_PresetStatsDialog> createState() => _PresetStatsDialogState();
}

class _PresetStatsDialogState extends State<_PresetStatsDialog> {
  Map<String, dynamic>? _details;
  bool _isLoading = true;
  String? _error;

  final AdminRepositoryImpl _adminRepository = AdminRepositoryImpl();

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final details = await _adminRepository.getSystemPresetDetails(widget.presetId);
      setState(() {
        _details = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('预设详情'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('加载失败: $_error'))
                : _buildDetails(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    if (_details == null) return const SizedBox();

    final preset = _details!['preset'] as Map<String, dynamic>?;
    final statistics = _details!['statistics'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preset != null) ...[
            Text('预设名称: ${preset['presetName'] ?? ''}'),
            Text('功能类型: ${preset['aiFeatureType'] ?? ''}'),
            Text('创建时间: ${preset['createdAt'] ?? ''}'),
            Text('最后更新: ${preset['updatedAt'] ?? ''}'),
            
            const SizedBox(height: 16),
            const Text('使用统计:', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
          
          if (statistics != null) ...[
            Text('使用次数: ${statistics['useCount'] ?? 0}'),
            Text('最后使用: ${statistics['lastUsedAt'] ?? '从未使用'}'),
            Text('创建天数: ${statistics['daysSinceCreated'] ?? 0}'),
            if (statistics['daysSinceLastUsed'] != null)
              Text('上次使用距今: ${statistics['daysSinceLastUsed']} 天'),
          ],
        ],
      ),
    );
  }
}