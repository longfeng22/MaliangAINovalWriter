import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/preset/preset_bloc.dart';
import 'package:ainoval/blocs/preset/preset_event.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/services/ai_preset_service.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/logger.dart';

/// AI对话框公共逻辑混入
mixin AIDialogCommonLogic<T extends StatefulWidget> on State<T> {
  
  /// 创建统一的模型配置
  /// 根据模型类型（公共/私有）创建正确的配置
  UserAIModelConfigModel createModelConfig(UnifiedAIModel unifiedModel) {
    if (unifiedModel.isPublic) {
      // 对于公共模型，创建包含公共模型信息的临时配置
      final publicModel = (unifiedModel as PublicAIModel).publicConfig;
      debugPrint('🚀 创建公共模型配置 - 显示名: ${publicModel.displayName}, 模型ID: ${publicModel.modelId}, 公共模型ID: ${publicModel.id}');
      return UserAIModelConfigModel.fromJson({
        'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
        'userId': AppConfig.userId ?? 'unknown',
        'name': publicModel.displayName, // 🚀 修复：添加 name 字段
        'alias': publicModel.displayName,
        'modelName': publicModel.modelId,
        'provider': publicModel.provider,
        'apiEndpoint': '', // 公共模型没有单独的apiEndpoint
        'isDefault': false,
        'isValidated': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        // 🚀 修复：添加公共模型的额外信息
        'isPublic': true,
        'creditMultiplier': publicModel.creditRateMultiplier ?? 1.0,
      });
    } else {
      // 对于私有模型，直接使用用户配置
      final privateModel = (unifiedModel as PrivateAIModel).userConfig;
      debugPrint('🚀 使用私有模型配置 - 显示名: ${privateModel.name}, 模型名: ${privateModel.modelName}, 配置ID: ${privateModel.id}');
      return privateModel;
    }
  }

  /// 创建包含模型元数据的metadata
  Map<String, dynamic> createModelMetadata(
    UnifiedAIModel unifiedModel, 
    Map<String, dynamic> baseMetadata,
  ) {
    final metadata = Map<String, dynamic>.from(baseMetadata);
    
    // 🚀 添加模型信息
    metadata.addAll({
      'modelName': unifiedModel.modelId,
      'modelProvider': unifiedModel.provider,
      'modelConfigId': unifiedModel.id,
      'isPublicModel': unifiedModel.isPublic,
    });
    
    // 🚀 如果是公共模型，添加公共模型的真实ID
    if (unifiedModel.isPublic) {
      final String publicId = (unifiedModel as PublicAIModel).publicConfig.id;
      // 发送后端期望的无前缀公共配置ID
      metadata['publicModelConfigId'] = publicId;
      // 同时保留兼容字段
      metadata['publicModelId'] = publicId;
    }
    
    return metadata;
  }

  /// 🚀 新增：处理公共模型的积分预估和确认
  Future<bool> handlePublicModelCreditConfirmation(
    UnifiedAIModel unifiedModel, 
    UniversalAIRequest request,
  ) async {
    if (!unifiedModel.isPublic) {
      // 私有模型直接返回 true
      return true;
    }
    
    try {
      debugPrint('🚀 检测到公共模型，启动积分预估确认流程: ${unifiedModel.displayName}');
      
      bool shouldProceed = await showCreditEstimationAndConfirm(request);
      
      if (!shouldProceed) {
        debugPrint('🚀 用户取消了积分预估确认');
        return false; // 用户取消或积分不足
      }
      
      debugPrint('🚀 用户确认了积分预估');
      return true;
    } catch (e) {
      AppLogger.e('AIDialogCommonLogic', '积分预估确认失败', e);
      TopToast.error(context, '积分预估失败: $e');
      return false;
    }
  }

  /// 显示积分预估和确认对话框（仅对公共模型）
  Future<bool> showCreditEstimationAndConfirm(UniversalAIRequest request) async {
    try {
      // 显示积分预估确认对话框，传递UniversalAIBloc
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return BlocProvider.value(
            value: context.read<UniversalAIBloc>(),
            child: _CreditEstimationDialog(
              modelName: request.modelConfig?.name ?? 'Unknown Model',
              request: request,
              onConfirm: () => Navigator.of(dialogContext).pop(true),
              onCancel: () => Navigator.of(dialogContext).pop(false),
            ),
          );
        },
      ) ?? false;

    } catch (e) {
      AppLogger.e('AIDialogCommonLogic', '积分预估失败', e);
      TopToast.error(context, '积分预估失败: $e');
      return false;
    }
  }

  /// 🚀 新增：通用的预设创建逻辑
  Future<void> createPreset(
    String name, 
    String description, 
    UniversalAIRequest currentRequest,
    {Function(AIPromptPreset)? onPresetCreated}
  ) async {
    try {
      final presetService = AIPresetService();
      final request = CreatePresetRequest(
        presetName: name,
        presetDescription: description.isNotEmpty ? description : null,
        request: currentRequest,
      );

      final preset = await presetService.createPreset(request);
      
      // 🚀 新增：更新本地预设缓存
      try {
        context.read<PresetBloc>().add(AddPresetToCache(preset: preset));
        AppLogger.i('AIDialogCommonLogic', '✅ 已添加预设到本地缓存: ${preset.presetName}');
      } catch (e) {
        AppLogger.w('AIDialogCommonLogic', '⚠️ 添加预设到本地缓存失败，但预设创建成功', e);
      }
      
      // 调用回调处理预设创建成功
      onPresetCreated?.call(preset);
      
      TopToast.success(context, '预设 "$name" 创建成功');

      AppLogger.i('AIDialogCommonLogic', '预设创建成功: $name');
    } catch (e) {
      AppLogger.e('AIDialogCommonLogic', '创建预设失败', e);
      TopToast.error(context, '创建预设失败: $e');
    }
  }

  /// 🚀 新增：显示预设名称输入对话框
  Future<void> showPresetNameDialog(
    UniversalAIRequest currentRequest,
    {Function(AIPromptPreset)? onPresetCreated}
  ) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建预设'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                hintText: '输入预设名称',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                hintText: '输入预设描述',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop();
                createPreset(name, descController.text.trim(), currentRequest, onPresetCreated: onPresetCreated);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 🚀 新增：通用的预设应用逻辑
  void applyPresetToForm(
    AIPromptPreset preset,
    {
      TextEditingController? instructionsController,
      Function(String?)? onStyleChanged,
      Function(String?)? onLengthChanged,
      Function(bool)? onSmartContextChanged,
      Function(String?)? onPromptTemplateChanged,
      Function(double)? onTemperatureChanged,
      Function(double)? onTopPChanged,
      Function(ContextSelectionData)? onContextSelectionChanged,
      Function(UnifiedAIModel?)? onModelChanged,
      ContextSelectionData? currentContextData,
    }
  ) {
    try {
      // 🚀 解析requestData中的JSON并应用到表单
      final parsedRequest = preset.parsedRequest;
      if (parsedRequest != null) {
        AppLogger.i('AIDialogCommonLogic', '从预设解析出完整配置: ${preset.presetName}');
        
        // 应用指令内容
        if (instructionsController != null) {
          if (parsedRequest.instructions != null && parsedRequest.instructions!.isNotEmpty) {
            instructionsController.text = parsedRequest.instructions!;
          } else {
            // 回退到预设的用户提示词
            instructionsController.text = preset.effectiveUserPrompt;
          }
        }
        
        // 应用模型配置
        if (parsedRequest.modelConfig != null && onModelChanged != null) {
          onModelChanged(PrivateAIModel(parsedRequest.modelConfig!));
          AppLogger.i('AIDialogCommonLogic', '应用模型配置: ${parsedRequest.modelConfig!.name}');
        }
        
        // 🚀 应用上下文选择（保持完整菜单结构）
        if (parsedRequest.contextSelections != null && 
            parsedRequest.contextSelections!.selectedCount > 0 &&
            onContextSelectionChanged != null &&
            currentContextData != null) {
          final updatedContextData = currentContextData.applyPresetSelections(
            parsedRequest.contextSelections!,
          );
          onContextSelectionChanged(updatedContextData);
          AppLogger.i('AIDialogCommonLogic', '应用预设上下文选择: ${updatedContextData.selectedCount}个项目');
        }
        
        // 应用参数设置
        if (parsedRequest.parameters.isNotEmpty) {
          // 应用智能上下文设置
          if (onSmartContextChanged != null) {
            onSmartContextChanged(parsedRequest.enableSmartContext);
          }
          
          // 🚀 应用温度参数
          final temperature = parsedRequest.parameters['temperature'];
          if (temperature != null && onTemperatureChanged != null) {
            if (temperature is double) {
              onTemperatureChanged(temperature);
            } else if (temperature is num) {
              onTemperatureChanged(temperature.toDouble());
            }
            AppLogger.i('AIDialogCommonLogic', '应用预设温度参数: $temperature');
          }
          
          // 🚀 应用Top-P参数
          final topP = parsedRequest.parameters['topP'];
          if (topP != null && onTopPChanged != null) {
            if (topP is double) {
              onTopPChanged(topP);
            } else if (topP is num) {
              onTopPChanged(topP.toDouble());
            }
            AppLogger.i('AIDialogCommonLogic', '应用预设Top-P参数: $topP');
          }
          
          // 🚀 应用提示词模板ID
          final promptTemplateId = parsedRequest.parameters['promptTemplateId'];
          if (promptTemplateId is String && promptTemplateId.isNotEmpty && onPromptTemplateChanged != null) {
            onPromptTemplateChanged(promptTemplateId);
            AppLogger.i('AIDialogCommonLogic', '应用预设提示词模板ID: $promptTemplateId');
          }
          
          // 应用特定参数（如长度、风格等）
          final style = parsedRequest.parameters['style'] as String?;
          if (style != null && style.isNotEmpty && onStyleChanged != null) {
            onStyleChanged(style);
          }
          
          final length = parsedRequest.parameters['length'] as String?;
          if (length != null && length.isNotEmpty && onLengthChanged != null) {
            onLengthChanged(length);
          }
          
          AppLogger.i('AIDialogCommonLogic', '应用参数设置完成');
        }
        
        AppLogger.i('AIDialogCommonLogic', '完整配置应用成功');
      } else {
        AppLogger.w('AIDialogCommonLogic', '无法解析预设的requestData，仅应用提示词');
        // 回退到仅应用提示词
        if (instructionsController != null) {
          instructionsController.text = preset.effectiveUserPrompt;
        }
      }
      
      // 记录预设使用
      AIPresetService().applyPreset(preset.presetId);
      
      TopToast.success(context, '已应用预设: ${preset.displayName}');
      
      AppLogger.i('AIDialogCommonLogic', '预设已应用: ${preset.displayName}');
    } catch (e) {
      AppLogger.e('AIDialogCommonLogic', '应用预设失败', e);
      TopToast.error(context, '应用预设失败: $e');
    }
  }
}

/// 🚀 积分预估确认对话框（从expansion_dialog.dart提取）
class _CreditEstimationDialog extends StatefulWidget {
  final String modelName;
  final UniversalAIRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _CreditEstimationDialog({
    required this.modelName,
    required this.request,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_CreditEstimationDialog> createState() => _CreditEstimationDialogState();
}

class _CreditEstimationDialogState extends State<_CreditEstimationDialog> {
  CostEstimationResponse? _costEstimation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _estimateCost();
  }

  Future<void> _estimateCost() async {
    try {
      // 🚀 调用真实的积分预估API
      final universalAIBloc = context.read<UniversalAIBloc>();
      universalAIBloc.add(EstimateCostEvent(widget.request));
    } catch (e) {
      setState(() {
        _errorMessage = '预估失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UniversalAIBloc, UniversalAIState>(
      listener: (context, state) {
        if (state is UniversalAICostEstimationSuccess) {
          setState(() {
            _costEstimation = state.costEstimation;
            _errorMessage = null;
          });
        } else if (state is UniversalAIError) {
          setState(() {
            _errorMessage = state.message;
            _costEstimation = null;
          });
        }
      },
      child: BlocBuilder<UniversalAIBloc, UniversalAIState>(
        builder: (context, state) {
          final isLoading = state is UniversalAILoading;
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: WebTheme.getPrimaryColor(context),
                ),
                const SizedBox(width: 8),
                const Text('积分消耗预估'),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模型: ${widget.modelName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (isLoading) ...[
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('正在估算积分消耗...'),
                      ],
                    ),
                  ] else if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_costEstimation != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                       decoration: BoxDecoration(
                         color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                         borderRadius: BorderRadius.circular(8),
                         border: Border.all(
                           color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                         ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '预估消耗积分:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${_costEstimation!.estimatedCost}',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: WebTheme.getPrimaryColor(context),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (_costEstimation!.estimatedInputTokens != null || _costEstimation!.estimatedOutputTokens != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Token预估:',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                Text(
                                  '输入: ${_costEstimation!.estimatedInputTokens ?? 0}, 输出: ${_costEstimation!.estimatedOutputTokens ?? 0}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '实际消耗可能因内容长度和模型响应而有所不同',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  Text(
                    '确认要继续生成吗？',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : widget.onCancel,
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: isLoading || _errorMessage != null || _costEstimation == null ? null : widget.onConfirm,
                child: const Text('确认生成'),
              ),
            ],
          );
        },
      ),
    );
  }
} 