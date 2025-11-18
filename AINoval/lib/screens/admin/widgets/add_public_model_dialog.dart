import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../models/public_model_config.dart';
import '../../../models/model_pricing.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/logger.dart';
import '../../../utils/web_theme.dart';
import 'validation_results_dialog.dart';
import 'pricing_info_dialog.dart';

/// 添加公共模型对话框 - 直接配置表单
class AddPublicModelDialog extends StatefulWidget {
  const AddPublicModelDialog({
    super.key,
    required this.onSuccess,
    this.selectedProvider,
    this.sourceConfig,
  });

  final VoidCallback onSuccess;
  final String? selectedProvider;
  final PublicModelConfigDetails? sourceConfig;

  @override
  State<AddPublicModelDialog> createState() => _AddPublicModelDialogState();
}

class _AddPublicModelDialogState extends State<AddPublicModelDialog> {
  final String _tag = 'AddPublicModelDialog';
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
  final _creditRateController = TextEditingController(text: '1.0');
  final _maxConcurrentController = TextEditingController(text: '-1');
  final _dailyLimitController = TextEditingController(text: '-1');
  final _hourlyLimitController = TextEditingController(text: '-1');
  final _priorityController = TextEditingController(text: '0');
  
  final Set<AIFeatureType> _selectedFeatures = {AIFeatureType.aiChat};
  bool _enabled = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _adminRepository = AdminRepositoryImpl();
    
    // 如果指定了提供商，预填充
    if (widget.selectedProvider != null) {
      _providerController.text = widget.selectedProvider!;
    }
    
    // 如果有源配置，预填充数据（复制模式）
    if (widget.sourceConfig != null) {
      _initializeFromSource(widget.sourceConfig!);
    }
  }

  void _initializeFromSource(PublicModelConfigDetails source) {
    // 基本信息 - 添加副本标识
    _providerController.text = source.provider;
    _modelIdController.text = '${source.modelId}-copy';
    _displayNameController.text = '${source.displayName ?? source.modelId} (副本)';
    _apiEndpointController.text = source.apiEndpoint ?? '';
    _enabled = source.enabled ?? true;
    
    // 配置信息
    _descriptionController.text = source.description ?? '';
    _tagsController.text = source.tags?.join(', ') ?? '';
    _creditRateController.text = source.creditRateMultiplier?.toString() ?? '1.0';
    _maxConcurrentController.text = source.maxConcurrentRequests?.toString() ?? '-1';
    _dailyLimitController.text = source.dailyRequestLimit?.toString() ?? '-1';
    _hourlyLimitController.text = source.hourlyRequestLimit?.toString() ?? '-1';
    _priorityController.text = source.priority?.toString() ?? '0';
    
    // 功能授权
    _selectedFeatures.clear();
    if (source.enabledForFeatures != null) {
      for (final featureStr in source.enabledForFeatures!) {
        final feature = AIFeatureTypeHelper.fromApiString(featureStr);
        _selectedFeatures.add(feature);
      }
    }
    
    // 如果没有选中任何功能，默认选中AI聊天
    if (_selectedFeatures.isEmpty) {
      _selectedFeatures.add(AIFeatureType.aiChat);
    }
    
    // 加载完整的配置信息包括API Keys
    _loadFullConfigWithApiKeys(source.id!);
  }

  Future<void> _loadFullConfigWithApiKeys(String configId) async {
    try {
      final fullConfig = await _adminRepository.getPublicModelConfigById(configId);
      
      if (mounted) {
        setState(() {
          // 复制实际的API Keys，每行一个
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
      AppLogger.e(_tag, '加载源配置API Keys失败', e);
      if (mounted) {
        setState(() {
          // 如果加载失败，留空让用户重新配置
          _apiKeysController.text = '';
          _keyNotesController.text = '';
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

  /// 检查定价信息
  Future<void> _checkPricing() async {
    if (_providerController.text.isEmpty || _modelIdController.text.isEmpty) {
      _showSnackBar('请先填写提供商和模型ID', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _adminRepository.checkModelPricing(_providerController.text, _modelIdController.text);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => PricingInfoDialog(
            provider: _providerController.text,
            modelId: _modelIdController.text,
            checkResult: result,
            onPricingAdded: () {
              _showSnackBar('定价信息添加成功！', isError: false);
            },
          ),
        );
      }
    } catch (e) {
      AppLogger.e(_tag, '检查定价失败', e);
      _showSnackBar('检查定价失败: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 显示定价警告对话框
  Future<bool> _showPricingWarningDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缺少定价信息'),
        content: const Text('该模型没有定价信息，这可能导致积分计算错误。是否继续创建？\n\n建议您先添加定价信息。'),
        backgroundColor: WebTheme.getCardColor(context),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续创建'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// 显示备选定价对话框
  Future<bool> _showFallbackPricingDialog(PricingCheckResult result) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('找到备选定价'),
        content: Text('没有找到精确的定价信息，但找到了备选方案：\n\n${result.message}\n\n是否继续创建？系统将自动使用备选定价。'),
        backgroundColor: WebTheme.getCardColor(context),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('使用备选定价'),
          ),
        ],
      ),
    ) ?? false;
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

    if (_apiKeysController.text.trim().isEmpty) {
      _showSnackBar('请至少输入一个API Key', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 首先检查定价信息
      PricingCheckResult? pricingCheck;
      try {
        pricingCheck = await _adminRepository.checkModelPricing(_providerController.text, _modelIdController.text);
        
        if (!pricingCheck.hasPricing) {
          // 提示用户缺少定价信息
          final shouldContinue = await _showPricingWarningDialog();
          if (!shouldContinue) {
            setState(() {
              _isLoading = false;
            });
            return;
          }
        } else if (pricingCheck.status == 'fallback_available') {
          // 有备选方案，询问用户
          final shouldContinue = await _showFallbackPricingDialog(pricingCheck);
          if (!shouldContinue) {
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }
      } catch (e) {
        AppLogger.w(_tag, '检查定价信息失败，继续创建', e);
      }

      // 解析API Keys
      final apiKeyLines = _apiKeysController.text.split('\n').where((line) => line.trim().isNotEmpty).toList();
      final noteLines = _keyNotesController.text.split('\n');

      final apiKeys = <ApiKeyRequest>[];
      for (int i = 0; i < apiKeyLines.length; i++) {
        final note = i < noteLines.length ? noteLines[i].trim() : '';
        apiKeys.add(ApiKeyRequest(
          apiKey: apiKeyLines[i].trim(),
          note: note.isEmpty ? null : note,
        ));
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
        apiKeys: apiKeys,
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

      // 调用API创建配置，传递验证参数
      final result = await _adminRepository.createPublicModelConfig(request, validate: validate);
      
      AppLogger.i(_tag, validate ? '✅ 创建并验证模型配置成功' : '✅ 创建模型配置成功');
      
      if (validate) {
        // 拉取包含Key的明细并弹出结果
        try {
          final withKeys = await _adminRepository.getPublicModelConfigById(result.id!);
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => ValidationResultsDialog(config: withKeys),
            );
          }
        } catch (_) {}
      } else {
        _showSnackBar('模型配置创建成功！', isError: false);
      }
      
      widget.onSuccess();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.e(_tag, validate ? '创建并验证模型配置失败' : '创建模型配置失败', e);
      if (mounted) {
        _showSnackBar(validate ? '创建并验证失败: ${e.toString()}' : '创建失败: ${e.toString()}', isError: true);
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
                  widget.sourceConfig != null ? '复制公共模型配置' : '添加公共模型配置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                if (widget.sourceConfig != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Text(
                      '基于: ${widget.sourceConfig!.displayName ?? widget.sourceConfig!.modelId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
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
                              label: '显示名称 *',
                              hint: '用户界面显示的名称',
                              validator: (value) => value?.trim().isEmpty == true ? '请输入显示名称' : null,
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
                            child: _buildTextField(
                              controller: _apiKeysController,
                              label: 'API Keys *',
                              hint: '每行一个API Key',
                              maxLines: 3,
                              validator: (value) => value?.trim().isEmpty == true ? '请至少输入一个API Key' : null,
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
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _checkPricing,
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: const Text('检查定价'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
                const SizedBox(width: 8),
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