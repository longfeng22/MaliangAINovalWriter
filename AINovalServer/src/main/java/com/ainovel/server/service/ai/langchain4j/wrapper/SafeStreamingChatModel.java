package com.ainovel.server.service.ai.langchain4j.wrapper;

import java.util.List;

import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.model.chat.StreamingChatLanguageModel;
import dev.langchain4j.model.chat.listener.ChatModelListener;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.request.ChatRequestParameters;
import dev.langchain4j.model.chat.response.ChatResponse;
import dev.langchain4j.model.chat.response.StreamingChatResponseHandler;

/**
 * 安全包装器：过滤底层模型可能发出的 null/空 分片，避免上层 sink.next(t) NPE。
 */
public class SafeStreamingChatModel implements StreamingChatLanguageModel {

    private final StreamingChatLanguageModel delegate;

    public SafeStreamingChatModel(StreamingChatLanguageModel delegate) {
        this.delegate = delegate;
    }

    @Override
    public void chat(List<ChatMessage> messages, StreamingChatResponseHandler handler) {
        StreamingChatResponseHandler safeHandler = new StreamingChatResponseHandler() {
            @Override
            public void onPartialResponse(String partialResponse) {
                if (partialResponse != null && !partialResponse.isEmpty()) {
                    handler.onPartialResponse(partialResponse);
                }
            }

            @Override
            public void onCompleteResponse(ChatResponse response) {
                handler.onCompleteResponse(response);
            }

            @Override
            public void onError(Throwable error) {
                handler.onError(error);
            }
        };
        delegate.chat(messages, safeHandler);
    }

    @Override
    public void chat(ChatRequest chatRequest, StreamingChatResponseHandler handler) {
        StreamingChatResponseHandler safeHandler = new StreamingChatResponseHandler() {
            @Override
            public void onPartialResponse(String partialResponse) {
                if (partialResponse != null && !partialResponse.isEmpty()) {
                    handler.onPartialResponse(partialResponse);
                }
            }

            @Override
            public void onCompleteResponse(ChatResponse response) {
                handler.onCompleteResponse(response);
            }

            @Override
            public void onError(Throwable error) {
                handler.onError(error);
            }
        };
        delegate.chat(chatRequest, safeHandler);
    }

    @Override
    public ChatRequestParameters defaultRequestParameters() {
        return delegate.defaultRequestParameters();
    }

    @Override
    public List<ChatModelListener> listeners() {
        return delegate.listeners();
    }
}


