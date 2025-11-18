package com.ainovel.server.service.setting.generation;

import com.ainovel.server.domain.model.SettingType;
import com.ainovel.server.domain.model.setting.generation.SettingGenerationSession;
import com.ainovel.server.domain.model.setting.generation.SettingNode;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.*;

/**
 * 结构化设定输出验证器
 * 检查生成的节点是否满足质量要求
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StructuredSettingOutputValidator {
    
    private final SettingValidationService validationService;
    
    /**
     * 验证生成的节点列表是否满足质量要求
     */
    public ValidationResult validate(
            List<SettingNode> nodes,
            ConfigurableStrategyAdapter strategyAdapter,
            SettingGenerationSession session) {
        
        List<String> errors = new ArrayList<>();
        List<String> warnings = new ArrayList<>();
        
        if (nodes == null || nodes.isEmpty()) {
            errors.add("节点列表为空，未生成任何设定");
            return new ValidationResult(false, errors, warnings);
        }
        
        log.info("开始验证结构化输出：共 {} 个节点", nodes.size());
        
        // 1. 检查节点数量（至少5个）
        if (nodes.size() < 5) {
            errors.add("节点数量不足：生成了 " + nodes.size() + " 个，建议至少5个");
        } else if (nodes.size() >= 15) {
            log.info("✅ 节点数量充足：{} 个", nodes.size());
        } else {
            warnings.add("节点数量偏少：" + nodes.size() + " 个，建议15个以上");
        }
        
        // 2. 检查根节点数量
        long rootCount = nodes.stream()
            .filter(n -> n.getParentId() == null)
            .count();
        if (rootCount < 1) {
            errors.add("缺少根节点：必须至少有1个根节点");
        } else if (rootCount > 10) {
            warnings.add("根节点过多：" + rootCount + " 个，建议2-5个");
        } else {
            log.info("✅ 根节点数量合理：{} 个", rootCount);
        }
        
        // 3. 检查层级深度（至少2层）
        int maxDepth = calculateMaxDepth(nodes);
        if (maxDepth < 2) {
            errors.add("层级深度不足：当前 " + maxDepth + " 层，至少需要2层");
        } else if (maxDepth >= 3) {
            log.info("✅ 层级深度充足：{} 层", maxDepth);
        } else {
            warnings.add("层级深度偏浅：" + maxDepth + " 层，建议3层以上");
        }
        
        // 4. 检查父子关系完整性
        Map<String, String> tempIdToRealIdMap = new HashMap<>();
        for (SettingNode node : nodes) {
            String tempId = getTempIdFromNode(node);
            if (tempId != null && !tempId.isBlank()) {
                tempIdToRealIdMap.put(tempId, node.getId());
                log.debug("节点tempId映射: {} -> {} ({})", tempId, node.getId(), node.getName());
            } else {
                log.warn("⚠️ 节点 [{}] 缺少tempId", node.getName());
            }
        }
        
        log.debug("tempId映射表: {}", tempIdToRealIdMap.keySet());
        
        for (SettingNode node : nodes) {
            if (node.getParentId() != null && !node.getParentId().isBlank()) {
                String parentId = node.getParentId();
                log.debug("检查节点 [{}] 的父节点: {}", node.getName(), parentId);
                
                // 检查父节点是否存在（支持tempId引用）
                boolean hasParent = nodes.stream()
                    .anyMatch(n -> {
                        String nTempId = getTempIdFromNode(n);
                        return n.getId().equals(parentId) || 
                               (nTempId != null && nTempId.equals(parentId));
                    });
                
                if (!hasParent) {
                    // 提供更详细的错误信息
                    if (tempIdToRealIdMap.containsKey(parentId)) {
                        // tempId存在但匹配失败，说明代码有bug
                        log.error("🐛 Bug: tempId {} 在映射表中但匹配失败！", parentId);
                    }
                    errors.add("节点 [" + node.getName() + "] 的父节点不存在：parentId=" + parentId + 
                        " (可用tempId: " + tempIdToRealIdMap.keySet() + ")");
                }
            }
        }
        
        // 5. 检查节点内容质量（描述长度等）
        int emptyDescCount = 0;
        int shortDescCount = 0;
        for (SettingNode node : nodes) {
            String desc = node.getDescription();
            if (desc == null || desc.trim().isEmpty()) {
                emptyDescCount++;
                errors.add("节点 [" + node.getName() + "] 缺少描述内容");
            } else if (desc.trim().length() < 20) {
                shortDescCount++;
                warnings.add("节点 [" + node.getName() + "] 描述过短：" + desc.trim().length() + " 字");
            }
        }
        
        if (emptyDescCount > 0) {
            errors.add("有 " + emptyDescCount + " 个节点缺少描述");
        }
        if (shortDescCount > nodes.size() * 0.5) {
            warnings.add("有 " + shortDescCount + " 个节点描述过短（少于20字）");
        }
        
        // 6. 检查节点名称规范（不包含'/'等）
        for (SettingNode node : nodes) {
            if (node.getName() != null && node.getName().contains("/")) {
                errors.add("节点 [" + node.getName() + "] 名称包含非法字符'/'，请使用全角'／'");
            }
            if (node.getName() == null || node.getName().trim().isEmpty()) {
                errors.add("存在空名称节点");
            }
        }
        
        // 7. 策略特定验证
        int strategyErrorCount = 0;
        if (strategyAdapter != null) {
            for (SettingNode node : nodes) {
                try {
                    var strategyValidation = strategyAdapter.validateNode(
                        node, strategyAdapter.getCustomConfig(), session);
                    if (!strategyValidation.valid()) {
                        errors.add("节点 [" + node.getName() + "] 策略验证失败: " + 
                            strategyValidation.errorMessage());
                        strategyErrorCount++;
                    }
                } catch (Exception e) {
                    log.warn("策略验证节点失败: {}", e.getMessage());
                }
            }
        }
        
        // 8. 通用验证服务验证
        int validationErrorCount = 0;
        for (SettingNode node : nodes) {
            try {
                var validation = validationService.validateNode(node, session);
                if (!validation.isValid()) {
                    String errorMsg = String.join(", ", validation.errors());
                    errors.add("节点 [" + node.getName() + "] 验证失败: " + errorMsg);
                    validationErrorCount++;
                }
            } catch (Exception e) {
                log.warn("验证节点失败: {}", e.getMessage());
            }
        }
        
        // 9. 检查类型多样性
        Set<SettingType> types = new HashSet<>();
        for (SettingNode node : nodes) {
            if (node.getType() != null) {
                types.add(node.getType());
            }
        }
        if (types.size() < 2 && nodes.size() > 5) {
            warnings.add("节点类型单一：只有 " + types.size() + " 种类型，建议增加多样性");
        }
        
        // 总结
        boolean isValid = errors.isEmpty();
        if (isValid) {
            log.info("✅ 结构化输出验证通过：{} 个节点，{} 层深度，{} 种类型", 
                    nodes.size(), maxDepth, types.size());
        } else {
            log.warn("❌ 结构化输出验证失败：{} 个错误，{} 个警告", errors.size(), warnings.size());
        }
        
        return new ValidationResult(isValid, errors, warnings);
    }
    
    /**
     * 计算树的最大深度
     */
    private int calculateMaxDepth(List<SettingNode> nodes) {
        if (nodes.isEmpty()) {
            return 0;
        }
        
        // 构建父子关系映射（支持tempId）
        Map<String, String> nodeIdToParentId = new HashMap<>();
        Map<String, String> tempIdToRealId = new HashMap<>();
        
        for (SettingNode node : nodes) {
            String tempId = getTempIdFromNode(node);
            if (tempId != null && !tempId.isBlank()) {
                tempIdToRealId.put(tempId, node.getId());
            }
        }
        
        for (SettingNode node : nodes) {
            String parentId = node.getParentId();
            if (parentId != null && !parentId.isBlank()) {
                // 尝试将tempId转换为真实ID
                String realParentId = tempIdToRealId.getOrDefault(parentId, parentId);
                nodeIdToParentId.put(node.getId(), realParentId);
            }
        }
        
        // 计算每个节点的深度
        Map<String, Integer> depthMap = new HashMap<>();
        for (SettingNode node : nodes) {
            calculateNodeDepth(node.getId(), nodeIdToParentId, depthMap);
        }
        
        return depthMap.values().stream()
            .max(Integer::compare)
            .orElse(0);
    }
    
    /**
     * 递归计算节点深度
     */
    private int calculateNodeDepth(String nodeId, Map<String, String> parentMap, Map<String, Integer> depthMap) {
        if (depthMap.containsKey(nodeId)) {
            return depthMap.get(nodeId);
        }
        
        String parentId = parentMap.get(nodeId);
        int depth;
        if (parentId == null || parentId.isBlank()) {
            // 根节点深度为1
            depth = 1;
        } else {
            // 子节点深度 = 父节点深度 + 1
            depth = calculateNodeDepth(parentId, parentMap, depthMap) + 1;
        }
        
        depthMap.put(nodeId, depth);
        return depth;
    }
    
    /**
     * 从节点attributes中获取tempId
     */
    private String getTempIdFromNode(SettingNode node) {
        if (node.getAttributes() != null) {
            Object tempIdObj = node.getAttributes().get("tempId");
            if (tempIdObj != null) {
                return tempIdObj.toString();
            }
        }
        return null;
    }
    
    /**
     * 验证结果
     */
    @Getter
    @AllArgsConstructor
    public static class ValidationResult {
        private final boolean valid;
        private final List<String> errors;
        private final List<String> warnings;
        
        public String getErrorSummary() {
            if (errors.isEmpty()) {
                return "";
            }
            return String.join("\n", errors);
        }
        
        public String getWarningSummary() {
            if (warnings.isEmpty()) {
                return "";
            }
            return String.join("\n", warnings);
        }
    }
}

