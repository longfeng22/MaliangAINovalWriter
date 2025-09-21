import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:ainoval/blocs/auth/auth_bloc.dart';
import 'package:ainoval/models/app_registration_config.dart';

import 'package:ainoval/widgets/common/icp_record_footer.dart';

import 'package:flutter/material.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 增强版登录页面
/// 完整实现邮箱注册和手机验证码注册功能
class EnhancedLoginScreen extends StatefulWidget {
  const EnhancedLoginScreen({Key? key}) : super(key: key);

  @override
  State<EnhancedLoginScreen> createState() => _EnhancedLoginScreenState();
}

class _EnhancedLoginScreenState extends State<EnhancedLoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  final _captchaController = TextEditingController();

  bool _isLogin = true; // 是否为登录模式
  String _loginMethod = 'username'; // 登录方式: username, phone, email
  RegistrationMethod? _registrationMethod; // 注册方式: email, phone
  String? _captchaId;
  String? _captchaImage;
  bool _isCaptchaLoading = false;
  bool _isVerificationCodeSent = false;
  int _countdown = 0;
  bool _hasNetworkConnection = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RegistrationConfig? _registrationConfig;
  Timer? _countdownTimer;
  
  // 动画控制器
  late AnimationController _animationController;
  late AnimationController _textAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _rotationAnimation;
  
  // 动态文字列表
  final List<String> _dynamicTexts = [
    'AI驱动的智能创作平台',
    '释放您的创作无限可能',
    '与AI共同编织精彩故事',
    '开启全新的写作体验',
    '让创意在这里绽放',
  ];
  int _currentTextIndex = 0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadRegistrationConfig();
    _initNetworkListener();
    _startTextAnimation();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _verificationCodeController.dispose();
    _captchaController.dispose();
    _connectivitySubscription?.cancel();
    _countdownTimer?.cancel();
    _animationController.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }

  /// 初始化动画
  void _initAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));
    
    _animationController.forward();
  }
  
  /// 开始文字动画
  void _startTextAnimation() {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _currentTextIndex = (_currentTextIndex + 1) % _dynamicTexts.length;
        });
        _textAnimationController.reset();
        _textAnimationController.forward();
      } else {
        timer.cancel();
      }
    });
  }

  /// 加载注册配置
  Future<void> _loadRegistrationConfig() async {
    final config = RegistrationConfig(
      phoneRegistrationEnabled: await AppRegistrationConfig.isPhoneRegistrationEnabled(),
      emailRegistrationEnabled: await AppRegistrationConfig.isEmailRegistrationEnabled(),
      verificationRequired: await AppRegistrationConfig.isVerificationRequired(),
      quickRegistrationEnabled: await AppRegistrationConfig.isQuickRegistrationEnabled(),
    );
    
    setState(() {
      _registrationConfig = config;
      // 设置默认注册方式为第一个可用的方式
      if (config.availableMethods.isNotEmpty) {
        _registrationMethod = config.availableMethods.first;
      }
    });
  }

  /// 初始化网络连接监听
  void _initNetworkListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final isConnected = results.any((result) => result != ConnectivityResult.none);
        if (mounted) {
          setState(() {
            _hasNetworkConnection = isConnected;
          });
          if (!isConnected) {
            _showNetworkError();
          }
        }
      },
    );
  }

  /// 检查网络连接
  Future<bool> _checkNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 显示网络错误提示
  void _showNetworkError() {
    TopToast.warning(context, '网络连接已断开，请检查您的网络连接');
    // 提供简单的重试逻辑：连接恢复后给出提示
    () async {
      final isConnected = await _checkNetworkConnection();
      if (mounted) {
        setState(() {
          _hasNetworkConnection = isConnected;
        });
        if (isConnected) {
          TopToast.success(context, '网络连接已恢复');
        }
      }
    }();
  }

  /// 清理验证码相关状态
  void _clearVerificationCodeState() {
    // 停止倒计时定时器
    _countdownTimer?.cancel();
    
    // 重置验证码发送状态
    _isVerificationCodeSent = false;
    _countdown = 0;
    
    // 清空验证码输入框
    _verificationCodeController.clear();
    
    // 注意：不清空图片验证码相关状态，因为图片验证码在整个注册流程中应该保持一致
    // 只在模式切换或者用户主动刷新时才清空图片验证码
    
    //print('🧹 清理验证码状态: 定时器已停止，验证码输入框已清空');
  }

  /// 清理图片验证码状态（仅在必要时调用）
  void _clearCaptchaState() {
    _captchaController.clear();
    _captchaId = null;
    _captchaImage = null;
    _isCaptchaLoading = false;
    //print('🧹 清理图片验证码状态: 输入框已清空，验证码图片已重置');
  }

  /// 切换登录/注册模式
  void _toggleMode() {
    // 先清理验证码相关状态
    _clearVerificationCodeState();
    
    setState(() {
      _isLogin = !_isLogin;
      _loginMethod = 'username'; // 重置登录方式
      if (!_isLogin) {
        // 切换到注册模式：仅在非快捷注册时加载图片验证码
        _clearCaptchaState();
        if (!(_registrationConfig?.quickRegistrationEnabled ?? true)) {
          _loadCaptcha();
        }
        // 设置默认注册方式
        if (_registrationConfig != null && _registrationConfig!.availableMethods.isNotEmpty) {
          _registrationMethod = _registrationConfig!.availableMethods.first;
        }
      } else {
        // 切换到登录模式时，清理图片验证码状态
        _clearCaptchaState();
      }
    });
    _formKey.currentState?.reset(); // 重置表单验证状态
  }

  /// 加载图片验证码
  Future<void> _loadCaptcha() async {
    if (_isCaptchaLoading) return;
    setState(() {
      _isCaptchaLoading = true;
    });
    final authBloc = context.read<AuthBloc>();
    authBloc.add(LoadCaptcha());
  }

  /// 发送验证码
  Future<void> _sendVerificationCode() async {
    // 快捷注册不发送验证码
    if (!_isLogin && (_registrationConfig?.quickRegistrationEnabled ?? true)) {
      return;
    }

    // 检查是否在冷却时间内
    if (_isVerificationCodeSent) {
      _showError('请等待${_countdown}秒后再次发送');
      return;
    }
    
    final authBloc = context.read<AuthBloc>();
    
    String type = '';
    String target = '';
    
    if (_isLogin) {
      // 登录时的验证码发送（不需要图片验证码）
      if (_loginMethod == 'phone') {
        type = 'phone';
        target = _phoneController.text.trim();
        if (target.isEmpty) {
          _showError('请输入手机号');
          return;
        }
        if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(target)) {
          _showError('请输入正确的手机号格式');
          return;
        }
      } else if (_loginMethod == 'email') {
        type = 'email';
        target = _emailController.text.trim();
        if (target.isEmpty) {
          _showError('请输入邮箱地址');
          return;
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(target)) {
          _showError('请输入正确的邮箱地址格式');
          return;
        }
      }
      
      if (type.isNotEmpty && target.isNotEmpty) {
        //print('📨 发送登录验证码: $type -> $target');
        authBloc.add(SendVerificationCode(
          type: type,
          target: target,
          purpose: 'login',
        ));
        
        // 先开始倒计时，如果发送失败会在listener中处理
        _startCountdown();
      }
    } else {
      // 注册时的验证码发送（需要先验证图片验证码）
      if (_registrationMethod == RegistrationMethod.email) {
        type = 'email';
        target = _emailController.text.trim();
        if (target.isEmpty) {
          _showError('请输入邮箱地址');
          return;
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(target)) {
          _showError('请输入正确的邮箱地址格式');
          return;
        }
      } else if (_registrationMethod == RegistrationMethod.phone) {
        type = 'phone';
        target = _phoneController.text.trim();
        if (target.isEmpty) {
          _showError('请输入手机号');
          return;
        }
        if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(target)) {
          _showError('请输入正确的手机号格式');
          return;
        }
      }
      
      // 注册时需要先验证图片验证码
      if (type.isNotEmpty && target.isNotEmpty) {
        if (_captchaId == null || _captchaId!.isEmpty) {
          _showError('请先加载图片验证码');
          _loadCaptcha();
          return;
        }
        
        if (_captchaController.text.trim().isEmpty) {
          _showError('请输入图片验证码');
          return;
        }
        
        if (_captchaController.text.trim().length != 4) {
          _showError('图片验证码必须为4位');
          return;
        }
        
        //print('📨 发送注册验证码: $type -> $target (图片验证码ID: $_captchaId)');
        authBloc.add(SendVerificationCodeWithCaptcha(
          type: type,
          target: target,
          purpose: 'register',
          captchaId: _captchaId!,
          captchaCode: _captchaController.text.trim(),
        ));
        
        // 先开始倒计时，如果发送失败会在listener中处理
        _startCountdown();
      }
    }
  }

  /// 开始倒计时
  void _startCountdown() {
    if (mounted) {
      setState(() {
        _isVerificationCodeSent = true;
        _countdown = 60; // 60秒倒计时，与后端频率限制保持一致
      });
    }
    
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isVerificationCodeSent = false;
          });
        }
      }
    });
  }

  /// 处理验证码发送错误
  void _handleVerificationCodeError(String errorMessage) {
    // 如果是验证码相关错误，停止倒计时
    if (errorMessage.contains('验证码') && _isVerificationCodeSent) {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() {
          _isVerificationCodeSent = false;
          _countdown = 0;
        });
      }
    }
  }

  // 已废弃：现在直接展示后端返回的错误信息

  /// 格式化倒计时显示
  String _formatCountdown(int seconds) {
    if (seconds <= 0) return '发送验证码';
    
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    
    if (minutes > 0) {
      return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${seconds}秒';
    }
  }

  /// 显示错误消息
  void _showError(String message) {
    TopToast.error(context, message);
  }

  /// 提交表单
  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 检查网络连接
    if (!_hasNetworkConnection) {
      final isConnected = await _checkNetworkConnection();
      if (!isConnected) {
        _showError('请检查您的网络连接后再试');
        return;
      } else {
        setState(() {
          _hasNetworkConnection = true;
        });
      }
    }

    final authBloc = context.read<AuthBloc>();

    if (_isLogin) {
      // 登录逻辑保持不变
      if (_loginMethod == 'email') {
        if (_emailController.text.trim().isEmpty) {
          _showError('请输入邮箱地址');
          return;
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text.trim())) {
          _showError('请输入有效的邮箱地址');
          return;
        }
        if (_verificationCodeController.text.trim().isEmpty) {
          _showError('请输入验证码');
          return;
        }
        if (_verificationCodeController.text.trim().length != 6) {
          _showError('验证码应为6位数字');
          return;
        }
        if (!RegExp(r'^\d{6}$').hasMatch(_verificationCodeController.text.trim())) {
          _showError('验证码只能包含数字');
          return;
        }
      } else if (_loginMethod == 'phone') {
        if (_phoneController.text.trim().isEmpty) {
          _showError('请输入手机号码');
          return;
        }
        if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phoneController.text.trim())) {
          _showError('请输入正确的手机号格式');
          return;
        }
        if (_verificationCodeController.text.trim().isEmpty) {
          _showError('请输入验证码');
          return;
        }
        if (_verificationCodeController.text.trim().length != 6) {
          _showError('验证码应为6位数字');
          return;
        }
        if (!RegExp(r'^\d{6}$').hasMatch(_verificationCodeController.text.trim())) {
          _showError('验证码只能包含数字');
          return;
        }
      } else {
        if (_usernameController.text.trim().isEmpty) {
          _showError('请输入用户名');
          return;
        }
        if (_passwordController.text.isEmpty) {
          _showError('请输入密码');
          return;
        }
      }

      // 根据登录方式发送不同的登录事件
      switch (_loginMethod) {
        case 'phone':
          //print('📱 发起手机号登录: ${_phoneController.text.trim()}');
          authBloc.add(PhoneLogin(
            phone: _phoneController.text.trim(),
            verificationCode: _verificationCodeController.text.trim(),
          ));
          break;
        case 'email':
          //print('📧 发起邮箱登录: ${_emailController.text.trim()}');
          authBloc.add(EmailLogin(
            email: _emailController.text.trim(),
            verificationCode: _verificationCodeController.text.trim(),
          ));
          break;
        default:
          //print('👤 发起用户名登录: ${_usernameController.text.trim()}');
          authBloc.add(AuthLogin(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          ));
      }
    } else {
      // 注册逻辑：快捷注册仅需用户名+密码
      final bool quick = _registrationConfig?.quickRegistrationEnabled ?? true;
      if (quick) {
        if (_usernameController.text.trim().isEmpty) {
          _showError('请输入用户名');
          return;
        }
        if (_passwordController.text.isEmpty) {
          _showError('请输入密码');
          return;
        }
        //print('⚡ 发起快捷注册: 用户名=${_usernameController.text.trim()}');
        authBloc.add(AuthRegister(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          email: null,
          phone: null,
          displayName: _usernameController.text.trim(),
          captchaId: null,
          captchaCode: null,
          emailVerificationCode: null,
          phoneVerificationCode: null,
        ));
      } else {
        // 旧流程（邮箱/手机 + 验证码 + 图片验证码）
        String? email;
        String? phone;
        String? emailVerificationCode;
        String? phoneVerificationCode;
        
        if (_registrationMethod == RegistrationMethod.email) {
          email = _emailController.text.trim();
          emailVerificationCode = _verificationCodeController.text.trim();
        } else if (_registrationMethod == RegistrationMethod.phone) {
          phone = _phoneController.text.trim();
          phoneVerificationCode = _verificationCodeController.text.trim();
        }
        
        //print('📝 发起注册: 用户名=${_usernameController.text.trim()}, 邮箱=$email, 手机=$phone');
        authBloc.add(AuthRegister(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          email: email,
          phone: phone,
          displayName: _usernameController.text.trim(),
          captchaId: _captchaId,
          captchaCode: _captchaController.text.trim(),
          emailVerificationCode: emailVerificationCode,
          phoneVerificationCode: phoneVerificationCode,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1024;
    final isTablet = size.width > 768 && size.width <= 1024;

    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated || curr is AuthUnauthenticated ||
            curr.runtimeType.toString() == 'VerificationCodeSent' ||
            curr is AuthError || curr is AuthLoading || curr is CaptchaLoaded,
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            if (mounted) {
              // 先关闭登录Dialog
              Navigator.of(context).pop();
              // 然后触发主页面刷新（通过返回成功状态）
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop(true);
              }
            }
          } else if (state is AuthUnauthenticated) {
            if (mounted) {
              _clearVerificationCodeState();
              _clearCaptchaState();
            }
          } else if (state is AuthError) {
            if (mounted && state.message.isNotEmpty) {
              _handleVerificationCodeError(state.message);
              if (state.message.contains('图片验证码')) {
                _captchaController.clear();
              }
              // 直接展示后端返回的错误信息
              TopToast.error(context, state.message);
            }
            if (mounted) {
              setState(() {
                _isCaptchaLoading = false;
              });
            }
          } else if (state is CaptchaLoaded) {
            if (mounted) {
              setState(() {
                _captchaId = state.captchaId;
                _captchaImage = state.captchaImage;
                _isCaptchaLoading = false;
              });
            }
          } else if (state.runtimeType.toString() == 'VerificationCodeSent') {
            if (mounted) {
              TopToast.success(context, '验证码已发送，请查收');
            }
          }
        },
        buildWhen: (previous, current) {
          if (current is AuthAuthenticated || current is AuthUnauthenticated) {
            return true;
          }
          return false;
        },
        builder: (context, state) {
          final bool isLoading = state is AuthLoading;
          final String? errorMessage = state is AuthError ? state.message : null;
          
          if (state is CaptchaLoaded) {
            _captchaId = state.captchaId;
            _captchaImage = state.captchaImage;
            _isCaptchaLoading = false;
          }

          if (isDesktop) {
            return _buildDesktopLayout(theme, isDarkMode, isLoading, errorMessage);
          } else if (isTablet) {
            return _buildTabletLayout(theme, isDarkMode, isLoading, errorMessage);
          } else {
            return _buildMobileLayout(theme, isDarkMode, isLoading, errorMessage);
          }
        },
      ),
    );
  }

  /// 构建桌面端布局（左右分栏）
  Widget _buildDesktopLayout(ThemeData theme, bool isDarkMode, bool isLoading, String? errorMessage) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildLeftPanel(theme, isDarkMode),
            ),
            Expanded(
              flex: 2,
              child: _buildRightPanel(theme, isDarkMode, isLoading, errorMessage),
            ),
          ],
        ),
        _buildTopButtons(),
      ],
    );
  }

  /// 构建平板端布局
  Widget _buildTabletLayout(ThemeData theme, bool isDarkMode, bool isLoading, String? errorMessage) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildLeftPanel(theme, isDarkMode, isCompact: true),
            ),
            Expanded(
              flex: 3,
              child: _buildRightPanel(theme, isDarkMode, isLoading, errorMessage),
            ),
          ],
        ),
        _buildTopButtons(),
      ],
    );
  }

  /// 构建移动端布局（堆叠布局）
  Widget _buildMobileLayout(ThemeData theme, bool isDarkMode, bool isLoading, String? errorMessage) {
    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              child: _buildMobileHeader(theme, isDarkMode),
            ),
            Expanded(
              child: _buildRightPanel(theme, isDarkMode, isLoading, errorMessage, isMobile: true),
            ),
          ],
        ),
        _buildTopButtons(),
      ],
    );
  }

  /// 构建左侧面板
  Widget _buildLeftPanel(ThemeData theme, bool isDarkMode, {bool isCompact = false}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  const Color(0xFF1e3c72),
                  const Color(0xFF8e44ad),
                  const Color(0xFFe74c3c),
                  const Color(0xFFf39c12),
                  const Color(0xFF3498db),
                ]
              : [
                  const Color(0xFF3498db),
                  const Color(0xFF9b59b6),  
                  const Color(0xFFe74c3c),
                  const Color(0xFFf1c40f),
                  const Color(0xFF2980b9),
                ],
        ),
      ),
      child: Stack(
        children: [
          ..._buildGeometricShapes(isDarkMode),
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 32.0 : 48.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildBrandSection(theme, isCompact),
                      SizedBox(height: isCompact ? 24 : 48),
                      _buildDynamicText(theme, isCompact),
                      SizedBox(height: isCompact ? 16 : 24),
                      if (!isCompact) _buildFeaturesList(theme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建右侧面板
  Widget _buildRightPanel(ThemeData theme, bool isDarkMode, bool isLoading, String? errorMessage, {bool isMobile = false}) {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 24.0 : 48.0),
          child: Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 400),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isMobile) ...[
                    Text(
                      _isLogin ? '欢迎回来' : '开始创作',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? '登录到您的创作平台' : '加入AINoval开始您的创作之旅',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.card_giftcard,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '测试阶段福利：注册即送200积分',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],

                  if (errorMessage != null) ...[
                    _buildErrorContainer(theme, errorMessage),
                    const SizedBox(height: 24),
                  ],

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_isLogin)
                          _buildModernLoginForm(theme, isDarkMode)
                        else if (_registrationConfig != null)
                          _buildModernRegistrationForm(theme, isDarkMode)
                        else
                          _buildLoadingIndicator(),

                        const SizedBox(height: 32),
                        _buildModernSubmitButton(theme, isLoading),
                        const SizedBox(height: 24),
                        _buildModeToggleButton(theme, isLoading),
                        const SizedBox(height: 32),
                        ICPRecordText(
                          textStyle: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopButtons() {
    return const SizedBox.shrink();
  }

  List<Widget> _buildGeometricShapes(bool isDarkMode) {
    return [
      Positioned(
        top: 100,
        right: 80,
        child: RotationTransition(
          turns: _rotationAnimation,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 2,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 150,
        left: 60,
        child: Transform.rotate(
          angle: 0.3,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      Positioned(
        top: 300,
        left: 40,
        child: ClipPath(
          clipper: TriangleClipper(),
          child: Container(
            width: 30,
            height: 30,
            color: Colors.white.withOpacity(0.12),
          ),
        ),
      ),
    ];
  }

  Widget _buildBrandSection(ThemeData theme, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isCompact ? 48 : 64,
              height: isCompact ? 48 : 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: isCompact ? 24 : 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'AINoval',
              style: TextStyle(
                fontSize: isCompact ? 32 : 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        SizedBox(height: isCompact ? 8 : 16),
        Center(
          child: Text(
            'AI赋能的小说创作平台',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 16 : 20,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w300,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicText(ThemeData theme, bool isCompact) {
    return AnimatedBuilder(
      animation: _textAnimationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: _textAnimationController,
            curve: Curves.easeInOut,
          )),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _textAnimationController,
              curve: Curves.easeOut,
            )),
            child: Center(
              child: Text(
                _dynamicTexts[_currentTextIndex],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isCompact ? 18 : 24,
                  color: Colors.white.withOpacity(0.95),
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturesList(ThemeData theme) {
    final features = [
      {'icon': Icons.psychology, 'text': '丰富的AI写作功能'},
      {'icon': Icons.library_books, 'text': '自定义接入大模型和定制提示词'},
      {'icon': Icons.group, 'text': '丰富的模版和预设库'},
      {'icon': Icons.timeline, 'text': '设定生成与管理与创作辅助'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                ),
                child: Icon(
                  feature['icon'] as IconData,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                feature['text'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMobileHeader(ThemeData theme, bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  const Color(0xFF1e3c72),
                  const Color(0xFF8e44ad),
                  const Color(0xFFe74c3c),
                  const Color(0xFFf39c12),
                ]
              : [
                  const Color(0xFF3498db),
                  const Color(0xFF9b59b6),  
                  const Color(0xFFe74c3c),
                  const Color(0xFFf1c40f),
                ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 30,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'AINoval',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI赋能的小说创作平台',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorContainer(ThemeData theme, String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernLoginForm(ThemeData theme, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildModernLoginMethodSelector(theme, isDarkMode),
        const SizedBox(height: 24),

        if (_loginMethod == 'username') ...[
          _buildModernTextField(
            controller: _usernameController,
            label: '用户名',
            icon: Icons.person_outline,
            theme: theme,
            isDarkMode: isDarkMode,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入用户名';
              }
              if (value.length < 3 || value.length > 20) {
                return '用户名长度必须在3-20个字符之间';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                return '用户名只能包含字母、数字和下划线';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildModernTextField(
            controller: _passwordController,
            label: '密码',
            icon: Icons.lock_outline,
            theme: theme,
            isDarkMode: isDarkMode,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              if (value.length < 6) {
                return '密码长度至少为6位';
              }
              return null;
            },
          ),
        ] else if (_loginMethod == 'email') ...[
          _buildModernTextField(
            controller: _emailController,
            label: '邮箱地址',
            icon: Icons.email_outlined,
            theme: theme,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入邮箱地址';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return '请输入有效的邮箱地址';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildModernVerificationCodeRow(theme, isDarkMode),
        ] else if (_loginMethod == 'phone') ...[
          _buildModernTextField(
            controller: _phoneController,
            label: '手机号码',
            icon: Icons.phone_outlined,
            theme: theme,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入手机号码';
              }
              if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(value)) {
                return '请输入正确的手机号';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildModernVerificationCodeRow(theme, isDarkMode),
        ],
      ],
    );
  }

  Widget _buildModernRegistrationForm(ThemeData theme, bool isDarkMode) {
    // 快捷注册：仅展示用户名+密码
    final bool quick = _registrationConfig?.quickRegistrationEnabled ?? true;
    if (quick) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModernTextField(
            controller: _usernameController,
            label: '用户名',
            icon: Icons.person_outline,
            theme: theme,
            isDarkMode: isDarkMode,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入用户名';
              }
              if (value.length < 3 || value.length > 20) {
                return '用户名长度必须在3-20个字符之间';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                return '用户名只能包含字母、数字和下划线';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildModernTextField(
            controller: _passwordController,
            label: '密码',
            icon: Icons.lock_outline,
            theme: theme,
            isDarkMode: isDarkMode,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              if (value.length < 6) {
                return '密码长度至少为6位';
              }
              return null;
            },
          ),
        ],
      );
    }

    if (_registrationConfig != null && !_registrationConfig!.hasAvailableMethod) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '暂时无法注册新账户，请联系管理员',
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_registrationConfig!.availableMethods.length > 1) ...[
          _buildModernRegistrationMethodSelector(theme, isDarkMode),
          const SizedBox(height: 24),
        ],
        _buildModernTextField(
          controller: _usernameController,
          label: '用户名',
          icon: Icons.person_outline,
          theme: theme,
          isDarkMode: isDarkMode,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入用户名';
            }
            if (value.length < 3 || value.length > 20) {
              return '用户名长度必须在3-20个字符之间';
            }
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
              return '用户名只能包含字母、数字和下划线';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildModernTextField(
          controller: _passwordController,
          label: '密码',
          icon: Icons.lock_outline,
          theme: theme,
          isDarkMode: isDarkMode,
          obscureText: true,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入密码';
            }
            if (value.length < 6) {
              return '密码长度至少为6位';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        if (_registrationMethod == RegistrationMethod.email) ...[
          _buildModernTextField(
            controller: _emailController,
            label: '邮箱地址',
            icon: Icons.email_outlined,
            theme: theme,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入邮箱地址';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return '请输入有效的邮箱地址';
              }
              return null;
            },
          ),
        ] else if (_registrationMethod == RegistrationMethod.phone) ...[
          _buildModernTextField(
            controller: _phoneController,
            label: '手机号码',
            icon: Icons.phone_outlined,
            theme: theme,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入手机号码';
              }
              if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(value)) {
                return '请输入正确的手机号';
              }
              return null;
            },
          ),
        ],
        const SizedBox(height: 20),
        _buildModernVerificationCodeRow(theme, isDarkMode),
        const SizedBox(height: 20),
        _buildModernCaptchaRow(theme, isDarkMode),
      ],
    );
  }

  Widget _buildModernLoginMethodSelector(ThemeData theme, bool isDarkMode) {
    final methods = [
      {'key': 'username', 'label': '用户名', 'icon': Icons.person_outline},
      {'key': 'email', 'label': '邮箱', 'icon': Icons.email_outlined},
      if (_registrationConfig?.phoneRegistrationEnabled == true)
        {'key': 'phone', 'label': '手机号', 'icon': Icons.phone_outlined},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: methods.map((method) {
          final isSelected = _loginMethod == method['key'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_loginMethod != method['key'] as String) {
                  _clearVerificationCodeState();
                }
                setState(() {
                  _loginMethod = method['key'] as String;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      method['icon'] as IconData,
                      size: 18,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      method['label'] as String,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModernRegistrationMethodSelector(ThemeData theme, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: _registrationConfig!.availableMethods.map((method) {
          final isSelected = _registrationMethod == method;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_registrationMethod != method) {
                  _clearVerificationCodeState();
                }
                setState(() {
                  _registrationMethod = method;
                  if (method == RegistrationMethod.email) {
                    _phoneController.clear();
                  } else if (method == RegistrationMethod.phone) {
                    _emailController.clear();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  method.displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ThemeData theme,
    required bool isDarkMode,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.error,
              width: 1,
            ),
          ),
          filled: true,
          fillColor: isDarkMode ? Colors.grey[850] : Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildModernVerificationCodeRow(ThemeData theme, bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildModernTextField(
            controller: _verificationCodeController,
            label: '验证码',
            icon: Icons.verified_user_outlined,
            theme: theme,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入验证码';
              }
              if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                return '验证码为6位数字';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 16),
        Container(
          height: 56,
          constraints: const BoxConstraints(minWidth: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isVerificationCodeSent ? null : _sendVerificationCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isVerificationCodeSent
                  ? theme.colorScheme.outline.withOpacity(0.3)
                  : theme.colorScheme.primary,
              foregroundColor: _isVerificationCodeSent
                  ? theme.colorScheme.onSurface.withOpacity(0.5)
                  : theme.colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              _isVerificationCodeSent ? _formatCountdown(_countdown) : '发送验证码',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernCaptchaRow(ThemeData theme, bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildModernTextField(
            controller: _captchaController,
            label: '图片验证码',
            icon: Icons.security,
            theme: theme,
            isDarkMode: isDarkMode,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入验证码';
              }
              if (value.length != 4) {
                return '验证码长度为4位';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 120,
          height: 56,
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: _loadCaptcha,
            borderRadius: BorderRadius.circular(12),
            child: _isCaptchaLoading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_captchaImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          Uri.parse(_captchaImage!).data!.contentAsBytes(),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.refresh,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击加载',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      )),
          ),
        ),
      ],
    );
  }

  Widget _buildModernSubmitButton(ThemeData theme, bool isLoading) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _hasNetworkConnection
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withOpacity(0.8),
                ],
              )
            : null,
        color: !_hasNetworkConnection ? theme.colorScheme.outline : null,
        boxShadow: _hasNetworkConnection
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: _hasNetworkConnection
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface.withOpacity(0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_hasNetworkConnection) ...[
                    const Icon(Icons.wifi_off, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    !_hasNetworkConnection
                        ? '网络断开'
                        : (_isLogin ? '登录' : '注册'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildModeToggleButton(ThemeData theme, bool isLoading) {
    return TextButton(
      onPressed: isLoading ? null : _toggleMode,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        _isLogin ? '还没有账户？立即注册' : '已有账户？前往登录',
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
