import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../../models/prompt_models.dart';
import '../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../utils/logger.dart';
import '../../utils/web_theme.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/master_detail_split_view.dart';
import 'widgets/enhanced_template_card.dart';
import 'widgets/template_review_dialog.dart';
import 'widgets/template_details_dialog.dart';
import 'widgets/batch_operation_dialog.dart';
import 'widgets/enhanced_template_editor.dart';

/// 增强提示词模板管理页面
/// 基于 EnhancedUserPromptTemplate 的统一管理
class EnhancedTemplatesManagementScreen extends StatefulWidget {
  const EnhancedTemplatesManagementScreen({Key? key}) : super(key: key);

  @override
  State<EnhancedTemplatesManagementScreen> createState() => _EnhancedTemplatesManagementScreenState();
}

/// 增强模板管理内容主体，可以在不同布局中复用
class EnhancedTemplatesManagementBody extends StatefulWidget {
  const EnhancedTemplatesManagementBody({Key? key}) : super(key: key);

  @override
  State<EnhancedTemplatesManagementBody> createState() => _EnhancedTemplatesManagementBodyState();
}

class _EnhancedTemplatesManagementScreenState extends State<EnhancedTemplatesManagementScreen> 
    with TickerProviderStateMixin {
  final GlobalKey<_EnhancedTemplatesManagementBodyState> _bodyKey = GlobalKey<_EnhancedTemplatesManagementBodyState>();
  late TabController _topLevelTabController;
  int _topLevelTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _topLevelTabController = TabController(length: 2, vsync: this);
    _topLevelTabController.addListener(() {
      setState(() {
        _topLevelTabIndex = _topLevelTabController.index;
      });
      _bodyKey.currentState?._switchTemplateType(_topLevelTabIndex == 0 ? 'public' : 'user');
    });
  }

  @override
  void dispose() {
    _topLevelTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '增强模板管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        bottom: TabBar(
          controller: _topLevelTabController,
          tabs: const [
            Tab(text: '公共模板'),
            Tab(text: '用户模板'),
          ],
          labelColor: WebTheme.getTextColor(context),
          unselectedLabelColor: WebTheme.getTextColor(context).withOpacity(0.6),
        ),
        actions: [
          IconButton(
            onPressed: () => _bodyKey.currentState?._refreshData(),
            icon: Icon(Icons.refresh, color: WebTheme.getTextColor(context)),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: () => _bodyKey.currentState?._showStatistics(),
            icon: Icon(Icons.analytics, color: WebTheme.getTextColor(context)),
            tooltip: '统计信息',
          ),
          if (_topLevelTabIndex == 0)
            IconButton(
              onPressed: () => _bodyKey.currentState?._startCreate(),
              icon: Icon(Icons.add, color: WebTheme.getTextColor(context)),
              tooltip: '添加官方模板',
            ),
        ],
      ),
      backgroundColor: WebTheme.getBackgroundColor(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: EnhancedTemplatesManagementBody(key: _bodyKey),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "refresh",
            onPressed: () => _bodyKey.currentState?._refreshData(),
            tooltip: '刷新数据',
            child: const Icon(Icons.refresh),
          ),
          if (_topLevelTabIndex == 0) ...[
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: "add",
              onPressed: () => _bodyKey.currentState?._startCreate(),
              tooltip: '添加官方模板',
              child: const Icon(Icons.add),
            ),
          ],
        ],
      ),
    );
  }

}

class _EnhancedTemplatesManagementBodyState extends State<EnhancedTemplatesManagementBody>
    with TickerProviderStateMixin {
  List<EnhancedUserPromptTemplate> _templates = [];
  Map<String, List<EnhancedUserPromptTemplate>> _templatesByStatus = {};
  Map<String, Object> _statistics = {};
  bool _isLoading = true;
  String? _error;
  String _templateType = 'public'; // 'public' 或 'user'
  String _selectedTab = 'ALL';
  List<String> _selectedTemplates = [];
  bool _batchMode = false;
  String _searchKeyword = '';
  String? _filterFeatureType;
  bool? _filterVerified;
  String _sortOption = 'LATEST'; // LATEST | MOST_USED | RATING
  int _pageSize = 30;
  int _currentPage = 1;

  // 右侧编辑器状态
  EnhancedUserPromptTemplate? _selectedTemplate; // 选中用于编辑的模板
  bool _isCreating = false; // 创建模式

  late TabController _tabController;
  
  final AdminRepositoryImpl _adminRepository = AdminRepositoryImpl();

  static const List<String> _tabs = ['ALL', 'VERIFIED', 'PENDING', 'POPULAR', 'LATEST'];
  static const Map<String, String> _tabLabels = {
    'ALL': '全部模板',
    'VERIFIED': '已认证',
    'PENDING': '待审核',
    'POPULAR': '热门模板',
    'LATEST': '最新模板',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index >= 0 && _tabController.index < _tabs.length) {
      final newTab = _tabs[_tabController.index];
      if (newTab != _selectedTab) {
        setState(() {
          _selectedTab = newTab;
          _batchMode = false;
          _selectedTemplates.clear();
        });
        _loadTemplates();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadTemplates(),
        _loadStatistics(),
      ]);
    } catch (e) {
      AppLogger.e('EnhancedTemplatesManagement', '加载增强模板数据失败', e);
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _switchTemplateType(String type) {
    setState(() {
      _templateType = type;
      _selectedTab = 'ALL';
      _batchMode = false;
      _selectedTemplates.clear();
      _isCreating = false;
      _selectedTemplate = null;
      _currentPage = 1;
    });
    _loadData();
  }

  Future<void> _loadTemplates() async {
    try {
      List<EnhancedUserPromptTemplate> templates;
      
      if (_templateType == 'user') {
        // 用户模板：直接获取所有用户模板，然后前端过滤
        templates = await _adminRepository.getAllUserEnhancedTemplates(
          page: 0,
          size: 1000, // 获取更多数据用于前端过滤
          search: _searchKeyword.isEmpty ? null : _searchKeyword,
        );
        
        // 过滤掉系统模板（userId为system的模板）
        templates = templates.where((t) => t.userId != 'system').toList();
        
        // 根据选中的tab进行过滤
        switch (_selectedTab) {
          case 'VERIFIED':
            templates = templates.where((t) => t.isVerified == true).toList();
            break;
          case 'PENDING':
            templates = templates.where((t) => t.isPublic == true && t.isVerified != true).toList();
            break;
          case 'POPULAR':
            templates.sort((a, b) => (b.usageCount + (b.favoriteCount ?? 0)).compareTo(a.usageCount + (a.favoriteCount ?? 0)));
            templates = templates.take(20).toList();
            break;
          case 'LATEST':
            templates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            templates = templates.take(20).toList();
            break;
          case 'ALL':
          default:
            // 显示所有
            break;
        }
      } else {
        // 公共模板：使用原有逻辑
        switch (_selectedTab) {
          case 'VERIFIED':
            templates = await _adminRepository.getVerifiedEnhancedTemplates();
            break;
          case 'PENDING':
            templates = await _adminRepository.getPendingEnhancedTemplates();
            break;
          case 'POPULAR':
            templates = await _adminRepository.getPopularEnhancedTemplates(
              featureType: _filterFeatureType,
              limit: 20,
            );
            break;
          case 'LATEST':
            templates = await _adminRepository.getLatestEnhancedTemplates(
              featureType: _filterFeatureType,
              limit: 20,
            );
            break;
          default:
            templates = await _adminRepository.getAllPublicEnhancedTemplates(
              featureType: _filterFeatureType,
            );
            break;
        }
      }

      // 应用搜索过滤
      if (_searchKeyword.isNotEmpty) {
        templates = templates.where((template) {
          final name = template.name.toLowerCase();
          final description = (template.description ?? '').toLowerCase();
          final keyword = _searchKeyword.toLowerCase();
          return name.contains(keyword) || description.contains(keyword);
        }).toList();
      }

      // 应用验证状态过滤
      if (_filterVerified != null) {
        templates = templates.where((template) => 
          template.isVerified == _filterVerified).toList();
      }

      setState(() {
        _templates = templates;
        _templatesByStatus = _groupTemplatesByStatus(templates);
      });
    } catch (e) {
      AppLogger.e('EnhancedTemplatesManagement', '加载增强模板失败', e);
      rethrow;
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final stats = await _adminRepository.getEnhancedTemplatesStatistics();
      setState(() {
        _statistics = stats;
      });
    } catch (e) {
      AppLogger.e('EnhancedTemplatesManagement', '加载统计信息失败', e);
      // 统计信息加载失败不影响主要功能
    }
  }

  Map<String, List<EnhancedUserPromptTemplate>> _groupTemplatesByStatus(
      List<EnhancedUserPromptTemplate> templates) {
    return groupBy(templates, (template) {
      if (template.isVerified == true) return 'VERIFIED';
      if (template.isPublic == true && template.isVerified != true) return 'PENDING';
      return 'PRIVATE';
    });
  }

  void _refreshData() {
    _loadData();
  }

  // 局部乐观更新：用后端返回的模板替换列表中的同ID项，并更新分组
  void _applyLocalUpdate(EnhancedUserPromptTemplate updated) {
    setState(() {
      _templates = _templates.map((t) => t.id == updated.id ? updated : t).toList();
      _templatesByStatus = _groupTemplatesByStatus(_templates);
    });
  }

  void _showStatistics() {
    showDialog(
      context: context,
      builder: (context) => _StatisticsDialog(statistics: _statistics),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_error != null) {
      return ErrorView(
        error: _error!,
        onRetry: _refreshData,
      );
    }

    return Column(
      children: [
        _buildToolbar(),
        _buildFilterBar(),
        _buildTabs(),
        Expanded(
          child: MasterDetailSplitView(
            master: _buildTemplatesList(),
            detail: _buildRightDetailPane(),
            masterFlex: 2,
            detailFlex: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_batchMode) ...[ 
            Expanded(
              child: Text(
                '已选择 ${_selectedTemplates.length} 个模板',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: _selectedTemplates.isNotEmpty ? () => _batchReview(true) : null,
              icon: const Icon(Icons.check_circle),
              tooltip: '批量审核通过',
            ),
            IconButton(
              onPressed: _selectedTemplates.isNotEmpty ? () => _batchReview(false) : null,
              icon: const Icon(Icons.cancel),
              tooltip: '批量审核拒绝',
            ),
            IconButton(
              onPressed: _selectedTemplates.isNotEmpty ? () => _batchSetVerified(true) : null,
              icon: const Icon(Icons.verified),
              tooltip: '批量设为认证',
            ),
            IconButton(
              onPressed: _selectedTemplates.isNotEmpty ? () => _batchPublish(true) : null,
              icon: const Icon(Icons.public),
              tooltip: '批量发布',
            ),
            IconButton(
              onPressed: _selectedTemplates.isNotEmpty ? _batchExport : null,
              icon: const Icon(Icons.file_download),
              tooltip: '导出选中模板',
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _batchMode = false;
                  _selectedTemplates.clear();
                });
              },
              icon: const Icon(Icons.close),
              tooltip: '退出批量模式',
            ),
          ] else ...[ 
            Expanded(
              child: Text(
                '${_templateType == 'public' ? '公共' : '用户'}模板总数: ${_templates.length}',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: _importTemplates,
              icon: const Icon(Icons.file_upload),
              tooltip: '导入模板',
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _batchMode = true;
                });
              },
              icon: const Icon(Icons.checklist),
              tooltip: '批量操作',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 搜索框
          Expanded(
            flex: 2,
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索模板名称或描述...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchKeyword = value;
                  _currentPage = 1;
                });
                Future.delayed(const Duration(milliseconds: 400), () {
                  if (_searchKeyword == value) {
                    _loadTemplates();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          
          // 功能类型过滤
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _filterFeatureType,
              decoration: InputDecoration(
                labelText: '功能类型',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('全部功能')),
                DropdownMenuItem(value: 'AI_CHAT', child: Text('AI聊天')),
                DropdownMenuItem(value: 'TEXT_EXPANSION', child: Text('文本扩写')),
                DropdownMenuItem(value: 'TEXT_REFACTOR', child: Text('文本润色')),
                DropdownMenuItem(value: 'TEXT_SUMMARY', child: Text('文本总结')),
                DropdownMenuItem(value: 'PROFESSIONAL_FICTION_CONTINUATION', child: Text('专业续写')),
                DropdownMenuItem(value: 'SCENE_BEAT_GENERATION', child: Text('场景节拍生成')),
                DropdownMenuItem(value: 'NOVEL_COMPOSE', child: Text('设定编排')),
                DropdownMenuItem(value: 'SETTING_TREE_GENERATION', child: Text('设定树生成')),
              ],
              onChanged: (value) {
                setState(() {
                  _filterFeatureType = value;
                  _currentPage = 1;
                });
                _loadTemplates();
              },
            ),
          ),
          const SizedBox(width: 16),
          
          // 验证状态过滤
          Expanded(
            child: DropdownButtonFormField<bool?>(
              value: _filterVerified,
              decoration: InputDecoration(
                labelText: '认证状态',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('全部状态')),
                DropdownMenuItem(value: true, child: Text('已认证')),
                DropdownMenuItem(value: false, child: Text('未认证')),
              ],
              onChanged: (value) {
                setState(() {
                  _filterVerified = value;
                  _currentPage = 1;
                });
                _loadTemplates();
              },
            ),
          ),
          const SizedBox(width: 16),
          // 排序
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _sortOption,
              decoration: InputDecoration(
                labelText: '排序',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'LATEST', child: Text('最新')),
                DropdownMenuItem(value: 'MOST_USED', child: Text('使用最多')),
                DropdownMenuItem(value: 'RATING', child: Text('评分最高')),
              ],
              onChanged: (value) {
                setState(() {
                  _sortOption = value ?? 'LATEST';
                  _currentPage = 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: _tabs.map((tab) {
          final count = _getTabCount(tab);
          return Tab(
            text: '${_tabLabels[tab]} ($count)',
          );
        }).toList(),
        isScrollable: true,
        labelColor: WebTheme.getTextColor(context),
        unselectedLabelColor: WebTheme.getTextColor(context).withOpacity(0.6),
      ),
    );
  }

  int _getTabCount(String tab) {
    switch (tab) {
      case 'VERIFIED':
        return _templatesByStatus['VERIFIED']?.length ?? 0;
      case 'PENDING':
        return _templatesByStatus['PENDING']?.length ?? 0;
      default:
        return _templates.length;
    }
  }

  Widget _buildTemplatesList() {
    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: WebTheme.getTextColor(context).withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无模板',
              style: TextStyle(
                color: WebTheme.getTextColor(context).withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角的加号创建第一个模板',
              style: TextStyle(
                color: WebTheme.getTextColor(context).withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // 本地排序
    final List<EnhancedUserPromptTemplate> sorted = List.of(_templates);
    switch (_sortOption) {
      case 'MOST_USED':
        sorted.sort((a, b) => (b.usageCount).compareTo(a.usageCount));
        break;
      case 'RATING':
        sorted.sort((a, b) => (b.rating).compareTo(a.rating));
        break;
      case 'LATEST':
      default:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }

    // 本地分页
    final visibleCount = (_currentPage * _pageSize).clamp(0, sorted.length);
    final items = sorted.take(visibleCount).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final template = items[index];
                return EnhancedTemplateCard(
                  template: template,
                  isSelected: _selectedTemplates.contains(template.id),
                  batchMode: _batchMode,
                  showUserInfo: _templateType == 'user', // 用户模板模式显示用户信息
                  onTap: () => _handleTemplateTap(template),
                  onEdit: () => _openEditor(template),
                  onDelete: () => _deleteTemplate(template),
                  onReview: () => _reviewTemplate(template),
                  onToggleVerified: () => _toggleVerified(template),
                  onTogglePublish: () => _togglePublish(template),
                  onViewStats: () => _viewTemplateStats(template),
                  onViewDetails: () => _viewTemplateDetails(template),
                  onDuplicate: () => _duplicateTemplate(template),
                  onSelectionChanged: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTemplates.add(template.id);
                      } else {
                        _selectedTemplates.remove(template.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          if (visibleCount < sorted.length)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentPage += 1;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: Text('加载更多（${sorted.length - visibleCount}）'),
              ),
            ),
        ],
      ),
    );
  }

  void _handleTemplateTap(EnhancedUserPromptTemplate template) {
    if (_batchMode) {
      final isSelected = _selectedTemplates.contains(template.id);
      setState(() {
        if (isSelected) {
          _selectedTemplates.remove(template.id);
        } else {
          _selectedTemplates.add(template.id);
        }
      });
    } else {
      _openEditor(template);
    }
  }

  void _openEditor(EnhancedUserPromptTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _isCreating = false;
    });
  }

  Future<void> _duplicateTemplate(EnhancedUserPromptTemplate template) async {
    final controller = TextEditingController(text: '${template.name} (复制)');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('复制模板'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '新模板名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      final now = DateTime.now();
      final duplicate = EnhancedUserPromptTemplate(
        id: '',
        userId: template.userId,
        name: newName,
        description: template.description,
        featureType: template.featureType,
        systemPrompt: template.systemPrompt,
        userPrompt: template.userPrompt,
        tags: List<String>.from(template.tags),
        categories: List<String>.from(template.categories),
        isPublic: true,
        shareCode: null,
        isFavorite: false,
        isDefault: false,
        usageCount: 0,
        rating: 0,
        ratingCount: 0,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: null,
        isVerified: template.isVerified,
        authorId: template.authorId,
        version: 1,
        language: template.language,
        favoriteCount: 0,
        reviewedAt: null,
        reviewedBy: null,
        reviewComment: null,
      );

      final saved = await _adminRepository.createOfficialEnhancedTemplate(duplicate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制为新模板: ${saved.name}')),
        );
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(EnhancedUserPromptTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除模板 "${template.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminRepository.deleteEnhancedTemplate(template.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('模板 "${template.name}" 删除成功')),
          );
          _refreshData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _reviewTemplate(EnhancedUserPromptTemplate template) {
    showDialog(
      context: context,
      builder: (context) => TemplateReviewDialog(
        template: template,
        onReview: (approved, comment) async {
          try {
            await _adminRepository.reviewEnhancedTemplate(
              template.id,
              approved,
              comment,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('模板 "${template.name}" 审核${approved ? "通过" : "拒绝"}')),
              );
              _refreshData();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('审核失败: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleVerified(EnhancedUserPromptTemplate template) async {
    try {
      final newVerifiedStatus = !template.isVerified;
      await _adminRepository.setEnhancedTemplateVerified(
        template.id,
        newVerifiedStatus,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板 "${template.name}" ${newVerifiedStatus ? "已设为认证" : "已取消认证"}'),
          ),
        );
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _togglePublish(EnhancedUserPromptTemplate template) async {
    try {
      final newPublishStatus = !template.isPublic;
      await _adminRepository.toggleEnhancedTemplatePublish(
        template.id,
        newPublishStatus,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板 "${template.name}" 已${newPublishStatus ? "发布" : "取消发布"}'),
          ),
        );
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _viewTemplateStats(EnhancedUserPromptTemplate template) async {
    try {
      final stats = await _adminRepository.getEnhancedTemplateStatistics(template.id);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${template.name} - 统计信息'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatItem('使用次数', stats['usageCount']?.toString() ?? '0'),
                  _buildStatItem('收藏次数', stats['favoriteCount']?.toString() ?? '0'),
                  _buildStatItem('评分', stats['rating']?.toString() ?? '0.0'),
                  _buildStatItem('创建时间', stats['createdAt']?.toString() ?? '未知'),
                  _buildStatItem('最后更新', stats['updatedAt']?.toString() ?? '未知'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取统计信息失败: $e')),
        );
      }
    }
  }
  
  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _batchReview(bool approved) async {
    if (_selectedTemplates.isEmpty) return;
    
    final selectedTemplateObjs = _templates
        .where((t) => _selectedTemplates.contains(t.id))
        .toList();
    
    if (selectedTemplateObjs.isEmpty) return;
    
    final config = approved 
        ? BatchOperationConfig.configs[BatchOperationType.review]!
        : BatchOperationConfig(
            type: BatchOperationType.review,
            title: '批量拒绝审核',
            description: '您即将批量拒绝选中模板的审核申请。',
            actionColor: Colors.red,
            requiresComment: true,
            commentHint: '请说明拒绝原因',
          );

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => BatchOperationDialog(
          operation: approved ? '审核通过' : '审核拒绝',
          title: config.title,
          description: config.description,
          templates: selectedTemplateObjs,
          actionColor: config.actionColor,
          requiresComment: config.requiresComment,
          commentHint: config.commentHint,
          onConfirm: (comment) async {
            final result = await _adminRepository.batchReviewEnhancedTemplates(
              _selectedTemplates,
              approved,
            );
            
            if (mounted) {
              final successCount = (result['successCount'] as int?) ?? 0;
              final failureCount = (result['failureCount'] as int?) ?? 0;
              
              String message = '批量${approved ? "审核通过" : "审核拒绝"}完成: ';
              message += '成功 $successCount 个';
              if (failureCount > 0) {
                message += ', 失败 $failureCount 个';
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
              
              setState(() {
                _batchMode = false;
                _selectedTemplates.clear();
              });
              _refreshData();
            }
          },
        ),
      );
    }
  }

  Future<void> _batchSetVerified(bool verified) async {
    if (_selectedTemplates.isEmpty) return;
    
    final selectedTemplateObjs = _templates
        .where((t) => _selectedTemplates.contains(t.id))
        .toList();
    
    if (selectedTemplateObjs.isEmpty) return;
    
    final config = verified
        ? BatchOperationConfig.configs[BatchOperationType.verify]!
        : BatchOperationConfig(
            type: BatchOperationType.verify,
            title: '批量取消认证',
            description: '您即将取消选中模板的官方认证标识。',
            actionColor: Colors.grey,
          );

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => BatchOperationDialog(
          operation: verified ? '认证' : '取消认证',
          title: config.title,
          description: config.description,
          templates: selectedTemplateObjs,
          actionColor: config.actionColor,
          onConfirm: (comment) async {
            final result = await _adminRepository.batchSetEnhancedTemplatesVerified(
              _selectedTemplates,
              verified,
            );
            
            if (mounted) {
              final successCount = (result['successCount'] as int?) ?? 0;
              final failureCount = (result['failureCount'] as int?) ?? 0;
              
              String message = '批量${verified ? "认证" : "取消认证"}完成: ';
              message += '成功 $successCount 个';
              if (failureCount > 0) {
                message += ', 失败 $failureCount 个';
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
              
              setState(() {
                _batchMode = false;
                _selectedTemplates.clear();
              });
              _refreshData();
            }
          },
        ),
      );
    }
  }

  Future<void> _batchPublish(bool publish) async {
    if (_selectedTemplates.isEmpty) return;
    
    final selectedTemplateObjs = _templates
        .where((t) => _selectedTemplates.contains(t.id))
        .toList();
    
    if (selectedTemplateObjs.isEmpty) return;
    
    final config = publish
        ? BatchOperationConfig.configs[BatchOperationType.publish]!
        : BatchOperationConfig(
            type: BatchOperationType.publish,
            title: '批量取消发布',
            description: '您即将取消发布选中的模板，模板将不再对用户可见。',
            actionColor: Colors.grey,
          );

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => BatchOperationDialog(
          operation: publish ? '发布' : '取消发布',
          title: config.title,
          description: config.description,
          templates: selectedTemplateObjs,
          actionColor: config.actionColor,
          onConfirm: (comment) async {
            final result = await _adminRepository.batchPublishEnhancedTemplates(
              _selectedTemplates,
              publish,
            );
            
            if (mounted) {
              final successCount = (result['successCount'] as int?) ?? 0;
              final failureCount = (result['failureCount'] as int?) ?? 0;
              
              String message = '批量${publish ? "发布" : "取消发布"}完成: ';
              message += '成功 $successCount 个';
              if (failureCount > 0) {
                message += ', 失败 $failureCount 个';
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
              
              setState(() {
                _batchMode = false;
                _selectedTemplates.clear();
              });
              _refreshData();
            }
          },
        ),
      );
    }
  }

  Future<void> _batchExport() async {
    if (_selectedTemplates.isEmpty) return;
    
    final selectedTemplateObjs = _templates
        .where((t) => _selectedTemplates.contains(t.id))
        .toList();
    
    if (selectedTemplateObjs.isEmpty) return;
    
    final config = BatchOperationConfig.configs[BatchOperationType.export]!;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => BatchOperationDialog(
          operation: '导出',
          title: config.title,
          description: config.description,
          templates: selectedTemplateObjs,
          actionColor: config.actionColor,
          onConfirm: (comment) async {
            final templates = await _adminRepository.exportEnhancedTemplates(_selectedTemplates);
            
            if (mounted) {
              // TODO: 实现文件下载或保存功能
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已导出 ${templates.length} 个模板')),
              );
              
              setState(() {
                _batchMode = false;
                _selectedTemplates.clear();
              });
            }
          },
        ),
      );
    }
  }

  void _viewTemplateDetails(EnhancedUserPromptTemplate template) async {
    try {
      // 获取模板统计信息
      Map<String, Object>? statistics = await _adminRepository.getEnhancedTemplateStatistics(template.id);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => TemplateDetailsDialog(
            template: template,
            statistics: statistics,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => TemplateDetailsDialog(
            template: template,
          ),
        );
      }
    }
  }

  // 右侧详情/编辑区域
  Widget _buildRightDetailPane() {
    if (_isCreating || _selectedTemplate != null) {
      return EnhancedTemplateEditor(
        key: ValueKey(_selectedTemplate?.id ?? 'creating'),
        template: _selectedTemplate,
        onCancel: () {
          setState(() {
            _selectedTemplate = null;
            _isCreating = false;
          });
        },
        onSaved: (saved) {
          final exists = _templates.any((t) => t.id == saved.id);
          if (exists) {
            _applyLocalUpdate(saved);
          } else {
            // 新建的场景，插入并重算分组
            setState(() {
              _templates.insert(0, saved);
              _templatesByStatus = _groupTemplatesByStatus(_templates);
            });
          }
          setState(() {
            _selectedTemplate = saved;
            _isCreating = false;
          });
        },
      );
    }

    // 占位空视图
    return Container(
      color: WebTheme.getSurfaceColor(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 64, color: WebTheme.getTextColor(context).withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              '在左侧选择一个模板查看并编辑，或点击“新增”创建',
              style: TextStyle(color: WebTheme.getTextColor(context).withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  // 提供给父级AppBar/FAB调用：进入创建模式
  void _startCreate() {
    setState(() {
      _isCreating = true;
      _selectedTemplate = null;
    });
  }

  Future<void> _importTemplates() async {
    // TODO: 实现文件选择和上传功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入功能待实现')),
    );
  }
}

/// 统计信息对话框
class _StatisticsDialog extends StatelessWidget {
  final Map<String, Object> statistics;

  const _StatisticsDialog({required this.statistics});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('增强模板统计'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatItem('总模板数', statistics['totalTemplates']?.toString() ?? '0'),
            _buildStatItem('公共模板数', statistics['publicTemplates']?.toString() ?? '0'),
            _buildStatItem('已认证模板', statistics['verifiedTemplates']?.toString() ?? '0'),
            _buildStatItem('总使用次数', statistics['totalUsage']?.toString() ?? '0'),
            _buildStatItem('总收藏次数', statistics['totalFavorites']?.toString() ?? '0'),
            _buildStatItem('平均评分', statistics['averageRating']?.toString() ?? '0.0'),
            
            const SizedBox(height: 16),
            const Text('按功能类型分布:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            if (statistics['byFeatureType'] is Map<String, dynamic>)
              ...(statistics['byFeatureType'] as Map<String, dynamic>).entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text(entry.value.toString()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}