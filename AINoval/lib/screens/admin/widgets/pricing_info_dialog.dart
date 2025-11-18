import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/model_pricing.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/logger.dart';
import '../../../utils/web_theme.dart';

/// 定价信息对话框 - 显示定价检查结果并提供添加定价的功能
class PricingInfoDialog extends StatefulWidget {
  const PricingInfoDialog({
    super.key,
    required this.provider,
    required this.modelId,
    required this.checkResult,
    required this.onPricingAdded,
  });

  final String provider;
  final String modelId;
  final PricingCheckResult checkResult;
  final VoidCallback onPricingAdded;

  @override
  State<PricingInfoDialog> createState() => _PricingInfoDialogState();
}

class _PricingInfoDialogState extends State<PricingInfoDialog> {
  final String _tag = 'PricingInfoDialog';
  late final AdminRepositoryImpl _adminRepository;
  
  bool _showAddForm = false;
  bool _isLoading = false;
  
  // 表单控制器
  final _formKey = GlobalKey<FormState>();
  final _modelNameController = TextEditingController();
  final _inputPriceController = TextEditingController();
  final _outputPriceController = TextEditingController();
  final _unifiedPriceController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _useUnifiedPrice = false;
  bool _supportsStreaming = true;

  @override
  void initState() {
    super.initState();
    _adminRepository = AdminRepositoryImpl();
    
    // 如果有备选定价，预填充一些数据
    if (widget.checkResult.fallbackPricing != null) {
      final fallback = widget.checkResult.fallbackPricing!;
      _modelNameController.text = widget.modelId;
      
      if (fallback.unifiedPricePerThousandTokens != null) {
        _useUnifiedPrice = true;
        _unifiedPriceController.text = fallback.unifiedPricePerThousandTokens.toString();
      } else {
        _inputPriceController.text = fallback.inputPricePerThousandTokens?.toString() ?? '';
        _outputPriceController.text = fallback.outputPricePerThousandTokens?.toString() ?? '';
      }
      
      _maxTokensController.text = fallback.maxContextTokens?.toString() ?? '';
      _supportsStreaming = fallback.supportsStreaming ?? true;
    } else {
      _modelNameController.text = widget.modelId;
    }
  }

  @override
  void dispose() {
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

  /// 提交添加定价表单
  Future<void> _submitAddPricing() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = CreatePricingRequest(
        provider: widget.provider,
        modelId: widget.modelId,
        modelName: _modelNameController.text.isEmpty ? null : _modelNameController.text,
        inputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_inputPriceController.text),
        outputPricePerThousandTokens: _useUnifiedPrice ? null : double.tryParse(_outputPriceController.text),
        unifiedPricePerThousandTokens: _useUnifiedPrice ? double.tryParse(_unifiedPriceController.text) : null,
        maxContextTokens: int.tryParse(_maxTokensController.text),
        supportsStreaming: _supportsStreaming,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      );

      await _adminRepository.createModelPricing(request);
      
      AppLogger.i(_tag, '✅ 添加定价信息成功');
      _showSnackBar('定价信息添加成功！', isError: false);
      
      widget.onPricingAdded();
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.e(_tag, '❌ 添加定价信息失败', e);
      _showSnackBar('添加定价信息失败: ${e.toString()}', isError: true);
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
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(
                  Icons.attach_money,
                  color: WebTheme.getTextColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '模型定价信息',
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
            
            const SizedBox(height: 16),
            
            // 模型信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WebTheme.getBackgroundColor(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: WebTheme.getTextColor(context).withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模型信息',
                    style: TextStyle(
                      color: WebTheme.getTextColor(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '提供商: ${widget.provider}',
                    style: TextStyle(color: WebTheme.getTextColor(context)),
                  ),
                  Text(
                    '模型ID: ${widget.modelId}',
                    style: TextStyle(color: WebTheme.getTextColor(context)),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 检查结果
            _buildCheckResult(),
            
            if (_showAddForm) ...[
              const SizedBox(height: 20),
              _buildAddPricingForm(),
            ],
            
            const SizedBox(height: 20),
            
            // 按钮栏
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_showAddForm && !widget.checkResult.exists) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAddForm = true;
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加定价'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                
                if (_showAddForm) ...[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showAddForm = false;
                      });
                    },
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitAddPricing,
                    child: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存定价'),
                  ),
                  const SizedBox(width: 12),
                ],
                
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckResult() {
    switch (widget.checkResult.status) {
      case 'found':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '找到精确定价',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.checkResult.message),
              if (widget.checkResult.exactPricing != null) ...[
                const SizedBox(height: 8),
                Text(
                  '定价信息: ${widget.checkResult.exactPricing!.priceDisplayText}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        );
        
      case 'fallback_available':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '找到备选定价',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.checkResult.message),
              if (widget.checkResult.fallbackPricing != null) ...[
                const SizedBox(height: 8),
                Text(
                  '备选定价: ${widget.checkResult.fallbackPricing!.priceDisplayText}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                Text(
                  '来源: ${widget.checkResult.fallbackPricing!.provider}:${widget.checkResult.fallbackPricing!.modelId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getTextColor(context).withOpacity(0.7),
                  ),
                ),
              ],
            ],
          ),
        );
        
      default:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '未找到定价信息',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.checkResult.message),
              const SizedBox(height: 8),
              Text(
                '建议添加定价信息以确保积分计算准确。',
                style: TextStyle(
                  color: WebTheme.getTextColor(context).withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildAddPricingForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.getTextColor(context).withOpacity(0.1),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加定价信息',
              style: TextStyle(
                color: WebTheme.getTextColor(context),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 模型名称
            TextFormField(
              controller: _modelNameController,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: '显示用的模型名称',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入模型名称';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // 定价类型选择
            Row(
              children: [
                Text(
                  '定价类型:',
                  style: TextStyle(color: WebTheme.getTextColor(context)),
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('分别定价'),
                    subtitle: const Text('输入和输出token分别定价'),
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
                    subtitle: const Text('输入和输出token使用相同价格'),
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
            
            const SizedBox(height: 16),
            
            // 价格输入
            if (_useUnifiedPrice) ...[
              TextFormField(
                controller: _unifiedPriceController,
                decoration: const InputDecoration(
                  labelText: '统一价格 (USD/1K tokens)',
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
                        labelText: '输入价格 (USD/1K tokens)',
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
                        labelText: '输出价格 (USD/1K tokens)',
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
          ],
        ),
      ),
    );
  }
}

