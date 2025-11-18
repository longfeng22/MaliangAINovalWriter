package com.ainovel.server.service.payment;

import com.ainovel.server.domain.model.PaymentOrder;
import com.ainovel.server.domain.model.PaymentOrder.PayChannel;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 支付订单服务接口
 */
public interface PaymentOrderService {

    /**
     * 创建订阅计划支付订单
     *
     * @param userId 用户ID
     * @param planId 订阅计划ID
     * @param channel 支付渠道
     * @param returnUrl 同步回调地址
     * @return 支付订单信息（包含支付URL）
     */
    Mono<PaymentOrder> createSubscriptionOrder(String userId, String planId, PayChannel channel, String returnUrl);

    /**
     * 创建积分包支付订单
     *
     * @param userId 用户ID
     * @param creditPackId 积分包ID
     * @param channel 支付渠道
     * @param returnUrl 同步回调地址
     * @return 支付订单信息（包含支付URL）
     */
    Mono<PaymentOrder> createCreditPackOrder(String userId, String creditPackId, PayChannel channel, String returnUrl);

    /**
     * 根据商户订单号查询订单
     *
     * @param outTradeNo 商户订单号
     * @return 支付订单
     */
    Mono<PaymentOrder> getOrderByOutTradeNo(String outTradeNo);

    /**
     * 根据订单ID查询订单
     *
     * @param orderId 订单ID
     * @return 支付订单
     */
    Mono<PaymentOrder> getOrderById(String orderId);

    /**
     * 查询用户的所有订单
     *
     * @param userId 用户ID
     * @return 订单列表
     */
    Flux<PaymentOrder> getUserOrders(String userId);

    /**
     * 更新订单状态为支付成功
     *
     * @param outTradeNo 商户订单号
     * @param transactionId 支付宝交易号
     * @return 更新后的订单
     */
    Mono<PaymentOrder> markOrderPaid(String outTradeNo, String transactionId);

    /**
     * 更新订单状态为支付失败
     *
     * @param outTradeNo 商户订单号
     * @return 更新后的订单
     */
    Mono<PaymentOrder> markOrderFailed(String outTradeNo);

    /**
     * 更新订单状态为已取消
     *
     * @param outTradeNo 商户订单号
     * @return 更新后的订单
     */
    Mono<PaymentOrder> markOrderCanceled(String outTradeNo);

    /**
     * 处理支付成功回调
     * 包括分配订阅、发放积分等业务逻辑
     *
     * @param outTradeNo 商户订单号
     * @return 处理结果
     */
    Mono<Boolean> handlePaymentSuccess(String outTradeNo);

    /**
     * 同步支付宝订单状态
     *
     * @param outTradeNo 商户订单号
     * @return 同步后的订单
     */
    Mono<PaymentOrder> syncOrderStatus(String outTradeNo);

    /**
     * 生成商户订单号
     *
     * @return 商户订单号
     */
    String generateOutTradeNo();
}

