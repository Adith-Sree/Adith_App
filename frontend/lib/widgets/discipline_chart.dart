// lib/widgets/discipline_chart.dart
//
// A live fl_chart LineChart that plots the user's cumulative discipline score
// over the last 7 days. Powered exclusively by real data from the backend.
//
// - If the database is empty → 7 data points all at 0 (flat line at bottom)
// - Positive trend → line rises with blue glow
// - Touch any point to see the exact score for that day

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DisciplineLineChart extends StatefulWidget {
  /// 7 cumulative score values: index 0 = 6 days ago, index 6 = today
  final List<double> dataPoints;

  const DisciplineLineChart({super.key, required this.dataPoints});

  @override
  State<DisciplineLineChart> createState() => _DisciplineLineChartState();
}

class _DisciplineLineChartState extends State<DisciplineLineChart> {
  int? _touchedIndex;

  // Compute the 7 day-of-week labels ending today
  List<String> get _dayLabels {
    const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now().weekday; // 1=Mon … 7=Sun
    return List.generate(7, (i) {
      final dayIndex = (today - 6 + i) % 7; // 0-indexed, wraps correctly
      return short[dayIndex < 0 ? dayIndex + 7 : dayIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.dataPoints;

    // Guard: ensure exactly 7 points
    final safePoints = List.generate(7, (i) => i < points.length ? points[i] : 0.0);

    // Y-axis bounds with padding so the line never hugs the top/bottom
    final maxY = safePoints.reduce((a, b) => a > b ? a : b);
    final minY = safePoints.reduce((a, b) => a < b ? a : b);
    final yPadding = maxY == minY ? 10.0 : (maxY - minY) * 0.2;
    final yMax = (maxY + yPadding).ceilToDouble();
    final yMin = (minY - yPadding).floorToDouble().clamp(double.negativeInfinity, 0.0).toDouble();

    final spots = List.generate(
      7,
      (i) => FlSpot(i.toDouble(), safePoints[i]),
    );

    final labels = _dayLabels;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: yMin,
        maxY: yMax == 0 ? 10.0 : yMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY == 0 ? 5.0 : (yMax / 4).clamp(1.0, double.infinity).toDouble(),
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          // Left Y-axis labels
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: maxY == 0 ? 5.0 : (yMax / 4).clamp(1.0, double.infinity).toDouble(),
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
          // Bottom X-axis day labels
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                final isToday = i == 6;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: isToday
                          ? const Color(0xFF2962FF)
                          : Colors.white38,
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions || response == null) {
              if (mounted) setState(() => _touchedIndex = null);
              return;
            }
            final idx = response.lineBarSpots?.first.spotIndex;
            if (mounted) setState(() => _touchedIndex = idx);
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1A2E),
            tooltipRoundedRadius: 8,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '${s.y.toInt()} pts',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: const Color(0xFF2962FF),
            barWidth: 2.5,
            isStrokeCapRound: true,
            // Gradient fill under the line
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2962FF).withValues(alpha: 0.25),
                  const Color(0xFF2962FF).withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            // Dot styling — highlighted on touch
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                final isTouched = index == _touchedIndex;
                return FlDotCirclePainter(
                  radius: isTouched ? 5.5 : 3.0,
                  color: isTouched ? Colors.white : const Color(0xFF2962FF),
                  strokeWidth: isTouched ? 2 : 1.5,
                  strokeColor: const Color(0xFF2962FF),
                );
              },
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }
}
