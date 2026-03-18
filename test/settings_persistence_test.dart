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
      expect(settings.theme, AppTheme.liquidBlue);
      expect(settings.fftWindowSize, 1024);
      expect(settings.fftWindowType, FftWindowType.hanning);
      expect(settings.language, 'en');
    });

    test('saveSettings and loadSettings persists data', () async {
      const customSettings = AppSettings(
        theme: AppTheme.inferno,
        fftWindowSize: 2048,
        fftWindowType: FftWindowType.blackman,
        language: 'en',
      );

      await SettingsService.saveSettings(customSettings);
      final loadedSettings = await SettingsService.loadSettings();

      expect(loadedSettings.theme, customSettings.theme);
      expect(loadedSettings.fftWindowSize, customSettings.fftWindowSize);
      expect(loadedSettings.fftWindowType, customSettings.fftWindowType);
      expect(loadedSettings.language, customSettings.language);
    });

    test('fromMap handles missing fields with defaults', () {
      final map = {'theme': 'emerald'};
      final settings = AppSettings.fromMap(map);
      expect(settings.theme, AppTheme.emerald);
      expect(settings.fftWindowSize, 1024); // Default
    });
  });
}
