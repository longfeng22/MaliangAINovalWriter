// 非Web平台的存根实现
/// 在新窗口打开支付宝HTML表单（存根）
void openPaymentFormInNewWindow(String htmlForm) {
  // 非Web平台不支持，实际逻辑在payment_dialog.dart中处理
  throw UnimplementedError('openPaymentFormInNewWindow is only supported on web');
}

