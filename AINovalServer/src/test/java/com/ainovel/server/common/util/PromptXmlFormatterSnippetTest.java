package com.ainovel.server.common.util;

import com.ainovel.server.domain.model.NovelSnippet;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * PromptXmlFormatter 片段格式化测试
 */
@SpringBootTest
public class PromptXmlFormatterSnippetTest {

    private PromptXmlFormatter formatter;

    @BeforeEach
    void setUp() {
        formatter = new PromptXmlFormatter();
    }

    @Test
    void testFormatSnippet() {
        // 创建测试片段数据
        NovelSnippet snippet = new NovelSnippet();
        snippet.setId("snippet_001");
        snippet.setTitle("角色描述模板");
        snippet.setNotes("用于描述主要角色的外貌特征");
        snippet.setContent("这个角色有着明亮的眼睛，温和的笑容，总是穿着朴素的衣服。");
        snippet.setCategory("角色描述");
        
        List<String> tags = Arrays.asList("主角", "外貌", "性格");
        snippet.setTags(tags);

        // 执行格式化
        String result = formatter.formatSnippet(snippet);

        // 验证结果
        assertNotNull(result, "格式化结果不应为null");
        assertFalse(result.isEmpty(), "格式化结果不应为空");
        
        // 验证XML内容
        assertTrue(result.contains("<snippet"), "应包含snippet根标签");
        assertTrue(result.contains("id=\"snippet_001\""), "应包含id属性");
        assertTrue(result.contains("title=\"角色描述模板\""), "应包含title属性");
        assertTrue(result.contains("<notes>"), "应包含notes标签");
        assertTrue(result.contains("用于描述主要角色的外貌特征"), "应包含notes内容");
        assertTrue(result.contains("<content>"), "应包含content标签");
        assertTrue(result.contains("这个角色有着明亮的眼睛"), "应包含content内容");
        assertTrue(result.contains("<category>"), "应包含category标签");
        assertTrue(result.contains("角色描述"), "应包含category内容");
        assertTrue(result.contains("<tags>"), "应包含tags标签");
        assertTrue(result.contains("主角, 外貌, 性格"), "应包含合并的tags内容");
        
        // 验证不包含XML声明
        assertFalse(result.contains("<?xml"), "不应包含XML声明");
        
        System.out.println("片段格式化结果：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");
    }

    @Test
    void testFormatSnippetWithMinimalData() {
        // 测试最小数据的片段
        NovelSnippet snippet = new NovelSnippet();
        snippet.setId("snippet_002");
        snippet.setTitle("简单片段");
        snippet.setContent("这是一个简单的片段内容。");

        String result = formatter.formatSnippet(snippet);

        assertNotNull(result);
        assertFalse(result.isEmpty());
        assertTrue(result.contains("id=\"snippet_002\""));
        assertTrue(result.contains("title=\"简单片段\""));
        assertTrue(result.contains("这是一个简单的片段内容"));
        
        System.out.println("最小数据片段格式化结果：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");
    }

    @Test
    void testFormatSnippetWithEmptyTags() {
        // 测试空标签列表的片段
        NovelSnippet snippet = new NovelSnippet();
        snippet.setId("snippet_003");
        snippet.setTitle("无标签片段");
        snippet.setContent("没有标签的片段内容。");
        snippet.setTags(Arrays.asList()); // 空列表

        String result = formatter.formatSnippet(snippet);

        assertNotNull(result);
        assertFalse(result.isEmpty());
        assertTrue(result.contains("id=\"snippet_003\""));
        
        // 验证空的tags字段
        assertTrue(result.contains("<tags></tags>") || result.contains("<tags/>"));
        
        System.out.println("空标签片段格式化结果：");
        System.out.println("====================================");
        System.out.println(result);
        System.out.println("====================================");
    }
} 