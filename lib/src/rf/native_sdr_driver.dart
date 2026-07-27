import 'dart:async';
import 'dart:typed_data';

import 'rtl2832u.dart';

/// Where the integrated (native USB) driver currently stands.
///
/// The UI renders these directly, so each value is a distinct thing the user
/// can act on rather than a generic "not ready".
enum SdrDriverState {
  /// This platform has no native USB path at all (web, desktop).
  unsupported,

  /// USB host works, but no RTL-SDR dongle is attached.
  noDevice,

  /// A dongle is attached but the app has not been granted USB access.
  needsPermission,

  /// A dongle is attached and permitted, but not opened yet.
  ready,

  /// The dongle is open and its tuner is configured.
  open,

  /// A dongle is attached but the driver cannot drive it (unsupported tuner,
  /// or bring-up failed). [NativeSdrDriverInterface.lastError] says why.
  error,
}

/// A dongle reported by the platform's USB stack.
class SdrDeviceInfo {
  const SdrDeviceInfo({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    this.productName,
    this.manufacturerName,
    this.hasPermission = false,
    this.supported = false,
    this.tuner = RtlTuner.none,
  });

  /// Opaque platform handle (Android's `/dev/bus/usb/...` path).
  final String deviceName;
  final int vendorId;
  final int productId;
  final String? productName;
  final String? manufacturerName;
  final bool hasPermission;

  /// Whether the VID/PID is a dongle the driver knows.
  final bool supported;
  final RtlTuner tuner;

  /// A human-readable label, falling back to the raw IDs when the device
  /// reports no product string (common on cheap dongles).
  String get displayName {
    final name = productName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'USB ${vendorId.toRadixString(16).padLeft(4, '0')}:'
        '${productId.toRadixString(16).padLeft(4, '0')}';
  }

  static SdrDeviceInfo fromMap(Map<dynamic, dynamic> map) => SdrDeviceInfo(
        deviceName: map['deviceName']?.toString() ?? '',
        vendorId: (map['vendorId'] as num?)?.toInt() ?? 0,
        productId: (map['productId'] as num?)?.toInt() ?? 0,
        productName: map['productName']?.toString(),
        manufacturerName: map['manufacturerName']?.toString(),
        hasPermission: map['hasPermission'] == true,
        supported: map['supported'] == true,
        tuner: RtlTuner.parse(map['tuner']?.toString()),
      );
}

/// The platform-specific half of the integrated SDR path.
abstract class NativeSdrDriverInterface {
  /// True once the device is open and streaming can start.
  bool get isInitialized;

  SdrDriverState get state;

  /// The dongle currently attached (or opened), if any.
  SdrDeviceInfo? get device;

  /// Why the driver is in [SdrDriverState.error], if it is.
  String? get lastError;

  /// Fires whenever [state] changes — including on hot-plug, so the app can
  /// react to a dongle appearing without the user re-entering settings.
  Stream<SdrDriverState> get stateChanges;

  /// Raw interleaved unsigned-8-bit I/Q straight off the bulk endpoint.
  Stream<Uint8List> get samples;

  /// Re-enumerates attached dongles and updates [state].
  Future<List<SdrDeviceInfo>> refreshDevices();

  /// Prompts for USB access. Returns true if access is (already) granted.
  Future<bool> requestPermission({String? deviceName});

  /// Opens the dongle and runs the RTL2832U + tuner bring-up.
  Future<bool> initialize({
    int sampleRate,
    int frequency,
    int ppm,
    int? tunerGainTenthsDb,
  });

  Future<void> setFrequency(int hz);
  Future<void> setSampleRate(int hz);
  Future<void> setPpm(int ppm);

  /// Enables the tuner + RTL2832 AGC (the "just works" default).
  Future<void> setAgc(bool enabled);

  /// Sets a fixed tuner gain, in tenths of a dB.
  Future<void> setTunerGain(int tenthsDb);

  Future<bool> startStream();
  Future<void> stopStream();

  /// Reads back a few registers for diagnosing a bring-up on real hardware.
  Future<Map<String, dynamic>?> selfTest();

  void dispose();
}

/// Process-wide handle to the integrated driver.
///
/// The concrete implementation is injected at startup via [setDelegate] (see
/// `main.dart`), which keeps the platform-specific imports out of the widget
/// tree and lets tests substitute a fake.
class NativeSdrDriver implements NativeSdrDriverInterface {
  static final NativeSdrDriver _instance = NativeSdrDriver._internal();
  factory NativeSdrDriver() => _instance;
  NativeSdrDriver._internal();

  NativeSdrDriverInterface? _delegate;

  final StreamController<SdrDriverState> _stateController =
      StreamController<SdrDriverState>.broadcast();
  final StreamController<Uint8List> _sampleController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<SdrDriverState>? _stateSub;
  StreamSubscription<Uint8List>? _sampleSub;

  /// Installs the platform implementation, re-pointing the facade's streams at
  /// it. Safe to call more than once (tests swap delegates).
  void setDelegate(NativeSdrDriverInterface delegate) {
    _stateSub?.cancel();
    _sampleSub?.cancel();
    _delegate = delegate;
    _stateSub = delegate.stateChanges.listen(
      (s) {
        if (!_stateController.isClosed) _stateController.add(s);
      },
      onError: (Object _) {},
    );
    _sampleSub = delegate.samples.listen(
      (chunk) {
        if (!_sampleController.isClosed) _sampleController.add(chunk);
      },
      onError: (Object _) {},
    );
  }

  @override
  bool get isInitialized => _delegate?.isInitialized ?? false;

  @override
  SdrDriverState get state => _delegate?.state ?? SdrDriverState.unsupported;

  @override
  SdrDeviceInfo? get device => _delegate?.device;

  @override
  String? get lastError => _delegate?.lastError;

  @override
  Stream<SdrDriverState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get samples => _sampleController.stream;

  @override
  Future<List<SdrDeviceInfo>> refreshDevices() async =>
      await _delegate?.refreshDevices() ?? const [];

  @override
  Future<bool> requestPermission({String? deviceName}) async =>
      await _delegate?.requestPermission(deviceName: deviceName) ?? false;

  @override
  Future<bool> initialize({
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppm = 0,
    int? tunerGainTenthsDb,
  }) async =>
      await _delegate?.initialize(
        sampleRate: sampleRate,
        frequency: frequency,
        ppm: ppm,
        tunerGainTenthsDb: tunerGainTenthsDb,
      ) ??
      false;

  @override
  Future<void> setFrequency(int hz) async => await _delegate?.setFrequency(hz);

  @override
  Future<void> setSampleRate(int hz) async => await _delegate?.setSampleRate(hz);

  @override
  Future<void> setPpm(int ppm) async => await _delegate?.setPpm(ppm);

  @override
  Future<void> setAgc(bool enabled) async => await _delegate?.setAgc(enabled);

  @override
  Future<void> setTunerGain(int tenthsDb) async =>
      await _delegate?.setTunerGain(tenthsDb);

  @override
  Future<bool> startStream() async => await _delegate?.startStream() ?? false;

  @override
  Future<void> stopStream() async => await _delegate?.stopStream();

  @override
  Future<Map<String, dynamic>?> selfTest() async => await _delegate?.selfTest();

  @override
  void dispose() {
    _stateSub?.cancel();
    _stateSub = null;
    _sampleSub?.cancel();
    _sampleSub = null;
    _delegate?.dispose();
  }
}
