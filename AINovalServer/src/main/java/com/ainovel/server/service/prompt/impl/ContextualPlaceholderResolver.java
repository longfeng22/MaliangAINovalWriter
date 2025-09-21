package com.ainovel.server.service.prompt.impl;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.ainovel.server.service.impl.content.ContentProviderFactory;
import com.ainovel.server.service.impl.content.ContentProvider;
import com.ainovel.server.service.prompt.ContentPlaceholderResolver;
import com.ainovel.server.web.dto.request.UniversalAIRequestDto;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * 上下文感知的占位符解析器
 * 负责协调专用占位符（如{{snippets}}、{{setting}}）和通用占位符（{{context}}）
 * 确保内容不重复，专用占位符优先处理，{{context}}只包含未被专用占位符处理的内容
 */
@Slf4j
@Component
public class ContextualPlaceholderResolver implements ContentPlaceholderResolver {

    @Autowired
    private ContentProviderFactory contentProviderFactory;

    @Autowired
    private ContentProviderPlaceholderResolver delegateResolver;

    // 占位符匹配模式：{{type}} 或 {{type:id}}
    private static final Pattern PLACEHOLDER_PATTERN = Pattern.compile("\\{\\{([^:}]+)(?::([^}]+))?\\}\\}");

    // 专用占位符映射：这些占位符有专门的处理逻辑，不应该在{{context}}中重复
    private static final Map<String, String> SPECIALIZED_PLACEHOLDERS = java.util.Map.ofEntries(
        java.util.Map.entry("snippets", "snippet"),
        java.util.Map.entry("settings", "setting"),
        java.util.Map.entry("setting", "setting"),
        // 🚀 新增：设定组/设定类型也归一到setting，避免{{context}}重复
        java.util.Map.entry("setting_groups", "setting"),
        java.util.Map.entry("settings_by_type", "setting"),
        java.util.Map.entry("characters", "character"),
        java.util.Map.entry("locations", "location"),
        java.util.Map.entry("items", "item"),
        java.util.Map.entry("lore", "lore"),
        java.util.Map.entry("full_novel_text", "full_novel_text"),
        java.util.Map.entry("full_novel_summary", "full_novel_summary")
    );

    // 线程安全的解析上下文跟踪器
    private final ThreadLocal<PlaceholderResolutionContext> contextTracker = new ThreadLocal<>();

    /**
     * 占位符解析上下文
     * 用于跟踪在单次模板解析过程中哪些内容类型已经被专用占位符处理
     */
    public static class PlaceholderResolutionContext {
        private final Set<String> processedContentTypes = ConcurrentHashMap.newKeySet();
        private final Map<String, String> resolvedContent = new ConcurrentHashMap<>();
        
        public void markContentTypeProcessed(String contentType) {
            processedContentTypes.add(contentType.toLowerCase());
            log.debug("标记内容类型已处理: {}", contentType);
        }
        
        public boolean isContentTypeProcessed(String contentType) {
            return processedContentTypes.contains(contentType.toLowerCase());
        }
        
        public void storeResolvedContent(String placeholder, String content) {
            resolvedContent.put(placeholder, content);
        }
        
        public String getResolvedContent(String placeholder) {
            return resolvedContent.get(placeholder);
        }
        
        public Set<String> getProcessedContentTypes() {
            return new HashSet<>(processedContentTypes);
        }
        
        public void clear() {
            processedContentTypes.clear();
            resolvedContent.clear();
        }
    }

    /**
     * 智能解析模板中的所有占位符，确保专用占位符和通用占位符不重复
     */
    public Mono<String> resolveTemplate(String template, Map<String, Object> parameters, 
                                       String userId, String novelId) {
        if (template == null || template.isEmpty()) {
            return Mono.just("");
        }
        
        log.info("🧠 开始智能占位符解析: template length={}, userId={}, novelId={}", 
                template.length(), userId, novelId);
        
        // 初始化解析上下文
        PlaceholderResolutionContext context = new PlaceholderResolutionContext();
        contextTracker.set(context);
        
        // 1. 提取所有占位符
        List<String> placeholders = extractAllPlaceholders(template);
        if (placeholders.isEmpty()) {
            return Mono.just(template)
                    .doFinally(signalType -> {
                        context.clear();
                        contextTracker.remove();
                    });
        }
        
        log.info("📋 发现占位符: {}", placeholders);
        
        // 2. 分类占位符：专用占位符和通用占位符
        List<String> specializedPlaceholders = new ArrayList<>();
        List<String> contextPlaceholders = new ArrayList<>();
        List<String> otherPlaceholders = new ArrayList<>();
        
        for (String placeholder : placeholders) {
            if (isSpecializedPlaceholder(placeholder)) {
                specializedPlaceholders.add(placeholder);
            } else if ("context".equals(placeholder)) {
                contextPlaceholders.add(placeholder);
            } else {
                otherPlaceholders.add(placeholder);
            }
        }
        
        log.info("📊 占位符分类 - 专用: {}, 上下文: {}, 其他: {}", 
                specializedPlaceholders.size(), contextPlaceholders.size(), otherPlaceholders.size());
        
        // 3. 优先处理专用占位符
        return resolveSpecializedPlaceholders(template, specializedPlaceholders, parameters, userId, novelId)
                .flatMap(templateAfterSpecialized -> {
                    // 4. 处理上下文占位符（排除已处理的内容类型）
                    return resolveContextPlaceholders(templateAfterSpecialized, contextPlaceholders, 
                                                     parameters, userId, novelId);
                })
                .flatMap(templateAfterContext -> {
                    // 5. 处理其他占位符
                    return resolveOtherPlaceholders(templateAfterContext, otherPlaceholders, 
                                                   parameters, userId, novelId);
                })
                .doFinally(signalType -> {
                    // 🚀 修复：在流完成后清理线程本地上下文
                    context.clear();
                    contextTracker.remove();
                    log.debug("🧹 清理ThreadLocal上下文，信号类型: {}", signalType);
                });
    }

    @Override
    public Mono<String> resolvePlaceholder(String placeholder, Map<String, Object> parameters, 
                                          String userId, String novelId) {
        // 对于单个占位符解析，委托给原有的解析器
        return delegateResolver.resolvePlaceholder(placeholder, parameters, userId, novelId);
    }

    @Override
    public boolean supports(String placeholder) {
        return delegateResolver.supports(placeholder) || "context".equals(placeholder);
    }

    @Override
    public String getPlaceholderDescription(String placeholder) {
        if ("context".equals(placeholder)) {
            return "智能上下文信息（排除专用占位符已处理的内容）";
        }
        return delegateResolver.getPlaceholderDescription(placeholder);
    }

    /**
     * 提取模板中的所有占位符
     */
    private List<String> extractAllPlaceholders(String template) {
        List<String> placeholders = new ArrayList<>();
        Matcher matcher = PLACEHOLDER_PATTERN.matcher(template);
        
        while (matcher.find()) {
            String placeholderName = matcher.group(1); // placeholder 或 type
            String id = matcher.group(2); // id 或 null
            
            // 对于带ID的占位符，使用完整格式，否则只使用名称
            if (id != null) {
                placeholders.add(placeholderName + ":" + id);
            } else {
                placeholders.add(placeholderName);
            }
        }
        
        return placeholders.stream().distinct().collect(Collectors.toList());
    }

    /**
     * 判断是否为专用占位符
     */
    private boolean isSpecializedPlaceholder(String placeholder) {
        // 移除可能的ID部分
        String basePlaceholder = placeholder.contains(":") ? 
            placeholder.substring(0, placeholder.indexOf(":")) : placeholder;
            
        return SPECIALIZED_PLACEHOLDERS.containsKey(basePlaceholder);
    }

    /**
     * 解析专用占位符
     */
    private Mono<String> resolveSpecializedPlaceholders(String template, List<String> placeholders,
                                                       Map<String, Object> parameters, String userId, String novelId) {
        if (placeholders.isEmpty()) {
            return Mono.just(template);
        }
        
        log.info("🎯 处理专用占位符: {}", placeholders);
        
        // 解析所有专用占位符
        List<Mono<Map.Entry<String, String>>> resolutions = placeholders.stream()
            .map(placeholder -> {
                return delegateResolver.resolvePlaceholder(placeholder, parameters, userId, novelId)
                    .map(content -> {
                        return Map.entry("{{" + placeholder + "}}", content);
                    })
                    .doOnNext(entry -> log.debug("✅ 专用占位符解析完成: {} -> {} 字符", 
                                                entry.getKey(), entry.getValue().length()));
            })
            .collect(Collectors.toList());
        
        // 并行解析并替换
        return Mono.zip(resolutions, entries -> {
            String result = template;
            for (Object entry : entries) {
                @SuppressWarnings("unchecked")
                Map.Entry<String, String> e = (Map.Entry<String, String>) entry;
                result = result.replace(e.getKey(), e.getValue());
            }
            
            // 🚀 修复：确保在这里标记所有专用占位符对应的内容类型已被处理
            if (contextTracker.get() != null) {
                for (String placeholder : placeholders) {
                    String basePlaceholder = placeholder.contains(":") ? 
                        placeholder.substring(0, placeholder.indexOf(":")) : placeholder;
                    String contentType = SPECIALIZED_PLACEHOLDERS.get(basePlaceholder);
                    if (contentType != null) {
                        contextTracker.get().markContentTypeProcessed(contentType);
                        log.debug("🏷️ 标记内容类型已处理: {} -> {}", basePlaceholder, contentType);
                    }
                }
            }
            
            return result;
        });
    }

    /**
     * 解析上下文占位符（排除已被专用占位符处理的内容类型）
     */
    private Mono<String> resolveContextPlaceholders(String template, List<String> placeholders,
                                                   Map<String, Object> parameters, String userId, String novelId) {
        if (placeholders.isEmpty()) {
            return Mono.just(template);
        }
        
        Set<String> processedTypes = contextTracker.get() != null ? contextTracker.get().getProcessedContentTypes() : Collections.emptySet();
        log.info("🌐 处理上下文占位符，排除已处理的内容类型: {}", processedTypes);
        
        // 🚀 添加调试：验证ThreadLocal是否正常工作
        if (contextTracker.get() != null) {
            log.debug("🧠 ThreadLocal上下文存在，已处理类型: {}", processedTypes);
        } else {
            log.warn("⚠️ ThreadLocal上下文为null！");
        }
        
        // 构建增强的参数，包含排除信息
        Map<String, Object> enhancedParameters = new HashMap<>(parameters);
        if (contextTracker.get() != null) {
            enhancedParameters.put("excludedContentTypes", contextTracker.get().getProcessedContentTypes());
        }
        
        // 获取过滤后的上下文数据，并与请求中显式传入的context/previousChaptersContent合并
        return getFilteredContextData(enhancedParameters, userId, novelId)
            .map(filteredContext -> {
                // 合并顺序：显式context → 过滤后的contextSelections上下文 → previousChaptersContent
                String explicitContext = null;
                Object ctxObj = parameters.get("context");
                if (ctxObj instanceof String && !((String) ctxObj).isBlank()) {
                    explicitContext = (String) ctxObj;
                }

                String previousChapters = null;
                Object prevObj = parameters.get("previousChaptersContent");
                if (prevObj instanceof String && !((String) prevObj).isBlank()) {
                    previousChapters = (String) prevObj;
                }

                StringBuilder merged = new StringBuilder();
                if (explicitContext != null) {
                    merged.append(explicitContext.trim());
                }
                if (filteredContext != null && !filteredContext.isBlank()) {
                    if (merged.length() > 0) merged.append("\n\n");
                    merged.append(filteredContext.trim());
                }
                if (previousChapters != null) {
                    if (merged.length() > 0) merged.append("\n\n");
                    merged.append(previousChapters.trim());
                }

                String mergedContext = merged.toString();
                String result = template;
                for (String placeholder : placeholders) {
                    result = result.replace("{{" + placeholder + "}}", mergedContext);
                }
                log.info("✅ 上下文占位符处理完成，合并内容长度: {} 字符", mergedContext.length());
                return result;
            });
    }

    /**
     * 解析其他占位符
     */
    private Mono<String> resolveOtherPlaceholders(String template, List<String> placeholders,
                                                 Map<String, Object> parameters, String userId, String novelId) {
        if (placeholders.isEmpty()) {
            return Mono.just(template);
        }
        
        log.info("🔧 处理其他占位符: {}", placeholders);
        
        // 解析所有其他占位符
        List<Mono<Map.Entry<String, String>>> resolutions = placeholders.stream()
            .map(placeholder -> {
                return delegateResolver.resolvePlaceholder(placeholder, parameters, userId, novelId)
                    .map(content -> {
                        return Map.entry("{{" + placeholder + "}}", content);
                    });
            })
            .collect(Collectors.toList());
        
        // 并行解析并替换
        return Mono.zip(resolutions, entries -> {
            String result = template;
            for (Object entry : entries) {
                @SuppressWarnings("unchecked")
                Map.Entry<String, String> e = (Map.Entry<String, String>) entry;
                result = result.replace(e.getKey(), e.getValue());
            }
            return result;
        });
    }

    /**
     * 获取过滤后的上下文数据
     * 排除已被专用占位符处理的内容类型
     */
    private Mono<String> getFilteredContextData(Map<String, Object> parameters, String userId, String novelId) {
        @SuppressWarnings("unchecked")
        Set<String> excludedTypes = (Set<String>) parameters.get("excludedContentTypes");
        
        if (excludedTypes == null || excludedTypes.isEmpty()) {
            // 没有需要排除的类型，使用标准的上下文获取逻辑
            return getStandardContextData(parameters, userId, novelId);
        }
        
        log.info("🚫 获取过滤上下文数据，排除类型: {}", excludedTypes);
        
        // 获取用户选择的上下文类型
        @SuppressWarnings("unchecked")
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = 
            (List<UniversalAIRequestDto.ContextSelectionDto>) parameters.get("contextSelections");
            
        if (contextSelections == null || contextSelections.isEmpty()) {
            return Mono.just("");
        }
        
        // 过滤掉已被专用占位符处理的类型
        List<UniversalAIRequestDto.ContextSelectionDto> filteredSelections = contextSelections.stream()
            .filter(selection -> {
                String selectionType = selection.getType() != null ? selection.getType().toLowerCase() : "";
                
                // 🚀 修复：检查是否是专用占位符对应的内容类型
                String mappedContentType = SPECIALIZED_PLACEHOLDERS.get(selectionType);
                boolean shouldExclude = excludedTypes.contains(selectionType) || 
                                      (mappedContentType != null && excludedTypes.contains(mappedContentType));
                
                if (shouldExclude) {
                    log.debug("🚫 排除已处理的上下文选择: {} ({}) -> 映射到: {}", 
                             selection.getTitle(), selectionType, mappedContentType);
                } else {
                    log.debug("✅ 保留上下文选择: {} ({})", selection.getTitle(), selectionType);
                }
                
                return !shouldExclude;
            })
            .collect(Collectors.toList());
            
        log.info("📊 过滤后的上下文选择数量: {} -> {}", contextSelections.size(), filteredSelections.size());
        
        // 使用过滤后的选择获取上下文数据
        return getContextDataFromSelections(filteredSelections, parameters, userId, novelId);
    }

    /**
     * 获取标准的上下文数据（未过滤）
     */
    private Mono<String> getStandardContextData(Map<String, Object> parameters, String userId, String novelId) {
        // 从参数中获取上下文选择
        @SuppressWarnings("unchecked")
        List<UniversalAIRequestDto.ContextSelectionDto> contextSelections = 
            (List<UniversalAIRequestDto.ContextSelectionDto>) parameters.get("contextSelections");
            
        if (contextSelections == null || contextSelections.isEmpty()) {
            return Mono.just("");
        }
        
        return getContextDataFromSelections(contextSelections, parameters, userId, novelId);
    }

    /**
     * 从指定的上下文选择中获取数据
     */
    private Mono<String> getContextDataFromSelections(List<UniversalAIRequestDto.ContextSelectionDto> selections,
                                                     Map<String, Object> parameters, String userId, String novelId) {
        if (selections.isEmpty()) {
            return Mono.just("");
        }
        
        // 并行获取所有选择的内容
        List<Mono<String>> contentMonos = selections.stream()
            .map(selection -> getContentFromSelection(selection, parameters, userId, novelId))
            .collect(Collectors.toList());
        
        return Mono.zip(contentMonos, contents -> {
            return Arrays.stream(contents)
                .map(Object::toString)
                .filter(content -> content != null && !content.trim().isEmpty())
                .collect(Collectors.joining("\n\n"));
        });
    }

    /**
     * 从单个上下文选择中获取内容
     */
    private Mono<String> getContentFromSelection(UniversalAIRequestDto.ContextSelectionDto selection,
                                               Map<String, Object> parameters, String userId, String novelId) {
        String type = selection.getType();
        String id = selection.getId();
        
        if (type == null || id == null) {
            return Mono.just("");
        }
        
        // 通过ContentProvider获取内容
        Optional<ContentProvider> providerOptional = contentProviderFactory.getProvider(type.toLowerCase());
        if (providerOptional.isEmpty()) {
            log.warn("未找到类型为 {} 的ContentProvider", type);
            return Mono.just("");
        }
        
        ContentProvider provider = providerOptional.get();
        return provider.getContentForPlaceholder(userId, novelId, id, parameters)
            .onErrorResume(error -> {
                log.error("获取上下文内容失败: type={}, id={}, error={}", type, id, error.getMessage());
                return Mono.just("");
            });
    }
}