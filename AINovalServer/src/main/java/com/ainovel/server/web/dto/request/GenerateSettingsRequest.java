package com.ainovel.server.web.dto.request;

import java.util.List;
import java.util.Map;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class GenerateSettingsRequest {
    @NotBlank(message = "起始章节ID不能为空")
    private String startChapterId;

    // endChapterId 可以为空，如果为空，则表示从 startChapterId 到最新章节
    private String endChapterId;

    @NotEmpty(message = "设定类型列表不能为空")
    @Size(min = 1, message = "至少选择一个设定类型")
    private List<String> settingTypes; // 使用 String 类型接收，后续转换为 SettingType 枚举

    private Integer maxSettingsPerType = 8; // 默认值
    private String additionalInstructions;
    
    @NotBlank(message = "模型配置ID不能为空")
    private String modelConfigId; // 模型配置ID，后端会自己查询novelId对应的已有设定
} 