import 'package:flutter/material.dart';

class IncludeDepthField extends StatelessWidget {
  final String value; // 'summaryOnly' | 'full'
  final ValueChanged<String> onChanged;
  final String title;
  final String description;

  const IncludeDepthField({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = '上下文深度',
    this.description = '选择将设定或既有内容以摘要或全文形式纳入上下文',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('全文'),
              selected: true, // 始终选中全文
              onSelected: null, // 禁用点击
            ),
          ],
        ),
      ],
    );
  }
}



