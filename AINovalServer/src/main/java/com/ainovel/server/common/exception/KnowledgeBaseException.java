package com.ainovel.server.common.exception;

/**
 * 知识库相关异常
 */
public class KnowledgeBaseException extends RuntimeException {
    
    private final String errorCode;
    
    public KnowledgeBaseException(String message) {
        super(message);
        this.errorCode = "KNOWLEDGE_BASE_ERROR";
    }
    
    public KnowledgeBaseException(String message, String errorCode) {
        super(message);
        this.errorCode = errorCode;
    }
    
    public KnowledgeBaseException(String message, Throwable cause) {
        super(message, cause);
        this.errorCode = "KNOWLEDGE_BASE_ERROR";
    }
    
    public KnowledgeBaseException(String message, String errorCode, Throwable cause) {
        super(message, cause);
        this.errorCode = errorCode;
    }
    
    public String getErrorCode() {
        return errorCode;
    }
}


