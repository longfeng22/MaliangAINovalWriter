import 'package:flutter/material.dart';

class ChapterLengthField extends StatefulWidget {
  final String? preset; // 'short' | 'medium' | 'long' | null
  final String? customLength;
  final ValueChanged<String?> onPresetChanged;
  final ValueChanged<String> onCustomChanged;
  final String title;
  final String description;

  const ChapterLengthField({
    super.key,
    this.preset,
    this.customLength,
    required this.onPresetChanged,
    required this.onCustomChanged,
    this.title = '每章长度',
    this.description = '每章期望长度（短/中/长）或自定义字数',
  });

  @override
  State<ChapterLengthField> createState() => _ChapterLengthFieldState();
}

class _ChapterLengthFieldState extends State<ChapterLengthField> {
  late TextEditingController _controller;
  String? _preset;
  bool _isCustomizing = false;

  @override
  void initState() {
    super.initState();
    _preset = widget.preset;
    _controller = TextEditingController(text: widget.customLength ?? '');
    _isCustomizing = widget.preset == null && widget.customLength?.isNotEmpty == true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getWordCountText() {
    if (_preset == 'short') return '1000字';
    if (_preset == 'medium') return '2000字';
    if (_preset == 'long') return '3000字';
    if (_controller.text.isNotEmpty) {
      final customNumber = int.tryParse(_controller.text.trim());
      if (customNumber != null && customNumber > 0) {
        return '${customNumber}字';
      }
    }
    return '3000字'; // 默认显示
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getWordCountText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(widget.description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('短（1000字）'),
              selected: _preset == 'short' && !_isCustomizing,
              onSelected: (_) {
                setState(() { 
                  _preset = 'short'; 
                  _controller.clear(); 
                  _isCustomizing = false;
                });
                widget.onPresetChanged('short');
              },
            ),
            ChoiceChip(
              label: const Text('中（2000字）'),
              selected: _preset == 'medium' && !_isCustomizing,
              onSelected: (_) {
                setState(() { 
                  _preset = 'medium'; 
                  _controller.clear(); 
                  _isCustomizing = false;
                });
                widget.onPresetChanged('medium');
              },
            ),
            ChoiceChip(
              label: const Text('长（3000字）'),
              selected: _preset == 'long' && !_isCustomizing,
              onSelected: (_) {
                setState(() { 
                  _preset = 'long'; 
                  _controller.clear(); 
                  _isCustomizing = false;
                });
                widget.onPresetChanged('long');
              },
            ),
            if (!_isCustomizing)
              ActionChip(
                label: const Text('自定义'),
                onPressed: () {
                  setState(() {
                    _isCustomizing = true;
                    _preset = null;
                  });
                  widget.onPresetChanged(null);
                },
              ),
          ],
        ),
        if (_isCustomizing) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '输入自定义字数，如 2500',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    setState(() {});
                    widget.onCustomChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isCustomizing = false;
                    _preset = 'long';
                    _controller.clear();
                  });
                  widget.onPresetChanged('long');
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}



