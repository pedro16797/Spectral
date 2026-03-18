import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/utils/localization_helper.dart';

void main() {
  setUp(() async {
    await LocalizationHelper.load('en');
  });

  testWidgets('Dial interaction: tap to toggle, drag to show, exclusive visibility', (WidgetTester tester) async {
    // Set a larger screen size to ensure widgets are on screen
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const SpectralApp());
    await tester.pumpAndSettle();

    // Use find.byWidgetPredicate to find the trigger in the interaction bar
    Finder findTrigger(String label) {
      return find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      ).last;
    }

    final gainTrigger = findTrigger('GAIN');
    final sensTrigger = findTrigger('SENS');

    expect(gainTrigger, findsOneWidget);
    expect(sensTrigger, findsOneWidget);

    // Initial state: no large dials visible
    expect(find.text('GAIN'), findsOneWidget); // Only in the bar
    expect(find.text('SENSITIVITY'), findsNothing);

    // 1. Tap GAIN to show
    await tester.tap(gainTrigger);
    await tester.pump();
    expect(find.text('GAIN'), findsNWidgets(2)); // Bar + Large Dial
    expect(find.text('SENSITIVITY'), findsNothing);

    // 2. Tap GAIN again to hide
    await tester.tap(gainTrigger);
    await tester.pump();
    expect(find.text('GAIN'), findsOneWidget);

    // 3. Drag GAIN to show and stay visible
    await tester.drag(gainTrigger, const Offset(0, -50));
    await tester.pump();
    expect(find.text('GAIN'), findsNWidgets(2));

    // 4. Tap SENS to show SENS and hide GAIN
    await tester.tap(sensTrigger);
    await tester.pump();
    expect(find.text('SENSITIVITY'), findsOneWidget); // In Large Dial
    expect(find.text('GAIN'), findsOneWidget); // Only in the bar

    // 5. Verify layout: Value is above Label in the trigger
    // The trigger Column's children are updated.
    final gainColumn = find.descendant(
      of: gainTrigger,
      matching: find.byType(Column),
    ).first;
    final columnWidget = tester.widget<Column>(gainColumn);

    expect(columnWidget.children.first, isA<Container>()); // Value
    expect(columnWidget.children.last, isA<Text>()); // Label
    final labelText = columnWidget.children.last as Text;
    expect(labelText.data, 'GAIN');

    // Reset view size
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
