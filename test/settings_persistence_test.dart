import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loadSettings returns default settings when nothing is saved', () async {
      final settings = await SettingsService.loadSettings();
      expect(settings.theme, AppTheme.frost);
      expect(settings.fftWindowSize, 1024);
      expect(settings.fftWindowType, FftWindowType.hanning);
      expect(settings.language, 'en');
      // Sprint 4.2 Defaults
      expect(settings.peakHoldEnabled, false);
      expect(settings.fftAveragingMode, FftAveragingMode.none);
      expect(settings.fftAveragingCount, 5);
      expect(settings.ppmCorrection, 0.0);
      expect(settings.showHarmonics, false);
    });

    test('saveSettings and loadSettings persists data', () async {
      const customSettings = AppSettings(
        theme: AppTheme.magma,
        fftWindowSize: 2048,
        fftWindowType: FftWindowType.blackman,
        language: 'en',
        peakHoldEnabled: true,
        fftAveragingMode: FftAveragingMode.exponential,
        fftAveragingCount: 10,
        ppmCorrection: 15.5,
        showHarmonics: true,
      );

      await SettingsService.saveSettings(customSettings);
      final loadedSettings = await SettingsService.loadSettings();

      expect(loadedSettings.theme, customSettings.theme);
      expect(loadedSettings.fftWindowSize, customSettings.fftWindowSize);
      expect(loadedSettings.fftWindowType, customSettings.fftWindowType);
      expect(loadedSettings.language, customSettings.language);
      expect(loadedSettings.peakHoldEnabled, true);
      expect(loadedSettings.fftAveragingMode, FftAveragingMode.exponential);
      expect(loadedSettings.fftAveragingCount, 10);
      expect(loadedSettings.ppmCorrection, 15.5);
      expect(loadedSettings.showHarmonics, true);
    });

    test('fromMap handles missing fields with defaults', () {
      final map = {'theme': 'emerald'};
      final settings = AppSettings.fromMap(map);
      expect(settings.theme, AppTheme.emerald);
      expect(settings.fftWindowSize, 1024); // Default
      expect(settings.peakHoldEnabled, false); // Default
    });
  });
}
