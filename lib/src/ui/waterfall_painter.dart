import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../core/settings_model.dart';

class WaterfallPainter extends CustomPainter {
  final List<List<double>> fftHistory;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;
  final AppTheme theme;
  final double frequencySkew;

  WaterfallPainter({
    required this.fftHistory,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
    this.theme = AppTheme.frost,
    this.frequencySkew = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fftHistory.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final historyCount = fftHistory.length;
    final rowHeight = height / historyCount;

    final totalNyquist = sampleRate / 2;
    final double startNormalized = (minFreq / totalNyquist);
    final double endNormalized = (maxFreq / totalNyquist);
    final double range = endNormalized - startNormalized;
    const int binCount = 160;
    final barWidth = width / binCount;

    // Pre-calculate skew if needed
    final skewedIndices = Int32List(binCount);
    for (int j = 0; j < binCount; j++) {
      double t = j / binCount;
      if (frequencySkew != 1.0) {
        t = math.pow(t, frequencySkew).toDouble();
      }
      final double freqNorm = startNormalized + t * range;
      // Note: fftData length might vary if window size changes, but usually it's stable.
      // We'll calculate indices relative to a normalized factor.
      skewedIndices[j] = (freqNorm * 1e6).toInt(); // Use a high precision factor
    }

    const double logScale = 1.0 / 4.0;

    for (var i = 0; i < historyCount; i++) {
      final fftData = fftHistory[i];
      if (fftData.isEmpty) continue;

      for (var j = 0; j < binCount; j++) {
        final int dataIndex = (skewedIndices[j] * fftData.length ~/ 1e6).clamp(0, fftData.length - 1);

        final magnitude = fftData[dataIndex];
        // Use consistent scale with FftBarChartPainter
        final normalized = (math.log(magnitude + 1) * logScale).clamp(0.0, 1.1);

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
      case AppTheme.frost:
        return _getFrostColor(value);
      case AppTheme.magma:
        return _getMagmaColor(value);
      case AppTheme.gray:
        return _getGrayColor(value);
      case AppTheme.emerald:
        return _getEmeraldColor(value);
      case AppTheme.rainbow:
        return _getRainbowColor(value);
    }
  }

  Color _getFrostColor(double value) {
    if (value < 0.3) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF007AFF), value / 0.3)!;
    } else if (value < 0.7) {
      return Color.lerp(const Color(0xFF007AFF), const Color(0xFF5AC8FA), (value - 0.3) / 0.4)!;
    } else {
      return Color.lerp(const Color(0xFF5AC8FA), Colors.white, (value - 0.7) / 0.3)!;
    }
  }

  Color _getMagmaColor(double value) {
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

  Color _getGrayColor(double value) {
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

  Color _getRainbowColor(double value) {
    // Black -> Purple -> Blue -> Cyan -> Green -> Yellow -> Red -> White
    if (value < 0.1) {
      return Color.lerp(Colors.black, Colors.purple, value / 0.1)!;
    } else if (value < 0.25) {
      return Color.lerp(Colors.purple, Colors.blue, (value - 0.1) / 0.15)!;
    } else if (value < 0.4) {
      return Color.lerp(Colors.blue, Colors.cyan, (value - 0.25) / 0.15)!;
    } else if (value < 0.55) {
      return Color.lerp(Colors.cyan, Colors.green, (value - 0.4) / 0.15)!;
    } else if (value < 0.7) {
      return Color.lerp(Colors.green, Colors.yellow, (value - 0.55) / 0.15)!;
    } else if (value < 0.85) {
      return Color.lerp(Colors.yellow, Colors.red, (value - 0.7) / 0.15)!;
    } else {
      return Color.lerp(Colors.red, Colors.white, (value - 0.85) / 0.15)!;
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return true;
  }
}
