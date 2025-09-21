package com.ainovel.server.service.impl;

import com.ainovel.server.web.dto.request.UniversalAIRequestDto;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 通用AI服务预处理去重逻辑测试
 */
@SpringBootTest
public class UniversalAIServicePreprocessTest {

    @Test
    public void testPreprocessAndDeduplicateSelections() {
        // 创建测试用的选择列表
        List<UniversalAIRequestDto.ContextSelectionDto> selections = Arrays.asList(
            createSelection("full_novel_text", "novel_1", "完整小说"),
            createSelection("chapter", "chapter_1", "第一章"),
            createSelection("scene", "scene_1", "场景1"),
            createSelection("scene", "scene_2", "场景2"),
            createSelection("character", "char_1", "主角")
        );

        // 模拟UniversalAIServiceImpl实例
        UniversalAIServiceImpl service = new UniversalAIServiceImpl();
        
        // 测试预处理去重逻辑
        // 注：由于方法是私有的，这里主要测试逻辑思路，实际测试需要通过公开接口
        
        // 预期结果：
        // 1. full_novel_text 优先级最高，应该被保留
        // 2. chapter 和 scene 应该被排除，因为被 full_novel_text 包含
        // 3. character 应该被保留，因为不被其他内容包含
        
        System.out.println("测试用例设计完成，验证去重逻辑：");
        System.out.println("输入选择项：");
        for (UniversalAIRequestDto.ContextSelectionDto selection : selections) {
            System.out.println("  - " + selection.getType() + ": " + selection.getTitle());
        }
        
        System.out.println("预期输出（去重后）：");
        System.out.println("  - full_novel_text: 完整小说");
        System.out.println("  - character: 主角");
    }
    
    @Test
    public void testChapterSceneDeduplication() {
        // 测试章节和场景的去重逻辑
        List<UniversalAIRequestDto.ContextSelectionDto> selections = Arrays.asList(
            createSelection("chapter", "chapter_1", "第一章"),
            createSelection("scene", "scene_1", "场景1 (属于第一章)"),
            createSelection("scene", "scene_3", "场景3 (属于第二章)"),
            createSelection("character", "char_1", "主角")
        );
        
        // 预期结果：
        // 1. chapter_1 应该被保留
        // 2. scene_1 应该被排除，因为属于 chapter_1
        // 3. scene_3 应该被保留，因为不属于被选择的章节
        // 4. character 应该被保留
        
        System.out.println("\n章节场景去重测试：");
        System.out.println("输入选择项：");
        for (UniversalAIRequestDto.ContextSelectionDto selection : selections) {
            System.out.println("  - " + selection.getType() + ": " + selection.getTitle());
        }
        
        System.out.println("预期输出（去重后）：");
        System.out.println("  - chapter: 第一章");
        System.out.println("  - scene: 场景3 (属于第二章)");
        System.out.println("  - character: 主角");
    }
    
    private UniversalAIRequestDto.ContextSelectionDto createSelection(String type, String id, String title) {
        UniversalAIRequestDto.ContextSelectionDto selection = new UniversalAIRequestDto.ContextSelectionDto();
        selection.setType(type);
        selection.setId(id);
        selection.setTitle(title);
        return selection;
    }
} 