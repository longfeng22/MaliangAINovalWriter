import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/model_pricing.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/logger.dart';
import '../../../utils/web_theme.dart';

/// 编辑/创建模型定价对话框
class EditPricingDialog extends StatefulWidget {
  const EditPricingDialog({
    super.key,
    this.pricing,
    required this.onSuccess,
  });

  final ModelPricing? pricing;
  final VoidCallback onSuccess;

  @override
  State<EditPricingDialog> createState() => _EditPricingDialogState();
}

class _EditPricingDialogState extends State<EditPricingDialog> {
  final String _tag = 'EditPricingDialog';
  late final AdminRepositoryImpl _adminRepository;
  
  bool _isLoading = false;
  
  // 表单控制器
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _modelIdController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _inputPriceController = TextEditingController();
  final _outputPriceController = TextEditingController();
  final _unifiedPriceController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _useUnifiedPrice = false;
  bool _supportsStreaming = true;
  
  bool get _isEditing => widget.pricing != null;

  @override
  void initState() {
    super.initState();
    _adminRepository = AdminRepositoryImpl();
    
    // 如果是编辑模式，填充现有数据
    if (_isEditing) {
      final pricing = widget.pricing!;
      _providerController.text = pricing.provider;
      _modelIdController.text = pricing.modelId;
      _modelNameController.text = pricing.modelName ?? '';
      
      if (pricing.unifiedPricePerThousandTokens != null) {
        _useUnifiedPrice = true;
        _unifiedPriceController.text = pricing.unifiedPricePerThousandTokens.toString();
      } else {
        _inputPriceController.text = pricing.inputPricePerThousandTokens?.toString() ?? '';
        _outputPriceController.text = pricing.outputPricePerThousandTokens?.toString() ?? '';
      }
      
      _maxTokensController.text = pricing.maxContextTokens?.toString() ?? '';
      _descriptionController.text = pricing.description ?? '';
      _supportsStreaming = pricing.supportsStreaming ?? true;
    }
  }

  @override
  void dispose() {
    _providerController.dispose();
    _modelIdController.dispose();
    _modelNameController.dispose();
    _inputPriceController.dispose();
    _outputPriceController.dispose();
    _unifiedPriceController.dispose();
    _maxTokensController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  /// 提交表单
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isEditing) {
        // 更新现有定价
        final updatedPricing = ModelPricing(
          id: widget.pricing!.id,
          provider: _providerController.text,
          modelId: _modelIdController.text,
          modelName: _modelNameController.text.isEmpty ? null : _modelNameController.text,
          inputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_inputPriceController.text),
          outputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_outputPriceController.text),
          unifiedPricePerThousandTokens: _useUnifiedPrice ? double.tryParse(_unifiedPriceController.text) : null,
          maxContextTokens: int.tryParse(_maxTokensController.text),
          supportsStreaming: _supportsStreaming,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
          source: widget.pricing!.source,
          createdAt: widget.pricing!.createdAt,
          updatedAt: DateTime.now(),
          version: widget.pricing!.version,
          active: widget.pricing!.active,
        );
        
        await _adminRepository.updateModelPricing(updatedPricing);
        
        AppLogger.i(_tag, '✅ 更新定价信息成功');
        _showSnackBar('定价信息更新成功！', isError: false);
      } else {
        // 创建新定价
        final request = CreatePricingRequest(
          provider: _providerController.text,
          modelId: _modelIdController.text,
          modelName: _modelNameController.text.isEmpty ? null : _modelNameController.text,
          inputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_inputPriceController.text),
          outputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_outputPriceController.text),
          unifiedPricePerThousandTokens: _useUnifiedPrice ? double.tryParse(_unifiedPriceController.text) : null,
          maxContextTokens: int.tryParse(_maxTokensController.text),
          supportsStreaming: _supportsStreaming,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        );

        await _adminRepository.createModelPricing(request);
        
        AppLogger.i(_tag, '✅ 创建定价信息成功');
        _showSnackBar('定价信息创建成功！', isError: false);
      }
      
      widget.onSuccess();
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ ${_isEditing ? "更新" : "创建"}定价信息失败', e);
      _showSnackBar('${_isEditing ? "更新" : "创建"}定价信息失败: ${e.toString()}', isError: true);
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
        width: 700,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Row(
                  children: [
                    Icon(
                      _isEditing ? Icons.edit : Icons.add,
                      color: WebTheme.getTextColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isEditing ? '编辑模型定价' : '添加模型定价',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: WebTheme.getTextColor(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close,
                        color: WebTheme.getTextColor(context),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // 基本信息
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _providerController,
                        enabled: !_isEditing, // 编辑时不允许修改
                        decoration: const InputDecoration(
                          labelText: '提供商 *',
                          hintText: '如: openai, anthropic',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入提供商';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _modelIdController,
                        enabled: !_isEditing, // 编辑时不允许修改
                        decoration: const InputDecoration(
                          labelText: '模型ID *',
                          hintText: '如: gpt-4o, claude-3-5-sonnet',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入模型ID';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // 模型名称
                TextFormField(
                  controller: _modelNameController,
                  decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: '显示用的模型名称（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 定价类型选择
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WebTheme.getBackgroundColor(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: WebTheme.getTextColor(context).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '定价类型',
                        style: TextStyle(
                          color: WebTheme.getTextColor(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('分别定价'),
                              subtitle: const Text('输入和输出token分别定价'),
                              dense: true,
                              value: false,
                              groupValue: _useUnifiedPrice,
                              onChanged: (value) {
                                setState(() {
                                  _useUnifiedPrice = value!;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('统一定价'),
                              subtitle: const Text('输入和输出使用相同价格'),
                              dense: true,
                              value: true,
                              groupValue: _useUnifiedPrice,
                              onChanged: (value) {
                                setState(() {
                                  _useUnifiedPrice = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 价格输入
                if (_useUnifiedPrice) ...[
                  TextFormField(
                    controller: _unifiedPriceController,
                    decoration: const InputDecoration(
                      labelText: '统一价格 (USD/1K tokens) *',
                      hintText: '例如: 0.000500',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入统一价格';
                      }
                      if (double.tryParse(value) == null) {
                        return '请输入有效的数字';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _inputPriceController,
                          decoration: const InputDecoration(
                            labelText: '输入价格 (USD/1K tokens) *',
                            hintText: '例如: 0.000250',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入输入价格';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效的数字';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _outputPriceController,
                          decoration: const InputDecoration(
                            labelText: '输出价格 (USD/1K tokens) *',
                            hintText: '例如: 0.001000',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入输出价格';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效的数字';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 16),
                
                // 最大Token数和流式支持
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxTokensController,
                        decoration: const InputDecoration(
                          labelText: '最大上下文Token数',
                          hintText: '例如: 128000',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('支持流式输出'),
                        value: _supportsStreaming,
                        onChanged: (value) {
                          setState(() {
                            _supportsStreaming = value!;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // 描述
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '描述 (可选)',
                    hintText: '定价信息的相关说明',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                
                const SizedBox(height: 24),
                
                // 按钮栏
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEditing ? '保存' : '创建'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

