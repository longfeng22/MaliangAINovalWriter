package com.ainovel.server.service.payment.impl;

import com.alipay.easysdk.factory.Factory;
import com.alipay.easysdk.payment.page.models.AlipayTradePagePayResponse;
import com.alipay.easysdk.payment.wap.models.AlipayTradeWapPayResponse;
import com.alipay.easysdk.payment.common.models.AlipayTradeQueryResponse;
import com.alipay.easysdk.payment.common.models.AlipayTradeCloseResponse;
import com.alipay.easysdk.payment.common.models.AlipayTradeRefundResponse;
import com.ainovel.server.service.payment.AlipayService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

/**
 * 支付宝支付服务实现类
 */
@Slf4j
@Service
public class AlipayServiceImpl implements AlipayService {

    @Override
    public Mono<String> createPagePayment(String outTradeNo, BigDecimal totalAmount, String subject, String returnUrl) {
        return Mono.fromCallable(() -> {
            log.info("💳 创建电脑网站支付订单: outTradeNo={}, amount={}, subject={}", 
                    outTradeNo, totalAmount, subject);
            
            try {
                AlipayTradePagePayResponse response = Factory.Payment.Page()
                        .pay(subject, outTradeNo, totalAmount.toString(), returnUrl);
                
                if (response != null) {
                    log.info("✅ 支付宝订单创建成功: {}", outTradeNo);
                    return response.body;
                } else {
                    log.error("❌ 支付宝订单创建失败: 响应为空");
                    throw new RuntimeException("支付宝订单创建失败");
                }
            } catch (Exception e) {
                log.error("❌ 调用支付宝API异常", e);
                throw new RuntimeException("调用支付宝API异常: " + e.getMessage(), e);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<String> createWapPayment(String outTradeNo, BigDecimal totalAmount, String subject, String returnUrl) {
        return Mono.fromCallable(() -> {
            log.info("📱 创建手机网站支付订单: outTradeNo={}, amount={}, subject={}", 
                    outTradeNo, totalAmount, subject);
            
            try {
                AlipayTradeWapPayResponse response = Factory.Payment.Wap()
                        .pay(subject, outTradeNo, totalAmount.toString(), "", returnUrl);
                
                if (response != null) {
                    log.info("✅ 手机网站支付订单创建成功: {}", outTradeNo);
                    return response.body;
                } else {
                    log.error("❌ 手机网站支付订单创建失败: 响应为空");
                    throw new RuntimeException("手机网站支付订单创建失败");
                }
            } catch (Exception e) {
                log.error("❌ 调用支付宝API异常", e);
                throw new RuntimeException("调用支付宝API异常: " + e.getMessage(), e);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Boolean> verifyNotify(Map<String, String> params) {
        return Mono.fromCallable(() -> {
            try {
                log.info("🔍 验证支付宝异步通知签名");
                boolean verified = Factory.Payment.Common().verifyNotify(params);
                
                if (verified) {
                    log.info("✅ 支付宝异步通知签名验证成功");
                } else {
                    log.warn("⚠️ 支付宝异步通知签名验证失败");
                }
                
                return verified;
            } catch (Exception e) {
                log.error("❌ 验证支付宝通知签名异常", e);
                return false;
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Map<String, String>> queryTrade(String outTradeNo) {
        return Mono.fromCallable(() -> {
            log.info("🔍 查询支付宝交易状态: outTradeNo={}", outTradeNo);
            
            try {
                AlipayTradeQueryResponse response = Factory.Payment.Common().query(outTradeNo);
                
                if (response != null) {
                    Map<String, String> result = new HashMap<>();
                    result.put("tradeNo", response.tradeNo);
                    result.put("tradeStatus", response.tradeStatus);
                    result.put("totalAmount", response.totalAmount);
                    result.put("buyerPayAmount", response.buyerPayAmount);
                    result.put("sendPayDate", response.sendPayDate);
                    
                    log.info("✅ 查询成功: tradeNo={}, status={}", response.tradeNo, response.tradeStatus);
                    return result;
                } else {
                    log.warn("⚠️ 查询失败: 响应为空");
                    return null;
                }
            } catch (Exception e) {
                log.error("❌ 查询支付宝交易异常", e);
                return null;
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Boolean> closeTrade(String outTradeNo) {
        return Mono.fromCallable(() -> {
            log.info("🔒 关闭支付宝订单: outTradeNo={}", outTradeNo);
            
            try {
                AlipayTradeCloseResponse response = Factory.Payment.Common().close(outTradeNo);
                
                if (response != null) {
                    log.info("✅ 订单关闭成功: {}", outTradeNo);
                    return true;
                } else {
                    log.warn("⚠️ 订单关闭失败: 响应为空");
                    return false;
                }
            } catch (Exception e) {
                log.error("❌ 关闭支付宝订单异常", e);
                return false;
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Boolean> refund(String outTradeNo, BigDecimal refundAmount, String refundReason) {
        return Mono.fromCallable(() -> {
            log.info("💰 发起支付宝退款: outTradeNo={}, amount={}, reason={}", 
                    outTradeNo, refundAmount, refundReason);
            
            try {
                AlipayTradeRefundResponse response = Factory.Payment.Common()
                        .refund(outTradeNo, refundAmount.toString());
                
                if (response != null) {
                    log.info("✅ 退款成功: {}", outTradeNo);
                    return true;
                } else {
                    log.error("❌ 退款失败: 响应为空");
                    return false;
                }
            } catch (Exception e) {
                log.error("❌ 支付宝退款异常", e);
                return false;
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }
}

