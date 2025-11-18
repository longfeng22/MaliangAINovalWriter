import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import 'package:ainoval/models/admin/admin_models.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 用户活动趋势图表（支持登录和注册数据对比）
class UserActivityChart extends StatefulWidget {
  final List<ChartData> loginData;
  final List<ChartData> registrationData;
  final String title;

  const UserActivityChart({
    super.key,
    required this.loginData,
    required this.registrationData,
    this.title = '用户活动趋势',
  });

  @override
  State<UserActivityChart> createState() => _UserActivityChartState();
}

class _UserActivityChartState extends State<UserActivityChart> {
  int touchedIndex = -1;

  List<ChartData> get _sortedLoginData {
    final List<ChartData> copy = List<ChartData>.from(widget.loginData);
    copy.sort((a, b) => a.date.compareTo(b.date));
    return copy;
  }

  List<ChartData> get _sortedRegistrationData {
    final List<ChartData> copy = List<ChartData>.from(widget.registrationData);
    copy.sort((a, b) => a.date.compareTo(b.date));
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildChart(),
        const SizedBox(height: 24),
        _buildLegend(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: WebTheme.getCardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: WebTheme.getBorderColor(context).withOpacity(0.5),
        ),
      ),
      child: Text(
        widget.title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: WebTheme.getSecondaryTextColor(context),
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (widget.loginData.isEmpty && widget.registrationData.isEmpty) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        child: Text(
          '暂无数据',
          style: TextStyle(
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
      );
    }

    final double maxY = _getMaxY();
    final double yInterval = _getNiceGridInterval(maxY);
    final int maxLength = math.max(_sortedLoginData.length, _sortedRegistrationData.length);
    final double xInterval = _computeXLabelInterval(maxLength).toDouble();

    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: WebTheme.getBorderColor(context).withOpacity(0.3),
              strokeWidth: 1,
              dashArray: [3, 3],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < _sortedRegistrationData.length) {
                    final date = _sortedRegistrationData[index].label;
                    final label = _formatXAxisLabel(date);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: WebTheme.getSecondaryTextColor(context),
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: yInterval,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: WebTheme.getSecondaryTextColor(context),
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (maxLength - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            // 登录数据线
            if (_sortedLoginData.isNotEmpty)
              LineChartBarData(
                spots: _getLoginSpots(),
                isCurved: true,
                color: const Color(0xFF3B82F6),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF3B82F6).withOpacity(0.3),
                      const Color(0xFF3B82F6).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            // 注册数据线
            if (_sortedRegistrationData.isNotEmpty)
              LineChartBarData(
                spots: _getRegistrationSpots(),
                isCurved: true,
                color: const Color(0xFF10B981),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF10B981).withOpacity(0.3),
                      const Color(0xFF10B981).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => WebTheme.getCardColor(context),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final dataIndex = spot.x.toInt();
                  String label = '';
                  
                  if (spot.barIndex == 0 && dataIndex < _sortedLoginData.length) {
                    final data = _sortedLoginData[dataIndex];
                    label = '${data.label}\n登录: ${data.value.toInt()} 人';
                  } else if (spot.barIndex == 1 && dataIndex < _sortedRegistrationData.length) {
                    final data = _sortedRegistrationData[dataIndex];
                    label = '${data.label}\n注册: ${data.value.toInt()} 人';
                  }
                  
                  return LineTooltipItem(
                    label,
                    TextStyle(
                      color: WebTheme.getTextColor(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
            touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
              setState(() {
                if (response == null || response.lineBarSpots == null) {
                  touchedIndex = -1;
                } else {
                  touchedIndex = response.lineBarSpots!.first.x.toInt();
                }
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final loginTotal = _sortedLoginData.fold<double>(
      0, (sum, item) => sum + item.value,
    );
    final registrationTotal = _sortedRegistrationData.fold<double>(
      0, (sum, item) => sum + item.value,
    );
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(
          color: const Color(0xFF3B82F6),
          label: '登录',
          value: '${loginTotal.toInt()}人',
        ),
        const SizedBox(width: 32),
        _buildLegendItem(
          color: const Color(0xFF10B981),
          label: '注册',
          value: '${registrationTotal.toInt()}人',
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
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
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: WebTheme.getTextColor(context),
          ),
        ),
      ],
    );
  }

  List<FlSpot> _getLoginSpots() {
    return _sortedLoginData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();
  }

  List<FlSpot> _getRegistrationSpots() {
    return _sortedRegistrationData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();
  }

  double _getMaxY() {
    if (_sortedLoginData.isEmpty && _sortedRegistrationData.isEmpty) {
      return 10;
    }
    
    final maxLogin = _sortedLoginData.isEmpty 
        ? 0.0 
        : _sortedLoginData.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final maxRegistration = _sortedRegistrationData.isEmpty 
        ? 0.0 
        : _sortedRegistrationData.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final max = maxLogin > maxRegistration ? maxLogin : maxRegistration;
    
    // 添加20%的padding
    final withPadding = (max * 1.2).ceilToDouble();
    return withPadding <= 0 ? 10 : withPadding;
  }

  double _getNiceGridInterval(double maxY) {
    final double roughStep = (maxY <= 0 ? 10.0 : maxY) / 5.0;
    final double magnitude = math.pow(10, (math.log(roughStep) / math.ln10).floor()).toDouble();
    final double residual = roughStep / magnitude;
    double nice;
    if (residual >= 5) {
      nice = 5;
    } else if (residual >= 2) {
      nice = 2;
    } else {
      nice = 1;
    }
    return nice * magnitude;
  }

  int _computeXLabelInterval(int length) {
    if (length <= 10) return 1;
    if (length <= 20) return 2;
    if (length <= 40) return 4;
    return (length / 10).ceil();
  }

  String _formatXAxisLabel(String raw) {
    // 期望格式 'yyyy-MM-dd'，显示为 'MM-dd'
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(raw)) {
      return raw.substring(5); // 从第5个字符开始（MM-dd）
    }
    return raw;
  }
}

