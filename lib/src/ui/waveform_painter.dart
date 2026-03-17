import 'package:flutter/material.dart';
import 'dart:typed_data';

class WaveformPainter extends CustomPainter {
  final Float64List audioData;
  final List<Float64List> history;
  final Color color;

  WaveformPainter({
    required this.audioData,
    this.history = const [],
    this.color = Colors.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty && history.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    // Draw history (ghosts)
    for (var i = 0; i < history.length; i++) {
      final ghostData = history[i];
      final opacity = (1.0 - (i + 1) / (history.length + 1)) * 0.3;
      final ghostPaint = Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      _drawWave(canvas, ghostData, ghostPaint, width, height, centerY);
    }

    // Draw main wave
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    _drawWave(canvas, audioData, paint, width, height, centerY);

    // Add a soft organic glow to main wave
    if (audioData.isNotEmpty) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.2)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      _drawWave(canvas, audioData, glowPaint, width, height, centerY);
    }
  }

  void _drawWave(Canvas canvas, Float64List data, Paint paint, double width, double height, double centerY) {
    if (data.isEmpty) return;
    final path = Path();

    final sampleCount = data.length;
    const maxSamplesToDraw = 800;
    final skip = (sampleCount / maxSamplesToDraw).ceil();
    final actualPoints = (sampleCount / skip).floor();
    final step = width / (actualPoints - 1);

    for (var i = 0; i < sampleCount; i += skip) {
      final normalizedSample = data[i];
      final x = (i / skip) * step;
      final y = centerY + (normalizedSample * centerY * 0.85);

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
    return true; // Simple for now given history changes
  }
}
