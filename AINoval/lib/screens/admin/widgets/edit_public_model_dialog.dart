import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../models/public_model_config.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/logger.dart';
import '../../../utils/web_theme.dart';
import 'validation_results_dialog.dart';

/// 编辑公共模型对话框
class EditPublicModelDialog extends StatefulWidget {
  const EditPublicModelDialog({
    super.key,
    required this.config,
    required this.onSuccess,
  });

  final PublicModelConfigDetails config;
  final VoidCallback onSuccess;

  @override
  State<EditPublicModelDialog> createState() => _EditPublicModelDialogState();
}

class _EditPublicModelDialogState extends State<EditPublicModelDialog> {
  final String _tag = 'EditPublicModelDialog';
  late final AdminRepositoryImpl _adminRepository;
  
  // 表单数据
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _modelIdController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _apiEndpointController = TextEditingController();
  final _apiKeysController = TextEditingController();
  final _keyNotesController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _creditRateController = TextEditingController();
  final _maxConcurrentController = TextEditingController();
  final _dailyLimitController = TextEditingController();
  final _hourlyLimitController = TextEditingController();
  final _priorityController = TextEditingController();
  
  final Set<AIFeatureType> _selectedFeatures = {};
  bool _enabled = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _adminRepository = AdminRepositoryImpl();
    _initializeForm();
  }

  void _initializeForm() {
    final config = widget.config;
    
    // 基本信息
    _providerController.text = config.provider;
    _modelIdController.text = config.modelId;
    _displayNameController.text = config.displayName ?? '';
    _apiEndpointController.text = config.apiEndpoint ?? '';
    _enabled = config.enabled ?? true;
    
    // 配置信息
    _descriptionController.text = config.description ?? '';
    _tagsController.text = config.tags?.join(', ') ?? '';
    _creditRateController.text = config.creditRateMultiplier?.toString() ?? '1.0';
    _maxConcurrentController.text = config.maxConcurrentRequests?.toString() ?? '-1';
    _dailyLimitController.text = config.dailyRequestLimit?.toString() ?? '-1';
    _hourlyLimitController.text = config.hourlyRequestLimit?.toString() ?? '-1';
    _priorityController.text = config.priority?.toString() ?? '0';
    
    // 功能授权
    if (config.enabledForFeatures != null) {
      for (final featureStr in config.enabledForFeatures!) {
        final feature = AIFeatureTypeHelper.fromApiString(featureStr);
        _selectedFeatures.add(feature);
      }
    }
    
    // 如果没有选中任何功能，默认选中AI聊天
    if (_selectedFeatures.isEmpty) {
      _selectedFeatures.add(AIFeatureType.aiChat);
    }
    
    // 加载完整的配置信息包括API Keys
    _loadFullConfigWithApiKeys();
  }

  Future<void> _loadFullConfigWithApiKeys() async {
    try {
      final fullConfig = await _adminRepository.getPublicModelConfigById(widget.config.id!);
      
      if (mounted) {
        setState(() {
          // 显示实际的API Keys，每行一个
          if (fullConfig.apiKeyStatuses?.isNotEmpty == true) {
            final apiKeys = fullConfig.apiKeyStatuses!
                .map((status) => status.apiKey ?? '')
                .where((key) => key.isNotEmpty)
                .join('\n');
            _apiKeysController.text = apiKeys;
            _keyNotesController.text = fullConfig.apiKeyStatuses!
                .map((status) => status.note ?? '')
                .join('\n');
          } else {
            _apiKeysController.text = '';
            _keyNotesController.text = '';
          }
        });
      }
    } catch (e) {
      AppLogger.e(_tag, '加载完整配置信息失败', e);
      if (mounted) {
        setState(() {
          // 如果加载失败，显示占位符
          _apiKeysController.text = '*** 加载API Keys失败 ***';
          _keyNotesController.text = widget.config.apiKeyStatuses?.map((status) => status.note ?? '').join('\n') ?? '';
        });
      }
    }
  }

  @override
  void dispose() {
    _providerController.dispose();
    _modelIdController.dispose();
    _displayNameController.dispose();
    _apiEndpointController.dispose();
    _apiKeysController.dispose();
    _keyNotesController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _creditRateController.dispose();
    _maxConcurrentController.dispose();
    _dailyLimitController.dispose();
    _hourlyLimitController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  /// 保存配置
  Future<void> _saveConfig({required bool validate}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_providerController.text.isEmpty) {
      _showSnackBar('请输入提供商', isError: true);
      return;
    }

    if (_modelIdController.text.isEmpty) {
      _showSnackBar('请输入模型ID', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 解析API Keys - 如果用户修改了API Keys
      List<ApiKeyRequest>? apiKeys;
      if (_apiKeysController.text.trim() != '*** API Keys已配置 ***') {
        final apiKeyLines = _apiKeysController.text.split('\n').where((line) => line.trim().isNotEmpty).toList();
        final noteLines = _keyNotesController.text.split('\n');

        apiKeys = <ApiKeyRequest>[];
        for (int i = 0; i < apiKeyLines.length; i++) {
          final note = i < noteLines.length ? noteLines[i].trim() : '';
          apiKeys.add(ApiKeyRequest(
            apiKey: apiKeyLines[i].trim(),
            note: note.isEmpty ? null : note,
          ));
        }
      }

      // 解析标签
      final tags = _tagsController.text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();

      // 使用扩展方法转换功能类型枚举为字符串
      final enabledFeaturesStrings = AIFeatureTypeHelper.toApiStringList(_selectedFeatures);

      final request = PublicModelConfigRequest(
        provider: _providerController.text,
        modelId: _modelIdController.text,
        displayName: _displayNameController.text.isEmpty ? null : _displayNameController.text,
        enabled: _enabled,
        apiKeys: apiKeys, // 如果为null，后端保持原有API Keys不变
        apiEndpoint: _apiEndpointController.text.isEmpty ? null : _apiEndpointController.text,
        enabledForFeatures: enabledFeaturesStrings,
        creditRateMultiplier: double.tryParse(_creditRateController.text),
        maxConcurrentRequests: int.tryParse(_maxConcurrentController.text),
        dailyRequestLimit: int.tryParse(_dailyLimitController.text),
        hourlyRequestLimit: int.tryParse(_hourlyLimitController.text),
        priority: int.tryParse(_priorityController.text),
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        tags: tags,
      );

      // 调用API更新配置
      await _adminRepository.updatePublicModelConfig(widget.config.id!, request, validate: validate);
      
      AppLogger.i(_tag, validate ? '✅ 更新并验证模型配置成功' : '✅ 更新模型配置成功');
      
      if (validate) {
        try {
          final withKeys = await _adminRepository.getPublicModelConfigById(widget.config.id!);
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => ValidationResultsDialog(config: withKeys),
            );
          }
        } catch (_) {
          _showSnackBar('模型配置更新成功，验证完成！', isError: false);
        }
      } else {
        _showSnackBar('模型配置更新成功！', isError: false);
      }
      
      widget.onSuccess();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.e(_tag, validate ? '更新并验证模型配置失败' : '更新模型配置失败', e);
      if (mounted) {
        _showSnackBar(validate ? '更新并验证失败: ${e.toString()}' : '更新失败: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WebTheme.getCardColor(context),
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Text(
                  '编辑公共模型配置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Text(
                    widget.config.provider,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: WebTheme.getTextColor(context)),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 表单内容
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基本信息 - 两列布局
                      _buildSectionTitle('基本信息'),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _providerController,
                              label: '提供商 *',
                              hint: '如: openai, anthropic',
                              validator: (value) => value?.trim().isEmpty == true ? '请输入提供商名称' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _modelIdController,
                              label: '模型ID *',
                              hint: '如: gpt-4, claude-3-opus',
                              validator: (value) => value?.trim().isEmpty == true ? '请输入模型ID' : null,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _displayNameController,
                              label: '显示名称',
                              hint: '用户界面显示的名称',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _apiEndpointController,
                              label: 'API Endpoint',
                              hint: '可选，自定义API地址',
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // API Keys配置
                      _buildSectionTitle('API Keys配置'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTextField(
                                  controller: _apiKeysController,
                                  label: 'API Keys',
                                  hint: '每行一个API Key，或保持不变',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '提示: 如需修改API Keys，请清空并重新输入',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: WebTheme.getSecondaryTextColor(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _keyNotesController,
                              label: 'Key备注',
                              hint: '每行一个备注（可选）',
                              maxLines: 3,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 功能授权
                      _buildSectionTitle('功能授权'),
                      _buildFeatureSelection(),
                      
                      const SizedBox(height: 16),
                      
                      // 限制配置 - 三列布局
                      _buildSectionTitle('限制配置'),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _creditRateController,
                              label: '积分倍数',
                              hint: '默认 1.0',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value?.isNotEmpty == true) {
                                  final parsed = double.tryParse(value!);
                                  if (parsed == null || parsed <= 0) return '请输入大于0的数字';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _maxConcurrentController,
                              label: '最大并发',
                              hint: '-1表示无限制',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _priorityController,
                              label: '优先级',
                              hint: '数字越大优先级越高',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _dailyLimitController,
                              label: '每日请求限制',
                              hint: '-1表示无限制',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _hourlyLimitController,
                              label: '每小时请求限制',
                              hint: '-1表示无限制',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 启用状态开关
                          Expanded(
                            child: SwitchListTile(
                              title: Text(
                                '启用状态',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: WebTheme.getTextColor(context),
                                ),
                              ),
                              value: _enabled,
                              onChanged: (value) => setState(() => _enabled = value),
                              activeColor: Colors.green,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 其他信息
                      _buildSectionTitle('其他信息'),
                      _buildTextField(
                        controller: _descriptionController,
                        label: '描述',
                        hint: '模型用途、特点等描述信息',
                        maxLines: 2,
                      ),
                      
                      const SizedBox(height: 12),
                      
                      _buildTextField(
                        controller: _tagsController,
                        label: '标签',
                        hint: '用逗号分隔，如: 高性能,推荐,beta',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    '取消',
                    style: TextStyle(color: WebTheme.getSecondaryTextColor(context)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveConfig(validate: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WebTheme.getSecondaryTextColor(context),
                    foregroundColor: WebTheme.getBackgroundColor(context),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('仅保存'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveConfig(validate: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存并验证'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: WebTheme.getTextColor(context),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: WebTheme.getTextColor(context), fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: WebTheme.getSecondaryTextColor(context),
          fontSize: 12,
        ),
        hintStyle: TextStyle(
          color: WebTheme.getSecondaryTextColor(context).withValues(alpha: 0.7),
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(
            color: Colors.blue,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: WebTheme.getBackgroundColor(context),
        isDense: true,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildFeatureSelection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: WebTheme.getBorderColor(context)),
        borderRadius: BorderRadius.circular(6),
        color: WebTheme.getBackgroundColor(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择授权功能 (至少选择一个)',
            style: TextStyle(
              fontSize: 12,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: AIFeatureTypeHelper.allFeatures.map((featureType) {
              final bool isSelected = _selectedFeatures.contains(featureType);
              return FilterChip(
                label: Text(
                  featureType.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : WebTheme.getTextColor(context),
                  ),
                ),
                tooltip: _getFeatureDescription(featureType),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedFeatures.add(featureType);
                    } else {
                      _selectedFeatures.remove(featureType);
                    }
                  });
                },
                selectedColor: Colors.blue,
                backgroundColor: WebTheme.getCardColor(context),
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          if (_selectedFeatures.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '请至少选择一个功能',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getFeatureDescription(AIFeatureType type) {
    switch (type) {
      case AIFeatureType.aiChat:
        return 'AI对话功能';
      case AIFeatureType.textExpansion:
        return '文本内容扩展';
      case AIFeatureType.textRefactor:
        return '文本结构重构';
      case AIFeatureType.textSummary:
        return '文本内容总结';
      case AIFeatureType.sceneToSummary:
        return '场景生成摘要';
      case AIFeatureType.summaryToScene:
        return '摘要生成场景';
      case AIFeatureType.novelGeneration:
        return '小说内容生成';
      case AIFeatureType.professionalFictionContinuation:
        return '专业小说续写';
      case AIFeatureType.sceneBeatGeneration:
        return '场景节拍生成';
      case AIFeatureType.novelCompose:
        return '设定编排（大纲/章节/组合）';
      case AIFeatureType.settingTreeGeneration:
        return '设定树生成';
      case AIFeatureType.settingGenerationTool:
        return '设定生成工具调用阶段';
      case AIFeatureType.storyPlotContinuation:
        return '故事剧情续写（总结当前剧情并生成下一个大纲）';
      case AIFeatureType.knowledgeExtractionSetting:
        return '知识库拆书 - 设定提取';
      case AIFeatureType.knowledgeExtractionOutline:
        return '知识库拆书 - 章节大纲生成';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
} 