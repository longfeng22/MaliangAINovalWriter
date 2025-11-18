import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_bloc.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_event.dart';
import 'package:ainoval/blocs/universal_ai/universal_ai_state.dart';
import 'package:ainoval/blocs/credit/credit_bloc.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/utils/logger.dart';

/// 🚀 公共积分确认对话框
/// 统一处理所有功能的积分校验和确认逻辑
class CreditConfirmationDialog extends StatefulWidget {
  final String modelName;
  final String featureName;
  final UniversalAIRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onPurchase; // 可选的购买回调

  const CreditConfirmationDialog({
    super.key,
    required this.modelName,
    required this.featureName,
    required this.request,
    required this.onConfirm,
    required this.onCancel,
    this.onPurchase,
  });

  @override
  State<CreditConfirmationDialog> createState() => _CreditConfirmationDialogState();
}

class _CreditConfirmationDialogState extends State<CreditConfirmationDialog> {
  CostEstimationResponse? _costEstimation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _estimateCost();
    _ensureCreditLoaded();
  }
  
  void _ensureCreditLoaded() {
    try {
      final creditState = context.read<CreditBloc>().state;
      if (creditState is! CreditLoaded) {
        context.read<CreditBloc>().add(const LoadUserCredits());
      }
    } catch (e) {
      AppLogger.w('CreditConfirmationDialog', '加载积分状态失败', e);
    }
  }

  Future<void> _estimateCost() async {
    try {
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
      child: BlocBuilder<CreditBloc, CreditState>(
        builder: (context, creditState) {
          return BlocBuilder<UniversalAIBloc, UniversalAIState>(
            builder: (context, universalState) {
              final isLoading = universalState is UniversalAILoading;
              
              // 检查积分余额是否足够
              int? currentCredits;
              bool hasInsufficientCredits = false;
              bool isCreditLoading = creditState is CreditLoading || creditState is CreditInitial;
              
              if (creditState is CreditLoaded && _costEstimation != null) {
                currentCredits = creditState.userCredit.credits;
                hasInsufficientCredits = currentCredits < _costEstimation!.estimatedCost;
              }
              
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('积分消耗确认'),
                  ],
                ),
                content: SizedBox(
                  width: 350,
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
                      const SizedBox(height: 8),
                      Text(
                        '功能: ${widget.featureName}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // 当前积分余额显示
                      if (isCreditLoading) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('正在加载积分信息...', style: TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (creditState is CreditError) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '积分信息加载失败',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (creditState is CreditLoaded) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '当前积分余额:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${creditState.userCredit.credits}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: hasInsufficientCredits 
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
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
                            color: hasInsufficientCredits 
                              ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)
                              : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasInsufficientCredits 
                                ? Theme.of(context).colorScheme.error.withOpacity(0.3)
                                : Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
                                      color: hasInsufficientCredits 
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary,
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
                              const SizedBox(height: 12),
                              
                              // 积分不足警告或正常提示
                              if (hasInsufficientCredits) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber,
                                            color: Theme.of(context).colorScheme.error,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '当前积分不足，需要 ${_costEstimation!.estimatedCost - currentCredits!} 积分',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onErrorContainer,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '请前往订阅页面购买订阅计划或积分加量包',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onErrorContainer,
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  '实际消耗可能因内容长度而有所不同',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('取消'),
                  ),
                  if (hasInsufficientCredits) ...[
                    // 积分不足时显示购买按钮
                    ElevatedButton.icon(
                      onPressed: widget.onPurchase ?? () {
                        // 默认关闭对话框，后续可以扩展购买逻辑
                        widget.onCancel();
                      },
                      icon: const Icon(Icons.shopping_cart, size: 18),
                      label: const Text('购买积分'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ] else ...[
                    // 积分充足时显示确认按钮
                    ElevatedButton(
                      onPressed: (_costEstimation != null && !isLoading && !isCreditLoading && !hasInsufficientCredits) 
                        ? widget.onConfirm 
                        : null,
                      child: const Text('确认生成'),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 🚀 公共积分确认工具方法
/// 显示积分确认对话框的便捷方法
Future<bool> showCreditConfirmationDialog({
  required BuildContext context,
  required String modelName,
  required String featureName,
  required UniversalAIRequest request,
  VoidCallback? onPurchase,
}) async {
  try {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<UniversalAIBloc>()),
            BlocProvider.value(value: context.read<CreditBloc>()),
          ],
          child: CreditConfirmationDialog(
            modelName: modelName,
            featureName: featureName,
            request: request,
            onConfirm: () => Navigator.of(dialogContext).pop(true),
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onPurchase: onPurchase,
          ),
        );
      },
    );
    
    return result ?? false;
  } catch (e) {
    AppLogger.e('CreditConfirmationDialog', '积分确认对话框异常', e);
    return false;
  }
}
