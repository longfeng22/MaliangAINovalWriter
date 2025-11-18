package com.ainovel.server.domain.model;

/**
 * 审核状态常量
 * 用于模板分享审核流程
 */
public final class ReviewStatusConstants {
    
    private ReviewStatusConstants() {
        throw new UnsupportedOperationException("This is a constants class and cannot be instantiated");
    }
    
    /**
     * 草稿状态（未提交审核）
     */
    public static final String DRAFT = "DRAFT";
    
    /**
     * 待审核状态
     */
    public static final String PENDING = "PENDING";
    
    /**
     * 审核通过
     */
    public static final String APPROVED = "APPROVED";
    
    /**
     * 审核拒绝
     */
    public static final String REJECTED = "REJECTED";
    
    /**
     * 审核优先级：低
     */
    public static final String PRIORITY_LOW = "LOW";
    
    /**
     * 审核优先级：普通
     */
    public static final String PRIORITY_NORMAL = "NORMAL";
    
    /**
     * 审核优先级：高
     */
    public static final String PRIORITY_HIGH = "HIGH";
    
    /**
     * 审核优先级：紧急
     */
    public static final String PRIORITY_URGENT = "URGENT";
}








