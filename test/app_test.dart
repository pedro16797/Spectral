import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/utils/localization_helper.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

// A simple mock for rootBundle
class MockAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'resources/locales/en.json') {
      return json.encode({
        "app": {"name": "Spectral"},
        "common": {
          "start_capture": "Start Capture",
          "stop_capture": "Stop Capture"
        }
      });
    }
    throw FlutterError('Asset not found');
  }

  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  testWidgets('Spectral app loads and shows title', (WidgetTester tester) async {
    // Let's manually initialize it for the test environment.
    await LocalizationHelper.load('en', MockAssetBundle());

    // Provide the mock asset bundle to the widget tree
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: MockAssetBundle(),
        child: const SpectralApp(),
      ),
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
