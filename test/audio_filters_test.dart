import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/audio_filters.dart';

void main() {
  group('DcBlocker', () {
    test('passes the first sample on reset', () {
      expect(DcBlocker().processSample(0.7), 0.7);
    });

    test('drives a constant (DC) signal toward zero', () {
      final dc = DcBlocker();
      double y = 0;
      for (int i = 0; i < 10000; i++) {
        y = dc.processSample(1.0);
      }
      expect(y, closeTo(0.0, 1e-3));
    });

    test('reset restores initial behavior', () {
      final dc = DcBlocker();
      for (int i = 0; i < 100; i++) {
        dc.processSample(1.0);
      }
      dc.reset();
      expect(dc.processSample(0.5), 0.5);
    });
  });

  group('Deemphasis', () {
    test('passes DC: a constant input converges to that constant', () {
      final de = Deemphasis(sampleRate: 44100);
      double y = 0;
      for (int i = 0; i < 5000; i++) {
        y = de.processSample(2.0);
      }
      expect(y, closeTo(2.0, 1e-3));
    });

    test('low-passes: the first output of a step is between 0 and the step', () {
      final first = Deemphasis(sampleRate: 44100).processSample(1.0);
      expect(first, greaterThan(0.0));
      expect(first, lessThan(1.0));
    });

    test('a lower sample rate (larger alpha) responds faster to a step', () {
      final fast = Deemphasis(sampleRate: 8000).processSample(1.0);
      final slow = Deemphasis(sampleRate: 2000000).processSample(1.0);
      expect(fast, greaterThan(slow));
    });
  });
}
