import 'package:ainoval/models/ai_model_group.dart';
import 'package:ainoval/models/model_info.dart';
import 'package:flutter/material.dart';

/// 模型分组列表组件
/// 在提供商内显示按前缀分组的模型列表
class ModelGroupList extends StatelessWidget {
  const ModelGroupList({
    super.key,
    required this.modelGroup,
    required this.onModelSelected,
    this.selectedModel,
    this.verifiedModels = const [],
  });

  final AIModelGroup modelGroup;
  final ValueChanged<String> onModelSelected;
  final String? selectedModel;
  final List<String> verifiedModels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: modelGroup.groups.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: theme.colorScheme.outline.withOpacity(0.1),
          indent: 16,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final group = modelGroup.groups[index];
          return _buildModelPrefixGroup(context, group);
        },
      ),
    );
  }

  Widget _buildModelPrefixGroup(BuildContext context, ModelPrefixGroup group) {
    final theme = Theme.of(context);
    // final isDark = theme.brightness == Brightness.dark;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        title: Text(
          group.prefix,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        iconColor: theme.colorScheme.onSurface,
        collapsedIconColor: theme.colorScheme.onSurface.withOpacity(0.7),
        initiallyExpanded: true,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        children: group.modelsInfo.map((modelInfo) {
          final isSelected = modelInfo.id == selectedModel;
          final isVerified = verifiedModels.contains(modelInfo.id);
          return _buildModelItem(context, modelInfo, isSelected, isVerified);
        }).toList(),
      ),
    );
  }

  Widget _buildModelItem(BuildContext context, ModelInfo modelInfo, bool isSelected, bool isVerified) {
    final theme = Theme.of(context);
    // final isDark = theme.brightness == Brightness.dark;

    String displayName = modelInfo.name.isNotEmpty ? modelInfo.name : modelInfo.id;
    final inputPrice = modelInfo.inputPricePerThousandTokens;
    final outputPrice = modelInfo.outputPricePerThousandTokens;
    final tags = modelInfo.tags;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.surfaceContainerHigh
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.outline.withOpacity(0.3)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Row(
          children: [
            // 模型状态图标
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isVerified
                    ? Colors.green.withOpacity(0.1)
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isVerified
                      ? Colors.green.withOpacity(0.3)
                      : theme.colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: isVerified
                    ? Icon(
                        Icons.check,
                        color: theme.colorScheme.secondary,
                        size: 12,
                      )
                    : Text(
                        _getModelInitial(modelInfo.id),
                        style: TextStyle(
                        color: theme.colorScheme.onSurface,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            
            // 模型名称
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (modelInfo.id != displayName)
                    Text(
                      modelInfo.id,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  // 价格信息（若存在）
                  if (inputPrice != null || outputPrice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          if (inputPrice != null)
                            Text(
                              '入: \$${inputPrice.toStringAsFixed(4)}/1K',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface.withOpacity(0.75),
                              ),
                            ),
                          if (inputPrice != null && outputPrice != null)
                            const SizedBox(width: 6),
                          if (outputPrice != null)
                            Text(
                              '出: \$${outputPrice.toStringAsFixed(4)}/1K',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface.withOpacity(0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            
            // 标签
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 已验证标记
                if (isVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '✓',
                      style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                
                const SizedBox(width: 4),
                
                // 动态标签：来自 properties.tags
                ...tags.take(3).map((t) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      t.toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )),
                
                // 特性徽标
                if (modelInfo.supportsPromptCaching)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.save_alt, size: 14, color: theme.colorScheme.primary),
                  ),
                if (modelInfo.tieredPricing)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(Icons.stacked_line_chart, size: 14, color: theme.colorScheme.primary),
                  ),
              ],
            ),
          ],
        ),
        onTap: () => onModelSelected(modelInfo.id),
        selected: isSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  // 获取模型的首字母作为图标
  String _getModelInitial(String modelId) {
    if (modelId.contains('/')) {
      return modelId.split('/').first[0].toUpperCase();
    } else if (modelId.contains('-')) {
      return modelId.split('-').first[0].toUpperCase();
    } else {
      return modelId.isNotEmpty ? modelId[0].toUpperCase() : '?';
    }
  }
}
