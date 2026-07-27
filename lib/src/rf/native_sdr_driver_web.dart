import 'dart:async';
import 'dart:typed_data';

import 'native_sdr_driver.dart';

/// Web build of the native driver.
///
/// Browsers cannot claim a USB dongle through this app, so the driver reports
/// [SdrDriverState.unsupported] and the UI steers the user to the rtl_tcp
/// source instead of offering a setup flow that cannot succeed.
class NativeSdrDriverDelegate implements NativeSdrDriverInterface {
  final StreamController<SdrDriverState> _stateController =
      StreamController<SdrDriverState>.broadcast();
  final StreamController<Uint8List> _sampleController =
      StreamController<Uint8List>.broadcast();

  @override
  bool get isInitialized => false;

  @override
  SdrDriverState get state => SdrDriverState.unsupported;

  @override
  SdrDeviceInfo? get device => null;

  @override
  String? get lastError => 'USB SDR access is not available on the web build.';

  @override
  Stream<SdrDriverState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get samples => _sampleController.stream;

  @override
  Future<List<SdrDeviceInfo>> refreshDevices() async => const [];

  @override
  Future<bool> requestPermission({String? deviceName}) async => false;

  @override
  Future<bool> initialize({
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppm = 0,
    int? tunerGainTenthsDb,
  }) async =>
      false;

  @override
  Future<void> setFrequency(int hz) async {}

  @override
  Future<void> setSampleRate(int hz) async {}

  @override
  Future<void> setPpm(int ppm) async {}

  @override
  Future<void> setAgc(bool enabled) async {}

  @override
  Future<void> setTunerGain(int tenthsDb) async {}

  @override
  Future<bool> startStream() async => false;

  @override
  Future<void> stopStream() async {}

  @override
  Future<Map<String, dynamic>?> selfTest() async => null;

  @override
  void dispose() {
    _stateController.close();
    _sampleController.close();
  }
}
