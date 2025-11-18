// import 'dart:math'; // Added for min function
import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_type.dart'; // Your SettingType enum
import 'package:ainoval/blocs/ai_setting_generation/ai_setting_generation_bloc.dart'; // Correct BLoC import
import 'package:ainoval/models/novel_structure.dart'; // Import for Chapter model
import 'package:ainoval/services/api_service/repositories/editor_repository.dart'; // Import EditorRepository
import 'package:ainoval/services/api_service/repositories/novel_ai_repository.dart'; // Needed for BLoC creation
import 'package:ainoval/blocs/setting/setting_bloc.dart'; 
import 'package:ainoval/widgets/common/model_display_selector.dart'; // 通用模型显示选择器
import 'package:ainoval/models/unified_ai_model.dart'; // 统一AI模型
import 'package:ainoval/utils/logger.dart';

// Removed placeholder BLoC, State, and Event definitions

class AISettingGenerationPanel extends StatelessWidget {
  final String novelId;
  final VoidCallback onClose; 
  final bool isCardMode;      
  final EditorRepository editorRepository; // Added
  final NovelAIRepository novelAIRepository; // Added

  const AISettingGenerationPanel({
    Key? key,
    required this.novelId,
    required this.onClose,
    required this.editorRepository, // Added
    required this.novelAIRepository, // Added
    this.isCardMode = false, 
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AISettingGenerationBloc>(
      create: (context) => AISettingGenerationBloc(
        editorRepository: editorRepository, // Changed from context.read
        novelAIRepository: novelAIRepository, // Changed from context.read
      )..add(LoadInitialDataForAISettingPanel(novelId)),
      child: AISettingGenerationView(novelId: novelId),
    );
  }
}

class AISettingGenerationView extends StatefulWidget {
  final String novelId;
  const AISettingGenerationView({Key? key, required this.novelId}) : super(key: key);

  @override
  State<AISettingGenerationView> createState() => _AISettingGenerationViewState();
}

// 章节选择项数据模型
class ChapterOption {
  final String id;
  final String title;
  final int order;
  final int globalOrder; // 全局排序序号
  final String actTitle;
  final int actOrder;
  
  ChapterOption({
    required this.id,
    required this.title,
    required this.order,
    required this.globalOrder,
    required this.actTitle,
    required this.actOrder,
  });
  
  String get displayTitle {
    final chapterTitle = title.isNotEmpty ? title : '无标题章节';
    return '第${globalOrder}章 $chapterTitle';
  }
  
  String get actDisplayTitle {
    return actTitle.isNotEmpty ? actTitle : '第${actOrder}卷';
  }
}

class _AISettingGenerationViewState extends State<AISettingGenerationView> {
  String? _selectedStartChapterId;
  String? _selectedEndChapterId;
  final List<SettingTypeOption> _settingTypeOptions = 
      SettingType.values.map((type) => SettingTypeOption(type)).toList();
  final _maxSettingsController = TextEditingController(text: '3');
  final _instructionsController = TextEditingController();
  UnifiedAIModel? _selectedModel; // 选中的模型

  final _formKey = GlobalKey<FormState>();
  
  // 生成排序后的章节选项列表
  List<ChapterOption> _generateChapterOptions(List<Chapter> chapters, Novel? novel) {
    List<ChapterOption> options = [];
    int globalOrder = 1;
    
    if (novel == null) {
      // 回退方案：没有Novel信息时，简单排序
      chapters.sort((a, b) => a.order.compareTo(b.order));
      for (final chapter in chapters) {
        options.add(ChapterOption(
          id: chapter.id,
          title: chapter.title,
          order: chapter.order,
          globalOrder: globalOrder++,
          actTitle: '',
          actOrder: 1,
        ));
      }
    } else {
      // 有Novel信息时，按Act和章节顺序正确排序
      final sortedActs = novel.acts..sort((a, b) => a.order.compareTo(b.order));
      
      for (final act in sortedActs) {
        final sortedChapters = act.chapters..sort((a, b) => a.order.compareTo(b.order));
        
        for (final chapter in sortedChapters) {
          // 只处理在chapters列表中的章节（可能有过滤）
          if (chapters.any((c) => c.id == chapter.id)) {
            options.add(ChapterOption(
              id: chapter.id,
              title: chapter.title,
              order: chapter.order,
              globalOrder: globalOrder++,
              actTitle: act.title,
              actOrder: act.order,
            ));
          }
        }
      }
    }
    
    return options;
  }

  // 显示AI设定生成原理说明对话框
  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: WebTheme.getPrimaryColor(context),
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'AI设定生成原理',
              style: TextStyle(
                color: WebTheme.getTextColor(context),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpSection(
                context,
                icon: Icons.analytics_outlined,
                title: '1. 智能分析章节内容',
                content: 'AI会深度分析您选择的章节范围内的所有内容，理解故事情节、场景描写和角色互动。',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                context,
                icon: Icons.link,
                title: '2. 关联已有设定',
                content: 'AI会自动查询您小说中已有的所有设定（角色、地点、物品等），并识别它们之间的关联关系。',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                context,
                icon: Icons.auto_awesome,
                title: '3. 生成新设定',
                content: '基于章节内容和已有设定，AI会按照您选择的类型生成新的设定项。如果新设定与已有设定存在关联（如某个物品属于某个角色），AI会自动建立层级关系。',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                context,
                icon: Icons.account_tree,
                title: '4. 自动建立层级',
                content: '生成的设定会自动填充父设定ID（parentId），形成完整的设定体系。例如：角色的武器、地点的子区域等。添加后会在左侧边栏以树状结构展示。',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates,
                      color: WebTheme.getPrimaryColor(context),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '提示：生成的设定仅供参考，您可以自由编辑或删除。建议先从较小的章节范围开始尝试。',
                        style: TextStyle(
                          fontSize: 12,
                          color: WebTheme.getSecondaryTextColor(context),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '我知道了',
              style: TextStyle(
                color: WebTheme.getPrimaryColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建帮助说明的单个部分
  Widget _buildHelpSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: WebTheme.getPrimaryColor(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WebTheme.getTextColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: TextStyle(
                  fontSize: 13,
                  color: WebTheme.getSecondaryTextColor(context),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _maxSettingsController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 使用LayoutBuilder检测可用空间，实现响应式布局
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        
        // 小屏幕模式：高度小于600px或高度不足时使用完全可滚动的单列布局
        final bool isSmallScreen = availableHeight < 600;
        
        if (isSmallScreen) {
          // 小屏幕：整个内容区域可滚动
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildConfigurationArea(context, theme, isCompact: true),
                const Divider(height: 1, thickness: 1),
                Container(
                  constraints: BoxConstraints(
                    minHeight: 200,
                    maxHeight: 400,
                  ),
                  child: _buildResultsArea(context, theme),
                ),
              ],
            ),
          );
        }
        
        // 正常屏幕：使用灵活布局，配置区域和结果区域分别可滚动
        return Column(
          children: [
            // 配置区域 - 使用Flexible允许自适应高度，最大占50%
            Flexible(
              flex: 1,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildConfigurationArea(context, theme, isCompact: false),
              ),
            ),
            const Divider(height: 1, thickness: 1),
            // 结果区域 - 使用Flexible允许自适应高度
            Flexible(
              flex: 1,
              child: _buildResultsArea(context, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigurationArea(BuildContext context, ThemeData theme, {required bool isCompact}) {
    // 根据紧凑模式调整间距和字体大小
    final double verticalSpacing = isCompact ? 8.0 : 16.0;
    final double smallSpacing = isCompact ? 6.0 : 12.0;
    final double padding = isCompact ? 8.0 : 12.0;
    final double titleFontSize = isCompact ? 13.0 : 14.0;
    
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和帮助图标
            Row(
              children: [
                Text(
                  'AI设定生成配置',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: WebTheme.getTextColor(context),
                    fontSize: isCompact ? 14.0 : null,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'AI设定生成原理说明',
                  preferBelow: false,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.help,
                    child: GestureDetector(
                      onTap: () => _showHelpDialog(context),
                      child: Container(
                        width: isCompact ? 18 : 20,
                        height: isCompact ? 18 : 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: WebTheme.getPrimaryColor(context),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              color: WebTheme.getPrimaryColor(context),
                              fontSize: isCompact ? 11 : 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: verticalSpacing),
            BlocBuilder<AISettingGenerationBloc, AISettingGenerationState>(
                builder: (context, state) {
                  List<Chapter> chapters = [];
                  Novel? novel;
                  bool isLoadingChapters = true;
                  String? chapterLoadingError;

                  if (state is AISettingGenerationDataLoaded) {
                    chapters = state.chapters;
                    novel = state.novel;
                    isLoadingChapters = false;
                  } else if (state is AISettingGenerationSuccess) {
                    chapters = state.chapters;
                    novel = state.novel;
                    isLoadingChapters = false;
                  } else if (state is AISettingGenerationFailure) {
                    chapters = state.chapters; // Might still have chapters from a previous successful load
                    novel = state.novel;
                    isLoadingChapters = false;
                    if(chapters.isEmpty) chapterLoadingError = state.error; // Only show error if no chapters displayed
                  } else if (state is AISettingGenerationLoadingChapters || state is AISettingGenerationInitial) {
                    isLoadingChapters = true;
                  } else {
                    isLoadingChapters = false; 
                  }

                  if (isLoadingChapters) { 
                    return const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ));
                  }
                  if (chapterLoadingError != null) {
                     return Center(child: Padding(
                       padding: const EdgeInsets.symmetric(vertical: 16.0),
                       child: Text('加载章节失败: $chapterLoadingError', style: TextStyle(color: theme.colorScheme.error)),
                     ));
                  }
                  if (chapters.isEmpty) {
                     return const Center(child: Padding(
                       padding: EdgeInsets.symmetric(vertical: 24.0),
                       child: Text('没有可用的章节。'),
                     ));
                  }

                  final chapterOptions = _generateChapterOptions(chapters, novel);

                  // 将章节选择和数量集成到一行
                  return Row(
                    children: [
                      // 起始章节（只显示序号）
                      Expanded(
                        flex: 2,
                        child: _buildCompactChapterDropdown(
                          context: context,
                          theme: theme,
                          label: '起始',
                          value: _selectedStartChapterId,
                          options: chapterOptions,
                          onChanged: (value) {
                            setState(() {
                              _selectedStartChapterId = value;
                              if (_selectedEndChapterId != null && _selectedStartChapterId != null) {
                                final startOption = chapterOptions.firstWhere((opt) => opt.id == _selectedStartChapterId);
                                final endOption = chapterOptions.firstWhere((opt) => opt.id == _selectedEndChapterId);
                                if (endOption.globalOrder < startOption.globalOrder) {
                                  _selectedEndChapterId = null; 
                                }
                              }
                            });
                          },
                          validator: (value) => value == null ? '请选择' : null,
                          isCompact: isCompact,
                        ),
                      ),
                      SizedBox(width: isCompact ? 6 : 8),
                      // 结束章节（只显示序号）
                      Expanded(
                        flex: 2,
                        child: _buildCompactChapterDropdown(
                          context: context,
                          theme: theme,
                          label: '终止',
                          value: _selectedEndChapterId,
                          options: chapterOptions.where((option) {
                            if (_selectedStartChapterId == null) return true;
                            final startOption = chapterOptions.firstWhere((opt) => opt.id == _selectedStartChapterId);
                            return option.globalOrder >= startOption.globalOrder;
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedEndChapterId = value;
                            });
                          },
                          hasDefaultOption: true,
                          isCompact: isCompact,
                        ),
                      ),
                      SizedBox(width: isCompact ? 6 : 8),
                      // 每类生成数量
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _maxSettingsController,
                          decoration: InputDecoration(
                            labelText: '数量',
                            labelStyle: TextStyle(fontSize: titleFontSize),
                            hintText: '1-5',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 8 : 12,
                              vertical: isCompact ? 12 : 16,
                            ),
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: titleFontSize),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          validator: (value) {
                            if (value == null || value.isEmpty) return '必填';
                            final num = int.tryParse(value);
                            if (num == null || num < 1 || num > 5) return '1-5';
                            return null;
                          },
                        ),
                      ),
                    ],
                  );
                },
            ),
            SizedBox(height: verticalSpacing),
            Text(
                '希望生成的设定类型:', 
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: titleFontSize,
                ),
            ),
            SizedBox(height: smallSpacing),
            Wrap(
                spacing: isCompact ? 6.0 : 8.0,
                runSpacing: isCompact ? 3.0 : 4.0,
                children: _settingTypeOptions.map((option) {
                  return FilterChip(
                    label: Text(
                      option.type.displayName, 
                      style: TextStyle(fontSize: isCompact ? 11 : 12),
                    ),
                    selected: option.isSelected,
                    onSelected: (selected) {
                      setState(() {
                        option.isSelected = selected;
                      });
                    },
                    checkmarkColor: option.isSelected ? theme.colorScheme.onPrimary : null,
                   selectedColor: WebTheme.getPrimaryColor(context),
                    labelStyle: TextStyle(
                        color: option.isSelected ? theme.colorScheme.onPrimary : theme.textTheme.bodySmall?.color, 
                        fontWeight: option.isSelected ? FontWeight.bold : FontWeight.normal),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,      
                    visualDensity: isCompact ? const VisualDensity(horizontal: -2, vertical: -2) : VisualDensity.compact,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 4 : 6,
                      vertical: isCompact ? 1 : 2,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                           color: option.isSelected ? WebTheme.getPrimaryColor(context) : theme.colorScheme.outline,
                            width: 1.0,
                        ),
                    ),
                  );
                }).toList(),
            ),
            SizedBox(height: verticalSpacing),
            // 模型选择器
            Text(
                '选择AI模型:', 
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: titleFontSize,
                ),
            ),
            SizedBox(height: smallSpacing),
            ModelDisplaySelector(
                selectedModel: _selectedModel,
                onModelSelected: (model) {
                  setState(() {
                    _selectedModel = model;
                  });
                },
                size: isCompact ? ModelDisplaySize.small : ModelDisplaySize.medium,
                height: isCompact ? 50 : 60,
                showIcon: true,
                showTags: !isCompact, // 紧凑模式下隐藏标签
                showSettingsButton: false,
                placeholder: '选择AI模型',
            ),
            SizedBox(height: verticalSpacing),
            // 说明或风格指令输入框 - 添加边框
            TextFormField(
                controller: _instructionsController,
                decoration: InputDecoration(
                  labelText: '说明或风格指令 (可选)',
                  labelStyle: TextStyle(fontSize: titleFontSize),
                  hintText: '例如：希望角色更神秘，或侧重描写地点的历史感',
                  hintStyle: TextStyle(fontSize: isCompact ? 12 : 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 8 : 12,
                    vertical: isCompact ? 8 : 12,
                  ),
                ),
                style: TextStyle(fontSize: titleFontSize),
                maxLines: isCompact ? 2 : 3,
                maxLength: 200,
            ),
            SizedBox(height: isCompact ? 12 : 20),
            Center(
                child: BlocBuilder<AISettingGenerationBloc, AISettingGenerationState>(
                  builder: (context, state) {
                    bool isLoading = state is AISettingGenerationInProgress;
                    return ElevatedButton.icon(
                      icon: isLoading 
                          ? SizedBox(
                              width: isCompact ? 14 : 16,
                              height: isCompact ? 14 : 16,
                              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.auto_awesome_outlined, size: isCompact ? 16 : 18),
                      label: Text(isLoading ? '生成中...' : '开始生成设定'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 20,
                          vertical: isCompact ? 10 : 12,
                        ),
                        textStyle: TextStyle(
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: isLoading ? null : () {
                        if (_formKey.currentState!.validate()) {
                          final selectedTypes = _settingTypeOptions
                                                  .where((opt) => opt.isSelected)
                                                  .map((opt) => opt.type.value)
                                                  .toList();
                          if (selectedTypes.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请至少选择一个设定类型'), backgroundColor: Colors.orange)
                            );
                            return;
                          }
                          if (_selectedStartChapterId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请选择起始章节'), backgroundColor: Colors.orange)
                            );
                            return;
                          }
                          if (_selectedModel == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请选择AI模型'), backgroundColor: Colors.orange)
                            );
                            return;
                          }

                          // 后端会自己查询novelId对应的已有设定，前端不需要传递
                          context.read<AISettingGenerationBloc>().add(GenerateSettingsRequested(
                            novelId: widget.novelId,
                            startChapterId: _selectedStartChapterId!,
                            endChapterId: _selectedEndChapterId,
                            settingTypes: selectedTypes,
                            maxSettingsPerType: int.parse(_maxSettingsController.text),
                            additionalInstructions: _instructionsController.text,
                            modelConfigId: _selectedModel!.id, // 模型配置ID
                          ));
                        }
                      },
                    );
                  }
                ),
            ),
            ],
          ),
        ),
    );
  }

  // 紧凑型章节下拉框（只显示序号）
  Widget _buildCompactChapterDropdown({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required String? value,
    required List<ChapterOption> options,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
    bool hasDefaultOption = false,
    bool isCompact = false,
  }) {
    final double fontSize = isCompact ? 12.0 : 13.0;
    final double iconSize = isCompact ? 16.0 : 18.0;
    final double verticalPadding = isCompact ? 12.0 : 16.0;
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: fontSize),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 12,
          vertical: verticalPadding,
        ),
        isDense: true,
      ),
      value: value,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down,
        size: iconSize,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      style: TextStyle(fontSize: fontSize, color: theme.colorScheme.onSurface),
      items: [
        if (hasDefaultOption)
          DropdownMenuItem<String>(
            value: null,
            child: Text(
              '最新',
              style: TextStyle(
                color: WebTheme.getPrimaryColor(context),
                fontSize: fontSize,
              ),
            ),
          ),
        ...options.map((option) {
          return DropdownMenuItem<String>(
            value: option.id,
            child: Text(
              '第${option.globalOrder}章',
              style: TextStyle(
                fontSize: fontSize,
                color: theme.colorScheme.onSurface,
              ),
            ),
          );
        }).toList(),
      ],
      onChanged: onChanged,
      validator: validator,
      selectedItemBuilder: (BuildContext context) {
        return [
          if (hasDefaultOption)
            Text(
              '最新',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: fontSize,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ...options.map((option) {
            return Text(
              '第${option.globalOrder}章',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: fontSize,
              ),
              overflow: TextOverflow.ellipsis,
            );
          }).toList(),
        ];
      },
      dropdownColor: theme.cardColor,
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      menuMaxHeight: 250,
    );
  }

  Widget _buildResultsArea(BuildContext context, ThemeData theme) {
    return BlocBuilder<AISettingGenerationBloc, AISettingGenerationState>(
      builder: (context, state) {
        if (state is AISettingGenerationInProgress) {
          return const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在分析章节并生成设定，请稍候...')
            ],
          ));
        }
        if (state is AISettingGenerationSuccess) {
          if (state.generatedSettings.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('AI未能根据您的选择生成任何设定，请尝试调整选项或章节内容后再试。', textAlign: TextAlign.center,)
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: state.generatedSettings.length,
            itemBuilder: (context, index) {
              return NovelSettingItemCard(
                settingItem: state.generatedSettings[index], 
                novelId: widget.novelId,
              );
            },
          );
        }
        if (state is AISettingGenerationFailure) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                  const SizedBox(height:16),
                  Text('生成设定时出错:', style: theme.textTheme.titleMedium),
                  const SizedBox(height:8),
                  Text(state.error, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center,),
                  const SizedBox(height:16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                    onPressed: (){
                        if (_formKey.currentState!.validate()) {
                          final selectedTypes = _settingTypeOptions
                                                  .where((opt) => opt.isSelected)
                                                  .map((opt) => opt.type.value)
                                                  .toList();
                          if (selectedTypes.isEmpty || _selectedStartChapterId == null || _selectedModel == null) {
                             ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请确保已选择起始章节、AI模型和至少一个设定类型再重试。'), backgroundColor: Colors.orange)
                            );
                            return;
                          }
                          
                          // 后端会自己查询novelId对应的已有设定，前端不需要传递
                          context.read<AISettingGenerationBloc>().add(GenerateSettingsRequested(
                            novelId: widget.novelId,
                            startChapterId: _selectedStartChapterId!,
                            endChapterId: _selectedEndChapterId,
                            settingTypes: selectedTypes,
                            maxSettingsPerType: int.parse(_maxSettingsController.text),
                            additionalInstructions: _instructionsController.text,
                            modelConfigId: _selectedModel!.id, // 模型配置ID
                          ));
                        }
                    }
                  )
                ],
              )
            ),
          );
        }
        // Initial or other states
        return const Center(child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('请选择起始章节和希望生成的设定类型，然后点击"开始生成设定"按钮。', textAlign: TextAlign.center,)
        ));
      },
    );
  }
}

class NovelSettingItemCard extends StatefulWidget {
  final NovelSettingItem settingItem;
  final String novelId;

  const NovelSettingItemCard({
    Key? key, 
    required this.settingItem,
    required this.novelId,
  }) : super(key: key);

  @override
  State<NovelSettingItemCard> createState() => _NovelSettingItemCardState();
}

class _NovelSettingItemCardState extends State<NovelSettingItemCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeEnum = SettingType.fromValue(widget.settingItem.type ?? 'OTHER');
    final itemAttributes = widget.settingItem.attributes; // Store in a local variable
    final itemTags = widget.settingItem.tags; // Store in a local variable

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)), // Softer corners
      clipBehavior: Clip.antiAlias, // Ensures content respects border radius
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
              children: [
                Expanded(
                  child: Text(
                    widget.settingItem.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(typeEnum.displayName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                  backgroundColor: _getTypeColor(typeEnum).withOpacity(0.15),
                  labelStyle: TextStyle(color: _getTypeColor(typeEnum)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: 0.0, vertical: -2), // Compact chip
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.settingItem.description ?? '无描述',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
              maxLines: _isExpanded ? null : 3, // Show a bit more before expanding
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if ((widget.settingItem.description?.length ?? 0) > 120) // Show expand if description is somewhat long
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50,30), visualDensity: VisualDensity.compact),
                  child: Text(_isExpanded ? '收起' : '展开', style: TextStyle(fontSize: 12, color: WebTheme.getPrimaryColor(context))),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded)),
              ),
            
            if ((itemAttributes?.isNotEmpty ?? false) || (itemTags?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Divider(thickness: 0.5, color: theme.dividerColor.withOpacity(0.5)),
              const SizedBox(height: 6),
              if (itemAttributes?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: itemAttributes!.entries.map((e) => Chip(
                      label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    )).toList(),
                  ),
                ),
              if (itemTags?.isNotEmpty ?? false)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: itemTags!.map((tag) => Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 10)),
                    backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.6),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  )).toList(),
                ),
            ],

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WebTheme.getPrimaryColor(context),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _handleAdoptSetting(context, widget.settingItem, widget.novelId);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(SettingType type) {
    switch (type) {
      case SettingType.character: return Colors.blue.shade600;
      case SettingType.location: return Colors.green.shade600;
      case SettingType.item: return Colors.orange.shade700;
      case SettingType.lore: return Colors.purple.shade600;
      case SettingType.event: return Colors.red.shade600;
      case SettingType.concept: return Colors.teal.shade600;
      case SettingType.faction: return Colors.indigo.shade600;
      case SettingType.creature: return Colors.brown.shade600;
      case SettingType.magicSystem: return Colors.cyan.shade600;
      case SettingType.technology: return Colors.blueGrey.shade600;
      case SettingType.culture: return Colors.deepOrange.shade600;
      case SettingType.history: return Colors.brown.shade600;
      case SettingType.organization: return Colors.indigo.shade600;
      case SettingType.worldview: return Colors.purple.shade600;
      case SettingType.pleasurePoint: return Colors.redAccent.shade200;
      case SettingType.anticipationHook: return Colors.teal.shade400;
      case SettingType.theme: return Colors.blueGrey.shade500;
      case SettingType.tone: return Colors.amber.shade700;
      case SettingType.style: return Colors.cyan.shade700;
      case SettingType.trope: return Colors.pink.shade400;
      case SettingType.plotDevice: return Colors.green.shade600;
      case SettingType.powerSystem: return Colors.orange.shade700;
      case SettingType.timeline: return Colors.blue.shade600;
      case SettingType.religion: return Colors.deepPurple.shade600;
      case SettingType.politics: return Colors.red.shade700;
      case SettingType.economy: return Colors.lightGreen.shade700;
      case SettingType.geography: return Colors.lightBlue.shade700;
      default: return Colors.grey.shade600;
    }
  }

  // 直接添加设定，不再选择设定组
  void _handleAdoptSetting(BuildContext context, NovelSettingItem itemToAdopt, String novelId) {
    final settingBloc = context.read<SettingBloc>();
    
    AppLogger.i("AISettingGenerationPanel", "准备添加设定: ${itemToAdopt.name}, parentId: ${itemToAdopt.parentId}, 描述长度: ${itemToAdopt.description?.length ?? 0}");

    try {
      // 确保类型值使用正确的枚举value值
      final typeValue = itemToAdopt.type;
      
      // 准备创建的设定条目
      NovelSettingItem itemForCreation = itemToAdopt.copyWith(
        id: null,  // 让后端生成新的ID
        isAiSuggestion: false,
        status: 'ACTIVE',
        type: typeValue,
        description: itemToAdopt.description,
        attributes: itemToAdopt.attributes,
        tags: itemToAdopt.tags,
        parentId: itemToAdopt.parentId,  // 保留AI生成的父设定ID
        generatedBy: "AI设定生成器",
      );
      
      // 直接创建设定项（不需要选择设定组）
      settingBloc.add(CreateSettingItem(
        novelId: novelId,
        item: itemForCreation,
      ));
      
      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加设定: "${itemToAdopt.name}"'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
      AppLogger.i("AISettingGenerationPanel", "设定添加成功: ${itemToAdopt.name}");
    } catch (e, stackTrace) {
      AppLogger.e("AISettingGenerationPanel", "添加设定失败", e, stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('添加设定失败: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 