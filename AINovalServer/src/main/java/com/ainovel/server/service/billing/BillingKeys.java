package com.ainovel.server.service.billing;

/**
 * 计费相关的标准键名，统一providerSpecific与metadata中的键，避免魔法字符串。
 */
public final class BillingKeys {
    public static final String USED_PUBLIC_MODEL = "usedPublicModel";
    public static final String REQUIRES_POST_STREAM_DEDUCTION = "requiresPostStreamDeduction";
    public static final String STREAM_FEATURE_TYPE = "streamFeatureType";
    public static final String PUBLIC_MODEL_CONFIG_ID = "publicModelConfigId";
    public static final String PROVIDER = "provider";
    public static final String MODEL_ID = "modelId";
    public static final String CORRELATION_ID = "correlationId";
    public static final String REQUEST_IDEMPOTENCY_KEY = "idempotencyKey";
    public static final String REQUEST_TYPE = "requestType";
    /**
     * 工具编排链路的特殊标记：当为 true 时，表示该请求属于设定生成等工具调用编排，
     * 不进行计费标记注入，也不触发后扣费或对账流程。
     */
    public static final String SKIP_BILLING_FOR_TOOL_ORCHESTRATION = "skipBillingForToolOrchestration";

    private BillingKeys() {}
}


