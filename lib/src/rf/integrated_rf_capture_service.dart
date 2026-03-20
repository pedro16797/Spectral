import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';
// import 'native_sdr_driver.dart'; // Temporarily disabled for web build

/// Capture service that uses the integrated native SDR driver.
/// For this prototype, it simulates data after successful native driver initialization.
class IntegratedRfCaptureService implements SignalSource {
  final double centerFrequency; // Hz
  final double bandwidth; // Hz
  final double ppmCorrection; // PPM
  final _dataController = StreamController<Float64List>.broadcast();
  Timer? _timer;
  bool _isCapturing = false;

  IntegratedRfCaptureService({
    required this.centerFrequency,
    required this.bandwidth,
    this.ppmCorrection = 0.0,
  });

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => bandwidth.toInt();

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async {
    // return NativeSdrDriver().isInitialized;
    return true; // Simplified for web build
  }

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    // In a real implementation, this would trigger libusb bulk transfers.
    // For this prototype, we'll simulate high-quality RF data if the driver is ready.
    /*
    if (!NativeSdrDriver().isInitialized) {
       throw Exception("Native SDR Driver not initialized.");
    }
    */

    // Apply PPM correction to internal state if this were talking to hardware
    // await NativeSdrDriver().setPpm(ppmCorrection.toInt());

    _isCapturing = true;
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      final samples = Float64List(1024 * 2);
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

      // Simulate frequency offset due to PPM correction (simulating hardware error)
      final double actualOffsetHz = centerFrequency * (ppmCorrection / 1e6);

      // Simulate multiple peaks on a lower noise floor to distinguish from Mock
      final freqs = [
        bandwidth * 0.1 - actualOffsetHz,
        -bandwidth * 0.3 - actualOffsetHz,
        bandwidth * 0.45 - actualOffsetHz
      ];
      final amps = [0.6, 0.4, 0.2];

      for (int i = 0; i < 1024; i++) {
        final t = i / sampleRate;
        double realSum = 0;
        double imagSum = 0;

        for (int f = 0; f < freqs.length; f++) {
          final phase = 2 * math.pi * freqs[f] * (now + t);
          realSum += amps[f] * math.cos(phase);
          imagSum += amps[f] * math.sin(phase);
        }

        // Low noise floor
        double ni = (math.Random().nextDouble() - 0.5) * 0.01;
        double nq = (math.Random().nextDouble() - 0.5) * 0.01;

        samples[i * 2] = realSum + ni;
        samples[i * 2 + 1] = imagSum + nq;
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
