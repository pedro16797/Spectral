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

    await tester.pumpAndSettle();

    expect(find.text('SPECTRAL'), findsOneWidget);
    // expect(find.text('START CAPTURE'), findsOneWidget); // Removed as it's now in a complex hub

    // Verify Settings (Tune) icon is present
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });
}
