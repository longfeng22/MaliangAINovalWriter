/// LLM可观测性管理页面
/// 用于查看和分析大模型调用日志，便于运维和观察

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:ainoval/models/admin/llm_observability_models.dart';
import 'package:ainoval/services/api_service/repositories/impl/admin/llm_observability_repository_impl.dart';
import 'package:ainoval/widgets/common/loading_indicator.dart';
import 'package:ainoval/widgets/common/error_view.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/services.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:ainoval/widgets/analytics/multi_series_line_chart.dart';

class LLMObservabilityScreen extends StatefulWidget {
  const LLMObservabilityScreen({super.key});

  @override
  State<LLMObservabilityScreen> createState() => _LLMObservabilityScreenState();
}

class _LLMObservabilityScreenState extends State<LLMObservabilityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late LLMObservabilityRepositoryImpl _repository;
  final String _tag = 'LLMObservabilityScreen';

  // 数据状态
  List<LLMTrace> _traces = [];
  String? _nextCursor;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Map<String, dynamic> _overviewStats = {};
  List<ProviderStatistics> _providerStats = [];
  List<ModelStatistics> _modelStats = [];
  List<UserStatistics> _userStats = [];
  SystemHealthStatus? _systemHealth;
  LLMTrace? _selectedTrace;

  // UI状态
  bool _isLoading = false;
  String? _error;
  static const int _pageSize = 50;
  final ScrollController _listScrollController = ScrollController();

  // 搜索条件
  LLMTraceSearchCriteria _searchCriteria = const LLMTraceSearchCriteria();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _providerController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _sessionIdController = TextEditingController();
  final TextEditingController _contentSearchController = TextEditingController();
  final TextEditingController _correlationIdController = TextEditingController();
  final TextEditingController _traceIdController = TextEditingController();
  String? _callType; // CHAT/STREAMING_CHAT/COMPLETION/STREAMING_COMPLETION
  final TextEditingController _tagController = TextEditingController();
  DateTime? _startTime;
  DateTime? _endTime;
  bool? _hasError;
  
  // ✅ 业务类型过滤（用标签形式）
  final Map<String, String> _businessTypeLabels = {
    'TEXT_EXPANSION': '文本扩写',
    'TEXT_REFACTOR': '文本润色',
    'TEXT_SUMMARY': '文本总结',
    'AI_CHAT': 'AI对话',
    'SCENE_TO_SUMMARY': '场景转摘要',
    'SUMMARY_TO_SCENE': '摘要转场景',
    'NOVEL_GENERATION': '小说生成',
    'PROFESSIONAL_FICTION_CONTINUATION': '专业续写',
    'SCENE_BEAT_GENERATION': '场景节拍生成',
    'SETTING_TREE_GENERATION': '设定树生成',
    'SETTING_GENERATION_TOOL': '设定生成工具',
    'NOVEL_COMPOSE': '小说编排',
    'STORY_PLOT_CONTINUATION': '剧情续写',
    'KNOWLEDGE_EXTRACTION_SETTING': '知识库拆书-设定',
    'KNOWLEDGE_EXTRACTION_OUTLINE': '知识库拆书-大纲',
    '__NULL__': '未分类', // ✅ 特殊标识用于表示null/empty类型
  };
  
  // 选中的业务类型（默认所有类型都选中，除了知识库相关）
  late Set<String> _selectedBusinessTypes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _repository = GetIt.instance<LLMObservabilityRepositoryImpl>();
    
    // 默认所有类型都选中，除了知识库相关和未分类
    _selectedBusinessTypes = _businessTypeLabels.keys.where((type) {
      return !type.startsWith('KNOWLEDGE_EXTRACTION') && type != '__NULL__';
    }).toSet();
    
    _listScrollController.addListener(() {
      if (_listScrollController.position.pixels >=
              _listScrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMore &&
          _tabController.index == 1) {
        _loadMoreTracesCursor();
      }
    });
    _initializeData().then((_) {
      // 初始化后自动加载趋势（默认：调用次数 + 未选择功能时加载总体）
      _loadAndRenderTrendsMulti();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _listScrollController.dispose();
    _userIdController.dispose();
    _providerController.dispose();
    _modelController.dispose();
    _sessionIdController.dispose();
    _contentSearchController.dispose();
    _correlationIdController.dispose();
    _traceIdController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _resetCursorAndLoad(),
        _loadOverviewStatistics(),
        _loadProviderStatistics(),
        _loadModelStatistics(),
        _loadUserStatistics(),
        _loadSystemHealth(),
      ]);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resetCursorAndLoad() async {
    setState(() {
      _traces = [];
      _selectedTrace = null;
      _nextCursor = null;
      _hasMore = true;
    });
    await _loadMoreTracesCursor();
  }

  Future<void> _loadMoreTracesCursor() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    try {
      // ✅ 不通过后端API过滤businessType，因为后端只支持单个类型
      // 我们在前端基于_selectedBusinessTypes集合进行多选过滤
      final resp = await _repository.getTracesByCursor(
        cursor: _nextCursor,
        limit: _pageSize,
        userId: _userIdController.text.isEmpty ? null : _userIdController.text,
        provider: _providerController.text.isEmpty ? null : _providerController.text,
        model: _modelController.text.isEmpty ? null : _modelController.text,
        sessionId: _sessionIdController.text.isEmpty ? null : _sessionIdController.text,
        hasError: _hasError,
        businessType: null,  // ✅ 改为null，不在后端过滤
        correlationId: _correlationIdController.text.isEmpty ? null : _correlationIdController.text,
        traceId: _traceIdController.text.isEmpty ? null : _traceIdController.text,
        type: _callType,
        tag: _tagController.text.isEmpty ? null : _tagController.text,
        startTime: _startTime,
        endTime: _endTime,
      );

      // 追加并去重
      final existingIds = _traces.map((e) => e.id).toSet();
      final List<LLMTrace> appended = [
        ..._traces,
        ...resp.items.where((e) => !existingIds.contains(e.id)),
      ];

      // 本地内容搜索过滤（可选）
      List<LLMTrace> finalList = appended;
      
      // ✅ 应用业务类型过滤（前端过滤）
      finalList = finalList.where((trace) {
        // 如果trace没有businessType或为空，映射为__NULL__特殊标识
        if (trace.businessType == null || trace.businessType!.isEmpty) {
          return _selectedBusinessTypes.contains('__NULL__');
        }
        // 只保留选中的业务类型
        return _selectedBusinessTypes.contains(trace.businessType);
      }).toList();
      
      if (_contentSearchController.text.isNotEmpty) {
        final searchTerm = _contentSearchController.text.toLowerCase();
        finalList = finalList.where((trace) {
          final messages = trace.request.messages;
          if (messages != null) {
            for (final m in messages) {
              final c = m.content;
              if (c != null && c.toLowerCase().contains(searchTerm)) return true;
            }
          }
          final rc = trace.response?.content;
          if (rc != null && rc.toLowerCase().contains(searchTerm)) return true;
          return false;
        }).toList();
      }

      // 维护选中项
      LLMTrace? nextSelected = _selectedTrace;
      nextSelected ??= finalList.isNotEmpty ? finalList.first : null;

      setState(() {
        _traces = finalList;
        _selectedTrace = nextSelected;
        _nextCursor = resp.nextCursor;
        _hasMore = resp.hasMore;
      });
    } catch (e) {
      TopToast.error(context, '加载调用日志失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadOverviewStatistics() async {
    try {
      final stats = await _repository.getOverviewStatistics(
        startTime: _startTime,
        endTime: _endTime,
      );
      setState(() {
        _overviewStats = stats;
      });
    } catch (e) {
      throw Exception('加载统计概览失败: $e');
    }
  }

  Future<void> _loadProviderStatistics() async {
    try {
      final stats = await _repository.getProviderStatistics(
        startTime: _startTime,
        endTime: _endTime,
      );
      setState(() {
        _providerStats = stats;
      });
    } catch (e) {
      AppLogger.e(_tag, '加载提供商统计失败', e);
      // 不抛出异常，设置空列表避免崩溃
      setState(() {
        _providerStats = [];
      });
    }
  }

  Future<void> _loadModelStatistics() async {
    try {
      final stats = await _repository.getModelStatistics(
        startTime: _startTime,
        endTime: _endTime,
      );
      setState(() {
        _modelStats = stats;
      });
    } catch (e) {
      AppLogger.e(_tag, '加载模型统计失败', e);
      // 不抛出异常，设置空列表避免崩溃
      setState(() {
        _modelStats = [];
      });
    }
  }

  Future<void> _loadUserStatistics() async {
    try {
      final stats = await _repository.getUserStatistics(
        startTime: _startTime,
        endTime: _endTime,
      );
      setState(() {
        _userStats = stats;
      });
    } catch (e) {
      AppLogger.e(_tag, '加载用户统计失败', e);
      // 不抛出异常，设置空列表避免崩溃
      setState(() {
        _userStats = [];
      });
    }
  }

  Future<void> _loadSystemHealth() async {
    try {
      final health = await _repository.getSystemHealth();
      setState(() {
        _systemHealth = health;
      });
    } catch (e) {
      AppLogger.e(_tag, '加载系统健康状态失败', e);
      // 不抛出异常，设置null避免崩溃
      setState(() {
        _systemHealth = null;
      });
    }
  }

  void _searchTraces() {
    setState(() {
      _searchCriteria = LLMTraceSearchCriteria(
        userId: _userIdController.text.isEmpty ? null : _userIdController.text,
        provider: _providerController.text.isEmpty ? null : _providerController.text,
        model: _modelController.text.isEmpty ? null : _modelController.text,
        sessionId: _sessionIdController.text.isEmpty ? null : _sessionIdController.text,
        hasError: _hasError,
        startTime: _startTime,
        endTime: _endTime,
        page: 0,
        size: _pageSize,
      );
    });
    
    _resetCursorAndLoad();
  }

  void _clearSearch() {
    setState(() {
      _userIdController.clear();
      _providerController.clear();
      _modelController.clear();
      _sessionIdController.clear();
      _contentSearchController.clear();
      _correlationIdController.clear();
      _traceIdController.clear();
      _callType = null;
      _tagController.clear();
      _hasError = null;
      // 恢复默认的业务类型过滤（不含知识库和未分类）
      _selectedBusinessTypes = _businessTypeLabels.keys.where((type) {
        return !type.startsWith('KNOWLEDGE_EXTRACTION') && type != '__NULL__';
      }).toSet();
      _startTime = null;
      _endTime = null;
      _searchCriteria = const LLMTraceSearchCriteria();
    });
    _resetCursorAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: const Center(child: LoadingIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: ErrorView(
            error: _error!,
            onRetry: _initializeData,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM可观测性'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeData,
            tooltip: '刷新数据',
          ),
          IconButton(
            icon: const Icon(Icons.health_and_safety),
            onPressed: _showSystemHealthDialog,
            tooltip: '系统健康状态',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览', icon: Icon(Icons.dashboard)),
            Tab(text: '调用日志', icon: Icon(Icons.list)),
            Tab(text: '提供商统计', icon: Icon(Icons.cloud)),
            Tab(text: '模型统计', icon: Icon(Icons.smart_toy)),
            Tab(text: '用户统计', icon: Icon(Icons.people)),
          ],
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildTracesTab(),
              _buildProviderStatsTab(),
              _buildModelStatsTab(),
              _buildUserStatsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimeRangeSelector(),
          const SizedBox(height: 16),
          _buildOverviewCards(),
          const SizedBox(height: 16),
          _buildTrendsSection(),
          const SizedBox(height: 16),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildTrendsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('趋势图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildTrendMetricDropdown(),
                _buildTrendIntervalDropdown(),
                _buildTrendFeatureMultiSelect(),
                _buildTrendModelField(),
                _buildTrendProviderField(),
                ElevatedButton.icon(
                  onPressed: _loadAndRenderTrendsMulti,
                  icon: const Icon(Icons.show_chart),
                  label: const Text('生成趋势'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTrendChart(),
          ],
        ),
      ),
    );
  }

  // 以下为简化的趋势控件与展示占位，后续可替换为真正折线图组件
  String _trendMetric = 'count';
  String _trendInterval = 'hour';
  String? _trendBusinessType;
  final _trendModelCtrl = TextEditingController();
  final _trendProviderCtrl = TextEditingController();
  // 多线折线图数据
  final List<Color> _trendPalette = const [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
  ];
  final List<String> _trendSelectedFeatures = [];
  List<LineSeries> _trendMultiSeries = const [];

  Widget _buildTrendMetricDropdown() {
    return DropdownButton<String>(
      value: _trendMetric,
      items: const [
        DropdownMenuItem(value: 'count', child: Text('调用次数')),
        DropdownMenuItem(value: 'successRate', child: Text('成功率')),
        DropdownMenuItem(value: 'avgLatency', child: Text('平均延迟')),
        DropdownMenuItem(value: 'p90Latency', child: Text('TP90')),
        DropdownMenuItem(value: 'p95Latency', child: Text('TP95')),
        DropdownMenuItem(value: 'tokens', child: Text('Token用量')),
      ],
      onChanged: (v) => setState(() => _trendMetric = v ?? 'count'),
    );
  }

  Widget _buildTrendIntervalDropdown() {
    return DropdownButton<String>(
      value: _trendInterval,
      items: const [
        DropdownMenuItem(value: 'hour', child: Text('按小时')),
        DropdownMenuItem(value: 'day', child: Text('按天')),
      ],
      onChanged: (v) => setState(() => _trendInterval = v ?? 'hour'),
    );
  }

  Widget _buildTrendFeatureMultiSelect() {
    const List<Map<String, String>> options = [
      {'key': 'TEXT_EXPANSION', 'label': '文本扩写'},
      {'key': 'TEXT_REFACTOR', 'label': '文本润色'},
      {'key': 'TEXT_SUMMARY', 'label': '文本总结'},
      {'key': 'AI_CHAT', 'label': 'AI对话'},
      {'key': 'SCENE_TO_SUMMARY', 'label': '场景转摘要'},
      {'key': 'SUMMARY_TO_SCENE', 'label': '摘要转场景'},
      {'key': 'NOVEL_GENERATION', 'label': '小说生成'},
      {'key': 'PROFESSIONAL_FICTION_CONTINUATION', 'label': '专业续写'},
      {'key': 'SCENE_BEAT_GENERATION', 'label': '场景节拍生成'},
      {'key': 'SETTING_TREE_GENERATION', 'label': '设定树生成'},
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...options.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final selected = _trendSelectedFeatures.contains(item['key']);
            final color = _trendPalette[idx % _trendPalette.length];
            return FilterChip(
              selected: selected,
              label: Text(item['label']!),
              avatar: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _trendSelectedFeatures.add(item['key']!);
                  } else {
                    _trendSelectedFeatures.remove(item['key']!);
                  }
                });
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTrendModelField() {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: _trendModelCtrl,
        decoration: const InputDecoration(labelText: '模型(可选)'),
      ),
    );
  }

  Widget _buildTrendProviderField() {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: _trendProviderCtrl,
        decoration: const InputDecoration(labelText: '提供商(可选)'),
      ),
    );
  }

  Future<void> _loadAndRenderTrendsMulti() async {
    try {
      final List<String> features = _trendSelectedFeatures.isEmpty && _trendBusinessType != null
          ? [_trendBusinessType!]
          : _trendSelectedFeatures.toList();

      final bool renderOverallOnly = features.isEmpty;

      final List<Future<Map<String, dynamic>>> futures = [];
      if (renderOverallOnly) {
        futures.add(_repository.getTrends(
          metric: _trendMetric,
          businessType: null,
          model: _trendModelCtrl.text.isEmpty ? null : _trendModelCtrl.text,
          provider: _trendProviderCtrl.text.isEmpty ? null : _trendProviderCtrl.text,
          interval: _trendInterval,
          startTime: _startTime,
          endTime: _endTime,
        ));
      } else {
        for (final f in features) {
          futures.add(_repository.getTrends(
            metric: _trendMetric,
            businessType: f,
            model: _trendModelCtrl.text.isEmpty ? null : _trendModelCtrl.text,
            provider: _trendProviderCtrl.text.isEmpty ? null : _trendProviderCtrl.text,
            interval: _trendInterval,
            startTime: _startTime,
            endTime: _endTime,
          ));
        }
      }

      final results = await Future.wait(futures);
      final List<LineSeries> lines = [];
      if (renderOverallOnly) {
        final series = (results.first['series'] as List?)?.cast<Map>() ?? const [];
        lines.add(LineSeries(
          name: '总体',
          color: _trendPalette.first,
          points: series.map((p) => LinePoint(label: (p['timestamp'] ?? '').toString(), value: (p['value'] as num?)?.toDouble() ?? 0)).toList(),
        ));
      } else {
        for (int i = 0; i < results.length; i++) {
          final series = (results[i]['series'] as List?)?.cast<Map>() ?? const [];
          final color = _trendPalette[i % _trendPalette.length];
          final name = features[i];
          lines.add(LineSeries(
            name: _formatFeatureName(name),
            color: color,
            points: series.map((p) => LinePoint(label: (p['timestamp'] ?? '').toString(), value: (p['value'] as num?)?.toDouble() ?? 0)).toList(),
          ));
        }
      }

      setState(() {
        _trendMultiSeries = lines;
      });
    } catch (e) {
      TopToast.error(context, '加载趋势失败: $e');
    }
  }

  Widget _buildTrendChart() {
    return MultiSeriesLineChart(
      title: _metricDisplayName(_trendMetric),
      seriesList: _trendMultiSeries,
      height: 280,
      showArea: false,
    );
  }

  String _metricDisplayName(String? m) {
    switch (m) {
      case 'count':
        return '调用次数';
      case 'avgLatency':
        return '平均延迟(ms)';
      case 'p90Latency':
        return 'TP90延迟(ms)';
      case 'p95Latency':
        return 'TP95延迟(ms)';
      case 'tokens':
        return 'Token用量';
      case 'successRate':
      default:
        return '成功率(%)';
    }
  }

  String _formatFeatureName(String key) {
    switch (key) {
      case 'TEXT_EXPANSION':
        return '文本扩写';
      case 'TEXT_REFACTOR':
        return '文本润色';
      case 'TEXT_SUMMARY':
        return '文本总结';
      case 'AI_CHAT':
        return 'AI对话';
      case 'SCENE_TO_SUMMARY':
        return '场景转摘要';
      case 'SUMMARY_TO_SCENE':
        return '摘要转场景';
      case 'NOVEL_GENERATION':
        return '小说生成';
      case 'PROFESSIONAL_FICTION_CONTINUATION':
        return '专业续写';
      case 'SCENE_BEAT_GENERATION':
        return '场景节拍生成';
      case 'SETTING_TREE_GENERATION':
        return '设定树生成';
      default:
        return key;
    }
  }

  Widget _buildTracesTab() {
    return Column(
      children: [
        _buildSearchFilters(),
        Expanded(
          child: Row(
            children: [
              Flexible(
                flex: 2,
                child: _buildLeftListPane(),
              ),
              const VerticalDivider(width: 1),
              Flexible(
                flex: 3,
                child: _buildRightDetailPane(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderStatsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _providerStats.length,
      itemBuilder: (context, index) {
        final providerStat = _providerStats[index];
        return _buildProviderStatCard(providerStat);
      },
    );
  }

  Widget _buildModelStatsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _modelStats.length,
      itemBuilder: (context, index) {
        final modelStat = _modelStats[index];
        return _buildModelStatCard(modelStat);
      },
    );
  }

  Widget _buildUserStatsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _userStats.length,
      itemBuilder: (context, index) {
        final userStat = _userStats[index];
        return _buildUserStatCard(userStat);
      },
    );
  }

  Widget _buildTimeRangeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '时间范围',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '开始时间',
                      hintText: _startTime?.toString() ?? '选择开始时间',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startTime ?? DateTime.now().subtract(const Duration(days: 7)),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() {
                          _startTime = date;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '结束时间',
                      hintText: _endTime?.toString() ?? '选择结束时间',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endTime ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() {
                          _endTime = date;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    _loadOverviewStatistics();
                    _loadProviderStatistics();
                    _loadModelStatistics();
                    _loadUserStatistics();
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCards() {
    return Row(
      children: [
        Expanded(child: _buildStatCard('总调用次数', _overviewStats['totalCalls']?.toString() ?? '0')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('成功次数', _overviewStats['successfulCalls']?.toString() ?? '0')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('失败次数', _overviewStats['failedCalls']?.toString() ?? '0')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('成功率', '${(_overviewStats['successRate'] ?? 0.0).toStringAsFixed(1)}%')),
      ],
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建业务类型过滤标签
  Widget _buildBusinessTypeFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '业务类型过滤（默认隐藏知识库拆书和未分类）：',
          style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _businessTypeLabels.entries.map((entry) {
            final isSelected = _selectedBusinessTypes.contains(entry.key);
            final isKnowledgeType = entry.key.startsWith('KNOWLEDGE_EXTRACTION');
            final isNullType = entry.key == '__NULL__';
            
            return FilterChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedBusinessTypes.add(entry.key);
                  } else {
                    _selectedBusinessTypes.remove(entry.key);
                  }
                  // 重新加载数据以应用过滤
                  _resetCursorAndLoad();
                });
              },
              selectedColor: isNullType
                  ? Colors.grey.withOpacity(0.3)
                  : (isKnowledgeType 
                      ? Colors.orange.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.3)),
              backgroundColor: isNullType
                  ? Colors.grey.withOpacity(0.05)
                  : (isKnowledgeType 
                      ? Colors.grey.withOpacity(0.1)
                      : null),
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected 
                    ? (isNullType 
                        ? Colors.grey[800]
                        : (isKnowledgeType ? Colors.orange[800] : Colors.blue[800]))
                    : Colors.grey[600],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedBusinessTypes = _businessTypeLabels.keys.toSet();
                  _resetCursorAndLoad();
                });
              },
              icon: const Icon(Icons.select_all, size: 16),
              label: const Text('全选', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedBusinessTypes.clear();
                  _resetCursorAndLoad();
                });
              },
              icon: const Icon(Icons.deselect, size: 16),
              label: const Text('清空', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedBusinessTypes = _businessTypeLabels.keys.where((type) {
                    return !type.startsWith('KNOWLEDGE_EXTRACTION') && type != '__NULL__';
                  }).toSet();
                  _resetCursorAndLoad();
                });
              },
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('默认（不含知识库和未分类）', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '快速操作',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _exportTraces,
                  icon: const Icon(Icons.download),
                  label: const Text('导出日志'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _showCleanupDialog,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('清理旧日志'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _showSystemHealthDialog,
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('系统健康检查'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchFilters() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '搜索过滤',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _contentSearchController,
                    decoration: const InputDecoration(
                      labelText: '内容搜索',
                      hintText: '搜索提示词或回复内容...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _searchTraces(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      labelText: '用户ID',
                      hintText: '输入用户ID',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _providerController,
                    decoration: const InputDecoration(
                      labelText: '提供商',
                      hintText: '输入提供商名称',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(
                      labelText: '模型',
                      hintText: '输入模型名称',
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<bool?>(
                    value: _hasError,
                    decoration: const InputDecoration(
                      labelText: '错误状态',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部')),
                      DropdownMenuItem(value: true, child: Text('有错误')),
                      DropdownMenuItem(value: false, child: Text('无错误')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _hasError = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _correlationIdController,
                    decoration: const InputDecoration(
                      labelText: '关联ID (correlationId)',
                      hintText: '输入关联ID',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _traceIdController,
                    decoration: const InputDecoration(
                      labelText: 'Trace ID',
                      hintText: '输入Trace ID',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _callType,
                    decoration: const InputDecoration(
                      labelText: '调用类型',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部')),
                      DropdownMenuItem(value: 'CHAT', child: Text('CHAT')),
                      DropdownMenuItem(value: 'STREAMING_CHAT', child: Text('STREAMING_CHAT')),
                      DropdownMenuItem(value: 'COMPLETION', child: Text('COMPLETION')),
                      DropdownMenuItem(value: 'STREAMING_COMPLETION', child: Text('STREAMING_COMPLETION')),
                    ],
                    onChanged: (v) => setState(() => _callType = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      labelText: '会话标签 (tag)',
                      hintText: '输入标签，如 prod/beta',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ✅ 业务类型过滤标签
            _buildBusinessTypeFilters(),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _searchTraces,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.clear),
                  label: const Text('清空'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 左侧列表面板
  Widget _buildLeftListPane() {
    return Column(
      children: [
        // 顶部信息条与会话筛选提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _contentSearchController.text.isNotEmpty
                      ? '搜索到 ${_traces.length} 条包含 "${_contentSearchController.text}" 的记录'
                      : '显示 ${_traces.length} 条记录',
                  style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_contentSearchController.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    _contentSearchController.clear();
                    _searchTraces();
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('清除搜索'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (_sessionIdController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 14, color: Colors.teal.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '会话: ${_sessionIdController.text.length > 8 ? _sessionIdController.text.substring(0, 8) : _sessionIdController.text}',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _sessionIdController.clear();
                          });
                          _searchTraces();
                        },
                        child: Icon(Icons.close, size: 14, color: Colors.teal.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // 列表
        Expanded(
          child: _traces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _contentSearchController.text.isNotEmpty ? Icons.search_off : Icons.inbox_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _contentSearchController.text.isNotEmpty
                            ? '未找到包含 "${_contentSearchController.text}" 的记录'
                            : '暂无调用日志数据',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _listScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _traces.length + ((_isLoadingMore || _hasMore) ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    if (index >= _traces.length) {
                      // 底部加载/提示
                      if (_isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (!_hasMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: Text('已无更多')),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    final trace = _traces[index];
                    final selected = _selectedTrace?.id == trace.id;
                    return _buildTraceListItem(trace, selected: selected, onTap: () {
                      setState(() {
                        _selectedTrace = trace;
                      });
                    });
                  },
                ),
        ),
      ],
    );
  }

  // 右侧详情面板
  Widget _buildRightDetailPane() {
    final trace = _selectedTrace;
    if (trace == null) {
      return Center(
        child: Text(
          '请选择左侧一条调用记录',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Column(
      children: [
        // 详情头部操作栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              Icon(Icons.list_alt, size: 18, color: Colors.blueGrey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${trace.provider} - ${trace.model}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatDateTime(trace.timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              if (trace.sessionId != null)
                OutlinedButton.icon(
                  onPressed: () {
                    final sid = trace.sessionId!;
                    _sessionIdController.text = sid;
                    _searchTraces();
                  },
                  icon: const Icon(Icons.filter_list),
                  label: const Text('查看此会话'),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildTraceDetails(trace),
          ),
        ),
      ],
    );
  }

  // 左侧列表项
  Widget _buildTraceListItem(LLMTrace trace, {required bool selected, required VoidCallback onTap}) {
    // 用户与助手消息预览
    String userMessagePreview = '';
    String assistantMessagePreview = '';
    final messages = trace.request.messages;
    if (messages != null) {
      for (final message in messages) {
        if (message.role.toLowerCase() == 'user' && userMessagePreview.isEmpty) {
          final content = message.content;
          if (content != null) {
            userMessagePreview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
          }
        }
      }
    }
    final responseContent = trace.response?.content;
    if (responseContent != null && responseContent.isNotEmpty) {
      assistantMessagePreview = responseContent.length > 60 ? '${responseContent.substring(0, 60)}...' : responseContent;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.blue.shade200 : Colors.grey.withOpacity(0.2)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusIcon(trace.status),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${trace.provider} - ${trace.model}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDateTime(trace.timestamp),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (trace.userId != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_circle, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(trace.userId!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      if (trace.sessionId != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              trace.sessionId!.length > 8 ? trace.sessionId!.substring(0, 8) : trace.sessionId!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer, size: 14, color: Colors.purple.shade600),
                          const SizedBox(width: 4),
                          Text('${trace.performance?.requestLatencyMs ?? 0}ms', style: TextStyle(fontSize: 11, color: Colors.purple.shade700)),
                        ],
                      ),
                      if (trace.response?.tokenUsage != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stacked_line_chart, size: 14, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text('${trace.response!.tokenUsage!.totalTokens ?? 0}T', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                          ],
                        ),
                      if ((trace.toolCalls?.isNotEmpty ?? false))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.build, size: 14, color: Colors.blueGrey.shade600),
                            const SizedBox(width: 4),
                            Text('${trace.toolCalls!.length}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
                          ],
                        ),
                    ],
                  ),
                  if (userMessagePreview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person, size: 14, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            userMessagePreview,
                            style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (assistantMessagePreview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.smart_toy, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            assistantMessagePreview,
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  

  Widget _buildStatusIcon(LLMTraceStatus status) {
    switch (status) {
      case LLMTraceStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case LLMTraceStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 20);
      case LLMTraceStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.orange, size: 20);
      case LLMTraceStatus.timeout:
        return const Icon(Icons.timer_off, color: Colors.red, size: 20);
      case LLMTraceStatus.cancelled:
        return const Icon(Icons.cancel, color: Colors.grey, size: 20);
    }
  }

  Widget _buildTraceDetails(LLMTrace trace) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                // 展开/折叠由 ExpansionTile 控制；这里作为示例，未来可将详情分段折叠加入统一控制
                setState(() {});
              },
              icon: const Icon(Icons.unfold_more),
              label: const Text('展开/折叠全部'),
            ),
          ],
        ),
        // 基本信息
        _buildCopyableDetailRow('Trace ID', trace.traceId),
        _buildCopyableDetailRow('会话ID', trace.sessionId ?? 'N/A'),
        _buildDetailRow('时间戳', formatDateTime(trace.timestamp)),
        _buildDetailRow('流式', trace.isStreaming ? '是' : '否'),
        
        const SizedBox(height: 16),
        const Divider(),
        
        // 输入内容（重点显示）
        _buildInputSection(trace),
        
        const SizedBox(height: 16),
        const Divider(),
        
        // 输出内容（重点显示）
        if (trace.response != null) _buildOutputSection(trace.response!),
        
        const SizedBox(height: 16),
        const Divider(),

        // 工具调用（结构化展示）
        if (trace.toolCalls?.isNotEmpty ?? false) _buildToolCallsSection(trace),

        if (trace.toolCalls?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          const Divider(),
        ],
        
        // 模型参数
        _buildParametersSection(trace),
        
        // 性能指标
        const SizedBox(height: 16),
        const Divider(),
        _buildPerformanceSection(trace),
        
        // 错误信息
        if (trace.error != null) ...[
          const SizedBox(height: 16),
          const Divider(),
          _buildErrorSection(trace.error!),
        ],
      ],
    );
  }

  Widget _buildInputSection(LLMTrace trace) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📝 输入内容 (提示词和上下文)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '消息数量: ${trace.request.messages?.length ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ...(trace.request.messages?.asMap().entries.map((entry) {
                final index = entry.key;
                final message = entry.value;
                return _buildMessageCard(index + 1, message);
              }) ?? []),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard(int index, LLMMessage message) {
    MaterialColor roleColor;
    IconData roleIcon;
    switch (message.role.toLowerCase()) {
      case 'system':
        roleColor = Colors.purple;
        roleIcon = Icons.settings;
        break;
      case 'user':
        roleColor = Colors.green;
        roleIcon = Icons.person;
        break;
      case 'assistant':
        roleColor = Colors.blue;
        roleIcon = Icons.smart_toy;
        break;
      default:
        roleColor = Colors.grey;
        roleIcon = Icons.message;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: roleColor.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(roleIcon, size: 16, color: roleColor),
              const SizedBox(width: 4),
              Text(
                '${message.role.toUpperCase()} #$index',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                  fontSize: 12,
                ),
              ),
              if (message.name != null) ...[
                const SizedBox(width: 8),
                Text(
                  'Name: ${message.name}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => _copyToClipboard(message.content ?? '', '消息内容'),
                tooltip: '复制消息内容',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: _buildHighlightedText(
              message.content ?? '(空内容)',
              const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputSection(LLMResponse response) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '🤖 输出内容 (模型响应)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const Spacer(),
            if (response.content?.isNotEmpty ?? false) ...[
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyToClipboard(response.content ?? '', '模型响应'),
                tooltip: '复制响应内容',
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 8),
            ],
            if (response.tokenUsage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${response.tokenUsage!.totalTokens ?? 0} tokens',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (response.finishReason != null) ...[
                Row(
                  children: [
                    Icon(Icons.flag, size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '完成原因: ${response.finishReason}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.green.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: (response.content?.isEmpty ?? true)
                    ? const Text(
                        '(空响应)',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      )
                    : _buildHighlightedText(
                        response.content ?? '',
                        const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
              ),
              if (response.tokenUsage != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTokenStat('输入', response.tokenUsage!.promptTokens ?? 0, Colors.blue),
                    _buildTokenStat('输出', response.tokenUsage!.completionTokens ?? 0, Colors.orange),
                    _buildTokenStat('总计', response.tokenUsage!.totalTokens ?? 0, Colors.green),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTokenStat(String label, int value, MaterialColor color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildParametersSection(LLMTrace trace) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '⚙️ 模型参数',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (trace.request.temperature != null)
              _buildParameterChip('温度', trace.request.temperature.toString()),
            if (trace.request.topP != null)
              _buildParameterChip('Top P', trace.request.topP.toString()),
            if (trace.request.topK != null)
              _buildParameterChip('Top K', trace.request.topK.toString()),
            if (trace.request.maxTokens != null)
              _buildParameterChip('最大Token', trace.request.maxTokens.toString()),
            if (trace.request.seed != null)
              _buildParameterChip('随机种子', trace.request.seed.toString()),
            if (trace.request.responseFormat != null)
              _buildParameterChip('响应格式', trace.request.responseFormat!),
          ],
        ),
      ],
    );
  }

  Widget _buildToolCallsSection(LLMTrace trace) {
    final calls = trace.toolCalls ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🛠️ 工具调用',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final tc = calls[index];
            final args = tc.arguments ?? {};
            final argsPretty = _prettyPrintJson(args);
            final isTextToSettings = tc.name.toLowerCase() == 'text_to_settings';

            // 构造概览UI（不直接展示原始JSON）
            Widget summary;
            if (isTextToSettings) {
              final nodes = (args['nodes'] is List) ? (args['nodes'] as List) : const [];
              final List<Widget> items = [];
              items.add(Row(
                children: [
                  _buildKVChip('节点数', nodes.length.toString(), Colors.blueGrey),
                  const SizedBox(width: 8),
                  if (args['complete'] != null)
                    _buildKVChip('complete', args['complete'].toString(), Colors.teal),
                ],
              ));
              final previewCount = nodes.length > 0 ? (nodes.length >= 3 ? 3 : nodes.length) : 0;
              for (int i = 0; i < previewCount; i++) {
                final n = nodes[i] as Map? ?? const {};
                final type = (n['type'] ?? 'UNKNOWN').toString();
                final name = (n['name'] ?? (n['tempId'] ?? '节点')).toString();
                items.add(Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.label, size: 14, color: Colors.blueGrey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('$name · $type', style: TextStyle(color: Colors.blueGrey.shade700)),
                      ),
                    ],
                  ),
                ));
              }
              if (nodes.length > previewCount) {
                items.add(Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('… 其余 ${nodes.length - previewCount} 个节点', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500)),
                ));
              }
              summary = Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
            } else {
              // 通用：展示前若干个 key 的值片段
              final keys = args.keys.take(4).toList();
              summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: keys.map((k) {
                  final v = args[k];
                  final text = (v is String) ? v : (v is List || v is Map) ? (v is List ? 'List(${v.length})' : 'Object') : v.toString();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _buildKVChip(k.toString(), text.length > 36 ? text.substring(0, 36) + '…' : text, Colors.blueGrey),
                      ],
                    ),
                  );
                }).toList(),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Row(
                  children: [
                    Icon(Icons.extension, size: 16, color: Colors.blueGrey.shade700),
                    const SizedBox(width: 6),
                    Text(
                      tc.name,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: summary),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制原始参数',
                  onPressed: () => _copyToClipboard(argsPretty, '工具参数'),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: SelectableText(
                      argsPretty,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: calls.length,
        )
      ],
    );
  }

  Widget _buildKVChip(String k, String v, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$k: $v',
        style: TextStyle(fontSize: 12, color: color.shade700),
      ),
    );
  }

  String _prettyPrintJson(Map<String, dynamic> map) {
    try {
      return const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {
      return map.toString();
    }
  }

  Widget _buildParameterChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: Colors.orange.shade700,
        ),
      ),
    );
  }

  Widget _buildPerformanceSection(LLMTrace trace) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 性能指标',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (trace.performance != null)
              _buildMetricCard('请求延迟', '${trace.performance!.requestLatencyMs ?? 0}ms', Colors.purple),
            if (trace.performance?.firstTokenLatencyMs != null)
              _buildMetricCard('首Token延迟', '${trace.performance!.firstTokenLatencyMs}ms', Colors.indigo),
            if (trace.performance?.totalDurationMs != null)
              _buildMetricCard('总耗时', '${trace.performance!.totalDurationMs}ms', Colors.cyan),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection(LLMError error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '❌ 错误信息',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('错误类型', error.type ?? '未知错误'),
              if (error.code != null)
                _buildDetailRow('错误代码', error.code!),
              const SizedBox(height: 8),
              const Text(
                '错误消息:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              SelectableText(
                error.message ?? '无错误消息',
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: Colors.red,
                ),
              ),
              if (error.stackTrace != null) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('堆栈跟踪'),
                  children: [
                    SelectableText(
                      error.stackTrace!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Text(value)),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制$label',
                  onPressed: value.isEmpty || value == 'N/A' ? null : () => _copyToClipboard(value, label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderStatCard(ProviderStatistics providerStat) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              providerStat.provider,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总调用', providerStat.statistics.totalCalls.toString()),
                _buildStatItem('成功率', '${providerStat.statistics.successRate.toStringAsFixed(1)}%'),
                _buildStatItem('平均延迟', '${providerStat.statistics.averageLatency.toStringAsFixed(0)}ms'),
                _buildStatItem('总Token', providerStat.statistics.totalTokens.toString()),
              ],
            ),
            if (providerStat.models.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('模型详情', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...providerStat.models.map((model) => _buildModelItem(model)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatCard(ModelStatistics modelStat) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${modelStat.modelName} (${modelStat.provider})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总调用', modelStat.statistics.totalCalls.toString()),
                _buildStatItem('成功率', '${modelStat.statistics.successRate.toStringAsFixed(1)}%'),
                _buildStatItem('平均延迟', '${modelStat.statistics.averageLatency.toStringAsFixed(0)}ms'),
                _buildStatItem('总Token', modelStat.statistics.totalTokens.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserStatCard(UserStatistics userStat) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '用户: ${userStat.username ?? userStat.userId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总调用', userStat.statistics.totalCalls.toString()),
                _buildStatItem('成功率', '${userStat.statistics.successRate.toStringAsFixed(1)}%'),
                _buildStatItem('平均延迟', '${userStat.statistics.averageLatency.toStringAsFixed(0)}ms'),
              ],
            ),
            if (userStat.topModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('常用模型: ${userStat.topModels.join(', ')}'),
            ],
            if (userStat.topProviders.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('常用提供商: ${userStat.topProviders.join(', ')}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildModelItem(ModelStatistics model) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(model.modelName),
          ),
          Text('${model.statistics.totalCalls} 次'),
          const SizedBox(width: 16),
          Text('${model.statistics.successRate.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  void _exportTraces() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final traces = await _repository.exportTraces(filterCriteria: _searchCriteria.toJson());

      TopToast.success(context, '成功导出 ${traces.length} 条日志');
    } catch (e) {
      TopToast.error(context, '导出失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showCleanupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理旧日志'),
        content: const Text('确定要清理30天前的日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _cleanupOldTraces();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _cleanupOldTraces() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final beforeTime = DateTime.now().subtract(const Duration(days: 30));
      final result = await _repository.cleanupOldTraces(beforeTime);
      final deletedCount = result['deletedCount'] ?? 0;

      TopToast.success(context, '成功清理 $deletedCount 条旧日志');

      await _resetCursorAndLoad();
    } catch (e) {
      TopToast.error(context, '清理失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSystemHealthDialog() {
    if (_systemHealth == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系统健康状态'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHealthStatus('整体状态', _systemHealth!.status.name),
              const Divider(),
              const Text('组件状态', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._buildComponentHealthStatuses(),
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

  List<Widget> _buildComponentHealthStatuses() {
    if (_systemHealth == null) return [];
    
    final components = _systemHealth!.components;
    if (components.isEmpty) return [];
    
    return components.entries.map((entry) {
      final componentHealth = entry.value;
      final status = componentHealth.status.name;
      return _buildHealthStatus(entry.key, status);
    }).toList();
  }

  Widget _buildHealthStatus(String name, String status) {
    Color color;
    String text;
    switch (status.toLowerCase()) {
      case 'healthy':
        color = Colors.green;
        text = '健康';
        break;
      case 'degraded':
        color = Colors.orange;
        text = '降级';
        break;
      case 'unhealthy':
        color = Colors.red;
        text = '不健康';
        break;
      default:
        color = Colors.grey;
        text = '未知';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name)),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 复制内容到剪贴板
  void _copyToClipboard(String content, String type) {
    Clipboard.setData(ClipboardData(text: content));
    TopToast.success(context, '$type已复制到剪贴板');
  }

  /// 构建高亮搜索文本的Widget
  Widget _buildHighlightedText(String text, TextStyle baseStyle) {
    final searchTerm = _contentSearchController.text.trim();
    
    if (searchTerm.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }

    final List<TextSpan> spans = [];
    final searchLower = searchTerm.toLowerCase();
    final textLower = text.toLowerCase();
    
    int start = 0;
    int index = textLower.indexOf(searchLower);
    
    while (index != -1) {
      // 添加搜索词之前的文本
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: baseStyle,
        ));
      }
      
      // 添加高亮的搜索词
      spans.add(TextSpan(
        text: text.substring(index, index + searchTerm.length),
        style: baseStyle.copyWith(
          backgroundColor: Colors.yellow.shade300,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ));
      
      start = index + searchTerm.length;
      index = textLower.indexOf(searchLower, start);
    }
    
    // 添加剩余的文本
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: baseStyle,
      ));
    }
    
    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }
}