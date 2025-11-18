import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ainoval/models/admin/subscription_models.dart';
import 'package:ainoval/services/api_service/repositories/payment_repository.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';
// 条件导入：只在Web平台导入dart:html
import 'payment_dialog_web.dart' if (dart.library.io) 'payment_dialog_stub.dart';

/// 支付对话框
/// 标准的AI产品订阅支付流程
class PaymentDialog extends StatefulWidget {
  final SubscriptionPlan plan;
  final PayChannel channel;
  final PaymentRepository paymentRepo;

  const PaymentDialog({
    super.key,
    required this.plan,
    required this.channel,
    required this.paymentRepo,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  static const String _tag = 'PaymentDialog';
  
  PaymentOrderDto? _order;
  Timer? _pollTimer;
  bool _isCreatingOrder = false;  // 不自动创建
  String? _errorMessage;
  String _currentStatus = 'PENDING';
  bool _showPreview = true;  // 默认显示预览

  @override
  void initState() {
    super.initState();
    // ❌ 不再自动创建订单
    // _createOrder();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 用户确认支付后创建订单
  Future<void> _confirmAndCreateOrder() async {
    try {
      setState(() {
        _showPreview = false;  // 隐藏预览
        _isCreatingOrder = true;
        _errorMessage = null;
      });

      final order = await widget.paymentRepo.createPayment(
        planId: widget.plan.id!,
        channel: widget.channel,
        returnUrl: '${Uri.base.origin}/#/payment-result',
      );

      setState(() {
        _order = order;
        _currentStatus = order.status;
        _isCreatingOrder = false;
      });

      // 开始轮询订单状态
      _startPolling();
    } catch (e) {
      AppLogger.e(_tag, '创建订单失败', e);
      setState(() {
        _errorMessage = '创建订单失败: $e';
        _isCreatingOrder = false;
      });
    }
  }

  /// 构建订单预览页面
  Widget _buildOrderPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 订单信息卡片
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '订单信息',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildInfoRow('订阅计划', widget.plan.planName),
                _buildInfoRow('计费周期', widget.plan.billingCycleText),
                _buildInfoRow('订单金额', '¥${widget.plan.price.toStringAsFixed(2)}'),
                if (widget.plan.creditsGranted != null)
                  _buildInfoRow('赠送积分', '${widget.plan.creditsGranted} 积分'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 支付方式选择
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支付方式',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildPaymentMethodItem(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 订单说明
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    '订单说明',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                '• 订单确认后将跳转到支付页面\n'
                '• 请在15分钟内完成支付\n'
                '• 支付成功后将自动激活订阅',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 确认支付按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmAndCreateOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '确认支付',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建支付方式项
  Widget _buildPaymentMethodItem() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            widget.channel == PayChannel.alipay
                ? Icons.account_balance_wallet
                : Icons.chat,
            size: 32,
            color: widget.channel == PayChannel.alipay
                ? const Color(0xFF1677FF)
                : const Color(0xFF07C160),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getChannelName(widget.channel),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.channel == PayChannel.alipay
                      ? '推荐使用，支持扫码和网页支付'
                      : '支持扫码支付',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.blue, size: 24),
        ],
      ),
    );
  }

  /// 开始轮询订单状态
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_order == null) return;

      try {
        final status = await widget.paymentRepo.getOrderStatus(_order!.outTradeNo);
        if (status != null && status.status != _currentStatus) {
          setState(() {
            _currentStatus = status.status;
          });

          // 支付成功或失败，停止轮询
          if (status.status == 'SUCCESS' || status.status == 'FAILED') {
            timer.cancel();
            if (status.status == 'SUCCESS') {
              _showSuccessAndClose();
            }
          }
        }
      } catch (e) {
        AppLogger.e(_tag, '查询订单状态失败', e);
      }
    });
  }

  /// 显示成功提示并关闭对话框
  void _showSuccessAndClose() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop(true); // 返回true表示支付成功
      }
    });
  }

  /// 打开支付链接
  Future<void> _openPaymentUrl() async {
    if (_order?.paymentUrl == null || _order!.paymentUrl.isEmpty) return;

    try {
      final paymentUrl = _order!.paymentUrl;
      
      // 判断是HTML表单还是URL
      if (paymentUrl.trim().startsWith('<')) {
        // 支付宝返回的HTML表单，需要在新窗口渲染
        _openPaymentForm(paymentUrl);
      } else {
        // 普通URL，直接打开
        final uri = Uri.parse(paymentUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      AppLogger.e(_tag, '打开支付链接失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开支付链接失败: $e')),
        );
      }
    }
  }

  /// 在新窗口渲染支付宝HTML表单
  void _openPaymentForm(String htmlForm) {
    if (kIsWeb) {
      // Web平台：使用专用方法打开支付表单
      openPaymentFormInNewWindow(htmlForm);
    } else {
      // 移动端：复制HTML到剪贴板，提示用户在浏览器中打开
      Clipboard.setData(ClipboardData(text: htmlForm));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('支付表单已复制，请在浏览器中打开'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 复制支付链接
  void _copyPaymentUrl() {
    if (_order?.paymentUrl == null || _order!.paymentUrl.isEmpty) return;

    Clipboard.setData(ClipboardData(text: _order!.paymentUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('支付链接已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.payment, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '订阅支付',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const Divider(height: 32),

            // 内容区域
            if (_showPreview)
              // 显示订单预览
              Expanded(
                child: SingleChildScrollView(
                  child: _buildOrderPreview(),
                ),
              )
            else if (_isCreatingOrder)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在创建订单...'),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showPreview = true;
                            _errorMessage = null;
                          });
                        },
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_order != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 订单信息
                      _buildOrderInfo(),
                      const SizedBox(height: 24),

                      // 支付状态
                      _buildPaymentStatus(),
                      const SizedBox(height: 24),

                      // 支付方式说明
                      _buildPaymentInstructions(),
                      const SizedBox(height: 24),

                      // 支付链接操作
                      _buildPaymentActions(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建订单信息卡片
  Widget _buildOrderInfo() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '订单信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('订阅计划', widget.plan.planName),
            _buildInfoRow('订单金额', '¥${widget.plan.price.toStringAsFixed(2)}'),
            _buildInfoRow('支付方式', _getChannelName(widget.channel)),
            if (_order != null)
              _buildInfoRow('订单号', _order!.outTradeNo),
          ],
        ),
      ),
    );
  }

  /// 构建支付状态指示器
  Widget _buildPaymentStatus() {
    IconData icon;
    Color color;
    String text;

    switch (_currentStatus) {
      case 'PENDING':
        icon = Icons.schedule;
        color = Colors.orange;
        text = '等待支付';
        break;
      case 'SUCCESS':
        icon = Icons.check_circle;
        color = Colors.green;
        text = '支付成功';
        break;
      case 'FAILED':
        icon = Icons.error;
        color = Colors.red;
        text = '支付失败';
        break;
      case 'CANCELLED':
        icon = Icons.cancel;
        color = Colors.grey;
        text = '已取消';
        break;
      default:
        icon = Icons.help;
        color = Colors.grey;
        text = '未知状态';
    }

    return Card(
      elevation: 2,
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (_currentStatus == 'PENDING')
                  const Text(
                    '请在新窗口完成支付',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (_currentStatus == 'PENDING')
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建支付说明
  Widget _buildPaymentInstructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                '支付说明',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.channel == PayChannel.alipay
                ? '1. 点击下方按钮打开支付宝支付页面\n'
                    '2. 使用支付宝扫码或登录支付\n'
                    '3. 支付完成后本窗口将自动更新状态'
                : '1. 点击下方按钮打开微信支付页面\n'
                    '2. 使用微信扫描二维码支付\n'
                    '3. 支付完成后本窗口将自动更新状态',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 构建支付操作按钮
  Widget _buildPaymentActions() {
    if (_currentStatus == 'SUCCESS') {
      return ElevatedButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        icon: const Icon(Icons.check),
        label: const Text('完成'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          minimumSize: const Size(double.infinity, 48),
        ),
      );
    }

    if (_currentStatus != 'PENDING') {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _openPaymentUrl,
          icon: const Icon(Icons.open_in_new),
          label: const Text('打开支付页面'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _copyPaymentUrl,
          icon: const Icon(Icons.copy),
          label: const Text('复制支付链接'),
        ),
      ],
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取支付渠道名称
  String _getChannelName(PayChannel channel) {
    switch (channel) {
      case PayChannel.alipay:
        return '支付宝';
      case PayChannel.wechat:
        return '微信支付';
    }
  }
}

