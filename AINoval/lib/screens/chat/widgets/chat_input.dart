import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/context_selection_models.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_group.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/models/ai_request_models.dart';
import 'package:ainoval/models/preset_models.dart';
import 'package:ainoval/models/unified_ai_model.dart';
import 'package:ainoval/services/ai_preset_service.dart';
import 'package:ainoval/config/app_config.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/common/model_display_selector.dart';
import 'package:ainoval/widgets/common/context_selection_dropdown_menu_anchor.dart';
import 'package:ainoval/widgets/common/credit_display.dart';
import 'package:flutter/material.dart';
import 'package:ainoval/utils/web_theme.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    Key? key,
    required this.controller,
    required this.onSend,
    this.isGenerating = false,
    this.onCancel,
    this.onModelSelected,
    this.initialModel,
    this.novel,
    this.contextData,
    this.onContextChanged,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.chatConfig,
    this.onConfigChanged,
    this.onCreditError, // 🚀 新增：积分不足错误回调
    this.initialChapterId,
    this.initialSceneId,
  }) : super(key: key);

  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(String)? onCreditError; // 🚀 新增：积分不足错误回调
  final bool isGenerating;
  final VoidCallback? onCancel;
  final Function(UserAIModelConfigModel?)? onModelSelected;
  final UserAIModelConfigModel? initialModel;
  final dynamic novel;
  final ContextSelectionData? contextData;
  final ValueChanged<ContextSelectionData>? onContextChanged;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;
  final UniversalAIRequest? chatConfig;
  final ValueChanged<UniversalAIRequest>? onConfigChanged;
  final String? initialChapterId;
  final String? initialSceneId;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  OverlayEntry? _presetOverlay;
  final LayerLink _layerLink = LayerLink();
  bool _isComposing = false;
  
  // 预设相关状态
  // final GlobalKey _presetButtonKey = GlobalKey();
  List<AIPromptPreset> _availablePresets = [];
  bool _isLoadingPresets = false;
  AIPromptPreset? _currentPreset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChange);
    _handleTextChange();
    _loadPresets();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    _removePresetOverlay();
    super.dispose();
  }

  /// 加载预设数据
  Future<void> _loadPresets() async {
    if (_isLoadingPresets) return;
    
    if (!mounted) return;
    setState(() {
      _isLoadingPresets = true;
    });

    try {
      final presetService = AIPresetService();
      
      // 直接获取AI_CHAT类型的预设
      final chatPresets = await presetService.getUserPresets(featureType: 'AI_CHAT');
      
      if (!mounted) return;
      setState(() {
        _availablePresets = chatPresets;
        _isLoadingPresets = false;
      });
      
      AppLogger.i('ChatInput', '加载了 ${_availablePresets.length} 个聊天预设');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPresets = false;
      });
      AppLogger.e('ChatInput', '加载预设失败', e);
    }
  }

  void _handleTextChange() {
    final bool composingNow = widget.controller.text.trim().isNotEmpty;
    if (composingNow != _isComposing) {
      // 只有从空 → 非空 或 非空 → 空 时才重建，避免输入过程中频繁 setState
      setState(() {
        _isComposing = composingNow;
      });
    }
  }

  /// 显示预设下拉菜单
  void _showPresetOverlay() {
    if (_presetOverlay != null) {
      _removePresetOverlay();
      return;
    }

    _presetOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _removePresetOverlay,
              child: Container(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -8),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
               color: Theme.of(context).colorScheme.surfaceContainer,
               shadowColor: WebTheme.getShadowColor(context, opacity: 0.15),
              child: Container(
                width: 240,
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                   border: Border.all(
                     color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                   ),
                ),
                child: _buildPresetMenuContent(),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_presetOverlay!);
  }

  /// 移除预设下拉菜单
  void _removePresetOverlay() {
    _presetOverlay?.remove();
    _presetOverlay = null;
  }

  /// 构建预设菜单内容
  Widget _buildPresetMenuContent() {
    if (_isLoadingPresets) {
      return Container(
        height: 120,
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 8),
              Text(
                '加载预设中...',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_availablePresets.isEmpty) {
      return Container(
        height: 120,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Text(
                '暂无可用预设',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '可在设置中创建预设',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 对预设进行分组
    final Map<String, List<AIPromptPreset>> groupedPresets = {
      '最近使用': _availablePresets.where((p) => p.lastUsedAt != null).take(3).toList(),
      '收藏预设': _availablePresets.where((p) => p.isFavorite).toList(),
      '所有预设': _availablePresets,
    };

    return ListView(
      padding: const EdgeInsets.all(8),
      shrinkWrap: true,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '快速预设',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        
               const Divider(height: 1),
        
        // 预设分组列表
        ...groupedPresets.entries.where((entry) => entry.value.isNotEmpty).map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.key != '所有预设' || (entry.key == '所有预设' && groupedPresets['最近使用']!.isEmpty && groupedPresets['收藏预设']!.isEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ...entry.value.map((preset) => _buildPresetMenuItem(preset)).toList(),
            ],
          );
        }).toList(),
      ],
    );
  }

  /// 构建预设菜单项
  Widget _buildPresetMenuItem(AIPromptPreset preset) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _currentPreset?.presetId == preset.presetId;

    return InkWell(
      onTap: () => _handlePresetSelected(preset),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // 预设图标
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 12,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            
            // 预设信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          preset.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (preset.isFavorite) ...[
                        const SizedBox(width: 4),
                         Icon(
                          Icons.star,
                          size: 10,
                           color: Colors.amber.shade600,
                        ),
                      ],
                    ],
                  ),
                  if (preset.presetDescription != null && preset.presetDescription!.isNotEmpty)
                    Text(
                      preset.presetDescription!,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            
            // 选中标识
            if (isSelected)
              Icon(
                Icons.check_circle,
                size: 14,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  /// 处理预设选择
  void _handlePresetSelected(AIPromptPreset preset) {
    _removePresetOverlay();
    
    try {
      setState(() {
        _currentPreset = preset;
      });
      
      // 解析预设并应用到聊天配置
      final parsedRequest = preset.parsedRequest;
      if (parsedRequest != null && widget.onConfigChanged != null) {
        // 创建新的配置，保留现有的基础信息
        final baseConfig = widget.chatConfig ?? UniversalAIRequest(
          requestType: AIRequestType.chat,
          userId: AppConfig.userId ?? 'unknown',
          novelId: widget.novel?.id,
        );
        
        // 应用预设配置
        final updatedConfig = baseConfig.copyWith(
          modelConfig: parsedRequest.modelConfig ?? baseConfig.modelConfig,
          instructions: parsedRequest.instructions?.isNotEmpty == true 
              ? parsedRequest.instructions 
              : preset.effectiveUserPrompt.isNotEmpty ? preset.effectiveUserPrompt : null,
          contextSelections: parsedRequest.contextSelections ?? baseConfig.contextSelections,
          enableSmartContext: parsedRequest.enableSmartContext,
          parameters: {
            ...baseConfig.parameters,
            ...parsedRequest.parameters,
          },
          metadata: {
            ...baseConfig.metadata,
            'appliedPreset': preset.presetId,
            'presetName': preset.presetName,
            'lastPresetApplied': DateTime.now().toIso8601String(),
          },
        );
        
        widget.onConfigChanged!(updatedConfig);
        
        // 如果预设包含模型配置，也要通知模型选择器
        if (parsedRequest.modelConfig != null) {
          widget.onModelSelected?.call(parsedRequest.modelConfig);
        }
        
        AppLogger.i('ChatInput', '预设已应用: ${preset.displayName}');
        
        // 记录预设使用
        AIPresetService().applyPreset(preset.presetId);
        
        // 显示成功提示
        TopToast.success(context, '已应用预设: ${preset.displayName}');
      } else {
        AppLogger.w('ChatInput', '预设解析失败或缺少配置变更回调');
        TopToast.error(context, '应用预设失败');
      }
    } catch (e) {
      AppLogger.e('ChatInput', '应用预设失败', e);
      TopToast.error(context, '应用预设失败: $e');
    }
  }

  void _updateContextData(ContextSelectionData newData, {bool isAddOperation = true}) {
    if (widget.onConfigChanged != null) {
      if (widget.chatConfig != null) {
        // 🚀 修复：使用完整的菜单结构而不是可能不完整的currentSelections
        final currentSelections = widget.chatConfig!.contextSelections;
        
        // 🚀 获取完整的菜单结构数据
        ContextSelectionData? fullContextData;
        if (widget.contextData != null) {
          fullContextData = widget.contextData;
        } else if (widget.novel != null) {
          fullContextData = ContextSelectionDataBuilder.fromNovelWithContext(
            widget.novel!,
            settings: widget.settings,
            settingGroups: widget.settingGroups,
            snippets: widget.snippets,
          );
        }
        
        if (fullContextData != null) {
          ContextSelectionData updatedSelections;
          
          if (isAddOperation && currentSelections != null) {
            // 🚀 添加操作：将现有选择应用到完整结构，然后添加新选择
            // 先应用现有选择到完整结构
            updatedSelections = fullContextData.applyPresetSelections(currentSelections);
            
            // 再添加新选择的项目
            for (final newItem in newData.selectedItems.values) {
              if (!updatedSelections.selectedItems.containsKey(newItem.id)) {
                updatedSelections = updatedSelections.selectItem(newItem.id);
              }
            }
          } else if (!isAddOperation && currentSelections != null) {
            // 🚀 删除操作：将现有选择应用到完整结构，然后移除指定项目
            updatedSelections = fullContextData.applyPresetSelections(currentSelections);
            
            // 找出被删除的项目并移除
            for (final existingId in currentSelections.selectedItems.keys) {
              if (!newData.selectedItems.containsKey(existingId)) {
                updatedSelections = updatedSelections.deselectItem(existingId);
              }
            }
          } else {
            // 🚀 如果当前没有选择，直接使用新数据（但保持完整结构）
            updatedSelections = fullContextData;
            for (final newItem in newData.selectedItems.values) {
              updatedSelections = updatedSelections.selectItem(newItem.id);
            }
          }
          
          final updatedConfig = widget.chatConfig!.copyWith(
            contextSelections: updatedSelections,
          );
          widget.onConfigChanged!(updatedConfig);
        } else {
          // 如果无法获取完整菜单结构，回退到原来的逻辑
          final updatedConfig = widget.chatConfig!.copyWith(
            contextSelections: newData,
          );
          widget.onConfigChanged!(updatedConfig);
        }
      } else {
        // 如果没有chatConfig，创建一个基础配置
        final newConfig = UniversalAIRequest(
          requestType: AIRequestType.chat,
          userId: 'unknown', // 这应该从某个地方获取
          novelId: widget.novel?.id,
          contextSelections: newData,
        );
        widget.onConfigChanged!(newConfig);
      }
    } else {
      // 🚀 如果没有onConfigChanged回调，则使用传统的onContextChanged
      widget.onContextChanged?.call(newData);
    }
  }



  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool canSend = _isComposing && !widget.isGenerating;
    
    ContextSelectionData? currentContextData;
    
    if (widget.contextData != null) {
      // 🚀 使用EditorScreenController维护的级联菜单数据（静态结构）
      currentContextData = widget.contextData;
    } else if (widget.novel != null) {
      // 备用方案：如果EditorScreenController还没有准备好数据，则临时构建
      currentContextData = ContextSelectionDataBuilder.fromNovelWithContext(
        widget.novel!,
        settings: widget.settings,
        settingGroups: widget.settingGroups,
        snippets: widget.snippets,
      );
    }

    // final contextSelectionCount = widget.chatConfig?.contextSelections?.selectedCount ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上下文选择区域 - 始终显示，以便用户可以点击添加
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withOpacity(0.1),
                  width: 1.0,
                ),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center, // 垂直居中对齐
              children: [
                // 使用完整的上下文选择组件 - 包含完整的级联菜单
                if (currentContextData != null)
                  ContextSelectionDropdownBuilder.buildMenuAnchor(
                    data: currentContextData,
                    onSelectionChanged: _updateContextData,
                    placeholder: '+ Context',
                    maxHeight: 400,
                    initialChapterId: widget.initialChapterId,
                    initialSceneId: widget.initialSceneId,
                  )
                else
                  // 当没有数据时显示占位符
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pending_outlined,
                          size: 16,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '等待级联菜单数据...',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // 🚀 修复：使用完整菜单结构中的已选择项目显示标签
                if (currentContextData != null && widget.chatConfig?.contextSelections != null)
                  ..._buildSelectedContextTags(currentContextData, widget.chatConfig!.contextSelections!).map((item) {
                    return Container(
                      height: 36,
                      constraints: const BoxConstraints(maxWidth: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.type.icon,
                            size: 16,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.displaySubtitle.isNotEmpty)
                                  Text(
                                    item.displaySubtitle,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              // 🚀 修复：使用完整菜单结构进行删除操作
                              if (currentContextData != null && widget.chatConfig!.contextSelections != null) {
                                // 将当前选择应用到完整结构，然后删除指定项目
                                final fullDataWithSelections = currentContextData.applyPresetSelections(widget.chatConfig!.contextSelections!);
                                final newData = fullDataWithSelections.deselectItem(item.id);
                                _updateContextData(newData, isAddOperation: false);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
          
          const SizedBox(height: 8.0),
          // 输入框行 - 独占一行，去掉圆角，紧贴边缘
          Container(
            width: double.infinity,
            child: TextField(
              controller: widget.controller,
              decoration: InputDecoration(
                hintText: widget.isGenerating ? 'AI 正在回复...' : '输入消息...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(0), // 去掉圆角
                  borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(0), // 去掉圆角
                  borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(0), // 去掉圆角
                  borderSide:
                      BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12), // 增加垂直内边距
                isDense: false, // 改为false以获得更多空间
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(0), // 去掉圆角
                   borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                ),
              ),
              readOnly: widget.isGenerating,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              onSubmitted: (_) {
                if (canSend) {
                  widget.onSend();
                }
              },
            ),
          ),
          
          const SizedBox(height: 8.0),
          // 预设按钮、积分显示、模型选择器和发送按钮行
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 预设快捷按钮 - 使用PopupMenuButton实现精准定位
              CompositedTransformTarget(
                link: _layerLink,
                child: GestureDetector(
                  onTap: _showPresetOverlay,
                  child: Container(
                    width: 40,
                    height: 36, // 与模型选择器保持一致的高度
                    decoration: BoxDecoration(
                       color: Theme.of(context).brightness == Brightness.dark 
                           ? Theme.of(context).colorScheme.surfaceContainerHighest // 深色容器
                           : Theme.of(context).colorScheme.surface, // 浅色容器
                      border: Border.all(
                         color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(20), // rounded-full
                      boxShadow: [
                         BoxShadow(
                           color: WebTheme.getShadowColor(context, opacity: 0.1),
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: _showPresetOverlay,
                        borderRadius: BorderRadius.circular(20),
                         hoverColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
                        child: Container(
                          width: 40,
                          height: 36,
                          child: Center(
                            child: Icon(
                              Icons.auto_awesome,
                              size: 16,
                               color: _currentPreset != null 
                                   ? colorScheme.primary 
                                   : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // 🚀 积分显示组件
              const CreditDisplay(
                size: CreditDisplaySize.small,
                showRefreshButton: false,
              ),
              
              const SizedBox(width: 8),
              
              // 模型选择按钮 - 使用统一的显示/选择组件
              Expanded(
                child: ModelDisplaySelector(
                  selectedModel: widget.initialModel != null ? PrivateAIModel(widget.initialModel!) : null,
                  onModelSelected: (unifiedModel) {
                    // 将UnifiedAIModel转换为UserAIModelConfigModel以保持兼容性
                    UserAIModelConfigModel? compatModel;
                    if (unifiedModel != null) {
                      if (unifiedModel.isPublic) {
                        final publicModel = (unifiedModel as PublicAIModel).publicConfig;
                        compatModel = UserAIModelConfigModel.fromJson({
                          'id': 'public_${publicModel.id}',
                          'userId': AppConfig.userId ?? 'unknown',
                          'alias': publicModel.displayName,
                          'modelName': publicModel.modelId,
                          'provider': publicModel.provider,
                          'apiEndpoint': '',
                          'isDefault': false,
                          'isValidated': true,
                          'createdAt': DateTime.now().toIso8601String(),
                          'updatedAt': DateTime.now().toIso8601String(),
                        });
                      } else {
                        compatModel = (unifiedModel as PrivateAIModel).userConfig;
                      }
                    }
                    widget.onModelSelected?.call(compatModel);
                  },
                  chatConfig: widget.chatConfig,
                  onConfigChanged: widget.onConfigChanged,
                  novel: widget.novel,
                  settings: widget.settings,
                  settingGroups: widget.settingGroups,
                  snippets: widget.snippets,
                  size: ModelDisplaySize.medium,
                  showIcon: true,
                  showTags: true,
                  showSettingsButton: true,
                  placeholder: '选择模型',
                ),
              ),
              
              const SizedBox(width: 8),
              
              // 发送/停止按钮 - 改为纯黑/灰黑主题
              SizedBox(
                height: 36, // 与模型选择器保持一致的高度
                width: 36,
                child: widget.isGenerating
                    ? Material(
                         color: colorScheme.primary, // 使用主色
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: widget.onCancel,
                          child: Container(
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.stop_rounded,
                              size: 20, 
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Material(
                         color: canSend
                             ? colorScheme.primary
                             : colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: canSend ? _handleSendWithCreditCheck : null,
                          child: Container(
                            width: 36,
                            height: 36,
                            child: Icon(
                              Icons.arrow_upward_rounded,
                              size: 20,
                               color: canSend 
                                   ? colorScheme.onPrimary 
                                   : colorScheme.onPrimary.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 🚀 新增：带积分检查的发送处理
  void _handleSendWithCreditCheck() {
    try {
      // 调用原发送方法，积分校验将在后端处理
      widget.onSend();
    } catch (e) {
      // 如果发送失败，检查是否为积分不足错误
      final errorMessage = e.toString();
      if (errorMessage.contains('积分不足') || errorMessage.contains('InsufficientCredits')) {
        // 积分不足，调用错误回调
        widget.onCreditError?.call('积分不足，无法发送消息。请充值后重试。');
        
        // 同时显示Toast提示
        TopToast.error(context, '积分不足，无法发送消息');
      } else {
        // 其他错误，显示通用错误提示
        TopToast.error(context, '发送失败: $errorMessage');
      }
    }
  }

  /// 🚀 构建已选择的上下文标签，使用完整菜单结构中的数据
  List<ContextSelectionItem> _buildSelectedContextTags(
    ContextSelectionData fullContextData,
    ContextSelectionData currentSelections,
  ) {
    // 将当前选择应用到完整菜单结构中
    final updatedContextData = fullContextData.applyPresetSelections(currentSelections);
    
    // 返回应用后的选中项目列表
    return updatedContextData.selectedItems.values.toList();
  }


}
