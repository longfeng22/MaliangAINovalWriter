package com.ainovel.server.web.controller;

import com.ainovel.server.domain.model.PaymentOrder;
import com.ainovel.server.domain.model.PaymentOrder.PayChannel;
import com.ainovel.server.service.payment.AlipayService;
import com.ainovel.server.service.payment.PaymentOrderService;
import com.ainovel.server.web.dto.ApiResponse;
import com.ainovel.server.web.dto.CreatePaymentRequest;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import com.ainovel.server.security.CurrentUser;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;
import java.util.HashMap;
import java.util.Map;

/**
 * 支付控制器
 * 处理订阅计划和积分包的支付相关请求
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/payments")
@RequiredArgsConstructor
@Tag(name = "支付管理", description = "支付相关API")
public class PaymentController {

    private final PaymentOrderService paymentOrderService;
    private final AlipayService alipayService;

    /**
     * 创建订阅计划支付订单
     */
    @PostMapping("/subscription/create")
    @Operation(summary = "创建订阅计划支付订单", description = "创建订阅计划支付订单并返回支付URL")
    public Mono<ApiResponse<Map<String, Object>>> createSubscriptionPayment(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreatePaymentRequest request) {
        
        String userId = currentUser.getId();
        log.info("📝 创建订阅支付订单: userId={}, planId={}, channel={}", 
                userId, request.getPlanId(), request.getChannel());

        return paymentOrderService.createSubscriptionOrder(
                userId,
                request.getPlanId(),
                PayChannel.valueOf(request.getChannel()),
                request.getReturnUrl()
        ).map(order -> {
            Map<String, Object> data = new HashMap<>();
            data.put("orderId", order.getId());
            data.put("outTradeNo", order.getOutTradeNo());
            data.put("amount", order.getAmount());
            data.put("currency", order.getCurrency());
            data.put("paymentUrl", order.getPaymentUrl());
            data.put("expireAt", order.getExpireAt());
            
            return ApiResponse.success(data);
        }).onErrorResume(e -> {
            log.error("❌ 创建订阅支付订单失败", e);
            return Mono.just(ApiResponse.error(e.getMessage()));
        });
    }

    /**
     * 创建积分包支付订单
     */
    @PostMapping("/credit-pack/create")
    @Operation(summary = "创建积分包支付订单", description = "创建积分包支付订单并返回支付URL")
    public Mono<ApiResponse<Map<String, Object>>> createCreditPackPayment(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreatePaymentRequest request) {
        
        String userId = currentUser.getId();
        log.info("📝 创建积分包支付订单: userId={}, creditPackId={}, channel={}", 
                userId, request.getPlanId(), request.getChannel());

        return paymentOrderService.createCreditPackOrder(
                userId,
                request.getPlanId(),
                PayChannel.valueOf(request.getChannel()),
                request.getReturnUrl()
        ).map(order -> {
            Map<String, Object> data = new HashMap<>();
            data.put("orderId", order.getId());
            data.put("outTradeNo", order.getOutTradeNo());
            data.put("amount", order.getAmount());
            data.put("currency", order.getCurrency());
            data.put("paymentUrl", order.getPaymentUrl());
            data.put("expireAt", order.getExpireAt());
            
            return ApiResponse.success(data);
        }).onErrorResume(e -> {
            log.error("❌ 创建积分包支付订单失败", e);
            return Mono.just(ApiResponse.error(e.getMessage()));
        });
    }

    /**
     * 查询订单状态
     */
    @GetMapping("/order/{outTradeNo}")
    @Operation(summary = "查询订单状态", description = "根据商户订单号查询订单状态")
    public Mono<ApiResponse<PaymentOrder>> getOrderStatus(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String outTradeNo) {
        
        String userId = currentUser.getId();
        log.info("🔍 查询订单状态: userId={}, outTradeNo={}", userId, outTradeNo);

        return paymentOrderService.getOrderByOutTradeNo(outTradeNo)
                .flatMap(order -> {
                    // 验证订单所有者
                    if (!order.getUserId().equals(userId)) {
                        return Mono.just(ApiResponse.<PaymentOrder>error("无权访问该订单"));
                    }
                    return Mono.just(ApiResponse.success(order));
                })
                .switchIfEmpty(Mono.just(ApiResponse.error("订单不存在")));
    }

    /**
     * 同步订单状态（从支付宝查询最新状态）
     */
    @PostMapping("/order/{outTradeNo}/sync")
    @Operation(summary = "同步订单状态", description = "从支付渠道同步订单最新状态")
    public Mono<ApiResponse<PaymentOrder>> syncOrderStatus(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String outTradeNo) {
        
        String userId = currentUser.getId();
        log.info("🔄 同步订单状态: userId={}, outTradeNo={}", userId, outTradeNo);

        return paymentOrderService.getOrderByOutTradeNo(outTradeNo)
                .flatMap(order -> {
                    // 验证订单所有者
                    if (!order.getUserId().equals(userId)) {
                        return Mono.just(ApiResponse.<PaymentOrder>error("无权访问该订单"));
                    }
                    
                    return paymentOrderService.syncOrderStatus(outTradeNo)
                            .map(ApiResponse::success);
                })
                .switchIfEmpty(Mono.just(ApiResponse.error("订单不存在")))
                .onErrorResume(e -> {
                    log.error("❌ 同步订单状态失败", e);
                    return Mono.just(ApiResponse.error(e.getMessage()));
                });
    }

    /**
     * 查询用户所有订单
     */
    @GetMapping("/orders")
    @Operation(summary = "查询用户所有订单", description = "查询当前用户的所有支付订单")
    public Mono<ApiResponse<java.util.List<PaymentOrder>>> getUserOrders(
            @AuthenticationPrincipal CurrentUser currentUser) {
        
        String userId = currentUser.getId();
        log.info("📋 查询用户订单: userId={}", userId);

        return paymentOrderService.getUserOrders(userId)
                .collectList()
                .map(ApiResponse::success);
    }

    /**
     * 支付宝异步通知回调
     */
    @PostMapping(value = "/notify/ALIPAY", produces = MediaType.TEXT_PLAIN_VALUE)
    @Operation(summary = "支付宝异步通知", description = "接收支付宝的异步通知回调")
    public Mono<String> alipayNotify(@RequestParam Map<String, String> params) {
        log.info("📣 收到支付宝异步通知: {}", params);

        return alipayService.verifyNotify(params)
                .flatMap(verified -> {
                    if (!verified) {
                        log.warn("⚠️ 支付宝通知签名验证失败");
                        return Mono.just("fail");
                    }

                    String outTradeNo = params.get("out_trade_no");
                    String tradeNo = params.get("trade_no");
                    String tradeStatus = params.get("trade_status");

                    log.info("✅ 支付宝通知验证成功: outTradeNo={}, tradeNo={}, status={}", 
                            outTradeNo, tradeNo, tradeStatus);

                    if ("TRADE_SUCCESS".equals(tradeStatus) || "TRADE_FINISHED".equals(tradeStatus)) {
                        // 标记订单为已支付
                        return paymentOrderService.markOrderPaid(outTradeNo, tradeNo)
                                .flatMap(order -> {
                                    // 处理支付成功业务逻辑
                                    return paymentOrderService.handlePaymentSuccess(outTradeNo)
                                            .thenReturn("success");
                                })
                                .onErrorResume(e -> {
                                    log.error("❌ 处理支付宝通知失败", e);
                                    return Mono.just("fail");
                                });
                    } else if ("TRADE_CLOSED".equals(tradeStatus)) {
                        // 订单关闭
                        return paymentOrderService.markOrderCanceled(outTradeNo)
                                .thenReturn("success");
                    }

                    return Mono.just("success");
                })
                .onErrorResume(e -> {
                    log.error("❌ 处理支付宝通知异常", e);
                    return Mono.just("fail");
                });
    }

    /**
     * 支付宝同步回调（用户支付完成后跳转）
     */
    @GetMapping("/return/ALIPAY")
    @Operation(summary = "支付宝同步回调", description = "用户支付完成后的同步跳转")
    public Mono<String> alipayReturn(@RequestParam Map<String, String> params) {
        log.info("🔙 收到支付宝同步回调: {}", params);

        String outTradeNo = params.get("out_trade_no");
        
        // 验证签名
        return alipayService.verifyNotify(params)
                .flatMap(verified -> {
                    if (!verified) {
                        log.warn("⚠️ 支付宝同步回调签名验证失败");
                        return Mono.just("redirect:/payment/failure");
                    }

                    // 同步订单状态
                    return paymentOrderService.syncOrderStatus(outTradeNo)
                            .map(order -> {
                                if (order.getStatus() == PaymentOrder.PayStatus.SUCCESS) {
                                    return "redirect:/payment/success?outTradeNo=" + outTradeNo;
                                } else {
                                    return "redirect:/payment/pending?outTradeNo=" + outTradeNo;
                                }
                            })
                            .onErrorResume(e -> {
                                log.error("❌ 处理同步回调失败", e);
                                return Mono.just("redirect:/payment/failure");
                            });
                });
    }
}
