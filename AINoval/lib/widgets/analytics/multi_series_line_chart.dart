import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

class LineSeries {
  final String name;
  final Color color;
  final List<LinePoint> points;

  const LineSeries({required this.name, required this.color, required this.points});
}

class LinePoint {
  final String label; // x 轴标签（时间）
  final double value; // y 值

  const LinePoint({required this.label, required this.value});
}

class MultiSeriesLineChart extends StatelessWidget {
  final List<LineSeries> seriesList;
  final double height;
  final String? title;
  final bool showArea;

  const MultiSeriesLineChart({
    super.key,
    required this.seriesList,
    this.height = 320,
    this.title,
    this.showArea = false,
  });

  @override
  Widget build(BuildContext context) {
    if (seriesList.isEmpty || seriesList.every((s) => s.points.isEmpty)) {
      return _buildEmpty(context);
    }

    final int maxLen = seriesList.map((s) => s.points.length).fold(0, (a, b) => a > b ? a : b);
    final double maxY = _getMaxY(seriesList);
    final double yInterval = _getNiceGridInterval(maxY);

    final List<String> xLabels = _collectXLabels(seriesList);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (maxLen - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.25),
                    strokeWidth: 1,
                    dashArray: const [3, 3],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) => Text(_formatYAxis(value), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: _computeXLabelInterval(xLabels.length).toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < xLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              xLabels[index],
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Colors.white,
                    tooltipBorder: BorderSide(color: Colors.grey.withOpacity(0.3)),
                    getTooltipItems: (spots) {
                      return spots.map((s) {
                        final series = seriesList[s.barIndex];
                        final x = s.x.toInt();
                        final label = x >= 0 && x < xLabels.length ? xLabels[x] : '';
                        return LineTooltipItem(
                          '${series.name}\n$label\n${_formatValue(s.y)}',
                          const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: _buildBars(seriesList, xLabels, showArea),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildLegend(seriesList),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('暂无趋势数据'),
    );
  }

  List<String> _collectXLabels(List<LineSeries> seriesList) {
    final Set<String> labels = {};
    for (final s in seriesList) {
      for (final p in s.points) {
        labels.add(p.label);
      }
    }
    final List<String> sorted = labels.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  List<LineChartBarData> _buildBars(List<LineSeries> seriesList, List<String> xLabels, bool showArea) {
    return seriesList.asMap().entries.map((entry) {
      final LineSeries series = entry.value;
      final List<FlSpot> spots = [];
      for (int i = 0; i < xLabels.length; i++) {
        final label = xLabels[i];
        final match = series.points.firstWhere(
          (p) => p.label == label,
          orElse: () => const LinePoint(label: '', value: double.nan),
        );
        if (match.label.isEmpty) {
          // 缺失点跳过，折线会断开
          continue;
        }
        spots.add(FlSpot(i.toDouble(), match.value));
      }

      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: series.color,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: showArea,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              series.color.withOpacity(0.25),
              series.color.withOpacity(0.0),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildLegend(List<LineSeries> seriesList) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: seriesList.map((s) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(s.name, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        );
      }).toList(),
    );
  }

  static double _getMaxY(List<LineSeries> seriesList) {
    double maxV = 0;
    for (final s in seriesList) {
      for (final p in s.points) {
        if (p.value > maxV) maxV = p.value;
      }
    }
    final padded = (maxV * 1.2).ceilToDouble();
    return padded <= 0 ? 1.0 : padded;
  }

  static double _getNiceGridInterval(double maxY) {
    final double base = (maxY <= 0 ? 1.0 : maxY) / 5.0;
    final double magnitude = _pow10((log10(base)).floor());
    final double residual = base / magnitude;
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

  static double log10(double x) => (x <= 0) ? 0.0 : (math.log(x) / math.ln10);
  static double _pow10(int exp) => math.pow(10, exp).toDouble();

  static String _formatYAxis(double value) {
    final double absVal = value.abs();
    if (absVal >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (absVal >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toInt().toString();
  }

  static String _formatValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  static int _computeXLabelInterval(int length) {
    if (length <= 10) return 1;
    if (length <= 20) return 2;
    if (length <= 40) return 4;
    return (length / 10).ceil();
  }
}


