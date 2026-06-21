import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../core/settings_model.dart';
import '../core/spectral_theme.dart';
import '../utils/frequency_scale.dart';

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
      final double t = FrequencyScale.toData(j / binCount, frequencySkew);
      final double freqNorm = startNormalized + t * range;
      // Note: fftData length might vary if window size changes, but usually it's stable.
      // We'll calculate indices relative to a normalized factor.
      skewedIndices[j] = (freqNorm * 1e6).toInt(); // Use a high precision factor
    }

    const double logScale = 1.0 / 4.0;

    // Reuse a single Paint across all cells; only the color changes per cell.
    // Allocating a Paint per cell would churn thousands of objects per frame.
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    for (var i = 0; i < historyCount; i++) {
      final fftData = fftHistory[i];
      if (fftData.isEmpty) continue;

      final ageFade = 1.0 - (i / historyCount);
      final y = i * rowHeight;

      for (var j = 0; j < binCount; j++) {
        final int dataIndex = (skewedIndices[j] * fftData.length ~/ 1e6).clamp(0, fftData.length - 1);

        final magnitude = fftData[dataIndex];
        // Use consistent scale with FftBarChartPainter
        final normalized = (math.log(magnitude + 1) * logScale).clamp(0.0, 1.1);

        if (normalized < 0.05) continue;

        paint.color = SpectralTheme.waterfallColor(theme, normalized).withOpacity(ageFade * 0.4);

        final x = j * barWidth;

        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth + 0.6, rowHeight + 0.6),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) {
    return true;
  }
}
