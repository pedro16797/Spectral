import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/settings_model.dart';

void main() {
  group('AppSettings.fromMap coercion', () {
    test('coerces numbers stored as doubles back to int fields', () {
      final s = AppSettings.fromMap({'rtlTcpPort': 1234.0, 'fftWindowSize': 2048.0});
      expect(s.rtlTcpPort, 1234);
      expect(s.fftWindowSize, 2048);
    });

    test('coerces numeric strings', () {
      final s = AppSettings.fromMap({
        'centerFrequency': '101.5',
        'fftWindowSize': '512',
        'rtlTcpPort': '8080',
        'peakHoldEnabled': 'true',
      });
      expect(s.centerFrequency, 101.5);
      expect(s.fftWindowSize, 512);
      expect(s.rtlTcpPort, 8080);
      expect(s.peakHoldEnabled, true);
    });

    test('coerces ints into double fields and numbers into bools', () {
      final s = AppSettings.fromMap({
        'centerFrequency': 100,
        'frequencySkew': 2,
        'peakHoldEnabled': 1,
        'showSnr': 0,
      });
      expect(s.centerFrequency, 100.0);
      expect(s.frequencySkew, 2.0);
      expect(s.peakHoldEnabled, true);
      expect(s.showSnr, false);
    });

    test('falls back to defaults for un-coercible values', () {
      final s = AppSettings.fromMap({
        'rtlTcpPort': 'not-a-number',
        'centerFrequency': true,
        'fftWindowSize': null,
        'rtlTcpHost': 99,
      });
      expect(s.rtlTcpPort, 1234);
      expect(s.centerFrequency, 100.0);
      expect(s.fftWindowSize, 1024);
      expect(s.rtlTcpHost, '127.0.0.1');
    });

    test('a fully malformed map yields defaults without throwing', () {
      late AppSettings s;
      expect(
        () => s = AppSettings.fromMap({
          'theme': 123,
          'fftWindowSize': [1, 2, 3],
          'demodulationMode': 42,
          'audioOutputEnabled': 'maybe',
        }),
        returnsNormally,
      );
      expect(s.theme, AppTheme.frost);
      expect(s.fftWindowSize, 1024);
      expect(s.demodulationMode, DemodulationMode.none);
      expect(s.audioOutputEnabled, false); // 'maybe' is not 'true'
    });
  });

  test('toMap -> fromMap round-trips every field', () {
    const original = AppSettings(
      theme: AppTheme.rainbow,
      signalSource: SignalSourceType.rf,
      rfSource: RfSourceType.rtlTcp,
      rtlTcpHost: '192.168.1.5',
      rtlTcpPort: 5555,
      centerFrequency: 433.92,
      rfBandwidth: 1.5,
      fftWindowSize: 4096,
      fftWindowType: FftWindowType.blackman,
      language: 'es',
      frequencySkew: 2.5,
      peakHoldEnabled: true,
      fftAveragingMode: FftAveragingMode.linear,
      fftAveragingCount: 20,
      ppmCorrection: -3.5,
      showHarmonics: true,
      showSnr: true,
      demodulationMode: DemodulationMode.fm,
      audioOutputEnabled: true,
    );

    final restored = AppSettings.fromMap(original.toMap());
    expect(restored.toMap(), original.toMap());
  });
}
