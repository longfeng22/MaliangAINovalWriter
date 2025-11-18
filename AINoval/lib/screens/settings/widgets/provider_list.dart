import 'package:flutter/material.dart';
import 'package:ainoval/widgets/common/app_search_field.dart';
import '../../../config/provider_icons.dart';

/// 提供商列表组件
/// 显示左侧的提供商列表，类似CherryStudio的UI
class ProviderList extends StatelessWidget {
  const ProviderList({
    super.key,
    required this.providers,
    required this.selectedProvider,
    required this.onProviderSelected,
  });

  final List<String> providers;
  final String? selectedProvider;
  final ValueChanged<String> onProviderSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: AppSearchField(
              hintText: '搜索模型平台...',
              height: 34,
              borderRadius: 8,
              onChanged: (value) {
                // 实现搜索功能
                // 这里可以添加搜索逻辑
              },
              controller: TextEditingController(),
            ),
          ),
          
          // 提供商列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final provider = providers[index];
                final isSelected = provider == selectedProvider;
                
                return _buildProviderItem(context, provider, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderItem(BuildContext context, String provider, bool isSelected) {
    final theme = Theme.of(context);
    
    // 获取提供商图标
    Widget providerIcon = _getProviderIcon(provider);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minLeadingWidth: 24,
        minVerticalPadding: 0,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: providerIcon,
        title: Text(
          _getProviderDisplayName(provider),
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: () => onProviderSelected(provider),
        // 如果是OpenRouter，添加一个标签
        trailing: provider.toLowerCase() == 'openrouter'
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '启用',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  // 获取提供商图标
  Widget _getProviderIcon(String provider) {
    final iconColor = ProviderIcons.getProviderColor(provider);
    
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: ProviderIcons.getProviderIconForContext(
        provider,
        iconSize: IconSize.small,
      ),
    );
  }

  // 获取提供商显示名称
  String _getProviderDisplayName(String provider) {
    return ProviderIcons.getProviderDisplayName(provider);
  }
}
