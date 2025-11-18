import 'package:flutter/material.dart';

/// 可搜索的模型下拉框
/// 允许用户搜索和选择模型
class SearchableModelDropdown extends StatefulWidget {
  const SearchableModelDropdown({
    super.key,
    required this.models,
    required this.onModelSelected,
    this.hintText = '搜索模型',
    this.onCreateCustom,
    this.onSearchChanged,
    this.value,
  });

  final List<String> models;
  final ValueChanged<String> onModelSelected;
  final String hintText;
  // 当输入的关键字没有匹配时，允许创建自定义模型
  // 回调返回要创建的模型名称
  final ValueChanged<String>? onCreateCustom;
  // 搜索关键字变更回调，用于外部联动过滤下方列表
  final ValueChanged<String>? onSearchChanged;
  // 外部受控文本值，用于回填所选模型ID
  final String? value;

  @override
  State<SearchableModelDropdown> createState() => _SearchableModelDropdownState();
}

class _SearchableModelDropdownState extends State<SearchableModelDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  
  OverlayEntry? _overlayEntry;
  String _searchText = '';
  bool _isDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
    if (widget.value != null && widget.value!.isNotEmpty) {
      _searchController.text = widget.value!;
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchableModelDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final next = widget.value ?? '';
      if (_searchController.text != next) {
        _searchController.text = next;
        // 触发一次外部搜索回调，保持一致
        if (widget.onSearchChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSearchChanged!.call(next);
          });
        }
      }
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text;
      if (_isDropdownOpen) {
        _updateOverlay();
      } else if (_searchText.isNotEmpty) {
        _showOverlay();
      }
    });
    // 对外通知搜索关键字变化
    widget.onSearchChanged?.call(_searchText);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    }

    _isDropdownOpen = true;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isDropdownOpen = false;
    }
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: 250,
                  minWidth: size.width,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    width: 0.5,
                  ),
                ),
                child: _buildDropdownList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownList() {
    final filteredModels = widget.models
        .where((model) => model.toLowerCase().contains(_searchText.toLowerCase()))
        .toList();

    if (filteredModels.isEmpty) {
      // 无匹配时，显示创建自定义模型入口（若提供回调）
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Text('没有找到匹配的模型', style: TextStyle(fontSize: 13)),
            ),
            if (widget.onCreateCustom != null && _searchText.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final name = _searchText.trim();
                  if (name.isEmpty) return;
                  widget.onCreateCustom!(name);
                  // 不清空输入，保留用户输入；仅关闭下拉
                  _removeOverlay();
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text('添加自定义模型 “$_searchText”', overflow: TextOverflow.ellipsis),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: filteredModels.length,
      itemBuilder: (context, index) {
        final model = filteredModels[index];
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            model,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            // 选中后直接回填到输入框
            _searchController.text = model;
            // 通知上层所选模型
            widget.onModelSelected(model);
            // 同步一次搜索关键字，供下方列表过滤
            widget.onSearchChanged?.call(_searchController.text);
            // 关闭下拉，但保留焦点
            _removeOverlay();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: Theme.of(context).hintColor.withOpacity(0.7),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: 1.0,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
          ),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
              : Theme.of(context).colorScheme.surfaceContainerLowest.withOpacity(0.7),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          isDense: true,
        ),
      ),
    );
  }
}
