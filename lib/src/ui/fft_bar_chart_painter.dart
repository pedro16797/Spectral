import 'package:flutter/material.dart';
import 'dart:math' as math;

class FftBarChartPainter extends CustomPainter {
  final List<double> fftData;
  final Color color;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;

  FftBarChartPainter({
    required this.fftData,
    this.color = Colors.blue,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fftData.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Determine indices in fftData based on frequency range
    // fftData represents frequencies from 0 to sampleRate/2
    final totalNyquist = sampleRate / 2;
    final startIndex = ((minFreq / totalNyquist) * fftData.length).floor().clamp(0, fftData.length - 1);
    final endIndex = ((maxFreq / totalNyquist) * fftData.length).ceil().clamp(startIndex + 1, fftData.length);

    final visibleData = fftData.sublist(startIndex, endIndex);
    if (visibleData.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const maxBars = 80;
    final binCount = visibleData.length;
    final skip = (binCount / maxBars).ceil();
    final actualBarCount = (binCount / skip).floor();
    final barWidth = width / actualBarCount;

    for (var i = 0; i < actualBarCount; i++) {
      var maxMag = 0.0;
      for (var j = 0; j < skip; j++) {
        final index = i * skip + j;
        if (index < binCount) {
          maxMag = math.max(maxMag, visibleData[index]);
        }
      }

      final normalizedHeight = (math.log(maxMag + 1) / 4.5).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * (height - 20); // Leave room for labels

      final x = i * barWidth;
      final y = (height - 20) - barHeight;

      final rect = Rect.fromLTWH(x + 1, y, barWidth - 2, barHeight);

      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.6 * normalizedHeight + 0.2),
          color.withOpacity(0.05),
        ],
      ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        paint,
      );
    }

    // Draw Frequency Labels
    _drawLabels(canvas, size);
  }

  void _drawLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: color.withOpacity(0.4),
      fontSize: 8,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    );

    final labelCount = 5;
    for (var i = 0; i < labelCount; i++) {
      final ratio = i / (labelCount - 1);
      final freq = minFreq + (maxFreq - minFreq) * ratio;
      final x = ratio * size.width;

      final label = freq >= 1000 ? "${(freq / 1000).toStringAsFixed(1)}k" : "${freq.toInt()}";

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Adjust x to keep text within bounds
      double drawX = x - (textPainter.width / 2);
      if (i == 0) drawX = 0;
      if (i == labelCount - 1) drawX = size.width - textPainter.width;

      textPainter.paint(canvas, Offset(drawX, size.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant FftBarChartPainter oldDelegate) {
    return oldDelegate.fftData != fftData ||
           oldDelegate.minFreq != minFreq ||
           oldDelegate.maxFreq != maxFreq;
  }
}
