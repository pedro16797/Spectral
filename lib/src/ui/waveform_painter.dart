import 'package:flutter/material.dart';
import 'dart:typed_data';

class WaveformPainter extends CustomPainter {
  final Uint8List audioData;
  final Color color;

  WaveformPainter({required this.audioData, this.color = Colors.blue});

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    // We assume 16-bit PCM (2 bytes per sample)
    final sampleCount = audioData.length ~/ 2;
    if (sampleCount == 0) return;

    // To optimize performance, we can skip samples if there are too many to draw
    const maxSamplesToDraw = 1000;
    final skip = (sampleCount / maxSamplesToDraw).ceil();
    final step = width / (sampleCount / skip);

    for (var i = 0; i < sampleCount; i += skip) {
      // Convert two bytes to a 16-bit signed integer (Little Endian)
      final byteLow = audioData[i * 2];
      final byteHigh = audioData[i * 2 + 1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;

      // Normalize sample to [-1.0, 1.0]
      final normalizedSample = sample / 32768.0;
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
