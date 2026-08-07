import 'package:flutter/material.dart';
import '../core/settings_model.dart';
import '../core/spectral_theme.dart';
import '../utils/spectrum_bins.dart';

class WaterfallPainter extends CustomPainter {
  final List<List<double>> fftHistory;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;
  final AppTheme theme;
  final double frequencySkew;

  /// Full span the FFT data covers. Null means a real (audio) spectrum running
  /// 0..Nyquist; a complex RF spectrum must pass its centre ± sampleRate/2,
  /// because absolute RF frequencies mean nothing against Nyquist alone.
  final double? bandStart;
  final double? bandEnd;

  WaterfallPainter({
    required this.fftHistory,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
    this.theme = AppTheme.frost,
    this.frequencySkew = 1.0,
    this.bandStart,
    this.bandEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fftHistory.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final historyCount = fftHistory.length;
    final rowHeight = height / historyCount;

    const int binCount = 160;
    final barWidth = width / binCount;

    final mapper = SpectrumBinMapper(
      columnCount: binCount,
      viewStartHz: minFreq,
      viewEndHz: maxFreq,
      bandStartHz: bandStart ?? 0,
      bandEndHz: bandEnd ?? sampleRate / 2,
      frequencySkew: frequencySkew,
    );

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
        // Peak across the covered bins, so a narrow carrier cannot fall
        // between columns and vanish.
        final normalized = normalizeMagnitude(mapper.peak(fftData, j));

        if (normalized < 0.05) continue;

        paint.color = SpectralTheme.waterfallColor(theme, normalized).withValues(alpha: ageFade * 0.4);

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
