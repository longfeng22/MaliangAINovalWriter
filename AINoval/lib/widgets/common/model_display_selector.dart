import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/ai_config/ai_config_bloc.dart';
import '../../blocs/public_models/public_models_bloc.dart';
import '../../config/app_config.dart';
import '../../config/provider_icons.dart';
import '../../models/ai_request_models.dart';
import '../../models/novel_setting_item.dart';
import '../../models/novel_snippet.dart';
import '../../models/novel_structure.dart';
import '../../models/setting_group.dart';
import '../../models/unified_ai_model.dart';
import '../../models/user_ai_model_config_model.dart';
import '../../models/public_model_config.dart';
import 'top_toast.dart';
import 'unified_ai_model_dropdown.dart';

/// 尺寸变体：根据不同大小展示不同的信息密度
enum ModelDisplaySize { small, medium, large }

/// 通用的“模型显示与选择”组件
/// - 支持显示模型名称、标签，可选显示提供商图标
/// - 点击后弹出统一的模型下拉菜单（自动根据空间选择上下方向）
class ModelDisplaySelector extends StatefulWidget {
  const ModelDisplaySelector({
    Key? key,
    this.selectedModel,
    this.onModelSelected,
    this.chatConfig,
    this.onConfigChanged,
    this.novel,
    this.settings = const [],
    this.settingGroups = const [],
    this.snippets = const [],
    this.placeholder = '选择模型',
    this.size = ModelDisplaySize.medium,
    this.showIcon = true,
    this.showTags = true,
    this.showSettingsButton = true,
    this.width,
    this.height,
  }) : super(key: key);

  final UnifiedAIModel? selectedModel;
  final ValueChanged<UnifiedAIModel?>? onModelSelected;
  final UniversalAIRequest? chatConfig;
  final ValueChanged<UniversalAIRequest>? onConfigChanged;
  final Novel? novel;
  final List<NovelSettingItem> settings;
  final List<SettingGroup> settingGroups;
  final List<NovelSnippet> snippets;
  final String placeholder;
  final ModelDisplaySize size;
  final bool showIcon;
  final bool showTags;
  final bool showSettingsButton;
  final double? width;
  final double? height; // 可覆盖默认高度

  @override
  State<ModelDisplaySelector> createState() => _ModelDisplaySelectorState();
}

class _ModelDisplaySelectorState extends State<ModelDisplaySelector> {
  OverlayEntry? _overlay;
  bool _autoPickDone = false;

  @override
  void initState() {
    super.initState();
    // 首帧尝试自动选择默认模型
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPickDefault());
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    if (_overlay != null && _overlay!.mounted) {
      _overlay!.remove();
    }
    _overlay = null;
  }

  void _showDropdown() {
    if (_overlay != null) {
      _removeOverlay();
      return;
    }

    // 兜底：如果没有任何可用模型，提示并返回
    final aiState = context.read<AiConfigBloc>().state;
    final publicState = context.read<PublicModelsBloc>().state;
    final hasPrivate = aiState.validatedConfigs.isNotEmpty;
    final hasPublic = publicState is PublicModelsLoaded && publicState.models.isNotEmpty;
    if (!hasPrivate && !hasPublic) {
      TopToast.error(context, '暂无可用的AI模型配置');
      return;
    }

    // 计算触发器组件的全局矩形作为锚点
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset globalPosition = box.localToGlobal(Offset.zero);
    final Rect anchorRect = Rect.fromLTWH(
      globalPosition.dx,
      globalPosition.dy,
      box.size.width,
      box.size.height,
    );

    _overlay = UnifiedAIModelDropdown.show(
      context: context,
      anchorRect: anchorRect,
      selectedModel: widget.selectedModel,
      onModelSelected: (unifiedModel) {
        // 直接回传统一模型
        widget.onModelSelected?.call(unifiedModel);

        // 如果需要同步到聊天配置（保留与旧接口兼容）
        if (widget.onConfigChanged != null && widget.chatConfig != null && unifiedModel != null) {
          UserAIModelConfigModel? compatModel;
          if (unifiedModel.isPublic) {
            final publicModel = (unifiedModel as PublicAIModel).publicConfig;
            compatModel = UserAIModelConfigModel.fromJson({
              'id': publicModel.id, // 直接使用公共模型ID，不拼接前缀
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

          final Map<String, dynamic> mergedMetadata = {
            ...?widget.chatConfig?.metadata,
            'modelName': unifiedModel.modelId,
            'modelProvider': unifiedModel.provider,
            'modelConfigId': unifiedModel.id,
            'isPublicModel': unifiedModel.isPublic,
          };
          if (unifiedModel.isPublic) {
            final publicId = (unifiedModel as PublicAIModel).publicConfig.id;
            mergedMetadata['publicModelConfigId'] = publicId;
            mergedMetadata['publicModelId'] = publicId;
          } else {
            mergedMetadata.remove('publicModelConfigId');
            mergedMetadata.remove('publicModelId');
          }

          final updated = widget.chatConfig!.copyWith(
            modelConfig: compatModel,
            metadata: mergedMetadata,
          );
          widget.onConfigChanged!(updated);
        }
      },
      showSettingsButton: widget.showSettingsButton,
      // 隐藏“调整并生成”入口：小说列表输入框不需要该动作
      // 该组件当前仅用于首页/列表输入区，因此固定为false
      // 如将来复用到其他地方，可将该参数暴露为构造函数可配置
      showAdjustAndGenerate: false,
      novel: widget.novel,
      settings: widget.settings,
      settingGroups: widget.settingGroups,
      snippets: widget.snippets,
      chatConfig: widget.chatConfig,
      onConfigChanged: widget.onConfigChanged,
      onClose: () {
        _overlay = null;
      },
    );
  }

  void _maybeAutoPickDefault() {
    if (_autoPickDone) return;
    if (widget.selectedModel != null) return;

    final UnifiedAIModel? defaultModel = _computeDefaultModel();
    if (defaultModel != null) {
      _autoPickDone = true;
      widget.onModelSelected?.call(defaultModel);
    }
  }

  UnifiedAIModel? _computeDefaultModel() {
    // 优先：已登录用户的默认私有模型
    final String? userId = AppConfig.userId;
    final aiState = context.read<AiConfigBloc>().state;
    if (userId != null) {
      final defaults = aiState.validatedConfigs.where((c) => c.isDefault).toList();
      if (defaults.isNotEmpty) {
        return PrivateAIModel(defaults.first);
      }
      // 可选：如无默认，继续尝试公共模型
    }

    // 未登录或无默认 → 使用公共服务 gemini-2.0（或最优的gemini可用项）
    final publicState = context.read<PublicModelsBloc>().state;
    if (publicState is PublicModelsLoaded) {
      final List<PublicModel> models = publicState.models;
      PublicModel? target;
      for (final m in models) {
        if (m.modelId.toLowerCase() == 'gemini-2.0') {
          target = m;
          break;
        }
      }
      if (target == null) {
        // 选择 provider/modelId 含 gemini 的优先项（按 priority 降序）
        final geminiCandidates = models.where((m) {
          final p = m.provider.toLowerCase();
          final id = m.modelId.toLowerCase();
          return p.contains('gemini') || p.contains('google') || id.contains('gemini');
        }).toList();
        if (geminiCandidates.isNotEmpty) {
          geminiCandidates.sort((a, b) => (b.priority ?? 0).compareTo(a.priority ?? 0));
          target = geminiCandidates.first;
        }
      }
      if (target != null) {
        return PublicAIModel(target);
      }
    }

    return null;
  }

  String _displayName() {
    if (widget.selectedModel != null) return widget.selectedModel!.displayName;
    final configModel = widget.chatConfig?.modelConfig;
    if (configModel != null) {
      return configModel.alias.isNotEmpty ? configModel.alias : configModel.modelName;
    }
    return widget.placeholder;
  }

  double _heightForSize() {
    if (widget.height != null) return widget.height!;
    switch (widget.size) {
      case ModelDisplaySize.small:
        return 32;
      case ModelDisplaySize.medium:
        return 36;
      case ModelDisplaySize.large:
        return 44;
    }
  }

  double _fontSizeForSize() {
    switch (widget.size) {
      case ModelDisplaySize.small:
        return 12;
      case ModelDisplaySize.medium:
        return 13;
      case ModelDisplaySize.large:
        return 14;
    }
  }

  int _maxTagsToShow() {
    if (!widget.showTags) return 0;
    switch (widget.size) {
      case ModelDisplaySize.small:
        return 1;
      case ModelDisplaySize.medium:
        return 2;
      case ModelDisplaySize.large:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 主题与展示数据
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151);
    final borderColor = isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB);
    List<String> tags;
    final sel = widget.selectedModel;
    if (sel != null) {
      final bool isPublicById = sel.id.startsWith('public_') || sel.isPublic;
      if (isPublicById) {
        tags = ['系统'];
      } else {
        tags = sel.modelTags;
      }
    } else {
      final cfgId = widget.chatConfig?.modelConfig?.id;
      if (cfgId != null && cfgId.startsWith('public_')) {
        tags = ['系统'];
      } else {
        tags = const [];
      }
    }
    final int showTagCount = _maxTagsToShow().clamp(0, tags.length);

    // 监听相关Bloc以在数据加载后执行一次自动选择
    // 注意：仅在尚未自动选择且外部未传入selectedModel时才会触发
    // 使用Listener而非Builder，避免无谓重建
    final child = GestureDetector(
      onTap: _showDropdown,
      child: Container(
        width: widget.width,
        height: _heightForSize(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF374151) : Colors.white,
          border: Border.all(color: borderColor, width: 1.0),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            if (widget.showIcon)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildProviderIcon(),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _displayName(),
                      style: TextStyle(
                        fontSize: _fontSizeForSize(),
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showTagCount > 0) const SizedBox(width: 8),
                  if (showTagCount > 0)
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          ...tags
                              .take(showTagCount)
                              .map((t) => _TagChip(text: t))
                              .toList(),
                          if (sel is PrivateAIModel && sel.userConfig.isToolDefault)
                            _TagChip(text: '工具默认'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.expand_more,
              size: 18,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );

    return MultiBlocListener(
      listeners: [
        BlocListener<AiConfigBloc, AiConfigState>(
          listenWhen: (p, c) => !_autoPickDone && widget.selectedModel == null,
          listener: (context, state) => _maybeAutoPickDefault(),
        ),
        BlocListener<PublicModelsBloc, PublicModelsState>(
          listenWhen: (p, c) => !_autoPickDone && widget.selectedModel == null,
          listener: (context, state) => _maybeAutoPickDefault(),
        ),
      ],
      child: child,
    );
  }

  Widget _buildProviderIcon() {
    final model = widget.selectedModel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (model == null) {
      return Icon(
        Icons.model_training_outlined,
        size: 16,
        color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
      );
    }

    final color = ProviderIcons.getProviderColor(model.provider);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.9) : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? color.withOpacity(0.3) : color.withOpacity(0.25),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ProviderIcons.getProviderIcon(model.provider, size: 12, useHighQuality: true),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color tagColor;
    Color backgroundColor;
    Color borderColor;

    if (text == '私有') {
      tagColor = Colors.blue;
      backgroundColor = isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.withOpacity(0.1);
      borderColor = Colors.blue.withOpacity(isDark ? 0.3 : 0.2);
    } else if (text == '系统') {
      tagColor = Colors.green;
      backgroundColor = isDark ? Colors.green.withOpacity(0.15) : Colors.green.withOpacity(0.1);
      borderColor = Colors.green.withOpacity(isDark ? 0.3 : 0.2);
    } else if (text == '推荐') {
      tagColor = Colors.orange;
      backgroundColor = isDark ? Colors.orange.withOpacity(0.15) : Colors.orange.withOpacity(0.1);
      borderColor = Colors.orange.withOpacity(isDark ? 0.3 : 0.2);
    } else if (text == '免费') {
      tagColor = Colors.purple;
      backgroundColor = isDark ? Colors.purple.withOpacity(0.15) : Colors.purple.withOpacity(0.1);
      borderColor = Colors.purple.withOpacity(isDark ? 0.3 : 0.2);
    } else if (text.contains('积分')) {
      tagColor = Colors.red;
      backgroundColor = isDark ? Colors.red.withOpacity(0.15) : Colors.red.withOpacity(0.1);
      borderColor = Colors.red.withOpacity(isDark ? 0.3 : 0.2);
    } else {
      tagColor = cs.outline;
      backgroundColor = isDark ? cs.surfaceVariant.withOpacity(0.3) : cs.surfaceVariant.withOpacity(0.5);
      borderColor = cs.outline.withOpacity(isDark ? 0.3 : 0.2);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tagColor.withOpacity(isDark ? 0.9 : 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}


