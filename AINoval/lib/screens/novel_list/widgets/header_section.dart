import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/common/theme_toggle_button.dart';

/// 标题栏组件
class HeaderSection extends StatelessWidget {
  const HeaderSection({
    super.key,
    required this.onCreateNovel,
    required this.onImportNovel,
  });

  final VoidCallback onCreateNovel;
  final VoidCallback onImportNovel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.08),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '你的小说',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // 主题切换按钮
              const ThemeToggleButton(),
              const SizedBox(width: 12),
              // 测试按钮
              ElevatedButton.icon(
                onPressed: () {
                },
                icon: const Icon(Icons.bug_report),
                label: const Text('测试'),
                style: WebTheme.getPrimaryButtonStyle(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onImportNovel,
                icon: const Icon(Icons.file_upload),
                label: const Text('导入'),
                style: WebTheme.getPrimaryButtonStyle(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onCreateNovel,
                icon: const Icon(Icons.add),
                label: const Text('创建小说'),
                style: WebTheme.getPrimaryButtonStyle(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
