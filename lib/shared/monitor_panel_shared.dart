import 'dart:math' as math;

import 'package:flutter/material.dart';

String formatMonitorValue(dynamic value) {
  if (value == null) return '--';
  if (value is double) return value.toStringAsFixed(2);
  if (value is int) return value.toString();
  return value.toString();
}

double? toMonitorDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<double> toMonitorDoubleList(dynamic value) {
  if (value is! List) return [];
  return value.map((item) => toMonitorDouble(item) ?? 0.0).toList();
}

class SparklinePainter extends CustomPainter {
  final List<double> series;
  final Color color;

  SparklinePainter({required this.series, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;

    final minVal = series.reduce(math.min);
    final maxVal = series.reduce(math.max);
    final range = maxVal - minVal;
    if (range == 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final x = i / (series.length - 1) * size.width;
      final y = (1 - (series[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return series != oldDelegate.series || color != oldDelegate.color;
  }
}
