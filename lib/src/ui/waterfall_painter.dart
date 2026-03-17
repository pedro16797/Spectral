import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaterfallPainter extends CustomPainter {
  final List<List<double>> fftHistory;

  WaterfallPainter({required this.fftHistory});

  @override
  void paint(Canvas canvas, Size size) {
    if (fftHistory.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final historyCount = fftHistory.length;
    final rowHeight = height / historyCount;

    for (var i = 0; i < historyCount; i++) {
      final fftData = fftHistory[i];
      if (fftData.isEmpty) continue;

      final binCount = fftData.length;
      // For performance, we might want to limit binCount or draw fewer rects
      // but let's start simple.
      final barWidth = width / binCount;

      for (var j = 0; j < binCount; j++) {
        final magnitude = fftData[j];
        // Normalize magnitude for display.
        final normalized = (math.log(magnitude + 1) / 5.0).clamp(0.0, 1.0);

        if (normalized < 0.05) continue; // Optimization: skip very low values

        final paint = Paint()
          ..color = _getColorForNormalizedValue(normalized)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

        final x = j * barWidth;
        // i=0 is the oldest or newest?
        // If we want newest at top, then i=0 should be newest.
        final y = i * rowHeight;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.2, rowHeight + 0.2),
          paint,
        );
      }
    }
  }

  Color _getColorForNormalizedValue(double value) {
    // Sci-fi heatmap: Black -> Dark Blue -> Cyan -> Electric Green -> Neon Yellow
    if (value < 0.25) {
      return Color.lerp(const Color(0xFF050505), const Color(0xFF001A33), value * 4)!;
    } else if (value < 0.5) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF00B2FF), (value - 0.25) * 4)!;
    } else if (value < 0.75) {
      return Color.lerp(const Color(0xFF00B2FF), const Color(0xFF00FF9F), (value - 0.5) * 4)!;
    } else {
      return Color.lerp(const Color(0xFF00FF9F), const Color(0xFFE5FF00), (value - 0.75) * 4)!;
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    // In a real app, we might check if the content changed,
    // but for now, we'll assume it changes if the reference is different or
    // simply return true since it's a real-time visualization.
    return true;
  }
}
