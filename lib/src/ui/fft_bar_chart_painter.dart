import 'package:flutter/material.dart';
import 'dart:math' as math;

class FftBarChartPainter extends CustomPainter {
  final List<double> fftData;
  final Color color;

  FftBarChartPainter({required this.fftData, this.color = Colors.blue});

  @override
  void paint(Canvas canvas, Size size) {
    if (fftData.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5);

    final width = size.width;
    final height = size.height;

    const maxBars = 80;
    final binCount = fftData.length;
    final skip = (binCount / maxBars).ceil();
    final actualBarCount = (binCount / skip).floor();
    final barWidth = width / actualBarCount;

    for (var i = 0; i < actualBarCount; i++) {
      var maxMag = 0.0;
      for (var j = 0; j < skip; j++) {
        final index = i * skip + j;
        if (index < binCount) {
          maxMag = math.max(maxMag, fftData[index]);
        }
      }

      final normalizedHeight = (math.log(maxMag + 1) / 4.5).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * height;

      final x = i * barWidth;
      final y = height - barHeight;

      final rect = Rect.fromLTWH(x + 1, y, barWidth - 2, barHeight);

      // Floating light effect: Higher bars are more opaque
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.6 * normalizedHeight + 0.2),
          color.withOpacity(0.05),
        ],
      ).createShader(rect);

      // Draw as a rounded line/bar rather than a rigid box
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FftBarChartPainter oldDelegate) {
    return oldDelegate.fftData != fftData;
  }
}
