import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/public_model_config.dart';
import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
import 'package:ainoval/blocs/public_models/public_models_bloc.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';

/// 多模型选择器组件
/// 
/// 支持同时选择多个公共模型和私有模型
/// 用于需要多模型协同工作的场景，如剧情推演
class MultiModelSelector extends StatefulWidget {
  final List<UnifiedAIModel> selectedModels;
  final Function(List<UnifiedAIModel>) onSelectionChanged;
  final bool includePublicModels;
  final bool includePrivateModels;
  final int? maxSelections;
  final String? placeholder;

  const MultiModelSelector({
    Key? key,
    required this.selectedModels,
    required this.onSelectionChanged,
    this.includePublicModels = true,
    this.includePrivateModels = true,
    this.maxSelections,
    this.placeholder,
  }) : super(key: key);

  @override
  State<MultiModelSelector> createState() => _MultiModelSelectorState();
}

class _MultiModelSelectorState extends State<MultiModelSelector> {
  List<UnifiedAIModel> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableModels();
  }

  /// 加载可用的模型列表
  void _loadAvailableModels() {
    setState(() {
      _isLoadingModels = true;
    });

    final aiConfigState = context.read<AiConfigBloc>().state;
    final publicModelsState = context.read<PublicModelsBloc>().state;
    
    final allModels = _combineModels(aiConfigState, publicModelsState);
    
    setState(() {
      _availableModels = allModels;
      _isLoadingModels = false;
    });
  }

  /// 合并私有模型和公共模型
  List<UnifiedAIModel> _combineModels(AiConfigState aiState, PublicModelsState publicState) {
    final List<UnifiedAIModel> allModels = [];
    
    // 添加已验证的私有模型
    if (widget.includePrivateModels) {
      final validatedConfigs = aiState.validatedConfigs;
      for (final config in validatedConfigs) {
        allModels.add(PrivateAIModel(config));
      }
    }
    
    // 添加公共模型
    if (widget.includePublicModels && publicState is PublicModelsLoaded) {
      for (final publicModel in publicState.models) {
        allModels.add(PublicAIModel(publicModel));
      }
    }
    
    return allModels;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选择的模型标签
        if (widget.selectedModels.isNotEmpty)
          _buildSelectedModelsChips(),
        
        if (widget.selectedModels.isNotEmpty)
          const SizedBox(height: 12),
        
        // 选择器按钮 - 暂时显示占位符
        _buildPlaceholderSelector(),
      ],
    );
  }

  /// 构建已选择模型的标签
  Widget _buildSelectedModelsChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.selectedModels.map((model) {
        return Chip(
          avatar: Icon(
            Icons.smart_toy, // 简化图标
            size: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          label: Text(
            model.displayName,
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getTextColor(context),
            ),
          ),
          deleteIcon: Icon(
            Icons.close,
            size: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          onDeleted: () => _removeModel(model),
          backgroundColor: WebTheme.getSurfaceColor(context),
          side: BorderSide(
            color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey300 
              : WebTheme.grey300,
          ),
        );
      }).toList(),
    );
  }

  /// 构建占位符选择器
  Widget _buildPlaceholderSelector() {
    return InkWell(
      onTap: _showModelSelectionDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey300 
              : WebTheme.grey300,
          ),
          borderRadius: BorderRadius.circular(8),
          color: WebTheme.getBackgroundColor(context),
        ),
        child: Row(
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.placeholder ?? '点击选择AI模型',
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示模型选择对话框
  void _showModelSelectionDialog() {
    // 检查widget是否还在widget树中，避免生命周期错误
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => _buildModelSelectionDialog(),
    );
  }

  /// 构建模型选择对话框
  Widget _buildModelSelectionDialog() {
    // 创建临时选择状态
    List<UnifiedAIModel> tempSelectedModels = List.from(widget.selectedModels);
    
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('选择AI模型'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: _isLoadingModels 
              ? const Center(child: CircularProgressIndicator())
              : _availableModels.isEmpty
                ? const Center(
                    child: Text(
                      '暂无可用模型\n请先配置AI模型',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已选择 ${tempSelectedModels.length} 个模型'
                        '${widget.maxSelections != null ? ' / ${widget.maxSelections}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _availableModels.length,
                          itemBuilder: (context, index) {
                            final model = _availableModels[index];
                            final isSelected = tempSelectedModels.any((selected) => selected.id == model.id);
                            final canSelect = widget.maxSelections == null || 
                                            tempSelectedModels.length < widget.maxSelections! ||
                                            isSelected;
                            
                            return ListTile(
                              leading: Icon(
                                model.isPublic ? Icons.public : Icons.person,
                                color: model.isPublic ? Colors.blue : Colors.green,
                                size: 20,
                              ),
                              title: Text(
                                model.displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: canSelect ? null : Colors.grey,
                                ),
                              ),
                              subtitle: Text(
                                '${model.provider} ${model.isPublic ? '(公共)' : '(私有)'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Checkbox(
                                value: isSelected,
                                onChanged: canSelect ? (bool? value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      tempSelectedModels.add(model);
                                    } else {
                                      tempSelectedModels.removeWhere((selected) => selected.id == model.id);
                                    }
                                  });
                                } : null,
                              ),
                              onTap: canSelect ? () {
                                setDialogState(() {
                                  final isCurrentlySelected = tempSelectedModels.any((selected) => selected.id == model.id);
                                  if (isCurrentlySelected) {
                                    tempSelectedModels.removeWhere((selected) => selected.id == model.id);
                                  } else {
                                    tempSelectedModels.add(model);
                                  }
                                });
                              } : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                widget.onSelectionChanged(tempSelectedModels);
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }


  /// 移除指定模型
  void _removeModel(UnifiedAIModel model) {
    final selectedModels = List<UnifiedAIModel>.from(widget.selectedModels);
    selectedModels.removeWhere((selected) => selected.id == model.id);
    
    AppLogger.d('MultiModelSelector', '移除模型: ${model.displayName}');
    widget.onSelectionChanged(selectedModels);
  }
}
