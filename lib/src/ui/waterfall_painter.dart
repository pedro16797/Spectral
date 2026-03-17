import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaterfallPainter extends CustomPainter {
  final List<List<double>> fftHistory;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;

  WaterfallPainter({
    required this.fftHistory,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fftHistory.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final historyCount = fftHistory.length;
    final rowHeight = height / historyCount;

    final totalNyquist = sampleRate / 2;

    for (var i = 0; i < historyCount; i++) {
      final fftData = fftHistory[i];
      if (fftData.isEmpty) continue;

      // Filter based on frequency range
      final startIndex = ((minFreq / totalNyquist) * fftData.length).floor().clamp(0, fftData.length - 1);
      final endIndex = ((maxFreq / totalNyquist) * fftData.length).ceil().clamp(startIndex + 1, fftData.length);

      final visibleData = fftData.sublist(startIndex, endIndex);
      if (visibleData.isEmpty) continue;

      final binCount = visibleData.length;
      final barWidth = width / binCount;

      for (var j = 0; j < binCount; j++) {
        final magnitude = visibleData[j];
        final normalized = (math.log(magnitude + 1) / 5.0).clamp(0.0, 1.0);

        if (normalized < 0.05) continue;

        final ageFade = 1.0 - (i / historyCount);

        final paint = Paint()
          ..color = _getLiquidColor(normalized).withOpacity(ageFade * 0.4)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

        final x = j * barWidth;
        final y = i * rowHeight;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.5, rowHeight + 0.5),
          paint,
        );
      }
    }
  }

  Color _getLiquidColor(double value) {
    // Liquid minimalism palette: Deep blue -> Bright Azure -> Soft White
    if (value < 0.33) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF007AFF), value * 3)!;
    } else if (value < 0.66) {
      return Color.lerp(const Color(0xFF007AFF), const Color(0xFF5AC8FA), (value - 0.33) * 3)!;
    } else {
      return Color.lerp(const Color(0xFF5AC8FA), Colors.white, (value - 0.66) * 3)!;
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return true;
  }
}
