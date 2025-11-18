package com.ainovel.server.common.exception;

/**
 * 知识提取异常
 */
public class KnowledgeExtractionException extends RuntimeException {
    
    private final String errorCode;
    
    public KnowledgeExtractionException(String message) {
        super(message);
        this.errorCode = "KNOWLEDGE_EXTRACTION_ERROR";
    }
    
    public KnowledgeExtractionException(String message, String errorCode) {
        super(message);
        this.errorCode = errorCode;
    }
    
    public KnowledgeExtractionException(String message, Throwable cause) {
        super(message, cause);
        this.errorCode = "KNOWLEDGE_EXTRACTION_ERROR";
    }
    
    public KnowledgeExtractionException(String message, String errorCode, Throwable cause) {
        super(message, cause);
        this.errorCode = errorCode;
    }
    
    public String getErrorCode() {
        return errorCode;
    }
}


