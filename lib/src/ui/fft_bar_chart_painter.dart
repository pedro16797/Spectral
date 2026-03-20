import 'package:flutter/material.dart';
import 'dart:math' as math;

class FftBarChartPainter extends CustomPainter {
  final List<double> fftData;
  final List<double>? peakHoldData;
  final List<double> markers; // Frequencies in Hz
  final bool showHarmonics;
  final double? fundamentalFreq; // Hz
  final double? snrValue; // dB
  final Color color;
  final double minFreq;
  final double maxFreq;
  final int sampleRate;
  final double frequencySkew;

  FftBarChartPainter({
    required this.fftData,
    this.peakHoldData,
    this.markers = const [],
    this.showHarmonics = false,
    this.fundamentalFreq,
    this.snrValue,
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
    final totalNyquist = sampleRate / 2;
    final double startNormalized = (minFreq / totalNyquist);
    final double endNormalized = (maxFreq / totalNyquist);
    final double range = endNormalized - startNormalized;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const actualBarCount = 120;
    final barWidth = width / actualBarCount;
    final double spacing = barWidth > 15 ? 4.0 : (barWidth > 8 ? 2.0 : (barWidth > 4 ? 1.0 : 0.0));
    final double actualWidth = math.max(1.0, barWidth - spacing);

    // Draw bars
    for (var i = 0; i < actualBarCount; i++) {
      double t = i / actualBarCount;
      if (frequencySkew != 1.0) {
        t = math.pow(t, frequencySkew).toDouble();
      }

      final double freqNorm = startNormalized + t * range;
      final int dataIndex = (freqNorm * fftData.length).floor().clamp(0, fftData.length - 1);

      final maxMag = fftData[dataIndex];
      final normalizedHeight = (math.log(maxMag + 1) / 4.5).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * (height - 20);

      final x = i * barWidth + (spacing / 2);
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

    // Draw Peak Hold
    if (peakHoldData != null && peakHoldData!.length == fftData.length) {
      final peakPaint = Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final path = Path();
      bool first = true;

      for (var i = 0; i < actualBarCount; i++) {
        double t = i / actualBarCount;
        if (frequencySkew != 1.0) {
          t = math.pow(t, frequencySkew).toDouble();
        }
        final double freqNorm = startNormalized + t * range;
        final int dataIndex = (freqNorm * peakHoldData!.length).floor().clamp(0, peakHoldData!.length - 1);

        final mag = peakHoldData![dataIndex];
        final normalizedHeight = (math.log(mag + 1) / 4.5).clamp(0.0, 1.0);
        final y = (height - 20) - (normalizedHeight * (height - 20));
        final x = i * barWidth + barWidth / 2;

        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, peakPaint);
    }

    // Draw Markers
    for (final markerFreq in markers) {
      if (markerFreq < minFreq || markerFreq > maxFreq) continue;

      final t = (markerFreq - minFreq) / (maxFreq - minFreq);
      // Map back from frequency to screen space accounting for skew
      double screenT = t;
      if (frequencySkew != 1.0) {
        screenT = math.pow(t, 1.0 / frequencySkew).toDouble();
      }
      final x = screenT * width;

      final markerPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(Offset(x, 0), Offset(x, height - 20), markerPaint);

      // Label
      final label = markerFreq >= 1000 ? "${(markerFreq / 1000).toStringAsFixed(2)}k" : "${markerFreq.toInt()}";
      _drawText(canvas, label, Offset(x + 4, 10), Colors.white70);
    }

    // Draw Harmonics
    if (showHarmonics && fundamentalFreq != null) {
      final harmonicPaint = Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (int h = 2; h <= 5; h++) {
        final hFreq = fundamentalFreq! * h;
        if (hFreq < minFreq || hFreq > maxFreq) continue;

        final t = (hFreq - minFreq) / (maxFreq - minFreq);
        double screenT = t;
        if (frequencySkew != 1.0) {
          screenT = math.pow(t, 1.0 / frequencySkew).toDouble();
        }
        final x = screenT * width;

        // Dashed line simulation
        for (double dy = 0; dy < height - 20; dy += 10) {
          canvas.drawLine(Offset(x, dy), Offset(x, dy + 5), harmonicPaint);
        }
        _drawText(canvas, "${h}H", Offset(x + 4, height - 35), color.withOpacity(0.7));
      }
    }

    // Draw SNR
    if (snrValue != null) {
      _drawText(
        canvas,
        "SNR: ${snrValue!.toStringAsFixed(1)} dB",
        const Offset(10, 10),
        color.withOpacity(0.8),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      );
    }

    // Draw Frequency Labels
    _drawLabels(canvas, size);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, {double fontSize = 8, FontWeight fontWeight = FontWeight.normal}) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
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

    for (var i = 0; i < labelCount; i++) {
      final ratio = i / (labelCount - 1);
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

      if (i > 0 && label == lastLabelText && maxFreq - minFreq < 1) continue;

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      double drawX = x - (textPainter.width / 2);
      if (i == 0) drawX = 0;
      if (i == labelCount - 1) drawX = size.width - textPainter.width;

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
           oldDelegate.peakHoldData != peakHoldData ||
           oldDelegate.markers != markers ||
           oldDelegate.showHarmonics != showHarmonics ||
           oldDelegate.fundamentalFreq != fundamentalFreq ||
           oldDelegate.snrValue != snrValue ||
           oldDelegate.minFreq != minFreq ||
           oldDelegate.maxFreq != maxFreq ||
           oldDelegate.color != color ||
           oldDelegate.frequencySkew != frequencySkew;
  }
}
