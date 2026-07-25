import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_sdr_driver.dart';
import 'rtl2832u.dart';

/// Native RTL-SDR driver, talking to the Android USB host stack.
///
/// The register-level work (RTL2832U bring-up, R82xx tuner, bulk streaming)
/// lives in Kotlin under `android/app/src/main/kotlin/com/example/spectral/usb/`
/// so it can use `UsbDeviceConnection` directly. This class is the Dart half:
/// it mirrors the driver's state, surfaces hot-plug events, and forwards the
/// sample stream.
///
/// On platforms without a USB host implementation the driver reports
/// [SdrDriverState.unsupported] and every call is a no-op.
class NativeSdrDriverDelegate implements NativeSdrDriverInterface {
  NativeSdrDriverDelegate() {
    if (_platformSupported) {
      _eventSubscription = _events
          .receiveBroadcastStream()
          .listen(_onPlatformEvent, onError: _onPlatformEventError);
      _sampleSubscription = _sampleEvents
          .receiveBroadcastStream()
          .listen(_onSamples, onError: _onPlatformEventError);
      // Enumerate whatever is already attached (the common case when the app
      // was launched by the USB_DEVICE_ATTACHED intent).
      unawaited(refreshDevices());
    } else {
      _state = SdrDriverState.unsupported;
    }
  }

  static const MethodChannel _methods = MethodChannel('spectral/sdr');
  static const EventChannel _events = EventChannel('spectral/sdr/events');
  static const EventChannel _sampleEvents = EventChannel('spectral/sdr/samples');

  /// Only Android implements the native USB path today.
  static bool get _platformSupported => !kIsWeb && Platform.isAndroid;

  final StreamController<SdrDriverState> _stateController =
      StreamController<SdrDriverState>.broadcast();
  final StreamController<Uint8List> _sampleController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<dynamic>? _sampleSubscription;

  SdrDriverState _state = SdrDriverState.noDevice;
  SdrDeviceInfo? _device;
  String? _lastError;
  bool _isOpen = false;

  /// Settings the driver was last opened with, replayed when a dongle is
  /// hot-plugged so re-opening does not need the caller to pass them again.
  int _sampleRate = 2048000;
  int _frequency = 100000000;
  int _ppm = 0;
  int? _tunerGainTenthsDb;

  @override
  bool get isInitialized => _isOpen;

  @override
  SdrDriverState get state => _state;

  @override
  SdrDeviceInfo? get device => _device;

  @override
  String? get lastError => _lastError;

  @override
  Stream<SdrDriverState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get samples => _sampleController.stream;

  void _setState(SdrDriverState next, {String? error}) {
    _lastError = error;
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  // --------------------------------------------------------------- events ---

  void _onPlatformEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    final deviceMap = event['device'];
    final info = deviceMap is Map ? SdrDeviceInfo.fromMap(deviceMap) : null;

    switch (type) {
      case 'attached':
        _device = info;
        // An attach that came through the system dialog already carries
        // permission; otherwise the user still has to grant it.
        _setState(info?.hasPermission == true
            ? SdrDriverState.ready
            : SdrDriverState.needsPermission);
        break;
      case 'detached':
        _isOpen = false;
        _device = null;
        _setState(SdrDriverState.noDevice);
        break;
      case 'permission':
        if (info != null) _device = info;
        _setState(event['granted'] == true
            ? SdrDriverState.ready
            : SdrDriverState.needsPermission);
        break;
      case 'streamError':
        _isOpen = false;
        _setState(SdrDriverState.error, error: 'The sample stream stopped.');
        break;
    }
  }

  void _onPlatformEventError(Object error) {
    debugPrint('NativeSdrDriver: platform event error: $error');
    _setState(SdrDriverState.error, error: error.toString());
  }

  void _onSamples(dynamic data) {
    if (data is Uint8List && !_sampleController.isClosed) {
      _sampleController.add(data);
    }
  }

  // -------------------------------------------------------------- commands ---

  @override
  Future<List<SdrDeviceInfo>> refreshDevices() async {
    if (!_platformSupported) return const [];
    try {
      final result = await _methods.invokeListMethod<dynamic>('listDevices');
      final devices = (result ?? const [])
          .whereType<Map>()
          .map(SdrDeviceInfo.fromMap)
          .toList(growable: false);

      if (devices.isEmpty) {
        _device = null;
        _isOpen = false;
        _setState(SdrDriverState.noDevice);
      } else {
        final current = devices.first;
        _device = current;
        // Don't downgrade an already-open device just because we re-enumerated.
        if (!_isOpen) {
          _setState(current.hasPermission
              ? SdrDriverState.ready
              : SdrDriverState.needsPermission);
        }
      }
      return devices;
    } on PlatformException catch (e) {
      _setState(SdrDriverState.error, error: e.message);
      return const [];
    }
  }

  @override
  Future<bool> requestPermission({String? deviceName}) async {
    if (!_platformSupported) return false;
    try {
      final granted = await _methods.invokeMethod<bool>(
            'requestPermission',
            {'deviceName': deviceName ?? _device?.deviceName},
          ) ??
          false;
      _setState(granted ? SdrDriverState.ready : SdrDriverState.needsPermission);
      return granted;
    } on PlatformException catch (e) {
      _setState(SdrDriverState.error, error: e.message);
      return false;
    }
  }

  @override
  Future<bool> initialize({
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppm = 0,
    int? tunerGainTenthsDb,
  }) async {
    if (!_platformSupported) {
      _setState(SdrDriverState.unsupported);
      return false;
    }

    _sampleRate = clampRtlSampleRate(sampleRate);
    _frequency = frequency;
    _ppm = ppm;
    _tunerGainTenthsDb = tunerGainTenthsDb;

    // Make sure we know about the device (and hold permission) first.
    if (_device == null) await refreshDevices();
    final target = _device;
    if (target == null) {
      _setState(SdrDriverState.noDevice);
      return false;
    }
    if (!target.hasPermission && !await requestPermission(deviceName: target.deviceName)) {
      return false;
    }

    try {
      final result = await _methods.invokeMapMethod<String, dynamic>('open', {
        'deviceName': target.deviceName,
        'sampleRate': _sampleRate,
        'frequency': _frequency,
        'ppm': _ppm,
        'tunerGainTenthsDb': _tunerGainTenthsDb,
      });
      if (result == null) {
        _isOpen = false;
        _setState(
          SdrDriverState.error,
          error: 'Could not open the dongle. It may be claimed by another app.',
        );
        return false;
      }

      final opened = SdrDeviceInfo.fromMap(result);
      _device = opened;
      if (!opened.tuner.isSupported) {
        _isOpen = false;
        _setState(
          SdrDriverState.error,
          error: 'Unsupported tuner (${opened.tuner.name}). '
              'This driver supports R820T/R820T2/R828D dongles.',
        );
        return false;
      }

      _isOpen = true;
      _setState(SdrDriverState.open);
      return true;
    } on PlatformException catch (e) {
      _isOpen = false;
      _setState(SdrDriverState.error, error: e.message);
      return false;
    }
  }

  @override
  Future<void> setFrequency(int hz) async {
    _frequency = hz;
    if (!_isOpen) return;
    await _invokeVoid('setFrequency', {'hz': hz});
  }

  @override
  Future<void> setSampleRate(int hz) async {
    _sampleRate = clampRtlSampleRate(hz);
    if (!_isOpen) return;
    await _invokeVoid('setSampleRate', {'hz': _sampleRate});
  }

  @override
  Future<void> setPpm(int ppm) async {
    _ppm = ppm;
    if (!_isOpen) return;
    await _invokeVoid('setPpm', {'ppm': ppm});
  }

  @override
  Future<void> setAgc(bool enabled) async {
    _tunerGainTenthsDb = enabled ? null : _tunerGainTenthsDb;
    if (!_isOpen) return;
    await _invokeVoid('setAgc', {'enabled': enabled});
  }

  @override
  Future<void> setTunerGain(int tenthsDb) async {
    _tunerGainTenthsDb = tenthsDb;
    if (!_isOpen) return;
    await _invokeVoid('setTunerGain', {'tenthsDb': tenthsDb});
  }

  @override
  Future<bool> startStream() async {
    if (!_isOpen) return false;
    try {
      return await _methods.invokeMethod<bool>('startStream') ?? false;
    } on PlatformException catch (e) {
      _setState(SdrDriverState.error, error: e.message);
      return false;
    }
  }

  @override
  Future<void> stopStream() async {
    if (!_isOpen) return;
    await _invokeVoid('stopStream', null);
  }

  @override
  Future<Map<String, dynamic>?> selfTest() async {
    if (!_isOpen) return null;
    try {
      return await _methods.invokeMapMethod<String, dynamic>('selfTest');
    } on PlatformException catch (e) {
      debugPrint('NativeSdrDriver: selfTest failed: ${e.message}');
      return null;
    }
  }

  Future<void> _invokeVoid(String method, Map<String, dynamic>? args) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('NativeSdrDriver: $method failed: ${e.message}');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _sampleSubscription?.cancel();
    if (_platformSupported && _isOpen) {
      unawaited(_invokeVoid('close', null));
    }
    _isOpen = false;
    _stateController.close();
    _sampleController.close();
  }
}
