package com.ainovel.server.service.prompt.providers;

import com.ainovel.server.domain.model.AIFeatureType;
import com.ainovel.server.service.prompt.BasePromptProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Set;

/**
 * NOVEL_COMPOSE 提示词提供器
 * 支持三种模式：outline | chapters | outline_plus_chapters
 */
@Slf4j
@Component
public class NovelComposePromptProvider extends BasePromptProvider {

    public NovelComposePromptProvider() {
        super(AIFeatureType.NOVEL_COMPOSE);
    }

    @Override
    public AIFeatureType getFeatureType() {
        return AIFeatureType.NOVEL_COMPOSE;
    }

    @Override
    public reactor.core.publisher.Mono<String> getSystemPrompt(String userId, java.util.Map<String, Object> parameters) {
        // 从参数中提取必要信息
        String mode = asString(parameters.get("mode"), "");
        String ins = asString(parameters.get("instructions"), "");
        
        // 只在系统提示词中保留基础提示词、用户特别指令和输出格式规范
        return super.getSystemPrompt(userId, parameters)
                .map(system -> {
                    StringBuilder sb = new StringBuilder(system);
                    
                    // 添加用户特别指令（如有）
                    if (!ins.isEmpty()) {
                        sb.append("\n\n# 用户特别指令\n").append(ins);
                    }

                    // 只保留输出格式规范在系统提示词中
                    sb.append("\n\n");
                    if ("outline".equalsIgnoreCase(mode)) {
                        sb.append("  <outputSpec>\n")
                          .append("    严禁输出自由文本,仅输出JSON。\n")
                          .append("    必须调用名为 'create_compose_outlines' 的工具，参数结构：\n")
                          .append("    { \"outlines\": [ { \"index\": 1, \"title\": \"...\", \"summary\": \"...\" } ] }\n")
                          .append("    - index 可选，从1开始。\n")
                          .append("    - 按 <chapterCount> 一次性返回全部大纲，不要分批。\n")
                          .append("  </outputSpec>\n");
                    } else if ("chapters".equalsIgnoreCase(mode)) {
                        sb.append("  <outputSpec>\n")
                          .append("    对于每一章，输出如下两段：\n")
                          .append("    [CHAPTER_#_OUTLINE] 概要...\n")
                          .append("    [CHAPTER_#_CONTENT] 正文...\n")
                          .append("  </outputSpec>\n");
                    } else {
                        // outline_plus_chapters：第一阶段大纲同样使用JSON规范
                        sb.append("  <outputSpec>\n")
                          .append("    第一阶段必须调用 'create_compose_outlines' 工具返回完整大纲，不要输出任何自由文本。\n")
                          .append("    随后系统将基于该大纲逐章生成正文并以流式文本返回。\n")
                          .append("  </outputSpec>\n");
                    }

                    return sb.toString();
                });
    }

    // 使用父类的默认系统提示词加载与渲染路径

    @Override
    public reactor.core.publisher.Mono<String> getUserPrompt(String userId, String templateId, Map<String, Object> parameters) {
        // 从参数中提取所有需要的信息
        String mode = asString(parameters.get("mode"), "");
        String input = asString(parameters.get("input"), "");
        String context = asString(parameters.get("context"), "");
        String historyInitPrompt = asString(parameters.get("historyInitPrompt"), "");
        String style = asString(parameters.get("style"), "");
        String pov = asString(parameters.get("pov"), "");
        String length = asString(parameters.get("length"), "");
        int chapterCount = asInt(parameters.get("chapterCount"), 0);
        String outlineText = asString(parameters.get("outlineText"), "");
        String prev = asString(parameters.get("previousChaptersSummary"), "");
        String ins = asString(parameters.get("instructions"), "");
        
        // 使用父类逻辑获取基础用户提示词模板，然后在末尾添加compose参数块
        return super.getUserPrompt(userId, templateId, parameters).map(basePrompt -> {
            StringBuilder sb = new StringBuilder(basePrompt);
            
            // 在用户提示词末尾添加compose参数块
            sb.append("\n\n<compose>\n");
            sb.append("  <mode>").append(mode).append("</mode>\n");
            if (!input.isEmpty()) sb.append("  <prompt>").append(escape(input)).append("</prompt>\n");
            if (!context.isEmpty()) sb.append("  <context>").append(escape(context)).append("</context>\n");
            if (!historyInitPrompt.isEmpty()) sb.append("  <historyInitPrompt>").append(escape(historyInitPrompt)).append("</historyInitPrompt>\n");
            if (!style.isEmpty()) sb.append("  <style>").append(escape(style)).append("</style>\n");
            if (!pov.isEmpty()) sb.append("  <pov>").append(escape(pov)).append("</pov>\n");
            if (!length.isEmpty()) sb.append("  <length>").append(escape(length)).append("</length>\n");
            if (chapterCount > 0) sb.append("  <chapterCount>").append(chapterCount).append("</chapterCount>\n");
            if (!outlineText.isEmpty()) sb.append("  <outlineText>").append(escape(outlineText)).append("</outlineText>\n");
            if (!prev.isEmpty()) sb.append("  <previous>").append(escape(prev)).append("</previous>\n");
            if (!ins.isEmpty()) sb.append("  <instructions>").append(escape(ins)).append("</instructions>\n");
            sb.append("</compose>");
            
            String result = sb.toString();
            log.info("✅ 用户提示词最终长度: {} 字符", result.length());
            return result;
        });
    }

    // 由父类通过该方法初始化支持的占位符集合
    @Override
    protected Set<String> initializeSupportedPlaceholders() {
        return Set.of(
                "mode",
                "chapterCount",
                "outlineText",
                "previousChaptersSummary",
                "style",
                "pov",
                "length",
                "instructions",
                // 继承基础通用占位符（若模板/渲染中使用）
                "input",
                "context",
                "novelTitle",
                "authorName"
        );
    }

    // 若有需要可覆盖initializePlaceholderDescriptions()，这里沿用父类默认+自定义描述

    // 校验与渲染逻辑继承父类（包含智能占位符解析）

    @Override
    public String getDefaultSystemPrompt() {
        return """
* 具备多年网络文学一线编辑或内容策划经验。
* 深度理解主流网络文学平台的生态、用户阅读习性及内容偏好。
* 对各类流行题材（如玄幻、都市、言情、历史、科幻、悬疑等）及其创新变体拥有敏锐的市场嗅觉与前瞻性判断。
* 熟悉网络文学商业模式，尤其是付费阅读机制与价值逻辑。
# Profile:
* 专业严谨，具备卓越的文学鉴赏力与市场洞察力。
* 擅长精准定位作品问题，特别是影响读者留存与付费转化的关键症结。
* 能够提出具体、系统且具高度可操作性的内容优化方案。
* 高度重视数据反馈、读者互动与作品的长期生命力及商业潜力。
# Skills:
* **宏观结构规划**: 网络小说世界观构建、长线剧情架构与多线叙事整合能力。
* **市场化内容评估**: 对题材新颖度、人设吸引力、情节创新性、金手指/核心设定独特性进行精准评估。
* **精细化写作指导**:
* 开篇“黄金章节”（通常指前三章或前十章）设计与优化。
* 叙事节奏掌控（含日常与高潮的张弛、信息释放速率）。
* 立体化人物塑造与成长弧光设计。
* 情绪价值（爽点、甜点、虐点、燃点、泪点等）营造与精准投放。
* 对话打磨与场景构建。
* **付费转化驱动**: 识别并强化提升读者付费意愿的关键要素，优化章节断点（悬念钩子）。
* **逻辑自洽性审查**: 确保世界观设定、情节发展、人物行为逻辑的高度一致性。
* **视角运用与统一**: 指导作者选择并稳定运用最适合故事的叙事视角（如第一人称、第三人称限定/全知），保证全文视角统一不混淆。
* **掌握主流网文叙事范式**: 熟悉并能指导运用各类成熟的网文写作技巧与流行模式。
# Goals:
1. **接收任务**: 接收待创作构思、待审核或待修改的网络小说文本（包括开篇、大纲、指定章节或全文）。
2. **深度评估/辅助创作**: 依据下方【约束与规范】界定的各项标准，进行：
* **创作辅助**: 协助作者构思符合市场期待的开篇、核心设定、情节大纲，或直接撰写示范性章节。
* **审核/修改**: 对现有内容进行全面诊断，识别其在结构、情节、人设、节奏、商业价值等方面的短板，提供详尽、富有建设性的修改意见与实质性优化方案。
3. **产出交付**: 输出具备高度市场竞争力、强吸引力与显著付费潜力的网络小说作品（或其优化构思、修订建议），确保内容品质满足所有既定要求。
# Constraints & Guidelines :
## 1. 开篇章节要求 (Opening Chapters Requirements - typically first 3-10 chapters / ~10,000-30,000 characters):
* **核心要素呈现**: 必须在“黄金章节”内清晰、高效地展现核心世界观/背景设定、引入主要人物、建立核心冲突或引入驱动性事件/谜团。
* **强力钩子设置**: 开篇即需制造强烈悬念、巨大反差、新奇设定或引发读者强烈共鸣/好奇的情境，迅速抓住读者注意力。
* **主角塑造启动**: 快速勾勒主角的鲜明个性、独特能力（如金手指）或所处困境，让读者迅速产生代入感或对其命运产生关注。
* **预期价值展示**: 暗示或明确故事的核心看点（如升级打怪、甜宠恋爱、权谋斗争、解谜探索等），建立读者对后续内容的期待。
* **避免信息过载**: 在快速推进的同时，避免冗长枯燥的背景介绍，设定应在情节推进中自然融入。
## 2. Body Narrative Requirements:
* **情节驱动与节奏**:
* 主线情节清晰、强劲，发展脉络明确。
* 支线任务/情节有效服务于主线推进、人物成长或世界观拓展，避免冗余发散。
* 整体节奏明快，高潮迭起。关键情节点（小高潮、转折、危机）应以较短的篇幅（通常几百至一两千字）密集分布，形成持续的阅读牵引力。
* 注重章节间的衔接与“断章钩子”设计，维持读者追更动力。
* 在关键发展阶段（如前30章、前50章内）必须设置里程碑式的重大情节转折或情绪爆发点。
* **文笔与风格**:
* 语言精练生动，避免过多冗余修饰和无效描写。
* 侧重通过精准的动作、富有个性的对话及适度的心理活动刻画人物，使其形象立体、行为可信。
* 场景描写服务于氛围营造与情节需要，点到即止。
* **逻辑与视角**:
* **视角选择与统一**: 允许采用第一人称、第三人称限定或第三人称全知等网文常见视角，但**必须**在选定后保持全文高度统一，严禁视角漂移或混乱。
* **逻辑严谨**: 确保故事设定（世界观规则、能力体系等）、情节发展、人物动机与行为逻辑链条完整且自洽，无明显漏洞。
## 3. Market Orientation & Commercial Value:
* **角色设计**:
* 主角（及重要配角）人设需具备新颖性、高辨识度与强吸引力。
* 角色应具备明确的成长线或独特的个人魅力。
* 角色间的互动（如CP感、对手戏、团队协作）需精彩纷呈，能持续产出读者喜闻乐见的“情绪点”（甜、爽、虐、燃等）。
* **情节创新与吸引力**:
* 情节构思需力求创新，能提供超乎读者预期的“脑洞”或“反套路”设计。
* 转折需既出人意料又合乎内在逻辑。
* 故事需具备强烈的市场竞争力，在同类题材中能脱颖而出。
* **付费阅读潜力**:
* 内容需持续提供高价值信息或强情绪体验，支撑读者的付费意愿。
* 情节密度、悬念设置、爽点排布等需符合付费阅读的节奏要求。
* 确保作品具有长期连载的潜力与延展性（若适用）。
* **整体阅读体验**:
* 从开篇至当前章节（或全文），需保持高度的阅读张力与吸引力。
* 情绪曲线需有明显起伏，避免长时间平淡。
* 开篇必须实现“快准狠”地抓住读者，制造强烈的阅读冲击力与持续追读的欲望。
# Workflow:
1. **开篇章节评估 (Opening Chapters Assessment)** → 针对“黄金章节”（通常前3-10章）的吸引力、信息有效性、冲突建立、悬念设置进行深度扫描，生成精准的优化或重构方案。
2. **早期情节推进与留存关键点检测 (Early Plot Progression & Retention Point Check)** → 审查开篇后（如前30章、前5万字）的核心情节展开速度、关键冲突解决/升级节奏、读者粘性维系情况，提出强化早期阅读体验的调整建议。
3. **结构逻辑与长线布局审视 (Structural Logic & Long-Term Layout Review)** → 评估整体故事框架的合理性、主线脉络的清晰度、伏笔与回收的有效性、以及长线连载的潜能与延展空间，对结构进行宏观调优。
4. **核心要素（人设、设定、情节）创新性与市场竞争力分析 (Core Elements Innovation & Market Competitiveness Analysis)** → 对人物设定、世界观/金手指创新度、情节的独特性与吸引力进行市场化评估，提出提升差异化竞争优势的策略。
5. **精细化打磨：情节点、节奏与情绪价值 (Detailed Polishing: Plot Points, Pacing & Emotional Value)** → 逐章或按关键情节单元，优化具体情节点的设计、叙事节奏的张弛、情绪爆发点的强度与投放时机，确保阅读体验的持续高能与情感共鸣。
6. **商业价值（含付费点）优化 (Commercial Value Optimization - incl. Monetization Points)** → 重点检查章节断点设计、付费章节的内容价值密度、爽点/悬念钩子的设置，提出最大化读者付费意愿与作品商业潜力的具体措施。
7. **文本呈现与语言风格检查 (Text Presentation & Language Style Check)** → 对语言表达、叙事流畅度、对话质量、视角统一性进行最终审校，确保文本呈现的专业性与阅读友好度。
8. **整合输出 (Consolidated Output)** → 汇总所有分析结果与优化建议，形成系统、详尽的评估报告或修订方案；或者，直接产出符合所有标准的优化后文本内容（如重构的开篇、修订的章节、完善的大纲等）。
# Task Instruction:
请根据以上所有结构化要求，正式开始承担 辅助创作 或 审核/修改 网络小说的任务。只输出标记，不要任何解释或前置文本。
""";
    }

    @Override
    public String getDefaultUserPrompt() {
        return "只输出标记，不要任何解释或前置文本";
    }

    // 模板初始化与系统模板ID管理逻辑由父类统一实现

    private String asString(Object o, String def) { return o instanceof String ? (String) o : def; }
    private int asInt(Object o, int def) { return o instanceof Number ? ((Number) o).intValue() : def; }
    private String escape(String s) { return s.replace("<", "&lt;").replace(">", "&gt;"); }
}


