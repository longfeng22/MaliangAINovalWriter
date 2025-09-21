import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ainoval/utils/logger.dart';

class Debouncer {

  Debouncer({this.delay = const Duration(milliseconds: 500)});
  Timer? _timer;
  final Duration delay;

  void run(Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

class EditableTitle extends StatefulWidget {

  const EditableTitle({
    Key? key,
    required this.initialText,
    this.onChanged,
    this.onSubmitted,
    this.commitOnBlur = true,
    this.style,
    this.textAlign = TextAlign.left,
    this.autofocus = false,
  }) : super(key: key);
  final String initialText;
  // 可选：仅用于本地UI联动（不做持久化）
  final Function(String)? onChanged;
  // 提交时回调：回车或失焦触发
  final Function(String)? onSubmitted;
  // 失焦时是否提交
  final bool commitOnBlur;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;

  @override
  State<EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends State<EditableTitle> {
  late TextEditingController _controller;
  late Debouncer _debouncer;
  late FocusNode _focusNode;
  String _lastCommittedText = '';
  bool _isCommitting = false; // 🚀 新增：标记是否正在提交

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _debouncer = Debouncer();
    _focusNode = FocusNode();
    _lastCommittedText = widget.initialText;

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && widget.commitOnBlur) {
        AppLogger.i('EditableTitle', '📤 失焦触发提交');
        _commitIfChanged();
      }
    });
  }

  @override
  void didUpdateWidget(EditableTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText) {
      AppLogger.i('EditableTitle', 
          '外部更新: "${oldWidget.initialText}" -> "${widget.initialText}", '
          '当前输入: "${_controller.text}", 有焦点: ${_focusNode.hasFocus}, 提交中: $_isCommitting');
          
      // 🚀 修复：如果用户正在编辑或正在提交，不要覆盖用户的输入
      if (_focusNode.hasFocus || _isCommitting) {
        // 用户正在编辑或提交中，不更新文本内容，但更新基线用于后续比较
        _lastCommittedText = widget.initialText;
        AppLogger.i('EditableTitle', '保护用户输入，仅更新基线');
      } else {
        // 用户没有焦点且未在提交，可以安全更新
        _controller.text = widget.initialText;
        _lastCommittedText = widget.initialText;
        AppLogger.i('EditableTitle', '安全更新文本内容');
      }
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitIfChanged() {
    final current = _controller.text;
    AppLogger.i('EditableTitle', 
        '尝试提交: 当前文本="$current", 上次提交="$_lastCommittedText"');
        
    if (current != _lastCommittedText) {
      AppLogger.i('EditableTitle', '✅ 检测到变化，开始提交');
      // 🚀 修复：标记正在提交，防止在提交期间被外部更新覆盖
      _isCommitting = true;
      _lastCommittedText = current;
      
      if (widget.onSubmitted != null) {
        AppLogger.i('EditableTitle', '📤 调用onSubmitted回调: "$current"');
        widget.onSubmitted!(current);
      }
      
      // 🚀 延迟清除提交标记，给外部更新一些时间
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _isCommitting = false;
          AppLogger.i('EditableTitle', '🏁 提交完成，清除标记');
        }
      });
    } else {
      AppLogger.i('EditableTitle', '⏭️ 无变化，跳过提交');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: widget.style,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        textAlign: widget.textAlign,
        autofocus: widget.autofocus,
        // onChanged 仅用于本地UI联动（不持久化）
        onChanged: (value) {
          if (widget.onChanged != null) {
            _debouncer.run(() {
              widget.onChanged!(value);
            });
          }
        },
        // 按下回车时提交
        onSubmitted: (_) {
          AppLogger.i('EditableTitle', '⌨️ 回车触发提交');
          _commitIfChanged();
        },
      ),
    );
  }
}