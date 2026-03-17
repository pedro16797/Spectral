import 'package:flutter/material.dart';
import 'dart:typed_data';

class WaveformPainter extends CustomPainter {
  final Float64List audioData;
  final Color color;

  WaveformPainter({required this.audioData, this.color = Colors.blue});

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    final sampleCount = audioData.length;
    if (sampleCount == 0) return;

    const maxSamplesToDraw = 800;
    final skip = (sampleCount / maxSamplesToDraw).ceil();
    final step = width / (sampleCount / skip);

    for (var i = 0; i < sampleCount; i += skip) {
      final normalizedSample = audioData[i];
      final x = (i / skip) * step;
      // Soften the wave for a liquid look
      final y = centerY + (normalizedSample * centerY * 0.9);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw main wave
    canvas.drawPath(path, paint);

    // Add a soft organic glow
    final glowPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.audioData != audioData;
  }
}
