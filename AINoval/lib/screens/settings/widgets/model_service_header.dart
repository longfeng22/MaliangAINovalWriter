import 'package:flutter/material.dart';
import 'package:ainoval/widgets/common/app_search_field.dart';

/// 模型服务列表页面的头部组件
/// 包含标题、描述、搜索框、筛选下拉框和添加按钮
class ModelServiceHeader extends StatelessWidget {
  const ModelServiceHeader({
    super.key,
    required this.onSearch,
    required this.onAddNew,
    required this.onFilterChange,
  });

  final Function(String) onSearch;
  final VoidCallback onAddNew;
  final Function(String) onFilterChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主标题区域
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '模型服务管理',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '管理和配置你的 AI 模型提供商及其可用模型。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 添加按钮
              ElevatedButton.icon(
                onPressed: onAddNew,
                icon: Icon(
                  Icons.add, 
                  size: 18,
                  color: theme.colorScheme.onPrimary,
                ),
                label: Text(
                  '添加模型',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 控制栏
          Row(
            children: [
              // 搜索框
              Expanded(
                flex: 2,
                child: AppSearchField(
                  hintText: '搜索模型提供商...',
                  height: 48, // 调高搜索框高度以提升整体控件高度
                  borderRadius: 8,
                  onChanged: onSearch,
                  controller: TextEditingController(),
                ),
              ),

              const SizedBox(width: 16),

              // 筛选下拉框（增大高度与图标尺寸，添加Tooltip）
              Tooltip(
                message: '筛选',
                child: SizedBox(
                  width: 140,
                  height: 48,
                  child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  value: 'all',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 24, // 放大下拉箭头图标
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  dropdownColor: theme.colorScheme.surface,
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(
                        '全部模型',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text(
                        '已验证',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'unverified',
                      child: Text(
                        '未验证',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onFilterChange(value);
                    }
                  },
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // 设置按钮（增大图标和按钮尺寸，添加Tooltip）
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings, size: 24),
                tooltip: '设置',
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  minimumSize: const Size(44, 44),
                  backgroundColor: Colors.transparent,
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
                  side: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
