import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/rf/integrated_rf_capture_service.dart';
import 'package:spectral/src/rf/native_sdr_driver.dart';
import 'package:spectral/src/rf/rtl2832u.dart';

/// A driver stand-in that records what the capture service asked for and lets
/// a test push raw bulk-transfer chunks at it.
class FakeSdrDriver implements NativeSdrDriverInterface {
  FakeSdrDriver({this.open = true, this.streamStarts = true});

  bool open;
  bool streamStarts;

  final _samples = StreamController<Uint8List>.broadcast();
  final _states = StreamController<SdrDriverState>.broadcast();

  final List<String> calls = [];
  int? appliedFrequency;
  int? appliedSampleRate;
  int? appliedPpm;
  bool? appliedAgc;
  bool streaming = false;

  void emit(List<int> bytes) => _samples.add(Uint8List.fromList(bytes));

  @override
  bool get isInitialized => open;

  @override
  SdrDriverState get state =>
      open ? SdrDriverState.open : SdrDriverState.noDevice;

  @override
  SdrDeviceInfo? get device => null;

  @override
  String? get lastError => 'fake failure';

  @override
  Stream<SdrDriverState> get stateChanges => _states.stream;

  @override
  Stream<Uint8List> get samples => _samples.stream;

  @override
  Future<List<SdrDeviceInfo>> refreshDevices() async => const [];

  @override
  Future<bool> requestPermission({String? deviceName}) async => true;

  @override
  Future<bool> initialize({
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppm = 0,
    int? tunerGainTenthsDb,
  }) async {
    calls.add('initialize');
    appliedSampleRate = sampleRate;
    appliedFrequency = frequency;
    appliedPpm = ppm;
    return open;
  }

  @override
  Future<void> setFrequency(int hz) async {
    calls.add('setFrequency');
    appliedFrequency = hz;
  }

  @override
  Future<void> setSampleRate(int hz) async {
    calls.add('setSampleRate');
    appliedSampleRate = hz;
  }

  @override
  Future<void> setPpm(int ppm) async {
    calls.add('setPpm');
    appliedPpm = ppm;
  }

  @override
  Future<void> setAgc(bool enabled) async {
    calls.add('setAgc');
    appliedAgc = enabled;
  }

  @override
  Future<void> setTunerGain(int tenthsDb) async => calls.add('setTunerGain');

  @override
  Future<bool> startStream() async {
    calls.add('startStream');
    streaming = streamStarts;
    return streamStarts;
  }

  @override
  Future<void> stopStream() async {
    calls.add('stopStream');
    streaming = false;
  }

  @override
  Future<Map<String, dynamic>?> selfTest() async => null;

  @override
  void dispose() {
    _samples.close();
    _states.close();
  }
}

void main() {
  group('RtlUsbIds', () {
    test('recognizes common RTL-SDR dongles', () {
      expect(RtlUsbIds.isKnownDongle(0x0bda, 0x2838), isTrue);
      expect(RtlUsbIds.isKnownDongle(0x0bda, 0x2832), isTrue);
      expect(RtlUsbIds.isKnownDongle(0x0ccd, 0x00a9), isTrue);
    });

    test('rejects unrelated devices', () {
      // Right vendor, wrong product: a Realtek NIC is not a dongle.
      expect(RtlUsbIds.isKnownDongle(0x0bda, 0x8153), isFalse);
      expect(RtlUsbIds.isKnownDongle(0x1234, 0x5678), isFalse);
    });
  });

  group('RtlTuner', () {
    test('parses the platform channel spelling', () {
      expect(RtlTuner.parse('R820T'), RtlTuner.r820t);
      expect(RtlTuner.parse('R828D'), RtlTuner.r828d);
      expect(RtlTuner.parse('NONE'), RtlTuner.none);
      expect(RtlTuner.parse(null), RtlTuner.none);
      expect(RtlTuner.parse('something-else'), RtlTuner.none);
    });

    test('the R82xx family and the FC0013 are driveable', () {
      expect(RtlTuner.r820t.isSupported, isTrue);
      expect(RtlTuner.r828d.isSupported, isTrue);
      expect(RtlTuner.fc0013.isSupported, isTrue);
    });

    test('tuners without a native driver are reported unsupported', () {
      // FC0012 shares the FC0013's I2C address and is easy to confuse with it,
      // so it must stay explicitly unsupported.
      expect(RtlTuner.fc0012.isSupported, isFalse);
      expect(RtlTuner.e4000.isSupported, isFalse);
      expect(RtlTuner.fc2580.isSupported, isFalse);
      expect(RtlTuner.none.isSupported, isFalse);
    });
  });

  group('sample rate limits', () {
    test('accepts rates the resampler can produce', () {
      expect(isSupportedRtlSampleRate(2048000), isTrue);
      expect(isSupportedRtlSampleRate(250000), isTrue);
    });

    test('rejects rates outside the resampler range', () {
      expect(isSupportedRtlSampleRate(200000), isFalse);
      expect(isSupportedRtlSampleRate(500000), isFalse); // dead band
      expect(isSupportedRtlSampleRate(3300000), isFalse);
    });

    test('clamping always lands on a supported rate', () {
      for (final rate in [0, 100000, 225000, 400000, 800000, 2400000, 5000000]) {
        expect(
          isSupportedRtlSampleRate(clampRtlSampleRate(rate)),
          isTrue,
          reason: 'clamping $rate produced an unsupported rate',
        );
      }
    });

    test('clamping snaps to the nearer edge of the dead band', () {
      expect(clampRtlSampleRate(320000), 300000);
      expect(clampRtlSampleRate(880000), 900001);
    });

    test('leaves supported rates untouched', () {
      expect(clampRtlSampleRate(2048000), 2048000);
    });
  });

  group('SdrDeviceInfo', () {
    test('reads the platform channel payload', () {
      final info = SdrDeviceInfo.fromMap({
        'deviceName': '/dev/bus/usb/001/004',
        'vendorId': 0x0bda,
        'productId': 0x2838,
        'productName': 'RTL2838UHIDIR',
        'hasPermission': true,
        'supported': true,
        'tuner': 'R820T',
      });
      expect(info.deviceName, '/dev/bus/usb/001/004');
      expect(info.hasPermission, isTrue);
      expect(info.tuner, RtlTuner.r820t);
      expect(info.displayName, 'RTL2838UHIDIR');
    });

    test('falls back to the raw IDs when the dongle reports no name', () {
      final info = SdrDeviceInfo.fromMap({
        'vendorId': 0x0bda,
        'productId': 0x2838,
      });
      expect(info.displayName, 'USB 0bda:2838');
    });
  });

  group('IntegratedRfCaptureService', () {
    test('applies tuning settings and starts the stream', () async {
      final driver = FakeSdrDriver();
      final service = IntegratedRfCaptureService(
        centerFrequency: 100e6,
        bandwidth: 2048000,
        ppmCorrection: 12.0,
        driver: driver,
      );
      addTearDown(driver.dispose);
      addTearDown(service.dispose);

      await service.startCapture();

      expect(driver.streaming, isTrue);
      expect(driver.appliedFrequency, 100000000);
      expect(driver.appliedSampleRate, 2048000);
      expect(driver.appliedPpm, 12);
      // Automatic gain is the default, matching the rtl_tcp path.
      expect(driver.appliedAgc, isTrue);
    });

    test('converts unsigned bytes into normalized I/Q', () async {
      final driver = FakeSdrDriver();
      final service = IntegratedRfCaptureService(
        centerFrequency: 100e6,
        bandwidth: 2048000,
        driver: driver,
      );
      addTearDown(driver.dispose);
      addTearDown(service.dispose);
      await service.startCapture();

      final received = <Float64List>[];
      service.dataStream.listen(received.add);

      driver.emit([0, 255, 128, 127]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, hasLength(4));
      expect(received.single[0], closeTo(-1.0, 1e-9));
      expect(received.single[1], closeTo(1.0, 0.01));
    });

    test('carries an odd trailing byte so I/Q pairs never drift', () async {
      final driver = FakeSdrDriver();
      final service = IntegratedRfCaptureService(
        centerFrequency: 100e6,
        bandwidth: 2048000,
        driver: driver,
      );
      addTearDown(driver.dispose);
      addTearDown(service.dispose);
      await service.startCapture();

      final received = <Float64List>[];
      service.dataStream.listen(received.add);

      // Three bytes: two are usable, the third must be held back.
      driver.emit([10, 20, 30]);
      await pumpEventQueue();
      expect(received.single, hasLength(2));

      // The held byte is prepended to the next chunk.
      driver.emit([40]);
      await pumpEventQueue();
      expect(received, hasLength(2));
      expect(received[1], hasLength(2));
      expect(received[1][0], closeTo((30 - 127.5) / 127.5, 1e-9));
      expect(received[1][1], closeTo((40 - 127.5) / 127.5, 1e-9));
    });

    test('surfaces the driver error when the dongle is not ready', () async {
      final driver = FakeSdrDriver(open: false);
      final service = IntegratedRfCaptureService(
        centerFrequency: 100e6,
        bandwidth: 2048000,
        driver: driver,
      );
      addTearDown(driver.dispose);
      addTearDown(service.dispose);

      await expectLater(service.startCapture(), throwsA(isA<StateError>()));
    });

    test('stopCapture releases the stream', () async {
      final driver = FakeSdrDriver();
      final service = IntegratedRfCaptureService(
        centerFrequency: 100e6,
        bandwidth: 2048000,
        driver: driver,
      );
      addTearDown(driver.dispose);
      addTearDown(service.dispose);

      await service.startCapture();
      await service.stopCapture();

      expect(driver.streaming, isFalse);
      expect(driver.calls, contains('stopStream'));
    });
  });
}
