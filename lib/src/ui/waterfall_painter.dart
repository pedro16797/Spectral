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
      final barWidth = width / binCount;

      for (var j = 0; j < binCount; j++) {
        final magnitude = fftData[j];
        final normalized = (math.log(magnitude + 1) / 5.0).clamp(0.0, 1.0);

        if (normalized < 0.05) continue;

        // Fading intensity based on age (i)
        final ageFade = 1.0 - (i / historyCount);

        final paint = Paint()
          ..color = _getColorForNormalizedValue(normalized).withOpacity(ageFade * 0.5)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

        final x = j * barWidth;
        final y = i * rowHeight;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.1, rowHeight + 0.1),
          paint,
        );
      }
    }
  }

  Color _getColorForNormalizedValue(double value) {
    // Holographic Heatmap
    if (value < 0.25) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF00B2FF), value * 4)!;
    } else if (value < 0.5) {
      return Color.lerp(const Color(0xFF00B2FF), const Color(0xFF00FF9F), (value - 0.25) * 4)!;
    } else if (value < 0.75) {
      return Color.lerp(const Color(0xFF00FF9F), const Color(0xFFE5FF00), (value - 0.5) * 4)!;
    } else {
      return Color.lerp(const Color(0xFFE5FF00), Colors.white, (value - 0.75) * 4)!;
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return true;
  }
}
