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
      ..strokeWidth = 2.0
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

    // To optimize performance, we can skip samples if there are too many to draw
    const maxSamplesToDraw = 1000;
    final skip = (sampleCount / maxSamplesToDraw).ceil();
    final step = width / (sampleCount / skip);

    for (var i = 0; i < sampleCount; i += skip) {
      final normalizedSample = audioData[i];
      final x = (i / skip) * step;
      final y = centerY + (normalizedSample * centerY);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.audioData != audioData;
  }
}
