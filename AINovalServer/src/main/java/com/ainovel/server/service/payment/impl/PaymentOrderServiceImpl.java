package com.ainovel.server.service.payment.impl;

import com.ainovel.server.domain.model.*;
import com.ainovel.server.domain.model.PaymentOrder.OrderType;
import com.ainovel.server.domain.model.PaymentOrder.PayChannel;
import com.ainovel.server.domain.model.PaymentOrder.PayStatus;
import com.ainovel.server.repository.*;
import com.ainovel.server.service.CreditService;
import com.ainovel.server.service.SubscriptionAssignmentService;
import com.ainovel.server.service.payment.AlipayService;
import com.ainovel.server.service.payment.PaymentOrderService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.UUID;

/**
 * 支付订单服务实现类
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentOrderServiceImpl implements PaymentOrderService {

    private final PaymentOrderRepository paymentOrderRepository;
    private final SubscriptionPlanRepository subscriptionPlanRepository;
    private final CreditPackRepository creditPackRepository;
    private final AlipayService alipayService;
    private final SubscriptionAssignmentService subscriptionAssignmentService;
    private final CreditService creditService;

    @Override
    public Mono<PaymentOrder> createSubscriptionOrder(String userId, String planId, PayChannel channel, String returnUrl) {
        log.info("📝 创建订阅计划支付订单: userId={}, planId={}, channel={}", userId, planId, channel);

        return subscriptionPlanRepository.findById(planId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("订阅计划不存在")))
                .flatMap(plan -> {
                    if (!plan.getActive()) {
                        return Mono.error(new IllegalArgumentException("订阅计划已停用"));
                    }

                    // 创建支付订单
                    String outTradeNo = generateOutTradeNo();
                    PaymentOrder order = PaymentOrder.builder()
                            .outTradeNo(outTradeNo)
                            .userId(userId)
                            .planId(planId)
                            .planNameSnapshot(plan.getPlanName())
                            .priceSnapshot(plan.getPrice())
                            .currencySnapshot(plan.getCurrency())
                            .billingCycleSnapshot(plan.getBillingCycle())
                            .amount(plan.getPrice())
                            .currency(plan.getCurrency())
                            .channel(channel)
                            .status(PayStatus.CREATED)
                            .orderType(OrderType.SUBSCRIPTION)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .expireAt(LocalDateTime.now().plusMinutes(30)) // 30分钟过期
                            .build();

                    return paymentOrderRepository.save(order)
                            .flatMap(savedOrder -> createPaymentUrl(savedOrder, plan.getPlanName(), returnUrl));
                });
    }

    @Override
    public Mono<PaymentOrder> createCreditPackOrder(String userId, String creditPackId, PayChannel channel, String returnUrl) {
        log.info("📝 创建积分包支付订单: userId={}, creditPackId={}, channel={}", userId, creditPackId, channel);

        return creditPackRepository.findById(creditPackId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("积分包不存在")))
                .flatMap(pack -> {
                    if (!pack.getActive()) {
                        return Mono.error(new IllegalArgumentException("积分包已停用"));
                    }

                    // 创建支付订单
                    String outTradeNo = generateOutTradeNo();
                    PaymentOrder order = PaymentOrder.builder()
                            .outTradeNo(outTradeNo)
                            .userId(userId)
                            .planId(creditPackId)
                            .planNameSnapshot(pack.getName())
                            .priceSnapshot(pack.getPrice())
                            .currencySnapshot(pack.getCurrency())
                            .amount(pack.getPrice())
                            .currency(pack.getCurrency())
                            .channel(channel)
                            .status(PayStatus.CREATED)
                            .orderType(OrderType.CREDIT_PACK)
                            .createdAt(LocalDateTime.now())
                            .updatedAt(LocalDateTime.now())
                            .expireAt(LocalDateTime.now().plusMinutes(30)) // 30分钟过期
                            .build();

                    return paymentOrderRepository.save(order)
                            .flatMap(savedOrder -> createPaymentUrl(savedOrder, pack.getName() + " 积分包", returnUrl));
                });
    }

    /**
     * 创建支付URL
     */
    private Mono<PaymentOrder> createPaymentUrl(PaymentOrder order, String subject, String returnUrl) {
        if (order.getChannel() == PayChannel.ALIPAY) {
            // 支付宝支付
            return alipayService.createPagePayment(
                    order.getOutTradeNo(),
                    order.getAmount(),
                    subject,
                    returnUrl
            ).flatMap(paymentForm -> {
                order.setPaymentUrl(paymentForm);
                order.setStatus(PayStatus.PENDING);
                order.setUpdatedAt(LocalDateTime.now());
                return paymentOrderRepository.save(order);
            });
        }
        
        return Mono.error(new IllegalArgumentException("暂不支持该支付渠道"));
    }

    @Override
    public Mono<PaymentOrder> getOrderByOutTradeNo(String outTradeNo) {
        return paymentOrderRepository.findByOutTradeNo(outTradeNo);
    }

    @Override
    public Mono<PaymentOrder> getOrderById(String orderId) {
        return paymentOrderRepository.findById(orderId);
    }

    @Override
    public Flux<PaymentOrder> getUserOrders(String userId) {
        return paymentOrderRepository.findByUserIdOrderByCreatedAtDesc(userId);
    }

    @Override
    public Mono<PaymentOrder> markOrderPaid(String outTradeNo, String transactionId) {
        return paymentOrderRepository.findByOutTradeNo(outTradeNo)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("订单不存在")))
                .flatMap(order -> {
                    if (order.getStatus() == PayStatus.SUCCESS) {
                        log.info("⚠️ 订单已支付，跳过重复处理: {}", outTradeNo);
                        return Mono.just(order);
                    }

                    order.setStatus(PayStatus.SUCCESS);
                    order.setTransactionId(transactionId);
                    order.setPaidAt(LocalDateTime.now());
                    order.setUpdatedAt(LocalDateTime.now());

                    return paymentOrderRepository.save(order);
                });
    }

    @Override
    public Mono<PaymentOrder> markOrderFailed(String outTradeNo) {
        return paymentOrderRepository.findByOutTradeNo(outTradeNo)
                .flatMap(order -> {
                    order.setStatus(PayStatus.FAILED);
                    order.setUpdatedAt(LocalDateTime.now());
                    return paymentOrderRepository.save(order);
                });
    }

    @Override
    public Mono<PaymentOrder> markOrderCanceled(String outTradeNo) {
        return paymentOrderRepository.findByOutTradeNo(outTradeNo)
                .flatMap(order -> {
                    order.setStatus(PayStatus.CANCELED);
                    order.setUpdatedAt(LocalDateTime.now());
                    return paymentOrderRepository.save(order);
                });
    }

    @Override
    public Mono<Boolean> handlePaymentSuccess(String outTradeNo) {
        log.info("🎉 处理支付成功回调: outTradeNo={}", outTradeNo);

        return getOrderByOutTradeNo(outTradeNo)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("订单不存在")))
                .flatMap(order -> {
                    if (order.getStatus() == PayStatus.SUCCESS) {
                        log.info("⚠️ 订单已处理过，跳过: {}", outTradeNo);
                        return Mono.just(true);
                    }

                    // 根据订单类型处理业务逻辑
                    if (order.getOrderType() == OrderType.SUBSCRIPTION) {
                        // 分配订阅计划
                        return subscriptionAssignmentService.assignSubscription(order)
                                .then(Mono.just(true))
                                .onErrorResume(e -> {
                                    log.error("❌ 分配订阅计划失败", e);
                                    return Mono.just(false);
                                });
                    } else if (order.getOrderType() == OrderType.CREDIT_PACK) {
                        // 发放积分
                        return creditPackRepository.findById(order.getPlanId())
                                .flatMap(pack -> creditService.addCredits(order.getUserId(), pack.getCredits(), "购买积分包"))
                                .then(Mono.just(true))
                                .onErrorResume(e -> {
                                    log.error("❌ 发放积分失败", e);
                                    return Mono.just(false);
                                });
                    }

                    return Mono.just(true);
                });
    }

    @Override
    public Mono<PaymentOrder> syncOrderStatus(String outTradeNo) {
        return paymentOrderRepository.findByOutTradeNo(outTradeNo)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("订单不存在")))
                .flatMap(order -> {
                    if (order.getChannel() == PayChannel.ALIPAY) {
                        return alipayService.queryTrade(outTradeNo)
                                .flatMap(tradeInfo -> {
                                    if (tradeInfo != null) {
                                        String tradeStatus = tradeInfo.get("tradeStatus");
                                        String tradeNo = tradeInfo.get("tradeNo");

                                        if ("TRADE_SUCCESS".equals(tradeStatus) || "TRADE_FINISHED".equals(tradeStatus)) {
                                            return markOrderPaid(outTradeNo, tradeNo)
                                                    .flatMap(updatedOrder -> 
                                                        handlePaymentSuccess(outTradeNo)
                                                                .thenReturn(updatedOrder)
                                                    );
                                        } else if ("TRADE_CLOSED".equals(tradeStatus)) {
                                            return markOrderCanceled(outTradeNo);
                                        }
                                    }
                                    return Mono.just(order);
                                });
                    }
                    return Mono.just(order);
                });
    }

    @Override
    public String generateOutTradeNo() {
        // 格式: AINOVAL_yyyyMMddHHmmss_随机UUID前8位
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"));
        String random = UUID.randomUUID().toString().replace("-", "").substring(0, 8);
        return "AINOVAL_" + timestamp + "_" + random;
    }
}

