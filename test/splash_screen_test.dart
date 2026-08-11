import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/ui/splash_screen.dart';
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
  testWidgets('splash overlay plays over the home page and dismisses itself',
      (WidgetTester tester) async {
    await LocalizationHelper.load('en', FileAssetBundle());

    await tester.pumpWidget(
      const SpectralApp(initialSettings: AppSettings()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-animation the overlay is painting above a fully built home page.
    expect(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.text('SPECTRAL ANALYSIS'), findsOneWidget);

    // The overlay never blocks input to the app underneath.
    expect(find.byType(IgnorePointer), findsWidgets);

    // After its finite run (hold + fade) it collapses entirely and stops
    // scheduling frames, so pumpAndSettle-based tests keep working.
    await tester.pump(
        SplashOverlay.holdDuration + SplashOverlay.fadeDuration);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('splash overlay reports completion', (WidgetTester tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const SizedBox.expand(),
            SplashOverlay(onFinished: () => finished = true),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(finished, isFalse);
    await tester.pump(
        SplashOverlay.holdDuration + SplashOverlay.fadeDuration);
    await tester.pump();
    expect(finished, isTrue);
  });
}
