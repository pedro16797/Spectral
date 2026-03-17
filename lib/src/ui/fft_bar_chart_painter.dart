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
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1);

    final width = size.width;
    final height = size.height;

    // Limit the number of bars to draw for performance
    const maxBars = 64;
    final binCount = fftData.length;
    final skip = (binCount / maxBars).ceil();
    final actualBarCount = (binCount / skip).floor();
    final barWidth = width / actualBarCount;

    for (var i = 0; i < actualBarCount; i++) {
      // Find the max magnitude in the bin range
      var maxMag = 0.0;
      for (var j = 0; j < skip; j++) {
        final index = i * skip + j;
        if (index < binCount) {
          maxMag = math.max(maxMag, fftData[index]);
        }
      }

      // Normalize magnitude for display.
      // FFT magnitudes can be large, so we use a log-like scaling or a fixed range.
      // For MVP, we'll use a simple scaling and cap it.
      final normalizedHeight = (math.log(maxMag + 1) / 5.0).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * height;

      final x = i * barWidth;
      final y = height - barHeight;

      final rect = Rect.fromLTWH(x, y, barWidth - 1, barHeight);
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color,
          color.withOpacity(0.1),
        ],
      ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
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
