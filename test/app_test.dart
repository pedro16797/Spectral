import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/utils/localization_helper.dart';

/// Serves the real locale files from disk, so the test never drifts from the
/// strings the app actually ships. Reads synchronously because widget tests
/// run in a fake-async zone where real IO futures never complete.
class FileAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(File(key).readAsStringSync());

  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  testWidgets('Spectral app loads and shows title', (WidgetTester tester) async {
    await LocalizationHelper.load('en', FileAssetBundle());

    await tester.pumpWidget(
      const SpectralApp(initialSettings: AppSettings()),
    );

    // pumpAndSettle times out due to infinite rotation animation.
    // Use pump instead for non-animating verification.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SPECTRAL ANALYSIS'), findsOneWidget);

    // Verify GAIN and SENS controls are present
    expect(find.text('GAIN'), findsOneWidget);
    expect(find.text('SENS'), findsOneWidget);

    // Verify Frequency Focus control is present
    expect(find.text('FOCUS'), findsOneWidget);
  });
}
