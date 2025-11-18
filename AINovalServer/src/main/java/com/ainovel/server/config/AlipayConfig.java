package com.ainovel.server.config;

import com.alipay.easysdk.factory.Factory;
import com.alipay.easysdk.kernel.Config;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import jakarta.annotation.PostConstruct;

/**
 * 支付宝支付配置类
 * 用于配置支付宝SDK和支付参数
 */
@Slf4j
@Data
@Component
@ConfigurationProperties(prefix = "payment.alipay")
public class AlipayConfig {

    /**
     * 应用ID
     */
    private String appId;

    /**
     * 商户私钥（PEM格式）
     */
    private String merchantPrivateKeyPem;

    /**
     * 商户公钥（PEM格式）
     */
    private String merchantPublicKeyPem;

    /**
     * 支付宝公钥（PEM格式）
     */
    private String alipayPublicKeyPem;

    /**
     * 异步通知回调地址
     */
    private String notifyUrl;

    /**
     * 是否启用沙箱环境
     */
    private Boolean sandbox = false;

    /**
     * 支付宝网关地址
     */
    private String gatewayHost;

    /**
     * 签名类型（默认RSA2）
     */
    private String signType = "RSA2";

    @PostConstruct
    public void init() {
        Config config = getConfig();
        
        // 初始化支付宝SDK
        Factory.setOptions(config);
        
        log.info("✅ 支付宝SDK初始化成功");
        log.info("   - 应用ID: {}", appId);
        log.info("   - 沙箱模式: {}", sandbox);
        log.info("   - 网关地址: {}", config.gatewayHost);
    }

    /**
     * 获取支付宝配置对象
     */
    @Bean
    public Config getConfig() {
        Config config = new Config();
        config.protocol = "https";
        
        // 根据沙箱模式设置网关地址
        if (sandbox != null && sandbox) {
            config.gatewayHost = "openapi-sandbox.dl.alipaydev.com";
            log.info("🧪 使用支付宝沙箱环境");
        } else {
            config.gatewayHost = "openapi.alipay.com";
            log.info("🌐 使用支付宝正式环境");
        }
        
        // 如果手动指定了网关地址，则使用指定的
        if (gatewayHost != null && !gatewayHost.isEmpty()) {
            config.gatewayHost = gatewayHost;
        }

        config.appId = this.appId;
        
        // 设置私钥
        config.merchantPrivateKey = cleanPemKey(this.merchantPrivateKeyPem);
        
        // 设置支付宝公钥
        config.alipayPublicKey = cleanPemKey(this.alipayPublicKeyPem);

        // 异步通知接收服务地址
        config.notifyUrl = this.notifyUrl;

        // 设置签名类型
        config.signType = this.signType;

        return config;
    }

    /**
     * 清理PEM密钥格式
     * 移除PEM头尾和换行符
     */
    private String cleanPemKey(String pemKey) {
        if (pemKey == null || pemKey.isEmpty()) {
            return pemKey;
        }
        
        return pemKey
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replace("-----BEGIN PUBLIC KEY-----", "")
                .replace("-----END PUBLIC KEY-----", "")
                .replace("-----BEGIN RSA PRIVATE KEY-----", "")
                .replace("-----END RSA PRIVATE KEY-----", "")
                .replace("-----BEGIN RSA PUBLIC KEY-----", "")
                .replace("-----END RSA PUBLIC KEY-----", "")
                .replaceAll("\\s+", "")
                .trim();
    }
}

