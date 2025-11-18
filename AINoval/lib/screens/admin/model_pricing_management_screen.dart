import 'package:flutter/material.dart';

import '../../models/model_pricing.dart';
import '../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../utils/logger.dart';
import '../../utils/web_theme.dart';
import '../../widgets/common/top_toast.dart';
import 'widgets/edit_pricing_dialog.dart';

/// 模型定价管理页面
class ModelPricingManagementScreen extends StatefulWidget {
  const ModelPricingManagementScreen({super.key});

  @override
  State<ModelPricingManagementScreen> createState() => _ModelPricingManagementScreenState();
}

class _ModelPricingManagementScreenState extends State<ModelPricingManagementScreen> {
  final String _tag = 'ModelPricingManagementScreen';
  late final AdminRepositoryImpl _adminRepository;
  
  List<ModelPricing> _pricingList = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _providerFilter = 'all';
  
  // 分页参数
  int _currentPage = 0;
  static const int _pageSize = 20;
  
  // 可用的提供商列表
  final Set<String> _availableProviders = {};

  @override
  void initState() {
    super.initState();
    _adminRepository = AdminRepositoryImpl();
    _loadPricingData();
  }

  /// 加载定价数据
  Future<void> _loadPricingData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pricingList = await _adminRepository.getAllModelPricing();
      
      // 提取可用的提供商
      _availableProviders.clear();
      for (final pricing in pricingList) {
        _availableProviders.add(pricing.provider);
      }
      
      setState(() {
        _pricingList = pricingList;
        _isLoading = false;
      });
      
      AppLogger.d(_tag, '✅ 加载定价数据成功: ${pricingList.length} 条记录');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      AppLogger.e(_tag, '❌ 加载定价数据失败', e);
    }
  }

  /// 刷新数据
  Future<void> _refreshData() async {
    await _loadPricingData();
    TopToast.info(context, '数据已刷新');
  }

  /// 编辑定价
  void _editPricing(ModelPricing pricing) {
    showDialog(
      context: context,
      builder: (context) => EditPricingDialog(
        pricing: pricing,
        onSuccess: _refreshData,
      ),
    );
  }

  /// 添加新定价
  void _addPricing() {
    showDialog(
      context: context,
      builder: (context) => EditPricingDialog(
        onSuccess: _refreshData,
      ),
    );
  }

  /// 删除定价
  Future<void> _deletePricing(ModelPricing pricing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('是否删除模型 ${pricing.provider}:${pricing.modelId} 的定价信息？'),
        backgroundColor: WebTheme.getCardColor(context),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminRepository.deleteModelPricing(pricing.provider, pricing.modelId);
        TopToast.success(context, '删除定价成功');
        _refreshData();
      } catch (e) {
        TopToast.error(context, '删除失败: ${e.toString()}');
      }
    }
  }

  /// 获取过滤后的定价列表
  List<ModelPricing> get _filteredPricingList {
    var filtered = _pricingList.where((pricing) {
      // 提供商筛选
      if (_providerFilter != 'all' && pricing.provider != _providerFilter) {
        return false;
      }
      
      // 搜索筛选
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return pricing.provider.toLowerCase().contains(query) ||
               pricing.modelId.toLowerCase().contains(query) ||
               (pricing.modelName?.toLowerCase().contains(query) ?? false) ||
               (pricing.description?.toLowerCase().contains(query) ?? false);
      }
      
      return true;
    }).toList();
    
    // 按提供商和模型ID排序
    filtered.sort((a, b) {
      final providerCompare = a.provider.compareTo(b.provider);
      if (providerCompare != 0) return providerCompare;
      return a.modelId.compareTo(b.modelId);
    });
    
    return filtered;
  }

  /// 获取当前页的数据
  List<ModelPricing> get _currentPageData {
    final filtered = _filteredPricingList;
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  /// 获取总页数
  int get _totalPages {
    final filtered = _filteredPricingList;
    return (filtered.length / _pageSize).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: WebTheme.getBackgroundColor(context),
        foregroundColor: WebTheme.getTextColor(context),
        title: Text(
          '模型定价管理',
          style: TextStyle(color: WebTheme.getTextColor(context)),
        ),
        actions: [
          IconButton(
            onPressed: _refreshData,
            icon: Icon(Icons.refresh, color: WebTheme.getTextColor(context)),
            tooltip: '刷新',
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _addPricing,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加定价'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      backgroundColor: WebTheme.getBackgroundColor(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              '加载失败: $_error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPricingData,
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 搜索和筛选栏
        _buildSearchAndFilterBar(),
        
        // 数据表格
        Expanded(
          child: _buildDataTable(),
        ),
        
        // 分页控件
        if (_totalPages > 1) _buildPaginationBar(),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getTextColor(context).withOpacity(0.1),
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
                hintText: '搜索提供商、模型ID或描述...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 0; // 重置到第一页
                });
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 提供商筛选
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _providerFilter,
              decoration: InputDecoration(
                labelText: '提供商筛选',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('全部提供商'),
                ),
                ..._availableProviders.map((provider) => DropdownMenuItem(
                  value: provider,
                  child: Text(provider),
                )),
              ],
              onChanged: (value) {
                setState(() {
                  _providerFilter = value!;
                  _currentPage = 0; // 重置到第一页
                });
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 统计信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: WebTheme.getBackgroundColor(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: WebTheme.getTextColor(context).withOpacity(0.2),
              ),
            ),
            child: Text(
              '共 ${_filteredPricingList.length} 条记录',
              style: TextStyle(
                color: WebTheme.getTextColor(context),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_currentPageData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.attach_money,
              size: 64,
              color: WebTheme.getTextColor(context).withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _providerFilter != 'all'
                  ? '未找到匹配的定价记录'
                  : '暂无定价数据',
              style: TextStyle(
                color: WebTheme.getTextColor(context).withOpacity(0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: WebTheme.getCardColor(context),
        child: DataTable(
          columnSpacing: 20,
          horizontalMargin: 16,
          headingRowColor: MaterialStateProperty.all(
            WebTheme.getBackgroundColor(context),
          ),
          columns: [
            DataColumn(
              label: Text(
                '提供商',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '模型ID',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '模型名称',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '定价信息',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '最大Token',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '来源',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                '操作',
                style: TextStyle(
                  color: WebTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          rows: _currentPageData.map((pricing) {
            return DataRow(
              cells: [
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pricing.provider,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    pricing.modelId,
                    style: TextStyle(
                      color: WebTheme.getTextColor(context),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    pricing.modelName ?? '-',
                    style: TextStyle(color: WebTheme.getTextColor(context)),
                  ),
                ),
                DataCell(
                  Text(
                    pricing.priceDisplayText,
                    style: TextStyle(
                      color: WebTheme.getTextColor(context),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    pricing.maxContextTokens?.toString() ?? '-',
                    style: TextStyle(color: WebTheme.getTextColor(context)),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getSourceColor(pricing.source).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pricing.sourceDisplayText,
                      style: TextStyle(
                        fontSize: 11,
                        color: _getSourceColor(pricing.source),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _editPricing(pricing),
                        icon: const Icon(Icons.edit, size: 18),
                        color: Colors.blue,
                        tooltip: '编辑',
                      ),
                      IconButton(
                        onPressed: () => _deletePricing(pricing),
                        icon: const Icon(Icons.delete, size: 18),
                        color: Colors.red,
                        tooltip: '删除',
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        border: Border(
          top: BorderSide(
            color: WebTheme.getTextColor(context).withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 0 ? () {
              setState(() {
                _currentPage--;
              });
            } : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一页',
          ),
          
          ...List.generate(_totalPages, (index) {
            final isCurrentPage = index == _currentPage;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ElevatedButton(
                onPressed: isCurrentPage ? null : () {
                  setState(() {
                    _currentPage = index;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCurrentPage 
                      ? Colors.blue 
                      : WebTheme.getCardColor(context),
                  foregroundColor: isCurrentPage 
                      ? Colors.white 
                      : WebTheme.getTextColor(context),
                  minimumSize: const Size(40, 40),
                ),
                child: Text('${index + 1}'),
              ),
            );
          }),
          
          IconButton(
            onPressed: _currentPage < _totalPages - 1 ? () {
              setState(() {
                _currentPage++;
              });
            } : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(String? source) {
    switch (source) {
      case 'OFFICIAL_API':
        return Colors.green;
      case 'MANUAL':
        return Colors.blue;
      case 'WEB_SCRAPING':
        return Colors.orange;
      case 'DEFAULT':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
