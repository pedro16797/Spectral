import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/ui/radio_dial_focus_slider.dart';

void main() {
  testWidgets('RadioDialFocusSlider updates range on drag', (WidgetTester tester) async {
    RangeValues currentValues = const RangeValues(1000, 5000);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 100,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return RadioDialFocusSlider(
                    values: currentValues,
                    min: 0,
                    max: 10000,
                    onChanged: (values) {
                      setState(() {
                        currentValues = values;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Initial state
    expect(currentValues.start, 1000);
    expect(currentValues.end, 5000);

    final center = tester.getCenter(find.byType(RadioDialFocusSlider));
    final topLeft = tester.getTopLeft(find.byType(RadioDialFocusSlider));

    debugPrint('TopLeft: $topLeft, Center: $center');

    // Drag center (move)
    // 1000-5000 range. Center is 3000 (0.3 of 10000). 0.3 * 400 = 120.
    final startDragAt = Offset(topLeft.dx + 120, center.dy);
    final gestureMove = await tester.startGesture(startDragAt);
    await gestureMove.moveBy(const Offset(100, 0)); // +100px = +2500Hz
    await gestureMove.up();
    await tester.pumpAndSettle();

    expect(currentValues.start, closeTo(3500, 1));
    expect(currentValues.end, closeTo(7500, 1));

    // Resize start (left handle)
    // New start is 3500 (0.35 of 10000). 0.35 * 400 = 140.
    final startHandleAt = Offset(topLeft.dx + 140, center.dy);
    final gestureResize = await tester.startGesture(startHandleAt);
    await gestureResize.moveBy(const Offset(-40, 0)); // -40px = -1000Hz
    await gestureResize.up();
    await tester.pumpAndSettle();

    expect(currentValues.start, closeTo(2500, 1));
    expect(currentValues.end, closeTo(7500, 1));
  });
}
