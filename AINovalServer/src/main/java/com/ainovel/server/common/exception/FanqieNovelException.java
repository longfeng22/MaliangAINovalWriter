package com.ainovel.server.common.exception;

/**
 * 番茄小说相关异常
 */
public class FanqieNovelException extends RuntimeException {
    
    private final String errorCode;
    
    public FanqieNovelException(String message) {
        super(message);
        this.errorCode = "FANQIE_NOVEL_ERROR";
    }
    
    public FanqieNovelException(String message, String errorCode) {
        super(message);
        this.errorCode = errorCode;
    }
    
    public FanqieNovelException(String message, Throwable cause) {
        super(message, cause);
        this.errorCode = "FANQIE_NOVEL_ERROR";
    }
    
    public FanqieNovelException(String message, String errorCode, Throwable cause) {
        super(message, cause);
        this.errorCode = errorCode;
    }
    
    public String getErrorCode() {
        return errorCode;
    }
}


