package com.ainovel.server.common.util;

import com.ainovel.server.domain.model.Scene;
import com.ainovel.server.domain.model.NovelSettingItem;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * PromptXmlFormatter 测试类
 */
@SpringBootTest
public class PromptXmlFormatterTest {

    private PromptXmlFormatter formatter;

    @BeforeEach
    void setUp() {
        formatter = new PromptXmlFormatter();
    }

    @Test
    void testFormatSystemPrompt() {
        // 准备测试数据
        String role = "你是一位专业的小说助手";
        String instructions = "请帮助用户完成小说创作";
        String context = "当前正在创作奇幻小说";
        String length = "500字左右";
        String style = "幽默风趣";
        
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("temperature", 0.7);
        parameters.put("maxTokens", 1000);

        // 执行格式化
        String result = formatter.formatSystemPrompt(role, instructions, context, length, style, parameters);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<system>"));
        assertTrue(result.contains("<role>"));
        assertTrue(result.contains(role));
        assertTrue(result.contains("<instructions>"));
        assertTrue(result.contains(instructions));
        assertTrue(result.contains("<context>"));
        assertTrue(result.contains(context));
        
        System.out.println("系统提示词格式化结果：");
        System.out.println(result);
    }

    @Test
    void testFormatUserPrompt() {
        // 准备测试数据
        String action = "请扩写以下文本内容";
        String input = "【叮！恭喜宿主络风成功绑定特权神豪系统。】";
        String context = "这是一个都市系统小说的开头";
        String length = "1000字";
        String style = "轻松幽默";
        String tone = "第三人称";

        // 执行格式化
        String result = formatter.formatUserPrompt(action, input, context, length, style, tone);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<task>"));
        assertTrue(result.contains("<action>"));
        assertTrue(result.contains(action));
        assertTrue(result.contains("<input>"));
        assertTrue(result.contains(input));
        assertTrue(result.contains("<context>"));
        assertTrue(result.contains(context));
        
        System.out.println("用户提示词格式化结果：");
        System.out.println(result);
    }

    @Test
    void testFormatChatMessage() {
        // 准备测试数据
        String message = "请帮我分析一下这个角色的性格特点";
        String context = "角色：李明，年龄25岁，程序员";

        // 执行格式化
        String result = formatter.formatChatMessage(message, context);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<message>"));
        assertTrue(result.contains("<content>"));
        assertTrue(result.contains(message));
        
        System.out.println("聊天消息格式化结果：");
        System.out.println(result);
    }

    @Test
    void testFormatScene() {
        // 准备测试Scene数据
        Scene scene = new Scene();
        scene.setId("scene_001");
        scene.setTitle("第一场：系统觉醒");
        scene.setSequence(1);
        scene.setSummary("主角络风获得神豪系统");
        scene.setContent("【叮！恭喜宿主络风成功绑定特权神豪系统。】\n络风听到脑海中响起的声音，惊讶地瞪大了眼睛。");

        // 执行格式化
        String result = formatter.formatScene(scene);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<scene"));
        assertTrue(result.contains("title=\"" + scene.getTitle() + "\""));
        assertTrue(result.contains("number=\"" + scene.getSequence() + "\""));
        assertTrue(result.contains("id=\"" + scene.getId() + "\""));
        assertTrue(result.contains("<summary>"));
        assertTrue(result.contains(scene.getSummary()));
        assertTrue(result.contains("<content>"));
        
        System.out.println("场景格式化结果：");
        System.out.println(result);
    }

    @Test
    void testFormatSetting() {
        // 准备测试NovelSettingItem数据
        NovelSettingItem setting = new NovelSettingItem();
        setting.setId("char_001");
        setting.setType("character");
        setting.setName("络风");
        setting.setDescription("25岁的普通上班族，意外获得神豪系统");
        
        Map<String, String> attributes = new HashMap<>();
        attributes.put("年龄", "25");
        attributes.put("职业", "程序员");
        attributes.put("性格", "内向但善良");
        setting.setAttributes(attributes);
        
        setting.setTags(Arrays.asList("主角", "系统文", "都市"));

        // 执行格式化
        String result = formatter.formatSetting(setting);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<setting"));
        assertTrue(result.contains("type=\"" + setting.getType() + "\""));
        assertTrue(result.contains("id=\"" + setting.getId() + "\""));
        assertTrue(result.contains("<name>"));
        assertTrue(result.contains(setting.getName()));
        assertTrue(result.contains("<description>"));
        assertTrue(result.contains(setting.getDescription()));
        
        System.out.println("设定格式化结果：");
        System.out.println(result);
    }

    @Test
    void testFormatNovelOutline() {
        // 准备测试数据
        String title = "神豪系统：我真的只想低调";
        String description = "一个普通程序员意外获得神豪系统的故事";
        
        // 创建测试场景
        Scene scene1 = new Scene();
        scene1.setId("scene_001");
        scene1.setTitle("系统觉醒");
        scene1.setChapterId("chapter_001");
        scene1.setSequence(1);
        scene1.setSummary("主角获得系统");
        scene1.setContent("【叮！恭喜宿主络风成功绑定特权神豪系统。】");
        
        Scene scene2 = new Scene();
        scene2.setId("scene_002");
        scene2.setTitle("初次体验");
        scene2.setChapterId("chapter_001");
        scene2.setSequence(2);
        scene2.setSummary("主角尝试使用系统功能");
        scene2.setContent("络风小心翼翼地尝试使用系统的功能。");
        
        List<Scene> scenes = Arrays.asList(scene1, scene2);

        // 执行格式化
        String result = formatter.formatNovelOutline(title, description, scenes);

        // 验证结果
        assertNotNull(result);
        assertTrue(result.contains("<outline>"));
        assertTrue(result.contains("<title>"));
        assertTrue(result.contains(title));
        assertTrue(result.contains("<description>"));
        assertTrue(result.contains(description));
        assertTrue(result.contains("<act"));
        assertTrue(result.contains("<chapter"));
        assertTrue(result.contains("<scene"));
        
        System.out.println("小说大纲格式化结果：");
        System.out.println(result);
    }

    @Test
    void testUserPromptWithXmlContext() {
        String action = "请扩写以下文本内容";
        String input = "阿宝穿着一件有些褪色的蓝色小棉袄";
        String xmlContext = "      <scene title=\"场景 1743861548241\" number=\"1\" id=\"1743861548241\">\n" +
                           "        <content>远处，阿宝的妈妈站在街角，远远地看着这一幕，嘴角也扬起一抹温柔的笑。她知道，这颗糖对阿宝来说，不仅仅是一块甜食，更是一份小小的幸福，一份童年里最纯真的快乐。</content>\n" +
                           "      </scene>\n" +
                           "      <scene title=\"场景 1743861548242\" number=\"2\" id=\"1743861548242\">\n" +
                           "        <content>dsaddsads</content>\n" +
                           "      </scene>";

        String result = formatter.formatUserPrompt(action, input, xmlContext, "triple", "温暖", "第三人称");

        System.out.println("=== XML转义修复测试结果 ===");
        System.out.println(result);
        System.out.println("=== 结束 ===");

        // 验证XML内容没有被转义
        assert !result.contains("&lt;"); // 应该没有转义的 <
        assert !result.contains("&gt;"); // 应该没有转义的 >
        assert result.contains("<scene"); // 应该保持原有的XML标签
        assert result.contains("<content>"); // 应该保持原有的XML标签
    }

    @Test
    void testSystemPromptWithXmlContext() {
        String role = "你是一位经验丰富的小说作者助手";
        String instructions = "请根据提供的上下文信息进行扩写";
        String xmlContext = "<settings>\n" +
                           "  <character id=\"阿宝\" type=\"角色\">\n" +
                           "    <name>阿宝</name>\n" +
                           "    <description>一个可爱的小孩子</description>\n" +
                           "  </character>\n" +
                           "</settings>";

        String result = formatter.formatSystemPrompt(role, instructions, xmlContext, "long", "温暖", null);

        System.out.println("=== 系统提示词XML转义修复测试结果 ===");
        System.out.println(result);
        System.out.println("=== 结束 ===");

        // 验证XML内容没有被转义
        assert !result.contains("&lt;"); // 应该没有转义的 <
        assert !result.contains("&gt;"); // 应该没有转义的 >
        assert result.contains("<character"); // 应该保持原有的XML标签
        assert result.contains("<settings>"); // 应该保持原有的XML标签
    }
} 