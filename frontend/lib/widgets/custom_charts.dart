import 'dart:math' as math;
import 'package:flutter/material.dart';

class CustomLineChart extends StatelessWidget {
  final List<double> dataPoints;
  final List<String> labels;
  final Color lineColor;
  final Color glowColor;

  const CustomLineChart({
    super.key,
    required this.dataPoints,
    required this.labels,
    this.lineColor = const Color(0xFF2962FF),
    this.glowColor = const Color(0x332962FF),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _LineChartPainter(
              dataPoints: dataPoints,
              lineColor: lineColor,
              glowColor: glowColor,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels.map((label) {
            return Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> dataPoints;
  final Color lineColor;
  final Color glowColor;

  _LineChartPainter({
    required this.dataPoints,
    required this.lineColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final double width = size.width;
    final double height = size.height;
    final double stepX = width / (dataPoints.length - 1);
    
    final double maxVal = dataPoints.reduce(math.max);
    final double minVal = dataPoints.reduce(math.min);
    final double range = (maxVal - minVal) == 0 ? 1 : (maxVal - minVal);

    final List<Offset> points = [];
    for (int i = 0; i < dataPoints.length; i++) {
      final double x = i * stepX;
      final double normalizedY = (dataPoints[i] - minVal) / range;
      // Invert Y coordinate since Canvas (0,0) is top-left
      final double y = height - (normalizedY * height * 0.7 + height * 0.15);
      points.add(Offset(x, y));
    }

    // 1. Draw glowing background fill
    final Path fillPath = Path();
    fillPath.moveTo(0, height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(width, height);
    fillPath.close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [glowColor, Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(fillPath, fillPaint);

    // 2. Draw glowing line
    final Paint glowLinePaint = Paint()
      ..color = lineColor.withOpacity(0.3)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    final Path linePath = Path();
    linePath.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(linePath, glowLinePaint);

    // 3. Draw main sharp line
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(linePath, linePaint);

    // 4. Draw glowing data point indicator circles
    final Paint pointGlowPaint = Paint()
      ..color = lineColor.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    final Paint pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 6.0, pointGlowPaint);
      canvas.drawCircle(point, 3.0, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CustomBarChart extends StatelessWidget {
  final List<double> dataPoints;
  final List<String> labels;
  final Color barColor;

  const CustomBarChart({
    super.key,
    required this.dataPoints,
    required this.labels,
    this.barColor = const Color(0xFFFF1744),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final double height = constraints.maxHeight;
              final double barWidth = (width / dataPoints.length) * 0.6;
              final double spacing = (width / dataPoints.length) * 0.4;
              
              final double maxVal = dataPoints.reduce(math.max);
              final double range = maxVal == 0 ? 1 : maxVal;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(dataPoints.length, (index) {
                  final double val = dataPoints[index];
                  final double barHeight = (val / range) * height * 0.85;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: barWidth,
                        height: math.max(barHeight, 4.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [barColor, barColor.withOpacity(0.3)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: barColor.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[index],
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}
