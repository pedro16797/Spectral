import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/utils/frequency_scale.dart';

void main() {
  group('FrequencyScale', () {
    test('is the identity when skew is 1.0', () {
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(FrequencyScale.toData(t, 1.0), t);
        expect(FrequencyScale.toScreen(t, 1.0), t);
      }
    });

    test('preserves endpoints for any skew', () {
      for (final skew in [0.2, 0.5, 1.0, 2.0, 3.0]) {
        expect(FrequencyScale.toData(0.0, skew), 0.0);
        expect(FrequencyScale.toData(1.0, skew), closeTo(1.0, 1e-12));
        expect(FrequencyScale.toScreen(0.0, skew), 0.0);
        expect(FrequencyScale.toScreen(1.0, skew), closeTo(1.0, 1e-12));
      }
    });

    test('toScreen is the inverse of toData', () {
      for (final skew in [0.2, 0.5, 2.0, 3.0]) {
        for (final t in [0.1, 0.3, 0.5, 0.8, 0.95]) {
          final roundTrip = FrequencyScale.toScreen(FrequencyScale.toData(t, skew), skew);
          expect(roundTrip, closeTo(t, 1e-9));
        }
      }
    });

    test('is monotonically increasing', () {
      for (final skew in [0.5, 2.0]) {
        double prev = -1;
        for (int i = 0; i <= 10; i++) {
          final v = FrequencyScale.toData(i / 10, skew);
          expect(v, greaterThanOrEqualTo(prev));
          prev = v;
        }
      }
    });
  });
}
