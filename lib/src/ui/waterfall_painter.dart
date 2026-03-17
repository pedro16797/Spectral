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
          ..style = PaintingStyle.fill;

        final x = j * barWidth;
        // i=0 is the oldest or newest?
        // If we want newest at top, then i=0 should be newest.
        final y = i * rowHeight;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.5, rowHeight + 0.5),
          paint,
        );
      }
    }
  }

  Color _getColorForNormalizedValue(double value) {
    // Simple heatmap: Black -> Blue -> Cyan -> Green -> Yellow -> Red
    if (value < 0.2) {
      return Color.lerp(Colors.black, Colors.blue, value * 5)!;
    } else if (value < 0.4) {
      return Color.lerp(Colors.blue, Colors.cyan, (value - 0.2) * 5)!;
    } else if (value < 0.6) {
      return Color.lerp(Colors.cyan, Colors.green, (value - 0.4) * 5)!;
    } else if (value < 0.8) {
      return Color.lerp(Colors.green, Colors.yellow, (value - 0.6) * 5)!;
    } else {
      return Color.lerp(Colors.yellow, Colors.red, (value - 0.8) * 5)!;
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
