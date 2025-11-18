import 'package:flutter/material.dart';
import 'package:ainoval/models/prompt_models.dart';

/// 提示词模板详情对话框（仿策略详情样式）
class PromptTemplateDetailDialog extends StatelessWidget {
  final EnhancedUserPromptTemplate template;

  const PromptTemplateDetailDialog({super.key, required this.template});

  static BuildContext? _dialogContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Builder(builder: (context) {
        _dialogContext = context;
        return Container(
        width: screenSize.width < 600
            ? screenSize.width * 0.95
            : (screenSize.width < 900 ? 700 : 800),
        constraints: BoxConstraints(maxHeight: screenSize.height * 0.85),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              Flexible(child: _buildBody(theme)),
            ],
          ),
        ),
      );
      }),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
                    : [const Color(0xFF5856D6), const Color(0xFF4947CC)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: (isDark
                          ? const Color(0xFF5E5CE6)
                          : const Color(0xFF5856D6))
                      .withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.description_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              template.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.close,
                size: 18,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
              ),
              onPressed: () => Navigator.of(_dialogContext!).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((template.description ?? '').isNotEmpty) ...[
            Text(
              template.description!,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildSection(title: 'System Prompt', content: template.systemPrompt, theme: theme, isDark: isDark),
          const SizedBox(height: 12),
          _buildSection(title: 'User Prompt', content: template.userPrompt, theme: theme, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required String content, required ThemeData theme, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
              width: 0.5,
            ),
          ),
          child: SelectableText(
            content.isEmpty ? '(空)' : content,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}


