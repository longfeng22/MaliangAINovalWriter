package com.ainovel.server.common.util;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

/**
 * XML格式化测试
 * 验证紧凑格式化的效果
 */
public class PromptXmlFormatterFormatTest {

    private PromptXmlFormatter formatter;

    @BeforeEach
    void setUp() {
        formatter = new PromptXmlFormatter();
    }

    @Test
    void testUserPromptFormatting() {
        String action = "请扩写以下文本内容";
        String input = "宝穿着一件有些褪色的蓝色小棉袄，袖口上还缝着妈妈亲手绣的小黄鸭图案。";
        String context = "这是一个温馨的乡村故事";
        String length = "triple";
        String style = "温暖";
        String tone = "第三人称";

        String result = formatter.formatUserPrompt(action, input, context, length, style, tone);

        System.out.println("格式化后的用户提示词：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");

        // 验证格式特征
        assert !result.contains("<?xml"); // 不应包含XML声明
        assert result.contains("<task>"); // 应包含根标签
        assert result.contains("<action>\n" + action + "\n</action>"); // 内容应正确分离
        assert !result.contains("\n\n"); // 不应有多余空行
        assert !result.contains("><"); // 内容不应与标签连在一起
    }

    @Test
    void testSystemPromptFormatting() {
        String role = "你是一位专业的小说助手";
        String instructions = "请帮助用户完成小说创作";
        String context = "当前正在创作温馨的乡村小说";
        String length = "适中";
        String style = "温暖人心";
        
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("temperature", 0.8);
        parameters.put("maxTokens", 2000);

        String result = formatter.formatSystemPrompt(role, instructions, context, length, style, parameters);

        System.out.println("格式化后的系统提示词：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");

        // 验证格式特征
        assert !result.contains("<?xml"); // 不应包含XML声明
        assert result.contains("<system>"); // 应包含根标签
        assert result.contains("<role>\n  " + role); // 内容应在新行
        assert !result.contains("\n\n"); // 不应有多余空行
    }

    @Test
    void testChatMessageFormatting() {
        String message = "请帮我分析一下这个角色的性格特点";
        String context = "角色：小宝，年龄8岁，乡村儿童";

        String result = formatter.formatChatMessage(message, context);

        System.out.println("格式化后的聊天消息：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");

        // 验证格式特征
        assert !result.contains("<?xml"); // 不应包含XML声明
        assert result.contains("<message>"); // 应包含根标签
        assert result.contains("<content>\n  " + message); // 内容应在新行
        assert !result.contains("\n\n"); // 不应有多余空行
    }
} 