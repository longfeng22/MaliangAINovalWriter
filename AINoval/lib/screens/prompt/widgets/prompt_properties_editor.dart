import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_bloc.dart';
import 'package:ainoval/blocs/prompt_new/prompt_new_event.dart';
import 'package:ainoval/models/prompt_models.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 提示词属性编辑器
class PromptPropertiesEditor extends StatefulWidget {
  const PromptPropertiesEditor({
    super.key,
    required this.prompt,
  });

  final UserPromptInfo prompt;

  @override
  State<PromptPropertiesEditor> createState() => _PromptPropertiesEditorState();
}

class _PromptPropertiesEditorState extends State<PromptPropertiesEditor> {
  late TextEditingController _descriptionController;
  late List<String> _tags;
  late List<String> _categories;
  final TextEditingController _tagInputController = TextEditingController();
  final TextEditingController _categoryInputController = TextEditingController();
  bool _isEdited = false;
  bool get _isReadOnlyTemplate =>
      widget.prompt.id.startsWith('system_default_') ||
      widget.prompt.id.startsWith('public_');

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.prompt.description ?? '');
    _tags = List.from(widget.prompt.tags);
    _categories = []; // UserPromptInfo 没有 categories 字段，这里留空
  }

  @override
  void didUpdateWidget(PromptPropertiesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prompt.id != widget.prompt.id) {
      _descriptionController.text = widget.prompt.description ?? '';
      _tags = List.from(widget.prompt.tags);
      _categories = [];
      _isEdited = false;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagInputController.dispose();
    _categoryInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 页面标题
            _buildPageHeader(),
            
            const SizedBox(height: 24),
            
            // 描述
            _buildDescriptionEditor(),
            
            const SizedBox(height: 24),
            
            // 标签
            _buildTagsEditor(),
            
            const SizedBox(height: 24),
            
            // 分类
            _buildCategoriesEditor(),
            
            const SizedBox(height: 24),
            
            // 收藏状态
            _buildFavoriteToggle(),
            
            const SizedBox(height: 24),
            
            // 元数据
            _buildMetadata(),
            
            const SizedBox(height: 24),
            
            // 🆕 设定生成配置（仅对SETTING_TREE_GENERATION类型显示）
            if (widget.prompt.featureType == AIFeatureType.settingTreeGeneration &&
                widget.prompt.settingGenerationConfig != null) ...[
              _buildSettingGenerationConfigSection(),
              const SizedBox(height: 24),
            ],
            
            // 保存按钮（系统/公共模板不显示）
            if (!_isReadOnlyTemplate && _isEdited) _buildSaveButton(),
            
            // 底部留白
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 构建页面标题
  Widget _buildPageHeader() {
    return Row(
      children: [
        Icon(
          Icons.settings_outlined,
          size: 20,
          color: WebTheme.getTextColor(context),
        ),
        const SizedBox(width: 8),
        Text(
          '模板属性设置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
      ],
    );
  }

  /// 构建描述编辑器
  Widget _buildDescriptionEditor() {
    final isDark = WebTheme.isDarkMode(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              '模板描述',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '为模板添加详细的功能描述和使用说明',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isDark ? WebTheme.darkGrey50 : WebTheme.white,
          ),
          child: TextField(
            controller: _descriptionController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            readOnly: _isReadOnlyTemplate,
            decoration: InputDecoration(
              hintText: '输入模板描述...\n\n例如：用于生成小说角色对话的模板，适用于日常对话、情感表达等场景。',
              hintStyle: TextStyle(
                color: WebTheme.getSecondaryTextColor(context),
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: WebTheme.getTextColor(context),
            ),
            onChanged: (value) {
              if (!_isReadOnlyTemplate) {
                setState(() {
                  _isEdited = true;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  /// 构建标签编辑器
  Widget _buildTagsEditor() {
    final isDark = WebTheme.isDarkMode(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.label_outline,
              size: 16,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              '标签管理',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '添加相关标签便于分类和搜索模板',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        
        // 现有标签
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _tags.map((tag) => _buildEditableChip(
              tag,
              onDeleted: () {
                if (_isReadOnlyTemplate) return;
                setState(() {
                  _tags.remove(tag);
                  _isEdited = true;
                });
              },
            )).toList(),
          ),
        
        const SizedBox(height: 8),
        
        // 添加标签输入框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInputController,
                decoration: InputDecoration(
                  hintText: '添加标签...',
                  hintStyle: TextStyle(
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? WebTheme.darkGrey50 : WebTheme.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getTextColor(context),
                ),
                onSubmitted: _isReadOnlyTemplate ? null : _addTag,
                readOnly: _isReadOnlyTemplate,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.add,
                color: WebTheme.getTextColor(context),
              ),
              onPressed: _isReadOnlyTemplate ? null : () => _addTag(_tagInputController.text),
              tooltip: '添加标签',
            ),
          ],
        ),
      ],
    );
  }

  /// 构建分类编辑器
  Widget _buildCategoriesEditor() {
    final isDark = WebTheme.isDarkMode(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.category_outlined,
              size: 16,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              '分类管理',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '设置模板所属的功能分类，支持多级分类',
          style: TextStyle(
            fontSize: 12,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        
        // 现有分类
        if (_categories.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _categories.map((category) => _buildEditableChip(
              category,
              color: isDark ? Theme.of(context).colorScheme.primary.withOpacity(0.25) : Theme.of(context).colorScheme.primary.withOpacity(0.12),
              textColor: isDark ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.primary,
              onDeleted: () {
                if (_isReadOnlyTemplate) return;
                setState(() {
                  _categories.remove(category);
                  _isEdited = true;
                });
              },
            )).toList(),
          ),
        
        const SizedBox(height: 8),
        
        // 添加分类输入框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _categoryInputController,
                decoration: InputDecoration(
                  hintText: '添加分类...',
                  hintStyle: TextStyle(
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? WebTheme.darkGrey300 : WebTheme.grey300,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? WebTheme.darkGrey50 : WebTheme.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getTextColor(context),
                ),
                onSubmitted: _isReadOnlyTemplate ? null : _addCategory,
                readOnly: _isReadOnlyTemplate,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.add,
                color: WebTheme.getTextColor(context),
              ),
              onPressed: _isReadOnlyTemplate ? null : () => _addCategory(_categoryInputController.text),
              tooltip: '添加分类',
            ),
          ],
        ),
      ],
    );
  }

  /// 构建收藏开关
  Widget _buildFavoriteToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.isDarkMode(context) 
            ? WebTheme.darkGrey100.withOpacity(0.3)
            : WebTheme.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey200
              : WebTheme.grey200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            widget.prompt.isFavorite ? Icons.star : Icons.star_outline,
            size: 20,
            color: widget.prompt.isFavorite 
                ? Colors.amber
                : WebTheme.getTextColor(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '收藏模板',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '收藏后可在收藏列表中快速找到',
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: widget.prompt.isFavorite,
            onChanged: _isReadOnlyTemplate
                ? null
                : (value) {
                    context.read<PromptNewBloc>().add(ToggleFavoriteStatus(
                      promptId: widget.prompt.id,
                      isFavorite: value,
                    ));
                  },
          ),
        ],
      ),
    );
  }

  /// 构建元数据
  Widget _buildMetadata() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              '模板信息',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.isDarkMode(context) 
                ? WebTheme.darkGrey100.withOpacity(0.3)
                : WebTheme.grey50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: WebTheme.isDarkMode(context) 
                  ? WebTheme.darkGrey200
                  : WebTheme.grey200,
            ),
          ),
          child: Column(
            children: [
              _buildMetadataRow('创建时间', _formatDateTime(widget.prompt.updatedAt), Icons.access_time),
              const Divider(height: 16),
              _buildMetadataRow('更新时间', _formatDateTime(widget.prompt.updatedAt), Icons.update),
              const Divider(height: 16),
              _buildMetadataRow('使用次数', '${widget.prompt.usageCount}', Icons.trending_up),
              if (widget.prompt.lastUsedAt != null) ...[
                const Divider(height: 16),
                _buildMetadataRow('最后使用', _formatDateTime(widget.prompt.lastUsedAt!), Icons.schedule),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 构建元数据行
  Widget _buildMetadataRow(String label, String value, [IconData? icon]) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 构建可编辑芯片
  Widget _buildEditableChip(
    String label, {
    Color? color,
    Color? textColor,
    VoidCallback? onDeleted,
  }) {
    final isDark = WebTheme.isDarkMode(context);
    
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: textColor ?? (isDark ? WebTheme.white : WebTheme.getTextColor(context)),
        ),
      ),
      backgroundColor: color ?? (isDark ? WebTheme.darkGrey300 : WebTheme.grey200),
      deleteIcon: Icon(
        Icons.close,
        size: 16,
        color: textColor ?? (isDark ? WebTheme.white : WebTheme.getTextColor(context)),
      ),
      onDeleted: onDeleted,
    );
  }

  /// 🆕 构建设定生成配置区域
  Widget _buildSettingGenerationConfigSection() {
    final config = widget.prompt.settingGenerationConfig!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.settings_suggest_outlined,
              size: 16,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              '设定生成策略配置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.isDarkMode(context) 
                ? WebTheme.darkGrey100.withOpacity(0.3)
                : WebTheme.grey50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: WebTheme.isDarkMode(context) 
                  ? WebTheme.darkGrey200
                  : WebTheme.grey200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 策略名称
              if (config.strategyName != null) ...[
                _buildConfigRow('策略名称', config.strategyName!, Icons.label),
                const Divider(height: 16),
              ],
              
              // 策略描述
              if (config.description != null && config.description!.isNotEmpty) ...[
                _buildConfigRow('策略描述', config.description!, Icons.description),
                const Divider(height: 16),
              ],
              
              // 期望根节点数
              _buildConfigRow(
                '期望根节点数', 
                config.expectedRootNodes == -1 ? '不限制' : '${config.expectedRootNodes}',
                Icons.account_tree,
              ),
              const Divider(height: 16),
              
              // 最大深度
              _buildConfigRow('最大深度', '${config.maxDepth}', Icons.layers),
              
              // 节点模板配置
              if (config.nodeTemplates.isNotEmpty) ...[
                const Divider(height: 16),
                _buildConfigRow(
                  '节点模板数量', 
                  '${config.nodeTemplates.length} 个类型',
                  Icons.category,
                ),
              ],
              
              // 生成规则
              if (config.rules != null) ...[
                const Divider(height: 16),
                _buildConfigRow(
                  '批量生成数量', 
                  '${config.rules!.preferredBatchSize} (最多${config.rules!.maxBatchSize})',
                  Icons.batch_prediction,
                ),
                const Divider(height: 16),
                _buildConfigRow(
                  '描述长度范围', 
                  '${config.rules!.minDescriptionLength}-${config.rules!.maxDescriptionLength} 字符',
                  Icons.text_fields,
                ),
              ],
              
              // 系统策略标识
              if (config.isSystemStrategy) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.verified,
                      size: 16,
                      color: const Color(0xFF34C759),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '系统预设策略',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF34C759),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        // 详细节点模板列表（可折叠）
        if (config.nodeTemplates.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildNodeTemplatesExpansionPanel(config.nodeTemplates),
        ],
      ],
    );
  }
  
  /// 构建配置行
  Widget _buildConfigRow(String label, String value, [IconData? icon]) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: WebTheme.getSecondaryTextColor(context),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
  
  /// 构建节点模板可折叠面板
  Widget _buildNodeTemplatesExpansionPanel(List<NodeTemplateConfig> templates) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      backgroundColor: WebTheme.isDarkMode(context) 
          ? WebTheme.darkGrey100.withOpacity(0.3)
          : WebTheme.grey50,
      collapsedBackgroundColor: WebTheme.isDarkMode(context) 
          ? WebTheme.darkGrey100.withOpacity(0.3)
          : WebTheme.grey50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey200
              : WebTheme.grey200,
        ),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: WebTheme.isDarkMode(context) 
              ? WebTheme.darkGrey200
              : WebTheme.grey200,
        ),
      ),
      leading: Icon(
        Icons.category_outlined,
        size: 20,
        color: WebTheme.getTextColor(context),
      ),
      title: Text(
        '节点模板详情 (${templates.length})',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: WebTheme.getTextColor(context),
        ),
      ),
      children: templates.map((template) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WebTheme.isDarkMode(context) 
                ? WebTheme.darkGrey200.withOpacity(0.3)
                : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: WebTheme.isDarkMode(context) 
                  ? WebTheme.darkGrey300
                  : WebTheme.grey300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 节点类型标题
              Row(
                children: [
                  Icon(
                    Icons.label_outlined,
                    size: 14,
                    color: const Color(0xFF007AFF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    template.displayName ?? template.nodeType,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                ],
              ),
              
              // 描述
              if (template.description != null && template.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  template.description!,
                  style: TextStyle(
                    fontSize: 12,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
              
              // 数量范围
              if (template.minCount > 0 || template.maxCount != -1) ...[
                const SizedBox(height: 6),
                Text(
                  '数量范围: ${template.minCount} - ${template.maxCount == -1 ? "不限" : template.maxCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 构建保存按钮
  Widget _buildSaveButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.save, size: 16),
        label: const Text('保存更改'),
        onPressed: _saveChanges,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  /// 添加标签
  void _addTag(String tag) {
    final trimmedTag = tag.trim();
    if (trimmedTag.isNotEmpty && !_tags.contains(trimmedTag)) {
      setState(() {
        _tags.add(trimmedTag);
        _tagInputController.clear();
        _isEdited = true;
      });
    }
  }

  /// 添加分类
  void _addCategory(String category) {
    final trimmedCategory = category.trim();
    if (trimmedCategory.isNotEmpty && !_categories.contains(trimmedCategory)) {
      setState(() {
        _categories.add(trimmedCategory);
        _categoryInputController.clear();
        _isEdited = true;
      });
    }
  }

  /// 保存更改
  void _saveChanges() {
    final request = UpdatePromptTemplateRequest(
      description: _descriptionController.text.trim().isEmpty 
          ? null 
          : _descriptionController.text.trim(),
      tags: _tags,
      categories: _categories,
    );

    context.read<PromptNewBloc>().add(UpdatePromptDetails(
      promptId: widget.prompt.id,
      request: request,
    ));

    setState(() {
      _isEdited = false;
    });
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
} 