import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';
import 'native_sdr_driver.dart';

/// Capture service for the integrated (native USB) SDR path.
///
/// The native RTL2832U driver is experimental and does not yet stream real
/// samples (see `NativeSdrDriverDelegate` and `rtl2832u.dart`), so this
/// currently emits a simulated multi-tone signal once the driver reports
/// ready. For real hardware today, use the rtl_tcp source with a bridge.
class IntegratedRfCaptureService implements SignalSource {
  final double centerFrequency; // Hz
  final double bandwidth; // Hz
  final double ppmCorrection; // PPM
  final _dataController = StreamController<Float64List>.broadcast();
  final math.Random _rng = math.Random();
  Timer? _timer;
  bool _isCapturing = false;
  int _sampleIndex = 0;

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
    return NativeSdrDriver().isInitialized;
  }

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    // In a real implementation, this would trigger libusb bulk transfers.
    // For this prototype, we'll simulate high-quality RF data if the driver is ready.
    if (!NativeSdrDriver().isInitialized) {
       throw Exception("Native SDR Driver not initialized.");
    }

    // Apply PPM correction to internal state if this were talking to hardware
    await NativeSdrDriver().setPpm(ppmCorrection.toInt());

    _isCapturing = true;
    _sampleIndex = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      final samples = Float64List(1024 * 2);

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
        // Continuous time across frames from a running sample counter, avoiding
        // the float-precision loss of multiplying by absolute wall-clock time.
        final t = (_sampleIndex + i) / sampleRate;
        double realSum = 0;
        double imagSum = 0;

        for (int f = 0; f < freqs.length; f++) {
          final phase = 2 * math.pi * freqs[f] * t;
          realSum += amps[f] * math.cos(phase);
          imagSum += amps[f] * math.sin(phase);
        }

        // Low noise floor
        double ni = (_rng.nextDouble() - 0.5) * 0.01;
        double nq = (_rng.nextDouble() - 0.5) * 0.01;

        samples[i * 2] = realSum + ni;
        samples[i * 2 + 1] = imagSum + nq;
      }
      _sampleIndex += 1024;
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
