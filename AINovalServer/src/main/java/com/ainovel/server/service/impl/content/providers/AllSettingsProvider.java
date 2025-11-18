package com.ainovel.server.service.impl.content.providers;

import com.ainovel.server.service.NovelSettingService;
import com.ainovel.server.service.impl.content.ContentProvider;
import com.ainovel.server.service.impl.content.ContentResult;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import com.ainovel.server.common.util.PromptXmlFormatter;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import lombok.extern.slf4j.Slf4j;

/**
 * 全部设定提供器
 * 用于一次性获取该小说下的所有设定内容，作为通用上下文选择项
 */
@Slf4j
@Component
public class AllSettingsProvider implements ContentProvider {

    private static final String TYPE_ALL_SETTINGS = "all_settings";

    @Autowired
    private NovelSettingService novelSettingService;

    @Autowired
    private PromptXmlFormatter promptXmlFormatter;

    @Override
    public Mono<ContentResult> getContent(String id, UniversalAIRequestDto request) {
        String targetNovelId = request != null ? request.getNovelId() : null;
        if (targetNovelId == null || targetNovelId.isEmpty()) {
            log.warn("小说ID为空，无法获取全部设定");
            return Mono.just(new ContentResult("", TYPE_ALL_SETTINGS, id));
        }

        return novelSettingService
                .getNovelSettingItems(targetNovelId, null, null, null, null, null, Pageable.unpaged())
                .map(promptXmlFormatter::formatSettingWithoutId)
                .collectList()
                .map(list -> String.join("\n", list))
                .map(content -> new ContentResult(content, TYPE_ALL_SETTINGS, id))
                .onErrorReturn(new ContentResult("", TYPE_ALL_SETTINGS, id));
    }

    @Override
    public String getType() {
        return TYPE_ALL_SETTINGS;
    }

    @Override
    public Mono<String> getContentForPlaceholder(String userId, String novelId, String contentId,
                                                 java.util.Map<String, Object> parameters) {
        if (novelId == null || novelId.isEmpty()) {
            log.warn("novelId为空，无法获取全部设定");
            return Mono.just("");
        }

        return novelSettingService
                .getNovelSettingItems(novelId, null, null, null, null, null, Pageable.unpaged())
                .map(promptXmlFormatter::formatSettingWithoutId)
                .collectList()
                .map(list -> String.join("\n", list))
                .onErrorReturn("");
    }

    @Override
    public Mono<Integer> getEstimatedContentLength(java.util.Map<String, Object> contextParameters) {
        // 需要 novelId 来估算设定内容的长度
        String novelId = (String) contextParameters.get("novelId");
        if (novelId == null || novelId.isBlank()) {
            return Mono.just(0);
        }

        return novelSettingService
                .getNovelSettingItems(novelId, null, null, null, null, null, Pageable.unpaged())
                .map(setting -> {
                    String description = setting.getDescription();
                    return description != null ? description.length() : 0;
                })
                .reduce(0, Integer::sum)
                .onErrorReturn(0);
    }
}


