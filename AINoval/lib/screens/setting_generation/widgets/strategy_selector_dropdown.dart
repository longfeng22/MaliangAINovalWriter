import 'package:flutter/material.dart';
import '../../../models/strategy_template_info.dart';
import '../../../utils/web_theme.dart';

/// 自定义策略选择下拉框组件
class StrategySelectorDropdown extends StatefulWidget {
  final List<StrategyTemplateInfo> strategies;
  final StrategyTemplateInfo? selectedStrategy;
  final ValueChanged<StrategyTemplateInfo?>? onChanged;
  final bool isLoading;

  const StrategySelectorDropdown({
    Key? key,
    required this.strategies,
    this.selectedStrategy,
    this.onChanged,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<StrategySelectorDropdown> createState() => _StrategySelectorDropdownState();
}

class _StrategySelectorDropdownState extends State<StrategySelectorDropdown> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _isDisposing = false;

  @override
  void dispose() {
    _isDisposing = true;
    _removeOverlay(force: true);
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    if (widget.strategies.isEmpty || widget.isLoading) return;

    final RenderBox? renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final overlay = Overlay.of(context);
    
    setState(() {
      _isOpen = true;
    });
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 透明背景，点击关闭
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeOverlay,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 下拉菜单内容
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: Material(
              elevation: 8,
              color: WebTheme.getSurfaceColor(context),
              shadowColor: WebTheme.getShadowColor(context, opacity: 0.2),
              child: Container(
                width: size.width,
                constraints: const BoxConstraints(
                  maxHeight: 320,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: WebTheme.getBorderColor(context).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: _buildDropdownContent(),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay({bool force = false}) {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    // 在 dispose 阶段或未挂载时，直接更新标志，避免调用 setState 触发断言
    if (force || _isDisposing || !mounted) {
      _isOpen = false;
      return;
    }
    setState(() {
      _isOpen = false;
    });
  }

  Widget _buildDropdownContent() {
    return ClipRRect(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: WebTheme.getSecondaryBorderColor(context).withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: WebTheme.getBorderColor(context).withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                '选择生成策略',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ),
            // 策略列表
            ...widget.strategies.asMap().entries.map((entry) {
              final index = entry.key;
              final strategy = entry.value;
              final isSelected = widget.selectedStrategy?.promptTemplateId == strategy.promptTemplateId;
              final isLast = index == widget.strategies.length - 1;
              
              return _buildStrategyItem(strategy, isSelected, isLast);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyItem(StrategyTemplateInfo strategy, bool isSelected, bool isLast) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onChanged?.call(strategy);
          _removeOverlay();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected 
                ? WebTheme.getPrimaryColor(context).withOpacity(0.08)
                : Colors.transparent,
            border: !isLast ? Border(
              bottom: BorderSide(
                color: WebTheme.getBorderColor(context).withOpacity(0.1),
                width: 1,
              ),
            ) : null,
          ),
          child: Row(
            children: [
              // 策略信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 策略名称
                    Text(
                      strategy.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected 
                            ? WebTheme.getPrimaryColor(context)
                            : WebTheme.getTextColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 策略描述
                    if (strategy.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        strategy.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WebTheme.getSecondaryTextColor(context),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // 选中状态指示器
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: WebTheme.getPrimaryColor(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成策略',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _layerLink,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: _buttonKey,
              onTap: widget.isLoading ? null : _toggleDropdown,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: WebTheme.getSurfaceColor(context),
                  border: Border.all(
                    color: _isOpen 
                        ? WebTheme.getPrimaryColor(context).withOpacity(0.5)
                        : WebTheme.getBorderColor(context),
                    width: _isOpen ? 2 : 1,
                  ),
                ),
                child: widget.isLoading 
                    ? _buildLoadingContent()
                    : _buildButtonContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingContent() {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '加载策略中...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildButtonContent() {
    return Row(
      children: [
        Expanded(
          child: widget.selectedStrategy != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.selectedStrategy!.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: WebTheme.getTextColor(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (widget.selectedStrategy!.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.selectedStrategy!.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WebTheme.getSecondaryTextColor(context),
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                )
              : Text(
                  '选择生成策略',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        AnimatedRotation(
          turns: _isOpen ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.keyboard_arrow_down,
            color: WebTheme.getSecondaryTextColor(context),
            size: 20,
          ),
        ),
      ],
    );
  }
}
