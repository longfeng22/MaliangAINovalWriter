import 'package:flutter/material.dart';
import '../../../models/strategy_template_info.dart';
import '../../../models/prompt_models.dart';
import '../../../utils/web_theme.dart';
import '../../prompt_market/prompt_market_dialog.dart';
import '../../../utils/event_bus.dart';

/// 增强的策略选择器
/// 包含策略下拉框 + 市场入口按钮
class EnhancedStrategySelector extends StatelessWidget {
  final List<StrategyTemplateInfo> strategies;
  final String selectedStrategy;
  final ValueChanged<String?> onChanged;
  final bool isLoading;

  const EnhancedStrategySelector({
    super.key,
    required this.strategies,
    required this.selectedStrategy,
    required this.onChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度以自适应布局
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600; // 窄屏幕检测
    
    return Row(
      children: [
        // 策略选择下拉框
        Expanded(
          child: _buildStrategyDropdown(context),
        ),
        
        SizedBox(width: isNarrow ? 4 : 8), // 窄屏幕减小间距
        
        // 市场入口按钮
        _buildMarketplaceButton(context, isCompact: isNarrow),
      ],
    );
  }

  Widget _buildStrategyDropdown(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WebTheme.getBorderColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: isLoading
          ? _buildLoadingState(context)
          : _buildDropdown(context),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              WebTheme.getPrimaryColor(context),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '加载中...',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedStrategy.isEmpty ? null : selectedStrategy,
        isExpanded: true,
        style: TextStyle(
          fontSize: 12,
          color: WebTheme.getTextColor(context),
        ),
        dropdownColor: WebTheme.getSurfaceColor(context),
        icon: Icon(
          Icons.arrow_drop_down,
          size: 16,
          color: WebTheme.getSecondaryTextColor(context),
        ),
        items: strategies.map((strategy) {
          return DropdownMenuItem(
            value: strategy.promptTemplateId,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strategy.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // 需求：禁用点击打开详情

  Widget _buildMarketplaceButton(BuildContext context, {bool isCompact = false}) {
    return Tooltip(
      message: '浏览提示词市场',
      child: Container(
        height: 48,
        constraints: BoxConstraints(
          minWidth: isCompact ? 40 : 80, // 紧凑模式最小宽度
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WebTheme.getPrimaryColor(context),
              WebTheme.getPrimaryColor(context).withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openMarketplace(context),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store,
                    size: 18,
                    color: Colors.white,
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 6),
                    Text(
                      '市场',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMarketplace(BuildContext context) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const PromptMarketDialog(
        // 🎯 设定生成功能，传入对应的AIFeatureType
        initialFeatureType: AIFeatureType.settingTreeGeneration,
      ),
    );
    // 市场关闭后刷新策略列表，确保新复制策略可见（通过上层触发，不在此直接依赖 Bloc）


    // 处理导航请求：通过事件总线保持左侧布局跳转到「提示词与预设」
    if (selected != null && selected['navigate_to'] == 'unified_management') {
      try { EventBus.instance.fire(const NavigateToUnifiedManagement()); } catch (_) {}
      return;
    }

    if (selected != null && selected['id'] != null) {
      onChanged(selected['id'] as String);
      
      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('已选择提示词: ${selected['name']}'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

