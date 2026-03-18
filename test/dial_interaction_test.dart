import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/utils/localization_helper.dart';

void main() {
  setUp(() async {
    await LocalizationHelper.load('en');
  });

  testWidgets('Dial interaction: tap to toggle, drag to show, exclusive visibility, and drag on large dial', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const SpectralApp());
    await tester.pumpAndSettle();

    final gainTriggerFinder = find.byKey(const Key('trigger_GAIN'));
    final sensTriggerFinder = find.byKey(const Key('trigger_SENS'));
    final leftDialFinder = find.byKey(const Key('large_dial_left'));
    final rightDialFinder = find.byKey(const Key('large_dial_right'));

    // 1. Initially no dials visible
    expect(leftDialFinder, findsNothing);
    expect(rightDialFinder, findsNothing);

    // 2. Drag GAIN trigger: Dial should be visible during drag
    final gesture = await tester.startGesture(tester.getCenter(gainTriggerFinder));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(leftDialFinder, findsOneWidget);

    // 3. Release drag: Dial should disappear
    await gesture.up();
    await tester.pump();
    expect(leftDialFinder, findsNothing);

    // 4. Tap GAIN trigger: Dial should become persistent
    await tester.tap(gainTriggerFinder);
    await tester.pump();
    expect(leftDialFinder, findsOneWidget);

    // 5. Tap SENS trigger: GAIN should disappear, SENS should become persistent
    await tester.tap(sensTriggerFinder);
    await tester.pump();
    expect(leftDialFinder, findsNothing);
    expect(rightDialFinder, findsOneWidget);

    // 6. Tap SENS again: SENS should disappear
    await tester.tap(sensTriggerFinder);
    await tester.pump();
    expect(rightDialFinder, findsNothing);

    // 7. Test direct drag on large dial
    await tester.tap(gainTriggerFinder);
    await tester.pumpAndSettle();
    expect(leftDialFinder, findsOneWidget);

    // Initial value is 1.00
    expect(find.text('1.00'), findsNWidgets(3));

    // Drag from x=5
    final dragGesture = await tester.startGesture(const Offset(5, 800));
    await dragGesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await dragGesture.up();
    await tester.pumpAndSettle();

    // Check if value updated.
    expect(find.text('2.00'), findsNWidgets(2));
  });
}
