import 'package:flutter/material.dart';

import '../../../models/prompt_models.dart';
import '../../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../../utils/web_theme.dart';

/// 增强模板右侧编辑器（可创建/更新）
class EnhancedTemplateEditor extends StatefulWidget {
  final EnhancedUserPromptTemplate? template;
  final VoidCallback? onCancel;
  final ValueChanged<EnhancedUserPromptTemplate>? onSaved;

  const EnhancedTemplateEditor({
    super.key,
    this.template,
    this.onCancel,
    this.onSaved,
  });

  @override
  State<EnhancedTemplateEditor> createState() => _EnhancedTemplateEditorState();
}

class _EnhancedTemplateEditorState extends State<EnhancedTemplateEditor>
    with TickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _userPromptController;
  late final TextEditingController _tagsController;
  late final TextEditingController _authorIdController;
  late final TextEditingController _userIdController;
  late final TextEditingController _categoriesController;

  late String _featureType;
  late String _language;
  late bool _isVerified;
  bool _isSaving = false;

  late TabController _tabController;

  // 功能类型由 AIFeatureTypeHelper.allFeatures 动态提供

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final t = widget.template;
    _nameController = TextEditingController(text: t?.name ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _systemPromptController = TextEditingController(text: t?.systemPrompt ?? '');
    _userPromptController = TextEditingController(text: t?.userPrompt ?? '');
    _tagsController = TextEditingController(text: (t?.tags ?? const []).join(', '));
    _authorIdController = TextEditingController(text: t?.authorId ?? 'system');
    _userIdController = TextEditingController(text: t?.userId ?? 'system');
    _categoriesController = TextEditingController(text: (t?.categories ?? const []).join(', '));
    _featureType = t?.featureType.toApiString() ?? 'TEXT_EXPANSION';
    _language = t?.language ?? 'zh';
    _isVerified = t?.isVerified ?? false;
  }

  @override
  void didUpdateWidget(covariant EnhancedTemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template?.id != widget.template?.id) {
      final t = widget.template;
      _nameController.text = t?.name ?? '';
      _descriptionController.text = t?.description ?? '';
      _systemPromptController.text = t?.systemPrompt ?? '';
      _userPromptController.text = t?.userPrompt ?? '';
      _tagsController.text = (t?.tags ?? const []).join(', ');
      setState(() {
        _featureType = t?.featureType.toApiString() ?? 'TEXT_EXPANSION';
        _language = t?.language ?? 'zh';
        _isVerified = t?.isVerified ?? false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _systemPromptController.dispose();
    _userPromptController.dispose();
    _tagsController.dispose();
    _authorIdController.dispose();
    _userIdController.dispose();
    _categoriesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.template == null;
    return Column(
      children: [
        _buildTopBar(isCreate),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildContentTab(),
              _buildPropertiesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(bool isCreate) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.onCancel != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: _isSaving ? null : widget.onCancel,
            ),
          Expanded(
            child: TextField(
              controller: _nameController,
              decoration: WebTheme.getBorderlessInputDecoration(
                hintText: isCreate ? '输入新模板名称…' : '编辑模板名称…',
                context: context,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 16),
            label: Text(_isSaving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(color: WebTheme.getBorderColor(context), width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: WebTheme.getPrimaryColor(context),
        unselectedLabelColor: WebTheme.getSecondaryTextColor(context),
        indicatorColor: WebTheme.getPrimaryColor(context),
        tabs: const [
          Tab(icon: Icon(Icons.notes_outlined, size: 18), text: '提示词内容'),
          Tab(icon: Icon(Icons.tune, size: 18), text: '基础信息'),
        ],
      ),
    );
  }

  Widget _buildContentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextFormField(
            controller: _systemPromptController,
            decoration: const InputDecoration(
              labelText: '系统提示词 *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.multiline,
            minLines: 6,
            maxLines: null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _userPromptController,
            decoration: const InputDecoration(
              labelText: '用户提示词 *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.multiline,
            minLines: 6,
            maxLines: null,
          ),
        ],
      ),
    );
  }

  Widget _buildPropertiesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '模板描述',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: '用户ID (userId)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _authorIdController,
                  decoration: const InputDecoration(
                    labelText: '作者ID (authorId)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _featureType,
            decoration: const InputDecoration(
              labelText: '功能类型 *',
              border: OutlineInputBorder(),
            ),
            items: AIFeatureTypeHelper.allFeatures
                .map((t) => DropdownMenuItem<String>(
                      value: t.toApiString(),
                      child: Text(t.displayName),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _featureType = v ?? _featureType),
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
            onChanged: (v) => setState(() => _language = v ?? _language),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: '标签（用逗号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _categoriesController,
            decoration: const InputDecoration(
              labelText: '分类（用逗号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text('设为官方认证模板'),
            value: _isVerified,
            onChanged: (v) => setState(() => _isVerified = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板名称不能为空')));
      return;
    }
    if (_systemPromptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示词不能为空')));
      return;
    }
    if (_userPromptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('用户提示词不能为空')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final adminRepo = AdminRepositoryImpl();
      final List<String> tags = _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final List<String> categories = _categoriesController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      EnhancedUserPromptTemplate saved;
      if (widget.template != null) {
        final updated = widget.template!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          systemPrompt: _systemPromptController.text.trim(),
          userPrompt: _userPromptController.text.trim(),
          tags: tags,
          categories: categories,
          language: _language,
          featureType: _getFeatureTypeFromString(_featureType),
          isVerified: _isVerified,
          userId: _userIdController.text.trim().isEmpty ? null : _userIdController.text.trim(),
          authorId: _authorIdController.text.trim().isEmpty ? null : _authorIdController.text.trim(),
        );
        saved = await adminRepo.updateEnhancedTemplate(widget.template!.id, updated);
      } else {
        final now = DateTime.now();
        final t = EnhancedUserPromptTemplate(
          id: '',
          userId: _userIdController.text.trim().isEmpty ? 'system' : _userIdController.text.trim(),
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          featureType: _getFeatureTypeFromString(_featureType),
          systemPrompt: _systemPromptController.text.trim(),
          userPrompt: _userPromptController.text.trim(),
          tags: tags,
          categories: categories,
          createdAt: now,
          updatedAt: now,
          isPublic: true,
          isVerified: _isVerified,
          version: 1,
          language: _language,
          authorId: _authorIdController.text.trim().isEmpty ? null : _authorIdController.text.trim(),
        );
        saved = await adminRepo.createOfficialEnhancedTemplate(t);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板保存成功')));
        widget.onSaved?.call(saved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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


