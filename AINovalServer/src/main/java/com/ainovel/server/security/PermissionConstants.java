package com.ainovel.server.security;

/**
 * 权限常量定义
 */
public final class PermissionConstants {
    
    private PermissionConstants() {
        // 防止实例化
    }
    
    // 角色常量
    public static final String ROLE_ADMIN = "ROLE_ADMIN";
    public static final String ROLE_PRO = "ROLE_PRO";
    public static final String ROLE_FREE = "ROLE_FREE";
    public static final String ROLE_USER = "ROLE_USER";
    
    // AI功能权限
    public static final String FEATURE_SCENE_TO_SUMMARY = "FEATURE_SCENE_TO_SUMMARY";
    public static final String FEATURE_SUMMARY_TO_SCENE = "FEATURE_SUMMARY_TO_SCENE";
    public static final String FEATURE_TEXT_EXPANSION = "FEATURE_TEXT_EXPANSION";
    public static final String FEATURE_TEXT_REFACTOR = "FEATURE_TEXT_REFACTOR";
    public static final String FEATURE_TEXT_SUMMARY = "FEATURE_TEXT_SUMMARY";
    public static final String FEATURE_AI_CHAT = "FEATURE_AI_CHAT";
    public static final String FEATURE_NOVEL_GENERATION = "FEATURE_NOVEL_GENERATION";
    public static final String FEATURE_PROFESSIONAL_FICTION_CONTINUATION = "FEATURE_PROFESSIONAL_FICTION_CONTINUATION";
    public static final String FEATURE_SCENE_BEAT_GENERATION = "FEATURE_SCENE_BEAT_GENERATION";
    public static final String FEATURE_SETTING_TREE_GENERATION = "FEATURE_SETTING_TREE_GENERATION";
    public static final String FEATURE_NOVEL_COMPOSE = "FEATURE_NOVEL_COMPOSE";
    public static final String FEATURE_STORY_PREDICTION_SUMMARY = "FEATURE_STORY_PREDICTION_SUMMARY";
    public static final String FEATURE_STORY_PREDICTION_SCENE = "FEATURE_STORY_PREDICTION_SCENE";
    
    // 管理权限
    public static final String ADMIN_MANAGE_USERS = "ADMIN_MANAGE_USERS";
    public static final String ADMIN_MANAGE_ROLES = "ADMIN_MANAGE_ROLES";
    public static final String ADMIN_MANAGE_SUBSCRIPTIONS = "ADMIN_MANAGE_SUBSCRIPTIONS";
    public static final String ADMIN_MANAGE_MODELS = "ADMIN_MANAGE_MODELS";
    public static final String ADMIN_MANAGE_CONFIGS = "ADMIN_MANAGE_CONFIGS";
    public static final String ADMIN_VIEW_ANALYTICS = "ADMIN_VIEW_ANALYTICS";
    public static final String ADMIN_MANAGE_CREDITS = "ADMIN_MANAGE_CREDITS";
    
    // 用户管理权限
    public static final String USER_READ_PROFILE = "USER_READ_PROFILE";
    public static final String USER_UPDATE_PROFILE = "USER_UPDATE_PROFILE";
    public static final String USER_DELETE_ACCOUNT = "USER_DELETE_ACCOUNT";
    public static final String USER_MANAGE_SUBSCRIPTIONS = "USER_MANAGE_SUBSCRIPTIONS";
    
    // 小说管理权限
    public static final String NOVEL_CREATE = "NOVEL_CREATE";
    public static final String NOVEL_READ = "NOVEL_READ";
    public static final String NOVEL_UPDATE = "NOVEL_UPDATE";
    public static final String NOVEL_DELETE = "NOVEL_DELETE";
    public static final String NOVEL_EXPORT = "NOVEL_EXPORT";
    public static final String NOVEL_IMPORT = "NOVEL_IMPORT";
    
    // 场景管理权限
    public static final String SCENE_CREATE = "SCENE_CREATE";
    public static final String SCENE_READ = "SCENE_READ";
    public static final String SCENE_UPDATE = "SCENE_UPDATE";
    public static final String SCENE_DELETE = "SCENE_DELETE";
    
    // 聊天权限
    public static final String CHAT_CREATE = "CHAT_CREATE";
    public static final String CHAT_READ = "CHAT_READ";
    public static final String CHAT_DELETE = "CHAT_DELETE";
    
    // 提示词模板权限
    public static final String TEMPLATE_CREATE = "TEMPLATE_CREATE";
    public static final String TEMPLATE_READ = "TEMPLATE_READ";
    public static final String TEMPLATE_UPDATE = "TEMPLATE_UPDATE";
    public static final String TEMPLATE_DELETE = "TEMPLATE_DELETE";
    public static final String TEMPLATE_PUBLISH = "TEMPLATE_PUBLISH";
    
    // 积分相关权限
    public static final String CREDIT_VIEW_BALANCE = "CREDIT_VIEW_BALANCE";
    public static final String CREDIT_VIEW_HISTORY = "CREDIT_VIEW_HISTORY";
    public static final String CREDIT_PURCHASE = "CREDIT_PURCHASE";
}