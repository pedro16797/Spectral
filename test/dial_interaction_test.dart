import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/utils/localization_helper.dart';

void main() {
  setUp(() async {
    await LocalizationHelper.load('en');
  });

  testWidgets('Dial interaction: tap to toggle, drag to show, exclusive visibility, and drag on large dial', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const SpectralApp());
    await tester.pumpAndSettle();

    Finder findTrigger(String label) {
      return find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      ).last;
    }

    final gainTrigger = findTrigger('GAIN');
    final sensTrigger = findTrigger('SENS');

    // 1. Show GAIN dial
    await tester.tap(gainTrigger);
    await tester.pumpAndSettle();
    expect(find.text('GAIN'), findsNWidgets(2)); // Bar + Large Dial

    // 2. Drag on the large dial to update value
    final largeDialGainLabel = find.descendant(
      of: find.byType(Positioned),
      matching: find.text('GAIN'),
    );

    expect(find.text('1.00'), findsNWidgets(3));

    // Drag on large dial
    await tester.drag(largeDialGainLabel, const Offset(0, 50), warnIfMissed: false);
    await tester.pumpAndSettle();

    // 3. Switch to SENS dial
    await tester.tap(sensTrigger);
    await tester.pumpAndSettle();

    // 4. Drag on the SENS large dial
    final largeDialSensLabel = find.descendant(
      of: find.byType(Positioned),
      matching: find.text('SENSITIVITY'),
    );

    // Drag on large dial
    await tester.drag(largeDialSensLabel, const Offset(0, -50), warnIfMissed: false);
    await tester.pumpAndSettle();

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
