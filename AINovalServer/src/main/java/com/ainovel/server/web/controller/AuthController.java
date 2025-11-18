package com.ainovel.server.web.controller;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ainovel.server.domain.model.User;
import com.ainovel.server.service.JwtService;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.UserService;
import com.ainovel.server.service.UserLoginLogService;
import com.ainovel.server.domain.model.UserLoginLog;
import com.ainovel.server.web.dto.AuthRequest;
import com.ainovel.server.web.dto.AuthResponse;
import com.ainovel.server.web.dto.ChangePasswordRequest;
import com.ainovel.server.web.dto.RefreshTokenRequest;
import com.ainovel.server.web.dto.UserRegistrationRequest;
import com.ainovel.server.web.dto.PhoneLoginRequest;
import com.ainovel.server.web.dto.EmailLoginRequest;
import com.ainovel.server.web.dto.SendVerificationCodeRequest;
import com.ainovel.server.service.VerificationCodeService;
import com.ainovel.server.common.exception.ValidationException;
import com.ainovel.server.web.dto.QuickRegistrationRequest;
import com.ainovel.server.common.response.ApiResponse;

import reactor.core.publisher.Mono;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.server.reactive.ServerHttpRequest;

/**
 * 认证控制器
 * 处理用户登录、注册和令牌刷新
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    
    private final UserService userService;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final VerificationCodeService verificationCodeService;
    private final CreditService creditService;
    private final UserLoginLogService loginLogService;
    
    // 注册功能开关
    @Value("${ainovel.registration.quick-enabled:true}")
    private boolean quickRegistrationEnabled;
    @Value("${ainovel.registration.email-enabled:false}")
    private boolean emailRegistrationEnabled;
    @Value("${ainovel.registration.phone-enabled:false}")
    private boolean phoneRegistrationEnabled;
    
    @Autowired
    public AuthController(UserService userService, PasswordEncoder passwordEncoder, 
                         JwtService jwtService, VerificationCodeService verificationCodeService,
                         CreditService creditService, UserLoginLogService loginLogService) {
        this.userService = userService;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.verificationCodeService = verificationCodeService;
        this.creditService = creditService;
        this.loginLogService = loginLogService;
    }
    
    /**
     * 从请求中提取IP地址
     */
    private String getClientIpAddress(ServerHttpRequest request) {
        String xForwardedFor = request.getHeaders().getFirst("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }
        
        String xRealIp = request.getHeaders().getFirst("X-Real-IP");
        if (xRealIp != null && !xRealIp.isEmpty()) {
            return xRealIp;
        }
        
        if (request.getRemoteAddress() != null) {
            return request.getRemoteAddress().getAddress().getHostAddress();
        }
        
        return "unknown";
    }
    
    /**
     * 从请求中提取User-Agent
     */
    private String getUserAgent(ServerHttpRequest request) {
        String userAgent = request.getHeaders().getFirst("User-Agent");
        return userAgent != null ? userAgent : "unknown";
    }
    
    /**
     * 用户登录
     * @param request 登录请求
     * @param httpRequest HTTP请求（用于提取IP和User-Agent）
     * @return 认证响应
     */
    @PostMapping("/login")
    public Mono<ResponseEntity<Object>> login(@RequestBody AuthRequest request, ServerHttpRequest httpRequest) {
        String ipAddress = getClientIpAddress(httpRequest);
        String userAgent = getUserAgent(httpRequest);
        
        return userService.findUserByUsername(request.getUsername())
                .filter(user -> passwordEncoder.matches(request.getPassword(), user.getPassword()))
                .flatMap(user -> {
                    String token = jwtService.generateToken(user);
                    String refreshToken = jwtService.generateRefreshToken(user);
                    
                    // 记录登录日志
                    return loginLogService.recordSuccessfulLogin(
                            user.getId(), 
                            user.getUsername(), 
                            UserLoginLog.LoginType.PASSWORD,
                            ipAddress,
                            userAgent
                    ).thenReturn(user)
                    .map(u -> {
                        AuthResponse response = new AuthResponse(
                                token,
                                refreshToken,
                                u.getId(),
                                u.getUsername(),
                                u.getDisplayName()
                        );
                        
                        // 成功：保持向后兼容，直接返回顶层字段
                        return ResponseEntity.ok((Object) response);
                    });
                })
                // 失败：返回带自定义消息的错误体，避免客户端误判为"登录过期"
                .switchIfEmpty(Mono.just(ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body((Object) ApiResponse.error("用户名或密码错误", "INVALID_CREDENTIALS"))));
    }
    
    /**
     * 手机号登录
     * @param request 手机号登录请求
     * @param httpRequest HTTP请求（用于提取IP和User-Agent）
     * @return 认证响应
     */
    @PostMapping("/login/phone")
    public Mono<ResponseEntity<Object>> phoneLogin(@Valid @RequestBody PhoneLoginRequest request, ServerHttpRequest httpRequest) {
        log.info("收到手机号登录请求，phone: {}", request.getPhone());
        
        String ipAddress = getClientIpAddress(httpRequest);
        String userAgent = getUserAgent(httpRequest);
        
        return verificationCodeService.verifyPhoneCode(request.getPhone(), request.getVerificationCode(), "login")
                .flatMap(verified -> {
                    if (!verified) {
                        log.warn("手机号登录验证码验证失败，phone: {}", request.getPhone());
                        return Mono.error(new ValidationException("验证码错误或已过期"));
                    }
                    log.info("手机验证码验证成功，查找用户，phone: {}", request.getPhone());
                    return userService.findUserByPhone(request.getPhone());
                })
                .switchIfEmpty(Mono.defer(() -> {
                    log.warn("手机号登录失败，手机号未注册，phone: {}", request.getPhone());
                    return Mono.error(new ValidationException("该手机号尚未注册"));
                }))
                .flatMap(user -> {
                    log.info("手机号登录成功，用户ID: {}, phone: {}", user.getId(), request.getPhone());
                    String token = jwtService.generateToken(user);
                    String refreshToken = jwtService.generateRefreshToken(user);
                    
                    // 记录登录日志
                    return loginLogService.recordSuccessfulLogin(
                            user.getId(), 
                            user.getUsername(), 
                            UserLoginLog.LoginType.PHONE,
                            ipAddress,
                            userAgent
                    ).thenReturn(user)
                    .map(u -> {
                        AuthResponse response = new AuthResponse(
                                token,
                                refreshToken,
                                u.getId(),
                                u.getUsername(),
                                u.getDisplayName()
                        );
                        
                        return ResponseEntity.ok((Object) response);
                    });
                })
                .onErrorResume(ValidationException.class, e -> {
                    log.error("手机号登录验证异常，phone: {}, 错误: {}", request.getPhone(), e.getMessage());
                    // 让全局异常处理器处理，提供标准的错误响应格式
                    return Mono.error(e);
                })
                .doOnError(throwable -> {
                    if (!(throwable instanceof ValidationException)) {
                        log.error("手机号登录过程中发生未预期异常，phone: {}, 异常类型: {}, 错误: {}", 
                                request.getPhone(), throwable.getClass().getSimpleName(), throwable.getMessage(), throwable);
                    }
                });
    }
    
    /**
     * 邮箱登录
     * @param request 邮箱登录请求
     * @param httpRequest HTTP请求（用于提取IP和User-Agent）
     * @return 认证响应
     */
    @PostMapping("/login/email")
    public Mono<ResponseEntity<Object>> emailLogin(@Valid @RequestBody EmailLoginRequest request, ServerHttpRequest httpRequest) {
        log.info("收到邮箱登录请求，email: {}", request.getEmail());
        
        String ipAddress = getClientIpAddress(httpRequest);
        String userAgent = getUserAgent(httpRequest);
        
        return verificationCodeService.verifyEmailCode(request.getEmail(), request.getVerificationCode(), "login")
                .flatMap(verified -> {
                    if (!verified) {
                        log.warn("邮箱登录验证码验证失败，email: {}", request.getEmail());
                        return Mono.error(new ValidationException("验证码错误或已过期"));
                    }
                    log.info("邮箱验证码验证成功，查找用户，email: {}", request.getEmail());
                    return userService.findUserByEmail(request.getEmail());
                })
                .switchIfEmpty(Mono.defer(() -> {
                    log.warn("邮箱登录失败，邮箱未注册，email: {}", request.getEmail());
                    return Mono.error(new ValidationException("该邮箱尚未注册"));
                }))
                .flatMap(user -> {
                    log.info("邮箱登录成功，用户ID: {}, email: {}", user.getId(), request.getEmail());
                    String token = jwtService.generateToken(user);
                    String refreshToken = jwtService.generateRefreshToken(user);
                    
                    // 记录登录日志
                    return loginLogService.recordSuccessfulLogin(
                            user.getId(), 
                            user.getUsername(), 
                            UserLoginLog.LoginType.EMAIL,
                            ipAddress,
                            userAgent
                    ).thenReturn(user)
                    .map(u -> {
                        AuthResponse response = new AuthResponse(
                                token,
                                refreshToken,
                                u.getId(),
                                u.getUsername(),
                                u.getDisplayName()
                        );
                        
                        return ResponseEntity.ok((Object) response);
                    });
                })
                .onErrorResume(ValidationException.class, e -> {
                    log.error("邮箱登录验证异常，email: {}, 错误: {}", request.getEmail(), e.getMessage());
                    // 让全局异常处理器处理，提供标准的错误响应格式
                    return Mono.error(e);
                })
                .doOnError(throwable -> {
                    if (!(throwable instanceof ValidationException)) {
                        log.error("邮箱登录过程中发生未预期异常，email: {}, 异常类型: {}, 错误: {}", 
                                request.getEmail(), throwable.getClass().getSimpleName(), throwable.getMessage(), throwable);
                    }
                });
    }
    
    /**
     * 发送验证码
     * @param request 发送验证码请求
     * @return 操作结果
     */
    @PostMapping("/verification-code")
    public Mono<ResponseEntity<Map<String, Object>>> sendVerificationCode(@Valid @RequestBody SendVerificationCodeRequest request) {
        log.info("收到验证码发送请求，type: {}, target: {}, purpose: {}", 
                request.getType(), request.getTarget(), request.getPurpose());
        
        // 开关：注册目的下的邮箱/手机验证码是否允许
        if ("register".equals(request.getPurpose())) {
            if ("email".equals(request.getType()) && !emailRegistrationEnabled) {
                return Mono.just(ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("message", "邮箱注册已关闭")));
            }
            if ("phone".equals(request.getType()) && !phoneRegistrationEnabled) {
                return Mono.just(ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("message", "手机注册已关闭")));
            }
        }
        
        // 如果是注册请求，必须验证图片验证码
        if ("register".equals(request.getPurpose())) {
            if (request.getCaptchaId() == null || request.getCaptchaId().trim().isEmpty()) {
                log.warn("注册请求缺少图片验证码ID");
                return Mono.just(ResponseEntity.badRequest()
                        .body(Map.of("message", "图片验证码ID不能为空")));
            }
            if (request.getCaptchaCode() == null || request.getCaptchaCode().trim().isEmpty()) {
                log.warn("注册请求缺少图片验证码内容");
                return Mono.just(ResponseEntity.badRequest()
                        .body(Map.of("message", "请输入图片验证码")));
            }
            
            log.info("验证注册请求的图片验证码，captchaId: {}, captchaCode: {}", 
                    request.getCaptchaId(), request.getCaptchaCode());
            
            // 验证图片验证码（不消费，避免后续注册时失效）
            return verificationCodeService.verifyCaptcha(request.getCaptchaId(), request.getCaptchaCode(), false)
                    .flatMap(valid -> {
                        if (!valid) {
                            log.warn("图片验证码验证失败，captchaId: {}, captchaCode: {}", 
                                    request.getCaptchaId(), request.getCaptchaCode());
                            return Mono.just(ResponseEntity.badRequest()
                                    .body(Map.of("message", "图片验证码错误或已过期")));
                        }
                        
                        log.info("图片验证码验证成功，继续处理验证码发送");
                        // 图片验证码验证通过，继续处理验证码发送
                        return processSendVerificationCode(request);
                    });
        } else {
            // 登录请求，不需要图片验证码
            log.info("登录请求，直接处理验证码发送");
            return processSendVerificationCode(request);
        }
    }
    
    /**
     * 处理验证码发送逻辑
     */
    private Mono<ResponseEntity<Map<String, Object>>> processSendVerificationCode(SendVerificationCodeRequest request) {
        log.info("开始处理验证码发送逻辑，type: {}, target: {}, purpose: {}", 
                request.getType(), request.getTarget(), request.getPurpose());
        Mono<Boolean> sendResult;
        
        if ("phone".equals(request.getType())) {
            log.info("检测到手机验证码发送请求");
            // 验证手机号格式
            if (!request.getTarget().matches("^1[3-9]\\d{9}$")) {
                return Mono.just(ResponseEntity.badRequest()
                        .body(Map.of("message", "手机号格式不正确")));
            }
            
            // 如果是注册，检查手机号是否已存在
            if ("register".equals(request.getPurpose())) {
                return userService.existsByPhone(request.getTarget())
                        .flatMap(exists -> {
                            if (exists) {
                                return Mono.just(ResponseEntity.badRequest()
                                        .body(Map.of("message", "该手机号已被注册")));
                            }
                            return verificationCodeService.sendPhoneVerificationCode(request.getTarget(), request.getPurpose())
                                    .map(success -> {
                                        if (success) {
                                            return ResponseEntity.ok(Map.of("message", "验证码已发送"));
                                        } else {
                                            return ResponseEntity.status(500)
                                                    .body(Map.of("message", "验证码发送失败，请稍后重试"));
                                        }
                                    });
                        });
            }
            
            sendResult = verificationCodeService.sendPhoneVerificationCode(request.getTarget(), request.getPurpose());
        } else {
            log.info("检测到邮箱验证码发送请求");
            // 验证邮箱格式
            if (!request.getTarget().matches("^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$")) {
                return Mono.just(ResponseEntity.badRequest()
                        .body(Map.of("message", "邮箱格式不正确")));
            }
            
            // 如果是注册，检查邮箱是否已存在
            if ("register".equals(request.getPurpose())) {
                return userService.existsByEmail(request.getTarget())
                        .flatMap(exists -> {
                            if (exists) {
                                return Mono.just(ResponseEntity.badRequest()
                                        .body(Map.of("message", "该邮箱已被注册")));
                            }
                            return verificationCodeService.sendEmailVerificationCode(request.getTarget(), request.getPurpose())
                                    .map(success -> {
                                        if (success) {
                                            return ResponseEntity.ok(Map.of("message", "验证码已发送"));
                                        } else {
                                            return ResponseEntity.status(500)
                                                    .body(Map.of("message", "验证码发送失败，请稍后重试"));
                                        }
                                    });
                        });
            }
            
            log.info("调用邮箱验证码发送服务，target: {}", request.getTarget());
            sendResult = verificationCodeService.sendEmailVerificationCode(request.getTarget(), request.getPurpose());
        }
        
        return sendResult.map(success -> {
            log.info("验证码发送结果: {}", success);
            if (success) {
                return ResponseEntity.ok(Map.of("message", "验证码已发送"));
            } else {
                return ResponseEntity.status(500)
                        .body(Map.of("message", "验证码发送失败，请稍后重试"));
            }
        });
    }
    
    /**
     * 获取图片验证码
     * @return 验证码信息
     */
    @PostMapping("/captcha")
    public Mono<ResponseEntity<Map<String, String>>> getCaptcha() {
        return verificationCodeService.generateCaptcha()
                .map(result -> ResponseEntity.ok(Map.of(
                        "captchaId", result.captchaId(),
                        "captchaImage", result.captchaImage()
                )));
    }
    
    /**
     * 用户注册
     * @param request 注册请求
     * @return 认证响应
     */
    @PostMapping("/register")
    public Mono<ResponseEntity<Object>> register(@Valid @RequestBody UserRegistrationRequest request) {
        log.info("收到用户注册请求，username: {}, email: {}, phone: {}", 
                request.getUsername(), request.getEmail(), request.getPhone());
        
        // 开关：邮箱/手机注册是否允许
        if (request.getEmail() != null && !request.getEmail().isEmpty() && !emailRegistrationEnabled) {
            return Mono.error(new ValidationException("邮箱注册已关闭"));
        }
        if (request.getPhone() != null && !request.getPhone().isEmpty() && !phoneRegistrationEnabled) {
            return Mono.error(new ValidationException("手机注册已关闭"));
        }
        
        // 首先验证图片验证码（消费，注册仅能使用一次）
        return verificationCodeService.verifyCaptcha(request.getCaptchaId(), request.getCaptchaCode(), true)
                .flatMap(captchaValid -> {
                    if (!captchaValid) {
                        log.warn("用户注册图片验证码验证失败，username: {}", request.getUsername());
                        return Mono.error(new ValidationException("图片验证码错误"));
                    }
                    
                    log.info("图片验证码验证成功，检查用户名唯一性，username: {}", request.getUsername());
                    // 检查用户名是否已存在
                    return userService.existsByUsername(request.getUsername());
                })
                .flatMap(usernameExists -> {
                    if (usernameExists) {
                        log.warn("用户注册失败，用户名已存在，username: {}", request.getUsername());
                        return Mono.error(new ValidationException("用户名已被注册"));
                    }
                    
                    // 检查邮箱是否已存在
                    if (request.getEmail() != null && !request.getEmail().isEmpty()) {
                        log.info("检查邮箱唯一性，email: {}", request.getEmail());
                        return userService.existsByEmail(request.getEmail());
                    }
                    return Mono.just(false);
                })
                .flatMap(emailExists -> {
                    if (emailExists) {
                        log.warn("用户注册失败，邮箱已存在，email: {}", request.getEmail());
                        return Mono.error(new ValidationException("邮箱已被注册"));
                    }
                    
                    // 检查手机号是否已存在
                    if (request.getPhone() != null && !request.getPhone().isEmpty()) {
                        log.info("检查手机号唯一性，phone: {}", request.getPhone());
                        return userService.existsByPhone(request.getPhone());
                    }
                    return Mono.just(false);
                })
                .flatMap(phoneExists -> {
                    if (phoneExists) {
                        log.warn("用户注册失败，手机号已存在，phone: {}", request.getPhone());
                        return Mono.error(new ValidationException("手机号已被注册"));
                    }
                    
                    // 验证邮箱验证码（如果提供了邮箱）
                    if (request.getEmail() != null && !request.getEmail().isEmpty() && 
                        request.getEmailVerificationCode() != null) {
                        log.info("验证邮箱验证码，email: {}, code: {}", request.getEmail(), request.getEmailVerificationCode());
                        return verificationCodeService.verifyEmailCode(
                                request.getEmail(), 
                                request.getEmailVerificationCode(), 
                                "register");
                    }
                    log.info("跳过邮箱验证码验证（未提供邮箱或验证码）");
                    return Mono.just(true);
                })
                .flatMap(emailVerified -> {
                    if (!emailVerified) {
                        log.warn("用户注册邮箱验证码验证失败，email: {}", request.getEmail());
                        return Mono.error(new ValidationException("邮箱验证码错误或已过期"));
                    }
                    
                    // 验证手机验证码（如果提供了手机号）
                    if (request.getPhone() != null && !request.getPhone().isEmpty() && 
                        request.getPhoneVerificationCode() != null) {
                        log.info("验证手机验证码，phone: {}, code: {}", request.getPhone(), request.getPhoneVerificationCode());
                        return verificationCodeService.verifyPhoneCode(
                                request.getPhone(), 
                                request.getPhoneVerificationCode(), 
                                "register");
                    }
                    log.info("跳过手机验证码验证（未提供手机号或验证码）");
                    return Mono.just(true);
                })
                .flatMap(phoneVerified -> {
                    if (!phoneVerified) {
                        log.warn("用户注册手机验证码验证失败，phone: {}", request.getPhone());
                        return Mono.error(new ValidationException("手机验证码错误或已过期"));
                    }
                    
                    log.info("所有验证通过，开始创建用户，username: {}", request.getUsername());
                    // 创建用户（密码统一在UserServiceImpl中进行加密）
                    User user = User.builder()
                            .username(request.getUsername())
                            .password(request.getPassword())
                            .email(request.getEmail())
                            .phone(request.getPhone())
                            .displayName(request.getDisplayName() != null ? 
                                    request.getDisplayName() : request.getUsername())
                            .emailVerified(request.getEmailVerificationCode() != null)
                            .phoneVerified(request.getPhoneVerificationCode() != null)
                            .build();
                    
                    return userService.createUser(user);
                })
                .flatMap(createdUser -> {
                    log.info("用户注册成功，用户ID: {}, username: {}，开始赠送新用户积分", createdUser.getId(), createdUser.getUsername());
                    return creditService.grantNewUserCredits(createdUser.getId())
                        .onErrorResume(err -> {
                            log.error("新用户赠送积分失败, userId: {}, err: {}", createdUser.getId(), err.getMessage());
                            return Mono.just(false);
                        })
                        .map(granted -> {
                            String token = jwtService.generateToken(createdUser);
                            String refreshToken = jwtService.generateRefreshToken(createdUser);
                            AuthResponse response = new AuthResponse(
                                    token,
                                    refreshToken,
                                    createdUser.getId(),
                                    createdUser.getUsername(),
                                    createdUser.getDisplayName()
                            );
                            return ResponseEntity.status(HttpStatus.CREATED).body((Object) response);
                        });
                })
                .onErrorResume(ValidationException.class, e -> {
                    log.error("用户注册验证异常，username: {}, 错误: {}", request.getUsername(), e.getMessage());
                    // 让全局异常处理器处理，提供标准的错误响应格式
                    return Mono.error(e);
                })
                .doOnError(throwable -> {
                    if (!(throwable instanceof ValidationException)) {
                        log.error("用户注册过程中发生未预期异常，username: {}, 异常类型: {}, 错误: {}", 
                                request.getUsername(), throwable.getClass().getSimpleName(), throwable.getMessage(), throwable);
                    }
                });
    }
    
    /**
     * 快捷注册（仅用户名+密码）
     */
    @PostMapping("/register/quick")
    public Mono<ResponseEntity<Object>> quickRegister(@Valid @RequestBody QuickRegistrationRequest request) {
        log.info("收到快捷注册请求，username: {}", request.getUsername());
        if (!quickRegistrationEnabled) {
            return Mono.error(new ValidationException("快捷注册已关闭"));
        }
        return userService.existsByUsername(request.getUsername())
            .flatMap(exists -> {
                if (exists) {
                    return Mono.error(new ValidationException("用户名已被注册"));
                }
                User user = User.builder()
                        .username(request.getUsername())
                        .password(request.getPassword())
                        .displayName(request.getDisplayName() != null ? request.getDisplayName() : request.getUsername())
                        .build();
                return userService.createUser(user);
            })
            .flatMap(createdUser -> creditService.grantNewUserCredits(createdUser.getId())
                .onErrorResume(err -> {
                    log.error("快捷注册赠送积分失败, userId: {}, err: {}", createdUser.getId(), err.getMessage());
                    return Mono.just(false);
                })
                .map(granted -> {
                    String token = jwtService.generateToken(createdUser);
                    String refreshToken = jwtService.generateRefreshToken(createdUser);
                    return ResponseEntity.status(HttpStatus.CREATED).body((Object) new AuthResponse(
                        token,
                        refreshToken,
                        createdUser.getId(),
                        createdUser.getUsername(),
                        createdUser.getDisplayName()
                    ));
                })
            )
            .onErrorResume(ValidationException.class, e -> Mono.error(e));
    }
    
    /**
     * 刷新令牌
     * @param request 刷新令牌请求
     * @return 认证响应
     */
    @PostMapping("/refresh")
    public Mono<ResponseEntity<Object>> refreshToken(@RequestBody RefreshTokenRequest request) {
        try {
            String username = jwtService.extractUsername(request.getRefreshToken());
            
            return userService.findUserByUsername(username)
                    .filter(user -> jwtService.validateToken(request.getRefreshToken(), user))
                    .map(user -> {
                        String newToken = jwtService.generateToken(user);
                        String newRefreshToken = jwtService.generateRefreshToken(user);
                        
                        AuthResponse response = new AuthResponse(
                                newToken,
                                newRefreshToken,
                                user.getId(),
                                user.getUsername(),
                                user.getDisplayName()
                        );
                        
                        return ResponseEntity.ok((Object) response);
                    })
                    .defaultIfEmpty(ResponseEntity.status(HttpStatus.UNAUTHORIZED).build());
        } catch (Exception e) {
            return Mono.just(ResponseEntity.status(HttpStatus.UNAUTHORIZED).build());
        }
    }
    
    /**
     * 修改密码
     * @param request 修改密码请求
     * @return 操作结果
     */
    @PostMapping("/change-password")
    public Mono<ResponseEntity<Void>> changePassword(@RequestBody ChangePasswordRequest request) {
        return userService.findUserByUsername(request.getUsername())
                .filter(user -> passwordEncoder.matches(request.getCurrentPassword(), user.getPassword()))
                .flatMap(user -> userService.updateUserPassword(user.getId(), passwordEncoder.encode(request.getNewPassword())))
                .map(updatedUser -> ResponseEntity.ok().<Void>build())
                .defaultIfEmpty(ResponseEntity.status(HttpStatus.UNAUTHORIZED).build());
    }
    
    /**
     * 用户登出
     * 虽然JWT是无状态的，但提供标准的logout接口用于：
     * 1. 记录用户登出日志
     * 2. 清理可能的服务器端会话数据  
     * 3. 为未来的token黑名单机制预留接口
     * @return 操作结果
     */
    @PostMapping("/logout")
    public Mono<ResponseEntity<Map<String, Object>>> logout() {
        // 在JWT无状态架构中，主要在客户端删除token
        // 这里主要用于记录登出日志和返回标准响应
        
        return Mono.just(ResponseEntity.ok(Map.of(
                "success", true,
                "message", "登出成功"
        )));
    }
} 