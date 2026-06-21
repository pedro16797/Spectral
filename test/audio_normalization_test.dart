import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
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
    test('decimates by an integer factor', () {
      final input = Float64List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final output = AudioUtils.decimate(input, 2);
      expect(output, [0, 2, 4, 6]);
    });

    test('reused buffer never leaks stale tail samples for a smaller chunk', () {
      // Prime a reusable buffer with a longer input.
      final long = Float64List.fromList(List<double>.filled(8, 9.0));
      var buffer = AudioUtils.decimate(long, 2); // length 4
      expect(buffer.length, 4);

      // Decimate a shorter input reusing the oversized buffer.
      final short = Float64List.fromList([1, 2, 3, 4]);
      final output = AudioUtils.decimate(short, 2, target: buffer);

      expect(output.length, 2);
      expect(output, [1, 3]); // no stale 9.0 values in the tail
    });

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
}
