import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';

class RfCaptureService implements SignalSource {
  final _dataController = StreamController<Float64List>.broadcast();
  Timer? _timer;
  bool _isCapturing = false;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => 2048000; // 2.048 MHz typical for RTL-SDR

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;
    _isCapturing = true;

    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final samples = Float64List(1024 * 2); // 1024 I/Q pairs
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

      // Simulate some RF signals
      // A strong signal at +250kHz from center
      const freq1 = 250000.0;
      // A weaker signal at -500kHz from center
      const freq2 = -500000.0;

      for (int i = 0; i < 1024; i++) {
        final t = i / sampleRate;
        final phase1 = 2 * math.pi * freq1 * (now + t);
        final phase2 = 2 * math.pi * freq2 * (now + t);

        // Signal 1 (I/Q)
        double i1 = 0.5 * math.cos(phase1);
        double q1 = 0.5 * math.sin(phase1);

        // Signal 2 (I/Q)
        double i2 = 0.2 * math.cos(phase2);
        double q2 = 0.2 * math.sin(phase2);

        // Noise
        double ni = (math.Random().nextDouble() - 0.5) * 0.05;
        double nq = (math.Random().nextDouble() - 0.5) * 0.05;

        samples[i * 2] = i1 + i2 + ni;
        samples[i * 2 + 1] = q1 + q2 + nq;
      }
      _dataController.add(samples);
    });
  }

  @override
  Future<void> stopCapture() async {
    _timer?.cancel();
    _timer = null;
    _isCapturing = false;
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
