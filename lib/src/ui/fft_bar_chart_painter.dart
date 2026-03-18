import 'package:flutter/material.dart';
import 'dart:math' as math;

class FftBarChartPainter extends CustomPainter {
  final List<double> fftData;
  final Color color;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;
  final double frequencySkew;

  FftBarChartPainter({
    required this.fftData,
    this.color = Colors.blue,
    this.minFreq = 0,
    this.maxFreq = 22050,
    this.sampleRate = 44100,
    this.frequencySkew = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fftData.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Determine indices in fftData based on frequency range
    // fftData represents frequencies from 0 to sampleRate/2
    final totalNyquist = sampleRate / 2;
    final double startNormalized = (minFreq / totalNyquist);
    final double endNormalized = (maxFreq / totalNyquist);
    final double range = endNormalized - startNormalized;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const actualBarCount = 120;

    // Ensure the bars fill the available width
    final barWidth = width / actualBarCount;
    const offset = 0.0;

    // Dynamic spacing based on bar width
    final double spacing = barWidth > 15 ? 4.0 : (barWidth > 8 ? 2.0 : (barWidth > 4 ? 1.0 : 0.0));
    final double actualWidth = math.max(1.0, barWidth - spacing);

    for (var i = 0; i < actualBarCount; i++) {
      // Apply skew to the frequency axis
      double t = i / actualBarCount;
      if (frequencySkew != 1.0) {
        t = math.pow(t, frequencySkew).toDouble();
      }

      final double freqNorm = startNormalized + t * range;
      final int dataIndex = (freqNorm * fftData.length).floor().clamp(0, fftData.length - 1);

      final maxMag = fftData[dataIndex];

      final normalizedHeight = (math.log(maxMag + 1) / 4.5).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * (height - 20); // Leave room for labels

      final x = offset + i * barWidth + (spacing / 2);
      final y = (height - 20) - barHeight;

      final rect = Rect.fromLTWH(x, y, actualWidth, barHeight);

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
    double lastLabelEndX = -20.0;
    String lastLabelText = "";

    final totalNyquist = sampleRate / 2;
    final double startNormalized = (minFreq / totalNyquist);
    final double endNormalized = (maxFreq / totalNyquist);
    final double range = endNormalized - startNormalized;

    for (var i = 0; i < labelCount; i++) {
      final ratio = i / (labelCount - 1);

      // Apply inverse skew to find the frequency at this screen position ratio
      double t = ratio;
      if (frequencySkew != 1.0) {
        t = math.pow(t, frequencySkew).toDouble();
      }

      final freq = minFreq + (maxFreq - minFreq) * t;
      final x = ratio * size.width;

      String label;
      if (maxFreq - minFreq < 100) {
        label = freq >= 1000 ? "${(freq / 1000).toStringAsFixed(3)}k" : freq.toStringAsFixed(1);
      } else {
        label = freq >= 1000 ? "${(freq / 1000).toStringAsFixed(1)}k" : "${freq.toInt()}";
      }

      // Skip redundant labels if they are identical to the last one (unless it's the first)
      if (i > 0 && label == lastLabelText && maxFreq - minFreq < 1) continue;

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Adjust x to keep text within bounds
      double drawX = x - (textPainter.width / 2);
      if (i == 0) drawX = 0;
      if (i == labelCount - 1) drawX = size.width - textPainter.width;

      // Only paint if it doesn't overlap with the previous label
      if (drawX > lastLabelEndX + 5 || i == 0) {
        textPainter.paint(canvas, Offset(drawX, size.height - 15));
        lastLabelEndX = drawX + textPainter.width;
        lastLabelText = label;
      }
    }
  }

  @override
  bool shouldRepaint(covariant FftBarChartPainter oldDelegate) {
    return oldDelegate.fftData != fftData ||
           oldDelegate.minFreq != minFreq ||
           oldDelegate.maxFreq != maxFreq ||
           oldDelegate.color != color;
  }
}
