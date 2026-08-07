import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/signal_source.dart';
import 'native_sdr_driver.dart';
import 'rtl2832u.dart';

/// Capture service for the integrated (native USB) SDR path.
///
/// Streams real interleaved I/Q from an RTL-SDR dongle claimed directly by the
/// app over USB — no rtl_tcp bridge in between. The register-level driver runs
/// on the platform side; this service owns the Dart-side lifecycle: it applies
/// the tuning settings, starts the bulk stream, and converts the RTL2832U's
/// unsigned-8-bit samples into the normalized doubles the pipeline expects.
class IntegratedRfCaptureService implements SignalSource {
  IntegratedRfCaptureService({
    required this.centerFrequency,
    required this.bandwidth,
    this.ppmCorrection = 0.0,
    this.tunerGainTenthsDb,
    NativeSdrDriverInterface? driver,
  })  : _driver = driver ?? NativeSdrDriver(),
        _sampleRate = clampRtlSampleRate(bandwidth.toInt());

  final double centerFrequency; // Hz
  final double bandwidth; // Hz
  final double ppmCorrection; // PPM

  /// Fixed tuner gain in tenths of a dB. Null (the default) runs the dongle's
  /// automatic gain, which is the configuration that works out of the box.
  final int? tunerGainTenthsDb;

  final NativeSdrDriverInterface _driver;
  final int _sampleRate;

  final _dataController = StreamController<Float64List>.broadcast();
  StreamSubscription<Uint8List>? _sampleSubscription;
  bool _isCapturing = false;

  /// Holds a trailing odd byte between chunks so I/Q pairs never drift out of
  /// phase if a transfer ever splits mid-sample.
  int? _pendingByte;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => _sampleRate;

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async => _driver.isInitialized;

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    if (!_driver.isInitialized) {
      // Try to bring the dongle up on demand — the user may have plugged it in
      // (or granted permission) after this source was created.
      final opened = await _driver.initialize(
        sampleRate: _sampleRate,
        frequency: centerFrequency.toInt(),
        ppm: ppmCorrection.round(),
        tunerGainTenthsDb: tunerGainTenthsDb,
      );
      if (!opened) {
        throw StateError(
          _driver.lastError ?? 'The RTL-SDR dongle is not ready.',
        );
      }
    } else {
      // Already open: re-apply this source's settings.
      await _driver.setSampleRate(_sampleRate);
      await _driver.setPpm(ppmCorrection.round());
      await _driver.setFrequency(centerFrequency.toInt());
      if (tunerGainTenthsDb == null) {
        await _driver.setAgc(true);
      } else {
        await _driver.setTunerGain(tunerGainTenthsDb!);
      }
    }

    _pendingByte = null;
    _sampleSubscription = _driver.samples.listen(
      _onSamples,
      onError: (Object e) => debugPrint('IntegratedRfCaptureService: $e'),
    );

    if (!await _driver.startStream()) {
      await _sampleSubscription?.cancel();
      _sampleSubscription = null;
      throw StateError('Could not start the RTL-SDR sample stream.');
    }
    _isCapturing = true;
  }

  void _onSamples(Uint8List chunk) {
    if (_dataController.isClosed || chunk.isEmpty) return;

    final pending = _pendingByte;
    Uint8List data;
    if (pending == null) {
      data = chunk;
    } else {
      data = Uint8List(chunk.length + 1)
        ..[0] = pending
        ..setRange(1, chunk.length + 1, chunk);
      _pendingByte = null;
    }

    // Emit whole I/Q pairs only; carry any odd trailing byte to the next chunk.
    final usable = data.length - (data.length % 2);
    if (usable < data.length) _pendingByte = data[data.length - 1];
    if (usable == 0) return;

    _dataController.add(rtlIqBytesToDouble(data, 0, usable));
  }

  @override
  Future<void> stopCapture() async {
    if (!_isCapturing) return;
    _isCapturing = false;
    await _sampleSubscription?.cancel();
    _sampleSubscription = null;
    await _driver.stopStream();
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
