import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:ainoval/blocs/setting/setting_bloc.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/models/setting_type.dart'; // 导入设定类型枚举
// import 'package:ainoval/screens/editor/widgets/floating_setting_dialogs.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/services/api_service/repositories/novel_setting_repository.dart';
import 'package:ainoval/services/api_service/repositories/storage_repository.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/widgets/common/floating_card.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/widgets/setting/setting_relations_tab.dart';
import 'package:ainoval/widgets/setting/setting_tracking_tab.dart';
import 'package:ainoval/models/ai_context_tracking.dart';
import 'package:image/image.dart' as img;

/// 浮动设定详情管理器
class FloatingNovelSettingDetail {
  static bool _isShowing = false;

  /// 显示浮动设定详情卡片
  static void show({
    required BuildContext context,
    String? itemId, // 若为null则表示创建新条目
    required String novelId,
    String? groupId, // 所属设定组ID，可选
    bool isEditing = false, // 是否处于编辑模式
    String? prefilledDescription, // 预填充的描述内容
    String? prefilledType, // 预填充的设定类型
    required Function(NovelSettingItem, String?) onSave, // 保存回调，第二个参数为所选组ID
    required VoidCallback onCancel, // 取消回调
  }) {
    if (_isShowing) {
      hide();
    }

    // 🚀 安全获取当前的 Provider 实例，添加错误处理
    SettingBloc? settingBloc;
    NovelSettingRepository? settingRepository;
    StorageRepository? storageRepository;
    
    try {
      settingBloc = context.read<SettingBloc>();
      settingRepository = context.read<NovelSettingRepository>();
      storageRepository = context.read<StorageRepository>();
      
      AppLogger.d('FloatingNovelSettingDetail', '✅ 成功获取所有必要的Provider实例');
    } catch (e) {
      AppLogger.e('FloatingNovelSettingDetail', '❌ 无法获取必要的Provider实例', e);
      
      // 显示错误提示
      if (context.mounted) {
        TopToast.error(context, '无法打开设定详情：缺少必要的服务组件');
      }
      return;
    }

    // 获取布局信息
    final layoutManager = Provider.of<EditorLayoutManager>(context, listen: false);
    final sidebarWidth = layoutManager.isEditorSidebarVisible ? layoutManager.editorSidebarWidth : 0.0;

    AppLogger.d('FloatingNovelSettingDetail', '显示浮动卡片，侧边栏宽度: $sidebarWidth');

    // 计算卡片宽度 - 进一步优化尺寸
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = (screenSize.width * 0.28).clamp(400.0, 600.0); // 进一步缩小并减少最大宽度

    FloatingCard.show(
      context: context,
      position: FloatingCardPosition(
        left: sidebarWidth + 16.0,
        top: 60.0,
      ),
      config: FloatingCardConfig(
        width: cardWidth,
        // 移除 height 参数，让内容自适应高度
        maxHeight: screenSize.height * 0.85, // 增加可用高度
        showCloseButton: false,
        enableBackgroundTap: false,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.easeOutCubic,
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero,
        backgroundColor: WebTheme.getBackgroundColor(context),
      ),
      child: MultiProvider(
        providers: [
          BlocProvider<SettingBloc>.value(value: settingBloc),
          Provider<NovelSettingRepository>.value(value: settingRepository),
          Provider<StorageRepository>.value(value: storageRepository),
        ],
        child: _NovelSettingDetailContent(
          itemId: itemId,
          novelId: novelId,
          groupId: groupId,
          isEditing: isEditing,
          prefilledDescription: prefilledDescription,
          prefilledType: prefilledType,
          onSave: onSave,
          onCancel: () {
            onCancel();
            hide();
          },
        ),
      ),
      onClose: () {
        onCancel();
        hide();
      },
    );

    _isShowing = true;
  }

  /// 隐藏浮动卡片
  static void hide() {
    if (_isShowing) {
      FloatingCard.hide();
      _isShowing = false;
    }
  }

  /// 检查是否正在显示
  static bool get isShowing => _isShowing;
}

/// 小说设定条目详情和编辑组件
class _NovelSettingDetailContent extends StatefulWidget {
  final String? itemId; // 若为null则表示创建新条目
  final String novelId;
  final String? groupId; // 所属设定组ID，可选
  final bool isEditing; // 是否处于编辑模式
  final String? prefilledDescription; // 预填充的描述内容
  final String? prefilledType; // 预填充的设定类型
  final Function(NovelSettingItem, String?) onSave; // 保存回调，第二个参数为所选组ID
  final VoidCallback onCancel; // 取消回调
  
  const _NovelSettingDetailContent({
    Key? key,
    this.itemId,
    required this.novelId,
    this.groupId,
    this.isEditing = false,
    this.prefilledDescription,
    this.prefilledType,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<_NovelSettingDetailContent> createState() => _NovelSettingDetailContentState();
}

class _NovelSettingDetailContentState extends State<_NovelSettingDetailContent> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  
  // 表单控制器
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _aliasesController = TextEditingController();
  
  // 新增：标签控制器
  final _tagsController = TextEditingController();
  
  // 新增：属性列表
  final List<MapEntry<String, String>> _attributes = [];
  
  // 设定条目数据
  NovelSettingItem? _settingItem;
  
  // 选择的类型 - 使用displayName
  String? _selectedType;
  
  // 选择的设定组ID
  String? _selectedGroupId;
  
  // 类型选项 - 使用枚举获取，确保没有重复
  late final List<String> _typeOptions = SettingType.values
      .map((type) => type.displayName)
      .toSet() // 去重
      .toList();
  
  // 加载状态
  bool _isLoading = true;
  bool _isSaving = false;
  
  // 标签页控制器
  late TabController _tabController;
  
  // 是否固定（Pin）
  // bool _isPinned = false;
  
  // 图片相关状态
  bool _isImageHovered = false;
  bool _isImageUploading = false;
  String? _imageUrl;
  
  // 下拉菜单状态
  bool _isDropdownOpen = false;
  final GlobalKey _dropdownKey = GlobalKey();
  OverlayEntry? _dropdownOverlayEntry;
  
  // 设定组下拉菜单状态
  bool _isGroupDropdownOpen = false;
  final GlobalKey _groupDropdownKey = GlobalKey();
  OverlayEntry? _groupDropdownOverlayEntry;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化标签页控制器
    _tabController = TabController(length: 5, vsync: this);
    
    // 加载设定组列表（仅当尚未成功加载过时）
    final settingState = context.read<SettingBloc>().state;
    if (settingState.groupsStatus != SettingStatus.success) {
      AppLogger.i('FloatingNovelSettingDetail', '加载设定组（当前状态: ${settingState.groupsStatus}）');
      context.read<SettingBloc>().add(LoadSettingGroups(widget.novelId));
    } else {
      AppLogger.d('FloatingNovelSettingDetail', '跳过加载设定组，已成功加载（数量: ${settingState.groups.length}）');
    }
    
    if (widget.itemId != null) {
      _loadSettingItem();
    } else {
      // 创建新条目
      setState(() {
        _isLoading = false;
        // 使用预填充的类型，如果没有则默认为角色
        if (widget.prefilledType != null) {
          final prefilledTypeEnum = SettingType.fromValue(widget.prefilledType!);
          _selectedType = prefilledTypeEnum.displayName;
        } else {
          _selectedType = SettingType.character.displayName; // 使用displayName而不是数组索引
        }
        _selectedGroupId = widget.groupId; // 初始化选择的组ID
        
        // 如果有预填充的描述内容，设置到描述字段
        if (widget.prefilledDescription != null) {
          _descriptionController.text = widget.prefilledDescription!;
        }
        
        // 如果没有传入 groupId，但有可用的设定组，默认选择第一个设定组
        if (_selectedGroupId == null) {
          final settingState = context.read<SettingBloc>().state;
          if (settingState.groups.isNotEmpty) {
            _selectedGroupId = settingState.groups.first.id;
          }
        }
      });
    }
  }
  
  @override
  void dispose() {
    // 清理下拉菜单overlay
    _dropdownOverlayEntry?.remove();
    _dropdownOverlayEntry = null;
    _groupDropdownOverlayEntry?.remove();
    _groupDropdownOverlayEntry = null;
    
    _nameController.dispose();
    _descriptionController.dispose();
    _aliasesController.dispose();
    _tagsController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  // 加载设定条目详情
  Future<void> _loadSettingItem() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 从SettingBloc中查找设定条目
      final settingBloc = context.read<SettingBloc>();
      final state = settingBloc.state;
      
      // 如果当前状态中有该条目，直接使用
      if (state.items.isNotEmpty) {
        final itemIndex = state.items.indexWhere((item) => item.id == widget.itemId);
        if (itemIndex >= 0) {
          _settingItem = state.items[itemIndex];
          _initializeForm();
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      
      // 如果Bloc中找不到数据，则请求详细数据
      try {
        final settingRepository = context.read<NovelSettingRepository>();
        final item = await settingRepository.getSettingItemDetail(
          novelId: widget.novelId,
          itemId: widget.itemId!,
        );
        
        _settingItem = item;
        
        // 不要在仅查看详情时触发全局更新或远程更新，避免引发全局重建
        // 如需缓存到本地状态，可在未来添加专门的本地缓存事件
      } catch (e) {
        AppLogger.e('NovelSettingDetail', '从API加载设定条目详情失败', e);
        // 如果API请求也失败，使用默认值
        _settingItem = NovelSettingItem(
          id: widget.itemId,
          novelId: widget.novelId,
          name: "加载失败",
          type: "OTHER",
          content: "无法加载该设定条目数据",
        );
      }
      
      // 初始化表单
      _initializeForm();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.e('NovelSettingDetail', '加载设定条目详情失败', e);
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // 初始化表单
  void _initializeForm() {
    if (_settingItem == null) return;
    
    _nameController.text = _settingItem!.name;
    _descriptionController.text = (_settingItem!.description ?? _settingItem!.content)!;
    
    // 初始化标签
    if (_settingItem!.tags != null && _settingItem!.tags!.isNotEmpty) {
      _tagsController.text = _settingItem!.tags!.join(', ');
    }
    
    // 初始化属性
    _attributes.clear();
    if (_settingItem!.attributes != null) {
      _attributes.addAll(_settingItem!.attributes!.entries.toList());
    }
    
    // 修复类型初始化 - 确保使用displayName
    final settingTypeEnum = SettingType.fromValue(_settingItem!.type ?? 'OTHER');
    _selectedType = settingTypeEnum.displayName;
    
    _selectedGroupId = widget.groupId; // 如果有传入groupId，将其设为默认选择
    if (_selectedGroupId == null && _settingItem!.id != null) {
      // 未传入 groupId 时，尝试从当前状态反查所属组，改善“按类型视图打开详情”的体验
      try {
        final settingState = context.read<SettingBloc>().state;
        for (final group in settingState.groups) {
          if (group.itemIds != null && group.itemIds!.contains(_settingItem!.id)) {
            _selectedGroupId = group.id;
            break;
          }
        }
      } catch (e) {
        AppLogger.w('NovelSettingDetail', '初始化反查所属组失败', e);
      }
    }
    
    // 初始化图片URL
    _imageUrl = _settingItem!.imageUrl;
  }
  
  // 保存设定条目
  Future<void> _saveSettingItem() async {
    // 安全检查表单状态
    if (_formKey.currentState?.validate() != true) {
      AppLogger.w('NovelSettingDetail', '表单验证失败，无法保存');
      // 显示错误提示
      if (mounted) {
        TopToast.error(context, '请检查输入内容是否正确');
      }
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    AppLogger.d('NovelSettingDetail', '开始保存设定条目，itemId: ${widget.itemId}');
    
    try {
      // 获取选择的类型枚举 - 使用displayName转换
      final typeEnum = _getTypeEnumFromDisplayName(_selectedType ?? SettingType.character.displayName);
      
      // 处理标签
      List<String>? tags;
      if (_tagsController.text.isNotEmpty) {
        tags = _tagsController.text.split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList();
      }
      
      // 转换属性为Map
      Map<String, String>? attributes;
      if (_attributes.isNotEmpty) {
        attributes = Map.fromEntries(_attributes);
      }
      
      // 构建设定条目对象
      final settingItem = NovelSettingItem(
        id: widget.itemId,
        novelId: widget.novelId,
        type: typeEnum.value, // 保存value值而不是displayName
        name: _nameController.text,
        content: "",
        description: _descriptionController.text,
        attributes: attributes,
        tags: tags,
        relationships: _settingItem?.relationships,
        generatedBy: _settingItem?.generatedBy,
        imageUrl: _imageUrl, // 使用更新的图片URL
        sceneIds: _settingItem?.sceneIds,
        priority: _settingItem?.priority,
        status: _settingItem?.status,
        isAiSuggestion: _settingItem?.isAiSuggestion ?? false,
        nameAliasTracking: _settingItem?.nameAliasTracking ?? NameAliasTracking.track,
        aiContextTracking: _settingItem?.aiContextTracking ?? AIContextTracking.detected,
        referenceUpdatePolicy: _settingItem?.referenceUpdatePolicy ?? SettingReferenceUpdate.ask,
      );
      
      // 记录所选的组ID
      final String? selectedGroupId = _selectedGroupId ?? widget.groupId;
      
      AppLogger.i('NovelSettingDetail', 
        '保存设定条目: ${settingItem.name}, 类型: ${typeEnum.value}, ' 
        '选择的组ID: ${selectedGroupId ?? "无"}'
      );
      
      // 先更新本地状态，立即反馈给用户
      setState(() {
        _settingItem = settingItem;
        _isSaving = false;
      });
      
      // 通知父组件并触发后端保存
      widget.onSave(settingItem, selectedGroupId);
      
      // 显示成功提示
      if (mounted) {
        TopToast.success(context, widget.itemId == null ? '设定条目创建成功' : '设定条目保存成功');
      }
      
    } catch (e) {
      AppLogger.e('NovelSettingDetail', '保存设定条目失败', e);
      
      // 显示错误提示
      if (mounted) {
        TopToast.error(context, '保存失败: ${e.toString()}');
      }
      
      setState(() {
        _isSaving = false;
      });
    }
  }
  
  // 保存并关闭
  Future<void> _saveAndClose() async {
    await _saveSettingItem();
    if (!_isSaving) {
      // 只有在保存成功（不在保存状态）时才关闭
      FloatingNovelSettingDetail.hide();
    }
  }
  
  // 移除属性
  void _removeAttribute(String key) {
    setState(() {
      _attributes.removeWhere((entry) => entry.key == key);
    });
  }
  
  // 显示添加属性对话框
  void _showAddAttributeDialog(bool isDark) {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加属性'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: '属性名称',
                hintText: '例如：身高、年龄等',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: '属性值',
                hintText: '例如：180cm、25岁等',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final key = keyController.text.trim();
              final value = valueController.text.trim();
              
              if (key.isNotEmpty && value.isNotEmpty) {
                setState(() {
                  // 检查是否已存在相同键名
                  _attributes.removeWhere((entry) => entry.key == key);
                  _attributes.add(MapEntry(key, value));
                });
                Navigator.of(context).pop();
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // 添加关系
  // void _addRelationship() {}
  
  // 删除关系
  // void _deleteRelationship(String targetItemId, String relationshipType) {}
  
  @override
  Widget build(BuildContext context) {
    final isDark = WebTheme.isDarkMode(context);
    
    if (_isLoading) {
      return Container(
        decoration: BoxDecoration(
          color: WebTheme.getCardColor(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: WebTheme.getShadowColor(context, opacity: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? WebTheme.darkGrey800 : WebTheme.grey200,
          width: 2,
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部区域（类型、标题、图片）
            _buildHeaderSection(isDark),
            
            // 进度条/分割线
            _buildProgressSection(isDark),
            
            // 标签页
            _buildTabSection(isDark),
            
            // 标签页内容 - 固定合理高度
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDetailsTab(isDark),
                  _buildResearchTab(isDark),
                  _buildRelationsTab(isDark),
                  _buildMentionsTab(isDark),
                  _buildTrackingTab(isDark),
                ],
              ),
            ),
            
            // 底部操作按钮区域
            _buildActionButtons(isDark),
          ],
        ),
      ),
    );
  }
  
  // 构建头部区域
  Widget _buildHeaderSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), // 进一步缩小padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧内容区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 类型下拉菜单和设定组选择 - 并排显示
                    _buildTypeAndGroupRow(isDark),
                    
                    const SizedBox(height: 6), // 缩小间距
                    
                    // 标题输入框
                    _buildTitleInput(isDark),
                    
                    const SizedBox(height: 8), // 增加间距避免重叠
                    
                    // 标签/别名输入
                    _buildTagsInput(isDark),
                  ],
                ),
              ),
              
              const SizedBox(width: 12), // 缩小间距
              
              // 右侧图片区域
              _buildImageSection(isDark),
            ],
          ),
        ],
      ),
    );
  }
  
  // 构建类型和设定组并排显示区域
  Widget _buildTypeAndGroupRow(bool isDark) {
    return Row(
      children: [
        // 类型下拉菜单
        _buildTypeDropdown(isDark),
        
        const SizedBox(width: 8),
        
        // 设定组选择
        _buildGroupDropdownCompact(isDark),
      ],
    );
  }

  // 构建类型下拉菜单 - 使用简化的自定义实现
  Widget _buildTypeDropdown(bool isDark) {
    // 确保_selectedType在_typeOptions中
    if (_selectedType == null || !_typeOptions.contains(_selectedType)) {
      _selectedType = _typeOptions.isNotEmpty ? _typeOptions.first : SettingType.character.displayName;
    }
    
    return GestureDetector(
      onTap: () => _toggleDropdown(isDark),
      child: Container(
        key: _dropdownKey,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context), // 使用动态表面色
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? WebTheme.darkGrey700 : WebTheme.grey300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getTypeIconData(_getTypeEnumFromDisplayName(_selectedType!)),
              size: 10,
              color: WebTheme.getTextColor(context),
            ),
            const SizedBox(width: 3),
            Text(
              _selectedType!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              _isDropdownOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 12,
              color: WebTheme.getTextColor(context),
            ),
          ],
        ),
      ),
    );
  }
  
  // 切换下拉菜单
  void _toggleDropdown(bool isDark) {
    if (_isDropdownOpen) {
      // 如果菜单已打开，关闭它
      _hideDropdown();
    } else {
      // 打开菜单
      _showCustomDropdown(isDark);
    }
  }
  
  // 隐藏下拉菜单
  void _hideDropdown() {
    _dropdownOverlayEntry?.remove();
    _dropdownOverlayEntry = null;
    setState(() {
      _isDropdownOpen = false;
    });
  }
  
  // 计算下拉菜单的水平位置，确保不超出屏幕
  double _calculateMenuLeft(double buttonLeft, double screenWidth) {
    const menuWidth = 200.0;
    
    // 如果菜单会超出右边界，调整位置
    if (buttonLeft + menuWidth > screenWidth) {
      return screenWidth - menuWidth - 16; // 留16px边距
    }
    
    // 确保不超出左边界
    return buttonLeft.clamp(16.0, screenWidth - menuWidth - 16);
  }
  
  // 计算下拉菜单的垂直位置，确保不超出屏幕
  double _calculateMenuTop(double buttonTop, double buttonHeight, double screenHeight) {
    const menuMaxHeight = 250.0; // 与约束中的maxHeight保持一致
    const spacing = 2.0;
    
    final preferredTop = buttonTop + buttonHeight + spacing;
    
    // 如果菜单会超出下边界，显示在按钮上方
    if (preferredTop + menuMaxHeight > screenHeight - 50) {
      return (buttonTop - menuMaxHeight - spacing).clamp(50.0, screenHeight - menuMaxHeight - 50);
    }
    
    return preferredTop;
  }
  
  // 显示自定义下拉菜单
  void _showCustomDropdown(bool isDark) {
    // 使用GlobalKey获取按钮的准确位置
    final RenderBox? renderBox = _dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // 获取相对于整个屏幕的全局位置
    final Offset globalOffset = renderBox.localToGlobal(Offset.zero);
    final Size buttonSize = renderBox.size;
    
    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    
    // 如果已有下拉菜单，先关闭
    if (_dropdownOverlayEntry != null) {
      _hideDropdown();
      return;
    }
    
    setState(() {
      _isDropdownOpen = true;
    });
    
    // 使用Overlay直接显示下拉菜单，确保显示在最顶层
    _dropdownOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 背景遮罩，点击关闭下拉菜单
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _hideDropdown();
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          
          // 下拉菜单
          Positioned(
            left: _calculateMenuLeft(globalOffset.dx, screenSize.width),
            top: _calculateMenuTop(globalOffset.dy, buttonSize.height, screenSize.height),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: WebTheme.getSurfaceColor(context),
              shadowColor: WebTheme.getShadowColor(context, opacity: 0.3),
              child: Container(
                width: 200,
                constraints: BoxConstraints(
                  maxWidth: screenSize.width * 0.8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? WebTheme.darkGrey600 : WebTheme.grey300,
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 250, // 限制最大高度，避免溢出
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _typeOptions.map((typeDisplayName) {
                      final isSelected = typeDisplayName == _selectedType;
                                             return InkWell(
                         onTap: () {
                           _hideDropdown();
                           if (typeDisplayName != _selectedType) {
                             setState(() {
                               _selectedType = typeDisplayName;
                             });
                           }
                         },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? (isDark ? WebTheme.darkGrey700 : WebTheme.grey100)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getTypeIconData(_getTypeEnumFromDisplayName(typeDisplayName)),
                                size: 16,
                                color: isSelected 
                                    ? (isDark ? WebTheme.grey200 : WebTheme.grey900)
                                    : (isDark ? WebTheme.grey400 : WebTheme.grey700),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  typeDisplayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected 
                                        ? (isDark ? WebTheme.grey200 : WebTheme.grey900)
                                        : (isDark ? WebTheme.grey300 : WebTheme.grey700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    
    // 插入到Overlay中
    Overlay.of(context).insert(_dropdownOverlayEntry!);
  }
  
  // 构建紧凑型设定组下拉菜单 - 与类型下拉菜单样式保持一致
  Widget _buildGroupDropdownCompact(bool isDark) {
    return BlocBuilder<SettingBloc, SettingState>(
      builder: (context, state) {
        final groups = state.groups;
        
        // 构建选项列表，包含无分组选项
        final groupOptions = <Map<String, dynamic>>[
          {'id': null, 'name': '无分组'},
          ...groups.map((group) => {
            'id': group.id,
            'name': group.name,
          }),
        ];
        
        // 确保当前选择的组ID在选项列表中
        if (_selectedGroupId != null && 
            !groupOptions.any((option) => option['id'] == _selectedGroupId)) {
          _selectedGroupId = null;
        }
        
        // 查找当前选择的组名
        final selectedOption = groupOptions.firstWhere(
          (option) => option['id'] == _selectedGroupId,
          orElse: () => {'id': null, 'name': '无分组'},
        );
        final selectedGroupName = selectedOption['name'] as String;
        
        return GestureDetector(
          onTap: () => _toggleGroupDropdown(isDark, groupOptions),
          child: Container(
            key: _groupDropdownKey,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: WebTheme.getSurfaceColor(context), // 使用动态表面色
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark ? WebTheme.darkGrey700 : WebTheme.grey300,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedGroupId == null ? Icons.folder_off : Icons.folder,
                  size: 12,
                  color: WebTheme.getTextColor(context),
                ),
                const SizedBox(width: 4),
                Text(
                  selectedGroupName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: WebTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isGroupDropdownOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: WebTheme.getTextColor(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 构建设定组选择 - 使用与类型下拉框相同的实现方式（保留原版本作为备用）
  /* Widget _buildGroupSelection(bool isDark) {
    return BlocBuilder<SettingBloc, SettingState>(
      builder: (context, state) {
        final groups = state.groups;
        
        // 构建选项列表，包含无分组选项
        final groupOptions = <Map<String, dynamic>>[
          {'id': null, 'name': '无分组'},
          ...groups.map((group) => {
            'id': group.id,
            'name': group.name ?? '未命名组', // 防止组名为null
          }),
        ];
        
        // 确保当前选择的组ID在选项列表中
        if (_selectedGroupId != null && 
            !groupOptions.any((option) => option['id'] == _selectedGroupId)) {
          _selectedGroupId = null; // 如果选择的组不存在，重置为无分组
        }
        
        // 查找当前选择的组名
        final selectedOption = groupOptions.firstWhere(
          (option) => option['id'] == _selectedGroupId,
          orElse: () => {'id': null, 'name': '无分组'},
        );
        final selectedGroupName = selectedOption['name'] as String;
        
        return Container(
          height: 30,
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 12,
                color: WebTheme.getSecondaryTextColor(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleGroupDropdown(isDark, groupOptions),
                  child: Container(
                    key: _groupDropdownKey,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedGroupName,
                            style: TextStyle(
                              fontSize: 11,
                              color: _selectedGroupId == null 
                                  ? WebTheme.getSecondaryTextColor(context).withOpacity(0.6)
                                  : WebTheme.getSecondaryTextColor(context),
                            ),
                          ),
                        ),
                        Icon(
                          _isGroupDropdownOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 14,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  } */
  
  // 切换设定组下拉菜单
  void _toggleGroupDropdown(bool isDark, List<Map<String, dynamic>> groupOptions) {
    if (_isGroupDropdownOpen) {
      // 如果菜单已打开，关闭它
      _hideGroupDropdown();
    } else {
      // 打开菜单
      _showGroupCustomDropdown(isDark, groupOptions);
    }
  }
  
  // 隐藏设定组下拉菜单
  void _hideGroupDropdown() {
    _groupDropdownOverlayEntry?.remove();
    _groupDropdownOverlayEntry = null;
    setState(() {
      _isGroupDropdownOpen = false;
    });
  }
  
  // 显示设定组自定义下拉菜单
  void _showGroupCustomDropdown(bool isDark, List<Map<String, dynamic>> groupOptions) {
    // 使用GlobalKey获取按钮的准确位置
    final RenderBox? renderBox = _groupDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // 获取相对于整个屏幕的全局位置
    final Offset globalOffset = renderBox.localToGlobal(Offset.zero);
    final Size buttonSize = renderBox.size;
    
    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    
    // 如果已有下拉菜单，先关闭
    if (_groupDropdownOverlayEntry != null) {
      _hideGroupDropdown();
      return;
    }
    
    setState(() {
      _isGroupDropdownOpen = true;
    });
    
    // 使用Overlay直接显示下拉菜单，确保显示在最顶层
    _groupDropdownOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 背景遮罩，点击关闭下拉菜单
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _hideGroupDropdown();
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          
          // 下拉菜单
          Positioned(
            left: _calculateMenuLeft(globalOffset.dx, screenSize.width),
            top: _calculateMenuTop(globalOffset.dy, buttonSize.height, screenSize.height),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: WebTheme.getSurfaceColor(context),
              shadowColor: WebTheme.getShadowColor(context, opacity: 0.3),
              child: Container(
                width: 200,
                constraints: BoxConstraints(
                  maxWidth: screenSize.width * 0.8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? WebTheme.darkGrey600 : WebTheme.grey300,
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 250, // 限制最大高度，避免溢出
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: groupOptions.map((option) {
                          final String? groupId = option['id'] as String?;
                          final String groupName = option['name'] as String;
                          final bool isSelected = _selectedGroupId == groupId;
                          
                          return InkWell(
                            onTap: () {
                              _hideGroupDropdown();
                              if (groupId != _selectedGroupId) {
                                setState(() {
                                  _selectedGroupId = groupId;
                                });
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? WebTheme.getTextColor(context).withOpacity(0.12)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    groupId == null ? Icons.folder_off : Icons.folder,
                                    size: 16,
                                    color: isSelected 
                                        ? (isDark ? WebTheme.grey200 : WebTheme.grey900)
                                        : (isDark ? WebTheme.grey400 : WebTheme.grey700),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      groupName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected 
                                        ? WebTheme.getTextColor(context)
                                        : WebTheme.getSecondaryTextColor(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    
    // 插入到Overlay中
    Overlay.of(context).insert(_groupDropdownOverlayEntry!);
  }
  
  // 显示设定组选择菜单（旧版本，保留作为备用）
  /* void _showGroupSelectionMenu(bool isDark, List<Map<String, dynamic>> groupOptions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? WebTheme.darkGrey800 : WebTheme.grey200,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: WebTheme.getTextColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '选择设定组',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: groupOptions.map((option) {
                    final String? groupId = option['id'] as String?;
                    final String groupName = option['name'] as String;
                    final bool isSelected = _selectedGroupId == groupId;
                    
                    return ListTile(
                      leading: Icon(
                        groupId == null ? Icons.folder_off : Icons.folder,
                        size: 18,
                        color: isSelected 
                            ? WebTheme.getTextColor(context)
                            : WebTheme.getSecondaryTextColor(context),
                      ),
                      title: Text(
                        groupName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected 
                              ? WebTheme.getTextColor(context)
                              : WebTheme.getTextColor(context),
                        ),
                      ),
                      trailing: isSelected 
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: WebTheme.getTextColor(context),
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedGroupId = groupId;
                        });
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  } */

  // 构建标题输入框
  Widget _buildTitleInput(bool isDark) {
    return TextFormField(
      controller: _nameController,
      style: const TextStyle(
        fontSize: 18, // 进一步缩小
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
      decoration: InputDecoration(
        hintText: 'Unnamed Entry',
        hintStyle: TextStyle(
          fontSize: 18, // 保持一致
          fontWeight: FontWeight.w800,
          color: WebTheme.getSecondaryTextColor(context),
        ),
        border: InputBorder.none,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: WebTheme.getTextColor(context).withOpacity(0.3),
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      maxLines: 1,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '设定条目名称不能为空';
        }
        return null;
      },
    );
  }
  
  // 构建标签输入
  Widget _buildTagsInput(bool isDark) {
    return Container(
      height: 30, // 从26增加到30，与设定组选择保持一致
      child: TextFormField(
        controller: _tagsController, // 使用正确的标签控制器
        style: TextStyle(
          fontSize: 11, // 从12缩小到11
          color: WebTheme.getSecondaryTextColor(context),
        ),
        decoration: InputDecoration(
          hintText: '+ Add Tags/Labels',
          hintStyle: TextStyle(
            fontSize: 11, // 从12缩小到11
            color: WebTheme.getSecondaryTextColor(context).withOpacity(0.6),
          ),
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: WebTheme.getTextColor(context).withOpacity(0.3),
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), // 调整padding
        ),
        maxLines: 1,
      ),
    );
  }
  
  // 构建图片区域
  Widget _buildImageSection(bool isDark) {
    final typeEnum = _selectedType != null 
        ? _getTypeEnumFromDisplayName(_selectedType!) 
        : SettingType.character;
        
    return MouseRegion(
      onEnter: (_) => setState(() => _isImageHovered = true),
      onExit: (_) => setState(() => _isImageHovered = false),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: isDark ? WebTheme.darkGrey800 : WebTheme.grey100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? WebTheme.darkGrey700 : WebTheme.grey300,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // 背景图片或图标
            if (_imageUrl != null && _imageUrl!.isNotEmpty)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / 
                                  loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          _getTypeIconData(typeEnum),
                          size: 24,
                          color: WebTheme.getTextColor(context),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              // 默认图标
              Center(
                child: Icon(
                  _getTypeIconData(typeEnum),
                  size: 24,
                  color: WebTheme.getTextColor(context),
                ),
              ),
            
            // 上传状态遮罩
            if (_isImageUploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: WebTheme.getShadowColor(context, opacity: 0.7),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? WebTheme.getTextColor(context) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            
            // 悬停时显示的操作按钮
            if (_isImageHovered && !_isImageUploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: WebTheme.getShadowColor(context, opacity: 0.6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(3),
                          onTap: _uploadImage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: WebTheme.getBackgroundColor(context).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'Upload',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w500,
                                color: WebTheme.getTextColor(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(3),
                          onTap: _pasteImage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: WebTheme.getBackgroundColor(context).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'Paste',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w500,
                                color: WebTheme.getTextColor(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  // 构建进度条区域
  Widget _buildProgressSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), // 缩小padding
      child: Row(
        children: [
          // 进度条
          Expanded(
            child: Container(
              height: 16, // 从20缩小到16
              child: CustomPaint(
                painter: _ProgressPainter(
                  backgroundColor: isDark ? WebTheme.darkGrey700 : WebTheme.grey200,
                  progressColor: isDark ? WebTheme.darkGrey800 : WebTheme.getBackgroundColor(context),
                  strokeColor: isDark ? WebTheme.darkGrey400 : WebTheme.grey700,
                  progress: 0.35,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          
          const SizedBox(width: 10), // 从12缩小到10
          
          // 提及数量
          Text(
            '1 mention',
            style: TextStyle(
              fontSize: 12, // 从14缩小到12
              fontWeight: FontWeight.w500,
              color: WebTheme.getTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
  
  // 构建标签页区域
  Widget _buildTabSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? WebTheme.darkGrey800 : WebTheme.grey200,
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: isDark ? WebTheme.grey300 : WebTheme.grey900,
        unselectedLabelColor: isDark ? WebTheme.grey400 : WebTheme.grey500,
        labelStyle: const TextStyle(
          fontSize: 12, // 从14缩小到12
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12, // 从14缩小到12
          fontWeight: FontWeight.w500,
        ),
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? WebTheme.grey400 : WebTheme.grey900,
              width: 2,
            ),
          ),
        ),
        tabs: const [
          Tab(text: 'Details'),
          Tab(text: 'Research'),
          Tab(text: 'Relations'),
          Tab(text: 'Mentions'),
          Tab(text: 'Tracking'),
        ],
      ),
    );
  }
  
  // 构建Details标签页 - 重新设计为系统相关字段
  Widget _buildDetailsTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14), // 进一步缩小
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 基本信息区域
          _buildBasicInfoSection(isDark),
          
          const SizedBox(height: 18), // 从24缩小到18
          
          // 描述区域
          _buildDescriptionSection(isDark),
          
          const SizedBox(height: 18),
          
          // 系统属性区域
          _buildSystemAttributesSection(isDark),
          
          const SizedBox(height: 18),
          
          // 添加详情按钮
          //_buildAddDetailsButton(isDark),
        ],
      ),
    );
  }
  
  // 构建基本信息区域
  Widget _buildBasicInfoSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签/别名字段
        _buildFieldSection(
          '标签/别名',
          '所有名称都会在文本中被识别且不会被拼写检查。',
          TextFormField(
            controller: _tagsController, // 使用正确的标签控制器
            decoration: InputDecoration(
              hintText: '添加别名, 标签...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6), // 从8缩小到6
                borderSide: BorderSide(
                  color: isDark ? WebTheme.darkGrey600 : WebTheme.grey400,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: WebTheme.getTextColor(context),
                  width: 1,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // 缩小padding
            ),
            style: const TextStyle(fontSize: 12), // 缩小字体
          ),
        ),
        
        // 如果有AI生成的属性，显示属性区域
        if (_attributes.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildAttributesSection(isDark),
        ],
      ],
    );
  }
  
  // 构建AI生成的属性区域
  Widget _buildAttributesSection(bool isDark) {
    return _buildFieldSection(
      '属性',
      '设定的详细属性信息。',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 显示现有属性
          if (_attributes.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _attributes.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? WebTheme.darkGrey800.withOpacity(0.5) : WebTheme.grey100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? WebTheme.darkGrey600 : WebTheme.grey300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.key}: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: WebTheme.getTextColor(context),
                        ),
                      ),
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 12,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeAttribute(entry.key),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: WebTheme.getSecondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          
          // 添加新属性按钮
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加属性'),
            onPressed: () => _showAddAttributeDialog(isDark),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  // 构建描述区域
  Widget _buildDescriptionSection(bool isDark) {
    return _buildFieldSection(
      '详细描述',
      '记录所有必要的细节信息。保持具体且简洁。有时拆分条目有助于更好的组织。',
      Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? WebTheme.darkGrey600 : WebTheme.grey400,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextFormField(
              controller: _descriptionController,
              maxLines: 10, // 增加到10行以显示更多内容
              minLines: 10, // 设置最小行数为10行
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(10),
                hintText: '输入描述内容...',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          
          // 底部工具栏
          Container(
            margin: const EdgeInsets.only(top: 3), // 从4缩小到3
            child: Row(
              children: [
                Text(
                  '${_descriptionController.text.split(' ').length} 字',
                  style: TextStyle(
                    fontSize: 10, // 从12缩小到10
                    fontWeight: FontWeight.w500,
                    color: WebTheme.getSecondaryTextColor(context),
                  ),
                ),
                
                const Spacer(),
                
                // 工具按钮
                _buildToolButton('进展', Icons.layers, isDisabled: true),
                const SizedBox(width: 6), // 从8缩小到6
                _buildToolButton('历史', Icons.history),
                const SizedBox(width: 6),
                _buildToolButton('复制', Icons.content_copy),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 构建系统属性区域
  Widget _buildSystemAttributesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '系统属性',
          style: TextStyle(
            fontSize: 13, // 从14缩小到13
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // 属性标签
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // 生成来源标签
            _buildAttributeTag(
              '生成方式',
              _settingItem?.generatedBy ?? 'manual',
              _getGeneratedByColor(_settingItem?.generatedBy),
            ),
            
            // 优先级标签
            _buildAttributeTag(
              '优先级',
              _settingItem?.priority?.toString() ?? 'normal',
              _getPriorityColor(_settingItem?.priority),
            ),
            
            // 状态标签
            _buildAttributeTag(
              '状态',
              _settingItem?.status ?? 'active',
              _getStatusColor(_settingItem?.status),
            ),
            
            // AI建议标签
            if (_settingItem?.isAiSuggestion == true)
              _buildAttributeTag(
                'AI建议',
                'true',
                Theme.of(context).colorScheme.tertiary,
              ),
            
            // 关联场景数量
            if (_settingItem?.sceneIds != null && _settingItem!.sceneIds!.isNotEmpty)
              _buildAttributeTag(
                '关联场景',
                '${_settingItem!.sceneIds!.length}个',
                Theme.of(context).colorScheme.secondary,
              ),
          ],
        ),
      ],
    );
  }
  
  // 构建属性标签
  Widget _buildAttributeTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  // 获取生成方式颜色
  Color _getGeneratedByColor(String? generatedBy) {
    final scheme = Theme.of(context).colorScheme;
    switch (generatedBy?.toLowerCase()) {
      case 'ai':
      case 'openai':
      case 'claude':
        return scheme.secondary;
      case 'manual':
      case 'user':
        return scheme.primary;
      default:
        return WebTheme.getSecondaryTextColor(context);
    }
  }
  
  // 获取优先级颜色
  Color _getPriorityColor(int? priority) {
    final scheme = Theme.of(context).colorScheme;
    if (priority == null) return WebTheme.getSecondaryTextColor(context);
    if (priority >= 8) return scheme.error;
    if (priority >= 5) return scheme.tertiary;
    if (priority >= 3) return scheme.secondary;
    return scheme.primary;
  }
  
  // 获取状态颜色
  Color _getStatusColor(String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status?.toLowerCase()) {
      case 'active':
        return scheme.primary;
      case 'archived':
        return WebTheme.getSecondaryTextColor(context);
      case 'draft':
        return scheme.tertiary;
      default:
        return scheme.secondary;
    }
  }
  
  // 构建字段区域
  Widget _buildFieldSection(String title, String description, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字段标题和AI图标
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13, // 从14缩小到13
                fontWeight: FontWeight.w500,
                color: WebTheme.getTextColor(context),
              ),
            ),
            const SizedBox(width: 3), // 从4缩小到3
            Icon(
              Icons.auto_awesome,
              size: 12, // 从14缩小到12
              color: WebTheme.getSecondaryTextColor(context).withOpacity(0.5),
            ),
          ],
        ),
        
        const SizedBox(height: 3), // 从4缩小到3
        
        // 描述文本
        Text(
          description,
          style: TextStyle(
            fontSize: 10, // 从12缩小到10
            color: WebTheme.getSecondaryTextColor(context),
            height: 1.4,
          ),
        ),
        
        const SizedBox(height: 6), // 从8缩小到6
        
        // 内容
        content,
      ],
    );
  }
  
  // 构建工具按钮
  Widget _buildToolButton(String label, IconData icon, {bool isDisabled = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(3), // 从4缩小到3
        onTap: isDisabled ? null : () {
          // TODO: 实现工具按钮功能
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // 缩小padding
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12, // 从14缩小到12
                color: isDisabled 
                    ? WebTheme.getSecondaryTextColor(context).withOpacity(0.3)
                    : WebTheme.getSecondaryTextColor(context),
              ),
              const SizedBox(width: 3), // 从4缩小到3
              Text(
                label,
                style: TextStyle(
                  fontSize: 10, // 从12缩小到10
                  fontWeight: FontWeight.w500,
                  color: isDisabled 
                      ? WebTheme.getSecondaryTextColor(context).withOpacity(0.3)
                      : WebTheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 构建添加详情按钮
  /* Widget _buildAddDetailsButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6), // 从8缩小到6
        onTap: () {
          // TODO: 实现添加详情功能
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10), // 从12缩小到10
          child: Row(
            children: [
              Icon(
                Icons.add,
                size: 14, // 从16缩小到14
                color: WebTheme.getSecondaryTextColor(context),
              ),
              const SizedBox(width: 6), // 从8缩小到6
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '添加详情',
                    style: TextStyle(
                      fontSize: 12, // 从14缩小到12
                      fontWeight: FontWeight.w500,
                      color: WebTheme.getTextColor(context),
                    ),
                  ),
                  Text(
                    '填写自定义详细信息',
                    style: TextStyle(
                      fontSize: 10, // 从12缩小到10
                      color: WebTheme.getSecondaryTextColor(context).withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } */
  
  // 构建其他标签页（暂时为占位符）
  Widget _buildResearchTab(bool isDark) {
    return const Center(child: Text('Research功能开发中...'));
  }
  
  Widget _buildRelationsTab(bool isDark) {
    if (_settingItem == null) {
      return const Center(child: Text('加载中...'));
    }
    
    return SettingRelationsTab(
      settingItem: _settingItem!,
      novelId: widget.novelId,
      availableItems: context.read<SettingBloc>().state.items,
      onItemUpdated: (updatedItem) {
        setState(() {
          _settingItem = updatedItem;
        });
      },
    );
  }
  
  Widget _buildMentionsTab(bool isDark) {
    return const Center(child: Text('Mentions功能开发中...'));
  }
  
  Widget _buildTrackingTab(bool isDark) {
    if (_settingItem == null) {
      return const Center(child: Text('加载中...'));
    }
    
    return SettingTrackingTab(
      settingItem: _settingItem!,
      novelId: widget.novelId,
      onItemUpdated: (updatedItem) {
        setState(() {
          _settingItem = updatedItem;
        });
      },
    );
  }
  
  // 构建底部操作按钮区域
  Widget _buildActionButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? WebTheme.darkGrey800 : WebTheme.grey200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 取消按钮
          TextButton(
            onPressed: widget.onCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(80, 36),
            ),
            child: Text(
              '取消',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? WebTheme.grey400 : WebTheme.grey600,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 保存按钮 - 参考 common 组件样式
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: WebTheme.getTextColor(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSaving ? null : _saveSettingItem,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSaving) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              WebTheme.getBackgroundColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _isSaving ? '保存中...' : '保存',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: WebTheme.getBackgroundColor(context),
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 保存并关闭按钮
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSaving ? null : _saveAndClose,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '保存并关闭',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onPrimary,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 获取类型枚举
  SettingType _getTypeEnumFromDisplayName(String displayName) {
    return SettingType.values.firstWhere(
      (type) => type.displayName == displayName,
      orElse: () => SettingType.other,
    );
  }
  
  // 上传图片
  Future<void> _uploadImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // 验证文件类型
        final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
        final fileExtension = file.extension?.toLowerCase();
        if (fileExtension == null || !allowedExtensions.contains(fileExtension)) {
          if (mounted) {
            TopToast.error(context, '不支持的文件格式，请选择 JPG、PNG、GIF 或 WEBP 格式的图片');
          }
          return;
        }

        setState(() {
          _isImageUploading = true;
        });
        
        Uint8List fileBytes;
        if (file.bytes != null) {
          fileBytes = file.bytes!;
        } else if (file.path != null) {
          final File imageFile = File(file.path!);
          fileBytes = await imageFile.readAsBytes();
        } else {
          throw Exception('无法读取图片文件');
        }
        
        // === 统一处理图片（压缩 + 转 JPG）===
        final img.Image? image = img.decodeImage(fileBytes);
        if (image == null) {
          throw Exception('无法解码所选图片');
        }

        // 若图片过大则按最长边 1200px 等比缩放，保持与小说封面上传一致
        img.Image processedImage = image;
        const int maxSize = 1200;
        if (image.width > maxSize || image.height > maxSize) {
          processedImage = img.copyResize(
            image,
            width: image.width > image.height ? maxSize : null,
            height: image.height >= image.width ? maxSize : null,
            interpolation: img.Interpolation.average,
          );
        }

        // 压缩为 JPG，统一格式，质量 85
        final Uint8List compressedBytes = Uint8List.fromList(
          img.encodeJpg(processedImage, quality: 85),
        );

        // 生成唯一文件名，统一使用 .jpg 扩展名
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final uniqueFileName = '${widget.novelId}_setting_${timestamp}_image.jpg';

        // === 上传 ===
        final storageRepository = context.read<StorageRepository>();
        final imageUrl = await storageRepository.uploadCoverImage(
          novelId: widget.novelId,
          fileBytes: compressedBytes,
          fileName: uniqueFileName,
          updateNovelCover: false,
        );
        
        setState(() {
          _imageUrl = imageUrl;
          _isImageUploading = false;
        });
        
        if (mounted) {
          TopToast.success(context, '图片上传成功');
        }
      }
    } catch (e) {
      AppLogger.e('NovelSettingDetail', '上传图片失败', e);
      
      setState(() {
        _isImageUploading = false;
      });
      
      if (mounted) {
        TopToast.error(context, '上传失败: ${e.toString()}');
      }
    }
  }

  // 粘贴图片
  Future<void> _pasteImage() async {
    try {
      setState(() {
        _isImageUploading = true;
      });
      
      // 尝试获取剪贴板中的图片数据
      bool hasImageData = false;
      
      // 首先尝试检查剪贴板中是否有图片
      try {
        // 对于Web平台，我们主要检查文本内容是否为图片URL
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        
        if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
          final text = clipboardData.text!.trim();
          
          // 简单的URL验证
          if (Uri.tryParse(text) != null && 
              (text.startsWith('http://') || text.startsWith('https://')) &&
              _isImageUrl(text)) {
            
            setState(() {
              _imageUrl = text;
              _isImageUploading = false;
            });
            
            if (mounted) {
              TopToast.success(context, '图片链接已粘贴');
            }
            hasImageData = true;
            return;
          }
        }
      } catch (e) {
        AppLogger.w('NovelSettingDetail', '无法访问剪贴板文本内容', e);
      }
      
      // 如果没有找到有效的图片数据，显示错误对话框
      if (!hasImageData) {
        setState(() {
          _isImageUploading = false;
        });
        
        if (mounted) {
          _showNoImageFoundDialog();
        }
      }
    } catch (e) {
      AppLogger.e('NovelSettingDetail', '粘贴图片失败', e);
      
      setState(() {
        _isImageUploading = false;
      });
      
      if (mounted) {
        _showNoImageFoundDialog();
      }
    }
  }
  
  // 显示"未找到兼容图片"对话框
  void _showNoImageFoundDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'No compatible image found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WebTheme.getTextColor(context),
            ),
          ),
          content: Text(
            'No image was found in the clipboard. Please make sure it\'s in PNG or JPEG format.',
            style: TextStyle(
              fontSize: 14,
              color: WebTheme.getTextColor(context),
              height: 1.4,
            ),
          ),
          actions: [
            Container(
              decoration: BoxDecoration(
                color: WebTheme.getSecondaryTextColor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'OK',
                  style: TextStyle(
                    color: WebTheme.getBackgroundColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
          backgroundColor: WebTheme.getSurfaceColor(context),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        );
      },
    );
  }

  // 检查是否为图片URL
  bool _isImageUrl(String url) {
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'];
    final lowerUrl = url.toLowerCase();
    return imageExtensions.any((ext) => lowerUrl.contains(ext));
  }

  // 获取类型图标 - 统一使用纯黑色
  IconData _getTypeIconData(SettingType type) {
    switch (type) {
      case SettingType.character:
        return Icons.person;
      case SettingType.location:
        return Icons.place;
      case SettingType.item:
        return Icons.inventory_2;
      case SettingType.lore:
        return Icons.public;
      case SettingType.event:
        return Icons.event;
      case SettingType.concept:
        return Icons.auto_awesome;
      case SettingType.faction:
        return Icons.groups;
      case SettingType.creature:
        return Icons.pets;
      case SettingType.magicSystem:
        return Icons.auto_fix_high;
      case SettingType.technology:
        return Icons.science;
      case SettingType.culture:
        return Icons.emoji_people;
      case SettingType.history:
        return Icons.history;
      case SettingType.organization:
        return Icons.apartment;
      case SettingType.worldview:
        return Icons.public;
      case SettingType.pleasurePoint:
        return Icons.whatshot;
      case SettingType.anticipationHook:
        return Icons.bolt;
      case SettingType.theme:
        return Icons.category;
      case SettingType.tone:
        return Icons.tonality;
      case SettingType.style:
        return Icons.brush;
      case SettingType.trope:
        return Icons.theater_comedy;
      case SettingType.plotDevice:
        return Icons.schema;
      case SettingType.powerSystem:
        return Icons.flash_on;
      case SettingType.timeline:
        return Icons.timeline;
      case SettingType.religion:
        return Icons.account_balance;
      case SettingType.politics:
        return Icons.gavel;
      case SettingType.economy:
        return Icons.attach_money;
      case SettingType.geography:
        return Icons.map;
      default:
        return Icons.article;
    }
  }
}

// 自定义进度条绘制器
class _ProgressPainter extends CustomPainter {
  final Color backgroundColor;
  final Color progressColor;
  final Color strokeColor;
  final double progress;

  _ProgressPainter({
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    // 绘制背景
    paint.color = backgroundColor;
    final backgroundPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.35, size.height)
      ..lineTo(size.width * 0.36, 0)
      ..lineTo(size.width * 0.37, 0)
      ..lineTo(size.width * 0.38, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    
    canvas.drawPath(backgroundPath, paint);

    // 绘制描边
    paint
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    canvas.drawPath(backgroundPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
