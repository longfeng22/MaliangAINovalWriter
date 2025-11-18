package com.ainovel.server.domain.model;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * AI请求模型
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AIRequest {

    /**
     * 用户ID
     */
    private String userId;

    /**
     * 会话ID
     */
    private String sessionId;
        

    /**
     * 最大生成令牌数
     */
    @Builder.Default
    private Integer maxTokens = 81920;
    
    /**
     * 温度参数（0-2之间，越高越随机）
     */
    @Builder.Default
    private Double temperature = 0.7;
    

    /**
     * 上下文相关的小说ID
     */
    private String novelId;

    /**
     * 上下文相关的场景ID
     */
    private String sceneId;

    /**
     * 请求的模型名称
     */
    private String model;

    /**
     * 明确的功能类型（用于计费/追踪决策）
     */
    private AIFeatureType featureType;

    /**
     * 明确的追踪ID（用于预扣费与后扣费关联），优先于metadata/providerSpecific中的幂等键
     */
    private String traceId;

    /**
     * 是否启用上下文
     */
    @Builder.Default
    private Boolean enableContext = true;

    /**
     * 提示内容
     */
    private String prompt;

        /**
     * 其他参数
     * 公共模型调用必须设置parameters.modelConfigId，否则无法正常扣费
     */
    @Builder.Default
    private Map<String, Object> parameters = new HashMap<>();

    /**
     * 其他参数
     */
    @Builder.Default
    private Map<String, Object> metadata = new HashMap<>();

    /**
     * 对话历史
     */
    @Builder.Default
    private List<Message> messages = new ArrayList<>();

    /**
     * 工具规范列表（用于函数调用）
     * 直接作为AIRequest的一级字段，避免在metadata中传递
     */
    private List<Object> toolSpecifications;

    /**
     * 对话消息
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Message {

        /**
         * 角色（user, assistant, system, tool）
         */
        private String role;

        /**
         * 消息内容
         */
        private String content;

        /**
         * 工具调用请求列表（仅用于assistant消息）
         */
        private List<ToolExecutionRequest> toolExecutionRequests;

        /**
         * 工具执行结果（仅用于tool消息）
         */
        private ToolExecutionResult toolExecutionResult;

        // 手动添加getter和setter方法，以防Lombok注解未正确处理
        public String getRole() {
            return role;
        }

        public void setRole(String role) {
            this.role = role;
        }

        public String getContent() {
            return content;
        }

        public void setContent(String content) {
            this.content = content;
        }

        public List<ToolExecutionRequest> getToolExecutionRequests() {
            return toolExecutionRequests;
        }

        public void setToolExecutionRequests(List<ToolExecutionRequest> toolExecutionRequests) {
            this.toolExecutionRequests = toolExecutionRequests;
        }

        public ToolExecutionResult getToolExecutionResult() {
            return toolExecutionResult;
        }

        public void setToolExecutionResult(ToolExecutionResult toolExecutionResult) {
            this.toolExecutionResult = toolExecutionResult;
        }
    }

    /**
     * 工具执行请求
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ToolExecutionRequest {
        private String id;
        private String name;
        private String arguments;
    }

    /**
     * 工具执行结果
     */
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ToolExecutionResult {
        private String toolExecutionId;
        private String toolName;
        private String result;
    }

    // 手动添加getter和setter方法，以防Lombok注解未正确处理
    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getSessionId() {
        return sessionId;
    }

    public void setSessionId(String sessionId) {
        this.sessionId = sessionId;
    }

    public String getNovelId() {
        return novelId;
    }

    public void setNovelId(String novelId) {
        this.novelId = novelId;
    }

    public String getSceneId() {
        return sceneId;
    }

    public void setSceneId(String sceneId) {
        this.sceneId = sceneId;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public AIFeatureType getFeatureType() {
        return featureType;
    }

    public void setFeatureType(AIFeatureType featureType) {
        this.featureType = featureType;
    }

    public String getTraceId() {
        return traceId;
    }

    public void setTraceId(String traceId) {
        this.traceId = traceId;
    }

    public Boolean getEnableContext() {
        return enableContext;
    }

    public void setEnableContext(Boolean enableContext) {
        this.enableContext = enableContext;
    }

    public String getPrompt() {
        return prompt;
    }

    public void setPrompt(String prompt) {
        this.prompt = prompt;
    }

    public Map<String, Object> getMetadata() {
        return metadata;
    }

    public void setMetadata(Map<String, Object> metadata) {
        this.metadata = metadata;
    }

    public List<Message> getMessages() {
        return messages;
    }

    public void setMessages(List<Message> messages) {
        this.messages = messages;
    }
}
