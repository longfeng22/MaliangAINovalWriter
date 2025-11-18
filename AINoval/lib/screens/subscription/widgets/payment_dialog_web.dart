// Web平台专用：打开支付宝HTML表单
import 'dart:html' as html;

/// 在新窗口打开支付宝HTML表单
void openPaymentFormInNewWindow(String htmlForm) {
  final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>支付宝支付</title>
</head>
<body>
    $htmlForm
    <script>
        // 自动提交表单
        document.forms[0].submit();
    </script>
</body>
</html>
''';
  
  // 创建Blob URL
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  
  // 在新窗口打开
  html.window.open(url, '_blank');
  
  // 清理Blob URL（延迟1秒后）
  Future.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  });
}

