import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import '../../../models/setting_node.dart';
import '../../../models/setting_type.dart';
import '../../../widgets/common/top_toast.dart';

/// 添加子节点表单组件
class AddChildNodeForm extends StatefulWidget {
  final SettingNode parentNode;
  final VoidCallback onCancel;
  final Function(String title, String content, SettingType type) onSave;

  const AddChildNodeForm({
    Key? key,
    required this.parentNode,
    required this.onCancel,
    required this.onSave,
  }) : super(key: key);

  @override
  State<AddChildNodeForm> createState() => _AddChildNodeFormState();
}

class _AddChildNodeFormState extends State<AddChildNodeForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  
  SettingType _selectedType = SettingType.other; // 默认类型
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    
    // 初始化动画
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    
    // 开始动画
    _animationController.forward();
    
    // 根据父节点类型智能推荐子节点类型
    _selectedType = _getRecommendedChildType(widget.parentNode.type);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// 根据父节点类型推荐子节点类型
  SettingType _getRecommendedChildType(SettingType parentType) {
    switch (parentType) {
      case SettingType.character:
        return SettingType.character; // 人物关系、属性等
      case SettingType.location:
        return SettingType.location; // 子区域、地标等
      case SettingType.faction:
        return SettingType.character; // 组织成员
      case SettingType.worldview:
        return SettingType.concept; // 世界观概念
      case SettingType.magicSystem:
        return SettingType.concept; // 魔法概念
      default:
        return SettingType.other;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: Container(
        margin: const EdgeInsets.only(
          left: 32, // 缩进，表示是子节点
          right: 8,
          top: 4,
          bottom: 8,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark 
              ? const Color(0xFF1F2937)
              : const Color(0xFFFAFAFA),
          border: Border.all(
            color: isDark 
                ? const Color(0xFF374151)
                : const Color(0xFFE5E7EB),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: isDark 
                  ? Colors.black.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 表单标题
              Row(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: WebTheme.getPrimaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '为 "${widget.parentNode.name}" 添加子设定',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // 设定类型选择
              Text(
                '设定类型',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              _buildTypeDropdown(),
              const SizedBox(height: 16),
              
              // 标题输入框
              Text(
                '设定标题',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: '请输入设定标题',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark 
                          ? const Color(0xFF374151)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark 
                          ? const Color(0xFF374151)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: WebTheme.getPrimaryColor(context),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark 
                      ? const Color(0xFF374151).withOpacity(0.3)
                      : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getTextColor(context),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '标题不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // 内容输入框
              Text(
                '设定内容',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contentController,
                maxLines: null, // 自适应高度
                minLines: 3,
                decoration: InputDecoration(
                  hintText: '请输入设定的详细内容...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark 
                          ? const Color(0xFF374151)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark 
                          ? const Color(0xFF374151)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: WebTheme.getPrimaryColor(context),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark 
                      ? const Color(0xFF374151).withOpacity(0.3)
                      : Colors.white,
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getTextColor(context),
                  height: 1.5,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '内容不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : _onCancel,
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: isDark 
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF6B7280),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WebTheme.getPrimaryColor(context),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            '保存',
                            style: TextStyle(fontSize: 14),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建类型下拉选择框
  Widget _buildTypeDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DropdownButtonFormField<SettingType>(
      value: _selectedType,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDark 
                ? const Color(0xFF374151)
                : const Color(0xFFD1D5DB),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDark 
                ? const Color(0xFF374151)
                : const Color(0xFFD1D5DB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: WebTheme.getPrimaryColor(context),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: isDark 
            ? const Color(0xFF374151).withOpacity(0.3)
            : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      style: TextStyle(
        fontSize: 14,
        color: WebTheme.getTextColor(context),
      ),
      dropdownColor: isDark 
          ? const Color(0xFF1F2937)
          : Colors.white,
      items: SettingType.values.map((type) {
        return DropdownMenuItem<SettingType>(
          value: type,
          child: Text(
            type.displayName,
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getTextColor(context),
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedType = value;
          });
        }
      },
    );
  }

  /// 取消操作
  void _onCancel() {
    _animationController.reverse().then((_) {
      widget.onCancel();
    });
  }

  /// 提交表单
  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isSubmitting = true;
      });
      
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();
      
      try {
        widget.onSave(title, content, _selectedType);
      } catch (e) {
        setState(() {
          _isSubmitting = false;
        });
        TopToast.error(context, '保存失败: $e');
      }
    }
  }
}

