package com.ainovel.server.service.prompt;

import java.util.HashMap;
import java.util.EnumMap;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Autowired;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.domain.model.EnhancedUserPromptTemplate;
import com.ainovel.server.service.impl.content.ContentProviderFactory;
import com.ainovel.server.repository.EnhancedUserPromptTemplateRepository;

import java.time.LocalDateTime;
import java.util.List;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;

/**
 * 基础提示词提供器抽象类
 * 提供通用的提示词处理逻辑
 */
@Slf4j
public abstract class BasePromptProvider implements AIFeaturePromptProvider {

    @Autowired
    protected ContentProviderFactory contentProviderFactory;

    @Autowired
    protected EnhancedUserPromptTemplateRepository enhancedUserPromptTemplateRepository;
    
    @Autowired
    protected ContentPlaceholderResolver placeholderResolver;

    // 占位符匹配模式
    private static final Pattern PLACEHOLDER_PATTERN = Pattern.compile("\\{\\{([^}]+)\\}\\}");

    protected final AIFeatureType featureType;
    protected final Set<String> supportedPlaceholders;
    
    // 🚀 新增：系统模板ID缓存
    private volatile String systemTemplateId;

    protected BasePromptProvider(AIFeatureType featureType) {
        this.featureType = featureType;
        this.supportedPlaceholders = initializeSupportedPlaceholders();
    }

    @Override
    public AIFeatureType getFeatureType() {
        return featureType;
    }

    @Override
    public Set<String> getSupportedPlaceholders() {
        return new HashSet<>(supportedPlaceholders);
    }

    @Override
    public Map<String, String> getPlaceholderDescriptions() {
        return initializePlaceholderDescriptions();
    }

    @Override
    public ValidationResult validatePlaceholders(String content) {
        Set<String> foundPlaceholders = extractPlaceholders(content);
        Set<String> unsupportedPlaceholders = new HashSet<>();
        
        for (String placeholder : foundPlaceholders) {
            if (!supportedPlaceholders.contains(placeholder)) {
                unsupportedPlaceholders.add(placeholder);
            }
        }
        
        boolean valid = unsupportedPlaceholders.isEmpty();
        String message = valid ? "所有占位符都受支持" : 
                        "发现不支持的占位符: " + unsupportedPlaceholders.toString();
        
        return new ValidationResult(valid, message, new HashSet<>(), unsupportedPlaceholders);
    }

    @Override
    public Mono<String> renderPrompt(String template, Map<String, Object> context) {
        return renderPromptWithPlaceholderResolution(template, context, null, null);
    }
    
    /**
     * 渲染提示词，支持完整的占位符解析（包括内容提供器）
     */
    public Mono<String> renderPromptWithPlaceholderResolution(String template, Map<String, Object> context, 
                                                             String userId, String novelId) {
        log.debug("🔧 开始渲染提示词模板，模板长度: {} 字符, userId: {}, novelId: {}", 
                  template.length(), userId, novelId);
        
        Set<String> placeholders = extractPlaceholders(template);
        log.info("📋 提取到占位符: {}", placeholders);
        
        if (context != null && !context.isEmpty()) {
            log.debug("📊 上下文参数: {}", context.keySet());
            // 记录关键参数的值（避免日志过长）
            context.forEach((key, value) -> {
                if (value != null) {
                    String valueStr = value.toString();
                    if (valueStr.length() > 100) {
                        log.debug("   {}: {}... ({}字符)", key, valueStr.substring(0, 100), valueStr.length());
                    } else {
                        log.debug("   {}: {}", key, valueStr);
                    }
                }
            });
        }
        
        // 检查是否包含多个内容提供器占位符，如果是则使用虚拟线程并行处理
        long contentProviderPlaceholders = placeholders.stream()
                .filter(placeholder -> placeholderResolver != null && placeholderResolver.supports(placeholder) && isContentProviderPlaceholder(placeholder))
                .count();
        
        // 🚀 优先使用ContextualPlaceholderResolver进行智能占位符解析
        if (placeholderResolver instanceof com.ainovel.server.service.prompt.impl.ContextualPlaceholderResolver) {
            log.info("🧠 使用智能占位符解析器处理 {} 个占位符", placeholders.size());
            com.ainovel.server.service.prompt.impl.ContextualPlaceholderResolver contextualResolver = 
                    (com.ainovel.server.service.prompt.impl.ContextualPlaceholderResolver) placeholderResolver;
            return contextualResolver.resolveTemplate(template, context, userId, novelId)
                    .doOnNext(result -> log.info("✅ 智能占位符解析完成，结果长度: {} 字符", result.length()));
        } else if (contentProviderPlaceholders > 1 && placeholderResolver instanceof com.ainovel.server.service.prompt.impl.ContentProviderPlaceholderResolver) {
            // 使用虚拟线程并行处理多个内容提供器占位符
            log.info("🚀 检测到{}个内容提供器占位符，使用虚拟线程并行处理", contentProviderPlaceholders);
            com.ainovel.server.service.prompt.impl.ContentProviderPlaceholderResolver resolver = 
                    (com.ainovel.server.service.prompt.impl.ContentProviderPlaceholderResolver) placeholderResolver;
            return resolver.resolveTemplate(template, context, userId, novelId)
                    .doOnNext(result -> log.info("✅ 虚拟线程并行处理完成，结果长度: {} 字符", result.length()));
        } else {
            // 逐个解析占位符（原有逻辑）
            log.info("🔄 逐个解析占位符，总数: {}", placeholders.size());
            Mono<String> result = Mono.just(template);
            
            for (String placeholder : placeholders) {
                result = result.flatMap(currentTemplate -> {
                    log.debug("🔍 处理占位符: {}", placeholder);
                    
                    if (placeholderResolver != null && placeholderResolver.supports(placeholder)) {
                        // 使用占位符解析器获取内容
                        log.debug("  使用占位符解析器处理: {}", placeholder);
                        return placeholderResolver.resolvePlaceholder(placeholder, context, userId, novelId)
                                .map(resolvedContent -> {
                                    String placeholderPattern = "{{" + placeholder + "}}";
                                    String replacedTemplate = currentTemplate.replace(placeholderPattern, resolvedContent);
                                    log.debug("  占位符 {} 解析完成，内容长度: {} 字符", placeholder, resolvedContent.length());
                                    return replacedTemplate;
                                })
                                .doOnError(error -> log.error("  占位符 {} 解析失败: {}", placeholder, error.getMessage()));
                    } else {
                        // 回退到简单的参数替换
                        Object value = (context != null) ? context.get(placeholder) : null;
                        String placeholderPattern = "{{" + placeholder + "}}";
                        String replacement = value != null ? value.toString() : "";
                        log.debug("  简单参数替换: {} -> {} ({}字符)", placeholder, 
                                 replacement.length() > 50 ? replacement.substring(0, 50) + "..." : replacement, 
                                 replacement.length());
                        return Mono.just(currentTemplate.replace(placeholderPattern, replacement));
                    }
                });
            }
            
            return result.doOnNext(finalResult -> log.info("✅ 逐个占位符解析完成，最终结果长度: {} 字符", finalResult.length()));
        }
    }
    
    /**
     * 检查是否是内容提供器占位符
     */
    private boolean isContentProviderPlaceholder(String placeholder) {
        return placeholder.startsWith("full_novel_") || 
               placeholder.equals("scene") || placeholder.startsWith("scene:") ||
               placeholder.equals("chapter") || placeholder.startsWith("chapter:") ||
               placeholder.equals("act") || placeholder.startsWith("act:") ||
               placeholder.equals("setting") || placeholder.startsWith("setting:") ||
               placeholder.equals("snippet") || placeholder.startsWith("snippet:");
    }

    @Override
    public Mono<String> getSystemPrompt(String userId, Map<String, Object> parameters) {
        log.info("🚀 BasePromptProvider.getSystemPrompt - featureType: {}, userId: {}, parameters数量: {}", 
                 featureType, userId, parameters != null ? parameters.size() : 0);
        String novelId = extractNovelId(parameters);
        log.debug("提取的novelId: {}", novelId);

        // 优先：显式模板ID（支持 public_ / system_default_ 前缀）
        Mono<String> explicitTemplateMono = Mono.defer(() -> {
            String tid = extractTemplateIdFromParameters(parameters);
            if (tid == null || tid.isEmpty()) return Mono.empty();
            return findTemplateByIdRelaxed(userId, tid)
                    .map(t -> t.getSystemPrompt())
                    .filter(sp -> sp != null && !sp.trim().isEmpty());
        });

        Mono<String> templateMono = explicitTemplateMono
                // 其次：当前用户自定义系统模板
                .switchIfEmpty(loadCustomSystemPrompt(userId))
                // 然后：数据库 system 账户系统模板
                .switchIfEmpty(loadSystemAccountSystemPrompt())
                // 最后：内置默认模板
                .switchIfEmpty(Mono.fromCallable(this::getDefaultSystemPrompt));

        return templateMono
                .flatMap(template ->
                    renderPromptWithPlaceholderResolution(template, parameters, userId, novelId)
                        .flatMap(rendered -> {
                            if (rendered == null || rendered.trim().isEmpty()) {
                                // 再次使用默认模板渲染一次兜底
                                log.warn("系统提示词渲染为空，使用默认模板二次渲染兜底");
                                return renderPromptWithPlaceholderResolution(getDefaultSystemPrompt(), parameters, userId, novelId);
                            }
                            return Mono.just(rendered);
                        })
                )
                .doOnNext(res -> log.info("✅ 系统提示词最终长度: {} 字符", res.length()))
                .onErrorResume(err -> {
                    log.error("系统提示词渲染失败，返回默认简短提示: {}", err.getMessage());
                    return Mono.just("你是一位专业的AI助手，请根据用户的要求提供帮助。");
                });
    }

    @Override
    public Mono<String> getUserPrompt(String userId, String templateId, Map<String, Object> parameters) {
        log.info("🚀 BasePromptProvider.getUserPrompt - featureType: {}, userId: {}, templateId: {}, parameters数量: {}", 
                 featureType, userId, templateId, parameters != null ? parameters.size() : 0);
        String novelId = extractNovelId(parameters);
        log.debug("提取的novelId: {}", novelId);

        Mono<String> templateMono;
        if (templateId != null && !templateId.isEmpty()) {
            templateMono = loadCustomUserPrompt(userId, templateId)
                            .switchIfEmpty(Mono.fromCallable(this::getDefaultUserPrompt));
        } else {
            templateMono = loadCustomUserPrompt(userId, null)
                            .switchIfEmpty(Mono.fromCallable(this::getDefaultUserPrompt));
        }

        return templateMono.flatMap(template ->
                renderPromptWithPlaceholderResolution(template, parameters, userId, novelId)
                    .flatMap(rendered -> {
                        if (rendered == null || rendered.trim().isEmpty()) {
                            log.warn("用户提示词渲染为空，使用默认模板二次渲染兜底");
                            return renderPromptWithPlaceholderResolution(getDefaultUserPrompt(), parameters, userId, novelId);
                        }
                        return Mono.just(rendered);
                    })
        ).doOnNext(res -> log.info("✅ 用户提示词最终长度: {} 字符", res.length()))
         .onErrorResume(err -> {
             log.error("用户提示词渲染失败，返回简单占位符: {}", err.getMessage());
             return Mono.just("{{input}}");
         });
    }
    
    /**
     * 从参数中提取novelId
     */
    private String extractNovelId(Map<String, Object> parameters) {
        Object novelId = parameters.get("novelId");
        return novelId != null ? novelId.toString() : null;
    }

    /**
     * 加载用户自定义系统提示词
     */
    protected Mono<String> loadCustomSystemPrompt(String userId) {
        log.debug("🔍 查找用户自定义系统提示词 - userId: {}, featureType: {}", userId, featureType);
        
        // 首先尝试查找默认模板
        return enhancedUserPromptTemplateRepository.findByUserIdAndFeatureTypeAndIsDefaultTrue(userId, featureType)
                .filter(template -> template.getSystemPrompt() != null && !template.getSystemPrompt().trim().isEmpty())
                .map(template -> {
                    log.info("✅ 找到用户默认系统提示词，长度: {} 字符", template.getSystemPrompt().length());
                    return template.getSystemPrompt();
                })
                .switchIfEmpty(
                    // 如果没有默认模板，则查找第一个有系统提示词的模板
                    enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType(userId, featureType)
                            .filter(template -> template.getSystemPrompt() != null && !template.getSystemPrompt().trim().isEmpty())
                            .sort((t1, t2) -> t1.getCreatedAt().compareTo(t2.getCreatedAt())) // 按创建时间排序
                            .next() // 取第一个有系统提示词的模板
                            .map(template -> {
                                log.info("✅ 找到用户自定义系统提示词（非默认），长度: {} 字符", template.getSystemPrompt().length());
                                return template.getSystemPrompt();
                            })
                )
                .onErrorResume(error -> {
                    log.debug("未找到用户自定义系统提示词: {}", error.getMessage());
                    return Mono.empty();
                });
    }

    /**
     * 从数据库加载 system 账号下的系统提示词模板
     * 优先用于系统级默认模板回退。
     */
    protected Mono<String> loadSystemAccountSystemPrompt() {
        log.debug("🔍 查找 system 账户系统提示词 - featureType: {}", featureType);
        // 优先尝试使用已缓存的系统模板ID
        String sysId = getSystemTemplateId();
        if (sysId != null && !sysId.isEmpty()) {
            return enhancedUserPromptTemplateRepository.findById(sysId)
                    .filter(this::isAllowedPublicOrSystem)
                    .map(t -> t.getSystemPrompt())
                    .filter(sp -> sp != null && !sp.trim().isEmpty())
                    .switchIfEmpty(
                        // 回退到按 featureType 检索 system 账户模板
                        enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType("system", featureType)
                                .filter(t -> t.getSystemPrompt() != null && !t.getSystemPrompt().trim().isEmpty())
                                .map(t -> t.getSystemPrompt())
                                .next()
                    )
                    .onErrorResume(error -> {
                        log.debug("未找到缓存的 system 模板: {}", error.getMessage());
                        return Mono.empty();
                    });
        }

        // 直接按 featureType 检索 system 账户模板
        return enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType("system", featureType)
                .filter(t -> t.getSystemPrompt() != null && !t.getSystemPrompt().trim().isEmpty())
                .map(t -> t.getSystemPrompt())
                .next()
                .onErrorResume(error -> {
                    log.debug("未找到 system 账户系统提示词: {}", error.getMessage());
                    return Mono.empty();
                });
    }

    /**
     * 加载用户自定义用户提示词
     */
    protected Mono<String> loadCustomUserPrompt(String userId, String templateId) {
        log.debug("🔍 查找用户自定义用户提示词 - userId: {}, templateId: {}, featureType: {}", userId, templateId, featureType);
        
        if (templateId != null && !templateId.isEmpty()) {
            // 放宽权限：允许当前用户 / 公开 / system 模板
            return findTemplateByIdRelaxed(userId, templateId)
                    .map(t -> {
                        log.info("✅ 通过templateId找到用户提示词，长度: {} 字符", t.getUserPrompt() != null ? t.getUserPrompt().length() : 0);
                        return t.getUserPrompt();
                    })
                    .onErrorResume(error -> {
                        log.debug("未找到指定的用户提示词模板: {}", error.getMessage());
                        return Mono.empty();
                    });
        }
        
        // 首先尝试查找默认模板
        return enhancedUserPromptTemplateRepository.findByUserIdAndFeatureTypeAndIsDefaultTrue(userId, featureType)
                .filter(template -> template.getUserPrompt() != null && !template.getUserPrompt().trim().isEmpty())
                .map(template -> {
                    log.info("✅ 找到用户默认用户提示词，长度: {} 字符", template.getUserPrompt().length());
                    return template.getUserPrompt();
                })
                .switchIfEmpty(
                    // 如果没有默认模板，则查找第一个有用户提示词的模板
                    enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType(userId, featureType)
                            .filter(template -> template.getUserPrompt() != null && !template.getUserPrompt().trim().isEmpty())
                            .sort((t1, t2) -> t1.getCreatedAt().compareTo(t2.getCreatedAt())) // 按创建时间排序
                            .next() // 取第一个有用户提示词的模板
                            .map(template -> {
                                log.info("✅ 找到用户自定义用户提示词（非默认），长度: {} 字符", template.getUserPrompt().length());
                                return template.getUserPrompt();
                            })
                )
                .onErrorResume(error -> {
                    log.debug("未找到用户自定义用户提示词: {}", error.getMessage());
                    return Mono.empty();
                });
    }

    // ==================== Helper methods ====================

    /**
     * 从 parameters 中提取模板ID，兼容 promptTemplateId / associatedTemplateId，并处理 public_ / system_default_ 前缀。
     */
    private String extractTemplateIdFromParameters(Map<String, Object> parameters) {
        if (parameters == null) return null;
        Object raw = parameters.get("promptTemplateId");
        if (!(raw instanceof String) || ((String) raw).isEmpty()) {
            raw = parameters.get("associatedTemplateId");
        }
        if (!(raw instanceof String)) return null;
        String tid = (String) raw;
        if (tid.startsWith("public_")) {
            return tid.substring("public_".length());
        }
        // system_default_* 留给 findTemplateByIdRelaxed 解析
        return tid;
    }

    /**
     * 允许读取：当前用户、公开模板、system 作者或归属的模板。
     * 同时支持处理 public_ / system_default_ 前缀。
     */
    private Mono<EnhancedUserPromptTemplate> findTemplateByIdRelaxed(String userId, String templateId) {
        if (templateId == null || templateId.isEmpty()) return Mono.empty();

        if (templateId.startsWith("public_")) {
            templateId = templateId.substring("public_".length());
        }

        if (templateId.startsWith("system_default_")) {
            // 优先使用缓存的系统模板ID；否则按 featureType 从 system 账户取一个
            String sysId = getSystemTemplateId();
            if (sysId != null && !sysId.isEmpty()) {
                return enhancedUserPromptTemplateRepository.findById(sysId)
                        .filter(this::isAllowedPublicOrSystem)
                        .switchIfEmpty(
                                enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType("system", featureType).next()
                        );
            }
            return enhancedUserPromptTemplateRepository.findByUserIdAndFeatureType("system", featureType).next();
        }

        final String id = templateId;
        return enhancedUserPromptTemplateRepository.findById(id)
                .filter(t -> isAllowedForUser(userId, t));
    }

    private boolean isAllowedForUser(String userId, EnhancedUserPromptTemplate t) {
        if (t == null) return false;
        if (t.getUserId() != null && t.getUserId().equals(userId)) return true;
        if (Boolean.TRUE.equals(t.getIsPublic())) return true;
        return isSystemTemplate(t);
    }

    private boolean isAllowedPublicOrSystem(EnhancedUserPromptTemplate t) {
        if (t == null) return false;
        if (Boolean.TRUE.equals(t.getIsPublic())) return true;
        return isSystemTemplate(t);
    }

    private boolean isSystemTemplate(EnhancedUserPromptTemplate t) {
        String uid = t.getUserId();
        String author = t.getAuthorId();
        return (uid != null && uid.equals("system")) || (author != null && author.equals("system"));
    }

    /**
     * 提取占位符
     */
    private Set<String> extractPlaceholders(String content) {
        Set<String> placeholders = new HashSet<>();
        Matcher matcher = PLACEHOLDER_PATTERN.matcher(content);
        
        while (matcher.find()) {
            placeholders.add(matcher.group(1).trim());
        }
        
        return placeholders;
    }

    /**
     * 初始化支持的占位符
     * 子类需要实现此方法
     */
    protected abstract Set<String> initializeSupportedPlaceholders();

    /**
     * 初始化占位符描述信息
     * 子类可以重写此方法提供更详细的描述
     */
    protected Map<String, String> initializePlaceholderDescriptions() {
        Map<String, String> descriptions = new HashMap<>();
        
        // 基础占位符描述
        descriptions.put("input", "用户输入的主要内容");
        descriptions.put("context", "相关的上下文信息");
        descriptions.put("novelTitle", "小说标题");
        descriptions.put("authorName", "作者姓名");
        
        // 内容提供器占位符描述
        descriptions.put("full_novel_text", "完整小说正文内容");
        descriptions.put("full_novel_summary", "完整小说摘要");
        descriptions.put("scene", "指定场景内容");
        descriptions.put("chapter", "指定章节内容");
        descriptions.put("act", "指定卷/部内容");
        descriptions.put("setting", "指定设定内容");
        descriptions.put("snippet", "指定片段内容");
        
        return descriptions;
    }

    // ==================== 🚀 新增：模板初始化相关方法 ====================

    @Override
    public Mono<String> initializeSystemTemplate() {
        log.info("🚀 开始初始化系统模板: featureType={}, templateIdentifier={}", 
                featureType, getTemplateIdentifier());
        
        // 检查数据库中是否已存在系统模板
        return enhancedUserPromptTemplateRepository.findByUserId("system")
                .filter(template -> 
                    template.getFeatureType() == featureType
                )
                .next()
                .map(existingTemplate -> {
                    log.info("✅ 系统模板已存在: templateId={}, name={}", 
                            existingTemplate.getId(), existingTemplate.getName());
                    this.systemTemplateId = existingTemplate.getId();
                    return existingTemplate.getId();
                })
                .switchIfEmpty(createSystemTemplate())
                .doOnSuccess(templateId -> {
                    this.systemTemplateId = templateId;
                    log.info("✅ 系统模板初始化完成: featureType={}, templateId={}", 
                            featureType, templateId);
                })
                .doOnError(error -> log.error("❌ 系统模板初始化失败: featureType={}, error={}", 
                        featureType, error.getMessage(), error));
    }

    @Override
    public String getSystemTemplateId() {
        return systemTemplateId;
    }

    @Override
    public String getTemplateName() {
        return getTemplateIdentifier();
    }

    @Override
    public String getTemplateDescription() {
        return "系统默认的" + getFeatureDisplayName() + "提示词模板";
    }

    @Override
    public String getTemplateIdentifier() {
        return featureType.name() + "_1";
    }

    /**
     * 创建系统模板
     */
    private Mono<String> createSystemTemplate() {
        log.info("📝 创建新的系统模板: featureType={}, templateIdentifier={}", 
                featureType, getTemplateIdentifier());
        
        EnhancedUserPromptTemplate systemTemplate = EnhancedUserPromptTemplate.builder()
                .userId("system")
                .featureType(featureType)
                .name(getTemplateIdentifier())
                .description(getTemplateDescription())
                .systemPrompt(getDefaultSystemPrompt())
                .userPrompt(getDefaultUserPrompt())
                .tags(List.of("系统预设", "默认模板", getFeatureDisplayName()))
                .categories(List.of("系统", featureType.name()))
                .isPublic(true)
                .isVerified(true)
                .isDefault(false) // 系统模板不设为默认
                .authorId("system")
                .version(1)
                .language("zh")
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
        
        return enhancedUserPromptTemplateRepository.save(systemTemplate)
                .map(savedTemplate -> {
                    log.info("✅ 系统模板创建成功: templateId={}, name={}, featureType={}", 
                            savedTemplate.getId(), savedTemplate.getName(), featureType);
                    return savedTemplate.getId();
                })
                .doOnError(error -> log.error("❌ 系统模板创建失败: featureType={}, error={}", 
                        featureType, error.getMessage(), error));
    }

    /**
     * 获取功能类型的显示名称
     */
    private String getFeatureDisplayName() {
        return FEATURE_DISPLAY_NAME_MAP.getOrDefault(featureType, featureType.name());
    }

    // 使用 EnumMap 避免编译器为 enum switch 生成合成内部类（如 BasePromptProvider$1）
    private static final Map<AIFeatureType, String> FEATURE_DISPLAY_NAME_MAP = createFeatureDisplayNameMap();

    private static Map<AIFeatureType, String> createFeatureDisplayNameMap() {
        Map<AIFeatureType, String> map = new EnumMap<>(AIFeatureType.class);
        map.put(AIFeatureType.TEXT_EXPANSION, "文本扩写");
        map.put(AIFeatureType.TEXT_REFACTOR, "文本重构");
        map.put(AIFeatureType.TEXT_SUMMARY, "文本总结");
        map.put(AIFeatureType.AI_CHAT, "AI聊天");
        map.put(AIFeatureType.SCENE_TO_SUMMARY, "场景摘要");
        map.put(AIFeatureType.SUMMARY_TO_SCENE, "摘要生成场景");
        map.put(AIFeatureType.NOVEL_GENERATION, "小说生成");
        map.put(AIFeatureType.PROFESSIONAL_FICTION_CONTINUATION, "专业小说续写");
        map.put(AIFeatureType.SETTING_TREE_GENERATION, "设定树生成");
        return Collections.unmodifiableMap(map);
    }
} 