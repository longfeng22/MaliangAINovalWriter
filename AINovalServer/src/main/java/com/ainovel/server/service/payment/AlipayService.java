package com.ainovel.server.service.payment;

import reactor.core.publisher.Mono;

import java.math.BigDecimal;
import java.util.Map;

/**
 * 支付宝支付服务接口
 */
public interface AlipayService {

    /**
     * 创建电脑网站支付订单
     *
     * @param outTradeNo 商户订单号
     * @param totalAmount 订单金额
     * @param subject 订单标题
     * @param returnUrl 同步回调地址
     * @return 支付表单HTML
     */
    Mono<String> createPagePayment(String outTradeNo, BigDecimal totalAmount, String subject, String returnUrl);

    /**
     * 创建手机网站支付订单
     *
     * @param outTradeNo 商户订单号
     * @param totalAmount 订单金额
     * @param subject 订单标题
     * @param returnUrl 同步回调地址
     * @return 支付表单HTML
     */
    Mono<String> createWapPayment(String outTradeNo, BigDecimal totalAmount, String subject, String returnUrl);

    /**
     * 验证支付宝异步通知签名
     *
     * @param params 通知参数
     * @return 是否验证通过
     */
    Mono<Boolean> verifyNotify(Map<String, String> params);

    /**
     * 查询交易状态
     *
     * @param outTradeNo 商户订单号
     * @return 支付宝交易信息
     */
    Mono<Map<String, String>> queryTrade(String outTradeNo);

    /**
     * 关闭订单
     *
     * @param outTradeNo 商户订单号
     * @return 是否关闭成功
     */
    Mono<Boolean> closeTrade(String outTradeNo);

    /**
     * 退款
     *
     * @param outTradeNo 商户订单号
     * @param refundAmount 退款金额
     * @param refundReason 退款原因
     * @return 是否退款成功
     */
    Mono<Boolean> refund(String outTradeNo, BigDecimal refundAmount, String refundReason);
}

