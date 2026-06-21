import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/ui/edge_dial.dart';

void main() {
  // The drag helper emits a haptic, which routes through a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dialValueFromDrag', () {
    test('dragging up (negative dy) increases the value', () {
      expect(dialValueFromDrag(1.0, -100), closeTo(2.0, 1e-9));
    });

    test('dragging down (positive dy) decreases the value', () {
      expect(dialValueFromDrag(3.0, 50), closeTo(2.5, 1e-9));
    });

    test('clamps to the lower bound', () {
      expect(dialValueFromDrag(0.5, 100), kDialMin);
    });

    test('clamps to the upper bound', () {
      expect(dialValueFromDrag(4.8, -100), kDialMax);
    });

    test('is a no-op for zero delta', () {
      expect(dialValueFromDrag(2.34, 0), closeTo(2.34, 1e-9));
    });
  });
}
