package com.ainovel.server.common.util;

/**
 * 简单XML测试
 */
public class SimpleXmlTest {
    
    public static void main(String[] args) {
        PromptXmlFormatter formatter = new PromptXmlFormatter();
        
        // 测试用户提示词格式化
        String result = formatter.formatUserPrompt(
            "请扩写以下文本内容",
            "宝穿着一件有些褪色的蓝色小棉袄",
            "这是一个温馨的乡村故事",
            "triple",
            "温暖",
            "第三人称"
        );
        
        System.out.println("=== 格式化结果 ===");
        System.out.println(result);
        System.out.println("===================");
        
        // 检查是否修复了内容与标签连接的问题
        if (result.contains("><")) {
            System.out.println("❌ 仍然存在内容与标签连接的问题");
        } else {
            System.out.println("✅ 内容与标签正确分离");
        }
        
        // 检查是否有多余空行
        if (result.contains("\n\n")) {
            System.out.println("❌ 仍然存在多余空行");
        } else {
            System.out.println("✅ 没有多余空行");
        }
        
        // 检查XML声明
        if (result.contains("<?xml")) {
            System.out.println("❌ 包含了不必要的XML声明");
        } else {
            System.out.println("✅ 没有XML声明");
        }
        
        // 显示行分解
        System.out.println("\n=== 行分解 ===");
        String[] lines = result.split("\n");
        for (int i = 0; i < lines.length; i++) {
            System.out.println(String.format("%2d: '%s'", i + 1, lines[i]));
        }
    }
} 