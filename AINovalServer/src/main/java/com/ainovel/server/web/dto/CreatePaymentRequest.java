package com.ainovel.server.web.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/**
 * 创建支付请求DTO
 */
@Data
public class CreatePaymentRequest {

    /**
     * 计划ID（订阅计划ID或积分包ID）
     */
    @NotBlank(message = "计划ID不能为空")
    private String planId;

    /**
     * 支付渠道（ALIPAY, WECHAT）
     */
    @NotBlank(message = "支付渠道不能为空")
    private String channel;

    /**
     * 同步回调地址（用户支付完成后跳转的地址）
     */
    private String returnUrl;
}

