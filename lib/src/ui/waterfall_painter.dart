import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../core/settings_model.dart';

class WaterfallPainter extends CustomPainter {
  final List<List<double>> fftHistory;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;
  final AppTheme theme;

  WaterfallPainter({
    required this.fftHistory,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
    this.theme = AppTheme.liquidBlue,
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

      final rawBinCount = visibleData.length;
      const int maxBins = 160;
      final binCount = math.min(rawBinCount, maxBins);
      final skip = (rawBinCount / binCount).floor().clamp(1, rawBinCount);
      final barWidth = width / binCount;

      for (var j = 0; j < binCount; j++) {
        final dataIndex = (j * skip).clamp(0, rawBinCount - 1);
        final magnitude = visibleData[dataIndex];
        // Use consistent scale with FftBarChartPainter
        final normalized = (math.log(magnitude + 1) / 4.0).clamp(0.0, 1.1);

        if (normalized < 0.05) continue;

        final ageFade = 1.0 - (i / historyCount);

        final paint = Paint()
          ..color = _getThemeColor(normalized, theme).withOpacity(ageFade * 0.4)
          ..style = PaintingStyle.fill
          ..isAntiAlias = false;

        final x = j * barWidth;
        final y = i * rowHeight;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.6, rowHeight + 0.6),
          paint,
        );
      }
    }
  }

  Color _getThemeColor(double value, AppTheme theme) {
    switch (theme) {
      case AppTheme.liquidBlue:
        return _getLiquidBlueColor(value);
      case AppTheme.inferno:
        return _getInfernoColor(value);
      case AppTheme.monochrome:
        return _getMonochromeColor(value);
      case AppTheme.emerald:
        return _getEmeraldColor(value);
    }
  }

  Color _getLiquidBlueColor(double value) {
    if (value < 0.3) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF007AFF), value / 0.3)!;
    } else if (value < 0.7) {
      return Color.lerp(const Color(0xFF007AFF), const Color(0xFF5AC8FA), (value - 0.3) / 0.4)!;
    } else {
      return Color.lerp(const Color(0xFF5AC8FA), Colors.white, (value - 0.7) / 0.3)!;
    }
  }

  Color _getInfernoColor(double value) {
    if (value < 0.2) {
      return Color.lerp(const Color(0xFF000000), const Color(0xFF7D0000), value / 0.2)!;
    } else if (value < 0.5) {
      return Color.lerp(const Color(0xFF7D0000), const Color(0xFFFF4500), (value - 0.2) / 0.3)!;
    } else if (value < 0.8) {
      return Color.lerp(const Color(0xFFFF4500), const Color(0xFFFFD700), (value - 0.5) / 0.3)!;
    } else {
      return Color.lerp(const Color(0xFFFFD700), Colors.white, (value - 0.8) / 0.2)!;
    }
  }

  Color _getMonochromeColor(double value) {
    return Color.lerp(Colors.black, Colors.white, value)!;
  }

  Color _getEmeraldColor(double value) {
    if (value < 0.3) {
      return Color.lerp(const Color(0xFF001A00), const Color(0xFF00C853), value / 0.3)!;
    } else if (value < 0.7) {
      return Color.lerp(const Color(0xFF00C853), const Color(0xFF69F0AE), (value - 0.3) / 0.4)!;
    } else {
      return Color.lerp(const Color(0xFF69F0AE), Colors.white, (value - 0.7) / 0.3)!;
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return true;
  }
}
