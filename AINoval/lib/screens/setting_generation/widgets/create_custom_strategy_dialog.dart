import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service/repositories/prompt_repository.dart';
import '../../../models/prompt_models.dart';
import '../../../services/api_service/repositories/setting_generation_repository.dart';
import '../../../utils/logger.dart';

/// 创建/编辑自定义策略对话框
class CreateCustomStrategyDialog extends StatefulWidget {
  final Map<String, dynamic>? strategy; // 亦可复用为提示词复制时的模板数据
  final bool isPromptMode; // 普通提示词复制模式（隐藏部分组件，并走提示词接口）

  const CreateCustomStrategyDialog({super.key, this.strategy, this.isPromptMode = false});

  @override
  State<CreateCustomStrategyDialog> createState() => _CreateCustomStrategyDialogState();
}

class _CreateCustomStrategyDialogState extends State<CreateCustomStrategyDialog> {
  static const String _tag = 'CreateCustomStrategyDialog';
  
  late final SettingGenerationRepository _repository;
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _userPromptController;
  late final TextEditingController _expectedRootNodesController;
  late final TextEditingController _maxDepthController;
  
  bool _isSaving = false;
  bool _hidePrompts = false; // 是否隐藏提示词
  String? _baseStrategyId;
  final List<Map<String, dynamic>> _nodeTemplates = [];

  @override
  void initState() {
    super.initState();
    _repository = context.read<SettingGenerationRepository>();
    
    // 初始化控制器
    final strategy = widget.strategy;
    _nameController = TextEditingController(text: strategy?['name'] ?? '');
    _descriptionController = TextEditingController(text: strategy?['description'] ?? '');
    // ✅ 确保提示词正确回显
    _systemPromptController = TextEditingController(text: strategy?['systemPrompt'] ?? '');
    _userPromptController = TextEditingController(text: strategy?['userPrompt'] ?? '');
    _expectedRootNodesController = TextEditingController(
      text: (strategy?['expectedRootNodes'] ?? 8).toString(),
    );
    _maxDepthController = TextEditingController(
      text: (strategy?['maxDepth'] ?? 3).toString(),
    );
    
    if (strategy != null && strategy['nodeTemplates'] != null) {
      _nodeTemplates.addAll((strategy['nodeTemplates'] as List).cast<Map<String, dynamic>>());
    }
    
    _hidePrompts = strategy?['hidePrompts'] as bool? ?? false;
    
    // 调试输出
    AppLogger.info(_tag, '初始化策略数据: name=${strategy?['name']}, systemPrompt length=${_systemPromptController.text.length}, userPrompt length=${_userPromptController.text.length}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _systemPromptController.dispose();
    _userPromptController.dispose();
    _expectedRootNodesController.dispose();
    _maxDepthController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (widget.isPromptMode) {
        // 提示词复制模式：调用提示词接口创建副本
        final promptRepo = context.read<PromptRepository>();
        // 复制来源ID来自 strategy['id'] or strategy['templateId']
        final sourceId = (widget.strategy?['id'] as String?) ?? (widget.strategy?['templateId'] as String?) ?? '';
        final copied = await promptRepo.copyPublicEnhancedTemplate(sourceId);
        // 紧接着更新名称/描述/提示词内容
        await promptRepo.updateEnhancedPromptTemplate(
          copied.id,
          UpdatePromptTemplateRequest(
            name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            systemPrompt: _systemPromptController.text.trim(),
            userPrompt: _userPromptController.text.trim(),
          ),
        );
      } else {
        final requestData = {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'systemPrompt': _systemPromptController.text.trim(),
          'userPrompt': _userPromptController.text.trim(),
          'nodeTemplates': _nodeTemplates,
          'expectedRootNodes': int.tryParse(_expectedRootNodesController.text) ?? 8,
          'maxDepth': int.tryParse(_maxDepthController.text) ?? 3,
          'hidePrompts': _hidePrompts,
          if (_baseStrategyId != null) 'baseStrategyId': _baseStrategyId,
        };

        // 判断是创建新策略还是更新现有策略
        final strategyId = widget.strategy?['id'] as String?;
        final isCreating = strategyId == null || strategyId.isEmpty;
        if (isCreating) {
          await _repository.createCustomStrategy(
            name: requestData['name'] as String,
            description: requestData['description'] as String,
            systemPrompt: requestData['systemPrompt'] as String,
            userPrompt: requestData['userPrompt'] as String,
            nodeTemplates: requestData['nodeTemplates'] as List<Map<String, dynamic>>,
            expectedRootNodes: requestData['expectedRootNodes'] as int,
            maxDepth: requestData['maxDepth'] as int,
            baseStrategyId: _baseStrategyId,
            hidePrompts: _hidePrompts,
          );
        } else {
          await _repository.updateStrategy(
            strategyId: strategyId,
            name: requestData['name'] as String,
            description: requestData['description'] as String,
            systemPrompt: requestData['systemPrompt'] as String,
            userPrompt: requestData['userPrompt'] as String,
            nodeTemplates: requestData['nodeTemplates'] as List<Map<String, dynamic>>,
            expectedRootNodes: requestData['expectedRootNodes'] as int,
            maxDepth: requestData['maxDepth'] as int,
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isPromptMode ? '模板复制成功' : '策略保存成功'),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      AppLogger.error(_tag, '保存策略失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final isEditing = widget.strategy != null;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: screenSize.width < 600 ? screenSize.width * 0.95 : 
               screenSize.width < 1000 ? 900 : 1000,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.9,
        ),
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
              _buildHeader(theme, isDark, isEditing),
              Flexible(
                child: _buildBody(theme, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark, bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
                  : [const Color(0xFF5856D6), const Color(0xFF4947CC)],
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF5E5CE6) : const Color(0xFF5856D6)).withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.edit_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEditing ? '编辑策略' : '创建策略',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.close,
                size: 16,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名称
            _buildSection(
              theme,
              isDark,
              title: widget.isPromptMode ? '模板名称' : '策略名称',
              icon: Icons.label_rounded,
              child: _buildTextField(
                theme,
                isDark,
                controller: _nameController,
                hintText: widget.isPromptMode ? '请输入模板名称' : '请输入策略名称',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return widget.isPromptMode ? '模板名称不能为空' : '策略名称不能为空';
                  }
                  return null;
                },
              ),
            ),
            
            const SizedBox(height: 12),
            
            // 描述
            _buildSection(
              theme,
              isDark,
              title: widget.isPromptMode ? '模板描述' : '策略描述',
              icon: Icons.description_rounded,
              child: _buildTextField(
                theme,
                isDark,
                controller: _descriptionController,
                hintText: widget.isPromptMode ? '请输入模板描述（可选）' : '请输入策略描述',
                maxLines: 3,
                validator: (value) {
                  if (!widget.isPromptMode) {
                    if (value == null || value.trim().isEmpty) {
                      return '策略描述不能为空';
                    }
                  }
                  return null;
                },
              ),
            ),
            
            const SizedBox(height: 12),
            
            // 提示词 - 左右分栏布局（提示词复制模式也展示，便于用户修改系统/用户提示词）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左栏：系统提示词
                Expanded(
                  child: _buildSection(
                    theme,
                    isDark,
                    title: '系统提示词',
                    subtitle: 'System Prompt',
                    icon: Icons.settings_suggest_rounded,
                    child: _buildTextField(
                      theme,
                      isDark,
                      controller: _systemPromptController,
                      hintText: '请输入系统提示词（必填）',
                      maxLines: 22,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '系统提示词不能为空';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // 右栏：用户提示词
                Expanded(
                  child: _buildSection(
                    theme,
                    isDark,
                    title: '用户提示词',
                    subtitle: 'User Prompt',
                    icon: Icons.person_rounded,
                    child: _buildTextField(
                      theme,
                      isDark,
                      controller: _userPromptController,
                      hintText: '请输入用户提示词（必填）',
                      maxLines: 22,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '用户提示词不能为空';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 高级设置（提示词复制模式下隐藏）
            if (!widget.isPromptMode) ...[
            _buildSection(
              theme,
              isDark,
              title: '高级设置',
              icon: Icons.tune_rounded,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '预期根节点数',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildTextField(
                              theme,
                              isDark,
                              controller: _expectedRootNodesController,
                              hintText: '例如: 8',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final num = int.tryParse(value ?? '');
                                if (num == null || num <= 0) {
                                  return '请输入有效数字';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '最大深度',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildTextField(
                              theme,
                              isDark,
                              controller: _maxDepthController,
                              hintText: '例如: 3',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final num = int.tryParse(value ?? '');
                                if (num == null || num <= 0) {
                                  return '请输入有效数字';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 隐藏提示词开关
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 18,
                          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '隐藏提示词',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '开启后，其他用户可以使用您的策略但无法查看提示词内容',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _hidePrompts,
                          onChanged: (value) {
                            setState(() {
                              _hidePrompts = value;
                            });
                          },
                          activeColor: const Color(0xFF34C759),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ],
            
            const SizedBox(height: 16),
            
            // 保存按钮 - iOS风格
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _isSaving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isSaving
                          ? [Colors.grey, Colors.grey]
                          : (isDark
                              ? [const Color(0xFF0A84FF), const Color(0xFF0066CC)]
                              : [const Color(0xFF007AFF), const Color(0xFF0051D5)]),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _isSaving ? [] : [
                      BoxShadow(
                        color: (isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF)).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _isSaving
                      ? const Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            _getSaveButtonText(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取保存按钮文字
  String _getSaveButtonText() {
    if (widget.isPromptMode) return '复制模板';
    final strategyId = widget.strategy?['id'] as String?;
    if (strategyId == null || strategyId.isEmpty) return '创建策略';
    return '保存修改';
  }

  Widget _buildSection(
    ThemeData theme,
    bool isDark, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getIconGradient(icon, isDark),
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: _getIconGradient(icon, isDark)[0].withOpacity(0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(icon, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  List<Color> _getIconGradient(IconData icon, bool isDark) {
    if (icon == Icons.label_rounded) {
      return isDark 
        ? [const Color(0xFF0A84FF), const Color(0xFF0066CC)]
        : [const Color(0xFF007AFF), const Color(0xFF0051D5)];
    } else if (icon == Icons.description_rounded) {
      return isDark 
        ? [const Color(0xFFFF9500), const Color(0xFFFF6B00)]
        : [const Color(0xFFFF9F0A), const Color(0xFFFF7A00)];
    } else if (icon == Icons.settings_suggest_rounded) {
      return isDark 
        ? [const Color(0xFF5E5CE6), const Color(0xFF4E4CD9)]
        : [const Color(0xFF5856D6), const Color(0xFF4947CC)];
    } else if (icon == Icons.person_rounded) {
      return isDark 
        ? [const Color(0xFF32ADE6), const Color(0xFF0A84FF)]
        : [const Color(0xFF30B0C7), const Color(0xFF007AFF)];
    } else if (icon == Icons.tune_rounded) {
      return isDark 
        ? [const Color(0xFF34C759), const Color(0xFF2BA746)]
        : [const Color(0xFF34C759), const Color(0xFF2BA746)];
    }
    return isDark 
      ? [const Color(0xFF0A84FF), const Color(0xFF0066CC)]
      : [const Color(0xFF007AFF), const Color(0xFF0051D5)];
  }

  Widget _buildTextField(
    ThemeData theme,
    bool isDark, {
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white : Colors.black,
        letterSpacing: -0.2,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43).withOpacity(0.5),
          letterSpacing: -0.2,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFFFF3B30),
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFFFF3B30),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }
}
