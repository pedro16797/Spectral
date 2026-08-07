import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:spectral/src/core/audio_filters.dart';
import 'package:spectral/src/utils/audio_utils.dart';

void main() {
  group('Audio Data Normalization', () {
    test('converts 16-bit PCM to normalized double', () {
      final data = Uint8List.fromList([0, 0]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples.length, 1);
      expect(samples[0], 0.0);
    });

    test('converts max 16-bit PCM to 1.0 (approx)', () {
      final data = Uint8List.fromList([0xFF, 0x7F]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples[0], closeTo(32767 / 32768.0, 0.0001));
    });

    test('converts min 16-bit PCM to -1.0', () {
      final data = Uint8List.fromList([0x00, 0x80]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples[0], -1.0);
    });

    test('reused buffer never leaks stale tail samples for a smaller chunk', () {
      // First, a large chunk populates the reusable buffer.
      final large = Uint8List(8); // 4 samples
      for (int i = 0; i < large.length; i++) {
        large[i] = 0xFF; // non-zero so stale data would be detectable
      }
      var buffer = AudioUtils.convertPcmToDouble(large);
      expect(buffer.length, 4);

      // Then a smaller chunk reuses the same (oversized) buffer.
      final small = Uint8List.fromList([0x00, 0x00]); // 1 sample, value 0.0
      final result = AudioUtils.convertPcmToDouble(small, target: buffer);

      // The result must be exactly one sample long with no leaked tail data.
      expect(result.length, 1);
      expect(result[0], 0.0);
    });
  });

  group('Audio Decimation', () {
    test('decimateAveraged averages each group of factor samples', () {
      final input = Float64List.fromList([1, 1, 1, 1, 5, 5, 5, 5]);
      expect(AudioUtils.decimateAveraged(input, 4), [1.0, 5.0]);
      expect(AudioUtils.decimateAveraged(Float64List.fromList([0, 2, 4, 6]), 2), [1.0, 5.0]);
    });

    test('decimateAveraged returns input unchanged for factor <= 1', () {
      final input = Float64List.fromList([1, 2, 3]);
      expect(identical(AudioUtils.decimateAveraged(input, 1), input), true);
    });

    test('decimateAveraged reuses an exact-length target', () {
      final out = AudioUtils.decimateAveraged(
        Float64List.fromList([2, 4, 6, 8]),
        2,
        target: Float64List(2),
      );
      expect(out, [3.0, 7.0]);
    });
  });

  group('LinearResampler', () {
    test('is the identity at equal rates', () {
      final r = LinearResampler()
        ..configure(inputRate: 44100, outputRate: 44100);
      final input = Float64List.fromList([0.1, 0.2, 0.3, 0.4]);
      expect(r.process(input), input);
    });

    test('produces the right output count for a fractional ratio', () {
      final r = LinearResampler()
        ..configure(inputRate: 48000, outputRate: 44100);
      // 48000 input samples must resample to ~44100 outputs, not 48000: the
      // old integer-only path pushed them through unchanged, playing ~9% fast.
      int produced = 0;
      for (int chunk = 0; chunk < 48; chunk++) {
        produced += r.process(Float64List(1000)).length;
      }
      expect(produced, closeTo(44100, 2));
    });

    test('interpolates linearly within a chunk', () {
      final r = LinearResampler()..configure(inputRate: 2, outputRate: 4);
      final out = r.process(Float64List.fromList([0.0, 1.0]));
      expect(out, [0.0, 0.5, 1.0]);
    });

    test('stays continuous across chunk boundaries', () {
      final r = LinearResampler()..configure(inputRate: 3, outputRate: 2);
      // A steadily increasing ramp split into chunks must stay monotonic —
      // any discontinuity means the carried phase/previous sample is wrong.
      final outputs = <double>[];
      for (int chunk = 0; chunk < 10; chunk++) {
        final input = Float64List.fromList(
            List.generate(5, (i) => (chunk * 5 + i).toDouble()));
        outputs.addAll(r.process(input));
      }
      for (int i = 1; i < outputs.length; i++) {
        expect(outputs[i] - outputs[i - 1], closeTo(1.5, 1e-9),
            reason: 'discontinuity at output $i');
      }
    });
  });
}
