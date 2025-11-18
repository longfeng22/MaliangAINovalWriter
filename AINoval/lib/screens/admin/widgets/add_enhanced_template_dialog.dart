import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/web_theme.dart';
import '../../../widgets/common/dialog_container.dart';
import '../../../widgets/common/dialog_header.dart';

/// 添加增强模板对话框
class AddEnhancedTemplateDialog extends StatefulWidget {
  final EnhancedUserPromptTemplate? template;
  final VoidCallback? onSuccess;
  final ValueChanged<EnhancedUserPromptTemplate>? onUpdated;

  const AddEnhancedTemplateDialog({
    Key? key,
    this.template,
    this.onSuccess,
    this.onUpdated,
  }) : super(key: key);

  @override
  State<AddEnhancedTemplateDialog> createState() => _AddEnhancedTemplateDialogState();
}

class _AddEnhancedTemplateDialogState extends State<AddEnhancedTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _userPromptController = TextEditingController();
  final _tagsController = TextEditingController();
  
  String _featureType = 'TEXT_EXPANSION';
  String _language = 'zh';
  bool _isVerified = false;
  bool _isLoading = false;

  // 功能类型由 AIFeatureTypeHelper.allFeatures 动态提供

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，填充现有数据
    if (widget.template != null) {
      final template = widget.template!;
      _nameController.text = template.name;
      _descriptionController.text = template.description ?? '';
      _systemPromptController.text = template.systemPrompt;
      _userPromptController.text = template.userPrompt;
      _tagsController.text = template.tags.join(', ');
      _featureType = template.featureType.toApiString();
      _language = template.language ?? 'zh';
      _isVerified = template.isVerified;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _systemPromptController.dispose();
    _userPromptController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogHeader(
            title: widget.template != null ? '编辑模板' : '添加官方模板',
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfo(),
                    const SizedBox(height: 24),
                    _buildPromptContent(),
                    const SizedBox(height: 24),
                    _buildAdvancedSettings(),
                  ],
                ),
              ),
            ),
          ),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '基础信息',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '模板名称 *',
            hintText: '请输入模板名称',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入模板名称';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: '模板描述',
            hintText: '请输入模板描述',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _featureType,
          decoration: const InputDecoration(
            labelText: '功能类型 *',
            border: OutlineInputBorder(),
          ),
          items: AIFeatureTypeHelper.allFeatures.map((type) {
            final api = type.toApiString();
            return DropdownMenuItem(
              value: api,
              child: Text(type.displayName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _featureType = value;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _tagsController,
          decoration: const InputDecoration(
            labelText: '标签',
            hintText: '请输入标签，用逗号分隔',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '提示词内容',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _systemPromptController,
          decoration: const InputDecoration(
            labelText: '系统提示词',
            hintText: '请输入系统提示词内容',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入系统提示词内容';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _userPromptController,
          decoration: const InputDecoration(
            labelText: '用户提示词',
            hintText: '请输入用户提示词内容',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '请输入用户提示词内容';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '高级设置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: WebTheme.getTextColor(context),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _language,
          decoration: const InputDecoration(
            labelText: '语言',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'zh', child: Text('中文')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ja', child: Text('日本語')),
            DropdownMenuItem(value: 'ko', child: Text('한국어')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _language = value;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          title: const Text('设为官方认证模板'),
          subtitle: const Text('官方认证的模板会显示认证标识'),
          value: _isVerified,
          onChanged: (value) {
            setState(() {
              _isVerified = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          top: BorderSide(
            color: WebTheme.getBorderColor(context),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _createTemplate,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.template != null ? '更新' : '创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTemplate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      EnhancedUserPromptTemplate? saved;
      // 解析标签
      List<String> tags = [];
      if (_tagsController.text.trim().isNotEmpty) {
        tags = _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList();
      }

      final adminRepository = AdminRepositoryImpl();
      
      if (widget.template != null) {
        // 编辑模式 - 更新现有模板
        final updatedTemplate = widget.template!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty 
              ? _descriptionController.text.trim() 
              : null,
          featureType: _getFeatureTypeFromString(_featureType),
          systemPrompt: _systemPromptController.text.trim(),
          userPrompt: _userPromptController.text.trim(),
          tags: tags,
          language: _language,
          isVerified: _isVerified,
        );
        
        saved = await adminRepository.updateEnhancedTemplate(
          widget.template!.id,
          updatedTemplate,
        );
      } else {
        // 创建模式 - 新建模板
        final now = DateTime.now();
        final template = EnhancedUserPromptTemplate(
          id: '', // 将由后端生成
          userId: 'admin', // 管理员创建
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty 
              ? _descriptionController.text.trim() 
              : null,
          featureType: _getFeatureTypeFromString(_featureType),
          systemPrompt: _systemPromptController.text.trim(),
          userPrompt: _userPromptController.text.trim(),
          tags: tags,
          createdAt: now,
          updatedAt: now,
          isPublic: true, // 官方模板默认为公开
          isVerified: _isVerified,
          version: 1,
          language: _language,
        );

        saved = await adminRepository.createOfficialEnhancedTemplate(template);
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        if (widget.onUpdated != null) {
          widget.onUpdated!(saved);
        } else {
          widget.onSuccess?.call();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.template != null ? '模板更新成功' : '官方模板创建成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  AIFeatureType _getFeatureTypeFromString(String featureType) {
    switch (featureType) {
      case 'TEXT_EXPANSION':
        return AIFeatureType.textExpansion;
      case 'TEXT_REFACTOR':
        return AIFeatureType.textRefactor;
      case 'TEXT_SUMMARY':
        return AIFeatureType.textSummary;
      case 'AI_CHAT':
        return AIFeatureType.aiChat;
      case 'NOVEL_GENERATION':
        return AIFeatureType.novelGeneration;
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return AIFeatureType.professionalFictionContinuation;
      case 'SCENE_BEAT_GENERATION':
        return AIFeatureType.sceneBeatGeneration;
      case 'SCENE_TO_SUMMARY':
        return AIFeatureType.sceneToSummary;
      case 'SUMMARY_TO_SCENE':
        return AIFeatureType.summaryToScene;
      case 'NOVEL_COMPOSE':
        return AIFeatureType.novelCompose;
      case 'SETTING_TREE_GENERATION':
        return AIFeatureType.settingTreeGeneration;
      case 'STORY_PLOT_CONTINUATION':
        return AIFeatureType.storyPlotContinuation;
      default:
        return AIFeatureType.textExpansion;
    }
  }
}